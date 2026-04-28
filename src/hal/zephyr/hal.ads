--  HAL package — Zephyr binding. Same spec as src/hal/host/ and
--  src/hal/stm32h5/ so the core code is profile-agnostic.
--
--  The body imports C functions defined in src/hal/zephyr/hal_zephyr.c,
--  which call into Zephyr's GPIO, kernel timing, and printk APIs. Pure
--  Ada bindings would require linkable symbols, but most of Zephyr's
--  GPIO and socket APIs are `static inline` in headers — see
--  alire skill zephyr.md "Bridging Zephyr's inline APIs to Ada".

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
