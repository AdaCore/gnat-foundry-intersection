--  Cmd_Parser — pure dispatcher for UART1 command lines.
--
--  Implements the wire-protocol § 2 grammar:
--
--      PRESS PED NE|NW|SE|SW
--      SET LT NS|EW 0|1
--      FAULT 1|0
--      RESET
--
--  Tokens are case-sensitive. Unknown / malformed lines are silently
--  discarded per spec (no acknowledgement, no error reply).
--
--  This package has NO dependency on HAL — line assembly and the byte
--  source live in src/app/cmd_input.adb. Keeping the parser HAL-free
--  preserves the src/core/ vs src/hal/ separation and lets the unit test
--  drive Dispatch directly.
--
--  @req FR-UI-02, FR-UI-05, FR-PD-01, FR-PH-02, FR-SF-07

with Phase_Sequencer;

package Cmd_Parser is

   --  Apply a single command line (LF and any trailing CR already stripped
   --  by the caller). Applied is True iff the line matched a known form
   --  and mutated S — caller uses this to decide whether to emit a fresh
   --  diagnostic transition record so the wire reflects the new state
   --  without waiting for the next phase transition.
   procedure Dispatch
     (S : in out Phase_Sequencer.State; Line : String; Applied : out Boolean);

end Cmd_Parser;
