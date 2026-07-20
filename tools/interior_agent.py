#!/usr/bin/env python3
"""Headless, semantic interior-design tools for Chicago level documents.

The CLI deliberately uses the same LevelFormat v1 and EditorCatalog v1 files as
the editor.  Preview is read-only; commit appends one ordinary [[objects]] entry
using an atomic file replacement.
"""

from __future__ import annotations

import argparse
import html
import json
import math
from pathlib import Path
import subprocess
import tomllib
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_LEVEL = ROOT / "assets/levels/vale_house.toml"
DEFAULT_CATALOG = ROOT / "assets/catalog/editor_catalog.toml"
DEFAULT_ENGINE = ROOT / "build/chicago"


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def point_in_polygon(point: tuple[float, float], polygon: list[list[float]]) -> bool:
    x, y = point
    inside = False
    for index, first in enumerate(polygon):
        second = polygon[(index + 1) % len(polygon)]
        x1, y1 = first
        x2, y2 = second
        if (y1 > y) != (y2 > y):
            crossing = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < crossing:
                inside = not inside
    return inside


def room_for(level: dict[str, Any], room_id: str) -> dict[str, Any]:
    for room in level.get("rooms", []):
        if room.get("id") == room_id:
            return room
    raise ValueError(f"unknown room: {room_id}")


def catalog_objects(catalog: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {entry["id"]: entry for entry in catalog.get("objects", [])}


def object_for(level: dict[str, Any], object_id: str) -> dict[str, Any]:
    for entry in level.get("objects", []):
        if entry.get("id") == object_id:
            return entry
    raise ValueError(f"unknown object: {object_id}")


def position(entity: dict[str, Any]) -> tuple[float, float]:
    value = entity.get("position", [[0.0, 0.0]])
    return float(value[0][0]), float(value[0][1])


def room_objects(level: dict[str, Any], room: dict[str, Any]) -> list[dict[str, Any]]:
    story = room.get("story", 0)
    return [
        entry for entry in level.get("objects", [])
        if entry.get("story", 0) == story and point_in_polygon(position(entry), room["points"])
    ]


def room_markers(level: dict[str, Any], room: dict[str, Any]) -> list[dict[str, Any]]:
    story = room.get("story", 0)
    return [
        entry for entry in level.get("markers", [])
        if entry.get("story", 0) == story and point_in_polygon(position(entry), room["points"])
    ]


def room_bounds(room: dict[str, Any]) -> tuple[float, float, float, float]:
    xs = [float(point[0]) for point in room["points"]]
    ys = [float(point[1]) for point in room["points"]]
    return min(xs), min(ys), max(xs), max(ys)


def inspect_room(level: dict[str, Any], catalog: dict[str, Any], room_id: str) -> dict[str, Any]:
    room = room_for(level, room_id)
    entries = catalog_objects(catalog)
    objects = []
    for item in room_objects(level, room):
        metadata = entries.get(item.get("catalog_id", ""), {})
        objects.append({
            "id": item.get("id"), "catalog_id": item.get("catalog_id"),
            "category": metadata.get("category"), "position": list(position(item)),
            "rotation": item.get("rotation", 0.0), "elevation": item.get("elevation", 0.0),
            "support_id": item.get("support_id", ""),
            "footprint_radius": metadata.get("footprint_radius", 0.0),
        })
    return {
        "id": room["id"], "name": room.get("name", room["id"]),
        "story": room.get("story", 0), "points": room["points"],
        "bounds": list(room_bounds(room)),
        "materials": {"floor": room.get("floor_material"), "wall": room.get("wall_material")},
        "objects": objects, "markers": room_markers(level, room),
    }


def search_catalog(catalog: dict[str, Any], query: str, category: str | None,
                   placement: str | None, limit: int) -> list[dict[str, Any]]:
    words = query.lower().split()
    matches = []
    for entry in catalog.get("objects", []):
        haystack = f"{entry.get('id', '')} {entry.get('category', '')} {entry.get('placement', '')}".lower()
        if any(word not in haystack for word in words):
            continue
        if category and entry.get("category") != category:
            continue
        if placement and placement not in entry.get("placement", ""):
            continue
        matches.append({key: entry.get(key) for key in (
            "id", "category", "model", "thumbnail", "placement",
            "footprint_radius", "surface_height", "default_elevation",
            "dimensions", "front_direction", "clearance_front",
            "clearance_back", "clearance_left", "clearance_right",
            "surfaces", "styles", "affordances")})
    return matches[:limit]


def centroid(points: list[list[float]]) -> tuple[float, float]:
    return (sum(point[0] for point in points) / len(points),
            sum(point[1] for point in points) / len(points))


def unit(dx: float, dy: float) -> tuple[float, float]:
    length = math.hypot(dx, dy)
    if length < 1e-6:
        raise ValueError("relationship direction has zero length")
    return dx / length, dy / length


def heading_toward(origin: tuple[float, float], target: tuple[float, float]) -> float:
    return math.degrees(math.atan2(target[1] - origin[1], target[0] - origin[0])) % 360


def against_wall(room: dict[str, Any], wall: str, clearance: float) -> tuple[tuple[float, float], float]:
    points = room["points"]
    center = centroid(points)
    candidates: list[tuple[float, int, tuple[float, float], tuple[float, float]]] = []
    for index, first in enumerate(points):
        second = points[(index + 1) % len(points)]
        middle = ((first[0] + second[0]) / 2, (first[1] + second[1]) / 2)
        direction = unit(second[0] - first[0], second[1] - first[1])
        if wall == "north": score = -middle[1]
        elif wall == "south": score = middle[1]
        elif wall == "east": score = -middle[0]
        elif wall == "west": score = middle[0]
        elif wall == "nearest": score = math.hypot(middle[0] - center[0], middle[1] - center[1])
        else: raise ValueError("wall must be north, south, east, west, or nearest")
        candidates.append((score, index, middle, direction))
    _, _, middle, direction = min(candidates, key=lambda item: item[0])
    normals = [(-direction[1], direction[0]), (direction[1], -direction[0])]
    inward = min(normals, key=lambda normal: math.hypot(
        middle[0] + normal[0] * .1 - center[0], middle[1] + normal[1] * .1 - center[1]))
    candidate = (middle[0] + inward[0] * clearance, middle[1] + inward[1] * clearance)
    return candidate, heading_toward(candidate, center)


def resolve_placement(level: dict[str, Any], catalog: dict[str, Any], room_id: str,
                      catalog_id: str, relationship: str, target_id: str | None,
                      distance: float, wall: str, rotation: float | None) -> dict[str, Any]:
    room = room_for(level, room_id)
    assets = catalog_objects(catalog)
    if catalog_id not in assets:
        raise ValueError(f"unknown catalog object: {catalog_id}")
    asset = assets[catalog_id]
    radius = max(float(asset.get("footprint_radius", .25)), .1)
    support_id = ""
    elevation = float(asset.get("default_elevation", 0.0))
    center = centroid(room["points"])
    resolved_rotation = 0.0
    if relationship == "center_of_room":
        resolved = center
    elif relationship == "against_wall":
        resolved, resolved_rotation = against_wall(room, wall, radius + distance)
    elif relationship in {"beside", "in_front_of", "facing", "on_surface"}:
        if not target_id:
            raise ValueError(f"{relationship} requires --target")
        target = object_for(level, target_id)
        if target.get("story", 0) != room.get("story", 0) or not point_in_polygon(position(target), room["points"]):
            raise ValueError(f"target {target_id} is not in room {room_id}")
        target_position = position(target)
        target_rotation = math.radians(float(target.get("rotation", 0.0)))
        target_asset = assets.get(target.get("catalog_id", ""), {})
        target_radius = max(float(target_asset.get("footprint_radius", .25)), .1)
        separation = radius + target_radius + distance
        if relationship == "beside":
            direction = (-math.sin(target_rotation), math.cos(target_rotation))
            resolved = (target_position[0] + direction[0] * separation,
                        target_position[1] + direction[1] * separation)
            resolved_rotation = float(target.get("rotation", 0.0))
        elif relationship == "in_front_of":
            direction = (math.cos(target_rotation), math.sin(target_rotation))
            resolved = (target_position[0] + direction[0] * separation,
                        target_position[1] + direction[1] * separation)
            resolved_rotation = heading_toward(resolved, target_position)
        elif relationship == "facing":
            direction = unit(center[0] - target_position[0], center[1] - target_position[1])
            resolved = (target_position[0] + direction[0] * separation,
                        target_position[1] + direction[1] * separation)
            resolved_rotation = heading_toward(resolved, target_position)
        else:
            surface = float(target_asset.get("surface_height", 0.0))
            if surface <= 0:
                raise ValueError(f"target {target_id} has no authored support surface")
            resolved = target_position
            elevation = float(target.get("elevation", 0.0)) + surface
            support_id = target_id
            resolved_rotation = float(target.get("rotation", 0.0))
    else:
        raise ValueError(f"unsupported relationship: {relationship}")
    if rotation is not None:
        resolved_rotation = rotation % 360
    return {
        "catalog_id": catalog_id, "room_id": room_id, "story": room.get("story", 0),
        "position": [round(resolved[0], 3), round(resolved[1], 3)],
        "rotation": round(resolved_rotation, 3), "elevation": round(elevation, 3),
        "support_id": support_id, "footprint_radius": radius,
    }


def render_plan_svg(level: dict[str, Any], catalog: dict[str, Any], room_id: str, output: Path) -> None:
    data = inspect_room(level, catalog, room_id)
    min_x, min_y, max_x, max_y = data["bounds"]
    scale = min(760 / max(max_x - min_x, 1), 620 / max(max_y - min_y, 1))
    margin = 70
    width = (max_x - min_x) * scale + margin * 2
    height = (max_y - min_y) * scale + margin * 2
    def sx(x: float) -> float: return margin + (x - min_x) * scale
    def sy(y: float) -> float: return height - margin - (y - min_y) * scale
    polygon = " ".join(f"{sx(p[0]):.1f},{sy(p[1]):.1f}" for p in data["points"])
    shapes = []
    for item in data["objects"]:
        radius = max(float(item.get("footprint_radius") or .25) * scale, 5)
        x, y = item["position"]
        label = html.escape(str(item["catalog_id"]))
        shapes.append(f'<circle cx="{sx(x):.1f}" cy="{sy(y):.1f}" r="{radius:.1f}" fill="#a97850" fill-opacity=".72" stroke="#38291f"/>')
        shapes.append(f'<text x="{sx(x):.1f}" y="{sy(y)+4:.1f}" text-anchor="middle">{label}</text>')
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" viewBox="0 0 {width:.1f} {height:.1f}">
<style>text{{font:12px system-ui;fill:#241d18}} .title{{font-size:20px;font-weight:700}}</style>
<rect width="100%" height="100%" fill="#eee8dd"/><text class="title" x="{margin}" y="35">{html.escape(data['name'])} · canonical plan</text>
<polygon points="{polygon}" fill="#d7c7ac" stroke="#302921" stroke-width="5"/>{''.join(shapes)}
</svg>'''
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(svg, encoding="utf-8")


def engine_transaction(engine: Path, level_path: Path, catalog_path: Path, mode: str,
                       candidate: dict[str, Any]) -> dict[str, Any]:
    if not engine.exists():
        raise ValueError(f"engine executable not found at {engine}; run make build")
    command = [str(engine), "--agent-object-transaction", mode, str(level_path), str(catalog_path),
               candidate["id"], candidate["catalog_id"],
               str(candidate["position"][0]), str(candidate["position"][1]),
               str(candidate["elevation"]), str(candidate["rotation"]),
               candidate.get("support_id", ""), str(candidate["story"])]
    completed = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    output = completed.stdout.strip().splitlines()
    if not output:
        raise ValueError(completed.stderr.strip() or "engine transaction produced no result")
    result = json.loads(output[-1])
    result["engine_validated"] = True
    if completed.returncode not in (0, 2):
        raise ValueError(completed.stderr.strip() or f"engine transaction failed ({completed.returncode})")
    return result


def engine_validate(engine: Path, level_path: Path) -> dict[str, Any]:
    if not engine.exists():
        raise ValueError(f"engine executable not found at {engine}; run make build")
    completed = subprocess.run([str(engine), "--agent-level-validate", str(level_path)],
                               cwd=ROOT, text=True, capture_output=True)
    output = completed.stdout.strip().splitlines()
    if not output:
        raise ValueError(completed.stderr.strip() or "engine validation produced no result")
    result = json.loads(output[-1]); result["engine_validated"] = True
    return result


def render_canonical(engine: Path, level_path: Path, room_id: str, output: Path) -> None:
    if not engine.exists():
        raise ValueError(f"engine executable not found at {engine}; run make build")
    if output.suffix.lower() != ".png":
        raise ValueError("production canonical renders must use a .png output path")
    completed = subprocess.run(
        [str(engine), "--capture-agent-room", room_id, f"--level={level_path}",
         f"--capture-output={output.resolve()}"], cwd=ROOT, text=True,
        capture_output=True)
    if completed.returncode != 0 or not output.exists():
        raise ValueError(completed.stderr.strip() or completed.stdout.strip() or "canonical render failed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--level", type=Path, default=DEFAULT_LEVEL)
    result.add_argument("--catalog", type=Path, default=DEFAULT_CATALOG)
    result.add_argument("--engine", type=Path, default=DEFAULT_ENGINE)
    commands = result.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect-room"); inspect.add_argument("room_id")
    search = commands.add_parser("search-catalog"); search.add_argument("query", nargs="?", default=""); search.add_argument("--category"); search.add_argument("--placement"); search.add_argument("--limit", type=int, default=20)
    validation = commands.add_parser("validate"); validation.add_argument("--room")
    render = commands.add_parser("render-room"); render.add_argument("room_id"); render.add_argument("--output", type=Path, required=True)
    plan = commands.add_parser("render-plan"); plan.add_argument("room_id"); plan.add_argument("--output", type=Path, required=True)
    for name in ("preview-placement", "place-object"):
        place = commands.add_parser(name); place.add_argument("object_id"); place.add_argument("catalog_id"); place.add_argument("--room", required=True)
        place.add_argument("--relationship", choices=("center_of_room", "against_wall", "beside", "in_front_of", "facing", "on_surface"), required=True)
        place.add_argument("--target"); place.add_argument("--distance", type=float, default=.25); place.add_argument("--wall", default="nearest"); place.add_argument("--rotation", type=float)
    return result


def main() -> int:
    args = parser().parse_args()
    level = load_toml(args.level)
    catalog = load_toml(args.catalog)
    if args.command == "inspect-room": result = inspect_room(level, catalog, args.room_id)
    elif args.command == "search-catalog": result = search_catalog(catalog, args.query, args.category, args.placement, args.limit)
    elif args.command == "validate":
        result = engine_validate(args.engine, args.level)
        if args.room: result["room"] = inspect_room(level, catalog, args.room)
    elif args.command == "render-room":
        render_canonical(args.engine, args.level, args.room_id, args.output)
        result = {"render": str(args.output.resolve()), "room_id": args.room_id, "kind": "production_canonical"}
    elif args.command == "render-plan":
        render_plan_svg(level, catalog, args.room_id, args.output)
        result = {"render": str(args.output.resolve()), "room_id": args.room_id, "kind": "diagnostic_plan"}
    else:
        placement = resolve_placement(level, catalog, args.room, args.catalog_id, args.relationship, args.target, args.distance, args.wall, args.rotation)
        candidate = dict(placement, id=args.object_id)
        engine_result = engine_transaction(args.engine, args.level, args.catalog,
                                           "commit" if args.command == "place-object" else "preview",
                                           candidate)
        result = {"state": engine_result["state"], "message": engine_result.get("message", ""),
                  "candidate": dict(candidate, position=engine_result.get("position", candidate["position"])),
                  "engine_validated": True,
                  "diff": {"operation": "add", "collection": "objects",
                           "after": dict(candidate, position=engine_result.get("position", candidate["position"]))}}
        if args.command == "place-object":
            if result["state"] == "blocked":
                print(json.dumps(result, indent=2)); return 2
            result["committed"] = True
            result["level"] = str(args.level.resolve())
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, tomllib.TOMLDecodeError) as error:
        print(json.dumps({"error": str(error)}))
        raise SystemExit(2)
