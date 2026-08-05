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

end Llr_4_Controller_2_Left_Demand_Tests;
