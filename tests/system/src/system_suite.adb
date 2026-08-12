--  The suite's test-case objects are body state because AUnit.Test_Caller
--  registers them by reference: they have to outlive the call to Suite.

with AUnit.Test_Caller;

with Hlr_3_Timing_Tests;

package body System_Suite is

   use AUnit.Test_Suites;

   package Timing_Caller is new AUnit.Test_Caller (Hlr_3_Timing_Tests.Test);

   Result : aliased Test_Suite;

   Power_On_Barrier : aliased Timing_Caller.Test_Case;

   function Suite return Access_Test_Suite is
   begin
      Timing_Caller.Create
        (Power_On_Barrier,
         "hlr_3_timing: the power-on barrier holds for T_BARRIER",
         Hlr_3_Timing_Tests.Test_Power_On_Barrier_Holds_For_T_Barrier'Access);

      Add_Test (Result'Access, Power_On_Barrier'Access);

      return Result'Access;
   end Suite;

end System_Suite;
