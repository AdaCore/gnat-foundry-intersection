--  Pedestrian sub-state machine: Idle -> Walk -> FlashingDontWalk -> DontWalk.
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
   procedure Press (S : in out Crosswalk_State);

   --  Advance one tick.
   procedure Tick (S : in out Crosswalk_State);

end Pedestrian;
