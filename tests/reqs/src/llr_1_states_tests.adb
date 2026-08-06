with AUnit.Assertions; use AUnit.Assertions;

with States;

package body Llr_1_States_Tests is

   use all type States.Movement;
   use all type States.Pedestrian_Head;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;

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
