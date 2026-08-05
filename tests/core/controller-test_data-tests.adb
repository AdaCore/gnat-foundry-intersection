--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Controller.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

--  begin read only
--  end read only
package body Controller.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Initialize (Gnattest_T : in out Test);
   procedure Test_Initialize_9cb2dc (Gnattest_T : in out Test) renames Test_Initialize;
--  id:2.2/9cb2dc2f1d1660db/Initialize/1/0/
   procedure Test_Initialize (Gnattest_T : in out Test) is
   --  controller.ads:83:4:Initialize
--  end read only

      --@covers none: unattributed controller scenario, retained for
      --  regression coverage while the per-requirement tests under
      --  tests/reqs/ are written (#51). Claims no requirement.

      pragma Unreferenced (Gnattest_T);

      use States;

      State : Controller_State;

   begin

      Initialize (State);

      --  Power-on mode (llr_4_controller.2, hlr_1_modes.2).

      Assert
        (State.Mode = Normal_Operation,
         "power-on should enter NORMAL_OPERATION");

      --  Power-on sequencer state (llr_4_controller.3, hlr_5_vehicle.47):
      --  EW_BARRIER_ALLRED with the barrier timer armed to its full dwell.

      Assert
        (State.Vehicle = EW_Barrier_Allred,
         "power-on should put the sequencer in EW_BARRIER_ALLRED");
      Assert
        (State.Veh_Timer = T_Barrier,
         "power-on should arm the barrier timer to T_BARRIER");

      --  No latched left demand (llr_4_controller.4).

      Assert
        ((for all A in Approach => State.Left (A) = No_Left_Demand),
         "power-on should latch no left demand on any approach");

      --  No pedestrian request, no running pedestrian timer
      --  (llr_4_controller.5).

      Assert
        ((for all C in Crosswalk => State.Ped (C) = No_Pedestrian_Request),
         "power-on should leave every crosswalk idle");
      Assert
        ((for all C in Crosswalk => State.Ped_Timer (C) = 0),
         "power-on should zero every pedestrian timer");

--  begin read only
   end Test_Initialize;
--  end read only


--  begin read only
   procedure Test_Project_Outputs (Gnattest_T : in out Test);
   procedure Test_Project_Outputs_229f82 (Gnattest_T : in out Test) renames Test_Project_Outputs;
--  id:2.2/229f82fac868336c/Project_Outputs/1/0/
   procedure Test_Project_Outputs (Gnattest_T : in out Test) is
   --  controller.ads:91:4:Project_Outputs
--  end read only

      --@covers none: unattributed controller scenario, retained for
      --  regression coverage while the per-requirement tests under
      --  tests/reqs/ are written (#51). Claims no requirement.

      pragma Unreferenced (Gnattest_T);

      use States;

      --  A composite state with every machine off its power-on value: the
      --  sequencer serving the NS both-through, a latched West left demand,
      --  and the four crosswalks in four distinct pedestrian sub-states.
      --  Controller_State is a public record, so tests build states
      --  directly. The timers are irrelevant to the pure Moore projection.
      Busy : constant Controller_State :=
        (Mode      => Normal_Operation,
         Vehicle   => NS_Both_Through,
         Veh_Timer => T_Both_Min,
         Veh_Lag   => False,
         Left      => (West => Left_Demand_Pending, others => No_Left_Demand),
         Ped       =>
           (North_Side => Buffer_Interval_Latched,
            South_Side => Pending_Pedestrian_Request,
            East_Side  => Walk_Interval,
            West_Side  => Change_Interval),
         Ped_Timer => (others => 0));

      State   : Controller_State;
      Outputs : Display_State;

   begin

      --  FAULT projection (llr_4_controller.6/.7/.8): every through and
      --  left face FLASHING_RED, every pedestrian head dark (NONE), every
      --  request lamp NO_REQUEST -- regardless of the sub-machine states.

      State := Busy;
      State.Mode := Fault;

      Outputs := Project_Outputs (State);

      Assert
        ((for all A in Approach =>
            Outputs.Through (A) = Flashing_Red
            and then Outputs.Left (A) = Flashing_Red),
         "FAULT should project FLASHING_RED on every vehicle face");
      Assert
        ((for all C in Crosswalk => Outputs.Heads (C) = None),
         "FAULT should project a dark (NONE) head on every crosswalk");
      Assert
        ((for all C in Crosswalk => Outputs.Requests (C) = No_Request),
         "FAULT should project NO_REQUEST on every request lamp");

      --  NORMAL_OPERATION vehicle faces (llr_4_controller.9): the Moore
      --  output row of the sequencer state. NS_BOTH_THROUGH drives the two
      --  NS throughs GREEN and every other face RED
      --  (llr_4_controller_1_vehicle) -- the latched left demand is not an
      --  output.

      Outputs := Project_Outputs (Busy);

      Assert
        (Outputs.Through (North) = Green
         and then Outputs.Through (South) = Green
         and then Outputs.Through (East) = Red
         and then Outputs.Through (West) = Red,
         "NS_BOTH_THROUGH should drive the NS throughs GREEN, the EW"
         & " throughs RED");
      Assert
        ((for all A in Approach => Outputs.Left (A) = Red),
         "NS_BOTH_THROUGH should drive every left face RED");

      --  NORMAL_OPERATION pedestrian heads (llr_4_controller.10): Head_Of
      --  per sub-state -- WALK, flashing DONT WALK, and steady DONT WALK
      --  for PENDING and the buffer.

      Assert
        (Outputs.Heads (East_Side) = Walk,
         "WALK_INTERVAL should project the WALK head");
      Assert
        (Outputs.Heads (West_Side) = Flash_Dont_Walk,
         "CHANGE_INTERVAL should project the flashing DONT WALK head");
      Assert
        (Outputs.Heads (South_Side) = Dont_Walk,
         "PENDING_PEDESTRIAN_REQUEST should project the DONT WALK head");
      Assert
        (Outputs.Heads (North_Side) = Dont_Walk,
         "BUFFER_INTERVAL_LATCHED should project the DONT WALK head");

      --  NORMAL_OPERATION request lamps (llr_4_controller.11): Request_Of
      --  per sub-state -- lit exactly for PENDING and the latched buffer.

      Assert
        (Outputs.Requests (South_Side) = Request_Pending
         and then Outputs.Requests (North_Side) = Request_Pending,
         "PENDING and BUFFER_INTERVAL_LATCHED should light the request"
         & " lamp");
      Assert
        (Outputs.Requests (East_Side) = No_Request
         and then Outputs.Requests (West_Side) = No_Request,
         "a crosswalk being served should not light the request lamp");

      --  A lead/lag row (llr_4_controller.9, llr_4_controller_1_vehicle):
      --  W_LAG_YELLOW drives the West through and West left YELLOW
      --  together, every other face RED.

      State := Busy;
      State.Vehicle := W_Lag_Yellow;

      Outputs := Project_Outputs (State);

      Assert
        (Outputs.Through (West) = Yellow
         and then Outputs.Left (West) = Yellow
         and then (for all A in Approach =>
                     (A = West
                      or else (Outputs.Through (A) = Red
                               and then Outputs.Left (A) = Red))),
         "W_LAG_YELLOW should drive the West through and left YELLOW,"
         & " every other face RED");

--  begin read only
   end Test_Project_Outputs;
--  end read only


--  begin read only
   procedure Test_Step (Gnattest_T : in out Test);
   procedure Test_Step_550f0c (Gnattest_T : in out Test) renames Test_Step;
--  id:2.2/550f0cec4ac973af/Step/1/0/
   procedure Test_Step (Gnattest_T : in out Test) is
   --  controller.ads:101:4:Step
--  end read only

      --@covers none: unattributed controller scenario, retained for
      --  regression coverage while the per-requirement tests under
      --  tests/reqs/ are written (#51). Claims no requirement.

      pragma Unreferenced (Gnattest_T);

      use States;

      --  The all-inactive input snapshot: no presses, no vehicles, no fault.
      Quiet : constant Sensors_State :=
        (Buttons    => (others => Released),
         Left_Turns => (others => No_Vehicle),
         Fault      => Not_Asserted);

      --  A mid-dwell NORMAL_OPERATION state: the power-on barrier state with
      --  a caller-chosen vehicle dwell remainder and every other machine
      --  idle. Controller_State is a public record, so tests build mid-dwell
      --  states directly instead of stepping their way there.
      function Barrier_State (Remaining : Duration_Ms) return Controller_State
      is ((Mode      => Normal_Operation,
           Vehicle   => EW_Barrier_Allred,
           Veh_Timer => Remaining,
           Veh_Lag   => False,
           Left      => (others => No_Left_Demand),
           Ped       => (others => No_Pedestrian_Request),
           Ped_Timer => (others => 0)));

      --  The Moore outputs of the power-on barrier state: all faces RED,
      --  all heads DONT WALK, all lamps NO_REQUEST.
      Barrier_Outputs : constant Display_State :=
        (Through  => (others => Red),
         Left     => (others => Red),
         Heads    => (others => Dont_Walk),
         Requests => (others => No_Request));

      --  The FAULT outputs (hlr_2_fault.1/.2/.3): all faces FLASHING_RED,
      --  all heads dark, all lamps NO_REQUEST.
      Fault_Outputs : constant Display_State :=
        (Through  => (others => Flashing_Red),
         Left     => (others => Flashing_Red),
         Heads    => (others => None),
         Requests => (others => No_Request));

      State   : Controller_State;
      Outputs : Display_State;

   begin

      --  T_SAMPLE valuation (llr_1_states.30): 100 ms, and the
      --  acknowledgment budget 2 x T_SAMPLE <= T_ACK = 200 ms
      --  (hlr_3_timing.13) -- one period of worst-case latch-to-read
      --  latency plus one period of margin.

      Assert (T_Sample = 100, "T_SAMPLE should be valued at 100 ms");

      Assert
        (2 * T_Sample <= 200,
         "2 x T_SAMPLE should fit the T_ACK = 200 ms budget");

      --  Dwell granularity (llr_1_states.31): every dwell valuation is an
      --  integral multiple of T_SAMPLE -- so every timed boundary falls
      --  exactly on a sampling boundary, and the fixed T_SAMPLE advance
      --  drifts nothing. (Anchored statically by the Compile_Time_Error
      --  pragmas in states.ads; pinned here at value level.)

      Assert
        (T_Walk mod T_Sample = 0
         and then T_FDW mod T_Sample = 0
         and then T_Buffer mod T_Sample = 0
         and then T_Yellow mod T_Sample = 0
         and then T_Redclear mod T_Sample = 0
         and then T_Barrier mod T_Sample = 0
         and then T_Axis mod T_Sample = 0
         and then T_Lead mod T_Sample = 0
         and then T_Lag mod T_Sample = 0
         and then T_Both_Min mod T_Sample = 0,
         "every dwell valuation should be an integral multiple of"
         & " T_SAMPLE");

      --  Pure sampling step (llr_4_controller.17): right after power-on the
      --  barrier dwell (T_BARRIER) exceeds T_SAMPLE, so a quiet Step
      --  decrements the vehicle timer by exactly T_SAMPLE and fires no
      --  transition; the next quiet Step re-emits identical Moore outputs.

      declare
         First, Second : Display_State;
      begin
         Initialize (State);

         Step (State, Quiet, First);

         Assert
           (State.Vehicle = EW_Barrier_Allred,
            "a pure sampling step should fire no vehicle transition");
         Assert
           (State.Veh_Timer = T_Barrier - T_Sample,
            "a pure sampling step should decrement the vehicle timer"
            & " by exactly T_SAMPLE");
         Assert
           (First = Barrier_Outputs,
            "the barrier state's Moore outputs should be emitted");

         Step (State, Quiet, Second);

         Assert
           (Second = First,
            "pure sampling steps should re-emit identical outputs");
         Assert
           (State.Veh_Timer = T_Barrier - 2 * T_Sample,
            "each pure sampling step should decrement the vehicle timer"
            & " by exactly T_SAMPLE");
      end;

      --  Boundary firing (llr_4_controller.17/.18): with a two-sample dwell
      --  remainder, the first Step is a pure sampling step leaving exactly
      --  one T_SAMPLE of dwell, and the second Step fires the boundary
      --  exactly -- every dwell being a multiple of T_SAMPLE
      --  (llr_1_states.31), the boundary falls on a sampling boundary.

      State := Barrier_State (2 * T_Sample);

      Step (State, Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Barrier_Allred
         and then State.Veh_Timer = T_Sample,
         "the pure sampling step should leave one T_SAMPLE of dwell"
         & " unfired");
      Assert
        (Outputs = Barrier_Outputs,
         "the pure sampling step should re-emit the barrier outputs");

      Step (State, Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "the dwell boundary should fire on the step where the remaining"
         & " dwell is T_SAMPLE (EW barrier -> NS both-through, no left"
         & " demand)");
      Assert
        (Outputs = Barrier_Outputs,
         "the boundary step still emits the pre-boundary Moore outputs");

      Step (State, Quiet, Outputs);

      Assert
        (Outputs.Through (North) = Green
         and then Outputs.Through (South) = Green,
         "the step after the boundary should emit the new state's outputs");

      --  Boundary exactness (llr_4_controller.16/.17): from power-on, each
      --  Step accounts for exactly T_SAMPLE, so the steps to leave the
      --  barrier sum to the barrier dwell exactly -- the fixed cadence
      --  moves no timed boundary.

      declare
         Total : Duration_Ms := 0;
         Steps : Natural := 0;
      begin
         Initialize (State);

         while State.Vehicle = EW_Barrier_Allred and then Steps < 100 loop
            Step (State, Quiet, Outputs);
            Total := Total + T_Sample;
            Steps := Steps + 1;
         end loop;

         Assert
           (State.Vehicle = NS_Both_Through,
            "the barrier boundary should fire (EW barrier ->"
            & " NS both-through, no left demand)");
         Assert
           (Total = T_Barrier,
            "the summed sampling periods should hit the barrier dwell"
            & " exactly");
      end;

      --  FAULT (llr_4_controller.15): entering FAULT emits the fault
      --  outputs; FAULT is terminal, later Steps re-emit the same outputs
      --  with no sub-machine movement.

      declare
         Faulty : Sensors_State := Quiet;
      begin
         Faulty.Fault := Asserted;

         Initialize (State);
         Step (State, Faulty, Outputs);

         Assert
           (State.Mode = Fault, "an asserted fault line should enter FAULT");
         Assert
           (Outputs = Fault_Outputs,
            "the FAULT Step should emit the fault outputs");

         Step (State, Quiet, Outputs);

         Assert
           (State.Mode = Fault,
            "FAULT should be terminal even with the fault line dropped");
         Assert
           (Outputs = Fault_Outputs,
            "later FAULT Steps should re-emit the fault outputs");
         Assert
           (State.Veh_Timer = T_Barrier,
            "FAULT Steps should not advance any NORMAL_OPERATION"
            & " sub-machine");
      end;

      --  Press mid-dwell (hlr_6_pedestrian.5, hlr_3_timing.13): a button
      --  press sampled mid-dwell arms NO_REQUEST -> PENDING and lights the
      --  crosswalk's REQUEST_PENDING lamp on that very Step. Under the
      --  fixed cadence a press waits at most one T_SAMPLE for the next
      --  sampling step, which arms it and writes the lit lamp in the same
      --  iteration: within T_ACK = 2 x T_SAMPLE = 200 ms.

      declare
         Pressing : Sensors_State := Quiet;
      begin
         Pressing.Buttons (East_Side) := Pressed;

         Initialize (State);
         Step (State, Quiet, Outputs);  --  now mid-dwell

         Step (State, Pressing, Outputs);

         Assert
           (State.Ped (East_Side) = Pending_Pedestrian_Request,
            "a press sampled mid-dwell should arm the crosswalk to PENDING");
         Assert
           (Outputs.Requests (East_Side) = Request_Pending,
            "the same Step should light the REQUEST_PENDING lamp");
         Assert
           (Outputs.Requests (North_Side) = No_Request
            and then Outputs.Requests (South_Side) = No_Request
            and then Outputs.Requests (West_Side) = No_Request,
            "only the pressed crosswalk's lamp should light");
      end;

      --  Buffer-press mirror (hlr_6_pedestrian.15/.16): a press sampled
      --  while the crosswalk is in BUFFER_INTERVAL latches
      --  BUFFER_INTERVAL_LATCHED and lights the lamp on the same Step; the
      --  serving timer keeps running, decremented by T_SAMPLE.

      declare
         Pressing : Sensors_State := Quiet;
      begin
         Pressing.Buttons (East_Side) := Pressed;

         State := Barrier_State (2_000);
         State.Ped (East_Side) := Buffer_Interval;
         State.Ped_Timer (East_Side) := 500;

         Step (State, Pressing, Outputs);

         Assert
           (State.Ped (East_Side) = Buffer_Interval_Latched,
            "a press sampled in BUFFER_INTERVAL should latch"
            & " BUFFER_INTERVAL_LATCHED");
         Assert
           (Outputs.Requests (East_Side) = Request_Pending,
            "the latched buffer press should light the lamp on the"
            & " same Step");
         Assert
           (State.Ped_Timer (East_Side) = 500 - T_Sample,
            "the serving pedestrian timer should decrement by T_SAMPLE"
            & " without firing");
      end;

      --  A serving pedestrian timer at exactly one T_SAMPLE fires its
      --  boundary on this step (llr_4_controller.17/.18): WALK -> CHANGE
      --  exactly, the boundary step still emits the WALK head, and the
      --  vehicle timer advances by the same T_SAMPLE.

      State := Barrier_State (2_000);
      State.Ped (East_Side) := Walk_Interval;
      State.Ped_Timer (East_Side) := T_Sample;

      Step (State, Quiet, Outputs);

      Assert
        (Outputs.Heads (East_Side) = Walk,
         "the boundary step still emits the WALK head");
      Assert
        (State.Ped (East_Side) = Change_Interval
         and then State.Ped_Timer (East_Side) = T_FDW,
         "the pedestrian boundary should fire exactly"
         & " (WALK -> CHANGE, timer reloaded to T_FDW)");
      Assert
        (State.Veh_Timer = 2_000 - T_Sample,
         "the vehicle timer should advance by the same T_SAMPLE");

      Step (State, Quiet, Outputs);

      Assert
        (Outputs.Heads (East_Side) = Flash_Dont_Walk,
         "the step after the boundary should emit the new sub-state's"
         & " CHANGE head");

      --  Pedestrian boundary exactness (llr_4_controller.17/.18): a WALK
      --  interval armed with its full dwell consumes exactly T_WALK of
      --  sampled time before firing, one T_SAMPLE per step; and a crosswalk
      --  outside the SERVING superstate runs no timer -- the per-step
      --  advance must leave a PENDING crosswalk untouched.

      declare
         Total : Duration_Ms := 0;
         Steps : Natural := 0;
      begin
         State := Barrier_State (T_Barrier);
         State.Ped (East_Side) := Walk_Interval;
         State.Ped_Timer (East_Side) := T_Walk;
         State.Ped (South_Side) := Pending_Pedestrian_Request;

         while State.Ped (East_Side) = Walk_Interval and then Steps < 100 loop
            Step (State, Quiet, Outputs);
            Total := Total + T_Sample;
            Steps := Steps + 1;
         end loop;

         Assert
           (State.Ped (East_Side) = Change_Interval,
            "the WALK boundary should fire within the step bound");
         Assert
           (Total = T_Walk,
            "the summed sampling periods should hit the WALK dwell"
            & " exactly");
         Assert
           (State.Ped (South_Side) = Pending_Pedestrian_Request
            and then State.Ped_Timer (South_Side) = 0,
            "a PENDING crosswalk runs no timer: the T_SAMPLE advance"
            & " should not touch it");
      end;

      --  Latched buffer expiry (hlr_6_pedestrian.18): a latched buffer whose
      --  timer runs out re-arms the crosswalk to PENDING instead of releasing
      --  it, and the request lamp stays lit through the expiry step.

      State := Barrier_State (2_000);
      State.Ped (East_Side) := Buffer_Interval_Latched;
      State.Ped_Timer (East_Side) := 100;

      Step (State, Quiet, Outputs);

      Assert
        (State.Ped (East_Side) = Pending_Pedestrian_Request,
         "a latched buffer expiry should re-arm the crosswalk to PENDING");
      Assert
        (Outputs.Requests (East_Side) = Request_Pending,
         "the lamp should stay lit through the latched buffer expiry");

      --  Left-demand clear (hlr_5_vehicle_1_left_demand.4): a latched West
      --  demand clears when its next conflicting through (North) rises --
      --  here on the EW barrier exit into NS both-through, whose entry
      --  raises both NS throughs from RED.

      State := Barrier_State (100);
      State.Left (West) := Left_Demand_Pending;

      Step (State, Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "the barrier boundary should fire into NS both-through");
      Assert
        (State.Left (West) = No_Left_Demand,
         "the West demand should clear when the North through rises");

      --  No-demand full cycle (hlr_5_vehicle.13/.18/.23/.36/.41/.46,
      --  hlr_3_timing.7): with no left demand latched the sequencer skips
      --  every lead/lag state -- barrier -> both-through -> both-drop-yellow
      --  on each axis -- and one full cycle takes exactly 2 x T_AXIS.

      declare
         type Visit_Flags is array (Vehicle_Sequencer_State) of Boolean;

         Visited  : Visit_Flags := (others => False);
         Total    : Duration_Ms := 0;
         Steps    : Natural := 0;
         Departed : Boolean := False;
      begin
         Initialize (State);

         loop
            Step (State, Quiet, Outputs);
            Total := Total + T_Sample;
            Steps := Steps + 1;
            Visited (State.Vehicle) := True;
            Departed := Departed or else State.Vehicle /= EW_Barrier_Allred;
            exit when
              (Departed and then State.Vehicle = EW_Barrier_Allred)
              or else Steps > 1_000;
         end loop;

         Assert
           (State.Vehicle = EW_Barrier_Allred,
            "the sequencer should return to the EW barrier within the"
            & " step bound");
         Assert
           (Visited (NS_Both_Through)
            and then Visited (NS_Both_Drop_Yellow)
            and then Visited (NS_Barrier_Allred)
            and then Visited (EW_Both_Through)
            and then Visited (EW_Both_Drop_Yellow),
            "the no-demand cycle should run both axes through the"
            & " both-through / both-drop-yellow spine");
         Assert
           (not Visited (N_Lead)
            and then not Visited (S_Lag)
            and then not Visited (E_Lead)
            and then not Visited (W_Lag),
            "no lead/lag state should run without a latched left demand");
         Assert
           (Total = 2 * T_Axis,
            "a full no-demand cycle should take exactly 2 x T_AXIS");
      end;

      --  Demand-serving full cycle (hlr_5_vehicle.12/.35,
      --  hlr_5_vehicle_1_left_demand.3, hlr_6_pedestrian.8/.12/.13/.17,
      --  hlr_3_timing.7): left-turn vehicles held present on every approach
      --  and one pedestrian press on West_Side sampled at the start. The
      --  cycle serves every lead/lag state, walks the pedestrian through
      --  WALK -> CHANGE -> BUFFER -> idle, and -- the axis slot being
      --  demand-independent -- still takes exactly 2 x T_AXIS.

      declare
         type Visit_Flags is array (Vehicle_Sequencer_State) of Boolean;

         Lefts     : Sensors_State := Quiet;
         First     : Sensors_State := Quiet;
         Visited   : Visit_Flags := (others => False);
         Total     : Duration_Ms := 0;
         Steps     : Natural := 0;
         Departed  : Boolean := False;
         Seen_Walk : Boolean := False;
         Seen_FDW  : Boolean := False;
      begin
         Lefts.Left_Turns := (others => Vehicle_Present);
         First := Lefts;
         First.Buttons (West_Side) := Pressed;

         Initialize (State);

         Step (State, First, Outputs);
         Total := Total + T_Sample;

         Assert
           ((for all A in Approach =>
               State.Left (A) = Left_Demand_Pending),
            "a sampled left-turn vehicle should latch the approach's"
            & " demand");
         Assert
           (State.Ped (West_Side) = Pending_Pedestrian_Request,
            "the sampled press should arm West_Side to PENDING");

         loop
            Step (State, Lefts, Outputs);
            Total := Total + T_Sample;
            Steps := Steps + 1;
            Visited (State.Vehicle) := True;
            Seen_Walk :=
              Seen_Walk or else Outputs.Heads (West_Side) = Walk;
            Seen_FDW :=
              Seen_FDW or else Outputs.Heads (West_Side) = Flash_Dont_Walk;
            Departed := Departed or else State.Vehicle /= EW_Barrier_Allred;
            exit when
              (Departed and then State.Vehicle = EW_Barrier_Allred)
              or else Steps > 1_000;
         end loop;

         Assert
           (Visited (N_Lead)
            and then Visited (S_Lag)
            and then Visited (E_Lead)
            and then Visited (W_Lag),
            "latched demands should route the cycle through every"
            & " lead/lag state");
         Assert
           (Total = 2 * T_Axis,
            "the axis slot should be independent of left-turn demand:"
            & " the full cycle still takes exactly 2 x T_AXIS");
         Assert
           (Seen_Walk and then Seen_FDW,
            "the pedestrian service should display WALK then flashing"
            & " DONT WALK");
         Assert
           (State.Ped (West_Side) = No_Pedestrian_Request,
            "an unlatched buffer expiry should release the crosswalk"
            & " to idle");
      end;

--  begin read only
   end Test_Step;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end Controller.Test_Data.Tests;
