-- Richer extraction fields (see DESIGN §6 JSON v2). Non-destructive add-columns.
ALTER TABLE receipts     ADD COLUMN receipt_number TEXT;   -- bong-nr, for dedup/uniqueness
ALTER TABLE transactions ADD COLUMN product_code  TEXT;    -- EAN/barcode when printed (seeds product identity)
