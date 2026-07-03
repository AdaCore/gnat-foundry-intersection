--  Application entry point. Initialises the display, wires the two data buses
--  to the HAL (source bus <- Sources.Sample, display bus -> Display.Show),
--  instantiates the generic core loop against those wires plus the HAL timing
--  service, and runs it forever. All wiring is local -- no globals
--  (design/architecture.md sections "The core loop" and "Code conventions").

with Timings;
with Sources;
with Display;
with Buses;
with State_Machine_Loop;

procedure Main is
   --  Wire the buses: each instantiation binds one bus end to its HAL side.
   --  The source-bus latch is per-instance state living here in main's
   --  declarative region, not a source-level global.
   --
   --  The latch's persistence between reads is staged for the future
   --  asynchronous revision (design/architecture.md §Buses); in this
   --  synchronous revision it is cleared on every read, so some compiler
   --  versions flag this instance's latch as an "unused hidden state".
   --  Silence that one diagnostic -- it reflects the staged design, not a
   --  defect (see the matching note in buses.adb).
   pragma Warnings (Off, "*unused hidden states*");
   package Source_Wire is new Buses.Source_Bus (Activate => Sources.Sample);
   pragma Warnings (On, "*unused hidden states*");
   package Display_Wire is new Buses.Display_Bus (Consume => Display.Show);

   --  Instantiate the generic core loop against the consumer side of the
   --  source bus, the producer side of the display bus, and the HAL delay.
   procedure Run is new
     State_Machine_Loop
       (Delay_For     => Timings.Delay_For,
        Read_Sources  => Source_Wire.Read,
        Write_Display => Display_Wire.Write);
begin
   Display.Initialize;
   Display.Diag_Write_Line ("startup");
   Run;  --  No_Return: drives the four-stage loop forever.
end Main;
