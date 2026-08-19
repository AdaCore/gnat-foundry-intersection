# reqs — requirements tooling

Tooling for the requirement YAML files in this directory: schema validation,
EARS linting, traceability (`reqs trace`), and rendering the corpus as a
document (`reqs document`). The requirement format
itself is documented under [`docs/`](docs/README.md); a machine-checkable
schema is defined (with Pydantic) in [`src/reqs/document.py`](src/reqs/document.py).

## Usage

```bash
# Validate against the schema + structural/RS.3 rules (a path is required)
uv run reqs validate schema docs/examples    # files or directories
uv run reqs validate schema --complete .     # complete set: unresolved parent_req is an error

# Lint the EARS grammar of every description statement
uv run reqs validate ears docs/examples

# Traceability across a chain config (see requirements/trace_chain.yaml)
uv run reqs trace --chain <chain.yaml> --complete                 # the CI gate (text diagnostics)
uv run reqs trace --chain <chain.yaml> --complete --format table  # dev tables
uv run reqs trace --chain <chain.yaml> --complete --format json -o report.json
# `--format json` writes the machine-readable trace report consumed by the
# verification-report generator (engine/report). Unlike the text gate it exits
# 0 once the report is written: the verdict (errors/warnings/corpus_valid) and
# the same rows the tables render travel inside the payload.

# Render the requirement layers of a chain as a linked document
uv run reqs document --chain <chain.yaml> --out <dir>
uv run reqs document --chain <chain.yaml> --out <dir> --source-root <repo>
# Writes `<dir>/pages/<container>.md` (one MyST page per container, titled as the
# section its name says it is and nested under the container the name places it
# under, one anchored subsection per statement, each carrying its resolved trace
# neighbourhood; a markdown layer like the CONOPS is carried through as written,
# its leaves anchored in place and a closing table naming what realizes each) and
# `<dir>/index.json` (schema_version, each layer's pages and top-level pages,
# every node's page and anchor). With
# `--source-root`, the sources the requirements cite are listed too, under
# `<dir>/pages/sources/`, and the evidence links to the cited lines. The
# verification-report generator folds the pages into its own tree and links its
# trace matrices through the index. Trace gaps render into the document as open
# items; a corpus that does not analyse renders nothing and exits non-zero.

# Tests (prints a coverage report; configured in pyproject.toml)
uv run pytest
uv run pytest --cov-report=html   # browsable report in htmlcov/
```

`uv` handles the environment from `pyproject.toml`; no manual venv setup. If
`uv` isn't on `PATH`, install it: `curl -LsSf https://astral.sh/uv/install.sh | sh`.

## Layout

```
engine/requirements/
├── pyproject.toml          # project + the `reqs` entry point
├── src/reqs/
│   ├── cli.py              # Typer app: `reqs validate {schema,ears}`, `trace`, `document`
│   ├── core.py             # Diagnostic, file walking, YAML+source-line load, reporting
│   ├── document.py         # requirement file schema as Pydantic models
│   ├── requirement_set.py  # loading of requirement files
│   ├── render.py           # the corpus as a document (pages + index), linked via the chain
│   └── checks/
│       ├── schema.py       # RequirementChecker (schema + structural + RS.3)
│       └── ears.py         # EarsChecker (EARS grammar)
├── tests/                  # pytest suites + negative fixtures
└── docs/                   # the requirement-format documentation + examples
```

Each check is a small class exposing `check(paths) -> list[Diagnostic]`, plus a
thin `*_paths()` function used by the tests; the CLI commands in `cli.py` wrap
them uniformly via `core.report`.

## What's checked

The CLI emits coded diagnostics; each runtime message is self-describing. The
**Violates** column cites where the rule is *defined* — don't restate it here.

### `validate schema`

| Code | Level | Violates |
| --- | --- | --- |
| `E-PREFIX` | error | [`requirement_set.py`](src/reqs/requirement_set.py) |
| `E-YAML` | error | [`requirement_set.py`](src/reqs/requirement_set.py) |
| `E-SCHEMA` | error | [`document.py`](src/reqs/document.py) |
| `E-DESCKEY` | error | [`document.py`](src/reqs/document.py) |
| `E-DESCKEY-DUP` | error | [`requirement_set.py`](src/reqs/requirement_set.py) |
| `E-DUPID` | error | [`rules.md` RS.2](docs/rules.md#rule-rs2) |
| `E-PARENT-FORMAT` | error | [`rules.md` RS.2](docs/rules.md#rule-rs2) |
| `E-PARENT-TYPE` | error | [`checks/schema.py`](src/reqs/checks/schema.py) |
| `W`/`E-PARENT-MISSING` | warning, error under `--complete` | [`checks/schema.py`](src/reqs/checks/schema.py) |
| `W`/`E-UNVERIFIED` | warning, error under `--complete` | [`checks/schema.py`](src/reqs/checks/schema.py) |
| `W`/`E-UNIMPLEMENTED` | warning, error under `--complete` | [`checks/schema.py`](src/reqs/checks/schema.py) |
| `W-RS3` | warning | [`rules.md` RS.3](docs/rules.md#rule-rs3) |

### `validate ears`

| Code | Level | Violates |
| --- | --- | --- |
| `E-EARS-NOSHALL` | error | [`ears.md`](docs/ears.md#generic-ears-syntax) |
| `E-EARS-COMMA` | error | [`ears.md`](docs/ears.md#generic-ears-syntax) |
| `E-EARS-IFTHEN` | error | [`ears.md`](docs/ears.md#unwanted-behavior-requirements) |
| `E-EARS-CASE` | error | [`ears.md`](docs/ears.md#generic-ears-syntax) |
| `E-EARS-PATTERN` | error | [`ears.md`](docs/ears.md) |

Both commands exit non-zero on any error; warnings alone exit 0.

## Out of scope (planned / deferred)

Deeper EARS semantics, stable opaque IDs, and ReqIF round-tripping are deferred.
