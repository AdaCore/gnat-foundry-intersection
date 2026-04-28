--  HAL host stub — prints lamp state changes to stdout, simulates the
--  1 kHz tick with a delay. Buttons read False by default; tests inject
--  presses by overriding via a separate test fixture (TBD).

with Ada.Text_IO;
with Ada.Calendar;

package body HAL is

   use Ada.Text_IO;

   procedure Initialize is
   begin
      Put_Line ("[HAL/host] Initialize");
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
