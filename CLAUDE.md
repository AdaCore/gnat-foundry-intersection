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
make test-pro       # Run the testsuite
make prove          # Run the prover

make all-coverage-pro  # Generate a coverage report
```

## When editing code

- Read the code architecture: `design/architecture.md`
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
- Validate your change with `make build-native && make test-pro`
- If working on coverage augmentation, run `make all-coverage-pro` to list uncovered code.
