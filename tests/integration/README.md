# Integration tests

Reserved for in-process Ada scenario harnesses (no real binary, no
emulator) — currently empty. The system-level scenarios this directory
was originally sketched for now live in
[`../requirements/`](../requirements/), which drives the actual
`bin/qemu_zynq7000/traffic_light` binary under `qemu-system-arm` and asserts
against the SRS:

- `test_no_demand_idle` →
  `tests/requirements/test_fr_ph.py::test_fr_ph_02_skip_*`
- `test_pedestrian_extends_min_green` →
  `tests/requirements/test_fr_pd.py::test_fr_pd_03_06_*`
- `test_all_red_clearance` →
  `tests/requirements/test_fr_ph.py::test_fr_ph_05_06_*`
- `test_conflict_invariant` →
  `tests/requirements/test_fr_sf.py::test_fr_sf_01_02_*` (wire-level)
  + SPARK proof of `conflict_check` via `gnatprove -P traffic_light.gpr` (formal proof)
