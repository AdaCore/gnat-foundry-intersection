--  The in-memory result of a tracer run: packages, the subprograms they
--  declare, and the documentation attached to each.
--
--  No Libadalang type appears in this interface. `Ada_Tracer.Walk` fills the
--  model from the syntax tree and `Ada_Tracer.Emit` serializes it, so the two
--  halves of the tool can be reasoned about - and exercised - separately.

with Ada.Containers.Vectors;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package Ada_Tracer.Model is

   ---------------------
   --  Documentation  --
   ---------------------

   type Doc_Source is (No_Doc, Leading, Trailing, Both);
   --  Where a declaration's documentation was found relative to it.
   --  @enum No_Doc No documentation comment was associated
   --  @enum Leading The comment block sits immediately above the declaration
   --  @enum Trailing The comment block follows the declaration
   --  @enum Both Comment blocks were found on both sides and concatenated

   type Tag_Kind is (Param_Tag, Return_Tag, Field_Tag, Enum_Tag, Other_Tag);
   --  The gnatdoc tags `design/code_conventions.md` mandates, plus a
   --  catch-all.
   --  @enum Param_Tag `@param <Name> <text>`
   --  @enum Return_Tag `@return <text>`
   --  @enum Field_Tag `@field <Name> <text>`
   --  @enum Enum_Tag `@enum <Name> <text>`
   --  @enum Other_Tag Any other `@tag`, preserved verbatim, not rejected

   type Doc_Tag is record
      Kind : Tag_Kind := Other_Tag;
      Tag  : Unbounded_String;
      Name : Unbounded_String;
      Text : Unbounded_String;
      Line : Natural := 0;
   end record;
   --  One parsed gnatdoc tag.
   --  @field Kind Which tag this is
   --  @field Tag The tag word as written, without the `@`
   --  @field Name The entity the tag documents; empty for `@return` and
   --    for unknown tags, which take no name
   --  @field Text The tag's prose, with continuation lines folded in
   --  @field Line The source line the tag word is written on, so a diagnostic
   --    about a tag can point at the tag rather than at the declaration. It is
   --    counted from the block's `First_Line`, which is exact for a block
   --    parsed on its own; for a `Both` documentation the two halves were
   --    concatenated before parsing, so tags past the seam are off by the span
   --    of the declaration between them

   package Tag_Vectors is new Ada.Containers.Vectors (Positive, Doc_Tag);

   type Documentation is record
      Text        : Unbounded_String;
      Source      : Doc_Source := No_Doc;
      Description : Unbounded_String;
      Tags        : Tag_Vectors.Vector;
   end record;
   --  A declaration's documentation, both raw and parsed.
   --  @field Text The verbatim comment block: `--` markers and the common
   --    indentation removed, lines joined with LF
   --  @field Source Where the block was found
   --  @field Description The free prose before the first tag line
   --  @field Tags The parsed gnatdoc tags, in source order

   No_Documentation : constant Documentation;

   type Comment_Region is record
      Text       : Unbounded_String;
      First_Line : Natural := 0;
      Last_Line  : Natural := 0;
      Tags       : Tag_Vectors.Vector;
   end record;
   --  A run of comment lines that documents nothing, kept for the tags it may
   --  carry - see `Comments.Interior_Blocks`. It is deliberately not a
   --  `Documentation`: there is no declaration here for a description to be
   --  *about*, and its tags may repeat, which `Documentation`'s consumers
   --  assume they do not.
   --  @field Text The verbatim block: `--` markers and the common indentation
   --    removed, lines joined with LF
   --  @field First_Line The line the block's first comment sits on
   --  @field Last_Line The line the block's last comment sits on
   --  @field Tags The tags parsed out of it, in source order, repetitions kept

   package Comment_Region_Vectors is new
     Ada.Containers.Vectors (Positive, Comment_Region);

   ------------------
   --  Subprograms  --
   ------------------

   type Parameter_Mode is (Mode_In, Mode_In_Out, Mode_Out);
   --  A formal parameter's mode. An absent mode is normalised to `Mode_In`.

   type Parameter_Info is record
      Name      : Unbounded_String;
      Mode      : Parameter_Mode := Mode_In;
      Type_Name : Unbounded_String;
   end record;
   --  One formal parameter. A multi-identifier `Param_Spec` such as
   --  `(A, B : Movement)` yields one `Parameter_Info` per identifier.
   --  @field Name The formal's name
   --  @field Mode Its mode
   --  @field Type_Name The type expression, as written in the source

   package Parameter_Vectors is new
     Ada.Containers.Vectors (Positive, Parameter_Info);

   type Subprogram_Kind is (A_Procedure, A_Function, An_Entry);
   --  What sort of callable this is.

   type Declaration_Site is (In_Spec, In_Body);
   --  Whether the declaration was found in a package spec or a package body.

   type Subprogram_Info is record
      Name           : Unbounded_String;
      Qualified_Name : Unbounded_String;
      Kind           : Subprogram_Kind := A_Procedure;
      Declared_In    : Declaration_Site := In_Spec;
      Nested         : Boolean := False;
      Has_Body       : Boolean := False;
      Is_Generic     : Boolean := False;
      Is_Renaming    : Boolean := False;
      Is_Expression  : Boolean := False;
      Is_Abstract    : Boolean := False;
      Is_Body        : Boolean := False;
      Parameters     : Parameter_Vectors.Vector;
      Return_Type    : Unbounded_String;
      File           : Unbounded_String;
      Line           : Natural := 0;
      Column         : Natural := 0;
      Doc            : Documentation;
      Body_Comments  : Comment_Region_Vectors.Vector;
   end record;
   --  One subprogram (or entry) declared in a package.
   --  @field Name The simple name
   --  @field Qualified_Name The fully qualified name, for instance
   --    `Conflicts.Compatible`
   --  @field Kind Procedure, function or entry
   --  @field Declared_In Which part of the package it was found in
   --  @field Nested True when an enclosing subprogram body sits between this
   --    declaration and its package
   --  @field Has_Body True when a spec declaration is completed by a body
   --  @field Is_Generic True for a generic subprogram declaration
   --  @field Is_Renaming True for a renaming declaration
   --  @field Is_Expression True for an expression function
   --  @field Is_Abstract True for an abstract or null subprogram declaration
   --  @field Is_Body True when this entry *is* a subprogram body, rather than
   --    a declaration completed by one elsewhere (`Has_Body`) or found in a
   --    package body (`Declared_In`). A routine written out as a forward
   --    declaration, a `renames` alias and a body yields three entries, and
   --    `Is_Body and not Is_Renaming` is what picks the body out
   --  @field Parameters The formal parameters, flattened, in source order
   --  @field Return_Type The return type expression; empty for a procedure
   --  @field File The source file, relative to the run's base directory
   --  @field Line The line the declaration starts on
   --  @field Column The column the declaration starts at
   --  @field Doc The documentation associated with the declaration
   --  @field Body_Comments For a body, the comment blocks inside it, in source
   --    order; empty otherwise. See `Comments.Interior_Blocks`

   package Subprogram_Vectors is new
     Ada.Containers.Vectors (Positive, Subprogram_Info);

   ----------------
   --  Entities  --
   ----------------

   type Entity_Kind is
     (A_Type, A_Subtype, A_Constant, A_Variable, An_Exception);
   --  What sort of non-callable declaration this is.
   --  @enum A_Type A type declaration
   --  @enum A_Subtype A subtype declaration
   --  @enum A_Constant An object declared `constant`, or a named number
   --  @enum A_Variable Any other object declaration
   --  @enum An_Exception An exception declaration

   type Entity_Info is record
      Name           : Unbounded_String;
      Qualified_Name : Unbounded_String;
      Kind           : Entity_Kind := A_Type;
      Declared_In    : Declaration_Site := In_Spec;
      Is_Renaming    : Boolean := False;
      File           : Unbounded_String;
      Line           : Natural := 0;
      Column         : Natural := 0;
      Doc            : Documentation;
   end record;
   --  One type, subtype, object or exception declared in a package.
   --
   --  Reported because a requirement names whatever realizes it, and about
   --  half of this repository's LLR `implemented_by:` refs name a type, a
   --  subtype or a constant rather than a subprogram. A declaration such
   --  as `A, B : Integer;` yields one entry per identifier, as for parameters.
   --  @field Name The simple name
   --  @field Qualified_Name The fully qualified name, for instance
   --    `States.Movement`
   --  @field Kind Type, subtype, constant, variable or exception
   --  @field Declared_In Which part of the package it was found in
   --  @field Is_Renaming True for an object or exception renaming declaration
   --  @field File The source file, relative to the run's base directory
   --  @field Line The line the declaration starts on
   --  @field Column The column the declaration starts at
   --  @field Doc The documentation associated with the declaration

   package Entity_Vectors is new
     Ada.Containers.Vectors (Positive, Entity_Info);

   ----------------
   --  Packages  --
   ----------------

   type Package_Info is record
      Name        : Unbounded_String;
      Spec_File   : Unbounded_String;
      Body_File   : Unbounded_String;
      Is_Generic  : Boolean := False;
      Doc         : Documentation;
      Subprograms : Subprogram_Vectors.Vector;
      Entities    : Entity_Vectors.Vector;
   end record;
   --  One package, with its spec and body merged into a single entry.
   --  @field Name The fully qualified package name
   --  @field Spec_File The file declaring the package; empty if only a body
   --    was seen
   --  @field Body_File The file holding its body; empty if it has none
   --  @field Is_Generic True for a generic package declaration
   --  @field Doc The package's header documentation
   --  @field Subprograms Its subprograms, in the order they were encountered
   --  @field Entities Its types, subtypes, objects and exceptions, in the
   --    order they were encountered

   package Package_Vectors is new
     Ada.Containers.Vectors (Positive, Package_Info);

   package Package_Index_Maps is new
     Ada.Containers.Indefinite_Ordered_Maps (String, Positive);

   type Project_Info is record
      Project             : Unbounded_String;
      Packages            : Package_Vectors.Vector;
      Library_Subprograms : Subprogram_Vectors.Vector;
      Index               : Package_Index_Maps.Map;
   end record;
   --  Everything the tool extracted from one project.
   --  @field Project The project file the run was given
   --  @field Packages The packages found, keyed positionally by `Index`
   --  @field Library_Subprograms The subprograms that are compilation units in
   --    their own right and so belong to no package - `main.adb`'s `Main`, or
   --    a library-level generic procedure. The tool's unit of output is the
   --    package, and these are the exception: a requirement may name one, so
   --    dropping them would leave a ref with nothing to resolve against
   --  @field Index Maps a fully qualified package name to its position in
   --    `Packages`, so `Walk` can merge a spec and its body in one pass

   function Find_Or_Add
     (Self : in out Project_Info; Name : String) return Positive;
   --  Return the index of the package called `Name`, creating an empty entry
   --  for it if this is the first time it is seen.
   --  @param Self The project being populated
   --  @param Name The fully qualified package name
   --  @return Its position in `Self.Packages`

   procedure Sort_By_Name (Self : in out Project_Info);
   --  Sort the packages by name so that successive runs diff cleanly. This
   --  invalidates `Self.Index`, so call it only once population is complete.
   --  @param Self The project to sort

private

   No_Documentation : constant Documentation :=
     (Text        => Null_Unbounded_String,
      Source      => No_Doc,
      Description => Null_Unbounded_String,
      Tags        => Tag_Vectors.Empty_Vector);

end Ada_Tracer.Model;
