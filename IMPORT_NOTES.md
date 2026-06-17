# Import notes (read this first)

This is the initial scaffold for the traffic-light-controller project. It is
designed to be imported into a fresh GitLab repository and then iterated on
in Claude Code (CLI).

## Importing into GitLab

```bash
# 1. Create an empty project on GitLab (no README, no .gitignore — we have ours).
#    Note the SSH or HTTPS URL.

# 2. Initialize and push:
unzip traffic-light-controller-scaffold.zip
cd traffic-light-controller
git init -b main
git add .
git commit -m "chore: initial repository scaffold"
git remote add origin git@gitlab.com:<you>/traffic-light-controller.git
git push -u origin main
```

## First things to do in Claude Code

The scaffold has intentional gaps and one known issue. Highest-value first
moves:

1. **Fix the conflict matrix (in `docs/requirements/conflict-matrix.md`).**
   The matrix as written has the Ped rows inverted relative to the rationale
   text. Resolve which convention you want and update the table + the Ada
   constant in `src/core/conflict_check.ads` to match. Open an issue using
   the `requirement_change` template before changing the matrix.

2. **Populate the conflict matrix in Ada.** Replace the placeholder
   `(others => (others => False))` in `conflict_check.ads` with the real
   matrix and add the symmetry/reflexivity ghost predicates. Run
   `gnatprove` and iterate until the proof obligations discharge.

3. **Implement the sequencer transitions** in `phase_sequencer.adb` per the
   state diagram in `docs/architecture/state-machine.md`.

4. **Replace the test runner with AUnit or gnattest.** The current
   `test_runner.adb` is a hand-rolled placeholder.

5. **Wire up the cross-toolchain.** Uncomment `gnat_arm_elf` in
   `alire.toml`, then update `.gitlab-ci.yml`'s `build:target` job.

6. ~~**Resolve PD8/PD9 conflict in `hardware/pinout.md`.**~~ Obsolete —
   ST-LINK/STM32-specific. The project now targets Zynq-7000 (see retired
   ADR 0001); `hardware/pinout.md` needs a separate Zynq pinout pass.

## Things deliberately left out

- No `gnatcheck` rules file yet — add `gnat.adc` or a `coding-style.txt`
  once you have a preference.
- No `Dockerfile` for CI — the `.gitlab-ci.yml` uses Debian + apt-get;
  swap to an Alire image when one stabilizes.
- No real proof obligations on the conflict-check module — the spec is
  scaffolded but the matrix is empty.
- No AUnit / gnattest harness — placeholder test runner only.
- No real PCB / shield — only a paper pinout.

## What's already wired

- Alire crate manifest (`alire.toml`).
- GPRbuild project with host/target profile selection.
- Layered source tree with an HAL stub for host builds.
- SRS in Markdown with stable requirement IDs.
- Traceability check (`tools/trace-check.py`) that scans `-- @req`
  annotations and produces `docs/requirements/traceability.md`.
- Pandoc-based renderer for SRS → docx/PDF.
- GitLab CI pipeline skeleton (lint, build, test, prove, docs, package).
- Issue and MR templates.
- ADRs 0001–0003 covering the platform, SPARK use, and phasing decision.
- Hazard analysis and safety-case stubs.

## Delete this file before the first push (optional)

Once you've imported and read this, you can either remove `IMPORT_NOTES.md`
or repurpose it as a "Getting started" doc.
