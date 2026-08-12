with AUnit.Assertions; use AUnit.Assertions;

with States;
with System_Support.Demand;
with System_Support.Timeline;

package body Hlr_3_Timing_Tests is

   use type States.Duration_Ms;
   use type States.Pedestrian_Head;

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

   procedure Observe_Pedestrian_Service (Pattern : Demand_Case);
   --  Press every button for one read at power-on and observe a full cycle
   --  under Pattern: each crosswalk is then served once, when its adjacent
   --  through greens (hlr_6_pedestrian.8).
   --  @param Pattern Which left-turn detectors are held

   procedure Check_Head_Interval
     (Head     : States.Pedestrian_Head;
      Held_For : States.Duration_Ms;
      Named    : String;
      Pattern  : Demand_Case);
   --  Assert every crosswalk displayed Head over exactly one run of frames in
   --  the last observation, for Held_For in total. A vehicle change during the
   --  interval opens a frame of its own, so the run is what carries it.
   --  @param Head The head value bounding the interval
   --  @param Held_For The duration the requirement gives it
   --  @param Named How the requirement names that duration
   --  @param Pattern The pattern observed, for the message

   procedure Observe_Pedestrian_Service (Pattern : Demand_Case) is
   begin
      Demand.Clear;

      if Pattern = All_Lefts then
         for A in States.Approach loop
            Demand.Left_Turn (A, From => 0);
         end loop;
      end if;

      for C in States.Crosswalk loop
         Demand.Press (C, From => 0, Before => States.T_Sample + 1);
      end loop;

      Timeline.Observe (For_Ms => Cycle, Demand => Demand.Snapshot'Access);

      Assert
        (not Timeline.Truncated,
         "the observation dropped frames, so the timeline is a prefix");
   end Observe_Pedestrian_Service;

   procedure Check_Head_Interval
     (Head     : States.Pedestrian_Head;
      Held_For : States.Duration_Ms;
      Named    : String;
      Pattern  : Demand_Case) is
   begin
      for C in States.Crosswalk loop
         declare
            Runs : Natural := 0;
            Span : States.Duration_Ms := 0;
         begin
            for N in 1 .. Timeline.Count loop
               declare
                  Served : constant Timeline.Interval := Timeline.Nth (N);

                  Shown : constant Boolean :=
                    Served.Frame.Heads (C) = Head;
               begin
                  if Shown
                    and then (N = 1
                              or else Timeline.Nth (N - 1).Frame.Heads (C)
                                      /= Head)
                  then
                     Runs := Runs + 1;
                     Span := 0;
                  end if;

                  if Shown then
                     Assert
                       (Served.Closed,
                        States.Crosswalk'Image (C)
                        & "'s "
                        & States.Pedestrian_Head'Image (Head)
                        & " frame published at"
                        & States.Duration_Ms'Image (Served.Opened_At)
                        & " ms was never replaced, so the interval is only a"
                        & " lower bound");

                     Span := Span + Served.Span;
                  end if;
               end;
            end loop;

            Assert
              (Runs = 1,
               States.Crosswalk'Image (C)
               & " must be served once in a cycle, but displayed "
               & States.Pedestrian_Head'Image (Head)
               & " over"
               & Integer'Image (Runs)
               & " run(s) under "
               & Demand_Case'Image (Pattern));

            Assert
              (Span = Held_For,
               States.Crosswalk'Image (C)
               & " must display "
               & States.Pedestrian_Head'Image (Head)
               & " for "
               & Named
               & " ="
               & States.Duration_Ms'Image (Held_For)
               & " ms, but displayed it for"
               & States.Duration_Ms'Image (Span)
               & " ms under "
               & Demand_Case'Image (Pattern));
         end;
      end loop;
   end Check_Head_Interval;

   procedure Test_Walk_Holds_For_T_Walk (T : in out Test) is
      --@observes hlr_3_timing.1

      pragma Unreferenced (T);

      T_Walk : constant States.Duration_Ms := 7_000;
      --  hlr_3_timing.1: a WALK interval of 7 seconds.
   begin
      for Pattern in Demand_Case loop
         Observe_Pedestrian_Service (Pattern);
         Check_Head_Interval (States.Walk, T_Walk, "T_WALK", Pattern);
      end loop;
   end Test_Walk_Holds_For_T_Walk;

   procedure Test_Flash_Dont_Walk_Holds_For_T_FDW (T : in out Test) is
      --@observes hlr_3_timing.2

      pragma Unreferenced (T);

      T_FDW : constant States.Duration_Ms := 7_000;
      --  hlr_3_timing.2: a pedestrian change interval of 7 seconds.
   begin
      for Pattern in Demand_Case loop
         Observe_Pedestrian_Service (Pattern);
         Check_Head_Interval
           (States.Flash_Dont_Walk, T_FDW, "T_FDW", Pattern);
      end loop;
   end Test_Flash_Dont_Walk_Holds_For_T_FDW;

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

   procedure Test_Request_Acknowledged_Within_T_Ack (T : in out Test) is
      --@observes hlr_3_timing.13

      pragma Unreferenced (T);

      T_Ack : constant States.Duration_Ms := 200;
      --  hlr_3_timing.13: an acknowledgment bound of 0.2 seconds.

      procedure Check_Ack
        (C : States.Crosswalk; After : States.Duration_Ms; Context : String);
      --  Press C's button just past the read at After, and assert the frame
      --  taking the request reaches the display within T_ACK of the press.
      --  @param C The crosswalk pressed
      --  @param After The last read the press misses
      --  @param Context What the intersection is doing

      procedure Check_Ack
        (C : States.Crosswalk; After : States.Duration_Ms; Context : String)
      is
         Taken : Natural := 0;
      begin
         Demand.Clear;
         Demand.Press (C, From => After + 1);

         Timeline.Observe (For_Ms => Cycle, Demand => Demand.Snapshot'Access);

         Assert
           (not Timeline.Truncated,
            "the observation dropped frames, so the timeline is a prefix");

         for N in 1 .. Timeline.Count loop
            if System_Support.Acknowledged (Timeline.Nth (N).Frame, C) then

               Assert
                 (Timeline.Nth (N).Opened_At > After,
                  "the frame published at"
                  & States.Duration_Ms'Image (Timeline.Nth (N).Opened_At)
                  & " ms acknowledges a request at "
                  & States.Crosswalk'Image (C)
                  & " that the press "
                  & Context
                  & " had not yet made");

               Taken := N;
               exit;
            end if;
         end loop;

         Assert
           (Taken > 0,
            "the press "
            & Context
            & " was never acknowledged at "
            & States.Crosswalk'Image (C));

         Assert
           (Timeline.Nth (Taken).Opened_At <= After + T_Ack,
            "the press "
            & Context
            & " must be acknowledged at "
            & States.Crosswalk'Image (C)
            & " within T_ACK ="
            & States.Duration_Ms'Image (T_Ack)
            & " ms of"
            & States.Duration_Ms'Image (After)
            & " ms, but the frame taking it was published at"
            & States.Duration_Ms'Image (Timeline.Nth (Taken).Opened_At)
            & " ms");
      end Check_Ack;

   begin
      Check_Ack
        (C       => States.East_Side,
         After   => 1_000,
         Context => "while the barrier holds all-red");

      Check_Ack
        (C       => States.East_Side,
         After   => States.T_Barrier - States.T_Sample,
         Context => "on the last read of the barrier");

      Check_Ack
        (C       => States.North_Side,
         After   => 10_000,
         Context => "mid-service of the other axis");
   end Test_Request_Acknowledged_Within_T_Ack;

end Hlr_3_Timing_Tests;
