"""
Collect proof evidence from a gnatprove artifact directory.

Reads the per-unit ``*.spark`` JSON files, the ``gnatprove.out`` text summary
(header and summary table), ``gnatprove.sarif`` (invocation metadata and
warnings), and ``gnatprove-version.txt``. All artifacts must come from one
clean, forced run (``make prove-report``): gnatprove reuses per-unit results,
so artifacts from differently-switched runs are mutually inconsistent.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

from vreport.model import (
    ArtifactParseError,
    AssumptionClaim,
    AssumptionRef,
    GnatproveHeader,
    MissingArtifactsError,
    PragmaAssume,
    ProofCheck,
    ProofEvidence,
    ProverStats,
    SarifInvocation,
    SkipAnnotation,
    Sloc,
    SparkModeEntry,
    ToolWarning,
)
from vreport.provenance import read_optional

if TYPE_CHECKING:
    from collections.abc import Mapping
    from pathlib import Path

_HEADER_KEYS = {
    "date": "date",
    "gnatprove version": "version",
    "host": "host",
    "command line": "command_line",
}
_SUMMARY_TITLE = "Summary of SPARK analysis"
_SUMMARY_END = "max steps used"
_SUMMARY_FALLBACK_LINES = 30


def _sloc(entry: Mapping[str, Any], default_file: str) -> Sloc:
    """Build a Sloc from a .spark record (accepts both "col" and "column")."""
    column = entry.get("col", entry.get("column"))
    return Sloc(
        file=str(entry.get("file", default_file)),
        line=int(entry.get("line", 0)),
        column=int(column) if column is not None else None,
    )


def _entities(data: Mapping[str, Any]) -> dict[int, tuple[str, Sloc | None]]:
    """Index the entities table by id (ids carry a leading space in the JSON)."""
    out: dict[int, tuple[str, Sloc | None]] = {}
    for key, val in dict(data.get("entities") or {}).items():
        ident = int(str(key).strip())
        name = str(val.get("name", f"entity {ident}"))
        slocs = val.get("sloc") or []
        sloc = _sloc(slocs[0], name) if slocs else None
        out[ident] = (name, sloc)
    return out


def _entity_name(entities: Mapping[int, tuple[str, Sloc | None]], ref: Any) -> str | None:
    """Resolve an entity reference (an integer id) to its name."""
    if isinstance(ref, int) and ref in entities:
        return entities[ref][0]
    return None


def _justification(entry: Mapping[str, Any]) -> str | None:
    """Extract the pragma Annotate reason from a check's "suppressed" field."""
    suppressed = entry.get("suppressed")
    if isinstance(suppressed, str):
        return suppressed
    if isinstance(suppressed, dict):
        return str(suppressed.get("message", suppressed))
    return None


def _check(
    entry: Mapping[str, Any],
    unit: str,
    kind: str,
    entities: Mapping[int, tuple[str, Sloc | None]],
) -> ProofCheck:
    """Build a ProofCheck from one entry of a .spark "flow"/"proof" array."""
    message = entry.get("message")
    text = message.get("text") if isinstance(message, dict) else None
    provers = {
        str(name): ProverStats(
            count=int(stat.get("count", 0)),
            max_steps=int(stat.get("max_steps", 0)),
            max_time=float(stat.get("max_time", 0.0)),
        )
        for name, stat in dict(entry.get("stats") or {}).items()
    }
    return ProofCheck(
        unit=unit,
        kind=kind,
        rule=str(entry.get("rule", "?")),
        severity=str(entry.get("severity", "?")),
        location=_sloc(entry, unit),
        entity=_entity_name(entities, entry.get("entity")),
        message=text,
        how_proved=str(entry["how_proved"]) if "how_proved" in entry else None,
        provers=provers,
        justification=_justification(entry),
    )


def _skips(
    raw: Any,
    unit: str,
    kind: str,
    entities: Mapping[int, tuple[str, Sloc | None]],
) -> list[SkipAnnotation]:
    """Parse a skip_proof / skip_flow_proof array (entity ids or records)."""
    out: list[SkipAnnotation] = []
    for item in raw or []:
        if isinstance(item, int):
            name, sloc = entities.get(item, (f"entity {item}", None))
            out.append(SkipAnnotation(unit=unit, entity=name, kind=kind, location=sloc))
        elif isinstance(item, dict):
            name = str(item.get("name") or _entity_name(entities, item.get("entity")) or "?")
            sloc = _sloc(item, unit) if "line" in item else None
            out.append(SkipAnnotation(unit=unit, entity=name, kind=kind, location=sloc))
        else:
            out.append(SkipAnnotation(unit=unit, entity=str(item), kind=kind))
    return out


def _assumption_ref(
    raw: Mapping[str, Any], entities: Mapping[int, tuple[str, Sloc | None]]
) -> AssumptionRef:
    """Build an AssumptionRef from a claim/assumption record."""
    return AssumptionRef(
        predicate=str(raw.get("predicate", "?")),
        entity=_entity_name(entities, raw.get("arg")),
    )


def _parse_out(text: str) -> tuple[GnatproveHeader | None, str | None]:
    """Parse gnatprove.out: the --output-header block and the summary table."""
    lines = text.splitlines()
    fields: dict[str, str] = {}
    for line in lines[:15]:
        key, sep, value = line.partition(":")
        target = _HEADER_KEYS.get(key.strip())
        if sep and target:
            fields[target] = value.strip()
    header = GnatproveHeader(**fields) if fields else None

    summary: str | None = None
    starts = [i for i, line in enumerate(lines) if line.strip() == _SUMMARY_TITLE]
    if starts:
        start = starts[0] - 1 if starts[0] > 0 and set(lines[starts[0] - 1]) == {"="} else starts[0]
        end = next(
            (i for i in range(starts[0], len(lines)) if lines[i].startswith(_SUMMARY_END)),
            min(starts[0] + _SUMMARY_FALLBACK_LINES, len(lines) - 1),
        )
        summary = "\n".join(lines[start : end + 1]).strip()
    return header, summary


def _parse_sarif(path: Path) -> tuple[SarifInvocation | None, list[ToolWarning]]:
    """Parse gnatprove.sarif: invocation metadata and non-pass results."""
    data = _parse_json(path)
    runs = data.get("runs") or []
    if not runs:
        return None, []
    run: dict[str, Any] = runs[0]
    results: list[dict[str, Any]] = run.get("results") or []
    warnings: list[ToolWarning] = []
    passes = 0
    for result in results:
        if result.get("kind") == "pass":
            passes += 1
            continue
        location: Sloc | None = None
        locations = result.get("locations") or []
        if locations:
            physical = locations[0].get("physicalLocation") or {}
            region = physical.get("region") or {}
            uri = (physical.get("artifactLocation") or {}).get("uri")
            if uri is not None:
                location = Sloc(
                    file=str(uri),
                    line=int(region.get("startLine", 0)),
                    column=(int(region["startColumn"]) if "startColumn" in region else None),
                )
        warnings.append(
            ToolWarning(
                rule=str(result.get("ruleId", "?")),
                message=str((result.get("message") or {}).get("text", "")),
                location=location,
                suppressed=bool(result.get("suppressions")),
            )
        )
    invocations = run.get("invocations") or [{}]
    inv: dict[str, Any] = invocations[0]
    invocation = SarifInvocation(
        command_line=inv.get("commandLine"),
        end_time=inv.get("endTimeUtc"),
        exit_code=inv.get("exitCode"),
        execution_successful=inv.get("executionSuccessful"),
        pass_results=passes,
        open_results=len(results) - passes,
    )
    return invocation, warnings


def _parse_json(path: Path) -> dict[str, Any]:
    """Parse a JSON artifact, naming the file in any error."""
    try:
        data: dict[str, Any] = json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ArtifactParseError(path, str(exc)) from exc
    return data


def collect_proof(proof_dir: Path) -> ProofEvidence:
    """Parse a gnatprove artifact directory into ProofEvidence."""
    spark_files = sorted(proof_dir.glob("*.spark"))
    if not spark_files:
        raise MissingArtifactsError(proof_dir, "*.spark files")

    units: list[str] = []
    checks: list[ProofCheck] = []
    assumes: list[PragmaAssume] = []
    skips: list[SkipAnnotation] = []
    spark_modes: list[SparkModeEntry] = []
    claims: list[AssumptionClaim] = []

    for path in spark_files:
        unit = path.stem
        units.append(unit)
        data = _parse_json(path)
        entities = _entities(data)
        for kind in ("flow", "proof"):
            checks.extend(_check(entry, unit, kind, entities) for entry in data.get(kind) or [])
        assumes.extend(
            PragmaAssume(
                unit=unit,
                location=_sloc(entry, unit),
                entity=_entity_name(entities, entry.get("entity")),
            )
            for entry in data.get("pragma_assume") or []
        )
        skips.extend(_skips(data.get("skip_proof"), unit, "skip_proof", entities))
        skips.extend(_skips(data.get("skip_flow_proof"), unit, "skip_flow_and_proof", entities))
        for ident, mode in dict(data.get("spark") or {}).items():
            name, sloc = entities.get(int(str(ident).strip()), (f"entity {ident}", None))
            spark_modes.append(
                SparkModeEntry(unit=unit, entity=name, mode=str(mode), location=sloc)
            )
        claims.extend(
            AssumptionClaim(
                unit=unit,
                claim=_assumption_ref(entry.get("claim") or {}, entities),
                assumptions=[_assumption_ref(a, entities) for a in entry.get("assumptions") or []],
            )
            for entry in data.get("assumptions") or []
        )

    out_text = read_optional(proof_dir / "gnatprove.out")
    header, summary = _parse_out(out_text) if out_text else (None, None)
    sarif_path = proof_dir / "gnatprove.sarif"
    invocation, warnings = _parse_sarif(sarif_path) if sarif_path.is_file() else (None, [])

    return ProofEvidence(
        header=header,
        version_text=read_optional(proof_dir / "gnatprove-version.txt"),
        invocation=invocation,
        summary_text=summary,
        units=units,
        checks=checks,
        assumes=assumes,
        skips=skips,
        spark_modes=spark_modes,
        claims=claims,
        warnings=warnings,
    )
