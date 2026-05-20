--  C-callable symbols expected by crt0.S that bare_runtime does not itself
--  provide. The controller loop never returns, but the linker still needs
--  to resolve the `bl _exit` instruction in the reset handler tail.

package Support is

   procedure OS_Exit;
   pragma Export (C, OS_Exit, "_exit");

end Support;
