"""
`reqs` command-line interface.

    reqs validate schema [PATHS...]            # schema + structural rules
    reqs validate ears   [PATHS...]            # EARS grammar
    reqs trace --chain FILE [--format table]   # traceability across the chain
    reqs trace --chain FILE --layers A,B       # ...over a subset of its layers
    reqs trace ... --allow-unselected M,N      # ...deferring these methods' evidence
    reqs trace --chain FILE --format json      # machine-readable trace report
    reqs document --chain FILE --out DIR       # the requirements as a document
    reqs document ... --source-root DIR        # ...listing the sources it cites

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
from reqs.render import RunInfo, render_document


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
_DOC_OUT = typer.Option(
    ..., "--out", help="Directory to write the rendered pages and their index into."
)
_DOC_SOURCE_ROOT = typer.Option(
    None,
    "--source-root",
    help=(
        "Directory the inventories' file paths are relative to (the repo root). "
        "Given, the cited sources are listed as pages and the evidence links into "
        "them; omitted, evidence renders as plain ids."
    ),
)
_DOC_LAYERS = typer.Option(
    None,
    "--layers",
    help=(
        "Comma-separated layer names to restrict the chain to (default: all). "
        "Links into an unselected layer render as plain ids."
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


@app.command("document")
def document(
    chain: Path = _CHAIN,
    out: Path = _DOC_OUT,
    layers_option: str | None = _DOC_LAYERS,
    source_root: Path | None = _DOC_SOURCE_ROOT,
    quiet: bool = _QUIET,
) -> None:
    """Render the requirement layers of the chain as a linked document."""
    chain_layers = load_chain(chain)
    selected_names: list[str] | None = None
    select_diags: list[Diagnostic] = []
    if layers_option is not None:
        selected_names = [name.strip() for name in layers_option.split(",") if name.strip()]
        _selected, select_diags = select_layers(chain_layers, selected_names, chain)
    req_paths = [layer.path for layer in chain_layers if layer.kind == REQUIREMENT_YAML]
    if select_diags:
        raise typer.Exit(report(select_diags, req_paths, quiet=quiet))
    argv = ["reqs", "document", "--chain", str(chain), "--out", str(out)]
    argv += ["--layers", layers_option] if layers_option is not None else []
    argv += ["--source-root", str(source_root)] if source_root is not None else []
    pages, diags, valid = render_document(
        chain_layers,
        out,
        selected_layers=selected_names,
        source_root=source_root,
        run=RunInfo(
            command=shlex.join(argv),
            generated_at=datetime.now(tz=UTC).isoformat(timespec="seconds"),
        ),
    )
    if not valid:
        # Nothing was written: the corpus did not analyse, so there is no
        # document to render. The diagnostics say why -- that is the verdict.
        raise typer.Exit(report(diags, req_paths, quiet=quiet) or 1)
    # Trace gaps are not this command's verdict (`reqs trace` owns that): they
    # are rendered *into* the document as the open items they are.
    print(f"{len(pages)} page(s) written to {out}")  # noqa: T201
    raise typer.Exit(0)


def main() -> None:
    """Entry point for the `reqs` executable."""
    app()


if __name__ == "__main__":
    main()
