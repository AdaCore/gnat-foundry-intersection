# Traffic Light Controller

A four-way intersection traffic light controller with dedicated left-turn
phases and concurrent pedestrian crossings, targeting the STM32H563ZI
(Nucleo-H563ZI development board), implemented in Ada with SPARK-proven
conflict-detection logic.

This is a learning / hobby project. **It is not intended for deployment on
public roads** and has not been certified to any traffic-control or
functional-safety standard.

## Status

Early scaffold — see [`docs/requirements/srs.md`](docs/requirements/srs.md)
for the specification and [`CHANGELOG.md`](CHANGELOG.md) for progress.

## Quick start

```bash
# Host build (runs on your laptop, uses stub HAL)
alr build

# Run unit tests
alr exec -- gprbuild -P tests/unit/unit_tests.gpr
./tests/unit/obj/test_runner

# Run SPARK proofs on the conflict-check module
alr exec -- gnatprove -P tests/proof/conflict_check_proof.gpr --level=2

# Build firmware for the Nucleo-H563ZI via Zephyr
# (one-time: west init -l . && west update)
make
```

## Repository layout

| Path | Contents |
|------|----------|
| `docs/requirements/` | Software Requirements Specification (Markdown source) |
| `docs/architecture/` | Architecture overview, state machine, diagrams |
| `docs/safety/` | Hazard analysis and safety case |
| `docs/adr/` | Architecture Decision Records |
| `src/core/` | Pure logic — host-buildable, SPARK-targetable |
| `src/hal/zephyr/` | Zephyr-backed HAL (STM32H5 and other Zephyr-supported boards) |
| `src/hal/host/` | Stub HAL for desktop simulation and unit tests |
| `src/app/` | Top-level application, diagnostics |
| `tests/unit/` | Unit tests (host-runnable) |
| `tests/integration/` | Phase-sequence scenario tests |
| `tests/proof/` | SPARK proof configuration |
| `tools/` | Traceability check, doc rendering, helpers |
| `hardware/` | Pinout, schematics, bill of materials |

## Documentation

- **Specification**: [`docs/requirements/srs.md`](docs/requirements/srs.md)
- **Conflict matrix**: [`docs/requirements/conflict-matrix.md`](docs/requirements/conflict-matrix.md)
- **Architecture**: [`docs/architecture/overview.md`](docs/architecture/overview.md)
- **Decisions**: [`docs/adr/`](docs/adr/)

The SRS is rendered to `.docx` and PDF by CI on every push to `main` and
attached as artifacts to tagged releases.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). All changes go through merge
requests; CI must be green; requirement IDs are stable forever (never
reused, even if deleted).

## License

See [`LICENSE`](LICENSE).
