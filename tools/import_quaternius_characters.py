import bpy
import os
import sys


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.actions, bpy.data.armatures, bpy.data.meshes, bpy.data.materials):
        for datablock in list(datablocks):
            datablocks.remove(datablock)


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :]
    source, destination = argv
    reset_scene()
    bpy.ops.import_scene.fbx(filepath=source, use_anim=True)
    clip_names = {
        "Idle": "Idle_A",
        "Standing": "Idle_B",
        "Clapping": "Interact",
        "Walk": "Walking_B",
        "Run": "Running_A",
    }
    for action in bpy.data.actions:
        suffix = action.name.rsplit("_", 1)[-1]
        if suffix in clip_names:
            action.name = clip_names[suffix]
    # FBX opacity imports as zero for these otherwise opaque materials. Normalize
    # it before glTF export or alpha masking discards the complete character.
    for material in bpy.data.materials:
        material.diffuse_color[3] = 1.0
        if hasattr(material, "use_backface_culling"):
            material.use_backface_culling = True
        if material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type != "BSDF_PRINCIPLED":
                    continue
                alpha = node.inputs.get("Alpha")
                if alpha is not None:
                    alpha.default_value = 1.0
                base_color = node.inputs.get("Base Color")
                if base_color is not None:
                    color = list(base_color.default_value)
                    color[3] = 1.0
                    base_color.default_value = color
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=destination,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_skins=True,
        export_all_influences=False,
        export_yup=True,
    )
    print("EXPORTED", destination)
    print("ACTIONS", [action.name for action in bpy.data.actions])


main()
