-- MD5 hash of the raw Overpass response body at last ingest.
-- Used for change detection: skip re-ingest if hash unchanged.
ALTER TABLE courses ADD COLUMN IF NOT EXISTS overpass_hash TEXT;
