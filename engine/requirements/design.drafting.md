# Drafting the design

How to write the low-level design (`design/low-level-design.md`) — the document
the LLRs are drafted against. Terse on purpose. Read once before writing the
design, after `HLR.drafting.md` and before `LLR.drafting.md`.

Examples are drawn from the traffic-signal controller; substitute your own units
and entities.

## Where the design sits

Trace chain: **CONOPS ◀── HLR ◀── LLR**. The design is **not** in it. It sits
beside the high-level design (`architecture.md` — project structure and the big
concepts) and above the source, and it is the **baseline the LLRs are written
against**: it names the entities the LLRs refine onto (their `implemented_by`
and `@llr` tags).

- The CONOPS and HLRs are **normative** for *what* the controller does. The
  design **plans** *how* the software is organized to realize it — it prescribes
  the code's structure but invents no behavior and carries no authority over it.
- It is the **planned** decomposition — what the units shall be. The code is
  written to realize the design, not the design extracted from the code.

## What a design is — the altitude rule

The design is the **structural surface**: what units, types, and subprograms the
software shall have, and what each shall be **responsible for**. That is the whole
of it.

- **The design answers "what shall the entities be, and what shall each be
  responsible for?"** — a noun and a role (`Both_Duration` — computes the
  both-through dwell).
- **The LLR answers "what shall each entity do?"** — the verb: the value, the
  formula, the guard, the order. That is behavior, written *against* the design's
  named entities, and it is the LLR's job, not the design's.

**The lift test.** If a sentence could be lifted verbatim into an LLR as "The X
shall …", it is at LLR altitude — *reference* it, do not restate it. "`States`
defines the type `Vehicle_Face`" is design; "`Vehicle_Face` has the literals RED,
YELLOW, …" is the LLR (`llr_1_states`). Cite the LLR; never reproduce its content.

## Name entities, not values

Name the **declared entities** — types, subprograms, constants, the state record
— because those are what an `@llr` tag anchors to and an LLR's `implemented_by`
lists. Do **not** enumerate what lives *inside* them:

- **Values are not design.** Signal literals, index literals, enumeration members,
  duration valuations — you tag `Vehicle_Face`, never `RED`. Value sets are fixed
  by the HLR (the signals and timing files) and restated by the LLR; the design
  points at them.
- **Counts and structure, sparingly.** A count intrinsic to the domain (the eight
  vehicle movements) may orient a reader; a count that is an artifact of a
  decomposition the LLR enumerates (the twenty sequencer states) should not.

## Keep decisions of structure; drop mechanism, rationale, and proof

The one thing beyond bare entities that the design carries is the **decomposition
decisions** — the carving the signatures don't show. State each as a decision, in
a sentence:

- **IN:** unit boundaries (one package for the tightly-coupled machines); state
  ownership (all state in one record, threaded `in out`, no globals); dependency
  direction (why `Conflicts` is stand-alone, not a child); a representation choice
  (flatten a superstate into a contiguous range so a subtype can name it; declare
  states in cycle order). Naming the subtype and the decision is design; listing
  the members is not.
- **OUT → LLR:** computation (formulae, how a value is derived), transition
  sequences, guards, step ordering, and **unobservable mechanism** — latched
  decisions, series clocks, edge-from-delta derivation. These are the LLR's
  `algorithm_aspects`, which claim them by name.
- **OUT → its own document:** the **proof strategy** (why an obligation
  discharges, by-construction arguments). It is orthogonal to writing the LLRs;
  give it a separate file (`proof.md`), not a section here.

## Register

Tight and descriptive. Per entity: the name and a one-line responsibility.

- Drop **moment-in-time narration** ("in this synchronous revision", "the planned
  latch"), **planned-future asides**, and **rationale prose**.
- Keep **coarse HLR cross-references** where they anchor a decision
  (`hlr_0_safety.2`) — the design is a design-level cross-reference. Drop
  **fine-grained citations** (`.2–.11`, `.3/.6/.14`); those are the LLR's.
- Show a **state record or a loop skeleton as code** when that is the densest way
  to convey a decomposition — but comment fields with roles, not values.

## Organization

- **A unit map first** — one row per unit (project, unit, files, role). Every
  unit the design defines appears here, including proof-only harnesses.
- **One short section per unit**, in dependency order (leaf types first,
  integration last), each naming the unit's entities with a responsibility each.
  Body-local subprograms are legitimate to name — they are `@llr` anchors — but
  with a responsibility, never their behavior.
- Mirror the **software units**, not the HLR machines: one unit may realize
  several machines (that is the LLR family's shape too).

## Consistency

Before it can be a baseline the design must be internally sound. There is no
linter — check by hand:

- Every unit in the map has a home (a section, or a stated other-document home).
- Every cross-reference — a `§N`, a file path, an entity name — resolves.
- Counts and names agree with the HLRs and the informative render
  (`requirements/state-machines.md`) — no "five machines" above a list of four.

## Procedure

1. Decide the unit decomposition from the HLR machines and the concepts in
   `architecture.md`; write the unit map.
2. For each unit, name the entities it shall declare (types, subprograms, the
   state record) and give each a one-line responsibility.
3. Record the decomposition decisions the signatures won't show; apply the lift
   test to cut anything that is really an LLR statement.
4. Move proof strategy to its own document.
5. Read it through: resolve every reference; reconcile counts and names with the
   HLRs and the render.

## Done-checklist

- [ ] Every entity carries a responsibility, not a behavior (no formula, guard,
      transition sequence, or value set).
- [ ] No value sets, literals, or duration valuations — referenced to the LLR,
      not reproduced.
- [ ] Decomposition decisions stated as decisions; mechanism and proof live
      elsewhere.
- [ ] Unit map covers every unit; each has a home.
- [ ] Coarse HLR cross-refs only; every reference resolves; counts match the
      HLRs and the render.
