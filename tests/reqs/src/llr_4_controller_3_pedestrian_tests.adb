with AUnit.Assertions; use AUnit.Assertions;

with Conflicts;
with Controller;
with Reqs_Support;
with States;

package body Llr_4_Controller_3_Pedestrian_Tests is

   use all type States.Approach;
   use all type States.Crosswalk;
   use all type States.Pedestrian_Button;
   use all type States.Pedestrian_Head;
   use all type States.Pedestrian_State;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   use type States.Duration_Ms;

   ------------------------------------------------------------------------
   --  Moore output helpers
   ------------------------------------------------------------------------

   Idle_Head : constant States.Pedestrian_Head :=
     Reqs_Support.Expected_Ped (No_Pedestrian_Request).Head;
   --  The head the three crosswalks not under test must show: they are in
   --  NO_PEDESTRIAN_REQUEST, so this is statement .1's own value, named here
   --  because it is used for a different purpose -- showing that the state
   --  under test drives its own crosswalk's head and no other's.

   Idle_Request : constant States.Request_Indicator :=
     Reqs_Support.Expected_Ped (No_Pedestrian_Request).Request;
   --  Likewise for the request indicator, from statement .6.

   procedure Check_Head (P : States.Pedestrian_State);
   --  Assert, for each crosswalk in turn, that the pedestrian head
   --  Project_Outputs emits for a crosswalk in state P is the Head column
   --  llr_4_controller_3_pedestrian transcribed into
   --  Reqs_Support.Expected_Ped, and that the other three crosswalks still
   --  show the idle head. Shared by the five head routines so each is a single
   --  call naming its own state.
   --
   --  Head_Of is private to the Controller body, so the row is observed
   --  through Project_Outputs -- which llr_4_controller.10 requires to return
   --  exactly Head_Of (State.Ped (C)) for each crosswalk in NORMAL_OPERATION.
   --  The state is *constructed and projected* rather than reached by
   --  stepping, because these statements are about the output function itself;
   --  nothing here depends on when in a step the outputs are emitted.
   --
   --  Only the heads are checked: the vehicle faces belong to the sequencer
   --  and the request indicators to statements .6-.9.

   procedure Check_Request (P : States.Pedestrian_State);
   --  As Check_Head, for the request indicator: Request_Of, reached through
   --  llr_4_controller.11.

   procedure Check_Head (P : States.Pedestrian_State) is
      Expected : constant States.Pedestrian_Head :=
        Reqs_Support.Expected_Ped (P).Head;
   begin

      --  The statements quantify over the crosswalk ("that crosswalk's
      --  pedestrian head"), and Crosswalk is a four-value enumeration, so the
      --  quantifier is discharged by running every crosswalk rather than
      --  picking one. Pedestrian_State (C, P) puts one crosswalk in P and
      --  leaves the other three idle, so each run also shows the output does
      --  not spill onto the others.

      for C in States.Crosswalk loop
         declare
            Outputs : constant States.Display_State :=
              Controller.Project_Outputs
                (Reqs_Support.Pedestrian_State (C, P));
         begin
            Assert
              (Outputs.Heads (C) = Expected,
               States.Pedestrian_State'Image (P)
               & " on "
               & States.Crosswalk'Image (C)
               & ": head was "
               & States.Pedestrian_Head'Image (Outputs.Heads (C))
               & " but the requirement gives "
               & States.Pedestrian_Head'Image (Expected));

            for Other in States.Crosswalk loop
               if Other /= C then
                  Assert
                    (Outputs.Heads (Other) = Idle_Head,
                     States.Pedestrian_State'Image (P)
                     & " on "
                     & States.Crosswalk'Image (C)
                     & " must leave the head of "
                     & States.Crosswalk'Image (Other)
                     & " at "
                     & States.Pedestrian_Head'Image (Idle_Head)
                     & ", but it was "
                     & States.Pedestrian_Head'Image (Outputs.Heads (Other)));
               end if;
            end loop;
         end;
      end loop;
   end Check_Head;

   procedure Check_Request (P : States.Pedestrian_State) is
      Expected : constant States.Request_Indicator :=
        Reqs_Support.Expected_Ped (P).Request;
   begin
      for C in States.Crosswalk loop
         declare
            Outputs : constant States.Display_State :=
              Controller.Project_Outputs
                (Reqs_Support.Pedestrian_State (C, P));
         begin
            Assert
              (Outputs.Requests (C) = Expected,
               States.Pedestrian_State'Image (P)
               & " on "
               & States.Crosswalk'Image (C)
               & ": request indicator was "
               & States.Request_Indicator'Image (Outputs.Requests (C))
               & " but the requirement gives "
               & States.Request_Indicator'Image (Expected));

            for Other in States.Crosswalk loop
               if Other /= C then
                  Assert
                    (Outputs.Requests (Other) = Idle_Request,
                     States.Pedestrian_State'Image (P)
                     & " on "
                     & States.Crosswalk'Image (C)
                     & " must leave the request indicator of "
                     & States.Crosswalk'Image (Other)
                     & " at "
                     & States.Request_Indicator'Image (Idle_Request)
                     & ", but it was "
                     & States.Request_Indicator'Image
                         (Outputs.Requests (Other)));
               end if;
            end loop;
         end;
      end loop;
   end Check_Request;

   ------------------------------------------------------------------------
   --  Timed-exit helper
   ------------------------------------------------------------------------

   procedure Check_Timed_Exit
     (From   : States.Pedestrian_State;
      To     : States.Pedestrian_State;
      Loaded : States.Duration_Ms);
   --  Assert, for each crosswalk in turn, that a crosswalk in pedestrian state
   --  From moves to To with Loaded as its new dwell on the step where its
   --  dwell elapses, and does not move on a step one sampling period earlier.
   --  Shared by the four timed-exit routines so each is a single call carrying
   --  the target and dwell its own statement gives.
   --
   --  A timed EARS transition carries two claims, and a test that checks only
   --  the second passes against code that fires a tick early, so both are
   --  checked on either side of the one boundary the requirement names. Every
   --  dwell is an integral multiple of T_SAMPLE (llr_1_states.31) and a
   --  transition fires on the step whose remaining dwell is at most T_SAMPLE
   --  (llr_4_controller.18), so the boundary is exactly one step wide and
   --  there is nothing between the two cases to probe.
   --
   --  The machine is parked at the boundary of its dwell rather than counted
   --  down from the full interval: firing depends only on the remaining dwell
   --  (llr_4_controller.18), and the full value is the *entering* statement's
   --  claim, checked by that statement's own routine.
   --
   --  What is asserted is State.Ped (C) and State.Ped_Timer (C) after the
   --  step, not the outputs the step emitted: these statements are about the
   --  resulting state, and the phase of Step's emit relative to its advance is
   --  llr_4_controller.16's claim, tested there.
   --
   --  The buttons are quiet, so no arming edge (.10, .11) can re-route the
   --  exit, and Pedestrian_State parks the sequencer mid-dwell in a state
   --  whose every face is RED (llr_4_controller_1_vehicle.24), so no through
   --  face rises to GREEN and the service edge (.12) cannot fire either. What
   --  is observed is the timed transition alone.

   procedure Check_Timed_Exit
     (From   : States.Pedestrian_State;
      To     : States.Pedestrian_State;
      Loaded : States.Duration_Ms)
   is
      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin
      for C in States.Crosswalk loop

         --  Before the boundary: two sampling periods of dwell left, so the
         --  state holds and only the timer moves.

         State :=
           Reqs_Support.Pedestrian_State
             (C, From, Remaining => 2 * States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (State.Ped (C) = From,
            States.Crosswalk'Image (C)
            & " with two sampling periods of dwell left must stay in "
            & States.Pedestrian_State'Image (From)
            & ", but moved to "
            & States.Pedestrian_State'Image (State.Ped (C)));

         Assert
           (State.Ped_Timer (C) = States.T_Sample,
            States.Crosswalk'Image (C)
            & ": the unfired step must leave exactly one sampling period of"
            & " dwell, but left"
            & States.Duration_Ms'Image (State.Ped_Timer (C)));

         --  On the boundary: the step whose remaining dwell is one sampling
         --  period is the step on which the dwell elapses.

         State :=
           Reqs_Support.Pedestrian_State
             (C, From, Remaining => States.T_Sample);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         Assert
           (State.Ped (C) = To,
            States.Crosswalk'Image (C)
            & ": on the step where the "
            & States.Pedestrian_State'Image (From)
            & " dwell elapses the crosswalk must enter "
            & States.Pedestrian_State'Image (To)
            & ", but it is in "
            & States.Pedestrian_State'Image (State.Ped (C)));

         Assert
           (State.Ped_Timer (C) = Loaded,
            States.Crosswalk'Image (C)
            & ": entering "
            & States.Pedestrian_State'Image (To)
            & " must load"
            & States.Duration_Ms'Image (Loaded)
            & " ms as its dwell, but the dwell is"
            & States.Duration_Ms'Image (State.Ped_Timer (C)));
      end loop;
   end Check_Timed_Exit;

   ------------------------------------------------------------------------
   --  Service-edge helpers
   ------------------------------------------------------------------------

   function Barrier_Before_Green
     (A : States.Approach) return States.Vehicle_Sequencer_State
   is (case A is
         when North | South => EW_Barrier_Allred,
         when East | West => NS_Barrier_Allred);
   --  The barrier state whose exit raises approach A's through face to GREEN.
   --  From llr_4_controller_1_vehicle: EW_BARRIER_ALLRED with no north left
   --  demand enters NS_BOTH_THROUGH when T_BARRIER elapses (.26), whose row
   --  (.6) drives the N and S throughs GREEN; NS_BARRIER_ALLRED with no east
   --  left demand enters EW_BOTH_THROUGH (.39), whose row (.17) drives the E
   --  and W throughs GREEN. Both barrier rows (.13, .24) are every face RED,
   --  so either exit is a rise on both of its axis's throughs.
   --  @param A The approach whose through face is to rise
   --  @return The barrier state one exit short of that rise

   function Both_Through_After
     (A : States.Approach) return States.Vehicle_Sequencer_State
   is (case A is
         when North | South => NS_Both_Through,
         when East | West => EW_Both_Through);
   --  The state that exit enters -- the target of .26 / .39. Only the target
   --  is used, never the commit interval those two statements load, which is
   --  the part #63 diverges on.
   --  @param A The approach whose through face has risen
   --  @return The both-through state holding it GREEN

   ------------------------------------------------------------------------
   --  Moore outputs: the pedestrian head (statements 1-5)
   ------------------------------------------------------------------------

   procedure Test_01_No_Request_Head_Is_Dont_Walk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.1

      pragma Unreferenced (T);
   begin
      Check_Head (No_Pedestrian_Request);
   end Test_01_No_Request_Head_Is_Dont_Walk;

   procedure Test_02_Pending_Head_Is_Dont_Walk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.2

      pragma Unreferenced (T);
   begin
      Check_Head (Pending_Pedestrian_Request);
   end Test_02_Pending_Head_Is_Dont_Walk;

   procedure Test_03_Walk_Interval_Head_Is_Walk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.3

      pragma Unreferenced (T);
   begin
      Check_Head (Walk_Interval);
   end Test_03_Walk_Interval_Head_Is_Walk;

   procedure Test_04_Change_Head_Is_Flash_Dont_Walk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.4

      pragma Unreferenced (T);
   begin
      Check_Head (Change_Interval);
   end Test_04_Change_Head_Is_Flash_Dont_Walk;

   procedure Test_05_Buffer_Heads_Are_Dont_Walk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.5

      pragma Unreferenced (T);
   begin

      --  The statement speaks for both buffer states, so both are asserted
      --  here: the latch changes the request indicator (.9), not the head.

      Check_Head (Buffer_Interval);
      Check_Head (Buffer_Interval_Latched);
   end Test_05_Buffer_Heads_Are_Dont_Walk;

   ------------------------------------------------------------------------
   --  Moore outputs: the request indicator (statements 6-9)
   ------------------------------------------------------------------------

   procedure Test_06_No_Request_Indicator_Is_No_Request (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.6

      pragma Unreferenced (T);
   begin
      Check_Request (No_Pedestrian_Request);
   end Test_06_No_Request_Indicator_Is_No_Request;

   procedure Test_07_Pending_Indicator_Is_Request_Pending (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.7

      pragma Unreferenced (T);
   begin
      Check_Request (Pending_Pedestrian_Request);
   end Test_07_Pending_Indicator_Is_Request_Pending;

   procedure Test_08_Serving_Indicators_Are_No_Request (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.8

      pragma Unreferenced (T);
   begin

      --  The statement speaks for three states -- the whole serving run except
      --  the latched buffer, whose indicator is .9's claim -- so all three are
      --  asserted here.

      Check_Request (Walk_Interval);
      Check_Request (Change_Interval);
      Check_Request (Buffer_Interval);
   end Test_08_Serving_Indicators_Are_No_Request;

   procedure Test_09_Latched_Indicator_Is_Request_Pending (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.9

      pragma Unreferenced (T);
   begin
      Check_Request (Buffer_Interval_Latched);
   end Test_09_Latched_Indicator_Is_Request_Pending;

   ------------------------------------------------------------------------
   --  Input arming (statements 10-11)
   ------------------------------------------------------------------------

   procedure Test_10_Press_Arms_Idle_Crosswalk (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.10

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Sensors : States.Sensors_State;
      Outputs : States.Display_State;
   begin

      --  A per-crosswalk guarded assignment: while a crosswalk is
      --  NO_PEDESTRIAN_REQUEST, observing PRESSED on its button arms it to
      --  PENDING_PEDESTRIAN_REQUEST.
      --
      --  Crosswalk is a four-value enumeration, so the "for a crosswalk C"
      --  quantifier is discharged by running every crosswalk -- and each is
      --  pressed alone, so the test also shows the arming does not spill onto
      --  the other three.
      --
      --  What is asserted is State.Ped (C) after the step, not the outputs the
      --  step emitted: the claim is about the resulting state. That the
      --  request lamp lights on this same step is llr_4_controller.16's claim
      --  about emit ordering, tested there.
      --
      --  Pedestrian_State parks the sequencer mid-dwell in a state whose every
      --  face is RED, so no through face rises to GREEN during the step and
      --  the service edge (.12) cannot key onto the crosswalk just armed.

      for Armed in States.Crosswalk loop
         State :=
           Reqs_Support.Pedestrian_State (Armed, No_Pedestrian_Request);

         Sensors := Reqs_Support.Quiet;
         Sensors.Buttons (Armed) := Pressed;

         Controller.Step (State, Sensors, Outputs);

         Assert
           (State.Ped (Armed) = Pending_Pedestrian_Request,
            "a press observed on "
            & States.Crosswalk'Image (Armed)
            & " must arm that crosswalk to PENDING_PEDESTRIAN_REQUEST, but it"
            & " is "
            & States.Pedestrian_State'Image (State.Ped (Armed)));

         for Other in States.Crosswalk loop
            if Other /= Armed then
               Assert
                 (State.Ped (Other) = No_Pedestrian_Request,
                  "arming "
                  & States.Crosswalk'Image (Armed)
                  & " must leave "
                  & States.Crosswalk'Image (Other)
                  & " at NO_PEDESTRIAN_REQUEST, but it is "
                  & States.Pedestrian_State'Image (State.Ped (Other)));
            end if;
         end loop;
      end loop;

   end Test_10_Press_Arms_Idle_Crosswalk;

   procedure Test_11_Press_Latches_Buffer_Interval (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.11

      pragma Unreferenced (T);

      Dwell : constant States.Duration_Ms := 3 * States.T_Sample;
      --  Some way into the buffer and more than one sampling period from its
      --  end, so no timed exit (.15) fires during the step and what is left is
      --  the latch alone.

      State   : Controller.Controller_State;
      Sensors : States.Sensors_State;
      Outputs : States.Display_State;
   begin

      --  The second arming edge: a press during the buffer re-routes the
      --  buffer's exit (to .16's target) instead of arming a fresh request,
      --  and must not disturb the running dwell. Every crosswalk is run, each
      --  pressed alone, for the same reason as .10.
      --
      --  "Leaving State.Ped_Timer (C) unchanged" is observable only after the
      --  whole step, and every step accounts for exactly one sampling period
      --  of every running timer (llr_4_controller.17). BUFFER_INTERVAL and
      --  BUFFER_INTERVAL_LATCHED are both serving states, so that advance
      --  happens whichever of the two the timer is read against: "unchanged"
      --  shows up as the dwell less one sampling period. A latch that reloaded
      --  T_BUFFER, or zeroed the timer, fails here.

      for Latched in States.Crosswalk loop
         State :=
           Reqs_Support.Pedestrian_State
             (Latched, Buffer_Interval, Remaining => Dwell);

         Sensors := Reqs_Support.Quiet;
         Sensors.Buttons (Latched) := Pressed;

         Controller.Step (State, Sensors, Outputs);

         Assert
           (State.Ped (Latched) = Buffer_Interval_Latched,
            "a press observed on "
            & States.Crosswalk'Image (Latched)
            & " during its buffer must latch it to BUFFER_INTERVAL_LATCHED,"
            & " but it is "
            & States.Pedestrian_State'Image (State.Ped (Latched)));

         Assert
           (State.Ped_Timer (Latched) = Dwell - States.T_Sample,
            "the latch must leave the buffer's dwell alone, so"
            & States.Duration_Ms'Image (Dwell)
            & " ms must become"
            & States.Duration_Ms'Image (Dwell - States.T_Sample)
            & " ms across the step, but it is"
            & States.Duration_Ms'Image (State.Ped_Timer (Latched)));

         for Other in States.Crosswalk loop
            if Other /= Latched then
               Assert
                 (State.Ped (Other) = No_Pedestrian_Request,
                  "latching "
                  & States.Crosswalk'Image (Latched)
                  & " must leave "
                  & States.Crosswalk'Image (Other)
                  & " at NO_PEDESTRIAN_REQUEST, but it is "
                  & States.Pedestrian_State'Image (State.Ped (Other)));
            end if;
         end loop;
      end loop;

   end Test_11_Press_Latches_Buffer_Interval;

   ------------------------------------------------------------------------
   --  The service edge (statement 12)
   ------------------------------------------------------------------------

   procedure Test_12_Adjacent_Green_Rise_Serves_Pending (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.12

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  The edge that starts a service: a pending crosswalk gets WALK on the
      --  step where its adjacent through *rises* to GREEN, with T_WALK loaded
      --  as the interval's dwell.
      --
      --  Which through is the adjacent one is read from
      --  Conflicts.Adjacent_Through, the function this statement names -- the
      --  geometry itself is llr_3_conflicts.5's claim, not this one's. Every
      --  crosswalk is run, which discharges the "for a crosswalk C"
      --  quantifier; because the four crosswalks split two-and-two across the
      --  axes, both barrier exits are exercised.
      --
      --  Two cases, because the trigger is a rise and not a level
      --  (llr_4_controller.20 keys it on the through faces GREEN after this
      --  step's advance that were not GREEN before it): the step that carries
      --  the rise serves the crosswalk, and a step in the middle of that same
      --  GREEN does not. Without the second case a level-triggered
      --  implementation would pass, and it would start WALK mid-green -- with
      --  less than T_WALK + T_FDW + T_BUFFER of green left to cover it.
      --
      --  What is asserted is State.Ped (C) and State.Ped_Timer (C) after the
      --  step, not the outputs the step emitted: the claim is about the
      --  resulting state.

      for C in States.Crosswalk loop
         declare
            A : constant States.Approach := Conflicts.Adjacent_Through (C);

            Barrier : constant States.Vehicle_Sequencer_State :=
              Barrier_Before_Green (A);

            Both : constant States.Vehicle_Sequencer_State :=
              Both_Through_After (A);

            Rises : constant Boolean :=
              Reqs_Support.Expected_Faces (Barrier).Through (A) /= Green
              and then Reqs_Support.Expected_Faces (Both).Through (A) = Green;
         begin

            --  The construction's premise rather than this statement's claim,
            --  asserted so a vehicle-sequencer defect cannot read as a
            --  pedestrian one: the rows transcribed in Expected_Faces must
            --  hold A's through RED at the barrier and GREEN in the state the
            --  barrier's exit enters.

            Assert
              (Rises,
               "premise: the exit of "
               & States.Vehicle_Sequencer_State'Image (Barrier)
               & " must raise the through face of "
               & States.Approach'Image (A)
               & " to GREEN");

            --  Case one: the step on which the barrier's dwell elapses, so the
            --  adjacent through rises to GREEN during this very step.

            State :=
              Reqs_Support.Pedestrian_State (C, Pending_Pedestrian_Request);
            State.Vehicle := Barrier;
            State.Veh_Timer := States.T_Sample;

            Controller.Step (State, Reqs_Support.Quiet, Outputs);

            Assert
              (State.Vehicle = Both,
               "premise: the step must leave the sequencer in "
               & States.Vehicle_Sequencer_State'Image (Both)
               & ", but it is in "
               & States.Vehicle_Sequencer_State'Image (State.Vehicle));

            Assert
              (State.Ped (C) = Walk_Interval,
               "with the through face of "
               & States.Approach'Image (A)
               & " rising to GREEN, pending "
               & States.Crosswalk'Image (C)
               & " must enter WALK_INTERVAL, but it is in "
               & States.Pedestrian_State'Image (State.Ped (C)));

            Assert
              (State.Ped_Timer (C) = States.T_Walk,
               States.Crosswalk'Image (C)
               & ": entering WALK_INTERVAL must load T_WALK ("
               & States.Duration_Ms'Image (States.T_Walk)
               & " ms) as its dwell, but the dwell is"
               & States.Duration_Ms'Image (State.Ped_Timer (C)));

            --  Case two: the same GREEN, mid-dwell. Nothing rises, so nothing
            --  is served.

            State :=
              Reqs_Support.Pedestrian_State (C, Pending_Pedestrian_Request);
            State.Vehicle := Both;
            State.Veh_Timer := 2 * States.T_Sample;

            Controller.Step (State, Reqs_Support.Quiet, Outputs);

            Assert
              (State.Ped (C) = Pending_Pedestrian_Request,
               "with the through face of "
               & States.Approach'Image (A)
               & " already GREEN and not rising, pending "
               & States.Crosswalk'Image (C)
               & " must stay in PENDING_PEDESTRIAN_REQUEST, but it is in "
               & States.Pedestrian_State'Image (State.Ped (C)));
         end;
      end loop;

   end Test_12_Adjacent_Green_Rise_Serves_Pending;

   ------------------------------------------------------------------------
   --  Timed transitions (statements 13-16)
   ------------------------------------------------------------------------

   procedure Test_13_Walk_Elapses_To_Change (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.13

      pragma Unreferenced (T);
   begin
      Check_Timed_Exit
        (From   => Walk_Interval,
         To     => Change_Interval,
         Loaded => States.T_FDW);
   end Test_13_Walk_Elapses_To_Change;

   procedure Test_14_Change_Elapses_To_Buffer (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.14

      pragma Unreferenced (T);
   begin
      Check_Timed_Exit
        (From   => Change_Interval,
         To     => Buffer_Interval,
         Loaded => States.T_Buffer);
   end Test_14_Change_Elapses_To_Buffer;

   procedure Test_15_Buffer_Elapses_To_No_Request (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.15

      pragma Unreferenced (T);
   begin

      --  The unlatched buffer's exit ends the service: back to
      --  NO_PEDESTRIAN_REQUEST with the timer stopped at 0, which is what
      --  makes the timer-discipline statement (.17) true of the state it lands
      --  in.

      Check_Timed_Exit
        (From   => Buffer_Interval,
         To     => No_Pedestrian_Request,
         Loaded => 0);
   end Test_15_Buffer_Elapses_To_No_Request;

   procedure Test_16_Latched_Buffer_Elapses_To_Pending (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.16

      pragma Unreferenced (T);
   begin

      --  The one dwell the requirements give as a remainder rather than a
      --  named constant: the latch may fire at any point in the buffer and the
      --  timer runs on (.11), so the dwell here is whatever is left of
      --  T_BUFFER. That makes no difference to the test, because firing is
      --  fixed to the step whose remaining dwell is at most T_SAMPLE
      --  (llr_4_controller.18) -- the two cases are one and two sampling
      --  periods of remainder, both legitimate remainders.

      Check_Timed_Exit
        (From   => Buffer_Interval_Latched,
         To     => Pending_Pedestrian_Request,
         Loaded => 0);
   end Test_16_Latched_Buffer_Elapses_To_Pending;

   ------------------------------------------------------------------------
   --  Timer discipline (statement 17)
   ------------------------------------------------------------------------

   procedure Test_17_Ped_Timer_Runs_While_Serving (T : in out Test) is
      --@covers llr_4_controller_3_pedestrian.17

      pragma Unreferenced (T);

      function Serving (P : States.Pedestrian_State) return Boolean
      is (case P is
            when No_Pedestrian_Request | Pending_Pedestrian_Request => False,
            when Walk_Interval
               | Change_Interval
               | Buffer_Interval
               | Buffer_Interval_Latched => True);
      --  Serving_Pedestrian_State, transcribed from llr_1_states.15's range
      --  WALK_INTERVAL .. BUFFER_INTERVAL_LATCHED as an exhaustive case with
      --  no `others` choice: a new pedestrian state fails the build here until
      --  it is classified, and this routine does not inherit its answer from
      --  the subtype declaration whose own statement is verified elsewhere.
      --  @param P The pedestrian state to classify
      --  @return Whether the requirement counts P as serving

      Dwell : constant States.Duration_Ms := 3 * States.T_Sample;
      --  More than one sampling period, so no timed exit fires and the step's
      --  only effect on the dwell is the advance -- or the absence of one.

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  "Running" has exactly one observable: whether a step moves
      --  State.Ped_Timer (C). llr_4_controller.17 fixes the amount at one
      --  T_SAMPLE per step, so a running dwell must show Dwell - T_SAMPLE
      --  after a step and a stopped one must show Dwell unchanged.
      --
      --  The claim is an "exactly while", so both halves are checked over the
      --  whole six-value state alphabet and all four crosswalks: the four
      --  serving states must run, the two others must not.
      --
      --  The two non-serving states are given a non-zero dwell precisely
      --  because "not running" is only observable on a timer that has
      --  something to lose. In reachable operation their dwell is 0 (.15, .16
      --  stop it there), and a step that decremented 0 could not be told from
      --  one that left it alone.

      for C in States.Crosswalk loop
         for P in States.Pedestrian_State loop
            State :=
              Reqs_Support.Pedestrian_State (C, P, Remaining => Dwell);

            Controller.Step (State, Reqs_Support.Quiet, Outputs);

            if Serving (P) then
               Assert
                 (State.Ped_Timer (C) = Dwell - States.T_Sample,
                  States.Crosswalk'Image (C)
                  & " in "
                  & States.Pedestrian_State'Image (P)
                  & ": the dwell must be running, so"
                  & States.Duration_Ms'Image (Dwell)
                  & " ms must become"
                  & States.Duration_Ms'Image (Dwell - States.T_Sample)
                  & " ms across the step, but it is"
                  & States.Duration_Ms'Image (State.Ped_Timer (C)));
            else
               Assert
                 (State.Ped_Timer (C) = Dwell,
                  States.Crosswalk'Image (C)
                  & " in "
                  & States.Pedestrian_State'Image (P)
                  & ": the dwell must not be running, so"
                  & States.Duration_Ms'Image (Dwell)
                  & " ms must be unchanged across the step, but it is"
                  & States.Duration_Ms'Image (State.Ped_Timer (C)));
            end if;
         end loop;
      end loop;

   end Test_17_Ped_Timer_Runs_While_Serving;

end Llr_4_Controller_3_Pedestrian_Tests;
