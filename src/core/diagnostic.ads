--  Wire-schema diagnostic emitter — produces the line format consumed by
--  the gnat-agents Bevy visualizer. The canonical schema is defined in
--  docs/requirements/wire-protocol.md.
--
--  @req FR-UI-01, FR-UI-03, FR-UI-04, NFR-DG-01
--
--  Lines go through HAL.Diag_Write_Line. The host stub prefixes "[diag] "
--  which is not part of the schema — the visualizer's --tcp mode reads
--  the raw lines from UART0, which on the qemu HAL will have no prefix.

with Phase_Sequencer;

package Diagnostic is

   --  Emit one schema-conformant transition record (wire-protocol § 1.1).
   --  @req FR-UI-03
   procedure Emit_Transition (S : Phase_Sequencer.State);

   --  Emit one heartbeat record (wire-protocol § 1.2).
   --  @req FR-UI-04
   procedure Emit_Heartbeat (Now_Ms : Natural);

end Diagnostic;
