"""
Schema + structural validation of requirement YAML files.

File level is chosen by filename prefix: ``hlr_`` -> high-level, ``llr_`` -> low-level.

A requirement's ID is ``<stem>.<number>`` (see docs/README.md): the file's stem
identifies the *container*, the ``description`` key identifies the statement.

Checks:
    - E-DUPID : container stems are not unique across the set
    - E-PREFIX : filename has neither level prefix
    - E-IO / E-YAML : unreadable / unparsable file (from ``reqs.core.load_yaml``)
    - E-SCHEMA : structure or types do not match the document schema (see
      ``reqs.document``)
    - E-DESCKEY : description keys are not contiguous from 1
    - E-DESCKEY-DUP : a statement number is repeated within a file
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

from typing import TYPE_CHECKING

from reqs.core import SHALL_RE, Diagnostic, prose
from reqs.requirement_set import LlrFile, RequirementFile, RequirementSet, parse_req_id

if TYPE_CHECKING:
    import os
    from collections.abc import Iterable
    from pathlib import Path

RS3_OPTOUT = "rs3:skip"


def _count_shall(statement: str) -> int:
    return len(SHALL_RE.findall(prose(statement)))


class RequirementChecker:
    """Schema + structural + RS.3 checks over a set of requirement files."""

    def __init__(self, *, complete: bool = False) -> None:
        self.complete = complete

    def check(self, paths: Iterable[str | os.PathLike[str]]) -> list[Diagnostic]:
        reqset, diags = RequirementSet.load(paths)
        # Files with duplicate stems still deserve diagnostics.
        for file in (*reqset, *reqset.duplicates):
            diags.extend(self._rs3_lint(file))
        diags.extend(self._referential_integrity(reqset))
        return diags

    def _rs3_lint(self, file: RequirementFile) -> list[Diagnostic]:
        out: list[Diagnostic] = []
        for key, statement in file.description.items():
            if RS3_OPTOUT in statement.text:
                continue
            n = _count_shall(statement.text)
            if n != 1:
                _path, line, loc = file.loc_of(key, sub_key="text")
                out.append(
                    Diagnostic(
                        "warning",
                        "W-RS3",
                        f'statement {key} should contain exactly one "shall" (found {n}); '
                        f"add {RS3_OPTOUT!r} to opt out",
                        file.path,
                        line=line,
                        path=loc,
                    )
                )
        return out

    def _referential_integrity(self, reqset: RequirementSet) -> list[Diagnostic]:
        out: list[Diagnostic] = []
        for file in (*reqset, *reqset.duplicates):
            if not isinstance(file, LlrFile):
                continue
            for key, statement in file.description.items():
                _path, line, loc = file.loc_of(key, sub_key="up_ref")
                for parent_id in statement.parent_req:
                    diag = self._parent_diagnostic(reqset, parent_id, file.path, line, loc)
                    if diag is not None:
                        out.append(diag)
        return out

    def _parent_diagnostic(
        self,
        reqset: RequirementSet,
        parent_id: str,
        path: Path,
        line: int,
        loc: tuple[str, ...],
    ) -> Diagnostic | None:
        """Check one parent_req entry; return its Diagnostic, or None if it resolves to an HLR."""
        if (parsed := parse_req_id(parent_id)) is None:
            return Diagnostic(
                "error",
                "E-PARENT-FORMAT",
                f"parent_req {parent_id!r} must be a '<stem>.<number>' "
                "statement ID, not a bare container stem",
                path,
                line=line,
                path=loc,
            )
        parent_stem = parsed[0]
        resolved = reqset.statement(parent_id)
        if resolved is None:
            detail = (
                f"no statement {parent_id!r} in {parent_stem!r}"
                if parent_stem in reqset.by_stem
                else f"no requirement container {parent_stem!r} in the set"
            )
            return Diagnostic(
                "error" if self.complete else "warning",
                "E-PARENT-MISSING" if self.complete else "W-PARENT-MISSING",
                f"parent_req {parent_id!r} resolves to nothing ({detail})"
                + ("" if self.complete else " (use --complete to require resolution)"),
                path,
                line=line,
                path=loc,
            )
        target_file, _statement = resolved
        if target_file.level != "hlr":
            return Diagnostic(
                "error",
                "E-PARENT-TYPE",
                f"parent_req {parent_id!r} must reference an HLR statement; "
                f"its container {parent_stem!r} is an {target_file.level.upper()}",
                path,
                line=line,
                path=loc,
            )
        return None


def validate_paths(
    paths: Iterable[str | os.PathLike[str]], *, complete: bool = False
) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests)."""
    return RequirementChecker(complete=complete).check(paths)
