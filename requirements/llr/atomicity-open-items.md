# LLR atomicity — open items

Working note from the atomicity sweep (see `coverage.md`, `TODO.md`). Records
the two candidates left undone and the reasoning, so we can resume cold.

Convention established during the sweep: **setting a machine state and its
companion dwell timer in one statement is atomic** — "enter state X, load its
dwell" is a single thought (the vehicle sequencer context says the schedule
"rides on the (state, timer) pair"). This is why `llr_4_controller.3/.5`
(`Initialize` state + timer) are *not* defects.

Already fixed this pass (clean renumber, cross-refs + coverage reconciled):
- `llr_1_states` — `Left_Demand_State`/`Array` (10/11), `Pedestrian_State`/`Array`
  (13/14), `Movement`/`Face_Of` (18/19) split.
- `llr_4_controller` — NORMAL projection split per signal (9/10/11), FAULT step
  split into Moore-output vs transition (14/15), edge derivation split into
  demand-clear vs pedestrian-service (19/20).

---

## 1. `llr_4_controller_1_vehicle.47` (`Enter_Both`) — RESOLVED (2026-07-10)

Not split — **dropped**. `Enter_Both` was a DRY procedural bundle with no
behavioural content of its own; keeping it as a requirement was reading the
code structure back into the spec. Resolution:

- **`Enter_Both` requirement removed entirely.** Every "apply `Enter_Both`"
  now states the assignments directly, so the both-through entries read like
  every other transition in the file.
- **Entries split on the lag-approach demand (Moore restatement).** The
  Mealy "set `Veh_Lag` to TRUE *when* …" became fully-guarded transitions
  with a *definite* `Veh_Lag`: `24/25` and `28/29` (NS, on SOUTH), `38/39`
  and `42/43` (EW, on WEST). Each sets `Veh_Lag`, `State.Vehicle`, and the
  residual dwell inline.
- **The residual formula folded into the entries** (four `(lead, lag)` cases,
  each appearing NS + EW), bound to `Both_Duration` via `impl`. The demand
  floor is owned by `llr_1_states.29` (`hlr_3_timing.12`); the separate
  `Both_Duration` postcondition statement was dropped as derivable.

Key realisation: the latch is **forced by `hlr_3_timing.8`** (T_BOTH is the
residual after the phases that *actually run*, sized at entry), so the
composed machine is genuinely Mealy at both-through entry — accepted rather
than papered over. File renumbered to contiguous keys 1–50; `coverage.md`
reconciled. Validators clean (schema/ears 18/0/0).

---

## 2. `llr_7_main.3` — RESOLVED (2026-07-09)

Split three ways into `llr_7_main.3/.4/.5`; `parent_req` unchanged;
`coverage.md` `1_modes.2` row updated to `llr_7_main.3/.4/.5`; schema + ears
validators clean (18/0/0).

- `3` (ubiquitous) — instantiate `State_Machine_Loop` with `Delay_For` +
  `Bus_Read` + `Bus_Write`. Traces `hlr_1_modes.2`.
- `4` (event) — "When the controller starts up, … shall call
  `Display.Initialize`." Traces `hlr_1_modes.2`.
- `5` (event, chained) — "When `Display.Initialize` has returned, … shall run
  `State_Machine_Loop`." Traces `hlr_1_modes.2`.

**EARS framing decided.** The ordering constraint (Initialize *before* run) is
expressed as the **trigger of `5`** ("When `Display.Initialize` has returned"),
not an "and … after …" clause — EARS is temporal-logic ordered, so sequence
lives in the `When` clause. Mirrors `llr_5_core_loop.1` ("before the first
iteration").

**Tracing decided.** All three refine `hlr_1_modes.2` (the loop *lifecycle*:
build → init display → run). Statement `3` is loop *composition*, not signal
binding — it wires the loop against the `Bus_Read`/`Bus_Write` operations, not
the named signals — so it does **not** trace to `hlr_4_signals`. Only `1`/`2`
(which bind the six signals) trace to `hlr_4_signals`. This resolves the
`main.3` tracing question raised during the split.
