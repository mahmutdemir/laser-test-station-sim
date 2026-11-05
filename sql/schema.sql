PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

CREATE TABLE IF NOT EXISTS stations (
  station_id   INTEGER PRIMARY KEY,
  name         TEXT NOT NULL UNIQUE,
  location     TEXT
);

CREATE TABLE IF NOT EXISTS units (
  unit_id        INTEGER PRIMARY KEY,
  serial_number  TEXT NOT NULL UNIQUE,
  product        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS limits (
  product  TEXT NOT NULL,
  param    TEXT NOT NULL,          -- 'ith_a', 'slope_w_per_a'
  low      REAL,
  high     REAL,
  rev      TEXT NOT NULL,
  PRIMARY KEY (product, param, rev)
);

CREATE TABLE IF NOT EXISTS test_runs (
  run_id         INTEGER PRIMARY KEY,
  unit_id        INTEGER NOT NULL REFERENCES units(unit_id),
  station_id     INTEGER NOT NULL REFERENCES stations(station_id),
  started_at     TEXT NOT NULL,    -- ISO 8601, UTC
  ended_at       TEXT,
  sw_version     TEXT NOT NULL,
  limits_rev     TEXT,
  operator       TEXT,
  setpoint_c     REAL,
  ith_a          REAL,
  slope_w_per_a  REAL,
  pass           INTEGER,          -- 1 pass, 0 fail, NULL aborted
  abort_reason   TEXT
);
CREATE INDEX IF NOT EXISTS ix_runs_station_time ON test_runs(station_id, started_at);
CREATE INDEX IF NOT EXISTS ix_runs_unit ON test_runs(unit_id);

CREATE TABLE IF NOT EXISTS measurements (
  run_id      INTEGER NOT NULL REFERENCES test_runs(run_id),
  seq         INTEGER NOT NULL,
  current_a   REAL NOT NULL,
  power_w     REAL NOT NULL,
  temp_c      REAL,
  daq_temp_c  REAL,
  t_s         REAL,
  PRIMARY KEY (run_id, seq)
);

INSERT OR IGNORE INTO stations(name, location) VALUES ('LTS-01', 'Lab 2');
INSERT OR IGNORE INTO limits VALUES
  ('DL-6W', 'ith_a',          NULL, 0.60, 'A'),
  ('DL-6W', 'slope_w_per_a',  0.90, NULL, 'A');
