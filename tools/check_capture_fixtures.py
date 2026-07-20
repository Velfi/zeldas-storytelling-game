#!/usr/bin/env python3
"""Reject unstable numeric/index capture setup in src/main.odin."""

from pathlib import Path
import re
import sys


FORBIDDEN = (
    ("numeric dialogue entity", re.compile(r"dialogue_entity\s*=\s*\d+")),
    ("numeric context target", re.compile(r"context_(?:entity|runtime)_target\s*\(\s*&g\s*,\s*\d+")),
    ("numeric interactive access", re.compile(r"g\.interactives\s*\[\s*\d+\s*\]")),
    ("capture world-entity mutation", re.compile(r"WORLD_ENTITIES\s*\[[^]]+\]\s*\.(?:x|y)\s*=")),
)
DIRECT_TRANSFORM = re.compile(r"g\.(?:player_x|player_y|player_angle|camera_x|camera_y|camera_orbit)\s*=\s*[-+\d.]" )


def capture_setup(source: str) -> str:
    start = source.find("if capture_mode&&!capture_fixture_pose")
    end = source.find("dialogue_pointer_focus_id :: proc", start)
    return source[start:end] if start >= 0 and end >= 0 else source


def violations(source: str) -> list[str]:
    setup = capture_setup(source)
    found = [name for name, pattern in FORBIDDEN if pattern.search(source)]
    # Numeric transforms anywhere in main's deterministic setup are forbidden;
    # dynamic framing (for example an authored room center) remains allowed.
    if DIRECT_TRANSFORM.search(setup):
        found.append("hardcoded capture transform")
    return found


def main() -> int:
    source = Path("src/main.odin").read_text()
    found = violations(source)
    if found:
        print("capture fixture check failed: " + ", ".join(found), file=sys.stderr)
        return 1
    print("capture fixtures use authored IDs and markers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
