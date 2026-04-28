--  Phase sequencer — drives the controller through the phase sequence
--  defined in docs/requirements/srs.md Section 2.3 and the state machine
--  in docs/architecture/state-machine.md.
--
--  @req FR-PH-01, FR-PH-02, FR-PH-03, FR-PH-04, FR-PH-05, FR-PH-06

with Timing;
with Conflict_Check;

package Phase_Sequencer
is

   type Phase_Id is
     (Startup,
      NS_Left_Green,   NS_Left_Yellow,
      All_Red_1,
      NS_Through_Green, NS_Through_Yellow,
      All_Red_2,
      EW_Left_Green,   EW_Left_Yellow,
      All_Red_3,
      EW_Through_Green, EW_Through_Yellow,
      All_Red_4,
      Fault);

   type State is record
      Current        : Phase_Id := Startup;
      Time_In_Phase  : Timing.Milliseconds := 0;
      Active         : Conflict_Check.Movement_Set := (others => False);
   end record;

   --  Advance the state machine by one tick (1 ms).
   procedure Tick (S : in out State);

   --  Return whether the current state is consistent with the safety
   --  predicate. Used by integration tests; in production the SPARK
   --  proof on Conflict_Check + the sequencer's invariants stand in.
   function Invariant_Holds (S : State) return Boolean;

end Phase_Sequencer;
