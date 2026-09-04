with AUnit.Assertions; use AUnit.Assertions;

with Buses;
with Reqs_Support;
with States;

package body Llr_2_Buses_Tests is

   use all type States.Fault_Detection;
   use all type States.Left_Turn_Detector;
   use all type States.Pedestrian_Button;
   use all type States.Pedestrian_Head;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;

   ------------------------------------------------------------------------
   --  The spies and the two bus instances under test
   ------------------------------------------------------------------------

   --  The recorders and their state are body-level, and each instance is a
   --  single library-level one, because a generic formal procedure has a fixed
   --  profile: there is nowhere in a bus's boundary to thread a context
   --  through. Reset discards the previous routine's recording, so no routine
   --  inherits another's calls -- the same arrangement as
   --  Reqs_Support.Loop_Spy, kept local here because nothing outside these
   --  four statements needs it.

   Producer_Calls : Natural := 0;
   --  How many times the source bus has invoked its producer since Reset.

   Supplied : States.Sensors_State := Reqs_Support.Quiet;
   --  The snapshot the spy producer writes when it is next invoked.

   procedure Spy_Producer (Value : out States.Sensors_State);

   procedure Spy_Producer (Value : out States.Sensors_State) is
   begin
      Producer_Calls := Producer_Calls + 1;
      Value := Supplied;
   end Spy_Producer;

   package Source_Under_Test is new
     Buses.Source_Bus (Bus_Write => Spy_Producer);
   --  The source bus, wired to the spy producer: the unit llr_2_buses.1-.3
   --  constrains.

   Idle_Display : constant States.Display_State :=
     (Through  => (others => Red),
      Left     => (others => Red),
      Heads    => (others => Dont_Walk),
      Requests => (others => No_Request));
   --  Filler for the "nothing delivered yet" record below; never compared
   --  against anything.

   type Delivery is record
      Arrived : Boolean;
      Value   : States.Display_State;
   end record;
   --  What the display bus has handed its consumer, if anything. Every
   --  Display_State is a value the core may legitimately write, so no reserved
   --  display value could stand for "not delivered": the flag is what makes
   --  unset distinguishable.
   --  @field Arrived Whether the consumer has been called since Reset
   --  @field Value The value it was given on its last call

   Nothing_Delivered : constant Delivery :=
     (Arrived => False, Value => Idle_Display);

   Delivered      : Delivery := Nothing_Delivered;
   Consumer_Calls : Natural := 0;

   procedure Spy_Consumer (S : States.Display_State);

   procedure Spy_Consumer (S : States.Display_State) is
   begin
      Consumer_Calls := Consumer_Calls + 1;
      Delivered := (Arrived => True, Value => S);
   end Spy_Consumer;

   package Display_Under_Test is new
     Buses.Display_Bus (Bus_Read => Spy_Consumer);
   --  The display bus, wired to the spy consumer: the unit llr_2_buses.4
   --  constrains.

   ------------------------------------------------------------------------
   --  Helpers
   ------------------------------------------------------------------------

   procedure Reset;
   --  Discard the previous routine's recording.

   function Other
     (L : States.Pedestrian_Button) return States.Pedestrian_Button
   is (if L = Pressed then Released else Pressed);
   --  The other of the two levels llr_1_states.5 gives a button.

   function Other
     (L : States.Left_Turn_Detector) return States.Left_Turn_Detector
   is (if L = Vehicle_Present then No_Vehicle else Vehicle_Present);
   --  The other of the two levels llr_1_states.6 gives a detector.

   function Only_Button
     (C : States.Crosswalk; L : States.Pedestrian_Button)
      return States.Sensors_State;
   --  The snapshot in which crosswalk C's button is at level L and the other
   --  three buttons are at the other level. Setting the siblings *against* the
   --  signal under test is what makes a bus that reported some other
   --  crosswalk's button fail: over an all-idle base the RELEASED level would
   --  agree with every wrong index.

   function Only_Detector
     (A : States.Approach; L : States.Left_Turn_Detector)
      return States.Sensors_State;
   --  The same construction for approach A's left-turn detector.

   function Fault_Line
     (F : States.Fault_Detection) return States.Sensors_State;
   --  The idle snapshot with the fault line at level F. The fault line is
   --  intersection-wide (llr_1_states.17), so there is no index to confuse and
   --  its two levels over the idle base are the whole enumeration.

   function Read_Supplying
     (Supply : States.Sensors_State) return States.Sensors_State;
   --  One Bus_Read with the spy producer set to supply Supply.

   procedure Check_Snapshot
     (Actual : States.Sensors_State;
      Expect : States.Sensors_State;
      Where  : String);
   --  Assert that every input signal of Actual carries the level of Expect,
   --  naming the signal and the place (Where) on failure. Compared signal by
   --  signal rather than as whole records so a failure says which input is
   --  wrong.

   procedure Check_Display
     (Actual : States.Display_State;
      Expect : States.Display_State;
      Where  : String);
   --  The same, for the value the display bus delivered.

   procedure Reset is
   begin
      Producer_Calls := 0;
      Supplied := Reqs_Support.Quiet;
      Delivered := Nothing_Delivered;
      Consumer_Calls := 0;
   end Reset;

   function Only_Button
     (C : States.Crosswalk; L : States.Pedestrian_Button)
      return States.Sensors_State
   is
      S : States.Sensors_State :=
        (Buttons    => (others => Other (L)),
         Left_Turns => (others => No_Vehicle),
         Fault      => Not_Asserted);
   begin
      S.Buttons (C) := L;
      return S;
   end Only_Button;

   function Only_Detector
     (A : States.Approach; L : States.Left_Turn_Detector)
      return States.Sensors_State
   is
      S : States.Sensors_State :=
        (Buttons    => (others => Released),
         Left_Turns => (others => Other (L)),
         Fault      => Not_Asserted);
   begin
      S.Left_Turns (A) := L;
      return S;
   end Only_Detector;

   function Fault_Line (F : States.Fault_Detection) return States.Sensors_State
   is
      S : States.Sensors_State := Reqs_Support.Quiet;
   begin
      S.Fault := F;
      return S;
   end Fault_Line;

   function Read_Supplying
     (Supply : States.Sensors_State) return States.Sensors_State
   is
      Got : States.Sensors_State;
   begin
      Supplied := Supply;
      Source_Under_Test.Bus_Read (Got);
      return Got;
   end Read_Supplying;

   procedure Check_Snapshot
     (Actual : States.Sensors_State;
      Expect : States.Sensors_State;
      Where  : String) is
   begin
      for C in States.Crosswalk loop
         Assert
           (Actual.Buttons (C) = Expect.Buttons (C),
            Where
            & ": the button of "
            & States.Crosswalk'Image (C)
            & " was reported "
            & States.Pedestrian_Button'Image (Actual.Buttons (C))
            & " but the producer supplied "
            & States.Pedestrian_Button'Image (Expect.Buttons (C)));
      end loop;

      for A in States.Approach loop
         Assert
           (Actual.Left_Turns (A) = Expect.Left_Turns (A),
            Where
            & ": the left-turn detector of "
            & States.Approach'Image (A)
            & " was reported "
            & States.Left_Turn_Detector'Image (Actual.Left_Turns (A))
            & " but the producer supplied "
            & States.Left_Turn_Detector'Image (Expect.Left_Turns (A)));
      end loop;

      Assert
        (Actual.Fault = Expect.Fault,
         Where
         & ": the fault line was reported "
         & States.Fault_Detection'Image (Actual.Fault)
         & " but the producer supplied "
         & States.Fault_Detection'Image (Expect.Fault));
   end Check_Snapshot;

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
            & " arrived as "
            & States.Vehicle_Face'Image (Actual.Through (A))
            & " but the value written was "
            & States.Vehicle_Face'Image (Expect.Through (A)));

         Assert
           (Actual.Left (A) = Expect.Left (A),
            Where
            & ": left face for "
            & States.Approach'Image (A)
            & " arrived as "
            & States.Vehicle_Face'Image (Actual.Left (A))
            & " but the value written was "
            & States.Vehicle_Face'Image (Expect.Left (A)));
      end loop;

      for C in States.Crosswalk loop
         Assert
           (Actual.Heads (C) = Expect.Heads (C),
            Where
            & ": pedestrian head for "
            & States.Crosswalk'Image (C)
            & " arrived as "
            & States.Pedestrian_Head'Image (Actual.Heads (C))
            & " but the value written was "
            & States.Pedestrian_Head'Image (Expect.Heads (C)));

         Assert
           (Actual.Requests (C) = Expect.Requests (C),
            Where
            & ": request indicator for "
            & States.Crosswalk'Image (C)
            & " arrived as "
            & States.Request_Indicator'Image (Actual.Requests (C))
            & " but the value written was "
            & States.Request_Indicator'Image (Expect.Requests (C)));
      end loop;
   end Check_Display;

   ------------------------------------------------------------------------
   --  Shared snapshots
   ------------------------------------------------------------------------

   Every_Signal_Active : constant States.Sensors_State :=
     (Buttons    => (others => Pressed),
      Left_Turns => (others => Vehicle_Present),
      Fault      => Asserted);
   --  Every one of the nine input signals llr_1_states.17 aggregates at the
   --  level away from idle: four buttons PRESSED, four detectors
   --  VEHICLE_PRESENT, the fault line ASSERTED.

   ------------------------------------------------------------------------
   --  Statement .1 -- the whole snapshot, obtained by invoking the producer
   ------------------------------------------------------------------------

   procedure Test_01_Bus_Read_Obtains_Whole_Snapshot_From_Producer
     (T : in out Test)
   is
      --@covers llr_2_buses.1

      pragma Unreferenced (T);

      Got : States.Sensors_State;
   begin

      --  Two claims, both observable at the boundary the bus is generic over:
      --
      --  * BY INVOKING ITS PRODUCER. The spy producer is the only thing on the
      --    far side of the bus, so a Bus_Read that reported anything without
      --    calling it leaves the call count at zero.
      --
      --  * THE WHOLE SNAPSHOT, AT ONCE. Every signal is supplied away from
      --    idle, so a bus that took up only part of what the producer wrote
      --    reports an idle signal somewhere. Which level belongs to which
      --    signal is statement .2's claim; this routine only requires that
      --    none of the nine is left behind.
      --
      --  The count is then checked again after a second read: the statement is
      --  "when Bus_Read is called", so the producer is invoked once per call,
      --  not once ever.

      Reset;

      Got := Read_Supplying (Every_Signal_Active);

      Assert
        (Producer_Calls = 1,
         "one Bus_Read must invoke its producer exactly once, but invoked it"
         & Integer'Image (Producer_Calls)
         & " times");

      Check_Snapshot (Got, Every_Signal_Active, "the first Bus_Read");

      Got := Read_Supplying (Every_Signal_Active);

      Assert
        (Producer_Calls = 2,
         "each Bus_Read must invoke the producer, so two reads must invoke it"
         & " twice, but invoked it"
         & Integer'Image (Producer_Calls)
         & " times");

      Check_Snapshot (Got, Every_Signal_Active, "the second Bus_Read");

   end Test_01_Bus_Read_Obtains_Whole_Snapshot_From_Producer;

   ------------------------------------------------------------------------
   --  Statement .2 -- each signal at the level supplied during that call
   ------------------------------------------------------------------------

   procedure Test_02_Each_Signal_Reported_At_The_Level_Supplied
     (T : in out Test)
   is
      --@covers llr_2_buses.2

      pragma Unreferenced (T);
   begin

      --  The statement names every input signal and both levels of each: a
      --  button as PRESSED or RELEASED, a detector as VEHICLE_PRESENT or
      --  NO_VEHICLE, the fault line as ASSERTED or NOT_ASSERTED. The domain is
      --  therefore 4 buttons x 2 levels, 4 detectors x 2 levels and 2 fault
      --  levels, and it is enumerated rather than sampled -- the loops range
      --  over the alphabets themselves, so a literal added to any of the three
      --  enumerations widens the sweep with no edit here.
      --
      --  Each case supplies the signal under test at one level with its
      --  siblings at the other, and the whole reported snapshot is compared
      --  against what was supplied: that requires the level to reach the right
      --  signal, and not to leak into any other.

      Reset;

      for C in States.Crosswalk loop
         for L in States.Pedestrian_Button loop
            Check_Snapshot
              (Read_Supplying (Only_Button (C, L)),
               Only_Button (C, L),
               "with the button of "
               & States.Crosswalk'Image (C)
               & " supplied as "
               & States.Pedestrian_Button'Image (L));
         end loop;
      end loop;

      for A in States.Approach loop
         for L in States.Left_Turn_Detector loop
            Check_Snapshot
              (Read_Supplying (Only_Detector (A, L)),
               Only_Detector (A, L),
               "with the left-turn detector of "
               & States.Approach'Image (A)
               & " supplied as "
               & States.Left_Turn_Detector'Image (L));
         end loop;
      end loop;

      for F in States.Fault_Detection loop
         Check_Snapshot
           (Read_Supplying (Fault_Line (F)),
            Fault_Line (F),
            "with the fault line supplied as "
            & States.Fault_Detection'Image (F));
      end loop;

   end Test_02_Each_Signal_Reported_At_The_Level_Supplied;

   ------------------------------------------------------------------------
   --  Statement .3 -- nothing retained from one call to the next
   ------------------------------------------------------------------------

   procedure Test_03_Bus_Retains_No_Level_Between_Reads (T : in out Test) is
      --@covers llr_2_buses.3

      pragma Unreferenced (T);

      Mixed : constant States.Sensors_State :=
        (Buttons    =>
           (States.North_Side => Pressed,
            States.South_Side => Released,
            States.East_Side  => Pressed,
            States.West_Side  => Released),
         Left_Turns =>
           (States.North => No_Vehicle,
            States.South => Vehicle_Present,
            States.East  => No_Vehicle,
            States.West  => Vehicle_Present),
         Fault      => Asserted);
      --  A third pattern, mixing both levels within each array, so a bus that
      --  reported the previous read's levels again fails on some signal.
   begin

      --  The statement is about a sequence of reads, so it takes a sequence to
      --  refute. Three reads, each supplying different levels:
      --
      --  1. every signal active -- the levels a bus with a latch would keep;
      --  2. every signal idle -- so every signal that was PRESSED,
      --     VEHICLE_PRESENT or ASSERTED on read 1 must now report RELEASED,
      --     NO_VEHICLE or NOT_ASSERTED. This is the case a retaining bus
      --     fails, and it is what "reports only the levels sampled during it"
      --     comes to;
      --  3. a mixed pattern -- so a bus that reported its first sample for
      --     ever, or that alternated, fails too.

      Reset;

      Check_Snapshot
        (Read_Supplying (Every_Signal_Active),
         Every_Signal_Active,
         "the first read, every signal active");

      Check_Snapshot
        (Read_Supplying (Reqs_Support.Quiet),
         Reqs_Support.Quiet,
         "the second read, every signal released after being active");

      Check_Snapshot
        (Read_Supplying (Mixed), Mixed, "the third read, a mixed pattern");

   end Test_03_Bus_Retains_No_Level_Between_Reads;

   ------------------------------------------------------------------------
   --  Statement .4 -- delivered to the consumer before returning
   ------------------------------------------------------------------------

   procedure Test_04_Bus_Write_Delivers_Before_Returning (T : in out Test) is
      --@covers llr_2_buses.4

      pragma Unreferenced (T);

      Written : constant States.Display_State :=
        (Through  =>
           (States.North => Green,
            States.South => Yellow,
            States.East  => Red,
            States.West  => Flashing_Red),
         Left     =>
           (States.North => Yellow,
            States.South => Red,
            States.East  => Flashing_Red,
            States.West  => Green),
         Heads    =>
           (States.North_Side => Walk,
            States.South_Side => Flash_Dont_Walk,
            States.East_Side  => Dont_Walk,
            States.West_Side  => None),
         Requests =>
           (States.North_Side => Request_Pending,
            States.South_Side => No_Request,
            States.East_Side  => Request_Pending,
            States.West_Side  => No_Request));
      --  A value carrying every literal of all three output alphabets
      --  (llr_1_states.1-.3), so a consumer handed a default or a stale record
      --  rather than this one fails on some signal.
   begin

      --  "Before returning" is a claim about the ordering of two events, and
      --  the assertion is placed between them: the spy consumer records that
      --  it was called, and the check runs after Bus_Write has returned. If
      --  the delivery were deferred to any later point, Arrived would still be
      --  False here -- and Arrived, rather than a reserved display value, is
      --  what carries "not delivered", because every Display_State is a value
      --  the core may legitimately write.

      Reset;

      Assert
        (not Delivered.Arrived,
         "the consumer must not have been called before Bus_Write is,"
         & " or the observation below proves nothing");

      Display_Under_Test.Bus_Write (Written);

      Assert
        (Delivered.Arrived,
         "Bus_Write returned before its consumer had been called, so the"
         & " Display_State was not delivered before returning");

      Assert
        (Consumer_Calls = 1,
         "one Bus_Write must deliver to the consumer exactly once, but called"
         & " it"
         & Integer'Image (Consumer_Calls)
         & " times");

      Check_Display (Delivered.Value, Written, "the delivered display");

   end Test_04_Bus_Write_Delivers_Before_Returning;

end Llr_2_Buses_Tests;
