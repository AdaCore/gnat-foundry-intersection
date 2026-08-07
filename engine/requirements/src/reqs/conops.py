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

from dataclasses import dataclass
from typing import TYPE_CHECKING, ClassVar

from reqs.core import LEAF_RE

if TYPE_CHECKING:
    from collections.abc import Iterator
    from pathlib import Path

    from reqs.core import SubKey


@dataclass(frozen=True)
class Leaf:
    """One CONOPS leaf: the markdown analogue of a requirement ``Statement``."""

    line: int  # 1-based source line of the leaf bullet

    # The Statement trace surface (see reqs.document). A leaf carries no upward
    # trace of its own: the CONOPS sits at the top of the chain, and it names
    # nothing below it either -- that is the HLR's job.
    up_refs: ClassVar[None] = None
    is_derived: ClassVar[bool] = False
    verification_methods: ClassVar[tuple[str, ...]] = ()

    def down_refs_in(self, field: str | None) -> list[str] | None:  # noqa: ARG002
        """Nothing: a leaf names nothing below it."""
        return None


class ConopsSet:
    """The leaves of one CONOPS document, queryable like a ``RequirementSet``."""

    path: Path
    leaves: dict[str, Leaf]

    def __init__(self, path: Path, leaves: dict[str, Leaf]) -> None:
        self.path = path
        self.leaves = leaves

    @classmethod
    def load(cls, path: Path) -> ConopsSet:
        """
        Parse the leaf bullets of the CONOPS document at `path`.

        Non-leaf lines (headings, prose, non-leaf bullets) are ignored. A leaf
        id that somehow appears twice keeps its first line.
        """
        leaves: dict[str, Leaf] = {}
        text = path.read_text(encoding="utf-8")
        for lineno, line in enumerate(text.splitlines(), start=1):
            m = LEAF_RE.match(line)
            if m and m.group(1) not in leaves:
                leaves[m.group(1)] = Leaf(lineno)
        return cls(path, leaves)

    def all_statements(self) -> Iterator[tuple[str, Leaf]]:
        """Yield every leaf as (leaf id, leaf), in document order."""
        yield from self.leaves.items()

    def statement(self, leaf_id: str) -> Leaf | None:
        """Resolve a ``"<n>.<m>"`` leaf id to its leaf; None if absent."""
        return self.leaves.get(leaf_id)

    def loc_of(
        self,
        leaf_id: str,
        *,
        sub_key: SubKey | None = None,  # noqa: ARG002  # For signature parity with RequirementSet
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line number and key path of the specified leaf.

        Markdown has no key paths, so the third element is always empty. Raises
        `KeyError` if `leaf_id` is not present.
        """
        return self.path, self.leaves[leaf_id].line, ()
