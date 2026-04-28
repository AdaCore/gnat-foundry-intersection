# Integration tests

Phase-sequence scenario tests that run the sequencer over many ticks and
verify the lamp/walk output trace matches expected sequences.

To be implemented. Suggested scenarios:

- `test_no_demand_idle`: with no left-turn demand and no pedestrian
  requests, the sequencer should still cycle through through-phases
  (skipping lefts).
- `test_pedestrian_extends_min_green`: with a pedestrian request,
  the through phase must run for at least `T_walk + T_fdw`.
- `test_all_red_clearance`: every vehicle phase change goes through an
  all-red interval of at least `T_ar`.
- `test_conflict_invariant`: at every tick, `Conflict_Check.Is_Safe`
  holds.

Each test should be a small Ada program that constructs an initial state,
ticks the sequencer N times, and asserts properties of the output trace.
