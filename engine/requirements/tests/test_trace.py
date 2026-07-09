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
from reqs.conops import parse_leaves

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
    lines = ["waivers:"]
    for node, reason in entries:
        lines.append(f'  - leaf: "{node}"')
        lines.append(f"    reason: {reason}")
    p = tmp_path / name
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def conops_layer(path: Path, waivers: Path | None = None) -> Layer:
    return Layer("CONOPS", "markdown-leaves", path, waivers=waivers)


def hlr_layer(hlr_dir: Path, waivers: Path | None = None) -> Layer:
    return Layer(
        "HLR",
        "requirement-yaml",
        hlr_dir,
        id_pattern=r"CONOPS §(\d+\.\d+)",
        waivers=waivers,
    )


def llr_layer(llr_dir: Path) -> Layer:
    return Layer("LLR", "requirement-yaml", llr_dir, id_pattern=r"(.+\.\d+)")


def codes(diags: Sequence[Diagnostic]) -> set[tuple[str, str]]:
    return {(d.code, d.level) for d in diags}


COVERING = [["CONOPS §2.1"], ["CONOPS §2.2"], ["CONOPS §3.1"]]  # covers all but leaf 1.1


def conops_hlr_chain(
    tmp_path: Path,
    statements: Sequence[Sequence[str] | None],
    *,
    waive: Sequence[tuple[str, str]] | None = None,
) -> list[Layer]:
    conops = write_conops(tmp_path)
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir(exist_ok=True)
    write_req(hlr_dir, "hlr_x.yaml", "source", statements)
    waivers = write_waivers(tmp_path, "w.yaml", waive) if waive is not None else None
    return [conops_layer(conops, waivers=waivers), hlr_layer(hlr_dir)]


# --- adapters / config ------------------------------------------------------


def test_parse_leaves_extracts_bullets_only(tmp_path: Path) -> None:
    leaves = parse_leaves(write_conops(tmp_path))
    assert set(leaves) == {"1.1", "2.1", "2.2", "3.1"}
    assert all(isinstance(line, int) and line > 0 for line in leaves.values())


def test_load_chain_resolves_relative_paths(tmp_path: Path) -> None:
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
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "Physical site assumption.")])
    assert check_trace(chain, complete=True) == []


def test_uncovered_leaf_warns_by_default(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING)  # 1.1 uncovered/unwaived
    diags = check_trace(chain)
    assert ("W-TRACE-UNCOVERED", "warning") in codes(diags)
    assert not [d for d in diags if d.level == "error"]


def test_uncovered_leaf_errors_under_complete(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING)
    assert ("E-TRACE-UNCOVERED", "error") in codes(check_trace(chain, complete=True))


def test_waiver_suppresses_uncovered(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "Physical assumption.")])
    diags = check_trace(chain, complete=True)
    assert not [d for d in diags if d.code.endswith("UNCOVERED")]


def test_waiver_for_unknown_node_is_error(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok"), ("9.9", "stale")])
    assert ("E-TRACE-WAIVER-UNKNOWN", "error") in codes(check_trace(chain))


def test_redundant_waiver_warns(tmp_path: Path) -> None:
    # 2.1 is both covered and waived -> the waiver is unnecessary.
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok"), ("2.1", "unnecessary")])
    assert ("W-TRACE-WAIVER-REDUNDANT", "warning") in codes(check_trace(chain))


# --- CONOPS -> HLR, backward (the point-3 fix) ------------------------------


def test_dangling_ref_is_error(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, [["CONOPS §9.9"]])
    assert ("E-TRACE-DANGLING", "error") in codes(check_trace(chain))


def test_hlr_without_source_fails_schema(tmp_path: Path) -> None:
    # Statement 1 has neither source nor derived: a backward gap.
    chain = conops_hlr_chain(tmp_path, [[], *COVERING], waive=[("1.1", "ok")])
    # `[]` writes `source:` with no items.
    assert ("E-SCHEMA", "error") in codes(check_trace(chain))


def test_derived_statement_is_traced_not_untraced(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, [None, *COVERING], waive=[("1.1", "ok")])  # stmt 1 derived
    assert check_trace(chain, complete=True) == []


def test_source_that_is_not_a_conops_ref_is_untraced(tmp_path: Path) -> None:
    # Cites a standard directly instead of a CONOPS leaf -> no valid upward trace.
    chain = conops_hlr_chain(tmp_path, [["MUTCD §4E.01"], *COVERING], waive=[("1.1", "ok")])
    diags = check_trace(chain)
    assert ("E-TRACE-UNTRACED", "error") in codes(diags)
    assert ("E-TRACE-DANGLING", "error") not in codes(diags)  # not a CONOPS ref -> not dangling


# --- generalization: the same engine does HLR -> LLR ------------------------


def test_engine_generalizes_to_hlr_llr(tmp_path: Path) -> None:
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
    diags = check_trace(chain)
    # HLR -> LLR resolution ran: the bad parent_req is dangling.
    assert ("E-TRACE-DANGLING", "error") in codes(diags)
    dangling = [d for d in diags if d.code == "E-TRACE-DANGLING"]
    assert any("hlr_x.99" in d.message for d in dangling)


# --- rendering (point 2) ----------------------------------------------------


def test_render_tables_show_bidirectional_status(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING)  # 1.1 uncovered
    out = render_tables(chain)
    assert "CONOPS" in out
    assert "HLR" in out
    assert "1.1" in out  # forward: the uncovered leaf...
    assert "UNCOVERED" in out  # ...and its status
    assert "hlr_x.1" in out  # backward: the HLR statement appears with its trace


def test_render_tables_wrap_wide_column_to_width(tmp_path: Path) -> None:
    # A leaf covered by many statements makes the "Covered by" cell very wide.
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
    for status in ("UNCOVERED", "UNTRACED", "DANGLING"):
        assert _severity_style(status) == "red bold"
    for status in ("WAIVED", "DERIVED"):
        assert _severity_style(status) == "yellow"
    assert _severity_style("OK") == "green"


def test_render_tables_are_boxed(tmp_path: Path) -> None:
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "ok")])
    out = render_tables(chain, width=80)
    assert "─" in out  # a boxed rich table with row separators, not an ASCII pipe table


# --- CLI --------------------------------------------------------------------


def write_chain_file(tmp_path: Path, waive: Sequence[tuple[str, str]]) -> Path:
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
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--complete"])
    assert result.exit_code == 0, result.output


def test_cli_chain_exit_nonzero_when_uncovered_under_complete(tmp_path: Path) -> None:
    chain = write_chain_file(tmp_path, [])  # 1.1 not waived
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--complete"])
    assert result.exit_code != 0, result.output


def test_cli_format_table_renders(tmp_path: Path) -> None:
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--format", "table"])
    assert result.exit_code == 0, result.output
    assert "CONOPS" in result.output
    assert "hlr_x.1" in result.output
