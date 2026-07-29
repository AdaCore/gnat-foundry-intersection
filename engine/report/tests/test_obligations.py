"""Tests for the review-obligation synthesis."""

from __future__ import annotations

from vreport.model import (
    AssumptionClaim,
    AssumptionRef,
    CoverageEvidence,
    CoverageViolation,
    Evidence,
    GitInfo,
    Obligation,
    ObligationStatus,
    ProofCheck,
    ProofEvidence,
    Sloc,
    SparkModeEntry,
    TraceabilityEvidence,
)
from vreport.obligations import (
    ViolationClass,
    build_obligations,
    classify_violation,
    open_claims,
    toolchain_note,
)


def _violation(file: str) -> CoverageViolation:
    return CoverageViolation(
        location=Sloc(file=file, line=1),
        sco="SCO #1: STATEMENT",
        obligation_kind="STATEMENT",
        message="not executed",
        exempted=False,
    )


def _by_anchor(obligations: list[Obligation]) -> dict[str, Obligation]:
    return {o.anchor: o for o in obligations}


def test_classification(proof: ProofEvidence) -> None:
    """Violations classify by where proved checks actually are, per file."""
    cases = {
        # The instantiation harness itself.
        "src/core/state_machine_loop_proof.ads": ViolationClass.proof_support,
        # Never analyzed at all (SPARK_Mode off).
        "src/app/main.adb": ViolationClass.no_evidence,
        # Proved checks located in the file itself.
        "src/core/controller.adb": ViolationClass.proved_file,
        # Generic proved via the harness instance: checks land at these lines.
        "src/core/state_machine_loop.adb": ViolationClass.proved_file,
        # Generic whose bodies were never analyzed: must NOT read as proven.
        "src/types/buses.adb": ViolationClass.no_evidence,
        # File containing unproved checks: proof evidence there is tainted.
        "synth.adb": ViolationClass.no_evidence,
    }
    for file, expected in cases.items():
        assert classify_violation(_violation(file), proof) is expected, file


def test_open_claims(proof: ProofEvidence) -> None:
    """Assumptions closed by other claims or clean analyzed entities are discharged."""
    residual = open_claims(proof)
    assert len(residual) == 1
    claim, refs = residual[0]
    assert claim.claim.entity == "Synth.Proven"
    assert [a.entity for a in refs] == ["External.Helper"]


def _claim_on(entity: str, resting_on: str) -> AssumptionClaim:
    return AssumptionClaim(
        unit="pkg",
        claim=AssumptionRef(predicate="CLAIM_AORTE", entity=entity),
        assumptions=[AssumptionRef(predicate="CLAIM_AORTE", entity=resting_on)],
    )


def test_open_claims_tainted_entity_is_not_discharged() -> None:
    """An analyzed entity with an unproved check cannot discharge assumptions."""
    proof = ProofEvidence(
        checks=[
            ProofCheck(
                unit="pkg",
                kind="proof",
                rule="VC_OVERFLOW_CHECK",
                severity="medium",
                location=Sloc(file="pkg.adb", line=5),
                entity="Pkg.Helper",
            )
        ],
        spark_modes=[
            SparkModeEntry(unit="pkg", entity="Pkg.Helper", mode="all"),
            SparkModeEntry(unit="pkg", entity="Pkg.Caller", mode="all"),
        ],
        claims=[_claim_on("Pkg.Caller", resting_on="Pkg.Helper")],
    )
    residual = open_claims(proof)
    assert len(residual) == 1
    assert [a.entity for a in residual[0][1]] == ["Pkg.Helper"]


def test_open_claims_ambiguous_mode_is_not_discharged() -> None:
    """A name declared with both mode "all" and a lesser mode stays residual."""
    proof = ProofEvidence(
        spark_modes=[
            SparkModeEntry(unit="a", entity="Pkg.Helper", mode="all"),
            SparkModeEntry(unit="b", entity="Pkg.Helper", mode="no"),
            SparkModeEntry(unit="a", entity="Pkg.Caller", mode="all"),
        ],
        claims=[_claim_on("Pkg.Caller", resting_on="Pkg.Helper")],
    )
    assert len(open_claims(proof)) == 1


def test_toolchain_note_follows_recorded_versions() -> None:
    """The qualification note describes the recorded toolchain, not an assumption."""
    assert "FSF community" in toolchain_note("FSF 16.1.0", "GNATcoverage FSF 26.2")
    assert "not FSF" in toolchain_note("Pro 25.1", "GNATcoverage Pro 25.1")
    assert "not recorded" in toolchain_note(None, None)


def test_idents_unique(evidence: Evidence) -> None:
    """Obligation identifiers are unique and sequential."""
    obligations = build_obligations(evidence)
    idents = [o.ident for o in obligations]
    assert idents == [f"R-{i}" for i in range(1, len(obligations) + 1)]


def test_statuses_on_fixture_evidence(evidence: Evidence) -> None:
    """The fixture evidence (with synthetic findings) marks the right items."""
    by_anchor = _by_anchor(build_obligations(evidence))
    expect_review = {
        "proof-unproved",
        "proof-justified",
        "proof-assumes",
        "proof-skips",
        "proof-warnings",
        "proof-spark-modes",
        "proof-claims",
        "coverage-violations",
        "coverage-exemptions",
        "traceability-waivers",
        "traceability-derived",
        "traceability",
        "traceability-conops",
        "provenance-tools",
    }
    for anchor in expect_review:
        assert by_anchor[anchor].status is ObligationStatus.review, anchor
    assert by_anchor["provenance-git"].status is ObligationStatus.ok
    # The fixture gnatprove.out records a `-f` command line.
    assert by_anchor["provenance-invocations"].status is ObligationStatus.ok


def test_statuses_on_clean_evidence() -> None:
    """Empty findings collapse to OK; the always-human items stay review."""
    clean = Evidence(
        proof=ProofEvidence(),
        coverage=CoverageEvidence(level="stmt"),
        traceability=TraceabilityEvidence(sources_found=True),
        git=GitInfo(commit="abc", branch="main", dirty=False),
    )
    by_anchor = _by_anchor(build_obligations(clean))
    machine_ok = {
        "proof-unproved",
        "proof-justified",
        "proof-assumes",
        "proof-skips",
        "proof-warnings",
        "proof-spark-modes",
        "proof-claims",
        "coverage-violations",
        "coverage-exemptions",
        "traceability-waivers",
        "traceability-derived",
        "provenance-git",
    }
    for anchor in machine_ok:
        assert by_anchor[anchor].status is ObligationStatus.ok, anchor
    always_review = {"traceability", "traceability-conops", "provenance-tools"}
    for anchor in always_review:
        assert by_anchor[anchor].status is ObligationStatus.review, anchor
    # No recorded command line means the forced-run claim cannot be made.
    assert by_anchor["provenance-invocations"].status is ObligationStatus.review


def test_dirty_tree_is_flagged() -> None:
    """A dirty working tree (or no git at all) becomes a review item."""
    dirty = Evidence(
        proof=ProofEvidence(),
        coverage=CoverageEvidence(level="stmt"),
        traceability=TraceabilityEvidence(),
        git=GitInfo(commit="abc", branch="main", dirty=True),
    )
    assert _by_anchor(build_obligations(dirty))["provenance-git"].status is (
        ObligationStatus.review
    )
    no_git = dirty.model_copy(update={"git": None})
    assert _by_anchor(build_obligations(no_git))["provenance-git"].status is (
        ObligationStatus.review
    )


def test_items_are_capped(evidence: Evidence) -> None:
    """Long item lists are truncated with an explicit count of what was dropped."""
    many = [_violation(f"src/app/f{i}.adb") for i in range(60)]
    ev = evidence.model_copy(
        update={"coverage": evidence.coverage.model_copy(update={"violations": many})}
    )
    ob = _by_anchor(build_obligations(ev))["coverage-violations"]
    assert len(ob.items) == 41
    assert "and 20 more" in ob.items[-1]
