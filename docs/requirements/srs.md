---
title: "Traffic Light Controller — Software Requirements Specification"
subtitle: "Four-Way Intersection with Pedestrian Crossings"
version: "0.2"
status: "Draft"
author: "Mark"
date: "2026-06-02"
---

# 1. Introduction

## 1.1 Purpose

This document specifies the functional and non-functional requirements for a
basic four-way intersection traffic light controller with dedicated left-turn
phases and concurrent pedestrian crossings on each of the four crosswalks.
It is intended as a learning / hobby project on an STM32H563ZI Nucleo board,
with an architecture amenable to formal verification of the conflict-detection
logic in SPARK.

## 1.2 Scope

The system controls vehicle and pedestrian signals at a single isolated
intersection of two two-way roads, designated **North-South (NS)** and
**East-West (EW)**. It does **not** address coordination with adjacent
intersections, emergency vehicle preemption, or transit signal priority. It
is **not intended for deployment on public roads**.

## 1.3 Definitions

- **Phase** — a contiguous interval during which a particular set of movements
  is permitted.
- **Movement** — a directional traffic flow (e.g., NS-through, EW-left).
- **Conflict** — a pair of movements that must never receive simultaneous
  green or WALK indications.
- **All-red clearance** — an interval during which all vehicle indications
  are red.
- **MMU** — Malfunction Management Unit; an external supervisor that forces
  fail-safe behavior on detected conflicts.
- **WALK / FDW / DW** — pedestrian indications: WALK (steady), Flashing
  Don't Walk, steady Don't Walk.

## 1.4 References

- STM32H563xx Reference Manual (RM0481), STMicroelectronics.
- Nucleo-H563ZI User Manual (UM3115), STMicroelectronics.
- EN 12675:2017, Traffic signal controllers — Functional safety requirements
  (informative).
- NEMA TS-2-2021, Traffic Controller Assemblies (informative).

## 1.5 Quality Attributes

Every requirement in this document conforms to the meta-requirements checklist
defined in [`meta-requirements.md`](meta-requirements.md) (MR-01 through
MR-07). Each requirement carries a `[verification-method]` tag per MR-07;
see that document for the tag definitions.

# 2. System Overview

## 2.1 Intersection layout

Two two-way roads cross at a right angle. Each approach (N, S, E, W) has
dedicated through and left-turn signal heads, and each of the four corners
is connected by a marked crosswalk with its own pedestrian signal head and
request button.

## 2.2 Operational concept

The controller runs a deterministic phase sequence. Pedestrian phases run
concurrently with the parallel through phase when a request has been
registered for the corresponding crosswalk. Left-turn phases run only when
demand is present (in this version, demand is assumed to be detected by a
vehicle-presence input, abstracted as always-true unless otherwise
configured).

## 2.3 Phase sequence

The nominal sequence is shown below. Steps that depend on demand are skipped
when no demand is registered.

| #  | Phase                                | Concurrent Pedestrian            | Duration            |
|----|--------------------------------------|----------------------------------|---------------------|
| 1  | NS Left-turn green (if demanded)     | —                                | T_lt_g              |
| 2  | NS Left-turn yellow                  | —                                | T_y                 |
| 3  | All-red clearance                    | —                                | T_ar                |
| 4  | NS Through green                     | Ped-NS WALK then FDW (if req.)   | ≥ T_min_g, ≤ T_max_g |
| 5  | NS Through yellow                    | —                                | T_y                 |
| 6  | All-red clearance                    | —                                | T_ar                |
| 7  | EW Left-turn green (if demanded)     | —                                | T_lt_g              |
| 8  | EW Left-turn yellow                  | —                                | T_y                 |
| 9  | All-red clearance                    | —                                | T_ar                |
| 10 | EW Through green                     | Ped-EW WALK then FDW (if req.)   | ≥ T_min_g, ≤ T_max_g |
| 11 | EW Through yellow                    | —                                | T_y                 |
| 12 | All-red clearance                    | —                                | T_ar                |

# 3. Functional Requirements

## 3.1 Phase control

- **FR-PH-01** `[test]` The controller shall execute the phase sequence
  defined in Section 2.3 in the order listed.
- **FR-PH-02** `[test]` The controller shall skip any left-turn phase for
  which no left-turn demand is registered at the moment that phase would
  begin.
- **FR-PH-03** `[test]` The controller shall hold each through-phase green
  for at least `T_min_g` and no more than `T_max_g`.
- **FR-PH-04** `[test]` The controller shall transition from green to red on
  a vehicle phase only via an intermediate yellow interval of duration `T_y`.
- **FR-PH-05** `[test]` The controller shall apply an all-red clearance of
  duration `T_ar` between every consecutive pair of vehicle phases.
- **FR-PH-06** `[test]` The controller shall not begin a new phase before the
  all-red clearance of the previous phase has elapsed.

## 3.2 Pedestrian control

- **FR-PD-01** `[hw-test]` The controller shall register a pedestrian request
  when the corresponding crosswalk button is pressed and held for at least
  50 ms (debounced).
- **FR-PD-02** `[test]` Once registered, a pedestrian request shall remain
  latched until the corresponding pedestrian phase has been served.
- **FR-PD-03** `[test]` The Ped-NS phase shall be served concurrently with
  the NS-through green when a Ped-NS request is latched at the start of that
  phase.
- **FR-PD-04** `[test]` The Ped-EW phase shall be served concurrently with
  the EW-through green when a Ped-EW request is latched at the start of that
  phase.
- **FR-PD-05** `[test]` A pedestrian phase shall present steady WALK for
  `T_walk`, followed by flashing DON'T WALK for `T_fdw`, followed by steady
  DON'T WALK.
- **FR-PD-06** `[test]` The corresponding through-phase green shall not
  terminate before the steady WALK + flashing DON'T WALK interval
  (`T_walk + T_fdw`) has elapsed when a pedestrian phase is being served.
- **FR-PD-07** `[test]` Pressing a pedestrian button while the corresponding
  pedestrian phase is already active shall have no effect.
- **FR-PD-08** `[hw-test]` The controller shall provide visible
  acknowledgement (e.g., a button-mounted indicator) that a request has been
  registered.

## 3.3 Safety logic

- **FR-SF-01** `[proof]` The controller shall never simultaneously assert
  green or yellow indications on any pair of conflicting movements as defined
  in the conflict matrix in [`conflict-matrix.md`](conflict-matrix.md).
- **FR-SF-02** `[proof]` The controller shall never assert WALK on a
  pedestrian crosswalk while any conflicting vehicle movement is showing
  green or yellow.
- **FR-SF-03** `[test]` On startup, the controller shall display
  all-flashing-red on every vehicle indication for `T_startup` before
  entering the normal phase sequence.
- **FR-SF-04** `[test]` On detection of an internal fault (see Section 5),
  the controller shall transition to the fault state.
- **FR-SF-05** `[test]` Recovery from the fault state shall require a manual
  reset; the controller shall not auto-recover.
- **FR-SF-06** `[hw-test]` The controller shall emit a heartbeat pulse to the
  external MMU at no less than 1 Hz while operating normally.
- **FR-SF-07** `[test]` The controller shall enter the fault state immediately
  upon receiving an asserted fault input from the external MMU.
- **FR-SF-08** `[test]` While in the fault state, all vehicle indications
  shall display flashing red.
- **FR-SF-09** `[test]` While in the fault state, all pedestrian indications
  shall display steady DON'T WALK.

## 3.4 User interface

- **FR-UI-01** `[test]` The controller shall expose a serial diagnostic
  interface reporting current phase, time-in-phase, pedestrian request state,
  and last fault code.
- **FR-UI-02** `[test]` The controller shall provide a manual reset input that
  returns the system to the startup state.
- **FR-UI-03** `[test]` The controller shall emit a phase-transition record on
  the diagnostic serial interface immediately following each phase transition,
  in the line format defined in
  [`wire-protocol.md`](wire-protocol.md) § 1.1.
- **FR-UI-04** `[test]` The controller shall emit a heartbeat record on the
  diagnostic serial interface at no less than 1 Hz independent of phase
  transitions, in the format defined in
  [`wire-protocol.md`](wire-protocol.md) § 1.2. This is distinct from the
  MMU safety heartbeat (FR-SF-06), which is on a separate channel.
- **FR-UI-05** `[test]` The controller shall accept newline-terminated
  commands on the command serial interface in the forms defined in
  [`wire-protocol.md`](wire-protocol.md) § 2, and shall silently discard
  malformed or unknown commands.

# 4. Conflict Matrix

The pairwise conflict matrix is defined in
[`conflict-matrix.md`](conflict-matrix.md). The conflict-check module in
`src/core/conflict_check.ads` is the canonical machine-readable
implementation; the Markdown matrix is a human-readable mirror.

# 5. Timing Parameters

Defined in [`timing-parameters.md`](timing-parameters.md). All values are
build-time constants in `src/core/timing.ads`.

# 6. Hardware Interface

## 6.1 Target platform

Reference target: STMicroelectronics **Nucleo-H563ZI** (STM32H563ZI,
Cortex-M33, 250 MHz, 2 MB flash, 640 KB RAM).

## 6.2 I/O summary

| Signal                          | Direction | Count | Description                                    |
|---------------------------------|-----------|-------|------------------------------------------------|
| Vehicle lamp output (R/Y/G)     | Output    | 12    | 3 lamps × 4 approaches                         |
| Left-turn arrow output (R/Y/G)  | Output    | 12    | 3 lamps × 4 left-turn movements                |
| Pedestrian WALK / DON'T WALK    | Output    | 8     | 2 indicators × 4 crosswalks                    |
| Pedestrian request button       | Input     | 4     | One per crosswalk, debounced                   |
| Conflict-monitor heartbeat      | Output    | 1     | Pulse to external MMU                          |
| Conflict-monitor fault          | Input     | 1     | From external MMU; forces fault state          |

## 6.3 Electrical assumptions

- Vehicle and pedestrian lamps are driven through external solid-state relays
  or transistor drivers; the MCU outputs are 3.3 V logic-level signals.
- Pedestrian buttons are normally-open contacts to ground, with internal
  pull-ups enabled.
- Lamp current sense and supply monitoring are out of scope for this version
  but shall be reservable on unused GPIO.

## 6.4 Serial interface assignment

The diagnostic serial interface (FR-UI-01, FR-UI-03, FR-UI-04) and command
serial interface (FR-UI-05) are mapped to specific UART peripherals and
electrical parameters in the hardware pinout document
(`hardware/pinout.md`). The SRS requirements are interface-agnostic; the
physical binding is an implementation detail.

# 7. Non-Functional Requirements

## 7.1 Performance

- **NFR-PF-01** `[test]` Button press to latched-request transition within
  100 ms.
- **NFR-PF-02** `[test]` Lamp outputs updated within 50 ms of an internal
  phase transition.
- **NFR-PF-03** `[test]` Phase timing accuracy ±50 ms over any single phase
  interval.

## 7.2 Reliability

- **NFR-RL-01** `[hw-test]` RAM, flash CRC, and clock integrity self-tests
  on startup.
- **NFR-RL-02** `[hw-test]` IWDG resets the controller if the main loop
  fails to refresh it within 200 ms.
- **NFR-RL-03** `[hw-test]` WWDG configured to detect both early and late
  refreshes of the main loop.

## 7.3 Maintainability

- **NFR-MN-01** `[inspect]` Phase logic and conflict-check logic in separate
  modules, no circular dependency.
- **NFR-MN-02** `[inspect]` All timing parameters defined as named constants
  in a single configuration unit.
- **NFR-MN-03** `[inspect]` The conflict-check module shall be implementable
  in SPARK with proof of FR-SF-01 and FR-SF-02 as a future objective.

## 7.4 Diagnostics

- **NFR-DG-01** `[test]` Diagnostic record emitted on every phase transition
  over the diagnostic serial interface, in the format defined by FR-UI-03
  (see [`wire-protocol.md`](wire-protocol.md) § 1.1).
- **NFR-DG-02** `[hw-test]` Fault codes retained in non-volatile memory (one
  most-recent record) and readable over the diagnostic serial interface after
  reset.

# 8. Out of Scope (this version)

- Coordination with adjacent intersections (no SDLC, no NTCIP).
- Emergency vehicle preemption.
- Adaptive timing based on detected vehicle volumes.
- Failsafe lamp current monitoring (open-lamp detection).
- Certification to EN 12675, NEMA TS-2, or any equivalent standard.

# 9. Open Questions

- Should left-turn demand be modeled as a discrete input, or hard-coded as
  always-present for the bench prototype?
- Should the system support a night-time flashing-yellow / flashing-red mode,
  and if so on what schedule?
- Is the external MMU a separate microcontroller (e.g., a second STM32 on a
  CAN-FD link) or simulated initially in software?
- Are pedestrian countdown timers required, and if so what minimum count
  granularity?
