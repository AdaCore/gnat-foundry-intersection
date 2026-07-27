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

      --@covers none: input sampling is out of requirement scope (llr_6_hal sample assumption)

      pragma Unreferenced (Gnattest_T);

      use type States.Sensors_State;

      Value : States.Sensors_State;

   begin

      Sample (Value);

      --  The host stub producer documents an all-quiet snapshot: no buttons
      --  pressed, no left-turn vehicles, no fault asserted.
      Assert
        (Value
         = States.Sensors_State'
             (Buttons    => (others => States.Released),
              Left_Turns => (others => States.No_Vehicle),
              Fault      => States.Not_Asserted),
         "the host Sample stub should produce the all-quiet snapshot");

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
