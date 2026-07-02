"""
Schema + structural validation of requirement YAML files.

File level is chosen by filename prefix: ``hlr_`` -> high-level, ``llr_`` -> low-level.

A requirement's ID is ``<stem>.<number>`` (see docs/README.md): the file's stem
identifies the *container*, the ``description`` key identifies the statement.

Layered checks:

  Schema (JSON Schema 2020-12, ``schema/requirement.schema.json``)
    - field types, required fields, unknown-key rejection (additionalProperties:false,
      so ``test_cases`` and other unknown keys are errors)
    - up-ref (`source` on HLR statements, `parent_req` on LLR statements) XOR
      `derived` (oneOf) on each statement
    - non-empty string values

  Structural (this module)
    - E-DESCKEY     : description keys are integers, contiguous from 1
    - E-DESCKEY-DUP : a statement number is repeated within a file (``safe_load``
      silently merges duplicate keys, so it is caught from the raw node tree)
    - E-DUPID       : RS.2 - container stems unique across the validated set
    - E-PARENT-FORMAT : a parent_req entry that is not a ``<stem>.<number>``
      statement ID (e.g. a bare container stem)
    - E-PARENT-TYPE : a parent_req whose resolved statement lives in a non-HLR file
    - {E,W}-PARENT-MISSING : a parent_req that resolves to no statement in the set.
      Warning by default (the curated examples are deliberately partial);
      error when ``complete=True`` (a full requirement set must trace cleanly).

  Lint / soft (warnings; never fail the run)
    - W-RS3 : each description statement should contain exactly one "shall".
      Counted over requirement prose only (``reqs.core.prose`` -- code blocks,
      ``$$`` math, and table/list lines are stripped, the same reduction the
      EARS lint uses). Opt a statement out by including the token ``rs3:skip``
      anywhere in it.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml
from jsonschema import Draft202012Validator

from reqs.core import (
    SHALL_RE,
    Diagnostic,
    iter_yaml_files,
    load_yaml,
    prose,
    schema_path,
)

HLR_PREFIX = "hlr_"
LLR_PREFIX = "llr_"
RS3_OPTOUT = "rs3:skip"

# A full requirement ID is '<stem>.<number>' (see docs/README.md). Split on the
# final dot; <number> is a positive integer (a description key).
_REF_RE = re.compile(r"^(?P<stem>.+)\.(?P<number>[1-9][0-9]*)$")


def _level_of(path: Path) -> str | None:
    name = path.name
    if name.startswith(HLR_PREFIX):
        return "hlr"
    if name.startswith(LLR_PREFIX):
        return "llr"
    return None


def _stem(path: Path) -> str:
    """Return the requirement container's ID (the filename stem)."""
    return path.stem


def _number(key: Any) -> str:
    """Return a statement's number (a description key) as its ID component."""
    return str(key)


def _req_id(stem: str, number: Any) -> str:
    """Assemble a full statement ID '<stem>.<number>' (see docs/README.md)."""
    return f"{stem}.{_number(number)}"


def _jsonify_keys(obj: Any) -> Any:
    """Stringify mapping keys so JSON Schema (string-keyed) can validate YAML int keys."""
    if isinstance(obj, dict):
        return {str(k): _jsonify_keys(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_jsonify_keys(v) for v in obj]
    return obj


def _count_shall(statement: str) -> int:
    return len(SHALL_RE.findall(prose(statement)))


class RequirementChecker:
    """Schema + structural + RS.3 checks over a set of requirement files."""

    def __init__(self, *, complete: bool = False) -> None:
        self.complete = complete
        schema_doc = yaml.safe_load(schema_path().read_text(encoding="utf-8"))
        defs = {"$defs": schema_doc["$defs"]}
        self._validators = {
            level: Draft202012Validator({"$ref": f"#/$defs/{level}", **defs})
            for level in ("hlr", "llr")
        }

    def check(self, paths) -> list[Diagnostic]:
        files, diags = iter_yaml_files(paths)

        # First pass: parse, schema-validate, structural per-file checks.
        # Records (path, level, data, lines) feed the cross-file pass.
        records: list[tuple[Path, str, dict, dict]] = []
        seen_stems: dict[str, Path] = {}

        for path in files:
            level = _level_of(path)
            if level is None:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-PREFIX",
                        f"filename must start with {HLR_PREFIX!r} or {LLR_PREFIX!r}",
                        path,
                    )
                )
                continue

            stem = _stem(path)
            if stem in seen_stems:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-DUPID",
                        f"duplicate container stem {stem!r} (also {seen_stems[stem]})",
                        path,
                    )
                )
            else:
                seen_stems[stem] = path

            data, lines, dups, error = load_yaml(path)
            if error is not None:
                diags.append(error)
                continue

            diags.extend(self._schema_check(path, level, data, lines))
            diags.extend(self._description_keys(path, data, lines))
            diags.extend(self._duplicate_keys(path, lines, dups))
            diags.extend(self._rs3_lint(path, data, lines))
            records.append((path, level, data, lines))

        # Second pass: referential integrity needs the whole set.
        diags.extend(self._referential_integrity(records))
        return diags

    def _schema_check(self, path, level, data, lines) -> list[Diagnostic]:
        out: list[Diagnostic] = []
        jsonable = _jsonify_keys(data)
        for err in sorted(self._validators[level].iter_errors(jsonable), key=str):
            tpath = tuple(str(p) for p in err.absolute_path)
            out.append(
                Diagnostic(
                    "error",
                    "E-SCHEMA",
                    err.message,
                    path,
                    line=lines.get(tpath) or lines.get(tpath[:1]),
                    path=tpath,
                )
            )
        return out

    def _description_keys(self, path, data, lines) -> list[Diagnostic]:
        desc = data.get("description")
        if not isinstance(desc, dict) or not desc:
            return []  # absence/shape is the schema's job
        out: list[Diagnostic] = []
        non_int = [k for k in desc if not isinstance(k, int) or isinstance(k, bool)]
        if non_int:
            out.append(
                Diagnostic(
                    "error",
                    "E-DESCKEY",
                    f"description keys must be integers; got {sorted(map(str, non_int))}",
                    path,
                    line=lines.get(("description",)),
                    path=("description",),
                )
            )
            return out
        keys = sorted(desc)
        expected = list(range(1, len(keys) + 1))
        if keys != expected:
            out.append(
                Diagnostic(
                    "error",
                    "E-DESCKEY",
                    f"description keys must be contiguous from 1; got {keys}, expected {expected}",
                    path,
                    line=lines.get(("description",)),
                    path=("description",),
                )
            )
        return out

    def _duplicate_keys(self, path, lines, dups) -> list[Diagnostic]:
        return [
            Diagnostic(
                "error",
                "E-DESCKEY-DUP",
                f"duplicate description key {k!r}; statement numbers must be unique within a file",
                path,
                line=lines.get(("description", k)),
                path=("description", k),
            )
            for k in dups
        ]

    def _rs3_lint(self, path, data, lines) -> list[Diagnostic]:
        desc = data.get("description")
        if not isinstance(desc, dict):
            return []
        out: list[Diagnostic] = []
        for key, statement in desc.items():
            if not isinstance(statement, str) or RS3_OPTOUT in statement:
                continue
            n = _count_shall(statement)
            if n != 1:
                out.append(
                    Diagnostic(
                        "warning",
                        "W-RS3",
                        f'statement {key} should contain exactly one "shall" (found {n}); '
                        f"add {RS3_OPTOUT!r} to opt out",
                        path,
                        line=lines.get(("description", str(key))),
                        path=("description", str(key)),
                    )
                )
        return out

    def _referential_integrity(self, records) -> list[Diagnostic]:
        # Build the registry from the whole set: every statement ID and its
        # container's level, plus which container stems exist at all.
        statements: dict[str, str] = {}  # "<stem>.<number>" -> container level
        stem_levels: dict[str, str] = {}  # "<stem>" -> level
        for path, level, data, _lines in records:
            stem = _stem(path)
            stem_levels[stem] = level
            desc = data.get("description")
            if isinstance(desc, dict):
                for key in desc:
                    statements[_req_id(stem, key)] = level

        out: list[Diagnostic] = []
        for path, level, data, lines in records:
            if level != "llr":
                continue
            desc = data.get("description")
            if not isinstance(desc, dict):
                continue
            for key, statement in desc.items():
                if not isinstance(statement, dict):
                    continue  # schema already flagged a malformed statement
                parents = statement.get("parent_req")
                if not isinstance(parents, list):
                    continue  # absent (derived) or malformed (the schema's job)
                loc = ("description", _number(key), "parent_req")
                line = lines.get(loc) or lines.get(loc[:2])
                for parent in parents:
                    diag = self._parent_diagnostic(parent, statements, stem_levels, path, line, loc)
                    if diag is not None:
                        out.append(diag)
        return out

    def _parent_diagnostic(  # noqa: PLR0913
        self,
        parent,
        statements: dict[str, str],
        stem_levels: dict[str, str],
        file: Path,
        line: int | None,
        loc: tuple[str, ...],
    ) -> Diagnostic | None:
        """Check one parent_req entry; return its Diagnostic, or None if it resolves to an HLR."""
        match = _REF_RE.match(parent) if isinstance(parent, str) else None
        if match is None:
            return Diagnostic(
                "error",
                "E-PARENT-FORMAT",
                f"parent_req {parent!r} must be a '<stem>.<number>' statement ID, "
                "not a bare container stem",
                file,
                line=line,
                path=loc,
            )
        target_level = statements.get(parent)
        if target_level is None:
            pstem = match["stem"]
            detail = (
                f"no statement {parent!r} in {pstem!r}"
                if pstem in stem_levels
                else f"no requirement container {pstem!r} in the set"
            )
            return Diagnostic(
                "error" if self.complete else "warning",
                "E-PARENT-MISSING" if self.complete else "W-PARENT-MISSING",
                f"parent_req {parent!r} resolves to nothing ({detail})"
                + ("" if self.complete else " (use --complete to require resolution)"),
                file,
                line=line,
                path=loc,
            )
        if target_level != "hlr":
            return Diagnostic(
                "error",
                "E-PARENT-TYPE",
                f"parent_req {parent!r} must reference an HLR statement; "
                f"its container {match['stem']!r} is an {target_level.upper()}",
                file,
                line=line,
                path=loc,
            )
        return None


def validate_paths(paths, *, complete: bool = False) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests)."""
    return RequirementChecker(complete=complete).check(paths)
