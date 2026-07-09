# Code conventions

Follow these conventions when writing Ada/SPARK code.

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

## Type system

Leverage the Ada typing system: introduce narrow types as needed. Introduce new types to avoid
danger of introducing arithmetic operations involving types that are not meant to be compatible.

## Commented-out code

It is possible for code to be commented out (for instance, code deferred for future implementation,
or code that can be activated for debug purposes). The reason for commenting code out should be
explained in a comment.

## Global variables

There should be no global variables.

## Constants

There should be no "magic numbers" in the code. Constants should be declared for all
numbers that have a meaning in the code, scoped to the smallest possible scope.
