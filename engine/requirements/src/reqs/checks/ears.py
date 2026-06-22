"""
Lint requirement `description` statements against the EARS grammar.

EARS (see ``docs/ears.md``) constrains a requirement to a small set of patterns
whose clauses always appear in the same order::

    [While <precondition>,] [When <trigger>,] the <system> shall <response>
    If <trigger>, then the <system> shall <response>          (unwanted behavior)

This is a closed grammar with fixed keywords and ordering, so it is checkable
with regular expressions -- no model required. Each statement is classified; a
statement matching no pattern is reported with the most specific diagnosis:

  E-EARS-NOSHALL  : statement contains no "shall"
  E-EARS-COMMA    : a While/When clause is not terminated by a comma
  E-EARS-IFTHEN   : an `If` statement is missing its `then`
  E-EARS-CASE     : a leading EARS keyword is not capitalized (while/when/if)
  E-EARS-PATTERN  : matches no EARS pattern (e.g. bad clause order / no
                    "the <system> shall <response>" core)

`shall`-count is intentionally NOT checked here -- that is RS.3, enforced by the
schema check (W-RS3). Statements deliberately outside EARS (rare) can opt out
with the token ``ears:skip``.
"""

from __future__ import annotations

import re

from reqs.core import (
    SHALL_RE,
    Diagnostic,
    iter_yaml_files,
    load_yaml,
    prose,
)

EARS_OPTOUT = "ears:skip"

# EARS patterns, most specific first so the reported classification is accurate.
# All are anchored at the start of the (normalized) statement.
_PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("complex-event", re.compile(r"^While\b.+?,\s+[Ww]hen\b.+?,\s+.*?\bshall\b.+", re.S)),
    ("complex-unwanted", re.compile(r"^While\b.+?,\s+[Ii]f\b.+?,\s+then\b.+?\bshall\b.+", re.S)),
    ("state-driven", re.compile(r"^While\b.+?,\s+.*?\bshall\b.+", re.S)),
    ("event-driven", re.compile(r"^When\b.+?,\s+.*?\bshall\b.+", re.S)),
    ("unwanted", re.compile(r"^If\b.+?,\s+then\b.+?\bshall\b.+", re.S)),
    ("ubiquitous", re.compile(r"^The\b.*?\bshall\b.+", re.S)),
]


def classify(prose: str) -> str | None:
    for name, pat in _PATTERNS:
        if pat.match(prose):
            return name
    return None


def diagnose(prose: str) -> tuple[str, str]:
    """Return (code, message) for a statement that matched no EARS pattern."""
    if not SHALL_RE.search(prose):
        return "E-EARS-NOSHALL", 'statement contains no "shall"'
    lead = prose.split(" ", 1)[0].rstrip(",")
    if lead.lower() in ("while", "when", "if") and lead[0].islower():
        return "E-EARS-CASE", f'EARS keyword "{lead}" must be capitalized'
    if lead in ("While", "When"):
        return "E-EARS-COMMA", f'"{lead}" clause must be terminated by a comma before "shall"'
    if lead == "If":
        return "E-EARS-IFTHEN", 'an "If" statement must use "If <trigger>, then ... shall ..."'
    return (
        "E-EARS-PATTERN",
        "does not match any EARS pattern (ubiquitous / While / When / If-then); "
        'expected "the <system> shall <response>" with clauses in order',
    )


class EarsChecker:
    """Classify every `description` statement against the EARS grammar."""

    def check(self, paths) -> list[Diagnostic]:
        diags: list[Diagnostic] = []
        for path in iter_yaml_files(paths):
            data, lines, _dups, error = load_yaml(path)
            if error is not None:
                diags.append(error)
                continue
            desc = data.get("description")
            if not isinstance(desc, dict):
                continue  # structural problems are the schema check's job

            for key, statement in desc.items():
                if not isinstance(statement, str) or EARS_OPTOUT in statement:
                    continue
                text = prose(statement)
                if text and classify(text) is None:
                    code, msg = diagnose(text)
                    diags.append(
                        Diagnostic(
                            "error",
                            code,
                            msg,
                            path,
                            line=lines.get(("description", str(key))),
                            path=("description", str(key)),
                        )
                    )
        return diags


def lint_paths(paths) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests)."""
    return EarsChecker().check(paths)
