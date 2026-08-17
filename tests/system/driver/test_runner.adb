--  AUnit driver for the system-level tests. Written out rather than generated:
--  gnattest is not involved in this harness.

with AUnit;
with AUnit.Options;
with AUnit.Reporter.Text;
with AUnit.Run;
with Ada.Command_Line;

with System_Suite;

procedure Test_Runner is

   use type AUnit.Status;

   function Runner is new
     AUnit.Run.Test_Runner_With_Status (System_Suite.Suite);

   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Options  : AUnit.Options.AUnit_Options := AUnit.Options.Default_Options;
   Outcome  : AUnit.Status;

begin
   Options.Report_Successes := True;
   Outcome := Runner (Reporter, Options);

   if Outcome = AUnit.Failure then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Runner;
