--  Sources body -- host profile. Keyboard simulation of the sensor surface:
--  each Sample call drains whatever the operator has typed since the previous
--  poll and folds those keypresses into one Sensors_State snapshot.
--
--  Key map (the specification, no other magic literals):
--    '1' '2' '3' '4' -- pedestrian request, crosswalk NS_North / NS_South /
--                       EW_East / EW_West -> Pressed
--    'n' 's' 'e' 'w' -- left-turn detector, approach North / South / East /
--                       West -> Vehicle_Present
--  Unrecognized keys are ignored; the fault-detection line has no key and
--  stays Not_Asserted.
--
--  The drain is a non-blocking, coalescing pass: keys not seen this poll read
--  inactive (Released / No_Vehicle), and repeated presses of the same key
--  within one poll collapse to a single active reading (the set is
--  idempotent). See Sample for the two termination paths.
--
--  This is the host simulation only; the UART/target edge-capture realization
--  of the producer lives under the qemu_zynq7000 profile.

with Ada.IO_Exceptions;
with Ada.Text_IO;

package body Sources is

   procedure Decode (Key : Character; Value : in out States.Sensors_State);
   --  Fold one keypress into the snapshot being built. Recognized keys set
   --  their signal active (idempotent); unrecognized keys leave Value
   --  unchanged.
   --  @param Key The character drained from the input queue
   --  @param Value The snapshot being accumulated this poll

   procedure Decode (Key : Character; Value : in out States.Sensors_State) is
   begin
      case Key is
         when '1'    =>
            Value.Buttons (States.NS_North) := States.Pressed;

         when '2'    =>
            Value.Buttons (States.NS_South) := States.Pressed;

         when '3'    =>
            Value.Buttons (States.EW_East) := States.Pressed;

         when '4'    =>
            Value.Buttons (States.EW_West) := States.Pressed;

         when 'n'    =>
            Value.Left_Turns (States.North) := States.Vehicle_Present;

         when 's'    =>
            Value.Left_Turns (States.South) := States.Vehicle_Present;

         when 'e'    =>
            Value.Left_Turns (States.East) := States.Vehicle_Present;

         when 'w'    =>
            Value.Left_Turns (States.West) := States.Vehicle_Present;

         when others =>
            null;
      end case;
   end Decode;

   procedure Sample (Value : out States.Sensors_State) is
      Item      : Character;
      Available : Boolean;
   begin
      --  Start all-quiet; keys not seen this poll read inactive.
      Value :=
        (Buttons    => (others => States.Released),
         Left_Turns => (others => States.No_Vehicle),
         Fault      => States.Not_Asserted);

      loop
         Ada.Text_IO.Get_Immediate (Item, Available);
         pragma
           Annotate
             (Xcov,
              Exempt_On,
              "live-tty only: under file/pipe-redirected input "
              & "Get_Immediate returns Available => True until EOF, then "
              & "raises End_Error, so 'not Available' is never True in "
              & "automated tests; this exit is the interactive-terminal "
              & "empty-queue path (see Get_Immediate file-vs-tty semantics "
              & "in the header comment).");
         exit when not Available;   --  live-tty: input queue empty
         pragma Annotate (Xcov, Exempt_Off);
         Decode (Item, Value);
      end loop;
   exception
      when Ada.IO_Exceptions.End_Error =>
         --  Input stream drained / closed: the accumulated snapshot stands.
         null;
   end Sample;

end Sources;
