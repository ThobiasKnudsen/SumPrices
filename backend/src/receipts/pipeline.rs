//! Shared persistence seam used by BOTH the HTTP upload handler and the dev ingest harness.
use std::sync::Arc;

use sqlx::PgPool;
use uuid::Uuid;

use crate::enums::{ExtractionStatus, ReceiptSource};
use crate::errors::AppError;
use crate::extraction::{ExtractedReceipt, ReceiptExtractor};

pub const DEV_USER_ID: Uuid = Uuid::from_u128(0xDE);
pub const DEV_USER_EMAIL: &str = "dev@summprices.local";
const SCAN_REWARD: i32 = 10;

pub async fn ensure_dev_user(pool: &PgPool) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO users (id, email, password_hash) VALUES ($1, $2, $3)
         ON CONFLICT (id) DO NOTHING",
    )
    .bind(DEV_USER_ID)
    .bind(DEV_USER_EMAIL)
    .bind("dev-user-no-login")
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn insert_pending_receipt(
    pool: &PgPool,
    user_id: Uuid,
    source: ReceiptSource,
    mime: Option<&str>,
    file_hash: Option<&str>,
    parser_commit: &str,
) -> Result<Uuid, AppError> {
    let row: (Uuid,) = sqlx::query_as(
        "INSERT INTO receipts (user_id, source, original_mime, source_file_hash, parser_commit)
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
    )
    .bind(user_id)
    .bind(source)
    .bind(mime)
    .bind(file_hash)
    .bind(parser_commit)
    .fetch_one(pool)
    .await?;
    Ok(row.0)
}

pub async fn set_asset_key(pool: &PgPool, receipt_id: Uuid, key: &str) -> Result<(), AppError> {
    sqlx::query("UPDATE receipts SET original_asset_key = $2 WHERE id = $1")
        .bind(receipt_id)
        .bind(key)
        .execute(pool)
        .await?;
    Ok(())
}

fn compute_needs_review(ex: &ExtractedReceipt) -> bool {
    ex.line_items.is_empty() || ex.confidence.is_some_and(|c| c < 0.5)
}

/// Persist an extraction result. Reparse-idempotent: deletes existing line items first,
/// and the scan reward is guarded by a unique index so a reparse never double-credits.
pub async fn persist_extraction(
    pool: &PgPool,
    receipt_id: Uuid,
    user_id: Uuid,
    ex: &ExtractedReceipt,
) -> Result<(), AppError> {
    let needs_review = compute_needs_review(ex);
    let status = if needs_review {
        ExtractionStatus::NeedsReview
    } else {
        ExtractionStatus::Done
    };

    sqlx::query(
        "UPDATE receipts SET
            store_name_raw = $2,
            purchase_at = $3,
            currency = $4,
            subtotal = $5,
            mva_total = $6,
            total = $7,
            raw_extraction = $8,
            extraction_engine = $9,
            extraction_conf = $10,
            extraction_status = $11,
            needs_review = $12,
            receipt_number = $13,
            updated_at = now()
         WHERE id = $1",
    )
    .bind(receipt_id)
    .bind(&ex.store_name_raw)
    .bind(ex.purchase_at)
    .bind(&ex.currency)
    .bind(ex.subtotal)
    .bind(ex.mva_total)
    .bind(ex.total)
    .bind(&ex.raw)
    .bind(&ex.engine)
    .bind(ex.confidence)
    .bind(status)
    .bind(needs_review)
    .bind(&ex.receipt_number)
    .execute(pool)
    .await?;

    sqlx::query("DELETE FROM transactions WHERE receipt_id = $1")
        .bind(receipt_id)
        .execute(pool)
        .await?;

    for (i, li) in ex.line_items.iter().enumerate() {
        sqlx::query(
            "INSERT INTO transactions
                (receipt_id, user_id, occurred_at, line_no, description_raw, description_clean,
                 product_code, item_type, quantity, unit, shelf_unit_price, unit_price,
                 discount_amount, line_total, price_type, mva_rate)
             VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16)",
        )
        .bind(receipt_id)
        .bind(user_id)
        .bind(ex.purchase_at)
        .bind(i as i32 + 1)
        .bind(&li.description_raw)
        .bind(&li.description_clean)
        .bind(&li.product_code)
        .bind(li.item_type)
        .bind(li.quantity)
        .bind(&li.unit)
        .bind(li.shelf_unit_price)
        .bind(li.unit_price)
        .bind(li.discount_amount)
        .bind(li.line_total)
        .bind(li.price_type)
        .bind(li.mva_rate)
        .execute(pool)
        .await?;
    }

    award_scan_credit(pool, user_id, receipt_id).await?;
    Ok(())
}

async fn award_scan_credit(pool: &PgPool, user_id: Uuid, receipt_id: Uuid) -> Result<(), AppError> {
    let mut tx = pool.begin().await?;
    let inserted: Option<(i64,)> = sqlx::query_as(
        "INSERT INTO credit_ledger (user_id, delta, reason, ref_type, ref_id, balance_after)
         SELECT $1, $2, 'scan_reward', 'receipt', $3, u.credit_balance + $2
         FROM users u WHERE u.id = $1
         ON CONFLICT (user_id, ref_id) WHERE reason = 'scan_reward' DO NOTHING
         RETURNING id",
    )
    .bind(user_id)
    .bind(SCAN_REWARD)
    .bind(receipt_id.to_string())
    .fetch_optional(&mut *tx)
    .await?;

    if inserted.is_some() {
        sqlx::query("UPDATE users SET credit_balance = credit_balance + $2 WHERE id = $1")
            .bind(user_id)
            .bind(SCAN_REWARD)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    Ok(())
}

async fn mark_failed(pool: &PgPool, receipt_id: Uuid, err: &str) {
    let _ = sqlx::query(
        "UPDATE receipts SET extraction_status = 'failed', extraction_error = $2,
             extraction_attempts = extraction_attempts + 1, updated_at = now() WHERE id = $1",
    )
    .bind(receipt_id)
    .bind(err)
    .execute(pool)
    .await;
}

/// Orchestrate extraction for one receipt (off the request path). Marks processing,
/// runs the extractor, persists, or records failure.
pub async fn run_extraction(
    pool: &PgPool,
    extractor: &Arc<dyn ReceiptExtractor>,
    receipt_id: Uuid,
    user_id: Uuid,
    bytes: &[u8],
    mime: &str,
) {
    let _ = sqlx::query("UPDATE receipts SET extraction_status = 'processing' WHERE id = $1")
        .bind(receipt_id)
        .execute(pool)
        .await;

    match extractor.extract(bytes, mime).await {
        Ok(ex) => {
            if let Err(e) = persist_extraction(pool, receipt_id, user_id, &ex).await {
                mark_failed(pool, receipt_id, &e.to_string()).await;
            }
        }
        Err(e) => mark_failed(pool, receipt_id, &e.to_string()).await,
    }
}
