--  Requirements-based tests for
--  requirements/llr/llr_4_controller_2_left_demand.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  All three statements of that file are covered here: the level-triggered arm
--  (.1), its idempotence once armed (.2), and the clear on the rising GREEN of
--  the approach's next conflicting through (.3). Approach is a four-value
--  enumeration and Left_Turn_Detector a two-value one, so each routine runs
--  every approach rather than picking one, and each keeps the other three
--  approaches in view so a per-approach edge that spilled across the array
--  fails as well.

with AUnit.Test_Fixtures;

package Llr_4_Controller_2_Left_Demand_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Detector_Arms_Idle_Approach (T : in out Test);

   procedure Test_02_Pending_Approach_Ignores_Its_Detector (T : in out Test);

   procedure Test_03_Conflicting_Through_Green_Edge_Clears_Pending_Demand
     (T : in out Test);

end Llr_4_Controller_2_Left_Demand_Tests;
