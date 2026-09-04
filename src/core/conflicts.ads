--  The conflict / crosswalk-to-movement binding the controller's safety
--  invariants and cross-machine couplings quantify over (`llr_3_conflicts`).
--
--  The HLRs state the invariants but leave the binding quantified; the
--  controller can neither run nor be proven without it, so this package is
--  where the conflict matrix and the crosswalk -> movement enumeration land,
--  taken straight from the geometry the HLRs already state:
--    * the "next conflicting movement" list in `hlr_5_vehicle_1_left_demand`
--      context (N_left -> S_thru, S_left -> E_thru, E_left -> W_thru,
--      W_left -> N_thru), and
--    * keep-right geometry over the two naming conventions of `states.ads`
--      (crosswalks named by the junction side they span, approaches by
--      travel direction): northbound traffic keeps to the east half of the
--      road, so the East_Side crossing is adjacent to the North through,
--      and so on around the junction.
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
   --  Two movements are *compatible* -- releasable together -- exactly when
   --  the serialized Moore sequencer ever drives them non-RED in the same
   --  output row (`hlr_5_vehicle.2`-.11 / .25-.34): a through with its own
   --  protected left (the lead / lag rows) or the two opposing throughs of one
   --  axis (the both-through rows). Every other pair is treated as
   --  conflicting. This is a sound (conservative) realization of the deferred
   --  geometric conflict matrix: any pair not known compatible is held to
   --  conflict, so the hlr_0_safety.2 postcondition it feeds can only be
   --  stronger, never weaker.
   --
   --  The symmetric relation in full, transcribed from the
   --  `llr_3_conflicts` algorithm_aspects table -- `·` a compatible pair,
   --  `X` a conflicting one:
   --
   --                NT ST ET WT NL SL EL WL
   --      N_THRU     ·  ·  X  X  ·  X  X  X
   --      S_THRU     ·  ·  X  X  X  ·  X  X
   --      E_THRU     X  X  ·  ·  X  X  ·  X
   --      W_THRU     X  X  ·  ·  X  X  X  ·
   --      N_LEFT     ·  X  X  X  ·  X  X  X
   --      S_LEFT     X  ·  X  X  X  ·  X  X
   --      E_LEFT     X  X  ·  X  X  X  ·  X
   --      W_LEFT     X  X  X  ·  X  X  X  ·
   --
   --  The N_LEFT/S_LEFT cell is the conservatism above by example: the two
   --  opposing protected lefts never share an output row, so they are held to
   --  conflict even though a fuller geometric analysis might permit them.
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
   --  FLASHING_RED, none "go") and, in NORMAL_OPERATION, by construction of
   --  the Moore output rows (each row's non-RED faces are a compatible set).
   --  NOTE: documented in leading style pending a gnatdoc fix -- a trailing
   --  comment on this nested-quantifier expression function crashes the
   --  trailing extractor (gnatdoc-comments-extractor-trailing.adb:843).

   function Next_Conflicting_Through
     (Turn : States.Approach) return States.Approach
   is (case Turn is
         when States.North => States.South,   --  N_left cleared by S_thru
         when States.South => States.East,     --  S_left cleared by E_thru
         when States.East  => States.West,     --  E_left cleared by W_thru
         when States.West  => States.North);   --  W_left cleared by N_thru
   --  Binding for the left-demand clear (`hlr_5_vehicle_1_left_demand.4`): the
   --  through movement whose GREEN release ends each approach's protected-left
   --  clearance and so clears that approach's latched demand.
   --  @param Turn The approach making the protected left turn, i.e. the one
   --  whose latched left demand is being cleared
   --  @return The approach whose through release clears that demand

   function Adjacent_Through (C : States.Crosswalk) return States.Approach
   is (case C is
         when States.North_Side => States.West,
         when States.South_Side => States.East,
         when States.East_Side  => States.North,
         when States.West_Side  => States.South);
   --  Binding for the pedestrian PENDING -> WALK edge (`hlr_6_pedestrian.8`):
   --  the through movement parallel and adjacent to each crosswalk. Crosswalks
   --  are named by the junction side they span and approaches by travel
   --  direction, so the map is a 90-degree rotation, from keep-right geometry:
   --  a through movement keeps to its own right half of the road, touching the
   --  crossing on the arm to its right (northbound traffic hugs the east half,
   --  so East_Side is adjacent to North, and so on around the junction).
   --  @param C The crosswalk whose adjacent through is wanted
   --  @return The approach whose through movement is parallel to that
   --  crosswalk

   function Crosswalk_Conflicts
     (C : States.Crosswalk; M : States.Movement) return Boolean
   is (case C is
         when States.North_Side =>
           M not in States.E_Thru | States.W_Thru | States.W_Left,
         when States.South_Side =>
           M not in States.E_Thru | States.W_Thru | States.E_Left,
         when States.East_Side  =>
           M not in States.N_Thru | States.S_Thru | States.N_Left,
         when States.West_Side  =>
           M not in States.N_Thru | States.S_Thru | States.S_Left);
   --  The crosswalk conflict relation (`hlr_0_safety.3` / CONOPS §3.9): a
   --  movement conflicts with a crosswalk unless it is one of the two through
   --  movements of the crosswalk's parallel axis -- the axis perpendicular to
   --  the arm it spans -- or the protected left of `Adjacent_Through (C)`, the
   --  left that turns away from the crossing rather than sweeping across it.
   --  Each case arm above is one row of the `llr_3_conflicts`
   --  algorithm_aspects table (`·` non-conflicting, `X` conflicting):
   --
   --                  N_THRU S_THRU E_THRU W_THRU N_LEFT S_LEFT E_LEFT W_LEFT
   --      NORTH_SIDE    X      X      ·      ·      X      X      X      ·
   --      SOUTH_SIDE    X      X      ·      ·      X      X      ·      X
   --      EAST_SIDE     ·      ·      X      X      ·      X      X      X
   --      WEST_SIDE     ·      ·      X      X      X      ·      X      X
   --
   --  This is the binding hlr_0_safety.1 and hlr_3_timing.10 quantify over
   --  ("hold every conflicting movement RED while the crosswalk is served").
   --  Nothing reads it at run time: that invariant is discharged statically by
   --  the margin inequalities (llr_1_states.27/.28) over the sequencer
   --  schedule, so this enumeration is a proof / audit entity -- what makes
   --  those margins' completeness checkable against the geometry.
   --  @param C The crosswalk being served
   --  @param M The movement to test against it
   --  @return True when the movement conflicts with that crosswalk

end Conflicts;
