# Task: Implementation

## Purpose

Implement the LLRs in Ada, honoring the architecture and the code conventions,
so the app builds, lints clean, and the existing test suite stays green.

## Inputs

- `workflow/<feature>/implementation.md` if this exists — this is your blueprint for the implementation: follow this carefully.
- `workflow/<feature>/notes.md` if this exists — it might contain useful notes.
- The LLRs in `requirements/llr/*.yaml` — what to implement.
- `design/architecture.md` — where the code goes and the bus/proof boundaries.
- `design/code_conventions.md` — code conventions to follow.
- Existing `src/` code — match surrounding style.

## Outputs

- Changes in sources under `src/` implementing the LLRs. Write Ada code;
  use C only if absolutely necessary and only in the hardware interface layer.

## Procedure

1. Implement each LLR statement in the module the architecture assigns it to.
2. Keep `core` SPARK-friendly if it is in a proof target (the Prove task will
   check this next; don't introduce constructs that block proof).
3. If a compile-time check you add is the evidence for a `static_check` LLR
   statement, tag it: a `--@covers <llr id>` comment on the line directly
   before the pragma / aspect (see `engine/requirements/docs/README.md`) —
   `make trace-check` resolves it; the statement stays uncovered until then.
4. Document specs per the conventions.
5. Build, lint, and run the tests (the oracle).
6. Edit `workflow/<feature>/notes.md` to remove any entries that are now addressed or captured in the
   implementation, and to add any notes that might be necessary for the proof or test generation phases.
7. Remove `workflow/<feature>/implementation.md` if it exists — the plan is now implemented.

## Oracle

```bash
make check && make build-native && make test
```

**Done when all three succeed** — lint clean, native build succeeds, and the
AUnit suite passes (0 failures).

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if an LLR cannot
be implemented as written (it is infeasible or contradicts another requirement —
that is an LLR/HLR gap, not something to code around), or if implementing it
would require an architecture change not yet made (return to the Architecture
task).
