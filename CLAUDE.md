# CLAUDE.md

## What this is

The *engine*: a set of reusable modules for driving AI agents to
produce high-quality software artifacts. The engine is located under `engine/`.

The *app*: four-way traffic-light controller targeting the Xilinx Zynq-7000 (dual-core
Cortex-A9), exercised under QEMU. Implemented in Ada with the **controller proven to SPARK Silver**.

The aim of this repository is to demonstrate how the engine can work on the *app*.

## Commands

Essential commands:

```bash
make help           # List the public targets, by section

make build-native   # Build the native app
make test           # Run the testsuite
make prove          # Run the prover

make all-coverage   # Generate a coverage report (requirements-based tests only)

make build-target   # Build the bare-metal arm-eabi firmware
make smoke-target   # Boot the firmware under QEMU, check its first display frame
make test-target    # Run the testsuite ON TARGET (arm-eabi, under QEMU)

make report         # Generate the verification report
```

The verification report (proof + coverage + traceability + the requirements
themselves + review obligations) renders to `reports/report/html/`; `make
report-pdf` also renders it to `reports/report/pdf/verification-report.pdf`
(rst2pdf, no TeX needed). The generator lives in `engine/report/`. `report`
regenerates its evidence first (`validate-reqs-corpus trace-report
requirements-doc prove-report all-coverage coverage-report-xml`), so it never
reports stale proof runs, trace matrices, requirement text, or test
executions, and it gates on the requirement files being parseable
(schema + EARS). Trace gaps at any layer do not fail `report` (that is
`trace-check`'s job): they render as open items, so a report is available
part-way through a project, showing what is not yet done.

The `test`/`coverage` targets auto-detect the toolchain provisioned under
`install/` (`make setup-pro` or `make setup-community`), so they are the same
regardless of which one you ran.

The `*-target` targets additionally need `qemu-system-arm` on PATH; the
`setup-*` targets do not provision it (CI takes it from the `image:serotonic`
runner image). `test-target` runs the *generated* test bodies under `tests/`,
minus the host-profile HAL units listed in
`traffic_light_qemu/tests/host_only_sources.txt` — 11 of the 16 skeletons. It
does **not** run the requirements-based routines under `tests/reqs/`, which
reach the native harness through `--additional-tests` and have no cross-harness
equivalent. Coverage is native-only.

## Feature workflow

Add a feature as a succession of **Tasks**, each delegated to a purpose-built
sub-agent, each gated by a **mechanical oracle** (a command that must
pass). The task specs and oracles are defined once, tool-agnostically, in
[`engine/workflow/`](engine/workflow/README.md) — read it before orchestrating.

Task types and their sub-agents:

| Task | Sub-agent |
| ------ | ----------- |
| Elaborate HLR | `hlr-author` |
| Elaborate LLR | `llr-author` |
| Architecture | `architecture-editor` |
| Plan | `planner` |
| Implementation | `implementer` |
| Prove | `prover` |
| Test generation | `test-generator` |
| Coverage | `coverage-closer` |

Default order: HLR → LLR → Architecture → Plan → Implementation → Prove → Test
generation → Coverage. **A feature uses only the subset it needs.**

As the orchestrating (main) session:

1. Slugify the feature and create `workflow/<feature>/`.
2. Write `workflow/<feature>/plan.md`: the selected chain, one status line per
   task (`todo` / `in-progress` / `oracle-passed` / `blocked`).
3. For each task in order: dispatch the matching sub-agent (Task tool /
   `subagent_type`), passing the feature slug. **Advance only when that task's
   oracle command passes — verify it yourself, don't take the sub-agent's word.**
4. After each sub-agent returns, check `workflow/<feature>/questions.md`; if it
   has an unanswered `Q`, relay it to the human via `AskUserQuestion`, write the
   `A:` back, and re-dispatch so the sub-agent resumes.
5. Update `plan.md`. Done when every task in the chain is `oracle-passed`.
6. Once the feature is done, run `make report` to produce the final report.
   Include a summary of the results in your concluding message, and direct the
   user to where they can read it in full.

Sub-agents cannot prompt the human directly — the **shared questions file**
(`workflow/<feature>/questions.md`, append-only) is the only escalation channel;
its format is in `engine/workflow/README.md`.

Unless specifically asked, do not look at git branches other than the one you're on.

## When editing any artifact

- Read the section on commentary conventions in code conventions: `design/code_conventions.md`
- With the exception of explicit records of history (change logs etc.), do not
  document how things used to be; artifacts should read as if they were written
  from scratch the way they are now. When something is moved, there is no
  obligation to leave breadcrumbs where it was previously.

## When editing code

- Read the code architecture: `design/architecture.md`
- Read the code conventions: `design/code_conventions.md`
- Format with `make format`
- Validate your change with `make check && make build-native`
- A contract or compile-time check that discharges a `proof` / `static_check`
  LLR carries a `--@covers <id>` comment on the line directly above the aspect
  or pragma (see `engine/requirements/docs/README.md`); `make trace-check`
  resolves those. Untagged checks are fine — tagging is opt-in evidence.

## Keeping `core` proven

`types.gpr` and `core.gpr` are SPARK Silver proof targets: `make prove` must
stay clean at `--level=2 --checks-as-errors=on`. Keep `core` proven as much as
possible. **Never** discharge a proof obligation with a manual justification
(`pragma Annotate ... Assume`, `pragma Assume`, suppressed checks, or the
like). If a change means the core can no longer be proven without such an
escape hatch, stop and raise a flag rather than papering over it — that broken
invariant is a signal worth surfacing.

`make prove` is rooted at `src/proof.gpr`, whose tree is the proof scope and
whose sources are the instantiation harnesses (design/architecture.md
§"Project structure"). Keep them in step with the generic surface, and put new
ones there, never in `core`: a generic no analyzed instance reaches is unproved
code, which `make report` reports under "Generics" -- nested generics
included, so a bus generic nothing instantiates is caught too.

## When editing tests

- Format with `make format`
- Validate your change with `make build-native && make test`
- Trace each test to its requirement: every test routine carries a `--@covers`
  tag (first editable line of its body) naming the LLR statement id(s) it
  verifies, or `--@covers none: <reason>` for a boundary test. `make trace-check`
  enforces this via the `TEST` layer of `requirements/trace_chain.yaml` — for
  the generated skeletons and `tests/reqs/` alike; run `make trace` to see the
  LLR↔test coverage tables.
- Every LLR statement declares its `verification:` method(s). `make trace-check`
  requires a covering test for each `test`-verified statement and rejects a
  `--@covers` citing a statement not declaring `test` — add a `method: test`
  entry to that statement's `verification:` in the same change if the test is
  genuine.
- Writing a requirements-based test under `tests/reqs/`: read
  `tests/reqs/README.md` first — its rules are the review criteria.
- If working on coverage augmentation, run `make all-coverage` to list uncovered
  code, and close the gaps with routines under `tests/reqs/` — nothing else is
  in the measured run. If no LLR statement governs the uncovered code, that is
  the finding: raise it rather than transcribing an expectation from the code.
