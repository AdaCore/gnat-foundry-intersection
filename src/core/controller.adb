--  Controller body: the five communicating Moore machines. The sub-machines
--  are kept cohesive as sections of local subprograms here (rather than child
--  units): they are genuinely communicating -- the pedestrian and left-demand
--  edges observe the vehicle sequencer's GREEN edges within a single Step -- so
--  keeping them in one body with the state threaded `in out` avoids both
--  globals and a spray of cross-unit contracts, keeping the proof closure tight.

package body Controller
  with SPARK_Mode => On
is

   use States;

   type Approach_Flags is array (States.Approach) of Boolean;

   --  The vehicle face outputs of one sequencer state: the Through and Left
   --  faces of `hlr_5_vehicle`'s output rows.
   type Vehicle_Faces is record
      Through : States.Through_Faces;
      Left    : States.Left_Faces;
   end record;

   -----------------------------------------------------------------------
   --  Moore output tables (pure functions of state)
   -----------------------------------------------------------------------

   --  The vehicle face table: rows `hlr_5_vehicle.2`-.11 (NS) and .25-.34 (EW),
   --  every unlisted face held RED. Written as explicit literal aggregates per
   --  state (rather than a DRY axis-parameterized helper -- a deferred cleanup
   --  in TODO.md) so gnatprove discharges the hlr_0_safety.2 postcondition by
   --  enumeration over constants.
   function Vehicle_Face_Outputs
     (V : States.Vehicle_Sequencer_State) return Vehicle_Faces
   is (case V is
         --  ---- NS axis (.2-.11) ----
         when N_Lead              =>              --  .2  N_thru G, N_left G
           (Through => (North => Green, others => Red),
            Left    => (North => Green, others => Red)),
         when N_Lead_Yellow       =>       --  .3  N_thru G, N_left Y
           (Through => (North => Green, others => Red),
            Left    => (North => Yellow, others => Red)),
         when N_Lead_Clear        =>        --  .4  N_thru G
           (Through => (North => Green, others => Red),
            Left    => (others => Red)),
         when NS_Both_Through     =>     --  .5  N_thru G, S_thru G
           (Through => (North => Green, South => Green, others => Red),
            Left    => (others => Red)),
         when N_Drop_Yellow       =>       --  .6  N_thru Y, S_thru G
           (Through => (North => Yellow, South => Green, others => Red),
            Left    => (others => Red)),
         when N_Drop_Clear        =>        --  .7  S_thru G
           (Through => (South => Green, others => Red),
            Left    => (others => Red)),
         when S_Lag               =>               --  .8  S_thru G, S_left G
           (Through => (South => Green, others => Red),
            Left    => (South => Green, others => Red)),
         when S_Lag_Yellow        =>        --  .9  S_thru Y, S_left Y
           (Through => (South => Yellow, others => Red),
            Left    => (South => Yellow, others => Red)),
         when NS_Both_Drop_Yellow => --  .10 N_thru Y, S_thru Y
           (Through => (North => Yellow, South => Yellow, others => Red),
            Left    => (others => Red)),
         when NS_Barrier_Allred   =>   --  .11 all RED
           (Through => (others => Red), Left => (others => Red)),
         --  ---- EW axis (.25-.34), the exact N/S <-> E/W mirror ----
         when E_Lead              =>              --  .25 E_thru G, E_left G
           (Through => (East => Green, others => Red),
            Left    => (East => Green, others => Red)),
         when E_Lead_Yellow       =>       --  .26 E_thru G, E_left Y
           (Through => (East => Green, others => Red),
            Left    => (East => Yellow, others => Red)),
         when E_Lead_Clear        =>        --  .27 E_thru G
           (Through => (East => Green, others => Red),
            Left    => (others => Red)),
         when EW_Both_Through     =>     --  .28 E_thru G, W_thru G
           (Through => (East => Green, West => Green, others => Red),
            Left    => (others => Red)),
         when E_Drop_Yellow       =>       --  .29 E_thru Y, W_thru G
           (Through => (East => Yellow, West => Green, others => Red),
            Left    => (others => Red)),
         when E_Drop_Clear        =>        --  .30 W_thru G
           (Through => (West => Green, others => Red),
            Left    => (others => Red)),
         when W_Lag               =>               --  .31 W_thru G, W_left G
           (Through => (West => Green, others => Red),
            Left    => (West => Green, others => Red)),
         when W_Lag_Yellow        =>        --  .32 W_thru Y, W_left Y
           (Through => (West => Yellow, others => Red),
            Left    => (West => Yellow, others => Red)),
         when EW_Both_Drop_Yellow => --  .33 E_thru Y, W_thru Y
           (Through => (East => Yellow, West => Yellow, others => Red),
            Left    => (others => Red)),
         when EW_Barrier_Allred   =>   --  .34 all RED
           (Through => (others => Red), Left => (others => Red)));

   --  The through face for one approach in a given sequencer state -- the
   --  signal the GREEN-edge derivations watch.
   function Through_Face
     (V : States.Vehicle_Sequencer_State; A : States.Approach)
      return States.Vehicle_Face
   is (Vehicle_Face_Outputs (V).Through (A));

   --  Pedestrian head output per sub-state (`hlr_6_pedestrian.3/.6/.10/.11/.14`).
   function Head_Of (P : States.Pedestrian_State) return States.Pedestrian_Head
   is (case P is
         when No_Pedestrian_Request      => Dont_Walk,        --  .3
         when Pending_Pedestrian_Request => Dont_Walk,        --  .6
         when Walk_Interval              => Walk,             --  .10
         when Change_Interval            => Flash_Dont_Walk,  --  .11
         when Buffer_Interval            => Dont_Walk,        --  .14
         when Buffer_Interval_Latched    => Dont_Walk);       --  .14

   --  Request indicator (lamp) per sub-state
   --  (`hlr_6_pedestrian.4/.7/.9/.16`).
   function Request_Of
     (P : States.Pedestrian_State) return States.Request_Indicator
   is (case P is
         when No_Pedestrian_Request      => No_Request,       --  .4
         when Pending_Pedestrian_Request => Request_Pending,  --  .7
         when Walk_Interval              => No_Request,       --  .9
         when Change_Interval            => No_Request,       --  .9
         when Buffer_Interval            => No_Request,       --  .9
         when Buffer_Interval_Latched    => Request_Pending); --  .16

   -----------------------------------------------------------------------
   --  Durations (pure functions of state; the T_BOTH residual is not)
   -----------------------------------------------------------------------

   --  A pedestrian sub-state runs a timer exactly in the SERVING superstate
   --  (WALK / CHANGE / BUFFER / BUFFER_LATCHED); NO_REQUEST and PENDING do not.
   function Running_Ped (P : States.Pedestrian_State) return Boolean
   is (P in States.Serving_Pedestrian_State);

   --  The fixed dwell of each timed vehicle state (`hlr_3_timing`). The
   --  both-through states are excluded -- their dwell is the residual T_BOTH
   --  computed by Both_Duration -- and map here to T_BOTH_MIN purely to keep
   --  the function total; the value is never consulted for those states.
   function Fixed_Duration
     (V : States.Vehicle_Sequencer_State) return States.Duration_Ms
   is (case V is
         when N_Lead | E_Lead                                           =>
           T_Lead,
         when S_Lag | W_Lag                                             =>
           T_Lag,
         when N_Lead_Yellow
            | S_Lag_Yellow
            | N_Drop_Yellow
            | NS_Both_Drop_Yellow
            | E_Lead_Yellow
            | W_Lag_Yellow
            | E_Drop_Yellow
            | EW_Both_Drop_Yellow                                       =>
           T_Yellow,
         when N_Lead_Clear | N_Drop_Clear | E_Lead_Clear | E_Drop_Clear =>
           T_Redclear,
         when NS_Barrier_Allred | EW_Barrier_Allred                     =>
           T_Barrier,
         when NS_Both_Through | EW_Both_Through                         =>
           T_Both_Min);

   --  The both-through residual T_BOTH (`hlr_3_timing.8`): the axis slot T_AXIS
   --  left after the barrier, and the lead and lag overheads that actually run
   --  in the slot -- so T_AXIS stays independent of left-turn demand
   --  (`hlr_3_timing.7`). Decided once, on entering the both-through state
   --  (see Enter_Both), from whether the lead ran and whether the lag will run.
   --  The postcondition captures `hlr_3_timing.12` (never below T_BOTH_MIN) and
   --  proves the subtraction cannot underflow, given the valued durations.
   function Both_Duration (Lead_Ran, Lag : Boolean) return States.Duration_Ms
   is (States.T_Axis
       - States.T_Barrier
       - (if Lead_Ran
          then States.T_Lead + States.T_Yellow + States.T_Redclear
          else 0)
       - (if Lag
          then
            States.T_Yellow
            + States.T_Redclear
            + States.T_Lag
            + States.T_Yellow
          else States.T_Yellow))
   with
     Post =>
       Both_Duration'Result >= States.T_Both_Min
       and then Both_Duration'Result <= States.T_Axis;

   -----------------------------------------------------------------------
   --  Project_Outputs
   -----------------------------------------------------------------------

   function Project_Outputs
     (State : Controller_State) return States.Display_State
   is
      Heads    : Pedestrian_Heads;
      Requests : Request_Indicators;
   begin
      --  FAULT pre-empts every region: all faces FLASHING_RED, all heads NONE,
      --  all lamps NO_REQUEST (`hlr_2_fault.1/.2/.3`).
      if State.Mode = Fault then
         return
           (Through  => (others => Flashing_Red),
            Left     => (others => Flashing_Red),
            Heads    => (others => None),
            Requests => (others => No_Request));
      end if;

      --  NORMAL_OPERATION: vehicle faces from the sequencer row, and the
      --  pedestrian head / lamp from each crosswalk's sub-state.
      for C in Crosswalk loop
         Heads (C) := Head_Of (State.Ped (C));
         Requests (C) := Request_Of (State.Ped (C));
      end loop;

      declare
         F : constant Vehicle_Faces := Vehicle_Face_Outputs (State.Vehicle);
      begin
         return
           (Through  => F.Through,
            Left     => F.Left,
            Heads    => Heads,
            Requests => Requests);
      end;
   end Project_Outputs;

   -----------------------------------------------------------------------
   --  Vehicle sequencer transitions (hlr_5_vehicle .12-.47)
   -----------------------------------------------------------------------

   --  Enter a both-through state: latch the lag decision from current demand
   --  (so guard .17/.18 or .40/.41 uses it) and size the residual dwell so the
   --  axis slot stays demand-independent.
   procedure Enter_Both
     (State : in out Controller_State; NS : Boolean; Lead_Ran : Boolean)
   is
      Lag_Pending : constant Boolean :=
        (if NS then State.Left (South) else State.Left (West))
        = Left_Demand_Pending;
   begin
      State.Veh_Lag := Lag_Pending;
      State.Vehicle := (if NS then NS_Both_Through else EW_Both_Through);
      State.Veh_Timer := Both_Duration (Lead_Ran, Lag_Pending);
   end Enter_Both;

   --  Fire the elapsed-timer transition for the current vehicle state,
   --  consulting the left-demand machines on the demand-guarded edges and
   --  reloading Veh_Timer for the new state.
   procedure Advance_Vehicle (State : in out Controller_State) is
   begin
      case State.Vehicle is
         --  ---- NS axis ----

         when EW_Barrier_Allred   =>
            --  .12/.13
            if State.Left (North) = Left_Demand_Pending then
               State.Vehicle := N_Lead;
               State.Veh_Timer := Fixed_Duration (N_Lead);
            else
               Enter_Both (State, NS => True, Lead_Ran => False);
            end if;

         when N_Lead              =>
            --  .14
            State.Vehicle := N_Lead_Yellow;
            State.Veh_Timer := Fixed_Duration (N_Lead_Yellow);

         when N_Lead_Yellow       =>
            --  .15
            State.Vehicle := N_Lead_Clear;
            State.Veh_Timer := Fixed_Duration (N_Lead_Clear);

         when N_Lead_Clear        =>
            --  .16
            Enter_Both (State, NS => True, Lead_Ran => True);

         when NS_Both_Through     =>
            --  .17/.18
            if State.Veh_Lag then
               State.Vehicle := N_Drop_Yellow;
            else
               State.Vehicle := NS_Both_Drop_Yellow;
            end if;
            State.Veh_Timer := Fixed_Duration (State.Vehicle);

         when N_Drop_Yellow       =>
            --  .19
            State.Vehicle := N_Drop_Clear;
            State.Veh_Timer := Fixed_Duration (N_Drop_Clear);

         when N_Drop_Clear        =>
            --  .20
            State.Vehicle := S_Lag;
            State.Veh_Timer := Fixed_Duration (S_Lag);

         when S_Lag               =>
            --  .21
            State.Vehicle := S_Lag_Yellow;
            State.Veh_Timer := Fixed_Duration (S_Lag_Yellow);

         when S_Lag_Yellow        =>
            --  .22
            State.Vehicle := NS_Barrier_Allred;
            State.Veh_Timer := Fixed_Duration (NS_Barrier_Allred);

         when NS_Both_Drop_Yellow =>
            --  .23
            State.Vehicle := NS_Barrier_Allred;
            State.Veh_Timer := Fixed_Duration (NS_Barrier_Allred);
         --  ---- EW axis ----

         when NS_Barrier_Allred   =>
            --  .35/.36
            if State.Left (East) = Left_Demand_Pending then
               State.Vehicle := E_Lead;
               State.Veh_Timer := Fixed_Duration (E_Lead);
            else
               Enter_Both (State, NS => False, Lead_Ran => False);
            end if;

         when E_Lead              =>
            --  .37
            State.Vehicle := E_Lead_Yellow;
            State.Veh_Timer := Fixed_Duration (E_Lead_Yellow);

         when E_Lead_Yellow       =>
            --  .38
            State.Vehicle := E_Lead_Clear;
            State.Veh_Timer := Fixed_Duration (E_Lead_Clear);

         when E_Lead_Clear        =>
            --  .39
            Enter_Both (State, NS => False, Lead_Ran => True);

         when EW_Both_Through     =>
            --  .40/.41
            if State.Veh_Lag then
               State.Vehicle := E_Drop_Yellow;
            else
               State.Vehicle := EW_Both_Drop_Yellow;
            end if;
            State.Veh_Timer := Fixed_Duration (State.Vehicle);

         when E_Drop_Yellow       =>
            --  .42
            State.Vehicle := E_Drop_Clear;
            State.Veh_Timer := Fixed_Duration (E_Drop_Clear);

         when E_Drop_Clear        =>
            --  .43
            State.Vehicle := W_Lag;
            State.Veh_Timer := Fixed_Duration (W_Lag);

         when W_Lag               =>
            --  .44
            State.Vehicle := W_Lag_Yellow;
            State.Veh_Timer := Fixed_Duration (W_Lag_Yellow);

         when W_Lag_Yellow        =>
            --  .45
            State.Vehicle := EW_Barrier_Allred;
            State.Veh_Timer := Fixed_Duration (EW_Barrier_Allred);

         when EW_Both_Drop_Yellow =>
            --  .46
            State.Vehicle := EW_Barrier_Allred;
            State.Veh_Timer := Fixed_Duration (EW_Barrier_Allred);
      end case;
   end Advance_Vehicle;

   --  Fire the elapsed-timer transition of one pedestrian crosswalk's SERVING
   --  sub-sequence (`hlr_6_pedestrian.12/.13/.17/.18`). Because both buffer
   --  exits key off time-in-SERVING (= T_WALK + T_FDW + T_BUFFER), and the .15
   --  latch does not reset the timer, running the per-sub-state timers in
   --  series realizes that without a separate serving clock. The Running_Ped
   --  precondition (discharged by the sole call site's guard) narrows the
   --  case to Serving_Pedestrian_State, so it is total over the four SERVING
   --  sub-states with no dead alternative.
   procedure Advance_Ped
     (State : in out Controller_State; C : States.Crosswalk)
   with Pre => Running_Ped (State.Ped (C))
   is
   begin
      case States.Serving_Pedestrian_State'(State.Ped (C)) is
         when Walk_Interval           =>
            --  .12  WALK -> CHANGE
            State.Ped (C) := Change_Interval;
            State.Ped_Timer (C) := T_FDW;

         when Change_Interval         =>
            --  .13  CHANGE -> BUFFER
            State.Ped (C) := Buffer_Interval;
            State.Ped_Timer (C) := T_Buffer;

         when Buffer_Interval         =>
            --  .17  BUFFER -> NO_REQUEST
            State.Ped (C) := No_Pedestrian_Request;
            State.Ped_Timer (C) := 0;

         when Buffer_Interval_Latched =>
            --  .18  LATCHED -> PENDING
            State.Ped (C) := Pending_Pedestrian_Request;
            State.Ped_Timer (C) := 0;
      end case;
   end Advance_Ped;

   -----------------------------------------------------------------------
   --  Initialize
   -----------------------------------------------------------------------

   procedure Initialize (State : out Controller_State) is
   begin
      State :=
        (Mode      => Normal_Operation,
         --  hlr_1_modes.2
         Vehicle   => EW_Barrier_Allred,
         --  hlr_5_vehicle.47
         Veh_Timer => T_Barrier,
         Veh_Lag   => False,
         Left      => (others => No_Left_Demand),
         --  ..._left_demand.2
         Ped       => (others => No_Pedestrian_Request),
         --  hlr_6_pedestrian.2
         Ped_Timer => (others => 0));
   end Initialize;

   -----------------------------------------------------------------------
   --  Step -- one core-loop iteration (see the timing model in the spec)
   -----------------------------------------------------------------------

   procedure Step
     (State   : in out Controller_State;
      Sensors : States.Sensors_State;
      Outputs : out States.Display_State;
      Wait    : out States.Duration_Ms)
   is
      Prev_V : constant Vehicle_Sequencer_State := State.Vehicle;
      Rose   : Approach_Flags;
   begin
      --  1. Fault pre-emption: entering FAULT abandons every NORMAL_OPERATION
      --     sub-machine (`hlr_1_modes.3`); FAULT is terminal (`hlr_1_modes.4`).
      --     Wait is T_SAMPLE as pacing only -- FAULT has no timed transitions;
      --     one uniform wake-up cadence in both modes keeps the loop's
      --     sampling guarantee (`llr_5_core_loop.4`) unconditional
      --     (`llr_4_controller.15`).
      if State.Mode = Fault or else Sensors.Fault = Asserted then
         State.Mode := Fault;
         Outputs := Project_Outputs (State);
         Wait := T_Sample;
         return;
      end if;

      --  2. Level-triggered input arming, done before emitting so a press this
      --     tick lights the request lamp this tick. Guarded by the source
      --     sub-state, so re-reading a held level is idempotent.
      --     left-demand arm (`hlr_5_vehicle_1_left_demand.3`)
      for A in Approach loop
         if State.Left (A) = No_Left_Demand
           and then Sensors.Left_Turns (A) = Vehicle_Present
         then
            State.Left (A) := Left_Demand_Pending;
         end if;
      end loop;
      --     pedestrian button arm: NO_REQUEST -> PENDING (`.5`) and the
      --     buffer-press latch BUFFER -> BUFFER_LATCHED (`.15`).
      for C in Crosswalk loop
         if State.Ped (C) = No_Pedestrian_Request
           and then Sensors.Buttons (C) = Pressed
         then
            State.Ped (C) := Pending_Pedestrian_Request;
         elsif State.Ped (C) = Buffer_Interval
           and then Sensors.Buttons (C) = Pressed
         then
            State.Ped (C) := Buffer_Interval_Latched;
         end if;
      end loop;

      --  3. Emit the current (post-arm) composite state's outputs.
      Outputs := Project_Outputs (State);

      --  4. Wait = min time to the next timed transition (the smallest running
      --     timer; Veh_Timer always runs in NORMAL_OPERATION, so the min is
      --     defined), capped at the sampling period T_SAMPLE
      --     (`llr_4_controller.17`). Steps where the cap wins are pure
      --     sampling steps: input arming plus re-emission of the unchanged
      --     Moore outputs.
      Wait := States.Duration_Ms'Min (T_Sample, State.Veh_Timer);
      for C in Crosswalk loop
         if Running_Ped (State.Ped (C)) and then State.Ped_Timer (C) < Wait
         then
            Wait := State.Ped_Timer (C);
         end if;
      end loop;

      --  5. Advance every timed machine by Wait; the timer(s) that reach 0 fire
      --     their timed transition. The subtraction runs only on the strictly
      --     larger branch, so it cannot underflow. When the T_SAMPLE cap won
      --     stage 4, Wait is strictly below every running timer: nothing
      --     fires and every running timer is decremented -- the pure sampling
      --     step.
      if State.Veh_Timer <= Wait then
         Advance_Vehicle (State);
      else
         State.Veh_Timer := State.Veh_Timer - Wait;
      end if;
      for C in Crosswalk loop
         if Running_Ped (State.Ped (C)) then
            if State.Ped_Timer (C) <= Wait then
               Advance_Ped (State, C);
            else
               State.Ped_Timer (C) := State.Ped_Timer (C) - Wait;
            end if;
         end if;
      end loop;

      --  6. GREEN-edge derivations off the vehicle transition just made
      --     (unchanged vehicle => no edges). A rising edge is a through face
      --     that is GREEN now and was not before.
      for A in Approach loop
         Rose (A) :=
           Through_Face (State.Vehicle, A) = Green
           and then Through_Face (Prev_V, A) /= Green;
      end loop;
      --     left-demand clear (`hlr_5_vehicle_1_left_demand.4`): a pending
      --     approach whose next conflicting movement just went GREEN.
      for A in Approach loop
         if State.Left (A) = Left_Demand_Pending
           and then Rose (Conflicts.Next_Conflicting_Through (A))
         then
            State.Left (A) := No_Left_Demand;
         end if;
      end loop;
      --     pedestrian PENDING -> WALK (`hlr_6_pedestrian.8`): a pending
      --     crosswalk whose adjacent parallel through just went GREEN.
      for C in Crosswalk loop
         if State.Ped (C) = Pending_Pedestrian_Request
           and then Rose (Conflicts.Adjacent_Through (C))
         then
            State.Ped (C) := Walk_Interval;
            State.Ped_Timer (C) := T_Walk;
         end if;
      end loop;
   end Step;

end Controller;
