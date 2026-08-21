"""
Collect the declared-code inventory from the Ada tracer.

Reads ``obj/analysis/code_inventory.json`` (``make code-inventory``), the
libadalang parse of the project's own sources. The report takes one thing from
it: the set of generics the code *declares*. That set is the denominator the
proof evidence is judged against, and it has to come from the sources, because
the case worth catching — a generic no analyzed instance reaches — is precisely
the one gnatprove's output cannot name.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

from vreport.model import (
    ArtifactParseError,
    CodeInventory,
    GenericDeclaration,
    MissingArtifactsError,
    Sloc,
)

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence
    from pathlib import Path

TOOL = "ada_tracer"
SCHEMA_VERSIONS = (3,)


def _sloc(raw: Any) -> Sloc | None:
    """Build a Sloc from a tracer ``location`` record."""
    if not isinstance(raw, dict) or "file" not in raw:
        return None
    return Sloc(
        file=str(raw["file"]),
        line=int(raw.get("line", 0)),
        column=int(raw["column"]) if raw.get("column") is not None else None,
    )


def _anchors(items: Sequence[Mapping[str, Any]]) -> list[Sloc]:
    """Collect the declaration locations of a package's members, in file order."""
    locs = [loc for item in items if (loc := _sloc(item.get("location"))) is not None]
    return sorted(locs, key=lambda s: (s.file, s.line))


def _package_generic(raw: Mapping[str, Any]) -> GenericDeclaration:
    """Build a GenericDeclaration for a generic package (possibly a nested one)."""
    spec = str(raw.get("spec_file") or raw.get("body_file") or "")
    # A generic member carries a row of its own and anchors itself there.
    # Leaving it out of the package's anchors is what lets a check inside it
    # attribute to it rather than to the package enclosing it.
    plain = [s for s in raw.get("subprograms") or [] if not s.get("is_generic")]
    return GenericDeclaration(
        name=str(raw.get("name", "?")),
        kind="package",
        declared_in=spec,
        anchors=_anchors([*plain, *(raw.get("entities") or [])]),
    )


def _subprogram_generic(raw: Mapping[str, Any]) -> GenericDeclaration:
    """Build a GenericDeclaration for one generic subprogram declaration."""
    loc = _sloc(raw.get("location"))
    return GenericDeclaration(
        name=str(raw.get("qualified_name") or raw.get("name", "?")),
        kind=str(raw.get("kind", "subprogram")),
        declared_in=loc.file if loc else "",
        anchors=[loc] if loc else [],
    )


def _member_generics(raw: Mapping[str, Any]) -> list[GenericDeclaration]:
    """
    Build a declaration for each generic subprogram a package declares.

    Nesting makes a generic nobody else's obligation: a generic subprogram
    inside a package -- ordinary or itself generic -- is reached only through an
    instance of its own, and no enclosing declaration stands in for it. It is
    also the kind gnatprove's output cannot name, so omitted here it would be
    missing from the denominator altogether.
    """
    return [_subprogram_generic(s) for s in raw.get("subprograms") or [] if s.get("is_generic")]


def _records(data: Mapping[str, Any], key: str, path: Path) -> list[Mapping[str, Any]]:
    """Read one array of records, insisting on the shape the schema promises."""
    raw = data.get(key) or []
    if not isinstance(raw, list) or any(not isinstance(item, dict) for item in raw):
        raise ArtifactParseError(path, f"`{key}` must be an array of objects")
    return raw


def _check_contract(data: Mapping[str, Any], path: Path) -> None:
    """
    Insist the file is an inventory this reader understands.

    An unrecognized inventory must not pass for a real one. A *missing*
    inventory the report carries as an open review item, saying in so many words
    that the generics it lists are gnatprove's own; an inventory of the wrong
    tool or schema would instead be read as the authoritative denominator --
    most likely an empty one, which reads as "the sources declare no generics"
    and settles the obligation against nothing.
    """
    tool = data.get("tool")
    if tool != TOOL:
        raise ArtifactParseError(
            path,
            f"not a {TOOL} inventory (tool={tool!r}) -- regenerate with `make code-inventory`",
        )
    version = data.get("schema_version")
    if version not in SCHEMA_VERSIONS:
        raise ArtifactParseError(
            path,
            f"unsupported schema_version {version!r} (this reader supports "
            f"{', '.join(str(v) for v in SCHEMA_VERSIONS)}) -- regenerate with "
            "`make code-inventory`",
        )


def collect_inventory(path: Path) -> CodeInventory:
    """Parse the tracer's code inventory, keeping the generics it declares."""
    if not path.is_file():
        raise MissingArtifactsError(path, "code inventory (ada_tracer JSON)")
    try:
        data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactParseError(path, str(exc)) from exc
    if not isinstance(data, dict):
        raise ArtifactParseError(path, "expected a JSON object")
    _check_contract(data, path)

    packages = _records(data, "packages", path)
    subprograms = _records(data, "library_subprograms", path)
    # A malformed record is the same failure as a malformed file, and the CLI
    # knows how to report that one against a path.
    try:
        generics = [
            *(_package_generic(p) for p in packages if p.get("is_generic")),
            *(g for p in packages for g in _member_generics(p)),
            *(_subprogram_generic(s) for s in subprograms if s.get("is_generic")),
        ]
        project = str(data["project"]) if data.get("project") else None
    except (AttributeError, TypeError, ValueError) as exc:
        raise ArtifactParseError(path, f"malformed inventory record: {exc}") from exc
    return CodeInventory(
        schema_version=int(data["schema_version"]),
        project=project,
        generics=sorted(generics, key=lambda g: g.name),
    )


def default_inventory_path(root: Path) -> Path:
    """Where `make code-inventory` leaves the inventory under a project root."""
    return root / "obj" / "analysis" / "code_inventory.json"
