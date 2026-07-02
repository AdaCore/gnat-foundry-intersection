procedure State_Machine_Loop is

   --  The evolving controller state, the compute seam, and its seed all live
   --  nested in this body: the project forbids globals, so the state is a
   --  local threaded through the loop, and the compute step is a subprogram
   --  taking it `in out`. This is a STUB. Child 4 owns the real
   --  Controller_State shape, the state-transition function, the Moore output
   --  mapping, and the per-state delays; it will flesh out (or promote) this
   --  seam. Until then the loop is behaviourally inert but compilable and
   --  provable, so it and child 4 can be developed in parallel.

   --  Minimal placeholder state: just the operating mode, enough to compile,
   --  prove, and be threaded through the loop.
   type Controller_State is record
      Mode : States.Mode;
   end record;

   Initial_State : constant Controller_State :=
     (Mode => States.Normal_Operation);

   --  Turn (state, sensors) into (next state, outputs, delay). The stub
   --  leaves State unchanged, ignores Sensors, and emits a fixed safe display
   --  (every vehicle face Red, every head Dont_Walk, no request indicators)
   --  with a fixed one-second wait.
   procedure Step
     (State   : in out Controller_State;
      Sensors : States.Sensors_State;
      Outputs : out States.Display_State;
      Wait    : out States.Duration_Ms);

   procedure Step
     (State   : in out Controller_State;
      Sensors : States.Sensors_State;
      Outputs : out States.Display_State;
      Wait    : out States.Duration_Ms)
   is
      pragma Unreferenced (State, Sensors);
   begin
      Outputs :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request));
      Wait := 1_000;
   end Step;

   State   : Controller_State := Initial_State;
   Sensors : States.Sensors_State;
   Outputs : States.Display_State;
   Wait    : States.Duration_Ms;
begin
   loop
      Read_Sources (Sensors);                 --  1. poll the external sources
      Step (State, Sensors, Outputs, Wait);   --  2. compute the next state
      Write_Display (Outputs);                --  3. update the outputs
      Delay_For (Wait);                       --  4. wait the state's delay
   end loop;
end State_Machine_Loop;
