--  SPARK proof harness for State_Machine_Loop.
--
--  gnatprove analyses generic *instances*, not uninstantiated generics, so
--  State_Machine_Loop on its own would contribute no proof obligations to
--  `make prove`. This unit instantiates it once against trivial in-SPARK stub
--  formals, purely so the loop's absence-of-run-time-error proof (Silver) is
--  exercised by the default project closure independently of the HAL. The
--  instance is never called -- it exists only to be proved. See CLAUDE.md on
--  keeping `core` proven.

with States;
with State_Machine_Loop;

package State_Machine_Loop_Proof
  with SPARK_Mode => On
is

   --  Trivial in-SPARK stubs standing in for the HAL surface: the two writers
   --  do nothing, and the reader fully initialises the snapshot so the
   --  instance carries no uninitialised-input obligation.

   procedure Stub_Delay_For (Ms : States.Duration_Ms) is null;
   --  Stub for the delay writer -- does nothing.
   --  @param Ms Ignored

   procedure Stub_Read_Sources (Sensors : out States.Sensors_State);
   --  Stub for the source reader -- fully initialises the snapshot.
   --  @param Sensors The snapshot, fully initialised by the stub

   procedure Stub_Write_Display (Outputs : States.Display_State) is null;
   --  Stub for the display writer -- does nothing.
   --  @param Outputs Ignored

   procedure Run is new
     State_Machine_Loop
       (Delay_For     => Stub_Delay_For,
        Read_Sources  => Stub_Read_Sources,
        Write_Display => Stub_Write_Display);
   --  The instance under proof -- never called, exists only to be proved.

end State_Machine_Loop_Proof;
