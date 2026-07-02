--  Top-level entry point.
--
--  Placeholder main: brings the display up, emits a startup line, and paces a
--  bare loop with the timing service. Full bus/core wiring -- instantiating
--  Buses.Source_Bus / Buses.Display_Bus against Sources.Sample / Display.Show
--  and running the core loop -- lands with the app.gpr work item.

with Display;
with Timings;

procedure Traffic_Light is
begin
   Display.Initialize;
   Display.Diag_Write_Line ("startup");
   loop
      Timings.Delay_For (1);
   end loop;
end Traffic_Light;
