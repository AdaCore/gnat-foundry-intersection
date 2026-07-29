# ada_tracer — a JSON inventory of an Ada project's packages

Parses an Ada project with [Libadalang](https://github.com/AdaCore/libadalang)
and emits, for every package it finds, the subprograms that package declares
and the comments documenting each of them.

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
| --- | --- |
| `-o`, `--output FILE` | Write the JSON to `FILE` instead of standard output |
| `--compact` | One line instead of an indented document |
| `--specs-only` | Report only package specs, skipping bodies |
| `--base-dir DIR` | Report file names relative to `DIR` rather than to the project's own directory |

The document shape is described in [`json_schema.md`](json_schema.md).

`--base-dir` is useful for a *generated* project such as the GNATtest
harness project which names the skeleton directories under `tests/` as source
dirs from several levels down, so without it every test body is reported by
its absolute name. Point it at the repository root and the names stay the
repo-relative ones the rest of the toolchain prints.

Run it inside the Alire environment, which is what puts the crate's
dependencies (`aunit`, for the harness project) on `GPR_PROJECT_PATH`:

```bash
alr exec -P -- ./engine/ada_tracer/bin/ada_tracer -U     # -P inserts the crate's own project
```

From the repository root:

```bash
make build-tracer    # build the `ada_tracer` binary
make code-inventory  # build if needed, then run against traffic_light.gpr
make test-inventory  # ...and against the generated GNATtest harness project
make inventories     # both, which is what `make trace-check` / `make trace` need
```

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
├── json_schema.md               # the schema of the emitted document
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
