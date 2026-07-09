-- Dimension tables (DESIGN §7.1). Order matters for FKs: categories/chains -> stores/products.

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT NOT NULL UNIQUE,
    password_hash   TEXT NOT NULL,
    display_name    TEXT,
    credit_balance  INT NOT NULL DEFAULT 0,       -- cached; credit_ledger is source of truth
    trust_score     REAL NOT NULL DEFAULT 0,
    consent_version TEXT,
    consent_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE categories (
    id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent_id INT REFERENCES categories(id),
    slug      TEXT NOT NULL UNIQUE,
    name      TEXT NOT NULL
);
INSERT INTO categories (slug, name) VALUES
    ('groceries', 'Groceries'),
    ('dining', 'Dining'),
    ('furniture', 'Furniture'),
    ('electronics', 'Electronics'),
    ('transport', 'Transport'),
    ('clothing', 'Clothing'),
    ('health', 'Health'),
    ('other', 'Other');

CREATE TABLE chains (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         TEXT NOT NULL UNIQUE,
    country_code CHAR(2) NOT NULL DEFAULT 'NO',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stores (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chain_id     UUID REFERENCES chains(id),
    name         TEXT NOT NULL,
    org_no       TEXT,
    country_code CHAR(2) NOT NULL DEFAULT 'NO',
    address      TEXT,
    city         TEXT,
    postal_code  TEXT,
    latitude     DECIMAL(9,6),
    longitude    DECIMAL(9,6),
    timezone     TEXT,                 -- IANA tz, used to compute purchase_at (DESIGN §7.4)
    osm_id       TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_stores_chain ON stores(chain_id);
CREATE INDEX idx_stores_geo   ON stores(latitude, longitude);

CREATE TABLE products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gtin        TEXT UNIQUE,           -- the universal barcode number; NULL for non-grocery/unresolved
    name        TEXT NOT NULL,
    brand       TEXT,
    category_id INT REFERENCES categories(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
