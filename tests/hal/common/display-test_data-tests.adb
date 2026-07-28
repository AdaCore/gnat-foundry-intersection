--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Display.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Ada.Text_IO;

--  begin read only
--  end read only
package body Display.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

   --  The host Display renders to standard output, so these tests capture
   --  it: Run redirects standard output to a temporary file, invokes the
   --  rendering under test, and hands the captured lines back one by one.

   ESC : constant Character := Ada.Characters.Latin_1.ESC;
   --  The ANSI escape character the host display paints with.

   procedure Run_Captured
     (Render     : not null access procedure;
      Check_Line :
        not null access procedure (Line : String; Number : Positive);
      Line_Count : out Natural);

   procedure Run_Captured
     (Render     : not null access procedure;
      Check_Line :
        not null access procedure (Line : String; Number : Positive);
      Line_Count : out Natural)
   is
      Capture : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Capture);
      Ada.Text_IO.Set_Output (Capture);
      Render.all;
      Ada.Text_IO.Set_Output (Ada.Text_IO.Standard_Output);
      Ada.Text_IO.Reset (Capture, Ada.Text_IO.In_File);

      Line_Count := 0;
      while not Ada.Text_IO.End_Of_File (Capture) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (Capture);
         begin
            Line_Count := Line_Count + 1;
            Check_Line (Line, Line_Count);
         end;
      end loop;

      Ada.Text_IO.Close (Capture);
   end Run_Captured;

--  begin read only
--  end read only

--  begin read only
   procedure Test_Initialize (Gnattest_T : in out Test);
   procedure Test_Initialize_b0ff4a (Gnattest_T : in out Test) renames Test_Initialize;
--  id:2.2/b0ff4afbf3d6da35/Initialize/1/0/
   procedure Test_Initialize (Gnattest_T : in out Test) is
   --  display.ads:9:4:Initialize
--  end read only

      pragma Unreferenced (Gnattest_T);

      Count : Natural;

      procedure Render is
      begin
         Initialize;
      end Render;

      procedure Check_Line (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         --  Initialize clears the screen (ANSI 2J + home) and then banners.
         Assert
           (Line = ESC & "[2J" & ESC & "[H" & "[display/host] Initialize",
            "Initialize should clear the screen and announce itself");
      end Check_Line;

   begin

      Run_Captured (Render'Access, Check_Line'Access, Count);

      Assert (Count = 1, "Initialize should emit exactly one banner line");

--  begin read only
   end Test_Initialize;
--  end read only


--  begin read only
   procedure Test_Show (Gnattest_T : in out Test);
   procedure Test_Show_bcb862 (Gnattest_T : in out Test) renames Test_Show;
--  id:2.2/bcb86212e488c2c2/Show/1/0/
   procedure Test_Show (Gnattest_T : in out Test) is
   --  display.ads:12:4:Show
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  A distinctive probe state: one GREEN through, everything else
      --  restrictive.
      Probe : constant States.Display_State :=
        (Through  => (States.North => States.Green, others => States.Red),
         Left     => (others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      Frame_Height : constant := 24;
      --  Height of the host display's ASCII-art frame (keep in step with
      --  the Art constant in the host Display body): 3 legend header rows
      --  plus 21 picture rows.

      Green_On : constant String := ESC & "[92m";
      --  The SGR sequence the host display paints GREEN lamps with.

      Count           : Natural := 0;
      Green_Found     : Natural := 0;
      Saw_Ped_Request : Boolean := False;
      Saw_Left_Turn   : Boolean := False;
      --  Set when the captured frame carries the keyboard-shortcut legend
      --  rows in the header.

      procedure Render is
      begin
         Show (Probe);
      end Render;

      procedure Check_Line (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         --  Every GREEN paint in the frame must be the probe's single GREEN
         --  lamp: the northbound through arrow.
         for I in Line'First .. Line'Last - Green_On'Length + 1 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On then
               Green_Found := Green_Found + 1;
               declare
                  Char : Character := Line (I + Green_On'Length);
               begin
                  Assert
                    (I + Green_On'Length <= Line'Last
                     and then (Char = '^' or Char = '.'),
                     "GREEN should paint the north/south through arrows");
               end;
            end if;
         end loop;

         --  The header legend rows pin the keyboard-shortcut documentation,
         --  key digits and side bindings included.
         if Ada.Strings.Fixed.Index
             (Line, "1/2/3/4 = ped request N/S/E/W crosswalk") /= 0
         then
            Saw_Ped_Request := True;
         end if;
         if Ada.Strings.Fixed.Index
             (Line, "n/s/e/w = left-turn N/S/E/W approach") /= 0
         then
            Saw_Left_Turn := True;
         end if;
      end Check_Line;

      --  Geometry probes: a served crosswalk must be painted PARALLEL to the
      --  traffic it runs with, never lying across it. Crosswalks are named by
      --  the arm they span: an East_Side/West_Side head (served with the N-S
      --  green) is a vertical '=' band across its E/W arm; a North_Side/
      --  South_Side head (served with the E-W green) is a horizontal '|' band
      --  across its N/S arm. (Painting a WALK lying across the green it moves
      --  with was the bug that motivated the side-of-junction names.)
      East_Walk_Probe : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    =>
           (States.East_Side => States.Walk, others => States.Dont_Walk),
         Requests => (others => States.No_Request));
      North_Walk_Probe : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    =>
           (States.North_Side => States.Walk, others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      Saw_East_Walk  : Boolean := False;
      Saw_North_Walk : Boolean := False;

      procedure Render_East_Walk is
      begin
         Show (East_Walk_Probe);
      end Render_East_Walk;

      procedure Render_North_Walk is
      begin
         Show (North_Walk_Probe);
      end Render_North_Walk;

      procedure Check_East_Walk (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         for I in Line'First .. Line'Last - Green_On'Length + 1 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On
              and then I + Green_On'Length <= Line'Last
            then
               declare
                  Char : constant Character := Line (I + Green_On'Length);
               begin
                  Saw_East_Walk := True;
                  Assert
                    (Char = '=' or Char = '-',
                     "East_Side WALK must paint the vertical crosswalk band "
                     & "(parallel to N-S traffic), not lie across the N-S road");
               end;
            end if;
         end loop;
      end Check_East_Walk;

      procedure Check_North_Walk (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         for I in Line'First .. Line'Last - Green_On'Length + 1 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On
              and then I + Green_On'Length <= Line'Last
            then
               declare
                  Char : constant Character := Line (I + Green_On'Length);
               begin
                  Saw_North_Walk := True;
                  Assert
                    (Char = '|' or Char = ' ',
                     "North_Side WALK must paint the horizontal crosswalk band "
                     & "across the north arm (parallel to E-W traffic)");
               end;
            end if;
         end loop;
      end Check_North_Walk;

      --  Legend probes: each corner key digit is painted by its OWN side's
      --  request indicator -- the digit-to-crosswalk binding that makes the
      --  header legend literally true. With a single side pending and every
      --  other lamp restrictive, the request lamp is the frame's only
      --  YELLOW paint, so it must land on that side's corner label.

      Yellow_On : constant String := ESC & "[93m";
      --  The SGR sequence the host display paints pending requests with.

      Pending_Side : States.Crosswalk := States.North_Side;
      Saw_Request  : Boolean := False;

      function Corner_Label (C : States.Crosswalk) return String
      is (case C is
            when States.North_Side => "1>",
            when States.South_Side => "<2",
            when States.East_Side  => "3v",
            when States.West_Side  => "4^");
      --  The two art characters forming each crosswalk's corner key label.

      procedure Render_Request is
         S : States.Display_State :=
           (Through  => (others => States.Red),
            Left     => (others => States.Red),
            Heads    => (others => States.Dont_Walk),
            Requests => (others => States.No_Request));
      begin
         S.Requests (Pending_Side) := States.Request_Pending;
         Show (S);
      end Render_Request;

      procedure Check_Request (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
         Label : constant String := Corner_Label (Pending_Side);
      begin
         for I in Line'First .. Line'Last - Yellow_On'Length + 1 loop
            if Line (I .. I + Yellow_On'Length - 1) = Yellow_On
              and then I + Yellow_On'Length <= Line'Last
            then
               declare
                  Char : constant Character := Line (I + Yellow_On'Length);
               begin
                  Saw_Request := True;
                  Assert
                    (Char = Label (1) or Char = Label (2),
                     "a pending " & States.Crosswalk'Image (Pending_Side)
                     & " request must light only its own corner key label");
               end;
            end if;
         end loop;
      end Check_Request;

   begin

      Run_Captured (Render'Access, Check_Line'Access, Count);

      Assert
        (Count = Frame_Height,
         "Show should render the whole intersection frame");

      Assert
        (Green_Found > 0, "Show should paint at least one GREEN character");

      Assert
        (Saw_Ped_Request,
         "the header should legend the ped-request key shortcuts");
      Assert
        (Saw_Left_Turn,
         "the header should legend the left-turn key shortcuts");

      Run_Captured (Render_East_Walk'Access, Check_East_Walk'Access, Count);
      Assert
        (Saw_East_Walk,
         "the East_Side WALK probe should paint at least one green stripe");

      Run_Captured (Render_North_Walk'Access, Check_North_Walk'Access, Count);
      Assert
        (Saw_North_Walk,
         "the North_Side WALK probe should paint at least one green stripe");

      for C in States.Crosswalk loop
         Pending_Side := C;
         Saw_Request  := False;
         Run_Captured (Render_Request'Access, Check_Request'Access, Count);
         Assert
           (Saw_Request,
            "the " & States.Crosswalk'Image (C)
            & " request lamp should light its corner key label");
      end loop;

--  begin read only
   end Test_Show;
--  end read only


--  begin read only
   procedure Test_Diag_Write_Line (Gnattest_T : in out Test);
   procedure Test_Diag_Write_Line_751432 (Gnattest_T : in out Test) renames Test_Diag_Write_Line;
--  id:2.2/751432547ed5b558/Diag_Write_Line/1/0/
   procedure Test_Diag_Write_Line (Gnattest_T : in out Test) is
   --  display.ads:24:4:Diag_Write_Line
--  end read only

      pragma Unreferenced (Gnattest_T);

      Count : Natural;

      procedure Render is
      begin
         Diag_Write_Line ("coverage probe");
      end Render;

      procedure Check_Line (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         Assert
           (Line = "[diag] coverage probe",
            "the diagnostic line should be emitted under the diag tag");
      end Check_Line;

   begin

      Run_Captured (Render'Access, Check_Line'Access, Count);

      Assert
        (Count = 1, "Diag_Write_Line should emit exactly one diagnostic line");

--  begin read only
   end Test_Diag_Write_Line;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end Display.Test_Data.Tests;
