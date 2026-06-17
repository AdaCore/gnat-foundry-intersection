"""
Schema + structural validation of requirement YAML files.

File level is chosen by filename prefix: ``hlr_`` -> high-level, ``llr_`` -> low-level.

Layered checks:

  Schema (JSON Schema 2020-12, ``schema/requirement.schema.json``)
    - field types, required fields, unknown-key rejection (additionalProperties:false,
      so ``test_cases`` and other unknown keys are errors)
    - source XOR derived on HLRs (oneOf)
    - visibility is a non-empty string (project-defined vocabulary, not a fixed enum)
    - non-empty description statements

  Structural (this module)
    - E-DESCKEY : description keys are integers, contiguous from 1
    - E-DUPID   : RS.2 - filename stems (IDs) unique across the validated set
    - E-PARENT-TYPE : an LLR parent_req that resolves to a non-HLR file
    - {E,W}-PARENT-MISSING : a parent_req that resolves to no file in the set.
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


def _level_of(path: Path) -> str | None:
    name = path.name
    if name.startswith(HLR_PREFIX):
        return "hlr"
    if name.startswith(LLR_PREFIX):
        return "llr"
    return None


def _req_id(path: Path) -> str:
    """Return the requirement ID (currently the filename stem; deferred item #1)."""
    return path.stem


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
        diags: list[Diagnostic] = []

        # First pass: parse, schema-validate, structural per-file checks.
        # Records (path, level, data) feed the cross-file pass.
        records: list[tuple[Path, str, dict]] = []
        seen_ids: dict[str, Path] = {}

        for path in iter_yaml_files(paths):
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

            req_id = _req_id(path)
            if req_id in seen_ids:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-DUPID",
                        f"duplicate requirement ID {req_id!r} (also {seen_ids[req_id]})",
                        path,
                    )
                )
            else:
                seen_ids[req_id] = path

            data, lines, error = load_yaml(path)
            if error is not None:
                diags.append(error)
                continue

            diags.extend(self._schema_check(path, level, data, lines))
            diags.extend(self._description_keys(path, data, lines))
            diags.extend(self._rs3_lint(path, data, lines))
            records.append((path, level, data))

        # Second pass: referential integrity needs the whole set.
        diags.extend(self._referential_integrity(records, seen_ids))
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

    def _referential_integrity(self, records, seen_ids) -> list[Diagnostic]:
        out: list[Diagnostic] = []
        for path, level, data in records:
            if level != "llr":
                continue
            parents = data.get("parent_req")
            if not isinstance(parents, list):
                continue  # schema already flagged a malformed/missing parent_req
            for parent in parents:
                target = seen_ids.get(parent)
                if target is None:
                    miss_level = "error" if self.complete else "warning"
                    out.append(
                        Diagnostic(
                            miss_level,
                            "E-PARENT-MISSING" if self.complete else "W-PARENT-MISSING",
                            f"parent_req {parent!r} resolves to no requirement in the set"
                            + ("" if self.complete else " (use --complete to require resolution)"),
                            path,
                            path=("parent_req",),
                        )
                    )
                elif _level_of(target) != "hlr":
                    out.append(
                        Diagnostic(
                            "error",
                            "E-PARENT-TYPE",
                            f"parent_req {parent!r} must reference an HLR, "
                            f"but {target.name} is not one",
                            path,
                            path=("parent_req",),
                        )
                    )
        return out


def validate_paths(paths, *, complete: bool = False) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests)."""
    return RequirementChecker(complete=complete).check(paths)
