"""Tests for the rendered-requirements collector."""

from __future__ import annotations

import json
from typing import TYPE_CHECKING, Any

import pytest

from vreport.model import REQUIREMENTS_INDEX_SCHEMA_VERSION, ArtifactParseError
from vreport.requirements import collect_requirements

if TYPE_CHECKING:
    from pathlib import Path


def _write_render(
    root: Path, *, pages: tuple[str, ...] = ("hlr_x", "llr_x"), **overrides: Any
) -> Path:
    """Write a rendered document under the default path, with its pages present."""
    directory = root / "reports" / "requirements"
    (directory / "pages").mkdir(parents=True, exist_ok=True)
    for page in pages:
        (directory / "pages" / f"{page}.md").write_text(f"# {page}\n", encoding="utf-8")
    payload: dict[str, Any] = {
        "schema_version": REQUIREMENTS_INDEX_SCHEMA_VERSION,
        "command": "reqs document --chain requirements/trace_chain.yaml",
        "generated_at": "2026-07-29T00:00:00+00:00",
        "corpus_valid": True,
        "layers": [{"name": "HLR", "pages": ["hlr_x"]}, {"name": "LLR", "pages": ["llr_x"]}],
        "nodes": {
            "HLR": {"hlr_x.1": {"page": "hlr_x", "anchor": "hlr-x-1", "text": "Thing."}},
            "LLR": {"llr_x.1": {"page": "llr_x", "anchor": "llr-x-1", "text": "Realization."}},
        },
    }
    payload.update(overrides)
    (directory / "index.json").write_text(json.dumps(payload), encoding="utf-8")
    return directory


def test_absent_render_is_not_an_error(tmp_path: Path) -> None:
    """The render is optional input: without it the report simply carries no links."""
    assert collect_requirements(tmp_path) is None


def test_collects_the_index_and_records_where_it_came_from(tmp_path: Path) -> None:
    """The index parses into the model, keeping the directory the pages live in."""
    directory = _write_render(tmp_path)

    document = collect_requirements(tmp_path)

    assert document is not None
    assert document.source_dir == str(directory)
    assert document.pages == ["hlr_x", "llr_x"]
    assert document.corpus_valid is True
    statement = document.statement("HLR", "hlr_x.1")
    assert statement is not None
    assert statement.anchor == "hlr-x-1"


def test_a_node_of_an_unrendered_layer_resolves_to_nothing(tmp_path: Path) -> None:
    """Layers the document does not render have no statements to link to."""
    _write_render(tmp_path)

    document = collect_requirements(tmp_path)

    assert document is not None
    assert document.statement("CONOPS", "1.1") is None
    assert document.statement("HLR", "hlr_x.9") is None


def test_unreadable_index_is_an_error(tmp_path: Path) -> None:
    """A render that is present but broken must not degrade into a silent fallback."""
    directory = _write_render(tmp_path)
    (directory / "index.json").write_text("{not json", encoding="utf-8")

    with pytest.raises(ArtifactParseError):
        collect_requirements(tmp_path)


def test_unsupported_schema_version_names_the_remedy(tmp_path: Path) -> None:
    """A future index is refused with the command that regenerates it."""
    _write_render(tmp_path, schema_version=REQUIREMENTS_INDEX_SCHEMA_VERSION + 1)

    with pytest.raises(ArtifactParseError, match="make requirements-doc"):
        collect_requirements(tmp_path)


def test_index_of_the_wrong_shape_is_an_error(tmp_path: Path) -> None:
    """An index whose layers are not layers is a parse error, not a partial render."""
    _write_render(tmp_path, layers="HLR")

    with pytest.raises(ArtifactParseError):
        collect_requirements(tmp_path)


def test_index_naming_an_unrendered_page_is_an_error(tmp_path: Path) -> None:
    """A page the index promises but the render never wrote would break the build."""
    directory = _write_render(tmp_path)
    (directory / "pages" / "llr_x.md").unlink()

    with pytest.raises(ArtifactParseError, match="not rendered"):
        collect_requirements(tmp_path)


def test_an_explicit_directory_overrides_the_default(tmp_path: Path) -> None:
    """`--requirements-dir` reads a render from somewhere other than the default."""
    elsewhere = tmp_path / "somewhere"
    (elsewhere / "pages").mkdir(parents=True)
    (elsewhere / "pages" / "hlr_x.md").write_text("# hlr_x\n", encoding="utf-8")
    (elsewhere / "index.json").write_text(
        json.dumps(
            {
                "schema_version": REQUIREMENTS_INDEX_SCHEMA_VERSION,
                "layers": [{"name": "HLR", "pages": ["hlr_x"]}],
                "nodes": {},
            }
        ),
        encoding="utf-8",
    )

    document = collect_requirements(tmp_path, elsewhere)

    assert document is not None
    assert document.pages == ["hlr_x"]
