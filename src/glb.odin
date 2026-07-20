package main

import "core:strings"
import gltf "zelda_engine:gltf"

Vec3 :: gltf.Vec3
Vec4 :: gltf.Vec4
Glb_Joints :: gltf.Glb_Joints
Glb_Mat4 :: gltf.Glb_Mat4
Glb_Mesh :: gltf.Glb_Mesh
Glb_Primitive_Range :: gltf.Glb_Primitive_Range
Glb_TRS :: gltf.Glb_TRS
Glb_Texture_Data :: gltf.Glb_Texture_Data
GLB_MAX_JOINTS :: gltf.GLB_MAX_JOINTS

glb_blend_pose :: gltf.glb_blend_pose
glb_clip_index :: gltf.glb_clip_index
glb_clip_index_suffix :: gltf.glb_clip_index_suffix
glb_has_animation :: gltf.glb_has_animation
glb_mat4_multiply :: gltf.glb_mat4_multiply
glb_pose_palette :: gltf.glb_pose_palette
glb_quat_slerp :: gltf.glb_quat_slerp
glb_sample_pose :: gltf.glb_sample_pose

character_meshes: [4]Glb_Mesh
CHARACTER_MESH_PATHS :: [4]string {
	"assets/quaternius_animated_people/investigator.glb",
	"assets/quaternius_animated_people/miriam.glb",
	"assets/quaternius_animated_people/daniel.glb",
	"assets/quaternius_animated_people/elsie.glb",
}

glb_foliage_material_role :: proc(name: string) -> int {
	lower := strings.to_lower(name)
	if strings.contains(lower, "bark") || strings.contains(lower, "wood") || strings.contains(lower, "trunk") || strings.contains(lower, "branch") do return 1
	if strings.contains(lower, "leaf") || strings.contains(lower, "leaves") || strings.contains(lower, "green") || strings.contains(lower, "foliage") || strings.contains(lower, "grass") || strings.contains(lower, "flower") || strings.contains(lower, "cactus") do return 2
	return 0
}

glb_thin_wall_material_role :: proc(name: string) -> int {
	lower := strings.to_lower(strings.trim_space(name))
	if lower == "lamp" || strings.contains(lower, "lampshade") || strings.contains(lower, "lamp_shade") do return 1
	return 0
}

glb_load :: proc(path: string, allocator := context.allocator) -> (Glb_Mesh, bool) {
	return gltf.glb_load(path, allocator)
}
