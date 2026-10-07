-- Phase 3b: the online card ledger (docs/BACKEND.md → Cards online).
ALTER TABLE players ADD COLUMN level INTEGER NOT NULL DEFAULT 1;

CREATE TABLE IF NOT EXISTS online_wallet (
  player_id  TEXT PRIMARY KEY,
  coins      INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS online_cards (
  player_id  TEXT NOT NULL,
  card_id    TEXT NOT NULL,
  n          INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (player_id, card_id)
);

-- Every coin and card movement, for the books (pruned after 90 days).
CREATE TABLE IF NOT EXISTS online_ledger (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  player_id  TEXT NOT NULL,
  kind       TEXT NOT NULL,          -- buy | reward | play
  card_id    TEXT,
  coins      INTEGER NOT NULL DEFAULT 0,
  room       TEXT,
  at         INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS online_ledger_player ON online_ledger (player_id, at DESC);
