--  TICK_PERIOD_US=1000 profile. Faithful real time; safe to flash. Selected by
--  the Naming trick in src/hal.gpr. See the Timings bodies.

package Timings.Tick_Config is
   Tick_Period_Us : constant := 1000;
   --  Wall-clock microseconds per logical millisecond; 1000 is faithful real
   --  time.
end Timings.Tick_Config;
