# Requirements — Deferred Work

Items intentionally deferred out of the current HLR pass. The HLRs in `hlr/` are
complete and well-formed enough to anchor design; everything below is
parallelizable cleanup or downstream (CONOPS / LLR) work. Terse by design.

## CONOPS changes

- **Push the 8 Derived HLR statements up to CONOPS decision leaves** (see the
  orphan table in `coverage.md`). Four new leaves absorb them:
  - **Power-on state** (under §5) — `1_modes.2`, `5_vehicle.47`,
    `5_vehicle_1_left_demand.2`, `6_pedestrian.2`. NB: `5_vehicle.47` is *not* a free
    default — its value is fixed by the initialization item below (MUTCD 4G.04.01.B).
- **Specify controller initialization, tied to MUTCD 4G.04.01.B.** The CONOPS has no
  initialization clause. Because fault recovery is a power cycle (§6.3,
  `1_modes.4`), power-on *is* the flashing-to-steady transition MUTCD
  4G.04.01.B governs: the change from flashing red "shall be made by changing the
  flashing red indications to steady red indications followed by appropriate green
  indications to begin the steady mode cycle," and that green must begin the common
  major-street green (both directions) or, absent one, the major-street
  major-movement green. Add a CONOPS initialization leaf (under §5, cross-referencing
  §6.3 and citing MUTCD 4G.04.01.B) fixing: power-on enters NORMAL_OPERATION
  (`1_modes.2`) with the vehicle sequencer in the steady all-red barrier that leads
  into NS (major-street) service — realized as `5_vehicle.47` entering
  EW_BARRIER_ALLRED. Re-trace `5_vehicle.47` to this leaf; it then ceases to be
  Derived.
  - *Decision for the CONOPS author:* 4G.04.01.B's primary clause prefers the common
    major-street green (`NS_BOTH_THROUGH`). Entering EW_BARRIER_ALLRED lets
    transition 12 serve the Northbound left lead (`N_LEAD`) first when its demand is
    pending — defensible under the "major traffic movement on the major street"
    alternative clause, but confirm this reading is acceptable rather than forcing
    `NS_BOTH_THROUGH` as the first green.
  - **Fault-state request lamps** (under §6) — `2_fault.3`.
  - **Left-turn / through time allocation** (under §2) — `3_timing.8`
    (both-through residual `T_BOTH`), `3_timing.12` (both-through floor `T_BOTH_MIN`),
    and `3_timing.9` (left ≤ ½ T_AXIS).
- **Reword §3.3** onto the indication / output-signal level (the §3.3 wording note in
  D1): "each head continuously presents one of its defined indications … and is
  dark only in FAULT." The HLR trace already relies on this reading; only the
  CONOPS prose needs the fix.

## LLR items

- **Write the LLRs** against the flat HLR IDs (none exist yet).
- **Realize FAULT pre-emption in the LLRs.** The HLRs drop the
  `While ... NORMAL_OPERATION` guard from every sub-machine statement (a nested
  state implies its mode) and state the pre-emption only in prose: entering FAULT
  (`1_modes.3`) must abandon every `NORMAL_OPERATION` sub-state so the `2_fault`
  outputs override the sub-machine outputs, and the two top-level modes are
  mutually exclusive (exactly one active). EARS cannot carry this without
  repeating the mode guard on every statement, so the LLR/design layer must make
  it explicit — the HLRs rely on it being true.
- **Discharge the pedestrian-conflict invariant `0_safety.1`** — CONOPS §3.4 and
  §3.5, WALK/FDW/BUFFER ⇒ conflicting perpendicular movement held RED (the clearance
  buffer is now folded into `SERVING_PEDESTRIAN_REQUEST`, `6_pedestrian.14-18`, so
  the invariant covers the §3.5 "≥ 2 s before release" window). Treat as **one
  coupled work item**; the obligation is not satisfied until all four land:
  1. *Invariant* — `hlr_0_safety.1` (done; the obligation, in our states).
  2. *Binding* — the crosswalk → conflicting-movement / adjacent-through enumeration
     (the same binding as the bullet below); the invariant and `3_timing.10`
     quantify over it.
  3. *Discharge* — show the static margin `3_timing.10` holds for the chosen
     durations: every conflicting movement RED for ≥ `T_WALK + T_FDW + T_BUFFER`
     (16 s) after its adjacent through goes GREEN, across every binding case
     (late-greening through vs perpendicular release; lagging left vs the opposite
     crosswalk), under the no-gap-out premise `3_timing.11`. A satisfying set exists
     (e.g. `T_YELLOW=4`, `T_REDCLEAR=2`, `T_BARRIER=2`, `T_LEAD=T_LAG≤6`,
     `T_BOTH_MIN=10`, `T_AXIS=40 s`) — pick one and verify, don't assume.
  4. *Fallback* — there is **no** fallback requirement if the inequality proves
     unsatisfiable. If the margin cannot be shown, add a runtime-coupling
     requirement (sequencer holds conflicting movements RED while it observes the
     crosswalk in `SERVING_PEDESTRIAN_REQUEST`) and discharge `0_safety.1` that way.
  The static margin is the **sole** current discharge of a MUTCD Standard, so this
  item gates §3.4's safety claim entirely.
- **Discharge the vehicle-conflict invariant `0_safety.2`** — CONOPS §2.8, no two
  conflicting vehicle face outputs driven non-RED at once. In the current serialized
  Moore design this is discharged *by construction* (exactly one `5_vehicle` output
  row active, each row conflict-free by inspection, with all-red clearance at the
  yellow-then-red terminations and barrier/clear states). Two pieces are still
  deferred: (1) *Binding* — enumerate the vehicle-face conflict matrix the invariant
  quantifies over (the analogue of the crosswalk → movement binding for `0_safety.1`);
  (2) *Check* — verify "no reachable state releases a conflicting pair" against that
  matrix. Note the premise (`0_safety.2` rationale) that the by-construction argument
  holds only while the sequencer stays serialized Moore: under any future concurrent /
  dual-ring (NEMA) design this invariant becomes load-bearing rather than emergent.
- **Value the deferred durations**: kinematic (`T_YELLOW`, `T_REDCLEAR`,
  `T_BARRIER`) and policy (`T_AXIS`, `T_LEAD`, `T_LAG`, `T_BOTH`, `T_BOTH_MIN`).
  The HLR leaves these bounded-not-valued by design.
- **Crosswalk → movement bindings**: enumerate, per crosswalk (×4), its
  "adjacent / parallel through" and its set of "conflicting movements" — the
  relations `0_safety.1`, `3_timing.10`, and `6_pedestrian.8` quantify over. (This
  is item 2 of the `0_safety.1` coupled work item above.)
- **Mechanism** (already named as LLR concerns): button/detector debounce &
  placement, request latch, FLASH_DONT_WALK blink realization. The buffer-press
  latch *behaviour* is fixed at the HLR (`6_pedestrian.15-18`: a press during the
  clearance buffer is held and served the next cycle); only its *realization*
  (debounce, electrical hold) is the LLR concern here.
- **Reconcile legacy `timing.ads`** 5/10 s vs CONOPS 7/7 s (`T_WALK`/`T_FDW`).

## Tooling / format

- **Forward-coverage `reqs` subcommand**: invert traces, list mappable CONOPS
  leaves with no covering HLR (operationalizes `coverage.md`).
- **DRY the EW mirror**: a parameterized axis sub-machine instantiated twice
  (the `hlr_5_vehicle` EW block is the exact mirror of the NS block).
