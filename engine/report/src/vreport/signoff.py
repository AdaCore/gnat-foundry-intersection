"""
Read and write the human sign-off record.

Three review obligations rest on judgement no tool can supply: the waivers
excusing CONOPS leaves from HLR coverage, the derived HLR statements that have
no CONOPS parent, and the CONOPS itself. ``requirements/signoffs.yaml`` records
that a human read each of them, keyed to a digest of the text they read. Edit
the text and the sign-off lapses, so the obligation re-opens naming exactly what
moved -- which is the point: against an otherwise green baseline, a change
nobody has reviewed is the only thing that shows.

The record is evidence of review, not an attestation anything enforces:
whatever can write the repository can write this file. Its worth is that a
change to it is conspicuous in a diff.

The digest subject is built here, once, and the report renders that same string
-- so what a sign-off covers is exactly what the reader sees.
"""

from __future__ import annotations

import hashlib
from typing import TYPE_CHECKING, Any

import yaml

from vreport.model import (
    ArtifactParseError,
    Signoff,
    SignoffItem,
    SignoffState,
    SignoffStatus,
)

if TYPE_CHECKING:
    from collections.abc import Iterable, Sequence
    from pathlib import Path

    from vreport.model import DerivedRequirement, TraceabilityEvidence, Waiver

DIGEST_PREFIX = "sha256:"

CONOPS_ITEM = "conops"
CONOPS_PATH = "requirements/conops.md"


def digest_of(text: str) -> str:
    """Digest the reviewed text, prefixed with the algorithm that produced it."""
    return DIGEST_PREFIX + hashlib.sha256(text.encode("utf-8")).hexdigest()


def waiver_item(leaf: str) -> str:
    """Build the sign-off item id of the waiver on one CONOPS leaf."""
    return f"waiver:{leaf}"


def derived_item(ident: str) -> str:
    """Build the sign-off item id of one derived HLR statement."""
    return f"derived:{ident}"


def waiver_subject(waiver: Waiver) -> str:
    """Build the text a waiver's sign-off covers: its leaf and the reason given."""
    return f"CONOPS §{waiver.leaf} — {waiver.reason}"


def derived_subject(derived: DerivedRequirement) -> str:
    """Build the text a derived requirement's sign-off covers: its id and statement."""
    return f"{derived.ident} — {derived.text}"


def item_sort_key(item: str) -> tuple[int, tuple[int, ...], str]:
    """
    Order items so the record reads in chain order and diffs stay minimal.

    The CONOPS first, then the waivers by leaf number (numerically, so 3.10
    follows 3.9), then the derived requirements by id.
    """
    kind, _, rest = item.partition(":")
    rank = {CONOPS_ITEM: 0, "waiver": 1, "derived": 2}.get(kind, 3)
    parts = rest.split(".")
    numeric = tuple(int(p) for p in parts) if all(p.isdigit() for p in parts) else ()
    return (rank, numeric, rest)


def enumerate_items(t: TraceabilityEvidence) -> list[SignoffItem]:
    """
    Every item a human can sign off, in record order, with the digest of its text now.

    A digest of None means the text itself is missing, so there is nothing to
    sign: only the CONOPS can be in that state, the waivers and derived
    requirements being enumerated from the files that carry them.
    """
    items = [SignoffItem(item=CONOPS_ITEM, subject=CONOPS_PATH, digest=t.conops_digest)]
    items += [
        SignoffItem(
            item=waiver_item(w.leaf),
            subject=waiver_subject(w),
            digest=digest_of(waiver_subject(w)),
        )
        for w in t.waivers
    ]
    items += [
        SignoffItem(
            item=derived_item(d.ident),
            subject=derived_subject(d),
            digest=digest_of(derived_subject(d)),
        )
        for d in t.derived
    ]
    return sorted(items, key=lambda i: item_sort_key(i.item))


def load_signoffs(path: Path) -> tuple[list[Signoff], bool]:
    """
    Parse the sign-off record at `path`, returning its entries and whether it exists.

    An absent file is not an error: the mechanism is opt-in, and a project
    without the file gets the obligations it had before sign-offs existed.
    """
    if not path.is_file():
        return [], False
    try:
        data: dict[str, Any] = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        raise ArtifactParseError(path, str(exc)) from exc
    if not isinstance(data, dict):
        raise ArtifactParseError(path, "top level must be an object")
    entries = data.get("signoffs") or []
    if not isinstance(entries, list):
        raise ArtifactParseError(path, "`signoffs` must be a list")
    signoffs: list[Signoff] = []
    for entry in entries:
        if not isinstance(entry, dict):
            raise ArtifactParseError(path, "each `signoffs` entry must be an object")
        try:
            signoffs.append(Signoff.model_validate(entry))
        except ValueError as exc:
            raise ArtifactParseError(path, str(exc)) from exc
    return signoffs, True


def resolve(signoffs: Iterable[Signoff], item: str, digest: str | None) -> SignoffState:
    """
    State the sign-off record leaves one item in.

    `digest` is None when the reviewed text itself is missing, which is neither
    signed nor unsigned: nothing can be said about it.
    """
    match = next((s for s in signoffs if s.item == item), None)
    if match is None:
        status = SignoffStatus.unsigned
    elif digest is None:
        status = SignoffStatus.unknown
    elif match.digest == digest:
        status = SignoffStatus.signed
    else:
        status = SignoffStatus.lapsed
    return SignoffState(item=item, status=status, signoff=match)


def all_signed(states: Sequence[SignoffState]) -> bool:
    """Whether every one of these items carries a current sign-off."""
    return all(s.status is SignoffStatus.signed for s in states)


def outstanding_note(states: Sequence[SignoffState]) -> str:
    """Name what is not signed, as a phrase for an obligation title ("" if all are)."""
    counts = [
        (label, sum(1 for s in states if s.status is status))
        for label, status in (
            ("not signed off", SignoffStatus.unsigned),
            ("lapsed", SignoffStatus.lapsed),
            ("unknown", SignoffStatus.unknown),
        )
    ]
    return ", ".join(f"{n} {label}" for label, n in counts if n)


def render_signoffs(signoffs: Iterable[Signoff]) -> str:
    """Serialize the record, header comment and all, ready to write."""
    entries = sorted(signoffs, key=lambda s: item_sort_key(s.item))
    body = yaml.dump(
        {"signoffs": [s.model_dump(exclude_defaults=True) for s in entries]},
        Dumper=_IndentedDumper,
        sort_keys=False,
        allow_unicode=True,
        width=88,
    )
    return _HEADER + body


class _IndentedDumper(yaml.SafeDumper):
    """Indent block sequences under their key, as the hand-written artifacts do."""

    def increase_indent(self, flow: bool = False, indentless: bool = False) -> None:  # noqa: ARG002, FBT001, FBT002
        """Never emit an indentless sequence."""
        super().increase_indent(flow=flow, indentless=False)


# Written verbatim at the head of every record this module renders, so the file
# carries its own prohibition -- and so a re-stamp restores it rather than
# dropping a hand-edited one.
_HEADER = """\
# Recorded human review of the items that cannot be checked automatically.
#
# Entries are protected by a digest. Agents MAY NOT recompute the digest
# automatically.
#
# Commentary belongs in an entry's `note:`, which a re-stamp preserves; comments
# written between entries do not survive one.
"""
