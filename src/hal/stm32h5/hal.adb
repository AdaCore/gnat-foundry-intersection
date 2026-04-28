--  STM32H5 HAL — TO BE IMPLEMENTED.
--
--  This body will use the ST CMSIS register definitions (or Ada Drivers
--  Library bindings if available for the H5) to drive GPIO, TIM6 for the
--  1 kHz tick, and USART3 for diagnostics.
--
--  Pinout: see hardware/pinout.md.

package body HAL is

   procedure Initialize is
   begin
      null;  --  TODO: clocks, GPIOs, TIM6, USART3.
   end Initialize;

   procedure Set_Through_Lamp (App : Approach; L : Lamp; On : Boolean) is
      pragma Unreferenced (App, L, On);
   begin
      null;  --  TODO
   end Set_Through_Lamp;

   procedure Set_Left_Lamp (App : Approach; L : Lamp; On : Boolean) is
      pragma Unreferenced (App, L, On);
   begin
      null;  --  TODO
   end Set_Left_Lamp;

   procedure Set_Walk (CW : Crosswalk; Walking : Boolean) is
      pragma Unreferenced (CW, Walking);
   begin
      null;  --  TODO
   end Set_Walk;

   procedure Set_Dont_Walk (CW : Crosswalk; Steady : Boolean; Flashing : Boolean) is
      pragma Unreferenced (CW, Steady, Flashing);
   begin
      null;  --  TODO
   end Set_Dont_Walk;

   function Read_Button (CW : Crosswalk) return Boolean is
      pragma Unreferenced (CW);
   begin
      return False;  --  TODO
   end Read_Button;

   procedure Tick_Wait is
   begin
      null;  --  TODO: wait for TIM6 update event.
   end Tick_Wait;

   procedure Diag_Write_Line (S : String) is
      pragma Unreferenced (S);
   begin
      null;  --  TODO: USART3 TX.
   end Diag_Write_Line;

end HAL;
