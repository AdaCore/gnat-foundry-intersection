--  The core-loop spy (llr_5_core_loop).
--
--  State_Machine_Loop is No_Return: it has no exit, so a test cannot simply
--  call it and then inspect what it did. What makes it observable anyway is
--  that it is generic over exactly the three procedures that move data and
--  time across its boundary -- so a test instantiates it against spies that
--  record every call and, once the requested number of iterations has been
--  seen, leave the loop the only way a No_Return procedure can be left: by
--  propagating an exception.
--
--  The escape is raised from the spy Delay_For, the last of the four stages
--  (llr_5_core_loop.2), so an escaped run ends on an iteration boundary with
--  every stage of the final iteration already recorded, rather than mid-cycle.
--
--  What the run leaves behind is the loop's observable trace: which stage ran,
--  in what order, the snapshot each Read_Sources delivered, the outputs each
--  Write_Display received, and the period each Delay_For was asked to sleep.
--  Every claim llr_5_core_loop makes -- the four-stage order (.2), the
--  sampling cadence (.4), and the once-only Initialize before the first
--  iteration (.1) -- is a property of that trace, so the whole file is tested
--  through this one instrument.
--
--  Controller.Initialize is *not* a formal of the generic, so .1 cannot be
--  checked by counting calls to it. It is checked through its consequences
--  instead; Llr_5_Core_Loop_Tests carries that argument.

with States;

package Reqs_Support.Loop_Spy is

   Max_Events : constant := 256;
   --  The trace is a fixed array rather than a container, so a run's length is
   --  bounded and Run's precondition can say so. Three events per iteration.

   subtype Event_Index is Positive range 1 .. Max_Events;

   type Loop_Stage is
     (Read_Sources_Stage, Write_Display_Stage, Delay_For_Stage);
   --  The three stages of an iteration that cross the generic's boundary and
   --  are therefore observable. Controller.Step, the second of the four stages
   --  llr_5_core_loop.2 names, is called directly by the loop and leaves no
   --  event of its own -- what shows it ran, and ran between the read and the
   --  write, is that the outputs of the Write_Display event derive from the
   --  snapshot the Read_Sources event of the same iteration delivered.

   type Event is record
      Stage   : Loop_Stage;
      Sensors : States.Sensors_State;
      Outputs : States.Display_State;
      Ms      : States.Duration_Ms;
   end record;
   --  One recorded call. Only the field belonging to Stage carries meaning:
   --  Sensors for a read, Outputs for a write, Ms for a delay.
   --  @field Stage Which of the three observable stages this call was
   --  @field Sensors The snapshot delivered, on a Read_Sources_Stage event
   --  @field Outputs The outputs received, on a Write_Display_Stage event
   --  @field Ms The period asked for, on a Delay_For_Stage event

   type Sensor_Script is array (Event_Index) of States.Sensors_State;
   --  What Read_Sources delivers on its Nth call. Passed to Run rather than
   --  held as settable state, so no test can inherit another's inputs.

   All_Quiet : constant Sensor_Script := (others => Quiet);
   --  The script that arms nothing: every read delivers the idle snapshot.

   Escape : exception;
   --  Raised by the spy Delay_For to leave the loop. Run absorbs it; it should
   --  never reach a test.

   procedure Run (Iterations : Positive; Inputs : Sensor_Script := All_Quiet)
   with Pre => 3 * Iterations <= Max_Events;
   --  Drive State_Machine_Loop for exactly Iterations complete iterations,
   --  delivering Inputs (N) on the Nth Read_Sources, then escape. Discards the
   --  previous run's trace.
   --  @param Iterations How many complete iterations to observe
   --  @param Inputs The snapshot to deliver on each successive read

   function Count return Natural;
   --  How many events the last Run recorded -- three per iteration.
   --  @return The number of events in the trace

   function Left_By_Escape return Boolean;
   --  Whether the last Run left the loop by propagating Escape rather than by
   --  the loop returning to its caller. State_Machine_Loop is No_Return with
   --  no termination path (llr_5_core_loop.3), so the escape is the only way
   --  out; a run that ended any other way found one the requirement forbids.
   --  Run absorbs the exception, so without this a test cannot tell the two
   --  endings apart.
   --  @return True when the last run ended by propagating Escape

   function Nth (N : Event_Index) return Event
   with Pre => N <= Count;
   --  The Nth event of the last run's trace, in call order.
   --  @param N Which event, counting from the first call of iteration one
   --  @return That event

end Reqs_Support.Loop_Spy;
