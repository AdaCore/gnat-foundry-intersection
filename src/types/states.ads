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

   type Vehicle_Face is (Red, Yellow, Green, Flashing_Red);
   --  Every vehicle face output signal (hlr_4_signals.1). Flashing_Red is a
   --  FAULT-only value (hlr_2_fault.1) but belongs to the alphabet regardless.
   --  @enum Red Stop
   --  @enum Yellow Change -- release ending, about to stop
   --  @enum Green Go
   --  @enum Flashing_Red FAULT-only stop-and-proceed

   type Pedestrian_Head is (None, Walk, Flash_Dont_Walk, Dont_Walk);
   --  Every crosswalk's pedestrian head output signal, where None is dark
   --  (hlr_4_signals.2). None is a FAULT-only value (hlr_2_fault.2).
   --  @enum None Dark head -- FAULT-only
   --  @enum Walk WALK -- crossing permitted
   --  @enum Flash_Dont_Walk Flashing DONT WALK -- pedestrian clearance
   --  @enum Dont_Walk Steady DONT WALK -- do not cross

   type Request_Indicator is (No_Request, Request_Pending);
   --  Every crosswalk's request indicator output signal (hlr_4_signals.3).
   --  @enum No_Request No pedestrian request outstanding
   --  @enum Request_Pending A pedestrian request has been registered

   --  Input signals (read by the controller).

   type Fault_Detection is (Not_Asserted, Asserted);
   --  The fault-detection input signal (hlr_4_signals.4).
   --  @enum Not_Asserted No fault detected
   --  @enum Asserted A fault is being signalled

   type Pedestrian_Button is (Released, Pressed);
   --  Each crosswalk's pedestrian demand button input signal
   --  (hlr_4_signals.5).
   --  @enum Released Button not pressed
   --  @enum Pressed Button pressed this cycle

   type Left_Turn_Detector is (No_Vehicle, Vehicle_Present);
   --  Each approach's left-turn detector input signal (hlr_4_signals.6).
   --  @enum No_Vehicle No vehicle in the left-turn lane
   --  @enum Vehicle_Present A vehicle is waiting in the left-turn lane

   -----------------------------------------------------------------------
   --  Shared approach / crosswalk / lamp vocabulary
   -----------------------------------------------------------------------

   type Approach is (North, South, East, West);
   --  The four approaches of the intersection.
   --  @enum North The northbound approach
   --  @enum South The southbound approach
   --  @enum East The eastbound approach
   --  @enum West The westbound approach

   type Crosswalk is (North_Side, South_Side, East_Side, West_Side);
   --  The four crosswalks, named by the side of the junction -- the arm --
   --  each one spans (approaches, by contrast, are named by travel
   --  direction). Pedestrians on a crosswalk walk across its own arm and are
   --  served concurrently with the perpendicular axis's through green
   --  (CONOPS 3.8/3.9).
   --  @enum North_Side Spans the north arm; walked E-W with the E-W green
   --  @enum South_Side Spans the south arm; walked E-W with the E-W green
   --  @enum East_Side Spans the east arm; walked N-S with the N-S green
   --  @enum West_Side Spans the west arm; walked N-S with the N-S green

   type Lamp is (Red, Yellow, Green);
   --  The three physical bulbs of a vehicular signal head. Red/Yellow/Green
   --  are also literals of Vehicle_Face (overloaded enumeration literals,
   --  resolved by context); a few call sites may need qualification.
   --  @enum Red The red bulb
   --  @enum Yellow The yellow bulb
   --  @enum Green The green bulb

   -----------------------------------------------------------------------
   --  Machine-state enumerations (requirements/state-machines.md + HLRs)
   -----------------------------------------------------------------------

   type Mode is (Normal_Operation, Fault);
   --  The two top-level operating modes (hlr_1_modes.1). Fault is terminal.
   --  @enum Normal_Operation Ordinary signalling operation
   --  @enum Fault Terminal fault mode -- every face FLASHING_RED

   type Left_Demand_State is (No_Left_Demand, Left_Demand_Pending);
   --  Per-approach left-turn demand machine
   --  (hlr_5_vehicle_1_left_demand.1).
   --  @enum No_Left_Demand No protected-left demand latched
   --  @enum Left_Demand_Pending A protected-left demand is latched

   type Vehicle_Sequencer_State is
     (N_Lead,
      N_Lead_Yellow,
      N_Lead_Clear,
      NS_Both_Through,
      N_Drop_Yellow,
      N_Drop_Clear,
      S_Lag,
      S_Lag_Yellow,
      NS_Both_Through_Hold,
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
      EW_Both_Through_Hold,
      EW_Both_Drop_Yellow,
      EW_Barrier_Allred);
   --  The vehicle phase sequencer states.
   --  @enum N_Lead North leading protected left
   --  @enum N_Lead_Yellow North lead-left yellow change
   --  @enum N_Lead_Clear North lead-left red clearance
   --  @enum NS_Both_Through Both NS throughs green
   --  @enum N_Drop_Yellow North through yellow, dropping to the lag
   --  @enum N_Drop_Clear North through red clearance
   --  @enum S_Lag South lagging protected left
   --  @enum S_Lag_Yellow South lag-left yellow change
   --  @enum NS_Both_Through_Hold Both NS throughs green, lag declined
   --  @enum NS_Both_Drop_Yellow Both NS movements yellow, ending the axis
   --  @enum NS_Barrier_Allred NS barrier all-red clearance
   --  @enum E_Lead East leading protected left
   --  @enum E_Lead_Yellow East lead-left yellow change
   --  @enum E_Lead_Clear East lead-left red clearance
   --  @enum EW_Both_Through Both EW throughs green
   --  @enum E_Drop_Yellow East through yellow, dropping to the lag
   --  @enum E_Drop_Clear East through red clearance
   --  @enum W_Lag West lagging protected left
   --  @enum W_Lag_Yellow West lag-left yellow change
   --  @enum EW_Both_Through_Hold Both EW throughs green, lag declined
   --  @enum EW_Both_Drop_Yellow Both EW movements yellow, ending the axis
   --  @enum EW_Barrier_Allred EW barrier all-red clearance

   type Pedestrian_State is
     (No_Pedestrian_Request,
      Pending_Pedestrian_Request,
      Walk_Interval,
      Change_Interval,
      Buffer_Interval,
      Buffer_Interval_Latched);
   --  The pedestrian crosswalk machine states (hlr_6_pedestrian.1 and
   --  requirements/state-machines.md §4). The Serving_Pedestrian_Request
   --  superstate is flattened into its four contiguous sub-states so the
   --  subtype below can name it directly.
   --  @enum No_Pedestrian_Request Idle -- no demand registered
   --  @enum Pending_Pedestrian_Request Demand latched, awaiting WALK
   --  @enum Walk_Interval WALK displayed
   --  @enum Change_Interval Flashing DONT WALK -- pedestrian clearance
   --  @enum Buffer_Interval Post-clearance buffer before releasing the hold
   --  @enum Buffer_Interval_Latched Buffer with a fresh demand already latched

   subtype Serving_Pedestrian_State is
     Pedestrian_State range Walk_Interval .. Buffer_Interval_Latched;
   --  The Serving_Pedestrian_Request superstate: the RED-hold safety
   --  obligation (hlr_0_safety.1) is conditioned on being in this range.

   type Left_Demand_Array is array (Approach) of Left_Demand_State;
   --  Per-approach latched left-turn demand (`hlr_5_vehicle_1_left_demand`).

   type Pedestrian_Array is array (Crosswalk) of Pedestrian_State;
   --  Per-crosswalk pedestrian control state (`hlr_6_pedestrian`).

   -----------------------------------------------------------------------
   --  Display state -- the aggregate of every output signal
   -----------------------------------------------------------------------

   --  All the output-signal values pushed to the display bus in one write:
   --  a vehicle face per approach going straight and per approach turning
   --  left, a pedestrian head per crosswalk, and a request indicator per
   --  crosswalk (hlr_4_signals.1-.3).

   type Through_Faces is array (Approach) of Vehicle_Face;
   --  A vehicle face per approach for the through movement.

   type Left_Faces is array (Approach) of Vehicle_Face;
   --  A vehicle face per approach for the protected-left movement.

   type Pedestrian_Heads is array (Crosswalk) of Pedestrian_Head;
   --  A pedestrian head per crosswalk.

   type Request_Indicators is array (Crosswalk) of Request_Indicator;
   --  A request indicator per crosswalk.

   type Display_State is record
      Through  : Through_Faces;
      Left     : Left_Faces;
      Heads    : Pedestrian_Heads;
      Requests : Request_Indicators;
   end record;
   --  The whole output surface written to the display bus in one shot.
   --  @field Through Vehicle faces for the through movements
   --  @field Left Vehicle faces for the protected-left movements
   --  @field Heads Pedestrian heads, one per crosswalk
   --  @field Requests Request indicators, one per crosswalk

   -----------------------------------------------------------------------
   --  Vehicle movements -- the index the safety invariant quantifies over
   -----------------------------------------------------------------------

   type Movement is
     (N_Thru, S_Thru, E_Thru, W_Thru, N_Left, S_Left, E_Left, W_Left);
   --  The eight vehicle movements -- the eight vehicle face output signals of
   --  `hlr_4_signals.1`: the four through movements and the four
   --  protected-left movements. This is the index the vehicle-conflict
   --  invariant `hlr_0_safety.2` quantifies over.
   --  @enum N_Thru North through movement
   --  @enum S_Thru South through movement
   --  @enum E_Thru East through movement
   --  @enum W_Thru West through movement
   --  @enum N_Left North protected-left movement
   --  @enum S_Left South protected-left movement
   --  @enum E_Left East protected-left movement
   --  @enum W_Left West protected-left movement

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
   --  The face a Display_State drives for a given movement: the through
   --  movements read the Through faces, the left movements the Left faces.
   --  @param D The display state to read
   --  @param M The movement whose face is wanted
   --  @return The vehicle face driven for that movement

   function Is_Go (F : Vehicle_Face) return Boolean
   is (F in Green | Yellow);
   --  A face is "go" -- releasing traffic -- exactly when it is GREEN or
   --  YELLOW. `hlr_0_safety.2` forbids two conflicting movements being driven
   --  to GREEN or YELLOW at once; RED and the FAULT-only FLASHING_RED are both
   --  restrictive (stop), hence safe together.
   --  @param F The face to test
   --  @return True when the face is releasing traffic (GREEN or YELLOW)

   -----------------------------------------------------------------------
   --  Sensors state -- the aggregate of every input signal
   -----------------------------------------------------------------------

   --  All the input-signal values sampled from the source bus in one read:
   --  a pedestrian demand button per crosswalk, a left-turn detector per
   --  approach, and the intersection-wide fault-detection line
   --  (hlr_4_signals.4-.6). A single record so the whole input surface
   --  crosses the source bus in one shot (design/architecture.md §Buses).

   type Pedestrian_Buttons is array (Crosswalk) of Pedestrian_Button;
   --  A pedestrian demand button per crosswalk.

   type Left_Turn_Detectors is array (Approach) of Left_Turn_Detector;
   --  A left-turn detector per approach.

   type Sensors_State is record
      Buttons    : Pedestrian_Buttons;
      Left_Turns : Left_Turn_Detectors;
      Fault      : Fault_Detection;
   end record;
   --  The whole input surface sampled from the source bus in one shot.
   --  @field Buttons Pedestrian demand buttons, one per crosswalk
   --  @field Left_Turns Left-turn detectors, one per approach
   --  @field Fault The intersection-wide fault-detection line

   -----------------------------------------------------------------------
   --  Timing constants (hlr_3_timing)
   -----------------------------------------------------------------------

   type Duration_Ms is range 0 .. 3_600_000;
   --  All durations are in milliseconds: the HAL tick and Delay_For work in
   --  ms (design/architecture.md §Tasking / §Timing simulation). The ceiling
   --  is well above any interval and kept explicit so overflow is provable.

   --  Standard-fixed durations (hlr_3_timing.1-.3).
   T_Walk   : constant Duration_Ms := 7_000;    --  WALK interval, 7 s
   T_FDW    : constant Duration_Ms := 7_000;     --  pedestrian change, 7 s
   T_Buffer : constant Duration_Ms := 2_000;  --  pedestrian buffer, 2 s

   --  Durations (hlr_3_timing.4-.9, .12). Their final valuation belongs to
   --  deployment, from the MUTCD kinematic basis (yellow/red-clear/barrier) or
   --  per-intersection policy (axis/lead/lag/both-min), and is a deferred LLR
   --  item. The provisional values below (T_YELLOW=4, T_REDCLEAR=2,
   --  T_BARRIER=2, T_LEAD=T_LAG=6, T_BOTH_MIN=10, T_AXIS=40 s) stand in so
   --  the vehicle sequencer's per-state waits and the T_BOTH residual are
   --  concrete and provable.
   --
   --  The set is chosen to satisfy the timing constraints the state machine
   --  relies on: hlr_3_timing.9 (T_LEAD, T_LAG <= T_AXIS / 2 = 20 s) and
   --  hlr_3_timing.12 (the both-through residual T_BOTH never drops below
   --  T_BOTH_MIN -- with these values its minimum, the lead having run, is
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
   --  barrier, the lead block that actually ran, and a reserved full lagging
   --  left block, so that T_Axis is held independent of left-turn demand
   --  (see Controller).

   --  Input sampling period (hlr_3_timing.13 realization): the LLR-chosen
   --  period realizing the acknowledgment bound T_ACK = 0.2 s. Each
   --  Controller.Step accounts for exactly one T_SAMPLE of logical time and
   --  the core loop sleeps T_SAMPLE every iteration, so the inputs are
   --  re-sampled exactly once every T_SAMPLE. The valuation keeps
   --  2 x T_SAMPLE <= T_ACK: one period of worst-case latch-to-read latency,
   --  and one period of margin for processing and display rendering.
   T_Sample : constant Duration_Ms := 100;  --  input sampling period, 0.1 s

   --  Sampling-alignment constraint (llr_1_states.31): every dwell duration
   --  is an integral multiple of T_SAMPLE, which is what makes the
   --  fixed-cadence step engine exact -- every timed transition's boundary
   --  falls on a sampling boundary (llr_4_controller.17/.18). Any
   --  re-valuation of a dwell (or of T_SAMPLE) must preserve divisibility;
   --  these checks make a violation a compile-time error.
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Walk mod T_Sample /= 0,
        "T_WALK must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_FDW mod T_Sample /= 0,
        "T_FDW must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Buffer mod T_Sample /= 0,
        "T_BUFFER must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Yellow mod T_Sample /= 0,
        "T_YELLOW must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Redclear mod T_Sample /= 0,
        "T_REDCLEAR must be an integral multiple of T_SAMPLE"
        & " (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Barrier mod T_Sample /= 0,
        "T_BARRIER must be an integral multiple of T_SAMPLE"
        & " (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Axis mod T_Sample /= 0,
        "T_AXIS must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Lead mod T_Sample /= 0,
        "T_LEAD must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Lag mod T_Sample /= 0,
        "T_LAG must be an integral multiple of T_SAMPLE (llr_1_states.31)");
   --@covers llr_1_states.31
   pragma
     Compile_Time_Error
       (T_Both_Min mod T_Sample /= 0,
        "T_BOTH_MIN must be an integral multiple of T_SAMPLE"
        & " (llr_1_states.31)");

   --  Valuation checks (llr_1_states.21-.28, .30): a re-valuation that breaks
   --  a requirement is a compile-time error.
   --@covers llr_1_states.21
   pragma
     Compile_Time_Error
       (Duration_Ms'First /= 0 or else Duration_Ms'Last /= 3_600_000,
        "Duration_Ms must be the range 0 .. 3_600_000 (llr_1_states.21)");
   --@covers llr_1_states.22
   pragma
     Compile_Time_Error
       (T_Walk /= 7_000, "T_WALK must be 7_000 ms (llr_1_states.22)");
   --@covers llr_1_states.23
   pragma
     Compile_Time_Error
       (T_FDW /= 7_000, "T_FDW must be 7_000 ms (llr_1_states.23)");
   --@covers llr_1_states.24
   pragma
     Compile_Time_Error
       (T_Buffer /= 2_000, "T_BUFFER must be 2_000 ms (llr_1_states.24)");
   --@covers llr_1_states.25
   pragma
     Compile_Time_Error
       (T_Yellow /= 4_000
        or else T_Redclear /= 2_000
        or else T_Barrier /= 2_000,
        "kinematic durations must hold their provisional values"
        & " (llr_1_states.25)");
   --@covers llr_1_states.26
   pragma
     Compile_Time_Error
       (T_Axis /= 40_000
        or else T_Lead /= 6_000
        or else T_Lag /= 6_000
        or else T_Both_Min /= 10_000,
        "policy durations must hold their required values (llr_1_states.26)");
   --@covers llr_1_states.27
   pragma
     Compile_Time_Error
       (T_Both_Min + T_Yellow + T_Barrier < T_Walk + T_FDW + T_Buffer,
        "pedestrian service must fit the both-through window"
        & " (llr_1_states.27)");
   --@covers llr_1_states.28
   pragma
     Compile_Time_Error
       (T_Axis - T_Barrier - T_Yellow - T_Lag < T_Walk + T_FDW + T_Buffer,
        "pedestrian service must fit the axis slot (llr_1_states.28)");
   --  A compile-time claim about the constants, not about what Both_Duration
   --  computes from them: the residual is fixed by the valuation.
   --@covers llr_1_states.29
   pragma
     Compile_Time_Error
       (T_Axis
        - T_Barrier
        - (T_Lead + T_Yellow + T_Redclear)
        - (T_Yellow + T_Redclear + T_Lag + T_Yellow)
        < T_Both_Min,
        "the both-through residual must not fall below T_BOTH_MIN"
        & " (llr_1_states.29)");
   --@covers llr_1_states.30
   pragma
     Compile_Time_Error
       (T_Sample /= 100, "T_SAMPLE must be 100 ms (llr_1_states.30)");

end States;
