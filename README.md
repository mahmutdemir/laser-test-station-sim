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
| `Typedefs/` | Type definitions shared across VIs (station state enum, test config, measurement clusters) |
| `Instruments/` | Simulated instrument drivers: chiller (functional global), laser model, power meter |
| `DAQ/` | NI-DAQmx acquisition VIs (finite and continuous, TDMS logging) |
| `Sequencer/` | Test sequence state machine |
| `Tests/` | Test harnesses for each instrument and end-to-end runs |
| `Reporting/` | Report generation |
| `Data/` | Runtime output (TDMS/CSV). Ignored by git |

Open `LaserTestStation.lvproj` to get started.

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
- [ ] Simulated instruments (chiller, laser, power meter)
- [ ] DAQmx acquisition and TDMS logging
- [ ] Sequencer state machine
- [ ] Reporting

---

*This project was developed with AI assistance.*
