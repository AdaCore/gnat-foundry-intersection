# LLR verification-means classification (first pass)

143 LLR statements, classified by the means that can discharge them.

**Classifier used.** Not "does the text force one means" (that misfires — see
Notes) but: *does the statement constrain the **shape of a declaration**, or the
**values a subprogram produces**?* Shape → analysis or compiler check. Values →
test or proof.

| Means | Statements | Share | Carries over |
| --- | ---: | ---: | ---: |
| test | 106 | 74% | 6 |
| analysis (LKQL) | 24 | 17% | 0 |
| compiler check | 11 | 8% | 1 |
| proof | 2 | 1% | 2 (after the `.12`/`.21` reword) |

"Carries over" is test *content* that survives the rewrite, not statements a
test touches today. 31 statements are cited by a `--@covers` tag right now, but
25 of those come from `Test_Initialize` / `Test_Project_Outputs` / `Test_Step`,
whose tags are being stripped — that credit goes to zero. See Notes.

---

## test — 106

| Range | n | Shape |
| --- | ---: | --- |
| `llr_1_states.19-.20` | 2 | `Face_Of`, `Is_Go` over finite domains — exhaustive. **Both stubs today.** |
| `llr_2_buses.1-.4` | 4 | generic bus behaviour; spy producer/consumer |
| `llr_3_conflicts.1-.6` | 6 | relations over finite domains — exhaustive. `.2` is a stub; `.3` is 2 cases, needs exhaustive |
| `llr_4_controller.2-.11` | 10 | `Initialize` post-state; `Project_Outputs` FAULT + NORMAL projections |
| `llr_4_controller.13-.20`, `.22` | 9 | `Step` frame: fault entry, terminality, sampling, timed firing, GREEN-edge couplings |
| `llr_4_controller_1_vehicle.2` | 1 | "changes only when dwell elapsed" — universal over timer values; **proof candidate** |
| `llr_4_controller_1_vehicle.3-.24` | 22 | Moore output table, one row per sequencer state — tabular |
| `llr_4_controller_1_vehicle.25-.50` | 26 | transition relation — timed, 2 cases each (fires at boundary, not before) |
| `llr_4_controller_2_left_demand.1-.3` | 3 | arming, idempotence, clear-on-rising-GREEN |
| `llr_4_controller_3_pedestrian.1-.9` | 9 | `Head_Of` / `Request_Of` tables — tabular, exhaustive |
| `llr_4_controller_3_pedestrian.10-.17` | 8 | arming/latch/service edges, timed transitions, timer-running invariant |
| `llr_5_core_loop.1-.2`, `.4` | 3 | loop ordering and cadence; needs a spy `Delay_For` that escapes the `No_Return` loop |
| `llr_6_hal.1` | 1 | `Delay_For` wall-clock floor — exists |
| `llr_7_main.4-.5` | 2 | startup ordering — **system-level, belongs to #17 not #51** |

Carried over: 6. To write: 100 (98 unit + 2 system-level).

## analysis (LKQL) — 24

None implemented. Per #100, annotate and mark uncovered.

| Range | n | Check |
| --- | ---: | --- |
| `llr_1_states.1-.10`, `.12-.13`, `.18` | 13 | enumeration type has exactly these literals |
| `llr_1_states.11`, `.14` | 2 | array type over this index, this component |
| `llr_1_states.15` | 1 | subtype is this contiguous range |
| `llr_1_states.16-.17` | 2 | record aggregates exactly these components |
| `llr_4_controller.1` | 1 | `Controller_State` holds exactly these fields |
| `llr_4_controller_1_vehicle.1` | 1 | `State.Vehicle` assigned only in `Advance_Vehicle` |
| `llr_5_core_loop.3` | 1 | `No_Return`, no termination path |
| `llr_7_main.1-.3` | 3 | instantiation wiring (generic ← actual) |

## compiler check — 11

| Range | n | Status |
| --- | ---: | --- |
| `llr_1_states.21` | 1 | `Duration_Ms` range — no check |
| `llr_1_states.22-.26`, `.30` | 6 | constant valuations — no check |
| `llr_1_states.27-.29` | 3 | duration inequalities — **no check, and safety-relevant** |
| `llr_1_states.31` | 1 | dwell/T_SAMPLE divisibility — **done**, `states.ads:346-387` (10 pragmas) |

## proof — 2

| Statement | Evidence |
| --- | --- |
| `llr_4_controller.12` (reworded) | `Post` at `src/core/controller.ads:93` |
| `llr_4_controller.21` (reworded) | `Post` at `src/core/controller.ads:105` |

`#103` would add a third (`Both_Duration >= T_BOTH_MIN`).

**These two are the statements whose evidence can evaporate unnoticed.** Both
were reworded away from *"shall carry the postcondition ..."* — a claim about
source text — to the behaviour, which is the right shape for a requirement but
changes what a regression looks like. Deleting the `Post` aspect at
`controller.ads:93` no longer falsifies the statement: `Project_Outputs` would
still *return* a `Safe_Faces` display, being total and literal per state. All
that would break is the recorded means pointing at a contract that is no longer
there — and since `verified_by` is a comment no tool reads, in silence. On the
repository's headline safety property, with two of the three proof statements in
the set. The general fix belongs to #100: a `means: proof` block whose cited
contract is absent should fail validation, which would serve #103's third
contract too.

---

## Notes

**The litmus test misfires on "shall define the function F returning …".**
`llr_3_conflicts.1-.6` and `llr_1_states.19-.20` all open with *"shall define"*,
which reads as artifact-shaped, but what they constrain is the value the
function returns over its domain — behaviour, and testable. Classify on the
predicate, not the verb.

**`llr_4_controller_1_vehicle` dominates.** 50 statements, 35% of the LLR layer,
49 of them test. Any estimate for #51 is mostly an estimate for this one file.

**Proof is thin.** Two statements out of 143 for a repo whose headline claim is
SPARK Silver. The behavioural properties proof establishes are largely unstated
at requirement level. The codebase carries four contracts —
`controller.ads:93`, `controller.ads:105`, `controller.adb:181`
(`Both_Duration'Result >= T_Both_Min and <= T_Axis`) and `controller.adb:377`
(a `Pre`) — and the third of those is discharged today with no requirement
pointing at it (#103).

**Six statements are blocked by #63.** The requirements specify a 22-state
sequencer with `NS_BOTH_THROUGH_HOLD` / `EW_BOTH_THROUGH_HOLD`;
`States.Vehicle_Sequencer_State` has 20 literals and neither HOLD state. So
`llr_4_controller_1_vehicle.7`, `.18`, `.31`, `.32`, `.44` and `.45` cannot be
tested at all, and `.26` / `.29` / `.39` / `.42` would fail if written
faithfully — `.26` requires a 22 000 ms commit interval where the code produces
34 000 ms. #63 records that the code lags the requirements here deliberately.
These ten are inside the 106 and are not yet subtracted from it.

**Currently mis-attributed.** `llr_4_controller.12` and `.21` are cited by
`--@covers` on `Test_Project_Outputs` / `Test_Step` today; both are proof.

**What "carries over" means.** Every test is rewritten or ported into the new
`--additional-tests` project; nothing stays where it is. Of the 31 statements
cited today:

| Source | Cited | Fate |
| --- | ---: | --- |
| `Test_Initialize`, `Test_Project_Outputs`, `Test_Step` | 25 | tags stripped, quarantined as unattributed regression coverage; credit → 0 |
| conflicts tests | 5 | content reusable — ported and renamed; `.3` needs strengthening first |
| `Test_Delay_For` | 1 | content reusable — ported and renamed |
| the three stubs | 3 | delete |

The monolith still has salvage value as raw material even though no routine
survives it: `Barrier_State`
(`tests/core/controller-test_data-tests.adb:251`), the fault-outputs aggregate
(`:270`), and the cycle-driving loops are worked-out state constructors for the
new project's shared infrastructure. They carry no verification credit.

**`llr_3_conflicts.3` is load-bearing and thinly tested.** It grounds the
`Safe_Faces` predicate that the two proof statements rely on. Two cases today;
needs exhaustive over movement pairs.
