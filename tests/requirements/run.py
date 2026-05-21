#!/usr/bin/env python3
"""Run the requirements-based test suite for the traffic-light controller.

Discovers every ``test_*`` module in this directory, runs each
``test_*`` function, and prints a PASS/FAIL summary plus the set of
FR/NFR IDs that passing tests cover.

Usage:
    python3 tests/requirements/run.py [<module_substring> ...]

With one or more substrings, only modules whose name contains any of
them are loaded — e.g. ``python3 tests/requirements/run.py fr_ph``
runs only the FR-PH-* tests.
"""
from __future__ import annotations

import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import harness  # noqa: E402


def discover_modules(filters: list[str]) -> list:
    mods = []
    for path in sorted(HERE.glob("test_*.py")):
        stem = path.stem
        if filters and not any(f in stem for f in filters):
            continue
        mods.append(importlib.import_module(stem))
    return mods


def main(argv: list[str]) -> int:
    filters = argv[1:]
    mods = discover_modules(filters)
    if not mods:
        print(f"No test modules matched {filters}", file=sys.stderr)
        return 2
    print(f"Loaded {len(mods)} test module(s): "
          f"{', '.join(m.__name__ for m in mods)}")
    return harness.run(mods)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
