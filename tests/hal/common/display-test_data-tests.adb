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
with Ada.Environment_Variables;
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

      --@covers none: display bring-up is out of scope (README "Verification scope")

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

      --@covers none: display rendering is out of scope (README "Verification scope")

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
         --  The frame is not newline-terminated -- on a terminal exactly as
         --  tall as the picture that newline would scroll it off by one -- so
         --  the erase-below tail rides on the end of the last row.
         if Number = Frame_Height then
            Assert
              (Line'Length >= 3
               and then Line (Line'Last - 2 .. Line'Last) = ESC & "[J",
               "the last row should carry the erase-below tail");
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

         --  The header legend rows pin the keyboard-shortcut documentation,
         --  key digits and side bindings included.
         if Ada.Strings.Fixed.Index
              (Line, "1/2/3/4 = ped request N/S/E/W crosswalk")
           /= 0
         then
            Saw_Ped_Request := True;
         end if;
         if Ada.Strings.Fixed.Index
              (Line, "n/s/e/w = left-turn N/S/E/W approach")
           /= 0
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
      East_Walk_Probe  : constant States.Display_State :=
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
                     "a pending "
                     & States.Crosswalk'Image (Pending_Side)
                     & " request must light only its own corner key label");
               end;
            end if;
         end loop;
      end Check_Request;

      --  Wide profile. A signal head straddles every lane, so a movement's
      --  colour lands on that head's bulbs and nowhere else -- and the glyph
      --  a paint falls on says which head lit, because the through head shows
      --  circular indications while the turn head shows arrows only, never
      --  circular (CONOPS 2.7).
      subtype Glyph_Bytes is String (1 .. 3);
      --  Every glyph the wide picture's heads and crosswalks use encodes
      --  to three UTF-8 bytes.

      Wide_Frame_Height : constant := 50;
      --  Height of the wide picture (keep in step with the host Display
      --  body): 3 legend header rows plus 47 picture rows.

      function Glyph (B1, B2, B3 : Natural) return String
      is (Character'Val (B1) & Character'Val (B2) & Character'Val (B3));
      --  One three-byte UTF-8 glyph of the wide picture, by code point. The
      --  captured frame is a byte string and -gnatW8 forbids writing these
      --  characters in a String literal, so they are spelled out.
      --  @param B1 First byte of the encoding
      --  @param B2 Second byte of the encoding
      --  @param B3 Third byte of the encoding
      --  @return The encoded glyph

      Circle    : constant Glyph_Bytes := Glyph (16#E2#, 16#97#, 16#8F#);
      Arrow_W   : constant Glyph_Bytes := Glyph (16#E2#, 16#97#, 16#80#);
      Bar_Down  : constant String := Glyph (16#E2#, 16#96#, 16#8C#);
      Bar_Along : constant String := Glyph (16#E2#, 16#96#, 16#80#);
      --  The head's circular indication, its westward arrow indication, and
      --  the two crosswalk bars: upright bars across the north/south arms,
      --  flat bars across the east/west arms.

      --  A protected left, and nothing else, released: its head is then the
      --  only GREEN in the frame. North's left turn exits west, so the arrow
      --  it must light is the westward one.
      Turn_Probe : constant States.Display_State :=
        (Through  => (others => States.Red),
         Left     => (States.North => States.Green, others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request));

      Wide_Count       : Natural := 0;
      Saw_Wide_Legend  : Boolean := False;
      Saw_Through_Bulb : Boolean := False;
      Saw_Turn_Bulb    : Boolean := False;
      Saw_Wide_East    : Boolean := False;
      Saw_Wide_North   : Boolean := False;

      procedure Render_Turn is
      begin
         Show (Turn_Probe);
      end Render_Turn;

      procedure Check_Wide_Green
        (Line     : String;
         Expected : String;
         Seen     : in out Boolean;
         Message  : String) is
      begin
         for I in Line'First .. Line'Last - Green_On'Length - 2 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On then
               Seen := True;
               Assert
                 (Line (I + Green_On'Length .. I + Green_On'Length + 2)
                  = Expected,
                  Message);
            end if;
         end loop;
      end Check_Wide_Green;
      --  Every GREEN paint in the line must land on the one glyph the probe
      --  can legitimately light.

      procedure Check_Wide_Through (Line : String; Number : Positive) is
      begin
         if Ada.Strings.Fixed.Index
              (Line, "pedestrian request  --  N / S / E / W crosswalk")
           /= 0
         then
            Saw_Wide_Legend := True;
         end if;
         if Number = Wide_Frame_Height then
            Assert
              (Line'Length >= 3
               and then Line (Line'Last - 2 .. Line'Last) = ESC & "[J",
               "the last row should carry the erase-below tail");
         end if;
         Check_Wide_Green
           (Line,
            Circle,
            Saw_Through_Bulb,
            "a GREEN through face must light a circular indication, never "
            & "the turn head's arrows");
      end Check_Wide_Through;

      procedure Check_Wide_Turn (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         Check_Wide_Green
           (Line,
            Arrow_W,
            Saw_Turn_Bulb,
            "a GREEN protected-left face must light an arrow indication "
            & "pointing where the turn exits, never a circular one "
            & "(CONOPS 2.7)");
      end Check_Wide_Turn;

      procedure Check_Wide_East (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         Check_Wide_Green
           (Line,
            Bar_Along,
            Saw_Wide_East,
            "East_Side WALK must paint the bars across the east arm "
            & "(parallel to N-S traffic), not lie across the N-S road");
      end Check_Wide_East;

      procedure Check_Wide_North (Line : String; Number : Positive) is
         pragma Unreferenced (Number);
      begin
         Check_Wide_Green
           (Line,
            Bar_Down,
            Saw_Wide_North,
            "North_Side WALK must paint the bars across the north arm "
            & "(parallel to E-W traffic), not lie across the E-W road");
      end Check_Wide_North;

      --  Every movement's head, probed one at a time. The turn arrows tell
      --  the four protected lefts apart outright, but all four through faces
      --  show the same circular indication, so glyph alone cannot catch a
      --  transposed pair of through masks. The positions do: with a single
      --  movement released the frame holds exactly one green paint, and the
      --  eight probes must light eight distinct places. That holds whatever
      --  the drawing is, so it survives the picture being redrawn.
      Arrow_E : constant Glyph_Bytes := Glyph (16#E2#, 16#96#, 16#B6#);
      Arrow_N : constant Glyph_Bytes := Glyph (16#E2#, 16#96#, 16#B2#);
      Arrow_S : constant Glyph_Bytes := Glyph (16#E2#, 16#96#, 16#BC#);
      --  The remaining turn-exit arrows; Arrow_W is declared above.

      type Head_Expectation is record
         Approach : States.Approach;
         Is_Left  : Boolean;
         Lamp     : Glyph_Bytes;
      end record;
      --  One movement and the indication its head must light on GREEN.
      --  @field Approach The approach the movement belongs to
      --  @field Is_Left True for the protected left, False for the through
      --  @field Lamp The glyph a GREEN must land on

      Heads_Table : constant array (1 .. 8) of Head_Expectation :=
        ((States.North, False, Circle),
         (States.South, False, Circle),
         (States.East, False, Circle),
         (States.West, False, Circle),
         (States.North, True, Arrow_W),
         (States.South, True, Arrow_E),
         (States.East, True, Arrow_N),
         (States.West, True, Arrow_S));
      --  A left turn's arrow points where the turn exits, so north's exits
      --  west, south's east, east's north and west's south.

      function Movement_Name (E : Head_Expectation) return String
      is (States.Approach'Image (E.Approach)
          & (if E.Is_Left then " protected left" else " through"));
      --  The movement an entry names, for assertion messages.
      --  @param E The table entry
      --  @return The movement's name

      Probe_Index  : Positive := Heads_Table'First;
      Green_Paints : Natural := 0;
      Lamp_Line    : array (Heads_Table'Range) of Natural := (others => 0);
      Lamp_Offset  : array (Heads_Table'Range) of Natural := (others => 0);

      procedure Render_Movement is
         S : States.Display_State :=
           (Through  => (others => States.Red),
            Left     => (others => States.Red),
            Heads    => (others => States.Dont_Walk),
            Requests => (others => States.No_Request));
      begin
         if Heads_Table (Probe_Index).Is_Left then
            S.Left (Heads_Table (Probe_Index).Approach) := States.Green;
         else
            S.Through (Heads_Table (Probe_Index).Approach) := States.Green;
         end if;
         Show (S);
      end Render_Movement;

      procedure Check_Movement (Line : String; Number : Positive) is
         Entry_Under_Test : constant Head_Expectation :=
           Heads_Table (Probe_Index);
      begin
         for I in Line'First .. Line'Last - Green_On'Length - 2 loop
            if Line (I .. I + Green_On'Length - 1) = Green_On then
               Green_Paints := Green_Paints + 1;
               Lamp_Line (Probe_Index) := Number;
               Lamp_Offset (Probe_Index) := I;
               Assert
                 (Line (I + Green_On'Length .. I + Green_On'Length + 2)
                  = Entry_Under_Test.Lamp,
                  "a released "
                  & Movement_Name (Entry_Under_Test)
                  & " must light its own head's indication");
            end if;
         end loop;
      end Check_Movement;

   begin

      --  Both pictures are exercised, and neither may be chosen by accident:
      --  left to itself the body measures the terminal, which under a
      --  captured run is whatever the suite happens to have been started in.
      Ada.Environment_Variables.Set ("TRAFFIC_LIGHT_FRAME", "narrow");

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
         Saw_Request := False;
         Run_Captured (Render_Request'Access, Check_Request'Access, Count);
         Assert
           (Saw_Request,
            "the "
            & States.Crosswalk'Image (C)
            & " request lamp should light its corner key label");
      end loop;

      Ada.Environment_Variables.Set ("TRAFFIC_LIGHT_FRAME", "wide");

      Run_Captured (Render'Access, Check_Wide_Through'Access, Wide_Count);
      Assert
        (Wide_Count = Wide_Frame_Height,
         "Show should render the whole wide intersection frame");
      Assert
        (Saw_Wide_Legend,
         "the wide header should legend the ped-request key shortcuts");
      Assert
        (Saw_Through_Bulb,
         "the through probe should light a circular indication");

      Run_Captured (Render_Turn'Access, Check_Wide_Turn'Access, Wide_Count);
      Assert
        (Saw_Turn_Bulb, "the turn probe should light an arrow indication");

      Run_Captured
        (Render_East_Walk'Access, Check_Wide_East'Access, Wide_Count);
      Assert
        (Saw_Wide_East,
         "the East_Side WALK probe should paint at least one green bar");

      Run_Captured
        (Render_North_Walk'Access, Check_Wide_North'Access, Wide_Count);
      Assert
        (Saw_Wide_North,
         "the North_Side WALK probe should paint at least one green bar");

      for Index in Heads_Table'Range loop
         Probe_Index := Index;
         Green_Paints := 0;
         Run_Captured
           (Render_Movement'Access, Check_Movement'Access, Wide_Count);
         Assert
           (Green_Paints = 1,
            "releasing only the "
            & Movement_Name (Heads_Table (Index))
            & " should light exactly one bulb of one head");
      end loop;

      for A in Heads_Table'Range loop
         for B in A + 1 .. Heads_Table'Last loop
            Assert
              (Lamp_Line (A) /= Lamp_Line (B)
               or else Lamp_Offset (A) /= Lamp_Offset (B),
               "the "
               & Movement_Name (Heads_Table (A))
               & " and the "
               & Movement_Name (Heads_Table (B))
               & " must light different places -- two movements sharing a "
               & "bulb means their masks are transposed");
         end loop;
      end loop;

      --  Distinct places rule out two movements sharing a head, but not a
      --  permutation among the four through faces, which show the same
      --  circular indication by CONOPS 2.7 and so cannot be told apart by
      --  glyph. Where they sit tells them apart. A head is at the end of the
      --  box its own traffic arrives at, and traffic keeps right, so the
      --  southbound head is above the northbound one and -- the westbound
      --  approach running along the north half of the east-west road -- the
      --  westbound head is above the eastbound one. Both are orderings, not
      --  coordinates, so redrawing the picture leaves them true.
      Assert
        (Lamp_Line (2) < Lamp_Line (1),
         "the southbound through head should sit above the northbound one");
      Assert
        (Lamp_Line (4) < Lamp_Line (3),
         "the westbound through head should sit above the eastbound one");

      --  With no override the body measures for itself, and the destination
      --  here is a captured file rather than the terminal behind standard
      --  output -- whose size would say nothing about it. That is the
      --  fallback, and it must land on the picture that fits anywhere.
      Ada.Environment_Variables.Clear ("TRAFFIC_LIGHT_FRAME");

      Run_Captured (Render'Access, Check_Line'Access, Count);
      Assert
        (Count = Frame_Height,
         "a redirected destination cannot be measured, so Show should fall "
         & "back to the narrow picture rather than trust the terminal size");

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

      --@covers none: diagnostic output is out of scope (README "Verification scope")

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
