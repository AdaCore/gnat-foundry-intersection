--  Association of comment trivia with the declarations they document.
--
--  `Libadalang.Doc_Utils` already encodes this repository's placement
--  convention, but it is unusable here: `Extract_Doc_From` treats any comment
--  line starting with `@` as an annotation and accepts only `belongs-to`,
--  `exclude` and `exclude-value`, raising `Property_Error` on anything else.
--  `design/code_conventions.md` mandates `@param`, `@return`, `@field` and
--  `@enum`, so it would raise on nearly every documented subprogram in the
--  tree. Its own header also declares the API experimental and unsupported.
--  This package therefore reimplements the token walk, with two differences:
--  it never raises on odd formatting, and it looks in both directions.
--
--  Both directions are needed because the codebase documents specs and bodies
--  differently. `design/code_conventions.md` puts documentation *after* the
--  specification, which `src/core/conflicts.ads` follows; bodies invert it and
--  put the comment above the subprogram, as `src/core/controller.adb` does.
--
--  A third mode, `Interior_Blocks`, collects the comments *inside* a body. It
--  documents nothing, and the package learns nothing about what such comments
--  mean; it exists because a convention may put a machine-readable tag there
--  rather than around the declaration. The GNATtest `--@covers` tag is the
--  case in hand: the routine's surroundings are regenerated boilerplate, so
--  the first editable line of the body is the only durable place for it.

with Ada.Containers.Vectors;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Libadalang.Common; use Libadalang.Common;

package Ada_Tracer.Comments is

   type Comment_Block is record
      Text       : Unbounded_String;
      First_Line : Natural := 0;
      Last_Line  : Natural := 0;
   end record;
   --  A run of consecutive comment lines.
   --  @field Text The lines with their `--` markers and the block's common
   --    indentation removed, joined with LF
   --  @field First_Line The line the first comment of the block sits on; 0
   --    when the block is empty
   --  @field Last_Line The line the last comment of the block sits on; 0 when
   --    the block is empty

   package Comment_Block_Vectors is new
     Ada.Containers.Vectors (Positive, Comment_Block);

   Empty_Block : constant Comment_Block;

   function Is_Empty (Block : Comment_Block) return Boolean;
   --  Whether no comment was associated.
   --  @param Block The block to test
   --  @return True when the block holds no comment line

   function Trailing_Block (After : Token_Reference) return Comment_Block;
   --  The comment block that follows `After` on the lines below it - the
   --  convention `design/code_conventions.md` mandates for specs.
   --
   --  A comment on the *same* line as `After` is an end-of-line remark, not
   --  documentation, and is rejected: `src/core/controller.adb` is full of
   --  them (`when N_Lead => --  .2 ...`). A blank line ends the association.
   --  @param After The declaration's last token, normally its `;`
   --  @return The block, or `Empty_Block` if there is none

   function Leading_Block
     (Before : Token_Reference; Skip_Blank_Lines : Boolean := False)
      return Comment_Block;
   --  The comment block immediately above `Before` - the convention bodies
   --  follow, and the one packages use for their header.
   --
   --  Section rulers (a comment whose payload is only dashes and spaces, as in
   --  `src/core/controller.adb`) terminate the block and are dropped, so a
   --  banner heading is never mistaken for a subprogram's documentation.
   --  @param Before The declaration's first token
   --  @param Skip_Blank_Lines Whether to look past a run of blank lines to
   --    reach the block. Needed only for a package header, which is separated
   --    from the compilation unit by the blank line above its context clause.
   --  @return The block, or `Empty_Block` if there is none

   function Interior_Blocks
     (From, To : Token_Reference) return Comment_Block_Vectors.Vector;
   --  Every comment block strictly between `From` and `To`, in source order -
   --  for a body, the comments between its `is` and its final `end`.
   --
   --  A vector rather than a single block because the interior of a body may
   --  hold several unrelated runs of comments, and a caller looking for a tag
   --  cannot know in advance which one carries it: in a GNATtest routine the
   --  first block is the generated `--  <spec>:<line>:<col>:<name>` /
   --  `--  end read only` pair and the tag sits in the second.
   --
   --  The rules `Trailing_Block` and `Leading_Block` apply are unchanged, only
   --  their effect differs: a blank line ends the current block and starts a
   --  new one rather than stopping the search, a section ruler does the same
   --  and is itself dropped, and an intervening code token also closes the
   --  current block. End-of-line remarks stay excluded -- a comment counts
   --  only when it opens its own line.
   --  @param From The token to start after, normally the last token of the
   --    body's specification
   --  @param To The token to stop at, normally the body's final `;`
   --  @return The blocks found, possibly empty; never holding an empty block

private

   Empty_Block : constant Comment_Block :=
     (Text => Null_Unbounded_String, First_Line => 0, Last_Line => 0);

end Ada_Tracer.Comments;
