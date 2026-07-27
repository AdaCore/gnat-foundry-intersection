# The `ada_tracer` JSON document

One JSON object per run, on standard output or the file given to `-o`.
Bump `Schema_Version` in [`src/ada_tracer.ads`](src/ada_tracer.ads) on any
incompatible change here.

## Root

| Field | Type | Meaning |
|---|---|---|
| `schema_version` | integer | Currently `2` |
| `tool` | string | Always `"ada_tracer"` |
| `project` | string | The project file the run was given, or `"<none>"` |
| `packages` | array | The packages found, sorted by `name` |
| `library_subprograms` | array | [Subprogram](#subprogram) entries that are compilation units in their own right, so belong to no package — `main.adb`'s `Main`, a library-level generic procedure. In the order encountered |

## Package

| Field | Type | Meaning |
|---|---|---|
| `name` | string | Fully qualified, e.g. `"Buses.Display_Bus"` |
| `spec_file` | string \| null | The file declaring it, relative to the base directory (see below); `null` if only a body was seen |
| `body_file` | string \| null | The file holding its body; `null` if it has none |
| `is_generic` | boolean | True for a generic package declaration |
| `doc` | object | See [Documentation](#documentation) |
| `subprograms` | array | In the order encountered — spec declarations first, then body-only ones |
| `entities` | array | Its types, subtypes, objects and exceptions; see [Entity](#entity) |

A package spec and its body are **one entry**, with both file fields set.

Every file name in the document — `spec_file`, `body_file` and the `file` of a
`location` — is relative to the **base directory**: the directory holding the
project file, or the argument of `--base-dir` when given. A file that is not
under that directory is reported by its absolute name.

## Subprogram

| Field | Type | Meaning |
|---|---|---|
| `name` | string | The simple name |
| `qualified_name` | string | e.g. `"Conflicts.Compatible"` |
| `kind` | string | `"procedure"`, `"function"` or `"entry"` |
| `declared_in` | string | `"spec"` or `"body"` |
| `nested` | boolean | An enclosing subprogram body sits between it and its package |
| `has_body` | boolean | A spec declaration completed by a body in the same run |
| `is_generic` | boolean | A generic subprogram declaration |
| `is_renaming` | boolean | A renaming declaration |
| `is_expression_function` | boolean | An expression function |
| `is_abstract` | boolean | An abstract or null subprogram declaration |
| `is_body` | boolean | This entry *is* a body — see below |
| `parameters` | array | Flattened: `(A, B : T)` yields two entries |
| `return_type` | string \| null | As written in the source; `null` for a procedure |
| `location` | object | `{ "file": string, "line": integer, "column": integer }` |
| `doc` | object | See [Documentation](#documentation) |
| `body_comments` | array | For a body, the comment blocks inside it; see [Comment block](#comment-block). Empty otherwise |

A subprogram declared in a spec and defined in the body appears **once**, on
the spec declaration, with `has_body: true`. Matching is by name and parameter
profile, which keeps the tool free of name resolution.

`is_body` is not the same question as either `has_body` or `declared_in`
(`"body"` there means "found in the package body"). A routine written out as a
forward declaration, a `renames` alias and a body — which is how GNATtest emits
one — yields three entries, all with `declared_in: "body"`; **`is_body` and not
`is_renaming`** is the selector that picks the body out. Because the body of a
subprogram declared in a spec is folded onto the spec entry, that folded entry
keeps `is_body: false` and inherits the body's `body_comments`.

### Comment block

A run of comment lines inside a body. It documents nothing — it is reported for
the tags it may carry, where a convention puts a machine-readable tag in the
body rather than around the declaration.

| Field | Type | Meaning |
|---|---|---|
| `text` | string | The verbatim block, as for `doc.text` |
| `first_line` | integer | The line the block's first comment sits on |
| `last_line` | integer | The line the block's last comment sits on |
| `tags` | array | `{ "tag": string, "name": string, "text": string, "line": integer }`, in source order |

`tags` is an **array**, not an object keyed by tag word as `doc.other_tags` is,
because here repetition is meaningful: a body may carry the same tag several
times and each occurrence has its own line. `src/tests/controller-test_data-tests.adb`
spreads one routine's `--@covers` ids over seven lines, and keying by tag word
would collapse them to the last. `doc.other_tags` is left as it was so nothing
downstream of schema 1 has to move.

### Entity

A type, subtype, object or exception declared in a package. Reported because a
requirement names whatever realizes it, and such a name is as likely to be a
type or a constant as a subprogram.

| Field | Type | Meaning |
|---|---|---|
| `name` | string | The simple name |
| `qualified_name` | string | e.g. `"States.Movement"` |
| `kind` | string | `"type"`, `"subtype"`, `"constant"`, `"variable"` or `"exception"` |
| `declared_in` | string | `"spec"` or `"body"` |
| `is_renaming` | boolean | An object or exception renaming declaration |
| `location` | object | `{ "file": string, "line": integer, "column": integer }` |
| `doc` | object | See [Documentation](#documentation) |

`A, B : Integer;` yields one entry per identifier, as parameters do, and the two
share the declaration's documentation. `X : constant := 3` is a `"constant"`
even though Ada gives a named number a node of its own.

### Parameter

| Field | Type | Meaning |
|---|---|---|
| `name` | string | The formal's name |
| `mode` | string | `"in"`, `"in out"` or `"out"`; an absent mode reads as `"in"` |
| `type` | string | The type expression as written, not resolved |

## Documentation

| Field | Type | Meaning |
|---|---|---|
| `text` | string | The verbatim block: `--` markers and the common indentation removed, lines joined with `\n` |
| `source` | string | `"none"`, `"leading"`, `"trailing"` or `"both"` |
| `description` | string | The prose before the first tag line |
| `params` | object | `@param` tags, keyed by formal name |
| `returns` | string \| null | The `@return` tag |
| `fields` | object | `@field` tags, keyed by field name |
| `enums` | object | `@enum` tags, keyed by literal name |
| `other_tags` | object | Any other `@tag`, keyed by tag word — preserved, never an error |

A tag runs until the next tag line or the end of the block, so its prose may
span several lines; continuations are folded in with single spaces.

## Example

From `src/core/conflicts.ads`:

```json
{
  "name": "Compatible",
  "qualified_name": "Conflicts.Compatible",
  "kind": "function",
  "declared_in": "spec",
  "nested": false,
  "has_body": false,
  "is_generic": false,
  "is_renaming": false,
  "is_expression_function": true,
  "is_abstract": false,
  "is_body": false,
  "parameters": [
    { "name": "A", "mode": "in", "type": "States.Movement" },
    { "name": "B", "mode": "in", "type": "States.Movement" }
  ],
  "return_type": "Boolean",
  "location": { "file": "src/core/conflicts.ads", "line": 37, "column": 4 },
  "doc": {
    "text": "Two movements are *compatible* -- releasable together -- exactly when\n...",
    "source": "trailing",
    "description": "Two movements are *compatible* -- releasable together -- exactly when\n...",
    "params": {
      "A": "One movement",
      "B": "The other movement"
    },
    "returns": "True when the two movements may be released together",
    "fields": {},
    "enums": {},
    "other_tags": {}
  },
  "body_comments": []
}
```

And the `--@covers` tag of a GNATtest routine, from
`src/tests/conflicts-test_data-tests.adb` — the second block, because the first
is the generated `--  <spec>:<line>:<col>:<name>` / `--  end read only` pair:

```json
"is_body": true,
"body_comments": [
  { "text": "conflicts.ads:35:4:Compatible\nend read only",
    "first_line": 37, "last_line": 38, "tags": [] },
  { "text": "@covers llr_3_conflicts.1",
    "first_line": 40, "last_line": 40,
    "tags": [ { "tag": "covers", "name": "", "text": "llr_3_conflicts.1", "line": 40 } ] },
  { "text": "begin read only", "first_line": 50, "last_line": 50, "tags": [] }
]
```

## Stability

`packages` is sorted by name; `subprograms`, `entities`,
`library_subprograms` and `body_comments` keep source order. Two runs over
unchanged sources therefore produce byte-identical output and the document diffs
cleanly. Non-ASCII characters are emitted as `\uXXXX` escapes.

That is what keeps the inventories diffable across regenerations:
`obj/analysis/*_inventory.json` is regenerated by `make code-inventory` /
`make test-inventory` on every `make validate-reqs` / `make trace`, and a run
that changes nothing changes no byte, so a real change to the sources is the
only thing a diff of two runs shows.
