with AUnit.Assertions; use AUnit.Assertions;

with Controller;
with Reqs_Support;
with States;

package body Llr_4_Controller_1_Vehicle_Tests is

   use all type States.Approach;
   use all type States.Left_Demand_State;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   procedure Check_Face_Row (V : States.Vehicle_Sequencer_State);
   --  Assert that the vehicle faces Project_Outputs emits in sequencer state V
   --  are the row llr_4_controller_1_vehicle transcribed into
   --  Reqs_Support.Expected_Faces. Shared by the twenty-two row routines, so
   --  each is a single call naming its own state.
   --
   --  Vehicle_Face_Outputs is private to the Controller body, so the row is
   --  observed through Project_Outputs -- which llr_4_controller.9 requires to
   --  return exactly those faces in NORMAL_OPERATION. Only Through and Left
   --  are checked: the heads and request lamps belong to the pedestrian
   --  machine and are no part of this requirement.

   procedure Check_Face_Row (V : States.Vehicle_Sequencer_State) is
      Expected : constant Reqs_Support.Face_Row :=
        Reqs_Support.Expected_Faces (V);

      Outputs : constant States.Display_State :=
        Controller.Project_Outputs
          (Reqs_Support.Vehicle_State (V, Remaining => States.T_Sample));
   begin
      for A in States.Approach loop
         Assert
           (Outputs.Through (A) = Expected.Through (A),
            States.Vehicle_Sequencer_State'Image (V)
            & ": through face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Outputs.Through (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expected.Through (A)));

         Assert
           (Outputs.Left (A) = Expected.Left (A),
            States.Vehicle_Sequencer_State'Image (V)
            & ": left face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Outputs.Left (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expected.Left (A)));
      end loop;
   end Check_Face_Row;

   procedure Check_Fixed_Dwell_Exit
     (Source      : States.Vehicle_Sequencer_State;
      Target      : States.Vehicle_Sequencer_State;
      Loaded      : States.Duration_Ms;
      Loaded_Name : String);
   --  Assert both cases of the unguarded timed transition Source -> Target
   --  that loads Loaded -- the target's own dwell, named by Loaded_Name for
   --  the failure messages. Shared by the transitions whose whole content is
   --  that triple.
   --
   --  Test_27 spells out the two-case argument every transition routine in
   --  this file rests on; it is not repeated per routine. Not shared by the
   --  guarded exits (.25, .26, .30, .31, .38, .39, .43, .44) or by the two
   --  whose loaded dwell is a both-through commit interval (.29, .42): those
   --  are written out, because the guard each reads is particular to it.

   procedure Check_Fixed_Dwell_Exit
     (Source      : States.Vehicle_Sequencer_State;
      Target      : States.Vehicle_Sequencer_State;
      Loaded      : States.Duration_Ms;
      Loaded_Name : String)
   is
      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin
      State := Reqs_Support.Vehicle_State (Source, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = Source,
         "with two sampling periods of dwell left the sequencer must stay in "
         & States.Vehicle_Sequencer_State'Image (Source)
         & ", but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         States.Vehicle_Sequencer_State'Image (Source)
         & ": the unfired step must leave exactly one sampling period of"
         & " dwell, but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (Source, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = Target,
         "on the step where the dwell of "
         & States.Vehicle_Sequencer_State'Image (Source)
         & " elapses the sequencer must enter "
         & States.Vehicle_Sequencer_State'Image (Target)
         & ", but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Loaded,
         "entering "
         & States.Vehicle_Sequencer_State'Image (Target)
         & " must load "
         & Loaded_Name
         & " ("
         & States.Duration_Ms'Image (Loaded)
         & " ms) as its dwell, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));
   end Check_Fixed_Dwell_Exit;

   ------------------------------------------------------------------------
   --  Structural discipline
   ------------------------------------------------------------------------

   procedure Test_02_Vehicle_Held_While_Dwell_Remains (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.2

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  A universal claim, over the state alphabet and over the timer: no
      --  sequencer state is left before its own dwell has elapsed, and the
      --  absence of vehicular demand never moves the sequencer.
      --
      --  Vehicle_Sequencer_State is a twenty-two-value enumeration, so every
      --  state is run rather than a few sampled, and the input snapshot is
      --  the quiet one -- no left-turn detector present anywhere, which is the
      --  absence of vehicular demand the statement names.
      --
      --  Two sampling periods of dwell remain, so the dwell has not elapsed
      --  (llr_4_controller.18 fires only at a remaining dwell of at most one),
      --  and the step must leave State.Vehicle alone while accounting for
      --  exactly one T_SAMPLE of that dwell (llr_4_controller.17).

      for V in States.Vehicle_Sequencer_State loop
         State := Reqs_Support.Vehicle_State (V, 2 * States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (State.Vehicle = V,
            "with two sampling periods of dwell left and no vehicular demand"
            & " the sequencer must stay in "
            & States.Vehicle_Sequencer_State'Image (V)
            & ", but it moved to "
            & States.Vehicle_Sequencer_State'Image (State.Vehicle));

         Assert
           (State.Veh_Timer = States.T_Sample,
            States.Vehicle_Sequencer_State'Image (V)
            & ": the unfired step must decrement the dwell by exactly"
            & " T_SAMPLE, leaving"
            & States.Duration_Ms'Image (States.T_Sample)
            & " ms, but left"
            & States.Duration_Ms'Image (State.Veh_Timer));
      end loop;

   end Test_02_Vehicle_Held_While_Dwell_Remains;

   ------------------------------------------------------------------------
   --  Moore output rows, NS axis
   ------------------------------------------------------------------------

   procedure Test_03_N_Lead_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.3

      pragma Unreferenced (T);
   begin
      Check_Face_Row (N_Lead);
   end Test_03_N_Lead_Faces;

   procedure Test_04_N_Lead_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.4

      pragma Unreferenced (T);
   begin
      Check_Face_Row (N_Lead_Yellow);
   end Test_04_N_Lead_Yellow_Faces;

   procedure Test_05_N_Lead_Clear_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.5

      pragma Unreferenced (T);
   begin
      Check_Face_Row (N_Lead_Clear);
   end Test_05_N_Lead_Clear_Faces;

   procedure Test_06_NS_Both_Through_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.6

      pragma Unreferenced (T);
   begin
      Check_Face_Row (NS_Both_Through);
   end Test_06_NS_Both_Through_Faces;

   procedure Test_07_NS_Both_Through_Hold_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.7

      pragma Unreferenced (T);
   begin
      --  The hold continues the both-through phase, so .7 gives the same faces
      --  as .6 -- and the row is asserted separately from .6's for that reason
      --  rather than in spite of it: they agree by requirement, not by sharing
      --  a table entry, and code that dropped one of them would still pass the
      --  other.
      Check_Face_Row (NS_Both_Through_Hold);
   end Test_07_NS_Both_Through_Hold_Faces;

   procedure Test_08_N_Drop_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.8

      pragma Unreferenced (T);
   begin
      Check_Face_Row (N_Drop_Yellow);
   end Test_08_N_Drop_Yellow_Faces;

   procedure Test_09_N_Drop_Clear_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.9

      pragma Unreferenced (T);
   begin
      Check_Face_Row (N_Drop_Clear);
   end Test_09_N_Drop_Clear_Faces;

   procedure Test_10_S_Lag_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.10

      pragma Unreferenced (T);
   begin
      Check_Face_Row (S_Lag);
   end Test_10_S_Lag_Faces;

   procedure Test_11_S_Lag_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.11

      pragma Unreferenced (T);
   begin
      Check_Face_Row (S_Lag_Yellow);
   end Test_11_S_Lag_Yellow_Faces;

   procedure Test_12_NS_Both_Drop_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.12

      pragma Unreferenced (T);
   begin
      Check_Face_Row (NS_Both_Drop_Yellow);
   end Test_12_NS_Both_Drop_Yellow_Faces;

   procedure Test_13_NS_Barrier_Allred_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.13

      pragma Unreferenced (T);
   begin
      Check_Face_Row (NS_Barrier_Allred);
   end Test_13_NS_Barrier_Allred_Faces;

   ------------------------------------------------------------------------
   --  Moore output rows, EW axis
   ------------------------------------------------------------------------

   procedure Test_14_E_Lead_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.14

      pragma Unreferenced (T);
   begin
      Check_Face_Row (E_Lead);
   end Test_14_E_Lead_Faces;

   procedure Test_15_E_Lead_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.15

      pragma Unreferenced (T);
   begin
      Check_Face_Row (E_Lead_Yellow);
   end Test_15_E_Lead_Yellow_Faces;

   procedure Test_16_E_Lead_Clear_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.16

      pragma Unreferenced (T);
   begin
      Check_Face_Row (E_Lead_Clear);
   end Test_16_E_Lead_Clear_Faces;

   procedure Test_17_EW_Both_Through_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.17

      pragma Unreferenced (T);
   begin
      Check_Face_Row (EW_Both_Through);
   end Test_17_EW_Both_Through_Faces;

   procedure Test_18_EW_Both_Through_Hold_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.18

      pragma Unreferenced (T);
   begin
      --  The mirror of .7.
      Check_Face_Row (EW_Both_Through_Hold);
   end Test_18_EW_Both_Through_Hold_Faces;

   procedure Test_19_E_Drop_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.19

      pragma Unreferenced (T);
   begin
      Check_Face_Row (E_Drop_Yellow);
   end Test_19_E_Drop_Yellow_Faces;

   procedure Test_20_E_Drop_Clear_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.20

      pragma Unreferenced (T);
   begin
      Check_Face_Row (E_Drop_Clear);
   end Test_20_E_Drop_Clear_Faces;

   procedure Test_21_W_Lag_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.21

      pragma Unreferenced (T);
   begin
      Check_Face_Row (W_Lag);
   end Test_21_W_Lag_Faces;

   procedure Test_22_W_Lag_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.22

      pragma Unreferenced (T);
   begin
      Check_Face_Row (W_Lag_Yellow);
   end Test_22_W_Lag_Yellow_Faces;

   procedure Test_23_EW_Both_Drop_Yellow_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.23

      pragma Unreferenced (T);
   begin
      Check_Face_Row (EW_Both_Drop_Yellow);
   end Test_23_EW_Both_Drop_Yellow_Faces;

   procedure Test_24_EW_Barrier_Allred_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.24

      pragma Unreferenced (T);
   begin
      Check_Face_Row (EW_Barrier_Allred);
   end Test_24_EW_Barrier_Allred_Faces;

   ------------------------------------------------------------------------
   --  Transitions, NS axis
   ------------------------------------------------------------------------

   procedure Test_25_EW_Barrier_Allred_To_N_Lead_On_North_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.25

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Guard: State.Left (NORTH) is LEFT_DEMAND_PENDING, which routes the
      --  barrier's exit into the north leading left and loads T_LEAD.
      --  Reqs_Support.Vehicle_State leaves every approach at NO_LEFT_DEMAND,
      --  so the demand is placed on the constructed state.

      State :=
        Reqs_Support.Vehicle_State (EW_Barrier_Allred, 2 * States.T_Sample);
      State.Left (North) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Barrier_Allred,
         "with two sampling periods of the T_BARRIER dwell left the sequencer"
         & " must stay in EW_BARRIER_ALLRED, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (EW_Barrier_Allred, States.T_Sample);
      State.Left (North) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = N_Lead,
         "on the step where T_BARRIER elapses with a NORTH left-turn demand"
         & " pending the sequencer must enter N_LEAD, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Lead,
         "entering N_LEAD must load T_LEAD as its dwell, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_25_EW_Barrier_Allred_To_N_Lead_On_North_Demand;

   procedure Test_26_EW_Barrier_Allred_To_NS_Both_Through_No_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.26

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Guard: State.Left (NORTH) is NO_LEFT_DEMAND -- the value
      --  Reqs_Support.Vehicle_State already leaves every approach at -- so no
      --  lead runs and the barrier's exit goes straight to the both-throughs.
      --  Their dwell is the commit interval with no lead spent,
      --  Reqs_Support.Commit_After_Barrier, transcribed there as the
      --  arithmetic over named durations this statement writes.

      State :=
        Reqs_Support.Vehicle_State (EW_Barrier_Allred, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Barrier_Allred,
         "with two sampling periods of the T_BARRIER dwell left the sequencer"
         & " must stay in EW_BARRIER_ALLRED, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (EW_Barrier_Allred, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "on the step where T_BARRIER elapses with no NORTH left-turn demand"
         & " the sequencer must enter NS_BOTH_THROUGH, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Commit_After_Barrier,
         "entering NS_BOTH_THROUGH off the barrier must load the commit"
         & " interval T_AXIS - T_BARRIER - (T_YELLOW + T_REDCLEAR + T_LAG +"
         & " T_YELLOW) ="
         & States.Duration_Ms'Image (Reqs_Support.Commit_After_Barrier)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_26_EW_Barrier_Allred_To_NS_Both_Through_No_Demand;

   procedure Test_27_N_Lead_To_N_Lead_Yellow_On_Dwell_Elapse (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.27

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State : Controller.Controller_State;
      Out_1 : States.Display_State;
   begin

      --  A timed EARS transition carries two claims, and a test that checks
      --  only the second passes against code that fires a tick early. So both
      --  are checked, on either side of the one boundary the requirement
      --  names.
      --
      --  Every dwell is an integral multiple of T_SAMPLE (llr_1_states.31) and
      --  a transition fires on the step whose remaining dwell is at most
      --  T_SAMPLE (llr_4_controller.18), so the boundary is exactly one step
      --  wide and there is nothing between the two cases to probe.

      --  While the dwell has not elapsed (two sampling periods left), N_LEAD
      --  holds and only the timer moves.

      State := Reqs_Support.Vehicle_State (N_Lead, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Out_1);

      Assert
        (State.Vehicle = N_Lead,
         "with two sampling periods of dwell left the sequencer must stay in"
         & " N_LEAD, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell");

      --  When the dwell elapses -- the step whose remaining dwell is one
      --  sampling period -- N_LEAD_YELLOW is entered and its own dwell
      --  (T_YELLOW) is loaded.

      State := Reqs_Support.Vehicle_State (N_Lead, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Out_1);

      Assert
        (State.Vehicle = N_Lead_Yellow,
         "on the step where the T_LEAD dwell elapses the sequencer must enter"
         & " N_LEAD_YELLOW, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Yellow,
         "entering N_LEAD_YELLOW must load T_YELLOW as its dwell");

   end Test_27_N_Lead_To_N_Lead_Yellow_On_Dwell_Elapse;

   procedure Test_28_N_Lead_Yellow_To_N_Lead_Clear_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.28

      pragma Unreferenced (T);
   begin
      --  The lead's yellow hands over to its red clearance, T_REDCLEAR.
      Check_Fixed_Dwell_Exit
        (Source      => N_Lead_Yellow,
         Target      => N_Lead_Clear,
         Loaded      => States.T_Redclear,
         Loaded_Name => "T_REDCLEAR");
   end Test_28_N_Lead_Yellow_To_N_Lead_Clear_On_Dwell_Elapse;

   procedure Test_29_N_Lead_Clear_To_NS_Both_Through_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.29

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Unguarded, but its loaded dwell is the commit interval *after* a lead
      --  ran: the axis slot less the barrier, less the whole north lead block
      --  that has just run, less a reserved full lagging-left block --
      --  Reqs_Support.Commit_After_Lead, transcribed there as the arithmetic
      --  this statement writes.

      State := Reqs_Support.Vehicle_State (N_Lead_Clear, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = N_Lead_Clear,
         "with two sampling periods of the T_REDCLEAR dwell left the sequencer"
         & " must stay in N_LEAD_CLEAR, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (N_Lead_Clear, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "on the step where the lead's T_REDCLEAR elapses the sequencer must"
         & " enter NS_BOTH_THROUGH, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Commit_After_Lead,
         "entering NS_BOTH_THROUGH after a lead must load the commit interval"
         & " T_AXIS - T_BARRIER - (T_LEAD + T_YELLOW + T_REDCLEAR) -"
         & " (T_YELLOW + T_REDCLEAR + T_LAG + T_YELLOW) ="
         & States.Duration_Ms'Image (Reqs_Support.Commit_After_Lead)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_29_N_Lead_Clear_To_NS_Both_Through_On_Dwell_Elapse;

   procedure Test_30_NS_Both_Through_To_N_Drop_Yellow_On_South_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.30

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Guard: State.Left (SOUTH) is LEFT_DEMAND_PENDING at the commit
      --  boundary, which routes the slot into the south lag block -- opened by
      --  the north through's closing yellow, T_YELLOW.
      --
      --  How long the commit interval itself is belongs to .26 and .29, not
      --  here: the two cases only need a state with more than one sampling
      --  period of dwell left and a state with exactly one.

      State :=
        Reqs_Support.Vehicle_State (NS_Both_Through, 2 * States.T_Sample);
      State.Left (South) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "with two sampling periods of the commit interval left the sequencer"
         & " must stay in NS_BOTH_THROUGH, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (NS_Both_Through, States.T_Sample);
      State.Left (South) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = N_Drop_Yellow,
         "on the step where the commit interval elapses with a SOUTH left-turn"
         & " demand pending the sequencer must enter N_DROP_YELLOW, but it is"
         & " in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Yellow,
         "entering N_DROP_YELLOW must load T_YELLOW as its dwell, but the"
         & " timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_30_NS_Both_Through_To_N_Drop_Yellow_On_South_Demand;

   procedure Test_31_NS_Both_Through_To_Hold_No_South_Demand (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.31

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The other branch of the commit boundary from .30: State.Left (SOUTH)
      --  is NO_LEFT_DEMAND -- the value Reqs_Support.Vehicle_State already
      --  leaves every approach at -- so the reserved lag block is not spent on
      --  a lag and the slot runs the hold interval instead,
      --  Reqs_Support.Hold_Interval.

      State :=
        Reqs_Support.Vehicle_State (NS_Both_Through, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through,
         "with two sampling periods of the commit interval left the sequencer"
         & " must stay in NS_BOTH_THROUGH, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (NS_Both_Through, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Both_Through_Hold,
         "on the step where the commit interval elapses with no SOUTH"
         & " left-turn demand the sequencer must enter NS_BOTH_THROUGH_HOLD,"
         & " but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Hold_Interval,
         "entering NS_BOTH_THROUGH_HOLD must load the hold interval T_REDCLEAR"
         & " + T_LAG + T_YELLOW ="
         & States.Duration_Ms'Image (Reqs_Support.Hold_Interval)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_31_NS_Both_Through_To_Hold_No_South_Demand;

   procedure Test_32_NS_Both_Through_Hold_To_NS_Both_Drop_Yellow
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.32

      pragma Unreferenced (T);
   begin
      --  Unconditional: the hold has already declined the lag, so nothing is
      --  read here and the slot closes on the both-drop yellow.
      Check_Fixed_Dwell_Exit
        (Source      => NS_Both_Through_Hold,
         Target      => NS_Both_Drop_Yellow,
         Loaded      => States.T_Yellow,
         Loaded_Name => "T_YELLOW");
   end Test_32_NS_Both_Through_Hold_To_NS_Both_Drop_Yellow;

   procedure Test_33_N_Drop_Yellow_To_N_Drop_Clear_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.33

      pragma Unreferenced (T);
   begin
      --  The north through's closing yellow hands over to its red clearance.
      Check_Fixed_Dwell_Exit
        (Source      => N_Drop_Yellow,
         Target      => N_Drop_Clear,
         Loaded      => States.T_Redclear,
         Loaded_Name => "T_REDCLEAR");
   end Test_33_N_Drop_Yellow_To_N_Drop_Clear_On_Dwell_Elapse;

   procedure Test_34_N_Drop_Clear_To_S_Lag_On_Dwell_Elapse (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.34

      pragma Unreferenced (T);
   begin
      --  The red clearance opens the south lagging left, T_LAG.
      Check_Fixed_Dwell_Exit
        (Source      => N_Drop_Clear,
         Target      => S_Lag,
         Loaded      => States.T_Lag,
         Loaded_Name => "T_LAG");
   end Test_34_N_Drop_Clear_To_S_Lag_On_Dwell_Elapse;

   procedure Test_35_S_Lag_To_S_Lag_Yellow_On_Dwell_Elapse (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.35

      pragma Unreferenced (T);
   begin
      --  The lag's own yellow change, T_YELLOW.
      Check_Fixed_Dwell_Exit
        (Source      => S_Lag,
         Target      => S_Lag_Yellow,
         Loaded      => States.T_Yellow,
         Loaded_Name => "T_YELLOW");
   end Test_35_S_Lag_To_S_Lag_Yellow_On_Dwell_Elapse;

   procedure Test_36_S_Lag_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.36

      pragma Unreferenced (T);
   begin
      --  The lag's yellow closes the NS slot at the barrier, T_BARRIER.
      Check_Fixed_Dwell_Exit
        (Source      => S_Lag_Yellow,
         Target      => NS_Barrier_Allred,
         Loaded      => States.T_Barrier,
         Loaded_Name => "T_BARRIER");
   end Test_36_S_Lag_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse;

   procedure Test_37_NS_Both_Drop_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.37

      pragma Unreferenced (T);
   begin
      --  The other way out of the NS slot -- both throughs dropped together --
      --  reaches the same barrier with the same T_BARRIER.
      Check_Fixed_Dwell_Exit
        (Source      => NS_Both_Drop_Yellow,
         Target      => NS_Barrier_Allred,
         Loaded      => States.T_Barrier,
         Loaded_Name => "T_BARRIER");
   end Test_37_NS_Both_Drop_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse;

   ------------------------------------------------------------------------
   --  Transitions, EW axis (the exact mirror)
   ------------------------------------------------------------------------

   procedure Test_38_NS_Barrier_Allred_To_E_Lead_On_East_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.38

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Guard: State.Left (EAST) is LEFT_DEMAND_PENDING, which routes the
      --  barrier's exit into the east leading left and loads T_LEAD.

      State :=
        Reqs_Support.Vehicle_State (NS_Barrier_Allred, 2 * States.T_Sample);
      State.Left (East) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Barrier_Allred,
         "with two sampling periods of the T_BARRIER dwell left the sequencer"
         & " must stay in NS_BARRIER_ALLRED, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (NS_Barrier_Allred, States.T_Sample);
      State.Left (East) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = E_Lead,
         "on the step where T_BARRIER elapses with an EAST left-turn demand"
         & " pending the sequencer must enter E_LEAD, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Lead,
         "entering E_LEAD must load T_LEAD as its dwell, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_38_NS_Barrier_Allred_To_E_Lead_On_East_Demand;

   procedure Test_39_NS_Barrier_Allred_To_EW_Both_Through_No_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.39

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Guard: State.Left (EAST) is NO_LEFT_DEMAND -- what
      --  Reqs_Support.Vehicle_State already leaves every approach at -- so no
      --  lead runs and the dwell is Reqs_Support.Commit_After_Barrier, the
      --  mirror of .26.

      State :=
        Reqs_Support.Vehicle_State (NS_Barrier_Allred, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = NS_Barrier_Allred,
         "with two sampling periods of the T_BARRIER dwell left the sequencer"
         & " must stay in NS_BARRIER_ALLRED, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (NS_Barrier_Allred, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Both_Through,
         "on the step where T_BARRIER elapses with no EAST left-turn demand"
         & " the sequencer must enter EW_BOTH_THROUGH, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Commit_After_Barrier,
         "entering EW_BOTH_THROUGH off the barrier must load the commit"
         & " interval T_AXIS - T_BARRIER - (T_YELLOW + T_REDCLEAR + T_LAG +"
         & " T_YELLOW) ="
         & States.Duration_Ms'Image (Reqs_Support.Commit_After_Barrier)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_39_NS_Barrier_Allred_To_EW_Both_Through_No_Demand;

   procedure Test_40_E_Lead_To_E_Lead_Yellow_On_Dwell_Elapse (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.40

      pragma Unreferenced (T);
   begin
      --  The east lead's yellow change, T_YELLOW -- the mirror of .27.
      Check_Fixed_Dwell_Exit
        (Source      => E_Lead,
         Target      => E_Lead_Yellow,
         Loaded      => States.T_Yellow,
         Loaded_Name => "T_YELLOW");
   end Test_40_E_Lead_To_E_Lead_Yellow_On_Dwell_Elapse;

   procedure Test_41_E_Lead_Yellow_To_E_Lead_Clear_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.41

      pragma Unreferenced (T);
   begin
      --  The east lead's red clearance, T_REDCLEAR.
      Check_Fixed_Dwell_Exit
        (Source      => E_Lead_Yellow,
         Target      => E_Lead_Clear,
         Loaded      => States.T_Redclear,
         Loaded_Name => "T_REDCLEAR");
   end Test_41_E_Lead_Yellow_To_E_Lead_Clear_On_Dwell_Elapse;

   procedure Test_42_E_Lead_Clear_To_EW_Both_Through_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.42

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The mirror of .29: the loaded dwell is the commit interval after a
      --  lead ran, Reqs_Support.Commit_After_Lead.

      State := Reqs_Support.Vehicle_State (E_Lead_Clear, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = E_Lead_Clear,
         "with two sampling periods of the T_REDCLEAR dwell left the sequencer"
         & " must stay in E_LEAD_CLEAR, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (E_Lead_Clear, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Both_Through,
         "on the step where the lead's T_REDCLEAR elapses the sequencer must"
         & " enter EW_BOTH_THROUGH, but it is in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Commit_After_Lead,
         "entering EW_BOTH_THROUGH after a lead must load the commit interval"
         & " T_AXIS - T_BARRIER - (T_LEAD + T_YELLOW + T_REDCLEAR) -"
         & " (T_YELLOW + T_REDCLEAR + T_LAG + T_YELLOW) ="
         & States.Duration_Ms'Image (Reqs_Support.Commit_After_Lead)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_42_E_Lead_Clear_To_EW_Both_Through_On_Dwell_Elapse;

   procedure Test_43_EW_Both_Through_To_E_Drop_Yellow_On_West_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.43

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The mirror of .30. Guard: State.Left (WEST) is LEFT_DEMAND_PENDING at
      --  the commit boundary, which routes the slot into the west lag block --
      --  opened by the east through's closing yellow, T_YELLOW.

      State :=
        Reqs_Support.Vehicle_State (EW_Both_Through, 2 * States.T_Sample);
      State.Left (West) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Both_Through,
         "with two sampling periods of the commit interval left the sequencer"
         & " must stay in EW_BOTH_THROUGH, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (EW_Both_Through, States.T_Sample);
      State.Left (West) := Left_Demand_Pending;

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = E_Drop_Yellow,
         "on the step where the commit interval elapses with a WEST left-turn"
         & " demand pending the sequencer must enter E_DROP_YELLOW, but it is"
         & " in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Yellow,
         "entering E_DROP_YELLOW must load T_YELLOW as its dwell, but the"
         & " timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_43_EW_Both_Through_To_E_Drop_Yellow_On_West_Demand;

   procedure Test_44_EW_Both_Through_To_Hold_No_West_Demand (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.44

      pragma Unreferenced (T);

      use type States.Duration_Ms;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The mirror of .31: no WEST demand at the commit boundary, so the slot
      --  runs Reqs_Support.Hold_Interval rather than the west lag block.

      State :=
        Reqs_Support.Vehicle_State (EW_Both_Through, 2 * States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Both_Through,
         "with two sampling periods of the commit interval left the sequencer"
         & " must stay in EW_BOTH_THROUGH, but it moved to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = States.T_Sample,
         "the unfired step must leave exactly one sampling period of dwell,"
         & " but left"
         & States.Duration_Ms'Image (State.Veh_Timer));

      State := Reqs_Support.Vehicle_State (EW_Both_Through, States.T_Sample);

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Vehicle = EW_Both_Through_Hold,
         "on the step where the commit interval elapses with no WEST left-turn"
         & " demand the sequencer must enter EW_BOTH_THROUGH_HOLD, but it is"
         & " in "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));
      Assert
        (State.Veh_Timer = Reqs_Support.Hold_Interval,
         "entering EW_BOTH_THROUGH_HOLD must load the hold interval T_REDCLEAR"
         & " + T_LAG + T_YELLOW ="
         & States.Duration_Ms'Image (Reqs_Support.Hold_Interval)
         & " ms, but the timer holds"
         & States.Duration_Ms'Image (State.Veh_Timer));

   end Test_44_EW_Both_Through_To_Hold_No_West_Demand;

   procedure Test_45_EW_Both_Through_Hold_To_EW_Both_Drop_Yellow
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.45

      pragma Unreferenced (T);
   begin
      --  The mirror of .32, and unconditional for the same reason.
      Check_Fixed_Dwell_Exit
        (Source      => EW_Both_Through_Hold,
         Target      => EW_Both_Drop_Yellow,
         Loaded      => States.T_Yellow,
         Loaded_Name => "T_YELLOW");
   end Test_45_EW_Both_Through_Hold_To_EW_Both_Drop_Yellow;

   procedure Test_46_E_Drop_Yellow_To_E_Drop_Clear_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.46

      pragma Unreferenced (T);
   begin
      --  The east through's closing yellow hands over to its red clearance.
      Check_Fixed_Dwell_Exit
        (Source      => E_Drop_Yellow,
         Target      => E_Drop_Clear,
         Loaded      => States.T_Redclear,
         Loaded_Name => "T_REDCLEAR");
   end Test_46_E_Drop_Yellow_To_E_Drop_Clear_On_Dwell_Elapse;

   procedure Test_47_E_Drop_Clear_To_W_Lag_On_Dwell_Elapse (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.47

      pragma Unreferenced (T);
   begin
      --  The red clearance opens the west lagging left, T_LAG.
      Check_Fixed_Dwell_Exit
        (Source      => E_Drop_Clear,
         Target      => W_Lag,
         Loaded      => States.T_Lag,
         Loaded_Name => "T_LAG");
   end Test_47_E_Drop_Clear_To_W_Lag_On_Dwell_Elapse;

   procedure Test_48_W_Lag_To_W_Lag_Yellow_On_Dwell_Elapse (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.48

      pragma Unreferenced (T);
   begin
      --  The west lag's own yellow change, T_YELLOW.
      Check_Fixed_Dwell_Exit
        (Source      => W_Lag,
         Target      => W_Lag_Yellow,
         Loaded      => States.T_Yellow,
         Loaded_Name => "T_YELLOW");
   end Test_48_W_Lag_To_W_Lag_Yellow_On_Dwell_Elapse;

   procedure Test_49_W_Lag_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.49

      pragma Unreferenced (T);
   begin
      --  The west lag's yellow closes the EW slot at the barrier, T_BARRIER.
      Check_Fixed_Dwell_Exit
        (Source      => W_Lag_Yellow,
         Target      => EW_Barrier_Allred,
         Loaded      => States.T_Barrier,
         Loaded_Name => "T_BARRIER");
   end Test_49_W_Lag_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse;

   procedure Test_50_EW_Both_Drop_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test)
   is
      --@covers llr_4_controller_1_vehicle.50

      pragma Unreferenced (T);
   begin
      --  The other way out of the EW slot reaches the same barrier with the
      --  same T_BARRIER -- the mirror of .37, and the cycle's wrap.
      Check_Fixed_Dwell_Exit
        (Source      => EW_Both_Drop_Yellow,
         Target      => EW_Barrier_Allred,
         Loaded      => States.T_Barrier,
         Loaded_Name => "T_BARRIER");
   end Test_50_EW_Both_Drop_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse;

end Llr_4_Controller_1_Vehicle_Tests;
