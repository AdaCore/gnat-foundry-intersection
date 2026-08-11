--  Requirements-based tests for
--  requirements/llr/llr_4_controller_3_pedestrian.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Statements 1-5 are the pedestrian head's Moore output table and 6-9 the
--  request indicator's. Their expected values live together in
--  Reqs_Support.Expected_Ped -- one row per pedestrian state, no `others`
--  choice -- while each column of a row is *asserted* by the routine of the
--  statement that gives it, so a wrong row fails one requirement rather than
--  nine. Two statements speak for more than one state: .5 for both buffer
--  states and .8 for the three unlatched serving states. Those routines assert
--  every state their statement names, so no row is left unasserted.
--
--  Statements 10-17 are the machine's edges -- arming, buffer latch, service,
--  the four timed exits -- and its timer discipline, all observed through
--  Controller.Step.

with AUnit.Test_Fixtures;

package Llr_4_Controller_3_Pedestrian_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  ---- Moore outputs: the pedestrian head (statements 1-5) ----
   procedure Test_01_No_Request_Head_Is_Dont_Walk (T : in out Test);
   procedure Test_02_Pending_Head_Is_Dont_Walk (T : in out Test);
   procedure Test_03_Walk_Interval_Head_Is_Walk (T : in out Test);
   procedure Test_04_Change_Head_Is_Flash_Dont_Walk (T : in out Test);
   procedure Test_05_Buffer_Heads_Are_Dont_Walk (T : in out Test);

   --  ---- Moore outputs: the request indicator (statements 6-9) ----
   procedure Test_06_No_Request_Indicator_Is_No_Request (T : in out Test);
   procedure Test_07_Pending_Indicator_Is_Request_Pending (T : in out Test);
   procedure Test_08_Serving_Indicators_Are_No_Request (T : in out Test);
   procedure Test_09_Latched_Indicator_Is_Request_Pending (T : in out Test);

   --  ---- Input arming (statements 10-11) ----
   procedure Test_10_Press_Arms_Idle_Crosswalk (T : in out Test);
   procedure Test_11_Press_Latches_Buffer_Interval (T : in out Test);

   --  ---- The service edge (statement 12) ----
   procedure Test_12_Adjacent_Green_Rise_Serves_Pending (T : in out Test);

   --  ---- Timed transitions (statements 13-16) ----
   procedure Test_13_Walk_Elapses_To_Change (T : in out Test);
   procedure Test_14_Change_Elapses_To_Buffer (T : in out Test);
   procedure Test_15_Buffer_Elapses_To_No_Request (T : in out Test);
   procedure Test_16_Latched_Buffer_Elapses_To_Pending (T : in out Test);

   --  ---- Timer discipline (statement 17) ----
   procedure Test_17_Ped_Timer_Runs_While_Serving (T : in out Test);

end Llr_4_Controller_3_Pedestrian_Tests;
