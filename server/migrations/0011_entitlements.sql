-- Entitlements (docs/BACKEND.md → Ticket store → Entitlements): what a
-- player OWNS from a one-time purchase (remove_ads), as opposed to the
-- credit-once ticket packs in `purchases`. One row per store transaction
-- (a re-delivered restore is stopped by the key); a refund revokes it; a
-- RevenueCat TRANSFER moves live rows to the new player id.
CREATE TABLE IF NOT EXISTS entitlements (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id      TEXT NOT NULL,
  key            TEXT NOT NULL,         -- the entitlement key (remove_ads)
  product_id     TEXT NOT NULL,
  store          TEXT NOT NULL,
  transaction_id TEXT NOT NULL,
  environment    TEXT NOT NULL,
  granted_at     INTEGER NOT NULL,
  event_id       TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  revoked_at     INTEGER,
  UNIQUE (store, transaction_id)
);
CREATE INDEX IF NOT EXISTS entitlements_player ON entitlements (player_id, revoked_at);
