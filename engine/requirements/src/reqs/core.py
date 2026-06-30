"""
Shared scaffolding for the requirement checks.

Every check (schema, EARS, and later traceability/reporting) walks a set of
requirement YAML files and emits located diagnostics. This module holds what
they share so each check reads the same way: the `Diagnostic` record, file
discovery, YAML loading with source-line tracking, the markup regexes, and the
`report` helper that renders diagnostics and yields an exit code.

CLI wiring lives in `reqs.cli` (Typer); this module is framework-agnostic.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from functools import cache
from pathlib import Path

import yaml

# Markup that is not requirement prose; stripped before counting "shall" or
# matching the EARS grammar so code listings / math / tables don't interfere.
FENCE_RE = re.compile(r"```.*?```", re.DOTALL)
MATH_RE = re.compile(r"\$\$.*?\$\$", re.DOTALL)
SHALL_RE = re.compile(r"\bshall\b", re.IGNORECASE)


def prose(statement: str) -> str:
    """
    Reduce a statement to its requirement prose.

    Strips fenced code blocks, ``$$`` math, and table/list lines, then collapses
    to one line. Shared by the RS.3 "shall"-count (schema check) and the EARS
    grammar lint so the two agree on what counts as prose -- a "shall" inside a
    code block, math span, or table cell is invisible to both.
    """
    s = FENCE_RE.sub(" ", statement)
    s = MATH_RE.sub(" ", s)
    lines = [ln for ln in s.splitlines() if not ln.lstrip().startswith("|")]
    return re.sub(r"\s+", " ", " ".join(lines)).strip()


@cache
def project_root() -> Path:
    """Return the `engine/requirements` directory (nearest ancestor with pyproject.toml)."""
    for parent in Path(__file__).resolve().parents:
        if (parent / "pyproject.toml").is_file():
            return parent
    raise RuntimeError("could not locate project root (no pyproject.toml found)")  # noqa: TRY003


def schema_path() -> Path:
    return project_root() / "schema" / "requirement.schema.json"


@dataclass
class Diagnostic:
    level: str  # "error" | "warning"
    code: str  # e.g. "E-SCHEMA", "W-RS3", "E-EARS-PATTERN"
    message: str
    file: Path
    line: int | None = None
    path: tuple[str, ...] = ()  # location within the file, e.g. ("description", "4")

    def format(self) -> str:
        loc = str(self.file)
        if self.line is not None:
            loc += f":{self.line}"
        where = f" (at {'.'.join(self.path)})" if self.path else ""
        return f"{loc}: [{self.level.upper()} {self.code}] {self.message}{where}"


def iter_yaml_files(paths) -> list[Path]:
    """
    Expand each path into requirement files, preserving the given order.

    A directory is walked recursively and its files sorted; any other path
    (an explicit file, or a typo that exists as neither file nor directory) is
    kept as given, so callers see it and :func:`load_yaml` reports it.
    """
    files: list[Path] = []
    for raw in paths:
        p = Path(raw)
        files.extend(sorted(p.rglob("*.yaml")) if p.is_dir() else [p])
    return files


def compose_lines(text: str) -> tuple[dict[tuple[str, ...], int], list[str]]:
    """
    Walk the compose node tree once, returning ``(lines, dups)``.

    ``lines`` maps top-level keys and `description` sub-keys to 1-based source
    lines. ``dups`` lists `description` sub-keys that appear more than once:
    ``safe_load`` silently merges duplicate mapping keys (last value wins), so a
    repeated statement number is invisible after parsing -- the node tree
    preserves every occurrence, so we surface them from the same pass.
    """
    lines: dict[tuple[str, ...], int] = {}
    dups: list[str] = []
    try:
        root = yaml.compose(text)
    except yaml.YAMLError:
        return lines, dups
    if not isinstance(root, yaml.MappingNode):
        return lines, dups
    for key_node, value_node in root.value:
        key = str(key_node.value)
        lines[(key,)] = key_node.start_mark.line + 1
        if key == "description" and isinstance(value_node, yaml.MappingNode):
            seen: set[str] = set()
            for sub_key, _ in value_node.value:
                k = str(sub_key.value)
                lines[("description", k)] = sub_key.start_mark.line + 1
                if k in seen and k not in dups:
                    dups.append(k)
                seen.add(k)
    return lines, dups


def load_yaml(path: Path):
    """
    Parse a requirement file.

    Returns ``(data, lines, dups, error)``: ``data`` is the parsed mapping (or
    None), ``lines`` and ``dups`` are the source-line map and duplicate
    `description` sub-keys from :func:`compose_lines`, and ``error`` is a
    Diagnostic to report when the file can't be read, fails to parse, or isn't
    a mapping.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, {}, [], Diagnostic("error", "E-IO", f"cannot read file: {exc}", path)
    lines, dups = compose_lines(text)
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        return None, lines, dups, Diagnostic("error", "E-YAML", f"YAML parse error: {exc}", path)
    if not isinstance(data, dict):
        return None, lines, dups, Diagnostic("error", "E-YAML", "top level must be a mapping", path)
    return data, lines, dups, None


def report(diags: list[Diagnostic], paths, *, quiet: bool = False) -> int:
    """
    Print diagnostics (errors -> stderr, warnings -> stdout) + a summary line.

    Returns the process exit code: non-zero iff any error was reported.
    """
    errors = [d for d in diags if d.level == "error"]
    warnings = [d for d in diags if d.level == "warning"]
    for d in sorted(diags, key=lambda d: (str(d.file), d.line or 0, d.code)):
        if d.level == "warning" and quiet:
            continue
        print(d.format(), file=sys.stderr if d.level == "error" else sys.stdout)
    n = len(iter_yaml_files(paths))
    summary = f"{n} file(s): {len(errors)} error(s), {len(warnings)} warning(s)"
    print(summary, file=sys.stderr if errors else sys.stdout)
    return 1 if errors else 0
