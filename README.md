# Laser Test Station Simulator

A simulated laser production test station built in LabVIEW. All hardware is simulated: a chiller
(functional global variable), a diode laser L-I model with threshold and thermal rollover, a power
meter with gain, offset and noise, and NI-DAQmx on a simulated PCIe-6361 (`Dev1`). The station
stabilizes temperature, sweeps drive current, fits the L-I curve, and makes a pass/fail decision.

## How to run

1. Install NI-DAQmx and create a simulated **PCIe-6361** named `Dev1` in NI MAX:
   *Devices and Interfaces → Create New… → Simulated NI-DAQmx Device or Modular Instrument → PCIe-6361*
2. Open `LaserTestStation.lvproj` in LabVIEW 2026 Q3. The project uses separate compiled code, so only source is stored in git.
3. Run `Main.vi` and press **Start**.

`Tests/Continuous AI.vi` logs to `C:\temp\ai_log.tdms`, so create `C:\temp` before running it.

## Architecture

`Main.vi` is an enum-driven state machine plus a separate logging loop fed by a queue (producer/consumer). Shift registers carry the run state.

```
Idle (event structure) → Initialize → Chiller Stabilize → Current Ramp ⇄ Measure
                                                              ↓
              Idle ← Safe Shutdown ← Report ← Log ← Evaluate
```

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
| `Tests/Scratch*.vi` | Dataflow and loop drills |

## Test method

1. Wait for the chiller to stabilize within tolerance.
2. Sweep drive current from 0 to 6 A in 0.1 A steps, recording power at each step.
3. Fit the linear region with Linear Fit. The window comes from Test Config (`Fit P Min`, `Fit I Max`).
4. Compute I<sub>th</sub> = −intercept / slope.
5. **PASS** if I<sub>th</sub> ≤ `Ith Max` and slope ≥ `Slope Min`.

**Latest result with default settings:** PASS, I<sub>th</sub> = 0.425 A, slope = 0.908 W/A, peak about 2.78 W near 4.6 A.

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

Roadmap:

- [ ] Safe-shutdown gate: Abort, Interlock, over-temperature and errors always go to Safe Shutdown
- [ ] CSV logging in the consumer loop
- [ ] Fault-injection tests
- [ ] SQLite results database
- [ ] HTML reports
- [ ] Yield query

---

*This project was developed with AI assistance.*
