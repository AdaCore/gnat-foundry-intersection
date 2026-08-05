"""
`vreport` command-line interface.

    vreport generate --root DIR --out DIR   # collect evidence, render the report

Inputs are the artifacts left by the verification tools (see README.md);
outputs are `evidence.json`, the generated MyST sources, and the HTML report.
"""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from typing import NoReturn

import typer

from vreport.build import build_html, build_pdf, write_sphinx_sources
from vreport.emit import emit_pages
from vreport.gnatcov import collect_coverage
from vreport.gnatprove import collect_proof
from vreport.model import ArtifactParseError, Evidence, MissingArtifactsError, ObligationStatus
from vreport.obligations import build_obligations
from vreport.provenance import collect_git
from vreport.traceability import collect_traceability

app = typer.Typer(help="Verification-report generator.", no_args_is_help=True)


@app.callback()
def _callback() -> None:
    """Keep `generate` an explicit subcommand (future commands attach here)."""


_ROOT = typer.Option(Path(), "--root", help="Project root the evidence describes.")
_OUT = typer.Option(..., "--out", help="Output directory for the report.")
_PROOF_DIR = typer.Option(
    None, "--proof-dir", help="gnatprove artifact dir (default: ROOT/obj/development/gnatprove)."
)
_COVERAGE_DIR = typer.Option(
    None, "--coverage-dir", help="gnatcov XML dir (default: ROOT/reports/coverage/xml)."
)
_TITLE = typer.Option(None, "--title", help="Report title (default derives from ROOT).")
_HTML = typer.Option(True, "--html/--no-html", help="Also build the HTML report.")
_PDF = typer.Option(False, "--pdf/--no-pdf", help="Also build a PDF rendering (rst2pdf).")


def _fail(message: str, hint: str | None = None) -> NoReturn:
    """Report a fatal error (with an optional make-target hint) and exit."""
    typer.secho(f"error: {message}", fg=typer.colors.RED, err=True)
    if hint:
        typer.secho(f"hint: run `{hint}` first", err=True)
    raise typer.Exit(1)


@app.command()
def generate(
    out: Path = _OUT,
    root: Path = _ROOT,
    proof_dir: Path | None = _PROOF_DIR,
    coverage_dir: Path | None = _COVERAGE_DIR,
    title: str | None = _TITLE,
    html: bool = _HTML,
    pdf: bool = _PDF,
) -> None:
    """Collect the tool evidence under ROOT and render the report into OUT."""
    root = root.resolve()
    try:
        proof = collect_proof(proof_dir or root / "obj" / "development" / "gnatprove")
    except (MissingArtifactsError, ArtifactParseError) as exc:
        _fail(str(exc), hint="make prove-report")
    try:
        coverage = collect_coverage(coverage_dir or root / "reports" / "coverage" / "xml", root)
    except (MissingArtifactsError, ArtifactParseError) as exc:
        _fail(str(exc), hint="make coverage-report-xml")
    try:
        traceability = collect_traceability(root)
    except ArtifactParseError as exc:
        _fail(str(exc))

    evidence = Evidence(
        generated_at=datetime.now(tz=UTC).isoformat(timespec="seconds"),
        root=str(root),
        title=title or f"Verification report — {root.name}",
        git=collect_git(root),
        proof=proof,
        coverage=coverage,
        traceability=traceability,
    )

    out.mkdir(parents=True, exist_ok=True)
    (out / "evidence.json").write_text(evidence.model_dump_json(indent=2))
    obligations = build_obligations(evidence)
    pages = emit_pages(evidence, obligations)
    write_sphinx_sources(pages, out / "src", evidence.title)
    typer.echo(f"evidence: {out / 'evidence.json'}")
    typer.echo(f"sources:  {out / 'src'}")

    if html:
        rc = build_html(out / "src", out / "html")
        if rc != 0:
            _fail("sphinx build failed (see warnings above)")
        typer.echo(f"html:     {out / 'html' / 'index.html'}")

    if pdf:
        rc = build_pdf(out / "src", out / "pdf")
        if rc != 0:
            _fail("sphinx pdf build failed (see warnings above)")
        typer.echo(f"pdf:      {out / 'pdf' / 'verification-report.pdf'}")

    review = sum(1 for o in obligations if o.status is ObligationStatus.review)
    typer.echo(f"obligations: {review} of {len(obligations)} need human review")


def main() -> None:
    """Entry point for the `vreport` executable."""
    app()


if __name__ == "__main__":
    main()
