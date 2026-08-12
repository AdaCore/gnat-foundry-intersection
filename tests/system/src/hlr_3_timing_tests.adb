with AUnit.Assertions; use AUnit.Assertions;

with States;
with System_Support.Demand;
with System_Support.Timeline;

package body Hlr_3_Timing_Tests is

   use type States.Duration_Ms;

   package Demand renames System_Support.Demand;
   package Timeline renames System_Support.Timeline;

   Cycle : constant States.Duration_Ms :=
     2 * States.T_Axis + 2 * States.T_Barrier;
   --  Both axis slots and the barrier that closes the second.

   type Demand_Case is (No_Lefts, All_Lefts);
   --  The two left-turn demand patterns a cycle is observed under: no
   --  protected left runs, or both run on each axis.

   procedure Observe_Cycle (Pattern : Demand_Case);
   --  Observe a full cycle under Pattern, with no button pressed: a frame then
   --  changes only when a vehicle face does.
   --  @param Pattern Which left-turn detectors are held

   procedure Observe_Cycle (Pattern : Demand_Case) is
   begin
      Demand.Clear;

      if Pattern = All_Lefts then
         for A in States.Approach loop
            Demand.Left_Turn (A, From => 0);
         end loop;
      end if;

      Timeline.Observe (For_Ms => Cycle, Demand => Demand.Snapshot'Access);

      Assert
        (not Timeline.Truncated,
         "the observation dropped frames, so the timeline is a prefix");
   end Observe_Cycle;

   procedure Test_Yellow_Holds_For_T_Yellow (T : in out Test) is
      --@observes hlr_3_timing.4

      pragma Unreferenced (T);

      Expected : constant array (Demand_Case) of Natural :=
        (No_Lefts => 2, All_Lefts => 6);
      --  One both-through drop per axis when no left runs
      --  (hlr_5_vehicle.10/.33); a lead, a through drop and a lag per axis
      --  when both do (.3/.6/.9 and .26/.29/.32).
   begin
      for Pattern in Demand_Case loop
         Observe_Cycle (Pattern);

         declare
            Seen : Natural := 0;
         begin
            for N in 1 .. Timeline.Count loop
               declare
                  Yellow : constant Timeline.Interval := Timeline.Nth (N);
               begin
                  if System_Support.Any_Yellow (Yellow.Frame) then
                     Seen := Seen + 1;

                     Assert
                       (Yellow.Closed and then Yellow.Span = States.T_Yellow,
                        "the yellow frame published at"
                        & States.Duration_Ms'Image (Yellow.Opened_At)
                        & " ms under "
                        & Demand_Case'Image (Pattern)
                        & " must be displayed for T_YELLOW ="
                        & States.Duration_Ms'Image (States.T_Yellow)
                        & " ms, but was displayed for"
                        & States.Duration_Ms'Image (Yellow.Span)
                        & " ms");
                  end if;
               end;
            end loop;

            Assert
              (Seen = Expected (Pattern),
               "a cycle under "
               & Demand_Case'Image (Pattern)
               & " must publish"
               & Integer'Image (Expected (Pattern))
               & " yellow frame(s), but published"
               & Integer'Image (Seen));
         end;
      end loop;
   end Test_Yellow_Holds_For_T_Yellow;

   procedure Test_Red_Clearance_Holds_For_T_Redclear (T : in out Test) is
      --@observes hlr_3_timing.5

      pragma Unreferenced (T);

      Expected : constant array (Demand_Case) of Natural :=
        (No_Lefts => 0, All_Lefts => 4);
      --  The lead and the through drop of each axis (hlr_5_vehicle.4/.7 and
      --  .27/.30); the yellows that close an axis are followed by the barrier.
   begin
      for Pattern in Demand_Case loop
         Observe_Cycle (Pattern);

         declare
            Seen : Natural := 0;
         begin
            for N in 2 .. Timeline.Count loop
               declare
                  Clear : constant Timeline.Interval := Timeline.Nth (N);
               begin
                  if System_Support.Any_Yellow (Timeline.Nth (N - 1).Frame)
                    and then not System_Support.Any_Yellow (Clear.Frame)
                    and then not System_Support.All_Vehicle_Red (Clear.Frame)
                  then
                     Seen := Seen + 1;

                     Assert
                       (Clear.Closed
                        and then Clear.Span = States.T_Redclear,
                        "the red-clearance frame published at"
                        & States.Duration_Ms'Image (Clear.Opened_At)
                        & " ms under "
                        & Demand_Case'Image (Pattern)
                        & " must be displayed for T_REDCLEAR ="
                        & States.Duration_Ms'Image (States.T_Redclear)
                        & " ms, but was displayed for"
                        & States.Duration_Ms'Image (Clear.Span)
                        & " ms");
                  end if;
               end;
            end loop;

            Assert
              (Seen = Expected (Pattern),
               "a cycle under "
               & Demand_Case'Image (Pattern)
               & " must publish"
               & Integer'Image (Expected (Pattern))
               & " red-clearance frame(s), but published"
               & Integer'Image (Seen));
         end;
      end loop;
   end Test_Red_Clearance_Holds_For_T_Redclear;

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

   procedure Test_Axis_Change_Barriers_Hold_For_T_Barrier (T : in out Test) is
      --@observes hlr_3_timing.6 hlr_5_vehicle.11 hlr_5_vehicle.34

      pragma Unreferenced (T);

      Expected : constant Natural := 3;
      --  The power-on barrier, then one per axis change (hlr_5_vehicle.11
      --  and .34).
   begin
      for Pattern in Demand_Case loop
         Observe_Cycle (Pattern);

         declare
            Seen : Natural := 0;
         begin
            for N in 1 .. Timeline.Count loop
               declare
                  Barrier : constant Timeline.Interval := Timeline.Nth (N);
               begin
                  if System_Support.All_Vehicle_Red (Barrier.Frame) then
                     Seen := Seen + 1;

                     Assert
                       (Barrier.Closed
                        and then Barrier.Span = States.T_Barrier,
                        "the all-red frame published at"
                        & States.Duration_Ms'Image (Barrier.Opened_At)
                        & " ms under "
                        & Demand_Case'Image (Pattern)
                        & " must be displayed for T_BARRIER ="
                        & States.Duration_Ms'Image (States.T_Barrier)
                        & " ms, but was displayed for"
                        & States.Duration_Ms'Image (Barrier.Span)
                        & " ms");
                  end if;
               end;
            end loop;

            Assert
              (Seen = Expected,
               "a cycle under "
               & Demand_Case'Image (Pattern)
               & " must publish"
               & Integer'Image (Expected)
               & " all-red frames, but published"
               & Integer'Image (Seen));
         end;
      end loop;
   end Test_Axis_Change_Barriers_Hold_For_T_Barrier;

end Hlr_3_Timing_Tests;
