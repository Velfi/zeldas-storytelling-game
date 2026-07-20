package main

import "core:fmt"
import "core:math"
import "core:strings"

city_landmark_count :: proc(g: ^Game) -> int {payload := mystery_game_payload(g); return(
		len(CITY_FIXED_LANDMARKS) +
		(payload == nil ? 0 : min(len(payload.city_labels), len(CITY_CASE_LOCATION_SITES))) \
	)}
city_fixed_landmark_id_exists :: proc(id: string) -> bool {for landmark in CITY_FIXED_LANDMARKS do if landmark.id == id do return true
	return false}
city_fixed_landmark_name_exists :: proc(name: string) -> bool {candidate := strings.to_upper(name)
	for landmark in CITY_FIXED_LANDMARKS do if landmark.name == candidate do return true
	return false}
city_case_site_id_exists :: proc(id: string) -> bool {for site in CITY_CASE_LOCATION_SITES do if site.id == id do return true
	return false}
city_case_site :: proc(id: string) -> (City_Location_Site, bool) {for site in CITY_CASE_LOCATION_SITES do if site.id == id do return site, true
	return {}, false}
city_landmark_at :: proc(g: ^Game, index: int) -> (City_Landmark, bool) {
	if index >= 0 && index < len(CITY_FIXED_LANDMARKS) do return CITY_FIXED_LANDMARKS[index], true
	payload := mystery_game_payload(
		g,
	); case_index := index - len(CITY_FIXED_LANDMARKS); if payload == nil || case_index < 0 || case_index >= len(payload.city_labels) || case_index >= len(CITY_CASE_LOCATION_SITES) do return {}, false
	location :=
		payload.city_labels[case_index]; site, found := city_case_site(location.city_site); if !found do return {}, false; return {x = site.x, y = site.y, arrival_x = site.arrival_x, arrival_y = site.arrival_y, arrival_facing = site.arrival_facing, id = location.id, name = strings.to_upper(location.display_name), case_authored = true}, true
}
city_landmark_index :: proc(g: ^Game, id: string) -> int {for 	i in 0 ..< city_landmark_count(g) {landmark, ok := city_landmark_at(g, i); if ok && landmark.id == id do return i}
	return -1}
city_place_at_landmark :: proc(g: ^Game, id: string) -> bool {
	index := city_landmark_index(g, id); if index < 0 do return false
	landmark, _ := city_landmark_at(
		g,
		index,
	); g.city_x = landmark.arrival_x; g.city_y = landmark.arrival_y; g.city_angle = landmark.arrival_facing * f32(math.PI) / 180
	g.city_camera_x = g.city_x; g.city_camera_y = g.city_y; g.city_camera_initialized = true
	// Arrival facings are authored toward the destination. Put the aerial boom
	// behind that facing so the first exterior frame reveals the surrounding
	// street wall instead of looking diagonally through the widest road opening.
	g.camera_orbit =
		g.city_angle +
		f32(
			math.PI,
		); g.camera_zoom = id == "police_station" ? f32(1.15) : f32(.82); g.camera_orbit_initialized = true
	return true
}
case_city_location :: proc(g: ^Game, id: string) -> (^Mystery_City_Label, bool) {payload :=
		mystery_game_payload(g)
	if payload != nil {for &location in payload.city_labels do if location.id == id do return &location, true}
	return nil, false}

CITY_CARS := [?]City_Car {
		{17.4, 42.0, "sedan"},
		{19.8, 52.0, "hatchback-sports"},
		{33.2, 66.0, "suv"},
		{48.0, 81.2, "taxi"},
		{78.0, 33.2, "delivery"},
		{81.3, 50.0, "sedan-sports"},
		{96.8, 67.0, "police"},
		{113.3, 82.0, "van"},
		{132.0, 17.2, "suv-luxury"},
		{145.5, 33.4, "ambulance"},
		{161.3, 48.0, "firetruck"},
		{177.8, 65.4, "garbage-truck"},
		{34.0, 97.4, "taxi"},
		{66.7, 113.2, "truck"},
		{98.2, 129.3, "truck-flat"},
		{129.8, 114.0, "delivery-flat"},
		{145.5, 129.4, "tractor"},
		{177.2, 145.3, "race"},
		{18.2, 23.5, "police"},
		// A small station motor pool, parked along the curb without blocking the
		// station arrival point at (49.5, 58.5).
		{49.0, 53.5, "police"},
		{51.0, 63.0, "police"},
		{49.0, 68.0, "police"},
	}
city_car_meshes: [len(CITY_CARS)]Glb_Mesh

initialize_city_vehicles :: proc(g: ^Game) {
	if g.vehicles == nil do g.vehicles = make([dynamic]Vehicle_State, len(CITY_CARS), len(CITY_CARS))
	for car, i in CITY_CARS {
		heading: f32 = 0
		if int(car.x) % CITY_BLOCK < 4 do heading = f32(math.PI / 2)
		g.vehicles[i] = {
			x       = city_world(car.x),
			y       = city_world(car.y),
			heading = heading,
		}
	}
	g.vehicles_initialized = true
}

city_furniture_template :: proc(kind: City_Furniture_Kind) -> City_Furniture_Template {return(
		CITY_FURNITURE_TEMPLATES[int(kind)] \
	)}

initialize_city_furniture :: proc(g: ^Game) {
	if g.city_furniture == nil do g.city_furniture = make([dynamic]City_Furniture_State, 0, 96)
	clear(&g.city_furniture)
	// Populate curb edges deterministically. Each candidate remains on traversable
	// ground, beside a solid block, and clear of parked cars and landmark arrivals.
	for iy in 2 ..< CITY_HEIGHT - 2 {for ix in 2 ..< CITY_WIDTH - 2 {
			if len(g.city_furniture) >= 72 || !city_road_cell(ix, iy) do continue
			hash := ix * 73856093 ~ iy * 19349663
			if hash % 43 != 0 do continue
			edge_x, edge_y: f32
			if city_developed_lot_cell(ix - 1, iy) do edge_x = -.30
			else if city_developed_lot_cell(ix + 1, iy) do edge_x = .30
			else if city_developed_lot_cell(ix, iy - 1) do edge_y = -.30
			else if city_developed_lot_cell(ix, iy + 1) do edge_y = .30
			else do continue
			x, y := city_world(f32(ix) + .5 + edge_x), city_world(f32(iy) + .5 + edge_y)
			if city_wall(x, y) do continue
			blocked := false
			for car in CITY_CARS {dx, dy := x - city_world(car.x), y - city_world(car.y)
				if dx * dx + dy * dy < 3.2 * 3.2 do blocked = true}
			for landmark in CITY_FIXED_LANDMARKS {dx, dy :=
					x - landmark.arrival_x, y - landmark.arrival_y
				if dx * dx + dy * dy < 3.5 * 3.5 do blocked = true}
			for prop in g.city_furniture {dx, dy := x - prop.x, y - prop.y; if dx * dx + dy * dy < 2.2 * 2.2 do blocked = true}
			if blocked do continue
			kind := City_Furniture_Kind(
				hash % len(CITY_FURNITURE_TEMPLATES),
			); heading := edge_x != 0 ? f32(math.PI / 2) : f32(0)
			append(
				&g.city_furniture,
				City_Furniture_State{x = x, y = y, heading = heading, kind = kind},
			)
		}}
	g.city_furniture_initialized = true
}

city_furniture_index_at :: proc(g: ^Game, x, y: f32, ignore: int = -1) -> int {
	for prop, i in g.city_furniture {if i == ignore do continue; radius := city_furniture_template(prop.kind).radius; dx, dy := x - prop.x, y - prop.y; if dx * dx + dy * dy < radius * radius do return i}
	return -1
}

vehicle_collision_furniture_index :: proc(g: ^Game, x, y, heading: f32) -> int {
	forward_x, forward_y :=
		f32(math.cos(f64(heading))),
		f32(math.sin(f64(heading))); right_x, right_y := -forward_y, forward_x
	longitudinal_samples := [3]f32{-1.05, 0, 1.05}; lateral_samples := [3]f32{-.48, 0, .48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {hit :=
				city_furniture_index_at(
					g,
					x + forward_x * longitudinal + right_x * lateral,
					y + forward_y * longitudinal + right_y * lateral,
				)
			if hit >= 0 do return hit}}
	return -1
}

city_car_index_at :: proc(g: ^Game, x, y: f32, ignore: int = -1) -> int {for 	car, i in g.vehicles {if i == ignore do continue; dx := x - car.x; dy := y - car.y; if dx * dx + dy * dy < 0.9 * 0.9 do return i}
	return -1}
city_car_at :: proc(g: ^Game, x, y: f32, ignore: int = -1) -> bool {return(
		city_car_index_at(g, x, y, ignore) >=
		0 \
	)}

vehicle_collision_car_index :: proc(g: ^Game, x, y, heading: f32, index: int) -> int {
	forward_x, forward_y :=
		math.cos(heading), math.sin(heading); right_x, right_y := -forward_y, forward_x
	longitudinal_samples := [3]f32{-1.05, 0, 1.05}; lateral_samples := [2]f32{-0.48, 0.48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {sx :=
				x + forward_x * longitudinal + right_x * lateral
			sy := y + forward_y * longitudinal + right_y * lateral
			hit := city_car_index_at(g, sx, sy, index)
			if hit >= 0 do return hit}}
	return -1
}

vehicle_position_clear :: proc(g: ^Game, x, y, heading: f32, index: int) -> bool {
	if vehicle_collision_furniture_index(g, x, y, heading) >= 0 do return false
	forward_x, forward_y :=
		math.cos(heading), math.sin(heading); right_x, right_y := -forward_y, forward_x
	longitudinal_samples := [3]f32{-1.05, 0, 1.05}; lateral_samples := [2]f32{-0.48, 0.48}
	for longitudinal in longitudinal_samples {for lateral in lateral_samples {sx :=
				x + forward_x * longitudinal + right_x * lateral
			sy := y + forward_y * longitudinal + right_y * lateral
			if city_wall(sx, sy) || city_car_at(g, sx, sy, index) || city_furniture_index_at(g, sx, sy) >= 0 do return false}}
	return true
}

vehicle_sync_driveline_to_velocity :: proc(v: ^Vehicle_State) {
	v.speed = vehicle_longitudinal_speed(v^)
	if math.abs(v.speed) < .001 do v.speed = 0
}

vehicle_feedback_response :: proc(current, target, attack, release: f32) -> f32 {
	if current * target < 0 || math.abs(target) > math.abs(current) do return attack
	return release
}

vehicle_update_acceleration_feedback_targets :: proc(
	v: ^Vehicle_State,
	target, chassis_target, lateral_target: f32,
) {
	response := vehicle_feedback_response(v.acceleration_feedback, target, .24, .14)
	v.acceleration_feedback += (target - v.acceleration_feedback) * response
	if math.abs(v.acceleration_feedback) < .001 && target == 0 do v.acceleration_feedback = 0
	chassis_response := vehicle_feedback_response(v.chassis_acceleration, chassis_target, .24, .14)
	v.chassis_acceleration += (chassis_target - v.chassis_acceleration) * chassis_response
	if math.abs(v.chassis_acceleration) < .001 && chassis_target == 0 do v.chassis_acceleration = 0
	lateral_response := vehicle_feedback_response(
		v.chassis_lateral_acceleration,
		lateral_target,
		.28,
		.18,
	)
	v.chassis_lateral_acceleration +=
		(lateral_target - v.chassis_lateral_acceleration) * lateral_response
	if math.abs(v.chassis_lateral_acceleration) < .001 && lateral_target == 0 do v.chassis_lateral_acceleration = 0
}

vehicle_update_acceleration_feedback_from_velocity :: proc(
	v: ^Vehicle_State,
	before_x, before_y: f32,
	collided: bool,
) {
	target, chassis_target, lateral_target: f32
	forward_x, forward_y :=
		f32(math.cos(f64(v.heading))),
		f32(math.sin(f64(v.heading))); right_x, right_y := -forward_y, forward_x
	delta_x, delta_y := v.velocity_x - before_x, v.velocity_y - before_y
	if collided {
		// Swept contact already recorded the strongest lateral impulse directly.
		lateral_target = v.chassis_lateral_acceleration
	} else {
		lateral_target = clamp((delta_x * right_x + delta_y * right_y) / .018, -1, 1)
		before_speed := f32(
			math.sqrt(f64(before_x * before_x + before_y * before_y)),
		); after_speed := vehicle_actual_speed(v^)
		target = clamp((after_speed - before_speed) / .024, -1, 1)
		chassis_target = clamp((delta_x * forward_x + delta_y * forward_y) / .024, -1, 1)
	}
	vehicle_update_acceleration_feedback_targets(v, target, chassis_target, lateral_target)
}

vehicle_update_acceleration_feedback :: proc(
	v: ^Vehicle_State,
	longitudinal_before: f32,
	collided: bool,
) {
	forward_x, forward_y := f32(math.cos(f64(v.heading))), f32(math.sin(f64(v.heading)))
	vehicle_update_acceleration_feedback_from_velocity(
		v,
		forward_x * longitudinal_before,
		forward_y * longitudinal_before,
		collided,
	)
}

vehicle_collision_transfer_factor :: proc(source_tune, target_tune: Vehicle_Tune) -> f32 {
	// Momentum transfer follows archetype inertia independently of restitution:
	// a truck should shove a sports car harder even if both contacts slide alike.
	return clamp(.20 * source_tune.mass / max(target_tune.mass, f32(.1)), .12, .32)
}

vehicle_collision_rebound :: proc(source_tune, target_tune: Vehicle_Tune) -> f32 {
	// A light car should recoil more from a heavy target, while a truck striking
	// a light body should carry through. Walls continue using the authored base.
	mass_response := clamp(target_tune.mass / max(source_tune.mass, f32(.1)), .65, 1.45)
	return clamp(source_tune.collision_rebound * mass_response, .04, .24)
}

vehicle_resolve_car_contact_velocity :: proc(
	relative_x, relative_y, normal_x, normal_y, tangent_retention, rebound: f32,
) -> Vec2 {
	length := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y)))
	if length <= .0001 do return {-relative_x * rebound, -relative_y * rebound}
	nx, ny := normal_x / length, normal_y / length
	normal_speed := relative_x * nx + relative_y * ny
	// Only reverse motion closing into the contact. A separating velocity can be
	// observed when another body has already transferred momentum this tick.
	if normal_speed >= 0 do return {relative_x, relative_y}
	tangent_x, tangent_y := relative_x - nx * normal_speed, relative_y - ny * normal_speed
	return {
		tangent_x * tangent_retention - nx * normal_speed * rebound,
		tangent_y * tangent_retention - ny * normal_speed * rebound,
	}
}

vehicle_car_contact_transfer :: proc(
	relative_x, relative_y, normal_x, normal_y, transfer: f32,
) -> Vec2 {
	length := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y)))
	if length <= .0001 do return {}
	nx, ny := normal_x / length, normal_y / length
	normal_speed := relative_x * nx + relative_y * ny
	if normal_speed >= 0 do return {}
	tangent_x, tangent_y := relative_x - nx * normal_speed, relative_y - ny * normal_speed
	amount := clamp(transfer, 0, 1)
	// Closing speed delivers the shove; only restrained tire/body friction carries
	// scrape-direction motion into the struck vehicle.
	return {
		-nx * (-normal_speed) * amount + tangent_x * amount * .18,
		-ny * (-normal_speed) * amount + tangent_y * amount * .18,
	}
}

vehicle_car_contact_tangent_step :: proc(step_x, step_y, normal_x, normal_y: f32) -> Vec2 {
	length := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y)))
	if length <= .0001 do return {}
	nx, ny := normal_x / length, normal_y / length
	normal_step := step_x * nx + step_y * ny
	return {step_x - nx * normal_step, step_y - ny * normal_step}
}

vehicle_wall_tangent_retention :: proc() -> f32 {
	// Static walls should redirect a glancing car, not repeatedly scrub away its
	// parallel speed. A high retention lets the body slide clear while the small
	// normal rebound still creates separation before the next fixed tick.
	return .94
}

vehicle_collision_yaw_impulse :: proc(
	source, target: Vehicle_State,
	incoming_x, incoming_y, transfer: f32,
) -> f32 {
	// The center offset approximates the contact lever arm. A centered, straight
	// impact produces no spin, while a glancing hit rotates the struck chassis in
	// the direction of the delivered impulse. Keep it restrained so contact never
	// turns a parked car into a pinwheel.
	rx, ry := source.x - target.x, source.y - target.y
	return clamp((rx * incoming_y - ry * incoming_x) * transfer * .10, -.12, .12)
}

vehicle_collision_yaw_rate :: proc(current, impulse: f32) -> f32 {
	// Repeated contacts in a pileup may arrive before passive damping runs. Cap
	// the accumulated body rotation as well as each impulse to prevent pinwheels.
	return clamp(current + impulse, -.12, .12)
}

vehicle_impact_strength_from_delta :: proc(delta_x, delta_y: f32) -> f32 {
	return clamp(f32(math.sqrt(f64(delta_x * delta_x + delta_y * delta_y))) / .58, 0, 1)
}

vehicle_impact_is_new_event :: proc(current_impact, new_strength: f32) -> bool {
	amount := clamp(new_strength, 0, 1)
	return current_impact <= .002 || amount > current_impact + .20
}

vehicle_record_impact :: proc(v: ^Vehicle_State, delta_x, delta_y, strength: f32) {
	amount := clamp(strength, 0, 1)
	if amount + f32(.0001) >= v.impact {
		magnitude := f32(math.sqrt(f64(delta_x * delta_x + delta_y * delta_y)))
		if magnitude > .0001 {
			forward_x, forward_y :=
				f32(math.cos(f64(v.heading))),
				f32(math.sin(f64(v.heading))); right_x, right_y := -forward_y, forward_x
			v.impact_forward = clamp(
				(delta_x * forward_x + delta_y * forward_y) / magnitude,
				-1,
				1,
			)
			v.impact_side = clamp((delta_x * right_x + delta_y * right_y) / magnitude, -1, 1)
		}
		// Comparable contact on consecutive ticks refreshes strength and direction
		// without pinning the directional camera wave at sin(0). Restart only for a
		// fresh pulse, a materially stronger hit, or after the prior pulse has run.
		if vehicle_impact_is_new_event(v.impact, amount) || v.impact_time > .09 do v.impact_time = 0
	}
	v.impact = max(v.impact, amount)
}

vehicle_record_collision_lateral_load :: proc(v: ^Vehicle_State, delta_x, delta_y: f32) {
	right_x := -f32(math.sin(f64(v.heading))); right_y := f32(math.cos(f64(v.heading)))
	load := clamp((delta_x * right_x + delta_y * right_y) / .018, -1, 1)
	if math.abs(load) > math.abs(v.chassis_lateral_acceleration) do v.chassis_lateral_acceleration = load
}

vehicle_decay_impact :: proc(v: ^Vehicle_State) {
	if v.impact > 0 do v.impact_time += FIXED_TIMESTEP
	v.impact *= .82
	if v.impact < .002 {v.impact = 0; v.impact_forward = 0; v.impact_side = 0; v.impact_time = 0}
}

vehicle_collision_pitch_impulse :: proc(
	v: Vehicle_State,
	delta_x, delta_y: f32,
	tune: Vehicle_Tune,
) -> f32 {
	forward_x, forward_y := f32(math.cos(f64(v.heading))), f32(math.sin(f64(v.heading)))
	longitudinal_delta := delta_x * forward_x + delta_y * forward_y
	return clamp(longitudinal_delta * .055 * tune.chassis_compliance, -.065, .065)
}

vehicle_advance_resolved_collision_motion :: proc(
	g: ^Game,
	v: ^Vehicle_State,
	index, remaining_steps, total_steps: int,
) -> int {
	if remaining_steps <= 0 || total_steps <= 0 do return 0
	step_x, step_y := v.velocity_x / f32(total_steps), v.velocity_y / f32(total_steps)
	advanced := 0
	for _ in 0 ..< remaining_steps {
		nx, ny := v.x + step_x, v.y + step_y
		if !vehicle_position_clear(g, nx, ny, v.heading, index) do break
		v.x, v.y = nx, ny; advanced += 1
	}
	return advanced
}

vehicle_swept_move :: proc(
	g: ^Game,
	v: ^Vehicle_State,
	index: int,
	transfer_impulse: bool = true,
	impact_event: ^f32 = nil,
	travel_event: ^f32 = nil,
) -> bool {
	distance := vehicle_actual_speed(v^)
	if travel_event != nil do travel_event^ = 0
	if distance <= .00001 do return false
	// Keep each collision probe comfortably below the narrowest vehicle sample
	// spacing. This prevents a fast car from stepping through parked traffic or
	// clipping across a building corner between frames.
	steps := max(1, int(math.ceil(f64(distance / .10))))
	step_x, step_y := v.velocity_x / f32(steps), v.velocity_y / f32(steps)
	step_distance := f32(math.sqrt(f64(step_x * step_x + step_y * step_y))); traveled: f32
	collision_tune := vehicle_tune(index)
	for step_index in 0 ..< steps {
		nx, ny := v.x + step_x, v.y + step_y
		if !vehicle_position_clear(g, nx, ny, v.heading, index) {
			hit_index := vehicle_collision_car_index(g, nx, ny, v.heading, index)
			hit_furniture := vehicle_collision_furniture_index(g, nx, ny, v.heading)
			rebound :=
				collision_tune.collision_rebound; if hit_index >= 0 do rebound = vehicle_collision_rebound(collision_tune, vehicle_tune(hit_index))
			if hit_furniture >= 0 do rebound = .06
			incoming_x, incoming_y := v.velocity_x, v.velocity_y
			contact_base_x, contact_base_y: f32
			if hit_index >=
			   0 {contact_base_x = g.vehicles[hit_index].velocity_x; contact_base_y = g.vehicles[hit_index].velocity_y}
			if hit_furniture >=
			   0 {contact_base_x = g.city_furniture[hit_furniture].velocity_x; contact_base_y = g.city_furniture[hit_furniture].velocity_y}
			relative_x, relative_y := incoming_x - contact_base_x, incoming_y - contact_base_y
			// Resolve a glancing contact along whichever world axis remains clear.
			// This preserves tangential motion against long walls and parked cars;
			// a corner that blocks both axes still receives the compact rebound.
			x_clear :=
				math.abs(step_x) > .00001 &&
				vehicle_position_clear(g, v.x + step_x, v.y, v.heading, index)
			y_clear :=
				math.abs(step_y) > .00001 &&
				vehicle_position_clear(g, v.x, v.y + step_y, v.heading, index)
			contact_normal_x, contact_normal_y: f32
			if hit_index >= 0 || hit_furniture >= 0 {
				// Vehicle contacts use their center line as the normal, making glancing
				// response rotationally consistent instead of dependent on world axes.
				if hit_index >=
				   0 {contact_normal_x, contact_normal_y = v.x - g.vehicles[hit_index].x, v.y - g.vehicles[hit_index].y} else {contact_normal_x, contact_normal_y = v.x - g.city_furniture[hit_furniture].x, v.y - g.city_furniture[hit_furniture].y}
				tangent_step := vehicle_car_contact_tangent_step(
					step_x,
					step_y,
					contact_normal_x,
					contact_normal_y,
				)
				if tangent_step.x * tangent_step.x + tangent_step.y * tangent_step.y > .0000001 &&
				   vehicle_position_clear(
					   g,
					   v.x + tangent_step.x,
					   v.y + tangent_step.y,
					   v.heading,
					   index,
				   ) {v.x += tangent_step.x; v.y += tangent_step.y; traveled += f32(math.sqrt(f64(tangent_step.x * tangent_step.x + tangent_step.y * tangent_step.y)))}
				resolved := vehicle_resolve_car_contact_velocity(
					relative_x,
					relative_y,
					contact_normal_x,
					contact_normal_y,
					collision_tune.collision_tangent_retention,
					rebound,
				)
				v.velocity_x =
					contact_base_x + resolved.x; v.velocity_y = contact_base_y + resolved.y
				tangent_speed := math.abs(
					relative_x * contact_normal_y - relative_y * contact_normal_x,
				)
				if tangent_speed > .001 do v.yaw_rate *= .42
				else do v.yaw_rate *= -.22
			} else if x_clear && !y_clear {
				v.x +=
					step_x; traveled += math.abs(step_x); v.velocity_x = contact_base_x + relative_x * vehicle_wall_tangent_retention(); v.velocity_y = contact_base_y - relative_y * rebound; v.yaw_rate *= .42
			} else if y_clear && !x_clear {
				v.y +=
					step_y; traveled += math.abs(step_y); v.velocity_x = contact_base_x - relative_x * rebound; v.velocity_y = contact_base_y + relative_y * vehicle_wall_tangent_retention(); v.yaw_rate *= .42
			} else {
				v.velocity_x =
					contact_base_x -
					relative_x *
						rebound; v.velocity_y = contact_base_y - relative_y * rebound; v.yaw_rate *= -.22
			}
			// Camera, haptics, and audio should follow the acceleration occupants feel,
			// not merely closing speed. Mass-aware carry-through therefore reads softer
			// than a large recoil even when both contacts begin at the same speed.
			delta_velocity_x, delta_velocity_y :=
				v.velocity_x - incoming_x, v.velocity_y - incoming_y
			if hit_index >= 0 {
				// The same off-center impulse that spins the struck body also acts at a
				// lever arm on the source. Derive reaction torque from its resolved delta
				// so carry-through and recoil produce proportionate rotation.
				reaction_factor := vehicle_collision_transfer_factor(
					vehicle_tune(hit_index),
					collision_tune,
				)
				reaction_yaw := vehicle_collision_yaw_impulse(
					g.vehicles[hit_index],
					v^,
					delta_velocity_x,
					delta_velocity_y,
					reaction_factor,
				)
				v.yaw_rate = vehicle_collision_yaw_rate(v.yaw_rate, reaction_yaw)
			}
			contact_impact := vehicle_impact_strength_from_delta(
				delta_velocity_x,
				delta_velocity_y,
			); new_audio_impact := vehicle_impact_is_new_event(v.impact, contact_impact); vehicle_record_impact(v, delta_velocity_x, delta_velocity_y, contact_impact); if impact_event != nil do impact_event^ = new_audio_impact ? contact_impact : f32(0)
			vehicle_record_collision_lateral_load(v, delta_velocity_x, delta_velocity_y)
			// The tire model must inherit the direction and magnitude that survived
			// contact; retaining the pre-impact wheel speed pulls the car back into
			// the obstacle on the following simulation tick.
			v.body_pitch += vehicle_collision_pitch_impulse(
				v^,
				v.velocity_x - incoming_x,
				v.velocity_y - incoming_y,
				collision_tune,
			)
			v.body_pitch = clamp(v.body_pitch, -.075, .075)
			vehicle_sync_driveline_to_velocity(v)
			if transfer_impulse && hit_index >= 0 {
				target := &g.vehicles[hit_index]
				transfer := vehicle_collision_transfer_factor(
					collision_tune,
					vehicle_tune(hit_index),
				)
				yaw_impulse := vehicle_collision_yaw_impulse(
					v^,
					target^,
					relative_x,
					relative_y,
					transfer,
				); target.yaw_rate = vehicle_collision_yaw_rate(target.yaw_rate, yaw_impulse)
				// Use the same pre-slide contact normal as source rebound. Recomputing
				// after tangential advancement makes the two bodies solve different frames.
				delta := vehicle_car_contact_transfer(
					relative_x,
					relative_y,
					contact_normal_x,
					contact_normal_y,
					transfer,
				); delta_x, delta_y := delta.x, delta.y
				target.body_pitch += vehicle_collision_pitch_impulse(
					target^,
					delta_x,
					delta_y,
					vehicle_tune(hit_index),
				); target.body_pitch = clamp(target.body_pitch, -.075, .075)
				target.velocity_x += delta_x; target.velocity_y += delta_y
				target_impact := vehicle_impact_strength_from_delta(
					delta_x,
					delta_y,
				); vehicle_record_impact(target, delta_x, delta_y, target_impact)
				vehicle_record_collision_lateral_load(target, delta_x, delta_y)
				vehicle_sync_driveline_to_velocity(target)
			}
			if transfer_impulse && hit_furniture >= 0 {
				prop := &g.city_furniture[hit_furniture]; template := city_furniture_template(prop.kind)
				normal_length := f32(
					math.sqrt(
						f64(
							contact_normal_x * contact_normal_x +
							contact_normal_y * contact_normal_y,
						),
					),
				); if normal_length < .001 do normal_length = 1
				nx_contact, ny_contact :=
					contact_normal_x / normal_length, contact_normal_y / normal_length
				closing := max(
					0,
					-(relative_x * nx_contact + relative_y * ny_contact),
				); transfer := clamp(collision_tune.mass / (collision_tune.mass + template.mass) * 1.35, .28, 1.05)
				impulse :=
					closing *
					transfer; prop.velocity_x -= nx_contact * impulse; prop.velocity_y -= ny_contact * impulse
				lever :=
					(-ny_contact * relative_x +
						nx_contact *
							relative_y); prop.angular_velocity += clamp(lever * transfer * .10, -.16, .16)
				prop.pitch = clamp(
					prop.pitch + closing * .16,
					0,
					.38,
				); prop.roll = clamp(prop.roll + lever * .10, -.32, .32)
			}
			// Finish the unused fraction of this fixed tick with resolved motion.
			// Each substep remains collision-checked, so a second obstacle safely stops
			// the carry-through without reapplying the first contact impulse.
			advanced := vehicle_advance_resolved_collision_motion(
				g,
				v,
				index,
				steps - step_index - 1,
				steps,
			); resolved_step_distance := vehicle_actual_speed(v^) / f32(steps); traveled += f32(advanced) * resolved_step_distance; if travel_event != nil do travel_event^ = traveled
			return true
		}
		v.x, v.y = nx, ny; traveled += step_distance
	}
	if travel_event != nil do travel_event^ = traveled
	return false
}

vehicle_update_passive :: proc(g: ^Game, index: int) {
	v := &g.vehicles[index]
	tune := vehicle_tune(index)
	velocity_before_x, velocity_before_y := v.velocity_x, v.velocity_y
	vehicle_decay_impact(v)
	v.driver_assist = .None; v.driver_assist_strength = 0; v.driver_assist_time = 0
	v.handbrake_slip = vehicle_handbrake_slip_step_tuned(v.handbrake_slip, false, tune)
	surface_roughness, surface_bias := vehicle_surface_contact(
		v^,
	); v.surface_blend = vehicle_surface_blend_step_to(v.surface_blend, surface_roughness); v.surface_lateral_bias = vehicle_surface_bias_step(v.surface_lateral_bias, surface_bias); surface_retention := 1 - v.surface_blend * .025; surface_tune := vehicle_tune_for_surface_blend(tune, v.surface_blend)
	v.yaw_rate +=
		vehicle_surface_drag_yaw(v^) +
		vehicle_self_aligning_yaw_blended(
			v^,
			v.handbrake_slip,
			surface_tune,
		); v.yaw_rate *= vehicle_passive_yaw_retention(tune) * (1 - v.surface_blend * .015); v.heading += v.yaw_rate
	if vehicle_actual_speed(v^) <
	   .002 {v.velocity_x = 0; v.velocity_y = 0; v.speed = 0; v.yaw_rate *= .65; if math.abs(v.yaw_rate) < .0002 do v.yaw_rate = 0; v.acceleration_feedback *= .82; v.chassis_acceleration *= .82; v.chassis_lateral_acceleration *= .82; vehicle_update_body_roll_blended(v, v.handbrake_slip, tune); vehicle_update_body_pitch(v, tune); v.traction_state = .Grip; return}
	// An unoccupied car rolls freely longitudinally, but its tires still oppose a
	// sideways shove. Sync wheel speed first so only lateral slip is scrubbed.
	vehicle_sync_driveline_to_velocity(
		v,
	); vehicle_apply_tire_grip_blended(v, v.handbrake_slip, surface_tune)
	retention :=
		vehicle_passive_momentum_retention(tune) *
		surface_retention; v.velocity_x *= retention; v.velocity_y *= retention
	vehicle_sync_driveline_to_velocity(v)
	// Passive bodies still carry real collision momentum. The regular transfer
	// factor and passive damping keep pile-up propagation bounded while allowing
	// a struck car to shove the next vehicle instead of acting as a dead stop.
	collided := vehicle_swept_move(g, v, index, true)
	v.traction_state = vehicle_traction_state_step(v.traction_state, v^)
	vehicle_update_acceleration_feedback_from_velocity(
		v,
		velocity_before_x,
		velocity_before_y,
		collided,
	); vehicle_update_body_roll_blended(v, v.handbrake_slip, tune); vehicle_update_body_pitch(v, tune)
}

vehicle_passive_momentum_retention :: proc(tune: Vehicle_Tune) -> f32 {
	// Once unoccupied, a struck body coasts according to inertia rather than the
	// unrelated coefficient used for sliding along collision surfaces.
	return clamp(.89 + tune.mass * .035, .90, .95)
}
vehicle_passive_yaw_retention :: proc(tune: Vehicle_Tune) -> f32 {
	return clamp(.76 + tune.mass * .08, .80, .90)
}

vehicle_update_passive_vehicles :: proc(g: ^Game) {for 	_, i in g.vehicles {if i != g.driving_vehicle do vehicle_update_passive(g, i)}}

city_furniture_position_clear :: proc(g: ^Game, index: int, x, y: f32) -> bool {
	prop := g.city_furniture[index]; radius := city_furniture_template(prop.kind).radius
	offsets := [5]Vec2{{0, 0}, {radius, 0}, {-radius, 0}, {0, radius}, {0, -radius}}
	for offset in offsets {sx, sy := x + offset.x, y + offset.y
		currently_inside_vehicle := city_car_at(g, prop.x + offset.x, prop.y + offset.y)
		if city_wall(sx, sy) || city_car_at(g, sx, sy) && !currently_inside_vehicle || city_furniture_index_at(g, sx, sy, index) >= 0 do return false}
	return true
}

update_city_furniture :: proc(g: ^Game) {
	for &prop, i in g.city_furniture {
		speed := f32(
			math.sqrt(f64(prop.velocity_x * prop.velocity_x + prop.velocity_y * prop.velocity_y)),
		)
		if speed > .0005 {
			steps := max(
				1,
				int(math.ceil(f64(speed / .08))),
			); step_x, step_y := prop.velocity_x / f32(steps), prop.velocity_y / f32(steps)
			for _ in 0 ..< steps {
				x_clear := city_furniture_position_clear(
					g,
					i,
					prop.x + step_x,
					prop.y,
				); y_clear := city_furniture_position_clear(g, i, prop.x, prop.y + step_y)
				if x_clear do prop.x += step_x
				else do prop.velocity_x *= -.18
				if y_clear do prop.y += step_y
				else do prop.velocity_y *= -.18
				if !x_clear && !y_clear do break
			}
		}
		prop.heading +=
			prop.angular_velocity; prop.velocity_x *= .90; prop.velocity_y *= .90; prop.angular_velocity *= .86; prop.roll *= .92; prop.pitch *= .92
		if math.abs(prop.velocity_x) < .0005 do prop.velocity_x = 0; if math.abs(prop.velocity_y) < .0005 do prop.velocity_y = 0; if math.abs(prop.angular_velocity) < .0003 do prop.angular_velocity = 0
	}
}

vehicle_can_exit :: proc(v: Vehicle_State) -> bool {
	// Chassis stillness alone is insufficient during a burnout or locked driveline
	// transition. Require the wheels, body translation, and rotation all to settle.
	return(
		vehicle_actual_speed(v) < .075 &&
		math.abs(v.speed) < .075 &&
		math.abs(v.yaw_rate) < .008 \
	)
}

city_player_exit_clear :: proc(g: ^Game, position: Vec2, vehicle_index: int) -> bool {
	offsets := [5]Vec2{{0, 0}, {.24, 0}, {-.24, 0}, {0, .24}, {0, -.24}}
	for offset in offsets {x, y := position.x + offset.x, position.y + offset.y
		if city_wall(x, y) || city_car_at(g, x, y, vehicle_index) || city_furniture_index_at(g, x, y) >= 0 do return false}
	return true
}

vehicle_exit_position :: proc(g: ^Game, v: Vehicle_State, vehicle_index: int) -> (Vec2, bool) {
	side := Vec2{-f32(math.sin(f64(v.heading))), f32(math.cos(f64(v.heading)))}
	signs := [2]f32 {
		1,
		-1,
	}; for sign in signs {candidate := Vec2{v.x + side.x * 1.45 * sign, v.y + side.y * 1.45 * sign}; if city_player_exit_clear(g, candidate, vehicle_index) do return candidate, true}
	return {}, false
}

city_district :: proc(x: f32) -> int {if x < 64 do return 0; if x < 128 do return 1; return 2}
city_district_name :: proc(x: f32) -> string {names := [3]string {
		"WESTHAVEN",
		"CENTRAL LOOP",
		"LAKE INDUSTRIAL",
	}
	return names[city_district(x)]}

// Neighborhood names follow memorable seams in the city rather than the old
// three vertical render bands. They are intentionally stable map vocabulary:
// landmark directions and future cases can refer to them without owning city
// geometry.
city_neighborhood_name :: proc(x, y: f32) -> string {
	lx, ly := city_layout(x), city_layout(y)
	if lx < 64 {if ly < 72 do return "WESTHAVEN HEIGHTS"; return "DEPOT WARD"}
	if lx < 128 {
		if ly < 64 do return "OLD MARKET"
		if ly < 104 do return "CIVIC LOOP"
		return "FOUNDRY WARD"
	}
	if ly < 64 do return "EAST BANK"
	if ly < 116 do return "SOUTH QUAY"
	return "MARINA REACH"
}

// Preserve a continuous skyline from the low driving camera while leaving a
// little room before the world's far plane for meshes at the envelope edge.
CITY_ROAD_DRAW_DISTANCE :: f32(96) * CITY_WORLD_SCALE
CITY_BUILDING_DRAW_DISTANCE :: f32(112) * CITY_WORLD_SCALE
CITY_DYNAMIC_DRAW_DISTANCE :: f32(88) * CITY_WORLD_SCALE
CITY_DRIVING_BEHIND_DISTANCE :: f32(-20) * CITY_WORLD_SCALE

city_render_chunk_visible :: proc(g: ^Game, x, y, distance_limit, behind_limit: f32) -> bool {
	origin_x, origin_y := g.city_x, g.city_y
	forward_x, forward_y := f32(0), f32(0)
	if g.driving_vehicle >= 0 && g.driving_vehicle < len(g.vehicles) {
		// Use the rendered camera rather than vehicle heading. Reverse driving,
		// momentum lookahead, impacts, and camera transitions can all make the
		// camera face somewhere other than g.city_angle.
		view := vk_world_view_pose(g)
		origin_x, origin_y = view.eye.x, view.eye.z
		forward_x, forward_y = view.target.x - view.eye.x, view.target.z - view.eye.z
		forward_length := f32(math.sqrt(f64(forward_x * forward_x + forward_y * forward_y)))
		if forward_length > .0001 {forward_x /= forward_length; forward_y /= forward_length}
	}
	dx, dy := x - origin_x, y - origin_y
	if dx * dx + dy * dy > distance_limit * distance_limit do return false
	// Walking uses the elevated orbit camera, so the player's facing direction
	// says nothing about which chunks are in the camera frustum. The directional
	// rejection is only useful for the low, forward-facing driving camera.
	if g.driving_vehicle < 0 do return true
	facing := dx * forward_x + dy * forward_y
	return facing >= behind_limit
}

context_resolve_city :: proc(g: ^Game) {
	next := Context_Target{}
	if g.driving_vehicle >=
	   0 {car := g.vehicles[g.driving_vehicle]; stopped := vehicle_can_exit(car); _, exit_clear := vehicle_exit_position(g, car, g.driving_vehicle); can_exit := stopped && exit_clear; action := can_exit ? "EXIT VEHICLE" : stopped ? "NO ROOM TO EXIT" : "SLOW TO EXIT"; next = {
			valid         = true,
			kind          = .Vehicle,
			status        = can_exit ? .Available : .Unavailable,
			stable_id     = fmt.tprintf("vehicle_%d", g.driving_vehicle),
			label         = strings.to_upper(CITY_CARS[g.driving_vehicle].model),
			action        = action,
			world         = {car.x, car.y},
			source_index  = g.driving_vehicle,
			runtime_index = -1,
			priority      = 40,
			reachable     = can_exit,
		}} else if g.near_landmark >= 0 {
		landmark, _ := city_landmark_at(
			g,
			g.near_landmark,
		); payload := mystery_game_payload(g); tutorial := payload != nil && payload.tutorial_id == "basic_controls"; destination := payload != nil && landmark.id == payload.city_destination; available := true
		action := "VISIT"; if payload != nil && landmark.id == payload.city_start && tutorial {available = true; action = "RECEIVE BRIEFING"} else if destination {available = !tutorial || tutorial_completed(g, .Briefing); action = available ? "ENTER VALE HOUSE" : "RECEIVE BRIEFING FIRST"}
		next = {
			valid         = true,
			kind          = .Landmark,
			status        = available ? .Available : .Unavailable,
			stable_id     = landmark.id,
			label         = landmark.name,
			action        = action,
			world         = {landmark.x, landmark.y},
			source_index  = g.near_landmark,
			runtime_index = -1,
			priority      = 30,
			reachable     = available,
		}
	} else if g.near_vehicle >= 0 {car := g.vehicles[g.near_vehicle]; next = {
			valid         = true,
			kind          = .Vehicle,
			status        = .Available,
			stable_id     = fmt.tprintf("vehicle_%d", g.near_vehicle),
			label         = strings.to_upper(CITY_CARS[g.near_vehicle].model),
			action        = "ENTER VEHICLE",
			world         = {car.x, car.y},
			source_index  = g.near_vehicle,
			runtime_index = -1,
			priority      = 25,
			reachable     = true,
		}}
	if next.valid {g.context_ui.last_valid_time = g.animation_time; if !g.context_ui.current.valid || g.context_ui.current.kind != next.kind || g.context_ui.current.stable_id != next.stable_id {g.context_ui.previous = g.context_ui.current; g.context_ui.focus_started = g.animation_time; play_sound(g, .Pick_Up)}}
	g.context_ui.current = next
}

city_briefing_actionable :: proc(g: ^Game) -> bool {
	target := g.context_ui.current
	payload := mystery_game_payload(
		g,
	); return payload != nil && payload.tutorial_id == "basic_controls" && target.valid && target.reachable && target.kind == .Landmark && target.stable_id == payload.city_start
}

context_activate_city :: proc(g: ^Game, target: Context_Target) -> bool {
	if !target.valid || !target.reachable do return false
	if target.kind == .Vehicle {
		tutorial_complete(g, .Travel)
		if g.driving_vehicle >=
		   0 {v := g.vehicles[g.driving_vehicle]; if !vehicle_can_exit(v) do return false; exit_position, exit_clear := vehicle_exit_position(g, v, g.driving_vehicle); if !exit_clear do return false; g.city_x = exit_position.x; g.city_y = exit_position.y; g.city_camera_x = exit_position.x; g.city_camera_y = exit_position.y; g.city_camera_initialized = true; g.vehicles[g.driving_vehicle].driver_assist = .None; g.vehicles[g.driving_vehicle].driver_assist_strength = 0; g.vehicles[g.driving_vehicle].driver_assist_time = 0; g.driving_vehicle = -1; return true}
		if target.source_index >= 0 &&
		   target.source_index <
			   len(
				   g.vehicles,
			   ) {g.driving_vehicle = target.source_index; vehicle := &g.vehicles[g.driving_vehicle]; vehicle.steering = 0; vehicle.acceleration_feedback = 0; vehicle.chassis_acceleration = 0; vehicle.chassis_lateral_acceleration = 0; vehicle.driver_assist = .None; vehicle.driver_assist_strength = 0; vehicle.driver_assist_time = 0; vehicle.traction_state = vehicle_traction_state(vehicle^); g.city_x = vehicle.x; g.city_y = vehicle.y; g.city_angle = vehicle.heading; g.near_vehicle = -1; g.vehicle_audio_frequency = 0; g.vehicle_audio_gain = 0; g.vehicle_audio_tire_frequency_a = 0; g.vehicle_audio_tire_frequency_b = 0; g.vehicle_audio_tire_gain = 0; g.vehicle_audio_rough_gain = 0; g.vehicle_camera_reverse_blend = 0; g.vehicle_camera_follow_distance = 0; g.vehicle_skid_emit_distance = 0; g.vehicle_impact_sound_cooldown = 0; return true}
	}
	if target.kind ==
	   .Landmark {landmark, ok := city_landmark_at(g, target.source_index); if !ok do return false
		payload := mystery_game_payload(
			g,
		); if payload != nil && landmark.id == payload.city_start && payload.tutorial_id == "basic_controls" {tutorial_complete(g, .Contextual_Interaction); if !dialogue_start_scene(g, story_scene_index(g.story_project, "scene_police_briefing")) do return false; tutorial_complete(g, .Briefing); _ = game_story_milestone(g, "city.briefing_received"); return true}
		if payload != nil &&
		   landmark.id ==
			   payload.city_destination {location, found := case_city_location(g, landmark.id); if !found || !apply_player_spawn_marker(g, location.level_spawn) do return false; tutorial_complete(g, .Travel); _ = game_story_milestone(g, "city.case_destination_entered"); g.city_return_x = landmark.arrival_x; g.city_return_y = landmark.arrival_y; g.city_return_angle = landmark.arrival_facing * f32(math.PI) / 180; g.camera_initialized = false; g.environment_blend = 1; g.cutaway_transition = 0; g.screen = .Investigate; return true}
		context_feedback(
			g,
			landmark.name,
			.Available,
			landmark.id,
		); g.context_ui.feedback_expires = g.animation_time + 4; return true
	}
	return false
}

// A roughly GTA III-scale footprint across 30,720 cells. Each borough has its
// own grain: Westhaven's narrow residential blocks, the Loop's dense commercial
// streets, and the port's long industrial superblocks. A handful of old routes
// cross those grains and make the neighborhood seams legible while driving.
