use std::env;

#[derive(Clone)]
pub struct Config {
    pub database_url: String,
    pub jwt_secret: String,
    pub s3_endpoint: String,
    pub s3_bucket: String,
    pub s3_access_key: String,
    pub s3_secret_key: String,
    pub s3_region: String,
    // Extraction
    pub extractor: String, // "mock" | "hosted"
    pub vlm_url: String,   // OpenAI-compatible endpoint (OpenRouter / Mistral / vLLM / Ollama)
    pub vlm_model: String,
    pub vlm_api_key: Option<String>, // bearer key for hosted APIs (OpenRouter/Mistral); None for local
    pub dev_receipts_dir: String,
}

impl Config {
    pub fn from_env() -> Self {
        Self {
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgres://kvittering:localdev@localhost:5432/kvitteringsapp".to_string()),
            jwt_secret: env::var("JWT_SECRET").expect("JWT_SECRET must be set"),
            s3_endpoint: env::var("S3_ENDPOINT").unwrap_or_else(|_| "http://localhost:9000".to_string()),
            s3_bucket: env::var("S3_BUCKET").unwrap_or_else(|_| "receipts".to_string()),
            s3_access_key: env::var("S3_ACCESS_KEY").unwrap_or_else(|_| "minioadmin".to_string()),
            s3_secret_key: env::var("S3_SECRET_KEY").unwrap_or_else(|_| "minioadmin".to_string()),
            s3_region: env::var("S3_REGION").unwrap_or_else(|_| "us-east-1".to_string()),
            extractor: env::var("EXTRACTOR").unwrap_or_else(|_| "mock".to_string()),
            vlm_url: env::var("VLM_URL").unwrap_or_else(|_| "http://localhost:11434/v1".to_string()),
            vlm_model: env::var("VLM_MODEL").unwrap_or_else(|_| "qwen3-vl:8b".to_string()),
            vlm_api_key: env::var("VLM_API_KEY").ok().filter(|s| !s.is_empty()),
            dev_receipts_dir: env::var("DEV_RECEIPTS_DIR").unwrap_or_else(|_| "dev_receipts".to_string()),
        }
    }
}
