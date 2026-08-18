"""Tests for the vreport CLI."""

from __future__ import annotations

import json
from pathlib import Path

from typer.testing import CliRunner

from vreport.cli import app

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
