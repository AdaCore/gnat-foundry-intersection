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

### Notes
- Toolchain pinned via `alire.toml`.
- Requirement IDs (`FR-*`, `NFR-*`) are stable forever.
