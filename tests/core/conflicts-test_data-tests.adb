--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Conflicts.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

--  begin read only
--  end read only
package body Conflicts.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Compatible (Gnattest_T : in out Test);
   procedure Test_Compatible_1f0996 (Gnattest_T : in out Test) renames Test_Compatible;
--  id:2.2/1f09964fe5edad9f/Compatible/1/0/
   procedure Test_Compatible (Gnattest_T : in out Test) is
   --  conflicts.ads:38:4:Compatible
--  end read only

      pragma Unreferenced (Gnattest_T);

      use all type States.Movement;

      type Movement_Pair is record
         A, B : States.Movement;
      end record;

      type Pair_List is array (Positive range <>) of Movement_Pair;

      Same_Approach_Pairs : constant Pair_List :=
        ((N_Thru, N_Left), (S_Thru, S_Left),
         (E_Thru, E_Left), (W_Thru, W_Left));

      Opposing_Through_Pairs : constant Pair_List :=
        ((N_Thru, S_Thru), (E_Thru, W_Thru));

      Named_Pairs : constant Pair_List :=
        Same_Approach_Pairs & Opposing_Through_Pairs;
      --  Each unordered pair once; Expected closes them under symmetry.

      function Expected (A, B : States.Movement) return Boolean
      is (A = B
          or else
            (for some P of Named_Pairs =>
               (A = P.A and then B = P.B)
               or else (A = P.B and then B = P.A)));
      --  The pairs llr_3_conflicts.1 names compatible, transcribed from its
      --  three clauses rather than from the Compatible expression under test.

   begin

      for A in States.Movement loop
         for B in States.Movement loop
            AUnit.Assertions.Assert
              (Compatible (A, B) = Expected (A, B),
               "Compatible (" & States.Movement'Image (A) & ", "
               & States.Movement'Image (B) & ") = "
               & Boolean'Image (Compatible (A, B))
               & " but llr_3_conflicts.1 requires "
               & Boolean'Image (Expected (A, B)));
         end loop;
      end loop;

--  begin read only
   end Test_Compatible;
--  end read only


--  begin read only
   procedure Test_Conflicts (Gnattest_T : in out Test);
   procedure Test_Conflicts_3327f5 (Gnattest_T : in out Test) renames Test_Conflicts;
--  id:2.2/3327f57d603b4c68/Conflicts/1/0/
   procedure Test_Conflicts (Gnattest_T : in out Test) is
   --  conflicts.ads:89:4:Conflicts
--  end read only

      pragma Unreferenced (Gnattest_T);

   begin

      AUnit.Assertions.Assert
        (Gnattest_Generated.Default_Assert_Value,
         "Test not implemented.");

--  begin read only
   end Test_Conflicts;
--  end read only


--  begin read only
   procedure Test_Safe_Faces (Gnattest_T : in out Test);
   procedure Test_Safe_Faces_d90a65 (Gnattest_T : in out Test) renames Test_Safe_Faces;
--  id:2.2/d90a65c788a3dbb4/Safe_Faces/1/0/
   procedure Test_Safe_Faces (Gnattest_T : in out Test) is
   --  conflicts.ads:97:4:Safe_Faces
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  The all-restrictive display: every face RED, every head steady
      --  DONT WALK, every lamp dark. No movement is "go", so no conflicting
      --  pair can be jointly released.
      All_Red : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      Unsafe : States.Display_State := All_Red;

   begin

      Assert
        (Safe_Faces (All_Red),
         "an all-red display should satisfy the conflict invariant");

      --  Two crossing throughs driven GREEN at once is exactly what
      --  hlr_0_safety.2 forbids: N_Thru and E_Thru conflict.
      Unsafe.Through (States.North) := States.Green;
      Unsafe.Through (States.East) := States.Green;

      Assert
        (not Safe_Faces (Unsafe),
         "crossing throughs both GREEN should violate the conflict"
         & " invariant");

--  begin read only
   end Test_Safe_Faces;
--  end read only


--  begin read only
   procedure Test_Next_Conflicting_Through (Gnattest_T : in out Test);
   procedure Test_Next_Conflicting_Through_b37cc2 (Gnattest_T : in out Test) renames Test_Next_Conflicting_Through;
--  id:2.2/b37cc2483d3dfff3/Next_Conflicting_Through/1/0/
   procedure Test_Next_Conflicting_Through (Gnattest_T : in out Test) is
   --  conflicts.ads:112:4:Next_Conflicting_Through
--  end read only

      pragma Unreferenced (Gnattest_T);

      use all type States.Approach;

   begin

      --  The clearing-through binding of hlr_5_vehicle_1_left_demand: each
      --  approach's latched left demand is cleared by the GREEN release of
      --  the next conflicting through in cycle order.

      Assert
        (Next_Conflicting_Through (North) = South,
         "the North left demand should be cleared by the South through");
      Assert
        (Next_Conflicting_Through (South) = East,
         "the South left demand should be cleared by the East through");
      Assert
        (Next_Conflicting_Through (East) = West,
         "the East left demand should be cleared by the West through");
      Assert
        (Next_Conflicting_Through (West) = North,
         "the West left demand should be cleared by the North through");

--  begin read only
   end Test_Next_Conflicting_Through;
--  end read only


--  begin read only
   procedure Test_Adjacent_Through (Gnattest_T : in out Test);
   procedure Test_Adjacent_Through_4df54a (Gnattest_T : in out Test) renames Test_Adjacent_Through;
--  id:2.2/4df54af56a927601/Adjacent_Through/1/0/
   procedure Test_Adjacent_Through (Gnattest_T : in out Test) is
   --  conflicts.ads:126:4:Adjacent_Through
--  end read only

      pragma Unreferenced (Gnattest_T);

      use all type States.Approach;
      use all type States.Crosswalk;

   begin

      --  The keep-right rotation map of hlr_6_pedestrian.8: each crosswalk
      --  takes its PENDING -> WALK edge with the through movement parallel
      --  and adjacent to it -- the arm to that through's right.

      Assert
        (Adjacent_Through (North_Side) = West,
         "the North_Side crossing should be served by the West through");
      Assert
        (Adjacent_Through (South_Side) = East,
         "the South_Side crossing should be served by the East through");
      Assert
        (Adjacent_Through (East_Side) = North,
         "the East_Side crossing should be served by the North through");
      Assert
        (Adjacent_Through (West_Side) = South,
         "the West_Side crossing should be served by the South through");

--  begin read only
   end Test_Adjacent_Through;
--  end read only


--  begin read only
   procedure Test_Crosswalk_Conflicts (Gnattest_T : in out Test);
   procedure Test_Crosswalk_Conflicts_740c67 (Gnattest_T : in out Test) renames Test_Crosswalk_Conflicts;
--  id:2.2/740c67ad5c5dd0af/Crosswalk_Conflicts/1/0/
   procedure Test_Crosswalk_Conflicts (Gnattest_T : in out Test) is
   --  conflicts.ads:142:4:Crosswalk_Conflicts
--  end read only

      pragma Unreferenced (Gnattest_T);

      use all type States.Crosswalk;
      use all type States.Movement;

      type Movement_Row is array (States.Movement) of Boolean;
      type Crosswalk_Table is array (States.Crosswalk) of Movement_Row;

      --  The llr_3_conflicts.6 table transcribed cell by cell from its
      --  algorithm_aspects rendering rather than from the expression under
      --  test, so a mis-edited case arm shows up here. True is a conflicting
      --  cell (`X`), False a non-conflicting one (`·`):
      --
      --              N_THRU S_THRU E_THRU W_THRU N_LEFT S_LEFT E_LEFT W_LEFT
      --  NORTH_SIDE    X      X      ·      ·      X      X      X      ·
      --  SOUTH_SIDE    X      X      ·      ·      X      X      ·      X
      --  EAST_SIDE     ·      ·      X      X      ·      X      X      X
      --  WEST_SIDE     ·      ·      X      X      X      ·      X      X
      Expected : constant Crosswalk_Table :=
        (North_Side =>
           (N_Thru => True,  S_Thru => True,  E_Thru => False, W_Thru => False,
            N_Left => True,  S_Left => True,  E_Left => True,  W_Left => False),
         South_Side =>
           (N_Thru => True,  S_Thru => True,  E_Thru => False, W_Thru => False,
            N_Left => True,  S_Left => True,  E_Left => False, W_Left => True),
         East_Side =>
           (N_Thru => False, S_Thru => False, E_Thru => True,  W_Thru => True,
            N_Left => False, S_Left => True,  E_Left => True,  W_Left => True),
         West_Side =>
           (N_Thru => False, S_Thru => False, E_Thru => True,  W_Thru => True,
            N_Left => True,  S_Left => False, E_Left => True,  W_Left => True));

   begin

      for C in States.Crosswalk loop
         for M in States.Movement loop
            Assert
              (Crosswalk_Conflicts (C, M) = Expected (C) (M),
               "Crosswalk_Conflicts ("
               & States.Crosswalk'Image (C)
               & ", "
               & States.Movement'Image (M)
               & ") = "
               & Boolean'Image (Crosswalk_Conflicts (C, M))
               & " but llr_3_conflicts.6 requires "
               & Boolean'Image (Expected (C) (M)));
         end loop;
      end loop;

--  begin read only
   end Test_Crosswalk_Conflicts;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end Conflicts.Test_Data.Tests;
