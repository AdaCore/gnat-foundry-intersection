--  HAL package — STM32H5 binding.
--
--  Provides the abstract operations the core layer needs:
--    * Initialize: bring up clocks, GPIO, timers, UART.
--    * Set_Lamp / Set_Walk_Sign: drive the indicators.
--    * Read_Button: sample a (debounced) pedestrian button.
--    * Tick_Wait: block until the next 1 ms tick.
--
--  The same spec exists in src/hal/host/ with a stub body for
--  desktop simulation and unit testing.

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
