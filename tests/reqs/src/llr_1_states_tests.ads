--  Requirements-based tests for requirements/llr/llr_1_states.yaml.
--
--  One routine per statement; the routine name carries the statement number so
--  a failure names its requirement without a lookup.
--
--  Statements .1-.18 constrain declarations rather than behaviour -- what
--  literals a type has, what a record aggregates -- and are verified here by
--  *shape witnesses*: declarations written from the requirement text which the
--  compiler rejects when the shape is wrong. Each is wrapped in a routine so
--  it carries a `--@covers` tag and a runtime assertion of the part a
--  declaration cannot state on its own (a cardinality, a bound). See
--  tests/reqs/README.md rule 10 for the technique and what it does and does
--  not establish. Statements .19-.20 are the two the package gives a
--  *function*, verified conventionally and exhaustively over their finite
--  domains.

with AUnit.Test_Fixtures;

package Llr_1_States_Tests is

   type Test is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  ---- output signal alphabets ----

   procedure Test_01_Vehicle_Face_Has_Exactly_Four_Literals (T : in out Test);

   procedure Test_02_Pedestrian_Head_Has_Exactly_Four_Literals
     (T : in out Test);

   procedure Test_03_Request_Indicator_Has_Exactly_Two_Literals
     (T : in out Test);

   --  ---- input signal alphabets ----

   procedure Test_04_Fault_Detection_Has_Exactly_Two_Literals
     (T : in out Test);

   procedure Test_05_Pedestrian_Button_Has_Exactly_Two_Literals
     (T : in out Test);

   procedure Test_06_Left_Turn_Detector_Has_Exactly_Two_Literals
     (T : in out Test);

   --  ---- instance indices ----

   procedure Test_07_Approach_Has_Exactly_Four_Literals (T : in out Test);

   procedure Test_08_Crosswalk_Has_Exactly_Four_Literals (T : in out Test);

   --  ---- machine-state enumerations ----

   procedure Test_09_Mode_Has_Exactly_Two_Literals (T : in out Test);

   procedure Test_10_Left_Demand_State_Has_Exactly_Two_Literals
     (T : in out Test);

   procedure Test_11_Left_Demand_Array_Holds_One_State_Per_Approach
     (T : in out Test);

   procedure Test_12_Vehicle_Sequencer_Has_Exactly_Twenty_Two_States
     (T : in out Test);

   procedure Test_13_Pedestrian_State_Has_Exactly_Six_Literals
     (T : in out Test);

   procedure Test_14_Pedestrian_Array_Holds_One_State_Per_Crosswalk
     (T : in out Test);

   procedure Test_15_Serving_Pedestrian_State_Spans_Walk_To_Buffer_Latched
     (T : in out Test);

   --  ---- I/O aggregates ----

   procedure Test_16_Display_State_Aggregates_Every_Output_Signal
     (T : in out Test);

   procedure Test_17_Sensors_State_Aggregates_Every_Input_Signal
     (T : in out Test);

   --  ---- the movement view ----

   procedure Test_18_Movement_Has_Exactly_Eight_Literals (T : in out Test);

   --  ---- the two functions ----

   procedure Test_19_Face_Of_Reads_The_Movements_Own_Face (T : in out Test);

   procedure Test_20_Is_Go_Holds_Exactly_For_Green_And_Yellow
     (T : in out Test);

end Llr_1_States_Tests;
