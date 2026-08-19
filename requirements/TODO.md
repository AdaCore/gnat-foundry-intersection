# Requirements — Deferred Work

Parallelizable cleanup, not blocking. Terse by design.

## CONOPS changes

- **Specify intersection geometry.** Lane widths, lane counts, etc. are needed
  to form the basis of kinematic duration calculations.

## LLR items

- **Button/detector debounce & placement.** The HLRs name these as LLR concerns
  (`hlr_4_signals`, `hlr_5_vehicle_1_left_demand`, `hlr_6_pedestrian`
  rationales), but no LLR realizes them.
- **Kinematic duration calculations.** The current values of `T_YELLOW`,
  `T_REDCLEAR` and `T_BARRIER` are provisional. They should be derived from the
  MUTCD kinematic basis.

## Tooling / format

- **DRY the EW mirror**: a parameterized axis sub-machine instantiated twice
  (the `hlr_5_vehicle` EW block is the exact mirror of the NS block).
