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
   expectation alone, record the divergence in the statement's `verified_by`
   block (`status:`), and raise it. Seven tests fail today for this reason: six
   for #63, one for #105.

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
   outputs.** `Controller.Step` emits before it advances (#105), so a state
   claim read off the display fails for someone else's defect.

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

`workflow/verification-means/classification.md` records which means was assigned
to each of the 143 LLR statements, and why.
