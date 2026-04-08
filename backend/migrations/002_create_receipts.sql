CREATE TABLE receipts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_name      TEXT,
    purchase_date   DATE,
    purchase_time   TIME,
    total           NUMERIC(12,2),
    subtotal        NUMERIC(12,2),
    currency        TEXT NOT NULL DEFAULT 'NOK',
    image_key       TEXT NOT NULL,
    ocr_raw         JSONB,
    ocr_confidence  REAL,
    ocr_status      TEXT NOT NULL DEFAULT 'pending',
    ocr_token       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_receipts_user_id ON receipts(user_id);
CREATE INDEX idx_receipts_purchase_date ON receipts(user_id, purchase_date);
