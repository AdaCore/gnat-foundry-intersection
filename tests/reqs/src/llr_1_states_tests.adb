with AUnit.Assertions; use AUnit.Assertions;

with States;

package body Llr_1_States_Tests is

   use all type States.Approach;
   use all type States.Crosswalk;
   use all type States.Fault_Detection;
   use all type States.Left_Demand_State;
   use all type States.Left_Turn_Detector;
   use all type States.Mode;
   use all type States.Movement;
   use all type States.Pedestrian_Button;
   use all type States.Pedestrian_Head;
   use all type States.Pedestrian_State;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   ------------------------------------------------------------------------
   --  Shape witnesses (.1-.18)
   ------------------------------------------------------------------------

   --  Statements .1-.18 constrain declarations, not values, so most of the
   --  evidence for them is produced by the compiler rather than at run time.
   --  Each routine declares something written from its requirement's text
   --  which does not compile when the declaration under test has the wrong
   --  shape, and then asserts the one part a declaration cannot state about
   --  itself.
   --
   --  For an alphabet statement the witness is a Boolean table indexed by the
   --  type, with a named association per literal the requirement lists and no
   --  `others` choice. That fails the build two ways: a literal added to the
   --  type leaves the aggregate incomplete, and a literal removed or renamed
   --  leaves a choice naming nothing. What it cannot do is say how many
   --  literals the requirement asked for -- an aggregate is complete for
   --  whatever the type happens to hold -- so each routine tallies the type
   --  by iterating it and asserts that count against the number written in
   --  the requirement. That assertion is the one that fails when the code
   --  and the requirement disagree, which is why it is a run-time check and
   --  not a `pragma Compile_Time_Error`: llr_1_states.12 disagrees today
   --  (#63), and a static witness for it would break the build rather than
   --  report a finding (tests/reqs/README.md rule 2).
   --
   --  The tally is deliberately computed by reading the table rather than
   --  taken from `'Length`: iterating the type is what makes the count the
   --  type's own cardinality instead of a restatement of the aggregate's
   --  bounds.

   procedure Check_Literal_Count
     (Type_Name : String;
      Counted   : Natural;
      Required  : Natural;
      Statement : String);
   --  Assert that a type holds exactly the number of values its statement
   --  names, reporting both counts.

   procedure Check_Literal_Count
     (Type_Name : String;
      Counted   : Natural;
      Required  : Natural;
      Statement : String) is
   begin
      Assert
        (Counted = Required,
         Type_Name
         & " must have exactly"
         & Natural'Image (Required)
         & " literals ("
         & Statement
         & ") but has"
         & Natural'Image (Counted));
   end Check_Literal_Count;

   ------------------------------------------------------------------------
   --  Statement .1 -- the vehicle face alphabet
   ------------------------------------------------------------------------

   procedure Test_01_Vehicle_Face_Has_Exactly_Four_Literals (T : in out Test)
   is
      --@covers llr_1_states.1

      pragma Unreferenced (T);

      type Witness is array (States.Vehicle_Face) of Boolean;

      Named : constant Witness :=
        (Red => True, Yellow => True, Green => True, Flashing_Red => True);

      Counted : Natural := 0;
   begin
      for F in States.Vehicle_Face loop
         if Named (F) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Vehicle_Face", Counted, 4, "llr_1_states.1");
   end Test_01_Vehicle_Face_Has_Exactly_Four_Literals;

   ------------------------------------------------------------------------
   --  Statement .2 -- the pedestrian head alphabet
   ------------------------------------------------------------------------

   procedure Test_02_Pedestrian_Head_Has_Exactly_Four_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.2

      pragma Unreferenced (T);

      type Witness is array (States.Pedestrian_Head) of Boolean;

      Named : constant Witness :=
        (None            => True,
         Walk            => True,
         Flash_Dont_Walk => True,
         Dont_Walk       => True);

      Counted : Natural := 0;
   begin
      for H in States.Pedestrian_Head loop
         if Named (H) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Pedestrian_Head", Counted, 4, "llr_1_states.2");
   end Test_02_Pedestrian_Head_Has_Exactly_Four_Literals;

   ------------------------------------------------------------------------
   --  Statement .3 -- the request indicator alphabet
   ------------------------------------------------------------------------

   procedure Test_03_Request_Indicator_Has_Exactly_Two_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.3

      pragma Unreferenced (T);

      type Witness is array (States.Request_Indicator) of Boolean;

      Named : constant Witness :=
        (No_Request => True, Request_Pending => True);

      Counted : Natural := 0;
   begin
      for R in States.Request_Indicator loop
         if Named (R) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Request_Indicator", Counted, 2, "llr_1_states.3");
   end Test_03_Request_Indicator_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .4 -- the fault-detection alphabet
   ------------------------------------------------------------------------

   procedure Test_04_Fault_Detection_Has_Exactly_Two_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.4

      pragma Unreferenced (T);

      type Witness is array (States.Fault_Detection) of Boolean;

      Named : constant Witness :=
        (Not_Asserted => True, Asserted => True);

      Counted : Natural := 0;
   begin
      for F in States.Fault_Detection loop
         if Named (F) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Fault_Detection", Counted, 2, "llr_1_states.4");
   end Test_04_Fault_Detection_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .5 -- the pedestrian button alphabet
   ------------------------------------------------------------------------

   procedure Test_05_Pedestrian_Button_Has_Exactly_Two_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.5

      pragma Unreferenced (T);

      type Witness is array (States.Pedestrian_Button) of Boolean;

      Named : constant Witness := (Released => True, Pressed => True);

      Counted : Natural := 0;
   begin
      for B in States.Pedestrian_Button loop
         if Named (B) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Pedestrian_Button", Counted, 2, "llr_1_states.5");
   end Test_05_Pedestrian_Button_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .6 -- the left-turn detector alphabet
   ------------------------------------------------------------------------

   procedure Test_06_Left_Turn_Detector_Has_Exactly_Two_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.6

      pragma Unreferenced (T);

      type Witness is array (States.Left_Turn_Detector) of Boolean;

      Named : constant Witness :=
        (No_Vehicle => True, Vehicle_Present => True);

      Counted : Natural := 0;
   begin
      for D in States.Left_Turn_Detector loop
         if Named (D) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Left_Turn_Detector", Counted, 2, "llr_1_states.6");
   end Test_06_Left_Turn_Detector_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .7 -- the approach index
   ------------------------------------------------------------------------

   procedure Test_07_Approach_Has_Exactly_Four_Literals (T : in out Test) is
      --@covers llr_1_states.7

      pragma Unreferenced (T);

      type Witness is array (States.Approach) of Boolean;

      Named : constant Witness :=
        (North => True, South => True, East => True, West => True);

      Counted : Natural := 0;
   begin
      for A in States.Approach loop
         if Named (A) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count ("States.Approach", Counted, 4, "llr_1_states.7");
   end Test_07_Approach_Has_Exactly_Four_Literals;

   ------------------------------------------------------------------------
   --  Statement .8 -- the crosswalk index
   ------------------------------------------------------------------------

   procedure Test_08_Crosswalk_Has_Exactly_Four_Literals (T : in out Test) is
      --@covers llr_1_states.8

      pragma Unreferenced (T);

      type Witness is array (States.Crosswalk) of Boolean;

      Named : constant Witness :=
        (North_Side => True,
         South_Side => True,
         East_Side  => True,
         West_Side  => True);

      Counted : Natural := 0;
   begin
      for C in States.Crosswalk loop
         if Named (C) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count ("States.Crosswalk", Counted, 4, "llr_1_states.8");
   end Test_08_Crosswalk_Has_Exactly_Four_Literals;

   ------------------------------------------------------------------------
   --  Statement .9 -- the operating modes
   ------------------------------------------------------------------------

   procedure Test_09_Mode_Has_Exactly_Two_Literals (T : in out Test) is
      --@covers llr_1_states.9

      pragma Unreferenced (T);

      type Witness is array (States.Mode) of Boolean;

      Named : constant Witness := (Normal_Operation => True, Fault => True);

      Counted : Natural := 0;
   begin
      for M in States.Mode loop
         if Named (M) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count ("States.Mode", Counted, 2, "llr_1_states.9");
   end Test_09_Mode_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .10 -- the left-demand machine states
   ------------------------------------------------------------------------

   procedure Test_10_Left_Demand_State_Has_Exactly_Two_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.10

      pragma Unreferenced (T);

      type Witness is array (States.Left_Demand_State) of Boolean;

      Named : constant Witness :=
        (No_Left_Demand => True, Left_Demand_Pending => True);

      Counted : Natural := 0;
   begin
      for L in States.Left_Demand_State loop
         if Named (L) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Left_Demand_State", Counted, 2, "llr_1_states.10");
   end Test_10_Left_Demand_State_Has_Exactly_Two_Literals;

   ------------------------------------------------------------------------
   --  Statement .11 -- one left-demand state per approach
   ------------------------------------------------------------------------

   procedure Test_11_Left_Demand_Array_Holds_One_State_Per_Approach
     (T : in out Test)
   is
      --@covers llr_1_states.11

      pragma Unreferenced (T);

      Witness : constant States.Left_Demand_Array :=
        (others => No_Left_Demand);

      Reached : Natural := 0;
   begin

      --  "over Approach" and "holding one Left_Demand_State" are both
      --  discharged by the loop below rather than by an assertion: indexing
      --  the witness with an Approach compiles only if Approach is the index
      --  type, and holding a cell in a Left_Demand_State constant compiles
      --  only if that is the component type. What is asserted is the "one
      --  per" -- that sweeping the approaches reaches every cell of the
      --  array and no cell twice, so the array is neither shorter nor longer
      --  than the index.

      for A in States.Approach loop
         declare
            Cell : constant States.Left_Demand_State := Witness (A);
         begin
            Assert
              (Cell = No_Left_Demand,
               "the Left_Demand_Array cell for "
               & States.Approach'Image (A)
               & " did not read back the state written into it");
            Reached := Reached + 1;
         end;
      end loop;

      Assert
        (Reached = Witness'Length,
         "States.Left_Demand_Array must hold exactly one Left_Demand_State"
         & " per approach (llr_1_states.11) but has"
         & Natural'Image (Witness'Length)
         & " cells for"
         & Natural'Image (Reached)
         & " approaches");
   end Test_11_Left_Demand_Array_Holds_One_State_Per_Approach;

   ------------------------------------------------------------------------
   --  Statement .12 -- the vehicle sequencer states
   ------------------------------------------------------------------------

   procedure Test_12_Vehicle_Sequencer_Has_Exactly_Twenty_Two_States
     (T : in out Test)
   is
      --@covers llr_1_states.12

      pragma Unreferenced (T);

      type Witness is array (States.Vehicle_Sequencer_State) of Boolean;

      --  The states .12 names, in the order it names them. Two of the
      --  twenty-two cannot appear: NS_BOTH_THROUGH_HOLD and
      --  EW_BOTH_THROUGH_HOLD are not literals of the type, so naming them
      --  here would not compile. They are marked where they fall, the same
      --  way Reqs_Support.Expected_Faces marks the rows they would carry.
      Named : constant Witness :=
        (N_Lead              => True,
         N_Lead_Yellow       => True,
         N_Lead_Clear        => True,
         NS_Both_Through     => True,
         N_Drop_Yellow       => True,
         N_Drop_Clear        => True,
         S_Lag               => True,
         S_Lag_Yellow        => True,
         --  NS_BOTH_THROUGH_HOLD -- absent from the type (#63)
         NS_Both_Drop_Yellow => True,
         NS_Barrier_Allred   => True,
         E_Lead              => True,
         E_Lead_Yellow       => True,
         E_Lead_Clear        => True,
         EW_Both_Through     => True,
         E_Drop_Yellow       => True,
         E_Drop_Clear        => True,
         W_Lag               => True,
         W_Lag_Yellow        => True,
         --  EW_BOTH_THROUGH_HOLD -- absent from the type (#63)
         EW_Both_Drop_Yellow => True,
         EW_Barrier_Allred   => True);

      Counted : Natural := 0;
   begin

      --  EXPECTED TO FAIL, and the failure is the finding: the requirement
      --  gives the sequencer twenty-two states and the type has twenty. This
      --  is #63 -- the code lags the requirements here deliberately -- and it
      --  is the same divergence that keeps six statements of
      --  llr_4_controller_1_vehicle untestable. The count below is
      --  transcribed from .12 and is left alone until the type carries the
      --  two HOLD states (tests/reqs/README.md rule 2).

      for V in States.Vehicle_Sequencer_State loop
         if Named (V) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Vehicle_Sequencer_State", Counted, 22, "llr_1_states.12");
   end Test_12_Vehicle_Sequencer_Has_Exactly_Twenty_Two_States;

   ------------------------------------------------------------------------
   --  Statement .13 -- the pedestrian machine states
   ------------------------------------------------------------------------

   procedure Test_13_Pedestrian_State_Has_Exactly_Six_Literals
     (T : in out Test)
   is
      --@covers llr_1_states.13

      pragma Unreferenced (T);

      type Witness is array (States.Pedestrian_State) of Boolean;

      Named : constant Witness :=
        (No_Pedestrian_Request      => True,
         Pending_Pedestrian_Request => True,
         Walk_Interval              => True,
         Change_Interval            => True,
         Buffer_Interval            => True,
         Buffer_Interval_Latched    => True);

      Counted : Natural := 0;
   begin
      for P in States.Pedestrian_State loop
         if Named (P) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count
        ("States.Pedestrian_State", Counted, 6, "llr_1_states.13");
   end Test_13_Pedestrian_State_Has_Exactly_Six_Literals;

   ------------------------------------------------------------------------
   --  Statement .14 -- one pedestrian state per crosswalk
   ------------------------------------------------------------------------

   procedure Test_14_Pedestrian_Array_Holds_One_State_Per_Crosswalk
     (T : in out Test)
   is
      --@covers llr_1_states.14

      pragma Unreferenced (T);

      Witness : constant States.Pedestrian_Array :=
        (others => No_Pedestrian_Request);

      Reached : Natural := 0;
   begin

      --  As for .11: the index and component types are discharged by the
      --  loop compiling at all, the "one per crosswalk" by the tally.

      for C in States.Crosswalk loop
         declare
            Cell : constant States.Pedestrian_State := Witness (C);
         begin
            Assert
              (Cell = No_Pedestrian_Request,
               "the Pedestrian_Array cell for "
               & States.Crosswalk'Image (C)
               & " did not read back the state written into it");
            Reached := Reached + 1;
         end;
      end loop;

      Assert
        (Reached = Witness'Length,
         "States.Pedestrian_Array must hold exactly one Pedestrian_State per"
         & " crosswalk (llr_1_states.14) but has"
         & Natural'Image (Witness'Length)
         & " cells for"
         & Natural'Image (Reached)
         & " crosswalks");
   end Test_14_Pedestrian_Array_Holds_One_State_Per_Crosswalk;

   ------------------------------------------------------------------------
   --  Statement .15 -- the serving-pedestrian subtype
   ------------------------------------------------------------------------

   procedure Test_15_Serving_Pedestrian_State_Spans_Walk_To_Buffer_Latched
     (T : in out Test)
   is
      --@covers llr_1_states.15

      pragma Unreferenced (T);

      --  Holding the ends in Pedestrian_State variables is the "of
      --  Pedestrian_State" clause: the values of a subtype of any other type
      --  would not fit here. Contiguity is free -- an Ada subtype of a
      --  discrete type is a range -- so the two ends are what is left.
      --
      --  They are found by walking the subtype rather than read off its
      --  `'First` and `'Last`, for the same reason the alphabet routines
      --  tally by iterating: the ends then come from the values the subtype
      --  actually admits. (It also keeps the assertions live. Read off the
      --  attributes they are static, and the compiler folds them to True
      --  before the test ever runs.)
      --
      --  NOTE: .15 fixes the endpoints, not which literals fall between
      --  them. That follows from the declaration order of Pedestrian_State,
      --  and .13 gives a value set rather than an order, so no statement in
      --  this file requires CHANGE_INTERVAL and BUFFER_INTERVAL to sort
      --  inside the range. Nothing here asserts it either, rather than
      --  asserting an order the requirements do not state.

      First : States.Pedestrian_State := States.Pedestrian_State'Last;
      Last  : States.Pedestrian_State := States.Pedestrian_State'First;

      Inhabited : Boolean := False;
   begin
      for P in States.Serving_Pedestrian_State loop
         if not Inhabited or else P < First then
            First := P;
         end if;

         if not Inhabited or else P > Last then
            Last := P;
         end if;

         Inhabited := True;
      end loop;

      Assert
        (Inhabited,
         "States.Serving_Pedestrian_State must run from WALK_INTERVAL to"
         & " BUFFER_INTERVAL_LATCHED (llr_1_states.15) but is empty");

      Assert
        (First = Walk_Interval,
         "States.Serving_Pedestrian_State must begin at WALK_INTERVAL"
         & " (llr_1_states.15) but begins at "
         & States.Pedestrian_State'Image (First));

      Assert
        (Last = Buffer_Interval_Latched,
         "States.Serving_Pedestrian_State must end at"
         & " BUFFER_INTERVAL_LATCHED (llr_1_states.15) but ends at "
         & States.Pedestrian_State'Image (Last));
   end Test_15_Serving_Pedestrian_State_Spans_Walk_To_Buffer_Latched;

   ------------------------------------------------------------------------
   --  Statement .16 -- the display aggregates every output signal
   ------------------------------------------------------------------------

   procedure Test_16_Display_State_Aggregates_Every_Output_Signal
     (T : in out Test)
   is
      --@covers llr_1_states.16

      pragma Unreferenced (T);

      --  One typed value per component group .16 names. Building them as
      --  named types first, rather than writing the values straight into the
      --  record aggregate, is what ties each component to a type: an
      --  aggregate of the form `(others => Red)` would fit a Vehicle_Face
      --  array over any index at all, whereas a Through_Faces value fits the
      --  Through component only if that is its type.

      Through_Row  : constant States.Through_Faces := (others => Red);
      Left_Row     : constant States.Left_Faces := (others => Red);
      Head_Row     : constant States.Pedestrian_Heads := (others => Dont_Walk);
      Request_Row  : constant States.Request_Indicators :=
        (others => No_Request);

      --  Named associations and no `others` choice, so the record holds
      --  exactly the four groups .16 lists: a component added to
      --  Display_State leaves this aggregate incomplete, and one removed or
      --  renamed leaves a choice naming nothing.

      Witness : constant States.Display_State :=
        (Through  => Through_Row,
         Left     => Left_Row,
         Heads    => Head_Row,
         Requests => Request_Row);
   begin

      --  "per approach" and "per crosswalk" are then swept through the
      --  record, so each group's index and component types are checked on
      --  the component itself and not on the constant it was built from.

      for A in States.Approach loop
         declare
            Through : constant States.Vehicle_Face := Witness.Through (A);
            Left    : constant States.Vehicle_Face := Witness.Left (A);
         begin
            Assert
              (Through = Red and then Left = Red,
               "Display_State must carry a through face and a left face for"
               & " approach "
               & States.Approach'Image (A)
               & ", but they did not read back the faces written into them");
         end;
      end loop;

      for C in States.Crosswalk loop
         declare
            Head    : constant States.Pedestrian_Head := Witness.Heads (C);
            Request : constant States.Request_Indicator :=
              Witness.Requests (C);
         begin
            Assert
              (Head = Dont_Walk and then Request = No_Request,
               "Display_State must carry a pedestrian head and a request"
               & " indicator for crosswalk "
               & States.Crosswalk'Image (C)
               & ", but they did not read back the values written into"
               & " them");
         end;
      end loop;
   end Test_16_Display_State_Aggregates_Every_Output_Signal;

   ------------------------------------------------------------------------
   --  Statement .17 -- the sensors aggregate every input signal
   ------------------------------------------------------------------------

   procedure Test_17_Sensors_State_Aggregates_Every_Input_Signal
     (T : in out Test)
   is
      --@covers llr_1_states.17

      pragma Unreferenced (T);

      Button_Row   : constant States.Pedestrian_Buttons :=
        (others => Released);
      Detector_Row : constant States.Left_Turn_Detectors :=
        (others => No_Vehicle);
      Fault_Line   : constant States.Fault_Detection := Not_Asserted;

      --  As for .16: named associations, no `others` choice, so the record
      --  holds exactly the three groups .17 lists.

      Witness : constant States.Sensors_State :=
        (Buttons    => Button_Row,
         Left_Turns => Detector_Row,
         Fault      => Fault_Line);

      Line : constant States.Fault_Detection := Witness.Fault;
   begin
      for C in States.Crosswalk loop
         declare
            Button : constant States.Pedestrian_Button := Witness.Buttons (C);
         begin
            Assert
              (Button = Released,
               "Sensors_State must carry a pedestrian button for crosswalk "
               & States.Crosswalk'Image (C)
               & ", but it did not read back the value written into it");
         end;
      end loop;

      for A in States.Approach loop
         declare
            Detector : constant States.Left_Turn_Detector :=
              Witness.Left_Turns (A);
         begin
            Assert
              (Detector = No_Vehicle,
               "Sensors_State must carry a left-turn detector for approach "
               & States.Approach'Image (A)
               & ", but it did not read back the value written into it");
         end;
      end loop;

      Assert
        (Line = Not_Asserted,
         "Sensors_State must carry the fault-detection line, but it did not"
         & " read back the value written into it");
   end Test_17_Sensors_State_Aggregates_Every_Input_Signal;

   ------------------------------------------------------------------------
   --  Statement .18 -- the vehicle movements
   ------------------------------------------------------------------------

   procedure Test_18_Movement_Has_Exactly_Eight_Literals (T : in out Test) is
      --@covers llr_1_states.18

      pragma Unreferenced (T);

      type Witness is array (States.Movement) of Boolean;

      Named : constant Witness :=
        (N_Thru => True,
         S_Thru => True,
         E_Thru => True,
         W_Thru => True,
         N_Left => True,
         S_Left => True,
         E_Left => True,
         W_Left => True);

      Counted : Natural := 0;
   begin
      for M in States.Movement loop
         if Named (M) then
            Counted := Counted + 1;
         end if;
      end loop;

      Check_Literal_Count ("States.Movement", Counted, 8, "llr_1_states.18");
   end Test_18_Movement_Has_Exactly_Eight_Literals;

   ------------------------------------------------------------------------
   --  Statement .19 -- Face_Of picks the movement's own face
   ------------------------------------------------------------------------

   procedure Test_19_Face_Of_Reads_The_Movements_Own_Face (T : in out Test) is
      --@covers llr_1_states.19

      pragma Unreferenced (T);

      type Face_Expectation is array (States.Movement) of States.Vehicle_Face;

      --  A display in which the four through faces are four different values
      --  and so are the four left faces, with no approach carrying the same
      --  value in both arrays -- the left row is the through row rotated by
      --  one. Vehicle_Face has four literals (llr_1_states.1) and there are
      --  eight faces, so no single display can make all eight values distinct;
      --  what this one does rule out is every *single* misreading: a routine
      --  that took the wrong approach within an array, or the right approach
      --  from the wrong array, returns a value this table does not give.
      --  The residual coincidences -- wrong array *and* wrong approach -- are
      --  what the sweep at the end of the routine closes.

      Distinct : constant States.Display_State :=
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
         Heads    => (others => Dont_Walk),
         Requests => (others => No_Request));

      --  Transcribed from .19 against the display above: a through movement
      --  reads the through face of its own approach, a left movement the left
      --  face of its own approach. Named associations and no `others` choice,
      --  so a movement added to llr_1_states.18 fails the build here until its
      --  face is transcribed.

      Expected : constant Face_Expectation :=
        (N_Thru => Green,          --  Through (NORTH)
         S_Thru => Yellow,         --  Through (SOUTH)
         E_Thru => Red,            --  Through (EAST)
         W_Thru => Flashing_Red,   --  Through (WEST)
         N_Left => Yellow,         --  Left (NORTH)
         S_Left => Red,            --  Left (SOUTH)
         E_Left => Flashing_Red,   --  Left (EAST)
         W_Left => Green);         --  Left (WEST)

      function Only_Go (M : States.Movement) return States.Display_State;
      --  An all-red display with exactly movement M's own face GREEN. The
      --  movement-to-face mapping is written out again here as a case
      --  statement -- a second rendering of the same sentence, independent of
      --  the function under test, which is what makes the sweep below evidence
      --  rather than a tautology.

      function Only_Go (M : States.Movement) return States.Display_State is
         D : States.Display_State :=
           (Through  => (others => Red),
            Left     => (others => Red),
            Heads    => (others => Dont_Walk),
            Requests => (others => No_Request));
      begin
         case M is
            when N_Thru =>
               D.Through (States.North) := Green;

            when S_Thru =>
               D.Through (States.South) := Green;

            when E_Thru =>
               D.Through (States.East) := Green;

            when W_Thru =>
               D.Through (States.West) := Green;

            when N_Left =>
               D.Left (States.North) := Green;

            when S_Left =>
               D.Left (States.South) := Green;

            when E_Left =>
               D.Left (States.East) := Green;

            when W_Left =>
               D.Left (States.West) := Green;
         end case;

         return D;
      end Only_Go;

   begin

      --  First, the whole mapping at once, on a display whose values were
      --  chosen so that each of the eight answers pins down which array and
      --  which approach was read.

      for M in States.Movement loop
         Assert
           (States.Face_Of (Distinct, M) = Expected (M),
            "Face_Of for "
            & States.Movement'Image (M)
            & " returned "
            & States.Vehicle_Face'Image (States.Face_Of (Distinct, M))
            & " but the requirement gives "
            & States.Vehicle_Face'Image (Expected (M)));
      end loop;

      --  Then the sweep: with exactly one movement's face GREEN and the other
      --  seven RED, Face_Of must answer GREEN for that movement and RED for
      --  every other. Over all 64 ordered pairs that makes the mapping a
      --  bijection between the eight movements and the eight faces, so no pair
      --  of faces can be transposed and still pass -- including the pairs the
      --  four-valued alphabet leaves indistinguishable above.

      for M in States.Movement loop
         declare
            D : constant States.Display_State := Only_Go (M);
         begin
            for Probe in States.Movement loop
               declare
                  Want : constant States.Vehicle_Face :=
                    (if Probe = M then Green else Red);
               begin
                  Assert
                    (States.Face_Of (D, Probe) = Want,
                     "with only "
                     & States.Movement'Image (M)
                     & " driven GREEN, Face_Of for "
                     & States.Movement'Image (Probe)
                     & " returned "
                     & States.Vehicle_Face'Image (States.Face_Of (D, Probe))
                     & " but the requirement gives "
                     & States.Vehicle_Face'Image (Want));
               end;
            end loop;
         end;
      end loop;

   end Test_19_Face_Of_Reads_The_Movements_Own_Face;

   ------------------------------------------------------------------------
   --  Statement .20 -- Is_Go holds exactly for GREEN and YELLOW
   ------------------------------------------------------------------------

   procedure Test_20_Is_Go_Holds_Exactly_For_Green_And_Yellow
     (T : in out Test)
   is
      --@covers llr_1_states.20

      pragma Unreferenced (T);

      type Go_Expectation is array (States.Vehicle_Face) of Boolean;

      --  Transcribed from .20: TRUE exactly when the face is GREEN or YELLOW,
      --  and therefore FALSE for the other two literals llr_1_states.1 gives.
      --  No `others` choice, so a literal added to Vehicle_Face fails the
      --  build until its answer is transcribed -- which matters here, because
      --  "exactly when" is a claim about the whole alphabet.

      Expected : constant Go_Expectation :=
        (Red          => False,
         Yellow       => True,
         Green        => True,
         Flashing_Red => False);
   begin

      --  Four values, so the domain is enumerated outright: the sweep is the
      --  requirement.

      for F in States.Vehicle_Face loop
         Assert
           (States.Is_Go (F) = Expected (F),
            "Is_Go for "
            & States.Vehicle_Face'Image (F)
            & " returned "
            & Boolean'Image (States.Is_Go (F))
            & " but the requirement gives "
            & Boolean'Image (Expected (F)));
      end loop;

   end Test_20_Is_Go_Holds_Exactly_For_Green_And_Yellow;

end Llr_1_States_Tests;
