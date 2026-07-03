--  The core loop body. The controller logic that was a nested stub here now
--  lives in the dedicated, HAL-independent, directly-provable Controller
--  package (child 4): the loop drives it through the four stages forever,
--  threading the Controller_State local (no globals) `in out` through Step.
--
--  Per-iteration ordering (design/architecture.md §"The core loop"): poll the
--  sources, compute the next state and its outputs, write the outputs, then
--  wait the delay the current state requires. Controller.Step folds the
--  compute-next-state and output-projection stages together and returns Wait,
--  the discrete-event min-time-to-next-event delay (see Controller's spec).

with Controller;

procedure State_Machine_Loop is
   State   : Controller.Controller_State;
   Sensors : States.Sensors_State;
   Outputs : States.Display_State;
   Wait    : States.Duration_Ms;
begin
   Controller.Initialize (State);
   loop
      Read_Sources (Sensors);                 --  1. poll the external sources
      Controller.Step (State, Sensors, Outputs, Wait);  --  2. compute next
      Write_Display (Outputs);                --  3. update the outputs
      Delay_For (Wait);                       --  4. wait the state's delay
   end loop;
end State_Machine_Loop;
