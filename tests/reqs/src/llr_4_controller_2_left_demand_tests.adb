with AUnit.Assertions; use AUnit.Assertions;

with Controller;
with Reqs_Support;
with States;

package body Llr_4_Controller_2_Left_Demand_Tests is

   use all type States.Approach;
   use all type States.Left_Demand_State;
   use all type States.Left_Turn_Detector;
   use all type States.Vehicle_Sequencer_State;
   use type States.Duration_Ms;

   procedure Test_01_Detector_Arms_Idle_Approach (T : in out Test) is
      --@covers llr_4_controller_2_left_demand.1

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Sensors : States.Sensors_State;
      Outputs : States.Display_State;
   begin

      --  The requirement is a per-approach guarded assignment: while an
      --  approach's demand is NO_LEFT_DEMAND, observing VEHICLE_PRESENT on
      --  that approach's detector arms it to LEFT_DEMAND_PENDING.
      --
      --  Approach is a four-value enumeration, so the "for an approach A"
      --  quantifier is discharged by running every approach rather than
      --  picking one -- and each is run alone, so the test also shows the
      --  arming does not spill onto the other three.
      --
      --  The sequencer is parked mid-dwell in the barrier state so no timed
      --  transition fires during the step: what is observed is the arming and
      --  nothing else.

      for Armed in States.Approach loop
         State :=
           Reqs_Support.Vehicle_State
             (EW_Barrier_Allred, Remaining => 2 * States.T_Sample);

         Sensors := Reqs_Support.Quiet;
         Sensors.Left_Turns (Armed) := Vehicle_Present;

         Controller.Step (State, Sensors, Outputs);

         Assert
           (State.Left (Armed) = Left_Demand_Pending,
            "a left-turn vehicle observed on "
            & States.Approach'Image (Armed)
            & " must arm that approach to LEFT_DEMAND_PENDING, but it is "
            & States.Left_Demand_State'Image (State.Left (Armed)));

         for Other in States.Approach loop
            if Other /= Armed then
               Assert
                 (State.Left (Other) = No_Left_Demand,
                  "arming "
                  & States.Approach'Image (Armed)
                  & " must leave "
                  & States.Approach'Image (Other)
                  & " at NO_LEFT_DEMAND, but it is "
                  & States.Left_Demand_State'Image (State.Left (Other)));
            end if;
         end loop;
      end loop;

   end Test_01_Detector_Arms_Idle_Approach;

   procedure Test_02_Pending_Approach_Ignores_Its_Detector (T : in out Test) is
      --@covers llr_4_controller_2_left_demand.2

      pragma Unreferenced (T);

      State   : Controller.Controller_State;
      Sensors : States.Sensors_State;
      Outputs : States.Display_State;
   begin

      --  The requirement is an idempotence claim: once an approach is
      --  LEFT_DEMAND_PENDING, no observation of its detector moves it. "Any
      --  observation" is a two-value enumeration, so both values are run --
      --  VEHICLE_PRESENT for the vehicle still sitting on the loop, which must
      --  not re-arm anything, and NO_VEHICLE for the vehicle that has moved
      --  off it, which must not disarm the latched demand. Sampling one value
      --  would leave half the statement unverified, and it is the half a
      --  plausible mis-implementation gets wrong: a detector read that is not
      --  guarded by the machine's own state clears on NO_VEHICLE.
      --
      --  Crossed with all four approaches: the statement is per-approach.
      --
      --  The sequencer is parked mid-dwell in the barrier state, so no timed
      --  transition fires and no through face rises to GREEN during the step:
      --  the clear edge of statement .3 cannot be what holds or moves the
      --  demand here, and what is observed is the detector observation alone.

      for Pending in States.Approach loop
         for Reading in States.Left_Turn_Detector loop
            State :=
              Reqs_Support.Vehicle_State
                (EW_Barrier_Allred, Remaining => 2 * States.T_Sample);
            State.Left (Pending) := Left_Demand_Pending;

            Sensors := Reqs_Support.Quiet;
            Sensors.Left_Turns (Pending) := Reading;

            Controller.Step (State, Sensors, Outputs);

            Assert
              (State.Left (Pending) = Left_Demand_Pending,
               "a pending demand on "
               & States.Approach'Image (Pending)
               & " must survive a detector reading of "
               & States.Left_Turn_Detector'Image (Reading)
               & ", but it is "
               & States.Left_Demand_State'Image (State.Left (Pending)));
         end loop;
      end loop;

   end Test_02_Pending_Approach_Ignores_Its_Detector;

   procedure Test_03_Conflicting_Through_Green_Edge_Clears_Pending_Demand
     (T : in out Test)
   is
      --@covers llr_4_controller_2_left_demand.3

      pragma Unreferenced (T);

      type Green_Edge is record
         Before : States.Vehicle_Sequencer_State;
         After  : States.Vehicle_Sequencer_State;
         Rising : States.Approach;
      end record;
      --  Rising is the approach whose through face this step drives to GREEN:
      --  Next_Conflicting_Through of the indexing approach, transcribed from
      --  llr_3_conflicts.4 rather than called, so this routine depends on no
      --  code but Controller.Step.

      type Green_Edge_Table is array (States.Approach) of Green_Edge;

      --  One step per approach, indexed by the approach whose demand is under
      --  test. Each is derived from the sequencer's own requirements -- the
      --  Moore output rows and transitions of llr_4_controller_1_vehicle, and
      --  the map of llr_3_conflicts.4 -- and from nothing in Controller.Step.
      --
      --  For approach A the step must drive the through face of
      --  Next_Conflicting_Through (A) from not-GREEN to GREEN, which is the
      --  edge llr_4_controller.19 keys this clear on:
      --
      --  NORTH is cleared by the SOUTH through. N_LEAD_CLEAR shows the NORTH
      --    through GREEN and every other face RED (.5); when its T_REDCLEAR
      --    dwell elapses the sequencer enters NS_BOTH_THROUGH (.29), which
      --    shows the NORTH and SOUTH throughs GREEN (.6). SOUTH rises.
      --  SOUTH is cleared by the EAST through. NS_BARRIER_ALLRED shows every
      --    face RED (.13); with EAST pending, its T_BARRIER dwell elapses into
      --    E_LEAD (.38), which shows the EAST through GREEN (.14). EAST rises.
      --  EAST is cleared by the WEST through. E_LEAD_CLEAR shows the EAST
      --    through GREEN and every other face RED (.16); when its T_REDCLEAR
      --    dwell elapses the sequencer enters EW_BOTH_THROUGH (.42), which
      --    shows the EAST and WEST throughs GREEN (.17). WEST rises.
      --  WEST is cleared by the NORTH through. EW_BARRIER_ALLRED shows every
      --    face RED (.24); with NORTH pending, its T_BARRIER dwell elapses
      --    into N_LEAD (.25), which shows the NORTH through GREEN (.3). NORTH
      --    rises.
      --
      --  Exactly one through face rises in each of the four steps, so exactly
      --  one approach's demand may clear -- which is why every approach is
      --  armed and all four are asserted after the step. In the NORTH and EAST
      --  cases the through that is GREEN on both sides of the step belongs to
      --  another approach's clear (the NORTH through is WEST's, the EAST
      --  through is SOUTH's), so those two steps also show that the clear keys
      --  on the rising edge and not on the level.
      Edge : constant Green_Edge_Table :=
        (North =>
           (Before => N_Lead_Clear,
            After  => NS_Both_Through,
            Rising => South),
         South =>
           (Before => NS_Barrier_Allred,
            After  => E_Lead,
            Rising => East),
         East  =>
           (Before => E_Lead_Clear,
            After  => EW_Both_Through,
            Rising => West),
         West  =>
           (Before => EW_Barrier_Allred,
            After  => N_Lead,
            Rising => North));

      State   : Controller.Controller_State;
      Outputs : States.Display_State;
   begin

      --  A transition fires on the step whose remaining dwell is at most
      --  T_SAMPLE (llr_4_controller.18), so one sampling period of dwell left
      --  is the step on whose boundary the sequencer moves.

      for Cleared in States.Approach loop
         State :=
           Reqs_Support.Vehicle_State
             (Edge (Cleared).Before, Remaining => States.T_Sample);
         State.Left := (others => Left_Demand_Pending);

         Controller.Step (State, Reqs_Support.Quiet, Outputs);

         --  The construction, not the requirement: if the sequencer did not
         --  land where the transitions above say it does, the intended GREEN
         --  edge never happened and the demand assertions below would pass or
         --  fail for the wrong reason.

         Assert
           (State.Vehicle = Edge (Cleared).After,
            "this case needs the step out of "
            & States.Vehicle_Sequencer_State'Image (Edge (Cleared).Before)
            & " to reach "
            & States.Vehicle_Sequencer_State'Image (Edge (Cleared).After)
            & " so the through face of the next conflicting approach rises to"
            & " GREEN, but the sequencer is in "
            & States.Vehicle_Sequencer_State'Image (State.Vehicle));

         --  The resulting state is what the requirement constrains, so it is
         --  what is asserted -- not this step's Outputs, which the code emits
         --  before advancing (the known llr_4_controller.16 divergence).

         Assert
           (State.Left (Cleared) = No_Left_Demand,
            "the "
            & States.Approach'Image (Edge (Cleared).Rising)
            & " through rose to GREEN in this step, so the pending demand on "
            & States.Approach'Image (Cleared)
            & " must be cleared to NO_LEFT_DEMAND, but it is "
            & States.Left_Demand_State'Image (State.Left (Cleared)));

         for Other in States.Approach loop
            if Other /= Cleared then
               Assert
                 (State.Left (Other) = Left_Demand_Pending,
                  "this step raises only the "
                  & States.Approach'Image (Edge (Cleared).Rising)
                  & " through, which clears "
                  & States.Approach'Image (Cleared)
                  & ", so the pending demand on "
                  & States.Approach'Image (Other)
                  & " must stay LEFT_DEMAND_PENDING, but it is "
                  & States.Left_Demand_State'Image (State.Left (Other)));
            end if;
         end loop;
      end loop;

   end Test_03_Conflicting_Through_Green_Edge_Clears_Pending_Demand;

end Llr_4_Controller_2_Left_Demand_Tests;
