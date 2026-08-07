"""
Integration test for the `--@covers` check extraction of ``engine/ada_tracer``.

Every other test in this suite fabricates the inventory JSON, which is the right
trade for testing `reqs` -- but it leaves the producer side of the schema
untested: a token/AST association regression in the tracer would emit an empty
or incomplete ``checks`` array and every fabricated-inventory test would still
pass. So this one runs the real binary over an Ada fixture and checks what comes
out, end to end: the tracer's extraction, the consumer's schema, and the
`CheckSet` the PROOF / STATIC layers are built from.

The fixture (``fixtures/ada_tracer/checks.ads``) carries one instance of each
tag shape ``docs/README.md`` documents -- a tagged pragma, a tag directly above
an aspect association, a tag above the ``with`` that opens a one-line aspect
list, a compiler-checked aspect, ``none:``, a bare (broken) tag -- plus the
untagged constructs that must *not* be reported.

The tracer costs a Libadalang build, so the module skips when the binary is
absent (``make test-reqs-engine`` on a machine with no Ada toolchain).
``make test-tracer`` builds it first and passes ``ADA_TRACER``, which turns the
skip into a failure: that target is the one that must not pass vacuously.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

import pytest

from reqs.ada_checks import CheckSet
from reqs.code_inventory import SCHEMA_VERSION, load

if TYPE_CHECKING:
    from reqs.code_inventory import Inventory

FIXTURE = Path(__file__).parent / "fixtures" / "ada_tracer" / "checks.ads"

# Where `make build-tracer` leaves the binary.
DEFAULT_TRACER = Path(__file__).parents[2] / "ada_tracer" / "bin" / "ada_tracer"

# The anchors `requirements/trace_chain.yaml` gives the two ada-checks layers.
PROOF_ANCHORS = ["aspect:Post"]
STATIC_ANCHORS = ["pragma:Compile_Time_Error", "aspect:No_Return"]

# What the tracer must report for the fixture: (kind, name, line, payloads), in
# the emitted order. The lines are the *construct's*, not the tag's, and the
# payloads are raw -- splitting them is the consumer's job.
EXPECTED_CHECKS = [
    ("pragma", "Compile_Time_Error", 16, ["llr_1_checks.1"]),
    ("aspect", "Post", 33, ["llr_1_checks.2"]),
    ("aspect", "Post", 40, ["llr_1_checks.3"]),
    ("aspect", "Post", 49, ["llr_1_checks.4, llr_1_checks.5", "llr_1_checks.6"]),
    ("aspect", "No_Return", 58, ["llr_1_checks.7"]),
    ("aspect", "Pre", 65, ["none: guards an implementation detail"]),
    ("aspect", "Pre", 74, [""]),
]


def _tracer() -> Path:
    """Return the tracer binary to exercise; skip the module when there is none built."""
    override = os.environ.get("ADA_TRACER")
    if override:
        # Explicitly asked for: a missing binary is a broken invocation, not a
        # reason to pass without testing anything.
        if not Path(override).is_file():
            pytest.fail(f"ADA_TRACER is {override!r}, which is not a file")
        return Path(override)
    if not DEFAULT_TRACER.is_file():
        pytest.skip(f"{DEFAULT_TRACER} is not built; run `make build-tracer`")
    return DEFAULT_TRACER


def _line_of(needle: str) -> int:
    """Return the 1-based fixture line containing `needle`, which must occur exactly once."""
    text = FIXTURE.read_text(encoding="utf-8")
    lines = [n for n, line in enumerate(text.splitlines(), start=1) if needle in line]
    assert len(lines) == 1, f"{needle!r} occurs on {lines} of the fixture, expected one line"
    return lines[0]


@pytest.fixture(scope="module")
def inventory(tmp_path_factory: pytest.TempPathFactory) -> Inventory:
    """Run the tracer over the fixture once and load the result as the checks do."""
    output = tmp_path_factory.mktemp("ada_tracer") / "inventory.json"
    run = subprocess.run(  # noqa: S603  # the binary is ours, the paths are the fixture's
        [
            str(_tracer()),
            str(FIXTURE),
            "--base-dir",
            str(FIXTURE.parent),
            "-o",
            str(output),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    assert run.returncode == 0, f"the tracer failed:\n{run.stdout}\n{run.stderr}"
    loaded, diags = load(output)
    assert diags == [], f"the emitted inventory does not load: {diags}"
    return loaded


def test_the_emitted_schema_version_is_the_one_the_checks_read(inventory: Inventory) -> None:
    """Producer and consumer agree on the schema; a bump on one side is loud, not silent."""
    assert (inventory.schema_version, inventory.tool) == (SCHEMA_VERSION, "ada_tracer")


def test_every_tagged_construct_is_reported_once_and_exactly(inventory: Inventory) -> None:
    """The whole `checks` array of the fixture, in order: kinds, names, lines, payloads."""
    assert [
        (c.kind, c.name, c.location.line, c.covers) for c in inventory.checks
    ] == EXPECTED_CHECKS


def test_untagged_constructs_are_not_checks(inventory: Inventory) -> None:
    """Tagging is opt-in: an untagged pragma or contract is not evidence of anything."""
    lines = {c.location.line for c in inventory.checks}
    assert _line_of("T_WALK must be positive") not in lines
    assert _line_of("Doubled'Result") not in lines


def test_check_locations_are_relative_to_the_base_dir(inventory: Inventory) -> None:
    """`--base-dir` is what keeps a check's node id (`<file>:<line>`) repo-relative."""
    assert {c.location.file for c in inventory.checks} == {"checks.ads"}


def test_checks_are_sorted_by_source_position(inventory: Inventory) -> None:
    """The schema's stability claim: two runs over unchanged sources diff cleanly."""
    positions = [(c.location.file, c.location.line) for c in inventory.checks]
    assert positions == sorted(positions)


def test_the_proof_anchors_select_the_tagged_contracts(inventory: Inventory) -> None:
    """The `PROOF` layer reads the tagged `Post` aspects, and unions their payloads."""
    checkset, diags = CheckSet.from_inventory(inventory, FIXTURE, PROOF_ANCHORS)
    assert diags == []
    assert {nid: node.refs for nid, node in checkset.all_statements()} == {
        "checks.ads:33": ["llr_1_checks.2"],
        "checks.ads:40": ["llr_1_checks.3"],
        "checks.ads:49": ["llr_1_checks.4", "llr_1_checks.5", "llr_1_checks.6"],
    }


def test_the_static_anchors_select_the_pragma_and_the_no_return(inventory: Inventory) -> None:
    """The `STATIC` layer reads the tagged `Compile_Time_Error` and `No_Return`."""
    checkset, diags = CheckSet.from_inventory(inventory, FIXTURE, STATIC_ANCHORS)
    assert diags == []
    assert {nid: node.refs for nid, node in checkset.all_statements()} == {
        "checks.ads:16": ["llr_1_checks.1"],
        "checks.ads:58": ["llr_1_checks.7"],
    }


def test_a_covers_none_check_reaches_the_consumer_as_derived(inventory: Inventory) -> None:
    """`none:` survives the round trip, so a check outside requirement scope says so."""
    checkset, _diags = CheckSet.from_inventory(inventory, FIXTURE, ["aspect:Pre"])
    assert checkset.nodes["checks.ads:65"].is_derived


def test_a_bare_covers_tag_reaches_the_consumer_to_be_diagnosed(inventory: Inventory) -> None:
    """A broken tag is emitted with an empty payload -- the shape E-TRACE-CHECK-EMPTY reads."""
    anchors = PROOF_ANCHORS + STATIC_ANCHORS  # the union the trace engine checks against
    checkset, _diags = CheckSet.from_inventory(inventory, FIXTURE, anchors)
    assert [c.location.line for c in checkset.malformed()] == [74]
    # The broken tag sits on a `Pre`, which no anchor accepts, and it cites no id:
    # without the payload check above, neither report names it and it vanishes.
    assert checkset.unmatched(anchors) == []
