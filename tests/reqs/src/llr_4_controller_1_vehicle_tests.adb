with AUnit.Assertions; use AUnit.Assertions;

with Controller;
with Reqs_Support;
with States;

package body Llr_4_Controller_1_Vehicle_Tests is

   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   procedure Check_Face_Row (V : States.Vehicle_Sequencer_State);
   --  Assert that the vehicle faces Project_Outputs emits in sequencer state V
   --  are the row llr_4_controller_1_vehicle transcribed into
   --  Reqs_Support.Expected_Faces. Shared by the twenty-two row routines so
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

   ------------------------------------------------------------------------
   --  Moore output rows
   ------------------------------------------------------------------------

   procedure Test_06_NS_Both_Through_Faces (T : in out Test) is
      --@covers llr_4_controller_1_vehicle.6

      pragma Unreferenced (T);
   begin
      Check_Face_Row (NS_Both_Through);
   end Test_06_NS_Both_Through_Faces;

   ------------------------------------------------------------------------
   --  Transitions
   ------------------------------------------------------------------------

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

end Llr_4_Controller_1_Vehicle_Tests;
