--  Body state, as Timeline's recorders are. One window per input.

package body System_Support.Demand is

   use type States.Duration_Ms;

   type Window is record
      From   : States.Duration_Ms;
      Before : States.Duration_Ms;
   end record;
   --  The span of logical time over which one input reads asserted.
   --  @field From The first logical time it does
   --  @field Before The first logical time it does not

   Idle : constant Window := (From => Forever, Before => Forever);
   --  A window no read falls inside.

   Buttons : array (States.Crosswalk) of Window := (others => Idle);
   Lefts   : array (States.Approach) of Window := (others => Idle);

   function Open (W : Window; Elapsed : States.Duration_Ms) return Boolean
   is (Elapsed >= W.From and then Elapsed < W.Before);

   procedure Clear is
   begin
      Buttons := (others => Idle);
      Lefts := (others => Idle);
   end Clear;

   procedure Press
     (C      : States.Crosswalk;
      From   : States.Duration_Ms;
      Before : States.Duration_Ms := Forever) is
   begin
      Buttons (C) := (From => From, Before => Before);
   end Press;

   procedure Left_Turn
     (A      : States.Approach;
      From   : States.Duration_Ms;
      Before : States.Duration_Ms := Forever) is
   begin
      Lefts (A) := (From => From, Before => Before);
   end Left_Turn;

   function Snapshot
     (Elapsed : States.Duration_Ms) return States.Sensors_State
   is
      Result : States.Sensors_State := Quiet;
   begin
      for C in States.Crosswalk loop
         if Open (Buttons (C), Elapsed) then
            Result.Buttons (C) := States.Pressed;
         end if;
      end loop;

      for A in States.Approach loop
         if Open (Lefts (A), Elapsed) then
            Result.Left_Turns (A) := States.Vehicle_Present;
         end if;
      end loop;

      return Result;
   end Snapshot;

end System_Support.Demand;
