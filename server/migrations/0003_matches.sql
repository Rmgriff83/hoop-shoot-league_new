-- Phase 3: finished online matches (the room writes one row at the end).
CREATE TABLE IF NOT EXISTS matches (
  room      TEXT PRIMARY KEY,
  area      TEXT NOT NULL,
  a_id      TEXT NOT NULL,
  b_id      TEXT NOT NULL,
  a_score   INTEGER NOT NULL,
  b_score   INTEGER NOT NULL,
  ot        INTEGER NOT NULL DEFAULT 0,
  reason    TEXT NOT NULL,            -- played | forfeit | void
  desync    INTEGER NOT NULL DEFAULT 0,
  ended_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS matches_player_a ON matches (a_id, ended_at DESC);
CREATE INDEX IF NOT EXISTS matches_player_b ON matches (b_id, ended_at DESC);
