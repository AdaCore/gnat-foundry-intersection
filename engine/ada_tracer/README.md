# ada_tracer — a JSON inventory of an Ada project's packages

Parses an Ada project with [Libadalang](https://github.com/AdaCore/libadalang)
and emits, for every package it finds, the subprograms that package declares
and the comments documenting each of them.

This is *engine* tooling: it knows nothing about the traffic-light
application, and takes the project to analyse on the command line.

## Why it exists

Nothing in this repository can answer *"which subprograms exist in which
package, and what are they documented as?"* from the sources themselves. Two
earlier attempts scraped comments with regular expressions and both rotted —
`tools/trace-check.py` (deleted in `4c60218`, its stale output still committed
at `docs/requirements/traceability.md` naming packages that no longer exist),
and the regexes in `engine/requirements/src/reqs/ada_tests.py`, which landed in
`d40417e` and which this tool has since replaced.

Meanwhile `requirements/llr/*.yaml` carries ~50 distinct `implemented_by:`
refs naming `Package.Entity` identifiers, and
[`../requirements/LLR.drafting.md`](../requirements/LLR.drafting.md) states
that each LLR statement is implemented by exactly one entity. `ada_tracer` is
the parser that makes resolving those names possible: it now feeds both the
TEST and the CODE layers of `requirements/trace_chain.yaml`, via the generated
inventories `obj/analysis/test_inventory.json` and
`obj/analysis/code_inventory.json`. The tool itself still knows nothing about
requirements — it reports what the sources say and `reqs` interprets it.

## Usage

```bash
ada_tracer -P <project.gpr> -U [options]
```

`-U` is almost always wanted. Without it Libadalang looks at the root project
alone, which for a wrapper project like `traffic_light.gpr` — whose only source
is a library-level `main.adb` — yields nothing. The tool says so on stderr
rather than silently emitting an empty document.

Options beyond the ones
[`Libadalang.Helpers.App`](https://github.com/AdaCore/libadalang) already
provides (`-P`, `-X`, `-U`, `-C`, `-k`, positional file names, `--help`):

| Switch | Effect |
|---|---|
| `-o`, `--output FILE` | Write the JSON to `FILE` instead of standard output |
| `--compact` | One line instead of an indented document |
| `--specs-only` | Report only package specs, skipping bodies |
| `--base-dir DIR` | Report file names relative to `DIR` rather than to the project's own directory |

The document shape is described in [`json_schema.md`](json_schema.md).

`--base-dir` is for a *generated* project: the GNATtest harness project
`obj/<profile>/gnattest/harness/test_traffic_light.gpr` names `src/tests` as a
source dir from four levels down, so without it every test body is reported by
its absolute name. Point it at the repository root and the names stay the
repo-relative ones the rest of the toolchain prints.

Run it inside the Alire environment, which is what puts the crate's
dependencies (`aunit`, for the harness project) on `GPR_PROJECT_PATH`:

```bash
alr exec -P -- ./engine/ada_tracer/bin/ada_tracer -U     # -P inserts the crate's own project
```

From the repository root:

```bash
make trace-code      # build if needed, then run against traffic_light.gpr
make build-tracer    # build only
make inventories     # both inventories, as `make validate-reqs` regenerates them
```

## Building

The crate declares `libadalang` as an Alire dependency, so the portable route
is plain `alr build` from this directory. Two things to know:

* **It builds Libadalang from source** — ~23 MB of generated Ada, so budget a
  one-off 10–25 minutes. Later builds are cached.
* **It needs an Alire index.** The repository's own `install/alire/settings/`
  has none configured (the root crate has no dependencies, so it never needed
  one). Build with your ambient Alire settings, not through
  `ALIRE_SETTINGS_DIR=install/...`.

### Against an already-installed Libadalang

Much faster where one exists, and what `make build-tracer` picks automatically
when it finds a `libadalang.gpr` on `GPR_PROJECT_PATH`. `ada_tracer.gpr`
imports `libadalang` by name, so the same project file serves both routes.

In an AdaCore `wave` sandbox:

```bash
W=$PWD/../../wave/x86_64-linux
export GPR_PROJECT_PATH=$(printf '%s:' \
  $W/{libadalang,langkit_support,gnatcoll-core,libgpr2_bare,libgpr,xmlada}_ide_stable/install/share/gpr \
  $W/gnatcoll-bindings-{gmp,iconv}_ide_stable/install/share/gpr \
  $W/vss-extra/install/share/gpr)

make trace-code LAL_BIN_DIR=$W/gnat_ide_stable/install/bin
```

`LAL_BIN_DIR` matters: the prebuilt libraries are only usable with the
compiler that produced them. Building against them with a different GNAT fails
at bind time with *"compiled with different GNAT versions"*. Point
`LAL_BIN_DIR` at the bin directory of the matching compiler and the Makefile
puts it in front of `PATH` for the tracer build alone, leaving the rest of the
repository on its usual toolchain.

`build-tracer` and `trace-code` are opt-in and are wired into no other target:
`build-native`, `check` and `test` are what CI runs, and no CI job should pay
for a Libadalang build.

## How comments are associated

`design/code_conventions.md` puts an entity's documentation in the comments
that *follow* its specification, and a package's in a header comment above it.
Bodies invert the first rule — `src/core/controller.adb` writes the comment
above the subprogram. The tool therefore looks in both directions and records
which rule fired in `doc.source`.

A third rule covers comments *inside* a body, which document nothing: they are
reported verbatim, per block, in `body_comments`, because a convention may put a
machine-readable tag there. `--@covers` is the case in hand — a GNATtest
routine's surroundings are regenerated boilerplate, so the first editable line
of the body is the only durable place for it. The tool learns nothing about what
such a tag means.

Three things that look like documentation but are not, and are excluded:

* an end-of-line remark on the same line as the declaration
  (`when N_Lead => --  .2 ...`, all over `controller.adb`);
* a section ruler (`------------`), which terminates a leading block and is
  dropped, so a banner heading never becomes the next subprogram's doc;
* a block already taken as the *preceding* declaration's trailing
  documentation — adjacent declarations would otherwise both claim it.

The last of those does not apply to `body_comments`: that rule stops two
adjacent *declarations* fighting over one block, and an interior block belongs
to exactly one body by construction.

### Why not `Libadalang.Doc_Utils`

Libadalang ships `Doc_Utils.Get_Documentation`, which implements exactly the
placement convention above, including the fallback that finds a file header
sitting above the context clause. It is unusable here: `Extract_Doc_From`
treats any comment line starting with `@` as an annotation and accepts only
`belongs-to`, `exclude` and `exclude-value`, raising `Property_Error` on
anything else. `design/code_conventions.md` mandates `@param`, `@return`,
`@field` and `@enum`, so it would raise on nearly every documented subprogram
in the tree. Its own header also declares the API experimental and
unsupported. `Ada_Tracer.Comments` reimplements the token walk — never raising
on odd formatting, looking both ways, and parsing the tags into structured
output instead of rejecting them.

## Layout

```
engine/ada_tracer/
├── alire.toml
├── ada_tracer.gpr
├── json_schema.md               # the emitted document, field by field
└── src/
    ├── ada_tracer.ads           # shared vocabulary
    ├── ada_tracer-model.ads/adb # the result, with no Libadalang in it
    ├── ada_tracer-comments.*    # comment trivia -> blocks
    ├── ada_tracer-gnatdoc_tags.*# blocks -> description + tags
    ├── ada_tracer-walk.*        # syntax tree -> model
    ├── ada_tracer-emit.*        # model -> JSON
    └── ada_tracer-main.adb      # Libadalang.Helpers.App instantiation
```

Only syntactic Libadalang properties are used, and every one is guarded, so a
project whose dependencies do not all resolve is still reported on.

## Scope

The unit of output is the **package**, with two documented exceptions, both
there because a requirement may name what they hold:

* types, subtypes, objects and exceptions are reported per package, in
  `entities`;
* a subprogram that is a compilation unit of its own and so belongs to no
  package (`main.adb`'s `Main`, `state_machine_loop.ads`) is reported in the
  root-level `library_subprograms`.

Between them, 49 of the 50 LLR `implemented_by:` refs resolve. The
fiftieth — `Conflicts.Crosswalk_Conflicts` — resolves to nothing because
`src/core/conflicts.ads` declares no such thing, which is the finding the
exercise was for.

What is still out of scope: names are **not resolved**. Matching an
`implemented_by:` ref is textual, against `qualified_name`; renamings and
use-clauses are not followed. That is adequate for the refs at hand and is what
keeps the tool working on a project whose dependencies do not all resolve.
