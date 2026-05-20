# Diagnostic Wire Protocol

The controller exposes two UART channels carrying line-oriented ASCII text:

- **UART0** — diagnostic output (controller → host visualizer)
- **UART1** — command input (host visualizer → controller)

Both channels run at 115200 8N1 per [`FR-UI-01`](srs.md). Lines are
LF-terminated (0x0A); no fixed maximum length but a 256-byte ceiling is
recommended for buffer sizing.

## 1. Diagnostic output (UART0)

### 1.1 Phase-transition record

Emitted on every transition of the phase sequencer (per
[`FR-UI-03`](srs.md)):

```
PH=<phase> T=<ms> PED=NS:<req|clr>,EW:<req|clr> LT=NS:<0|1>,EW:<0|1> FAULT=<code>
```

| Field    | Meaning                                                          |
|----------|------------------------------------------------------------------|
| `PH=`    | Current phase token (see § 1.3)                                  |
| `T=`     | Milliseconds elapsed in current phase (decimal, no leading zero) |
| `PED=`   | Pedestrian request state per axis (see § 1.4)                    |
| `LT=`    | Left-turn demand state per axis (`1` = demanded)                 |
| `FAULT=` | Most recent fault code; `0` = no fault                           |

Fields appear in the order shown, separated by single spaces.

### 1.2 Heartbeat record

Emitted at no less than 1 Hz independent of phase transitions (per
[`FR-UI-04`](srs.md)). Provides a liveness signal and a clock-interpolation
reference for the visualizer between transitions:

```
HB T=<ms>
```

`T=` is milliseconds since startup (monotonic, decimal).

**This is distinct from the MMU safety heartbeat** ([`FR-SF-06`](srs.md)),
which is a GPIO pulse on a separate channel.

### 1.3 Phase token set

Canonical phase names, in nominal cycle order:

```
STARTUP_FLASH
NS_LT_GREEN        NS_LT_YELLOW        ALL_RED_1
NS_THROUGH_GREEN   NS_THROUGH_YELLOW   ALL_RED_2
EW_LT_GREEN        EW_LT_YELLOW        ALL_RED_3
EW_THROUGH_GREEN   EW_THROUGH_YELLOW   ALL_RED_4
FAULT
```

These are the strings emitted in the `PH=` field. They do not have to
match the internal Ada `Phase_Sequencer.Phase_Id` enum spelling
one-to-one; the mapping is implemented in `Diagnostic.Phase_Name`
(`src/core/diagnostic.adb`).

### 1.4 Pedestrian axis aggregation

The Ada `Pedestrian.Crosswalk` enum identifies four physical corners
(`NS_North`, `NS_South`, `EW_East`, `EW_West`). The wire field `PED=`
aggregates these into the two ped-phase axes:

| Wire token | Aggregates                                                    |
|------------|---------------------------------------------------------------|
| `PED=NS:`  | `req` if Ped-NS phase has any latched request, else `clr`     |
| `PED=EW:`  | `req` if Ped-EW phase has any latched request, else `clr`     |

The "Ped-NS phase" runs concurrently with NS-through (per
[`srs.md` § 2.3](srs.md)) and covers the crosswalks parallel to the NS
roadway.

> **Open issue:** the exact mapping from `Crosswalk` enum values to
> ped-phase axes depends on the resolution of the Ped-row inversion in
> [`conflict-matrix.md`](conflict-matrix.md). Both files must be
> updated consistently when that question is resolved.

## 2. Command input (UART1)

The visualizer (or any host tool) drives state changes into the
controller by writing newline-terminated commands on UART1, per
[`FR-UI-05`](srs.md):

| Form                          | Effect                                            |
|-------------------------------|---------------------------------------------------|
| `PRESS PED NE\|NW\|SE\|SW`    | Inject a debounced ped-button press ([`FR-PD-01`](srs.md)) |
| `SET LT NS\|EW 0\|1`          | Set left-turn demand for the named axis ([`FR-PH-02`](srs.md)) |
| `FAULT 1\|0`                  | Inject / clear MMU fault input ([`FR-SF-07`](srs.md))       |
| `RESET`                       | Trigger manual reset ([`FR-UI-02`](srs.md))                 |

Tokens are case-sensitive. Unknown commands shall be silently discarded
(no acknowledgement, no error reply).

### 2.1 Corner naming

The `PRESS PED` form uses compass-corner names (`NE`, `NW`, `SE`, `SW`).
The mapping from compass corner to the Ada `Pedestrian.Crosswalk` enum
(`NS_North`, `NS_South`, `EW_East`, `EW_West`) is implementation-defined
and lives in the command-dispatch layer (to be added).

Note that the diag-out `PED=` field uses axis-level aggregation (`NS`,
`EW`) while cmd-in `PRESS PED` is per-corner. This asymmetry is
intentional: the visualizer renders four physical corners but the
controller schedules in two axes.

## 3. Implementation

- Ada emitter: `src/core/diagnostic.{ads,adb}`. Procedures carry
  `-- @req` annotations pointing at the requirement they implement.
- Visualizer parser: `gnat-agents/visualizer/` (separate repo). Parser
  unit tests round-trip every line shape defined above.

## 4. Stability

The token set in § 1.3 and the line grammars in § 1.1, § 1.2, and § 2 are
the public wire interface. Changes require a coordinated update on both
sides of the channel. Adding new line forms (without altering existing
ones) is a minor revision; renaming or removing existing forms is a
breaking change.
