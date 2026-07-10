//! Hosted vision-LLM extractor over any OpenAI-compatible `/chat/completions`
//! endpoint: OpenRouter or Mistral (dev/prod), or a self-hosted vLLM/Ollama.
//! Set VLM_URL, VLM_MODEL, and VLM_API_KEY (bearer). No key → keyless (local).
use base64::Engine;
use serde::Deserialize;

use crate::enums::{ItemType, PriceType};
use crate::errors::AppError;

use super::{dec2, parse_purchase_at, ExtractedLineItem, ExtractedReceipt, ReceiptExtractor};

pub struct HostedVlmExtractor {
    client: reqwest::Client,
    url: String,
    model: String,
    api_key: Option<String>,
    engine: String,
}

impl HostedVlmExtractor {
    pub fn new(url: &str, model: &str, api_key: Option<String>) -> Self {
        Self {
            client: reqwest::Client::new(),
            url: url.trim_end_matches('/').to_string(),
            model: model.to_string(),
            api_key,
            engine: model.to_string(),
        }
    }
}

const PROMPT: &str = r#"You are a receipt-parsing engine. Extract the receipt in the image into JSON with EXACTLY this shape (no extra keys, no prose, no markdown):
{
  "store": { "name": string|null, "org_no": string|null, "address": string|null, "city": string|null, "postal_code": string|null, "country_code": string|null },
  "purchase_at": string|null,          // the printed local date/time, e.g. "2026-01-15T13:30" or "2026-01-15 13:30"
  "currency": string,                  // e.g. "NOK"
  "receipt_number": string|null,       // bong/receipt number if printed
  "payment": { "method": string|null },// "card" | "cash" | "vipps" | ... (NEVER card numbers)
  "subtotal": number|null,
  "total": number|null,
  "mva_lines": [ { "rate": number, "base": number, "vat": number } ],  // the VAT/MVA breakdown table
  "line_items": [
    {
      "description": string,
      "product_code": string|null,     // EAN/barcode if printed
      "quantity": number|null,
      "unit": string|null,             // "stk","kg","l"
      "shelf_unit_price": number|null, // price before discount, if shown
      "unit_price": number|null,       // net price actually paid per unit
      "discount_amount": number|null,
      "line_total": number|null,       // net amount paid for the line
      "item_type": "product"|"deposit"|"discount"|"fee"|"rounding"|"unknown",
      "price_type": "shelf"|"promo"|"member"|"coupon"|"net_only",
      "mva_rate": number|null          // e.g. 25, 15, 12
    }
  ]
}
Norwegian receipts: comma is the decimal separator (49,90 = 49.90); "pant" lines are deposits (item_type "deposit"); "Rabatt"/"Trumf" lines are discounts (item_type "discount"). Output only the JSON object."#;

#[derive(Deserialize, Default)]
struct VlmStore {
    name: Option<String>,
    org_no: Option<String>,
}

#[derive(Deserialize, Default)]
struct VlmPayment {
    method: Option<String>,
}

#[derive(Deserialize)]
struct VlmMva {
    #[allow(dead_code)]
    rate: Option<f64>,
    #[allow(dead_code)]
    base: Option<f64>,
    vat: Option<f64>,
}

#[derive(Deserialize)]
struct VlmOut {
    #[serde(default)]
    store: VlmStore,
    purchase_at: Option<String>,
    currency: Option<String>,
    receipt_number: Option<String>,
    #[serde(default)]
    payment: VlmPayment,
    subtotal: Option<f64>,
    total: Option<f64>,
    #[serde(default)]
    mva_lines: Vec<VlmMva>,
    #[serde(default)]
    line_items: Vec<VlmItem>,
}

#[derive(Deserialize)]
struct VlmItem {
    description: Option<String>,
    product_code: Option<String>,
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

/// Extract the outermost JSON object from a model response that may wrap it in
/// markdown fences (```json … ```) or prose.
fn extract_json_object(s: &str) -> &str {
    match (s.find('{'), s.rfind('}')) {
        (Some(a), Some(b)) if b >= a => &s[a..=b],
        _ => s.trim(),
    }
}

fn empty_pdf_result(engine: &str) -> ExtractedReceipt {
    ExtractedReceipt {
        store_name_raw: None,
        org_no: None,
        receipt_number: None,
        payment_method: None,
        purchase_at: None,
        currency: "NOK".to_string(),
        subtotal: None,
        mva_total: None,
        total: None,
        line_items: vec![],
        confidence: Some(0.0),
        engine: engine.to_string(),
        raw: serde_json::json!({ "note": "pdf extraction not yet supported by hosted VLM" }),
    }
}

#[async_trait::async_trait]
impl ReceiptExtractor for HostedVlmExtractor {
    async fn extract(&self, bytes: &[u8], mime: &str) -> Result<ExtractedReceipt, AppError> {
        // PDFs can't be sent to a vision model directly; text-layer parsing is deferred.
        if mime == "application/pdf" {
            return Ok(empty_pdf_result(&self.engine));
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

        // Send with a few retries on transient rate-limits (429) / 5xx.
        let endpoint = format!("{}/chat/completions", self.url);
        let mut resp = None;
        let mut last_err = String::new();
        for attempt in 1..=3u32 {
            let mut req = self.client.post(&endpoint).json(&body);
            if let Some(key) = &self.api_key {
                // Bearer auth for OpenRouter/Mistral; referer/title are OpenRouter
                // attribution headers, ignored elsewhere.
                req = req
                    .bearer_auth(key)
                    .header("HTTP-Referer", "https://summprices.app")
                    .header("X-Title", "SummPrices");
            }
            match req.send().await {
                Ok(r) if r.status().is_success() => {
                    resp = Some(r);
                    break;
                }
                Ok(r) => {
                    let status = r.status();
                    let retryable = status.as_u16() == 429 || status.is_server_error();
                    let text = r.text().await.unwrap_or_default();
                    last_err = format!("VLM returned {status}: {text}");
                    if retryable && attempt < 3 {
                        tokio::time::sleep(std::time::Duration::from_millis(800 * attempt as u64))
                            .await;
                        continue;
                    }
                    return Err(AppError::Internal(last_err));
                }
                Err(e) => {
                    last_err = format!("VLM request failed: {e}");
                    if attempt < 3 {
                        tokio::time::sleep(std::time::Duration::from_millis(800 * attempt as u64))
                            .await;
                        continue;
                    }
                    return Err(AppError::Internal(last_err));
                }
            }
        }
        let resp = resp.ok_or_else(|| AppError::Internal(last_err))?;

        let val: serde_json::Value = resp
            .json()
            .await
            .map_err(|e| AppError::Internal(format!("VLM parse failed: {e}")))?;
        let content = val["choices"][0]["message"]["content"]
            .as_str()
            .ok_or_else(|| AppError::Internal("VLM response missing content".to_string()))?;
        // Tolerate markdown fences / prose around the JSON object.
        let json_str = extract_json_object(content);
        let out: VlmOut = serde_json::from_str(json_str)
            .map_err(|e| AppError::Internal(format!("VLM JSON invalid: {e}")))?;
        // Store the model's receipt JSON (store address, mva_lines, payment, …) for audit/reprocess.
        let raw: serde_json::Value = serde_json::from_str(json_str).unwrap_or(serde_json::Value::Null);

        let mva_total = if out.mva_lines.is_empty() {
            None
        } else {
            let sum: f64 = out.mva_lines.iter().filter_map(|m| m.vat).sum();
            dec2(Some(sum))
        };

        let line_items = out
            .line_items
            .into_iter()
            .filter_map(|it| {
                let desc = it.description?;
                Some(ExtractedLineItem {
                    description_clean: Some(desc.clone()),
                    description_raw: desc,
                    product_code: it.product_code,
                    item_type: item_type_of(&it.item_type),
                    quantity: super::dec3(it.quantity),
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
            store_name_raw: out.store.name,
            org_no: out.store.org_no,
            receipt_number: out.receipt_number,
            payment_method: out.payment.method,
            purchase_at: parse_purchase_at(out.purchase_at.as_deref()),
            currency: out.currency.unwrap_or_else(|| "NOK".to_string()),
            subtotal: dec2(out.subtotal),
            mva_total,
            total: dec2(out.total),
            line_items,
            confidence: None,
            engine: self.engine.clone(),
            raw,
        })
    }

    fn engine_id(&self) -> &str {
        &self.engine
    }
}
