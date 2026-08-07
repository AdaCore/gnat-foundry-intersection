"""
The requirement file format, as pydantic models.

A requirement file is a *container* (see docs/README.md): its `description`
map holds the numbered shall-statements, each an object carrying its own
trace refs. `HlrDocument` / `LlrDocument` describe the two levels' documents and
are the machine-checkable contract for the format documented under ``docs/``.
"""

from __future__ import annotations

from abc import abstractmethod
from typing import Annotated, ClassVar, Literal, Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from pydantic_core import PydanticCustomError

NonEmptyStr = Annotated[str, Field(min_length=1)]
RefList = Annotated[list[NonEmptyStr], Field(min_length=1)]

# How an LLR statement is verified; machine evidence cites it back via `--@covers`.
VERIFICATION_METHODS = ("test", "proof", "static_check", "review")
VerificationMethod = Literal["test", "proof", "static_check", "review"]


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


class VerificationMeans(_Model):
    """One way a statement is discharged."""

    method: VerificationMethod
    justification: NonEmptyStr | None = None  # review only: why no machine check

    @model_validator(mode="after")
    def _justification_matches_method(self) -> Self:
        if (self.justification is not None) != (self.method == "review"):
            raise PydanticCustomError(
                "verification_justification",
                "'justification' must be present exactly when method is 'review'",
            )
        return self


class _BaseStatement(_Model):
    """One atomic shall-statement, carrying its own trace refs."""

    up_ref_key: ClassVar[str]  # name of the subclass's up-ref field
    # Down-ref fields, if any; the trace engine resolves each against its own
    # layer below (a layer's `ref_field`).
    down_ref_fields: ClassVar[tuple[str, ...]] = ()

    text: NonEmptyStr

    @property
    @abstractmethod
    def up_refs(self) -> list[str] | None:
        """The statement's upward trace refs; None when derived (HLR only)."""

    def down_refs_in(self, field: str | None) -> list[str] | None:
        """Return the downward trace refs held in `field`; None if it has none."""
        if field in self.down_ref_fields:
            return getattr(self, field)  # type: ignore[no-any-return]
        return None

    @property
    def _verification(self) -> list[VerificationMeans]:
        # Only an LLR declares verification means; the shared surface reads ().
        return getattr(self, "verification", None) or []

    @property
    def verification_methods(self) -> tuple[str, ...]:
        """The declared verification methods, in order; empty when undeclared."""
        return tuple(means.method for means in self._verification)

    def justification_for(self, method: str | None) -> str | None:
        """Return the justification of the entry declaring `method`, if any."""
        for means in self._verification:
            if means.method == method:
                return means.justification
        return None

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
    """
    An LLR statement.

    `verification` lists how the statement is discharged, one entry per method;
    `verification: test` is shorthand for the single bare entry. A `review`
    entry says why no machine check exists (`justification`); the machine
    methods carry nothing here, because their evidence cites *us* -- a
    `--@covers` tag on the test routine, contract or pragma.
    """

    up_ref_key: ClassVar[str] = "parent_req"
    down_ref_fields: ClassVar[tuple[str, ...]] = ("implemented_by",)

    parent_req: RefList
    verification: Annotated[list[VerificationMeans], Field(min_length=1)] | None = None
    implemented_by: RefList | None = None

    @property
    def up_refs(self) -> list[str]:
        """The statement's `parent_req` refs."""
        return self.parent_req

    @field_validator("verification", mode="before")
    @classmethod
    def _shorthand(cls, value: object) -> object:
        # `verification: test` is sugar for a single entry with no evidence.
        if isinstance(value, str):
            return [{"method": value}]
        return value

    @field_validator("verification", mode="after")
    @classmethod
    def _methods_unique(
        cls, value: list[VerificationMeans] | None
    ) -> list[VerificationMeans] | None:
        methods = [means.method for means in value or ()]
        if len(set(methods)) != len(methods):
            raise PydanticCustomError("verification_dup", "verification methods must not repeat")
        return value


# Every downward-ref field a statement can hold. A trace layer's `ref_field`
# must name one of these: a mistyped field reads no refs from any statement, so
# the layer would resolve nothing and quietly check nothing.
DOWN_REF_FIELDS: tuple[str, ...] = tuple(
    dict.fromkeys(name for cls in (HlrStatement, LlrStatement) for name in cls.down_ref_fields)
)


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
    algorithm_aspects: NonEmptyStr | None = None


Statement = HlrStatement | LlrStatement
