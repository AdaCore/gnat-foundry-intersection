# #51 — requirements-based tests: state and next steps

Read `classification.md` first: it holds the per-statement verification-means
assignment and the counts this document assumes.

## What is already done

**Classification.** All 143 LLR statements assigned a means. 106 test, 24
analysis, 11 compiler check, 2 proof.

**Attribution cleaned.** The three monolithic routines
(`Test_Initialize`, `Test_Project_Outputs`, `Test_Step` in
`tests/core/controller-test_data-tests.adb`) no longer claim any requirement —
they are `--@covers none:` and stay in the suite purely as regression coverage
until the per-requirement tests replace them. Three skeletons that asserted
nothing while claiming requirements are now explicit `null;` no-ops.
`--skeleton-default=fail` is on, so a future empty skeleton fails loudly.

**Test project.** `tests/reqs/`, folded into the generated harness by
`gnattest --additional-tests` (see `GNATTEST_FLAGS` in the Makefile). One
package per LLR file, one routine per statement.

**Six exemplars, all green.**

| Means | Statement | Evidence |
| --- | --- | --- |
| proof | `llr_4_controller.12`, `.21` | `src/core/controller.ads:93`, `:105` |
| compiler check | `llr_1_states.31` | `src/types/states.ads:346-387` |
| analysis | `llr_4_controller_1_vehicle.1` | annotation only; no LKQL yet |
| test, exhaustive | `llr_3_conflicts.3` | `llr_3_conflicts_tests.adb` |
| test, tabular | `llr_4_controller_1_vehicle.6` | `llr_4_controller_1_vehicle_tests.adb` |
| test, timed | `llr_4_controller_1_vehicle.27` | same file |

## Conventions to follow — these are the review criteria

1. **One routine per LLR statement.** Name it
   `Test_<nn>_<behaviour_phrase>`, where `<nn>` is the statement number. The
   `--@covers` tag is the first line of the body and names exactly one
   statement.

2. **File per LLR file.** `tests/reqs/src/<llr_file_stem>_tests.{ads,adb}`. A
   routine's statements must belong to the LLR file its filename names.

3. **Expected values are transcribed from the requirement text, never from the
   code.** This is the load-bearing rule. Two independent renderings of the
   same English, cross-checked exhaustively, is evidence; one rendering
   agreeing with itself is not. If a table is ever back-filled from the
   implementation the tests silently stop proving anything.

4. **Exhaustive over small finite domains.** The state and input alphabets are
   enumerations, so enumerate them — do not sample. There is no
   equivalence-partitioning or high/med/low probing to do.

5. **Timed transitions get two cases.** An EARS "when its dwell elapses"
   statement asserts both that the transition fires at the boundary and that
   it does not fire before it. One case passes against off-by-one-tick code.
   Every dwell is a multiple of `T_SAMPLE` (`llr_1_states.31`) and firing is
   at remaining dwell `<= T_SAMPLE` (`llr_4_controller.18`), so the boundary is
   exactly one step wide — see `Test_27_...` for the shape.

6. **Build states directly.** `Controller_State` is a public record; use
   `Reqs_Support.Vehicle_State` and friends rather than driving the machine
   through unrelated behaviour. This is what keeps each test short and
   independent.

7. **Shared tables live in `Reqs_Support`, with no `others` choice**, so adding
   an enumeration literal fails the build until its row is transcribed. Each
   row is asserted by its own routine, so a wrong row fails one requirement.
   Every row carries its `.<n>` statement number.

8. **Annotate the requirement.** Add the commented `verified_by` block to the
   LLR statement (see any exemplar). Commented-out valid YAML — `sed 's/^# //'`
   migrates it when the schema lands under #100. Do **not** add a real
   `verified_by:` key: the schema rejects unknown keys and #100 is another
   person's work item.

## The remaining work

**100 tests to write** (98 unit, 2 system-level). Distribution by file is in
`classification.md`. `llr_4_controller_1_vehicle` is 49 of them — 21 more
tabular rows at ~3 lines each, and 26 timed transitions at two cases each.

**Ten of the 100 are blocked by #63** and must not be attempted:
`llr_4_controller_1_vehicle.7`, `.18`, `.31`, `.32`, `.44`, `.45` name
sequencer states that do not exist, and `.26`, `.29`, `.39`, `.42` would fail
(`.26` wants a 22 000 ms commit interval; the code produces 34 000 ms).
Annotate them `BLOCKED (#63)` as `.26` already is, and skip.

**Two are system-level** (`llr_7_main.4`, `.5`) and belong to #17, not here.

**`llr_5_core_loop.1`, `.2`, `.4` need a technique that does not exist yet:**
`State_Machine_Loop` is `No_Return`, so a test must instantiate it with a spy
`Delay_For` that escapes the loop by exception after N iterations. Worth
solving once, in `Reqs_Support`, before farming the rest out — it is the only
statement group whose test shape is unsettled, and it closes the 8 uncovered
statements in `state_machine_loop.adb`.

## Suggested fan-out

The work parallelises by LLR file, since each maps to one test package with no
shared state beyond `Reqs_Support`. Sensible units of work:

| Batch | Statements | Notes |
| --- | ---: | --- |
| `llr_4_controller_1_vehicle` rows `.3-.24` | 21 | mechanical; table already transcribed |
| `llr_4_controller_1_vehicle` transitions `.25-.50` | 22 | minus the 4 blocked; two cases each |
| `llr_4_controller` `.2-.11`, `.13-.20`, `.22` | 19 | `Initialize`, `Project_Outputs`, `Step` frame |
| `llr_4_controller_3_pedestrian` `.1-.17` | 17 | 9 tabular, 8 behavioural |
| `llr_3_conflicts` `.1`, `.2`, `.4`, `.5`, `.6` | 5 | port from the existing skeletons |
| `llr_2_buses` `.1-.4` | 4 | needs spy producer/consumer |
| `llr_5_core_loop` `.1`, `.2`, `.4` | 3 | do this one first, see above |
| `llr_1_states` `.19`, `.20`; `llr_6_hal.1` | 3 | port from skeletons |

Anything touching `Reqs_Support` should be serialised — parallel edits to one
shared table will conflict. Transcribe a batch's table rows into
`Reqs_Support` up front, then fan out the assertion routines.

## Finishing pass

1. `make test` — every routine green.
2. `make all-coverage` — must not have regressed from the 20 statement
   violations recorded at the start (all in `main.adb`, `state_machine_loop*`,
   `buses.adb`). Closing `llr_2_buses` and `llr_5_core_loop` should *reduce*
   that number.
3. Retire the monolith: delete each scenario from `Test_Step` as its
   replacement lands, confirming coverage holds. Done when the three routines
   are empty.
4. Raise `min_nodes` in `requirements/trace_chain.yaml:59` (currently 15) to
   the new routine count.
5. `make trace-check` — **currently impossible**: `engine/ada_tracer` will not
   build here (libadalang/GPR2 against this compiler,
   `gpr2-log.ads:137:09: error: completion of nonlimited type cannot be
   limited`). Until that is fixed the `--@covers` tags are not mechanically
   checked by anything. Treat as a blocker to raise, not to work around.
