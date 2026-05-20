--  HAL host stub — prints lamp state changes to stdout, simulates the
--  1 kHz tick with a delay. Buttons read False by default; tests inject
--  presses by overriding via a separate test fixture (TBD).
--
--  Cmd-input on this profile is wired to STDIN with O_NONBLOCK so the
--  developer can pipe wire-protocol § 2 lines in (e.g.
--  `echo "PRESS PED NE" | ./bin/host/main`). On bare metal the equivalent
--  channel is CMSDK UART1; see src/hal/qemu_mps2/hal.adb.

with Ada.Text_IO;
with Ada.Calendar;
with Ada.Unchecked_Conversion;
with Interfaces;
with Interfaces.C;
with System;

package body HAL is

   use Ada.Text_IO;
   use Interfaces;

   ----------------------------------------------------------------------
   --  Non-blocking stdin for the cmd-input channel
   ----------------------------------------------------------------------

   STDIN_FD : constant Interfaces.C.int := 0;

   --  Linux fcntl constants (glibc <bits/fcntl-linux.h> on x86_64/arm):
   F_GETFL    : constant Interfaces.C.int := 3;
   F_SETFL    : constant Interfaces.C.int := 4;
   O_NONBLOCK : constant Unsigned_32      := 8#04000#;

   function C_Fcntl_Get (Fd, Cmd : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "fcntl";

   function C_Fcntl_Set
     (Fd, Cmd, Arg : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C, External_Name => "fcntl";

   function C_Read
     (Fd  : Interfaces.C.int;
      Buf : System.Address;
      N   : Interfaces.C.size_t) return Interfaces.C.long
     with Import, Convention => C, External_Name => "read";

   function To_U is new Ada.Unchecked_Conversion
     (Interfaces.C.int, Unsigned_32);
   function To_I is new Ada.Unchecked_Conversion
     (Unsigned_32, Interfaces.C.int);

   procedure Set_Stdin_Nonblocking is
      Flags : Interfaces.C.int;
      Rc    : Interfaces.C.int;
      pragma Unreferenced (Rc);
      use type Interfaces.C.int;
   begin
      Flags := C_Fcntl_Get (STDIN_FD, F_GETFL);
      if Flags >= 0 then
         Rc := C_Fcntl_Set
                 (STDIN_FD, F_SETFL, To_I (To_U (Flags) or O_NONBLOCK));
      end if;
   end Set_Stdin_Nonblocking;

   procedure Initialize is
   begin
      Put_Line ("[HAL/host] Initialize");
      Set_Stdin_Nonblocking;
   end Initialize;

   procedure Set_Through_Lamp (App : Approach; L : Lamp; On : Boolean) is
   begin
      Put_Line ("[HAL/host] through "
                & Approach'Image (App) & " "
                & Lamp'Image (L) & " "
                & Boolean'Image (On));
   end Set_Through_Lamp;

   procedure Set_Left_Lamp (App : Approach; L : Lamp; On : Boolean) is
   begin
      Put_Line ("[HAL/host] left "
                & Approach'Image (App) & " "
                & Lamp'Image (L) & " "
                & Boolean'Image (On));
   end Set_Left_Lamp;

   procedure Set_Walk (CW : Crosswalk; Walking : Boolean) is
   begin
      Put_Line ("[HAL/host] walk "
                & Crosswalk'Image (CW) & " "
                & Boolean'Image (Walking));
   end Set_Walk;

   procedure Set_Dont_Walk (CW : Crosswalk; Steady : Boolean; Flashing : Boolean) is
   begin
      Put_Line ("[HAL/host] dontwalk "
                & Crosswalk'Image (CW)
                & " steady=" & Boolean'Image (Steady)
                & " flash="  & Boolean'Image (Flashing));
   end Set_Dont_Walk;

   function Read_Button (CW : Crosswalk) return Boolean is
      pragma Unreferenced (CW);
   begin
      return False;
   end Read_Button;

   procedure Read_Cmd_Byte (C : out Character; Got : out Boolean) is
      use type Interfaces.C.long;
      Buf : Character := ASCII.NUL;
      N   : Interfaces.C.long;
   begin
      N := C_Read (STDIN_FD, Buf'Address, 1);
      if N = 1 then
         C   := Buf;
         Got := True;
      else
         --  0 = EOF, -1 = EAGAIN / EWOULDBLOCK / other error → no byte
         --  available this tick. We do not propagate EOF specially; the
         --  caller continues polling and will simply see no further
         --  bytes after stdin closes.
         C   := ASCII.NUL;
         Got := False;
      end if;
   end Read_Cmd_Byte;

   procedure Tick_Wait is
      use Ada.Calendar;
      Now : constant Time := Clock;
   begin
      delay until Now + 0.001;  -- 1 ms
   end Tick_Wait;

   procedure Diag_Write_Line (S : String) is
   begin
      Put_Line ("[diag] " & S);
   end Diag_Write_Line;

end HAL;
