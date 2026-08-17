"""
`reqs` command-line interface.

    reqs validate schema [PATHS...]            # schema + structural rules
    reqs validate ears   [PATHS...]            # EARS grammar
    reqs trace --chain FILE [--format table]   # traceability across the chain
    reqs trace --chain FILE --layers A,B       # ...over a subset of its layers
    reqs trace ... --allow-unselected M,N      # ...deferring these methods' evidence
    reqs trace --chain FILE --format json      # machine-readable trace report

With no PATHS, a validate command targets the default requirement set (the
curated examples for now). Future top-level commands (e.g. `reqs report`) attach
to the same app.
"""

from __future__ import annotations

import json
import shlex
import sys
from datetime import UTC, datetime
from enum import StrEnum
from pathlib import Path

import typer

from reqs.checks.ears import EarsChecker
from reqs.checks.schema import RequirementChecker
from reqs.checks.trace import (
    REQUIREMENT_YAML,
    TraceChecker,
    load_chain,
    select_allowed_methods,
    select_layers,
)
from reqs.core import Diagnostic, report


class OutputFormat(StrEnum):
    """Output formats supported by the `trace` command."""

    text = "text"  # diagnostics (the CI gate)
    table = "table"  # coverage / upward-trace tables for development
    json = "json"  # machine-readable report (for report generators)


app = typer.Typer(help="Requirements tooling for the requirement YAML files.", no_args_is_help=True)
validate_app = typer.Typer(help="Validate requirement files.", no_args_is_help=True)
app.add_typer(validate_app, name="validate")

_PATHS = typer.Argument(..., help="Files or directories to check.")
_QUIET = typer.Option(False, "--quiet", "-q", help="Suppress warnings.")
_CHAIN = typer.Option(..., "--chain", help="Trace-chain config file (e.g. trace_chain.yaml).")
_FORMAT = typer.Option(
    OutputFormat.text,
    "--format",
    help=(
        "Output: 'text' (diagnostics), 'table' (dev tables), or 'json' (machine-readable "
        "report; exits 0 once written -- the verdict travels inside the payload)."
    ),
)
_OUTPUT = typer.Option(None, "--output", "-o", help="Write the json report here instead of stdout.")
_TRACE_COMPLETE = typer.Option(
    False, "--complete", help="Treat an uncovered upper-layer node as an error (the CI gate)."
)
_TRACE_LAYERS = typer.Option(
    None,
    "--layers",
    help=(
        "Comma-separated layer names to restrict the chain to (default: all). "
        "Only pairs wholly inside the selection are checked."
    ),
)
_TRACE_ALLOW_UNSELECTED = typer.Option(
    None,
    "--allow-unselected",
    help=(
        "Comma-separated verification methods whose declared-but-unselected "
        "statements are tolerated (no E-TRACE-UNSELECTED)."
    ),
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
    layers_option: str | None = _TRACE_LAYERS,
    allow_unselected_option: str | None = _TRACE_ALLOW_UNSELECTED,
    output: OutputFormat = _FORMAT,
    output_path: Path | None = _OUTPUT,
    quiet: bool = _QUIET,
) -> None:
    """Check traceability across the chain: dangling/untraced refs and uncovered nodes."""
    if output_path is not None and output is not OutputFormat.json:
        raise typer.BadParameter("--output applies only to --format json")
    chain_layers = load_chain(chain)
    selected_layers = chain_layers
    selected_names: list[str] | None = None
    select_diags: list[Diagnostic] = []
    if layers_option is not None:
        selected_names = [name.strip() for name in layers_option.split(",") if name.strip()]
        selected_layers, select_diags = select_layers(chain_layers, selected_names, chain)
    allow_unselected: frozenset[str] = frozenset()
    if allow_unselected_option is not None:
        methods = [m.strip() for m in allow_unselected_option.split(",") if m.strip()]
        allow_unselected, allow_diags = select_allowed_methods(methods, chain)
        select_diags += allow_diags
    req_paths = [layer.path for layer in selected_layers if layer.kind == REQUIREMENT_YAML]
    if select_diags:
        raise typer.Exit(report(select_diags, req_paths, quiet=quiet))
    checker = TraceChecker(
        chain_layers,
        selected_layers=selected_names,
        complete=complete,
        allow_unselected=allow_unselected,
    )
    if output is OutputFormat.json:
        # Producing the report is not the gate (`text` is): exit 0 once it is
        # written, so a chain full of gaps still yields the evidence describing
        # them. The verdict is in the payload (`errors`/`warnings`/`corpus_valid`).
        argv = ["reqs", "trace", "--chain", str(chain)]
        argv += ["--complete"] if complete else []
        argv += ["--layers", layers_option] if layers_option is not None else []
        argv += (
            ["--allow-unselected", allow_unselected_option]
            if allow_unselected_option is not None
            else []
        )
        argv += ["--quiet"] if quiet else []
        argv += ["--format", "json"]
        argv += ["--output", str(output_path)] if output_path is not None else []
        payload = checker.to_report(
            chain=chain,
            command=shlex.join(argv),
            generated_at=datetime.now(tz=UTC).isoformat(timespec="seconds"),
        )
        text = json.dumps(payload, indent=2) + "\n"
        if output_path is None:
            sys.stdout.write(text)
        else:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            output_path.write_text(text, encoding="utf-8")
        raise typer.Exit(0)
    diags = checker.check()
    if output is OutputFormat.table:
        checker.print_tables()
        raise typer.Exit(1 if any(d.level == "error" for d in diags) else 0)
    raise typer.Exit(report(diags, req_paths, quiet=quiet))


def main() -> None:
    """Entry point for the `reqs` executable."""
    app()


if __name__ == "__main__":
    main()
