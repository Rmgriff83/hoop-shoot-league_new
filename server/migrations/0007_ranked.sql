-- 2026-10-19: ranked online (docs/BACKEND.md → Ranked). One global Glicko-2
-- rating per player, the visible tier/division with its shield, floor and peak,
-- the rooms the Lobby paired for ranked play, and what a match did to both ratings.
CREATE TABLE IF NOT EXISTS ratings (
  player_id     TEXT PRIMARY KEY,
  mu            REAL NOT NULL,
  rd            REAL NOT NULL,
  vol           REAL NOT NULL,
  cons          REAL NOT NULL,          -- mu - rd_k*rd, the board's key
  games         INTEGER NOT NULL DEFAULT 0,
  wins          INTEGER NOT NULL DEFAULT 0,
  losses        INTEGER NOT NULL DEFAULT 0,
  win_streak    INTEGER NOT NULL DEFAULT 0,
  loss_streak   INTEGER NOT NULL DEFAULT 0,
  tier          TEXT NOT NULL,
  division      INTEGER NOT NULL,
  peak_tier     TEXT NOT NULL,
  peak_division INTEGER NOT NULL,
  shield_left   INTEGER NOT NULL DEFAULT 0,
  updated_at    INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS ratings_board ON ratings (cons DESC, updated_at ASC);
CREATE TABLE IF NOT EXISTS ranked_rooms (
  room        TEXT PRIMARY KEY,
  area        TEXT NOT NULL,
  a_id        TEXT NOT NULL,
  b_id        TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);
ALTER TABLE matches ADD COLUMN ranked INTEGER NOT NULL DEFAULT 0;
ALTER TABLE matches ADD COLUMN winner TEXT;                 -- a | b | NULL (void)
ALTER TABLE matches ADD COLUMN a_level INTEGER;
ALTER TABLE matches ADD COLUMN b_level INTEGER;
ALTER TABLE matches ADD COLUMN cap INTEGER;
ALTER TABLE matches ADD COLUMN a_mu_before REAL;
ALTER TABLE matches ADD COLUMN a_mu_after REAL;
ALTER TABLE matches ADD COLUMN b_mu_before REAL;
ALTER TABLE matches ADD COLUMN b_mu_after REAL;
