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

 Detailed plan in `workflow/<feature>/implementation.md` — what to implement, and where it goes.

## Procedure

1. Read `workflow/<feature>/notes.md` if it exists, which might mention architecture
   changes made to support the work.
2. Read the LLRs and existing architecture.
3. Plan the work: identify any changes that will need to be made in the implementation.
   This should contain a testing plan.
4. Write the implementation plan in `workflow/<feature>/implementation.md`.
5. Add in `workflow/<feature>/notes.md` any notes that might be useful to the proof or test generation phases.
6. Remove any entries from `workflow/<feature>/notes.md` that are now addressed or captured in the plan.

## Oracle

```bash
bash -c "[ -s workflow/<feature>/implementation.md ]"
```

**Done when the plan file exists and is non-empty.**

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if an LLR cannot
be implemented as written (it is infeasible or contradicts another requirement —
that is an LLR/HLR gap, not something to code around), or if implementing it
would require an architecture change not yet made (return to the Architecture
task).
