--  The published-frame timeline: what the display showed, and for how long.
--
--  State_Machine_Loop is No_Return, so it is observed the way
--  Reqs_Support.Loop_Spy observes it -- instantiated against recording formals
--  and left by raising from the innermost stage. What differs is the level.
--  The spy records one event per stage and a test reads iterations off it;
--  this observer discards iteration structure and records one entry per
--  *published frame*, however many iterations republished it. A 40-second axis
--  slot is 400 iterations and one entry.
--
--  Logical time is the only time here, accumulated from the periods the loop
--  hands Delay_For. A publication is timestamped at the logical time standing
--  when Write_Display is called, which is before that iteration's Delay_For:
--  the loop publishes and then sleeps. The wall-clock span of a logical
--  millisecond is Timings.Tick_Config, and the accuracy of the sleep itself is
--  a HAL property outside the verification scope.

with States;

package System_Support.Timeline is

   Max_Intervals : constant := 128;
   --  Entries a single observation can hold. One entry per published frame,
   --  so a full two-axis cycle is well inside this.

   subtype Interval_Index is Positive range 1 .. Max_Intervals;

   type Interval is record
      Frame     : States.Display_State;
      Opened_At : States.Duration_Ms;
      Span      : States.Duration_Ms;
      Closed    : Boolean;
   end record;
   --  One published frame and the span it was displayed for.
   --  @field Frame The frame handed to Write_Display
   --  @field Opened_At Logical time of its first publication
   --  @field Span Logical time displayed; a lower bound unless Closed
   --  @field Closed Whether a later frame replaced it inside the observation

   type Demand_Function is
     access function
       (Elapsed : States.Duration_Ms) return States.Sensors_State;
   --  What Read_Sources delivers, as a function of the logical time standing
   --  at that read. Demand is scripted against the clock rather than against
   --  an iteration count, which is the level these tests work at.
   --  @param Elapsed The logical time standing at this read
   --  @return The snapshot to deliver

   procedure Observe
     (For_Ms : States.Duration_Ms; Demand : Demand_Function := null)
   with
     Pre =>
       For_Ms > 0 and then For_Ms <= States.Duration_Ms'Last - States.T_Sample;
   --  Drive the loop from power-on until For_Ms of logical time has passed,
   --  recording the timeline. Discards the previous observation. A null Demand
   --  delivers Quiet at every read.
   --  @param For_Ms How much logical time to observe
   --  @param Demand The snapshot to deliver at each read

   function Count return Natural;
   --  How many frames the last observation published.
   --  @return The number of entries in the timeline

   function Nth (N : Interval_Index) return Interval
   with Pre => N <= Count;
   --  The Nth entry of the last observation, in publication order.
   --  @param N Which entry, counting from the first frame published
   --  @return That entry

   function Observed_Ms return States.Duration_Ms;
   --  The logical time the last observation actually spanned, which overshoots
   --  its For_Ms by less than one sampling period.
   --  @return The logical time observed

   function Truncated return Boolean;
   --  Whether the last observation published more frames than Max_Intervals
   --  holds, so the timeline is a prefix of the run.
   --  @return True when entries were dropped

end System_Support.Timeline;
