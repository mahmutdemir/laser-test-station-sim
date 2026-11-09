-- Laser Test Station: store-and-forward sync procedure (SQL Server)
-- One call per finished station run. Idempotent: calling twice for the same
-- (station, local_run_id) returns the existing central run_id and inserts nothing.
-- Run with:  sqlcmd -S lpc:.\SQLEXPRESS -E -I -i sql\sync_run_mssql.sql
USE LTS;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE dbo.sync_run
    @station_name       NVARCHAR(64),
    @local_run_id       BIGINT,
    @serial_number      NVARCHAR(64),
    @product            NVARCHAR(64),
    @started_at         NVARCHAR(40),      -- ISO 8601 UTC text from SQLite, e.g. 2026-11-05T21:25:48Z
    @ended_at           NVARCHAR(40),
    @sw_version         NVARCHAR(32),
    @limits_rev         NVARCHAR(16),
    @operator           NVARCHAR(64),
    @setpoint_c         NVARCHAR(40),      -- numbers arrive as text; '' means NULL
    @ith_a              NVARCHAR(40),
    @slope_w_per_a      NVARCHAR(40),
    @pass               NVARCHAR(8),       -- '1', '0' or '' (aborted)
    @abort_reason       NVARCHAR(400),
    @measurements_json  NVARCHAR(MAX)      -- [[seq,current_a,power_w,temp_c,t_s], ...]
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;    -- any error rolls back the whole run

    DECLARE @station_id INT = (SELECT station_id FROM dbo.stations WHERE name = @station_name);
    IF @station_id IS NULL
        THROW 50001, 'sync_run: unknown station name', 1;

    DECLARE @run_id INT = (SELECT run_id FROM dbo.test_runs
                           WHERE station_id = @station_id AND local_run_id = @local_run_id);
    IF @run_id IS NOT NULL
    BEGIN
        SELECT @run_id AS run_id, CAST(1 AS BIT) AS already_synced;
        RETURN;
    END

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.units WHERE serial_number = @serial_number)
        INSERT INTO dbo.units(serial_number, product) VALUES (@serial_number, @product);
    DECLARE @unit_id INT = (SELECT unit_id FROM dbo.units WHERE serial_number = @serial_number);

    INSERT INTO dbo.test_runs(unit_id, station_id, local_run_id, started_at, ended_at, sw_version,
                              limits_rev, operator, setpoint_c, ith_a, slope_w_per_a, pass, abort_reason)
    VALUES (@unit_id, @station_id, @local_run_id,
            CAST(CAST(@started_at AS DATETIMEOFFSET) AS DATETIME2(0)),
            CAST(CAST(NULLIF(@ended_at, '') AS DATETIMEOFFSET) AS DATETIME2(0)),
            @sw_version,
            NULLIF(@limits_rev, ''),
            NULLIF(@operator, ''),
            TRY_CAST(NULLIF(@setpoint_c, '') AS FLOAT),
            TRY_CAST(NULLIF(@ith_a, '') AS FLOAT),
            TRY_CAST(NULLIF(@slope_w_per_a, '') AS FLOAT),
            TRY_CAST(NULLIF(@pass, '') AS BIT),
            NULLIF(@abort_reason, ''));

    SET @run_id = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.measurements(run_id, seq, current_a, power_w, temp_c, t_s)
    SELECT @run_id, j.seq, j.current_a, j.power_w, j.temp_c, j.t_s
    FROM OPENJSON(NULLIF(@measurements_json, ''))
         WITH (seq INT '$[0]', current_a FLOAT '$[1]', power_w FLOAT '$[2]',
               temp_c FLOAT '$[3]', t_s FLOAT '$[4]') AS j;

    COMMIT TRANSACTION;

    SELECT @run_id AS run_id, CAST(0 AS BIT) AS already_synced;
END
GO
