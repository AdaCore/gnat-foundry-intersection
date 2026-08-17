with AUnit.Assertions; use AUnit.Assertions;

with States;
with System_Support.Timeline;

package body Hlr_3_Timing_Tests is

   use type States.Duration_Ms;

   package Timeline renames System_Support.Timeline;

   procedure Test_Power_On_Barrier_Holds_For_T_Barrier (T : in out Test) is
      --@observes hlr_3_timing.6 hlr_5_vehicle.34 hlr_5_vehicle.47

      pragma Unreferenced (T);

      Boot : Timeline.Interval;
   begin

      --  hlr_5_vehicle.47 puts the controller in EW_BARRIER_ALLRED at
      --  power-on, .34 holds every vehicle face RED while it is there, and .13
      --  leaves for NS service when T_BARRIER has elapsed. Composed, they give
      --  the first published frame: all-red, from t = 0, for T_BARRIER.
      --
      --  Observed past the barrier so a successor closes the frame rather than
      --  the end of the observation, which would make the span a lower bound.

      Timeline.Observe (For_Ms => 2 * States.T_Barrier);

      Assert
        (not Timeline.Truncated,
         "the observation dropped frames, so the timeline is a prefix");

      Assert
        (Timeline.Count >= 2,
         "the barrier must be followed by a second frame inside"
         & States.Duration_Ms'Image (2 * States.T_Barrier)
         & " ms, but the display published"
         & Integer'Image (Timeline.Count)
         & " frame(s)");

      Boot := Timeline.Nth (1);

      Assert
        (System_Support.All_Vehicle_Red (Boot.Frame),
         "the power-on frame must hold every vehicle movement at RED, but"
         & " released " & System_Support.Released_Movements (Boot.Frame));

      Assert
        (Boot.Opened_At = 0,
         "the power-on frame must reach the display before any logical time"
         & " has passed, but was first published at"
         & States.Duration_Ms'Image (Boot.Opened_At)
         & " ms");

      Assert
        (Boot.Closed,
         "the power-on frame was never replaced, so its span is only a lower"
         & " bound");

      Assert
        (Boot.Span = States.T_Barrier,
         "the power-on all-red must be displayed for T_BARRIER ="
         & States.Duration_Ms'Image (States.T_Barrier)
         & " ms, but was displayed for"
         & States.Duration_Ms'Image (Boot.Span)
         & " ms");

   end Test_Power_On_Barrier_Holds_For_T_Barrier;

end Hlr_3_Timing_Tests;
