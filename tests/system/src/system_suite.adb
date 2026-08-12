--  The suite's test-case objects are body state because AUnit.Test_Caller
--  registers them by reference: they have to outlive the call to Suite.

with AUnit.Test_Caller;

with Demand_Tests;
with Hlr_3_Timing_Tests;
with Timeline_Tests;

package body System_Suite is

   use AUnit.Test_Suites;

   package Timing_Caller is new AUnit.Test_Caller (Hlr_3_Timing_Tests.Test);
   package Timeline_Caller is new AUnit.Test_Caller (Timeline_Tests.Test);
   package Demand_Caller is new AUnit.Test_Caller (Demand_Tests.Test);

   Result : aliased Test_Suite;

   Yellow           : aliased Timing_Caller.Test_Case;
   Red_Clearance    : aliased Timing_Caller.Test_Case;
   Power_On_Barrier : aliased Timing_Caller.Test_Case;
   Axis_Barriers    : aliased Timing_Caller.Test_Case;
   Full_Cycle_Fits  : aliased Timeline_Caller.Test_Case;
   Demand_Windows   : aliased Demand_Caller.Test_Case;

   function Suite return Access_Test_Suite is
   begin
      Timing_Caller.Create
        (Yellow,
         "hlr_3_timing: every yellow holds for T_YELLOW",
         Hlr_3_Timing_Tests.Test_Yellow_Holds_For_T_Yellow'Access);

      Timing_Caller.Create
        (Red_Clearance,
         "hlr_3_timing: every red clearance holds for T_REDCLEAR",
         Hlr_3_Timing_Tests.Test_Red_Clearance_Holds_For_T_Redclear'Access);

      Timing_Caller.Create
        (Power_On_Barrier,
         "hlr_3_timing: the power-on barrier holds for T_BARRIER",
         Hlr_3_Timing_Tests.Test_Power_On_Barrier_Holds_For_T_Barrier'Access);

      Timing_Caller.Create
        (Axis_Barriers,
         "hlr_3_timing: every axis-change barrier holds for T_BARRIER",
         Hlr_3_Timing_Tests.Test_Axis_Change_Barriers_Hold_For_T_Barrier'
           Access);

      Timeline_Caller.Create
        (Full_Cycle_Fits,
         "timeline: a full cycle under full demand fits",
         Timeline_Tests.Test_Full_Cycle_Fits_The_Timeline'Access);

      Demand_Caller.Create
        (Demand_Windows,
         "demand: a window bounds the reads that see it",
         Demand_Tests.Test_Windows_Bound_The_Scripted_Reads'Access);

      Add_Test (Result'Access, Yellow'Access);
      Add_Test (Result'Access, Red_Clearance'Access);
      Add_Test (Result'Access, Power_On_Barrier'Access);
      Add_Test (Result'Access, Axis_Barriers'Access);
      Add_Test (Result'Access, Full_Cycle_Fits'Access);
      Add_Test (Result'Access, Demand_Windows'Access);

      return Result'Access;
   end Suite;

end System_Suite;
