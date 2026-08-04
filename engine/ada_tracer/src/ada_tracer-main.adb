--  Entry point.
--
--  The tool is built on `Libadalang.Helpers.App`, which supplies project
--  loading, scenario variables, charset handling, the analysis context and
--  the per-file dispatch. Only the switches specific to this tool are added
--  on top of it.
--
--  All the work happens in `Report`, the `App_Post_Process` callback: the
--  framework appends every unit it parsed to `App_Job_Context.Units_Processed`
--  whether or not `Process_Unit` does anything, so the run needs no mutable
--  state of its own. `Report` is declared before the instantiation and
--  completed after the switches, which is what lets it read them.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Text_IO;

with GNATCOLL.Opt_Parse; use GNATCOLL.Opt_Parse;

with Libadalang.Analysis; use Libadalang.Analysis;
with Libadalang.Helpers;

with Ada_Tracer.Emit;
with Ada_Tracer.Model;
with Ada_Tracer.Walk;

procedure Ada_Tracer.Main is

   procedure Report
     (Context : Libadalang.Helpers.App_Context;
      Jobs    : Libadalang.Helpers.App_Job_Context_Array);
   --  Walk every unit the run parsed and write the JSON document.
   --  @param Context The application context; unused
   --  @param Jobs The finished jobs, holding the units to report on

   package App is new
     Libadalang.Helpers.App
       (Name             => "ada_tracer",
        Description      =>
          "Emit a JSON inventory of the packages of an Ada project, the "
          & "subprograms each declares, and the comments documenting them.",
        App_Post_Process => Report);

   package Output is new
     GNATCOLL.Opt_Parse.Parse_Option
       (Parser      => App.Args.Parser,
        Short       => "-o",
        Long        => "--output",
        Help        => "Write the JSON here instead of to standard output",
        Arg_Type    => Unbounded_String,
        Default_Val => Null_Unbounded_String);

   package Compact is new
     GNATCOLL.Opt_Parse.Parse_Flag
       (Parser => App.Args.Parser,
        Long   => "--compact",
        Help   => "Emit one line rather than an indented document");

   package Specs_Only is new
     GNATCOLL.Opt_Parse.Parse_Flag
       (Parser => App.Args.Parser,
        Long   => "--specs-only",
        Help   =>
          "Report only package specs, skipping bodies and the subprograms "
          & "they declare");

   package Base_Directory is new
     GNATCOLL.Opt_Parse.Parse_Option
       (Parser      => App.Args.Parser,
        Long        => "--base-dir",
        Help        =>
          "Report file names relative to this directory rather than to the "
          & "project's own directory. Wanted when the project file is "
          & "generated somewhere below the sources it names.",
        Arg_Type    => Unbounded_String,
        Default_Val => Null_Unbounded_String);

   ------------
   -- Report --
   ------------

   procedure Report
     (Context : Libadalang.Helpers.App_Context;
      Jobs    : Libadalang.Helpers.App_Job_Context_Array)
   is
      pragma Unreferenced (Context);

      Project_File : constant String := To_String (App.Args.Project_File.Get);

      Requested_Base : constant String := To_String (Base_Directory.Get);

      Base_Dir : constant String :=
        (if Requested_Base /= ""
         then Ada.Directories.Full_Name (Requested_Base)
         elsif Project_File = ""
         then Ada.Directories.Current_Directory
         else
           Ada.Directories.Containing_Directory
             (Ada.Directories.Full_Name (Project_File)));

      Setting : constant Walk.Options :=
        (Specs_Only => Specs_Only.Get,
         Base_Dir   => To_Unbounded_String (Base_Dir));

      Result : Model.Project_Info;
   begin
      Result.Project :=
        To_Unbounded_String
          (if Project_File = "" then "<none>" else Project_File);

      for Job of Jobs loop
         for Unit of Job.Units_Processed loop
            if Unit.Has_Diagnostics then
               for Diagnostic of Unit.Diagnostics loop
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     Unit.Get_Filename
                     & ": "
                     & Unit.Format_GNU_Diagnostic (Diagnostic));
               end loop;
            end if;

            Walk.Unit (Result, Unit, Setting);
         end loop;
      end loop;

      Model.Sort_By_Name (Result);

      --  Without `-U`, `App` looks at the root project alone. That is empty
      --  for a wrapper project like `traffic_light.gpr`, whose only source is
      --  a library-level `main.adb` and whose packages all live in imported
      --  projects - an easy result to misread as "this project has no code".

      if Result.Packages.Is_Empty
        and then not App.Args.Process_Full_Project_Tree.Get
      then
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "ada_tracer: no packages found in the root project; "
            & "pass -U to include imported projects");
      end if;

      declare
         Document : constant String :=
           To_String (Emit.To_JSON (Result, Compact => Compact.Get));
         Target   : constant String := To_String (Output.Get);
      begin
         if Target = "" then
            Ada.Text_IO.Put_Line (Document);
         else
            declare
               File : Ada.Text_IO.File_Type;
            begin
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Target);
               Ada.Text_IO.Put_Line (File, Document);
               Ada.Text_IO.Close (File);
            exception
               when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error =>
                  Ada.Text_IO.Put_Line
                    (Ada.Text_IO.Standard_Error,
                     "ada_tracer: cannot write " & Target);
                  Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
            end;
         end if;
      end;
   end Report;

begin
   App.Run;
end Ada_Tracer.Main;
