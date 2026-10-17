-- Platform identity prep (docs/BACKEND.md → Platform identity): a Game Center
-- or Play Games identity may be linked to one player, and a player holds a
-- secret per device so a platform restore on a second phone keeps the first
-- phone signed in (the transfer code still replaces every secret).

-- provider: 'gamecenter' | 'playgames' ('test' only in the Vitest env).
-- subject: the stable platform player id — Apple's teamPlayerID (the one the
-- identity-verification signature covers), Google's per-game Play Games
-- player id. meta: JSON (Apple's gamePlayerID, a display name) — never a proof.
CREATE TABLE IF NOT EXISTS player_identities (
  provider   TEXT NOT NULL,
  subject    TEXT NOT NULL,
  player_id  TEXT NOT NULL,
  linked_at  INTEGER NOT NULL,
  meta       TEXT,
  PRIMARY KEY (provider, subject),
  UNIQUE (player_id, provider)
);
CREATE INDEX IF NOT EXISTS player_identities_player ON player_identities (player_id);

-- One row per device secret (SHA-256 hex); capped at MAX_SECRETS in auth.ts.
-- players.secret_hash stays as the first secret's copy; auth reads this table.
CREATE TABLE IF NOT EXISTS player_secrets (
  player_id    TEXT NOT NULL,
  secret_hash  TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  last_seen    INTEGER NOT NULL,
  label        TEXT,                 -- first | transfer | gamecenter | playgames | test
  PRIMARY KEY (player_id, secret_hash)
);
CREATE INDEX IF NOT EXISTS player_secrets_player ON player_secrets (player_id);

INSERT OR IGNORE INTO player_secrets (player_id, secret_hash, created_at, last_seen, label)
  SELECT id, secret_hash, created_at, last_seen, 'first' FROM players;
