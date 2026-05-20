--  Pedestrian sub-state machine: Idle -> Walk -> FlashingDontWalk -> DontWalk.
--  See docs/architecture/state-machine.md § "Pedestrian sub-state machine".
--
--  @req FR-PD-01, FR-PD-02, FR-PD-03, FR-PD-04, FR-PD-05, FR-PD-06,
--       FR-PD-07, FR-PD-08

with Timing;

package Pedestrian is

   type Crosswalk is (NS_North, NS_South, EW_East, EW_West);

   type Indication is (Idle, Walk, Flashing_Dont_Walk, Dont_Walk);

   type Crosswalk_State is record
      Request_Latched : Boolean    := False;
      Indication      : Pedestrian.Indication := Idle;
      Time_In_State   : Timing.Milliseconds := 0;
   end record;

   type Crosswalk_States is array (Crosswalk) of Crosswalk_State;

   --  Latch a request (debounced upstream by the HAL).
   --  FR-PD-07: ignored if the ped phase is already active.
   procedure Press (S : in out Crosswalk_State);

   --  Begin a ped phase on this crosswalk. Enters Walk if a request is
   --  latched, otherwise Dont_Walk. Always clears the latch
   --  (FR-PD-02: latched until served).
   procedure Start_Phase (S : in out Crosswalk_State);

   --  End the ped phase: returns the crosswalk to Idle.
   procedure End_Phase (S : in out Crosswalk_State);

   --  Advance one tick (1 ms): Walk -> Flashing_Dont_Walk after T_Walk,
   --  Flashing_Dont_Walk -> Dont_Walk after T_FDW.
   procedure Tick (S : in out Crosswalk_State);

   --  Predicate: this crosswalk is currently being served (showing Walk
   --  or Flashing_Dont_Walk). Used by the sequencer to extend the
   --  through-green per FR-PD-06.
   function Is_Serving (S : Crosswalk_State) return Boolean;

end Pedestrian;
