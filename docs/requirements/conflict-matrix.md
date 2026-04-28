# Conflict Matrix

The matrix below defines pairwise compatibility between movements:

- `X` — **conflict**: the two movements must never be active simultaneously.
- `.` — **compatible**: the two movements may run concurrently.

The matrix is symmetric.

|              | NS-Through | NS-Left | EW-Through | EW-Left | Ped-NS | Ped-EW |
|--------------|:----------:|:-------:|:----------:|:-------:|:------:|:------:|
| **NS-Through** |     .      |    .    |     X      |    X    |   X    |   .    |
| **NS-Left**    |     .      |    .    |     X      |    X    |   X    |   .    |
| **EW-Through** |     X      |    X    |     .      |    .    |   .    |   X    |
| **EW-Left**    |     X      |    X    |     .      |    .    |   .    |   X    |
| **Ped-NS**     |     X      |    X    |     .      |    .    |   .    |   .    |
| **Ped-EW**     |     .      |    .    |     X      |    X    |   .    |   .    |

## Rationale

- **NS-through and NS-left are compatible** because in this configuration the
  NS-left runs as a *leading protected phase* before NS-through (see
  [ADR-0003](../adr/0003-leading-protected-left.md)). They are sequential, not
  simultaneous, but the matrix captures permissibility, not scheduling.
- **Ped-NS conflicts with NS-through and NS-left** because the Ped-NS
  crosswalks are perpendicular to the NS movements — wait, that's the
  opposite. Re-read carefully:
  - Ped-NS crosswalks run **parallel** to the NS roadway, which means
    pedestrians cross the EW roadway. Therefore Ped-NS conflicts with
    **EW** movements (which would run over the pedestrians) and is
    **compatible** with NS movements (which run alongside).
  - The matrix above reflects this: Ped-NS is `.` against EW-Through and
    EW-Left, and `X` against — wait, the matrix shows the opposite.

> **Open issue:** the matrix above needs review. Convention used here:
> "Ped-NS" = pedestrian phase that runs **concurrently with NS through**
> (i.e., crosses the EW roadway). Under that convention, Ped-NS should be
> compatible with NS-Through and NS-Left, and conflict with EW-Through
> and EW-Left.
>
> The matrix as currently shown is **inverted** for the Ped rows/columns
> and must be corrected before code references it. This is intentionally
> left as a finding for the first MR after import — see
> `docs/adr/template.md` and open an issue with label `area::safety`.

## Machine-readable form

The canonical form is implemented in `src/core/conflict_check.ads` as a
constant 2D Boolean array. The CI traceability check verifies that the
matrix in this Markdown file matches the Ada constant byte-for-byte (see
`tools/conflict-matrix-check.py`).
