--  HAL package — host stub. Mirrors src/hal/stm32h5/hal.ads so the
--  core code is unchanged across profiles.

package HAL is

   type Lamp is (Red, Yellow, Green);
   type Approach is (North, South, East, West);
   type Crosswalk is (NS_North, NS_South, EW_East, EW_West);

   procedure Initialize;
   procedure Set_Through_Lamp   (App : Approach; L : Lamp; On : Boolean);
   procedure Set_Left_Lamp      (App : Approach; L : Lamp; On : Boolean);
   procedure Set_Walk           (CW : Crosswalk; Walking : Boolean);
   procedure Set_Dont_Walk      (CW : Crosswalk; Steady : Boolean; Flashing : Boolean);
   function  Read_Button        (CW : Crosswalk) return Boolean;
   procedure Tick_Wait;
   procedure Diag_Write_Line    (S : String);

end HAL;
