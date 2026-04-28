--  Pedestrian sub-state machine body — TO BE IMPLEMENTED.

package body Pedestrian is

   procedure Press (S : in out Crosswalk_State) is
   begin
      --  @req FR-PD-02 (latched until served)
      S.Request_Latched := True;
   end Press;

   procedure Tick (S : in out Crosswalk_State) is
   begin
      --  TODO: implement Walk -> FDW -> DW transitions per timing constants.
      S.Time_In_State := S.Time_In_State + 1;
   end Tick;

end Pedestrian;
