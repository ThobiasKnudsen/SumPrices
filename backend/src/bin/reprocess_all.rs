//! Re-extract stored receipts straight from the database + object storage (not the dev
//! folder) — so it rescans receipts that were uploaded through the app. Optionally scope to
//! one account and/or override the model. Runs sequentially through the shared pipeline
//! (same code path as the HTTP rescan), so it's safe against the concurrent-persist race.
//!
//! Usage (from backend/):
//!   cargo run --bin reprocess_all -- <model> [user_email]
//!   e.g. cargo run --bin reprocess_all -- google/gemini-2.5-pro thobknu@gmail.com
use uuid::Uuid;

use kvitteringsapp_backend::config::Config;
use kvitteringsapp_backend::storage::s3::Storage;
use kvitteringsapp_backend::{db, extraction, receipts::pipeline};

#[tokio::main]
async fn main() {
    dotenvy::dotenv().ok();

    let model = std::env::args().nth(1).filter(|m| !m.trim().is_empty());
    let user_email = std::env::args().nth(2).filter(|m| !m.trim().is_empty());

    let config = Config::from_env();
    let pool = db::create_pool(&config.database_url).await;
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations");
    let storage = Storage::new(&config);

    let extractor = match model.as_deref() {
        Some(m) => extraction::build_hosted_model(&config, m),
        None => extraction::build_from_env(&config),
    };

    let rows: Vec<(Uuid, Uuid, String, Option<String>, String)> = sqlx::query_as(
        "SELECT r.id, r.user_id, r.original_asset_key, r.original_mime, u.email
         FROM receipts r JOIN users u ON u.id = r.user_id
         WHERE r.original_asset_key IS NOT NULL
           AND ($1::text IS NULL OR u.email = $1)
         ORDER BY r.created_at",
    )
    .bind(&user_email)
    .fetch_all(&pool)
    .await
    .expect("query receipts");

    println!(
        "Reprocessing {} receipt(s){} with {} …\n",
        rows.len(),
        user_email
            .as_deref()
            .map(|e| format!(" for {e}"))
            .unwrap_or_default(),
        model.as_deref().unwrap_or("<config default model>"),
    );

    let total = rows.len();
    for (idx, (id, user_id, key, mime, email)) in rows.iter().enumerate() {
        let mime = mime.clone().unwrap_or_else(|| "image/jpeg".to_string());
        match storage.get(key).await {
            Ok(bytes) => {
                pipeline::run_extraction(&pool, &extractor, *id, *user_id, &bytes, &mime).await;
                let summary: Option<(
                    Option<String>,
                    String,
                    Option<String>,
                    String,
                    bool,
                    Option<String>,
                    i64,
                )> = sqlx::query_as(
                    "SELECT store_name_raw, currency, total::text, extraction_status::text,
                            needs_review, review_reason,
                            (SELECT count(*) FROM transactions t WHERE t.receipt_id = $1)
                     FROM receipts WHERE id = $1",
                )
                .bind(id)
                .fetch_optional(&pool)
                .await
                .ok()
                .flatten();

                if let Some((store, cur, total_s, status, needs, reason, items)) = summary {
                    let store: String =
                        store.unwrap_or_else(|| "—".into()).chars().take(26).collect();
                    let total_s = total_s.unwrap_or_else(|| "—".into());
                    println!(
                        "  [{}/{total}] {email:<20} {store:<26} {items:>3} items  {total_s:>9} {cur}  [{status}]{}",
                        idx + 1,
                        if needs { " ⚠" } else { "" },
                    );
                    if let Some(reason) = reason {
                        println!("        ↳ {reason}");
                    }
                } else {
                    println!("  [{}/{total}] {email} (done)", idx + 1);
                }
            }
            Err(e) => println!("  [{}/{total}] {email} — storage get failed: {e}", idx + 1),
        }
    }

    println!("\nDone.");
}
