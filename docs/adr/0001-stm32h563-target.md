# 0001 — Target the STM32H563ZI on the Nucleo-H563ZI dev board

- **Status:** Retired (2026-06-16) — the project now targets the Xilinx
  Zynq-7000 (dual-core Cortex-A9), run under QEMU's `xilinx-zynq-a9` machine.
  The STM32H563 is no longer planned. The decision below is kept for history.
- **Date:** 2026-04-27
- **Deciders:** Mark

## Context

Need an MCU and dev board to host the traffic-light controller logic. The
controller itself is light on processing requirements (state machine + GPIO),
but the project also wants headroom for future work: networked diagnostics,
TrustZone-based partitioning of the conflict monitor, secure boot, OTA.

## Decision

Use the **STMicroelectronics Nucleo-H563ZI** development board, featuring the
**STM32H563ZI** (Cortex-M33, 250 MHz, 2 MB flash, 640 KB RAM).

## Consequences

- Positive: Ethernet PHY on board (future networked diagnostics); TrustZone
  available; ST publishes a Safety Manual for the H5 family; well-supported
  by Alire / GNAT cross-toolchain; affordable (~$30).
- Positive: M33 + TrustZone gives a clean architectural option to put the
  conflict monitor in the secure world later.
- Negative: M33 / H5 is newer than F4/F7, so Ada Drivers Library coverage may
  trail behind. Some bindings may need to be hand-rolled from SVD.
- Neutral: Overkill for a single intersection's logic, but the price
  difference vs. an STM32G0 is irrelevant for a one-off.

## Alternatives considered

- **STM32G071 Nucleo** — perfectly adequate for the logic alone, much
  cheaper, but no Ethernet, no TrustZone, less headroom.
- **Raspberry Pi Pico (RP2040)** — cheap and well-supported, but no published
  safety material and weaker fit for the SPARK-on-Cortex-M direction.
- **MAX32xxx (Analog Devices)** — viable, but ST's safety documentation and
  the Ada Drivers Library coverage tilt the choice toward STM32.

## References

- ST Nucleo-H563ZI User Manual (UM3115)
- STM32H563xx Reference Manual (RM0481)
