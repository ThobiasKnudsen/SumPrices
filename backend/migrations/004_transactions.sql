-- The central fact table: one row per purchased line item (DESIGN §7.2).

CREATE TABLE transactions (
    id                BIGSERIAL PRIMARY KEY,
    receipt_id        UUID NOT NULL REFERENCES receipts(id) ON DELETE CASCADE,
    user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    store_id          UUID REFERENCES stores(id),
    product_id        UUID REFERENCES products(id),
    category_id       INT REFERENCES categories(id),
    occurred_at       TIMESTAMPTZ,              -- denormalized receipts.purchase_at
    line_no           INT,
    description_raw   TEXT NOT NULL,
    description_clean TEXT,
    item_type         item_type NOT NULL DEFAULT 'product',
    quantity          NUMERIC(12,3) DEFAULT 1,
    unit              TEXT,
    shelf_unit_price  NUMERIC(12,2),           -- store-set price before discount, when shown
    unit_price        NUMERIC(12,2),           -- net price per unit actually paid
    discount_amount   NUMERIC(12,2),
    line_total        NUMERIC(12,2),           -- net amount paid for the line
    price_type        price_type NOT NULL DEFAULT 'net_only',
    mva_rate          NUMERIC(5,2),
    confidence        REAL,
    needs_review      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_tx_user_desc    ON transactions(user_id, description_clean);
CREATE INDEX idx_tx_product_time ON transactions(product_id, occurred_at);
CREATE INDEX idx_tx_store_time   ON transactions(store_id, occurred_at);
CREATE INDEX idx_tx_receipt      ON transactions(receipt_id);
CREATE INDEX idx_tx_category     ON transactions(category_id);
