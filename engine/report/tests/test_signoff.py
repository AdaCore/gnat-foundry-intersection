"""Tests for the sign-off record: what it covers, and when it lapses."""

from __future__ import annotations

from typing import TYPE_CHECKING

import pytest

from vreport.model import ArtifactParseError, DerivedRequirement, Signoff, SignoffStatus, Waiver
from vreport.signoff import (
    CONOPS_ITEM,
    all_signed,
    derived_subject,
    digest_of,
    enumerate_items,
    item_sort_key,
    load_signoffs,
    outstanding_note,
    render_signoffs,
    resolve,
    waiver_subject,
)
from vreport.traceability import collect_judgement_items, signoffs_path

if TYPE_CHECKING:
    from pathlib import Path

_WAIVER = Waiver(leaf="1.1", reason="Physical site assumption.")
_DERIVED = DerivedRequirement(ident="hlr_3_timing.8", text="Derived text.")


def _signoff(item: str, digest: str) -> Signoff:
    return Signoff(item=item, digest=digest, by="Reviewer", date="2026-08-21")


def test_digest_names_its_algorithm() -> None:
    """The digest carries the algorithm that produced it, so a change of it is visible."""
    assert digest_of("x").startswith("sha256:")
    assert digest_of("x") != digest_of("y")


def test_subject_is_the_text_the_report_shows() -> None:
    """What a sign-off covers is the leaf and reason a reader sees, nothing else."""
    assert waiver_subject(_WAIVER) == "CONOPS §1.1 — Physical site assumption."
    assert derived_subject(_DERIVED) == "hlr_3_timing.8 — Derived text."


def test_resolve_reports_signed_lapsed_and_unsigned() -> None:
    """A sign-off holds only against the digest it was taken over."""
    entry = _signoff("waiver:1.1", digest_of(waiver_subject(_WAIVER)))
    assert resolve([entry], "waiver:1.1", entry.digest).status is SignoffStatus.signed
    assert resolve([entry], "waiver:1.1", digest_of("edited")).status is SignoffStatus.lapsed
    assert resolve([], "waiver:1.1", entry.digest).status is SignoffStatus.unsigned
    # Signed, but the reviewed text has gone missing: neither claim can be made.
    assert resolve([entry], "waiver:1.1", None).status is SignoffStatus.unknown


def test_summaries_name_what_is_outstanding() -> None:
    """The title clause counts each way an item can fail to be signed."""
    states = [
        resolve([], "a", digest_of("a")),
        resolve([_signoff("b", digest_of("stale"))], "b", digest_of("b")),
    ]
    assert not all_signed(states)
    assert outstanding_note(states) == "1 not signed off, 1 lapsed"
    signed = [resolve([_signoff("a", digest_of("a"))], "a", digest_of("a"))]
    assert all_signed(signed)
    assert outstanding_note(signed) == ""


def test_items_sort_in_chain_order() -> None:
    """The CONOPS leads, then waivers by leaf number, then derived requirements."""
    items = ["derived:hlr_1.2", "waiver:3.10", "waiver:3.9", CONOPS_ITEM, "waiver:1.1"]
    assert sorted(items, key=item_sort_key) == [
        CONOPS_ITEM,
        "waiver:1.1",
        "waiver:3.9",
        "waiver:3.10",
        "derived:hlr_1.2",
    ]


def test_absent_record_is_not_an_error(tmp_path: Path) -> None:
    """The mechanism is opt-in: a project without the file simply has no sign-offs."""
    signoffs, found = load_signoffs(tmp_path / "signoffs.yaml")
    assert (signoffs, found) == ([], False)


def test_malformed_record_names_the_file(tmp_path: Path) -> None:
    """A broken record aborts rather than silently reading as "nothing signed"."""
    path = tmp_path / "signoffs.yaml"
    for text in (
        "signoffs: [\n",  # not YAML at all
        "- a\n",  # top level is a list
        "signoffs: 3\n",  # `signoffs` is not a list
        "signoffs:\n  - a string\n",  # an entry is not an object
        "signoffs:\n  - item: conops\n",  # an entry is missing its fields
    ):
        path.write_text(text)
        with pytest.raises(ArtifactParseError):
            load_signoffs(path)


def test_render_round_trips_through_the_loader(tmp_path: Path) -> None:
    """What the stamping command writes is what the collector reads back."""
    entries = [
        Signoff(item="waiver:1.1", digest=digest_of("a"), by="R", date="2026-08-21", note="why"),
        Signoff(item=CONOPS_ITEM, digest=digest_of("b"), by="R", date="2026-08-21"),
    ]
    path = tmp_path / "signoffs.yaml"
    text = render_signoffs(entries)
    path.write_text(text)
    assert text.startswith("#")  # the header explaining who may write it survives
    loaded, found = load_signoffs(path)
    assert found
    # Written in record order, whatever order they were stamped in.
    assert [s.item for s in loaded] == [CONOPS_ITEM, "waiver:1.1"]
    assert {s.note for s in loaded} == {"", "why"}


def test_enumerate_items_covers_every_judgement_item(tmp_path: Path) -> None:
    """Every waiver, every derived statement, and the CONOPS are signable."""
    (tmp_path / "requirements").mkdir()
    (tmp_path / "requirements" / "conops.md").write_text("- **1.1 ✔** A leaf.\n")
    (tmp_path / "requirements" / "trace_waivers.yaml").write_text(
        'waivers:\n  - leaf: "1.1"\n    reason: Physical site assumption.\n'
    )
    (tmp_path / "requirements" / "hlr").mkdir()
    (tmp_path / "requirements" / "hlr" / "hlr_x.yaml").write_text(
        "description:\n  4:\n    text: Derived text.\n    derived: true\n"
    )
    items = enumerate_items(collect_judgement_items(tmp_path))
    assert [i.item for i in items] == [CONOPS_ITEM, "waiver:1.1", "derived:hlr_x.4"]
    assert all(i.digest is not None for i in items)
    assert signoffs_path(tmp_path).name == "signoffs.yaml"


def test_missing_conops_leaves_nothing_to_sign(tmp_path: Path) -> None:
    """Without the document there is no digest, so no sign-off can be claimed over it."""
    (tmp_path / "requirements").mkdir()
    items = enumerate_items(collect_judgement_items(tmp_path))
    assert [(i.item, i.digest) for i in items] == [(CONOPS_ITEM, None)]
