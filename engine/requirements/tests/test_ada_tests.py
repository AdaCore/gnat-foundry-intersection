"""
Tests for the test-suite trace layer (reqs.ada_tests).

Each GNATtest routine body is one trace node: its id is ``<unit>.<routine>``,
its up-refs are the ids in its ``--@covers`` tags, and a ``--@covers none`` tag
marks it derived (verifies code no requirement governs). The set is queried by
the level-agnostic trace engine exactly like a CONOPS / requirement set.

The input is the ``ada_tracer`` inventory, not Ada source -- see
``inventory_fixture``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from inventory_fixture import gnattest_routine, package, write_inventory

from reqs.ada_tests import TestSet
from reqs.code_inventory import Inventory

if TYPE_CHECKING:
    from pathlib import Path

    from reqs.core import Diagnostic

FILE = "tests/core/conflicts-test_data-tests.adb"

# A routine's forward declaration and `renames` alias are entries of their own;
# only the body ends in `is`, and only the body can host a `--@covers` tag (the
# read-only regions around it are regenerated).
ROUTINES = [
    gnattest_routine("Test_Compatible", FILE, line=33, is_body=False),
    gnattest_routine("Test_Compatible_abc123", FILE, line=34, is_renaming=True),
    gnattest_routine("Test_Compatible", FILE, line=36, covers=["llr_3_conflicts.1"]),
    gnattest_routine(
        "Test_Safe_Faces",
        FILE,
        line=42,
        covers=["llr_3_conflicts.3, llr_3_conflicts.6", "llr_0_safety.1"],
    ),
]


def load_with_diagnostics(
    tmp_path: Path, *packages: dict[str, Any]
) -> tuple[TestSet, list[Diagnostic]]:
    """Write an inventory of the given packages and load it as a test set."""
    path = write_inventory(tmp_path / "test_inventory.json", packages=packages)
    inventory = Inventory.model_validate_json(path.read_text(encoding="utf-8"))
    return TestSet.from_inventory(inventory, path)


def load(tmp_path: Path, *packages: dict[str, Any]) -> TestSet:
    """As above, for the cases that expect no diagnostics."""
    tests, diags = load_with_diagnostics(tmp_path, *packages)
    assert diags == []
    return tests


def conflicts(tmp_path: Path) -> TestSet:
    """Load the standard fixture package."""
    return load(tmp_path, package("Conflicts.Test_Data.Tests", subprograms=ROUTINES))


def test_node_id_is_unit_dot_routine(tmp_path: Path) -> None:
    """A node's id is the file's unit stem (before the first '-') and its routine."""
    ids = {nid for nid, _n in conflicts(tmp_path).all_statements()}
    assert ids == {"conflicts.Test_Compatible", "conflicts.Test_Safe_Faces"}


def test_declaration_and_renames_are_not_nodes(tmp_path: Path) -> None:
    """Only the routine *body* is a node, not its declaration or its renames."""
    nodes = conflicts(tmp_path).nodes
    assert "conflicts.Test_Compatible_abc123" not in nodes
    assert len(nodes) == 2


def test_body_wins_over_forward_declaration(tmp_path: Path) -> None:
    """A routine's node is its body, so its line and tags are the body's."""
    node = conflicts(tmp_path).statement("conflicts.Test_Compatible")
    assert node is not None
    assert node.line == 36  # the body, not the forward declaration on line 33
    assert node.up_refs == ["llr_3_conflicts.1"]


def test_covers_ids_are_unioned_across_tags(tmp_path: Path) -> None:
    """Comma-/space-separated ids across several tags on one routine are unioned."""
    node = conflicts(tmp_path).statement("conflicts.Test_Safe_Faces")
    assert node is not None
    assert node.up_refs == ["llr_3_conflicts.3", "llr_3_conflicts.6", "llr_0_safety.1"]
    assert not node.is_derived


def test_none_tag_marks_derived(tmp_path: Path) -> None:
    """`--@covers none: <reason>` marks the node derived with no up-refs."""
    file = "tests/hal/common/display-test_data-tests.adb"
    node = load(
        tmp_path,
        package(
            "Display.Test_Data.Tests",
            subprograms=[
                gnattest_routine(
                    "Test_Show",
                    file,
                    line=79,
                    covers=["none: rendering is out of requirement scope (llr_6_hal)"],
                )
            ],
        ),
    ).statement("display.Test_Show")
    assert node is not None
    assert node.up_refs == []
    assert node.is_derived


def test_untagged_routine_has_no_refs_and_is_not_derived(tmp_path: Path) -> None:
    """A routine with no `--@covers` tag has empty refs and is not derived (=> untraced)."""
    file = "tests/types/states-test_data-tests.adb"
    node = load(
        tmp_path,
        package(
            "States.Test_Data.Tests",
            subprograms=[gnattest_routine("Test_Face_Of", file, line=36)],
        ),
    ).statement("states.Test_Face_Of")
    assert node is not None
    assert node.up_refs == []
    assert not node.is_derived  # a bare test is UNTRACED, not accounted-for


def test_helper_with_test_name_but_wrong_profile_is_not_a_node(tmp_path: Path) -> None:
    """`Test_*` alone does not make a routine a test; the GNATtest profile does."""
    nodes = load(
        tmp_path,
        package(
            "Conflicts.Test_Data.Tests",
            subprograms=[
                gnattest_routine("Test_Helper", FILE, line=20, parameters=[]),
                gnattest_routine("Test_Compatible", FILE, line=36),
            ],
        ),
    ).nodes
    assert set(nodes) == {"conflicts.Test_Compatible"}


def test_library_subprograms_are_searched_too(tmp_path: Path) -> None:
    """A routine outside any package is still a candidate node."""
    path = write_inventory(
        tmp_path / "test_inventory.json",
        library_subprograms=[gnattest_routine("Test_Loose", "tests/loose-tests.adb", line=5)],
    )
    inventory = Inventory.model_validate_json(path.read_text(encoding="utf-8"))
    tests, diags = TestSet.from_inventory(inventory, path)
    assert set(tests.nodes) == {"loose.Test_Loose"}
    assert diags == []


def test_loc_of_points_at_tag_for_up_ref_else_routine(tmp_path: Path) -> None:
    """An up_ref location is the first `--@covers` line; otherwise the routine line."""
    tests = conflicts(tmp_path)
    path, routine_line, loc = tests.loc_of("conflicts.Test_Compatible")
    _path, ref_line, _loc = tests.loc_of("conflicts.Test_Compatible", sub_key="up_ref")
    assert loc == ()  # Ada bodies have no YAML-style key path
    assert str(path) == FILE  # the Ada source, not the inventory
    assert routine_line == 36  # the `procedure ... is` line
    assert ref_line == 40  # the `--@covers` line


def test_empty_inventory_yields_empty_set(tmp_path: Path) -> None:
    """
    An inventory with no packages is an empty set, not an error *here*.

    Whether an empty layer is acceptable is the chain's business, not this
    module's: it is the TEST layer's `min_nodes` that rejects one (see
    ``reqs.checks.trace``), because only the chain knows how many routines the
    harness is supposed to hold.
    """
    assert load(tmp_path).nodes == {}


def test_two_files_sharing_a_unit_stem_is_reported(tmp_path: Path) -> None:
    """A node-id collision is diagnosed, not silently resolved to the first routine."""
    tests, diags = load_with_diagnostics(
        tmp_path,
        package(
            "Display.Test_Data.Tests",
            subprograms=[
                gnattest_routine(
                    "Test_Show",
                    "tests/hal/host/display-test_data-tests.adb",
                    line=36,
                    covers=["llr_6_hal.1"],
                ),
                gnattest_routine(
                    "Test_Show",
                    "tests/hal/qemu_zynq7000/display-test_data-tests.adb",
                    line=36,
                    covers=["llr_6_hal.2"],
                ),
            ],
        ),
    )
    assert set(tests.nodes) == {"display.Test_Show"}  # first wins, as before...
    assert [d.code for d in diags] == ["E-TEST-DUPID"]  # ...but the second is not lost silently
    assert "qemu_zynq7000" in diags[0].message
