--  Display -- the consumer side of the display data bus. Shared spec:
--  identical across the native and target profiles, which supply the bodies.
--  See src/hal.gpr.

with States;

package Display is

   --  Bring the display surface up: a banner on the host, UART0 on the target.
   procedure Initialize;

   --  Render the whole traffic state to the display (console on the host, the
   --  UART0 wire stream on the target). This is exactly the signature of
   --  Buses.Display_Bus's generic formal Consume, so `app` can instantiate the
   --  display bus directly against it:
   --
   --     package Sink is new Buses.Display_Bus (Consume => Display.Show);
   --
   --  It absorbs the old Set_Through_Lamp / Set_Left_Lamp / Set_Walk /
   --  Set_Dont_Walk surface.
   procedure Show (S : States.Display_State);

   --  Emit a free-form diagnostic line, retained for the bring-up main and any
   --  ad-hoc diagnostics.
   procedure Diag_Write_Line (S : String);

end Display;
