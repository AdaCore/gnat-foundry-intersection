--  Cmd_Parser body. Hand-rolled tokenizer over fixed forms — no heap, no
--  exceptions, SPARK-subset clean.

with Pedestrian;

package body Cmd_Parser is

   --  Per wire-protocol § 2.1, compass corners map to the Ada
   --  Pedestrian.Crosswalk enum via the same convention the visualizer's
   --  scene uses for its ped-axis grouping (see scene.rs in the
   --  visualizer crate): NE/SW walk EW, NW/SE walk NS. We commit those
   --  groupings to specific Crosswalk positions by mating compass with
   --  enum naming (NE corner → eastern EW crosswalk, etc.).
   --
   --  As with the diagnostic.adb axis-aggregation, this convention may be
   --  flipped by the conflict-matrix Ped-row inversion (backlog #1) — but
   --  the change is gated on a requirement_change issue.
   function To_Crosswalk
     (Tok : String; Ok : out Boolean) return Pedestrian.Crosswalk is
   begin
      Ok := True;
      if Tok = "NE" then
         return Pedestrian.EW_East;
      elsif Tok = "SW" then
         return Pedestrian.EW_West;
      elsif Tok = "NW" then
         return Pedestrian.NS_North;
      elsif Tok = "SE" then
         return Pedestrian.NS_South;
      else
         Ok := False;
         return Pedestrian.NS_North;  -- ignored
      end if;
   end To_Crosswalk;

   function To_Axis
     (Tok : String; Ok : out Boolean) return Phase_Sequencer.Axis is
   begin
      Ok := True;
      if Tok = "NS" then
         return Phase_Sequencer.NS;
      elsif Tok = "EW" then
         return Phase_Sequencer.EW;
      else
         Ok := False;
         return Phase_Sequencer.NS;  -- ignored
      end if;
   end To_Axis;

   function To_Bit (Tok : String; Ok : out Boolean) return Boolean is
   begin
      Ok := True;
      if Tok = "1" then
         return True;
      elsif Tok = "0" then
         return False;
      else
         Ok := False;
         return False;  -- ignored
      end if;
   end To_Bit;

   --  Find the next whitespace-delimited token starting at From within S.
   --  On return, Token_First / Token_Last delimit the token (if any) and
   --  Next is the index one past it; Found indicates whether a token was
   --  found. Tokens are separated by single ASCII spaces; we tolerate any
   --  run of spaces between tokens.
   procedure Next_Token
     (S          : String;
      From       : Positive;
      Token_First, Token_Last, Next : out Natural;
      Found      : out Boolean)
   is
      I : Natural := From;
   begin
      Token_First := 0;
      Token_Last  := 0;
      Next        := S'Last + 1;
      Found       := False;

      while I <= S'Last and then S (I) = ' ' loop
         I := I + 1;
      end loop;

      if I > S'Last then
         return;
      end if;

      Token_First := I;
      while I <= S'Last and then S (I) /= ' ' loop
         I := I + 1;
      end loop;
      Token_Last := I - 1;
      Next       := I;
      Found      := True;
   end Next_Token;

   procedure Dispatch
     (S       : in out Phase_Sequencer.State;
      Line    : String;
      Applied : out Boolean)
   is
      F1, L1, N1 : Natural;
      F2, L2, N2 : Natural;
      F3, L3, N3 : Natural;
      F4, L4, N4 : Natural;
      Have_1, Have_2, Have_3, Have_4 : Boolean;
      Ok         : Boolean;
   begin
      Applied := False;

      if Line'Length = 0 then
         return;
      end if;

      Next_Token (Line, Line'First, F1, L1, N1, Have_1);
      if not Have_1 then
         return;
      end if;

      declare
         Verb : constant String := Line (F1 .. L1);
      begin
         if Verb = "RESET" then
            --  RESET takes no arguments; anything trailing is rejected
            --  (the spec lists "RESET" as a complete form; tolerating
            --  trailing tokens would normalize unknown commands into a
            --  reset which would be surprising).
            Next_Token (Line, N1, F2, L2, N2, Have_2);
            if Have_2 then
               return;
            end if;
            Phase_Sequencer.Reset_Controller (S);
            Applied := True;
            return;

         elsif Verb = "FAULT" then
            Next_Token (Line, N1, F2, L2, N2, Have_2);
            if not Have_2 then
               return;
            end if;
            Next_Token (Line, N2, F3, L3, N3, Have_3);
            if Have_3 then
               return;  --  unexpected extra token
            end if;
            declare
               Bit : constant Boolean := To_Bit (Line (F2 .. L2), Ok);
            begin
               if not Ok then
                  return;
               end if;
               Phase_Sequencer.Set_Fault (S, Bit);
               Applied := True;
            end;
            return;

         elsif Verb = "PRESS" then
            Next_Token (Line, N1, F2, L2, N2, Have_2);
            if not Have_2 or else Line (F2 .. L2) /= "PED" then
               return;
            end if;
            Next_Token (Line, N2, F3, L3, N3, Have_3);
            if not Have_3 then
               return;
            end if;
            Next_Token (Line, N3, F4, L4, N4, Have_4);
            if Have_4 then
               return;
            end if;
            declare
               CW : constant Pedestrian.Crosswalk :=
                  To_Crosswalk (Line (F3 .. L3), Ok);
            begin
               if not Ok then
                  return;
               end if;
               Phase_Sequencer.Press_Ped (S, CW);
               Applied := True;
            end;
            return;

         elsif Verb = "SET" then
            Next_Token (Line, N1, F2, L2, N2, Have_2);
            if not Have_2 or else Line (F2 .. L2) /= "LT" then
               return;
            end if;
            Next_Token (Line, N2, F3, L3, N3, Have_3);
            if not Have_3 then
               return;
            end if;
            Next_Token (Line, N3, F4, L4, N4, Have_4);
            if not Have_4 then
               return;
            end if;
            declare
               Tail_F, Tail_L, Tail_N : Natural;
               Tail_Have              : Boolean;
            begin
               Next_Token (Line, N4, Tail_F, Tail_L, Tail_N, Tail_Have);
               if Tail_Have then
                  return;
               end if;
            end;
            declare
               A   : constant Phase_Sequencer.Axis :=
                  To_Axis (Line (F3 .. L3), Ok);
               Bit : Boolean;
            begin
               if not Ok then
                  return;
               end if;
               Bit := To_Bit (Line (F4 .. L4), Ok);
               if not Ok then
                  return;
               end if;
               Phase_Sequencer.Set_Left_Demand (S, A, Bit);
               Applied := True;
            end;
            return;
         end if;
      end;
      --  Verb did not match any known form. Silently discard per § 2.
   end Dispatch;

end Cmd_Parser;
