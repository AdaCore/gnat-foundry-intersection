--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Pedestrian.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

--  @req FR-PD-02, FR-PD-05, FR-PD-06, FR-PD-07

--  begin read only
--  end read only
package body Pedestrian.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Press (Gnattest_T : in out Test);
   procedure Test_Press_20b92d (Gnattest_T : in out Test) renames Test_Press;
--  id:2.2/20b92d2989db40ae/Press/1/0/
   procedure Test_Press (Gnattest_T : in out Test) is
   --  pedestrian.ads:25:4:Press
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  Press latches a request. FR-PD-07: a Press during an active
      --  ped phase is ignored (no observable mutation).
      C : Crosswalk_State;
   begin
      Press (C);
      Assert (C.Request_Latched, "Press latches the request");

      Start_Phase (C);            -- enters Walk, clears the latch
      Press (C);                  -- should be ignored
      Assert (not C.Request_Latched,
              "Press during Walk is ignored (FR-PD-07)");

--  begin read only
   end Test_Press;
--  end read only


--  begin read only
   procedure Test_Start_Phase (Gnattest_T : in out Test);
   procedure Test_Start_Phase_622760 (Gnattest_T : in out Test) renames Test_Start_Phase;
--  id:2.2/622760f2d784b0ee/Start_Phase/1/0/
   procedure Test_Start_Phase (Gnattest_T : in out Test) is
   --  pedestrian.ads:30:4:Start_Phase
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-PD-02: Start_Phase with a latched request enters Walk and
      --  clears the latch. Without a latched request the phase enters
      --  Dont_Walk directly.
      C1, C2 : Crosswalk_State;
   begin
      Press (C1);
      Start_Phase (C1);
      Assert (C1.Indication = Walk,
              "Start_Phase with latched request enters Walk");
      Assert (not C1.Request_Latched,
              "Start_Phase clears the latched request (FR-PD-02)");

      Start_Phase (C2);
      Assert (C2.Indication = Dont_Walk,
              "Start_Phase without a request enters Dont_Walk");

--  begin read only
   end Test_Start_Phase;
--  end read only


--  begin read only
   procedure Test_End_Phase (Gnattest_T : in out Test);
   procedure Test_End_Phase_bb914c (Gnattest_T : in out Test) renames Test_End_Phase;
--  id:2.2/bb914c191df09fed/End_Phase/1/0/
   procedure Test_End_Phase (Gnattest_T : in out Test) is
   --  pedestrian.ads:33:4:End_Phase
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  End_Phase returns the crosswalk to Idle.
      C : Crosswalk_State;
   begin
      Press (C);
      Start_Phase (C);
      End_Phase (C);
      Assert (C.Indication = Idle, "End_Phase returns to Idle");

--  begin read only
   end Test_End_Phase;
--  end read only


--  begin read only
   procedure Test_Tick (Gnattest_T : in out Test);
   procedure Test_Tick_9db004 (Gnattest_T : in out Test) renames Test_Tick;
--  id:2.2/9db004ffd005a188/Tick/1/0/
   procedure Test_Tick (Gnattest_T : in out Test) is
   --  pedestrian.ads:37:4:Tick
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-PD-05: Walk -> Flashing_Dont_Walk after T_Walk;
      --  Flashing_Dont_Walk -> Dont_Walk after T_FDW.
      C : Crosswalk_State;
   begin
      Press (C);
      Start_Phase (C);

      for I in 1 .. Timing.T_Walk loop
         Tick (C);
      end loop;
      Assert (C.Indication = Flashing_Dont_Walk,
              "Walk -> Flashing_Dont_Walk after T_Walk");

      for I in 1 .. Timing.T_FDW loop
         Tick (C);
      end loop;
      Assert (C.Indication = Dont_Walk,
              "Flashing_Dont_Walk -> Dont_Walk after T_FDW");

--  begin read only
   end Test_Tick;
--  end read only


--  begin read only
   procedure Test_Is_Serving (Gnattest_T : in out Test);
   procedure Test_Is_Serving_184144 (Gnattest_T : in out Test) renames Test_Is_Serving;
--  id:2.2/1841443235b5a022/Is_Serving/1/0/
   procedure Test_Is_Serving (Gnattest_T : in out Test) is
   --  pedestrian.ads:42:4:Is_Serving
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  Is_Serving is True iff the indication is Walk or
      --  Flashing_Dont_Walk (the phases that extend through-green per
      --  FR-PD-06). Idle and Dont_Walk are not "serving".
      C : Crosswalk_State;
   begin
      Assert (not Is_Serving (C), "Idle is not serving");

      Press (C);
      Start_Phase (C);
      Assert (Is_Serving (C), "Walk is serving");

      for I in 1 .. Timing.T_Walk loop
         Tick (C);
      end loop;
      Assert (Is_Serving (C), "Flashing_Dont_Walk is serving");

      for I in 1 .. Timing.T_FDW loop
         Tick (C);
      end loop;
      Assert (not Is_Serving (C), "Dont_Walk is not serving");

--  begin read only
   end Test_Is_Serving;
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
end Pedestrian.Test_Data.Tests;
