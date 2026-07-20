package main

import "core:math"

City_Car :: struct {
	x, y:  f32,
	model: string,
}
Vehicle_Traction_State :: enum {
	Grip,
	Slip,
	Drift,
	Lock,
	Spin,
}
Vehicle_Driver_Assist :: enum {
	None,
	ABS,
	Traction_Control,
}
Vehicle_State :: struct {
	x,
	y,
	heading:                                                                                                                                                                                                                                              f32,
	// speed is the signed driveline speed; velocity carries the car's actual
	// world-space momentum so steering and the handbrake can produce slip.
	speed,
	steering,
	velocity_x,
	velocity_y,
	yaw_rate,
	body_roll,
	body_pitch,
	handbrake_slip,
	surface_blend,
	surface_lateral_bias,
	acceleration_feedback,
	chassis_acceleration,
	chassis_lateral_acceleration,
	impact,
	impact_forward,
	impact_side,
	impact_time: f32,
	traction_state:                                                                                                                                                                                                                                             Vehicle_Traction_State,
	driver_assist:                                                                                                                                                                                                                                              Vehicle_Driver_Assist,
	driver_assist_strength,
	driver_assist_time:                                                                                                                                                                                                                 f32,
}

VEHICLE_SKID_CAPACITY :: 256
VEHICLE_SKID_LIFETIME :: f32(4)
Vehicle_Skid_Mark :: struct {
	position:               Vec2,
	heading, age, strength: f32,
	active:                 bool,
}

Vehicle_Tune :: struct {
	acceleration,
	brake,
	reverse_acceleration,
	max_forward,
	max_reverse:                                                                       f32,
	steering_response,
	steering_scale,
	yaw_response,
	longitudinal_grip,
	traction_control_floor,
	lateral_grip,
	handbrake_grip,
	coast_retention: f32,
	collision_tangent_retention,
	collision_rebound,
	chassis_compliance,
	mass:                                                                  f32,
}

City_Driving_Surface :: enum {
	Road,
	Open_Ground,
}

vehicle_tune_for_surface :: proc(
	tune: Vehicle_Tune,
	surface: City_Driving_Surface,
) -> Vehicle_Tune {
	if surface == .Road do return tune
	result := tune
	result.acceleration *= .78; result.max_forward *= .66; result.max_reverse *= .78
	result.steering_scale *= .84; result.yaw_response *= .86; result.longitudinal_grip *= .70; result.lateral_grip *= .70
	return result
}

vehicle_surface_blend_step_to :: proc(current, target_roughness: f32) -> f32 {
	target := clamp(target_roughness, 0, 1)
	// Grip loads onto rough ground progressively and recovers a little faster
	// on pavement, avoiding a one-frame coefficient jump at road boundaries.
	response := target > current ? f32(.11) : f32(.18)
	result := current + (target - current) * response
	if math.abs(result - target) < .001 do return target
	return clamp(result, 0, 1)
}
vehicle_surface_blend_step :: proc(
	current: f32,
	surface: City_Driving_Surface,
) -> f32 {return vehicle_surface_blend_step_to(current, surface == .Open_Ground ? f32(1) : f32(0))}
vehicle_surface_bias_step :: proc(current, target_bias: f32) -> f32 {
	target := clamp(
		target_bias,
		-1,
		1,
	); response := math.abs(target) > math.abs(current) ? f32(.18) : f32(.22)
	result := current + (target - current) * response
	if math.abs(result - target) < .001 do return target
	return clamp(result, -1, 1)
}

vehicle_surface_contact :: proc(v: Vehicle_State) -> (roughness, lateral_bias: f32) {
	// Sample the four tire contact regions instead of classifying the chassis
	// origin. Shoulder crossings then load each axle progressively.
	forward_x := f32(
		math.cos(f64(v.heading)),
	); forward_y := f32(math.sin(f64(v.heading))); right_x, right_y := -forward_y, forward_x
	right_rough, left_rough: f32; longitudinal_samples := [2]f32{-.78, .78}; lateral_samples := [2]f32{-.42, .42}
	for longitudinal in longitudinal_samples {
		for lateral in lateral_samples {
			x :=
				v.x +
				forward_x * longitudinal +
				right_x * lateral; y := v.y + forward_y * longitudinal + right_y * lateral
			if city_driving_surface(x, y) == .Open_Ground {if lateral > 0 do right_rough += .5
				else do left_rough += .5}
		}
	}
	return (right_rough + left_rough) * .5, right_rough - left_rough
}
vehicle_surface_roughness :: proc(v: Vehicle_State) -> f32 {roughness, _ :=
		vehicle_surface_contact(v)
	return roughness}
vehicle_surface_drag_yaw :: proc(v: Vehicle_State, throttle: f32 = 0) -> f32 {
	bias := clamp(v.surface_lateral_bias, -1, 1); longitudinal := vehicle_longitudinal_speed(v)
	if math.abs(longitudinal) < .04 do return 0
	direction :=
		longitudinal < 0 ? f32(-1) : f32(1); speed_weight := clamp((math.abs(longitudinal) - .04) / .30, 0, 1)
	brake_authority: f32
	if math.abs(throttle) > .05 do brake_authority = 1 - vehicle_requested_drive_authority(v, throttle)
	return bias * direction * speed_weight * .0016 * (1 + brake_authority * .55)
}

vehicle_tune_for_surface_blend :: proc(tune: Vehicle_Tune, roughness: f32) -> Vehicle_Tune {
	rough := vehicle_tune_for_surface(
		tune,
		.Open_Ground,
	); t := clamp(roughness, 0, 1); result := tune
	result.acceleration +=
		(rough.acceleration - tune.acceleration) *
		t; result.brake += (rough.brake - tune.brake) * t; result.reverse_acceleration += (rough.reverse_acceleration - tune.reverse_acceleration) * t
	result.max_forward +=
		(rough.max_forward - tune.max_forward) *
		t; result.max_reverse += (rough.max_reverse - tune.max_reverse) * t
	result.steering_response +=
		(rough.steering_response - tune.steering_response) *
		t; result.steering_scale += (rough.steering_scale - tune.steering_scale) * t; result.yaw_response += (rough.yaw_response - tune.yaw_response) * t
	result.longitudinal_grip +=
		(rough.longitudinal_grip - tune.longitudinal_grip) *
		t; result.traction_control_floor += (rough.traction_control_floor - tune.traction_control_floor) * t; result.lateral_grip += (rough.lateral_grip - tune.lateral_grip) * t; result.handbrake_grip += (rough.handbrake_grip - tune.handbrake_grip) * t; result.coast_retention += (rough.coast_retention - tune.coast_retention) * t
	return result
}

city_driving_surface_label :: proc(surface: City_Driving_Surface) -> string {return(
		surface == .Road ? "ROAD" : "ROUGH" \
	)}
vehicle_surface_blend_label :: proc(roughness: f32) -> string {
	amount := clamp(roughness, 0, 1)
	if amount < .20 do return "ROAD"
	if amount > .80 do return "ROUGH"
	return "MIXED"
}

vehicle_analog_curve :: proc(value: f32) -> f32 {
	shaped := clamp(value, -1, 1)
	// Retain some linear response around center, then progressively open toward
	// full lock/load. This makes small stick corrections precise without making
	// the outer range feel unresponsive.
	return shaped * (.38 + .62 * math.abs(shaped))
}

vehicle_analog_deadzone :: proc(value, deadzone: f32) -> f32 {
	clamped := clamp(value, -1, 1); magnitude := math.abs(clamped); zone := clamp(deadzone, 0, .5)
	if magnitude <= zone do return 0
	rescaled := (magnitude - zone) / (1 - zone)
	return clamped < 0 ? -rescaled : rescaled
}

vehicle_gamepad_throttle :: proc(right_trigger_raw, left_trigger_raw: f32) -> f32 {
	right_trigger := vehicle_analog_deadzone(
		right_trigger_raw,
		.04,
	); left_trigger := vehicle_analog_deadzone(left_trigger_raw, .04)
	return vehicle_analog_curve(right_trigger) - vehicle_analog_curve(left_trigger)
}

vehicle_control_inputs :: proc(g: ^Game) -> (throttle, steering: f32) {
	throttle = vehicle_gamepad_throttle(g.pad_right_trigger, g.pad_left_trigger)
	steering = vehicle_analog_curve(vehicle_analog_deadzone(g.pad_left_x, .08))
	if g.keys[.W] || g.keys[.UP] do throttle += 1
	if g.keys[.S] || g.keys[.DOWN] do throttle -= 1
	if g.keys[.A] || g.keys[.LEFT] do steering -= 1
	if g.keys[.D] || g.keys[.RIGHT] do steering += 1
	return clamp(throttle, -1, 1), clamp(steering, -1, 1)
}

vehicle_handbrake_input :: proc(g: ^Game) -> bool {return(
		g.keys[.SPACE] ||
		g.pad_buttons[.RIGHT_SHOULDER] \
	)}

Vehicle_Rear_Light_State :: enum {
	Off,
	Brake,
	Reverse,
}
vehicle_rear_light_state :: proc(
	v: Vehicle_State,
	throttle: f32,
	handbrake: bool,
) -> Vehicle_Rear_Light_State {
	if handbrake do return .Brake
	longitudinal := vehicle_longitudinal_speed(v)
	if throttle < -.05 {
		if v.speed > .015 || vehicle_direction_change_authority(longitudinal, false) < .5 do return .Brake
		return .Reverse
	}
	if throttle > .05 && (v.speed < -.015 || vehicle_direction_change_authority(longitudinal, true) < .5) do return .Brake
	return .Off
}

vehicle_rear_light_intensity :: proc(v: Vehicle_State, throttle: f32, handbrake: bool) -> f32 {
	state := vehicle_rear_light_state(v, throttle, handbrake)
	if state == .Off do return 0
	if state == .Reverse do return .55
	// Keep a readable base glow at the brake threshold, then let analog pedal
	// pressure brighten the lamps. The handbrake remains an unambiguous full cue.
	if handbrake do return .50
	return .20 + clamp(math.abs(throttle), 0, 1) * .30
}

vehicle_engine_load :: proc(v: Vehicle_State, throttle: f32) -> f32 {
	load := clamp(math.abs(throttle), 0, 1)
	if load == 0 do return 0
	// Opposing motion is predominantly braking, but retain a small engine
	// transient and grow load continuously as both wheel and chassis become ready.
	drive_authority := vehicle_requested_drive_authority(v, throttle)
	result := load * (.12 + drive_authority * .88)
	if v.driver_assist == .Traction_Control do result *= 1 - clamp(v.driver_assist_strength, 0, 1) * .28
	return result
}

VEHICLE_TUNE_STANDARD :: Vehicle_Tune {
	.012,
	.028,
	.009,
	.58,
	.22,
	.16,
	1,
	.26,
	1,
	.62,
	1,
	1,
	.989,
	.72,
	.12,
	1,
	1,
}
// The everyday sedan trades the generic arcade-like launch for a progressive
// 0-to-road-speed run. Keep its speed, braking, and handling familiar; only the
// driveline is softened so it still feels responsive once underway.
VEHICLE_TUNE_SEDAN :: Vehicle_Tune {
	.0012,
	.028,
	.003,
	.58,
	.22,
	.16,
	1,
	.26,
	1,
	.62,
	1,
	1,
	.989,
	.72,
	.12,
	1,
	1,
}
VEHICLE_TUNE_SPORT :: Vehicle_Tune {
	.015,
	.032,
	.011,
	.68,
	.24,
	.19,
	1.12,
	.32,
	1.06,
	.74,
	1.08,
	.9,
	.990,
	.68,
	.16,
	.82,
	.88,
}
VEHICLE_TUNE_UTILITY :: Vehicle_Tune {
	.010,
	.026,
	.008,
	.51,
	.20,
	.14,
	.88,
	.22,
	.92,
	.58,
	.94,
	1.05,
	.992,
	.76,
	.10,
	1.12,
	1.18,
}
VEHICLE_TUNE_HEAVY :: Vehicle_Tune {
	.008,
	.022,
	.006,
	.43,
	.17,
	.12,
	.72,
	.17,
	.84,
	.54,
	.82,
	1.14,
	.994,
	.82,
	.07,
	1.24,
	1.65,
}

vehicle_tune :: proc(index: int) -> Vehicle_Tune {
	if index < 0 || index >= len(CITY_CARS) do return VEHICLE_TUNE_STANDARD
	switch CITY_CARS[index].model {
	case "sedan":
		return VEHICLE_TUNE_SEDAN
	case "race", "sedan-sports", "hatchback-sports", "police":
		return VEHICLE_TUNE_SPORT
	case "delivery", "delivery-flat", "van", "ambulance", "suv", "suv-luxury", "taxi":
		return VEHICLE_TUNE_UTILITY
	case "truck", "truck-flat", "firetruck", "garbage-truck", "tractor":
		return VEHICLE_TUNE_HEAVY
	case:
		return VEHICLE_TUNE_STANDARD
	}
}

vehicle_actual_speed :: proc(v: Vehicle_State) -> f32 {
	return f32(math.sqrt(f64(v.velocity_x * v.velocity_x + v.velocity_y * v.velocity_y)))
}

vehicle_longitudinal_speed :: proc(v: Vehicle_State) -> f32 {return(
		v.velocity_x * f32(math.cos(f64(v.heading))) +
		v.velocity_y * f32(math.sin(f64(v.heading))) \
	)}
vehicle_direction_label :: proc(v: Vehicle_State) -> string {longitudinal :=
		vehicle_longitudinal_speed(v)
	if longitudinal < -.02 || v.speed < -.02 do return "R"
	if longitudinal > .02 || v.speed > .02 do return "D"
	return "N"}

vehicle_transmission_label :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> string {
	longitudinal := vehicle_longitudinal_speed(v)
	if math.abs(v.speed) < .015 && math.abs(longitudinal) > .02 do return "N"
	direction := vehicle_direction_label(v)
	if direction != "D" do return direction
	normalized := clamp(max(v.speed, longitudinal) / max(tune.max_forward, f32(.01)), 0, 1)
	gear, _ := vehicle_forward_gear_phase(normalized)
	switch gear {case 0:
		return "D1"; case 1:
		return "D2"; case 2:
		return "D3"; case:
		return "D4"}
	return "D1"
}

vehicle_reverse_camera_target :: proc(v: Vehicle_State, throttle, current: f32) -> f32 {
	longitudinal := vehicle_longitudinal_speed(v)
	// Follow the same progressive direction-change authority as the driveline;
	// the camera should not announce reverse before reverse torque can engage.
	if throttle < -.1 do return vehicle_direction_change_authority(longitudinal, false)
	if throttle > .1 do return 1 - vehicle_direction_change_authority(longitudinal, true)
	// With no directional command, travel hysteresis keeps the orbit stable.
	if longitudinal < -.045 do return 1
	if longitudinal > .045 do return 0
	return current
}

vehicle_lateral_slip_ratio :: proc(v: Vehicle_State) -> f32 {
	right_x := -f32(math.sin(f64(v.heading))); right_y := f32(math.cos(f64(v.heading)))
	lateral := math.abs(v.velocity_x * right_x + v.velocity_y * right_y)
	return clamp(lateral / max(vehicle_actual_speed(v), f32(.05)), 0, 1)
}

vehicle_longitudinal_slip_ratio :: proc(v: Vehicle_State) -> f32 {
	longitudinal := vehicle_longitudinal_speed(v)
	reference := max(max(math.abs(longitudinal), math.abs(v.speed)), f32(.05))
	return clamp(math.abs(v.speed - longitudinal) / reference, 0, 1)
}

vehicle_slip_ratio :: proc(v: Vehicle_State) -> f32 {return max(
		vehicle_lateral_slip_ratio(v),
		vehicle_longitudinal_slip_ratio(v) * .85,
	)}

vehicle_traction_state :: proc(v: Vehicle_State) -> Vehicle_Traction_State {
	actual_speed := vehicle_actual_speed(v); wheel_speed := math.abs(v.speed)
	if actual_speed < .08 && wheel_speed < .08 do return .Grip
	lateral := vehicle_lateral_slip_ratio(v); longitudinal := vehicle_longitudinal_slip_ratio(v)
	if lateral > .52 && actual_speed >= .08 do return .Drift
	if longitudinal > .55 {
		road_speed := math.abs(vehicle_longitudinal_speed(v))
		if wheel_speed > road_speed + .02 do return .Spin
		return .Lock
	}
	if max(lateral, longitudinal * .85) > .22 do return .Slip
	return .Grip
}

vehicle_traction_state_step :: proc(
	current: Vehicle_Traction_State,
	v: Vehicle_State,
) -> Vehicle_Traction_State {
	actual_speed := vehicle_actual_speed(
		v,
	); wheel_speed := math.abs(v.speed); lateral := vehicle_lateral_slip_ratio(v); longitudinal := vehicle_longitudinal_slip_ratio(v)
	// Entry uses the regular classifier. Lower release thresholds prevent one
	// noisy sample from flickering the HUD and tire timbre around a boundary.
	switch current {
	case .Drift:
		if actual_speed >= .07 && lateral > .44 do return .Drift
	case .Spin:
		if wheel_speed > math.abs(vehicle_longitudinal_speed(v)) + .015 && longitudinal > .45 do return .Spin
	case .Lock:
		if wheel_speed <= math.abs(vehicle_longitudinal_speed(v)) + .025 && longitudinal > .45 do return .Lock
	case .Slip:
		if max(lateral, longitudinal * .85) > .16 do return .Slip
	case .Grip:
	}
	return vehicle_traction_state(v)
}

vehicle_traction_label :: proc(state: Vehicle_Traction_State) -> string {
	switch state {case .Grip:
		return "GRIP"; case .Slip:
		return "SLIP"; case .Drift:
		return "DRIFT"; case .Lock:
		return "LOCK"; case .Spin:
		return "SPIN"}
	return "GRIP"
}

vehicle_tire_audio_frequencies :: proc(v: Vehicle_State) -> (low, high: f32) {
	return vehicle_tire_audio_frequencies_for_state(vehicle_traction_state(v))
}
vehicle_tire_audio_frequencies_for_state :: proc(
	state: Vehicle_Traction_State,
) -> (
	low, high: f32,
) {
	switch state {
	case .Lock:
		return 112, 157
	case .Spin:
		return 218, 307
	case .Drift:
		return 173, 241
	case .Slip:
		return 151, 211
	case .Grip:
		return 151, 211
	}
	return 151, 211
}

vehicle_tire_audio_frequencies_for_vehicle :: proc(
	v: Vehicle_State,
	state: Vehicle_Traction_State,
	assist: Vehicle_Driver_Assist,
	strength: f32,
) -> (
	low, high: f32,
) {
	low, high = vehicle_tire_audio_frequencies_for_state(state)
	// Pitch rises continuously with scrub severity, making the approach to a
	// traction-state boundary audible instead of relying on a discrete label swap.
	severity := clamp((vehicle_slip_ratio(v) - .16) / .84, 0, 1)
	pitch := 1 + severity * .10; low *= pitch; high *= pitch
	amount := clamp(strength, 0, 1); target_low, target_high := low, high
	switch assist {case .ABS:
		target_low, target_high = 112, 157; case .Traction_Control:
		target_low, target_high = 218, 307; case .None:
		return}
	// At full intervention retain the authored hydraulic/driveline voices exactly;
	// partial intervention blends naturally out of the current tire scrub pitch.
	low += (target_low - low) * amount; high += (target_high - high) * amount
	return
}

vehicle_tire_frequency_step :: proc(current, target: f32) -> f32 {
	if current <= 0 do return target
	return current + (target - current) * .14
}

vehicle_forward_gear_phase :: proc(normalized_speed: f32) -> (gear: int, progress: f32) {
	scaled := (clamp(normalized_speed, .06, 1) - .06) / .94 * 4
	gear = min(int(math.floor(f64(scaled))), 3); progress = clamp(scaled - f32(gear), 0, 1)
	return
}

vehicle_shift_torque_factor :: proc(normalized_speed: f32) -> f32 {
	if normalized_speed <= .06 do return 1
	gear, progress := vehicle_forward_gear_phase(normalized_speed)
	// Unload over the closing slice of each ratio, meeting the following clutch
	// recovery at the same .78 floor. This retains a readable shift without an
	// instantaneous longitudinal-force cliff at the exact boundary.
	if gear < 3 && progress > .92 do return 1 - clamp((progress - .92) / .08, 0, 1) * .22
	if gear > 0 && progress < .16 do return .78 + clamp(progress / .16, 0, 1) * .22
	return 1
}

vehicle_engine_pitch_scale :: proc(tune: Vehicle_Tune) -> f32 {
	// Preserve the standard-car voice exactly. Higher-revving, lighter tunes sit
	// above it; mass and lower road gearing give utility/heavy engines more rumble.
	return clamp(
		1 + (tune.max_forward - VEHICLE_TUNE_STANDARD.max_forward) * .35 - (tune.mass - 1) * .16,
		.84,
		1.07,
	)
}

vehicle_engine_frequency :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> f32 {
	pitch := vehicle_engine_pitch_scale(tune)
	if v.speed < 0 {
		normalized := clamp(math.abs(v.speed) / max(tune.max_reverse, f32(.01)), 0, 1)
		// Blend the reverse tonal offset in from idle; selecting a 34 Hz base at a
		// tiny negative speed otherwise produces an audible neutral-crossing pop.
		reverse_engagement := clamp(math.abs(v.speed) / .02, 0, 1)
		return (30 + reverse_engagement * 4 + normalized * 54) * pitch
	}
	normalized := clamp(v.speed / max(tune.max_forward, f32(.01)), 0, 1)
	if normalized < .06 do return (30 + normalized / .06 * 22) * pitch
	gear, progress := vehicle_forward_gear_phase(normalized)
	// Each ratio climbs through a compact band before dropping into the next.
	// The audio stream smooths the discontinuity into a restrained shift event.
	return (52 + f32(gear) * 4 + progress * 42) * pitch
}

vehicle_normalized_driveline_speed :: proc(v: Vehicle_State, tune: Vehicle_Tune) -> f32 {
	limit := v.speed < 0 ? tune.max_reverse : tune.max_forward
	return clamp(math.abs(v.speed) / max(limit, f32(.01)), 0, 1)
}

vehicle_engine_targets :: proc(
	v: Vehicle_State,
	tune: Vehicle_Tune,
	throttle: f32,
) -> (
	frequency, gain: f32,
) {
	normalized := vehicle_normalized_driveline_speed(v, tune)
	// Keep a restrained idle and let both road speed and driver load brighten it.
	frequency = vehicle_engine_frequency(v, tune)
	gain = .022 + normalized * .018 + vehicle_engine_load(v, throttle) * .028
	return
}

vehicle_tire_audio_target_blended :: proc(v: Vehicle_State, handbrake_amount: f32) -> f32 {
	speed_weight := clamp((vehicle_actual_speed(v) - .07) / .35, 0, 1)
	slip_weight := clamp((vehicle_slip_ratio(v) - .16) / .64, 0, 1)
	handbrake_weight :=
		clamp((vehicle_actual_speed(v) - .08) / .30, 0, 1) * .45 * clamp(handbrake_amount, 0, 1)
	slip_weight = max(slip_weight, handbrake_weight)
	return speed_weight * slip_weight * .042
}
vehicle_tire_audio_target :: proc(
	v: Vehicle_State,
) -> f32 {return vehicle_tire_audio_target_blended(v, 0)}

vehicle_rough_feedback_blended :: proc(v: Vehicle_State, roughness: f32) -> f32 {
	speed_weight := clamp((vehicle_actual_speed(v) - .045) / .34, 0, 1)
	return speed_weight * clamp(roughness, 0, 1)
}
vehicle_rough_feedback :: proc(
	v: Vehicle_State,
	surface: City_Driving_Surface,
) -> f32 {return vehicle_rough_feedback_blended(v, surface == .Open_Ground ? f32(1) : f32(0))}
vehicle_rough_audio_frequency :: proc(v: Vehicle_State) -> f32 {
	speed_weight := clamp((vehicle_actual_speed(v) - .045) / .34, 0, 1)
	return 24 + speed_weight * 52
}

vehicle_longitudinal_load_haptic :: proc(acceleration_feedback: f32) -> f32 {
	load := clamp(acceleration_feedback, -1, 1)
	// Braking carries slightly more low-motor weight, matching the larger visual
	// suspension travel while keeping both cues subordinate to terrain/impacts.
	return load < 0 ? -load * .11 : load * .08
}
vehicle_cornering_load_haptic :: proc(lateral_acceleration: f32) -> f32 {return(
		math.abs(clamp(lateral_acceleration, -1, 1)) *
		.06 \
	)}
vehicle_shift_haptic :: proc(v: Vehicle_State, tune: Vehicle_Tune, drive_demand: f32 = 1) -> f32 {
	demand := clamp(drive_demand, 0, 1)
	if v.speed <= 0 || v.acceleration_feedback <= 0 || demand == 0 do return 0
	normalized := clamp(v.speed / max(tune.max_forward, f32(.01)), 0, 1)
	unload := clamp((1 - vehicle_shift_torque_factor(normalized)) / .22, 0, 1)
	return unload * clamp(v.acceleration_feedback, 0, 1) * demand * .035
}
vehicle_rough_haptic :: proc(v: Vehicle_State, roughness: f32) -> f32 {
	base := vehicle_rough_feedback_blended(v, roughness)
	phase := v.x * 8.3 + v.y * 5.1 + .4
	texture := .65 + math.abs(f32(math.sin(f64(phase)))) * .35
	return base * texture * .18
}

vehicle_haptic_strengths_blended :: proc(
	v: Vehicle_State,
	roughness, handbrake_amount: f32,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
	drive_demand: f32 = 1,
) -> (
	low, high: f32,
) {
	rough := vehicle_rough_haptic(v, roughness)
	slip := clamp(vehicle_tire_audio_target_blended(v, handbrake_amount) / .042, 0, 1)
	load :=
		vehicle_longitudinal_load_haptic(v.acceleration_feedback) +
		vehicle_shift_haptic(v, tune, drive_demand)
	cornering := vehicle_cornering_load_haptic(v.chassis_lateral_acceleration)
	// Body motor carries road texture, longitudinal load, and collision weight;
	// the faster motor communicates tire scrub. Impacts briefly dominate both.
	low = clamp(max(max(max(rough, load), cornering), v.impact * .90), 0, 1)
	high = clamp(max(slip * .25, v.impact * .48), 0, 1)
	return
}
vehicle_haptic_strengths :: proc(
	v: Vehicle_State,
	roughness: f32,
	handbrake: bool,
	tune: Vehicle_Tune = VEHICLE_TUNE_STANDARD,
	drive_demand: f32 = 1,
) -> (
	low, high: f32,
) {return vehicle_haptic_strengths_blended(
		v,
		roughness,
		handbrake ? f32(1) : f32(0),
		tune,
		drive_demand,
	)}
vehicle_assisted_high_haptic :: proc(
	v: Vehicle_State,
	high: f32,
	assist: Vehicle_Driver_Assist,
	strength, animation_time: f32,
) -> f32 {
	amount := clamp(
		strength,
		0,
		1,
	); multiplier := vehicle_assist_haptic_multiplier_blended(assist, amount, animation_time); modulated := high * multiplier
	// A correction can remove the slip rumble it was modulating. Keep a subtle
	// intervention pulse floor so successful ABS/TC remains tactile instead of
	// disappearing precisely when wheel grip is restored.
	intervention :=
		assist == .None ? f32(0) : (1 - vehicle_assist_haptic_multiplier(assist, animation_time)) * .09 * amount
	// Assist pulses belong to tire feedback; never attenuate a simultaneous
	// collision event, which must remain the dominant high-motor cue.
	return max(max(modulated, intervention), clamp(v.impact, 0, 1) * .48)
}

vehicle_impact_audio_parameters :: proc(impact: f32) -> (frequency, gain, duration: f32) {
	strength := clamp(impact, 0, 1)
	frequency = 92 - strength * 34; gain = .035 + strength * .13; duration = .055 + strength * .105
	return
}
vehicle_impact_audio_ready :: proc(impact, cooldown: f32) -> bool {return(
		impact > .12 &&
		cooldown <= 0 \
	)}

vehicle_skid_strength_surface_blended :: proc(
	v: Vehicle_State,
	handbrake_amount, roughness: f32,
) -> f32 {
	speed_weight := clamp((vehicle_actual_speed(v) - .10) / .34, 0, 1)
	traction := max(vehicle_slip_ratio(v), .52 * clamp(handbrake_amount, 0, 1))
	road_weight := 1 - clamp(roughness, 0, 1)
	return speed_weight * clamp((traction - .18) / .62, 0, 1) * road_weight
}
vehicle_skid_strength_blended :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
	surface: City_Driving_Surface,
) -> f32 {return vehicle_skid_strength_surface_blended(
		v,
		handbrake_amount,
		surface == .Open_Ground ? f32(1) : f32(0),
	)}
vehicle_skid_strength :: proc(
	v: Vehicle_State,
	handbrake: bool,
	surface: City_Driving_Surface,
) -> f32 {return vehicle_skid_strength_blended(v, handbrake ? f32(1) : f32(0), surface)}
vehicle_front_skid_weight_for_state :: proc(
	state: Vehicle_Traction_State,
	handbrake_amount: f32,
) -> f32 {
	if handbrake_amount > .35 do return 0
	return state == .Lock ? f32(.82) : f32(0)
}
vehicle_front_skid_weight :: proc(
	v: Vehicle_State,
	handbrake_amount: f32,
) -> f32 {return vehicle_front_skid_weight_for_state(vehicle_traction_state(v), handbrake_amount)}
