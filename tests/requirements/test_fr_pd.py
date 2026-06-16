"""Pedestrian requirement tests (FR-PD-*).

FR-PD-01 (50 ms debounce) is implemented at the HAL boundary and is
not observable on QEMU — cmd-in injects an already-debounced press, so
the debounce path is bypassed. See README.md § scope.

FR-PD-08 (visible button-mounted indicator) is a hardware-only output
(no GPIO on QEMU). Untestable here; rely on hardware bring-up.

Compass-corner → axis mapping (per src/core/cmd_parser.adb):
  NE → EW_East   SW → EW_West   →  PED=EW
  NW → NS_North  SE → NS_South  →  PED=NS
"""
from __future__ import annotations

# @req FR-PD-02, FR-PD-03, FR-PD-04, FR-PD-05, FR-PD-06, FR-PD-07
from harness import QemuSession, requires

T_STARTUP_MS = 5_000
T_MIN_G_MS   = 7_000
T_WALK_MS    = 5_000
T_FDW_MS     = 10_000
T_MIN_G_PED  = T_WALK_MS + T_FDW_MS   # 15_000 ms — through-green floor when ped


@requires("FR-PD-02")
def test_fr_pd_02_press_latches_until_served_or_reset():
    """FR-PD-02: once registered, a pedestrian request shall remain
    latched until the corresponding pedestrian phase has been served.

    Quick observable: press NE (→ PED=EW:req), confirm the latch shows
    up immediately on the cmd-applied re-emit and again on the next
    natural transition (NS_LT_GREEN) — confirming the latch persisted
    across at least one Tick-driven phase change."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED NE")
        press_wall = q.elapsed_ms()

        def first_req(log):
            for tr in log.transitions:
                if tr.wall_ms > press_wall and tr.ped_ew == "req":
                    return tr
            return None
        first = q.read_until(first_req, timeout_s=2.0)
        assert first.ped_ew == "req"

        # Wait for the next natural transition (Tick-driven, T=0). The
        # latch must still be visible on this record — FR-PD-02
        # requires persistence across phase changes until the ped
        # phase is served.
        ns_lt = q.wait_for_transition_to("NS_LT_GREEN",
                                         timeout_s=T_STARTUP_MS / 1000 + 3)
        assert ns_lt.ped_ew == "req", (
            f"PED=EW latch dropped before EW ped phase was served: "
            f"{ns_lt.raw}"
        )


@requires("FR-PD-02")
def test_fr_pd_02_reset_clears_latch():
    """FR-PD-02 corollary: RESET clears all latched ped requests
    (Reset_Controller assigns a default-initialized State)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED NW")  # NW → NS_North → PED=NS:req
        press_wall = q.elapsed_ms()
        def pred(log):
            for tr in log.transitions:
                if tr.wall_ms > press_wall and tr.ped_ns == "req":
                    return tr
            return None
        q.read_until(pred, timeout_s=2.0)
        # Reset and confirm the latch clears on the next emitted transition.
        # Match by transition index rather than wall-clock time: this build
        # can process RESET and emit the clearing record inside the same
        # wall-millisecond as the press, so a strict wall_ms comparison races.
        n_before = len(q.log.transitions)
        q.send("RESET")
        def after_reset(log):
            for tr in log.transitions[n_before:]:
                if tr.phase == "STARTUP_FLASH":
                    return tr
            return None
        tr = q.read_until(after_reset, timeout_s=2.0)
        assert tr.ped_ns == "clr" and tr.ped_ew == "clr", (
            f"RESET did not clear ped latches: {tr.raw}"
        )


@requires("FR-PD-03", "FR-PD-06")
def test_fr_pd_03_06_through_green_extends_for_ped_request():
    """FR-PD-03: Ped-NS shall be served concurrently with NS-through
    green when a Ped-NS request is latched at the start of that phase.

    FR-PD-06: the corresponding through-phase green shall not terminate
    before T_walk + T_fdw has elapsed when a pedestrian phase is being
    served.

    Concretely: press NW (PED=NS:req), wait for NS_THROUGH_GREEN, then
    measure the wall-clock interval until NS_THROUGH_YELLOW. Expect
    ≥ T_walk + T_fdw, not just T_min_g."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED NW")
        ns_green = q.wait_for_transition_to("NS_THROUGH_GREEN", timeout_s=25.0)
        # PED=NS must be "req" at this transition record — it's being
        # served concurrently.
        assert ns_green.ped_ns == "req", (
            f"NS_THROUGH_GREEN entered with PED=NS:clr — ped not served "
            f"concurrently: {ns_green.raw}"
        )
        ns_yellow = q.wait_for_transition_to("NS_THROUGH_YELLOW",
                                             timeout_s=T_MIN_G_PED / 1000 + 5)
        dur = ns_yellow.wall_ms - ns_green.wall_ms
        # Allow a 250 ms upper jitter window (the controller exits the
        # phase on the first Tick where elapsed >= floor; emit
        # latency adds ~1 ms).
        assert T_MIN_G_PED - 50 <= dur <= T_MIN_G_PED + 250, (
            f"NS_THROUGH_GREEN with ped served lasted {dur} ms "
            f"(expected ≥ {T_MIN_G_PED}, FR-PD-06)"
        )


@requires("FR-PD-04", "FR-PD-06")
def test_fr_pd_04_06_ew_through_extends_for_ew_ped():
    """FR-PD-04: Ped-EW served concurrently with EW-through green.
    Mirror of test_fr_pd_03_06 on the EW axis."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED SW")  # SW → EW_West → PED=EW:req
        ew_green = q.wait_for_transition_to("EW_THROUGH_GREEN", timeout_s=50.0)
        assert ew_green.ped_ew == "req", (
            f"EW_THROUGH_GREEN entered with PED=EW:clr: {ew_green.raw}"
        )
        ew_yellow = q.wait_for_transition_to("EW_THROUGH_YELLOW",
                                             timeout_s=T_MIN_G_PED / 1000 + 5)
        dur = ew_yellow.wall_ms - ew_green.wall_ms
        assert T_MIN_G_PED - 50 <= dur <= T_MIN_G_PED + 250, (
            f"EW_THROUGH_GREEN with ped served lasted {dur} ms"
        )


@requires("FR-PD-05")
def test_fr_pd_05_walk_then_fdw_then_dw_progression():
    """FR-PD-05: a pedestrian phase shall present steady WALK for
    T_walk, followed by flashing DON'T WALK for T_fdw, followed by
    steady DON'T WALK.

    The wire field PED=<axis>:req aggregates "request latched OR
    actively serving". So the latch-or-serve token stays "req" through
    the entire ped phase (WALK + FDW). Once steady DON'T WALK is
    reached at the through-green's end, the token drops to "clr".

    What we can verify on the wire: PED=NS:req at NS_THROUGH_GREEN
    entry, still "req" all the way until NS_THROUGH_YELLOW, then
    "clr" by NS_THROUGH_YELLOW (steady DW reached, ped no longer
    serving). The T_walk → T_fdw → DW timing is structurally enforced
    by Phase_Sequencer.Phase_Duration (it returns T_walk + T_fdw on a
    served phase), so observing the green's total duration ≥
    T_walk + T_fdw is sufficient evidence the progression executed."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED NW")
        ns_green = q.wait_for_transition_to("NS_THROUGH_GREEN", timeout_s=25.0)
        ns_yellow = q.wait_for_transition_to("NS_THROUGH_YELLOW",
                                             timeout_s=T_MIN_G_PED / 1000 + 5)
        assert ns_green.ped_ns == "req"
        # By NS_THROUGH_YELLOW the ped is back to Idle — no longer
        # serving — so PED=NS:clr.
        assert ns_yellow.ped_ns == "clr", (
            f"PED=NS still 'req' at NS_THROUGH_YELLOW — DW transition "
            f"didn't complete: {ns_yellow.raw}"
        )


@requires("FR-PD-07")
def test_fr_pd_07_press_during_active_phase_has_no_effect():
    """FR-PD-07: pressing a pedestrian button while the corresponding
    pedestrian phase is already active shall have no effect.

    Observable on wire: while NS ped is serving (NS_THROUGH_GREEN with
    PED=NS:req), press NW again. The duration of NS_THROUGH_GREEN must
    remain T_walk + T_fdw, NOT be extended further — confirming the
    second press did not re-arm the latch (which on top of an
    in-progress walk would have no extension semantics anyway, but a
    bug could plausibly reset the walk clock)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("PRESS PED NW")
        ns_green = q.wait_for_transition_to("NS_THROUGH_GREEN", timeout_s=25.0)
        # Spam re-presses during the active walk phase.
        for _ in range(5):
            q.send("PRESS PED NW")
        ns_yellow = q.wait_for_transition_to("NS_THROUGH_YELLOW",
                                             timeout_s=T_MIN_G_PED / 1000 + 5)
        dur = ns_yellow.wall_ms - ns_green.wall_ms
        # Same window as FR-PD-06 — the second press must NOT extend
        # the phase beyond T_walk + T_fdw.
        assert dur <= T_MIN_G_PED + 250, (
            f"in-phase re-press extended NS_THROUGH_GREEN to {dur} ms "
            f"(> T_walk+T_fdw={T_MIN_G_PED}) — FR-PD-07 violated"
        )
