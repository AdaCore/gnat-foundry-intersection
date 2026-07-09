"""
`reqs` command-line interface.

    reqs validate schema [PATHS...]            # schema + structural rules
    reqs validate ears   [PATHS...]            # EARS grammar
    reqs trace --chain FILE [--format table]   # traceability across the chain

With no PATHS, a validate command targets the default requirement set (the
curated examples for now). Future top-level commands (e.g. `reqs report`) attach
to the same app.
"""

from __future__ import annotations

from enum import StrEnum
from pathlib import Path

import typer

from reqs.checks.ears import EarsChecker
from reqs.checks.schema import RequirementChecker
from reqs.checks.trace import REQUIREMENT_YAML, TraceChecker, load_chain
from reqs.core import report


class OutputFormat(StrEnum):
    """Output formats supported by the `trace` command."""

    text = "text"  # diagnostics (the CI gate)
    table = "table"  # coverage / upward-trace tables for development


app = typer.Typer(help="Requirements tooling for the requirement YAML files.", no_args_is_help=True)
validate_app = typer.Typer(help="Validate requirement files.", no_args_is_help=True)
app.add_typer(validate_app, name="validate")

_PATHS = typer.Argument(..., help="Files or directories to check.")
_QUIET = typer.Option(False, "--quiet", "-q", help="Suppress warnings.")
_CHAIN = typer.Option(..., "--chain", help="Trace-chain config file (e.g. trace_chain.yaml).")
_FORMAT = typer.Option(
    OutputFormat.text, "--format", help="Output: 'text' (diagnostics) or 'table'."
)
_TRACE_COMPLETE = typer.Option(
    False, "--complete", help="Treat an uncovered upper-layer node as an error (the CI gate)."
)


@validate_app.command("schema")
def validate_schema(
    paths: list[Path] = _PATHS,
    complete: bool = typer.Option(
        False,
        "--complete",
        help="Treat the inputs as a complete set: unresolved parent_req is an error.",
    ),
    quiet: bool = _QUIET,
) -> None:
    """Validate against the schema plus the structural/RS.3 rules."""
    diags = RequirementChecker(complete=complete).check(paths)
    raise typer.Exit(report(diags, paths, quiet=quiet))


@validate_app.command("ears")
def validate_ears(
    paths: list[Path] = _PATHS,
    quiet: bool = _QUIET,
) -> None:
    """Lint the EARS grammar of every description statement."""
    diags = EarsChecker().check(paths)
    raise typer.Exit(report(diags, paths, quiet=quiet))


@app.command("trace")
def trace(
    chain: Path = _CHAIN,
    complete: bool = _TRACE_COMPLETE,
    output: OutputFormat = _FORMAT,
    quiet: bool = _QUIET,
) -> None:
    """Check traceability across the chain: dangling/untraced refs and uncovered nodes."""
    layers = load_chain(chain)
    checker = TraceChecker(layers, complete=complete)
    diags = checker.check()
    if output is OutputFormat.table:
        checker.print_tables()
        raise typer.Exit(1 if any(d.level == "error" for d in diags) else 0)
    req_paths = [layer.path for layer in layers if layer.kind == REQUIREMENT_YAML]
    raise typer.Exit(report(diags, req_paths, quiet=quiet))


def main() -> None:
    """Entry point for the `reqs` executable."""
    app()


if __name__ == "__main__":
    main()
