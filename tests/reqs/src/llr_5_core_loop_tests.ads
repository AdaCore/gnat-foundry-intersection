--  Requirements-based tests for requirements/llr/llr_5_core_loop.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Every statement is observed through Reqs_Support.Loop_Spy, which
--  instantiates State_Machine_Loop against recording formals and escapes the
--  No_Return loop by exception -- see that package for why the loop is
--  observable at all.
--
--  Statement .3 (No_Return, no termination path) is the odd one: most of its
--  evidence is not here. `No_Return` on the declaration is a legality rule, so
--  the compiler rejects any return statement in the body, and GNATprove
--  discharges the implicit return at the end of it. What the routine below
--  adds is the behavioural half -- that a bounded run leaves the loop only by
--  the exception the spy injects.

with AUnit.Test_Fixtures;

package Llr_5_Core_Loop_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Initialize_Once_Before_First_Iteration (T : in out Test);

   procedure Test_02_Iteration_Runs_The_Four_Stages_In_Order (T : in out Test);

   procedure Test_03_Loop_Never_Returns_To_Its_Caller (T : in out Test);

   procedure Test_04_Sources_Read_Once_Per_Sampling_Period (T : in out Test);

   procedure Test_05_Startup_Publishes_And_Holds_Before_First_Step
     (T : in out Test);

end Llr_5_Core_Loop_Tests;
