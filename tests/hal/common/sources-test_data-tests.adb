--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Sources.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

with Ada.Text_IO;

--  begin read only
--  end read only
package body Sources.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Sample (Gnattest_T : in out Test);
   procedure Test_Sample_fca1f9 (Gnattest_T : in out Test) renames Test_Sample;
--  id:2.2/fca1f9d4f66af1b6/Sample/1/0/
   procedure Test_Sample (Gnattest_T : in out Test) is
   --  sources.ads:9:4:Sample
--  end read only

      pragma Unreferenced (Gnattest_T);

      use type States.Sensors_State;

      All_Quiet : constant States.Sensors_State :=
        (Buttons    => (others => States.Released),
         Left_Turns => (others => States.No_Vehicle),
         Fault      => States.Not_Asserted);
      --  The baseline snapshot: nothing pressed, no vehicle, no fault.

      function Snapshot (Keys : String) return States.Sensors_State;
      --  Drive Sample against a temporary input stream preloaded with Keys
      --  and return the resulting snapshot. Mirrors the display tests'
      --  Run_Captured harness, but redirects standard *input* instead of
      --  output. Uses Put (not Put_Line): a trailing newline would decode as
      --  an unrecognized key, and while harmless we keep the feed exact.

      function With_Button
        (C : States.Crosswalk) return States.Sensors_State;
      --  All-quiet with a single crosswalk button Pressed.

      function With_Turn (A : States.Approach) return States.Sensors_State;
      --  All-quiet with a single approach left-turn detector Vehicle_Present.

      function Snapshot (Keys : String) return States.Sensors_State is
         Temp   : Ada.Text_IO.File_Type;
         Result : States.Sensors_State;
      begin
         Ada.Text_IO.Create (Temp);
         Ada.Text_IO.Put (Temp, Keys);
         Ada.Text_IO.Reset (Temp, Ada.Text_IO.In_File);
         Ada.Text_IO.Set_Input (Temp);

         Sample (Result);

         Ada.Text_IO.Set_Input (Ada.Text_IO.Standard_Input);
         Ada.Text_IO.Close (Temp);
         return Result;
      end Snapshot;

      function With_Button
        (C : States.Crosswalk) return States.Sensors_State
      is
         Result : States.Sensors_State := All_Quiet;
      begin
         Result.Buttons (C) := States.Pressed;
         return Result;
      end With_Button;

      function With_Turn (A : States.Approach) return States.Sensors_State is
         Result : States.Sensors_State := All_Quiet;
      begin
         Result.Left_Turns (A) := States.Vehicle_Present;
         return Result;
      end With_Turn;

      Everything : constant States.Sensors_State :=
        (Buttons    => (others => States.Pressed),
         Left_Turns => (others => States.Vehicle_Present),
         Fault      => States.Not_Asserted);
      --  Every button pressed and every detector active in one poll.

   begin

      --  Empty stream: the drain sees no keys, so the snapshot stays quiet.
      Assert
        (Snapshot ("") = All_Quiet,
         "an empty input stream should produce the all-quiet snapshot");

      --  Each crosswalk key isolates exactly its own pedestrian button;
      --  every unseen signal reads inactive.
      Assert
        (Snapshot ("1") = With_Button (States.NS_North),
         "'1' should press only the NS_North crosswalk button");
      Assert
        (Snapshot ("2") = With_Button (States.NS_South),
         "'2' should press only the NS_South crosswalk button");
      Assert
        (Snapshot ("3") = With_Button (States.EW_East),
         "'3' should press only the EW_East crosswalk button");
      Assert
        (Snapshot ("4") = With_Button (States.EW_West),
         "'4' should press only the EW_West crosswalk button");

      --  Each approach key isolates exactly its own left-turn detector.
      Assert
        (Snapshot ("n") = With_Turn (States.North),
         "'n' should set only the North left-turn detector");
      Assert
        (Snapshot ("s") = With_Turn (States.South),
         "'s' should set only the South left-turn detector");
      Assert
        (Snapshot ("e") = With_Turn (States.East),
         "'e' should set only the East left-turn detector");
      Assert
        (Snapshot ("w") = With_Turn (States.West),
         "'w' should set only the West left-turn detector");

      --  The full key set in one poll activates every signal, and the fault
      --  line -- which no key maps to -- stays Not_Asserted.
      declare
         use type States.Fault_Detection;
         Full : constant States.Sensors_State := Snapshot ("1234nsew");
      begin
         Assert
           (Full = Everything,
            "'1234nsew' should activate every button and detector");
         Assert
           (Full.Fault = States.Not_Asserted,
            "no key maps to the fault line; it stays Not_Asserted");
      end;

      --  Coalescing: repeating a key within one poll is idempotent.
      Assert
        (Snapshot ("11") = With_Button (States.NS_North),
         "repeated '1' should coalesce to a single NS_North press");

      --  Unrecognized keys are ignored: the snapshot stays all-quiet.
      Assert
        (Snapshot ("x") = All_Quiet,
         "an unrecognized key should leave the snapshot all-quiet");

--  begin read only
   end Test_Sample;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end Sources.Test_Data.Tests;
