use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Receipt {
    pub id: Uuid,
    pub user_id: Uuid,
    pub store_name: Option<String>,
    pub purchase_date: Option<NaiveDate>,
    pub purchase_time: Option<NaiveTime>,
    pub total: Option<Decimal>,
    pub subtotal: Option<Decimal>,
    pub currency: String,
    pub image_key: String,
    pub ocr_confidence: Option<f32>,
    pub ocr_status: String,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct ReceiptSummary {
    pub id: Uuid,
    pub store_name: Option<String>,
    pub purchase_date: Option<NaiveDate>,
    pub total: Option<Decimal>,
    pub currency: String,
    pub ocr_status: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct Item {
    pub id: Uuid,
    pub receipt_id: Uuid,
    pub description: String,
    pub quantity: Option<f32>,
    pub unit_price: Option<Decimal>,
    pub line_total: Option<Decimal>,
    pub product_code: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ReceiptWithItems {
    #[serde(flatten)]
    pub receipt: Receipt,
    pub items: Vec<Item>,
    pub image_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct ReceiptListResponse {
    pub receipts: Vec<ReceiptSummary>,
    pub total_count: i64,
}

#[derive(Debug, Deserialize)]
pub struct ReceiptListQuery {
    pub page: Option<i64>,
    pub per_page: Option<i64>,
    pub store: Option<String>,
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}

#[derive(Debug, Deserialize)]
pub struct UpdateReceiptRequest {
    pub store_name: Option<String>,
    pub purchase_date: Option<NaiveDate>,
    pub total: Option<Decimal>,
}

#[derive(Debug, Serialize)]
pub struct OcrStatusResponse {
    pub ocr_status: String,
    pub ocr_confidence: Option<f32>,
}
