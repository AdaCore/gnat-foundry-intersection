"""
Collect the requirements rendered as a document.

`reqs document` (``make requirements-doc``) renders the requirement corpus as
MyST pages plus an ``index.json`` naming every statement's page and anchor. The
report folds the pages into its own source tree and links its trace matrices to
them, so a reviewer reading a matrix reaches the requirement text in one click
instead of opening the YAML and counting keys.

The render is *optional* input: a report generated without it still says
everything it said before, with matrix ids as plain text. A render that is
present but unreadable is an error, not a silent fallback -- a half-linked
matrix would be indistinguishable from a fully-linked one.
"""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

from pydantic import ValidationError

from vreport.model import (
    REQUIREMENTS_INDEX_SCHEMA_VERSION,
    ArtifactParseError,
    RequirementsDocument,
)

if TYPE_CHECKING:
    from pathlib import Path

INDEX_NAME = "index.json"
PAGES_DIR = "pages"


def collect_requirements(root: Path, source: Path | None = None) -> RequirementsDocument | None:
    """
    Parse the rendered requirement document under ROOT, or None if there is none.

    Naming the file in any error: an index that cannot be read must not degrade
    quietly into an unlinked report.
    """
    directory = source or root / "reports" / "requirements"
    index = directory / INDEX_NAME
    if not index.is_file():
        return None
    try:
        data = json.loads(index.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ArtifactParseError(index, str(exc)) from exc
    if not isinstance(data, dict):
        raise ArtifactParseError(index, "top level must be an object")
    version = data.pop("schema_version", None)
    if version != REQUIREMENTS_INDEX_SCHEMA_VERSION:
        raise ArtifactParseError(
            index,
            f"unsupported schema_version {version!r} (this reader supports "
            f"{REQUIREMENTS_INDEX_SCHEMA_VERSION}) — regenerate with `make requirements-doc`",
        )
    payload: dict[str, Any] = {**data, "source_dir": str(directory)}
    try:
        document = RequirementsDocument.model_validate(payload)
    except ValidationError as exc:
        raise ArtifactParseError(index, str(exc)) from exc
    pages = directory / PAGES_DIR
    missing = [page for page in document.pages if not (pages / f"{page}.md").is_file()]
    if missing:
        raise ArtifactParseError(
            index,
            f"index names {len(missing)} page(s) that were not rendered "
            f"({', '.join(missing[:3])}) — regenerate with `make requirements-doc`",
        )
    return document
