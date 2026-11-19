-- Last Light island server schema (Turso / libSQL).
-- Apply with:  turso db shell <your-db> < schema.sql

CREATE TABLE IF NOT EXISTS players (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  created_at  INTEGER NOT NULL
);

-- One row per life. `days` is filled in when the survivor dies.
CREATE TABLE IF NOT EXISTS runs (
  id          TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id),
  seed        INTEGER NOT NULL,
  started_at  INTEGER NOT NULL,
  ended_at    INTEGER,
  days        INTEGER,
  cause       TEXT
);
CREATE INDEX IF NOT EXISTS runs_seed ON runs (seed, days);

-- Everything survivors leave behind on an island.
CREATE TABLE IF NOT EXISTS traces (
  id           TEXT PRIMARY KEY,
  seed         INTEGER NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('grave', 'note', 'stash', 'camp')),
  player_id    TEXT NOT NULL REFERENCES players(id),
  player_name  TEXT NOT NULL,
  x            INTEGER NOT NULL,
  y            INTEGER NOT NULL,
  text         TEXT NOT NULL DEFAULT '',
  items        TEXT,
  days         INTEGER,
  created_at   INTEGER NOT NULL,
  taken_by     TEXT,
  taken_at     INTEGER
);
CREATE INDEX IF NOT EXISTS traces_seed ON traces (seed, created_at);
CREATE INDEX IF NOT EXISTS traces_player ON traces (player_id, seed, kind);

-- Accounts and cloud saves. The Worker also creates these on demand
-- (see LATER_TABLES in src/app.js), so older databases don't need a migration.
CREATE TABLE IF NOT EXISTS accounts (
  player_id     TEXT PRIMARY KEY REFERENCES players(id),
  username      TEXT NOT NULL,
  username_key  TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  salt          TEXT NOT NULL,
  iterations    INTEGER NOT NULL,
  created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  token_hash  TEXT PRIMARY KEY,
  player_id   TEXT NOT NULL REFERENCES players(id),
  created_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS saves (
  player_id   TEXT PRIMARY KEY REFERENCES players(id),
  data        TEXT NOT NULL,
  saved_at    REAL NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS login_failures (
  username_key TEXT NOT NULL,
  at           INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS login_failures_key ON login_failures (username_key, at);
