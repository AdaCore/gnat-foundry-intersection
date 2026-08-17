--  System-level tests for the intervals of
--  requirements/hlr/hlr_3_timing.yaml.
--
--  One routine per observed interval. Each is a property of the
--  published-frame timeline (System_Support.Timeline): the frame the
--  requirement names, held for the duration the requirement gives. No routine
--  here reads controller state -- the subject is what the display was driven
--  to, which is what hlr_4_signals makes the controller's output boundary.
--
--  T_BUFFER (hlr_3_timing.3) has no routine: BUFFER_INTERVAL and
--  NO_PEDESTRIAN_REQUEST publish the same frame, so the buffer's end is not
--  observable here. It shows only in the margin of statement 10. Statements 9
--  and 12 relate constants, which states.ads checks at compile time.

with AUnit.Test_Fixtures;

package Hlr_3_Timing_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Walk_Holds_For_T_Walk (T : in out Test);

   procedure Test_Flash_Dont_Walk_Holds_For_T_FDW (T : in out Test);

   procedure Test_Yellow_Holds_For_T_Yellow (T : in out Test);

   procedure Test_Red_Clearance_Holds_For_T_Redclear (T : in out Test);

   procedure Test_Power_On_Barrier_Holds_For_T_Barrier (T : in out Test);

   procedure Test_Axis_Change_Barriers_Hold_For_T_Barrier (T : in out Test);

   procedure Test_Axis_Slot_Is_Demand_Independent (T : in out Test);

   procedure Test_Crosswalk_Conflicts_Held_Red_For_The_Margin
     (T : in out Test);

   procedure Test_Request_Acknowledged_Within_T_Ack (T : in out Test);

end Hlr_3_Timing_Tests;
