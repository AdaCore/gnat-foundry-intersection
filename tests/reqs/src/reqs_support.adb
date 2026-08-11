package body Reqs_Support is

   function Vehicle_State
     (V : States.Vehicle_Sequencer_State; Remaining : States.Duration_Ms)
      return Controller.Controller_State
   is (Mode      => States.Normal_Operation,
       Vehicle   => V,
       Veh_Timer => Remaining,
       Left      => (others => States.No_Left_Demand),
       Ped       => (others => States.No_Pedestrian_Request),
       Ped_Timer => (others => 0));

   function Pedestrian_State
     (C         : States.Crosswalk;
      P         : States.Pedestrian_State;
      Remaining : States.Duration_Ms := 0)
      return Controller.Controller_State
   is
      State : Controller.Controller_State :=
        (Mode      => States.Normal_Operation,
         Vehicle   => EW_Barrier_Allred,
         Veh_Timer => 2 * States.T_Sample,
         Left      => (others => States.No_Left_Demand),
         Ped       => (others => States.No_Pedestrian_Request),
         Ped_Timer => (others => 0));
   begin
      State.Ped (C) := P;
      State.Ped_Timer (C) := Remaining;
      return State;
   end Pedestrian_State;

end Reqs_Support;
