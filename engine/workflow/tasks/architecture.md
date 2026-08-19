# Task: Code architecture modification

## Purpose

Adjust the code architecture so the feature has a place to live — new/changed
modules, bus boundaries, `.gpr` project graph, or the SPARK proof boundary —
*before* implementation. Keep `design/architecture.md` the accurate description
of the code (it is meant to be edited in step with the code).

## Inputs

- `design/architecture.md` — current architecture (state machine, core loop, data
  buses, `.gpr` graph, SPARK proof boundaries). Read fully.
- `design/code_conventions.md` — naming, documentation, type-system, no globals,
  no magic numbers.
- `requirements/llr/*.yaml` (and HLRs) — what the architecture must support.

## Outputs

- Edits to the `.gpr` project graph and package structure under `src/` as needed
  (new packages, moved boundaries) — skeletons/specs, not full implementation.
- **`design/architecture.md` edited in sync** — the doc must describe the code as
  it now is.
- If the SPARK proof boundary moves, keep the `state_machine_loop_proof`
  instantiation harness (`src/proof/state_machine_loop_proof.{ads,adb}`) in step
  with the generic surface. A new generic under proof needs a harness of its own
  there, or nothing in its body is analyzed.

## Procedure

1. Locate where the feature fits in the existing layering (`types` → `core`,
   `hal`, `app`).
2. Make the minimal structural change that supports the LLRs; respect the
   conventions (no globals, narrow types, child packages, no namespaces).
3. Update `design/architecture.md` to match.
4. Verify the tree still builds and lints (the oracle).

## Oracle

```bash
make check && make build-native
```

**Done when both succeed** — `check` (Ada/shell/Python lint) is clean and the
native app builds. (There is no requirements/proof gate for this task by design;
correctness is confirmed by the downstream Implementation, Prove, and Coverage
tasks.)

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if the change
would move the SPARK proof boundary in a way that risks `core`'s provability, or
if there are competing structural options with materially different trade-offs
that a human should choose between.
