# Task: Elaborate low-level requirements (LLR)

## Purpose

Refine the HLRs into detailed, implementable low-level requirements: the
mechanism the HLR deliberately omits (debounce, latching, counters, algorithms,
error handling). Every LLR statement traces up to an HLR via `parent_req`. An LLR
must **never** reference the CONOPS.

## Inputs

- `workflow/<feature>/notes.md` — if it exists.
- `requirements/hlr/*.yaml` — the parents (LLRs trace to these).
- `engine/requirements/HLR.drafting.md` — LLR vs HLR distinction (LLR owns
  unobservable mechanism).
- `engine/requirements/docs/{rules,ears}.md` — RS.1–RS.5, EARS grammar.
- `engine/requirements/docs/examples/*/llr_*.yaml` — worked LLR examples showing
  the format: `visibility:`, `description:` map with per-statement `text` +
  `parent_req:` (list of HLR IDs), optional `preconditions`, `implemented_by`,
  `algorithm_aspects`, `rationale`.

## Outputs

- New/edited `requirements/llr/*.yaml`.
- **One-time prerequisite** (perform if not yet done): enable the LLR layer so the
  oracle actually checks it —
  - uncomment the `LLR` block in `requirements/trace_chain.yaml`, and
  - uncomment the `# "$(REQS_DIR)/llr"` paths on the two `validate schema` /
    `validate ears` lines of the `validate-reqs` recipe in the `Makefile`, and
  - create the `requirements/llr/` directory.

## Procedure

1. If the LLR layer is not yet enabled, do the one-time prerequisite above.
2. For each HLR the feature touches, write the refining LLR statements in EARS.
3. Set `parent_req` on every statement to the HLR ID(s) it refines.
4. Record mechanism detail (algorithms, latches, error paths) that the HLR omits.
5. Validate (the oracle).
6. Remove from `workflow/<feature>/notes.md` any notes that have been addressed by the LLRs.
7. Add to `workflow/<feature>/notes.md` any notes that are useful for implementation, in particular
   any LLRs that you have added/modified and that are not yet implemented by code.

## Oracle

```bash
make validate-reqs
```

**Done when it exits 0 with no diagnostics** — with the LLR layer enabled this
now also checks HLR→LLR traceability (every LLR has a real parent; every HLR is
covered or waived) in addition to schema + EARS.

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if the HLR is too
vague to refine without inventing behavior (the fix belongs in the HLR task, not
here), or if a mechanism choice has externally observable consequences the HLR
doesn't cover.
