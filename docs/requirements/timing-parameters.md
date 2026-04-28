# Timing Parameters

All values below are build-time constants in `src/core/timing.ads`. Any
change here must be mirrored there, and vice versa. CI verifies the two
agree.

| Parameter                        | Symbol     | Value | Notes                                          |
|----------------------------------|------------|-------|------------------------------------------------|
| Minimum green time               | `T_min_g`  | 7 s   | Per approach, prevents short cycles            |
| Maximum green time               | `T_max_g`  | 60 s  | Cap on a single phase                          |
| Yellow (amber) time              | `T_y`      | 3 s   | Fixed across all vehicle phases                |
| All-red clearance                | `T_ar`     | 2 s   | Applied between every vehicle phase change     |
| Left-turn green time             | `T_lt_g`   | 8 s   | When demanded                                  |
| Pedestrian WALK time             | `T_walk`   | 5 s   | Steady WALK indication                         |
| Pedestrian flashing DON'T WALK   | `T_fdw`    | 10 s  | Flashing clearance                             |
| Startup all-flashing-red         | `T_startup`| 5 s   | On power-up before normal operation            |
| Fault flashing-red period        | `T_fault`  | 1 s   | 0.5 s on / 0.5 s off                           |

## Tolerances

Per **NFR-PF-03**, phase timing must be accurate to within ±50 ms over any
single phase interval. The implementation uses a 1 kHz tick from a hardware
timer (TIM6 on the target, monotonic clock on host).

## Derived constraints

For pedestrian-served through phases, **FR-PD-06** implies:

```
T_through_green ≥ T_walk + T_fdw  =  5 + 10  =  15 s
```

Therefore `T_min_g` (7 s) alone is insufficient when a pedestrian phase is
being served. The phase sequencer must extend the green to at least
`T_walk + T_fdw` in that case. This is a **derived requirement** and is
captured in the test suite as `test_pedestrian_extends_min_green`.
