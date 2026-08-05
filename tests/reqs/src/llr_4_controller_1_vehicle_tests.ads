--  Requirements-based tests for requirements/llr/llr_4_controller_1_vehicle.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Statements 3-24 are the twenty-two rows of one Moore output table. Their
--  expected values live together in Reqs_Support.Vehicle_Faces as a single
--  aggregate with no `others` choice -- so adding a sequencer state fails to
--  compile until its row is transcribed -- while each row is *asserted* by its
--  own routine here, so a wrong row fails one requirement rather than
--  twenty-two.

with AUnit.Test_Fixtures;

package Llr_4_Controller_1_Vehicle_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Moore output rows (statements 3-24). Exemplar: only .6 is written.
   procedure Test_06_NS_Both_Through_Faces (T : in out Test);

   --  Transitions (statements 25-50). Exemplar: only .27 is written.
   --
   --  .26 was the intended exemplar but cannot pass: it requires the
   --  both-through commit interval to reserve a full lag block, and the code
   --  still decides the lag at both-through entry (#63). .27 is a plain
   --  fixed-dwell transition outside that divergence.
   procedure Test_27_N_Lead_To_N_Lead_Yellow_On_Dwell_Elapse (T : in out Test);

end Llr_4_Controller_1_Vehicle_Tests;
