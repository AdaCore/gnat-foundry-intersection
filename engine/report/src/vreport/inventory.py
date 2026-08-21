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
    members = [*(raw.get("subprograms") or []), *(raw.get("entities") or [])]
    return GenericDeclaration(
        name=str(raw.get("name", "?")),
        kind="package",
        declared_in=spec,
        anchors=_anchors(members),
    )


def _subprogram_generic(raw: Mapping[str, Any]) -> GenericDeclaration:
    """Build a GenericDeclaration for a library-level generic subprogram."""
    loc = _sloc(raw.get("location"))
    return GenericDeclaration(
        name=str(raw.get("qualified_name") or raw.get("name", "?")),
        kind=str(raw.get("kind", "subprogram")),
        declared_in=loc.file if loc else "",
        anchors=[loc] if loc else [],
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

    generics = [_package_generic(p) for p in data.get("packages") or [] if p.get("is_generic")] + [
        _subprogram_generic(s) for s in data.get("library_subprograms") or [] if s.get("is_generic")
    ]
    return CodeInventory(
        schema_version=int(data.get("schema_version", 0)),
        project=str(data["project"]) if data.get("project") else None,
        generics=sorted(generics, key=lambda g: g.name),
    )


def default_inventory_path(root: Path) -> Path:
    """Where `make code-inventory` leaves the inventory under a project root."""
    return root / "obj" / "analysis" / "code_inventory.json"
