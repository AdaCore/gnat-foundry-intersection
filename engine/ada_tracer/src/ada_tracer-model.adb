package body Ada_Tracer.Model is

   -----------------
   -- Find_Or_Add --
   -----------------

   function Find_Or_Add
     (Self : in out Project_Info; Name : String) return Positive
   is
      Position : constant Package_Index_Maps.Cursor := Self.Index.Find (Name);
   begin
      if Package_Index_Maps.Has_Element (Position) then
         return Package_Index_Maps.Element (Position);
      end if;

      Self.Packages.Append
        (Package_Info'
           (Name        => To_Unbounded_String (Name),
            Spec_File   => Null_Unbounded_String,
            Body_File   => Null_Unbounded_String,
            Is_Generic  => False,
            Doc         => No_Documentation,
            Subprograms => Subprogram_Vectors.Empty_Vector,
            Entities    => Entity_Vectors.Empty_Vector));

      Self.Index.Insert (Name, Self.Packages.Last_Index);

      return Self.Packages.Last_Index;
   end Find_Or_Add;

   ------------------
   -- Sort_By_Name --
   ------------------

   procedure Sort_By_Name (Self : in out Project_Info) is

      function Before (Left, Right : Package_Info) return Boolean;
      --  Order two packages by their fully qualified name.

      function Before (Left, Right : Check_Info) return Boolean;
      --  Order two checks by source position.

      ------------
      -- Before --
      ------------

      function Before (Left, Right : Package_Info) return Boolean is
      begin
         return Left.Name < Right.Name;
      end Before;

      ------------
      -- Before --
      ------------

      function Before (Left, Right : Check_Info) return Boolean is
      begin
         return
           Left.File < Right.File
           or else (Left.File = Right.File and then Left.Line < Right.Line);
      end Before;

      package Sorting is new Package_Vectors.Generic_Sorting (Before);
      package Check_Sorting is new Check_Vectors.Generic_Sorting (Before);

   begin
      Sorting.Sort (Self.Packages);
      Check_Sorting.Sort (Self.Checks);
      Self.Index.Clear;
   end Sort_By_Name;

end Ada_Tracer.Model;
