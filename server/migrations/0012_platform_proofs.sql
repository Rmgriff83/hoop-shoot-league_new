-- Game Center identity proofs are taken once (docs/BACKEND.md → Platform
-- identity): /v1/link/restore needs no bearer, so a replayed signature within
-- its freshness window would be an account takeover. The verifier inserts the
-- signature's SHA-256 here after it checks out; a second insert fails → 401.
-- The daily cron drops rows older than the window (db.ts prune).
CREATE TABLE IF NOT EXISTS platform_proofs (
  sig_hash  TEXT PRIMARY KEY,
  seen_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS platform_proofs_seen ON platform_proofs (seen_at);
