# Task: Prove (gnatprove)

## Purpose

Keep the SPARK Silver proof targets (`types.gpr`, `core.gpr`) proven after the
change — absence of run-time errors, discharged at `--level=2` with checks as
errors.

## Inputs

- `workflow/<feature>/notes.md` — if this exists, it may contain notes relevant to this task.
- `src/core/*` and `src/types/*` — the proof targets (contracts, invariants,
  loop invariants, ghost code as needed).
- `src/proof/state_machine_loop_proof.{ads,adb}` — the in-SPARK instantiation
  harness that exercises the generic core loop under proof.
- `CLAUDE.md` (Claude Code) or `AGENTS.md` (Codex) — the "Keeping `core` proven" rules.

## Outputs

- Edits to contracts / invariants / ghost code in the proof targets so `make
  prove` is clean. If the generic surface changed, the
  `state_machine_loop_proof` harness updated in step.

## Procedure

1. Run the oracle to see the unproved checks.
2. Discharge them by strengthening contracts, adding loop invariants, or adding
   *proof-only ghost code / lemmas* — never by weakening what is being proven.
3. If a contract you add or change is the evidence for a `proof`-verified LLR
   statement, tag it: a `--@covers <llr id>` comment on the line directly
   before the aspect (or above the `with` opening a one-line aspect list) —
   see `engine/requirements/docs/README.md`.
4. Re-run until clean.

## Oracle

```bash
make prove && make trace-check-proof
```

**Done when it exits 0 with no unproved checks or traceability gaps.**

**Hard rule (from CLAUDE.md / AGENTS.md — never violate):** do **not** discharge a proof
obligation with a manual escape hatch — no `pragma Annotate ... Assume`, no
`pragma Assume`, no suppressed checks, or the like. If the core can no longer be
proven without such an escape hatch, **stop and raise a flag** (escalate) rather
than papering over it — that broken invariant is a signal worth surfacing.

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if a check cannot
be discharged without an escape hatch (surface exactly which obligation and why),
or if proving it would require changing a contract in a way that alters intended
behavior — a human must decide.
