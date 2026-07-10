# Code architecture

This describes the high-level architecture of the implementation: the project
structure, the bus boundary, and the core-loop concept. The low-level
design — units, state records, and the discrete-event timing model — is in
`low-level-design.md`, and the verification strategy is in `proof.md`. Edit
these as needed to maintain them in sync with the code.

## Overview

The project is structured around the following key concepts.

The main controller is a state machine that implements the traffic light logic.

The central point of the program is a core loop which takes the state machine
through its stages:

- Poll the external sources (sensors that indicate cars wanting a left turn, or pedestrians wanting to cross)
- Compute the next state of the traffic light
- Update the traffic light outputs
- Wait the delay required by the current state

## Buses

Transport of data between the main loop and the external sources (sensors) and outputs (traffic lights) is done via _data buses_. There are two types of buses:

- _source data bus_: a single bus carrying every input source. The producer (the HAL)
  samples all sources into a `States.Sensors_State` record; the consumer (the main loop)
  reads a coalescing latch that is cleared on read. Grouping every input in one record
  lets the core acknowledge input events (e.g. lighting a crosswalk's request indicator
  when its button has been pressed). Transitionally the consumer's `Read` still pulls a
  fresh sample through the producer; a future asynchronous revision will have the
  producer drive the latch directly.
- _display data bus_: which holds the state of the traffic lights.
  When the main loop writes the value, it is sent to the display (GUI or console).

Each bus goes in a single direction, from a producer to a consumer.

Buses serve as a boundary between the core loop and the hardware, and also as a boundary
for the SPARK proof. They are written that way to mimic a likely real-world
hardware implementation. In future implementation, we might add
fault detection on the buses, which would throw the system into the fault state if a
bus is not working properly.

In this implementation, buses are "reset on read" (for source buses) or "fired on
write" (for display buses) - there is no asynchrony, and all the code is executed
as part of the main loop. In a future implementation, we might add asynchrony, with
the main loop running in a task, and the buses being implemented with protected
objects. This is not the case for now.

## The core loop

The core loop reads the data from the external sources via a single _source data bus_,
whose producer samples all sources into a `States.Sensors_State` record and whose latch
is cleared when the value is read. This mimics a latch in the real world, where the
input is captured and held until it is processed, and values are coalesced (multiple
presses on the pedestrian button, or multiple cars wanting a left turn, are treated as a
single request).

The core loop is only given the "consumer" part of the bus, and does not know anything
about the implementation of the producer, which is provided by the HAL.

Similarly, the core loop writes the outputs to the traffic light via a
_display data bus_, which holds the state of the traffic lights. The core loop
is only given the "producer" part of the bus, and does not know anything about
the implementation of the consumer, which is again provided by the HAL.

The core loop is implemented as a generic subprogram, which is parameterized by:

- a "Delay_For" procedure, which is used to wait for the required time
- a procedure which reads the source data bus, sampling every external source
  (the sensors) into a `States.Sensors_State` "out" parameter and clearing the
  latch when the value is read
- a procedure which is used to write the traffic light outputs

## Project structure

The code is organised into .gpr projects, as follows:

- `src/types.gpr`: The type definitions for the project, including the data bus types.
  - `src/types/states.ads`: the definition of the traffic light states, and
  any constants used by the state machine
  - `src/types/buses.[ads|adb]`: the type definition of the source data bus,
  and the display data bus, and their implementation. These are _generic packages_,
  which are meant to be instantiated, with producers and consumers being passed
  as generic parameters.

- `src/core.gpr`: The core logic, which contains
  - `src/core/state_machine_loop.[ads|adb]`: the main state machine definition,
  and the main loop that drives it.
  - Other sources as needed for the core logic, including a replacement for the
   `conflict_check` module, which is the main proof target.

- `src/hal.gpr`: the hardware abstraction layer (HAL) for the
  target platform. The scenario variable BUILD_KIND controls whether to build the native or target
  version of the sources. Different Makefile targets are used for each variant.
  This project contains:
  - `src/hal/timings.[ads|adb]`: provides a "delay_for" procedure that can be used to
    wait for a specified number of milliseconds.
  - `src/hal/sources.[ads|adb]`: producers for the source data buses, simulating
    real-world input events.
  - `src/hal/display.[ads|adb]`: a consumer for the display data bus, representing
    the state of the traffic
    lights on a GUI or console display.

- `src/app.gpr`: the application layer, which contains
  - `src/app/main.adb`: the main entry point, which initializes the HAL, the display,
    then "wires" the buses (i.e., instantiates the bus types, connecting them to displays
    and sources provided by the HAL project), and finally calls the main loop that's
    defined in the `core` project.

The `core.gpr` and `types.gpr` projects are expected to be proven with SPARK, at
Silver level.
The `hal.gpr` and `app.gpr` projects are not expected to be proven, but they may
contain annotations necessary to support the proof of the `core.gpr` and
`types.gpr` projects.

The dependencies are as follows:

- app.gpr depends on core.gpr, hal.gpr, types.gpr
- core.gpr depends on types.gpr
- hal.gpr depends on types.gpr
- types.gpr has no dependencies

The `core.gpr` project does not depend on the `hal.gpr` project. This allows the
core logic to be tested and proven independently of the hardware abstraction layer.
The core logic does not know anything about the implementation of sources or display.

### Build scaffolding: `shared.gpr` and `traffic_light.gpr`

Two source-less support projects sit alongside the four architecture projects
above:

- `src/shared.gpr`: a source-less helper that centralises the build
  configuration reused across `types`, `core`, `hal`, and `app`. It carries the
  `BUILD_KIND` scenario variable (`native` vs `target`) and, keyed off it, the
  object/exec directories, target, runtime, and the common compiler / binder /
  linker switches. The four architecture projects `with` it so the host and
  bare-metal builds stay in step from a single definition.

- `traffic_light.gpr` (repo root): the Alire crate root for the host build. It
  *extends* `src/app.gpr` so the application sources — notably `main.adb` —
  belong to the crate root, which keeps it both the Alire crate root and the
  GNATtest driver root and pins the produced binary to the `traffic_light`
  name. The bare-metal arm-eabi cross-target build lives in its own sibling
  Alire crate, `traffic_light_qemu/`, which `with`s `../traffic_light.gpr` and
  `../src/shared.gpr` with `BUILD_KIND=target`.

### Rationale for the separation between `core.gpr` and `hal.gpr|app.gpr`

It might make more sense to have the core loop hosted as part of the `app` project, but
setting it in its own project is intentional, and structuring: it's meant as a
safeguard to ensure that the core loop never depends on the HAL, and can be proven
independently of the HAL. This comes at the price of contracted indirect
calls in the proof target. We will revisit this if we find that we cannot prove the
core loop at Silver level.

## Tasking

This implementation requires no explicit tasks, relying on the following:

- The runtime provides either `delay` statements or a monotonic timer that can be
  used to implement the required delays.
- The display bus updates its consumer as soon as it is written to.

## Timing simulation

The "delay_for" procedure in the HAL can be tuned at compile time to act faster than real-time, to ease testing and debugging.

## Command-input and diagnostic streams

TODO: This will be refined at a future revision of this document.
