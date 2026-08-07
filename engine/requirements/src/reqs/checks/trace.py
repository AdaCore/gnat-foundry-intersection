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
                             A ``method`` layer covers only nodes declaring it.
  E-TRACE-UNVERIFIED       : a method-verified node declaring no method.
  E-TRACE-METHOD           : coverage contradicting the covered node's method.
  E-TRACE-CHECK-IGNORED    : a tagged check no ada-checks layer's anchors accept.
  E-TRACE-CHECK-EMPTY      : a ``--@covers`` tag on a check citing nothing at all.
  E-TRACE-WAIVER-UNKNOWN   : a waiver naming a node that is not in its layer.
  W-TRACE-WAIVER-REDUNDANT : a waiver naming a node the layer below covers.

  E-TRACE-PARENT           : a layer names a ``parent`` that is not in the chain.
  E-TRACE-CONFIG           : inconsistent layer config (unknown ``method``,
                             ``ref_field`` or config key; ``refs_point_down``
                             iff ``ref_field``, whose parent must hold
                             statements; ``method`` layers trace upward and
                             cannot be ``partial_coverage``; ``anchors`` only,
                             and well-formed, on ``ada-checks``).
  E-TRACE-LAYER            : ``--layers`` named a layer that is not in the chain.
  E-INVENTORY-*            : the code inventory a layer reads is missing, stale
                             or malformed (see :mod:`reqs.code_inventory`).

Nothing here is CONOPS- or HLR-specific. A :class:`Layer` says how to enumerate
its nodes (``kind``: ``markdown-leaves``, ``requirement-yaml``, ``ada-tests``,
``ada-entities`` or ``ada-checks``) and, for any layer that traces upward, how
to extract a parent-node id from each ref (``id_pattern``, one capture group,
matched against the *whole* ref: a pattern that matched only a prefix would
accept ``llr_3_conflicts.1typo`` as ``llr_3_conflicts.1``).

A layer that discharges one verification method declares it as ``method``: its
parent's nodes need covering exactly when they declare that method. Method
layers trace upward -- the evidence cites the statement it discharges via a
``--@covers`` tag, whether it is a test routine (``ada-tests``) or a tagged
pragma / contract aspect (``ada-checks``, whose ``anchors`` say which
constructs count). This also keeps an empty generated inventory loud -- no
test routines means every test-verified requirement goes uncovered.

One layer kind traces the other way. Code cites nothing -- it is the LLR that
names what implements it -- so a layer may set ``refs_point_down`` and name
the parent-statement field its refs are written in (``ref_field``, e.g.
``implemented_by``) -- which must be a field its parent's statements actually
hold, since a mistyped one reads no refs at all and checks the layer away in
silence. Several layers can hang off the same parent. The checks keep their
meaning under the flip: a ref that resolves to nothing is still
E-TRACE-DANGLING, reported against whichever node wrote it, which is now the
parent.

A layer may set ``partial_coverage`` when it covers the layer above only in
part by design and no ``method`` says which part (e.g. CODE): uncovered upper
nodes are then shown in the table but never flagged, even under ``--complete``.

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
from reqs.ada_checks import CheckSet
from reqs.ada_tests import TestSet
from reqs.code_entities import CodeSet
from reqs.conops import ConopsSet
from reqs.core import Diagnostic
from reqs.document import DOWN_REF_FIELDS, VERIFICATION_METHODS
from reqs.requirement_set import RequirementSet

if TYPE_CHECKING:
    import os
    from collections.abc import Iterable

    from reqs.core import SubKey

MARKDOWN_LEAVES = "markdown-leaves"
REQUIREMENT_YAML = "requirement-yaml"
ADA_TESTS = "ada-tests"
ADA_ENTITIES = "ada-entities"
ADA_CHECKS = "ada-checks"


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
    # Covers the layer above only partially by design: uncovered parent nodes
    # are tabulated but never flagged.
    partial_coverage: bool = False
    # The refs linking this layer to its parent are written in the *parent* and
    # point down into this one (set for CODE: the LLR cites its entities).
    refs_point_down: bool = False
    # Parent-statement field the down-refs are read from (down layers only).
    ref_field: str | None = None
    # Verification method this layer discharges: parent nodes need covering by
    # this layer exactly when they declare it. Method layers trace upward.
    method: str | None = None
    # ada-checks only: the anchor shapes accepted ("pragma", "aspect:Post", ...).
    anchors: list[str] = field(default_factory=list)
    # Chain-file keys that mean nothing here; E-TRACE-CONFIG, never silence.
    unknown_keys: tuple[str, ...] = ()


_LAYER_KEYS = frozenset(
    {
        "name",
        "kind",
        "path",
        "id_pattern",
        "waivers",
        "parent",
        "partial_coverage",
        "refs_point_down",
        "ref_field",
        "method",
        "anchors",
    }
)


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
            ref_field=item.get("ref_field"),
            method=item.get("method"),
            anchors=list(item.get("anchors") or []),
            unknown_keys=tuple(sorted(set(item) - _LAYER_KEYS)),
        )
        for item in data.get("layers", [])
    ]


def select_layers(
    layers: list[Layer], names: Iterable[str], chain: Path
) -> tuple[list[Layer], list[Diagnostic]]:
    """
    Restrict a chain to the named layers, keeping the file's order.

    A caller that cannot afford every layer -- ``make validate-reqs`` runs with no
    Ada toolchain, so the inventory-backed layers are out of its reach -- asks for
    the portion it can check rather than dropping the check altogether. Only pairs
    *wholly* inside the selection are then checked; a layer whose parent is left
    out is reported as E-TRACE-PARENT, since silently checking nothing is the
    failure mode this exists to avoid. An unknown name is E-TRACE-LAYER rather
    than a silently smaller chain, for the same reason.
    """
    wanted = list(names)
    known = {layer.name for layer in layers}
    diags = [
        Diagnostic("error", "E-TRACE-LAYER", f"no layer named {name!r} in this chain", chain)
        for name in wanted
        if name not in known
    ]
    return [layer for layer in layers if layer.name in wanted], diags


@dataclass
class _Loaded:
    layer: Layer
    # nodes: coverage targets, up-refs, locations
    reqset: RequirementSet | ConopsSet | TestSet | CodeSet | CheckSet
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
        diags = _config_diagnostics(self.layers)
        if diags:
            return diags  # the chain config itself is wrong; don't guess at intent
        loaded = [self._load(layer, diags) for layer in self.layers]
        pairs = _pairs(loaded, diags)
        if any(d.level == "error" for d in diags):
            return diags  # corpus isn't valid; traceability over it is meaningless
        diags.extend(self._unverified_diagnostics(pairs))
        diags.extend(self._check_diagnostics(loaded))
        for upper, lower in pairs:
            diags.extend(self._diagnostics(_analyze(upper, lower)))
        return diags

    @staticmethod
    def _check_diagnostics(loaded: list[_Loaded]) -> list[Diagnostic]:
        """
        Report tagged checks whose ``--@covers`` tag discharges nothing.

        Two ways that happens, reported independently: the payload cites no id
        at all (E-TRACE-CHECK-EMPTY, a broken tag wherever it sits), or no
        ada-checks layer's anchors accept the construct it sits on
        (E-TRACE-CHECK-IGNORED). Either way the author opted in, and a citation
        that vanishes looks done while verifying nothing. Anchors are unioned
        per inventory, so select all of its ada-checks layers or none.
        """
        by_path: dict[Path, tuple[list[str], CheckSet]] = {}
        for item in loaded:
            if isinstance(item.reqset, CheckSet):
                anchors, _ = by_path.setdefault(item.layer.path, ([], item.reqset))
                anchors.extend(item.layer.anchors)
        out: list[Diagnostic] = []
        for anchors, checkset in by_path.values():
            out.extend(
                Diagnostic(
                    "error",
                    "E-TRACE-CHECK-EMPTY",
                    f"tagged {check.kind} {check.name!r} has a --@covers tag citing "
                    f"nothing; name the statement id(s) it discharges, or write "
                    f"--@covers none: <reason>",
                    Path(check.location.file),
                    line=check.location.line,
                )
                for check in checkset.malformed()
            )
            out.extend(
                Diagnostic(
                    "error",
                    "E-TRACE-CHECK-IGNORED",
                    f"tagged {check.kind} {check.name!r} matches no ada-checks layer's "
                    f"anchors; its --@covers citation is silently discharging nothing",
                    Path(check.location.file),
                    line=check.location.line,
                )
                for check in checkset.unmatched(anchors)
            )
        return out

    @staticmethod
    def _unverified_diagnostics(pairs: list[tuple[_Loaded, _Loaded]]) -> list[Diagnostic]:
        """Report nodes declaring no method, once per method-verified upper layer."""
        out: list[Diagnostic] = []
        checked: set[str] = set()
        for upper, lower in pairs:
            if lower.layer.method is None or upper.layer.name in checked:
                continue
            checked.add(upper.layer.name)
            for nid, statement in upper.reqset.all_statements():
                if statement.verification_methods:
                    continue
                file, line, loc = upper.reqset.loc_of(nid)
                out.append(
                    Diagnostic(
                        "error",
                        "E-TRACE-UNVERIFIED",
                        f"{upper.layer.name} {nid!r} declares no verification method "
                        f"(one of: {', '.join(VERIFICATION_METHODS)})",
                        file,
                        line=line,
                        path=loc,
                    )
                )
        return out

    def print_tables(self, console: Console | None = None) -> None:
        """
        Print the coverage / upward-trace tables for every (parent, child) pair.

        The method layers merge into one verification table per parent -- one
        row per statement, its declared methods' evidence side by side -- since
        they are facets of a single relation, not successive abstractions. Each
        method layer also keeps its own upward-trace table: that one is about
        the *artifacts* -- every test routine or tagged check and what it cites.
        """
        console = console or Console(width=_terminal_width())
        loaded = [self._load(layer, []) for layer in self.layers]
        analyzed = [(upper, _analyze(upper, lower)) for upper, lower in _pairs(loaded, [])]
        merged: set[str] = set()
        for upper, pair in analyzed:
            if pair.lower.layer.method is None:
                for table in _pair_tables(pair):
                    console.print(table)
                continue
            if upper.layer.name not in merged:
                merged.add(upper.layer.name)
                method_pairs = [
                    p
                    for u, p in analyzed
                    if p.lower.layer.method is not None and u.layer.name == upper.layer.name
                ]
                console.print(_verification_table(upper, method_pairs))
            console.print(_upward_table(pair))

    # -- loading -------------------------------------------------------------

    def _load(self, layer: Layer, diags: list[Diagnostic]) -> _Loaded:
        waived = self._load_waivers(layer, diags)
        if layer.kind == MARKDOWN_LEAVES:
            return _Loaded(layer, ConopsSet.load(layer.path), waived, layer.waivers)
        if layer.kind == REQUIREMENT_YAML:
            reqset, load_diags = RequirementSet.load([layer.path])
            diags.extend(load_diags)
            return _Loaded(layer, reqset, waived, layer.waivers)
        if layer.kind in (ADA_TESTS, ADA_ENTITIES, ADA_CHECKS):
            inventory, load_diags = code_inventory.load(layer.path)
            diags.extend(load_diags)
            if layer.kind == ADA_TESTS:
                testset, test_diags = TestSet.from_inventory(inventory, layer.path)
                diags.extend(test_diags)
                return _Loaded(layer, testset, waived, layer.waivers)
            if layer.kind == ADA_CHECKS:
                checkset, check_diags = CheckSet.from_inventory(
                    inventory, layer.path, layer.anchors
                )
                diags.extend(check_diags)
                return _Loaded(layer, checkset, waived, layer.waivers)
            return _Loaded(
                layer, CodeSet.from_inventory(inventory, layer.path), waived, layer.waivers
            )
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
        if pair.refs_point_down:
            owner, target = up, lo
            sub_key: SubKey | None = pair.lower.layer.ref_field
            direction = pair.lower.layer.ref_field or "down-ref"
        else:
            owner, target = lo, up
            sub_key = "up_ref"
            direction = "up-ref"
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
        out.extend(self._uncovered_diagnostics(pair))
        out.extend(self._method_diagnostics(pair))
        out.extend(self._waiver_diagnostics(pair))
        return out

    def _uncovered_diagnostics(self, pair: _Pair) -> list[Diagnostic]:
        # A partial-coverage layer never flags uncovered parents, not even
        # under --complete.
        if pair.lower.layer.partial_coverage:
            return []
        method = pair.lower.layer.method
        out: list[Diagnostic] = []
        up, lo = pair.upper.layer.name, pair.lower.layer.name
        hint = "" if self.complete else " (use --complete to require coverage)"
        for nid, statement in pair.upper.reqset.all_statements():
            if nid in pair.coverage or nid in pair.upper.waived:
                continue
            if method is not None and method not in statement.verification_methods:
                continue  # verified by other methods (or none: E-TRACE-UNVERIFIED)
            if pair.refs_point_down and nid in pair.dangling:
                continue  # every ref it wrote dangles; already reported above
            declared = f"declares verification {method!r} but" if method else "is"
            file, line, _loc = pair.upper.reqset.loc_of(nid)
            out.append(
                Diagnostic(
                    "error" if self.complete else "warning",
                    "E-TRACE-UNCOVERED" if self.complete else "W-TRACE-UNCOVERED",
                    f"{up} node {nid!r} {declared} covered by no {lo} and no waiver{hint}",
                    file,
                    line=line,
                )
            )
        return out

    @staticmethod
    def _method_diagnostics(pair: _Pair) -> list[Diagnostic]:
        """Report coverage that contradicts the covered node's declared method."""
        method = pair.lower.layer.method
        if method is None:
            return []
        out: list[Diagnostic] = []
        up, lo = pair.upper.layer.name, pair.lower.layer.name
        for nid, statement in pair.upper.reqset.all_statements():
            declared = statement.verification_methods
            if nid not in pair.coverage or not declared or method in declared:
                continue  # declaring nothing is E-TRACE-UNVERIFIED already
            for lower_id in pair.coverage[nid]:
                file, line, loc = pair.lower.reqset.loc_of(lower_id, sub_key="up_ref")
                out.append(
                    Diagnostic(
                        "error",
                        "E-TRACE-METHOD",
                        f"{lo} {lower_id!r} covers {up} {nid!r}, whose verification "
                        f"({', '.join(declared)}) does not include {method!r}",
                        file,
                        line=line,
                        path=loc,
                    )
                )
        return out

    @staticmethod
    def _waiver_diagnostics(pair: _Pair) -> list[Diagnostic]:
        """Lint the upper layer's waiver file: unknown nodes, redundant entries."""
        out: list[Diagnostic] = []
        up = pair.upper.layer.name
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


def _parent_in(layers: list[Layer], index: int) -> Layer | None:
    """
    Resolve which layer ``layers[index]`` traces to, by the rule :func:`_pairs` uses.

    None when it has no parent here: the first entry of the chain, or a named
    parent left out of a ``--layers`` selection (E-TRACE-PARENT reports that).
    """
    layer = layers[index]
    if layer.parent is not None:
        return next((item for item in layers if item.name == layer.parent), None)
    return layers[index - 1] if index > 0 else None


def _ref_field_messages(layers: list[Layer], index: int) -> list[str]:
    """
    Check a layer's down-ref config: the flag, the field name, and its parent.

    Getting any of the three wrong reads *no* refs rather than the wrong ones,
    and a down layer usually carries ``partial_coverage``, so nothing is left to
    report: no dangling refs, no coverage, nothing uncovered. Silently checking
    the whole layer away is the failure mode these three exist to prevent.
    """
    layer = layers[index]
    if layer.refs_point_down and not layer.ref_field:
        return [
            f"layer {layer.name!r} sets refs_point_down but no ref_field "
            f"says where its refs are written"
        ]
    if not layer.ref_field:
        return []

    out: list[str] = []
    if not layer.refs_point_down:
        out.append(
            f"layer {layer.name!r} names ref_field {layer.ref_field!r} "
            f"but its refs do not point down"
        )
    if layer.ref_field not in DOWN_REF_FIELDS:
        out.append(
            f"layer {layer.name!r} names unknown ref_field {layer.ref_field!r}; "
            f"no statement holds refs in it, so the layer would resolve nothing "
            f"(one of: {', '.join(DOWN_REF_FIELDS)})"
        )
    parent = _parent_in(layers, index)
    if parent is not None and parent.kind != REQUIREMENT_YAML:
        # Only requirement statements hold downward refs at all, so even a real
        # field read from any other kind of parent resolves nothing.
        out.append(
            f"layer {layer.name!r} reads its refs from the {layer.ref_field!r} of "
            f"{parent.name!r}, whose {parent.kind!r} nodes hold no downward refs"
        )
    return out


def _config_diagnostics(layers: list[Layer]) -> list[Diagnostic]:
    """Reject inconsistent layer config, which would silently check less than intended."""
    out: list[Diagnostic] = []

    def bad(layer: Layer, message: str) -> None:
        out.append(Diagnostic("error", "E-TRACE-CONFIG", message, layer.path))

    for index, layer in enumerate(layers):
        for message in _ref_field_messages(layers, index):
            bad(layer, message)
        if layer.method is not None and layer.refs_point_down:
            bad(
                layer,
                f"layer {layer.name!r} sets both method and refs_point_down; "
                f"a method layer's evidence cites its parent upward",
            )
        if layer.method is not None and layer.partial_coverage:
            bad(
                layer,
                f"layer {layer.name!r} sets both method and partial_coverage, "
                f"which would exempt the very statements the method requires covered",
            )
        if layer.method is not None and layer.method not in VERIFICATION_METHODS:
            bad(
                layer,
                f"layer {layer.name!r} names unknown method {layer.method!r} "
                f"(one of: {', '.join(VERIFICATION_METHODS)})",
            )
        if layer.anchors and layer.kind != ADA_CHECKS:
            bad(
                layer,
                f"layer {layer.name!r} lists anchors but is not an ada-checks layer; "
                f"they would select nothing",
            )
        if layer.unknown_keys:
            bad(
                layer,
                f"layer {layer.name!r} has unknown config key(s) {', '.join(layer.unknown_keys)}",
            )
        if layer.kind == ADA_CHECKS and not layer.anchors:
            bad(
                layer,
                f"layer {layer.name!r} is ada-checks but lists no anchors; "
                f"it would match no check at all",
            )
        for anchor in layer.anchors:
            kind, _, name = anchor.partition(":")
            if kind not in ("pragma", "aspect") or (kind == "aspect" and not name):
                bad(
                    layer,
                    f"layer {layer.name!r} anchor {anchor!r} is not 'pragma'[':<Name>'] "
                    f"or 'aspect:<Name>'",
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
            # `fullmatch`, not `match`: with a prefix match, `llr_3_conflicts.1typo`
            # would resolve to `llr_3_conflicts.1` and pass, so a fat-fingered tag
            # would silently trace to the wrong requirement instead of dangling.
            m = pattern.fullmatch(ref) if pattern else None
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

    The mirror image of :func:`_analyze`: the refs live in the parent-statement
    field named by the layer's ``ref_field``, so it is the upper node that can
    dangle. There is no ``untraced`` counterpart -- statement completeness is
    the upper layer's schema check's job.
    """
    pair = _Pair(upper, lower)
    for nid, statement in upper.reqset.all_statements():
        refs = statement.down_refs_in(lower.layer.ref_field)
        for ref in refs or []:
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


_RED_STATUSES = frozenset({"UNCOVERED", "UNTRACED", "DANGLING", "UNVERIFIED", "MISMATCH"})
# Expected-and-accounted-for, not a gap (waived, derived, review-verified,
# or partial coverage).
_YELLOW_STATUSES = frozenset(
    {"WAIVED", "DERIVED", "UNTESTED", "UNIMPLEMENTED", "UNREQUIRED", "REVIEW"}
)


def _severity_style(status: str) -> str:
    """Map a row's status to a rich style: red for real gaps, yellow for expected ones."""
    if status in _RED_STATUSES:
        return "red bold"
    if status in _YELLOW_STATUSES:
        return "yellow"
    return "green"


def _new_table(title: str, id_header: str, detail_header: str) -> Table:
    table = Table(title=title, box=box.SQUARE, show_lines=True, title_justify="left")
    table.add_column(id_header, no_wrap=True)
    table.add_column("Status", no_wrap=True)
    table.add_column(detail_header)  # wraps to fit the remaining terminal width
    return table


def _coverage_status(pair: _Pair, nid: str) -> tuple[str, str]:
    """Status and detail of one upper node's coverage row."""
    if nid in pair.coverage:
        return "OK", ", ".join(pair.coverage[nid])
    if nid in pair.upper.waived:
        return "WAIVED", pair.upper.waived[nid] or "(waived)"
    # Under partial coverage, uncovered is expected (accounted for elsewhere).
    return ("UNTESTED", "—") if pair.lower.layer.partial_coverage else ("UNCOVERED", "—")


def _upward_table(pair: _Pair) -> Table:
    """Build the lower layer's upward-trace table: what each artifact cites."""
    up, lo = pair.upper.layer.name, pair.lower.layer.name
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
    return upward


# Aggregate row statuses of the verification table, worst last.
_VERIFICATION_SEVERITY = ("OK", "REVIEW", "UNCOVERED", "MISMATCH")


def _verification_status(
    nid: str, statement: object, by_method: dict[str | None, _Pair]
) -> tuple[str, str]:
    """Status and per-method evidence of one statement's verification row."""
    declared: tuple[str, ...] = statement.verification_methods  # type: ignore[attr-defined]
    parts: list[str] = []
    worst = "OK"

    def bump(status: str) -> None:
        nonlocal worst
        if _VERIFICATION_SEVERITY.index(status) > _VERIFICATION_SEVERITY.index(worst):
            worst = status

    for method in declared:
        pair = by_method.get(method)
        if method == "review":
            justification = statement.justification_for(method)  # type: ignore[attr-defined]
            parts.append(f"review: {justification}")
            bump("REVIEW")
        elif pair is None:
            parts.append(f"{method}: (layer not selected)")
        elif nid in pair.coverage:
            parts.append(f"{method}: {', '.join(pair.coverage[nid])}")
        else:
            parts.append(f"{method}: —")
            bump("UNCOVERED")
    # Evidence in a layer whose method the statement does not declare: drift.
    for stray, pair in by_method.items():
        if stray not in declared and nid in pair.coverage:
            parts.append(f"{stray}: {', '.join(pair.coverage[nid])} (not declared)")
            bump("MISMATCH")
    if not declared:
        return "UNVERIFIED", "; ".join(parts) or "—"
    return worst, "; ".join(parts)


def _verification_table(upper: _Loaded, pairs: list[_Pair]) -> Table:
    """
    Build the one verification table of a parent layer.

    The method layers are facets of a single relation -- each statement versus
    the evidence its declared methods require -- so they merge into one row per
    statement instead of one table per method.
    """
    by_method = {pair.lower.layer.method: pair for pair in pairs}
    table = _new_table(
        f"{upper.layer.name} → VERIFICATION  (declared methods)", upper.layer.name, "Evidence"
    )
    for nid, statement in upper.reqset.all_statements():
        if nid in upper.waived:
            status, detail = "WAIVED", upper.waived[nid] or "(waived)"
        else:
            status, detail = _verification_status(nid, statement, by_method)
        table.add_row(nid, status, detail, style=_severity_style(status))
    return table


def _pair_tables(pair: _Pair) -> list[Table]:
    if pair.refs_point_down:
        return _downward_tables(pair)

    up, lo = pair.upper.layer.name, pair.lower.layer.name

    coverage = _new_table(f"{up} → {lo}  (coverage)", up, f"Covered by ({lo})")
    for nid, _statement in pair.upper.reqset.all_statements():
        status, detail = _coverage_status(pair, nid)
        coverage.add_row(nid, status, detail, style=_severity_style(status))

    return [coverage, _upward_table(pair)]


# Downward-table labels, keyed by the layer's ref_field: title suffix, detail
# header, uncovered status.
_REF_FIELD_LABELS = {
    "implemented_by": ("implementation", "Implemented by", "UNIMPLEMENTED"),
}


def _downward_tables(pair: _Pair) -> list[Table]:
    """
    Build the two tables of a pair whose refs run downward (LLR -> CODE).

    The upper node is the one that can dangle; a lower node no upper node names
    is expected rather than a gap -- most of the code realizes no requirement
    directly.
    """
    up, lo = pair.upper.layer.name, pair.lower.layer.name
    field = pair.lower.layer.ref_field or "down refs"
    title, header, uncovered = _REF_FIELD_LABELS.get(field, (field, field, "UNCOVERED"))

    forward = _new_table(f"{up} → {lo}  ({title})", up, f"{header} ({lo})")
    for nid, _statement in pair.upper.reqset.all_statements():
        if nid in pair.dangling:
            status, detail = "DANGLING", ", ".join(pair.dangling[nid])
        elif nid in pair.coverage:
            status, detail = "OK", ", ".join(pair.coverage[nid])
        else:
            status, detail = uncovered, "—"
        forward.add_row(nid, status, detail, style=_severity_style(status))

    required = _new_table(f"{lo} → {up}  (required by)", lo, f"Required by ({up})")
    for nid, _statement in pair.lower.reqset.all_statements():
        if nid in pair.resolved:
            status, detail = "OK", ", ".join(pair.resolved[nid])
        else:
            # Code no requirement names: a helper, the HAL, a test fixture.
            status, detail = "UNREQUIRED", "—"
        required.add_row(nid, status, detail, style=_severity_style(status))
    return [forward, required]


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
