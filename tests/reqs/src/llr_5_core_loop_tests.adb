with AUnit.Assertions; use AUnit.Assertions;

with Reqs_Support.Loop_Spy;
with States;

package body Llr_5_Core_Loop_Tests is

   use all type States.Fault_Detection;
   use all type States.Pedestrian_Head;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;
   use all type Reqs_Support.Loop_Spy.Loop_Stage;

   use type States.Duration_Ms;
   use type States.Left_Faces;
   use type States.Pedestrian_Heads;
   use type States.Request_Indicators;
   use type States.Through_Faces;

   package Spy renames Reqs_Support.Loop_Spy;

   ------------------------------------------------------------------------
   --  Expected displays, transcribed from the requirements
   ------------------------------------------------------------------------

   --  The loop's only observable output is what it hands Write_Display, so
   --  each statement below is checked against a whole Display_State. The three
   --  the tests need are assembled here from the statements that give them:
   --  the vehicle faces from the Moore rows already transcribed into
   --  Reqs_Support.Expected_Faces, the pedestrian half from
   --  llr_4_controller_3_pedestrian, and the FAULT projection from
   --  llr_4_controller.6-.8.

   Idle_Heads : constant States.Pedestrian_Heads := (others => Dont_Walk);
   --  Every crosswalk idle: llr_4_controller_3_pedestrian.1 gives DONT_WALK
   --  for NO_PEDESTRIAN_REQUEST, which llr_4_controller.5 makes the power-on
   --  pedestrian state.

   Idle_Requests : constant States.Request_Indicators :=
     (others => No_Request);
   --  llr_4_controller_3_pedestrian.6: NO_REQUEST for NO_PEDESTRIAN_REQUEST.

   Power_On_Display : constant States.Display_State :=
     (Through  => Reqs_Support.Expected_Faces (EW_Barrier_Allred).Through,
      Left     => Reqs_Support.Expected_Faces (EW_Barrier_Allred).Left,
      Heads    => Idle_Heads,
      Requests => Idle_Requests);
   --  What the power-on state projects (llr_4_controller.9-.11): the vehicle
   --  faces of EW_BARRIER_ALLRED, the state llr_4_controller.3 requires
   --  Initialize to set -- every face RED
   --  (llr_4_controller_1_vehicle.24) -- over the idle pedestrian half.

   Both_Through_Display : constant States.Display_State :=
     (Through  => Reqs_Support.Expected_Faces (NS_Both_Through).Through,
      Left     => Reqs_Support.Expected_Faces (NS_Both_Through).Left,
      Heads    => Idle_Heads,
      Requests => Idle_Requests);
   --  What the state after the barrier projects. With no north left-turn
   --  demand, llr_4_controller_1_vehicle.26 sends EW_BARRIER_ALLRED to
   --  NS_BOTH_THROUGH when T_BARRIER elapses, whose row (.6) is the N and S
   --  throughs GREEN. Only the *target* of .26 is used here, not its dwell,
   --  which is .26's own routine to assert.

   Fault_Display : constant States.Display_State :=
     (Through  => (others => Flashing_Red),
      Left     => (others => Flashing_Red),
      Heads    => (others => None),
      Requests => (others => No_Request));
   --  The FAULT projection: llr_4_controller.6 (FLASHING_RED on every through
   --  and left face), .7 (NONE for every head), .8 (NO_REQUEST for every
   --  indicator).

   ------------------------------------------------------------------------
   --  Trace helpers
   ------------------------------------------------------------------------

   procedure Check_Display
     (Actual : States.Display_State;
      Expect : States.Display_State;
      Where  : String);
   --  Assert that every signal of Actual equals Expect, naming the differing
   --  signal and the place in the trace (Where) on failure. Compared signal by
   --  signal rather than as whole records so a failure says which lamp is
   --  wrong.

   function Write_Of (Iteration : Positive) return Spy.Event;
   --  The Write_Display event of the given iteration. The trace is three
   --  events per iteration in stage order, so this is arithmetic -- and the
   --  routines that use it assert that stage order first.

   function Same (Left, Right : States.Display_State) return Boolean;
   --  Whether two displays drive every signal alike. Used where a routine has
   --  to *locate* a change in the trace rather than assert a value at a known
   --  place; Check_Display is what reports the mismatch once located.

   procedure Check_Display
     (Actual : States.Display_State;
      Expect : States.Display_State;
      Where  : String) is
   begin
      for A in States.Approach loop
         Assert
           (Actual.Through (A) = Expect.Through (A),
            Where
            & ": through face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Actual.Through (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expect.Through (A)));

         Assert
           (Actual.Left (A) = Expect.Left (A),
            Where
            & ": left face for "
            & States.Approach'Image (A)
            & " was "
            & States.Vehicle_Face'Image (Actual.Left (A))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expect.Left (A)));
      end loop;

      for C in States.Crosswalk loop
         Assert
           (Actual.Heads (C) = Expect.Heads (C),
            Where
            & ": pedestrian head for "
            & States.Crosswalk'Image (C)
            & " was "
            & States.Pedestrian_Head'Image (Actual.Heads (C))
            & " but the requirement gives "
            & States.Pedestrian_Head'Image (Expect.Heads (C)));

         Assert
           (Actual.Requests (C) = Expect.Requests (C),
            Where
            & ": request indicator for "
            & States.Crosswalk'Image (C)
            & " was "
            & States.Request_Indicator'Image (Actual.Requests (C))
            & " but the requirement gives "
            & States.Request_Indicator'Image (Expect.Requests (C)));
      end loop;
   end Check_Display;

   function Write_Of (Iteration : Positive) return Spy.Event
   is (Spy.Nth (Spy.Prologue_Events + 3 * Iteration - 1));

   function Same (Left, Right : States.Display_State) return Boolean
   is (Left.Through = Right.Through
       and then Left.Left = Right.Left
       and then Left.Heads = Right.Heads
       and then Left.Requests = Right.Requests);

   ------------------------------------------------------------------------
   --  Statement .1 -- Initialize, once, before the first iteration
   ------------------------------------------------------------------------

   procedure Test_01_Initialize_Once_Before_First_Iteration (T : in out Test)
   is
      --@covers llr_5_core_loop.1

      pragma Unreferenced (T);

      Barrier_Steps : constant Positive :=
        Positive (States.T_Barrier / States.T_Sample);
      --  How many iterations the power-on dwell spans. T_BARRIER is an
      --  integral multiple of T_SAMPLE (llr_1_states.31), so this is exact.

      Window : constant Positive := Barrier_Steps + 1;
      --  One iteration more than the dwell, so the barrier's exit is inside
      --  the window whichever step of the iteration emits it -- see below.

      Changed_At : Natural := 0;
   begin

      --  Controller.Initialize is not a formal of the generic, so no spy can
      --  count its calls; the statement is checked through the two things that
      --  are observable, which together admit only one call and only before
      --  the first iteration:
      --
      --  * BEFORE THE FIRST ITERATION. The outputs written by iteration 1 are
      --    those of the power-on state llr_4_controller.2-.5 requires. An
      --    uninitialized state would have been stepped and projected instead,
      --    and the power-on state is not the default value of anything.
      --
      --  * EXACTLY ONCE. Initialize sets Veh_Timer to T_BARRIER
      --    (llr_4_controller.3) and each iteration accounts for one T_SAMPLE
      --    of that dwell (llr_4_controller.17), so within T_BARRIER the
      --    barrier's exit fires (llr_4_controller.18) and the faces change to
      --    the row of the state .26 sends the barrier to. A second Initialize
      --    on any iteration would reload the dwell, and the exit would never
      --    be reached at all -- so observing it refutes re-initialization.
      --
      --  What this routine deliberately does NOT pin down is *which* iteration
      --  carries the change: that is the phase of Step's emit relative to its
      --  advance, which llr_4_controller.16 governs and its own test checks. A
      --  routine here that fixed the index would fail for a .16 phase defect
      --  as well, and two requirements failing for one cause is exactly what
      --  one-routine-per-statement is meant to prevent. So the window is one
      --  iteration wider than the dwell and the change is located, not
      --  predicted -- while everything before it is still required to be the
      --  power-on display, which is what carries the once-only claim.

      Spy.Run (Iterations => Window);

      Assert
        (Spy.Count = Spy.Prologue_Events + 3 * Window,
         "the spy must record the prologue's"
         & Integer'Image (Spy.Prologue_Events)
         & " events and three more for each of the"
         & Integer'Image (Window)
         & " iterations, but recorded"
         & Integer'Image (Spy.Count));

      Check_Display (Write_Of (1).Outputs, Power_On_Display, "iteration 1");

      for K in 1 .. Window loop
         if Changed_At = 0
           and then not Same (Write_Of (K).Outputs, Power_On_Display)
         then
            Changed_At := K;
         end if;
      end loop;

      Assert
        (Changed_At /= 0,
         "the display never left the power-on outputs in"
         & Integer'Image (Window)
         & " iterations, so the power-on dwell was never allowed to elapse --"
         & " which is what re-initializing on every iteration would do");

      --  The change, wherever it fell, is the barrier's exit and nothing else:
      --  the display held the power-on outputs up to it, and the row it
      --  changed to is the one llr_4_controller_1_vehicle.26 gives for a
      --  barrier exit with no north left-turn demand.

      for K in 1 .. Changed_At - 1 loop
         Check_Display
           (Write_Of (K).Outputs,
            Power_On_Display,
            "iteration" & Integer'Image (K) & ", before the barrier elapsed");
      end loop;

      Check_Display
        (Write_Of (Changed_At).Outputs,
         Both_Through_Display,
         "iteration" & Integer'Image (Changed_At) & ", the barrier's exit");

   end Test_01_Initialize_Once_Before_First_Iteration;

   ------------------------------------------------------------------------
   --  Statement .2 -- the four stages, in order, every iteration
   ------------------------------------------------------------------------

   procedure Test_02_Iteration_Runs_The_Four_Stages_In_Order (T : in out Test)
   is
      --@covers llr_5_core_loop.2

      pragma Unreferenced (T);

      Iterations : constant := 3;

      Inputs : Spy.Sensor_Script := Spy.All_Quiet;
   begin

      --  Three of the four stages cross the generic's boundary and are
      --  recorded directly, so their order and the delay's argument are read
      --  off the trace. Controller.Step does not: it is called through the
      --  loop's own closure. What places it *between* the read and the write
      --  of the same iteration is a distinguishable input -- the fault line,
      --  which llr_4_controller.13 turns into a mode change and .6-.8 into an
      --  unmistakable projection. Asserting it on the fault line rather than
      --  on some interior state also keeps the check independent of every
      --  sub-machine.

      Inputs (2).Fault := Asserted;

      Spy.Run (Iterations => Iterations, Inputs => Inputs);

      Assert
        (Spy.Count = Spy.Prologue_Events + 3 * Iterations,
         "the spy must record three events per iteration after the"
         & " prologue's"
         & Integer'Image (Spy.Prologue_Events)
         & ", but recorded"
         & Integer'Image (Spy.Count));

      for K in 1 .. Iterations loop
         declare
            Base : constant Positive := Spy.Prologue_Events + 3 * K;

            Read  : constant Spy.Event := Spy.Nth (Base - 2);
            Write : constant Spy.Event := Spy.Nth (Base - 1);
            Sleep : constant Spy.Event := Spy.Nth (Base);

            Where : constant String := "iteration" & Integer'Image (K);
         begin
            Assert
              (Read.Stage = Read_Sources_Stage,
               Where
               & " must begin with Read_Sources, but began with "
               & Spy.Loop_Stage'Image (Read.Stage));

            Assert
              (Write.Stage = Write_Display_Stage,
               Where
               & " must write the display after reading the sources, but the"
               & " second call was "
               & Spy.Loop_Stage'Image (Write.Stage));

            Assert
              (Sleep.Stage = Delay_For_Stage,
               Where
               & " must delay after writing the display, but the third call"
               & " was "
               & Spy.Loop_Stage'Image (Sleep.Stage));

            Assert
              (Sleep.Ms = States.T_Sample,
               Where
               & " must delay exactly T_SAMPLE, but delayed"
               & States.Duration_Ms'Image (Sleep.Ms));
         end;
      end loop;

      --  Iteration 1 read the quiet snapshot and wrote the power-on outputs;
      --  iteration 2 read the fault and wrote the fault outputs *in that same
      --  iteration*. So the step ran on the snapshot the read had just
      --  delivered, and the write carried what the step produced.

      Check_Display
        (Write_Of (1).Outputs, Power_On_Display, "iteration 1, quiet inputs");

      Check_Display
        (Write_Of (2).Outputs, Fault_Display, "iteration 2, fault asserted");

   end Test_02_Iteration_Runs_The_Four_Stages_In_Order;

   ------------------------------------------------------------------------
   --  Statement .3 -- No_Return, with no termination path
   ------------------------------------------------------------------------

   procedure Test_03_Loop_Never_Returns_To_Its_Caller (T : in out Test) is
      --@covers llr_5_core_loop.3

      pragma Unreferenced (T);

      Iterations : constant := 4;
   begin

      --  This routine carries one third of .3, and it is worth being precise
      --  about which third.
      --
      --  * `No_Return` ON THE DECLARATION (src/core/state_machine_loop.ads:31)
      --    is a legality rule, not a comment: RM 6.5.1 forbids a return
      --    statement in the body of such a procedure, so no explicit
      --    termination path can even be written. The compiler is the check,
      --    and it runs on every build.
      --
      --  * THE IMPLICIT RETURN at the end of the body is what is left, and
      --    the unit is in SPARK (state_machine_loop_proof instantiates it so
      --    `make prove` actually analyses the generic), so GNATprove
      --    discharges the obligation that the end is unreachable.
      --
      --  * WHAT NEITHER OF THOSE OBSERVES is the loop actually running: both
      --    are satisfied by a body that raises on its first statement. So the
      --    routine drives real iterations and then asks how the loop was
      --    left. Over a bounded run that is necessarily weaker than the
      --    proof -- it shows no termination path was taken in four
      --    iterations, not that none exists -- but it is the half that fails
      --    if the loop stops iterating, which is the failure the requirement
      --    is really about.

      Spy.Run (Iterations => Iterations);

      Assert
        (Spy.Left_By_Escape,
         "State_Machine_Loop must have no termination path, so the only way"
         & " out of it is the exception the spy raises from Delay_For -- but"
         & " the loop returned to its caller instead");

      Assert
        (Spy.Count = Spy.Prologue_Events + 3 * Iterations,
         "the loop must keep iterating until it is escaped, so"
         & Integer'Image (Iterations)
         & " iterations must leave three events each after the prologue's"
         & Integer'Image (Spy.Prologue_Events)
         & ", but the trace holds"
         & Integer'Image (Spy.Count));

   end Test_03_Loop_Never_Returns_To_Its_Caller;

   ------------------------------------------------------------------------
   --  Statement .4 -- the sources are read at least once every T_SAMPLE
   ------------------------------------------------------------------------

   procedure Test_04_Sources_Read_Once_Per_Sampling_Period (T : in out Test) is
      --@covers llr_5_core_loop.4

      pragma Unreferenced (T);

      Iterations : constant := 5;

      Elapsed : States.Duration_Ms := 0;
      --  Logical time accumulated since the previous read -- the sum of the
      --  delays the loop asked for, which is the only time the loop spends.

      Reads : Natural := 0;
   begin

      --  The bound is on logical time between reads, so it is checked by
      --  walking the trace and summing the delays: the loop's only source of
      --  elapsed time is what it hands Delay_For. Statement .4 is a bound, not
      --  an equality, so the assertion is `<=` -- .2 is what pins the cadence
      --  to exactly one T_SAMPLE per iteration.
      --
      --  Several iterations are run rather than one because the claim is about
      --  every gap: a loop that read once and then slept forever would satisfy
      --  the first gap.

      Spy.Run (Iterations => Iterations);

      for N in 1 .. Spy.Count loop
         declare
            E : constant Spy.Event := Spy.Nth (N);
         begin
            case E.Stage is
               when Read_Sources_Stage  =>
                  Reads := Reads + 1;

                  Assert
                    (Elapsed <= States.T_Sample,
                     "read"
                     & Integer'Image (Reads)
                     & " came"
                     & States.Duration_Ms'Image (Elapsed)
                     & " ms of logical time after the previous one, which"
                     & " exceeds T_SAMPLE");

                  Elapsed := 0;

               when Delay_For_Stage     =>
                  Elapsed := Elapsed + E.Ms;

               when Write_Display_Stage =>
                  null;
            end case;
         end;
      end loop;

      Assert
        (Reads = Iterations,
         "every iteration must read the sources, so"
         & Integer'Image (Iterations)
         & " iterations must produce that many reads, but produced"
         & Integer'Image (Reads));

      --  And the window does not end with the cadence lapsing: the delay after
      --  the last read is itself within the bound.

      Assert
        (Elapsed <= States.T_Sample,
         "the run ended with"
         & States.Duration_Ms'Image (Elapsed)
         & " ms of logical time since the last read, which exceeds T_SAMPLE");

   end Test_04_Sources_Read_Once_Per_Sampling_Period;

   ------------------------------------------------------------------------
   --  Statement .5 -- the startup prologue: publish, then hold
   ------------------------------------------------------------------------

   procedure Test_05_Startup_Publishes_And_Holds_Before_First_Step
     (T : in out Test)
   is
      --@covers llr_5_core_loop.5

      pragma Unreferenced (T);

      Publish : Spy.Event;
      Hold    : Spy.Event;
   begin

      --  The prologue is what the trace opens with, so it is read off the head
      --  of the trace: a Write_Display, a Delay_For of one sampling period,
      --  and only then iteration one's Read_Sources. Controller.Initialize
      --  leaves no event of its own (statement .1's routine says why), so what
      --  shows it ran before the publication is that the frame published is
      --  the power-on one.
      --
      --  The hold is the operative half of the statement and the assertion on
      --  Ms is what carries it: a publication with no delay after it leaves
      --  the boot state displayed for one sampling period less than its dwell,
      --  which is what the displayed-duration test in tests/system observes at
      --  the whole-run level.

      Spy.Run (Iterations => 1);

      Assert
        (Spy.Count = Spy.Prologue_Events + 3,
         "one iteration after the prologue must leave"
         & Integer'Image (Spy.Prologue_Events + 3)
         & " events, but the trace holds"
         & Integer'Image (Spy.Count));

      Publish := Spy.Nth (1);
      Hold := Spy.Nth (2);

      Assert
        (Publish.Stage = Write_Display_Stage,
         "the loop must publish before its first iteration, but the trace"
         & " opens with "
         & Spy.Loop_Stage'Image (Publish.Stage));

      Check_Display (Publish.Outputs, Power_On_Display, "the prologue");

      Assert
        (Hold.Stage = Delay_For_Stage,
         "the published frame must be held, but the publication was followed"
         & " by "
         & Spy.Loop_Stage'Image (Hold.Stage));

      Assert
        (Hold.Ms = States.T_Sample,
         "the hold must be exactly T_SAMPLE, but was"
         & States.Duration_Ms'Image (Hold.Ms)
         & " ms");

      Assert
        (Spy.Nth (Spy.Prologue_Events + 1).Stage = Read_Sources_Stage,
         "the first iteration must begin only after the hold, but the event"
         & " following it was "
         & Spy.Loop_Stage'Image (Spy.Nth (Spy.Prologue_Events + 1).Stage));

   end Test_05_Startup_Publishes_And_Holds_Before_First_Step;

end Llr_5_Core_Loop_Tests;
