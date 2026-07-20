package main

import "core:math"

run_vehicle_self_tests :: proc() {
	furniture_game := new(
		Game,
	); defer free(furniture_game); initialize_city_vehicles(furniture_game); initialize_city_furniture(furniture_game); assert(len(furniture_game.city_furniture) >= 36); for prop in furniture_game.city_furniture {template := city_furniture_template(prop.kind); assert(template.radius > 0 && template.mass > 0 && !city_wall(prop.x, prop.y))}; impact_prop := furniture_game.city_furniture[0]; delete(furniture_game.city_furniture); furniture_game.city_furniture = make([dynamic]City_Furniture_State, 1, 1); furniture_game.city_furniture[0] = impact_prop; furniture_game.city_furniture[0].x = 10; furniture_game.city_furniture[0].y = 2; furniture_game.vehicles[0] = {
		x          = 8.8,
		y          = 2,
		heading    = 0,
		speed      = .55,
		velocity_x = .55,
	}; assert(
		vehicle_swept_move(furniture_game, &furniture_game.vehicles[0], 0, true),
	); assert(furniture_game.city_furniture[0].velocity_x > 0 && furniture_game.vehicles[0].velocity_x < f32(.55)); prop_x_before := furniture_game.city_furniture[0].x; update_city_furniture(furniture_game); assert(furniture_game.city_furniture[0].x > prop_x_before)
	vehicle_test_game := new(
		Game,
	); defer free(vehicle_test_game); vehicle_test_game.driving_vehicle = -1; vehicle_test_game.near_vehicle = -1; initialize_city_vehicles(vehicle_test_game); assert(city_car_at(vehicle_test_game, city_world(CITY_CARS[0].x), city_world(CITY_CARS[0].y))); assert(!city_car_at(vehicle_test_game, city_world(10.5), city_world(10.5)))
	drive_test := new(
		Game,
	); defer free(drive_test); drive_test.screen = .Exterior; drive_test.city_x = city_world(CITY_CARS[0].x); drive_test.city_y = city_world(CITY_CARS[0].y) - 1.2; drive_test.city_angle = f32(math.PI / 2); drive_test.driving_vehicle = -1; drive_test.near_vehicle = -1; drive_test.input.vehicle_action = true; initialize_city_vehicles(drive_test); update_city(drive_test); assert(drive_test.driving_vehicle == 0); drive_test.input = {}; drive_test.keys[.W] = true; old_vehicle_y := drive_test.vehicles[0].y; for _ in 0 ..< 12 do update_city(drive_test); assert(drive_test.vehicles[0].speed > 0 && drive_test.vehicles[0].y > old_vehicle_y)
	// Turning retains some of the pre-turn world velocity; pulling the
	// handbrake retains considerably more and therefore produces real slip.
	normal_turn := new(
		Game,
	); defer free(normal_turn); normal_turn.screen = .Exterior; normal_turn.driving_vehicle = 0; normal_turn.near_vehicle = -1; initialize_city_vehicles(normal_turn); normal_turn.vehicles[0].x = city_world(17.4); normal_turn.vehicles[0].y = city_world(34); normal_turn.vehicles[0].heading = f32(math.PI / 2); normal_turn.vehicles[0].speed = .42; normal_turn.vehicles[0].velocity_y = .42; normal_turn.keys[.D] = true; for _ in 0 ..< 10 do update_city(normal_turn); normal_lateral := math.abs(normal_turn.vehicles[0].velocity_x)
	handbrake_turn := new(
		Game,
	); defer free(handbrake_turn); handbrake_turn.screen = .Exterior; handbrake_turn.driving_vehicle = 0; handbrake_turn.near_vehicle = -1; initialize_city_vehicles(handbrake_turn); handbrake_turn.vehicles[0].x = city_world(17.4); handbrake_turn.vehicles[0].y = city_world(34); handbrake_turn.vehicles[0].heading = f32(math.PI / 2); handbrake_turn.vehicles[0].speed = .42; handbrake_turn.vehicles[0].velocity_y = .42; handbrake_turn.keys[.D] = true; handbrake_turn.keys[.SPACE] = true; for _ in 0 ..< 10 do update_city(handbrake_turn); assert(math.abs(handbrake_turn.vehicles[0].velocity_x) < normal_lateral)
	// Forward and side forces are independent: normal tires scrub side slip,
	// while the handbrake retains it. Camera framing also expands with speed.
	normal_grip := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .2,
		velocity_y = .3,
	}; handbrake_grip :=
		normal_grip; vehicle_apply_tire_grip(&normal_grip, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&handbrake_grip, true, VEHICLE_TUNE_STANDARD); assert(math.abs(normal_grip.velocity_y) < math.abs(handbrake_grip.velocity_y)); assert(normal_grip.velocity_x > f32(.2) && handbrake_grip.velocity_x > f32(.2))
	feedback_independent_grip_a := Vehicle_State {
		heading              = 0,
		speed                = .3,
		velocity_x           = .3,
		velocity_y           = .2,
		chassis_acceleration = -1,
	}; feedback_independent_grip_b :=
		feedback_independent_grip_a; feedback_independent_grip_b.chassis_acceleration = 1; vehicle_apply_tire_grip(&feedback_independent_grip_a, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&feedback_independent_grip_b, false, VEHICLE_TUNE_STANDARD); assert(feedback_independent_grip_a.velocity_x == feedback_independent_grip_b.velocity_x && feedback_independent_grip_a.velocity_y == feedback_independent_grip_b.velocity_y)
	engaged_slip := vehicle_handbrake_slip_step(
		0,
		true,
	); released_slip := vehicle_handbrake_slip_step(1, false); assert(engaged_slip > 0 && engaged_slip < 1 && released_slip > 0 && released_slip < 1 && engaged_slip > 1 - released_slip); slip_progress := f32(0); for _ in 0 ..< 24 do slip_progress = vehicle_handbrake_slip_step(slip_progress, true); assert(slip_progress > .99); first_release := vehicle_handbrake_slip_step(slip_progress, false); for _ in 0 ..< 80 do slip_progress = vehicle_handbrake_slip_step(slip_progress, false); assert(first_release > slip_progress && slip_progress == 0); blended_grip := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .2,
		velocity_y = .3,
	}; vehicle_apply_tire_grip_blended(
		&blended_grip,
		.5,
		VEHICLE_TUNE_STANDARD,
	); assert(math.abs(blended_grip.velocity_y) > math.abs(normal_grip.velocity_y) && math.abs(blended_grip.velocity_y) < math.abs(handbrake_grip.velocity_y))
	sport_slip_release := vehicle_handbrake_slip_step_tuned(
		1,
		false,
		VEHICLE_TUNE_SPORT,
	); standard_slip_release := vehicle_handbrake_slip_step_tuned(1, false, VEHICLE_TUNE_STANDARD); heavy_slip_release := vehicle_handbrake_slip_step_tuned(1, false, VEHICLE_TUNE_HEAVY); assert(sport_slip_release < standard_slip_release && standard_slip_release < heavy_slip_release && vehicle_handbrake_slip_step_tuned(0, true, VEHICLE_TUNE_SPORT) == vehicle_handbrake_slip_step_tuned(0, true, VEHICLE_TUNE_HEAVY))
	road_braking_grip := Vehicle_State {
		heading    = 0,
		speed      = 0,
		velocity_x = .4,
	}; rough_braking_grip :=
		road_braking_grip; heavy_braking_grip := road_braking_grip; vehicle_apply_tire_grip(&road_braking_grip, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&rough_braking_grip, false, vehicle_tune_for_surface(VEHICLE_TUNE_STANDARD, .Open_Ground)); vehicle_apply_tire_grip(&heavy_braking_grip, false, VEHICLE_TUNE_HEAVY); assert(math.abs(road_braking_grip.velocity_x) < math.abs(rough_braking_grip.velocity_x) && math.abs(road_braking_grip.velocity_x) < math.abs(heavy_braking_grip.velocity_x)); assert(VEHICLE_TUNE_SPORT.longitudinal_grip > VEHICLE_TUNE_STANDARD.longitudinal_grip && VEHICLE_TUNE_HEAVY.longitudinal_grip < VEHICLE_TUNE_STANDARD.longitudinal_grip)
	assert(
		!vehicle_should_settle_velocity(Vehicle_State{speed = 0, velocity_x = .3}) &&
		vehicle_should_settle_velocity(Vehicle_State{speed = 0, velocity_x = .01}) &&
		!vehicle_should_settle_velocity(Vehicle_State{speed = .01, velocity_x = 0}),
	)
	assert(
		vehicle_combined_grip_factor(0) == 1 &&
		math.abs(vehicle_combined_grip_factor(.075) - .66) < .0001 &&
		math.abs(vehicle_combined_grip_factor(1) - .66) < .0001 &&
		vehicle_combined_grip_factor(.03) > vehicle_combined_grip_factor(.06),
	); coasting_corner := Vehicle_State {
		heading    = 0,
		speed      = .2,
		velocity_x = .2,
		velocity_y = .2,
	}; loaded_corner :=
		coasting_corner; loaded_corner.speed = .42; vehicle_apply_tire_grip(&coasting_corner, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&loaded_corner, false, VEHICLE_TUNE_STANDARD); assert(math.abs(loaded_corner.velocity_y) > math.abs(coasting_corner.velocity_y)); handbrake_budget := Vehicle_State {
		heading    = 0,
		speed      = .42,
		velocity_x = .2,
		velocity_y = .2,
	}; vehicle_apply_tire_grip(
		&handbrake_budget,
		true,
		VEHICLE_TUNE_STANDARD,
	); assert(math.abs(handbrake_budget.velocity_y) > math.abs(loaded_corner.velocity_y))
	normal_longitudinal_response := vehicle_longitudinal_grip_response(
		0,
		VEHICLE_TUNE_STANDARD,
	); half_longitudinal_response := vehicle_longitudinal_grip_response(.5, VEHICLE_TUNE_STANDARD); loose_longitudinal_response := vehicle_longitudinal_grip_response(1, VEHICLE_TUNE_STANDARD); assert(normal_longitudinal_response > half_longitudinal_response && half_longitudinal_response > loose_longitudinal_response && math.abs(half_longitudinal_response - (normal_longitudinal_response + loose_longitudinal_response) * .5) < .0001)
	gripping := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; slipping := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
		velocity_y = .12,
	}; drifting := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .2,
		velocity_y = .35,
	}; assert(
		vehicle_traction_state(gripping) == .Grip &&
		vehicle_traction_state(slipping) == .Slip &&
		vehicle_traction_state(drifting) == .Drift,
	); assert(vehicle_slip_ratio(gripping) == 0 && vehicle_lateral_slip_ratio(gripping) == 0 && vehicle_longitudinal_slip_ratio(gripping) == 0 && vehicle_slip_ratio(drifting) > vehicle_slip_ratio(slipping)); assert(vehicle_traction_label(.Drift) == "DRIFT" && vehicle_traction_label(.Lock) == "LOCK" && vehicle_traction_label(.Spin) == "SPIN"); locked_wheels := Vehicle_State {
		heading    = 0,
		speed      = 0,
		velocity_x = .3,
	}; spinning_wheels := Vehicle_State {
		heading    = 0,
		speed      = .3,
		velocity_x = 0,
	}; assert(
		vehicle_longitudinal_slip_ratio(locked_wheels) == 1 &&
		vehicle_longitudinal_slip_ratio(spinning_wheels) == 1 &&
		vehicle_slip_ratio(locked_wheels) == .85 &&
		vehicle_traction_state(locked_wheels) == .Lock &&
		vehicle_traction_state(spinning_wheels) == .Spin,
	); drift_with_wheel_mismatch := drifting; drift_with_wheel_mismatch.speed = .6; assert(vehicle_traction_state(drift_with_wheel_mismatch) == .Drift)
	drift_release_probe := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .35,
		velocity_y = .18,
	}; assert(
		vehicle_traction_state(drift_release_probe) != .Drift &&
		vehicle_traction_state_step(.Drift, drift_release_probe) == .Drift,
	); settled_drift_probe := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .39,
		velocity_y = .05,
	}; assert(
		vehicle_traction_state_step(.Drift, settled_drift_probe) != .Drift &&
		vehicle_traction_state_step(
			.Slip,
			Vehicle_State{heading = 0, speed = .4, velocity_x = .39, velocity_y = .08},
		) ==
			.Slip,
	)
	lock_tire_low, lock_tire_high := vehicle_tire_audio_frequencies(
		locked_wheels,
	); drift_tire_low, drift_tire_high := vehicle_tire_audio_frequencies(drifting); spin_tire_low, spin_tire_high := vehicle_tire_audio_frequencies(spinning_wheels); assert(lock_tire_low < drift_tire_low && lock_tire_high < drift_tire_high && spin_tire_low > drift_tire_low && spin_tire_high > drift_tire_high && lock_tire_low >= 100 && spin_tire_high <= 320)
	assert(
		vehicle_tire_frequency_step(0, 173) == 173,
	); tire_pitch_step := vehicle_tire_frequency_step(151, 173); assert(tire_pitch_step > 151 && tire_pitch_step < 173); for _ in 0 ..< 80 do tire_pitch_step = vehicle_tire_frequency_step(tire_pitch_step, 173); assert(math.abs(tire_pitch_step - 173) < .001)
	abs_feedback_low, abs_feedback_high := vehicle_tire_audio_frequencies_for_vehicle(
		{},
		.Grip,
		.ABS,
		1,
	); tc_feedback_low, tc_feedback_high := vehicle_tire_audio_frequencies_for_vehicle({}, .Grip, .Traction_Control, 1); half_abs_feedback_low, half_abs_feedback_high := vehicle_tire_audio_frequencies_for_vehicle({}, .Grip, .ABS, .5); no_assist_feedback_low, no_assist_feedback_high := vehicle_tire_audio_frequencies_for_vehicle({}, .Grip, .None, 1); assert(abs_feedback_low == 112 && abs_feedback_high == 157 && tc_feedback_low == 218 && tc_feedback_high == 307 && half_abs_feedback_low > abs_feedback_low && half_abs_feedback_low < no_assist_feedback_low && half_abs_feedback_high > abs_feedback_high && half_abs_feedback_high < no_assist_feedback_high && no_assist_feedback_low == 151 && no_assist_feedback_high == 211)
	grip_severity_low, grip_severity_high := vehicle_tire_audio_frequencies_for_vehicle(
		gripping,
		.Grip,
		.None,
		0,
	); slip_severity_low, slip_severity_high := vehicle_tire_audio_frequencies_for_vehicle(slipping, .Grip, .None, 0); full_abs_severity_low, full_abs_severity_high := vehicle_tire_audio_frequencies_for_vehicle(locked_wheels, .Lock, .ABS, 1); half_abs_severity_low, _ := vehicle_tire_audio_frequencies_for_vehicle(locked_wheels, .Lock, .ABS, .5); assert(grip_severity_low == 151 && grip_severity_high == 211 && slip_severity_low > grip_severity_low && slip_severity_high > grip_severity_high && full_abs_severity_low == 112 && full_abs_severity_high == 157 && half_abs_severity_low > full_abs_severity_low)
	assert(
		vehicle_tire_audio_target(gripping) == 0 &&
		vehicle_tire_audio_target(drifting) > vehicle_tire_audio_target(slipping) &&
		vehicle_tire_audio_target(Vehicle_State{velocity_y = .04}) == 0 &&
		vehicle_tire_audio_target(drifting) <= .042,
	)
	full_handbrake_audio := vehicle_tire_audio_target_blended(
		gripping,
		1,
	); half_handbrake_audio := vehicle_tire_audio_target_blended(gripping, .5); assert(full_handbrake_audio > half_handbrake_audio && half_handbrake_audio > vehicle_tire_audio_target_blended(gripping, 0) && full_handbrake_audio <= .042)
	assert(
		vehicle_rough_feedback(gripping, .Road) == 0 &&
		vehicle_rough_feedback(Vehicle_State{velocity_x = .04}, .Open_Ground) == 0 &&
		vehicle_rough_feedback(gripping, .Open_Ground) > 0 &&
		vehicle_rough_feedback(Vehicle_State{velocity_x = 1}, .Open_Ground) == 1,
	); half_rough_feedback := vehicle_rough_feedback_blended(gripping, .5); assert(half_rough_feedback > 0 && math.abs(half_rough_feedback * 2 - vehicle_rough_feedback_blended(gripping, 1)) < .0001); rough_camera := gripping; rough_camera.surface_blend = 1; half_rough_camera := rough_camera; half_rough_camera.surface_blend = .5; shifted_rough_jolt_camera := rough_camera; shifted_rough_jolt_camera.x = .3; assert(vehicle_camera_rough_jolt(gripping) == 0 && math.abs(vehicle_camera_rough_jolt(rough_camera)) <= .018 && math.abs(vehicle_camera_rough_jolt(half_rough_camera)) < math.abs(vehicle_camera_rough_jolt(rough_camera)) && vehicle_camera_rough_jolt(shifted_rough_jolt_camera) != vehicle_camera_rough_jolt(rough_camera))
	assert(
		vehicle_rough_audio_frequency(Vehicle_State{}) == 24 &&
		vehicle_rough_audio_frequency(Vehicle_State{velocity_x = .2}) > 24 &&
		vehicle_rough_audio_frequency(Vehicle_State{velocity_x = .4}) == 76 &&
		vehicle_rough_audio_frequency(Vehicle_State{velocity_x = -.4}) == 76,
	)
	rough_body_roll, rough_body_pitch := vehicle_rough_body_pose(
		rough_camera,
	); half_rough_body_roll, half_rough_body_pitch := vehicle_rough_body_pose(half_rough_camera); road_body_roll, road_body_pitch := vehicle_rough_body_pose(gripping); shifted_rough_camera := rough_camera; shifted_rough_camera.x = .3; shifted_roll, shifted_pitch := vehicle_rough_body_pose(shifted_rough_camera); assert(math.abs(rough_body_roll) <= .006 && math.abs(rough_body_pitch) <= .010 && math.abs(half_rough_body_roll) < math.abs(rough_body_roll) && math.abs(half_rough_body_pitch) < math.abs(rough_body_pitch) && road_body_roll == 0 && road_body_pitch == 0 && (shifted_roll != rough_body_roll || shifted_pitch != rough_body_pitch))
	idle_low, idle_high := vehicle_haptic_strengths(
		Vehicle_State{},
		0,
		false,
	); rough_low, rough_high := vehicle_haptic_strengths(gripping, 1, false); half_rough_low, _ := vehicle_haptic_strengths(gripping, .5, false); shifted_haptic_car := gripping; shifted_haptic_car.x = .2; shifted_rough_low, _ := vehicle_haptic_strengths(shifted_haptic_car, 1, false); slip_low, slip_high := vehicle_haptic_strengths(drifting, 0, false); impact_low, impact_high := vehicle_haptic_strengths(Vehicle_State{impact = 1}, 0, false); handbrake_low, handbrake_high := vehicle_haptic_strengths(gripping, 0, true); assert(idle_low == 0 && idle_high == 0 && rough_low > 0 && half_rough_low > 0 && half_rough_low < rough_low && shifted_rough_low != rough_low && rough_high == 0 && slip_low == 0 && slip_high > 0 && impact_low == .9 && impact_high == .48 && handbrake_low == 0 && handbrake_high > 0); assert(rough_low <= .18 && shifted_rough_low <= .18 && slip_high <= .25 && impact_low <= 1 && impact_high <= 1)
	assert(
		vehicle_longitudinal_load_haptic(1) == .08 &&
		vehicle_longitudinal_load_haptic(-1) == .11 &&
		vehicle_longitudinal_load_haptic(2) == .08 &&
		vehicle_longitudinal_load_haptic(-2) == .11,
	); launch_load_low, _ := vehicle_haptic_strengths(Vehicle_State{acceleration_feedback = .7}, 0, false); brake_load_low, _ := vehicle_haptic_strengths(Vehicle_State{acceleration_feedback = -1}, 0, false); loaded_impact_low, loaded_impact_high := vehicle_haptic_strengths(Vehicle_State{acceleration_feedback = 1, impact = 1}, 0, false); assert(launch_load_low > .05 && launch_load_low < brake_load_low && brake_load_low == .11 && loaded_impact_low == .9 && loaded_impact_high == .48)
	shift_haptic_speed :=
		VEHICLE_TUNE_STANDARD.max_forward * f32(.06 + .94 / 4); shift_haptic_car := Vehicle_State {
		speed                 = shift_haptic_speed,
		acceleration_feedback = 1,
	}; between_shift_car := Vehicle_State {
		speed                 = VEHICLE_TUNE_STANDARD.max_forward * .18,
		acceleration_feedback = 1,
	}; shift_load_low, _ := vehicle_haptic_strengths(
		shift_haptic_car,
		0,
		false,
	); between_shift_low, _ := vehicle_haptic_strengths(between_shift_car, 0, false); assert(vehicle_shift_haptic(shift_haptic_car, VEHICLE_TUNE_STANDARD) > 0 && vehicle_shift_haptic(shift_haptic_car, VEHICLE_TUNE_STANDARD, 0) == 0 && vehicle_shift_haptic(shift_haptic_car, VEHICLE_TUNE_STANDARD, .5) < vehicle_shift_haptic(shift_haptic_car, VEHICLE_TUNE_STANDARD) && vehicle_shift_haptic(between_shift_car, VEHICLE_TUNE_STANDARD) == 0 && shift_load_low > between_shift_low && vehicle_shift_haptic(Vehicle_State{speed = -shift_haptic_speed, acceleration_feedback = 1}, VEHICLE_TUNE_STANDARD) == 0)
	corner_load_low, _ := vehicle_haptic_strengths(
		Vehicle_State{chassis_lateral_acceleration = 1},
		0,
		false,
	); assert(vehicle_cornering_load_haptic(1) == .06 && vehicle_cornering_load_haptic(-1) == .06 && corner_load_low == .06)
	_, half_handbrake_high := vehicle_haptic_strengths_blended(
		gripping,
		0,
		.5,
	); assert(half_handbrake_high > 0 && half_handbrake_high < handbrake_high)
	soft_frequency, soft_gain, soft_duration := vehicle_impact_audio_parameters(
		.2,
	); hard_frequency, hard_gain, hard_duration := vehicle_impact_audio_parameters(1); assert(hard_frequency < soft_frequency && hard_gain > soft_gain && hard_duration > soft_duration && hard_gain <= .165 && hard_duration <= .16); assert(vehicle_impact_audio_ready(.2, 0) && !vehicle_impact_audio_ready(.1, 0) && !vehicle_impact_audio_ready(1, .01))
	skidding_vehicle := Vehicle_State {
		x          = 20,
		y          = 2,
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; assert(
		vehicle_skid_strength(skidding_vehicle, true, .Road) > 0 &&
		vehicle_skid_strength(skidding_vehicle, false, .Road) == 0 &&
		vehicle_skid_strength(skidding_vehicle, true, .Open_Ground) == 0 &&
		vehicle_skid_strength(locked_wheels, false, .Road) > 0 &&
		vehicle_tire_audio_target(locked_wheels) > 0,
	); assert(vehicle_skid_heading(skidding_vehicle) == 0 && vehicle_skid_heading(Vehicle_State{heading = .7}) == .7 && vehicle_skid_heading(Vehicle_State{heading = 0, velocity_x = .2, velocity_y = .2}) > 0); skid_game := new(Game); defer free(skid_game); skid_game.vehicle_skid_emit_distance = .72; vehicle_update_skid_marks(skid_game, skidding_vehicle, true, .Road); assert(skid_game.vehicle_skid_next == 2 && skid_game.vehicle_skid_marks[0].active && skid_game.vehicle_skid_marks[1].active && skid_game.vehicle_skid_marks[0].position.y != skid_game.vehicle_skid_marks[1].position.y && math.abs(skid_game.vehicle_skid_emit_distance - .4) < .0001 && math.abs(skid_game.vehicle_skid_marks[0].position.x - 18.88) < .0001); blocked_skid_game := new(Game); defer free(blocked_skid_game); blocked_skid_game.vehicle_skid_emit_distance = .7; vehicle_update_skid_marks_blended(blocked_skid_game, skidding_vehicle, 1, 0, {}, true); assert(blocked_skid_game.vehicle_skid_emit_distance == .7 && blocked_skid_game.vehicle_skid_next == 0); drift_mark_vehicle := Vehicle_State {
		x          = 20,
		y          = 2,
		heading    = 0,
		speed      = .4,
		velocity_x = .2,
		velocity_y = .3,
	}; skid_game.vehicle_skid_emit_distance = .72; vehicle_update_skid_marks(skid_game, drift_mark_vehicle, true, .Road); assert(skid_game.vehicle_skid_marks[2].heading > drift_mark_vehicle.heading && skid_game.vehicle_skid_marks[2].heading == skid_game.vehicle_skid_marks[3].heading); skid_game.vehicle_skid_emit_distance = 2; vehicle_update_skid_marks(skid_game, skidding_vehicle, true, .Road); assert(skid_game.vehicle_skid_emit_distance == .71); skid_game.vehicle_skid_marks[0].age = VEHICLE_SKID_LIFETIME - FIXED_TIMESTEP * .5; vehicle_age_skid_marks(skid_game); assert(!skid_game.vehicle_skid_marks[0].active)
	path_skid_game := new(
		Game,
	); defer free(path_skid_game); path_skid_game.vehicle_skid_emit_distance = .6; vehicle_update_skid_marks_blended(path_skid_game, skidding_vehicle, 1, 0, {.1, 0}, true, .2); assert(path_skid_game.vehicle_skid_next == 2 && math.abs(path_skid_game.vehicle_skid_marks[0].position.x - 19.20) < .0001)
	assert(
		vehicle_skid_pending_distance_step(.6, 0) == 0 &&
		math.abs(vehicle_skid_pending_distance_step(.6, .05) - .39) < .0001 &&
		vehicle_skid_pending_distance_step(.01, .05) == 0,
	); marginal_skid_game := new(Game); defer free(marginal_skid_game); marginal_skid_game.vehicle_skid_emit_distance = .6; marginal_skid := Vehicle_State {
		speed      = .2,
		velocity_x = .2,
		velocity_y = .06,
	}; marginal_strength := vehicle_skid_strength_surface_blended(
		marginal_skid,
		0,
		0,
	); assert(marginal_strength > .02 && marginal_strength <= .08); vehicle_update_skid_marks_blended(marginal_skid_game, marginal_skid, 0, 0, {.1, 0}, true, .1); assert(marginal_skid_game.vehicle_skid_emit_distance > 0 && marginal_skid_game.vehicle_skid_emit_distance < .6 && marginal_skid_game.vehicle_skid_next == 0)
	half_skid_strength := vehicle_skid_strength_blended(
		skidding_vehicle,
		.5,
		.Road,
	); assert(half_skid_strength > 0 && half_skid_strength < vehicle_skid_strength_blended(skidding_vehicle, 1, .Road))
	transition_skid_strength := vehicle_skid_strength_surface_blended(
		skidding_vehicle,
		1,
		.5,
	); assert(transition_skid_strength > 0 && transition_skid_strength < vehicle_skid_strength_surface_blended(skidding_vehicle, 1, 0) && vehicle_skid_strength_surface_blended(skidding_vehicle, 1, 1) == 0)
	assert(
		vehicle_front_skid_weight(locked_wheels, 0) > 0 &&
		vehicle_front_skid_weight(locked_wheels, 1) == 0 &&
		vehicle_front_skid_weight(drifting, 0) == 0,
	)
	assert(
		vehicle_front_skid_weight_for_state(.Lock, 0) > .8 &&
		vehicle_front_skid_weight_for_state(.Lock, .5) == 0 &&
		vehicle_front_skid_weight_for_state(.Slip, 0) == 0,
	)
	idle_frequency, idle_gain := vehicle_engine_targets(
		Vehicle_State{},
		VEHICLE_TUNE_STANDARD,
		0,
	); cruise_frequency, cruise_gain := vehicle_engine_targets(Vehicle_State{speed = .4}, VEHICLE_TUNE_STANDARD, 0); loaded_frequency, loaded_gain := vehicle_engine_targets(Vehicle_State{speed = .4}, VEHICLE_TUNE_STANDARD, 1); _, braking_gain := vehicle_engine_targets(Vehicle_State{speed = .4}, VEHICLE_TUNE_STANDARD, -1); residual_brake_load := vehicle_engine_load(Vehicle_State{velocity_x = .01}, -1); near_stop_reverse_load := vehicle_engine_load(Vehicle_State{velocity_x = .001}, -1); assert(cruise_frequency > idle_frequency && cruise_gain > idle_gain && loaded_frequency == cruise_frequency && loaded_gain > cruise_gain && braking_gain > cruise_gain && braking_gain < loaded_gain && residual_brake_load > .12 && near_stop_reverse_load > residual_brake_load && near_stop_reverse_load < 1); assert(vehicle_engine_load(Vehicle_State{speed = -.2}, 1) < vehicle_engine_load(Vehicle_State{speed = -.2}, -1) && vehicle_engine_load(Vehicle_State{}, 0) == 0)
	tc_engine := Vehicle_State {
		speed                  = .3,
		velocity_x             = .3,
		driver_assist          = .Traction_Control,
		driver_assist_strength = 1,
	}; half_tc_engine :=
		tc_engine; half_tc_engine.driver_assist_strength = .5; abs_engine := tc_engine; abs_engine.driver_assist = .ABS; assert(vehicle_engine_load(tc_engine, 1) < vehicle_engine_load(half_tc_engine, 1) && vehicle_engine_load(half_tc_engine, 1) < vehicle_engine_load(abs_engine, 1) && math.abs(vehicle_engine_load(tc_engine, 1) - .72) < .0001)
	first_gear_low := vehicle_engine_frequency(
		Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward * .15},
		VEHICLE_TUNE_STANDARD,
	); first_gear_high := vehicle_engine_frequency(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward * .28}, VEHICLE_TUNE_STANDARD); second_gear_start := vehicle_engine_frequency(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward * .30}, VEHICLE_TUNE_STANDARD); reverse_pitch := vehicle_engine_frequency(Vehicle_State{speed = -VEHICLE_TUNE_STANDARD.max_reverse}, VEHICLE_TUNE_STANDARD); near_neutral_forward_pitch := vehicle_engine_frequency(Vehicle_State{speed = .001}, VEHICLE_TUNE_STANDARD); near_neutral_reverse_pitch := vehicle_engine_frequency(Vehicle_State{speed = -.001}, VEHICLE_TUNE_STANDARD); assert(idle_frequency == 30 && first_gear_high > first_gear_low && second_gear_start < first_gear_high && reverse_pitch > idle_frequency && reverse_pitch < first_gear_high && near_neutral_reverse_pitch > idle_frequency && math.abs(near_neutral_reverse_pitch - near_neutral_forward_pitch) < 1); for step in 0 ..= 100 {sample_speed := VEHICLE_TUNE_STANDARD.max_forward * f32(step) / 100; sample_frequency := vehicle_engine_frequency(Vehicle_State{speed = sample_speed}, VEHICLE_TUNE_STANDARD); assert(sample_frequency >= 30 && sample_frequency <= 106)}
	assert(
		vehicle_engine_pitch_scale(VEHICLE_TUNE_STANDARD) == 1 &&
		vehicle_engine_pitch_scale(VEHICLE_TUNE_SPORT) > 1 &&
		vehicle_engine_pitch_scale(VEHICLE_TUNE_UTILITY) < 1 &&
		vehicle_engine_pitch_scale(VEHICLE_TUNE_HEAVY) <
			vehicle_engine_pitch_scale(VEHICLE_TUNE_UTILITY),
	); sport_engine_pitch := vehicle_engine_frequency(Vehicle_State{speed = VEHICLE_TUNE_SPORT.max_forward * .5}, VEHICLE_TUNE_SPORT); standard_engine_pitch := vehicle_engine_frequency(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward * .5}, VEHICLE_TUNE_STANDARD); heavy_engine_pitch := vehicle_engine_frequency(Vehicle_State{speed = VEHICLE_TUNE_HEAVY.max_forward * .5}, VEHICLE_TUNE_HEAVY); assert(sport_engine_pitch > standard_engine_pitch && standard_engine_pitch > heavy_engine_pitch)
	assert(
		vehicle_normalized_driveline_speed(
			Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward},
			VEHICLE_TUNE_STANDARD,
		) ==
			1 &&
		vehicle_normalized_driveline_speed(
			Vehicle_State{speed = -VEHICLE_TUNE_STANDARD.max_reverse},
			VEHICLE_TUNE_STANDARD,
		) ==
			1,
	); _, full_forward_gain := vehicle_engine_targets(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward}, VEHICLE_TUNE_STANDARD, 0); _, full_reverse_gain := vehicle_engine_targets(Vehicle_State{speed = -VEHICLE_TUNE_STANDARD.max_reverse}, VEHICLE_TUNE_STANDARD, 0); assert(full_forward_gain == full_reverse_gain)
	assert(
		vehicle_analog_curve(0) == 0 &&
		vehicle_analog_curve(1) == 1 &&
		vehicle_analog_curve(-1) == -1 &&
		vehicle_analog_curve(.5) > 0 &&
		vehicle_analog_curve(.5) < .5,
	)
	assert(
		vehicle_analog_deadzone(.04, .08) == 0 &&
		vehicle_analog_deadzone(-.08, .08) == 0 &&
		vehicle_analog_deadzone(1, .08) == 1 &&
		vehicle_analog_deadzone(-1, .08) == -1 &&
		vehicle_analog_deadzone(.5, .08) > 0 &&
		vehicle_analog_deadzone(.5, .08) < .5,
	); noisy_controls := Game {
		pad_left_x        = .06,
		pad_left_y        = -.07,
		pad_right_trigger = .03,
	}; noise_throttle, noise_steer := vehicle_control_inputs(
		&noisy_controls,
	); assert(noise_throttle == 0 && noise_steer == 0)
	stick_controls := Game {
		pad_left_x = .5,
		pad_left_y = -.6,
	}; stick_throttle, stick_steer := vehicle_control_inputs(
		&stick_controls,
	); assert(stick_throttle == 0 && stick_steer > 0 && stick_steer < .5)
	below_trigger_edge := vehicle_gamepad_throttle(
		.039,
		0,
	); above_trigger_edge := vehicle_gamepad_throttle(.041, 0); partial_trigger := vehicle_gamepad_throttle(.10, 0); full_trigger := vehicle_gamepad_throttle(1, 0); assert(below_trigger_edge == 0 && above_trigger_edge > 0 && partial_trigger > above_trigger_edge && full_trigger == 1)
	trigger_controls := Game {
		pad_left_y        = 1,
		pad_right_trigger = .7,
		pad_left_trigger  = .2,
	}; trigger_throttle, trigger_steer := vehicle_control_inputs(
		&trigger_controls,
	); assert(trigger_throttle > 0 && trigger_steer == 0); trigger_controls.keys[.S] = true; keyboard_throttle, _ := vehicle_control_inputs(&trigger_controls); assert(keyboard_throttle < trigger_throttle); trigger_controls.pad_buttons[.RIGHT_SHOULDER] = true; assert(vehicle_handbrake_input(&trigger_controls))
	balanced_triggers := Game {
		pad_right_trigger = .4,
		pad_left_trigger  = .4,
	}; balanced_throttle, _ := vehicle_control_inputs(
		&balanced_triggers,
	); assert(balanced_throttle == 0); full_controls := Game {
		pad_left_x        = 1,
		pad_right_trigger = 1,
	}; full_throttle, full_steer := vehicle_control_inputs(
		&full_controls,
	); assert(full_throttle == 1 && full_steer == 1)
	assert(
		vehicle_rear_light_state(Vehicle_State{speed = .3}, -1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{velocity_x = .2}, -1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{speed = -.1}, 1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{velocity_x = -.2}, 1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{speed = -.1}, -1, false) == .Reverse &&
		vehicle_rear_light_state(Vehicle_State{}, -1, false) == .Reverse &&
		vehicle_rear_light_state(Vehicle_State{velocity_x = .01}, -1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{velocity_x = .001}, -1, false) == .Reverse &&
		vehicle_rear_light_state(Vehicle_State{velocity_x = -.01}, 1, false) == .Brake &&
		vehicle_rear_light_state(Vehicle_State{speed = .3}, 1, false) == .Off &&
		vehicle_rear_light_state(Vehicle_State{}, 0, true) == .Brake,
	)
	soft_brake_light := vehicle_rear_light_intensity(
		Vehicle_State{speed = .3},
		-.2,
		false,
	); hard_brake_light := vehicle_rear_light_intensity(Vehicle_State{speed = .3}, -1, false); assert(soft_brake_light > 0 && hard_brake_light > soft_brake_light && hard_brake_light == .5 && vehicle_rear_light_intensity(Vehicle_State{}, -1, false) == .55 && vehicle_rear_light_intensity(Vehicle_State{speed = .3}, 1, false) == 0 && vehicle_rear_light_intensity(Vehicle_State{}, 0, true) == .5)
	assert(
		vehicle_camera_distance(.58) > vehicle_camera_distance(0) &&
		vehicle_camera_height(.58) > vehicle_camera_height(0),
	)
	assert(
		vehicle_camera_bank(Vehicle_State{yaw_rate = .045}) > 0 &&
		vehicle_camera_bank(Vehicle_State{yaw_rate = -.045}) < 0 &&
		vehicle_camera_bank(Vehicle_State{}) == 0,
	); planted_camera := Vehicle_State {
		heading    = 0,
		yaw_rate   = .025,
		velocity_x = .35,
	}; force_camera :=
		planted_camera; force_camera.chassis_lateral_acceleration = 1; drifting_camera := planted_camera; drifting_camera.velocity_y = .28; below_force_bank_speed := vehicle_camera_bank(Vehicle_State{velocity_x = .059, chassis_lateral_acceleration = 1}); above_force_bank_speed := vehicle_camera_bank(Vehicle_State{velocity_x = .061, chassis_lateral_acceleration = 1}); assert(vehicle_camera_bank(force_camera) > vehicle_camera_bank(planted_camera) && vehicle_camera_bank(drifting_camera) > vehicle_camera_bank(planted_camera) && below_force_bank_speed == 0 && above_force_bank_speed > 0 && above_force_bank_speed < .001 && vehicle_camera_bank(Vehicle_State{heading = 0, velocity_x = .1, velocity_y = 10}) <= .05); impact_camera := Vehicle_State {
		impact = 1,
	}; assert(
		math.abs(vehicle_camera_impact_jolt(impact_camera, .02)) <= .09 &&
		vehicle_camera_impact_jolt(Vehicle_State{}, .02) == 0,
	); forward_camera_impact := vehicle_camera_impact_offset(Vehicle_State{impact = 1, impact_forward = -1, impact_time = .01}, .02); side_camera_impact := vehicle_camera_impact_offset(Vehicle_State{impact = 1, impact_side = 1, impact_time = .01}, .02); assert(forward_camera_impact.x > 0 && forward_camera_impact.y == 0 && side_camera_impact.x == 0 && side_camera_impact.y < 0 && math.abs(side_camera_impact.y) > math.abs(forward_camera_impact.x)); assert(vehicle_camera_impact_offset(Vehicle_State{impact = 1, impact_forward = -1, impact_time = 0}, .37) == Vec2{})
	forward_yaw_camera := Vehicle_State {
		velocity_x = .3,
		yaw_rate   = .02,
	}; reverse_yaw_camera := Vehicle_State {
		velocity_x = -.3,
		yaw_rate   = -.02,
	}; assert(
		math.abs(
			vehicle_camera_bank(forward_yaw_camera) - vehicle_camera_bank(reverse_yaw_camera),
		) <
		.0001,
	)
	idle_fov := vehicle_camera_field_of_view(
		Vehicle_State{},
	); fast_fov := vehicle_camera_field_of_view(Vehicle_State{velocity_x = .58}); impact_fov := vehicle_camera_field_of_view(Vehicle_State{velocity_x = .58, impact = 1}); assert(fast_fov > idle_fov && impact_fov > fast_fov && impact_fov <= f32(math.PI / 3) + .127)
	launch_feedback := Vehicle_State {
		velocity_x = .024,
	}; vehicle_update_acceleration_feedback(
		&launch_feedback,
		0,
		false,
	); reverse_launch_feedback := Vehicle_State {
		velocity_x = -.024,
	}; vehicle_update_acceleration_feedback(
		&reverse_launch_feedback,
		0,
		false,
	); brake_feedback := Vehicle_State {
		velocity_x = .20,
	}; vehicle_update_acceleration_feedback(
		&brake_feedback,
		.224,
		false,
	); reverse_brake_feedback := Vehicle_State {
		velocity_x = -.20,
	}; vehicle_update_acceleration_feedback(
		&reverse_brake_feedback,
		-.224,
		false,
	); assert(launch_feedback.acceleration_feedback > 0 && reverse_launch_feedback.acceleration_feedback > 0 && brake_feedback.acceleration_feedback < 0 && launch_feedback.chassis_acceleration > 0 && reverse_launch_feedback.chassis_acceleration < 0 && brake_feedback.chassis_acceleration < 0 && reverse_brake_feedback.chassis_acceleration > 0 && vehicle_camera_acceleration_distance(launch_feedback) > 0 && vehicle_camera_acceleration_distance(brake_feedback) < 0); assert(vehicle_camera_field_of_view(launch_feedback) > vehicle_camera_field_of_view(Vehicle_State{velocity_x = .024}) && vehicle_camera_field_of_view(brake_feedback) < vehicle_camera_field_of_view(Vehicle_State{velocity_x = .20})); launch_base_distance := vehicle_camera_distance(vehicle_actual_speed(launch_feedback)); assert(vehicle_camera_effective_distance(launch_feedback, launch_base_distance) > launch_base_distance && vehicle_camera_effective_distance(launch_feedback, 2) == 2 && vehicle_camera_effective_distance(brake_feedback, 5) < 5); before_feedback := math.abs(launch_feedback.acceleration_feedback); vehicle_update_acceleration_feedback(&launch_feedback, .024, false); assert(math.abs(launch_feedback.acceleration_feedback) < before_feedback); impact_feedback := Vehicle_State {
		velocity_x            = -.2,
		acceleration_feedback = .5,
		chassis_acceleration  = -.5,
	}; vehicle_update_acceleration_feedback(
		&impact_feedback,
		.2,
		true,
	); assert(impact_feedback.acceleration_feedback > 0 && impact_feedback.acceleration_feedback < .5 && impact_feedback.chassis_acceleration < 0 && impact_feedback.chassis_acceleration > -.5)
	rotated_momentum_feedback := Vehicle_State {
		heading    = f32(math.PI / 2),
		velocity_x = .3,
	}; vehicle_update_acceleration_feedback_from_velocity(
		&rotated_momentum_feedback,
		.3,
		0,
		false,
	); assert(rotated_momentum_feedback.acceleration_feedback == 0 && rotated_momentum_feedback.chassis_acceleration == 0 && rotated_momentum_feedback.chassis_lateral_acceleration == 0); lateral_force_feedback := Vehicle_State {
		heading    = 0,
		velocity_x = .3,
		velocity_y = .018,
	}; vehicle_update_acceleration_feedback_from_velocity(
		&lateral_force_feedback,
		.3,
		0,
		false,
	); assert(lateral_force_feedback.chassis_lateral_acceleration > 0 && lateral_force_feedback.chassis_acceleration == 0)
	reversing_feedback := Vehicle_State {
		acceleration_feedback        = .5,
		chassis_acceleration         = .5,
		chassis_lateral_acceleration = .5,
	}; settling_feedback :=
		reversing_feedback; vehicle_update_acceleration_feedback_targets(&reversing_feedback, -.5, -.5, -.5); vehicle_update_acceleration_feedback_targets(&settling_feedback, .2, .2, .2); assert(vehicle_feedback_response(.5, -.5, .24, .14) == .24 && vehicle_feedback_response(.5, .2, .24, .14) == .14 && reversing_feedback.acceleration_feedback < settling_feedback.acceleration_feedback && reversing_feedback.chassis_acceleration < settling_feedback.chassis_acceleration && reversing_feedback.chassis_lateral_acceleration < settling_feedback.chassis_lateral_acceleration)
	open_camera_distance := vehicle_camera_clear_distance(
		10,
		2,
		1,
		0,
		5.2,
	); blocked_camera_distance := vehicle_camera_clear_distance(3, 10, -1, 0, 5.2); assert(open_camera_distance == 5.2 && blocked_camera_distance < 5.2 && blocked_camera_distance >= 1.2); contracted_camera := vehicle_camera_distance_step(5.2, 2); recovering_camera := vehicle_camera_distance_step(2, 5.2); assert(contracted_camera < 5.2 && recovering_camera > 2 && (5.2 - contracted_camera) > (recovering_camera - 2) && vehicle_camera_distance_step(0, 3) == 3)
	assert(
		vehicle_camera_momentum_heading(Vehicle_State{heading = .4, velocity_x = .02}) == .4,
	); forward_camera_slide := vehicle_camera_momentum_heading(Vehicle_State{heading = 0, velocity_x = .2, velocity_y = .3}); reverse_camera_slide := vehicle_camera_momentum_heading(Vehicle_State{heading = 0, velocity_x = -.2, velocity_y = -.3}); assert(forward_camera_slide > 0 && forward_camera_slide < f32(math.atan2(f64(.3), f64(.2))) && math.abs(forward_camera_slide - reverse_camera_slide) < .0001); left_camera_slide := vehicle_camera_momentum_heading(Vehicle_State{heading = 0, velocity_x = .2, velocity_y = -.3}); assert(left_camera_slide < 0 && math.abs(left_camera_slide + forward_camera_slide) < .0001)
	forward_camera := Vehicle_State {
		heading    = 0,
		velocity_x = .2,
	}; reverse_camera := Vehicle_State {
		heading    = 0,
		velocity_x = -.2,
	}; braking_camera := Vehicle_State {
		heading    = 0,
		velocity_x = .2,
	}; residual_forward_camera := Vehicle_State {
		velocity_x = .01,
	}; near_stop_camera := Vehicle_State {
		velocity_x = .001,
	}; assert(
		vehicle_longitudinal_speed(forward_camera) > .19 &&
		vehicle_longitudinal_speed(reverse_camera) < -.19,
	); assert(vehicle_reverse_camera_target(reverse_camera, -1, 0) == 1 && vehicle_reverse_camera_target(forward_camera, 1, 1) == 0 && vehicle_reverse_camera_target(braking_camera, -1, 0) == 0 && vehicle_reverse_camera_target(residual_forward_camera, -1, 0) > 0 && vehicle_reverse_camera_target(residual_forward_camera, -1, 0) < vehicle_reverse_camera_target(near_stop_camera, -1, 0) && vehicle_reverse_camera_target(near_stop_camera, -1, 0) < 1 && vehicle_reverse_camera_target(Vehicle_State{}, 0, .4) == .4)
	assert(
		vehicle_direction_label(forward_camera) == "D" &&
		vehicle_direction_label(reverse_camera) == "R" &&
		vehicle_direction_label(Vehicle_State{}) == "N",
	)
	assert(
		vehicle_transmission_label(Vehicle_State{}, VEHICLE_TUNE_STANDARD) == "N" &&
		vehicle_transmission_label(
			Vehicle_State{speed = -.2, velocity_x = -.2},
			VEHICLE_TUNE_STANDARD,
		) ==
			"R" &&
		vehicle_transmission_label(
			Vehicle_State {
				speed = VEHICLE_TUNE_STANDARD.max_forward * .2,
				velocity_x = VEHICLE_TUNE_STANDARD.max_forward * .2,
			},
			VEHICLE_TUNE_STANDARD,
		) ==
			"D1" &&
		vehicle_transmission_label(
			Vehicle_State {
				speed = VEHICLE_TUNE_STANDARD.max_forward * .35,
				velocity_x = VEHICLE_TUNE_STANDARD.max_forward * .35,
			},
			VEHICLE_TUNE_STANDARD,
		) ==
			"D2" &&
		vehicle_transmission_label(
			Vehicle_State {
				speed = VEHICLE_TUNE_STANDARD.max_forward * .9,
				velocity_x = VEHICLE_TUNE_STANDARD.max_forward * .9,
			},
			VEHICLE_TUNE_STANDARD,
		) ==
			"D4",
	)
	// The roster has meaningful archetypes rather than cosmetic-only models.
	sedan_tune := vehicle_tune(
		0,
	); sport_tune := vehicle_tune(5); heavy_tune := vehicle_tune(10); race_tune := vehicle_tune(17); assert(sedan_tune == VEHICLE_TUNE_SEDAN && sedan_tune.acceleration < VEHICLE_TUNE_STANDARD.acceleration && sedan_tune.max_forward == VEHICLE_TUNE_STANDARD.max_forward); assert(sport_tune.max_forward > VEHICLE_TUNE_STANDARD.max_forward && sport_tune.steering_response > VEHICLE_TUNE_STANDARD.steering_response); assert(heavy_tune.max_forward < VEHICLE_TUNE_STANDARD.max_forward && heavy_tune.acceleration < VEHICLE_TUNE_STANDARD.acceleration); assert(race_tune == VEHICLE_TUNE_SPORT)
	assert(
		vehicle_drag_factor(VEHICLE_TUNE_HEAVY, 0, false, 0) >
		vehicle_drag_factor(VEHICLE_TUNE_SPORT, 0, false, 0),
	); assert(vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 1) > vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 0)); assert(vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 1, false, 0) < vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 0) && vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, true, 0) < vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 1, false, 0)); assert(vehicle_drag_factor(VEHICLE_TUNE_STANDARD, .5, false, 0) < vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 0) && vehicle_drag_factor(VEHICLE_TUNE_STANDARD, .5, false, 0) > vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 1, false, 0))
	low_speed_coast := vehicle_drag_factor(
		VEHICLE_TUNE_STANDARD,
		0,
		false,
		0,
		0,
		.2,
	); high_speed_coast := vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 0, 0, 1); heavy_high_speed_coast := vehicle_drag_factor(VEHICLE_TUNE_HEAVY, 0, false, 0, 0, 1); below_old_powered_drag_threshold := vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, .049, 0, .5); above_old_powered_drag_threshold := vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, .051, 0, .5); assert(high_speed_coast < low_speed_coast && heavy_high_speed_coast > high_speed_coast && below_old_powered_drag_threshold > vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 0, 0, .5) && above_old_powered_drag_threshold > below_old_powered_drag_threshold && above_old_powered_drag_threshold - below_old_powered_drag_threshold < .001 && vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, false, 1, 0, 1) == .994)
	straight_handbrake_drag := vehicle_handbrake_drag_factor(
		0,
		0,
	); sliding_handbrake_drag := vehicle_handbrake_drag_factor(1, 0); rough_handbrake_drag := vehicle_handbrake_drag_factor(0, 1); assert(straight_handbrake_drag > .955 && sliding_handbrake_drag < straight_handbrake_drag && sliding_handbrake_drag >= .946 && rough_handbrake_drag < straight_handbrake_drag); assert(vehicle_drag_factor(VEHICLE_TUNE_STANDARD, 0, true, 0, 1) == sliding_handbrake_drag)
	normal_drift_drag := vehicle_drag_factor_blended(
		VEHICLE_TUNE_STANDARD,
		0,
		0,
		0,
		1,
		0,
	); half_drift_drag := vehicle_drag_factor_blended(VEHICLE_TUNE_STANDARD, 0, .5, 0, 1, 0); full_drift_drag := vehicle_drag_factor_blended(VEHICLE_TUNE_STANDARD, 0, 1, 0, 1, 0); assert(full_drift_drag < half_drift_drag && half_drift_drag < normal_drift_drag && math.abs(half_drift_drag - (normal_drift_drag + full_drift_drag) * .5) < .0001)
	assert(
		vehicle_drive_torque(VEHICLE_TUNE_STANDARD, 0, true) >
			VEHICLE_TUNE_STANDARD.acceleration &&
		vehicle_drive_torque(VEHICLE_TUNE_STANDARD, .57, true) <
			VEHICLE_TUNE_STANDARD.acceleration,
	); assert(vehicle_drive_torque(VEHICLE_TUNE_STANDARD, 0, false) > vehicle_drive_torque(VEHICLE_TUNE_STANDARD, -.21, false)); launch_car := Vehicle_State{}; vehicle_apply_throttle(&launch_car, VEHICLE_TUNE_STANDARD, 1); assert(launch_car.speed > VEHICLE_TUNE_STANDARD.acceleration); forward_braking := Vehicle_State {
		speed = .02,
	}; reverse_braking := Vehicle_State {
		speed = -.02,
	}; vehicle_apply_throttle(
		&forward_braking,
		VEHICLE_TUNE_STANDARD,
		-1,
	); vehicle_apply_throttle(&reverse_braking, VEHICLE_TUNE_STANDARD, 1); assert(forward_braking.speed == 0 && reverse_braking.speed == 0); vehicle_apply_throttle(&forward_braking, VEHICLE_TUNE_STANDARD, -1); vehicle_apply_throttle(&reverse_braking, VEHICLE_TUNE_STANDARD, 1); assert(forward_braking.speed < 0 && reverse_braking.speed > 0)
	forward_coast_interlock := Vehicle_State {
		velocity_x = .2,
	}; reverse_coast_interlock := Vehicle_State {
		velocity_x = -.2,
	}; vehicle_apply_throttle(
		&forward_coast_interlock,
		VEHICLE_TUNE_STANDARD,
		-1,
	); vehicle_apply_throttle(&reverse_coast_interlock, VEHICLE_TUNE_STANDARD, 1); assert(forward_coast_interlock.speed == 0 && reverse_coast_interlock.speed == 0 && vehicle_transmission_label(forward_coast_interlock, VEHICLE_TUNE_STANDARD) == "N" && vehicle_transmission_label(reverse_coast_interlock, VEHICLE_TUNE_STANDARD) == "N"); slow_forward_authority := vehicle_direction_change_authority(.01, false); near_stop_forward_authority := vehicle_direction_change_authority(.001, false); slow_reverse_authority := vehicle_direction_change_authority(-.01, true); assert(slow_forward_authority > 0 && slow_forward_authority < near_stop_forward_authority && near_stop_forward_authority < 1 && slow_reverse_authority == slow_forward_authority && vehicle_direction_change_authority(.015, false) == 0 && vehicle_direction_change_authority(0, false) == 1); feathered_reverse := Vehicle_State {
		velocity_x = .01,
	}; near_stop_reverse := Vehicle_State {
		velocity_x = .001,
	}; vehicle_apply_throttle(
		&feathered_reverse,
		VEHICLE_TUNE_STANDARD,
		-1,
	); vehicle_apply_throttle(&near_stop_reverse, VEHICLE_TUNE_STANDARD, -1); assert(feathered_reverse.speed < 0 && near_stop_reverse.speed < feathered_reverse.speed); forward_coast_interlock.velocity_x = 0; reverse_coast_interlock.velocity_x = 0; vehicle_apply_throttle(&forward_coast_interlock, VEHICLE_TUNE_STANDARD, -1); vehicle_apply_throttle(&reverse_coast_interlock, VEHICLE_TUNE_STANDARD, 1); assert(forward_coast_interlock.speed < 0 && reverse_coast_interlock.speed > 0); assert(vehicle_engine_load(Vehicle_State{velocity_x = .2}, -1) < vehicle_engine_load(Vehicle_State{velocity_x = .2}, 1))
	assert(
		vehicle_service_brake_factor(Vehicle_State{speed = .3, velocity_x = .3}) == 1 &&
		math.abs(vehicle_service_brake_factor(locked_wheels) - .58) < .0001,
	); unmodulated_brake := Vehicle_State {
		speed      = .12,
		velocity_x = .3,
	}; modulated_factor := vehicle_service_brake_factor(
		unmodulated_brake,
	); before_brake_speed := unmodulated_brake.speed; vehicle_apply_throttle(&unmodulated_brake, VEHICLE_TUNE_STANDARD, -1); assert(modulated_factor < 1 && unmodulated_brake.speed < before_brake_speed && unmodulated_brake.speed > before_brake_speed - VEHICLE_TUNE_STANDARD.brake); assert(vehicle_handbrake_drag_factor(1, 0) < vehicle_handbrake_drag_factor(0, 0))
	abs_pressure_probe := Vehicle_State {
		speed                  = .3,
		velocity_x             = .3,
		driver_assist          = .ABS,
		driver_assist_strength = 1,
	}; half_abs_pressure_probe :=
		abs_pressure_probe; half_abs_pressure_probe.driver_assist_strength = .5; tc_pressure_probe := abs_pressure_probe; tc_pressure_probe.driver_assist = .Traction_Control; assert(math.abs(vehicle_service_brake_pressure(abs_pressure_probe) - .88) < .0001 && vehicle_service_brake_pressure(half_abs_pressure_probe) > vehicle_service_brake_pressure(abs_pressure_probe) && vehicle_service_brake_pressure(half_abs_pressure_probe) < vehicle_service_brake_pressure(tc_pressure_probe) && vehicle_service_brake_pressure(tc_pressure_probe) == 1)
	abs_release :=
		locked_wheels; half_abs_release := locked_wheels; reverse_abs_release := Vehicle_State {
		speed      = 0,
		velocity_x = -.3,
	}; vehicle_apply_abs_release(
		&abs_release,
		1,
	); vehicle_apply_abs_release(&half_abs_release, .5); vehicle_apply_abs_release(&reverse_abs_release, 1); assert(abs_release.speed > 0 && abs_release.speed < .3 && half_abs_release.speed > 0 && half_abs_release.speed < abs_release.speed && reverse_abs_release.speed < 0 && math.abs(reverse_abs_release.speed + abs_release.speed) < .0001); spinning_abs_probe := spinning_wheels; vehicle_apply_abs_release(&spinning_abs_probe, 1); assert(spinning_abs_probe.speed == spinning_wheels.speed)
	locked_braking_corner := Vehicle_State {
		speed      = 0,
		velocity_x = .3,
		velocity_y = .15,
	}; abs_braking_corner :=
		locked_braking_corner; vehicle_apply_abs_release(&abs_braking_corner, 1); vehicle_apply_tire_grip(&locked_braking_corner, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&abs_braking_corner, false, VEHICLE_TUNE_STANDARD); assert(abs_braking_corner.velocity_x > locked_braking_corner.velocity_x && math.abs(abs_braking_corner.velocity_y) < math.abs(locked_braking_corner.velocity_y) * .98)
	assert(
		vehicle_traction_control_factor(gripping, VEHICLE_TUNE_STANDARD) == 1 &&
		math.abs(
			vehicle_traction_control_factor(spinning_wheels, VEHICLE_TUNE_STANDARD) -
			VEHICLE_TUNE_STANDARD.traction_control_floor,
		) <
			.0001 &&
		vehicle_traction_control_factor(locked_wheels, VEHICLE_TUNE_STANDARD) == 1,
	); assert(vehicle_traction_control_factor(spinning_wheels, VEHICLE_TUNE_SPORT) > vehicle_traction_control_factor(spinning_wheels, VEHICLE_TUNE_STANDARD) && vehicle_traction_control_factor(spinning_wheels, VEHICLE_TUNE_HEAVY) < vehicle_traction_control_factor(spinning_wheels, VEHICLE_TUNE_STANDARD)); assisted_spin := Vehicle_State {
		speed = VEHICLE_TUNE_STANDARD.max_forward * .5,
	}; unassisted_spin :=
		assisted_spin; assisted_spin_before := assisted_spin.speed; vehicle_apply_throttle_for_reference(&assisted_spin, VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_STANDARD, 1, true); vehicle_apply_throttle_for_reference(&unassisted_spin, VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_STANDARD, 1, false); assert(assisted_spin.speed > assisted_spin_before && assisted_spin.speed < unassisted_spin.speed)
	retained_tc_drive := Vehicle_State {
		speed                  = .3,
		velocity_x             = .3,
		driver_assist          = .Traction_Control,
		driver_assist_strength = 1,
	}; half_retained_tc_drive :=
		retained_tc_drive; half_retained_tc_drive.driver_assist_strength = .5; abs_drive_probe := retained_tc_drive; abs_drive_probe.driver_assist = .ABS; assert(vehicle_traction_control_factor(retained_tc_drive, VEHICLE_TUNE_STANDARD) == 1 && vehicle_traction_control_drive_factor(retained_tc_drive, VEHICLE_TUNE_STANDARD) < vehicle_traction_control_drive_factor(half_retained_tc_drive, VEHICLE_TUNE_STANDARD) && vehicle_traction_control_drive_factor(half_retained_tc_drive, VEHICLE_TUNE_STANDARD) < vehicle_traction_control_drive_factor(abs_drive_probe, VEHICLE_TUNE_STANDARD) && vehicle_traction_control_drive_factor(abs_drive_probe, VEHICLE_TUNE_STANDARD) == 1)
	trimmed_spin :=
		spinning_wheels; half_trimmed_spin := spinning_wheels; sport_trimmed_spin := spinning_wheels; vehicle_apply_traction_control(&trimmed_spin, VEHICLE_TUNE_STANDARD, 1); vehicle_apply_traction_control(&half_trimmed_spin, VEHICLE_TUNE_STANDARD, .5); vehicle_apply_traction_control(&sport_trimmed_spin, VEHICLE_TUNE_SPORT, 1); assert(trimmed_spin.speed < spinning_wheels.speed && trimmed_spin.speed > 0 && half_trimmed_spin.speed > trimmed_spin.speed && half_trimmed_spin.speed < spinning_wheels.speed && sport_trimmed_spin.speed > trimmed_spin.speed); locked_tc_probe := locked_wheels; vehicle_apply_traction_control(&locked_tc_probe, VEHICLE_TUNE_STANDARD, 1); assert(locked_tc_probe.speed == locked_wheels.speed)
	assert(
		vehicle_traction_control_trim_response(VEHICLE_TUNE_HEAVY) >
			vehicle_traction_control_trim_response(VEHICLE_TUNE_STANDARD) &&
		vehicle_traction_control_trim_response(VEHICLE_TUNE_STANDARD) >
			vehicle_traction_control_trim_response(VEHICLE_TUNE_SPORT),
	); unassisted_power_corner := Vehicle_State {
		heading    = 0,
		speed      = .3,
		velocity_x = .1,
		velocity_y = .15,
	}; assisted_power_corner :=
		unassisted_power_corner; vehicle_apply_traction_control(&assisted_power_corner, VEHICLE_TUNE_STANDARD, 1); vehicle_apply_tire_grip(&unassisted_power_corner, false, VEHICLE_TUNE_STANDARD); vehicle_apply_tire_grip(&assisted_power_corner, false, VEHICLE_TUNE_STANDARD); assert(math.abs(assisted_power_corner.velocity_y) < math.abs(unassisted_power_corner.velocity_y) && vehicle_longitudinal_slip_ratio(assisted_power_corner) < vehicle_longitudinal_slip_ratio(unassisted_power_corner))
	unassisted_yaw_corner := Vehicle_State {
		heading    = 0,
		speed      = .3,
		velocity_x = .1,
		steering   = 1,
	}; assisted_yaw_corner :=
		unassisted_yaw_corner; vehicle_apply_traction_control(&assisted_yaw_corner, VEHICLE_TUNE_STANDARD, 1); vehicle_apply_yaw(&unassisted_yaw_corner, false, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw(&assisted_yaw_corner, false, VEHICLE_TUNE_STANDARD); assert(assisted_yaw_corner.yaw_rate > unassisted_yaw_corner.yaw_rate)
	unassisted_align_corner := Vehicle_State {
		heading    = 0,
		speed      = .3,
		velocity_x = .1,
		velocity_y = .15,
	}; assisted_align_corner :=
		unassisted_align_corner; vehicle_apply_traction_control(&assisted_align_corner, VEHICLE_TUNE_STANDARD, 1); assert(vehicle_self_aligning_yaw(assisted_align_corner, false, VEHICLE_TUNE_STANDARD) > vehicle_self_aligning_yaw(unassisted_align_corner, false, VEHICLE_TUNE_STANDARD)); bounded_tc := Vehicle_State {
		heading    = 0,
		speed      = .4,
		velocity_x = .2,
	}; vehicle_apply_traction_control(
		&bounded_tc,
		VEHICLE_TUNE_STANDARD,
		1,
	); assert(bounded_tc.speed >= f32(.2) && bounded_tc.speed < .4); bounded_reverse_tc := Vehicle_State {
		heading    = 0,
		speed      = -.4,
		velocity_x = -.2,
	}; vehicle_apply_traction_control(
		&bounded_reverse_tc,
		VEHICLE_TUNE_STANDARD,
		1,
	); assert(bounded_reverse_tc.speed <= f32(-.2) && math.abs(bounded_reverse_tc.speed + bounded_tc.speed) < .0001)
	half_assisted_spin := Vehicle_State {
		speed = assisted_spin_before,
	}; vehicle_apply_throttle_assisted(
		&half_assisted_spin,
		VEHICLE_TUNE_STANDARD,
		VEHICLE_TUNE_STANDARD,
		1,
		.5,
	); assert(half_assisted_spin.speed > assisted_spin.speed && half_assisted_spin.speed < unassisted_spin.speed && math.abs(half_assisted_spin.speed - (assisted_spin.speed + unassisted_spin.speed) * .5) < .0001)
	assert(
		vehicle_driver_assist(locked_wheels, VEHICLE_TUNE_STANDARD, -1, false) == .ABS &&
		vehicle_driver_assist(spinning_wheels, VEHICLE_TUNE_STANDARD, 1, false) ==
			.Traction_Control &&
		vehicle_driver_assist(spinning_wheels, VEHICLE_TUNE_STANDARD, 1, true) == .None &&
		vehicle_driver_assist(gripping, VEHICLE_TUNE_STANDARD, 1, false) == .None,
	); assert(vehicle_driver_assist_label(.ABS) == "ABS" && vehicle_driver_assist_label(.Traction_Control) == "TC" && vehicle_driver_assist_label(.None) == "")
	idle_assist_color := vehicle_driver_assist_indicator_color(
		0,
	); half_assist_color := vehicle_driver_assist_indicator_color(.5); full_assist_color := vehicle_driver_assist_indicator_color(1); assert(idle_assist_color == [4]u8{145, 153, 162, 255} && full_assist_color == [4]u8{255, 211, 92, 255} && half_assist_color[0] > idle_assist_color[0] && half_assist_color[0] < full_assist_color[0] && half_assist_color[1] > idle_assist_color[1] && half_assist_color[1] < full_assist_color[1] && vehicle_driver_assist_indicator_color(-1) == idle_assist_color && vehicle_driver_assist_indicator_color(2) == full_assist_color)
	full_tc_assist, full_tc_strength := vehicle_driver_assist_blended(
		spinning_wheels,
		VEHICLE_TUNE_STANDARD,
		1,
		0,
	); half_tc_assist, half_tc_strength := vehicle_driver_assist_blended(spinning_wheels, VEHICLE_TUNE_STANDARD, 1, .5); no_tc_assist, no_tc_strength := vehicle_driver_assist_blended(spinning_wheels, VEHICLE_TUNE_STANDARD, 1, 1); assert(full_tc_assist == .Traction_Control && half_tc_assist == .Traction_Control && no_tc_assist == .None && full_tc_strength == 1 && math.abs(half_tc_strength - .5) < .0001 && no_tc_strength == 0)
	handbrake_abs, handbrake_abs_strength := vehicle_driver_assist_blended(
		locked_wheels,
		VEHICLE_TUNE_STANDARD,
		-1,
		1,
	); normal_abs, normal_abs_strength := vehicle_driver_assist_blended(locked_wheels, VEHICLE_TUNE_STANDARD, -1, 0); assert(handbrake_abs == .ABS && normal_abs == .ABS && handbrake_abs_strength == normal_abs_strength && handbrake_abs_strength > .99)
	held_assist, held_assist_strength := vehicle_driver_assist_state_step(
		.ABS,
		1,
		.None,
		0,
	); weaker_same_assist, weaker_same_assist_strength := vehicle_driver_assist_state_step(.ABS, 1, .ABS, .1); stronger_same_assist, stronger_same_assist_strength := vehicle_driver_assist_state_step(.ABS, .2, .ABS, .8); assert(held_assist == .ABS && held_assist_strength == .72 && weaker_same_assist == .ABS && weaker_same_assist_strength == .72 && stronger_same_assist == .ABS && stronger_same_assist_strength == .8); for _ in 0 ..< 20 do held_assist, held_assist_strength = vehicle_driver_assist_state_step(held_assist, held_assist_strength, .None, 0); assert(held_assist == .None && held_assist_strength == 0); switched_assist, switched_assist_strength := vehicle_driver_assist_state_step(.ABS, .5, .Traction_Control, .7); assert(switched_assist == .Traction_Control && switched_assist_strength == .7)
	cancelled_tc, cancelled_tc_strength := vehicle_driver_assist_state_step(
		.Traction_Control,
		.8,
		.None,
		0,
		.5,
	); retained_handbrake_abs, retained_handbrake_abs_strength := vehicle_driver_assist_state_step(.ABS, .8, .None, 0, .5); assert(cancelled_tc == .None && cancelled_tc_strength == 0 && retained_handbrake_abs == .ABS && retained_handbrake_abs_strength > 0)
	transition_abs_car := Vehicle_State {
		velocity_x = .01,
	}; transition_abs, transition_abs_strength := vehicle_driver_assist_blended(
		transition_abs_car,
		VEHICLE_TUNE_STANDARD,
		-1,
		0,
	); full_transition_abs, full_transition_abs_strength := vehicle_driver_assist_blended(Vehicle_State{velocity_x = .015}, VEHICLE_TUNE_STANDARD, -1, 0); assert(vehicle_requested_drive_authority(transition_abs_car, -1) > 0 && vehicle_requested_drive_authority(transition_abs_car, -1) < 1 && transition_abs == .ABS && transition_abs_strength > 0 && full_transition_abs == .ABS && full_transition_abs_strength > transition_abs_strength && vehicle_requested_drive_authority(Vehicle_State{}, 0) == 0)
	abs_haptic_min, abs_haptic_max :=
		f32(1),
		f32(
			0,
		); tc_haptic_min, tc_haptic_max := f32(1), f32(0); for step in 0 ..= 60 {sample_time := f32(step) / 60; abs_sample := vehicle_assist_haptic_multiplier(.ABS, sample_time); tc_sample := vehicle_assist_haptic_multiplier(.Traction_Control, sample_time); abs_haptic_min = min(abs_haptic_min, abs_sample); abs_haptic_max = max(abs_haptic_max, abs_sample); tc_haptic_min = min(tc_haptic_min, tc_sample); tc_haptic_max = max(tc_haptic_max, tc_sample); assert(abs_sample >= .55 && abs_sample <= 1 && tc_sample >= .72 && tc_sample <= 1)}; assert(abs_haptic_min < abs_haptic_max && tc_haptic_min < tc_haptic_max && vehicle_assist_haptic_multiplier(.None, .5) == 1)
	haptic_time := f32(
		.07,
	); full_tc_haptic := vehicle_assist_haptic_multiplier_blended(.Traction_Control, 1, haptic_time); half_tc_haptic := vehicle_assist_haptic_multiplier_blended(.Traction_Control, .5, haptic_time); assert(full_tc_haptic < half_tc_haptic && half_tc_haptic < 1 && vehicle_assist_haptic_multiplier_blended(.Traction_Control, 0, haptic_time) == 1)
	assist_slip_high := vehicle_assisted_high_haptic(
		spinning_wheels,
		.25,
		.Traction_Control,
		1,
		haptic_time,
	); assist_impact_high := vehicle_assisted_high_haptic(Vehicle_State{impact = 1}, .48, .ABS, 1, haptic_time); assert(assist_slip_high < .25 && assist_slip_high > 0 && assist_impact_high == .48)
	abs_recovered_haptic := vehicle_assisted_high_haptic(
		Vehicle_State{},
		0,
		.ABS,
		1,
		0,
	); half_abs_recovered_haptic := vehicle_assisted_high_haptic(Vehicle_State{}, 0, .ABS, .5, 0); tc_recovered_haptic := vehicle_assisted_high_haptic(Vehicle_State{}, 0, .Traction_Control, 1, 0); assert(abs_recovered_haptic > tc_recovered_haptic && tc_recovered_haptic > 0 && half_abs_recovered_haptic > 0 && half_abs_recovered_haptic < abs_recovered_haptic && vehicle_assisted_high_haptic(Vehicle_State{}, 0, .None, 1, 0) == 0)
	abs_assist_audio := vehicle_assist_audio_gain(
		.ABS,
		1,
		0,
	); half_abs_assist_audio := vehicle_assist_audio_gain(.ABS, .5, 0); tc_assist_audio := vehicle_assist_audio_gain(.Traction_Control, 1, 0); assert(abs_assist_audio > tc_assist_audio && tc_assist_audio > 0 && half_abs_assist_audio > 0 && half_abs_assist_audio < abs_assist_audio && vehicle_assist_audio_gain(.None, 1, 0) == 0); for step in 0 ..= 60 {sample_time := f32(step) / 60; assert(vehicle_assist_audio_gain(.ABS, 1, sample_time) >= 0 && vehicle_assist_audio_gain(.ABS, 1, sample_time) <= .025 && vehicle_assist_audio_gain(.Traction_Control, 1, sample_time) <= .020)}
	first_shift_normalized := f32(
		.06 + .94 / 4,
	); first_shift_speed := VEHICLE_TUNE_STANDARD.max_forward * first_shift_normalized; pre_shift_torque := vehicle_drive_torque(VEHICLE_TUNE_STANDARD, first_shift_speed - .002, true); post_shift_torque := vehicle_drive_torque(VEHICLE_TUNE_STANDARD, first_shift_speed + .002, true); recovered_shift_torque := vehicle_drive_torque(VEHICLE_TUNE_STANDARD, first_shift_speed + .025, true); just_before_shift_factor := vehicle_shift_torque_factor(first_shift_normalized - .00001); just_after_shift_factor := vehicle_shift_torque_factor(first_shift_normalized + .00001); assert(post_shift_torque < pre_shift_torque && recovered_shift_torque > post_shift_torque && vehicle_shift_torque_factor(.06) == 1 && vehicle_shift_torque_factor(1) == 1 && just_before_shift_factor < .781 && just_after_shift_factor < .781 && math.abs(just_before_shift_factor - just_after_shift_factor) < .001); for step in 0 ..= 100 {sample_speed := VEHICLE_TUNE_STANDARD.max_forward * f32(step) / 100; assert(vehicle_drive_torque(VEHICLE_TUNE_STANDARD, sample_speed, true) > 0)}
	turn_in_response := vehicle_steering_response(
		VEHICLE_TUNE_STANDARD,
		.5,
		1,
	); low_speed_center := vehicle_steering_response(VEHICLE_TUNE_STANDARD, 0, 0); high_speed_center := vehicle_steering_response(VEHICLE_TUNE_STANDARD, 1, 0); near_center_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, .019); past_old_threshold_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, .021); medium_input_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, .10); below_old_reversal_threshold := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, -.032, .6); above_old_reversal_threshold := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, -.034, .6); same_magnitude_non_reversal := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, .032, .6); left_to_right_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, 1, -.6); right_to_left_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, -1, .6); same_direction_response := vehicle_steering_response(VEHICLE_TUNE_STANDARD, .5, 1, .6); assert(low_speed_center > turn_in_response && high_speed_center > low_speed_center && high_speed_center <= .42 && near_center_response > past_old_threshold_response && past_old_threshold_response > medium_input_response && near_center_response - past_old_threshold_response < .01 && medium_input_response > turn_in_response && below_old_reversal_threshold > same_magnitude_non_reversal && math.abs(above_old_reversal_threshold - below_old_reversal_threshold) < .01 && left_to_right_response > turn_in_response && left_to_right_response == right_to_left_response && same_direction_response == turn_in_response && left_to_right_response <= .42); steering_release := Vehicle_State {
		steering = .8,
	}; steering_release.steering +=
		(0 - steering_release.steering) *
		high_speed_center; assert(steering_release.steering > 0 && steering_release.steering < .8)
	locked_steering_speed := vehicle_normalized_steering_speed(
		Vehicle_State{speed = 0, velocity_x = VEHICLE_TUNE_STANDARD.max_forward},
		VEHICLE_TUNE_STANDARD,
	); spinning_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward}, VEHICLE_TUNE_STANDARD); gripping_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward, velocity_x = VEHICLE_TUNE_STANDARD.max_forward}, VEHICLE_TUNE_STANDARD); assert(locked_steering_speed == 1 && spinning_steering_speed > 0 && spinning_steering_speed < 1 && gripping_steering_speed == 1 && vehicle_normalized_steering_speed(Vehicle_State{}, VEHICLE_TUNE_STANDARD) == 0)
	full_reverse_steering_speed := vehicle_normalized_steering_speed(
		Vehicle_State {
			speed = -VEHICLE_TUNE_STANDARD.max_reverse,
			velocity_x = -VEHICLE_TUNE_STANDARD.max_reverse,
		},
		VEHICLE_TUNE_STANDARD,
	); half_reverse_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = -VEHICLE_TUNE_STANDARD.max_reverse * .5, velocity_x = -VEHICLE_TUNE_STANDARD.max_reverse * .5}, VEHICLE_TUNE_STANDARD); half_forward_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = VEHICLE_TUNE_STANDARD.max_forward * .5, velocity_x = VEHICLE_TUNE_STANDARD.max_forward * .5}, VEHICLE_TUNE_STANDARD); reverse_locked_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{velocity_x = -VEHICLE_TUNE_STANDARD.max_reverse}, VEHICLE_TUNE_STANDARD); assert(full_reverse_steering_speed == 1 && math.abs(half_reverse_steering_speed - half_forward_steering_speed) < .0001 && reverse_locked_steering_speed == 1)
	near_forward_steering_weight := vehicle_reverse_steering_weight(
		Vehicle_State{speed = .01, velocity_x = .001},
	); neutral_steering_weight := vehicle_reverse_steering_weight(Vehicle_State{}); near_reverse_steering_weight := vehicle_reverse_steering_weight(Vehicle_State{speed = -.01, velocity_x = -.001}); below_neutral_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = -.08, velocity_x = .001}, VEHICLE_TUNE_STANDARD); above_neutral_steering_speed := vehicle_normalized_steering_speed(Vehicle_State{speed = -.08, velocity_x = -.001}, VEHICLE_TUNE_STANDARD); assert(near_forward_steering_weight < neutral_steering_weight && neutral_steering_weight < near_reverse_steering_weight && neutral_steering_weight == .5 && math.abs(above_neutral_steering_speed - below_neutral_steering_speed) < .02)
	normal_high_speed_lock := vehicle_steering_limit(
		VEHICLE_TUNE_STANDARD,
		1,
		0,
	); half_drift_lock := vehicle_steering_limit(VEHICLE_TUNE_STANDARD, 1, .5, true); full_drift_lock := vehicle_steering_limit(VEHICLE_TUNE_STANDARD, 1, 1, true); assert(normal_high_speed_lock < half_drift_lock && half_drift_lock < full_drift_lock && math.abs(half_drift_lock - (normal_high_speed_lock + full_drift_lock) * .5) < .0001 && full_drift_lock <= .98 && vehicle_steering_limit(VEHICLE_TUNE_STANDARD, 1, 1, false) == normal_high_speed_lock && vehicle_steering_limit(VEHICLE_TUNE_SPORT, 0, 1, true) == .98); assert(vehicle_is_countersteering(Vehicle_State{heading = 0, velocity_x = .3, velocity_y = .2}, 1) && !vehicle_is_countersteering(Vehicle_State{heading = 0, velocity_x = .3, velocity_y = .2}, -1) && vehicle_is_countersteering(Vehicle_State{heading = 0, velocity_x = -.3, velocity_y = .2}, 1))
	below_old_creep_cutoff := vehicle_steering_yaw_speed(
		.0019,
	); above_old_creep_cutoff := vehicle_steering_yaw_speed(.0021); assert(vehicle_steering_yaw_speed(0) == 0 && below_old_creep_cutoff > 0 && above_old_creep_cutoff > below_old_creep_cutoff && above_old_creep_cutoff - below_old_creep_cutoff < .001 && vehicle_steering_yaw_speed(.02) > .02 && vehicle_steering_yaw_speed(-.02) < -.02 && vehicle_steering_yaw_speed(.10) == .10 && vehicle_steering_yaw_speed(-.0021) == -above_old_creep_cutoff); creep_forward := Vehicle_State {
		speed      = .02,
		steering   = 1,
		velocity_x = .02,
	}; creep_reverse := Vehicle_State {
		speed      = -.02,
		steering   = 1,
		velocity_x = -.02,
	}; unboosted_creep_yaw :=
		.02 *
		.075 *
		VEHICLE_TUNE_STANDARD.yaw_response; vehicle_apply_yaw(&creep_forward, false, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw(&creep_reverse, false, VEHICLE_TUNE_STANDARD); assert(creep_forward.yaw_rate > unboosted_creep_yaw && creep_reverse.yaw_rate < -unboosted_creep_yaw && math.abs(creep_forward.yaw_rate + creep_reverse.yaw_rate) < .0001)
	locked_turning := Vehicle_State {
		speed      = 0,
		steering   = 1,
		velocity_x = .2,
	}; spinning_turning := Vehicle_State {
		speed    = .3,
		steering = 1,
	}; vehicle_apply_yaw(
		&locked_turning,
		false,
		VEHICLE_TUNE_STANDARD,
	); vehicle_apply_yaw(&spinning_turning, false, VEHICLE_TUNE_STANDARD); assert(locked_turning.yaw_rate > 0 && spinning_turning.yaw_rate == 0); reverse_locked_turning := Vehicle_State {
		speed      = 0,
		steering   = 1,
		velocity_x = -.2,
	}; vehicle_apply_yaw(
		&reverse_locked_turning,
		false,
		VEHICLE_TUNE_STANDARD,
	); assert(reverse_locked_turning.yaw_rate < 0 && math.abs(reverse_locked_turning.yaw_rate + locked_turning.yaw_rate) < .0001)
	assert(
		vehicle_steering_lateral_grip_factor(Vehicle_State{heading = 0, velocity_x = .4}, 1) == 1,
	); saturated_slide := Vehicle_State {
		heading    = 0,
		velocity_x = .2,
		velocity_y = .3,
	}; assert(
		vehicle_steering_lateral_grip_factor(saturated_slide, -1) < 1 &&
		vehicle_steering_lateral_grip_factor(saturated_slide, 1) == 1,
	); understeer_probe := saturated_slide; countersteer_probe := saturated_slide; understeer_probe.speed = .36; countersteer_probe.speed = .36; understeer_probe.steering = -1; countersteer_probe.steering = 1; vehicle_apply_yaw(&understeer_probe, false, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw(&countersteer_probe, false, VEHICLE_TUNE_STANDARD); assert(math.abs(countersteer_probe.yaw_rate) > math.abs(understeer_probe.yaw_rate))
	right_slide_assist := vehicle_stability_steering(
		Vehicle_State{heading = 0, speed = .35, velocity_x = .25, velocity_y = .20},
		false,
	); left_slide_assist := vehicle_stability_steering(Vehicle_State{heading = 0, speed = .35, velocity_x = .25, velocity_y = -.20}, false); reverse_slide_assist := vehicle_stability_steering(Vehicle_State{heading = 0, speed = -.35, velocity_x = -.25, velocity_y = .20}, false); below_assist_speed := vehicle_stability_steering(Vehicle_State{velocity_x = .07, velocity_y = .07}, false); above_assist_speed := vehicle_stability_steering(Vehicle_State{velocity_x = .072, velocity_y = .072}, false); assert(right_slide_assist > 0 && left_slide_assist < 0 && reverse_slide_assist > 0 && math.abs(right_slide_assist) <= .26 && below_assist_speed == 0 && above_assist_speed > 0 && above_assist_speed < .01); assert(vehicle_stability_steering(Vehicle_State{velocity_x = .09, velocity_y = .02}, false) == 0 && vehicle_stability_steering(Vehicle_State{velocity_x = .25, velocity_y = .20}, true) == 0); manual_recovery := Vehicle_State {
		heading    = 0,
		speed      = .35,
		velocity_x = .25,
		velocity_y = .20,
	}; manual_recovery.steering =
		right_slide_assist; before_recovery_slip := vehicle_lateral_slip_ratio(manual_recovery); vehicle_apply_yaw(&manual_recovery, false, VEHICLE_TUNE_STANDARD); assert(vehicle_lateral_slip_ratio(manual_recovery) < before_recovery_slip)
	half_slide_assist := vehicle_stability_steering_blended(
		Vehicle_State{heading = 0, speed = .35, velocity_x = .25, velocity_y = .20},
		.5,
	); assert(half_slide_assist > 0 && half_slide_assist < right_slide_assist && math.abs(half_slide_assist - right_slide_assist * .5) < .0001)
	assist_probe := Vehicle_State {
		heading    = 0,
		speed      = .35,
		velocity_x = .25,
		velocity_y = .20,
	}; assisted_center := vehicle_assisted_steering_input(
		assist_probe,
		0,
		0,
	); assisted_nudge := vehicle_assisted_steering_input(assist_probe, .01, 0); assisted_correction := vehicle_assisted_steering_input(assist_probe, .175, 0); unassisted_command := vehicle_assisted_steering_input(assist_probe, .35, 0); assert(assisted_center == right_slide_assist && assisted_nudge > assisted_center && assisted_nudge - assisted_center < .01 && assisted_correction > .175 && assisted_correction < .175 + right_slide_assist && unassisted_command == .35 && vehicle_assisted_steering_input(assist_probe, 0, 1) == 0); assert(vehicle_assisted_steering_input(assist_probe, -.175, 0) < -.175 + right_slide_assist && vehicle_assisted_steering_input(assist_probe, -.35, 0) == -.35)
	assert(
		vehicle_stability_assist_scale(VEHICLE_TUNE_SPORT) <
			vehicle_stability_assist_scale(VEHICLE_TUNE_STANDARD) &&
		vehicle_stability_assist_scale(VEHICLE_TUNE_STANDARD) == 1 &&
		vehicle_stability_assist_scale(VEHICLE_TUNE_STANDARD) <
			vehicle_stability_assist_scale(VEHICLE_TUNE_UTILITY) &&
		vehicle_stability_assist_scale(VEHICLE_TUNE_UTILITY) <
			vehicle_stability_assist_scale(VEHICLE_TUNE_HEAVY),
	); sport_stability := vehicle_assisted_steering_input(assist_probe, 0, 0, VEHICLE_TUNE_SPORT); utility_stability := vehicle_assisted_steering_input(assist_probe, 0, 0, VEHICLE_TUNE_UTILITY); heavy_stability := vehicle_assisted_steering_input(assist_probe, 0, 0, VEHICLE_TUNE_HEAVY); assert(sport_stability < assisted_center && assisted_center < utility_stability && utility_stability < heavy_stability && vehicle_assisted_steering_input(assist_probe, .35, 0, VEHICLE_TUNE_HEAVY) == .35)
	residual_spin_assist := vehicle_stability_steering(
		Vehicle_State{heading = 0, speed = .3, velocity_x = .3, velocity_y = .03, yaw_rate = .04},
		false,
	); reverse_residual_spin_assist := vehicle_stability_steering(Vehicle_State{heading = 0, speed = -.3, velocity_x = -.3, velocity_y = .03, yaw_rate = -.04}, false); assert(residual_spin_assist < 0 && reverse_residual_spin_assist < 0 && math.abs(residual_spin_assist) <= .12 && vehicle_stability_steering_blended(Vehicle_State{heading = 0, speed = .3, velocity_x = .3, velocity_y = .03, yaw_rate = .04}, 1) == 0)
	sport_yaw := Vehicle_State {
		speed      = .5,
		steering   = .7,
		velocity_x = .5,
	}; heavy_yaw :=
		sport_yaw; vehicle_apply_yaw(&sport_yaw, false, VEHICLE_TUNE_SPORT); vehicle_apply_yaw(&heavy_yaw, false, VEHICLE_TUNE_HEAVY); assert(sport_yaw.yaw_rate > heavy_yaw.yaw_rate && sport_yaw.heading == sport_yaw.yaw_rate); before_yaw := sport_yaw.yaw_rate; sport_yaw.steering = 0; vehicle_apply_yaw(&sport_yaw, false, VEHICLE_TUNE_SPORT); assert(sport_yaw.yaw_rate > 0 && sport_yaw.yaw_rate < before_yaw)
	coast_corner := Vehicle_State {
		speed      = .4,
		steering   = .7,
		velocity_x = .4,
	}; power_corner :=
		coast_corner; brake_corner := coast_corner; vehicle_apply_yaw(&coast_corner, false, VEHICLE_TUNE_STANDARD, 0); vehicle_apply_yaw(&power_corner, false, VEHICLE_TUNE_STANDARD, 1); vehicle_apply_yaw(&brake_corner, false, VEHICLE_TUNE_STANDARD, -1); near_neutral_power_load := vehicle_yaw_load_factor(Vehicle_State{speed = .001, velocity_x = .001}, 1, false); near_neutral_brake_load := vehicle_yaw_load_factor(Vehicle_State{speed = .001, velocity_x = .001}, -1, false); assert(brake_corner.yaw_rate > coast_corner.yaw_rate && coast_corner.yaw_rate > power_corner.yaw_rate && near_neutral_power_load < 1 && near_neutral_brake_load > 1 && 1 - near_neutral_power_load < .01 && near_neutral_brake_load - 1 < .01); assert(math.abs(vehicle_yaw_load_factor(Vehicle_State{speed = -.4, velocity_x = -.4}, 1, false) - 1.10) < .0001 && math.abs(vehicle_yaw_load_factor(Vehicle_State{speed = -.4, velocity_x = -.4}, -1, false) - .94) < .0001 && vehicle_yaw_load_factor(coast_corner, 1, true) == 1)
	normal_yaw := Vehicle_State {
		speed    = .5,
		yaw_rate = .02,
	}; drift_yaw :=
		normal_yaw; vehicle_apply_yaw(&normal_yaw, false, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw(&drift_yaw, true, VEHICLE_TUNE_STANDARD); assert(drift_yaw.yaw_rate > normal_yaw.yaw_rate)
	normal_blended_yaw := Vehicle_State {
		speed      = .4,
		velocity_x = .4,
		steering   = .7,
		yaw_rate   = .02,
	}; half_blended_yaw :=
		normal_blended_yaw; full_blended_yaw := normal_blended_yaw; vehicle_apply_yaw_blended(&normal_blended_yaw, 0, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw_blended(&half_blended_yaw, .5, VEHICLE_TUNE_STANDARD); vehicle_apply_yaw_blended(&full_blended_yaw, 1, VEHICLE_TUNE_STANDARD); assert(normal_blended_yaw.yaw_rate < half_blended_yaw.yaw_rate && half_blended_yaw.yaw_rate < full_blended_yaw.yaw_rate)
	forward_slide := Vehicle_State {
		heading    = 0,
		velocity_x = .32,
		velocity_y = .16,
	}; reverse_slide := Vehicle_State {
		heading    = 0,
		velocity_x = -.32,
		velocity_y = .16,
	}; forward_alignment := vehicle_self_aligning_yaw(
		forward_slide,
		false,
		VEHICLE_TUNE_STANDARD,
	); reverse_alignment := vehicle_self_aligning_yaw(reverse_slide, false, VEHICLE_TUNE_STANDARD); assert(forward_alignment > 0 && reverse_alignment < 0 && math.abs(forward_alignment) <= .010); assert(math.abs(vehicle_self_aligning_yaw(forward_slide, true, VEHICLE_TUNE_STANDARD)) < math.abs(forward_alignment)); blended_alignment := vehicle_self_aligning_yaw_blended(forward_slide, .5, VEHICLE_TUNE_STANDARD); assert(math.abs(blended_alignment) < math.abs(forward_alignment) && math.abs(blended_alignment) > math.abs(vehicle_self_aligning_yaw(forward_slide, true, VEHICLE_TUNE_STANDARD))); assert(vehicle_self_aligning_yaw(Vehicle_State{velocity_x = .04, velocity_y = .02}, false, VEHICLE_TUNE_STANDARD) == 0); aligned_slide := forward_slide; vehicle_apply_yaw(&aligned_slide, false, VEHICLE_TUNE_STANDARD); assert(aligned_slide.yaw_rate > 0 && aligned_slide.heading > 0 && vehicle_lateral_slip_ratio(aligned_slide) < vehicle_lateral_slip_ratio(forward_slide))
	rolling_body := Vehicle_State {
		velocity_x = .46,
		yaw_rate   = .045,
	}; force_rolling_body := Vehicle_State {
		velocity_x                   = .46,
		chassis_lateral_acceleration = 1,
	}; assert(
		vehicle_body_roll_target(rolling_body, false) < 0 &&
		math.abs(vehicle_body_roll_target(rolling_body, false)) <= .068 &&
		math.abs(vehicle_body_roll_target(force_rolling_body, false)) >
			math.abs(vehicle_body_roll_target(rolling_body, false)),
	); assert(math.abs(vehicle_body_roll_target(rolling_body, true)) > math.abs(vehicle_body_roll_target(rolling_body, false))); stationary_body := Vehicle_State {
		yaw_rate = .045,
	}; assert(
		vehicle_body_roll_target(stationary_body, false) == 0,
	); vehicle_update_body_roll(&rolling_body, false); assert(rolling_body.body_roll < 0 && math.abs(rolling_body.body_roll) < .068); rolling_body.yaw_rate = 0; before_body_roll := math.abs(rolling_body.body_roll); vehicle_update_body_roll(&rolling_body, false); assert(math.abs(rolling_body.body_roll) < before_body_roll)
	reverse_rolling_body := Vehicle_State {
		velocity_x = -.46,
		yaw_rate   = -.045,
	}; neutral_rolling_body := Vehicle_State {
		velocity_y = .46,
		yaw_rate   = .045,
	}; assert(
		math.abs(
			vehicle_body_roll_target(reverse_rolling_body, false) -
			vehicle_body_roll_target(Vehicle_State{velocity_x = .46, yaw_rate = .045}, false),
		) <
			.0001 &&
		vehicle_body_roll_target(neutral_rolling_body, false) == 0,
	)
	reversing_body_roll := Vehicle_State {
		velocity_x                   = .46,
		chassis_lateral_acceleration = 1,
		body_roll                    = .04,
	}; vehicle_update_body_roll(
		&reversing_body_roll,
		false,
	); assert(reversing_body_roll.body_roll < .03)
	roll_probe := Vehicle_State {
		velocity_x = .46,
		yaw_rate   = .045,
	}; normal_roll_target := math.abs(
		vehicle_body_roll_target_blended(roll_probe, 0),
	); half_roll_target := math.abs(vehicle_body_roll_target_blended(roll_probe, .5)); drift_roll_target := math.abs(vehicle_body_roll_target_blended(roll_probe, 1)); assert(normal_roll_target < half_roll_target && half_roll_target < drift_roll_target && math.abs(half_roll_target - (normal_roll_target + drift_roll_target) * .5) < .0001)
	assert(
		vehicle_body_pitch_target(1) > 0 &&
		vehicle_body_pitch_target(-1) < 0 &&
		math.abs(vehicle_body_pitch_target(-1)) > vehicle_body_pitch_target(1),
	); pitching_body := Vehicle_State {
		chassis_acceleration = 1,
	}; vehicle_update_body_pitch(
		&pitching_body,
	); assert(pitching_body.body_pitch > 0 && pitching_body.body_pitch < .038); reversing_body_pitch := Vehicle_State {
		chassis_acceleration = -1,
		body_pitch           = .04,
	}; vehicle_update_body_pitch(
		&reversing_body_pitch,
	); assert(reversing_body_pitch.body_pitch < .03); pitching_body.chassis_acceleration = -1; for _ in 0 ..< 20 do vehicle_update_body_pitch(&pitching_body); assert(pitching_body.body_pitch < 0 && pitching_body.body_pitch > -.052); pitching_body.chassis_acceleration = 0; before_pitch_settle := math.abs(pitching_body.body_pitch); vehicle_update_body_pitch(&pitching_body); assert(math.abs(pitching_body.body_pitch) < before_pitch_settle)
	compliance_body := Vehicle_State {
		velocity_x = .46,
		yaw_rate   = .045,
	}; assert(
		math.abs(vehicle_body_roll_target(compliance_body, true, VEHICLE_TUNE_SPORT)) <
			math.abs(vehicle_body_roll_target(compliance_body, true, VEHICLE_TUNE_STANDARD)) &&
		math.abs(vehicle_body_roll_target(compliance_body, true, VEHICLE_TUNE_HEAVY)) >
			math.abs(vehicle_body_roll_target(compliance_body, true, VEHICLE_TUNE_STANDARD)),
	); assert(vehicle_body_pitch_target(1, VEHICLE_TUNE_SPORT) < vehicle_body_pitch_target(1, VEHICLE_TUNE_STANDARD) && vehicle_body_pitch_target(1, VEHICLE_TUNE_HEAVY) > vehicle_body_pitch_target(1, VEHICLE_TUNE_STANDARD))
	sport_settle := Vehicle_State {
		body_roll  = .05,
		body_pitch = .04,
	}; heavy_settle :=
		sport_settle; vehicle_update_body_roll(&sport_settle, false, VEHICLE_TUNE_SPORT); vehicle_update_body_roll(&heavy_settle, false, VEHICLE_TUNE_HEAVY); vehicle_update_body_pitch(&sport_settle, VEHICLE_TUNE_SPORT); vehicle_update_body_pitch(&heavy_settle, VEHICLE_TUNE_HEAVY); assert(math.abs(sport_settle.body_roll) < math.abs(heavy_settle.body_roll) && math.abs(sport_settle.body_pitch) < math.abs(heavy_settle.body_pitch))
	sport_drive := new(
		Game,
	); defer free(sport_drive); sport_drive.screen = .Exterior; sport_drive.driving_vehicle = 5; initialize_city_vehicles(sport_drive); sport_drive.vehicles[5].x = city_world(82); sport_drive.vehicles[5].y = city_world(34); sport_drive.vehicles[5].heading = 0; sport_drive.keys[.W] = true; for _ in 0 ..< 20 do update_city(sport_drive)
	heavy_drive := new(
		Game,
	); defer free(heavy_drive); heavy_drive.screen = .Exterior; heavy_drive.driving_vehicle = 10; initialize_city_vehicles(heavy_drive); heavy_drive.vehicles[10].x = city_world(82); heavy_drive.vehicles[10].y = city_world(34); heavy_drive.vehicles[10].heading = 0; heavy_drive.keys[.W] = true; for _ in 0 ..< 20 do update_city(heavy_drive); assert(sport_drive.vehicles[5].speed > heavy_drive.vehicles[10].speed)
	assert(
		city_driving_surface(city_world(82), city_world(34)) == .Road &&
		city_driving_surface(city_world(75), city_world(45)) == .Open_Ground &&
		city_driving_surface_label(.Open_Ground) == "ROUGH",
	); split_surface := Vehicle_State {
		x          = city_world(3.8),
		y          = city_world(45),
		heading    = f32(math.PI / 2),
		velocity_y = .3,
	}; split_roughness, split_bias := vehicle_surface_contact(
		split_surface,
	); split_surface.surface_lateral_bias = split_bias; reverse_split_surface := split_surface; reverse_split_surface.velocity_y = -.3; entering_bias := vehicle_surface_bias_step(0, -1); recovering_bias := vehicle_surface_bias_step(entering_bias, 0); assert(vehicle_surface_roughness(Vehicle_State{x = city_world(2), y = city_world(45), heading = 0}) == 0 && vehicle_surface_roughness(Vehicle_State{x = city_world(5), y = city_world(45), heading = 0}) == 1 && split_roughness > 0 && split_roughness < 1 && split_bias < 0 && entering_bias < 0 && entering_bias > -1 && math.abs(recovering_bias) < math.abs(entering_bias)); coast_split_yaw := vehicle_surface_drag_yaw(split_surface); braking_split_yaw := vehicle_surface_drag_yaw(split_surface, -1); assert(coast_split_yaw < 0 && braking_split_yaw < coast_split_yaw && math.abs(braking_split_yaw) > math.abs(coast_split_yaw) && vehicle_surface_drag_yaw(reverse_split_surface) > 0 && math.abs(vehicle_surface_drag_yaw(split_surface) + vehicle_surface_drag_yaw(reverse_split_surface)) < .0001 && vehicle_surface_drag_yaw(Vehicle_State{x = city_world(3.8), y = city_world(45), heading = f32(math.PI / 2), velocity_y = .03, surface_lateral_bias = -1}) == 0); assert(vehicle_surface_blend_label(0) == "ROAD" && vehicle_surface_blend_label(.19) == "ROAD" && vehicle_surface_blend_label(.20) == "MIXED" && vehicle_surface_blend_label(.8) == "MIXED" && vehicle_surface_blend_label(.81) == "ROUGH" && vehicle_surface_blend_label(2) == "ROUGH"); rough_tune := vehicle_tune_for_surface(VEHICLE_TUNE_STANDARD, .Open_Ground); half_rough_tune := vehicle_tune_for_surface_blend(VEHICLE_TUNE_STANDARD, .5); assert(rough_tune.max_forward < VEHICLE_TUNE_STANDARD.max_forward && rough_tune.acceleration < VEHICLE_TUNE_STANDARD.acceleration && rough_tune.longitudinal_grip < VEHICLE_TUNE_STANDARD.longitudinal_grip && rough_tune.lateral_grip < VEHICLE_TUNE_STANDARD.lateral_grip); assert(half_rough_tune.max_forward < VEHICLE_TUNE_STANDARD.max_forward && half_rough_tune.max_forward > rough_tune.max_forward && half_rough_tune.longitudinal_grip < VEHICLE_TUNE_STANDARD.longitudinal_grip && half_rough_tune.longitudinal_grip > rough_tune.longitudinal_grip); entering_surface := vehicle_surface_blend_step(0, .Open_Ground); half_entering_surface := vehicle_surface_blend_step_to(0, .5); leaving_surface := vehicle_surface_blend_step(1, .Road); assert(entering_surface > 0 && entering_surface < 1 && half_entering_surface > 0 && half_entering_surface < entering_surface && leaving_surface > 0 && leaving_surface < 1 && leaving_surface < 1 - entering_surface); surface_progress := f32(0); for _ in 0 ..< 80 do surface_progress = vehicle_surface_blend_step(surface_progress, .Open_Ground); assert(surface_progress == 1); for _ in 0 ..< 80 do surface_progress = vehicle_surface_blend_step(surface_progress, .Road); assert(surface_progress == 0)
	stable_ratio_speed := f32(
		.18,
	); road_reference_torque := vehicle_drive_torque_for_reference(VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_STANDARD, stable_ratio_speed, true); rough_reference_torque := vehicle_drive_torque_for_reference(rough_tune, VEHICLE_TUNE_STANDARD, stable_ratio_speed, true); assert(rough_reference_torque < road_reference_torque && vehicle_engine_frequency(Vehicle_State{speed = stable_ratio_speed}, VEHICLE_TUNE_STANDARD) == vehicle_engine_frequency(Vehicle_State{speed = stable_ratio_speed, surface_blend = 1}, VEHICLE_TUNE_STANDARD))
	rough_entry_speed :=
		VEHICLE_TUNE_STANDARD.max_forward * .9; rough_entry_momentum := Vehicle_State {
		speed      = rough_entry_speed,
		velocity_x = rough_entry_speed,
	}; vehicle_apply_throttle_for_reference(
		&rough_entry_momentum,
		rough_tune,
		VEHICLE_TUNE_STANDARD,
		1,
	); assert(rough_entry_momentum.speed == rough_entry_speed && rough_entry_momentum.speed <= VEHICLE_TUNE_STANDARD.max_forward && rough_entry_momentum.speed > rough_tune.max_forward); rough_entry_momentum.speed *= vehicle_drag_factor_blended(VEHICLE_TUNE_STANDARD, 1, 0, 1, 0, rough_entry_momentum.speed / VEHICLE_TUNE_STANDARD.max_forward); assert(rough_entry_momentum.speed > rough_entry_speed * .9 && rough_entry_momentum.speed < rough_entry_speed); rough_cruise := Vehicle_State{}; for _ in 0 ..< 240 {rough_cruise.velocity_x = rough_cruise.speed; vehicle_apply_throttle_for_reference(&rough_cruise, rough_tune, VEHICLE_TUNE_STANDARD, 1); rough_cruise.speed *= vehicle_drag_factor_blended(VEHICLE_TUNE_STANDARD, 1, 0, 1, 0, rough_cruise.speed / VEHICLE_TUNE_STANDARD.max_forward)}; rough_reverse_cruise := Vehicle_State{}; for _ in 0 ..< 240 {rough_reverse_cruise.velocity_x = rough_reverse_cruise.speed; vehicle_apply_throttle_for_reference(&rough_reverse_cruise, rough_tune, VEHICLE_TUNE_STANDARD, -1); rough_reverse_cruise.speed *= vehicle_drag_factor_blended(VEHICLE_TUNE_STANDARD, 1, 0, -1, 0, math.abs(rough_reverse_cruise.speed) / VEHICLE_TUNE_STANDARD.max_reverse)}; assert(math.abs(rough_cruise.speed - rough_tune.max_forward) < .035 && math.abs(math.abs(rough_reverse_cruise.speed) - rough_tune.max_reverse) < .03 && math.abs(rough_reverse_cruise.speed) < VEHICLE_TUNE_STANDARD.max_reverse)
	road_drive := new(
		Game,
	); defer free(road_drive); road_drive.screen = .Exterior; road_drive.driving_vehicle = 0; initialize_city_vehicles(road_drive); road_drive.vehicles[0] = {
		x       = city_world(82),
		y       = city_world(34),
		heading = 0,
	}; road_drive.keys[.W] = true; for _ in 0 ..< 20 do update_city(road_drive)
	rough_drive := new(
		Game,
	); defer free(rough_drive); rough_drive.screen = .Exterior; rough_drive.driving_vehicle = 0; initialize_city_vehicles(rough_drive); rough_drive.vehicles[0] = {
		x       = city_world(75),
		y       = city_world(45),
		heading = 0,
	}; rough_drive.keys[.W] =
		true; for _ in 0 ..< 20 do update_city(rough_drive); assert(road_drive.vehicles[0].speed > rough_drive.vehicles[0].speed)
	rough_entry := new(
		Game,
	); defer free(rough_entry); rough_entry.screen = .Exterior; rough_entry.driving_vehicle = 0; initialize_city_vehicles(rough_entry); rough_entry.vehicles[0] = {
		x          = city_world(75),
		y          = city_world(45),
		heading    = 0,
		speed      = .55,
		velocity_x = .55,
	}; update_city(
		rough_entry,
	); assert(rough_entry.vehicles[0].speed < .55 && rough_entry.vehicles[0].speed > rough_tune.max_forward)
	// Swept probes catch a parked car even when an exaggerated one-frame move
	// would finish beyond it. Exit interaction is unavailable until nearly still.
	sweep_test := new(
		Game,
	); defer free(sweep_test); initialize_city_vehicles(sweep_test); sweep_test.vehicles[0] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 4.3,
		velocity_x = 4.3,
	}; sweep_test.vehicles[1] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; assert(
		vehicle_position_clear(sweep_test, 10, 2, 0, 0) &&
		vehicle_position_clear(sweep_test, 14.3, 2, 0, 0),
	); sweep_impact_event: f32; assert(vehicle_swept_move(sweep_test, &sweep_test.vehicles[0], 0, true, &sweep_impact_event)); assert(sweep_impact_event == 1 && sweep_test.vehicles[0].x < 12.2 && sweep_test.vehicles[0].velocity_x < 0 && sweep_test.vehicles[0].impact == 1 && sweep_test.vehicles[0].body_pitch < 0 && sweep_test.vehicles[1].velocity_x > 0 && sweep_test.vehicles[1].body_pitch > 0 && math.abs(sweep_test.vehicles[0].speed - vehicle_longitudinal_speed(sweep_test.vehicles[0])) < .0001)
	glance_test := new(
		Game,
	); defer free(glance_test); initialize_city_vehicles(glance_test); glance_test.vehicles[0] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
		velocity_y = .5,
	}; glance_test.vehicles[1] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; glance_travel: f32; assert(vehicle_swept_move(glance_test, &glance_test.vehicles[0], 0, true, nil, &glance_travel)); glance_displacement := f32(math.sqrt(f64((glance_test.vehicles[0].x - 10) * (glance_test.vehicles[0].x - 10) + (glance_test.vehicles[0].y - 2) * (glance_test.vehicles[0].y - 2)))); assert(glance_test.vehicles[0].velocity_x < 0 && glance_test.vehicles[0].velocity_y > 0 && math.abs(glance_test.vehicles[0].velocity_y) > math.abs(glance_test.vehicles[0].velocity_x) && glance_test.vehicles[0].y > 2.2 && glance_travel > glance_displacement && glance_test.vehicles[0].speed < 0 && glance_test.vehicles[0].yaw_rate < 0 && glance_test.vehicles[1].yaw_rate < 0 && glance_test.vehicles[1].velocity_y > 0 && glance_test.vehicles[1].velocity_y < glance_test.vehicles[1].velocity_x * .06 && math.abs(glance_test.vehicles[0].speed - vehicle_longitudinal_speed(glance_test.vehicles[0])) < .0001); sync_test := Vehicle_State {
		heading    = f32(math.PI / 2),
		speed      = .5,
		velocity_x = .1,
		velocity_y = -.2,
	}; vehicle_sync_driveline_to_velocity(
		&sync_test,
	); assert(math.abs(sync_test.speed + .2) < .0001)
	assert(glance_test.vehicles[1].yaw_rate != 0); centered_source := Vehicle_State {
		x = 10,
		y = 2,
	}; centered_target := Vehicle_State {
		x = 12.2,
		y = 2,
	}; assert(
		vehicle_collision_yaw_impulse(centered_source, centered_target, 2, 0, .2) == 0,
	); assert(math.abs(vehicle_collision_yaw_impulse(centered_source, centered_target, 2, .5, .2)) <= .12)
	assert(
		vehicle_collision_yaw_rate(.10, .08) == .12 &&
		vehicle_collision_yaw_rate(-.10, -.08) == -.12 &&
		vehicle_collision_yaw_rate(.04, -.02) == .02,
	)
	assert(
		vehicle_impact_strength_from_delta(0, 0) == 0 &&
		vehicle_impact_strength_from_delta(.29, 0) == .5 &&
		vehicle_impact_strength_from_delta(.58, 0) == 1 &&
		vehicle_impact_strength_from_delta(.3, .3) > vehicle_impact_strength_from_delta(.3, 0),
	)
	assert(
		vehicle_impact_is_new_event(0, .1) &&
		!vehicle_impact_is_new_event(.82, 1) &&
		vehicle_impact_is_new_event(.70, 1) &&
		!vehicle_impact_is_new_event(.41, .5),
	)
	directional_impact := Vehicle_State {
		heading = 0,
	}; vehicle_record_impact(
		&directional_impact,
		-.29,
		0,
		.5,
	); assert(directional_impact.impact == .5 && directional_impact.impact_forward == -1 && directional_impact.impact_side == 0 && directional_impact.impact_time == 0); vehicle_record_impact(&directional_impact, 0, .1, .1); assert(directional_impact.impact_forward == -1 && directional_impact.impact_side == 0); vehicle_record_impact(&directional_impact, 0, .58, 1); assert(directional_impact.impact == 1 && directional_impact.impact_forward == 0 && directional_impact.impact_side == 1 && directional_impact.impact_time == 0); vehicle_decay_impact(&directional_impact); assert(directional_impact.impact == .82 && directional_impact.impact_side == 1 && directional_impact.impact_time == FIXED_TIMESTEP)
	repeated_impact :=
		Vehicle_State{}; vehicle_record_impact(&repeated_impact, -.29, 0, .5); vehicle_decay_impact(&repeated_impact); repeated_phase := repeated_impact.impact_time; vehicle_record_impact(&repeated_impact, -.29, 0, .5); assert(repeated_impact.impact == .5 && repeated_impact.impact_time == repeated_phase && vehicle_camera_impact_offset(repeated_impact, .37) != Vec2{}); for _ in 0 ..< 6 do vehicle_decay_impact(&repeated_impact); vehicle_record_impact(&repeated_impact, -.29, 0, .5); assert(repeated_impact.impact_time == 0)
	collision_roll_load := Vehicle_State {
			heading = 0,
		}; vehicle_record_collision_lateral_load(
		&collision_roll_load,
		.3,
		0,
	); assert(collision_roll_load.chassis_lateral_acceleration == 0); vehicle_record_collision_lateral_load(&collision_roll_load, 0, .3); assert(collision_roll_load.chassis_lateral_acceleration == 1); vehicle_record_collision_lateral_load(&collision_roll_load, 0, -.01); assert(collision_roll_load.chassis_lateral_acceleration == 1)
	assert(
		vehicle_collision_pitch_impulse(Vehicle_State{heading = 0}, .4, 0, VEHICLE_TUNE_STANDARD) >
			0 &&
		vehicle_collision_pitch_impulse(
			Vehicle_State{heading = 0},
			-.4,
			0,
			VEHICLE_TUNE_STANDARD,
		) <
			0 &&
		math.abs(
			vehicle_collision_pitch_impulse(
				Vehicle_State{heading = 0},
				10,
				0,
				VEHICLE_TUNE_STANDARD,
			),
		) ==
			.065,
	)
	assert(
		VEHICLE_TUNE_SPORT.mass < VEHICLE_TUNE_STANDARD.mass &&
		VEHICLE_TUNE_STANDARD.mass < VEHICLE_TUNE_UTILITY.mass &&
		VEHICLE_TUNE_UTILITY.mass < VEHICLE_TUNE_HEAVY.mass,
	); assert(vehicle_collision_transfer_factor(VEHICLE_TUNE_HEAVY, VEHICLE_TUNE_SPORT) > vehicle_collision_transfer_factor(VEHICLE_TUNE_SPORT, VEHICLE_TUNE_HEAVY) && vehicle_collision_transfer_factor(VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_STANDARD) == .20)
	assert(
		vehicle_collision_rebound(VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_HEAVY) >
			vehicle_collision_rebound(VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_SPORT) &&
		vehicle_collision_rebound(VEHICLE_TUNE_STANDARD, VEHICLE_TUNE_STANDARD) ==
			VEHICLE_TUNE_STANDARD.collision_rebound,
	)
	axis_contact := vehicle_resolve_car_contact_velocity(
		2,
		.5,
		-1,
		0,
		.72,
		.12,
	); diagonal_scale := f32(math.sqrt(f64(.5))); diagonal_contact := vehicle_resolve_car_contact_velocity((2 - .5) * diagonal_scale, (2 + .5) * diagonal_scale, -diagonal_scale, -diagonal_scale, .72, .12); assert(math.abs(axis_contact.x + .24) < .0001 && math.abs(axis_contact.y - .36) < .0001 && math.abs(diagonal_contact.x - (axis_contact.x - axis_contact.y) * diagonal_scale) < .0001 && math.abs(diagonal_contact.y - (axis_contact.x + axis_contact.y) * diagonal_scale) < .0001); separating_contact := vehicle_resolve_car_contact_velocity(-.2, 0, -1, 0, .72, .12); assert(separating_contact == Vec2{-.2, 0})
	axis_transfer := vehicle_car_contact_transfer(
		2,
		.5,
		-1,
		0,
		.2,
	); diagonal_transfer := vehicle_car_contact_transfer((2 - .5) * diagonal_scale, (2 + .5) * diagonal_scale, -diagonal_scale, -diagonal_scale, .2); assert(math.abs(axis_transfer.x - .4) < .0001 && axis_transfer.y > 0 && axis_transfer.y < .02 && math.abs(diagonal_transfer.x - (axis_transfer.x - axis_transfer.y) * diagonal_scale) < .0001 && math.abs(diagonal_transfer.y - (axis_transfer.x + axis_transfer.y) * diagonal_scale) < .0001 && vehicle_car_contact_transfer(-.2, 0, -1, 0, .2) == Vec2{})
	axis_tangent_step := vehicle_car_contact_tangent_step(
		.1,
		.025,
		-1,
		0,
	); diagonal_tangent_step := vehicle_car_contact_tangent_step((.1 - .025) * diagonal_scale, (.1 + .025) * diagonal_scale, -diagonal_scale, -diagonal_scale); assert(axis_tangent_step == Vec2{0, .025} && math.abs(diagonal_tangent_step.x - (axis_tangent_step.x - axis_tangent_step.y) * diagonal_scale) < .0001 && math.abs(diagonal_tangent_step.y - (axis_tangent_step.x + axis_tangent_step.y) * diagonal_scale) < .0001)
	assert(
		vehicle_wall_tangent_retention() > .9 &&
		vehicle_wall_tangent_retention() > VEHICLE_TUNE_HEAVY.collision_tangent_retention,
	)
	wall_glance := new(
		Game,
	); defer free(wall_glance); initialize_city_vehicles(wall_glance); wall_glance.vehicles[0] = {
		x          = .55,
		y          = city_world(20),
		heading    = f32(math.PI / 2),
		speed      = .4,
		velocity_x = -4,
		velocity_y = .4,
	}; wall_glance_start_y :=
		wall_glance.vehicles[0].y; assert(vehicle_position_clear(wall_glance, wall_glance.vehicles[0].x, wall_glance.vehicles[0].y, wall_glance.vehicles[0].heading, 0)); assert(vehicle_swept_move(wall_glance, &wall_glance.vehicles[0], 0)); assert(wall_glance.vehicles[0].velocity_x > 0 && wall_glance.vehicles[0].velocity_y > .36 && wall_glance.vehicles[0].y > wall_glance_start_y)
	sport_collision := new(
		Game,
	); defer free(sport_collision); initialize_city_vehicles(sport_collision); sport_collision.vehicles[5] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
		velocity_y = .5,
	}; sport_collision.vehicles[1] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; assert(
		vehicle_swept_move(sport_collision, &sport_collision.vehicles[5], 5),
	); heavy_collision := new(Game); defer free(heavy_collision); initialize_city_vehicles(heavy_collision); heavy_collision.vehicles[10] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
		velocity_y = .5,
	}; heavy_collision.vehicles[1] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; assert(
		vehicle_swept_move(heavy_collision, &heavy_collision.vehicles[10], 10),
	); assert(math.abs(heavy_collision.vehicles[10].velocity_y) > math.abs(sport_collision.vehicles[5].velocity_y) && math.abs(heavy_collision.vehicles[10].velocity_x) < math.abs(sport_collision.vehicles[5].velocity_x) && heavy_collision.vehicles[1].velocity_x > sport_collision.vehicles[1].velocity_x && heavy_collision.vehicles[1].impact > sport_collision.vehicles[1].impact); assert(VEHICLE_TUNE_HEAVY.collision_tangent_retention > VEHICLE_TUNE_SPORT.collision_tangent_retention && VEHICLE_TUNE_HEAVY.collision_rebound < VEHICLE_TUNE_SPORT.collision_rebound)
	same_direction_collision := new(
		Game,
	); defer free(same_direction_collision); initialize_city_vehicles(same_direction_collision); same_direction_collision.vehicles[0] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
	}; same_direction_collision.vehicles[1] = {
		x          = 12.2,
		y          = 2,
		heading    = 0,
		speed      = 1.6,
		velocity_x = 1.6,
	}; assert(
		vehicle_swept_move(same_direction_collision, &same_direction_collision.vehicles[0], 0),
	); same_direction_gain := same_direction_collision.vehicles[1].velocity_x - 1.6; assert(same_direction_collision.vehicles[0].velocity_x > 0); oncoming_collision := new(Game); defer free(oncoming_collision); initialize_city_vehicles(oncoming_collision); oncoming_collision.vehicles[0] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
	}; oncoming_collision.vehicles[1] = {
		x          = 12.2,
		y          = 2,
		heading    = f32(math.PI),
		speed      = 1,
		velocity_x = -1,
	}; assert(
		vehicle_swept_move(oncoming_collision, &oncoming_collision.vehicles[0], 0),
	); oncoming_gain := oncoming_collision.vehicles[1].velocity_x + 1; assert(oncoming_collision.vehicles[0].velocity_x < 0 && same_direction_gain > 0 && oncoming_gain > same_direction_gain && oncoming_collision.vehicles[0].impact > same_direction_collision.vehicles[0].impact)
	passive_test := new(
		Game,
	); defer free(passive_test); initialize_city_vehicles(passive_test); passive_test.driving_vehicle = -1; passive_test.vehicles[1] = {
		x              = 20,
		y              = 2,
		heading        = 0,
		speed          = .4,
		velocity_x     = .4,
		yaw_rate       = .04,
		handbrake_slip = 1,
	}; passive_start :=
		passive_test.vehicles[1].x; vehicle_update_passive(passive_test, 1); assert(passive_test.vehicles[1].x > passive_start && passive_test.vehicles[1].velocity_x < .4 && passive_test.vehicles[1].heading > 0 && passive_test.vehicles[1].body_roll < 0 && passive_test.vehicles[1].handbrake_slip < 1); for _ in 0 ..< 100 do vehicle_update_passive(passive_test, 1); assert(vehicle_actual_speed(passive_test.vehicles[1]) < .002 && math.abs(passive_test.vehicles[1].yaw_rate) < .0002 && passive_test.vehicles[1].handbrake_slip == 0)
	passive_side_slide := new(
		Game,
	); defer free(passive_side_slide); initialize_city_vehicles(passive_side_slide); passive_side_slide.vehicles[1] = {
		x          = 20,
		y          = 2,
		heading    = 0,
		velocity_x = .3,
		velocity_y = .2,
	}; uniform_passive_lateral :=
		.2 *
		vehicle_passive_momentum_retention(
			vehicle_tune(1),
		); vehicle_update_passive(passive_side_slide, 1); assert(passive_side_slide.vehicles[1].velocity_y < uniform_passive_lateral && passive_side_slide.vehicles[1].yaw_rate > 0 && passive_side_slide.vehicles[1].heading > 0)
	assert(
		passive_side_slide.vehicles[1].chassis_lateral_acceleration < 0 &&
		passive_side_slide.vehicles[1].body_roll > 0 &&
		passive_side_slide.vehicles[1].acceleration_feedback < 0,
	)
	assert(
		vehicle_passive_momentum_retention(VEHICLE_TUNE_SPORT) <
			vehicle_passive_momentum_retention(VEHICLE_TUNE_STANDARD) &&
		vehicle_passive_momentum_retention(VEHICLE_TUNE_STANDARD) <
			vehicle_passive_momentum_retention(VEHICLE_TUNE_HEAVY),
	); same_mass_slide_tune := VEHICLE_TUNE_STANDARD; same_mass_slide_tune.collision_tangent_retention = .1; assert(vehicle_passive_momentum_retention(same_mass_slide_tune) == vehicle_passive_momentum_retention(VEHICLE_TUNE_STANDARD) && vehicle_passive_yaw_retention(same_mass_slide_tune) == vehicle_passive_yaw_retention(VEHICLE_TUNE_STANDARD)); sport_passive := new(Game); defer free(sport_passive); initialize_city_vehicles(sport_passive); sport_passive.vehicles[5] = {
		x          = 20,
		y          = 2,
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; heavy_passive := new(
		Game,
	); defer free(heavy_passive); initialize_city_vehicles(heavy_passive); heavy_passive.vehicles[10] = {
		x          = 20,
		y          = 2,
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; vehicle_update_passive(
		sport_passive,
		5,
	); vehicle_update_passive(heavy_passive, 10); assert(heavy_passive.vehicles[10].velocity_x > sport_passive.vehicles[5].velocity_x)
	assert(
		vehicle_passive_yaw_retention(VEHICLE_TUNE_SPORT) <
			vehicle_passive_yaw_retention(VEHICLE_TUNE_STANDARD) &&
		vehicle_passive_yaw_retention(VEHICLE_TUNE_STANDARD) <
			vehicle_passive_yaw_retention(VEHICLE_TUNE_HEAVY),
	); sport_passive.vehicles[5] = {
		x        = 20,
		y        = 2,
		heading  = 0,
		yaw_rate = .04,
	}; heavy_passive.vehicles[10] = {
		x        = 20,
		y        = 2,
		heading  = 0,
		yaw_rate = .04,
	}; vehicle_update_passive(
		sport_passive,
		5,
	); vehicle_update_passive(heavy_passive, 10); assert(heavy_passive.vehicles[10].yaw_rate > sport_passive.vehicles[5].yaw_rate && heavy_passive.vehicles[10].heading > sport_passive.vehicles[5].heading)
	sport_passive.vehicles[5] = {
		x                     = 20,
		y                     = 2,
		heading               = 0,
		body_pitch            = .05,
		acceleration_feedback = 0,
	}; heavy_passive.vehicles[10] = {
		x                     = 20,
		y                     = 2,
		heading               = 0,
		body_pitch            = .05,
		acceleration_feedback = 0,
	}; vehicle_update_passive(
		sport_passive,
		5,
	); vehicle_update_passive(heavy_passive, 10); assert(math.abs(sport_passive.vehicles[5].body_pitch) < math.abs(heavy_passive.vehicles[10].body_pitch))
	road_passive := new(
		Game,
	); defer free(road_passive); initialize_city_vehicles(road_passive); road_passive.vehicles[0] = {
		x          = city_world(82),
		y          = city_world(34),
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; rough_passive := new(
		Game,
	); defer free(rough_passive); initialize_city_vehicles(rough_passive); rough_passive.vehicles[0] = {
		x          = city_world(75),
		y          = city_world(45),
		heading    = 0,
		speed      = .4,
		velocity_x = .4,
	}; vehicle_update_passive(
		road_passive,
		0,
	); vehicle_update_passive(rough_passive, 0); assert(road_passive.vehicles[0].surface_blend == 0 && rough_passive.vehicles[0].surface_blend > 0 && rough_passive.vehicles[0].velocity_x < road_passive.vehicles[0].velocity_x)
	chain_collision := new(
		Game,
	); defer free(chain_collision); initialize_city_vehicles(chain_collision); chain_collision.driving_vehicle = -1; chain_collision.vehicles[0] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
	}; chain_collision.vehicles[1] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; chain_collision.vehicles[2] = {
		x       = 14.3,
		y       = 2,
		heading = 0,
	}; vehicle_update_passive(
		chain_collision,
		0,
	); assert(chain_collision.vehicles[1].velocity_x > 0 && chain_collision.vehicles[2].velocity_x == 0); chain_incoming := chain_collision.vehicles[1].velocity_x; vehicle_update_passive(chain_collision, 1); assert(chain_collision.vehicles[2].velocity_x > 0 && chain_collision.vehicles[2].velocity_x < chain_incoming)
	passive_hits_driver := new(
		Game,
	); defer free(passive_hits_driver); passive_hits_driver.screen = .Exterior; passive_hits_driver.driving_vehicle = 0; initialize_city_vehicles(passive_hits_driver); passive_hits_driver.vehicles[0] = {
		x       = 12.2,
		y       = 2,
		heading = 0,
	}; passive_hits_driver.vehicles[1] = {
		x          = 10,
		y          = 2,
		heading    = 0,
		speed      = 2,
		velocity_x = 2,
		velocity_y = .5,
	}; update_city(
		passive_hits_driver,
	); assert(passive_hits_driver.vehicles[0].impact > 0 && passive_hits_driver.vehicles[0].impact_time == 0 && passive_hits_driver.vehicles[0].velocity_x > 0 && math.abs(passive_hits_driver.vehicles[0].chassis_lateral_acceleration) > .2)
	moving_exit := Vehicle_State {
		velocity_x = .08,
	}; stopped_exit := Vehicle_State {
		velocity_x = .074,
		speed      = .074,
	}; spinning_exit := Vehicle_State {
		yaw_rate = .01,
	}; settled_spin_exit := Vehicle_State {
		yaw_rate = .0079,
	}; wheelspin_exit := Vehicle_State {
		speed = .08,
	}; settled_wheels_exit := Vehicle_State {
		speed = .074,
	}; assert(
		!vehicle_can_exit(moving_exit) &&
		vehicle_can_exit(stopped_exit) &&
		!vehicle_can_exit(spinning_exit) &&
		vehicle_can_exit(settled_spin_exit) &&
		!vehicle_can_exit(wheelspin_exit) &&
		vehicle_can_exit(settled_wheels_exit),
	)
	exit_test := new(
		Game,
	); defer free(exit_test); exit_test.screen = .Exterior; exit_test.driving_vehicle = 0; initialize_city_vehicles(exit_test); exit_test.vehicles[0].velocity_y = .2; context_resolve_city(exit_test); assert(!exit_test.context_ui.current.reachable && exit_test.context_ui.current.action == "SLOW TO EXIT"); exit_test.vehicles[0].velocity_y = 0; context_resolve_city(exit_test); assert(exit_test.context_ui.current.reachable && exit_test.context_ui.current.action == "EXIT VEHICLE"); assert(context_activate_city(exit_test, exit_test.context_ui.current) && exit_test.driving_vehicle == -1 && exit_test.city_camera_initialized && exit_test.city_camera_x == exit_test.city_x && exit_test.city_camera_y == exit_test.city_y)
	alternate_exit := new(
		Game,
	); defer free(alternate_exit); initialize_city_vehicles(alternate_exit); alternate_exit.vehicles[0] = {
		x       = city_world(10),
		y       = city_world(3.6),
		heading = 0,
	}; alternate_position, alternate_clear := vehicle_exit_position(
		alternate_exit,
		alternate_exit.vehicles[0],
		0,
	); assert(alternate_clear && alternate_position != Vec2{alternate_exit.vehicles[0].x, alternate_exit.vehicles[0].y}); lawn_exit := new(Game); defer free(lawn_exit); lawn_exit.screen = .Exterior; lawn_exit.driving_vehicle = 0; initialize_city_vehicles(lawn_exit); lawn_exit.vehicles[0] = {
		x       = city_world(10),
		y       = city_world(7),
		heading = 0,
	}; _, lawn_exit_clear := vehicle_exit_position(
		lawn_exit,
		lawn_exit.vehicles[0],
		0,
	); assert(lawn_exit_clear); context_resolve_city(lawn_exit); assert(lawn_exit.context_ui.current.reachable && lawn_exit.context_ui.current.action == "EXIT VEHICLE")
}
