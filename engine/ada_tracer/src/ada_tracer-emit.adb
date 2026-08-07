with GNATCOLL.JSON; use GNATCOLL.JSON;

package body Ada_Tracer.Emit is

   use Ada_Tracer.Model;

   function Text_Or_Null (Value : Unbounded_String) return JSON_Value;
   --  A string field that is `null` rather than `""` when unset, so a
   --  consumer can tell "no body" from "a body whose name is empty".
   --  @param Value The value to render
   --  @return Its JSON representation

   function Image (Kind : Subprogram_Kind) return String;
   --  The wire name of a subprogram kind.
   --  @param Kind The kind to render
   --  @return Its lower-case name

   function Image (Site : Declaration_Site) return String;
   --  The wire name of a declaration site.
   --  @param Site The site to render
   --  @return Its lower-case name

   function Image (Mode : Parameter_Mode) return String;
   --  The wire name of a parameter mode.
   --  @param Mode The mode to render
   --  @return The Ada syntax for it

   function Image (Source : Doc_Source) return String;
   --  The wire name of a documentation source.
   --  @param Source The source to render
   --  @return Its lower-case name

   function Image (Kind : Entity_Kind) return String;
   --  The wire name of an entity kind.
   --  @param Kind The kind to render
   --  @return Its lower-case name

   function Image (Kind : Check_Kind) return String;
   --  The wire name of a check anchor's kind.
   --  @param Kind The kind to render
   --  @return Its lower-case name

   function To_JSON (Doc : Documentation) return JSON_Value;
   --  Render one documentation record.
   --  @param Doc The documentation to serialize
   --  @return Its JSON representation

   function To_JSON (Tag : Doc_Tag) return JSON_Value;
   --  Render one parsed tag, as an array element rather than as a field of an
   --  object keyed by tag word: a block may carry the same tag more than once
   --  and each occurrence has its own line.
   --  @param Tag The tag to serialize
   --  @return Its JSON representation

   function To_JSON (Region : Comment_Region) return JSON_Value;
   --  Render one interior comment block with its parsed tags.
   --  @param Region The block to serialize
   --  @return Its JSON representation

   function To_JSON (Info : Subprogram_Info) return JSON_Value;
   --  Render one subprogram.
   --  @param Info The subprogram to serialize
   --  @return Its JSON representation

   function To_JSON (Info : Entity_Info) return JSON_Value;
   --  Render one entity.
   --  @param Info The entity to serialize
   --  @return Its JSON representation

   function To_JSON (Info : Package_Info) return JSON_Value;
   --  Render one package.
   --  @param Info The package to serialize
   --  @return Its JSON representation

   function To_JSON (Info : Check_Info) return JSON_Value;
   --  Render one `--@covers`-tagged check.
   --  @param Info The check to serialize
   --  @return Its JSON representation

   ------------------
   -- Text_Or_Null --
   ------------------

   function Text_Or_Null (Value : Unbounded_String) return JSON_Value is
   begin
      if Length (Value) = 0 then
         return JSON_Null;
      end if;

      return Create (To_String (Value));
   end Text_Or_Null;

   -----------
   -- Image --
   -----------

   function Image (Kind : Subprogram_Kind) return String is
   begin
      return
        (case Kind is
           when A_Procedure => "procedure",
           when A_Function  => "function",
           when An_Entry    => "entry");
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Site : Declaration_Site) return String is
   begin
      return
        (case Site is
           when In_Spec => "spec",
           when In_Body => "body");
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Mode : Parameter_Mode) return String is
   begin
      return
        (case Mode is
           when Mode_In     => "in",
           when Mode_In_Out => "in out",
           when Mode_Out    => "out");
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Source : Doc_Source) return String is
   begin
      return
        (case Source is
           when No_Doc   => "none",
           when Leading  => "leading",
           when Trailing => "trailing",
           when Both     => "both");
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Kind : Entity_Kind) return String is
   begin
      return
        (case Kind is
           when A_Type       => "type",
           when A_Subtype    => "subtype",
           when A_Constant   => "constant",
           when A_Variable   => "variable",
           when An_Exception => "exception");
   end Image;

   -----------
   -- Image --
   -----------

   function Image (Kind : Check_Kind) return String is
   begin
      return
        (case Kind is
           when A_Pragma  => "pragma",
           when An_Aspect => "aspect");
   end Image;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Doc : Documentation) return JSON_Value is
      Result       : constant JSON_Value := Create_Object;
      Params       : constant JSON_Value := Create_Object;
      Others_Found : constant JSON_Value := Create_Object;
      Fields       : constant JSON_Value := Create_Object;
      Enums        : constant JSON_Value := Create_Object;
      Returns      : JSON_Value := JSON_Null;
   begin
      for Tag of Doc.Tags loop
         case Tag.Kind is
            when Param_Tag  =>
               Params.Set_Field (To_String (Tag.Name), To_String (Tag.Text));

            when Field_Tag  =>
               Fields.Set_Field (To_String (Tag.Name), To_String (Tag.Text));

            when Enum_Tag   =>
               Enums.Set_Field (To_String (Tag.Name), To_String (Tag.Text));

            when Return_Tag =>
               Returns := Create (To_String (Tag.Text));

            when Other_Tag  =>
               Others_Found.Set_Field
                 (To_String (Tag.Tag), To_String (Tag.Text));
         end case;
      end loop;

      Result.Set_Field ("text", To_String (Doc.Text));
      Result.Set_Field ("source", Image (Doc.Source));
      Result.Set_Field ("description", To_String (Doc.Description));
      Result.Set_Field ("params", Params);
      Result.Set_Field ("returns", Returns);
      Result.Set_Field ("fields", Fields);
      Result.Set_Field ("enums", Enums);
      Result.Set_Field ("other_tags", Others_Found);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Tag : Doc_Tag) return JSON_Value is
      Result : constant JSON_Value := Create_Object;
   begin
      Result.Set_Field ("tag", To_String (Tag.Tag));
      Result.Set_Field ("name", To_String (Tag.Name));
      Result.Set_Field ("text", To_String (Tag.Text));
      Result.Set_Field ("line", Tag.Line);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Region : Comment_Region) return JSON_Value is
      Result : constant JSON_Value := Create_Object;
      Tags   : JSON_Array := Empty_Array;
   begin
      for Tag of Region.Tags loop
         Append (Tags, To_JSON (Tag));
      end loop;

      Result.Set_Field ("text", To_String (Region.Text));
      Result.Set_Field ("first_line", Region.First_Line);
      Result.Set_Field ("last_line", Region.Last_Line);
      Result.Set_Field ("tags", Tags);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Info : Entity_Info) return JSON_Value is
      Result   : constant JSON_Value := Create_Object;
      Location : constant JSON_Value := Create_Object;
   begin
      Location.Set_Field ("file", To_String (Info.File));
      Location.Set_Field ("line", Info.Line);
      Location.Set_Field ("column", Info.Column);

      Result.Set_Field ("name", To_String (Info.Name));
      Result.Set_Field ("qualified_name", To_String (Info.Qualified_Name));
      Result.Set_Field ("kind", Image (Info.Kind));
      Result.Set_Field ("declared_in", Image (Info.Declared_In));
      Result.Set_Field ("is_renaming", Info.Is_Renaming);
      Result.Set_Field ("location", Location);
      Result.Set_Field ("doc", To_JSON (Info.Doc));

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Info : Subprogram_Info) return JSON_Value is
      Result        : constant JSON_Value := Create_Object;
      Location      : constant JSON_Value := Create_Object;
      Parameters    : JSON_Array := Empty_Array;
      Body_Comments : JSON_Array := Empty_Array;
   begin
      for Region of Info.Body_Comments loop
         Append (Body_Comments, To_JSON (Region));
      end loop;

      for Parameter of Info.Parameters loop
         declare
            Item : constant JSON_Value := Create_Object;
         begin
            Item.Set_Field ("name", To_String (Parameter.Name));
            Item.Set_Field ("mode", Image (Parameter.Mode));
            Item.Set_Field ("type", To_String (Parameter.Type_Name));
            Append (Parameters, Item);
         end;
      end loop;

      Location.Set_Field ("file", To_String (Info.File));
      Location.Set_Field ("line", Info.Line);
      Location.Set_Field ("column", Info.Column);

      Result.Set_Field ("name", To_String (Info.Name));
      Result.Set_Field ("qualified_name", To_String (Info.Qualified_Name));
      Result.Set_Field ("kind", Image (Info.Kind));
      Result.Set_Field ("declared_in", Image (Info.Declared_In));
      Result.Set_Field ("nested", Info.Nested);
      Result.Set_Field ("has_body", Info.Has_Body);
      Result.Set_Field ("is_generic", Info.Is_Generic);
      Result.Set_Field ("is_renaming", Info.Is_Renaming);
      Result.Set_Field ("is_expression_function", Info.Is_Expression);
      Result.Set_Field ("is_abstract", Info.Is_Abstract);
      Result.Set_Field ("is_body", Info.Is_Body);
      Result.Set_Field ("parameters", Parameters);
      Result.Set_Field ("return_type", Text_Or_Null (Info.Return_Type));
      Result.Set_Field ("location", Location);
      Result.Set_Field ("doc", To_JSON (Info.Doc));
      Result.Set_Field ("body_comments", Body_Comments);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Info : Package_Info) return JSON_Value is
      Result      : constant JSON_Value := Create_Object;
      Subprograms : JSON_Array := Empty_Array;
      Entities    : JSON_Array := Empty_Array;
   begin
      for Subprogram of Info.Subprograms loop
         Append (Subprograms, To_JSON (Subprogram));
      end loop;

      for Entity of Info.Entities loop
         Append (Entities, To_JSON (Entity));
      end loop;

      Result.Set_Field ("name", To_String (Info.Name));
      Result.Set_Field ("spec_file", Text_Or_Null (Info.Spec_File));
      Result.Set_Field ("body_file", Text_Or_Null (Info.Body_File));
      Result.Set_Field ("is_generic", Info.Is_Generic);
      Result.Set_Field ("doc", To_JSON (Info.Doc));
      Result.Set_Field ("subprograms", Subprograms);
      Result.Set_Field ("entities", Entities);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON (Info : Check_Info) return JSON_Value is
      Result   : constant JSON_Value := Create_Object;
      Location : constant JSON_Value := Create_Object;
      Covers   : JSON_Array := Empty_Array;
   begin
      for Payload of Info.Covers loop
         Append (Covers, Create (To_String (Payload)));
      end loop;

      Location.Set_Field ("file", To_String (Info.File));
      Location.Set_Field ("line", Info.Line);
      Location.Set_Field ("column", Info.Column);

      Result.Set_Field ("kind", Image (Info.Kind));
      Result.Set_Field ("name", To_String (Info.Name));
      Result.Set_Field ("location", Location);
      Result.Set_Field ("covers", Covers);

      return Result;
   end To_JSON;

   -------------
   -- To_JSON --
   -------------

   function To_JSON
     (Project : Model.Project_Info; Compact : Boolean := False)
      return Unbounded_String
   is
      Root     : constant JSON_Value := Create_Object;
      Packages : JSON_Array := Empty_Array;
      Library  : JSON_Array := Empty_Array;
      Checks   : JSON_Array := Empty_Array;
   begin
      for Item of Project.Packages loop
         Append (Packages, To_JSON (Item));
      end loop;

      for Item of Project.Library_Subprograms loop
         Append (Library, To_JSON (Item));
      end loop;

      for Item of Project.Checks loop
         Append (Checks, To_JSON (Item));
      end loop;

      Root.Set_Field ("schema_version", Integer'(Schema_Version));
      Root.Set_Field ("tool", "ada_tracer");
      Root.Set_Field ("project", To_String (Project.Project));
      Root.Set_Field ("packages", Packages);
      Root.Set_Field ("library_subprograms", Library);
      Root.Set_Field ("checks", Checks);

      return Write (Root, Compact => Compact);
   end To_JSON;

end Ada_Tracer.Emit;
