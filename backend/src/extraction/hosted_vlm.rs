//! Hosted Qwen3-VL extractor over an OpenAI-compatible endpoint (vLLM / Ollama).
use base64::Engine;
use serde::Deserialize;

use crate::enums::{ItemType, PriceType};
use crate::errors::AppError;

use super::{dec2, dec3, parse_purchase_at, ExtractedLineItem, ExtractedReceipt, ReceiptExtractor};

pub struct HostedVlmExtractor {
    client: reqwest::Client,
    url: String,
    model: String,
    engine: String,
}

impl HostedVlmExtractor {
    pub fn new(url: &str, model: &str) -> Self {
        Self {
            client: reqwest::Client::new(),
            url: url.trim_end_matches('/').to_string(),
            model: model.to_string(),
            engine: model.to_string(),
        }
    }
}

const PROMPT: &str = r#"You are a receipt-parsing engine. Extract the receipt in the image into JSON with EXACTLY this shape (no extra keys, no prose):
{
  "store_name": string|null,
  "org_no": string|null,
  "purchase_datetime": string|null,
  "currency": string,
  "subtotal": number|null,
  "mva_total": number|null,
  "total": number|null,
  "line_items": [
    {
      "description": string,
      "quantity": number|null,
      "unit": string|null,
      "shelf_unit_price": number|null,
      "unit_price": number|null,
      "discount_amount": number|null,
      "line_total": number|null,
      "item_type": "product"|"deposit"|"discount"|"fee"|"rounding"|"unknown",
      "price_type": "shelf"|"promo"|"member"|"coupon"|"net_only",
      "mva_rate": number|null
    }
  ]
}
Norwegian receipts: comma is the decimal separator (49,90 = 49.90); "pant" lines are deposits (item_type "deposit"); "Rabatt"/"Trumf" lines are discounts (item_type "discount"). purchase_datetime is the printed local date/time. Output only the JSON object."#;

#[derive(Deserialize)]
struct VlmOut {
    store_name: Option<String>,
    org_no: Option<String>,
    purchase_datetime: Option<String>,
    currency: Option<String>,
    subtotal: Option<f64>,
    mva_total: Option<f64>,
    total: Option<f64>,
    #[serde(default)]
    line_items: Vec<VlmItem>,
}

#[derive(Deserialize)]
struct VlmItem {
    description: Option<String>,
    quantity: Option<f64>,
    unit: Option<String>,
    shelf_unit_price: Option<f64>,
    unit_price: Option<f64>,
    discount_amount: Option<f64>,
    line_total: Option<f64>,
    item_type: Option<String>,
    price_type: Option<String>,
    mva_rate: Option<f64>,
}

fn item_type_of(s: &Option<String>) -> ItemType {
    match s.as_deref() {
        Some("deposit") => ItemType::Deposit,
        Some("discount") => ItemType::Discount,
        Some("fee") => ItemType::Fee,
        Some("rounding") => ItemType::Rounding,
        Some("unknown") => ItemType::Unknown,
        _ => ItemType::Product,
    }
}

fn price_type_of(s: &Option<String>) -> PriceType {
    match s.as_deref() {
        Some("shelf") => PriceType::Shelf,
        Some("promo") => PriceType::Promo,
        Some("member") => PriceType::Member,
        Some("coupon") => PriceType::Coupon,
        _ => PriceType::NetOnly,
    }
}

#[async_trait::async_trait]
impl ReceiptExtractor for HostedVlmExtractor {
    async fn extract(&self, bytes: &[u8], mime: &str) -> Result<ExtractedReceipt, AppError> {
        // PDFs can't be sent to a vision model directly; text-layer parsing is deferred.
        // Return an empty result so the pipeline flags it needs_review.
        if mime == "application/pdf" {
            return Ok(ExtractedReceipt {
                store_name_raw: None,
                org_no: None,
                purchase_at: None,
                currency: "NOK".to_string(),
                subtotal: None,
                mva_total: None,
                total: None,
                line_items: vec![],
                confidence: Some(0.0),
                engine: self.engine.clone(),
                raw: serde_json::json!({ "note": "pdf extraction not yet supported by hosted VLM" }),
            });
        }

        let data_uri = format!(
            "data:{};base64,{}",
            mime,
            base64::engine::general_purpose::STANDARD.encode(bytes)
        );
        let body = serde_json::json!({
            "model": self.model,
            "temperature": 0,
            "response_format": { "type": "json_object" },
            "messages": [
                { "role": "system", "content": "You output only valid JSON." },
                { "role": "user", "content": [
                    { "type": "text", "text": PROMPT },
                    { "type": "image_url", "image_url": { "url": data_uri } }
                ]}
            ]
        });

        let resp = self
            .client
            .post(format!("{}/chat/completions", self.url))
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Internal(format!("VLM request failed: {e}")))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!("VLM returned {status}: {text}")));
        }

        let val: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("VLM parse failed: {e}")))?;
        let content = val["choices"][0]["message"]["content"]
            .as_str()
            .ok_or_else(|| AppError::Internal("VLM response missing content".to_string()))?;
        let out: VlmOut = serde_json::from_str(content)
            .map_err(|e| AppError::Internal(format!("VLM JSON invalid: {e}")))?;

        let line_items = out
            .line_items
            .into_iter()
            .filter_map(|it| {
                let desc = it.description?;
                Some(ExtractedLineItem {
                    description_clean: Some(desc.clone()),
                    description_raw: desc,
                    item_type: item_type_of(&it.item_type),
                    quantity: dec3(it.quantity),
                    unit: it.unit,
                    shelf_unit_price: dec2(it.shelf_unit_price),
                    unit_price: dec2(it.unit_price),
                    discount_amount: dec2(it.discount_amount),
                    line_total: dec2(it.line_total),
                    price_type: price_type_of(&it.price_type),
                    mva_rate: dec2(it.mva_rate),
                })
            })
            .collect();

        Ok(ExtractedReceipt {
            store_name_raw: out.store_name,
            org_no: out.org_no,
            purchase_at: parse_purchase_at(out.purchase_datetime.as_deref()),
            currency: out.currency.unwrap_or_else(|| "NOK".to_string()),
            subtotal: dec2(out.subtotal),
            mva_total: dec2(out.mva_total),
            total: dec2(out.total),
            line_items,
            confidence: None,
            engine: self.engine.clone(),
            raw: val,
        })
    }

    fn engine_id(&self) -> &str {
        &self.engine
    }
}
