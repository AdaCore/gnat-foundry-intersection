# Rules

## Rule RS.1

Each requirement shall be written with:

- natural language (English), which includes [EARS](ears.md) syntax for the
  `description` field constituting the body of the requirement
- semi-formal notations, such as:
  - code blocks
  - mathematical or graphical elements such as equations, graphs, diagrams,
    flow charts, and many other forms of representation (e.g., UML and SysML)

## Rule RS.2

Each requirement shall be uniquely identified.

> **Note**
> A requirement's identifier is `<stem>.<number>`, where `<stem>` is the
> requirement file's name without its extension and `<number>` is the key of
> the statement within that file's `description` map (see [RS.3](#rule-rs3)).
> For example, statement `2` of `hlr_Exponentiation_Int_1.yaml` has the
> identifier `hlr_Exponentiation_Int_1.2`. The bare `<stem>` denotes the file's
> container of statements, not an individual requirement; cross-references such
> as `parent_req` name a specific statement by its full `<stem>.<number>` ID.

## Rule RS.3

Each requirement shall contain exactly one "shall" statement.

> **Note**
> A physical file may contain more than one requirement statement; this rule
> refers to the individual requirement statements within the physical file
> container.

A statement that deliberately carries no "shall" (e.g. an explanatory note)
may opt out of this rule by including the token `rs3:skip` anywhere in it; the
`W-RS3` lint then suppresses the warning for that statement.

## Rule RS.4

Each requirement shall have the following characteristics:

- [atomic (singular)](glossary.md#atomic-singular)
- [feasible](glossary.md#feasible)
- [implementation-free](glossary.md#implementation-free)
- [internally consistent](glossary.md#internally-consistent)
- [unambiguous](glossary.md#unambiguous)
- [verifiable](glossary.md#verifiable)

## Rule RS.5

The set of requirements for an element shall have the following properties:

- [hierarchical structure](glossary.md#hierarchical-structure)
- [completeness](glossary.md#completeness)
- [external consistency](glossary.md#external-consistency)
- [no duplication](glossary.md#no-duplication)
