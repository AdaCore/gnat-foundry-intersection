--  Properties of the demand script (System_Support.Demand): what the sources
--  read for a given window, before any of it reaches the program. Every timing
--  test that scripts demand rests on these.

with AUnit.Test_Fixtures;

package Demand_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Windows_Bound_The_Scripted_Reads (T : in out Test);

end Demand_Tests;
