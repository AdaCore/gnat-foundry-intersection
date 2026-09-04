with Ada.Strings.Fixed;

with Langkit_Support.Text;

package body Ada_Tracer.Comments is

   package Line_Vectors is new
     Ada.Containers.Vectors (Positive, Unbounded_String);

   Comment_Marker_Length : constant := 2;
   --  The length of the `--` that introduces a comment token.

   Minimum_Ruler_Dashes : constant := 3;
   --  How many dashes a comment made only of dashes and spaces must have
   --  before it counts as a section ruler rather than as prose.

   LF : constant Character := Character'Val (10);

   function Line_Feeds (Text : String) return Natural;
   --  Count the line terminators in a whitespace token's text.
   --  @param Text The token's text
   --  @return The number of LF characters it contains

   function Strip_Marker (Comment : String) return String;
   --  Remove the leading `--` from a comment token's text.
   --  @param Comment The token's text
   --  @return The remainder, indentation included

   function Is_Ruler (Payload : String) return Boolean;
   --  Whether a marker-stripped comment is a section ruler.
   --  @param Payload The comment without its `--`
   --  @return True when it holds only dashes and spaces, with enough dashes

   function Assemble
     (Lines : Line_Vectors.Vector; First, Last : Natural) return Comment_Block;
   --  Turn collected lines into a block, removing the indentation they share.
   --  @param Lines The marker-stripped lines, in source order
   --  @param First The line number of the first one
   --  @param Last The line number of the last one
   --  @return The assembled block

   function Token_Text (Token : Token_Reference) return String;
   --  A token's text as UTF-8.
   --  @param Token The token to read
   --  @return Its text

   function Start_Line (Token : Token_Reference) return Natural;
   --  The line a token starts on.
   --  @param Token The token to locate
   --  @return Its starting line number

   --------------
   -- Is_Empty --
   --------------

   function Is_Empty (Block : Comment_Block) return Boolean is
   begin
      return Block.First_Line = 0;
   end Is_Empty;

   ----------------
   -- Line_Feeds --
   ----------------

   function Line_Feeds (Text : String) return Natural is
      Count : Natural := 0;
   begin
      for C of Text loop
         if C = LF then
            Count := Count + 1;
         end if;
      end loop;

      return Count;
   end Line_Feeds;

   ------------------
   -- Strip_Marker --
   ------------------

   function Strip_Marker (Comment : String) return String is
   begin
      if Comment'Length <= Comment_Marker_Length then
         return "";
      end if;

      return Comment (Comment'First + Comment_Marker_Length .. Comment'Last);
   end Strip_Marker;

   --------------
   -- Is_Ruler --
   --------------

   function Is_Ruler (Payload : String) return Boolean is
      Dashes : Natural := 0;
   begin
      for C of Payload loop
         case C is
            when '-'                     =>
               Dashes := Dashes + 1;

            when ' ' | Character'Val (9) =>
               null;

            when others                  =>
               return False;
         end case;
      end loop;

      return Dashes >= Minimum_Ruler_Dashes;
   end Is_Ruler;

   --------------
   -- Assemble --
   --------------

   function Assemble
     (Lines : Line_Vectors.Vector; First, Last : Natural) return Comment_Block
   is
      Indent : Natural := Natural'Last;
      Result : Unbounded_String;
   begin
      if Lines.Is_Empty then
         return Empty_Block;
      end if;

      --  The shared indentation is the smallest one over the non-blank lines;
      --  blank lines must not drag it down to zero.

      for Line of Lines loop
         declare
            Raw     : constant String := To_String (Line);
            Trimmed : constant String :=
              Ada.Strings.Fixed.Trim (Raw, Ada.Strings.Both);
         begin
            if Trimmed'Length > 0 then
               Indent :=
                 Natural'Min
                   (Indent,
                    Ada.Strings.Fixed.Index_Non_Blank (Raw) - Raw'First);
            end if;
         end;
      end loop;

      if Indent = Natural'Last then
         Indent := 0;
      end if;

      for Position in Lines.First_Index .. Lines.Last_Index loop
         declare
            Raw : constant String := To_String (Lines (Position));
         begin
            if Raw'Length > Indent then
               Append (Result, Raw (Raw'First + Indent .. Raw'Last));
            end if;

            if Position /= Lines.Last_Index then
               Append (Result, LF);
            end if;
         end;
      end loop;

      return (Text => Result, First_Line => First, Last_Line => Last);
   end Assemble;

   ----------------
   -- Token_Text --
   ----------------

   function Token_Text (Token : Token_Reference) return String is
   begin
      return Langkit_Support.Text.To_UTF8 (Text (Token));
   end Token_Text;

   ----------------
   -- Start_Line --
   ----------------

   function Start_Line (Token : Token_Reference) return Natural is
   begin
      return Natural (Sloc_Range (Data (Token)).Start_Line);
   end Start_Line;

   --------------------
   -- Trailing_Block --
   --------------------

   function Trailing_Block (After : Token_Reference) return Comment_Block is
      Lines       : Line_Vectors.Vector;
      Token       : Token_Reference := After;
      First, Last : Natural := 0;
   begin
      if Token = No_Token then
         return Empty_Block;
      end if;

      --  Documentation starts on the line below the declaration. Requiring
      --  exactly one line terminator rejects both an end-of-line remark (no
      --  terminator between it and the declaration) and a comment cut off by
      --  a blank line (two or more).

      Token := Next (Token, Exclude_Trivia => False);

      if Token = No_Token
        or else Kind (Data (Token)) /= Ada_Whitespace
        or else Line_Feeds (Token_Text (Token)) /= 1
      then
         return Empty_Block;
      end if;

      Token := Next (Token, Exclude_Trivia => False);

      while Token /= No_Token loop
         case Kind (Data (Token)) is
            when Ada_Whitespace =>
               exit when Line_Feeds (Token_Text (Token)) > 1;

            when Ada_Comment    =>
               declare
                  Payload : constant String :=
                    Strip_Marker (Token_Text (Token));
               begin
                  exit when Is_Ruler (Payload);

                  if First = 0 then
                     First := Start_Line (Token);
                  end if;

                  Last := Start_Line (Token);
                  Lines.Append (To_Unbounded_String (Payload));
               end;

            when others         =>
               exit;
         end case;

         Token := Next (Token, Exclude_Trivia => False);
      end loop;

      return Assemble (Lines, First, Last);
   end Trailing_Block;

   -------------------
   -- Leading_Block --
   -------------------

   function Leading_Block
     (Before : Token_Reference; Skip_Blank_Lines : Boolean := False)
      return Comment_Block
   is
      Lines       : Line_Vectors.Vector;
      Token       : Token_Reference := Before;
      First, Last : Natural := 0;
   begin
      if Token = No_Token then
         return Empty_Block;
      end if;

      Token := Previous (Token, Exclude_Trivia => False);

      if Token = No_Token or else Kind (Data (Token)) /= Ada_Whitespace then
         return Empty_Block;
      end if;

      --  As above, one terminator means the comment is on the line directly
      --  overhead. A package header is the exception: it sits above the
      --  context clause, so a blank line separates it from the compilation
      --  unit and the caller asks us to look past it.

      if Line_Feeds (Token_Text (Token)) /= 1 and then not Skip_Blank_Lines
      then
         return Empty_Block;
      end if;

      Token := Previous (Token, Exclude_Trivia => False);

      while Token /= No_Token loop
         case Kind (Data (Token)) is
            when Ada_Whitespace =>
               exit when Line_Feeds (Token_Text (Token)) > 1;

            when Ada_Comment    =>
               --  An end-of-line remark belongs to the code on its line: stop.

               declare
                  Above : constant Token_Reference :=
                    Previous (Token, Exclude_Trivia => False);
               begin
                  exit when
                    Above /= No_Token
                    and then
                      (Kind (Data (Above)) /= Ada_Whitespace
                       or else Line_Feeds (Token_Text (Above)) = 0);
               end;

               declare
                  Payload : constant String :=
                    Strip_Marker (Token_Text (Token));
               begin
                  exit when Is_Ruler (Payload);

                  if Last = 0 then
                     Last := Start_Line (Token);
                  end if;

                  First := Start_Line (Token);
                  Lines.Prepend (To_Unbounded_String (Payload));
               end;

            when others         =>
               exit;
         end case;

         Token := Previous (Token, Exclude_Trivia => False);
      end loop;

      return Assemble (Lines, First, Last);
   end Leading_Block;

   ---------------------
   -- Interior_Blocks --
   ---------------------

   function Interior_Blocks
     (From, To : Token_Reference) return Comment_Block_Vectors.Vector
   is
      Result      : Comment_Block_Vectors.Vector;
      Lines       : Line_Vectors.Vector;
      Token       : Token_Reference := From;
      First, Last : Natural := 0;

      --  Whether the next comment token would open its own line. It does only
      --  when a line terminator has been crossed since the last comment or
      --  code token; otherwise the comment is an end-of-line remark on that
      --  token's line and is not documentation.

      Own_Line : Boolean := False;

      procedure Flush;
      --  Close the block being collected, appending it to the result unless it
      --  is empty, and start a fresh one.

      -----------
      -- Flush --
      -----------

      procedure Flush is
         Block : constant Comment_Block := Assemble (Lines, First, Last);
      begin
         if not Is_Empty (Block) then
            Result.Append (Block);
         end if;

         Lines.Clear;
         First := 0;
         Last := 0;
      end Flush;

   begin
      if Token = No_Token then
         return Comment_Block_Vectors.Empty_Vector;
      end if;

      loop
         Token := Next (Token, Exclude_Trivia => False);

         exit when Token = No_Token or else Token = To;

         case Kind (Data (Token)) is
            when Ada_Whitespace =>
               --  One terminator continues the run on the next line; a blank
               --  line separates two blocks.

               if Line_Feeds (Token_Text (Token)) > 1 then
                  Flush;
               end if;

               if Line_Feeds (Token_Text (Token)) > 0 then
                  Own_Line := True;
               end if;

            when Ada_Comment    =>
               if Own_Line then
                  declare
                     Payload : constant String :=
                       Strip_Marker (Token_Text (Token));
                  begin
                     if Is_Ruler (Payload) then
                        Flush;
                     else
                        if First = 0 then
                           First := Start_Line (Token);
                        end if;

                        Last := Start_Line (Token);
                        Lines.Append (To_Unbounded_String (Payload));
                     end if;
                  end;
               end if;

               Own_Line := False;

            when others         =>
               --  Code closes the run: what follows it is a new block.

               Flush;
               Own_Line := False;
         end case;
      end loop;

      Flush;

      return Result;
   end Interior_Blocks;

end Ada_Tracer.Comments;
