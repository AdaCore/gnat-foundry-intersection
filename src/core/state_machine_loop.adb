--  The core loop body. The controller logic that was a nested stub here now
--  lives in the dedicated, HAL-independent, directly-provable Controller
--  package (child 4): the loop drives it through the four stages forever,
--  threading the Controller_State local (no globals) `in out` through Step.
--
--  Per-iteration ordering (design/architecture.md §"The core loop"): poll the
--  sources, compute the next state and its outputs, write the outputs, then
--  wait the delay the controller asked for. Controller.Step folds the
--  compute-next-state and output-projection stages together and returns Wait,
--  the discrete-event time to the next timed transition capped at the
--  sampling period States.T_Sample (see Controller's spec); intervening
--  iterations are pure sampling steps that re-read the inputs and re-emit
--  the unchanged Moore outputs. The loop itself is cadence-ignorant -- it
--  just passes Wait through to Delay_For.

with Controller;

procedure State_Machine_Loop is
   State   : Controller.Controller_State;
   Sensors : States.Sensors_State;
   Outputs : States.Display_State;
   Wait    : States.Duration_Ms;
begin
   Controller.Initialize (State);
   loop
      --  1. poll the external sources
      Read_Sources (Sensors);
      --  2. compute next
      Controller.Step (State, Sensors, Outputs, Wait);
      --  3. update the outputs
      Write_Display (Outputs);
      --  4. wait the delay Step returned (<= T_SAMPLE)
      Delay_For (Wait);
   end loop;
end State_Machine_Loop;
