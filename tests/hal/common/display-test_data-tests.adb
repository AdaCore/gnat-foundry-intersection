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
      begin
         --  Past the frame, only the erase-below tail Show ends with.
         if Number > Frame_Height then
            Assert
              (Line = ESC & "[J",
               "the frame should be followed only by the erase-below tail");
            return;
         end if;

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

         --  The header legend rows pin the keyboard-shortcut documentation.
         if Ada.Strings.Fixed.Index (Line, "ped request") /= 0 then
            Saw_Ped_Request := True;
         end if;
         if Ada.Strings.Fixed.Index (Line, "left-turn") /= 0 then
            Saw_Left_Turn := True;
         end if;
      end Check_Line;

      --  Geometry probes: a served crosswalk must be painted PARALLEL to the
      --  traffic it runs with, never lying across it. An NS-axis head is drawn
      --  on the vertical '=' band spanning an E/W arm; an EW-axis head on the
      --  horizontal '|' band spanning an N/S arm. (Painting them the other way
      --  round -- a WALK sat across the green it moves with -- was the bug.)
      NS_Walk_Probe : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    =>
           (States.NS_North => States.Walk, others => States.Dont_Walk),
         Requests => (others => States.No_Request));
      EW_Walk_Probe : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    =>
           (States.EW_West => States.Walk, others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      Saw_NS_Walk : Boolean := False;
      Saw_EW_Walk : Boolean := False;

      procedure Render_NS_Walk is
      begin
         Show (NS_Walk_Probe);
      end Render_NS_Walk;

      procedure Render_EW_Walk is
      begin
         Show (EW_Walk_Probe);
      end Render_EW_Walk;

      procedure Check_NS_Walk (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         for I in Line'First .. Line'Last - Green_On'Length + 1 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On
              and then I + Green_On'Length <= Line'Last
            then
               declare
                  Char : constant Character := Line (I + Green_On'Length);
               begin
                  Saw_NS_Walk := True;
                  Assert
                    (Char = '=' or Char = '-',
                     "NS_North WALK must paint the vertical crosswalk band "
                     & "(parallel to N-S traffic), not lie across the N-S road");
               end;
            end if;
         end loop;
      end Check_NS_Walk;

      procedure Check_EW_Walk (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         for I in Line'First .. Line'Last - Green_On'Length + 1 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On
              and then I + Green_On'Length <= Line'Last
            then
               declare
                  Char : constant Character := Line (I + Green_On'Length);
               begin
                  Saw_EW_Walk := True;
                  Assert
                    (Char = '|' or Char = ' ',
                     "EW_West WALK must paint the horizontal crosswalk band "
                     & "across the N-S arm (parallel to E-W traffic)");
               end;
            end if;
         end loop;
      end Check_EW_Walk;

   begin

      Run_Captured (Render'Access, Check_Line'Access, Count);

      Assert
        (Count = Frame_Height + 1,
         "Show should render the whole intersection frame followed by "
         & "the erase-below tail");

      Assert
        (Green_Found > 0, "Show should paint at least one GREEN character");

      Assert
        (Saw_Ped_Request,
         "the header should legend the ped-request key shortcuts");
      Assert
        (Saw_Left_Turn,
         "the header should legend the left-turn key shortcuts");

      Run_Captured (Render_NS_Walk'Access, Check_NS_Walk'Access, Count);
      Assert
        (Saw_NS_Walk,
         "the NS_North WALK probe should paint at least one green stripe");

      Run_Captured (Render_EW_Walk'Access, Check_EW_Walk'Access, Count);
      Assert
        (Saw_EW_Walk,
         "the EW_West WALK probe should paint at least one green stripe");

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
