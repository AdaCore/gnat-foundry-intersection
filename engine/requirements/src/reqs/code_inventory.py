"""
Load the ``ada_tracer`` JSON inventory of a project's Ada sources.

The bottom of the trace chain is the code, and reading Ada with regular
expressions rots -- two attempts in this repository's history did. So the
parsing is done once, by ``engine/ada_tracer`` (a Libadalang tool), into the
document described in ``engine/ada_tracer/json_schema.md``; this module is the
consumer side of that contract and the only place in ``reqs`` that knows the
document's shape.

The inventory is *generated, never committed* (``make inventories`` writes
``obj/analysis/code_inventory.json`` and ``obj/analysis/test_inventory.json``,
and ``make validate-reqs`` / ``make trace`` depend on it). It costs an Ada
toolchain and a Libadalang build wherever the requirements checks run, which is
the price of the alternative being unacceptable: a committed inventory that has
gone stale reports "every test traced" while the tests have moved, and that is
strictly worse than the regexes this replaced.

Only the fields the checks consume are modelled, and unknown ones are ignored:
the tracer's schema grows by addition, and a consumer that rejected a field it
does not read would break on every such change. The *version* is checked,
though -- a mismatch is ``E-INVENTORY-SCHEMA``, reported like any other
diagnostic rather than raised as a crash:

  E-IO               : the inventory is missing or unreadable
  E-INVENTORY-JSON   : it is not well-formed JSON
  E-INVENTORY-SCHEMA : wrong ``schema_version``, wrong ``tool``, or a field the
                       checks need is missing or of the wrong type
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from reqs.core import Diagnostic

if TYPE_CHECKING:
    import os
    from collections.abc import Iterator

SCHEMA_VERSION = 2
"""The ``schema_version`` this module can read. Owned here, not shared with the
tracer: the two are separate programs and the whole point of the field is that
they can disagree and say so."""

TOOL = "ada_tracer"


class _Model(BaseModel):
    """Strict about the types of what we read, tolerant of what we do not."""

    # `extra="ignore"` is deliberate -- see the module docstring.
    model_config = ConfigDict(extra="ignore", strict=True, frozen=True)


class Location(_Model):
    """Where a declaration is written."""

    file: str  # relative to the analysed project's directory, i.e. the repo root
    line: int
    column: int


class Tag(_Model):
    """One ``@tag`` parsed out of a comment block."""

    tag: str  # the tag word, without the `@`
    name: str  # empty for a tag that takes no name, such as `@covers`
    text: str
    line: int


class CommentBlock(_Model):
    """A run of comment lines inside a subprogram body, and its tags."""

    text: str
    first_line: int
    last_line: int
    # An array, not a map keyed by tag word: a body may carry the same tag
    # several times and each occurrence has its own line.
    tags: list[Tag] = Field(default_factory=list)


class Parameter(_Model):
    """One formal parameter, as written."""

    name: str
    mode: str
    type: str


class Subprogram(_Model):
    """One subprogram, entry, or one part of one."""

    name: str
    qualified_name: str
    kind: str
    declared_in: str
    is_renaming: bool
    is_body: bool
    parameters: list[Parameter] = Field(default_factory=list)
    location: Location
    body_comments: list[CommentBlock] = Field(default_factory=list)


class Entity(_Model):
    """One type, subtype, object or exception."""

    name: str
    qualified_name: str
    kind: str  # "type" | "subtype" | "constant" | "variable" | "exception"
    declared_in: str
    is_renaming: bool
    location: Location


class Package(_Model):
    """One package, with its spec and body merged."""

    name: str
    subprograms: list[Subprogram] = Field(default_factory=list)
    entities: list[Entity] = Field(default_factory=list)


class Inventory(_Model):
    """One ``ada_tracer`` run: everything it found in one project."""

    schema_version: int
    tool: str
    project: str
    packages: list[Package] = Field(default_factory=list)
    # Subprograms that are compilation units of their own and so belong to no
    # package -- `main.adb`'s `Main`, a library-level generic procedure.
    library_subprograms: list[Subprogram] = Field(default_factory=list)

    def all_subprograms(self) -> Iterator[Subprogram]:
        """Yield every subprogram entry, those in packages first."""
        for package in self.packages:
            yield from package.subprograms
        yield from self.library_subprograms

    def all_entities(self) -> Iterator[Entity]:
        """Yield every type, object and exception entry."""
        for package in self.packages:
            yield from package.entities


EMPTY = Inventory(schema_version=SCHEMA_VERSION, tool=TOOL, project="<none>")
"""Stand-in for an inventory that failed to load, so callers need no `None`
case: the diagnostics reported alongside it stop the run regardless."""


def load(path: str | os.PathLike[str]) -> tuple[Inventory, list[Diagnostic]]:
    """
    Load and validate the inventory at `path`.

    A missing file is an error, not an empty inventory: unlike a mistyped
    requirement directory, a missing inventory cannot be reported as "nothing
    found" without also reporting every test as untraced, which reads as a
    requirements problem when it is a build problem.
    """
    path = Path(path)
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as exc:
        return EMPTY, [Diagnostic("error", "E-IO", f"cannot read inventory: {exc}", path)]

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        return EMPTY, [Diagnostic("error", "E-INVENTORY-JSON", str(exc), path, line=exc.lineno)]

    try:
        inventory = Inventory.model_validate(data)
    except ValidationError as exc:
        return EMPTY, [
            Diagnostic(
                "error",
                "E-INVENTORY-SCHEMA",
                err["msg"],
                path,
                path=tuple(str(p) for p in err["loc"]),
            )
            for err in exc.errors(include_url=False)
        ]

    diags: list[Diagnostic] = []
    if inventory.tool != TOOL:
        diags.append(
            Diagnostic(
                "error",
                "E-INVENTORY-SCHEMA",
                f"not an {TOOL} document (tool is {inventory.tool!r})",
                path,
            )
        )
    if inventory.schema_version != SCHEMA_VERSION:
        diags.append(
            Diagnostic(
                "error",
                "E-INVENTORY-SCHEMA",
                f"schema_version is {inventory.schema_version}, expected {SCHEMA_VERSION}; "
                f"regenerate the inventory with a matching ada_tracer",
                path,
            )
        )
    if diags:
        return EMPTY, diags

    return inventory, diags
