--  Sources -- the producer side of the source data bus. Shared spec:
--  identical across the native and target profiles, which supply the bodies.
--  See src/hal.gpr.

with States;

package Sources is

   --  Sample the whole input surface -- pedestrian demand buttons, left-turn
   --  detectors, and the fault-detection line -- into one Sensors_State. This
   --  is exactly the signature of Buses.Source_Bus's generic formal Activate,
   --  so `app` can instantiate the source bus directly against it:
   --
   --     package Source is new Buses.Source_Bus (Activate => Sources.Sample);
   --
   --  It replaces the old ad-hoc Read_Button / Read_Cmd_Byte surface.
   procedure Sample (Value : out States.Sensors_State);

end Sources;
