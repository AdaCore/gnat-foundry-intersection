with AUnit.Assertions; use AUnit.Assertions;

with States;
with System_Support.Demand;

package body Demand_Tests is

   use type States.Crosswalk;
   use type States.Duration_Ms;
   use type States.Fault_Detection;
   use type States.Left_Turn_Detector;
   use type States.Pedestrian_Button;

   package Demand renames System_Support.Demand;

   procedure Test_Windows_Bound_The_Scripted_Reads (T : in out Test) is
      --@observes none: the demand script, not a requirement

      pragma Unreferenced (T);

      Opens  : constant States.Duration_Ms := 1_000;
      Closes : constant States.Duration_Ms := 2_000;
      Late   : constant States.Duration_Ms := 8_000;
      Far    : constant States.Duration_Ms := 3_000_000;

      procedure Check_Idle (Read_At : States.Duration_Ms; Context : String);
      --  Assert every input reads idle at Read_At.
      --  @param Read_At The read to examine
      --  @param Context What the script holds, for the message

      procedure Check_Idle (Read_At : States.Duration_Ms; Context : String) is
         Read : constant States.Sensors_State := Demand.Snapshot (Read_At);
      begin
         for C in States.Crosswalk loop
            Assert
              (Read.Buttons (C) = States.Released,
               Context
               & " must read every button RELEASED, but "
               & States.Crosswalk'Image (C)
               & " read PRESSED at"
               & States.Duration_Ms'Image (Read_At)
               & " ms");
         end loop;

         for A in States.Approach loop
            Assert
              (Read.Left_Turns (A) = States.No_Vehicle,
               Context
               & " must read every detector NO_VEHICLE, but "
               & States.Approach'Image (A)
               & " read VEHICLE_PRESENT at"
               & States.Duration_Ms'Image (Read_At)
               & " ms");
         end loop;

         Assert
           (Read.Fault = States.Not_Asserted,
            Context & " must read the fault line NOT_ASSERTED");
      end Check_Idle;

   begin
      Demand.Clear;
      Check_Idle (0, "an unscripted read");
      Check_Idle (Far, "an unscripted read");

      Demand.Press (States.East_Side, From => Opens, Before => Closes);

      Assert
        (Demand.Snapshot (Opens - 1).Buttons (States.East_Side)
         = States.Released,
         "the read before a press window must not see the press");

      Assert
        (Demand.Snapshot (Opens).Buttons (States.East_Side) = States.Pressed,
         "the window's first read must see the press");

      Assert
        (Demand.Snapshot (Closes - 1).Buttons (States.East_Side)
         = States.Pressed,
         "the window's last read must see the press");

      Assert
        (Demand.Snapshot (Closes).Buttons (States.East_Side) = States.Released,
         "the read closing a press window must not see the press");

      declare
         Read : constant States.Sensors_State := Demand.Snapshot (Opens);
      begin
         for C in States.Crosswalk loop
            Assert
              (C = States.East_Side or else Read.Buttons (C) = States.Released,
               "a press must reach its own crosswalk only, but "
               & States.Crosswalk'Image (C)
               & " read PRESSED too");
         end loop;

         for A in States.Approach loop
            Assert
              (Read.Left_Turns (A) = States.No_Vehicle,
               "a press must not reach a detector, but "
               & States.Approach'Image (A)
               & " read VEHICLE_PRESENT");
         end loop;
      end;

      Demand.Left_Turn (States.North, From => Late);

      Assert
        (Demand.Snapshot (Late - 1).Left_Turns (States.North)
         = States.No_Vehicle,
         "the read before a detector window must not see the vehicle");

      Assert
        (Demand.Snapshot (Late).Left_Turns (States.North)
         = States.Vehicle_Present,
         "the window's first read must see the vehicle");

      Assert
        (Demand.Snapshot (Far).Left_Turns (States.North)
         = States.Vehicle_Present,
         "a window left open must still be open however late the read");

      Demand.Press (States.East_Side, From => Late);

      Assert
        (Demand.Snapshot (Opens).Buttons (States.East_Side) = States.Released,
         "a second press on a crosswalk must replace its window");

      Demand.Clear;
      Check_Idle (Opens, "a read after Clear");
      Check_Idle (Late, "a read after Clear");
   end Test_Windows_Bound_The_Scripted_Reads;

end Demand_Tests;
