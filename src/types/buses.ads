--  Generic data-bus packages -- the boundary between the core loop and the
--  hardware (design/architecture.md §Buses). Each bus goes in a single
--  direction, from one producer to one consumer, and is instantiated once
--  per wire so the core loop only ever sees one side.
--
--  There is no asynchrony in this implementation: source buses are "reset on
--  read", display buses are "fired on write". A future revision may make
--  these protected objects, at which point the source bus will carry a
--  coalescing latch as instance state; for now Read samples afresh and holds
--  no state.

with States;

package Buses
  with SPARK_Mode => On
is

   --  Source data bus -- "reset on read". A single bus carries every input
   --  source at once: the producer (the HAL) samples them all into a
   --  States.Sensors_State, and the consumer (the core loop) reads that whole
   --  snapshot back. A future asynchronous revision will add a coalescing
   --  latch here -- cleared on read so momentary events (button presses,
   --  left-turn detections) between reads collapse into a single held request
   --  -- carried as instance state. In this synchronous revision Read samples
   --  afresh through the producer on every call, so the bus holds no state.
   generic
      --  Producer side (HAL): sample all input sources in one shot.
      with procedure Activate (Value : out States.Sensors_State);
   package Source_Bus is
      --  Consumer side (core): read the whole sensor snapshot. Transitional --
      --  this samples afresh through Activate for now; a later revision will
      --  have the producer drive a latch and leave Read a pure read-reset.
      procedure Read (Value : out States.Sensors_State);
   end Source_Bus;

   --  Display data bus -- "fired on write". Holds the traffic-light state and
   --  pushes it to the consumer the instant it is written. Parameterized over
   --  the consumer procedure so the core loop (producer) stays ignorant of the
   --  display implementation (design/architecture.md §The core loop).
   generic
      with procedure Consume (S : States.Display_State);
   package Display_Bus is
      --  Producer side (core): push the state to the consumer synchronously.
      procedure Write (S : States.Display_State);
   end Display_Bus;

end Buses;
