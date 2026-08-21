"""Typed evidence model shared by the collectors, obligation synthesis, and emitters."""

from __future__ import annotations

from enum import StrEnum
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field

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


class Instantiation(Frozen):
    """
    One generic instantiation gnatprove recorded while analyzing a unit.

    A `.spark` entity whose `sloc` chain carries more than one element is an
    instance: the first element is the declaration inside the *generic's* own
    source, and the last is the instantiation that reached it. This is the one
    place gnatprove names a generic nested in an ordinary package — such a
    generic has no artifact of its own to be marked
    `STOP_REASON_GENERIC_UNIT`, and no entity in its own unit's artifact.
    """

    unit: str
    entity: str
    declared_at: Sloc
    site: Sloc


class UnitAnalysis(Frozen):
    """Completion record of one unit's analysis (.spark progress/stop_reason)."""

    unit: str
    progress: str | None = None
    stop_reason: str | None = None

    @property
    def complete(self) -> bool:
        """Whether the analysis reached the proof phase's end (unknown counts as incomplete)."""
        return self.stop_reason == "STOP_REASON_NONE" and self.progress == "PROGRESS_PROOF"

    @property
    def generic(self) -> bool:
        """
        Whether gnatprove skipped the unit because the unit itself is a generic.

        This marks a *library-level* generic and nothing else: the stop reason
        is a property of a compilation unit, so a generic nested in an ordinary
        package never carries it however it was analyzed. Do not read the
        absence of this flag as "holds no generic" — see `Instantiation`.
        """
        return self.stop_reason == "STOP_REASON_GENERIC_UNIT"


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
    instantiations: list[Instantiation] = Field(default_factory=list)
    checks: list[ProofCheck] = Field(default_factory=list)
    assumes: list[PragmaAssume] = Field(default_factory=list)
    skips: list[SkipAnnotation] = Field(default_factory=list)
    spark_modes: list[SparkModeEntry] = Field(default_factory=list)
    claims: list[AssumptionClaim] = Field(default_factory=list)
    warnings: list[ToolWarning] = Field(default_factory=list)

    @property
    def incomplete_analyses(self) -> list[UnitAnalysis]:
        """
        Unit analyses that did not run to the end of the proof phase.

        Generic units are not among them: gnatprove analyzes generic
        *instances*, so a generic's own artifact is empty by construction and
        stopping on it is the normal outcome, not an early stop. The risk a
        generic carries is a different one — see `Evidence.generics`.
        """
        return [a for a in self.analyses if not a.complete and not a.generic]

    @property
    def generic_analyses(self) -> list[UnitAnalysis]:
        """Units gnatprove skipped because the unit itself is a generic."""
        return [a for a in self.analyses if a.generic]

    def instance_units(self, unit: str) -> list[str]:
        """
        Units whose analysis produced checks located in `unit`'s sources.

        Analyzing an instance attributes the generic body's checks to the
        instantiating unit while leaving them *located* in the generic's own
        source file, so this is where the evidence that a generic was actually
        analyzed lives. Heuristic caveat: the match is by source-file stem, so
        two same-named files in different directories would be conflated.
        """
        return sorted(
            {c.unit for c in self.checks if Path(c.location.file).stem == unit and c.unit != unit}
        )

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


# --- Code inventory ---------------------------------------------------------


class GenericDeclaration(Frozen):
    """
    One generic declared in the analyzed sources, as the Ada tracer found it.

    The tracer parses the sources with libadalang, so this is the *declared*
    set of generics — the denominator the proof evidence is judged against.
    Deriving it from gnatprove's own output instead would be circular: a
    generic no analyzed instance reached is exactly what gnatprove has nothing
    to say about, and so exactly what must not be scoped by what gnatprove saw.
    """

    name: str
    kind: str
    declared_in: str
    anchors: list[Sloc] = Field(default_factory=list)
    """
    Locations of the generic's own declarations (its subprograms, for a generic
    package). A check or instance located in one of the generic's source files
    belongs to whichever generic owns the nearest preceding anchor, which is
    how two generics nested in one file are told apart.
    """

    @property
    def sources(self) -> list[str]:
        """Source-file stems the generic's own declarations live in."""
        return sorted({Path(a.file).stem for a in self.anchors} | {Path(self.declared_in).stem})


class CodeInventory(Frozen):
    """The Ada tracer's inventory of the analyzed sources (`make code-inventory`)."""

    schema_version: int = 0
    project: str | None = None
    generics: list[GenericDeclaration] = Field(default_factory=list)


class GenericInstance(Frozen):
    """One analyzed instance of a generic, and where it was instantiated."""

    unit: str
    site: Sloc | None = None


class GenericAnalysis(Frozen):
    """A generic, and the analysis that reached its body — or did not."""

    name: str
    kind: str
    declared_in: str
    instances: list[GenericInstance] = Field(default_factory=list)

    @property
    def analyzed(self) -> bool:
        """Whether any analyzed instance stands behind this generic."""
        return bool(self.instances)


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


REQUIREMENTS_INDEX_SCHEMA_VERSION = 2


class RequirementStatement(Frozen):
    """One rendered statement: where it sits in the document, and what it says."""

    page: str  # the rendered page's name, relative to the document's page directory
    anchor: str  # the cross-reference target that page carries for this statement
    text: str


class RequirementLayer(Frozen):
    """One rendered layer of the chain and the pages it rendered as."""

    name: str
    kind: str = ""  # the chain layer's kind, so a consumer can name its nodes correctly
    pages: list[str] = Field(default_factory=list)
    # The pages at the top of the layer. The rest are nested under one of these
    # by the render, which enters them from their parent's page: a table of
    # contents naming every page would enter the nested ones a second time.
    roots: list[str] = Field(default_factory=list)


class RequirementSource(Frozen):
    """One cited source file, listed as its own page."""

    page: str  # the listing's page name, relative to the document's page directory
    path: str  # the file it lists, as the inventories name it


class RequirementsDocument(Frozen):
    """
    The requirement corpus rendered as pages (`reqs document`).

    Only the index is normalized here: the pages themselves are copied into the
    report's source tree verbatim, since they are already the rendering. The
    index is what the report needs -- it turns a matrix's node id into a link
    without this consumer knowing how an anchor is spelled.
    """

    source_dir: str  # where the render was read from, for the provenance page
    command: str | None = None
    generated_at: str | None = None
    corpus_valid: bool = False
    layers: list[RequirementLayer] = Field(default_factory=list)
    nodes: dict[str, dict[str, RequirementStatement]] = Field(default_factory=dict)
    sources: list[RequirementSource] = Field(default_factory=list)  # what the chain cites

    @property
    def requirement_pages(self) -> list[str]:
        """The requirement pages, in chain then file order."""
        return [page for layer in self.layers for page in layer.pages]

    @property
    def pages(self) -> list[str]:
        """Every rendered page: the requirements, then the source listings."""
        return self.requirement_pages + [source.page for source in self.sources]

    def statement(self, layer: str, node: str) -> RequirementStatement | None:
        """Resolve one node of one layer to its rendered statement, if it has one."""
        return self.nodes.get(layer, {}).get(node)


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


def _owner(generics: list[GenericDeclaration], loc: Sloc) -> str | None:
    """
    Name the generic a source location falls inside.

    Two levels, because the inventory anchors a generic at its declarations and
    a check can land anywhere in a body. Within a file that has anchors,
    attribution is per line — the nearest preceding one wins, since a single
    file can declare several generics and the ordinary package enclosing them,
    and a file-level match would credit all of them for an instance of any one.
    A location before the first anchor in such a file belongs to no generic:
    that is the enclosing package's own code.

    A file with no anchors of its own (the body of a library-level generic,
    which the inventory records only at its spec) falls back to the unit — but
    only when exactly one generic claims it, so an ambiguous case abstains
    instead of guessing.

    Files are matched by basename: gnatprove reports a bare file name and the
    inventory a path relative to the project root, so two same-named sources in
    different directories would be conflated.
    """
    name = Path(loc.file).name
    anchored = [(g.name, a.line) for g in generics for a in g.anchors if Path(a.file).name == name]
    if anchored:
        preceding = [pair for pair in anchored if pair[1] <= loc.line]
        return max(preceding, key=lambda pair: pair[1])[0] if preceding else None
    claimants = {g.name for g in generics if Path(name).stem in g.sources}
    return next(iter(claimants)) if len(claimants) == 1 else None


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
    requirements: RequirementsDocument | None = None
    inventory: CodeInventory | None = None

    @property
    def generics(self) -> list[GenericAnalysis]:
        """
        Every generic in the proof scope, with the instances that analyzed it.

        The row set comes from the *declared* generics (the code inventory),
        restricted to those whose sources gnatprove actually analyzed — a
        generic outside the proof scope is not described by this report at all,
        and listing it as unanalyzed would contradict {ref}`proof-scope`.
        Without an inventory the rows fall back to the generic *units*
        gnatprove reported, which omits any generic nested in an ordinary
        package.

        Each row's instances come from two signals, because gnatprove records
        the two kinds of generic differently. A nested generic appears as an
        `Instantiation` naming both its declaration and the instantiation site;
        a library-level generic's instance entities carry only the
        instantiation site, and the evidence that its body was analyzed is
        instead the checks *located* in its sources under another unit's name.
        """
        scope = set(self.proof.units)
        declared = [
            g for g in (self.inventory.generics if self.inventory else []) if scope & set(g.sources)
        ]
        rows = [
            GenericAnalysis(
                name=g.name,
                kind=g.kind,
                declared_in=g.declared_in,
                instances=self._instances_of(declared, g),
            )
            for g in declared
        ]
        covered = {Path(g.declared_in).stem for g in declared}
        rows.extend(
            GenericAnalysis(
                name=a.unit,
                kind="unit",
                declared_in=a.unit,
                instances=[GenericInstance(unit=u) for u in self.proof.instance_units(a.unit)],
            )
            for a in self.proof.generic_analyses
            if a.unit not in covered
        )
        return sorted(rows, key=lambda r: r.name)

    def _instances_of(
        self, declared: list[GenericDeclaration], generic: GenericDeclaration
    ) -> list[GenericInstance]:
        """Merge both instance signals for one generic, preferring a known site."""
        sites: dict[str, Sloc | None] = {}
        for inst in self.proof.instantiations:
            if _owner(declared, inst.declared_at) == generic.name:
                sites[inst.unit] = inst.site
        own = set(generic.sources)
        for check in self.proof.checks:
            # A check under the generic's own unit name is not instance
            # evidence: only an instantiation elsewhere proves the body was
            # reached. Ada's default file naming makes the stem the unit name.
            if check.unit in own or Path(check.location.file).stem not in own:
                continue
            if _owner(declared, check.location) == generic.name:
                sites.setdefault(check.unit, None)
        return [GenericInstance(unit=u, site=sites[u]) for u in sorted(sites)]


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
