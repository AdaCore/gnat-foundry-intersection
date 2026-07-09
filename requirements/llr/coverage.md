# HLR → LLR coverage matrix (Rule 4)

Hand-maintained inverse of the LLR trace comments: every HLR statement and
the LLR statement(s) that refine it. Rule 4 (`engine/requirements/
LLR.drafting.md`) requires every row to be non-empty. Regenerate by
inspection of the `# -> hlr_…` trailing comments whenever an LLR file
changes; a `reqs` subcommand to automate this is future tooling
(`requirements/TODO.md`).

Status: **complete** — all 96 HLR statements are refined. Where a row lists
several LLR statements, the first is the primary refinement and the rest are
supporting (binding, engine plumbing, or a second entity that carries the
same obligation).

## hlr_0_safety

| HLR | Refined by | Note |
|---|---|---|
| 0_safety.1 | llr_1_states.27, llr_1_states.28; llr_1_states.15, llr_3_conflicts.5 | Discharged as the static margin over the valuation (the two inequalities); the SERVING subtype and the adjacent-through binding are what the obligation and its discharge quantify over. Derivation: llr_1_states `algorithm_aspects`. |
| 0_safety.2 | llr_4_controller.12, llr_4_controller.21; llr_3_conflicts.1–.3, llr_1_states.18–.20 | Encoded as the proven `Safe_Faces` postcondition; the predicate and movement view define it. |

## hlr_1_modes

| HLR | Refined by | Note |
|---|---|---|
| 1_modes.1 | llr_1_states.9; llr_4_controller.1 | |
| 1_modes.2 | llr_4_controller.2; llr_5_core_loop.1, llr_7_main.3/.4/.5 | |
| 1_modes.3 | llr_4_controller.13 | |
| 1_modes.4 | llr_4_controller.14, llr_4_controller.15; llr_5_core_loop.3 | Terminal by structure: no assignment leaves FAULT; the loop keeps driving the fault outputs. |

## hlr_2_fault

| HLR | Refined by |
|---|---|
| 2_fault.1 | llr_4_controller.6 |
| 2_fault.2 | llr_4_controller.7 |
| 2_fault.3 | llr_4_controller.8 |

## hlr_3_timing

| HLR | Refined by | Note |
|---|---|---|
| 3_timing.1 | llr_1_states.22 (repr. llr_1_states.21) | |
| 3_timing.2 | llr_1_states.23 | |
| 3_timing.3 | llr_1_states.24 | |
| 3_timing.4 | llr_1_states.25 | Provisional valuation; kinematic derivation deferred. |
| 3_timing.5 | llr_1_states.25 | Provisional. |
| 3_timing.6 | llr_1_states.25 | Provisional. |
| 3_timing.7 | llr_4_controller_1_vehicle.24, .25, .28, .29, .38, .39, .42, .43 | Demand-independence: the eight both-through entries load the residual that holds T_AXIS constant. |
| 3_timing.8 | llr_4_controller_1_vehicle.24, .25, .28, .29, .38, .39, .42, .43 | The both-through residual, per lead/lag case. |
| 3_timing.9 | llr_1_states.26 | |
| 3_timing.10 | llr_1_states.27, llr_1_states.28 | The static margin as valuation constraints; both hold (16 ≥ 16 tight; 28 ≥ 16). |
| 3_timing.11 | llr_4_controller_1_vehicle.2; llr_4_controller.17–.18, llr_5_core_loop.3, llr_6_hal.1 | No-gap-out premise plus the elapse machinery it rests on. |
| 3_timing.12 | llr_1_states.29 | Valuation constraint (the worst-case residual holds at or above T_BOTH_MIN). |

## hlr_4_signals

| HLR | Refined by | Note |
|---|---|---|
| 4_signals.1 | llr_1_states.1; llr_1_states.16, llr_1_states.19, llr_2_buses.3, llr_4_controller.9/.16, llr_6_hal.3, llr_7_main.2 | Alphabet; then the aggregate, movement view (19), transport, projection (9), emit (16), rendering, and wiring of the signal. |
| 4_signals.2 | llr_1_states.2; llr_4_controller.10 (projection), else the 4_signals.1 chain | |
| 4_signals.3 | llr_1_states.3; llr_4_controller.11 (projection), else the 4_signals.1 chain | |
| 4_signals.4 | llr_1_states.4; llr_1_states.17, llr_2_buses.1, llr_6_hal.2, llr_7_main.1 | |
| 4_signals.5 | llr_1_states.5; same supporting chain | |
| 4_signals.6 | llr_1_states.6; same supporting chain | |

## hlr_5_vehicle

| HLR | Refined by | Note |
|---|---|---|
| 5_vehicle.1 | llr_4_controller_1_vehicle.1 (jointly: .23–.36); llr_1_states.12 | Visit order is a structural property of the transition set. |
| 5_vehicle.2 – .11 | llr_4_controller_1_vehicle.3 – .12 (in order) | NS output rows, one-for-one. |
| 5_vehicle.12 | llr_4_controller_1_vehicle.23 | NS: barrier → N_LEAD. |
| 5_vehicle.13 | llr_4_controller_1_vehicle.24, .25 | Both-through entry, split on the SOUTH lag approach. |
| 5_vehicle.14 – .15 | llr_4_controller_1_vehicle.26 – .27 (in order) | |
| 5_vehicle.16 | llr_4_controller_1_vehicle.28, .29 | Both-through entry, split on the SOUTH lag approach. |
| 5_vehicle.17 | llr_4_controller_1_vehicle.30; entries .24, .28 | Exit routes on the Veh_Lag latched by the entries. |
| 5_vehicle.18 | llr_4_controller_1_vehicle.31; entries .25, .29 | |
| 5_vehicle.19 – .23 | llr_4_controller_1_vehicle.32 – .36 (in order) | NS transitions. |
| 5_vehicle.24 | llr_4_controller_1_vehicle.1 (jointly: .37–.50); llr_1_states.12 | |
| 5_vehicle.25 – .34 | llr_4_controller_1_vehicle.13 – .22 (in order) | EW output rows, one-for-one. |
| 5_vehicle.35 | llr_4_controller_1_vehicle.37 | EW: barrier → E_LEAD. |
| 5_vehicle.36 | llr_4_controller_1_vehicle.38, .39 | Both-through entry, split on the WEST lag approach. |
| 5_vehicle.37 – .38 | llr_4_controller_1_vehicle.40 – .41 (in order) | |
| 5_vehicle.39 | llr_4_controller_1_vehicle.42, .43 | Both-through entry, split on the WEST lag approach. |
| 5_vehicle.40 | llr_4_controller_1_vehicle.44; entries .38, .42 | Exit routes on the Veh_Lag latched by the entries. |
| 5_vehicle.41 | llr_4_controller_1_vehicle.45; entries .39, .43 | |
| 5_vehicle.42 – .46 | llr_4_controller_1_vehicle.46 – .50 (in order) | EW transitions. |
| 5_vehicle.47 | llr_4_controller.3 | Power-on entry. |

## hlr_5_vehicle_1_left_demand

| HLR | Refined by |
|---|---|
| 5_vehicle_1_left_demand.1 | llr_1_states.10, .11 (index: .7); llr_4_controller.1 |
| 5_vehicle_1_left_demand.2 | llr_4_controller.4 |
| 5_vehicle_1_left_demand.3 | llr_4_controller_2_left_demand.1, .2 |
| 5_vehicle_1_left_demand.4 | llr_4_controller_2_left_demand.3; llr_3_conflicts.4, llr_4_controller.19 |

## hlr_6_pedestrian

| HLR | Refined by |
|---|---|
| 6_pedestrian.1 | llr_1_states.13, .14, .15 (index: .8); llr_4_controller.1 |
| 6_pedestrian.2 | llr_4_controller.5 |
| 6_pedestrian.3 | llr_4_controller_3_pedestrian.1 |
| 6_pedestrian.4 | llr_4_controller_3_pedestrian.6 |
| 6_pedestrian.5 | llr_4_controller_3_pedestrian.10 |
| 6_pedestrian.6 | llr_4_controller_3_pedestrian.2 |
| 6_pedestrian.7 | llr_4_controller_3_pedestrian.7 |
| 6_pedestrian.8 | llr_4_controller_3_pedestrian.12; llr_3_conflicts.5, llr_4_controller.20 |
| 6_pedestrian.9 | llr_4_controller_3_pedestrian.8 |
| 6_pedestrian.10 | llr_4_controller_3_pedestrian.3 |
| 6_pedestrian.11 | llr_4_controller_3_pedestrian.4 |
| 6_pedestrian.12 | llr_4_controller_3_pedestrian.13 (timer discipline: .17) |
| 6_pedestrian.13 | llr_4_controller_3_pedestrian.14 (timer discipline: .17) |
| 6_pedestrian.14 | llr_4_controller_3_pedestrian.5 |
| 6_pedestrian.15 | llr_4_controller_3_pedestrian.11 |
| 6_pedestrian.16 | llr_4_controller_3_pedestrian.9 |
| 6_pedestrian.17 | llr_4_controller_3_pedestrian.15 (timer discipline: .17) |
| 6_pedestrian.18 | llr_4_controller_3_pedestrian.16 (timer discipline: .17) |
