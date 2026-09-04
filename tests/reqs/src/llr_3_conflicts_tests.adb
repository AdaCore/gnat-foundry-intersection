with AUnit.Assertions; use AUnit.Assertions;

with Conflicts;
with States;

package body Llr_3_Conflicts_Tests is

   procedure Test_01_Compatible_Holds_For_Exactly_The_Listed_Pairs
     (T : in out Test)
   is
      --@covers llr_3_conflicts.1

      pragma Unreferenced (T);

      use all type States.Movement;

      type Movement_Row is array (States.Movement) of Boolean;
      type Compatible_Matrix is array (States.Movement) of Movement_Row;

      --  The relation llr_3_conflicts.1 gives, transcribed cell by cell from
      --  the matrix that statement tabulates in algorithm_aspects: TRUE where
      --  the table shows `·` (compatible), FALSE where it shows `X`.
      --
      --  That matrix is the statement's own second rendering of the three pair
      --  groups its prose names -- any movement with itself; each through with
      --  the protected left of its own approach (N_THRU/N_LEFT, S_THRU/S_LEFT,
      --  E_THRU/E_LEFT, W_THRU/W_LEFT); the two opposing throughs of one axis
      --  (N_THRU/S_THRU, E_THRU/W_THRU) -- closed under symmetry. Reading the
      --  table against the prose, the two agree, and neither is the Compatible
      --  expression under test: that is what makes the sweep below evidence
      --  rather than a tautology.
      --
      --  Named associations and no `others` choice, so a ninth movement fails
      --  the build until its row and column are transcribed.
      --
      --              NT ST ET WT NL SL EL WL
      --  N_THRU       ·  ·  X  X  ·  X  X  X
      --  S_THRU       ·  ·  X  X  X  ·  X  X
      --  E_THRU       X  X  ·  ·  X  X  ·  X
      --  W_THRU       X  X  ·  ·  X  X  X  ·
      --  N_LEFT       ·  X  X  X  ·  X  X  X
      --  S_LEFT       X  ·  X  X  X  ·  X  X
      --  E_LEFT       X  X  ·  X  X  X  ·  X
      --  W_LEFT       X  X  X  ·  X  X  X  ·
      Expected : constant Compatible_Matrix :=
        (N_Thru =>
           (N_Thru => True,
            S_Thru => True,
            E_Thru => False,
            W_Thru => False,
            N_Left => True,
            S_Left => False,
            E_Left => False,
            W_Left => False),
         S_Thru =>
           (N_Thru => True,
            S_Thru => True,
            E_Thru => False,
            W_Thru => False,
            N_Left => False,
            S_Left => True,
            E_Left => False,
            W_Left => False),
         E_Thru =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => True,
            W_Thru => True,
            N_Left => False,
            S_Left => False,
            E_Left => True,
            W_Left => False),
         W_Thru =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => True,
            W_Thru => True,
            N_Left => False,
            S_Left => False,
            E_Left => False,
            W_Left => True),
         N_Left =>
           (N_Thru => True,
            S_Thru => False,
            E_Thru => False,
            W_Thru => False,
            N_Left => True,
            S_Left => False,
            E_Left => False,
            W_Left => False),
         S_Left =>
           (N_Thru => False,
            S_Thru => True,
            E_Thru => False,
            W_Thru => False,
            N_Left => False,
            S_Left => True,
            E_Left => False,
            W_Left => False),
         E_Left =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => True,
            W_Thru => False,
            N_Left => False,
            S_Left => False,
            E_Left => True,
            W_Left => False),
         W_Left =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => False,
            W_Thru => True,
            N_Left => False,
            S_Left => False,
            E_Left => False,
            W_Left => True));

   begin

      --  Movement is an eight-value enumeration, so "exactly these pairs and
      --  FALSE for every other pair" is discharged by ranging over all 64
      --  ordered pairs -- a Compatible that admitted one pair too many, or
      --  dropped one, fails on that cell and names it.

      for A in States.Movement loop
         for B in States.Movement loop
            Assert
              (Conflicts.Compatible (A, B) = Expected (A) (B),
               "Compatible ("
               & States.Movement'Image (A)
               & ", "
               & States.Movement'Image (B)
               & ") returned "
               & Boolean'Image (Conflicts.Compatible (A, B))
               & " but llr_3_conflicts.1 gives "
               & Boolean'Image (Expected (A) (B)));

            --  The statement gives "the full symmetric relation", so the
            --  reversed pair is a claim in its own right and is checked as
            --  one: an implementation that tested only its first argument's
            --  approach would agree with the table on one order and not the
            --  other. Named notation for the reversed call, so the swap is
            --  visibly deliberate.

            Assert
              (Conflicts.Compatible (A, B)
               = Conflicts.Compatible (A => B, B => A),
               "llr_3_conflicts.1 gives a symmetric relation, but Compatible ("
               & States.Movement'Image (A)
               & ", "
               & States.Movement'Image (B)
               & ") returned "
               & Boolean'Image (Conflicts.Compatible (A, B))
               & " while the reversed pair returned "
               & Boolean'Image (Conflicts.Compatible (A => B, B => A)));
         end loop;
      end loop;

   end Test_01_Compatible_Holds_For_Exactly_The_Listed_Pairs;

   procedure Test_02_Conflicts_Is_The_Complement_Of_Compatible
     (T : in out Test)
   is
      --@covers llr_3_conflicts.2

      pragma Unreferenced (T);

   begin

      --  llr_3_conflicts.2 defines Conflicts relative to Compatible rather
      --  than by a table of its own, so the negation below *is* the statement,
      --  transcribed; there is no separate expected value to render. What
      --  anchors it to the requirement text is Test_01, which pins Compatible
      --  to the pair list llr_3_conflicts.1 names -- with Compatible pinned,
      --  agreeing with its negation on every pair is the whole of .2.
      --
      --  Exhaustive over all 64 ordered pairs for the same reason as .1: the
      --  statement quantifies over pairs of an eight-value enumeration, so the
      --  quantifier can be run rather than sampled.

      for A in States.Movement loop
         for B in States.Movement loop
            Assert
              (Conflicts.Conflicts (A, B) = not Conflicts.Compatible (A, B),
               "Conflicts ("
               & States.Movement'Image (A)
               & ", "
               & States.Movement'Image (B)
               & ") returned "
               & Boolean'Image (Conflicts.Conflicts (A, B))
               & " but llr_3_conflicts.2 requires "
               & Boolean'Image (not Conflicts.Compatible (A, B))
               & ", the complement of Compatible for that pair");
         end loop;
      end loop;

   end Test_02_Conflicts_Is_The_Complement_Of_Compatible;

   procedure Test_03_Safe_Faces_Holds_Exactly_When_No_Conflicting_Pair_Is_Go
     (T : in out Test)
   is
      --@covers llr_3_conflicts.3

      pragma Unreferenced (T);

      use all type States.Movement;

      --  Every face RED, every head steady DONT WALK, every lamp dark: no
      --  movement is "go", so no pair can be jointly released.
      All_Red : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      function Go_Pair (A, B : States.Movement) return States.Display_State;
      --  All_Red with exactly A and B driven GREEN. Isolating one pair at a
      --  time is what lets the check below range over the whole relation:
      --  llr_3_conflicts.3 quantifies over pairs, so a state carrying exactly
      --  one pair of go faces exercises exactly one instance of the
      --  quantifier body.

      function Go_Pair (A, B : States.Movement) return States.Display_State is
         D : States.Display_State := All_Red;

         procedure Set_Go (M : States.Movement);

         procedure Set_Go (M : States.Movement) is
         begin
            case M is
               when N_Thru =>
                  D.Through (States.North) := States.Green;

               when S_Thru =>
                  D.Through (States.South) := States.Green;

               when E_Thru =>
                  D.Through (States.East) := States.Green;

               when W_Thru =>
                  D.Through (States.West) := States.Green;

               when N_Left =>
                  D.Left (States.North) := States.Green;

               when S_Left =>
                  D.Left (States.South) := States.Green;

               when E_Left =>
                  D.Left (States.East) := States.Green;

               when W_Left =>
                  D.Left (States.West) := States.Green;
            end case;
         end Set_Go;

      begin
         Set_Go (A);
         Set_Go (B);
         return D;
      end Go_Pair;

   begin

      --  llr_3_conflicts.3 says Safe_Faces is TRUE for a Display_State
      --  exactly when no two movements for which Conflicts is TRUE both have
      --  Is_Go faces. Ranging over all 64 ordered pairs and driving exactly
      --  that pair go, the predicate must agree with the relation on every
      --  one -- so a Safe_Faces that missed a pair, or quantified over the
      --  wrong domain, fails here.
      --
      --  The expected value comes from Conflicts (llr_3_conflicts.2), not
      --  from the Safe_Faces expression under test: the two are independent
      --  renderings of the requirement, cross-checked exhaustively.

      for A in States.Movement loop
         for B in States.Movement loop
            Assert
              (Conflicts.Safe_Faces (Go_Pair (A, B))
               = not Conflicts.Conflicts (A, B),
               "Safe_Faces with only "
               & States.Movement'Image (A)
               & " and "
               & States.Movement'Image (B)
               & " go returned "
               & Boolean'Image (Conflicts.Safe_Faces (Go_Pair (A, B)))
               & " but llr_3_conflicts.3 requires "
               & Boolean'Image (not Conflicts.Conflicts (A, B)));
         end loop;
      end loop;

      --  The all-red state carries no go face at all, so the quantifier is
      --  vacuously satisfied -- the boundary the pairwise sweep never builds.

      Assert
        (Conflicts.Safe_Faces (All_Red),
         "an all-red display carries no go face and must satisfy"
         & " llr_3_conflicts.3");

   end Test_03_Safe_Faces_Holds_Exactly_When_No_Conflicting_Pair_Is_Go;

   procedure Test_04_Next_Conflicting_Through_Maps_Every_Approach
     (T : in out Test)
   is
      --@covers llr_3_conflicts.4

      pragma Unreferenced (T);

      use all type States.Approach;

      type Clearing_Through is array (States.Approach) of States.Approach;

      --  The whole of llr_3_conflicts.4, transcribed from its four clauses:
      --  NORTH to SOUTH, SOUTH to EAST, EAST to WEST, WEST to NORTH.
      --
      --  Named associations and no `others` choice: a fifth approach would
      --  fail the build rather than silently inherit a neighbour's entry.
      Expected : constant Clearing_Through :=
        (North => South, South => East, East => West, West => North);

   begin

      --  A total map over a four-value enumeration, so the sweep below is the
      --  entire relation -- there is nothing left for a sampled test to miss.

      for A in States.Approach loop
         Assert
           (Conflicts.Next_Conflicting_Through (A) = Expected (A),
            "Next_Conflicting_Through ("
            & States.Approach'Image (A)
            & ") returned "
            & States.Approach'Image (Conflicts.Next_Conflicting_Through (A))
            & " but llr_3_conflicts.4 gives "
            & States.Approach'Image (Expected (A)));
      end loop;

   end Test_04_Next_Conflicting_Through_Maps_Every_Approach;

   procedure Test_05_Adjacent_Through_Maps_Every_Crosswalk (T : in out Test) is
      --@covers llr_3_conflicts.5

      pragma Unreferenced (T);

      use all type States.Approach;
      use all type States.Crosswalk;

      type Adjacent_Approach is array (States.Crosswalk) of States.Approach;

      --  The whole of llr_3_conflicts.5, transcribed from its four clauses:
      --  NORTH_SIDE to WEST, SOUTH_SIDE to EAST, EAST_SIDE to NORTH,
      --  WEST_SIDE to SOUTH. Crosswalks are named by the arm they span and
      --  approaches by travel direction, so the map is a rotation and none of
      --  the four entries can be guessed from the names -- which is why every
      --  one is written out and every one is checked.
      Expected : constant Adjacent_Approach :=
        (North_Side => West,
         South_Side => East,
         East_Side  => North,
         West_Side  => South);

   begin

      --  Four crosswalks, four entries, so the sweep is the whole map: a
      --  rotation applied the wrong way round fails on every crosswalk, and a
      --  single transposed pair fails on the two it swaps.

      for C in States.Crosswalk loop
         Assert
           (Conflicts.Adjacent_Through (C) = Expected (C),
            "Adjacent_Through ("
            & States.Crosswalk'Image (C)
            & ") returned "
            & States.Approach'Image (Conflicts.Adjacent_Through (C))
            & " but llr_3_conflicts.5 gives "
            & States.Approach'Image (Expected (C)));
      end loop;

   end Test_05_Adjacent_Through_Maps_Every_Crosswalk;

   procedure Test_06_Crosswalk_Conflicts_Exempts_Exactly_The_Listed_Pairs
     (T : in out Test)
   is
      --@covers llr_3_conflicts.6

      pragma Unreferenced (T);

      use all type States.Crosswalk;
      use all type States.Movement;

      type Movement_Row is array (States.Movement) of Boolean;
      type Crosswalk_Matrix is array (States.Crosswalk) of Movement_Row;

      --  The relation llr_3_conflicts.6 gives, transcribed cell by cell from
      --  the matrix that statement tabulates in algorithm_aspects: TRUE where
      --  the table shows `X` (conflicting), FALSE where it shows `·`.
      --
      --  Reading the table against the statement's prose, the FALSE cells are
      --  exactly the three exemptions it lists per crosswalk -- the two
      --  through movements of the parallel axis (EAST_SIDE and WEST_SIDE with
      --  N_THRU and S_THRU; NORTH_SIDE and SOUTH_SIDE with E_THRU and W_THRU)
      --  and the protected left of the crosswalk's Adjacent_Through approach
      --  (NORTH_SIDE with W_LEFT, SOUTH_SIDE with E_LEFT, EAST_SIDE with
      --  N_LEFT, WEST_SIDE with S_LEFT) -- and every other cell is TRUE. The
      --  two renderings agree, and neither is the expression under test.
      --
      --              NT ST ET WT NL SL EL WL
      --  NORTH_SIDE   X  X  ·  ·  X  X  X  ·
      --  SOUTH_SIDE   X  X  ·  ·  X  X  ·  X
      --  EAST_SIDE    ·  ·  X  X  ·  X  X  X
      --  WEST_SIDE    ·  ·  X  X  X  ·  X  X
      Expected : constant Crosswalk_Matrix :=
        (North_Side =>
           (N_Thru => True,
            S_Thru => True,
            E_Thru => False,
            W_Thru => False,
            N_Left => True,
            S_Left => True,
            E_Left => True,
            W_Left => False),
         South_Side =>
           (N_Thru => True,
            S_Thru => True,
            E_Thru => False,
            W_Thru => False,
            N_Left => True,
            S_Left => True,
            E_Left => False,
            W_Left => True),
         East_Side  =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => True,
            W_Thru => True,
            N_Left => False,
            S_Left => True,
            E_Left => True,
            W_Left => True),
         West_Side  =>
           (N_Thru => False,
            S_Thru => False,
            E_Thru => True,
            W_Thru => True,
            N_Left => True,
            S_Left => False,
            E_Left => True,
            W_Left => True));

   begin

      --  Four crosswalks by eight movements is 32 cells, so "FALSE for exactly
      --  these pairs and TRUE for every other pair" is run in full: an
      --  exemption granted to one movement too many, or withheld from one the
      --  statement lists, fails on its own cell and names the pair.

      for C in States.Crosswalk loop
         for M in States.Movement loop
            Assert
              (Conflicts.Crosswalk_Conflicts (C, M) = Expected (C) (M),
               "Crosswalk_Conflicts ("
               & States.Crosswalk'Image (C)
               & ", "
               & States.Movement'Image (M)
               & ") returned "
               & Boolean'Image (Conflicts.Crosswalk_Conflicts (C, M))
               & " but llr_3_conflicts.6 gives "
               & Boolean'Image (Expected (C) (M)));
         end loop;
      end loop;

   end Test_06_Crosswalk_Conflicts_Exempts_Exactly_The_Listed_Pairs;

end Llr_3_Conflicts_Tests;
