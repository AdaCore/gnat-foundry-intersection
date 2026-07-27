--  Root package of `ada_tracer`, the Libadalang-based extractor that emits a
--  JSON inventory of the packages, subprograms and documentation comments of
--  an Ada project.
--
--  This package holds only the vocabulary shared by the child packages; all
--  behaviour lives in the children:
--
--    * `Ada_Tracer.Project`      - load a `.gpr` and enumerate its units
--    * `Ada_Tracer.Comments`     - associate comment trivia with declarations
--    * `Ada_Tracer.Gnatdoc_Tags` - parse `@param` / `@return` / ... tags
--    * `Ada_Tracer.Model`        - the Libadalang-free in-memory result
--    * `Ada_Tracer.Walk`         - traverse the units and populate the model
--    * `Ada_Tracer.Emit`         - serialize the model to JSON

package Ada_Tracer is

   Schema_Version : constant := 2;
   --  Version of the emitted JSON document. Bump on any incompatible change
   --  to the shape described in `json_schema.md`.

   Tracer_Error : exception;
   --  Raised for conditions the tool cannot recover from (an unloadable
   --  project, an unwritable output file). Parse diagnostics are *not* fatal:
   --  they are reported on standard error and the run continues.

end Ada_Tracer;
