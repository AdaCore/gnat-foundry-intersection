"""Tests for the gnatcov XML report parser."""

from __future__ import annotations

from pathlib import Path

import pytest

from vreport.gnatcov import collect_coverage
from vreport.model import (
    TOTAL_LINES,
    ArtifactParseError,
    CoverageEvidence,
    MissingArtifactsError,
)

FIXTURES = Path(__file__).parent / "fixtures" / "gnatcov"


def test_level_and_version(coverage: CoverageEvidence) -> None:
    """Coverage level and tool version are recorded."""
    assert coverage.level == "stmt+mcdc"
    assert coverage.version_text == "GNATcoverage FSF 26.2"


def test_traces(coverage: CoverageEvidence) -> None:
    """trace.xml identifies the test execution that produced the data."""
    assert len(coverage.traces) == 1
    assert coverage.traces[0].program == "Test_Driver"


def test_global_metrics(coverage: CoverageEvidence) -> None:
    """Global line counts and per-criterion obligation stats are read."""
    assert coverage.counts[TOTAL_LINES] == 540
    by_kind = {o.kind: o for o in coverage.obligations}
    assert set(by_kind) == {"Stmt", "Decision", "MCDC"}
    stmt = by_kind["Stmt"]
    assert stmt.total == 227
    assert stmt.covered == 206
    assert stmt.not_covered == 20
    assert stmt.exempted == 1
    assert stmt.pct == pytest.approx(90.7)


def test_files(coverage: CoverageEvidence) -> None:
    """Per-file entries are relativized against the project root."""
    assert [f.path for f in coverage.files] == [
        "src/app/main.adb",
        "src/hal/host/sources.adb",
    ]


def test_scopes(coverage: CoverageEvidence) -> None:
    """Nested scope metrics flatten to dotted names."""
    main = coverage.files[0]
    names = {s.name for s in main.scopes}
    assert "Main" in names
    assert "Main.Source_Wire" in names


def test_violations(coverage: CoverageEvidence) -> None:
    """Statement violations carry location, kind, and source text."""
    non_exempted = coverage.non_exempted_violations
    assert len(non_exempted) == 6
    assert all(v.location.file == "src/app/main.adb" for v in non_exempted)
    assert all(v.obligation_kind == "STATEMENT" for v in non_exempted)
    assert all(v.message == "not executed" for v in non_exempted)
    assert all(v.source_text for v in non_exempted)
    assert all(v.location.line > 0 for v in non_exempted)


def test_exemption(coverage: CoverageEvidence) -> None:
    """The exempted region carries its justification and its masked violation."""
    assert len(coverage.exemptions) == 1
    exemption = coverage.exemptions[0]
    assert exemption.file == "src/hal/host/sources.adb"
    assert exemption.justification.startswith("live-tty only:")
    exempted = coverage.exempted_violations
    assert len(exempted) == 1
    assert exempted[0].obligation_kind == "DECISION"
    assert "never exercised" in exempted[0].message
    assert exemption.masked == exempted


_TWO_REGION_INDEX = """<?xml version="1.0" ?>
<document>
 <coverage_report coverage_level="stmt">
  <coverage_summary>
   <file name="/r/two.adb"><metric kind="not_covered" count="0"/></file>
  </coverage_summary>
 </coverage_report>
</document>
"""

_TWO_REGION_SOURCE = """<?xml version="1.0" ?>
<source file="/r/two.adb" coverage_level="stmt">
 <src_mapping coverage="*">
  <src><line num="5" src="pragma Annotate (Xcov, Exempt_On, ...);"/></src>
  <message kind="notice" message="Exempted region justification: &quot;first&quot;"/>
 </src_mapping>
 <src_mapping coverage="*">
  <statement id="1" text="S1;" coverage="-">
   <src><line num="6" column_begin="4" src="S1;"/></src>
  </statement>
  <message kind="violation" SCO="SCO #1: STATEMENT" message="not executed"/>
 </src_mapping>
 <src_mapping coverage="*">
  <src><line num="8" src="pragma Annotate (Xcov, Exempt_On, ...);"/></src>
  <message kind="notice" message="Exempted region justification: &quot;second&quot;"/>
 </src_mapping>
 <src_mapping coverage="*">
  <statement id="2" text="S2;" coverage="-">
   <src><line num="9" column_begin="4" src="S2;"/></src>
  </statement>
  <message kind="violation" SCO="SCO #2: STATEMENT" message="not executed"/>
 </src_mapping>
</source>
"""


def test_two_exempted_regions_attribute_separately(tmp_path: Path) -> None:
    """Masked violations attach to their own region, not to every region in the file."""
    (tmp_path / "index.xml").write_text(_TWO_REGION_INDEX)
    (tmp_path / "two.adb.xml").write_text(_TWO_REGION_SOURCE)
    coverage = collect_coverage(tmp_path, tmp_path)
    assert [e.justification for e in coverage.exemptions] == ["first", "second"]
    first, second = coverage.exemptions
    assert [v.location.line for v in first.masked] == [6]
    assert [v.location.line for v in second.masked] == [9]


def test_corrupt_index_names_the_file(tmp_path: Path) -> None:
    """A malformed index.xml fails with the offending path named."""
    (tmp_path / "index.xml").write_text("<document><unclosed>")
    with pytest.raises(ArtifactParseError, match=r"index\.xml"):
        collect_coverage(tmp_path, tmp_path)


def test_missing_artifacts(tmp_path: Path) -> None:
    """A directory without index.xml is a hard error."""
    with pytest.raises(MissingArtifactsError):
        collect_coverage(tmp_path, tmp_path)


def test_missing_per_source(tmp_path: Path) -> None:
    """A summary entry without its per-source report is a hard error."""
    (tmp_path / "index.xml").write_text(
        """<?xml version="1.0" ?>
<document>
 <coverage_report coverage_level="stmt">
  <coverage_summary>
   <file name="/x/missing.adb"><metric kind="not_covered" count="1"/></file>
  </coverage_summary>
 </coverage_report>
</document>
"""
    )
    with pytest.raises(MissingArtifactsError):
        collect_coverage(tmp_path, tmp_path)
