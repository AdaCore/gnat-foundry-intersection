--  The observer's implementation. The recorders and the clock are body state
--  because the generic's formals are procedures with fixed profiles: there is
--  nowhere in the loop's boundary to thread a context through, so the instance
--  is a single library-level one and Observe resets its state.

with State_Machine_Loop;

package body System_Support.Timeline is

   use type States.Display_State;

   Unset : constant Interval :=
     (Frame     =>
        (Through  => (others => States.Red),
         Left     => (others => States.Red),
         Heads    => (others => States.Dont_Walk),
         Requests => (others => States.No_Request)),
      Opened_At => 0,
      Span      => 0,
      Closed    => False);
   --  Filler for the unwritten tail of the timeline. Never read: Nth's
   --  precondition keeps a test inside the recorded prefix.

   Table  : array (Interval_Index) of Interval := (others => Unset);
   Logged : Natural := 0;

   Now     : States.Duration_Ms := 0;
   Horizon : States.Duration_Ms := States.T_Sample;

   Script     : Demand_Function := null;
   Overflowed : Boolean := False;

   Escape : exception;
   --  Raised by the observing Delay_For to leave the loop. Observe absorbs it.

   procedure Obs_Delay_For (Ms : States.Duration_Ms);
   procedure Obs_Read_Sources (Sensors : out States.Sensors_State);
   procedure Obs_Write_Display (Outputs : States.Display_State);

   ------------------------------------------------------------------------
   --  The recorders
   ------------------------------------------------------------------------

   procedure Obs_Read_Sources (Sensors : out States.Sensors_State) is
   begin
      Sensors := (if Script = null then Quiet else Script (Now));
   end Obs_Read_Sources;

   procedure Obs_Write_Display (Outputs : States.Display_State) is
   begin
      if Overflowed then
         return;
      end if;

      if Logged = 0 then
         Logged := 1;
         Table (Logged) :=
           (Frame => Outputs, Opened_At => Now, Span => 0, Closed => False);

      elsif Table (Logged).Frame /= Outputs then

         --  The frame standing until this instant is over, and its span is the
         --  logical time between the two publications.

         Table (Logged).Span := Now - Table (Logged).Opened_At;
         Table (Logged).Closed := True;

         if Logged = Max_Intervals then
            Overflowed := True;
         else
            Logged := Logged + 1;
            Table (Logged) :=
              (Frame => Outputs, Opened_At => Now, Span => 0, Closed => False);
         end if;
      end if;
   end Obs_Write_Display;

   procedure Obs_Delay_For (Ms : States.Duration_Ms) is
   begin
      --  The delay is where logical time passes, and it closes the iteration.

      Now := Now + Ms;

      if Now >= Horizon then
         raise Escape;
      end if;
   end Obs_Delay_For;

   ------------------------------------------------------------------------
   --  The instance under observation
   ------------------------------------------------------------------------

   procedure Drive is new
     State_Machine_Loop
       (Delay_For     => Obs_Delay_For,
        Read_Sources  => Obs_Read_Sources,
        Write_Display => Obs_Write_Display);
   --  The composed program: the loop driving Controller, wired to the
   --  observers. This is the subject of every test here.

   ------------------------------------------------------------------------
   --  Driving an observation
   ------------------------------------------------------------------------

   procedure Observe
     (For_Ms : States.Duration_Ms; Demand : Demand_Function := null) is
   begin
      Logged := 0;
      Now := 0;
      Horizon := For_Ms;
      Script := Demand;
      Overflowed := False;

      Drive;

   --  Unreachable: Drive is No_Return and only ever leaves by Escape.

   exception
      when Escape =>

         --  The frame still standing was never replaced, so its span is only
         --  what the observation saw of it.

         if Logged > 0 then
            Table (Logged).Span := Now - Table (Logged).Opened_At;
         end if;
   end Observe;

   function Count return Natural
   is (Logged);

   function Nth (N : Interval_Index) return Interval
   is (Table (N));

   function Observed_Ms return States.Duration_Ms
   is (Now);

   function Truncated return Boolean
   is (Overflowed);

end System_Support.Timeline;
