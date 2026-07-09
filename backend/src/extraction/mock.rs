//! Deterministic extractor for tests / CI / no-GPU dev. Returns a fixed Norwegian receipt.
use chrono::{TimeZone, Utc};
use rust_decimal::Decimal;

use crate::enums::{ItemType, PriceType};
use crate::errors::AppError;

use super::{ExtractedLineItem, ExtractedReceipt, ReceiptExtractor};

pub struct MockExtractor {
    engine: String,
}

impl MockExtractor {
    pub fn new() -> Self {
        Self {
            engine: "mock@v1".to_string(),
        }
    }
}

fn product(desc: &str, unit_price: Decimal) -> ExtractedLineItem {
    ExtractedLineItem {
        description_raw: desc.to_string(),
        description_clean: Some(desc.to_string()),
        item_type: ItemType::Product,
        quantity: Some(Decimal::ONE),
        unit: Some("stk".to_string()),
        shelf_unit_price: None,
        unit_price: Some(unit_price),
        discount_amount: None,
        line_total: Some(unit_price),
        price_type: PriceType::NetOnly,
        mva_rate: Some(Decimal::new(1500, 2)), // 15.00 %
    }
}

#[async_trait::async_trait]
impl ReceiptExtractor for MockExtractor {
    async fn extract(&self, _bytes: &[u8], _mime: &str) -> Result<ExtractedReceipt, AppError> {
        let milk = Decimal::new(2490, 2); // 24.90
        let bread = Decimal::new(3990, 2); // 39.90
        let pant = Decimal::new(300, 2); // 3.00
        let total = milk + bread + pant; // 67.80

        let line_items = vec![
            product("MELK LETT 1.5L", milk),
            product("BROD GROVT", bread),
            ExtractedLineItem {
                description_raw: "PANT".to_string(),
                description_clean: Some("Pant".to_string()),
                item_type: ItemType::Deposit,
                quantity: Some(Decimal::ONE),
                unit: None,
                shelf_unit_price: None,
                unit_price: Some(pant),
                discount_amount: None,
                line_total: Some(pant),
                price_type: PriceType::NetOnly,
                mva_rate: None,
            },
        ];

        Ok(ExtractedReceipt {
            store_name_raw: Some("KIWI Storgata".to_string()),
            org_no: Some("NO123456789MVA".to_string()),
            purchase_at: Utc.with_ymd_and_hms(2026, 1, 15, 13, 30, 0).single(),
            currency: "NOK".to_string(),
            subtotal: Some(total),
            mva_total: None,
            total: Some(total),
            line_items,
            confidence: Some(1.0),
            engine: self.engine.clone(),
            raw: serde_json::json!({ "mock": true }),
        })
    }

    fn engine_id(&self) -> &str {
        &self.engine
    }
}
