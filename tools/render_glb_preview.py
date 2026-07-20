#!/usr/bin/env python3
"""Small dependency-light GLB preview renderer used for asset verification."""

import json
import struct
import sys
from pathlib import Path

import cv2
import numpy as np


def load_glb(path):
    data = Path(path).read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2
    off = 12
    json_len, _ = struct.unpack_from("<I4s", data, off); off += 8
    doc = json.loads(data[off:off + json_len]); off += json_len
    bin_len, _ = struct.unpack_from("<I4s", data, off); off += 8
    blob = data[off:off + bin_len]

    def accessor(index):
        acc = doc["accessors"][index]
        view = doc["bufferViews"][acc["bufferView"]]
        types = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}
        widths = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
        width = widths[acc["type"]]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        out = np.frombuffer(blob, dtype=types[acc["componentType"]], count=acc["count"] * width, offset=start)
        return out.reshape((-1, width)) if width > 1 else out

    texture = None
    if doc.get("images"):
        image_view = doc["bufferViews"][doc["images"][0]["bufferView"]]
        start = image_view.get("byteOffset", 0)
        encoded = np.frombuffer(blob, np.uint8, image_view["byteLength"], start)
        texture = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    meshes = []
    for prim in doc["meshes"][0]["primitives"]:
        pbr = doc["materials"][prim["material"]]["pbrMetallicRoughness"]
        color = pbr.get("baseColorFactor", [1, 1, 1, 1])[:3]
        texcoords = accessor(prim["attributes"]["TEXCOORD_0"]) if "TEXCOORD_0" in prim["attributes"] else None
        meshes.append((accessor(prim["attributes"]["POSITION"]), accessor(prim["indices"]).reshape((-1, 3)), np.array(color), texcoords, texture))
    return meshes


def render(meshes, out_path, size=900):
    image = np.zeros((size, size, 3), np.uint8)
    image[:] = (48, 44, 41)
    depth = np.full((size, size), np.inf, np.float32)
    all_v = np.concatenate([m[0] for m in meshes])
    center = (all_v.min(0) + all_v.max(0)) * 0.5
    camera = center + np.array([1.25, 0.25, 2.2], np.float32)
    forward = center - camera; forward /= np.linalg.norm(forward)
    right = np.cross(forward, np.array([0, 1, 0], np.float32)); right /= np.linalg.norm(right)
    up = np.cross(right, forward)
    extent = max(np.ptp(all_v @ right), np.ptp(all_v @ up))
    scale = size * 0.78 / extent
    light = np.array([-0.5, 0.8, 0.65], np.float32); light /= np.linalg.norm(light)

    for verts, triangles, color, texcoords, texture in meshes:
        rel = verts - center
        screen = np.column_stack((size / 2 + rel @ right * scale, size / 2 - rel @ up * scale, (verts - camera) @ forward))
        base = color[::-1] * 255.0
        for tri in triangles:
            world = verts[tri]
            normal = np.cross(world[1] - world[0], world[2] - world[0])
            length = np.linalg.norm(normal)
            if length < 1e-8:
                continue
            normal /= length
            # Generated project assets use clockwise top faces; orient the
            # verification normal toward the camera instead of dropping them.
            if np.dot(normal, camera - world.mean(0)) <= 0:
                normal = -normal
            p = screen[tri]
            xmin = max(0, int(np.floor(p[:, 0].min()))); xmax = min(size - 1, int(np.ceil(p[:, 0].max())))
            ymin = max(0, int(np.floor(p[:, 1].min()))); ymax = min(size - 1, int(np.ceil(p[:, 1].max())))
            if xmin > xmax or ymin > ymax:
                continue
            x, y = np.meshgrid(np.arange(xmin, xmax + 1), np.arange(ymin, ymax + 1))
            den = (p[1, 1] - p[2, 1]) * (p[0, 0] - p[2, 0]) + (p[2, 0] - p[1, 0]) * (p[0, 1] - p[2, 1])
            if abs(den) < 1e-8:
                continue
            w0 = ((p[1, 1] - p[2, 1]) * (x - p[2, 0]) + (p[2, 0] - p[1, 0]) * (y - p[2, 1])) / den
            w1 = ((p[2, 1] - p[0, 1]) * (x - p[2, 0]) + (p[0, 0] - p[2, 0]) * (y - p[2, 1])) / den
            w2 = 1.0 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            z = w0 * p[0, 2] + w1 * p[1, 2] + w2 * p[2, 2]
            region = depth[ymin:ymax + 1, xmin:xmax + 1]
            take = inside & (z < region)
            if not take.any():
                continue
            region[take] = z[take]
            shade = 0.52 + 0.48 * max(0.0, float(np.dot(normal, light)))
            target = image[ymin:ymax + 1, xmin:xmax + 1]
            if texture is not None and texcoords is not None:
                tri_uv = texcoords[tri]
                u = np.mod(w0 * tri_uv[0, 0] + w1 * tri_uv[1, 0] + w2 * tri_uv[2, 0], 1.0)
                v = np.mod(w0 * tri_uv[0, 1] + w1 * tri_uv[1, 1] + w2 * tri_uv[2, 1], 1.0)
                tx = np.clip((u * (texture.shape[1] - 1)).astype(np.int32), 0, texture.shape[1] - 1)
                ty = np.clip(((1.0 - v) * (texture.shape[0] - 1)).astype(np.int32), 0, texture.shape[0] - 1)
                sampled = texture[ty, tx].astype(np.float32) * color[::-1]
                target[take] = np.clip(sampled[take] * shade, 0, 255).astype(np.uint8)
            else:
                target[take] = np.clip(base * shade, 0, 255).astype(np.uint8)

    cv2.imwrite(str(out_path), image)


if __name__ == "__main__":
    render(load_glb(sys.argv[1]), sys.argv[2])
    print(sys.argv[2])
