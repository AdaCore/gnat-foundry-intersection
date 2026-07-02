package body Buses
  with SPARK_Mode => On
is

   package body Source_Bus
     with Refined_State => (Latch => Latched)
   is
      --  The latch. Instance state, not a shared global: each instantiation
      --  gets its own, mirroring a per-source hardware latch.
      Latched : Boolean := False;

      procedure Activate is
      begin
         Latched := True;
      end Activate;

      procedure Read_And_Reset (Value : out Boolean) is
      begin
         Value := Latched;
         Latched := False;
      end Read_And_Reset;
   end Source_Bus;

   package body Display_Bus is
      procedure Write (S : States.Display_State) is
      begin
         Consume (S);
      end Write;
   end Display_Bus;

end Buses;
