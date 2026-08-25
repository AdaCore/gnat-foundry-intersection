--  Display body -- host profile. Renders the traffic state to stdout as a
--  coloured plan view of the four-way intersection, redrawn in place (ANSI
--  cursor-home) on every bus write.
--
--  The picture is data, not code. A profile is three same-shaped layers:
--  `Art` is the frame exactly as displayed; `Mask` names, for each character,
--  the signal whose state colours it; and `Bulb` says which lamp of that
--  signal the character is. A blank `Bulb` under a vehicle mask code paints
--  the whole area in the face's colour rather than one bulb of a head. To
--  change a drawing, edit its three constants in step -- the renderer never
--  changes.
--
--  Two profiles are carried, and every `Show` picks between them from the
--  measured terminal, so resizing the window mid-run switches profile at the
--  next frame:
--
--    Wide (95x50)   the plan view: three lanes per arm (a through lane and a
--                   left-turn bay on each approach, one receiving lane on
--                   each departure), continental crosswalks, stop lines,
--                   lane arrows, and a signal head straddling every lane.
--    Narrow (39x24) the reduction for terminals that cannot seat the above,
--                   where each movement's whole lane area carries its colour
--                   instead of a head.
--
--  Mask codes, both profiles:
--    'N' 'S' 'E' 'W' -- through face of that approach
--    'n' 's' 'e' 'w' -- protected-left face of that approach
--    'A' 'B' 'C' 'D' -- pedestrian head, in Crosswalk order:
--                       A = North_Side, B = South_Side,
--                       C = East_Side,  D = West_Side
--                     Crosswalks are named by the arm they span, so each head
--                     paints the band across its own arm. A band's
--                     pedestrians walk PARALLEL to the green they are served
--                     with (CONOPS 3.8/3.9) -- A/B run with the E-W green,
--                     C/D with the N-S green -- so a WALK is never painted
--                     lying across the green it moves with.
--    'a' 'b' 'c' 'd' -- request indicator of the same crosswalk
--    'y'             -- painted yellow always: the double centreline, which
--                       is a pavement marking and not a lamp
--  Bulb codes: 'R', 'Y', 'G' name one lamp of a vehicle head; blank means the
--  mask paints an area.

with Ada.Characters.Latin_1;
with Ada.Environment_Variables;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Text_IO.C_Streams;
with Ada.Text_IO.Text_Streams;
with Interfaces.C;
with Interfaces.C_Streams;

package body Display is

   --  A frame line is as wide as the picture; it cannot be split without
   --  splitting the drawing, so the art literals below run past the project's
   --  usual column limit.
   pragma Style_Checks ("M120");

   use type Interfaces.C.int;
   use type States.Vehicle_Face;

   ESC : constant Character := Ada.Characters.Latin_1.ESC;
   --  The escape character introducing every ANSI control sequence below.

   function CSI (Sequence : String) return String
   is (ESC & '[' & Sequence);
   --  An ANSI control sequence: the CSI introducer followed by its body.
   --  @param Sequence The control-sequence body (e.g. "2J", "92m")
   --  @return The full escape sequence

   -----------------------------------------------------------------------
   --  The two profiles
   -----------------------------------------------------------------------

   type Layout is (Narrow, Wide);
   --  Which picture a frame is drawn from.
   --  @enum Narrow The 39x24 reduction
   --  @enum Wide The 95x50 plan view

   Narrow_Width  : constant := 39;
   Narrow_Height : constant := 24;
   Wide_Width    : constant := 95;
   Wide_Height   : constant := 50;

   subtype Narrow_Line is Wide_Wide_String (1 .. Narrow_Width);
   type Narrow_Frame is array (1 .. Narrow_Height) of Narrow_Line;
   subtype Narrow_Codes is String (1 .. Narrow_Width);
   type Narrow_Overlay is array (1 .. Narrow_Height) of Narrow_Codes;

   subtype Wide_Line is Wide_Wide_String (1 .. Wide_Width);
   type Wide_Frame is array (1 .. Wide_Height) of Wide_Line;
   subtype Wide_Codes is String (1 .. Wide_Width);
   type Wide_Overlay is array (1 .. Wide_Height) of Wide_Codes;
   --  Fixed-width lines, so the type system keeps a profile's three layers
   --  the same shape.

   -----------------------------------------------------------------------
   --  Narrow profile -- plan view, north up, one colour per movement area
   -----------------------------------------------------------------------

   --  Traffic keeps right, so each arm carries the *approaching* movements on
   --  its right-hand half: northbound arrows sit in the south arm, and so on.
   --  Each approach shows a through arrow and a turn-left arrow (pointing
   --  where the turn exits). The bands ("=" across the east/west arms,
   --  "|| ||" across the north/south arms) are the pedestrian crosswalks, one
   --  per arm. Each corner's digit label (e.g. "1>") is the request-pending
   --  lamp of the crosswalk its arrow points at, showing the key that
   --  requests it. The top three rows legend the host keyboard shortcuts (see
   --  the Sources host body); they carry no lamp, so the mask leaves them
   --  blank and they are always printed verbatim.
   Narrow_Art : constant Narrow_Frame :=
     ("1/2/3/4 = ped request N/S/E/W crosswalk",
      "n/s/e/w = left-turn N/S/E/W approach   ",
      "                                       ",
      "            | .  . |      |          N ",
      "            | .  . |      |            ",
      "            | .  . |      |            ",
      "            | v  > |      |            ",
      "            |      |      |            ",
      "            |      |      |            ",
      "         1> | || || || || | 3v         ",
      "------------+             +------------",
      "         ==                 ==  < - - -",
      "         ==                 ==  v - - -",
      "---------==-               -==---------",
      "- - - ^  ==                 ==         ",
      "- - - >  ==                 ==         ",
      "------------+             +------------",
      "         4^ | || || || || | <2         ",
      "            |      |      |            ",
      "            |      |      |            ",
      "            |      | <  ^ |            ",
      "            |      | .  . |            ",
      "            |      | .  . |            ",
      "            |      | .  . |            ");

   Narrow_Mask : constant Narrow_Overlay :=
     ("                                       ",
      "                                       ",
      "                                       ",
      "              S  s                     ",
      "              S  s                     ",
      "              S  s                     ",
      "              S  s                     ",
      "                                       ",
      "                                       ",
      "         aa  AAAAAAAAAAAAA  cc         ",
      "                                       ",
      "         DD                 CC  WWWWWWW",
      "         DD                 CC  wwwwwww",
      "         DD                 CC         ",
      "eeeeeee  DD                 CC         ",
      "EEEEEEE  DD                 CC         ",
      "                                       ",
      "         dd  BBBBBBBBBBBBB  bb         ",
      "                                       ",
      "                                       ",
      "                     n  N              ",
      "                     n  N              ",
      "                     n  N              ",
      "                     n  N              ");

   Narrow_Bulb : constant Narrow_Overlay := (others => (others => ' '));
   --  The narrow picture has no room for signal heads: every vehicle mask
   --  code paints its movement's whole lane area.

   -----------------------------------------------------------------------
   --  Wide profile -- plan view, north up, with lane geometry
   -----------------------------------------------------------------------

   --  Read the picture as a plan, north up. Each arm is three lanes: the
   --  approach half carries a through lane and a left-turn bay against the
   --  centreline, the departure half one receiving lane. The double
   --  centreline "|| ==" therefore jogs across the box, because the middle
   --  lane belongs to whichever approach that side of the junction serves.
   --  Solid "|" and "-" are lane lines, dashed where the turn bay has not yet
   --  begun; a full block is a stop line, drawn unbroken across the whole
   --  approach and set back one cell from the crosswalk. The crosswalks are
   --  continental bars, laid perpendicular to the walk: half-block columns
   --  across the north and south arms, half-block rows across the east and
   --  west arms.
   --
   --  Each approach's two signal heads sit inside the box, one cell past the
   --  crosswalk, each straddling the lane it governs -- so which head serves
   --  the turn bay needs no convention to read. Their long axis is
   --  perpendicular to travel, like the mast arm carrying them: the north and
   --  south approaches read across, the east and west approaches read down.
   --  Bulbs run in the order the driver sees them, red first, which puts red
   --  at the right of the southbound head and at the left of the northbound
   --  one. The through head shows circular indications and the turn head
   --  shows arrows only, never circular (CONOPS 2.7), pointing where the turn
   --  exits.
   Wide_Art : constant Wide_Frame :=
     ("1 2 3 4   pedestrian request  --  N / S / E / W crosswalk                                      ",
      "n s e w   left-turn call  --  N / S / E / W approach                                           ",
      "                                                                                               ",
      "                                   │       │       ║       │                                   ",
      "                                   │               ║       │                                   ",
      "                                   │       │       ║       │                                   ",
      "                                   │               ║       │                                   ",
      "                                   │       │       ║       │                                   ",
      "                                   │               ║       │                                   ",
      "                                   │       │       ║       │                                   ",
      "                                   │       │       ║       │                                   ",
      "                                   │   ┃   │   ┃   ║       │                                   ",
      "                                   │   ┃   │   ┃   ║       │                                   ",
      "                                   │   ┃   │   ┃   ║       │                                   ",
      "                                   │   ▼   │   ╰━▶ ║       │                                   ",
      "                                   │       │       ║       │                                   ",
      "                                   │███████████████║       │                                   ",
      "                                   │               ║       │                                   ",
      "                                   │▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌│                                   ",
      "                                1▸ │▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌│3▾                                 ",
      "───────────────────────────────────╯                       ╰───────────────────────────────────",
      "                               ▀▀▀▀  ● ● ●   ▶ ▶ ▶       ●  ▀▀▀▀ █                             ",
      "                               ▀▀▀▀                      ●  ▀▀▀▀ █  ◀━━━━━                     ",
      "                               ▀▀▀▀                      ●  ▀▀▀▀ █                             ",
      "═══════════════════════════════▀▀▀▀                         ▀▀▀▀ █───────────── ─ ─ ─ ─ ─ ─ ─ ─",
      "                          ▲  █ ▀▀▀▀  ▲                   ▼  ▀▀▀▀ █                             ",
      "                     ━━━━━╯  █ ▀▀▀▀  ▲                   ▼  ▀▀▀▀ █  ╭━━━━━                     ",
      "                             █ ▀▀▀▀  ▲                   ▼  ▀▀▀▀ █  ▼                          ",
      "─ ─ ─ ─ ─ ─ ─ ─ ─────────────█ ▀▀▀▀                         ▀▀▀▀═══════════════════════════════",
      "                             █ ▀▀▀▀  ●                      ▀▀▀▀                               ",
      "                     ━━━━━▶  █ ▀▀▀▀  ●                      ▀▀▀▀                               ",
      "                             █ ▀▀▀▀  ●       ◀ ◀ ◀   ● ● ●  ▀▀▀▀                               ",
      "───────────────────────────────────╮                       ╭───────────────────────────────────",
      "                                4▴ │▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌│ ◂2                                ",
      "                                   │▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌│                                   ",
      "                                   │       ║               │                                   ",
      "                                   │       ║███████████████│                                   ",
      "                                   │       ║       │       │                                   ",
      "                                   │       ║◀━━╮   │   ▲   │                                   ",
      "                                   │       ║   ┃   │   ┃   │                                   ",
      "                                   │       ║   ┃   │   ┃   │                                   ",
      "                                   │       ║   ┃   │   ┃   │                                   ",
      "                                   │       ║       │       │                                   ",
      "                                   │       ║       │       │                                   ",
      "                                   │       ║               │                                   ",
      "                                   │       ║       │       │                                   ",
      "                                   │       ║               │                                   ",
      "                                   │       ║       │       │                                   ",
      "                                   │       ║               │                                   ",
      "                                   │       ║       │       │                                   ");

   Wide_Mask : constant Wide_Overlay :=
     ("                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                                   y                                           ",
      "                                    AAAAAAAAAAAAAAAAAAAAAAA                                    ",
      "                                aa  AAAAAAAAAAAAAAAAAAAAAAA cc                                 ",
      "                                                                                               ",
      "                               DDDD  S S S   s s s       W  CCCC                               ",
      "                               DDDD                      W  CCCC                               ",
      "                               DDDD                      W  CCCC                               ",
      "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyDDDD                         CCCC                               ",
      "                               DDDD  e                   w  CCCC                               ",
      "                               DDDD  e                   w  CCCC                               ",
      "                               DDDD  e                   w  CCCC                               ",
      "                               DDDD                         CCCCyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy",
      "                               DDDD  E                      CCCC                               ",
      "                               DDDD  E                      CCCC                               ",
      "                               DDDD  E       n n n   N N N  CCCC                               ",
      "                                                                                               ",
      "                                dd  BBBBBBBBBBBBBBBBBBBBBBB  bb                                ",
      "                                    BBBBBBBBBBBBBBBBBBBBBBB                                    ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ",
      "                                           y                                                   ");

   Wide_Bulb : constant Wide_Overlay :=
     ("                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                     G Y R   G Y R       G                                     ",
      "                                                         Y                                     ",
      "                                                         R                                     ",
      "                                                                                               ",
      "                                     R                   G                                     ",
      "                                     Y                   Y                                     ",
      "                                     G                   R                                     ",
      "                                                                                               ",
      "                                     R                                                         ",
      "                                     Y                                                         ",
      "                                     G       R Y G   R Y G                                     ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ",
      "                                                                                               ");

   -----------------------------------------------------------------------
   --  Lamp-state colours (SGR codes)
   -----------------------------------------------------------------------

   SGR_Red    : constant String := "91";  --  bright red
   SGR_Yellow : constant String := "93";  --  bright yellow / amber
   SGR_Green  : constant String := "92";  --  bright green
   SGR_Dark   : constant String := "90";  --  dim grey -- an unlit lamp
   SGR_Blink  : constant String := "5";   --  blink attribute, for flashing

   Max_SGR : constant := 4;
   --  Longest SGR body the functions below return ("5;91"). Emit_Row
   --  caches a body of this width, so a longer code added below must
   --  raise it.

   function Face_SGR (F : States.Vehicle_Face) return String
   is (case F is
         when States.Red          => SGR_Red,
         when States.Yellow       => SGR_Yellow,
         when States.Green        => SGR_Green,
         when States.Flashing_Red => SGR_Blink & ";" & SGR_Red);
   --  SGR colour for a vehicle face, painting a whole movement area.
   --  @param F The face value
   --  @return The SGR code rendering that face's colour

   function Vehicle_SGR
     (F : States.Vehicle_Face; Bulb : Character) return String
   is (case Bulb is
         when 'R'    =>
           (case F is
              when States.Red          => SGR_Red,
              when States.Flashing_Red => SGR_Blink & ";" & SGR_Red,
              when others              => SGR_Dark),
         when 'Y'    => (if F = States.Yellow then SGR_Yellow else SGR_Dark),
         when 'G'    => (if F = States.Green then SGR_Green else SGR_Dark),
         when others => Face_SGR (F));
   --  SGR colour for one character of a vehicle signal. A named bulb lights
   --  only when the face is showing it and is dim grey otherwise, so a head
   --  reads like the real thing; an unnamed bulb paints the movement's area.
   --  FLASHING_RED lights the red bulb, blinking.
   --  @param F The face value
   --  @param Bulb 'R', 'Y' or 'G' for one lamp of a head, blank for an area
   --  @return The SGR code rendering that character

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

   function SGR_Of
     (Key : Character; Bulb : Character; S : States.Display_State)
      return String
   is (case Key is
         when 'N'    => Vehicle_SGR (S.Through (States.North), Bulb),
         when 'S'    => Vehicle_SGR (S.Through (States.South), Bulb),
         when 'E'    => Vehicle_SGR (S.Through (States.East), Bulb),
         when 'W'    => Vehicle_SGR (S.Through (States.West), Bulb),
         when 'n'    => Vehicle_SGR (S.Left (States.North), Bulb),
         when 's'    => Vehicle_SGR (S.Left (States.South), Bulb),
         when 'e'    => Vehicle_SGR (S.Left (States.East), Bulb),
         when 'w'    => Vehicle_SGR (S.Left (States.West), Bulb),
         when 'A'    => Head_SGR (S.Heads (States.North_Side)),
         when 'B'    => Head_SGR (S.Heads (States.South_Side)),
         when 'C'    => Head_SGR (S.Heads (States.East_Side)),
         when 'D'    => Head_SGR (S.Heads (States.West_Side)),
         when 'a'    => Request_SGR (S.Requests (States.North_Side)),
         when 'b'    => Request_SGR (S.Requests (States.South_Side)),
         when 'c'    => Request_SGR (S.Requests (States.East_Side)),
         when 'd'    => Request_SGR (S.Requests (States.West_Side)),
         when 'y'    => SGR_Yellow,
         when others => "");
   --  Decode one character of the overlays: the SGR colour of what the mask
   --  names there, or "" for positions the mask leaves unpainted.
   --  @param Key The mask character
   --  @param Bulb The bulb character at the same position
   --  @param S The traffic state supplying the lamp values
   --  @return The SGR code, or "" when Key names nothing

   -----------------------------------------------------------------------
   --  Choosing a profile
   -----------------------------------------------------------------------

   Frame_Variable : constant String := "TRAFFIC_LIGHT_FRAME";
   --  Environment override, "wide" or "narrow", for a terminal whose size
   --  cannot be measured (a pipe, a captured test run) or to force one.

   TIOCGWINSZ : constant Interfaces.C.unsigned_long := 16#5413#;
   --  Linux's "report the window size" terminal ioctl.

   type Winsize is record
      Rows     : Interfaces.C.unsigned_short;
      Cols     : Interfaces.C.unsigned_short;
      X_Pixels : Interfaces.C.unsigned_short;
      Y_Pixels : Interfaces.C.unsigned_short;
   end record
   with Convention => C;
   --  struct winsize, as TIOCGWINSZ fills it in.
   --  @field Rows Terminal height in character cells
   --  @field Cols Terminal width in character cells
   --  @field X_Pixels Width in pixels, not populated by every terminal
   --  @field Y_Pixels Height in pixels, not populated by every terminal

   function Ioctl
     (Fd      : Interfaces.C.int;
      Request : Interfaces.C.unsigned_long;
      Size    : access Winsize) return Interfaces.C.int
   with Import, Convention => C, External_Name => "ioctl";
   --  ioctl(2). The C declaration is variadic; this profile is the shape of
   --  the TIOCGWINSZ call, whose third argument is a struct winsize *.
   --  @param Fd The file descriptor to interrogate -- standard output here
   --  @param Request The ioctl number
   --  @param Size Filled in with the window size on success
   --  @return Zero on success

   function Destination_Fd return Interfaces.C.int
   is (Interfaces.C.int
         (Interfaces.C_Streams.fileno
            (Ada.Text_IO.C_Streams.C_Stream (Current_Output))));
   --  The file descriptor the frame is actually being written to. Emit writes
   --  through the current output, which a caller may have redirected, so the
   --  size that governs the choice of picture has to be read from wherever
   --  that leads rather than from standard output on principle.
   --  @return The descriptor behind Text_IO's current output

   function Seats_Wide return Boolean;
   --  Whether the frame's destination is a terminal big enough for the wide
   --  picture. A destination that is not a terminal at all -- a file, a pipe,
   --  a captured test run -- has no size to report, and answers False.
   --  @return True when the measured window is at least 95x50

   function Seats_Wide return Boolean is
      Size : aliased Winsize;
   begin
      return
        Ioctl (Destination_Fd, TIOCGWINSZ, Size'Access) = 0
        and then Natural (Size.Cols) >= Wide_Width
        and then Natural (Size.Rows) >= Wide_Height;
   end Seats_Wide;

   function Chosen_Layout return Layout;
   --  Which profile this frame should be drawn from. Consulted per frame, so
   --  resizing the terminal takes effect at the next display write.
   --  @return The profile to render

   function Chosen_Layout return Layout is
   begin
      if Ada.Environment_Variables.Exists (Frame_Variable) then
         return
           (if Ada.Environment_Variables.Value (Frame_Variable) = "wide"
            then Wide
            else Narrow);
      end if;
      return (if Seats_Wide then Wide else Narrow);
   end Chosen_Layout;

   -----------------------------------------------------------------------
   --  Rendering
   -----------------------------------------------------------------------

   procedure Emit (Text : String);
   --  Write bytes to the current output verbatim. The frame is UTF-8 encoded
   --  by hand, and Text_IO.Put would encode it a second time: -gnatW8 sets the
   --  encoding method for Text_IO output as well as for the source, so every
   --  byte above 127 handed to Put comes back out as its own two-byte
   --  sequence. Text_Streams writes the bytes through untouched. Current, not
   --  Standard, output -- so a caller that has redirected with Set_Output
   --  still captures the frame.
   --  @param Text The bytes to write

   procedure Emit (Text : String) is
   begin
      String'Write (Text_Streams.Stream (Current_Output), Text);
   end Emit;

   New_Row : constant String := (1 => Ada.Characters.Latin_1.LF);
   --  Row separator, written through Emit like everything else in a frame.

   procedure Emit_Row
     (Art  : Wide_Wide_String;
      Mask : String;
      Bulb : String;
      S    : States.Display_State);
   --  Write one frame row, followed by an erase-to-end-of-line that clears
   --  any older, wider content underneath. A colour is introduced only where
   --  it changes, so a run of one lamp's characters costs one escape
   --  sequence rather than one per character.
   --  @param Art The row as displayed
   --  @param Mask The lamp codes at the same positions
   --  @param Bulb The bulb codes at the same positions
   --  @param S The traffic state supplying the lamp values

   procedure Emit_Row
     (Art  : Wide_Wide_String;
      Mask : String;
      Bulb : String;
      S    : States.Display_State)
   is
      Active : String (1 .. Max_SGR) := (others => ' ');
      Length : Natural := 0;
      --  The SGR body currently in effect, empty where nothing is painted.
   begin
      for Index in Art'Range loop
         declare
            Offset : constant Natural := Index - Art'First;
            SGR    : constant String :=
              SGR_Of
                (Mask (Mask'First + Offset), Bulb (Bulb'First + Offset), S);
         begin
            if SGR /= Active (1 .. Length) then
               Emit ((if SGR = "" then CSI ("0m") else CSI (SGR & "m")));
               Length := SGR'Length;
               Active (1 .. Length) := SGR;
            end if;
            Emit
              (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode
                 (Art (Index .. Index)));
         end;
      end loop;
      if Length /= 0 then
         Emit (CSI ("0m"));
      end if;
      Emit (CSI ("K"));
   end Emit_Row;

   procedure Initialize is
   begin
      --  Clear the screen so the frame owns the viewport, then banner.
      Put (CSI ("2J") & CSI ("H"));
      Put_Line ("[display/host] Initialize");
   end Initialize;

   procedure Show (S : States.Display_State) is
   begin
      --  Home the cursor and repaint the frame in place. The last row is not
      --  newline-terminated: on a terminal exactly as tall as the picture,
      --  that newline would scroll the frame off by one.
      Emit (CSI ("H"));
      case Chosen_Layout is
         when Wide   =>
            for Row in Wide_Art'Range loop
               Emit_Row (Wide_Art (Row), Wide_Mask (Row), Wide_Bulb (Row), S);
               if Row /= Wide_Art'Last then
                  Emit (New_Row);
               end if;
            end loop;

         when Narrow =>
            for Row in Narrow_Art'Range loop
               Emit_Row
                 (Narrow_Art (Row), Narrow_Mask (Row), Narrow_Bulb (Row), S);
               if Row /= Narrow_Art'Last then
                  Emit (New_Row);
               end if;
            end loop;
      end case;
      Emit (CSI ("J"));
      Flush;
   end Show;

   procedure Diag_Write_Line (S : String) is
   begin
      Put_Line ("[diag] " & S);
   end Diag_Write_Line;

end Display;
