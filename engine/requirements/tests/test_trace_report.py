"""
Tests for the machine-readable trace report (`reqs trace --format json`).

The report is built from the same rows the tables render and the same
diagnostics `check` reports (see `TraceChecker.to_report`), so these tests pin
that agreement: every gap a diagnostic names must appear as a red-status row,
and vice versa.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import TYPE_CHECKING, Any, cast

from test_trace import (
    COVERING,
    TWO_LLRS,
    conops_hlr_chain,
    llr_code_chain,
    llr_layer,
    llr_test_chain,
    write_chain_file,
    write_code,
    write_llr_with_code_refs,
)
from typer.testing import CliRunner

from reqs.checks.trace import TRACE_REPORT_SCHEMA_VERSION, Layer, TraceChecker
from reqs.cli import app

if TYPE_CHECKING:
    from collections.abc import Sequence

runner = CliRunner()

CHAIN = Path("trace_chain.yaml")


def report_for(
    layers: Sequence[Layer], *, complete: bool = False, allow_unselected: Sequence[str] = ()
) -> dict[str, Any]:
    """Build the report payload for a chain, as the CLI would."""
    checker = TraceChecker(list(layers), complete=complete, allow_unselected=allow_unselected)
    return checker.to_report(chain=CHAIN)


def rows_by_node(rows: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    """Index a row list by node id."""
    return {cast("str", row["node"]): row for row in rows}


# --- payload shape ------------------------------------------------------------


def test_report_carries_schema_version_and_verdict(tmp_path: Path) -> None:
    """The payload identifies its schema and carries the verdict inside."""
    report = report_for(conops_hlr_chain(tmp_path, COVERING), complete=True)  # 1.1 uncovered
    assert report["schema_version"] == TRACE_REPORT_SCHEMA_VERSION
    assert report["chain"] == str(CHAIN)
    assert report["complete"] is True
    assert report["corpus_valid"] is True
    assert report["errors"] == 1
    assert report["warnings"] == 0


def test_report_lists_layers_with_node_counts(tmp_path: Path) -> None:
    """Each layer appears with its config and the number of nodes it enumerates."""
    report = report_for(conops_hlr_chain(tmp_path, COVERING))
    conops, hlr = report["layers"]
    assert (conops["name"], conops["kind"], conops["node_count"]) == (
        "CONOPS",
        "markdown-leaves",
        4,
    )
    assert (hlr["name"], hlr["node_count"]) == ("HLR", 3)


# --- rows agree with the diagnostics -------------------------------------------


def test_uncovered_diagnostic_has_its_row(tmp_path: Path) -> None:
    """A leaf the gate flags UNCOVERED is an UNCOVERED row of the coverage matrix."""
    report = report_for(conops_hlr_chain(tmp_path, COVERING), complete=True)
    (pair,) = report["pairs"]
    row = rows_by_node(pair["upper_rows"])["1.1"]
    assert row["status"] == "UNCOVERED"
    assert row["refs"] == []
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-UNCOVERED"]
    assert "1.1" in report["diagnostics"][0]["message"]


def test_dangling_ref_has_its_row_and_names_the_ref(tmp_path: Path) -> None:
    """A dangling up-ref is a DANGLING row naming the unresolvable ref."""
    chain = conops_hlr_chain(
        tmp_path, [["CONOPS §2.1", "CONOPS §9.9"], ["CONOPS §2.2"], ["CONOPS §3.1"]]
    )
    report = report_for(chain)
    (pair,) = report["pairs"]
    row = rows_by_node(pair["lower_rows"])["hlr_x.1"]
    assert row["status"] == "DANGLING"
    assert row["refs"] == ["CONOPS §9.9"]
    assert "E-TRACE-DANGLING" in [d["code"] for d in report["diagnostics"]]


def test_waived_and_covered_rows_are_not_gaps(tmp_path: Path) -> None:
    """Waived rows carry their reason; covered rows cite their coverage."""
    chain = conops_hlr_chain(tmp_path, COVERING, waive=[("1.1", "physical assumption")])
    report = report_for(chain, complete=True)
    assert report["errors"] == 0
    (pair,) = report["pairs"]
    rows = rows_by_node(pair["upper_rows"])
    assert rows["1.1"]["status"] == "WAIVED"
    assert rows["1.1"]["detail"] == "physical assumption"
    assert rows["2.1"]["status"] == "OK"
    assert rows["2.1"]["refs"] == ["hlr_x.1"]


def test_derived_statement_row_is_derived(tmp_path: Path) -> None:
    """A derived statement is a DERIVED row of the upward matrix, not a gap."""
    chain = conops_hlr_chain(tmp_path, [*COVERING, None])  # hlr_x.4 is derived
    report = report_for(chain)
    (pair,) = report["pairs"]
    assert rows_by_node(pair["lower_rows"])["hlr_x.4"]["status"] == "DERIVED"


# --- verification section -------------------------------------------------------


def test_method_pair_moves_its_upper_side_into_verification(tmp_path: Path) -> None:
    """A method pair's upper rows live in the merged verification matrix."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1"]},
        method="test",
        verifications=["test", "review"],
    )
    report = report_for(chain, complete=True)
    (pair,) = report["pairs"]
    assert pair["method"] == "test"
    assert pair["upper_rows"] == []  # the verification matrix holds them
    (verification,) = report["verification"]
    assert verification["layer"] == "LLR"
    rows = rows_by_node(verification["rows"])
    assert rows["llr_x.1"]["status"] == "OK"
    assert rows["llr_x.1"]["methods"] == [
        {"method": "test", "status": "OK", "evidence": ["u.Test_A"]}
    ]
    assert rows["llr_x.2"]["status"] == "REVIEW"
    assert rows["llr_x.2"]["methods"] == [
        {"method": "review", "status": "REVIEW", "evidence": ["fixture"]}
    ]
    assert rows["llr_x.2"]["detail"] == "review: fixture"


def test_unverified_and_uncovered_statements_are_red_rows(tmp_path: Path) -> None:
    """Statements the gate flags surface as UNVERIFIED / UNCOVERED verification rows."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.1", "llr_x.2"]},
        method="test",
        verifications=["test", None],  # llr_x.2 declares nothing yet is covered
    )
    report = report_for(chain, complete=True)
    (verification,) = report["verification"]
    rows = rows_by_node(verification["rows"])
    assert rows["llr_x.2"]["status"] == "UNVERIFIED"
    codes = [d["code"] for d in report["diagnostics"]]
    assert "E-TRACE-UNVERIFIED" in codes

    chain = llr_test_chain(
        tmp_path, TWO_LLRS, {"Test_A": ["llr_x.1"]}, method="test", verifications=["test", "test"]
    )
    report = report_for(chain, complete=True)
    (verification,) = report["verification"]
    rows = rows_by_node(verification["rows"])
    assert rows["llr_x.2"]["status"] == "UNCOVERED"
    assert rows["llr_x.2"]["methods"] == [{"method": "test", "status": "UNCOVERED", "evidence": []}]
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-UNCOVERED"]


def test_declared_method_without_its_layer_is_open_not_verified(tmp_path: Path) -> None:
    """An LLR declaring `proof` under a test-only chain is UNSELECTED: open work."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.2"]},
        method="test",
        verifications=["proof", "test"],
    )
    report = report_for(chain, complete=True)
    (verification,) = report["verification"]
    rows = rows_by_node(verification["rows"])
    assert rows["llr_x.1"]["status"] == "UNSELECTED"
    assert rows["llr_x.1"]["methods"] == [
        {"method": "proof", "status": "UNSELECTED", "evidence": []}
    ]
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-UNSELECTED"]
    assert report["errors"] == 1


def test_allow_unselected_keeps_the_open_status_but_not_the_error(tmp_path: Path) -> None:
    """A deferred method still renders UNSELECTED -- visible open work, not a verdict."""
    chain = llr_test_chain(
        tmp_path,
        TWO_LLRS,
        {"Test_A": ["llr_x.2"]},
        method="test",
        verifications=["proof", "test"],
    )
    report = report_for(chain, complete=True, allow_unselected=["proof"])
    (verification,) = report["verification"]
    rows = rows_by_node(verification["rows"])
    assert rows["llr_x.1"]["status"] == "UNSELECTED"
    assert report["diagnostics"] == []
    assert report["errors"] == 0


def test_missing_conops_document_reports_invalid_corpus(tmp_path: Path) -> None:
    """A missing CONOPS path yields the invalid-corpus payload, not a traceback."""
    chain = conops_hlr_chain(tmp_path, COVERING)
    chain[0].path.unlink()
    report = report_for(chain)
    assert report["corpus_valid"] is False
    assert report["pairs"] == []
    assert "E-IO" in [d["code"] for d in report["diagnostics"]]


# --- down pairs -----------------------------------------------------------------


def test_down_pair_reports_both_directions(tmp_path: Path) -> None:
    """A down pair's rows cover implementation and required-by, like the tables."""
    chain = llr_code_chain(
        tmp_path,
        [
            (["hlr_a.1"], ["Conflicts.Compatible"]),
            (["hlr_a.2"], ["Conflicts.Nope"]),
            (["hlr_a.3"], []),
        ],
        ["Conflicts.Compatible", "Conflicts.Helper"],
    )
    report = report_for(chain)
    (pair,) = report["pairs"]
    assert pair["refs_point_down"] is True
    assert pair["ref_field"] == "implemented_by"
    upper = rows_by_node(pair["upper_rows"])
    assert upper["llr_x.1"]["status"] == "OK"
    assert upper["llr_x.1"]["refs"] == ["Conflicts.Compatible"]
    assert upper["llr_x.2"]["status"] == "DANGLING"
    assert upper["llr_x.3"]["status"] == "UNIMPLEMENTED"
    lower = rows_by_node(pair["lower_rows"])
    assert lower["Conflicts.Helper"]["status"] == "NO REQUIREMENT"


def test_non_partial_down_pair_uncovered_row_matches_the_gate(tmp_path: Path) -> None:
    """Without partial coverage an unimplemented node is UNCOVERED, as the gate says."""
    llr_dir = write_llr_with_code_refs(tmp_path, [(["hlr_a.1"], [])])
    layers = [
        llr_layer(llr_dir),
        Layer(
            "CODE",
            "ada-entities",
            write_code(tmp_path, "Conflicts.Compatible"),
            parent="LLR",
            refs_point_down=True,
            ref_field="implemented_by",
        ),
    ]
    report = report_for(layers, complete=True)
    (pair,) = report["pairs"]
    assert rows_by_node(pair["upper_rows"])["llr_x.1"]["status"] == "UNCOVERED"
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-UNCOVERED"]


# --- invalid corpora --------------------------------------------------------------


def test_invalid_config_omits_matrices(tmp_path: Path) -> None:
    """On a broken chain config the matrices are omitted, not fabricated."""
    layers = [
        Layer("X", "requirement-yaml", tmp_path),
        Layer("Y", "requirement-yaml", tmp_path, refs_point_down=True),  # no ref_field
    ]
    report = report_for(layers)
    assert report["corpus_valid"] is False
    assert report["pairs"] == []
    assert report["verification"] == []
    assert all(layer["node_count"] is None for layer in report["layers"])  # nothing was loaded
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-CONFIG"]


def test_empty_chain_is_a_config_error() -> None:
    """A chain with nothing to trace must not report as fully traced."""
    report = report_for([])
    assert report["corpus_valid"] is False
    assert [d["code"] for d in report["diagnostics"]] == ["E-TRACE-CONFIG"]


def test_invalid_corpus_omits_matrices(tmp_path: Path) -> None:
    """On a broken corpus the layers are recorded but the matrices are omitted."""
    conops = tmp_path / "conops.md"
    conops.write_text("- **1.1 ◆** A leaf.\n", encoding="utf-8")
    hlr_dir = tmp_path / "hlr"
    hlr_dir.mkdir()
    (hlr_dir / "hlr_x.yaml").write_text(": not yaml [", encoding="utf-8")
    report = report_for(
        [
            Layer("CONOPS", "markdown-leaves", conops),
            Layer("HLR", "requirement-yaml", hlr_dir, id_pattern=r"CONOPS §(\d+\.\d+)"),
        ]
    )
    assert report["corpus_valid"] is False
    assert report["pairs"] == []
    assert cast("int", report["errors"]) >= 1


# --- CLI ---------------------------------------------------------------------------


def test_cli_json_exits_zero_despite_gaps_and_records_verdict(tmp_path: Path) -> None:
    """`--format json` exits 0 once written; the verdict travels in the payload."""
    chain = write_chain_file(tmp_path, [])  # 1.1 uncovered: the text gate would fail
    out = tmp_path / "reports" / "trace_report.json"
    result = runner.invoke(
        app, ["trace", "--chain", str(chain), "--complete", "--format", "json", "-o", str(out)]
    )
    assert result.exit_code == 0, result.output
    report = json.loads(out.read_text(encoding="utf-8"))
    assert report["errors"] == 1
    assert report["corpus_valid"] is True
    assert report["command"].startswith("reqs trace")
    assert report["generated_at"]
    assert report["chain"] == str(chain)


def test_cli_json_defaults_to_stdout(tmp_path: Path) -> None:
    """Without --output the payload goes to stdout, parseable as-is."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    result = runner.invoke(app, ["trace", "--chain", str(chain), "--format", "json"])
    assert result.exit_code == 0, result.output
    report = json.loads(result.output)
    assert report["schema_version"] == TRACE_REPORT_SCHEMA_VERSION
    assert report["errors"] == 0


def test_cli_output_requires_json_format(tmp_path: Path) -> None:
    """`--output` with a non-json format is a usage error, not a silent no-op."""
    chain = write_chain_file(tmp_path, [("1.1", "ok")])
    out = tmp_path / "r.json"
    result = runner.invoke(app, ["trace", "--chain", str(chain), "-o", str(out)])
    assert result.exit_code != 0
    assert not out.exists()
