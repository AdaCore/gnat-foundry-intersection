"""Shared fixtures: evidence built from the checked-in tool artifacts."""

from __future__ import annotations

from pathlib import Path

import pytest

from vreport.gnatcov import collect_coverage
from vreport.gnatprove import collect_proof
from vreport.model import (
    CoverageEvidence,
    DerivedRequirement,
    Evidence,
    GitInfo,
    ProofEvidence,
    RequirementLayer,
    RequirementsDocument,
    RequirementStatement,
    TraceabilityEvidence,
    TraceReport,
    Waiver,
)
from vreport.traceability import collect_trace_report

FIXTURES = Path(__file__).parent / "fixtures"
# The absolute prefix baked into the copied gnatcov XML fixtures.
COVERAGE_ROOT = Path("/workspace/traffic-light-controller")


@pytest.fixture(scope="session")
def proof() -> ProofEvidence:
    """Proof evidence parsed from the fixture gnatprove directory."""
    return collect_proof(FIXTURES / "gnatprove")


@pytest.fixture(scope="session")
def coverage() -> CoverageEvidence:
    """Coverage evidence parsed from the fixture gnatcov XML directory."""
    return collect_coverage(FIXTURES / "gnatcov", COVERAGE_ROOT)


@pytest.fixture(scope="session")
def trace_report() -> TraceReport:
    """Trace report parsed from the fixture JSON (with open gaps and review rows)."""
    return collect_trace_report(FIXTURES / "trace" / "trace_report.json")


@pytest.fixture(scope="session")
def evidence(
    proof: ProofEvidence, coverage: CoverageEvidence, trace_report: TraceReport
) -> Evidence:
    """Build a complete Evidence value over the fixture artifacts."""
    return Evidence(
        generated_at="2026-07-29T00:00:00+00:00",
        root=str(COVERAGE_ROOT),
        title="Test verification report",
        git=GitInfo(commit="0123456789abcdef", branch="main", dirty=False),
        proof=proof,
        coverage=coverage,
        traceability=TraceabilityEvidence(
            waivers=[Waiver(leaf="1.1", reason="Physical site assumption.")],
            derived=[DerivedRequirement(ident="hlr_3_timing.8", text="Derived text.")],
            waivers_found=True,
            hlr_found=True,
            report=trace_report,
        ),
    )


def _statement(node: str) -> RequirementStatement:
    """Build an index entry for one fixture statement."""
    page = node.rsplit(".", 1)[0]
    return RequirementStatement(
        page=page, anchor=node.replace(".", "-").replace("_", "-"), text=f"Text of {node}."
    )


@pytest.fixture
def requirements_document() -> RequirementsDocument:
    """Build a rendered document covering the fixture chain's HLR and LLR statements."""
    return RequirementsDocument(
        source_dir="/workspace/traffic-light-controller/reports/requirements",
        command="reqs document --chain requirements/trace_chain.yaml --out reports/requirements",
        generated_at="2026-07-29T00:00:00+00:00",
        corpus_valid=True,
        layers=[
            RequirementLayer(name="HLR", pages=["hlr_x"]),
            RequirementLayer(name="LLR", pages=["llr_x"]),
        ],
        nodes={
            "HLR": {f"hlr_x.{n}": _statement(f"hlr_x.{n}") for n in (1, 2, 3)},
            "LLR": {f"llr_x.{n}": _statement(f"llr_x.{n}") for n in (1, 2, 3)},
        },
    )


@pytest.fixture
def evidence_with_requirements(
    evidence: Evidence, requirements_document: RequirementsDocument
) -> Evidence:
    """Return the fixture evidence, plus the requirements rendered as a document."""
    return evidence.model_copy(update={"requirements": requirements_document})
