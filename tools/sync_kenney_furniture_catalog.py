"""Register every Kenney Furniture Kit GLB in the editor catalog.

Existing hand-tuned catalog entries remain authoritative. The script appends one
generated entry for each otherwise-unreferenced model and can be rerun safely.
"""

from __future__ import annotations

import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/catalog/editor_catalog.toml"
MODEL_DIR = ROOT / "assets/kenney_furniture-kit/Models/GLTF format"
START = "# BEGIN GENERATED KENNEY FURNITURE ASSETS"
END = "# END GENERATED KENNEY FURNITURE ASSETS"


def snake_case(name: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", name).lower()


def metadata(name: str) -> tuple[str, float, float, float, str]:
    """Return category, footprint, surface height, elevation, placement."""
    key = name.lower()
    category = "decor"
    footprint = 0.35
    surface = 0.0
    elevation = 0.0
    placement = "indoor"

    if key.startswith(("wall", "floor", "doorway", "stairs", "paneling")):
        category, footprint = "architecture", 1.0
    elif key.startswith(("bathroom", "bathtub", "shower", "toilet")):
        category, footprint = "bathroom", 0.55
    elif key.startswith(("kitchen", "hood", "toaster")):
        category, footprint = "kitchen", 0.5
    elif key.startswith(("bed", "cabinetbed", "pillow")):
        category, footprint = "bedroom", 0.65
    elif key.startswith(("chair", "bench", "lounge", "stool")):
        category, footprint = "seating", 0.5
    elif key.startswith(("table", "sidetable", "desk")):
        category, footprint, surface = "tables", 0.7, 0.74
    elif key.startswith(("bookcase", "cardboardbox")):
        category, footprint = "storage", 0.55
    elif key.startswith(("computer", "laptop")):
        category, footprint = "office", 0.25
    elif key.startswith(("television", "speaker", "radio")):
        category, footprint = "electronics", 0.35
    elif key.startswith("rug"):
        category, footprint = "rugs", 0.75
    elif key.startswith(("plant", "pottedplant")):
        category, footprint, placement = "landscaping", 0.3, "indoor_or_outdoor"
    elif key.startswith(("washer", "dryer", "trashcan")):
        category, footprint = "utility", 0.5

    if "cabinet" in key and category in {"bathroom", "kitchen", "bedroom"}:
        surface = 0.82
    if key.startswith("bathroomsink"):
        surface = 0.82
    if key.startswith(("computer", "laptop", "books", "pillow", "radio", "speaker", "toaster")):
        footprint = min(footprint, 0.28)
    if key.startswith("wall") or key == "paneling":
        elevation = 0.0
    return category, footprint, surface, elevation, placement


def main() -> None:
    original = CATALOG.read_text()
    if START in original:
        before, remainder = original.split(START, 1)
        _, after = remainder.split(END, 1)
        original = before.rstrip() + after

    parsed = tomllib.loads(original)
    referenced_models = {entry.get("model", "") for entry in parsed.get("objects", [])}
    used_ids = {entry.get("id", "") for entry in parsed.get("objects", [])}
    blocks: list[str] = []

    for model in sorted(MODEL_DIR.glob("*.glb"), key=lambda path: path.name.lower()):
        relative_model = model.relative_to(ROOT).as_posix()
        if relative_model in referenced_models:
            continue
        asset_id = snake_case(model.stem)
        if asset_id in used_ids:
            asset_id = f"kenney_{asset_id}"
        category, footprint, surface, elevation, placement = metadata(model.stem)
        lines = [
            "[[objects]]",
            f'id = "{asset_id}"',
            f'category = "{category}"',
            f'model = "{relative_model}"',
            f"footprint_radius = {footprint:.2f}",
        ]
        if surface:
            lines.append(f"surface_height = {surface:.2f}")
        if elevation:
            lines.append(f"default_elevation = {elevation:.2f}")
        lines.append(f'placement = "{placement}"')
        blocks.append("\n".join(lines))
        used_ids.add(asset_id)

    generated = f"{START}\n\n" + "\n\n".join(blocks) + f"\n\n{END}\n"
    CATALOG.write_text(original.rstrip() + "\n\n" + generated)
    print(f"Registered {len(blocks)} previously missing furniture models")


if __name__ == "__main__":
    main()
