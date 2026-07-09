CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Fixed-value columns use native ENUM types (DESIGN §7.0).
CREATE TYPE receipt_source    AS ENUM ('camera_photo', 'image_upload', 'pdf_upload', 'ereceipt_api');
CREATE TYPE extraction_status AS ENUM ('pending', 'queued', 'processing', 'done', 'failed', 'needs_review');
CREATE TYPE item_type         AS ENUM ('product', 'deposit', 'discount', 'fee', 'rounding', 'unknown');
CREATE TYPE fraud_status      AS ENUM ('ok', 'suspected', 'confirmed', 'dismissed');
CREATE TYPE ledger_reason     AS ENUM ('scan_reward', 'price_query', 'signup_bonus', 'referral', 'adjustment', 'reversal');
CREATE TYPE mapping_status    AS ENUM ('proposed', 'approved', 'rejected');
CREATE TYPE price_type        AS ENUM ('shelf', 'promo', 'member', 'coupon', 'net_only');
