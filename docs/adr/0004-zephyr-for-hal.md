# 0004 — Use Zephyr RTOS as the HAL layer; retire the bare-metal stub

- **Status:** Accepted
- **Date:** 2026-04-28
- **Deciders:** Mark

## Context

The initial scaffold included a hand-written bare-metal HAL stub at
`src/hal/stm32h5/` that would have driven STM32H5 GPIO, TIM6 (1 kHz tick),
and USART3 directly via CMSIS register definitions or the Ada Drivers
Library. The body was a TODO; nothing real had been written.

Doing the bare-metal port from scratch is a non-trivial amount of work
(clocks, NVIC, GPIO alt-functions, DMA-less UART, watchdog setup) on a
relatively new MCU family where Ada Drivers Library coverage is partial.
None of that work directly advances the project's actual goal — proving
the conflict-check logic and getting a phase sequencer running — and the
work it produces would be a tightly board-coupled HAL that doesn't
trivially carry to other boards.

Zephyr RTOS provides device-tree-driven GPIO, timing, UART, and watchdog
abstractions across hundreds of supported boards, including the
Nucleo-H563ZI. AdaCore ships the `gnat_arm_elf` cross toolchain with
runtimes (`light-cortex-m33f`) compatible with Zephyr's link model.

## Decision

**Use Zephyr as the HAL layer.** The cross-target build is driven by
Zephyr's CMake/west, with gprbuild emitting `libada_app.a` and gnatbind
emitting `ada_bind.o`, both linked into the Zephyr firmware via a C
trampoline (`src/hal/zephyr/ada_main.c`).

The Ada-side HAL spec (`src/hal/zephyr/hal.ads`) is identical to the host
stub spec; the body bridges through small C shims (`hal_zephyr.c`,
`tlc_zephyr_*` symbols) to Zephyr's APIs — most of which are
`static inline` in headers and therefore not directly addressable via
`pragma Import`.

The bare-metal stub at `src/hal/stm32h5/` and the host/target profile
mechanism in `traffic_light.gpr` are **removed**. `traffic_light.gpr`
becomes the host-only build; `traffic_light_zephyr.gpr` is the cross
build.

## Consequences

- Positive: Hardware bring-up is mostly Zephyr's job — board files, device
  trees, GPIO / UART / timer drivers come for free. Project effort goes
  into the Ada logic, not register banging.
- Positive: Same Ada code can target any Zephyr-supported board (other
  Cortex-M variants, RISC-V) by changing the runtime, compiler flags,
  and `BOARD` only.
- Positive: Zephyr provides the watchdog (NFR-RL-02, NFR-RL-03) primitives
  and a logging backend usable for the diagnostic stream (NFR-DG-01).
- Negative: Zephyr is a large dependency. Image footprint and build time
  grow. CI now needs `west`, the Zephyr SDK, and a full clone of the
  Zephyr tree.
- Negative: ABI / FPU / RTS alignment must be maintained across three
  files (GPR compiler flags, CMake binder invocation, `prj.conf`); a
  silent FP-ABI mismatch is the canonical Zephyr-Ada bug.
- Negative: Many Zephyr APIs are `static inline` and can't be reached by
  `pragma Import` directly — every one needs a C shim. Modest
  per-symbol cost but consistent.
- Neutral: ADR-0001 (target hardware: STM32H563ZI) is unaffected. ADR-0002
  (SPARK for conflict-check) is unaffected — the SPARK boundary is in
  `src/core/`, untouched by this decision.
- Neutral: The MMU (external safety supervisor in
  `docs/safety/hazard-analysis.md`) remains an independent channel —
  Zephyr is the single-channel software layer, not a substitute for the
  MMU.

## Alternatives considered

- **Continue with the bare-metal stub.** Lowest binary footprint, full
  control, no RTOS overhead. Rejected: the implementation cost is large
  and orthogonal to the project's safety/proof goals; it locks the
  controller to STM32H5; it needs a watchdog/clocks/UART implementation
  that Zephyr already ships.
- **Use the Ada Drivers Library directly without an RTOS.** Smaller than
  Zephyr, idiomatic Ada bindings. Rejected: H5 coverage is partial and
  trails the F4/F7 family; we'd still hand-roll watchdog, scheduling,
  and logging.
- **Use FreeRTOS or another minimal RTOS.** Smaller than Zephyr, but
  AdaCore tooling and recent integration work targets Zephyr; the
  ecosystem fit is weaker.

## References

- alire skill `zephyr.md` (the build pattern this ADR commits to).
- ADR-0001 (target hardware) — unchanged.
- ADR-0002 (SPARK use) — unchanged.
- `CMakeLists.txt`, `traffic_light_zephyr.gpr`, `src/hal/zephyr/`.
