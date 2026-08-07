--  The core loop -- the centrepiece of the controller (design/architecture.md
--  §"The core loop"). A generic subprogram that drives the state machine
--  through its four stages forever: poll the external sources, compute the
--  next state, update the outputs, then sleep the fixed sampling period
--  T_SAMPLE (llr_5_core_loop.2), so the loop runs at a uniform cadence and
--  the sources are re-read exactly once every T_SAMPLE (llr_5_core_loop.4).
--
--  It is parameterized by exactly the consumer/producer procedures of the two
--  data buses -- never the bus packages themselves -- so the loop stays
--  ignorant of both the source latch and the display implementation, which
--  the HAL provides. The three formals match the HAL surface one-for-one
--  (Timings.Delay_For, Sources.Sample / Buses.Source_Bus.Read, and
--  Display.Show / Buses.Display_Bus.Write), so `app` can instantiate this
--  loop directly against the wired buses.

with States;

generic
   with procedure Delay_For (Ms : States.Duration_Ms);
   --  Sleep the fixed sampling period -- always called with States.T_Sample
   --  (Timings.Delay_For's signature).

   with procedure Read_Sources (Sensors : out States.Sensors_State);
   --  Consumer side of the source bus: sample every input source into one
   --  snapshot (Buses.Source_Bus.Read's signature).

   with procedure Write_Display (Outputs : States.Display_State);
   --  Producer side of the display bus: push the outputs to the display
   --  (Buses.Display_Bus.Write's signature).
procedure State_Machine_Loop
with
  SPARK_Mode => On,
  --@covers llr_5_core_loop.3
  No_Return;
