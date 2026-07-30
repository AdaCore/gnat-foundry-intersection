"""Tests for the MyST emitters and the strict Sphinx build."""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

from vreport.build import build_html, build_pdf, write_sphinx_sources
from vreport.emit import emit_pages
from vreport.model import CoverageViolation, Sloc
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
