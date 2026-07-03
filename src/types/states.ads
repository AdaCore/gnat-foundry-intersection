--  Foundational type vocabulary for the traffic-light controller.
--
--  Single source of truth for the signal alphabets, the shared
--  approach/crosswalk/lamp vocabulary, the machine-state enumerations, and
--  the named timing constants. Each declaration cites the HLR statement(s)
--  it traces to (files under `requirements/hlr/`). This package is
--  dependency-free -- it is the leaf every other layer builds on.

package States
  with SPARK_Mode => On
is

   -----------------------------------------------------------------------
   --  Signal alphabets (hlr_4_signals)
   -----------------------------------------------------------------------

   --  Output signals (driven by the controller). Only controller-meaningful
   --  *values* live here; lens/arrow/pictograph *symbology* is a HAL concern.

   --  Every vehicle face output signal (hlr_4_signals.1). Flashing_Red is a
   --  FAULT-only value (hlr_2_fault.1) but belongs to the alphabet regardless.
   type Vehicle_Face is (Red, Yellow, Green, Flashing_Red);

   --  Every crosswalk's pedestrian head output signal, where None is dark
   --  (hlr_4_signals.2). None is a FAULT-only value (hlr_2_fault.2).
   type Pedestrian_Head is (None, Walk, Flash_Dont_Walk, Dont_Walk);

   --  Every crosswalk's request indicator output signal (hlr_4_signals.3).
   type Request_Indicator is (No_Request, Request_Pending);

   --  Input signals (read by the controller).

   --  The fault-detection input signal (hlr_4_signals.4).
   type Fault_Detection is (Not_Asserted, Asserted);

   --  Each crosswalk's pedestrian demand button input signal
   --  (hlr_4_signals.5).
   type Pedestrian_Button is (Released, Pressed);

   --  Each approach's left-turn detector input signal (hlr_4_signals.6).
   type Left_Turn_Detector is (No_Vehicle, Vehicle_Present);

   -----------------------------------------------------------------------
   --  Shared approach / crosswalk / lamp vocabulary
   -----------------------------------------------------------------------

   --  The four approaches of the intersection.
   type Approach is (North, South, East, West);

   --  The four crosswalks, named by the axis and side they serve.
   type Crosswalk is (NS_North, NS_South, EW_East, EW_West);

   --  The three physical bulbs of a vehicular signal head. Red/Yellow/Green
   --  are also literals of Vehicle_Face (overloaded enumeration literals,
   --  resolved by context); a few call sites may need qualification.
   type Lamp is (Red, Yellow, Green);

   -----------------------------------------------------------------------
   --  Machine-state enumerations (requirements/state-machines.md + HLRs)
   -----------------------------------------------------------------------

   --  The two top-level operating modes (hlr_1_modes.1). Fault is terminal.
   type Mode is (Normal_Operation, Fault);

   --  Per-approach left-turn demand machine
   --  (hlr_5_vehicle_1_left_demand.1).
   type Left_Demand_State is (No_Left_Demand, Left_Demand_Pending);

   --  The vehicle phase sequencer states, declared in cycle order: the NS
   --  block then its EW mirror (hlr_5_vehicle.1, .24 and
   --  requirements/state-machines.md §2).
   type Vehicle_Sequencer_State is
     (N_Lead,
      N_Lead_Yellow,
      N_Lead_Clear,
      NS_Both_Through,
      N_Drop_Yellow,
      N_Drop_Clear,
      S_Lag,
      S_Lag_Yellow,
      NS_Both_Drop_Yellow,
      NS_Barrier_Allred,
      E_Lead,
      E_Lead_Yellow,
      E_Lead_Clear,
      EW_Both_Through,
      E_Drop_Yellow,
      E_Drop_Clear,
      W_Lag,
      W_Lag_Yellow,
      EW_Both_Drop_Yellow,
      EW_Barrier_Allred);

   --  The pedestrian crosswalk machine states (hlr_6_pedestrian.1 and
   --  requirements/state-machines.md §4). The Serving_Pedestrian_Request
   --  superstate is flattened into its four contiguous sub-states so the
   --  subtype below can name it directly.
   type Pedestrian_State is
     (No_Pedestrian_Request,
      Pending_Pedestrian_Request,
      Walk_Interval,
      Change_Interval,
      Buffer_Interval,
      Buffer_Interval_Latched);

   --  The Serving_Pedestrian_Request superstate: the RED-hold safety
   --  obligation (hlr_0_safety.1) is conditioned on being in this range.
   subtype Serving_Pedestrian_State is
     Pedestrian_State range Walk_Interval .. Buffer_Interval_Latched;

   --  Per-approach latched left-turn demand (`hlr_5_vehicle_1_left_demand`).
   type Left_Demand_Array is array (Approach) of Left_Demand_State;

   --  Per-crosswalk pedestrian control state (`hlr_6_pedestrian`).
   type Pedestrian_Array is array (Crosswalk) of Pedestrian_State;

   -----------------------------------------------------------------------
   --  Display state -- the aggregate of every output signal
   -----------------------------------------------------------------------

   --  All the output-signal values pushed to the display bus in one write:
   --  a vehicle face per approach going straight and per approach turning
   --  left, a pedestrian head per crosswalk, and a request indicator per
   --  crosswalk (hlr_4_signals.1-.3).
   type Through_Faces is array (Approach) of Vehicle_Face;
   type Left_Faces is array (Approach) of Vehicle_Face;
   type Pedestrian_Heads is array (Crosswalk) of Pedestrian_Head;
   type Request_Indicators is array (Crosswalk) of Request_Indicator;

   type Display_State is record
      Through  : Through_Faces;
      Left     : Left_Faces;
      Heads    : Pedestrian_Heads;
      Requests : Request_Indicators;
   end record;

   -----------------------------------------------------------------------
   --  Vehicle movements -- the index the safety invariant quantifies over
   -----------------------------------------------------------------------

   --  The eight vehicle movements -- the eight vehicle face output signals of
   --  `hlr_4_signals.1`: the four through movements and the four protected-left
   --  movements. This is the index the vehicle-conflict invariant
   --  `hlr_0_safety.2` quantifies over.
   type Movement is
     (N_Thru, S_Thru, E_Thru, W_Thru, N_Left, S_Left, E_Left, W_Left);

   --  The face a Display_State drives for a given movement: the through
   --  movements read the Through faces, the left movements the Left faces.
   function Face_Of (D : Display_State; M : Movement) return Vehicle_Face
   is (case M is
         when N_Thru => D.Through (North),
         when S_Thru => D.Through (South),
         when E_Thru => D.Through (East),
         when W_Thru => D.Through (West),
         when N_Left => D.Left (North),
         when S_Left => D.Left (South),
         when E_Left => D.Left (East),
         when W_Left => D.Left (West));

   --  A face is "go" -- releasing traffic -- exactly when it is GREEN or
   --  YELLOW. `hlr_0_safety.2` forbids two conflicting movements being driven
   --  to GREEN or YELLOW at once; RED and the FAULT-only FLASHING_RED are both
   --  restrictive (stop), hence safe together.
   function Is_Go (F : Vehicle_Face) return Boolean
   is (F in Green | Yellow);

   -----------------------------------------------------------------------
   --  Sensors state -- the aggregate of every input signal
   -----------------------------------------------------------------------

   --  All the input-signal values sampled from the source bus in one read:
   --  a pedestrian demand button per crosswalk, a left-turn detector per
   --  approach, and the intersection-wide fault-detection line
   --  (hlr_4_signals.4-.6). A single record so the whole input surface
   --  crosses the source bus in one shot (design/architecture.md §Buses).
   type Pedestrian_Buttons is array (Crosswalk) of Pedestrian_Button;
   type Left_Turn_Detectors is array (Approach) of Left_Turn_Detector;

   type Sensors_State is record
      Buttons    : Pedestrian_Buttons;
      Left_Turns : Left_Turn_Detectors;
      Fault      : Fault_Detection;
   end record;

   -----------------------------------------------------------------------
   --  Timing constants (hlr_3_timing)
   -----------------------------------------------------------------------

   --  All durations are in milliseconds: the HAL tick and Delay_For work in
   --  ms (design/architecture.md §Tasking / §Timing simulation). The ceiling
   --  is well above any interval and kept explicit so overflow is provable.
   type Duration_Ms is range 0 .. 3_600_000;

   --  Standard-fixed durations (hlr_3_timing.1-.3).
   T_Walk   : constant Duration_Ms := 7_000;    --  WALK interval, 7 s
   T_FDW    : constant Duration_Ms := 7_000;     --  pedestrian change, 7 s
   T_Buffer : constant Duration_Ms := 2_000;  --  pedestrian buffer, 2 s

   --  Formerly-deferred durations (hlr_3_timing.4-.9, .12): named here but
   --  valued at deployment, from the MUTCD kinematic basis
   --  (yellow/red-clear/barrier) or per-intersection policy
   --  (axis/lead/lag/both-min).
   --
   --  These are now given the satisfying provisional values `TODO.md` proposes
   --  (T_YELLOW=4, T_REDCLEAR=2, T_BARRIER=2, T_LEAD=T_LAG=6, T_BOTH_MIN=10,
   --  T_AXIS=40 s) so the vehicle sequencer's per-state waits and the T_BOTH
   --  residual are concrete and provable. The *final* valuation (kinematic
   --  basis / per-intersection policy) remains the deferred LLR item in
   --  `requirements/TODO.md`; only the placeholder values land here.
   --
   --  The set is chosen to satisfy the timing constraints the state machine
   --  relies on: hlr_3_timing.9 (T_LEAD, T_LAG <= T_AXIS / 2 = 20 s) and
   --  hlr_3_timing.12 (the both-through residual T_BOTH never drops below
   --  T_BOTH_MIN -- with these values its minimum, both lefts served, is
   --  exactly 40 - 2 - (6+4+2) - (4+2+6+4) = 10 s = T_BOTH_MIN).

   --  Kinematic basis (hlr_3_timing.4-.6):
   T_Yellow   : constant Duration_Ms := 4_000;  --  yellow change, 4 s
   T_Redclear : constant Duration_Ms := 2_000;  --  red clearance, 2 s
   T_Barrier  : constant Duration_Ms := 2_000;  --  barrier clearance, 2 s

   --  Per-intersection policy (hlr_3_timing.7, .9, .12):
   T_Axis     : constant Duration_Ms := 40_000;  --  axis service slot, 40 s
   T_Lead     : constant Duration_Ms :=
     6_000;   --  leading protected left, 6 s
   T_Lag      : constant Duration_Ms :=
     6_000;   --  lagging protected left, 6 s
   T_Both_Min : constant Duration_Ms := 10_000;  --  both-through floor, 10 s

   --  T_Both (hlr_3_timing.8), the both-through residual, is intentionally
   --  NOT declared: it is computed each cycle as the slot remainder after the
   --  lead/lag/yellow/red-clear/barrier intervals that actually run, so that
   --  T_Axis is held independent of left-turn demand (see Controller).

end States;
