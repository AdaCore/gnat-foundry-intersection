--  Timings -- the HAL's timing service. Shared spec: identical across the
--  native (src/hal/host) and target (src/hal/qemu_zynq7000) profiles, which
--  supply the bodies. See src/hal.gpr.

with States;

package Timings is

   procedure Delay_For (Ms : States.Duration_Ms);
   --  Wait the requested number of *logical* milliseconds. The wall-clock
   --  span is scaled at compile time by the TICK_PERIOD_US profile (see the
   --  Timings.Tick_Config child selected by the Naming trick in src/hal.gpr)
   --  so the requirements suite can run faster than real time: each logical
   --  millisecond costs Tick_Period_Us microseconds of wall clock, with 1000
   --  giving faithful real time.
   --
   --  The delay is per-call relative (no running deadline), matching the
   --  "waits N ms" contract and the architecture's no-globals convention. It
   --  is therefore not drift-free across calls; a monotonic deadline can be
   --  reintroduced behind this same spec should cadence accuracy be required.
   --  @param Ms Number of logical milliseconds to wait

end Timings;
