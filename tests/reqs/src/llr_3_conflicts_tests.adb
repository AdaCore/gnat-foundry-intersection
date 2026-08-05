with AUnit.Assertions; use AUnit.Assertions;

with Conflicts;
with States;

package body Llr_3_Conflicts_Tests is

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

end Llr_3_Conflicts_Tests;
