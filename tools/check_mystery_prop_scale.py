"""Validate exported mystery GLB bounds against the real-world scale contract."""

from __future__ import annotations

import json
import struct
from pathlib import Path

from mystery_prop_scale import target_max_span_m


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/models/mysteries"


def multiply(a, b):
    return [[sum(a[row][k] * b[k][col] for k in range(4)) for col in range(4)] for row in range(4)]


def node_matrix(node):
    if "matrix" in node:
        values = node["matrix"]
        return [[values[col * 4 + row] for col in range(4)] for row in range(4)]
    tx, ty, tz = node.get("translation", (0, 0, 0))
    sx, sy, sz = node.get("scale", (1, 1, 1))
    x, y, z, w = node.get("rotation", (0, 0, 0, 1))
    return [
        [(1 - 2*y*y - 2*z*z)*sx, (2*x*y - 2*z*w)*sy, (2*x*z + 2*y*w)*sz, tx],
        [(2*x*y + 2*z*w)*sx, (1 - 2*x*x - 2*z*z)*sy, (2*y*z - 2*x*w)*sz, ty],
        [(2*x*z - 2*y*w)*sx, (2*y*z + 2*x*w)*sy, (1 - 2*x*x - 2*y*y)*sz, tz],
        [0, 0, 0, 1],
    ]


def glb_dimensions(path: Path):
    data = path.read_bytes()
    json_length, _ = struct.unpack_from("<II", data, 12)
    gltf = json.loads(data[20:20 + json_length])
    nodes = gltf.get("nodes", [])
    children = {child for node in nodes for child in node.get("children", [])}
    roots = [index for index in range(len(nodes)) if index not in children]
    points = []

    def visit(index, parent):
        node = nodes[index]
        world = multiply(parent, node_matrix(node))
        if "mesh" in node:
            for primitive in gltf["meshes"][node["mesh"]]["primitives"]:
                accessor_index = primitive.get("attributes", {}).get("POSITION")
                if accessor_index is None:
                    continue
                accessor = gltf["accessors"][accessor_index]
                low, high = accessor.get("min"), accessor.get("max")
                if low is None or high is None:
                    continue
                for px in (low[0], high[0]):
                    for py in (low[1], high[1]):
                        for pz in (low[2], high[2]):
                            vector = (px, py, pz, 1)
                            points.append([sum(world[row][k] * vector[k] for k in range(4)) for row in range(3)])
        for child in node.get("children", []):
            visit(child, world)

    identity = [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]]
    for root in roots:
        visit(root, identity)
    low = [min(point[axis] for point in points) for axis in range(3)]
    high = [max(point[axis] for point in points) for axis in range(3)]
    return [high[axis] - low[axis] for axis in range(3)]


def main() -> int:
    manifest = json.loads((ASSETS / "manifest.json").read_text())["models"]
    errors = []
    for entry in manifest:
        dimensions = glb_dimensions(ASSETS / entry["path"])
        actual = max(dimensions)
        expected = target_max_span_m(entry["name"])
        if abs(actual - expected) > max(0.012, expected * 0.025):
            errors.append(f"{entry['name']}: expected {expected:.3f} m, got {actual:.3f} m ({dimensions})")
    # These sentinels catch the historical Y/Z double-conversion directly.
    for name in ("Connecting suite door", "Projection booth door"):
        entry = next(item for item in manifest if item["name"] == name)
        dimensions = glb_dimensions(ASSETS / entry["path"])
        if dimensions[1] < 1.8:
            errors.append(f"{name}: expected upright Y extent, got {dimensions}")
    if errors:
        print("Mystery prop scale: FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print(f"Mystery prop scale: OK ({len(manifest)} exported GLBs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
