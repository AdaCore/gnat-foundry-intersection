"""Phase-control requirement tests (FR-PH-*)."""
from __future__ import annotations

# @req FR-PH-01, FR-PH-02, FR-PH-03, FR-PH-04, FR-PH-05, FR-PH-06
from harness import QemuSession, requires

T_STARTUP_MS = 5_000
T_LT_G_MS    = 8_000
T_Y_MS       = 3_000
T_AR_MS      = 2_000
T_MIN_G_MS   = 7_000

NOMINAL_ORDER = [
    "STARTUP_FLASH",
    "NS_LT_GREEN", "NS_LT_YELLOW", "ALL_RED_1",
    "NS_THROUGH_GREEN", "NS_THROUGH_YELLOW", "ALL_RED_2",
    "EW_LT_GREEN", "EW_LT_YELLOW", "ALL_RED_3",
    "EW_THROUGH_GREEN", "EW_THROUGH_YELLOW", "ALL_RED_4",
]


@requires("FR-PH-01")
def test_fr_ph_01_nominal_phase_sequence_order():
    """FR-PH-01: the controller shall execute the phase sequence in the
    order listed in SRS § 2.3."""
    with QemuSession() as q:
        trs = q.wait_for_transitions(len(NOMINAL_ORDER), timeout_s=70.0)
        observed = [tr.phase for tr in trs[:len(NOMINAL_ORDER)]]
        assert observed == NOMINAL_ORDER, (
            f"nominal order mismatch:\n  expected {NOMINAL_ORDER}\n  "
            f"observed {observed}"
        )


@requires("FR-PH-02")
def test_fr_ph_02_skip_ns_left_when_no_demand():
    """FR-PH-02: the controller shall skip any left-turn phase for which
    no left-turn demand is registered at the moment that phase would
    begin.

    Clear NS left demand during STARTUP_FLASH; expect STARTUP_FLASH to
    advance directly to NS_THROUGH_GREEN (skipping NS_LT_GREEN and
    NS_LT_YELLOW and the intermediate ALL_RED)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("SET LT NS 0")
        # Walk past STARTUP_FLASH and confirm the next non-startup
        # *_LT_GREEN we see is EW's, not NS's.
        nt = q.wait_for_transition_to("NS_THROUGH_GREEN",
                                      timeout_s=T_STARTUP_MS / 1000 + 3)
        phases = [tr.phase for tr in q.log.transitions]
        assert "NS_LT_GREEN" not in phases, (
            f"NS_LT_GREEN should have been skipped, but saw: {phases}"
        )
        assert "NS_LT_YELLOW" not in phases


@requires("FR-PH-02")
def test_fr_ph_02_skip_ew_left_when_no_demand():
    """FR-PH-02 (EW axis): clearing EW left demand mid-cycle causes the
    EW left phase to be skipped at the moment it would begin."""
    with QemuSession() as q:
        # Clear EW demand before we ever reach EW_LT_GREEN.
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("SET LT EW 0")
        # Walk all the way to EW_THROUGH_GREEN — confirm no
        # EW_LT_GREEN/EW_LT_YELLOW appeared.
        q.wait_for_transition_to("EW_THROUGH_GREEN", timeout_s=50.0)
        phases = [tr.phase for tr in q.log.transitions]
        assert "EW_LT_GREEN" not in phases, (
            f"EW_LT_GREEN should have been skipped, saw: {phases}"
        )
        assert "EW_LT_YELLOW" not in phases


@requires("FR-PH-03")
def test_fr_ph_03_through_green_holds_at_least_T_min_g():
    """FR-PH-03: the controller shall hold each through-phase green for
    at least T_min_g (and no more than T_max_g, untested here because
    the upper bound is only exercised under continuous demand).

    Observable on wire: wall-clock interval between NS_THROUGH_GREEN
    entry and NS_THROUGH_YELLOW entry is at least T_min_g."""
    with QemuSession() as q:
        ns_green = q.wait_for_transition_to("NS_THROUGH_GREEN", timeout_s=25.0)
        ns_yellow = q.wait_for_transition_to("NS_THROUGH_YELLOW",
                                             timeout_s=T_MIN_G_MS / 1000 + 5)
        dur = ns_yellow.wall_ms - ns_green.wall_ms
        # T_min_g lower bound is hard; allow a small jitter window.
        assert dur >= T_MIN_G_MS - 50, (
            f"NS_THROUGH_GREEN held only {dur} ms (< T_min_g={T_MIN_G_MS})"
        )


@requires("FR-PH-04")
def test_fr_ph_04_green_to_red_only_via_yellow():
    """FR-PH-04: the controller shall transition from green to red on a
    vehicle phase only via an intermediate yellow interval of duration
    T_y.

    Observable on wire: between every *_GREEN and the next ALL_RED_*
    there is a *_YELLOW record, and that yellow lasts within
    [T_y - 50, T_y + 250] ms."""
    with QemuSession() as q:
        # Walk through to ALL_RED_2 — covers two green/yellow pairs
        # (NS_LT and NS_THROUGH).
        q.wait_for_transition_to("ALL_RED_2", timeout_s=30.0)
        seq = [tr.phase for tr in q.log.transitions]
        for i, ph in enumerate(seq[:-1]):
            if not ph.endswith("_GREEN") or ph == "STARTUP_FLASH":
                continue
            nxt = seq[i + 1]
            assert nxt.endswith("_YELLOW"), (
                f"green phase {ph} was not followed by a yellow "
                f"(got {nxt}) — FR-PH-04 violated"
            )
        # And the yellow durations are correct.
        for i, tr in enumerate(q.log.transitions[:-1]):
            if not tr.phase.endswith("_YELLOW"):
                continue
            dur = q.log.transitions[i + 1].wall_ms - tr.wall_ms
            assert T_Y_MS - 50 <= dur <= T_Y_MS + 250, (
                f"yellow {tr.phase} lasted {dur} ms (expected "
                f"{T_Y_MS} ±50/+250)"
            )


@requires("FR-PH-05", "FR-PH-06")
def test_fr_ph_05_06_all_red_clearance_between_vehicle_phases():
    """FR-PH-05: the controller shall apply an all-red clearance of
    duration T_ar between every consecutive pair of vehicle phases.

    FR-PH-06 (also covered): the controller shall not begin a new phase
    before the all-red clearance of the previous phase has elapsed
    (i.e. the ALL_RED phase actually holds for at least T_ar)."""
    with QemuSession() as q:
        # Walk through both NS all-reds (1 and 2). EW_LT_GREEN entry
        # is at wall ~30 s under the nominal cycle; allow margin.
        q.wait_for_transition_to("EW_LT_GREEN", timeout_s=35.0)
        for i, tr in enumerate(q.log.transitions[:-1]):
            if not tr.phase.startswith("ALL_RED"):
                continue
            dur = q.log.transitions[i + 1].wall_ms - tr.wall_ms
            assert T_AR_MS - 50 <= dur <= T_AR_MS + 250, (
                f"{tr.phase} clearance lasted {dur} ms (expected "
                f"{T_AR_MS} ±50/+250) — FR-PH-05/06 violated"
            )
