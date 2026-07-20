package main

import "core:fmt"
import "core:math"
import "core:mem"
import "core:time"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"

vk_shadow_draw_eligible :: proc(
	draw: ^Vk_World_Draw,
	local: bool,
	light_position: Vec3,
	light_range: f32,
	light_room: int,
) -> bool {
	receiver_only :=
		draw.surface_kind == 1 ||
		draw.surface_kind == 3 ||
		draw.surface_kind == 4 ||
		draw.surface_kind == 6 ||
		draw.surface_kind == 7 ||
		draw.surface_kind == 11 ||
		draw.surface_kind == 12 ||
		draw.surface_kind == 14 ||
		(draw.surface_kind == 16 &&
				!draw.shadow_only); if draw.no_shadow || receiver_only || (draw.tint[3] < 128 && !draw.shadow_only) || (local && draw.shadow_only) do return false
	if local {dx, dz := draw.x - light_position.x, draw.z - light_position.z; if dx * dx + dz * dz > (light_range + 2) * (light_range + 2) do return false; draw_room := vk_world_room_at({draw.x, draw.z}); if light_room >= 0 && draw_room != light_room && !world_line_clear(draw.x, draw.z, light_position.x, light_position.z) do return false}
	return true
}

vk_shadow_render_layer :: proc(
	scene: ^Vk_World_Scene,
	command: vk.CommandBuffer,
	image: ^Vk_Shadow_Image,
	layer, matrix_index, frame_index: int,
	local := false,
	light_position := Vec3{},
	light_range: f32 = 0,
	light_room := -1,
) {
	if layer < 0 || layer >= len(image.layer_views) do return; clear := vk.ClearValue {
		depthStencil = {depth = 1},
	}; attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = image.layer_views[layer],
		imageLayout = .DEPTH_ATTACHMENT_OPTIMAL,
		loadOp      = .CLEAR,
		storeOp     = .STORE,
		clearValue  = clear,
	}; rendering := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {image.image.width, image.image.height}},
		layerCount = 1,
		pDepthAttachment = &attachment,
	}; vk.CmdBeginRendering(command, &rendering); viewport := vk.Viewport {
		width    = f32(image.image.width),
		height   = f32(image.image.height),
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		extent = {image.image.width, image.image.height},
	}; vk.CmdSetViewport(
		command,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(command, 0, 1, &scissor); vk.CmdBindPipeline(command, .GRAPHICS, scene.shadows.pipeline); vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.shadows.pipeline_layout, 0, 1, &scene.shadows.descriptors[frame_index], 0, nil)
	offset := vk.DeviceSize(
		0,
	); for &draw, draw_index in scene.draws {if !vk_shadow_draw_eligible(&draw, local, light_position, light_range, light_room) do continue; mesh := &scene.meshes[draw.mesh]; skinned := len(mesh.source.skin.joints) > 0; palette_slot := skinned ? vk_world_skin_slot(scene, draw_index) : -1; skin_offset := u32(max(palette_slot, 0) * GLB_MAX_JOINTS); if skinned {if palette_slot < 0 || !vk_world_write_palette(scene, mesh.source, &draw, palette_slot, frame_index) do continue}; vk.CmdBindVertexBuffers(command, 0, 1, &mesh.vertices.handle, &offset); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32); model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); push := Vk_Shadow_Push{model, {skinned ? 1 : 0, skin_offset, u32(matrix_index), 0}}; vk.CmdPushConstants(command, scene.shadows.pipeline_layout, {.VERTEX}, 0, u32(size_of(push)), &push); for primitive in mesh.source.primitives do vk.CmdDrawIndexed(command, u32(primitive.count), 1, u32(primitive.first), 0, 0)}; vk.CmdEndRendering(command)
}

vk_world_shadow_record :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	command: vk.CommandBuffer,
	g: ^Game,
	frame_index: int,
) {
	if !scene.shadows.ready || len(scene.draws) == 0 do return; state := &scene.shadows; view := vk_world_view_pose(g); count := view.interior ? 1 : lighting_quality_directional_cascades(g.lighting_quality); state.cascade_count = count; state.splits = vk_shadow_practical_splits(count, .08, 120); focus := view.target; weather_strength := g.screen == .Exterior ? f32(1) : clamp(g.environment_blend, 0, 1); light_direction := world_key_light_direction(g.animation_time, weather_strength); resolution := f32(state.directional.image.width)
	for cascade in 0 ..< count {far := state.splits[cascade]; interior_radius := max(f32(max(level_document.width, level_document.height)) * .75, f32(24)); radius := view.interior ? interior_radius : max(far * .72, f32(5)); texel := radius * 2 / resolution; center := focus; center.x = f32(math.round(f64(center.x / texel))) * texel; center.z = f32(math.round(f64(center.z / texel))) * texel; eye := Vec3{center.x - light_direction.x * radius * 2, center.y - light_direction.y * radius * 2, center.z - light_direction.z * radius * 2}; state.matrices[cascade] = glb_mat4_multiply(vk_world_orthographic(-radius, radius, -radius, radius, .05, radius * 5), vk_world_look_at(eye, center, {0, 1, 0}))}
	runtime_lights := make(
		[dynamic]Vk_World_Runtime_Light,
		0,
		VK_WORLD_MAX_LIGHTS,
		context.temp_allocator,
	); sequence := 0; for light in level_document.lights {if light.story != level_document.active_story do continue; base_y := f32(0); if light.story >= 0 && light.story < len(level_document.stories) do base_y = level_document.stories[light.story].base_elevation; vk_world_runtime_light_insert(&runtime_lights, Vk_World_Runtime_Light{position = {light.position.x, base_y + light.elevation, light.position.y, light.range}, color = {f32(light.color[0]) / 255, f32(light.color[1]) / 255, f32(light.color[2]) / 255, light.intensity * .34}, params = {f32(light.kind), light.facing * f32(math.PI) / 180, f32(math.cos(f64(light.cone_angle * .5 * f32(math.PI) / 180))), 0}, room = vk_world_room_at(light.position), sequence = sequence}, focus); sequence += 1}; for object in level_document.objects {if object.story != level_document.active_story do continue; entry, found := catalog_object_entry(object.catalog_id); if !found || !entry.emits_light do continue; has_bound := false; for light in level_document.lights do if fmt.tprintf("light_%s", object.id) == light.id do has_bound = true; if has_bound do continue; base_y := object.elevation; if object.story >= 0 && object.story < len(level_document.stories) do base_y += level_document.stories[object.story].base_elevation; if level_terrain_supports_position(&level_document, object.position, object.story) do base_y += level_terrain_height(&level_document, object.position); vk_world_runtime_light_insert(&runtime_lights, Vk_World_Runtime_Light{position = {object.position.x, base_y + entry.light_height, object.position.y, entry.light_range}, color = {f32(entry.light_color[0]) / 255, f32(entry.light_color[1]) / 255, f32(entry.light_color[2]) / 255, entry.light_intensity * .34}, params = {f32(entry.light_kind), (object.rotation + entry.light_facing) * f32(math.PI) / 180, f32(math.cos(f64(entry.light_cone_angle * .5 * f32(math.PI) / 180))), 0}, room = vk_world_room_at(object.position), sequence = sequence}, focus); sequence += 1}
	if g.screen == .Exterior do vk_world_add_city_vehicle_lights(&runtime_lights, g, focus)
	for &source in state.point_sources do source = -1; for &source in state.spot_sources do source = -1; point_count, spot_count := 0, 0; point_limit := lighting_quality_point_shadow_slots(g.lighting_quality); spot_limit := lighting_quality_spot_shadow_slots(g.lighting_quality); face_budget := lighting_quality_shadow_face_budget(g.lighting_quality); faces_used := 0
	cube_directions := [6]Vec3 {
		{1, 0, 0},
		{-1, 0, 0},
		{0, 1, 0},
		{0, -1, 0},
		{0, 0, 1},
		{0, 0, -1},
	}; cube_ups := [6]Vec3{{0, -1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}, {0, -1, 0}, {0, -1, 0}}
	for light in runtime_lights {if light.params[0] < .5 &&
		   point_count < point_limit &&
		   faces_used + 6 <=
			   face_budget {slot := point_count; state.point_sources[slot] = light.sequence; position := Vec3{light.position[0], light.position[1], light.position[2]}; for face in 0 ..< 6 {matrix_index := 4 + slot * 6 + face; direction := cube_directions[face]; state.matrices[matrix_index] = glb_mat4_multiply(vk_world_perspective(math.PI / 2, 1, .08, max(light.position[3], .1)), vk_world_look_at(position, {position.x + direction.x, position.y + direction.y, position.z + direction.z}, cube_ups[face]))}; point_count += 1; faces_used += 6} else if light.params[0] > .5 && light.params[0] < 1.5 && spot_count < spot_limit && faces_used < face_budget {slot := spot_count; state.spot_sources[slot] = light.sequence; position := Vec3{light.position[0], light.position[1], light.position[2]}; direction := vk_world_normalize({f32(math.cos(f64(light.params[1]))), -.35, f32(math.sin(f64(light.params[1])))}); matrix_index := 28 + slot; cone := f32(math.acos(f64(clamp(light.params[2], -.99, .99)))) * 2; state.matrices[matrix_index] = glb_mat4_multiply(vk_world_perspective(max(cone, .15), 1, .08, max(light.position[3], .1)), vk_world_look_at(position, {position.x + direction.x, position.y + direction.y, position.z + direction.z}, {0, 1, 0})); spot_count += 1; faces_used += 1}}
	mem.copy_non_overlapping(
		state.matrix_buffers[frame_index].mapped,
		raw_data(state.matrices[:]),
		len(state.matrices) * size_of(Glb_Mat4),
	); engine.vk_cmd_image_barrier2(ctx, command, state.directional.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for cascade in 0 ..< count do vk_shadow_render_layer(scene, command, &state.directional, cascade, cascade, frame_index); engine.vk_cmd_image_barrier2(ctx, command, state.directional.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})
	if point_count >
	   0 {engine.vk_cmd_image_barrier2(ctx, command, state.points.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for slot in 0 ..< point_count {source := state.point_sources[slot]; for light in runtime_lights do if light.sequence == source {position := Vec3{light.position[0], light.position[1], light.position[2]}; for face in 0 ..< 6 do vk_shadow_render_layer(scene, command, &state.points, slot * 6 + face, 4 + slot * 6 + face, frame_index, true, position, light.position[3], light.room); break}}; engine.vk_cmd_image_barrier2(ctx, command, state.points.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})}
	if spot_count >
	   0 {engine.vk_cmd_image_barrier2(ctx, command, state.spots.image.image, {.TOP_OF_PIPE, .FRAGMENT_SHADER}, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.SHADER_READ}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, .UNDEFINED, .DEPTH_ATTACHMENT_OPTIMAL, {.DEPTH}); for slot in 0 ..< spot_count {source := state.spot_sources[slot]; for light in runtime_lights do if light.sequence == source {vk_shadow_render_layer(scene, command, &state.spots, slot, 28 + slot, frame_index, true, {light.position[0], light.position[1], light.position[2]}, light.position[3], light.room); break}}; engine.vk_cmd_image_barrier2(ctx, command, state.spots.image.image, {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS}, {.FRAGMENT_SHADER}, {.DEPTH_STENCIL_ATTACHMENT_WRITE}, {.SHADER_READ}, .DEPTH_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, {.DEPTH})}
}

vk_world_draw_primitive_batchable :: proc(
	mesh: ^Vk_World_Mesh,
	draw: ^Vk_World_Draw,
	primitive_index: int,
) -> bool {
	if draw.shadow_only || len(mesh.source.skin.joints) > 0 || draw.tint[3] < 255 do return false
	alpha_mode :=
		primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0
	return alpha_mode != 2
}

vk_world_texture_flags :: proc(
	mesh: ^Vk_World_Mesh,
	primitive_index, normal_index, roughness_index: int,
) -> int {
	primitive := mesh.source.primitives[primitive_index]
	material_name :=
		primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; thin_wall := glb_thin_wall_material_role(material_name) > 0
	return(
		(primitive.texture >= 0 ? 1 : 0) +
		(normal_index >= 0 ? 2 : 0) +
		(roughness_index >= 0 ? 4 : 0) +
		(thin_wall ? 8 : 0) \
	)
}

vk_world_draw_push :: proc(
	scene: ^Vk_World_Scene,
	mesh: ^Vk_World_Mesh,
	draw: ^Vk_World_Draw,
	draw_index, primitive_index: int,
	skinned: bool = false,
	skin_offset: u32 = 0,
) -> Vk_World_Push {
	primitive :=
		mesh.source.primitives[primitive_index]; model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); primitive_tint := [4]f32{f32(draw.tint[0]) / 255, f32(draw.tint[1]) / 255, f32(draw.tint[2]) / 255, f32(draw.tint[3]) / 255}; material_name := primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; role := glb_foliage_material_role(material_name); if draw.foliage_colors && role == 1 do primitive_tint = {f32(draw.bark_tint[0]) / 255, f32(draw.bark_tint[1]) / 255, f32(draw.bark_tint[2]) / 255, f32(draw.bark_tint[3]) / 255}; if draw.foliage_colors && role == 2 do primitive_tint = {f32(draw.foliage_tint[0]) / 255, f32(draw.foliage_tint[1]) / 255, f32(draw.foliage_tint[2]) / 255, f32(draw.foliage_tint[3]) / 255}; alpha_mode := primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0; alpha_cutoff := primitive_index < len(mesh.source.alpha_cutoffs) ? mesh.source.alpha_cutoffs[primitive_index] : f32(.5); if draw.foliage_colors && alpha_mode == 2 {alpha_mode = 1; alpha_cutoff = .5}; alpha_state := f32(alpha_mode) + alpha_cutoff * .1; normal_index := primitive_index < len(mesh.source.normal_textures) ? mesh.source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(mesh.source.roughness_textures) ? mesh.source.roughness_textures[primitive_index] : -1; texture_flags := vk_world_texture_flags(mesh, primitive_index, normal_index, roughness_index); pbr := [4]f32{0, .72, 1, 0}; authored_pbr := primitive_index < len(mesh.source.roughness_factors); if primitive_index < len(mesh.source.metallic_factors) do pbr.x = mesh.source.metallic_factors[primitive_index]; if authored_pbr do pbr.y = mesh.source.roughness_factors[primitive_index]; if primitive_index < len(mesh.source.normal_scales) do pbr.z = mesh.source.normal_scales[primitive_index]; pbr.w = authored_pbr ? 1 : 0; return {model, primitive_tint * primitive.base_color, {f32(texture_flags), f32(draw.surface_kind), f32(scene.draw_lights[draw_index].meta[1]), alpha_state}, pbr, {skinned ? 1 : 0, skin_offset, u32(draw_index), 0}}
}

vk_world_record :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	command: vk.CommandBuffer,
	extent: vk.Extent2D,
	g: ^Game,
	frame_index: int,
) {
	if len(scene.draws) == 0 do return; if scene.depth.width != extent.width || scene.depth.height != extent.height {_ = vk.DeviceWaitIdle(ctx.device); vk_ui_image_destroy(&scene.depth, ctx); if !vk_world_depth_create(ctx, extent.width, extent.height, &scene.depth) do return}
	scene.profile_lights_ms = 0; scene.profile_batches_ms = 0; scene.profile_unbatched_ms = 0; lights_started := time.tick_now()
	view := vk_world_view_pose(
		g,
	); eye, target, up := view.eye, view.target, view.up; interior, baking := view.interior, view.baking; projection_aspect := baking ? f32(1) : f32(extent.width) / f32(max(extent.height, 1)); field_of_view := f32(math.PI / 3); if g.screen == .Exterior && g.driving_vehicle >= 0 && g.driving_vehicle < len(g.vehicles) do field_of_view = vehicle_camera_field_of_view(g.vehicles[g.driving_vehicle]); weather_strength := g.screen == .Exterior ? f32(1) : clamp(g.environment_blend, 0, 1); if baking do weather_strength = 0; interior_amount := baking ? f32(1) : 1 - weather_strength; camera := Vk_World_Camera {
		view_projection = glb_mat4_multiply(
			vk_world_perspective(field_of_view, projection_aspect, .08, 140),
			vk_world_look_at(eye, target, up),
		),
		camera_position = {eye.x, eye.y, eye.z, 1},
		lighting        = {interior_amount, 1 - interior_amount * .18, 0, 0},
		atmosphere      = {
			weather_strength,
			g.animation_time,
			world_time_of_day(g.animation_time),
			0,
		},
	}; for shadow_matrix, index in scene.shadows.matrices[:4] do camera.directional_shadow_matrices[index] = shadow_matrix; camera.directional_shadow_splits = scene.shadows.splits; camera.directional_shadow_params = {f32(scene.shadows.cascade_count), .0007, .003, 1 / f32(max(scene.shadows.directional.image.width, 1))}
	runtime_lights := make(
		[dynamic]Vk_World_Runtime_Light,
		0,
		VK_WORLD_MAX_LIGHTS,
		context.temp_allocator,
	); sequence := 0
	// The character studio is a diagnostic stage, so it uses a stable neutral
	// review rig instead of inheriting the active level's night lighting. A broad
	// warm key and cool fill for each model keep skin, clothing, and silhouettes
	// readable while retaining enough directionality to reveal deformation.
	if g.character_studio {
		studio_x := [4]f32{-3, -1, 1, 3}
		for x in studio_x {
			append(
				&runtime_lights,
				Vk_World_Runtime_Light {
					position = {x, 3.8, 2.6, 7.5},
					color = {1.0, .91, .78, 1.65},
					params = {2, 0, 0, 0},
					room = vk_world_room_at({x, 0}),
					sequence = sequence,
				},
			); sequence += 1
		}
		append(
			&runtime_lights,
			Vk_World_Runtime_Light {
				position = {0, 2.7, -3.2, 9},
				color = {.48, .67, 1.0, .82},
				params = {2, 0, 0, 0},
				room = vk_world_room_at({0, 0}),
				sequence = sequence,
			},
		); sequence += 1
	}
	if interior {for light in level_document.lights {if light.story != level_document.active_story do continue; base_y := f32(0); if light.story >= 0 && light.story < len(level_document.stories) do base_y = level_document.stories[light.story].base_elevation; light_level := f32(1); for object in level_document.objects {if fmt.tprintf("light_%s", object.id) == light.id {interactive_index := runtime_interactive_index(g, object.id); if interactive_index >= 0 do light_level = g.interactives[interactive_index].light_level; break}}; runtime := Vk_World_Runtime_Light {
				position = {
					light.position.x,
					base_y + light.elevation,
					light.position.y,
					light.range,
				},
				color    = {
					f32(light.color[0]) / 255,
					f32(light.color[1]) / 255,
					f32(light.color[2]) / 255,
					light.intensity * .34 * light_level,
				},
				params   = {
					f32(light.kind),
					light.facing * f32(math.PI) / 180,
					f32(math.cos(f64(light.cone_angle * .5 * f32(math.PI) / 180))),
					0,
				},
				room     = vk_world_room_at(light.position),
				sequence = sequence,
			}; vk_world_runtime_light_insert(&runtime_lights, runtime, eye); sequence += 1}}
	if interior {for object in level_document.objects {if object.story != level_document.active_story do continue; entry, found := catalog_object_entry(object.catalog_id); if !found || !entry.emits_light do continue; has_bound_light := false; for light in level_document.lights do if fmt.tprintf("light_%s", object.id) == light.id do has_bound_light = true; if has_bound_light do continue; base_y := object.elevation; if object.story >= 0 && object.story < len(level_document.stories) do base_y += level_document.stories[object.story].base_elevation; if level_terrain_supports_position(&level_document, object.position, object.story) do base_y += level_terrain_height(&level_document, object.position); light_level := f32(1); interactive_index := runtime_interactive_index(g, object.id); if interactive_index >= 0 do light_level = g.interactives[interactive_index].light_level; runtime := Vk_World_Runtime_Light {
				position = {
					object.position.x,
					base_y + entry.light_height,
					object.position.y,
					entry.light_range,
				},
				color    = {
					f32(entry.light_color[0]) / 255,
					f32(entry.light_color[1]) / 255,
					f32(entry.light_color[2]) / 255,
					entry.light_intensity * .34 * light_level,
				},
				params   = {
					f32(entry.light_kind),
					(object.rotation + entry.light_facing) * f32(math.PI) / 180,
					f32(math.cos(f64(entry.light_cone_angle * .5 * f32(math.PI) / 180))),
					0,
				},
				room     = vk_world_room_at(object.position),
				sequence = sequence,
			}; vk_world_runtime_light_insert(&runtime_lights, runtime, eye); sequence += 1}}
	if g.screen == .Exterior do vk_world_add_city_vehicle_lights(&runtime_lights, g, eye)
	for light, slot in runtime_lights {camera.light_positions[slot] = light.position
		camera.light_colors[slot] = light.color
		camera.light_params[slot] = light.params
		for source, shadow_slot in scene.shadows.point_sources do if source == light.sequence do camera.light_shadow_meta[slot] = {1, f32(shadow_slot), light.position[3], .003}
		for source, shadow_slot in scene.shadows.spot_sources do if source == light.sequence do camera.light_shadow_meta[slot] = {2, f32(shadow_slot), light.position[3], .002}}; for matrix_index in 0 ..< 24 do camera.point_shadow_matrices[matrix_index] = scene.shadows.matrices[4 + matrix_index]; for shadow_slot in 0 ..< 10 do camera.local_shadow_matrices[shadow_slot] = scene.shadows.matrices[28 + shadow_slot]; camera.lighting[2] = f32(len(runtime_lights)); vk_world_build_draw_light_lists(scene, runtime_lights[:], g.lighting_quality, frame_index)
	scene.profile_lights_ms =
		time.duration_seconds(time.tick_diff(lights_started, time.tick_now())) *
		1000; mem.copy_non_overlapping(scene.cameras[frame_index].mapped, &camera, size_of(camera)); viewport := vk.Viewport {
		width    = f32(extent.width),
		height   = f32(extent.height),
		minDepth = 0,
		maxDepth = 1,
	}; scissor := vk.Rect2D {
		extent = extent,
	}; vk.CmdSetViewport(
		command,
		0,
		1,
		&viewport,
	); vk.CmdSetScissor(command, 0, 1, &scissor); vk.CmdBindPipeline(command, .GRAPHICS, scene.pipeline); batches_started := time.tick_now()
	// Opaque static props are order-independent. Preserve their per-object data
	// in a storage buffer and collapse each repeated mesh primitive to one draw.
	mesh_offsets := make(
		[]int,
		len(scene.meshes) + 1,
		context.temp_allocator,
	); draw_order := make([]int, len(scene.draws), context.temp_allocator); for draw in scene.draws do mesh_offsets[draw.mesh + 1] += 1; for i in 1 ..< len(mesh_offsets) do mesh_offsets[i] += mesh_offsets[i - 1]; cursors := make([]int, len(scene.meshes), context.temp_allocator); copy(cursors, mesh_offsets[:len(scene.meshes)]); for draw, draw_index in scene.draws {draw_order[cursors[draw.mesh]] = draw_index; cursors[draw.mesh] += 1}
	instance_data := transmute([^]Vk_World_Push)(scene.instance_buffer.mapped); instance_start := frame_index * VK_WORLD_INSTANCES_PER_FRAME; instance_count := instance_start; vertex_offset := vk.DeviceSize(0)
	for &mesh, mesh_index in scene.meshes {
		if len(mesh.source.skin.joints) > 0 do continue
		vk.CmdBindVertexBuffers(
			command,
			0,
			1,
			&mesh.vertices.handle,
			&vertex_offset,
		); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32)
		for primitive, primitive_index in mesh.source.primitives {
			batch_start := instance_count
			for order_index in mesh_offsets[mesh_index] ..< mesh_offsets[mesh_index + 1] {
				draw_index := draw_order[order_index]; draw := &scene.draws[draw_index]
				if !vk_world_draw_primitive_batchable(&mesh, draw, primitive_index) || instance_count >= instance_start + VK_WORLD_INSTANCES_PER_FRAME do continue
				instance_data[instance_count] = vk_world_draw_push(
					scene,
					&mesh,
					draw,
					draw_index,
					primitive_index,
				); instance_count += 1
			}
			batch_count := instance_count - batch_start; if batch_count == 0 do continue
			set_index :=
				primitive_index * engine.MAX_FRAMES_IN_FLIGHT +
				frame_index; if set_index < 0 || set_index >= len(mesh.sets) do set_index = frame_index; set := mesh.sets[set_index]; vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.pipeline_layout, 0, 1, &set, 0, nil); push := Vk_World_Push{}; push.skin = {0, 0, u32(batch_start), 1}; vk.CmdPushConstants(command, scene.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); vk.CmdDrawIndexed(command, u32(primitive.count), u32(batch_count), u32(primitive.first), 0, 0)
		}
	}
	scene.profile_batches_ms =
		time.duration_seconds(time.tick_diff(batches_started, time.tick_now())) *
		1000; unbatched_started := time.tick_now()
	for &draw, draw_index in scene.draws {if draw.shadow_only do continue; mesh := &scene.meshes[draw.mesh]; skinned := len(mesh.source.skin.joints) > 0; palette_slot := skinned ? vk_world_skin_slot(scene, draw_index) : -1; if skinned && (palette_slot < 0 || !vk_world_write_palette(scene, mesh.source, &draw, palette_slot, frame_index)) do continue; skin_offset := u32(max(palette_slot, 0) * GLB_MAX_JOINTS); offset := vk.DeviceSize(0); vk.CmdBindVertexBuffers(command, 0, 1, &mesh.vertices.handle, &offset); vk.CmdBindIndexBuffer(command, mesh.indices.handle, 0, .UINT32); model := vk_world_model(mesh.source, draw.x, draw.z, draw.width, draw.height, draw.yaw, draw.pitch, draw.base_y, draw.scale_by_footprint, draw.centered, draw.roll); tint := [4]f32{f32(draw.tint[0]) / 255, f32(draw.tint[1]) / 255, f32(draw.tint[2]) / 255, f32(draw.tint[3]) / 255}; light_selector := f32(scene.draw_lights[draw_index].meta[1]); for primitive, primitive_index in mesh.source.primitives {if vk_world_draw_primitive_batchable(mesh, &draw, primitive_index) do continue; primitive_tint := tint; material_name := primitive_index < len(mesh.source.material_names) ? mesh.source.material_names[primitive_index] : ""; role := glb_foliage_material_role(material_name); if draw.foliage_colors && role == 1 do primitive_tint = {f32(draw.bark_tint[0]) / 255, f32(draw.bark_tint[1]) / 255, f32(draw.bark_tint[2]) / 255, f32(draw.bark_tint[3]) / 255}; if draw.foliage_colors && role == 2 do primitive_tint = {f32(draw.foliage_tint[0]) / 255, f32(draw.foliage_tint[1]) / 255, f32(draw.foliage_tint[2]) / 255, f32(draw.foliage_tint[3]) / 255}; set_index := primitive_index * engine.MAX_FRAMES_IN_FLIGHT + frame_index; if set_index < 0 || set_index >= len(mesh.sets) do set_index = frame_index; set := mesh.sets[set_index]; vk.CmdBindDescriptorSets(command, .GRAPHICS, scene.pipeline_layout, 0, 1, &set, 0, nil); alpha_mode := primitive_index < len(mesh.source.alpha_modes) ? mesh.source.alpha_modes[primitive_index] : 0; alpha_cutoff := primitive_index < len(mesh.source.alpha_cutoffs) ? mesh.source.alpha_cutoffs[primitive_index] : f32(.5); if draw.foliage_colors && alpha_mode == 2 {alpha_mode = 1; alpha_cutoff = .5}; alpha_state := f32(alpha_mode) + alpha_cutoff * .1; normal_index := primitive_index < len(mesh.source.normal_textures) ? mesh.source.normal_textures[primitive_index] : -1; roughness_index := primitive_index < len(mesh.source.roughness_textures) ? mesh.source.roughness_textures[primitive_index] : -1; texture_flags := vk_world_texture_flags(mesh, primitive_index, normal_index, roughness_index); pbr := [4]f32{0, .72, 1, 0}; authored_pbr := primitive_index < len(mesh.source.roughness_factors); if primitive_index < len(mesh.source.metallic_factors) do pbr.x = mesh.source.metallic_factors[primitive_index]; if authored_pbr do pbr.y = mesh.source.roughness_factors[primitive_index]; if primitive_index < len(mesh.source.normal_scales) do pbr.z = mesh.source.normal_scales[primitive_index]; pbr.w = authored_pbr ? 1 : 0; push := Vk_World_Push{model, primitive_tint * primitive.base_color, {f32(texture_flags), f32(draw.surface_kind), light_selector, alpha_state}, pbr, {skinned ? 1 : 0, skin_offset, u32(draw_index), 0}}; vk.CmdPushConstants(command, scene.pipeline_layout, {.VERTEX, .FRAGMENT}, 0, u32(size_of(push)), &push); vk.CmdDrawIndexed(command, u32(primitive.count), 1, u32(primitive.first), 0, 0)}}
	scene.profile_unbatched_ms =
		time.duration_seconds(time.tick_diff(unbatched_started, time.tick_now())) * 1000
}
