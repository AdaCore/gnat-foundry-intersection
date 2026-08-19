# Task: Elaborate high-level requirements (HLR)

## Purpose

Capture externally observable behavior of the feature as HLR YAML, traced up to
the CONOPS. HLRs describe *what* is observable — never the mechanism (that is the
LLR's job).

## Inputs

- `requirements/conops.md` — the concept of operations (the layer HLRs trace to).
- `requirements/hlr/*.yaml` — existing HLRs (match their style and IDs).
- Any accompanying explanatory documentation in `requirements/*.md`.
- `engine/requirements/HLR.drafting.md` — **the methodology** (Moore state
  machines in EARS, the manifestation test, one machine per file). Follow it.
- `engine/requirements/docs/{README,rules,ears,glossary}.md` — format, RS.1–RS.5,
  EARS grammar.

## Outputs

- New/edited `requirements/hlr/*.yaml`. Each statement traces to a CONOPS leaf via
  `source:` **or** is marked `derived: true`.
- Edited `requirements/trace_waivers.yaml` if there are CONOPS leaves that do
  not describe software behavior (physical/environmental assumptions, etc.).
- Edited accompanying `requirements/*.md` documentation, if applicable.

## Procedure

Follow the `Procedure` in `engine/requirements/HLR.drafting.md`.

Record a brief summary in `workflow/<feature>/notes.md` as needed.

## Oracle

```bash
make validate-reqs TRACE_LAYERS=CONOPS,HLR
```

**Done when it exits 0 with no diagnostics** — schema (`--complete`) + EARS +
CONOPS→HLR traceability all clean.

## Escalation

Append a question to `workflow/<feature>/questions.md` and stop if: the CONOPS is
silent on behavior the feature needs (does it require a CONOPS change, and what
should it say?), or an observable behavior is genuinely ambiguous. Do **not**
invent a requirement to make the trace close — a missing upper node is a real gap.
