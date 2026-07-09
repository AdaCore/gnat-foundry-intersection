--  TICK_PERIOD_US=300 profile. Compensates QEMU's ~3.33x-slow timer
--  (~1 ms wall/tick); not faithful real time, do not flash. See the Timings
--  bodies.

package Timings.Tick_Config is
   Tick_Period_Us : constant := 300;
   --  Wall-clock microseconds per logical millisecond; 1000 is faithful real
   --  time. This can be used to speed up the clock by a factor of 3.33,
   --  needed on some versions of QEMU to simulate real-time.
end Timings.Tick_Config;
