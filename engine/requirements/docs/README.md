# Requirements format

This directory documents the requirements format adopted for this project: a
YAML-structured, [EARS](ears.md)-constrained requirements.

## Layout

| Path | Contents |
| --- | --- |
| [`rules.md`](rules.md) | The meta-requirements RS.1–RS.5. |
| [`ears.md`](ears.md) | EARS notation and the requirement patterns. |
| [`glossary.md`](glossary.md) | Definitions of requirement characteristics and set properties. |
| [`examples/`](examples/) | Curated example requirement YAMLs (see below). |

## The requirement YAML model

Each YAML file is a requirement *container*; the `description` map holds the
individual numbered "shall" statements (RS.3 — exactly one shall per
statement). Each statement is uniquely identified as `<stem>.<number>` — the
file's name without extension, then the statement's `description` key (RS.2);
e.g. `hlr_Exponentiation_Int_1.2`. Top-level fields observed across the
examples:

| Field | Level | Meaning |
| --- | --- | --- |
| `visibility` | LLR | Audience/exposure of the implemented entity. The allowed values are **project-defined**; the framework fixes only the meaning of the slot, not its vocabulary. (The runtime examples here use `compiler`/`api`/`internal`.) |
| `context` | both | Givens scoping the requirement statements. |
| `description` | both | Numbered map of atomic statements (see below). |
| `preconditions` | LLR | Conditions assumed to hold (not re-checked) by the implementation. |
| `algorithm_aspects` | LLR | Informative notes on the implementation approach. |
| `rationale` | both | Why the requirement exists / why it is shaped this way. |

A *statement* is an object carrying its `text` (the shall-statement itself)
and upward/downward traces:

- an HLR statement carries exactly one of `source` (upstream references, e.g.
  clauses of a governing specification or standard) or `derived: true` (no
  upstream source; an implementation/design choice);
- an LLR statement carries `parent_req` (full `<stem>.<number>` statement IDs
  of the HLR statement(s) this one refines), `implemented_by` (the full
  expanded names of the code entities that realize this statement), and
  `verification` (how it is discharged — see below). Both downward fields are
  warnings when absent, errors under `--complete`: a complete set leaves no
  statement unimplemented or unverified.

An LLR's `verification` lists one entry per method that discharges it. For
every machine method the evidence lives artifact-side — it cites the statement
with a `--@covers` tag, so the statement itself carries only the declaration:

| Method | Meaning | Where the evidence cites it |
| --- | --- | --- |
| `test` | A unit test asserts the behavior. | `--@covers` on the first editable line of the test routine's body (the trace `TEST` layer). |
| `proof` | A formally verified contract states the property. | `--@covers` on the comment line directly above the contract aspect — before the `Post =>`, or above the `with` that opens a one-line aspect list (the `PROOF` layer). |
| `static_check` | The compiler rejects a violation (e.g. `pragma Compile_Time_Error`, a compiler-checked aspect like `No_Return`). | `--@covers` on the comment line directly above the pragma / aspect (the `STATIC` layer). |
| `review` | Human inspection only; no machine evidence is possible. | Nowhere — the entry carries `justification:` (E-SCHEMA when absent); these are the set's open review obligations. |

```yaml
verification:
  - method: test
  - method: proof
```

```ada
--@covers llr_4_controller.21
with Post => Conflicts.Safe_Faces (Outputs);
```

A statement discharged by one bare method may use the scalar shorthand
`verification: test` (≡ a single entry with no fields).

Declaring a machine method before its check exists is valid and marks an open
obligation: the trace gate reports the statement uncovered until a tagged
check cites it. Tagging checks is *opt-in*, unlike test routines: an untagged
contract or pragma is simply not evidence (most exist for engineering and
proof-plumbing reasons), so there is no UNTRACED analogue for checks — the
pressure comes from the statement side. Which constructs count for which
method is the chain's `anchors` policy (see `requirements/trace_chain.yaml`);
a tag on a construct *no* layer's anchors accept is E-TRACE-CHECK-IGNORED —
the author opted in, so the citation must not vanish silently. A tag whose
payload names nothing at all (a bare `--@covers`) is E-TRACE-CHECK-EMPTY,
reported wherever it sits: an empty payload discharges nothing on any
construct, accepted anchor or not.

> **Note**
> The gate anchors the tag to the parsed construct — deleting the pragma or
> contract deletes the citation, and the statement drops back to uncovered.
> What no tool checks is that the contract's *content* still states the
> property; that link is upheld by review of changes to the evidence.

## Curated examples

The examples are a representative subset drawn from Ada-runtime certification,
chosen to exercise the full field set and every embedded-markup kind — not a
complete feature set:

- **`exponentiation/`** — the canonical walkthrough: ubiquitous, event-driven
  (`When`), and unwanted-behavior (`If`/`Then`) statements; `source` and
  `derived` HLRs; LLRs with `algorithm_aspects` and `implemented_by`.
- **`bit_operations/`** — adds `preconditions` and Markdown tables (from
  `list-table`).
- **`floating_point_floor/`** — adds `$$` math (from `.. math::`) and a fully
  self-contained HLR↔LLR trace.

> **Note**
> Examples are verbatim excerpts (markup-converted, plus a `verification:`
> mark added per statement — `test`, the source domain's method). Trace fields
> (`parent_req`, `implemented_by`) may reference requirements or code entities
> that live outside this curated subset — e.g. `bit_operations` LLRs cite
> `hlr_BitOperations_1.1`, whose container is not included here. Likewise, the
> `visibility: compiler` values are the source domain's (Ada-runtime)
> vocabulary, not a framework-mandated value set — see the field table above.
