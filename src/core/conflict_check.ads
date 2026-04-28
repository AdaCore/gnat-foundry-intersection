--  Conflict-check module — the canonical safety logic.
--
--  This package is the SPARK proof target. It defines:
--    * the set of movements (vehicle and pedestrian),
--    * the conflict matrix as a constant,
--    * a predicate Is_Safe that returns True iff a candidate set of active
--      movements respects the matrix.
--
--  @req FR-SF-01, FR-SF-02
--
--  Proof obligations (to be discharged by gnatprove):
--    * Symmetry of the conflict matrix.
--    * Reflexivity: a movement does not conflict with itself.
--    * For all M1, M2: Conflicts (M1, M2) implies not (Active (M1)
--      and Active (M2)) in any state where Is_Safe returns True.

package Conflict_Check
  with SPARK_Mode => On,
       Pure
is

   --  All controllable movements.
   type Movement is
     (NS_Through, NS_Left,
      EW_Through, EW_Left,
      Ped_NS, Ped_EW);

   --  A bit-set of movements: True means "active" (showing green/yellow
   --  for vehicles, WALK / FDW for pedestrians).
   type Movement_Set is array (Movement) of Boolean;

   --  The conflict matrix. Conflicts (A, B) is True iff A and B must never
   --  be simultaneously active.
   type Conflict_Matrix is array (Movement, Movement) of Boolean;

   --  TODO: populate the matrix and prove its properties.
   --  The current value is a placeholder; see the open question in
   --  docs/requirements/conflict-matrix.md regarding Ped row inversion.
   Conflicts : constant Conflict_Matrix := (others => (others => False));

   --  Symmetry: Conflicts (A, B) = Conflicts (B, A).
   --  Reflexivity: Conflicts (M, M) = False.
   --  These will be encoded as Static_Predicate or Ghost expressions
   --  once the real matrix is populated.

   --  Returns True iff no two simultaneously-active movements are in
   --  conflict. This is the central safety predicate.
   function Is_Safe (Active : Movement_Set) return Boolean
     with Ghost,
          Post => Is_Safe'Result =
            (for all M1 in Movement =>
               (for all M2 in Movement =>
                  (if Active (M1) and Active (M2)
                   then not Conflicts (M1, M2))));

end Conflict_Check;
