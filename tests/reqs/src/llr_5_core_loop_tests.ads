--  Requirements-based tests for requirements/llr/llr_5_core_loop.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  All three testable statements are observed through Reqs_Support.Loop_Spy,
--  which instantiates State_Machine_Loop against recording formals and escapes
--  the No_Return loop by exception -- see that package for why the loop is
--  observable at all. Statement .3 (No_Return, no termination path) is not
--  here: it constrains the declaration, not the values, and is classified as
--  analysis.

with AUnit.Test_Fixtures;

package Llr_5_Core_Loop_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Initialize_Once_Before_First_Iteration (T : in out Test);

   procedure Test_02_Iteration_Runs_The_Four_Stages_In_Order (T : in out Test);

   procedure Test_04_Sources_Read_Once_Per_Sampling_Period (T : in out Test);

end Llr_5_Core_Loop_Tests;
