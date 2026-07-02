--  Generic data-bus packages -- the boundary between the core loop and the
--  hardware (design/architecture.md §Buses). Each bus goes in a single
--  direction, from one producer to one consumer, and is instantiated once
--  per wire so the core loop only ever sees one side.
--
--  There is no asynchrony in this implementation: source buses are "reset on
--  read", display buses are "fired on write". A future revision may make
--  these protected objects; the source-bus instance state is the sanctioned
--  stand-in for that latch, hence the Abstract_State rather than an ordinary
--  global.

with States;

package Buses
  with SPARK_Mode => On
is

   --  Source data bus -- "reset on read". A single bus carries every input
   --  source at once: the producer (the HAL) samples them all into a
   --  States.Sensors_State, and the consumer (the core loop) reads a
   --  coalescing Boolean latch that is cleared on read, so multiple
   --  activations between reads collapse into a single request. The latch is
   --  guarded by an Abstract_State so it can become a protected object in a
   --  future asynchronous revision without introducing a source-level global.
   generic
      --  Producer side (HAL): sample all input sources in one shot.
      with procedure Activate (Value : out States.Sensors_State);
   package Source_Bus with Abstract_State => Latch, Initializes => Latch is
      --  Consumer side (core): sense whether a button has been pressed.
      --  Transitional -- this calls Activate for now; a later revision will
      --  have the producer drive the latch and leave Read a pure read-reset.
      procedure Read (Value : out Boolean)
      with Global => (In_Out => Latch);
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
