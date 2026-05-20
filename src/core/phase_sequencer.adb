--  Phase sequencer body — drives the controller through the 13-state cycle
--  defined in docs/architecture/state-machine.md.
--
--  @req FR-PH-01, FR-PH-02, FR-PH-03, FR-PH-04, FR-PH-05, FR-PH-06

package body Phase_Sequencer is

   --  v0.1 hard-wires left-turn demand to always-present per
   --  state-machine.md § Guards. When demand becomes a real input,
   --  Next_Phase below is where the skip-on-no-demand branch lands.
   Left_Demand_Always_On : constant Boolean := True;
   pragma Unreferenced (Left_Demand_Always_On);

   --  Static next-phase table for the nominal cycle (v0.1: no skips).
   --  @req FR-PH-01, FR-PH-05
   function Next_Phase (P : Phase_Id) return Phase_Id is
   begin
      case P is
         when Startup           => return NS_Left_Green;
         when NS_Left_Green     => return NS_Left_Yellow;
         when NS_Left_Yellow    => return All_Red_1;
         when All_Red_1         => return NS_Through_Green;
         when NS_Through_Green  => return NS_Through_Yellow;
         when NS_Through_Yellow => return All_Red_2;
         when All_Red_2         => return EW_Left_Green;
         when EW_Left_Green     => return EW_Left_Yellow;
         when EW_Left_Yellow    => return All_Red_3;
         when All_Red_3         => return EW_Through_Green;
         when EW_Through_Green  => return EW_Through_Yellow;
         when EW_Through_Yellow => return All_Red_4;
         when All_Red_4         => return NS_Left_Green;
         when Fault             => return Fault;
      end case;
   end Next_Phase;

   --  Which movements show green/yellow during phase P.
   --  Startup and all-red phases yield the empty set (flashing red /
   --  clearance). Yellow phases keep the same movement asserted as the
   --  preceding green per FR-PH-04.
   function Movements_For (P : Phase_Id) return Conflict_Check.Movement_Set is
      use Conflict_Check;
      M : Movement_Set := (others => False);
   begin
      case P is
         when Startup | All_Red_1 | All_Red_2 | All_Red_3 | All_Red_4
            | Fault =>
            null;
         when NS_Left_Green | NS_Left_Yellow =>
            M (NS_Left) := True;
         when NS_Through_Green | NS_Through_Yellow =>
            M (NS_Through) := True;
         when EW_Left_Green | EW_Left_Yellow =>
            M (EW_Left) := True;
         when EW_Through_Green | EW_Through_Yellow =>
            M (EW_Through) := True;
      end case;
      return M;
   end Movements_For;

   --  Duration after which the current phase's exit guard fires.
   --  For through-green, v0.1 has no concurrent ped phase plumbed in
   --  yet, so green_done from state-machine.md collapses to T_Min_G
   --  (FR-PH-03). When pedestrian state lands, this returns the
   --  max of T_Min_G and (T_Walk + T_FDW) when a ped phase is served.
   function Phase_Duration (P : Phase_Id) return Timing.Milliseconds is
   begin
      case P is
         when Startup =>
            return Timing.T_Startup;
         when NS_Left_Green | EW_Left_Green =>
            return Timing.T_LT_G;
         when NS_Left_Yellow | NS_Through_Yellow
            | EW_Left_Yellow | EW_Through_Yellow =>
            return Timing.T_Y;
         when All_Red_1 | All_Red_2 | All_Red_3 | All_Red_4 =>
            return Timing.T_AR;
         when NS_Through_Green | EW_Through_Green =>
            return Timing.T_Min_G;
         when Fault =>
            return Timing.Milliseconds'Last;
      end case;
   end Phase_Duration;

   procedure Tick (S : in out State) is
   begin
      --  Saturating add: Fault has no exit guard, so we could sit there
      --  arbitrarily long. The guard test below uses >=, so saturation
      --  does not perturb any transition decision.
      if S.Time_In_Phase < Timing.Milliseconds'Last then
         S.Time_In_Phase := S.Time_In_Phase + 1;
      end if;

      --  FR-SF-05: no auto-recovery from Fault.
      if S.Current /= Fault
        and then S.Time_In_Phase >= Phase_Duration (S.Current)
      then
         S.Current       := Next_Phase (S.Current);
         S.Time_In_Phase := 0;
         S.Active        := Movements_For (S.Current);
      end if;
   end Tick;

   --  Non-ghost mirror of Conflict_Check.Is_Safe so this function can be
   --  called from ordinary integration tests. Is_Safe itself is Ghost.
   function Invariant_Holds (S : State) return Boolean is
      use Conflict_Check;
   begin
      for M1 in Movement loop
         for M2 in Movement loop
            if S.Active (M1) and then S.Active (M2)
              and then Conflicts (M1, M2)
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Invariant_Holds;

end Phase_Sequencer;
