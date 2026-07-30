"""
Render the evidence and review obligations as MyST Markdown pages.

Every claim on the index page cross-references (`{ref}`) an explicit target
(`(name)=`) on an evidence page; the Sphinx build runs with `-W -n`, so a
reference to a missing target fails the build.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from vreport.model import (
    EXEMPTED,
    EXEMPTED_NO_VIOLATION,
    FULLY_COVERED,
    NOT_COVERED,
    PARTIALLY_COVERED,
    TOTAL_LINES,
    UNDETERMINED,
    CheckStatus,
    ObligationStatus,
)
from vreport.obligations import (
    classify_violation,
    open_claims,
    predicate_label,
    toolchain_note,
)

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence

    from vreport.model import Evidence, Obligation

_PAGE_ORDER = ("provenance", "proof", "coverage", "traceability")


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
    """Render a fenced code block."""
    return f"```{lang}\n{text}\n```"


def _admonition(title: str, body: str, *, kind: str) -> str:
    """Render a MyST admonition (colon fence)."""
    return f":::{{admonition}} {title}\n:class: {kind}\n\n{body}\n:::"


def _obligation_admonition(ob: Obligation) -> str:
    """Render one review obligation as an admonition with its evidence link."""
    parts = [ob.detail]
    if ob.items:
        parts.append("\n".join(f"- {item}" for item in ob.items))
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
        ("Review obligations", f"{len(review)} need review, {ok} machine-checked OK"),
        ("Sources", git_row),
    ]

    toctree = "```{toctree}\n:hidden:\n\n" + "\n".join(_PAGE_ORDER) + "\n```"
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

    return f"""{_target("provenance")}

# Provenance

{_target("provenance-git")}

## Sources

{git_block}

{_target("provenance-tools")}

## Tools

{toolchain_note(ev.proof.version_text, ev.coverage.version_text)}
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

gnatcov analyzed at level `{ev.coverage.level}` from these test executions:

{_table_or(("Program", "Date", "Trace"), trace_rows, "No trace information was recorded.")}
"""


def _emit_proof(ev: Evidence) -> str:
    """Render the gnatprove evidence page."""
    p = ev.proof

    unproved_rows: list[Sequence[str]] = [
        (f"`{c.location}`", c.rule, c.entity or "", c.message or "") for c in p.unproved_checks
    ]
    justified_rows: list[Sequence[str]] = [
        (f"`{c.location}`", c.rule, c.entity or "", c.justification or "")
        for c in p.justified_checks
    ]
    assume_rows: list[Sequence[str]] = [(f"`{a.location}`", a.entity or a.unit) for a in p.assumes]
    skip_rows: list[Sequence[str]] = [(s.entity, s.kind, s.unit) for s in p.skips]
    warning_rows: list[Sequence[str]] = [
        (
            f"`{w.location}`" if w.location else "—",
            w.rule,
            w.message,
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

    return f"""{_target("proof")}

# Proof

gnatprove analyzed {len(p.units)} units toward the project's Silver target
(absence of run-time errors); the contracts written in the code are proved by
the same analysis (see the summary table). {run_note}

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
a human decision that the condition is benign):

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
            v.message,
            str(classify_violation(v, ev.proof)),
            f"`{v.source_text}`" if v.source_text else "",
        )
        for v in c.non_exempted_violations
    ]

    exemption_blocks: list[str] = []
    for e in c.exemptions:
        lines = [f"**`{e.file}:{e.line}`**", "", f"> {_esc(e.justification)}"]
        if e.masked:
            lines.append("")
            lines.append("Masked violations:")
            lines.extend(f"- `{v.location}` — {v.obligation_kind} {v.message}" for v in e.masked)
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


def _emit_traceability(ev: Evidence) -> str:
    """Render the (currently partial) requirements-chain page."""
    t = ev.traceability
    waiver_rows: list[Sequence[str]] = [(f"§{w.leaf}", w.reason) for w in t.waivers]
    derived_rows: list[Sequence[str]] = [(f"`{d.ident}`", d.text) for d in t.derived]
    missing = (
        "" if t.sources_found else "\n\nNo requirements tree was found under the project root.\n"
    )

    status = _admonition(
        "Partial",
        "This page currently shows the human-judgement items of the requirements "
        "chain (waivers and derived requirements). The CONOPS → HLR → LLR chain "
        "itself is mechanically validated by `make validate-reqs`; requirement → "
        "code → test matrices are planned work (plan phase 4) and are **not** yet "
        "part of this report.",
        kind="warning",
    )

    return f"""{_target("traceability")}

# Traceability

{status}{missing}

{_target("traceability-waivers")}

## Waived CONOPS leaves

CONOPS leaves deliberately not realized by any HLR, each with its recorded
reason:

{_table_or(("Leaf", "Reason"), waiver_rows, "None.")}

{_target("traceability-derived")}

## Derived requirements

HLR statements with no CONOPS parent, standing on their rationale alone:

{_table_or(("Requirement", "Text"), derived_rows, "None.")}

{_target("traceability-conops")}

## CONOPS validity

The CONOPS (`requirements/conops.md`) is the root of the chain: every HLR is
checked against it, but nothing checks the CONOPS itself. Its validity — that
it describes the intersection the stakeholders actually want — is established
only by human review.
"""


def emit_pages(ev: Evidence, obligations: list[Obligation]) -> dict[str, str]:
    """Render all report pages, keyed by output filename."""
    return {
        "index.md": _emit_index(ev, obligations),
        "provenance.md": _emit_provenance(ev),
        "proof.md": _emit_proof(ev),
        "coverage.md": _emit_coverage(ev),
        "traceability.md": _emit_traceability(ev),
    }
