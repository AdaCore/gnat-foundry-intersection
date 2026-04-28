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
- Zephyr build path for the STM32H563ZI / Cortex-M33F target:
  `gnat_arm_elf` toolchain pinned via Alire; `traffic_light_zephyr.gpr`
  static-library GPR (`light-cortex-m33f` runtime, hard-float ABI);
  `CMakeLists.txt` driving gprbuild and linking via `_ada_main` trampoline;
  `prj.conf`, `west.yml` (Zephyr v4.4.0), `Makefile` wrapping `west` with
  `alr exec`. Default board: `nucleo_h563zi`. New HAL stub at
  `src/hal/zephyr/`.

### Changed
- `alire.toml` description shortened to fit Alire's 72-char limit.
- `traffic_light.gpr` simplified to a host-only build (profile mechanism
  removed). Cross-target builds go through `traffic_light_zephyr.gpr`.
- `docs/architecture/overview.md` updated to describe the Zephyr-backed
  HAL and the C-shim bridge pattern.

### Removed
- Bare-metal STM32H5 HAL stub (`src/hal/stm32h5/`) — superseded by the
  Zephyr-backed HAL per ADR-0004.
- `Target_Profile` configuration variable from `alire.toml` (no longer
  needed; Zephyr cross-build is a separate GPR + CMake pipeline).

### Notes
- Toolchain pinned via `alire.toml`.
- Requirement IDs (`FR-*`, `NFR-*`) are stable forever.
