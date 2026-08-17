with AUnit.Assertions; use AUnit.Assertions;

with States;
with System_Support.Demand;
with System_Support.Timeline;

package body Timeline_Tests is

   use type States.Duration_Ms;

   package Demand renames System_Support.Demand;
   package Timeline renames System_Support.Timeline;

   Cycle : States.Duration_Ms renames System_Support.Cycle;

   procedure Test_Full_Cycle_Fits_The_Timeline (T : in out Test) is
      --@observes none: the observer's capacity, not a requirement

      pragma Unreferenced (T);

      Quiet_Frames : Natural;
   begin
      Demand.Clear;
      Timeline.Observe (For_Ms => Cycle, Demand => Demand.Snapshot'Access);
      Quiet_Frames := Timeline.Count;

      --  Every detector and every button held: both protected lefts run on
      --  each axis, and each crosswalk is served and re-latched.

      for A in States.Approach loop
         Demand.Left_Turn (A, From => 0);
      end loop;

      for C in States.Crosswalk loop
         Demand.Press (C, From => 0);
      end loop;

      Timeline.Observe (For_Ms => Cycle, Demand => Demand.Snapshot'Access);

      Assert
        (Timeline.Observed_Ms >= Cycle,
         "the observation spanned"
         & States.Duration_Ms'Image (Timeline.Observed_Ms)
         & " ms, short of the"
         & States.Duration_Ms'Image (Cycle)
         & " ms cycle it must cover");

      Assert
        (Timeline.Count > Quiet_Frames,
         "the scripted demand must reach the program, but the cycle published"
         & Integer'Image (Timeline.Count)
         & " frames against the quiet cycle's"
         & Integer'Image (Quiet_Frames));

      Assert
        (not Timeline.Truncated,
         "a full cycle under full demand published more frames than the"
         & Integer'Image (Timeline.Max_Intervals)
         & " the timeline holds");

   end Test_Full_Cycle_Fits_The_Timeline;

end Timeline_Tests;
