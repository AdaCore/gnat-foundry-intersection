package body Buses
  with SPARK_Mode => On
is

   package body Source_Bus is
      procedure Bus_Read (Value : out States.Sensors_State) is
      begin
         --  Sample every input source through the producer. Transitional:
         --  "this samples afresh for now" -- a future asynchronous revision
         --  will have the producer drive a coalescing latch, cleared on read
         --  (design/architecture.md §Buses), so momentary events between reads
         --  are not lost. In this synchronous revision every read samples
         --  afresh, so no latch -- and hence no bus state -- is needed.
         Bus_Write (Value);
      end Bus_Read;
   end Source_Bus;

   package body Display_Bus is
      procedure Bus_Write (S : States.Display_State) is
      begin
         Bus_Read (S);
      end Bus_Write;
   end Display_Bus;

end Buses;
