# Task: Modification of tests to reach 100% coverage

## Purpose

Close coverage gaps left after test generation: add or extend tests until the
GNATcov report (stmt + MCDC) shows no uncovered lines.

Coverage is measured from the requirements-based tests alone, so this task is
requirements work: an uncovered line is a line no requirement demonstrably
exercises. Extending a generated skeleton under `tests/core`, `tests/types` or
`tests/hal` cannot move the oracle — those tests are not in the measured run.

## Inputs

- The coverage report findings from the oracle command (printed as
  `file:line:col:` lines) and `coverage.log`.
- Existing routines under `tests/reqs/` — extend these.
- `tests/reqs/README.md` — its rules are the review criteria for a new routine.
- `CLAUDE.md` — the "If working on coverage augmentation" note.

## Outputs

- Additional/extended routines under `tests/reqs/` that exercise the uncovered
  lines and decisions, each tagged `--@covers` with the LLR statement it
  verifies.

## Procedure

1. Run the oracle; each printed `file:line:col:` is an uncovered line/decision.
2. Find the LLR statement that governs the uncovered code, and add or extend the
   routine for that statement (new inputs, boundary values, error paths, both
   sides of each decision for MCDC). Transcribe expected values from the
   requirement, never from the code.
3. If no requirement governs it, that is the finding — escalate rather than
   writing a routine that tests the code against itself.
4. Re-run until the oracle prints nothing.

## Oracle

```bash
make all-coverage && make check-coverage && make trace-check
```

The first instruments, builds, runs the requirements-based harness under
GNATcov, and greps the report for findings; the second is the gate CI runs over
that report; the third re-checks full traceability. **Done when all exit zero**
(`no SID file found` warnings for un-instrumented units are benign).

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop, rather than
writing a contrived routine purely to touch a line, if:

- the line is genuinely unreachable (defensive/impossible code — a human should
  decide whether to add a justification, restructure, or accept it); or
- no LLR statement governs the uncovered code, so covering it would mean
  transcribing the expectation from the code itself.
