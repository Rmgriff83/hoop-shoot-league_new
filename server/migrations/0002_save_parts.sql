-- Phase 2: the cloud save mirror. One gzipped whole-part snapshot per player per part.
CREATE TABLE IF NOT EXISTS save_parts (
  player_id   TEXT NOT NULL,
  part        TEXT NOT NULL,
  updated_at  INTEGER NOT NULL,   -- the part's own updatedAt (ms), the LWW key
  size        INTEGER NOT NULL,   -- gzipped bytes
  body        BLOB NOT NULL,
  stored_at   INTEGER NOT NULL,
  PRIMARY KEY (player_id, part)
);
