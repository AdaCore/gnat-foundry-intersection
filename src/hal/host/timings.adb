--  Timings body -- host profile. Scales the requested logical span by the
--  compile-time TICK_PERIOD_US profile and waits it out with Ada.Calendar.

with Ada.Calendar; use Ada.Calendar;
with Timings.Tick_Config;

package body Timings is

   procedure Delay_For (Ms : States.Duration_Ms) is
      --  Wall-clock seconds for the requested logical span: each logical
      --  millisecond costs Tick_Period_Us microseconds (1000 = real time).
      Span : constant Duration :=
        Duration
          (Long_Float (Ms)
           * Long_Float (Tick_Config.Tick_Period_Us)
           / 1_000_000.0);
   begin
      delay until Clock + Span;
   end Delay_For;

end Timings;
