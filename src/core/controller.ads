--  The traffic-light controller: the communicating Moore state machines that
--  compute the next state and project the signal outputs. This is the
--  "replacement for the conflict_check module" (design/architecture.md
--  §Project structure) and the main SPARK proof target.
--
--  It realizes, from the HLR YAML in `requirements/hlr/` (the single source of
--  truth) and the informative render in `requirements/state-machines.md`, five
--  communicating machines:
--    * the supervisor / modes machine (`hlr_1_modes`, `hlr_2_fault`),
--    * the vehicle phase sequencer (`hlr_5_vehicle`),
--    * the four left-turn demand machines (`hlr_5_vehicle_1_left_demand`), and
--    * the four pedestrian crosswalk machines (`hlr_6_pedestrian`).
--
--  Being non-generic, it needs no instantiation harness of its own: it
--  contributes proof obligations to `make prove` as soon as it is in the
--  project closure (via the core loop, exercised by State_Machine_Loop_Proof).
--
--  == Concurrency / timing model (jeeves plan Q1, agreed) ==
--
--  The architecture's core loop applies exactly one `Delay_For` per iteration,
--  but the controller is nine concurrent timed machines (one sequencer + four
--  pedestrian services) with independent time bases -- a pedestrian service
--  (T_WALK + T_FDW + T_BUFFER = 16 s) spans several vehicle states, and each
--  crosswalk can be at a different phase. So "the delay required by the current
--  state" is read as a **discrete-event, min-time-to-next-event** model: each
--  timed machine carries the time left in its current state; `Step` emits the
--  current composite state's outputs, returns `Wait` = the minimum of those
--  remaining times (the nearest transition), and advances every machine by
--  `Wait`, firing whichever transitions come due. Input edges landing between
--  wake-ups are held by the source bus's coalescing latch
--  (design/architecture.md §Buses) and serviced at the next wake, so the model
--  never misses a timed transition and never drops an input; worst-case input
--  latency is one inter-event interval, which the coalescing design sanctions.
--
--  == Safety invariants (`hlr_0_safety`) ==
--
--  * `hlr_0_safety.2` (no two conflicting movements GREEN/YELLOW at once) is
--    encoded as the `Conflicts.Safe_Faces` postcondition on `Project_Outputs`
--    (hence on `Step`'s outputs). It holds by construction -- each Moore output
--    row drives only a compatible face set -- and gnatprove discharges it by
--    enumeration over the literal aggregates.
--  * `hlr_0_safety.1` (SERVING => conflicting movements RED) is *not* a
--    per-state property: it is discharged as the static timing margin
--    `hlr_3_timing.10` (a property over the whole schedule and the chosen
--    durations), which `requirements/TODO.md` tracks as a coupled LLR item.
--    It is therefore deliberately NOT encoded as a runtime contract here; doing
--    so would require an escape hatch (`pragma Assume` / suppressed checks) that
--    `CLAUDE.md` forbids. This is the expected, flagged deferral, not a hole.

with States;
with Conflicts;

package Controller
  with SPARK_Mode => On
is

   --  Per-crosswalk remaining time in the current pedestrian sub-state; 0 and
   --  unused while the crosswalk is in NO_PEDESTRIAN_REQUEST or
   --  PENDING_PEDESTRIAN_REQUEST (those sub-states carry no timer).
   type Pedestrian_Timers is array (States.Crosswalk) of States.Duration_Ms;

   --  The whole controller state -- the composite state of the five machines
   --  plus their discrete-event timers. No globals (design/architecture.md
   --  §Code conventions): all state lives here and is threaded `in out`.
   type Controller_State is record
      Mode      : States.Mode;                     --  hlr_1_modes
      Vehicle   : States.Vehicle_Sequencer_State;  --  hlr_5_vehicle
      Veh_Timer : States.Duration_Ms;              --  time left in Vehicle
      Veh_Lag   : Boolean;                          --  lag-served decision,
      --    latched on both-entry
      Left      : States.Left_Demand_Array;        --  hlr_5_vehicle_1
      Ped       : States.Pedestrian_Array;          --  hlr_6_pedestrian
      Ped_Timer : Pedestrian_Timers;               --  time left in Ped (c)
   end record;

   --  Power-on state (the Derived initialization statements): mode
   --  NORMAL_OPERATION (`hlr_1_modes.2`), the sequencer in EW_BARRIER_ALLRED
   --  (`hlr_5_vehicle.47`), every approach NO_LEFT_DEMAND
   --  (`hlr_5_vehicle_1_left_demand.2`), every crosswalk NO_PEDESTRIAN_REQUEST
   --  (`hlr_6_pedestrian.2`), and the barrier timer armed.
   procedure Initialize (State : out Controller_State);

   --  Project the composite state to the display-bus payload -- a pure Moore
   --  output function (`hlr_2_fault`, `hlr_5_vehicle` output rows,
   --  `hlr_6_pedestrian` head / lamp rows). Total and literal per state so the
   --  hlr_0_safety.2 postcondition discharges by enumeration.
   function Project_Outputs
     (State : Controller_State) return States.Display_State
   with Post => Conflicts.Safe_Faces (Project_Outputs'Result);

   --  One core-loop step: emit the current composite state's outputs, report
   --  the delay to remain in it (`Wait`, the min time to the next event), and
   --  advance every machine by that delay -- ready for the next call. The
   --  emitted outputs honour the vehicle-conflict invariant hlr_0_safety.2.
   procedure Step
     (State   : in out Controller_State;
      Sensors : States.Sensors_State;
      Outputs : out States.Display_State;
      Wait    : out States.Duration_Ms)
   with Post => Conflicts.Safe_Faces (Outputs);

end Controller;
