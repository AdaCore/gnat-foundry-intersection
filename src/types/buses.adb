package body Buses
  with SPARK_Mode => On
is

   package body Source_Bus
     with Refined_State => (Latch => Latched)
   is
      --  The coalescing latch. Instance state, not a shared global: each
      --  instantiation gets its own, mirroring a per-bus hardware latch.
      Latched : Boolean := False;

      procedure Read (Value : out Boolean) is
         use type States.Pedestrian_Button;
         Sensors : States.Sensors_State;
      begin
         --  Sample every input source through the producer. Transitional:
         --  "this calls Activate for now" -- a future asynchronous revision
         --  will have the producer drive the latch (design/architecture.md
         --  §Buses), leaving Read a pure read-and-reset.
         Activate (Sensors);

         --  Coalesce a fresh button press into whatever was already latched,
         --  so repeated presses between reads collapse into one request ...
         Latched :=
           Latched
           or else (for some B of Sensors.Buttons => B = States.Pressed);

         --  ... then reset on read: hand the request to the core and clear it.
         Value := Latched;
         Latched := False;
      end Read;
   end Source_Bus;

   package body Display_Bus is
      procedure Write (S : States.Display_State) is
      begin
         Consume (S);
      end Write;
   end Display_Bus;

end Buses;
