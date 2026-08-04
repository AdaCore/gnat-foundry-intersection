with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Ada_Tracer.Gnatdoc_Tags is

   use Ada_Tracer.Model;

   LF : constant Character := Character'Val (10);

   type Tag_Name_Entry is record
      Name : access constant String;
      Kind : Tag_Kind;
   end record;
   --  One entry of the recognised-tag table.
   --  @field Name The tag word, without its `@`
   --  @field Kind The kind it maps to

   Param_Name  : aliased constant String := "param";
   Return_Name : aliased constant String := "return";
   Field_Name  : aliased constant String := "field";
   Enum_Name   : aliased constant String := "enum";

   Known_Tags : constant array (Positive range <>) of Tag_Name_Entry :=
     [(Param_Name'Access, Param_Tag),
      (Return_Name'Access, Return_Tag),
      (Field_Name'Access, Field_Tag),
      (Enum_Name'Access, Enum_Tag)];
   --  The tags `design/code_conventions.md` lists. Anything else parses as
   --  `Other_Tag`.

   function Trim (Text : String) return String;
   --  Strip the leading and trailing whitespace from a line.
   --  @param Text The line to trim
   --  @return The trimmed line

   function Classify (Word : String) return Tag_Kind;
   --  Map a tag word to its kind.
   --  @param Word The tag word, without its `@`
   --  @return The matching kind, or `Other_Tag`

   function Takes_A_Name (Kind : Tag_Kind) return Boolean;
   --  Whether a tag's first word names the entity it documents.
   --  @param Kind The tag kind
   --  @return True for `@param`, `@field` and `@enum`

   procedure Split_Word
     (Text : String; Word : out Unbounded_String; Rest : out Unbounded_String);
   --  Peel the first whitespace-delimited word off a line.
   --  @param Text The line to split
   --  @param Word Its first word, empty when the line is blank
   --  @param Rest What follows, with its leading whitespace removed

   procedure Append_Line (Target : in out Unbounded_String; Line : String);
   --  Append a line to an accumulating block, inserting a separator when the
   --  block is not empty.
   --  @param Target The block to extend
   --  @param Line The line to add

   ----------
   -- Trim --
   ----------

   function Trim (Text : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both);
   end Trim;

   --------------
   -- Classify --
   --------------

   function Classify (Word : String) return Tag_Kind is
   begin
      for Known of Known_Tags loop
         if Word = Known.Name.all then
            return Known.Kind;
         end if;
      end loop;

      return Other_Tag;
   end Classify;

   ------------------
   -- Takes_A_Name --
   ------------------

   function Takes_A_Name (Kind : Tag_Kind) return Boolean is
   begin
      return Kind in Param_Tag | Field_Tag | Enum_Tag;
   end Takes_A_Name;

   ----------------
   -- Split_Word --
   ----------------

   procedure Split_Word
     (Text : String; Word : out Unbounded_String; Rest : out Unbounded_String)
   is
      Trimmed : constant String := Trim (Text);
      Space   : Natural;
   begin
      if Trimmed = "" then
         Word := Null_Unbounded_String;
         Rest := Null_Unbounded_String;
         return;
      end if;

      Space := Ada.Strings.Fixed.Index (Trimmed, " ");

      if Space = 0 then
         Word := To_Unbounded_String (Trimmed);
         Rest := Null_Unbounded_String;
      else
         Word := To_Unbounded_String (Trimmed (Trimmed'First .. Space - 1));
         Rest :=
           To_Unbounded_String (Trim (Trimmed (Space + 1 .. Trimmed'Last)));
      end if;
   end Split_Word;

   -----------------
   -- Append_Line --
   -----------------

   procedure Append_Line (Target : in out Unbounded_String; Line : String) is
   begin
      if Length (Target) > 0 then
         Append (Target, LF);
      end if;

      Append (Target, Line);
   end Append_Line;

   -----------
   -- Parse --
   -----------

   function Parse
     (Block : Comments.Comment_Block; Source : Model.Doc_Source)
      return Model.Documentation
   is
      Raw    : constant String := To_String (Block.Text);
      Result : Documentation;
      First  : Positive := Raw'First;
      In_Tag : Boolean := False;

      Line_No : Natural := Block.First_Line;
      --  The source line `First` sits on. `Assemble` joins the block's comment
      --  tokens with one LF each and a block never spans a blank line, so the
      --  block's lines and the source's run in step.

   begin
      if Comments.Is_Empty (Block) then
         return No_Documentation;
      end if;

      Result.Text := Block.Text;
      Result.Source := Source;

      --  Walk the block a line at a time. A line whose first non-blank
      --  character is `@` opens a new tag; any other line extends whatever is
      --  currently open - the description to begin with, then the last tag.

      while First <= Raw'Last + 1 loop
         declare
            Stop      : Natural := Ada.Strings.Fixed.Index (Raw, [LF], First);
            Line      : constant String :=
              (if Stop = 0
               then Raw (First .. Raw'Last)
               else Raw (First .. Stop - 1));
            Body_Text : constant String := Trim (Line);
         begin
            if Stop = 0 then
               Stop := Raw'Last + 1;
            end if;

            if Body_Text'Length > 0 and then Body_Text (Body_Text'First) = '@'
            then
               declare
                  Without_At : constant String :=
                    Body_Text (Body_Text'First + 1 .. Body_Text'Last);
                  Word, Rest : Unbounded_String;
                  Tag        : Doc_Tag;
               begin
                  Split_Word (Without_At, Word, Rest);
                  Tag.Tag := Word;
                  Tag.Kind := Classify (To_String (Word));
                  Tag.Line := Line_No;

                  if Takes_A_Name (Tag.Kind) then
                     declare
                        Name, Prose : Unbounded_String;
                     begin
                        Split_Word (To_String (Rest), Name, Prose);
                        Tag.Name := Name;
                        Tag.Text := Prose;
                     end;
                  else
                     Tag.Text := Rest;
                  end if;

                  Result.Tags.Append (Tag);
                  In_Tag := True;
               end;

            elsif In_Tag then
               declare
                  Last : constant Positive := Result.Tags.Last_Index;
                  Tag  : Doc_Tag := Result.Tags (Last);
               begin
                  if Body_Text'Length > 0 then
                     if Length (Tag.Text) > 0 then
                        Append (Tag.Text, " ");
                     end if;

                     Append (Tag.Text, Body_Text);
                     Result.Tags.Replace_Element (Last, Tag);
                  end if;
               end;

            else
               Append_Line (Result.Description, Line);
            end if;

            exit when Stop > Raw'Last;
            First := Stop + 1;
            Line_No := Line_No + 1;
         end;
      end loop;

      Result.Description :=
        To_Unbounded_String (Trim (To_String (Result.Description)));

      return Result;
   end Parse;

   -----------
   -- Merge --
   -----------

   function Merge
     (Leading, Trailing : Comments.Comment_Block) return Model.Documentation
   is
      Has_Leading  : constant Boolean := not Comments.Is_Empty (Leading);
      Has_Trailing : constant Boolean := not Comments.Is_Empty (Trailing);
   begin
      if Has_Leading and then Has_Trailing then
         declare
            Combined : Comments.Comment_Block := Trailing;
         begin
            Combined.Text := Leading.Text & LF & Trailing.Text;
            Combined.First_Line := Leading.First_Line;

            return Parse (Combined, Both);
         end;

      elsif Has_Trailing then
         return Parse (Trailing, Model.Trailing);

      elsif Has_Leading then
         return Parse (Leading, Model.Leading);

      else
         return No_Documentation;
      end if;
   end Merge;

end Ada_Tracer.Gnatdoc_Tags;
