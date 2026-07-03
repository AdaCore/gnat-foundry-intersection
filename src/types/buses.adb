package body Buses
  with SPARK_Mode => On
is

   --  Source_Bus's coalescing latch (Abstract_State => Latch) is staged for
   --  the future asynchronous revision: in this synchronous "calls Activate on
   --  read" implementation the latch is cleared on every read (see Read
   --  below), so its persistence between reads is not yet exercised
   --  (design/architecture.md §Buses). Some compiler versions therefore report
   --  the latch as an "unused hidden state". Silence that one diagnostic -- it
   --  reflects the deliberately-staged design, not a defect, and has no bearing
   --  on proof (Source_Bus has no in-SPARK instance, so gnatprove never
   --  analyses this body). Remove once the async revision drives the latch.
   pragma Warnings (Off, "*unused hidden states*");

   package body Source_Bus
     with Refined_State => (Latch => (Latched_Buttons, Latched_Left_Turns))
   is
      --  The coalescing latches. Instance state, not shared globals: each
      --  instantiation gets its own, mirroring per-bus hardware latches.
      Latched_Buttons    : States.Pedestrian_Buttons :=
        (others => States.Released);
      Latched_Left_Turns : States.Left_Turn_Detectors :=
        (others => States.No_Vehicle);

      procedure Read (Value : out States.Sensors_State) is
         use type States.Pedestrian_Button;
         use type States.Left_Turn_Detector;
      begin
         --  Sample every input source through the producer. Transitional:
         --  "this calls Activate for now" -- a future asynchronous revision
         --  will have the producer drive the latch (design/architecture.md
         --  §Buses), leaving Read a pure read-and-reset.
         Activate (Value);

         --  Coalesce fresh momentary events into whatever was already
         --  latched, so repeated presses / detections between reads collapse
         --  into a single held request ...
         for C in States.Crosswalk loop
            if Value.Buttons (C) = States.Pressed then
               Latched_Buttons (C) := States.Pressed;
            end if;
         end loop;
         for A in States.Approach loop
            if Value.Left_Turns (A) = States.Vehicle_Present then
               Latched_Left_Turns (A) := States.Vehicle_Present;
            end if;
         end loop;

         --  ... then reset on read: hand the coalesced events back to the core
         --  in the returned snapshot and clear the latches. The fault line is
         --  a level signal, so it passes through as freshly sampled.
         Value.Buttons := Latched_Buttons;
         Value.Left_Turns := Latched_Left_Turns;
         Latched_Buttons := (others => States.Released);
         Latched_Left_Turns := (others => States.No_Vehicle);
      end Read;
   end Source_Bus;
   pragma Warnings (On, "*unused hidden states*");

   package body Display_Bus is
      procedure Write (S : States.Display_State) is
      begin
         Consume (S);
      end Write;
   end Display_Bus;

end Buses;
