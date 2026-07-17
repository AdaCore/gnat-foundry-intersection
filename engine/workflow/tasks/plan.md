# Task: Plan

## Purpose

Write a plan for the implementation and LLRs in Ada, honoring the architecture
and the code conventions.

## Inputs

- `workflow/<feature>/notes.md` — if it exists.
- `requirements/llr/*.yaml` — what to implement (the spec).
- `design/architecture.md` — where the code goes and the bus/proof boundaries.
- `design/code_conventions.md` — the implementation must heed these conventions.
- Existing `src/` code.

## Outputs

- Detailed plan in `workflow/<feature>/notes.md` — what to implement, where it goes, and
  how to test it.

## Procedure

1. Read `workflow/<feature>/notes.md` if it exists, which might mention architecture
   changes made to support the work.
2. Read the LLRs and existing architecture.
3. Plan the work: identify any changes that will need to be made in the implementation.
   This should contain a testing plan.
4. Edit `workflow/<feature>/notes.md` to record the plan, including any notes
   for the implementers and testers. Remove any entries that are now addressed or captured in the plan.

## Oracle

```bash
bash -c "[ -s workflow/<feature>/notes.md ]"
```

**Done when the plan file exists and is non-empty.**

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if an LLR cannot
be implemented as written (it is infeasible or contradicts another requirement —
that is an LLR/HLR gap, not something to code around), or if implementing it
would require an architecture change not yet made (return to the Architecture
task).
