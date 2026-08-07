# Review findings from the verification-method classification (2026-08-05)

Deviations between requirements and code found while classifying every LLR
statement's `verification:` method. None are caught by `make prove` or the
current tests; all sit in `review`-marked statements today. Each needs either a
code fix or a requirements change — decide direction before editing.

## Code vs requirements deviations

- [ ] **Missing HOLD states.** The requirements describe a commit/HOLD
  two-state both-through split (`NS_BOTH_THROUGH_HOLD`, `EW_BOTH_THROUGH_HOLD`,
  see `requirements/state-machines.md` §the both-through edges), but
  `States.Vehicle_Sequencer_State` (src/types/states.ads) declares 20 literals
  with no `*_HOLD` at all. Affected: `llr_4_controller_1_vehicle.7/.18`
  (Moore rows), `.31/.32/.44/.45` (transitions).
- [ ] **`llr_1_states.12` literal count.** Says "exactly the twenty-two
  sequencer states", its own parenthesis lists 21 names, the type declares 20.
- [ ] **Latched lag flag.** `llr_4_controller_1_vehicle` context says "no
  latched lag flag: the exit reads State.Left directly" (`.30`/`.43`), but
  `Controller.Enter_Both` latches `State.Veh_Lag` at both-through entry and the
  exits read that flag. Also defeats `llr_4_controller.22` for the lagging-left
  case, and `Veh_Lag` is a `Controller_State` field `llr_4_controller.1` does
  not enumerate.
- [ ] **`Both_Duration` formula.** `.26/.29/.39/.42` require
  `T_AXIS - T_BARRIER - [lead overhead] - (T_YELLOW + T_REDCLEAR + T_LAG +
  T_YELLOW)` and a `Lead_Ran`-only signature; the implementation takes
  `(Lead_Ran, Lag)` and subtracts only `T_YELLOW` when `Lag` is False, so the
  emitted dwell differs on the no-lag branch. Its `Post` proves only the
  `T_Both_Min`/`T_Axis` bounds, so `make prove` cannot see this.
- [ ] **Emit precedes advance.** `llr_4_controller.16` (and the pedestrian
  `algorithm_aspects`) require outputs to project the state *after* this step's
  transitions, but `Controller.Step` assigns `Outputs := Project_Outputs
  (State)` before the advance and edge stages, so GREEN-edge couplings land one
  display write late.

## Test-quality gaps

- [ ] `tests/types/states-test_data-tests.adb` routines carry `--@covers
  llr_1_states.19/.20` tags but are unimplemented gnattest skeletons — the
  `test` marks on those two statements record vacuous evidence.
- [ ] `Test_Step` cites `llr_4_controller.16` and `.22` and passes despite the
  emit-ordering and lag-latch deviations above — the assertions are too shallow
  to catch them.
