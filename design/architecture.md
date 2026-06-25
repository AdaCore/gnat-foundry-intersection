# Code architecture

## Overview

The project is structured around the following key concepts.

The main controller is a state machine that implements the traffic light logic.

The program is a main loop which takes the state machine through its stages:

- poll the external sources (sensors that indicate cars wanting a left turn, or pedestrians wanting to cross)
- compute the next state of the traffic light
- update the traffic light outputs
- wait the delay required by the current state

The main loop reads the data from the external sources via _source data buses_, one for each source, that hold one boolean - when the value is read, it is cleared.

The main loop writes the outputs to the traffic light via a _display data bus_, writing to it an object which contains the state of the traffic lights.

## Project structure

The code is organised into .gpr projects, as follows:

- `src/types.gpr`: The type definitions for the project, including the data bus types.
  - `src/types/states.ads`: the definition of the traffic light states, and any constants used by the state machine
  - `src/types/source_buses.ads`: the definition of the source data bus types
  - `src/types/display_buses.ads`: the definition of the display data bus types

- `src/core.gpr`: The core logic (SPARK target), which contains
  - `src/core/state_machine_loop.ads`: the main state machine definition, and the main loop that drives it

- `src/hal.gpr`: the hardware abstraction layer (HAL) for the target platform, which contains
  - `src/hal/timings.ads`: provides a "delay_for" procedure that can be used to wait for a
    specified number of milliseconds.
  - `src/hal/sources.ads`: provides a "read_inputs" task which reads the external sources and writes
    them to the source data buses.
  - `src/hal/display.ads`: provides a "display" tasks which simulates the traffic light outputs by
     reading the output data bus and representing the state of the traffic lights to a GUI or console display.

- `src/app.gpr`: the application layer, which contains
  - `src/app/main.adb`: the main program, which initializes the HAL, the display(s), the buses, and runs the main loop.

The dependencies are as follows:

- app.gpr depends on core.gpr, hal.gpr, types.gpr
- core.gpr depends on types.gpr
- hal.gpr depends on types.gpr
- types.gpr has no dependencies

The `core.gpr` project does not depend on the `hal.gpr` project. This allows the core logic
to be tested and proven independently of the hardware abstraction layer.
The core logic does not know anything about the implementation of sources or display.

## Tasking

This implementation requires no explicit tasks, relying on the following:

- The input sources can buffer input until their buses are polled.
  For instance, if the input source is simulated by a keyboard and the bus polls+flushes the keyboard buffer.
- The runtime provides either `delay` statements or a monotonic timer that can be used to implement the required delays.
- The display bus updates its consumer as soon as it is written to.

## Timing simulation

The "delay_for" procedure in the HAL can be tuned at compile time to act faster than real-time, to ease testing and debugging.
