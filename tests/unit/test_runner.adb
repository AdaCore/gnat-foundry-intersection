--  Minimal test runner. Replace with AUnit or gnattest harness once those
--  are wired into the Alire crate.
--
--  @req FR-PH-03, FR-PH-04, FR-PD-02, FR-PD-05, FR-PD-06, FR-PD-07

with Ada.Text_IO;
with Phase_Sequencer;
with Pedestrian;
with Conflict_Check;
with Timing;

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

begin
   Test_Sequencer_Initial_State;
   Test_Sequencer_Advances_Past_Startup;
   Test_Conflict_Matrix_Reflexivity;
   Test_Ped_Walk_FDW_DontWalk_Progression;
   Test_Ped_Press_During_Active_Has_No_Effect;
   Test_Through_Green_Extends_For_Ped;
   Test_Through_Green_Does_Not_Extend_Without_Ped;

   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED");
   else
      Put_Line (Failures'Image & " FAILURES");
   end if;
end Test_Runner;
