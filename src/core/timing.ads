--  Build-time timing constants.
--
--  This is the single source of truth for the controller's timing.
--  See docs/requirements/timing-parameters.md for rationale.
--
--  Any change here must be mirrored in the Markdown table; CI verifies
--  the two agree (tools/timing-check.py).

package Timing
  with SPARK_Mode => On, Pure
is

   --  Time is represented as milliseconds (Natural). The 1 kHz tick gives
   --  us 1 ms resolution, which is more than enough for traffic timing.

   subtype Milliseconds is Natural;

   --  @req NFR-MN-02
   T_Min_G   : constant Milliseconds := 7_000;   -- min through green
   T_Max_G   : constant Milliseconds := 60_000;   -- max through green
   T_Y       : constant Milliseconds := 3_000;   -- yellow
   T_AR      : constant Milliseconds := 2_000;   -- all-red clearance
   T_LT_G    : constant Milliseconds := 8_000;   -- left-turn green
   T_Walk    : constant Milliseconds := 5_000;   -- pedestrian WALK
   T_FDW     : constant Milliseconds := 10_000;   -- flashing don't-walk
   T_Startup : constant Milliseconds := 5_000;   -- power-up flash period
   T_Fault   : constant Milliseconds := 1_000;   -- fault-flash period

   --  Sanity checks at compile time.
   pragma Compile_Time_Error (T_Y < 1_000, "Yellow time too short");

   pragma Compile_Time_Error (T_Min_G < T_Y, "Min green must exceed yellow");

   pragma
     Compile_Time_Error
       (T_Walk + T_FDW > T_Max_G, "WALK + FDW must fit within max green");

end Timing;
