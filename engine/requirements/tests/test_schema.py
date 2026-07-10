"""Tests for the schema + structural checks (reqs.checks.schema)."""

from __future__ import annotations

from pathlib import Path

import pytest

from reqs.checks.schema import _count_shall, validate_paths
from reqs.core import Diagnostic, project_root

EXAMPLES = project_root() / "docs" / "examples"
FIX = Path(__file__).parent / "fixtures" / "invalid" / "schema"


def test_examples_validate_clean():
    """The curated examples have no errors in default mode."""
    errors = [d for d in validate_paths([EXAMPLES]) if d.level == "error"]
    assert not errors, "examples should have no errors:\n  " + "\n  ".join(
        d.format() for d in errors
    )


def test_complete_escalates_partial_trace():
    """Under --complete the deliberately-partial example trace becomes an error."""
    codes = {d.code for d in validate_paths([EXAMPLES], complete=True)}
    assert "E-PARENT-MISSING" in codes


# (description, [fixture files], expected code, expected level)
NEGATIVE_CASES = [
    ("unknown top-level key rejected", ["hlr_unknown_key.yaml"], "E-SCHEMA", "error"),
    ("source XOR derived (both)", ["hlr_both_source_derived.yaml"], "E-SCHEMA", "error"),
    ("source XOR derived (neither)", ["hlr_neither_source_derived.yaml"], "E-SCHEMA", "error"),
    ("description key gap", ["hlr_desc_gap.yaml"], "E-DESCKEY", "error"),
    ("duplicate description key", ["hlr_desc_dup.yaml"], "E-DESCKEY-DUP", "error"),
    ("empty description statement", ["hlr_desc_empty.yaml"], "E-SCHEMA", "error"),
    ("visibility must be non-empty string", ["llr_bad_visibility.yaml"], "E-SCHEMA", "error"),
    ("bad filename prefix", ["badprefix.yaml"], "E-PREFIX", "error"),
    ("two shall in a statement", ["hlr_two_shall.yaml"], "W-RS3", "warning"),
    ("LLR missing parent_req", ["llr_no_parent.yaml"], "E-SCHEMA", "error"),
    ("derived on LLR", ["llr_derived.yaml"], "E-SCHEMA", "error"),
    ("terminal rejected", ["hlr_terminal.yaml"], "E-SCHEMA", "error"),
    (
        "parent_req points to an LLR",
        ["llr_parent_is_llr.yaml", "llr_target_1.yaml"],
        "E-PARENT-TYPE",
        "error",
    ),
    ("parent_req must be a statement ID", ["llr_parent_barestem.yaml"], "E-PARENT-FORMAT", "error"),
]


@pytest.mark.parametrize(
    ("files", "code", "level"),
    [(files, code, level) for _, files, code, level in NEGATIVE_CASES],
    ids=[desc for desc, *_ in NEGATIVE_CASES],
)
def test_negative_fixture_fires(files, code, level):
    diags = validate_paths([FIX / f for f in files])
    assert (code, level) in {(d.code, d.level) for d in diags}


def test_missing_path_reports_clean_diagnostic(tmp_path):
    """A nonexistent path yields a located E-IO error, not a traceback."""
    missing = tmp_path / "does_not_exist"
    diags = validate_paths([missing])
    assert diags == [Diagnostic("error", "E-IO", "no such file or directory", missing)]


# RS.3 counts "shall" over requirement prose only -- the same reduction the EARS
# lint uses (reqs.core.prose). A "shall" hiding in markup must not be counted,
# else the two checks disagree about what is prose.
@pytest.mark.parametrize(
    ("statement", "expected"),
    [
        ("The system shall do the thing.", 1),
        ("The system shall do X.\n```\nit shall not\n```", 1),
        ("The system shall hold $$x \\text{ shall } y$$.", 1),
        ("The system shall act.\n| col | a shall b |\n| --- | --- |", 1),
        ("The system does the thing.", 0),
    ],
)
def test_count_shall_ignores_markup(statement, expected):
    assert _count_shall(statement) == expected
