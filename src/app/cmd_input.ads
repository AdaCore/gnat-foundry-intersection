--  Cmd_Input — UART1 line-assembly + dispatch.
--
--  Pump() drains all currently-available cmd-input bytes from HAL,
--  buffers them into a fixed-size scratch line, and hands each complete
--  (LF-terminated) line to Cmd_Parser.Dispatch. Buffer overflow drops
--  the in-progress line silently per wire-protocol § 2.
--
--  Lives in src/app/ (not src/core/) because line assembly depends on
--  HAL.Read_Cmd_Byte; keeping the byte source out of src/core/ preserves
--  the core/HAL separation called out in CLAUDE.md.
--
--  @req FR-UI-05

with Phase_Sequencer;

package Cmd_Input is

   --  Drain the cmd-input byte stream non-blockingly and dispatch any
   --  completed lines. Applied is True iff at least one line successfully
   --  mutated S — caller emits a fresh diagnostic transition record when
   --  this is True so the wire reflects the new state immediately.
   procedure Pump (S : in out Phase_Sequencer.State; Applied : out Boolean);

end Cmd_Input;
