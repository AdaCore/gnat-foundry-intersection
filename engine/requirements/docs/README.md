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
e.g. `hlr_Exponentiation_Int_1.2`. Fields observed across the examples:

| Field | Level | Meaning |
| --- | --- | --- |
| `source` | HLR | Upstream references (e.g. clauses of a governing specification or standard). Mutually exclusive with `derived`. |
| `derived` | HLR | `True` when the requirement has no upstream source (an implementation/design choice). |
| `terminal` | HLR | `True` when the requirement is not further decomposed into lower-level requirements. |
| `parent_req` | LLR | Full statement IDs (`<stem>.<number>`) of the higher-level requirement statement(s) this one refines. |
| `visibility` | LLR | Audience/exposure of the implemented entity. The allowed values are **project-defined**; the framework fixes only the meaning of the slot, not its vocabulary. (The runtime examples here use `compiler`/`api`/`internal`.) |
| `context` | both | Givens scoping the requirement statements. |
| `description` | both | Numbered map of atomic shall-statements (the requirement body). |
| `preconditions` | LLR | Conditions assumed to hold (not re-checked) by the implementation. |
| `implemented_by` | LLR | Code entities that realize the requirement. |
| `algorithm_aspects` | LLR | Informative notes on the implementation approach. |
| `rationale` | both | Why the requirement exists / why it is shaped this way. |

## Curated examples

The examples are a representative subset drawn from Ada-runtime certification,
chosen to exercise the full field set and every embedded-markup kind — not a
complete feature set:

- **`exponentiation/`** — the canonical walkthrough: ubiquitous, event-driven
  (`When`), and unwanted-behavior (`If`/`Then`) statements; `source`,
  `derived`, and `terminal` HLRs; LLRs with `algorithm_aspects` and
  `implemented_by`.
- **`bit_operations/`** — adds `preconditions` and Markdown tables (from
  `list-table`).
- **`floating_point_floor/`** — adds `$$` math (from `.. math::`) and a fully
  self-contained HLR↔LLR trace.

> **Note**
> Examples are verbatim excerpts (markup-converted). Trace fields
> (`parent_req`, `implemented_by`) may reference requirements or code entities
> that live outside this curated subset — e.g. `bit_operations` LLRs cite
> `hlr_BitOperations_1.1`, whose container is not included here. Likewise, the
> `visibility: compiler` values are the source domain's (Ada-runtime)
> vocabulary, not a framework-mandated value set — see the field table above.
