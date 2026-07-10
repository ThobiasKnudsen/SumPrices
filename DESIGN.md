# SummPrices — Design & Architecture

> Canonical design context for SummPrices. Read this first. It records **what we're building and why**, the **decisions made** (with rationale), and the **open items**. The existing repo code and any older "spec" documents are **out of date** relative to this file — this file wins.
>
> Last updated: 2026-07-09.

---

## 1. Product

**SummPrices** is a **personal "everything you buy" archive**. A user scans (or uploads) *any* receipt — groceries, furniture, electronics, a restaurant bill — and the app stores **the receipt image itself + structured line items**. Core consumer value:

- **Personal history & insight** — look back over time ("where did my money go"), filter by shop, by item, by date range; count how many times item Y was bought from START→END.
- **Credit for contributing** — scanning receipts earns account credit. Viewing your *own* purchases is always free (see §7.7).
- **Price search** — spend credit to query the *crowd / aggregated* price data via the Price API (see §7.7).
- **Digital receipts** — import machine-readable receipts (PDF), not only photos.
- **Export** — select receipts and export them.
- **Later:** "am I overpaying vs other stores?" — unlocked once enough crowd data exists.

**It is not** just groceries, and **not** a per-store tool — it's a universal archive of a person's purchases.

## 2. Positioning & business model

- **Consumer-first, B2B-later.** The free consumer app is the **data-acquisition funnel**; the anonymized aggregate **price index is the future monetizable asset** (sold via the B2B API/dashboard). Build the consumer app + the anonymized price pipeline now; design so the B2B API is added later without a rewrite.
- **The Price API is the single monetization surface.** It serves only the *crowd / aggregated* price data — **never** a user's own receipts, which are always free (see §7.7). Consumers pay in *earned credits*; B2B customers (later) pay in *money*. Same underlying API, different auth/metering.

## 3. Target market

- **Norway-first** (NOK, MVA/VAT, Norwegian chains and receipt formats), **international-ready by design** (country-aware schema, currency per receipt/price, locale-aware parsing).

## 4. Architecture principles

1. **Modular monolith**, not microservices. A Cargo **workspace of libraries + one axum binary**. Extract a service only when load/release cadence actually diverges. (The old spec's 3-microservice split is premature for a solo team.)
2. **Two data domains, separated from day one** (§7):
   - **Operational / PII** — users, receipts, images, their line-item transactions. Tied to identity.
   - **Anonymized crowd/price data** — derived from `transactions` (aggregated, **no user identity**). Materialized into a retained de-identified store only when B2B / retention needs it (§7.3).
3. **Thin client.** The web app (React + TS SPA) = capture + upload + display + API calls. **No meaningful processing on the client** — Postgres, the backend, and the extraction service do the work.
4. **Extraction behind a `ReceiptExtractor` trait** — the model/provider is a swappable implementation detail (§6).
5. **GDPR-first** (§8). Self-hosting the model and keeping all data in the EU is a deliberate compliance + product advantage.
6. **Async by default.** Receipt extraction runs off the request path via a durable job queue.

## 5. System architecture

```
React web app  ──HTTPS──> axum backend (modular monolith) ──> PostgreSQL
   (thin: capture,             │  ├─ identity/auth               │  (operational/PII
    upload, display,           │  ├─ capture/ingest               │   + reference catalog
    API calls)                 │  ├─ extraction (trait)           │   + anonymized
                               │  ├─ catalog (stores/products)    │   price time-series)
                               │  ├─ price-index / Price API      │
                               │  └─ credits/ledger               │
                               │                                  
                               ├──> Object storage (S3-compatible): receipt images
                               └──> Extraction service: self-hosted VLM on on-demand EU GPU
                                     (Ollama/vLLM, OpenAI-compatible localhost endpoint)
```

- **Backend:** Rust, axum 0.8, sqlx 0.8 (Postgres, compile-time-checked), argon2 + JWT auth, `rust-s3` for object storage.
- **Client:** React + TypeScript SPA (Vite, Tailwind). *(Flutter web MVP was replaced; native mobile revisited later.)*
- **Object storage:** S3-compatible; receipt images keyed per user; presigned URLs for display.

## 6. Receipt extraction pipeline

**Goal:** receipt image (or digital PDF) → validated structured JSON:
`{ store{name,org_no,address,city,postal_code,country_code}, purchase_at, currency, receipt_number, payment{method}, subtotal, total, mva_lines[{rate,base,vat}], line_items[{description, product_code, quantity, unit, shelf_unit_price, unit_price, discount_amount, line_total, item_type, price_type, mva_rate}] }` (the full v2 shape lives in `extraction/hosted_vlm.rs`'s prompt). Key fields are promoted to columns (`receipts.receipt_number`, `transactions.product_code`, …); the whole JSON is kept in `receipts.raw_extraction`.

**Tiered flow (behind `ReceiptExtractor`):**
1. **Structured import first** where possible — a **digital PDF with a text layer** is parsed directly (no OCR). *Manual PDF upload is a launch feature; email/mailbox ingestion is later.*
2. **VLM extraction** for images — a self-hosted vision-LLM takes the image and emits the JSON schema directly.
3. **Validators (Rust)** — normalize NOK (comma decimals, space/period thousands), parse `DD.MM.YYYY`, reconcile the MVA table, handle `pant`/`rabatt` lines, capture the `NO…MVA` org-number as store identity.
4. **Confidence gate (free):** `line_total == qty×unit_price`, `Σ line_totals == subtotal`, `subtotal + MVA == total`, org-number mod-11 checksum. **Pass → store; fail → flag `needs_review`** and/or escalate to a larger model.

**Model choice (verified 2026):**
- **Recommended: Qwen3-VL-Instruct (Apache-2.0)** — start at **4B**, upgrade to **8B** if 4B underperforms on messy Norwegian receipts. General instruction-following VLM → emits our exact JSON schema directly. OCR expanded to 32 languages (helps Norwegian); robust to blur/tilt.
- **AVOID (license):** `Qwen2.5-VL-3B` and **all Nanonets-OCR** models — Qwen *Research* license = **non-commercial**.
- **Sizes:** 8B ≈ 17 GB weights, ~18–20 GB VRAM fp16 (fits a 24 GB card: RTX 4090 / L4 / A10) or ~8–11 GB at 4-bit (16 GB card); 4B ≈ 8 GB fp16 / ~3.5 GB 4-bit. **Cap image `max_pixels`** to avoid OOM.
- OCR-only specialists (PaddleOCR-VL-0.9B, dots.ocr, PP-OCRv5) output page text/markdown, not our schema — optional as a cheap pre-filter or a VRAM-saving 2-stage path, not the primary.

**Serving & deployment:**
- **Engine (chosen):** the extractor calls **any OpenAI-compatible vision endpoint** — env `EXTRACTOR=hosted`, `VLM_URL`, `VLM_MODEL`, `VLM_API_KEY` (bearer). **Dev = OpenRouter** (one key; benchmark many vision models on real Norwegian receipts to pick the best). **Prod = EU-direct** (Mistral, Paris) before real users — receipts are sensitive; OpenRouter is a US router → not EU-resident. It's a config switch, no code change. `EXTRACTOR=mock` for tests/CI. Self-hosted Qwen3-VL on a rented GPU (below) remains an option.
- **Serving (self-host option):** **Ollama** (single binary, OpenAI-compatible endpoint, native `json_schema` structured output) → migrate to **vLLM** (guided-JSON + continuous batching) at volume. Backend calls it via `reqwest`. Enforce JSON with constrained decoding; validate server-side before any DB write.
- **GPU deployment: on-demand / scale-to-zero EU GPU.** Batch-drain the queue in warm windows. ~1k receipts/mo ≈ €2–3/mo; 10k/mo ≈ €25–30/mo. EU-sovereign per-second GPU (**Scaleway L4** Paris/Warsaw preferred; RunPod/Modal EU regions with a signed DPA). Migrate to an **always-on Hetzner** GPU (~€184/mo) only above ~66k receipts/mo. **Avoid fly.io** (GPUs deprecated after 2026-08-01).
- **Job mechanism:** durable **Postgres `SELECT … FOR UPDATE SKIP LOCKED`** queue + background worker, so scans survive restarts and the GPU can batch-drain. (The repo's current OCR seam is fire-and-forget `tokio::spawn` + lazy polling — to be upgraded.)

**Non-negotiable before locking a model:** no model has a published **Norwegian-receipt benchmark**. Build a **~50–100 real Norwegian receipt eval set** (Rema/Kiwi/Coop + restaurant/furniture/electronics, incl. faded thermal) and measure line-item / MVA / total accuracy first.

## 7. Data model

> **Star schema.** One big central **fact table** (`transactions` — every line item bought) surrounded by small **dimension tables** (`users`, `chains`, `stores`, `products`, `categories`) that it points to via foreign keys. Crowd/price data is **derived from `transactions`** (aggregate queries), not a separate table at MVP (§7.3). Types are PostgreSQL; fixed-value columns use native `ENUM` types (§7.0). `PK` = primary key, `FK→x` = foreign key to table `x`. The fact table holds the FKs; dimension tables never carry a transaction id.

### 7.0 Enum types

| Enum type | Values |
|---|---|
| `receipt_source` | camera_photo, image_upload, pdf_upload, ereceipt_api |
| `extraction_status` | pending, queued, processing, done, failed, needs_review |
| `item_type` | product, deposit, discount, fee, rounding, unknown |
| `fraud_status` | ok, suspected, confirmed, dismissed |
| `ledger_reason` | scan_reward, price_query, signup_bonus, referral, adjustment, reversal |
| `mapping_status` | proposed, approved, rejected |
| `price_type` | shelf, promo, member, coupon, net_only |

### 7.1 Dimension tables (small, shared)

**`users`** — accounts / auth *(extends existing; per-user PII)*

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | existing |
| email | TEXT | NOT NULL, UNIQUE | existing |
| password_hash | TEXT | NOT NULL | existing (argon2) |
| display_name | TEXT | | existing |
| credit_balance | INT | NOT NULL, default 0 | cached; `credit_ledger` is source of truth |
| trust_score | REAL | NOT NULL, default 0 | anti-fraud reputation; grows with verified scans |
| consent_version | TEXT | | GDPR: privacy/ToS version accepted |
| consent_at | TIMESTAMPTZ | | when consent was given |
| created_at / updated_at | TIMESTAMPTZ | NOT NULL, default now() | existing |

**`chains`** — retail chains (groups stores)

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | |
| name | TEXT | NOT NULL, UNIQUE | 'Rema 1000', 'Kiwi', 'Coop Extra', … |
| country_code | CHAR(2) | NOT NULL, default 'NO' | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

**`stores`** — one row per physical outlet

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | |
| chain_id | UUID | FK→chains | NULL for independent shops |
| name | TEXT | NOT NULL | plain text (Nominative Fair Use) |
| org_no | TEXT | | Norwegian org number (outlet / legal entity) |
| country_code | CHAR(2) | NOT NULL, default 'NO' | |
| address / city / postal_code | TEXT | | from the receipt when present |
| latitude / longitude | DECIMAL(9,6) | | OSM geo |
| timezone | TEXT | | IANA tz (e.g. 'Europe/Oslo') — used to compute `purchase_at` (§7.4) |
| osm_id | TEXT | | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

*Indexes:* `chain_id`; `(latitude, longitude)`.

**`products`** — the item catalog; identified by barcode

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | surrogate key |
| gtin | TEXT | UNIQUE | **the universal number** — EAN/UPC barcode; NULL if item has no barcode |
| name | TEXT | NOT NULL | |
| brand | TEXT | | |
| category_id | INT | FK→categories | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

Note: `gtin` is the universal item id when a barcode exists; many receipt lines (and non-grocery items) have none, so we keep a surrogate `id` too.

**`categories`** — spend categories (hierarchy)

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | INT | PK (identity) | |
| parent_id | INT | FK→categories | hierarchy (NULL = top level) |
| slug | TEXT | NOT NULL, UNIQUE | |
| name | TEXT | NOT NULL | seeded: groceries, dining, furniture, electronics, transport, … |

### 7.2 Fact tables

**`receipts`** — one row per uploaded / scanned receipt (the *header*; parent of the line items)

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | |
| user_id | UUID | FK→users, NOT NULL, cascade delete | owner |
| source | `receipt_source` | NOT NULL | how it arrived |
| original_asset_key | TEXT | | object-storage key of image/PDF; NULL for API imports |
| original_mime | TEXT | | `image/jpeg`, `application/pdf` |
| store_id | UUID | FK→stores | NULL until store resolved |
| store_name_raw | TEXT | | extracted store text; shown even if unresolved |
| purchase_at | TIMESTAMPTZ | | universal instant of purchase (§7.4 timezone rules) |
| capture_timezone | TEXT | | client device tz at upload — VPN-safe fallback for `purchase_at` |
| currency | TEXT | NOT NULL, default 'NOK' | |
| subtotal / mva_total / total | NUMERIC(12,2) | | |
| extraction_status | `extraction_status` | NOT NULL, default 'pending' | pipeline state |
| extraction_engine | TEXT | | model + version, e.g. `qwen3-vl-8b@2026-06` |
| extraction_conf | REAL | | 0–1 |
| needs_review | BOOLEAN | NOT NULL, default false | low-confidence seam |
| raw_extraction | JSONB | | full model output (audit / reprocess) |
| image_phash | BIT(64) | | perceptual hash — near-duplicate images |
| dedup_signature | TEXT | UNIQUE(user_id, dedup_signature) | hash(user, store, date, total, item_count) |
| txn_signature | TEXT | | hash(org_no, purchase_at, total) — cross-user dup (later) |
| fraud_status | `fraud_status` | NOT NULL, default 'ok' | |
| extraction_attempts | INT | NOT NULL, default 0 | retry counter for the queue |
| extraction_error | TEXT | | last failure message |
| next_attempt_at | TIMESTAMPTZ | | backoff time for retries |
| created_at / updated_at | TIMESTAMPTZ | NOT NULL, default now() | |

*Indexes:* `(user_id, purchase_at DESC)`; `store_id`; `extraction_status` (partial, active states) for the queue; `txn_signature`.

The `receipts` table **is** the extraction queue — the worker polls `WHERE extraction_status IN ('pending','queued') … FOR UPDATE SKIP LOCKED`. A generic `jobs` table is only worth it once job types multiply (§7.8).

**`transactions`** — **the central fact table: one row per purchased line item.** Biggest table; references every dimension.

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | BIGSERIAL | PK | compact key for the biggest table |
| receipt_id | UUID | FK→receipts, NOT NULL, cascade delete | parent receipt |
| user_id | UUID | FK→users, NOT NULL, cascade delete | dimension (denormalized for user queries) |
| store_id | UUID | FK→stores | dimension (denormalized from receipt for per-store analytics) |
| product_id | UUID | FK→products | dimension; NULL until resolved (the §4/#4 "unsure" seam) |
| category_id | INT | FK→categories | dimension |
| occurred_at | TIMESTAMPTZ | | denormalized `receipts.purchase_at` — for time queries |
| line_no | INT | | order on the receipt |
| description_raw | TEXT | NOT NULL | exactly as extracted |
| description_clean | TEXT | | normalized for search / matching |
| item_type | `item_type` | NOT NULL, default 'product' | handles `pant` / `rabatt` lines |
| quantity | NUMERIC(12,3) | default 1 | supports weight (kg) |
| unit | TEXT | | 'stk', 'kg', 'l' |
| shelf_unit_price | NUMERIC(12,2) | | shelf/list price per unit *before* discount (when the receipt shows it) |
| unit_price | NUMERIC(12,2) | | **net** price per unit actually paid |
| discount_amount | NUMERIC(12,2) | | line discount = (shelf − net) × qty; 0 / NULL if none |
| line_total | NUMERIC(12,2) | | **net** amount paid for the line |
| price_type | `price_type` | NOT NULL, default 'net_only' | shelf / promo / member / coupon / net_only (§7.3) |
| mva_rate | NUMERIC(5,2) | | 25.00 / 15.00 / 12.00 |
| confidence | REAL | | |
| needs_review | BOOLEAN | NOT NULL, default false | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

*Indexes:* `(user_id, description_clean)` for "item Y over time"; `(product_id, occurred_at)`; `(store_id, occurred_at)`; `receipt_id`; `category_id`.

### 7.3 Crowd / price index — derived, not stored (yet)

**There is no separate price table at MVP.** Every `transactions` row already *is* a price observation (`product_id` / `description_clean`, `store_id`, `occurred_at`, `unit_price`, `unit`, `currency`). A dedicated `price_history` table would be a ~1:1 duplicate of the biggest table, so:

- **Crowd/market price queries = aggregate queries over `transactions`** (grouped by product × store × time), with **k-anonymity enforced** (only return aggregates backed by ≥ K distinct sources) and credit-metered at the API (§7.7). At MVP, the free "*your own* item Y over time" is just a `transactions` query on `(user_id, description_clean)` — no product resolution needed.
- **`current_prices` (latest price per product × store)** is *not* 1:1 — it collapses to one row per pair. If/when price search needs speed, add it as a **materialized view** over `transactions` (refresh periodically). Not needed at launch.

**Price semantics — one item can have several prices at once.** Two shoppers can pay different amounts for the same item at the same store+time (member price, coupon, promo), so a price is not a single number. We model it per line from *what the receipt shows*:
- `unit_price` / `line_total` = the **net** the user actually paid — always captured; this is what the personal archive uses.
- `shelf_unit_price` + `discount_amount` = the **store-set** price and the reduction, *when the receipt itemizes them* (a base line + a `Rabatt`/`Trumf` line).
- `price_type` classifies the observation: `shelf` / `promo` are **store-set** (user-independent, comparable across shoppers); `member` / `coupon` are **personal**; `net_only` = we only know what was paid.
- Line-attributable discounts fold onto the product row (shelf + discount); basket-level discounts stay as standalone `item_type = 'discount'` transactions.

For the crowd **price index**, compare **store-set prices** (`shelf` / `promo`) for apples-to-apples; surface `member` prices as a separate tier; never mix a coupon price into the shelf-price series. **We can only model what's on the receipt** — a bare net total is stored tagged `net_only`. This stays general across all shops worldwide while representing the richer cases when the data is there. **Out of per-item scope:** chain loyalty rebates that pay 1–3 % back on the whole basket to a membership account (Coop *kjøpeutbytte*, Trumf) — a basket-level perk paid later, not a per-item price (optionally a receipt-level note if we ever want effective-cost analytics).

**Deferred: a de-identified retained `price_history`.** Its *only* justification is GDPR — a copy with **no `user_id`** that (a) survives a user deleting their account and (b) lets the B2B API answer without touching PII. Build it when B2B/retention actually lands (a background job snapshots `transactions` → de-identified, coarsened, k-anonymized rows). **Trade-off of deferring:** until then, a user who deletes their account removes their contribution from the crowd aggregates — acceptable at MVP scale. The asset still accrues from day 1 *inside `transactions`*.

**Time-series at scale — still just Postgres.** When the retained `price_history` arrives, use native **monthly range-partitioning** (built-in) so recent months stay hot and old ones can be compressed; add the **TimescaleDB** extension later for automatic compression / retention / continuous aggregates (the "old data in a less-aggressive cache" idea). No separate time-series DB needed.

### 7.4 Timezone handling for `purchase_at`

A paper receipt prints *local* wall-clock time with no zone, but `purchase_at` stores a **universal instant**. Resolution order (VPN-proof — never IP geolocation):
1. **Store address / geo → timezone.** If the receipt gives the shop address (or we've resolved `store_id`), use `stores.timezone`. Most reliable.
2. **Client-reported timezone.** Else use `receipts.capture_timezone` — the device's own timezone/position sent at upload (not IP-based, so a VPN doesn't corrupt it).
3. **Fallback** `Europe/Oslo` (Norway-first) if neither is known; flag `needs_review`.

### 7.5 Support tables

**`refresh_tokens`** — session management (JWT access tokens are short-lived; these rotate/revoke)

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | |
| user_id | UUID | FK→users, NOT NULL, cascade delete | |
| token_hash | TEXT | NOT NULL, UNIQUE | store a hash, never the raw token |
| expires_at | TIMESTAMPTZ | NOT NULL | |
| revoked_at | TIMESTAMPTZ | | NULL = active |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

*Index:* `(user_id)`.

**`credit_ledger`** — append-only; balance = Σ delta

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | BIGSERIAL | PK | ordered |
| user_id | UUID | FK→users, NOT NULL, cascade delete | |
| delta | INT | NOT NULL | `+` earn, `−` spend |
| reason | `ledger_reason` | NOT NULL | |
| ref_type | TEXT | | 'receipt', 'price_query', … |
| ref_id | TEXT | | receipt / query id |
| balance_after | INT | NOT NULL | running balance (audit) |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

*Constraint:* `UNIQUE(user_id, ref_id) WHERE reason = 'scan_reward'` → a receipt is rewarded **at most once**.

**`raw_text_mappings`** *(later)* — raw string → product, per store/chain, voted / moderated (the corrected "barcode bridge" — never global first-write-wins)

| Column | Type | Key / Rules | Notes |
|---|---|---|---|
| id | UUID | PK | |
| chain_id | UUID | FK→chains | scope to a chain… |
| store_id | UUID | FK→stores | …or a specific store |
| raw_text | TEXT | NOT NULL | |
| product_id | UUID | FK→products, NOT NULL | |
| status | `mapping_status` | NOT NULL, default 'proposed' | |
| votes | INT | NOT NULL, default 0 | |
| proposed_by | UUID | FK→users | |
| created_at | TIMESTAMPTZ | NOT NULL, default now() | |

**`review_queue`** *(later)* — receipts / items needing resolution. MVP uses the `needs_review` flags; a dedicated table + resolution UX comes later.

### 7.6 Anti-fraud & de-duplication

Because scanning earns spendable credit, dedup/anti-fraud is **layered** (stronger than a single hash):

- **MVP:** `image_phash` + `dedup_signature` (UNIQUE per user) block re-uploads of the same receipt; the §6 arithmetic / MVA / org-no self-checks must pass to earn full credit (fail → `needs_review`, no credit); `credit_ledger` idempotency (one `scan_reward` per receipt) prevents double-crediting; basic per-user scan/credit rate limits.
- **Later:** `txn_signature` catches the *same transaction claimed by different users*; `trust_score` down-weights new / low-reputation users; provisional / "escrow" credit that only settles after checks and is reversible via `reversal` ledger entries if a receipt is flagged after the fact.

### 7.7 Free vs credit-metered (where the credit line falls)

- **Always free — personal domain:** viewing / searching your own `receipts` + `transactions`, your personal analytics, and *your own* price history for *your own* purchases. Looking at your own data is **never** gated.
- **Credit-metered — crowd domain:** aggregate queries over everyone's `transactions` (§7.3) via the Price API — each query writes a `price_query` debit. Later, B2B access is the *same* surface, metered by money instead of earned credits.

### 7.8 Tables considered & deferred

Not built at MVP; documented so we don't rediscover the need later:

- **De-identified `price_history` + `current_prices` view** — when B2B / retention-past-deletion / scale arrives (§7.3).
- **Generic `jobs` table** — only if job types multiply beyond extraction (MVP: `receipts` is the queue, §7.2).
- **`consent_events`** — full GDPR consent audit trail (MVP uses columns on `users`).
- **`data_requests`** — track GDPR export / deletion (DSAR) requests and their status.
- **`devices`** — push-notification tokens (when notifications ship).
- **`store_aliases`** — raw store-name → `store_id` resolution (part of the later identity-resolution flow, alongside `raw_text_mappings`).
- **`receipt_tags` / notes** — user annotations on receipts.
- **Item-enrichment tables** (`item_contributions`, `info_requests`, `contribution_verifications`) + KYC fields — the crowdsourced-enrichment vision (§14).

## 8. GDPR & compliance (hard constraints)

- Receipts can be **Article 9 special-category** data (pharmacy → health, etc.) → treat the corpus as sensitive; use **explicit consent** as the lawful basis.
- **Self-host the model; keep all data in the EU.** No third-party processor for extraction → no DPA/Schrems exposure. If a cloud fallback is ever used, **EU-only**; **avoid US processors** (EU–US Data Privacy Framework is in acute doubt after a June 2026 US Supreme Court ruling).
- **Deletion** must cascade to the user's `receipts` + `transactions` and their receipt images in object storage **and backups**, not just the `users` row. At MVP, since crowd prices are derived from `transactions`, a deleted user's contribution leaves the aggregates (accepted; §7.3).
- **Export/portability** (Art. 20) — a full per-user export (transactions + arguably source images) should be one query.
- **Post-deletion retention** — once the de-identified `price_history` is introduced (§7.3), retaining it after account deletion is allowed **only with genuine anonymization** (real k-anonymity/aggregation), documented — most naive "anonymization" is reversible pseudonymization and would be non-compliant.

## 9. Norway specifics

- **Formats:** NOK comma decimals (`49,90`), space/period thousands, `DD.MM.YYYY` dates, MVA breakdown table (rates 25 % / 15 % / 12 %, **prices shown gross**), `pant` (deposit) and `Rabatt`/`Trumf` lines, `Totalt`/`Å betale` labels, `NO#########MVA` org-number as store id. Member/`Trumf` prices are *personal*, not shelf prices (§7.3).
- **Chain digital receipts** (Rema 1000 Æ, Coop Medlem, Trumf → Kiwi/Meny) expose perfect structured line items covering ~97 % of grocery — but via **unofficial, reverse-engineered, ToS-gray** APIs. **Opt-in Phase-3 only, never load-bearing.**
- **EHF/Peppol** is B2B/B2G e-invoicing, **not** consumer receipts — out of scope for ingestion.

## 10. Tech stack

- **Backend:** Rust (edition 2024), axum 0.8, tokio, sqlx 0.8 (Postgres + compile-time checks), argon2, jsonwebtoken, `rust-s3`, reqwest.
- **DB:** PostgreSQL (crowd prices derived from `transactions`; native partitioning + TimescaleDB later, if a retained price series is introduced).
- **Client:** React + TypeScript SPA in `web/` (Vite + Tailwind + React Router + TanStack Query + Recharts).
- **Extraction:** self-hosted Qwen3-VL via Ollama → vLLM, on an on-demand EU GPU.
- **Object storage:** S3-compatible.

## 11. Roadmap (phased)

**Launch (MVP)**
- Auth (+ `refresh_tokens`); capture/upload (photo **and manual digital-PDF upload**); durable extraction queue (on `receipts`) + self-hosted VLM; validators + confidence gate + `needs_review`; personal archive with filtering (by shop / item / date range) and spend analytics; credit ledger (earn on scan); basic price search as credit-metered aggregate queries over `transactions`; export; GDPR basics (consent, export, delete-with-cascade).

**Later**
- Email/mailbox digital-receipt ingestion; item-uncertainty **resolution flow** + per-store `raw_text_mappings` (crowd/vote); chain-API opt-in import; "overpaying" comparisons; TimescaleDB for the price series; B2B paid Price API + dashboard; richer product/store identity resolution; international expansion; **crowdsourced item enrichment + demand-driven bounties + reputation/KYC (§14)**.

## 12. Open items / next steps

1. **Data model finalized (§7).** Implement it: **overwrite** the schema SQL + Rust models/handlers to match (no incremental migrations — no deployment/data yet) and do the workspace restructure.
2. Norwegian **eval set** (~50–100 receipts) to validate Qwen3-VL 4B vs 8B before locking the model.
3. Extraction worker (VLM + durable `SKIP LOCKED` queue on `receipts`).
4. Price-API contract (filters, credit metering, and the B2B-access seam).
5. Web client = React + TS SPA in `web/` (built); the Flutter `client/` was removed.

## 13. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-07-09 | Product = universal personal purchase archive (any receipt), not a grocery/price app first | User's stated primary value: organized history of everything bought |
| 2026-07-09 | Consumer-first; B2B price index designed-for but built later | Consumer app is the data funnel; aggregate data is the asset |
| 2026-07-09 | Modular monolith (workspace + one binary), not microservices | Premature to split for a solo team |
| 2026-07-09 | Self-hosted **Qwen3-VL** (4B→8B, Apache-2.0) on an **on-demand EU GPU** | Best accuracy-per-VRAM that emits our schema; on-demand is cheapest at launch; self-host = clean GDPR |
| 2026-07-09 | Extraction behind a `ReceiptExtractor` trait; Ollama→vLLM; durable Postgres queue | Swappable engine; robust async jobs |
| 2026-07-09 | Two data domains: PII vs anonymized price time-series | Clean GDPR deletion; protect the B2B asset |
| 2026-07-09 | Thin client; backend/Postgres do the work | User decision |
| 2026-07-09 | **Personal archive always free**; credit gates only the crowd/aggregated Price API | Gating a user's own data would anger users |
| 2026-07-09 | Item-uncertainty via a `needs_review` seam + nullable `product_id`; full resolution later | Straight seam to handle unsure items later |
| 2026-07-09 | Manual digital-PDF upload at launch; email integration later | User decision |
| 2026-07-09 | GDPR-first; EU-only; avoid US processors; explicit consent | Receipts can be Art. 9 data; DPF legal uncertainty |
| 2026-07-09 | Credits = integer points; cached `users.credit_balance`, `credit_ledger` authoritative | Simple, fast reads, fully auditable |
| 2026-07-09 | **Star schema:** central `transactions` fact table (one row / line item) + `users`/`chains`/`stores`/`products`/`categories` dimensions | User's model; the fact table holds FKs to dimensions |
| 2026-07-09 | Separate `chains` table; `products` identified by barcode (`gtin`, universal number) | User's model |
| 2026-07-09 | PostgreSQL native **`ENUM`** types for fixed-value columns (not TEXT+CHECK) | User's call |
| 2026-07-09 | **No stored price table** at MVP — `transactions` already *is* the price observations; crowd price = k-anon aggregate queries over it | User: a 1:1 duplicate of the fact table is redundant |
| 2026-07-09 | De-identified retained `price_history` + `current_prices` view **deferred** to when B2B / retention / scale needs it | Consumer-first; avoid premature duplication (accept: deleted-account signal is lost until then) |
| 2026-07-09 | `purchase_at` = universal `TIMESTAMPTZ`; timezone from store address/geo → else client device tz (VPN-safe, never IP) | User decision on time/VPN |
| 2026-07-09 | `receipts` table **is** the extraction queue (`SKIP LOCKED` + retry columns); generic `jobs` table only if job types multiply | Simplest for one job type |
| 2026-07-09 | Add `refresh_tokens` for real session management | JWT access tokens alone can't rotate/revoke |
| 2026-07-09 | Layered anti-fraud (phash + signatures + arithmetic gate + idempotent ledger), stronger than a hash | Credit has spendable value; asset accrues in `transactions` |
| 2026-07-09 | Price modeled per line as **net paid** + optional **shelf price / discount** + a `price_type` tag (shelf/promo/member/coupon/net_only); index compares store-set prices | Same item has several prices at once (member/coupon/promo); model receipt-visible cases, degrade to net_only |
| 2026-07-09 | Chain loyalty rebates (1–3 % basket cashback) out of per-item price scope | Basket-level perk paid later, not a per-item price |
| 2026-07-09 | **Progressive KYC** — basic scanning/earning stays open; identity verification gates only high-value contributions / cash-out / elevated trust (provider-based, store status only, never ID docs) | Corruption-resistance without killing the funnel or holding identity data |
| 2026-07-09 | `trust_score` = earned from contributions proving true over time (corroboration); crowdsourced enrichment + bounty economy captured as vision (§14) | Hard-to-corrupt data moat; phased, post-MVP |
| 2026-07-09 | Trust engine = weighted truth discovery (Dawid–Skene-style batch EM); **KYC = high prior weight, not an oracle**; reward = value-of-information; output = value + confidence | User's KYC-weighting idea, with guardrails against KYC-as-oracle and minority-suppression |
| 2026-07-10 | MVP backend built + verified end-to-end (star schema, `ReceiptExtractor` trait mock/hosted, ingest harness, credits) | Commit 029ec07; runs on local Postgres + MinIO |
| 2026-07-10 | **Web frontend = React + TypeScript SPA** (Vite + Tailwind + TanStack Query + Recharts); Flutter `client/` **removed** | Team prefers TS; cleaner web DX. Supersedes the earlier Flutter-web choice (§5/§10). Native mobile revisited later |
| 2026-07-10 | Extraction engine = **any OpenAI-compatible vision API** (`VLM_API_KEY`). **Dev = OpenRouter**, **prod = EU-direct (Mistral)** before real users | OpenRouter = 1 key to benchmark many models; but US router → not EU-resident, so switch before real user data. Config switch, no code change |
| 2026-07-10 | Receipt→JSON **v2 schema** (nested store+address, `receipt_number`, `mva_lines`, `payment.method` no card digits, per-line `product_code`/EAN) | Richer, validatable, seeds product identity; key fields promoted to columns, rest in `raw_extraction` |

## 14. Future vision — crowdsourced item enrichment & reputation

> **Post-MVP, directional.** Captured so we don't design the foundations into a corner. The MVP already accommodates it: `credit_ledger.reason` is an extensible enum, `users.trust_score` exists, and `products` + `raw_text_mappings` establish the crowdsourcing pattern. No MVP changes needed.

Beyond receipts, SummPrices can become a **crowdsourced product-knowledge graph** — users earn credit not only for scanning but for *enriching* items, can *request* information, and a reputation system makes the data hard to corrupt.

- **Contributions (earn credit by enriching an item):** ingredients-list photo, a general product photo, weight / dimensions, a manual (furniture / Lego), etc. → a flexible `item_contributions` table (`product_id`, `attribute_type`, value / `asset_key`, `contributed_by`, `confidence`, verification status). Typed, so new attribute types are config, not migrations.
- **Requests & demand-driven bounties:** users *request* a missing attribute (`info_requests`); **reward scales with demand** (more distinct requesters for the same attribute → higher credit) **and difficulty** (a photo is easy; provenance is hard). Fulfilment credits the contributor via a new `credit_ledger.reason` (`contribution_reward` / `bounty_reward`).
- **Trust & truth-over-time (weighted truth discovery):** model it as **Dawid–Skene-style weighted consensus** — a periodic batch EM job over all contributions jointly infers each claim's most-likely value **+ a confidence** *and* each contributor's reliability. `trust_score` = a contributor's estimated reliability, earned from **how often their past contributions match the inferred truth** as data accumulates. Output is **value + confidence, never a binary** (the confidence is itself a B2B selling point). *Research-grade (Sybil/collusion resistance, convergence) — phase it: simple corroboration first, then a proper statistical model. Frameworks: Dawid–Skene + Bayesian variants, truth-discovery (TruthFinder / CRH / CATD), IRT ability/difficulty models, Beta-reputation / EigenTrust.*
- **KYC as a weight, not an oracle:** KYC gives a user a **high prior weight** in the consensus and unlocks a higher earning tier (+ a signup bonus) — but a KYC user is **still updated by their own track record** and can be wrong. **Guardrails:** require *multiple independent* high-trust confirmations before a claim is "near-true"; **cap any single actor's weight**; detect collusion (correlated voting clusters); **don't hard-punish disagreement** (the minority is sometimes right — let truth shift over time). Non-KYC users' reliability is calibrated from agreement with the trust-weighted consensus. Progressive: **basic scanning/earning stays open** (KYC would kill the funnel); KYC gates only high-value contributions / cash-out / elevated trust. Provider-based (Vipps / BankID in NO; Stripe Identity abroad), storing only `kyc_status` + a reference — **never** ID documents.
- **Reward = value of information:** credit ≈ **demand × difficulty × info-gain × contributor-weight** — pay most for the validation that most reduces a claim's uncertainty (e.g. a scarce KYC confirmation of a claim many anonymous users asserted — the user's original instinct, generalized). Objective attributes (weight, ingredients-as-printed, barcode) converge well; subjective / hard-to-verify ones (country-of-origin / provenance) don't — keep those low-confidence or deferred.
- **Anti-gaming:** fake requests, collusion rings, and self-fulfilment are resisted by KYC + `trust_score` weighting + rate limits + the same idempotent, auditable `credit_ledger`.

**Future tables:** `item_contributions`, `contribution_types`, `info_requests` (+ demand count), `contribution_verifications`; KYC fields on `users` (`kyc_status`, `kyc_ref`); new `credit_ledger.reason` values.
