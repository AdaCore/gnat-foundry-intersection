"""Tests for the MyST emitters and the strict Sphinx build."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from vreport.build import build_html, build_pdf, write_sphinx_sources
from vreport.emit import emit_pages
from vreport.model import (
    CoverageViolation,
    DerivedRequirement,
    Sloc,
    TraceabilityEvidence,
    TraceDiagnostic,
    TracePair,
    TraceReport,
    TraceRow,
    Waiver,
)
from vreport.obligations import build_obligations

if TYPE_CHECKING:
    from pathlib import Path

    from vreport.model import Evidence

_TARGET_RE = re.compile(r"^\(([\w-]+)\)=$", re.MULTILINE)
_REF_RE = re.compile(r"\{ref\}`([\w-]+)`")


def _targets_and_refs(pages: dict[str, str]) -> tuple[set[str], set[str]]:
    text = "\n".join(pages.values())
    return set(_TARGET_RE.findall(text)), set(_REF_RE.findall(text))


def test_every_reference_resolves(evidence: Evidence) -> None:
    """No page references a target that no page defines."""
    pages = emit_pages(evidence, build_obligations(evidence))
    targets, refs = _targets_and_refs(pages)
    assert refs <= targets, refs - targets


def test_every_obligation_links_to_evidence(evidence: Evidence) -> None:
    """Each obligation's anchor exists on some evidence page."""
    obligations = build_obligations(evidence)
    pages = emit_pages(evidence, obligations)
    targets, _ = _targets_and_refs(pages)
    missing = {o.anchor for o in obligations} - targets
    assert not missing, missing


def test_table_cells_are_escaped(evidence: Evidence) -> None:
    """Pipes in tool messages cannot break the Markdown tables."""
    hostile = CoverageViolation(
        location=Sloc(file="src/x.adb", line=3),
        sco="SCO #9: STATEMENT",
        obligation_kind="STATEMENT",
        message="pipe | in message",
        exempted=False,
    )
    ev = evidence.model_copy(
        update={
            "coverage": evidence.coverage.model_copy(
                update={"violations": [*evidence.coverage.violations, hostile]}
            )
        }
    )
    pages = emit_pages(ev, build_obligations(ev))
    assert "pipe \\| in message" in pages["coverage.md"]
    assert "pipe | in message" not in pages["coverage.md"]


# Fence breakout, a fabricated green obligation, and a bogus cross-reference.
_HOSTILE = (
    "reason\n\n:::\n\n:::{admonition} R-99 (OK) — Fake all-clear\n:class: tip\n\n"
    "All good.\n\n:::\n\nsee {ref}`bogus-target` and `unclosed span"
)


def test_hostile_evidence_text_cannot_inject_myst(evidence: Evidence, tmp_path: Path) -> None:
    """Evidence-carried text is data: no fence breakout, no roles, no broken refs."""
    hostile = TraceabilityEvidence(
        waivers=[Waiver(leaf="1.1", reason=_HOSTILE)],
        derived=[DerivedRequirement(ident="hlr_x.1", text=_HOSTILE)],
        waivers_found=True,
        hlr_found=True,
    )
    ev = evidence.model_copy(update={"traceability": hostile})
    obligations = build_obligations(ev)
    pages = emit_pages(ev, obligations)

    # A fence breakout would add colon-fence lines beyond the obligations' own.
    fence_lines = [line for line in pages["index.md"].splitlines() if line.startswith(":::")]
    assert len(fence_lines) == 2 * len(obligations)
    assert not any("Fake all-clear" in line for line in fence_lines)

    # The planted role must be escaped everywhere.
    everything = "\n".join(pages.values())
    assert not re.search(r"(?<!\\)\{ref\}`bogus-target`", everything)

    # The real oracle: the strict build still passes.
    write_sphinx_sources(pages, tmp_path / "src", ev.title)
    assert build_html(tmp_path / "src", tmp_path / "html") == 0


def test_provenance_records_gnatcov_command(evidence: Evidence) -> None:
    """The recorded gnatcov invocation appears on the provenance page."""
    pages = emit_pages(evidence, build_obligations(evidence))
    assert "gnatcov coverage --level=stmt+mcdc" in pages["provenance.md"]


def test_provenance_records_reqs_trace_command(evidence: Evidence) -> None:
    """The recorded `reqs trace` invocation appears on the provenance page."""
    pages = emit_pages(evidence, build_obligations(evidence))
    assert "reqs trace --chain requirements/trace_chain.yaml" in pages["provenance.md"]


def test_traceability_page_puts_open_items_first(evidence: Evidence) -> None:
    """The open items lead the page: the red rows plus the rowless gate findings."""
    page = emit_pages(evidence, build_obligations(evidence))["traceability.md"]
    open_start = page.index("## Open items")
    assert open_start < page.index("## Verification matrix") < page.index("## Chain matrices")
    section = page[open_start : page.index("## Verification matrix")]
    for node in ("`3.1`", "`hlr_x.3`", "`llr_x.3`"):
        assert node in section, node
    assert "**UNCOVERED**" in section
    assert "**DANGLING**" in section
    # The waiver-lint warning has no matrix row, yet it is an open item too.
    assert "W-TRACE-WAIVER-REDUNDANT" in section
    assert "`1.1`" not in section  # waived: accounted-for, not open


def test_traceability_page_renders_matrices_and_method_note(evidence: Evidence) -> None:
    """Pair matrices mirror the CLI tables; method pairs defer to the verification view."""
    page = emit_pages(evidence, build_obligations(evidence))["traceability.md"]
    assert "### CONOPS → HLR (coverage)" in page
    assert "### HLR → CONOPS (upward trace)" in page
    assert "### LLR → CODE (implementation)" in page
    assert "### CODE → LLR (required by)" in page
    assert "verification matrix above" in page  # the LLR → TEST pair
    assert "review: Argued against MUTCD §4E.01." in page
    assert "W-TRACE-WAIVER-REDUNDANT" in page  # the gate diagnostics table


def test_index_glance_counts_trace_open_items(evidence: Evidence) -> None:
    """The front page counts the open rows plus the rowless gate findings."""
    index = emit_pages(evidence, build_obligations(evidence))["index.md"]
    assert "4 open items (3 gate errors, 1 warning)" in index


def test_rowless_gate_findings_do_not_read_as_all_clear(evidence: Evidence) -> None:
    """Gate errors with no matrix row (waiver lint, ignored tags) never render green."""
    report = TraceReport(
        complete=True,
        corpus_valid=True,
        errors=1,
        diagnostics=[
            TraceDiagnostic(
                level="error",
                code="E-TRACE-CHECK-IGNORED",
                message="tagged check matches no anchors",
                file="src/x.ads",
            )
        ],
    )
    ev = evidence.model_copy(
        update={"traceability": evidence.traceability.model_copy(update={"report": report})}
    )
    page = emit_pages(ev, build_obligations(ev))["traceability.md"]
    assert "None — every requirement" not in page
    section = page[page.index("## Open items") : page.index("## Verification matrix")]
    assert "gate finding" in section
    assert "E-TRACE-CHECK-IGNORED" in section


def test_traceability_page_names_the_report_gate_honestly(evidence: Evidence) -> None:
    """The page must not claim a gate `make report` does not run (only the corpus check)."""
    page = emit_pages(evidence, build_obligations(evidence))["traceability.md"]
    assert "`validate-reqs-corpus`" in page
    assert "gated by `make validate-reqs`" not in page
    assert "prerequisite of `make report`" not in page


def test_missing_trace_report_warns_and_builds(evidence: Evidence, tmp_path: Path) -> None:
    """Without a trace report every claim renders as unknown, never green."""
    ev = evidence.model_copy(
        update={"traceability": evidence.traceability.model_copy(update={"report": None})}
    )
    obligations = build_obligations(ev)
    pages = emit_pages(ev, obligations)
    assert "no trace report was collected" in pages["traceability.md"]
    assert "no trace report" in pages["index.md"]
    write_sphinx_sources(pages, tmp_path / "src", ev.title)
    assert build_html(tmp_path / "src", tmp_path / "html") == 0


def test_invalid_corpus_shows_diagnostics_and_builds(evidence: Evidence, tmp_path: Path) -> None:
    """An unanalyzable corpus renders its diagnostics instead of fabricated matrices."""
    report = TraceReport(
        corpus_valid=False,
        errors=1,
        diagnostics=[
            TraceDiagnostic(level="error", code="E-YAML", message="parse error", file="x.yaml")
        ],
    )
    ev = evidence.model_copy(
        update={"traceability": evidence.traceability.model_copy(update={"report": report})}
    )
    obligations = build_obligations(ev)
    pages = emit_pages(ev, obligations)
    assert "could not analyze the chain" in pages["traceability.md"]
    assert "E-YAML" in pages["traceability.md"]
    write_sphinx_sources(pages, tmp_path / "src", ev.title)
    assert build_html(tmp_path / "src", tmp_path / "html") == 0


def test_hostile_trace_report_text_cannot_inject_myst(evidence: Evidence, tmp_path: Path) -> None:
    """Trace-report-carried text (details, messages, command) is data, not markup."""
    fence_breakout = "x\n```\n:::{admonition} R-99 (OK) — Fake all-clear\n:class: tip\n:::"
    report = TraceReport(
        complete=True,
        corpus_valid=True,
        errors=1,
        command=fence_breakout,
        pairs=[
            TracePair(
                upper="A",
                lower="B",
                upper_rows=[
                    TraceRow(node="a.1", status="UNCOVERED", detail=_HOSTILE),
                    # A backtick in a node cannot end its code span; a status is
                    # escaped like any other free text (unknown, so bold-open).
                    TraceRow(node="a`2", status="BREAK`OUT{", detail="—"),
                ],
            )
        ],
        diagnostics=[TraceDiagnostic(level="error", code="E-X", message=_HOSTILE, file="x.yaml")],
    )
    ev = evidence.model_copy(
        update={"traceability": evidence.traceability.model_copy(update={"report": report})}
    )
    pages = emit_pages(ev, build_obligations(ev))
    everything = "\n".join(pages.values())
    assert not re.search(r"(?<!\\)\{ref\}`bogus-target`", everything)
    assert "``a`2``" in pages["traceability.md"]
    assert "**BREAK\\`OUT\\{**" in pages["traceability.md"]
    # The recorded command's ``` runs stay inside the (longer) provenance fence.
    assert "````text\n" + fence_breakout in pages["provenance.md"]
    write_sphinx_sources(pages, tmp_path / "src", ev.title)
    assert build_html(tmp_path / "src", tmp_path / "html") == 0


def test_proof_page_flags_incomplete_analysis(evidence: Evidence) -> None:
    """The early-stopped fixture unit shows up in the completeness table."""
    pages = emit_pages(evidence, build_obligations(evidence))
    assert "Analysis completeness" in pages["proof.md"]
    assert "STOP_REASON_CHECK_MODE" in pages["proof.md"]


def test_proof_page_lists_the_analyzed_scope(evidence: Evidence) -> None:
    """
    The scope table is the run's unit list — every unit, and nothing else.

    A "none" elsewhere on the page means "none among these", so a table that
    silently dropped or invented a unit would misstate what the page covers.
    Which units *should* be in a run is the project's declaration, not this
    generator's business: the fixture models a wide run on purpose.
    """
    page = emit_pages(evidence, build_obligations(evidence))["proof.md"]
    section = page.split("## Analysis scope", 1)[1].split("(proof-completeness)=", 1)[0]
    rows = [ln.split("|")[1].strip() for ln in section.splitlines() if ln.startswith("| ")]
    assert rows == ["Unit", *evidence.proof.units]
    assert "| state_machine_loop | generic, through state_machine_loop_proof |" in section
    assert "| main | " in section


def test_proof_page_credits_a_nested_generic_to_its_instance(evidence: Evidence) -> None:
    """
    A unit hosting a nested generic must not read as a bare zero.

    `buses` records no check of its own — its two bus generics are analyzed
    through the instance in `buses_proof` — and that cell is the only place the
    page can say so, since the generics table sees whole generic units only.
    """
    page = emit_pages(evidence, build_obligations(evidence))["proof.md"]
    assert "| buses | 0 checks; instances analyzed through buses_proof |" in page


def test_boundary_obligation_is_bounded_by_the_scope(evidence: Evidence) -> None:
    """A clean boundary must not read as "no unproved code exists anywhere"."""
    ob = {o.anchor: o for o in build_obligations(evidence)}["proof-spark-modes"]
    assert "{ref}`proof-scope`" in ob.detail


def test_proof_page_names_each_generic_instance(evidence: Evidence) -> None:
    """The generics table says which unit stands behind each generic."""
    page = emit_pages(evidence, build_obligations(evidence))["proof.md"]
    assert "## Generic units" in page
    assert "| state_machine_loop | state_machine_loop_proof |" in page
    assert "STOP_REASON_GENERIC_UNIT" not in page


def test_provenance_strips_local_tool_paths(evidence: Evidence) -> None:
    """Prover version lines show tool basenames, not this machine's layout."""
    pages = emit_pages(evidence, build_obligations(evidence))
    assert "Alt-Ergo version" in pages["provenance.md"]
    assert "install/alire/prefix" not in pages["provenance.md"]


def test_sphinx_build_is_strict_and_green(evidence: Evidence, tmp_path: Path) -> None:
    """The generated sources build under -W -n (the report's own oracle)."""
    pages = emit_pages(evidence, build_obligations(evidence))
    write_sphinx_sources(pages, tmp_path / "src", evidence.title)
    assert (tmp_path / "src" / "conf.py").exists()
    rc = build_html(tmp_path / "src", tmp_path / "html")
    assert rc == 0
    assert (tmp_path / "html" / "index.html").exists()


def test_pdf_build_produces_a_pdf(evidence: Evidence, tmp_path: Path) -> None:
    """The same sources render to PDF via the rst2pdf builder."""
    pages = emit_pages(evidence, build_obligations(evidence))
    write_sphinx_sources(pages, tmp_path / "src", evidence.title)
    rc = build_pdf(tmp_path / "src", tmp_path / "pdf")
    assert rc == 0
    out = tmp_path / "pdf" / "verification-report.pdf"
    assert out.exists()
    assert out.read_bytes().startswith(b"%PDF")
