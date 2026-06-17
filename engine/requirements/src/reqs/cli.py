"""
`reqs` command-line interface.

    reqs validate schema [PATHS...]   # schema + structural rules
    reqs validate ears   [PATHS...]   # EARS grammar

With no PATHS, a command targets the default requirement set (the curated
examples for now). Future top-level commands (e.g. `reqs trace`, `reqs report`)
attach to the same app.
"""

from __future__ import annotations

from pathlib import Path

import typer

from reqs.checks.ears import EarsChecker
from reqs.checks.schema import RequirementChecker
from reqs.core import report

app = typer.Typer(help="Requirements tooling for the requirement YAML files.", no_args_is_help=True)
validate_app = typer.Typer(help="Validate requirement files.", no_args_is_help=True)
app.add_typer(validate_app, name="validate")

_PATHS = typer.Argument(..., help="Files or directories to check.")
_QUIET = typer.Option(False, "--quiet", "-q", help="Suppress warnings.")


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
    """Validate against the JSON Schema plus the structural/RS.3 rules."""
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


def main() -> None:
    app()


if __name__ == "__main__":
    main()
