# Task: Elaborate high-level requirements (HLR)

## Purpose

Capture externally observable behavior of the feature as HLR YAML, traced up to
the CONOPS. HLRs describe *what* is observable — never the mechanism (that is the
LLR's job).

## Inputs

- `requirements/conops.md` — the concept of operations (the layer HLRs trace to).
- `requirements/hlr/*.yaml` — existing HLRs (match their style and IDs).
- `engine/requirements/HLR.drafting.md` — **the methodology** (Moore state
  machines in EARS, the manifestation test, one machine per file). Follow it.
- `engine/requirements/docs/{README,rules,ears,glossary}.md` — format, RS.1–RS.5,
  EARS grammar.

## Outputs

- New/edited `requirements/hlr/*.yaml`. Each statement traces to a CONOPS leaf via
  `source:` **or** is marked `derived: true` (and the gap pushed up to CONOPS).
- If the feature is not yet covered by the CONOPS, an edit to
  `requirements/conops.md` (or a `trace_waivers.yaml` entry) so the trace closes.

## Procedure

Follow the `Procedure` in `engine/requirements/HLR.drafting.md`:
1. List the subsystem's inputs, outputs (+ value sets), and states.
2. Apply the manifestation test; draw the machine.
3. Write it in EARS: one `While`-output per state, one `While…when…` per edge.
4. Put durations in the timing file; cite them by name.
5. Trace each statement to a CONOPS leaf via `source`, or `derived: true`.
6. Validate (the oracle).

## Oracle

```bash
make validate-reqs
```

**Done when it exits 0 with no diagnostics** — schema (`--complete`) + EARS +
CONOPS→HLR traceability all clean.

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if: the CONOPS is
silent on behavior the feature needs (does it require a CONOPS change, and what
should it say?), or an observable behavior is genuinely ambiguous. Do **not**
invent a requirement to make the trace close — a missing upper node is a real gap.
