package main

import "core:math"
import "core:mem"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import resources "zelda_engine:render_resources"

vk_world_model :: proc(
	mesh: ^Glb_Mesh,
	x, z, width, height, yaw, pitch, base_y: f32,
	footprint: bool,
	centered := false,
	roll: f32 = 0,
) -> Glb_Mat4 {
	dimension :=
		footprint ? max(mesh.max.x - mesh.min.x, mesh.max.z - mesh.min.z) : mesh.max.y - mesh.min.y; if dimension <= 0 do dimension = 1
	sy :=
		height /
		dimension; sx, sz := sy, sy; if width > 0 {span_x := mesh.max.x - mesh.min.x; if span_x > .0001 do sx = width / span_x; sz = 1}
	cx, cy, cz :=
		(mesh.min.x + mesh.max.x) *
		.5,
		(mesh.min.y + mesh.max.y) *
		.5,
		(mesh.min.z + mesh.max.z) *
		.5; c, si := f32(math.cos(f64(yaw))), f32(math.sin(f64(yaw))); cp, sp := f32(math.cos(f64(pitch))), f32(math.sin(f64(pitch))); cr, sr := f32(math.cos(f64(roll))), f32(math.sin(f64(roll)))
	c0x, c0y, c0z :=
		(c * cr - si * sp * sr) *
		sx,
		cp *
		sr *
		sx,
		(si * cr + c * sp * sr) *
		sx; c1x, c1y, c1z := (-c * sr - si * sp * cr) * sy, cp * cr * sy, (-si * sr + c * sp * cr) * sy; c2x, c2y, c2z := -si * cp * sz, -sp * sz, c * cp * sz
	if centered {tx := x - (c0x * cx + c1x * cy + c2x * cz); ty := base_y - (c0y * cx + c1y * cy + c2y * cz); tz := z - (c0z * cx + c1z * cy + c2z * cz); return {c0x, c0y, c0z, 0, c1x, c1y, c1z, 0, c2x, c2y, c2z, 0, tx, ty, tz, 1}}
	return {
		c0x,
		c0y,
		c0z,
		0,
		c1x,
		c1y,
		c1z,
		0,
		c2x,
		c2y,
		c2z,
		0,
		x - (c0x * cx + c2x * cz),
		base_y - mesh.min.y * sy,
		z - (c0z * cx + c2z * cz),
		1,
	}
}

vk_world_room_at :: proc(point: Vec2) -> int {for room, i in level_document.rooms do if room.story == level_document.active_story && !room.exterior && level_point_in_polygon(point, room.points[:]) do return i
	return -1}

vk_world_runtime_light_score :: proc(light: Vk_World_Runtime_Light, eye: Vec3) -> f32 {dx, dz :=
		light.position[0] - eye.x, light.position[2] - eye.z
	return light.color[3] / (1 + dx * dx + dz * dz)}
vk_world_runtime_light_insert :: proc(
	out: ^[dynamic]Vk_World_Runtime_Light,
	light: Vk_World_Runtime_Light,
	eye: Vec3,
) {
	if len(out) <
	   VK_WORLD_MAX_LIGHTS {append(out, light); return}; wanted := vk_world_runtime_light_score(light, eye); worst := 0; worst_score := vk_world_runtime_light_score(out[0], eye); for candidate, i in out {score := vk_world_runtime_light_score(candidate, eye); if score < worst_score || (score == worst_score && candidate.sequence > out[worst].sequence) {worst = i; worst_score = score}}; if wanted > worst_score do out[worst] = light
}

vk_world_add_city_vehicle_lights :: proc(
	out: ^[dynamic]Vk_World_Runtime_Light,
	g: ^Game,
	focus: Vec3,
) {
	headlight_signs := [2]f32{-1, 1}
	for vehicle, vehicle_index in g.vehicles {
		forward := Vec2 {
			f32(math.cos(f64(vehicle.heading))),
			f32(math.sin(f64(vehicle.heading))),
		}; side := Vec2{-forward.y, forward.x}
		for sign in headlight_signs {position := Vec2 {
				vehicle.x + forward.x * 1.05 + side.x * .34 * sign,
				vehicle.y + forward.y * 1.05 + side.y * .34 * sign,
			}
			vk_world_runtime_light_insert(
				out,
				Vk_World_Runtime_Light {
					position = {
						position.x,
						city_elevation(position.x, position.y) + .55,
						position.y,
						12,
					},
					color = {1, .82, .58, .42},
					params = {
						f32(Level_Light_Kind.Spot),
						vehicle.heading,
						f32(math.cos(f64(18 * f32(math.PI) / 180))),
						0,
					},
					room = -1,
					sequence = 10000 + vehicle_index * 2 + (sign > 0 ? 1 : 0),
				},
				focus,
			)}
	}
	if g.driving_vehicle < 0 || g.driving_vehicle >= len(g.vehicles) do return
	vehicle :=
		g.vehicles[g.driving_vehicle]; throttle, _ := vehicle_control_inputs(g); handbrake := vehicle_handbrake_input(g); state := vehicle_rear_light_state(vehicle, throttle, handbrake); if state == .Off do return
	forward := Vec2 {
		f32(math.cos(f64(vehicle.heading))),
		f32(math.sin(f64(vehicle.heading))),
	}; side := Vec2{-forward.y, forward.x}; intensity := vehicle_rear_light_intensity(vehicle, throttle, handbrake); color := state == .Brake ? [4]f32{1, .018, .008, intensity} : [4]f32{.88, .94, 1, intensity}; light_range := state == .Brake ? f32(2.2) : f32(3); half_angle := state == .Brake ? f32(16) : f32(20)
	for sign in headlight_signs {position := Vec2 {
			vehicle.x - forward.x * 1.02 + side.x * .33 * sign,
			vehicle.y - forward.y * 1.02 + side.y * .33 * sign,
		}
		vk_world_runtime_light_insert(
			out,
			Vk_World_Runtime_Light {
				position = {
					position.x,
					city_elevation(position.x, position.y) + .52,
					position.y,
					light_range,
				},
				color = color,
				params = {
					f32(Level_Light_Kind.Spot),
					vehicle.heading + f32(math.PI),
					f32(math.cos(f64(half_angle * f32(math.PI) / 180))),
					0,
				},
				room = -1,
				sequence = 20000 + g.driving_vehicle * 2 + (sign > 0 ? 1 : 0),
			},
			focus,
		)}
}

Vk_World_View_Pose :: struct {
	eye, target, up:  Vec3,
	baking, interior: bool,
}

vehicle_camera_distance :: proc(actual_speed: f32) -> f32 {return(
		5.2 +
		clamp(actual_speed / .58, 0, 1) * 1.8 \
	)}
vehicle_camera_height :: proc(actual_speed: f32) -> f32 {return(
		1.15 +
		clamp(actual_speed / .58, 0, 1) * .32 \
	)}
vehicle_camera_acceleration_distance :: proc(v: Vehicle_State) -> f32 {load := clamp(
		v.acceleration_feedback,
		-1,
		1,
	)
	return load * (load >= 0 ? f32(.34) : f32(.20))}
vehicle_camera_effective_distance :: proc(v: Vehicle_State, cleared_distance: f32) -> f32 {
	base := vehicle_camera_distance(vehicle_actual_speed(v)); distance := cleared_distance
	if distance <= 0 do distance = base
	offset := vehicle_camera_acceleration_distance(v)
	// Never spend launch pullback through a boom that was shortened by a wall.
	if offset > 0 && distance < base - .05 do offset = 0
	return max(distance + offset, f32(1.2))
}
vehicle_camera_bank :: proc(v: Vehicle_State) -> f32 {
	actual_speed := vehicle_actual_speed(v)
	// At useful road speed yaw implies opposite lateral load in reverse. Fade its
	// direction through neutral; retain the raw low-speed collision-spin cue.
	travel_direction :=
		actual_speed < .06 ? f32(1) : clamp(vehicle_longitudinal_speed(v) / .04, -1, 1)
	yaw_bank := clamp(v.yaw_rate / .045, -1, 1) * travel_direction * .018
	if actual_speed < .06 do return yaw_bank
	// Yaw communicates an ordinary corner; signed lateral travel adds a second,
	// bounded cue when the velocity vector escapes the chassis during oversteer.
	right_x := -f32(math.sin(f64(v.heading))); right_y := f32(math.cos(f64(v.heading)))
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	slip := clamp(lateral / max(actual_speed, f32(.05)), -1, 1)
	speed_weight := clamp((actual_speed - .06) / .25, 0, 1)
	force_bank := clamp(v.chassis_lateral_acceleration, -1, 1) * speed_weight * .020
	return clamp(yaw_bank + force_bank + slip * speed_weight * .012, -.05, .05)
}
vehicle_camera_impact_jolt :: proc(v: Vehicle_State, animation_time: f32) -> f32 {return(
		f32(math.sin(f64(animation_time * 72))) *
		v.impact *
		.09 \
	)}
vehicle_camera_impact_offset :: proc(v: Vehicle_State, animation_time: f32) -> Vec2 {
	forward, side := v.impact_forward, v.impact_side
	directional := math.abs(forward) + math.abs(side) >= .001
	phase := directional ? v.impact_time : animation_time
	if !directional do side = 1
	wave := f32(math.sin(f64(phase * 72))) * v.impact
	// Camera inertia initially travels opposite the resolved acceleration delta.
	return {-wave * forward * .075, -wave * side * .09}
}
vehicle_camera_rough_jolt :: proc(v: Vehicle_State) -> f32 {
	phase := v.x * 6.9 + v.y * 7.7 + .2
	return f32(math.sin(f64(phase))) * vehicle_rough_feedback_blended(v, v.surface_blend) * .018
}
vehicle_rough_body_pose :: proc(v: Vehicle_State) -> (roll, pitch: f32) {
	amount := vehicle_rough_feedback_blended(v, v.surface_blend)
	// Spatial phases make bump frequency follow ground speed and keep nearby cars
	// from bobbing in sync. Amplitudes remain subordinate to real load transfer.
	roll = f32(math.sin(f64(v.x * 7.3 + v.y * 4.9 + 1.7))) * amount * .006
	pitch = f32(math.sin(f64(v.x * 5.7 - v.y * 8.1 + .6))) * amount * .010
	return
}
vehicle_camera_field_of_view :: proc(v: Vehicle_State) -> f32 {
	speed_response := clamp(vehicle_actual_speed(v) / .58, 0, 1) * .105
	impact_response := clamp(v.impact, 0, 1) * .022
	load := clamp(
		v.acceleration_feedback,
		-1,
		1,
	); acceleration_response := load >= 0 ? load * .014 : load * .006
	return f32(math.PI / 3) + speed_response + impact_response + acceleration_response
}

vk_world_view_pose :: proc(g: ^Game) -> Vk_World_View_Pose {
	if g.screen == .Dialogue &&
	   g.story_presentation.interaction_active {distance := 3.5 * g.dialogue_interaction.zoom; return {{.35, 1.15, distance}, {.35, .78, 0}, {0, 1, 0}, false, true}}
	px, pz, angle := g.player_x, g.player_y, g.player_angle
	driving_speed: f32 = 0; driving_orbit_angle := angle
	if g.screen ==
	   .Exterior {px, pz, angle = g.city_x, g.city_y, g.city_angle; driving_orbit_angle = angle; if g.driving_vehicle >= 0 {car := g.vehicles[g.driving_vehicle]; driving_speed = vehicle_actual_speed(car); distance := vehicle_camera_effective_distance(car, g.vehicle_camera_follow_distance); driving_orbit_angle = angle + g.vehicle_camera_reverse_blend * f32(math.PI); px = car.x - f32(math.cos(f64(driving_orbit_angle))) * distance; pz = car.y - f32(math.sin(f64(driving_orbit_angle))) * distance}}
	interior :=
		g.screen == .Investigate ||
		g.screen ==
			.Dialogue; baking := g.catalog_bake_index >= 0; aerial := interior || (g.screen == .Exterior && g.driving_vehicle < 0)
	eye := Vec3 {
		px,
		vehicle_camera_height(driving_speed),
		pz,
	}; target := Vec3{px + f32(math.cos(f64(angle))), 1.15, pz + f32(math.sin(f64(angle)))}; up := Vec3{0, 1, 0}
	if g.screen == .Exterior && g.driving_vehicle >= 0 {
		car :=
			g.vehicles[g.driving_vehicle]; lookahead := 1.1 + clamp(driving_speed / .58, 0, 1) * 2.4; target = {car.x + car.velocity_x * lookahead, 0.72, car.y + car.velocity_y * lookahead}
		bank := vehicle_camera_bank(
			car,
		); right_x, right_z := -f32(math.sin(f64(driving_orbit_angle))), f32(math.cos(f64(driving_orbit_angle))); up = {right_x * bank, 1, right_z * bank}
		impact_offset := vehicle_camera_impact_offset(
			car,
			g.animation_time,
		); car_forward_x, car_forward_z := f32(math.cos(f64(car.heading))), f32(math.sin(f64(car.heading))); car_right_x, car_right_z := -car_forward_z, car_forward_x; jolt_x := car_forward_x * impact_offset.x + car_right_x * impact_offset.y; jolt_z := car_forward_z * impact_offset.x + car_right_z * impact_offset.y; jolt_magnitude := f32(math.sqrt(f64(jolt_x * jolt_x + jolt_z * jolt_z))); eye.y += jolt_magnitude * .55; eye.x += jolt_x; eye.z += jolt_z; target.x += jolt_x * .22; target.z += jolt_z * .22
		rough_jolt := vehicle_camera_rough_jolt(
			car,
		); eye.y += rough_jolt; target.y += rough_jolt * .28
		eye.y += city_elevation(eye.x, eye.z); target.y += city_elevation(target.x, target.z)
	}
	if baking {eye = {2.6, 2.2, 2.6}; target = {0, .72, 0}} else if aerial {focus_x, focus_z := px, pz; if interior && g.camera_initialized {focus_x, focus_z = g.camera_x, g.camera_y} else if g.screen == .Exterior && g.city_camera_initialized {focus_x, focus_z = g.city_camera_x, g.city_camera_y}; base_y := camera_story_y(g); if g.screen == .Exterior do base_y = city_elevation(focus_x, focus_z); eye, target, up = aerial_camera_pose(g, focus_x, focus_z, base_y)}
	if g.character_studio {eye = {0, 3.2, 10}; target = {0, 1, 0}; up = {0, 1, 0}}
	if interior &&
	   g.first_person_camera {pitch_scale := f32(math.cos(f64(g.first_person_pitch))); eye_height := g.player_elevation + 1.65; eye = {g.player_x, eye_height, g.player_y}; target = {g.player_x + f32(math.cos(f64(g.player_angle))) * pitch_scale, eye_height + f32(math.sin(f64(g.first_person_pitch))), g.player_y + f32(math.sin(f64(g.player_angle))) * pitch_scale}; up = {0, 1, 0}}
	return {eye, target, up, baking, interior}
}

vk_world_reuse_grouped_light_list :: proc(scene: ^Vk_World_Scene, draw_index: int) -> bool {
	if draw_index < 0 || draw_index >= len(scene.draws) || scene.draws[draw_index].light_group == 0 do return false
	for candidate in 0 ..< draw_index do if scene.draws[candidate].light_group == scene.draws[draw_index].light_group {scene.draw_lights[draw_index] = scene.draw_lights[candidate]; return true}
	return false
}

vk_world_build_draw_light_lists :: proc(
	scene: ^Vk_World_Scene,
	lights: []Vk_World_Runtime_Light,
	quality: Lighting_Quality,
	frame_index: int,
) {
	limit := lighting_quality_light_count(
		quality,
	); shadow_candidates := lighting_quality_shadow_candidates(quality); draw_count := min(len(scene.draws), len(scene.draw_lights)); group_keys: [256]u64; group_draws: [256]int; point_x: [4096]f32; point_z: [4096]f32; point_previous_primary: [4096]u32; point_previous_active: [4096]bool; point_draws: [4096]int; for &index in group_draws do index = -1; for &index in point_draws do index = -1
	cache_matches :=
		scene.light_cache_valid &&
		scene.light_cache_quality == quality &&
		len(scene.light_cache_inputs) == draw_count &&
		len(scene.light_cache_lights) == len(lights)
	if cache_matches {for light, i in lights do if light != scene.light_cache_lights[i] {cache_matches = false; break}}
	if cache_matches {for draw, i in scene.draws[:draw_count] {sample_x, sample_z := draw.x, draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; input := scene.light_cache_inputs[i]; if input.x != sample_x || input.z != sample_z || input.group != draw.light_group {cache_matches = false; break}}}
	if cache_matches {if draw_count > 0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped, raw_data(scene.draw_lights[:draw_count]), draw_count * size_of(Vk_World_Draw_Lights)); return}
	for draw_index in 0 ..< draw_count {
		draw := &scene.draws[draw_index]
		group_slot := int(
			draw.light_group % len(group_keys),
		); if draw.light_group != 0 && group_keys[group_slot] == draw.light_group && group_draws[group_slot] >= 0 {scene.draw_lights[draw_index] = scene.draw_lights[group_draws[group_slot]]; continue}
		sample_x, sample_z :=
			draw.x,
			draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; previous := scene.draw_lights[draw_index]; previous_active := previous.meta[0] > 0; previous_primary := previous.indices_a[0]; point_hash := u64(transmute(u32)sample_x) * 0x9e3779b1 ~ u64(transmute(u32)sample_z); point_slot := int(point_hash % len(point_draws)); if point_draws[point_slot] >= 0 && point_x[point_slot] == sample_x && point_z[point_slot] == sample_z && point_previous_active[point_slot] == previous_active && point_previous_primary[point_slot] == previous_primary {scene.draw_lights[draw_index] = scene.draw_lights[point_draws[point_slot]]; continue}; list := Vk_World_Draw_Lights{}; scores: [VK_WORLD_MAX_DRAW_LIGHTS]f32; indices: [VK_WORLD_MAX_DRAW_LIGHTS]u32; weights: [VK_WORLD_MAX_DRAW_LIGHTS]f32; count := 0; draw_room := vk_world_room_at({sample_x, sample_z})
		for light, light_index in lights {dx, dz :=
				sample_x - light.position[0], sample_z - light.position[2]
			distance_sq := dx * dx + dz * dz
			range := max(light.position[3], .01)
			if distance_sq >= range * range do continue
			room_weight := f32(1)
			if draw_room !=
			   light.room {if !world_line_clear(sample_x, sample_z, light.position[0], light.position[2]) do continue
				room_weight = .35}
			falloff := 1 - f32(math.sqrt(f64(distance_sq))) / range
			score := light.color[3] * room_weight * falloff * falloff
			if score <= .0001 do continue
			insert := min(count, limit - 1)
			for slot in 0 ..< min(
				count,
				limit,
			) {if score > scores[slot] + .00001 || (math.abs(score - scores[slot]) <= .00001 && light_index < int(indices[slot])) {insert = slot; break}}
			if insert >= limit do continue
			end := min(count, limit - 1)
			for slot := end;
			    slot > insert;
			    slot -= 1 {scores[slot] = scores[slot - 1]; indices[slot] = indices[slot - 1]
				weights[slot] = weights[slot - 1]}
			scores[insert] = score
			indices[insert] = u32(light_index)
			weights[insert] = room_weight
			if count < limit do count += 1}
		if previous.meta[0] > 0 &&
		   count >
			   1 {previous_primary := previous.indices_a[0]; for slot in 1 ..< count do if indices[slot] == previous_primary && scores[0] < scores[slot] * 1.05 {scores[0], scores[slot] = scores[slot], scores[0]; indices[0], indices[slot] = indices[slot], indices[0]; weights[0], weights[slot] = weights[slot], weights[0]; break}}
		for slot in 0 ..< count {if slot < 4 {list.indices_a[slot] = indices[slot]; list.weights_a[slot] = weights[slot]} else {list.indices_b[slot - 4] = indices[slot]; list.weights_b[slot - 4] = weights[slot]}}; list.meta[0] = u32(count); list.meta[2] = u32(min(count, shadow_candidates)); if count > 0 && shadow_candidates > 0 do list.meta[1] = indices[0] + 1; scene.draw_lights[draw_index] = list; point_x[point_slot] = sample_x; point_z[point_slot] = sample_z; point_previous_active[point_slot] = previous_active; point_previous_primary[point_slot] = previous_primary; point_draws[point_slot] = draw_index; if draw.light_group != 0 {group_keys[group_slot] = draw.light_group; group_draws[group_slot] = draw_index}
	}
	resize(
		&scene.light_cache_inputs,
		draw_count,
	); for draw, i in scene.draws[:draw_count] {sample_x, sample_z := draw.x, draw.z; if draw.use_light_anchor do sample_x, sample_z = draw.light_x, draw.light_z; scene.light_cache_inputs[i] = {sample_x, sample_z, draw.light_group}}
	resize(
		&scene.light_cache_lights,
		len(lights),
	); copy(scene.light_cache_lights[:], lights); scene.light_cache_quality = quality; scene.light_cache_valid = true
	if draw_count > 0 do mem.copy_non_overlapping(scene.draw_light_buffers[frame_index].mapped, raw_data(scene.draw_lights[:draw_count]), draw_count * size_of(Vk_World_Draw_Lights))
}

vk_world_depth_create :: proc(
	ctx: ^engine.Vk_Context,
	width, height: u32,
	out: ^Vk_Ui_Image,
	samples: vk.SampleCountFlags = {._1},
) -> bool {
	return resources.depth_create(ctx, width, height, out, samples)
}

vk_world_mesh_destroy :: proc(mesh: ^Vk_World_Mesh, ctx: ^engine.Vk_Context) {for &image in mesh.images do vk_ui_image_destroy(&image, ctx)
	delete(mesh.images)
	delete(mesh.sets)
	engine.vk_destroy_buffer(ctx, &mesh.indices)
	engine.vk_destroy_buffer(ctx, &mesh.vertices)
	mesh^ = {}}
vk_world_destroy :: proc(scene: ^Vk_World_Scene, ctx: ^engine.Vk_Context) {for &mesh in scene.meshes do vk_world_mesh_destroy(&mesh, ctx)
	delete(scene.meshes)
	delete(scene.draws)
	delete(scene.draw_lights)
	delete(scene.light_cache_inputs)
	delete(scene.light_cache_lights)
	vk_ui_image_destroy(&scene.white, ctx)
	vk_ui_image_destroy(&scene.flat_normal, ctx)
	vk_ui_image_destroy(&scene.depth, ctx)
	if scene.pipeline != vk.Pipeline(0) do vk.DestroyPipeline(ctx.device, scene.pipeline, nil)
	if scene.pipeline_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(ctx.device, scene.pipeline_layout, nil)
	if scene.descriptor_pool != vk.DescriptorPool(0) do vk.DestroyDescriptorPool(ctx.device, scene.descriptor_pool, nil)
	if scene.descriptor_layout != vk.DescriptorSetLayout(0) do vk.DestroyDescriptorSetLayout(ctx.device, scene.descriptor_layout, nil)
	vk_shadow_state_destroy(&scene.shadows, ctx)
	engine.vk_destroy_buffer(ctx, &scene.instance_buffer)
	for 	i in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {engine.vk_destroy_buffer(ctx, &scene.draw_light_buffers[i])
		engine.vk_destroy_buffer(ctx, &scene.palettes[i])
		engine.vk_destroy_buffer(ctx, &scene.cameras[i])}
	scene^ = {}}
