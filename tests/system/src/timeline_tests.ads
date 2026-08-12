--  Properties of the observer (System_Support.Timeline) rather than of the
--  program it observes: what a timeline must hold before a test can read a
--  duration off it.

with AUnit.Test_Fixtures;

package Timeline_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Full_Cycle_Fits_The_Timeline (T : in out Test);

end Timeline_Tests;
