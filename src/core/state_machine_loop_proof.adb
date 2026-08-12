package body State_Machine_Loop_Proof
  with SPARK_Mode => On
is

   procedure Stub_Read_Sources (Sensors : out States.Sensors_State) is
   begin
      pragma
        Annotate
          (Xcov,
           Exempt_On,
           "proof support: see the exemption in the package spec.");
      Sensors :=
        (Buttons    => (others => States.Released),
         Left_Turns => (others => States.No_Vehicle),
         Fault      => States.Not_Asserted);
      pragma Annotate (Xcov, Exempt_Off);
   end Stub_Read_Sources;

end State_Machine_Loop_Proof;
