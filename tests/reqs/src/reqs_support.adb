package body Reqs_Support is

   function Vehicle_State
     (V : States.Vehicle_Sequencer_State; Remaining : States.Duration_Ms)
      return Controller.Controller_State
   is (Mode      => States.Normal_Operation,
       Vehicle   => V,
       Veh_Timer => Remaining,
       Veh_Lag   => False,
       Left      => (others => States.No_Left_Demand),
       Ped       => (others => States.No_Pedestrian_Request),
       Ped_Timer => (others => 0));

end Reqs_Support;
