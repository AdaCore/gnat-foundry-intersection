# Proof architecture

How the `core` proof obligations are discharged. This is orthogonal to the
low-level design (`low-level-design.md`) and to the writing of the LLRs: it
records the verification strategy, not the software structure.

`types.gpr` and `core.gpr` are proven at SPARK Silver
(`--level=2 --checks-as-errors=on`) with no manual justifications — a
`CLAUDE.md` policy that is load-bearing.

- **Vehicle-conflict invariant `hlr_0_safety.2`** — encoded as the
  `Conflicts.Safe_Faces` postcondition on `Project_Outputs` (hence on `Step`).
  It discharges by construction: `Project_Outputs` is total and literal per
  state, `Safe_Faces` a pure expression function, and gnatprove enumerates the
  finite cases. This is the headline proof.
- **Pedestrian-conflict invariant `hlr_0_safety.1`** — deliberately *not* a
  runtime contract. Its discharge is the static timing margin `hlr_3_timing.10`,
  a property of the whole schedule rather than any one state; encoding it on
  `Step` would need an escape hatch the proof policy forbids. It stays the
  flagged, coupled obligation tracked in `requirements/TODO.md`.
- **`Both_Duration`'s postcondition** proves the residual arithmetic safe and
  bounded (`hlr_3_timing.12`).
- **Absence of run-time errors** across `types` and `core` is the Silver
  baseline. Because gnatprove analyses generic *instances*, not uninstantiated
  generics, the core loop is exercised through `State_Machine_Loop_Proof` — a
  proof-only instantiation of `State_Machine_Loop` against in-SPARK stubs, never
  called at runtime.
