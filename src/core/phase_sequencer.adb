--  Phase sequencer body — TO BE IMPLEMENTED.
--
--  The implementation will:
--    * On each Tick, increment Time_In_Phase.
--    * When the current phase's exit guard is satisfied, transition to the
--      next phase per the state diagram.
--    * Update the Active movement set so that Conflict_Check.Is_Safe
--      remains True at all times.
--
--  See docs/architecture/state-machine.md for the transition table.

package body Phase_Sequencer is

   procedure Tick (S : in out State) is
   begin
      --  TODO: implement transitions.
      S.Time_In_Phase := S.Time_In_Phase + 1;
   end Tick;

   function Invariant_Holds (S : State) return Boolean is
      pragma Unreferenced (S);
   begin
      --  TODO: real check using Conflict_Check.Is_Safe (S.Active).
      return True;
   end Invariant_Holds;

end Phase_Sequencer;
