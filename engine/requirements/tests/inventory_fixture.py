"""
Builders for the ``ada_tracer`` inventory JSON that the code-backed layers read.

The TEST and CODE layers no longer read Ada; they read the document described in
``engine/ada_tracer/json_schema.md``. Their fixtures are therefore that document,
which makes these tests faster and more honest -- they stop re-testing
Libadalang, and what they do test is the contract between the two programs.

Shapes here must match what the tracer actually emits. The `--@covers` case in
particular: consecutive tag lines are **one** comment block carrying several
tags, which is why ``tags`` is an array in the schema.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

from reqs.code_inventory import SCHEMA_VERSION, TOOL

if TYPE_CHECKING:
    from collections.abc import Sequence
    from pathlib import Path

# The profile GNATtest gives every test routine; `reqs.ada_tests` checks it.
GNATTEST_PARAMS = [{"name": "Gnattest_T", "mode": "in out", "type": "Test"}]

# How far below the `procedure ... is` line a GNATtest tag block starts: the
# generated `--  <spec>:<line>:<col>:<name>` / `--  end read only` pair sits
# between them.
TAG_OFFSET = 4


def gnattest_routine(
    name: str,
    file: str,
    *,
    line: int,
    covers: Sequence[str] = (),
    tag_line: int | None = None,
    is_body: bool = True,
    is_renaming: bool = False,
    parameters: list[dict[str, str]] | None = None,
) -> dict[str, Any]:
    """
    Build one subprogram entry for a GNATtest routine.

    `covers` is one payload per ``--@covers`` line; they land in a single comment
    block, as consecutive comment lines do in the real document.
    """
    first = line + TAG_OFFSET if tag_line is None else tag_line
    blocks: list[dict[str, Any]] = []
    if covers:
        blocks.append(
            {
                "text": "\n".join(f"@covers {c}" for c in covers),
                "first_line": first,
                "last_line": first + len(covers) - 1,
                "tags": [
                    {"tag": "covers", "name": "", "text": c, "line": first + i}
                    for i, c in enumerate(covers)
                ],
            }
        )
    return subprogram(
        name,
        file=file,
        line=line,
        is_body=is_body,
        is_renaming=is_renaming,
        parameters=GNATTEST_PARAMS if parameters is None else parameters,
        body_comments=blocks,
    )


def subprogram(
    name: str,
    *,
    file: str,
    line: int,
    qualified_name: str | None = None,
    kind: str = "procedure",
    declared_in: str = "body",
    is_body: bool = False,
    is_renaming: bool = False,
    parameters: list[dict[str, str]] | None = None,
    body_comments: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build one subprogram entry."""
    return {
        "name": name,
        "qualified_name": name if qualified_name is None else qualified_name,
        "kind": kind,
        "declared_in": declared_in,
        "nested": False,
        "has_body": False,
        "is_generic": False,
        "is_renaming": is_renaming,
        "is_expression_function": False,
        "is_abstract": False,
        "is_body": is_body,
        "parameters": [] if parameters is None else parameters,
        "return_type": None,
        "location": {"file": file, "line": line, "column": 4},
        "doc": {},
        "body_comments": [] if body_comments is None else body_comments,
    }


def entity(qualified_name: str, *, file: str, line: int, kind: str = "type") -> dict[str, Any]:
    """Build one entity entry (type, subtype, constant, variable or exception)."""
    return {
        "name": qualified_name.rsplit(".", 1)[-1],
        "qualified_name": qualified_name,
        "kind": kind,
        "declared_in": "spec",
        "is_renaming": False,
        "location": {"file": file, "line": line, "column": 4},
        "doc": {},
    }


def package(
    name: str,
    *,
    subprograms: Sequence[dict[str, Any]] = (),
    entities: Sequence[dict[str, Any]] = (),
    spec_file: str | None = None,
) -> dict[str, Any]:
    """Build one package entry."""
    return {
        "name": name,
        "spec_file": spec_file,
        "body_file": None,
        "is_generic": False,
        "doc": {},
        "subprograms": list(subprograms),
        "entities": list(entities),
    }


def check(
    *,
    file: str,
    line: int,
    kind: str = "pragma",
    name: str = "Compile_Time_Error",
    covers: Sequence[str] = (),
) -> dict[str, Any]:
    """Build one `--@covers`-tagged check entry (a pragma or an aspect)."""
    return {
        "kind": kind,
        "name": name,
        "location": {"file": file, "line": line, "column": 4},
        "covers": list(covers),
    }


def write_inventory(
    path: Path,
    *,
    packages: Sequence[dict[str, Any]] = (),
    library_subprograms: Sequence[dict[str, Any]] = (),
    checks: Sequence[dict[str, Any]] = (),
    schema_version: int = SCHEMA_VERSION,
    tool: str = TOOL,
) -> Path:
    """Write an inventory document and return its path."""
    path.write_text(
        json.dumps(
            {
                "schema_version": schema_version,
                "tool": tool,
                "project": "fixture.gpr",
                "packages": list(packages),
                "library_subprograms": list(library_subprograms),
                "checks": list(checks),
            }
        ),
        encoding="utf-8",
    )
    return path
