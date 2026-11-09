# Laser Test Station Simulator

A simulated laser production test station built in LabVIEW. All hardware is simulated: a chiller
(functional global variable), a diode laser L-I model with threshold and thermal rollover, a power
meter with gain, offset and noise, and NI-DAQmx on a simulated PCIe-6361 (`Dev1`). The station
stabilizes temperature, sweeps drive current, fits the L-I curve, and makes a pass/fail decision.

## How to run

1. Install NI-DAQmx and create a simulated **PCIe-6361** named `Dev1` in NI MAX:
   *Devices and Interfaces → Create New… → Simulated NI-DAQmx Device or Modular Instrument → PCIe-6361*
2. Install the **SQLite Library** package (VI Package Manager) and the LabVIEW **Database Connectivity Toolkit**.
3. Open `LaserTestStation.lvproj` in LabVIEW 2026 Q3. The project uses separate compiled code, so only source is stored in git.
4. Run `Main.vi` and press **Start**. Each run is written to the local SQLite database `db/lts.db`, which is created on first use.

To forward results to SQL Server (optional):

1. Install SQL Server Express (instance `.\SQLEXPRESS`) and the Microsoft OLE DB Driver for SQL Server (`MSOLEDBSQL`).
2. Create the central database and the sync procedure:
   ```
   sqlcmd -S lpc:.\SQLEXPRESS -E -i sql\schema_mssql.sql
   sqlcmd -S lpc:.\SQLEXPRESS -E -I -i sql\sync_run_mssql.sql
   ```
3. `Main.vi` syncs finished runs at shutdown. To sync manually, run `Data/Sync To Server.vi`.
4. Run `Tests/Daily Yield.vi` to see yield per station per day.

`Tests/Continuous AI.vi` logs to `C:\temp\ai_log.tdms`, so create `C:\temp` before running it.

## Architecture

`Main.vi` is an enum-driven state machine plus a separate logging loop fed by a queue (producer/consumer). Shift registers carry the run state.

```
Idle (event structure) → Initialize → Chiller Stabilize → Current Ramp ⇄ Measure
                                                              ↓
                                     Idle ← Safe Shutdown ← Evaluate
```

### Safety gate

An error, Abort, an open interlock, or over-temperature forces Safe Shutdown. Safe Shutdown sets the laser to 0 A and logs the reason.

### Logging

The state machine (producer) sends log messages through a queue to the logging loop (consumer), which writes one CSV per run to `logs/<serial>_<timestamp>.csv`. Data columns are `current_a,power_w,temp_c,t_s`. Each file ends with a footer line:

```
# pass=<0|1> ith=<A> slope=<W/A> reason=<text>
```

### Results database

Each run is also recorded in a local SQLite database (`db/lts.db`, schema in `sql/schema.sql`):
one `test_runs` row with the fit results and pass/fail or abort reason, plus one `measurements` row per sweep point.
The station keeps working when the central server is unavailable.

### Store-and-forward sync

`Data/Sync To Server.vi` forwards finished, unsynced runs (`ended_at` set, `synced_at` empty) to SQL Server.
`Main.vi` calls it at shutdown, and it can also be run on its own.
For each run it calls the `dbo.sync_run` stored procedure (`sql/sync_run_mssql.sql`) with the run fields and the
measurements as a JSON array, then stamps the local row's `synced_at` with the UTC time in ISO 8601.

- **Idempotent:** the server keys runs on (station, local run ID). Calling `sync_run` again for a run that's already
  on the server returns the existing run and inserts nothing, so a retry never creates duplicates.
- **Atomic:** each run and its measurements are inserted in one transaction (`XACT_ABORT ON`).
- **Verified:** the first sync forwarded 3 runs and a second sync forwarded 0. The server holds one row per local run,
  with every measurement copied.

### Daily yield report

`sql/schema_mssql.sql` defines `dbo.v_daily_yield`, a view of run, pass and abort counts and yield per station per day.
Yield is passed runs divided by completed runs, so aborted runs don't count against it.
`Tests/Daily Yield.vi` queries the view and shows station, date, runs, passed, aborted and yield %.

## Repository contents

| Path | Purpose |
|---|---|
| `Main.vi` | Top-level state machine and logging loop |
| `Typedefs/Station State.ctl` | Enum of state machine states |
| `Typedefs/Test Config.ctl` | Test parameters and limits, including the fit window |
| `Typedefs/Measurement.ctl` | One measurement point |
| `Typedefs/Chiller Action.ctl` | Enum of chiller actions |
| `Typedefs/Log Message Type.ctl` | Enum of log message types |
| `Typedefs/Log Message.ctl` | Message passed through the logging queue |
| `Instruments/Chiller.vi` | Functional global variable, non-reentrant. Actions: Init, Set Setpoint, Step, Read |
| `Instruments/Laser.vi` | L-I model as a pure function, preallocated reentrant |
| `Instruments/Power Meter.vi` | Power reading with gain error, offset and noise |
| `DAQ/DAQ Thermistor.vi` | Finite analog input on `Dev1/ai0`, averaged and scaled to temperature |
| `Tests/Test Chiller.vi` | Chiller settling curve |
| `Tests/Test Li.vi` | L-I curves at 25 °C and 35 °C |
| `Tests/Test All Instruments.vi` | End-to-end instrument run on one error chain |
| `Tests/Continuous AI.vi` | Continuous analog input with TDMS logging and CSV block means |
| `Tests/Triggered AI.vi` | Analog input with a digital-edge start trigger |
| `Tests/View TDMS.vi` | Viewer for logged TDMS files |
| `Tests/Test SQL Server.vi` | Connection check against the central SQL Server database |
| `Tests/Daily Yield.vi` | Daily yield per station from SQL Server |
| `Tests/Scratch*.vi` | Dataflow and loop drills |
| `Data/DB Init.vi` | Opens or creates the local SQLite database |
| `Data/Sync To Server.vi` | Store-and-forward sync of finished runs to SQL Server |
| `sql/schema.sql` | Local SQLite schema |
| `sql/schema_mssql.sql` | Central SQL Server schema and daily yield view |
| `sql/sync_run_mssql.sql` | `dbo.sync_run` stored procedure |

## Test method

1. Wait for the chiller to stabilize within tolerance.
2. Sweep drive current from 0 to 6 A in 0.1 A steps, recording power at each step.
3. Fit the linear region with Linear Fit. The window comes from Test Config (`Fit P Min`, `Fit I Max`).
4. Compute I<sub>th</sub> = −intercept / slope.
5. **PASS** if I<sub>th</sub> ≤ `Ith Max` and slope ≥ `Slope Min`.

**Latest result with default settings:** PASS, I<sub>th</sub> = 0.425 A, slope = 0.908 W/A, peak about 2.78 W near 4.6 A.

## Fault-injection tests

Each case was run through `Main.vi` and checked against the CSV footer.

| Test | Result | Footer |
|---|---|---|
| Normal run | PASS | `pass=1`, I<sub>th</sub> ≈ 0.42 A, slope ≈ 0.91 W/A, empty reason |
| Interlock open | Safe Shutdown | `pass=0 reason=Interlock open` |
| Operator abort | Safe Shutdown | `pass=0 reason=Operator abort` |
| Stabilize timeout | Safe Shutdown, error 5001 | `pass=0 reason=Error 5001: Main.vi` |
| Bad DAQ channel | Safe Shutdown, error −200220 | `pass=0 reason=Error -200220: DAQmx Create Channel…` |
| Spec fail (`Ith Max` = 0.3) | FAIL | `pass=0`, I<sub>th</sub> ≈ 0.42 A, slope ≈ 0.91 W/A, empty reason |
| Over-temperature | Safe Shutdown | `pass=0 reason=Over-temperature` |

## Simulation models

**Chiller:** first-order response toward the setpoint, τ = 30 s, ±0.05 °C noise.

**Diode laser:**

| Quantity | Formula | At 25 °C |
|---|---|---|
| Threshold current I<sub>th</sub> | 0.5 · exp((T − 25) / 100) | 0.50 A |
| Slope efficiency η | 1.0 · (1 − 0.005 · (T − 25)) | 1.00 W/A |
| Output power P | η · x · (1 − 0.02 · x²), x = I − I<sub>th</sub>; 0 when I ≤ I<sub>th</sub> | peaks near 2.7 W at about 4.6 A |

**Power meter:** reading = P · 1.02 + 0.005 W ± 5 mW noise (2% gain error, 5 mW offset).

## Status

Done:

- [x] Type definitions, simulated instruments, DAQmx acquisition
- [x] State machine, event-driven UI, test states, L-I fit
- [x] Safe-shutdown gate: Abort, Interlock, over-temperature and errors always go to Safe Shutdown
- [x] CSV logging in the consumer loop
- [x] Fault-injection tests
- [x] SQLite results database
- [x] SQL Server store-and-forward sync, with sync at shutdown
- [x] Daily yield report

Roadmap:

- [ ] HTML reports

---

*This project was developed with AI assistance.*
