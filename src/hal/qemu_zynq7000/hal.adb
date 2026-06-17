--  HAL body — bare-metal arm-eabi (Cortex-A9) profile for QEMU's
--  `xilinx-zynq-a9` machine, built against the `light-tasking-zynq7000`
--  GNAT runtime (Ravenscar tasking).
--
--  Two device touches:
--    * Cadence UART (XUartPs) UART0 at 0xE000_0000 — Diag_Write_Line
--      emits the canonical wire-protocol lines byte-by-byte through
--      volatile MMIO. QEMU wires UART0 to the first -serial backend.
--    * Cadence UART UART1 at 0xE000_1000 — Read_Cmd_Byte polls the RX
--      FIFO for the cmd-input channel (wire-protocol § 2). QEMU wires
--      UART1 to the second -serial backend.
--
--  XUartPs register layout (offsets from base):
--    0x00 CR    — control: RXRST/TXRST/RXEN/RXDIS/TXEN/TXDIS
--    0x04 MR    — mode: char length, parity, stop bits
--    0x2C SR    — channel status: RXEMPTY (bit 1), TXFULL (bit 4)
--    0x30 FIFO  — TX (write) / RX (read) byte
--
--  Note the Cadence SR polarity differs from the CMSDK UART used on the
--  old mps2 profile: here a bit is set when the RX FIFO is EMPTY / the
--  TX FIFO is FULL.
--
--  The 1 ms tick no longer polls a hardware counter. The light-tasking
--  runtime supplies Ada.Real_Time (backed by the Zynq private timer), so
--  Tick_Wait is an absolute `delay until` on a periodic deadline — the
--  whole reason this profile moved to a tasking runtime.

with Interfaces;              use Interfaces;
with System.Storage_Elements; use System.Storage_Elements;
with Ada.Real_Time;           use Ada.Real_Time;
with HAL.Tick_Config;

package body HAL is

   ----------------------------------------------------------------------
   --  Cadence UART register helpers
   ----------------------------------------------------------------------

   UART0_BASE : constant := 16#E000_0000#;  --  diag output  (§ 1)
   UART1_BASE : constant := 16#E000_1000#;  --  command input (§ 2)

   CR_OFFSET   : constant := 16#00#;
   MR_OFFSET   : constant := 16#04#;
   SR_OFFSET   : constant := 16#2C#;
   FIFO_OFFSET : constant := 16#30#;

   --  Control-register commands.
   CR_RXRST : constant Unsigned_32 := 16#01#;
   CR_TXRST : constant Unsigned_32 := 16#02#;
   CR_RXEN  : constant Unsigned_32 := 16#04#;
   CR_TXEN  : constant Unsigned_32 := 16#10#;

   --  Mode register: 8 data bits, no parity (PAR = 0b100), 1 stop bit.
   MR_8N1 : constant Unsigned_32 := 16#20#;

   --  Channel-status bits.
   SR_RXEMPTY : constant Unsigned_32 := 16#02#;
   SR_TXFULL  : constant Unsigned_32 := 16#10#;

   --  UART0 registers.
   U0_CR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + CR_OFFSET), Import;
   U0_MR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + MR_OFFSET), Import;
   U0_SR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + SR_OFFSET), Import;
   U0_FIFO : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + FIFO_OFFSET), Import;

   --  UART1 registers.
   U1_CR   : Unsigned_32
   with Volatile, Address => To_Address (UART1_BASE + CR_OFFSET), Import;
   U1_MR   : Unsigned_32
   with Volatile, Address => To_Address (UART1_BASE + MR_OFFSET), Import;
   U1_SR   : Unsigned_32
   with Volatile, Address => To_Address (UART1_BASE + SR_OFFSET), Import;
   U1_FIFO : Unsigned_32
   with Volatile, Address => To_Address (UART1_BASE + FIFO_OFFSET), Import;

   ----------------------------------------------------------------------
   --  Logical 1 ms tick (Ada.Real_Time, Zynq private timer)
   ----------------------------------------------------------------------
   --  Wall-clock span one logical tick waits. The µs value comes from the
   --  TICK_PERIOD_US profile spec the GPR picks (see hal-tick_config__*.ads).
   --  1000 = faithful real time (true time on a real Zynq-7000 or clock-correct
   --  QEMU). Lower values shorten each tick for a faster requirements suite:
   --  300 compensates QEMU's ~3.33x-slow Cortex-A9 timer (~100 MHz vs the
   --  runtime's assumed 333 MHz PERIPHCLK), giving ~1 ms wall/tick.
   --  Any non-1000 build is NOT faithful and should not be flashed.
   Tick_Period : constant Time_Span :=
     Microseconds (HAL.Tick_Config.Tick_Period_Us);
   Next_Tick   : Time;

   ----------------------------------------------------------------------
   --  TX primitive
   ----------------------------------------------------------------------

   procedure Tx_Byte (C : Character) is
   begin
      while (U0_SR and SR_TXFULL) /= 0 loop
         null;
      end loop;
      U0_FIFO := Unsigned_32 (Character'Pos (C));
   end Tx_Byte;

   ----------------------------------------------------------------------
   --  HAL operations
   ----------------------------------------------------------------------

   procedure Initialize is
   begin
      --  UART0 — diagnostics (TX + RX enabled; RX unused here).
      U0_CR := CR_RXRST or CR_TXRST;
      U0_MR := MR_8N1;
      U0_CR := CR_RXEN or CR_TXEN;

      --  UART1 — RX command channel (host visualizer writes to us).
      U1_CR := CR_RXRST or CR_TXRST;
      U1_MR := MR_8N1;
      U1_CR := CR_RXEN or CR_TXEN;

      Next_Tick := Clock + Tick_Period;
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
      if (U1_SR and SR_RXEMPTY) = 0 then
         C := Character'Val (Integer (U1_FIFO and 16#FF#));
         Got := True;
      else
         C := ASCII.NUL;
         Got := False;
      end if;
   end Read_Cmd_Byte;

   procedure Tick_Wait is
   begin
      delay until Next_Tick;
      Next_Tick := Next_Tick + Tick_Period;
   end Tick_Wait;

   procedure Diag_Write_Line (S : String) is
   begin
      for I in S'Range loop
         Tx_Byte (S (I));
      end loop;
      Tx_Byte (ASCII.LF);
   end Diag_Write_Line;

end HAL;
