"""Convert the curated Quaternius foliage sources to engine-ready GLBs.

Run with Blender, from the repository root:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/import_foliage.py
"""

from pathlib import Path
import bpy


ROOT = Path.cwd()
NATURE = Path("/Users/zelda/Downloads/Ultimate Nature Pack by Quaternius")
TREES = Path("/Users/zelda/Downloads/Textured Stylized Trees - May 2020")
OUTPUT = ROOT / "assets" / "foliage"

# ID, source pack, source relative path. The selection emphasizes visibly distinct
# silhouettes and avoids filling build mode with every seasonal/numbered variant.
ASSETS = (
    ("nature_common_tree", NATURE, "OBJ/CommonTree_1.obj"),
    ("nature_birch_tree", NATURE, "OBJ/BirchTree_2.obj"),
    ("nature_pine_tree", NATURE, "OBJ/PineTree_3.obj"),
    ("nature_willow", NATURE, "OBJ/Willow_1.obj"),
    ("nature_palm", NATURE, "OBJ/PalmTree_2.obj"),
    ("nature_bush", NATURE, "OBJ/Bush_1.obj"),
    ("nature_berry_bush", NATURE, "OBJ/BushBerries_1.obj"),
    ("nature_cactus", NATURE, "OBJ/CactusFlowers_3.obj"),
    ("nature_flowers", NATURE, "OBJ/Flowers.obj"),
    ("nature_grass", NATURE, "OBJ/Grass.obj"),
    ("stylized_tree_1", TREES, "Blends/Tree_1.blend"),
    ("stylized_tree_4", TREES, "Blends/Tree_4.blend"),
    ("stylized_birch_1", TREES, "Blends/Birch_1.blend"),
    ("stylized_birch_5", TREES, "Blends/Birch_5.blend"),
    ("stylized_pine_1", TREES, "Blends/Pine_1.blend"),
    ("stylized_pine_3", TREES, "Blends/Pine_3.blend"),
    ("stylized_dead_tree", TREES, "Blends/DeadTree_1.blend"),
    ("stylized_dead_birch", TREES, "Blends/DeadBirch_1.blend"),
)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def load_source(source: Path):
    if source.suffix.lower() == ".blend":
        bpy.ops.wm.open_mainfile(filepath=str(source))
    else:
        reset_scene()
        bpy.ops.wm.obj_import(filepath=str(source), forward_axis="NEGATIVE_Z", up_axis="Y")


def reconnect_stylized_textures(asset_id: str):
    texture_dir = TREES / "Textures"
    for material in bpy.data.materials:
        name = material.name.lower()
        texture = None
        if "birch_bark" in name or ("bark" in name and "birch" in asset_id):
            texture = texture_dir / "Birch_Bark.png"
        elif "bark" in name:
            texture = texture_dir / "Tree_Bark.jpg"
        elif "pine" in name:
            texture = texture_dir / "Pine_Leaves.png"
        elif "leaf" in name or "leaves" in name:
            texture = texture_dir / ("Birch_Leaves_Green.png" if "birch" in asset_id else "Tree_Leaves.png")
        if texture is None or not texture.exists():
            continue
        material.use_nodes = True
        nodes = material.node_tree.nodes
        nodes.clear()
        output = nodes.new("ShaderNodeOutputMaterial")
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
        image_node = nodes.new("ShaderNodeTexImage")
        image_node.image = bpy.data.images.load(str(texture), check_existing=True)
        material.node_tree.links.new(image_node.outputs["Color"], shader.inputs["Base Color"])
        if texture.suffix.lower() == ".png":
            material.node_tree.links.new(image_node.outputs["Alpha"], shader.inputs["Alpha"])

    # The engine currently uses back-face culling. Give the pack's one-sided leaf
    # cards a paper-thin reverse face so their crowns remain intact from any view.
    for obj in [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]:
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        modifier = obj.modifiers.new(name="Engine double-sided cards", type="SOLIDIFY")
        modifier.thickness = 0.001
        bpy.ops.object.modifier_apply(modifier=modifier.name)
        obj.select_set(False)


def export_glb(destination: Path):
    destination.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(destination),
        export_format="GLB",
        export_materials="EXPORT",
        export_image_format="AUTO",
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
    )


for asset_id, pack, relative_source in ASSETS:
    source = pack / relative_source
    if not source.exists():
        raise FileNotFoundError(source)
    load_source(source)
    if pack == TREES:
        reconnect_stylized_textures(asset_id)
    export_glb(OUTPUT / f"{asset_id}.glb")
    print(f"IMPORTED {asset_id} from {source}")
