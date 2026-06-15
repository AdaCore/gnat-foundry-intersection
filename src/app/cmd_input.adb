--  Cmd_Input body. Static line buffer, hand-rolled assembler.

with HAL;
with Cmd_Parser;

package body Cmd_Input is

   --  Wire-protocol § preamble recommends a 256-byte ceiling for line
   --  length. The longest valid line is ~14 bytes ("PRESS PED NW"), so
   --  256 is comfortable padding for whitespace tolerance.
   Buffer_Size : constant := 256;

   Buffer     : String (1 .. Buffer_Size) := (others => ' ');
   Cursor     : Natural := 0;      --  bytes currently buffered
   Overflowed : Boolean := False;
   --  True after we've dropped at least one byte for the in-progress
   --  line; the rest of that line is discarded up to and including LF.

   procedure Pump (S : in out Phase_Sequencer.State; Applied : out Boolean) is
      C   : Character;
      Got : Boolean;
      One : Boolean;
   begin
      Applied := False;

      loop
         HAL.Read_Cmd_Byte (C, Got);
         exit when not Got;

         if C = ASCII.LF then
            if Overflowed then
               Overflowed := False;
               Cursor := 0;
            else
               --  Strip an optional trailing CR (wire-protocol says LF-only,
               --  but a CRLF source shouldn't break the dispatcher).
               if Cursor > 0 and then Buffer (Cursor) = ASCII.CR then
                  Cursor := Cursor - 1;
               end if;
               Cmd_Parser.Dispatch (S, Buffer (1 .. Cursor), One);
               if One then
                  Applied := True;
               end if;
               Cursor := 0;
            end if;
         elsif Overflowed then
            null;  --  drop the byte; line already poisoned
         elsif Cursor >= Buffer_Size then
            Overflowed := True;
         else
            Cursor := Cursor + 1;
            Buffer (Cursor) := C;
         end if;
      end loop;
   end Pump;

end Cmd_Input;
