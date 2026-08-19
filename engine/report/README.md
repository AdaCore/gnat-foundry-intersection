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
| `reports/coverage/xml/` | `make coverage-report-xml` | gnatcov XML report (`index.xml`, per-source XML, `trace.xml`), `gnatcov-version.txt`, `gnatcov-command.txt` (the recorded invocation) |
| `reports/trace/trace_report.json` | `make trace-report` | `reqs trace --format json` over the whole chain: per-pair matrices, the merged verification view, gate diagnostics, recorded command |
| `requirements/` | checked-in | `trace_waivers.yaml`, `hlr/*.yaml` (for waived/derived items) |
| `reports/requirements/` | `make requirements-doc` | the requirements rendered as a document: `pages/*.md` plus `index.json` (each statement's page and anchor) |

Outputs under `--out`: `evidence.json` (the normalized model, for debugging and
downstream tooling), `src/` (generated MyST sources), `html/` (the report),
and with `--pdf` (or `make report-pdf`) a `pdf/verification-report.pdf`
rendering built by rst2pdf — pure Python, no TeX toolchain required. The
strict `-W -n` HTML build remains the correctness oracle; the PDF is a
convenience rendering of the same sources.

## Architecture

```
collectors (gnatprove.py, gnatcov.py, traceability.py, requirements.py, provenance.py)
    -> Evidence (model.py, pydantic)  -> evidence.json
    -> review obligations (obligations.py)
    -> MyST pages (emit.py)
    -> sphinx-build -W -n (build.py)  -> html/
```

The Sphinx build runs with `-W -n` (warnings-as-errors, nitpicky references):
every claim-to-evidence cross-reference the emitters produce must resolve, or
the build fails. The build is itself the mechanical oracle for the report.

The rendered requirement pages are *copied* into the generated tree rather than
emitted (they are already the rendering; `reqs document` owns it) and appear as
the Requirements section. Their statements are what the trace matrices link to,
resolved through `index.json` — so a matrix id that names no rendered statement
fails the build rather than shipping a dead link. The render is optional input:
without it the report says everything it said before, with matrix ids as plain
text.

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
  generated — run the requirements-based tests under gnatcov first
  (`make all-coverage`).
  The report shows the trace dates so a reviewer can spot stale executions.
- The coverage-violation classification matches proved-check locations by
  source-file **basename**, per file (not per line); two files with the same
  basename in different directories would be conflated.
- Parsed messages are reconciled with the metric counters from the same
  report: coverage gaps or exemptions that appear only in the counters (e.g.
  undetermined coverage, or a drifted message format) render as review items
  rather than a green "none". Likewise a missing `gnatprove.sarif` flags the
  warnings item (falling back to the `.spark` `warn_error` records), and a
  unit whose `.spark` records an early analysis stop is flagged as
  incomplete.
- Every "none" in the proof sections is bounded by the **analyzed scope**: the
  units the run reached, listed on the proof page. `gnatprove -U` analyzes the
  tree of the project it is rooted at, so code outside that tree is absent from
  the report rather than cleared by it, and the boundary obligation says so.
- A generic unit is not an early stop: gnatprove skips generics and analyses
  their *instances*, so a generic's own artifact is empty by construction. The
  evidence that one was analysed at all is a check **located** in its sources
  but attributed to the instantiating unit, and a generic with no such check
  is reported as having no analyzed instance — unproved code that no other
  section names. Matched by source-file stem, with the same basename caveat.
  This is a **unit-level** check: it sees only what gnatprove reports as a
  generic unit, so a generic package *nested* inside an ordinary unit is not
  covered by it. Such a unit shows in the scope table with its true check count
  (often zero) beside any unit that did locate checks in its sources, so a
  nested generic an instance reaches is credited there and a zero standing
  alone is the signal to read.
- Evidence-carried free text (justifications, waiver reasons, tool messages)
  is escaped before interpolation into the MyST sources, so it cannot break
  the report structure or plant cross-references that fail the strict build.
- The `.spark` format is documented as internal and may change with the SPARK
  release (SPARK UG "Looking at Machine-Parsable GNATprove Output"); the
  parsers here are written against FSF 16.1.0 and validated by fixtures.
- gnatprove's `--assumptions` listing is documented as partial (only
  assumptions on called subprograms are reported); the report says so.
- The traceability items report only what the requirements tree *records*
  (waivers, `derived:` flags); that the CONOPS → HLR → LLR chain actually
  holds is `make validate-reqs`'s verdict, and down to the code
  `make trace-check`'s. Neither gates `make report` — gaps render as open items
  with their diagnostics, so a report is available part-way through a project —
  but `validate-reqs-corpus` (schema + EARS) does, since an unparseable corpus
  yields `corpus_valid: false` and no matrices. Each source is tracked
  separately: a missing `trace_waivers.yaml` or `requirements/hlr/` renders as a
  review item, never as a green "none".
