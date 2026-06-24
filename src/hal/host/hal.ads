--  HAL package — host stub. Mirrors src/hal/qemu_zynq7000/hal.ads so the
--  core code is unchanged across profiles.

package HAL is

   type Lamp is (Red, Yellow, Green);
   type Approach is (North, South, East, West);
   type Crosswalk is (NS_North, NS_South, EW_East, EW_West);

   procedure Initialize;
   procedure Set_Through_Lamp (App : Approach; L : Lamp; On : Boolean);
   procedure Set_Left_Lamp (App : Approach; L : Lamp; On : Boolean);
   procedure Set_Walk (CW : Crosswalk; Walking : Boolean);
   procedure Set_Dont_Walk
     (CW : Crosswalk; Steady : Boolean; Flashing : Boolean);
   function Read_Button (CW : Crosswalk) return Boolean;

   --  Non-blocking byte poll on the cmd-input channel (wire-protocol § 2,
   --  UART1 on bare metal; stdin on the host stub). Got=True means C
   --  holds one freshly-read byte; Got=False means no byte was available
   --  at the moment of the call. Bytes are returned in arrival order; LF
   --  terminates a logical line at the line-assembler layer
   --  (src/app/cmd_input.adb).
   procedure Read_Cmd_Byte (C : out Character; Got : out Boolean);

   procedure Tick_Wait;
   procedure Diag_Write_Line (S : String);

end HAL;
