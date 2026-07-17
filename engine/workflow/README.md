# Feature workflow

This directory is part of *the engine*: reusable, tool-agnostic definitions for
driving a feature through a fixed, auditable process. It is the single source of
truth for the workflow — both Claude Code (via the thin agents under
`.claude/agents/`) and any other AI CLI read the same specs here.

A **feature** is added as a succession of **Tasks**. Each Task type has:

- a **spec** in [`tasks/`](tasks/) describing exactly what to do, and
- an **oracle** — a mechanical command whose success *is* the definition of
  "done". A Task is complete only when its oracle passes. Nothing else counts.
  (Except for the Plan task, which has no oracle.)

## Task types and default order

```
HLR ─▶ LLR ─▶ Architecture ─▶ Plan ─▶ Implementation ─▶ Prove ─▶ Test generation ─▶ Coverage
```

A feature uses **only the subset it needs** — e.g. a proof-strengthening change
may run `Prove` + `Coverage` alone; a pure requirements clarification may run
`HLR` alone. The orchestrator picks the chain per feature (see
[Orchestration](#orchestration)).

| # | Task | Spec |
|---|------|------|
| 1 | Elaborate HLR | [`tasks/hlr.md`](tasks/hlr.md) |
| 2 | Elaborate LLR | [`tasks/llr.md`](tasks/llr.md) |
| 3 | Architecture | [`tasks/architecture.md`](tasks/architecture.md) |
| 4 | Plan | [`tasks/plan.md`](tasks/plan.md) |
| 5 | Implementation | [`tasks/implementation.md`](tasks/implementation.md) |
| 6 | Prove | [`tasks/prove.md`](tasks/prove.md) |
| 7 | Test generation | [`tasks/test-generation.md`](tasks/test-generation.md) |
| 8 | Coverage | [`tasks/coverage.md`](tasks/coverage.md) |

Every spec follows the same shape — **Purpose / Inputs / Outputs / Procedure /
Oracle / Escalation**.

## Orchestration

The workflow is driven by a **main (orchestrating) session**, human-in-the-loop.
There is no orchestration engine — the loop is:

1. Give the feature a slug and create its run directory: `workflow/<feature>/`.
2. Write `workflow/<feature>/plan.md` — the selected task chain and a status line
   per task (see [Run state](#run-state)).
3. For each task, in order:
   a. Dispatch the matching sub-agent (task `hlr` → agent `hlr-author`, etc.).
      Pass the feature slug to the sub-agent.
   b. **Block until the sub-agent completes.**.
   c. After the sub-agent returns, read `workflow/<feature>/questions.md`. If it
      contains an unanswered question, relay it to the human, write the answer
      back into the file, and re-dispatch the sub-agent so it can resume.
   d. Update the task's status in `workflow/<feature>/plan.md`.
4. The feature is done when every task in the chain is `oracle-passed`.

## Run state

Per feature, under `workflow/<feature>/` (tracked in git — auditable, and any CLI
can read/write it):

### `plan.md`

The selected chain and per-task status. One line per task; status is one of
`todo` · `in-progress` · `oracle-passed` · `blocked`:

```markdown
# Feature: <feature> — <one-line goal>

- [ ] hlr — todo
- [ ] llr — todo
- [ ] architecture — todo
- [ ] plan — todo
- [ ] implementation — todo
- [ ] prove — todo
- [ ] test-generation — todo
- [ ] coverage — todo
```

### `questions.md`

Append-only Q&A log — the **only** channel a sub-agent uses to reach a human. A
sub-agent that hits a decision it cannot make (a genuine design/requirements
choice, not a coding detail it should just decide) **appends a question block and
stops** rather than guessing:

```markdown
## Q1 [prove] — <the question, with enough context to answer>
<optional: options considered, why blocked>

A1:
```

The human (or the orchestrator on their behalf) fills the `A<n>:` line. Work
resumes on re-dispatch. Never edit or delete a prior Q/A — only append.

### `notes.md`

Any notes that are useful for the next sub-agents in the chain. Delete notes when addressed.

## Adding or changing a task type

Edit the spec here (and, if the oracle command changes, the table above and the
matching `.claude/agents/*.md` wrapper). Keep the substance in this directory;
the agent wrappers stay thin so the CLIs never diverge. Update `CLAUDE.md` accordingly.
