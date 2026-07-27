--  Serialization of `Ada_Tracer.Model` to the JSON document described in
--  `json_schema.md`.
--
--  Nothing here depends on Libadalang, so the emitted shape can be exercised
--  against a hand-built model without parsing anything.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Ada_Tracer.Model;

package Ada_Tracer.Emit is

   function To_JSON
     (Project : Model.Project_Info; Compact : Boolean := False)
      return Unbounded_String;
   --  Render a populated model.
   --  @param Project The model to serialize
   --  @param Compact Whether to emit one line rather than an indented document
   --  @return The JSON text

end Ada_Tracer.Emit;
