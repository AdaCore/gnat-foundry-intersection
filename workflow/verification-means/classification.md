# LLR verification-means classification

143 LLR statements, classified by the means that can discharge them.

**Classifier used.** Not "does the text force one means" (that misfires — see
Notes) but: *does the statement constrain the **shape of a declaration**, or the
**values a subprogram produces**?* Shape → compiler check. Values → test or
proof.

| Means | Statements | Share | Was (first pass) |
| --- | ---: | ---: | ---: |
| test | 109 | 76% | 106 |
| compiler check | 31 | 22% | 11 |
| proof | 3 | 2% | 2 |
| analysis (LKQL) | 0 | — | 24 |

**The analysis bucket is empty.** The first pass sent 24 statements to a
not-yet-written LKQL rule (#101) on the grounds that shape claims are not
testable. That was too pessimistic: in Ada most shape claims *are* statically
decidable, by writing a declaration from the requirement that does not compile
when the shape is wrong. 20 of the 24 moved to compiler check, one to proof,
and three to system-level test. #101 can close as won't-do — see "What replaced
the LKQL rule" below.

---

## test — 109

| Range | n | Shape |
| --- | ---: | --- |
| `llr_1_states.19-.20` | 2 | `Face_Of`, `Is_Go` over finite domains — exhaustive |
| `llr_2_buses.1-.4` | 4 | generic bus behaviour; spy producer/consumer |
| `llr_3_conflicts.1-.6` | 6 | relations over finite domains — exhaustive |
| `llr_4_controller.2-.11` | 10 | `Initialize` post-state; `Project_Outputs` FAULT + NORMAL projections |
| `llr_4_controller.13-.20`, `.22` | 9 | `Step` frame: fault entry, terminality, sampling, timed firing, GREEN-edge couplings |
| `llr_4_controller_1_vehicle.2` | 1 | "changes only when dwell elapsed" — **also proved**, see below |
| `llr_4_controller_1_vehicle.3-.24` | 22 | Moore output table, one row per sequencer state |
| `llr_4_controller_1_vehicle.25-.50` | 26 | transition relation — timed, 2 cases each |
| `llr_4_controller_2_left_demand.1-.3` | 3 | arming, idempotence, clear-on-rising-GREEN |
| `llr_4_controller_3_pedestrian.1-.9` | 9 | `Head_Of` / `Request_Of` tables — tabular, exhaustive |
| `llr_4_controller_3_pedestrian.10-.17` | 8 | arming/latch/service edges, timed transitions, timer-running invariant |
| `llr_5_core_loop.1-.2`, `.4` | 3 | loop ordering and cadence, through `Reqs_Support.Loop_Spy` |
| `llr_6_hal.1` | 1 | `Delay_For` wall-clock floor |
| `llr_7_main.1-.5` | 5 | wiring and startup ordering — **system-level, #17, none written** |

Ten of these are blocked by or fail for #63; see Notes.

## compiler check — 31

Nineteen of the twenty new ones are *shape witnesses* under `tests/reqs/`:
declarations written from the requirement text that the compiler rejects when
the declaration under test has the wrong shape, wrapped in a routine so each
carries a `--@covers` tag and a run-time assertion of the part a declaration
cannot state about itself. The technique, and its three failure modes, are in
`tests/reqs/README.md` rule 10.

| Range | n | Witness | Where |
| --- | ---: | --- | --- |
| `llr_1_states.1-.10`, `.12-.13`, `.18` | 13 | Boolean table over the type, no `others`, plus a cardinality tally | `llr_1_states_tests.adb` |
| `llr_1_states.11`, `.14` | 2 | typed index and typed cell, plus a per-index tally | `llr_1_states_tests.adb` |
| `llr_1_states.15` | 1 | ends held in base-type constants, found by walking the subtype | `llr_1_states_tests.adb` |
| `llr_1_states.16-.17` | 2 | full named aggregate, no `others`, over typed component groups | `llr_1_states_tests.adb` |
| `llr_4_controller.1` | 1 | as above — **partial**, see Notes | `llr_4_controller_tests.adb` |
| `llr_5_core_loop.3` | 1 | `No_Return` on the declaration; **also proved and tested** | `state_machine_loop.ads:31` |
| `llr_1_states.21` | 1 | `Duration_Ms` range — no check | — |
| `llr_1_states.22-.26`, `.30` | 6 | constant valuations — no check | — |
| `llr_1_states.27-.29` | 3 | duration inequalities — **no check, and safety-relevant** | — |
| `llr_1_states.31` | 1 | dwell/T_SAMPLE divisibility — 10 `Compile_Time_Error` pragmas | `states.ads:346-387` |

The bottom four rows are unchanged from the first pass and are still the
outstanding compiler-check work: eleven statements about the timing valuation,
of which only `.31` has a check. `.27-.29` are the static discharge of the
pedestrian-conflict invariant, so they are the ones worth doing next.

## proof — 3

| Statement | Evidence | Mutation-tested |
| --- | --- | --- |
| `llr_4_controller.12` (reworded) | `Post` at `controller.ads:100` | (see below) |
| `llr_4_controller.21` (reworded) | `Post` at `controller.ads:114` | (see below) |
| `llr_4_controller_1_vehicle.1` | frame `Post` at `controller.ads:108-118` and `controller.adb:375-390` | yes |

`llr_4_controller_1_vehicle.2` and `llr_5_core_loop.3` are also proved, but are
counted under test and compiler check respectively — each has a means that
reaches further.

`#103` would add a fourth (`Both_Duration >= T_BOTH_MIN`).

**`.12` and `.21` are still the statements whose evidence can evaporate
unnoticed.** Both were reworded away from *"shall carry the postcondition ..."*
— a claim about source text — to the behaviour, which is the right shape for a
requirement but changes what a regression looks like. Deleting the `Post` at
`controller.ads:100` no longer falsifies the statement: `Project_Outputs` would
still *return* a `Safe_Faces` display, being total and literal per state. All
that would break is the recorded means pointing at a contract that is no longer
there — and since `verified_by` is a comment no tool reads, in silence. The
general fix belongs to #100: a `means: proof` block whose cited contract is
absent should fail validation.

The new frame contract does not have that problem — deleting it leaves nothing
else asserting the frame — and it was checked by mutation both ways: a
`State.Vehicle` assignment added to Step's FAULT branch and one added to
`Advance_Ped` each make `make prove` fail.

---

## What replaced the LKQL rule

| Was | n | Now |
| --- | ---: | --- |
| enumeration has exactly these literals | 13 | compiler check — table over the type with no `others` |
| array over this index, this component | 2 | compiler check — typed index expression, typed cell |
| subtype is this contiguous range | 1 | compiler check — ends in base-type constants |
| record aggregates exactly these components | 2 | compiler check — full named aggregate, no `others` |
| `Controller_State` holds exactly these fields | 1 | compiler check, partial (Veh_Lag) |
| `State.Vehicle` assigned only in `Advance_Vehicle` | 1 | proof — frame contracts |
| `No_Return`, no termination path | 1 | compiler check + proof + test |
| `llr_7_main.1-.3` instantiation wiring | 3 | test (#17) — the compiler cannot help here |

**The syntactic rule would have been the *worse* means for the frame
statement.** The #101 placeholder called for a rule asserting that no
assignment to a `State.Vehicle` component appears outside `Advance_Vehicle`'s
body. `Enter_Both` (`controller.adb:238`) is exactly such an assignment: a
local helper called only from `Advance_Vehicle`, satisfying the requirement's
intent and not its letter. A syntactic rule needs a hand-maintained exception
list; the proof formulation gets it right for free, because `Enter_Both` sits
inside `Advance_Vehicle`'s call tree and inherits no obligation.

**Instantiation wiring is the one thing the compiler genuinely cannot check.**
Generic formal matching checks the *profile* of an actual, not its identity:
`new Buses.Source_Bus (Producer => Sources.Sample)` compiles just as happily
with any other matching procedure. Since what `llr_7_main.1-.3` are really
about is behavioural — every input signal reaching the controller from the HAL
sources — they belong with `.4-.5` in #17, not in a static rule. Three
statements is not worth a new tool in the chain.

---

## Notes

**The litmus test misfires on "shall define the function F returning …".**
`llr_3_conflicts.1-.6` and `llr_1_states.19-.20` all open with *"shall define"*,
which reads as artifact-shaped, but what they constrain is the value the
function returns over its domain — behaviour, and testable. Classify on the
predicate, not the verb.

**And it misfires the other way on "shall define the type T with exactly …".**
That is what sent thirteen alphabet statements to analysis. The predicate is
about a declaration, but a declaration is something the compiler can be made to
check — which is a different question from whether a *test* can check it, and
the one that matters.

**`llr_4_controller.1` is only partly discharged.** The statement says
`Controller_State` holds six things; the record holds seven. `Veh_Lag` is
admitted by name in the witness rather than breaking the build, so what is
established is that the six named components are present with the right types,
plus a build-time gate on any *further* component. The surplus is not
cosmetic: `Veh_Lag` latches the lag decision at both-through entry and the exit
guards read the latch, where `llr_4_controller_1_vehicle.30`/`.43` require the
demand to be read live at the commit boundary. It goes away with #63.

**`llr_4_controller_1_vehicle` dominates.** 50 statements, 35% of the LLR
layer. Any estimate for #51 is mostly an estimate for this one file.

**Ten statements are blocked by or fail for #63.** The requirements specify a
22-state sequencer with `NS_BOTH_THROUGH_HOLD` / `EW_BOTH_THROUGH_HOLD`;
`States.Vehicle_Sequencer_State` has 20 literals and neither HOLD state. So
`llr_4_controller_1_vehicle.7`, `.18`, `.31`, `.32`, `.44` and `.45` cannot be
tested at all, and `.26`, `.29`, `.30`, `.39`, `.42` and `.43` fail. As of this
pass `llr_1_states.12` fails for the same cause and is the most direct
statement of it: the witness can only name the twenty literals that exist, and
asserts the count the requirement gives.

**`llr_3_conflicts.3` is load-bearing and thinly tested.** It grounds the
`Safe_Faces` predicate that `.12`/`.21` rely on. Two cases today; needs
exhaustive over movement pairs.

**`make check` is red on `main`, unrelated to any of this.** `conflicts.ads`,
`sources.adb` and `states.ads` are not gnatformat-clean at HEAD. Left alone
here so the diff stays about verification means.
