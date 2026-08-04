--  Parsing of the gnatdoc tags `design/code_conventions.md` mandates out of a
--  comment block: `@param`, `@return`, `@field` and `@enum`.
--
--  A tag opens at the start of a line and runs until the next tag line or the
--  end of the block, so its prose may span several lines. Everything before
--  the first tag is the entity's description.
--
--  An unrecognised `@tag` is recorded as `Other_Tag` rather than rejected.
--  This is where `Libadalang.Doc_Utils` gives up - it raises `Property_Error`
--  on any tag outside its own three-name whitelist - and the reason this
--  parser exists at all.

with Ada_Tracer.Comments;
with Ada_Tracer.Model;

package Ada_Tracer.Gnatdoc_Tags is

   function Parse
     (Block : Comments.Comment_Block; Source : Model.Doc_Source)
      return Model.Documentation;
   --  Split a comment block into its description and its tags.
   --  @param Block The block to parse; an empty one yields no documentation
   --  @param Source Where the block was found, recorded as-is in the result
   --  @return The block's raw text alongside the parsed view of it

   function Merge
     (Leading, Trailing : Comments.Comment_Block) return Model.Documentation;
   --  Parse whichever blocks are present, concatenating them when a
   --  declaration carries documentation on both sides.
   --  @param Leading The block found above the declaration
   --  @param Trailing The block found below it
   --  @return The combined documentation, with `Source` set accordingly

end Ada_Tracer.Gnatdoc_Tags;
