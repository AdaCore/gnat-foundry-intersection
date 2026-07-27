"""
Level-agnostic traceability.

A trace *chain* is an ordered list of :class:`Layer`s, top (most abstract) to
bottom -- e.g. CONOPS -> HLR -> LLR -> code/test. Each layer traces to its
``parent``, which defaults to the entry above it, so the list reads as a chain
but is really a tree: both TEST and CODE hang off LLR, because a test cites the
LLR it verifies and an LLR cites the code that implements it -- neither has
anything to say about the other. The engine runs the same checks over every
(parent, child) pair, in both directions:

  E-TRACE-DANGLING         : a lower node's up-ref resolves to no upper node.
  E-TRACE-UNTRACED         : a lower node has no upward trace and is not derived
                             (in practice this is usually E-SCHEMA, but
                             E-TRACE-UNTRACED can occur if there is an upward
                             trace which doesn't match `id_pattern`).
  {W,E}-TRACE-UNCOVERED    : an upper node that no lower node covers and no
                             waiver excuses (warning; error under --complete).
  E-TRACE-WAIVER-UNKNOWN   : a waiver naming a node that is not in its layer.
  W-TRACE-WAIVER-REDUNDANT : a waiver naming a node the layer below covers.

  E-TRACE-PARENT           : a layer names a ``parent`` that is not in the chain.
  E-INVENTORY-*            : the code inventory a layer reads is missing, stale
                             or malformed (see :mod:`reqs.code_inventory`).

Nothing here is CONOPS- or HLR-specific. A :class:`Layer` says how to enumerate
its nodes (``kind``: ``markdown-leaves``, ``requirement-yaml``, ``ada-tests`` or
``ada-entities``) and, for any layer that traces upward, how to extract a
parent-node id from each ref (``id_pattern``, one capture group).

One layer kind traces the other way. Code cites nothing -- it is the LLR that
names what implements it -- so a layer may set ``refs_point_down``, and the
engine then reads the refs from the *parent's* nodes (an LLR's
``implemented_by``) and resolves them against this layer's. The checks keep their
meaning under the flip: a ref that resolves to nothing is still E-TRACE-DANGLING,
reported against whichever node wrote it, which is now the parent.

A layer may set ``partial_coverage`` when it covers the layer above only in part
by design -- e.g. tests, since many requirements are discharged by proof rather
than test. The upper layer's uncovered nodes are then shown (table) but never
flagged, even under ``--complete``; the upward checks (dangling/untraced) still
apply, so every test must still declare what it verifies.

A node is "accounted for" (not reported UNCOVERED) when the layer below covers
it OR a waiver excuses it with a reason. A waiver is a reviewed decision that
nothing below realizes the node -- the opposite of a lower node's ``derived``
flag (which lacks a *parent* but is still realized), not its analog: a wrongly
waived node silently drops a real obligation. The waiver file lists such nodes
so the source Markdown / YAML stays free of tags::

    waivers:
      - leaf: "1.1"
        reason: Physical site assumption; not a controller behavior.
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass, field
from io import StringIO
from itertools import pairwise
from pathlib import Path
from typing import TYPE_CHECKING

import yaml
from rich import box
from rich.console import Console
from rich.table import Table

from reqs import code_inventory
from reqs.ada_tests import TestSet
from reqs.code_entities import CodeSet
from reqs.conops import ConopsSet
from reqs.core import Diagnostic
from reqs.requirement_set import RequirementSet

if TYPE_CHECKING:
    import os

    from reqs.core import SubKey

MARKDOWN_LEAVES = "markdown-leaves"
REQUIREMENT_YAML = "requirement-yaml"
ADA_TESTS = "ada-tests"
ADA_ENTITIES = "ada-entities"


@dataclass
class Layer:
    """One layer of the trace chain."""

    name: str
    kind: str
    path: Path
    id_pattern: str | None = None  # regex; group(1) extracts a parent-node id from an up-ref
    waivers: Path | None = None  # nodes here intentionally left uncovered by the layer below
    # The layer this one traces to; None means "the entry above me in the file".
    parent: str | None = None
    # This layer covers the one above it only partially *by design* -- the rest
    # is accounted for elsewhere (e.g. LLRs discharged by proof rather than
    # test). Its parent's uncovered nodes are reported (table) but never flagged,
    # even under --complete; the upward checks (dangling / untraced) still apply.
    partial_coverage: bool = False
    # The refs linking this layer to its parent are written in the *parent* and
    # point down into this one, rather than the other way round. Set for the CODE
    # layer: an entity does not cite the requirement it realizes, the requirement
    # cites it (`implemented_by`).
    refs_point_down: bool = False


def load_chain(path: str | os.PathLike[str]) -> list[Layer]:
    """Load a trace-chain config; layer paths are resolved relative to the file."""
    path = Path(path)
    base = path.parent
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    return [
        Layer(
            name=item["name"],
            kind=item["kind"],
            path=base / item["path"],
            id_pattern=item.get("id_pattern"),
            waivers=(base / item["waivers"]) if item.get("waivers") else None,
            parent=item.get("parent"),
            partial_coverage=bool(item.get("partial_coverage", False)),
            refs_point_down=bool(item.get("refs_point_down", False)),
        )
        for item in data.get("layers", [])
    ]


@dataclass
class _Loaded:
    layer: Layer
    # nodes: coverage targets, up-refs, locations
    reqset: RequirementSet | ConopsSet | TestSet | CodeSet
    waived: dict[str, str]  # node id -> reason
    waiver_file: Path | None


@dataclass
class _Pair:
    upper: _Loaded
    lower: _Loaded
    coverage: dict[str, list[str]] = field(default_factory=dict)  # upper id -> covering lower ids
    resolved: dict[str, list[str]] = field(default_factory=dict)  # lower id -> resolved upper ids
    # Node id -> refs that resolve to nothing. Keyed by whichever layer *wrote*
    # the refs: the lower one normally, the upper one when they point down.
    dangling: dict[str, list[str]] = field(default_factory=dict)
    untraced: list[str] = field(default_factory=list)

    @property
    def refs_point_down(self) -> bool:
        """Whether the refs linking the pair are written in its upper layer."""
        return self.lower.layer.refs_point_down

    @property
    def ref_owner(self) -> _Loaded:
        """The layer whose nodes wrote the refs, and so where a gap is reported."""
        return self.upper if self.refs_point_down else self.lower


class TraceChecker:
    """Run the traceability checks over every adjacent pair of a chain."""

    def __init__(self, layers: list[Layer], *, complete: bool = False) -> None:
        self.layers = layers
        self.complete = complete

    def check(self) -> list[Diagnostic]:
        """Check every (parent, child) pair of the chain; return any diagnostics."""
        diags: list[Diagnostic] = []
        loaded = [self._load(layer, diags) for layer in self.layers]
        pairs = _pairs(loaded, diags)
        if any(d.level == "error" for d in diags):
            return diags  # corpus isn't valid; traceability over it is meaningless
        for upper, lower in pairs:
            diags.extend(self._diagnostics(_analyze(upper, lower)))
        return diags

    def print_tables(self, console: Console | None = None) -> None:
        """Print the coverage / upward-trace tables for every (parent, child) pair."""
        console = console or Console(width=_terminal_width())
        loaded = [self._load(layer, []) for layer in self.layers]
        for upper, lower in _pairs(loaded, []):
            for table in _pair_tables(_analyze(upper, lower)):
                console.print(table)

    # -- loading -------------------------------------------------------------

    def _load(self, layer: Layer, diags: list[Diagnostic]) -> _Loaded:
        waived = self._load_waivers(layer, diags)
        if layer.kind == MARKDOWN_LEAVES:
            return _Loaded(layer, ConopsSet.load(layer.path), waived, layer.waivers)
        if layer.kind == REQUIREMENT_YAML:
            reqset, load_diags = RequirementSet.load([layer.path])
            diags.extend(load_diags)
            return _Loaded(layer, reqset, waived, layer.waivers)
        if layer.kind in (ADA_TESTS, ADA_ENTITIES):
            inventory, load_diags = code_inventory.load(layer.path)
            diags.extend(load_diags)
            nodes = (
                TestSet.from_inventory(inventory, layer.path)
                if layer.kind == ADA_TESTS
                else CodeSet.from_inventory(inventory, layer.path)
            )
            return _Loaded(layer, nodes, waived, layer.waivers)
        diags.append(
            Diagnostic("error", "E-TRACE-KIND", f"unknown layer kind {layer.kind!r}", layer.path)
        )
        return _Loaded(layer, RequirementSet(()), waived, layer.waivers)

    def _load_waivers(self, layer: Layer, diags: list[Diagnostic]) -> dict[str, str]:
        if layer.waivers is None:
            return {}
        try:
            data = yaml.safe_load(layer.waivers.read_text(encoding="utf-8"))
        except OSError as exc:
            diags.append(Diagnostic("error", "E-IO", f"cannot read waivers: {exc}", layer.waivers))
            return {}
        except yaml.YAMLError as exc:
            diags.append(
                Diagnostic("error", "E-YAML", f"waivers parse error: {exc}", layer.waivers)
            )
            return {}
        entries = data.get("waivers") if isinstance(data, dict) else None
        return {
            str(item["leaf"]): str(item.get("reason", ""))
            for item in (entries or [])
            if isinstance(item, dict) and "leaf" in item
        }

    # -- diagnostics ---------------------------------------------------------

    def _diagnostics(self, pair: _Pair) -> list[Diagnostic]:
        up, lo = pair.upper.layer.name, pair.lower.layer.name
        out: list[Diagnostic] = []
        # A dangling ref is reported where it is written, and against the layer it
        # failed to reach -- which the flip exchanges.
        owner, target = (up, lo) if pair.refs_point_down else (lo, up)
        sub_key: SubKey = "down_ref" if pair.refs_point_down else "up_ref"
        direction = "down-ref" if pair.refs_point_down else "up-ref"
        for nid, refs in pair.dangling.items():
            file, line, loc = pair.ref_owner.reqset.loc_of(nid, sub_key=sub_key)
            out.extend(
                Diagnostic(
                    "error",
                    "E-TRACE-DANGLING",
                    f"{owner} {nid!r} {direction} {ref!r} resolves to no {target} node",
                    file,
                    line=line,
                    path=loc,
                )
                for ref in refs
            )
        for nid in pair.untraced:
            file, line, loc = pair.lower.reqset.loc_of(nid, sub_key="up_ref")
            out.append(
                Diagnostic(
                    "error",
                    "E-TRACE-UNTRACED",
                    f"{lo} {nid!r} traces to no {up} node and is not derived",
                    file,
                    line=line,
                    path=loc,
                )
            )
        out.extend(self._coverage_diagnostics(pair))
        return out

    def _coverage_diagnostics(self, pair: _Pair) -> list[Diagnostic]:
        out: list[Diagnostic] = []
        up, lo = pair.upper.layer.name, pair.lower.layer.name
        hint = "" if self.complete else " (use --complete to require coverage)"
        # A partial-coverage lower layer covers its parent only in part by
        # design (the rest is discharged elsewhere), so uncovered parent nodes
        # are shown in the table but never flagged -- not even under --complete.
        for nid, _statement in pair.upper.reqset.all_statements():
            if pair.lower.layer.partial_coverage:
                break
            if nid in pair.coverage or nid in pair.upper.waived:
                continue
            file, line, _loc = pair.upper.reqset.loc_of(nid)
            out.append(
                Diagnostic(
                    "error" if self.complete else "warning",
                    "E-TRACE-UNCOVERED" if self.complete else "W-TRACE-UNCOVERED",
                    f"{up} node {nid!r} is covered by no {lo} and no waiver{hint}",
                    file,
                    line=line,
                )
            )
        waiver_file = pair.upper.waiver_file
        if waiver_file is not None:
            for nid in pair.upper.waived:
                if pair.upper.reqset.statement(nid) is None:
                    out.append(
                        Diagnostic(
                            "error",
                            "E-TRACE-WAIVER-UNKNOWN",
                            f"waiver names {nid!r}, which is not a {up} node",
                            waiver_file,
                        )
                    )
                elif nid in pair.coverage:
                    out.append(
                        Diagnostic(
                            "warning",
                            "W-TRACE-WAIVER-REDUNDANT",
                            f"waiver names {nid!r}, but it is covered by "
                            f"{', '.join(pair.coverage[nid])}; remove the waiver",
                            waiver_file,
                        )
                    )
        return out


def _pairs(loaded: list[_Loaded], diags: list[Diagnostic]) -> list[tuple[_Loaded, _Loaded]]:
    """
    Pair every layer but the first with the layer it traces to.

    A layer's ``parent`` defaults to the entry above it, so a chain written as a
    flat list behaves exactly as it reads; naming a parent explicitly is what lets
    two layers hang off the same one.
    """
    by_name = {item.layer.name: item for item in loaded}
    out: list[tuple[_Loaded, _Loaded]] = []
    for above, item in pairwise(loaded):
        named = item.layer.parent
        if named is None:
            out.append((above, item))
        elif named in by_name:
            out.append((by_name[named], item))
        else:
            diags.append(
                Diagnostic(
                    "error",
                    "E-TRACE-PARENT",
                    f"layer {item.layer.name!r} names parent {named!r}, "
                    f"which is not a layer of this chain",
                    item.layer.path,
                )
            )
    return out


def _analyze(upper: _Loaded, lower: _Loaded) -> _Pair:
    """Resolve the refs linking a pair, in whichever direction they run."""
    if lower.layer.refs_point_down:
        return _analyze_downward(upper, lower)

    pair = _Pair(upper, lower)
    pattern = re.compile(lower.layer.id_pattern) if lower.layer.id_pattern else None
    for nid, statement in lower.reqset.all_statements():
        matched = False
        for ref in statement.up_refs or []:
            m = pattern.match(ref) if pattern else None
            if m is None:
                continue  # ref does not target this layer -> out of scope
            matched = True
            parent = m.group(1)
            if upper.reqset.statement(parent) is not None:
                pair.coverage.setdefault(parent, []).append(nid)
                pair.resolved.setdefault(nid, []).append(parent)
            else:
                pair.dangling.setdefault(nid, []).append(ref)
        if not (statement.is_derived or matched):
            pair.untraced.append(nid)
    return pair


def _analyze_downward(upper: _Loaded, lower: _Loaded) -> _Pair:
    """
    Resolve the upper layer's down-refs against the lower layer's nodes.

    The mirror image of :func:`_analyze`: the refs are written in the upper layer
    (an LLR's ``implemented_by``), so it is the upper node that can dangle. There
    is no ``untraced`` counterpart -- "this node cites nothing" is a question
    about the *upper* layer's own completeness, which its schema check already
    owns, and the coverage table shows it either way.
    """
    pair = _Pair(upper, lower)
    for nid, statement in upper.reqset.all_statements():
        for ref in statement.down_refs or []:
            # Resolve through the canonical spelling: Ada is case-insensitive, so
            # a ref must land on the one node it names rather than invent another.
            child = lower.reqset.canonical(ref) if isinstance(lower.reqset, CodeSet) else None
            if child is None:
                pair.dangling.setdefault(nid, []).append(ref)
            else:
                pair.coverage.setdefault(nid, []).append(child)
                pair.resolved.setdefault(child, []).append(nid)
    return pair


# -- rendering (point 2: colored, row-separated dev tables via rich) ----------


_MIN_WIDTH = 80  # assume at least an 80-column terminal, even when piped


def _terminal_width() -> int:
    return max(_MIN_WIDTH, shutil.get_terminal_size().columns)


def _severity_style(status: str) -> str:
    """Map a row's status to a rich style: red for real gaps, yellow for waived/derived."""
    if status in ("UNCOVERED", "UNTRACED", "DANGLING"):
        return "red bold"
    # Expected-and-accounted-for, not a gap: waived, derived, or a layer that
    # covers the one above it only in part by design.
    if status in ("WAIVED", "DERIVED", "UNTESTED", "UNIMPLEMENTED", "UNREQUIRED"):
        return "yellow"
    return "green"


def _new_table(title: str, id_header: str, detail_header: str) -> Table:
    table = Table(title=title, box=box.SQUARE, show_lines=True, title_justify="left")
    table.add_column(id_header, no_wrap=True)
    table.add_column("Status", no_wrap=True)
    table.add_column(detail_header)  # wraps to fit the remaining terminal width
    return table


def _pair_tables(pair: _Pair) -> list[Table]:
    if pair.refs_point_down:
        return _downward_tables(pair)

    up, lo = pair.upper.layer.name, pair.lower.layer.name

    coverage = _new_table(f"{up} → {lo}  (coverage)", up, f"Covered by ({lo})")
    for nid, _statement in pair.upper.reqset.all_statements():
        if nid in pair.coverage:
            status, detail = "OK", ", ".join(pair.coverage[nid])
        elif nid in pair.upper.waived:
            status, detail = "WAIVED", pair.upper.waived[nid] or "(waived)"
        elif pair.lower.layer.partial_coverage:
            # Uncovered here is expected (verified elsewhere, e.g. by proof),
            # not a gap: mark it UNTESTED rather than UNCOVERED.
            status, detail = "UNTESTED", "—"
        else:
            status, detail = "UNCOVERED", "—"
        coverage.add_row(nid, status, detail, style=_severity_style(status))

    upward = _new_table(f"{lo} → {up}  (upward trace)", lo, f"Traces to ({up})")
    for nid, statement in pair.lower.reqset.all_statements():
        if nid in pair.dangling:
            status, detail = "DANGLING", ", ".join(pair.dangling[nid])
        elif nid in pair.resolved:
            status, detail = "OK", ", ".join(pair.resolved[nid])
        elif statement.is_derived:
            status, detail = "DERIVED", "—"
        else:
            status, detail = "UNTRACED", "—"
        upward.add_row(nid, status, detail, style=_severity_style(status))
    return [coverage, upward]


def _downward_tables(pair: _Pair) -> list[Table]:
    """
    Build the two tables of a pair whose refs run downward (LLR -> CODE).

    Same two directions as :func:`_pair_tables`, read the other way: the upper
    node is the one that can dangle, and a lower node no upper node names is
    expected rather than a gap -- most of the code realizes no requirement
    directly.
    """
    up, lo = pair.upper.layer.name, pair.lower.layer.name

    implementation = _new_table(f"{up} → {lo}  (implementation)", up, f"Implemented by ({lo})")
    for nid, _statement in pair.upper.reqset.all_statements():
        if nid in pair.dangling:
            status, detail = "DANGLING", ", ".join(pair.dangling[nid])
        elif nid in pair.coverage:
            status, detail = "OK", ", ".join(pair.coverage[nid])
        else:
            status, detail = "UNIMPLEMENTED", "—"
        implementation.add_row(nid, status, detail, style=_severity_style(status))

    required = _new_table(f"{lo} → {up}  (required by)", lo, f"Required by ({up})")
    for nid, _statement in pair.lower.reqset.all_statements():
        if nid in pair.resolved:
            status, detail = "OK", ", ".join(pair.resolved[nid])
        else:
            # Code no requirement names: a helper, the HAL, a test fixture.
            status, detail = "UNREQUIRED", "—"
        required.add_row(nid, status, detail, style=_severity_style(status))
    return [implementation, required]


def check_trace(layers: list[Layer], *, complete: bool = False) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests and the CLI)."""
    return TraceChecker(layers, complete=complete).check()


def render_tables(layers: list[Layer], width: int | None = None) -> str:
    """Render the tables to a plain string (no color) -- for capture and tests."""
    buffer = StringIO()
    console = Console(
        file=buffer,
        width=width if width is not None else _terminal_width(),
        force_terminal=False,
        no_color=True,
    )
    TraceChecker(layers).print_tables(console)
    return buffer.getvalue()
