# Verification report generator — plan

Goal: an automated, regenerable **engineering trust report** covering proofs,
coverage, and traceability, whose front page tells a reviewer exactly what they
must personally review to establish the foundation for trust. Everything else
in the report is machine-derived evidence supporting that checklist.

## Decisions (2026-07-29)

- **Audience/register**: engineering trust report — factual sections + a
  generated review-obligations checklist. No ISO 26262 scaffolding; we borrow
  the NVIDIA SPARK Process *structure* (github.com/NVIDIA/spark-process,
  `source/process/process/unit-verification.rst`, `Develop_Verification_Report`;
  an untracked local clone sits under `tmp/spark-process/`) without
  mechanizing its checklists.
- **Format**: Sphinx rendering **MyST Markdown** sources, built with `-W -n`
  so any dangling claim→evidence cross-reference fails the build (the build is
  itself a mechanical oracle). Theme: furo. (Source excerpts use verbatim text
  from the gnatcov XML; if syntax-highlighted Ada is ever wanted, prefer
  Pygments' built-in Ada lexer — the NVIDIA clone's lexer is GPLv3.)
- **Home**: new **`engine/report/`** Python package, sibling of
  `engine/requirements/` (uv + hatchling + Typer + Pydantic, mirroring `reqs`).
  It may import `reqs` as a library for the traceability layer.
- **Lifecycle**: generated-only. `make report` writes under `reports/report/`
  (already gitignored via `reports/`); CI builds and publishes it like the
  coverage HTML pages. Requires adding the currently-missing `make prove` CI
  job.

## Data sources (established by research)

- **Proof** — gnatprove FSF 16.1.0. Per-unit JSON `obj/development/gnatprove/*.spark`
  (checks with rule/severity/location/prover/steps/time; `pragma_assume`;
  `assumptions`; `suppressed` justification text), `gnatprove.sarif`
  (SARIF 2.1.0, rule catalog, invocation metadata), `gnatprove.out`
  (summary table). Complete image requires a clean forced run:
  `gnatprove --clean` then
  `gnatprove -U -f --level=2 --report=statistics --assumptions --output-header`.
  Never mix artifacts from differently-switched runs. `.spark` locations are
  basenames only; prover versions come only from `gnatprove --version`.
- **Coverage** — gnatcov FSF 26.2. `--annotate=xml` is the full-fidelity
  format (ships an XSD; per-obligation stmt/decision/MC/DC with source spans;
  per-file and per-subprogram `scope_metric`; exempted regions carry their
  justification text — exempted = enclosing `src_mapping/@coverage` in `*`/`#`).
  Cobertura/SARIF are lossy (no MC/DC, no exemption justifications).
- **Traceability** — `reqs` (engine/requirements) checks CONOPS → HLR → LLR
  with waivers; `render_tables()` in `checks/trace.py` renders matrices; no
  machine-readable output yet (`reqs report` is the reserved future command).
  The chain has no code/test layers; `implemented_by` and requirement-ID
  comments in `src/`/`tests/` are validated by nothing. Deleted prior art
  (`tools/trace-check.py`, `tools/render-srs.py`) recoverable at
  `git show cb72122^:<path>`.

## Architecture

```
collectors (proof / coverage / traceability / provenance)
    → normalized Pydantic evidence model  → evidence.json (debuggable intermediate)
    → MyST emitters (index, provenance, proof, coverage, traceability)
    → sphinx-build -W -n → reports/report/html/
```

Report pages: `index` (verdict summary + review-obligations checklist),
`provenance` (tool versions incl. provers, exact commands, exit statuses, git
commit + dirty flag of the sources verified), `proof`, `coverage`,
`traceability`.

Review-obligation items, each cross-referenced to its evidence:

- every `pragma Assume` (currently 0 — report asserts the count),
- every justified/suppressed check (currently 0),
- every `Skip_Proof`/`Skip_Flow_And_Proof` (currently 0),
- units/entities with `SPARK_Mode` ≠ all (e.g. `main.adb`) — proven-by-review-and-test,
- unproved checks (currently 0),
- `--assumptions` claims remaining on the proof (documented-partial listing),
- coverage exemptions + their justification text,
- non-exempted coverage violations, classified via the NVIDIA deviation
  taxonomy by joining with proof data (e.g. proof-harness code such as
  `state_machine_loop_proof` is a recognized deviation class),
- trace waivers (`trace_waivers.yaml`) and derived requirements,
- tool-qualification note (FSF toolchain is unqualified),
- CONOPS validity (always human-owned).

## Phases

Statuses: `todo` / `in-progress` / `oracle-passed` / `blocked`.

Phases 0–3 landed 2026-07-29: `engine/report/` (package `vreport`, 39 tests,
mypy strict + full ruff set), `make report` renders
`reports/report/html/index.html` with 15 review obligations (currently 10
needing human review, 5 machine-checked OK). Implementation notes: the
residual-assumption logic discharges `--assumptions` entries that match
another proved claim or an entity verified clean by the same run; SARIF
supplies tag-suppressed warnings the `.spark` files don't carry; the package
requires Python ≥3.12 (Sphinx uses `type` statements).

An adversarial fresh-context review (2026-07-29) was addressed the same day:
coverage-violation classification now follows where proved checks are located
(per file — generic bodies get their evidence via instance analysis, so the
generic core classifies as proved and never-analyzed generic bodies do not);
the assumption discharge additionally requires the assumed-about entity to
have no unproved/justified checks and no ambiguous SPARK_Mode; the "single
forced run" and toolchain claims are computed from the recorded command
line/versions instead of asserted, with a dedicated evidence-consistency
obligation; exemption justifications attribute masked violations per region;
malformed artifacts fail with the file named.

### Phase 0 — enablers `oracle-passed`

Small Makefile/CI/doc fixes that everything else consumes.

- `coverage-report-xml` target (`--annotate=xml` → `reports/coverage/xml/`).
- `prove-report` target: clean + forced full run with `--assumptions
  --output-header` (keep plain `prove` as the gate; the report target must
  produce artifacts even with unproved checks, recording the exit status).
- Fix stale oracle names (`all-coverage-pro`, `test-pro`, `generate-tests-pro`)
  in `engine/workflow/tasks/*.md` and `.claude/agents/*.md` → current target
  names.
- Remove the stale `src/obj/development/gnatprove/` tree (done by hand; the
  underlying cause was fixed separately); generator pins
  `obj/development/gnatprove/` exactly (no globbing for gnatprove dirs).
- Oracle: `make check && make coverage-report-xml && make prove-report`
  produce the expected artifacts. (Note: on this box `check-ada` fails on the
  three known community-gnatformat drift files, unrelated to this feature.)

### Phase 1 — package skeleton + provenance + proof section `oracle-passed`

- Scaffold `engine/report/` (uv, hatchling, Typer CLI, pytest; deps: pydantic,
  sphinx, myst-parser, furo; mirror `engine/requirements` layout and the
  `check-python` lint set: ruff + mypy strict).
- Proof collector: parse `*.spark` + `gnatprove.sarif` (+ `gnatprove.out`
  header block); capture `gnatprove --version`, git commit/dirty state.
- Emit provenance + proof pages; `make report` wires collect → emit →
  sphinx-build.
- Oracle: `make report` succeeds under `-W -n` against current artifacts;
  `pytest` parser tests pass (fixtures: real `.spark`/SARIF samples, incl. a
  synthetic unproved/justified case so those paths are tested while the
  codebase has none).

### Phase 2 — coverage section `oracle-passed`

- Coverage collector: parse `reports/coverage/xml/` (index + per-file;
  ElementTree only — XSD validation deliberately skipped, revisit if the
  format drifts).
- Metrics tables (global / per-file / per-subprogram), violation list,
  exemptions with justifications; join with proof data to classify violations
  (proven subprogram / proof-support code / app shell).
- Oracle: `make report` includes coverage; pytest fixtures cover exempted and
  non-exempted cases.

### Phase 3 — review-obligations synthesis `oracle-passed`

- The trust checklist on `index`, generated from all collectors; each item
  either a machine-checked assertion (rendered PASS/FAIL with counts) or a
  manual-review item with evidence links.
- Oracle: `make report` under `-W -n`; a test asserting every obligation item
  resolves to an existing evidence anchor.

### Phase 4 — traceability section `todo` (deferred; ongoing reqs work)

- Machine-readable output from `reqs` (either `--format json` on `trace`, or
  import its API directly from `engine/report`).
- Render per-pair matrices, waivers, derived requirements.
- Later, as the reqs work matures: code/test trace layers (verify
  `implemented_by` against real Ada entities; scan requirement-ID comments in
  `src/` and `tests/`; `tools/trace-check.py` from git history is precedent).
- Oracle: `make report` renders traceability; matrix agrees with
  `reqs trace` diagnostics on fixtures.

### Phase 5 — CI publishing `todo`

- CI job running `make prove-report coverage-report-xml report` (community
  toolchain path) and publishing `reports/report/html/` via pages, alongside
  the existing coverage HTML.
- Oracle: pipeline green; published report reachable.

## Open items (not blocking)

- Whether to add a small test-results section (AUnit runner output is text
  only; pass/fail counts are scrapeable) — SWVR precedent says yes, cheap.
- PDF output (`latexpdf`) if ever needed — deliberately out of scope now.
