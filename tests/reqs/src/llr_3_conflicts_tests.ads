--  Requirements-based tests for requirements/llr/llr_3_conflicts.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.

with AUnit.Test_Fixtures;

package Llr_3_Conflicts_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_03_Safe_Faces_Holds_Exactly_When_No_Conflicting_Pair_Is_Go
     (T : in out Test);

end Llr_3_Conflicts_Tests;
