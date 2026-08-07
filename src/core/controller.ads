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
--  == Concurrency / timing model ==
--
--  The controller is nine concurrent timed machines (one sequencer + four
--  pedestrian services) with independent time bases -- a pedestrian service
--  (T_WALK + T_FDW + T_BUFFER = 16 s) spans several vehicle states, and each
--  crosswalk can be at a different phase. The model is the **fixed-cadence
--  sampled** one (llr_4_controller context, design/architecture.md §"Sampled
--  cadence and the acknowledgment chain"): each timed machine carries the
--  time left in its current state in Controller_State, and each `Step`
--  accounts for exactly one sampling period States.T_Sample of logical time.
--  The cadence lives in the core loop -- which sleeps exactly T_SAMPLE every
--  iteration -- while the timers live here; Step returns no timing value.
--  Timed boundaries stay exact under the fixed advance because every dwell
--  is an integral multiple of T_SAMPLE (llr_1_states.31): a machine fires
--  its timed transition on the step where its remaining dwell is at most
--  T_SAMPLE, which is precisely its boundary. The intervening steps are pure
--  sampling steps (nothing fires; every running timer is decremented; the
--  unchanged Moore outputs are re-emitted). Input edges landing between
--  wake-ups are held by the source bus's coalescing latch
--  (design/architecture.md §Buses) and serviced at the next step, so the
--  model never misses a timed transition and never drops an input;
--  worst-case input latency is one sampling period, which realizes the T_ACK
--  acknowledgment bound (`hlr_3_timing.13`).
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

   --  Operator visibility for the frame contract on Step below; no names are
   --  imported beyond the predefined operators of these four types.
   use type States.Duration_Ms;
   use type States.Fault_Detection;
   use type States.Mode;
   use type States.Vehicle_Sequencer_State;

   type Pedestrian_Timers is array (States.Crosswalk) of States.Duration_Ms;
   --  Per-crosswalk remaining time in the current pedestrian sub-state; 0 and
   --  unused while the crosswalk is in NO_PEDESTRIAN_REQUEST or
   --  PENDING_PEDESTRIAN_REQUEST (those sub-states carry no timer).

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
   --  The whole controller state -- the composite state of the five machines
   --  plus their discrete-event timers. No globals (design/architecture.md
   --  §Code conventions): all state lives here and is threaded `in out`.

   procedure Initialize (State : out Controller_State);
   --  Power-on state (the Derived initialization statements): mode
   --  NORMAL_OPERATION (`hlr_1_modes.2`), the sequencer in EW_BARRIER_ALLRED
   --  (`hlr_5_vehicle.47`), every approach NO_LEFT_DEMAND
   --  (`hlr_5_vehicle_1_left_demand.2`), every crosswalk NO_PEDESTRIAN_REQUEST
   --  (`hlr_6_pedestrian.2`), and the barrier timer armed.
   --  @param State The controller state, set to its power-on value

   function Project_Outputs
     (State : Controller_State)
      return States.Display_State
             --@covers llr_4_controller.12
   with Post => Conflicts.Safe_Faces (Project_Outputs'Result);
   --  Project the composite state to the display-bus payload -- a pure Moore
   --  output function (`hlr_2_fault`, `hlr_5_vehicle` output rows,
   --  `hlr_6_pedestrian` head / lamp rows). Total and literal per state so the
   --  hlr_0_safety.2 postcondition discharges by enumeration.
   --  @param State The controller state to project
   --  @return The display-bus payload for that state

   procedure Step
     (State   : in out Controller_State;
      Sensors : States.Sensors_State;
      Outputs : out States.Display_State)
     --@covers llr_4_controller.21, llr_4_controller_1_vehicle.1
     --@covers llr_4_controller_1_vehicle.2
   with
     Post =>
       Conflicts.Safe_Faces (Outputs)
       and then (if State'Old.Mode = States.Fault
                   or else Sensors.Fault = States.Asserted
                   or else State'Old.Veh_Timer > States.T_Sample
                 then State.Vehicle = State'Old.Vehicle);
   --  The frame of the vehicle sequencer
   --  (`llr_4_controller_1_vehicle.1`/`.2`, `llr_4_controller.15`): a step
   --  moves State.Vehicle only on the one branch that calls Advance_Vehicle,
   --  so it holds the sequencer whenever the step is pre-empted by FAULT or
   --  the current state's dwell has more than one sampling period left. This
   --  is the provable content of "assigns State.Vehicle only in
   --  Advance_Vehicle": nothing else Step does can move it, quantified over
   --  every state and every timer value rather than sampled. A test can only
   --  show the sequencer held at the timer values it picks.
   --
   --  One core-loop step, accounting for exactly one sampling period
   --  T_SAMPLE of logical time (llr_4_controller.17): arm the freshly
   --  sampled inputs, then advance every running timer (Veh_Timer; each
   --  serving Ped_Timer) by exactly T_SAMPLE, firing the timed transition of
   --  any machine whose remaining dwell is at most T_SAMPLE -- the step on
   --  whose boundary that dwell elapses, exact by llr_1_states.31 -- then
   --  derive the GREEN edges, and emit last. Outputs is therefore the Moore
   --  projection of the state the step results in (llr_4_controller.16). The
   --  emitted outputs honour the vehicle-conflict invariant hlr_0_safety.2.
   --  @param State The controller state, advanced in place by this step
   --  @param Sensors The input snapshot sampled for this step
   --  @param Outputs The output signals emitted for the state this step
   --  results in

end Controller;
