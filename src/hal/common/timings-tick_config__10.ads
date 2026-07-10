--  TICK_PERIOD_US=10 profile. Not faithful real time, do not flash. See the
--  Timings bodies.

package Timings.Tick_Config is
   Tick_Period_Us : constant := 10;
   --  Wall-clock microseconds per logical millisecond;
   --  speed up the simulation by a factor of 100.
end Timings.Tick_Config;
