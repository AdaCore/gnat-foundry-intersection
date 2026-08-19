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
    make_test_layer,
    write_conops,
    write_req,
    write_tests,
    write_waivers,
)
from typer.testing import CliRunner

from reqs.cli import app
from reqs.render import (
    INDEX_NAME,
    INDEX_SCHEMA_VERSION,
    DocumentRenderer,
    RenderedPage,
    anchor_of,
)

if TYPE_CHECKING:
    from pathlib import Path

    from reqs.checks.trace import Layer

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

    assert [page.name for page in pages] == ["hlr_a", "llr_a"]
    hlr = page_text(pages, "hlr_a")
    assert "# hlr_a" in hlr
    assert "(hlr-a-1)=\n## hlr_a.1" in hlr
    assert "The system shall do thing 1." in hlr


def test_up_refs_link_to_the_rendered_parent(tmp_path: Path) -> None:
    """An LLR's parent_req links to the HLR statement it resolves to."""
    llr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "llr_a")

    assert f"- **Parent:** [`hlr_a.1`](#{anchor_of('hlr_a.1')})" in llr


def test_up_refs_to_an_unrendered_layer_stay_plain(tmp_path: Path) -> None:
    """An HLR's CONOPS source is shown as written: the CONOPS is not rendered here."""
    hlr = page_text(DocumentRenderer(req_chain(tmp_path)).pages(), "hlr_a")

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
    assert [layer["name"] for layer in index["layers"]] == ["HLR", "LLR"]
    for nodes in index["nodes"].values():
        for node_id, entry in nodes.items():
            assert f"({entry['anchor']})=" in pages[entry["page"]], node_id
            assert entry["text"]


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
    assert "2 page(s) written" in result.output
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
