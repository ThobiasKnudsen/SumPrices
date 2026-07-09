use axum::extract::State;
use axum::http::StatusCode;
use axum::Json;
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier};
use argon2::password_hash::SaltString;
use argon2::password_hash::rand_core::OsRng;
use chrono::Utc;
use jsonwebtoken::{EncodingKey, Header, encode};
use sqlx::PgPool;

use crate::errors::AppError;

use super::middleware::AuthUser;
use super::models::*;

fn hash_password(password: &str) -> Result<String, AppError> {
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    argon2
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::Internal(format!("Password hashing failed: {e}")))
}

fn verify_password(password: &str, hash: &str) -> Result<(), AppError> {
    let parsed_hash =
        PasswordHash::new(hash).map_err(|e| AppError::Internal(format!("Invalid hash: {e}")))?;
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthorized)
}

fn create_token(sub: uuid::Uuid, email: &str) -> Result<String, AppError> {
    let jwt_secret = std::env::var("JWT_SECRET")
        .map_err(|_| AppError::Internal("JWT_SECRET not configured".to_string()))?;

    let claims = Claims {
        sub,
        email: email.to_string(),
        exp: (Utc::now() + chrono::Duration::days(7)).timestamp() as usize,
    };

    encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(jwt_secret.as_bytes()),
    )
    .map_err(|e| AppError::Internal(format!("Token creation failed: {e}")))
}

pub async fn register(
    State(pool): State<PgPool>,
    Json(req): Json<RegisterRequest>,
) -> Result<(StatusCode, Json<AuthResponse>), AppError> {
    if req.email.is_empty() || !req.email.contains('@') {
        return Err(AppError::BadRequest("Invalid email".to_string()));
    }
    if req.password.len() < 8 {
        return Err(AppError::BadRequest(
            "Password must be at least 8 characters".to_string(),
        ));
    }

    let password_hash = hash_password(&req.password)?;

    let row = sqlx::query_as::<_, (uuid::Uuid, String, Option<String>)>(
        "INSERT INTO users (email, password_hash, display_name) VALUES ($1, $2, $3) RETURNING id, email, display_name",
    )
    .bind(&req.email)
    .bind(&password_hash)
    .bind(&req.display_name)
    .fetch_one(&pool)
    .await
    .map_err(|e| match e {
        sqlx::Error::Database(ref db_err) if db_err.constraint() == Some("users_email_key") => {
            AppError::BadRequest("Email already registered".to_string())
        }
        _ => AppError::Database(e),
    })?;

    let token = create_token(row.0, &row.1)?;

    Ok((
        StatusCode::CREATED,
        Json(AuthResponse {
            token,
            user: UserResponse {
                id: row.0,
                email: row.1,
                display_name: row.2,
                credit_balance: 0,
            },
        }),
    ))
}

pub async fn login(
    State(pool): State<PgPool>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<AuthResponse>, AppError> {
    let row = sqlx::query_as::<_, (uuid::Uuid, String, String, Option<String>, i32)>(
        "SELECT id, email, password_hash, display_name, credit_balance FROM users WHERE email = $1",
    )
    .bind(&req.email)
    .fetch_optional(&pool)
    .await?
    .ok_or(AppError::Unauthorized)?;

    verify_password(&req.password, &row.2)?;

    let token = create_token(row.0, &row.1)?;

    Ok(Json(AuthResponse {
        token,
        user: UserResponse {
            id: row.0,
            email: row.1,
            display_name: row.3,
            credit_balance: row.4,
        },
    }))
}

pub async fn me(
    auth: AuthUser,
    State(pool): State<PgPool>,
) -> Result<Json<UserResponse>, AppError> {
    let row = sqlx::query_as::<_, (uuid::Uuid, String, Option<String>, i32)>(
        "SELECT id, email, display_name, credit_balance FROM users WHERE id = $1",
    )
    .bind(auth.user_id)
    .fetch_optional(&pool)
    .await?
    .ok_or(AppError::NotFound)?;

    Ok(Json(UserResponse {
        id: row.0,
        email: row.1,
        display_name: row.2,
        credit_balance: row.3,
    }))
}
