# Requirements-based integration tests

End-to-end tests that drive the **bare-metal arm-eabi binary** under
`qemu-system-arm` and assert against the SRS in
[`docs/requirements/srs.md`](../../docs/requirements/srs.md). Each
test corresponds to one or more `FR-*` / `NFR-*` IDs and carries a
`# @req <ID>` annotation that
[`tools/trace-check.py`](../../tools/trace-check.py) scans for
coverage reporting.

These tests complement, not replace:

| Layer | Location | Drives |
|-------|----------|--------|
| Unit | `tests/unit/test_runner.adb` | In-process — sequencer + cmd parser + ped state |
| Proof | `tests/proof/conflict_check_proof.gpr` | SPARK proof of FR-SF-01 / FR-SF-02 on the conflict matrix |
| **Requirements** (this directory) | `tests/requirements/test_*.py` | The actual `bin/qemu_mps2/main` running under QEMU, talking the wire protocol over two TCP-routed UARTs |

## Running

```bash
# 1. Build the QEMU binary.
alr -n exec -- gprbuild -P traffic_light_qemu.gpr

# 2. Run the full suite (~3 minutes; each test launches its own QEMU).
python3 tests/requirements/run.py

# 3. Or a subset by substring match on the module name.
python3 tests/requirements/run.py fr_sf fr_ui
```

Output ends with a summary like:

```
Summary: 16 passed, 0 failed, 16 total
Requirements exercised by passing tests (NN): FR-PH-01, FR-PH-02, ...
```

## Harness

[`harness.py`](harness.py) defines a `QemuSession` context manager
that:

1. Picks a unique pair of TCP ports (offset by PID to dodge
   `TIME_WAIT` between re-runs).
2. Spawns `qemu-system-arm -M mps2-an385 -cpu cortex-m3 -nographic`
   with two `-serial tcp:127.0.0.1:<port>,server` flags — the first
   is UART0 (diag-out, controller writes); the second is UART1
   (cmd-in, controller reads).
3. Connects to both ports. **`server` without `nowait` means QEMU
   blocks until both connections are made**, so the boot-time
   `startup` banner and the initial `PH=STARTUP_FLASH T=0` record
   are never lost (a real-time race we hit with `,nowait`).
4. Exposes `wait_for_transition_to(phase, timeout_s)`,
   `wait_for_transitions(n, timeout_s)`, `read_until(predicate, ...)`,
   `collect_for(seconds)`, and `send(cmd_line)`.
5. Parses every line off UART0 into either a `Transition` (`PH=` line)
   or a `Heartbeat` (`HB` line) and accumulates them in
   `q.log.transitions` / `q.log.heartbeats`.

Tests assert on the parsed log. The wire grammar is single-sourced in
[`docs/requirements/wire-protocol.md`](../../docs/requirements/wire-protocol.md);
the regex used to parse it lives in `harness.py`'s `PH_RE` /
`HB_RE` so any grammar drift surfaces as a parse failure.

## What's covered

| ID | Test | Notes |
|----|------|-------|
| FR-PH-01 | `test_fr_ph.test_fr_ph_01_nominal_phase_sequence_order` | Walks one full cycle, checks 13-token order |
| FR-PH-02 | `test_fr_ph.test_fr_ph_02_skip_ns_left_when_no_demand` / `..._ew_...` | `SET LT <axis> 0` then walk past the skipped phase |
| FR-PH-03 | `test_fr_ph.test_fr_ph_03_through_green_holds_at_least_T_min_g` | Measures NS_THROUGH_GREEN wall duration ≥ T_min_g |
| FR-PH-04 | `test_fr_ph.test_fr_ph_04_green_to_red_only_via_yellow` | Asserts every `*_GREEN` is followed by `*_YELLOW`, and the yellow lasts T_y ±50 ms |
| FR-PH-05, FR-PH-06 | `test_fr_ph.test_fr_ph_05_06_all_red_clearance_between_vehicle_phases` | Every ALL_RED phase lasts T_ar ±50 ms |
| FR-PD-02 | `test_fr_pd.test_fr_pd_02_press_latches_until_served_or_reset` / `..._reset_clears_latch` | Latch persists across a Tick-driven transition; RESET clears it |
| FR-PD-03, FR-PD-06 | `test_fr_pd.test_fr_pd_03_06_through_green_extends_for_ped_request` | NS_THROUGH_GREEN with NW press lasts T_walk + T_fdw |
| FR-PD-04, FR-PD-06 | `test_fr_pd.test_fr_pd_04_06_ew_through_extends_for_ew_ped` | EW_THROUGH_GREEN with SW press lasts T_walk + T_fdw |
| FR-PD-05 | `test_fr_pd.test_fr_pd_05_walk_then_fdw_then_dw_progression` | PED=NS=req at green entry, =clr by yellow entry — confirms WALK→FDW→DW completed |
| FR-PD-07 | `test_fr_pd.test_fr_pd_07_press_during_active_phase_has_no_effect` | Re-presses during an active walk don't extend the phase |
| FR-SF-01, FR-SF-02 | `test_fr_sf.test_fr_sf_01_02_conflict_invariant_holds_over_nominal_cycle` | Every yellow is followed by an ALL_RED on the wire over a full cycle |
| FR-SF-03 | `test_fr_sf.test_fr_sf_03_startup_holds_for_T_startup` | Time between first and second PH= record ≥ T_startup |
| FR-SF-04, FR-SF-07 | `test_fr_sf.test_fr_sf_07_fault_input_forces_fault_state` | `FAULT 1` → PH=FAULT within a few ticks |
| FR-SF-05 | `test_fr_sf.test_fr_sf_05_no_auto_recovery_from_fault` | After `FAULT 0`, controller stays in FAULT |
| FR-UI-02 | `test_fr_ui.test_fr_ui_02_reset_returns_controller_to_startup` | `RESET` mid-cycle returns to STARTUP_FLASH |
| FR-UI-03, NFR-DG-01 | `test_fr_ui.test_fr_ui_03_phase_transition_record_format` | Every PH= line parses against the canonical grammar |
| FR-UI-04 | `test_fr_ui.test_fr_ui_04_heartbeat_at_one_hz` | ≥5 heartbeats in a 6-second window, 1000 ms ±100 ms cadence |
| FR-UI-05 | `test_fr_ui.test_fr_ui_05_command_dispatch_round_trip` | All four verbs round-trip; malformed lines produce no cmd-applied re-emit |
| NFR-PF-03 | `test_nfr.test_nfr_pf_03_phase_timing_accuracy_within_50ms` | Every nominal phase's wall duration within ±50 ms (with +250 ms jitter ceiling) of its `timing.ads` constant |

## What's intentionally **not** covered here

Some requirements have no observable equivalent on the QEMU mps2-an385
target. They are left to other layers (hardware bring-up, code review,
or upstream SPARK proof).

| ID | Why not on QEMU |
|----|------------------|
| FR-PD-01 (50 ms button debounce) | The cmd-in `PRESS PED` line injects an *already-debounced* press; the debounce path lives in the HAL boundary. Covered by Zephyr/STM32 bring-up. |
| FR-PD-08 (visible request indicator) | The button-mounted LED is GPIO; no equivalent in this build (HAL `Set_Lamp` is a no-op on `qemu_mps2`). |
| FR-SF-06 (≥1 Hz MMU heartbeat) | A discrete GPIO pulse on a separate channel; no MMIO routing on mps2-an385. Distinct from the FR-UI-04 UART0 heartbeat, which **is** tested above. |
| NFR-MN-01..03 | Structural — module layout / SPARK amenability. Static-analysed by code review and (for the conflict-check module) by `gnatprove`. |
| NFR-RL-01..03 | RAM/CRC/clock self-tests + IWDG/WWDG — all device-specific; no equivalent peripheral on mps2-an385. |
| NFR-DG-02 | Fault-code retention in non-volatile memory — no flash on mps2-an385 in this build. |
| NFR-PF-01, NFR-PF-02 | Both phrased in terms of GPIO-edge → state-change latency; no GPIO. Conceptually verified by the bound on cmd-applied transition latency (sub-tick = ≤ 1 ms) but the SRS phrasing is hardware-specific. |

If any of these become testable in a future build (e.g. a Zephyr
integration profile that wires real GPIO into the wire protocol),
add a new test module here and remove the row from this table.

## Timing budget

QEMU's mps2-an385 emulation runs SysTick at ~1:1 with wall clock —
empirically each phase's wall duration matches the `timing.ads`
constant within < 5 ms. Consequently each test takes roughly as
long as the controller-time interval it observes:

- Smoke / cmd round-trip tests: 0.1–1 s
- FR-SF-03 (startup duration): ~5 s
- FR-PH-04 / -05 / -06 (covers two greens): ~28 s
- FR-PH-01 (full cycle): ~55 s
- FR-PD-* tests reaching NS_THROUGH_GREEN with ped: ~33 s
- FR-PD-* tests reaching EW_THROUGH_GREEN with ped: ~55 s

Total full-suite wall time is ~3–4 minutes. The runner spawns one
QEMU per test for clean isolation; an obvious optimization is to use
`RESET` between tests within a single QEMU, but no test currently
needs more than the per-test budget.
