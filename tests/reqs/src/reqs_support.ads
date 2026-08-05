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
   use all type States.Vehicle_Face;
   use all type States.Vehicle_Sequencer_State;

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
   --  comparison against a numbered paragraph, and the two gaps in the
   --  sequence (.7 and .18) are visible where they fall rather than only in
   --  the note below.
   Expected_Faces : constant Face_Table :=
   --  ---- NS axis ----
     (N_Lead              =>  --  .3  N through GREEN, N left GREEN
        (Through => (North => Green, others => Red),
         Left    => (North => Green, others => Red)),
      N_Lead_Yellow       =>  --  .4  N through GREEN, N left YELLOW
        (Through => (North => Green, others => Red),
         Left    => (North => Yellow, others => Red)),
      N_Lead_Clear        =>  --  .5  N through GREEN
        (Through => (North => Green, others => Red), Left => No_Left),
      NS_Both_Through     =>  --  .6  N and S through GREEN
        (Through => (North => Green, South => Green, others => Red),
         Left    => No_Left),
      --  .7 NS_BOTH_THROUGH_HOLD -- no row: the state does not exist (#63)
      N_Drop_Yellow       =>  --  .8  N through YELLOW, S through GREEN
        (Through => (North => Yellow, South => Green, others => Red),
         Left    => No_Left),
      N_Drop_Clear        =>  --  .9  S through GREEN
        (Through => (South => Green, others => Red), Left => No_Left),
      S_Lag               =>  --  .10 S through GREEN, S left GREEN
        (Through => (South => Green, others => Red),
         Left    => (South => Green, others => Red)),
      S_Lag_Yellow        =>  --  .11 S through YELLOW, S left YELLOW
        (Through => (South => Yellow, others => Red),
         Left    => (South => Yellow, others => Red)),
      NS_Both_Drop_Yellow =>  --  .12 N and S through YELLOW
        (Through => (North => Yellow, South => Yellow, others => Red),
         Left    => No_Left),
      NS_Barrier_Allred   =>  --  .13 every face RED
        (Through => No_Through, Left => No_Left),
      --  ---- EW axis ----
      E_Lead              =>  --  .14 E through GREEN, E left GREEN
        (Through => (East => Green, others => Red),
         Left    => (East => Green, others => Red)),
      E_Lead_Yellow       =>  --  .15 E through GREEN, E left YELLOW
        (Through => (East => Green, others => Red),
         Left    => (East => Yellow, others => Red)),
      E_Lead_Clear        =>  --  .16 E through GREEN
        (Through => (East => Green, others => Red), Left => No_Left),
      EW_Both_Through     =>  --  .17 E and W through GREEN
        (Through => (East => Green, West => Green, others => Red),
         Left    => No_Left),
      --  .18 EW_BOTH_THROUGH_HOLD -- no row: the state does not exist (#63)
      E_Drop_Yellow       =>  --  .19 E through YELLOW, W through GREEN
        (Through => (East => Yellow, West => Green, others => Red),
         Left    => No_Left),
      E_Drop_Clear        =>  --  .20 W through GREEN
        (Through => (West => Green, others => Red), Left => No_Left),
      W_Lag               =>  --  .21 W through GREEN, W left GREEN
        (Through => (West => Green, others => Red),
         Left    => (West => Green, others => Red)),
      W_Lag_Yellow        =>  --  .22 W through YELLOW, W left YELLOW
        (Through => (West => Yellow, others => Red),
         Left    => (West => Yellow, others => Red)),
      EW_Both_Drop_Yellow =>  --  .23 E and W through YELLOW
        (Through => (East => Yellow, West => Yellow, others => Red),
         Left    => No_Left),
      EW_Barrier_Allred   =>  --  .24 every face RED
        (Through => No_Through, Left => No_Left));
   --  NOTE: llr_4_controller_1_vehicle.7 (NS_BOTH_THROUGH_HOLD) and .18
   --  (EW_BOTH_THROUGH_HOLD) have no row here because those two sequencer
   --  states do not exist in States.Vehicle_Sequencer_State. That is the
   --  known requirements-vs-code divergence tracked by #63, not an omission
   --  in this table.

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

end Reqs_Support;
