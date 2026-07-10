--  The conflict / crosswalk-to-movement binding the controller's safety
--  invariants and cross-machine couplings quantify over (jeeves plan Q3;
--  requirements/TODO.md "Crosswalk -> movement bindings" / conflict matrix).
--
--  `TODO.md` defers the conflict matrix and the crosswalk -> movement
--  enumeration to the LLR, but the controller cannot run or be proven without
--  them, so this package is the concrete landing of that deferred binding,
--  enumerated straight from the geometry the HLRs already state:
--    * the "next conflicting movement" list in `hlr_5_vehicle_1_left_demand`
--      context (N_left -> S_thru, S_left -> E_thru, E_left -> W_thru,
--      W_left -> N_thru), and
--    * the crosswalk naming (axis + side) in `states.ads`
--      (NS_North is adjacent to the North through, and so on).
--
--  It is a stand-alone package rather than a child of `Controller` on purpose:
--  `Controller`'s own contracts (the hlr_0_safety.2 postcondition on
--  Project_Outputs) refer to Conflicts, and a parent unit may not depend on
--  its own child, so the binding cannot be a `Controller.Conflicts` child.
--
--  Everything here is a pure, state-free expression function, so gnatprove
--  sees straight through it when discharging the safety postcondition.

with States;

package Conflicts
  with SPARK_Mode => On
is

   use type States.Movement;

   --  The vehicle movements (`States.Movement`), the faces they read
   --  (`States.Face_Of`), and the "go" predicate (`States.Is_Go`) live in
   --  `types/states.ads` alongside the approach vocabulary they build on.

   function Compatible (A, B : States.Movement) return Boolean
   is (A = B
       or else
         (A in States.N_Thru | States.N_Left
          and then B in States.N_Thru | States.N_Left)
       or else
         (A in States.S_Thru | States.S_Left
          and then B in States.S_Thru | States.S_Left)
       or else
         (A in States.E_Thru | States.E_Left
          and then B in States.E_Thru | States.E_Left)
       or else
         (A in States.W_Thru | States.W_Left
          and then B in States.W_Thru | States.W_Left)
       or else
         (A in States.N_Thru | States.S_Thru
          and then B in States.N_Thru | States.S_Thru)
       or else
         (A in States.E_Thru | States.W_Thru
          and then B in States.E_Thru | States.W_Thru));
   --  Two movements are *compatible* -- releasable together -- exactly when the
   --  serialized Moore sequencer ever drives them non-RED in the same output
   --  row (`hlr_5_vehicle.2`-.11 / .25-.34): a through with its own protected
   --  left (the lead / lag rows) or the two opposing throughs of one axis (the
   --  both-through rows). Every other pair is treated as conflicting. This is a
   --  sound (conservative) realization of the deferred geometric conflict
   --  matrix: any pair not known compatible is held to conflict, so the
   --  hlr_0_safety.2 postcondition it feeds can only be stronger, never weaker.
   --  @param A One movement
   --  @param B The other movement
   --  @return True when the two movements may be released together

   function Conflicts (A, B : States.Movement) return Boolean
   is (not Compatible (A, B));
   --  The negation of Compatible: two movements conflict when they may not be
   --  released together.
   --  @param A One movement
   --  @param B The other movement
   --  @return True when the two movements conflict

   function Safe_Faces (D : States.Display_State) return Boolean
   is (for all M1 in States.Movement =>
         (for all M2 in States.Movement =>
            (if Conflicts (M1, M2)
             then
               not (States.Is_Go (States.Face_Of (D, M1))
                    and then States.Is_Go (States.Face_Of (D, M2))))));
   --  hlr_0_safety.2 as a property of one Display_State: no two conflicting
   --  movements are both "go" at once. Holds trivially in FAULT (every face
   --  FLASHING_RED, none "go") and, in NORMAL_OPERATION, by construction of the
   --  Moore output rows (each row's non-RED faces are a compatible set).
   --  NOTE: documented in leading style pending a gnatdoc fix -- a trailing
   --  comment on this nested-quantifier expression function crashes the
   --  trailing extractor (gnatdoc-comments-extractor-trailing.adb:843).

   function Next_Conflicting_Through
     (A : States.Approach) return States.Approach
   is (case A is
         when States.North => States.South,   --  N_left cleared by S_thru
         when States.South => States.East,     --  S_left cleared by E_thru
         when States.East  => States.West,     --  E_left cleared by W_thru
         when States.West  => States.North);   --  W_left cleared by N_thru
   --  Binding for the left-demand clear (`hlr_5_vehicle_1_left_demand.4`): the
   --  through movement whose GREEN release ends each approach's protected-left
   --  clearance and so clears that approach's latched demand.
   --  @param A The approach whose latched left demand is being cleared
   --  @return The approach whose through release clears that demand

   function Adjacent_Through (C : States.Crosswalk) return States.Approach
   is (case C is
         when States.NS_North => States.North,
         when States.NS_South => States.South,
         when States.EW_East  => States.East,
         when States.EW_West  => States.West);
   --  Binding for the pedestrian PENDING -> WALK edge (`hlr_6_pedestrian.8`):
   --  the through movement parallel and adjacent to each crosswalk. Crosswalks
   --  are named axis + side in `states.ads`, so NS_North is adjacent to the
   --  North approach's through, NS_South to South, and the EW pair likewise.
   --  @param C The crosswalk whose adjacent through is wanted
   --  @return The approach whose through movement is parallel to that crosswalk

end Conflicts;
