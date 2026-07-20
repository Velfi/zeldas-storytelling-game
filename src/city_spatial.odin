package main

import "core:math"

city_road_cell :: proc(ix, iy: int) -> bool {
	if ix < 0 || ix >= CITY_WIDTH || iy < 0 || iy >= CITY_HEIGHT do return false
	// Cross-city boulevard, north/south spine, and the three river bridges.
	if iy >= 78 && iy <= 83 || ix >= 94 && ix <= 99 do return true
	if ix >= 62 && ix <= 65 && (iy >= 30 && iy <= 35 || iy >= 78 && iy <= 83 || iy >= 126 && iy <= 131) do return true
	if ix >= 126 && ix <= 129 && (iy >= 14 && iy <= 19 || iy >= 62 && iy <= 67 || iy >= 110 && iy <= 115) do return true
	if ix < 64 {
		// Close residential north/south streets with fewer, wider east/west roads.
		return ix % 16 < 4 || iy % 32 < 4
	}
	if ix < 128 {
		// The old commercial core grew at a tighter cadence around civic blocks.
		return(
			(ix - 64) % 12 < 4 ||
			(iy + 2) % 20 < 4 ||
			ix >= 80 && ix <= 83 ||
			iy >= 30 && iy <= 35 ||
			iy >= 126 && iy <= 131 \
		)
	}
	// Freight roads create large sheds and yards; quay roads serve the waterfront.
	return(
		(ix - 128) % 32 < 4 ||
		(iy + 2) % 24 < 4 ||
		ix >= 144 && ix <= 147 ||
		iy >= 30 && iy <= 35 ||
		iy >= 110 && iy <= 115 \
	)
}

CITY_ROAD_NORTH :: u8(1)
CITY_ROAD_EAST :: u8(2)
CITY_ROAD_SOUTH :: u8(4)
CITY_ROAD_WEST :: u8(8)

city_road_connection_mask :: proc(ix, iy: int) -> u8 {
	if !city_road_cell(ix, iy) do return 0
	mask: u8
	if city_road_cell(ix, iy + 4) do mask |= CITY_ROAD_NORTH
	if city_road_cell(ix + 4, iy) do mask |= CITY_ROAD_EAST
	if city_road_cell(ix, iy - 4) do mask |= CITY_ROAD_SOUTH
	if city_road_cell(ix - 4, iy) do mask |= CITY_ROAD_WEST
	return mask
}

city_road_tile :: proc(mask: u8) -> (mesh_index: int, yaw: f32) {
	count := 0; for bit: u8 = 1; bit <= CITY_ROAD_WEST; bit <<= 1 do if mask & bit != 0 do count += 1
	if count >= 4 do return 1, 0
	if count == 3 {
		// The source T-junction connects west/east/south (missing north).
		if mask & CITY_ROAD_NORTH == 0 do return 3, 0
		if mask & CITY_ROAD_WEST == 0 do return 3, f32(math.PI / 2)
		if mask & CITY_ROAD_SOUTH == 0 do return 3, f32(math.PI)
		return 3, -f32(math.PI / 2)
	}
	if count == 2 {
		if mask == CITY_ROAD_EAST | CITY_ROAD_WEST do return 0, 0
		if mask == CITY_ROAD_NORTH | CITY_ROAD_SOUTH do return 0, f32(math.PI / 2)
		// The source bend connects west and south.
		if mask == CITY_ROAD_WEST | CITY_ROAD_SOUTH do return 2, 0
		if mask == CITY_ROAD_SOUTH | CITY_ROAD_EAST do return 2, f32(math.PI / 2)
		if mask == CITY_ROAD_EAST | CITY_ROAD_NORTH do return 2, f32(math.PI)
		return 2, -f32(math.PI / 2)
	}
	// The source end continues west from its barrier.
	if mask & CITY_ROAD_WEST != 0 do return 4, 0
	if mask & CITY_ROAD_SOUTH != 0 do return 4, f32(math.PI / 2)
	if mask & CITY_ROAD_EAST != 0 do return 4, f32(math.PI)
	return 4, -f32(math.PI / 2)
}

city_open_space_cell :: proc(ix, iy: int) -> bool {
	// Market square, civic green, depot forecourt, tank yards, and marina basin.
	return(
		(ix >= 72 && ix <= 87 && iy >= 40 && iy <= 55) ||
		(ix >= 104 && ix <= 119 && iy >= 70 && iy <= 93) ||
		(ix >= 24 && ix <= 43 && iy >= 88 && iy <= 107) ||
		(ix >= 136 && ix <= 155 && iy >= 88 && iy <= 103) ||
		(ix >= 152 && ix <= 179 && iy >= 120 && iy <= 143) \
	)
}

city_developed_lot_cell :: proc(ix, iy: int) -> bool {
	if ix < 0 || ix >= CITY_WIDTH || iy < 0 || iy >= CITY_HEIGHT do return true
	if iy > 148 + (ix % 7) do return true
	if ix >= 62 && ix <= 65 && !(iy >= 30 && iy <= 35) && !(iy >= 78 && iy <= 83) && !(iy >= 126 && iy <= 131) do return true
	if ix >= 126 && ix <= 129 && !(iy >= 14 && iy <= 19) && !(iy >= 62 && iy <= 67) && !(iy >= 110 && iy <= 115) do return true
	return !city_road_cell(ix, iy) && !city_open_space_cell(ix, iy)
}

city_building_site :: proc(bx, by: int) -> (x, y: f32, place: bool) {
	district := city_district(f32(bx * CITY_BLOCK + 8))
	switch district {
	case 0:
		x = f32(bx * CITY_BLOCK + 9 + (by % 2) * 2); y = f32(by * CITY_BLOCK + 10)
		place = (bx + by * 3) % 7 != 0
	case 1:
		x = f32(bx * CITY_BLOCK + 10); y = f32(by * CITY_BLOCK + 9 + (bx % 2) * 2); place = true
	case 2:
		x = f32(bx * CITY_BLOCK + 11); y = f32(by * CITY_BLOCK + 11); place = (bx + by) % 2 == 0
	}
	if city_open_space_cell(int(x), int(y)) || city_road_cell(int(x), int(y)) do place = false
	return
}

// Permanent landmarks still belong to the static city, so their street-side
// interaction points need a recognizable piece of the skyline behind them.
// The station occupies the complete block east of its authored marker;
// render that block as a low civic building instead of a random Westhaven home.
city_police_station_building :: proc(bx, by: int) -> bool {return bx == 3 && by == 3}

city_building_style :: proc(
	bx, by: int,
	layout_x: f32,
) -> (
	mesh_index: int,
	height, yaw: f32,
	tint: [4]u8,
) {
	district := city_district(layout_x)
	mesh_index =
		district == 0 ? (bx + by) % 2 : district == 1 ? 2 + (bx + by) % 3 : 5 + (bx + by) % 2
	height =
		district == 0 ? f32(2.7 + f32((bx + by) % 3) * .35) : district == 1 ? f32(4.2 + f32((bx * 7 + by * 3) % 6) * .75) : f32(3.0 + f32((bx * 5 + by) % 3) * .55)
	yaw =
		district == 0 && by % 2 == 1 ? f32(math.PI) : district == 2 && bx % 2 == 1 ? f32(math.PI / 2) : f32(0)
	tint = {255, 255, 255, 255}
	if city_police_station_building(bx, by) {
		mesh_index = 2 // broad commercial facade, distinct from nearby houses
		height = 4.1
		yaw = -f32(math.PI / 2) // entrance addresses the north/south street marker
		tint = {184, 205, 214, 255}
	}
	return
}

city_building_wall :: proc(layout_x, layout_y: f32) -> bool {
	if layout_x < 0 || layout_y < 0 do return false
	bx, by := int(layout_x) / CITY_BLOCK, int(layout_y) / CITY_BLOCK
	if bx < 0 || bx >= CITY_WIDTH / CITY_BLOCK || by < 0 || by >= CITY_HEIGHT / CITY_BLOCK do return false
	building_x, building_y, place := city_building_site(bx, by); if !place do return false
	mesh_index, height, yaw, _ := city_building_style(bx, by, building_x)
	// Match the rectangle to the mesh transform used by vk_world_build_city.
	// The previous district-wide square extended well beyond narrow facades,
	// leaving solid patches of apparently empty lawn and road setback.
	if mesh_index >= 0 && mesh_index < len(city_meshes) {
		mesh := &city_meshes[mesh_index]
		span_y := mesh.max.y - mesh.min.y
		if mesh.ready && span_y > .0001 {
			scale := height / span_y
			dx, dy := layout_x - building_x, layout_y - building_y
			c, s := f32(math.cos(f64(yaw))), f32(math.sin(f64(yaw)))
			local_x := c * dx + s * dy; local_y := -s * dx + c * dy
			half_x := (mesh.max.x - mesh.min.x) * scale * .5
			half_y := (mesh.max.z - mesh.min.z) * scale * .5
			return math.abs(local_x) <= half_x && math.abs(local_y) <= half_y
		}
	}
	// Asset loading failures should remain safe without restoring the oversized
	// district collider.
	return math.abs(layout_x - building_x) <= 3 && math.abs(layout_y - building_y) <= 3
}

city_driving_surface :: proc(x, y: f32) -> City_Driving_Surface {
	ix, iy := int(city_layout(x)), int(city_layout(y))
	return city_road_cell(ix, iy) ? .Road : .Open_Ground
}

vehicle_camera_clear_distance :: proc(x, y, direction_x, direction_y, desired: f32) -> f32 {
	if desired <= 1.2 do return max(desired, .2)
	distance := f32(.45)
	for distance <= desired {
		if city_wall(x + direction_x * distance, y + direction_y * distance) do return max(distance - .24, f32(1.2))
		distance += .14
	}
	return desired
}

vehicle_camera_distance_step :: proc(current, target: f32) -> f32 {
	if current <= 0 do return target
	response := target < current ? f32(.30) : f32(.075)
	return current + (target - current) * response
}

vehicle_camera_momentum_heading :: proc(v: Vehicle_State) -> f32 {
	if vehicle_actual_speed(v) < .08 do return v.heading
	travel_heading := f32(math.atan2(f64(v.velocity_y), f64(v.velocity_x)))
	delta := travel_heading - v.heading
	for delta > math.PI do delta -= f32(math.PI * 2)
	for delta < -math.PI do delta += f32(math.PI * 2)
	// A car's body axis is directionless for this purpose: choose the travel-axis
	// orientation nearest its nose. This keeps reverse and near-broadside motion
	// continuous instead of letting the camera snap by half a turn.
	if delta > math.PI / 2 do delta -= f32(math.PI)
	if delta < -math.PI / 2 do delta += f32(math.PI)
	weight := clamp((vehicle_lateral_slip_ratio(v) - .12) / .58, 0, 1) * .32
	return v.heading + delta * weight
}

city_wall :: proc(x, y: f32) -> bool {
	if x < 0 || x >= CITY_WORLD_WIDTH || y < 0 || y >= CITY_WORLD_HEIGHT do return true
	layout_x, layout_y := city_layout(x), city_layout(y); ix := int(layout_x); iy := int(layout_y)
	if ix < 0 || ix >= CITY_WIDTH || iy < 0 || iy >= CITY_HEIGHT do return true
	// The rendered waterfront defines the outer borough silhouette. Interior
	// channels are not rendered, so they cannot contribute collision here.
	if iy > 148 + (ix % 7) do return true
	// Two broad cross-city arterials and the regular street grid remain open.
	if city_road_cell(ix, iy) do return false
	// Squares, greens, station forecourts, yards, and the marina break the rhythm.
	if city_open_space_cell(ix, iy) do return false
	// Non-road portions of a lot are lawn or yard. Only the actual building
	// footprint is solid, allowing both pedestrians and vehicles to go off-road.
	return city_building_wall(layout_x, layout_y)
}

city_player_blocked :: proc(g: ^Game, x, y: f32) -> bool {
	offsets := [5]Vec2 {
		{0, 0},
		{CITY_PLAYER_RADIUS, 0},
		{-CITY_PLAYER_RADIUS, 0},
		{0, CITY_PLAYER_RADIUS},
		{0, -CITY_PLAYER_RADIUS},
	}
	for offset in offsets {sx, sy := x + offset.x, y + offset.y
		if city_wall(sx, sy) || city_car_at(g, sx, sy) || city_furniture_index_at(g, sx, sy) >= 0 do return true}
	current := city_surface_elevation(g.city_x, g.city_y)
	for offset in offsets {if city_surface_elevation(x + offset.x, y + offset.y) - current > CITY_PLAYER_MAX_STEP_HEIGHT do return true}
	return false
}

city_line_clear :: proc(x0, y0, x1, y1: f32) -> bool {dx := x1 - x0; dy := y1 - y0; distance :=
		math.sqrt(dx * dx + dy * dy)
	if distance <= 0.05 do return true
	steps := int(math.ceil(distance / 0.1))
	for 	step in 1 ..< steps {
		t := f32(step) / f32(steps)
		if city_wall(x0 + dx * t, y0 + dy * t) do return false
	}
	return true}

city_update_camera :: proc(g: ^Game) {
	if !g.city_camera_initialized {g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.city_camera_initialized = true}
	if !g.camera_orbit_initialized {g.camera_orbit = math.PI / 4; g.camera_zoom = 1; g.camera_orbit_initialized = true}
	g.camera_orbit += g.pad_right_x * .035
	if g.camera_orbit > math.PI do g.camera_orbit -= 2 * math.PI
	if g.camera_orbit < -math.PI do g.camera_orbit += 2 * math.PI
	g.camera_zoom = clamp(
		g.camera_zoom + g.pad_right_y * .025 - g.input.mouse_wheel * .1,
		.55,
		1.65,
	)
	desired_x :=
		g.city_x + g.city_velocity_x * 2.8; desired_y := g.city_y + g.city_velocity_y * 2.8
	g.city_camera_x +=
		(desired_x - g.city_camera_x) *
		.105; g.city_camera_y += (desired_y - g.city_camera_y) * .105
}

update_city :: proc(g: ^Game) {
	if !g.vehicles_initialized {g.driving_vehicle = -1; g.near_vehicle = -1; initialize_city_vehicles(g)}
	if !g.city_furniture_initialized do initialize_city_furniture(g)
	update_city_furniture(g)
	vehicle_age_skid_marks(g)
	passive_collision_impact: f32
	passive_collision := false
	if g.driving_vehicle >= 0 {
		// Age the player's prior impact before passive bodies can deliver a new one.
		// Decaying afterward makes the same collision weaker solely because another
		// vehicle happened to initiate contact resolution first.
		active := &g.vehicles[g.driving_vehicle]; vehicle_decay_impact(active); impact_before_passives := active.impact; passive_before_x, passive_before_y := active.velocity_x, active.velocity_y
		g.vehicle_impact_sound_cooldown = max(0, g.vehicle_impact_sound_cooldown - FIXED_TIMESTEP)
		vehicle_update_passive_vehicles(g)
		passive_collision =
			math.abs(active.velocity_x - passive_before_x) +
				math.abs(active.velocity_y - passive_before_y) >
			.00001
		if vehicle_impact_is_new_event(impact_before_passives, active.impact) do passive_collision_impact = active.impact
	} else {
		vehicle_update_passive_vehicles(g)
	}
	if g.driving_vehicle >= 0 {
		v := &g.vehicles[g.driving_vehicle]
		position_before_x, position_before_y := v.x, v.y
		velocity_before_x, velocity_before_y := v.velocity_x, v.velocity_y
		base_tune := vehicle_tune(
			g.driving_vehicle,
		); surface_roughness, surface_bias := vehicle_surface_contact(v^); v.surface_blend = vehicle_surface_blend_step_to(v.surface_blend, surface_roughness); v.surface_lateral_bias = vehicle_surface_bias_step(v.surface_lateral_bias, surface_bias); tune := vehicle_tune_for_surface_blend(base_tune, v.surface_blend)
		throttle, steer_input := vehicle_control_inputs(g)
		handbrake := vehicle_handbrake_input(g)
		v.handbrake_slip = vehicle_handbrake_slip_step_tuned(
			v.handbrake_slip,
			handbrake,
			base_tune,
		)
		reverse_camera_target := vehicle_reverse_camera_target(
			v^,
			throttle,
			g.vehicle_camera_reverse_blend,
		); g.vehicle_camera_reverse_blend += (reverse_camera_target - g.vehicle_camera_reverse_blend) * .075
		vehicle_apply_throttle_assisted(v, tune, base_tune, throttle, 1 - v.handbrake_slip)
		// Surface limits are sustainable speeds, not teleporting clamps. Preserve
		// momentum across a road edge and let rough-ground drag bleed excess speed.
		v.speed = clamp(v.speed, -base_tune.max_reverse, base_tune.max_forward)
		normalized_speed := vehicle_normalized_steering_speed(
			v^,
			tune,
		); assisted_input := vehicle_assisted_steering_input(v^, steer_input, v.handbrake_slip, base_tune); steer_limit := vehicle_steering_limit(tune, normalized_speed, v.handbrake_slip, vehicle_is_countersteering(v^, assisted_input)); target_steer := clamp(assisted_input, -1, 1) * steer_limit; steering_response := vehicle_steering_response(tune, normalized_speed, steer_input, v.steering); v.steering += (target_steer - v.steering) * steering_response
		v.speed *= vehicle_drag_factor_blended(
			base_tune,
			v.surface_blend,
			v.handbrake_slip,
			throttle,
			vehicle_lateral_slip_ratio(v^),
			math.abs(v.speed) / max(base_tune.max_forward, f32(.01)),
		); if math.abs(v.speed) < 0.001 do v.speed = 0
		detected_assist, detected_assist_strength := vehicle_driver_assist_blended(
			v^,
			base_tune,
			throttle,
			v.handbrake_slip,
		); previous_assist := v.driver_assist; v.driver_assist, v.driver_assist_strength = vehicle_driver_assist_state_step(v.driver_assist, v.driver_assist_strength, detected_assist, detected_assist_strength, v.handbrake_slip); if v.driver_assist == .None do v.driver_assist_time = 0
		else if v.driver_assist != previous_assist do v.driver_assist_time = 0
		else do v.driver_assist_time += FIXED_TIMESTEP
		requested_drive_authority := vehicle_requested_drive_authority(
			v^,
			throttle,
		); brake_authority := (1 - requested_drive_authority) * math.abs(throttle); vehicle_apply_abs_release(v, brake_authority); vehicle_apply_traction_control(v, base_tune, requested_drive_authority * math.abs(throttle) * (1 - v.handbrake_slip))
		// Steering observes the wheel state after driver assists have released lock
		// or trimmed spin, so recovered tire authority is available this same tick.
		vehicle_apply_yaw_blended(v, v.handbrake_slip, tune, throttle)

		// Resolve tire forces in the car's local forward/right basis so power and
		// side grip have distinct, tunable responses.
		vehicle_apply_tire_grip_blended(v, v.handbrake_slip, tune)
		if vehicle_should_settle_velocity(v^) {v.velocity_x *= .82; v.velocity_y *= .82}
		collision_impact, collision_travel: f32; collided := vehicle_swept_move(g, v, g.driving_vehicle, true, &collision_impact, &collision_travel)
		v.traction_state = vehicle_traction_state_step(v.traction_state, v^)
		// Synthesize after forces and contact so tire timbre, engine load, and the
		// HUD all observe the same resolved simulation tick.
		update_vehicle_drive_audio(g, v^, base_tune, throttle)
		vehicle_update_acceleration_feedback_from_velocity(
			v,
			velocity_before_x,
			velocity_before_y,
			collided || passive_collision,
		)
		vehicle_update_body_roll_blended(v, v.handbrake_slip, base_tune)
		vehicle_update_body_pitch(v, base_tune)
		audible_impact := max(
			collision_impact,
			passive_collision_impact,
		); if vehicle_impact_audio_ready(audible_impact, g.vehicle_impact_sound_cooldown) {play_vehicle_impact_sound(g, audible_impact); g.vehicle_impact_sound_cooldown = .14}
		vehicle_update_skid_marks_blended(
			g,
			v^,
			v.handbrake_slip,
			v.surface_blend,
			{v.x - position_before_x, v.y - position_before_y},
			true,
			collision_travel,
		)
		g.city_x = v.x; g.city_y = v.y
		camera_heading := vehicle_camera_momentum_heading(
			v^,
		); angle_delta := camera_heading - g.city_angle; for angle_delta > math.PI do angle_delta -= f32(math.PI * 2); for angle_delta < -math.PI do angle_delta += f32(math.PI * 2); g.city_angle += angle_delta * 0.09
		nominal_camera_distance := vehicle_camera_distance(
			vehicle_actual_speed(v^),
		); camera_orbit := g.city_angle + g.vehicle_camera_reverse_blend * f32(math.PI); clear_camera_distance := vehicle_camera_clear_distance(v.x, v.y, -f32(math.cos(f64(camera_orbit))), -f32(math.sin(f64(camera_orbit))), nominal_camera_distance); g.vehicle_camera_follow_distance = vehicle_camera_distance_step(g.vehicle_camera_follow_distance, clear_camera_distance)
		g.near_vehicle = -1; g.near_landmark = -1
		context_resolve_city(g)
		if g.input.vehicle_action do _ = context_activate_city(g, g.context_ui.current)
		return
	}
	if !g.camera_orbit_initialized {g.camera_orbit = math.PI / 4; g.camera_zoom = 1; g.camera_orbit_initialized = true}
	turn: f32 = 0; if g.keys[.LEFT] do turn -= 1; if g.keys[.RIGHT] do turn += 1; g.city_angle += turn * 0.045
	stick := house_radial_input(
		{g.pad_left_x, -g.pad_left_y},
	); forward, strafe := stick.y, stick.x; if g.keys[.W] || g.keys[.UP] do forward += 1; if g.keys[.S] || g.keys[.DOWN] do forward -= 1; if g.keys[.A] do strafe -= 1; if g.keys[.D] do strafe += 1
	desired_x, desired_y := f32(0), f32(0); moving := math.abs(forward) + math.abs(strafe) > .05
	if moving {length := f32(math.sqrt(f64(forward * forward + strafe * strafe))); magnitude := min(length, f32(1)); forward /= length; strafe /= length; view_x := -f32(math.cos(f64(g.camera_orbit))); view_y := -f32(math.sin(f64(g.camera_orbit))); desired_x = (forward * view_x - strafe * view_y) * .065 * magnitude; desired_y = (forward * view_y + strafe * view_x) * .065 * magnitude; g.city_angle = turn_toward(g.city_angle, f32(math.atan2(f64(desired_y), f64(desired_x))), .14)}
	velocity := house_approach_velocity(
		{g.city_velocity_x, g.city_velocity_y},
		{desired_x, desired_y},
		moving,
	); g.city_velocity_x, g.city_velocity_y = velocity.x, velocity.y
	dx, dy :=
		g.city_velocity_x,
		g.city_velocity_y; if !city_player_blocked(g, g.city_x + dx, g.city_y) {g.city_x += dx} else {g.city_velocity_x = 0}; if !city_player_blocked(g, g.city_x, g.city_y + dy) {g.city_y += dy} else {g.city_velocity_y = 0}; speed := f32(math.sqrt(f64(g.city_velocity_x * g.city_velocity_x + g.city_velocity_y * g.city_velocity_y))); g.player_walk_speed = speed; g.player_is_walking = speed > .006
	if g.player_is_walking do tutorial_complete(g, .Move)
	if math.abs(turn) + math.abs(g.pad_right_x) > .1 do tutorial_complete(g, .Look)
	city_update_camera(g)
	g.near_vehicle = -1; car_best: f32 = 1.9; for car, i in g.vehicles {cx := car.x - g.city_x; cy := car.y - g.city_y; d := math.sqrt(cx * cx + cy * cy); if d < car_best {car_best = d; g.near_vehicle = i}}
	g.near_landmark = -1; best: f32 = 2.2
	for i in 0 ..< city_landmark_count(
		g,
	) {landmark, _ := city_landmark_at(g, i); ex := landmark.x - g.city_x; ey := landmark.y - g.city_y; d := math.sqrt(ex * ex + ey * ey); if d < best && math.cos(g.city_angle) * ex + math.sin(g.city_angle) * ey > 0 && city_line_clear(g.city_x, g.city_y, landmark.x, landmark.y) {best = d; g.near_landmark = i}}
	context_resolve_city(g)
	if g.input.vehicle_action || g.input.activate && g.context_ui.current.kind == .Landmark do _ = context_activate_city(g, g.context_ui.current)
}
