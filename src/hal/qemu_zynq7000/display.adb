--  Display body -- bare-metal arm-eabi (Cortex-A9) profile for QEMU's
--  `xilinx-zynq-a9` machine. Drives the Cadence UART (XUartPs) UART0 at
--  0xE000_0000 via direct volatile MMIO; QEMU wires UART0 to the first
--  -serial backend. Absorbs the old Set_*_Lamp / Set_Walk / Set_Dont_Walk /
--  Diag surface -- there is no physical GPIO on the emulated machine, so the
--  traffic state is rendered as diagnostic lines on the wire stream.
--
--  XUartPs register layout (offsets from base):
--    0x00 CR   -- control: RXRST/TXRST/RXEN/TXEN
--    0x04 MR   -- mode: char length, parity, stop bits
--    0x2C SR   -- channel status: TXFULL (bit 4)
--    0x30 FIFO -- TX (write) / RX (read) byte
--
--  Note the Cadence SR polarity: a bit is set when the TX FIFO is FULL.
--
--  UART1 (the old command-input channel / Read_Cmd_Byte) is intentionally not
--  set up here -- it is deferred (see Sources and the work item Notes).

with Interfaces;              use Interfaces;
with System.Storage_Elements; use System.Storage_Elements;

package body Display is

   ----------------------------------------------------------------------
   --  Cadence UART0 register helpers
   ----------------------------------------------------------------------

   UART0_BASE : constant := 16#E000_0000#;  --  diag / wire-protocol output

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

   --  Channel-status bit.
   SR_TXFULL : constant Unsigned_32 := 16#10#;

   U0_CR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + CR_OFFSET), Import;
   U0_MR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + MR_OFFSET), Import;
   U0_SR   : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + SR_OFFSET), Import;
   U0_FIFO : Unsigned_32
   with Volatile, Address => To_Address (UART0_BASE + FIFO_OFFSET), Import;

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
   --  Display operations
   ----------------------------------------------------------------------

   procedure Initialize is
   begin
      --  UART0 -- diagnostics (TX + RX enabled; RX unused here).
      U0_CR := CR_RXRST or CR_TXRST;
      U0_MR := MR_8N1;
      U0_CR := CR_RXEN or CR_TXEN;
   end Initialize;

   procedure Diag_Write_Line (S : String) is
   begin
      for I in S'Range loop
         Tx_Byte (S (I));
      end loop;
      Tx_Byte (ASCII.LF);
   end Diag_Write_Line;

   procedure Show (S : States.Display_State) is
   begin
      for A in States.Approach loop
         Diag_Write_Line
           ("through "
            & States.Approach'Image (A)
            & " "
            & States.Vehicle_Face'Image (S.Through (A)));
      end loop;
      for A in States.Approach loop
         Diag_Write_Line
           ("left "
            & States.Approach'Image (A)
            & " "
            & States.Vehicle_Face'Image (S.Left (A)));
      end loop;
      for C in States.Crosswalk loop
         Diag_Write_Line
           ("head "
            & States.Crosswalk'Image (C)
            & " "
            & States.Pedestrian_Head'Image (S.Heads (C)));
      end loop;
      for C in States.Crosswalk loop
         Diag_Write_Line
           ("request "
            & States.Crosswalk'Image (C)
            & " "
            & States.Request_Indicator'Image (S.Requests (C)));
      end loop;
   end Show;

end Display;
