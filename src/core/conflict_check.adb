package body Conflict_Check
  with SPARK_Mode => On
is

   function Is_Safe (Active : Movement_Set) return Boolean
   is (for all M1 in Movement =>
         (for all M2 in Movement =>
            (if Active (M1) and Active (M2) then not Conflicts (M1, M2))));

end Conflict_Check;
