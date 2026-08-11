"""Small text helpers for the MyST emitters: escaping and counting."""

from __future__ import annotations

import re

# Backslash first: escaping it later would double the escapes just added.
_SPECIALS = ("\\", "`", "{")


def inline(text: str) -> str:
    """Neutralize free text for inline MyST: escape span/role openers, collapse whitespace."""
    for char in _SPECIALS:
        text = text.replace(char, "\\" + char)
    return " ".join(text.split())


def code_span(text: str) -> str:
    """
    Render text as an inline code span, delimited past any backtick run in it.

    Backslash escapes do not work inside code spans, so `inline` cannot make
    a backtick-carrying value safe there; a longer delimiter (plus CommonMark's
    space padding for edge backticks) can.
    """
    text = " ".join(text.split())
    delim = "`" * (max((len(run) for run in re.findall(r"`+", text)), default=0) + 1)
    pad = " " if text.startswith("`") or text.endswith("`") or not text else ""
    return f"{delim}{pad}{text}{pad}{delim}"


def count(n: int, noun: str) -> str:
    """Render a count with its naively pluralized noun ("1 error", "2 errors")."""
    return f"{n} {noun}" + ("" if n == 1 else "s")
