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
  E-DUPID       : RS.2 - container stems are not unique across the set

A file that fails validation is reported and left out of the set. Additional
schema rules that do not need to be enforced to load a type-valid
``RequirementSet`` live in ``reqs.checks.schema``.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar, Literal

from pydantic import BaseModel, ValidationError

from reqs.core import Diagnostic, YAMLLineMap, iter_yaml_files, load_yaml
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


class LlrFile(_BaseFile, LlrDocument):
    """An LLR document plus where it came from."""

    level: ClassVar[Literal["llr"]] = "llr"

    @classmethod
    def load(cls, path: Path, data: dict[str, object], lines: YAMLLineMap) -> LlrFile:
        """Validate `data` as an LLR document (may raise) and attach provenance."""
        document = LlrDocument.model_validate(data)
        return cls.model_construct(path=path, lines=lines, **dict(document))


RequirementFile = HlrFile | LlrFile


def _file_class(path: Path) -> type[RequirementFile] | None:
    """Return the file type a path loads as (by filename prefix); None = E-PREFIX."""
    if path.name.startswith(HLR_PREFIX):
        return HlrFile
    if path.name.startswith(LLR_PREFIX):
        return LlrFile
    return None


class RequirementSet:
    """A validated requirement set, queryable by container stem or statement ID."""

    files: tuple[RequirementFile, ...]
    _by_stem: dict[str, RequirementFile]

    def __init__(self, files: Iterable[RequirementFile]) -> None:
        self.files = tuple(files)
        # Reversed, so a stem's *first* file wins: E-DUPID reports every file
        # after it, and IDs resolve into the one file not reported.
        self._by_stem = {file.stem: file for file in reversed(self.files)}

    @classmethod
    def load(
        cls, paths: Iterable[str | os.PathLike[str]]
    ) -> tuple[RequirementSet, list[Diagnostic]]:
        """Validate and load requirement files, collecting diagnostics for the rest."""
        found, diags = iter_yaml_files(paths)
        files: list[RequirementFile] = []
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

            if path.stem in seen_stems:
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
                files.append(file_class.load(path, data, lines))
            except ValidationError as exc:
                diags.extend(_validation_diagnostics(path, exc, lines))

        return cls(files), diags

    def __iter__(self) -> Iterator[RequirementFile]:
        return iter(self.files)

    def file(self, stem: str) -> RequirementFile | None:
        return self._by_stem.get(stem)

    def statement(self, req_id: str) -> tuple[RequirementFile, Statement] | None:
        """Resolve a '<stem>.<number>' statement ID to its (file, statement)."""
        if (parsed := parse_req_id(req_id)) is None:
            return None
        stem, number = parsed
        if (file := self._by_stem.get(stem)) is None:
            return None
        if (statement := file.description.get(number)) is None:
            return None
        return file, statement


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
