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
   package Source_Wire is new Buses.Source_Bus (Bus_Write => Sources.Sample);
   package Display_Wire is new Buses.Display_Bus (Bus_Read => Display.Show);

   --  Instantiate the generic core loop against the consumer side of the
   --  source bus, the producer side of the display bus, and the HAL delay.
   procedure Run is new
     State_Machine_Loop
       (Delay_For     => Timings.Delay_For,
        Read_Sources  => Source_Wire.Bus_Read,
        Write_Display => Display_Wire.Bus_Write);
begin
   Display.Initialize;
   Display.Diag_Write_Line ("startup");
   Run;  --  No_Return: drives the four-stage loop forever.
end Main;
