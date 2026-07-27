"""
Read the test suite's requirement trace tags out of a code inventory.

The bottom of the trace chain is the test suite: every LLR that is verified by
test should be reachable from a test, and -- more importantly -- every test
should declare *what it verifies*, so a requirement that drifts out from under
its test is caught mechanically.

A test routine declares its trace with a ``--@covers`` tag placed in its
(editable) body::

    procedure Test_Compatible (Gnattest_T : in out Test) is
    begin
       --@covers llr_3_conflicts.1
       ...

The ids are whitespace- and/or comma-separated and may span several tags; they
are unioned. A test that intentionally verifies code no requirement governs
(a boundary/robustness test -- e.g. HAL rendering, which ``llr_6_hal`` places
"out of requirement scope") says so explicitly, which is the test-side analogue
of a ``derived`` requirement::

       --@covers none: display rendering is out of requirement scope (llr_6_hal)

The Ada itself is not parsed here. ``engine/ada_tracer`` does that and reports
each body's interior comments with their tags already split out (see
:mod:`reqs.code_inventory`); what is left for this module is the *tag payload*,
which is this repository's convention rather than anything about Ada.

Each *test routine* is one trace node. Its id is ``<unit>.<routine>`` (the unit
is the file-name stem up to the first ``-``, matching the GNATtest
``<unit>-test_data-tests.adb`` convention), its up-refs are the ids it covers,
and it is ``derived`` when tagged ``none``. The resulting :class:`TestSet` is
queryable exactly like a :class:`~reqs.conops.ConopsSet` /
:class:`~reqs.requirement_set.RequirementSet`, so the level-agnostic trace
engine treats the tests as the chain's bottom layer (LLR -> TEST) with no
special-casing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Iterator

    from reqs.code_inventory import Inventory, Subprogram
    from reqs.core import SubKey

# A GNATtest test routine is named `Test_<subprogram>`.
ROUTINE_RE = re.compile(r"^Test_\w+$")

# `none` (optionally followed by a reason after `:`/`-`/em-dash) marks the node
# derived: it verifies code no requirement governs.
NONE_RE = re.compile(r"^\s*none\b[\s:\-\u2014]*", re.IGNORECASE)

COVERS_TAG = "covers"

# The profile GNATtest gives every test routine. Checked so that a helper named
# `Test_Something` sitting in a test package is not mistaken for a test -- the
# regex this module used to apply to the source text made the same check.
GNATTEST_FORMAL = ("Gnattest_T", "in out", "Test")


@dataclass
class TestNode:
    """One test routine: the Ada analogue of a requirement ``Statement``."""

    path: Path  # the Ada source, relative to the analysed project's directory
    line: int  # 1-based source line of the `procedure Test_... is` body
    ref_line: int  # source line the up-refs are anchored to (first tag, else the body)
    refs: list[str] = field(default_factory=list)  # covered requirement ids
    derived: bool = False  # tagged `--@covers none` -- verifies un-required code

    @property
    def up_refs(self) -> list[str]:
        """The requirement ids this test covers (the ``Statement`` trace surface)."""
        return self.refs

    @property
    def down_refs(self) -> None:
        """Nothing: a test is the bottom of the chain and names nothing below it."""
        return None

    @property
    def is_derived(self) -> bool:
        """Whether the test is tagged ``none`` (verifies code no requirement governs)."""
        return self.derived and not self.refs


def _parse_covers(body: str) -> tuple[list[str], bool]:
    """Split a ``--@covers`` payload into (ids, derived); ``none`` sets derived."""
    if NONE_RE.match(body):
        return [], True
    return [tok for tok in re.split(r"[,\s]+", body.strip()) if tok], False


def _is_test_routine(sub: Subprogram) -> bool:
    """Whether an inventory entry is a GNATtest test routine's body."""
    # A routine appears three times -- forward declaration, `renames` alias and
    # body -- and only the body can host a `--@covers` tag, the read-only
    # regions around it being regenerated.
    if not sub.is_body or sub.is_renaming:
        return False
    if ROUTINE_RE.match(sub.name) is None:
        return False
    return [(p.name, p.mode, p.type) for p in sub.parameters] == [GNATTEST_FORMAL]


def _node_of(sub: Subprogram) -> TestNode:
    """Build a trace node from a test routine's inventory entry."""
    node = TestNode(Path(sub.location.file), sub.location.line, sub.location.line)
    for block in sub.body_comments:
        for tag in block.tags:
            if tag.tag != COVERS_TAG:
                continue
            if not node.refs and not node.derived:
                node.ref_line = tag.line
            refs, derived = _parse_covers(tag.text)
            node.refs.extend(refs)
            node.derived = node.derived or derived
    return node


class TestSet:
    """The test routines of a code inventory, queryable like a ``RequirementSet``."""

    path: Path
    nodes: dict[str, TestNode]

    def __init__(self, path: Path, nodes: dict[str, TestNode]) -> None:
        self.path = path
        self.nodes = nodes

    @classmethod
    def from_inventory(cls, inventory: Inventory, path: Path) -> TestSet:
        """
        Turn every GNATtest routine body in `inventory` into a trace node.

        A node's id stem is its *file*'s unit (the stem up to the first ``-``)
        rather than its Ada package name, which keeps the ids what they have
        always been -- they appear in ``make trace`` output. A routine that
        recurs across files keeps its first occurrence.
        """
        nodes: dict[str, TestNode] = {}
        for sub in inventory.all_subprograms():
            if not _is_test_routine(sub):
                continue
            unit = Path(sub.location.file).stem.split("-", 1)[0]
            nodes.setdefault(f"{unit}.{sub.name}", _node_of(sub))
        return cls(path, nodes)

    def all_statements(self) -> Iterator[tuple[str, TestNode]]:
        """Yield every test node as (node id, node), in discovery order."""
        yield from self.nodes.items()

    def statement(self, node_id: str) -> TestNode | None:
        """Resolve a node id to its test node; None if absent."""
        return self.nodes.get(node_id)

    def loc_of(
        self,
        node_id: str,
        *,
        sub_key: SubKey | None = None,
    ) -> tuple[Path, int, tuple[str, ...]]:
        """
        Return file path, line and (empty) key path of the specified test node.

        An ``up_ref`` location points at the node's first ``--@covers`` tag;
        otherwise at the routine. Raises `KeyError` if `node_id` is absent.
        """
        node = self.nodes[node_id]
        line = node.ref_line if sub_key == "up_ref" else node.line
        return node.path, line, ()
