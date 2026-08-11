with AUnit.Assertions; use AUnit.Assertions;

with Ada.Real_Time;

with States;
with Timings;
with Timings.Tick_Config;

package body Llr_6_Hal_Tests is

   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;

   ------------------------------------------------------------------------
   --  Statement .1 -- Delay_For returns only after the logical span
   ------------------------------------------------------------------------

   procedure Test_01_Delay_For_Returns_After_The_Logical_Span
     (T : in out Test)
   is
      --@covers llr_6_hal.1

      pragma Unreferenced (T);

      Span : constant States.Duration_Ms := 20;
      --  Twenty logical milliseconds. The floor has to be large against the
      --  clock's granularity for the measurement to mean anything, and small
      --  against the suite's runtime: twenty is 20 ms of wall clock under the
      --  faithful profile and still 200 us under the shortest tick the build
      --  offers (TICK_PERIOD_US=10), which is four orders of magnitude above
      --  Ada.Real_Time's tick, while costing the suite a fiftieth of a second
      --  at worst.

      Floor : constant Ada.Real_Time.Time_Span :=
        Ada.Real_Time.Microseconds
          (Integer (Span) * Timings.Tick_Config.Tick_Period_Us);
      --  The wall clock the statement requires the call to cover: Ms logical
      --  milliseconds, one logical millisecond being Tick_Period_Us
      --  microseconds. Expressed through the named constant, so the assertion
      --  follows whichever tick profile was compiled in rather than assuming
      --  real time.

      Before  : Ada.Real_Time.Time;
      Elapsed : Ada.Real_Time.Time_Span;
   begin

      --  The statement bounds the call from below only -- "shall return only
      --  after Ms logical milliseconds have elapsed" -- so only the floor is
      --  asserted. No ceiling is: the requirement gives none, and a scheduler
      --  on a loaded machine may return the call arbitrarily late without
      --  violating it, so an upper bound would test the machine instead of the
      --  code.
      --
      --  The clock is read either side of the one call and nothing else is
      --  done in between, so the measured span is the call's own.
      --  Ada.Real_Time rather than Ada.Calendar: it is monotonic, so a clock
      --  adjustment during the wait cannot fake a pass. (The wall-clock
      --  measurement is the construction the tests/hal skeleton used; the
      --  floor here is re-derived from the statement.)

      Before := Ada.Real_Time.Clock;

      Timings.Delay_For (Span);

      Elapsed := Ada.Real_Time.Clock - Before;

      Assert
        (Elapsed >= Floor,
         "Delay_For ("
         & States.Duration_Ms'Image (Span)
         & " ) returned after"
         & Duration'Image (Ada.Real_Time.To_Duration (Elapsed))
         & " s of wall clock, but the requirement gives a span of at least"
         & Duration'Image (Ada.Real_Time.To_Duration (Floor))
         & " s");

   end Test_01_Delay_For_Returns_After_The_Logical_Span;

end Llr_6_Hal_Tests;
