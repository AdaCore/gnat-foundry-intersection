# EARS Notation and Patterns

The Easy Approach to Requirements Syntax (EARS) notation uses keywords and a
simple underlying ruleset to constrain natural language requirements.

EARS requirements have clauses that are always in the same order, following
temporal logic. This means that the requirements mirror common usage of English
while optimizing **clarity** and **precision**. EARS requirements are designed
to be intuitively **simple to understand**.

## Generic EARS syntax

The clauses of a requirement written in EARS always appear in the same order.
The basic structure of an EARS requirement is:

> **While** \<optional pre-condition(s)\>, **when** \<optional trigger\>, the
> \<system name\> **shall** \<system response(s)\>

The EARS ruleset states that a requirement must have:

- Zero or more preconditions;
- Zero or one trigger;
- One system name;
- One or many system responses.

The application of the EARS notation produces requirements in a small number
of patterns, depending on the clauses that are used. The patterns are
illustrated below.

## Ubiquitous requirements

Ubiquitous requirements are always active (so there is no EARS keyword).

> The \<system name\> **shall** \<system response(s)\>

Example:

```text
The mobile phone shall have a mass of less than XX grams.
```

## State driven requirements

State driven requirements are active as long as the specified state remains
true and are denoted by the keyword **While**.

> **While** \<precondition(s)\>, the \<system name\> **shall** \<system response(s)\>

Example:

```text
While there is no card in the ATM, the ATM shall display
"insert card to begin".
```

## Event driven requirements

Event driven requirements specify how a system must respond when a triggering
event occurs and are denoted by the keyword **When**.

> **When** \<trigger\>, the \<system name\> **shall** \<system response(s)\>

Example:

```text
When "mute" is selected, the laptop shall suppress all audio output.
```

## Unwanted behavior requirements

Unwanted behavior requirements are used to specify the required system
response to undesired situations and are denoted by the keywords **If** and
**Then**.

> **If** \<trigger\>, **then** the \<system name\> **shall** \<system response(s)\>

Example:

```text
If an invalid credit card number is entered, then the website shall display
"please re-enter credit card details".
```

## Complex requirements

The simple building blocks of the EARS patterns described above can be
combined to specify requirements for richer system behaviour. Requirements
that include more than one EARS keyword are called Complex requirements.

> **While** \<precondition(s)\>, **when** \<trigger\>, the \<system name\>
> **shall** \<system response(s)\>

Example:

```text
While the aircraft is on the ground, when reverse thrust is commanded, the
engine control system shall enable reverse thrust.
```

Complex requirements for unwanted behavior also include the If-Then keywords.
