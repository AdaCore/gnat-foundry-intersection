# Code architecture

This describes the current state of the architecture; edit this as
needed to maintain it in sync with the code.

## Overview

The project is structured around the following key concepts.

The main controller is a state machine that implements the traffic light logic.

The central point of the program is a core loop which takes the state machine
through its stages:

- Poll the external sources (sensors that indicate cars wanting a left turn, or pedestrians wanting to cross)
- Compute the next state of the traffic light
- Update the traffic light outputs
- Wait the fixed sampling period T_SAMPLE (100 ms, `llr_1_states.30`), so
  the loop runs at a uniform cadence and every iteration is both a sampling
  point and a potential state change

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

**Invariant — there is no direct route from the sensors to the display.** The
display is driven _only_ by the display bus (a `States.Display_State`); it never
reads the source bus or the sensors.

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

- a "Delay_For" procedure, which the loop uses to sleep the fixed sampling
  period T_SAMPLE at the end of every iteration
- a procedure which reads the source data bus, sampling every external source
  (the sensors) into a `States.Sensors_State` "out" parameter and clearing the
  latch when the value is read
- a procedure which is used to write the traffic light outputs

### The startup prologue

Before its first iteration the loop publishes the initialised state and holds
it for one sampling period (`llr_5_core_loop.5`). This sets the phase of the
whole run: iteration N's stages fall at logical time N × T_SAMPLE, so the step
that charges the last T_SAMPLE of a dwell lands on that dwell's boundary in
elapsed time rather than one sample before it, and every published frame stands
for exactly the dwell of the state it projects. Without the prologue the
initialised state — the one state no `Step` enters, so the one state not both
entered and left by a step one dwell apart — is displayed for one sampling
period less than its dwell. The publication alone does not fix that; the hold
is the operative half. The prologue also puts the first `Read_Sources` at
t = T_SAMPLE, which defers power-on fault detection by one sample.

### Sampled cadence and the acknowledgment chain

The delay slept at the end of each iteration is the **fixed sensor sampling
period T_SAMPLE = 100 ms** (`llr_1_states.30`): the loop calls `Delay_For
(States.T_Sample)` every iteration, in every mode — FAULT included, so no
special pacing value is needed there. The cadence lives in the loop; the
timers live in the controller. `Controller.Step` has no timing out-parameter:
each call accounts for exactly one T_SAMPLE, advancing every running timer
(the fields of `Controller_State`: `Veh_Timer` and the per-crosswalk
`Ped_Timer` array) by exactly
T_SAMPLE. Timed boundaries stay exact under this fixed advance because every
dwell duration is an integral multiple of T_SAMPLE (`llr_1_states.31`): a
timed transition fires on the step where its remaining dwell is <= T_SAMPLE,
which is precisely its boundary — there is no drift and no fractional
remainder to sleep. The intervening iterations are pure sampling steps that
arm freshly read inputs and re-emit the current state's unchanged Moore
outputs (so the display bus is re-written every 100 ms, mostly with unchanged
values).

This cadence is what bounds pedestrian acknowledgment (T_ACK = 0.2 s,
`hlr_3_timing.13`): a button press landing between reads is held by the
source bus's coalescing latch; the next `Read_Sources` — at most T_SAMPLE
later — delivers it; the same iteration's `Step` arms it into the pedestrian
machine; and the same iteration's `Write_Display` carries the lit request
indicator — or, where that step's boundary also serves the crosswalk, the WALK
head, `Step` emitting the state it results in. The durable record of the coalesced
inputs is the loop-local `Controller_State` itself (arming latches a seen press
as PENDING_PEDESTRIAN_REQUEST or BUFFER_INTERVAL_LATCHED) — there is no
separate loop-side input record. Inter-read coalescing stays in the source-bus
latch; across-read memory stays in the controller state.

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

- `src/proof.gpr`: proof scaffolding — code written to be analyzed and never
  run. It contains
  - `src/proof/state_machine_loop_proof.[ads|adb]`: an in-SPARK instantiation of
    the generic core loop against trivial stub formals. gnatprove analyses
    generic *instances*, so without an instance in the analysed tree the loop
    body contributes no proof obligations at all.

- `traffic_light.gpr` (repo root): the application layer, which contains
  - `src/app/main.adb`: the main entry point, which initializes the HAL, the display,
    then "wires" the buses (i.e., instantiates the bus types, connecting them to displays
    and sources provided by the HAL project), and finally calls the main loop that's
    defined in the `core` project.

The `core.gpr` and `types.gpr` projects are expected to be proven with SPARK, at
Silver level.
The `hal.gpr` project and the crate root are not expected to be proven, but they may
contain annotations necessary to support the proof of the `core.gpr` and
`types.gpr` projects.

The dependencies are as follows:

- traffic_light.gpr depends on core.gpr, hal.gpr, types.gpr
- core.gpr depends on types.gpr
- hal.gpr depends on types.gpr
- proof.gpr depends on core.gpr, types.gpr
- types.gpr has no dependencies

Nothing depends on `proof.gpr` and no unit of it is in any executable's closure;
it is a root, not a leaf. `make prove` roots gnatprove there, and `gnatprove -U`
analyses the tree it is given, so `proof.gpr`'s tree is exactly the proof scope:
`core`, `types` and the harnesses. That matches the scope the coverage run
measures (`--projects core --projects types`), so one declared verification
scope governs both forms of evidence, and the HAL simulator and the entry point
fall outside both.

Keeping the harnesses out of `core.gpr` is what keeps the coverage denominator
to code that ships: coverage of a unit nothing calls would say nothing, so a
harness sits outside the denominator rather than exempted inside it.

The `core.gpr` project does not depend on the `hal.gpr` project. This allows the
core logic to be tested and proven independently of the hardware abstraction layer.
The core logic does not know anything about the implementation of sources or display.

### Build scaffolding: `shared.gpr` and `traffic_light.gpr`

- `src/shared.gpr`: a source-less helper that centralises the build
  configuration reused across `types`, `core`, `hal`, and the crate root. It
  carries the `BUILD_KIND` scenario variable (`native` vs `target`) and, keyed
  off it, the object/exec directories, target, runtime, and the common compiler
  / binder / linker switches. Those projects `with` it so the host and
  bare-metal builds stay in step from a single definition.

- `traffic_light.gpr` (repo root): the Alire crate root for the host build, and
  the owner of the application sources in `src/app`. `for Main` may only name a
  source of the project declaring it, so owning `main.adb` here is what pins
  the produced binary to the `traffic_light` name in this project's `bin/`; it
  is also the GNATtest driver root. The bare-metal arm-eabi cross-target build
  lives in its own sibling Alire crate, `traffic_light_qemu/`, which `with`s
  `../traffic_light.gpr` and `../src/shared.gpr` with `BUILD_KIND=target`.

### Rationale for the separation between `core.gpr` and `hal.gpr`

It might make more sense to have the core loop hosted as part of the application
layer, but setting it in its own project is intentional, and structuring: it's
meant as a safeguard to ensure that the core loop never depends on the HAL, and
can be proven independently of the HAL. This comes at the price of contracted
indirect calls in the proof target. We will revisit this if we find that we
cannot prove the core loop at Silver level.

## Tasking

This implementation requires no explicit tasks, relying on the following:

- The runtime provides either `delay` statements or a monotonic timer that can be
  used to implement the required delays.
- The display bus updates its consumer as soon as it is written to.

## Timing simulation

The "delay_for" procedure in the HAL can be tuned at compile time to act faster than real-time, to ease testing and debugging.

## Command-input and diagnostic streams

The source bus's producer is realized per profile (see §"Project structure",
`src/hal/sources`). On the native/host profile the producer is a **keyboard
simulation** of the physical sensors: the terminal stands in for the sensor
harness. Keys `1 2 3 4` raise a pedestrian request on a crosswalk (by
`States.Crosswalk` in enum order — North_Side, South_Side, East_Side, West_Side)
and keys `n s e w` raise a left-turn request on an approach (North, South, East,
West). Each poll drains the terminal input queue **non-blocking** (via
`Ada.Text_IO.Get_Immediate` looping while input is available) and folds the keys
seen since the previous poll into the `States.Sensors_State` snapshot it returns;
keys not seen this poll read as inactive, and repeated presses of the same key
within one inter-poll interval coalesce to a single active reading. Unrecognized
keys are ignored. This is the host stand-in for the honest pass-through producer
described in §Buses — the producer owns the buffering/consume-on-read guarantee,
and the source bus itself adds no buffering.

Still deferred (TODO):

- The `qemu_zynq7000` target profile keeps its own hardware edge-capture
  realization of the same producer; that body is a separate target concern and
  is not the keyboard simulation.
- A target-side UART command path (and any diagnostic output stream) is not yet
  defined and will be refined at a future revision of this document.
