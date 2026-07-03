"""
Smoke tests for the `reqs` CLI exit-code contract (reqs.cli).

The CLI's contract is the only thing CI depends on: exit non-zero iff any
error was reported, exit zero otherwise. These tests lock that contract down
by driving the Typer app over the clean examples and over known-bad fixtures.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from typer.testing import CliRunner

from reqs.cli import app
from reqs.core import project_root

runner = CliRunner()

EXAMPLES = project_root() / "docs" / "examples"
FIX = Path(__file__).parent / "fixtures" / "invalid"

# An error-level fixture per validate subcommand (codes asserted in the
# per-check test modules; here we only care that they drive the exit code).
SCHEMA_ERROR = FIX / "schema" / "hlr_unknown_key.yaml"
EARS_ERROR = FIX / "ears" / "hlr_ears_noshall.yaml"


@pytest.mark.parametrize("subcommand", ["schema", "ears"])
def test_clean_examples_exit_zero(subcommand: str) -> None:
    """Validating the curated examples exits 0 (no errors)."""
    result = runner.invoke(app, ["validate", subcommand, str(EXAMPLES)])
    assert result.exit_code == 0, result.output


@pytest.mark.parametrize(
    ("subcommand", "fixture"),
    [("schema", SCHEMA_ERROR), ("ears", EARS_ERROR)],
)
def test_error_fixture_exits_nonzero(subcommand: str, fixture: Path) -> None:
    """An error-level finding drives a non-zero exit code."""
    result = runner.invoke(app, ["validate", subcommand, str(fixture)])
    assert result.exit_code != 0, result.output


def test_no_args_is_help() -> None:
    """Bare `validate` prints help and does not exit zero (no_args_is_help)."""
    result = runner.invoke(app, ["validate"])
    assert result.exit_code != 0
    assert "schema" in result.output
    assert "ears" in result.output
