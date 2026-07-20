"""Apply a deterministic, room-aware furnishing pass to every authored lot."""

from __future__ import annotations

import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LEVELS = ROOT / "assets/levels"
CATALOG = ROOT / "assets/catalog/editor_catalog.toml"
START = "# BEGIN GENERATED ROOM FURNISHINGS"
END = "# END GENERATED ROOM FURNISHINGS"

# Asset, normalized X, normalized Y, rotation. Positions deliberately leave a
# circulation lane through the middle of each room.
OFFICE = (("desk", .28, .28, 0), ("chair_desk", .28, .48, 180), ("computer_screen", .28, .28, 0),
          ("bookcase_closed", .82, .24, 180), ("floor_lamp_round", .82, .78, 180))
BEDROOM = (("bed_single", .28, .34, 90), ("side_table", .28, .72, 90), ("table_lamp_square", .28, .72, 90),
           ("lounge_chair", .78, .72, 225), ("rug_rectangle", .55, .48, 90))
PUBLIC = (("table_round", .50, .48, 0), ("chair_rounded", .50, .25, 0), ("chair_rounded", .50, .72, 180),
          ("chair_rounded", .25, .48, 270), ("chair_rounded", .75, .48, 90))
LOUNGE = (("lounge_design_sofa", .25, .30, 0), ("lounge_design_chair", .75, .30, 0),
          ("table_coffee_square", .50, .55, 0), ("floor_lamp", .82, .76, 180), ("plant", .18, .78, 0))
STORAGE = (("bookcase_closed_wide", .18, .24, 180), ("bookcase_open_low", .50, .18, 180),
           ("cardboard_box_closed", .78, .24, 0), ("cardboard_box_open", .78, .72, 0), ("trashcan", .18, .75, 0))
SERVICE = (("kitchen_cabinet", .18, .22, 180), ("kitchen_cabinet_upper_double", .50, .18, 180),
           ("kitchen_cabinet_upper", .80, .18, 180), ("stool_bar", .48, .65, 0), ("trashcan", .82, .75, 0))
INDUSTRIAL = (("desk", .22, .24, 0), ("chair_desk", .22, .48, 180), ("bathroom_cabinet", .78, .22, 180),
              ("cardboard_box_closed", .78, .70, 0), ("trashcan", .50, .76, 0))
PASSAGE = (("bench_cushion", .28, .24, 180), ("coat_rack", .78, .24, 180), ("plant_small2", .78, .76, 0))
EXTERIOR = (("yard_bench", .35, .32, 180), ("nature_bush", .18, .76, 0), ("nature_flowers", .52, .78, 0),
            ("nature_grass", .80, .72, 0), ("stylized_tree_1", .82, .24, 0))
BATHROOM = (("bathroom_cabinet", .22, .22, 180), ("bathroom_sink", .50, .20, 180),
            ("bathroom_mirror", .50, .14, 180), ("toilet", .78, .25, 180), ("shower_round", .78, .72, 0))


def room_template(room_id: str, room_name: str):
    key = f"{room_id} {room_name}".lower()
    if any(word in key for word in ("courtyard", "terrace", "garden", "yard", "loading court")):
        return EXTERIOR
    if any(word in key for word in ("bathroom", "lavatory", "washroom")):
        return BATHROOM
    if any(word in key for word in ("bedroom", "suite", "sleeping", "apartment")):
        return BEDROOM
    if any(word in key for word in ("office", "studio", "control", "editing", "projection", "booth")):
        return OFFICE
    if any(word in key for word in ("archive", "library", "store", "vault", "baggage", "collection", "cloakroom")):
        return STORAGE
    if any(word in key for word in ("pantry", "kitchen", "service cellar")):
        return SERVICE
    if any(word in key for word in ("corridor", "passage", "vestibule", "lift")):
        return PASSAGE
    if any(word in key for word in ("station", "gallery", "track", "carriage", "floor", "tool bay", "shed", "print room", "cellar")):
        return INDUSTRIAL
    if any(word in key for word in ("lounge", "reception", "practice", "rehearsal")):
        return LOUNGE
    return PUBLIC


def strip_generated(text: str) -> str:
    if START in text:
        before, rest = text.split(START, 1)
        _, after = rest.split(END, 1)
        text = before.rstrip() + after
    # Early blockout lots used one generic placeholder per room. Remove only
    # those explicitly disposable IDs; authored and mystery-linked objects stay.
    sections = re.split(r"(?=^\[\[)", text, flags=re.M)
    sections = [section for section in sections if not (
        section.startswith("[[objects]]")
        and re.search(r'^id = "(?:table|furnishing)_\d+"$', section, re.M)
    )]
    return "".join(sections).rstrip() + "\n"


def room_bounds(room: dict) -> tuple[float, float, float, float]:
    points = room["points"]
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def main() -> None:
    catalog = tomllib.loads(CATALOG.read_text())
    catalog_ids = {entry["id"] for entry in catalog["objects"]}
    updated = 0
    placed = 0
    for path in sorted(LEVELS.glob("*.toml")):
        if path.name.startswith("."):
            continue
        original = strip_generated(path.read_text())
        level = tomllib.loads(original)
        if not any(marker.get("id") == "spawn_player" for marker in level.get("markers", [])):
            first_room = level["rooms"][0]
            x0, y0, x1, y1 = room_bounds(first_room)
            spawn = "\n".join((
                "[[markers]]",
                'id = "spawn_player"',
                'reference = ""',
                'kind = "player_spawn"',
                f"story = {first_room.get('story', 0)}",
                f"position = [[{x0 + (x1 - x0) * .18:.2f}, {y0 + (y1 - y0) * .82:.2f}]]",
                "radius = 0.4",
                "facing = 0.0",
            ))
            original = original.rstrip() + "\n\n" + spawn + "\n"
            level = tomllib.loads(original)
        existing_ids = {entry["id"] for entry in level.get("objects", [])}
        blocks: list[str] = []
        for room in level.get("rooms", []):
            x0, y0, x1, y1 = room_bounds(room)
            template = room_template(room["id"], room.get("name", ""))
            # Vale House already has complete kitchens and bathing fixtures;
            # enrich these rooms without duplicating their major appliances.
            if path.name == "vale_house.toml" and room["id"] in {"kitchen", "bathroom"}:
                continue
            if path.name == "vale_house.toml" and room["id"] == "powder_room":
                template = (("bathroom_mirror", .80, .18, 180), ("bathroom_cabinet", .25, .72, 0))
            for index, (asset, nx, ny, rotation) in enumerate(template, 1):
                if asset not in catalog_ids:
                    raise KeyError(f"unknown catalog asset {asset}")
                object_id = f"furnish_{room['id']}_{index}_{asset}"
                if object_id in existing_ids:
                    continue
                x = x0 + (x1 - x0) * nx
                y = y0 + (y1 - y0) * ny
                lines = [
                        "[[objects]]",
                        f'id = "{object_id}"',
                        f'catalog_id = "{asset}"',
                ]
                if template is OFFICE and asset == "computer_screen":
                    lines.extend((f'support_id = "furnish_{room["id"]}_1_desk"', "elevation = 0.74"))
                elif template is BEDROOM and asset == "table_lamp_square":
                    lines.extend((f'support_id = "furnish_{room["id"]}_2_side_table"', "elevation = 0.62"))
                lines.extend((
                        f"story = {room.get('story', 0)}",
                        f"position = [[{x:.2f}, {y:.2f}]]",
                        f"rotation = {rotation:.1f}",
                        "tint = [255, 255, 255, 255]",
                ))
                blocks.append("\n".join(lines))
                existing_ids.add(object_id)
        generated = f"{START}\n\n" + "\n\n".join(blocks) + f"\n\n{END}\n"
        path.write_text(original.rstrip() + "\n\n" + generated)
        updated += 1
        placed += len(blocks)
        print(f"{path.name}: {len(blocks)} generated furnishings")
    print(f"Updated {updated} lots with {placed} room-aware furnishings")


if __name__ == "__main__":
    main()
