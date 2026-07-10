--  The core loop -- the centrepiece of the controller (design/architecture.md
--  §"The core loop"). A generic subprogram that drives the state machine
--  through its four stages forever: poll the external sources, compute the
--  next state, update the outputs, then wait the delay the current state
--  requires.
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
   --  Wait the delay required by the current state
   --  (Timings.Delay_For's signature).

   with procedure Read_Sources (Sensors : out States.Sensors_State);
   --  Consumer side of the source bus: sample every input source into one
   --  snapshot (Buses.Source_Bus.Read's signature).

   with procedure Write_Display (Outputs : States.Display_State);
   --  Producer side of the display bus: push the outputs to the display
   --  (Buses.Display_Bus.Write's signature).
procedure State_Machine_Loop
with SPARK_Mode => On, No_Return;
