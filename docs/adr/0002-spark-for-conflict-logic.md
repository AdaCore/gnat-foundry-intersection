# 0002 — Use Ada/SPARK for the conflict-check module

- **Status:** Accepted
- **Date:** 2026-04-27
- **Deciders:** Mark

## Context

The conflict-check logic is the safety-critical core of a traffic controller:
it decides which combinations of lamp states are ever permitted. A bug here
is not a quality issue; it's a safety issue. The rest of the system
(scheduler, HAL, diagnostics) is less critical.

We want strong evidence — beyond testing — that the conflict-check module
cannot signal a conflicting combination as safe.

## Decision

Implement the conflict-check module in **SPARK**, with proof targets covering
**FR-SF-01** and **FR-SF-02**. Implement the rest of the system in plain
Ada with assertions. Allow the SPARK boundary to expand outward later
(toward the sequencer) once the conflict-check proof is stable.

## Consequences

- Positive: Mathematical proof of the safety invariants, not just tests.
- Positive: SPARK forces clean separation between the core logic and I/O,
  which we want anyway (see [ADR-0001](0001-stm32h563-target.md) and the
  layered architecture).
- Negative: SPARK has a learning curve; some idioms common in Ada (access
  types, exceptions) are restricted.
- Negative: CI gets a `gnatprove` stage which is slower than tests.
- Neutral: GNAT FSF toolchain is fine for the proof; GNAT Pro qualification
  isn't needed for a hobby project.

## Alternatives considered

- **Plain Ada with extensive assertions and tests.** Cheaper, but tests
  enumerate cases; proof rules them out.
- **Frama-C / TLA+ / model checking.** Off-toolchain — would mean writing
  the implementation in one language and the proof in another, with
  manual correspondence. Not worth the friction for this project.

## References

- SPARK 2014 Reference Manual
- AdaCore SPARK guide
