--  AUnit driver for the requirements-based harness, copied over the generated
--  driver of the same name by `make generate-tests-reqs`.
--
--  gnattest's own driver does not compile for a harness whose
--  generated-skeleton set is empty: with no test routines to map, it emits
--  `Test_Routines_Total : constant Positive := 0` and an empty if/else chain
--  in Gnattest_Generated.Mapping. This driver runs the main suite, so it never
--  withs that unit.

with AUnit;
with AUnit.Options;
with AUnit.Reporter.gnattest;
with AUnit.Run;
with Ada.Command_Line;
with Gnattest_Main_Suite;

procedure Test_Runner is

   use type AUnit.Status;

   function Runner is new AUnit.Run.Test_Runner_With_Status
     (Gnattest_Main_Suite.Suite);

   Reporter : AUnit.Reporter.gnattest.gnattest_Reporter;
   Options  : AUnit.Options.AUnit_Options := AUnit.Options.Default_Options;
   Outcome  : AUnit.Status;

begin
   Options.Report_Successes := True;
   Outcome := Runner (Reporter, Options);

   if Outcome = AUnit.Failure then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
