# Hazard Analysis (informal)

> ⚠️ **Project disclaimer**: this is a hobby/learning project and has not
> undergone the kind of hazard analysis that a deployable traffic controller
> would require. The notes below are exploratory.

## Top-level hazards

| ID    | Hazard                                            | Mitigation (sketch)                              |
|-------|---------------------------------------------------|--------------------------------------------------|
| H-01  | Conflicting greens shown simultaneously           | SPARK proof of conflict-check (FR-SF-01); external MMU forces flashing-red |
| H-02  | WALK shown to pedestrian while conflicting traffic moves | SPARK proof of FR-SF-02; MMU validates ped/vehicle pairing |
| H-03  | Yellow phase too short                            | Compile-time check `T_y >= T_y_min`              |
| H-04  | Phase change with no all-red clearance            | FR-PH-05; sequencer state machine enforces gap   |
| H-05  | Software hang leaves single phase indefinitely    | IWDG (NFR-RL-02); MMU heartbeat timeout          |
| H-06  | Lamp output stuck-on (driver failure)             | Out of scope for v0.1 — see Open Questions       |
| H-07  | Pedestrian button fails closed (always pressed)   | Detect via stuck-input timer; mask the input and log |
| H-08  | Power glitch corrupts state                       | Startup self-test (NFR-RL-01); ECC RAM on H5     |

## Defenses by layer

1. **Software (single-channel, in `src/core/`)**: SPARK proofs on
   conflict-check and on safety invariants of the sequencer.
2. **Software watchdog (single-channel)**: IWDG and WWDG.
3. **External MMU (independent channel)**: separate microcontroller (or
   discrete logic) that validates the lamp-output pattern and forces
   flashing-red on any violation. Even if the main controller is
   compromised, the MMU prevents conflicting greens reaching the lamps.

The third defense is what makes a traffic controller architecturally safe.
A SPARK proof on its own is necessary but not sufficient — proofs are
about the model, not the silicon. The MMU is the physical guarantee that
no single failure (including a buggy proof harness) creates a dangerous
output.

## Out of scope for v0.1

- Lamp current monitoring (open-lamp detection).
- Loss-of-AC detection.
- Tamper detection.
- Communication failures with adjacent controllers.
