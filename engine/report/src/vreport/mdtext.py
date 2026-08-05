"""Escaping for evidence-carried free text interpolated into MyST markup."""

from __future__ import annotations

# Backslash first: escaping it later would double the escapes just added.
_SPECIALS = ("\\", "`", "{")


def inline(text: str) -> str:
    """Neutralize free text for inline MyST: escape span/role openers, collapse whitespace."""
    for char in _SPECIALS:
        text = text.replace(char, "\\" + char)
    return " ".join(text.split())
