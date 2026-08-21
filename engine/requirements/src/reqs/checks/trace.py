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
  E-TRACE-UNSELECTED       : a node declaring a method no selected layer
                             verifies -- its evidence cannot be checked here.
                             Disable explicitly with ``--allow-unselected``.
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
  E-TRACE-ALLOW            : ``--allow-unselected`` named something that is not
                             a machine verification method.
  E-INVENTORY-*            : the code inventory a layer reads is missing, stale
                             or malformed (see :mod:`reqs.code_inventory`).

Nothing here is CONOPS- or HLR-specific. A :class:`Layer` says how to enumerate
its nodes (``kind``: ``markdown-leaves``, ``requirement-yaml``, ``ada-tests``,
``ada-entities`` or ``ada-checks``) and, for any layer that traces upward, how
to extract a parent-node id from each ref (``id_pattern``, one capture group,
matched against the *whole* ref: a pattern that matched only a prefix would
accept ``llr_3_conflicts.1typo`` as ``llr_3_conflicts.1``). Its ``name`` is the
short one the ids and matrix headings carry; a layer whose name is an acronym
can spell itself out in ``title``, which is what a document heading uses.

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
from collections import defaultdict
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
    # How a document naming this layer spells it out; the short `name` is what
    # ids, tags and matrix headings use, and stands in when no title is given.
    title: str | None = None
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
        "title",
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
            title=item.get("title"),
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


def select_allowed_methods(
    names: Iterable[str], chain: Path
) -> tuple[frozenset[str], list[Diagnostic]]:
    """
    Validate ``--allow-unselected``'s method names.

    Only the machine-evidence methods can be deferred: `review` never raises
    E-TRACE-UNSELECTED (it needs no layer), so allowing it would be a
    misunderstanding worth surfacing, and a typo'd name would silence nothing
    while looking deliberate -- E-TRACE-ALLOW either way, for the same reason
    an unknown ``--layers`` name is E-TRACE-LAYER.
    """
    machine = tuple(m for m in VERIFICATION_METHODS if m != "review")
    wanted = list(names)
    diags = [
        Diagnostic(
            "error",
            "E-TRACE-ALLOW",
            f"{name!r} is not a machine verification method (one of: {', '.join(machine)})",
            chain,
        )
        for name in wanted
        if name not in machine
    ]
    return frozenset(name for name in wanted if name in machine), diags


NodeSet = RequirementSet | ConopsSet | TestSet | CodeSet | CheckSet
"""Any layer's nodes: the surface every `kind` presents to the trace engine.

Whatever a layer reads -- requirement YAML, CONOPS markdown, an Ada inventory --
it presents the same three queries: `all_statements`, `statement`, `loc_of`.
"""


@dataclass
class _Loaded:
    layer: Layer
    # nodes: coverage targets, up-refs, locations
    reqset: NodeSet
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
    """
    Run the traceability checks over every adjacent pair of a chain.

    ``selected_layers`` names the layers to check (default: all of them).
    ``chain`` contains the full chain, including unselected layers.
    """

    def __init__(
        self,
        chain: list[Layer],
        *,
        selected_layers: Iterable[str] | None = None,
        complete: bool = False,
        allow_unselected: Iterable[str] = (),
    ) -> None:
        self.chain = chain
        self.complete = complete
        self.allow_unselected = frozenset(allow_unselected)
        if selected_layers is None:
            self.layers = chain
        else:
            names = set(selected_layers)
            unknown = names - {layer.name for layer in chain}
            if unknown:
                # `cli.trace()` should have already raised `E-TRACE-LAYER`.
                msg = f"selected layer(s) not in the chain: {', '.join(sorted(unknown))}"
                raise ValueError(msg)
            self.layers = [layer for layer in chain if layer.name in names]

    def check(self) -> list[Diagnostic]:
        """Check every (parent, child) pair of the chain; return any diagnostics."""
        diags, _loaded, _analyzed, _valid = self._gather()
        return diags

    def _gather(
        self,
    ) -> tuple[list[Diagnostic], list[_Loaded], list[tuple[_Loaded, _Pair]], bool]:
        """
        Load the chain, analyze every pair, and collect every diagnostic.

        Returns ``(diags, loaded, analyzed, corpus_valid)``. When the chain
        config or the corpus itself is invalid, analysis stops early and
        ``analyzed`` is empty: traceability over a broken corpus would be
        meaningless.
        """
        diags = _config_diagnostics(self.layers)
        if diags:
            return diags, [], [], False  # the chain config itself is wrong; don't guess at intent
        loaded = [self._load(layer, diags) for layer in self.layers]
        pairs = _pairs(loaded, diags)
        if any(d.level == "error" for d in diags):
            return diags, loaded, [], False
        diags.extend(self._unverified_diagnostics(pairs))
        diags.extend(self._check_diagnostics(loaded))
        analyzed = [(upper, _analyze(upper, lower)) for upper, lower in pairs]
        for _upper, pair in analyzed:
            diags.extend(self._diagnostics(pair))
        return diags, loaded, analyzed, True

    def to_report(
        self, *, chain: Path, command: str | None = None, generated_at: str | None = None
    ) -> dict[str, object]:
        """
        Build the machine-readable trace report (the ``--format json`` payload).

        The rows are the very rows the tables render and the diagnostics the
        very diagnostics `check` reports, so over a valid corpus the three
        views cannot disagree (`print_tables` still draws best-effort tables
        over an invalid one; this report omits them instead). The verdict
        travels *inside* the payload (``errors`` / ``warnings`` /
        ``corpus_valid``): a consumer renders the gaps, it does not re-judge
        them.
        """
        diags, loaded, analyzed, corpus_valid = self._gather()
        by_name = {item.layer.name: item for item in loaded}
        layers: list[dict[str, object]] = [
            {
                "name": layer.name,
                "kind": layer.kind,
                "path": str(layer.path),
                "parent": layer.parent,
                "method": layer.method,
                "partial_coverage": layer.partial_coverage,
                "refs_point_down": layer.refs_point_down,
                "ref_field": layer.ref_field,
                "node_count": (
                    sum(1 for _ in by_name[layer.name].reqset.all_statements())
                    if layer.name in by_name
                    else None
                ),
            }
            for layer in self.layers
        ]
        pairs_out: list[dict[str, object]] = []
        verification_out: list[dict[str, object]] = []
        merged: set[str] = set()
        for upper, pair in analyzed:
            method = pair.lower.layer.method
            if pair.refs_point_down:
                upper_rows, lower_rows = _forward_rows(pair), _required_rows(pair)
            elif method is not None:
                # The upper side of a method pair lives in `verification`.
                upper_rows, lower_rows = [], _upward_rows(pair)
            else:
                upper_rows, lower_rows = _coverage_rows(pair), _upward_rows(pair)
            pairs_out.append(
                {
                    "upper": upper.layer.name,
                    "lower": pair.lower.layer.name,
                    "refs_point_down": pair.refs_point_down,
                    "partial_coverage": pair.lower.layer.partial_coverage,
                    "method": method,
                    "ref_field": pair.lower.layer.ref_field,
                    "upper_rows": [_row_dict(r) for r in upper_rows],
                    "lower_rows": [_row_dict(r) for r in lower_rows],
                }
            )
            if method is not None and upper.layer.name not in merged:
                merged.add(upper.layer.name)
                rows = _verification_rows(upper, _method_pairs(analyzed, upper.layer.name))
                verification_out.append(
                    {
                        "layer": upper.layer.name,
                        "rows": [_verification_row_dict(r) for r in rows],
                    }
                )
        return {
            "schema_version": TRACE_REPORT_SCHEMA_VERSION,
            "chain": str(chain),
            "command": command,
            "generated_at": generated_at,
            "complete": self.complete,
            "corpus_valid": corpus_valid,
            "errors": sum(1 for d in diags if d.level == "error"),
            "warnings": sum(1 for d in diags if d.level == "warning"),
            "layers": layers,
            "pairs": pairs_out,
            "verification": verification_out,
            "diagnostics": [_diag_dict(d) for d in diags],
        }

    def view(self) -> tuple[ChainView, list[Diagnostic]]:
        """
        Build the chain as data: every node with its resolved links, both ways.

        The same analysis the gate and the JSON report run, presented
        node-first rather than pair-first, for a consumer that renders the
        chain rather than judging it (`reqs document`). Over an invalid corpus
        the view carries the nodes it could load with no links at all and
        `valid` false, mirroring `to_report`: links across a broken corpus
        would be misinformation, and rendering them as absent is not the same
        claim as rendering them as none.
        """
        diags, loaded, analyzed, valid = self._gather()
        sets = {item.layer.name: item.reqset for item in loaded}
        nodes: dict[str, dict[str, NodeView]] = {}
        up: dict[str, dict[str, tuple[str, ...]]] = {}
        down: dict[str, dict[str, tuple[str, ...]]] = {}
        dangling: dict[str, list[str]] = {}
        for _upper, pair in analyzed:
            upper_name, lower_name = pair.upper.layer.name, pair.lower.layer.name
            for node_id, covering in pair.coverage.items():
                down.setdefault(f"{upper_name}\0{node_id}", {})[lower_name] = tuple(covering)
            for node_id, resolved in pair.resolved.items():
                up.setdefault(f"{lower_name}\0{node_id}", {})[upper_name] = tuple(resolved)
            # Keyed by whichever layer wrote the refs, as `_Pair.dangling` is.
            owner = pair.ref_owner.layer.name
            for node_id, refs in pair.dangling.items():
                dangling.setdefault(f"{owner}\0{node_id}", []).extend(refs)
        for item in loaded:
            layer_name = item.layer.name
            views: dict[str, NodeView] = {}
            for node_id, node in item.reqset.all_statements():
                key = f"{layer_name}\0{node_id}"
                try:
                    file, line, _keys = item.reqset.loc_of(node_id)
                except KeyError:
                    file, line = None, None
                views[node_id] = NodeView(
                    layer=layer_name,
                    node=node_id,
                    file=file,
                    line=line,
                    up=up.get(key, {}),
                    down=down.get(key, {}),
                    dangling=tuple(dangling.get(key, ())),
                    is_derived=node.is_derived,
                    verification_methods=node.verification_methods,
                    waiver=item.waived.get(node_id),
                )
            nodes[layer_name] = views
        layers = {layer.name: layer for layer in self.layers}
        parents = {
            layer.name: (parent.name if (parent := _parent_in(self.layers, index)) else None)
            for index, layer in enumerate(self.layers)
        }
        return ChainView(nodes=nodes, sets=sets, layers=layers, parents=parents, valid=valid), diags

    def _check_diagnostics(self, loaded: list[_Loaded]) -> list[Diagnostic]:
        """
        Report tagged checks whose ``--@covers`` tag discharges nothing.

        Two ways that happens, reported independently: the payload cites no id
        at all (E-TRACE-CHECK-EMPTY, a broken tag wherever it sits), or no
        ada-checks layer's anchors accept the construct it sits on
        (E-TRACE-CHECK-IGNORED). Either way the author opted in, and a citation
        that vanishes looks done while verifying nothing.
        """
        checksets_by_path = {
            item.layer.path: item.reqset for item in loaded if isinstance(item.reqset, CheckSet)
        }
        anchors_by_path: defaultdict[Path, list[str]] = defaultdict(list)
        for layer in self.chain:
            anchors_by_path[layer.path].extend(layer.anchors)
        out: list[Diagnostic] = []
        for path, checkset in checksets_by_path.items():
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
                for check in checkset.unmatched(anchors_by_path[path])
            )
        return out

    def _unverified_diagnostics(self, pairs: list[tuple[_Loaded, _Loaded]]) -> list[Diagnostic]:
        """
        Report unverifiable statements, once per method-verified upper layer.

        Two ways a declaration can discharge nothing: the statement declares no
        method at all (E-TRACE-UNVERIFIED), or it declares one that no selected
        layer verifies (E-TRACE-UNSELECTED) -- without a layer for the method,
        its evidence is never checked, and silence would read as verified.
        `review` needs no layer: it carries no machine evidence. A method in
        ``allow_unselected`` does not trigger `E-TRACE-UNSELECTED`, but still
        renders as UNSELECTED in the tables and the report.
        """
        provided: dict[str, set[str]] = {}
        for upper, lower in pairs:
            if lower.layer.method is not None:
                provided.setdefault(upper.layer.name, set()).add(lower.layer.method)
        out: list[Diagnostic] = []
        checked: set[str] = set()
        for upper, lower in pairs:
            if lower.layer.method is None or upper.layer.name in checked:
                continue
            checked.add(upper.layer.name)
            for nid, statement in upper.reqset.all_statements():
                methods = statement.verification_methods
                file, line, loc = upper.reqset.loc_of(nid)
                if not methods:
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
                    continue
                out.extend(
                    Diagnostic(
                        "error",
                        "E-TRACE-UNSELECTED",
                        f"{upper.layer.name} {nid!r} declares verification {method!r}, "
                        f"but no selected layer verifies {method!r}",
                        file,
                        line=line,
                        path=loc,
                    )
                    for method in methods
                    if method != "review"
                    and method not in provided[upper.layer.name]
                    and method not in self.allow_unselected
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
                console.print(_verification_table(upper, _method_pairs(analyzed, upper.layer.name)))
            console.print(_upward_table(pair))

    # -- loading -------------------------------------------------------------

    def _load(self, layer: Layer, diags: list[Diagnostic]) -> _Loaded:
        waived = self._load_waivers(layer, diags)
        if layer.kind == MARKDOWN_LEAVES:
            try:
                leaves = ConopsSet.load(layer.path)
            except (OSError, UnicodeDecodeError) as exc:
                diags.append(
                    Diagnostic("error", "E-IO", f"cannot read leaf document: {exc}", layer.path)
                )
                leaves = ConopsSet(layer.path, {})
            return _Loaded(layer, leaves, waived, layer.waivers)
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


# A chain needs an upper and a lower layer before there is anything to trace.
_MIN_CHAIN_LAYERS = 2


def _config_diagnostics(layers: list[Layer]) -> list[Diagnostic]:
    """Reject inconsistent layer config, which would silently check less than intended."""
    out: list[Diagnostic] = []

    def bad(layer: Layer, message: str) -> None:
        out.append(Diagnostic("error", "E-TRACE-CONFIG", message, layer.path))

    # A chain of fewer than two layers has no pair to check: passing it (or
    # reporting it as fully traced) would be silently checking nothing.
    if len(layers) < _MIN_CHAIN_LAYERS:
        out.append(
            Diagnostic(
                "error",
                "E-TRACE-CONFIG",
                f"chain defines {len(layers)} layer(s); tracing needs at least two",
                layers[0].path if layers else Path(),
            )
        )

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


def parent_ref_id(layer: Layer, ref: str) -> str | None:
    """
    Return the parent-node id an up-ref names; None if it targets another layer.

    A layer's ``id_pattern`` says how its statements spell a parent ref (an HLR
    writes ``CONOPS §4.1`` for the leaf ``4.1``); group(1) is the id. Matched in
    full, not by prefix: with a prefix match ``llr_3_conflicts.1typo`` would
    resolve to ``llr_3_conflicts.1`` and pass, so a fat-fingered tag would
    silently trace to the wrong requirement instead of dangling.
    """
    if not layer.id_pattern:
        return None
    m = re.fullmatch(layer.id_pattern, ref)
    return m.group(1) if m else None


def _analyze(upper: _Loaded, lower: _Loaded) -> _Pair:
    """Resolve the refs linking a pair, in whichever direction they run."""
    if lower.layer.refs_point_down:
        return _analyze_downward(upper, lower)

    pair = _Pair(upper, lower)
    for nid, statement in lower.reqset.all_statements():
        matched = False
        for ref in statement.up_refs or []:
            parent = parent_ref_id(lower.layer, ref)
            if parent is None:
                continue  # ref does not target this layer -> out of scope
            matched = True
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


# -- matrix rows (shared by the printed tables and the JSON report) -----------


TRACE_REPORT_SCHEMA_VERSION = 1


@dataclass
class Row:
    """One matrix row: a node, its status, and the refs or prose behind it."""

    node: str
    status: str
    refs: list[str] = field(default_factory=list)
    prose: str | None = None  # non-ref detail: a waiver reason

    @property
    def detail(self) -> str:
        """The Detail cell of the rendered row."""
        if self.prose is not None:
            return self.prose
        return ", ".join(self.refs) if self.refs else "—"


@dataclass
class MethodEvidence:
    """One method's evidence cited for one statement (a verification-row facet)."""

    method: str
    status: str  # OK | UNCOVERED | REVIEW | MISMATCH | UNSELECTED
    evidence: list[str] = field(default_factory=list)

    @property
    def detail(self) -> str:
        """Render this facet's contribution to the row's Evidence cell."""
        if self.status == "UNSELECTED":
            return f"{self.method}: (layer not selected)"
        if self.status == "MISMATCH":
            return f"{self.method}: {', '.join(self.evidence)} (not declared)"
        return f"{self.method}: {', '.join(self.evidence) or '—'}"


@dataclass
class VerificationRow:
    """One statement's verification row: worst status plus per-method facets."""

    node: str
    status: str
    methods: list[MethodEvidence] = field(default_factory=list)
    prose: str | None = None  # non-evidence detail: a waiver reason

    @property
    def detail(self) -> str:
        """The Evidence cell of the rendered row."""
        if self.prose is not None:
            return self.prose
        return "; ".join(m.detail for m in self.methods) or "—"


def _coverage_rows(pair: _Pair) -> list[Row]:
    """Rows of the coverage table: each upper node and what covers it."""
    rows: list[Row] = []
    for nid, _statement in pair.upper.reqset.all_statements():
        if nid in pair.coverage:
            rows.append(Row(nid, "OK", refs=list(pair.coverage[nid])))
        elif nid in pair.upper.waived:
            rows.append(Row(nid, "WAIVED", prose=pair.upper.waived[nid] or "(waived)"))
        elif pair.lower.layer.partial_coverage:
            # Under partial coverage, uncovered is expected (accounted for elsewhere).
            rows.append(Row(nid, "UNTESTED"))
        else:
            rows.append(Row(nid, "UNCOVERED"))
    return rows


def _upward_rows(pair: _Pair) -> list[Row]:
    """Rows of the upward-trace table: each lower artifact and what it cites."""
    rows: list[Row] = []
    for nid, statement in pair.lower.reqset.all_statements():
        if nid in pair.dangling:
            rows.append(Row(nid, "DANGLING", refs=list(pair.dangling[nid])))
        elif nid in pair.resolved:
            rows.append(Row(nid, "OK", refs=list(pair.resolved[nid])))
        elif statement.is_derived:
            rows.append(Row(nid, "DERIVED"))
        else:
            rows.append(Row(nid, "UNTRACED"))
    return rows


def _forward_rows(pair: _Pair) -> list[Row]:
    """Rows of a down pair's forward table: each upper node and the code it names."""
    _title, _header, unimplemented = _ref_field_labels(pair)
    rows: list[Row] = []
    for nid, _statement in pair.upper.reqset.all_statements():
        if nid in pair.dangling:
            rows.append(Row(nid, "DANGLING", refs=list(pair.dangling[nid])))
        elif nid in pair.coverage:
            rows.append(Row(nid, "OK", refs=list(pair.coverage[nid])))
        elif nid in pair.upper.waived:
            rows.append(Row(nid, "WAIVED", prose=pair.upper.waived[nid] or "(waived)"))
        elif pair.lower.layer.partial_coverage:
            # The expected status only under partial coverage; anywhere else the
            # gate flags the node UNCOVERED, and the row must say the same.
            rows.append(Row(nid, unimplemented))
        else:
            rows.append(Row(nid, "UNCOVERED"))
    return rows


def _required_rows(pair: _Pair) -> list[Row]:
    """Rows of a down pair's required-by table: each lower node and who names it."""
    rows: list[Row] = []
    for nid, _statement in pair.lower.reqset.all_statements():
        if nid in pair.resolved:
            rows.append(Row(nid, "OK", refs=list(pair.resolved[nid])))
        else:
            # Code no requirement names: a helper, the HAL, a test fixture.
            rows.append(Row(nid, "UNREQUIRED"))
    return rows


def _verification_facets(
    nid: str, statement: object, by_method: dict[str, _Pair]
) -> tuple[str, list[MethodEvidence]]:
    """Worst status and per-method facets of one statement's verification row."""
    declared: tuple[str, ...] = statement.verification_methods  # type: ignore[attr-defined]
    facets: list[MethodEvidence] = []
    worst = "OK"

    def bump(status: str) -> None:
        nonlocal worst
        if _VERIFICATION_SEVERITY.index(status) > _VERIFICATION_SEVERITY.index(worst):
            worst = status

    for method in declared:
        pair = by_method.get(method)
        if method == "review":
            justification = statement.justification_for(method)  # type: ignore[attr-defined]
            facets.append(
                MethodEvidence(method, "REVIEW", [justification] if justification else [])
            )
            bump("REVIEW")
        elif pair is None:
            # No layer verifies this method here: unknown, which must not
            # aggregate to OK (an unchecked declaration is not evidence).
            facets.append(MethodEvidence(method, "UNSELECTED"))
            bump("UNSELECTED")
        elif nid in pair.coverage:
            facets.append(MethodEvidence(method, "OK", list(pair.coverage[nid])))
        else:
            facets.append(MethodEvidence(method, "UNCOVERED"))
            bump("UNCOVERED")
    # Evidence in a layer whose method the statement does not declare: drift.
    for stray, stray_pair in by_method.items():
        if stray not in declared and nid in stray_pair.coverage:
            facets.append(MethodEvidence(stray, "MISMATCH", list(stray_pair.coverage[nid])))
            bump("MISMATCH")
    if not declared:
        return "UNVERIFIED", facets
    return worst, facets


def _verification_rows(upper: _Loaded, pairs: list[_Pair]) -> list[VerificationRow]:
    """
    Rows of the one verification table of a parent layer.

    The method layers are facets of a single relation -- each statement versus
    the evidence its declared methods require -- so they merge into one row per
    statement instead of one table per method.
    """
    by_method: dict[str, _Pair] = {}
    for pair in pairs:
        if pair.lower.layer.method is not None:
            by_method[pair.lower.layer.method] = pair
    rows: list[VerificationRow] = []
    for nid, statement in upper.reqset.all_statements():
        if nid in upper.waived:
            rows.append(VerificationRow(nid, "WAIVED", prose=upper.waived[nid] or "(waived)"))
            continue
        status, facets = _verification_facets(nid, statement, by_method)
        rows.append(VerificationRow(nid, status, facets))
    return rows


def _method_pairs(analyzed: list[tuple[_Loaded, _Pair]], upper_name: str) -> list[_Pair]:
    """Select the method pairs hanging off one parent layer (the verification facets)."""
    return [
        p for u, p in analyzed if p.lower.layer.method is not None and u.layer.name == upper_name
    ]


def _row_dict(row: Row) -> dict[str, object]:
    """Serialize one matrix row for the JSON report."""
    return {"node": row.node, "status": row.status, "refs": list(row.refs), "detail": row.detail}


def _verification_row_dict(row: VerificationRow) -> dict[str, object]:
    """Serialize one verification row, keeping the per-method facets."""
    return {
        "node": row.node,
        "status": row.status,
        "detail": row.detail,
        "methods": [
            {"method": m.method, "status": m.status, "evidence": list(m.evidence)}
            for m in row.methods
        ],
    }


def _diag_dict(diag: Diagnostic) -> dict[str, object]:
    """Serialize one diagnostic for the JSON report."""
    return {
        "level": diag.level,
        "code": diag.code,
        "message": diag.message,
        "file": str(diag.file),
        "line": diag.line,
        "path": list(diag.path),
    }


# -- rendering (point 2: colored, row-separated dev tables via rich) ----------


_MIN_WIDTH = 80  # assume at least an 80-column terminal, even when piped


def _terminal_width() -> int:
    return max(_MIN_WIDTH, shutil.get_terminal_size().columns)


_RED_STATUSES = frozenset(
    {"UNCOVERED", "UNTRACED", "DANGLING", "UNVERIFIED", "UNSELECTED", "MISMATCH"}
)
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


def _rows_table(title: str, id_header: str, detail_header: str, rows: list[Row]) -> Table:
    """Render matrix rows into a rich table."""
    table = _new_table(title, id_header, detail_header)
    for row in rows:
        table.add_row(row.node, row.status, row.detail, style=_severity_style(row.status))
    return table


def _upward_table(pair: _Pair) -> Table:
    """Build the lower layer's upward-trace table: what each artifact cites."""
    up, lo = pair.upper.layer.name, pair.lower.layer.name
    return _rows_table(f"{lo} → {up}  (upward trace)", lo, f"Traces to ({up})", _upward_rows(pair))


# Aggregate row statuses of the verification table, worst last.
_VERIFICATION_SEVERITY = ("OK", "REVIEW", "UNSELECTED", "UNCOVERED", "MISMATCH")


def _verification_table(upper: _Loaded, pairs: list[_Pair]) -> Table:
    """Build the one verification table of a parent layer (see `_verification_rows`)."""
    table = _new_table(
        f"{upper.layer.name} → VERIFICATION  (declared methods)", upper.layer.name, "Evidence"
    )
    for row in _verification_rows(upper, pairs):
        table.add_row(row.node, row.status, row.detail, style=_severity_style(row.status))
    return table


def _pair_tables(pair: _Pair) -> list[Table]:
    if pair.refs_point_down:
        return _downward_tables(pair)
    up, lo = pair.upper.layer.name, pair.lower.layer.name
    coverage = _rows_table(
        f"{up} → {lo}  (coverage)", up, f"Covered by ({lo})", _coverage_rows(pair)
    )
    return [coverage, _upward_table(pair)]


# Downward-table labels, keyed by the layer's ref_field: title suffix, detail
# header, uncovered status.
_REF_FIELD_LABELS = {
    "implemented_by": ("implementation", "Implemented by", "UNIMPLEMENTED"),
}


def ref_field_header(field: str | None) -> str:
    """Return a down-ref field's reader-facing name (`implemented_by` -> `Implemented by`)."""
    name = field or "down refs"
    return _REF_FIELD_LABELS.get(name, (name, name, "UNCOVERED"))[1]


def _ref_field_labels(pair: _Pair) -> tuple[str, str, str]:
    """Title suffix, detail header, and uncovered status of a down pair."""
    field_name = pair.lower.layer.ref_field or "down refs"
    return _REF_FIELD_LABELS.get(field_name, (field_name, field_name, "UNCOVERED"))


def _downward_tables(pair: _Pair) -> list[Table]:
    """
    Build the two tables of a pair whose refs run downward (LLR -> CODE).

    The upper node is the one that can dangle; a lower node no upper node names
    is expected rather than a gap -- most of the code realizes no requirement
    directly.
    """
    up, lo = pair.upper.layer.name, pair.lower.layer.name
    title, header, _uncovered = _ref_field_labels(pair)
    forward = _rows_table(f"{up} → {lo}  ({title})", up, f"{header} ({lo})", _forward_rows(pair))
    required = _rows_table(
        f"{lo} → {up}  (required by)", lo, f"Required by ({up})", _required_rows(pair)
    )
    return [forward, required]


@dataclass(frozen=True)
class NodeView:
    """One chain node with its resolved links: what a renderer needs per node."""

    layer: str
    node: str
    file: Path | None  # where the node is written; None if its set cannot locate it
    line: int | None
    up: dict[str, tuple[str, ...]]  # upper layer name -> the nodes this one traces to
    down: dict[str, tuple[str, ...]]  # lower layer name -> the nodes covering this one
    dangling: tuple[str, ...]  # refs this node wrote that resolve to no node at all
    is_derived: bool  # cites nothing above it by declaration, not by omission
    verification_methods: tuple[str, ...]
    waiver: str | None  # why this node is left uncovered, when a waiver excuses it


@dataclass(frozen=True)
class ChainView:
    """The whole chain as data, node-first (see `TraceChecker.view`)."""

    nodes: dict[str, dict[str, NodeView]]  # layer name -> node id -> view, in document order
    sets: dict[str, NodeSet]  # layer name -> the nodes it loaded, for content beyond the links
    layers: dict[str, Layer]  # layer name -> its chain entry, for a consumer that reads its config
    parents: dict[str, str | None]  # layer name -> the layer above it, resolved from the chain
    valid: bool  # whether the corpus analysed at all; links are empty when it did not


def check_trace(
    chain: list[Layer],
    *,
    selected: Iterable[str] | None = None,
    complete: bool = False,
    allow_unselected: Iterable[str] = (),
) -> list[Diagnostic]:
    """Programmatic entry point (used by the tests and the CLI)."""
    checker = TraceChecker(
        chain, selected_layers=selected, complete=complete, allow_unselected=allow_unselected
    )
    return checker.check()


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
