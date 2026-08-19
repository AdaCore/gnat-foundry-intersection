--  SPARK proof harness for Buses.Source_Bus and Buses.Display_Bus.
--
--  gnatprove analyses generic *instances*, not uninstantiated generics, so
--  Source_Bus and Display_Bus on their own contribute no proof obligations to
--  `make prove`: the enclosing package Buses is analysed and its two bus
--  bodies are not. This unit instantiates each once against trivial in-SPARK
--  stub formals, purely so their absence-of-run-time-error proof (Silver) is
--  exercised by the proof scope independently of the HAL. The instances are
--  never used -- they exist only to be proved. See CLAUDE.md on keeping `core`
--  proven.

with Buses;
with States;

package Buses_Proof
  with SPARK_Mode => On
is

   Panel : States.Display_State
   with
     Volatile,
     Async_Readers    => True,
     Async_Writers    => False,
     Effective_Reads  => False,
     Effective_Writes => True;
   --  Stands in for the display surface the display bus ultimately drives:
   --  write-only external state, so the consumer stub below has an effect the
   --  way the HAL renderer does.

   --  Trivial in-SPARK stubs standing in for the two HAL ends the buses are
   --  wired to in Main. The sampler fully initialises the snapshot, so the
   --  source-bus instance carries no uninitialised-output obligation.

   procedure Stub_Sample (Value : out States.Sensors_State);
   --  Stub for the source bus's producer -- fully initialises the snapshot.
   --  @param Value The snapshot, fully initialised by the stub

   procedure Stub_Show (S : States.Display_State);
   --  Stub for the display bus's consumer -- pushes the state to Panel.
   --  @param S The state written to Panel

   package Source_Wire is new Buses.Source_Bus (Bus_Write => Stub_Sample);
   --  The source-bus instance under proof -- its Bus_Read is never called.

   package Display_Wire is new Buses.Display_Bus (Bus_Read => Stub_Show);
   --  The display-bus instance under proof -- its Bus_Write is never called.

end Buses_Proof;
