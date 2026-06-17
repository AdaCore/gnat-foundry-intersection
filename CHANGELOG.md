# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial repository scaffold.
- Software Requirements Specification (v0.1, draft).
- Conflict matrix for 4-way intersection with leading protected lefts.
- Architecture Decision Records: target platform, SPARK use, leading-left phasing.
- GitLab CI pipeline skeleton (lint, build, test, prove, docs, package).
- Traceability check tool (`tools/trace-check.py`).
- SRS render pipeline via Pandoc.
- Claude Code agentic scaffolding: `CLAUDE.md`, `.claude/settings.json`,
  five subagents (`spark-prover`, `requirements-tracer`, `safety-reviewer`,
  `requirement-change-issuer`, `documentation`).
- Bare-metal arm-eabi cross-target build (Cortex-A9, QEMU xilinx-zynq-a9)
  in a sibling Alire crate (`traffic_light_qemu/`) using the
  toolchain-bundled `light-tasking-zynq7000` GNAT runtime (Ravenscar
  tasking); emits `bin/qemu_zynq7000/traffic_light`. New HAL at
  `src/hal/qemu_zynq7000/` (Cadence XUartPs UART; 1 ms tick via
  Ada.Real_Time `delay until`). Driven via `make build-target` /
  `make run-target`.

### Changed
- `alire.toml` description shortened to fit Alire's 72-char limit.
- `traffic_light.gpr` simplified to a host-only build (profile mechanism
  removed). The arm-eabi cross-target build lives in its own crate.
- `docs/architecture/overview.md` updated to describe the host and
  bare-metal arm-eabi HAL variants.

### Notes
- Toolchain pinned via `alire.toml`.
- Requirement IDs (`FR-*`, `NFR-*`) are stable forever.
