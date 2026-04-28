#!/usr/bin/env python3
"""Render the SRS Markdown to .docx and PDF using Pandoc.

Outputs go to docs/requirements/srs.docx and docs/requirements/srs.pdf
(both .gitignored — they are CI artifacts, not committed).

Requires: pandoc (>= 2.19), and a LaTeX engine for PDF (xelatex recommended).

Usage:
    python3 tools/render-srs.py [--no-pdf]
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRS = ROOT / "docs" / "requirements" / "srs.md"
DOCX_OUT = ROOT / "docs" / "requirements" / "srs.docx"
PDF_OUT = ROOT / "docs" / "requirements" / "srs.pdf"


def have(cmd: str) -> bool:
    return shutil.which(cmd) is not None


def render_docx() -> int:
    cmd = [
        "pandoc",
        str(SRS),
        "-o", str(DOCX_OUT),
        "--toc",
        "--toc-depth=2",
        "-V", "lang=en-US",
    ]
    return subprocess.call(cmd)


def render_pdf() -> int:
    cmd = [
        "pandoc",
        str(SRS),
        "-o", str(PDF_OUT),
        "--toc",
        "--toc-depth=2",
        "--pdf-engine=xelatex",
        "-V", "geometry:margin=1in",
        "-V", "mainfont=DejaVu Serif",
    ]
    return subprocess.call(cmd)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-pdf", action="store_true")
    args = parser.parse_args()

    if not have("pandoc"):
        print("pandoc not found", file=sys.stderr)
        return 2

    rc = render_docx()
    if rc != 0:
        return rc
    print(f"Wrote {DOCX_OUT.relative_to(ROOT)}")

    if not args.no_pdf:
        if not have("xelatex"):
            print("xelatex not found, skipping PDF", file=sys.stderr)
            return 0
        rc = render_pdf()
        if rc != 0:
            return rc
        print(f"Wrote {PDF_OUT.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
