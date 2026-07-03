"""Tests for the EARS grammar lint (reqs.checks.ears)."""

from __future__ import annotations

from pathlib import Path

import pytest

from reqs.checks.ears import lint_paths
from reqs.core import Diagnostic, project_root

EXAMPLES = project_root() / "docs" / "examples"
FIX = Path(__file__).parent / "fixtures" / "invalid" / "ears"


def test_examples_lint_clean() -> None:
    """Every example statement classifies as a valid EARS pattern."""
    diags = lint_paths([EXAMPLES])
    assert not diags, "examples should lint clean:\n  " + "\n  ".join(d.format() for d in diags)


# (description, fixture file, expected code)
NEGATIVE_CASES = [
    ("no shall", "hlr_ears_noshall.yaml", "E-EARS-NOSHALL"),
    ("When without comma", "hlr_ears_no_comma.yaml", "E-EARS-COMMA"),
    ("If without then", "hlr_ears_if_no_then.yaml", "E-EARS-IFTHEN"),
    ("lowercase keyword", "hlr_ears_case.yaml", "E-EARS-CASE"),
    ("no EARS pattern", "hlr_ears_pattern.yaml", "E-EARS-PATTERN"),
]


@pytest.mark.parametrize(
    ("fname", "code"),
    [(fname, code) for _, fname, code in NEGATIVE_CASES],
    ids=[desc for desc, *_ in NEGATIVE_CASES],
)
def test_negative_fixture_fires(fname: str, code: str) -> None:
    assert code in {d.code for d in lint_paths([FIX / fname])}


def test_optout_suppresses() -> None:
    """The ears:skip token suppresses all findings for a statement."""
    assert not lint_paths([FIX / "hlr_ears_skip.yaml"])


def test_missing_path_reports_io(tmp_path: Path) -> None:
    """A nonexistent path yields a located E-IO error, not a traceback."""
    missing = tmp_path / "does_not_exist"
    diags = lint_paths([missing])
    assert diags == [Diagnostic("error", "E-IO", "no such file or directory", missing)]
