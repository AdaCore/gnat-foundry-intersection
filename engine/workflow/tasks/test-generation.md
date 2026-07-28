# Task: Test generation

## Purpose

Generate the unit-test harness for new/changed code (GNATtest + AUnit) and fill
in meaningful test bodies, so the suite builds and passes.

## Inputs

- `workflow/<feature>/notes.md` — if this exists, it may contain notes relevant to this task.
- New/changed `src/` specs — the subprograms needing tests.
- Existing test bodies under `tests/`, which mirrors `src/` (e.g.
  `tests/core/controller-test_data-tests.adb`, `tests/core/conflicts-*`,
  `tests/types/states-*`, `tests/hal/common/`) — match their style. Only
  code outside the `begin read only` regions is yours to edit.
- `CLAUDE.md` — the "When editing tests" rules.

## Outputs

- Regenerated GNATtest skeletons plus hand-written test bodies under `tests/`
  covering the new behavior. (Generated `*-test_data.ads` files stay untracked;
  `.adb` bodies are tracked.)

## Procedure

1. Regenerate the harness: `make generate-tests-pro`.
2. Fill in the test bodies for the new/changed subprograms (in the editable
   regions) — assert the behavior the LLRs specify.
3. Build and run (the oracle). Coverage-to-100% is the *next* task, not this one;
   here the bar is "harness builds and all tests pass".

## Oracle

```bash
make generate-tests-pro && make build-native && make test-pro
```

**Done when all succeed** — the harness regenerates, the app builds, and the
AUnit runner reports 0 failures.

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if the expected
result of a behavior is genuinely ambiguous from the LLRs (the test would encode
a guess — fix the LLR instead), or if a subprogram is untestable as structured
(may need an Architecture change).
