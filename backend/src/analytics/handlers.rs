use axum::extract::{Query, State};
use axum::Json;
use chrono::NaiveDate;
use rust_decimal::Decimal;
use serde::{Deserialize, Serialize};
use sqlx::PgPool;

use crate::auth::middleware::AuthUser;
use crate::errors::AppError;

#[derive(Debug, Deserialize)]
pub struct SpendingQuery {
    pub period: Option<String>, // "week" or "month"
    pub from: Option<NaiveDate>,
    pub to: Option<NaiveDate>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct SpendingPeriod {
    pub label: String,
    pub total: Option<Decimal>,
}

#[derive(Debug, Serialize)]
pub struct SpendingResponse {
    pub periods: Vec<SpendingPeriod>,
}

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct StoreSpending {
    pub name: Option<String>,
    pub total: Option<Decimal>,
    pub count: i64,
}

#[derive(Debug, Serialize)]
pub struct ByStoreResponse {
    pub stores: Vec<StoreSpending>,
}

pub async fn spending(
    auth: AuthUser,
    State(pool): State<PgPool>,
    Query(params): Query<SpendingQuery>,
) -> Result<Json<SpendingResponse>, AppError> {
    let period = params.period.as_deref().unwrap_or("month");
    let trunc = match period {
        "week" => "week",
        _ => "month",
    };

    let periods = sqlx::query_as::<_, SpendingPeriod>(&format!(
        "SELECT to_char(date_trunc('{trunc}', purchase_date), 'YYYY-MM-DD') as label,
                SUM(total) as total
         FROM receipts
         WHERE user_id = $1
           AND purchase_date IS NOT NULL
           AND total IS NOT NULL
           AND ($2::date IS NULL OR purchase_date >= $2)
           AND ($3::date IS NULL OR purchase_date <= $3)
         GROUP BY date_trunc('{trunc}', purchase_date)
         ORDER BY date_trunc('{trunc}', purchase_date)"
    ))
    .bind(auth.user_id)
    .bind(params.from)
    .bind(params.to)
    .fetch_all(&pool)
    .await?;

    Ok(Json(SpendingResponse { periods }))
}

pub async fn by_store(
    auth: AuthUser,
    State(pool): State<PgPool>,
    Query(params): Query<SpendingQuery>,
) -> Result<Json<ByStoreResponse>, AppError> {
    let stores = sqlx::query_as::<_, StoreSpending>(
        "SELECT store_name as name, SUM(total) as total, COUNT(*) as count
         FROM receipts
         WHERE user_id = $1
           AND total IS NOT NULL
           AND ($2::date IS NULL OR purchase_date >= $2)
           AND ($3::date IS NULL OR purchase_date <= $3)
         GROUP BY store_name
         ORDER BY total DESC NULLS LAST",
    )
    .bind(auth.user_id)
    .bind(params.from)
    .bind(params.to)
    .fetch_all(&pool)
    .await?;

    Ok(Json(ByStoreResponse { stores }))
}
