--  Requirements-based tests for requirements/llr/llr_1_states.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Only the two statements that give States a *function* are here. The rest
--  of the file declares types, constants and predicates, whose means is a
--  compiler check or analysis (see
--  workflow/verification-means/classification.md), so they have no routine.
--  Both functions are pure and total over small finite domains, so both
--  routines are exhaustive.

with AUnit.Test_Fixtures;

package Llr_1_States_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_19_Face_Of_Reads_The_Movements_Own_Face (T : in out Test);

   procedure Test_20_Is_Go_Holds_Exactly_For_Green_And_Yellow
     (T : in out Test);

end Llr_1_States_Tests;
