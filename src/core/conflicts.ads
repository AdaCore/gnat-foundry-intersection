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

   --  The eight vehicle movements -- the eight vehicle face output signals of
   --  `hlr_4_signals.1`: the four through movements and the four protected-left
   --  movements. This is the index the vehicle-conflict invariant
   --  `hlr_0_safety.2` quantifies over.
   type Movement is
     (N_Thru, S_Thru, E_Thru, W_Thru, N_Left, S_Left, E_Left, W_Left);

   --  The face a Display_State drives for a given movement: the through
   --  movements read the Through faces, the left movements the Left faces.
   function Face_Of
     (D : States.Display_State; M : Movement) return States.Vehicle_Face
   is (case M is
         when N_Thru => D.Through (States.North),
         when S_Thru => D.Through (States.South),
         when E_Thru => D.Through (States.East),
         when W_Thru => D.Through (States.West),
         when N_Left => D.Left (States.North),
         when S_Left => D.Left (States.South),
         when E_Left => D.Left (States.East),
         when W_Left => D.Left (States.West));

   --  A face is "go" -- releasing traffic -- exactly when it is GREEN or
   --  YELLOW. `hlr_0_safety.2` forbids two conflicting movements being driven
   --  to GREEN or YELLOW at once; RED and the FAULT-only FLASHING_RED are both
   --  restrictive (stop), hence safe together.
   function Is_Go (F : States.Vehicle_Face) return Boolean
   is (F in States.Green | States.Yellow);

   --  Two movements are *compatible* -- releasable together -- exactly when the
   --  serialized Moore sequencer ever drives them non-RED in the same output
   --  row (`hlr_5_vehicle.2`-.11 / .25-.34): a through with its own protected
   --  left (the lead / lag rows) or the two opposing throughs of one axis (the
   --  both-through rows). Every other pair is treated as conflicting. This is a
   --  sound (conservative) realization of the deferred geometric conflict
   --  matrix: any pair not known compatible is held to conflict, so the
   --  hlr_0_safety.2 postcondition it feeds can only be stronger, never weaker.
   function Compatible (A, B : Movement) return Boolean
   is (A = B
       or else (A in N_Thru | N_Left and then B in N_Thru | N_Left)
       or else (A in S_Thru | S_Left and then B in S_Thru | S_Left)
       or else (A in E_Thru | E_Left and then B in E_Thru | E_Left)
       or else (A in W_Thru | W_Left and then B in W_Thru | W_Left)
       or else (A in N_Thru | S_Thru and then B in N_Thru | S_Thru)
       or else (A in E_Thru | W_Thru and then B in E_Thru | W_Thru));

   function Conflicts (A, B : Movement) return Boolean
   is (not Compatible (A, B));

   --  hlr_0_safety.2 as a property of one Display_State: no two conflicting
   --  movements are both "go" at once. Holds trivially in FAULT (every face
   --  FLASHING_RED, none "go") and, in NORMAL_OPERATION, by construction of the
   --  Moore output rows (each row's non-RED faces are a compatible set).
   function Safe_Faces (D : States.Display_State) return Boolean
   is (for all M1 in Movement =>
         (for all M2 in Movement =>
            (if Conflicts (M1, M2)
             then
               not (Is_Go (Face_Of (D, M1))
                    and then Is_Go (Face_Of (D, M2))))));

   --  Binding for the left-demand clear (`hlr_5_vehicle_1_left_demand.4`): the
   --  through movement whose GREEN release ends each approach's protected-left
   --  clearance and so clears that approach's latched demand.
   function Next_Conflicting_Through
     (A : States.Approach) return States.Approach
   is (case A is
         when States.North => States.South,   --  N_left cleared by S_thru
         when States.South => States.East,     --  S_left cleared by E_thru
         when States.East  => States.West,     --  E_left cleared by W_thru
         when States.West  => States.North);   --  W_left cleared by N_thru

   --  Binding for the pedestrian PENDING -> WALK edge (`hlr_6_pedestrian.8`):
   --  the through movement parallel and adjacent to each crosswalk. Crosswalks
   --  are named axis + side in `states.ads`, so NS_North is adjacent to the
   --  North approach's through, NS_South to South, and the EW pair likewise.
   function Adjacent_Through (C : States.Crosswalk) return States.Approach
   is (case C is
         when States.NS_North => States.North,
         when States.NS_South => States.South,
         when States.EW_East  => States.East,
         when States.EW_West  => States.West);

end Conflicts;
