-- Laser Test Station: SQL Server schema (central database)
-- Mirrors sql/schema.sql (SQLite). Safe to run more than once.
-- Run with:  sqlcmd -S lpc:.\SQLEXPRESS -E -i sql\schema_mssql.sql

IF DB_ID(N'LTS') IS NULL
    CREATE DATABASE LTS;
GO
USE LTS;
GO

IF OBJECT_ID(N'dbo.stations', N'U') IS NULL
CREATE TABLE dbo.stations (
    station_id  INT IDENTITY(1,1) PRIMARY KEY,
    name        NVARCHAR(64)  NOT NULL UNIQUE,
    location    NVARCHAR(128) NULL
);
GO

IF OBJECT_ID(N'dbo.units', N'U') IS NULL
CREATE TABLE dbo.units (
    unit_id        INT IDENTITY(1,1) PRIMARY KEY,
    serial_number  NVARCHAR(64) NOT NULL UNIQUE,
    product        NVARCHAR(64) NOT NULL
);
GO

IF OBJECT_ID(N'dbo.limits', N'U') IS NULL
CREATE TABLE dbo.limits (
    product  NVARCHAR(64) NOT NULL,
    param    NVARCHAR(64) NOT NULL,      -- 'ith_a', 'slope_w_per_a'
    low      FLOAT NULL,
    high     FLOAT NULL,
    rev      NVARCHAR(16) NOT NULL,
    CONSTRAINT pk_limits PRIMARY KEY (product, param, rev)
);
GO

IF OBJECT_ID(N'dbo.test_runs', N'U') IS NULL
CREATE TABLE dbo.test_runs (
    run_id         INT IDENTITY(1,1) PRIMARY KEY,
    unit_id        INT NOT NULL REFERENCES dbo.units(unit_id),
    station_id     INT NOT NULL REFERENCES dbo.stations(station_id),
    local_run_id   BIGINT NULL,              -- run_id in the station's SQLite file (store-and-forward)
    started_at     DATETIME2(0) NOT NULL,    -- UTC
    ended_at       DATETIME2(0) NULL,
    sw_version     NVARCHAR(32) NOT NULL,
    limits_rev     NVARCHAR(16) NULL,
    operator       NVARCHAR(64) NULL,
    setpoint_c     FLOAT NULL,
    ith_a          FLOAT NULL,
    slope_w_per_a  FLOAT NULL,
    pass           BIT NULL,                 -- 1 pass, 0 fail, NULL aborted
    abort_reason   NVARCHAR(400) NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_runs_station_time')
    CREATE INDEX ix_runs_station_time ON dbo.test_runs(station_id, started_at) INCLUDE (pass);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_runs_unit')
    CREATE INDEX ix_runs_unit ON dbo.test_runs(unit_id);
-- One central row per station-local run (makes sync idempotent); NULLs allowed for direct writes
IF EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = N'uq_station_local_run')
    ALTER TABLE dbo.test_runs DROP CONSTRAINT uq_station_local_run;
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_station_local_run')
    CREATE UNIQUE INDEX ux_station_local_run ON dbo.test_runs(station_id, local_run_id)
        WHERE local_run_id IS NOT NULL;
GO

IF OBJECT_ID(N'dbo.measurements', N'U') IS NULL
CREATE TABLE dbo.measurements (
    run_id      INT NOT NULL REFERENCES dbo.test_runs(run_id),
    seq         INT NOT NULL,
    current_a   FLOAT NOT NULL,
    power_w     FLOAT NOT NULL,
    temp_c      FLOAT NULL,
    daq_temp_c  FLOAT NULL,
    t_s         FLOAT NULL,
    CONSTRAINT pk_measurements PRIMARY KEY (run_id, seq)
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.stations WHERE name = N'LTS-01')
    INSERT INTO dbo.stations(name, location) VALUES (N'LTS-01', N'Lab 2');
IF NOT EXISTS (SELECT 1 FROM dbo.limits WHERE product = N'DL-6W' AND rev = N'A')
    INSERT INTO dbo.limits(product, param, low, high, rev) VALUES
        (N'DL-6W', N'ith_a',         NULL, 0.60, N'A'),
        (N'DL-6W', N'slope_w_per_a', 0.90, NULL, N'A');
GO

-- Yield by station and day (the query reporting will use)
CREATE OR ALTER VIEW dbo.v_daily_yield AS
SELECT s.name AS station,
       CAST(r.started_at AS DATE) AS test_date,
       COUNT(*) AS runs,
       SUM(CASE WHEN r.pass = 1 THEN 1 ELSE 0 END) AS passed,
       SUM(CASE WHEN r.pass IS NULL THEN 1 ELSE 0 END) AS aborted,
       CAST(100.0 * SUM(CASE WHEN r.pass = 1 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN r.pass IS NOT NULL THEN 1 ELSE 0 END), 0) AS DECIMAL(5,1)) AS yield_pct
FROM dbo.test_runs r
JOIN dbo.stations s ON s.station_id = r.station_id
GROUP BY s.name, CAST(r.started_at AS DATE);
GO
