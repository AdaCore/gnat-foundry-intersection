"""Tests for the schema + structural checks (reqs.checks.schema)."""

from __future__ import annotations

from pathlib import Path

import pytest

from reqs.checks.schema import _count_shall, validate_paths
from reqs.core import Diagnostic, project_root
from reqs.requirement_set import RequirementSet

EXAMPLES = project_root() / "docs" / "examples"
FIX = Path(__file__).parent / "fixtures" / "invalid" / "schema"


def test_examples_validate_clean() -> None:
    """The curated examples have no errors in default mode."""
    errors = [d for d in validate_paths([EXAMPLES]) if d.level == "error"]
    assert not errors, "examples should have no errors:\n  " + "\n  ".join(
        d.format() for d in errors
    )


def test_complete_escalates_partial_trace() -> None:
    """Under --complete the deliberately-partial example trace becomes an error."""
    codes = {d.code for d in validate_paths([EXAMPLES], complete=True)}
    assert "E-PARENT-MISSING" in codes


# (description, [fixture files], expected code, expected level)
NEGATIVE_CASES = [
    ("unknown top-level key rejected", ["hlr_unknown_key.yaml"], "E-SCHEMA", "error"),
    ("source XOR derived (both)", ["hlr_both_source_derived.yaml"], "E-SCHEMA", "error"),
    ("source XOR derived (neither)", ["hlr_neither_source_derived.yaml"], "E-SCHEMA", "error"),
    ("description key gap", ["hlr_desc_gap.yaml"], "E-DESCKEY", "error"),
    ("non-integer description key", ["hlr_desc_strkey.yaml"], "E-SCHEMA", "error"),
    ("duplicate description key", ["hlr_desc_dup.yaml"], "E-DESCKEY-DUP", "error"),
    ("empty description statement", ["hlr_desc_empty.yaml"], "E-SCHEMA", "error"),
    ("explicit null rejected", ["hlr_source_null.yaml"], "E-SCHEMA", "error"),
    ("visibility must be non-empty string", ["llr_bad_visibility.yaml"], "E-SCHEMA", "error"),
    ("bad filename prefix", ["badprefix.yaml"], "E-PREFIX", "error"),
    ("two shall in a statement", ["hlr_two_shall.yaml"], "W-RS3", "warning"),
    ("LLR missing parent_req", ["llr_no_parent.yaml"], "E-SCHEMA", "error"),
    ("derived on LLR", ["llr_derived.yaml"], "E-SCHEMA", "error"),
    ("terminal rejected", ["hlr_terminal.yaml"], "E-SCHEMA", "error"),
    ("file-wide implemented_by", ["llr_filewide_implemented_by.yaml"], "E-SCHEMA", "error"),
    ("empty implemented_by", ["llr_empty_implemented_by.yaml"], "E-SCHEMA", "error"),
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
def test_negative_fixture_fires(files: list[str], code: str, level: str) -> None:
    """Each invalid fixture is reported with its expected diagnostic code and level."""
    diags = validate_paths([FIX / f for f in files])
    assert (code, level) in {(d.code, d.level) for d in diags}


def test_duplicate_stem_resolves_into_first_file_only() -> None:
    """
    A duplicated container stem resolves into the first file only.

    The stem is an E-DUPID: `hlr_dup_stem.2` exists only in the second file
    (reported as duplicate), so referencing it is a miss; `hlr_dup_stem.1` is
    found in a file that reported no duplicates, so referencing it is valid.
    """
    reqset, diags = RequirementSet.load(
        [
            FIX / "dup_stem" / "first" / "hlr_dup_stem.yaml",
            FIX / "dup_stem" / "second" / "hlr_dup_stem.yaml",
            FIX / "dup_stem" / "llr_dup_stem_ref.yaml",
        ]
    )
    assert "E-DUPID" in {d.code for d in diags}
    statement_1 = reqset.statement("hlr_dup_stem.1")
    assert statement_1 is not None
    assert statement_1[1].text == "The widget shall do the thing."
    assert reqset.statement("hlr_dup_stem.2") is None


def test_duplicate_stem_with_invalid_first_claimant() -> None:
    """A duplicate file is flagged E-DUPID even if the first claimant is invalid."""
    first = FIX / "dup_stem_invalid_first" / "first" / "hlr_dup_inv.yaml"
    second = FIX / "dup_stem_invalid_first" / "second" / "hlr_dup_inv.yaml"
    llr = FIX / "dup_stem_invalid_first" / "llr_dup_inv_ref.yaml"

    assert validate_paths([first, second, llr]) == [
        Diagnostic(
            "error",
            "E-SCHEMA",
            "Extra inputs are not permitted",
            first,
            line=3,
            path=("unknown_key",),
        ),
        Diagnostic(
            "error",
            "E-DUPID",
            f"duplicate container stem 'hlr_dup_inv' (also {first})",
            second,
        ),
    ]

    reqset, _ = RequirementSet.load([first, second, llr])
    assert set(reqset.by_stem) == {"llr_dup_inv_ref"}
    assert {f.path for f in reqset.duplicates} == {second}


def test_missing_path_reports_clean_diagnostic(tmp_path: Path) -> None:
    """A nonexistent path yields a located E-IO error, not a traceback."""
    missing = tmp_path / "does_not_exist"
    diags = validate_paths([missing])
    assert diags == [Diagnostic("error", "E-IO", "no such file or directory", missing)]


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
def test_count_shall_ignores_markup(statement: str, expected: int) -> None:
    """
    RS.3 counts "shall" over requirement prose only.

    This is the same reduction the EARS lint uses (reqs.core.prose). A "shall"
    hiding in markup must not be counted, else the two checks disagree about
    what is prose.
    """
    assert _count_shall(statement) == expected
