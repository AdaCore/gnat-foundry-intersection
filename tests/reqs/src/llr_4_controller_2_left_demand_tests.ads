--  Requirements-based tests for
--  requirements/llr/llr_4_controller_2_left_demand.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.

with AUnit.Test_Fixtures;

package Llr_4_Controller_2_Left_Demand_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Detector_Arms_Idle_Approach (T : in out Test);

end Llr_4_Controller_2_Left_Demand_Tests;
