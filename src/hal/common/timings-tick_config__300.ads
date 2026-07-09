--  TICK_PERIOD_US=300 profile. Compensates QEMU's ~3.33x-slow timer
--  (~1 ms wall/tick); not faithful real time, do not flash. See the Timings
--  bodies.
package Timings.Tick_Config is
   Tick_Period_Us : constant := 300;
end Timings.Tick_Config;
