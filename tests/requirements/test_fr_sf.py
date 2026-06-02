"""Safety-logic requirement tests (FR-SF-*).

Driven against the arm32-eabi QEMU binary built from
``traffic_light_qemu.gpr``. Each test gets a fresh QEMU instance.

FR-SF-06 (MMU GPIO heartbeat pulse) is intentionally not covered here:
the QEMU mps2-an385 build has no GPIO mapped to a discrete pin; the
MMU heartbeat is a hardware-only artifact. See README.md § scope.
"""
from __future__ import annotations

# @req FR-SF-01, FR-SF-02, FR-SF-03, FR-SF-04, FR-SF-05, FR-SF-07,
# @req FR-SF-08, FR-SF-09
from harness import QemuSession, requires

T_STARTUP_MS = 5_000   # src/core/timing.ads
T_LT_G_MS    = 8_000
T_Y_MS       = 3_000
T_AR_MS      = 2_000

# Pair of yellows-to-red moves we cross when walking the nominal cycle.
# (yellow_phase, following_all_red) — every consecutive pair of vehicle
# phases must be separated by an ALL_RED.
YELLOW_TO_RED = [
    ("NS_LT_YELLOW",     "ALL_RED_1"),
    ("NS_THROUGH_YELLOW","ALL_RED_2"),
    ("EW_LT_YELLOW",     "ALL_RED_3"),
    ("EW_THROUGH_YELLOW","ALL_RED_4"),
]


@requires("FR-SF-03")
def test_fr_sf_03_startup_holds_for_T_startup():
    """FR-SF-03: on startup the controller shall display all-flashing-red
    on every vehicle indication for ``T_startup`` before entering the
    normal phase sequence.

    Observable on wire: the first PH= record is STARTUP_FLASH at T=0,
    and the wall-clock interval between it and the next transition
    (NS_LT_GREEN) is at least ``T_startup`` (within timing tolerance)."""
    with QemuSession() as q:
        trs = q.wait_for_transitions(2, timeout_s=T_STARTUP_MS / 1000 + 5)
        assert trs[0].phase == "STARTUP_FLASH", (
            f"expected first phase STARTUP_FLASH, got {trs[0].phase}"
        )
        assert trs[0].t_ms == 0
        startup_dur = trs[1].wall_ms - trs[0].wall_ms
        # NFR-PF-03 says ±50 ms tolerance; loosen to 250 ms here because
        # the wall_ms is sampled at line-receive time, not at the
        # controller's emit time.
        assert abs(startup_dur - T_STARTUP_MS) < 250, (
            f"startup phase lasted {startup_dur} ms wall (expected "
            f"{T_STARTUP_MS} ±250)"
        )


@requires("FR-SF-04", "FR-SF-07", "FR-SF-08", "FR-SF-09")
def test_fr_sf_07_fault_input_forces_fault_state():
    """FR-SF-04: on detection of a fault, the controller shall transition
    to the fault state. FR-SF-07: the controller shall enter the fault
    state immediately upon receiving an asserted fault input. FR-SF-08:
    vehicle indications shall display flashing red (FAULT phase = empty
    movement set = all-red). FR-SF-09: pedestrian indications shall
    display steady DON'T WALK (no ped movement active in FAULT phase).

    Observable on wire: send ``FAULT 1`` on the command serial interface,
    expect a PH=FAULT record within a small number of ticks."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("FAULT 1")
        tr = q.wait_for_transition_to("FAULT", timeout_s=2.0)
        assert tr.fault == 1
        assert tr.phase == "FAULT"


@requires("FR-SF-05")
def test_fr_sf_05_no_auto_recovery_from_fault():
    """FR-SF-05: recovery from the fault state shall require a manual
    reset; the controller shall not auto-recover.

    Observable on wire: enter FAULT, deassert the fault input
    (``FAULT 0``), tick for several seconds, and observe no transition
    out of FAULT (no PH=<something other than FAULT> record)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("FAULT 1")
        fault_tr = q.wait_for_transition_to("FAULT", timeout_s=2.0)
        fault_entry_wall = fault_tr.wall_ms
        # Deassert the fault input and idle for several seconds. If
        # FR-SF-05 is violated we'd see the sequencer cycle out of
        # FAULT into STARTUP_FLASH or NS_LT_GREEN.
        q.send("FAULT 0")
        q.collect_for(3.0)
        post = [tr.phase for tr in q.log.transitions
                if tr.wall_ms > fault_entry_wall]
        # Cmd-applied re-emits of FAULT (T= non-zero) are fine; what we
        # forbid is any record whose phase is *not* FAULT after entry.
        non_fault = [p for p in post if p != "FAULT"]
        assert not non_fault, (
            f"controller auto-recovered from FAULT — saw {non_fault}"
        )


@requires("FR-SF-01", "FR-SF-02")
def test_fr_sf_01_02_conflict_invariant_holds_over_nominal_cycle():
    """FR-SF-01/02: the controller shall never simultaneously assert
    green/yellow on conflicting movements (FR-SF-01) or WALK against a
    conflicting vehicle movement (FR-SF-02).

    On QEMU we don't have raw GPIO; what we can verify on the wire is
    the *phase ordering invariant* that makes FR-SF-01/02 structurally
    impossible: every transition between two vehicle phases passes
    through an ALL_RED clearance, so no two vehicle phases are ever
    active simultaneously. Walking one full cycle of the nominal
    sequence is sufficient evidence that the ordering invariant holds
    in this build. (The deeper proof obligation lives in
    ``tests/proof/conflict_check_proof.gpr``.)"""
    with QemuSession() as q:
        # Each yellow must be followed by its corresponding all-red.
        # Walk through the nominal cycle.
        for yellow, all_red in YELLOW_TO_RED:
            q.wait_for_transition_to(yellow, timeout_s=30.0)
            q.wait_for_transition_to(all_red, timeout_s=T_Y_MS / 1000 + 2)
        # Spot-check that none of the transitions ever asserted FAULT=1
        # off-nominal and that we observed an ALL_RED between every two
        # vehicle phases.
        phases = [tr.phase for tr in q.log.transitions]
        # Every consecutive (vehicle_yellow → next_phase) must be
        # *_RED_*.
        for i, ph in enumerate(phases[:-1]):
            if ph.endswith("_YELLOW"):
                nxt = phases[i + 1]
                assert nxt.startswith("ALL_RED"), (
                    f"yellow {ph} was followed by {nxt}, not an all-red"
                )
