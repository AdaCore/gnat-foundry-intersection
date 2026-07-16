# Task: Implementation

## Purpose

Implement the LLRs in Ada, honoring the architecture and the code conventions,
so the app builds, lints clean, and the existing test suite stays green.

## Inputs

- `requirements/llr/*.yaml` — what to implement (the spec).
- `design/architecture.md` — where the code goes and the bus/proof boundaries.
- `design/code_conventions.md` — naming (`Mixed_Case`, child packages, no
  namespaces), trailing-doc comments, gnatdoc tags, narrow types, no globals, no
  magic numbers.
- Existing `src/` code — match surrounding style.

## Outputs

- Ada sources under `src/` (`.ads`/`.adb`) implementing the LLRs. (Ada files are
  auto-formatted by the repo's post-edit hook.)

## Procedure

1. Implement each LLR statement in the module the architecture assigns it to.
2. Keep `core` SPARK-friendly if it is in a proof target (the Prove task will
   check this next; don't introduce constructs that block proof).
3. Document specs per the conventions.
4. Build, lint, and run the tests (the oracle).

## Oracle

```bash
make check && make build-native && make test-pro
```

**Done when all three succeed** — lint clean, native build succeeds, and the
AUnit suite passes (0 failures).

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if an LLR cannot
be implemented as written (it is infeasible or contradicts another requirement —
that is an LLR/HLR gap, not something to code around), or if implementing it
would require an architecture change not yet made (return to the Architecture
task).
