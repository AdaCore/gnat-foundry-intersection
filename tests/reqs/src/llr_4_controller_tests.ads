--  Requirements-based tests for requirements/llr/llr_4_controller.yaml -- the
--  controller frame: the power-on state, the Moore output projection, and the
--  fixed-cadence step engine.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Three statements of the file have no routine here:
--
--    .1  the composite record's fields -- a structural claim, classified
--        compiler check / analysis, not test.
--    .12 Project_Outputs returns a Safe_Faces display -- discharged by the
--        postcondition at src/core/controller.ads:93 (proof).
--    .21 Step's outputs are Safe_Faces -- discharged by the postcondition at
--        src/core/controller.ads:105 (proof).

with AUnit.Test_Fixtures;

package Llr_4_Controller_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  ---- the power-on state (Initialize) ----
   procedure Test_02_Initialize_Sets_Normal_Operation (T : in out Test);
   procedure Test_03_Initialize_Sets_Barrier_And_Dwell (T : in out Test);
   procedure Test_04_Initialize_Clears_Every_Left_Demand (T : in out Test);
   procedure Test_05_Initialize_Clears_Every_Crosswalk (T : in out Test);

   --  ---- the output projection: FAULT ----
   procedure Test_06_Fault_Projects_Flashing_Red_Faces (T : in out Test);
   procedure Test_07_Fault_Projects_Dark_Pedestrian_Heads (T : in out Test);
   procedure Test_08_Fault_Projects_No_Request_Indicators (T : in out Test);

   --  ---- the output projection: NORMAL_OPERATION ----
   procedure Test_09_Normal_Projects_Vehicle_Faces (T : in out Test);
   procedure Test_10_Normal_Projects_Pedestrian_Heads (T : in out Test);
   procedure Test_11_Normal_Projects_Request_Indicators (T : in out Test);

   --  ---- Step: fault pre-emption ----
   procedure Test_13_Asserted_Fault_Enters_Fault_Mode (T : in out Test);
   procedure Test_14_Fault_Step_Emits_The_Projection (T : in out Test);
   procedure Test_15_Fault_Step_Changes_Nothing (T : in out Test);

   --  ---- Step: advance and emit ----
   procedure Test_16_Outputs_Project_The_Resulting_State (T : in out Test);
   procedure Test_17_Step_Advances_Every_Running_Timer (T : in out Test);
   procedure Test_18_Transition_Fires_On_Its_Boundary_Step (T : in out Test);
   procedure Test_19_Green_Edge_Clears_Left_Demand (T : in out Test);
   procedure Test_20_Green_Edge_Serves_Pedestrian_Request (T : in out Test);

   --  ---- Step: the sampling boundary (CONOPS 4.3) ----
   procedure Test_22_Boundary_Demand_Served_At_This_Onset (T : in out Test);

end Llr_4_Controller_Tests;
