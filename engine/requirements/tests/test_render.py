"""
Tests for the document renderer (reqs.render).

The renderer turns the requirement corpus into pages a reviewer can read: one
per container, one anchored subsection per statement, each carrying its trace
neighbourhood as links. What is checked here is that the *document says what the
chain says* -- a link exists exactly where the analysis resolved a ref, a gap
reads as a gap, and the index names the anchor the pages actually carry, since a
consumer links through the index rather than by guessing.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING

import pytest
from inventory_fixture import package, subprogram, write_inventory
from test_trace import (
    conops_layer,
    hlr_layer,
    llr_layer,
    make_code_layer,
    make_proof_layer,
    make_test_layer,
    write_checks,
    write_conops,
    write_req,
    write_tests,
    write_waivers,
)
from typer.testing import CliRunner

from reqs.checks.trace import Layer
from reqs.cli import app
from reqs.render import (
    INDEX_NAME,
    INDEX_SCHEMA_VERSION,
    DocumentRenderer,
    RenderedPage,
    anchor_of,
    container_parent,
    container_title,
    source_slugs,
)

if TYPE_CHECKING:
    from pathlib import Path

runner = CliRunner()


def req_chain(tmp_path: Path) -> list[Layer]:
    """Build a CONOPS -> HLR -> LLR chain over a small fixture corpus."""
    hlr_dir = tmp_path / "hlr"
    llr_dir = tmp_path / "llr"
    hlr_dir.mkdir()
    llr_dir.mkdir()
    write_req(hlr_dir, "hlr_a.yaml", "source", [["CONOPS §1.1"], ["CONOPS §2.1"], None])
    write_req(llr_dir, "llr_a.yaml", "parent_req", [["hlr_a.1"], ["hlr_a.9"]], ["test", "review"])
    return [conops_layer(write_conops(tmp_path)), hlr_layer(hlr_dir), llr_layer(llr_dir)]


def page_text(pages: list[RenderedPage], name: str) -> str:
    """Return the text of the rendered page called `name`."""
    return next(page.text for page in pages if page.name == name)


def test_one_page_per_container_with_anchored_statements(tmp_path: Path) -> None:
    """Each container renders as a page whose statements carry cross-reference targets."""
    pages = DocumentRenderer(req_chain(tmp_path)).pages()

    assert [page.name for page in pages] == ["conops", "hlr_a", "llr_a"]
    hlr = page_text(pages, "hlr_a")
    assert "# hlr_a" in hlr
    assert "(hlr-a-1)=\n## hlr_a.1" in hlr
    assert "The system shall do thing 1." in hlr


def test_up_refs_link_to_the_rendered_parent(tmp_path: Path) -> None:
    """An LLR's parent_req links to the HLR statement it resolves to."""
    llr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "llr_a")

    assert f"- **Parent:** [`hlr_a.1`](#{anchor_of('hlr_a.1')})" in llr


def test_up_refs_to_an_unrendered_layer_stay_plain(tmp_path: Path) -> None:
    """With the CONOPS out of the chain, an HLR's source is shown as written."""
    chain = req_chain(tmp_path)
    hlr = page_text(DocumentRenderer(chain, selected_layers=["HLR", "LLR"]).pages(), "hlr_a")

    assert "- **Source:** `CONOPS §1.1`" in hlr


def test_a_dangling_ref_is_rendered_as_dangling(tmp_path: Path) -> None:
    """A parent_req resolving to nothing is shown, not silently dropped."""
    llr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "llr_a")

    assert "- **Dangling:** `hlr_a.9` (resolves to nothing)" in llr


def test_a_derived_statement_says_so(tmp_path: Path) -> None:
    """A statement marked derived reads as derived rather than as missing a parent."""
    hlr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "hlr_a")

    assert "- **Source:** *derived*" in hlr


def test_coverage_is_rendered_in_both_directions(tmp_path: Path) -> None:
    """A covered HLR names its covering LLR, linked; an uncovered one names the gap."""
    pages = DocumentRenderer(req_chain(tmp_path)).pages()
    hlr = page_text(pages, "hlr_a")

    assert f"- **Covered by (LLR):** [`llr_a.1`](#{anchor_of('llr_a.1')})" in hlr
    # hlr_a.2 is covered by nothing: the line is still rendered, as the gap.
    assert "- **Covered by (LLR):** *nothing yet*" in hlr


def test_verification_methods_carry_their_justification(tmp_path: Path) -> None:
    """A review entry renders its justification; a machine method renders alone."""
    llr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "llr_a")

    assert "- **Verification:** verified by test" in llr
    assert "- **Verification:** verified by review (fixture)" in llr


def test_a_waiver_is_rendered_on_the_node_it_excuses(tmp_path: Path) -> None:
    """A waived statement's excuse reaches the reader beside the gap it excuses."""
    chain = req_chain(tmp_path)
    waivers = write_waivers(tmp_path, "waivers.yaml", [("hlr_a.2", "out of scope for the demo")])
    chain[1] = hlr_layer(chain[1].path, waivers=waivers)
    hlr = page_text(DocumentRenderer(chain).pages(), "hlr_a")

    assert "- **Covered by (LLR):** *nothing yet*\n- **Waived:** out of scope for the demo" in hlr


def test_the_index_names_the_anchors_the_pages_carry(tmp_path: Path) -> None:
    """Every indexed anchor exists as a target in the page the index names."""
    renderer = DocumentRenderer(req_chain(tmp_path))
    pages = {page.name: page.text for page in renderer.pages()}
    index = renderer.index()

    assert index["schema_version"] == INDEX_SCHEMA_VERSION
    assert index["corpus_valid"] is True
    assert [layer["name"] for layer in index["layers"]] == ["CONOPS", "HLR", "LLR"]
    for nodes in index["nodes"].values():
        for node_id, entry in nodes.items():
            page = pages[entry["page"]]
            # Either MyST target form: a block target, or an inline attribute.
            block, inline = f"({entry['anchor']})=", f"{{#{entry['anchor']}}}"
            assert block in page or inline in page, node_id
            assert entry["text"]


def test_the_index_spells_out_the_layers_the_chain_gave_a_title(tmp_path: Path) -> None:
    """A consumer heading a section with a layer reads its title, name if it has none."""
    chain = req_chain(tmp_path)
    chain[0] = Layer("CONOPS", "markdown-leaves", chain[0].path, title="Concept of Operations")
    index = DocumentRenderer(chain).index()

    assert {layer["name"]: layer["title"] for layer in index["layers"]} == {
        "CONOPS": "Concept of Operations",
        "HLR": "HLR",
        "LLR": "LLR",
    }


def test_statements_render_their_container_prose(tmp_path: Path) -> None:
    """The container's document-level fields are rendered above its statements."""
    chain = req_chain(tmp_path)
    llr_file = chain[2].path / "llr_a.yaml"
    llr_file.write_text(
        "context: How this unit realizes it.\n"
        "visibility: Controller\n"
        "preconditions:\n"
        "  - The bus is initialized.\n"
        "algorithm_aspects: A single pass.\n"
        "rationale: Because the HLR says so.\n" + llr_file.read_text(encoding="utf-8"),
        encoding="utf-8",
    )
    llr = page_text(DocumentRenderer(chain).pages(), "llr_a")

    assert "## Context\n\nHow this unit realizes it." in llr
    assert "## Visibility\n\nController" in llr
    assert "## Preconditions\n\n- The bus is initialized." in llr
    assert "## Algorithm aspects\n\nA single pass." in llr
    assert "## Rationale\n\nBecause the HLR says so." in llr


def test_a_down_ref_field_renders_from_the_resolved_side(tmp_path: Path) -> None:
    """With CODE in the chain, `implemented_by` is rendered once, canonically."""
    chain = req_chain(tmp_path)
    llr_dir = chain[2].path
    write_req(llr_dir, "llr_a.yaml", "parent_req", [["hlr_a.1"]], ["test"])
    llr_file = llr_dir / "llr_a.yaml"
    llr_file.write_text(
        llr_file.read_text(encoding="utf-8") + "    implemented_by:\n      - controller.step\n",
        encoding="utf-8",
    )
    inventory = tmp_path / "code_inventory.json"
    write_inventory(
        inventory,
        packages=[
            package(
                "Controller",
                spec_file="src/controller.ads",
                subprograms=[
                    subprogram(
                        "Step",
                        qualified_name="Controller.Step",
                        file="src/controller.ads",
                        line=10,
                    )
                ],
            )
        ],
    )
    chain.append(make_code_layer(inventory))
    llr = page_text(DocumentRenderer(chain).pages(), "llr_a")

    # Canonical spelling, from the entity, not the ref's casing -- and once.
    assert "- **Implemented by:** `Controller.Step`" in llr
    assert llr.count("Implemented by") == 1


def test_a_down_ref_field_renders_as_written_without_its_layer(tmp_path: Path) -> None:
    """Without CODE in the chain, `implemented_by` still reaches the reader."""
    chain = req_chain(tmp_path)
    llr_dir = chain[2].path
    write_req(llr_dir, "llr_a.yaml", "parent_req", [["hlr_a.1"]], ["test"])
    llr_file = llr_dir / "llr_a.yaml"
    llr_file.write_text(
        llr_file.read_text(encoding="utf-8") + "    implemented_by:\n      - Controller.Step\n",
        encoding="utf-8",
    )
    llr = page_text(DocumentRenderer(chain).pages(), "llr_a")

    assert "- **Implemented by:** `Controller.Step`" in llr


def test_a_method_layer_speaks_only_for_the_statements_declaring_it(tmp_path: Path) -> None:
    """A test-verified statement is not reported as missing proof evidence."""
    chain = req_chain(tmp_path)
    llr_dir = chain[2].path
    write_req(llr_dir, "llr_a.yaml", "parent_req", [["hlr_a.1"]], ["test"])
    chain.append(
        make_test_layer(write_tests(tmp_path, "llr_a", {"Test_1": ["llr_a.1"]}), method="test")
    )
    llr = page_text(DocumentRenderer(chain).pages(), "llr_a")

    assert "Covered by (TEST)" in llr
    assert "PROOF" not in llr


def test_an_invalid_corpus_renders_nothing(tmp_path: Path) -> None:
    """A corpus that does not analyse yields no pages and no index."""
    chain = req_chain(tmp_path)
    (chain[1].path / "hlr_a.yaml").write_text("description: not a mapping\n", encoding="utf-8")
    renderer = DocumentRenderer(chain)

    assert renderer.valid is False
    assert any(d.level == "error" for d in renderer.diagnostics)


def test_cli_writes_pages_and_index(tmp_path: Path) -> None:
    """`reqs document` writes the pages and the index, and reports what it wrote."""
    chain_file = tmp_path / "chain.yaml"
    req_chain(tmp_path)
    chain_file.write_text(
        "layers:\n"
        "  - name: CONOPS\n    kind: markdown-leaves\n    path: conops.md\n"
        "  - name: HLR\n    kind: requirement-yaml\n    path: hlr\n"
        "    id_pattern: 'CONOPS §(\\d+\\.\\d+)'\n"
        "  - name: LLR\n    kind: requirement-yaml\n    path: llr\n"
        "    id_pattern: '(.+\\.\\d+)'\n",
        encoding="utf-8",
    )
    out = tmp_path / "out"
    result = runner.invoke(app, ["document", "--chain", str(chain_file), "--out", str(out)])

    assert result.exit_code == 0, result.output
    assert "3 page(s) written" in result.output
    assert (out / "pages" / "hlr_a.md").is_file()
    index = json.loads((out / INDEX_NAME).read_text(encoding="utf-8"))
    assert index["nodes"]["HLR"]["hlr_a.1"]["page"] == "hlr_a"
    assert "reqs document --chain" in index["command"]


def test_cli_fails_on_a_corpus_that_does_not_analyse(tmp_path: Path) -> None:
    """A broken corpus exits non-zero and writes no document."""
    chain_file = tmp_path / "chain.yaml"
    req_chain(tmp_path)
    (tmp_path / "hlr" / "hlr_a.yaml").write_text("description: 3\n", encoding="utf-8")
    chain_file.write_text(
        "layers:\n"
        "  - name: HLR\n    kind: requirement-yaml\n    path: hlr\n"
        "  - name: LLR\n    kind: requirement-yaml\n    path: llr\n"
        "    id_pattern: '(.+\\.\\d+)'\n",
        encoding="utf-8",
    )
    out = tmp_path / "out"
    result = runner.invoke(app, ["document", "--chain", str(chain_file), "--out", str(out)])

    assert result.exit_code != 0
    assert not (out / INDEX_NAME).exists()


def test_cli_rejects_an_unknown_layer(tmp_path: Path) -> None:
    """A misspelled --layers name is reported, not silently rendered smaller."""
    chain_file = tmp_path / "chain.yaml"
    req_chain(tmp_path)
    chain_file.write_text(
        "layers:\n  - name: HLR\n    kind: requirement-yaml\n    path: hlr\n", encoding="utf-8"
    )
    result = runner.invoke(
        app,
        ["document", "--chain", str(chain_file), "--out", str(tmp_path / "o"), "--layers", "HRL"],
    )

    assert result.exit_code != 0
    assert "E-TRACE-LAYER" in result.output


@pytest.mark.parametrize(
    ("node_id", "expected"),
    [
        ("hlr_a.1", "hlr-a-1"),
        ("llr_4_controller_3_pedestrian.12", "llr-4-controller-3-pedestrian-12"),
    ],
)
def test_anchor_of_is_a_stable_slug(node_id: str, expected: str) -> None:
    """Anchors are slugs of the id: what the index records is what the page carries."""
    assert anchor_of(node_id) == expected


# --- containers read as the sections their names say they are -----------------


@pytest.mark.parametrize(
    ("stem", "title"),
    [
        ("hlr_0_safety", "0. Safety"),
        ("llr_5_core_loop", "5. Core Loop"),
        ("hlr_5_vehicle_1_left_demand", "1. Left Demand"),  # the last segment only
        ("hlr_a", "hlr_a"),  # no numbered segment: its own name, unprettified
        ("hlr_5", "hlr_5"),  # a number with nothing to name
    ],
)
def test_container_title_names_the_section(stem: str, title: str) -> None:
    """A container's heading is the section its name says it is."""
    assert container_title(stem) == title


@pytest.mark.parametrize(
    ("stem", "parent"),
    [
        ("hlr_5_vehicle_1_left_demand", "hlr_5_vehicle"),
        ("llr_4_controller_3_pedestrian", "llr_4_controller"),
        ("hlr_5_vehicle", None),
        ("hlr_a", None),
    ],
)
def test_container_parent_follows_the_name(stem: str, parent: str | None) -> None:
    """Nesting is what the names say: a further segment is a container below."""
    assert container_parent(stem) == parent


def nested_chain(tmp_path: Path) -> list[Layer]:
    """Build an HLR layer holding a container and the container nested under it."""
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir()
    write_req(hlr_dir, "hlr_5_vehicle.yaml", "source", [["CONOPS §1.1"]])
    write_req(hlr_dir, "hlr_5_vehicle_1_left_demand.yaml", "source", [["CONOPS §2.1"]])
    write_req(hlr_dir, "hlr_6_pedestrian.yaml", "source", [["CONOPS §2.6"]])
    return [conops_layer(write_conops(tmp_path)), hlr_layer(hlr_dir)]


def test_a_container_page_is_titled_and_says_which_file_it_renders(tmp_path: Path) -> None:
    """The heading is the section title, so the id and its file are named beneath it."""
    page = page_text(
        DocumentRenderer(nested_chain(tmp_path), source_root=tmp_path).pages(), "hlr_5_vehicle"
    )

    assert "# 5. Vehicle" in page
    assert "Container `hlr_5_vehicle`, authored in `hlr/hlr_5_vehicle.yaml`." in page


def test_a_nested_container_is_entered_from_its_parents_page(tmp_path: Path) -> None:
    """The page the names place above enters the one below, so the layer reads as a tree."""
    renderer = DocumentRenderer(nested_chain(tmp_path))
    pages = renderer.pages()

    assert "hlr_5_vehicle_1_left_demand\n```" in page_text(pages, "hlr_5_vehicle")
    # Entered once: a page named by its parent must not also be named by the layer.
    assert renderer.roots_of("HLR") == ["hlr_5_vehicle", "hlr_6_pedestrian"]
    assert "toctree" not in page_text(pages, "hlr_6_pedestrian")


def test_the_index_names_each_layers_top_pages(tmp_path: Path) -> None:
    """A consumer's table of contents starts at the roots; the rest hang off them."""
    index = DocumentRenderer(nested_chain(tmp_path)).index()

    layers = {layer["name"]: layer for layer in index["layers"]}
    assert layers["HLR"]["roots"] == ["hlr_5_vehicle", "hlr_6_pedestrian"]
    assert layers["HLR"]["pages"] == [
        "hlr_5_vehicle",
        "hlr_5_vehicle_1_left_demand",
        "hlr_6_pedestrian",
    ]
    assert layers["CONOPS"]["roots"] == ["conops"]


# --- the CONOPS: a document carried through, not rebuilt ----------------------


def test_the_conops_is_rendered_as_written_with_anchored_leaves(tmp_path: Path) -> None:
    """The narrative survives verbatim; each leaf gains an inline anchor."""
    conops = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "conops")

    assert "# 1. The Intersection" in conops  # the author's own headings
    assert "Some explanatory prose, not a leaf." in conops
    assert "- (conops-1-1)=\n\n  **1.1 ◆** Four approaches meet at 90°." in conops
    assert "- not a leaf bullet" in conops  # a non-leaf bullet is left alone


def test_conops_leaf_anchors_do_not_split_the_run_of_leaves(tmp_path: Path) -> None:
    """Each anchor sits inside its bullet, so consecutive leaves stay one list."""
    conops = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "conops")

    block = conops.split("# 2. Vehicle Signals")[1]
    assert block.count("- (conops-2-") == 2
    # A target at column 0 between two bullets would end the list there.
    assert not [line for line in block.splitlines() if line.startswith("(conops-")]


def test_hlr_sources_link_to_the_conops_leaf_they_name(tmp_path: Path) -> None:
    """`CONOPS §1.1` resolves through the layer's id_pattern to the leaf's anchor."""
    hlr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "hlr_a")

    assert "- **Source:** [`CONOPS §1.1`](#conops-1-1)" in hlr


def test_the_conops_page_says_what_realizes_each_leaf(tmp_path: Path) -> None:
    """The realization table closes the loop the other pages have as links."""
    chain = req_chain(tmp_path)
    waivers = write_waivers(tmp_path, "cw.yaml", [("2.2", "negative scope")])
    chain[0] = conops_layer(chain[0].path, waivers=waivers)
    conops = page_text(DocumentRenderer(chain).pages(), "conops")

    assert "# Realization" in conops
    assert "| [`1.1`](#conops-1-1) | [`hlr_a.1`](#hlr-a-1) |" in conops
    assert "| [`2.2`](#conops-2-2) | *waived* -- negative scope |" in conops
    assert "| [`3.1`](#conops-3-1) | *nothing yet* |" in conops


def test_conops_leaves_are_indexed_with_their_prose(tmp_path: Path) -> None:
    """A leaf's index entry names its page, its qualified anchor, and its text."""
    index = DocumentRenderer(req_chain(tmp_path)).index()

    entry = index["nodes"]["CONOPS"]["1.1"]
    assert entry == {
        "page": "conops",
        "anchor": "conops-1-1",
        "text": "Four approaches meet at 90°. — *decision*",
    }


def test_the_index_records_each_layers_kind(tmp_path: Path) -> None:
    """A consumer names a layer's nodes correctly only if it knows the kind."""
    index = DocumentRenderer(req_chain(tmp_path)).index()

    assert [(layer["name"], layer["kind"]) for layer in index["layers"]] == [
        ("CONOPS", "markdown-leaves"),
        ("HLR", "requirement-yaml"),
        ("LLR", "requirement-yaml"),
    ]


def test_a_leaf_bullet_of_an_unexpected_shape_still_gets_an_anchor(tmp_path: Path) -> None:
    """A dead link is worse than a split list: the anchor goes on the line before."""
    chain = req_chain(tmp_path)
    path = chain[0].path
    path.write_text(
        path.read_text(encoding="utf-8").replace(
            "- **1.1 ◆** Four approaches meet at 90°. — *decision*", "- **1.1 Four approaches."
        ),
        encoding="utf-8",
    )
    conops = page_text(DocumentRenderer(chain).pages(), "conops")

    assert "(conops-1-1)=\n- **1.1 Four approaches." in conops


# --- the sources the requirements cite ---------------------------------------


SOURCE = """package Controller is
   --  A comment.
   procedure Step (S : in out State)
     with Post => Safe (S);
end Controller;
"""


def cited_chain(tmp_path: Path) -> list[Layer]:
    """Build a chain whose LLR names an entity, with the source on disk to list."""
    chain = req_chain(tmp_path)
    llr_dir = chain[2].path
    write_req(llr_dir, "llr_a.yaml", "parent_req", [["hlr_a.1"]], ["test"])
    llr_file = llr_dir / "llr_a.yaml"
    llr_file.write_text(
        llr_file.read_text(encoding="utf-8") + "    implemented_by:\n      - Controller.Step\n",
        encoding="utf-8",
    )
    (tmp_path / "src").mkdir(exist_ok=True)
    (tmp_path / "src" / "controller.ads").write_text(SOURCE, encoding="utf-8")
    inventory = tmp_path / "code_inventory.json"
    write_inventory(
        inventory,
        packages=[
            package(
                "Controller",
                spec_file="src/controller.ads",
                subprograms=[
                    subprogram(
                        "Step",
                        qualified_name="Controller.Step",
                        file="src/controller.ads",
                        line=3,
                    )
                ],
            )
        ],
    )
    chain.append(make_code_layer(inventory))
    return chain


def test_a_cited_source_is_listed_as_its_own_page(tmp_path: Path) -> None:
    """A file the requirements point into is listed, whole, on a page of its own."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    listing = page_text(renderer.pages(), renderer.source_page("src/controller.ads"))

    assert "# src/controller.ads" in listing
    assert "package Controller is" in listing  # the lines before the citation
    assert "procedure Step (S : in out State)" in listing
    assert "end Controller;" in listing


def test_the_cited_line_carries_the_anchor_on_a_paragraph(tmp_path: Path) -> None:
    """The anchor sits on prose, which is what a PDF builder can resolve."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    listing = page_text(renderer.pages(), renderer.source_page("src/controller.ads"))

    anchor = renderer.source_anchor("src/controller.ads", 3)
    assert f"({anchor})=\n\n**Line 3** -- " in listing


def test_a_listed_line_links_up_to_what_cites_it(tmp_path: Path) -> None:
    """The reference runs upward: the reader has the line, not the requirement on it."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    listing = page_text(renderer.pages(), renderer.source_page("src/controller.ads"))

    assert "**Line 3** -- `Controller.Step`, cited by [`llr_a.1`](#llr-a-1)" in listing


def test_a_check_named_by_its_location_names_only_what_cites_it(tmp_path: Path) -> None:
    """A check's id is the line itself, so naming it beside the line would say nothing."""
    chain = cited_chain(tmp_path)
    write_req(chain[2].path, "llr_a.yaml", "parent_req", [["hlr_a.1"]], ["test", "proof"])
    chain.append(
        make_proof_layer(
            write_checks(
                tmp_path,
                {
                    "kind": "aspect",
                    "name": "Post",
                    "file": "src/controller.ads",
                    "line": 4,
                    "covers": ["llr_a.1"],
                },
            )
        )
    )
    renderer = DocumentRenderer(chain, source_root=tmp_path)
    listing = page_text(renderer.pages(), renderer.source_page("src/controller.ads"))

    assert "**Line 4** -- cited by [`llr_a.1`](#llr-a-1)" in listing


def test_the_listing_itself_is_html_only(tmp_path: Path) -> None:
    """The source is a browsing aid: the HTML carries it, the PDF does not."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    listing = page_text(renderer.pages(), renderer.source_page("src/controller.ads"))

    assert ":::{only} html" in listing
    # The anchor is *not* gated: a link that resolves in one rendering only
    # would be a broken document.
    anchor_at = listing.index(f"({renderer.source_anchor('src/controller.ads', 3)})=")
    assert listing.rindex(":::{only} html", 0, anchor_at) < anchor_at
    assert listing.index(":::", anchor_at) > anchor_at


def test_the_evidence_links_into_the_listing(tmp_path: Path) -> None:
    """`implemented_by` reaches the declaration's line, and says where it is."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    llr = page_text(renderer.pages(), "llr_a")

    anchor = renderer.source_anchor("src/controller.ads", 3)
    assert f"[`Controller.Step`](#{anchor}) (src/controller.ads:3)" in llr


def test_without_a_source_root_nothing_is_listed(tmp_path: Path) -> None:
    """Listing sources is opt-in; without it the evidence renders as plain ids."""
    pages = DocumentRenderer(cited_chain(tmp_path)).pages()

    assert not [p for p in pages if p.name.startswith("sources/")]
    assert "- **Implemented by:** `Controller.Step`" in page_text(pages, "llr_a")


def test_a_source_the_inventory_names_but_disk_lacks_is_skipped(tmp_path: Path) -> None:
    """A stale inventory must not stop the requirements rendering."""
    chain = cited_chain(tmp_path)
    (tmp_path / "src" / "controller.ads").unlink()
    pages = DocumentRenderer(chain, source_root=tmp_path).pages()

    assert not [p for p in pages if p.name.startswith("sources/")]
    assert "- **Implemented by:** `Controller.Step`" in page_text(pages, "llr_a")


def test_the_index_names_the_listings_and_locates_the_evidence(tmp_path: Path) -> None:
    """A consumer can link a matrix's code id to the line it is listed at."""
    renderer = DocumentRenderer(cited_chain(tmp_path), source_root=tmp_path)
    index = renderer.index()

    assert index["sources"] == [
        {"page": renderer.source_page("src/controller.ads"), "path": "src/controller.ads"}
    ]
    assert index["nodes"]["CODE"]["Controller.Step"] == {
        "page": renderer.source_page("src/controller.ads"),
        "anchor": renderer.source_anchor("src/controller.ads", 3),
        "text": "src/controller.ads:3",
    }


def test_distinct_paths_never_share_a_slug() -> None:
    """Slugging alone is not injective, so the assignment counts collisions apart."""
    slugs = source_slugs(["src/a-b.ads", "src/a_b.ads", "src/a.b.ads"])

    assert len(set(slugs.values())) == 3
    assert slugs["src/a-b.ads"] == "src-a-b-ads"


def test_a_source_outside_the_root_is_not_listed(tmp_path: Path) -> None:
    """A cited file outside the root is refused, not copied into the report."""
    chain = cited_chain(tmp_path)
    outside = tmp_path.parent / "outside_secret.ads"
    outside.write_text("--  not ours to publish\n", encoding="utf-8")
    inventory = tmp_path / "code_inventory.json"
    write_inventory(
        inventory,
        packages=[
            package(
                "Controller",
                spec_file="../outside_secret.ads",
                subprograms=[
                    subprogram(
                        "Step",
                        qualified_name="Controller.Step",
                        file="../outside_secret.ads",
                        line=1,
                    )
                ],
            )
        ],
    )
    pages = DocumentRenderer(chain, source_root=tmp_path).pages()

    assert not [page for page in pages if page.name.startswith("sources/")]
    assert "not ours to publish" not in "\n".join(page.text for page in pages)


def test_a_citation_past_the_end_of_the_file_is_forgotten(tmp_path: Path) -> None:
    """A drifted inventory must not promise a link the listing cannot define."""
    chain = cited_chain(tmp_path)
    (tmp_path / "src" / "controller.ads").write_text("package Controller is\n", encoding="utf-8")
    renderer = DocumentRenderer(chain, source_root=tmp_path)
    llr = page_text(renderer.pages(), "llr_a")

    assert "- **Implemented by:** `Controller.Step`" in llr  # plain, not a dead link
    assert "CODE" not in renderer.index()["nodes"]


def test_every_layer_below_a_markdown_layer_gets_a_realization_table(tmp_path: Path) -> None:
    """A chain that branches below the CONOPS renders each branch's realization."""
    chain = req_chain(tmp_path)
    other = tmp_path / "hlr2"
    other.mkdir()
    write_req(other, "hlr_b.yaml", "source", [["CONOPS §2.1"]])
    chain.append(
        Layer("HLR2", "requirement-yaml", other, id_pattern=r"CONOPS §(\d+\.\d+)", parent="CONOPS")
    )
    conops = page_text(DocumentRenderer(chain).pages(), "conops")

    assert "| Leaf | Realized by (HLR) |" in conops
    assert "| Leaf | Realized by (HLR2) |" in conops
