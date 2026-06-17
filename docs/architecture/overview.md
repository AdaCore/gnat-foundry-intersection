# Architecture Overview

## Layered structure

```
┌────────────────────────────────────────────────────────────┐
│  Application      src/app/                                 │
│    main.adb, diagnostics.adb                               │
├────────────────────────────────────────────────────────────┤
│  Core (pure logic, host-buildable, SPARK-targetable)       │
│    src/core/                                               │
│    ├── conflict_check     (SPARK proof target)             │
│    ├── phase_sequencer    (state machine)                  │
│    ├── pedestrian         (WALK / FDW / DW)                │
│    └── timing             (build-time constants)           │
├────────────────────────────────────────────────────────────┤
│  HAL (board-specific, thin)                                │
│    src/hal/qemu_zynq7000/ (bare-metal arm-eabi; Cortex-A9) │
│    src/hal/host/      (stub for laptop / unit tests)       │
└────────────────────────────────────────────────────────────┘
```

## Design rules

1. **Core depends on nothing.** The core layer has no `with` clauses pointing
   into the HAL. It defines abstract operations (read button state, set lamp
   output) as types and procedures with no implementation, deferred to the
   HAL. This keeps the core fully testable on a laptop and provable in SPARK.
2. **HAL implements core's abstractions.** Both `qemu_zynq7000` and `host`
   HAL variants provide the same package spec (just different bodies). For
   the host build, `traffic_light.gpr` selects `src/hal/host`. For the
   bare-metal arm-eabi cross-build, the sibling `traffic_light_qemu` crate
   selects `src/hal/qemu_zynq7000`, whose body drives the QEMU
   xilinx-zynq-a9 peripherals (Cadence UART) directly and takes its 1 ms
   tick from Ada.Real_Time on the light-tasking-zynq7000 runtime.
3. **App orchestrates.** `main.adb` initializes the HAL, then drives the
   core state machine on a periodic tick.

## Concurrency model

- **Single task** for v0.1 (no Ravenscar / Jorvik tasking yet).
- Periodic 1 kHz tick from a hardware timer interrupt (host: monotonic
  timer thread).
- ISR posts a tick event; the main loop drains events and steps the state
  machine.
- This keeps the SPARK proof obligations on the core simple — no shared
  mutable state, no protected objects in v0.1.

## Why this layering

The conflict-check module is the proof target. Keeping it in `src/core/`
with no HAL dependencies means `gnatprove` can analyze it without dealing
with hardware-specific SVD bindings, vendor headers, or volatile-memory
quirks.

When we later want to prove the **whole sequencer** (not just the conflict
check), the same layering pays off: we only have to abstract the I/O
boundary, not also disentangle the logic from device drivers.

## State machine

See [`state-machine.md`](state-machine.md) for the phase state machine
diagram and transition table.

## Diagnostics

See **NFR-DG-01** and **NFR-DG-02**. The diagnostic stream is a simple
line-oriented protocol on UART:

```
TICK <ms>
PHASE <id> <duration_ms>
PED_REQ <crosswalk> <state>
FAULT <code> <details>
```

The host HAL writes these to stdout; the bare-metal arm-eabi HAL writes
them to the QEMU xilinx-zynq-a9 UART0 (diagnostics channel), with UART1
reserved for the wire-protocol command stream.
