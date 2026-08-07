"""
Read the source's `--@covers`-tagged checks out of a code inventory.

A `pragma Compile_Time_Error`, a `Post =>` contract or a `No_Return` aspect
verifies a requirement the same way a test does: it is evidence in the
artifact, so it cites the statement it discharges from the source, with a
``--@covers`` tag on the line immediately above the construct::

    --@covers llr_1_states.21
    pragma Compile_Time_Error (States.T_Amber /= 3, "llr_1_states.21");

``engine/ada_tracer`` anchors the tag to the parsed construct (see its
``checks`` array): a comment that precedes no pragma or aspect is not
evidence, and deleting the construct deletes the citation with it. Tagging is
*opt-in*, unlike test routines: most contracts exist for engineering and
proof-plumbing reasons and cite nothing, so an untagged check is simply not a
node here -- there is no UNTRACED analogue. The completeness pressure comes
from the statement side: an LLR declaring ``proof`` / ``static_check`` with no
citing check is E-TRACE-UNCOVERED.

Which constructs count for which layer is the chain's decision, not this
module's: a layer's ``anchors`` lists the accepted anchor shapes (``pragma``,
``aspect:Post``, ...), so `PROOF` reads contract aspects and `STATIC` reads
pragmas plus the compiler-checked aspects the project relies on.

Each tagged check is one trace node, id ``<file>:<line>``, its up-refs the ids
it covers. The payload grammar is the test one (:mod:`reqs.ada_tests`),
including ``none: <reason>`` -- useful for a check that guards something out
of requirement scope.

One diagnostic of its own -- E-CHECK-DUPID, two inventory entries claiming one
``<file>:<line>`` id; the trace engine adds E-TRACE-CHECK-IGNORED for a tagged
check that no ada-checks layer's anchors accept and E-TRACE-CHECK-EMPTY for one
whose payload cites nothing at all. The two are reported independently of each
other -- a bare ``--@covers`` is a broken tag wherever it sits, and reporting it
only when its construct happens to be an accepted anchor would let the typo
vanish on every other construct.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, ClassVar

from reqs.ada_tests import _parse_covers
from reqs.core import Diagnostic

if TYPE_CHECKING:
    from collections.abc import Iterator

    from reqs.code_inventory import Check, Inventory
    from reqs.core import SubKey


def _matches(anchor: str, check: Check) -> bool:
    """Whether an anchor spec (`pragma`, `aspect:Post`, ...) accepts a check."""
    kind, _, name = anchor.partition(":")
    if kind != check.kind:
        return False
    # Ada names are case-insensitive; an empty name accepts every one.
    return not name or name.casefold() == check.name.casefold()


@dataclass
class CheckNode:
    """One tagged check: the source-side analogue of a test routine."""

    path: Path  # the Ada source, relative to the analysed project's directory
    line: int  # 1-based source line of the pragma / aspect association
    kind: str  # "pragma" | "aspect" -- for reporting
    name: str  # the pragma name or aspect mark, as written
    refs: list[str] = field(default_factory=list)  # covered requirement ids
    derived: bool = False  # tagged `--@covers none`

    verification_methods: ClassVar[tuple[str, ...]] = ()

    @property
    def up_refs(self) -> list[str]:
        """The requirement ids this check covers (the ``Statement`` trace surface)."""
        return self.refs

    def down_refs_in(self, field: str | None) -> list[str] | None:  # noqa: ARG002
        """Nothing: a check is the bottom of the chain and names nothing below it."""
        return None

    @property
    def is_derived(self) -> bool:
        """Whether the check is tagged ``none`` (guards code no requirement governs)."""
        return self.derived and not self.refs


def _cites_nothing(payload: str) -> bool:
    """Whether a ``--@covers`` payload names no id and does not say ``none``."""
    refs, derived = _parse_covers(payload)
    return not refs and not derived


def _node_of(check: Check) -> CheckNode:
    """Build a trace node from a check's inventory entry."""
    node = CheckNode(Path(check.location.file), check.location.line, check.kind, check.name)
    for payload in check.covers:
        refs, derived = _parse_covers(payload)
        node.refs.extend(refs)
        node.derived = node.derived or derived
    return node


class CheckSet:
    """The tagged checks of a code inventory, queryable like a ``RequirementSet``."""

    path: Path
    nodes: dict[str, CheckNode]
    checks: list[Check]  # every tagged check of the inventory, unfiltered

    def __init__(self, path: Path, nodes: dict[str, CheckNode], checks: list[Check]) -> None:
        self.path = path
        self.nodes = nodes
        self.checks = checks

    @classmethod
    def from_inventory(
        cls, inventory: Inventory, path: Path, anchors: list[str]
    ) -> tuple[CheckSet, list[Diagnostic]]:
        """
        Turn every tagged check matching one of `anchors` into a trace node.

        The ``<file>:<line>`` id is unique from any real tracer run; a
        collision (a malformed inventory) would silently drop citations, so
        it is reported instead.
        """
        nodes: dict[str, CheckNode] = {}
        diags: list[Diagnostic] = []
        for check in inventory.checks:
            if not any(_matches(anchor, check) for anchor in anchors):
                continue
            node_id = f"{check.location.file}:{check.location.line}"
            if node_id in nodes:
                diags.append(
                    Diagnostic(
                        "error",
                        "E-CHECK-DUPID",
                        f"check node id {node_id!r} is claimed by two entries; one "
                        f"construct's citations would be silently dropped -- the "
                        f"inventory is malformed, regenerate it",
                        path,
                    )
                )
                continue
            nodes[node_id] = _node_of(check)
        return cls(path, nodes, list(inventory.checks)), diags

    def unmatched(self, anchors: list[str]) -> list[Check]:
        """Return the tagged checks (with real refs) that `anchors` accept none of."""
        return [
            check
            for check in self.checks
            if _node_of(check).refs and not any(_matches(anchor, check) for anchor in anchors)
        ]

    def malformed(self) -> list[Check]:
        """
        Return the tagged checks carrying a ``--@covers`` payload citing nothing.

        Anchor-independent, unlike :meth:`unmatched`: a payload that parses to no
        id and does not say ``none`` discharges nothing on any construct, and an
        accepted anchor is precisely what its author thought they had. Were this
        keyed on anchors too, a bare ``--@covers`` on an unaccepted construct
        would be reported by neither check and disappear.
        """
        return [check for check in self.checks if any(map(_cites_nothing, check.covers))]

    def all_statements(self) -> Iterator[tuple[str, CheckNode]]:
        """Yield every check node as (node id, node), in inventory order."""
        yield from self.nodes.items()

    def statement(self, node_id: str) -> CheckNode | None:
        """Resolve a node id to its check node; None if absent."""
        return self.nodes.get(node_id)

    def loc_of(
        self,
        node_id: str,
        *,
        sub_key: SubKey | None = None,  # noqa: ARG002  # the tag sits on the construct
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line and (empty) key path of the specified check.

        Raises `KeyError` if `node_id` is absent.
        """
        node = self.nodes[node_id]
        return node.path, node.line, ()
