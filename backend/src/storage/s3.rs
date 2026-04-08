use std::sync::Arc;

use s3::bucket::Bucket;
use s3::creds::Credentials;
use s3::region::Region;

use crate::config::Config;
use crate::errors::AppError;

#[derive(Clone)]
pub struct Storage {
    bucket: Arc<Bucket>,
}

impl Storage {
    pub fn new(config: &Config) -> Self {
        let region = Region::Custom {
            region: config.s3_region.clone(),
            endpoint: config.s3_endpoint.clone(),
        };

        let credentials = Credentials::new(
            Some(&config.s3_access_key),
            Some(&config.s3_secret_key),
            None,
            None,
            None,
        )
        .expect("Failed to create S3 credentials");

        let bucket = Bucket::new(&config.s3_bucket, region, credentials)
            .expect("Failed to create S3 bucket handle")
            .with_path_style();

        Self { bucket: Arc::new(*bucket) }
    }

    pub async fn upload(&self, key: &str, data: &[u8], content_type: &str) -> Result<(), AppError> {
        self.bucket
            .put_object_with_content_type(key, data, content_type)
            .await
            .map_err(|e| AppError::Internal(format!("S3 upload failed: {e}")))?;
        Ok(())
    }

    pub async fn get_presigned_url(&self, key: &str, expiry_secs: u32) -> Result<String, AppError> {
        self.bucket
            .presign_get(key, expiry_secs, None)
            .await
            .map_err(|e| AppError::Internal(format!("S3 presign failed: {e}")))
    }

    pub async fn delete(&self, key: &str) -> Result<(), AppError> {
        self.bucket
            .delete_object(key)
            .await
            .map_err(|e| AppError::Internal(format!("S3 delete failed: {e}")))?;
        Ok(())
    }
}
