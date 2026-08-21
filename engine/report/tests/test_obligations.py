"""Tests for the review-obligation synthesis."""

from __future__ import annotations

from vreport.model import (
    EXEMPTED,
    FULLY_COVERED,
    NOT_COVERED,
    TOTAL_OBLIGATIONS,
    UNDETERMINED,
    AssumptionClaim,
    AssumptionRef,
    CodeInventory,
    CoverageEvidence,
    CoverageViolation,
    Evidence,
    GitInfo,
    GnatproveHeader,
    MethodFacet,
    Obligation,
    ObligationStats,
    ObligationStatus,
    ProofCheck,
    ProofEvidence,
    Sloc,
    SparkModeEntry,
    TraceabilityEvidence,
    TraceDiagnostic,
    TracePair,
    TraceReport,
    TraceRow,
    UnitAnalysis,
    VerificationMatrix,
    VerificationRow,
)
from vreport.obligations import (
    ViolationClass,
    build_obligations,
    classify_violation,
    open_claims,
    open_trace_items,
    review_verified_rows,
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


_COMPLETE = UnitAnalysis(unit="pkg", progress="PROGRESS_PROOF", stop_reason="STOP_REASON_NONE")

_GENERIC = UnitAnalysis(
    unit="gen", progress="PROGRESS_NONE", stop_reason="STOP_REASON_GENERIC_UNIT"
)


_CLEAN_REPORT = TraceReport(complete=True, corpus_valid=True)

# The real pipeline always inventories the sources, so the default is "parsed,
# and it declares no generics" -- pass inventory=None for the fallback path.
_EMPTY_INVENTORY = CodeInventory(schema_version=3, project="synthetic.gpr")


def _evidence(
    proof: ProofEvidence | None = None,
    coverage: CoverageEvidence | None = None,
    traceability: TraceabilityEvidence | None = None,
    inventory: CodeInventory | None = _EMPTY_INVENTORY,
) -> Evidence:
    """Synthetic evidence with clean defaults, overridable per aspect."""
    return Evidence(
        proof=proof if proof is not None else ProofEvidence(),
        coverage=coverage if coverage is not None else CoverageEvidence(level="stmt"),
        traceability=traceability
        if traceability is not None
        else TraceabilityEvidence(waivers_found=True, hlr_found=True, report=_CLEAN_REPORT),
        git=GitInfo(commit="abc", branch="main", dirty=False),
        inventory=inventory,
    )


def test_classification(proof: ProofEvidence) -> None:
    """Violations classify by where proved checks actually are, per file."""
    cases = {
        # The instantiation harness itself.
        "src/proof/state_machine_loop_proof.ads": ViolationClass.proof_support,
        # Never analyzed at all (SPARK_Mode off).
        "src/app/main.adb": ViolationClass.no_evidence,
        # Proved checks located in the file itself.
        "src/core/controller.adb": ViolationClass.proved_file,
        # Generic proved via the harness instance: checks land at these lines.
        "src/core/state_machine_loop.adb": ViolationClass.proved_file,
        # Nested generic proved through the harness instance: the checks are
        # located in the spec, so the body is credited across the unit.
        "src/types/buses.adb": ViolationClass.proved_file,
        "src/types/buses.ads": ViolationClass.proved_file,
        # File containing unproved checks: proof evidence there is tainted.
        "synth.adb": ViolationClass.no_evidence,
    }
    for file, expected in cases.items():
        assert classify_violation(_violation(file), proof) is expected, file


def test_tainted_unit_is_not_credited_across_its_sources(proof: ProofEvidence) -> None:
    """
    An unproved check anywhere in the unit withdraws the credit from all of it.

    Instance evidence is carried from a generic's spec to its body, so the
    taint has to travel the same way: otherwise a body would read as proved
    on the strength of a spec whose own check failed.
    """
    unproved = ProofCheck(
        unit="buses_proof",
        kind="proof",
        rule="VC_OVERFLOW_CHECK",
        severity="medium",
        location=Sloc(file="buses.ads", line=32),
    )
    tainted = proof.model_copy(update={"checks": [*proof.checks, unproved]})
    assert classify_violation(_violation("src/types/buses.adb"), tainted) is (
        ViolationClass.no_evidence
    )


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


def test_idents_unique(evidence: Evidence) -> None:
    """Obligation identifiers are unique and sequential."""
    obligations = build_obligations(evidence)
    idents = [o.ident for o in obligations]
    assert idents == [f"R-{i}" for i in range(1, len(obligations) + 1)]


def test_statuses_on_fixture_evidence(evidence: Evidence) -> None:
    """The fixture evidence (with synthetic findings) marks the right items."""
    by_anchor = _by_anchor(build_obligations(evidence))
    expect_review = {
        "proof-completeness",  # synthetic.spark records an early stop
        "proof-unproved",
        "proof-justified",
        "proof-assumes",
        "proof-skips",
        "proof-warnings",
        "proof-spark-modes",
        "proof-claims",
        "coverage-violations",
        "coverage-exemptions",
        "traceability-gaps",  # the fixture report carries open items
        "traceability-verification",  # ...and a review-verified statement
        "traceability-waivers",
        "traceability-derived",
        "traceability-conops",
    }
    for anchor in expect_review:
        assert by_anchor[anchor].status is ObligationStatus.review, anchor
    assert by_anchor["provenance-git"].status is ObligationStatus.ok
    # The fixture records a gnatprove and a gnatcov version.
    assert by_anchor["provenance-tools"].status is ObligationStatus.ok
    # The fixture gnatprove.out records a `-f` command line.
    assert by_anchor["provenance-invocations"].status is ObligationStatus.ok


def test_statuses_on_clean_evidence() -> None:
    """Empty findings collapse to OK; the always-human items stay review."""
    clean = _evidence(proof=ProofEvidence(sarif_found=True, analyses=[_COMPLETE]))
    by_anchor = _by_anchor(build_obligations(clean))
    machine_ok = {
        "proof-completeness",
        "proof-unproved",
        "proof-justified",
        "proof-assumes",
        "proof-skips",
        "proof-warnings",
        "proof-spark-modes",
        "proof-claims",
        "coverage-violations",
        "coverage-exemptions",
        "traceability-gaps",
        "traceability-verification",
        "traceability-waivers",
        "traceability-derived",
        "provenance-git",
    }
    for anchor in machine_ok:
        assert by_anchor[anchor].status is ObligationStatus.ok, anchor
    assert by_anchor["traceability-conops"].status is ObligationStatus.review
    # No recorded command line means the forced-run claim cannot be made.
    assert by_anchor["provenance-invocations"].status is ObligationStatus.review
    # ...and synthetic evidence records no tool versions.
    assert by_anchor["provenance-tools"].status is ObligationStatus.review


def test_missing_tool_version_forces_review() -> None:
    """A tool with no recorded version is named, and holds its item open."""
    both = _evidence(
        proof=ProofEvidence(version_text="FSF 16.1.0"),
        coverage=CoverageEvidence(level="stmt", version_text="GNATcoverage FSF 26.2"),
    )
    recorded = _by_anchor(build_obligations(both))["provenance-tools"]
    assert recorded.status is ObligationStatus.ok
    assert "gnatprove" not in recorded.title

    coverage_only = both.model_copy(
        update={"proof": ProofEvidence(version_text=None)},
    )
    partial = _by_anchor(build_obligations(coverage_only))["provenance-tools"]
    assert partial.status is ObligationStatus.review
    assert partial.title == "Tool versions not recorded: gnatprove"
    assert "gnatcov" not in partial.detail

    neither = _by_anchor(build_obligations(_evidence()))["provenance-tools"]
    assert neither.status is ObligationStatus.review
    assert neither.title == "Tool versions not recorded: gnatprove and gnatcov"


def test_missing_requirements_tree_forces_review() -> None:
    """An absent requirements tree is absence of evidence, never a green tick."""
    by_anchor = _by_anchor(build_obligations(_evidence(traceability=TraceabilityEvidence())))
    for anchor in ("traceability-waivers", "traceability-derived"):
        assert by_anchor[anchor].status is ObligationStatus.review, anchor
        assert "not found" in by_anchor[anchor].title


def test_each_traceability_source_forces_its_own_review() -> None:
    """A single missing source flips only its own obligation to review."""
    no_waivers = _evidence(traceability=TraceabilityEvidence(hlr_found=True))
    by_anchor = _by_anchor(build_obligations(no_waivers))
    assert by_anchor["traceability-waivers"].status is ObligationStatus.review
    assert "not found" in by_anchor["traceability-waivers"].title
    assert by_anchor["traceability-derived"].status is ObligationStatus.ok

    no_hlr = _evidence(traceability=TraceabilityEvidence(waivers_found=True))
    by_anchor = _by_anchor(build_obligations(no_hlr))
    assert by_anchor["traceability-waivers"].status is ObligationStatus.ok
    assert by_anchor["traceability-derived"].status is ObligationStatus.review
    assert "not found" in by_anchor["traceability-derived"].title


def test_missing_sarif_forces_warning_review() -> None:
    """No gnatprove.sarif means the warning record is unverifiable, never OK."""
    ob = _by_anchor(build_obligations(_evidence()))["proof-warnings"]
    assert ob.status is ObligationStatus.review
    assert "SARIF record not found" in ob.title


def test_incomplete_or_unrecorded_analyses_force_review() -> None:
    """An early-stopped unit — or no completion records at all — is flagged."""
    stopped = ProofEvidence(
        analyses=[_COMPLETE, UnitAnalysis(unit="cut", progress="PROGRESS_FLOW")],
    )
    ob = _by_anchor(build_obligations(_evidence(proof=stopped)))["proof-completeness"]
    assert ob.status is ObligationStatus.review
    assert ob.title == "Incomplete unit analyses: 1"
    assert any("cut" in item for item in ob.items)

    ob = _by_anchor(build_obligations(_evidence()))["proof-completeness"]
    assert ob.status is ObligationStatus.review
    assert "not recorded" in ob.title


def test_generic_unit_is_not_an_incomplete_analysis() -> None:
    """A generic skipped for want of an instance is not an early stop."""
    evidence = _evidence(proof=ProofEvidence(analyses=[_COMPLETE, _GENERIC]))
    assert _by_anchor(build_obligations(evidence))["proof-completeness"].title == (
        "Incomplete unit analyses: none"
    )


def test_generic_with_an_analyzed_instance_is_ok(evidence: Evidence) -> None:
    """Every declared generic, nested ones included, has an instance behind it."""
    ob = _by_anchor(build_obligations(evidence))["proof-generics"]
    assert ob.status is ObligationStatus.ok
    assert ob.title == "Generics, each analyzed through an instance: 3"
    assert ob.items == [
        "Buses.Display_Bus (package in src/types/buses.ads) — analyzed through buses_proof",
        "Buses.Source_Bus (package in src/types/buses.ads) — analyzed through buses_proof",
        (
            "State_Machine_Loop (procedure in src/core/state_machine_loop.ads) — "
            "analyzed through state_machine_loop_proof"
        ),
    ]


def test_generic_without_an_instance_forces_review() -> None:
    """No instance means nothing in the generic's body is proved: say so."""
    evidence = _evidence(proof=ProofEvidence(analyses=[_COMPLETE, _GENERIC]), inventory=None)
    ob = _by_anchor(build_obligations(evidence))["proof-generics"]
    assert ob.status is ObligationStatus.review
    assert ob.title == "Generics with no analyzed instance: 1"
    assert ob.items == ["gen (unit in gen) — no instance analyzed"]


def test_nested_generic_without_an_instance_forces_review(evidence: Evidence) -> None:
    """
    The case only the inventory can catch: a nested generic nothing instantiates.

    gnatprove reports no stop reason and no entity for it, and a body with
    nothing that can fail contributes no check either — so dropping the
    instantiation must still leave the obligation red.
    """
    proof = evidence.proof.model_copy(
        update={
            "instantiations": [
                i for i in evidence.proof.instantiations if "Display_Wire" not in i.entity
            ]
        }
    )
    ob = _by_anchor(build_obligations(evidence.model_copy(update={"proof": proof})))[
        "proof-generics"
    ]
    assert ob.status is ObligationStatus.review
    assert ob.title == "Generics with no analyzed instance: 1"
    assert "Buses.Display_Bus (package in src/types/buses.ads) — no instance analyzed" in ob.items


def test_missing_inventory_never_reads_as_settled() -> None:
    """Without the declared set, "all generics analyzed" is a claim nothing supports."""
    ob = _by_anchor(build_obligations(_evidence(inventory=None)))["proof-generics"]
    assert ob.status is ObligationStatus.review
    assert "nested in an ordinary package cannot appear" in ob.detail


def test_undetermined_coverage_is_not_green() -> None:
    """Undetermined obligations produce no violation messages but never render OK."""
    coverage = CoverageEvidence(
        level="stmt+mcdc",
        obligations=[
            ObligationStats(
                kind="Stmt",
                counts={TOTAL_OBLIGATIONS: 100, FULLY_COVERED: 60, UNDETERMINED: 40},
            )
        ],
    )
    ob = _by_anchor(build_obligations(_evidence(coverage=coverage)))["coverage-violations"]
    assert ob.status is ObligationStatus.review
    assert "40 undetermined" in ob.title


def test_coverage_counter_mismatch_is_not_green() -> None:
    """Counters reporting gaps that no parsed message explains flip to review."""
    coverage = CoverageEvidence(
        level="stmt+mcdc",
        obligations=[
            ObligationStats(
                kind="Stmt",
                counts={TOTAL_OBLIGATIONS: 10, FULLY_COVERED: 5, NOT_COVERED: 5},
            )
        ],
    )
    ob = _by_anchor(build_obligations(_evidence(coverage=coverage)))["coverage-violations"]
    assert ob.status is ObligationStatus.review
    assert "disagree" in ob.title


def test_unparsed_exemptions_are_not_green() -> None:
    """Exempted counters with no parsed exemption region flip to review."""
    coverage = CoverageEvidence(
        level="stmt+mcdc",
        obligations=[
            ObligationStats(
                kind="Stmt",
                counts={TOTAL_OBLIGATIONS: 10, FULLY_COVERED: 10, EXEMPTED: 2},
            )
        ],
    )
    ob = _by_anchor(build_obligations(_evidence(coverage=coverage)))["coverage-exemptions"]
    assert ob.status is ObligationStatus.review
    assert "disagree" in ob.title


def test_open_claims_unresolved_entities_do_not_discharge() -> None:
    """A claim whose entity failed to resolve discharges nothing."""
    proof = ProofEvidence(
        claims=[
            AssumptionClaim(
                unit="a",
                claim=AssumptionRef(predicate="CLAIM_AORTE", entity=None),
                assumptions=[],
            ),
            AssumptionClaim(
                unit="b",
                claim=AssumptionRef(predicate="CLAIM_AORTE", entity=None),
                assumptions=[AssumptionRef(predicate="CLAIM_AORTE", entity=None)],
            ),
        ],
    )
    assert len(open_claims(proof)) == 1


def test_missing_gnatcov_command_forces_provenance_review() -> None:
    """A forced proof run alone is not enough: the gnatcov command must be recorded."""
    header = GnatproveHeader(command_line="gnatprove -P p.gpr -U -f")
    proof = ProofEvidence(header=header, sarif_found=True, analyses=[_COMPLETE])
    ob = _by_anchor(build_obligations(_evidence(proof=proof)))["provenance-invocations"]
    assert ob.status is ObligationStatus.review
    assert "gnatcov-command.txt" in ob.detail

    with_command = _evidence(
        proof=proof,
        coverage=CoverageEvidence(level="stmt", command_text="gnatcov coverage ..."),
    )
    ob = _by_anchor(build_obligations(with_command))["provenance-invocations"]
    assert ob.status is ObligationStatus.ok


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


def test_trace_fixture_open_items_and_review_rows(trace_report: TraceReport) -> None:
    """The fixture report yields exactly its red rows as open, review rows as reviewed."""
    opened = open_trace_items(trace_report)
    assert [(i.where, i.layer, i.row.node, i.row.status) for i in opened] == [
        ("LLR verification", "LLR", "llr_x.3", "UNCOVERED"),
        ("CONOPS → HLR", "CONOPS", "3.1", "UNCOVERED"),
        ("HLR → CONOPS", "HLR", "hlr_x.3", "DANGLING"),
    ]
    reviewed = review_verified_rows(trace_report)
    assert [(layer, row.node) for layer, row in reviewed] == [("LLR", "llr_x.2")]


def test_trace_gaps_obligation_flags_open_items(evidence: Evidence) -> None:
    """Open matrix rows and rowless gate findings become one review obligation."""
    ob = _by_anchor(build_obligations(evidence))["traceability-gaps"]
    assert ob.status is ObligationStatus.review
    assert "4 open items" in ob.title  # 3 open rows + the rowless waiver lint
    assert "3 gate errors" in ob.title
    for node in ("3.1", "hlr_x.3", "llr_x.3"):
        assert any(f"`{node}`" in item for item in ob.items), node
    assert any("W-TRACE-WAIVER-REDUNDANT" in item for item in ob.items)


def test_review_verified_statements_become_review_items(evidence: Evidence) -> None:
    """Review-verified statements are listed with their recorded justification."""
    ob = _by_anchor(build_obligations(evidence))["traceability-verification"]
    assert ob.status is ObligationStatus.review
    assert ob.title == "Review-verified requirements: 1"
    (item,) = ob.items
    assert "llr_x.2" in item
    assert "MUTCD" in item


def test_missing_trace_report_forces_review() -> None:
    """No trace report is absence of evidence, never a green tick."""
    by_anchor = _by_anchor(
        build_obligations(_evidence(traceability=TraceabilityEvidence(report=None)))
    )
    ob = by_anchor["traceability-gaps"]
    assert ob.status is ObligationStatus.review
    assert "not found" in ob.title
    assert by_anchor["traceability-verification"].status is ObligationStatus.review


def test_invalid_corpus_forces_review_with_diagnostics() -> None:
    """An unanalyzable corpus surfaces its diagnostics instead of matrices."""
    report = TraceReport(
        corpus_valid=False,
        errors=1,
        diagnostics=[
            TraceDiagnostic(level="error", code="E-YAML", message="parse error", file="llr_x.yaml")
        ],
    )
    by_anchor = _by_anchor(
        build_obligations(_evidence(traceability=TraceabilityEvidence(report=report)))
    )
    ob = by_anchor["traceability-diagnostics"]
    assert ob.status is ObligationStatus.review
    assert "corpus invalid" in ob.title
    assert any("E-YAML" in item for item in ob.items)


def test_gate_warnings_alone_keep_the_gaps_obligation_under_review() -> None:
    """Warning-level gate findings (waiver lint) must not render green."""
    report = TraceReport(
        complete=True,
        corpus_valid=True,
        warnings=1,
        diagnostics=[
            TraceDiagnostic(
                level="warning",
                code="W-TRACE-WAIVER-REDUNDANT",
                message="waiver names '2.1', but it is covered",
                file="trace_waivers.yaml",
            )
        ],
    )
    ob = _by_anchor(build_obligations(_evidence(traceability=TraceabilityEvidence(report=report))))[
        "traceability-gaps"
    ]
    assert ob.status is ObligationStatus.review
    assert any("W-TRACE-WAIVER-REDUNDANT" in item for item in ob.items)


def test_unknown_row_status_counts_as_open() -> None:
    """A status this consumer has never seen surfaces as a finding, not silence."""
    report = TraceReport(
        corpus_valid=True,
        pairs=[
            TracePair(
                upper="A",
                lower="B",
                upper_rows=[
                    TraceRow(node="a.1", status="SOMETHING-NEW"),
                    TraceRow(node="a.2", status="WAIVED", detail="reason"),
                ],
            )
        ],
        verification=[
            VerificationMatrix(
                layer="A",
                rows=[
                    VerificationRow(
                        node="a.3",
                        status="REVIEW",
                        methods=[MethodFacet(method="review", status="REVIEW", evidence=["ok"])],
                    )
                ],
            )
        ],
    )
    opened = open_trace_items(report)
    assert [(i.where, i.layer, i.row.node) for i in opened] == [("A → B", "A", "a.1")]
