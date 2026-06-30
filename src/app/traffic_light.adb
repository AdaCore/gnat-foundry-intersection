--  Top-level entry point.

with HAL;

procedure Traffic_Light is
begin
   HAL.Initialize;
   HAL.Diag_Write_Line ("startup");
   loop
      HAL.Tick_Wait;
   end loop;
end Traffic_Light;
