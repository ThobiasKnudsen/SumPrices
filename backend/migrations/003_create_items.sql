CREATE TABLE items (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    receipt_id            UUID NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    description           TEXT NOT NULL,
    quantity              REAL DEFAULT 1.0,
    unit_price            NUMERIC(12,2),
    line_total            NUMERIC(12,2),
    product_code          TEXT,
    gtin                  TEXT,
    canonical_product_id  UUID,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_items_receipt_id ON items(receipt_id);
CREATE INDEX idx_items_user_id ON items(user_id);
