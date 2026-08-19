"""Tests for the MyST emitters and the strict Sphinx build."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from vreport.build import (
    PDF_NAME,
    build_html,
    build_pdf,
    copy_requirement_pages,
    write_sphinx_sources,
)
from vreport.emit import REQUIREMENTS_SUBDIR, emit_pages
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


# --- the requirements rendered as a document ---------------------------------


def test_matrix_ids_link_to_the_requirement_text(evidence_with_requirements: Evidence) -> None:
    """A matrix's node and its refs both link to the statements they name."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    traceability = pages["traceability.md"]

    assert "[`hlr_x.1`](#hlr-x-1)" in traceability  # the node cell
    assert "[`llr_x.1`](#llr-x-1)" in traceability  # a detail cell's ref


def test_ids_of_unrendered_layers_stay_plain(evidence_with_requirements: Evidence) -> None:
    """A test routine has no rendered statement, so it carries no link."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    traceability = pages["traceability.md"]

    assert "`u.Test_A`" in traceability
    assert "[`u.Test_A`]" not in traceability


def test_conops_leaves_link_to_the_rendered_document(evidence_with_requirements: Evidence) -> None:
    """A markdown layer's leaf ids link under the anchors its render qualified them with."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))

    assert "[`3.1`](#conops-3-1)" in pages["traceability.md"]


def test_open_items_and_verification_rows_link_too(evidence_with_requirements: Evidence) -> None:
    """The tables a reviewer reads first carry the same links as the full matrices."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    traceability = pages["traceability.md"]
    open_items = traceability.split("## Open items")[1].split("## Verification matrix")[0]
    verification = traceability.split("## Verification matrix")[1].split("## Chain matrices")[0]

    assert "[`llr_x.3`](#llr-x-3)" in open_items
    assert "[`llr_x.1`](#llr-x-1)" in verification


def test_the_requirements_page_names_every_rendered_container(
    evidence_with_requirements: Evidence,
) -> None:
    """The section page enters one page per layer, and each of those its containers."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    requirements = pages["requirements.md"]

    assert "102 statements" not in requirements  # counts come from the render, not hardcoded
    assert "4 leaf statements (CONOPS)" in requirements  # named as its kind, not as containers
    assert "3 statements in 2 containers (HLR)" in requirements
    assert "\nconops\nhlr\nllr\n" in requirements
    assert f"{REQUIREMENTS_SUBDIR}/hlr_x" in pages["hlr.md"]
    assert f"{REQUIREMENTS_SUBDIR}/llr_x" in pages["llr.md"]
    assert "requirements" in pages["index.md"]


def test_a_layer_page_enters_its_top_containers_only(
    evidence_with_requirements: Evidence,
) -> None:
    """A nested container is entered from its parent's page, so not from the layer's."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))

    assert f"{REQUIREMENTS_SUBDIR}/hlr_x_1_nested" not in pages["hlr.md"]
    assert "3 statements in 2 containers" in pages["hlr.md"]
    assert "4 leaf statements, in the document below" in pages["conops.md"]


def test_without_a_render_the_report_omits_the_section(evidence: Evidence) -> None:
    """The section and its links appear only when a render was collected."""
    pages = emit_pages(evidence, build_obligations(evidence))

    assert "requirements.md" not in pages
    assert "\nrequirements\n" not in pages["index.md"]
    assert "](#hlr-x-1)" not in pages["traceability.md"]
    assert "`hlr_x.1`" in pages["traceability.md"]


def test_the_report_builds_with_the_requirement_pages(
    evidence_with_requirements: Evidence, tmp_path: Path
) -> None:
    """The strict build resolves every anchor the matrices link to."""
    ev = evidence_with_requirements
    render = tmp_path / "render" / "pages"
    render.mkdir(parents=True)
    for layer, nodes in ev.requirements.nodes.items() if ev.requirements else []:
        for node, statement in nodes.items():
            page = render / f"{statement.page}.md"
            page.parent.mkdir(parents=True, exist_ok=True)
            head = f"# {statement.page}\n\n" if not page.exists() else ""
            with page.open("a", encoding="utf-8") as fh:
                fh.write(
                    f"{head}({statement.anchor})=\n## {node} ({layer})\n\n{statement.text}\n\n"
                )

    pages = emit_pages(ev, build_obligations(ev))
    write_sphinx_sources(pages, tmp_path / "src", ev.title)
    copy_requirement_pages(render, tmp_path / "src", REQUIREMENTS_SUBDIR)

    assert build_html(tmp_path / "src", tmp_path / "html") == 0
    assert (tmp_path / "html" / REQUIREMENTS_SUBDIR / "hlr_x.html").is_file()


def test_copying_the_pages_drops_a_container_that_went_away(tmp_path: Path) -> None:
    """A stale page must not linger: the strict build would reject it as unreferenced."""
    render = tmp_path / "render"
    render.mkdir()
    (render / "hlr_x.md").write_text("# hlr_x\n", encoding="utf-8")
    srcdir = tmp_path / "src"
    (srcdir / REQUIREMENTS_SUBDIR).mkdir(parents=True)
    (srcdir / REQUIREMENTS_SUBDIR / "hlr_gone.md").write_text("# gone\n", encoding="utf-8")

    copy_requirement_pages(render, srcdir, REQUIREMENTS_SUBDIR)

    assert (srcdir / REQUIREMENTS_SUBDIR / "hlr_x.md").is_file()
    assert not (srcdir / REQUIREMENTS_SUBDIR / "hlr_gone.md").exists()


def test_evidence_ids_link_into_the_source_listings(evidence_with_requirements: Evidence) -> None:
    """A code id the render located is linked to the line it is listed at."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))

    assert "[`Ctrl.Do_Thing`](#src-x-ads-l10)" in pages["traceability.md"]


def test_the_listings_are_in_the_toctree_of_both_renderings(
    evidence_with_requirements: Evidence,
) -> None:
    """The evidence links into them, so a link must not resolve in one rendering only."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    listings = pages["source-listings.md"]

    assert "The requirements cite 1 file." in listings
    # Titled by the path the `src/` roots carry no information in, entered by page.
    assert f"x.ads <{REQUIREMENTS_SUBDIR}/sources/src-x-ads>" in listings
    assert "{only}" not in listings  # gating the pages would dangle the PDF's links
    assert "\nsource-listings\n" in pages["index.md"]
    assert "{ref}`source-listings`" in pages["requirements.md"]


def test_an_empty_pdf_is_reported_as_a_failure(tmp_path: Path) -> None:
    """rst2pdf logs a failed document and exits 0; an empty PDF is still a failure."""
    src = tmp_path / "src"
    write_sphinx_sources({"index.md": "# T\n\n[nowhere](#missing-target)\n"}, src, "T")

    assert build_pdf(src, tmp_path / "pdf") != 0


def test_a_failed_pdf_build_cannot_be_vouched_for_by_an_earlier_one(tmp_path: Path) -> None:
    """A previous rendering must not satisfy the check for a run that failed."""
    src = tmp_path / "src"
    write_sphinx_sources({"index.md": "# T\n\n[nowhere](#missing-target)\n"}, src, "T")
    out = tmp_path / "pdf"
    out.mkdir()
    stale = out / f"{PDF_NAME}.pdf"
    stale_bytes = b"%PDF-1.4 stale but plausible"
    stale.write_bytes(stale_bytes)

    assert build_pdf(src, out) != 0
    # Whatever is there now, it is not the rendering of an earlier run.
    assert not stale.exists() or stale.read_bytes() != stale_bytes


def test_evidence_ids_are_linked_in_the_open_items_and_verification_tables(
    evidence_with_requirements: Evidence,
) -> None:
    """The two tables a reviewer reads first link the same ids the full matrices do."""
    pages = emit_pages(evidence_with_requirements, build_obligations(evidence_with_requirements))
    traceability = pages["traceability.md"]
    open_items = traceability.split("## Open items")[1].split("## Verification matrix")[0]
    verification = traceability.split("## Verification matrix")[1].split("## Chain matrices")[0]

    # An open CONOPS row's detail names the HLRs that cover it (none, here), and
    # an open HLR row's detail names the CONOPS leaf its dangling ref points at.
    assert "[`hlr_x.3`](#hlr-x-3)" in open_items
    # The verification matrix's evidence cell links the test routine's listing.
    assert "[`u.Test_A`](#" in verification or "u.Test_A" in verification


def test_a_verification_cell_this_consumer_misreads_is_left_as_produced(
    evidence_with_requirements: Evidence,
) -> None:
    """When the rebuilt cell does not reproduce the producer's, the producer wins."""
    report = evidence_with_requirements.traceability.report
    assert report is not None
    matrix = report.verification[0].model_copy(
        update={
            "rows": [
                report.verification[0].rows[0].model_copy(update={"detail": "waived: see the note"})
            ]
        }
    )
    ev = evidence_with_requirements.model_copy(
        update={
            "traceability": evidence_with_requirements.traceability.model_copy(
                update={"report": report.model_copy(update={"verification": [matrix]})}
            )
        }
    )
    pages = emit_pages(ev, build_obligations(ev))

    assert "waived: see the note" in pages["traceability.md"]
