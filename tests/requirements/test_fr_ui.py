"""User-interface requirement tests (FR-UI-*).

FR-UI-01 (serial 115200 8N1) is covered structurally by the fact that
the QEMU CMSDK UART driver in ``src/hal/qemu_mps2/hal.adb`` is the
sole writer on UART0 and the binary builds; the baud-rate detail is
not observable on QEMU's TCP-tunnelled chardev (QEMU doesn't enforce
baud on TCP transport). The wire grammar — which is the *functional*
contract behind FR-UI-01 — is checked by the format assertions below.
"""
from __future__ import annotations

# @req FR-UI-01, FR-UI-02, FR-UI-03, FR-UI-04, FR-UI-05, NFR-DG-01
from harness import QemuSession, requires, PH_RE, HB_RE

T_STARTUP_MS = 5_000


@requires("FR-UI-03", "NFR-DG-01")
def test_fr_ui_03_phase_transition_record_format():
    """FR-UI-03: the controller shall emit a phase-transition record on
    UART0 immediately following each phase transition, in the
    wire-protocol § 1.1 line format.

    NFR-DG-01 also covered: diagnostic record on every phase transition.
    """
    with QemuSession() as q:
        # Walk past STARTUP into the first vehicle phase — that guarantees
        # we've crossed a real transition (not just the boot-time
        # initial emit).
        q.wait_for_transitions(2, timeout_s=T_STARTUP_MS / 1000 + 5)
        # Every PH= line we logged must parse against the canonical RE.
        for tr in q.log.transitions:
            m = PH_RE.match(tr.raw)
            assert m is not None, (
                f"PH= line did not match wire grammar: {tr.raw!r}"
            )
        # And the two records we expect: STARTUP_FLASH then NS_LT_GREEN.
        assert q.log.transitions[0].phase == "STARTUP_FLASH"
        assert q.log.transitions[1].phase == "NS_LT_GREEN"
        # Each transition record carries T=0 — the controller emits
        # immediately after entering the new phase.
        assert q.log.transitions[1].t_ms == 0


@requires("FR-UI-04")
def test_fr_ui_04_heartbeat_at_one_hz():
    """FR-UI-04: heartbeat record on UART0 at no less than 1 Hz,
    independent of phase transitions.

    Observe a 6 s window from STARTUP_FLASH and count HB records; we
    must see at least 5 (the controller emits every 1000 ticks, so 6 s
    yields 5 or 6 HB records depending on alignment)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        window_start_wall = q.elapsed_ms()
        hb_at_start = len(q.log.heartbeats)
        q.collect_for(6.0)
        new_hbs = q.log.heartbeats[hb_at_start:]
        assert len(new_hbs) >= 5, (
            f"expected at least 5 HBs in 6 s window, got "
            f"{len(new_hbs)}: {[h.raw for h in new_hbs]}"
        )
        # And the grammar of each HB line parses.
        for hb in new_hbs:
            assert HB_RE.match(hb.raw), f"bad HB line: {hb.raw!r}"
        # Monotonic: t_ms increases by at least 900 ms (allow some jitter
        # under emulation) and by at most 1100 ms between consecutive HBs.
        for prev, nxt in zip(new_hbs, new_hbs[1:]):
            delta = nxt.t_ms - prev.t_ms
            assert 900 <= delta <= 1100, (
                f"heartbeat cadence anomaly: {prev.raw} → {nxt.raw} "
                f"(Δ={delta} ms)"
            )


@requires("FR-UI-02")
def test_fr_ui_02_reset_returns_controller_to_startup():
    """FR-UI-02: the controller shall provide a manual reset input that
    returns the system to the startup state.

    On QEMU the reset is exposed over the cmd-in wire as the ``RESET``
    line (per FR-UI-05 + wire-protocol § 2)."""
    with QemuSession() as q:
        # Walk into a non-startup phase first.
        ns_lt = q.wait_for_transition_to("NS_LT_GREEN",
                                         timeout_s=T_STARTUP_MS / 1000 + 5)
        reset_wall = q.elapsed_ms()
        q.send("RESET")

        def pred(log):
            for tr in log.transitions:
                if tr.wall_ms > reset_wall and tr.phase == "STARTUP_FLASH":
                    return tr
            return None
        tr = q.read_until(pred, timeout_s=2.0)
        # After RESET the new STARTUP_FLASH record should have T=0
        # (fresh state).
        assert tr.t_ms == 0
        # And the cycle proceeds normally afterward (i.e. RESET dropped
        # us back to the genuine startup flow, not some half-state).
        q.wait_for_transition_to("NS_LT_GREEN", timeout_s=T_STARTUP_MS / 1000 + 5)


@requires("FR-UI-05")
def test_fr_ui_05_command_dispatch_round_trip():
    """FR-UI-05: the controller shall accept newline-terminated commands
    on UART1 in the wire-protocol § 2 forms.

    Cover the four verbs (PRESS PED, SET LT, FAULT, RESET) with a
    minimal-effect round-trip each, and assert that malformed input is
    silently discarded (no state change observable on UART0)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)

        # SET LT EW 0 — observable on next emitted record as LT=EW:0.
        q.send("SET LT EW 0")
        def lt_pred(log):
            for tr in log.transitions:
                if tr.lt_ew == 0:
                    return tr
            return None
        tr = q.read_until(lt_pred, timeout_s=2.0)
        assert tr.lt_ew == 0 and tr.lt_ns == 1, (
            f"SET LT EW 0 did not clear EW left demand only: {tr.raw}"
        )

        # FAULT 1 — observable as FAULT=1 (and shortly PH=FAULT).
        q.send("FAULT 1")
        q.wait_for_transition_to("FAULT", timeout_s=2.0)

        # RESET — observable as a return to STARTUP_FLASH.
        reset_wall = q.elapsed_ms()
        q.send("RESET")
        def reset_pred(log):
            for tr in log.transitions:
                if tr.wall_ms > reset_wall and tr.phase == "STARTUP_FLASH":
                    return tr
            return None
        q.read_until(reset_pred, timeout_s=2.0)

        # PRESS PED NE — must light up PED=EW:req (NE maps to EW_East
        # per the cmd-parser convention; aggregated as PED=EW). We send
        # the press while still in STARTUP_FLASH; the cmd-applied
        # re-emit shows the new state.
        q.send("PRESS PED NE")
        press_wall = q.elapsed_ms()
        def press_pred(log):
            for tr in log.transitions:
                if tr.wall_ms > press_wall and tr.ped_ew == "req":
                    return tr
            return None
        tr = q.read_until(press_pred, timeout_s=2.0)
        assert tr.ped_ew == "req" and tr.ped_ns == "clr"

        # Malformed lines must be silently discarded — no spurious
        # state change. Send several junk lines and confirm no
        # cmd-applied transition record appears within 1 s.
        baseline = len(q.log.transitions)
        for bad in ("PRESS PED ZZ", "set lt ns 0", "FAULT 9",
                    "RESET extra", "", "garbage"):
            q.send(bad)
        q.collect_for(1.5)
        new_trs = q.log.transitions[baseline:]
        for tr in new_trs:
            # The only legitimate new transition during this 1.5 s
            # window would be the controller's own Tick advancing past
            # STARTUP_FLASH; we accept that. What we forbid is a
            # cmd-applied re-emit of the same phase, since that would
            # be evidence that a malformed line was accepted.
            assert tr.t_ms == 0, (
                f"malformed cmd produced a cmd-applied re-emit "
                f"(T={tr.t_ms}, not a natural Tick-driven transition): "
                f"{tr.raw}"
            )
