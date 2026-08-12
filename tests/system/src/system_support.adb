package body System_Support is

   use all type States.Vehicle_Face;

   function All_Vehicle_Red (Frame : States.Display_State) return Boolean is
   begin
      for A in States.Approach loop
         if Frame.Through (A) /= Red or else Frame.Left (A) /= Red then
            return False;
         end if;
      end loop;

      return True;
   end All_Vehicle_Red;

   function Any_Yellow (Frame : States.Display_State) return Boolean is
   begin
      for A in States.Approach loop
         if Frame.Through (A) = Yellow or else Frame.Left (A) = Yellow then
            return True;
         end if;
      end loop;

      return False;
   end Any_Yellow;

   function Released_Movements (Frame : States.Display_State) return String is
      Listed : String (1 .. 256);
      Length : Natural := 0;

      procedure Append (Item : String);
      --  Add Item to the list, comma-separated, silently dropping an item
      --  that would overflow Listed.
      --  @param Item The movement to name

      procedure Append (Item : String) is
         Separator : constant String := (if Length = 0 then "" else ", ");
         Addition  : constant String := Separator & Item;
      begin
         if Length + Addition'Length <= Listed'Last then
            Listed (Length + 1 .. Length + Addition'Length) := Addition;
            Length := Length + Addition'Length;
         end if;
      end Append;

   begin
      for A in States.Approach loop
         if Frame.Through (A) /= Red then
            Append
              (States.Approach'Image (A)
               & " through "
               & States.Vehicle_Face'Image (Frame.Through (A)));
         end if;

         if Frame.Left (A) /= Red then
            Append
              (States.Approach'Image (A)
               & " left "
               & States.Vehicle_Face'Image (Frame.Left (A)));
         end if;
      end loop;

      return Listed (1 .. Length);
   end Released_Movements;

end System_Support;
