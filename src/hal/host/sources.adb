--  Sources body -- host profile. Stub producer: returns an all-quiet snapshot
--  (no buttons pressed, no left-turn vehicles, no fault), preserving the old
--  Read_Button = False behaviour that the source-bus latch coalesces over.
--
--  Richer, scripted or time-based simulation of presses / detections is the
--  natural follow-up. The UART1 command-input path is intentionally NOT wired
--  here -- it is deferred per the work item's Notes and the architecture's
--  "Command-input ... TODO".

package body Sources is

   procedure Sample (Value : out States.Sensors_State) is
   begin
      Value :=
        (Buttons    => (others => States.Released),
         Left_Turns => (others => States.No_Vehicle),
         Fault      => States.Not_Asserted);
   end Sample;

end Sources;
