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

   Walk             : aliased Timing_Caller.Test_Case;
   Flash_Dont_Walk  : aliased Timing_Caller.Test_Case;
   Yellow           : aliased Timing_Caller.Test_Case;
   Red_Clearance    : aliased Timing_Caller.Test_Case;
   Power_On_Barrier : aliased Timing_Caller.Test_Case;
   Axis_Barriers    : aliased Timing_Caller.Test_Case;
   Axis_Slot        : aliased Timing_Caller.Test_Case;
   Crosswalk_Margin : aliased Timing_Caller.Test_Case;
   Acknowledgment   : aliased Timing_Caller.Test_Case;
   Full_Cycle_Fits  : aliased Timeline_Caller.Test_Case;
   Demand_Windows   : aliased Demand_Caller.Test_Case;

   function Suite return Access_Test_Suite is
   begin
      Timing_Caller.Create
        (Walk,
         "hlr_3_timing: WALK holds for T_WALK",
         Hlr_3_Timing_Tests.Test_Walk_Holds_For_T_Walk'Access);

      Timing_Caller.Create
        (Flash_Dont_Walk,
         "hlr_3_timing: FLASHING DONT WALK holds for T_FDW",
         Hlr_3_Timing_Tests.Test_Flash_Dont_Walk_Holds_For_T_FDW'Access);

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
         Hlr_3_Timing_Tests
           .Test_Axis_Change_Barriers_Hold_For_T_Barrier'Access);

      Timing_Caller.Create
        (Axis_Slot,
         "hlr_3_timing: the axis slot is T_AXIS whatever the demand",
         Hlr_3_Timing_Tests.Test_Axis_Slot_Is_Demand_Independent'Access);

      Timing_Caller.Create
        (Crosswalk_Margin,
         "hlr_3_timing: crosswalk conflicts stay RED for the margin",
         Hlr_3_Timing_Tests
           .Test_Crosswalk_Conflicts_Held_Red_For_The_Margin'Access);

      Timing_Caller.Create
        (Acknowledgment,
         "hlr_3_timing: a press is acknowledged within T_ACK",
         Hlr_3_Timing_Tests.Test_Request_Acknowledged_Within_T_Ack'Access);

      Timeline_Caller.Create
        (Full_Cycle_Fits,
         "timeline: a full cycle under full demand fits",
         Timeline_Tests.Test_Full_Cycle_Fits_The_Timeline'Access);

      Demand_Caller.Create
        (Demand_Windows,
         "demand: a window bounds the reads that see it",
         Demand_Tests.Test_Windows_Bound_The_Scripted_Reads'Access);

      Add_Test (Result'Access, Walk'Access);
      Add_Test (Result'Access, Flash_Dont_Walk'Access);
      Add_Test (Result'Access, Yellow'Access);
      Add_Test (Result'Access, Red_Clearance'Access);
      Add_Test (Result'Access, Power_On_Barrier'Access);
      Add_Test (Result'Access, Axis_Barriers'Access);
      Add_Test (Result'Access, Axis_Slot'Access);
      Add_Test (Result'Access, Crosswalk_Margin'Access);
      Add_Test (Result'Access, Acknowledgment'Access);
      Add_Test (Result'Access, Full_Cycle_Fits'Access);
      Add_Test (Result'Access, Demand_Windows'Access);

      return Result'Access;
   end Suite;

end System_Suite;
