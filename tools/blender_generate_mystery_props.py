"""Build an authored low-poly mystery-prop library with Blender.

Run headlessly from the repository root:
  Blender --background --python tools/blender_generate_mystery_props.py

The script keeps the inventory manifest as the asset contract, but replaces the
earlier primitive-only blockouts with semantic multi-part Blender meshes.  Every
file remains independently replaceable by a hand-authored hero asset later.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
import sys

import bpy
from mathutils import Euler
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mystery_prop_scale import target_max_span_m


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/models/mysteries"
MANIFEST = OUT / "manifest.json"
P0_HERO_PATHS = {
    "bellwether-mysteries/the-last-garden-prize/silver-garden-prize-cup.glb",
    "bellwether-mysteries/the-last-garden-prize/cast-iron-hose-guide.glb",
    "bellwether-mysteries/the-last-garden-prize/exhibition-plant-cart.glb",
    "bellwether-mysteries/the-last-garden-prize/prize-orchid-and-display-pot.glb",
    "bellwether-mysteries/a-recipe-for-silence/engraved-tasting-spoon.glb",
    "bellwether-mysteries/a-recipe-for-silence/herb-jars.glb",
    "one-more-question/a-private-performance/heavy-mechanical-metronome.glb",
    "one-more-question/the-final-cut/film-projector.glb",
    "one-more-question/a-private-performance/violin-bow-and-fitted-case.glb",
    "one-more-question/the-perfect-vintage/rare-hero-bottle.glb",
    "the-blackthorn-papers/the-ashes-of-blackthorn-lane/brass-cartographer-s-divider.glb",
    "one-more-question/the-architect-s-model/modular-tower-scale-model.glb",
    "the-blackthorn-papers/the-empty-carriage/inspection-rail-carriage.glb",
}


PALETTE = {
    "wood": (0.19, 0.075, 0.025, 1), "dark_wood": (0.055, 0.02, 0.008, 1),
    "brass": (0.52, 0.27, 0.035, 1), "steel": (0.035, 0.20, 0.24, 1),
    "black": (0.018, 0.024, 0.03, 1), "paper": (0.61, 0.49, 0.29, 1),
    "cloth": (0.20, 0.045, 0.05, 1), "green": (0.03, 0.22, 0.075, 1),
    "leaf": (0.015, 0.34, 0.08, 1), "glass": (0.08, 0.25, 0.20, 1),
    "ceramic": (0.68, 0.58, 0.43, 1), "red": (0.42, 0.025, 0.018, 1),
    "concrete": (0.27, 0.27, 0.25, 1), "rail": (0.10, 0.12, 0.13, 1),
    "gold": (0.72, 0.44, 0.07, 1), "white": (0.72, 0.70, 0.62, 1),
}


def clear() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for material in list(bpy.data.materials):
        bpy.data.materials.remove(material)


def mat(name: str, key: str, metallic: float = 0.0, roughness: float = 0.5) -> bpy.types.Material:
    material = bpy.data.materials.get(name)
    if material:
        return material
    material = bpy.data.materials.new(name)
    material.diffuse_color = PALETTE[key]
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = PALETTE[key]
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def finish(obj: bpy.types.Object, material: bpy.types.Material, bevel: float = 0.0) -> bpy.types.Object:
    obj.data.materials.append(material)
    if bevel > 0 and obj.type == "MESH":
        modifier = obj.modifiers.new("soft edges", "BEVEL")
        modifier.width = bevel
        modifier.segments = 2
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def cube(name: str, loc, scale, material, bevel: float = 0.02):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, material, bevel)


def cyl(name: str, loc, radius: float, depth: float, material, vertices: int = 16, rotation=None, bevel: float = 0.01):
    # Blender primitives are Z-long by default.  Authoring in this project is
    # Y-up, so callers describe an adjustment from a Y-up primitive.
    base = Euler((math.pi / 2, 0, 0))
    adjustment = Euler(rotation or (0, 0, 0))
    final_rotation = (adjustment.to_matrix() @ base.to_matrix()).to_euler()
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=final_rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material, bevel)


def sphere(name: str, loc, radius: float, material, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=radius, location=loc)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, material)


def cone(name: str, loc, radius1: float, radius2: float, depth: float, material, vertices: int = 16, rotation=None):
    base = Euler((math.pi / 2, 0, 0))
    adjustment = Euler(rotation or (0, 0, 0))
    final_rotation = (adjustment.to_matrix() @ base.to_matrix()).to_euler()
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=loc, rotation=final_rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material, 0.01)


def torus(name: str, loc, major: float, minor: float, material, rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=16, minor_segments=6, location=loc, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    return finish(obj, material)


def curve(name: str, points, radius: float, material):
    curve_data = bpy.data.curves.new(name, "CURVE")
    curve_data.dimensions = "3D"
    curve_data.bevel_depth = radius
    curve_data.bevel_resolution = 2
    spline = curve_data.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, co in zip(spline.bezier_points, points):
        point.co = co
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve_data)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(material)
    return obj


def wheel(loc, radius=0.16, width=0.07):
    return cyl("wheel", loc, radius, width, mat("rubber", "black", 0.0, 0.85), 16, (math.pi / 2, 0, 0))


def add_table(name: str):
    key = name.lower()
    wood = mat("wood", "wood", 0.0, 0.36)
    steel = mat("steel", "steel", 0.72, 0.26)
    if "plinth" in key:
        cube("gallery plinth", (0, 0.48, 0), (0.58, 0.96, 0.58), mat("plinth stone", "ceramic"), 0.045)
        cube("plinth cap", (0, 0.99, 0), (0.70, 0.09, 0.70), mat("plinth cap", "brass"), 0.02)
        return
    if any(word in key for word in ("podium", "lectern")):
        cube("podium base", (0, 0.38, 0), (0.74, 0.76, 0.52), wood, 0.04)
        top = cube("sloped lectern top", (0, 0.84, -0.05), (0.82, 0.09, 0.60), mat("lectern top", "dark_wood"), 0.025)
        top.rotation_euler[0] = math.radians(18)
        cube("page rail", (0, 0.88, -0.30), (0.62, 0.05, 0.05), mat("lectern rail", "brass"), 0.008)
        return
    if any(word in key for word in ("workbench", "potting bench")):
        cube("bench top", (0, 0.82, 0), (1.55, 0.12, 0.86), wood, 0.03)
        cube("bench shelf", (0, 0.30, 0), (1.38, 0.08, 0.72), mat("bench shelf", "dark_wood"), 0.02)
        for x in (-0.65, 0.65):
            cube("bench leg", (x, 0.40, 0), (0.09, 0.80, 0.09), steel, 0.01)
        return
    cube("top", (0, 0.82, 0), (1.5, 0.10, 0.88), wood, 0.035)
    for x in (-0.61, 0.61):
        for z in (-0.32, 0.32):
            cube("leg", (x, 0.40, z), (0.08, 0.8, 0.08), steel, 0.01)
    cube("drawer", (0, 0.66, 0.38), (0.75, 0.22, 0.12), wood, 0.02)


def add_cart(name: str):
    key = name.lower()
    steel = mat("steel", "steel", 0.75, 0.24)
    wood = mat("wood", "wood", 0.0, 0.4)
    if any(word in key for word in ("lift", "dumbwaiter")):
        cube("lift cage frame left", (-0.38, 0.70, 0), (0.07, 1.40, 0.62), steel, 0.02)
        cube("lift cage frame right", (0.38, 0.70, 0), (0.07, 1.40, 0.62), steel, 0.02)
        cube("lift platform", (0, 0.18, 0), (0.82, 0.10, 0.70), wood, 0.025)
        for y in (0.38, 0.70, 1.02):
            cube("lift crossbar", (0, y, 0), (0.72, 0.05, 0.68), steel, 0.008)
        return
    if any(word in key for word in ("serving", "linen", "trolley")):
        for y in (0.38, 0.82):
            cube("trolley tray", (0, y, 0), (1.30, 0.07, 0.76), wood, 0.025)
        for x in (-0.58, 0.58):
            for z in (-0.30, 0.30):
                wheel((x, 0.16, z), 0.13, 0.06)
        cube("trolley handle", (0.72, 0.68, 0), (0.06, 0.70, 0.70), steel, 0.02)
        return
    cube("platform", (0, 0.38, 0), (1.45, 0.10, 0.84), wood, 0.03)
    for x in (-0.57, 0.57):
        for z in (-0.30, 0.30):
            wheel((x, 0.16, z))
    for z in (-0.36, 0.36):
        curve("handle", [(0.67, 0.40, z), (0.85, 0.63, z), (0.97, 0.68, z)], 0.03, steel)
    cube("side rail", (-0.62, 0.63, 0), (0.04, 0.52, 0.82), steel, 0.01)


def add_shelf(name: str):
    key = name.lower()
    wood = mat("dark wood", "dark_wood", 0.0, 0.35)
    if "wine rack" in key:
        for y in (0.22, 0.53, 0.84):
            cube("wine rack rail", (0, y, 0), (1.28, 0.06, 0.54), wood, 0.01)
            for x in (-0.42, 0, 0.42):
                cyl("stored bottle", (x, y + 0.08, 0), 0.09, 0.42, mat("rack bottle", "glass", 0.12, 0.2), 12, (0, 0, math.pi / 2), 0.005)
        return
    if any(word in key for word in ("map drawers", "flat file")):
        cube("flat file cabinet", (0, 0.56, 0), (1.18, 1.12, 0.72), wood, 0.035)
        for y in (0.24, 0.48, 0.72, 0.96):
            cube("flat drawer", (0, y, -0.38), (1.04, 0.16, 0.04), mat("drawer face", "paper"), 0.005)
            cyl("drawer pull", (0, y, -0.42), 0.025, 0.04, mat("drawer brass", "brass"), 12, (math.pi / 2, 0, 0))
        return
    cube("left upright", (-0.65, 0.95, 0), (0.08, 1.90, 0.34), wood, 0.02)
    cube("right upright", (0.65, 0.95, 0), (0.08, 1.90, 0.34), wood, 0.02)
    for y in (0.16, 0.72, 1.28, 1.84):
        cube("shelf", (0, y, 0), (1.38, 0.07, 0.42), wood, 0.015)
    for x in (-0.35, -0.12, 0.14, 0.38):
        cube("book", (x, 0.97, 0.02), (0.17, 0.40, 0.30), mat("paper", "paper"), 0.01)


def add_door(name: str):
    key = name.lower()
    wood = mat("door wood", "dark_wood", 0.0, 0.35)
    brass = mat("brass", "brass", 0.8, 0.22)
    steel = mat("door steel", "steel", 0.65, 0.28)
    if any(word in key for word in ("gate", "barrier")):
        for x in (-0.42, 0.42):
            cyl("gate post", (x, 0.62, 0), 0.06, 1.24, steel, 12)
            cone("gate cap", (x, 1.28, 0), 0.10, 0.03, 0.14, brass, 12)
        for y in (0.38, 0.76, 1.12):
            cube("gate rail", (0, y, 0), (0.90, 0.05, 0.06), steel, 0.01)
        return
    if any(word in key for word in ("hatch", "transom")):
        cube("hatch frame", (0, 0.12, 0), (1.08, 0.14, 0.80), steel, 0.035)
        cube("hatch inset", (0, 0.20, 0), (0.84, 0.08, 0.58), mat("hatch dark", "black"), 0.018)
        torus("hatch wheel", (0, 0.27, -0.30), 0.13, 0.025, brass, (math.pi / 2, 0, 0))
        return
    if "window" in key:
        cube("window frame", (0, 0.82, 0), (1.20, 1.52, 0.10), wood, 0.02)
        cube("window glass", (0, 0.82, -0.06), (1.02, 1.32, 0.015), mat("window glass", "glass", 0.05, 0.12), 0.002)
        cube("window mullion", (0, 0.82, -0.08), (0.05, 1.36, 0.025), wood, 0.004)
        cube("window rail", (0, 0.82, -0.08), (1.06, 0.05, 0.025), wood, 0.004)
        return
    cube("door slab", (0, 1.05, 0), (1.10, 2.10, 0.10), wood, 0.025)
    for y in (0.54, 1.05, 1.56):
        cube("panel", (0, y, 0.058), (0.82, 0.36, 0.025), mat("panel wood", "wood"), 0.01)
    cyl("knob", (0.34, 1.02, 0.11), 0.055, 0.08, brass, 12, (math.pi / 2, 0, 0))
    cube("latch", (0.34, 1.02, 0.16), (0.16, 0.05, 0.04), brass, 0.005)


def add_bottle(name: str):
    key = name.lower()
    glass = mat("bottle glass", "glass", 0.05, 0.18)
    label = mat("label", "paper", 0.0, 0.68)
    if "glass" in key:
        clear_glass = mat("clear glass", "glass", 0.05, 0.12)
        if any(word in key for word in ("wine", "tasting")):
            cyl("wine glass foot", (-0.18, 0.05, 0), 0.17, 0.035, clear_glass, 20)
            cyl("wine glass stem", (-0.18, 0.24, 0), 0.025, 0.40, clear_glass, 12)
            cone("wine glass bowl", (-0.18, 0.54, 0), 0.17, 0.11, 0.36, clear_glass, 16)
        else:
            cyl("water tumbler", (-0.16, 0.22, 0), 0.16, 0.40, clear_glass, 16, bevel=0.01)
        cyl("whisky tumbler", (0.25, 0.14, 0), 0.17, 0.26, clear_glass, 12, bevel=0.01)
        return
    if "decanter" in key or "carafe" in key:
        sphere("decanter body", (0, 0.36, 0), 0.31, glass, (1.0, 1.12, 1.0))
        cone("decanter shoulder", (0, 0.70, 0), 0.23, 0.08, 0.28, glass, 16)
        cyl("decanter neck", (0, 0.91, 0), 0.08, 0.25, glass, 16)
        cone("decanter stopper", (0, 1.09, 0), 0.11, 0.06, 0.15, mat("stopper", "brass"), 12)
        return
    if "jar" in key:
        cyl("wide jar body", (0, 0.30, 0), 0.29, 0.54, glass, 12, bevel=0.015)
        cyl("jar lid", (0, 0.60, 0), 0.31, 0.08, mat("jar lid", "brass", 0.55, 0.25), 16, bevel=0.01)
        cube("jar label", (0, 0.32, -0.29), (0.32, 0.20, 0.01), label, 0.002)
        return
    if any(word in key for word in ("vial", "applicator", "chemical")):
        cyl("small vial", (0, 0.23, 0), 0.11, 0.42, glass, 12, bevel=0.01)
        cyl("vial cap", (0, 0.47, 0), 0.12, 0.10, mat("vial cap", "red"), 12)
        cube("vial label", (0, 0.22, -0.112), (0.14, 0.12, 0.008), label, 0.002)
        return
    if "wine" in key:
        cyl("wine bottle body", (0, 0.43, 0), 0.25, 0.78, mat("wine glass", "green", 0.10, 0.16), 16, bevel=0.015)
        cone("wine shoulder", (0, 0.89, 0), 0.25, 0.075, 0.22, mat("wine shoulder glass", "green", 0.10, 0.16), 16)
        cyl("wine neck", (0, 1.08, 0), 0.07, 0.28, mat("wine neck glass", "green", 0.10, 0.16), 16)
        cyl("wine foil", (0, 1.22, 0), 0.085, 0.08, mat("wine foil", "gold", 0.55, 0.22), 16)
        cube("wine label", (0, 0.46, -0.255), (0.25, 0.34, 0.01), label, 0.002)
        return
    cyl("body", (0, 0.40, 0), 0.23, 0.72, glass)
    cone("shoulder", (0, 0.79, 0), 0.23, 0.09, 0.20, glass)
    cyl("neck", (0, 0.99, 0), 0.075, 0.28, glass)
    cyl("cap", (0, 1.15, 0), 0.09, 0.06, mat("cap", "brass", 0.5, 0.3))
    cube("label", (0, 0.44, -0.235), (0.22, 0.30, 0.01), label, 0.001)


def add_clock(name: str):
    key = name.lower()
    brass = mat("clock brass", "brass", 0.78, 0.2)
    face = mat("clock face", "paper", 0, 0.75)
    if "gauge" in key or "thermometer" in key:
        cyl("gauge housing", (0, 0.48, 0), 0.36, 0.16, brass, 20, (math.pi / 2, 0, 0))
        cyl("gauge face", (0, 0.48, -0.085), 0.29, 0.015, face, 20, (math.pi / 2, 0, 0))
        cube("gauge needle", (0.08, 0.56, -0.10), (0.025, 0.25, 0.02), mat("gauge needle", "red"), 0.002)
        cyl("gauge pipe", (0, 0.12, 0), 0.08, 0.42, mat("gauge pipe", "steel"), 16)
        return
    if "timer" in key:
        cyl("kitchen timer body", (0, 0.24, 0), 0.32, 0.38, mat("timer ceramic", "red"), 20, bevel=0.02)
        cyl("timer face", (0, 0.28, -0.325), 0.23, 0.02, face, 20, (math.pi / 2, 0, 0))
        cone("timer knob", (0, 0.50, 0), 0.13, 0.06, 0.13, brass, 16)
        return
    if "mantel" in key:
        cube("mantel clock body", (0, 0.43, 0), (0.84, 0.76, 0.26), mat("mantel wood", "wood"), 0.05)
        cyl("mantel face", (0, 0.46, -0.145), 0.25, 0.018, face, 20, (math.pi / 2, 0, 0))
        cube("mantel foot", (-0.28, 0.06, 0), (0.14, 0.12, 0.24), brass, 0.015)
        cube("mantel foot", (0.28, 0.06, 0), (0.14, 0.12, 0.24), brass, 0.015)
        return
    cube("base", (0, 0.10, 0), (0.78, 0.20, 0.30), brass, 0.03)
    cyl("clock body", (0, 0.54, 0), 0.34, 0.16, brass, 20, (math.pi / 2, 0, 0))
    cyl("face", (0, 0.54, -0.085), 0.27, 0.015, face, 20, (math.pi / 2, 0, 0))
    cube("hour hand", (0.05, 0.54, -0.10), (0.20, 0.025, 0.02), mat("hands", "black"), 0.002)
    cube("minute hand", (-0.025, 0.64, -0.10), (0.025, 0.25, 0.02), mat("hands", "black"), 0.002)


def add_instrument(name: str):
    key = name.lower()
    wood = mat("instrument wood", "wood", 0.0, 0.3)
    black = mat("ebony", "black", 0.0, 0.38)
    if "double bass" in key and "case" in key:
        case = mat("bass case", "cloth", 0, 0.45)
        sphere("bass case lower", (0, 0.38, 0), 0.34, case, (0.96, 1.30, 0.38))
        sphere("bass case upper", (0, 0.82, 0), 0.24, case, (0.90, 1.20, 0.38))
        cube("bass case neck", (0, 1.28, 0), (0.12, 0.64, 0.10), case, 0.025)
        for x in (-0.18, 0.18):
            wheel((x, 0.12, 0), 0.11, 0.06)
        return
    if "mute" in key:
        cone("orchestral mute", (0, 0.24, 0), 0.26, 0.08, 0.48, mat("mute wood", "wood"), 12)
        cyl("mute cork", (0, 0.50, 0), 0.08, 0.10, mat("mute cork", "paper"), 12)
        return
    if "bass" in key:
        sphere("lower bout", (0, 0.55, 0), 0.28, wood, (0.8, 1.25, 0.42))
        sphere("upper bout", (0, 0.92, 0), 0.20, wood, (0.8, 1.15, 0.42))
        cube("neck", (0, 1.42, 0), (0.10, 0.78, 0.07), black, 0.01)
    else:
        sphere("lower bout", (0, 0.36, 0), 0.18, wood, (1.0, 1.2, 0.36))
        sphere("upper bout", (0, 0.60, 0), 0.14, wood, (1.0, 1.15, 0.36))
        cube("neck", (0, 0.98, 0), (0.065, 0.55, 0.05), black, 0.008)
    cube("fingerboard", (0, 0.78, -0.035), (0.09, 0.70, 0.03), black, 0.003)
    for offset in (-0.022, -0.007, 0.007, 0.022):
        curve("string", [(offset, 0.25, -0.06), (offset, 1.20, -0.06)], 0.003, mat("strings", "steel", 0.6, 0.3))


def add_projector(name: str):
    key = name.lower()
    steel = mat("projector steel", "steel", 0.7, 0.22)
    black = mat("projector black", "black", 0.1, 0.35)
    if "splicer" in key:
        cube("splicer base", (0, 0.10, 0), (1.05, 0.20, 0.54), black, 0.035)
        for x in (-0.28, 0.28):
            # The reels stand in X/Y with thickness along Z.  Keep their
            # centers above the base so the lower halves are not buried.
            cyl("splicer reel", (x, 0.40, 0), 0.18, 0.055, steel, 16, (math.pi / 2, 0, 0))
            cyl("splicer hub", (x, 0.40, -0.035), 0.045, 0.07, mat("splicer hub", "brass"), 12, (math.pi / 2, 0, 0))
        cube("splice clamp", (0, 0.28, 0), (0.20, 0.18, 0.38), steel, 0.02)
        cube("film strip", (0, 0.39, 0), (0.75, 0.015, 0.06), mat("film", "black"), 0.003)
        return
    if "editing bench" in key:
        cube("editing table", (0, 0.58, 0), (1.45, 0.10, 0.82), mat("editing wood", "wood"), 0.03)
        for x in (-0.58, 0.58):
            for z in (-0.28, 0.28):
                cube("editing bench leg", (x, 0.29, z), (0.07, 0.58, 0.07), steel, 0.01)
        for x in (-0.32, 0.32):
            cyl("editing reel", (x, 0.85, 0), 0.20, 0.05, steel, 16, (math.pi / 2, 0, 0))
        cube("viewer", (0, 0.76, 0.22), (0.28, 0.18, 0.08), black, 0.015)
        return
    cube("projector body", (0, 0.46, 0), (0.80, 0.46, 0.50), black, 0.04)
    cyl("lens", (0.45, 0.49, 0), 0.15, 0.18, steel, 16, (0, math.pi / 2, 0))
    for x in (-0.28, 0.10):
        cyl("reel", (x, 0.90, 0), 0.25, 0.055, steel, 16, (math.pi / 2, 0, 0))
        cyl("hub", (x, 0.90, -0.035), 0.055, 0.07, black, 12, (math.pi / 2, 0, 0))
    for x in (-0.30, 0.30):
        cube("foot", (x, 0.18, 0), (0.10, 0.15, 0.18), steel, 0.01)


def add_rail_car(name: str):
    rail = mat("rail car paint", "rail", 0.35, 0.28)
    brass = mat("rail brass", "brass", 0.65, 0.28)
    cube("carriage shell", (0, 1.0, 0), (3.4, 1.55, 1.05), rail, 0.06)
    cube("roof", (0, 1.82, 0), (3.55, 0.15, 1.15), mat("roof", "black"), 0.05)
    for x in (-1.15, -0.38, 0.38, 1.15):
        cube("window", (x, 1.18, -0.535), (0.45, 0.55, 0.02), mat("window", "glass", 0.1, 0.22), 0.005)
    for x in (-1.12, 1.12):
        for z in (-0.38, 0.38):
            wheel((x, 0.27, z), 0.28, 0.12)
    cube("coupler", (1.84, 0.45, 0), (0.34, 0.12, 0.18), brass, 0.02)


def add_tableware(name: str):
    key = name.lower()
    ceramic = mat("ceramic", "ceramic", 0.0, 0.32)
    metal = mat("cutlery", "steel", 0.72, 0.22)
    if any(word in key for word in ("cookware", "pots", "pans")):
        cyl("cooking pot", (-0.20, 0.18, 0), 0.25, 0.32, mat("copper pot", "brass", 0.65, 0.22), 16, bevel=0.01)
        torus("pot rim", (-0.20, 0.35, 0), 0.25, 0.018, metal)
        cube("pan handle", (0.42, 0.16, 0), (0.62, 0.05, 0.10), metal, 0.015)
        cyl("small pan", (0.24, 0.10, 0), 0.19, 0.10, mat("pan steel", "steel", 0.65, 0.20), 16)
        return
    if any(word in key for word in ("cloche", "serving tray", "serving trays")):
        cyl("serving tray", (0, 0.05, 0), 0.44, 0.06, mat("silver tray", "steel", 0.76, 0.16), 24)
        sphere("serving cloche", (0, 0.24, 0), 0.30, mat("cloche silver", "steel", 0.76, 0.16), (1.0, 0.72, 1.0))
        cyl("cloche handle", (0, 0.47, 0), 0.05, 0.10, mat("cloche brass", "brass"), 16)
        return
    if any(word in key for word in ("place-setting", "place setting", "five-place", "formal five")):
        cyl("charger plate", (0, 0.035, 0), 0.42, 0.05, mat("charger brass", "brass", 0.55, 0.22), 24)
        cyl("formal plate", (0, 0.075, 0), 0.31, 0.05, ceramic, 24)
        for x in (-0.48, 0.48):
            cube("formal cutlery", (x, 0.048, 0), (0.045, 0.018, 0.42), metal, 0.004)
        return
    if "spoon" in key:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.18, location=(0.22, 0.055, 0))
        bowl = bpy.context.object
        bowl.scale = (0.82, 0.18, 1.1)
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        finish(bowl, metal)
        cube("spoon handle", (-0.30, 0.05, 0), (0.86, 0.07, 0.10), metal, 0.03)
    else:
        cyl("plate", (0, 0.045, 0), 0.40, 0.07, ceramic, 24)
        cyl("plate well", (0, 0.09, 0), 0.27, 0.03, mat("plate well", "white"), 24)
        if "bowl" in key:
            cone("bowl", (0, 0.22, 0), 0.28, 0.18, 0.30, ceramic, 24)
        cube("knife", (0.53, 0.055, 0), (0.05, 0.025, 0.42), metal, 0.006)
        cube("fork", (-0.53, 0.055, 0), (0.045, 0.025, 0.42), metal, 0.006)


def add_tripod(name: str):
    brass = mat("survey brass", "brass", 0.75, 0.24)
    for angle in (0, 120, 240):
        a = math.radians(angle)
        leg = cube("tripod leg", (math.cos(a) * 0.25, 0.35, math.sin(a) * 0.25), (0.055, 0.78, 0.055), brass, 0.01)
        leg.rotation_euler[1] = -a
        leg.rotation_euler[2] = math.radians(20)
    cyl("survey head", (0, 0.80, 0), 0.14, 0.16, brass, 16)
    cube("scope", (0, 0.94, 0), (0.42, 0.12, 0.13), mat("scope", "black"), 0.02)


def add_backdrop(name: str):
    cloth = mat("backdrop cloth", "cloth", 0.0, 0.70)
    if "rolled" in name.lower():
        cyl("backdrop roll", (0, 0.35, 0), 0.25, 1.35, cloth, 24, (0, 0, math.pi / 2))
        cube("hanging edge", (0.72, 0.36, 0), (0.04, 0.95, 0.65), cloth, 0.01)
    else:
        cube("painted backdrop", (0, 0.85, 0), (1.6, 1.65, 0.05), cloth, 0.01)
        cyl("top roller", (0, 1.70, 0), 0.05, 1.72, mat("roller", "wood"), 16, (0, 0, math.pi / 2))


def add_seating(name: str):
    key = name.lower()
    fabric = mat("seat fabric", "cloth", 0, 0.78)
    wood = mat("seat wood", "wood", 0, 0.34)
    if any(word in key for word in ("lounge", "sofa", "suite furniture")):
        cube("sofa base", (0, 0.31, 0), (1.32, 0.42, 0.70), fabric, 0.07)
        cube("sofa back", (0, 0.72, 0.25), (1.32, 0.62, 0.18), fabric, 0.07)
        for x in (-0.46, 0.46):
            cube("sofa arm", (x, 0.52, 0), (0.20, 0.48, 0.70), fabric, 0.06)
            cube("sofa foot", (x, 0.09, -0.23), (0.11, 0.18, 0.11), wood, 0.02)
        return
    if any(word in key for word in ("auditorium", "screening", "recital")):
        cube("theater seat cushion", (0, 0.42, 0), (0.84, 0.14, 0.58), fabric, 0.035)
        cube("folding theater back", (0, 0.86, 0.22), (0.84, 0.68, 0.10), fabric, 0.035)
        for x in (-0.34, 0.34):
            cube("theater arm", (x, 0.64, 0), (0.08, 0.12, 0.54), wood, 0.012)
            cube("theater pedestal", (x, 0.18, 0.13), (0.08, 0.36, 0.08), mat("seat steel", "steel"), 0.01)
        return
    if "dining" in key or "formal" in key:
        cube("dining seat", (0, 0.48, 0), (0.62, 0.13, 0.58), fabric, 0.025)
        cube("ladder chair back", (0, 0.89, 0.23), (0.62, 0.66, 0.08), wood, 0.02)
        for y in (0.72, 0.96):
            cube("back rung", (0, y, 0.18), (0.50, 0.05, 0.06), wood, 0.008)
        for x in (-0.24, 0.24):
            for z in (-0.19, 0.19):
                cube("dining chair leg", (x, 0.23, z), (0.06, 0.46, 0.06), wood, 0.008)
        return
    cube("seat cushion", (0, 0.47, 0), (0.70, 0.16, 0.64), fabric, 0.04)
    cube("seat back", (0, 0.90, 0.24), (0.70, 0.70, 0.14), fabric, 0.04)
    for x in (-0.27, 0.27):
        cube("seat leg", (x, 0.23, -0.20), (0.07, 0.45, 0.07), wood, 0.01)
        cube("seat leg", (x, 0.23, 0.20), (0.07, 0.45, 0.07), wood, 0.01)


def add_console(name: str):
    key = name.lower()
    black = mat("console black", "black", 0.1, 0.30)
    brass = mat("console brass", "brass", 0.55, 0.24)
    steel = mat("console steel", "steel", 0.4, 0.30)
    if any(word in key for word in ("computer workstation", "laptop")):
        cube("computer screen", (0, 0.66, 0), (0.92, 0.58, 0.08), black, 0.035)
        cube("screen glow", (0, 0.66, -0.05), (0.76, 0.42, 0.008), mat("screen glow", "glass", 0.1, 0.10), 0.002)
        cyl("screen stand", (0, 0.32, 0), 0.05, 0.32, steel, 12)
        cube("keyboard", (0, 0.12, 0.12), (0.72, 0.06, 0.34), mat("keyboard", "black"), 0.015)
        return
    if any(word in key for word in ("speaker", "monitor")) and "control" not in key:
        cube("speaker cabinet", (0, 0.48, 0), (0.62, 0.96, 0.46), black, 0.06)
        for y, radius in ((0.65, 0.16), (0.30, 0.10)):
            cyl("speaker cone", (0, y, -0.24), radius, 0.03, steel, 16, (math.pi / 2, 0, 0))
        return
    if any(word in key for word in ("playback", "voice recorder", "audio recorder", "recording player")):
        cube("recorder deck", (0, 0.22, 0), (1.05, 0.38, 0.62), black, 0.045)
        for x in (-0.25, 0.25):
            cyl("recorder reel", (x, 0.59, -0.10), 0.16, 0.04, steel, 16, (math.pi / 2, 0, 0))
        cube("recorder controls", (0, 0.43, 0.20), (0.50, 0.04, 0.12), brass, 0.006)
        return
    if "microphone" in key:
        cyl("microphone stand", (0, 0.50, 0), 0.035, 1.0, steel, 12)
        sphere("microphone head", (0, 1.02, 0), 0.13, black, (0.75, 1.0, 0.75))
        torus("microphone grille", (0, 1.02, 0), 0.10, 0.010, steel, (math.pi / 2, 0, 0))
        return
    if any(word in key for word in ("control board", "lighting console", "recording console")):
        cube("console base", (0, 0.32, 0), (1.35, 0.64, 0.76), black, 0.05)
        panel = cube("mixer panel", (0, 0.72, -0.08), (1.25, 0.08, 0.68), steel, 0.012)
        panel.rotation_euler[0] = math.radians(14)
        for x in (-0.45, -0.15, 0.15, 0.45):
            cube("fader", (x, 0.79, -0.08), (0.05, 0.025, 0.34), brass, 0.004)
        return
    cube("console body", (0, 0.42, 0), (1.20, 0.70, 0.70), black, 0.05)
    cube("sloped control face", (0, 0.72, -0.10), (1.08, 0.10, 0.60), mat("control face", "steel", 0.4, 0.3), 0.01)
    for x in (-0.36, -0.12, 0.12, 0.36):
        for z in (-0.22, -0.05, 0.12):
            cyl("dial", (x, 0.80, z), 0.045, 0.035, brass, 12, (math.pi / 2, 0, 0))
    cube("display", (0, 0.83, 0.22), (0.42, 0.07, 0.16), mat("screen", "glass", 0.1, 0.18), 0.005)


def add_costume_rack(name: str):
    steel = mat("rack steel", "steel", 0.72, 0.30)
    cloth = mat("costume cloth", "cloth", 0, 0.74)
    cube("rack base", (0, 0.08, 0), (1.35, 0.10, 0.52), steel, 0.02)
    for x in (-0.54, 0.54):
        cyl("upright", (x, 0.84, 0), 0.035, 1.5, steel, 12)
    cyl("hanging rail", (0, 1.50, 0), 0.035, 1.2, steel, 12, (0, 0, math.pi / 2))
    for x in (-0.32, 0, 0.32):
        curve("hanger", [(x, 1.47, 0), (x - 0.10, 1.25, 0), (x + 0.10, 1.25, 0), (x, 1.47, 0)], 0.012, steel)
        cone("costume", (x, 1.04, 0), 0.18, 0.06, 0.52, cloth, 12)


def add_frame(name: str):
    key = name.lower()
    gold = mat("frame gold", "gold", 0.65, 0.22)
    paper = mat("art image", "paper", 0, 0.72)
    if any(word in key for word in ("seating chart", "map", "poster", "program")):
        cube("noticeboard frame", (0, 0.72, 0), (1.22, 1.04, 0.12), mat("notice wood", "wood"), 0.035)
        cube("pinned chart", (0, 0.72, -0.07), (1.04, 0.84, 0.018), paper, 0.002)
        for x, y in ((-0.38, 0.98), (0.38, 0.98), (-0.38, 0.46), (0.38, 0.46)):
            sphere("push pin", (x, y, -0.10), 0.035, mat("pin", "red"), (1, 0.35, 1))
        return
    if any(word in key for word in ("reflection", "mirror")):
        cube("mirror frame", (0, 0.76, 0), (1.06, 1.48, 0.10), gold, 0.045)
        cube("mirror glass", (0, 0.76, -0.07), (0.84, 1.24, 0.012), mat("mirror", "glass", 0.35, 0.06), 0.002)
        return
    cube("frame", (0, 0.72, 0), (1.10, 1.44, 0.12), gold, 0.04)
    cube("image", (0, 0.72, -0.07), (0.88, 1.20, 0.02), paper, 0.002)
    cube("frame inset", (0, 0.72, -0.09), (0.60, 0.84, 0.01), mat("image contrast", "cloth"), 0.001)


def add_bell(name: str):
    brass = mat("bell brass", "brass", 0.82, 0.18)
    cone("bell dome", (0, 0.31, 0), 0.33, 0.08, 0.42, brass, 24)
    cyl("bell base", (0, 0.09, 0), 0.40, 0.10, mat("bell base", "wood"), 24)
    sphere = None
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.06, location=(0, 0.18, -0.25))
    finish(bpy.context.object, brass, 0.0)
    cyl("bell button", (0, 0.57, 0), 0.05, 0.10, brass, 16)


def add_suitcase(name: str):
    key = name.lower()
    leather = mat("travel leather", "cloth", 0, 0.38)
    brass = mat("luggage brass", "brass", 0.7, 0.24)
    if "hat box" in key:
        cyl("hatbox body", (0, 0.34, 0), 0.38, 0.62, leather, 16, bevel=0.025)
        torus("hatbox trim", (0, 0.57, 0), 0.38, 0.025, brass)
        curve("hatbox handle", [(-0.15, 0.67, 0), (0, 0.82, 0), (0.15, 0.67, 0)], 0.025, leather)
        return
    if "trunk" in key:
        cube("trunk body", (0, 0.37, 0), (1.20, 0.70, 0.62), leather, 0.06)
        cube("trunk lid", (0, 0.74, 0), (1.20, 0.10, 0.62), mat("trunk lid", "wood"), 0.03)
        for x in (-0.48, 0, 0.48):
            cube("trunk strap", (x, 0.41, -0.32), (0.06, 0.64, 0.025), brass, 0.004)
        return
    cube("suitcase shell", (0, 0.30, 0), (1.12, 0.60, 0.34), leather, 0.06)
    cube("suitcase lid seam", (0, 0.31, -0.18), (1.00, 0.025, 0.025), brass, 0.002)
    curve("suitcase handle", [(-0.18, 0.61, 0), (-0.18, 0.77, 0), (0.18, 0.77, 0), (0.18, 0.61, 0)], 0.025, leather)
    for x in (-0.38, 0.38):
        cube("corner cap", (x, 0.10, -0.18), (0.10, 0.10, 0.04), brass, 0.008)


def add_cage(name: str):
    brass = mat("cage wire", "brass", 0.65, 0.30)
    wood = mat("cage base", "wood", 0, 0.38)
    cyl("cage base", (0, 0.10, 0), 0.36, 0.20, wood, 20)
    for angle in range(0, 360, 30):
        a = math.radians(angle)
        cyl("cage bar", (math.cos(a) * 0.27, 0.58, math.sin(a) * 0.27), 0.012, 0.90, brass, 8)
    torus("cage top", (0, 1.03, 0), 0.28, 0.018, brass)
    curve("cage hook", [(0, 1.04, 0), (0, 1.28, 0), (0.11, 1.35, 0)], 0.018, brass)


def add_brush(name: str):
    wood = mat("brush wood", "wood", 0, 0.4)
    bristle = mat("bristle", "cloth", 0, 0.85)
    cube("brush block", (0, 0.14, 0), (0.65, 0.18, 0.28), wood, 0.03)
    for x in (-0.23, -0.08, 0.08, 0.23):
        for z in (-0.08, 0.08):
            cone("bristle", (x, 0.03, z), 0.035, 0.020, 0.22, bristle, 8)
    cube("brush handle", (0, 0.42, 0), (0.12, 0.50, 0.10), wood, 0.03)


def add_crate(name: str):
    key = name.lower()
    wood = mat("crate wood", "wood", 0, 0.42)
    dark = mat("crate interior", "dark_wood", 0, 0.65)
    if "barrel" in key:
        cyl("barrel body", (0, 0.42, 0), 0.31, 0.82, wood, 16, bevel=0.02)
        for y in (0.20, 0.42, 0.64):
            torus("barrel hoop", (0, y, 0), 0.32, 0.022, mat("barrel hoop", "steel"))
        return
    if any(word in key for word in ("sack", "bag")):
        sphere("filled sack", (0, 0.30, 0), 0.33, mat("sack cloth", "paper"), (0.90, 1.20, 0.75))
        curve("sack tie", [(-0.16, 0.54, 0), (0, 0.63, 0), (0.16, 0.54, 0)], 0.025, mat("sack tie", "cloth"))
        return
    if "pallet" in key:
        for z in (-0.26, 0, 0.26):
            cube("pallet slat", (0, 0.20, z), (1.28, 0.10, 0.16), wood, 0.012)
        for x in (-0.45, 0.45):
            cube("pallet runner", (x, 0.08, 0), (0.18, 0.12, 0.76), dark, 0.012)
        return
    cube("crate body", (0, 0.36, 0), (0.95, 0.68, 0.68), dark, 0.03)
    for x in (-0.43, 0.43):
        cube("corner upright", (x, 0.38, -0.35), (0.06, 0.72, 0.06), wood, 0.008)
        cube("corner upright", (x, 0.38, 0.35), (0.06, 0.72, 0.06), wood, 0.008)
    for y in (0.12, 0.36, 0.60):
        cube("front slat", (0, y, -0.36), (0.86, 0.10, 0.04), wood, 0.004)
    cube("diagonal brace", (0, 0.38, -0.39), (1.00, 0.07, 0.025), wood, 0.004).rotation_euler[1] = math.radians(32)


def add_camera(name: str):
    key = name.lower()
    black = mat("camera body", "black", 0.18, 0.28)
    glass = mat("camera lens", "glass", 0.18, 0.12)
    if any(word in key for word in ("phone", "handheld", "tablet")):
        cube("handheld device", (0, 0.38, 0), (0.44, 0.74, 0.07), black, 0.04)
        cube("device screen", (0, 0.38, -0.045), (0.35, 0.57, 0.008), glass, 0.002)
        cyl("device camera", (0.13, 0.65, -0.052), 0.035, 0.01, mat("device lens", "brass"), 12, (math.pi / 2, 0, 0))
        return
    if any(word in key for word in ("fixed", "surveillance")):
        cyl("security camera barrel", (0, 0.54, 0), 0.18, 0.54, black, 16, (0, math.pi / 2, 0), 0.02)
        cyl("camera lens", (0.31, 0.54, 0), 0.12, 0.08, glass, 16, (0, math.pi / 2, 0))
        cube("security mount", (-0.20, 0.48, 0), (0.18, 0.14, 0.34), mat("camera mount", "steel", 0.6, 0.3), 0.015)
        return
    cube("camera body", (0, 0.44, 0), (0.78, 0.48, 0.44), black, 0.06)
    cyl("camera lens", (0.49, 0.45, 0), 0.17, 0.20, glass, 20, (0, math.pi / 2, 0))
    cube("viewfinder", (-0.16, 0.75, 0), (0.22, 0.12, 0.18), black, 0.02)
    cube("mount", (0, 0.15, 0), (0.18, 0.22, 0.18), mat("camera mount", "steel", 0.6, 0.3), 0.01)


def add_plant(name: str):
    """Build deliberately separate pot and foliage families in Y-up space."""
    key = name.lower()
    leaf = mat("leaf", "leaf")
    stem = mat("stem", "green")

    if "conservatory plant collection" in key:
        # Three foliage-only specimens. Pots are authored separately so a
        # designer can combine these plants with any planter without nested
        # duplicate containers.
        for x in (-0.52, 0.0, 0.52):
            sphere("plant/root ball", (x, 0.08, 0), 0.11, mat("root ball", "dark_wood"), (1.0, 0.55, 1.0))

        # Fern: low radial fronds.
        for angle in range(0, 360, 45):
            a = math.radians(angle)
            frond = sphere(
                "plant/fern frond",
                (-0.52 + math.cos(a) * 0.18, 0.25, math.sin(a) * 0.18),
                0.13,
                leaf,
                (1.5, 0.20, 0.42),
            )
            frond.rotation_euler[1] = -a

        # Snake plant: tall, narrow blades.
        for index, (dx, dz, height) in enumerate(((-0.07, 0.01, 0.58), (0.0, -0.04, 0.76), (0.07, 0.03, 0.64))):
            blade = sphere("plant/snake blade", (dx, 0.14 + height / 2, dz), 0.18, stem, (0.28, height / 0.36, 0.16))
            blade.rotation_euler[2] = math.radians((-7, 2, 9)[index])

        # Flowering specimen: branching stem and upright blossoms.
        curve("plant/flower stem", [(0.52, 0.08, 0), (0.50, 0.48, 0), (0.58, 0.75, 0)], 0.022, stem)
        for y, side in ((0.43, -1), (0.60, 1), (0.77, 0)):
            cx = 0.54 + side * 0.10
            for angle in range(0, 360, 72):
                a = math.radians(angle)
                petal = sphere("plant/flower petal", (cx + math.cos(a) * 0.075, y + math.sin(a) * 0.055, -0.015), 0.065, mat("flower petal", "red"), (1.0, 0.68, 0.18))
                petal.rotation_euler[2] = a
            sphere("plant/flower center", (cx, y, -0.03), 0.025, mat("flower center", "gold"))
        return

    if "planter" in key:
        pot = mat("planter ceramic", "ceramic", 0.0, 0.5)
        cone("pot/planter", (0, 0.18, 0), 0.34, 0.25, 0.36, pot, 20)
        torus("pot/rim", (0, 0.36, 0), 0.29, 0.035, pot)
        cyl("pot/soil", (0, 0.37, 0), 0.25, 0.045, mat("potting soil", "dark_wood"), 20)
        return

    # A compact broadleaf fallback for any future explicitly named plant.
    curve("plant/stem", [(0, 0.04, 0), (0.03, 0.62, 0)], 0.025, stem)
    for angle in range(0, 360, 72):
        a = math.radians(angle)
        blade = sphere("plant/broad leaf", (0.18 * math.cos(a), 0.42, 0.18 * math.sin(a)), 0.12, leaf, (1.2, 0.2, 0.55))
        blade.rotation_euler[1] = -a


def add_fabric(name: str):
    cloth = mat("draped cloth", "cloth", 0, 0.76)
    if any(word in name.lower() for word in ("coat", "robe")):
        cone("shoulders", (0, 1.08, 0), 0.30, 0.13, 0.25, cloth, 16)
        cone("hanging fabric", (0, 0.58, 0), 0.34, 0.16, 0.88, cloth, 16)
        curve("collar", [(-0.16, 1.18, 0), (0, 1.27, 0), (0.16, 1.18, 0)], 0.02, mat("collar trim", "black"))
    else:
        for x in (-0.23, 0, 0.23):
            cube("fold", (x, 0.08, 0), (0.18, 0.06, 0.90), cloth, 0.04)
        cube("rolled end", (0, 0.12, -0.44), (0.72, 0.12, 0.10), cloth, 0.04)


def add_cleaning(name: str):
    key = name.lower()
    steel = mat("cleaning steel", "steel", 0.45, 0.28)
    plastic = mat("cleaning plastic", "red", 0, 0.38)
    if "sanitizer" in key:
        cyl("sanitizer reservoir", (0, 0.35, 0), 0.16, 0.56, plastic, 16, bevel=0.015)
        cube("pump head", (0, 0.67, 0), (0.26, 0.08, 0.12), steel, 0.018)
        cube("pump spout", (0.16, 0.64, 0), (0.18, 0.05, 0.07), steel, 0.01)
        return
    if "wash-station" in key:
        cube("wash basin", (0, 0.48, 0), (1.12, 0.56, 0.72), steel, 0.045)
        cube("sink well", (0, 0.78, 0), (0.74, 0.08, 0.46), mat("sink interior", "black"), 0.015)
        curve("gooseneck faucet", [(0, 0.80, 0.18), (0, 1.15, 0.18), (0.20, 1.15, 0.18), (0.20, 1.00, 0.18)], 0.035, steel)
        return
    if "mop" in key:
        cyl("mop handle", (0, 0.68, 0), 0.035, 1.36, steel, 12)
        for x in (-0.12, -0.06, 0, 0.06, 0.12):
            curve("mop strand", [(0, 0.10, 0), (x, 0.02, 0.12), (x * 1.3, 0.02, -0.14)], 0.018, mat("mop fiber", "cloth"))
        return
    cyl("bucket", (-0.22, 0.18, 0), 0.20, 0.34, plastic, 20)
    torus("bucket handle", (-0.22, 0.36, 0), 0.20, 0.02, steel, (math.pi / 2, 0, 0))
    cube("spray bottle", (0.25, 0.27, 0), (0.22, 0.46, 0.16), plastic, 0.025)
    curve("spray trigger", [(0.25, 0.52, 0), (0.35, 0.60, 0), (0.45, 0.57, 0)], 0.025, steel)


def add_rigging(name: str):
    key = name.lower()
    steel = mat("rigging steel", "steel", 0.72, 0.26)
    rope = mat("rigging rope", "cloth", 0, 0.70)
    if "cue-light" in key or "cue light" in key:
        cyl("cue light housing", (0, 0.30, 0), 0.16, 0.48, mat("cue housing", "black"), 16, (0, math.pi / 2, 0), 0.02)
        cyl("cue lens", (0.27, 0.30, 0), 0.12, 0.04, mat("cue lens", "red"), 16, (0, math.pi / 2, 0))
        cube("cue clamp", (-0.20, 0.20, 0), (0.16, 0.26, 0.18), steel, 0.02)
        return
    cyl("pulley wheel", (0, 0.85, 0), 0.24, 0.08, steel, 20, (math.pi / 2, 0, 0))
    cyl("pulley hub", (0, 0.85, -0.06), 0.06, 0.10, mat("pulley brass", "brass", 0.65, 0.26), 12, (math.pi / 2, 0, 0))
    curve("rigging line", [(0, 0.85, 0), (-0.28, 0.66, 0), (-0.28, 0.10, 0)], 0.035, rope)
    cube("counterweight", (-0.28, 0.30, 0), (0.18, 0.44, 0.18), steel, 0.02)


def add_ladder(name: str):
    wood = mat("ladder wood", "wood", 0, 0.34)
    for x in (-0.23, 0.23):
        cube("ladder rail", (x, 0.80, 0), (0.06, 1.60, 0.07), wood, 0.01)
    for y in (0.20, 0.45, 0.70, 0.95, 1.20, 1.45):
        cube("ladder rung", (0, y, 0), (0.52, 0.055, 0.06), wood, 0.008)


def add_sign(name: str):
    key = name.lower()
    wood = mat("sign wood", "wood", 0, 0.38)
    paper = mat("sign face", "paper", 0, 0.74)
    if "banner" in key or "bunting" in key:
        for x in (-0.54, 0.54):
            cyl("banner pole", (x, 0.86, 0), 0.035, 1.72, wood, 12)
            cone("pole finial", (x, 1.76, 0), 0.07, 0.01, 0.12, mat("finial", "brass"), 12)
        cube("hanging banner", (0, 1.12, 0), (1.02, 0.90, 0.04), mat("banner cloth", "cloth"), 0.02)
        return
    if any(word in key for word in ("booth", "stall", "counter")):
        cube("service counter", (0, 0.45, 0), (1.42, 0.90, 0.58), wood, 0.04)
        cube("counter top", (0, 0.93, 0), (1.56, 0.10, 0.70), paper, 0.02)
        for x in (-0.58, 0.58):
            cube("canopy post", (x, 1.40, 0), (0.05, 0.92, 0.05), wood, 0.008)
        cube("canopy", (0, 1.82, 0), (1.52, 0.10, 0.74), mat("canopy cloth", "cloth"), 0.025)
        return
    cube("sign board", (0, 0.78, 0), (1.15, 0.72, 0.05), paper, 0.02)
    cube("sign frame top", (0, 1.16, 0), (1.24, 0.06, 0.07), wood, 0.01)
    cube("sign frame bottom", (0, 0.40, 0), (1.24, 0.06, 0.07), wood, 0.01)
    for x in (-0.58, 0.58):
        cube("sign post", (x, 0.38, 0), (0.06, 0.76, 0.07), wood, 0.01)


def add_music_stand(name: str):
    black = mat("music stand", "black", 0.25, 0.28)
    cube("score shelf", (0, 1.16, 0), (0.62, 0.42, 0.06), black, 0.02)
    cyl("stand pole", (0, 0.55, 0), 0.035, 1.05, black, 12)
    for a in (0, 120, 240):
        angle = math.radians(a)
        leg = cube("tripod foot", (math.cos(angle) * 0.25, 0.06, math.sin(angle) * 0.25), (0.42, 0.045, 0.055), black, 0.008)
        leg.rotation_euler[1] = -angle


def add_press(name: str):
    steel = mat("press steel", "steel", 0.72, 0.26)
    wood = mat("press wood", "wood", 0, 0.38)
    cube("press base", (0, 0.10, 0), (1.10, 0.20, 0.75), wood, 0.03)
    for x in (-0.38, 0.38):
        cube("press upright", (x, 0.60, 0), (0.10, 1.00, 0.16), steel, 0.02)
    cube("press platen", (0, 0.76, 0), (0.82, 0.12, 0.58), steel, 0.02)
    cyl("press screw", (0, 1.15, 0), 0.06, 0.65, steel, 16)
    cube("press handle", (0, 1.45, 0), (0.72, 0.06, 0.06), wood, 0.01)


def add_ppe(name: str):
    yellow = mat("safety yellow", "gold", 0.1, 0.32)
    black = mat("goggle black", "black", 0.18, 0.3)
    sphere("hard hat dome", (-0.18, 0.33, 0), 0.25, yellow, (1.0, 0.55, 1.0))
    cube("hard hat brim", (-0.18, 0.25, 0), (0.58, 0.05, 0.40), yellow, 0.02)
    torus("goggles", (0.28, 0.33, -0.03), 0.13, 0.028, black, (math.pi / 2, 0, 0))
    cube("respirator", (0.28, 0.15, 0), (0.32, 0.15, 0.16), black, 0.03)


def add_industrial(name: str):
    """A readable pump/fan/meter assembly — deliberately not a square housing."""
    steel = mat("industrial teal", "steel", 0.72, 0.32)
    brass = mat("industrial brass", "brass", 0.6, 0.32)
    black = mat("industrial rubber", "black", 0.25, 0.36)
    cyl("motor drum", (-0.16, 0.47, 0), 0.31, 0.68, steel, 16, (0, math.pi / 2, 0), 0.02)
    for x in (-0.42, 0.10):
        torus("motor band", (x, 0.47, 0), 0.315, 0.022, brass, (0, math.pi / 2, 0))
    cone("pump bell", (0.42, 0.47, 0), 0.32, 0.15, 0.34, steel, 16, (0, math.pi / 2, 0))
    cyl("pipe outlet", (0.68, 0.47, 0), 0.12, 0.34, black, 16, (0, math.pi / 2, 0), 0.01)
    torus("valve wheel", (0.36, 0.72, -0.18), 0.18, 0.035, brass, (math.pi / 2, 0, 0))
    cyl("hub", (0.36, 0.72, -0.18), 0.05, 0.08, brass, 12, (math.pi / 2, 0, 0))
    for x in (-0.34, 0.32):
        cube("machine foot", (x, 0.10, 0), (0.18, 0.18, 0.36), black, 0.025)


def add_body(name: str):
    cloth = mat("body cloth", "cloth", 0.0, 0.7)
    skin = mat("skin", "ceramic", 0.0, 0.62)
    cube("torso", (0, 0.48, 0), (0.44, 0.75, 0.24), cloth, 0.08)
    sphere("head", (0, 0.98, 0), 0.17, skin, (0.9, 1.0, 0.9))
    for x in (-0.28, 0.28):
        cyl("arm", (x, 0.55, 0), 0.07, 0.65, cloth, 12, (0, 0, math.radians(18 if x < 0 else -18)))
    for x in (-0.14, 0.14):
        cyl("leg", (x, 0.03, 0), 0.09, 0.62, cloth, 12, (0, 0, 0))


def add_generic(name: str):
    key = name.lower()
    if "festival wristband" in key:
        band = mat("festival band", "red", 0.0, 0.42)
        torus("festival wristband", (0, 0.08, 0), 0.26, 0.045, band, (math.pi / 2, 0, 0))
        cube("wristband clasp", (0.24, 0.08, 0), (0.10, 0.08, 0.07), mat("wristband clasp", "brass"), 0.008)
        cube("printed band tab", (0, 0.08, -0.26), (0.22, 0.06, 0.015), mat("band print", "white"), 0.002)
        return
    if "bright coat" in key:
        cloth = mat("bright coat cloth", "red", 0.0, 0.58)
        cone("coat shoulders", (0, 1.08, 0), 0.32, 0.14, 0.24, cloth, 16)
        cone("coat body", (0, 0.56, 0), 0.38, 0.18, 0.92, cloth, 16)
        for x in (-0.22, 0.22):
            curve("coat lapel", [(x, 1.06, -0.06), (x * 0.5, 0.75, -0.13), (x * 0.7, 0.48, -0.08)], 0.020, mat("coat trim", "brass"))
        cyl("coat button", (-0.07, 0.68, -0.20), 0.035, 0.02, mat("coat button", "gold"), 12, (math.pi / 2, 0, 0))
        cyl("coat button", (0.07, 0.56, -0.20), 0.035, 0.02, mat("coat button", "gold"), 12, (math.pi / 2, 0, 0))
        return
    if "stone sample block" in key:
        stone = mat("porous stone", "ceramic", 0, 0.72)
        cube("stone sample", (0, 0.16, 0), (0.62, 0.32, 0.42), stone, 0.035)
        for x, z in ((-0.18, -0.12), (0.10, 0.10), (0.22, -0.05)):
            sphere("stone pore", (x, 0.335, z), 0.045, mat("pore shadow", "dark_wood"), (1.0, 0.18, 1.0))
        cube("sample label", (0, 0.18, -0.215), (0.28, 0.12, 0.008), mat("sample label", "paper"), 0.002)
        return
    if "marble bookend" in key:
        marble = mat("marble", "white", 0.0, 0.30)
        for x in (-0.28, 0.28):
            cube("bookend base", (x, 0.08, 0), (0.24, 0.16, 0.42), marble, 0.025)
            cube("bookend upright", (x, 0.33, 0.12), (0.24, 0.52, 0.16), marble, 0.025)
            torus("bookend inlay", (x, 0.38, -0.085), 0.06, 0.012, mat("bookend inlay", "brass"), (math.pi / 2, 0, 0))
        return
    if "stage brace" in key:
        steel = mat("stage brace steel", "steel", 0.75, 0.23)
        for angle in (-0.50, 0.50):
            bar = cube("folding brace arm", (0, 0.34, 0), (0.12, 0.82, 0.12), steel, 0.018)
            bar.rotation_euler[2] = angle
        cyl("brace hinge", (0, 0.34, -0.08), 0.10, 0.06, mat("brace hinge brass", "brass"), 16, (math.pi / 2, 0, 0))
        cube("brace foot", (0, 0.05, 0), (0.92, 0.10, 0.24), mat("brace foot", "black"), 0.025)
        return
    if "survey weight" in key:
        brass = mat("survey brass", "brass", 0.75, 0.22)
        cone("plumb bob", (0, 0.32, 0), 0.25, 0.035, 0.54, brass, 16)
        torus("plumb bob collar", (0, 0.55, 0), 0.10, 0.018, mat("survey collar", "steel"))
        curve("plumb line", [(0, 0.58, 0), (0, 1.10, 0)], 0.012, mat("plumb line", "cloth"))
        return
    if "bottle cradle" in key:
        wood = mat("cradle wood", "wood", 0, 0.34)
        for x in (-0.28, 0.28):
            curve("cradle arc", [(x, 0.10, -0.34), (x, 0.34, 0), (x, 0.10, 0.34)], 0.055, wood)
        for z in (-0.30, 0.30):
            cube("cradle crossbar", (0, 0.10, z), (0.76, 0.10, 0.08), wood, 0.015)
        cyl("cradle pivot", (0, 0.34, 0), 0.06, 0.66, mat("cradle pivot", "brass"), 16, (0, 0, math.pi / 2))
        return
    if "entrance mat" in key:
        fabric = mat("woven mat", "cloth", 0.0, 0.8)
        cube("woven mat", (0, 0.045, 0), (1.25, 0.09, 0.82), fabric, 0.035)
        for x in (-0.42, -0.14, 0.14, 0.42):
            cube("mat stripe", (x, 0.095, 0), (0.035, 0.012, 0.70), mat("mat stripe", "brass"), 0.002)
        return
    if any(word in key for word in ("cookware", "place-setting", "place settings", "cloches", "room-service tray", "caterer")):
        return add_tableware(name)
    if "waste bin" in key:
        cyl("pedal bin", (0, 0.32, 0), 0.28, 0.62, mat("bin steel", "steel", 0.65, 0.26), 16, bevel=0.025)
        cone("bin lid", (0, 0.66, 0), 0.29, 0.18, 0.12, mat("bin lid", "black"), 16)
        cube("pedal", (0, 0.07, -0.26), (0.20, 0.05, 0.14), mat("bin pedal", "brass"), 0.012)
        return
    if "smoke-test canister" in key:
        cyl("smoke canister", (0, 0.30, 0), 0.20, 0.56, mat("signal canister", "red"), 16, bevel=0.02)
        cone("canister cap", (0, 0.62, 0), 0.16, 0.08, 0.16, mat("canister cap", "brass"), 16)
        curve("smoke plume", [(0, 0.72, 0), (0.10, 0.92, 0.02), (-0.08, 1.10, 0.04)], 0.06, mat("smoke", "white"))
        return
    if "maintenance pit" in key:
        steel = mat("pit steel", "steel", 0.7, 0.34)
        cube("pit rim left", (-0.48, 0.10, 0), (0.18, 0.20, 1.18), steel, 0.02)
        cube("pit rim right", (0.48, 0.10, 0), (0.18, 0.20, 1.18), steel, 0.02)
        cube("pit floor", (0, -0.14, 0), (0.82, 0.08, 1.10), mat("pit shadow", "black"), 0.01)
        for z in (-0.32, 0, 0.32):
            cube("pit cross brace", (0, 0.18, z), (0.80, 0.06, 0.07), mat("pit brass", "brass"), 0.01)
        return
    if any(word in key for word in ("body", "mannequin")):
        return add_body(name)
    if any(word in key for word in ("crate", "road case", "pallet", "hopper", "tool bay")):
        return add_crate(name)
    if any(word in key for word in ("camera", "surveillance")):
        return add_camera(name)
    if any(word in key for word in ("coat", "robe", "scarf", "bedding", "linen", "fabric")):
        return add_fabric(name)
    if any(word in key for word in ("cleaning", "sanitizer", "wash-station")):
        return add_cleaning(name)
    if any(word in key for word in ("rigging", "cue-light", "cue light")):
        return add_rigging(name)
    if "ladder" in key:
        return add_ladder(name)
    if any(word in key for word in ("sign", "banner", "booth", "counter", "stall")):
        return add_sign(name)
    if any(word in key for word in ("music stand", "lectern")):
        return add_music_stand(name)
    if any(word in key for word in ("print press", "printer")):
        return add_press(name)
    if any(word in key for word in ("ppe", "safety set", "safety signs")):
        return add_ppe(name)
    if any(word in key for word in ("blood", "residue", "ash", "dust", "trace", "footprint", "drag", "chalk", "fiber", "scratch")):
        trace = mat("trace pigment", "red")
        dark = mat("trace dark", "black")
        if "blood" in key:
            pool = sphere("blood pool", (0, 0.018, 0), 0.34, trace, (1.30, 0.045, 0.88))
            for x, z, size in ((-0.42, 0.18, 0.07), (0.28, 0.30, 0.05), (0.40, -0.14, 0.035), (-0.24, -0.30, 0.045)):
                sphere("blood droplet", (x, 0.015, z), size, trace, (1.0, 0.08, 1.0))
        elif "drag" in key:
            for offset in (-0.20, 0.20):
                curve("drag groove", [(-0.50, 0.018, offset), (-0.12, 0.022, offset + 0.06), (0.28, 0.018, offset - 0.04), (0.52, 0.018, offset)], 0.035, dark)
            for x in (-0.34, 0.04, 0.38):
                sphere("drag debris", (x, 0.020, -0.28), 0.032, trace, (1, 0.20, 1))
        elif any(word in key for word in ("footprint", "shoe", "sole")):
            for x, z, rotation in ((-0.24, -0.18, -0.20), (0.18, 0.16, 0.18)):
                sole = sphere("shoe impression", (x, 0.023, z), 0.18, dark, (0.72, 0.05, 1.45))
                sole.rotation_euler[1] = rotation
                for dx in (-0.07, 0, 0.07):
                    cube("tread bar", (x + dx, 0.030, z), (0.035, 0.015, 0.19), trace, 0.003).rotation_euler[1] = rotation
        elif any(word in key for word in ("chalk", "scratch", "fiber")):
            for offset in (-0.26, 0, 0.26):
                curve("linear trace", [(offset - 0.12, 0.018, -0.25), (offset, 0.025, 0), (offset + 0.12, 0.018, 0.25)], 0.018, trace if "chalk" in key else dark)
        elif any(word in key for word in ("ash", "dust", "residue")):
            for index, (x, z, scale) in enumerate(((-0.25, -0.08, 1.0), (0.02, 0.12, 0.68), (0.30, -0.05, 0.84))):
                sphere("powder mound", (x, 0.018, z), 0.13, dark, (scale, 0.05, scale))
                for spike in range(5):
                    a = spike * math.tau / 5
                    sphere("powder fleck", (x + math.cos(a) * 0.17, 0.014, z + math.sin(a) * 0.17), 0.018, trace, (1, 0.2, 1))
        else:
            for index, (x, z, scale) in enumerate(((-0.30, -0.18, 1.0), (0.00, 0.10, 0.68), (0.30, -0.08, 0.82))):
                mark = sphere("visible trace", (x, 0.024, z), 0.11, trace, (1.45 * scale, 0.06, 0.78 * scale))
                mark.rotation_euler[1] = index * 0.45
        return
    if any(word in key for word in ("tableware", "plate", "bowl", "cutlery", "spoon", "crockery")):
        return add_tableware(name)
    if any(word in key for word in ("tripod", "survey staff", "survey instrument", "laser", "level")):
        return add_tripod(name)
    if any(word in key for word in ("backdrop", "curtain")):
        return add_backdrop(name)
    if any(word in key for word in ("auditorium seating", "screening-room seats", "seat cushion", "recital chairs")):
        return add_seating(name)
    if any(word in key for word in ("console", "control board", "control panel", "monitor", "microphone", "terminal", "point-of-sale", "display", "recorder", "recording player")):
        return add_console(name)
    if any(word in key for word in ("costume rack", "coat rack", "claim rack", "hanger")):
        return add_costume_rack(name)
    if any(word in key for word in ("art frame", "frame", "portrait")):
        return add_frame(name)
    if any(word in key for word in ("bell", "chime")):
        return add_bell(name)
    if any(word in key for word in ("suitcase", "luggage", "hat box", "survey case")):
        return add_suitcase(name)
    if any(word in key for word in ("cage", "carrier")):
        return add_cage(name)
    if any(word in key for word in ("brush", "mop")):
        return add_brush(name)
    if any(word in key for word in ("inspection rail carriage", "wash-track rail car", "sleeping carriage")):
        return add_rail_car(name)
    if any(word in key for word in ("blower", "fan", "pipe", "valve", "vent", "switch-booth", "pumping", "gas", "industrial")):
        return add_industrial(name)
    if any(word in key for word in ("projector", "editing bench", "splicer")):
        return add_projector(name)
    if any(word in key for word in ("film can", "workprint", "film strip", "reel")):
        cyl("film can", (0, 0.09, 0), 0.34, 0.18, mat("film can metal", "steel", 0.65, 0.25), 20)
        torus("film coil", (0, 0.20, 0), 0.22, 0.022, mat("film", "black"))
        return
    if any(word in key for word in ("violin", "bass", "instrument", "bow", "mute", "strings")):
        return add_instrument(name)
    if any(word in key for word in ("clock", "timer", "metronome", "gauge")):
        return add_clock(name)
    if any(word in key for word in ("bottle", "vial", "jar", "wine", "glass", "decanter", "carafe")):
        return add_bottle(name)
    if any(word in key for word in ("acoustic panel", "window panel")):
        cube("acoustic panel", (0, 0.85, 0), (1.10, 1.60, 0.10), mat("panel fabric", "cloth"), 0.03)
        for x in (-0.32, 0, 0.32):
            cube("acoustic rib", (x, 0.85, -0.07), (0.05, 1.40, 0.025), mat("panel trim", "wood"), 0.004)
        return
    if any(word in key for word in ("door", "gate", "hatch", "barrier", "transom", "latch", "catch", "bolt", "lock", "window")):
        return add_door(name)
    if any(word in key for word in ("cart", "trolley", "cradle", "luggage chair", "bell cart", "lift", "dumbwaiter")):
        return add_cart(name)
    if any(word in key for word in ("shelf", "shelving", "rack", "cabinet", "bookcase", "archive", "file", "suite furniture", "lounge furnishings")):
        return add_shelf(name)
    if any(word in key for word in ("table", "desk", "bench", "workstation", "counter", "podium", "plinth", "board")):
        return add_table(name)
    if "soil bin" in key:
        cube("soil bin/body", (0, 0.34, 0), (0.84, 0.68, 0.70), mat("soil bin", "steel", 0.45, 0.38), 0.04)
        cube("soil bin/soil", (0, 0.70, 0), (0.72, 0.05, 0.58), mat("loose soil", "dark_wood"), 0.015)
        return
    if "soil and compost sacks" in key:
        for x, scale in ((-0.24, (0.82, 1.15, 0.72)), (0.24, (0.76, 0.98, 0.68))):
            sphere("sack/filled bag", (x, 0.29, 0), 0.31, mat("sack cloth", "paper"), scale)
            curve("sack/tie", [(x - 0.10, 0.54, 0), (x, 0.61, 0), (x + 0.10, 0.54, 0)], 0.018, mat("sack tie", "cloth"))
        return
    if any(word in key for word in ("plant", "orchid", "flower", "planter")):
        return add_plant(name)
    if any(word in key for word in ("paper", "letter", "document", "card", "ticket", "luggage tag", " tags", "score", "map", "log", "ledger", "folder", "photograph", "permit", "chart", "program", "script", "blueprint", "adhesive", "signature")):
        paper = mat("paper", "paper", 0.0, 0.86)
        if any(word in key for word in ("map", "blueprint", "chart")):
            cyl("rolled plan", (-0.22, 0.09, 0), 0.12, 0.72, paper, 16, (0, math.pi / 2, 0), 0.01)
            cube("unrolled plan", (0.30, 0.025, 0), (0.70, 0.03, 0.72), mat("blue plan", "glass"), 0.004)
            for x in (0.12, 0.30, 0.48):
                cube("plan line", (x, 0.048, 0), (0.018, 0.006, 0.58), mat("ink", "black"), 0.001)
        elif any(word in key for word in ("folder", "file", "packet", "sleeve")):
            cube("open file folder", (0, 0.04, 0), (1.0, 0.055, 0.76), mat("folder cover", "cloth"), 0.008)
            cube("file papers", (0.08, 0.075, 0), (0.68, 0.025, 0.58), paper, 0.002)
            cube("file tab", (0.34, 0.08, -0.34), (0.22, 0.025, 0.11), mat("tab", "red"), 0.003)
        elif any(word in key for word in ("photograph", "card", "ticket", "tag")):
            cube("photo print", (0, 0.025, 0), (0.70, 0.03, 0.50), mat("photo border", "white"), 0.004)
            cube("photo image", (0, 0.045, 0), (0.54, 0.008, 0.34), mat("photo image", "glass"), 0.001)
            cube("second print", (0.25, 0.04, 0.19), (0.42, 0.02, 0.32), paper, 0.003).rotation_euler[1] = 0.25
        else:
            cube("page stack", (0, 0.03, 0), (0.75, 0.055, 1.0), paper, 0.005)
            cube("cover", (0, 0.065, 0.02), (0.82, 0.018, 1.06), mat("cover", "cloth"), 0.003)
            cube("label", (0, 0.078, -0.20), (0.38, 0.008, 0.20), mat("label", "white"), 0.001)
        return
    if any(word in key for word in ("key", "token", "wristband", "seal")):
        brass = mat("key brass", "brass", 0.8, 0.22)
        torus("key bow", (0, 0.06, 0), 0.13, 0.035, brass, (math.pi / 2, 0, 0))
        cube("key stem", (0.28, 0.06, 0), (0.45, 0.07, 0.07), brass, 0.01)
        cube("tooth", (0.44, 0.02, 0), (0.08, 0.10, 0.07), brass, 0.005)
        return
    if any(word in key for word in ("line", "rope", "hose", "cords", " cord", "cable", "wire")):
        curve("coiled line", [(-0.55, 0.05, 0), (-0.2, 0.10, 0.25), (0.2, 0.10, -0.25), (0.55, 0.05, 0)], 0.045, mat("rope", "cloth"))
        return
    if any(word in key for word in ("knife", "divider", "brace", "guide", "weight", "shoe", "sole", "tool", "wrench", "trowel", "fork", "shears", "sample", "bookend", "mute")):
        steel = mat("tool steel", "steel", 0.85, 0.20)
        grip = mat("tool grip", "black")
        if "knife" in key:
            cube("riveted knife handle", (-0.30, 0.055, 0), (0.42, 0.10, 0.14), grip, 0.025)
            cone("tapered blade", (0.30, 0.050, 0), 0.15, 0.012, 0.72, steel, 4, (0, math.pi / 2, 0))
            for x in (-0.40, -0.28):
                cyl("handle rivet", (x, 0.11, -0.072), 0.025, 0.012, mat("rivet", "brass"), 12, (math.pi / 2, 0, 0))
        elif any(word in key for word in ("weight", "bookend")):
            cyl("heavy base", (0, 0.14, 0), 0.26, 0.28, steel, 12, bevel=0.02)
            torus("weight grip", (0, 0.31, 0), 0.13, 0.035, mat("weight brass", "brass"), (math.pi / 2, 0, 0))
        elif any(word in key for word in ("shoe", "sole")):
            sole = sphere("carved boot sole", (0, 0.08, 0), 0.28, mat("leather sole", "wood"), (0.76, 0.20, 1.50))
            for z in (-0.20, -0.07, 0.07, 0.20):
                cube("boot tread", (0, 0.13, z), (0.28, 0.025, 0.035), grip, 0.004)
        elif any(word in key for word in ("fork", "shears", "trowel")):
            cube("wooden tool handle", (-0.28, 0.06, 0), (0.42, 0.11, 0.13), mat("tool wood", "wood"), 0.025)
            if "shears" in key:
                for angle in (-0.24, 0.24):
                    blade = cube("shear blade", (0.25, 0.055, 0), (0.62, 0.04, 0.055), steel, 0.006)
                    blade.rotation_euler[1] = angle
                cyl("shear pivot", (0.02, 0.085, 0), 0.045, 0.04, mat("pivot", "brass"), 12)
            else:
                cone("tool head", (0.30, 0.055, 0), 0.24, 0.08, 0.45, steel, 6, (0, math.pi / 2, 0))
        else:
            cube("handle", (-0.28, 0.06, 0), (0.45, 0.10, 0.12), grip, 0.015)
            cube("working end", (0.28, 0.06, 0), (0.65, 0.055, 0.07), steel, 0.008)
        return
    # Concrete generic object: layered body, inset panel and visible hardware.
    print(f"FALLBACK: {name}")
    cube("main body", (0, 0.42, 0), (0.82, 0.76, 0.64), mat("generic body", "steel", 0.2, 0.4), 0.05)
    cube("inset", (0, 0.47, -0.33), (0.52, 0.38, 0.025), mat("inset", "black"), 0.005)
    cyl("control", (0.23, 0.45, -0.36), 0.055, 0.03, mat("control", "brass", 0.7, 0.22), 12, (math.pi / 2, 0, 0))


def export(entry: dict) -> None:
    clear()
    name = entry["name"]
    add_generic(name)
    # Curves report control-point bounds rather than their evaluated bevel
    # geometry. Convert them before measuring so ropes, collars and handles are
    # normalized from the mesh that will actually ship.
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.convert(target="MESH")
    # Builders work in the project's metre-based Y-up authoring space.  Apply
    # the reviewed semantic size contract to the complete asset before export.
    objects = [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "CURVE"}]
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if points:
        low = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
        high = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
        span = max(high - low)
        factor = target_max_span_m(name) / span
        for obj in objects:
            obj.location *= factor
            obj.scale *= factor
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    for obj in bpy.context.scene.objects:
        obj["inventory_name"] = name
        obj["inventory_status"] = entry["status"]
        obj["inventory_notes"] = entry["notes"]
    target = OUT / entry["path"]
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(target),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        # Geometry is already authored Y-up.  Asking Blender to convert its
        # native Z-up basis here would rotate the finished prop a second time.
        export_yup=False,
        export_extras=True,
        export_materials="EXPORT",
    )


def main() -> None:
    entries = json.loads(MANIFEST.read_text())["models"]
    requested = set(sys.argv[sys.argv.index("--") + 1:]) if "--" in sys.argv else set()
    built = 0
    for index, entry in enumerate(entries, 1):
        if entry["path"] in P0_HERO_PATHS or requested and entry["path"] not in requested:
            continue
        export(entry)
        built += 1
        if not requested and (index % 20 == 0 or index == len(entries)):
            print(f"Built {index}/{len(entries)}: {entry['path']}")
    print(f"Completed {built} real Blender props")


main()
