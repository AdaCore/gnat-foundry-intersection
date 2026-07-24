--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Timings.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

with Ada.Calendar;
with Timings.Tick_Config;

--  begin read only
--  end read only
package body Timings.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Delay_For (Gnattest_T : in out Test);
   procedure Test_Delay_For_c5d16f (Gnattest_T : in out Test) renames Test_Delay_For;
--  id:2.2/c5d16fcaa0755408/Delay_For/1/0/
   procedure Test_Delay_For (Gnattest_T : in out Test) is
   --  timings.ads:9:4:Delay_For
--  end read only

      pragma Unreferenced (Gnattest_T);

      use type Ada.Calendar.Time;

      --  The wall-clock floor of a 5 logical-millisecond wait under the
      --  compiled-in tick profile: each logical millisecond costs
      --  Tick_Period_Us microseconds.
      Span_Ms : constant States.Duration_Ms := 5;
      Floor   : constant Duration :=
        Duration
          (Long_Float (Span_Ms)
           * Long_Float (Tick_Config.Tick_Period_Us)
           / 1_000_000.0);

      Before : constant Ada.Calendar.Time := Ada.Calendar.Clock;

   begin

      Delay_For (Span_Ms);

      Assert
        (Ada.Calendar.Clock - Before >= Floor,
         "Delay_For should wait at least the profile-scaled span");

--  begin read only
   end Test_Delay_For;
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
end Timings.Test_Data.Tests;
