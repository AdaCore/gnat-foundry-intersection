"""Tests for the traceability and git-provenance collectors."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

import pytest

from vreport.model import (
    TRACE_REPORT_SCHEMA_VERSION,
    ArtifactParseError,
    MissingArtifactsError,
)
from vreport.provenance import collect_git
from vreport.traceability import collect_trace_report, collect_traceability

FIXTURES = Path(__file__).parent / "fixtures"

_WAIVERS = """\
waivers:
  - leaf: "1.1"
    reason: Physical site assumption.
  - leaf: "5.2"
    reason: >-
      Explicit exclusion; negative scope.
"""

_HLR = """\
context: Timing.
description:
  1:
    text: The controller shall do the timed thing.
    source: ["CONOPS §3.1"]
  2:
    text: The controller shall do the derived thing.
    derived: true
"""


def _write_report(tmp_path: Path, **overrides: Any) -> Path:
    """Write a minimal (clean) trace report under the default path."""
    payload: dict[str, Any] = {
        "schema_version": TRACE_REPORT_SCHEMA_VERSION,
        "chain": "requirements/trace_chain.yaml",
        "complete": True,
        "corpus_valid": True,
        "errors": 0,
        "warnings": 0,
        "layers": [],
        "pairs": [],
        "verification": [],
        "diagnostics": [],
    }
    payload.update(overrides)
    path = tmp_path / "reports" / "trace" / "trace_report.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


def test_collect_traceability(tmp_path: Path) -> None:
    """The trace report, waivers, and derived HLR statements are all gathered."""
    _write_report(tmp_path, errors=2)
    reqs = tmp_path / "requirements"
    (reqs / "hlr").mkdir(parents=True)
    (reqs / "trace_waivers.yaml").write_text(_WAIVERS)
    (reqs / "hlr" / "hlr_3_timing.yaml").write_text(_HLR)

    trace = collect_traceability(tmp_path)
    assert trace.report is not None
    assert trace.report.errors == 2
    assert trace.waivers_found
    assert trace.hlr_found
    assert [w.leaf for w in trace.waivers] == ["1.1", "5.2"]
    assert trace.waivers[1].reason == "Explicit exclusion; negative scope."
    assert len(trace.derived) == 1
    assert trace.derived[0].ident == "hlr_3_timing.2"
    assert "derived thing" in trace.derived[0].text


def test_collect_traceability_absent(tmp_path: Path) -> None:
    """No requirements tree is reported as such, not invented."""
    _write_report(tmp_path)
    trace = collect_traceability(tmp_path)
    assert not trace.waivers_found
    assert not trace.hlr_found
    assert trace.waivers == []
    assert trace.derived == []


def test_collect_traceability_sources_tracked_separately(tmp_path: Path) -> None:
    """One source's presence must not vouch for the other's."""
    _write_report(tmp_path)
    reqs = tmp_path / "requirements"
    (reqs / "hlr").mkdir(parents=True)
    (reqs / "hlr" / "hlr_3_timing.yaml").write_text(_HLR)
    trace = collect_traceability(tmp_path)
    assert not trace.waivers_found
    assert trace.hlr_found

    (reqs / "trace_waivers.yaml").write_text(_WAIVERS)
    (reqs / "hlr" / "hlr_3_timing.yaml").unlink()
    (reqs / "hlr").rmdir()
    trace = collect_traceability(tmp_path)
    assert trace.waivers_found
    assert not trace.hlr_found


def test_collect_trace_report_parses_the_fixture() -> None:
    """The fixture report parses into the typed model with its matrices."""
    report = collect_trace_report(FIXTURES / "trace" / "trace_report.json")
    assert report.corpus_valid
    assert report.errors == 3
    assert [layer.name for layer in report.layers] == ["CONOPS", "HLR", "LLR", "TEST", "CODE"]
    assert report.pairs[0].upper_rows[0].status == "WAIVED"
    assert report.verification[0].rows[1].review_facets[0].evidence == [
        "Argued against MUTCD §4E.01."
    ]


def test_collect_trace_report_missing_is_a_missing_artifact(tmp_path: Path) -> None:
    """An absent trace report raises the missing-artifact error, naming the path."""
    with pytest.raises(MissingArtifactsError, match="trace report"):
        collect_trace_report(tmp_path / "trace_report.json")


def test_collect_trace_report_rejects_malformed_json(tmp_path: Path) -> None:
    """Malformed JSON fails with the file named, not a bare decode error."""
    path = tmp_path / "trace_report.json"
    path.write_text("{ not json", encoding="utf-8")
    with pytest.raises(ArtifactParseError, match="trace_report"):
        collect_trace_report(path)


def test_collect_trace_report_rejects_unknown_schema_version(tmp_path: Path) -> None:
    """A schema this reader does not understand must not be half-parsed."""
    path = _write_report(tmp_path, schema_version=99)
    with pytest.raises(ArtifactParseError, match="schema_version"):
        collect_trace_report(path)


def test_collect_trace_report_rejects_unexpected_shape(tmp_path: Path) -> None:
    """Fields drifting past the model fail loudly with the file named."""
    path = _write_report(tmp_path, pairs=[{"unexpected": True}])
    with pytest.raises(ArtifactParseError, match="trace_report"):
        collect_trace_report(path)


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True, text=True)


def test_collect_git(tmp_path: Path) -> None:
    """Commit, branch, and dirtiness are read from a real repository."""
    _git(tmp_path, "init", "-q", "-b", "main")
    _git(
        tmp_path,
        "-c",
        "user.email=t@t",
        "-c",
        "user.name=t",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "x",
    )
    info = collect_git(tmp_path)
    assert info is not None
    assert info.branch == "main"
    assert not info.dirty
    (tmp_path / "f").write_text("x")
    dirty = collect_git(tmp_path)
    assert dirty is not None
    assert dirty.dirty
