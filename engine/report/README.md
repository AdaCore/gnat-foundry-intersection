# vreport — verification-report generator

Collects the machine-readable evidence left by the verification tools and
renders it as a Sphinx/MyST HTML report whose front page tells a reviewer
exactly what they must personally review to establish trust in the artifact.
Everything else in the report is supporting evidence for that checklist.

## Usage

```bash
vreport generate --root <repo> --out <repo>/reports/report
vreport signoff  --root <repo>                   # what needs a human, and who signed it
vreport signoff  --root <repo> --item conops     # record that a human reviewed it
```

or, from the repository root, `make report`, whose prerequisites regenerate
the tool inputs so the report never describes stale artifacts. Inputs (when
invoking `vreport` directly, produce them first):

| Input | Producer | Contents |
|---|---|---|
| `obj/development/gnatprove/` | `make prove-report` | per-unit `*.spark` JSON, `gnatprove.out` (with `--output-header`/`--assumptions`), `gnatprove.sarif`, `gnatprove-version.txt` |
| `reports/coverage/xml/` | `make coverage-report-xml` | gnatcov XML report (`index.xml`, per-source XML, `trace.xml`), `gnatcov-version.txt`, `gnatcov-command.txt` (the recorded invocation) |
| `reports/trace/trace_report.json` | `make trace-report` | `reqs trace --format json` over the whole chain: per-pair matrices, the merged verification view, gate diagnostics, recorded command |
| `obj/analysis/code_inventory.json` | `make code-inventory` | the Ada tracer's libadalang parse of the project's own sources; the report reads the generics it declares |
| `requirements/` | checked-in | `conops.md`, `trace_waivers.yaml`, `hlr/*.yaml` (the waived and derived items), `signoffs.yaml` (who reviewed them) |
| `reports/requirements/` | `make requirements-doc` | the requirements rendered as a document: `pages/*.md` (the CONOPS, HLR and LLR, plus a listing of each cited source under `pages/sources/`) and `index.json` (each layer's title, pages and top-level pages, each node's page and anchor) |

Outputs under `--out`: `evidence.json` (the normalized model, for debugging and
downstream tooling), `src/` (generated MyST sources), `html/` (the report),
and with `--pdf` (or `make report-pdf`) a `pdf/verification-report.pdf`
rendering built by rst2pdf — pure Python, no TeX toolchain required. The
strict `-W -n` HTML build remains the correctness oracle; the PDF is a
convenience rendering of the same sources.

## Architecture

```
collectors (gnatprove.py, gnatcov.py, traceability.py, requirements.py,
            inventory.py, provenance.py)
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
the Requirements section: a page per chain layer, entering that layer's
top-level containers, which in turn enter the containers nested under them. The
layer pages are emitted here, because which layers the report carries and in
what order is the report's own structure; the nesting below them comes from the
render, which is what knows how the containers relate. Neither the section page
nor a layer's page says anything but its heading and its contents: a page whose
whole job is to enter the next one is not the place to describe the rendering,
and what produced the pages is recorded with the other tool invocations on the
provenance page. Their statements are what
the trace matrices link to, resolved through `index.json` — so a matrix id that
names no rendered statement fails the build rather than shipping a dead link.
The render is optional input: without it the report says everything it said
before, with matrix ids as plain text.

The source listings are a section of their own, after the traceability page:
they are what the evidence links *into*, read from a requirement or a matrix
rather than in their own right. Each cited line names the requirements resting
on it, so the navigation runs back up as well. They are marked HTML-only
*inside* their pages, so the PDF rendering carries each cited line's anchor and
its citing requirements but not the source; the pages themselves are in both
renderings, because a link that resolves in one and dangles in the other is a
broken document (and rst2pdf fails the build on one, which `build_pdf` now
catches -- it logs a failed document and exits 0, leaving an empty file).

### Generics

gnatprove analyzes generic *instances*, never generics, and it records the two
kinds of generic differently. A library-level generic gets an artifact of its
own, stopped with `STOP_REASON_GENERIC_UNIT` and empty; the checks its body
contributes are located in its sources but attributed to whichever unit
instantiated it. A generic nested in an ordinary package gets no artifact and
no entity in its own unit's -- it appears only on the instantiating side, as an
entity whose `sloc` chain runs from the declaration inside the generic to the
instantiation that reached it.

So the generics table is a join. Its rows are the generics the *code inventory*
declares, bounded by the units gnatprove analyzed; what fills the "analyzed
through" column is those sloc chains, plus the checks located in a generic's
sources under another unit's name (which is all the evidence a library-level
generic's body leaves). Taking the rows from gnatprove's output instead would
be circular in the way a coverage denominator scoped by what already traces is
circular: a generic no analyzed instance reaches is precisely what that output
has nothing to say about, and precisely the case the table exists to catch.

Attribution is per line, not per file, because one file can declare several
generics and the package enclosing them -- a file-level match would credit
each of `buses.ads`'s two bus generics with the other's instance. A location
in a file with no anchors of its own (a library-level generic's body, which
the inventory anchors only at its spec) falls back to the unit, and only when
exactly one generic claims it.

The inventory is optional input: without it the table falls back to the generic
units gnatprove reported, says in the section and in the obligation that it can
no longer see nested generics, and holds the obligation open.

The review obligations follow the structure of NVIDIA's SPARK Process
(Software Unit Verification Report / `Review_Diagnostic_Justifications` /
coverage-deviation handling): machine-checkable assertions are rendered as
OK/FAIL with counts; genuinely human judgements (justification texts,
exemptions, waivers, non-SPARK code) are rendered as review items with
evidence links.

### Sign-offs

Three of those judgements can be discharged by nothing but a reading: the
waivers excusing CONOPS leaves from HLR coverage, the derived HLR statements
that have no CONOPS parent, and the CONOPS itself. `requirements/signoffs.yaml`
records the reading, one entry per item:

```yaml
signoffs:
  - item: conops                    # or waiver:<leaf>, or derived:<statement id>
    digest: sha256:7d6dcc07…        # of the text reviewed (signoff.py builds it)
    by: A Reviewer
    date: '2026-08-21'
    note: what the review established   # optional
```

The digest is the mechanism. It is taken over the same string the report
renders for that item, so a sign-off covers exactly what a reader sees; edit
the text and the digest no longer matches, the sign-off lapses, and its
obligation re-opens saying so. Against a baseline where every item is signed,
an unreviewed change is the only thing that shows — which is the point, for a
report read after an agent has been through the requirements.

`vreport signoff` (`make signoff`) lists the items with their state and stamps
one, or `--all` outstanding; the digest is computed, `by` defaults to git's
`user.name` and `date` to today. Without the file the three obligations read as
they did before sign-offs existed, so the mechanism is opt-in and the engine
stays project-agnostic.

Sign-offs are a record of human review, **not** an attestation anything
enforces: whatever can write the repository can write that file. What they buy
is that a change to them is conspicuous in a diff. Automated work must
therefore never stamp one (`engine/workflow/README.md` says so for the feature
workflow).

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
