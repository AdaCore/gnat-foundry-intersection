# CLAUDE.md

Project context loaded into every Claude Code session. Keep terse; for full
detail, follow links into `docs/`.

## What this is

Four-way traffic-light controller targeting STM32H563ZI (Nucleo-H563ZI),
implemented in Ada with the **conflict-check module proven in SPARK**. Hobby
project; not for public-road deployment. See `README.md`.

## Commands

```bash
# Host build (stub HAL)
alr build

# Zephyr build for nucleo_h563zi (one-time setup: west init -l . && west update)
make                              # incremental
make pristine                     # clean rebuild
make flash                        # flash via on-board ST-LINK
make BOARD=<other_board>          # override target board

# Unit tests (host, AUnit harness via gnattest)
# One-time setup if gnattest is not installed: `alr install gnattest`
# (lands at $HOME/.alire/bin/gnattest, which is NOT on PATH automatically).
cd tests && alr -n exec -- bash -c \
  'PATH="$HOME/.alire/bin:$PATH" gnattest -P ../traffic_light.gpr'   # generate / refresh skeletons
alr -n exec -- gprbuild -P obj/development/gnattest/harness/test_driver.gpr -cargs:Ada -gnat2022
./obj/development/gnattest/harness/test_runner

# Requirements-based tests (QEMU mps2-an385; ~3 min wall)
# The QEMU build is its own Alire crate (arm-eabi cross toolchain); it
# emits bin/qemu_mps2/main at the repo root.
(cd traffic_light_qemu && alr build)
python3 tests/requirements/run.py

# SPARK proofs on the conflict-check module
alr exec -- gnatprove -P tests/proof/conflict_check_proof.gpr --level=2

# Lint
alr exec -- gnatcheck -P traffic_light.gpr

# Requirement coverage check (writes docs/requirements/traceability.md)
python3 tools/trace-check.py

# Render SRS to .docx + .pdf (gitignored output)
python3 tools/render-srs.py
```

## Architecture in one rule

`src/core/` has **no** dependency on `src/hal/`. The HAL layer (`stm32h5/`,
`host/`) implements specs the core defines. App orchestrates. This is what
makes the core host-buildable, host-testable, and SPARK-provable. Don't break
this — it's load-bearing for the proof story. See
`docs/architecture/overview.md`.

## Requirement discipline (non-negotiable)

- IDs (`FR-*`, `NFR-*`) are **stable forever**. To remove, mark obsolete:
  `~~FR-XX-NN~~ (obsolete in vX.Y — superseded by FR-XX-MM)`.
- Every requirement in `srs.md` must carry a `[verification-method]` tag
  (`[proof]`, `[test]`, `[inspect]`, or `[hw-test]`) per MR-07. See
  `docs/requirements/meta-requirements.md` for the full quality checklist
  (MR-01..MR-07) adapted from the NVIDIA SPARK Process.
- **Non-SPARK code**: annotate with coarse `-- @req <ID>[, <ID>...]`.
- **SPARK-proven code**: annotate with fine-grained tags (`@outcome`,
  `@pre`, `@type_contract`) per `docs/requirements/traceability-guide.md`.
- CI runs `tools/trace-check.py` and fails on uncovered active reqs. The
  checker also cross-validates verification methods (e.g., `[proof]` reqs
  must have SPARK code refs; `[test]` reqs must have test refs).
- Changing a requirement → open a `requirement_change` issue **first** (template at
  `.gitlab/issue_templates/requirement_change.md`). Use the
  `requirement-change-issuer` agent to draft.

## Conflict matrix

`docs/requirements/conflict-matrix.md` (human) ↔ `src/core/conflict_check.ads`
(machine) must agree. Any change touches **both**, requires an ADR if it
shifts policy, and requires re-running `gnatprove`. The matrix is symmetric
and reflexive (`Conflicts(M,M) = False`).

**Known bug** (from `IMPORT_NOTES.md`): Ped rows in the markdown matrix are
inverted vs the rationale text. Fixing this is the first scheduled change.

## Commits & branches

- Conventional Commits: `<type>(<scope>): <subject>`. Types: `feat`, `fix`,
  `docs`, `test`, `refactor`, `chore`, `ci`, `safety`. Scopes: `core`, `hal`,
  `app`, `srs`, `proof`, `ci`, `adr`.
- Branch prefixes: `feat/`, `fix/`, `docs/`, `chore/`, `refactor/`.
- Squash-merge by default. Reference FR/NFR IDs in the body.

See `CONTRIBUTING.md` for the full version.

## Subagents — when to call which

Spawn via the Agent tool. Each is one focused responsibility.

- **`spark-prover`** — drive a gnatprove iteration loop on `src/core/`.
  Use when working on contracts, ghost code, or unproved checks.
- **`requirements-tracer`** — owns `-- @req` annotations, SRS↔code drift,
  `tools/trace-check.py`. Use when adding/changing requirements or before
  any merge that touches `src/core/` or `docs/requirements/`.
- **`safety-reviewer`** — reads `docs/safety/`, reviews proposed changes
  against hazard table H-01..H-08 and the three-layer defense model. Use
  before merging anything that could shift safety properties.
- **`requirement-change-issuer`** — drafts a properly-formatted issue body
  matching the GitLab template. Use **before** editing the SRS or conflict
  matrix.
- **`documentation`** — owns README, CHANGELOG, CONTRIBUTING, ADRs,
  `docs/architecture/`, render pipelines. Does **not** edit SRS content
  (that's `requirements-tracer`) or safety docs (that's `safety-reviewer`).
- **`pipeline-fixer`** — pulls GitLab CI pipeline status / job traces via
  `glab`, diagnoses failures, and proposes fixes to `.gitlab-ci.yml` or
  source. Read-mostly; won't push, retry, or edit without confirmation.
  Use when the user asks "why did the pipeline fail?", "fix CI", or names
  a pipeline/job ID.
- **`developer`** — implements features and fixes compile errors /
  warnings under `src/`, `tests/` (the nested AUnit test crate), GPRs,
  and the Zephyr glue. Runs `alr build` / `make` and the gnattest
  harness (`obj/development/gnattest/harness/test_runner`). Hands off SPARK,
  requirements, safety, and CI work to the specialists. Use when the user
  asks to "implement X", "fix this build error", "clear the warnings", or
  picks up a backlog item.

## First-move backlog

From `IMPORT_NOTES.md`, in priority order:

1. Fix Ped-row inversion in `docs/requirements/conflict-matrix.md`; update
   `src/core/conflict_check.ads` to match. **Open a `requirement_change`
   issue first.**
2. Populate the real conflict matrix + symmetry/reflexivity ghost predicates;
   iterate `gnatprove` to discharge.
3. Implement transitions in `src/core/phase_sequencer.adb` per
   `docs/architecture/state-machine.md`.
4. ~~Replace hand-rolled `tests/unit/test_runner.adb` with AUnit or gnattest.~~
   (done — `tests/` is now a nested test crate per the `/alire` testing
   discipline, AUnit harness generated by gnattest at
   `obj/development/gnattest/harness/test_runner`. Stubs for `cmd_input` /
   `diagnostic` / `hal-host` skeletons remain as TODO; they pass by
   default via `Skeletons_Default = "pass"` in `traffic_light.gpr`'s
   `package Gnattest`. See `/gnattest` skill for the full pattern.)
5. ~~Wire up cross-toolchain: uncomment `gnat_arm_elf` in `alire.toml`~~
   (done — toolchain pinned, Zephyr build wired; bare-metal stub retired
   per ADR-0004). Still TODO: update `.gitlab-ci.yml` `build:target` job
   to invoke `make` (Zephyr).
6. Resolve PD8/PD9 ST-LINK VCP conflict in `hardware/pinout.md`.

## Zephyr build layout

Top-level: `CMakeLists.txt`, `prj.conf`, `west.yml`, `Makefile`,
`traffic_light_zephyr.gpr`. Zephyr owns the build; gprbuild emits
`libada_app.a`, gnatbind emits `ada_bind.o`, CMake links both into the
firmware via the C trampoline at `src/hal/zephyr/ada_main.c`. C shims for
inline Zephyr APIs live in `src/hal/zephyr/hal_zephyr.c` (Ada calls them as
`tlc_zephyr_*` via `pragma Import`). Cortex-M33F runtime: `light-cortex-m33f`,
hard-float ABI — keep `CONFIG_FPU=y` and the `-mfpu=fpv5-sp-d16
-mfloat-abi=hard` flags in lockstep across the GPR, the binder invocation in
CMake, and `prj.conf`. See the alire skill `zephyr.md` for the full pattern
and pitfall list.

## Pointers

- ADRs: `docs/adr/` (0001 platform, 0002 SPARK use, 0003 leading protected left, 0004 Zephyr for HAL)
- Meta-requirements: `docs/requirements/meta-requirements.md` (MR-01..MR-07 quality checklist)
- Traceability guide: `docs/requirements/traceability-guide.md` (coarse @req + fine-grained SPARK tags)
- Hazards: `docs/safety/hazard-analysis.md`
- State machine: `docs/architecture/state-machine.md`
- MR/issue templates: `.gitlab/`
