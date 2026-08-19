"""
Render a requirement chain as a document.

The requirement files are the authoring surface: YAML, one container per file,
statements keyed by number (see ``docs/README.md``). They are not a reading
surface -- a reviewer following a trace matrix reads ``hlr_6_pedestrian.5`` and
has to open the file and count keys to learn what the requirement says.

This module renders the chain as prose instead. A requirement layer becomes one
MyST page per container, titled as the section the container's name says it is
(``hlr_5_vehicle`` reads "5. Vehicle") and holding one anchored subsection per
statement, each carrying the trace neighbourhood the chain resolved for it: what
it refines above, what covers it below, how it is verified, and any waiver or
unresolved ref. A container the names place under another
(``hlr_5_vehicle_1_left_demand`` under ``hlr_5_vehicle``) is nested beneath it, so
the layer reads as the tree its names describe. A markdown layer (the CONOPS) is
carried through as its author wrote it, with an anchor planted in each leaf and a
closing table naming what realizes it. Given a source root, the sources those
requirements cite are listed too, so the evidence below the requirements -- an
entity, a contract, a test routine -- links to its own line.

The output is *generated evidence*, consumed by the verification-report
generator the way it consumes the trace matrices: pages plus an ``index.json``
naming every node's page and anchor, so a consumer links to the requirement text
without knowing how an anchor is spelled. The index names each layer's top-level
containers as well, because that is where the consumer's own table of contents
starts; the nesting below them is carried by the pages themselves.

The neighbourhood comes from `TraceChecker.view`, so what the document shows and
what the traceability gate checks are one analysis.
"""

from __future__ import annotations

import json
import re
from contextlib import suppress
from dataclasses import dataclass
from pathlib import Path
from typing import TYPE_CHECKING, Any

from reqs.checks.trace import (
    MARKDOWN_LEAVES,
    REQUIREMENT_YAML,
    TraceChecker,
    parent_ref_id,
    ref_field_header,
)
from reqs.conops import ConopsSet
from reqs.requirement_set import RequirementSet, parse_req_id

if TYPE_CHECKING:
    from collections.abc import Iterable, Iterator

    from reqs.checks.trace import Layer, NodeView
    from reqs.core import Diagnostic
    from reqs.document import Statement
    from reqs.requirement_set import RequirementFile

INDEX_SCHEMA_VERSION = 2
"""Bumped whenever the index's shape changes; a consumer must check it."""

INDEX_NAME = "index.json"
PAGES_DIR = "pages"
SOURCES_DIR = "sources"  # page subdirectory for the source listings

# Highlighting language per source suffix; anything else is listed as plain text.
_LANGUAGES = {".ads": "ada", ".adb": "ada", ".gpr": "ada", ".c": "c", ".h": "c", ".py": "python"}

# The kinds of layer this module renders as prose. The rest of the chain -- code,
# tests, tagged checks -- is linked to, never rendered as a requirement.
RENDERED_KINDS = (REQUIREMENT_YAML, MARKDOWN_LEAVES)

# A markdown leaf bullet, split so a target can be planted inside the bullet,
# above its `**<id> <marker>**` span. Inside, because a target between two
# bullets would break the run of leaves into a series of one-item lists.
_LEAF_SPAN_RE = re.compile(r"^(\s*-\s+)(\*\*[^*]+\*\*)(.*)$")

# What a statement's `verification:` method means to a reader, spelled out once.
_METHOD_GLOSS = {
    "test": "verified by test",
    "proof": "verified by proof",
    "static_check": "verified by a compile-time check",
    "review": "verified by review",
}


def anchor_of(node_id: str, prefix: str | None = None) -> str:
    """
    Return the cross-reference target a node is rendered under.

    A requirement id names its own container (`hlr_6_pedestrian.5`), so it is
    unique across the document as it stands. A markdown layer's leaf id is a bare
    section number (`4.1`), so it is qualified by its layer -- ids from different
    layers must not collide on one anchor.
    """
    return _slug(f"{prefix}-{node_id}" if prefix else node_id)


def source_page_of(slug: str) -> str:
    """Return the page a source file is listed on, under the sources directory."""
    return f"{SOURCES_DIR}/{slug}"


def source_anchor_of(slug: str, line: int) -> str:
    """Return the cross-reference target of one line of one source file."""
    return f"{slug}-l{line}"


def source_page_anchor_of(slug: str) -> str:
    """Return the cross-reference target of a source listing as a whole."""
    return f"{slug}-listing"


def source_slugs(paths: Iterable[str]) -> dict[str, str]:
    """
    Assign each source path a distinct anchor spelling.

    Slugging alone is not injective -- ``src/a-b.ads`` and ``src/a_b.ads`` reduce
    to the same thing -- and two files sharing a spelling would mean one listing
    overwriting the other and citations opening the wrong source, so a collision
    is resolved by counting rather than left to chance.
    """
    out: dict[str, str] = {}
    taken: set[str] = set()
    for path in sorted(paths):
        base = _slug(path)
        slug, n = base, 1
        while slug in taken:
            n += 1
            slug = f"{base}-{n}"
        taken.add(slug)
        out[path] = slug
    return out


def _slug(text: str) -> str:
    """Reduce an identifier to the spelling a cross-reference target is built from."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def container_segments(stem: str) -> tuple[str, list[list[str]]]:
    """
    Split a container stem into its level prefix and its numbered segments.

    A container names its place in the layer: ``hlr_5_vehicle_1_left_demand`` is
    the first elaboration of the fifth section, under the ``hlr`` level. Each
    segment starts at a number, so ``[["5", "vehicle"], ["1", "left", "demand"]]``
    -- the last segment names the container and the ones before it name what it
    sits under. A stem that does not follow the convention has no segments; it is
    then rendered under its own name, at the top of its layer.
    """
    parts = stem.split("_")
    segments: list[list[str]] = []
    prefix: list[str] = []
    for part in parts:
        if part.isdigit():
            segments.append([part])
        elif segments:
            segments[-1].append(part)
        else:
            prefix.append(part)
    return "_".join(prefix), segments


def container_title(stem: str) -> str:
    """
    Return the heading a container is rendered under: "5. Vehicle" for `hlr_5_vehicle`.

    The number and words come from the container's last segment, since the ones
    before it are the containers it is nested under and are already headings of
    their own. A stem the convention does not fit is its own title: inventing a
    prettier name for it would hide which file the reader is looking at.
    """
    _, segments = container_segments(stem)
    if not segments:
        return stem
    number, *words = segments[-1]
    if not words:
        return stem
    return f"{number}. {' '.join(_capitalized(word) for word in words)}"


def container_parent(stem: str) -> str | None:
    """Return the stem of the container this one elaborates, or None if it is top level."""
    prefix, segments = container_segments(stem)
    if not segments[1:]:
        return None
    parts = [part for segment in segments[:-1] for part in segment]
    return "_".join([prefix, *parts] if prefix else parts)


def _capitalized(word: str) -> str:
    """Capitalize a word for a heading, leaving any capitals it already has alone."""
    return word[:1].upper() + word[1:]


def page_of(node_id: str) -> str:
    """Return the page a statement is rendered on: its container, which owns the file."""
    parsed = parse_req_id(node_id)
    return parsed[0] if parsed is not None else node_id


@dataclass(frozen=True)
class RunInfo:
    """How one render was produced, recorded in its index for the reader."""

    command: str | None = None
    generated_at: str | None = None


@dataclass(frozen=True)
class RenderedPage:
    """One generated page: where it goes, and what is in it."""

    name: str  # path under the pages directory, without the `.md` suffix
    text: str


class DocumentRenderer:
    """
    Render a requirement corpus as pages, linked through a trace chain.

    Construction loads and analyses the chain; `pages` renders it and `index`
    describes what was rendered. A corpus that does not analyse renders
    nothing -- see `valid`.
    """

    def __init__(
        self,
        chain: list[Layer],
        *,
        selected_layers: Iterable[str] | None = None,
        source_root: Path | None = None,
    ) -> None:
        self.source_root = source_root
        self.view, self.diagnostics = TraceChecker(chain, selected_layers=selected_layers).view()
        self.rendered = [
            layer.name
            for layer in chain
            if layer.kind in RENDERED_KINDS and layer.name in self.view.nodes
        ]
        # A markdown layer's leaf ids are bare section numbers, so its anchors are
        # qualified by the layer; a requirement id already names its container.
        self.prefixes = {
            layer.name: (layer.name if layer.kind == MARKDOWN_LEAVES else None) for layer in chain
        }
        # Layers a statement names itself (`implemented_by` -> CODE), keyed by the
        # field that names them: their refs are rendered from the resolved side,
        # so the field and the coverage line do not say the same thing twice.
        self.down_fields = {
            layer.ref_field: layer.name
            for layer in chain
            if layer.refs_point_down and layer.ref_field and layer.name in self.view.nodes
        }
        # The layers below each rendered one, in chain order: a statement reports
        # what covers it there *and* what does not, so a gap reads as a gap
        # rather than as a line the renderer had nothing to say about.
        self.children: dict[str, list[str]] = {}
        for layer in chain:
            if (parent := self.view.parents.get(layer.name)) is not None:
                self.children.setdefault(parent, []).append(layer.name)

        # Which container elaborates which, per requirement layer: the names say
        # so (`hlr_5_vehicle_1_left_demand` under `hlr_5_vehicle`), and a name
        # whose parent is not itself a container of the layer is top level.
        self.contained: dict[str, dict[str, list[str]]] = {}
        for name in self.rendered:
            if isinstance(self.view.sets[name], ConopsSet):
                continue
            stems = [file.stem for file in self.files_of(name)]
            tree: dict[str, list[str]] = {stem: [] for stem in stems}
            for stem in stems:
                parent = container_parent(stem)
                if parent is not None and parent in tree:
                    tree[parent].append(stem)
            self.contained[name] = tree

        # Where the evidence below the requirements lives, and what cites it: the
        # source listings exist because a requirement points into them, and the
        # lines a requirement points *at* are the ones that carry an anchor.
        self.citations: dict[str, dict[int, list[str]]] = {}
        self.locations: dict[tuple[str, str], tuple[str, int]] = {}
        for name, nodes in self.view.nodes.items():
            if name in self.rendered:
                continue
            for node_id, node in nodes.items():
                # `up` is the requirements this node answers to; a node no
                # requirement reaches is not part of the traceable surface.
                if not node.up or node.file is None or node.line is None:
                    continue
                path = node.file.as_posix()
                self.citations.setdefault(path, {}).setdefault(node.line, []).append(node_id)
                self.locations[name, node_id] = (path, node.line)
        self.sources = self._read_sources()
        self._prune_citations()
        self.slugs = source_slugs(self.sources)

    @property
    def valid(self) -> bool:
        """Whether the corpus analysed; nothing is rendered when it did not."""
        return self.view.valid

    def _read_sources(self) -> dict[str, list[str]]:
        """
        Read every cited source file, keyed by its inventory-relative path.

        Only files *under* the source root are read: an inventory may name one
        outside it (the format allows absolute paths), and copying an arbitrary
        readable file into a published report is not this tool's business.

        A file that cannot be read is left out rather than fatal: the inventories
        are generated, and a stale one must not stop the requirements rendering.
        Its citations then render as plain text, exactly as an unlisted layer's do.
        """
        if self.source_root is None:
            return {}
        root = self.source_root.resolve()
        out: dict[str, list[str]] = {}
        for path in sorted(self.citations):
            candidate = (root / path).resolve()
            if not candidate.is_relative_to(root):
                continue
            try:
                text = candidate.read_text(encoding="utf-8")
            except OSError:
                continue
            out[path] = text.splitlines()
        return out

    def _prune_citations(self) -> None:
        """
        Drop citations of lines the file being listed does not have.

        The inventories are generated from the sources, so a citation past the end
        of one means they have drifted apart. The line cannot be anchored, so the
        citation is forgotten here rather than left to promise a link the listing
        never defines; that evidence renders as plain text instead.
        """
        for path, lines in self.sources.items():
            stale = [line for line in self.citations[path] if line > len(lines)]
            for line in stale:
                del self.citations[path][line]
        self.locations = {
            key: (path, line)
            for key, (path, line) in self.locations.items()
            if path not in self.sources or line in self.citations[path]
        }

    def files_of(self, layer: str) -> Iterator[RequirementFile]:
        """Yield the containers of a requirement layer, in file order."""
        node_set = self.view.sets[layer]
        if not isinstance(node_set, RequirementSet):
            msg = f"layer {layer!r} is not a requirement-YAML layer"
            raise TypeError(msg)
        yield from node_set

    def pages(self) -> list[RenderedPage]:
        """Render every rendered layer's pages, in chain order and then file order."""
        out: list[RenderedPage] = []
        for layer in self.rendered:
            if isinstance(self.view.sets[layer], ConopsSet):
                out.append(self._leaves_page(layer))
            else:
                out.extend(self._page(layer, file) for file in self.files_of(layer))
        out.extend(self._source_pages())
        return out

    def pages_of(self, layer: str) -> list[str]:
        """Return the page names a layer renders as, in file order."""
        node_set = self.view.sets[layer]
        if isinstance(node_set, ConopsSet):
            return [node_set.path.stem]
        return [file.stem for file in self.files_of(layer)]

    def roots_of(self, layer: str) -> list[str]:
        """
        Return the layer's top-level pages, in file order.

        A consumer builds its table of contents from these: the containers nested
        under them are named by their parent's own page, so listing every page
        would enter the nested ones twice.
        """
        tree = self.contained.get(layer)
        if tree is None:
            return self.pages_of(layer)
        nested = {stem for children in tree.values() for stem in children}
        return [stem for stem in tree if stem not in nested]

    def anchor(self, layer: str, node_id: str) -> str:
        """Return the anchor a node of `layer` is rendered under."""
        return anchor_of(node_id, self.prefixes.get(layer))

    def page(self, layer: str, node_id: str) -> str:
        """Return the page a node of `layer` is rendered on."""
        node_set = self.view.sets[layer]
        return node_set.path.stem if isinstance(node_set, ConopsSet) else page_of(node_id)

    def index(self, run: RunInfo | None = None) -> dict[str, Any]:
        """
        Describe the render: which pages exist, and where each statement sits.

        The consumer linking to a statement reads its page and anchor from here
        rather than deriving them, so how an anchor is spelled stays this
        module's business.
        """
        run = run or RunInfo()
        return {
            "schema_version": INDEX_SCHEMA_VERSION,
            "command": run.command,
            "generated_at": run.generated_at,
            "corpus_valid": self.view.valid,
            "layers": [
                {
                    "name": layer,
                    "kind": self.view.layers[layer].kind,
                    "pages": self.pages_of(layer),
                    "roots": self.roots_of(layer),
                }
                for layer in self.rendered
            ],
            "nodes": {
                layer: {
                    node_id: {
                        "page": self.page(layer, node_id),
                        "anchor": self.anchor(layer, node_id),
                        "text": text,
                    }
                    for node_id, text in self._texts(layer)
                }
                for layer in self.rendered
            }
            | self._source_nodes(),
            "sources": [
                {"page": self.source_page(path), "path": path} for path in sorted(self.sources)
            ],
        }

    def _source_nodes(self) -> dict[str, dict[str, dict[str, str]]]:
        """Index the cited evidence: which listing line each node of it is rendered at."""
        out: dict[str, dict[str, dict[str, str]]] = {}
        for (layer, node_id), (path, line) in self.locations.items():
            if path not in self.sources:
                continue
            out.setdefault(layer, {})[node_id] = {
                "page": self.source_page(path),
                "anchor": self.source_anchor(path, line),
                "text": f"{path}:{line}",
            }
        return out

    def write(self, out: Path, run: RunInfo | None = None) -> list[RenderedPage]:
        """Write the pages and the index under `out`, returning what was written."""
        pages = self.pages()
        pages_dir = out / PAGES_DIR
        pages_dir.mkdir(parents=True, exist_ok=True)
        for page in pages:
            target = pages_dir / f"{page.name}.md"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(page.text, encoding="utf-8")
        index = self.index(run)
        (out / INDEX_NAME).write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
        return pages

    def _texts(self, layer: str) -> Iterator[tuple[str, str]]:
        """Yield every node of a rendered layer as (id, its one-line text)."""
        node_set = self.view.sets[layer]
        if isinstance(node_set, ConopsSet):
            lines = node_set.path.read_text(encoding="utf-8").splitlines()
            for node_id, leaf in node_set.all_statements():
                yield node_id, _flat(_leaf_prose(lines[leaf.line - 1]))
            return
        for file in self.files_of(layer):
            for number, statement in file.description.items():
                yield f"{file.stem}.{number}", _flat(statement.text)

    def _page(self, layer: str, file: RequirementFile) -> RenderedPage:
        """Render one container: what it is, its document-level prose, then every statement."""
        parts = [
            f"({anchor_of(file.stem)})=",
            f"# {container_title(file.stem)}",
            self._identity(file),
            _preamble(file),
        ]
        parts += [
            self._statement(layer, f"{file.stem}.{number}", statement)
            for number, statement in file.description.items()
        ]
        parts.append(self._contained_toc(layer, file.stem))
        return RenderedPage(name=file.stem, text="\n\n".join(p for p in parts if p) + "\n")

    def _identity(self, file: RequirementFile) -> str:
        """
        Name the container the page renders, and the file it is authored in.

        The heading is the container's section title, so the container id -- what
        a matrix cites and what a statement id is built from -- is said here
        instead, next to the file a reviewer would edit to change any of it.
        """
        path = file.path
        if self.source_root is not None:
            with suppress(ValueError):
                path = path.resolve().relative_to(self.source_root.resolve())
        return f"Container `{file.stem}`, authored in `{path.as_posix()}`."

    def _contained_toc(self, layer: str, stem: str) -> str:
        """Enter the containers nested under this one, so they hang off its page."""
        children = self.contained.get(layer, {}).get(stem, [])
        if not children:
            return ""
        entries = "\n".join(children)
        return (
            "## Sections\n\n"
            "The containers this one's name places under it. Each of their "
            "statements traces upward on its own: the nesting says how the layer "
            "is organized, not what refines what.\n\n"
            f"```{{toctree}}\n:maxdepth: 1\n\n{entries}\n```"
        )

    def _source_pages(self) -> list[RenderedPage]:
        """Render one page per cited source file, in path order."""
        return [self._source_page(path, lines) for path, lines in sorted(self.sources.items())]

    def source_page(self, path: str) -> str:
        """Return the page a cited source file is listed on."""
        return source_page_of(self.slugs[path])

    def source_anchor(self, path: str, line: int) -> str:
        """Return the anchor one cited line of one source file is rendered under."""
        return source_anchor_of(self.slugs[path], line)

    def _source_page(self, path: str, lines: list[str]) -> RenderedPage:
        """
        List one source file whole, split so each cited line can be a target.

        A target has to attach to something a reader's renderer will draw: the
        PDF builder resolves one on a paragraph or a heading, but not one on a
        code block. So each cited line is introduced by a paragraph that carries
        its anchor and says what cites it, and the listing follows.

        The listings themselves are marked HTML-only -- they are a browsing aid,
        not part of the argument, and thousands of lines of source do not belong
        in a printed report. Their anchors are not: a link that resolves in one
        rendering and dangles in the other is a broken document.
        """
        cited = sorted(self.citations.get(path, {}))
        language = _LANGUAGES.get(Path(path).suffix, "text")
        blocks: list[str] = []
        for start, end in _spans(cited, len(lines)):
            listing = _html_only(
                _fenced(
                    language,
                    f":lineno-start: {start}\n"
                    + (":emphasize-lines: 1\n" if start in cited else ""),
                    "\n".join(lines[start - 1 : end]),
                )
            )
            if start not in cited:
                blocks.append(listing)
                continue
            citers = ", ".join(f"`{node}`" for node in self.citations[path][start])
            blocks.append(
                f"({self.source_anchor(path, start)})=\n\n"
                f"**Line {start}** -- cited by {citers}\n\n{listing}"
            )
        return RenderedPage(
            name=self.source_page(path),
            text=(
                f"({source_page_anchor_of(self.slugs[path])})=\n"
                f"# {path}\n\n"
                f"{_count(len(cited), 'line')} of this file "
                f"{'is' if len(cited) == 1 else 'are'} cited by the requirements; the "
                f"listing below each is the file from that line on. The source is "
                f"listed in the HTML rendering only.\n\n" + "\n\n".join(blocks) + "\n"
            ),
        )

    def _leaves_page(self, layer: str) -> RenderedPage:
        """
        Render a markdown layer: the document as written, with its leaves anchored.

        The CONOPS is already a document -- a narrative a human wrote, with prose
        and tables between its leaves -- so it is carried through as it is rather
        than rebuilt from its leaves. What is added is an anchor per leaf, so the
        requirements above can link to the statement they refine, and a closing
        table of what realizes each leaf, so the navigation runs both ways here
        as it does on every other page.
        """
        node_set = self.view.sets[layer]
        if not isinstance(node_set, ConopsSet):  # pragma: no cover - dispatched on the kind
            msg = f"layer {layer!r} is not a markdown-leaves layer"
            raise TypeError(msg)
        lines = node_set.path.read_text(encoding="utf-8").splitlines()
        unanchored: list[str] = []
        for node_id, leaf in node_set.all_statements():
            index = leaf.line - 1
            anchored = _anchor_leaf(lines[index], self.anchor(layer, node_id))
            if anchored is None:
                # The bullet is not shaped as expected, so the anchor goes on the
                # line before it: it breaks the run of leaves into separate lists,
                # which is cosmetic, where a missing anchor would be a dead link.
                unanchored.append(node_id)
                lines[index] = f"({self.anchor(layer, node_id)})=\n{lines[index]}"
            else:
                lines[index] = anchored
        body = "\n".join(lines).rstrip()
        return RenderedPage(name=node_set.path.stem, text=f"{body}\n\n{self._realization(layer)}")

    def _realization(self, layer: str) -> str:
        """Render the closing tables: what realizes each leaf of a markdown layer."""
        tables = [self._realization_table(layer, lower) for lower in self.children.get(layer, [])]
        if not tables:
            return ""
        return (
            "# Realization\n\nWhich statement below realizes each leaf above. A leaf "
            "realized by nothing is either work not yet done or a deliberate "
            "exclusion, and says which.\n\n" + "\n\n".join(tables) + "\n"
        )

    def _realization_table(self, layer: str, lower: str) -> str:
        """Render one layer below's realization of every leaf, as a table."""
        rows: list[str] = []
        for node_id, view in self.view.nodes[layer].items():
            covering = ", ".join(self._down_ref(lower, i) for i in view.down.get(lower, ()))
            excuse = f"*waived* -- {_flat(view.waiver)}" if view.waiver else "*nothing yet*"
            rows.append(f"| [`{node_id}`](#{self.anchor(layer, node_id)}) | {covering or excuse} |")
        return "\n".join([f"| Leaf | Realized by ({lower}) |", "|---|---|", *rows])

    def _statement(self, layer: str, node_id: str, statement: Statement) -> str:
        """Render one statement: its anchor, its text, then its neighbourhood."""
        view = self.view.nodes[layer].get(node_id)
        trace = "\n".join(
            f"- **{label}:** {value}" for label, value in self._trace(layer, statement, view)
        )
        anchor = self.anchor(layer, node_id)
        return f"({anchor})=\n## {node_id}\n\n{statement.text.strip()}\n\n{trace}"

    def _trace(
        self, layer: str, statement: Statement, view: NodeView | None
    ) -> Iterator[tuple[str, str]]:
        """Yield the statement's trace neighbourhood, one label/value pair per line."""
        yield from self._upward(layer, statement)
        for field in statement.down_ref_fields:
            # Rendered below from the resolved side, where the layer is in view;
            # as written when it is not, so the statement's own content survives
            # a render of the requirement layers alone.
            if self.down_fields.get(field) is None and (refs := statement.down_refs_in(field)):
                yield ref_field_header(field), ", ".join(f"`{r}`" for r in refs)
        if methods := statement.verification_methods:
            yield "Verification", ", ".join(_method(statement, m) for m in methods)
        if view is not None:
            yield from self._downward(layer, statement, view)
            if view.dangling:
                unresolved = ", ".join(f"`{r}`" for r in view.dangling)
                yield "Dangling", f"{unresolved} (resolves to nothing)"
            if view.waiver:
                yield "Waived", _flat(view.waiver)

    def _upward(self, layer: str, statement: Statement) -> Iterator[tuple[str, str]]:
        """Yield the statement's parent refs, linked where the parent is rendered."""
        label = "Source" if statement.up_ref_key == "source" else "Parent"
        if statement.is_derived:
            yield label, "*derived* -- no parent above it, by declaration"
            return
        if refs := statement.up_refs:
            yield label, ", ".join(self._up_ref(layer, ref) for ref in refs)

    def _up_ref(self, layer: str, ref: str) -> str:
        """Render one parent ref: as written, linked to the node it names."""
        parent = self.view.parents.get(layer)
        target = parent_ref_id(self.view.layers[layer], ref) if parent else None
        if parent is not None and target is not None and self._is_rendered(parent, target):
            return f"[`{ref}`](#{self.anchor(parent, target)})"
        return f"`{ref}`"

    def _downward(
        self, layer: str, statement: Statement, view: NodeView
    ) -> Iterator[tuple[str, str]]:
        """Yield one line per layer below, naming what covers this node there."""
        by_layer = {name: field for field, name in self.down_fields.items()}
        for lower in self.children.get(layer, []):
            ids = view.down.get(lower, ())
            method = self.view.layers[lower].method
            # A method layer speaks only for the statements declaring its method:
            # an LLR verified by test alone is not missing proof evidence. A
            # citation from one anyway is a gap the gate reports, so it shows.
            if method is not None and method not in statement.verification_methods and not ids:
                continue
            covering = ", ".join(self._down_ref(lower, i) for i in ids)
            # A layer the statement names itself is labelled by the field that
            # names it; one that cites the statement is labelled by coverage.
            label = (
                ref_field_header(by_layer[lower]) if lower in by_layer else f"Covered by ({lower})"
            )
            yield label, covering or "*nothing yet*"

    def _down_ref(self, layer: str, node_id: str) -> str:
        """Render one covering node: linked to its statement, or to its source line."""
        if self._is_rendered(layer, node_id):
            return f"[`{node_id}`](#{self.anchor(layer, node_id)})"
        if (located := self.locations.get((layer, node_id))) is not None:
            path, line = located
            if path in self.sources:
                where = f"{path}:{line}"
                # A check node is named by its location, so naming it twice says
                # nothing; anything else is worth locating for the reader.
                suffix = "" if node_id == where else f" ({where})"
                return f"[`{node_id}`](#{self.source_anchor(path, line)}){suffix}"
        return f"`{node_id}`"

    def _is_rendered(self, layer: str | None, node_id: str) -> bool:
        """Whether a node has a rendered subsection to link to."""
        return layer in self.rendered and node_id in self.view.nodes[layer]


def _spans(boundaries: list[int], last: int) -> Iterator[tuple[int, int]]:
    """Yield the 1-based (start, end) line spans of a file split at `boundaries`."""
    starts = sorted({1, *(b for b in boundaries if 1 < b <= last)})
    for index, start in enumerate(starts):
        yield start, (starts[index + 1] - 1 if index + 1 < len(starts) else last)


def _count(n: int, noun: str) -> str:
    """Render a count with its naively pluralized noun ("1 line", "2 lines")."""
    return f"{n} {noun}" + ("" if n == 1 else "s")


def _html_only(body: str) -> str:
    """Wrap a block so only the HTML rendering carries it."""
    return f":::{{only}} html\n\n{body}\n\n:::"


def _fenced(language: str, options: str, body: str) -> str:
    """Render a code-block directive, its fence sized past any backtick run inside."""
    longest = max((len(run) for run in re.findall(r"`+", body)), default=0)
    fence = "`" * max(3, longest + 1)
    return f"{fence}{{code-block}} {language}\n{options}\n{body}\n{fence}"


def _anchor_leaf(line: str, anchor: str) -> str | None:
    """
    Plant `anchor` inside a leaf bullet, above its text; None if it is not one.

    A block target as the bullet's first block, rather than an inline attribute
    on its text: an inline target is not a destination the PDF builder can
    resolve, and a target *between* bullets would end the list. This keeps the
    run of leaves one list and puts the anchor on the leaf's own paragraph, at
    the cost of rendering that list loose.
    """
    m = _LEAF_SPAN_RE.match(line)
    if m is None:
        return None
    indent = " " * len(m.group(1))
    return f"{m.group(1)}({anchor})=\n\n{indent}{m.group(2)}{m.group(3)}"


def _leaf_prose(line: str) -> str:
    """Return a leaf bullet's prose: what follows its id-and-marker span."""
    m = _LEAF_SPAN_RE.match(line)
    return m.group(3).strip() if m else line.lstrip("- ").strip()


def _preamble(file: RequirementFile) -> str:
    """Render the container's document-level prose, in authoring order."""
    sections: list[tuple[str, str | None]] = [
        ("Context", file.context),
        ("Visibility", getattr(file, "visibility", None)),
        ("Preconditions", _bullets(getattr(file, "preconditions", None))),
        ("Algorithm aspects", getattr(file, "algorithm_aspects", None)),
        ("Rationale", file.rationale),
    ]
    # Sibling sections of the statements below them: both are parts of the
    # container, and a jump past a heading level is a malformed document.
    return "\n\n".join(f"## {title}\n\n{body.strip()}" for title, body in sections if body)


def _bullets(items: list[str] | None) -> str | None:
    """Render a list-valued field as markdown bullets."""
    return "\n".join(f"- {item.strip()}" for item in items) if items else None


def _method(statement: Statement, method: str) -> str:
    """Render one verification method, with its justification when it has one."""
    gloss = _METHOD_GLOSS.get(method, method)
    if justification := statement.justification_for(method):
        return f"{gloss} ({_flat(justification)})"
    return gloss


def _flat(text: str) -> str:
    """Collapse prose to one line, for a trace line or an index entry."""
    return " ".join(text.split())


def render_document(
    chain: list[Layer],
    out: Path,
    *,
    selected_layers: Iterable[str] | None = None,
    source_root: Path | None = None,
    run: RunInfo | None = None,
) -> tuple[list[RenderedPage], list[Diagnostic], bool]:
    """
    Render a chain's requirement layers into `out`.

    Returns ``(pages, diagnostics, valid)``. Nothing is written when the corpus
    does not analyse: a document whose every link is silently absent would
    misrepresent a corpus that simply failed to load.
    """
    renderer = DocumentRenderer(chain, selected_layers=selected_layers, source_root=source_root)
    if not renderer.valid:
        return [], renderer.diagnostics, False
    pages = renderer.write(out, run)
    return pages, renderer.diagnostics, True
