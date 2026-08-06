--  Requirements-based tests for requirements/llr/llr_3_conflicts.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  All six statements of that file are covered here. Each is a relation or a
--  map over a small finite domain -- eight movements, four approaches, four
--  crosswalks -- so every routine ranges over its whole domain: 64 movement
--  pairs for .1, .2 and .3, 32 crosswalk/movement pairs for .6, and the four
--  entries of the maps .4 and .5. Nothing here is sampled.

with AUnit.Test_Fixtures;

package Llr_3_Conflicts_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_01_Compatible_Holds_For_Exactly_The_Listed_Pairs
     (T : in out Test);

   procedure Test_02_Conflicts_Is_The_Complement_Of_Compatible
     (T : in out Test);

   procedure Test_03_Safe_Faces_Holds_Exactly_When_No_Conflicting_Pair_Is_Go
     (T : in out Test);

   procedure Test_04_Next_Conflicting_Through_Maps_Every_Approach
     (T : in out Test);

   procedure Test_05_Adjacent_Through_Maps_Every_Crosswalk
     (T : in out Test);

   procedure Test_06_Crosswalk_Conflicts_Exempts_Exactly_The_Listed_Pairs
     (T : in out Test);

end Llr_3_Conflicts_Tests;
