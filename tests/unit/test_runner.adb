--  Minimal test runner. Replace with AUnit or gnattest harness once those
--  are wired into the Alire crate.
--
--  @req FR-PH-03, FR-PH-04, FR-PD-05, FR-PD-06

with Ada.Text_IO;
with Phase_Sequencer;
with Conflict_Check;

procedure Test_Runner is

   use Ada.Text_IO;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("PASS " & Name);
      else
         Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Placeholder tests — these will become real tests as the
   --  implementation lands.

   procedure Test_Sequencer_Initial_State is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      Check (S.Current = Phase_Sequencer.Startup,
             "sequencer starts in Startup");
   end Test_Sequencer_Initial_State;

   procedure Test_Conflict_Matrix_Reflexivity is
      use Conflict_Check;
   begin
      for M in Movement loop
         Check (not Conflicts (M, M),
                "movement does not conflict with itself: "
                & Movement'Image (M));
      end loop;
   end Test_Conflict_Matrix_Reflexivity;

begin
   Test_Sequencer_Initial_State;
   Test_Conflict_Matrix_Reflexivity;

   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " FAILURES");
   end if;
end Test_Runner;
