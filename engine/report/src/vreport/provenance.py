"""Git provenance and small file helpers shared by the collectors."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

from vreport.model import GitInfo

if TYPE_CHECKING:
    from pathlib import Path


def read_optional(path: Path) -> str | None:
    """Return the stripped text of `path`, or None if it does not exist."""
    return path.read_text().strip() if path.is_file() else None


def _git(root: Path, *args: str) -> str | None:
    """Run one git query under `root`; None when git fails or is absent."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), *args],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    return proc.stdout.strip() if proc.returncode == 0 else None


def collect_git(root: Path) -> GitInfo | None:
    """Describe the state of the sources under `root` (None outside git)."""
    commit = _git(root, "rev-parse", "HEAD")
    if commit is None:
        return None
    status = _git(root, "status", "--porcelain")
    return GitInfo(
        commit=commit,
        branch=_git(root, "rev-parse", "--abbrev-ref", "HEAD") or "?",
        dirty=bool(status) if status is not None else True,
        describe=_git(root, "describe", "--always", "--dirty"),
    )
