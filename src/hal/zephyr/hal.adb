--  Zephyr HAL — TO BE IMPLEMENTED.
--
--  Each operation will pragma Import a C function from hal_zephyr.c that
--  in turn calls Zephyr APIs (gpio_pin_set_dt, k_msleep, printk, ...).
--  Initialize is wired below as the canonical example of the bridge
--  pattern; the rest are stubs to be filled in alongside hal_zephyr.c.

package body HAL is

   procedure Tlc_Init
     with Import,
          Convention    => C,
          External_Name => "tlc_zephyr_init";

   procedure Initialize is
   begin
      Tlc_Init;
   end Initialize;

   procedure Set_Through_Lamp (App : Approach; L : Lamp; On : Boolean) is
      pragma Unreferenced (App, L, On);
   begin
      null;  --  TODO: import tlc_zephyr_set_through_lamp from hal_zephyr.c.
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
      null;  --  TODO: import k_msleep wrapper from hal_zephyr.c.
   end Tick_Wait;

   procedure Diag_Write_Line (S : String) is
      pragma Unreferenced (S);
   begin
      null;  --  TODO: import printk wrapper; pass an Interfaces.C.Strings.chars_ptr.
   end Diag_Write_Line;

end HAL;
