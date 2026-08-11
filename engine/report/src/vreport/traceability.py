"""
Collect the requirement-chain evidence.

Two kinds of source feed this collector. The trace report
(``reports/trace/trace_report.json``, produced by ``make trace-report`` /
``reqs trace --format json``) carries the machine-checked matrices over the
whole chain — coverage per (parent, child) pair, the merged verification view,
and the gate's diagnostics. The requirement tree itself supplies the pure
human-judgement items: ``requirements/trace_waivers.yaml`` (CONOPS leaves
waived from HLR coverage, each with a reason to review) and the
``derived: true`` statements in ``requirements/hlr/*.yaml`` (requirements with
no CONOPS parent).
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import yaml
from pydantic import ValidationError

from vreport.model import (
    TRACE_REPORT_SCHEMA_VERSION,
    ArtifactParseError,
    DerivedRequirement,
    MissingArtifactsError,
    TraceabilityEvidence,
    TraceReport,
    Waiver,
)

if TYPE_CHECKING:
    from pathlib import Path


def _load_yaml(path: Path) -> dict[str, Any]:
    """Parse a YAML artifact, naming the file in any error."""
    try:
        data: dict[str, Any] = yaml.safe_load(path.read_text()) or {}
    except yaml.YAMLError as exc:
        raise ArtifactParseError(path, str(exc)) from exc
    return data


def _description_key(item: tuple[Any, Any]) -> tuple[int, str]:
    """Sort description keys numerically when possible, lexically otherwise."""
    key = str(item[0])
    return (0, f"{int(key):09d}") if key.isdigit() else (1, key)


def collect_trace_report(path: Path) -> TraceReport:
    """Parse the `reqs trace --format json` payload, naming the file in any error."""
    if not path.is_file():
        raise MissingArtifactsError(path, "trace report (reqs trace --format json)")
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactParseError(path, str(exc)) from exc
    if not isinstance(data, dict):
        raise ArtifactParseError(path, "top level must be an object")
    version = data.pop("schema_version", None)
    if version != TRACE_REPORT_SCHEMA_VERSION:
        raise ArtifactParseError(
            path,
            f"unsupported schema_version {version!r} (this reader supports "
            f"{TRACE_REPORT_SCHEMA_VERSION}) — regenerate with `make trace-report`",
        )
    try:
        return TraceReport.model_validate(data)
    except ValidationError as exc:
        raise ArtifactParseError(path, str(exc)) from exc


def collect_traceability(root: Path, trace_report: Path | None = None) -> TraceabilityEvidence:
    """Gather the trace report, waivers, and derived requirements under ROOT."""
    report = collect_trace_report(trace_report or root / "reports" / "trace" / "trace_report.json")

    waivers: list[Waiver] = []
    derived: list[DerivedRequirement] = []

    waivers_path = root / "requirements" / "trace_waivers.yaml"
    waivers_found = waivers_path.is_file()
    if waivers_found:
        data = _load_yaml(waivers_path)
        waivers = [
            Waiver(leaf=str(w.get("leaf", "?")), reason=str(w.get("reason", "")).strip())
            for w in data.get("waivers") or []
        ]

    hlr_dir = root / "requirements" / "hlr"
    hlr_found = hlr_dir.is_dir()
    if hlr_found:
        for path in sorted(hlr_dir.glob("*.yaml")):
            doc = _load_yaml(path)
            description = doc.get("description")
            if not isinstance(description, dict):
                continue
            derived.extend(
                DerivedRequirement(
                    ident=f"{path.stem}.{key}", text=str(val.get("text", "")).strip()
                )
                for key, val in sorted(description.items(), key=_description_key)
                if isinstance(val, dict) and val.get("derived")
            )

    return TraceabilityEvidence(
        waivers=waivers,
        derived=derived,
        waivers_found=waivers_found,
        hlr_found=hlr_found,
        report=report,
    )
