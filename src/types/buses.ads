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

   --  Source data bus -- "reset on read". Holds one Boolean latch: the
   --  producer (a HAL source) sets it with Activate; the consumer (the core
   --  loop) reads-and-clears it with Read_And_Reset, so multiple activations
   --  between reads coalesce into a single request. Generic so each source
   --  gets its own independent latch instance without a shared global.
   generic
   package Source_Bus with Abstract_State => Latch, Initializes => Latch is
      --  Producer side (HAL): raise the latch. The core loop never sees this.
      procedure Activate
      with Global => (Output => Latch), Depends => (Latch => null);

      --  Consumer side (core): return the current latch and clear it.
      procedure Read_And_Reset (Value : out Boolean)
      with
        Global  => (In_Out => Latch),
        Depends => (Value => Latch, Latch => null);
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
