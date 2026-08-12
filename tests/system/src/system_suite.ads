--  The system-level suite: every fixture under tests/system/src, registered
--  for the driver. Written out rather than generated, one entry per test
--  routine.

with AUnit.Test_Suites;

package System_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite;
   --  The suite holding every system-level test routine.
   --  @return The assembled suite

end System_Suite;
