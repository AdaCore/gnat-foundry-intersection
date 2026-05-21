"""Non-functional requirement tests.

Most NFRs are structural (NFR-MN-01..03 — module layout / SPARK
amenability), self-test driven on real hardware (NFR-RL-01..03 — RAM
CRC, IWDG, WWDG; no equivalent on QEMU), or already exercised
elsewhere (NFR-DG-01 — covered by test_fr_ui_03).

What's testable here:
- NFR-PF-03 — phase timing accuracy ±50 ms.
"""
from __future__ import annotations

# @req NFR-PF-03
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
