# Contributing

## Workflow

- `main` is always green and represents the latest tested state.
- All changes go through a Merge Request. Even solo work — the CI gate and
  reviewable history are worth it.
- Branch naming: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`,
  `chore/<short-name>`, `refactor/<short-name>`.
- Squash-merge by default. Keep MRs small and focused.

## Commit messages

Follow Conventional Commits:

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `ci`, `safety`.
Scopes (suggested): `core`, `hal`, `app`, `srs`, `proof`, `ci`, `adr`.

Example:
```
feat(core): add pedestrian phase sequencer

Implements the WALK / FDW / DW state machine with concurrent
through-phase coupling per FR-PD-03..07.

Refs: FR-PD-03, FR-PD-04, FR-PD-05, FR-PD-06
```

## Requirements

- Requirement IDs (`FR-*`, `NFR-*`) are **stable forever**. Never reuse an ID,
  even if the requirement is deleted.
- To remove a requirement, mark it obsolete in `docs/requirements/srs.md`:
  `~~FR-PH-99~~ (obsolete in v0.4 — superseded by FR-PH-12)`.
- Every code module that implements a requirement must reference its FR IDs
  with an `-- @req` comment. Same for tests.
- The traceability check (`tools/trace-check.py`) runs in CI and fails if any
  active FR has zero references in code or tests.

## Architecture Decision Records

Significant decisions get an ADR. Copy `docs/adr/template.md` to a new file
numbered sequentially (`NNNN-short-title.md`). Status starts as "Proposed";
becomes "Accepted" on merge.

## Code style

- Ada code follows GNAT conventions; `gnatcheck` runs in CI.
- SPARK-mode code lives in `src/core/` and must pass `gnatprove --level=2`
  with no unproven checks (other than those explicitly justified with
  `pragma Annotate`).

## SPARK invariants

The conflict-check module is the proof target. Any change that weakens an
invariant or adds a `pragma Annotate (GNATprove, False_Positive, ...)`
without justification will be rejected.

## Pre-commit checks

Before pushing:

```bash
alr build                                    # Host build
alr exec -- gnatcheck -P traffic_light.gpr   # Lint
python3 tools/trace-check.py                 # Requirement coverage
```

CI will run all of these plus the cross-target build and SPARK proofs.
