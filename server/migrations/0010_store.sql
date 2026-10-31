-- 2026-10-31: the ticket store (docs/BACKEND.md → Ticket store). RevenueCat's
-- webhook is the only thing that credits a pack: each delivery is claimed
-- once by its event id, and each sale becomes a `purchases` row waiting for
-- the phone's CLAIM (the /v1/rewards/claim pattern — the wallet lives on the
-- phone). A transaction is unique per store, so a re-delivered sale under a
-- new event id (a restore) cannot credit twice. A refund marks the row; an
-- unclaimed refund is never credited, a claimed one is not clawed back.
CREATE TABLE IF NOT EXISTS store_events (
  id          TEXT PRIMARY KEY,      -- RevenueCat event id (retries reuse it)
  type        TEXT NOT NULL,
  received_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS purchases (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id      TEXT NOT NULL,
  product_id     TEXT NOT NULL,      -- tickets_300 | tickets_1000 (data/store.json)
  store          TEXT NOT NULL,      -- APP_STORE | PLAY_STORE | TEST_STORE | …
  transaction_id TEXT NOT NULL,      -- the store's id (StoreKit transaction / Play order)
  environment    TEXT NOT NULL,      -- SANDBOX | PRODUCTION
  tickets        INTEGER NOT NULL,   -- what the pack credits, from data/store.json at the time
  price          REAL,               -- USD, as RevenueCat reports it
  currency       TEXT,
  country        TEXT,
  purchased_at   INTEGER NOT NULL,
  event_id       TEXT NOT NULL,
  created_at     INTEGER NOT NULL,
  claimed_at     INTEGER,            -- the phone took the tickets
  refunded_at    INTEGER,            -- a CANCELLATION arrived
  UNIQUE (store, transaction_id)
);
CREATE INDEX IF NOT EXISTS purchases_player ON purchases (player_id, claimed_at);
