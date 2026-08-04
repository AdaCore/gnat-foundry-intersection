--  Root package of `ada_tracer`, the Libadalang-based extractor that emits a
--  JSON inventory of the packages, subprograms and documentation comments of
--  an Ada project.
--
--  This package holds only the vocabulary shared by the child packages; all
--  behaviour lives in the children:
--
--    * `Ada_Tracer.Comments`     - associate comment trivia with declarations
--    * `Ada_Tracer.Gnatdoc_Tags` - parse `@param` / `@return` / ... tags
--    * `Ada_Tracer.Model`        - the Libadalang-free in-memory result
--    * `Ada_Tracer.Walk`         - traverse the units and populate the model
--    * `Ada_Tracer.Emit`         - serialize the model to JSON
--
--  Loading the project and enumerating its units is not ours: that is
--  `Libadalang.Helpers.App`, instantiated in `Ada_Tracer.Main`.
--
--  Nothing here declares a failure vocabulary either. Parse diagnostics are
--  not fatal -- they go to standard error and the run continues -- and the one
--  condition that is (an unwritable output file) is reported on standard error
--  by `Main` with a non-zero exit status, rather than raised.

package Ada_Tracer is

   Schema_Version : constant := 2;
   --  Version of the emitted JSON document. Bump on any incompatible change
   --  to the shape described in `json_schema.md`.

end Ada_Tracer;
