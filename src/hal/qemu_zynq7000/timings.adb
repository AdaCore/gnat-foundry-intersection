--  Timings body -- bare-metal arm-eabi (Cortex-A9) profile for QEMU's
--  `xilinx-zynq-a9` machine, built against the `light-tasking-zynq7000`
--  runtime. Ada.Real_Time is backed by the Zynq private timer.
--
--  The wall-clock span for one logical millisecond comes from the
--  TICK_PERIOD_US profile spec the GPR picks (see timings-tick_config__*.ads).
--  1000 = faithful real time (a real Zynq-7000 or clock-correct QEMU); lower
--  values shorten each tick for a faster requirements suite (300 compensates
--  QEMU's ~3.33x-slow Cortex-A9 private timer). Any non-1000 build is NOT
--  faithful and should not be flashed.
--
--  This is a per-call relative delay; it drops the old Tick_Wait's running
--  Next_Tick deadline (see the spec's note on drift).

with Ada.Real_Time; use Ada.Real_Time;
with Timings.Tick_Config;

package body Timings is

   procedure Delay_For (Ms : States.Duration_Ms) is
      Span : constant Time_Span :=
        Microseconds (Tick_Config.Tick_Period_Us) * Integer (Ms);
   begin
      delay until Clock + Span;
   end Delay_For;

end Timings;
