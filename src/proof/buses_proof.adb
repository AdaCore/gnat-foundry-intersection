package body Buses_Proof
  with SPARK_Mode => On
is

   procedure Stub_Sample (Value : out States.Sensors_State) is
   begin
      Value :=
        (Buttons    => (others => States.Released),
         Left_Turns => (others => States.No_Vehicle),
         Fault      => States.Not_Asserted);
   end Stub_Sample;

   procedure Stub_Show (S : States.Display_State) is
   begin
      Panel := S;
   end Stub_Show;

end Buses_Proof;
