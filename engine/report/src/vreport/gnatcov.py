"""
Collect coverage evidence from a gnatcov XML report directory.

Reads ``index.xml`` (global and per-file counters), each per-source XML
(scope metrics, violations, exempted regions with their justification text),
``trace.xml`` (which test executions fed the analysis), and
``gnatcov-version.txt``. The XML annotation format is the documented
machine-readable gnatcov output; exempted code is recognized by the enclosing
``src_mapping`` coverage state (``*``/``#``). Message kinds other than
violations and exemption notices (e.g. undetermined-coverage notes) are not
collected — their counts still surface through the metric tables.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from pathlib import Path

from vreport.model import (
    ArtifactParseError,
    CoverageEvidence,
    CoverageViolation,
    Exemption,
    FileCoverage,
    FileScope,
    MissingArtifactsError,
    ObligationStats,
    Sloc,
    TraceInfo,
)
from vreport.provenance import read_optional

_SCO_RE = re.compile(r"SCO #(\d+): (\w+)")
_EXEMPTION_PREFIX = "Exempted region justification: "
_EXEMPTED_STATES = frozenset({"*", "#"})
_OBLIGATION_TAGS = ("statement", "decision", "condition")


def _counts(el: ET.Element) -> dict[str, int]:
    """Read the direct <metric> children of `el` into a kind->count map."""
    return {m.get("kind", "?"): int(m.get("count", "0")) for m in el.findall("metric")}


def _obligations(el: ET.Element) -> list[ObligationStats]:
    """Read the direct <obligation_stats> children of `el`."""
    return [
        ObligationStats(kind=o.get("kind", "?"), counts=_counts(o))
        for o in el.findall("obligation_stats")
    ]


def _scopes(el: ET.Element, prefix: str) -> list[FileScope]:
    """Flatten the nested <scope_metric> tree into dotted-name entries."""
    out: list[FileScope] = []
    for scope in el.findall("scope_metric"):
        name = scope.get("scope_name", "?")
        qualified = f"{prefix}.{name}" if prefix else name
        out.append(
            FileScope(
                name=qualified,
                line=int(scope.get("scope_line", "0")),
                counts=_counts(scope),
            )
        )
        out.extend(_scopes(scope, qualified))
    return out


def _first_line(el: ET.Element) -> tuple[int | None, str | None]:
    """Return the first (line number, source text) under `el`'s <src> block."""
    line = el.find("./src/line")
    if line is None:
        return None, None
    num = line.get("num")
    return int(num) if num is not None else None, line.get("src")


def _obligation_index(mapping: ET.Element) -> dict[str, ET.Element]:
    """Index a mapping's statement/decision/condition elements by SCO id."""
    out: dict[str, ET.Element] = {}
    for tag in _OBLIGATION_TAGS:
        for ob in mapping.iter(tag):
            ident = ob.get("id")
            if ident is not None:
                out[ident] = ob
    return out


def _violation(
    msg: ET.Element,
    mapping: ET.Element,
    obligations: dict[str, ET.Element],
    path: str,
    *,
    exempted: bool,
) -> CoverageViolation:
    """Build a CoverageViolation from one <message kind="violation">."""
    sco = msg.get("SCO", "")
    match = _SCO_RE.match(sco)
    kind = match.group(2) if match else "?"
    source = obligations.get(match.group(1)) if match else None
    line, text = _first_line(source) if source is not None else (None, None)
    if line is None:
        line, text = _first_line(mapping)
    column = source.get("column_begin") if source is not None else None
    return CoverageViolation(
        location=Sloc(file=path, line=line or 0, column=int(column) if column else None),
        sco=sco,
        obligation_kind=kind,
        message=msg.get("message", ""),
        exempted=exempted,
        source_text=text.strip() if text else None,
    )


def _unquote(text: str) -> str:
    """Drop one pair of surrounding double quotes, preserving interior ones."""
    if len(text) > 1 and text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    return text


def _parse_source(
    detail: Path, path: str
) -> tuple[list[FileScope], list[CoverageViolation], list[Exemption]]:
    """
    Parse one per-source XML into scopes, violations, and exemptions.

    Masked violations are attributed to the most recent exemption notice in
    document order (the notice sits on the ``Exempt_On`` pragma, which
    precedes its region); an exempted violation with no preceding notice
    stays unattributed but is still flagged in the violation list.
    """
    root = _parse_xml(detail)
    violations: list[CoverageViolation] = []
    pending: list[tuple[int, str, list[CoverageViolation]]] = []
    for mapping in root.iter("src_mapping"):
        exempted = mapping.get("coverage", ".") in _EXEMPTED_STATES
        obligations = _obligation_index(mapping)
        for msg in mapping.iter("message"):
            kind = msg.get("kind")
            text = msg.get("message", "")
            if kind == "violation":
                violation = _violation(msg, mapping, obligations, path, exempted=exempted)
                violations.append(violation)
                if exempted and pending:
                    pending[-1][2].append(violation)
            elif kind == "notice" and text.startswith(_EXEMPTION_PREFIX):
                line, _ = _first_line(mapping)
                justification = _unquote(text.removeprefix(_EXEMPTION_PREFIX).strip())
                pending.append((line or 0, justification, []))
    exemptions = [
        Exemption(file=path, line=line, justification=justification, masked=masked)
        for line, justification, masked in pending
    ]
    return _scopes(root, ""), violations, exemptions


def _parse_xml(path: Path) -> ET.Element:
    """Parse an XML artifact into its root element, naming the file in any error."""
    try:
        return ET.parse(path).getroot()
    except ET.ParseError as exc:
        raise ArtifactParseError(path, str(exc)) from exc


def _relative(name: str, root: Path) -> str:
    """Make an absolute source path relative to the project root if possible."""
    try:
        return str(Path(name).relative_to(root))
    except ValueError:
        return name


def collect_coverage(xml_dir: Path, root: Path) -> CoverageEvidence:
    """Parse a gnatcov XML report directory into CoverageEvidence."""
    index = xml_dir / "index.xml"
    if not index.is_file():
        raise MissingArtifactsError(xml_dir, "a gnatcov XML report (index.xml)")

    report = _parse_xml(index).find("coverage_report")
    if report is None:
        raise MissingArtifactsError(xml_dir, "a <coverage_report> element in index.xml")
    summary = report.find("coverage_summary")
    if summary is None:
        raise MissingArtifactsError(xml_dir, "a <coverage_summary> element in index.xml")

    files: list[FileCoverage] = []
    violations: list[CoverageViolation] = []
    exemptions: list[Exemption] = []
    for file_el in summary.findall("file"):
        name = file_el.get("name", "?")
        path = _relative(name, root)
        detail = xml_dir / (Path(name).name + ".xml")
        if not detail.is_file():
            raise MissingArtifactsError(xml_dir, f"the per-source report {detail.name}")
        scopes, file_violations, file_exemptions = _parse_source(detail, path)
        violations.extend(file_violations)
        exemptions.extend(file_exemptions)
        files.append(
            FileCoverage(
                path=path,
                counts=_counts(file_el),
                obligations=_obligations(file_el),
                scopes=scopes,
            )
        )

    traces: list[TraceInfo] = []
    trace_file = xml_dir / "trace.xml"
    if trace_file.is_file():
        traces = [
            TraceInfo(
                filename=t.get("filename", "?"),
                program=t.get("program", "?"),
                date=t.get("date", "?"),
            )
            for t in _parse_xml(trace_file).findall("trace")
        ]

    return CoverageEvidence(
        level=report.get("coverage_level", "?"),
        version_text=read_optional(xml_dir / "gnatcov-version.txt"),
        command_text=read_optional(xml_dir / "gnatcov-command.txt"),
        traces=traces,
        counts=_counts(summary),
        obligations=_obligations(summary),
        files=files,
        violations=violations,
        exemptions=exemptions,
    )
