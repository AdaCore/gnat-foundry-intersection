--  Shared infrastructure for the requirements-based tests (#51).
--
--  Two things live here, and nothing else should:
--
--  1. Expected-value tables, transcribed from the requirement text. These are
--     deliberately *independent renderings* of the same English the
--     implementation was written from -- never derived from, or regenerated
--     out of, the code under test. That independence is the whole reason an
--     exhaustive cross-check is worth anything: two renderings agreeing over a
--     whole finite domain is evidence; one rendering agreeing with itself is
--     not. If a table is ever back-filled from the implementation, the tests
--     that use it stop proving anything and nothing will say so.
--
--  2. State constructors, so a test for one requirement can build the state
--     that requirement talks about directly rather than driving the machine
--     there through unrelated behaviour. Controller_State is a public record,
--     which is what makes per-requirement tests short and independent.

with Controller;
with States;

package Reqs_Support is

   use all type States.Approach;
   use all type States.Pedestrian_Head;
   use all type States.Pedestrian_State;
   use all type States.Request_Indicator;
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

   use type States.Duration_Ms;

   --  ---------------------------------------------------------------------
   --  Vehicle face rows (llr_4_controller_1_vehicle.3-.24)
   --  ---------------------------------------------------------------------

   type Face_Row is record
      Through : States.Through_Faces;
      Left    : States.Left_Faces;
   end record;

   type Face_Table is array (States.Vehicle_Sequencer_State) of Face_Row;

   No_Through : constant States.Through_Faces := (others => Red);
   No_Left    : constant States.Left_Faces := (others => Red);

   --  One row per sequencer state, transcribed from
   --  llr_4_controller_1_vehicle.3-.24. Named associations and **no `others`
   --  choice**: adding a literal to Vehicle_Sequencer_State makes this
   --  aggregate incomplete and the build fails until the new state's row is
   --  transcribed from its requirement. That is the completeness argument for
   --  the table as a whole; each row is separately *asserted* by its own
   --  routine in Llr_4_Controller_1_Vehicle_Tests, so a wrong row fails one
   --  requirement rather than all twenty-two.
   --
   --  Every row carries the statement it was transcribed from, as `.<n>` in
   --  llr_4_controller_1_vehicle. Reviewing the table is then a row-at-a-time
   --  comparison against a numbered paragraph.
   Expected_Faces : constant Face_Table :=
   --  ---- NS axis ----
     (N_Lead               =>  --  .3  N through GREEN, N left GREEN
        (Through => (North => Green, others => Red),
         Left    => (North => Green, others => Red)),
      N_Lead_Yellow        =>  --  .4  N through GREEN, N left YELLOW
        (Through => (North => Green, others => Red),
         Left    => (North => Yellow, others => Red)),
      N_Lead_Clear         =>  --  .5  N through GREEN
        (Through => (North => Green, others => Red), Left => No_Left),
      NS_Both_Through      =>  --  .6  N and S through GREEN
        (Through => (North => Green, South => Green, others => Red),
         Left    => No_Left),
      NS_Both_Through_Hold =>  --  .7  N and S through GREEN
        (Through => (North => Green, South => Green, others => Red),
         Left    => No_Left),
      N_Drop_Yellow        =>  --  .8  N through YELLOW, S through GREEN
        (Through => (North => Yellow, South => Green, others => Red),
         Left    => No_Left),
      N_Drop_Clear         =>  --  .9  S through GREEN
        (Through => (South => Green, others => Red), Left => No_Left),
      S_Lag                =>  --  .10 S through GREEN, S left GREEN
        (Through => (South => Green, others => Red),
         Left    => (South => Green, others => Red)),
      S_Lag_Yellow         =>  --  .11 S through YELLOW, S left YELLOW
        (Through => (South => Yellow, others => Red),
         Left    => (South => Yellow, others => Red)),
      NS_Both_Drop_Yellow  =>  --  .12 N and S through YELLOW
        (Through => (North => Yellow, South => Yellow, others => Red),
         Left    => No_Left),
      NS_Barrier_Allred    =>  --  .13 every face RED
        (Through => No_Through, Left => No_Left),
      --  ---- EW axis ----
      E_Lead               =>  --  .14 E through GREEN, E left GREEN
        (Through => (East => Green, others => Red),
         Left    => (East => Green, others => Red)),
      E_Lead_Yellow        =>  --  .15 E through GREEN, E left YELLOW
        (Through => (East => Green, others => Red),
         Left    => (East => Yellow, others => Red)),
      E_Lead_Clear         =>  --  .16 E through GREEN
        (Through => (East => Green, others => Red), Left => No_Left),
      EW_Both_Through      =>  --  .17 E and W through GREEN
        (Through => (East => Green, West => Green, others => Red),
         Left    => No_Left),
      EW_Both_Through_Hold =>  --  .18 E and W through GREEN
        (Through => (East => Green, West => Green, others => Red),
         Left    => No_Left),
      E_Drop_Yellow        =>  --  .19 E through YELLOW, W through GREEN
        (Through => (East => Yellow, West => Green, others => Red),
         Left    => No_Left),
      E_Drop_Clear         =>  --  .20 W through GREEN
        (Through => (West => Green, others => Red), Left => No_Left),
      W_Lag                =>  --  .21 W through GREEN, W left GREEN
        (Through => (West => Green, others => Red),
         Left    => (West => Green, others => Red)),
      W_Lag_Yellow         =>  --  .22 W through YELLOW, W left YELLOW
        (Through => (West => Yellow, others => Red),
         Left    => (West => Yellow, others => Red)),
      EW_Both_Drop_Yellow  =>  --  .23 E and W through YELLOW
        (Through => (East => Yellow, West => Yellow, others => Red),
         Left    => No_Left),
      EW_Barrier_Allred    =>  --  .24 every face RED
        (Through => No_Through, Left => No_Left));
   --  A HOLD row (.7, .18) is transcribed independently of its parent
   --  both-through row (.6, .17) even though the two statements give the same
   --  faces: they are separate paragraphs, and a table that derived one from
   --  the other could not catch a code change that moved only one of them.

   --  ---------------------------------------------------------------------
   --  Both-through commit and hold intervals
   --  (llr_4_controller_1_vehicle.26, .29, .31, .39, .42, .44)
   --  ---------------------------------------------------------------------

   --  The one dwell the requirements give as an expression rather than a
   --  constant, and the only expected value in this file shared by more than
   --  one statement's routine -- so it is transcribed once, here, in the form
   --  the statement writes it: as the arithmetic over the named durations, NOT
   --  as the millisecond total it happens to come to. A reviewer compares an
   --  expression against an expression; a number would have to be recomputed
   --  to be checked, and a wrong number reads as plausible.
   --
   --  The two commit intervals differ only in whether the axis slot already
   --  spent a leading left: entering both-through straight off the barrier,
   --  nothing has run yet; entering it from the lead's red clearance, the lead
   --  block has. Both reserve a full lagging-left block, which is what lets
   --  the lag decision wait until the interval expires.

   Commit_After_Barrier : constant States.Duration_Ms :=
     States.T_Axis
     - States.T_Barrier
     - (States.T_Yellow + States.T_Redclear + States.T_Lag + States.T_Yellow);
   --  .26 and .39: the commit interval when no lead ran.

   Commit_After_Lead : constant States.Duration_Ms :=
     States.T_Axis
     - States.T_Barrier
     - (States.T_Lead + States.T_Yellow + States.T_Redclear)
     - (States.T_Yellow + States.T_Redclear + States.T_Lag + States.T_Yellow);
   --  .29 and .42: the commit interval after a leading left ran.

   Hold_Interval : constant States.Duration_Ms :=
     States.T_Redclear + States.T_Lag + States.T_Yellow;
   --  .31 and .44: the hold interval the no-demand exit from the commit
   --  boundary runs -- the reserved lagging-left block less its closing
   --  yellow, which the both-drop yellow then supplies.

   --  ---------------------------------------------------------------------
   --  Pedestrian output rows (llr_4_controller_3_pedestrian.1-.9)
   --  ---------------------------------------------------------------------

   type Ped_Row is record
      Head    : States.Pedestrian_Head;
      Request : States.Request_Indicator;
   end record;
   --  The two output signals a crosswalk's state drives: its head (Head_Of,
   --  statements .1-.5) and its request indicator (Request_Of, .6-.9). Held as
   --  one row per state because both are Moore outputs of the same state, so a
   --  reviewer reads a state's whole output in one place -- but each column is
   --  asserted by the routine of the statement that gives it.

   type Ped_Table is array (States.Pedestrian_State) of Ped_Row;

   --  One row per pedestrian state, transcribed from
   --  llr_4_controller_3_pedestrian.1-.9. Named associations and no `others`
   --  choice, for the same reason as Expected_Faces: a new pedestrian state
   --  fails the build until its two outputs are transcribed.
   --
   --  Each row carries the two statements it came from. Note that .5 and .8
   --  each speak for more than one state -- so those statements' routines
   --  assert every state they name, and a row is never asserted by no routine.
   Expected_Ped : constant Ped_Table :=
     (No_Pedestrian_Request      =>  --  .1 DONT_WALK, .6 NO_REQUEST
        (Head => Dont_Walk, Request => No_Request),
      Pending_Pedestrian_Request =>  --  .2 DONT_WALK, .7 REQUEST_PENDING
        (Head => Dont_Walk, Request => Request_Pending),
      Walk_Interval              =>  --  .3 WALK, .8 NO_REQUEST
        (Head => Walk, Request => No_Request),
      Change_Interval            =>  --  .4 FLASH_DONT_WALK, .8 NO_REQUEST
        (Head => Flash_Dont_Walk, Request => No_Request),
      Buffer_Interval            =>  --  .5 DONT_WALK, .8 NO_REQUEST
        (Head => Dont_Walk, Request => No_Request),
      Buffer_Interval_Latched    =>  --  .5 DONT_WALK, .9 REQUEST_PENDING
        (Head => Dont_Walk, Request => Request_Pending));

   --  ---------------------------------------------------------------------
   --  State constructors
   --  ---------------------------------------------------------------------

   Quiet : constant States.Sensors_State :=
     (Buttons    => (others => States.Released),
      Left_Turns => (others => States.No_Vehicle),
      Fault      => States.Not_Asserted);
   --  No press, no vehicle, no fault: the input snapshot that arms nothing, so
   --  a test observes only the behaviour it is about.

   function Vehicle_State
     (V : States.Vehicle_Sequencer_State; Remaining : States.Duration_Ms)
      return Controller.Controller_State;
   --  A NORMAL_OPERATION state parked in sequencer state V with Remaining of
   --  its dwell left and every other machine idle.

   function Pedestrian_State
     (C         : States.Crosswalk;
      P         : States.Pedestrian_State;
      Remaining : States.Duration_Ms := 0)
      return Controller.Controller_State;
   --  A NORMAL_OPERATION state with crosswalk C in pedestrian state P and
   --  Remaining of its dwell left, every other crosswalk idle, and the vehicle
   --  sequencer parked mid-dwell in EW_BARRIER_ALLRED -- a state whose every
   --  face is RED (llr_4_controller_1_vehicle.24), so no through face can rise
   --  to GREEN during a step and key a service edge onto the crosswalk under
   --  test. What the test observes is then the pedestrian behaviour alone.

end Reqs_Support;
