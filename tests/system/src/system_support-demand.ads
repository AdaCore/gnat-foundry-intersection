--  Scripted input demand: what the sources read, as windows of logical time.

with States;

package System_Support.Demand is

   Forever : constant States.Duration_Ms := States.Duration_Ms'Last;
   --  A bound no observation reaches.

   procedure Clear;
   --  Discard every window, leaving every input idle.

   procedure Press
     (C      : States.Crosswalk;
      From   : States.Duration_Ms;
      Before : States.Duration_Ms := Forever);
   --  Read C's button PRESSED over [From, Before), replacing C's window.
   --  @param C The crosswalk whose button is pressed
   --  @param From The first logical time the press is readable
   --  @param Before The first logical time it is not

   procedure Left_Turn
     (A      : States.Approach;
      From   : States.Duration_Ms;
      Before : States.Duration_Ms := Forever);
   --  Read A's detector VEHICLE_PRESENT over [From, Before), replacing A's
   --  window.
   --  @param A The approach whose left-turn lane holds a vehicle
   --  @param From The first logical time the vehicle is readable
   --  @param Before The first logical time it is not

   function Snapshot
     (Elapsed : States.Duration_Ms) return States.Sensors_State;
   --  The scripted snapshot at Elapsed; FAULT is never asserted.
   --  @param Elapsed The logical time standing at this read
   --  @return The snapshot to deliver

end System_Support.Demand;
