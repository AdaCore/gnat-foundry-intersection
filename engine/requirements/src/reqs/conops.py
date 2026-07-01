"""
Parse CONOPS leaves for traceability.

The CONOPS is free Markdown; each operational-concept *leaf* is a bullet of the
form ``- **<section>.<leaf> <marker>** ...`` (e.g. ``- **5.1 ◆** ...``). Every
such bullet is a decision the system has committed to -- whether a MUTCD Standard
(``✔``), Guidance (``◇``), or a project scoping decision (``◆``) -- so the trace
check treats each leaf as a node an HLR must cover (or a waiver must excuse).

Only the leaf id is needed here; the marker and prose are the human's concern.
"""

from __future__ import annotations

from pathlib import Path

from reqs.core import LEAF_RE


def parse_leaves(path: Path) -> dict[str, int]:
    """
    Map each CONOPS leaf id (``"<n>.<m>"``) to its 1-based source line.

    Non-leaf lines (headings, prose, non-leaf bullets) are ignored. A leaf id
    that somehow appears twice keeps its first line.
    """
    leaves: dict[str, int] = {}
    text = Path(path).read_text(encoding="utf-8")
    for lineno, line in enumerate(text.splitlines(), start=1):
        m = LEAF_RE.match(line)
        if m and m.group(1) not in leaves:
            leaves[m.group(1)] = lineno
    return leaves
