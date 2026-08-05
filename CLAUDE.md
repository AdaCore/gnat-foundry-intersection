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
make build-native   # Build the native app
make test           # Run the testsuite
make prove          # Run the prover

make all-coverage   # Generate a coverage report

make report         # Generate the verification report
```

The verification report (proof + coverage + review obligations) renders to
`reports/report/html/`; `make report-pdf` also renders it to
`reports/report/pdf/verification-report.pdf` (rst2pdf, no TeX needed). The
generator lives in `engine/report/`. `report` regenerates its evidence first
(`validate-reqs prove-report all-coverage coverage-report-xml`), so it never
reports stale proof runs or test executions, and its traceability claims are
gated on the requirements chain actually validating.

The `test`/`coverage` targets auto-detect the toolchain provisioned under
`install/` (`make setup-pro` or `make setup-community`), so they are the same
regardless of which one you ran.

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

Sub-agents cannot prompt the human directly — the **shared questions file**
(`workflow/<feature>/questions.md`, append-only) is the only escalation channel;
its format is in `engine/workflow/README.md`.

Unless specifically asked, do not look at git branches other than the one you're on.

## When editing code

- Read the code architecture: `design/architecture.md`
- Read the code conventions: `design/code_conventions.md`
- Format with `make format`
- Validate your change with `make check && make build-native`

## Keeping `core` proven

`types.gpr` and `core.gpr` are SPARK Silver proof targets: `make prove` must
stay clean at `--level=2 --checks-as-errors=on`. Keep `core` proven as much as
possible. **Never** discharge a proof obligation with a manual justification
(`pragma Annotate ... Assume`, `pragma Assume`, suppressed checks, or the
like). If a change means the core can no longer be proven without such an
escape hatch, stop and raise a flag rather than papering over it — that broken
invariant is a signal worth surfacing.

Because `gnatprove` analyses generic *instances* and not uninstantiated
generics, the `core` project carries a small in-SPARK instantiation harness
(`state_machine_loop_proof`) so the generic core loop is actually exercised by
`make prove`. Keep such harnesses in step when the generic surface changes.

## When editing tests

- Format with `make format`
- Validate your change with `make build-native && make test`
- Trace each test to its requirement: every test routine carries a `--@covers`
  tag (first editable line of its body) naming the LLR statement id(s) it
  verifies, or `--@covers none: <reason>` for a boundary test. `make trace-check`
  enforces this via the `TEST` layer of `requirements/trace_chain.yaml`; run
  `make trace` to see the LLR↔test coverage tables.
- If working on coverage augmentation, run `make all-coverage` to list uncovered code.
