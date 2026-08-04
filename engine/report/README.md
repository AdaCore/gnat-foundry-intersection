# vreport — verification-report generator

Collects the machine-readable evidence left by the verification tools and
renders it as a Sphinx/MyST HTML report whose front page tells a reviewer
exactly what they must personally review to establish trust in the artifact.
Everything else in the report is supporting evidence for that checklist.

## Usage

```bash
vreport generate --root <repo> --out <repo>/reports/report
```

or, from the repository root, `make report`, whose prerequisites regenerate
the tool inputs so the report never describes stale artifacts. Inputs (when
invoking `vreport` directly, produce them first):

| Input | Producer | Contents |
|---|---|---|
| `obj/development/gnatprove/` | `make prove-report` | per-unit `*.spark` JSON, `gnatprove.out` (with `--output-header`/`--assumptions`), `gnatprove.sarif`, `gnatprove-version.txt` |
| `reports/coverage/xml/` | `make coverage-report-xml` | gnatcov XML report (`index.xml`, per-source XML, `trace.xml`), `gnatcov-version.txt` |
| `requirements/` | checked-in | `trace_waivers.yaml`, `hlr/*.yaml` (for waived/derived items) |

Outputs under `--out`: `evidence.json` (the normalized model, for debugging and
downstream tooling), `src/` (generated MyST sources), `html/` (the report),
and with `--pdf` (or `make report-pdf`) a `pdf/verification-report.pdf`
rendering built by rst2pdf — pure Python, no TeX toolchain required. The
strict `-W -n` HTML build remains the correctness oracle; the PDF is a
convenience rendering of the same sources.

## Architecture

```
collectors (gnatprove.py, gnatcov.py, traceability.py, provenance.py)
    -> Evidence (model.py, pydantic)  -> evidence.json
    -> review obligations (obligations.py)
    -> MyST pages (emit.py)
    -> sphinx-build -W -n (build.py)  -> html/
```

The Sphinx build runs with `-W -n` (warnings-as-errors, nitpicky references):
every claim-to-evidence cross-reference the emitters produce must resolve, or
the build fails. The build is itself the mechanical oracle for the report.

The review obligations follow the structure of NVIDIA's SPARK Process
(Software Unit Verification Report / `Review_Diagnostic_Justifications` /
coverage-deviation handling): machine-checkable assertions are rendered as
OK/FAIL with counts; genuinely human judgements (justification texts,
exemptions, waivers, non-SPARK code) are rendered as review items with
evidence links.

## Caveats

- All proof artifacts must come from **one** clean, forced gnatprove run
  (`make prove-report` guarantees this); gnatprove reuses per-unit results, so
  mixing runs with different switches produces inconsistent evidence. The
  report checks the recorded command line for `-f` and flags its absence.
- The coverage XML reflects whatever traces were on disk when it was
  generated — run the test suite under gnatcov first (`make all-coverage`).
  The report shows the trace dates so a reviewer can spot stale executions.
- The coverage-violation classification matches proved-check locations by
  source-file **basename**, per file (not per line); two files with the same
  basename in different directories would be conflated.
- The `.spark` format is documented as internal and may change with the SPARK
  release (SPARK UG "Looking at Machine-Parsable GNATprove Output"); the
  parsers here are written against FSF 16.1.0 and validated by fixtures.
- gnatprove's `--assumptions` listing is documented as partial (only
  assumptions on called subprograms are reported); the report says so.
- Requirement-level traceability rendering is partial pending the trace-chain
  work (`workflow/verification-report/plan.md`, phase 4).
