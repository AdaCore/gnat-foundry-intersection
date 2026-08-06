--  The spy's implementation. The three recorders and the counters are body
--  state because the generic's formals are procedures with fixed profiles:
--  there is nowhere in the loop's boundary to thread a context through, so the
--  instance is a single library-level one and Run resets its state.

with State_Machine_Loop;

package body Reqs_Support.Loop_Spy is

   Unset : constant Event :=
     (Stage   => Read_Sources_Stage,
      Sensors => Quiet,
      Outputs =>
        (Through  => No_Through,
         Left     => No_Left,
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request)),
      Ms      => 0);
   --  Filler for the unwritten tail of the trace. Never read: Nth's
   --  precondition keeps a test inside the recorded prefix.

   Trace : array (Event_Index) of Event := (others => Unset);
   Logged : Natural := 0;

   Script : Sensor_Script := All_Quiet;
   Reads  : Natural := 0;

   Wanted : Natural := 0;
   Done   : Natural := 0;

   Escaped : Boolean := False;
   --  Set by Run's handler, so it distinguishes the loop being escaped from
   --  the loop returning. Nothing is assigned *after* the call to Drive: a
   --  statement there would be unreachable code, and leaving it out is what
   --  makes False mean "the loop returned" (llr_5_core_loop.3).

   procedure Record_Event (E : Event);

   procedure Spy_Delay_For (Ms : States.Duration_Ms);
   procedure Spy_Read_Sources (Sensors : out States.Sensors_State);
   procedure Spy_Write_Display (Outputs : States.Display_State);

   ------------------------------------------------------------------------
   --  The recorders
   ------------------------------------------------------------------------

   procedure Record_Event (E : Event) is
   begin
      if Logged < Max_Events then
         Logged := Logged + 1;
         Trace (Logged) := E;
      end if;
   end Record_Event;

   procedure Spy_Read_Sources (Sensors : out States.Sensors_State) is
   begin
      Reads := Reads + 1;
      Sensors := (if Reads <= Max_Events then Script (Reads) else Quiet);

      Record_Event
        (Event'
           (Stage   => Read_Sources_Stage,
            Sensors => Sensors,
            Outputs => Unset.Outputs,
            Ms      => 0));
   end Spy_Read_Sources;

   procedure Spy_Write_Display (Outputs : States.Display_State) is
   begin
      Record_Event
        (Event'
           (Stage   => Write_Display_Stage,
            Sensors => Quiet,
            Outputs => Outputs,
            Ms      => 0));
   end Spy_Write_Display;

   procedure Spy_Delay_For (Ms : States.Duration_Ms) is
   begin
      Record_Event
        (Event'
           (Stage   => Delay_For_Stage,
            Sensors => Quiet,
            Outputs => Unset.Outputs,
            Ms      => Ms));

      --  The delay closes the iteration, so the count is complete here and
      --  the escape leaves a whole number of iterations in the trace.

      Done := Done + 1;

      if Done >= Wanted then
         raise Escape;
      end if;
   end Spy_Delay_For;

   ------------------------------------------------------------------------
   --  The instance under test
   ------------------------------------------------------------------------

   procedure Drive is new
     State_Machine_Loop
       (Delay_For     => Spy_Delay_For,
        Read_Sources  => Spy_Read_Sources,
        Write_Display => Spy_Write_Display);
   --  The loop itself, wired to the spies. This is the unit llr_5_core_loop
   --  constrains; nothing else in this package is under test.

   ------------------------------------------------------------------------
   --  Driving a run
   ------------------------------------------------------------------------

   procedure Run (Iterations : Positive; Inputs : Sensor_Script := All_Quiet)
   is
   begin
      Logged := 0;
      Reads := 0;
      Done := 0;
      Wanted := Iterations;
      Script := Inputs;
      Escaped := False;

      Drive;

      --  Unreachable: Drive is No_Return and only ever leaves by Escape.

   exception
      when Escape =>
         Escaped := True;
   end Run;

   function Count return Natural is (Logged);

   function Left_By_Escape return Boolean is (Escaped);

   function Nth (N : Event_Index) return Event is (Trace (N));

end Reqs_Support.Loop_Spy;
