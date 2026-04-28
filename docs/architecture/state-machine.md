# Phase State Machine

The controller is a deterministic state machine. States correspond to phases
in the sequence; transitions are guarded by elapsed time and demand inputs.

## State diagram

```mermaid
stateDiagram-v2
    [*] --> Startup
    Startup --> NS_Left_Green : T_startup elapsed
    NS_Left_Green --> NS_Left_Yellow : T_lt_g elapsed [NS_left_demand]
    NS_Left_Green --> AllRed_1 : !NS_left_demand
    NS_Left_Yellow --> AllRed_1 : T_y elapsed
    AllRed_1 --> NS_Through_Green : T_ar elapsed
    NS_Through_Green --> NS_Through_Yellow : green_done
    NS_Through_Yellow --> AllRed_2 : T_y elapsed
    AllRed_2 --> EW_Left_Green : T_ar elapsed
    EW_Left_Green --> EW_Left_Yellow : T_lt_g elapsed [EW_left_demand]
    EW_Left_Green --> AllRed_3 : !EW_left_demand
    EW_Left_Yellow --> AllRed_3 : T_y elapsed
    AllRed_3 --> EW_Through_Green : T_ar elapsed
    EW_Through_Green --> EW_Through_Yellow : green_done
    EW_Through_Yellow --> AllRed_4 : T_y elapsed
    AllRed_4 --> NS_Left_Green : T_ar elapsed

    Startup --> Fault : self_test_failed
    NS_Left_Green --> Fault : MMU_fault
    NS_Through_Green --> Fault : MMU_fault
    EW_Left_Green --> Fault : MMU_fault
    EW_Through_Green --> Fault : MMU_fault
    Fault --> [*] : manual_reset
```

## Guards

- `green_done` is true when **both** of the following hold:
  - Elapsed time in phase ≥ `T_min_g`
  - **and** (elapsed ≥ `T_max_g`, **or** no pedestrian phase active,
    **or** elapsed ≥ `T_walk + T_fdw`).
- `<demand>` flags are read from the demand-detection module; in v0.1, vehicle
  left-turn demand is treated as always-true via build flag.

## Pedestrian sub-state machine

The pedestrian indication runs in parallel with the corresponding through
phase:

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Walk : phase_started [request_latched]
    Idle --> DontWalk : phase_started [!request_latched]
    Walk --> FlashingDontWalk : T_walk elapsed
    FlashingDontWalk --> DontWalk : T_fdw elapsed
    DontWalk --> Idle : phase_ended
```

## Invariants (proof targets)

These are the safety invariants the SPARK proof of the conflict-check module
will establish. They map to **FR-SF-01** and **FR-SF-02**.

1. **No conflicting greens/yellows**: For all pairs `(m1, m2)` such that
   `Conflict (m1, m2)` is true, never `Active (m1) and Active (m2)` where
   `Active` means showing green or yellow.
2. **No WALK during conflicting vehicle phase**: For all pedestrian phases
   `p` and movements `m` such that `Conflict (p, m)`, never
   `Walking (p) and Active (m)`.
3. **All-red gap honoured**: Between any two consecutive vehicle phases, the
   transition passes through a state where all vehicle indications are red,
   for at least `T_ar`.
