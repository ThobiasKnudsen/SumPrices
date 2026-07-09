-- Support tables (DESIGN §7.5).

CREATE TABLE refresh_tokens (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,     -- store a hash, never the raw token
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_refresh_user ON refresh_tokens(user_id);

CREATE TABLE credit_ledger (
    id            BIGSERIAL PRIMARY KEY,
    user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    delta         INT NOT NULL,          -- + earn, - spend
    reason        ledger_reason NOT NULL,
    ref_type      TEXT,
    ref_id        TEXT,
    balance_after INT NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_ledger_user ON credit_ledger(user_id, created_at DESC);
-- A receipt is rewarded at most once (idempotent crediting; survives reparse).
CREATE UNIQUE INDEX uq_ledger_scan_reward ON credit_ledger(user_id, ref_id) WHERE reason = 'scan_reward';
