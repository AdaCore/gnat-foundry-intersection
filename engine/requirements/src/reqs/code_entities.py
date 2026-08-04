"""
The declared entities of a project, as a trace layer.

This is the CODE layer, and it runs the opposite way round from every other one.
Elsewhere the lower node cites its parent -- an HLR names its CONOPS leaf, a test
names the LLR it verifies. Code names nothing: it is the *LLR* that says what
implements it, via ``implemented_by``. So this set only has to answer "is there
such an entity?" and the refs are read from the layer above (see
``reqs.checks.trace``, ``refs_point_down``).

A node is one declared name -- a subprogram, type, subtype, constant, variable
or exception -- keyed by its fully qualified name as the source writes it.
Matching is textual and case-insensitive, which is what Ada's own rules imply;
it is *not* name resolution, so a renaming or a use-clause is not followed. That
is adequate for the refs at hand and is what lets the inventory be produced
without a fully resolvable project.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar

if TYPE_CHECKING:
    from collections.abc import Iterator

    from reqs.code_inventory import Inventory
    from reqs.core import SubKey


@dataclass(frozen=True)
class CodeNode:
    """One declared entity: the Ada analogue of a requirement ``Statement``."""

    path: Path  # the Ada source, relative to the analysed project's directory
    line: int  # 1-based source line of the declaration
    kind: str  # "procedure", "function", "type", "constant", ... -- for reporting

    # The Statement trace surface (see reqs.document). Code carries no trace refs
    # in either direction: the requirement names the code, not the reverse, and
    # the code is the bottom of the chain.
    up_refs: ClassVar[None] = None
    down_refs: ClassVar[None] = None
    is_derived: ClassVar[bool] = False


class CodeSet:
    """The entities of a code inventory, queryable like a ``RequirementSet``."""

    path: Path
    nodes: dict[str, CodeNode]

    def __init__(self, path: Path, nodes: dict[str, CodeNode]) -> None:
        self.path = path
        self.nodes = nodes
        self._folded = {node_id.lower(): node_id for node_id in nodes}

    @classmethod
    def from_inventory(cls, inventory: Inventory, path: Path) -> CodeSet:
        """
        Index every declared name in `inventory` by its qualified name.

        A name declared more than once -- a spec declaration and its body, two
        overloads, a forward declaration in a package body -- keeps its first
        occurrence, which is the spec where there is one. An ``implemented_by``
        ref names an entity, not a profile, so collapsing overloads is what the
        refs mean.
        """
        nodes: dict[str, CodeNode] = {}
        for sub in inventory.all_subprograms():
            nodes.setdefault(
                sub.qualified_name,
                CodeNode(Path(sub.location.file), sub.location.line, sub.kind),
            )
        for entity in inventory.all_entities():
            nodes.setdefault(
                entity.qualified_name,
                CodeNode(Path(entity.location.file), entity.location.line, entity.kind),
            )
        return cls(path, nodes)

    def all_statements(self) -> Iterator[tuple[str, CodeNode]]:
        """Yield every entity as (qualified name, node), in discovery order."""
        yield from self.nodes.items()

    def statement(self, node_id: str) -> CodeNode | None:
        """Resolve a qualified name to its node, case-insensitively; None if absent."""
        if (canonical := self._folded.get(node_id.lower())) is None:
            return None
        return self.nodes[canonical]

    def canonical(self, node_id: str) -> str | None:
        """
        Return the name as the source spells it, for a ref that may differ in case.

        The trace engine reports and tabulates by node id, so a ref written
        ``States.T_WALK`` has to be reported against the one node
        ``States.T_Walk`` rather than creating a second.
        """
        return self._folded.get(node_id.lower())

    def loc_of(
        self,
        node_id: str,
        *,
        sub_key: SubKey | None = None,  # noqa: ARG002  # For signature parity with RequirementSet
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line and (empty) key path of the specified entity.

        Ada declarations have no key path, and no sub-location either: an entity
        cites nothing, so every `sub_key` resolves to the declaration. Raises
        `KeyError` if `node_id` is not present.
        """
        node = self.nodes[node_id]
        return node.path, node.line, ()
