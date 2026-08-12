--  System-level tests for the intervals of
--  requirements/hlr/hlr_3_timing.yaml.
--
--  One routine per observed interval. Each is a property of the
--  published-frame timeline (System_Support.Timeline): the frame the
--  requirement names, held for the duration the requirement gives. No routine
--  here reads controller state -- the subject is what the display was driven
--  to, which is what hlr_4_signals makes the controller's output boundary.

with AUnit.Test_Fixtures;

package Hlr_3_Timing_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Yellow_Holds_For_T_Yellow (T : in out Test);

   procedure Test_Red_Clearance_Holds_For_T_Redclear (T : in out Test);

   procedure Test_Power_On_Barrier_Holds_For_T_Barrier (T : in out Test);

   procedure Test_Axis_Change_Barriers_Hold_For_T_Barrier (T : in out Test);

end Hlr_3_Timing_Tests;
