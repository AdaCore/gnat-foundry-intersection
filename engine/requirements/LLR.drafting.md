# Drafting LLRs

How to refine HLRs into low-level requirements (LLRs). Terse on purpose. Read
once before drafting, after `HLR.drafting.md`.

An LLR is the detailed refinement of an HLR and **the home of unobservable
mechanism**. Where the HLR models *externally observable controller behavior*
as communicating Moore machines, the LLR binds that behavior to the
**software** that realizes it — named units, subprograms, state fields,
enumeration literals, durations. The LLR is what the code is checked against:
a literal LLR ↔ code correspondence is the point of the layer.

Examples are drawn from the traffic-signal controller (its design is
`design/low-level-design.md`); substitute your own units and entities.

## Tracing

Trace chain: **CONOPS ◀──`source`── HLR ◀──`parent_req`── LLR**.

- An LLR **must not reference the CONOPS** (Rule 3). Every CONOPS obligation
  entered at the HLR layer; an LLR reaches it only by refining an HLR.
- The LLR set must be **complete relative to the HLRs** (Rule 4): every HLR
  statement is refined by at least one LLR statement. Until tooling inverts
  the traces, keep the coverage matrix by hand (`requirements/llr/coverage.md`).
- `parent_req` is a container-level list of the **HLR statement IDs** the
  file's statements refine — real `<stem>.<number>` IDs
  (e.g. `hlr_6_pedestrian.8`). A bare stem is `E-PARENT-FORMAT`; a parent
  resolving to a non-HLR file is `E-PARENT-TYPE`; one resolving to nothing is
  `{W,E}-PARENT-MISSING` (`--complete` makes it an error).
- **Interim per-statement trace + impl**: `parent_req` and `implemented_by`
  are container-level today, so each statement carries a trailing comment
  `# -> hlr_<stem>.<n>   impl: <Entity>`. Promote both to per-statement keys
  together when the schema gains them.

## Organization: mirror the code, stay standalone

LLR files mirror the **software units** — one file per package (or per
cohesive sub-unit), not one per HLR file. A unit that realizes several HLR
machines yields one LLR family whose `parent_req` spans several HLR files;
that is expected and correct.

- Naming follows the HLR convention: `llr_<N>_<name>.yaml`, filename stem =
  ID stem, `<N>` fixes read order (dependency order reads well: types first,
  integration last). Numbers are frozen once merged — mark obsolete, don't
  renumber.
- A large unit realizing several machines splits into **child files that
  extend the parent stem** (`llr_4_controller_1_vehicle` sorts right after
  `llr_4_controller`), keeping each file one cohesive story.
- Each file must be **conceptually standalone**: its `context` names the unit
  and the design section it refines onto, states the calling contract
  (`preconditions`), and explains the mechanism (`algorithm_aspects`) well
  enough to read the requirements on their own. Close to the code in
  vocabulary, independent of it in readability.
- **`context` speaks HLRs and design only — never code.** The design is the
  baseline the LLR is written against; the code does not exist yet. Cite the
  design section (`design/low-level-design.md §N`) and HLR IDs, and name design
  entities — but never a source path, an `.ads`/`.adb`, or "the package body".
- **Keep every field as terse as possible.** Drop anything the design or an
  HLR already states, and drop repeated boilerplate. Say it once, at the right
  layer, and cross-reference.

## Altitude: name the software, not the abstraction

The HLR subject is *the controller*; the LLR subject is the **software
realization** — the unit, or the machine the unit realizes, used consistently
within a file ("the vehicle sequencer shall …", "the core loop shall …",
"`Project_Outputs` shall …").

- **Guards and actions name concrete code entities**: state fields
  (`State.Vehicle`, `State.Ped (C)`, `State.Veh_Timer`), parameters
  (`Sensors.Buttons (C)`, `Outputs`, `Wait`), enumeration literals
  (`N_LEAD_YELLOW`, `PENDING_PEDESTRIAN_REQUEST`), named durations
  (`T_WALK`). Cite durations by name, never inline a number.
- **Name the assignment, not an abstraction.** Write "set `State.Ped (C)` to
  `PENDING_PEDESTRIAN_REQUEST`", never "transition to PENDING". Assignment
  verbs, not the HLR's `drive`/`hold`: "set `<field/output>` to `<v>`",
  "return `<v>`". `drive`/`hold` are HLR signal vocabulary.
- **Guards read the state field**: `While State.Ped (C) is BUFFER_INTERVAL,
  when Sensors.Buttons (C) is PRESSED, …`.

## One LLR statement → one implementing entity

Each LLR statement is implemented by **exactly one entity** — a subprogram, a
constant, or a type declaration; one entity may implement many LLR statements,
never the reverse. This fixes statement granularity: split or merge statements
until each lands on a single entity.

- Prefer entities that are **declared where a tag can anchor**: a spec
  declaration when the unit exposes it, or a named body-local subprogram when
  the design keeps the machinery local (the controller design keeps its
  sub-machines as body-local subprograms for proof-closure cohesion — those
  are legitimate anchors; the tag sits on the body declaration).
- Where one mechanism serves several HLR edges (a single output table, a
  min-of-timers wait), it is one entity implementing several LLR statements,
  each tracing to its own HLR parent — the 1:1 rule is LLR→*entity*, not
  LLR→HLR.
- Startup defaults realized as type/aggregate initialization trace the
  power-on HLR to the initializing entity (`Initialize`, or the type when the
  language carries the default).
- An HLR "for each `<instance>`" quantifier is realized as an **index type**
  and arrays over it; the per-instance stepping is the owning engine's LLR,
  not the instance's.

## Boundaries: buses, geometry, mechanism

- **The bus is the boundary.** Debounce, electrical sensing, blink
  realization, and lamp symbology live in the HAL, across the bus. LLRs
  describe the controller side: read signal values, compute, write signal
  values. HAL *contract* LLRs state what the core relies on (the delay
  semantics, the snapshot sampling) — never how a profile body implements it.
- **Geometry gets one software home.** The instance→movement relations the
  HLR leaves quantified ("the through movement parallel and adjacent…",
  "every conflicting movement") are pinned once, as named pure functions in a
  dedicated unit (`Conflicts`), and their LLR file is where the enumeration is
  stated — one statement per non-identity map, generic statements for
  identity maps. A binding is often load-bearing for safety: trace it to the
  HLR statement that *uses* the relation, and flag any provisional geometry
  for ratification rather than presenting a guess as settled.
- **Unobservable mechanism is allowed here** (it was excluded from HLRs):
  timer fields, latched decisions, edge derivation from state deltas. Put the
  reasoning that justifies the mechanism — a series clock equaling a
  superstate dwell, a decision latched at entry — in `algorithm_aspects`.

## Code annotation (`@llr`)

Once the LLR IDs are stable, the source's requirement traceability moves to
structured tags on implementing entity declarations — and the HLR references
in code go away (the HLR link lives only in `parent_req`):

```ada
--  @llr llr_4_controller_1_vehicle.7
--  @llr llr_4_controller_1_vehicle.8
procedure Advance_Vehicle (State : in out Controller_State);
```

One tag line per LLR statement, immediately above the entity's declaration
(spec declaration if visible, body declaration otherwise). Prose commentary
stays separate from the tag block. The convention is greppable
(`grep -rn "@llr" src/`) so future tooling can check LLR↔code both ways.

## EARS & format

LLRs are EARS- and RS.3-linted exactly as HLRs (`reqs validate ears`).

- Lead with an EARS keyword; **one `shall`** per statement. Ubiquitous
  (`The <unit> shall …`), State-driven (`While <guard>, …`), Complex
  (`While <guard>, when <event>, …`) for transitions. `Each <x> shall …`
  fails — recast with the unit as subject and `each` as a qualifier.
- Keep the HLR's Moore framing. Composing machines tempts the LLR toward a
  Mealy "set X when Y" that computes an output inside a transition; resist it —
  split the guard so each transition has a definite outcome.
- One YAML container per file; `description` keys are integers contiguous
  from 1. Number by implementation concern; do **not** mirror HLR numbering.
- LLR keys (schema `$defs/llr`,
  `engine/requirements/schema/requirement.schema.json`): **`parent_req`** and
  **`description`** (required); optional `context`, `preconditions`,
  `implemented_by`, `algorithm_aspects`, `rationale`, `visibility`.
  - `context` — the unit, its `design/low-level-design.md` section, and the
    HLR machines it refines; HLRs and design only, never code.
  - `implemented_by` — the set of entities this file's statements implement.
  - `preconditions` — the calling contract (e.g. "the core loop calls `Step`
    once per iteration with the current sensor snapshot").
  - `algorithm_aspects` — the mechanism/algorithm prose.
  - `rationale` — a genuinely surprising decision only; omit it when the
    choice falls out of the design or the HLRs (usually empty).
  - `visibility` — omit unless it carries information.

## Procedure

1. Read `design/low-level-design.md` (or the unit's design section) and the
   unit's spec; list its entities, state fields, and the HLR statements it
   realizes.
2. Fix the file layout: one file per unit; child files where one unit
   realizes several machines.
3. Write one LLR statement per (output row / transition / computed value /
   default), subject = the unit or its machine, naming concrete entities and
   literal assignments; guards read state fields.
4. Put mechanism reasoning in `algorithm_aspects`, the calling contract in
   `preconditions`, the entity set in `implemented_by`.
5. Trace each statement (trailing comment) to an HLR statement; list all
   parents in `parent_req`. No CONOPS references.
6. Update the hand-kept coverage matrix; every HLR statement must appear.
7. Validate:
   ```
   cd engine/requirements
   uv run reqs validate schema --complete <reqs-dir>
   uv run reqs validate ears   <reqs-dir>/llr
   ```

## Done-checklist

- [ ] Every LLR statement names one implementing entity (`impl:` comment).
- [ ] Subject is the software unit/machine; guards and actions name concrete
      entities and literal assignments (no "transition to …", no
      `drive`/`hold`).
- [ ] No CONOPS reference (Rule 3); every HLR statement refined (Rule 4,
      coverage matrix updated).
- [ ] Bus mechanism / symbology absent (HAL-side); geometry stated in its one
      software home; provisional geometry flagged.
- [ ] `parent_req` lists real HLR statement IDs; keys integers from 1;
      durations cited by name.
- [ ] `context` cites design + HLRs only (no source paths or code constructs);
      `rationale` present only for a surprising decision; every field terse.
- [ ] schema (`--complete`) and ears validation pass 0/0.
