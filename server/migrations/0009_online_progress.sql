-- 2026-10-23: ranked Stage B (docs/BACKEND.md → Ranked → Stage B). Per-player
-- online progress (the drop meter, cumulative login days, the played-loss
-- streak), server grants waiting for a CLAIM (logins, welcome back,
-- milestones — idempotent by key), what each match paid, and the cards each
-- side played (the spoils).
CREATE TABLE IF NOT EXISTS online_progress (
  player_id          TEXT PRIMARY KEY,
  meter              INTEGER NOT NULL DEFAULT 0,
  login_days         INTEGER NOT NULL DEFAULT 0,
  last_login_day     INTEGER NOT NULL DEFAULT 0,   -- UTC day number (ms / 86 400 000)
  last_seen_day      INTEGER NOT NULL DEFAULT 0,
  first_win_day      INTEGER NOT NULL DEFAULT 0,
  loss_streak_played INTEGER NOT NULL DEFAULT 0,
  streak_card_day    INTEGER NOT NULL DEFAULT 0,
  updated_at         INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS grants (
  player_id   TEXT NOT NULL,
  key         TEXT NOT NULL,              -- login_day_7 | welcome_back_20750 | first_ranked_win | tier_pro | …
  kind        TEXT NOT NULL,              -- login | welcome_back | milestone
  card_id     TEXT NOT NULL,
  granted_at  INTEGER NOT NULL,
  claimed_at  INTEGER,
  PRIMARY KEY (player_id, key)
);
ALTER TABLE players ADD COLUMN login_day INTEGER NOT NULL DEFAULT 0;
ALTER TABLE matches ADD COLUMN pay INTEGER NOT NULL DEFAULT 1;   -- 0: the same-opponent cap held back spoils and the meter
ALTER TABLE matches ADD COLUMN a_played TEXT;                    -- JSON list of card ids the side played
ALTER TABLE matches ADD COLUMN b_played TEXT;
