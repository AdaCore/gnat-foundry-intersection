# Safety Case (placeholder)

This document will eventually contain:

1. **Safety claims** — what we assert is true about the system.
2. **Arguments** — why we believe the claims hold.
3. **Evidence** — the proofs, tests, and reviews that back each argument.

For v0.1, the file is a placeholder. Drafting begins after the
conflict-check module exists with a passing SPARK proof.

## Anticipated structure (Goal Structuring Notation, informal)

```
G1: The controller never displays a dangerous combination of indications.
 ├─ G1.1: Conflict matrix is correctly defined.
 │   └─ E1.1.1: Manual review against intersection geometry; ADR-0003.
 ├─ G1.2: Software respects the conflict matrix at every tick.
 │   ├─ G1.2.1: Conflict-check module's invariants hold.
 │   │   └─ E1.2.1.1: SPARK proof in tests/proof/.
 │   └─ G1.2.2: Sequencer only requests states the conflict-check accepts.
 │       └─ E1.2.2.1: Integration tests in tests/integration/.
 └─ G1.3: External MMU forces fail-safe on any violation.
     └─ E1.3.1: Hardware-in-the-loop test (future).
```

Strictly informal. A real EN 12675 / NEMA TS-2 safety case would require
considerable additional structure, evidence, and independent assessment.
