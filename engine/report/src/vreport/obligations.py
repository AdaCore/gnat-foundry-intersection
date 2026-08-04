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
from typing import TYPE_CHECKING

from vreport.model import CheckStatus, Obligation, ObligationStatus

if TYPE_CHECKING:
    from collections.abc import Iterable

    from vreport.model import (
        AssumptionClaim,
        AssumptionRef,
        CoverageViolation,
        Evidence,
        ProofEvidence,
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
    it. Heuristic caveats: the match is per source-file basename (two files
    with the same basename in different directories would be conflated) and
    per file, not per line.
    """
    name = Path(violation.location.file).name
    if Path(name).stem.endswith("_proof"):
        return ViolationClass.proof_support
    proved: set[str] = set()
    tainted: set[str] = set()
    for check in proof.checks:
        bucket = proved if check.status is CheckStatus.proved else tainted
        bucket.add(Path(check.location.file).name)
    if name in proved and name not in tainted:
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
    proved = {(c.claim.predicate, c.claim.entity) for c in proof.claims}
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
        items=[f"`{c.location}` — {c.rule}: {c.message or ''}" for c in unproved],
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
        items=[f"`{c.location}` — {c.rule}: {c.justification or ''}" for c in justified],
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
    b.add(
        f"Tool warnings: {len(warnings)}" if warnings else "Tool warnings: none",
        "proof-warnings",
        (
            "gnatprove warnings can flag violations of the tool's own soundness "
            "assumptions; suppressed warnings in particular are human claims and "
            "need review."
            if warnings
            else "gnatprove emitted no warnings."
        ),
        review=bool(warnings),
        items=[
            f"`{w.location}` — {w.rule}: {w.message}" + (" *(suppressed)*" if w.suppressed else "")
            if w.location
            else f"{w.rule}: {w.message}"
            for w in warnings
        ],
    )

    generic_note = (
        " Note: generic units are analyzed at their instantiations and contribute few "
        "or no entities to this list; judge generic code by where proved checks are "
        "located (the coverage classification does this per file)."
    )
    outside = ev.proof.non_spark_entities
    b.add(
        f"Code outside the proof: {len(outside)} entities"
        if outside
        else "Code outside the proof: none",
        "proof-spark-modes",
        (
            "These entities are not fully analyzed by gnatprove (`spec`: only the "
            "contract is in SPARK; `no`: not analyzed at all). No proof covers their "
            "bodies — confirm they are exercised by tests and reviewed by hand."
            if outside
            else "Every analyzed entity is fully in SPARK."
        )
        + generic_note,
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
    violations = ev.coverage.non_exempted_violations
    b.add(
        f"Uncovered code: {len(violations)} violations" if violations else "Uncovered code: none",
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
            "proven nor executed and needs a test, removal, or an exemption."
            if violations
            else f"The test suite covers every non-exempted obligation at `{ev.coverage.level}`."
        ),
        review=bool(violations),
        items=[
            f"`{v.location}` — {v.obligation_kind} {v.message} — "
            f"*{classify_violation(v, ev.proof)}*"
            for v in violations
        ],
    )

    exemptions = ev.coverage.exemptions
    b.add(
        f"Coverage exemptions: {len(exemptions)}" if exemptions else "Coverage exemptions: none",
        "coverage-exemptions",
        (
            "An exempted region replaces coverage with an argument. Review each "
            "justification and confirm it still holds for the current code."
            if exemptions
            else "No coverage obligation is exempted."
        ),
        review=bool(exemptions),
        items=[f"`{e.file}:{e.line}` — {e.justification}" for e in exemptions],
    )


def _traceability_obligations(ev: Evidence, b: _Builder) -> None:
    """Obligations derived from the requirements chain (partial, see plan)."""
    # An empty list means "verified clean" only if a requirements tree was
    # actually read — empty-because-absent must not render as OK.
    missing = not ev.traceability.sources_found
    missing_detail = (
        "No requirements tree was found under the project root, so nothing can "
        "be claimed here: check `--root`, or restore `requirements/`."
    )

    waivers = ev.traceability.waivers
    b.add(
        "Trace waivers: no requirements tree found"
        if missing
        else f"Trace waivers: {len(waivers)}"
        if waivers
        else "Trace waivers: none",
        "traceability-waivers",
        (
            missing_detail
            if missing
            else "These CONOPS leaves are deliberately not realized by any HLR. Review "
            "each reason and confirm the waiver is still appropriate."
            if waivers
            else "Every CONOPS leaf is covered by the HLRs."
        ),
        review=missing or bool(waivers),
        items=[f"CONOPS §{w.leaf} — {w.reason}" for w in waivers],
    )

    derived = ev.traceability.derived
    b.add(
        "Derived requirements: no requirements tree found"
        if missing
        else f"Derived requirements: {len(derived)}"
        if derived
        else "Derived requirements: none",
        "traceability-derived",
        (
            missing_detail
            if missing
            else "Derived requirements have no CONOPS parent; they exist on the strength "
            "of their rationale alone. Review each one."
            if derived
            else "Every HLR statement traces to the CONOPS."
        ),
        review=missing or bool(derived),
        items=[f"{d.ident} — {d.text}" for d in derived],
    )

    b.add(
        "Traceability below LLR is not machine-checked",
        "traceability",
        "The mechanical chain covers CONOPS → HLR → LLR (`make validate-reqs`). "
        "Requirement-to-code and requirement-to-test links are not yet verified: "
        "treat `implemented_by` references and requirement IDs in code or test "
        "comments as unchecked claims (planned work, plan phase 4).",
        review=True,
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
    prove_date = (header.date if header else None) or "unknown"
    trace_dates = "; ".join(f"{t.program} at {t.date}" for t in ev.coverage.traces) or "unknown"
    b.add(
        "Proof artifacts from a single forced run"
        if forced
        else "Proof-run provenance not verified",
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
        ),
        review=not forced,
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
