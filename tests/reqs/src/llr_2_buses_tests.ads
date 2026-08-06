--  Requirements-based tests for requirements/llr/llr_2_buses.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Both buses are generic over the one subprogram that carries a value across
--  their boundary -- Source_Bus over its producer, Display_Bus over its
--  consumer -- so every statement here is observed by instantiating the bus
--  against a recording spy and reading what the spy saw. The spies are local
--  to the body: they are shaped by these four statements and nothing else.

with AUnit.Test_Fixtures;

package Llr_2_Buses_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  ---- the source bus (.1-.3) ----
   procedure Test_01_Bus_Read_Obtains_Whole_Snapshot_From_Producer
     (T : in out Test);
   procedure Test_02_Each_Signal_Reported_At_The_Level_Supplied
     (T : in out Test);
   procedure Test_03_Bus_Retains_No_Level_Between_Reads (T : in out Test);

   --  ---- the display bus (.4) ----
   procedure Test_04_Bus_Write_Delivers_Before_Returning (T : in out Test);

end Llr_2_Buses_Tests;
