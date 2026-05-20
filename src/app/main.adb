--  Top-level entry point.
--
--  Wires the HAL up to the core sequencer and runs the main loop.

with HAL;
with Phase_Sequencer;
with Diagnostic;

procedure Main is
   use type Phase_Sequencer.Phase_Id;
   S          : Phase_Sequencer.State;
   Last_Phase : Phase_Sequencer.Phase_Id := S.Current;
   Ms_Counter : Natural := 0;
begin
   HAL.Initialize;
   HAL.Diag_Write_Line ("startup");
   Diagnostic.Emit_Transition (S);

   loop
      HAL.Tick_Wait;
      Phase_Sequencer.Tick (S);
      Ms_Counter := Ms_Counter + 1;

      if S.Current /= Last_Phase then
         Diagnostic.Emit_Transition (S);
         Last_Phase := S.Current;
      end if;

      if Ms_Counter mod 1000 = 0 then
         Diagnostic.Emit_Heartbeat (Ms_Counter);
      end if;
      --  TODO: dispatch S.Active to HAL outputs.
      --  TODO: exit condition for host build (e.g., N ticks then quit).
   end loop;
end Main;
