# Architecture Overview

## Layered structure

The project structure is as follows:

Native application:

```
traffic_light.gpr: The application.                Sources: src/app/
  ├── src/core.gpr: The core logic (SPARK target)  Sources: src/core/
  └── src/hal_host.gpr: The host HAL               Sources: src/hal/host/
```

Target application (bare-metal arm-eabi cross build):

```
traffic_light_qemu/traffic_light_qemu.gpr: The application. Sources: src/app/
  ├── src/core.gpr: The core logic (SPARK target)           Sources: src/core/
  └── src/hal_target.gpr: The QEMU HAL                      Sources: src/hal/qemu_mps2/
```

## Design rules

The `.gpr` files enforce the following rules:

1. **Core depends on nothing.** The core layer has no `with` clauses pointing
   into the HAL. It defines abstract operations (read button state, set lamp
   output) as types and procedures with no implementation, deferred to the
   HAL. This keeps the core fully testable on a native host and provable in SPARK.
2. **HAL implements core's abstractions.** Both `hal_host.gpr` and `hal_target.gpr`
   HAL variants provide the same interface. `hal_target.gpr` drives the QEMU mps2-an385
   peripherals (UART, SysTick) directly.
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
