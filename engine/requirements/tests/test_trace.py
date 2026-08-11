"""
Tests for the level-agnostic traceability engine (reqs.checks.trace).

A trace *chain* is an ordered list of `Layer`s, top (most abstract) to bottom.
The engine runs the same checks over every adjacent pair (upper -> lower), in
both directions:

  E-TRACE-DANGLING         : a lower node's up-ref resolves to no upper node.
  E-TRACE-UNTRACED         : a lower node has no upward trace and is not derived
                             (backward completeness -- always an error).
  {W,E}-TRACE-UNCOVERED    : an upper node no lower node covers and no waiver
                             excuses (warning by default, error under --complete).
  E-TRACE-WAIVER-UNKNOWN   : a waiver naming a node that is not in its layer.
  W-TRACE-WAIVER-REDUNDANT : a waiver naming a node that the layer below covers.

The engine is level-agnostic: the same code checks CONOPS->HLR and HLR->LLR (and
later LLR->code/test). A `Layer` says how to enumerate its nodes (`kind`) and,
for a lower layer, how to extract a parent id from each of its up-refs
(`id_pattern`).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

from inventory_fixture import check, gnattest_routine, package, subprogram, write_inventory
from typer.testing import CliRunner

from reqs.checks.trace import (
    Layer,
    _severity_style,
    check_trace,
    load_chain,
    render_tables,
    select_layers,
)
from reqs.cli import app
from reqs.conops import ConopsSet

if TYPE_CHECKING:
    from collections.abc import Sequence
    from pathlib import Path

    from reqs.core import Diagnostic

runner = CliRunner()

CONOPS_TEXT = """\
# Concept of Operations

# 1. The Intersection
- **1.1 ◆** Four approaches meet at 90°. — *decision*

# 2. Vehicle Signals
- **2.1 ✔** The controller shall show green. — *MUTCD §4E.01*
- **2.2 ✔** The controller shall show red. — *MUTCD §4E.01*

# 3. Pedestrian
- **3.1 ◇** A pedestrian head serves each crosswalk. — *MUTCD*

Some explanatory prose, not a leaf.
- not a leaf bullet
"""


def write_conops(tmp_path: Path) -> Path:
    """Write the fixture CONOPS document and return its path."""
    p = tmp_path / "conops.md"
    p.write_text(CONOPS_TEXT, encoding="utf-8")
    return p


def write_req(
    tmp_path: Path,
    name: str,
    ref_field: str,
    statements: Sequence[Sequence[str] | None],
    verifications: Sequence[str | None] | None = None,
) -> Path:
    """Write a requirement file from up-ref lists (None => derived) and optional method marks."""
    lines = ["description:"]
    for i, refs in enumerate(statements, start=1):
        lines.append(f"  {i}:")
        lines.append(f"    text: The system shall do thing {i}.")
        if refs is None:
            lines.append("    derived: true")
        else:
            lines.append(f"    {ref_field}:")
            lines.extend(f"      - {r}" for r in refs)
        method = verifications[i - 1] if verifications is not None else None
        if method == "review":  # a review entry must carry its justification
            lines.append("    verification:")
            lines.append("      - method: review")
            lines.append("        justification: fixture")
        elif method is not None:
            lines.append(f"    verification: {method}")
    p = tmp_path / name
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def write_waivers(tmp_path: Path, name: str, entries: Sequence[tuple[str, str]]) -> Path:
    """Write a waiver file from (node, reason) entries and return its path."""
    lines = ["waivers:"]
    for node, reason in entries:
        lines.append(f'  - leaf: "{node}"')
        lines.append(f"    reason: {reason}")
    p = tmp_path / name
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def conops_layer(path: Path, waivers: Path | None = None) -> Layer:
    """Make a CONOPS (markdown-leaves) layer."""
    return Layer("CONOPS", "markdown-leaves", path, waivers=waivers)


def hlr_layer(hlr_dir: Path, waivers: Path | None = None) -> Layer:
    """Make an HLR layer whose up-refs are CONOPS leaf citations."""
    return Layer(
        "HLR",
        "requirement-yaml",
        hlr_dir,
        id_pattern=r"CONOPS §(\d+\.\d+)",
        waivers=waivers,
    )


def llr_layer(llr_dir: Path) -> Layer:
    """Make an LLR layer whose up-refs are HLR statement IDs."""
    return Layer("LLR", "requirement-yaml", llr_dir, id_pattern=r"(.+\.\d+)")


def make_test_layer(inventory: Path, *, partial: bool = False, method: str | None = None) -> Layer:
    """Make a TEST layer whose up-refs are LLR statement IDs."""
    return Layer(
        "TEST",
        "ada-tests",
        inventory,
        id_pattern=r"(.+\.\d+)",
        partial_coverage=partial,
        method=method,
    )


def make_code_layer(
    inventory: Path,
    *,
    parent: str = "LLR",
    name: str = "CODE",
    ref_field: str | None = "implemented_by",
    method: str | None = None,
) -> Layer:
    """Make a CODE-like layer: the LLR names the code, so its refs point *down*."""
    return Layer(
        name,
        "ada-entities",
        inventory,
        parent=parent,
        partial_coverage=method is None,
        refs_point_down=True,
        ref_field=ref_field,
        method=method,
    )


def write_tests(tmp_path: Path, unit: str, routines: dict[str, list[str]]) -> Path:
    """Write a test inventory with the given routines; routines[name] are `--@covers` payloads."""
    file = f"src/tests/{unit}-test_data-tests.adb"
    return write_inventory(
        tmp_path / "test_inventory.json",
        packages=[
            package(
                f"{unit.capitalize()}.Test_Data.Tests",
                subprograms=[
                    gnattest_routine(name, file, line=10 + 10 * i, covers=covers)
                    for i, (name, covers) in enumerate(routines.items())
                ],
            )
        ],
    )


def llr_test_chain(
    tmp_path: Path,
    llr_statements: Sequence[Sequence[str]],
    routines: dict[str, list[str]],
    *,
    partial: bool = False,
    method: str | None = None,
    verifications: Sequence[str | None] | None = None,
) -> list[Layer]:
    """Build a minimal LLR -> TEST chain: LLR statements above, one test unit below."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    write_req(llr_dir, "llr_x.yaml", "parent_req", llr_statements, verifications=verifications)
    return [
        llr_layer(llr_dir),
        make_test_layer(write_tests(tmp_path, "u", routines), partial=partial, method=method),
    ]


def summarize(diags: Sequence[Diagnostic]) -> list[tuple[str, str, str]]:
    """Reduce diagnostics to (code, level, message) triples, preserving order."""
    return [(d.code, d.level, d.message) for d in diags]


def uncovered_warning(nid: str) -> tuple[str, str, str]:
    """Build the expected default-mode UNCOVERED warning for a CONOPS leaf."""
    return (
        "W-TRACE-UNCOVERED",
        "warning",
        f"CONOPS node '{nid}' is covered by no HLR and no waiver"
        " (use --complete to require coverage)",
    )


COVERING = [["CONOPS §2.1"], ["CONOPS §2.2"], ["CONOPS §3.1"]]  # covers all but leaf 1.1


def conops_hlr_chain(
    tmp_path: Path,
    statements: Sequence[Sequence[str] | None],
    *,
    waive: Sequence[tuple[str, str]] | None = None,
) -> list[Layer]:
    """Build a CONOPS -> HLR chain with the given HLR statements and waivers."""
    conops = write_conops(tmp_path)
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir(exist_ok=True)
    write_req(hlr_dir, "hlr_x.yaml", "source", statements)
    waivers = write_waivers(tmp_path, "w.yaml", waive) if waive is not None else None
    return [conops_layer(conops, waivers=waivers), hlr_layer(hlr_dir)]


# --- adapters / config ------------------------------------------------------


def test_conops_set_extracts_bullets_only(tmp_path: Path) -> None:
    """Only marked leaf bullets are extracted, each with a positive line number."""
    conops = ConopsSet.load(write_conops(tmp_path))
    assert {nid for nid, _leaf in conops.all_statements()} == {"1.1", "2.1", "2.2", "3.1"}
    assert all(leaf.line > 0 for _nid, leaf in conops.all_statements())


def test_load_chain_resolves_relative_paths(tmp_path: Path) -> None:
    """Layer paths in a chain config resolve relative to the config file."""
    write_conops(tmp_path)
    (tmp_path / "hlr").mkdir()
    write_waivers(tmp_path, "trace_waivers.yaml", [("1.1", "ok")])
    (tmp_path / "trace_chain.yaml").write_text(
        "layers:\n"
        "  - {name: CONOPS, kind: markdown-leaves, path: conops.md, waivers: trace_waivers.yaml}\n"
        "  - {name: HLR, kind: requirement-yaml, path: hlr,"
        " id_pattern: 'CONOPS §(\\d+\\.\\d+)'}\n",
        encoding="utf-8",
    )
    layers = load_chain(tmp_path / "trace_chain.yaml")
    assert [layer.name for layer in layers] == ["CONOPS", "HLR"]
    assert layers[0].path == tmp_path / "conops.md"
    assert layers[0].waivers == tmp_path / "trace_waivers.yaml"
    assert layers[1].id_pattern == r"CONOPS §(\d+\.\d+)"


# --- CONOPS -> HLR, forward (coverage) --------------------------------------


def test_clean_when_every_leaf_covered_or_waived(tmp_path: Path) -> None:
    """A chain where every leaf is covered or waived is clean even under --complete."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "Physical site assumption.")])
    assert check_trace(chain, complete=True) == []


def test_uncovered_leaf_warns_by_default(tmp_path: Path) -> None:
    """An uncovered, unwaived leaf is a warning (not an error) by default."""
    chain = conops_hlr_chain(tmp_path, COVERING)  # 1.1 uncovered/unwaived
    assert summarize(check_trace(chain)) == [uncovered_warning("1.1")]


def test_uncovered_leaf_errors_under_complete(tmp_path: Path) -> None:
    """Under --complete an uncovered leaf escalates to an error."""
    chain = conops_hlr_chain(tmp_path, COVERING)
    assert summarize(check_trace(chain, complete=True)) == [
        ("E-TRACE-UNCOVERED", "error", "CONOPS node '1.1' is covered by no HLR and no waiver")
    ]


def test_waiver_suppresses_uncovered(tmp_path: Path) -> None:
    """A waiver excuses an uncovered leaf: no UNCOVERED diagnostic fires."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "Physical assumption.")])
    diags = check_trace(chain, complete=True)
    assert not [d for d in diags if d.code.endswith("UNCOVERED")]


def test_waiver_for_unknown_node_is_error(tmp_path: Path) -> None:
    """A waiver naming a node that is not in its layer is an error."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok"), ("9.9", "stale")])
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-WAIVER-UNKNOWN", "error", "waiver names '9.9', which is not a CONOPS node")
    ]


def test_redundant_waiver_warns(tmp_path: Path) -> None:
    """A waiver naming a node the layer below covers (2.1) draws a warning."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok"), ("2.1", "unnecessary")])
    assert summarize(check_trace(chain)) == [
        (
            "W-TRACE-WAIVER-REDUNDANT",
            "warning",
            "waiver names '2.1', but it is covered by hlr_x.1; remove the waiver",
        )
    ]


# --- CONOPS -> HLR, backward (the point-3 fix) ------------------------------


def test_dangling_ref_is_error(tmp_path: Path) -> None:
    """An up-ref to a non-existent CONOPS leaf is a dangling-ref error."""
    chain = conops_hlr_chain(tmp_path, [["CONOPS §9.9"]])
    assert summarize(check_trace(chain)) == [
        (
            "E-TRACE-DANGLING",
            "error",
            "HLR 'hlr_x.1' up-ref 'CONOPS §9.9' resolves to no CONOPS node",
        ),
        # ...and, with the only HLR statement pointing nowhere, every leaf is uncovered.
        uncovered_warning("1.1"),
        uncovered_warning("2.1"),
        uncovered_warning("2.2"),
        uncovered_warning("3.1"),
    ]


def test_hlr_without_source_fails_schema(tmp_path: Path) -> None:
    """A statement with neither source nor derived (a backward gap) fails the schema."""
    chain = conops_hlr_chain(tmp_path, [[], *COVERING], waive=[("1.1", "ok")])
    # `[]` writes `source:` with no items. The whole file then fails to load,
    # so the leaves its other statements would have covered go uncovered too.
    assert summarize(check_trace(chain)) == [
        ("E-SCHEMA", "error", "'source' must not be null; omit the key instead")
    ]


def test_derived_statement_is_traced_not_untraced(tmp_path: Path) -> None:
    """A derived statement counts as accounted for, not UNTRACED."""
    chain = conops_hlr_chain(tmp_path, [None, *COVERING], waive=[("1.1", "ok")])  # stmt 1 derived
    assert check_trace(chain, complete=True) == []


def test_source_that_is_not_a_conops_ref_is_untraced(tmp_path: Path) -> None:
    """Citing a standard instead of a CONOPS leaf is UNTRACED, not DANGLING."""
    chain = conops_hlr_chain(tmp_path, [["MUTCD §4E.01"], *COVERING], waive=[("1.1", "ok")])
    # No E-TRACE-DANGLING: a ref that is not a CONOPS ref is out of scope, not dangling.
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-UNTRACED", "error", "HLR 'hlr_x.1' traces to no CONOPS node and is not derived")
    ]


# --- generalization: the same engine does HLR -> LLR ------------------------


def test_engine_generalizes_to_hlr_llr(tmp_path: Path) -> None:
    """The same engine checks the HLR -> LLR pair of a three-layer chain."""
    conops = write_conops(tmp_path)
    hlr_dir, llr_dir = tmp_path / "hlr", tmp_path / "llr"
    hlr_dir.mkdir()
    llr_dir.mkdir()
    write_req(hlr_dir, "hlr_x.yaml", "source", COVERING)  # hlr_x.1, .2, .3
    # LLR .1 refines a real HLR statement; .2 points at a non-existent one.
    write_req(llr_dir, "llr_y.yaml", "parent_req", [["hlr_x.1"], ["hlr_x.99"]])
    waivers = write_waivers(tmp_path, "w.yaml", [("1.1", "ok")])
    chain = [
        conops_layer(conops, waivers=waivers),
        hlr_layer(
            hlr_dir,
            waivers=write_waivers(
                tmp_path, "hw.yaml", [("hlr_x.2", "no LLR yet"), ("hlr_x.3", "no LLR yet")]
            ),
        ),
        llr_layer(llr_dir),
    ]
    # HLR -> LLR resolution ran: the bad parent_req is dangling.
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-DANGLING", "error", "LLR 'llr_y.2' up-ref 'hlr_x.99' resolves to no HLR node")
    ]


# --- rendering (point 2) ----------------------------------------------------


def test_render_tables_show_bidirectional_status(tmp_path: Path) -> None:
    """The tables show both coverage (forward) and upward-trace (backward) status."""
    chain = conops_hlr_chain(tmp_path, COVERING)  # 1.1 uncovered
    out = render_tables(chain)
    assert "CONOPS" in out
    assert "HLR" in out
    assert "1.1" in out  # forward: the uncovered leaf...
    assert "UNCOVERED" in out  # ...and its status
    assert "hlr_x.1" in out  # backward: the HLR statement appears with its trace


def test_render_tables_surface_partially_dangling_node(tmp_path: Path) -> None:
    """A node with both a resolved and a dangling up-ref is DANGLING, not OK."""
    chain = conops_hlr_chain(
        tmp_path, [["CONOPS §2.1", "CONOPS §9.9"], ["CONOPS §2.2"], ["CONOPS §3.1"]]
    )
    out = render_tables(chain, width=80)
    (row,) = [line for line in out.splitlines() if line.startswith("│ hlr_x.1 ")]
    assert "DANGLING" in row  # the resolved ref must not mask the dangling one
    assert "CONOPS §9.9" in row  # ...and the table names the unresolvable ref


def test_render_tables_wrap_wide_column_to_width(tmp_path: Path) -> None:
    """A very wide "Covered by" cell wraps to the terminal width instead of overflowing."""
    conops = write_conops(tmp_path)
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir()
    write_req(hlr_dir, "hlr_x.yaml", "source", [["CONOPS §2.1"]] * 12)
    chain = [
        conops_layer(conops, waivers=write_waivers(tmp_path, "w.yaml", [("1.1", "ok")])),
        hlr_layer(hlr_dir),
    ]
    out = render_tables(chain, width=80)
    assert all(len(line) <= 80 for line in out.splitlines())  # nothing overflows
    for n in range(1, 13):  # every covering statement still shown, wrapped across lines
        assert f"hlr_x.{n}" in out


def test_severity_style_flags_problems() -> None:
    """Row styles: red for real gaps, yellow for expected/accounted-for, green otherwise."""
    for status in ("UNCOVERED", "UNTRACED", "DANGLING", "UNVERIFIED", "MISMATCH"):
        assert _severity_style(status) == "red bold"
    for status in ("WAIVED", "DERIVED", "REVIEW"):
        assert _severity_style(status) == "yellow"
    assert _severity_style("OK") == "green"


def test_render_tables_are_boxed(tmp_path: Path) -> None:
    """The output is a boxed rich table with row separators, not an ASCII pipe table."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok")])
    out = render_tables(chain, width=80)
    assert "─" in out  # a boxed rich table with row separators, not an ASCII pipe table


# --- CLI --------------------------------------------------------------------


def write_chain_file(tmp_path: Path, waive: Sequence[tuple[str, str]]) -> Path:
    """Write a full CONOPS -> HLR fixture plus its chain config; return the config path."""
    write_conops(tmp_path)
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir(exist_ok=True)
    write_req(hlr_dir, "hlr_x.yaml", "source", COVERING)
    write_waivers(tmp_path, "trace_waivers.yaml", waive)
    chain = tmp_path / "trace_chain.yaml"
    chain.write_text(
        "layers:\n"
        "  - {name: CONOPS, kind: markdown-leaves, path: conops.md, waivers: trace_waivers.yaml}\n"
        "  - {name: HLR, kind: requirement-yaml, path: hlr,"
        " id_pattern: 'CONOPS §(\\d+\\.\\d+)'}\n",
        encoding="utf-8",
    )
    return chain


def test_cli_chain_exit_zero_when_clean(tmp_path: Path) -> None:
    """`reqs trace --complete` exits 0 on a clean chain."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--complete"])
    assert result.exit_code == 0, result.output


def test_cli_chain_exit_nonzero_when_uncovered_under_complete(tmp_path: Path) -> None:
    """`reqs trace --complete` exits non-zero when a leaf is uncovered."""
    chain = write_chain_file(tmp_path, [])  # 1.1 not waived
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--complete"])
    assert result.exit_code != 0, result.output


def test_cli_format_table_renders(tmp_path: Path) -> None:
    """`reqs trace --format table` renders the tables to stdout."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--format", "table"])
    assert result.exit_code == 0, result.output
    assert "CONOPS" in result.output
    assert "hlr_x.1" in result.output


# --- generalization: the same engine does LLR -> TEST (ada-tests kind) ------

TWO_LLRS = [["hlr_x.1"], ["hlr_x.2"]]  # yields llr_x.1, llr_x.2


def test_test_covering_a_real_llr_traces_clean(tmp_path: Path) -> None:
    """A test whose `--@covers` names a real LLR resolves upward with no diagnostic."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"], "Test_B": ["llr_x.2"]})
    assert check_trace(chain) == []


def test_covers_unknown_llr_is_dangling(tmp_path: Path) -> None:
    """A `--@covers` id that resolves to no LLR is a dangling-ref error."""
    # Both LLRs are covered, so only the bad ref surfaces (no incidental UNCOVERED).
    chain = llr_test_chain(
        tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1", "llr_x.2"], "Test_B": ["llr_x.1", "llr_x.99"]}
    )
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-DANGLING", "error", "TEST 'u.Test_B' up-ref 'llr_x.99' resolves to no LLR node")
    ]


def test_untagged_test_is_untraced(tmp_path: Path) -> None:
    """A test routine with no `--@covers` tag traces nowhere: a hard UNTRACED error."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1", "llr_x.2"], "Test_B": []})
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-UNTRACED", "error", "TEST 'u.Test_B' traces to no LLR node and is not derived")
    ]


def test_none_tagged_test_is_derived_not_untraced(tmp_path: Path) -> None:
    """A `--@covers none` test is accounted for (derived), not UNTRACED."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1", "llr_x.2"], "Test_Boundary": ["none: out of requirement scope"]},
    )
    assert check_trace(chain) == []


def test_partial_coverage_suppresses_uncovered_even_under_complete(tmp_path: Path) -> None:
    """A partial-coverage TEST layer never flags an untested LLR, even under --complete."""
    # llr_x.2 has no test, but tests cover LLRs only in part by design (proof covers the rest).
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, partial=True)
    assert check_trace(chain, complete=True) == []


def test_uncovered_llr_errors_under_complete_without_partial(tmp_path: Path) -> None:
    """Without partial_coverage the same untested LLR is a normal UNCOVERED error."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, partial=False)
    assert summarize(check_trace(chain, complete=True)) == [
        ("E-TRACE-UNCOVERED", "error", "LLR node 'llr_x.2' is covered by no TEST and no waiver")
    ]


def test_partial_coverage_table_marks_untested_not_uncovered(tmp_path: Path) -> None:
    """The coverage table shows an untested LLR as UNTESTED (neutral), not UNCOVERED (red)."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, partial=True)
    out = render_tables(chain, width=100)
    assert "UNTESTED" in out
    assert "UNCOVERED" not in out
    assert "u.Test_A" in out  # the covering test appears in the upward-trace table


def test_load_chain_reads_partial_coverage(tmp_path: Path) -> None:
    """`partial_coverage: true` on a layer is parsed from the chain config."""
    (tmp_path / "llr").mkdir()
    (tmp_path / "tests").mkdir()
    (tmp_path / "trace_chain.yaml").write_text(
        "layers:\n"
        "  - {name: LLR, kind: requirement-yaml, path: llr, id_pattern: '(.+\\.\\d+)'}\n"
        "  - {name: TEST, kind: ada-tests, path: tests, id_pattern: '(.+\\.\\d+)',"
        " partial_coverage: true}\n",
        encoding="utf-8",
    )
    layers = load_chain(tmp_path / "trace_chain.yaml")
    assert [layer.name for layer in layers] == ["LLR", "TEST"]
    assert layers[1].kind == "ada-tests"
    assert layers[1].partial_coverage is True
    assert layers[0].partial_coverage is False  # default


# -- the CODE layer: refs that point down -------------------------------------
#
# Every other layer cites its parent. Code cites nothing: it is the LLR that says
# what implements it, via `implemented_by`. So the CODE layer sets
# `refs_point_down`, the engine reads the refs from the LLR, and an
# `implemented_by` naming something the code does not declare is the dangling
# case -- reported against the LLR that wrote it.


def write_llr_with_code_refs(
    tmp_path: Path, statements: Sequence[tuple[Sequence[str], Sequence[str]]]
) -> Path:
    """Write an LLR file whose statements carry both `parent_req` and `implemented_by`."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    lines = ["description:"]
    for i, (parents, implementers) in enumerate(statements, start=1):
        lines.append(f"  {i}:")
        lines.append(f"    text: The system shall do thing {i}.")
        lines.append("    parent_req:")
        lines.extend(f"      - {r}" for r in parents)
        if implementers:
            lines.append("    implemented_by:")
            lines.extend(f"      - {r}" for r in implementers)
    (llr_dir / "llr_x.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return llr_dir


def write_code(tmp_path: Path, *names: str) -> Path:
    """Write a code inventory declaring the given qualified names as subprograms."""
    return write_inventory(
        tmp_path / "code_inventory.json",
        packages=[
            package(
                "Conflicts",
                subprograms=[
                    subprogram(
                        name.rsplit(".", 1)[-1],
                        qualified_name=name,
                        declared_in="spec",
                        file="src/core/conflicts.ads",
                        line=10 + 10 * i,
                    )
                    for i, name in enumerate(names)
                ],
            )
        ],
    )


def llr_code_chain(
    tmp_path: Path,
    statements: Sequence[tuple[Sequence[str], Sequence[str]]],
    declared: Sequence[str],
) -> list[Layer]:
    """Build a minimal LLR -> CODE chain."""
    return [
        llr_layer(write_llr_with_code_refs(tmp_path, statements)),
        make_code_layer(write_code(tmp_path, *declared)),
    ]


def test_implemented_by_resolving_to_code_is_ok(tmp_path: Path) -> None:
    """An `implemented_by` naming a declared entity is clean."""
    chain = llr_code_chain(
        tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])], ["Conflicts.Compatible"]
    )
    assert summarize(check_trace(chain, complete=True)) == []


def test_implemented_by_naming_absent_code_is_dangling(tmp_path: Path) -> None:
    """The point of the layer: a ref to code that does not exist is an error."""
    chain = llr_code_chain(
        tmp_path,
        [(["hlr_a.1"], ["Conflicts.Crosswalk_Conflicts"])],
        ["Conflicts.Compatible"],
    )
    assert summarize(check_trace(chain)) == [
        (
            "E-TRACE-DANGLING",
            "error",
            "LLR 'llr_x.1' implemented_by 'Conflicts.Crosswalk_Conflicts' resolves to no CODE node",
        )
    ]


def test_dangling_down_ref_is_located_at_the_implemented_by_key(tmp_path: Path) -> None:
    """The diagnostic points at the LLR that wrote the ref, not at the code."""
    chain = llr_code_chain(tmp_path, [(["hlr_a.1"], ["Conflicts.Nope"])], [])
    diag = check_trace(chain)[0]
    assert diag.file.name == "llr_x.yaml"
    assert diag.path == ("description", "1", "implemented_by")
    assert diag.line is not None


def test_implemented_by_matching_is_case_insensitive(tmp_path: Path) -> None:
    """Ada is case-insensitive, so a differently spelled ref still resolves."""
    chain = llr_code_chain(
        tmp_path, [(["hlr_a.1"], ["conflicts.COMPATIBLE"])], ["Conflicts.Compatible"]
    )
    assert summarize(check_trace(chain, complete=True)) == []


def test_code_no_requirement_names_is_not_an_error(tmp_path: Path) -> None:
    """Most of the code realizes no requirement directly; that is not a gap."""
    chain = llr_code_chain(
        tmp_path,
        [(["hlr_a.1"], ["Conflicts.Compatible"])],
        ["Conflicts.Compatible", "Conflicts.Helper"],
    )
    assert summarize(check_trace(chain, complete=True)) == []


def test_downward_tables_report_both_directions(tmp_path: Path) -> None:
    """The tables show what implements each LLR, and which code no LLR names."""
    chain = llr_code_chain(
        tmp_path,
        [(["hlr_a.1"], ["Conflicts.Compatible"]), (["hlr_a.2"], ["Conflicts.Nope"])],
        ["Conflicts.Compatible", "Conflicts.Helper"],
    )
    out = render_tables(chain, width=140)
    assert "LLR → CODE  (implementation)" in out
    assert "CODE → LLR  (required by)" in out
    assert "DANGLING" in out  # llr_x.2 names something absent
    assert "UNREQUIRED" in out  # Conflicts.Helper is named by no LLR


def test_llr_naming_no_code_is_reported_but_not_an_error(tmp_path: Path) -> None:
    """An LLR with no `implemented_by` shows as UNIMPLEMENTED, never a failure."""
    chain = llr_code_chain(tmp_path, [(["hlr_a.1"], [])], ["Conflicts.Compatible"])
    assert summarize(check_trace(chain, complete=True)) == []
    assert "UNIMPLEMENTED" in render_tables(chain, width=140)


def test_missing_inventory_fails_the_check(tmp_path: Path) -> None:
    """A missing inventory is reported, not silently degraded to 'nothing traced'."""
    chain = [
        llr_layer(write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])),
        make_code_layer(tmp_path / "absent.json"),
    ]
    assert [code for code, _level, _msg in summarize(check_trace(chain))] == ["E-IO"]


# -- proof / static-check evidence: `--@covers`-tagged checks in the source ----


def write_proof_llr(tmp_path: Path, *, also_test: bool = False) -> Path:
    """Write one proof-verified LLR statement."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    (llr_dir / "llr_x.yaml").write_text(
        "description:\n"
        "  1:\n"
        "    text: The system shall do the thing.\n"
        "    parent_req:\n"
        "      - hlr_a.1\n"
        "    verification:\n"
        "      - method: proof\n"
        + ("      - method: test\n" if also_test else "")
        + "    implemented_by:\n"
        "      - Conflicts.Compatible\n",
        encoding="utf-8",
    )
    return llr_dir


def write_checks(tmp_path: Path, *specs: dict[str, object]) -> Path:
    """Write a code inventory holding only tagged checks (see `inventory_fixture.check`)."""
    return write_inventory(
        tmp_path / "checks_inventory.json",
        checks=[check(**spec) for spec in specs],  # type: ignore[arg-type]
    )


POST_CHECK = {"kind": "aspect", "name": "Post", "file": "src/core/x.ads", "line": 12}


def make_proof_layer(inventory: Path) -> Layer:
    """Make a PROOF layer reading the source's tagged contract aspects."""
    return Layer(
        "PROOF",
        "ada-checks",
        inventory,
        parent="LLR",
        id_pattern=r"(.+\.\d+)",
        method="proof",
        anchors=["aspect:Post"],
    )


def test_tagged_contract_satisfies_the_proof_layer(tmp_path: Path) -> None:
    """A `Post` aspect tagged `--@covers llr_x.1` discharges the proof declaration."""
    chain = [
        llr_layer(write_proof_llr(tmp_path)),
        make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1"]})),
    ]
    assert check_trace(chain, complete=True) == []


def test_declared_proof_with_no_tagged_check_is_uncovered(tmp_path: Path) -> None:
    """A declared proof no check cites yet is an open obligation, not silently green."""
    chain = [
        llr_layer(write_proof_llr(tmp_path)),
        make_proof_layer(write_checks(tmp_path)),
    ]
    assert [code for code, _level, _msg in summarize(check_trace(chain, complete=True))] == [
        "E-TRACE-UNCOVERED"
    ]


def test_anchors_filter_which_constructs_count(tmp_path: Path) -> None:
    """A tagged pragma is not proof evidence, and its orphaned tag is reported."""
    inventory = write_checks(
        tmp_path, {"kind": "pragma", "file": "src/core/x.ads", "line": 3, "covers": ["llr_x.1"]}
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    assert [code for code, _level, _msg in summarize(check_trace(chain, complete=True))] == [
        "E-TRACE-CHECK-IGNORED",  # the author opted in; the citation must not vanish
        "E-TRACE-UNCOVERED",
    ]


def test_ignored_tagged_check_is_located_at_the_construct(tmp_path: Path) -> None:
    """The orphaned-tag diagnostic points at the tagged construct in the source."""
    inventory = write_checks(
        tmp_path,
        {
            "kind": "aspect",
            "name": "Pre",
            "file": "src/core/x.ads",
            "line": 7,
            "covers": ["llr_x.1"],
        },
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    diag = next(d for d in check_trace(chain) if d.code == "E-TRACE-CHECK-IGNORED")
    assert diag.message == (
        "tagged aspect 'Pre' matches no ada-checks layer's anchors; "
        "its --@covers citation is silently discharging nothing"
    )
    assert (str(diag.file), diag.line) == ("src/core/x.ads", 7)


def test_covers_none_check_outside_anchors_is_not_reported(tmp_path: Path) -> None:
    """A `--@covers none:` tag cites nothing, so dropping it loses no evidence."""
    inventory = write_checks(
        tmp_path,
        {"kind": "pragma", "file": "src/core/x.ads", "line": 3, "covers": ["none: out of scope"]},
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    codes = [code for code, _level, _msg in summarize(check_trace(chain, complete=True))]
    assert "E-TRACE-CHECK-IGNORED" not in codes


def test_empty_covers_payload_on_an_unanchored_construct_is_reported(tmp_path: Path) -> None:
    """A bare `--@covers` must not vanish just because its construct is unanchored."""
    inventory = write_checks(
        tmp_path,
        {**POST_CHECK, "covers": ["llr_x.1"]},  # the statement is covered anyway
        {"kind": "aspect", "name": "Pre", "file": "src/core/x.ads", "line": 7, "covers": [""]},
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    diags = check_trace(chain, complete=True)
    assert [d.code for d in diags] == ["E-TRACE-CHECK-EMPTY"]
    assert diags[0].message == (
        "tagged aspect 'Pre' has a --@covers tag citing nothing; name the statement "
        "id(s) it discharges, or write --@covers none: <reason>"
    )
    assert (str(diags[0].file), diags[0].line) == ("src/core/x.ads", 7)


def test_empty_covers_payload_on_an_anchored_construct_is_reported(tmp_path: Path) -> None:
    """The payload check is anchor-independent: the accepted construct is reported too."""
    inventory = write_checks(tmp_path, {**POST_CHECK, "covers": [""]})
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    codes = [code for code, _level, _msg in summarize(check_trace(chain, complete=True))]
    assert codes[0] == "E-TRACE-CHECK-EMPTY"


def test_a_check_with_one_good_and_one_empty_payload_is_reported(tmp_path: Path) -> None:
    """A construct's good citation does not excuse a second, broken tag on it."""
    inventory = write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1", "   "]})
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    assert [d.code for d in check_trace(chain, complete=True)] == ["E-TRACE-CHECK-EMPTY"]


def test_covers_none_payload_is_not_reported_as_empty(tmp_path: Path) -> None:
    """`none:` cites nothing on purpose -- it is a claim, not a broken tag."""
    inventory = write_checks(
        tmp_path,
        {**POST_CHECK, "covers": ["llr_x.1"]},
        {
            "kind": "aspect",
            "name": "Pre",
            "file": "src/core/x.ads",
            "line": 7,
            "covers": ["none: guards an implementation detail"],
        },
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    assert check_trace(chain, complete=True) == []


def test_anchor_matching_is_case_insensitive(tmp_path: Path) -> None:
    """Ada names are case-insensitive, so `aspect:post` accepts a `Post` aspect."""
    layer = make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1"]}))
    layer.anchors = ["aspect:post"]
    assert check_trace([llr_layer(write_proof_llr(tmp_path)), layer], complete=True) == []


def test_named_pragma_anchor_excludes_other_pragmas(tmp_path: Path) -> None:
    """`pragma:Compile_Time_Error` accepts only that pragma; a tagged Assert is drift-proofed."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    write_req(llr_dir, "llr_x.yaml", "parent_req", [["hlr_a.1"]], verifications=["static_check"])
    inventory = write_checks(
        tmp_path,
        {"kind": "pragma", "file": "src/x.ads", "line": 3, "covers": ["llr_x.1"]},
        {"kind": "pragma", "name": "Assert", "file": "src/x.ads", "line": 9, "covers": ["llr_x.1"]},
    )
    layer = Layer(
        "STATIC",
        "ada-checks",
        inventory,
        parent="LLR",
        id_pattern=r"(.+\.\d+)",
        method="static_check",
        anchors=["pragma:Compile_Time_Error"],
    )
    diags = summarize(check_trace([llr_layer(llr_dir), layer], complete=True))
    # The Compile_Time_Error covers the statement; the runtime Assert's tag is loud.
    assert [code for code, _level, _msg in diags] == ["E-TRACE-CHECK-IGNORED"]


def test_one_check_may_cover_several_statements(tmp_path: Path) -> None:
    """Multiple `--@covers` payloads on one construct union, like test tags."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    write_req(llr_dir, "llr_x.yaml", "parent_req", [["hlr_a.1"], ["hlr_a.2"]], ["proof", "proof"])
    inventory = write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1", "llr_x.2"]})
    assert check_trace([llr_layer(llr_dir), make_proof_layer(inventory)], complete=True) == []


def test_duplicate_check_node_id_is_reported(tmp_path: Path) -> None:
    """Two inventory entries claiming one file:line would silently drop citations."""
    inventory = write_checks(
        tmp_path,
        {**POST_CHECK, "covers": ["llr_x.1"]},
        {**POST_CHECK, "covers": ["llr_x.2"]},
    )
    chain = [llr_layer(write_proof_llr(tmp_path)), make_proof_layer(inventory)]
    assert "E-CHECK-DUPID" in [code for code, _level, _msg in summarize(check_trace(chain))]


def test_dangling_check_tag_is_located_at_the_construct(tmp_path: Path) -> None:
    """A tag citing an absent statement dangles, pointing at the tagged construct."""
    chain = [
        llr_layer(write_proof_llr(tmp_path)),
        make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.9"]})),
    ]
    diags = summarize(check_trace(chain))
    assert (
        "E-TRACE-DANGLING",
        "error",
        "PROOF 'src/core/x.ads:12' up-ref 'llr_x.9' resolves to no LLR node",
    ) in diags
    dangling = next(d for d in check_trace(chain) if d.code == "E-TRACE-DANGLING")
    assert (str(dangling.file), dangling.line) == ("src/core/x.ads", 12)


def test_check_citing_an_undeclared_method_is_drift(tmp_path: Path) -> None:
    """A contract citing a statement that does not declare proof contradicts the mark."""
    llr_dir = tmp_path / "llr"
    llr_dir.mkdir(exist_ok=True)
    write_req(llr_dir, "llr_x.yaml", "parent_req", [["hlr_a.1"]], verifications=["test"])
    chain = [
        llr_layer(llr_dir),
        make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1"]})),
    ]
    assert summarize(check_trace(chain, complete=True)) == [
        (
            "E-TRACE-UNSELECTED",
            "error",
            "LLR 'llr_x.1' declares verification 'test', but no selected layer verifies 'test'",
        ),
        (
            "E-TRACE-METHOD",
            "error",
            "PROOF 'src/core/x.ads:12' covers LLR 'llr_x.1', whose verification (test) "
            "does not include 'proof'",
        ),
    ]


def test_check_evidence_renders_in_the_verification_table(tmp_path: Path) -> None:
    """The merged table shows the citing construct; the checks keep an upward table."""
    chain = [
        llr_layer(write_proof_llr(tmp_path)),
        make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1"]})),
    ]
    out = render_tables(chain, width=140)
    assert "LLR → VERIFICATION" in out
    assert "proof: src/core/x.ads:12" in out
    assert "PROOF → LLR" in out  # the artifact-side view: each check and what it cites


def test_check_tagged_none_is_derived_not_untraced(tmp_path: Path) -> None:
    """`--@covers none: <reason>` on a check parks it as derived, like a boundary test."""
    chain = [
        llr_layer(write_proof_llr(tmp_path)),
        make_proof_layer(
            write_checks(
                tmp_path,
                {**POST_CHECK, "covers": ["llr_x.1"]},
                {**POST_CHECK, "line": 40, "covers": ["none: proof plumbing"]},
            )
        ),
    ]
    assert check_trace(chain, complete=True) == []
    assert "DERIVED" in render_tables(chain, width=140)


def test_multi_method_statement_satisfies_each_layer(tmp_path: Path) -> None:
    """A statement declaring proof and test is enforced by both layers, cleanly."""
    llr_dir = write_proof_llr(tmp_path, also_test=True)
    proof = make_proof_layer(write_checks(tmp_path, {**POST_CHECK, "covers": ["llr_x.1"]}))
    chain = [
        llr_layer(llr_dir),
        make_test_layer(write_tests(tmp_path, "u", {"Test_A": ["llr_x.1"]}), method="test"),
        proof,
    ]
    assert check_trace(chain, complete=True) == []  # each method met, no drift
    uncovered = [
        llr_layer(llr_dir),
        make_test_layer(write_tests(tmp_path, "u", {}), method="test"),
        proof,
    ]
    codes = [code for code, _l, _m in summarize(check_trace(uncovered, complete=True))]
    assert codes == ["E-TRACE-UNCOVERED"]  # ...and it still demands its test


# -- the chain is a tree: a layer traces to its named parent -------------------


def test_two_layers_can_share_a_parent(tmp_path: Path) -> None:
    """TEST and CODE both hang off LLR; neither says anything about the other."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    chain = [
        llr_layer(llr_dir),
        make_test_layer(write_tests(tmp_path, "u", {"Test_A": ["llr_x.1"]}), partial=True),
        make_code_layer(write_code(tmp_path, "Conflicts.Compatible"), parent="LLR"),
    ]
    assert summarize(check_trace(chain, complete=True)) == []
    out = render_tables(chain, width=140)
    assert "LLR → TEST" in out
    assert "LLR → CODE" in out
    assert "TEST → CODE" not in out  # the two are siblings, not a chain


def test_unknown_parent_is_reported(tmp_path: Path) -> None:
    """A layer naming a parent that is not in the chain is E-TRACE-PARENT."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    chain = [
        llr_layer(llr_dir),
        make_code_layer(write_code(tmp_path, "Conflicts.Compatible"), parent="NOSUCH"),
    ]
    assert [code for code, _level, _msg in summarize(check_trace(chain))] == ["E-TRACE-PARENT"]


def test_load_chain_reads_parent_refs_point_down_and_method(tmp_path: Path) -> None:
    """`parent`, `refs_point_down`, `ref_field`, `method` and `anchors` come from the config."""
    (tmp_path / "llr").mkdir()
    (tmp_path / "trace_chain.yaml").write_text(
        "layers:\n"
        "  - {name: LLR, kind: requirement-yaml, path: llr, id_pattern: '(.+\\.\\d+)'}\n"
        "  - {name: TEST, kind: ada-tests, path: test_inventory.json,"
        " id_pattern: '(.+\\.\\d+)', method: test}\n"
        "  - {name: CODE, kind: ada-entities, path: code_inventory.json, parent: LLR,"
        " partial_coverage: true, refs_point_down: true, ref_field: implemented_by}\n"
        "  - {name: STATIC, kind: ada-checks, path: code_inventory.json, parent: LLR,"
        " id_pattern: '(.+\\.\\d+)', method: static_check,"
        " anchors: [pragma, 'aspect:No_Return']}\n",
        encoding="utf-8",
    )
    layers = load_chain(tmp_path / "trace_chain.yaml")
    assert [layer.name for layer in layers] == ["LLR", "TEST", "CODE", "STATIC"]
    assert layers[2].parent == "LLR"
    assert layers[2].refs_point_down is True
    assert layers[2].ref_field == "implemented_by"
    assert layers[3].method == "static_check"
    assert layers[3].anchors == ["pragma", "aspect:No_Return"]
    assert layers[1].parent is None  # defaults to the layer above
    assert layers[1].refs_point_down is False
    assert layers[1].method == "test"
    assert layers[0].method is None  # default: no method
    assert layers[0].ref_field is None
    assert layers[0].anchors == []


# -- verification methods: each LLR declares how it is discharged --------------
#
# A method layer covers exactly the LLRs declaring its method; this also keeps
# an empty generated inventory loud, with no hand-maintained node floor.


def test_test_verified_llr_without_test_errors_under_complete(tmp_path: Path) -> None:
    """An LLR declaring `verification: test` that no test covers is UNCOVERED."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1"]},
        method="test",
        verifications=["test", "test"],
    )
    assert summarize(check_trace(chain, complete=True)) == [
        (
            "E-TRACE-UNCOVERED",
            "error",
            "LLR node 'llr_x.2' declares verification 'test' but covered by no TEST and no waiver",
        )
    ]


def test_llr_verified_by_another_method_needs_no_test(tmp_path: Path) -> None:
    """An LLR declaring `verification: review` is not this layer's to cover."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1"]},
        method="test",
        verifications=["test", "review"],
    )
    assert check_trace(chain, complete=True) == []


def test_llr_declaring_no_method_is_unverified(tmp_path: Path) -> None:
    """Under a method layer, an LLR that declares nothing is a hard error."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1"]},
        method="test",
        verifications=["test", None],
    )
    assert summarize(check_trace(chain, complete=True)) == [
        (
            "E-TRACE-UNVERIFIED",
            "error",
            "LLR 'llr_x.2' declares no verification method "
            "(one of: test, proof, static_check, review)",
        )
    ]


def test_llr_declaring_a_method_no_layer_verifies_is_unselected(tmp_path: Path) -> None:
    """A declared method with no layer to verify it is an error, never silence."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.2"]},
        method="test",
        verifications=["proof", "test"],
    )
    assert summarize(check_trace(chain, complete=True)) == [
        (
            "E-TRACE-UNSELECTED",
            "error",
            "LLR 'llr_x.1' declares verification 'proof', but no selected layer verifies 'proof'",
        )
    ]


def test_missing_conops_document_is_a_diagnostic_not_a_crash(tmp_path: Path) -> None:
    """An absent CONOPS document is E-IO, like every other unreadable layer."""
    chain = conops_hlr_chain(tmp_path, COVERING)
    chain[0].path.unlink()
    assert [(d.code, d.level) for d in check_trace(chain)] == [("E-IO", "error")]


def test_test_covering_a_review_verified_llr_is_method_drift(tmp_path: Path) -> None:
    """A test citing an LLR declared review-verified contradicts the mark: error."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1"], "Test_B": ["llr_x.2"]},
        method="test",
        verifications=["test", "review"],
    )
    assert summarize(check_trace(chain, complete=True)) == [
        (
            "E-TRACE-METHOD",
            "error",
            "TEST 'u.Test_B' covers LLR 'llr_x.2', whose verification (review) "
            "does not include 'test'",
        )
    ]


def test_empty_inventory_fails_through_the_uncovered_llrs(tmp_path: Path) -> None:
    """The empty-enumeration guard: no routines means every test-verified LLR errors."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {}, method="test", verifications=["test", "test"])
    assert [code for code, _level, _msg in summarize(check_trace(chain, complete=True))] == [
        "E-TRACE-UNCOVERED",
        "E-TRACE-UNCOVERED",
    ]


def test_verification_table_merges_the_method_layers(tmp_path: Path) -> None:
    """One row per statement: OK / REVIEW / UNCOVERED / UNVERIFIED / MISMATCH."""
    chain = llr_test_chain(
        tmp_path,
        [["hlr_x.1"], ["hlr_x.2"], ["hlr_x.3"], ["hlr_x.4"], ["hlr_x.5"]],
        {"Test_A": ["llr_x.1"], "Test_B": ["llr_x.4"]},
        method="test",
        verifications=["test", "review", None, "review", "test"],
    )
    out = render_tables(chain, width=120)
    assert "LLR → VERIFICATION" in out
    assert "LLR → TEST" not in out  # merged, not per-method
    assert "TEST → LLR" in out  # the artifacts' own upward trace stays
    (row_1,) = [line for line in out.splitlines() if line.startswith("│ llr_x.1 ")]
    (row_2,) = [line for line in out.splitlines() if line.startswith("│ llr_x.2 ")]
    (row_3,) = [line for line in out.splitlines() if line.startswith("│ llr_x.3 ")]
    (row_4,) = [line for line in out.splitlines() if line.startswith("│ llr_x.4 ")]
    (row_5,) = [line for line in out.splitlines() if line.startswith("│ llr_x.5 ")]
    assert "OK" in row_1
    assert "test: u.Test_A" in row_1  # the evidence, labeled by method
    assert "REVIEW" in row_2
    assert "review: fixture" in row_2  # the justification is the evidence
    assert "UNVERIFIED" in row_3
    assert "MISMATCH" in row_4  # covered by a test, yet declared review-verified
    assert "(not declared)" in row_4
    assert "UNCOVERED" in row_5  # declared test-verified, no test yet
    assert "test: —" in row_5


def test_unknown_method_is_a_config_error(tmp_path: Path) -> None:
    """A typo'd method would silently require nothing; it stops the run instead."""
    chain = llr_test_chain(
        tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, method="tets", verifications=["test", "test"]
    )
    assert summarize(check_trace(chain)) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'TEST' names unknown method 'tets' (one of: test, proof, static_check, review)",
        )
    ]


def test_refs_point_down_without_ref_field_is_a_config_error(tmp_path: Path) -> None:
    """A down-pointing layer with no ref_field would read no refs; it stops the run."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    layer = make_code_layer(write_code(tmp_path, "Conflicts.Compatible"))
    layer.ref_field = None
    assert summarize(check_trace([llr_layer(llr_dir), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'CODE' sets refs_point_down but no ref_field says where its refs are written",
        )
    ]


def test_method_on_a_downward_layer_is_a_config_error(tmp_path: Path) -> None:
    """Method layers trace upward: evidence cites its statement, not the reverse."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    layer = make_code_layer(write_code(tmp_path, "Conflicts.Compatible"), method="proof")
    assert summarize(check_trace([llr_layer(llr_dir), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'CODE' sets both method and refs_point_down; "
            "a method layer's evidence cites its parent upward",
        )
    ]


def test_ref_field_without_refs_point_down_is_a_config_error(tmp_path: Path) -> None:
    """A ref_field on an upward-tracing layer would never be read; it stops the run."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    layer = make_code_layer(write_code(tmp_path, "Conflicts.Compatible"))
    layer.refs_point_down = False
    assert summarize(check_trace([llr_layer(llr_dir), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'CODE' names ref_field 'implemented_by' but its refs do not point down",
        )
    ]


def test_unknown_ref_field_is_a_config_error(tmp_path: Path) -> None:
    """A mistyped ref_field would read no refs at all; the whole layer must not go quiet."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    layer = make_code_layer(write_code(tmp_path, "Conflicts.Compatible"))
    layer.ref_field = "implemented_byy"
    assert summarize(check_trace([llr_layer(llr_dir), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'CODE' names unknown ref_field 'implemented_byy'; no statement holds "
            "refs in it, so the layer would resolve nothing (one of: implemented_by)",
        )
    ]


def test_unknown_ref_field_is_caught_under_partial_coverage(tmp_path: Path) -> None:
    """The typo's danger: partial_coverage flags nothing, so the trace would pass green."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Nowhere.At_All"])])
    layer = make_code_layer(write_code(tmp_path, "Conflicts.Compatible"))
    layer.ref_field = "implemented_byy"
    # Spelt right, the dangling `implemented_by` ref is an error; spelt wrong, the
    # config check has to be what stops the run.
    assert [code for code, _level, _msg in summarize(check_trace([llr_layer(llr_dir), layer]))] == [
        "E-TRACE-CONFIG"
    ]


def test_ref_field_read_from_a_non_requirement_parent_is_a_config_error(tmp_path: Path) -> None:
    """Only requirement statements hold down-refs; any other parent resolves nothing."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], ["Conflicts.Compatible"])])
    inventory = write_code(tmp_path, "Conflicts.Compatible")
    # A CODE layer hung off TEST rather than LLR: `implemented_by` exists, but no
    # test routine holds any, so every ref would go unread.
    layer = make_code_layer(inventory, parent="TEST")
    chain = [llr_layer(llr_dir), make_test_layer(write_tests(tmp_path, "u", {})), layer]
    assert summarize(check_trace(chain)) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'CODE' reads its refs from the 'implemented_by' of 'TEST', "
            "whose 'ada-tests' nodes hold no downward refs",
        )
    ]


def test_method_with_partial_coverage_is_a_config_error(tmp_path: Path) -> None:
    """partial_coverage on a method layer would exempt exactly what it must cover."""
    layer = make_test_layer(write_tests(tmp_path, "u", {}), partial=True, method="test")
    (tmp_path / "llr").mkdir(exist_ok=True)
    assert summarize(check_trace([llr_layer(tmp_path / "llr"), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'TEST' sets both method and partial_coverage, "
            "which would exempt the very statements the method requires covered",
        )
    ]


def test_anchors_on_a_non_checks_layer_is_a_config_error(tmp_path: Path) -> None:
    """An anchors list means nothing outside ada-checks; it would select nothing."""
    layer = make_test_layer(write_tests(tmp_path, "u", {}), method="test")
    layer.anchors = ["pragma"]
    (tmp_path / "llr").mkdir(exist_ok=True)
    assert summarize(check_trace([llr_layer(tmp_path / "llr"), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'TEST' lists anchors but is not an ada-checks layer; they would select nothing",
        )
    ]


def test_unknown_chain_key_is_a_config_error(tmp_path: Path) -> None:
    """A leftover or misspelled config knob must not be silently ignored."""
    (tmp_path / "llr").mkdir()
    (tmp_path / "chain.yaml").write_text(
        "layers:\n"
        "  - {name: HLR, kind: requirement-yaml, path: llr, id_pattern: '(.+\\.\\d+)'}\n"
        "  - {name: LLR, kind: requirement-yaml, path: llr, id_pattern: '(.+\\.\\d+)',"
        " min_nodes: 3}\n",
        encoding="utf-8",
    )
    assert summarize(check_trace(load_chain(tmp_path / "chain.yaml"))) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'LLR' has unknown config key(s) min_nodes",
        )
    ]


def test_checks_layer_without_anchors_is_a_config_error(tmp_path: Path) -> None:
    """An ada-checks layer with no anchors would match nothing; it stops the run."""
    layer = make_proof_layer(write_checks(tmp_path))
    layer.anchors = []
    assert summarize(check_trace([llr_layer(write_proof_llr(tmp_path)), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'PROOF' is ada-checks but lists no anchors; it would match no check at all",
        )
    ]


def test_malformed_anchor_is_a_config_error(tmp_path: Path) -> None:
    """A typo'd anchor would silently match nothing; it stops the run instead."""
    layer = make_proof_layer(write_checks(tmp_path))
    layer.anchors = ["aspct:Post"]
    assert summarize(check_trace([llr_layer(write_proof_llr(tmp_path)), layer])) == [
        (
            "E-TRACE-CONFIG",
            "error",
            "layer 'PROOF' anchor 'aspct:Post' is not 'pragma'[':<Name>'] or 'aspect:<Name>'",
        )
    ]


# -- ids must match the pattern whole -----------------------------------------


def test_covers_id_with_trailing_garbage_does_not_resolve(tmp_path: Path) -> None:
    """`llr_x.1typo` must not be accepted as `llr_x.1`: the pattern matches whole refs."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1typo"]}, partial=True)
    # The malformed id resolves to nothing, so the routine traces nowhere at all --
    # what must *not* happen is it quietly covering llr_x.1.
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-UNTRACED", "error", "TEST 'u.Test_A' traces to no LLR node and is not derived")
    ]
    assert "u.Test_A" not in render_tables(chain, width=100).split("upward trace")[0]


def test_parent_req_with_trailing_garbage_does_not_resolve(tmp_path: Path) -> None:
    """Same for a requirement layer: `hlr_x.1 (partly)` is not `hlr_x.1`."""
    conops = write_conops(tmp_path)
    hlr_dir, llr_dir = tmp_path / "hlr", tmp_path / "llr"
    hlr_dir.mkdir()
    llr_dir.mkdir()
    write_req(hlr_dir, "hlr_x.yaml", "source", COVERING)
    write_req(llr_dir, "llr_y.yaml", "parent_req", [["hlr_x.1 (partly)"]])
    chain = [
        conops_layer(conops, waivers=write_waivers(tmp_path, "w.yaml", [("1.1", "ok")])),
        hlr_layer(
            hlr_dir,
            waivers=write_waivers(
                tmp_path,
                "hw.yaml",
                [("hlr_x.1", "no LLR"), ("hlr_x.2", "no LLR"), ("hlr_x.3", "no LLR")],
            ),
        ),
        llr_layer(llr_dir),
    ]
    assert summarize(check_trace(chain)) == [
        ("E-TRACE-UNTRACED", "error", "LLR 'llr_y.1' traces to no HLR node and is not derived")
    ]


# -- layer subsets ------------------------------------------------------------
#
# The inventory-backed layers cost an Ada toolchain, which `make validate-reqs`
# and the cheap CI job do not have. Selecting a subset lets them keep checking the
# layers they *can* reach instead of checking nothing.


def test_select_layers_keeps_the_named_layers_in_file_order(tmp_path: Path) -> None:
    """A subset keeps the chain's own order, whatever order the names come in."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, partial=True)
    selected, diags = select_layers(chain, ["TEST", "LLR"], tmp_path / "trace_chain.yaml")
    assert [layer.name for layer in selected] == ["LLR", "TEST"]
    assert diags == []


def test_select_layers_rejects_an_unknown_name(tmp_path: Path) -> None:
    """A typo'd layer name is an error, not a silently smaller chain."""
    chain = llr_test_chain(tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, partial=True)
    _selected, diags = select_layers(chain, ["LLR", "TESTS"], tmp_path / "trace_chain.yaml")
    assert summarize(diags) == [("E-TRACE-LAYER", "error", "no layer named 'TESTS' in this chain")]


def test_cli_layers_skips_the_layer_left_out(tmp_path: Path) -> None:
    """`--layers` omitting TEST passes even though the TEST inventory is missing."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    chain.write_text(
        chain.read_text(encoding="utf-8") + "  - {name: TEST, kind: ada-tests, path: absent.json,"
        " id_pattern: '(.+\\.\\d+)', partial_coverage: true}\n",
        encoding="utf-8",
    )
    # With TEST in the chain the missing inventory fails the run...
    assert runner.invoke(app, ["trace", "--chain", str(chain), "--complete"]).exit_code != 0
    # ...and without it the requirements-only portion is checked on its own.
    result = runner.invoke(
        app, ["trace", "--chain", str(chain), "--complete", "--layers", "CONOPS,HLR"]
    )
    assert result.exit_code == 0, result.output


def test_cli_layers_reports_an_unknown_layer(tmp_path: Path) -> None:
    """`--layers NOSUCH` fails with E-TRACE-LAYER rather than checking nothing."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(
        app, ["trace", "--chain", str(chain), "--complete", "--layers", "CONOPS,NOSUCH"]
    )
    assert result.exit_code != 0
    assert "E-TRACE-LAYER" in result.output


def test_cli_layers_orphaning_a_parent_is_reported(tmp_path: Path) -> None:
    """Selecting a layer without its parent is E-TRACE-PARENT, not a silent skip."""
    (tmp_path / "llr").mkdir()
    write_req(tmp_path / "llr", "llr_x.yaml", "parent_req", [["hlr_a.1"]])
    write_inventory(tmp_path / "code_inventory.json")
    chain = tmp_path / "trace_chain.yaml"
    chain.write_text(
        "layers:\n"
        "  - {name: LLR, kind: requirement-yaml, path: llr, id_pattern: '(.+\\.\\d+)'}\n"
        "  - {name: TEST, kind: ada-tests, path: test_inventory.json,"
        " id_pattern: '(.+\\.\\d+)', partial_coverage: true}\n"
        "  - {name: CODE, kind: ada-entities, path: code_inventory.json, parent: LLR,"
        " partial_coverage: true, refs_point_down: true, ref_field: implemented_by}\n",
        encoding="utf-8",
    )
    result = runner.invoke(
        app, ["trace", "--chain", str(chain), "--complete", "--layers", "TEST,CODE"]
    )
    assert result.exit_code != 0
    assert "E-TRACE-PARENT" in result.output
