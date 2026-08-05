# Task: Modification of tests to reach 100% coverage

## Purpose

Close coverage gaps left after test generation: add or extend tests until the
GNATcov report (stmt + MCDC) shows no uncovered lines.

## Inputs

- The coverage report findings from the oracle command (printed as
  `file:line:col:` lines) and `coverage.log`.
- Existing test bodies under `tests/` — extend these.
- `CLAUDE.md` — the "If working on coverage augmentation" note.

## Outputs

- Additional/extended test bodies under `tests/` that exercise the uncovered
  lines and decisions.

## Procedure

1. Run the oracle; each printed `file:line:col:` is an uncovered line/decision.
2. Add tests that exercise those paths (new inputs, boundary values, error paths,
   both sides of each decision for MCDC).
3. Re-run until the oracle prints nothing.

## Oracle

```bash
make all-coverage
```

This instruments, builds, runs the harness under GNATcov, and greps the report
for findings. **Done when it prints no `file:line:col:` lines** (silent on full
coverage; `no SID file found` warnings for un-instrumented units are benign).

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if a line is
genuinely unreachable (defensive/impossible code — a human should decide whether
to add a justification, restructure, or accept it) rather than writing a
contrived test purely to touch it.
