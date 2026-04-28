# 0003 — Use leading protected left-turn phases

- **Status:** Accepted
- **Date:** 2026-04-27
- **Deciders:** Mark

## Context

The intersection has dedicated left-turn movements on each approach. There
are several ways to schedule these:

- **Leading protected**: left-turn green runs *before* the parallel through
  green. Left-turn drivers move on a protected green arrow with no
  conflicting traffic.
- **Lagging protected**: left-turn green runs *after* the parallel through
  green.
- **Permissive**: left turns yield to oncoming through traffic (no separate
  arrow phase, just a green ball).
- **Protected/permissive (FYA)**: a flashing yellow arrow indicates yield;
  combines protected and permissive in one phase.

## Decision

Use **leading protected left-turn phases**. Permissive turns are out of
scope for v0.1.

## Consequences

- Positive: Simpler conflict matrix — left-turn and parallel through never
  conflict (they're sequential, not simultaneous).
- Positive: Clean SPARK proof obligation: any pair of "active" movements
  must be in the compatibility set.
- Positive: Sequence is deterministic and easy to test.
- Negative: Less efficient throughput than protected/permissive in
  light-traffic conditions.
- Neutral: Easy to flip to lagging by reordering the phase sequence in
  `phase_sequencer.adb` without changing the conflict matrix.

## Alternatives considered

- **Permissive** — lower safety margin; pedestrian/turning conflicts harder
  to guarantee.
- **Protected/permissive (FYA)** — adds a dual-meaning indication, which
  expands the conflict matrix and the proof state space. Worth revisiting
  after v0.1.

## References

- [`docs/requirements/conflict-matrix.md`](../requirements/conflict-matrix.md)
- [`docs/architecture/state-machine.md`](../architecture/state-machine.md)
