# reqs — requirements tooling

Tooling for the requirement YAML files in this directory: schema validation,
EARS linting, and (planned) traceability and reporting. The requirement format
itself is documented under [`docs/`](docs/README.md); the machine-checkable
contract is [`schema/requirement.schema.json`](schema/requirement.schema.json)
(JSON Schema 2020-12).

## Usage

```bash
# Validate against the schema + structural/RS.3 rules (a path is required)
uv run reqs validate schema docs/examples    # files or directories
uv run reqs validate schema --complete .     # complete set: unresolved parent_req is an error

# Lint the EARS grammar of every description statement
uv run reqs validate ears docs/examples

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
│   ├── cli.py              # Typer app: `reqs validate {schema,ears}`
│   ├── core.py             # Diagnostic, file walking, YAML+source-line load, reporting
│   └── checks/
│       ├── schema.py       # RequirementChecker (schema + structural + RS.3)
│       └── ears.py         # EarsChecker (EARS grammar)
├── tests/                  # pytest suites + negative fixtures
├── schema/                 # the JSON Schema contract
└── docs/                   # the requirement-format documentation + examples
```

Each check is a small class exposing `check(paths) -> list[Diagnostic]`, plus a
thin `*_paths()` function used by the tests; the CLI commands in `cli.py` wrap
them uniformly via `core.report`.

## What's checked

File level is chosen by filename prefix: `hlr_` → high-level, `llr_` → low-level.
The filename stem is the requirement ID (a stable opaque-ID scheme is deferred).

### `validate schema`

| Code | Level | Rule |
| --- | --- | --- |
| `E-PREFIX` | error | filename must start with `hlr_` or `llr_` |
| `E-YAML` | error | file parses as a YAML mapping |
| `E-SCHEMA` | error | JSON Schema: types, required fields, **unknown keys rejected** (so `test_cases` is an error), `source` XOR `derived` on HLRs, lowercase `visibility` enum, non-empty statements |
| `E-DESCKEY` | error | `description` keys are integers, contiguous from 1 |
| `E-DUPID` | error | RS.2 — filename stems (IDs) unique across the set |
| `E-PARENT-TYPE` | error | an LLR `parent_req` that resolves to a non-HLR |
| `W/E-PARENT-MISSING` | warning, or error under `--complete` | `parent_req` resolving to no file in the set |
| `W-RS3` | warning | each statement should contain exactly one "shall" (code blocks excluded; opt out with `rs3:skip`) |

### `validate ears`

EARS is a closed grammar, enforced with regexes. The linter classifies each
statement and reports the ones that match no pattern:

| Code | Rule |
| --- | --- |
| `E-EARS-NOSHALL` | statement contains no "shall" |
| `E-EARS-COMMA` | a `While`/`When` clause isn't terminated by a comma |
| `E-EARS-IFTHEN` | an `If` statement is missing its `then` |
| `E-EARS-CASE` | a leading EARS keyword isn't capitalized |
| `E-EARS-PATTERN` | matches no EARS pattern (bad clause order / no "the &lt;system&gt; shall &lt;response&gt;" core) |

Code blocks, `$$` math, and Markdown tables are stripped before matching.
`shall`-count is RS.3 (`W-RS3`) in `validate schema`, not here. A statement
deliberately outside EARS can opt out with `ears:skip`.

Both commands exit non-zero if any error is reported; warnings alone exit 0.

## Out of scope (planned / deferred)

Deeper EARS semantics, stable opaque IDs, and ReqIF round-tripping are deferred.
`reqs trace` and `reqs report` will attach as future top-level commands.
