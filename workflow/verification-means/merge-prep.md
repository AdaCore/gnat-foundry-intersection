# Merge prep: !84 against #51

!84 (`topic/Tracing-script-improvements`, based on main at `142fd3b`) closes #100:
every LLR statement declares a live `verification:` block, and machine evidence
moves artifact-side — a `--@covers` tag on a test routine, or on the comment
line directly above a contract aspect or pragma. The trace engine gains PROOF
and STATIC layers over that evidence and reports upward, per artifact, instead
of downward from the LLR.

It classifies the same 143 statements this directory's
[classification.md](classification.md) does, arriving at **123 test, 15
static_check, 3 proof, 2 review** against our **109 test, 31 compiler check, 3
proof, 0 analysis**.

**103 statements agree outright.** 12 more agree in substance and differ only in
vocabulary — our "compiler check" is their `static_check`. The remaining 28 are
below, each with the disposition decided 2026-08-07.

## Why the mechanics decide most of it

Two rules of !84's gate constrain what we can declare, whatever we think the
right means is:

- `static_check` and `proof` evidence must be a `--@covers` tag anchored to a
  **pragma or aspect**. `requirements/trace_chain.yaml` accepts
  `pragma:Compile_Time_Error` and `aspect:No_Return` for STATIC, `aspect:Post`
  for PROOF. There is no anchor kind for an ordinary declaration.
- The gate is bidirectional and exact. A `--@covers` on a routine whose
  statement does not declare `test` is an error; a statement declaring a method
  with no citing evidence is `E-TRACE-UNCOVERED`.

So a shape witness — a declaration written from the requirement that the
compiler rejects when the shape is wrong — has no anchor of its own. Wrapped in
a test routine, as `tests/reqs/` wraps ours, it is a TEST node and nothing else.

## Dispositions

| Statements | classification.md | !84 | Disposition |
| --- | --- | --- | --- |
| `llr_1_states.1-.18` (18) | compiler check — shape witnesses in `tests/reqs/src/llr_1_states_tests.adb`, written and passing | `test` | **Take `test`.** Our witnesses are tagged test routines, so the gate forces the label; declaring `static_check` would be red on both layers at once. Nothing is lost mechanically — a wrong shape still fails the build before the test runs. Record the distinction in `tests/reqs/README.md` rule 10. !84's own `review-reduction.md` calls `static_check` via `'Pos` pragmas "equally" valid; rewriting 18 witnesses to change a label is not worth it. |
| `llr_1_states.29` | compiler check, no check written | `proof` — tag on `Both_Duration`'s `Post`, `controller.adb:178` | **Push back: `static_check`.** `.29` constrains the *valuation*, and its inequality is static over named constants (40000 − 2000 − 12000 − 16000 = 10000 ≥ `T_BOTH_MIN`). A `Compile_Time_Error` beside !84's other nine is the faithful anchor. Proof is for expressions that are not constant-valued, or that the compiler cannot discharge; neither holds here. Their anchor also cites the function whose formula their own `findings.md` reports as deviating from `.26/.29/.39/.42`. |
| `llr_4_controller.12`, `.21` (2) | `proof` only | `test` + `proof`, `--@covers` on both `Post`s | **Take theirs whole.** The tag is the general fix classification.md asked for under "`.12` and `.21` are still the statements whose evidence can evaporate unnoticed": deleting the `Post` now breaks the trace gate. **Keep our reworded text** — the rewording from "shall carry the postcondition" to the behaviour only worked because something else protects the contract, and now something does. |
| `llr_4_controller_1_vehicle.1`, `.2` (2) | `.1` proof + test, `.2` test + proof | both `proof` | **Declare both methods on both.** We hold both kinds of evidence and the schema takes a list. |
| `llr_7_main.1-.3` (3) | `test` — system-level, #17 | `static_check` | **Push back: `test`.** Generic formal matching checks the actual's *profile*, not its identity — `new Buses.Source_Bus (Bus_Write => Sources.Sample)` compiles with any conforming procedure. !84's own note concedes ".1–.3 pin shape only … stays reviewer-judged", which argues against the label it chose. No anchor construct exists for an instantiation either, so these three would sit uncovered permanently. |
| `llr_7_main.4`, `.5` (2) | `test` — system-level, #17 | `review`, justified as "Main is SPARK_Mode-off and never returns" | **Keep `review` at merge, but replace the justification** — it is false. `main.adb` carries no `SPARK_Mode` aspect at all (`traffic_light.gpr` says so: "NOT a proof target: main.adb carries no SPARK_Mode, so gnatprove skips it"). Main is absent from proof, not excluded from it, and `No_Return` is no obstacle to SPARK. Cite #17 and the open proof route instead. See "Raising Main to SPARK — #109" below. |

Vocabulary-only, no argument: `llr_1_states.21-.28`, `.30`, `.31`,
`llr_4_controller.1`, `llr_5_core_loop.3` all become `static_check`. Add `test`
and `proof` as further methods on `llr_5_core_loop.3`, where we hold all three.

`llr_4_controller.1` needs one extra note: !84 declares `static_check` with no
evidence and flags it WOULD-FAIL, but a full record aggregate is not a pragma or
aspect, so that declaration has no anchor available. Declare `test`, keep our
partial witness, and carry the PARTIAL note until #63 removes `Veh_Lag`.

## Merge-conflict resolutions

| File | Conflict | Resolution |
| --- | --- | --- |
| `requirements/llr/*.yaml` (all 10) | our commented-out `# verified_by:` blocks against their live `verification:` | Drop ours; take theirs with the dispositions above. Keep our reworded `llr_4_controller.12`/`.21` text. |
| `requirements/trace_chain.yaml` | they replace the TEST layer with `method: test` and add PROOF/STATIC; we added the #106 note and `min_nodes: 15` | Take theirs. `min_nodes` is superseded by the method-exact rule. Re-apply the #106 note. |
| `src/types/states.ads` | we hold the 10 divisibility pragmas; they hold those plus tags plus 9 valuation pragmas | Take theirs, plus a tenth valuation pragma for `.29` per its disposition. |
| `src/core/controller.ads` | our frame `Post` against their `--@covers` tags on `Project_Outputs` and `Step` | Both — the tags go on the contracts we kept. |
| `tests/core/controller-test_data-tests.adb` | their two-line edit against our gnattest line-reference refresh | Ours; re-apply their edit if still meaningful. |
| `CLAUDE.md` | their base predates the `make help` and comment-conventions merges | Not ours to fix — it will read as a revert until !84 rebases. Flag it on the MR. |

## What !84 gives us

- **The nine valuation `Compile_Time_Error` pragmas** for `llr_1_states.21-.28`
  and `.30` — exactly the outstanding compiler-check work classification.md
  named. Those rows come off our list.
- **The `--@covers` tags on the `Post`s of `llr_4_controller.12`/`.21`**, which
  close the evidence-evaporation hole we recorded and could not close ourselves.
- **Independent confirmation** of the #63 HOLD-state gap, the `Veh_Lag` latch,
  the `Both_Duration` formula deviation, and the emit-before-advance ordering we
  already track as #105. Two classifications reached these separately.

Their `findings.md` also flags the `states-test_data-tests.adb` skeletons as
vacuous evidence for `llr_1_states.19`/`.20`. We fixed that independently —
those routines now carry `--@covers none:` and the real tests live in
`tests/reqs/`.

## What still blocks a green gate

#106, which !84 does not touch, and which decides whether the merged result is
green or red for roughly 120 statements:

1. `test-inventory` runs `ada_tracer` on the gnattest harness project without
   `-U`, so it reads only that project's own sources. `tests/reqs/` arrives
   through an imported project (`--additional-tests`), so none of its 98 tagged
   routines reach the TEST inventory. Under !84's exact-coverage rule, every
   `test`-declared statement whose only evidence is there reports uncovered.
2. `engine/ada_tracer` does not build against this compiler
   (`gpr2-log.ads:137:09: completion of nonlimited type cannot be limited`), so
   neither inventory regenerates and `make trace-check` cannot run at all. This
   blocks !84's design on our toolchain too; its CI only sees it as an
   `allow_failure` job.

The `--@covers` annotation work needs nothing: all 98 requirements-based test
routines already carry tags in the exact syntax and position !84 requires.

## Raising Main to SPARK — #109

`llr_7_main.4`/`.5` are call-occurrence and ordering claims, not directly
assertable — but they can be made observable, which would empty the `review`
bucket entirely:

- `Display`'s spec takes `SPARK_Mode => On` with an `Abstract_State` and
  `Initial_Condition => not Initialized`; `Initialize` takes
  `Post => Initialized`. The body stays `SPARK_Mode => Off`, so `Ada.Text_IO`
  and the ANSI renderer never enter SPARK.
- Main takes `SPARK_Mode => On` and wraps `Run` in a **local** non-returning
  subprogram with `Pre => Display.Initialized`.

That one precondition discharges both statements: proving it at the call site
requires that `Initialize` ran, and that it ran first. Deleting the call or
moving it below `Run` turns `make prove` red. The wrapper must be local to Main
— a `Pre` on `State_Machine_Loop` would make `core` depend on the HAL, which is
what the generic formals exist to prevent.

`make prove` already runs `gnatprove -U` over the root project, so `main.adb` is
in scope today and merely skipped; the aspect brings it under the existing
`--checks-as-errors=on` gate with no Makefile change. PROOF's anchors would need
`aspect:Pre` added in `requirements/trace_chain.yaml`.

The unknown worth timeboxing is the loop instance: `core` carries
`state_machine_loop_proof` because gnatprove analyses instances, not
uninstantiated generics, and a SPARK Main gives us the *real* instance wired to
HAL actuals whose `Global`s differ from the harness's stand-ins. If that
discharges, we would be proving the deployed loop rather than a stand-in, and
the harness could be slimmed or retired — worth more than the two statements
that motivated it.

This does not help `llr_7_main.1-.3`: proof cannot check that the actual is
`Sources.Sample` specifically any more than the compiler can.
