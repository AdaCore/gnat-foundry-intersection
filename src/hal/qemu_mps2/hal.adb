--  HAL body — bare-metal arm-eabi (Cortex-M3) profile for QEMU's
--  `mps2-an385` machine.
--
--  Two device touches:
--    * CMSDK UART0 at 0x4000_4000 — Diag_Write_Line emits the canonical
--      wire-protocol lines on UART0 byte-by-byte through volatile MMIO.
--    * Cortex-M SysTick at 0xE000_E010 — Tick_Wait blocks until the
--      next 1 ms expiry. SysTick is configured in Initialize and runs
--      free; Tick_Wait polls COUNTFLAG (cleared on read of CSR).
--
--  CMSDK UART register layout (offsets from base):
--    0x000 DATA    — RX (read) / TX (write) byte
--    0x004 STATE   — bit 0: TX BUFFER FULL, bit 1: RX BUFFER FULL
--    0x008 CTRL    — bit 0: TX ENABLE,      bit 1: RX ENABLE
--    0x010 BAUDDIV — baud divisor (>= 16 required by real CMSDK;
--                    QEMU accepts any non-zero value)
--
--  CMSDK STATE polarity is opposite to Zynq XUartPs: bits are set when
--  buffers are FULL, not empty.
--
--  See arm-echo/guest/src/echo.adb and .claude/skills/qemu/ for the
--  origin of this MMIO recipe.

with Interfaces;              use Interfaces;
with System.Storage_Elements; use System.Storage_Elements;
with Support;
pragma Unreferenced (Support);
--  Support exports `_exit` for crt0.S's reset-handler tail. Nothing
--  references it from Ada, so anchor it in this profile's closure.

package body HAL is

   ----------------------------------------------------------------------
   --  CMSDK UART0 (diagnostic output — wire-protocol § 1)
   ----------------------------------------------------------------------

   UART0_BASE : constant := 16#4000_4000#;

   U0_DATA    : Unsigned_32 with
     Volatile, Address => To_Address (UART0_BASE + 16#00#), Import;
   U0_STATE   : Unsigned_32 with
     Volatile, Address => To_Address (UART0_BASE + 16#04#), Import;
   U0_CTRL    : Unsigned_32 with
     Volatile, Address => To_Address (UART0_BASE + 16#08#), Import;
   U0_BAUDDIV : Unsigned_32 with
     Volatile, Address => To_Address (UART0_BASE + 16#10#), Import;

   STATE_TX_FULL : constant Unsigned_32 := 16#01#;

   ----------------------------------------------------------------------
   --  CMSDK UART1 (command input — wire-protocol § 2)
   ----------------------------------------------------------------------

   UART1_BASE : constant := 16#4000_5000#;

   U1_DATA    : Unsigned_32 with
     Volatile, Address => To_Address (UART1_BASE + 16#00#), Import;
   U1_STATE   : Unsigned_32 with
     Volatile, Address => To_Address (UART1_BASE + 16#04#), Import;
   U1_CTRL    : Unsigned_32 with
     Volatile, Address => To_Address (UART1_BASE + 16#08#), Import;
   U1_BAUDDIV : Unsigned_32 with
     Volatile, Address => To_Address (UART1_BASE + 16#10#), Import;

   STATE_RX_FULL  : constant Unsigned_32 := 16#02#;
   CTRL_RX_ENABLE : constant Unsigned_32 := 16#02#;

   ----------------------------------------------------------------------
   --  Cortex-M SysTick — 1 ms tick source
   ----------------------------------------------------------------------
   --  mps2-an385's nominal core clock is 25 MHz, so (25_000 - 1) cycles
   --  on the processor clock is one millisecond. Reload register is
   --  24-bit (max 0x00FFFFFF ≈ 671 ms at 25 MHz), so 25_000 fits.

   SYST_CSR : Unsigned_32 with
     Volatile, Address => To_Address (16#E000_E010#), Import;
   SYST_RVR : Unsigned_32 with
     Volatile, Address => To_Address (16#E000_E014#), Import;
   SYST_CVR : Unsigned_32 with
     Volatile, Address => To_Address (16#E000_E018#), Import;

   SYSTICK_RELOAD_1MS : constant Unsigned_32 := 25_000 - 1;

   --  CSR bit layout:
   --    bit 0  ENABLE
   --    bit 1  TICKINT     (interrupt — left disabled here)
   --    bit 2  CLKSOURCE   (1 = processor clock, 0 = external /8)
   --    bit 16 COUNTFLAG   (set when counter reached zero; cleared on read)
   SYST_ENABLE_PROC_CLK : constant Unsigned_32 := 16#05#;
   SYST_COUNTFLAG       : constant Unsigned_32 := 16#1_0000#;

   ----------------------------------------------------------------------
   --  TX primitive
   ----------------------------------------------------------------------

   procedure Tx_Byte (C : Character) is
   begin
      while (U0_STATE and STATE_TX_FULL) /= 0 loop
         null;
      end loop;
      U0_DATA := Unsigned_32 (Character'Pos (C));
   end Tx_Byte;

   ----------------------------------------------------------------------
   --  HAL operations
   ----------------------------------------------------------------------

   procedure Initialize is
   begin
      U0_BAUDDIV := 16;
      U0_CTRL    := 16#03#;        --  TX + RX enable

      --  UART1 — RX-only on this profile (host visualizer writes
      --  commands to us). Real CMSDK requires BAUDDIV >= 16; QEMU
      --  accepts any non-zero value so this also keeps the IP happy.
      U1_BAUDDIV := 16;
      U1_CTRL    := CTRL_RX_ENABLE;

      SYST_RVR := SYSTICK_RELOAD_1MS;
      SYST_CVR := 0;                --  any write clears CVR and COUNTFLAG
      SYST_CSR := SYST_ENABLE_PROC_CLK;
   end Initialize;

   procedure Set_Through_Lamp (App : Approach; L : Lamp; On : Boolean) is
      pragma Unreferenced (App, L, On);
   begin
      null;
   end Set_Through_Lamp;

   procedure Set_Left_Lamp (App : Approach; L : Lamp; On : Boolean) is
      pragma Unreferenced (App, L, On);
   begin
      null;
   end Set_Left_Lamp;

   procedure Set_Walk (CW : Crosswalk; Walking : Boolean) is
      pragma Unreferenced (CW, Walking);
   begin
      null;
   end Set_Walk;

   procedure Set_Dont_Walk
     (CW : Crosswalk; Steady : Boolean; Flashing : Boolean)
   is
      pragma Unreferenced (CW, Steady, Flashing);
   begin
      null;
   end Set_Dont_Walk;

   function Read_Button (CW : Crosswalk) return Boolean is
      pragma Unreferenced (CW);
   begin
      --  No physical GPIO on the emulated machine. Pedestrian presses
      --  arrive via the UART1 cmd-in channel (see Read_Cmd_Byte +
      --  src/app/cmd_input.adb + src/core/cmd_parser.adb), not via this
      --  primitive.
      return False;
   end Read_Button;

   procedure Read_Cmd_Byte (C : out Character; Got : out Boolean) is
   begin
      if (U1_STATE and STATE_RX_FULL) /= 0 then
         C   := Character'Val (Integer (U1_DATA and 16#FF#));
         Got := True;
      else
         C   := ASCII.NUL;
         Got := False;
      end if;
   end Read_Cmd_Byte;

   procedure Tick_Wait is
      Status : Unsigned_32;
   begin
      loop
         Status := SYST_CSR;
         exit when (Status and SYST_COUNTFLAG) /= 0;
      end loop;
   end Tick_Wait;

   procedure Diag_Write_Line (S : String) is
   begin
      for I in S'Range loop
         Tx_Byte (S (I));
      end loop;
      Tx_Byte (ASCII.LF);
   end Diag_Write_Line;

end HAL;
