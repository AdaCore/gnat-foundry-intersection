with HAL;

package body Diagnostic is

   function Phase_Name (P : Phase_Sequencer.Phase_Id) return String is
     (case P is
        when Phase_Sequencer.Startup            => "STARTUP_FLASH",
        when Phase_Sequencer.NS_Left_Green      => "NS_LT_GREEN",
        when Phase_Sequencer.NS_Left_Yellow     => "NS_LT_YELLOW",
        when Phase_Sequencer.All_Red_1          => "ALL_RED_1",
        when Phase_Sequencer.NS_Through_Green   => "NS_THROUGH_GREEN",
        when Phase_Sequencer.NS_Through_Yellow  => "NS_THROUGH_YELLOW",
        when Phase_Sequencer.All_Red_2          => "ALL_RED_2",
        when Phase_Sequencer.EW_Left_Green      => "EW_LT_GREEN",
        when Phase_Sequencer.EW_Left_Yellow     => "EW_LT_YELLOW",
        when Phase_Sequencer.All_Red_3          => "ALL_RED_3",
        when Phase_Sequencer.EW_Through_Green   => "EW_THROUGH_GREEN",
        when Phase_Sequencer.EW_Through_Yellow  => "EW_THROUGH_YELLOW",
        when Phase_Sequencer.All_Red_4          => "ALL_RED_4",
        when Phase_Sequencer.Fault              => "FAULT");

   function Image (N : Natural) return String is
      S : constant String := Natural'Image (N);
   begin
      return S (S'First + 1 .. S'Last);
   end Image;

   procedure Emit_Transition (S : Phase_Sequencer.State) is
   begin
      --  PED / LT / FAULT fields are placeholders until the corresponding
      --  state plumbing lands. T_in_phase is real.
      HAL.Diag_Write_Line
        ("PH="    & Phase_Name (S.Current)
         & " T="   & Image (Natural (S.Time_In_Phase))
         & " PED=NS:clr,EW:clr"
         & " LT=NS:0,EW:0"
         & " FAULT=0");
   end Emit_Transition;

   procedure Emit_Heartbeat (Now_Ms : Natural) is
   begin
      HAL.Diag_Write_Line ("HB T=" & Image (Now_Ms));
   end Emit_Heartbeat;

end Diagnostic;
