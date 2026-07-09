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

from typer.testing import CliRunner

from reqs.checks.trace import Layer, _severity_style, check_trace, load_chain, render_tables
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
    tmp_path: Path, name: str, ref_field: str, statements: Sequence[Sequence[str] | None]
) -> Path:
    """Write a requirement file; statements[i] is a list of up-refs, or None => derived."""
    lines = ["description:"]
    for i, refs in enumerate(statements, start=1):
        lines.append(f"  {i}:")
        lines.append(f"    text: The system shall do thing {i}.")
        if refs is None:
            lines.append("    derived: true")
        else:
            lines.append(f"    {ref_field}:")
            lines.extend(f"      - {r}" for r in refs)
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
        ("E-SCHEMA", "error", "'source' must not be null; omit the key instead"),
        uncovered_warning("2.1"),
        uncovered_warning("2.2"),
        uncovered_warning("3.1"),
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
    """Row styles: red for real gaps, yellow for waived/derived, green otherwise."""
    for status in ("UNCOVERED", "UNTRACED", "DANGLING"):
        assert _severity_style(status) == "red bold"
    for status in ("WAIVED", "DERIVED"):
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
