#!/usr/bin/env python3
"""Run odinfmt safely and account for its multiline loop-header bug."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


LOOP_HEADER = re.compile(
    r"(^[ \t]*|[;{}][ \t]*)for[ \t]*\n((?:(?!\{).)*?)\{",
    flags=re.DOTALL | re.MULTILINE,
)


def repair_loop_headers(path: Path) -> None:
    original = path.read_text()
    text = original
    while True:
        repaired = LOOP_HEADER.sub(
            lambda match: match.group(1)
            + "for "
            + re.sub(r"\n[ \t]*", " ", match.group(2))
            + "{",
            text,
        )
        if repaired == text:
            break
        text = repaired
    text = re.sub(r"[ \t]+(?=\n)", "", text)
    if text != original:
        path.write_text(text)


def source_files(directories: list[Path]) -> list[Path]:
    return sorted(path for directory in directories for path in directory.rglob("*.odin"))


def snapshot(files: list[Path]) -> dict[Path, bytes]:
    return {path: path.read_bytes() for path in files}


def format_until_stable(formatter: str, config: Path, directories: list[Path]) -> None:
    files = source_files(directories)
    previous = snapshot(files)
    for _ in range(8):
        for directory in directories:
            subprocess.run(
                [formatter, "-w", f"-config:{config}", str(directory)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        for path in files:
            repair_loop_headers(path)
        current = snapshot(files)
        if current == previous:
            return
        previous = current
    raise RuntimeError("odinfmt did not converge after 8 passes")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--formatter", default="odinfmt")
    parser.add_argument("--config", type=Path, default=Path("odinfmt.json"))
    parser.add_argument("directories", nargs="+", type=Path)
    args = parser.parse_args()

    original_files = source_files(args.directories)
    original = snapshot(original_files)
    if not args.check:
        format_until_stable(args.formatter, args.config.resolve(), args.directories)
        return 0

    with tempfile.TemporaryDirectory(prefix="chicago-odinfmt-") as temporary:
        root = Path(temporary)
        copies: list[Path] = []
        for directory in args.directories:
            destination = root / directory
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(directory, destination)
            copies.append(destination)
        format_until_stable(args.formatter, args.config.resolve(), copies)
        formatted = snapshot(source_files(copies))

    changed = []
    for original_path, formatted_path in zip(original_files, formatted.values(), strict=True):
        if original[original_path] != formatted_path:
            changed.append(str(original_path))
    if changed:
        print("Odin files need formatting:", file=sys.stderr)
        print("\n".join(changed), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
