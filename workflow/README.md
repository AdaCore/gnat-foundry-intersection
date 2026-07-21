# workflow/ — feature run state

This directory holds the **run state of feature-workflow instances**.
One subdirectory per feature: `workflow/<feature-slug>/`

The format for files in that directory and the orchestration loop that maintains them are
specified in [`engine/workflow/README.md`](../engine/workflow/README.md).

This state is not meant for the main branch, but may be committed on a feature branch for
auditability; it is tracked in git so any CLI can read and write it.
