"""Tests for the vreport CLI."""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING

from typer.testing import CliRunner

from vreport import cli
from vreport.cli import app

if TYPE_CHECKING:
    import pytest
    from typer.testing import Result

FIXTURES = Path(__file__).parent / "fixtures"

runner = CliRunner()


def _generate_args(tmp_path: Path, *extra: str) -> list[str]:
    return [
        "generate",
        "--root",
        str(tmp_path),
        "--out",
        str(tmp_path / "out"),
        "--proof-dir",
        str(FIXTURES / "gnatprove"),
        "--coverage-dir",
        str(FIXTURES / "gnatcov"),
        "--trace-report",
        str(FIXTURES / "trace" / "trace_report.json"),
        "--no-html",
        *extra,
    ]


def test_generate_writes_evidence_and_sources(tmp_path: Path) -> None:
    """A successful run leaves evidence.json and the MyST sources."""
    result = runner.invoke(app, _generate_args(tmp_path))
    assert result.exit_code == 0, result.output
    evidence = json.loads((tmp_path / "out" / "evidence.json").read_text())
    assert evidence["schema_version"] == 1
    assert evidence["proof"]["units"] == [
        "buses",
        "buses_proof",
        "conflicts",
        "controller",
        "main",
        "state_machine_loop",
        "state_machine_loop_proof",
        "synthetic",
    ]
    for page in ("index.md", "provenance.md", "proof.md", "coverage.md", "traceability.md"):
        assert (tmp_path / "out" / "src" / page).exists()
    assert "obligations:" in result.output


def test_generate_missing_proof_dir_fails(tmp_path: Path) -> None:
    """Missing proof artifacts abort the run instead of emitting an empty report."""
    empty = tmp_path / "empty"
    empty.mkdir()
    result = runner.invoke(
        app,
        [
            "generate",
            "--root",
            str(tmp_path),
            "--out",
            str(tmp_path / "out"),
            "--proof-dir",
            str(empty),
            "--coverage-dir",
            str(FIXTURES / "gnatcov"),
            "--trace-report",
            str(FIXTURES / "trace" / "trace_report.json"),
            "--no-html",
        ],
    )
    assert result.exit_code == 1


def test_generate_missing_trace_report_fails(tmp_path: Path) -> None:
    """A missing trace report aborts the run with the regenerating make target named."""
    result = runner.invoke(
        app,
        [
            "generate",
            "--root",
            str(tmp_path),
            "--out",
            str(tmp_path / "out"),
            "--proof-dir",
            str(FIXTURES / "gnatprove"),
            "--coverage-dir",
            str(FIXTURES / "gnatcov"),
            "--no-html",
        ],
    )
    assert result.exit_code == 1
    assert "make trace-report" in result.output


def _requirements(tmp_path: Path, reason: str = "Physical site assumption.") -> Path:
    """Build a requirement tree with one waiver, one derived statement, and a CONOPS."""
    reqs = tmp_path / "requirements"
    (reqs / "hlr").mkdir(parents=True, exist_ok=True)
    (reqs / "conops.md").write_text("- **1.1 ✔** A leaf.\n")
    (reqs / "trace_waivers.yaml").write_text(f'waivers:\n  - leaf: "1.1"\n    reason: {reason}\n')
    (reqs / "hlr" / "hlr_x.yaml").write_text(
        "description:\n  4:\n    text: Derived text.\n    derived: true\n"
    )
    return reqs


def _signoff(tmp_path: Path, *extra: str) -> Result:
    return runner.invoke(app, ["signoff", "--root", str(tmp_path), *extra])


def test_signoff_lists_every_item_as_unsigned(tmp_path: Path) -> None:
    """With no record yet, the listing names each item and what is outstanding."""
    _requirements(tmp_path)
    result = _signoff(tmp_path)
    assert result.exit_code == 0, result.output
    for item in ("conops", "waiver:1.1", "derived:hlr_x.4"):
        assert item in result.output, item
    assert "3 of 3 items carry no current sign-off" in result.output


def test_signoff_stamps_one_item(tmp_path: Path) -> None:
    """Stamping records the reviewer, the date, and the digest of what they read."""
    reqs = _requirements(tmp_path)
    result = _signoff(tmp_path, "--item", "waiver:1.1", "--by", "Tony", "--date", "2026-08-21")
    assert result.exit_code == 0, result.output
    assert "signed off waiver:1.1 (Tony, 2026-08-21)" in result.output
    record = (reqs / "signoffs.yaml").read_text()
    assert record.startswith("#")  # the header saying who may write it
    assert "sha256:" in record

    listed = _signoff(tmp_path)
    assert "signed — Tony, 2026-08-21" in listed.output
    assert "2 of 3 items carry no current sign-off" in listed.output


def test_signoff_all_then_an_edit_lapses_only_that_item(tmp_path: Path) -> None:
    """`--all` greens the baseline; editing one reason re-opens that item alone."""
    reqs = _requirements(tmp_path)
    result = _signoff(tmp_path, "--all", "--by", "Tony", "--date", "2026-08-21")
    assert result.exit_code == 0, result.output
    assert "all 3 items carry a current sign-off" in _signoff(tmp_path).output
    assert "nothing to do" in _signoff(tmp_path, "--all", "--by", "Tony").output

    (reqs / "trace_waivers.yaml").write_text('waivers:\n  - leaf: "1.1"\n    reason: Changed.\n')
    listed = _signoff(tmp_path)
    assert "LAPSED" in listed.output
    assert "1 of 3 items carry no current sign-off" in listed.output


def test_signoff_rejects_an_unknown_item(tmp_path: Path) -> None:
    """Only enumerated items can be signed, so a typo cannot green nothing at all."""
    _requirements(tmp_path)
    result = _signoff(tmp_path, "--item", "waiver:9.9", "--by", "Tony")
    assert result.exit_code == 1
    assert "no such item: waiver:9.9" in result.output


def test_signoff_refuses_contradictory_and_unsignable_requests(tmp_path: Path) -> None:
    """--item and --all conflict; and a missing CONOPS has nothing to sign."""
    _requirements(tmp_path)
    clash = _signoff(tmp_path, "--item", "conops", "--all", "--by", "Tony")
    assert clash.exit_code == 1
    assert "mutually exclusive" in clash.output

    (tmp_path / "requirements" / "conops.md").unlink()
    result = _signoff(tmp_path, "--item", "conops", "--by", "Tony")
    assert result.exit_code == 1
    assert "its text is missing" in result.output


def test_signoff_reports_a_broken_record(tmp_path: Path) -> None:
    """An unparseable record aborts rather than reading as "nothing signed"."""
    reqs = _requirements(tmp_path)
    (reqs / "signoffs.yaml").write_text("signoffs: [\n")
    result = _signoff(tmp_path)
    assert result.exit_code == 1
    assert "signoffs.yaml" in result.output


def test_signoff_needs_a_named_reviewer(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """A sign-off names who gave it, so an unattributable one is refused."""
    _requirements(tmp_path)
    monkeypatch.setattr(cli, "git_user_name", lambda _root: None)
    result = _signoff(tmp_path, "--item", "conops")
    assert result.exit_code == 1
    assert "no reviewer" in result.output
