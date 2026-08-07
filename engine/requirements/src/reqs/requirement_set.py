"""
Validate-and-load requirement YAML files into a typed requirement set.

See ``docs/README.md`` for the file format and the requirement-ID scheme.

The schema for the file content lives in ``reqs.document``; this module defines
runtime file objects that carry additional metadata (a file's path and line
numbers).

:meth:`RequirementSet.load` validates each file against its document schema and
returns files as a :class:`RequirementSet` -- queryable by container
stem or statement ID -- plus the diagnostics for everything that failed on
the way:

  E-PREFIX      : filename has neither level prefix
  E-IO / E-YAML : unreadable / unparsable file (from ``reqs.core.load_yaml``)
  E-SCHEMA      : the file does not match its document schema (see
                  ``reqs.document``)
  E-DESCKEY     : description keys are not contiguous from 1
  E-DESCKEY-DUP : a statement number is repeated within a file
  E-DUPID       : RS.2 - container stems are not unique across the files found

A file that fails validation is reported and left out of the set. Additional
schema rules that do not need to be enforced to load a type-valid
``RequirementSet`` live in ``reqs.checks.schema``.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar, Literal

from pydantic import BaseModel, ValidationError

from reqs.core import Diagnostic, SubKey, YAMLLineMap, iter_yaml_files, load_yaml
from reqs.document import HlrDocument, LlrDocument, Statement

if TYPE_CHECKING:
    import os
    from collections.abc import Iterable, Iterator

HLR_PREFIX = "hlr_"
LLR_PREFIX = "llr_"

# A full requirement ID is '<stem>.<number>' (see docs/README.md). Split on the
# final dot; <number> is a positive integer (a description key).
_REF_RE = re.compile(r"^(?P<stem>.+)\.(?P<number>[1-9][0-9]*)$")


def parse_req_id(ref: str) -> tuple[str, int] | None:
    """Split a full statement ID into `(stem, number)`; `None` if invalid."""
    if (match := _REF_RE.match(ref)) is None:
        return None
    return match["stem"], int(match["number"])


class _BaseFile(BaseModel):
    """Load provenance carried by the runtime file types on top of their document."""

    level: ClassVar[Literal["hlr", "llr"]]

    path: Path
    lines: YAMLLineMap

    @property
    def stem(self) -> str:
        return self.path.stem

    def nearest_line(self, loc: tuple[str, ...]) -> int | None:
        """Source line of the longest known prefix of `loc`."""
        return _nearest_line(self.lines, loc)


class HlrFile(_BaseFile, HlrDocument):
    """An HLR document plus where it came from."""

    level: ClassVar[Literal["hlr"]] = "hlr"

    @classmethod
    def load(cls, path: Path, data: dict[str, object], lines: YAMLLineMap) -> HlrFile:
        """Validate `data` as an HLR document (may raise) and attach provenance."""
        document = HlrDocument.model_validate(data)
        return cls.model_construct(path=path, lines=lines, **dict(document))

    def loc_of(
        self, number: int, sub_key: SubKey | None = None
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line number and YAML key path of the specified statement.

        Raises `KeyError` if `number` is not present.
        """
        return _loc_of(self, number, sub_key)


class LlrFile(_BaseFile, LlrDocument):
    """An LLR document plus where it came from."""

    level: ClassVar[Literal["llr"]] = "llr"

    @classmethod
    def load(cls, path: Path, data: dict[str, object], lines: YAMLLineMap) -> LlrFile:
        """Validate `data` as an LLR document (may raise) and attach provenance."""
        document = LlrDocument.model_validate(data)
        return cls.model_construct(path=path, lines=lines, **dict(document))

    def loc_of(
        self, number: int, sub_key: SubKey | None = None
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line number and YAML key path of the specified statement.

        Raises `KeyError` if `number` is not present.
        """
        return _loc_of(self, number, sub_key)


RequirementFile = HlrFile | LlrFile


def _loc_of(
    file: RequirementFile, number: int, sub_key: SubKey | None = None
) -> tuple[Path, int, tuple[str, ...]]:
    """
    Return file path, line number and YAML key path of the specified statement.

    Shared implementation of ``HlrFile.loc_of`` / ``LlrFile.loc_of``. Raises
    `KeyError` if `number` is not present.
    """
    statement = file.description[number]
    loc: tuple[str, ...] = ("description", str(number))
    # The key a `sub_key` names is per-level ("source" vs "parent_req"), and a
    # level may not have one at all; the location then falls back to the statement.
    if sub_key == "text":
        key = "text"
    elif sub_key == "up_ref":
        key = statement.up_ref_key
    elif sub_key in statement.down_ref_fields:
        key = sub_key
    else:
        key = None
    if key is not None:
        loc = (*loc, key)
    line = file.nearest_line(loc)
    if line is None:
        # Should be unreachable; `compose_lines()` should always record at least
        # `("description",)` for any file successfully loaded.
        msg = f"could not find source line for {'.'.join(loc)} in {file.path}"
        raise RuntimeError(msg)
    return file.path, line, loc


def _file_class(path: Path) -> type[RequirementFile] | None:
    """Return the file type a path loads as (by filename prefix); None = E-PREFIX."""
    if path.name.startswith(HLR_PREFIX):
        return HlrFile
    if path.name.startswith(LLR_PREFIX):
        return LlrFile
    return None


class RequirementSet:
    """
    A validated requirement set, queryable by container stem or statement ID.

    `by_stem` is the canonical view: one file per stem; first file wins.
    Duplicate stems are kept in `duplicates` so per-file checks still lint
    their content.
    """

    by_stem: dict[str, RequirementFile]
    duplicates: tuple[RequirementFile, ...]

    def __init__(
        self, files: Iterable[RequirementFile], duplicates: Iterable[RequirementFile] = ()
    ) -> None:
        files = tuple(files)
        self.by_stem = {file.stem: file for file in files}
        if len(self.by_stem) != len(files):
            msg = "files must contain at most one file per stem; partition duplicates first"
            raise ValueError(msg)
        self.duplicates = tuple(duplicates)

    @classmethod
    def load(
        cls, paths: Iterable[str | os.PathLike[str]]
    ) -> tuple[RequirementSet, list[Diagnostic]]:
        """Validate and load requirement files, collecting diagnostics for the rest."""
        found, diags = iter_yaml_files(paths)
        files: list[RequirementFile] = []
        duplicates: list[RequirementFile] = []
        seen_stems: dict[str, Path] = {}

        for path in found:
            file_class = _file_class(path)
            if file_class is None:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-PREFIX",
                        f"filename must start with {HLR_PREFIX!r} or {LLR_PREFIX!r}",
                        path,
                    )
                )
                continue

            is_duplicate = path.stem in seen_stems
            if is_duplicate:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-DUPID",
                        f"duplicate container stem {path.stem!r} (also {seen_stems[path.stem]})",
                        path,
                    )
                )
            else:
                seen_stems[path.stem] = path

            data, lines, dups = load_yaml(path)
            if isinstance(data, Diagnostic):
                diags.append(data)
                continue
            diags.extend(_duplicate_key_diagnostics(path, lines, dups))

            try:
                file = file_class.load(path, data, lines)
            except ValidationError as exc:
                diags.extend(_validation_diagnostics(path, exc, lines))
            else:
                (duplicates if is_duplicate else files).append(file)

        return cls(files, duplicates), diags

    def __iter__(self) -> Iterator[RequirementFile]:
        return iter(self.by_stem.values())

    def statement(self, req_id: str) -> tuple[RequirementFile, Statement] | None:
        """Resolve a '<stem>.<number>' statement ID to its (file, statement)."""
        if (parsed := parse_req_id(req_id)) is None:
            return None
        stem, number = parsed
        if (file := self.by_stem.get(stem)) is None:
            return None
        if (statement := file.description.get(number)) is None:
            return None
        return file, statement

    def all_statements(self) -> Iterator[tuple[str, Statement]]:
        """Yield every resolvable statement of the set as (full ID, statement), in file order."""
        for file in self:
            for number, statement in file.description.items():
                yield f"{file.stem}.{number}", statement

    def loc_of(
        self, req_id: str, *, sub_key: SubKey | None = None
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line number and YAML key path of the specified statement.

        Raises `KeyError` if `req_id` is not present.
        """
        if (parsed := parse_req_id(req_id)) is None:
            raise KeyError(req_id)
        stem, number = parsed
        if (file := self.by_stem.get(stem)) is None or number not in file.description:
            raise KeyError(req_id)
        return file.loc_of(number, sub_key=sub_key)


def _duplicate_key_diagnostics(path: Path, lines: YAMLLineMap, dups: list[str]) -> list[Diagnostic]:
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


def _validation_diagnostics(
    path: Path, exc: ValidationError, lines: YAMLLineMap
) -> list[Diagnostic]:
    out: list[Diagnostic] = []
    for err in exc.errors(include_url=False):
        key_path = tuple(str(p) for p in err["loc"])
        out.append(
            Diagnostic(
                "error",
                "E-DESCKEY" if err["type"] == "desckey" else "E-SCHEMA",
                err["msg"],
                path,
                line=_nearest_line(lines, key_path),
                path=key_path,
            )
        )
    return out


def _nearest_line(lines: YAMLLineMap, loc: tuple[str, ...]) -> int | None:
    """Source line of the longest known prefix of `loc`."""
    for n in range(len(loc), 0, -1):
        if (line := lines.get(loc[:n])) is not None:
            return line
    return None
