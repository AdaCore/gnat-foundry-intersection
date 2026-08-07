--  The core loop body. The controller logic that was a nested stub here now
--  lives in the dedicated, HAL-independent, directly-provable Controller
--  package (child 4): the loop drives it through the four stages forever,
--  threading the Controller_State local (no globals) `in out` through Step.
--
--  Per-iteration ordering (design/architecture.md §"The core loop"): poll the
--  sources, compute the next state and its outputs, write the outputs, then
--  sleep the fixed sampling period. The loop drives the fixed-cadence
--  engine: Controller.Step folds the compute-next-state and
--  output-projection stages together and accounts for exactly one T_SAMPLE
--  of logical time on the timers in the loop-local Controller_State (see
--  Controller's spec); intervening iterations are pure sampling steps that
--  re-read the inputs and re-emit the unchanged Moore outputs. The loop
--  itself owns the cadence: it sleeps exactly T_SAMPLE every iteration, in
--  every mode.

with Controller;

procedure State_Machine_Loop is
   State   : Controller.Controller_State;
   Sensors : States.Sensors_State;
   Outputs : States.Display_State;
begin
   Controller.Initialize (State);
   --  No frame is published before the first iteration, so the initialised
   --  state is displayed for one T_SAMPLE less than its dwell: the power-on
   --  all-red is lit for T_BARRIER - T_SAMPLE. Open, as #111.
   loop
      --  1. poll the external sources
      Read_Sources (Sensors);
      --  2. compute next
      Controller.Step (State, Sensors, Outputs);
      --  3. update the outputs
      Write_Display (Outputs);
      --  4. sleep the fixed sampling period (llr_5_core_loop.2)
      Delay_For (States.T_Sample);
   end loop;
end State_Machine_Loop;
