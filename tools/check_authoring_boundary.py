#!/usr/bin/env python3
"""Structural enforcement for authored-content/runtime boundaries."""

from dataclasses import dataclass
from pathlib import Path
import re
import sys


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    category: str
    destination: str

    def format(self) -> str:
        return f"{self.path}:{self.line}: {self.category}; author in {self.destination}"


RULES = (
    ("numeric runtime identity", re.compile(r"\b(?:dialogue_entity|pending_clue|pending_interactive|near_interactive|hover_interactive)\s*=\s*\d+"), "StoryCore stable IDs and resolver APIs"),
    ("compiled capture transform", re.compile(r"g\.(?:player_x|player_y|player_angle|camera_x|camera_y|camera_orbit)\s*=\s*[-+\d.]"), "LevelFormat staging/camera markers"),
    ("static World_Entity content", re.compile(r"(?:\[\d+\]World_Entity|\[dynamic\]World_Entity)\s*\{"), "StoryCore entities plus LevelFormat bindings"),
    ("synthetic interactive", re.compile(r"(?::=|=)\s*Runtime_Interactive\s*\{"), "LevelFormat openings, objects, or interaction markers"),
    ("renderer entity-ID dispatch", re.compile(r"(?:source_id|target_id)\s*==\s*\"[a-z][a-z0-9_]*\""), "StoryCore presentation/interaction metadata"),
    ("author-facing compiled copy", re.compile(r"World_Entity\s*\{[^\n]*(?:name|description)\s*=\s*\""), "StoryCore display_name/description or localized scene text"),
)


def findings_for_text(path: str, text: str) -> list[Finding]:
    findings: list[Finding] = []
    capture_region = path.endswith("main.odin")
    for number, line in enumerate(text.splitlines(), 1):
        for category, pattern, destination in RULES:
            if not pattern.search(line):
                continue
            if category == "compiled capture transform" and not capture_region:
                continue
            if category == "compiled capture transform" and "capture_mode" not in line:
                continue
            if category == "synthetic interactive" and "level_document." in line and line.lstrip().startswith("for "):
                continue
            # Dispatch checks apply to generic renderer entry points, identified
            # structurally by render/UI filenames rather than content IDs.
            if category == "renderer entity-ID dispatch" and not (path.endswith("ui_screens.odin") or "render" in Path(path).stem):
                continue
            findings.append(Finding(path, number, category, destination))
    return findings


def repository_findings(root: Path) -> list[Finding]:
    found: list[Finding] = []
    for path in sorted((root / "src").glob("*.odin")):
        found.extend(findings_for_text(str(path.relative_to(root)), path.read_text()))
    return found


def main() -> int:
    found = repository_findings(Path("."))
    for item in found:
        print(item.format(), file=sys.stderr)
    if found:
        print(f"authoring boundary check failed with {len(found)} violation(s)", file=sys.stderr)
        return 1
    print("authoring boundary check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
