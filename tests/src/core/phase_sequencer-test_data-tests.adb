--  This package has been generated automatically by GNATtest.
--  You are allowed to add your code to the bodies of test routines.
--  Such changes will be kept during further regeneration of this file.
--  All code placed outside of test routine bodies will be lost. The
--  code intended to set up and tear down the test environment should be
--  placed into Phase_Sequencer.Test_Data.

with AUnit.Assertions; use AUnit.Assertions;
with System.Assertions;

--  begin read only
--  id:2.2/00/
--
--  This section can be used to add with clauses if necessary.
--
--  end read only

--  @req FR-PH-02, FR-PH-03, FR-PD-06, FR-SF-02, FR-SF-04, FR-SF-05,
--  @req FR-SF-07, FR-SF-08, FR-SF-09, FR-UI-02

--  begin read only
--  end read only
package body Phase_Sequencer.Test_Data.Tests is

--  begin read only
--  id:2.2/01/
--
--  This section can be used to add global variables and other elements.
--
--  end read only

--  begin read only
--  end read only

--  begin read only
   procedure Test_Press_Ped (Gnattest_T : in out Test);
   procedure Test_Press_Ped_f7e55c (Gnattest_T : in out Test) renames Test_Press_Ped;
--  id:2.2/f7e55cc1bdfa8583/Press_Ped/1/0/
   procedure Test_Press_Ped (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:51:4:Press_Ped
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-PD-06: NS_Through_Green holds for T_Walk + T_FDW when a
      --  Ped-NS request is being served, then releases to
      --  NS_Through_Yellow with the ped back to Idle.
      use type Pedestrian.Indication;
      S : State;
   begin
      Press_Ped (S, Pedestrian.NS_North);
      while S.Current /= NS_Through_Green loop
         Tick (S);
      end loop;

      for I in 1 .. Timing.T_Min_G + 1 loop
         Tick (S);
      end loop;
      Assert (S.Current = NS_Through_Green,
              "NS_Through_Green holds past T_Min_G while Ped-NS is serving");

      while S.Current = NS_Through_Green loop
         Tick (S);
      end loop;
      Assert (S.Current = NS_Through_Yellow,
              "NS_Through_Green releases to yellow after T_Walk + T_FDW");
      Assert (S.Peds (Pedestrian.NS_North).Indication = Pedestrian.Idle,
              "Ped-NS returns to Idle when through-yellow begins");

--  begin read only
   end Test_Press_Ped;
--  end read only


--  begin read only
   procedure Test_Set_Left_Demand (Gnattest_T : in out Test);
   procedure Test_Set_Left_Demand_3a0ae3 (Gnattest_T : in out Test) renames Test_Set_Left_Demand;
--  id:2.2/3a0ae308cafa95fc/Set_Left_Demand/1/0/
   procedure Test_Set_Left_Demand (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:56:4:Set_Left_Demand
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-PH-02: when Left_Demand(EW)=False, the cycle skips
      --  EW_Left_Green/Yellow and goes directly to EW_Through_Green;
      --  and from Startup, Left_Demand(NS)=False skips NS_Left_*.
      S      : State;
      Saw_LG : Boolean := False;
      Saw_LY : Boolean := False;
   begin
      Set_Left_Demand (S, EW, False);
      while S.Current /= EW_Through_Green loop
         if S.Current = EW_Left_Green  then Saw_LG := True; end if;
         if S.Current = EW_Left_Yellow then Saw_LY := True; end if;
         Tick (S);
      end loop;
      Assert (not Saw_LG,
              "EW_Left_Green is skipped when Left_Demand(EW)=False");
      Assert (not Saw_LY,
              "EW_Left_Yellow is skipped when Left_Demand(EW)=False");
      Assert (Invariant_Holds (S),
              "skip-on-no-demand preserves the safety invariant");

      declare
         S2 : State;
      begin
         Set_Left_Demand (S2, NS, False);
         for I in 1 .. Timing.T_Startup + 1 loop
            Tick (S2);
         end loop;
         Assert (S2.Current = NS_Through_Green,
                 "Startup -> NS_Through_Green when Left_Demand(NS)=False");
      end;

--  begin read only
   end Test_Set_Left_Demand;
--  end read only


--  begin read only
   procedure Test_Set_Fault (Gnattest_T : in out Test);
   procedure Test_Set_Fault_4ff9be (Gnattest_T : in out Test) renames Test_Set_Fault;
--  id:2.2/4ff9bed62f797aee/Set_Fault/1/0/
   procedure Test_Set_Fault (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:62:4:Set_Fault
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-SF-07: asserting Fault forces Fault on the next Tick.
      --  FR-SF-05: clearing the input does not auto-recover.
      S : State;
   begin
      Tick (S);
      Set_Fault (S, True);
      Tick (S);
      Assert (S.Current = Fault,
              "Fault input forces entry to Fault on next Tick");

      Set_Fault (S, False);
      for I in 1 .. Timing.T_LT_G loop
         Tick (S);
      end loop;
      Assert (S.Current = Fault,
              "Fault is sticky after the input is cleared (FR-SF-05)");

--  begin read only
   end Test_Set_Fault;
--  end read only


--  begin read only
   procedure Test_Reset_Controller (Gnattest_T : in out Test);
   procedure Test_Reset_Controller_6b8f4b (Gnattest_T : in out Test) renames Test_Reset_Controller;
--  id:2.2/6b8f4b2871edaf07/Reset_Controller/1/0/
   procedure Test_Reset_Controller (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:67:4:Reset_Controller
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  FR-UI-02: Reset_Controller restores Startup state and clears
      --  the fault latch even after the controller has entered Fault.
      S : State;
   begin
      Set_Fault (S, True);
      Tick (S);
      Reset_Controller (S);
      Assert (S.Current = Startup,
              "Reset_Controller returns Current to Startup");
      Assert (not S.Fault_Latched,
              "Reset_Controller clears the fault latch");

--  begin read only
   end Test_Reset_Controller;
--  end read only


--  begin read only
   procedure Test_Tick (Gnattest_T : in out Test);
   procedure Test_Tick_88969f (Gnattest_T : in out Test) renames Test_Tick;
--  id:2.2/88969f896222755c/Tick/1/0/
   procedure Test_Tick (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:71:4:Tick
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  Initial Current is Startup; advances to NS_Left_Green after
      --  T_Startup ticks; the resulting state satisfies the invariant.
      --  Without a ped request, NS_Through_Green ends at T_Min_G.
      S : State;
   begin
      Assert (S.Current = Startup, "sequencer starts in Startup");

      for I in 1 .. Timing.T_Startup + 1 loop
         Tick (S);
      end loop;
      Assert (S.Current = NS_Left_Green,
              "Startup advances to NS_Left_Green after T_Startup");
      Assert (Invariant_Holds (S),
              "post-Startup state satisfies invariant");

      declare
         S2 : State;
      begin
         while S2.Current /= NS_Through_Green loop
            Tick (S2);
         end loop;
         for I in 1 .. Timing.T_Min_G + 1 loop
            Tick (S2);
         end loop;
         Assert (S2.Current /= NS_Through_Green,
                 "NS_Through_Green ends at T_Min_G when no ped is serving");
      end;

--  begin read only
   end Test_Tick;
--  end read only


--  begin read only
   procedure Test_Invariant_Holds (Gnattest_T : in out Test);
   procedure Test_Invariant_Holds_a21b50 (Gnattest_T : in out Test) renames Test_Invariant_Holds;
--  id:2.2/a21b50bb7db1b650/Invariant_Holds/1/0/
   procedure Test_Invariant_Holds (Gnattest_T : in out Test) is
   --  phase_sequencer.ads:76:4:Invariant_Holds
--  end read only

      pragma Unreferenced (Gnattest_T);

      --  Conflict-matrix reflexivity (FR-SF-02): a movement does not
      --  conflict with itself. conflict_check.ads is Pure so gnattest
      --  produced no skeleton for it; this is the closest semantic
      --  match because Phase_Sequencer.Invariant_Holds depends on
      --  Conflict_Check.Conflicts being well-formed. Also asserts the
      --  invariant holds on a fresh State.
      S : State;
   begin
      for M in Conflict_Check.Movement loop
         Assert (not Conflict_Check.Conflicts (M, M),
                 "movement does not conflict with itself: "
                 & Conflict_Check.Movement'Image (M));
      end loop;
      Assert (Invariant_Holds (S),
              "initial state satisfies the safety invariant");

--  begin read only
   end Test_Invariant_Holds;
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
end Phase_Sequencer.Test_Data.Tests;
