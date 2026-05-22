--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Diagnostic.Test_Data.

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
package body Diagnostic.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Emit_Transition (Gnattest_T : in out Test);
   procedure Test_Emit_Transition_0b6895 (Gnattest_T : in out Test) renames Test_Emit_Transition;
--  id:2.2/0b68955e4fd98c02/Emit_Transition/1/0/
   procedure Test_Emit_Transition (Gnattest_T : in out Test) is
   --  diagnostic.ads:17:4:Emit_Transition
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Gnattest_Generated.Default_Assert_Value,
         "Test not implemented.");

--  begin read only
   end Test_Emit_Transition;
--  end read only


--  begin read only
   procedure Test_Emit_Heartbeat (Gnattest_T : in out Test);
   procedure Test_Emit_Heartbeat_386706 (Gnattest_T : in out Test) renames Test_Emit_Heartbeat;
--  id:2.2/386706c0f0b6ca57/Emit_Heartbeat/1/0/
   procedure Test_Emit_Heartbeat (Gnattest_T : in out Test) is
   --  diagnostic.ads:21:4:Emit_Heartbeat
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Gnattest_Generated.Default_Assert_Value,
         "Test not implemented.");

--  begin read only
   end Test_Emit_Heartbeat;
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
end Diagnostic.Test_Data.Tests;
