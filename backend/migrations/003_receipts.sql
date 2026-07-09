-- Receipt header (DESIGN §7.2) + dev-harness columns (source_file_hash, parser_commit).

CREATE TABLE receipts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source              receipt_source NOT NULL,
    original_asset_key  TEXT,
    original_mime       TEXT,
    store_id            UUID REFERENCES stores(id),
    store_name_raw      TEXT,
    purchase_at         TIMESTAMPTZ,
    capture_timezone    TEXT,
    currency            TEXT NOT NULL DEFAULT 'NOK',
    subtotal            NUMERIC(12,2),
    mva_total           NUMERIC(12,2),
    total               NUMERIC(12,2),
    extraction_status   extraction_status NOT NULL DEFAULT 'pending',
    extraction_engine   TEXT,
    extraction_conf     REAL,
    extraction_attempts INT NOT NULL DEFAULT 0,
    extraction_error    TEXT,
    next_attempt_at     TIMESTAMPTZ,
    needs_review        BOOLEAN NOT NULL DEFAULT FALSE,
    raw_extraction      JSONB,
    image_phash         BIT(64),
    dedup_signature     TEXT,
    txn_signature       TEXT,
    fraud_status        fraud_status NOT NULL DEFAULT 'ok',
    source_file_hash    TEXT,          -- dev harness: sha256 of the ingested file
    parser_commit       TEXT,          -- dev harness: git commit that produced the parse
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, dedup_signature)  -- NULLs are distinct, so unset dedup is allowed
);
CREATE INDEX idx_receipts_user_purchase ON receipts(user_id, purchase_at DESC);
CREATE INDEX idx_receipts_store         ON receipts(store_id);
CREATE INDEX idx_receipts_queue         ON receipts(extraction_status)
    WHERE extraction_status IN ('pending', 'queued', 'processing');
CREATE INDEX idx_receipts_txn_sig       ON receipts(txn_signature);
CREATE INDEX idx_receipts_user_filehash ON receipts(user_id, source_file_hash);
