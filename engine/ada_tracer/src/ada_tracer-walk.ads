--  Traversal of an analysis unit, populating `Ada_Tracer.Model`.
--
--  The descent is explicit rather than a flat `Traverse` or `Find`, because
--  what the tool reports is a *containment* relation - which package declares
--  which subprogram - and a flat node list throws that away.
--
--  No Libadalang value escapes into the model: everything is converted to
--  UTF-8 text here. Holding a node or token past its context's lifetime would
--  raise `Stale_Reference_Error`.
--
--  Only syntactic properties are used (`P_Fully_Qualified_Name`,
--  `P_Subp_Spec_Or_Null`, `P_Params`, and the raw `Text` of a type
--  expression). Nothing here triggers name resolution, so the tool works on a
--  project whose dependencies do not all resolve, and every such call is
--  guarded anyway.

with Ada.Strings.Unbounded;

with Libadalang.Analysis; use Libadalang.Analysis;

with Ada_Tracer.Model;

package Ada_Tracer.Walk is

   type Options is record
      Specs_Only : Boolean := False;
      Base_Dir   : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   --  How to traverse.
   --  @field Specs_Only Skip package bodies and the subprograms they declare
   --  @field Base_Dir Directory that reported file names are relative to

   procedure Unit
     (Into    : in out Model.Project_Info;
      Source  : Analysis_Unit;
      Setting : Options);
   --  Add everything `Source` declares to `Into`, merging a package spec and
   --  its body into one entry.
   --  @param Into The project being populated
   --  @param Source The unit to traverse
   --  @param Setting The traversal options

end Ada_Tracer.Walk;
