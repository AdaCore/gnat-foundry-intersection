# Traceability Guide

> Extends the project's `-- @req` annotation discipline with the NVIDIA SPARK
> Process's fine-grained structured comment tags for SPARK-proven code.

## 1. Overview

The traceability chain is: **Requirement → Code → Test**.

Two levels of annotation granularity are used, depending on whether the code
is SPARK-proven:

| Code type          | Annotation style        | Example                                    |
|--------------------|-------------------------|--------------------------------------------|
| Non-SPARK Ada      | Coarse `-- @req FR-XX-NN` | `-- @req FR-PH-01, FR-PH-02`             |
| SPARK-proven       | Fine-grained `@outcome`, `@pre`, `@type_contract` | `-- @outcome (No_Conflicting_Pair) FR-SF-01` |
| Tests (Ada)        | Coarse `-- @req FR-XX-NN` | `-- @req FR-PH-02, FR-PH-03`             |
| Tests (Python)     | Coarse `# @req FR-XX-NN` + `@requires()` decorator | `@requires("FR-SF-01")`      |

## 2. Coarse Annotations (`@req`)

Unchanged from the existing discipline:

```ada
--  @req FR-PH-01, FR-PH-02, FR-PH-03
```

- Placed at the **package level** (top of `.ads` or `.adb`) to declare which
  requirements the compilation unit participates in.
- Placed at the **declaration level** (above a subprogram, type, or constant)
  to narrow the trace to a specific construct.
- The `tools/trace-check.py` scanner picks up both levels.

## 3. Fine-Grained SPARK Tags

For SPARK-proven code, the following structured comment tags — adapted from
the NVIDIA SPARK Process — create a tighter trace from individual contracts
to specific requirements. Each tag generates a hierarchical unique ID derived
from the Ada package and subprogram containment.

### Tag reference

| Tag               | Applies to                        | Meaning                                                   |
|--------------------|-----------------------------------|-----------------------------------------------------------|
| `@outcome`         | Postcondition (`Post`)            | Names a specific postcondition clause and traces it to a requirement. |
| `@pre`             | Precondition (`Pre`)              | Names a specific precondition clause and traces it to a requirement. |
| `@type_contract`   | Type invariant / predicate        | Names a property of a type (range, discriminant, predicate) and traces it. |
| `@rule_informal`   | Non-formal requirement in `.ads`  | A requirement that cannot be expressed as a SPARK contract; documented as structured natural language. |

### Syntax

```ada
--  @<tag> (<short-name>) <req-id>[, <req-id>...]
--  <optional natural-language description>
```

The `<short-name>` is a parenthesized identifier that becomes the leaf of
the hierarchical ID. Combined with the enclosing package and subprogram, it
forms a globally unique trace anchor:

```
Conflict_Check.Is_Safe.@outcome(No_Conflicting_Pair) → FR-SF-01
```

### When to use fine-grained vs. coarse

| Situation                                          | Use               |
|----------------------------------------------------|-------------------|
| SPARK package with formal contracts proving a requirement | Fine-grained |
| Non-SPARK package implementing a requirement       | Coarse `@req`     |
| Test file covering a requirement                   | Coarse `@req` + `@requires` |
| A requirement tagged `[proof]` in the SRS          | **Must** have at least one fine-grained tag |
| A requirement tagged `[test]` in the SRS           | **Must** have at least one test `@req` reference |
| A requirement tagged `[inspect]` in the SRS        | Code `@req` reference recommended; no test required |
| A requirement tagged `[hw-test]` in the SRS        | Code `@req` reference recommended; test requires real hardware |

## 4. Worked Example: `conflict_check.ads`

```ada
--  @type_contract (Symmetric) FR-SF-01
--  Conflicts(A, B) = Conflicts(B, A) for all A, B in Movement.
--
--  @type_contract (Irreflexive) FR-SF-01
--  Conflicts(M, M) = False for all M in Movement.

--  @outcome (No_Conflicting_Pair) FR-SF-01, FR-SF-02
--  For all M1, M2 in Movement: if Active(M1) and Active(M2) then
--  not Conflicts(M1, M2).
function Is_Safe (Active : Movement_Set) return Boolean
  with Ghost,
       Post => Is_Safe'Result =
         (for all M1 in Movement =>
            (for all M2 in Movement =>
               (if Active (M1) and Active (M2)
                then not Conflicts (M1, M2))));
```

The three tags above create the following trace anchors:

| Anchor                                                   | Requirement |
|----------------------------------------------------------|-------------|
| `Conflict_Check.@type_contract(Symmetric)`               | FR-SF-01    |
| `Conflict_Check.@type_contract(Irreflexive)`             | FR-SF-01    |
| `Conflict_Check.Is_Safe.@outcome(No_Conflicting_Pair)`   | FR-SF-01, FR-SF-02 |

## 5. Verification-Method Cross-Check

`tools/trace-check.py` enforces the following rules based on the
`[verification-method]` tag in `srs.md`:

| SRS tag      | Required trace evidence                                        |
|--------------|----------------------------------------------------------------|
| `[proof]`    | At least one `@outcome`, `@pre`, or `@type_contract` in `src/` **or** a coarse `@req` in SPARK source. |
| `[test]`     | At least one `@req` in `tests/`.                               |
| `[inspect]`  | At least one `@req` in `src/` (warning if missing, not failure). |
| `[hw-test]`  | At least one `@req` in `src/` (warning if missing, not failure). Test refs not required (can't run under QEMU). |

## 6. Planned Extensions

- **`@justify`** — for diagnostic justifications and pragma Annotate
  suppressions. Not yet needed (no suppressions in the current codebase).
- **`@doc`** — for design-documentation anchors. Deferred until the project
  adds a design-specification layer between SRS and code.
- **TRLC integration** — the NVIDIA SPARK Process uses TRLC files with
  machine-checkable schemas. If the demo graduates beyond the traffic-light
  controller, TRLC would replace the Markdown SRS + Python checker.
