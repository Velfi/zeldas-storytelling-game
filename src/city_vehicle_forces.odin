package main

import "core:math"

vehicle_age_skid_marks :: proc(g: ^Game) {for 	&mark in g.vehicle_skid_marks {if !mark.active do continue; mark.age += FIXED_TIMESTEP; if mark.age >= VEHICLE_SKID_LIFETIME do mark.active = false}}

vehicle_skid_pending_distance_step :: proc(current, strength: f32) -> f32 {
	if strength <= .02 do return 0
	result := max(current, f32(0)) * .65
	if result < .01 do return 0
	return result
}

vehicle_skid_heading :: proc(v: Vehicle_State) -> f32 {
	if vehicle_actual_speed(v) < .01 do return v.heading
	return f32(math.atan2(f64(v.velocity_y), f64(v.velocity_x)))
}

vehicle_update_skid_marks_blended :: proc(
	g: ^Game,
	v: Vehicle_State,
	handbrake_amount, roughness: f32,
	resolved_movement: Vec2 = {},
	movement_resolved: bool = false,
	resolved_travel_distance: f32 = -1,
) {
	strength := vehicle_skid_strength_surface_blended(v, handbrake_amount, roughness)
	if strength <=
	   .08 {g.vehicle_skid_emit_distance = vehicle_skid_pending_distance_step(g.vehicle_skid_emit_distance, strength); return}
	movement := resolved_movement
	if !movement_resolved do movement = {v.velocity_x, v.velocity_y}
	movement_distance := f32(
		math.sqrt(f64(movement.x * movement.x + movement.y * movement.y)),
	); travel_distance := movement_distance
	if resolved_travel_distance >= 0 do travel_distance = resolved_travel_distance
	g.vehicle_skid_emit_distance += travel_distance
	if g.vehicle_skid_emit_distance < .72 do return
	// Preserve distance beyond the spacing threshold so changing speed does not
	// stretch the trail. Cap exceptional collision overshoot to one pending mark.
	overshoot := min(
		g.vehicle_skid_emit_distance - .72,
		f32(.71),
	); g.vehicle_skid_emit_distance = overshoot
	// The threshold is usually crossed between fixed ticks. Back-project along
	// resolved travel so the mark lands at that crossing instead of the frame end.
	emit_x, emit_y := v.x, v.y
	if movement_distance >
	   .001 {emit_x -= movement.x / movement_distance * overshoot; emit_y -= movement.y / movement_distance * overshoot}
	forward := Vec2 {
		f32(math.cos(f64(v.heading))),
		f32(math.sin(f64(v.heading))),
	}; side := Vec2{-forward.y, forward.x}; rear := Vec2{emit_x - forward.x * .72, emit_y - forward.y * .72}
	track_heading := vehicle_skid_heading(v)
	signs := [2]f32 {
		-1,
		1,
	}; for sign in signs {index := g.vehicle_skid_next % VEHICLE_SKID_CAPACITY; g.vehicle_skid_marks[index] = {
			position = {rear.x + side.x * .34 * sign, rear.y + side.y * .34 * sign},
			heading  = track_heading,
			age      = 0,
			strength = strength,
			active   = true,
		}; g.vehicle_skid_next = (g.vehicle_skid_next + 1) % VEHICLE_SKID_CAPACITY}
	front_weight := vehicle_front_skid_weight_for_state(v.traction_state, handbrake_amount)
	if front_weight >
	   0 {front := Vec2{emit_x + forward.x * .72, emit_y + forward.y * .72}; for sign in signs {index := g.vehicle_skid_next % VEHICLE_SKID_CAPACITY; g.vehicle_skid_marks[index] = {
				position = {front.x + side.x * .34 * sign, front.y + side.y * .34 * sign},
				heading  = track_heading,
				age      = 0,
				strength = strength * front_weight,
				active   = true,
			}; g.vehicle_skid_next = (g.vehicle_skid_next + 1) % VEHICLE_SKID_CAPACITY}}
}
vehicle_update_skid_marks :: proc(
	g: ^Game,
	v: Vehicle_State,
	handbrake: bool,
	surface: City_Driving_Surface,
) {vehicle_update_skid_marks_blended(
		g,
		v,
		handbrake ? f32(1) : f32(0),
		surface == .Open_Ground ? f32(1) : f32(0),
	)}

vehicle_combined_grip_factor :: proc(longitudinal_impulse: f32) -> f32 {
	// Keep enough lateral authority for an arcade response, but reserve part of
	// the tire budget in proportion to force actually transmitted. Using raw
	// wheel-speed error would charge low-grip tires for force they cannot produce.
	return 1 - clamp(longitudinal_impulse / .075, 0, 1) * .34
}

vehicle_longitudinal_grip_response :: proc(handbrake_amount: f32, tune: Vehicle_Tune) -> f32 {
	release := clamp(handbrake_amount, 0, 1)
	normal := f32(.34) * tune.longitudinal_grip; loose := f32(.16) * tune.longitudinal_grip
	return normal + (loose - normal) * release
}

vehicle_longitudinal_tire_impulse :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune,
) -> f32 {
	longitudinal := vehicle_longitudinal_speed(v)
	demand := math.abs(v.speed - longitudinal)
	return demand * vehicle_longitudinal_grip_response(handbrake_amount, tune)
}

vehicle_lateral_grip_budget :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune,
) -> f32 {
	// One shared arcade rule: wheel lock/spin spends some cornering authority, but
	// never enough to make the car unsteerable. ABS and TC restore this naturally
	// by reducing the wheel/chassis speed mismatch.
	return vehicle_combined_grip_factor(
		vehicle_longitudinal_tire_impulse(v, handbrake_amount, tune),
	)
}

vehicle_handbrake_slip_step_tuned :: proc(current: f32, pressed: bool, tune: Vehicle_Tune) -> f32 {
	target :=
		pressed ? f32(1) : f32(0); release_response := clamp(.10 / max(tune.chassis_compliance, f32(.2)), .075, .125); response := target > current ? f32(.38) : release_response
	result := current + (target - current) * response
	if math.abs(result - target) < .001 do return target
	return clamp(result, 0, 1)
}
vehicle_handbrake_slip_step :: proc(
	current: f32,
	pressed: bool,
) -> f32 {return vehicle_handbrake_slip_step_tuned(current, pressed, VEHICLE_TUNE_STANDARD)}

vehicle_apply_tire_grip_blended :: proc(
	v: ^Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune,
) {
	forward_x := f32(math.cos(f64(v.heading))); forward_y := f32(math.sin(f64(v.heading)))
	right_x, right_y := -forward_y, forward_x
	longitudinal := v.velocity_x * forward_x + v.velocity_y * forward_y
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	release := clamp(handbrake_amount, 0, 1)
	// Longitudinal grip keeps the throttle responsive while lateral grip is
	// allowed to break away independently. A handbrake mostly releases the rear
	// tires instead of making the engine feel disconnected from the wheels.
	longitudinal_grip := vehicle_longitudinal_grip_response(release, tune)
	normal_lateral :=
		clamp(.24 - math.abs(longitudinal) * .18, .13, .24) *
		tune.lateral_grip *
		vehicle_lateral_grip_budget(
			v^,
			release,
			tune,
		); loose_lateral := f32(.035) * tune.handbrake_grip; lateral_grip := normal_lateral + (loose_lateral - normal_lateral) * release
	longitudinal += (v.speed - longitudinal) * longitudinal_grip
	lateral *= 1 - lateral_grip
	v.velocity_x = forward_x * longitudinal + right_x * lateral
	v.velocity_y = forward_y * longitudinal + right_y * lateral
}
vehicle_apply_tire_grip :: proc(
	v: ^Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune,
) {vehicle_apply_tire_grip_blended(v, handbrake ? f32(1) : f32(0), tune)}
vehicle_should_settle_velocity :: proc(v: Vehicle_State) -> bool {return(
		math.abs(v.speed) < .001 &&
		vehicle_actual_speed(v) < .012 \
	)}

vehicle_self_aligning_yaw_blended :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune,
) -> f32 {
	actual_speed := vehicle_actual_speed(v)
	if actual_speed < .055 do return 0
	forward_x := f32(math.cos(f64(v.heading))); forward_y := f32(math.sin(f64(v.heading)))
	right_x, right_y := -forward_y, forward_x
	longitudinal := v.velocity_x * forward_x + v.velocity_y * forward_y
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	// In reverse the body should align opposite the velocity vector, so the
	// correction changes sign with longitudinal travel. Handbrake grip loss
	// deliberately leaves only a trace of this restoring torque.
	direction := longitudinal < 0 ? f32(-1) : f32(1)
	slip := clamp(lateral / actual_speed, -1, 1)
	speed_weight := clamp((actual_speed - .055) / .30, 0, 1)
	release := 1 - clamp(handbrake_amount, 0, 1) * .78
	// Aligning torque is generated by the same contact patch as lateral force.
	// Wheel lock/spin therefore weakens it, while ABS/TC can restore it by bringing
	// wheel speed back toward chassis travel.
	grip_budget := vehicle_lateral_grip_budget(v, handbrake_amount, tune)
	return slip * direction * speed_weight * .010 * tune.lateral_grip * release * grip_budget
}
vehicle_self_aligning_yaw :: proc(
	v: Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune,
) -> f32 {return vehicle_self_aligning_yaw_blended(v, handbrake ? f32(1) : f32(0), tune)}

vehicle_yaw_load_factor :: proc(v: Vehicle_State, throttle: f32, handbrake: bool) -> f32 {
	if handbrake do return 1
	load := clamp(math.abs(throttle), 0, 1)
	// Use the least-aligned wheel/chassis motion so either can identify braking,
	// then ramp around neutral instead of flipping load transfer in one tick.
	alignment := min(v.speed * throttle, vehicle_longitudinal_speed(v) * throttle)
	power_weight := clamp(alignment / .03, 0, 1); brake_weight := clamp(-alignment / .03, 0, 1)
	return 1 - load * .06 * power_weight + load * .10 * brake_weight
}

vehicle_steering_yaw_speed :: proc(speed: f32) -> f32 {
	// Tire steering has useful leverage as soon as a car begins creeping. The
	// simulation's compact speed scale otherwise makes parking turn-in feel numb.
	// Fade the boost in from rest and away by ordinary street speed; a hard creep
	// threshold would turn tiny velocity noise into a sudden steering snap.
	magnitude := math.abs(speed)
	if magnitude == 0 do return 0
	creep_ramp := clamp(magnitude / .016, 0, 1)
	boost := (1 - clamp(magnitude / .10, 0, 1)) * .024 * creep_ramp
	return speed < 0 ? -(magnitude + boost) : magnitude + boost
}

vehicle_steering_travel_speed :: proc(v: Vehicle_State) -> f32 {
	// Steering geometry acts on ground travel, not wheel/driveline rotation.
	// This preserves direction control during braking and neutral coasting while
	// preventing a stationary burnout from rotating the whole chassis.
	return vehicle_steering_yaw_speed(vehicle_longitudinal_speed(v))
}

vehicle_steering_lateral_grip_factor :: proc(v: Vehicle_State, steering: f32) -> f32 {
	// Lateral saturation should soften added lock into a slide, giving the limit
	// a progressive understeer shoulder. Countersteer keeps full authority because
	// it is unloading the existing slip angle rather than asking for more of it.
	if vehicle_is_countersteering(v, steering) do return 1
	slip := vehicle_lateral_slip_ratio(v)
	return 1 - clamp((slip - .18) / .62, 0, 1) * .28
}

vehicle_apply_yaw_blended :: proc(
	v: ^Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune,
	throttle: f32 = 0,
) {
	steering_speed := vehicle_steering_travel_speed(v^)
	release := clamp(
		handbrake_amount,
		0,
		1,
	); normal_load := vehicle_yaw_load_factor(v^, throttle, false); load_factor := normal_load + (1 - normal_load) * release; yaw_leverage := 1 + release * .32
	// Steering rotation and lateral force must spend the same tire budget. This
	// keeps a locked or spinning wheel from yawing the body as though it still had
	// full cornering authority, while an ABS/TC correction restores turn-in.
	steering_grip :=
		vehicle_lateral_grip_budget(v^, release, tune) *
		vehicle_steering_lateral_grip_factor(v^, v.steering)
	target :=
		v.steering * steering_speed * .075 * yaw_leverage * load_factor * steering_grip +
		vehicle_self_aligning_yaw_blended(v^, release, tune) +
		vehicle_surface_drag_yaw(v^, throttle)
	// Rear grip loss lets rotation persist, while normal tires settle the body
	// promptly. Archetype response gives sports cars crisp turn-in and keeps
	// heavy vehicles deliberate without changing input semantics.
	response := tune.yaw_response * (1 - release * .45)
	v.yaw_rate += (target - v.yaw_rate) * response
	v.yaw_rate = clamp(v.yaw_rate, -.045, .045)
	if math.abs(v.speed) < .004 && math.abs(target) < .0001 do v.yaw_rate *= .72
	v.heading += v.yaw_rate
}
vehicle_apply_yaw :: proc(
	v: ^Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune,
	throttle: f32 = 0,
) {vehicle_apply_yaw_blended(v, handbrake ? f32(1) : f32(0), tune, throttle)}

vehicle_body_roll_target_blended :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {
	// Measured lateral tire force supplies the real weight transfer. A restrained
	// yaw contribution preserves readable passive collision rotation without
	// making a freely sliding body lean as though it still had full grip.
	speed_weight := clamp(vehicle_actual_speed(v) / .46, 0, 1)
	force_turn := clamp(v.chassis_lateral_acceleration, -1, 1)
	travel_direction := clamp(vehicle_longitudinal_speed(v) / .04, -1, 1)
	rotation_turn := clamp(v.yaw_rate / .045, -1, 1) * travel_direction
	turn_weight := clamp(force_turn + rotation_turn * .25, -1, 1)
	roll_limit := .068 + (.095 - .068) * clamp(handbrake_amount, 0, 1)
	return -turn_weight * speed_weight * roll_limit * tune.chassis_compliance
}
vehicle_body_roll_target :: proc(
	v: Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {return vehicle_body_roll_target_blended(v, handbrake ? f32(1) : f32(0), tune)}

vehicle_update_body_roll_blended :: proc(
	v: ^Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) {
	target := vehicle_body_roll_target_blended(v^, handbrake_amount, tune)
	compliance_response := clamp(1 / max(tune.chassis_compliance, f32(.2)), .76, 1.28)
	release_response := target == 0 ? f32(.14) : f32(.10)
	response :=
		vehicle_feedback_response(v.body_roll, target, .16, release_response) * compliance_response
	v.body_roll += (target - v.body_roll) * response
	if math.abs(v.body_roll) < .0001 && math.abs(target) < .0001 do v.body_roll = 0
}
vehicle_update_body_roll :: proc(
	v: ^Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) {vehicle_update_body_roll_blended(v, handbrake ? f32(1) : f32(0), tune)}

vehicle_body_pitch_target :: proc(
	acceleration_feedback: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {
	load := clamp(acceleration_feedback, -1, 1)
	// Launch raises the nose; braking gets slightly more travel so a firm stop
	// reads clearly without turning the chassis into a cartoon hinge.
	return load * (load >= 0 ? f32(.038) : f32(.052)) * tune.chassis_compliance
}

vehicle_update_body_pitch :: proc(v: ^Vehicle_State, tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD) {
	target := vehicle_body_pitch_target(v.chassis_acceleration, tune)
	compliance_response := clamp(1 / max(tune.chassis_compliance, f32(.2)), .76, 1.28)
	response := vehicle_feedback_response(v.body_pitch, target, .16, .11) * compliance_response
	v.body_pitch += (target - v.body_pitch) * response
	if math.abs(v.body_pitch) < .0001 && math.abs(target) < .0001 do v.body_pitch = 0
}

vehicle_handbrake_drag_factor :: proc(lateral_slip, roughness: f32) -> f32 {
	slip := clamp(lateral_slip, 0, 1); surface := clamp(roughness, 0, 1)
	road := .968 - slip * .022; rough := .962 - slip * .012
	return road + (rough - road) * surface
}

vehicle_drag_factor_blended :: proc(
	tune: Vehicle_Tune,
	roughness, handbrake_amount, throttle, lateral_slip, normalized_speed: f32,
) -> f32 {
	// Lift-off drag grows gently with road speed, providing a readable corner-
	// entry weight shift without making parking-lot coasting feel sticky. Powered
	// running retains the existing low-loss driveline response.
	coast_aero := clamp((normalized_speed - .25) / .75, 0, 1) * .003
	coast := tune.coast_retention - coast_aero
	powered_weight := clamp(math.abs(throttle) / .12, 0, 1)
	road := coast + (.994 - coast) * powered_weight
	// Rough ground keeps strong lift-off loss, while powered retention rises just
	// enough for reduced surface torque to sustain the authored terrain speed.
	rough_retention := .972 + powered_weight * .010
	normal := road + (rough_retention - road) * clamp(roughness, 0, 1)
	handbrake := vehicle_handbrake_drag_factor(lateral_slip, roughness)
	return normal + (handbrake - normal) * clamp(handbrake_amount, 0, 1)
}
vehicle_drag_factor :: proc(
	tune: Vehicle_Tune,
	roughness: f32,
	handbrake: bool,
	throttle: f32,
	lateral_slip: f32 = 0,
	normalized_speed: f32 = 0,
) -> f32 {return vehicle_drag_factor_blended(
		tune,
		roughness,
		handbrake ? f32(1) : f32(0),
		throttle,
		lateral_slip,
		normalized_speed,
	)}

vehicle_steering_response :: proc(
	tune: Vehicle_Tune,
	normalized_speed, steer_input: f32,
	current_steering: f32 = 0,
) -> f32 {
	response := tune.steering_response
	// Self-centering and tiny corrections need a quicker rack than full turn-in,
	// but the transition must remain continuous around stick center.
	center_weight := 1 - clamp(math.abs(steer_input) / .20, 0, 1)
	response *= 1 + center_weight * (.35 + clamp(normalized_speed, 0, 1) * .65)
	// An intentional direction reversal should cross the rack center promptly;
	// otherwise rapid corrections feel like they spend a beat fighting stale
	// steering. Keep normal turn-in unchanged and retain the global response cap.
	opposition := max(-steer_input * current_steering, f32(0))
	reversal_weight := clamp(opposition / .12, 0, 1)
	response *= 1 + reversal_weight * .28
	return min(response, f32(.42))
}

vehicle_reverse_steering_weight :: proc(v: Vehicle_State) -> f32 {
	longitudinal := vehicle_longitudinal_speed(v)
	// Chassis travel owns direction once established. Near rest, a restrained
	// wheel-speed contribution anticipates the selected direction without a sign
	// threshold that would make available steering lock jump at zero velocity.
	wheel_authority := 1 - clamp(math.abs(longitudinal) / .02, 0, 1)
	direction_signal := longitudinal + v.speed * .15 * wheel_authority
	return clamp((.02 - direction_signal) / .04, 0, 1)
}

vehicle_normalized_steering_speed :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> f32 {
	// Road speed governs safe steering lock. Retain a smaller wheel-speed
	// contribution so a stationary burnout does not instantly command full lock,
	// but never let locked wheels disguise a fast-moving chassis as stationary.
	reference := max(vehicle_actual_speed(v), math.abs(v.speed) * .45)
	// Reverse has a lower authored speed ceiling. Normalizing it against forward
	// top speed leaves far too much steering lock at maximum reversing speed. A
	// blended limit keeps direction changes continuous through neutral.
	reverse_weight := vehicle_reverse_steering_weight(v)
	limit := tune.max_forward + (tune.max_reverse - tune.max_forward) * reverse_weight
	return clamp(reference / max(limit, f32(.01)), 0, 1)
}

vehicle_is_countersteering :: proc(v: Vehicle_State, steer_input: f32) -> bool {
	right_x := -f32(math.sin(f64(v.heading))); right_y := f32(math.cos(f64(v.heading)))
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	return math.abs(lateral) > .01 && steer_input * lateral > 0
}

vehicle_steering_limit :: proc(
	tune: Vehicle_Tune,
	normalized_speed, handbrake_amount: f32,
	countersteering: bool = false,
) -> f32 {
	base := clamp((.9 - clamp(normalized_speed, 0, 1) * .44) * tune.steering_scale, .32, .98)
	// Rear grip release needs additional countersteer range at speed. Keep the
	// gain modest and bounded so the handbrake never restores twitchy full lock.
	if !countersteering do return base
	return clamp(base + clamp(handbrake_amount, 0, 1) * .12, .32, .98)
}

vehicle_stability_assist_scale :: proc(tune: Vehicle_Tune) -> f32 {
	// Preserve the standard tune as the handling baseline. Agile cars leave more
	// recovery to the driver, while slower, heavier archetypes get a calmer and
	// more assertive safety net without changing their authored tire grip.
	return clamp(
		1 +
		(VEHICLE_TUNE_STANDARD.yaw_response - tune.yaw_response) * 2 +
		(tune.mass - VEHICLE_TUNE_STANDARD.mass) * .08,
		.84,
		1.16,
	)
}

vehicle_stability_steering_blended :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {
	actual_speed := vehicle_actual_speed(v)
	if actual_speed < .10 do return 0
	forward_x := f32(
		math.cos(f64(v.heading)),
	); forward_y := f32(math.sin(f64(v.heading))); right_x, right_y := -forward_y, forward_x
	longitudinal := v.velocity_x * forward_x + v.velocity_y * forward_y
	lateral := v.velocity_x * right_x + v.velocity_y * right_y
	signed_slip := clamp(
		lateral / max(actual_speed, f32(.05)),
		-1,
		1,
	); slip := math.abs(signed_slip)
	assist_recovery := 1 - clamp(handbrake_amount, 0, 1)
	slip_steering := signed_slip * clamp((slip - .18) / .62, 0, 1) * .26
	// Slip steering points the nose back toward travel. Once that angle is nearly
	// recovered, compare remaining body rotation with the yaw still required and
	// counter only the excess so a released drift does not coast into a spin.
	direction := longitudinal < 0 ? f32(-1) : f32(1)
	speed_authority := clamp((actual_speed - .10) / .22, 0, 1)
	desired_yaw := signed_slip * direction * speed_authority * .025
	yaw_excess := v.yaw_rate - desired_yaw
	spin_gate :=
		clamp((math.abs(v.yaw_rate) - .012) / .028, 0, 1) * clamp((slip - .04) / .22, 0, 1)
	spin_steering := -clamp(yaw_excess / .032, -1, 1) * direction * spin_gate * .12
	// Apply the same ramp to all recovery torque. Without it, slip steering jumps
	// from zero to useful authority on the first tick above the speed threshold.
	assist_scale := vehicle_stability_assist_scale(tune)
	return clamp(
		(slip_steering + spin_steering) * assist_recovery * speed_authority * assist_scale,
		-.26 * assist_scale,
		.26 * assist_scale,
	)
}
vehicle_stability_steering :: proc(
	v: Vehicle_State,
	handbrake: bool,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {return vehicle_stability_steering_blended(v, handbrake ? f32(1) : f32(0), tune)}

vehicle_assisted_steering_input :: proc(
	v: Vehicle_State,
	driver_input, handbrake_amount: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
) -> f32 {
	// Fade recovery authority out across useful stick travel instead of dropping
	// it at a tiny input threshold. This keeps micro-corrections continuous while
	// ensuring a deliberate steering command always owns the front wheels.
	authority := 1 - clamp(math.abs(driver_input) / .35, 0, 1)
	assist := vehicle_stability_steering_blended(v, handbrake_amount, tune) * authority
	return clamp(driver_input + assist, -1, 1)
}

vehicle_drive_torque_for_reference :: proc(
	tune, driveline_tune: Vehicle_Tune,
	speed: f32,
	forward: bool,
) -> f32 {
	limit := forward ? driveline_tune.max_forward : driveline_tune.max_reverse
	normalized := clamp(math.abs(speed) / max(limit, f32(.01)), 0, 1)
	// A little launch punch makes leaving a stop decisive; tapering the upper
	// range makes reaching maximum speed feel earned instead of linear.
	result := (forward ? tune.acceleration : tune.reverse_acceleration) * (1.18 - normalized * .62)
	if forward do result *= vehicle_shift_torque_factor(normalized)
	// Surface limits are sustainable speeds, not velocity clamps. Above a lower
	// surface limit, taper drive force over a short band while preserving momentum.
	surface_limit := forward ? tune.max_forward : tune.max_reverse
	if surface_limit < limit {
		taper_range := max(surface_limit * .12, f32(.01))
		result *= 1 - clamp((math.abs(speed) - surface_limit) / taper_range, 0, 1)
	}
	return result
}
vehicle_drive_torque :: proc(
	tune: Vehicle_Tune,
	speed: f32,
	forward: bool,
) -> f32 {return vehicle_drive_torque_for_reference(tune, tune, speed, forward)}

vehicle_service_brake_factor :: proc(v: Vehicle_State) -> f32 {
	slip := vehicle_longitudinal_slip_ratio(v)
	// Full pressure remains below the lock threshold. Beyond it, progressively
	// release at most 42% so braking stays strong while tires regain authority.
	return 1 - clamp((slip - .18) / .62, 0, 1) * .42
}

vehicle_service_brake_pressure :: proc(v: Vehicle_State) -> f32 {
	pressure := vehicle_service_brake_factor(v)
	// Retained ABS strength acts as a short hydraulic memory. After a release has
	// recovered wheel speed, pressure reapplies progressively instead of snapping
	// to 100% for one tick and immediately locking the wheel again.
	if v.driver_assist == .ABS do pressure *= 1 - clamp(v.driver_assist_strength, 0, 1) * .12
	return pressure
}

vehicle_apply_abs_release :: proc(v: ^Vehicle_State, brake_authority: f32) {
	authority := clamp(brake_authority, 0, 1)
	if authority <= 0 do return
	longitudinal := vehicle_longitudinal_speed(v^)
	// ABS only releases a wheel lagging chassis travel; a spinning drive wheel is
	// traction control's domain. Moving toward road speed creates a real re-lock
	// cycle on the following brake tick instead of leaving the wheel at zero.
	if math.abs(v.speed) >= math.abs(longitudinal) - .001 || v.speed * longitudinal < 0 do return
	// Normalize the pressure modulation into lock severity. Multiplying the raw
	// 42% pressure release by another response coefficient left a fully locked
	// wheel with too little correction to recover meaningful steering authority.
	severity := clamp((1 - vehicle_service_brake_factor(v^)) / .42, 0, 1)
	release := severity * .62 * authority
	v.speed += (longitudinal - v.speed) * release
}

vehicle_traction_control_factor :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> f32 {
	wheel_speed := math.abs(v.speed); road_speed := math.abs(vehicle_longitudinal_speed(v))
	if wheel_speed <= road_speed + .02 do return 1
	slip := vehicle_longitudinal_slip_ratio(v)
	return 1 - clamp((slip - .20) / .60, 0, 1) * (1 - clamp(tune.traction_control_floor, 0, 1))
}

vehicle_traction_control_drive_factor :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> f32 {
	factor := vehicle_traction_control_factor(v, tune)
	// Wheel trim can momentarily clear the slip threshold. Retain a modest part
	// of the previous torque cut so the following tick does not jump straight to
	// full power and re-spin the tire. Fresh severe slip still cuts immediately.
	if v.driver_assist == .Traction_Control {
		retained :=
			1 -
			clamp(v.driver_assist_strength, 0, 1) *
				(1 - clamp(tune.traction_control_floor, 0, 1)) *
				.24
		factor = min(factor, retained)
	}
	return factor
}

vehicle_traction_control_trim_response :: proc(tune: Vehicle_Tune) -> f32 {
	// The torque floor describes how permissive the driveline is, while this
	// response determines how decisively an already-spinning wheel is reined in.
	// Sport cars retain more wheelspin; heavy vehicles trade flair for stability.
	return clamp(
		.68 + (VEHICLE_TUNE_STANDARD.traction_control_floor - tune.traction_control_floor) * 1.4,
		.54,
		.80,
	)
}

vehicle_apply_traction_control :: proc(
	v: ^Vehicle_State,
	tune: Vehicle_Tune,
	drive_authority: f32,
) {
	authority := clamp(drive_authority, 0, 1)
	if authority <= 0 do return
	longitudinal := vehicle_longitudinal_speed(
		v^,
	); wheel_speed := math.abs(v.speed); road_speed := math.abs(longitudinal)
	if wheel_speed <= road_speed + .02 || v.speed * longitudinal < 0 do return
	intervention := 1 - vehicle_traction_control_factor(v^, tune)
	range := max(1 - clamp(tune.traction_control_floor, 0, 1), f32(.001))
	// Normalize out the torque-retention floor so severe slip can genuinely
	// recover tire budget instead of receiving only a small cosmetic correction.
	severity := clamp(intervention / range, 0, 1)
	v.speed +=
		(longitudinal - v.speed) *
		severity *
		vehicle_traction_control_trim_response(tune) *
		authority
}

vehicle_driver_assist_blended :: proc(
	v: Vehicle_State,
	tune: Vehicle_Tune,
	throttle, handbrake_amount: f32,
) -> (
	assist: Vehicle_Driver_Assist,
	strength: f32,
) {
	authority := 1 - clamp(handbrake_amount, 0, 1)
	if math.abs(throttle) <= .05 do return .None, 0
	drive_authority := vehicle_requested_drive_authority(
		v,
		throttle,
	); brake_authority := 1 - drive_authority
	// Service-brake ABS remains independent of the mechanically locked rear axle;
	// handbrake slip only gates traction-control authority.
	strength = clamp((1 - vehicle_service_brake_factor(v)) / .42, 0, 1) * brake_authority
	if strength > .005 do return .ABS, strength
	tc := vehicle_traction_control_factor(
		v,
		tune,
	); range := max(1 - tune.traction_control_floor, f32(.001)); strength = clamp((1 - tc) / range, 0, 1) * authority * drive_authority
	if strength > .005 do return .Traction_Control, strength
	return .None, 0
}
vehicle_driver_assist :: proc(
	v: Vehicle_State,
	tune: Vehicle_Tune,
	throttle: f32,
	handbrake: bool,
) -> Vehicle_Driver_Assist {if handbrake do return .None; assist, _ :=
		vehicle_driver_assist_blended(v, tune, throttle, 0)
	return assist}
vehicle_driver_assist_label :: proc(assist: Vehicle_Driver_Assist) -> string {switch
	assist {case .ABS:
		return "ABS"; case .Traction_Control:
		return "TC"; case .None:
		return ""}
	return ""}
vehicle_driver_assist_indicator_color :: proc(strength: f32) -> [4]u8 {
	amount := clamp(
		strength,
		0,
		1,
	); idle := [4]u8{145, 153, 162, 255}; active := [4]u8{255, 211, 92, 255}; result := idle
	for i in 0 ..< 3 do result[i] = u8(f32(idle[i]) + (f32(active[i]) - f32(idle[i])) * amount)
	return result
}
vehicle_driver_assist_state_step :: proc(
	current: Vehicle_Driver_Assist,
	current_strength: f32,
	detected: Vehicle_Driver_Assist,
	detected_strength: f32,
	handbrake_amount: f32 = 0,
) -> (
	assist: Vehicle_Driver_Assist,
	strength: f32,
) {
	if detected != .None {
		strength = clamp(detected_strength, 0, 1)
		if detected == current do strength = max(strength, clamp(current_strength, 0, 1) * .72)
		return detected, strength
	}
	if current == .Traction_Control && handbrake_amount > .35 do return .None, 0
	strength = clamp(current_strength, 0, 1) * .72
	if current == .None || strength < .03 do return .None, 0
	return current, strength
}
vehicle_assist_haptic_multiplier :: proc(
	assist: Vehicle_Driver_Assist,
	animation_time: f32,
) -> f32 {
	switch assist {
	case .ABS:
		return .55 + math.abs(f32(math.sin(f64(animation_time * 48)))) * .45
	case .Traction_Control:
		return .72 + math.abs(f32(math.sin(f64(animation_time * 30)))) * .28
	case .None:
		return 1
	}
	return 1
}
vehicle_assist_haptic_multiplier_blended :: proc(
	assist: Vehicle_Driver_Assist,
	strength, animation_time: f32,
) -> f32 {pulse := vehicle_assist_haptic_multiplier(assist, animation_time); return(
		1 +
		(pulse - 1) * clamp(strength, 0, 1) \
	)}

vehicle_assist_audio_gain :: proc(
	assist: Vehicle_Driver_Assist,
	strength, assist_time: f32,
) -> f32 {
	if assist == .None do return 0
	depth := 1 - vehicle_assist_haptic_multiplier(assist, assist_time)
	// Share intervention phase with haptics. ABS has a sharper hydraulic chatter;
	// TC remains a quieter driveline texture beneath its engine-load reduction.
	peak := assist == .ABS ? f32(.025) : f32(.020)
	return depth * clamp(strength, 0, 1) * peak
}

vehicle_direction_change_authority :: proc(longitudinal_speed: f32, forward: bool) -> f32 {
	opposing_speed := forward ? -longitudinal_speed : longitudinal_speed
	return 1 - clamp(max(opposing_speed, f32(0)) / .015, 0, 1)
}
vehicle_requested_drive_authority :: proc(v: Vehicle_State, throttle: f32) -> f32 {
	if math.abs(throttle) <= .001 do return 0
	forward := throttle > 0
	return min(
		vehicle_direction_change_authority(v.speed, forward),
		vehicle_direction_change_authority(vehicle_longitudinal_speed(v), forward),
	)
}

vehicle_apply_throttle_assisted :: proc(
	v: ^Vehicle_State,
	tune, driveline_tune: Vehicle_Tune,
	throttle, traction_control_amount: f32,
) {
	longitudinal := vehicle_longitudinal_speed(v^)
	if throttle > .001 {
		if v.speed <
		   0 {v.speed = min(v.speed + tune.brake * vehicle_service_brake_pressure(v^) * throttle, f32(0))} else {tc := vehicle_traction_control_drive_factor(v^, driveline_tune); assist := 1 + (tc - 1) * clamp(traction_control_amount, 0, 1); direction_authority := vehicle_direction_change_authority(longitudinal, true); v.speed = min(v.speed + vehicle_drive_torque_for_reference(tune, driveline_tune, v.speed, true) * assist * throttle * direction_authority, driveline_tune.max_forward)}
	} else if throttle < -.001 {
		if v.speed >
		   0 {v.speed = max(v.speed + tune.brake * vehicle_service_brake_pressure(v^) * throttle, f32(0))} else {tc := vehicle_traction_control_drive_factor(v^, driveline_tune); assist := 1 + (tc - 1) * clamp(traction_control_amount, 0, 1); direction_authority := vehicle_direction_change_authority(longitudinal, false); v.speed = max(v.speed + vehicle_drive_torque_for_reference(tune, driveline_tune, v.speed, false) * assist * throttle * direction_authority, -driveline_tune.max_reverse)}
	}
}
vehicle_apply_throttle_for_reference :: proc(
	v: ^Vehicle_State,
	tune, driveline_tune: Vehicle_Tune,
	throttle: f32,
	traction_control: bool = true,
) {vehicle_apply_throttle_assisted(
		v,
		tune,
		driveline_tune,
		throttle,
		traction_control ? f32(1) : f32(0),
	)}
vehicle_apply_throttle :: proc(
	v: ^Vehicle_State,
	tune: Vehicle_Tune,
	throttle: f32,
) {vehicle_apply_throttle_for_reference(v, tune, tune, throttle)}
