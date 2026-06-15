with HAL;
with Pedestrian;

package body Diagnostic is

   function Phase_Name (P : Phase_Sequencer.Phase_Id) return String
   is (case P is
         when Phase_Sequencer.Startup           => "STARTUP_FLASH",
         when Phase_Sequencer.NS_Left_Green     => "NS_LT_GREEN",
         when Phase_Sequencer.NS_Left_Yellow    => "NS_LT_YELLOW",
         when Phase_Sequencer.All_Red_1         => "ALL_RED_1",
         when Phase_Sequencer.NS_Through_Green  => "NS_THROUGH_GREEN",
         when Phase_Sequencer.NS_Through_Yellow => "NS_THROUGH_YELLOW",
         when Phase_Sequencer.All_Red_2         => "ALL_RED_2",
         when Phase_Sequencer.EW_Left_Green     => "EW_LT_GREEN",
         when Phase_Sequencer.EW_Left_Yellow    => "EW_LT_YELLOW",
         when Phase_Sequencer.All_Red_3         => "ALL_RED_3",
         when Phase_Sequencer.EW_Through_Green  => "EW_THROUGH_GREEN",
         when Phase_Sequencer.EW_Through_Yellow => "EW_THROUGH_YELLOW",
         when Phase_Sequencer.All_Red_4         => "ALL_RED_4",
         when Phase_Sequencer.Fault             => "FAULT");

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   --  Aggregate per-axis ped state for the wire field (wire-protocol § 1.4).
   --  Per-corner Crosswalk → axis mapping uses literal enum naming;
   --  Ped-row inversion (backlog #1) may flip these groupings, gated on
   --  a requirement_change issue.
   function Ped_Axis_Token
     (Peds : Pedestrian.Crosswalk_States; A, B : Pedestrian.Crosswalk)
      return String is
   begin
      if Peds (A).Request_Latched
        or else Peds (B).Request_Latched
        or else Pedestrian.Is_Serving (Peds (A))
        or else Pedestrian.Is_Serving (Peds (B))
      then
         return "req";
      else
         return "clr";
      end if;
   end Ped_Axis_Token;

   function Bit (B : Boolean) return String
   is (if B then "1" else "0");

   procedure Emit_Transition (S : Phase_Sequencer.State) is
      use type Phase_Sequencer.Phase_Id;
      NS_Tok    : constant String :=
        Ped_Axis_Token (S.Peds, Pedestrian.NS_North, Pedestrian.NS_South);
      EW_Tok    : constant String :=
        Ped_Axis_Token (S.Peds, Pedestrian.EW_East, Pedestrian.EW_West);
      Fault_Now : constant Boolean :=
        S.Fault_Latched or else S.Current = Phase_Sequencer.Fault;
   begin
      HAL.Diag_Write_Line
        ("PH="
         & Phase_Name (S.Current)
         & " T="
         & Image (Natural (S.Time_In_Phase))
         & " PED=NS:"
         & NS_Tok
         & ",EW:"
         & EW_Tok
         & " LT=NS:"
         & Bit (S.Left_Demand (Phase_Sequencer.NS))
         & ",EW:"
         & Bit (S.Left_Demand (Phase_Sequencer.EW))
         & " FAULT="
         & Bit (Fault_Now));
   end Emit_Transition;

   procedure Emit_Heartbeat (Now_Ms : Natural) is
   begin
      HAL.Diag_Write_Line ("HB T=" & Image (Now_Ms));
   end Emit_Heartbeat;

end Diagnostic;
