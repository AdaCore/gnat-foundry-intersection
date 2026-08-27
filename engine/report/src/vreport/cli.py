"""
`vreport` command-line interface.

    vreport generate --root DIR --out DIR   # collect evidence, render the report
    vreport signoff --root DIR               # human-judgement items and their sign-off state
    vreport signoff --root DIR --item ITEM   # record that a human reviewed one of them

Inputs are the artifacts left by the verification tools (see README.md);
outputs are `evidence.json`, the generated MyST sources, and the HTML report.
"""

from __future__ import annotations

from datetime import UTC, date, datetime
from pathlib import Path
from typing import NoReturn

import typer

from vreport.build import (
    PDF_NAME,
    build_html,
    build_pdf,
    copy_requirement_pages,
    write_sphinx_sources,
)
from vreport.emit import REQUIREMENTS_SUBDIR, emit_pages
from vreport.gnatcov import collect_coverage
from vreport.gnatprove import collect_proof
from vreport.inventory import collect_inventory, default_inventory_path
from vreport.model import (
    ArtifactParseError,
    Evidence,
    MissingArtifactsError,
    ObligationStatus,
    Signoff,
    SignoffItem,
    SignoffState,
    SignoffStatus,
)
from vreport.obligations import build_obligations
from vreport.provenance import collect_git, git_user_name
from vreport.requirements import PAGES_DIR, collect_requirements
from vreport.signoff import enumerate_items, render_signoffs, resolve
from vreport.traceability import collect_judgement_items, collect_traceability, signoffs_path

app = typer.Typer(help="Verification-report generator.", no_args_is_help=True)


@app.callback()
def _callback() -> None:
    """Keep every operation an explicit subcommand."""


_ROOT = typer.Option(Path(), "--root", help="Project root the evidence describes.")
_OUT = typer.Option(..., "--out", help="Output directory for the report.")
_PROOF_DIR = typer.Option(
    None, "--proof-dir", help="gnatprove artifact dir (default: ROOT/obj/development/gnatprove)."
)
_COVERAGE_DIR = typer.Option(
    None, "--coverage-dir", help="gnatcov XML dir (default: ROOT/reports/coverage/xml)."
)
_TRACE_REPORT = typer.Option(
    None,
    "--trace-report",
    help="Trace-report JSON (default: ROOT/reports/trace/trace_report.json).",
)
_CODE_INVENTORY = typer.Option(
    None,
    "--code-inventory",
    help="Ada tracer inventory (default: ROOT/obj/analysis/code_inventory.json).",
)
_REQUIREMENTS_DIR = typer.Option(
    None,
    "--requirements-dir",
    help="Rendered requirement document (default: ROOT/reports/requirements).",
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
    trace_report: Path | None = _TRACE_REPORT,
    code_inventory: Path | None = _CODE_INVENTORY,
    requirements_dir: Path | None = _REQUIREMENTS_DIR,
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
        traceability = collect_traceability(root, trace_report)
    except (MissingArtifactsError, ArtifactParseError) as exc:
        _fail(str(exc), hint="make trace-report")
    try:
        # Optional input: without it the matrices simply carry no links.
        requirements = collect_requirements(root, requirements_dir)
    except (MissingArtifactsError, ArtifactParseError) as exc:
        _fail(str(exc), hint="make requirements-doc")
    try:
        inventory = collect_inventory(code_inventory or default_inventory_path(root))
    except MissingArtifactsError:
        # Optional input: without it the generics table falls back to the
        # generic *units* gnatprove reports, which cannot see a generic nested
        # in an ordinary package.
        inventory = None
    except ArtifactParseError as exc:
        _fail(str(exc), hint="make code-inventory")

    evidence = Evidence(
        generated_at=datetime.now(tz=UTC).isoformat(timespec="seconds"),
        root=str(root),
        title=title or f"Verification report — {root.name}",
        git=collect_git(root),
        proof=proof,
        coverage=coverage,
        traceability=traceability,
        requirements=requirements,
        inventory=inventory,
    )

    out.mkdir(parents=True, exist_ok=True)
    (out / "evidence.json").write_text(evidence.model_dump_json(indent=2))
    obligations = build_obligations(evidence)
    pages = emit_pages(evidence, obligations)
    write_sphinx_sources(pages, out / "src", evidence.title)
    if requirements is not None:
        copy_requirement_pages(
            Path(requirements.source_dir) / PAGES_DIR, out / "src", REQUIREMENTS_SUBDIR
        )
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
        typer.echo(f"pdf:      {out / 'pdf' / f'{PDF_NAME}.pdf'}")

    review = sum(1 for o in obligations if o.status is ObligationStatus.review)
    typer.echo(f"obligations: {review} of {len(obligations)} need human review")


_SIGNOFF_ITEM = typer.Option(
    None, "--item", help="Item to stamp (`conops`, `waiver:<leaf>`, `derived:<id>`)."
)
_SIGNOFF_ALL = typer.Option(
    False, "--all", help="Stamp every item that carries no current sign-off."
)
_SIGNOFF_BY = typer.Option(None, "--by", help="Reviewer (default: git's `user.name`).")
_SIGNOFF_DATE = typer.Option(
    None, "--date", help="Date of the review, YYYY-MM-DD (default: today)."
)
_SIGNOFF_NOTE = typer.Option(
    None, "--note", help="What the review established (omit to keep an entry's existing note)."
)


_STATUS_LABEL = {
    SignoffStatus.signed: "signed",
    SignoffStatus.lapsed: "LAPSED",
    SignoffStatus.unsigned: "unsigned",
    SignoffStatus.unknown: "text missing",
}


@app.command()
def signoff(
    root: Path = _ROOT,
    item: str | None = _SIGNOFF_ITEM,
    stamp_all: bool = _SIGNOFF_ALL,
    by: str | None = _SIGNOFF_BY,
    reviewed: str | None = _SIGNOFF_DATE,
    note: str | None = _SIGNOFF_NOTE,
) -> None:
    """
    Show the human-judgement items and their sign-off state, or record a review.

    Recording one asserts that a human read the item's text as it now stands.
    Nothing enforces that, so this is the human's own command: no automated task
    may run it on their behalf.
    """
    root = root.resolve()
    try:
        judgement = collect_judgement_items(root)
    except ArtifactParseError as exc:
        _fail(str(exc))
    items = enumerate_items(judgement)
    states = {i.item: resolve(judgement.signoffs, i.item, i.digest) for i in items}

    if item is None and not stamp_all:
        _list_signoffs(items, states)
        return
    if item is not None and stamp_all:
        _fail("--item and --all are mutually exclusive")

    known = {i.item: i for i in items}
    if item is not None and item not in known:
        _fail(f"no such item: {item}", hint="vreport signoff")
    targets = (
        [known[item]]
        if item is not None
        else [i for i in items if states[i.item].status is not SignoffStatus.signed]
    )
    blocked = [t for t in targets if t.digest is None]
    if blocked:
        _fail(f"nothing to sign for {blocked[0].item}: its text is missing")
    targets = [t for t in targets if t.digest is not None]
    if not targets:
        typer.echo("every item already carries a current sign-off; nothing to do")
        return

    reviewer = by or git_user_name(root)
    if not reviewer:
        _fail("no reviewer: pass --by, or set git's `user.name`")
    try:
        reviewed_on = date.fromisoformat(reviewed) if reviewed else datetime.now(tz=UTC).date()
    except ValueError:
        _fail(f"--date must be a calendar date as YYYY-MM-DD, not {reviewed!r}")
    stamped = {t.item for t in targets}
    kept = [s for s in judgement.signoffs if s.item not in stamped]
    # A re-stamp must not silently discard commentary the reviewer wrote: an
    # unpassed --note carries the previous one over, and `--note ""` clears it.
    previous = {s.item: s.note for s in judgement.signoffs}
    written = [
        Signoff(
            item=t.item,
            digest=t.digest or "",
            by=reviewer,
            date=reviewed_on,
            note=previous.get(t.item, "") if note is None else note,
        )
        for t in targets
    ]
    path = signoffs_path(root)
    path.write_text(render_signoffs([*kept, *written]), encoding="utf-8")
    for entry in written:
        typer.echo(f"signed off {entry.item} ({entry.by}, {entry.date.isoformat()})")
    typer.echo(f"record:  {path}")


def _list_signoffs(items: list[SignoffItem], states: dict[str, SignoffState]) -> None:
    """Print every item with its state, widest-first, and what is outstanding."""
    width = max((len(i.item) for i in items), default=0)
    for i in items:
        state = states[i.item]
        stamp = (
            f" — {state.signoff.by}, {state.signoff.date.isoformat()}"
            if state.signoff is not None and state.status is SignoffStatus.signed
            else ""
        )
        typer.echo(f"{i.item:<{width}}  {_STATUS_LABEL[state.status]}{stamp}")
    open_items = [i.item for i in items if states[i.item].status is not SignoffStatus.signed]
    typer.echo("")
    if open_items:
        typer.secho(
            f"{len(open_items)} of {len(items)} items carry no current sign-off",
            fg=typer.colors.YELLOW,
        )
        typer.echo("review each, then: vreport signoff --item <item>")
    else:
        typer.echo(f"all {len(items)} items carry a current sign-off")


def main() -> None:
    """Entry point for the `vreport` executable."""
    app()


if __name__ == "__main__":
    main()
