# Laser Test Station Simulator

A LabVIEW simulation of an automated diode-laser test station. Simulated instruments
(chiller, laser, power meter) and a simulated NI DAQ device stand in for real hardware.
A sequencer will drive them through a full test: stabilize temperature, ramp current,
measure the L-I curve, evaluate pass/fail, then log and report.

## Requirements

- LabVIEW 2026 (26.0). The project uses separate compiled code, so only source is stored in git.
- NI-DAQmx driver
- A simulated **PCIe-6361** named `Dev1`, created in NI MAX:
  *Devices and Interfaces → Create New… → Simulated NI-DAQmx Device or Modular Instrument → PCIe-6361*

## Project layout

| Folder | Contents |
|---|---|
| `Typedefs/` | Type definitions shared across VIs (station state and chiller action enums, test config and measurement clusters) |
| `Instruments/` | Simulated instrument drivers: chiller (functional global), laser model, power meter |
| `DAQ/` | NI-DAQmx acquisition VIs (finite and continuous, TDMS logging) |
| `Sequencer/` | Test sequence state machine |
| `Tests/` | Test harnesses for each instrument and end-to-end runs |
| `Reporting/` | Report generation |
| `Data/` | Runtime output (TDMS/CSV). Ignored by git |

Open `LaserTestStation.lvproj` to get started. All source folders are auto-populating in the project.

## VIs

| VI | Purpose |
|---|---|
| `Instruments/Chiller.vi` | Simulated chiller as a functional global (non-reentrant, state in uninitialized shift registers). Actions: Init, Set Setpoint, Step, Read |
| `Instruments/Laser.vi` | Stateless diode-laser model: power and threshold current from drive current and temperature |
| `Instruments/Power Meter.vi` | Power reading with calibration gain/offset error and noise |
| `DAQ/DAQ Thermistor.vi` | Finite DAQmx acquisition on `Dev1/ai0`, averaged and scaled to temperature |
| `Tests/Test Chiller.vi` | Steps the chiller toward a 25 °C setpoint and charts the settling curve |
| `Tests/Test Li.vi` | Sweeps 0–6 A through Laser + Power Meter and plots L-I curves at 25 °C and 35 °C |
| `Tests/Continuous AI.vi` | Continuous DAQmx acquisition with TDMS logging and per-block CSV means |
| `Tests/Triggered AI.vi` | DAQmx acquisition with a digital-edge start trigger |
| `Tests/View TDMS.vi` | Opens a logged TDMS file for viewing |
| `Tests/Test All Instruments.vi` | End-to-end run: chiller settle, thermistor read, L-I sweep at the chiller temperature, one error chain |
| `Tests/Scratch*.vi` | Dataflow and loop drills |

## Running

1. Create the simulated `Dev1` device (see Requirements).
2. Run `Tests/Test All Instruments.vi` for the full instrument chain, or any single test VI.
3. `Continuous AI.vi` logs to `C:\temp\ai_log.tdms`. Create `C:\temp` first.

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

- [x] Project structure and type definitions
- [x] Simulated instruments (chiller, laser, power meter)
- [x] DAQmx acquisition, triggering, and TDMS/CSV logging
- [ ] Sequencer state machine
- [ ] Reporting

---

*This project was developed with AI assistance.*
