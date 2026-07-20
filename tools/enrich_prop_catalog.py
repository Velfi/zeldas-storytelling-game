#!/usr/bin/env python3
"""Populate agent-facing design metadata for every editor catalog prop."""

from __future__ import annotations

import json
import math
import re
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/catalog/editor_catalog.toml"


def glb_dimensions(path: Path) -> tuple[float, float, float] | None:
    try:
        data = path.read_bytes()
        if data[:4] != b"glTF":
            return None
        _, _, length = struct.unpack_from("<III", data, 0)
        offset = 12
        document = None
        while offset + 8 <= min(length, len(data)):
            chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
            offset += 8
            if chunk_type == 0x4E4F534A:
                document = json.loads(data[offset : offset + chunk_length].decode("utf-8"))
                break
            offset += chunk_length
        if document is None:
            return None
        mins = [math.inf, math.inf, math.inf]
        maxs = [-math.inf, -math.inf, -math.inf]
        for accessor in document.get("accessors", []):
            if accessor.get("type") != "VEC3" or "min" not in accessor or "max" not in accessor:
                continue
            for axis in range(3):
                mins[axis] = min(mins[axis], float(accessor["min"][axis]))
                maxs[axis] = max(maxs[axis], float(accessor["max"][axis]))
        if not all(math.isfinite(value) for value in mins + maxs):
            return None
        return tuple(max(0.01, maxs[i] - mins[i]) for i in range(3))
    except (OSError, ValueError, KeyError, struct.error, UnicodeDecodeError):
        return None


def quoted(values: list[str]) -> str:
    return "[" + ", ".join(json.dumps(value) for value in dict.fromkeys(values)) + "]"


def classify(prop_id: str, category: str, placement: str, surface_height: float) -> dict[str, object]:
    words = set(prop_id.split("_"))
    surfaces: list[str] = []
    styles = ["stylized", "contemporary"]
    affordances = ["decorate"]
    front = "+z"
    front_clearance = back_clearance = side_clearance = 0.05

    if placement == "outdoor":
        styles.append("outdoor")
    if category in {"foliage", "landscaping"}:
        styles += ["naturalistic"]
        affordances = ["landscape", "soften_space"]
        front = "none"
    elif category == "rugs" or "rug" in words or "mat" in words:
        surfaces = ["floor"]
        styles += ["textile"]
        affordances = ["define_zone", "soften_floor", "decorate"]
        front = "none"
    elif category == "seating" or words & {"chair", "sofa", "bench", "stool", "ottoman"}:
        affordances = ["sit", "conversation", "rest"]
        front_clearance, back_clearance, side_clearance = 0.65, 0.10, 0.15
    elif category in {"tables", "kitchen"} and words & {"table", "desk", "island", "cabinet", "sink", "stove", "bar"}:
        surfaces = ["top"]
        affordances = ["support_objects", "work_surface"]
        front_clearance, back_clearance, side_clearance = 0.80, 0.05, 0.10
    elif category in {"storage", "bedroom", "bathroom", "utility"}:
        affordances = ["store"]
        front_clearance, back_clearance, side_clearance = 0.75, 0.05, 0.08
    elif category == "lighting":
        affordances = ["illuminate", "accent"]
        surfaces = ["ceiling"] if "ceiling" in words else (["wall"] if "wall" in words else ["floor"])
        if "table" in words:
            surfaces = ["support_surface"]
    elif category == "paintings":
        surfaces, affordances = ["wall"], ["display", "wall_decoration"]
    elif category in {"decor", "mystery_props"}:
        affordances = ["display", "decorate"]
        surfaces = ["support_surface"]

    if surface_height > 0 and "top" not in surfaces:
        surfaces.append("top")
        if "support_objects" not in affordances:
            affordances.append("support_objects")
    if words & {"bed", "bunk"}:
        affordances = ["sleep", "rest"]
        front_clearance, back_clearance, side_clearance = 0.75, 0.10, 0.45
    if words & {"bookcase", "cabinet", "fridge", "washer", "dryer", "television"}:
        affordances = ["store"] if not words & {"television"} else ["entertain", "focal_point"]
        front_clearance, back_clearance, side_clearance = 0.80, 0.05, 0.08
    if words & {"lamp", "light"}:
        affordances = ["illuminate", "accent"]
    if words & {"computer", "laptop", "radio", "speaker", "television"}:
        styles.append("electronic")
    if words & {"vintage", "gramophone"}:
        styles.append("vintage")
    if category == "mystery_props":
        styles.append("narrative")
        affordances.append("stage_evidence")

    return {
        "front": front,
        "front_clearance": front_clearance,
        "back_clearance": back_clearance,
        "side_clearance": side_clearance,
        "surfaces": surfaces,
        "styles": styles,
        "affordances": affordances,
    }


def value(block: str, key: str, default: str = "") -> str:
    match = re.search(rf"(?m)^{re.escape(key)}\s*=\s*\"([^\"]*)\"\s*$", block)
    return match.group(1) if match else default


def number(block: str, key: str) -> float:
    match = re.search(rf"(?m)^{re.escape(key)}\s*=\s*([-+0-9.eE]+)\s*$", block)
    return float(match.group(1)) if match else 0.0


def enrich(block: str) -> str:
    prop_id = value(block, "id")
    category = value(block, "category")
    placement = value(block, "placement")
    model = value(block, "model")
    footprint = number(block, "footprint_radius")
    metadata = classify(prop_id, category, placement, number(block, "surface_height"))
    dimensions = glb_dimensions(ROOT / model)
    if dimensions is None:
        dimensions = (footprint * 2, max(footprint * 2, 0.1), footprint * 2)
    # Raw GLB accessors are authoritative when present; dimensions use X/Y/Z.
    fields = (
        f'front_direction = "{metadata["front"]}"\n'
        f'dimensions = [{dimensions[0]:.3f}, {dimensions[1]:.3f}, {dimensions[2]:.3f}]\n'
        f'clearance_front = {metadata["front_clearance"]:.2f}\n'
        f'clearance_back = {metadata["back_clearance"]:.2f}\n'
        f'clearance_left = {metadata["side_clearance"]:.2f}\n'
        f'clearance_right = {metadata["side_clearance"]:.2f}\n'
        f'surfaces = {quoted(metadata["surfaces"])}\n'
        f'styles = {quoted(metadata["styles"])}\n'
        f'affordances = {quoted(metadata["affordances"])}\n'
    )
    cleaned = re.sub(
        r'(?m)^(?:front_direction|dimensions|clearance_front|clearance_back|clearance_left|clearance_right|surfaces|styles|affordances)\s*=.*\n?',
        "",
        block,
    ).rstrip()
    return cleaned + "\n" + fields.rstrip() + "\n"


def main() -> None:
    text = CATALOG.read_text()
    pattern = re.compile(r"(?ms)^\[\[objects\]\]\n.*?(?=^\[\[(?:objects|materials)\]\]|\Z)")
    result = pattern.sub(lambda match: enrich(match.group(0)), text)
    CATALOG.write_text(result)
    count = len(pattern.findall(result))
    print(f"enriched {count} props in {CATALOG.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
