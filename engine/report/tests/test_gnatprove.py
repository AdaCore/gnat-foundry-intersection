"""Tests for the gnatprove artifact parser."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from vreport.gnatprove import collect_proof
from vreport.model import (
    ArtifactParseError,
    CheckStatus,
    MissingArtifactsError,
    ProofEvidence,
)

FIXTURES = Path(__file__).parent / "fixtures" / "gnatprove"


def test_units(proof: ProofEvidence) -> None:
    """One unit per .spark file, sorted."""
    assert proof.units == [
        "buses",
        "buses_proof",
        "conflicts",
        "controller",
        "main",
        "state_machine_loop",
        "state_machine_loop_proof",
        "synthetic",
    ]


def test_header(proof: ProofEvidence) -> None:
    """The --output-header block is parsed field by field."""
    assert proof.header is not None
    assert proof.header.version == "FSF 16.1.0"
    assert proof.header.command_line is not None
    assert "--assumptions" in proof.header.command_line


def test_summary_text(proof: ProofEvidence) -> None:
    """The summary table is captured verbatim, including the steps line."""
    assert proof.summary_text is not None
    assert "Summary of SPARK analysis" in proof.summary_text
    assert "max steps used" in proof.summary_text


def test_version_text(proof: ProofEvidence) -> None:
    """gnatprove-version.txt records the prover versions."""
    assert proof.version_text is not None
    assert "Alt-Ergo" in proof.version_text


def test_check_counts(proof: ProofEvidence) -> None:
    """Real controller checks plus the synthetic ones are all collected."""
    controller = [c for c in proof.checks if c.unit == "controller"]
    synthetic = [c for c in proof.checks if c.unit == "synthetic"]
    assert len(controller) == 23  # 13 flow + 10 proof
    assert len(synthetic) == 4  # 1 flow + 3 proof
    assert all(c.status is CheckStatus.proved for c in controller)


def test_unproved(proof: ProofEvidence) -> None:
    """Unproved checks are recognized by their non-info severity."""
    unproved = proof.unproved_checks
    assert {c.rule for c in unproved} == {"UNINITIALIZED", "VC_OVERFLOW_CHECK"}
    assert all(c.unit == "synthetic" for c in unproved)


def test_justified(proof: ProofEvidence) -> None:
    """A "suppressed" field marks the check as justified and keeps the reason."""
    justified = proof.justified_checks
    assert len(justified) == 1
    assert justified[0].rule == "VC_ASSERT"
    assert justified[0].justification is not None
    assert "queue is bounded" in justified[0].justification


def test_prover_stats(proof: ProofEvidence) -> None:
    """Prover effort is attached to proved checks."""
    synth = next(c for c in proof.checks if c.unit == "synthetic" and c.rule == "VC_RANGE_CHECK")
    assert synth.provers["CVC5"].max_steps == 42
    real = [c for c in proof.checks if c.unit == "controller" and c.provers]
    assert any(s.max_steps > 0 for c in real for s in c.provers.values())


def test_assumes(proof: ProofEvidence) -> None:
    """Pragma Assume occurrences are enumerated with their entity."""
    assert len(proof.assumes) == 1
    assume = proof.assumes[0]
    assert assume.entity == "Synth.Off"
    assert str(assume.location) == "synth.adb:40:7"


def test_skips(proof: ProofEvidence) -> None:
    """Skip annotations are enumerated."""
    assert len(proof.skips) == 1
    assert proof.skips[0].entity == "Synth.Off"
    assert proof.skips[0].kind == "skip_proof"


def test_spark_modes(proof: ProofEvidence) -> None:
    """The SPARK_Mode map distinguishes all/spec/no per entity."""
    main = [m for m in proof.spark_modes if m.unit == "main"]
    assert len(main) == 1
    assert main[0].entity == "Main"
    assert main[0].mode == "no"
    assert proof.unit_fully_in_spark("controller")
    assert not proof.unit_fully_in_spark("main")
    assert not proof.unit_fully_in_spark("nonexistent")
    outside = {m.entity for m in proof.non_spark_entities}
    assert {"Main", "Synth.Spec_Only", "Synth.Off"} <= outside


def test_claims(proof: ProofEvidence) -> None:
    """--assumptions claims resolve entity names on both sides."""
    synth = [c for c in proof.claims if c.unit == "synthetic"]
    assert len(synth) == 1
    assert synth[0].claim.entity == "Synth.Proven"
    assert synth[0].assumptions[0].entity == "External.Helper"
    controller = [c for c in proof.claims if c.unit == "controller"]
    assert len(controller) == 18


def test_sarif(proof: ProofEvidence) -> None:
    """SARIF supplies the invocation record and (suppressed) warnings."""
    assert proof.sarif_found
    assert proof.invocation is not None
    assert proof.invocation.exit_code == 0
    assert proof.invocation.pass_results == 1
    assert proof.invocation.open_results == 1
    assert len(proof.warnings) == 1
    warning = proof.warnings[0]
    assert warning.rule == "operator-reassociation"
    assert warning.suppressed
    assert warning.location is not None
    assert warning.location.file == "controller.adb"


def test_sarif_absent_falls_back_to_spark_warnings(tmp_path: Path) -> None:
    """Without SARIF, warnings come from .spark warn_error, and the gap is flagged."""
    (tmp_path / "unit.spark").write_text(
        json.dumps(
            {
                "spark": {},
                "entities": {},
                "flow": [],
                "proof": [],
                "warn_error": [
                    {
                        "file": "unit.adb",
                        "line": 4,
                        "col": 8,
                        "rule": "operator-reassociation",
                        "severity": "warning",
                        "suppressed": "",
                        "message": {"text": "possible reassociation"},
                    },
                    {
                        "file": "unit.adb",
                        "line": 9,
                        "col": 1,
                        "rule": "imprecise-address",
                        "severity": "warning",
                        "message": {"text": "imprecisely supported address"},
                    },
                    {
                        "file": "unit.adb",
                        "line": 12,
                        "col": 1,
                        "rule": "error",
                        "severity": "info",
                        "message": {"text": "unrolling loop"},
                    },
                ],
            }
        )
    )
    proof = collect_proof(tmp_path)
    assert not proof.sarif_found
    assert proof.invocation is None
    assert [w.rule for w in proof.warnings] == ["operator-reassociation", "imprecise-address"]
    # Suppression is marked by the key's presence, even with an empty reason.
    assert proof.warnings[0].suppressed
    assert not proof.warnings[1].suppressed
    assert proof.warnings[0].location is not None
    assert proof.warnings[0].location.line == 4


def test_analysis_completion_records(proof: ProofEvidence) -> None:
    """Each unit carries its progress/stop_reason; an early stop is incomplete."""
    assert len(proof.analyses) == len(proof.units)
    incomplete = proof.incomplete_analyses
    assert [a.unit for a in incomplete] == ["synthetic"]
    assert incomplete[0].stop_reason == "STOP_REASON_CHECK_MODE"
    controller = next(a for a in proof.analyses if a.unit == "controller")
    assert controller.complete


def test_instance_analysis_locations(proof: ProofEvidence) -> None:
    """Checks proved at the generic's own lines live in the instantiating unit."""
    harness = [c for c in proof.checks if c.unit == "state_machine_loop_proof"]
    assert any(c.location.file == "state_machine_loop.adb" for c in harness)


def test_generic_units_are_not_incomplete(proof: ProofEvidence) -> None:
    """A skipped generic is the normal outcome, not an early stop."""
    generic = next(a for a in proof.analyses if a.unit == "state_machine_loop")
    assert generic.generic
    assert not generic.complete
    assert generic not in proof.incomplete_analyses
    assert [a.unit for a in proof.generic_analyses] == ["state_machine_loop"]


def test_generic_instance_evidence(proof: ProofEvidence) -> None:
    """A generic counts as analyzed through whichever unit located checks in it."""
    assert proof.instance_units("state_machine_loop") == ["state_machine_loop_proof"]
    assert proof.uninstantiated_generics == []


def test_nested_generic_instance_evidence(proof: ProofEvidence) -> None:
    """
    A generic nested in an ordinary unit is found the same way, by location.

    gnatprove reports the *unit* `buses` as fully analyzed and not generic, so
    the generic-unit checks never see its two nested bus generics. What does
    see them is the check located in `buses.ads` and recorded under the unit
    that instantiates them.
    """
    host = next(a for a in proof.analyses if a.unit == "buses")
    assert host.complete
    assert not host.generic
    assert not [c for c in proof.checks if c.unit == "buses"]
    assert proof.instance_units("buses") == ["buses_proof"]


def test_generic_without_an_instance(tmp_path: Path) -> None:
    """Drop the instantiating unit and the generic stands alone, unanalyzed."""
    src = Path(__file__).parent / "fixtures" / "gnatprove"
    for name in ("gnatprove.out", "state_machine_loop.spark"):
        (tmp_path / name).write_text((src / name).read_text())
    proof = collect_proof(tmp_path)
    assert [a.unit for a in proof.uninstantiated_generics] == ["state_machine_loop"]
    assert proof.instance_units("state_machine_loop") == []


def test_missing_artifacts(tmp_path: Path) -> None:
    """An empty directory is a hard error, not an empty report."""
    with pytest.raises(MissingArtifactsError):
        collect_proof(tmp_path)


def test_corrupt_spark_names_the_file(tmp_path: Path) -> None:
    """A truncated .spark fails with the offending path, not a bare traceback."""
    (tmp_path / "broken.spark").write_text("{ not json")
    with pytest.raises(ArtifactParseError, match=r"broken\.spark"):
        collect_proof(tmp_path)
