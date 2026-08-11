"""Typed evidence model shared by the collectors, obligation synthesis, and emitters."""

from __future__ import annotations

from enum import StrEnum
from typing import TYPE_CHECKING

from pydantic import BaseModel, ConfigDict, Field

if TYPE_CHECKING:
    from pathlib import Path

SCHEMA_VERSION = 1

# gnatcov metric-kind keys (values of the <metric kind=...> attribute).
TOTAL_LINES = "total_lines_of_relevance"
TOTAL_OBLIGATIONS = "total_obligations_of_relevance"
FULLY_COVERED = "fully_covered"
PARTIALLY_COVERED = "partially_covered"
NOT_COVERED = "not_covered"
UNDETERMINED = "undetermined_coverage"
EXEMPTED = "exempted"
EXEMPTED_NO_VIOLATION = "exempted_no_violation"


class MissingArtifactsError(Exception):
    """An expected tool-artifact input is absent."""

    def __init__(self, path: Path, what: str) -> None:
        self.path = path
        self.what = what
        super().__init__(f"no {what} found under {path}")


class ArtifactParseError(Exception):
    """A tool artifact exists but could not be parsed."""

    def __init__(self, path: Path, detail: str) -> None:
        self.path = path
        super().__init__(f"failed to parse {path}: {detail}")


class Frozen(BaseModel):
    """Base for all evidence models: immutable, no unknown fields."""

    model_config = ConfigDict(frozen=True, extra="forbid")


class Sloc(Frozen):
    """A source location: file path, 1-based line, optional column."""

    file: str
    line: int
    column: int | None = None

    def __str__(self) -> str:
        loc = f"{self.file}:{self.line}"
        return f"{loc}:{self.column}" if self.column is not None else loc


# --- Proof ------------------------------------------------------------------


class CheckStatus(StrEnum):
    """Verdict of one gnatprove check."""

    proved = "proved"
    justified = "justified"
    unproved = "unproved"


class ProverStats(Frozen):
    """Effort one prover spent on a check."""

    count: int
    max_steps: int
    max_time: float


class ProofCheck(Frozen):
    """One gnatprove flow or proof check."""

    unit: str
    kind: str  # "flow" | "proof"
    rule: str
    severity: str  # "info" when discharged
    location: Sloc
    entity: str | None = None
    message: str | None = None
    how_proved: str | None = None
    provers: dict[str, ProverStats] = Field(default_factory=dict)
    justification: str | None = None  # pragma Annotate reason ("suppressed" in .spark)

    @property
    def status(self) -> CheckStatus:
        """
        Classify the check: justified beats proved beats unproved.

        Fail-safe mapping: any severity other than "info" (including
        severities this parser has never seen) is reported as unproved, so
        the unknown surfaces as a finding rather than silence.
        """
        if self.justification is not None:
            return CheckStatus.justified
        if self.severity == "info":
            return CheckStatus.proved
        return CheckStatus.unproved


class PragmaAssume(Frozen):
    """One `pragma Assume` occurrence."""

    unit: str
    location: Sloc
    entity: str | None = None


class SkipAnnotation(Frozen):
    """One `Skip_Proof` / `Skip_Flow_And_Proof` annotation."""

    unit: str
    entity: str
    kind: str  # "skip_proof" | "skip_flow_and_proof"
    location: Sloc | None = None


class SparkModeEntry(Frozen):
    """SPARK analysis mode of one entity: "all", "spec", or "no"."""

    unit: str
    entity: str
    mode: str
    location: Sloc | None = None


class AssumptionRef(Frozen):
    """One claim or assumption predicate applied to an entity."""

    predicate: str
    entity: str | None = None


class AssumptionClaim(Frozen):
    """A proved claim and the assumptions it still rests on (`--assumptions`)."""

    unit: str
    claim: AssumptionRef
    assumptions: list[AssumptionRef] = Field(default_factory=list)


class ToolWarning(Frozen):
    """A non-pass gnatprove SARIF result (warnings, including suppressed ones)."""

    rule: str
    message: str
    location: Sloc | None = None
    suppressed: bool = False


class UnitAnalysis(Frozen):
    """Completion record of one unit's analysis (.spark progress/stop_reason)."""

    unit: str
    progress: str | None = None
    stop_reason: str | None = None

    @property
    def complete(self) -> bool:
        """Whether the analysis reached the proof phase's end (unknown counts as incomplete)."""
        return self.stop_reason == "STOP_REASON_NONE" and self.progress == "PROGRESS_PROOF"


class GnatproveHeader(Frozen):
    """The `--output-header` block of gnatprove.out."""

    date: str | None = None
    version: str | None = None
    host: str | None = None
    command_line: str | None = None

    @property
    def forced(self) -> bool:
        """Whether the recorded command line shows a forced (`-f`) re-analysis."""
        return "-f" in (self.command_line or "").split()


class SarifInvocation(Frozen):
    """Invocation metadata recorded in gnatprove.sarif."""

    command_line: str | None = None
    end_time: str | None = None
    exit_code: int | None = None
    execution_successful: bool | None = None
    pass_results: int = 0
    open_results: int = 0


class ProofEvidence(Frozen):
    """Everything collected from one gnatprove run."""

    header: GnatproveHeader | None = None
    version_text: str | None = None
    invocation: SarifInvocation | None = None
    sarif_found: bool = False
    summary_text: str | None = None  # verbatim summary table from gnatprove.out
    units: list[str] = Field(default_factory=list)
    analyses: list[UnitAnalysis] = Field(default_factory=list)
    checks: list[ProofCheck] = Field(default_factory=list)
    assumes: list[PragmaAssume] = Field(default_factory=list)
    skips: list[SkipAnnotation] = Field(default_factory=list)
    spark_modes: list[SparkModeEntry] = Field(default_factory=list)
    claims: list[AssumptionClaim] = Field(default_factory=list)
    warnings: list[ToolWarning] = Field(default_factory=list)

    @property
    def incomplete_analyses(self) -> list[UnitAnalysis]:
        """Unit analyses that did not run to the end of the proof phase."""
        return [a for a in self.analyses if not a.complete]

    @property
    def unproved_checks(self) -> list[ProofCheck]:
        """Checks gnatprove could not discharge."""
        return [c for c in self.checks if c.status is CheckStatus.unproved]

    @property
    def justified_checks(self) -> list[ProofCheck]:
        """Checks discharged by a `pragma Annotate` justification."""
        return [c for c in self.checks if c.status is CheckStatus.justified]

    @property
    def non_spark_entities(self) -> list[SparkModeEntry]:
        """Entities not fully analyzed by gnatprove (mode "spec" or "no")."""
        return [m for m in self.spark_modes if m.mode != "all"]

    def unit_fully_in_spark(self, unit: str) -> bool:
        """
        Return whether every *listed* entity of `unit` has SPARK_Mode "all".

        Caveat: generic units list few or no entities (they are analyzed at
        their instantiations), so this says nothing about generic bodies —
        judge those by where proved checks are located instead.
        """
        modes = [m for m in self.spark_modes if m.unit == unit]
        return bool(modes) and all(m.mode == "all" for m in modes)


# --- Coverage ---------------------------------------------------------------


class ObligationStats(Frozen):
    """gnatcov obligation counters for one criterion (Stmt/Decision/MCDC)."""

    kind: str
    counts: dict[str, int] = Field(default_factory=dict)

    @property
    def total(self) -> int:
        """Obligations of relevance."""
        return self.counts.get(TOTAL_OBLIGATIONS, 0)

    @property
    def covered(self) -> int:
        """Fully covered obligations."""
        return self.counts.get(FULLY_COVERED, 0)

    @property
    def not_covered(self) -> int:
        """Uncovered (non-exempted) obligations."""
        return self.counts.get(NOT_COVERED, 0)

    @property
    def exempted(self) -> int:
        """Exempted obligations, with or without masked violations."""
        return self.counts.get(EXEMPTED, 0) + self.counts.get(EXEMPTED_NO_VIOLATION, 0)

    @property
    def pct(self) -> float | None:
        """Fully-covered percentage, recomputed from counts (None when empty)."""
        return round(100.0 * self.covered / self.total, 1) if self.total else None


class FileScope(Frozen):
    """Line-level counters for one scope (package/subprogram), dotted name."""

    name: str
    line: int
    counts: dict[str, int] = Field(default_factory=dict)


class CoverageViolation(Frozen):
    """One gnatcov violation message, tied to its source obligation."""

    location: Sloc
    sco: str  # e.g. "SCO #276: STATEMENT"
    obligation_kind: str  # STATEMENT | DECISION | CONDITION | ...
    message: str
    exempted: bool
    source_text: str | None = None


class Exemption(Frozen):
    """
    One exempted region with its justification text.

    `masked` repeats the violations attributed to this region (they also
    appear, flagged exempted, in the evidence-wide violation list).
    """

    file: str
    line: int
    justification: str
    masked: list[CoverageViolation] = Field(default_factory=list)


class FileCoverage(Frozen):
    """Per-source-file coverage counters and scopes."""

    path: str
    counts: dict[str, int] = Field(default_factory=dict)  # line-level metrics
    obligations: list[ObligationStats] = Field(default_factory=list)
    scopes: list[FileScope] = Field(default_factory=list)


class TraceInfo(Frozen):
    """One execution trace consumed by gnatcov."""

    filename: str
    program: str
    date: str


class CoverageEvidence(Frozen):
    """Everything collected from one gnatcov XML report."""

    level: str
    version_text: str | None = None
    command_text: str | None = None  # the recorded `gnatcov coverage` invocation
    traces: list[TraceInfo] = Field(default_factory=list)
    counts: dict[str, int] = Field(default_factory=dict)  # global line-level metrics
    obligations: list[ObligationStats] = Field(default_factory=list)
    files: list[FileCoverage] = Field(default_factory=list)
    violations: list[CoverageViolation] = Field(default_factory=list)
    exemptions: list[Exemption] = Field(default_factory=list)

    @property
    def non_exempted_violations(self) -> list[CoverageViolation]:
        """Violations that count against the coverage objective."""
        return [v for v in self.violations if not v.exempted]

    @property
    def exempted_violations(self) -> list[CoverageViolation]:
        """Violations masked by an exempted region."""
        return [v for v in self.violations if v.exempted]


# --- Traceability -------------------------------------------------------------

TRACE_REPORT_SCHEMA_VERSION = 1

# Matrix-row statuses that are accounted-for rather than open work: covered,
# waived/derived (reviewed as their own obligations), review-verified (its own
# obligation), or expected under a partial-coverage layer. Fail-safe mapping:
# any status outside this set — including ones this consumer has never seen —
# is treated as open, so the unknown surfaces as a finding rather than silence.
SETTLED_TRACE_STATUSES = frozenset(
    {"OK", "WAIVED", "DERIVED", "REVIEW", "UNTESTED", "UNIMPLEMENTED", "UNREQUIRED"}
)


class Waiver(Frozen):
    """A CONOPS leaf waived from HLR coverage, with its recorded reason."""

    leaf: str
    reason: str


class DerivedRequirement(Frozen):
    """An HLR statement marked `derived: true` (no CONOPS parent)."""

    ident: str
    text: str


class TraceRow(Frozen):
    """One trace-matrix row: a node, its status, and the refs behind it."""

    node: str
    status: str
    refs: list[str] = Field(default_factory=list)
    detail: str = ""

    @property
    def is_open(self) -> bool:
        """Whether this row is open work rather than accounted-for."""
        return self.status not in SETTLED_TRACE_STATUSES


class MethodFacet(Frozen):
    """One verification method's evidence for one statement."""

    method: str
    status: str  # OK | UNCOVERED | REVIEW | MISMATCH | UNSELECTED
    evidence: list[str] = Field(default_factory=list)


class VerificationRow(Frozen):
    """One statement of the verification matrix: worst status plus per-method facets."""

    node: str
    status: str
    detail: str = ""
    methods: list[MethodFacet] = Field(default_factory=list)

    @property
    def is_open(self) -> bool:
        """Whether this row is open work rather than accounted-for."""
        return self.status not in SETTLED_TRACE_STATUSES

    @property
    def review_facets(self) -> list[MethodFacet]:
        """The review-method facets: human judgements standing in for evidence."""
        return [m for m in self.methods if m.method == "review"]


class TracePair(Frozen):
    """One (parent, child) pair of the chain and its two matrices."""

    upper: str
    lower: str
    refs_point_down: bool = False
    partial_coverage: bool = False
    method: str | None = None
    ref_field: str | None = None
    upper_rows: list[TraceRow] = Field(default_factory=list)
    lower_rows: list[TraceRow] = Field(default_factory=list)


class VerificationMatrix(Frozen):
    """The merged per-method verification view of one parent layer."""

    layer: str
    rows: list[VerificationRow] = Field(default_factory=list)


class TraceLayer(Frozen):
    """One layer of the trace chain, as recorded in the report."""

    name: str
    kind: str
    path: str = ""
    parent: str | None = None
    method: str | None = None
    partial_coverage: bool = False
    refs_point_down: bool = False
    ref_field: str | None = None
    node_count: int | None = None


class TraceDiagnostic(Frozen):
    """One located finding of the `reqs trace` gate."""

    level: str  # "error" | "warning"
    code: str
    message: str
    file: str = ""
    line: int | None = None
    path: list[str] = Field(default_factory=list)

    @property
    def location(self) -> str:
        """Render the file:line location, dash when unrecorded."""
        if not self.file:
            return "—"
        return f"{self.file}:{self.line}" if self.line is not None else self.file


class TraceReport(Frozen):
    """The `reqs trace --format json` payload (schema_version 1)."""

    chain: str = ""
    command: str | None = None
    generated_at: str | None = None
    complete: bool = False
    corpus_valid: bool = False
    errors: int = 0
    warnings: int = 0
    layers: list[TraceLayer] = Field(default_factory=list)
    pairs: list[TracePair] = Field(default_factory=list)
    verification: list[VerificationMatrix] = Field(default_factory=list)
    diagnostics: list[TraceDiagnostic] = Field(default_factory=list)


class TraceabilityEvidence(Frozen):
    """The requirement-chain facts the report covers, tracked per source."""

    waivers: list[Waiver] = Field(default_factory=list)
    derived: list[DerivedRequirement] = Field(default_factory=list)
    waivers_found: bool = False
    hlr_found: bool = False
    report: TraceReport | None = None


# --- Provenance / top level --------------------------------------------------


class GitInfo(Frozen):
    """State of the sources the evidence was produced from."""

    commit: str
    branch: str
    dirty: bool
    describe: str | None = None


class Evidence(Frozen):
    """The complete normalized evidence for one report."""

    schema_version: int = SCHEMA_VERSION
    generated_at: str = ""
    root: str = ""
    title: str = "Verification report"
    git: GitInfo | None = None
    proof: ProofEvidence
    coverage: CoverageEvidence
    traceability: TraceabilityEvidence


# --- Review obligations -------------------------------------------------------


class ObligationStatus(StrEnum):
    """Whether an obligation is machine-verified or needs a human."""

    ok = "ok"
    review = "review"


class Obligation(Frozen):
    """One entry of the front-page trust checklist."""

    ident: str
    title: str
    status: ObligationStatus
    detail: str
    anchor: str  # MyST target the evidence lives under
    items: list[str] = Field(default_factory=list)
