package main

import "core:mem"
import engine "zelda_engine:engine"

vk_world_begin :: proc(scene: ^Vk_World_Scene) {clear(&scene.draws)}
vk_world_draw_capacity_available :: proc(draw_count: int) -> bool {return(
		draw_count >= 0 &&
		draw_count < VK_WORLD_DRAW_CAPACITY \
	)}
vk_world_append_draw :: proc(
	scene: ^Vk_World_Scene,
	draw: Vk_World_Draw,
) -> bool {if !vk_world_draw_capacity_available(len(scene.draws)) do return false; append(
		&scene.draws,
		draw,
	)
	return true}
vk_world_add :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	tint := [4]u8{255, 255, 255, 255},
	footprint := false,
	surface_kind := 0,
	base_y: f32 = 0,
	pitch: f32 = 0,
	roll: f32 = 0,
	shadow_only := false,
	no_shadow: bool = false,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, roll = roll, base_y = base_y, tint = tint, scale_by_footprint = footprint, shadow_only = shadow_only, no_shadow = no_shadow, surface_kind = surface_kind, clip_a = -1, clip_b = -1})}
vk_world_add_centered :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, center_y, height, yaw, pitch: f32,
	tint := [4]u8{255, 255, 255, 255},
	surface_kind := 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, base_y = center_y, tint = tint, centered = true, surface_kind = surface_kind, clip_a = -1, clip_b = -1})}
vk_world_add_sized :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, width, height, yaw: f32,
	tint := [4]u8{255, 255, 255, 255},
	surface_kind := 0,
	base_y: f32 = 0,
	no_shadow: bool = false,
	light_anchor: Vec2 = {},
	use_light_anchor: bool = false,
	light_group: u64 = 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, width = width, height = height, yaw = yaw, base_y = base_y, tint = tint, surface_kind = surface_kind, no_shadow = no_shadow, light_x = light_anchor.x, light_z = light_anchor.y, light_group = light_group, use_light_anchor = use_light_anchor, clip_a = -1, clip_b = -1})}
vk_world_add_foliage :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	bark_tint, foliage_tint: [4]u8,
	base_y: f32 = 0,
	no_shadow: bool = false,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, base_y = base_y, tint = {255, 255, 255, 255}, bark_tint = bark_tint, foliage_tint = foliage_tint, foliage_colors = true, no_shadow = no_shadow, clip_a = -1, clip_b = -1})}
vk_world_add_animated :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	mesh: ^Glb_Mesh,
	x, z, height, yaw: f32,
	tint: [4]u8,
	clip_a, clip_b: int,
	time_a, time_b, blend: f32,
	base_y: f32 = 0,
	surface_kind := 5,
	pitch: f32 = 0,
) {if len(scene.draws) >= VK_WORLD_DRAW_CAPACITY do return; index := vk_world_register_mesh(
		scene,
		ctx,
		mesh,
	)
	if index >= 0 do _ = vk_world_append_draw(scene, Vk_World_Draw{mesh = index, x = x, z = z, height = height, yaw = yaw, pitch = pitch, base_y = base_y, tint = tint, surface_kind = surface_kind, clip_a = clip_a, clip_b = clip_b, time_a = time_a, time_b = time_b, blend = blend})}

vk_world_write_palette :: proc(
	scene: ^Vk_World_Scene,
	mesh: ^Glb_Mesh,
	draw: ^Vk_World_Draw,
	slot, frame_index: int,
) -> bool {if slot < 0 || slot >= VK_WORLD_MAX_SKINNED_DRAWS || len(mesh.skin.joints) == 0 do return false
	pose_a := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	pose_b := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	pose := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator)
	if !glb_sample_pose(mesh, draw.clip_a, draw.time_a, false, pose_a) do return false
	if draw.clip_b >= 0 && draw.blend > 0 {if !glb_sample_pose(mesh, draw.clip_b, draw.time_b, false, pose_b) do return false
		glb_blend_pose(pose_a, pose_b, clamp(draw.blend, 0, 1), pose)}
	else {copy(pose, pose_a)}
	palette := make([]Glb_Mat4, len(mesh.skin.joints), context.temp_allocator)
	if !glb_pose_palette(mesh, pose, palette) do return false
	destination :=
		uintptr(scene.palettes[frame_index].mapped) +
		uintptr(slot * GLB_MAX_JOINTS * size_of(Glb_Mat4))
	mem.copy_non_overlapping(
		rawptr(destination),
		raw_data(palette),
		len(palette) * size_of(Glb_Mat4),
	)
	return true}

// Palette slots belong to scene draws, not to a particular shadow light's
// filtered caster list. The mapped palette buffer is shared by every recorded
// shadow layer and the visible pass, so compacting slots after light culling
// makes a queued shadow draw read another character's final pose at submit.
vk_world_skin_slot :: proc(scene: ^Vk_World_Scene, draw_index: int) -> int {
	if draw_index < 0 || draw_index >= len(scene.draws) do return -1
	slot := 0
	for draw, i in scene.draws {
		if i >= draw_index do break
		mesh := &scene.meshes[draw.mesh]
		if len(mesh.source.skin.joints) > 0 do slot += 1
	}
	draw := &scene.draws[draw_index]
	mesh := &scene.meshes[draw.mesh]; if len(mesh.source.skin.joints) == 0 do return -1
	return slot
}
