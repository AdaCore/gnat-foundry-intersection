"""
Render the evidence and review obligations as MyST Markdown pages.

Every claim on the index page cross-references (`{ref}`) an explicit target
(`(name)=`) on an evidence page; the Sphinx build runs with `-W -n`, so a
reference to a missing target fails the build.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING

from vreport.mdtext import code_span, count, inline
from vreport.model import (
    EXEMPTED,
    EXEMPTED_NO_VIOLATION,
    FULLY_COVERED,
    NOT_COVERED,
    PARTIALLY_COVERED,
    TOTAL_LINES,
    UNDETERMINED,
    CheckStatus,
    GenericAnalysis,
    ObligationStatus,
    TraceRow,
)
from vreport.obligations import (
    OpenTraceItem,
    classify_violation,
    open_claims,
    open_trace_items,
    predicate_label,
    rowless_trace_findings,
)
from vreport.signoff import (
    CONOPS_ITEM,
    derived_item,
    derived_subject,
    digest_of,
    waiver_item,
    waiver_subject,
)

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence

    from vreport.model import (
        Evidence,
        MethodFacet,
        Obligation,
        ProofEvidence,
        RequirementLayer,
        RequirementsDocument,
        TraceDiagnostic,
        TracePair,
        TraceReport,
        VerificationRow,
    )

_PAGE_ORDER = ("provenance", "proof", "coverage", "traceability")

# Where the rendered requirement pages are copied to inside the source tree.
REQUIREMENTS_SUBDIR = "requirements"


def _page_order(ev: Evidence) -> tuple[str, ...]:
    """Return the top-level pages in reading order, with the requirements when rendered."""
    if ev.requirements is None:
        return _PAGE_ORDER
    index = _PAGE_ORDER.index("traceability")
    # The source listings last: they are what the evidence links *into*, read
    # from a requirement or a matrix rather than in their own right.
    listings = ("source-listings",) if ev.requirements.sources else ()
    return (*_PAGE_ORDER[:index], "requirements", *_PAGE_ORDER[index:], *listings)


def _req_link(doc: RequirementsDocument | None, layer: str, node: str) -> str:
    """
    Render a chain node as a link to its requirement text, where there is one.

    Anchors come from the render's index rather than being derived here: the
    renderer owns how a statement is spelled as a target. A node of a layer the
    document does not render (a CONOPS leaf, a test routine) stays plain text.
    """
    statement = doc.statement(layer, node) if doc else None
    if statement is None:
        return code_span(node)
    return f"[{code_span(node)}](#{statement.anchor})"


def _esc(cell: str) -> str:
    """Escape a value for use inside a Markdown table cell."""
    return cell.replace("|", "\\|").replace("\n", " ")


def _table(headers: Sequence[str], rows: Iterable[Sequence[str]]) -> str:
    """Render a Markdown pipe table."""
    lines = [
        "| " + " | ".join(headers) + " |",
        "|" + "|".join("---" for _ in headers) + "|",
    ]
    lines.extend("| " + " | ".join(_esc(c) for c in row) + " |" for row in rows)
    return "\n".join(lines)


def _table_or(headers: Sequence[str], rows: list[Sequence[str]], empty: str) -> str:
    """Render a table, or a plain sentence when there are no rows."""
    return _table(headers, rows) if rows else empty


def _target(name: str) -> str:
    """Render an explicit MyST cross-reference target."""
    return f"({name})="


def _code(text: str, lang: str = "text") -> str:
    """Render a fenced code block, its fence sized past any backtick run in the text."""
    longest = max((len(run) for run in re.findall(r"`+", text)), default=0)
    fence = "`" * max(3, longest + 1)
    return f"{fence}{lang}\n{text}\n{fence}"


def _admonition(title: str, body: str, *, kind: str) -> str:
    """Render a MyST admonition (colon fence)."""
    return f":::{{admonition}} {title}\n:class: {kind}\n\n{body}\n:::"


def _flat(text: str) -> str:
    """Collapse newlines: fences and list items break at line starts."""
    return text.replace("\n", " ")


def _obligation_admonition(ob: Obligation) -> str:
    """Render one review obligation as an admonition with its evidence link."""
    parts = [_flat(ob.detail)]
    if ob.items:
        parts.append("\n".join(f"- {_flat(item)}" for item in ob.items))
    parts.append(f"Evidence: {{ref}}`{ob.anchor}`")
    kind = "tip" if ob.status is ObligationStatus.ok else "warning"
    prefix = "OK" if ob.status is ObligationStatus.ok else "Review"
    return _admonition(f"{ob.ident} ({prefix}) — {ob.title}", "\n\n".join(parts), kind=kind)


def _cov_cell(covered: int, total: int) -> str:
    """Render a covered/total table cell, dash when nothing applies."""
    return f"{covered}/{total}" if total else "—"


def _strip_tool_paths(text: str | None) -> str | None:
    """
    Reduce absolute tool paths in version output to basenames.

    The prover paths in `gnatprove --version` describe this machine's install
    layout, not the toolchain identity — and they overflow the PDF frame.
    """
    if text is None:
        return None
    return "\n".join(re.sub(r"^/\S*/", "", line) for line in text.splitlines())


def _emit_index(ev: Evidence, obligations: list[Obligation]) -> str:
    """Render the front page: at-a-glance summary plus the review obligations."""
    checks = ev.proof.checks
    proved = sum(1 for c in checks if c.status is CheckStatus.proved)
    review = [o for o in obligations if o.status is ObligationStatus.review]
    ok = len(obligations) - len(review)

    git_row = "not a git checkout"
    if ev.git:
        state = "dirty" if ev.git.dirty else "clean"
        git_row = f"`{ev.git.commit[:12]}` on `{ev.git.branch}` ({state})"

    report = ev.traceability.report
    if report is None:
        trace_row = "no trace report — regenerate with `make trace-report`"
    elif not report.corpus_valid:
        trace_row = "requirement corpus invalid — see the traceability page"
    else:
        n_open = len(open_trace_items(report)) + len(rowless_trace_findings(report))
        trace_row = (count(n_open, "open item") if n_open else "no open items") + (
            f" ({count(report.errors, 'gate error')}, {count(report.warnings, 'warning')})"
        )

    glance_rows: list[Sequence[str]] = [
        (
            "Proof",
            (
                f"{len(checks)} checks: {proved} proved, "
                f"{len(ev.proof.unproved_checks)} unproved, "
                f"{len(ev.proof.justified_checks)} justified"
            ),
        ),
        *[
            (
                f"Coverage ({o.kind})",
                f"{_cov_cell(o.covered, o.total)} covered"
                + (f" ({o.pct}%)" if o.pct is not None else "")
                + f", {o.not_covered} uncovered, {o.exempted} exempted",
            )
            for o in ev.coverage.obligations
        ],
        ("Traceability", trace_row),
        ("Review obligations", f"{len(review)} need review, {ok} machine-checked OK"),
        ("Sources", git_row),
    ]

    toctree = "```{toctree}\n:hidden:\n\n" + "\n".join(_page_order(ev)) + "\n```"
    obligation_blocks = "\n\n".join(_obligation_admonition(o) for o in obligations)
    return f"""# {ev.title}

Generated {ev.generated_at} by `vreport`. This report collects the evidence
left by the verification tools (gnatprove, gnatcov, the requirements chain)
and reduces it to the checklist below: what a reviewer must personally examine
to establish trust in this software. Tool versions, exact commands and source
state are recorded under {{ref}}`provenance`.

## At a glance

{_table(("Area", "Result"), glance_rows)}

## What to review

Items marked **OK** are machine-checked assertions about the evidence; items
marked **Review** require human judgement and link to the evidence to judge.

{obligation_blocks}

{toctree}
"""


def _emit_provenance(ev: Evidence) -> str:
    """Tool versions, invocations, and source state."""
    git_rows: list[Sequence[str]] = []
    if ev.git:
        git_rows = [
            ("Commit", f"`{ev.git.commit}`"),
            ("Branch", f"`{ev.git.branch}`"),
            ("Working tree", "dirty — uncommitted changes" if ev.git.dirty else "clean"),
        ]
        if ev.git.describe:
            git_rows.append(("Describe", f"`{ev.git.describe}`"))
    git_block = _table_or(
        ("Field", "Value"), git_rows, "The report was not generated from a git checkout."
    )

    header = ev.proof.header
    inv = ev.proof.invocation
    prove_rows: list[Sequence[str]] = []
    if header:
        prove_rows.extend(
            (label, f"`{value}`")
            for label, value in (
                ("Command", header.command_line),
                ("Date", header.date),
                ("Host", header.host),
                ("Version", header.version),
            )
            if value
        )
    if inv and inv.exit_code is not None:
        prove_rows.append(("Exit code", f"`{inv.exit_code}`"))

    trace_rows: list[Sequence[str]] = [
        (t.program, t.date, f"`{t.filename.rsplit('/', 1)[-1]}`") for t in ev.coverage.traces
    ]

    gnatprove_version = _code(_strip_tool_paths(ev.proof.version_text) or "version not recorded")
    gnatcov_version = _code(ev.coverage.version_text or "version not recorded")

    forced = header is not None and header.forced
    prove_para = (
        "The recorded gnatprove command line shows a forced (`-f`) re-analysis, so "
        "every unit's artifacts come from this single invocation:"
        if forced
        else "**Warning:** no recorded gnatprove command line shows a forced (`-f`) "
        "run — per-unit artifacts may be stale carry-overs from earlier runs; "
        "regenerate with `make prove-report`."
    )

    # `make coverage-report-xml` records the command only after a zero exit.
    cov_block = (
        _code(ev.coverage.command_text)
        + "\n\n(The command file is written only after a zero exit status.)"
        if ev.coverage.command_text
        else "**Warning:** no gnatcov invocation record (`gnatcov-command.txt`) was "
        "found — the coverage XML cannot be tied to a command line; regenerate "
        "with `make coverage-report-xml`."
    )

    report = ev.traceability.report
    if report is not None and report.command:
        run_at = f"\n\n(run at {inline(report.generated_at)})" if report.generated_at else ""
        trace_block = _code(report.command) + run_at
    else:
        trace_block = (
            "**Warning:** no recorded `reqs trace` invocation — the trace matrices "
            "cannot be tied to a command line; regenerate with `make trace-report`."
        )

    # The requirement pages carry no provenance of their own: they are the
    # rendering, and a rendering that explained itself would read as part of the
    # requirements. What produced them is recorded here, with the other tools.
    doc = ev.requirements
    if doc is None:
        render_block = ""
    elif doc.command:
        rendered_at = f"\n\n(run at {inline(doc.generated_at)})" if doc.generated_at else ""
        render_block = (
            "\nThe requirement pages were rendered from the requirement files by:\n\n"
            + _code(doc.command)
            + rendered_at
            + "\n"
        )
    else:
        render_block = (
            "\n**Warning:** the requirement pages carry no recorded `reqs document` "
            "invocation — they cannot be tied to a command line; regenerate with "
            "`make requirements-doc`.\n"
        )

    return f"""{_target("provenance")}

# Provenance

{_target("provenance-git")}

## Sources

{git_block}

{_target("provenance-tools")}

## Tools

GNATprove's results are sound subject to its documented assumptions
(SPARK User's Guide, "GNATprove Assumptions").

gnatprove (with provers):

{gnatprove_version}

gnatcov:

{gnatcov_version}

{_target("provenance-invocations")}

## Invocations

{prove_para}

{_table_or(("Field", "Value"), prove_rows, "No gnatprove header was recorded.")}

gnatcov analyzed at level `{ev.coverage.level}`, invoked as:

{cov_block}

from these test executions:

{_table_or(("Program", "Date", "Trace"), trace_rows, "No trace information was recorded.")}

The requirement-trace matrices were produced by:

{trace_block}
{render_block}"""


def _instances_cell(g: GenericAnalysis) -> str:
    """List where a generic's analyzed instances are, for the generics table."""
    if not g.instances:
        return "**none**"
    return ", ".join(
        f"{i.unit} ({code_span(str(i.site))})" if i.site else i.unit for i in g.instances
    )


def _hosted_generics(generics: Sequence[GenericAnalysis], unit: str) -> list[GenericAnalysis]:
    """Return the generics a unit's own sources declare (by Ada's file-per-unit naming)."""
    return [g for g in generics if Path(g.declared_in).stem == unit and g.kind != "unit"]


def _scope_cell(p: ProofEvidence, generics: Sequence[GenericAnalysis], unit: str) -> str:
    """Say how one in-scope unit was treated, for the scope table."""
    analysis = next((a for a in p.analyses if a.unit == unit), None)
    if analysis is None:
        return "no completion record"
    if analysis.generic:
        row = next((g for g in generics if Path(g.declared_in).stem == unit), None)
        through = ", ".join(i.unit for i in row.instances) if row else ""
        return f"generic, through {through}" if through else "generic, **no instance analyzed**"
    if not analysis.complete:
        return f"stopped: `{analysis.stop_reason or 'unrecorded'}`"
    own = count(sum(1 for c in p.checks if c.unit == unit), "check")
    # A unit's own check count says nothing about the generics nested in it:
    # their checks are recorded under whichever unit instantiates them. Count
    # them here so a nested generic no instance reached cannot hide behind the
    # enclosing unit's ordinary "N checks".
    hosted = _hosted_generics(generics, unit)
    if not hosted:
        return own
    reached = sum(1 for g in hosted if g.analyzed)
    tally = (
        f"all {count(len(hosted), 'nested generic')} analyzed"
        if reached == len(hosted)
        else f"**{len(hosted) - reached} of {count(len(hosted), 'nested generic')} "
        "with no instance analyzed**"
    )
    return f"{own}; {tally}"


def _emit_proof(ev: Evidence) -> str:
    """Render the gnatprove evidence page."""
    p = ev.proof

    incomplete_rows: list[Sequence[str]] = [
        (a.unit, f"`{a.progress or 'unrecorded'}`", f"`{a.stop_reason or 'unrecorded'}`")
        for a in p.incomplete_analyses
    ]
    unproved_rows: list[Sequence[str]] = [
        (f"`{c.location}`", c.rule, c.entity or "", inline(c.message or ""))
        for c in p.unproved_checks
    ]
    justified_rows: list[Sequence[str]] = [
        (f"`{c.location}`", c.rule, c.entity or "", inline(c.justification or ""))
        for c in p.justified_checks
    ]
    assume_rows: list[Sequence[str]] = [(f"`{a.location}`", a.entity or a.unit) for a in p.assumes]
    skip_rows: list[Sequence[str]] = [(s.entity, s.kind, s.unit) for s in p.skips]
    warning_rows: list[Sequence[str]] = [
        (
            f"`{w.location}`" if w.location else "—",
            w.rule,
            inline(w.message),
            "yes" if w.suppressed else "no",
        )
        for w in p.warnings
    ]
    boundary_rows: list[Sequence[str]] = [
        (m.entity, f"`{m.mode}`", m.unit, f"`{m.location}`" if m.location else "—")
        for m in p.non_spark_entities
    ]
    fully = sum(1 for m in p.spark_modes if m.mode == "all")

    residual = open_claims(p)
    claim_rows: list[Sequence[str]] = [
        (
            c.claim.entity or c.unit,
            predicate_label(c.claim.predicate),
            "; ".join(f"{predicate_label(a.predicate)} of {a.entity}" for a in refs),
        )
        for c, refs in residual
    ]

    check_rows: list[Sequence[str]] = [
        (
            c.unit,
            f"`{c.location}`",
            c.rule,
            c.entity or "",
            c.status,
            ", ".join(c.provers) if c.provers else (c.how_proved or ""),
        )
        for c in p.checks
    ]

    summary_block = _code(p.summary_text) if p.summary_text else "No gnatprove.out summary found."

    forced = p.header is not None and p.header.forced
    run_note = (
        "Everything below comes from one forced (`-f`) run — see {ref}`provenance-invocations`."
        if forced
        else "**Warning:** the recorded command line does not show a forced (`-f`) "
        "run; per-unit artifacts may be stale carry-overs — regenerate with "
        "`make prove-report` (see {ref}`provenance-invocations`)."
    )

    completeness_block = (
        _table(("Unit", "Progress", "Stop reason"), incomplete_rows)
        if incomplete_rows
        else f"All {len(p.analyses) - len(p.generic_analyses)} non-generic unit "
        "analyses ran to the end of the proof phase."
        if p.analyses
        else "The `.spark` artifacts carry no completion records."
    )

    generics = ev.generics
    scope_block = (
        _table(("Unit", "Analysis"), [(u, _scope_cell(p, generics, u)) for u in p.units])
        if p.units
        else "No unit artifacts were recorded."
    )

    generic_rows: list[Sequence[str]] = [
        (
            g.name,
            g.kind,
            code_span(g.declared_in),
            _instances_cell(g),
        )
        for g in generics
    ]
    generics_note = (
        ""
        if ev.inventory
        else "\n\n**Warning:** the code inventory was not recorded, so this list "
        "comes from gnatprove's own output and names only *library-level* "
        "generics — a generic nested in an ordinary package cannot appear. "
        "Regenerate with `make code-inventory`."
    )

    warnings_note = (
        ""
        if p.sarif_found
        else "\n\n**Warning:** `gnatprove.sarif` was not recorded — the list below "
        "is recovered from the per-unit `.spark` artifacts; suppression detail "
        "may be incomplete and the exit code is lost. Regenerate with "
        "`make prove-report`."
    )

    return f"""{_target("proof")}

# Proof

gnatprove analyzed {len(p.units)} units toward the project's Silver target
(absence of run-time errors); the contracts written in the code are proved by
the same analysis (see the summary table). {run_note}

{_target("proof-scope")}

## Analysis scope

Every claim on this page is bounded by the units below. `gnatprove -U` analyzes
the project tree it is rooted at, so the root project chooses this list; the
exact command is under {{ref}}`provenance-invocations`. Code outside the list is
**not** described by this report — neither proved nor reported unproved — so
read "none" in the sections that follow as "none among these units". Whether
this is the right scope to verify is a human judgement, made where the scope is
declared and not re-derived here. A cell counts the checks recorded under its
unit; checks from a generic's body are recorded under whichever unit
instantiates it ({{ref}}`proof-generics`), so where that happens inside a unit's
own sources the cell names the instantiating unit too.

{scope_block}

{_target("proof-completeness")}

## Analysis completeness

Units whose recorded analysis stopped early list only part of their checks;
every table below is qualified by this one.

{completeness_block}

{_target("proof-generics")}

## Generics

gnatprove analyzes generic *instances*, not generics: a generic's own artifact
records no checks, and the checks from its body are attributed to the
instantiating unit while staying located in the generic's source. A generic
reached by no analyzed instance is therefore unproved code that no other table
names.

Every generic the in-scope sources declare has a row below, listed from the
code inventory rather than from gnatprove's output — a generic nothing
instantiates is exactly what that output has nothing to say about, so scoping
this table by what the analysis saw would hide the case it exists to catch.
"Analyzed through" names each instantiating unit, with the instantiation site
where gnatprove recorded one.{generics_note}

{
        _table_or(
            ("Generic", "Kind", "Declared in", "Analyzed through"),
            generic_rows,
            "The in-scope sources declare no generics.",
        )
    }

{_target("proof-summary")}

## Summary

Verbatim from `gnatprove.out`:

{summary_block}

{_target("proof-unproved")}

## Unproved checks

{_table_or(("Location", "Rule", "Entity", "Message"), unproved_rows, "None.")}

{_target("proof-justified")}

## Justified checks

Checks discharged by a `pragma Annotate (GNATprove, ...)` justification —
human claims, not proofs:

{_table_or(("Location", "Rule", "Entity", "Justification"), justified_rows, "None.")}

{_target("proof-assumes")}

## `pragma Assume` occurrences

Facts injected into the proof context without proof:

{_table_or(("Location", "Entity"), assume_rows, "None.")}

{_target("proof-skips")}

## Skipped-proof annotations

{_table_or(("Entity", "Kind", "Unit"), skip_rows, "None.")}

{_target("proof-warnings")}

## Tool warnings

Warnings from the run, including tag-suppressed ones (a suppressed warning is
a human decision that the condition is benign):{warnings_note}

{_table_or(("Location", "Rule", "Message", "Suppressed"), warning_rows, "None.")}

{_target("proof-spark-modes")}

## Analysis boundary

{fully} entities are fully in SPARK (`SPARK_Mode` covers spec and body).
Entities **not** fully analyzed — their bodies carry no proof:

{
        _table_or(
            ("Entity", "Mode", "Unit", "Declared at"),
            boundary_rows,
            "None — every analyzed entity is fully in SPARK.",
        )
    }

{_target("proof-claims")}

## Residual proof assumptions

From `gnatprove --assumptions`: proved claims and the assumptions they rest
on. An assumption is discharged within the run when it matches another proved
claim or concerns an entity fully in SPARK (analyzed by the same run); of
{len(p.claims)} claims, {len(p.claims) - len(residual)} close that way.
gnatprove documents the listing as partial (assumptions are reported only for
called subprograms).

{
        _table_or(
            ("Claim on", "Property", "Rests on"),
            claim_rows,
            "No claim carries residual assumptions.",
        )
    }

{_target("proof-checks")}

## All checks

{
        _table_or(
            ("Unit", "Location", "Rule", "Entity", "Status", "Discharged by"),
            check_rows,
            "No checks were recorded.",
        )
    }
"""


def _emit_coverage(ev: Evidence) -> str:
    """Render the gnatcov evidence page."""
    c = ev.coverage

    summary_rows: list[Sequence[str]] = [
        (
            o.kind,
            str(o.total),
            str(o.covered),
            str(o.counts.get(PARTIALLY_COVERED, 0)),
            str(o.not_covered),
            str(o.counts.get(UNDETERMINED, 0)),
            str(o.exempted),
            f"{o.pct}%" if o.pct is not None else "—",
        )
        for o in c.obligations
    ]
    summary_rows.append(
        (
            "Lines",
            str(c.counts.get(TOTAL_LINES, 0)),
            str(c.counts.get(FULLY_COVERED, 0)),
            str(c.counts.get(PARTIALLY_COVERED, 0)),
            str(c.counts.get(NOT_COVERED, 0)),
            str(c.counts.get(UNDETERMINED, 0)),
            str(c.counts.get(EXEMPTED, 0) + c.counts.get(EXEMPTED_NO_VIOLATION, 0)),
            "—",
        )
    )

    file_rows: list[Sequence[str]] = []
    for f in c.files:
        by_kind = {o.kind: o for o in f.obligations}
        cells = [
            _cov_cell(by_kind[k].covered, by_kind[k].total) if k in by_kind else "—"
            for k in ("Stmt", "Decision", "MCDC")
        ]
        file_rows.append((f"`{f.path}`", *cells, str(f.counts.get(NOT_COVERED, 0))))

    gap_rows: list[Sequence[str]] = [
        (f"`{f.path}`", scope.name, str(scope.line), str(scope.counts.get(NOT_COVERED, 0)))
        for f in c.files
        if f.counts.get(NOT_COVERED, 0)
        for scope in f.scopes
        if scope.counts.get(NOT_COVERED, 0)
    ]

    violation_rows: list[Sequence[str]] = [
        (
            f"`{v.location}`",
            v.obligation_kind,
            inline(v.message),
            str(classify_violation(v, ev.proof)),
            f"`{v.source_text}`" if v.source_text else "",
        )
        for v in c.non_exempted_violations
    ]

    exemption_blocks: list[str] = []
    for e in c.exemptions:
        lines = [f"**`{e.file}:{e.line}`**", "", f"> {inline(e.justification)}"]
        if e.masked:
            lines.append("")
            lines.append("Masked violations:")
            lines.extend(
                f"- `{v.location}` — {v.obligation_kind} {inline(v.message)}" for v in e.masked
            )
        exemption_blocks.append("\n".join(lines))
    exemptions_body = "\n\n".join(exemption_blocks) if exemption_blocks else "None."

    return f"""{_target("coverage")}

# Coverage

gnatcov measured `{c.level}` coverage of the instrumented test-suite run
recorded under {{ref}}`provenance-invocations`.

{_target("coverage-summary")}

## Summary

{
        _table(
            (
                "Criterion",
                "Total",
                "Covered",
                "Partial",
                "Uncovered",
                "Undetermined",
                "Exempted",
                "Coverage",
            ),
            summary_rows,
        )
    }

{_target("coverage-files")}

## Per-file results

{
        _table_or(
            ("File", "Stmt", "Decision", "MCDC", "Uncovered lines"),
            file_rows,
            "No files were analyzed.",
        )
    }

Scopes containing the uncovered lines:

{_table_or(("File", "Scope", "Line", "Uncovered lines"), gap_rows, "No scope has uncovered lines.")}

{_target("coverage-violations")}

## Violations (non-exempted)

Classification is a per-file heuristic cross-reference against where proved
checks are located (for generics, at their instantiations) — see the review
obligations on the index page for how to read it.

{_table_or(("Location", "Kind", "Message", "Classification", "Source"), violation_rows, "None.")}

{_target("coverage-exemptions")}

## Exempted regions

{exemptions_body}
"""


def _status(row: TraceRow | VerificationRow) -> str:
    """Render a row's status cell, bold when the row is open work."""
    return f"**{inline(row.status)}**" if row.is_open else inline(row.status)


def _diag_detail(d: TraceDiagnostic) -> str:
    """Render a gate diagnostic's code and message as one detail cell."""
    return f"{code_span(d.code)}: {inline(d.message)}"


@dataclass(frozen=True)
class _Links:
    """
    How one matrix's ids become links: the render, and which layer each cell names.

    A matrix's two id-bearing cells belong to different layers -- the node is of
    the matrix's own layer, the detail's refs are of the layer across the pair --
    so both are named here rather than guessed per cell.
    """

    doc: RequirementsDocument | None = None
    node_layer: str | None = None
    ref_layer: str | None = None

    def node(self, node: str) -> str:
        """Render a row's node cell."""
        return _req_link(self.doc, self.node_layer, node) if self.node_layer else code_span(node)

    def detail(self, row: TraceRow) -> str:
        """
        Render a row's detail: its refs as links where they are rendered statements.

        A row's detail is its refs or prose, never both (`reqs` `Row.detail`), so
        prose -- a waiver reason, an em-dash for nothing -- falls through unchanged.
        """
        if not (row.refs and self.ref_layer and self.doc):
            return inline(row.detail)
        return ", ".join(_req_link(self.doc, self.ref_layer, ref) for ref in row.refs)


def _facet_detail(
    facet: MethodFacet, doc: RequirementsDocument | None, layers: dict[str, str], *, link: bool
) -> str:
    """
    Render one method facet exactly as `reqs` does, optionally linking its evidence.

    Mirrors `reqs` `MethodEvidence.detail`; with `link` false it reproduces that
    text verbatim, which is what lets `_verification_detail` check itself.
    """
    if facet.status == "UNSELECTED":
        return f"{facet.method}: (layer not selected)"
    layer = layers.get(facet.method)
    ids = [_req_link(doc, layer, e) if link and layer is not None else e for e in facet.evidence]
    joined = ", ".join(ids)
    if facet.status == "MISMATCH":
        return f"{facet.method}: {joined} (not declared)"
    return f"{facet.method}: {joined or '—'}"


def _verification_detail(
    row: VerificationRow, doc: RequirementsDocument | None, layers: dict[str, str]
) -> str:
    """
    Render a verification row's evidence cell, linking the ids that are rendered.

    The cell is rebuilt from the row's own facets and used only when it
    reproduces what `reqs` rendered into `detail`: a mismatch means this consumer
    has misread the row -- a waiver reason standing in for the facets, say -- and
    the producer's rendering is the one to trust.
    """
    if not row.methods:
        return inline(row.detail)
    plain = "; ".join(_facet_detail(f, doc, layers, link=False) for f in row.methods)
    if plain != row.detail:
        return inline(row.detail)
    return "; ".join(_facet_detail(f, doc, layers, link=True) for f in row.methods)


def _method_layers(r: TraceReport) -> dict[str, str]:
    """Map each verification method to the layer of the chain that evidences it."""
    return {layer.method: layer.name for layer in r.layers if layer.method is not None}


def _trace_matrix(
    rows: Sequence[TraceRow],
    id_header: str,
    detail_header: str,
    links: _Links | None = None,
) -> str:
    """Render one trace matrix as a table, linking the ids it can."""
    link = links or _Links()
    return _table_or(
        (id_header, "Status", detail_header),
        [(link.node(r.node), _status(r), link.detail(r)) for r in rows],
        "No nodes.",
    )


def _open_detail(
    item: OpenTraceItem, doc: RequirementsDocument | None, layers: dict[str, str]
) -> str:
    """Render an open row's detail with the same links its full matrix carries."""
    if isinstance(item.row, TraceRow):
        return _Links(doc, item.layer, item.ref_layer).detail(item.row)
    return _verification_detail(item.row, doc, layers)


def _pair_sections(pair: TracePair, doc: RequirementsDocument | None = None) -> list[str]:
    """Render one (parent, child) pair's matrices, mirroring the `make trace` tables."""
    up, lo = pair.upper, pair.lower
    out: list[str] = []
    if pair.refs_point_down:
        field = pair.ref_field or "down refs"
        # Mirror the CLI tables' labels (reqs `_REF_FIELD_LABELS`).
        title, header = (
            ("implementation", "Implemented by") if field == "implemented_by" else (field, field)
        )
        out.append(
            f"### {up} → {lo} ({title})\n\n"
            + _trace_matrix(pair.upper_rows, up, f"{header} ({lo})", _Links(doc, up, lo))
        )
        out.append(
            f"### {lo} → {up} (required by)\n\n"
            + _trace_matrix(pair.lower_rows, lo, f"Required by ({up})", _Links(doc, lo, up))
        )
        return out
    if pair.method is None:
        out.append(
            f"### {up} → {lo} (coverage)\n\n"
            + _trace_matrix(pair.upper_rows, up, f"Covered by ({lo})", _Links(doc, up, lo))
        )
    else:
        out.append(
            f"### {up} → {lo}\n\nA `{pair.method}` evidence layer: the {up} side "
            f"of this pair is in the verification matrix above."
        )
    out.append(
        f"### {lo} → {up} (upward trace)\n\n"
        + _trace_matrix(pair.lower_rows, lo, f"Traces to ({up})", _Links(doc, lo, up))
    )
    return out


def _emit_trace_report(r: TraceReport | None, doc: RequirementsDocument | None = None) -> str:
    """Render the machine-checked portion of the traceability page."""
    regenerate = "Regenerate with `make trace-report`."
    if r is None:
        missing = f"**Warning:** no trace report was collected. {regenerate}"
        return f"""{missing}

{_target("traceability-gaps")}

## Open items

Unknown — there is no trace report to enumerate them from.

{_target("traceability-verification")}

## Verification matrix

Unknown — there is no trace report to enumerate it from.

{_target("traceability-matrices")}

## Chain matrices

Unknown — there is no trace report to enumerate them from.

{_target("traceability-diagnostics")}

## Gate diagnostics

Unknown — there is no trace report to enumerate them from.
"""

    layer_rows: list[Sequence[str]] = []
    for layer in r.layers:
        notes = [
            note
            for note, applies in (
                (f"verifies `{layer.method}`", layer.method is not None),
                # The count is the traced population, not the testsuite: a
                # routine tagged `--@covers none` verifies code no requirement
                # governs and is no node here.
                ("requirements-based routines only", layer.kind == "ada-tests"),
                ("partial coverage by design", layer.partial_coverage),
                (f"cited by the parent's `{layer.ref_field}`", layer.refs_point_down),
            )
            if applies
        ]
        layer_rows.append(
            (
                layer.name,
                f"`{layer.kind}`",
                str(layer.node_count) if layer.node_count is not None else "—",
                "; ".join(notes),
            )
        )

    diag_rows: list[Sequence[str]] = [
        (inline(d.level), code_span(d.code), code_span(d.location), inline(d.message))
        for d in r.diagnostics
    ]
    diag_block = _table_or(("Level", "Code", "Location", "Message"), diag_rows, "None.")

    if not r.corpus_valid:
        broken = (
            "**Warning:** `reqs trace` could not analyze the chain (broken chain "
            "config or requirement corpus); the matrices below are omitted rather "
            f"than fabricated. Fix the gate diagnostics, then regenerate. {regenerate}"
        )
        return f"""{broken}

{_target("traceability-gaps")}

## Open items

Unknown — the corpus is invalid; see the gate diagnostics below.

{_target("traceability-verification")}

## Verification matrix

Unknown — the corpus is invalid; see the gate diagnostics below.

{_target("traceability-matrices")}

## Chain matrices

Omitted — the corpus is invalid; see the gate diagnostics below.

{_target("traceability-diagnostics")}

## Gate diagnostics

{diag_block}
"""

    verdict = (
        f"`reqs trace{' --complete' if r.complete else ''}` reported "
        f"**{count(r.errors, 'error')}** and {count(r.warnings, 'warning')} over this chain"
        + (f" (run: {inline(r.generated_at)})" if r.generated_at else "")
        + "; the exact invocation is under {ref}`provenance-invocations`."
    )

    open_items = open_trace_items(r)
    rowless = rowless_trace_findings(r)
    methods = _method_layers(r)
    open_rows: list[Sequence[str]] = [
        (
            item.where,
            _req_link(doc, item.layer, item.row.node),
            _status(item.row),
            _open_detail(item, doc, methods),
        )
        for item in open_items
    ]
    # Gate findings with no matrix row (waiver lint, ignored check tags) are
    # open items all the same: absence of a row must not read as done.
    open_rows.extend(
        ("gate finding", code_span(d.location), f"**{inline(d.level)}**", _diag_detail(d))
        for d in rowless
    )
    if open_rows:
        open_block = _table(("Where", "Node", "Status", "Detail"), open_rows)
    elif r.errors or r.warnings:
        # Should be unreachable (a counted finding is a row or is rowless),
        # but a drifted producer must still not read as all-clear.
        open_block = (
            f"No open matrix rows, but the gate reported {count(r.errors, 'error')} and "
            f"{count(r.warnings, 'warning')} — see the gate diagnostics below."
        )
    else:
        open_block = (
            "None — every requirement of the chain is covered, traced, and verified as declared."
        )

    verification_blocks: list[str] = [
        f"### {matrix.layer}\n\n"
        + _table_or(
            (matrix.layer, "Status", "Evidence"),
            [
                (
                    _req_link(doc, matrix.layer, row.node),
                    _status(row),
                    _verification_detail(row, doc, methods),
                )
                for row in matrix.rows
            ],
            "No statements.",
        )
        for matrix in r.verification
    ]
    verification_body = (
        "\n\n".join(verification_blocks)
        if verification_blocks
        else "No evidence layer of the chain declares a verification method."
    )

    pair_blocks = [section for pair in r.pairs for section in _pair_sections(pair, doc)]
    pairs_body = "\n\n".join(pair_blocks) if pair_blocks else "The chain has no pairs."

    return f"""{verdict}

{_target("traceability-chain")}

## The chain

{_table(("Layer", "Kind", "Nodes", "Notes"), layer_rows)}

{_target("traceability-gaps")}

## Open items

Matrix rows whose status is neither satisfied nor accounted-for — requirements
without their declared evidence, dangling or untraced references, statements
declaring no verification method — plus gate findings with no matrix row
(waiver lint, ignored check tags). **Bold** statuses mark the open rows in
the full matrices below.

{open_block}

{_target("traceability-verification")}

## Verification matrix

One row per statement, its declared verification methods' evidence side by
side. `REVIEW` rows rest on a recorded human argument — they are review
obligations on the index page, not gaps. `UNSELECTED` marks a declared method
no layer of the traced chain verifies: unchecked, so open.

{verification_body}

{_target("traceability-matrices")}

## Chain matrices

Per-pair coverage and upward traces, as `make trace` prints them. Statuses:
`OK` covered/resolved; `WAIVED` excused with a recorded reason; `DERIVED` no
parent by design; `UNTESTED`/`UNIMPLEMENTED`/`NO REQUIREMENT` expected under a
partial-coverage layer; anything **bold** is an open item listed above.

{pairs_body}

{_target("traceability-diagnostics")}

## Gate diagnostics

Verbatim findings of the `reqs trace` gate (`make trace-check` fails on
errors; `make report` does not, so gaps stay visible here):

{diag_block}
"""


def _emit_traceability(ev: Evidence) -> str:
    """Render the requirements-chain page: matrices, gaps, and judgement items."""
    t = ev.traceability
    signed = {s.item: s for s in t.signoffs}

    def stamp(item: str, digest: str | None) -> str:
        """Render the sign-off cell for one item: who signed the text as it now stands."""
        entry = signed.get(item)
        if entry is None:
            return "**not signed off**"
        if entry.digest != digest:
            return f"**lapsed** (was {inline(entry.by)}, {inline(entry.date)})"
        return f"{inline(entry.by)}, {inline(entry.date)}"

    waiver_rows: list[Sequence[str]] = [
        (
            f"§{inline(w.leaf)}",
            inline(w.reason),
            stamp(waiver_item(w.leaf), digest_of(waiver_subject(w))),
        )
        for w in t.waivers
    ]
    derived_rows: list[Sequence[str]] = [
        (
            _req_link(ev.requirements, "HLR", d.ident),
            inline(d.text),
            stamp(derived_item(d.ident), digest_of(derived_subject(d))),
        )
        for d in t.derived
    ]
    conops_block = (
        f"The CONOPS as it stands is signed off: {stamp(CONOPS_ITEM, t.conops_digest)}."
        if t.conops_digest is not None
        else "**`requirements/conops.md` was not found — its review state is unknown.**"
    )
    absent = [
        note
        for note, is_absent in (
            (
                "`requirements/trace_waivers.yaml` was not found — waiver status is unknown.",
                not t.waivers_found,
            ),
            (
                "`requirements/hlr/` was not found — derived-requirement status is unknown.",
                not t.hlr_found,
            ),
        )
        if is_absent
    ]
    missing = "".join(f"\n\n**{note}**" for note in absent) + ("\n" if absent else "")

    return f"""{_target("traceability")}

# Traceability

The requirement chain (CONOPS → HLR → LLR, with test, code, proof, and
static-check evidence hanging off the LLRs) is checked mechanically by
`reqs trace`; this page renders its report. `make report` gates only on the
corpus being parseable (`validate-reqs-corpus`): the chain's own gates are
`make validate-reqs` (CONOPS → HLR → LLR) and `make trace-check` (down to the
code and evidence), and neither gates this report — their findings stay
visible as the open items below.
{missing}
{_emit_trace_report(t.report, ev.requirements)}

{_target("traceability-waivers")}

## Waived CONOPS leaves

CONOPS leaves deliberately not realized by any HLR, each with its recorded
reason and the review recorded against that reason:

{_table_or(("Leaf", "Reason", "Signed off"), waiver_rows, "None.")}

{_target("traceability-derived")}

## Derived requirements

HLR statements with no CONOPS parent, standing on their rationale alone, with
the review recorded against each:

{_table_or(("Requirement", "Text", "Signed off"), derived_rows, "None.")}

{_target("traceability-conops")}

## CONOPS validity

The CONOPS (`requirements/conops.md`) is the root of the chain: every HLR is
checked against it, but nothing checks the CONOPS itself. Its validity — that
it describes the intersection the stakeholders actually want — is established
only by human review.

{conops_block}

Sign-offs on this page and the two above are read from
`requirements/signoffs.yaml`, where each entry names the reviewer and fixes
what they read by digest: edit that text and the sign-off lapses, re-opening
its review obligation. They are a record of a human's reading, not something a
tool enforces — anything able to write the repository can write that file, so
what they buy is that a change to them is conspicuous in a diff.
"""


def _requirements(ev: Evidence) -> RequirementsDocument:
    """Return the collected render; the requirement pages are emitted only from one."""
    if ev.requirements is None:  # pragma: no cover - emitted only when a render was collected
        msg = "no rendered requirement document to emit"
        raise ValueError(msg)
    return ev.requirements


def _layer_page(layer: RequirementLayer) -> str:
    """Return the report page one rendered layer's containers are entered from."""
    return layer.name.lower()


def _emit_requirements(ev: Evidence) -> str:
    """Render the requirements landing page: the corpus entered one layer at a time."""
    layers = "\n".join(_layer_page(layer) for layer in _requirements(ev).layers)
    return f"""{_target("requirements")}

# Requirements

```{{toctree}}
:maxdepth: 2

{layers}
```
"""


def _emit_layer(layer: RequirementLayer) -> str:
    """Render one layer's page: its heading, then a toctree of its top pages."""
    roots = "\n".join(f"{REQUIREMENTS_SUBDIR}/{page}" for page in layer.roots)
    return f"""# {layer.heading}

```{{toctree}}
:maxdepth: 2

{roots}
```
"""


def _emit_source_listings(ev: Evidence) -> str:
    """Render the source-listing section: one page per file the requirements cite."""
    doc = _requirements(ev)
    # An entry titled by its path with the `src/` directories dropped: the nav
    # shows the entry's title, and which source root a file sits under says
    # nothing about the file. The listing itself is titled by the real path.
    entries = "\n".join(
        f"{_listing_title(source.path)} <{REQUIREMENTS_SUBDIR}/{source.page}>"
        for source in doc.sources
    )
    return f"""{_target("source-listings")}

# Source listings

The requirements cite {count(len(doc.sources), "file")}. Each is listed whole
with an anchor on every cited line, so a requirement's evidence -- an entity, a
contract, a test routine -- links to the line that carries it. The listings are
a navigation aid rather than part of the argument, so the source itself is
carried in the HTML rendering alone; the anchors are in both, because a link
that resolves in one rendering and dangles in the other is a broken document.

```{{toctree}}
:maxdepth: 1

{entries}
```
"""


def _listing_title(path: str) -> str:
    """Return the nav title of one listing: its path, minus the source roots in it."""
    return "/".join(part for part in path.split("/") if part != "src")


def emit_pages(ev: Evidence, obligations: list[Obligation]) -> dict[str, str]:
    """Render all report pages, keyed by output filename."""
    pages = {
        "index.md": _emit_index(ev, obligations),
        "provenance.md": _emit_provenance(ev),
        "proof.md": _emit_proof(ev),
        "coverage.md": _emit_coverage(ev),
        "traceability.md": _emit_traceability(ev),
    }
    if ev.requirements is None:
        return pages
    pages["requirements.md"] = _emit_requirements(ev)
    for layer in ev.requirements.layers:
        name = f"{_layer_page(layer)}.md"
        # A layer named after one of the report's own pages would replace it
        # here, silently: the chain names its layers, so this is checked rather
        # than assumed.
        if name in pages:
            msg = f"chain layer {layer.name!r} collides with the report page {name!r}"
            raise ValueError(msg)
        pages[name] = _emit_layer(layer)
    if ev.requirements.sources:
        pages["source-listings.md"] = _emit_source_listings(ev)
    return pages
