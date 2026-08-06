# #51 — requirements-based tests: state and next steps

Read `classification.md` first: it holds the per-statement verification-means
assignment and the counts this document assumes.

## Where this stands

**#51's test-writing is complete.** Every LLR statement classified `test` that
can be written has a routine: 98 of them, across nine packages under
`tests/reqs/`, one package per LLR file and one routine per statement.

    make test    114 tests run: 107 passed; 7 failed
    make prove   clean, 0 unproved checks, no pragma Assume
    coverage     10 statement violations, down from 20

The seven failures are deliberate and are the point of the exercise — see
"The seven red tests". Nothing else is red.

| Package | Statements covered |
| --- | ---: |
| `llr_4_controller_1_vehicle_tests` | 43 (`.2`, rows `.3-.24`, transitions `.25-.50`) |
| `llr_4_controller_tests` | 19 (`.2-.11`, `.13-.20`, `.22`) |
| `llr_4_controller_3_pedestrian_tests` | 17 (`.1-.17`) |
| `llr_3_conflicts_tests` | 6 |
| `llr_2_buses_tests` | 4 |
| `llr_4_controller_2_left_demand_tests` | 3 |
| `llr_5_core_loop_tests` | 3 |
| `llr_1_states_tests` | 2 |
| `llr_6_hal_tests` | 1 |

The arithmetic: 106 statements classified `test`, less the 2 system-level ones
that belong to #17 (`llr_7_main.4`, `.5`), less the 6 that name sequencer states
which do not exist, is 98.

**Shared infrastructure** lives in `Reqs_Support` and its child `Loop_Spy`:
the vehicle Moore table (`Expected_Faces`), the pedestrian output table
(`Expected_Ped`), the two both-through commit intervals as the arithmetic the
requirements write, the `Vehicle_State` / `Pedestrian_State` constructors, the
`Quiet` snapshot, and the core-loop spy.

**The core loop is testable now.** `State_Machine_Loop` is `No_Return`, so
`Reqs_Support.Loop_Spy` instantiates it against recording formals and leaves it
the only way a `No_Return` procedure can be left: the spy `Delay_For` raises
after the requested number of iterations. Because the delay is the last of the
four stages, an escaped run ends on an iteration boundary with every stage of
the final iteration recorded. The run leaves a trace — stage order, the snapshot
each read delivered, the outputs each write received, the period each delay was
asked for — and `llr_5_core_loop.1`, `.2` and `.4` are each a property of that
trace. This closed the 8 uncovered statements in `state_machine_loop.adb`.

`llr_5_core_loop.1` needs a note: `Controller.Initialize` is not a formal of the
generic, so no spy can count its calls. It is checked through two consequences
that together admit only one call, and only before the first iteration — the
first iteration's outputs are the power-on projection, and the barrier's dwell is
allowed to elapse (a second `Initialize` would reload it forever). The routine
deliberately does not pin down *which* iteration carries the change, because
that is the emit/advance phase that `llr_4_controller.16` governs; pinning it
would make one defect fail two requirements.

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

   Transitions are the exception: their expected values are literal in each
   routine, as `Test_27` does. A table indexed by statement could not be
   complete (four statements name states that do not exist) and a transition's
   target is shared by no other statement, so the table would buy nothing.

8. **Annotate the requirement.** Every covered statement now carries a
   commented `verified_by` block naming the routine. Still commented-out valid
   YAML — `sed 's/^# //'` migrates it when the schema lands under #100. The
   seven failing statements carry a `status:` field explaining the divergence;
   #100's schema should accommodate it.

9. **Assert state, not outputs, unless the statement is about outputs.**
   `Controller.Step` emits before it advances (see the `.16` finding), so a
   routine that reads a state claim off the emitted display fails for someone
   else's defect. Every batch followed this and said so per routine.

## The seven red tests

Six are #63 — the code deliberately lags the requirements on the both-through
scheme. All six pass their non-firing case and fail only the firing assertion.

| Statement | Requirement | Code |
| --- | --- | --- |
| `.26` / `.39` | commit interval reserves a full lag block: 22 000 ms | 34 000 ms |
| `.29` / `.42` | same, after a lead ran: 10 000 ms | 22 000 ms |
| `.30` / `.43` | lagging demand read live at the commit boundary | flag latched on both-through entry, so the no-demand branch is taken |

The seventh is **new, not #63, and not yet tracked by any issue**:

**`llr_4_controller.16` — `Step` emits its outputs a sampling period early.**
The statement (and the file's `context`, twice: "then emits the resulting
state") requires `Outputs` to be the projection of the state left by this step's
arming *and* timed transition. `controller.adb` sets `Outputs` at stage 3 and
advances at stage 4, never recomputing, so every Moore output appears one
`T_SAMPLE` after the state change that produced it. `controller.ads`'s own
comment for `Step` documents the code's order, so the divergence is between two
deliberate descriptions, not an accident of implementation.

It is a phase convention, not a timing error: a state is still emitted exactly
`dwell / T_SAMPLE` times under either order, and the lag is uniform across the
vehicle and pedestrian machines, so nothing is internally inconsistent. But it
contradicts the statement as written, and someone has to decide which of the two
moves — the requirement or the code. `Test_16`'s other two groups (sampling
steps, input arming) pass, so the failure localises to the transition phase
alone.

## What is left

**Not testable as written — 6 statements, all #63.**
`llr_4_controller_1_vehicle.7`, `.18` (output rows), `.31`, `.44` (transitions
*to* a HOLD state) and `.32`, `.45` (transitions *from* one) name
`NS_BOTH_THROUGH_HOLD` / `EW_BOTH_THROUGH_HOLD`, and
`States.Vehicle_Sequencer_State` has 20 literals with neither. There is no
compilable Ada rendering — nothing to park in and nothing to assert. Each gap is
marked where it falls in `Expected_Faces`, in the test `.ads` declaration lists,
and in the `.adb` bodies. These become writable the day #63 lands.

**System-level — 2 statements.** `llr_7_main.4`, `.5` (startup ordering) belong
to #17.

**Other means — 35 statements.** 24 analysis (LKQL, #100/#101) and 11 compiler
check, of which only `llr_1_states.31` is done. `.27-.29` (the duration
inequalities) are flagged in `classification.md` as safety-relevant and
unchecked; they are the most valuable of that group.

**The monolith stays.** `Test_Initialize`, `Test_Project_Outputs` and `Test_Step`
in `tests/core/controller-test_data-tests.adb` claim no requirements
(`--@covers none:`) and remain as unattributed regression coverage. Retiring
them scenario-by-scenario, confirming coverage holds at each step, is a separate
pass — deliberately not done here.

## Tooling blockers, in priority order

1. **`make all-coverage` and `make report` now abort.** `coverage-test`
   propagates the suite's exit status, and the suite is red by design while the
   seven statements above diverge. The traces are still produced, so the numbers
   are obtainable with `make coverage-report-text` after the failing
   `coverage-test` step, which is how the 10-violation figure above was
   measured. Whoever owns the report pipeline has to decide how a
   deliberately-failing requirements-based test should be represented — this is
   the first real instance of the question.

2. **The `--@covers` tags are enforced by nothing**, for two independent
   reasons, both recorded in `requirements/trace_chain.yaml` beside
   `min_nodes`:
   - `engine/ada_tracer` will not build against this compiler
     (`gpr2-log.ads:137:09: completion of nonlimited type cannot be limited`),
     so no inventory can be regenerated and `make trace-check` cannot run.
   - Even fixed, `test-inventory` runs the tracer without `-U` on the harness
     project, and the tracer then reads only that project's own sources. The
     generated harness's `Source_Dirs` are `tests/core`, `tests/hal/common`,
     `tests/types` and its own `common`; `tests/reqs/` arrives as an *imported*
     project via `--additional-tests`, so all 98 routines are invisible to the
     TEST layer. Plain `-U` is not the fix — it would pull the application into
     a layer that requires every node to carry a `--@covers` tag.

   `min_nodes` therefore stays at 15 and should become 113 once both are fixed.
   Raising it now would only produce a failure with a misleading cause.

3. **`make check` fails at `HEAD`, independently of #51.** `check-ada` reports
   `conflicts.ads`, `sources.adb` and `states.ads` "not correctly formatted"
   with the community gnatformat (26.0.0) provisioned here, on an unmodified
   `src/`. Pro tools are x86_64-only and this host is aarch64, so the
   disagreement cannot be settled locally. `make format` was **not** committed
   for those three files.

4. **`make format` covers no test sources at all.** `tests/tests.gpr` declares
   `for Source_Dirs use ()`, so neither the generated skeletons nor
   `tests/reqs/` are ever formatted or format-checked. The new files are
   hand-formatted to the project's rules (3-space indent, 79 columns, two
   spaces after `--`). Adding `tests/reqs/reqs_tests.gpr` to `format-ada` and
   `check-format` needs a gnatformat that can see `aunit`, which is why it was
   not done here.
