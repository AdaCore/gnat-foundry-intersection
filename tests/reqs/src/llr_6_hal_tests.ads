--  Requirements-based tests for requirements/llr/llr_6_hal.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  The file states one requirement -- the delay semantics the core invokes.
--  Everything else it records is an assumption on the HAL profile (input
--  sampling and output rendering), discharged by the profile rather than
--  verified here, so it has no routine.

with AUnit.Test_Fixtures;

package Llr_6_Hal_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Delay_For_Returns_After_The_Logical_Span
     (T : in out Test);

end Llr_6_Hal_Tests;
