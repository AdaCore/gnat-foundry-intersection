# workflow/ — feature run state

This directory holds the **run state of feature-workflow instances** for *this
app*. It is the app-side counterpart to the engine definitions under
[`engine/workflow/`](../engine/workflow/README.md) (the same way `requirements/`
holds the app's requirements while `engine/requirements/` holds the tool).

One subdirectory per feature: `workflow/<feature-slug>/` containing

- `plan.md` — the selected task chain and per-task status, and
- `questions.md` — the append-only human-escalation Q&A log.

The format of both files and the orchestration loop that maintains them are
specified in [`engine/workflow/README.md`](../engine/workflow/README.md). These
files are tracked in git so a feature's history is auditable and readable by any
AI CLI.
