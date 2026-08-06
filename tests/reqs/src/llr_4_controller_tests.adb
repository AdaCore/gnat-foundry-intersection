with AUnit.Assertions; use AUnit.Assertions;

with Controller;
with Reqs_Support;
with States;

package body Llr_4_Controller_Tests is

   use all type States.Approach;
   use all type States.Crosswalk;
   use all type States.Fault_Detection;
   use all type States.Left_Demand_State;
   use all type States.Left_Turn_Detector;
   use all type States.Mode;
   use all type States.Pedestrian_Button;
   use all type States.Pedestrian_Head;
   use all type States.Pedestrian_State;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   use type States.Duration_Ms;

   ------------------------------------------------------------------------
   --  Local scaffolding
   ------------------------------------------------------------------------

   Loud : constant States.Sensors_State :=
     (Buttons    => (others => Pressed),
      Left_Turns => (others => Vehicle_Present),
      Fault      => Not_Asserted);
   --  Every arming input asserted on every crosswalk and every approach, with
   --  the fault line quiet: the snapshot that would arm every
   --  NORMAL_OPERATION sub-machine, used where a routine has to show that
   --  nothing was armed, or that arming reached the emitted outputs.

   --  A whole-controller state: mode M, the sequencer in V with Veh_Remaining
   --  of its dwell left, every approach's demand at L, and every crosswalk in
   --  P with Ped_Remaining of its dwell left.
   --
   --  Reqs_Support's constructors set one machine at a time and are always
   --  NORMAL_OPERATION; the statements here quantify over all four approaches
   --  or all four crosswalks at once (.4, .5, .15, .17) and five of them
   --  (.6-.8, .14, .15) need a FAULT state. Veh_Lag is a field of the record
   --  that llr_4_controller.1 does not name, so no statement gives it a value:
   --  it is set FALSE and never asserted.
   function Composite_State
     (V             : States.Vehicle_Sequencer_State;
      Veh_Remaining : States.Duration_Ms;
      M             : States.Mode := Normal_Operation;
      P             : States.Pedestrian_State := No_Pedestrian_Request;
      Ped_Remaining : States.Duration_Ms := 0;
      L             : States.Left_Demand_State := No_Left_Demand)
      return Controller.Controller_State
   is (Mode      => M,
       Vehicle   => V,
       Veh_Timer => Veh_Remaining,
       Veh_Lag   => False,
       Left      => (others => L),
       Ped       => (others => P),
       Ped_Timer => (others => Ped_Remaining));

   procedure Check_Display
     (Actual : States.Display_State;
      Expect : States.Display_State;
      Where  : String);
   --  Assert that every signal of Actual equals Expect, naming the differing
   --  signal and the place (Where) on failure. Compared signal by signal
   --  rather than as whole records so a failure says which lamp is wrong.

   procedure Check_Display
     (Actual : States.Display_State;
      Expect : States.Display_State;
      Where  : String) is
   begin
      for A in States.Approach loop
         Assert
           (Actual.Through (A) = Expect.Through (A),
            Where
            & ": through face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Actual.Through (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expect.Through (A)));

         Assert
           (Actual.Left (A) = Expect.Left (A),
            Where
            & ": left face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Actual.Left (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expect.Left (A)));
      end loop;

      for C in States.Crosswalk loop
         Assert
           (Actual.Heads (C) = Expect.Heads (C),
            Where
            & ": pedestrian head for "
            & States.Crosswalk'Image (C)
            & " was "
            & States.Pedestrian_Head'Image (Actual.Heads (C))
            & " but the requirement gives "
            & States.Pedestrian_Head'Image (Expect.Heads (C)));

         Assert
           (Actual.Requests (C) = Expect.Requests (C),
            Where
            & ": request indicator for "
            & States.Crosswalk'Image (C)
            & " was "
            & States.Request_Indicator'Image (Actual.Requests (C))
            & " but the requirement gives "
            & States.Request_Indicator'Image (Expect.Requests (C)));
      end loop;
   end Check_Display;

   ------------------------------------------------------------------------
   --  Statement .1 -- the composite state record
   ------------------------------------------------------------------------

   procedure Test_01_Controller_State_Holds_The_Five_Machines
     (T : in out Test)
   is
      --@covers llr_4_controller.1

      pragma Unreferenced (T);

      --  A shape witness (tests/reqs/README.md rule 10). Named associations
      --  and no `others` choice, so a component added to Controller_State
      --  leaves this aggregate incomplete and one removed or renamed leaves a
      --  choice naming nothing -- either fails the build here. Each value is
      --  supplied through a constant of the type .1 requires the component to
      --  have, so the component types are checked too: a Left component of
      --  any type other than Left_Demand_Array would not take Every_Approach.
      --
      --  VEH_LAG IS NOT A COMPONENT .1 NAMES. It is a seventh field the
      --  implementation carries, and it is listed here because omitting it
      --  would make the aggregate incomplete and break the build rather than
      --  report a finding. So what this routine establishes is the "holding"
      --  clause -- the six components .1 names are present, with the types it
      --  gives them -- plus a build-time gate on any *further* component. It
      --  does not establish that the six are all there is; the one existing
      --  surplus is admitted by name, deliberately and visibly.
      --
      --  The surplus is not cosmetic. Veh_Lag latches the lag decision at
      --  both-through entry (src/core/controller.adb:237) and the exit guards
      --  read the latch (:275, :333), whereas llr_4_controller_1_vehicle.30
      --  and .43 require the demand to be read live at the commit boundary --
      --  which is why those two statements fail today. Removing the field is
      --  part of resolving that divergence, not a separate tidy-up.

      Idle_Mode     : constant States.Mode := Normal_Operation;
      Idle_Vehicle  : constant States.Vehicle_Sequencer_State :=
        EW_Barrier_Allred;
      Idle_Timer    : constant States.Duration_Ms := 0;
      Every_Approach : constant States.Left_Demand_Array :=
        (others => No_Left_Demand);
      Every_Crosswalk : constant States.Pedestrian_Array :=
        (others => No_Pedestrian_Request);
      Every_Ped_Timer : constant Controller.Pedestrian_Timers :=
        (others => 0);

      Witness : constant Controller.Controller_State :=
        (Mode      => Idle_Mode,
         Vehicle   => Idle_Vehicle,
         Veh_Timer => Idle_Timer,
         Veh_Lag   => False,  --  not named by .1 -- see above
         Left      => Every_Approach,
         Ped       => Every_Crosswalk,
         Ped_Timer => Every_Ped_Timer);

      --  Read back through the record, so each check lands on the component
      --  rather than on the constant it was built from.

      Mode_Held    : constant States.Mode := Witness.Mode;
      Vehicle_Held : constant States.Vehicle_Sequencer_State :=
        Witness.Vehicle;
      Timer_Held   : constant States.Duration_Ms := Witness.Veh_Timer;
   begin
      Assert
        (Mode_Held = Normal_Operation,
         "Controller_State must hold the Mode (llr_4_controller.1), but the"
         & " component did not read back the mode written into it");

      Assert
        (Vehicle_Held = EW_Barrier_Allred,
         "Controller_State must hold the Vehicle_Sequencer_State"
         & " (llr_4_controller.1), but the component did not read back the"
         & " sequencer state written into it");

      Assert
        (Timer_Held = 0,
         "Controller_State must hold the sequencer's remaining-time field"
         & " Veh_Timer (llr_4_controller.1), but the component did not read"
         & " back the value written into it");

      --  The two arrays are checked per index, which is what ".1"'s
      --  "Left_Demand_Array" and "per-crosswalk remaining-time array"
      --  amount to: one cell reachable per approach and per crosswalk, of
      --  the component type each machine's state is held in.

      for A in States.Approach loop
         declare
            Cell : constant States.Left_Demand_State := Witness.Left (A);
         begin
            Assert
              (Cell = No_Left_Demand,
               "the Left_Demand_Array cell for "
               & States.Approach'Image (A)
               & " did not read back the state written into it");
         end;
      end loop;

      for C in States.Crosswalk loop
         declare
            Cell  : constant States.Pedestrian_State := Witness.Ped (C);
            Timer : constant States.Duration_Ms := Witness.Ped_Timer (C);
         begin
            Assert
              (Cell = No_Pedestrian_Request,
               "the Pedestrian_Array cell for "
               & States.Crosswalk'Image (C)
               & " did not read back the state written into it");

            Assert
              (Timer = 0,
               "the Ped_Timer cell for "
               & States.Crosswalk'Image (C)
               & " did not read back the remaining time written into it");
         end;
      end loop;
   end Test_01_Controller_State_Holds_The_Five_Machines;

   ------------------------------------------------------------------------
   --  The power-on state (statements 2-5)
   ------------------------------------------------------------------------

   procedure Test_02_Initialize_Sets_Normal_Operation (T : in out Test) is
      --@covers llr_4_controller.2

      pragma Unreferenced (T);

      State : Controller.Controller_State;
   begin

      --  An unquantified assignment: Initialize is called on a fresh state and
      --  the mode field is read. The rest of the power-on state belongs to
      --  statements .3-.5 and is asserted by their routines, so a wrong field
      --  fails its own requirement.

      Controller.Initialize (State);

      Assert
        (State.Mode = Normal_Operation,
         "Initialize must set the mode to NORMAL_OPERATION, but set it to "
         & States.Mode'Image (State.Mode));

   end Test_02_Initialize_Sets_Normal_Operation;

   procedure Test_03_Initialize_Sets_Barrier_And_Dwell (T : in out Test) is
      --@covers llr_4_controller.3

      pragma Unreferenced (T);

      State : Controller.Controller_State;
   begin

      --  Both halves of the one statement -- the sequencer state and the dwell
      --  loaded with it -- because the schedule rides on the (state, timer)
      --  pair: the right state with a wrong dwell is a different power-on than
      --  the one required.

      Controller.Initialize (State);

      Assert
        (State.Vehicle = EW_Barrier_Allred,
         "Initialize must set the sequencer to EW_BARRIER_ALLRED, but set it"
         & " to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));

      Assert
        (State.Veh_Timer = States.T_Barrier,
         "Initialize must load T_BARRIER as the power-on dwell, but loaded"
         & States.Duration_Ms'Image (State.Veh_Timer)
         & " ms against T_BARRIER ="
         & States.Duration_Ms'Image (States.T_Barrier));

   end Test_03_Initialize_Sets_Barrier_And_Dwell;

   procedure Test_04_Initialize_Clears_Every_Left_Demand (T : in out Test) is
      --@covers llr_4_controller.4

      pragma Unreferenced (T);

      State : Controller.Controller_State;
   begin

      --  "for every approach" over a four-value enumeration: every element is
      --  read, none sampled.

      Controller.Initialize (State);

      for A in States.Approach loop
         Assert
           (State.Left (A) = No_Left_Demand,
            "Initialize must leave "
            & States.Approach'Image (A)
            & " at NO_LEFT_DEMAND, but left it at "
            & States.Left_Demand_State'Image (State.Left (A)));
      end loop;

   end Test_04_Initialize_Clears_Every_Left_Demand;

   procedure Test_05_Initialize_Clears_Every_Crosswalk (T : in out Test) is
      --@covers llr_4_controller.5

      pragma Unreferenced (T);

      State : Controller.Controller_State;
   begin

      --  "for every crosswalk" over a four-value enumeration, and both fields
      --  the statement names: the pedestrian state and its dwell field. The
      --  timer matters even though NO_PEDESTRIAN_REQUEST carries no dwell --
      --  it is the value the first advance would work from.

      Controller.Initialize (State);

      for C in States.Crosswalk loop
         Assert
           (State.Ped (C) = No_Pedestrian_Request,
            "Initialize must leave "
            & States.Crosswalk'Image (C)
            & " at NO_PEDESTRIAN_REQUEST, but left it at "
            & States.Pedestrian_State'Image (State.Ped (C)));

         Assert
           (State.Ped_Timer (C) = 0,
            "Initialize must leave the "
            & States.Crosswalk'Image (C)
            & " pedestrian dwell at 0, but left it at"
            & States.Duration_Ms'Image (State.Ped_Timer (C))
            & " ms");
      end loop;

   end Test_05_Initialize_Clears_Every_Crosswalk;

   ------------------------------------------------------------------------
   --  The output projection in FAULT (statements 6-8)
   ------------------------------------------------------------------------

   procedure Test_06_Fault_Projects_Flashing_Red_Faces (T : in out Test) is
      --@covers llr_4_controller.6

      pragma Unreferenced (T);

      Outputs : States.Display_State;
   begin

      --  "While State.Mode is FAULT" is unconditional on the rest of the
      --  state: the mode frame pre-empts every sub-machine, so the projection
      --  may not depend on where the pre-empted machines are parked. The
      --  sequencer is therefore swept over its whole alphabet -- twenty
      --  states, all but two of whose NORMAL_OPERATION rows drive a GREEN or
      --  YELLOW face (Reqs_Support.Expected_Faces) -- and both faces of every
      --  approach are read in each. A projection that ignored the mode would
      --  fail on the first state whose row is not all-RED.
      --
      --  The pedestrian half is held in WALK_INTERVAL, a serving state, for
      --  the same reason; its two signals are statements .7 and .8.

      for V in States.Vehicle_Sequencer_State loop
         Outputs :=
           Controller.Project_Outputs
             (Composite_State
                (V             => V,
                 Veh_Remaining => States.T_Sample,
                 M             => Fault,
                 P             => Walk_Interval,
                 Ped_Remaining => States.T_Sample));

         for A in States.Approach loop
            Assert
              (Outputs.Through (A) = Flashing_Red,
               "in FAULT with the sequencer in "
               & States.Vehicle_Sequencer_State'Image (V)
               & " the through face for "
               & States.Approach'Image (A)
               & " must be FLASHING_RED, but was "
               & States.Vehicle_Face'Image (Outputs.Through (A)));

            Assert
              (Outputs.Left (A) = Flashing_Red,
               "in FAULT with the sequencer in "
               & States.Vehicle_Sequencer_State'Image (V)
               & " the left face for "
               & States.Approach'Image (A)
               & " must be FLASHING_RED, but was "
               & States.Vehicle_Face'Image (Outputs.Left (A)));
         end loop;
      end loop;

   end Test_06_Fault_Projects_Flashing_Red_Faces;

   procedure Test_07_Fault_Projects_Dark_Pedestrian_Heads (T : in out Test) is
      --@covers llr_4_controller.7

      pragma Unreferenced (T);

      Outputs : States.Display_State;
   begin

      --  Two quantifiers. "For every crosswalk's pedestrian head" is the
      --  inner loop over the four crosswalks. The "While ... FAULT" is again
      --  unconditional on the pre-empted machines, so the pedestrian alphabet
      --  is swept exhaustively -- six states, whose NORMAL_OPERATION heads
      --  span WALK, FLASH_DONT_WALK and DONT_WALK
      --  (Reqs_Support.Expected_Ped) -- and NONE is required of all of them.
      --  The sequencer is held in a both-through state, whose faces are GREEN
      --  in NORMAL_OPERATION, so the state is not one a mode-blind projection
      --  could get right by accident.

      for P in States.Pedestrian_State loop
         Outputs :=
           Controller.Project_Outputs
             (Composite_State
                (V             => NS_Both_Through,
                 Veh_Remaining => States.T_Sample,
                 M             => Fault,
                 P             => P,
                 Ped_Remaining => States.T_Sample));

         for C in States.Crosswalk loop
            Assert
              (Outputs.Heads (C) = None,
               "in FAULT with every crosswalk in "
               & States.Pedestrian_State'Image (P)
               & " the head for "
               & States.Crosswalk'Image (C)
               & " must be NONE, but was "
               & States.Pedestrian_Head'Image (Outputs.Heads (C)));
         end loop;
      end loop;

   end Test_07_Fault_Projects_Dark_Pedestrian_Heads;

   procedure Test_08_Fault_Projects_No_Request_Indicators (T : in out Test) is
      --@covers llr_4_controller.8

      pragma Unreferenced (T);

      Outputs : States.Display_State;
   begin

      --  Same construction as .7, on the other pedestrian output signal: the
      --  four crosswalks inside the whole six-state pedestrian alphabet, two
      --  of whose NORMAL_OPERATION indicators are REQUEST_PENDING
      --  (Reqs_Support.Expected_Ped), so a mode-blind projection cannot pass.

      for P in States.Pedestrian_State loop
         Outputs :=
           Controller.Project_Outputs
             (Composite_State
                (V             => NS_Both_Through,
                 Veh_Remaining => States.T_Sample,
                 M             => Fault,
                 P             => P,
                 Ped_Remaining => States.T_Sample));

         for C in States.Crosswalk loop
            Assert
              (Outputs.Requests (C) = No_Request,
               "in FAULT with every crosswalk in "
               & States.Pedestrian_State'Image (P)
               & " the request indicator for "
               & States.Crosswalk'Image (C)
               & " must be NO_REQUEST, but was "
               & States.Request_Indicator'Image (Outputs.Requests (C)));
         end loop;
      end loop;

   end Test_08_Fault_Projects_No_Request_Indicators;

   ------------------------------------------------------------------------
   --  The output projection in NORMAL_OPERATION (statements 9-11)
   ------------------------------------------------------------------------

   procedure Test_09_Normal_Projects_Vehicle_Faces (T : in out Test) is
      --@covers llr_4_controller.9

      pragma Unreferenced (T);
   begin

      --  Vehicle_Face_Outputs is private to the Controller body, so "the
      --  through and left faces of Vehicle_Face_Outputs (State.Vehicle)" can
      --  only be rendered through the transcription of that table in
      --  Reqs_Support.Expected_Faces. The observable is therefore shared with
      --  llr_4_controller_1_vehicle.3-.24: a wrong row fails both this routine
      --  and that row's own.
      --
      --  What this routine adds, and what those rows do not claim, is that the
      --  forwarding is total over the sequencer alphabet and reads
      --  State.Vehicle alone: every one of the twenty states is projected, and
      --  the pedestrian half is held in a serving state rather than idle, so a
      --  projection whose vehicle faces were disturbed by a pedestrian service
      --  would fail here.

      for V in States.Vehicle_Sequencer_State loop
         declare
            Expected : constant Reqs_Support.Face_Row :=
              Reqs_Support.Expected_Faces (V);

            Outputs : constant States.Display_State :=
              Controller.Project_Outputs
                (Composite_State
                   (V             => V,
                    Veh_Remaining => States.T_Sample,
                    P             => Walk_Interval,
                    Ped_Remaining => States.T_Sample));
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
         end;
      end loop;

   end Test_09_Normal_Projects_Vehicle_Faces;

   procedure Test_10_Normal_Projects_Pedestrian_Heads (T : in out Test) is
      --@covers llr_4_controller.10

      pragma Unreferenced (T);
   begin

      --  Head_Of is private to the Controller body, so the row is observed
      --  through Project_Outputs against the transcription in
      --  Reqs_Support.Expected_Ped -- as with .9, the same observable as
      --  llr_4_controller_3_pedestrian.1-.5.
      --
      --  The claim this routine carries is the indexing: "for each crosswalk,
      --  Head_Of (State.Ped (C))". So one crosswalk at a time is put in each
      --  of the six pedestrian states, and the other three -- left in the
      --  power-on state -- are required to show that state's head. A
      --  projection that read one crosswalk's state for all four, or crossed
      --  the index, fails on the first cell. Twenty-four cells, the whole
      --  crosswalk x pedestrian-state product.

      for P in States.Pedestrian_State loop
         for C in States.Crosswalk loop
            declare
               Outputs : constant States.Display_State :=
                 Controller.Project_Outputs
                   (Reqs_Support.Pedestrian_State
                      (C, P, Remaining => States.T_Sample));
            begin
               Assert
                 (Outputs.Heads (C) = Reqs_Support.Expected_Ped (P).Head,
                  "with "
                  & States.Crosswalk'Image (C)
                  & " in "
                  & States.Pedestrian_State'Image (P)
                  & " its head was "
                  & States.Pedestrian_Head'Image (Outputs.Heads (C))
                  & " but the requirement gives "
                  & States.Pedestrian_Head'Image
                      (Reqs_Support.Expected_Ped (P).Head));

               for Other in States.Crosswalk loop
                  if Other /= C then
                     Assert
                       (Outputs.Heads (Other)
                        = Reqs_Support.Expected_Ped (No_Pedestrian_Request)
                            .Head,
                        "with only "
                        & States.Crosswalk'Image (C)
                        & " in "
                        & States.Pedestrian_State'Image (P)
                        & ", the head for "
                        & States.Crosswalk'Image (Other)
                        & " must still be that of NO_PEDESTRIAN_REQUEST, but"
                        & " was "
                        & States.Pedestrian_Head'Image
                            (Outputs.Heads (Other)));
                  end if;
               end loop;
            end;
         end loop;
      end loop;

   end Test_10_Normal_Projects_Pedestrian_Heads;

   procedure Test_11_Normal_Projects_Request_Indicators (T : in out Test) is
      --@covers llr_4_controller.11

      pragma Unreferenced (T);
   begin

      --  Same construction as .10, on the other pedestrian output signal:
      --  one crosswalk at a time through the whole pedestrian alphabet, with
      --  the other three required to keep showing the power-on state's
      --  indicator, so the per-crosswalk indexing is what is asserted.

      for P in States.Pedestrian_State loop
         for C in States.Crosswalk loop
            declare
               Outputs : constant States.Display_State :=
                 Controller.Project_Outputs
                   (Reqs_Support.Pedestrian_State
                      (C, P, Remaining => States.T_Sample));
            begin
               Assert
                 (Outputs.Requests (C) = Reqs_Support.Expected_Ped (P).Request,
                  "with "
                  & States.Crosswalk'Image (C)
                  & " in "
                  & States.Pedestrian_State'Image (P)
                  & " its request indicator was "
                  & States.Request_Indicator'Image (Outputs.Requests (C))
                  & " but the requirement gives "
                  & States.Request_Indicator'Image
                      (Reqs_Support.Expected_Ped (P).Request));

               for Other in States.Crosswalk loop
                  if Other /= C then
                     Assert
                       (Outputs.Requests (Other)
                        = Reqs_Support.Expected_Ped (No_Pedestrian_Request)
                            .Request,
                        "with only "
                        & States.Crosswalk'Image (C)
                        & " in "
                        & States.Pedestrian_State'Image (P)
                        & ", the request indicator for "
                        & States.Crosswalk'Image (Other)
                        & " must still be that of NO_PEDESTRIAN_REQUEST, but"
                        & " was "
                        & States.Request_Indicator'Image
                            (Outputs.Requests (Other)));
                  end if;
               end loop;
            end;
         end loop;
      end loop;

   end Test_11_Normal_Projects_Request_Indicators;

   ------------------------------------------------------------------------
   --  Step: fault pre-emption (statements 13-15)
   ------------------------------------------------------------------------

   procedure Test_13_Asserted_Fault_Enters_Fault_Mode (T : in out Test) is
      --@covers llr_4_controller.13

      pragma Unreferenced (T);

      Dwells : constant array (1 .. 2) of States.Duration_Ms :=
        (1 => States.T_Sample, 2 => 2 * States.T_Sample);
      --  A boundary step (one on which a timed transition also fires) and a
      --  pure sampling step. The mode change may not depend on which.

      Sensors : States.Sensors_State := Reqs_Support.Quiet;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The trigger is one input value, so the snapshot is the quiet one with
      --  only the fault line raised: whatever changes is attributable to that
      --  line and nothing else.
      --
      --  "While State.Mode is NORMAL_OPERATION" quantifies over every normal
      --  state, so the sequencer is swept over its whole alphabet, and each
      --  state is run at both dwell values -- a fault landing on a transition
      --  boundary must be pre-emptive too, which is the one case where the
      --  entry competes with other work in the same step.

      Sensors.Fault := Asserted;

      for V in States.Vehicle_Sequencer_State loop
         for K in Dwells'Range loop
            State := Composite_State (V, Veh_Remaining => Dwells (K));

            Controller.Step (State, Sensors, Outputs);

            Assert
              (State.Mode = Fault,
               "a step with the fault line ASSERTED from "
               & States.Vehicle_Sequencer_State'Image (V)
               & " with"
               & States.Duration_Ms'Image (Dwells (K))
               & " ms of dwell left must set the mode to FAULT, but left it "
               & States.Mode'Image (State.Mode));
         end loop;
      end loop;

   end Test_13_Asserted_Fault_Enters_Fault_Mode;

   procedure Test_14_Fault_Step_Emits_The_Projection (T : in out Test) is
      --@covers llr_4_controller.14

      pragma Unreferenced (T);

      State    : Controller.Controller_State;
      Expected : States.Display_State;
      Outputs  : States.Display_State;
   begin

      --  The statement ties Step's outputs to Project_Outputs of the state, so
      --  the expectation is that function's result on the state handed to Step
      --  -- not a re-transcription of the FAULT rows, which are statements
      --  .6-.8 and fail there if they are wrong. Statement .15 makes the two
      --  readings of "State" coincide: a FAULT step returns the state it was
      --  given, so projecting before the step is projecting the same state.
      --
      --  Swept over the sequencer and pedestrian alphabets -- a hundred and
      --  twenty composite states -- with every input asserted, so no parking
      --  choice is what makes the equality hold. Note the outputs of a FAULT
      --  step are unaffected by the emit-versus-advance phase this file's
      --  statement .16 governs: FAULT has no timed transition to be out of
      --  phase with.

      for V in States.Vehicle_Sequencer_State loop
         for P in States.Pedestrian_State loop
            State :=
              Composite_State
                (V             => V,
                 Veh_Remaining => States.T_Sample,
                 M             => Fault,
                 P             => P,
                 Ped_Remaining => States.T_Sample,
                 L             => Left_Demand_Pending);

            Expected := Controller.Project_Outputs (State);

            Controller.Step (State, Loud, Outputs);

            Check_Display
              (Outputs,
               Expected,
               "a FAULT step from "
               & States.Vehicle_Sequencer_State'Image (V)
               & " with every crosswalk in "
               & States.Pedestrian_State'Image (P));
         end loop;
      end loop;

   end Test_14_Fault_Step_Emits_The_Projection;

   procedure Test_15_Fault_Step_Changes_Nothing (T : in out Test) is
      --@covers llr_4_controller.15

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  FAULT is terminal, so the check is exhaustive over what a step could
      --  otherwise have changed, and each dimension is set up so that a
      --  NORMAL_OPERATION step would demonstrably change it:
      --
      --  * arming -- every left-turn detector reads VEHICLE_PRESENT and every
      --    button PRESSED against demand-free approaches and a crosswalk state
      --    swept over the whole pedestrian alphabet, so the two arming guards
      --    (llr_4_controller_2_left_demand.1,
      --    llr_4_controller_3_pedestrian.10/.11) are open in the states that
      --    admit them;
      --  * advancing -- every timer is left with exactly one sampling period,
      --    the value at which .17's advance would be observable and .18's
      --    transition would fire;
      --  * edges -- firing that transition is what would key the GREEN-edge
      --    couplings (.19, .20), so a sequencer that advanced would take the
      --    demand-clear and pedestrian-service edges with it.
      --
      --  The whole state record is then read back field by field. Veh_Lag is
      --  not read: llr_4_controller.1 does not give the record that field, so
      --  no statement says what it holds.

      for V in States.Vehicle_Sequencer_State loop
         for P in States.Pedestrian_State loop
            State :=
              Composite_State
                (V             => V,
                 Veh_Remaining => States.T_Sample,
                 M             => Fault,
                 P             => P,
                 Ped_Remaining => States.T_Sample);

            Controller.Step (State, Loud, Outputs);

            declare
               Where : constant String :=
                 "a FAULT step from "
                 & States.Vehicle_Sequencer_State'Image (V)
                 & " with every crosswalk in "
                 & States.Pedestrian_State'Image (P);
            begin
               Assert
                 (State.Mode = Fault,
                  Where
                  & " must leave the mode FAULT, but left it "
                  & States.Mode'Image (State.Mode));

               Assert
                 (State.Vehicle = V,
                  Where
                  & " must not advance the sequencer, but it moved to "
                  & States.Vehicle_Sequencer_State'Image (State.Vehicle));

               Assert
                 (State.Veh_Timer = States.T_Sample,
                  Where
                  & " must not advance the sequencer dwell, but it now reads"
                  & States.Duration_Ms'Image (State.Veh_Timer)
                  & " ms");

               for A in States.Approach loop
                  Assert
                    (State.Left (A) = No_Left_Demand,
                     Where
                     & " must not arm "
                     & States.Approach'Image (A)
                     & ", but its demand is "
                     & States.Left_Demand_State'Image (State.Left (A)));
               end loop;

               for C in States.Crosswalk loop
                  Assert
                    (State.Ped (C) = P,
                     Where
                     & " must leave "
                     & States.Crosswalk'Image (C)
                     & " where it was, but it is now "
                     & States.Pedestrian_State'Image (State.Ped (C)));

                  Assert
                    (State.Ped_Timer (C) = States.T_Sample,
                     Where
                     & " must not advance the "
                     & States.Crosswalk'Image (C)
                     & " dwell, but it now reads"
                     & States.Duration_Ms'Image (State.Ped_Timer (C))
                     & " ms");
               end loop;
            end;
         end loop;
      end loop;

   end Test_15_Fault_Step_Changes_Nothing;

   ------------------------------------------------------------------------
   --  Step: advance and emit (statements 16-20)
   ------------------------------------------------------------------------

   procedure Test_16_Outputs_Project_The_Resulting_State (T : in out Test) is
      --@covers llr_4_controller.16

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The statement names the state whose projection the outputs must be:
      --  the one *resulting* from this step's arming and timed transition. The
      --  file's context says the same twice ("... then emits the resulting
      --  state"). So the expectation is Project_Outputs of the state Step
      --  returns -- the requirement's own words, computed rather than
      --  tabulated, which is also what keeps this routine independent of every
      --  output row.
      --
      --  Three groups, in ascending strength:
      --
      --  1. Pure sampling steps: nothing is armed and no dwell elapses, so the
      --     resulting state is the state given, and the equality is the
      --     unchanged re-emission the context describes.
      --  2. Arming steps: every button pressed against idle crosswalks, so the
      --     resulting state has requests pending and its projection has lit
      --     lamps. This is the "arming (llr_4_controller_3_pedestrian.10-.11)"
      --     half of the statement -- outputs emitted before arming would still
      --     show NO_REQUEST.
      --  3. Boundary steps: one sampling period of dwell left in each of the
      --     twenty sequencer states, so each step fires a timed transition and
      --     the resulting state's faces differ from the state's before it.
      --     This is the "and timed transition (statements 18-20)" half.
      --
      --  GROUP 3 IS EXPECTED TO FAIL, and is written faithfully anyway. The
      --  implementation emits the outputs before it advances the timers and
      --  fires the transition, and never recomputes them, so every Moore
      --  output appears one sampling period after the state change that
      --  produced it. The expectation here is the requirement's, not the
      --  code's; weakening it (a tolerance, a one-step lag, skipping the
      --  group) would delete the only place the divergence is visible.

      for V in States.Vehicle_Sequencer_State loop
         State := Composite_State (V, Veh_Remaining => 3 * States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Check_Display
           (Outputs,
            Controller.Project_Outputs (State),
            "a pure sampling step in "
            & States.Vehicle_Sequencer_State'Image (V));
      end loop;

      for V in States.Vehicle_Sequencer_State loop
         State := Composite_State (V, Veh_Remaining => 3 * States.T_Sample);

         Controller.Step (State, Loud, Outputs);

         Check_Display
           (Outputs,
            Controller.Project_Outputs (State),
            "an arming step in " & States.Vehicle_Sequencer_State'Image (V));
      end loop;

      for V in States.Vehicle_Sequencer_State loop
         State := Composite_State (V, Veh_Remaining => States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Check_Display
           (Outputs,
            Controller.Project_Outputs (State),
            "the step on whose boundary the "
            & States.Vehicle_Sequencer_State'Image (V)
            & " dwell elapses");
      end loop;

   end Test_16_Outputs_Project_The_Resulting_State;

   procedure Test_17_Step_Advances_Every_Running_Timer (T : in out Test) is
      --@covers llr_4_controller.17

      pragma Unreferenced (T);

      Start : constant States.Duration_Ms := 3 * States.T_Sample;
      --  More than one sampling period, so no timed transition fires within
      --  the step (.18) and what is observed is the advance alone.

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The statement enumerates the running timers, so both are read: the
      --  sequencer's, which always runs in NORMAL_OPERATION, and each
      --  crosswalk's, which runs exactly while that crosswalk is in
      --  Serving_Pedestrian_State. The sweep is the product of the sequencer's
      --  twenty states and the four serving pedestrian states, with all four
      --  crosswalks serving at once -- so "every running timer" is nine timers
      --  advancing in the same step, not one at a time.
      --
      --  "By exactly T_SAMPLE" is an equality against Start - T_SAMPLE, so the
      --  routine fails on an advance that is short, long, or absent. Whether a
      --  non-serving crosswalk's timer runs at all is
      --  llr_4_controller_3_pedestrian.17 and is not asserted here.

      for V in States.Vehicle_Sequencer_State loop
         for P in States.Serving_Pedestrian_State loop
            State :=
              Composite_State
                (V             => V,
                 Veh_Remaining => Start,
                 P             => P,
                 Ped_Remaining => Start);

            Controller.Step (State, Reqs_Support.Quiet, Outputs);

            Assert
              (State.Veh_Timer = Start - States.T_Sample,
               "one step from "
               & States.Vehicle_Sequencer_State'Image (V)
               & " must advance the sequencer dwell by exactly T_SAMPLE, from"
               & States.Duration_Ms'Image (Start)
               & " ms to"
               & States.Duration_Ms'Image (Start - States.T_Sample)
               & " ms, but it now reads"
               & States.Duration_Ms'Image (State.Veh_Timer)
               & " ms");

            for C in States.Crosswalk loop
               Assert
                 (State.Ped_Timer (C) = Start - States.T_Sample,
                  "one step with "
                  & States.Crosswalk'Image (C)
                  & " in "
                  & States.Pedestrian_State'Image (P)
                  & " must advance its dwell by exactly T_SAMPLE, from"
                  & States.Duration_Ms'Image (Start)
                  & " ms to"
                  & States.Duration_Ms'Image (Start - States.T_Sample)
                  & " ms, but it now reads"
                  & States.Duration_Ms'Image (State.Ped_Timer (C))
                  & " ms");
            end loop;
         end loop;
      end loop;

   end Test_17_Step_Advances_Every_Running_Timer;

   procedure Test_18_Transition_Fires_On_Its_Boundary_Step (T : in out Test) is
      --@covers llr_4_controller.18

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The claim is *when* a timed transition fires: on the step whose
      --  remaining dwell is at most T_SAMPLE, and not before. Every dwell is
      --  an integral multiple of T_SAMPLE (llr_1_states.31), so the boundary
      --  is exactly one step wide and two cases bracket it -- one sampling
      --  period left, where the machine must move, and two, where it must not.
      --  A test with only the first passes against code that fires a step
      --  early.
      --
      --  Both timed machines are swept: the sequencer over its whole alphabet
      --  (every one of the twenty states has a timed exit, statements
      --  llr_4_controller_1_vehicle.25-.50) and a crosswalk over the four
      --  serving states (llr_4_controller_3_pedestrian.13-.16).
      --
      --  What is asserted is that the machine left its state, not which state
      --  it entered: the target is the child statement's claim, and two of the
      --  twenty sequencer targets (llr_4_controller_1_vehicle.31 and .44, the
      --  two HOLD states) do not exist in the implementation at all (#63).
      --  Firing is observable without them.
      --
      --  The sentence's remaining clause -- that a fired transition's guard is
      --  evaluated against the inputs armed on that same step -- is the
      --  property statement 22 states in its CONOPS 4.3 form, and is asserted
      --  by that routine rather than duplicated here.

      for V in States.Vehicle_Sequencer_State loop
         State := Composite_State (V, Veh_Remaining => 2 * States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (State.Vehicle = V,
            "with two sampling periods of dwell left the sequencer must stay"
            & " in "
            & States.Vehicle_Sequencer_State'Image (V)
            & ", but it moved to "
            & States.Vehicle_Sequencer_State'Image (State.Vehicle));

         State := Composite_State (V, Veh_Remaining => States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (State.Vehicle /= V,
            "on the step whose remaining dwell is one sampling period the"
            & " sequencer must leave "
            & States.Vehicle_Sequencer_State'Image (V)
            & ", but it is still there");
      end loop;

      --  The pedestrian services, with the sequencer parked mid-dwell in
      --  EW_BARRIER_ALLRED -- every face RED (llr_4_controller_1_vehicle.24)
      --  and no advance -- so no through face can rise to GREEN and key a
      --  service edge onto a crosswalk under test.

      for P in States.Serving_Pedestrian_State loop
         State :=
           Composite_State
             (V             => EW_Barrier_Allred,
              Veh_Remaining => 3 * States.T_Sample,
              P             => P,
              Ped_Remaining => 2 * States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         for C in States.Crosswalk loop
            Assert
              (State.Ped (C) = P,
               "with two sampling periods of dwell left "
               & States.Crosswalk'Image (C)
               & " must stay in "
               & States.Pedestrian_State'Image (P)
               & ", but it moved to "
               & States.Pedestrian_State'Image (State.Ped (C)));
         end loop;

         State :=
           Composite_State
             (V             => EW_Barrier_Allred,
              Veh_Remaining => 3 * States.T_Sample,
              P             => P,
              Ped_Remaining => States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         for C in States.Crosswalk loop
            Assert
              (State.Ped (C) /= P,
               "on the step whose remaining dwell is one sampling period "
               & States.Crosswalk'Image (C)
               & " must leave "
               & States.Pedestrian_State'Image (P)
               & ", but it is still there");
         end loop;
      end loop;

   end Test_18_Transition_Fires_On_Its_Boundary_Step;

   procedure Test_19_Green_Edge_Clears_Left_Demand (T : in out Test) is
      --@covers llr_4_controller.19

      pragma Unreferenced (T);

      type Clear_Case is record
         A     : States.Approach;
         Rises : States.Approach;
         From  : States.Vehicle_Sequencer_State;
      end record;
      --  A is the approach whose demand is latched. Rises is
      --  Conflicts.Next_Conflicting_Through (A), transcribed from
      --  llr_3_conflicts.4: NORTH to SOUTH, SOUTH to EAST, EAST to WEST, WEST
      --  to NORTH. From is a sequencer state whose timed exit raises that
      --  through from not-GREEN to GREEN, so the step under test carries the
      --  edge the statement keys on.

      Cases : constant array (1 .. 4) of Clear_Case :=
        (1 => (A => North, Rises => South, From => N_Lead_Clear),
         2 => (A => South, Rises => East, From => NS_Barrier_Allred),
         3 => (A => East, Rises => West, From => E_Lead_Clear),
         4 => (A => West, Rises => North, From => EW_Barrier_Allred));

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  All four approaches, since the coupling is per-approach and the
      --  geometry map it is keyed through is a permutation -- an
      --  implementation that clears the wrong approach passes any single case
      --  chosen to match it.
      --
      --  Each case brackets the step it is about with the two halves of the
      --  key, read from the transcribed face table rather than assumed: the
      --  through is required not to be GREEN in the state before the step and
      --  to be GREEN in the state after it. A failure of either says the
      --  scaffolding did not present an edge, which is distinguishable from
      --  the requirement's consequence failing. Only the approach under test
      --  is latched, so a clear that spilled onto another approach is caught
      --  by the case that tests that approach.

      for K in Cases'Range loop
         State := Composite_State (Cases (K).From, States.T_Sample);
         State.Left (Cases (K).A) := Left_Demand_Pending;

         Assert
           (Reqs_Support.Expected_Faces (Cases (K).From).Through
              (Cases (K).Rises)
            /= Green,
            "scaffolding: the "
            & States.Approach'Image (Cases (K).Rises)
            & " through must not be GREEN in "
            & States.Vehicle_Sequencer_State'Image (Cases (K).From)
            & " for this step to be a rising edge");

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (Reqs_Support.Expected_Faces (State.Vehicle).Through
              (Cases (K).Rises)
            = Green,
            "scaffolding: the step out of "
            & States.Vehicle_Sequencer_State'Image (Cases (K).From)
            & " was meant to raise the "
            & States.Approach'Image (Cases (K).Rises)
            & " through to GREEN, but it went to "
            & States.Vehicle_Sequencer_State'Image (State.Vehicle));

         Assert
           (State.Left (Cases (K).A) = No_Left_Demand,
            "the "
            & States.Approach'Image (Cases (K).Rises)
            & " through rising to GREEN must clear the "
            & States.Approach'Image (Cases (K).A)
            & " demand, but it is "
            & States.Left_Demand_State'Image (State.Left (Cases (K).A)));
      end loop;

      --  The other half of the key: GREEN in the state after the step is not
      --  enough, it must not have been GREEN before it. NS_BOTH_THROUGH holds
      --  the SOUTH through GREEN (llr_4_controller_1_vehicle.6), and parked
      --  mid-dwell no transition fires, so this step presents no rising edge
      --  and the NORTH demand -- whose Next_Conflicting_Through is SOUTH --
      --  must survive it. A clear keyed on the level rather than the edge
      --  fails here, and would take the demand a whole phase too early.

      State := Composite_State (NS_Both_Through, 3 * States.T_Sample);
      State.Left (North) := Left_Demand_Pending;

      Assert
        (Reqs_Support.Expected_Faces (NS_Both_Through).Through (South) = Green,
         "scaffolding: the SOUTH through must be GREEN in NS_BOTH_THROUGH for"
         & " this step to be a level without an edge");

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Left (North) = Left_Demand_Pending,
         "with the SOUTH through already GREEN and no transition on this step"
         & " the NORTH demand must stay LEFT_DEMAND_PENDING, but it is "
         & States.Left_Demand_State'Image (State.Left (North)));

   end Test_19_Green_Edge_Clears_Left_Demand;

   procedure Test_20_Green_Edge_Serves_Pedestrian_Request (T : in out Test) is
      --@covers llr_4_controller.20

      pragma Unreferenced (T);

      type Serve_Case is record
         C     : States.Crosswalk;
         Rises : States.Approach;
         From  : States.Vehicle_Sequencer_State;
      end record;
      --  C is the crosswalk whose request is pending. Rises is
      --  Conflicts.Adjacent_Through (C), transcribed from llr_3_conflicts.5:
      --  NORTH_SIDE to WEST, SOUTH_SIDE to EAST, EAST_SIDE to NORTH,
      --  WEST_SIDE to SOUTH. From is a sequencer state whose timed exit raises
      --  that through from not-GREEN to GREEN.

      Cases : constant array (1 .. 4) of Serve_Case :=
        (1 => (C => North_Side, Rises => West, From => E_Lead_Clear),
         2 => (C => South_Side, Rises => East, From => NS_Barrier_Allred),
         3 => (C => East_Side, Rises => North, From => EW_Barrier_Allred),
         4 => (C => West_Side, Rises => South, From => N_Lead_Clear));

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  Same construction as .19, on the other coupling and the other
      --  geometry map: all four crosswalks, with the two halves of the key
      --  bracketed from the transcribed face table, and the negative case that
      --  separates the edge from the level.
      --
      --  The assertion is on State.Ped, not on the emitted head. The statement
      --  says Step applies the service edge, and what the edge does is set the
      --  crosswalk's state (llr_4_controller_3_pedestrian.12), so the
      --  resulting state is where the claim lives. Reading the WALK head off
      --  Outputs instead would also fail for statement .16's cause -- the
      --  implementation emits before it advances, so the head trails the state
      --  by a step -- and two requirements failing for one defect is what
      --  one-routine-per-statement is meant to prevent. The dwell the edge
      --  loads (T_WALK) is llr_4_controller_3_pedestrian.12's value and is not
      --  asserted here.

      for K in Cases'Range loop
         State := Composite_State (Cases (K).From, States.T_Sample);
         State.Ped (Cases (K).C) := Pending_Pedestrian_Request;

         Assert
           (Reqs_Support.Expected_Faces (Cases (K).From).Through
              (Cases (K).Rises)
            /= Green,
            "scaffolding: the "
            & States.Approach'Image (Cases (K).Rises)
            & " through must not be GREEN in "
            & States.Vehicle_Sequencer_State'Image (Cases (K).From)
            & " for this step to be a rising edge");

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (Reqs_Support.Expected_Faces (State.Vehicle).Through
              (Cases (K).Rises)
            = Green,
            "scaffolding: the step out of "
            & States.Vehicle_Sequencer_State'Image (Cases (K).From)
            & " was meant to raise the "
            & States.Approach'Image (Cases (K).Rises)
            & " through to GREEN, but it went to "
            & States.Vehicle_Sequencer_State'Image (State.Vehicle));

         Assert
           (State.Ped (Cases (K).C) = Walk_Interval,
            "the "
            & States.Approach'Image (Cases (K).Rises)
            & " through rising to GREEN must serve the "
            & States.Crosswalk'Image (Cases (K).C)
            & " request, but that crosswalk is "
            & States.Pedestrian_State'Image (State.Ped (Cases (K).C)));

         for Other in States.Crosswalk loop
            if Other /= Cases (K).C then
               Assert
                 (State.Ped (Other) = No_Pedestrian_Request,
                  "serving "
                  & States.Crosswalk'Image (Cases (K).C)
                  & " must leave "
                  & States.Crosswalk'Image (Other)
                  & " at NO_PEDESTRIAN_REQUEST, but it is "
                  & States.Pedestrian_State'Image (State.Ped (Other)));
            end if;
         end loop;
      end loop;

      --  Edge, not level: NS_BOTH_THROUGH holds the NORTH through GREEN
      --  (llr_4_controller_1_vehicle.6) and parked mid-dwell nothing fires, so
      --  EAST_SIDE -- whose Adjacent_Through is NORTH -- must stay pending. A
      --  service keyed on the level would start a WALK in the middle of a
      --  green, with no clearance time left in the phase for it.

      State := Composite_State (NS_Both_Through, 3 * States.T_Sample);
      State.Ped (East_Side) := Pending_Pedestrian_Request;

      Assert
        (Reqs_Support.Expected_Faces (NS_Both_Through).Through (North) = Green,
         "scaffolding: the NORTH through must be GREEN in NS_BOTH_THROUGH for"
         & " this step to be a level without an edge");

      Controller.Step (State, Reqs_Support.Quiet, Outputs);

      Assert
        (State.Ped (East_Side) = Pending_Pedestrian_Request,
         "with the NORTH through already GREEN and no transition on this step"
         & " EAST_SIDE must stay PENDING_PEDESTRIAN_REQUEST, but it is "
         & States.Pedestrian_State'Image (State.Ped (East_Side)));

   end Test_20_Green_Edge_Serves_Pedestrian_Request;

   ------------------------------------------------------------------------
   --  Step: the sampling boundary (statement 22)
   ------------------------------------------------------------------------

   procedure Test_22_Boundary_Demand_Served_At_This_Onset (T : in out Test) is
      --@covers llr_4_controller.22

      pragma Unreferenced (T);

      type Serve_Case is record
         C    : States.Crosswalk;
         From : States.Vehicle_Sequencer_State;
      end record;
      --  C is the crosswalk whose button is pressed on the boundary step, and
      --  From a sequencer state whose timed exit raises Adjacent_Through (C)
      --  to GREEN -- the same four pairings as statement .20's routine, from
      --  llr_3_conflicts.5.

      Cases : constant array (1 .. 4) of Serve_Case :=
        (1 => (C => North_Side, From => E_Lead_Clear),
         2 => (C => South_Side, From => NS_Barrier_Allred),
         3 => (C => East_Side, From => EW_Barrier_Allred),
         4 => (C => West_Side, From => N_Lead_Clear));

      Sensors : States.Sensors_State;

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The statement is an ordering claim: the transition and its couplings
      --  are evaluated against the inputs armed *at the step the transition
      --  occurs on*, so a demand that arrives no later than that step is
      --  served by the green it arrived in time for, rather than a cycle
      --  later. Both couplings are asserted, each in its own form, and both on
      --  resulting state rather than on emitted outputs -- see .20's routine
      --  for why, and note that a state served this step is what the claim is
      --  about; when its head lights is statement .16's phase.
      --
      --  First the pedestrian request. Each case starts with the crosswalk
      --  idle and presses its button on the one step whose boundary raises the
      --  adjacent through to GREEN, so the arming and the service edge have to
      --  land in the same step for the request to be served at all: the WALK
      --  onset and the green onset coincide. Deferred arming, or a coupling
      --  computed from the previous step's inputs, leaves the crosswalk
      --  PENDING and the walk waits a whole cycle. All four crosswalks, since
      --  the geometry map is a permutation.

      for K in Cases'Range loop
         State := Composite_State (Cases (K).From, States.T_Sample);

         Sensors := Reqs_Support.Quiet;
         Sensors.Buttons (Cases (K).C) := Pressed;

         Controller.Step (State, Sensors, Outputs);

         Assert
           (State.Ped (Cases (K).C) = Walk_Interval,
            "a press on "
            & States.Crosswalk'Image (Cases (K).C)
            & " at the step whose boundary raises its adjacent through to"
            & " GREEN must be served at that onset, leaving the crosswalk in"
            & " WALK_INTERVAL, but it is "
            & States.Pedestrian_State'Image (State.Ped (Cases (K).C)));
      end loop;

      --  Then the left-turn detection. The barrier exits are the two
      --  transitions whose guard reads a left-turn demand
      --  (llr_4_controller_1_vehicle.25/.26 and .38/.39), so a detection armed
      --  on the boundary step routes the axis into its protected left instead
      --  of straight into the both-through phase. Both targets are the
      --  requirement's -- the assertion distinguishes the two branches the
      --  pair of statements gives, which is the whole of what "served at that
      --  onset rather than deferred a cycle" means here.
      --
      --  The lagging-left guards (llr_4_controller_1_vehicle.30/.31, .43/.44)
      --  state the same property at the commit boundary and are not asserted:
      --  the implementation decides the lag at both-through entry instead, the
      --  divergence tracked by #63.

      State := Composite_State (EW_Barrier_Allred, States.T_Sample);

      Sensors := Reqs_Support.Quiet;
      Sensors.Left_Turns (North) := Vehicle_Present;

      Controller.Step (State, Sensors, Outputs);

      Assert
        (State.Vehicle = N_Lead,
         "a NORTH left-turn vehicle observed at the step whose boundary ends"
         & " the barrier must be served by this axis, entering N_LEAD, but the"
         & " sequencer went to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));

      State := Composite_State (NS_Barrier_Allred, States.T_Sample);

      Sensors := Reqs_Support.Quiet;
      Sensors.Left_Turns (East) := Vehicle_Present;

      Controller.Step (State, Sensors, Outputs);

      Assert
        (State.Vehicle = E_Lead,
         "an EAST left-turn vehicle observed at the step whose boundary ends"
         & " the barrier must be served by this axis, entering E_LEAD, but the"
         & " sequencer went to "
         & States.Vehicle_Sequencer_State'Image (State.Vehicle));

   end Test_22_Boundary_Demand_Served_At_This_Onset;

end Llr_4_Controller_Tests;
