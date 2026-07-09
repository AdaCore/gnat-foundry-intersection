"""
The requirement file format, as pydantic models.

A requirement file is a *container* (see docs/README.md): its `description`
map holds the numbered shall-statements, each an object carrying its own
upward trace. `HlrDocument` / `LlrDocument` describe the two levels'
documents and are the machine-checkable contract for the format documented
under ``docs/``.
"""

from __future__ import annotations

from abc import abstractmethod
from typing import Annotated, ClassVar, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from pydantic_core import PydanticCustomError

NonEmptyStr = Annotated[str, Field(min_length=1)]
RefList = Annotated[list[NonEmptyStr], Field(min_length=1)]


class _Model(BaseModel):
    """Strict, immutable base: unknown keys rejected, no coercion, no nulls."""

    model_config = ConfigDict(extra="forbid", strict=True, frozen=True)

    @model_validator(mode="before")
    @classmethod
    def _no_null_values(cls, data: object) -> object:
        # Optional fields are `X | None` only so they can be *omitted*; an
        # explicit null is not a valid value for any key of the format.
        if isinstance(data, dict):
            for key, value in data.items():
                if value is None:
                    raise PydanticCustomError(
                        "null_value",
                        "'{key}' must not be null; omit the key instead",
                        {"key": key},
                    )
        return data


class _BaseStatement(_Model):
    """One atomic shall-statement, carrying its own upward trace."""

    up_ref_key: ClassVar[str]  # name of the subclass's up-ref field

    text: NonEmptyStr

    @property
    @abstractmethod
    def up_refs(self) -> list[str] | None:
        """The statement's upward trace refs; None when derived (HLR only)."""

    @property
    def is_derived(self) -> bool:
        """Whether the statement is marked `derived: true` (HLR-only)."""
        return False


class HlrStatement(_BaseStatement):
    """
    An HLR statement.

    Exactly one of `source` / `derived` must be present: a statement that
    traces nowhere must be explicitly marked derived.
    """

    up_ref_key: ClassVar[str] = "source"

    source: RefList | None = None
    derived: Literal[True] | None = None

    @property
    def up_refs(self) -> list[str] | None:
        """The statement's `source` refs; None when derived."""
        return self.source

    @property
    def is_derived(self) -> bool:
        """Whether the statement is marked `derived: true`."""
        return self.derived is True

    @model_validator(mode="after")
    def _trace_xor(self) -> Self:
        if (self.source is None) == (self.derived is None):
            raise PydanticCustomError(
                "trace_xor",
                "statement must have exactly one of 'source' or 'derived'",
            )
        return self


class LlrStatement(_BaseStatement):
    """An LLR statement."""

    up_ref_key: ClassVar[str] = "parent_req"

    parent_req: RefList

    @property
    def up_refs(self) -> list[str]:
        """The statement's `parent_req` refs."""
        return self.parent_req


class _BaseDocument(_Model):
    """A requirement container document."""

    context: NonEmptyStr | None = None
    rationale: NonEmptyStr | None = None

    @field_validator("description", mode="after", check_fields=False)
    @classmethod
    def _contiguous_keys(cls, value: dict[int, object]) -> dict[int, object]:
        """E-DESCKEY: description statement numbers must be contiguous from 1."""
        keys = sorted(value)
        expected = list(range(1, len(keys) + 1))
        if keys != expected:
            raise PydanticCustomError(
                "desckey",
                "description keys must be contiguous from 1; got {keys}, expected {expected}",
                {"keys": keys, "expected": expected},
            )
        return value


class HlrDocument(_BaseDocument):
    """A high-level requirement container document."""

    description: Annotated[dict[int, HlrStatement], Field(min_length=1)]


class LlrDocument(_BaseDocument):
    """A low-level requirement container document."""

    visibility: NonEmptyStr | None = None
    description: Annotated[dict[int, LlrStatement], Field(min_length=1)]
    preconditions: list[NonEmptyStr] | None = None
    implemented_by: list[NonEmptyStr] | None = None
    algorithm_aspects: NonEmptyStr | None = None


Statement = HlrStatement | LlrStatement
