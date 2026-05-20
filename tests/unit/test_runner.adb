--  Minimal test runner. Replace with AUnit or gnattest harness once those
--  are wired into the Alire crate.
--
--  @req FR-PH-02, FR-PH-03, FR-PH-04, FR-PD-01, FR-PD-02, FR-PD-05,
--       FR-PD-06, FR-PD-07, FR-SF-05, FR-SF-07, FR-UI-02, FR-UI-05

with Ada.Text_IO;
with Phase_Sequencer;
with Pedestrian;
with Conflict_Check;
with Timing;
with Cmd_Parser;

procedure Test_Runner is

   use Ada.Text_IO;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; Name : String) is
   begin
      if Condition then
         Put_Line ("PASS " & Name);
      else
         Put_Line ("FAIL " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Placeholder tests — these will become real tests as the
   --  implementation lands.

   procedure Test_Sequencer_Initial_State is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      Check (S.Current = Phase_Sequencer.Startup,
             "sequencer starts in Startup");
   end Test_Sequencer_Initial_State;

   procedure Test_Sequencer_Advances_Past_Startup is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      for I in 1 .. Timing.T_Startup + 1 loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.NS_Left_Green,
             "Startup advances to NS_Left_Green after T_Startup");
      Check (Phase_Sequencer.Invariant_Holds (S),
             "post-Startup state satisfies invariant");
   end Test_Sequencer_Advances_Past_Startup;

   procedure Test_Conflict_Matrix_Reflexivity is
      use Conflict_Check;
   begin
      for M in Movement loop
         Check (not Conflicts (M, M),
                "movement does not conflict with itself: "
                & Movement'Image (M));
      end loop;
   end Test_Conflict_Matrix_Reflexivity;

   --  FR-PD-05: Walk -> Flashing_Dont_Walk after T_Walk;
   --  Flashing_Dont_Walk -> Dont_Walk after T_FDW.
   --  FR-PD-02: Start_Phase consumes the latched request.
   procedure Test_Ped_Walk_FDW_DontWalk_Progression is
      use type Pedestrian.Indication;
      C : Pedestrian.Crosswalk_State;
   begin
      Pedestrian.Press (C);
      Check (C.Request_Latched, "Press latches the request");

      Pedestrian.Start_Phase (C);
      Check (C.Indication = Pedestrian.Walk,
             "Start_Phase with latched request enters Walk");
      Check (not C.Request_Latched,
             "Start_Phase clears the latched request (FR-PD-02)");

      for I in 1 .. Timing.T_Walk loop
         Pedestrian.Tick (C);
      end loop;
      Check (C.Indication = Pedestrian.Flashing_Dont_Walk,
             "Walk -> Flashing_Dont_Walk after T_Walk");

      for I in 1 .. Timing.T_FDW loop
         Pedestrian.Tick (C);
      end loop;
      Check (C.Indication = Pedestrian.Dont_Walk,
             "Flashing_Dont_Walk -> Dont_Walk after T_FDW");

      Pedestrian.End_Phase (C);
      Check (C.Indication = Pedestrian.Idle,
             "End_Phase returns to Idle");
   end Test_Ped_Walk_FDW_DontWalk_Progression;

   --  FR-PD-07: Press during an active ped phase has no effect.
   procedure Test_Ped_Press_During_Active_Has_No_Effect is
      C : Pedestrian.Crosswalk_State;
   begin
      Pedestrian.Press (C);
      Pedestrian.Start_Phase (C);   -- enters Walk, clears latch
      Pedestrian.Press (C);          -- should be ignored
      Check (not C.Request_Latched,
             "Press during Walk is ignored (FR-PD-07)");
   end Test_Ped_Press_During_Active_Has_No_Effect;

   --  FR-PD-06: NS_Through_Green must not terminate before
   --  T_Walk + T_FDW when a Ped-NS request is being served.
   procedure Test_Through_Green_Extends_For_Ped is
      use type Phase_Sequencer.Phase_Id;
      use type Pedestrian.Indication;
      S : Phase_Sequencer.State;
   begin
      --  Latch a Ped-NS request and tick into NS_Through_Green.
      Phase_Sequencer.Press_Ped (S, Pedestrian.NS_North);
      while S.Current /= Phase_Sequencer.NS_Through_Green loop
         Phase_Sequencer.Tick (S);
      end loop;

      --  At T_Min_G the green would normally end; with ped active it must hold.
      for I in 1 .. Timing.T_Min_G + 1 loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.NS_Through_Green,
             "NS_Through_Green holds past T_Min_G while Ped-NS is serving");

      --  Tick out to T_Walk + T_FDW; green should release at/just past that.
      while S.Current = Phase_Sequencer.NS_Through_Green loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.NS_Through_Yellow,
             "NS_Through_Green releases to yellow after T_Walk + T_FDW");
      Check (S.Peds (Pedestrian.NS_North).Indication = Pedestrian.Idle,
             "Ped-NS returns to Idle when through-yellow begins");
   end Test_Through_Green_Extends_For_Ped;

   --  Without a request, NS_Through_Green should not extend past T_Min_G.
   procedure Test_Through_Green_Does_Not_Extend_Without_Ped is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      while S.Current /= Phase_Sequencer.NS_Through_Green loop
         Phase_Sequencer.Tick (S);
      end loop;

      for I in 1 .. Timing.T_Min_G + 1 loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current /= Phase_Sequencer.NS_Through_Green,
             "NS_Through_Green ends at T_Min_G when no ped is serving");
   end Test_Through_Green_Does_Not_Extend_Without_Ped;

   --  FR-PH-02: when Left_Demand(EW)=False, All_Red_2 must transition to
   --  EW_Through_Green directly, skipping EW_Left_Green/Yellow.
   procedure Test_Skip_EW_Left_When_No_Demand is
      use type Phase_Sequencer.Phase_Id;
      S          : Phase_Sequencer.State;
      Saw_LG, Saw_LY : Boolean := False;
   begin
      Phase_Sequencer.Set_Left_Demand (S, Phase_Sequencer.EW, False);
      while S.Current /= Phase_Sequencer.EW_Through_Green loop
         if S.Current = Phase_Sequencer.EW_Left_Green  then Saw_LG := True; end if;
         if S.Current = Phase_Sequencer.EW_Left_Yellow then Saw_LY := True; end if;
         Phase_Sequencer.Tick (S);
      end loop;
      Check (not Saw_LG, "EW_Left_Green is skipped when Left_Demand(EW)=False");
      Check (not Saw_LY, "EW_Left_Yellow is skipped when Left_Demand(EW)=False");
      Check (Phase_Sequencer.Invariant_Holds (S),
             "skip-on-no-demand preserves the safety invariant");
   end Test_Skip_EW_Left_When_No_Demand;

   --  FR-PH-02: skip from Startup → NS_Through_Green when no NS demand.
   procedure Test_Skip_NS_Left_From_Startup_When_No_Demand is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      Phase_Sequencer.Set_Left_Demand (S, Phase_Sequencer.NS, False);
      for I in 1 .. Timing.T_Startup + 1 loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.NS_Through_Green,
             "Startup → NS_Through_Green when Left_Demand(NS)=False");
   end Test_Skip_NS_Left_From_Startup_When_No_Demand;

   --  FR-SF-07 + FR-SF-05: asserting fault forces entry to Fault; clearing
   --  the input does not auto-recover.
   procedure Test_Fault_Force_Entry_And_No_Auto_Recovery is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
   begin
      --  Tick once so we're past Startup-init; then assert fault.
      Phase_Sequencer.Tick (S);
      Phase_Sequencer.Set_Fault (S, True);
      Phase_Sequencer.Tick (S);
      Check (S.Current = Phase_Sequencer.Fault,
             "Fault input forces entry to Fault on next Tick");

      --  Clearing the input must NOT exit Fault (FR-SF-05).
      Phase_Sequencer.Set_Fault (S, False);
      for I in 1 .. Timing.T_LT_G loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.Fault,
             "Fault is sticky after the input is cleared (FR-SF-05)");
   end Test_Fault_Force_Entry_And_No_Auto_Recovery;

   --  FR-UI-02: RESET restores Startup state and clears Fault.
   procedure Test_Reset_From_Fault is
      use type Phase_Sequencer.Phase_Id;
      S : Phase_Sequencer.State;
      Applied : Boolean;
   begin
      Phase_Sequencer.Set_Fault (S, True);
      Phase_Sequencer.Tick (S);
      Cmd_Parser.Dispatch (S, "RESET", Applied);
      Check (Applied, "RESET dispatches");
      Check (S.Current = Phase_Sequencer.Startup,
             "RESET returns Current to Startup");
      Check (not S.Fault_Latched,
             "RESET clears the fault latch");
   end Test_Reset_From_Fault;

   --  FR-UI-05: cmd-in PRESS PED latches a request on the mapped crosswalk.
   --  Per the wire-protocol § 2.1 convention, NE maps to EW_East.
   procedure Test_Cmd_Press_Ped_NE_Latches is
      S       : Phase_Sequencer.State;
      Applied : Boolean;
   begin
      Cmd_Parser.Dispatch (S, "PRESS PED NE", Applied);
      Check (Applied, "PRESS PED NE dispatches");
      Check (S.Peds (Pedestrian.EW_East).Request_Latched,
             "PRESS PED NE latches EW_East");
   end Test_Cmd_Press_Ped_NE_Latches;

   --  Malformed and unknown commands are silently discarded (Applied=False,
   --  no state mutation observed).
   procedure Test_Cmd_Unknown_Discarded is
      S       : Phase_Sequencer.State;
      Applied : Boolean;
   begin
      Cmd_Parser.Dispatch (S, "FOO BAR BAZ", Applied);
      Check (not Applied, "FOO BAR BAZ does not dispatch");
      Cmd_Parser.Dispatch (S, "press ped ne", Applied);
      Check (not Applied, "case-sensitive: lowercase 'press ped ne' is rejected");
      Cmd_Parser.Dispatch (S, "RESET extra", Applied);
      Check (not Applied, "RESET with trailing tokens is rejected");
      Cmd_Parser.Dispatch (S, "SET LT NS 2", Applied);
      Check (not Applied, "SET LT with non-bit value is rejected");
   end Test_Cmd_Unknown_Discarded;

   --  Cmd_Parser drives Set_Left_Demand which then drives skip-on-no-demand.
   --  End-to-end check that the parser composes correctly with the state.
   procedure Test_Cmd_Set_LT_Drives_Skip is
      use type Phase_Sequencer.Phase_Id;
      S       : Phase_Sequencer.State;
      Applied : Boolean;
   begin
      Cmd_Parser.Dispatch (S, "SET LT NS 0", Applied);
      Check (Applied, "SET LT NS 0 dispatches");
      Check (not S.Left_Demand (Phase_Sequencer.NS),
             "SET LT NS 0 clears Left_Demand(NS)");
      for I in 1 .. Timing.T_Startup + 1 loop
         Phase_Sequencer.Tick (S);
      end loop;
      Check (S.Current = Phase_Sequencer.NS_Through_Green,
             "cmd-driven SET LT NS 0 causes Startup to skip NS-left");
   end Test_Cmd_Set_LT_Drives_Skip;

begin
   Test_Sequencer_Initial_State;
   Test_Sequencer_Advances_Past_Startup;
   Test_Conflict_Matrix_Reflexivity;
   Test_Ped_Walk_FDW_DontWalk_Progression;
   Test_Ped_Press_During_Active_Has_No_Effect;
   Test_Through_Green_Extends_For_Ped;
   Test_Through_Green_Does_Not_Extend_Without_Ped;
   Test_Skip_EW_Left_When_No_Demand;
   Test_Skip_NS_Left_From_Startup_When_No_Demand;
   Test_Fault_Force_Entry_And_No_Auto_Recovery;
   Test_Reset_From_Fault;
   Test_Cmd_Press_Ped_NE_Latches;
   Test_Cmd_Unknown_Discarded;
   Test_Cmd_Set_LT_Drives_Skip;

   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " FAILURES");
   end if;
end Test_Runner;
