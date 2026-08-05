"""
Collect the requirement-chain facts the report currently covers.

Reads ``requirements/trace_waivers.yaml`` (CONOPS leaves waived from HLR
coverage, each with a reason to review) and the ``derived: true`` statements
in ``requirements/hlr/*.yaml`` (requirements with no CONOPS parent). Full
requirement matrices are planned work (plan phase 4); the chain itself is
validated by ``make validate-reqs``.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import yaml

from vreport.model import ArtifactParseError, DerivedRequirement, TraceabilityEvidence, Waiver

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


def collect_traceability(root: Path) -> TraceabilityEvidence:
    """Gather waivers and derived requirements from the requirements tree."""
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
        waivers=waivers, derived=derived, waivers_found=waivers_found, hlr_found=hlr_found
    )
