# Low-level design

This document describes the low-level design of the traffic-light controller.
It supplements the high-level design in `architecture.md` (the project
structure, the bus concept, and the core-loop concept live there) and sits
between it and the source. This design names every unit and its
responsibilities, and is the design baseline against which the low-level
requirements (`requirements/llr/`) are written.

Behavioral authority is unchanged by this document: the CONOPS and the HLRs
(`requirements/hlr/`) are normative for *what* the controller does; this
document is descriptive of *how* the software is organized to realize those
goals. The informative state-machine render in `requirements/state-machines.md`
shows the machines this design realizes.

## 1. Unit map

| Project | Unit | Files | Role |
|---|---|---|---|
| `types` | `States` | `src/types/states.ads` | Type vocabulary: signal alphabets, approach/crosswalk indices, machine-state enumerations, I/O aggregates, durations |
| `types` | `Buses` | `src/types/buses.{ads,adb}` | Generic source / display data buses |
| `core` | `Conflicts` | `src/core/conflicts.ads` | Conflict matrix and geometry bindings |
| `core` | `Controller` | `src/core/controller.{ads,adb}` | The four communicating Moore machines |
| `core` | `State_Machine_Loop` | `src/core/state_machine_loop.{ads,adb}` | The generic four-stage core loop |
| `core` | `State_Machine_Loop_Proof` | `src/core/state_machine_loop_proof.{ads,adb}` | Proof-only instantiation harness |
| `hal` | `Timings` | `src/hal/common/timings.ads` + per-profile bodies | Delay service |
| `hal` | `Sources` | `src/hal/common/sources.ads` + per-profile bodies | Producer of the input snapshot |
| `hal` | `Display` | `src/hal/common/display.ads` + per-profile bodies | Consumer of the output state |
| `app` | `Main` | `src/app/main.adb` | Bus wiring and loop instantiation |

The HAL bodies come in two profiles selected by `BUILD_KIND` (`src/hal/host`,
`src/hal/qemu_zynq7000`); their internals are simulation / bring-up detail and
are outside the scope of this design's requirement coverage. The shared HAL
*specs* are the contract surface the core relies on and are in scope.

## 2. Types layer (`States`)

`States` is a dependency-free leaf package: one home for every name the
other units share, so no alphabet, index, or duration is defined twice. The
value sets themselves — the signal literals, the index literals, the duration
valuations — are pinned per entity in `llr_1_states`; this section records the
decomposition into types and the representation decisions behind them, not the
literals.

- **Signal alphabets** — one enumeration per signal kind: the output alphabets
  `Vehicle_Face`, `Pedestrian_Head`, `Request_Indicator` and the input
  alphabets `Fault_Detection`, `Pedestrian_Button`, `Left_Turn_Detector`, each
  the value set of one `hlr_4_signals` signal. The alphabets carry signal
  values only: lens shape, pictographs, and blink realization are HAL symbology
  and appear nowhere in the core.
- **Instance indices** — `Approach` and `Crosswalk`. Per-instance machines are
  realized as arrays indexed by these types (`Left_Demand_Array`,
  `Pedestrian_Array`, and the per-instance fields of the I/O aggregates); an
  instance is an index, never an actor. The `Crosswalk` literals are named by
  the axis and side each serves, so the geometry rides in the index name
  (§4, `Adjacent_Through`).
- **Machine-state enumerations** — one per machine: `Mode`,
  `Left_Demand_State`, `Vehicle_Sequencer_State`, and `Pedestrian_State`. Two
  representation decisions live here. `Vehicle_Sequencer_State` is declared in
  cycle order — the NS block then its EW mirror — so the enumeration reads as
  the schedule. And the HLR's `SERVING_PEDESTRIAN_REQUEST` superstate is
  *flattened* into contiguous `Pedestrian_State` literals so the subtype
  `Serving_Pedestrian_State` can name the superstate as a range — the form the
  safety obligation `hlr_0_safety.1` is conditioned on and the controller's
  timers dispatch on.
- **I/O aggregates** — `Display_State` (every output-signal value: a through
  and a left face per approach, a head and a request indicator per crosswalk)
  and `Sensors_State` (every input-signal value: buttons, left-turn detectors,
  the fault line). Each crosses its bus in one shot.
- **The movement view** — `Movement`, `Face_Of`, and `Is_Go`. `Movement`
  enumerates the eight vehicle movements; `Face_Of` projects a `Display_State`
  onto a movement's face and `Is_Go` defines "releasing traffic". These exist
  so the safety invariant can quantify over movements independently of the
  `Display_State` record layout.
- **Durations** — `Duration_Ms`, all timing in logical milliseconds, and one
  named constant per `hlr_3_timing` duration. The valuations are provisional
  and deferred (`requirements/TODO.md`); `llr_1_states` fixes them and states
  the margin inequalities any re-valuation must preserve. `T_Both` is
  deliberately *not* a constant — it is the per-cycle residual computed by the
  controller (§5.4).

## 3. Buses (`Buses`)

Two generic packages, one instantiation per wire, each carrying one whole
aggregate in one direction (the boundary concept is `architecture.md` §Buses):

- `Source_Bus` — generic over the producer `Bus_Write`; exposes `Bus_Read`.
- `Display_Bus` — generic over the consumer `Bus_Read`; exposes `Bus_Write`.

The buses decouple the core from the details of the HALs.

## 4. Conflict and geometry layer (`Conflicts`)

`Conflicts` contains the definitions of the intersection relations the HLRs
leave quantified ("every conflicting movement", "the through parallel and
adjacent to that crosswalk").  It is a stand-alone package, not a child of
`Controller`; `Controller`'s contracts reference it.

- `Compatible (A, B)` / `Conflicts (A, B)` — the conflict matrix, stated
  positively (two movements are compatible when some sequencer row drives them
  non-RED together) and negated.
- `Safe_Faces (D)` — a predicate over a `Display_State`:
  no two conflicting movements are both `Is_Go`.
- `Next_Conflicting_Through (A)` — the per-approach binding for the left-demand
  clear.
- `Adjacent_Through (C)` — the per-crosswalk binding for the pedestrian service
  edge; the `Crosswalk` naming carries the geometry.

## 5. The controller (`Controller`)

`Controller` realizes all four kinds of communicating machine — supervisor,
vehicle sequencer, four left-demand machines, four pedestrian machines — in one
package. The machines communicate within a single step, avoiding globals and
cross-unit contracts.

The public surface is three subprograms — `Initialize`, `Project_Outputs`,
`Step` — over one record, `Controller_State`.

### 5.1 The composite state

```
Controller_State = record
   Mode      : Mode                      -- supervisor
   Vehicle   : Vehicle_Sequencer_State   -- sequencer
   Veh_Timer : Duration_Ms               -- time left in Vehicle
   Veh_Lag   : Boolean                   -- lag decision, latched on both-entry
   Left      : Left_Demand_Array         -- 4 × left-demand machine
   Ped       : Pedestrian_Array          -- 4 × pedestrian machine
   Ped_Timer : Pedestrian_Timers         -- 4 × time left in Ped sub-state
end record
```

All controller state lives here — no globals — and is threaded `in out`
through `Step`. The timers and `Veh_Lag` are the discrete-event bookkeeping
(§5.2): `Veh_Timer` runs whenever in NORMAL_OPERATION; `Ped_Timer (C)` runs
only while crosswalk `C` is in the SERVING superstate.

### 5.2 The discrete-event timing model

The controller is several concurrently timed machines with independent time
bases, so `Step` follows a min-time-to-next-event contract: it returns `Wait`,
the time to the nearest transition, and leaves the composite state as of the
end of that delay. The loop sleeps `Wait` and the next `Step` emits that state.

### 5.3 Moore output tables and `Project_Outputs`

`Project_Outputs` is the Moore output function — pure over `Controller_State`,
carrying the postcondition `Conflicts.Safe_Faces (Project_Outputs'Result)`. In
FAULT it returns the fault table; in NORMAL_OPERATION it assembles the vehicle
faces from `Vehicle_Face_Outputs` and each crosswalk's head and lamp from
`Head_Of` / `Request_Of`.

`Through_Face` projects one approach's through face out of the table; it is
the signal the GREEN-edge derivations watch (§5.7).

### 5.4 Vehicle sequencer transitions

`Advance_Vehicle` advances the sequencer state on timer expiry and reloads
`Veh_Timer` with the new state's dwell. Two functions supply the dwell:
`Fixed_Duration` for the fixed per-state dwells and `Both_Duration` for the
both-through residual `T_Both`. `Enter_Both` handles both-through entry, setting
`Veh_Timer` and the lag decision `Veh_Lag`.

### 5.5 Pedestrian transitions

`Advance_Ped` advances one crosswalk's SERVING sub-sequence on timer expiry.
`Running_Ped` is the predicate identifying the pedestrian sub-states that run a
timer (the `Serving_Pedestrian_State` superstate).

### 5.6 Input arming (level-triggered)

`Step` samples `Sensors_State` and arms the demand machines. Debounce and
electrical sensing stay HAL-side.

### 5.7 GREEN-edge derivations

After advancing the sequencer, `Step` derives the couplings between machines
off the vehicle through-face GREEN edges: clearing a served approach's left
demand, and entering a served crosswalk's WALK.

### 5.8 Step: order of stages

`Step (State, Sensors, Outputs, Wait)` is the step engine that composes the
above: fault pre-emption, input arming, output emission, and timer advance with
the edge derivations. `Fault_Dwell` is the constant wait `Step` reports in
FAULT, where there is no timed transition to schedule.

## 6. The core loop (`State_Machine_Loop`)

A generic `No_Return` procedure parameterized by the three HAL-side procedures
— `Delay_For`, `Read_Sources`, `Write_Display` — whose profiles match the HAL
surface and the bus sides one-for-one, so `app` instantiates it directly
against the wired buses. The body is the architecture's four stages, forever:

```
Controller.Initialize (State);
loop
   Read_Sources (Sensors);                            -- 1. poll
   Controller.Step (State, Sensors, Outputs, Wait);   -- 2. compute
   Write_Display (Outputs);                           -- 3. update
   Delay_For (Wait);                                  -- 4. wait
end loop;
```

## 7. HAL contract surface

The shared specs under `src/hal/common/` are the contract the core relies on;
the per-profile bodies (`host`, `qemu_zynq7000`) implement them and are out of
requirement scope.

- `Timings.Delay_For (Ms)` — waits the requested number of *logical*
  milliseconds; the wall-clock cost per logical millisecond is fixed at compile
  time by the `Timings.Tick_Config` child. The delay is per-call relative, no
  running deadline, matching the no-globals convention.
- `Sources.Sample (Value)` — samples the whole input surface into one
  `Sensors_State`; the source bus's producer profile.
- `Display.Show (S)` — renders a whole `Display_State` (console on host, UART0
  on target); the display bus's consumer profile. `Display.Initialize` brings
  the surface up; `Diag_Write_Line` is a bring-up diagnostic channel.

## 8. Application wiring (`Main`)

`Main` performs the one-time composition, all local, no globals:
instantiate `Buses.Source_Bus` with `Sources.Sample` as producer and
`Buses.Display_Bus` with `Display.Show` as consumer; instantiate
`State_Machine_Loop` against `Timings.Delay_For` and the two bus sides;
initialize the display; run the loop (which never returns).
