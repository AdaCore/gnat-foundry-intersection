"""Tests for the traceability and git-provenance collectors."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

from vreport.provenance import collect_git
from vreport.traceability import collect_traceability

if TYPE_CHECKING:
    from pathlib import Path

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


def test_collect_traceability(tmp_path: Path) -> None:
    """Waivers and derived HLR statements are gathered with their identities."""
    reqs = tmp_path / "requirements"
    (reqs / "hlr").mkdir(parents=True)
    (reqs / "trace_waivers.yaml").write_text(_WAIVERS)
    (reqs / "hlr" / "hlr_3_timing.yaml").write_text(_HLR)

    trace = collect_traceability(tmp_path)
    assert trace.sources_found
    assert [w.leaf for w in trace.waivers] == ["1.1", "5.2"]
    assert trace.waivers[1].reason == "Explicit exclusion; negative scope."
    assert len(trace.derived) == 1
    assert trace.derived[0].ident == "hlr_3_timing.2"
    assert "derived thing" in trace.derived[0].text


def test_collect_traceability_absent(tmp_path: Path) -> None:
    """No requirements tree is reported as such, not invented."""
    trace = collect_traceability(tmp_path)
    assert not trace.sources_found
    assert trace.waivers == []
    assert trace.derived == []


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
