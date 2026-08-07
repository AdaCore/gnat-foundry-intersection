# Reducing the `review` bucket: machine-check candidates (2026-08-05)

Assessment of all 104 `verification: review` LLR statements. Verdict per
statement: the cheapest credible machine check (`test`, `proof`,
`static_check`), or `review` where none exists. Flags: **WOULD-FAIL** = a
faithful check is writable today but fails because the code deviates from the
requirement (see [findings.md](findings.md) — resolve the deviation first);
**UNIMPLEMENTED** = the required state/transition does not exist in the code.

Headline: **87 of 104 convert cleanly** (74 test, 1 proof, 12 static_check),
9 are machine-checkable but WOULD-FAIL today, 6 are blocked UNIMPLEMENTED,
and only 2 (`llr_7_main.4/.5`) must stay `review`.

Decision (2026-08-06): the WOULD-FAIL and UNIMPLEMENTED statements convert
too — write the check, let it fail, then fix the implementation or the
requirement (see [findings.md](findings.md)). All 102 are now marked; only
`llr_7_main.4/.5` remain `review`.

Converting a statement means, in one change: add the evidence (a `--@covers`
tag on the test routine, or above the contract aspect / pragma) and flip its
`verification:` — the trace gate enforces the pairing in both directions.

## llr_1_states

| Stmt | Method | How | Flag |
| --- | --- | --- | --- |
| 1–10, 13, 18 | test | loop `T'Range`, assert the exact literal list ('Image) and `'Pos ('Last)` | .12 below |
| 11, 14 | test | shape test: index type, `'Length`, component type |  |
| 12 | test | same literal-list loop | WOULD-FAIL (22 vs 21 vs 20 literals) |
| 15 | test | assert `'First`/`'Last` of the serving subtype and membership over the range |  |
| 16, 17 | test | named-component aggregate pins the record's exact field set; assert array index/component types |  |
| 21 | static_check | `Compile_Time_Error` pinning `Duration_Ms'First = 0` and `'Last = 3_600_000` |  |
| 22–26, 30 | static_check | one `Compile_Time_Error` per constant pinning its required value |  |
| 27, 28 | static_check | `Compile_Time_Error` restating each margin inequality over the constants |  |

Notes: the enum alphabets (1–10, 13, 18) could equally be `static_check` via
`'Pos` pragmas in states.ads — pick one mechanism uniformly when implementing.
Statements 1–8 carry a universal rider ("...as the value set of *every* such
signal") that no single check covers; the alphabet part is the checkable core.

## llr_2_buses — all `test`

| Stmt | How |
| --- | --- |
| 1 | instantiate `Source_Bus` with a counting producer; assert one call per `Bus_Read`, snapshot returned |
| 2 | table of producer level combinations; assert `Bus_Read` returns exactly what was sampled |
| 3 | producer yields A then B; assert the second read reports B entirely (no retained state) |
| 4 | instantiate `Display_Bus` with a recording consumer; assert delivery completed when `Bus_Write` returns |

Generics get no gnattest skeleton — these are hand-written AUnit cases (writable
region of an existing body, or `gnattest --additional-tests`). A proof
alternative for .3 (`Global => null` + an in-SPARK instantiation harness like
`state_machine_loop_proof`) exists but costs more for the same content.

## llr_5_core_loop — all `test`

| Stmt | How |
| --- | --- |
| 1 | instantiate the loop with stubs; a stub raises `Stop` after N iterations (escapes the `No_Return` procedure); compare emitted sequence to a single-`Initialize` reference trajectory |
| 2 | stubs record call-order tags; assert Read → Step → Write → Delay per iteration |
| 4 | assert every `Delay_For` argument = `T_Sample` and exactly one `Read_Sources` between consecutive delays |

.4 pins the cadence contract only; wall-clock accuracy remains the
`llr_6_hal.1` assumption.

## llr_4_controller

| Stmt | Method | How | Flag |
| --- | --- | --- | --- |
| 1 | static_check | named/positional full aggregate of `Controller_State` pins the exact component set | WOULD-FAIL (`Veh_Lag` is a 7th field the text omits) |

## llr_4_controller_1_vehicle

All checks go through the public `Project_Outputs` / `Step` — the helpers
(`Vehicle_Face_Outputs`, `Advance_Vehicle`, `Both_Duration`, ...) are private to
the controller body. `Controller_State` is fully visible, so tests can build
arbitrary states (the existing `Test_Step` already does).

| Stmt | Method | How | Flag |
| --- | --- | --- | --- |
| 1 | proof | `Post` on `Advance_Vehicle` enumerating successor per state + frame posts elsewhere | WOULD-FAIL (no HOLD branches; `Enter_Both` also assigns `Vehicle`) |
| 2 | proof | `Step` Post: `Veh_Timer'Old > T_Sample` ⇒ `Vehicle` unchanged ∧ timer decremented (see notes) |  |
| 3–6, 8–17, 19–24 | test | Moore-row test: `Project_Outputs` for the state, compare the whole Through/Left row | .7/.18: UNIMPLEMENTED (no `*_BOTH_THROUGH_HOLD` literal) |
| 25, 27, 28, 33–38, 40, 41, 46–50 | test | boundary transition test: craft `Veh_Timer = T_Sample`, call `Step`, assert successor state + timer load |  |
| 26, 29, 39, 42 | test | same, asserting the required commit-interval value | WOULD-FAIL (`Both_Duration` returns 34 000/22 000 instead of 22 000/10 000 on the no-lag branch) |
| 30, 43 | test | commit boundary with lag demand pending but entry-latched flag stale | WOULD-FAIL (exit reads latched `Veh_Lag`, not `State.Left`) |
| 31, 32, 44, 45 | test | boundary tests for the HOLD entry/exit | UNIMPLEMENTED |

## llr_4_controller_3_pedestrian — all `test`, all clean

| Stmt | How |
| --- | --- |
| 1–5 | `Project_Outputs` head row per pedestrian state (`DONT_WALK`/`WALK`/`FLASH_DONT_WALK`) |
| 6–9 | `Project_Outputs` request lamp per pedestrian state |
| 13–16 | boundary transition tests via `Step` with `Ped_Timer (C) = T_Sample` |
| 17 | multi-`Step` test: idle/PENDING timers stay put; serving timer drops exactly `T_Sample` |

## llr_7_main

| Stmt | Method | How | Flag |
| --- | --- | --- | --- |
| 1, 2 | static_check | the generic instantiation pins the actual's profile; the buses carry whole records, so every signal is bound |  |
| 3 | static_check | compiler pins the three `State_Machine_Loop` formal profiles + `No_Return` propagation |  |
| 4, 5 | review | HAL side effects / call ordering inside SPARK-off, `No_Return`, untestable `Main` — no hook |  |

.1–.3 pin shape only: any profile-conforming subprogram compiles, so "wired to
`Sources.Sample` / `Display.Show` *specifically*" stays reviewer-judged.

## Notes for implementation

- **vehicle.2 contract sketch** (on `Step` in controller.ads):
  `Post => ... and then (if State.Mode'Old = Normal_Operation and then
  Sensors.Fault /= Asserted and then State.Veh_Timer'Old > T_Sample then
  State.Vehicle = State.Vehicle'Old and then State.Veh_Timer =
  State.Veh_Timer'Old - T_Sample)`. Needs a frame `Post` on `Advance_Ped`
  (`Vehicle`/`Veh_Timer` unchanged) and the same equalities as a
  `Loop_Invariant` in the crosswalk advance loop. Write the guard with
  `T_Sample`, not "reaching zero" — the engine fires at `<= T_Sample`
  (sanctioned by llr_4_controller.18).
- Existing tests already model every needed pattern: one full Moore row
  (`W_LAG_YELLOW`), the boundary-firing shape, and the WALK→CHANGE reload.
