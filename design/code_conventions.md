# Code conventions

Follow these conventions when working with artifacts in this project. Note that
most code-centric sections are aimed at Ada/SPARK.

## Naming conventions

We do not use namespaces for packages; we use _child packages_ when needed for code organisation
purposes.

Casing:

* Use Mixed_Case for Ada identifiers
* Use their original case for C identifiers imported into Ada, for instance system constants or C functions.

## Documentation conventions

Each package spec (`.ads` file) should have a header comment that describes the purpose of the package.

For all other entities, documentation is materialised by comments which immediately
follow the **specification** of the entity.

All subprograms should have documentation.

Use gnatdoc tags to document entities:

* `@enum Enum_Name description` for enum literals
* `@field Field_Name description` for record fields
* `@param Param_Name description` for subprogram parameters
* `@return description` for function return value

## Commentary conventions

These conventions govern *commentary* — prose about an artifact — and not the artifact's own
content: a `rationale` field in a requirement, for instance, is content, and is out of scope.

Across all artifacts, seek to be concise.

The artifacts (code, scripts, Makefile, etc.) should stand alone as much as possible.
Commentary across all artifacts should not teach the language or the tools.
Explain what, when necessary; don't explain why: in general, decisions and their rationale
belong in commit messages or merge requests.

Commentary should exist in one place only, where it is most relevant.
E.g., architecture commentary in `architecture.md`; script commentary in the script; code
commentary in the code.

## Type system

Leverage the Ada typing system: introduce narrow types as needed. Introduce new types to avoid
danger of introducing arithmetic operations involving types that are not meant to be compatible.

## Commented-out code

It is possible for code to be commented out (for instance, code deferred for future implementation,
or code that can be activated for debug purposes). The reason for commenting code out should be
explained in a comment. This is an intentional deviation from the prohibition against explaining why,
because commented code needs that explanation to be understood in situ.

## Elaboration code

Packages bodies should _not_ contain elaboration code. Prefer an explicit `Initialize` subprogram
to be called by the application at startup. Package specs might have elaboration code by way of
constants initialization.

## Global variables

There should be no global variables.

## Constants

There should be no "magic numbers" in the code. Constants should be declared for all
numbers that have a meaning in the code, scoped to the smallest possible scope.
