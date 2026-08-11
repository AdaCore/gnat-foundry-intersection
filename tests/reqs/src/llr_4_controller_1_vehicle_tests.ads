--  Requirements-based tests for
--  requirements/llr/llr_4_controller_1_vehicle.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Statements 3-24 are the twenty-two rows of one Moore output table. Their
--  expected values live together in Reqs_Support.Expected_Faces as a single
--  aggregate with no `others` choice -- so adding a sequencer state fails to
--  compile until its row is transcribed -- while each row is *asserted* by its
--  own routine here, so a wrong row fails one requirement rather than
--  twenty-two.

with AUnit.Test_Fixtures;

package Llr_4_Controller_1_Vehicle_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Structural discipline (statement 2): a universal claim over the state
   --  alphabet and over the timer, so its routine runs all twenty sequencer
   --  states rather than a sample of them. Statement 1 is verified by analysis
   --  and has no routine here (see its verified_by annotation).
   procedure Test_02_Vehicle_Held_While_Dwell_Remains (T : in out Test);

   --  Moore output rows (statements 3-24), in statement order. Twenty of the
   --  twenty-two are written; .7 and .18 are not, because the sequencer states
   --  they name (NS_BOTH_THROUGH_HOLD, EW_BOTH_THROUGH_HOLD) do not exist in
   --  States.Vehicle_Sequencer_State (#63), so there is no state to park the
   --  controller in and nothing to call. The gaps are marked where they fall,
   --  here and in Reqs_Support.Expected_Faces.

   --  ---- NS axis ----
   procedure Test_03_N_Lead_Faces (T : in out Test);
   procedure Test_04_N_Lead_Yellow_Faces (T : in out Test);
   procedure Test_05_N_Lead_Clear_Faces (T : in out Test);
   procedure Test_06_NS_Both_Through_Faces (T : in out Test);
   --  .7 NS_BOTH_THROUGH_HOLD -- no routine: the state does not exist (#63)
   procedure Test_08_N_Drop_Yellow_Faces (T : in out Test);
   procedure Test_09_N_Drop_Clear_Faces (T : in out Test);
   procedure Test_10_S_Lag_Faces (T : in out Test);
   procedure Test_11_S_Lag_Yellow_Faces (T : in out Test);
   procedure Test_12_NS_Both_Drop_Yellow_Faces (T : in out Test);
   procedure Test_13_NS_Barrier_Allred_Faces (T : in out Test);

   --  ---- EW axis ----
   procedure Test_14_E_Lead_Faces (T : in out Test);
   procedure Test_15_E_Lead_Yellow_Faces (T : in out Test);
   procedure Test_16_E_Lead_Clear_Faces (T : in out Test);
   procedure Test_17_EW_Both_Through_Faces (T : in out Test);
   --  .18 EW_BOTH_THROUGH_HOLD -- no routine: the state does not exist (#63)
   procedure Test_19_E_Drop_Yellow_Faces (T : in out Test);
   procedure Test_20_E_Drop_Clear_Faces (T : in out Test);
   procedure Test_21_W_Lag_Faces (T : in out Test);
   procedure Test_22_W_Lag_Yellow_Faces (T : in out Test);
   procedure Test_23_EW_Both_Drop_Yellow_Faces (T : in out Test);
   procedure Test_24_EW_Barrier_Allred_Faces (T : in out Test);

   --  Transitions (statements 25-50), in statement order. Twenty-two of the
   --  twenty-six are written.
   --
   --  Four have no routine, for the same reason as .7 and .18: .31 and .44
   --  name NS_BOTH_THROUGH_HOLD / EW_BOTH_THROUGH_HOLD as their target and
   --  .32 and .45 name them as their source, and neither is a literal of
   --  States.Vehicle_Sequencer_State (#63) -- so there is no target to assert
   --  and no source to park the controller in. The gaps are marked where they
   --  fall, here and in the body.
   --
   --  Six of the twenty-two are expected to FAIL against today's code. They
   --  are written to the requirement anyway, undiluted, because that failure
   --  is the divergence #63 records:
   --
   --  * .26, .29, .39, .42 -- the both-through commit interval
   --    (Reqs_Support.Commit_After_Barrier, Commit_After_Lead). Each reserves
   --    a full lagging-left block; the code reserves only the closing yellow,
   --    so it loads a longer interval.
   --  * .30, .43 -- the lagging approach's demand read live at the commit
   --    boundary. The code decides the lag once, on entry to the both-through
   --    state, from a latched flag, so a state carrying a pending demand and
   --    no latched flag takes the other branch.
   --
   --  Every transition here is timed, so every routine carries two cases: it
   --  does not fire with two sampling periods of dwell left, and it does fire
   --  on the step whose remaining dwell is one, loading the target's own
   --  dwell. Test_27 spells that argument out; the rest do not repeat it.

   --  ---- NS axis ----
   procedure Test_25_EW_Barrier_Allred_To_N_Lead_On_North_Demand
     (T : in out Test);
   procedure Test_26_EW_Barrier_Allred_To_NS_Both_Through_No_Demand
     (T : in out Test);
   procedure Test_27_N_Lead_To_N_Lead_Yellow_On_Dwell_Elapse (T : in out Test);
   procedure Test_28_N_Lead_Yellow_To_N_Lead_Clear_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_29_N_Lead_Clear_To_NS_Both_Through_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_30_NS_Both_Through_To_N_Drop_Yellow_On_South_Demand
     (T : in out Test);
   --  .31 NS_BOTH_THROUGH -> NS_BOTH_THROUGH_HOLD -- no routine: the target
   --  state does not exist (#63)
   --  .32 NS_BOTH_THROUGH_HOLD -> NS_BOTH_DROP_YELLOW -- no routine: the
   --  source state does not exist (#63)
   procedure Test_33_N_Drop_Yellow_To_N_Drop_Clear_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_34_N_Drop_Clear_To_S_Lag_On_Dwell_Elapse (T : in out Test);
   procedure Test_35_S_Lag_To_S_Lag_Yellow_On_Dwell_Elapse (T : in out Test);
   procedure Test_36_S_Lag_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_37_NS_Both_Drop_Yellow_To_NS_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test);

   --  ---- EW axis (the exact mirror) ----
   procedure Test_38_NS_Barrier_Allred_To_E_Lead_On_East_Demand
     (T : in out Test);
   procedure Test_39_NS_Barrier_Allred_To_EW_Both_Through_No_Demand
     (T : in out Test);
   procedure Test_40_E_Lead_To_E_Lead_Yellow_On_Dwell_Elapse (T : in out Test);
   procedure Test_41_E_Lead_Yellow_To_E_Lead_Clear_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_42_E_Lead_Clear_To_EW_Both_Through_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_43_EW_Both_Through_To_E_Drop_Yellow_On_West_Demand
     (T : in out Test);
   --  .44 EW_BOTH_THROUGH -> EW_BOTH_THROUGH_HOLD -- no routine: the target
   --  state does not exist (#63)
   --  .45 EW_BOTH_THROUGH_HOLD -> EW_BOTH_DROP_YELLOW -- no routine: the
   --  source state does not exist (#63)
   procedure Test_46_E_Drop_Yellow_To_E_Drop_Clear_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_47_E_Drop_Clear_To_W_Lag_On_Dwell_Elapse (T : in out Test);
   procedure Test_48_W_Lag_To_W_Lag_Yellow_On_Dwell_Elapse (T : in out Test);
   procedure Test_49_W_Lag_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test);
   procedure Test_50_EW_Both_Drop_Yellow_To_EW_Barrier_Allred_On_Dwell_Elapse
     (T : in out Test);

end Llr_4_Controller_1_Vehicle_Tests;
