"""
Level-agnostic traceability.

A trace *chain* is an ordered list of :class:`Layer`s, top (most abstract) to
bottom -- e.g. CONOPS -> HLR -> LLR -> code/test. The engine runs the same
checks over every adjacent pair (upper -> lower), in both directions:

  E-TRACE-DANGLING         : a lower node's up-ref resolves to no upper node.
  E-TRACE-UNTRACED         : a lower node has no upward trace and is not derived
                             (backward completeness -- always an error).
  {W,E}-TRACE-UNCOVERED    : an upper node that no lower node covers and no
                             waiver excuses (warning; error under --complete).
  E-TRACE-WAIVER-UNKNOWN   : a waiver naming a node that is not in its layer.
  W-TRACE-WAIVER-REDUNDANT : a waiver naming a node the layer below covers.

Nothing here is CONOPS- or HLR-specific. A :class:`Layer` says how to enumerate
its nodes (``kind``: ``markdown-leaves`` or ``requirement-yaml``) and, for any
layer that traces upward, how to extract a parent-node id from each ref
(``id_pattern``, one capture group).

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

from reqs.conops import parse_leaves
from reqs.core import Diagnostic
from reqs.requirement_set import RequirementSet

if TYPE_CHECKING:
    import os

MARKDOWN_LEAVES = "markdown-leaves"
REQUIREMENT_YAML = "requirement-yaml"


@dataclass
class Layer:
    """One layer of the trace chain."""

    name: str
    kind: str
    path: Path
    id_pattern: str | None = None  # regex; group(1) extracts a parent-node id from an up-ref
    waivers: Path | None = None  # nodes here intentionally left uncovered by the layer below


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
        )
        for item in data.get("layers", [])
    ]


@dataclass
class _Loaded:
    layer: Layer
    nodes: dict[str, tuple[Path, int]]  # node id -> (file, line); the coverage targets
    reqset: RequirementSet  # the layer's requirement files (empty for markdown-leaves)
    waived: dict[str, str]  # node id -> reason
    waiver_file: Path | None


@dataclass
class _Pair:
    upper: _Loaded
    lower: _Loaded
    coverage: dict[str, list[str]] = field(default_factory=dict)  # upper id -> covering lower ids
    resolved: dict[str, list[str]] = field(default_factory=dict)  # lower id -> resolved upper ids
    dangling: dict[str, list[str]] = field(default_factory=dict)  # lower id -> unresolvable refs
    untraced: list[str] = field(default_factory=list)


class TraceChecker:
    """Run the traceability checks over every adjacent pair of a chain."""

    def __init__(self, layers: list[Layer], *, complete: bool = False) -> None:
        self.layers = layers
        self.complete = complete

    def check(self) -> list[Diagnostic]:
        diags: list[Diagnostic] = []
        loaded = [self._load(layer, diags) for layer in self.layers]
        for upper, lower in pairwise(loaded):
            diags.extend(self._diagnostics(_analyze(upper, lower)))
        return diags

    def print_tables(self, console: Console | None = None) -> None:
        console = console or Console(width=_terminal_width())
        loaded = [self._load(layer, []) for layer in self.layers]
        for upper, lower in pairwise(loaded):
            for table in _pair_tables(_analyze(upper, lower)):
                console.print(table)

    # -- loading -------------------------------------------------------------

    def _load(self, layer: Layer, diags: list[Diagnostic]) -> _Loaded:
        waived = self._load_waivers(layer, diags)
        if layer.kind == MARKDOWN_LEAVES:
            nodes: dict[str, tuple[Path, int]] = {
                nid: (layer.path, line) for nid, line in parse_leaves(layer.path).items()
            }
            return _Loaded(layer, nodes, RequirementSet(()), waived, layer.waivers)
        if layer.kind == REQUIREMENT_YAML:
            return self._load_requirements(layer, waived, diags)
        diags.append(
            Diagnostic("error", "E-TRACE-KIND", f"unknown layer kind {layer.kind!r}", layer.path)
        )
        return _Loaded(layer, {}, RequirementSet(()), waived, layer.waivers)

    def _load_requirements(
        self, layer: Layer, waived: dict[str, str], diags: list[Diagnostic]
    ) -> _Loaded:
        reqset, load_diags = RequirementSet.load([layer.path])
        diags.extend(load_diags)
        nodes: dict[str, tuple[Path, int]] = {}
        for nid, _statement in reqset.all_statements():
            file, line, _loc = reqset.loc_of(nid)
            nodes[nid] = (file, line)
        return _Loaded(layer, nodes, reqset, waived, layer.waivers)

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
        for nid, refs in pair.dangling.items():
            file, line, loc = pair.lower.reqset.loc_of(nid, sub_key="up_ref")
            out.extend(
                Diagnostic(
                    "error",
                    "E-TRACE-DANGLING",
                    f"{lo} {nid!r} up-ref {ref!r} resolves to no {up} node",
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
        for nid, (file, line) in pair.upper.nodes.items():
            if nid in pair.coverage or nid in pair.upper.waived:
                continue
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
                if nid not in pair.upper.nodes:
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


def _analyze(upper: _Loaded, lower: _Loaded) -> _Pair:
    """Resolve the lower layer's up-refs against the upper layer's nodes."""
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
            if parent in upper.nodes:
                pair.coverage.setdefault(parent, []).append(nid)
                pair.resolved.setdefault(nid, []).append(parent)
            else:
                pair.dangling.setdefault(nid, []).append(ref)
        if not (statement.is_derived or matched):
            pair.untraced.append(nid)
    return pair


# -- rendering (point 2: colored, row-separated dev tables via rich) ----------


_MIN_WIDTH = 80  # assume at least an 80-column terminal, even when piped


def _terminal_width() -> int:
    return max(_MIN_WIDTH, shutil.get_terminal_size().columns)


def _severity_style(status: str) -> str:
    """Map a row's status to a rich style: red for real gaps, yellow for waived/derived."""
    if status in ("UNCOVERED", "UNTRACED", "DANGLING"):
        return "red bold"
    if status in ("WAIVED", "DERIVED"):
        return "yellow"
    return "green"


def _new_table(title: str, id_header: str, detail_header: str) -> Table:
    table = Table(title=title, box=box.SQUARE, show_lines=True, title_justify="left")
    table.add_column(id_header, no_wrap=True)
    table.add_column("Status", no_wrap=True)
    table.add_column(detail_header)  # wraps to fit the remaining terminal width
    return table


def _pair_tables(pair: _Pair) -> list[Table]:
    up, lo = pair.upper.layer.name, pair.lower.layer.name

    coverage = _new_table(f"{up} → {lo}  (coverage)", up, f"Covered by ({lo})")
    for nid in pair.upper.nodes:
        if nid in pair.coverage:
            status, detail = "OK", ", ".join(pair.coverage[nid])
        elif nid in pair.upper.waived:
            status, detail = "WAIVED", pair.upper.waived[nid] or "(waived)"
        else:
            status, detail = "UNCOVERED", "—"
        coverage.add_row(nid, status, detail, style=_severity_style(status))

    upward = _new_table(f"{lo} → {up}  (upward trace)", lo, f"Traces to ({up})")
    for nid, statement in pair.lower.reqset.all_statements():
        if nid in pair.resolved:
            status, detail = "OK", ", ".join(pair.resolved[nid])
        elif statement.is_derived:
            status, detail = "DERIVED", "—"
        elif nid in pair.dangling:
            status, detail = "DANGLING", ", ".join(pair.dangling[nid])
        else:
            status, detail = "UNTRACED", "—"
        upward.add_row(nid, status, detail, style=_severity_style(status))
    return [coverage, upward]


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
