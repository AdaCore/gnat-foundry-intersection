"""Tests for the code-inventory collector and the generics join it feeds."""

from __future__ import annotations

import json
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


def _write(path: Path, **overrides: object) -> Path:
    """Write a minimal inventory, so one record can be varied at a time."""
    payload: dict[str, object] = {
        "schema_version": 3,
        "tool": "ada_tracer",
        "project": "traffic_light.gpr",
        "packages": [],
        "library_subprograms": [],
    }
    payload.update(overrides)
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path


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


def test_a_generic_subprogram_in_an_ordinary_package_is_declared(tmp_path: Path) -> None:
    """
    The denominator's whole point: gnatprove cannot name this one.

    A generic procedure inside an ordinary package is reached only through an
    instance of its own, and nothing about the enclosing package says so.
    """
    path = _write(
        tmp_path / "code_inventory.json",
        packages=[
            {
                "name": "Buses",
                "spec_file": "src/types/buses.ads",
                "is_generic": False,
                "subprograms": [
                    {
                        "name": "Latch",
                        "qualified_name": "Buses.Latch",
                        "kind": "procedure",
                        "is_generic": True,
                        "location": {"file": "src/types/buses.ads", "line": 60, "column": 7},
                    }
                ],
            }
        ],
    )
    (generic,) = collect_inventory(path).generics
    assert (generic.name, generic.kind) == ("Buses.Latch", "procedure")
    assert generic.declared_in == "src/types/buses.ads"
    assert [(a.file, a.line) for a in generic.anchors] == [("src/types/buses.ads", 60)]


def test_a_generic_member_anchors_itself_not_its_package(tmp_path: Path) -> None:
    """
    Both are declarations, and the inner one owns its own lines.

    Were the member left among the package's anchors, a check inside it would
    attribute to the package -- crediting the outer generic with an instance
    that never reached the inner one.
    """
    path = _write(
        tmp_path / "code_inventory.json",
        packages=[
            {
                "name": "Hal.Ring",
                "spec_file": "src/hal/hal-ring.ads",
                "is_generic": True,
                "subprograms": [
                    {
                        "name": "Push",
                        "qualified_name": "Hal.Ring.Push",
                        "kind": "procedure",
                        "is_generic": False,
                        "location": {"file": "src/hal/hal-ring.ads", "line": 12, "column": 7},
                    },
                    {
                        "name": "Map",
                        "qualified_name": "Hal.Ring.Map",
                        "kind": "procedure",
                        "is_generic": True,
                        "location": {"file": "src/hal/hal-ring.ads", "line": 20, "column": 7},
                    },
                ],
            }
        ],
    )
    rows = {g.name: g for g in collect_inventory(path).generics}
    assert set(rows) == {"Hal.Ring", "Hal.Ring.Map"}
    assert [a.line for a in rows["Hal.Ring"].anchors] == [12]
    assert [a.line for a in rows["Hal.Ring.Map"].anchors] == [20]


def test_another_tool_s_json_is_not_an_inventory(tmp_path: Path) -> None:
    """
    A foreign file must not pass for the declared set.

    Accepted, it would supply an empty denominator -- "the sources declare no
    generics" -- and settle the obligation the inventory exists to raise.
    """
    path = _write(tmp_path / "code_inventory.json", tool="gnatprove")
    with pytest.raises(ArtifactParseError, match="ada_tracer"):
        collect_inventory(path)


def test_an_unsupported_schema_version_is_rejected(tmp_path: Path) -> None:
    """A schema this reader was not written against says nothing it can rely on."""
    path = _write(tmp_path / "code_inventory.json", schema_version=99)
    with pytest.raises(ArtifactParseError, match="schema_version"):
        collect_inventory(path)


def test_malformed_records_are_a_parse_error(tmp_path: Path) -> None:
    """Wrong shapes inside a well-formed file are reported, not raised raw at the CLI."""
    path = _write(tmp_path / "code_inventory.json", packages={"Buses": {}})
    with pytest.raises(ArtifactParseError, match="`packages`"):
        collect_inventory(path)
    path = _write(tmp_path / "code_inventory.json", library_subprograms=["Main"])
    with pytest.raises(ArtifactParseError, match="`library_subprograms`"):
        collect_inventory(path)
    path = _write(
        tmp_path / "code_inventory.json",
        library_subprograms=[
            {
                "qualified_name": "Main",
                "is_generic": True,
                "location": {"file": "src/app/main.adb", "line": "top"},
            }
        ],
    )
    with pytest.raises(ArtifactParseError, match="malformed inventory record"):
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
