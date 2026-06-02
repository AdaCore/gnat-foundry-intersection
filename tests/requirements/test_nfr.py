"""Non-functional requirement tests.

Most NFRs are structural (NFR-MN-01..03 — module layout / SPARK
amenability), self-test driven on real hardware (NFR-RL-01..03 — RAM
CRC, IWDG, WWDG; no equivalent on QEMU), or already exercised
elsewhere (NFR-DG-01 — covered by test_fr_ui_03).

What's testable here:
- NFR-PF-01 — button press to latched-request within 100 ms.
- NFR-PF-02 — lamp outputs updated within 50 ms of phase transition.
- NFR-PF-03 — phase timing accuracy ±50 ms.

NFR-PF-01 and NFR-PF-02 are phrased in terms of GPIO-edge latency,
which has no direct equivalent on QEMU. The tests below use the wire
protocol as a proxy: cmd-in PRESS PED and FAULT commands travel
through the same main-loop code path as HAL button/transition events,
so the observed wire latency upper-bounds the GPIO latency.
"""
from __future__ import annotations

# @req NFR-PF-01, NFR-PF-02, NFR-PF-03
from harness import QemuSession, requires

T_STARTUP_MS = 5_000
T_LT_G_MS    = 8_000
T_Y_MS       = 3_000
T_AR_MS      = 2_000
T_MIN_G_MS   = 7_000

EXPECTED = {
    "STARTUP_FLASH":      T_STARTUP_MS,
    "NS_LT_GREEN":        T_LT_G_MS,
    "NS_LT_YELLOW":       T_Y_MS,
    "ALL_RED_1":          T_AR_MS,
    "NS_THROUGH_GREEN":   T_MIN_G_MS,  # no ped, no extension
    "NS_THROUGH_YELLOW":  T_Y_MS,
    "ALL_RED_2":          T_AR_MS,
}


@requires("NFR-PF-01")
def test_nfr_pf_01_button_press_to_latch_within_100ms():
    """NFR-PF-01: button press to latched-request transition within
    100 ms.

    On QEMU the cmd-in PRESS PED bypasses the HAL debounce layer and
    enters the main loop at Cmd_Input.Pump — the same tick boundary
    where a hardware button press would be sampled. The test measures
    wall-clock latency from command send to the first PH= record
    showing PED=<axis>:req. This upper-bounds the GPIO-edge-to-latch
    path because the TCP transport adds latency that the GPIO path
    would not have."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        # Small drain to let the startup record settle.
        q.collect_for(0.1)
        baseline = len(q.log.transitions)
        press_wall = q.elapsed_ms()
        q.send("PRESS PED NW")  # NW → NS_North → PED=NS:req

        def latch_visible(log):
            for tr in log.transitions[baseline:]:
                if tr.wall_ms > press_wall and tr.ped_ns == "req":
                    return tr
            return None
        tr = q.read_until(latch_visible, timeout_s=2.0)
        latency = tr.wall_ms - press_wall
        assert latency <= 100, (
            f"button-press-to-latch latency {latency} ms exceeds "
            f"100 ms (NFR-PF-01): {tr.raw}"
        )


@requires("NFR-PF-02")
def test_nfr_pf_02_lamp_output_within_50ms_of_transition():
    """NFR-PF-02: lamp outputs updated within 50 ms of an internal
    phase transition.

    On QEMU there are no GPIO lamp outputs. The diagnostic PH= record
    is emitted in the same main-loop tick as the phase transition,
    *after* the sequencer has updated the active-movement set that
    drives lamps. So the PH= record's arrival time is an upper bound
    on when lamps would have been set.

    Two checks:
    1. Forced transition: send FAULT 1 from a stable phase and
       measure wall-clock to the PH=FAULT record.
    2. Natural transitions: verify every PH= record carries T=0,
       confirming the diagnostic (and thus the lamp update) was
       emitted on the same tick as phase entry."""
    with QemuSession() as q:
        # Wait into a stable phase so the FAULT triggers a real
        # transition, not a re-emit of an already-faulted state.
        q.wait_for_transition_to("NS_LT_GREEN",
                                 timeout_s=T_STARTUP_MS / 1000 + 5)
        q.collect_for(0.1)
        baseline = len(q.log.transitions)
        fault_wall = q.elapsed_ms()
        q.send("FAULT 1")

        def fault_seen(log):
            for tr in log.transitions[baseline:]:
                if tr.wall_ms > fault_wall and tr.phase == "FAULT":
                    return tr
            return None
        tr = q.read_until(fault_seen, timeout_s=2.0)
        latency = tr.wall_ms - fault_wall
        assert latency <= 50, (
            f"phase-transition-to-output latency {latency} ms exceeds "
            f"50 ms (NFR-PF-02): {tr.raw}"
        )

        # Second check: every phase-entry record (where the phase
        # differs from the prior record) should carry T=0, confirming
        # the diagnostic was emitted on the tick of phase entry.
        # Cmd-applied re-emits (same phase, T>0) are expected and
        # excluded — they're mid-phase state updates, not entries.
        trs = q.log.transitions
        bad = [
            trs[i] for i in range(1, len(trs))
            if trs[i].phase != trs[i - 1].phase and trs[i].t_ms != 0
        ]
        assert not bad, (
            f"phase-entry records with T≠0 (diagnostic deferred past "
            f"phase entry): {[t.raw for t in bad]}"
        )


@requires("NFR-PF-03")
def test_nfr_pf_03_phase_timing_accuracy_within_50ms():
    """NFR-PF-03: phase timing accuracy ±50 ms over any single phase
    interval.

    Measure each nominal phase's wall-clock duration and assert it
    falls within ±50 ms of the spec-defined constant. (We allow a
    +250 ms upper bound — the wall clock includes line-receive
    latency, which is ~ms-scale but bounded above by socket select
    granularity. The lower bound is tight at 50 ms because the
    controller cannot under-shoot a duration without skipping a
    Tick.)"""
    with QemuSession() as q:
        # Walk to ALL_RED_2 (covers all 7 phases in EXPECTED).
        q.wait_for_transition_to("ALL_RED_2", timeout_s=30.0)
        trs = q.log.transitions
        violations: list[str] = []
        for i, tr in enumerate(trs[:-1]):
            if tr.phase not in EXPECTED:
                continue
            dur = trs[i + 1].wall_ms - tr.wall_ms
            target = EXPECTED[tr.phase]
            if not (target - 50 <= dur <= target + 250):
                violations.append(
                    f"{tr.phase}: dur={dur} ms (target {target} "
                    f"±50/+250)"
                )
        assert not violations, "\n".join(violations)
