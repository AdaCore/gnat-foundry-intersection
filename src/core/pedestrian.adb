--  Pedestrian sub-state machine body.
--
--  @req FR-PD-02, FR-PD-05, FR-PD-06, FR-PD-07

package body Pedestrian is

   procedure Press (S : in out Crosswalk_State) is
   begin
      --  FR-PD-07: pressing while the phase is already active has no effect.
      if S.Indication = Idle or else S.Indication = Dont_Walk then
         S.Request_Latched := True;
      end if;
   end Press;

   procedure Start_Phase (S : in out Crosswalk_State) is
   begin
      if S.Request_Latched then
         S.Indication := Walk;
      else
         S.Indication := Dont_Walk;
      end if;
      --  FR-PD-02: latch is consumed when the phase is served.
      S.Request_Latched := False;
      S.Time_In_State := 0;
   end Start_Phase;

   procedure End_Phase (S : in out Crosswalk_State) is
   begin
      S.Indication := Idle;
      S.Time_In_State := 0;
   end End_Phase;

   procedure Tick (S : in out Crosswalk_State) is
   begin
      --  Saturating add: Idle/Dont_Walk persist indefinitely between
      --  phases, so guard against Natural overflow. The transition
      --  guards below use >=, so saturation never perturbs a decision.
      if S.Time_In_State < Timing.Milliseconds'Last then
         S.Time_In_State := S.Time_In_State + 1;
      end if;

      --  FR-PD-05: Walk -> FDW after T_Walk; FDW -> Dont_Walk after T_FDW.
      case S.Indication is
         when Walk               =>
            if S.Time_In_State >= Timing.T_Walk then
               S.Indication := Flashing_Dont_Walk;
               S.Time_In_State := 0;
            end if;

         when Flashing_Dont_Walk =>
            if S.Time_In_State >= Timing.T_FDW then
               S.Indication := Dont_Walk;
               S.Time_In_State := 0;
            end if;

         when Idle | Dont_Walk   =>
            null;
      end case;
   end Tick;

   function Is_Serving (S : Crosswalk_State) return Boolean is
   begin
      return S.Indication = Walk or else S.Indication = Flashing_Dont_Walk;
   end Is_Serving;

end Pedestrian;
