"""
Synthesize the front-page review obligations from the collected evidence.

Follows the shape of NVIDIA's SPARK Process: what a machine verified is
asserted with counts (OK/FAIL); what inherently needs human judgement —
justifications, assumptions, exemptions, waivers, non-SPARK code — becomes a
review item pointing at its evidence.
"""

from __future__ import annotations

from enum import StrEnum
from pathlib import Path
from typing import TYPE_CHECKING, NamedTuple

from vreport.mdtext import code_span, count, inline
from vreport.model import (
    PARTIALLY_COVERED,
    UNDETERMINED,
    CheckStatus,
    Obligation,
    ObligationStatus,
)

if TYPE_CHECKING:
    from collections.abc import Iterable

    from vreport.model import (
        AssumptionClaim,
        AssumptionRef,
        CoverageViolation,
        Evidence,
        ProofEvidence,
        TraceDiagnostic,
        TraceReport,
        TraceRow,
        VerificationRow,
    )

_MAX_ITEMS = 40

# Prose for the --assumptions claim predicates.
PREDICATE_LABELS = {
    "CLAIM_AORTE": "absence of run-time errors",
    "CLAIM_EFFECTS": "effects on parameters and globals",
    "CLAIM_POST": "the postcondition",
    "CLAIM_INIT": "initialization of outputs",
}


class ViolationClass(StrEnum):
    """Why a coverage gap may (or may not) be acceptable."""

    proof_support = "proof-support code"
    proved_file = "proved code (file-level)"
    no_evidence = "no proof evidence"


def classify_violation(violation: CoverageViolation, proof: ProofEvidence) -> ViolationClass:
    """
    Classify a coverage violation against where proved checks actually are.

    A file counts as proved when at least one proved check is located in it
    and no unproved or justified check is — for generics, checks land at the
    generic's source lines via instance analysis, whichever unit performed
    it. A generic nested in an ordinary unit can leave a body file with no
    check of its own, its analysis recorded against the instantiating unit
    and located at the declaration in the other source of the same unit, so
    that evidence carries across the unit's sources. Heuristic caveats: the
    match is per source-file basename (two files with the same basename in
    different directories would be conflated) and per file, not per line.
    """
    name = Path(violation.location.file).name
    stem = Path(name).stem
    if stem.endswith("_proof"):
        return ViolationClass.proof_support
    proved: set[str] = set()
    tainted: set[str] = set()
    for check in proof.checks:
        bucket = proved if check.status is CheckStatus.proved else tainted
        bucket.add(Path(check.location.file).name)
    if name in proved and name not in tainted:
        return ViolationClass.proved_file
    if proof.instance_units(stem) and not any(Path(f).stem == stem for f in tainted):
        return ViolationClass.proved_file
    return ViolationClass.no_evidence


def predicate_label(predicate: str) -> str:
    """Return the prose form of a claim predicate, falling back to the raw name."""
    return PREDICATE_LABELS.get(predicate, predicate)


def open_claims(proof: ProofEvidence) -> list[tuple[AssumptionClaim, list[AssumptionRef]]]:
    """
    Pair each claim with its *residual* assumptions; drop internally closed ones.

    An assumption is discharged within the run when it matches another proved
    claim, or when the assumed-about entity was verified clean by the same
    run: SPARK_Mode "all", not also declared with a lesser mode under the
    same fully-qualified name (overload collisions), and with no unproved or
    justified check attributed to it. Anything less stays residual.
    """
    proved = {(c.claim.predicate, c.claim.entity) for c in proof.claims if c.claim.entity}
    tainted = {c.entity for c in proof.checks if c.status is not CheckStatus.proved and c.entity}
    non_all = {m.entity for m in proof.spark_modes if m.mode != "all"}
    clean = {m.entity for m in proof.spark_modes if m.mode == "all"} - non_all - tainted
    out: list[tuple[AssumptionClaim, list[AssumptionRef]]] = []
    for claim in proof.claims:
        residual = [
            a
            for a in claim.assumptions
            if (a.predicate, a.entity) not in proved and (a.entity is None or a.entity not in clean)
        ]
        if residual:
            out.append((claim, residual))
    return out


def _cap(items: list[str]) -> list[str]:
    """Bound an item list, saying explicitly how much was dropped."""
    if len(items) <= _MAX_ITEMS:
        return items
    dropped = len(items) - _MAX_ITEMS
    return [*items[:_MAX_ITEMS], f"… and {dropped} more (see the evidence section)."]


class _Builder:
    """Accumulates obligations with sequential R-n identifiers."""

    def __init__(self) -> None:
        self.obligations: list[Obligation] = []

    def add(
        self,
        title: str,
        anchor: str,
        detail: str,
        *,
        review: bool,
        items: Iterable[str] = (),
    ) -> None:
        """Append one obligation."""
        self.obligations.append(
            Obligation(
                ident=f"R-{len(self.obligations) + 1}",
                title=title,
                status=ObligationStatus.review if review else ObligationStatus.ok,
                detail=detail,
                anchor=anchor,
                items=_cap(list(items)),
            )
        )


def _proof_obligations(ev: Evidence, b: _Builder) -> None:
    """Obligations derived from the gnatprove evidence."""
    # Completeness first: an early stop qualifies every "none" below.
    incomplete = ev.proof.incomplete_analyses
    no_records = not ev.proof.analyses
    b.add(
        "Unit analyses: completion not recorded"
        if no_records
        else f"Incomplete unit analyses: {len(incomplete)}"
        if incomplete
        else "Incomplete unit analyses: none",
        "proof-completeness",
        (
            "The `.spark` artifacts carry no completion records, so nothing can be "
            "claimed about whether each unit's analysis ran to the end — "
            "regenerate with `make prove-report`."
            if no_records
            else "gnatprove recorded an early stop (or an unrecognized progress "
            "marker) for these units: their artifacts may cover only part of the "
            "code, so every count below is qualified by this. Regenerate with "
            "`make prove-report`."
            if incomplete
            else "Every unit's `.spark` artifact records an analysis that ran to "
            "the end of the proof phase."
        ),
        review=no_records or bool(incomplete),
        items=[
            f"{a.unit} — progress `{a.progress or 'unrecorded'}`, "
            f"stop reason `{a.stop_reason or 'unrecorded'}`"
            for a in incomplete
        ],
    )

    # Generics are the one class of unit gnatprove reports as skipped by
    # design; what matters is whether an analyzed instance stands behind each.
    generics = ev.proof.generic_analyses
    orphans = ev.proof.uninstantiated_generics
    b.add(
        f"Generic units without an analyzed instance: {len(orphans)}"
        if orphans
        else f"Generic units, each analyzed through an instance: {len(generics)}"
        if generics
        else "Generic units: none",
        "proof-generics",
        (
            "gnatprove analyzes generic *instances*, not generics themselves. No "
            "check is located in these generics' sources, so no instance this run "
            "analyzed exercises them and nothing in their bodies is proved. "
            "Instantiate each against in-SPARK formals in a unit the proof run "
            "reaches."
            if orphans
            else "gnatprove records each of these as skipped, which is the normal "
            "outcome for a generic and not an early stop. Each carries checks "
            "located in its own sources, contributed by an analyzed instance, so "
            "its body is covered by the tables below."
            if generics
            else "The run analyzed no generic units."
        ),
        review=bool(orphans),
        items=[
            f"{a.unit} — no instance analyzed"
            if not ev.proof.instance_units(a.unit)
            else f"{a.unit} — analyzed through {', '.join(ev.proof.instance_units(a.unit))}"
            for a in generics
        ],
    )

    unproved = ev.proof.unproved_checks
    b.add(
        f"Unproved checks: {len(unproved)}" if unproved else "Unproved checks: none",
        "proof-unproved",
        (
            "gnatprove could not discharge these checks; each is a potential run-time "
            "error or contract violation and must be fixed or formally justified."
            if unproved
            else "Every check gnatprove attempted was discharged."
        ),
        review=bool(unproved),
        items=[f"`{c.location}` — {c.rule}: {inline(c.message or '')}" for c in unproved],
    )

    justified = ev.proof.justified_checks
    b.add(
        f"Justified checks: {len(justified)}" if justified else "Justified checks: none",
        "proof-justified",
        (
            "A justified check is a human claim, not a proof. Review each justification "
            "and confirm it argues convincingly that the diagnostic masks no bug."
            if justified
            else "No check is discharged by a `pragma Annotate` justification — "
            "the proof stands without manual overrides."
        ),
        review=bool(justified),
        items=[f"`{c.location}` — {c.rule}: {inline(c.justification or '')}" for c in justified],
    )

    assumes = ev.proof.assumes
    b.add(
        f"`pragma Assume`: {len(assumes)}" if assumes else "`pragma Assume`: none",
        "proof-assumes",
        (
            "`pragma Assume` injects an unproven fact into the proof context. Review "
            "each one and confirm a test demonstrates the assumed condition."
            if assumes
            else "Nothing was fed to the prover by fiat."
        ),
        review=bool(assumes),
        items=[f"`{a.location}` — in {a.entity or a.unit}" for a in assumes],
    )

    skips = ev.proof.skips
    b.add(
        f"Skipped proofs: {len(skips)}" if skips else "Skipped proofs: none",
        "proof-skips",
        (
            "These entities carry `Skip_Proof`/`Skip_Flow_And_Proof`, lowering their "
            "verification below the project's Silver target. Review why."
            if skips
            else "No entity opts out of proof via a skip annotation."
        ),
        review=bool(skips),
        items=[f"{s.entity} ({s.kind}, unit {s.unit})" for s in skips],
    )

    warnings = ev.proof.warnings
    sarif_missing = not ev.proof.sarif_found
    b.add(
        f"Tool warnings: {len(warnings)}, SARIF record not found"
        if sarif_missing
        else f"Tool warnings: {len(warnings)}"
        if warnings
        else "Tool warnings: none",
        "proof-warnings",
        (
            "`gnatprove.sarif` was not recorded, so the warning record is "
            "incomplete: the invocation's exit code is lost and suppression "
            "detail is unreliable. The warnings below are recovered from the "
            "per-unit `.spark` artifacts — regenerate with `make prove-report` "
            "for the full record."
            if sarif_missing
            else "gnatprove warnings can flag violations of the tool's own soundness "
            "assumptions; suppressed warnings in particular are human claims and "
            "need review."
            if warnings
            else "gnatprove emitted no warnings."
        ),
        review=sarif_missing or bool(warnings),
        items=[
            f"`{w.location}` — {w.rule}: {inline(w.message)}"
            + (" *(suppressed)*" if w.suppressed else "")
            if w.location
            else f"{w.rule}: {inline(w.message)}"
            for w in warnings
        ],
    )

    generic_note = (
        " Note: generic units are analyzed at their instantiations and contribute few "
        "or no entities to this list; judge generic code by where proved checks are "
        "located (the coverage classification does this per file)."
    )
    outside = ev.proof.non_spark_entities
    # "None" here means none *within the analyzed scope*: code the run never
    # reached is absent from the evidence, not cleared by it.
    scope_note = (
        " This covers the analyzed scope and nothing wider: code the run did not "
        "reach is absent from this report rather than cleared by it — see "
        "{ref}`proof-scope`."
    )
    b.add(
        f"Code outside the proof: {len(outside)} entities"
        if outside
        else f"Code outside the proof: none of the {len(ev.proof.units)} analyzed units",
        "proof-spark-modes",
        (
            "These entities are not fully analyzed by gnatprove (`spec`: only the "
            "contract is in SPARK; `no`: not analyzed at all). No proof covers their "
            "bodies — confirm they are exercised by tests and reviewed by hand."
            if outside
            else "Every analyzed entity is fully in SPARK."
        )
        + generic_note
        + scope_note,
        review=bool(outside),
        items=[f"{m.entity} — SPARK_Mode `{m.mode}` (unit {m.unit})" for m in outside],
    )

    residual = open_claims(ev.proof)
    partial_note = (
        " Note: gnatprove documents this listing as partial (assumptions are reported "
        "only for called subprograms)."
    )
    b.add(
        f"Residual proof assumptions: {len(residual)} claims"
        if residual
        else "Residual proof assumptions: none",
        "proof-claims",
        (
            "These proved claims rest on assumptions not discharged within the run — "
            "each must hold in the real system." + partial_note
            if residual
            else f"All {len(ev.proof.claims)} proved claims close within the run: every "
            "assumption is either another proved claim or concerns an entity fully "
            "analyzed by this run with no unproved or justified checks (this discharge "
            "is only as strong as {ref}`proof-unproved` and {ref}`proof-justified` "
            "being clean, which they are checked to be above)." + partial_note
        ),
        review=bool(residual),
        items=[
            f"{c.claim.entity}: {predicate_label(c.claim.predicate)} rests on "
            + "; ".join(f"{predicate_label(a.predicate)} of {a.entity}" for a in refs)
            for c, refs in residual
        ],
    )


def _coverage_obligations(ev: Evidence, b: _Builder) -> None:
    """Obligations derived from the gnatcov evidence."""
    # Counter-reported gaps that no parsed message explains must not render green.
    violations = ev.coverage.non_exempted_violations
    stats = ev.coverage.obligations
    counted_gaps = sum(o.not_covered + o.counts.get(PARTIALLY_COVERED, 0) for o in stats)
    undetermined = sum(o.counts.get(UNDETERMINED, 0) for o in stats)
    unexplained = counted_gaps if not violations else 0
    undetermined_note = (
        f" gnatcov also counts {undetermined} obligations with *undetermined* "
        "coverage; these produce no violation messages and are not itemized "
        "below — see the coverage summary."
        if undetermined
        else ""
    )
    b.add(
        f"Uncovered code: {len(violations)} violations"
        if violations
        else "Uncovered code: counters disagree with messages"
        if unexplained
        else f"Uncovered code: {undetermined} undetermined obligations"
        if undetermined
        else "Uncovered code: none",
        "coverage-violations",
        (
            "Non-exempted coverage violations, cross-referenced against where proved "
            "checks are located. The classification is per source *file*, not per "
            "line — a heuristic aid, not a verdict: *proof-support code* exists only "
            "so gnatprove can analyze the generic core and is never executed; *proved "
            "code (file-level)* means gnatprove proved checks located in this file "
            "and none failed (for generics, via instance analysis) — confirm the "
            "uncovered lines fall within the proven subprograms; *no proof evidence* "
            "means no proved check is located in this file — such code is neither "
            "proven nor executed and needs a test, removal, or an exemption." + undetermined_note
            if violations
            else f"The obligation counters report {unexplained} obligations not "
            "fully covered, yet no violation message was parsed — the message "
            "format may have drifted past this parser. Treat the coverage claim "
            "as unverified and inspect the gnatcov summary." + undetermined_note
            if unexplained
            else "No coverage violations, but gnatcov could not determine the "
            f"coverage of {undetermined} obligations; undetermined obligations "
            "produce no violation messages, so they appear only in the summary "
            "counters. Investigate before trusting the coverage result."
            if undetermined
            else f"The test suite covers every non-exempted obligation at "
            f"`{ev.coverage.level}`; the obligation counters agree (no uncovered, "
            "partially covered, or undetermined obligations)."
        ),
        review=bool(violations) or bool(unexplained) or bool(undetermined),
        items=[
            f"`{v.location}` — {v.obligation_kind} {inline(v.message)} — "
            f"*{classify_violation(v, ev.proof)}*"
            for v in violations
        ],
    )

    # Exemption notices are matched by a fixed prefix; drift must not hide them.
    exemptions = ev.coverage.exemptions
    counted_exempted = sum(o.exempted for o in stats)
    unparsed_exempted = counted_exempted if not exemptions else 0
    b.add(
        f"Coverage exemptions: {len(exemptions)}"
        if exemptions
        else "Coverage exemptions: counters disagree with messages"
        if unparsed_exempted
        else "Coverage exemptions: none",
        "coverage-exemptions",
        (
            "An exempted region replaces coverage with an argument. Review each "
            "justification and confirm it still holds for the current code."
            if exemptions
            else f"The obligation counters report {unparsed_exempted} exempted "
            "obligations, yet no exempted region was parsed — the exemption-notice "
            "format may have drifted past this parser, leaving the masked "
            "violations and their justifications invisible to this report. "
            "Inspect the gnatcov XML."
            if unparsed_exempted
            else "No coverage obligation is exempted; the obligation counters agree."
        ),
        review=bool(exemptions) or bool(unparsed_exempted),
        items=[f"`{e.file}:{e.line}` — {inline(e.justification)}" for e in exemptions],
    )


class OpenTraceItem(NamedTuple):
    """One open matrix row: where it was found, which layer its node lives in, the row."""

    where: str
    layer: str  # so a consumer can resolve the node without re-deriving it from `where`
    row: TraceRow | VerificationRow


def open_trace_items(report: TraceReport) -> list[OpenTraceItem]:
    """
    Collect the open rows of every trace matrix, each with a where-label.

    Open means a status outside `SETTLED_TRACE_STATUSES`: work the chain still
    owes, as opposed to rows that are covered, waived, derived,
    review-verified, or expected under a partial-coverage layer.
    """
    items: list[OpenTraceItem] = []
    for matrix in report.verification:
        items.extend(
            OpenTraceItem(f"{matrix.layer} verification", matrix.layer, row)
            for row in matrix.rows
            if row.is_open
        )
    for pair in report.pairs:
        items.extend(
            OpenTraceItem(f"{pair.upper} → {pair.lower}", pair.upper, r)
            for r in pair.upper_rows
            if r.is_open
        )
        items.extend(
            OpenTraceItem(f"{pair.lower} → {pair.upper}", pair.lower, r)
            for r in pair.lower_rows
            if r.is_open
        )
    return items


# Gate diagnostic codes whose finding is some matrix row's open status: the row
# is the open item, and repeating its diagnostic would double-count the gap.
# Fail-safe mapping: a code outside this set — including ones this consumer has
# never seen — is treated as rowless and surfaces as an open item of its own.
ROW_BACKED_TRACE_CODES = frozenset(
    {
        "E-TRACE-UNCOVERED",
        "W-TRACE-UNCOVERED",
        "E-TRACE-DANGLING",
        "E-TRACE-UNTRACED",
        "E-TRACE-UNVERIFIED",
        "E-TRACE-UNSELECTED",
        "E-TRACE-METHOD",
    }
)


def rowless_trace_findings(report: TraceReport) -> list[TraceDiagnostic]:
    """Gate findings with no matrix row (waiver lint, ignored check tags): open items too."""
    return [d for d in report.diagnostics if d.code not in ROW_BACKED_TRACE_CODES]


def review_verified_rows(report: TraceReport) -> list[tuple[str, VerificationRow]]:
    """Statements whose declared verification includes `review`, with their layer."""
    return [
        (matrix.layer, row)
        for matrix in report.verification
        for row in matrix.rows
        if row.review_facets
    ]


def _trace_item(where: str, row: TraceRow | VerificationRow) -> str:
    """Render one open matrix row as a checklist item."""
    detail = f" ({inline(row.detail)})" if row.detail and row.detail != "—" else ""
    return f"{where}: {code_span(row.node)} — {inline(row.status)}{detail}"


def _diag_item(diag: TraceDiagnostic) -> str:
    """Render one gate diagnostic as a checklist item."""
    return f"{code_span(diag.location)} — {inline(diag.code)}: {inline(diag.message)}"


def _trace_gap_obligation(report: TraceReport | None, b: _Builder) -> None:
    """Add the headline traceability obligation: what the chain still owes."""
    # Missing or unanalyzable evidence must not render green.
    if report is None:
        b.add(
            "Traceability gaps: trace report not found",
            "traceability-gaps",
            "No trace report was collected, so nothing can be claimed about the "
            "requirement chain's coverage — regenerate with `make trace-report`.",
            review=True,
        )
        return
    if not report.corpus_valid:
        b.add(
            "Traceability gaps: unknown (corpus invalid)",
            "traceability-diagnostics",
            "`reqs trace` could not analyze the chain (broken chain config or "
            "requirement corpus), so the matrices are omitted rather than "
            "fabricated. Fix the diagnostics and regenerate with `make trace-report`.",
            review=True,
            items=[_diag_item(d) for d in report.diagnostics],
        )
        return
    open_items = open_trace_items(report)
    rowless = rowless_trace_findings(report)
    counts = f"{count(report.errors, 'gate error')}, {count(report.warnings, 'warning')}"
    clean = not (open_items or rowless or report.errors or report.warnings)
    b.add(
        f"Traceability gaps: {count(len(open_items) + len(rowless), 'open item')} ({counts})"
        if not clean
        else "Traceability gaps: none",
        "traceability-gaps",
        (
            "Every requirement of the chain is covered, traced, and verified as "
            "declared; the `reqs trace --complete` gate agrees (no errors or "
            "warnings)."
            if clean
            else "These are open work: matrix rows without their declared "
            "evidence, dangling or untraced references, statements declaring "
            "no verification method — plus gate findings with no matrix row "
            "(waiver lint, ignored check tags). Each must be closed (or waived "
            "with a reason) before the chain's coverage claim stands."
        ),
        review=not clean,
        items=(
            [_trace_item(item.where, item.row) for item in open_items]
            + [_diag_item(d) for d in rowless]
            or [_diag_item(d) for d in report.diagnostics]
        ),
    )


def _traceability_obligations(ev: Evidence, b: _Builder) -> None:
    """Obligations derived from the requirements chain and its trace report."""
    report = ev.traceability.report
    _trace_gap_obligation(report, b)

    if report is None or not report.corpus_valid:
        b.add(
            "Review-verified requirements: unknown",
            "traceability-verification",
            "Without an analyzable trace report the statements relying on human "
            "review cannot be enumerated — regenerate with `make trace-report`.",
            review=True,
        )
    else:
        reviewed = review_verified_rows(report)
        b.add(
            f"Review-verified requirements: {len(reviewed)}"
            if reviewed
            else "Review-verified requirements: none",
            "traceability-verification",
            (
                "These statements declare `review` as a verification method: a "
                "recorded human argument stands in for machine evidence. Confirm "
                "each justification still holds."
                if reviewed
                else "No statement substitutes human review for machine evidence."
            ),
            review=bool(reviewed),
            items=[
                f"{layer} `{row.node}` — review: "
                + (
                    inline("; ".join(e for m in row.review_facets for e in m.evidence))
                    or "(no justification recorded)"
                )
                for layer, row in reviewed
            ],
        )

    # Empty-because-absent must not render as OK; each source vouches only for itself.
    waivers = ev.traceability.waivers
    waivers_missing = not ev.traceability.waivers_found
    b.add(
        "Trace waivers: waiver record not found"
        if waivers_missing
        else f"Trace waivers: {len(waivers)}"
        if waivers
        else "Trace waivers: none",
        "traceability-waivers",
        (
            "`requirements/trace_waivers.yaml` was not found, so nothing can be "
            "claimed about waived CONOPS leaves: check `--root`, or restore the file."
            if waivers_missing
            else "These CONOPS leaves are deliberately not realized by any HLR. Review "
            "each reason and confirm the waiver is still appropriate."
            if waivers
            else "No CONOPS leaf is waived from HLR coverage. (That the HLRs cover "
            "every non-waived leaf is checked by `make validate-reqs`, a "
            "prerequisite of `make report` — this report does not re-verify it.)"
        ),
        review=waivers_missing or bool(waivers),
        items=[f"CONOPS §{inline(w.leaf)} — {inline(w.reason)}" for w in waivers],
    )

    derived = ev.traceability.derived
    hlr_missing = not ev.traceability.hlr_found
    b.add(
        "Derived requirements: HLR tree not found"
        if hlr_missing
        else f"Derived requirements: {len(derived)}"
        if derived
        else "Derived requirements: none",
        "traceability-derived",
        (
            "`requirements/hlr/` was not found, so nothing can be claimed about "
            "derived requirements: check `--root`, or restore the tree."
            if hlr_missing
            else "Derived requirements have no CONOPS parent; they exist on the strength "
            "of their rationale alone. Review each one."
            if derived
            else "No HLR statement is marked `derived`. (That every non-derived "
            "statement traces to the CONOPS is checked by `make validate-reqs`, a "
            "prerequisite of `make report` — this report does not re-verify it.)"
        ),
        review=hlr_missing or bool(derived),
        items=[f"{inline(d.ident)} — {inline(d.text)}" for d in derived],
    )

    b.add(
        "CONOPS validity is human-owned",
        "traceability-conops",
        "Everything below the CONOPS is checked against it; nothing checks the CONOPS "
        "itself. A reviewer must confirm it describes the intersection you want.",
        review=True,
    )


def toolchain_note(proof_version: str | None, coverage_version: str | None) -> str:
    """Describe the recorded toolchain honestly, without assuming which one ran."""
    blob = f"{proof_version or ''} {coverage_version or ''}"
    if "FSF" in blob or "Community" in blob:
        return (
            "The recorded versions identify FSF community builds of GNATprove and "
            "GNATcoverage; these are not tool-qualified releases."
        )
    if blob.strip():
        return (
            "The recorded tool versions are not FSF community builds; confirm which "
            "releases these are and whether tool qualification applies to this use."
        )
    return (
        "Tool versions were not recorded — regenerate the evidence with "
        "`make prove-report` and `make coverage-report-xml`; without recorded "
        "versions the evidence cannot be tied to a toolchain."
    )


def _provenance_obligations(ev: Evidence, b: _Builder) -> None:
    """Obligations about the evidence itself: run consistency, tools, sources."""
    header = ev.proof.header
    forced = header is not None and header.forced
    prove_date = inline((header.date if header else None) or "unknown")
    trace_dates = (
        inline("; ".join(f"{t.program} at {t.date}" for t in ev.coverage.traces)) or "unknown"
    )
    cov_note = (
        " The gnatcov invocation that produced the coverage XML is recorded in "
        "the provenance section."
        if ev.coverage.command_text
        else " **No gnatcov invocation record (`gnatcov-command.txt`) was found**, "
        "so the coverage XML cannot be tied to a command line — regenerate with "
        "`make coverage-report-xml`."
    )
    b.add(
        "Tool invocations recorded (single forced proof run)"
        if forced and ev.coverage.command_text
        else "Tool-invocation provenance incomplete",
        "provenance-invocations",
        (
            f"The recorded gnatprove command line includes `-f`, so every unit's "
            f"artifacts were regenerated by that one invocation (run: {prove_date}). "
            f"The generator cannot verify that the coverage traces ({trace_dates}) "
            f"were produced from the same sources — cross-check these dates against "
            f"each other and the git state below."
            if forced
            else f"No gnatprove `--output-header` command line was recorded, or it "
            f"lacks `-f`: per-unit artifacts may be stale carry-overs from earlier, "
            f"differently-configured runs. Regenerate with `make prove-report`. "
            f"Coverage traces: {trace_dates}."
        )
        + cov_note,
        review=not forced or ev.coverage.command_text is None,
    )

    b.add(
        "Tool qualification",
        "provenance-tools",
        toolchain_note(ev.proof.version_text, ev.coverage.version_text)
        + " The proof results are sound only subject to GNATprove's documented "
        "assumptions, and every recorded tool version is in the provenance section.",
        review=True,
    )

    dirty = ev.git is None or ev.git.dirty
    b.add(
        "Sources not at a clean commit" if dirty else "Sources at a clean commit",
        "provenance-git",
        (
            "The working tree was dirty (or not a git checkout) when the report was "
            "generated: the report may not describe any committed state. Regenerate "
            "from a clean checkout for evidence worth archiving."
            if dirty
            else "The working tree was clean when the report was generated. Note the "
            "git state is sampled at report time, not when the tools ran — confirm "
            "via the run dates above that the evidence was produced from this state."
        ),
        review=dirty,
    )


def build_obligations(ev: Evidence) -> list[Obligation]:
    """Build the full, ordered review-obligation list for the report."""
    b = _Builder()
    _proof_obligations(ev, b)
    _coverage_obligations(ev, b)
    _traceability_obligations(ev, b)
    _provenance_obligations(ev, b)
    return b.obligations
