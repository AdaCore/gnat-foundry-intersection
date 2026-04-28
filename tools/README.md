# Tools

Helper scripts run from the repository root.

| Script | Purpose |
|--------|---------|
| `trace-check.py` | Verifies every requirement in `srs.md` is referenced by at least one source file or test. Regenerates `docs/requirements/traceability.md`. |
| `render-srs.py` | Renders `srs.md` to `.docx` and PDF via Pandoc. |

## Conventions

- Scripts are Python 3 only, no third-party dependencies unless absolutely
  necessary (Pandoc is invoked as a subprocess).
- All scripts must be runnable from the repository root with no arguments.
- All scripts must exit non-zero on failure so CI can act on the result.
