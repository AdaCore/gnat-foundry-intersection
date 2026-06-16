--  HAL package — bare-metal arm-eabi (Cortex-M3) profile for QEMU's
--  `mps2-an385` machine. Same spec as src/hal/host/ so the core code is
--  profile-agnostic.
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

   --  Non-blocking byte poll on the cmd-input channel (wire-protocol § 2,
   --  CMSDK UART1 on this profile). Got=True means C holds one
   --  freshly-read byte; Got=False means no byte was available at the
   --  moment of the call. To route UART1 over TCP at qemu launch, pass a
   --  second -serial flag, e.g.
   --    qemu-system-arm ... -serial tcp:127.0.0.1:5578 \
   --                         -serial tcp:127.0.0.1:5577,server,nowait
   --  (first -serial = UART0 = diag-out; second = UART1 = cmd-in).
   procedure Read_Cmd_Byte (C : out Character; Got : out Boolean);

   procedure Tick_Wait;
   procedure Diag_Write_Line    (S : String);

end HAL;
