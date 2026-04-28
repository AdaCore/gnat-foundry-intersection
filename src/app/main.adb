--  Top-level entry point.
--
--  Wires the HAL up to the core sequencer and runs the main loop.

with HAL;
with Phase_Sequencer;

procedure Main is
   S : Phase_Sequencer.State;
begin
   HAL.Initialize;
   HAL.Diag_Write_Line ("startup");

   loop
      HAL.Tick_Wait;
      Phase_Sequencer.Tick (S);
      --  TODO: dispatch S.Active to HAL outputs.
      --  TODO: exit condition for host build (e.g., N ticks then quit).
   end loop;
end Main;
