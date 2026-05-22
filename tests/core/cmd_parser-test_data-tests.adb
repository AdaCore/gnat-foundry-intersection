--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Cmd_Parser.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

with Pedestrian;
with Timing;

--  @req FR-UI-02, FR-UI-05, FR-PH-02

--  begin read only
--  end read only
package body Cmd_Parser.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Dispatch (Gnattest_T : in out Test);
   procedure Test_Dispatch_08bd7d (Gnattest_T : in out Test) renames Test_Dispatch;
--  id:2.2/08bd7d22c406a91b/Dispatch/1/0/
   procedure Test_Dispatch (Gnattest_T : in out Test) is
   --  cmd_parser.ads:29:4:Dispatch
--  end read only

      pragma Unreferenced (Gnattest_T);

      use type Phase_Sequencer.Phase_Id;
   begin
      --  FR-UI-05: PRESS PED NE latches a request on EW_East per
      --  wire-protocol § 2.1's NE -> EW_East mapping.
      declare
         S       : Phase_Sequencer.State;
         Applied : Boolean;
      begin
         Dispatch (S, "PRESS PED NE", Applied);
         Assert (Applied, "PRESS PED NE dispatches");
         Assert (S.Peds (Pedestrian.EW_East).Request_Latched,
                 "PRESS PED NE latches EW_East");
      end;

      --  Malformed and unknown command lines are silently discarded.
      declare
         S       : Phase_Sequencer.State;
         Applied : Boolean;
      begin
         Dispatch (S, "FOO BAR BAZ", Applied);
         Assert (not Applied, "FOO BAR BAZ does not dispatch");
         Dispatch (S, "press ped ne", Applied);
         Assert (not Applied,
                 "case-sensitive: lowercase 'press ped ne' is rejected");
         Dispatch (S, "RESET extra", Applied);
         Assert (not Applied, "RESET with trailing tokens is rejected");
         Dispatch (S, "SET LT NS 2", Applied);
         Assert (not Applied, "SET LT with non-bit value is rejected");
      end;

      --  FR-PH-02: SET LT NS 0 drives Set_Left_Demand which causes the
      --  Startup -> NS_Through_Green skip on the next cycle.
      declare
         S       : Phase_Sequencer.State;
         Applied : Boolean;
      begin
         Dispatch (S, "SET LT NS 0", Applied);
         Assert (Applied, "SET LT NS 0 dispatches");
         Assert (not S.Left_Demand (Phase_Sequencer.NS),
                 "SET LT NS 0 clears Left_Demand(NS)");
         for I in 1 .. Timing.T_Startup + 1 loop
            Phase_Sequencer.Tick (S);
         end loop;
         Assert (S.Current = Phase_Sequencer.NS_Through_Green,
                 "cmd-driven SET LT NS 0 causes Startup to skip NS-left");
      end;

      --  FR-UI-02: RESET clears the fault latch and returns to Startup.
      declare
         S       : Phase_Sequencer.State;
         Applied : Boolean;
      begin
         Phase_Sequencer.Set_Fault (S, True);
         Phase_Sequencer.Tick (S);
         Dispatch (S, "RESET", Applied);
         Assert (Applied, "RESET dispatches");
         Assert (S.Current = Phase_Sequencer.Startup,
                 "RESET returns Current to Startup");
         Assert (not S.Fault_Latched,
                 "RESET clears the fault latch");
      end;

--  begin read only
   end Test_Dispatch;
--  end read only

--  begin read only
--  id:2.2/02/
--
--  This section can be used to add elaboration code for the global state.
--
begin
--  end read only
   null;
--  begin read only
--  end read only
end Cmd_Parser.Test_Data.Tests;
