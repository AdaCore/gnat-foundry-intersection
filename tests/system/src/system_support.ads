--  Shared vocabulary for the system-level tests: the idle input snapshot and
--  the frame predicates the HLR output statements are phrased over.

with States;

package System_Support is

   Quiet : constant States.Sensors_State :=
     (Buttons    => (others => States.Released),
      Left_Turns => (others => States.No_Vehicle),
      Fault      => States.Not_Asserted);
   --  No press, no vehicle, no fault: the snapshot that arms nothing.

   function All_Vehicle_Red (Frame : States.Display_State) return Boolean;
   --  Whether every through and left face of Frame is RED -- the output
   --  condition hlr_5_vehicle.11 and .34 give for the barrier states.
   --  @param Frame The published frame to examine
   --  @return True when the frame releases no vehicular movement

   function Any_Yellow (Frame : States.Display_State) return Boolean;
   --  Whether any through or left face of Frame is YELLOW -- the output
   --  condition of every vehicle change interval.
   --  @param Frame The published frame to examine
   --  @return True when the frame is ending a release

   function Released_Movements (Frame : States.Display_State) return String;
   --  The movements Frame does not hold at RED, as an approach list for a
   --  failure message; the empty string when it holds every one of them.
   --  @param Frame The published frame to examine
   --  @return The released movements, comma-separated

end System_Support;
