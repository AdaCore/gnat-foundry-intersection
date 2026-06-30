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

- Format with `make format`
- Validate your change with `make check && make build-native`

## When editing tests

- Format with `make format`
- Validate your change with `make build-native && make test-pro`
- If working on coverage augmentation, run `make all-coverage-pro` to list uncovered code.
