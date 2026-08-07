with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Langkit_Support.Slocs;
with Langkit_Support.Text; use Langkit_Support.Text;

with Libadalang.Common; use Libadalang.Common;

with Ada_Tracer.Comments;
with Ada_Tracer.Gnatdoc_Tags;

package body Ada_Tracer.Walk is

   use Ada_Tracer.Model;

   package Line_Sets is new Ada.Containers.Ordered_Sets (Positive);

   No_Owner : constant Natural := 0;
   --  Stands in for "this declaration is not inside any package", in which
   --  case its subprograms are not reported: the tool's unit of output is the
   --  package.

   function Node_Text (Node : Ada_Node'Class) return String;
   --  The source slice a node was parsed from, as UTF-8.
   --  @param Node The node to read; may be null
   --  @return Its text, or the empty string when the node is null

   function Qualified_Name (Decl : Basic_Decl'Class) return String;
   --  The fully qualified name of a declaration, falling back to its simple
   --  name when Libadalang cannot form one.
   --  @param Decl The declaration to name
   --  @return Its name, or the empty string if even that is unavailable

   function Simple_Name (Decl : Basic_Decl'Class) return String;
   --  The declaration's own name, without any prefix.
   --  @param Decl The declaration to name
   --  @return Its name, or the empty string if unavailable

   function Full_Name (Name : Defining_Name'Class) return String;
   --  The fully qualified form of one declared name. Taken per name rather
   --  than per declaration because `A, B : Integer;` declares two.
   --  @param Name The declared name
   --  @return Its qualified form, falling back to the name as written

   function Relative_To (Path, Base : String) return String;
   --  Express `Path` relative to `Base` when it sits underneath it.
   --  @param Path The absolute file name to shorten
   --  @param Base The directory to shorten it against
   --  @return The relative name, or `Path` unchanged

   function Signature (Info : Subprogram_Info) return String;
   --  A key distinguishing overloads of the same name, so that a body can be
   --  matched against the spec declaration it completes without asking
   --  Libadalang to resolve anything.
   --  @param Info The subprogram to key
   --  @return Its name and parameter profile

   ---------------
   -- Node_Text --
   ---------------

   function Node_Text (Node : Ada_Node'Class) return String is
   begin
      if Node.Is_Null then
         return "";
      end if;

      return To_UTF8 (Text (Node));
   end Node_Text;

   -----------------
   -- Simple_Name --
   -----------------

   function Simple_Name (Decl : Basic_Decl'Class) return String is
   begin
      return Node_Text (Decl.P_Defining_Name);
   exception
      when Property_Error | Precondition_Failure =>
         return "";
   end Simple_Name;

   --------------------
   -- Qualified_Name --
   --------------------

   function Qualified_Name (Decl : Basic_Decl'Class) return String is
   begin
      return To_UTF8 (Decl.P_Fully_Qualified_Name);
   exception
      when Property_Error | Precondition_Failure =>
         return Simple_Name (Decl);
   end Qualified_Name;

   ---------------
   -- Full_Name --
   ---------------

   function Full_Name (Name : Defining_Name'Class) return String is
   begin
      return To_UTF8 (Name.P_Fully_Qualified_Name);
   exception
      when Property_Error | Precondition_Failure =>
         return Node_Text (Name);
   end Full_Name;

   -----------------
   -- Relative_To --
   -----------------

   function Relative_To (Path, Base : String) return String is
      Prefix : constant String :=
        (if Base = "" or else Base (Base'Last) = '/'
         then Base
         else Base & '/');
   begin
      if Prefix'Length > 1
        and then Path'Length > Prefix'Length
        and then Path (Path'First .. Path'First + Prefix'Length - 1) = Prefix
      then
         return Path (Path'First + Prefix'Length .. Path'Last);
      end if;

      return Path;
   end Relative_To;

   ---------------
   -- Signature --
   ---------------

   function Signature (Info : Subprogram_Info) return String is
      Result : Unbounded_String := Info.Qualified_Name & "(";
   begin
      for Parameter of Info.Parameters loop
         Append (Result, Parameter.Type_Name);
         Append (Result, ";");
      end loop;

      Append (Result, ")");
      Append (Result, Info.Return_Type);

      return To_String (Result);
   end Signature;

   ----------
   -- Unit --
   ----------

   procedure Unit
     (Into    : in out Model.Project_Info;
      Source  : Analysis_Unit;
      Setting : Options)
   is
      use Langkit_Support.Slocs;

      Base : constant String := To_String (Setting.Base_Dir);

      File : constant String :=
        Relative_To (Ada.Directories.Full_Name (Source.Get_Filename), Base);

      Claimed : Line_Sets.Set;
      --  Lines already taken as some declaration's trailing documentation.
      --  Without this, the block below `procedure A;` would be handed to
      --  `procedure B;` as well when the two are adjacent.

      procedure Claim (Block : Comments.Comment_Block);
      --  Record a block's lines as taken.
      --  @param Block The block to claim

      function Unclaimed (Block : Comments.Comment_Block) return Boolean;
      --  Whether none of a block's lines have been taken already.
      --  @param Block The block to test
      --  @return True when the block is free to use

      function Entity_Doc (Node : Ada_Node'Class) return Documentation;
      --  The documentation of a declaration other than a package: the block
      --  below it by preference, per `design/code_conventions.md`, plus the
      --  block above it, which is how bodies are written.
      --  @param Node The declaration
      --  @return Its documentation

      function Package_Doc (Node : Ada_Node'Class) return Documentation;
      --  The documentation of a package: the block above the `package`
      --  keyword, falling back to the file header above the context clause.
      --  @param Node The package declaration, or the `generic` wrapper
      --  @return Its documentation

      procedure Fold_Or_Append
        (List : in out Subprogram_Vectors.Vector; Info : Subprogram_Info);
      --  Add a subprogram to a list, folding a body into the spec declaration
      --  it completes rather than reporting it twice.
      --  @param List The list to add to
      --  @param Info The subprogram to record

      procedure Add_Subprogram (Owner : Positive; Info : Subprogram_Info);
      --  File a subprogram under its package.
      --  @param Owner The index of the owning package
      --  @param Info The subprogram to record

      procedure Add_Entity (Owner : Positive; Info : Entity_Info);
      --  File a type, object or exception under its package.
      --  @param Owner The index of the owning package
      --  @param Info The entity to record

      function Interior_Comments
        (Decl : Ada_Node'Class) return Comment_Region_Vectors.Vector;
      --  The comment blocks inside a subprogram body, with their tags parsed.
      --  @param Decl The body
      --  @return Its interior blocks, or an empty vector for anything else

      function Is_First_Aspect (Node : Ada_Node'Class) return Boolean;
      --  Whether `Node` is the first association of its aspect list.
      --  @param Node The aspect association to test
      --  @return True when it opens the list

      procedure Record_Check
        (Node : Ada_Node'Class; Kind : Check_Kind; Name : String);
      --  Report `Node` as a check when the comment block directly above it
      --  carries a `@covers` tag; untagged constructs are not checks.
      --  @param Node The pragma or aspect association
      --  @param Kind Which of the two it is
      --  @param Name The pragma name or aspect mark

      function Scan_Checks (Node : Ada_Node'Class) return Visit_Status;
      --  `Traverse` callback dispatching pragmas and aspect associations to
      --  `Record_Check`.
      --  @param Node The node under visit
      --  @return Always `Into`: checks may sit at any depth

      function Register
        (Decl       : Basic_Decl'Class;
         Anchor     : Ada_Node'Class;
         Is_Generic : Boolean;
         Site       : Declaration_Site) return Natural;
      --  Create or update the entry for a package.
      --  @param Decl The package declaration or body
      --  @param Anchor The node its header comment sits above
      --  @param Is_Generic Whether it is a generic package
      --  @param Site Whether this is the spec or the body
      --  @return The package's index, or `No_Owner` if it cannot be named

      procedure Record_Subprogram
        (Decl   : Ada_Node'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site);
      --  Extract one subprogram declaration into the model.
      --  @param Decl The declaration
      --  @param Owner The index of the owning package, or `No_Owner` for a
      --    library-level subprogram, which is filed on its own
      --  @param Nested Whether a subprogram body encloses it
      --  @param Site Whether it was found in a spec or a body

      procedure Record_Entity
        (Decl        : Ada_Node'Class;
         Name        : Defining_Name'Class;
         Kind        : Entity_Kind;
         Owner       : Positive;
         Site        : Declaration_Site;
         Is_Renaming : Boolean;
         Doc         : Documentation);
      --  Extract one declared name into the model as an entity.
      --  @param Decl The declaration the name belongs to
      --  @param Name The declared name
      --  @param Kind What sort of entity it is
      --  @param Owner The index of the owning package
      --  @param Site Whether it was found in a spec or a body
      --  @param Is_Renaming Whether the declaration is a renaming
      --  @param Doc The documentation of the declaration as a whole

      procedure Record_Entities
        (Decl        : Ada_Node'Class;
         Names       : Defining_Name_List;
         Kind        : Entity_Kind;
         Owner       : Positive;
         Site        : Declaration_Site;
         Is_Renaming : Boolean := False);
      --  Extract every name of a multi-identifier declaration, one entity
      --  each. The documentation is read once and shared: it documents the
      --  declaration, not any single name of it.
      --  @param Decl The declaration
      --  @param Names Its declared names
      --  @param Kind What sort of entity they are
      --  @param Owner The index of the owning package
      --  @param Site Whether it was found in a spec or a body
      --  @param Is_Renaming Whether the declaration is a renaming

      procedure Walk_Decl
        (Decl   : Ada_Node'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site);
      --  Dispatch on a declaration's kind, recursing into whatever declares
      --  further entities.
      --  @param Decl The node to consider
      --  @param Owner The index of the package it sits in
      --  @param Nested Whether a subprogram body encloses it
      --  @param Site Whether it was found in a spec or a body

      procedure Walk_Part
        (Part   : Declarative_Part'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site);
      --  Walk a declarative part.
      --  @param Part The part to walk; may be null
      --  @param Owner The index of the package it belongs to
      --  @param Nested Whether a subprogram body encloses it
      --  @param Site Whether it was found in a spec or a body

      -----------
      -- Claim --
      -----------

      procedure Claim (Block : Comments.Comment_Block) is
      begin
         if Comments.Is_Empty (Block) then
            return;
         end if;

         for Line in Block.First_Line .. Block.Last_Line loop
            Claimed.Include (Line);
         end loop;
      end Claim;

      ---------------
      -- Unclaimed --
      ---------------

      function Unclaimed (Block : Comments.Comment_Block) return Boolean is
      begin
         if Comments.Is_Empty (Block) then
            return False;
         end if;

         for Line in Block.First_Line .. Block.Last_Line loop
            if Claimed.Contains (Line) then
               return False;
            end if;
         end loop;

         return True;
      end Unclaimed;

      ----------------
      -- Entity_Doc --
      ----------------

      function Entity_Doc (Node : Ada_Node'Class) return Documentation is
         Trailing : constant Comments.Comment_Block :=
           Comments.Trailing_Block (Node.Token_End);
         Leading  : Comments.Comment_Block :=
           Comments.Leading_Block (Node.Token_Start);
      begin
         Claim (Trailing);

         if not Unclaimed (Leading) then
            Leading := Comments.Empty_Block;
         end if;

         Claim (Leading);

         return Gnatdoc_Tags.Merge (Leading, Trailing);
      end Entity_Doc;

      -----------------
      -- Package_Doc --
      -----------------

      function Package_Doc (Node : Ada_Node'Class) return Documentation is
         Block : Comments.Comment_Block :=
           Comments.Leading_Block (Node.Token_Start);
      begin
         --  A library-level package's header sits above the context clause,
         --  not above the `package` keyword, so the prelude and a blank line
         --  separate it from the declaration. Retry from the root of the
         --  compilation unit, as `Libadalang.Doc_Utils` does.

         if Comments.Is_Empty (Block) and then not Source.Root.Is_Null then
            Block :=
              Comments.Leading_Block
                (Source.Root.Token_Start, Skip_Blank_Lines => True);
         end if;

         if not Unclaimed (Block) then
            return No_Documentation;
         end if;

         Claim (Block);

         return Gnatdoc_Tags.Parse (Block, Model.Leading);
      end Package_Doc;

      --------------------
      -- Fold_Or_Append --
      --------------------

      procedure Fold_Or_Append
        (List : in out Subprogram_Vectors.Vector; Info : Subprogram_Info)
      is
         Key : constant String := Signature (Info);
      begin
         --  A subprogram declared in a spec and defined in the body is one
         --  entity, not two. Matching on name and profile keeps this purely
         --  syntactic; asking Libadalang for the other part would drag in the
         --  name resolution the tool otherwise never needs.

         if Info.Declared_In = In_Body and then not Info.Nested then
            for Index in List.First_Index .. List.Last_Index loop
               declare
                  Existing : Subprogram_Info := List (Index);
               begin
                  if Existing.Declared_In = In_Spec
                    and then Signature (Existing) = Key
                  then
                     Existing.Has_Body := True;

                     if Existing.Doc.Source = No_Doc then
                        Existing.Doc := Info.Doc;
                     end if;

                     --  The folded entry is anchored at the spec declaration,
                     --  so it is not itself a body and `Is_Body` stays as it
                     --  is. Its interior comments would otherwise be lost,
                     --  though, and they are the only record of what the body
                     --  said.

                     if Existing.Body_Comments.Is_Empty then
                        Existing.Body_Comments := Info.Body_Comments;
                     end if;

                     List.Replace_Element (Index, Existing);

                     return;
                  end if;
               end;
            end loop;
         end if;

         List.Append (Info);
      end Fold_Or_Append;

      --------------------
      -- Add_Subprogram --
      --------------------

      procedure Add_Subprogram (Owner : Positive; Info : Subprogram_Info) is
         Owned : Package_Info := Into.Packages (Owner);
      begin
         Fold_Or_Append (Owned.Subprograms, Info);
         Into.Packages.Replace_Element (Owner, Owned);
      end Add_Subprogram;

      ----------------
      -- Add_Entity --
      ----------------

      procedure Add_Entity (Owner : Positive; Info : Entity_Info) is
         Owned : Package_Info := Into.Packages (Owner);
      begin
         Owned.Entities.Append (Info);
         Into.Packages.Replace_Element (Owner, Owned);
      end Add_Entity;

      -----------------------
      -- Interior_Comments --
      -----------------------

      function Interior_Comments
        (Decl : Ada_Node'Class) return Comment_Region_Vectors.Vector
      is
         Result : Comment_Region_Vectors.Vector;
         Blocks : Comments.Comment_Block_Vectors.Vector;
      begin
         if Decl.Kind /= Ada_Subp_Body then
            return Comment_Region_Vectors.Empty_Vector;
         end if;

         --  Start after the specification rather than at the body's first
         --  token, so that the search begins around the `is`. Interior blocks
         --  deliberately bypass `Claim` / `Unclaimed`: that set stops two
         --  adjacent *declarations* fighting over one block, and an interior
         --  block belongs to exactly one body by construction.

         declare
            Spec : constant Subp_Spec := Decl.As_Subp_Body.F_Subp_Spec;
         begin
            if Spec.Is_Null then
               return Comment_Region_Vectors.Empty_Vector;
            end if;

            Blocks :=
              Comments.Interior_Blocks
                (From => Spec.Token_End, To => Decl.Token_End);
         exception
            when Property_Error | Precondition_Failure =>
               return Comment_Region_Vectors.Empty_Vector;
         end;

         for Block of Blocks loop
            Result.Append
              (Comment_Region'
                 (Text       => Block.Text,
                  First_Line => Block.First_Line,
                  Last_Line  => Block.Last_Line,
                  Tags       =>
                    Gnatdoc_Tags.Parse (Block, Model.Leading).Tags));
         end loop;

         return Result;
      end Interior_Comments;

      ---------------------
      -- Is_First_Aspect --
      ---------------------

      function Is_First_Aspect (Node : Ada_Node'Class) return Boolean is
         List : constant Ada_Node := Node.Parent;
      begin
         return
           not List.Is_Null
           and then List.Kind = Ada_Aspect_Assoc_List
           and then List.Children_Count > 0
           and then List.Child (1) = Node.As_Ada_Node;
      end Is_First_Aspect;

      ------------------
      -- Record_Check --
      ------------------

      procedure Record_Check
        (Node : Ada_Node'Class; Kind : Check_Kind; Name : String)
      is
         Block : Comments.Comment_Block :=
           Comments.Leading_Block (Node.Token_Start);
         Info  : Check_Info;
      begin
         --  A first aspect may be tagged above the `with` that opens the
         --  aspect list, which is how a one-line `with Post => ...` reads.

         if Comments.Is_Empty (Block)
           and then Kind = An_Aspect
           and then Is_First_Aspect (Node)
           and then not Node.Parent.Parent.Is_Null
         then
            Block := Comments.Leading_Block (Node.Parent.Parent.Token_Start);
         end if;

         if Comments.Is_Empty (Block) then
            return;
         end if;

         for Tag of Gnatdoc_Tags.Parse (Block, Model.Leading).Tags loop
            if To_String (Tag.Tag) = "covers" then
               Info.Covers.Append (Tag.Text);
            end if;
         end loop;

         if Info.Covers.Is_Empty then
            return;
         end if;

         declare
            Sloc : constant Source_Location_Range := Sloc_Range (Node);
         begin
            Info.Kind := Kind;
            Info.Name := To_Unbounded_String (Name);
            Info.File := To_Unbounded_String (File);
            Info.Line := Natural (Sloc.Start_Line);
            Info.Column := Natural (Sloc.Start_Column);
         end;

         Into.Checks.Append (Info);
      end Record_Check;

      -----------------
      -- Scan_Checks --
      -----------------

      function Scan_Checks (Node : Ada_Node'Class) return Visit_Status is
      begin
         case Node.Kind is
            when Ada_Pragma_Node  =>
               Record_Check
                 (Node, A_Pragma, Node_Text (Node.As_Pragma_Node.F_Id));

            when Ada_Aspect_Assoc =>
               Record_Check
                 (Node, An_Aspect, Node_Text (Node.As_Aspect_Assoc.F_Id));

            when others           =>
               null;
         end case;

         return Libadalang.Common.Into;
      end Scan_Checks;

      --------------
      -- Register --
      --------------

      function Register
        (Decl       : Basic_Decl'Class;
         Anchor     : Ada_Node'Class;
         Is_Generic : Boolean;
         Site       : Declaration_Site) return Natural
      is
         Name : constant String := Qualified_Name (Decl);
      begin
         if Name = "" then
            return No_Owner;
         end if;

         declare
            Index       : constant Positive := Find_Or_Add (Into, Name);
            Entry_Value : Package_Info := Into.Packages (Index);
            Doc         : constant Documentation := Package_Doc (Anchor);
         begin
            case Site is
               when In_Spec =>
                  Entry_Value.Spec_File := To_Unbounded_String (File);
                  Entry_Value.Is_Generic := Is_Generic;

               when In_Body =>
                  Entry_Value.Body_File := To_Unbounded_String (File);
            end case;

            --  A body carries a header comment of its own; keep it only when
            --  the spec had none, so the spec's description wins.

            if Entry_Value.Doc.Source = No_Doc then
               Entry_Value.Doc := Doc;
            end if;

            Into.Packages.Replace_Element (Index, Entry_Value);

            return Index;
         end;
      end Register;

      -----------------------
      -- Record_Subprogram --
      -----------------------

      procedure Record_Subprogram
        (Decl   : Ada_Node'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site)
      is
         As_Decl : constant Basic_Decl := Decl.As_Basic_Decl;
         Sloc    : constant Source_Location_Range := Sloc_Range (Decl);
         Info    : Subprogram_Info;
         Spec    : Base_Subp_Spec;
      begin
         Info.Name := To_Unbounded_String (Simple_Name (As_Decl));
         Info.Qualified_Name := To_Unbounded_String (Qualified_Name (As_Decl));
         Info.Nested := Nested;
         Info.Is_Generic := Decl.Kind = Ada_Generic_Subp_Decl;
         Info.Is_Renaming := Decl.Kind = Ada_Subp_Renaming_Decl;
         Info.Is_Expression := Decl.Kind = Ada_Expr_Function;
         Info.Is_Abstract :=
           Decl.Kind in Ada_Abstract_Subp_Decl | Ada_Null_Subp_Decl;
         Info.Is_Body := Decl.Kind = Ada_Subp_Body;
         Info.Kind :=
           (if Decl.Kind = Ada_Entry_Decl then An_Entry else A_Procedure);
         Info.File := To_Unbounded_String (File);
         Info.Line := Natural (Sloc.Start_Line);
         Info.Column := Natural (Sloc.Start_Column);
         Info.Doc := Entity_Doc (Decl);
         Info.Body_Comments := Interior_Comments (Decl);

         --  A library-level subprogram sits in no package, so the site it was
         --  passed - which tracks the enclosing package's spec or body - says
         --  nothing. Read it off the declaration itself instead.

         Info.Declared_In :=
           (if Owner = No_Owner
            then
              (if Decl.Kind in Ada_Subp_Body | Ada_Subp_Body_Stub
               then In_Body
               else In_Spec)
            else Site);

         begin
            Spec := As_Decl.P_Subp_Spec_Or_Null;
         exception
            when Property_Error | Precondition_Failure =>
               Spec := No_Base_Subp_Spec;
         end;

         if not Spec.Is_Null then
            if Spec.Kind = Ada_Subp_Spec then
               Info.Kind :=
                 (if Spec.As_Subp_Spec.F_Subp_Kind.Kind
                    = Ada_Subp_Kind_Function
                  then A_Function
                  else A_Procedure);
            end if;

            Info.Return_Type :=
              To_Unbounded_String (Node_Text (Spec.P_Returns));

            for Parameter of Spec.P_Params loop
               for Formal of Parameter.F_Ids loop
                  Info.Parameters.Append
                    (Parameter_Info'
                       (Name      => To_Unbounded_String (Node_Text (Formal)),
                        Mode      =>
                          (case Parameter.F_Mode.Kind is
                             when Ada_Mode_In_Out => Model.Mode_In_Out,
                             when Ada_Mode_Out    => Model.Mode_Out,
                             when others          => Model.Mode_In),
                        Type_Name =>
                          To_Unbounded_String
                            (Node_Text (Parameter.F_Type_Expr))));
               end loop;
            end loop;
         end if;

         if Owner = No_Owner then
            Fold_Or_Append (Into.Library_Subprograms, Info);
         else
            Add_Subprogram (Owner, Info);
         end if;
      end Record_Subprogram;

      -------------------
      -- Record_Entity --
      -------------------

      procedure Record_Entity
        (Decl        : Ada_Node'Class;
         Name        : Defining_Name'Class;
         Kind        : Entity_Kind;
         Owner       : Positive;
         Site        : Declaration_Site;
         Is_Renaming : Boolean;
         Doc         : Documentation)
      is
         Sloc : constant Source_Location_Range := Sloc_Range (Decl);
         Info : Entity_Info;
      begin
         if Name.Is_Null then
            return;
         end if;

         Info.Name := To_Unbounded_String (Node_Text (Name));
         Info.Qualified_Name := To_Unbounded_String (Full_Name (Name));
         Info.Kind := Kind;
         Info.Declared_In := Site;
         Info.Is_Renaming := Is_Renaming;
         Info.File := To_Unbounded_String (File);
         Info.Line := Natural (Sloc.Start_Line);
         Info.Column := Natural (Sloc.Start_Column);
         Info.Doc := Doc;

         Add_Entity (Owner, Info);
      end Record_Entity;

      ---------------------
      -- Record_Entities --
      ---------------------

      procedure Record_Entities
        (Decl        : Ada_Node'Class;
         Names       : Defining_Name_List;
         Kind        : Entity_Kind;
         Owner       : Positive;
         Site        : Declaration_Site;
         Is_Renaming : Boolean := False)
      is
         Doc : constant Documentation := Entity_Doc (Decl);
      begin
         if Names.Is_Null then
            return;
         end if;

         for Name of Names loop
            Record_Entity (Decl, Name, Kind, Owner, Site, Is_Renaming, Doc);
         end loop;
      end Record_Entities;

      ---------------
      -- Walk_Part --
      ---------------

      procedure Walk_Part
        (Part   : Declarative_Part'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site) is
      begin
         if Part.Is_Null or else Part.F_Decls.Is_Null then
            return;
         end if;

         for Child of Part.F_Decls loop
            Walk_Decl (Child, Owner, Nested, Site);
         end loop;
      end Walk_Part;

      ---------------
      -- Walk_Decl --
      ---------------

      procedure Walk_Decl
        (Decl   : Ada_Node'Class;
         Owner  : Natural;
         Nested : Boolean;
         Site   : Declaration_Site) is
      begin
         if Decl.Is_Null then
            return;
         end if;

         case Decl.Kind is

            when Ada_Library_Item                          =>
               Walk_Decl (Decl.As_Library_Item.F_Item, Owner, Nested, Site);

            --  A generic package is a wrapper around the package proper. The
            --  header comment sits above the `generic` keyword, so the
            --  wrapper - not the inner declaration - is the anchor.

            when Ada_Generic_Package_Decl                  =>
               declare
                  Wrapper : constant Generic_Package_Decl :=
                    Decl.As_Generic_Package_Decl;
                  Inner   : constant Generic_Package_Internal :=
                    Wrapper.F_Package_Decl;
                  Index   : constant Natural :=
                    Register
                      (Inner,
                       Anchor     => Wrapper,
                       Is_Generic => True,
                       Site       => In_Spec);
               begin
                  if Index /= No_Owner then
                     Walk_Part (Inner.F_Public_Part, Index, Nested, In_Spec);
                     Walk_Part (Inner.F_Private_Part, Index, Nested, In_Spec);
                  end if;
               end;

            when Ada_Package_Decl                          =>
               declare
                  Spec  : constant Package_Decl := Decl.As_Package_Decl;
                  Index : constant Natural :=
                    Register
                      (Spec,
                       Anchor     => Spec,
                       Is_Generic => False,
                       Site       => In_Spec);
               begin
                  if Index /= No_Owner then
                     Walk_Part (Spec.F_Public_Part, Index, Nested, In_Spec);
                     Walk_Part (Spec.F_Private_Part, Index, Nested, In_Spec);
                  end if;
               end;

            when Ada_Package_Body                          =>
               if not Setting.Specs_Only then
                  declare
                     Unit_Body : constant Package_Body := Decl.As_Package_Body;
                     Index     : constant Natural :=
                       Register
                         (Unit_Body,
                          Anchor     => Unit_Body,
                          Is_Generic => False,
                          Site       => In_Body);
                  begin
                     if Index /= No_Owner then
                        Walk_Part (Unit_Body.F_Decls, Index, Nested, In_Body);
                     end if;
                  end;
               end if;

            when Ada_Subp_Decl
               | Ada_Abstract_Subp_Decl
               | Ada_Null_Subp_Decl
               | Ada_Expr_Function
               | Ada_Subp_Body
               | Ada_Subp_Body_Stub
               | Ada_Subp_Renaming_Decl
               | Ada_Generic_Subp_Decl
               | Ada_Entry_Decl                            =>
               --  A subprogram with `No_Owner` is a compilation unit of its
               --  own - `main.adb`'s `Main`, or a library-level generic
               --  procedure. `Record_Subprogram` files those separately.

               if Owner /= No_Owner
                 or else not Setting.Specs_Only
                 or else Decl.Kind not in Ada_Subp_Body | Ada_Subp_Body_Stub
               then
                  Record_Subprogram (Decl, Owner, Nested, Site);

                  --  A subprogram body may declare further subprograms. They
                  --  are reported, flagged as nested, so that an LLR pointing
                  --  at a body-local helper still resolves.

                  if Decl.Kind = Ada_Subp_Body then
                     Walk_Part (Decl.As_Subp_Body.F_Decls, Owner, True, Site);
                  end if;
               end if;

            --  Types, objects and exceptions. About half of this repository's
            --  LLR `implemented_by:` refs name one of these rather than a
            --  subprogram, so leaving them out would leave those refs with
            --  nothing to resolve against.

            when Ada_Concrete_Type_Decl | Ada_Subtype_Decl =>
               if Owner /= No_Owner then
                  Record_Entity
                    (Decl,
                     Decl.As_Base_Type_Decl.F_Name,
                     (if Decl.Kind = Ada_Subtype_Decl
                      then A_Subtype
                      else A_Type),
                     Owner,
                     Site,
                     Is_Renaming => False,
                     Doc         => Entity_Doc (Decl));
               end if;

            when Ada_Object_Decl                           =>
               if Owner /= No_Owner then
                  declare
                     Object : constant Object_Decl := Decl.As_Object_Decl;
                  begin
                     Record_Entities
                       (Decl,
                        Object.F_Ids,
                        (if Object.F_Has_Constant
                         then A_Constant
                         else A_Variable),
                        Owner,
                        Site,
                        Is_Renaming => not Object.F_Renaming_Clause.Is_Null);
                  end;
               end if;

            --  `X : constant := 3` has no subtype mark, so Libadalang gives it
            --  a node of its own. It is a constant all the same.

            when Ada_Number_Decl                           =>
               if Owner /= No_Owner then
                  Record_Entities
                    (Decl, Decl.As_Number_Decl.F_Ids, A_Constant, Owner, Site);
               end if;

            when Ada_Exception_Decl                        =>
               if Owner /= No_Owner then
                  declare
                     Raised : constant Exception_Decl :=
                       Decl.As_Exception_Decl;
                  begin
                     Record_Entities
                       (Decl,
                        Raised.F_Ids,
                        An_Exception,
                        Owner,
                        Site,
                        Is_Renaming => not Raised.F_Renames.Is_Null);
                  end;
               end if;

            when others                                    =>
               null;
         end case;
      end Walk_Decl;

      Root : constant Ada_Node := Source.Root;

   begin
      if Root.Is_Null then
         return;
      end if;

      case Root.Kind is
         when Ada_Compilation_Unit      =>
            Walk_Decl
              (Root.As_Compilation_Unit.F_Body, No_Owner, False, In_Spec);

         when Ada_Compilation_Unit_List =>
            for Child of Root.As_Compilation_Unit_List loop
               Walk_Decl (Child.F_Body, No_Owner, False, In_Spec);
            end loop;

         when others                    =>
            null;
      end case;

      --  Flat, unlike the walk above: a check anchors evidence wherever it sits.

      Root.Traverse (Scan_Checks'Access);
   end Unit;

end Ada_Tracer.Walk;
