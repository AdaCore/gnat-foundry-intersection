--  Top-level entry point.
--
--  Wires the HAL up to the core sequencer and runs the main loop.

with HAL;
with Phase_Sequencer;
with Pedestrian;
with Diagnostic;

procedure Main is
   use type Phase_Sequencer.Phase_Id;

   --  HAL.Crosswalk and Pedestrian.Crosswalk are parallel enums with
   --  matching literal names; the bridge keeps the HAL surface unchanged.
   function To_Ped (CW : HAL.Crosswalk) return Pedestrian.Crosswalk is
     (case CW is
        when HAL.NS_North => Pedestrian.NS_North,
        when HAL.NS_South => Pedestrian.NS_South,
        when HAL.EW_East  => Pedestrian.EW_East,
        when HAL.EW_West  => Pedestrian.EW_West);

   S          : Phase_Sequencer.State;
   Last_Phase : Phase_Sequencer.Phase_Id := S.Current;
   Ms_Counter : Natural := 0;
begin
   HAL.Initialize;
   HAL.Diag_Write_Line ("startup");
   Diagnostic.Emit_Transition (S);

   loop
      HAL.Tick_Wait;

      --  Poll ped buttons; HAL is responsible for the FR-PD-01 50 ms
      --  debounce, so any True here is a real press.
      for CW in HAL.Crosswalk loop
         if HAL.Read_Button (CW) then
            Phase_Sequencer.Press_Ped (S, To_Ped (CW));
         end if;
      end loop;

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
