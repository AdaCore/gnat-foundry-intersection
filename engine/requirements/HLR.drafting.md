# Drafting HLRs

How to turn a CONOPS into high-level requirements (HLRs). Terse on purpose.
Read once before drafting.

This method models controller behavior as **communicating Moore state machines
written in EARS**. That framing drives everything below. (It was adopted in place
of a black-box-only style; the manifestation test in Rule 1 is where that shows.)

Examples throughout are drawn from a traffic-signal controller — `WALK`, `GREEN`,
crosswalks, left-turn demand, MUTCD/NEMA references. They illustrate the rules;
substitute your own domain's states, signals, and source standards.

## Tracing

Trace chain: **CONOPS ◀──`source`── HLR ◀──`parent_req`── LLR**.

- **CONOPS** (`conops.md`) — system-level controlling document; the normative reference.
- **HLR** — software-level model of the CONOPS elements that are controller behavior.
- **LLR** — detailed refinement of HLRs, and the home of unobservable mechanism.

### HLR drafting rules

1. An HLR states **only externally observable controller behavior** — inputs,
   outputs, and states that manifest in outputs (see the manifestation test).
   Unobservable mechanism (debounce, latch, counters) is LLR, never HLR.
2. The HLR set must (eventually) be **complete relative to CONOPS-mandated
   controller behavior** (the coverage matrix checks this).
3. An LLR **must not reference the CONOPS**. Every CONOPS obligation enters at the
   HLR layer; LLRs reach it only by refining an HLR.
4. The LLR set must be **complete relative to the HLRs**.

(Rule 1 once read "no internal states." That was wrong — the system *is* a state
machine. The fix is the manifestation test below: it admits real system states and
excludes only bookkeeping.)

## What is an HLR

Walk the CONOPS leaf by leaf. For each: *is this controller input/output behavior?*

- **Yes** → one or more HLRs.
- **No** — anything that is not input/output behavior (e.g. site geometry,
  hardware existence, display symbology/color) → a CONOPS **premise**. Never an HLR.

This mappable/premise split is also what the **coverage matrix** keys on (below):
"missing" only ever means a *mappable* leaf with no HLR.

Friction is signal: symbology evaporates (keep the value, drop the appearance); a
premise carrying a consequence keeps the consequence ("a button exists" ⇒ service
is demand-gated); a compound leaf splits into two HLRs.

## Model behavior as state machines

Where a subsystem has time-varying behavior, model it as a **Moore machine**,
written directly in EARS. This is the default for behavioral HLRs — but not every
HLR is a machine: the value definitions in the signals file and the durations in
the timing file are flat ubiquitous statements (see *State machines own order…*
below), and an isolated input→output reaction may just be a single `When`/`If`
statement. Reach for a machine when behavior depends on history; don't force one
where there's no state to track.

- **Name states and signal values; leave events in prose.** `WALK`, `GREEN`,
  `PENDING_PEDESTRIAN_REQUEST` are named; "when the button is pressed", "when the
  parallel through signal becomes `GREEN`", "when `T_WALK` has elapsed" are prose.
  Do **not** coin event tokens (`ADJ_GREEN_RISE`) — that reads as code and fights
  comprehension.
- **Manifestation test** (may a state be named?): yes iff it has a defined
  manifestation in the controller's outputs. `FAULT` (dark heads), `PENDING` (the
  request lamp), `SERVING` (WALK/FDW on the head) qualify. A debounce timer or a
  latch register does not → it is LLR.
- **Moore discipline.** Every output is a function of the current state:
  `While <state>, the controller shall drive <signal> to <VALUE>`. Transitions are
  separate: `While <state>, when <event>, the controller shall enter <state>`.
  Never hang an output on a transition.
- **Timed sub-sequences are superstates.** If an output changes *within* a state
  over time, that state is really a superstate — split it (e.g. `SERVING` →
  `WALK_INTERVAL` / `CHANGE_INTERVAL`) so every output is again constant per state.
  Hoist outputs common to all sub-states up to the superstate.
- **Modes contain the sub-machines.** Top-level modes (`NORMAL_OPERATION`,
  `FAULT`) contain the per-crosswalk / per-axis regions. A nested state implies its
  mode, so drop the `While ... NORMAL_OPERATION` guard from the sub-statements; the
  one mode-level transition to `FAULT` pre-empts the whole region.
- **Serialize to stay in Moore.** A single serialized phase ring is still a Moore
  machine even with demand- and timer-guarded transitions. *Concurrency* (a true
  NEMA dual-ring) is the only thing that forces a statechart with parallel regions;
  serialize wherever the domain allows it to avoid that.

### Use communicating machines

Decompose by the *coupling*, not a uniform template:

- **Independent, actuated things** get their own small machine: each pedestrian
  crosswalk; each approach's left-turn demand. (A demand machine may have no output
  of its own — its state manifests in whether its service runs.)
- **A tightly-coupled core** is one machine with a rich output vector: the vehicle
  phase sequencer (the movement faces are its outputs, not separate machines).
- Machines **couple by observing each other's named state/signals** — the ped
  machine reads the parallel through signal; the sequencer reads the demand
  machines. Where a coupling can become a *static timing margin* (the
  pedestrian-clearance buffer), prefer that to a runtime handshake.

**An instance (crosswalk / approach) is an index — never an actor, never a
state-holder.** The instanced machines exist per crosswalk and per approach. Keep
the *controller* as the only subject of a `shall`, and the named per-instance
*machine* as the holder of state; the instance appears only as a possessive or a
qualifier, never as the subject. A crosswalk is a region of the controller, not an
agent.

- state guard — *While a crosswalk's pedestrian control machine is in `<STATE>`*
  (not *While a crosswalk is in `<STATE>`*).
- Moore output — *the controller shall drive that crosswalk's `<signal>` to
  `<VALUE>`* (not *that crosswalk shall drive its `<signal>`*).
- transition — *the controller shall enter `<STATE>` for that crosswalk* (not
  *that crosswalk shall enter `<STATE>`*).

## Signal vocabulary

Two action verbs only:

- **drive** `<signal>` **to** `<VALUE>` — set an output for a state/transition.
- **hold** `<signal>` **at** `<VALUE>` — a maintained value ("all other faces at RED").

Rules:

- The object is always a named **`… signal`**; its value set is fixed once in the
  signals file (`hlr_4_signals`), e.g. pedestrian head ∈ `{NONE, WALK,
  FLASH_DONT_WALK, DONT_WALK}`, `NONE` = dark.
- **Guards read a signal/state directly** — `While the … signal is GREEN`,
  `While the … left-turn demand machine is in LEFT_DEMAND_PENDING`.
- Banned synonyms: `show`, `set`, `present`, `change`, `begin`, `illuminate`,
  `release`. ("Release a movement" = **drive** its signal **to** `GREEN`.)

## EARS quick reference

One `shall` per statement (RS.3). Lead with the keyword.

- **Ubiquitous** — `The <sys> shall <resp>` (Moore outputs, value definitions)
- **State-driven** — `While <state>, the <sys> shall <resp>`
- **Event-driven** — `When <trigger>, the <sys> shall <resp>`
- **Unwanted** — `If <cond>, then the <sys> shall <resp>`
- **Complex** — `While <state>, when <event>, the <sys> shall <resp>` (transitions)

Gotchas:

- The lead clause must be an EARS keyword. `Each crosswalk shall…`, `Before…`,
  `At each…` fail the linter — recast as `When`/`While`/`The controller shall…`.
- **No biconditionals** → two `While` statements.
- A state machine is **many statements** — one `While`-output per state, one
  `While…when…`-transition per edge — *not* one statement with a table inside.

## State machines own order; Timing owns durations; Signals own values

Keep these apart:

- The **state machine** fixes the *order* of states and the *events* between them
  ("when the yellow change interval has elapsed").
- A **timing file** (`hlr_Timing_1`) names and fixes every *duration* once —
  numeric where CONOPS/MUTCD mandates it (`T_WALK = 7 s`), by reference where it is
  speed-dependent (`T_YELLOW` per the MUTCD kinematic basis), bounded-not-valued
  where it is deployment policy (`T_AXIS`). The state machines cite the name.
- A **signals file** (`hlr_4_signals`) names every input and output signal and
  fixes its *value set* once; the state machines drive or read only those values
  and cite the signal by name.
- Never inline a magic number or an ad-hoc signal value in a state machine; never
  describe sequencing in the timing or signals file.

## File & format mechanics

- One YAML container per file; `description:` is a map of numbered shall-statements.
  ID = `<stem>.<number>`. Keys are **integers contiguous from 1**; a dotted
  `2.3.1` is sketch-only and fails schema — flatten before it is real.
- HLR keys: **`source`** (list of CONOPS refs) **XOR** `derived: true`; optional
  `context`, `description`, `rationale`. Schema:
  `engine/requirements/schema/requirement.schema.json`.
- **Organize by cohesion, not by verification method or micro-concern.** One state
  machine = one file (states, outputs, transitions together), even though its
  statements verify differently. The old "one requirement per file" default does
  *not* apply to a machine.
- **`source` is container-level only.** Until per-statement source exists, carry a
  per-statement CONOPS trace as a **trailing comment** (`1: |-  # CONOPS §3.6`),
  `# Derived` where there is none. Cite CONOPS by section anchor (`§3.5`).
- LLRs trace per-statement via `parent_req`; one LLR file may refine across several
  HLRs.

## Tracing & completeness

- **Backward** (every HLR → a CONOPS leaf): the per-statement trace comment. No
  statement is left untraced.
- **Derived** (no CONOPS ancestor): mark it, then **push it up** — add a CONOPS
  decision leaf and re-trace. The recurring Derived buckets are startup defaults,
  fault-latching, and flow-control policy.
- **Forward** (the coverage matrix — "are we missing anything?"): invert the
  traces and list **mappable** CONOPS leaves with no HLR. Premises are expected to
  have none. This is the operational form of Rule 2.

## Modeling heuristics

- **Anchor couplings positively to one clean predicate** — tie ped service to the
  adjacent through signal, not to a list of conflicting movements.
- **Implication, not IFF**, when one direction is false (`WALK ⇒ green`, not iff).
- **Push untraced decisions up** to a CONOPS decision leaf.
- **One machine per file**; superstates for timed sub-sequences; outputs are Moore.

## Procedure

For a behavioral subsystem (a value-definition or timing HLR skips to step 4–6 —
it has no machine):

1. List the subsystem's inputs, outputs (and value sets), and states.
2. Apply the manifestation test; draw the machine (states, Moore outputs, edges).
3. Write it in EARS: one `While`-output per state, one `While…when…` per edge;
   modes contain the regions.
4. Put durations in the timing file; cite them by name.
5. Trace each statement (comment) to a CONOPS leaf, or mark `# Derived` and push up.
6. Validate:
   ```
   cd engine/requirements
   uv run reqs validate schema <reqs-dir>/<area>
   uv run reqs validate ears   <reqs-dir>/<area>
   ```

## Done-checklist

- [ ] Every named state passes the manifestation test; mechanism is in the LLR.
- [ ] Outputs are Moore (`While <state> … drive …`); transitions are separate.
- [ ] Durations live in the timing file and are cited by name (no inline numbers).
- [ ] Every statement has a CONOPS trace comment or `# Derived` (then pushed up).
- [ ] Files organized by cohesion (one machine per file); integer keys.
- [ ] schema + ears validation pass 0/0 (sketches: ears 0; schema clean once flat).
