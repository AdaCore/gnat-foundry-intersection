--  Display body -- host profile. Renders the traffic state to stdout with
--  Ada.Text_IO, in the readable style of the old host HAL. Absorbs the old
--  Set_Through_Lamp / Set_Left_Lamp / Set_Walk / Set_Dont_Walk / Diag surface.

with Ada.Text_IO; use Ada.Text_IO;

package body Display is

   procedure Initialize is
   begin
      Put_Line ("[display/host] Initialize");
   end Initialize;

   procedure Show (S : States.Display_State) is
   begin
      for A in States.Approach loop
         Put_Line
           ("[display/host] through "
            & States.Approach'Image (A)
            & " "
            & States.Vehicle_Face'Image (S.Through (A)));
      end loop;
      for A in States.Approach loop
         Put_Line
           ("[display/host] left "
            & States.Approach'Image (A)
            & " "
            & States.Vehicle_Face'Image (S.Left (A)));
      end loop;
      for C in States.Crosswalk loop
         Put_Line
           ("[display/host] head "
            & States.Crosswalk'Image (C)
            & " "
            & States.Pedestrian_Head'Image (S.Heads (C)));
      end loop;
      for C in States.Crosswalk loop
         Put_Line
           ("[display/host] request "
            & States.Crosswalk'Image (C)
            & " "
            & States.Request_Indicator'Image (S.Requests (C)));
      end loop;
   end Show;

   procedure Diag_Write_Line (S : String) is
   begin
      Put_Line ("[diag] " & S);
   end Diag_Write_Line;

end Display;
