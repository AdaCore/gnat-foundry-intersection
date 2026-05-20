--  HAL package — bare-metal arm-eabi (Cortex-M3) profile for QEMU's
--  `mps2-an385` machine. Same spec as src/hal/host/ and src/hal/zephyr/
--  so the core code is profile-agnostic.
--
--  The body drives the CMSDK UART0 at 0x4000_4000 via direct volatile
--  MMIO and uses Cortex-M SysTick as the 1 ms tick source. There is no
--  physical GPIO on the emulated machine, so the lamp / walk operations
--  are no-ops; lamp state is reconstructed by the Bevy visualizer from
--  the wire-protocol phase token (docs/requirements/wire-protocol.md).

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
