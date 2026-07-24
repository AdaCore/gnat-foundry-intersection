--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into States.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

--  begin read only
--  end read only
package body States.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Face_Of (Gnattest_T : in out Test);
   procedure Test_Face_Of_e7c064 (Gnattest_T : in out Test) renames Test_Face_Of;
--  id:2.2/e7c064a7a7c8aaee/Face_Of/1/0/
   procedure Test_Face_Of (Gnattest_T : in out Test) is
   --  states.ads:226:4:Face_Of
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Gnattest_Generated.Default_Assert_Value,
         "Test not implemented.");

--  begin read only
   end Test_Face_Of;
--  end read only


--  begin read only
   procedure Test_Is_Go (Gnattest_T : in out Test);
   procedure Test_Is_Go_f67b6e (Gnattest_T : in out Test) renames Test_Is_Go;
--  id:2.2/f67b6e1a4950facc/Is_Go/1/0/
   procedure Test_Is_Go (Gnattest_T : in out Test) is
   --  states.ads:242:4:Is_Go
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Gnattest_Generated.Default_Assert_Value,
         "Test not implemented.");

--  begin read only
   end Test_Is_Go;
--  end read only


--  begin read only
   --  procedure Test_Coalesce (Gnattest_T : in out Test);
   --  procedure Test_Coalesce_f3b6d8 (Gnattest_T : in out Test) renames Test_Coalesce;
--  id:2.2/f3b6d8d46fd3cc92/Coalesce/1/1/
   --  procedure Test_Coalesce (Gnattest_T : in out Test) is
--  end read only
--  
--        pragma Unreferenced (Gnattest_T);
--  
--        --  Build a snapshot from All_Quiet with a single field turned active,
--        --  so each assertion isolates one operand/field of the OR-accumulation.
--  
--        function With_Button
--          (S : Sensors_State; C : Crosswalk) return Sensors_State
--        is
--           Result : Sensors_State := S;
--        begin
--           Result.Buttons (C) := Pressed;
--           return Result;
--        end With_Button;
--  
--        function With_Left_Turn
--          (S : Sensors_State; Ap : Approach) return Sensors_State
--        is
--           Result : Sensors_State := S;
--        begin
--           Result.Left_Turns (Ap) := Vehicle_Present;
--           return Result;
--        end With_Left_Turn;
--  
--        function With_Fault (S : Sensors_State) return Sensors_State is
--           Result : Sensors_State := S;
--        begin
--           Result.Fault := Asserted;
--           return Result;
--        end With_Fault;
--  
--     begin
--  
--        --  Identity / all-inactive: coalescing two quiet snapshots stays quiet.
--  
--        Assert
--          (Coalesce (All_Quiet, All_Quiet) = All_Quiet,
--           "Coalesce (All_Quiet, All_Quiet) should be All_Quiet");
--  
--        --  Pedestrian button: Pressed dominates Released, from either operand
--        --  (exercises both sides of the per-crosswalk OR for MCDC).
--  
--        Assert
--          (Coalesce (With_Button (All_Quiet, NS_North), All_Quiet).Buttons
--             (NS_North)
--           = Pressed,
--           "A-side Pressed button should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, With_Button (All_Quiet, NS_North)).Buttons
--             (NS_North)
--           = Pressed,
--           "B-side Pressed button should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, All_Quiet).Buttons (NS_North) = Released,
--           "Two Released buttons should stay Released");
--  
--        --  Left-turn detector: Vehicle_Present dominates No_Vehicle, from either
--        --  operand (both sides of the per-approach OR).
--  
--        Assert
--          (Coalesce (With_Left_Turn (All_Quiet, North), All_Quiet).Left_Turns
--             (North)
--           = Vehicle_Present,
--           "A-side Vehicle_Present should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, With_Left_Turn (All_Quiet, North)).Left_Turns
--             (North)
--           = Vehicle_Present,
--           "B-side Vehicle_Present should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, All_Quiet).Left_Turns (North) = No_Vehicle,
--           "Two No_Vehicle detectors should stay No_Vehicle");
--  
--        --  Fault line: Asserted dominates Not_Asserted, from either operand
--        --  (both sides of the fault OR).
--  
--        Assert
--          (Coalesce (With_Fault (All_Quiet), All_Quiet).Fault = Asserted,
--           "A-side Asserted fault should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, With_Fault (All_Quiet)).Fault = Asserted,
--           "B-side Asserted fault should dominate");
--  
--        Assert
--          (Coalesce (All_Quiet, All_Quiet).Fault = Not_Asserted,
--           "Two Not_Asserted fault lines should stay Not_Asserted");
--  
--        --  Independence: active values at different indices are combined without
--        --  bleeding into each other -- a button pressed on one crosswalk and a
--        --  vehicle present on one approach coalesce into a single snapshot that
--        --  carries both, while every other index stays inactive.
--  
--        declare
--           A      : constant Sensors_State :=
--             With_Button (All_Quiet, NS_North);
--           B      : constant Sensors_State :=
--             With_Left_Turn (All_Quiet, East);
--           Merged : constant Sensors_State := Coalesce (A, B);
--        begin
--           Assert
--             (Merged.Buttons (NS_North) = Pressed
--              and then Merged.Left_Turns (East) = Vehicle_Present,
--              "Independent active fields should both survive coalescing");
--  
--           Assert
--             (Merged.Buttons (EW_East) = Released
--              and then Merged.Left_Turns (North) = No_Vehicle
--              and then Merged.Fault = Not_Asserted,
--              "Untouched indices should remain inactive after coalescing");
--        end;
--  
--  begin read only
   --  end Test_Coalesce;
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
end States.Test_Data.Tests;
