# Requirements-based tests

One test package per LLR file, one routine per LLR statement. These are
hand-written, unlike the generated skeletons under `tests/core`, `tests/types`
and `tests/hal`: the layout mirrors `requirements/llr/`, not the code's package
structure. `gnattest --additional-tests` folds them into the same `make test`
and the same `make all-coverage`.

The rules below are the review criteria for adding one.

1. **Expected values are transcribed from the requirement text, never from the
   code.** This is the load-bearing rule. Two independent renderings of the same
   English, cross-checked over a whole domain, is evidence; one rendering
   agreeing with itself is not. Read `src/` for signatures, not for answers.

2. **A faithful test that fails is a finding, not a test to fix.** Leave the
   expectation alone, raise it, and say so in a comment where the routine falls,
   naming the issue. Seven tests fail today for this reason, all for #63. The
   eighth was `Test_16`'s: #105 was settled in the requirement's favour and the
   routine now passes, which is what rule 2 is for.

3. **One routine per statement**, named `Test_<nn>_<behaviour_phrase>` with the
   statement number zero-padded. The `--@covers <llr_file_stem>.<nn>` tag is the
   first line of the body and names exactly one statement. Nothing enforces
   these tags yet — see #106 — so review is the only gate.

4. **Exhaustive over finite domains.** The state and input alphabets are
   enumerations; enumerate them. There is no sampling or partitioning to do.

5. **Timed statements get two cases**: the transition fires on the step whose
   remaining dwell is `T_SAMPLE`, and does *not* fire with `2 * T_SAMPLE` left.
   Checking only that it fires passes against off-by-one-tick code. Every dwell
   is a multiple of `T_SAMPLE` (`llr_1_states.31`) and firing is at remaining
   dwell `<= T_SAMPLE` (`llr_4_controller.18`), so the boundary is exactly one
   step wide. `Test_27` in `llr_4_controller_1_vehicle_tests.adb` is the shape.

6. **Assert state, not emitted outputs, unless the statement is about
   outputs.** `Step` emits last, so the display does now project the resulting
   state (#105) — but reading a state claim off it routes the claim through
   `Project_Outputs` and through `llr_4_controller.16`'s emit phase, so the
   routine fails for someone else's defect. `Project_Outputs` is lossy besides:
   BUFFER_INTERVAL and NO_PEDESTRIAN_REQUEST share DONT_WALK with NO_REQUEST,
   and PENDING_PEDESTRIAN_REQUEST and BUFFER_INTERVAL_LATCHED share DONT_WALK
   with REQUEST_PENDING, so the display cannot identify a pedestrian sub-state
   at all.

7. **Build states with `Reqs_Support`'s constructors** rather than driving the
   machine there through unrelated behaviour. That is what keeps each routine
   short and independent of every other requirement.

8. **Shared expected-value tables live in `Reqs_Support`, with no `others`
   choice**, so a new enumeration literal fails the build until its row is
   transcribed. Each row is still asserted by its own routine, so a wrong row
   fails one requirement rather than all of them, and each carries its `.<n>`.
   Transitions are the exception — their targets are shared by no other
   statement, and four of them name states the code does not have, so no table
   over them could be complete.

9. **A generic or `No_Return` unit is tested by instantiating it against
   recording spies.** `Reqs_Support.Loop_Spy` does this for the core loop,
   escaping the endless loop by exception from the spy `Delay_For`;
   `llr_2_buses_tests` does it for the buses. Read the former before writing a
   third.

10. **A statement about the shape of a declaration gets a *shape witness*: a
    declaration written from the requirement that does not compile when the
    shape is wrong.** These routines look odd next to the rest — the evidence
    is mostly in the declarative part, and the body asserts something small —
    so the technique is worth stating once.

    | Claim | Witness | What it rejects |
    | --- | --- | --- |
    | a type has exactly these literals | a Boolean table indexed by the type, one named association per literal, no `others` | a literal added (aggregate incomplete), removed or renamed (choice names nothing) |
    | an array is over this index, of this component | index it with a value of the index type and hold the cell in a constant of the component type | either type being anything else |
    | a record aggregates exactly these components | a full named aggregate, no `others` | a component added, removed or renamed, or given another type |
    | a subtype is this range of that type | hold its ends in constants of the base type | a subtype of another type, or wrong ends |

    Three rules go with it:

    - **The witness cannot count.** An aggregate is complete for whatever the
      type happens to hold, so it cannot say the requirement asked for four.
      Each routine therefore *also* asserts the cardinality at run time,
      arrived at by iterating the type rather than read off `'Length`.
    - **Prefer the run-time assertion to `pragma Compile_Time_Error`** for
      anything the code might diverge on. A static witness for a divergence
      breaks the build instead of reporting a finding, which rule 2 forbids;
      `llr_1_states.12` is the live example. The pragma is right where the
      claim cannot fail without the code already being wrong — see
      `states.ads:346-387` for `llr_1_states.31`.
    - **Watch for the compiler folding the assertion away.** `-gnatwc` reports
      it ("condition is always True") and a folded assertion is not a test.
      Route the value through something non-static — iterating the type, as
      `Test_15` does.

## Where the means assignment lives

Each LLR statement's `verification:` block in `requirements/llr/*.yaml` names
the means that discharge it, and that data is the record — there is no separate
classification document. `make trace-check` reads it in both directions: a
`--@covers` here citing a statement that does not declare `test` is an error,
and a `test`-declaring statement with no citing routine reports uncovered.

Nine statements declare `test` and have no routine here, all of them blocked
rather than overlooked:

| Statements | Why | Issue |
| --- | --- | --- |
| `llr_4_controller_1_vehicle.7`, `.18`, `.31`, `.32`, `.44`, `.45` | name the two HOLD sequencer states, which `States.Vehicle_Sequencer_State` does not have — there is nothing to drive the machine into | #63 |
| `llr_7_main.1-.3` | the instantiation wiring: system-level, and no unit test can observe which actual a generic was instantiated with | #17 |

The six #63 casualties each carry a comment where they fall in
`llr_4_controller_1_vehicle_tests.adb`. The three `llr_7_main` statements have
no package of their own, since a package of three comments and no routines
would not survive `gnattest`; this table is their marker.
