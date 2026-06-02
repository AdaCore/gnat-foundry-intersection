# Meta-Requirements: Quality Attributes for Requirements

> Adapted from the [NVIDIA SPARK Process](https://github.com/NVIDIA/spark-process)
> requirement-quality discipline. Lifecycle states (proposed / reviewed /
> approved / confirmed) are **not** adopted; see the lightweight requirement
> intake flow in Section 3 instead.

## 1. Quality Checklist

Every requirement in `srs.md` **must** satisfy all seven attributes below.
The `requirements-tracer` agent checks MR-01, MR-02, MR-05, and MR-07
automatically; the rest are verified by inspection during review.

| ID     | Attribute            | Rule                                                                                                          | Check |
|--------|----------------------|---------------------------------------------------------------------------------------------------------------|-------|
| MR-01  | Atomic               | The requirement cannot be decomposed into two or more independently-verifiable sub-requirements.               | review |
| MR-02  | Implementation-free  | The requirement states **what**, not **how**. No technology, component, register, bus, or protocol names unless the requirement *is* the interface specification. | review |
| MR-03  | Unambiguous          | The requirement admits exactly one interpretation. Quantifiers are explicit ("all", "each", "at least one"); temporal relationships are clear ("before", "after", "while", "on"). | review |
| MR-04  | Consistent           | The requirement does not contradict any other requirement in the SRS.                                          | review |
| MR-05  | Verifiable           | There exists a concrete procedure (proof obligation, test scenario, inspection criterion) that can determine pass/fail. | auto  |
| MR-06  | Comprehensible       | A qualified reviewer can understand the requirement without reading other requirements or implementation code. | review |
| MR-07  | Classified           | The requirement carries a `[verification-method]` tag: one of `[proof]`, `[test]`, `[inspect]`, or `[hw-test]`. | auto  |

### Verification-method tags

| Tag         | Meaning                                                                 |
|-------------|-------------------------------------------------------------------------|
| `[proof]`   | Verified by SPARK formal proof (GNATprove).                             |
| `[test]`    | Verified by automated test (unit, integration, or requirements-based).  |
| `[inspect]` | Verified by manual inspection or architectural review.                  |
| `[hw-test]` | Verified by test that requires real hardware (cannot run under QEMU).   |

A single requirement **must not** carry more than one tag. If a requirement
needs both proof and testing, split it into a formal sub-requirement
(tagged `[proof]`) and a non-formal sub-requirement (tagged `[test]`).

## 2. Agent-Checkable Form (YAML)

The `requirements-tracer` agent validates requirements against the following
schema. Human reviewers use the table above; the YAML form exists so the
agent can run the same checks mechanically.

```yaml
meta_requirements:
  - id: MR-01
    name: atomic
    check: review
    rule: >
      The requirement cannot be decomposed into two or more
      independently-verifiable sub-requirements.
    signal: >
      Presence of "and" or ";" joining clauses with different verification
      targets. Multiple distinct observable behaviors in one statement.

  - id: MR-02
    name: implementation_free
    check: review
    rule: >
      The requirement states what, not how. No technology, component,
      register, bus, or protocol names unless the requirement IS the
      interface specification.
    signal: >
      Named hardware registers, specific baud rates, chip part numbers,
      bus protocols, or GPIO pin assignments.

  - id: MR-03
    name: unambiguous
    check: review
    rule: >
      The requirement admits exactly one interpretation.
    signal: >
      Bare "it", "this", "the system" without antecedent; "etc.",
      "and/or", "as appropriate", "if possible".

  - id: MR-04
    name: consistent
    check: review
    rule: >
      The requirement does not contradict any other requirement.
    signal: >
      Two requirements prescribing different behaviors for the same
      stimulus, or conflicting timing bounds.

  - id: MR-05
    name: verifiable
    check: auto
    rule: >
      A concrete procedure exists that can determine pass/fail.
    signal: >
      "Should", "may", "ideally", "as much as possible" — any
      qualifier that prevents a binary pass/fail determination.

  - id: MR-06
    name: comprehensible
    check: review
    rule: >
      A qualified reviewer can understand the requirement without
      reading other requirements or implementation code.
    signal: >
      Forward references to undefined terms, implicit context
      ("the usual sequence"), acronyms without definition.

  - id: MR-07
    name: classified
    check: auto
    rule: >
      The requirement carries exactly one [verification-method] tag.
    signal: >
      Missing tag, or more than one tag on the same requirement.
```

## 3. Requirement Intake Flow (Act 2 Demo)

When a new requirement enters the system (e.g., a user describes a feature
in natural language), the following lightweight flow replaces a full lifecycle
state machine:

1. **Wish** — The user states a natural-language desire (e.g., "I want a
   countdown for the pedestrian crosswalk").
2. **Decompose** — The agent decomposes the wish into one or more candidate
   requirements, each written to pass MR-01 through MR-07.
3. **Self-check** — The agent validates each candidate against the YAML
   checklist above and flags any failures.
4. **Interview** — The agent presents the candidates to the user for
   approval, explaining any MR trade-offs (e.g., "I split this into two
   requirements because MR-01 requires atomicity").
5. **Commit** — Approved requirements are assigned IDs following the existing
   `FR-XX-NN` / `NFR-XX-NN` scheme and added to `srs.md`.

This flow is **not** a lifecycle (there is no "proposed" or "confirmed"
state). A requirement either enters the SRS or it doesn't.

## 4. Audit of Existing SRS (v0.1)

The following issues were identified when auditing the v0.1 SRS against this
checklist. They are resolved in the updated SRS.

| Requirement | Failure | Resolution |
|-------------|---------|------------|
| All 26 reqs | MR-07 (no verification-method tag) | Added `[proof]` / `[test]` / `[inspect]` / `[hw-test]` tags. |
| FR-SF-04 | MR-01 (not atomic: combines fault entry + vehicle indication + ped indication) | Split into FR-SF-04 (fault entry), FR-SF-08 (vehicle indication), FR-SF-09 (ped indication). |
| FR-UI-01 | MR-02 (implementation detail: "UART, 115200 8N1") | Removed baud rate and framing; these belong in the hardware interface section. |
| FR-UI-03 | MR-02 (implementation detail: "UART0") | Replaced with "diagnostic serial interface". |
| FR-UI-04 | MR-02 (implementation detail: "UART0") | Replaced with "diagnostic serial interface". |
| FR-UI-05 | MR-02 (implementation detail: "UART1") | Replaced with "command serial interface". |
