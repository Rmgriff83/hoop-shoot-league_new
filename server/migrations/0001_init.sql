-- Hoop Shoot API, phase 1: anonymous device accounts + per-area time-trial boards.
CREATE TABLE IF NOT EXISTS players (
  id          TEXT PRIMARY KEY,          -- UUIDv4 minted by the device
  secret_hash TEXT NOT NULL,             -- SHA-256 hex of the bearer secret
  name        TEXT NOT NULL,
  tag         TEXT NOT NULL,             -- two digits
  client_id   TEXT NOT NULL,
  created_at  INTEGER NOT NULL,
  last_seen   INTEGER NOT NULL,
  flags       INTEGER NOT NULL DEFAULT 0
);

-- One row per player per area: their best time trial, all time.
CREATE TABLE IF NOT EXISTS tt_best (
  player_id   TEXT NOT NULL,
  area        TEXT NOT NULL,
  score       INTEGER NOT NULL,
  makes       INTEGER NOT NULL,
  attempts    INTEGER NOT NULL,
  swishes     INTEGER NOT NULL,
  best_streak INTEGER NOT NULL,
  played_at   INTEGER NOT NULL,
  run_id      TEXT NOT NULL,
  PRIMARY KEY (player_id, area)
);
CREATE INDEX IF NOT EXISTS tt_best_board ON tt_best (area, score DESC, played_at ASC);

-- One row per player per area per week: their best that week.
CREATE TABLE IF NOT EXISTS tt_week_best (
  player_id   TEXT NOT NULL,
  area        TEXT NOT NULL,
  week        INTEGER NOT NULL,          -- weeks since Monday 1970-01-05 (UTC)
  score       INTEGER NOT NULL,
  makes       INTEGER NOT NULL,
  attempts    INTEGER NOT NULL,
  swishes     INTEGER NOT NULL,
  best_streak INTEGER NOT NULL,
  played_at   INTEGER NOT NULL,
  run_id      TEXT NOT NULL,
  PRIMARY KEY (player_id, area, week)
);
CREATE INDEX IF NOT EXISTS tt_week_board ON tt_week_best (area, week, score DESC, played_at ASC);

-- Every accepted run id, so a resent submission is a no-op (pruned by the cron).
CREATE TABLE IF NOT EXISTS seen_runs (
  run_id      TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL,
  seen_at     INTEGER NOT NULL
);

-- Move-to-new-phone codes.
CREATE TABLE IF NOT EXISTS transfer_codes (
  code        TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL,
  expires_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS transfer_player ON transfer_codes (player_id);

-- Fixed-window counters for the hour/day throttles (docs/BACKEND.md → Throttling).
CREATE TABLE IF NOT EXISTS rl (
  key         TEXT PRIMARY KEY,
  win         INTEGER NOT NULL,
  n           INTEGER NOT NULL
);
