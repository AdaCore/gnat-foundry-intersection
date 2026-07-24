--  Display body -- host profile. Renders the traffic state to stdout as a
--  colored ASCII-art plan view of the four-way intersection, redrawn in
--  place (ANSI cursor-home) on every bus write. Absorbs the old
--  Set_Through_Lamp / Set_Left_Lamp / Set_Walk / Set_Dont_Walk / Diag
--  surface.
--
--  The picture is data, not code: `Art` is the frame exactly as displayed,
--  and `Mask` is a same-shaped overlay naming, for each character, the lamp
--  whose state colours it. To change the drawing, edit the two constants in
--  step -- the renderer never changes.

with Ada.Characters.Latin_1;
with Ada.Text_IO; use Ada.Text_IO;

package body Display is

   ESC : constant Character := Ada.Characters.Latin_1.ESC;
   --  The escape character introducing every ANSI control sequence below.

   function CSI (Sequence : String) return String
   is (ESC & '[' & Sequence);
   --  An ANSI control sequence: the CSI introducer followed by its body.
   --  @param Sequence The control-sequence body (e.g. "2J", "92m")
   --  @return The full escape sequence

   -----------------------------------------------------------------------
   --  The intersection picture
   -----------------------------------------------------------------------

   Frame_Width  : constant := 39;
   Frame_Height : constant := 21;
   --  Dimensions of the ASCII-art frame below.

   subtype Frame_Line is String (1 .. Frame_Width);
   type Frame is array (1 .. Frame_Height) of Frame_Line;
   --  One frame of the display: fixed-width lines, so the type system keeps
   --  Art and Mask the same shape.

   --  Plan view, north up ("N" in the corner). Traffic keeps right, so each
   --  arm carries the *approaching* movements on its right-hand half:
   --  northbound arrows sit in the south arm, and so on. Each approach shows
   --  a through arrow and a turn-left arrow (pointing where the turn exits).
   --  "=" bands are the pedestrian crosswalks, one across each arm, and "o"
   --  is the pedestrian request-pending lamp at the corner serving that
   --  crosswalk.
   Art : constant Frame :=
     ("            | .  . |      |          N ",
      "            | .  . |      |            ",
      "            | .  . |      |            ",
      "            | v  > |      |            ",
      "            |      |      |            ",
      "            |      |      |            ",
      "          o | || || || || | o          ",
      "------------+             +------------",
      "         ==                 ==  < - - -",
      "         ==                 ==  v - - -",
      "---------==-               -==---------",
      "- - - ^  ==                 ==         ",
      "- - - >  ==                 ==         ",
      "------------+             +------------",
      "          o | || || || || | o          ",
      "            |      |      |            ",
      "            |      |      |            ",
      "            |      | <  ^ |            ",
      "            |      | .  . |            ",
      "            |      | .  . |            ",
      "            |      | .  . |            ");

   --  The lamp mask: each non-space character selects the lamp whose state
   --  colours the art character at the same position (space = never
   --  coloured). Codes:
   --    'N' 'S' 'E' 'W' -- through face of that approach
   --    'n' 's' 'e' 'w' -- protected-left face of that approach
   --    'A' 'B' 'C' 'D' -- pedestrian head, in Crosswalk order:
   --                       A = NS_North, B = NS_South,
   --                       C = EW_East,  D = EW_West
   --    'a' 'b' 'c' 'd' -- request indicator of the same crosswalk
   Mask : constant Frame :=
     ("              S  s                     ",
      "              S  s                     ",
      "              S  s                     ",
      "              S  s                     ",
      "                                       ",
      "                                       ",
      "          d  AAAAAAAAAAAAA  a          ",
      "                                       ",
      "         DD                 CC  WWWWWWW",
      "         DD                 CC  wwwwwww",
      "         DD                 CC         ",
      "eeeeeee  DD                 CC         ",
      "EEEEEEE  DD                 CC         ",
      "                                       ",
      "          b  BBBBBBBBBBBBB  c          ",
      "                                       ",
      "                                       ",
      "                     n  N              ",
      "                     n  N              ",
      "                     n  N              ",
      "                     n  N              ");

   -----------------------------------------------------------------------
   --  Lamp-state colours (SGR codes)
   -----------------------------------------------------------------------

   SGR_Red    : constant String := "91";  --  bright red
   SGR_Yellow : constant String := "93";  --  bright yellow / amber
   SGR_Green  : constant String := "92";  --  bright green
   SGR_Dark   : constant String := "90";  --  dim grey -- an unlit lamp
   SGR_Blink  : constant String := "5";   --  blink attribute, for flashing

   function Face_SGR (F : States.Vehicle_Face) return String
   is (case F is
         when States.Red          => SGR_Red,
         when States.Yellow       => SGR_Yellow,
         when States.Green        => SGR_Green,
         when States.Flashing_Red => SGR_Blink & ";" & SGR_Red);
   --  SGR colour for a vehicle face.
   --  @param F The face value
   --  @return The SGR code rendering that face's colour

   function Head_SGR (H : States.Pedestrian_Head) return String
   is (case H is
         when States.None            => SGR_Dark,
         when States.Walk            => SGR_Green,
         when States.Flash_Dont_Walk => SGR_Blink & ";" & SGR_Red,
         when States.Dont_Walk       => SGR_Red);
   --  SGR colour for a pedestrian head, painted over its crosswalk band.
   --  @param H The head value
   --  @return The SGR code rendering that head's colour

   function Request_SGR (R : States.Request_Indicator) return String
   is (case R is
         when States.No_Request      => SGR_Dark,
         when States.Request_Pending => SGR_Yellow);
   --  SGR colour for a request-pending lamp.
   --  @param R The indicator value
   --  @return The SGR code rendering that indicator's colour

   function SGR_Of (Key : Character; S : States.Display_State) return String
   is (case Key is
         when 'N'    => Face_SGR (S.Through (States.North)),
         when 'S'    => Face_SGR (S.Through (States.South)),
         when 'E'    => Face_SGR (S.Through (States.East)),
         when 'W'    => Face_SGR (S.Through (States.West)),
         when 'n'    => Face_SGR (S.Left (States.North)),
         when 's'    => Face_SGR (S.Left (States.South)),
         when 'e'    => Face_SGR (S.Left (States.East)),
         when 'w'    => Face_SGR (S.Left (States.West)),
         when 'A'    => Head_SGR (S.Heads (States.NS_North)),
         when 'B'    => Head_SGR (S.Heads (States.NS_South)),
         when 'C'    => Head_SGR (S.Heads (States.EW_East)),
         when 'D'    => Head_SGR (S.Heads (States.EW_West)),
         when 'a'    => Request_SGR (S.Requests (States.NS_North)),
         when 'b'    => Request_SGR (S.Requests (States.NS_South)),
         when 'c'    => Request_SGR (S.Requests (States.EW_East)),
         when 'd'    => Request_SGR (S.Requests (States.EW_West)),
         when others => "");
   --  Decode one mask character: the SGR colour of the lamp it names in the
   --  given state, or "" for positions the mask leaves unpainted.
   --  @param Key The mask character
   --  @param S The traffic state supplying the lamp values
   --  @return The SGR code, or "" when Key names no lamp

   procedure Initialize is
   begin
      --  Clear the screen so the frame owns the viewport, then banner.
      Put (CSI ("2J") & CSI ("H"));
      Put_Line ("[display/host] Initialize");
   end Initialize;

   procedure Show (S : States.Display_State) is
   begin
      --  Home the cursor and repaint the frame in place; erase-to-end-of-line
      --  after each row clears any older, wider content underneath.
      Put (CSI ("H"));
      for Row in Art'Range loop
         for Col in Frame_Line'Range loop
            declare
               SGR : constant String := SGR_Of (Mask (Row) (Col), S);
            begin
               if SGR = "" then
                  Put (Art (Row) (Col));
               else
                  Put (CSI (SGR & "m") & Art (Row) (Col) & CSI ("0m"));
               end if;
            end;
         end loop;
         Put (CSI ("K"));
         New_Line;
      end loop;
   end Show;

   procedure Diag_Write_Line (S : String) is
   begin
      Put_Line ("[diag] " & S);
   end Diag_Write_Line;

end Display;
