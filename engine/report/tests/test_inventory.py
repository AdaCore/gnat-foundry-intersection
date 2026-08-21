"""Tests for the code-inventory collector and the generics join it feeds."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from vreport.inventory import collect_inventory, default_inventory_path
from vreport.model import (
    ArtifactParseError,
    CodeInventory,
    GenericDeclaration,
    MissingArtifactsError,
    Sloc,
)

if TYPE_CHECKING:
    from pathlib import Path

    from vreport.model import Evidence


def test_collects_nested_and_library_generics(inventory: CodeInventory) -> None:
    """Both kinds are declarations; only the tracer sees the nested ones."""
    assert [g.name for g in inventory.generics] == [
        "Buses.Display_Bus",
        "Buses.Source_Bus",
        "Hal.Ring",
        "State_Machine_Loop",
    ]
    nested = next(g for g in inventory.generics if g.name == "Buses.Source_Bus")
    assert nested.kind == "package"
    assert nested.declared_in == "src/types/buses.ads"
    # Spec and body both anchor it: a check can land in either.
    assert [(a.file, a.line) for a in nested.anchors] == [
        ("src/types/buses.adb", 6),
        ("src/types/buses.ads", 32),
    ]
    library = next(g for g in inventory.generics if g.name == "State_Machine_Loop")
    assert library.kind == "procedure"
    assert library.sources == ["state_machine_loop"]


def test_non_generics_are_left_out(inventory: CodeInventory) -> None:
    """The report wants the generics, not the whole inventory."""
    names = {g.name for g in inventory.generics}
    assert "Buses" not in names
    assert "Main" not in names


def test_missing_inventory_is_a_typed_error(tmp_path: Path) -> None:
    """An absent inventory is reported as such, so the CLI can fall back."""
    with pytest.raises(MissingArtifactsError):
        collect_inventory(tmp_path / "code_inventory.json")


def test_corrupt_inventory_names_the_file(tmp_path: Path) -> None:
    """A truncated inventory fails with the offending path, not a bare traceback."""
    path = tmp_path / "code_inventory.json"
    path.write_text("{ not json")
    with pytest.raises(ArtifactParseError, match=r"code_inventory\.json"):
        collect_inventory(path)


def test_non_object_inventory_is_rejected(tmp_path: Path) -> None:
    """Valid JSON of the wrong shape is still a parse failure."""
    path = tmp_path / "code_inventory.json"
    path.write_text("[]")
    with pytest.raises(ArtifactParseError):
        collect_inventory(path)


def test_default_path_matches_the_make_target(tmp_path: Path) -> None:
    """The CLI default has to be where `make code-inventory` writes."""
    assert default_inventory_path(tmp_path) == tmp_path / "obj" / "analysis" / "code_inventory.json"


def test_two_generics_in_one_file_are_told_apart(evidence: Evidence) -> None:
    """
    Per-line attribution, not per-file: `buses.ads` declares both bus generics.

    A file-level match would credit each of them with the other's instance, so
    a nested generic nothing instantiates could hide behind its neighbour.
    """
    rows = {g.name: g for g in evidence.generics}
    assert [i.site.line for i in rows["Buses.Source_Bus"].instances if i.site] == [42]
    assert [i.site.line for i in rows["Buses.Display_Bus"].instances if i.site] == [46]


def test_generics_outside_the_proof_scope_are_not_listed(evidence: Evidence) -> None:
    """An un-analyzed unit is not described by the report, so it cannot be a gap."""
    assert "Hal.Ring" not in {g.name for g in evidence.generics}


def test_ambiguous_unit_fallback_abstains(evidence: Evidence) -> None:
    """
    Two anchorless generics claiming one unit attribute to neither.

    The unit-level fallback exists for a library-level generic's body, which
    the inventory anchors only at its spec. With two candidates there is no
    sound answer, and guessing would credit a generic no instance reached.
    """
    assert evidence.inventory is not None
    twin = GenericDeclaration(
        name="State_Machine_Loop_Twin",
        kind="procedure",
        declared_in="src/core/state_machine_loop.ads",
        anchors=[Sloc(file="src/core/state_machine_loop.ads", line=18)],
    )
    inventory = evidence.inventory.model_copy(
        update={"generics": [*evidence.inventory.generics, twin]}
    )
    rows = {g.name: g for g in evidence.model_copy(update={"inventory": inventory}).generics}
    # Both are anchored in the spec, but every check is in the body: nothing
    # there distinguishes them, so neither is credited.
    assert rows["State_Machine_Loop"].instances == []
    assert rows["State_Machine_Loop_Twin"].instances == []
