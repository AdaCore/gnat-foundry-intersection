"""Sanity tests for the requirements harness itself.

These don't anchor to a specific FR — they confirm the QEMU bring-up,
UART routing, and command channel work before the real requirement
tests rely on them.
"""
from __future__ import annotations

from harness import QemuSession, requires


def test_smoke_boot_emits_startup_record():
    """Smoke: QEMU boots and emits the initial PH=STARTUP_FLASH record."""
    with QemuSession() as q:
        tr = q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        assert tr.t_ms == 0, f"first transition T= should be 0, got {tr.t_ms}"
        assert tr.fault == 0
        assert tr.ped_ns == "clr"
        assert tr.ped_ew == "clr"


def test_smoke_uart1_dispatch_round_trip():
    """Smoke: a command on UART1 produces an immediate diag-out record
    reflecting the new state (FAULT 1 → FAULT=1 on next emitted line)."""
    with QemuSession() as q:
        q.wait_for_transition_to("STARTUP_FLASH", timeout_s=5.0)
        q.send("FAULT 1")
        # Cmd_Input.Pump runs once per 1 ms tick; we should see a
        # cmd-applied transition record with FAULT=1 inside ~1 s.
        def pred(log):
            for tr in log.transitions:
                if tr.fault == 1:
                    return tr
            return None
        tr = q.read_until(pred, timeout_s=2.0)
        assert tr.fault == 1, f"expected FAULT=1, got {tr.raw}"
