package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

run_self_tests :: proc() {
	assert(
		vk_world_draw_capacity_available(0) &&
		vk_world_draw_capacity_available(VK_WORLD_DRAW_CAPACITY - 1) &&
		!vk_world_draw_capacity_available(VK_WORLD_DRAW_CAPACITY) &&
		!vk_world_draw_capacity_available(VK_WORLD_DRAW_CAPACITY + 1),
	)
	parsed_camera, parsed_camera_ok := parse_vec3_argument(
		"36, 10.5, -14",
	); assert(parsed_camera_ok && parsed_camera == Vec3{36, 10.5, -14})
	_, bad_camera_count := parse_vec3_argument(
		"36,10",
	); _, bad_camera_value := parse_vec3_argument("36,north,14"); assert(!bad_camera_count && !bad_camera_value)
	walls_auto, walls_auto_ok := capture_wall_view_from_text(
		"auto",
	); walls_up, walls_up_ok := capture_wall_view_from_text("UP"); walls_down, walls_down_ok := capture_wall_view_from_text("cutaway"); _, walls_bad := capture_wall_view_from_text("half"); assert(walls_auto_ok && walls_auto == .Automatic && walls_up_ok && walls_up == .Walls_Up && walls_down_ok && walls_down == .Walls_Down && !walls_bad)
	capture_camera := Game {
		camera_pose_override   = true,
		camera_eye_override    = {36, 10, 14},
		camera_target_override = {30, 1, 14},
	}
	eye, target, up := aerial_camera_pose(
		&capture_camera,
		0,
		0,
		0,
	); assert(eye == capture_camera.camera_eye_override && target == capture_camera.camera_target_override && up == Vec3{0, 1, 0})
	capture_camera.camera_eye_override = {
		30,
		20,
		14,
	}; capture_camera.camera_target_override = {30, 0, 14}; _, _, up = aerial_camera_pose(&capture_camera, 0, 0, 0); assert(up == Vec3{0, 0, -1})
	assert(house_wall_camera_position(&capture_camera) == Vec2{30, 14})
	fmt.println("SELF TEST 1/3 · STORY CORE")
	run_story_core_tests()
	run_graph_completion_tests()
	run_authoring_foundation_tests()
	run_authoring_lifecycle_workflow_tests()
	run_lifecycle_closure_tests()
	run_project_asset_persistence_tests()
	run_project_asset_acceptance_tests()
	run_authoring_library_backend_tests()
	run_packaging_closure_tests()
	run_complete_authoring_regression_tests()
	run_story_mystery_completion_tests()
	fmt.println("SELF TEST 2/3 · SCENARIOS")
	scenario_runner_self_test()
	fmt.println("SELF TEST 3/3 · INTEGRATION")
	level_transaction_projection_enabled = false
	run_ui_dim_tests()
	fmt.println("SELF TEST · UI COMPLETE")
	campaign_storage_override = "/private/tmp/chicago-campaign-self-tests"
	campaign_initialize(

	); assert(campaign_browser.count > 0 && campaign_manifest_path != "" && campaign_validate(&campaign_document).ok)
	run_campaign_authoring_mutation_tests()
	run_unified_validation_playtest_tests()
	run_build_validation_closure_tests()
	campaign_paths := [5]string {
		"assets/campaigns/the_marigold_circle.toml",
		"assets/campaigns/the_blackthorn_papers.toml",
		"assets/campaigns/one_more_question.toml",
		"assets/campaigns/bellwether_mysteries.toml",
		"assets/campaigns/unsorted_cases.toml",
	}
	converted_story_count := 0
	for campaign_path in campaign_paths {
		authored_campaign: Campaign_Definition; loaded_campaign := load_campaign_manifest(campaign_path, &authored_campaign); assert(loaded_campaign.ok && campaign_validate(&authored_campaign).ok)
		for item in authored_campaign.cases {
			authored_story: Story_Project; loaded_story := load_story_project(item.story_path, &authored_story); if !loaded_story.ok do fmt.println(item.story_path, ": ", loaded_story.message); assert(loaded_story.ok); compiled_story := compile_story_project(&authored_story); assert(compiled_story.ok); story_compile_result_destroy(&compiled_story)
			authored_level: Level_Document; loaded_level := level_load(item.level_path, &authored_level); assert(loaded_level.ok && level_validate(&authored_level).ok); registry: Story_Spatial_Registry; space := story_level_space(&authored_level); assert(story_spatial_registry_register(&registry, space)); bindings := story_spatial_validate_project(&authored_story, &registry); if !bindings.ok {for diagnostic in bindings.diagnostics do fmt.println(item.story_path, ": ", diagnostic.message)}; assert(bindings.ok); story_validation_destroy(&bindings); story_spatial_registry_destroy(&registry); story_project_destroy(&authored_story); converted_story_count += 1
		}
	}
	assert(converted_story_count == 17)
	fmt.println("SELF TEST · AUTHORED CAMPAIGNS COMPLETE")
	campaign_test := campaign_clone(&campaign_document)
	branch := Campaign_Variable {
		id               = "branch",
		display_name     = "Chosen path",
		kind             = .Enumeration,
		default_enum     = "none",
		enum_value_count = 3,
	}; branch.enum_values[0] = "none"; branch.enum_values[1] = "railway"; branch.enum_values[2] = "harbor"; append(&campaign_test.variables, branch)
	append(
		&campaign_test.effects,
		Campaign_Effect{kind = .Set_Enum, variable_id = "branch", enum_value = "railway"},
	)
	campaign_test.cases[0].replay_mode = .Replace_Outcome; campaign_test.cases[0].outcome_effect_count = 1; campaign_test.cases[0].outcome_effects[0] = {
		outcome      = .Airtight,
		first_effect = 0,
		effect_count = 1,
	}
	append(
		&campaign_test.conditions,
		Campaign_Condition{kind = .Enum_Equals, variable_id = "branch", enum_value = "railway"},
	)
	append(
		&campaign_test.cases,
		Campaign_Case {
			id = "last_train",
			title = "The Last Train",
			story_path = "assets/stories/mysteries/last_train.story.toml",
			case_content_version = "1.0.0",
			condition_root = 1,
			required = true,
			replay_mode = .Disabled,
			invalid_result_policy = .Clear,
		},
	)
	assert(campaign_validate(&campaign_test).ok)
	campaign_progress := Campaign_Playthrough {
		campaign_id              = campaign_test.id,
		campaign_content_version = campaign_test.content_version,
		id                       = "test",
		name                     = "Test",
		active_case              = -1,
		next_completion_sequence = 1,
	}; campaign_reset_values(&campaign_test, &campaign_progress)
	assert(
		campaign_case_unlocked(&campaign_test, &campaign_progress, 0) &&
		!campaign_case_unlocked(&campaign_test, &campaign_progress, 1),
	)
	campaign_result := Campaign_Case_Result {
		case_id              = "the_torn_appointment",
		case_content_version = "1.0.0",
		outcome              = .Airtight,
	}; assert(
		campaign_apply_result(&campaign_test, &campaign_progress, campaign_result).ok &&
		campaign_progress.completion_count == 1 &&
		campaign_progress.values[0].enum_value == "railway" &&
		campaign_case_unlocked(&campaign_test, &campaign_progress, 1),
	)
	assert(
		campaign_apply_result(&campaign_test, &campaign_progress, Campaign_Case_Result{case_id = "last_train", outcome = .Airtight}).ok &&
		campaign_progress.completion_count == 2,
	)
	assert(
		campaign_apply_result(&campaign_test, &campaign_progress, Campaign_Case_Result{case_id = "the_torn_appointment", outcome = .Unresolved}).ok &&
		campaign_progress.completion_count == 1 &&
		!campaign_progress.results[1].present &&
		!campaign_case_unlocked(&campaign_test, &campaign_progress, 1),
	)
	campaign_roundtrip_path := "/private/tmp/chicago-campaign-roundtrip.toml"; assert(save_campaign_manifest(campaign_roundtrip_path, &campaign_test).ok); campaign_roundtrip: Campaign_Definition; assert(load_campaign_manifest(campaign_roundtrip_path, &campaign_roundtrip).ok && len(campaign_roundtrip.variables) == 1 && len(campaign_roundtrip.cases) == 2 && campaign_roundtrip.cases[1].invalid_result_policy == .Clear && campaign_roundtrip.conditions[1].kind == .Enum_Equals)
	saved_campaign_document :=
		campaign_document; saved_workspace := campaign_workspace; campaign_document = campaign_test; campaign_workspace = {
		selected_case      = 1,
		selected_variable  = 0,
		selected_condition = 1,
		draft              = campaign_clone(&campaign_test),
	}; before_conditions := len(
		campaign_workspace.draft.conditions,
	); assert(campaign_workspace_add_condition(.All) && len(campaign_workspace.draft.conditions) == before_conditions + 2 && campaign_workspace.draft.cases[1].condition_root == 1 && len(campaign_document.conditions) == before_conditions); campaign_document = saved_campaign_document; campaign_workspace = saved_workspace
	effect_workspace := Campaign_Workspace_State {
		selected_case      = 1,
		selected_variable  = 0,
		selected_condition = 1,
		selected_outcome   = int(Outcome.Airtight),
		draft              = campaign_clone(&campaign_test),
	}; campaign_workspace =
		effect_workspace; effect_before := len(campaign_workspace.draft.effects); assert(campaign_workspace_add_effect()); campaign_workspace.selected_outcome = int(Outcome.Unresolved); assert(campaign_workspace_add_effect()); campaign_workspace.selected_outcome = int(Outcome.Airtight); assert(campaign_workspace_add_effect() && len(campaign_workspace.draft.effects) == effect_before + 3); airtight_count := 0; for mapping in campaign_workspace.draft.cases[1].outcome_effects[:campaign_workspace.draft.cases[1].outcome_effect_count] do if mapping.outcome == .Airtight do airtight_count = mapping.effect_count; assert(airtight_count == 2); campaign_workspace = saved_workspace
	saved_library :=
		campaign_playthroughs; saved_playthrough := campaign_playthrough; campaign_playthroughs = {}; assert(campaign_create_playthrough("Alpha")); assert(campaign_playthrough_unused(&campaign_playthrough)); campaign_playthrough.active_case = 0; assert(campaign_playthrough_unused(&campaign_playthrough)); campaign_playthrough.results[0].started = true; assert(!campaign_playthrough_unused(&campaign_playthrough)); campaign_playthrough.results[0].started = false; assert(campaign_create_playthrough("Beta")); assert(campaign_playthroughs.count == 2); assert(campaign_rename_playthrough(1, "Branch Run")); assert(campaign_playthroughs.items[1].name == "Branch Run"); assert(campaign_select_playthrough(0)); campaign_playthrough.active_case = 0; assert(save_campaign_playthrough()); roundtrip_playthrough: Campaign_Playthrough; assert(campaign_load_playthrough_id(campaign_playthrough.id, &roundtrip_playthrough) && roundtrip_playthrough.active_case == 0); assert(campaign_delete_playthrough(1)); assert(campaign_playthroughs.count == 1); campaign_playthroughs = saved_library; campaign_playthrough = saved_playthrough
	assert(
		campaign_write_storage("self-test.progress", transmute([]u8)string("ok")),
	); data_written, write_found := campaign_read_storage("self-test.progress"); assert(write_found && string(data_written) == "ok")
	if campaign_browser.count >
	   1 {saved_selected := campaign_browser.selected; saved_scroll := campaign_browser.scroll; campaign_browser.scroll = 0; focus_sync := Game {
			screen        = .Campaign,
			active_device = .Keyboard_Mouse,
		}; focus_sync.gui.focused = campaign_browser_card_id(
			1,
		); campaign_focus_visible_selection(&focus_sync); assert(campaign_browser.selected == 1 && campaign_browser_card_rect(1).y == 270); campaign_browser.selected = saved_selected; campaign_browser.scroll = saved_scroll}
	fmt.println("SELF TEST · CAMPAIGN STATE COMPLETE")
	fmt.println("SELF TEST · GEOMETRY AND INPUT")
	join_walls := [2]Chicago_Wall_Segment {
		{0, 0, 2, 0, .4},
		{2, 0, 2, 2, .4},
	}; join_geometry: Chicago_Wall_Geometry; assert(chicago_wall_union(raw_data(join_walls[:]), 2, nil, 0, &join_geometry) != 0 && join_geometry.point_count >= 6); join_points := (cast([^]Chicago_Wall_Point)join_geometry.points)[:int(join_geometry.point_count)]; join_min_x, join_min_y, join_max_x, join_max_y := f64(1e30), f64(1e30), f64(-1e30), f64(-1e30); for point in join_points {join_min_x = min(join_min_x, point.x); join_min_y = min(join_min_y, point.y); join_max_x = max(join_max_x, point.x); join_max_y = max(join_max_y, point.y)}; assert(math.abs(join_min_x + .2) < .001 && math.abs(join_min_y + .2) < .001 && math.abs(join_max_x - 2.2) < .001 && math.abs(join_max_y - 2.2) < .001); chicago_wall_geometry_free(&join_geometry)
	assert(
		editor_build_tool_shortcut(.Select) == "1" &&
		editor_build_tool_shortcut(.Terrain) == "7" &&
		editor_build_tool_shortcut(.Stairs) == "8" &&
		editor_build_tool_shortcut(.Marker) == "M",
	)
	assert(
		lighting_quality_light_count(.Low) == 1 &&
		lighting_quality_light_count(.Medium) == 2 &&
		lighting_quality_light_count(.High) == 4 &&
		lighting_quality_light_count(.Ultra) == 8,
	)
	assert(
		lighting_quality_shadow_casters(.Low) == 8 &&
		lighting_quality_shadow_casters(.Ultra) == 16 &&
		lighting_quality_shadow_candidates(.Low) == 0 &&
		lighting_quality_shadow_candidates(.Ultra) == 4 &&
		lighting_quality_label(.High) == "HIGH",
	)
	assert(
		lighting_quality_directional_cascades(.Low) == 2 &&
		lighting_quality_directional_cascades(.High) == 4,
	)
	assert(
		lighting_quality_directional_resolution(.High) == 2048 &&
		lighting_quality_point_shadow_slots(.Ultra) == 4,
	)
	assert(
		lighting_quality_spot_shadow_slots(.Medium) == 2 &&
		lighting_quality_local_shadow_samples(.High) == 2,
	)
	assert(
		lighting_quality_shadow_face_budget(.Medium) == 6 &&
		lighting_quality_shadow_face_budget(.Ultra) == 28,
	)
	splits := vk_shadow_practical_splits(
		4,
		.08,
		120,
	); assert(splits[0] > .08 && splits[0] < splits[1] && splits[1] < splits[2] && splits[2] < splits[3] && math.abs(splits[3] - 120) < .001)
	assert(
		lighting_quality_from_text("lighting_quality=low") == .Low &&
		lighting_quality_from_text("lighting_quality=medium") == .Medium &&
		lighting_quality_from_text("lighting_quality=ultra") == .Ultra &&
		lighting_quality_from_text("lighting_quality=broken") == .High,
	)
	assert(
		guidance_mode_from_text("guidance=full") == .Full &&
		guidance_mode_from_text("guidance=adaptive") == .Adaptive &&
		guidance_mode_from_text("guidance=minimal") == .Minimal,
	)
	assert(
		size_of(Vk_World_Draw_Lights) == 80 &&
		VK_WORLD_MAX_LIGHTS == 64 &&
		VK_WORLD_MAX_DRAW_LIGHTS == 8,
	)
	group_scene :=
		Vk_World_Scene{}; group_scene.draws = make([dynamic]Vk_World_Draw, 0, 3); group_scene.draw_lights = make([dynamic]Vk_World_Draw_Lights, 3, 3); defer delete(group_scene.draws); defer delete(group_scene.draw_lights); append(&group_scene.draws, Vk_World_Draw{light_group = 77}, Vk_World_Draw{light_group = 77}, Vk_World_Draw{light_group = 78}); qualities := [4]Lighting_Quality{.Low, .Medium, .High, .Ultra}; for quality in qualities {limit := lighting_quality_light_count(quality); group_scene.draw_lights[0] = {
				indices_a = {3, 5, 7, 9},
				indices_b = {11, 13, 15, 17},
				weights_a = {1, .8, .6, .4},
				weights_b = {.3, .2, .1, .05},
				meta      = {
					u32(limit),
					4,
					u32(min(limit, lighting_quality_shadow_candidates(quality))),
					0,
				},
			}; group_scene.draw_lights[1] =
			{}; assert(vk_world_reuse_grouped_light_list(&group_scene, 1) && group_scene.draw_lights[1] == group_scene.draw_lights[0]); assert(!vk_world_reuse_grouped_light_list(&group_scene, 2))}
	assert(
		strings.contains(editor_build_tool_idle_hint(.Path), "Step 1") &&
		strings.contains(editor_build_tool_idle_hint(.Path), "Enter") &&
		strings.contains(editor_build_tool_idle_hint(.Stairs), "Step 2"),
	)
	assert(
		editor_segment_length({0, 0}, {3, 4}) == 5 &&
		editor_polyline_length([]Vec2{{0, 0}, {3, 4}, {6, 8}}) == 10,
	)
	assert(editor_polygon_preview_area([]Vec2{{0, 0}, {4, 0}}, {4, 3}) == 6)
	camera_test := Game {
			camera_x                 = 10,
			camera_y                 = 8,
			camera_zoom              = 1,
			camera_orbit_initialized = true,
			top_down_camera          = true,
		}; screen, visible := editor_world_screen(
		&camera_test,
		{10, 8},
	); assert(visible && screen == Vec2{600, 360}); camera_test.keys[.D] = true; editor_update_build_camera(&camera_test); assert(camera_test.camera_x > 10 && camera_test.camera_y == 8); camera_test.keys[.D] = false; camera_test.input.mouse_pos = {800, 300}; camera_test.input.mouse_wheel = 1; before_x, before_y, _ := editor_mouse_ground(&camera_test, camera_test.input.mouse_pos); editor_update_build_camera(&camera_test); after_x, after_y, _ := editor_mouse_ground(&camera_test, camera_test.input.mouse_pos); assert(camera_test.camera_zoom < 1 && math.abs(before_x - after_x) < .001 && math.abs(before_y - after_y) < .001); camera_test.camera_zoom = .21; editor_update_build_camera(&camera_test); assert(camera_test.camera_zoom == EDITOR_CAMERA_MIN_ZOOM)
	assert(
		editor_frame_zoom({0, 0}, {20, 8}, 3) > .9 && editor_frame_zoom({0, 0}, {0, 0}, 1) == .65,
	)
	stick_dead := house_radial_input(
		{.1, .1},
	); stick_half := house_radial_input({.5, 0}); stick_full := house_radial_input({1, 0}); assert(stick_dead == Vec2{} && stick_half.x > 0 && stick_half.x < .5 && stick_full.x == 1)
	accelerated := house_approach_velocity(
		{},
		Vec2{HOUSE_MANUAL_MOVE_SPEED, 0},
		true,
	); braked := house_approach_velocity(Vec2{HOUSE_MANUAL_MOVE_SPEED, 0}, {}, false); turned := house_approach_velocity(Vec2{HOUSE_MANUAL_MOVE_SPEED, 0}, Vec2{0, HOUSE_MANUAL_MOVE_SPEED}, true); reversed := house_approach_velocity(Vec2{HOUSE_MANUAL_MOVE_SPEED, 0}, Vec2{-HOUSE_MANUAL_MOVE_SPEED, 0}, true); assert(accelerated.x == HOUSE_MOVE_ACCELERATION && braked.x == HOUSE_MANUAL_MOVE_SPEED - HOUSE_MOVE_DECELERATION && turned.x < HOUSE_MANUAL_MOVE_SPEED && turned.y > HOUSE_MOVE_ACCELERATION * .7 && reversed.x == HOUSE_MANUAL_MOVE_SPEED - HOUSE_MOVE_REVERSE_ACCELERATION)
	assert(
		house_step_height_allowed(0, .25) &&
		!house_step_height_allowed(0, .5) &&
		house_step_height_allowed(.5, 0),
	)
	assert(
		vertical_ranges_overlap(.05, 1.65, 0, .8) &&
		!vertical_ranges_overlap(.05, 1.65, 1.7, 2.2) &&
		!vertical_ranges_overlap(.05, 1.65, -.8, 0),
	)
	step_doc :=
		level_document; step_doc.active_story = 0; step_doc.rooms = make([dynamic]Level_Room, 0, 1); defer delete(step_doc.rooms); step_points := make([dynamic]Vec2, 0, 4); append(&step_points, Vec2{2, 2}, Vec2{4, 2}, Vec2{4, 4}, Vec2{2, 4}); append(&step_doc.rooms, Level_Room{id = "low_step", story = 0, points = step_points, platform_height = .25}); saved_level_document := level_document; level_document = step_doc; step_game := Game {
		player_x = 2.5,
		player_y = 3,
	}; assert(
		house_player_ground_height({2.5, 3}) == .25,
	); house_update_player_elevation(&step_game); assert(step_game.player_elevation == HOUSE_PLAYER_STEP_SPEED); for _ in 0 ..< 8 do house_update_player_elevation(&step_game); assert(step_game.player_elevation == .25); level_document = saved_level_document
	assert(
		editor_object_rotation_angle({0, 0}, {1, 1}, true) == 45 &&
		editor_object_rotation_angle({0, 0}, {0, -1}, true) == 270,
	)
	story_reset_game := Game {
		build_has_anchor = true,
	}; editor_state.room_draw_count = 3; editor_state.foundation_draw_count = 3; editor_state.path_draw_count = 2; editor_state.water_draw_count = 3; editor_state.link_anchor_active = true; editor_reset_story_transients(&story_reset_game); assert(!story_reset_game.build_has_anchor && editor_state.room_draw_count == 0 && editor_state.foundation_draw_count == 0 && editor_state.path_draw_count == 0 && editor_state.water_draw_count == 0 && !editor_state.link_anchor_active)
	assert(
		utf8_glyph_count("A—B◆") == 4,
	); assert(utf8_next_index("—", 0) == 3); assert(COURIER_PUNCTUATION_FIRST <= int('—') && int('—') < COURIER_PUNCTUATION_FIRST + COURIER_PUNCTUATION_GLYPH_COUNT); assert(COURIER_ARROW_FIRST <= int('↔') && int('↔') < COURIER_ARROW_FIRST + COURIER_ARROW_GLYPH_COUNT); assert(COURIER_SHAPE_FIRST <= int('◆') && int('◆') < COURIER_SHAPE_FIRST + COURIER_SHAPE_GLYPH_COUNT)
	typewriter := text_effect_default(

	); typewriter.typewriter_characters_per_second = 10; typewriter.typewriter_delay = .5; assert(text_effect_visible_glyphs(typewriter, .25, 20) == 0); assert(text_effect_visible_glyphs(typewriter, 1, 20) == 5); assert(text_effect_visible_glyphs(typewriter, 4, 20) == 20); assert(text_effect_visible_glyphs(text_effect_default(), 0, 7) == 7)
	assert(
		text_effect_span_visible_glyphs(typewriter, 2, 1.5, 20) == 0,
	); assert(text_effect_span_visible_glyphs(typewriter, 2.5, 1.5, 20) == 5); assert(text_effect_span_duration(typewriter, 20) == 2.5); assert(text_effect_reveal_glyph_count("one\ntwo") == 6)
	effect_a := text_effect_default(
		{0, 20, 40, 255},
		1,
	); effect_b := text_effect_default({100, 120, 140, 55}, 3); effect_a.offset = {0, 10}; effect_b.offset = {20, 30}; effect_mid := text_effect_lerp(effect_a, effect_b, .5); assert(effect_mid.color == [4]u8{50, 70, 90, 155} && effect_mid.scale == 2 && effect_mid.offset == Vec2{10, 20})
	plain_style := text_effect_default(

	); styled := text_effect_default(); styled.bold = true; styled.italic = true; styled.underline = true; assert(!plain_style.bold && !plain_style.italic && !plain_style.underline); assert(text_effect_lerp(plain_style, styled, .49) == plain_style && text_effect_lerp(plain_style, styled, .5).bold && text_effect_lerp(plain_style, styled, .5).italic && text_effect_lerp(plain_style, styled, .5).underline)
	line_small := text_effect_default(
		{},
		1,
	); line_large := text_effect_default({}, 2.5); mixed_lines := []Text_Span{{"small ", line_small}, {"LARGE\n", line_large}, {"next", line_small}}; assert(text_effect_line_scale(mixed_lines, 0) == 2.5 && text_effect_line_scale(mixed_lines, 1) == 1)
	ogg_channels, ogg_rate: i32; ogg_samples: [^]i16; ogg_frames := stb_vorbis_decode_filename(cstring("assets/kenney_ui-audio/Audio/switch34.ogg"), &ogg_channels, &ogg_rate, &ogg_samples); assert(ogg_frames > 0 && ogg_channels == 2 && ogg_rate == 44100 && ogg_samples != nil); chicago_vorbis_free(ogg_samples); assert(!os.is_file("assets/kenney_ui-audio/Audio/evidence.wav"))
	runtime_cues := [8]string {
		"assets/audio/cues/clue-revealed.ogg",
		"assets/audio/cues/fact-established.ogg",
		"assets/audio/cues/decisive-clue.ogg",
		"assets/audio/cues/reveal-section-proven.ogg",
		"assets/audio/cues/wood-open.ogg",
		"assets/audio/cues/wood-close.ogg",
		"assets/audio/cues/crank-resistance.ogg",
		"assets/audio/cues/candle-extinguished.ogg",
	}; for cue_path in runtime_cues {cue_channels, cue_rate: i32; cue_samples: [^]i16; cue_frames := stb_vorbis_decode_filename(strings.clone_to_cstring(cue_path, context.temp_allocator), &cue_channels, &cue_rate, &cue_samples); assert(cue_frames > 0 && cue_channels == 2 && cue_rate == 44100 && cue_samples != nil); chicago_vorbis_free(cue_samples)}
	graph_import_story(
		&test_story_project,
	); choice_test_index := -1; for node, i in graph_document.nodes[:graph_document.node_count] do if node.beat.kind == "choice" && len(node.beat.choice_ids) > 0 {choice_test_index = i; break}; if choice_test_index >= 0 {choice_before := graph_document.nodes[choice_test_index].beat.choice_ids[0]; choice_count_before := len(graph_document.nodes[choice_test_index].beat.choice_ids); assert(graph_choice_duplicate(choice_test_index, 0)); choice_copy := graph_document.nodes[choice_test_index].beat.choice_ids[1]; assert(choice_copy != choice_before && len(graph_document.nodes[choice_test_index].beat.choice_ids) == choice_count_before + 1); assert(graph_choice_move(choice_test_index, 1, -1) && graph_document.nodes[choice_test_index].beat.choice_ids[0] == choice_copy && graph_document.nodes[choice_test_index].beat.choice_ids[1] == choice_before); assert(graph_choice_delete(choice_test_index, 0) && graph_document.nodes[choice_test_index].beat.choice_ids[0] == choice_before)}
	if graph_document.node_count > 0 &&
	   graph_document.localization_count <
		   len(
			   graph_document.localizations,
		   ) {localized_node := graph_document.nodes[0].beat.id; graph_document.localizations[graph_document.localization_count] = {
			node_id  = localized_node,
			language = "fr",
			text     = "Dialogue traduit — vérifié",
			status   = "reviewed",
			note     = "Unicode ✓",
			voice    = "vo/test.ogg",
		}; graph_document.localization_count += 1; localized_roundtrip: Story_Project; assert(graph_build_story_project(&test_story_project, &localized_roundtrip).ok); assert(len(localized_roundtrip.localizations) > 0); localized := localized_roundtrip.localizations[len(localized_roundtrip.localizations) - 1]; assert(localized.node_id == localized_node && localized.language == "fr" && localized.text == "Dialogue traduit — vérifié" && localized.note == "Unicode ✓" && localized.voice == "vo/test.ogg"); story_project_destroy(&localized_roundtrip)}; graph_import_story(&test_story_project)
	fmt.println("SELF TEST · UNIFIED STORY RUNTIME")
	ensure_test_torn_story()
	graph_import_story(
		&test_story_project,
	); semantic_roundtrip: Story_Project; assert(graph_build_story_project(&test_story_project, &semantic_roundtrip).ok); semantic_source := compile_story_project(&test_story_project); semantic_graph := compile_story_project(&semantic_roundtrip); if semantic_source.story.content_identity != semantic_graph.story.content_identity {_ = save_story_project("/private/tmp/graph-semantic-source.toml", &test_story_project); _ = save_story_project("/private/tmp/graph-semantic-roundtrip.toml", &semantic_roundtrip); fmt.println("GRAPH SEMANTIC HASHES ", semantic_source.story.content_identity, " ", semantic_graph.story.content_identity)}; assert(semantic_source.ok && semantic_graph.ok && semantic_source.story.content_identity == semantic_graph.story.content_identity); story_compile_result_destroy(&semantic_source); story_compile_result_destroy(&semantic_graph); story_project_destroy(&semantic_roundtrip)
	payload := mystery_payload(
		&test_story_project,
	); assert(payload != nil && len(payload.clues) == 11 && len(payload.questions) == 9 && len(payload.demonstrations) == 9)
	fragment_demo_index := mystery_authoring_demonstration_index(
		payload,
		"demo_fragment_source",
	); assert(fragment_demo_index >= 0 && payload.demonstrations[fragment_demo_index].presentation == "connect" && payload.demonstrations[fragment_demo_index].gesture == "join" && payload.demonstrations[fragment_demo_index].candidate_limit == 5)
	interaction_state := mystery_state_init(&test_story_project); interaction_game := Game {
		story_project     = &test_story_project,
		mystery_state     = &interaction_state,
		question_selected = -1,
	}; mystery_game_mark_all_clues(
		&interaction_game,
	); refresh_questions(&interaction_game); interaction_game.question_selected = question_index_by_id(&interaction_game, "q_fragment_source"); mystery_question_set_slot(&interaction_game, interaction_game.question_selected, 0, "clue_appointment_stub"); mystery_question_set_slot(&interaction_game, interaction_game.question_selected, 1, "clue_burned_fragment"); first_ranked := question_slot_piece_id(&interaction_game, 0); assert((first_ranked == "clue_appointment_stub" || first_ranked == "clue_burned_fragment") && question_slot_piece_id(&interaction_game, 0) == first_ranked); saved_fragment_demo := payload.demonstrations[fragment_demo_index]; payload.demonstrations[fragment_demo_index].gesture_step_count = 2; payload.demonstrations[fragment_demo_index].gesture_steps[1] = "align"; begin_question_demonstration(&interaction_game); assert(interaction_game.screen == .Recreate && interaction_game.interaction_active); advance_question_interaction(&interaction_game); assert(interaction_game.interaction_active && interaction_game.interaction_step == 1); advance_question_interaction(&interaction_game); assert(!interaction_game.interaction_active && !interaction_game.interaction_mismatch && knowledge_piece_known(&interaction_game, "ded_fragment_in_miriam_wastebin")); payload.demonstrations[fragment_demo_index] = saved_fragment_demo; mystery_state_destroy(&interaction_state)
	mismatch_state := mystery_state_init(&test_story_project); mismatch_game := Game {
		story_project     = &test_story_project,
		mystery_state     = &mismatch_state,
		question_selected = -1,
	}; mystery_game_mark_all_clues(
		&mismatch_game,
	); refresh_questions(&mismatch_game); mismatch_game.question_selected = question_index_by_id(&mismatch_game, "q_fragment_source"); mystery_question_set_slot(&mismatch_game, mismatch_game.question_selected, 0, "clue_appointment_stub"); mystery_question_set_slot(&mismatch_game, mismatch_game.question_selected, 1, "clue_cane"); begin_question_demonstration(&mismatch_game); advance_question_interaction(&mismatch_game); assert(mismatch_game.interaction_mismatch && !knowledge_piece_known(&mismatch_game, "ded_fragment_in_miriam_wastebin") && strings.contains(mismatch_game.question_feedback, "does not hold")); mystery_state_destroy(&mismatch_state)
	referred_ending := mystery_ending_index(
		&test_story_project,
		"case_referred",
	); incomplete_ending := mystery_ending_index(&test_story_project, "case_incomplete"); assert(referred_ending >= 0 && incomplete_ending >= 0 && strings.contains(payload.endings[referred_ending].epilogue, "phrase the inspector plans to regret") && strings.contains(payload.endings[incomplete_ending].epilogue, "'murder room' to 'study'") && strings.contains(payload.endings[incomplete_ending].epilogue, "whose account is written down"))
	validation := story_project_validate(
		&test_story_project,
	); assert(validation.ok); story_validation_destroy(&validation)
	compiled := compile_story_project(
		&test_story_project,
	); assert(compiled.ok); runtime := story_runtime_new(&compiled.story, nil); state := cast(^Mystery_State)story_runtime_capability_state(&runtime, "mystery", MYSTERY_DOMAIN_VERSION); assert(state != nil && state.action_budget_remaining == payload.action_budget)
	introduction_game := Game {
		story_project = &test_story_project,
		story_runtime = &runtime,
	}; introduction_sources := [3]string {
		"miriam",
		"daniel",
		"elsie",
	}; for source in introduction_sources {scene_id := fmt.tprintf("scene_intro_%s", source); known_before := len(state.acquired_evidence) + len(state.established_claims) + len(state.earned_deductions); assert(dialogue_start_character_introduction(&introduction_game, source) && runtime.current_scene == scene_id); for !runtime.finished {step := story_runtime_advance(&runtime); assert(step.ok)}; assert(dialogue_scene_completed(&introduction_game, scene_id) && !dialogue_start_character_introduction(&introduction_game, source)); assert(len(state.acquired_evidence) + len(state.established_claims) + len(state.earned_deductions) == known_before)}
	reveal_game := Game {
		story_project = &test_story_project,
		mystery_state = state,
	}; assert(
		!reveal_act_supported(&reveal_game, 3),
	); assert(mystery_string_set_add(&state.earned_deductions, "ded_daniel_affair") && mystery_string_set_add(&state.earned_deductions, "ded_elsie_theft") && reveal_act_supported(&reveal_game, 3)); reveal_first, reveal_second := reveal_act_lines(&reveal_game, 3); assert(strings.contains(reveal_first, "Daniel's false alibi") && strings.contains(reveal_second, "sixteen pounds") && strings.contains(reveal_act_third_line(&reveal_game, 3), "Neither explains"))
	reveal_game.mystery_state.accusation_id = "miriam"; assert(strings.contains(reveal_act_response(&reveal_game, 0, true, false), "grievance") && strings.contains(reveal_act_response(&reveal_game, 0, true, true), "unaccounted-for hour") && strings.contains(reveal_act_response(&reveal_game, 0, true, true), "does not correct")); assert(strings.contains(reveal_act_response(&reveal_game, 1, true, false), "available to everyone") && strings.contains(reveal_act_response(&reveal_game, 1, true, true), "polished that seam")); assert(strings.contains(reveal_act_response(&reveal_game, 2, true, false), "Sequence is not proof") && strings.contains(reveal_act_response(&reveal_game, 2, true, true), "watching the door")); assert(strings.contains(reveal_act_response(&reveal_game, 3, true, true), "Neither lie can shelter"))
	assert(
		mystery_string_set_add(&state.earned_deductions, "ded_miriam_denial_disproved"),
	); reveal_game.finale_demo_step = 0; assert(strings.contains(finale_demo_message(&reveal_game), "He did not")); reveal_game.finale_demo_step = 1; assert(strings.contains(finale_demo_message(&reveal_game), "two rooms, two scraps") && strings.contains(finale_demo_message(&reveal_game), "leaves it crooked")); reveal_game.finale_demo_step = 2; assert(strings.contains(finale_demo_message(&reveal_game), "four minutes after"))
	story_runtime_destroy(&runtime); compiled_story_destroy(&compiled.story)
	graph_import_story(
		&test_story_project,
	); assert(graph_document.case_id == test_story_project.id && graph_document.scene_count == len(test_story_project.scenes) && graph_document.node_count == len(test_story_project.nodes)); graph_round_trip: Story_Project; graph_built := graph_build_story_project(&test_story_project, &graph_round_trip); assert(graph_built.ok && len(graph_round_trip.scenes) == len(test_story_project.scenes) && len(graph_round_trip.nodes) == len(test_story_project.nodes)); for source_scene, i in test_story_project.scenes do assert(graph_round_trip.scenes[i] == source_scene); for source_node in test_story_project.nodes {round_index := story_node_index(&graph_round_trip, source_node.scene_id, source_node.id); assert(round_index >= 0); round_node := graph_round_trip.nodes[round_index]; assert(round_node.id == source_node.id && round_node.scene_id == source_node.scene_id && round_node.kind == source_node.kind && round_node.line_id == source_node.line_id && round_node.speaker_id == source_node.speaker_id && round_node.text == source_node.text && round_node.next == source_node.next && round_node.success == source_node.success && round_node.failure == source_node.failure && round_node.cancel == source_node.cancel && round_node.subscene_id == source_node.subscene_id && round_node.ui == source_node.ui && round_node.camera == source_node.camera && round_node.actor == source_node.actor && round_node.actor_mark == source_node.actor_mark && round_node.animation == source_node.animation && round_node.summary == source_node.summary && round_node.ending == source_node.ending && round_node.domain_ref == source_node.domain_ref && round_node.event_id == source_node.event_id && round_node.duration == source_node.duration && round_node.transition == source_node.transition && round_node.blocking == source_node.blocking && round_node.condition_id == source_node.condition_id && round_node.condition_root == source_node.condition_root && round_node.first_effect == source_node.first_effect && round_node.effect_count == source_node.effect_count && round_node.effect_id_count == source_node.effect_id_count && round_node.choice_count == source_node.choice_count); for i in 0 ..< source_node.choice_count do assert(round_node.choices[i] == source_node.choices[i]); for i in 0 ..< source_node.effect_id_count do assert(round_node.effect_ids[i] == source_node.effect_ids[i])}; story_project_destroy(&graph_round_trip)
	inspector_fields :=
		GRAPH_NODE_INSPECTOR_FIELDS; assert(len(inspector_fields) == 39); for field, i in inspector_fields {assert(field != .None); for other, j in inspector_fields do if i != j do assert(field != other)}
	graph_document = {
		case_id            = "rename_atomic",
		scene_count        = 2,
		node_count         = 3,
		condition_count    = 1,
		effect_count       = 1,
		localization_count = 1,
	}; graph_document.conditions = make(
		[dynamic]Story_Condition,
		0,
		1,
	); append(&graph_document.conditions, Story_Condition{id = "old_condition"}); graph_document.effects = make([dynamic]Story_Effect, 0, 1); append(&graph_document.effects, Story_Effect{id = "old_effect"}); graph_document.scenes[0].scene = {
		id    = "old_scene",
		entry = "old_node",
	}; graph_document.scenes[1].scene = {
		id        = "caller_scene",
		entry     = "caller",
		return_to = "old_scene",
	}; graph_document.nodes[0].beat = {
		id           = "old_node",
		scene        = "old_scene",
		kind         = "line",
		next         = "target",
		condition_id = "old_condition",
		effect_ids   = make([]string, 1),
	}; graph_document.nodes[0].beat.effect_ids[0] = "old_effect"; graph_document.nodes[1].beat = {
		id    = "target",
		scene = "old_scene",
		kind  = "end",
	}; graph_document.nodes[2].beat = {
		id                = "caller",
		scene             = "caller_scene",
		kind              = "subscene",
		subscene_id       = "old_scene",
		next              = "caller",
		choice_ids        = make([]string, 1),
		choice_labels     = make([]string, 1),
		choice_targets    = make([]string, 1),
		choice_conditions = make([]string, 1),
	}; graph_document.nodes[2].beat.choice_ids[0] = "old_choice"; graph_document.nodes[2].beat.choice_labels[0] = "Choice"; graph_document.nodes[2].beat.choice_targets[0] = "caller"; graph_document.nodes[2].beat.choice_conditions[0] = "old_condition"; graph_document.localizations[0] = {
		node_id  = "old_node",
		language = "en",
		text     = "Line",
	}; graph_state = {
		active_scene       = 0,
		selected_node      = 0,
		selected_condition = 0,
		selected_effect    = 0,
	}; graph_history = {}; graph_autosave_enabled = false
	graph_begin_edit(
		.Scene_Id,
		"renamed_scene",
	); assert(graph_commit_edit() && graph_document.nodes[0].beat.scene == "renamed_scene" && graph_document.nodes[1].beat.scene == "renamed_scene" && graph_document.nodes[2].beat.subscene_id == "renamed_scene" && graph_document.scenes[1].scene.return_to == "renamed_scene")
	graph_begin_edit(
		.Node_Id,
		"renamed_node",
		0,
	); assert(graph_commit_edit() && graph_document.scenes[0].scene.entry == "renamed_node" && graph_document.localizations[0].node_id == "renamed_node")
	graph_begin_choice_edit(
		.Choice_Id,
		"renamed_choice",
		2,
		0,
	); assert(graph_commit_edit() && graph_document.nodes[2].beat.choice_ids[0] == "renamed_choice")
	graph_begin_edit(
		.Condition_Id,
		"renamed_condition",
	); assert(graph_commit_edit() && graph_document.nodes[0].beat.condition_id == "renamed_condition" && graph_document.nodes[2].beat.choice_conditions[0] == "renamed_condition")
	graph_begin_edit(
		.Effect_Id,
		"renamed_effect",
	); assert(graph_commit_edit() && graph_document.nodes[0].beat.effect_ids[0] == "renamed_effect"); graph_import_story(&test_story_project)
	graph_configure_routing_test_board(

	); assert(graph_rendered_edge_hit({450, 151}, "wire_crossings", 11, 12, 0)); direct_point := Vec2{580, 134}; blocked_port := graph_port_rect(graph_document.nodes[2], 0); blocked_input := graph_input_rect(graph_document.nodes[4]); blocked_a, blocked_d := Vec2{blocked_port.x + blocked_port.w * .5, blocked_port.y + blocked_port.h * .5}, Vec2{blocked_input.x + blocked_input.w * .5, blocked_input.y + blocked_input.h * .5}; blocked_lane, blocked_lane_ok := graph_edge_local_lane("wire_routing", blocked_a, blocked_d, 2, 4); assert(blocked_lane_ok); blocked_p1, blocked_p2 := Vec2{blocked_a.x + 28, blocked_lane}, Vec2{blocked_d.x - 28, blocked_lane}; blocked_b := Vec2{blocked_p1.x + (blocked_p2.x - blocked_a.x) / 6, blocked_p1.y + (blocked_p2.y - blocked_a.y) / 6}; blocked_c := Vec2{blocked_p2.x - (blocked_d.x - blocked_p1.x) / 6, blocked_p2.y - (blocked_d.y - blocked_p1.y) / 6}; blocked_point := graph_edge_cubic_point(blocked_p1, blocked_b, blocked_c, blocked_p2, .5); back_point := Vec2{580, 360}; assert(graph_rendered_edge_hit(direct_point, "wire_routing", 0, 1, 0)); assert(graph_rendered_edge_hit(blocked_point, "wire_routing", 2, 4, 0) && !graph_rendered_edge_hit({580, 284}, "wire_routing", 2, 4, 0)); assert(graph_rendered_edge_hit(back_point, "wire_routing", 5, 6, 0)); direct_selection := graph_edge_hit(direct_point); blocked_selection := graph_edge_hit(blocked_point); back_selection := graph_edge_hit(back_point); assert(direct_selection.active && direct_selection.node == 0 && blocked_selection.active && blocked_selection.node == 2 && back_selection.active && back_selection.node == 5)
	collapsed_card := Graph_Node {
		collapsed = true,
	}; ordinary_card := Graph_Node {
		beat = {kind = "line"},
	}; check_card := Graph_Node {
		beat = {kind = "check"},
	}; max_choice_card := Graph_Node {
		beat = {kind = "choice", choice_labels = make([]string, STORY_MAX_NODE_CHOICES)},
	}; assert(
		graph_node_world_height(collapsed_card) == 36 &&
		graph_node_world_height(ordinary_card) == 72 &&
		graph_node_world_height(check_card) == 74,
	); assert(graph_node_world_height(max_choice_card) == GRAPH_NODE_HEADER_HEIGHT + GRAPH_NODE_OUTPUT_PADDING + STORY_MAX_NODE_CHOICES * GRAPH_NODE_OUTPUT_ROW_HEIGHT)
	graph_document = {
		case_id     = "height_layout",
		scene_count = 1,
		node_count  = 4,
	}; graph_document.scenes[0].scene.id = "height_layout"; graph_state = {
		active_scene  = 0,
		selected_node = -1,
		zoom          = 1,
	}; graph_document.nodes[0] =
		max_choice_card; graph_document.nodes[0].beat.scene = "height_layout"; for i in 1 ..< 4 {graph_document.nodes[i] = ordinary_card; graph_document.nodes[i].beat.scene = "height_layout"}; assert(graph_auto_layout()); assert(graph_document.nodes[3].position.y >= graph_document.nodes[0].position.y + graph_node_world_height(graph_document.nodes[0]) + GRAPH_NODE_LAYOUT_ROW_GAP); graph_import_story(&test_story_project)
	fmt.println("SELF TEST · UNIFIED STORY RUNTIME COMPLETE")
	assert(
		normalize_gamepad_axis(0) == 0,
	); assert(normalize_gamepad_axis(3000) == 0); assert(normalize_gamepad_axis(32767) == 1); assert(normalize_gamepad_axis(-32767) == -1)
	assert(
		!gamepad_disconnect_should_pause(.Title) &&
		!gamepad_disconnect_should_pause(.Options) &&
		gamepad_disconnect_should_pause(.Exterior) &&
		gamepad_disconnect_should_pause(.Dialogue) &&
		gamepad_disconnect_should_pause(.Check) &&
		gamepad_disconnect_should_pause(.Reveal),
	)
	assert(
		back_opens_pause(.Investigate) &&
		back_opens_pause(.Check) &&
		!back_opens_pause(.Dialogue) &&
		!back_opens_pause(.Pause),
	)
	disconnect_input := Game {
		controller_disconnected = true,
		active_device           = .Gamepad,
		pad_left_x              = .8,
		pad_left_y              = -.4,
		pad_right_x             = .2,
		pad_right_y             = -.3,
		pad_left_trigger        = .5,
		pad_right_trigger       = .9,
		axis_nav_x              = 1,
		axis_nav_y              = -1,
	}; disconnect_input.pad_buttons[.SOUTH] =
		true; clear_gamepad_input(&disconnect_input); assert(disconnect_input.pad_left_x == 0 && disconnect_input.pad_left_y == 0 && disconnect_input.pad_right_x == 0 && disconnect_input.pad_right_y == 0 && disconnect_input.pad_left_trigger == 0 && disconnect_input.pad_right_trigger == 0 && disconnect_input.axis_nav_x == 0 && disconnect_input.axis_nav_y == 0 && !disconnect_input.pad_buttons[.SOUTH]); activate_keyboard_mouse(&disconnect_input); assert(!disconnect_input.controller_disconnected && disconnect_input.input_resume_blocked && disconnect_input.active_device == .Keyboard_Mouse); disconnect_input.input.activate = true; prepare_input_poll(&disconnect_input); assert(!disconnect_input.input_resume_blocked && !disconnect_input.input.activate)
	fmt.println("SELF TEST · INPUT RESET COMPLETE")
	heading_cases := [4]f32 {
		0,
		f32(math.PI / 2),
		f32(math.PI),
		-f32(math.PI / 2),
	}; for heading in heading_cases {render_yaw := character_render_yaw(heading); model_forward := Vec2{-f32(math.sin(f64(render_yaw))), f32(math.cos(f64(render_yaw)))}; assert(math.abs(model_forward.x - f32(math.cos(f64(heading)))) < .0001 && math.abs(model_forward.y - f32(math.sin(f64(heading)))) < .0001)}
	assert(
		keyboard_prompt_label(.Accept) == "ENTER" &&
		keyboard_prompt_label(.Interact) == "E" &&
		keyboard_prompt_label(.Move) == "WASD" &&
		keyboard_prompt_label(.Look) == "ARROWS",
	)
	assert(
		keyboard_prompt_label(.Room_Hint) == "Q" &&
		keyboard_prompt_label(.Camera) == "F" &&
		keyboard_prompt_label(.Vehicle_Action) == "F" &&
		keyboard_prompt_label(.Attributes) == "C" &&
		keyboard_prompt_label(.Handbrake) == "SPACE",
	)
	assert(
		gamepad_prompt_label(.Board, 0) == "X" &&
		gamepad_prompt_label(.Back, 0) == "B" &&
		gamepad_prompt_label(.Room_Hint, 0) == "L3" &&
		gamepad_prompt_label(.Camera, 0) == "R3",
	)
	assert(
		gamepad_prompt_label(.Board, 1) == "SQUARE" &&
		gamepad_prompt_label(.Board, 2) == "Y" &&
		gamepad_prompt_label(.Attributes, 1) == "SQUARE" &&
		gamepad_prompt_label(.Vehicle_Action, 0) == "Y" &&
		gamepad_prompt_label(.Vehicle_Action, 1) == "TRIANGLE" &&
		gamepad_prompt_label(.Vehicle_Action, 2) == "X" &&
		gamepad_prompt_label(.Handbrake, 2) == "RB",
	)
	assert(
		gamepad_family(.XBOXONE) == 0 &&
		gamepad_family(.PS5) == 1 &&
		gamepad_family(.NINTENDO_SWITCH_PRO) == 2,
	)
	control_hint_game :=
		Game{}; assert(prompt_label(&control_hint_game, .Room_Hint) == "Q" && dialogue_interaction_controls_hint(&control_hint_game) == "DRAG ROTATE  ·  WHEEL ZOOM  ·  F RESET"); control_hint_game.active_device = .Gamepad; control_hint_game.gamepad_type = .PS5; assert(prompt_label(&control_hint_game, .Interact) == "CROSS" && dialogue_interaction_controls_hint(&control_hint_game) == "RIGHT STICK ROTATE  ·  TRIGGERS ZOOM  ·  R3 RESET")
	fmt.println("SELF TEST · CONTROL LABELS COMPLETE")
	// Aerial click navigation uses the exact camera ray used by the renderer.
	close_distance, close_height := gameplay_camera_boom(
		&Game{screen = .Investigate, camera_zoom = .55, camera_orbit_initialized = true},
	); far_distance, far_height := gameplay_camera_boom(&Game{screen = .Investigate, camera_zoom = 1.65, camera_orbit_initialized = true}); assert(close_distance < far_distance && close_height < far_height)
	exterior_close_distance, exterior_close_height := gameplay_camera_boom(
		&Game{screen = .Exterior, camera_zoom = .55, camera_orbit_initialized = true},
	); exterior_far_distance, exterior_far_height := gameplay_camera_boom(&Game{screen = .Exterior, camera_zoom = 1.65, camera_orbit_initialized = true}); assert(exterior_close_distance < exterior_far_distance && exterior_close_height < exterior_far_height)
	city_camera_test := Game {
		screen = .Exterior,
		city_x = 10,
		city_y = 12,
		pad_right_x = 1,
		pad_right_y = 1,
		input = {mouse_wheel = 1},
	}; city_update_camera(
		&city_camera_test,
	); assert(city_camera_test.camera_orbit_initialized && city_camera_test.city_camera_initialized); assert(city_camera_test.camera_orbit > math.PI / 4); assert(math.abs(city_camera_test.camera_zoom - .925) < .001)
	minimap_center := Vec2 {
		100,
		90,
	}; minimap_world_center := Vec2{10, 12}; minimap_right := Vec2{0, 1}; minimap_forward := Vec2{1, 0}; assert(city_minimap_project({10, 12}, minimap_world_center, minimap_right, minimap_forward, minimap_center, 2, 3) == minimap_center); assert(city_minimap_project({11, 12}, minimap_world_center, minimap_right, minimap_forward, minimap_center, 2, 3) == Vec2{100, 87}); assert(city_minimap_project({10, 13}, minimap_world_center, minimap_right, minimap_forward, minimap_center, 2, 3) == Vec2{102, 90})
	orbits := [3]f32 {
		math.PI / 4,
		-math.PI / 3,
		math.PI,
	}; zooms := [2]f32{.55, 1.65}; for orbit in orbits {for zoom in zooms {roundtrip_game := Game {
				screen                   = .Investigate,
				camera_x                 = 4,
				camera_y                 = 7,
				camera_orbit             = orbit,
				camera_zoom              = zoom,
				camera_orbit_initialized = true,
			}; roundtrip_screen, roundtrip_visible := context_world_point_screen(
				&roundtrip_game,
				{6, 8},
			); camera_x, camera_y, camera_ok := gameplay_mouse_ground(&roundtrip_game, roundtrip_screen); assert(roundtrip_visible && camera_ok && math.abs(camera_x - 6) < .002 && math.abs(camera_y - 8) < .002)}}
	fmt.println("SELF TEST · CAMERA ROUND TRIP COMPLETE")
	topdown_game := Game {
		top_down_camera = true,
		camera_x        = 12,
		camera_y        = 8,
	}; topdown_screen, topdown_visible := editor_world_screen(
		&topdown_game,
		{6.5, 11.5},
	); topdown_x, topdown_y, topdown_ok := editor_mouse_ground(&topdown_game, topdown_screen); assert(topdown_visible && topdown_ok && math.abs(topdown_x - 6.5) < .02 && math.abs(topdown_y - 11.5) < .02)
	// Wall cutaway easing has exact, deterministic endpoints and never leaks the
	// automatic gameplay transition into an isometric build-mode view.
	saved_view := editor_state.view; editor_state.view = .Isometric
	full_wall_game := Game{}; mid_wall_game := Game {
		cutaway_transition = .5,
	}; build_wall_game := Game {
		editor_mode        = .Build,
		cutaway_transition = 1,
	}; explicit_wall_game := Game {
		top_down_camera = true,
	}
	capture_partial_wall_game := Game {
		editor_mode              = .Build,
		capture_cutaway_override = true,
		capture_cutaway_amount   = .5,
	}
	assert(
		house_cutaway_amount(&full_wall_game) == 0 &&
		house_render_wall_height(&full_wall_game) == HOUSE_WALL_HEIGHT,
	)
	assert(
		math.abs(house_cutaway_amount(&mid_wall_game) - .5) < .0001 &&
		math.abs(
			house_render_wall_height(&mid_wall_game) -
			(HOUSE_WALL_HEIGHT + HOUSE_CUTAWAY_HEIGHT) * .5,
		) <
			.0001,
	)
	assert(
		math.abs(house_cutaway_amount(&capture_partial_wall_game) - .5) < .0001 &&
		math.abs(
			house_render_wall_height(&capture_partial_wall_game) -
			(HOUSE_WALL_HEIGHT + HOUSE_CUTAWAY_HEIGHT) * .5,
		) <
			.0001,
	)
	assert(
		house_cutaway_amount(&build_wall_game) == 0 &&
		house_render_wall_height(&build_wall_game) == HOUSE_WALL_HEIGHT,
	)
	assert(
		house_cutaway_amount(&explicit_wall_game) == 1 &&
		math.abs(house_render_wall_height(&explicit_wall_game) - HOUSE_CUTAWAY_HEIGHT) < .0001,
	); editor_state.view = saved_view
	uniform_saved_walls :=
		house_walls; house_walls = make([dynamic]Floorplan_Wall, 2); uniform_game := Game{}; uniform_zero, uniform_ok := house_wall_uniform_amount(&uniform_game); assert(uniform_ok && uniform_zero == 0); uniform_game.wall_cutaways[1] = 1; _, uniform_mixed := house_wall_uniform_amount(&uniform_game); assert(!uniform_mixed); delete(house_walls); house_walls = uniform_saved_walls
	wall_transition_mesh := procedural_wall_mesh(
		8,
		HOUSE_WALL_HEIGHT,
		HOUSE_WALL_THICKNESS,
	); wall_transition_model := vk_world_model(&wall_transition_mesh, 12, 8, house_render_wall_width(&wall_transition_mesh), house_render_wall_height(&mid_wall_game), 0, 0, 0, false); assert(math.abs(wall_transition_model[0] - 1) < .0001 && math.abs(wall_transition_model[10] - 1) < .0001 && wall_transition_model[5] < 1)
	// World-authored wall unions must retain their complete plan footprint when
	// their presentation height is lowered for a cutaway.
	union_cutaway_mesh := Glb_Mesh {
		min = {8, 0, 10},
		max = {40, HOUSE_WALL_HEIGHT, 42},
	}; union_cutaway_model := vk_world_model(
		&union_cutaway_mesh,
		24,
		26,
		house_render_wall_width(&union_cutaway_mesh),
		HOUSE_CUTAWAY_HEIGHT,
		0,
		0,
		0,
		false,
	); assert(math.abs(union_cutaway_model[0] - 1) < .0001 && math.abs(union_cutaway_model[10] - 1) < .0001 && union_cutaway_model[5] < 1)
	// Centered mechanical transforms keep their pivot fixed through arbitrary
	// pitch; the crank spoke relies on this while rotating in the wall plane.
	centered_mesh := procedural_wall_mesh(
		.065,
		.065,
		.27,
	); centered_model := vk_world_model(&centered_mesh, 3, 7, 0, .065, 0, -1.17, 1.2, false, true); center_x, center_y, center_z := (centered_mesh.min.x + centered_mesh.max.x) * .5, (centered_mesh.min.y + centered_mesh.max.y) * .5, (centered_mesh.min.z + centered_mesh.max.z) * .5; world_center_x := centered_model[0] * center_x + centered_model[4] * center_y + centered_model[8] * center_z + centered_model[12]; world_center_y := centered_model[1] * center_x + centered_model[5] * center_y + centered_model[9] * center_z + centered_model[13]; world_center_z := centered_model[2] * center_x + centered_model[6] * center_y + centered_model[10] * center_z + centered_model[14]; assert(math.abs(world_center_x - 3) < .0001 && math.abs(world_center_y - 1.2) < .0001 && math.abs(world_center_z - 7) < .0001)
	cap_tint_start, cap_tint_mid, cap_tint_end :=
		house_wall_cap_tint(0),
		house_wall_cap_tint(.5),
		house_wall_cap_tint(
			1,
		); assert(cap_tint_start == [4]u8{132, 138, 134, 255} && cap_tint_mid == [4]u8{150, 156, 152, 255} && cap_tint_end == [4]u8{168, 174, 170, 255})
	assert(
		house_wall_section_tint(0) == cap_tint_start &&
		house_wall_section_tint(.5) == cap_tint_mid &&
		house_wall_section_tint(1) == cap_tint_end,
	)
	reveal_tint_start, reveal_tint_end :=
		house_wall_junction_tint(0),
		house_wall_junction_tint(
			1,
		); assert(reveal_tint_start[0] < cap_tint_start[0] && reveal_tint_start[1] < cap_tint_start[1] && reveal_tint_end[2] < cap_tint_end[2])
	cap_edge_start, cap_edge_end :=
		house_wall_cap_edge_tint(0),
		house_wall_cap_edge_tint(
			1,
		); assert(cap_edge_start == cap_tint_start && cap_edge_end[0] < cap_tint_end[0] && cap_edge_end[1] < cap_tint_end[1] && cap_edge_end[2] < cap_tint_end[2] && HOUSE_WALL_CAP_EDGE_OVERHANG > 0)
	wall_cap_transform_mesh := procedural_quad_mesh(
		8,
		HOUSE_WALL_THICKNESS,
		true,
	); wall_cap_model := vk_world_model(&wall_cap_transform_mesh, 12, 8, 8, house_wall_cap_draw_height(&wall_cap_transform_mesh), 0, 0, 2, false); assert(math.abs(wall_cap_model[0] - 1) < .0001 && math.abs(wall_cap_model[5] - 1) < .0001 && math.abs(wall_cap_model[10] - 1) < .0001)
	saved_walls :=
		house_walls; house_walls = make([dynamic]Floorplan_Wall, 0, 2); append(&house_walls, Floorplan_Wall{a = {0, 0}, b = {2, 0}}, Floorplan_Wall{a = {2, 0}, b = {2, 2}}); junction_game := Game{}; junction_game.wall_cutaways[0] = 1; junction_game.wall_cutaways[1] = 0; assert(math.abs(house_wall_junction_reveal_height(&junction_game, 0, {2, 0}) - (HOUSE_WALL_HEIGHT - HOUSE_CUTAWAY_HEIGHT)) < .0001 && house_wall_junction_reveal_height(&junction_game, 1, {2, 0}) == 0 && house_wall_junction_reveal_height(&junction_game, 0, {0, 0}) == 0); delete(house_walls); house_walls = saved_walls
	attachment_saved_walls :=
		house_walls; house_walls = make([dynamic]Floorplan_Wall, 0, 1); append(&house_walls, Floorplan_Wall{a = {0, 0}, b = {4, 0}, positive_interior = true}); attachment_x, attachment_z, attachment_yaw, attachment_ok := house_wall_attachment_pose(0, {2, .3}); assert(attachment_ok && math.abs(attachment_x - 2) < .0001 && attachment_z > HOUSE_WALL_THICKNESS * .5 && math.abs(attachment_yaw) < .0001); delete(house_walls); house_walls = attachment_saved_walls
	// Automatic walls lower only the active room boundary between the player and
	// camera; the manual Sims-style up/down modes remain deterministic overrides.
	cutaway_doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &cutaway_doc).ok); cutaway_saved_doc := level_document; level_document = cutaway_doc; level_document.stories[0].wall_height = 4.2; authored_height_game := Game{}; authored_height_game.wall_cutaways[0] = .5; assert(math.abs(house_authored_wall_height() - 4.2) < .001 && math.abs(house_wall_section_height(&authored_height_game, 0) - (4.2 + HOUSE_CUTAWAY_HEIGHT) * .5) < .001 && math.abs(house_wall_finish_bands()[3] - 4.2) < .001); level_document.stories[0].wall_height = 3.5; garden_wall := Floorplan_Wall {
		a = {19, 18},
		b = {29, 18},
	}; garden_cut_game := Game {
		player_x                 = 24,
		player_y                 = 24,
		camera_x                 = 24,
		camera_y                 = 24,
		camera_orbit             = -f32(math.PI) / 2,
		camera_orbit_initialized = true,
		camera_zoom              = 1,
	}; assert(
		house_wall_cutaway_target(&garden_cut_game, &garden_wall) == 0,
	); garden_cut_game.camera_orbit = math.PI / 2; assert(house_wall_cutaway_target(&garden_cut_game, &garden_wall) == 0); garden_cut_game.wall_view = .Walls_Down; assert(house_wall_cutaway_target(&garden_cut_game, &garden_wall) == 1); garden_cut_game.wall_view = .Walls_Up; assert(house_wall_cutaway_target(&garden_cut_game, &garden_wall) == 0); pantry_corner_game := Game {
		player_x                 = 30,
		player_y                 = 14,
		camera_x                 = 30,
		camera_y                 = 14,
		camera_orbit             = -3 * f32(math.PI) / 4,
		camera_orbit_initialized = true,
		camera_zoom              = .55,
	}; pantry_west := Floorplan_Wall {
		a = {27, 10},
		b = {27, 18},
	}; pantry_south := Floorplan_Wall {
		a = {27, 10},
		b = {33, 10},
	}; assert(
		house_room_at_point({30, 14}) == level_room_index(&level_document, "pantry"),
	); pantry_camera := house_wall_camera_position(&pantry_corner_game); assert(!house_wall_sightline_crosses_window(&pantry_west, {30, 14}, pantry_camera)); assert(house_wall_cutaway_target(&pantry_corner_game, &pantry_west) == 1); assert(house_wall_cutaway_target(&pantry_corner_game, &pantry_south) == 1); level_document = cutaway_saved_doc
	window_cull_saved_openings := house_plan.openings; window_cull_wall := Floorplan_Wall {
		a = {0, 0},
		b = {4, 0},
	}; house_plan.openings = make(
		[dynamic]Plan_Opening,
		0,
		1,
	); append(&house_plan.openings, Plan_Opening{a = {1.5, 0}, b = {2.5, 0}, kind = .Window}); assert(house_wall_sightline_crosses_window(&window_cull_wall, {2, 1}, {2, -1})); assert(!house_wall_sightline_crosses_window(&window_cull_wall, {3, 1}, {3, -1})); delete(house_plan.openings); house_plan.openings = window_cull_saved_openings
	level_document =
		cutaway_doc; study_room := level_room_index(&level_document, "study"); garden_room := level_room_index(&level_document, "moon_garden"); assert(study_room >= 0 && garden_room >= 0 && house_room_at_point(level_room_center(&level_document.rooms[study_room])) == study_room && house_room_at_point(level_room_center(&level_document.rooms[garden_room])) < 0); assert(house_outdoor_exposure_at_point(level_room_center(&level_document.rooms[study_room])) == 0 && house_outdoor_exposure_at_point(level_room_center(&level_document.rooms[garden_room])) == 1 && house_outdoor_exposure_at_point({2, 2}) == 1); ceiling_test := procedural_room_ceiling_mesh(level_document.rooms[study_room]); assert(ceiling_test.ready && len(ceiling_test.indices) >= 3); ceiling_a, ceiling_b, ceiling_c := ceiling_test.vertices[ceiling_test.indices[0]], ceiling_test.vertices[ceiling_test.indices[1]], ceiling_test.vertices[ceiling_test.indices[2]]; ceiling_ab := Vec3{ceiling_b.x - ceiling_a.x, ceiling_b.y - ceiling_a.y, ceiling_b.z - ceiling_a.z}; ceiling_ac := Vec3{ceiling_c.x - ceiling_a.x, ceiling_c.y - ceiling_a.y, ceiling_c.z - ceiling_a.z}; assert(ceiling_ab.z * ceiling_ac.x - ceiling_ab.x * ceiling_ac.z > 0); interior_center := level_room_center(&level_document.rooms[study_room]); roof_game := Game {
		camera_pose_override   = true,
		camera_eye_override    = {2, 1.5, 2},
		camera_target_override = {interior_center.x, 0, interior_center.y},
	}; assert(
		!house_roof_visible(&roof_game),
	); roof_game.camera_target_override = {2, 0, 2}; assert(house_roof_visible(&roof_game)); level_document = cutaway_saved_doc
	fmt.println("SELF TEST · CUTAWAY AND ROOF COMPLETE")
	assert(
		house_door_render_height(Plan_Opening{height = 2.35}) == 2.35 &&
		house_door_render_height(Plan_Opening{}) == 2.1 &&
		house_door_render_width(1.6) == 1.6 &&
		house_door_render_width(1.4) == 1.4 &&
		house_door_casing_height(Plan_Opening{height = 2.35}) == 2.35 &&
		house_door_casing_height(Plan_Opening{}) == 2.1,
	)
	assert(
		math.abs(
			house_opening_face_offset(
				Plan_Opening{wall_width = HOUSE_INTERIOR_WALL_THICKNESS},
				.004,
			) -
			(HOUSE_INTERIOR_WALL_THICKNESS * .5 + .004),
		) <
		.0001,
	)
	assert(
		house_wall_cap_edge_mesh_for_width(HOUSE_INTERIOR_WALL_THICKNESS) ==
		&house_wall_cap_edge_interior_mesh,
	)
	assert(
		house_wall_cap_edge_mesh_for_width(HOUSE_EXTERIOR_WALL_THICKNESS) ==
		&house_wall_cap_edge_mesh,
	)
	casing_test := Plan_Opening {
		height = 2.1,
	}; casing_head_base := house_door_casing_head_base(
		casing_test,
	); assert(HOUSE_DOOR_CASING_RAIL > .001 && house_door_casing_jamb_height(casing_test, HOUSE_WALL_HEIGHT) == 2.1 && house_door_casing_jamb_height(casing_test, HOUSE_CUTAWAY_HEIGHT) == HOUSE_CUTAWAY_HEIGHT && house_door_casing_jamb_height(casing_test, -1) == 0); assert(math.abs(casing_head_base - (2.1 - HOUSE_DOOR_CASING_RAIL * .5)) < .0001 && house_door_casing_head_height(casing_test, HOUSE_WALL_HEIGHT) == HOUSE_DOOR_CASING_RAIL && house_door_casing_head_height(casing_test, casing_head_base) == 0 && math.abs(house_door_casing_head_height(casing_test, casing_head_base + HOUSE_DOOR_CASING_RAIL * .5) - HOUSE_DOOR_CASING_RAIL * .5) < .0001)
	assert(
		house_door_handle_height(Plan_Opening{height = 2.35}) == 1.02 &&
		math.abs(house_door_handle_height(Plan_Opening{}) - 1.02) < .0001 &&
		HOUSE_DOOR_HANDLE_ALONG > 0 &&
		HOUSE_DOOR_HANDLE_ALONG < 1,
	)
	assert(
		house_window_lower_masonry_height(1.5, 1.35) == 1.35 &&
		house_window_lower_masonry_height(.72, 1.35) == .72 &&
		house_window_lower_masonry_height(.72, -1) == 0,
	)
	door_proportion_mesh := procedural_wall_mesh(
		1.4,
		2.1,
		.07,
	); door_proportion_model := vk_world_model(&door_proportion_mesh, 0, 0, 1.2, 2.35, 0, 0, 0, false); assert(math.abs(door_proportion_model[0] - 1.2 / 1.4) < .0001 && math.abs(door_proportion_model[5] - 2.35 / 2.1) < .0001 && math.abs(door_proportion_model[10] - 1) < .0001)
	art_opacity_low, art_opacity_mid, art_opacity_high :=
		house_wall_art_opacity(HOUSE_CUTAWAY_HEIGHT),
		house_wall_art_opacity((HOUSE_WALL_ART_FADE_BOTTOM + HOUSE_WALL_ART_FADE_TOP) * .5),
		house_wall_art_opacity(
			HOUSE_WALL_HEIGHT,
		); assert(art_opacity_low == 0 && art_opacity_mid >= 127 && art_opacity_mid <= 128 && art_opacity_high == 255 && art_opacity_low < art_opacity_mid && art_opacity_mid < art_opacity_high && house_wall_art_supported(HOUSE_WALL_HEIGHT) && !house_wall_art_supported(HOUSE_CUTAWAY_HEIGHT))
	assert(
		window_style_from_name("casement") == .Casement &&
		window_style_from_name("awning") == .Awning &&
		window_style_from_name("picture") == .Picture &&
		window_style_from_name("double_hung") == .Double_Hung &&
		window_style_name(.Fixed) == "fixed" &&
		window_style_name(.Picture) == "picture" &&
		window_style_label(.Double_Hung) == "DOUBLE",
	)
	assert(
		house_aperture_top_for_height(
			Plan_Opening{id = "ordinary_window"},
			HOUSE_CUTAWAY_HEIGHT,
		) ==
			HOUSE_CUTAWAY_HEIGHT &&
		math.abs(
			house_aperture_top_for_height(
				Plan_Opening{id = "window_study_courtyard", height = 1.4, sill_height = .72},
				HOUSE_CUTAWAY_HEIGHT,
			) -
			2.175,
		) <
			.0001,
	)
	door_header_draws := make(
		[dynamic]Personal_Surface_Draw,
		0,
		2,
	); door_header_pixels := make([dynamic]u8, 0, 4); append(&door_header_pixels, 255, 255, 255, 255); door_header_texture := Glb_Texture_Data {
		pixels = door_header_pixels,
	}; append_door_wallpaper_header_draw(
		&door_header_draws,
		Plan_Opening{a = {0, 0}, b = {1.4, 0}, kind = .Door},
		true,
		door_header_texture,
		0,
	); door_header_height: f32 = 0; for draw in door_header_draws do door_header_height += draw.region_height; assert(len(door_header_draws) == 2 && math.abs(door_header_draws[0].region_base - 2.1) < .001 && math.abs(door_header_height - (HOUSE_WALL_HEIGHT - 2.1)) < .001 && door_header_draws[0].mesh.max.y - door_header_draws[0].mesh.min.y == door_header_draws[0].region_height)
	cap_test := Glb_Mesh {
		vertices   = make([dynamic]Vec3, 0, 4),
		texcoords  = make([dynamic]Vec2, 0, 4),
		indices    = make([dynamic]u32, 0, 12),
		primitives = make([dynamic]Glb_Primitive_Range, 0, 1),
	}; append_wall_cap_batch(
		&cap_test,
		{0, 0},
		{2, 0},
		HOUSE_WALL_HEIGHT,
		HOUSE_WALL_THICKNESS,
	); finalize_wall_cap_batch(&cap_test, HOUSE_WALL_HEIGHT); assert(cap_test.ready && len(cap_test.vertices) == 4 && len(cap_test.indices) == 12 && cap_test.min.y == 0 && cap_test.max.y == HOUSE_WALL_HEIGHT)
	wall_finish_bands := house_wall_finish_bands(

	); wallpaper_region_test := wallpaper_face_mesh({0, 0}, {2, 0}, HOUSE_CUTAWAY_HEIGHT, .625); assert(math.abs((wallpaper_region_test.max.y - wallpaper_region_test.min.y) - .625) < .0001 && math.abs(wallpaper_region_test.texcoords[0].y - HOUSE_CUTAWAY_HEIGHT * HOUSE_WALL_COVERING_UV_SCALE) < .0001 && math.abs(wallpaper_region_test.texcoords[2].y - (HOUSE_CUTAWAY_HEIGHT + .625) * HOUSE_WALL_COVERING_UV_SCALE) < .0001 && wall_finish_bands[0] == 0 && wall_finish_bands[len(wall_finish_bands) - 1] == HOUSE_WALL_HEIGHT)
	core_region_test := procedural_wall_band_mesh(
		{0, 0},
		{2, 0},
		HOUSE_CUTAWAY_HEIGHT,
		.625,
		HOUSE_WALL_THICKNESS,
	); assert(len(core_region_test.indices) == 24 && core_region_test.primitives[0].count == 24 && math.abs((core_region_test.max.y - core_region_test.min.y) - .625) < .0001 && math.abs(core_region_test.texcoords[0].y - HOUSE_CUTAWAY_HEIGHT * HOUSE_WALL_COVERING_UV_SCALE) < .0001 && math.abs(core_region_test.texcoords[6].y - (HOUSE_CUTAWAY_HEIGHT + .625) * HOUSE_WALL_COVERING_UV_SCALE) < .0001)
	assert(VK_WORLD_MAX_DESCRIPTOR_SETS >= 1024)
	assert(
		house_window_light_columns(.8) == 1 &&
		house_window_light_columns(1.6) == 2 &&
		house_window_light_columns(2.8) == 3 &&
		house_window_light_columns(5.8) == 5,
	); assert(house_window_light_rows(.9) == 1 && house_window_light_rows(1.4) == 2 && house_window_light_rows(2.4) == 3)
	assert(
		house_window_muntin_width(HOUSE_WINDOW_FRAME_RAIL_HEIGHT) <
			HOUSE_WINDOW_FRAME_RAIL_HEIGHT &&
		house_window_muntin_width(.02) == .022,
	)
	assert(
		house_window_glazing_bead_width(HOUSE_WINDOW_FRAME_RAIL_HEIGHT) <
			HOUSE_WINDOW_FRAME_RAIL_HEIGHT &&
		house_window_glazing_bead_width(.02) == .014,
	)
	glazing_test := procedural_glazing_mesh(
		2,
		1.4,
	); assert(glazing_test.ready && glazing_is_single_sheet(&glazing_test))
	bead_profile_test := procedural_wall_mesh(
		.016,
		1.4,
		HOUSE_WINDOW_GLAZING_BEAD_DEPTH,
	); assert(math.abs((bead_profile_test.max.z - bead_profile_test.min.z) - HOUSE_WINDOW_GLAZING_BEAD_DEPTH) < .0001 && HOUSE_WINDOW_GLAZING_BEAD_DEPTH < .045)
	hardware_profile_test := procedural_wall_mesh(
		.025,
		.16,
		HOUSE_WINDOW_HARDWARE_DEPTH,
	); assert(math.abs((hardware_profile_test.max.z - hardware_profile_test.min.z) - HOUSE_WINDOW_HARDWARE_DEPTH) < .0001 && HOUSE_WINDOW_HARDWARE_DEPTH > HOUSE_WINDOW_GLAZING_BEAD_DEPTH && HOUSE_WINDOW_HARDWARE_DEPTH < .045)
	muntin_profile_test := procedural_wall_mesh(
		.03,
		1.4,
		HOUSE_WINDOW_MUNTIN_DEPTH,
	); assert(math.abs((muntin_profile_test.max.z - muntin_profile_test.min.z) - HOUSE_WINDOW_MUNTIN_DEPTH) < .0001 && HOUSE_WINDOW_MUNTIN_DEPTH < .045)
	assert(
		house_window_casing_width(true) > house_window_casing_width(false) &&
		house_window_casing_width(false) > HOUSE_WINDOW_FRAME_RAIL_HEIGHT,
	)
	assert(house_window_head_flashing_overhang() > house_window_casing_width(true))
	assert(
		house_window_head_flashing_end_dam_width() < house_window_head_flashing_overhang() &&
		house_window_head_flashing_end_dam_height() > .04,
	)
	assert(
		house_window_operable_sash_offset(.Casement) > 0 &&
		house_window_operable_sash_offset(.Awning) ==
			house_window_operable_sash_offset(.Casement) &&
		house_window_operable_sash_offset(.Fixed) == 0 &&
		house_window_operable_sash_offset(.Double_Hung) == 0,
	)
	assert(
		house_window_operable_frame_width(HOUSE_WINDOW_FRAME_RAIL_HEIGHT) <
			HOUSE_WINDOW_FRAME_RAIL_HEIGHT &&
		house_window_operable_frame_width(.02) == .022,
	)
	assert(
		house_window_operable_mullion_count(.Casement, 1) == 0 &&
		house_window_operable_mullion_count(.Casement, 2) == 1 &&
		house_window_operable_mullion_count(.Casement, 3) == 2 &&
		house_window_operable_mullion_count(.Awning, 3) == 0,
	)
	assert(
		house_window_perimeter_sealant_width() <
			house_window_glazing_bead_width(HOUSE_WINDOW_FRAME_RAIL_HEIGHT) &&
		house_window_perimeter_sealant_width() < house_window_casing_width(false),
	)
	assert(
		house_window_interior_caulk_width() < house_window_perimeter_sealant_width() &&
		house_window_interior_caulk_width() < house_window_casing_width(true),
	)
	assert(
		level_opening_finish_clearance(.Window, .Window) == .24 &&
		level_opening_finish_clearance(.Door, .Door) == .12 &&
		level_opening_end_clearance(.Window) == .12,
	)
	assert(math.abs(level_window_head_finish_height(.72, 1.4) - 2.25) < .001)
	single_handles, single_hinges := house_window_casement_hardware_count(
		1,
	); paired_handles, paired_hinges := house_window_casement_hardware_count(2); assert(single_handles == 1 && single_hinges == 1 && paired_handles == 2 && paired_hinges == 2 && house_window_casement_handle_along(1, 0, .7, .06) > 0 && house_window_casement_hinge_along(1, 0, .7, .06) < 0 && house_window_casement_handle_along(1, 0, .7, .06, true) < 0 && house_window_casement_hinge_along(1, 0, .7, .06, true) > 0 && house_window_casement_hinge_along(2, 1, .7, .06) > 0)
	assert(
		house_window_double_hung_sash_offset() > .006 &&
		house_window_double_hung_sash_offset() < .0225,
	)
	frame_bead_offset := f32(
		.045 * .5 + .004,
	); upper_bead_offset := house_window_double_hung_upper_bead_offset(frame_bead_offset); assert(upper_bead_offset > 0 && upper_bead_offset < frame_bead_offset)
	assert(
		house_window_double_hung_stile_along(1.49, .055) > .70 &&
		house_window_double_hung_stile_along(.03, .055) == 0,
	)
	assert(
		house_window_double_hung_parting_bead_width(.055) < .02 &&
		house_window_double_hung_parting_bead_width(.02) == .012 &&
		house_window_double_hung_parting_bead_along(1.49, .055) >
			house_window_double_hung_stile_along(1.49, .055),
	)
	assert(
		house_window_internal_vertical_width(.Casement, .06) == .06 &&
		house_window_internal_vertical_width(.Fixed, .06) < .06 &&
		house_window_internal_horizontal_width(.Double_Hung, .06) == .06 &&
		house_window_internal_horizontal_width(.Fixed, .06) < .06,
	)
	fixed_columns, fixed_rows := house_window_style_grid(
		.Fixed,
		1.6,
		1.4,
	); picture_columns, picture_rows := house_window_style_grid(.Picture, 3.6, 1.8); casement_columns, casement_rows := house_window_style_grid(.Casement, .8, 1.4); paired_casement_columns, _ := house_window_style_grid(.Casement, 1.6, 1.4); awning_columns, awning_rows := house_window_style_grid(.Awning, 2.8, .9); _, tall_awning_rows := house_window_style_grid(.Awning, 2.8, 1.4); hung_columns, hung_rows := house_window_style_grid(.Double_Hung, 1.6, .9); assert(fixed_columns == 2 && fixed_rows == 2 && picture_columns == 1 && picture_rows == 1 && casement_columns == 1 && casement_rows == 1 && paired_casement_columns == 2 && awning_columns == 1 && awning_rows == 1 && tall_awning_rows == 2 && hung_columns == 2 && hung_rows == 2)
	wallpaper_window := Plan_Opening {
		a           = {0, 0},
		b           = {2, 0},
		kind        = .Window,
		height      = 1.4,
		sill_height = .72,
	}; wallpaper_full, wallpaper_cut :=
		Glb_Mesh{},
		Glb_Mesh{}; append_window_wallpaper_regions(&wallpaper_full, wallpaper_window, true, HOUSE_WALL_HEIGHT); append_window_wallpaper_regions(&wallpaper_cut, wallpaper_window, true, HOUSE_CUTAWAY_HEIGHT); assert(len(wallpaper_full.vertices) == 8 && len(wallpaper_full.indices) == 12 && math.abs(wallpaper_full.vertices[2].y - .72) < .001 && math.abs(wallpaper_full.vertices[4].y - 2.12) < .001 && len(wallpaper_cut.vertices) == 4 && len(wallpaper_cut.indices) == 6)
	wallpaper_below := wallpaper_face_mesh(
		{0, 0},
		{2, 0},
		0,
		.72,
	); wallpaper_above := wallpaper_face_mesh({0, 0}, {2, 0}, 2.12, 1.38); wallpaper_adjacent := wallpaper_face_mesh({2, 0}, {4, 0}, 0, 3.5); assert(wallpaper_below.texcoords[1].x == wallpaper_adjacent.texcoords[0].x && wallpaper_below.texcoords[2].y == .72 * HOUSE_WALL_COVERING_UV_SCALE && wallpaper_above.texcoords[0].x == wallpaper_below.texcoords[0].x && wallpaper_above.texcoords[0].y == 2.12 * HOUSE_WALL_COVERING_UV_SCALE)
	exterior_finish_span := house_exterior_opening_finish_span(
		wallpaper_window,
	); assert(math.abs((exterior_finish_span.b.x - exterior_finish_span.a.x) - (2 + HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP * 2)) < .0001 && math.abs((exterior_finish_span.a.x + exterior_finish_span.b.x) * .5 - 1) < .0001)
	assert(
		door_style_from_name("double") == .Double &&
		door_style_from_name("sliding") == .Sliding &&
		door_style_from_name("") == .Hinged &&
		door_style_name(.Hinged) == "hinged" &&
		door_style_label(.Sliding) == "SLIDING",
	)
	door_style_doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &door_style_doc).ok); front_door_index := level_opening_index(&door_style_doc, "door_front"); sliding_door_index := level_opening_index(&door_style_doc, "door_study_garden"); assert(front_door_index >= 0 && sliding_door_index >= 0 && door_style_doc.openings[front_door_index].door_style == .Double && door_style_doc.openings[sliding_door_index].door_style == .Sliding && strings.contains(level_serialize(&door_style_doc), "door_style = \"double\"")); style_command, style_ok := level_door_style_command(&door_style_doc, "door_front", .Sliding); assert(style_ok && level_commit_transaction(&door_style_doc, style_command, "change door style") && door_style_doc.openings[front_door_index].door_style == .Sliding && level_undo(&door_style_doc) && door_style_doc.openings[front_door_index].door_style == .Double)
	wanderer_index := level_object_index(
		&door_style_doc,
		"painting_wanderer",
	); study_bedroom_door_index := level_opening_index(&door_style_doc, "door_study_master_bedroom"); assert(wanderer_index >= 0 && study_bedroom_door_index >= 0); wanderer := door_style_doc.objects[wanderer_index]; study_bedroom_door := door_style_doc.openings[study_bedroom_door_index]; study_bedroom_path_index := level_path_index(&door_style_doc, study_bedroom_door.host_path); assert(study_bedroom_path_index >= 0); study_bedroom_path := door_style_doc.paths[study_bedroom_path_index]; study_bedroom_a, study_bedroom_b := study_bedroom_path.points[study_bedroom_door.segment], study_bedroom_path.points[study_bedroom_door.segment + 1]; study_bedroom_door_x := study_bedroom_a.x + (study_bedroom_b.x - study_bedroom_a.x) * study_bedroom_door.position; assert(math.abs(wanderer.position.x - study_bedroom_door_x) > study_bedroom_door.width * .5 + .9)
	assert(
		door_style_doc.openings[front_door_index].interaction == .Door &&
		!door_style_doc.openings[front_door_index].initially_active &&
		door_style_doc.openings[front_door_index].interaction_range == 1.8,
	); interaction_serialized := level_serialize(&door_style_doc); assert(strings.contains(interaction_serialized, "interaction = \"door\"") && strings.contains(interaction_serialized, "interaction_range = 1.800")); interaction_command := Level_Command {
		kind               = .Set_Interaction,
		entity_id          = "door_front",
		interaction        = .Door,
		interaction_prompt = "Open the front door",
		interaction_range  = 2.25,
		initially_active   = true,
		locked             = true,
		powered            = true,
	}; assert(
		level_commit_transaction(
			&door_style_doc,
			interaction_command,
			"author door interaction",
		) &&
		door_style_doc.openings[front_door_index].initially_active &&
		door_style_doc.openings[front_door_index].locked &&
		door_style_doc.openings[front_door_index].interaction_prompt == "Open the front door",
	); assert(level_undo(&door_style_doc) && !door_style_doc.openings[front_door_index].initially_active && !door_style_doc.openings[front_door_index].locked)
	level_document = level_clone_document(
		&door_style_doc,
	); level_project_runtime(&level_document); range_game := Game {
		story_project = &test_story_project,
		screen        = .Investigate,
		player_x      = -100,
		player_y      = -100,
	}; runtime_interactives_rebuild(
		&range_game,
	); assert(range_game.interactive_count > 0); stale_target := context_runtime_target(&range_game, 0); stale_target.valid = true; stale_target.reachable = true; stale_target.distance = 0; assert(!context_activate_house(&range_game, stale_target))
	statuette_gate := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&statuette_gate,
	); statuette_clue := mystery_clue_index(mystery_game_payload(&statuette_gate), "clue_statuette"); assert(statuette_clue >= 0 && !clue_available(&statuette_gate, statuette_clue)); assert(clue_locked_label(&statuette_gate, statuette_clue) == "LOCKED — EXPOSE WHAT THE SHIFTED RUG CONCEALS"); statuette_gate.study_rug_lifted = true; assert(!clue_available(&statuette_gate, statuette_clue) && clue_locked_label(&statuette_gate, statuette_clue) == "LOCKED — FIND THE DETAIL MISSED ON THE POLISHED BRONZE"); statuette_gate.study_seam_found = true; assert(clue_available(&statuette_gate, statuette_clue))
	dialogue_flow := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&dialogue_flow,
	); _ = learn_claim(&dialogue_flow, "claim_miriam_dinner"); _ = learn_claim(&dialogue_flow, "claim_daniel_alibi"); _ = learn_claim(&dialogue_flow, "claim_elsie_study"); for i in 0 ..< mystery_dialogue_approach_count(mystery_game_payload(&dialogue_flow)) {approach := mystery_dialogue_approach_at(mystery_game_payload(&dialogue_flow), i); if approach.node_id == "approach_miriam_alibi" || approach.node_id == "approach_daniel_alibi" || approach.node_id == "approach_elsie_denial" do _ = mystery_game_mark_dialogue(&dialogue_flow, i, false)}; miriam_first := mystery_dialogue_approach_at(mystery_game_payload(&dialogue_flow), visible_dialogue_approach(&dialogue_flow, "miriam", 0)); daniel_first := mystery_dialogue_approach_at(mystery_game_payload(&dialogue_flow), visible_dialogue_approach(&dialogue_flow, "daniel", 0)); elsie_first := mystery_dialogue_approach_at(mystery_game_payload(&dialogue_flow), visible_dialogue_approach(&dialogue_flow, "elsie", 0)); assert(miriam_first != nil && miriam_first.node_id == "approach_miriam_summons_denial"); assert(daniel_first != nil && daniel_first.node_id == "approach_daniel_affair"); assert(elsie_first != nil && elsie_first.node_id == "approach_elsie_routine")
	guidance_flow := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&guidance_flow,
	); assert(strings.contains(investigation_unresolved_summary(&guidance_flow), "remain separated") && !strings.contains(investigation_unresolved_summary(&guidance_flow), "Start with")); _ = learn_claim(&guidance_flow, "claim_miriam_dinner"); _ = learn_claim(&guidance_flow, "claim_daniel_alibi"); _ = learn_claim(&guidance_flow, "claim_elsie_study"); assert(strings.contains(investigation_unresolved_summary(&guidance_flow), "remain under guard") && !strings.contains(investigation_unresolved_summary(&guidance_flow), "Inspect Edgar")); guidance_flow.desk_key_found = true; guidance := investigation_unresolved_summary(&guidance_flow); assert(strings.contains(guidance, "case board") || strings.contains(guidance, "secured source") || strings.contains(guidance, "account") || strings.contains(guidance, "record")); assert(!strings.contains(guidance, "Take this") && !strings.contains(guidance, "Follow the next"))
	Officer_Fixture :: struct {
		entity, scene, entry: string,
	}; officer_fixtures := [3]Officer_Fixture {
		{"officer_lead", "scene_officer_lead", "officer_lead_open"},
		{"officer_hall", "scene_officer_hall", "officer_hall_open"},
		{"officer_garden", "scene_officer_garden", "officer_garden_open"},
	}; for fixture in officer_fixtures {entity := story_entity_index(&test_story_project, fixture.entity); scene := story_scene_index(&test_story_project, fixture.scene); assert(entity >= 0 && test_story_project.entities[entity].interaction_scene_id == fixture.scene && scene >= 0 && test_story_project.scenes[scene].entry_node == fixture.entry)}; lead_choice := story_node_index(&test_story_project, "scene_officer_lead", "officer_lead_choices"); confirm := story_node_index(&test_story_project, "scene_officer_lead", "officer_lead_confirm"); conclusion := story_node_index(&test_story_project, "scene_officer_lead", "officer_lead_conclusion"); assert(lead_choice >= 0 && test_story_project.nodes[lead_choice].choice_count == 2 && confirm >= 0 && test_story_project.nodes[confirm].choice_count == 2 && conclusion >= 0 && test_story_project.nodes[conclusion].domain_ref == "investigation.conclusion_presented")
	officer_compiled := compile_story_project(
		&test_story_project,
	); assert(officer_compiled.ok); officer_runtime := story_runtime_new(&officer_compiled.story); officer_state := cast(^Mystery_State)story_runtime_capability_state(&officer_runtime, "mystery", MYSTERY_DOMAIN_VERSION); assert(officer_state != nil && mystery_string_set_add(&officer_state.earned_deductions, "ded_miriam_denial_disproved")); officer_step := story_runtime_enter_scene(&officer_runtime, "scene_officer_hall"); assert(officer_step.ok && officer_step.node_id == "officer_hall_open"); officer_step = story_runtime_advance(&officer_runtime); assert(officer_step.ok && officer_step.node_id == "officer_hall_miriam"); story_runtime_destroy(&officer_runtime); story_compile_result_destroy(&officer_compiled)
	reentry_flow := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&reentry_flow,
	); assert(strings.contains(character_reentry_line(&reentry_flow, "miriam"), "ask it precisely") && strings.contains(character_reentry_line(&reentry_flow, "daniel"), "professionally useless") && strings.contains(character_reentry_line(&reentry_flow, "elsie"), "work will still be waiting")); assert(mystery_string_set_add(&reentry_flow.mystery_state.earned_deductions, "ded_scene_staged") && strings.contains(character_reentry_line(&reentry_flow, "miriam"), "audience with an author") && strings.contains(character_reentry_line(&reentry_flow, "daniel"), "name omitted") && strings.contains(character_reentry_line(&reentry_flow, "elsie"), "dead gentlemen")); assert(mystery_string_set_add(&reentry_flow.mystery_state.earned_deductions, "ded_daniel_affair") && strings.contains(character_reentry_line(&reentry_flow, "daniel"), "what I was protecting")); assert(mystery_string_set_add(&reentry_flow.mystery_state.earned_deductions, "ded_elsie_theft") && strings.contains(character_reentry_line(&reentry_flow, "miriam"), "taught confession") && strings.contains(character_reentry_line(&reentry_flow, "elsie"), "worst thing I did")); assert(mystery_string_set_add(&reentry_flow.mystery_state.earned_deductions, "ded_miriam_denial_disproved") && strings.contains(character_reentry_line(&reentry_flow, "miriam"), "scrap of paper") && strings.contains(character_reentry_line(&reentry_flow, "daniel"), "missing piece") && strings.contains(character_reentry_line(&reentry_flow, "elsie"), "edges inward"))
	failed_reentry := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&failed_reentry,
	); daniel_failure, elsie_failure := -1, -1; for i in 0 ..< mystery_dialogue_approach_count(mystery_game_payload(&failed_reentry)) {approach := mystery_dialogue_approach_at(mystery_game_payload(&failed_reentry), i); if approach.node_id == "approach_daniel_affair" do daniel_failure = i; if approach.node_id == "approach_elsie_theft" do elsie_failure = i}; assert(daniel_failure >= 0 && elsie_failure >= 0 && strings.contains(dialogue_approach_failure_response(&failed_reentry, daniel_failure), "sentence is rehearsed") && strings.contains(dialogue_approach_failure_response(&failed_reentry, elsie_failure), "counts silently")); unlock_topic(&failed_reentry, "failed_daniel_affair"); unlock_topic(&failed_reentry, "failed_elsie_theft"); assert(strings.contains(character_reentry_line(&failed_reentry, "daniel"), "pockets are not part of the estate") && strings.contains(character_reentry_line(&failed_reentry, "elsie"), "without deciding the answer"))
	evidence_daniel := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&evidence_daniel,
	); daniel_clue := mystery_clue_index(mystery_game_payload(&evidence_daniel), "clue_daniel"); dinner_clue := mystery_clue_index(mystery_game_payload(&evidence_daniel), "clue_dinner_settings"); assert(daniel_clue >= 0 && dinner_clue >= 0 && mystery_game_mark_clue(&evidence_daniel, dinner_clue)); daniel_feedback := dialogue_evidence_feedback(&evidence_daniel, daniel_clue); assert(strings.contains(daniel_feedback, "thumb finds the crease") && strings.contains(daniel_feedback, "what occupied it"))
	evidence_elsie := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&evidence_elsie,
	); elsie_clue := mystery_clue_index(mystery_game_payload(&evidence_elsie), "clue_elsie"); ledger_clue := mystery_clue_index(mystery_game_payload(&evidence_elsie), "clue_ledger"); assert(elsie_clue >= 0 && ledger_clue >= 0 && mystery_game_mark_clue(&evidence_elsie, ledger_clue)); assert(strings.contains(dialogue_evidence_feedback(&evidence_elsie, elsie_clue), "missing in more than one direction"))
	evidence_elsie_stub := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&evidence_elsie_stub,
	); stub_clue := mystery_clue_index(mystery_game_payload(&evidence_elsie_stub), "clue_appointment_stub"); assert(stub_clue >= 0 && mystery_game_mark_clue(&evidence_elsie_stub, stub_clue)); assert(strings.contains(dialogue_evidence_feedback(&evidence_elsie_stub, elsie_clue), "reads the name once") && strings.contains(dialogue_evidence_feedback(&evidence_elsie_stub, elsie_clue), "ask me that"))
	environment_copy := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&environment_copy,
	); environment_sources := [6]string{"body", "study_rug", "study_desk", "memo_stub", "edgar_watch", "burned_note"}; for source in environment_sources {entity_index := story_entity_index(environment_copy.story_project, source); assert(entity_index >= 0 && public_source_description(&environment_copy, source) == environment_copy.story_project.entities[entity_index].description && wrapped_line_count(public_source_description(&environment_copy, source), 445, .78) <= 5)}
	garden_question := question_index_by_id(
		&guidance_flow,
		"q_garden_murder",
	); assert(garden_question >= 0 && strings.contains(mystery_question_hypothesis_text(&guidance_flow, &payload.questions[garden_question]), "outdoor route with traces inside"))
	reflection_flow := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&reflection_flow,
	); assert(strings.contains(pond_reflection_line(&reflection_flow), "collection of surfaces")); unlock_topic(&reflection_flow, "edgar_controlled_by_correction"); unlock_topic(&reflection_flow, "edgar_kept_leverage"); unlock_topic(&reflection_flow, "edgar_household_power"); assert(strings.contains(pond_reflection_line(&reflection_flow), "Three portraits of Edgar") && strings.contains(pond_reflection_line(&reflection_flow), "who merely learned to fear him")); assert(mystery_string_set_add(&reflection_flow.mystery_state.earned_deductions, "ded_scene_staged") && strings.contains(pond_reflection_line(&reflection_flow), "performance left in the rain")); assert(mystery_string_set_add(&reflection_flow.mystery_state.earned_deductions, "ded_daniel_affair") && strings.contains(pond_reflection_line(&reflection_flow), "private fear")); assert(mystery_string_set_add(&reflection_flow.mystery_state.earned_deductions, "ded_elsie_theft") && strings.contains(pond_reflection_line(&reflection_flow), "Two lies have opened")); assert(mystery_string_set_add(&reflection_flow.mystery_state.earned_deductions, "ded_miriam_denial_disproved") && strings.contains(pond_reflection_line(&reflection_flow), "two scraps of paper"))
	check_copy := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&check_copy,
	); check_copy.pending_clue = mystery_clue_index(mystery_game_payload(&check_copy), "clue_ledger"); check_label := dialogue_check_commit_label(&check_copy, 1); assert(strings.contains(check_label, "ROLL ANALYSIS CHECK") && strings.contains(check_label, "1 TICK") && !strings.contains(check_label, "TRANSFERS")); failure_text := dialogue_check_failure_text(&check_copy, "white"); assert(strings.contains(failure_text, "red pencil could still be emphasis") && strings.contains(failure_text, "another tick to try again")); mystery_game_mark_clue_attempted(&check_copy, check_copy.pending_clue); assert(clue_available(&check_copy, check_copy.pending_clue)); mystery_game_payload(&check_copy).clues[check_copy.pending_clue].check_kind = "red"; assert(!clue_available(&check_copy, check_copy.pending_clue))
	pace_copy := Game {
		ap             = 12,
		screen         = .Investigate,
		phase          = .Investigation,
		animation_time = 300,
	}; initialize_test_mystery_state(
		&pace_copy,
	); update_case_pacing(&pace_copy); assert(pace_copy.case_pacing_mask == 1 && pacing_time_label(pace_copy.case_pacing_times[0]) == "05:00"); _ = learn_claim(&pace_copy, "claim_miriam_dinner"); _ = learn_claim(&pace_copy, "claim_daniel_alibi"); _ = learn_claim(&pace_copy, "claim_elsie_study"); pace_copy.animation_time = 600; update_case_pacing(&pace_copy); assert((pace_copy.case_pacing_mask & 2) != 0 && pacing_time_label(pace_copy.case_pacing_times[1]) == "10:00"); for i in 0 ..< mystery_dialogue_approach_count(mystery_game_payload(&pace_copy)) {approach := mystery_dialogue_approach_at(mystery_game_payload(&pace_copy), i); if approach.node_id == "approach_miriam_edgar" do assert(mystery_game_mark_dialogue(&pace_copy, i, false))}; configure_complete_questions(&pace_copy); pace_copy.animation_time = 3600; pace_copy.screen = .Result; pace_copy.phase = .Case_Result; update_case_pacing(&pace_copy); assert(pace_copy.case_pacing_mask == 63 && pacing_time_label(pace_copy.case_pacing_times[5]) == "60:00"); pace_report := case_pacing_report_text(&pace_copy); assert(strings.contains(pace_report, "Arrival: 05:00 · target 00:00–05:00 · ON TARGET") && strings.contains(pace_report, "False scene: 60:00 · target 15:00–30:00 · LATE") && strings.contains(pace_report, "Outcome: 60:00 · target 55:00–60:00 · ON TARGET") && strings.contains(pace_report, "Designed optional beats: 1/7 — Miriam's clock memory") && strings.contains(pace_report, "Other optional scenes encountered:") && strings.contains(pace_report, "Confusion or dead air:")); assert(pacing_band_status(299, 300, 900) == "EARLY" && pacing_band_status(300, 300, 900) == "ON TARGET" && pacing_band_status(901, 300, 900) == "LATE")
	assert(
		level_load(LEVEL_DEFAULT_PATH, &level_document).ok,
	); level_project_runtime(&level_document); assert(world_entities_rebuild(&test_story_project, &level_document).ok); access_test := Game {
		story_project = &test_story_project,
		ap            = 12,
	}; initialize_test_mystery_state(
		&access_test,
	); cloth_poi := poi_index(&access_test, "cloth"); ledger_poi := poi_index(&access_test, "ledger"); desk_poi := poi_index(&access_test, "study_desk"); assert(cloth_poi >= 0 && ledger_poi >= 0 && desk_poi >= 0); assert(reveal_location_pois(&access_test, 4) && !mystery_game_poi_revealed(&access_test, cloth_poi)); assert(nav_build_path(&access_test, {22, 12}, {30.5, 26})); access_test.player_x = 30.5; access_test.player_y = 26; scullery_room := world_authored_room_at_point({access_test.player_x, access_test.player_y}); assert(scullery_room >= 0 && level_document.rooms[scullery_room].id == "scullery" && room_has_available_lead(&access_test)); access_test.player_x = 35; access_test.player_y = 20; assert(!room_has_available_lead(&access_test)); access_test.player_x = 30.5; access_test.player_y = 26; assert(reveal_service_closet(&access_test) && mystery_game_poi_revealed(&access_test, cloth_poi) && access_test.service_closet_entered); assert(!reveal_service_closet(&access_test)); locked_desk := Game {
		story_project = &test_story_project,
		ap            = 12,
	}; initialize_test_mystery_state(
		&locked_desk,
	); assert(reveal_location_pois(&locked_desk, 2) && mystery_game_poi_revealed(&locked_desk, desk_poi) && !mystery_game_poi_revealed(&locked_desk, ledger_poi)); assert(nav_build_path(&locked_desk, {10, 21}, {13, 23})); desk_entity, body_entity := world_entity_index("study_desk"), world_entity_index("body"); ledger_entity := world_entity_index("ledger"); assert(desk_entity >= 0 && body_entity >= 0 && ledger_entity >= 0 && !entity_visible(&locked_desk, &WORLD_ENTITIES[ledger_entity])); locked_desk.desk_key_found = true; dialogue_interaction_enter(&locked_desk, .Desk); dialogue_interaction_unlock_desk(&locked_desk); assert(locked_desk.dialogue_interaction.key_inserted && !locked_desk.dialogue_interaction.lock_turned); dialogue_interaction_unlock_desk(&locked_desk); dialogue_interaction_open_drawer(&locked_desk); assert(locked_desk.desk_open && entity_visible(&locked_desk, &WORLD_ENTITIES[ledger_entity]))
	city_context_game := Game {
		screen                         = .Exterior,
		driving_vehicle                = -1,
		near_vehicle                   = -1,
		near_landmark                  = -1,
		city_angle                     = 1,
		vehicle_skid_emit_distance     = .6,
		vehicle_impact_sound_cooldown  = .1,
		vehicle_camera_reverse_blend   = 1,
		vehicle_camera_follow_distance = 6,
	}; initialize_city_vehicles(
		&city_context_game,
	); city_context_game.vehicles[0].steering = .8; city_context_game.vehicles[0].acceleration_feedback = .6; city_context_game.vehicles[0].chassis_acceleration = -.5; city_context_game.vehicles[0].chassis_lateral_acceleration = .5; city_context_game.vehicles[0].velocity_x = .03; city_context_game.vehicles[0].traction_state = .Drift; city_context_game.vehicles[0].driver_assist = .ABS; city_context_game.vehicles[0].driver_assist_strength = 1; city_context_game.vehicles[0].driver_assist_time = .5; city_vehicle_target := Context_Target {
		valid        = true,
		kind         = .Vehicle,
		status       = .Available,
		source_index = 0,
		reachable    = true,
	}; assert(
		context_activate_city(&city_context_game, city_vehicle_target) &&
		city_context_game.driving_vehicle == 0 &&
		city_context_game.city_angle == city_context_game.vehicles[0].heading &&
		city_context_game.vehicles[0].steering == 0 &&
		city_context_game.vehicles[0].acceleration_feedback == 0 &&
		city_context_game.vehicles[0].chassis_acceleration == 0 &&
		city_context_game.vehicles[0].chassis_lateral_acceleration == 0 &&
		city_context_game.vehicles[0].driver_assist == .None &&
		city_context_game.vehicles[0].driver_assist_strength == 0 &&
		city_context_game.vehicles[0].driver_assist_time == 0 &&
		city_context_game.vehicles[0].velocity_x == .03 &&
		city_context_game.vehicles[0].traction_state == .Grip &&
		city_context_game.vehicle_skid_emit_distance == 0 &&
		city_context_game.vehicle_impact_sound_cooldown == 0 &&
		city_context_game.vehicle_camera_reverse_blend == 0 &&
		city_context_game.vehicle_camera_follow_distance == 0,
	)
	chaos_lot: Level_Document; assert(level_load("assets/levels/chaos_lot.toml", &chaos_lot).ok && level_validate(&chaos_lot).ok); assert(len(chaos_lot.rooms) == 4 && len(chaos_lot.roofs) == 4 && len(chaos_lot.openings) == 12 && len(chaos_lot.objects) == 1000 && len(chaos_lot.lights) == 10)
	crime_scene_doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &crime_scene_doc).ok); crime_marker_ids := [?]string{"crime_scene_body", "crime_scene_blood", "crime_scene_drag_trace", "crime_scene_cane", "crime_scene_watch"}; for marker_id in crime_marker_ids {assert(level_marker_index(&crime_scene_doc, marker_id) >= 0)}; level_document = level_clone_document(&crime_scene_doc); assert(world_entities_rebuild(&test_story_project, &level_document).ok); marker_body := level_document.markers[level_marker_index(&level_document, "crime_scene_body")]; body_anchor := WORLD_ENTITIES[world_entity_index("body")]; assert(body_anchor.x == marker_body.position.x && body_anchor.y == marker_body.position.y)
	fmt.println("SELF TEST · PRE-LEVEL GEOMETRY COMPLETE")
	level_test: Level_Document; level_result := level_load(LEVEL_DEFAULT_PATH, &level_test); assert(level_result.ok && level_test.version == LEVEL_FORMAT_VERSION && level_validate(&level_test).ok); serialized_level := level_serialize(&level_test); assert(strings.contains(serialized_level, "LevelFormat v1")); preview_ok := level_command_preview(&level_test, Level_Command{kind = .Create_Room, a = {9, 9}, b = {11, 11}}); preview_bad := level_command_preview(&level_test, Level_Command{kind = .Create_Room, a = {-1, 1}, b = {3, 3}}); _ = preview_ok; _ = preview_bad; assert(level_commit(&level_test, Level_Command{kind = .Create_Room, entity_id = "test_room", a = {25, 14}, b = {27, 16}, material = "gallery"}, "test room"))
	fmt.println("SELF TEST · LEVEL LOAD COMPLETE")
	vale_exterior_path := level_path_index(
		&level_test,
		"shell",
	); vale_interior_path := level_path_index(&level_test, "dining_pantry_a"); assert(vale_exterior_path >= 0 && vale_interior_path >= 0 && math.abs(level_test.paths[vale_exterior_path].width - HOUSE_EXTERIOR_WALL_THICKNESS) < .001 && math.abs(level_test.paths[vale_interior_path].width - HOUSE_INTERIOR_WALL_THICKNESS) < .001)
	path_doc := level_clone_document(
		&level_test,
	); path_width := path_doc.paths[0].width; path_target := path_doc.paths[0].kind == .Wall ? f32(.3) : f32(1.6); assert(level_commit_transaction(&path_doc, Level_Command{kind = .Set_Path, entity_id = path_doc.paths[0].id, value = path_target}, "resize path") && path_doc.paths[0].width == path_target); assert(level_undo(&path_doc) && path_doc.paths[0].width == path_width); water_doc := level_clone_document(&level_test); if len(water_doc.waters) == 0 {water_points := make([dynamic]Vec2, 0, 4); append(&water_points, Vec2{1, 1}, Vec2{3, 1}, Vec2{3, 3}, Vec2{1, 3}); append(&water_doc.waters, Level_Water{id = "test_water_edit", points = water_points, elevation = .25})}; water_id := water_doc.waters[0].id; water_height := water_doc.waters[0].elevation; assert(level_commit_transaction(&water_doc, Level_Command{kind = .Set_Water, entity_id = water_id, value = water_height + .25}, "raise water") && water_doc.waters[0].elevation == water_height + .25); assert(level_undo(&water_doc) && water_doc.waters[0].elevation == water_height); link_doc := level_clone_document(&level_test); if len(link_doc.vertical_links) == 0 do append(&link_doc.vertical_links, Level_Vertical_Link{id = "test_link_edit", kind = .Stairs, from_story = 0, to_story = 0, start = {1, 1}, finish = {4, 4}, width = 1}); link_id := link_doc.vertical_links[0].id; link_width := link_doc.vertical_links[0].width; assert(level_commit_transaction(&link_doc, Level_Command{kind = .Set_Vertical_Link, entity_id = link_id, value = 1.2}, "widen link") && link_doc.vertical_links[0].width == 1.2); assert(level_undo(&link_doc) && link_doc.vertical_links[0].width == link_width)
	fmt.println("SELF TEST · LEVEL BASIC TRANSACTIONS COMPLETE")
	assert(
		level_command_preview(&level_test, Level_Command{kind = .Create_Room, a = {9, 9}, b = {11, 11}, material = "wood"}).state ==
		.Blocked,
	); unsupported_room := Level_Command {
		kind     = .Create_Room,
		a        = {9, 6},
		b        = {11, 8},
		material = "wood",
	}; assert(
		level_command_preview(&level_test, unsupported_room).state == .Blocked,
	); support_preview_doc := level_clone_document(&level_test); support_points := make([dynamic]Vec2, 0, 4); append(&support_points, Vec2{9, 6}, Vec2{11, 6}, Vec2{11, 8}, Vec2{9, 8}); append(&support_preview_doc.foundations, Level_Foundation{id = "test_support", kind = .Slab, points = support_points, depth = .25}); assert(level_command_preview(&support_preview_doc, unsupported_room).state == .Valid)
	assert(
		len(level_test.foundations) == 5 &&
		level_terrain_reserved_by_foundation(&level_test, {10, 12}) &&
		!level_terrain_reserved_by_foundation(&level_test, {23, 23}),
	); foundation_doc := level_clone_document(&level_test); foundation_command := Level_Command {
		kind        = .Create_Foundation,
		entity_id   = "test_basement",
		value       = 0,
		c           = {f32(Level_Foundation_Kind.Basement), 2.5},
		point_count = 4,
	}; foundation_command.points[0] = {
		9,
		6,
	}; foundation_command.points[1] = {11, 6}; foundation_command.points[2] = {11, 8}; foundation_command.points[3] = {9, 8}; foundation_count, story_count := len(foundation_doc.foundations), len(foundation_doc.stories); assert(level_commit_transaction(&foundation_doc, foundation_command, "create basement") && len(foundation_doc.foundations) == foundation_count + 1 && len(foundation_doc.stories) == story_count + 1); basement_story := foundation_doc.foundations[len(foundation_doc.foundations) - 1].story; assert(basement_story >= 0 && foundation_doc.stories[basement_story].base_elevation == -2.5 && level_story_below(&foundation_doc, 0) == basement_story && level_story_above(&foundation_doc, basement_story) == 0 && level_story_label(&foundation_doc, basement_story) == "B1" && strings.contains(level_serialize(&foundation_doc), "story = 1")); basement_path := "/private/tmp/chicago-basement-roundtrip.toml"; assert(level_save(basement_path, &foundation_doc).ok); basement_roundtrip: Level_Document; assert(level_load(basement_path, &basement_roundtrip).ok && len(basement_roundtrip.stories) == story_count + 1 && basement_roundtrip.foundations[len(basement_roundtrip.foundations) - 1].story == basement_story); foundation_doc.active_story = basement_story; basement_room := Level_Command {
		kind     = .Create_Room,
		a        = {9.25, 6.25},
		b        = {10.75, 7.75},
		material = "study",
	}; assert(
		level_preview_transaction(&foundation_doc, basement_room).state == .Valid,
	); outside_basement := Level_Command {
		kind     = .Create_Room,
		a        = {12, 6},
		b        = {14, 8},
		material = "study",
	}; assert(
		level_preview_transaction(&foundation_doc, outside_basement).state == .Blocked,
	); assert(level_undo(&foundation_doc) && len(foundation_doc.foundations) == foundation_count && len(foundation_doc.stories) == story_count); assert(level_preview_transaction(&level_test, Level_Command{kind = .Delete_Foundation, entity_id = "foundation_dining"}).state == .Blocked); rebuild_generated_stories(&level_test); assert(generated_foundation_count == 5)
	foundation_advance_doc := level_clone_document(
		&level_test,
	); foundation_advance_count := len(foundation_advance_doc.foundations); assert(level_commit_transaction(&foundation_advance_doc, foundation_command, "advance basement") && len(foundation_advance_doc.foundations) == foundation_advance_count + 1); foundation_advance_game := Game {
		build_tool = .Foundation,
	}; assert(
		editor_advance_from_foundation(
			&foundation_advance_game,
			&foundation_advance_doc,
			len(foundation_advance_doc.foundations) - 1,
		) &&
		foundation_advance_game.build_tool == .Room &&
		editor_state.room_mode == .Rectangle &&
		foundation_advance_doc.active_story ==
			foundation_advance_doc.foundations[len(foundation_advance_doc.foundations) - 1].story,
	)
	advance_basement_id :=
		foundation_advance_doc.foundations[len(foundation_advance_doc.foundations) - 1].id; assert(editor_state.selection_count == 1 && editor_state.selection[0].kind == .Foundation && editor_create_room_from_foundation(&foundation_advance_game, &foundation_advance_doc, advance_basement_id)); advance_room := foundation_advance_doc.rooms[len(foundation_advance_doc.rooms) - 1]; assert(advance_room.story == level_basement_story(&foundation_advance_doc) && advance_room.platform_height == 0 && foundation_advance_game.build_tool == .Select)
	polygon_foundation_doc := level_clone_document(
		&level_test,
	); clear(&polygon_foundation_doc.foundations); clear(&polygon_foundation_doc.rooms); polygon_foundation := Level_Command {
		kind        = .Create_Foundation,
		entity_id   = "l_foundation",
		c           = {f32(Level_Foundation_Kind.Slab), .25},
		point_count = 6,
	}; polygon_foundation.points[0] = {
		9,
		5,
	}; polygon_foundation.points[1] = {15, 5}; polygon_foundation.points[2] = {15, 7}; polygon_foundation.points[3] = {11, 7}; polygon_foundation.points[4] = {11, 11}; polygon_foundation.points[5] = {9, 11}; assert(level_preview_transaction(&polygon_foundation_doc, polygon_foundation).state == .Valid && level_commit_transaction(&polygon_foundation_doc, polygon_foundation, "create L foundation")); foundation_corner, picked_corner := level_pick_control_point(&polygon_foundation_doc, {15, 5}, {.Foundation, "l_foundation", -1}); assert(picked_corner && editor_control_point_index(foundation_corner) == 1); old_corner := polygon_foundation_doc.foundations[0].points[1]; corner_move, corner_ok := level_selection_move_command(&polygon_foundation_doc, foundation_corner, {.5, 0}); assert(corner_ok && corner_move.kind == .Move_Foundation_Point && level_preview_transaction(&polygon_foundation_doc, corner_move).state == .Valid && level_commit_transaction(&polygon_foundation_doc, corner_move, "reshape foundation") && polygon_foundation_doc.foundations[0].points[1] != old_corner); assert(level_undo(&polygon_foundation_doc) && polygon_foundation_doc.foundations[0].points[1] == old_corner); inside_l := Level_Command {
		kind        = .Create_Room_Polygon,
		material    = "study",
		point_count = 4,
	}; inside_l.points[0] = {
		9.25,
		7.25,
	}; inside_l.points[1] = {10.75, 7.25}; inside_l.points[2] = {10.75, 10.75}; inside_l.points[3] = {9.25, 10.75}; assert(level_preview_transaction(&polygon_foundation_doc, inside_l).state == .Valid); crosses_notch := Level_Command {
		kind        = .Create_Room_Polygon,
		material    = "study",
		point_count = 3,
	}; crosses_notch.points[0] = {
		9.5,
		10,
	}; crosses_notch.points[1] = {14.5, 6}; crosses_notch.points[2] = {9.5, 6}; assert(level_preview_transaction(&polygon_foundation_doc, crosses_notch).state == .Blocked); l_mesh := procedural_foundation_mesh(&polygon_foundation_doc, polygon_foundation_doc.foundations[0]); assert(l_mesh.ready && len(l_mesh.indices) > 0)
	shell_game := Game {
		build_tool    = .Room,
		build_surface = .Study,
	}; assert(
		editor_create_room_from_foundation(&shell_game, &polygon_foundation_doc, "l_foundation") &&
		len(polygon_foundation_doc.rooms) == 1 &&
		len(polygon_foundation_doc.rooms[0].points) ==
			len(polygon_foundation_doc.foundations[0].points) &&
		polygon_foundation_doc.rooms[0].points[3] ==
			polygon_foundation_doc.foundations[0].points[3] &&
		polygon_foundation_doc.rooms[0].floor_material == "core:study" &&
		shell_game.build_tool == .Select,
	); assert(!editor_create_room_from_foundation(&shell_game, &polygon_foundation_doc, "l_foundation"))
	l_split, l_is_split := level_wall_command(
		&polygon_foundation_doc,
		{9, 8},
		{11, 8},
	); l_area := math.abs(level_polygon_area(polygon_foundation_doc.rooms[0].points[:])); l_path_count := len(polygon_foundation_doc.paths); assert(l_is_split && l_split.kind == .Split_Room && level_preview_transaction(&polygon_foundation_doc, l_split).state == .Valid && level_commit_transaction(&polygon_foundation_doc, l_split, "split L room") && len(polygon_foundation_doc.rooms) == 2 && len(polygon_foundation_doc.paths) == l_path_count + 1 && polygon_foundation_doc.paths[len(polygon_foundation_doc.paths) - 1].kind == .Wall); assert(math.abs(math.abs(level_polygon_area(polygon_foundation_doc.rooms[0].points[:])) + math.abs(level_polygon_area(polygon_foundation_doc.rooms[1].points[:])) - l_area) < .001); assert(level_undo(&polygon_foundation_doc) && len(polygon_foundation_doc.rooms) == 1 && len(polygon_foundation_doc.rooms[0].points) == 6 && len(polygon_foundation_doc.paths) == l_path_count && level_redo(&polygon_foundation_doc) && len(polygon_foundation_doc.rooms) == 2 && len(polygon_foundation_doc.paths) == l_path_count + 1)
	divider_id :=
		polygon_foundation_doc.paths[len(polygon_foundation_doc.paths) - 1].id; opening_before_merge := len(polygon_foundation_doc.openings); append(&polygon_foundation_doc.openings, Level_Opening{id = "split_door", host_path = divider_id, kind = .Door, segment = 0, position = .5, width = 1, height = 2}); secondary_room_id := polygon_foundation_doc.rooms[1].id; append(&polygon_foundation_doc.roofs, Level_Roof{id = "secondary_split_roof", room_id = secondary_room_id, story = 0, style = .Flat, pitch = 5}); roof_before_merge := len(polygon_foundation_doc.roofs); merge_l := level_merge_room_command(polygon_foundation_doc.rooms[0].id, secondary_room_id); assert(level_preview_transaction(&polygon_foundation_doc, merge_l).state == .Valid && level_commit_transaction(&polygon_foundation_doc, merge_l, "merge L rooms") && len(polygon_foundation_doc.rooms) == 1 && math.abs(math.abs(level_polygon_area(polygon_foundation_doc.rooms[0].points[:])) - l_area) < .001 && len(polygon_foundation_doc.paths) == l_path_count && len(polygon_foundation_doc.openings) == opening_before_merge && len(polygon_foundation_doc.roofs) == roof_before_merge - 1); assert(level_undo(&polygon_foundation_doc) && len(polygon_foundation_doc.rooms) == 2 && len(polygon_foundation_doc.paths) == l_path_count + 1 && len(polygon_foundation_doc.openings) == opening_before_merge + 1 && len(polygon_foundation_doc.roofs) == roof_before_merge && level_redo(&polygon_foundation_doc) && len(polygon_foundation_doc.rooms) == 1)
	raised_shell_doc := level_clone_document(
		&level_test,
	); clear(&raised_shell_doc.foundations); clear(&raised_shell_doc.rooms); raised_foundation := Level_Command {
		kind        = .Create_Foundation,
		entity_id   = "raised_shell",
		value       = .75,
		c           = {f32(Level_Foundation_Kind.Raised), .25},
		point_count = 4,
	}; raised_foundation.points[0] = {
		2,
		2,
	}; raised_foundation.points[1] = {6, 2}; raised_foundation.points[2] = {6, 5}; raised_foundation.points[3] = {2, 5}; assert(level_commit_transaction(&raised_shell_doc, raised_foundation, "raised shell foundation")); assert(level_commit_transaction(&raised_shell_doc, Level_Command{kind = .Set_Foundation, entity_id = "raised_shell", value = 1, c = {f32(Level_Foundation_Kind.Raised), .25}}, "raise foundation") && raised_shell_doc.foundations[0].elevation == 1); assert(level_undo(&raised_shell_doc) && raised_shell_doc.foundations[0].elevation == .75); raised_game := Game {
		build_tool    = .Room,
		build_surface = .Dining,
	}; assert(
		editor_create_room_from_foundation(&raised_game, &raised_shell_doc, "raised_shell") &&
		raised_shell_doc.rooms[0].platform_height == .75,
	); rectangle_split, is_rectangle_split := level_wall_command(&raised_shell_doc, {4, 2}, {4, 5}); assert(is_rectangle_split && level_commit_transaction(&raised_shell_doc, rectangle_split, "split rectangle") && len(raised_shell_doc.rooms) == 2 && raised_shell_doc.rooms[0].platform_height == .75 && raised_shell_doc.rooms[1].platform_height == .75); freestanding, is_split_wall := level_wall_command(&raised_shell_doc, {8, 2}, {8, 5}); assert(!is_split_wall && freestanding.kind == .Add_Path)
	raised_shell_doc.rooms[1].platform_height = 1; assert(level_preview_transaction(&raised_shell_doc, level_merge_room_command(raised_shell_doc.rooms[0].id, raised_shell_doc.rooms[1].id)).state == .Blocked); assert(level_preview_transaction(&level_test, level_merge_room_command("dining_room", "gallery")).state == .Blocked)
	fmt.println("SELF TEST · FOUNDATION EDITING COMPLETE")
	assert(
		editor_build_tool_name(.Select) == "SELECT" &&
		editor_build_tool_name(.Wall_Paint) == "WALL STYLE",
	)
	assert(
		editor_build_tool_idle_hint(.Roof) ==
			"Step 1 · Move over a room · Step 2 · Adjust roof · Apply or click room" &&
		editor_build_tool_idle_hint(.Terrain) ==
			"Drag on the lot to sculpt · Ctrl reverses the brush",
	)
	assert(
		editor_build_tool_idle_hint(.Select) ==
		"Click or drag to select · Shift adds or removes items",
	)
	editor_state.selection[0] = {
		.Marker,
		"hint_marker",
		-1,
	}; editor_state.selection_count = 1; assert(editor_build_tool_idle_hint(.Marker) == "Editing selected marker · click empty space to place a new marker"); editor_state.selection[0] = {.Light, "hint_light", -1}; assert(editor_build_tool_idle_hint(.Light) == "Editing selected light · click empty space to place a new light"); editor_state.selection_count = 0
	assert(
		editor_selection_shortcut_hint(1) ==
			"Drag to move · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete" &&
		editor_selection_shortcut_hint(3) ==
			"Drag selection · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete",
	)
	assert(
		editor_selection_status_hint({.Path, "path", -1}, 1) ==
		"Drag a visible point to reshape · adjust width in inspector",
	)
	assert(
		editor_selection_status_hint({.Water, "pond", -1}, 1) ==
		"Drag a visible point to reshape · adjust surface in inspector",
	)
	assert(
		editor_selection_status_hint({.Opening, "window", 0}, 1) ==
		"Drag to slide · Resize from toolbar · Delete",
	)
	assert(
		editor_selection_status_hint({.Object, "chair", -1}, 1) ==
			editor_selection_shortcut_hint(1) &&
		editor_selection_status_hint({.Path, "path", -1}, 2) == editor_selection_shortcut_hint(2),
	)
	assert(
		editor_escape_target(.Wall) == .Room &&
		editor_escape_target(.Window) == .Room &&
		editor_escape_target(.Light) == .Plant,
	)
	assert(
		editor_escape_target(.Wall_Paint) == .Paint &&
		editor_escape_target(.Roof) == .Select &&
		editor_escape_target(.Select) == .Select,
	)
	editor_show_feedback(
		"DELETED OBJECT  ·  CTRL/CMD Z TO UNDO",
	); assert(editor_state.feedback_frames == 240 && editor_state.feedback == "DELETED OBJECT  ·  CTRL/CMD Z TO UNDO"); editor_state.feedback = ""; editor_state.feedback_frames = 0
	assert(EDITOR_SELECTION_ACTION_SIZE == Vec2{36, 30} && EDITOR_SELECTION_ACTION_PITCH == 40)
	assert(editor_status_hint_x(300) == 397 && editor_status_hint_x(600) == 247)
	assert(
		editor_diagnostic_rect(0) == Rect{820, 132, 354, 42} &&
		editor_diagnostic_rect(8) == Rect{820, 516, 354, 42},
	)
	assert(
		editor_view_menu_panel_rect() == Rect{308, 52, 218, 184} &&
		editor_view_menu_rect(0) == Rect{314, 58, 100, 30} &&
		editor_view_menu_rect(9) == Rect{418, 194, 100, 30},
	)
	assert(
		editor_diagnostic_window_start(15, 0, 9) == 0 &&
		editor_diagnostic_window_start(15, 8, 9) == 4 &&
		editor_diagnostic_window_start(15, 14, 9) == 6,
	)
	assert(
		editor_compact_inspector_step_rect(174, -1) == Rect{946, 174, 38, 30} &&
		editor_compact_inspector_step_rect(174, 1) == Rect{1142, 174, 38, 30},
	)
	assert(
		editor_compact_inspector_step_rect(198, -1) == Rect{946, 198, 38, 30} &&
		editor_compact_inspector_step_rect(198, 1) == Rect{1142, 198, 38, 30},
	)
	assert(
		editor_room_material_rect(false) == Rect{946, 202, 112, 24} &&
		editor_room_material_rect(true) == Rect{1066, 202, 112, 24},
	)
	assert(
		editor_room_inspector_rect() == Rect{938, 124, 250, 210} &&
		editor_room_roof_rect() == Rect{946, 230, 232, 24},
	)
	assert(
		editor_room_tint_rect(false, 0) == Rect{1018, 270, 20, 18} &&
		editor_room_tint_rect(true, 5) == Rect{1143, 294, 20, 18},
	)
	assert(
		editor_object_color_rect(0, 0) == Rect{1018, 326, 20, 18} &&
		editor_object_color_rect(1, 5) == Rect{1143, 350, 20, 18},
	)
	assert(editor_snap_rect() == Rect{1034, 648, 150, 32})
	assert(
		len(BUILD_TOOL_GRID) == 16 &&
		len(BUILD_TOOL_ICONS) == len(BUILD_TOOL_GRID) &&
		BUILD_TOOL_GRID[0] == .Select &&
		BUILD_TOOL_GRID[1] == .Room &&
		BUILD_TOOL_GRID[2] == .Foundation,
	); assert(BUILD_TOOL_ICONS[7] == [2]int{7, 0} && BUILD_TOOL_ICONS[8] == [2]int{7, 4} && BUILD_TOOL_ICONS[10] == [2]int{2, 4} && BUILD_TOOL_ICONS[11] == [2]int{7, 1} && BUILD_TOOL_ICONS[12] == [2]int{4, 5} && BUILD_TOOL_ICONS[14] == [2]int{7, 2}); assert(len(BUILD_MODE_GRID) == 11 && build_mode_for_tool(.Window) == .Room && build_mode_for_tool(.Wall_Paint) == .Paint && build_mode_for_tool(.Light) == .Plant); assert(editor_tool_rail_rect() == Rect{8, 76, 66, 566} && build_tool_grid_rect(0) == Rect{19, 87, 44, 44} && build_tool_grid_rect(5) == Rect{19, 337, 44, 44}); assert(editor_paint_target_rect(0) == Rect{78, 144, 42, 42} && editor_paint_target_rect(2) == Rect{174, 144, 42, 42}); assert(editor_paint_eyedropper_rect() == Rect{238, 144, 42, 42}); assert(editor_foundation_kind_rect(2) == Rect{174, 140, 42, 42} && editor_foundation_mode_rect(1) == Rect{380, 144, 38, 38}); assert(editor_terrain_mode_rect(4) == Rect{254, 140, 38, 38} && editor_marker_kind_rect(7) == Rect{372, 140, 38, 38}); assert(editor_catalog_search_rect() == Rect{86, 238, 226, 30} && editor_catalog_search_clear_rect() == Rect{316, 238, 30, 30}); assert(editor_catalog_card_rect(0) == Rect{86, 276, 80, 70} && editor_catalog_card_rect(8) == Rect{262, 436, 80, 70}); assert(editor_catalog_empty_action_rect() == Rect{132, 316, 168, 30}); assert(editor_selection_inspector_rect() == Rect{938, 124, 250, 128}); assert(editor_selection_uses_compact_inspector(.Room) && editor_selection_uses_compact_inspector(.Object) && editor_selection_uses_compact_inspector(.Foundation) && !editor_selection_uses_compact_inspector(.Marker)); assert(editor_selection_toolbar_position({0, 0}) == Vec2{90, 94} && editor_selection_toolbar_position({1200, 720}) == Vec2{944, 614}); assert(editor_placement_rotated(0, -1) == 345 && editor_placement_rotated(345, 1) == 0 && editor_placement_rotated(30, 2) == 60); assert(editor_wheel_steps(0) == 0 && editor_wheel_steps(.2) == 1 && editor_wheel_steps(-.2) == -1 && editor_wheel_steps(3.2) == 3 && editor_wheel_steps(20) == 6); assert(catalog_entry_selectable(Catalog_Entry{valid = true}) && !catalog_entry_selectable(Catalog_Entry{})); assert(UI_Art.Level_Builder_Atlas == UI_Art(len(UI_ART_PATHS) - 1))
	assert(
		editor_selection_uses_compact_inspector(.Edge) &&
		editor_selection_uses_compact_inspector(.Vertex) &&
		editor_selection_uses_compact_inspector(.Opening),
	)
	assert(
		editor_top_close_rect() == Rect{14, 14, 44, 34} &&
		editor_top_save_rect() == Rect{68, 14, 82, 34} &&
		editor_top_undo_rect() == Rect{160, 14, 68, 34} &&
		editor_top_redo_rect() == Rect{236, 14, 68, 34} &&
		editor_top_view_rect() == Rect{314, 14, 108, 34} &&
		editor_top_validate_rect() == Rect{432, 14, 90, 34},
	); assert(editor_top_story_down_rect() == Rect{780, 11, 40, 40} && editor_top_story_up_rect() == Rect{930, 11, 40, 40} && editor_top_recovery_rect() == Rect{980, 14, 102, 34} && editor_top_play_rect() == Rect{1090, 14, 92, 34})
	assert(
		editor_roof_gutters_rect() == Rect{406, 144, 82, 30} &&
		editor_submenu_block_rect() == Rect{74, 128, 426, 90},
	)
	assert(
		editor_opening_parameter_rect(0) == Rect{78, 188, 38, 26} &&
		editor_opening_parameter_rect(3) == Rect{326, 188, 38, 26},
	)
	assert(
		editor_foundation_measure_rect(0) == Rect{238, 144, 38, 30} &&
		editor_foundation_measure_rect(1) == Rect{284, 144, 38, 30},
	); assert(editor_terrain_parameter_rect(0) == Rect{78, 184, 38, 28} && editor_terrain_parameter_rect(3) == Rect{326, 184, 38, 28}); assert(editor_marker_parameter_rect(0) == Rect{78, 202, 38, 26} && editor_marker_parameter_rect(3) == Rect{208, 202, 38, 26}); assert(editor_light_parameter_rect(0) == Rect{168, 206, 38, 30} && editor_light_parameter_rect(3) == Rect{306, 206, 38, 30}); assert(editor_roof_parameter_rect(0) == Rect{168, 144, 38, 30} && editor_roof_parameter_rect(4) == Rect{352, 144, 46, 30}); assert(editor_link_width_rect(0) == Rect{178, 144, 38, 30} && editor_link_width_rect(1) == Rect{224, 144, 38, 30}); assert(editor_water_height_rect(0) == Rect{78, 144, 54, 30} && editor_water_height_rect(1) == Rect{140, 144, 54, 30})
	assert(
		editor_light_panel_rect() == Rect{74, 194, 328, 78} &&
		editor_roof_panel_rect() == Rect{74, 132, 418, 78},
	); assert(!editor_viewport_contains({200, 250}, .Light) && editor_viewport_contains({500, 250}, .Light))
	assert(
		editor_light_duplicate_rect() == Rect{1098, 136, 34, 28} &&
		editor_light_delete_rect() == Rect{1140, 136, 34, 28},
	)
	assert(
		editor_marker_duplicate_rect() == Rect{1098, 136, 34, 28} &&
		editor_marker_delete_rect() == Rect{1140, 136, 34, 28},
	)
	assert(
		editor_marker_position_rect(.Marker_X) == Rect{920, 286, 114, 26} &&
		editor_marker_position_rect(.Marker_Y) == Rect{1040, 286, 114, 26},
	)
	assert(
		level_marker_uses_binding(.Interaction) &&
		level_marker_uses_binding(.Trigger) &&
		level_marker_uses_binding(.Transition) &&
		!level_marker_uses_binding(.Camera) &&
		!level_marker_uses_binding(.Staging),
	)
	assert(
		editor_light_current_color_rect() == Rect{958, 214, 24, 22} &&
		editor_light_color_rect(.Point, 0) == Rect{990, 214, 24, 22} &&
		editor_light_color_rect(.Spot, 5) == Rect{1140, 214, 24, 22},
	)
	assert(
		editor_inspector_step_rect(318, -1) == Rect{920, 318, 38, 30} &&
		editor_inspector_step_rect(318, 1) == Rect{1138, 318, 38, 30},
	)
	assert(
		editor_inspector_step_rect(178, -1) == Rect{920, 178, 38, 30} &&
		editor_inspector_clear_rect(248) == Rect{1096, 248, 38, 30},
	)
	assert(
		editor_paint_command_kind(.Floor) == .Paint_Floor &&
		editor_paint_command_kind(.Walls) == .Paint_Walls &&
		editor_paint_command_kind(.Room) == .Paint_Room &&
		editor_paint_command_kind(.Floor, true) == .Paint_Room,
	)
	sample_room := Level_Room {
		floor_material = "core:oak",
		wall_material  = "core:plaster",
	}; assert(
		editor_room_sample_material(sample_room, .Floor) == "core:oak" &&
		editor_room_sample_material(sample_room, .Walls) == "core:plaster" &&
		editor_room_sample_material(sample_room, .Room) == "core:oak",
	)
	assert(
		editor_effective_terrain_mode(.Raise, false) == .Raise &&
		editor_effective_terrain_mode(.Raise, true) == .Lower &&
		editor_effective_terrain_mode(.Lower, true) == .Raise &&
		editor_effective_terrain_mode(.Smooth, true) == .Smooth,
	)
	terrain_sample_doc := Level_Document {
		width  = 1,
		height = 1,
	}; terrain_sample_doc.terrain = make(
		[dynamic]f32,
		0,
		4,
	); append(&terrain_sample_doc.terrain, f32(0), f32(1), f32(2), f32(3)); assert(level_terrain_height(&terrain_sample_doc, {.5, .5}) == 1.5 && level_terrain_height(&terrain_sample_doc, {.25, .75}) == 1.75); terrain_chunk := procedural_terrain_chunk_mesh(&terrain_sample_doc, 0, 0, 1, 1); assert(terrain_chunk.ready && len(terrain_chunk.vertices) == 4 && len(terrain_chunk.texcoords) == 4 && len(terrain_chunk.indices) == 6 && terrain_chunk.vertices[3].y == 3 && terrain_chunk.texcoords[3] == Vec2{.125, .125})
	rebuild_generated_ground(
		&level_test,
	); assert(generated_terrain_count == ((level_test.width + TERRAIN_CHUNK_CELLS - 1) / TERRAIN_CHUNK_CELLS) * ((level_test.height + TERRAIN_CHUNK_CELLS - 1) / TERRAIN_CHUNK_CELLS)); terrain_index_count := 0; for i in 0 ..< generated_terrain_count do terrain_index_count += len(generated_terrain_meshes[i].indices); assert(terrain_index_count > 0 && terrain_index_count < level_test.width * level_test.height * 6); pond_terrain_doc := Level_Document {
		width  = 2,
		height = 2,
	}; pond_terrain_doc.terrain = make(
		[dynamic]f32,
		9,
	); pond_terrain_points := make([dynamic]Vec2, 0, 4); append(&pond_terrain_points, Vec2{.25, .25}, Vec2{1.75, .25}, Vec2{1.75, 1.75}, Vec2{.25, 1.75}); append(&pond_terrain_doc.waters, Level_Water{id = "terrain_continuity_pond", points = pond_terrain_points, elevation = .05}); pond_terrain_mesh := procedural_terrain_chunk_mesh(&pond_terrain_doc, 0, 0, 2, 2); assert(pond_terrain_mesh.ready && len(pond_terrain_mesh.indices) == 24)
	clear(&level_test.waters)
	fmt.println("SELF TEST · TERRAIN MESH COMPLETE")
	assert(
		level_preview_transaction(&level_test, Level_Command{kind = .Sculpt_Terrain, a = {10, 10}, b = {11, 11}, c = {.5, 0}, value = 1, brush = .Raise}).state ==
		.Blocked,
	); assert(level_preview_transaction(&level_test, Level_Command{kind = .Sculpt_Terrain, a = {2, 4}, b = {6, 7}, c = {.5, 0}, value = .5, brush = .Raise}).state == .Valid)
	editor_support_points := make(
		[dynamic]Vec2,
		0,
		4,
	); append(&editor_support_points, Vec2{0, 0}, Vec2{f32(level_test.width), 0}, Vec2{f32(level_test.width), f32(level_test.height)}, Vec2{0, f32(level_test.height)}); append(&level_test.foundations, Level_Foundation{id = "editor_test_support", kind = .Slab, points = editor_support_points, depth = .25})
	editor_state.snap_mode = .Construction; editor_state.snap_suspended = false; assert(level_snap_point(&level_test, {1.26, 2.74}) == Vec2{1.5, 2.5} && level_snap_delta(&level_test, {.26, .74}) == Vec2{.5, .5}); editor_state.snap_mode = .Fine; assert(level_snap_point(&level_test, {1.26, 2.74}) == Vec2{1.25, 2.75}); editor_state.snap_mode = .Off; assert(level_snap_point(&level_test, {1.26, 2.74}) == Vec2{1.26, 2.74}); editor_state.snap_mode = .Construction; editor_state.snap_suspended = true; assert(level_snap_point(&level_test, {1.26, 2.74}) == Vec2{1.26, 2.74}); editor_state.snap_suspended = false; editor_state.snap_mode = .Fine
	fmt.println("SELF TEST · TERRAIN AND SNAP COMPLETE")
	// This mutation test owns an isolated marker fixture; authored capture markers
	// from the production level must not participate in its pick assertions.
	clear(&level_test.markers)
	append(
		&level_test.markers,
		Level_Marker {
			id = "test_spawn",
			kind = .Player_Spawn,
			story = 0,
			position = {6, 6},
			radius = .5,
		},
	)
	clear(
		&level_test.objects,
	); clear(&level_test.roofs); append(&level_test.stories, Level_Story{"upper", "Upper", 3, 2.5}); append(&level_test.objects, Level_Object{id = "test_object", catalog_id = "core:plant", story = 0, position = {2, 2}, elevation = .25, rotation = 45, tint = {1, 2, 3, 255}}); append(&level_test.roofs, Level_Roof{id = "test_roof", room_id = "dining_room", story = 0, style = .Hip, pitch = 32, overhang = .4, ridge_angle = 90}); water_points := make([dynamic]Vec2, 0, 4); append(&water_points, Vec2{9, 6}, Vec2{10, 6}, Vec2{10, 7}, Vec2{9, 7}); append(&level_test.waters, Level_Water{"test_water", water_points, .25}); append(&level_test.vertical_links, Level_Vertical_Link{id = "test_stairs", kind = .Stairs, from_story = 0, to_story = 1, start = {2, 2}, finish = {2, 5}, width = 1}); append(&level_test.markers, Level_Marker{id = "test_camera", kind = .Camera, story = 0, position = {4, 4}, radius = .5, facing = 90, camera_height = 2}); level_test.terrain[0] = .5; level_test.terrain[1] = .25; level_test_validation := level_validate(&level_test); if !level_test_validation.ok do fmt.println("LEVEL TEST VALIDATION FAILURE · ", level_test_validation.message); assert(level_test_validation.ok); fmt.println("SELF TEST · MUTATED LEVEL VALID COMPLETE"); roundtrip_path := "/private/tmp/chicago-level-roundtrip.toml"; assert(level_save(roundtrip_path, &level_test).ok); roundtrip: Level_Document; assert(level_load(roundtrip_path, &roundtrip).ok); fmt.println("SELF TEST · MUTATED LEVEL LOAD COMPLETE"); assert(len(roundtrip.objects) == 1 && roundtrip.objects[0].rotation == 45 && roundtrip.objects[0].tint == [4]u8{1, 2, 3, 255}); assert(len(roundtrip.roofs) == 1 && roundtrip.roofs[0].style == .Hip && len(roundtrip.waters) == 1 && len(roundtrip.vertical_links) == 1); assert(roundtrip.terrain[0] == .5 && roundtrip.terrain[1] == .25 && roundtrip.markers[len(roundtrip.markers) - 1].camera_height == 2); level_history = {}; original_point := roundtrip.rooms[0].points[1]; assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Move_Room, entity_id = roundtrip.rooms[0].id, a = {.5, .25}}, "move polygon") && roundtrip.rooms[0].points[1] != original_point); assert(level_undo(&roundtrip) && roundtrip.rooms[0].points[1] == original_point && level_redo(&roundtrip) && roundtrip.rooms[0].points[1] != original_point); roundtrip.active_story = 0; picked_marker := level_pick(&roundtrip, {4, 4}); picked_object := level_pick(&roundtrip, {2, 2}); assert(picked_marker.kind == .Marker && picked_marker.entity_id == "test_camera" && picked_object.kind == .Object); object_start := roundtrip.objects[0].position; assert(level_nudge_selection(&roundtrip, picked_object, {.25, 0}) && roundtrip.objects[0].position.x == object_start.x + .25); assert(level_undo(&roundtrip) && roundtrip.objects[0].position == object_start); object_count := len(roundtrip.objects); assert(level_delete_selection(&roundtrip, picked_object) && len(roundtrip.objects) == object_count - 1); assert(level_undo(&roundtrip) && len(roundtrip.objects) == object_count && roundtrip.objects[0].id == "test_object"); assert(level_snap_delta(&roundtrip, {.37, -.38}) == Vec2{.25, -.5}); room_selection := Editor_Selection{.Room, roundtrip.rooms[0].id, -1}; drag_command, drag_ok := level_selection_move_command(&roundtrip, room_selection, {.25, .5}); assert(drag_ok && drag_command.kind == .Move_Room && level_preview_transaction(&roundtrip, drag_command).state == .Valid); blocked_drag, _ := level_selection_move_command(&roundtrip, room_selection, {-100, 0}); assert(level_preview_transaction(&roundtrip, blocked_drag).state == .Blocked); vertex_pick, vertex_ok := level_pick_room_handle(&roundtrip, roundtrip.rooms[0].points[0], room_selection); assert(vertex_ok && vertex_pick.kind == .Vertex && vertex_pick.sub_index == 0); edge_mid := Vec2{(roundtrip.rooms[0].points[0].x + roundtrip.rooms[0].points[1].x) * .5, (roundtrip.rooms[0].points[0].y + roundtrip.rooms[0].points[1].y) * .5}; edge_pick, edge_ok := level_pick_room_handle(&roundtrip, edge_mid, room_selection); assert(edge_ok && edge_pick.kind == .Edge && edge_pick.sub_index == 0); vertex_before := roundtrip.rooms[0].points[0]; vertex_command, vertex_command_ok := level_selection_move_command(&roundtrip, vertex_pick, {.25, .25}); assert(vertex_command_ok && level_commit_transaction(&roundtrip, vertex_command, "vertex reshape") && roundtrip.rooms[0].points[0] != vertex_before); assert(level_undo(&roundtrip) && roundtrip.rooms[0].points[0] == vertex_before); edge_before_a, edge_before_b := roundtrip.rooms[0].points[0], roundtrip.rooms[0].points[1]; edge_command, edge_command_ok := level_selection_move_command(&roundtrip, edge_pick, {0, .25}); assert(edge_command_ok && level_commit_transaction(&roundtrip, edge_command, "edge reshape") && roundtrip.rooms[0].points[0].y == edge_before_a.y + .25 && roundtrip.rooms[0].points[1].y == edge_before_b.y + .25); assert(level_undo(&roundtrip) && roundtrip.rooms[0].points[0] == edge_before_a && roundtrip.rooms[0].points[1] == edge_before_b); collapsed_vertex := Level_Command {
		kind      = .Move_Room_Vertex,
		entity_id = room_selection.entity_id,
		a         = roundtrip.rooms[0].points[2],
		value     = 0,
	}; assert(
		level_preview_transaction(&roundtrip, collapsed_vertex).state == .Blocked,
	); transform_index := level_room_index(&roundtrip, "test_room"); assert(transform_index >= 0); roundtrip.rooms[transform_index].points[1].y += .5; roundtrip.rooms[transform_index].platform_height = .75; roundtrip.rooms[transform_index].ceiling_style = "coffered"; transform_original := roundtrip.rooms[transform_index].points[0]; rotate_command := Level_Command {
		kind      = .Rotate_Room,
		entity_id = "test_room",
		value     = 15,
	}; assert(
		level_preview_transaction(&roundtrip, rotate_command).state == .Valid &&
		level_commit_transaction(&roundtrip, rotate_command, "rotate arbitrary room") &&
		roundtrip.rooms[transform_index].points[0] != transform_original,
	); assert(level_undo(&roundtrip) && roundtrip.rooms[transform_index].points[0] == transform_original); copy_count := len(roundtrip.rooms); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Duplicate_Room, entity_id = "test_room", a = {.5, .5}, material = "test_room_copy"}, "copy arbitrary room") && len(roundtrip.rooms) == copy_count + 1); copy_index := level_room_index(&roundtrip, "test_room_copy"); assert(copy_index >= 0 && roundtrip.rooms[copy_index].platform_height == .75 && roundtrip.rooms[copy_index].ceiling_style == "coffered" && len(roundtrip.rooms[copy_index].points) == len(roundtrip.rooms[transform_index].points) && roundtrip.rooms[copy_index].points[1] == Vec2{roundtrip.rooms[transform_index].points[1].x + .5, roundtrip.rooms[transform_index].points[1].y + .5}); assert(level_undo(&roundtrip) && level_room_index(&roundtrip, "test_room_copy") == -1 && level_redo(&roundtrip) && level_room_index(&roundtrip, "test_room_copy") >= 0); fmt.println("SELF TEST · LEVEL TRANSFORMS COMPLETE"); platform_before := roundtrip.rooms[transform_index].platform_height; fmt.println("SELF TEST · PLATFORM COMMIT START"); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Set_Platform, entity_id = "test_room", value = platform_before + .25}, "raise platform") && roundtrip.rooms[transform_index].platform_height == platform_before + .25); fmt.println("SELF TEST · PLATFORM COMMIT COMPLETE"); assert(level_undo(&roundtrip) && roundtrip.rooms[transform_index].platform_height == platform_before)
	fmt.println("SELF TEST · PLATFORM COMPLETE")
	polygon_command := Level_Command {
		kind        = .Create_Room_Polygon,
		entity_id   = "test_polygon_room",
		material    = "wood",
		point_count = 5,
	}; polygon_command.points[0] = {
		18,
		10,
	}; polygon_command.points[1] = {22, 10}; polygon_command.points[2] = {22, 13}; polygon_command.points[3] = {20, 12}; polygon_command.points[4] = {18, 13}; assert(level_preview_transaction(&roundtrip, polygon_command).state == .Valid && level_commit_transaction(&roundtrip, polygon_command, "create polygon room")); polygon_index := level_room_index(&roundtrip, "test_polygon_room"); assert(polygon_index >= 0 && len(roundtrip.rooms[polygon_index].points) == 5); before_insert := len(roundtrip.rooms[polygon_index].points); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Insert_Room_Vertex, entity_id = "test_polygon_room", a = {20, 10}, value = 0}, "insert corner") && len(roundtrip.rooms[polygon_index].points) == before_insert + 1 && roundtrip.rooms[polygon_index].points[1] == Vec2{20, 10}); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Remove_Room_Vertex, entity_id = "test_polygon_room", value = 1}, "remove corner") && len(roundtrip.rooms[polygon_index].points) == before_insert); crossed := polygon_command; crossed.entity_id = "bad_polygon"; crossed.points[0] = {18, 10}; crossed.points[1] = {22, 13}; crossed.points[2] = {18, 13}; crossed.points[3] = {22, 10}; crossed.point_count = 4; assert(level_preview_transaction(&roundtrip, crossed).state == .Blocked)
	fmt.println("SELF TEST · POLYGON ROOM COMPLETE")
	catalog_test: Editor_Catalog; assert(catalog_load("assets/catalog/editor_catalog.toml", &catalog_test).ok && len(catalog_test.entries) > 0); editor_catalog = catalog_test; dining_material, dining_material_ok := catalog_material_entry("dining"); assert(dining_material_ok && dining_material.floor_repeat_m == 5 && dining_material.wall_repeat_m == 2 && material_floor_uv_scale(dining_material) == .2 && material_wall_uv_scale(dining_material) == .5); valid_objects := 0; floor_lamp_manifest := false; foliage_objects := 0; rug_objects := 0; for entry in catalog_test.entries do if entry.kind == .Object {assert(entry.model != "" && entry.mesh_index == -1 && entry.thumbnail_missing == !os.exists(entry.thumbnail)); if entry.id == "core:floor_lamp" do floor_lamp_manifest = strings.contains(entry.model, "lampSquareFloor.glb"); if entry.category == "foliage" do foliage_objects += 1; if entry.category == "rugs" do rug_objects += 1; if entry.valid do valid_objects += 1}; assert(valid_objects > 0 && foliage_objects > 0 && rug_objects > 0 && floor_lamp_manifest); catalog_state := Editor_State {
		catalog_category = "objects",
	}; catalog_state.search_buffer[0] = 's'; catalog_state.search_buffer[1] = 'o'; catalog_state.search_buffer[2] = 'f'; catalog_state.search_buffer[3] = 'a'; catalog_state.search_count = 4; matches := 0; for entry in catalog_test.entries do if catalog_entry_matches(entry, &catalog_state) do matches += 1; assert(matches >= 1); catalog_state.catalog_page = 1; catalog_clear_search(&catalog_state); assert(catalog_search_text(&catalog_state) == "" && catalog_state.catalog_page == 0 && catalog_state.search_active); assert(catalog_append_search_char(&catalog_state, 'F') && catalog_append_search_char(&catalog_state, '2') && catalog_append_search_char(&catalog_state, '_') && !catalog_append_search_char(&catalog_state, ' ')); assert(catalog_search_text(&catalog_state) == "f2_" && catalog_state.catalog_page == 0); catalog_clear_search(&catalog_state); catalog_record_recent(&catalog_state, "chair"); catalog_record_recent(&catalog_state, "sofa"); catalog_record_recent(&catalog_state, "chair"); assert(catalog_state.catalog_recent_count == 2 && catalog_state.catalog_recent[0] == "core:chair" && catalog_state.catalog_recent[1] == "core:sofa"); object_source := level_object_index(&roundtrip, "test_object"); assert(object_source >= 0); object_copy_count := len(roundtrip.objects); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Duplicate_Object, entity_id = "test_object", a = {.5, .5}, material = "test_object_copy"}, "duplicate object") && len(roundtrip.objects) == object_copy_count + 1); object_copy_index := level_object_index(&roundtrip, "test_object_copy"); assert(object_copy_index >= 0 && roundtrip.objects[object_copy_index].catalog_id == "core:plant" && roundtrip.objects[object_copy_index].rotation == 45 && roundtrip.objects[object_copy_index].elevation == .25 && roundtrip.objects[object_copy_index].tint == [4]u8{1, 2, 3, 255}); assert(level_undo(&roundtrip) && level_object_index(&roundtrip, "test_object_copy") == -1); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Set_Object_Elevation, entity_id = "test_object", value = .75}, "raise object") && roundtrip.objects[object_source].elevation == .75); assert(level_undo(&roundtrip) && roundtrip.objects[object_source].elevation == .25); assert(level_commit_transaction(&roundtrip, Level_Command{kind = .Move_Object, entity_id = "test_object", a = roundtrip.objects[object_source].position, value = 90}, "rotate object") && roundtrip.objects[object_source].rotation == 90); level_project_runtime(&roundtrip); assert(roundtrip.objects[object_source].rotation == 90 && roundtrip.objects[object_source].catalog_id == "core:plant" && strings.contains(level_serialize(&roundtrip), "catalog_id = \"core:plant\"")); assert(level_undo(&roundtrip) && roundtrip.objects[object_source].rotation == 45)
	enriched_catalog_objects := 0; for entry in catalog_test.entries do if entry.kind == .Object {if entry.front_direction != "" && entry.dimensions.x > 0 && entry.dimensions.y > 0 && entry.dimensions.z > 0 && len(entry.styles) > 0 && len(entry.affordances) > 0 do enriched_catalog_objects += 1; assert(entry.clearance_front >= 0 && entry.clearance_back >= 0 && entry.clearance_left >= 0 && entry.clearance_right >= 0)}; assert(enriched_catalog_objects > 0); floor_lamp_entry, floor_lamp_found := catalog_object_entry("floor_lamp"); assert(floor_lamp_found && floor_lamp_entry.dimensions.y > 1.7 && floor_lamp_entry.dimensions.y < 1.8)
	rounded_chair, rounded_chair_ok := catalog_object_entry(
		"chair_rounded",
	); bar_stool, bar_stool_ok := catalog_object_entry("bar_stool"); assert(rounded_chair_ok && rounded_chair.dimensions == [3]f32{.52, 1, .52}); assert(bar_stool_ok && bar_stool.dimensions == [3]f32{.42, .82, .42})
	prop_scale_mesh := Glb_Mesh {
		min = {0, 0, 0},
		max = {1, .4, 1},
	}; kenney_prop := Catalog_Entry {
		model = "assets/kenney_furniture-kit/Models/GLTF format/chair.glb",
	}; dimensioned_prop :=
		kenney_prop; dimensioned_prop.dimensions = {1, .9, 1}; assert(math.abs(catalog_object_render_height(&prop_scale_mesh, &kenney_prop) - .8) < .001); assert(math.abs(catalog_object_render_height(&prop_scale_mesh, &dimensioned_prop) - .9) < .001)
	catalog_has_sofa, catalog_has_plant :=
		false,
		false; for entry, i in catalog_test.entries {assert(entry.id != ""); if entry.id == "core:sofa" do catalog_has_sofa = true; if entry.id == "core:plant" do catalog_has_plant = true; for other, j in catalog_test.entries do if j > i do assert(entry.id != other.id)}; assert(catalog_has_sofa && catalog_has_plant)
	page_state := Editor_State {
		catalog_category = "objects",
		catalog_page     = 99,
	}; assert(
		catalog_match_count(&page_state) > 0 && catalog_page_count(&page_state) > 0,
	); catalog_clamp_page(&page_state); assert(page_state.catalog_page == catalog_page_count(&page_state) - 1); page_state.catalog_category = "recent"; catalog_clamp_page(&page_state); assert(page_state.catalog_page == 0); assert(catalog_toggle_pinned(&page_state, "chair") && catalog_is_pinned(&page_state, "chair")); page_state.catalog_category = "pinned"; assert(catalog_match_count(&page_state) == 1); assert(!catalog_toggle_pinned(&page_state, "chair") && !catalog_is_pinned(&page_state, "chair") && catalog_match_count(&page_state) == 0)
	editor_state.catalog_category = "materials"; editor_state.catalog_page = 0; assert(editor_catalog_visible_count() == 9 && editor_catalog_rows() == 3 && editor_catalog_footer_y() == 514 && editor_catalog_panel_bottom(.Paint) == 552); editor_state.catalog_category = "objects"; assert(editor_catalog_visible_count() == 9 && editor_catalog_rows() == 3 && editor_catalog_footer_y() == 514 && editor_catalog_panel_bottom(.Plant) == 590)
	placement_doc := level_clone_document(
		&roundtrip,
	); clear(&placement_doc.objects); placement_center := level_room_center(&placement_doc.rooms[0]); assert(level_preview_transaction(&placement_doc, Level_Command{kind = .Place_Object, a = placement_center, material = "plant"}).state == .Valid); assert(level_preview_transaction(&placement_doc, Level_Command{kind = .Place_Object, a = {0, 0}, material = "sofa"}).state == .Blocked); append(&placement_doc.objects, Level_Object{id = "occupied", catalog_id = "core:chair", story = placement_doc.active_story, position = placement_center, tint = {255, 255, 255, 255}}); assert(level_preview_transaction(&placement_doc, Level_Command{kind = .Place_Object, a = placement_center, material = "plant"}).state == .Warning); placed_count := len(placement_doc.objects); assert(level_commit_transaction(&placement_doc, Level_Command{kind = .Place_Object, a = {placement_center.x + .75, placement_center.y}, value = 30, material = "sofa"}, "place rotated sofa") && len(placement_doc.objects) == placed_count + 1 && placement_doc.objects[len(placement_doc.objects) - 1].rotation == 30); assert(level_undo(&placement_doc) && len(placement_doc.objects) == placed_count)
	clear(
		&placement_doc.objects,
	); append(&placement_doc.objects, Level_Object{id = "support_table", catalog_id = "core:dining_table", story = placement_doc.active_story, position = placement_center, tint = {255, 255, 255, 255}}); support_id, support_height, support_ok := level_object_support_at(&placement_doc, placement_center, "plant"); assert(support_ok && support_id == "support_table" && support_height > 0); supported_command := Level_Command {
		kind        = .Place_Object,
		entity_id   = "tabletop_plant",
		a           = placement_center,
		c           = {support_height, 0},
		material    = "plant",
		destination = support_id,
	}; assert(
		level_preview_transaction(&placement_doc, supported_command).state == .Valid &&
		level_commit_transaction(&placement_doc, supported_command, "place on furniture"),
	); tabletop_index := level_object_index(&placement_doc, "tabletop_plant"); assert(tabletop_index >= 0 && placement_doc.objects[tabletop_index].support_id == "support_table" && placement_doc.objects[tabletop_index].elevation == support_height); table_start := placement_doc.objects[0].position; assert(level_commit_transaction(&placement_doc, Level_Command{kind = .Move_Object, entity_id = "support_table", a = {table_start.x + .5, table_start.y}, value = 0}, "move supporting furniture") && placement_doc.objects[tabletop_index].position.x == placement_center.x + .5); supported_serialized := level_serialize(&placement_doc); assert(strings.contains(supported_serialized, "support_id = \"support_table\"")); supported_path := "/private/tmp/chicago-supported-object-roundtrip.toml"; assert(level_save(supported_path, &placement_doc).ok); supported_roundtrip: Level_Document; assert(level_load(supported_path, &supported_roundtrip).ok && supported_roundtrip.objects[level_object_index(&supported_roundtrip, "tabletop_plant")].support_id == "support_table")
	paint_doc := level_clone_document(
		&roundtrip,
	); paint_index := 0; old_floor, old_walls := paint_doc.rooms[paint_index].floor_material, paint_doc.rooms[paint_index].wall_material; assert(level_material_surface("study") == .Study && level_material_surface("dining") == .Dining); assert(level_commit_transaction(&paint_doc, Level_Command{kind = .Paint_Floor, entity_id = paint_doc.rooms[paint_index].id, material = "study"}, "paint floor") && paint_doc.rooms[paint_index].floor_material == "core:study" && paint_doc.rooms[paint_index].wall_material == old_walls); assert(level_undo(&paint_doc) && paint_doc.rooms[paint_index].floor_material == old_floor); assert(level_commit_transaction(&paint_doc, Level_Command{kind = .Paint_Walls, entity_id = paint_doc.rooms[paint_index].id, material = "study"}, "paint walls") && paint_doc.rooms[paint_index].floor_material == old_floor && paint_doc.rooms[paint_index].wall_material == "core:study"); level_project_runtime(&paint_doc); projected_study_wall := false; for paint in house_plan.wall_face_paints do if paint.surface == .Study do projected_study_wall = true; assert(projected_study_wall); assert(level_undo(&paint_doc) && paint_doc.rooms[paint_index].wall_material == old_walls); assert(level_commit_transaction(&paint_doc, Level_Command{kind = .Paint_Room, entity_id = paint_doc.rooms[paint_index].id, material = "study"}, "paint room") && paint_doc.rooms[paint_index].floor_material == "core:study" && paint_doc.rooms[paint_index].wall_material == "core:study"); assert(level_undo(&paint_doc) && paint_doc.rooms[paint_index].floor_material == old_floor && paint_doc.rooms[paint_index].wall_material == old_walls)
	floor_tint, wall_tint :=
		[4]u8{207, 177, 142, 255},
		[4]u8 {
			194,
			211,
			218,
			255,
		}; paint_room_id := paint_doc.rooms[paint_index].id; assert(level_commit_transaction(&paint_doc, Level_Command{kind = .Set_Room_Tint, entity_id = paint_room_id, destination = "floor", color = floor_tint}, "tint floor") && paint_doc.rooms[paint_index].floor_tint == floor_tint && level_undo(&paint_doc)); assert(level_commit_transaction(&paint_doc, Level_Command{kind = .Set_Room_Tint, entity_id = paint_room_id, destination = "walls", color = wall_tint}, "tint walls") && paint_doc.rooms[paint_index].wall_tint == wall_tint); tint_path := "/private/tmp/chicago-room-tint-roundtrip.toml"; assert(level_save(tint_path, &paint_doc).ok); tint_roundtrip: Level_Document; assert(level_load(tint_path, &tint_roundtrip).ok && tint_roundtrip.rooms[paint_index].wall_tint == wall_tint)
	fmt.println("SELF TEST · CATALOG AND OBJECTS COMPLETE")
	level_project_runtime(&roundtrip)
	opening_doc := level_clone_document(
		&roundtrip,
	); clear(&opening_doc.openings); host := Editor_Selection{.Path, "shell", 0}; opening_command, opening_command_ok := level_opening_command_at(&opening_doc, host, {14, 8}, .Window); assert(opening_command_ok && math.abs(opening_command.c.x - .1875) < .001 && level_preview_transaction(&opening_doc, opening_command).state == .Valid); opening_count := len(opening_doc.openings); assert(level_commit_transaction(&opening_doc, opening_command, "place hosted window") && len(opening_doc.openings) == opening_count + 1 && math.abs(opening_doc.openings[0].position - .1875) < .001 && opening_doc.openings[0].kind == .Window); overlap_command, overlap_ok := level_opening_command_at(&opening_doc, host, {14.5, 8}, .Door); assert(overlap_ok && level_preview_transaction(&opening_doc, overlap_command).state == .Blocked); opening_doc.openings[0].width = 2.25; opening_doc.openings[0].height = 1.75; opening_selection := Editor_Selection{.Opening, opening_doc.openings[0].id, 0}; assert(level_delete_selection(&opening_doc, opening_selection) && len(opening_doc.openings) == opening_count); assert(level_undo(&opening_doc) && len(opening_doc.openings) == opening_count + 1 && opening_doc.openings[0].position == .1875 && opening_doc.openings[0].width == 2.25 && opening_doc.openings[0].height == 1.75); assert(level_redo(&opening_doc) && len(opening_doc.openings) == opening_count && level_undo(&opening_doc) && opening_doc.openings[0].width == 2.25 && opening_doc.openings[0].height == 1.75); opening_roundtrip_path := "/private/tmp/chicago-opening-roundtrip.toml"; assert(level_save(opening_roundtrip_path, &opening_doc).ok); opening_roundtrip: Level_Document; assert(level_load(opening_roundtrip_path, &opening_roundtrip).ok && len(opening_roundtrip.openings) == 1 && opening_roundtrip.openings[0].kind == .Window && math.abs(opening_roundtrip.openings[0].position - .1875) < .001 && opening_roundtrip.openings[0].width == 2.25 && opening_roundtrip.openings[0].height == 1.75)
	custom_window, custom_window_ok := level_opening_command_at(
		&opening_doc,
		host,
		{14, 8},
		.Window,
		2.5,
		1.8,
	); custom_window.entity_id = "custom_window"; clear(&opening_doc.openings); assert(custom_window_ok && custom_window.b.y == 2.5 && custom_window.c.y == 1.8 && level_preview_transaction(&opening_doc, custom_window).state == .Valid && level_commit_transaction(&opening_doc, custom_window, "place custom window") && opening_doc.openings[0].width == 2.5 && opening_doc.openings[0].height == 1.8); resize_window, resize_window_ok := level_opening_resize_command(&opening_doc, "custom_window", .1, .1); assert(resize_window_ok && resize_window.kind == .Set_Opening && level_preview_transaction(&opening_doc, resize_window).state == .Valid && level_commit_transaction(&opening_doc, resize_window, "resize custom window") && opening_doc.openings[0].width == 2.6 && opening_doc.openings[0].height == 1.9); assert(level_undo(&opening_doc) && opening_doc.openings[0].width == 2.5 && opening_doc.openings[0].height == 1.8 && level_redo(&opening_doc) && opening_doc.openings[0].width == 2.6 && opening_doc.openings[0].height == 1.9); invalid_window := custom_window; invalid_window.entity_id = "invalid_window"; invalid_window.b.y = 8; assert(level_preview_transaction(&opening_doc, invalid_window).state == .Blocked); opening_doc.openings[0].height = 5; assert(!level_validate(&opening_doc).ok)
	opening_doc.openings[0].height = 1.9; window_path := opening_doc.paths[level_path_index(&opening_doc, "shell")]; window_a, window_b := window_path.points[0], window_path.points[1]; window_dx, window_dy := window_b.x - window_a.x, window_b.y - window_a.y; window_length := f32(math.sqrt(f64(window_dx * window_dx + window_dy * window_dy))); window_endpoint := Vec2{window_a.x + window_dx * (opening_doc.openings[0].position + opening_doc.openings[0].width * .45 / window_length), window_a.y + window_dy * (opening_doc.openings[0].position + opening_doc.openings[0].width * .45 / window_length)}; picked_window := level_pick(&opening_doc, window_endpoint); assert(picked_window.kind == .Opening && picked_window.entity_id == "custom_window"); window_position_before := opening_doc.openings[0].position; slide_window, slide_window_ok := level_selection_move_command(&opening_doc, picked_window, {window_dx / window_length * .5, window_dy / window_length * .5}); assert(slide_window_ok && slide_window.kind == .Set_Opening && slide_window.c.x > window_position_before && level_preview_transaction(&opening_doc, slide_window).state == .Valid && level_commit_transaction(&opening_doc, slide_window, "slide custom window") && opening_doc.openings[0].position > window_position_before); assert(level_undo(&opening_doc) && opening_doc.openings[0].position == window_position_before && level_redo(&opening_doc) && opening_doc.openings[0].position > window_position_before); slid_position := opening_doc.openings[0].position; perpendicular_window, perpendicular_window_ok := level_selection_move_command(&opening_doc, picked_window, {-window_dy / window_length * .5, window_dx / window_length * .5}); assert(perpendicular_window_ok && math.abs(perpendicular_window.c.x - slid_position) < .001)
	collision_window_doc := level_clone_document(
		&opening_doc,
	); collision_window_doc.openings[0].height = 1.9; append(&collision_window_doc.openings, Level_Opening{id = "neighbor_window", host_path = "shell", kind = .Window, segment = 0, position = .45, width = 1, height = 1.2}); overwide_resize, overwide_resize_ok := level_opening_resize_command(&collision_window_doc, "custom_window", 30, 0); assert(overwide_resize_ok)
	wall_hanging_entry, wall_hanging_found := catalog_object_entry(
		"wall_lamp",
	); assert(wall_hanging_found && level_catalog_entry_uses_surface(wall_hanging_entry, "wall")); wall_hanging_path := opening_doc.paths[level_path_index(&opening_doc, "shell")]; wall_hanging_a, wall_hanging_b := wall_hanging_path.points[0], wall_hanging_path.points[1]; wall_hanging_opening := opening_doc.openings[0]; wall_hanging_point := Vec2{wall_hanging_a.x + (wall_hanging_b.x - wall_hanging_a.x) * wall_hanging_opening.position, wall_hanging_a.y + (wall_hanging_b.y - wall_hanging_a.y) * wall_hanging_opening.position}; wall_hanging_heading := f32(math.atan2(f64(wall_hanging_b.y - wall_hanging_a.y), f64(wall_hanging_b.x - wall_hanging_a.x))) * 180 / f32(math.PI)
	wall_hanging_score := level_wall_hanging_badness(
		&opening_doc,
		wall_hanging_point,
		1.2,
		wall_hanging_heading,
		wall_hanging_entry,
	); assert(wall_hanging_score.opening_overlap > .5 && wall_hanging_score.wall_penetration > .5 && wall_hanging_score.total > .5)
	wall_dx, wall_dy :=
		wall_hanging_b.x -
		wall_hanging_a.x,
		wall_hanging_b.y -
		wall_hanging_a.y; wall_length := f32(math.sqrt(f64(wall_dx * wall_dx + wall_dy * wall_dy))); mounted_offset := house_wall_width(wall_hanging_path.width) * .5 + wall_hanging_entry.dimensions.z * .5; mounted_point := Vec2{wall_hanging_point.x - wall_dy / wall_length * mounted_offset, wall_hanging_point.y + wall_dx / wall_length * mounted_offset}; mounted_score := level_wall_hanging_badness(&opening_doc, mounted_point, 1.2, wall_hanging_heading, wall_hanging_entry); assert(mounted_score.wall_penetration < .01)
	wall_hanging_preview := level_preview_transaction(
		&opening_doc,
		Level_Command {
			kind = .Place_Object,
			a = wall_hanging_point,
			c = {1.2, 0},
			value = wall_hanging_heading,
			material = "wall_lamp",
		},
	); assert(wall_hanging_preview.state == .Warning && strings.contains(wall_hanging_preview.message, "door or window")); detached_hanging_score := level_wall_hanging_badness(&opening_doc, {wall_hanging_point.x, wall_hanging_point.y + 1}, 1.2, wall_hanging_heading, wall_hanging_entry); assert(detached_hanging_score.wall_distance > .5)
	sill_before :=
		opening_doc.openings[0].sill_height; raise_sill, raise_sill_ok := level_window_sill_command(&opening_doc, "custom_window", .1); assert(raise_sill_ok && math.abs(raise_sill.points[0].x - (sill_before + .1)) < .001 && level_preview_transaction(&opening_doc, raise_sill).state == .Valid && level_commit_transaction(&opening_doc, raise_sill, "raise custom window sill") && math.abs(opening_doc.openings[0].sill_height - (sill_before + .1)) < .001); assert(level_undo(&opening_doc) && opening_doc.openings[0].sill_height == sill_before && level_redo(&opening_doc) && math.abs(opening_doc.openings[0].sill_height - (sill_before + .1)) < .001); too_high_sill := raise_sill; too_high_sill.points[0].x = 2; assert(level_preview_transaction(&opening_doc, too_high_sill).state == .Blocked)
	flip_window, flip_window_ok := level_window_flip_command(
		&opening_doc,
		"custom_window",
	); assert(flip_window_ok && flip_window.points[1].x == 1 && level_commit_transaction(&opening_doc, flip_window, "flip custom window") && opening_doc.openings[0].window_flipped && strings.contains(level_serialize(&opening_doc), "flipped = true")); assert(level_undo(&opening_doc) && !opening_doc.openings[0].window_flipped && level_redo(&opening_doc) && opening_doc.openings[0].window_flipped)
	casement_window, casement_window_ok := level_window_style_command(
		&opening_doc,
		"custom_window",
		.Casement,
	); assert(casement_window_ok && level_commit_transaction(&opening_doc, casement_window, "make custom window casement") && opening_doc.openings[0].window_style == .Casement); hand_window, hand_window_ok := level_window_handing_command(&opening_doc, "custom_window"); assert(hand_window_ok && hand_window.points[1].x == 1 && hand_window.points[1].y == 1 && level_commit_transaction(&opening_doc, hand_window, "right-hand custom window") && opening_doc.openings[0].window_hinge_right && strings.contains(level_serialize(&opening_doc), "hinge_right = true")); assert(level_undo(&opening_doc) && !opening_doc.openings[0].window_hinge_right && level_redo(&opening_doc) && opening_doc.openings[0].window_hinge_right)
	window_test_mesh := procedural_wall_mesh(
		2,
		1.4,
		.045,
	); window_model := vk_world_model(&window_test_mesh, 0, 0, 2.5, 1.8, 0, 0, 0, false); assert(math.abs(window_model[0] - 1.25) < .001 && math.abs(window_model[5] - (1.8 / 1.4)) < .001 && window_model[10] == 1)
	roof_doc := level_clone_document(
		&roundtrip,
	); clear(&roof_doc.roofs); roof_command := Level_Command {
		kind      = .Create_Roof,
		entity_id = "roof_command_test",
		material  = "test_room",
		a         = {f32(Level_Roof_Style.Gable), 30},
		b         = {.4, 1},
		value     = 35,
	}; assert(
		level_preview_transaction(&roof_doc, roof_command).state == .Valid &&
		level_commit_transaction(&roof_doc, roof_command, "create generated roof") &&
		len(roof_doc.roofs) == 1 &&
		roof_doc.roofs[0].gutters,
	); roof_mesh := procedural_roof_mesh(roof_doc.rooms[level_room_index(&roof_doc, "test_room")].points[:], .Gable, 35, .4, 30); assert(roof_mesh.ready && len(roof_mesh.indices) > 0 && roof_mesh.max.y > roof_mesh.min.y && len(roof_mesh.primitives) == 2 && roof_mesh.primitives[1].count > 0); flat_mesh := procedural_roof_mesh(roof_doc.rooms[level_room_index(&roof_doc, "test_room")].points[:], .Flat, 5, .2, 0); hip_mesh := procedural_roof_mesh(roof_doc.rooms[level_room_index(&roof_doc, "test_room")].points[:], .Hip, 30, .4, 0); assert(flat_mesh.ready && hip_mesh.ready && len(flat_mesh.primitives) == 2 && len(hip_mesh.primitives) == 2); compound_mesh := procedural_compound_roof_mesh(&level_test, 0, 30, .55); assert(compound_mesh.ready && compound_mesh.min.x < 7.5 && compound_mesh.max.x > 40.5 && compound_mesh.min.z < 9.5 && compound_mesh.max.z > 42.5 && len(compound_mesh.primitives) == 2 && compound_mesh.primitives[1].count > 0); set_roof := Level_Command {
		kind      = .Set_Roof,
		entity_id = "roof_command_test",
		material  = "test_room",
		a         = {f32(Level_Roof_Style.Hip), 90},
		b         = {.6, 0},
		value     = 40,
	}; assert(
		level_commit_transaction(&roof_doc, set_roof, "edit generated roof") &&
		roof_doc.roofs[0].style == .Hip &&
		roof_doc.roofs[0].overhang == .6 &&
		!roof_doc.roofs[0].gutters,
	); assert(level_undo(&roof_doc) && roof_doc.roofs[0].style == .Gable && roof_doc.roofs[0].gutters && level_redo(&roof_doc) && roof_doc.roofs[0].style == .Hip); assert(level_delete_selection(&roof_doc, {.Roof, "roof_command_test", -1}) && len(roof_doc.roofs) == 0 && level_undo(&roof_doc) && len(roof_doc.roofs) == 1)
	fmt.println("SELF TEST · LEVEL EDITING COMPLETE")
	// Geometry checks explicitly project authored LevelFormat content. The
	// runtime initializer is intentionally empty and provides no sample house.
	authored_geometry_fixture: Level_Document
	assert(level_load(LEVEL_DEFAULT_PATH, &authored_geometry_fixture).ok)
	authored_geometry_fixture.active_story = 0
	level_document = authored_geometry_fixture
	level_project_runtime(&level_document)
	authored_window: Plan_Opening
	authored_window_found := false
	for opening in house_plan.openings {if opening.kind == .Window {authored_window = opening; authored_window_found = true; break}}
	assert(authored_window_found)
	house_plan_initialize(

	); build_house_floorplan(); build_house_navmesh(); assert(house_wall_solid.ready && house_wall_solid_cutaway.ready && house_wall_cap_union.ready && house_wall_cap_union_edge.ready && len(house_wall_solid.indices) > 0 && len(house_wall_cap_union.indices) > 0 && (house_wall_cap_union_edge.max.x - house_wall_cap_union_edge.min.x) > (house_wall_cap_union.max.x - house_wall_cap_union.min.x) && house_space_kind_at(24, 23) == .Grounds && house_space_kind_at(12, 20) == .Interior); assert(house_window_room_sign(authored_window.a, authored_window.b) != 0 && house_window_room_sign(authored_window.a, authored_window.b) == -house_window_room_sign(authored_window.b, authored_window.a)); assert(house_window_sill_cap_mesh.ready && house_window_head_return_mesh.ready && house_window_jamb_return_mesh.ready && (house_window_sill_cap_mesh.max.z - house_window_sill_cap_mesh.min.z) > HOUSE_WALL_THICKNESS); assert((house_window_mesh.max.z - house_window_mesh.min.z) < (house_window_frame_h_mesh.max.z - house_window_frame_h_mesh.min.z) && house_window_hardware_offset() < HOUSE_WALL_THICKNESS * .5); window_solids := [20]^Glb_Mesh{&house_window_sill_mesh, &house_window_header_mesh, &house_window_frame_h_mesh, &house_window_frame_v_mesh, &house_window_muntin_h_mesh, &house_window_muntin_v_mesh, &house_window_bead_h_mesh, &house_window_bead_v_mesh, &house_window_hardware_h_mesh, &house_window_hardware_v_mesh, &house_window_sill_cap_mesh, &house_window_exterior_sill_mesh, &house_window_head_return_mesh, &house_window_jamb_return_mesh, &house_shutter_slat_mesh, &shutter_crank_housing_mesh, &shutter_crank_arm_mesh, &shutter_crank_link_mesh, &shutter_crank_grip_mesh, &shutter_silk_mesh}; for mesh in window_solids do assert(mesh_triangles_face_outward(mesh)); assert(glazing_faces_both_outward_directions(&house_window_mesh)); for opening in house_plan.openings {if opening.kind == .Door {mx, mz := (opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5; for wall in house_walls do assert(point_segment_distance_sq(mx, mz, wall.a, wall.b) > .08 * .08)}}; for entity, i in WORLD_ENTITIES {if entity.kind != "person" do continue; assert(nav_point_walkable(entity.x, entity.y)); for furniture in house_plan.furniture do assert((entity.x - furniture.x) * (entity.x - furniture.x) + (entity.y - furniture.y) * (entity.y - furniture.y) > (furniture.radius + .3) * (furniture.radius + .3)); for other, j in WORLD_ENTITIES do if other.kind == "person" && j > i do assert((entity.x - other.x) * (entity.x - other.x) + (entity.y - other.y) * (entity.y - other.y) > 1.2 * 1.2)}; placement_game := Game {
		story_project = &test_story_project,
	}; miriam_entity, daniel_entity, elsie_entity :=
		world_entity_index("miriam"),
		world_entity_index("daniel"),
		world_entity_index(
			"elsie",
		); assert(miriam_entity >= 0 && daniel_entity >= 0 && elsie_entity >= 0); placement_game.player_x = WORLD_ENTITIES[miriam_entity].x; placement_game.player_y = WORLD_ENTITIES[miriam_entity].y; assert(world_location_index(&placement_game) == 0); placement_game.player_x = WORLD_ENTITIES[daniel_entity].x; placement_game.player_y = WORLD_ENTITIES[daniel_entity].y; assert(world_location_index(&placement_game) == 0); placement_game.player_x = WORLD_ENTITIES[elsie_entity].x; placement_game.player_y = WORLD_ENTITIES[elsie_entity].y; assert(world_location_index(&placement_game) == 2); assert(HOUSE_AUTHORED_PATH_COST > 0 && HOUSE_AUTHORED_PATH_COST < 1); nav_game := Game {
		player_x = 12,
		player_y = 14,
	}; assert(
		nav_build_path(&nav_game, {nav_game.player_x, nav_game.player_y}, {24, 14}) &&
		nav_game.nav_path_count > 1,
	); for i in 0 ..< nav_game.nav_path_count do assert(nav_point_walkable(nav_game.nav_path[i].x, nav_game.nav_path[i].y))
	if !city_ground_mesh.ready do load_city_meshes()
	assert(
		city_ground_mesh.ready &&
		city_background_mesh.ready &&
		city_ground_mesh.max.x - city_ground_mesh.min.x == CITY_WORLD_WIDTH &&
		city_ground_mesh.max.z - city_ground_mesh.min.z == CITY_WORLD_HEIGHT &&
		(city_background_mesh.max.x - city_background_mesh.min.x) > CITY_WORLD_WIDTH &&
		(city_background_mesh.max.z - city_background_mesh.min.z) > CITY_WORLD_HEIGHT,
	)
	junction_finish_extended :=
		false; for wall, i in house_walls {finish_a, finish_b := house_exterior_wall_finish_span(i); authored_dx, authored_dz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; finish_dx, finish_dz := finish_b.x - finish_a.x, finish_b.y - finish_a.y; authored_length := f32(math.sqrt(f64(authored_dx * authored_dx + authored_dz * authored_dz))); finish_length := f32(math.sqrt(f64(finish_dx * finish_dx + finish_dz * finish_dz))); assert(finish_length <= authored_length + HOUSE_WALL_THICKNESS + .001); if finish_length > authored_length + .001 do junction_finish_extended = true}; assert(junction_finish_extended)
	placement_game.player_x = 16; placement_game.player_y = -4; assert(world_location_index(&placement_game) == -1 && strings.contains(world_location_label(&placement_game), "GROUNDS")); placement_game.player_x = 16; placement_game.player_y = 12; assert(world_location_index(&placement_game) >= 0)
	assert(
		house_wall_cap_batch_full.ready &&
		math.abs(house_wall_cap_batch_full.max.y - .001) < .0001,
	)
	assert(
		len(house_art_mesh.alpha_modes) == 1 &&
		house_art_mesh.alpha_modes[0] == 2 &&
		len(house_art_frame_mesh.alpha_modes) == 1 &&
		house_art_frame_mesh.alpha_modes[0] == 2,
	)
	assert(len(house_window_mesh.alpha_modes) == 1 && house_window_mesh.alpha_modes[0] == 2)
	assert(
		glb_thin_wall_material_role("lamp") == 1 &&
		glb_thin_wall_material_role("LampShade Linen") == 1 &&
		glb_thin_wall_material_role("metal") == 0,
	)
	lamp_material_test, lamp_material_ok := glb_load(
		"assets/kenney_furniture-kit/Models/GLTF format/lampSquareTable.glb",
	); assert(lamp_material_ok && len(lamp_material_test.material_names) == len(lamp_material_test.primitives)); lamp_thin_found, lamp_solid_found := false, false; for name in lamp_material_test.material_names {if glb_thin_wall_material_role(name) > 0 do lamp_thin_found = true
		else do lamp_solid_found = true}; assert(lamp_thin_found && lamp_solid_found)
	assert(
		house_window_exterior_sill_mesh.ready &&
		house_window_exterior_sill_mesh.vertices[2].y >
			house_window_exterior_sill_mesh.vertices[6].y,
	)
	study_desk_marker := level_marker_index(
		&level_document,
		"evidence_study_desk",
	); burned_note_marker := level_marker_index(&level_document, "evidence_burned_note"); assert(study_desk_marker >= 0 && burned_note_marker >= 0); desk_anchor := WORLD_ENTITIES[world_entity_index("study_desk")]; burned_note_anchor := WORLD_ENTITIES[world_entity_index("burned_note")]; assert(Vec2{desk_anchor.x, desk_anchor.y} == level_document.markers[study_desk_marker].position); assert(Vec2{burned_note_anchor.x, burned_note_anchor.y} == level_document.markers[burned_note_marker].position)
	poi_anchor_doc := level_clone_document(
		&level_document,
	); poi_desk_marker := level_marker_index(&poi_anchor_doc, "evidence_study_desk"); poi_ledger_marker := level_marker_index(&poi_anchor_doc, "evidence_ledger"); assert(poi_desk_marker >= 0 && poi_ledger_marker >= 0); poi_anchor_doc.markers[poi_desk_marker].position = {12.25, 25.1}; poi_anchor_doc.markers[poi_ledger_marker].position = {12.37, 24.87}; assert(world_entities_rebuild(&test_story_project, &poi_anchor_doc).ok); synced_desk := WORLD_ENTITIES[world_entity_index("study_desk")]; synced_ledger := WORLD_ENTITIES[world_entity_index("ledger")]; assert(Vec2{synced_desk.x, synced_desk.y} == poi_anchor_doc.markers[poi_desk_marker].position); assert(math.abs(synced_ledger.x - 12.37) < .001 && math.abs(synced_ledger.y - 24.87) < .001); assert(world_entities_rebuild(&test_story_project, &level_document).ok)
	collision_game :=
		Game{}; assert(house_wall_solid.ready); collision_water_points := make([dynamic]Vec2, 0, 4); append(&collision_water_points, Vec2{17, 6}, Vec2{21, 6}, Vec2{21, 10}, Vec2{17, 10}); append(&level_document.waters, Level_Water{id = "collision_test_pond", points = collision_water_points, elevation = .25}); assert(house_player_blocked(&collision_game, 19, 8)); ordered_remove(&level_document.waters, len(level_document.waters) - 1); front_mat_index := level_object_index(&level_document, "front_doormat"); assert(front_mat_index >= 0 && !catalog_object_blocks_movement(level_document.objects[front_mat_index]) && !furniture_blocked(24, 10.65)); test_doorway := Plan_Opening {
			id     = "test_doorway",
			kind   = .Door,
			a      = {40, 40},
			b      = {42, 40},
			height = 2.1,
		}; append(
		&level_document.objects,
		Level_Object {
			id = "doorway_crate",
			catalog_id = "core:side_table",
			story = level_document.active_story,
			position = {41, 40},
		},
	); assert(doorway_object_obstructs(test_doorway) && furniture_blocked(41, 40)); level_document.objects[len(level_document.objects) - 1].elevation = 2.2; assert(!doorway_object_obstructs(test_doorway) && !furniture_blocked(41, 40)); ordered_remove(&level_document.objects, len(level_document.objects) - 1)
	pad_game := Game {
			story_project = &test_story_project,
			screen        = .Investigate,
			ap            = 12,
			player_x      = 12,
			player_y      = 14,
			near_entity   = -1,
			pad_left_y    = -1,
		}; old_x, old_y :=
		pad_game.player_x,
		pad_game.player_y; update_world(&pad_game); assert(math.abs(pad_game.player_x - old_x) + math.abs(pad_game.player_y - old_y) > 0)
	first_speed :=
		math.abs(pad_game.player_velocity_x) +
		math.abs(
			pad_game.player_velocity_y,
		); update_world(&pad_game); assert(math.abs(pad_game.player_velocity_x) + math.abs(pad_game.player_velocity_y) > first_speed); pad_game.pad_left_y = 0; for _ in 0 ..< 12 do update_world(&pad_game); assert(math.abs(pad_game.player_velocity_x) + math.abs(pad_game.player_velocity_y) < .001 && pad_game.camera_initialized)
	old_angle :=
		pad_game.player_angle; pad_game.pad_right_x = 1; pad_game.pad_right_y = -.5; pad_game.pad_left_y = 0; old_cursor := pad_game.input.mouse_pos; update_world(&pad_game); assert(pad_game.player_angle == old_angle && pad_game.input.mouse_pos == old_cursor && pad_game.camera_orbit > math.PI / 4 && pad_game.camera_zoom < 1)
	wheel_zoom := Game {
			camera_zoom = 1,
			camera_orbit_initialized = true,
			camera_initialized = true,
			input = {mouse_wheel = 1},
		}; update_aerial_camera(
		&wheel_zoom,
	); assert(wheel_zoom.camera_zoom < 1); wheel_zoom.camera_zoom = .21; wheel_zoom.editor_mode = .Build; update_aerial_camera(&wheel_zoom); assert(wheel_zoom.camera_zoom == EDITOR_CAMERA_MIN_ZOOM); wheel_zoom.editor_mode = .None; update_aerial_camera(&wheel_zoom); assert(wheel_zoom.camera_zoom == .55)
	pad_game.input.camera_toggle =
		true; orbit_before := pad_game.camera_orbit; update_world(&pad_game); assert(pad_game.first_person_camera && pad_game.camera_orbit == orbit_before && pad_game.player_angle > old_angle); pad_game.input.camera_toggle = false
	assert(
		pad_game.first_person_pitch > 0,
	); pad_game.pad_right_y = 1; for _ in 0 ..< 60 do update_world(&pad_game); assert(pad_game.first_person_pitch == -.45); pad_game.pad_right_y = -1; for _ in 0 ..< 60 do update_world(&pad_game); assert(pad_game.first_person_pitch == .45)
	relative_game := Game {
			story_project            = &test_story_project,
			screen                   = .Investigate,
			ap                       = 12,
			player_x                 = 12,
			player_y                 = 14,
			near_entity              = -1,
			camera_orbit             = 0,
			camera_zoom              = 1,
			camera_orbit_initialized = true,
			pad_left_y               = -1,
		}; relative_x, relative_y :=
		relative_game.player_x,
		relative_game.player_y; update_world(&relative_game); assert(relative_game.player_x < relative_x && math.abs(relative_game.player_y - relative_y) < .01)
	strafe_game := Game {
			story_project            = &test_story_project,
			screen                   = .Investigate,
			ap                       = 12,
			player_x                 = 12,
			player_y                 = 14,
			player_angle             = 0,
			near_entity              = -1,
			first_person_camera      = true,
			camera_orbit_initialized = true,
			camera_zoom              = 1,
			pad_left_x               = 1,
		}; strafe_x, strafe_y, strafe_angle :=
		strafe_game.player_x,
		strafe_game.player_y,
		strafe_game.player_angle; update_world(&strafe_game); assert(math.abs(strafe_game.player_x - strafe_x) < .01 && strafe_game.player_y > strafe_y && strafe_game.player_angle == strafe_angle)
	pad_game = Game {
			story_project = &test_story_project,
			ap            = 12,
			player_x      = 12,
			player_y      = 14,
		}; assert(
		pad_game.pad_left_x == 0 && pad_game.pad_right_x == 0 && !pad_game.pad_buttons[.SOUTH],
	)
	// Collision and sightlines use an authored wall segment, never a compiled
	// sample-house coordinate.
	assert(len(house_walls) > 0)
	authored_wall :=
		house_walls[0]; wall_mid := Vec2{(authored_wall.a.x + authored_wall.b.x) * .5, (authored_wall.a.y + authored_wall.b.y) * .5}; authored_wall_dx, authored_wall_dz := authored_wall.b.x - authored_wall.a.x, authored_wall.b.y - authored_wall.a.y; authored_wall_length := f32(math.sqrt(f64(authored_wall_dx * authored_wall_dx + authored_wall_dz * authored_wall_dz))); wall_normal := Vec2{-authored_wall_dz / authored_wall_length, authored_wall_dx / authored_wall_length}
	assert(
		world_wall(wall_mid.x, wall_mid.y),
	); assert(!world_line_clear(wall_mid.x - wall_normal.x, wall_mid.y - wall_normal.y, wall_mid.x + wall_normal.x, wall_mid.y + wall_normal.y))
	search_test := Game {
			story_project = &test_story_project,
			ap            = 12,
		}; initialize_test_mystery_state(
		&search_test,
	); search_ledger := world_entity_index("ledger"); assert(search_ledger >= 0 && !entity_visible(&search_test, &WORLD_ENTITIES[search_ledger])); assert(reveal_location_pois(&search_test, 2)); assert(search_test.ap == 12 && mystery_game_location_searched(&search_test, 2) && mystery_game_poi_revealed(&search_test, 0) && mystery_game_poi_revealed(&search_test, 1) && !mystery_game_poi_revealed(&search_test, 4)); search_history := search_test.history_count; assert(!reveal_location_pois(&search_test, 2) && search_test.history_count == search_history); assert(!reveal_location_pois(&search_test, 1) && !mystery_game_location_searched(&search_test, 1))
	connected_saved_doc := level_document; connected_doc := Level_Document {
			active_story = 0,
		}; connected_doc.rooms = make(
		[dynamic]Level_Room,
		0,
		2,
	); connected_doc.paths = make([dynamic]Level_Path, 0); study_points := make([dynamic]Vec2, 0, 4); dining_points := make([dynamic]Vec2, 0, 4); append(&study_points, Vec2{0, 0}, Vec2{4, 0}, Vec2{4, 4}, Vec2{0, 4}); append(&dining_points, Vec2{4, 0}, Vec2{8, 0}, Vec2{8, 4}, Vec2{4, 4}); append(&connected_doc.rooms, Level_Room{id = "study", story = 0, points = study_points}, Level_Room{id = "dining_room", story = 0, points = dining_points}); level_document = connected_doc; connected_search := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&connected_search,
	); dining_location := -1; for location, i in payload.locations do if location.entity_id == "dining_room" do dining_location = i; assert(dining_location >= 0 && world_room_open_connection(0, 1)); assert(reveal_location_pois(&connected_search, 2) && mystery_game_location_searched(&connected_search, 2) && mystery_game_location_searched(&connected_search, dining_location)); wall_points := make([dynamic]Vec2, 0, 2); append(&wall_points, Vec2{4, 0}, Vec2{4, 4}); append(&level_document.paths, Level_Path{id = "divider", story = 0, kind = .Wall, points = wall_points}); assert(!world_room_open_connection(0, 1)); level_document = connected_saved_doc
	pantry_search := Game {
		ap = 12,
	}; initialize_test_mystery_state(
		&pantry_search,
	); assert(reveal_location_pois(&pantry_search, 4) && pantry_search.ap == 12)
	visibility_game := Game {
		ap           = 12,
		screen       = .Investigate,
		player_x     = 23,
		player_y     = 25.05,
		player_angle = 0,
		near_entity  = -1,
	}; initialize_test_mystery_state(
		&visibility_game,
	); cane_poi := poi_index(&visibility_game, "cane"); assert(cane_poi >= 0); _ = mystery_game_mark_poi_revealed(&visibility_game, cane_poi); update_world(&visibility_game); assert(visibility_game.near_entity >= 0 && WORLD_ENTITIES[visibility_game.near_entity].source_id == "cane")
	visibility_game = Game {
		story_project = &test_story_project,
		ap            = 12,
		screen        = .Investigate,
		player_x      = 20.5,
		player_y      = 24.8,
		player_angle  = 0,
		near_entity   = -1,
	}; update_world(
		&visibility_game,
	); assert(visibility_game.near_entity >= 0 && WORLD_ENTITIES[visibility_game.near_entity].source_id == "garden")
	// Exterior traversal is a separate, city-scale world with connected bridge crossings.
	assert(
		CITY_WIDTH * CITY_HEIGHT == 30720,
	); assert(city_district_name(18.5) == "WESTHAVEN"); assert(city_district_name(82.5) == "CENTRAL LOOP"); assert(city_district_name(162.5) == "LAKE INDUSTRIAL")
	assert(
		CITY_WORLD_WIDTH == 384 && CITY_WORLD_HEIGHT == 320 && city_world(4) == 8,
	); assert(city_neighborhood_name(city_world(18.5), city_world(31.5)) == "WESTHAVEN HEIGHTS"); assert(city_neighborhood_name(city_world(34.5), city_world(98.5)) == "DEPOT WARD"); assert(city_neighborhood_name(city_world(82.5), city_world(34.5)) == "OLD MARKET"); assert(city_neighborhood_name(city_world(114.5), city_world(82.5)) == "CIVIC LOOP"); assert(city_neighborhood_name(city_world(98.5), city_world(114.5)) == "FOUNDRY WARD"); assert(city_neighborhood_name(city_world(146.5), city_world(82.5)) == "SOUTH QUAY"); assert(city_neighborhood_name(city_world(162.5), city_world(130.5)) == "MARINA REACH")
	assert(
		math.abs(city_elevation(0, 0)) < .0001 &&
		math.abs(city_elevation(CITY_WORLD_WIDTH, CITY_WORLD_HEIGHT)) < .0001 &&
		city_elevation(CITY_WORLD_WIDTH * .5, CITY_WORLD_HEIGHT * .5) > 4,
	); city_terrain_test := procedural_city_ground_mesh(); assert(city_terrain_test.ready && len(city_terrain_test.vertices) > 1000 && len(city_terrain_test.indices) % 6 == 0 && city_terrain_test.max.y > 7)
	assert(
		!city_road_cell(-1, 0) &&
		!city_road_cell(0, -1) &&
		!city_road_cell(CITY_WIDTH, 0) &&
		!city_road_cell(0, CITY_HEIGHT),
	); edge_mask := city_road_connection_mask(2, 2); assert(edge_mask & CITY_ROAD_SOUTH == 0 && edge_mask & CITY_ROAD_WEST == 0); straight_mesh, _ := city_road_tile(CITY_ROAD_EAST | CITY_ROAD_WEST); bend_mesh, _ := city_road_tile(CITY_ROAD_NORTH | CITY_ROAD_EAST); tee_mesh, _ := city_road_tile(CITY_ROAD_NORTH | CITY_ROAD_EAST | CITY_ROAD_WEST); cross_mesh, _ := city_road_tile(CITY_ROAD_NORTH | CITY_ROAD_EAST | CITY_ROAD_SOUTH | CITY_ROAD_WEST); end_mesh, _ := city_road_tile(CITY_ROAD_NORTH); assert(straight_mesh == 0 && cross_mesh == 1 && bend_mesh == 2 && tee_mesh == 3 && end_mesh == 4)
	road_surface_x, road_surface_z :=
		city_world(f32(2)),
		city_world(
			f32(2),
		); assert(city_surface_elevation(road_surface_x, road_surface_z) >= city_elevation(road_surface_x, road_surface_z)); city_collision_game := new(Game); defer free(city_collision_game); initialize_city_vehicles(city_collision_game); city_collision_game.city_furniture = make([dynamic]City_Furniture_State, 0); city_collision_game.city_x = road_surface_x; city_collision_game.city_y = road_surface_z; assert(!city_player_blocked(city_collision_game, road_surface_x, road_surface_z)); assert(city_player_blocked(city_collision_game, -.1, road_surface_z))
	station :=
		CITY_FIXED_LANDMARKS[0]; assert(!city_wall(station.arrival_x, station.arrival_y)); assert(station.arrival_x < station.x && station.arrival_facing == 0); assert(!city_wall(station.x, station.y)); case_landmark, case_landmark_ok := city_landmark_at(&Game{story_project = &test_story_project}, len(CITY_FIXED_LANDMARKS)); assert(case_landmark_ok && case_landmark.name == "VALE HOUSE" && !city_wall(case_landmark.x, case_landmark.y)); station_to_case_x, station_to_case_y := station.arrival_x - case_landmark.arrival_x, station.arrival_y - case_landmark.arrival_y; assert(station_to_case_x * station_to_case_x + station_to_case_y * station_to_case_y > city_world(40) * city_world(40)); assert(city_wall(-1, city_world(20))); assert(city_wall(CITY_WORLD_WIDTH, city_world(20)))
	station_layout_x, station_layout_y, station_place := city_building_site(
		3,
		3,
	); station_mesh, station_height, station_yaw, station_tint := city_building_style(3, 3, station_layout_x); assert(station_place && station_layout_x > city_layout(station.x) && station_layout_y < city_layout(station.y)); assert(city_police_station_building(3, 3) && !city_police_station_building(1, 1)); assert(station_mesh == 2 && station_height == 4.1 && station_yaw == -f32(math.PI / 2) && station_tint == [4]u8{184, 205, 214, 255})
	fixed_context := Game {
		story_project   = &test_story_project,
		near_landmark   = 1,
		driving_vehicle = -1,
		near_vehicle    = -1,
	}; tutorial_complete(
		&fixed_context,
		.Briefing,
	); context_resolve_city(&fixed_context); assert(fixed_context.context_ui.current.reachable && fixed_context.context_ui.current.stable_id == "old_market")
	briefing_context := Game {
		story_project   = &test_story_project,
		driving_vehicle = -1,
		near_vehicle    = -1,
		near_landmark   = -1,
	}; assert(
		!city_briefing_actionable(&briefing_context),
	); briefing_context.near_landmark = 0; context_resolve_city(&briefing_context); assert(city_briefing_actionable(&briefing_context)); briefing_context.context_ui.current.reachable = false; assert(!city_briefing_actionable(&briefing_context))
	vale_landmark, _ := city_landmark_at(
		&briefing_context,
		len(CITY_FIXED_LANDMARKS),
	); assert(!city_quest_marker_visible(&briefing_context, vale_landmark)); tutorial_complete(&briefing_context, .Briefing); assert(city_quest_marker_visible(&briefing_context, vale_landmark)); assert(!city_quest_marker_visible(&briefing_context, CITY_FIXED_LANDMARKS[0]))
	clamped_far := city_minimap_clamp_quest_marker(
		{-500, 900},
		100,
		80,
		200,
		160,
	); assert(clamped_far == Vec2{111, 229}); clamped_near := city_minimap_clamp_quest_marker({180, 140}, 100, 80, 200, 160); assert(clamped_near == Vec2{180, 140})
	destination_game := Game {
		story_project   = &test_story_project,
		driving_vehicle = -1,
		near_vehicle    = -1,
		near_landmark   = -1,
	}; tutorial_complete(&destination_game, .Briefing); destination_target := Context_Target {
		valid        = true,
		kind         = .Landmark,
		status       = .Available,
		source_index = len(CITY_FIXED_LANDMARKS),
		reachable    = true,
	}; assert(
		context_activate_city(&destination_game, destination_target) &&
		destination_game.screen == .Investigate &&
		destination_game.city_return_x == case_landmark.arrival_x &&
		destination_game.city_return_y == case_landmark.arrival_y &&
		destination_game.player_x ==
			level_document.markers[level_marker_index(&level_document, payload.city_labels[0].level_spawn)].position.x,
	)
	// The former river bands have no matching rendered geometry, so they must
	// remain traversable instead of creating invisible walls through the city.
	assert(
		!city_wall(city_world(63), city_world(32)),
	); assert(!city_wall(city_world(63), city_world(48))); assert(!city_wall(city_world(127), city_world(16))); assert(!city_wall(city_world(127), city_world(48)))
	// Empty lots and the setback around a building are rough but driveable; the
	// structure itself remains solid.
	assert(
		!city_road_cell(8, 8) &&
		!city_open_space_cell(8, 8) &&
		!city_wall(city_world(8), city_world(8)) &&
		city_driving_surface(city_world(8), city_world(8)) == .Open_Ground,
	)
	building_x, building_y, building_present := city_building_site(
		1,
		0,
	); assert(building_present && city_wall(city_world(building_x), city_world(building_y))); assert(!city_road_cell(21, 8) && !city_wall(city_world(21), city_world(8)))
	building_mesh_index, building_height, building_yaw, _ := city_building_style(
		1,
		0,
		building_x,
	); building_mesh := &city_meshes[building_mesh_index]; building_scale := building_height / (building_mesh.max.y - building_mesh.min.y); building_half_x := (building_mesh.max.x - building_mesh.min.x) * building_scale * .5; building_half_z := (building_mesh.max.z - building_mesh.min.z) * building_scale * .5; building_edge_x := building_x + math.cos(building_yaw) * (building_half_x + .05) - math.sin(building_yaw) * (building_half_z + .05); building_edge_y := building_y + math.sin(building_yaw) * (building_half_x + .05) + math.cos(building_yaw) * (building_half_z + .05); assert(!city_building_wall(building_edge_x, building_edge_y))
	cull_game := Game {
		city_x          = 20,
		city_y          = 20,
		city_angle      = 0,
		driving_vehicle = -1,
	}; initialize_city_vehicles(
		&cull_game,
	); defer delete(cull_game.vehicles); cull_game.driving_vehicle = -1; assert(city_render_chunk_visible(&cull_game, 10, 20, CITY_ROAD_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); assert(city_render_chunk_visible(&cull_game, 20 + CITY_ROAD_DRAW_DISTANCE - .1, 20, CITY_ROAD_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); assert(!city_render_chunk_visible(&cull_game, 20 + CITY_ROAD_DRAW_DISTANCE + .1, 20, CITY_ROAD_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); cull_game.driving_vehicle = 0; cull_game.vehicles[0] = {
		x       = 20,
		y       = 20,
		heading = 0,
	}; cull_game.vehicle_camera_follow_distance = 5.2; cull_view := vk_world_view_pose(&cull_game); cull_forward := Vec2{cull_view.target.x - cull_view.eye.x, cull_view.target.z - cull_view.eye.z}; cull_length := math.sqrt(cull_forward.x * cull_forward.x + cull_forward.y * cull_forward.y); cull_forward.x /= cull_length; cull_forward.y /= cull_length; cull_ahead := Vec2{cull_view.eye.x + cull_forward.x * 100, cull_view.eye.z + cull_forward.y * 100}; cull_behind := Vec2{cull_view.eye.x - cull_forward.x * (math.abs(CITY_DRIVING_BEHIND_DISTANCE) + 1), cull_view.eye.z - cull_forward.y * (math.abs(CITY_DRIVING_BEHIND_DISTANCE) + 1)}; assert(city_render_chunk_visible(&cull_game, cull_ahead.x, cull_ahead.y, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); assert(!city_render_chunk_visible(&cull_game, cull_behind.x, cull_behind.y, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); cull_game.vehicle_camera_reverse_blend = 1; reverse_view := vk_world_view_pose(&cull_game); reverse_forward := Vec2{reverse_view.target.x - reverse_view.eye.x, reverse_view.target.z - reverse_view.eye.z}; reverse_length := math.sqrt(reverse_forward.x * reverse_forward.x + reverse_forward.y * reverse_forward.y); reverse_forward.x /= reverse_length; reverse_forward.y /= reverse_length; reverse_ahead := Vec2{reverse_view.eye.x + reverse_forward.x * 100, reverse_view.eye.z + reverse_forward.y * 100}; reverse_behind := Vec2{reverse_view.eye.x - reverse_forward.x * (math.abs(CITY_DRIVING_BEHIND_DISTANCE) + 1), reverse_view.eye.z - reverse_forward.y * (math.abs(CITY_DRIVING_BEHIND_DISTANCE) + 1)}; assert(city_render_chunk_visible(&cull_game, reverse_ahead.x, reverse_ahead.y, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE)); assert(!city_render_chunk_visible(&cull_game, reverse_behind.x, reverse_behind.y, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE))
	assert(
		len(CITY_CARS) == 22 && CITY_CARS[len(CITY_CARS) - 1].model == "police",
	); for car in CITY_CARS {assert(!city_wall(city_world(car.x), city_world(car.y))); assert(os.exists(fmt.tprintf("assets/kenney_car-kit/Models/GLB format/%s.glb", car.model)))}
	assert(
		VEHICLE_TUNE_STANDARD.max_forward == .58 &&
		VEHICLE_TUNE_SPORT.max_forward == .68 &&
		VEHICLE_TUNE_UTILITY.max_forward == .51 &&
		VEHICLE_TUNE_HEAVY.max_forward == .43,
	)
	run_vehicle_self_tests()
	city_game := Game {
		story_project = &test_story_project,
		screen = .Exterior,
		city_x = case_landmark.x - f32(math.cos(f64(case_landmark.arrival_facing))),
		city_y = case_landmark.y - f32(math.sin(f64(case_landmark.arrival_facing))),
		city_angle = case_landmark.arrival_facing,
		driving_vehicle = -1,
		near_vehicle = -1,
		near_landmark = -1,
		input = {activate = true},
	}; tutorial_complete(
		&city_game,
		.Briefing,
	); update_city(&city_game); assert(city_game.near_landmark == len(CITY_FIXED_LANDMARKS) && city_game.screen == .Investigate); spawn_marker := level_document.markers[level_marker_index(&level_document, payload.city_labels[0].level_spawn)]; assert(city_game.player_x == spawn_marker.position.x && city_game.player_y == spawn_marker.position.y)
	for path, i in CHARACTER_MESH_PATHS {mesh, mesh_ok := glb_load(path)
		assert(mesh_ok && mesh.ready)
		assert(len(mesh.vertices) > 0 && len(mesh.indices) > 0 && len(mesh.indices) % 3 == 0)
		assert(mesh.max.y > mesh.min.y)
		assert(
			glb_has_animation(&mesh, "Idle_A") &&
			glb_has_animation(&mesh, "Idle_B") &&
			glb_has_animation(&mesh, "Interact") &&
			glb_has_animation(&mesh, "Walking_B") &&
			glb_has_animation(&mesh, "Running_A"),
		)
		assert(
			len(mesh.skin.joints) > 0 &&
			len(mesh.skin.inverse_bind) == len(mesh.skin.joints) &&
			len(mesh.joints) == len(mesh.vertices) &&
			len(mesh.weights) == len(mesh.vertices),
		)
		character_meshes[i] =
			mesh}; case_mesh_paths := [8]string{"assets/models/bronze-statuette.glb", "assets/models/edgars-cane.glb", "assets/models/private-ledger.glb", "assets/models/polishing-cloth.glb", "assets/models/lamp-oil-bottle.glb", "assets/models/stopped-watch-824.glb", "assets/rugs/study_rug_unfolded.glb", "assets/rugs/study_rug_folded.glb"}; for path, i in case_mesh_paths {case_mesh, case_mesh_ok := glb_load(path); assert(case_mesh_ok && case_mesh.ready && len(case_mesh.vertices) > 0 && len(case_mesh.indices) > 0 && len(case_mesh.indices) % 3 == 0); if i == 0 {assert(case_mesh.max.y - case_mesh.min.y > case_mesh.max.x - case_mesh.min.x); assert(case_mesh.max.y - case_mesh.min.y > case_mesh.max.z - case_mesh.min.z)}}
	mesh := &character_meshes[0]; pose := make([]Glb_TRS, len(mesh.nodes), context.temp_allocator); palette := make([]Glb_Mat4, len(mesh.skin.joints), context.temp_allocator); assert(glb_sample_pose(mesh, glb_clip_index(mesh, "Idle_A"), .25, true, pose) && glb_pose_palette(mesh, pose, palette)); q := glb_quat_slerp({0, 0, 0, 1}, {0, 0, 0, -1}, .5); assert(math.abs(q.w - 1) < .001)
	animation_game := Game {
		story_project = &test_story_project,
	}; initialize_character_animations(
		&animation_game,
	); assert(animation_game.character_animations[1].current == animation_game.character_animations[1].idle_clip && animation_game.character_animations[2].current == animation_game.character_animations[2].idle_clip); trigger_character_interact(&animation_game, "miriam"); assert(animation_game.character_animations[1].transitioning && animation_game.character_animations[1].next == glb_clip_index(&character_meshes[1], "Interact")); for _ in 0 ..< 300 do update_character_animations(&animation_game, 1.0 / 60.0); assert(!animation_game.character_animations[1].interacting)
	assert(
		character_action_clip(&character_meshes[1], .Sit) >= 0 &&
		character_action_clip(&character_meshes[1], .Jump) >= 0 &&
		character_action_clip(&character_meshes[1], .React) >= 0 &&
		character_action_clip(&character_meshes[1], .Death) >= 0,
	); assert(trigger_character_action(&animation_game, "miriam", .Sit)); for _ in 0 ..< 180 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.character_animations[1].action_loop && animation_game.character_animations[1].current == character_action_clip(&character_meshes[1], .Sit)); assert(stop_character_action(&animation_game, "miriam")); for _ in 0 ..< 30 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.character_animations[1].current == animation_game.character_animations[1].idle_clip)
	animation_game.player_is_walking =
		true; for _ in 0 ..< 30 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.player_animation.current == glb_clip_index(&character_meshes[0], "Walking_B")); animation_game.player_is_walking = false; for _ in 0 ..< 30 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.player_animation.current == glb_clip_index(&character_meshes[0], "Idle_A"))
	animation_game.player_is_walking =
		true; animation_game.player_walk_speed = HOUSE_MANUAL_MOVE_SPEED * 1.5; for _ in 0 ..< 30 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.player_animation.current == glb_clip_index(&character_meshes[0], "Running_A")); animation_game.player_is_walking = false; animation_game.player_walk_speed = 0; for _ in 0 ..< 30 do update_character_animations(&animation_game, 1.0 / 60.0)
	animation_game.player_is_walking =
		true; update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.player_animation.transitioning); animation_game.player_is_walking = false; update_character_animations(&animation_game, 1.0 / 60.0); for _ in 0 ..< 15 do update_character_animations(&animation_game, 1.0 / 60.0); assert(animation_game.player_animation.current == glb_clip_index(&character_meshes[0], "Idle_A"))
	textured_mesh, textured_mesh_ok := glb_load(
		"assets/KayKit_Character_Animations_1.1/Mannequin Character/characters/Mannequin_Medium.glb",
	); assert(textured_mesh_ok && len(textured_mesh.texcoords) == len(textured_mesh.vertices)); assert(len(textured_mesh.textures) == 1 && len(textured_mesh.textures[0].pixels) > 0); assert(len(textured_mesh.primitives) > 0 && textured_mesh.primitives[0].texture == 0); assert(len(textured_mesh.normal_textures) == len(textured_mesh.primitives) && len(textured_mesh.roughness_textures) == len(textured_mesh.primitives)); assert(len(textured_mesh.metallic_factors) == len(textured_mesh.primitives) && len(textured_mesh.roughness_factors) == len(textured_mesh.primitives) && len(textured_mesh.normal_scales) == len(textured_mesh.primitives)); assert(textured_mesh.normal_textures[0] >= -1 && textured_mesh.roughness_textures[0] >= -1 && textured_mesh.metallic_factors[0] >= 0 && textured_mesh.metallic_factors[0] <= 1 && textured_mesh.roughness_factors[0] >= 0 && textured_mesh.roughness_factors[0] <= 1 && textured_mesh.normal_scales[0] >= 0)
	city_texture_mesh, city_texture_ok := glb_load(
		"assets/kenney_city-kit-commercial_2.1/Models/GLB format/building-a.glb",
	); assert(city_texture_ok && len(city_texture_mesh.textures) == 1 && len(city_texture_mesh.textures[0].pixels) > 0); assert(len(city_texture_mesh.primitives) > 0 && city_texture_mesh.primitives[0].texture == 0)
	road_mesh, road_mesh_ok := glb_load(
		"assets/kenney_city-kit-roads/Models/GLB format/road-crossroad.glb",
	); assert(road_mesh_ok && len(road_mesh.textures) == 1 && len(road_mesh.textures[0].pixels) > 0); assert(road_mesh.max.x - road_mesh.min.x > road_mesh.max.y - road_mesh.min.y)
	// FPS-style near clipping preserves the visible portion of geometry that
	// crosses the camera plane instead of dropping the whole triangle.
	_, missing_mesh_ok := glb_load("assets/does-not-exist.glb"); assert(!missing_mesh_ok)
	run_vertical_link_tests(

	); run_roof_numeric_tests(); run_light_numeric_tests(); run_marker_numeric_tests(); run_light_direction_numeric_tests(); run_ground_generation_tests(); run_marker_editor_tests(); run_diagnostic_focus_tests(); run_editor_playtest_tests(); run_editor_selection_set_tests(); run_vale_house_editor_acceptance_tests(); run_build_spatial_acceptance_tests()
	fmt.println(
		"359/359 StoryCore, house tool, level editor, city, vehicle, and GLB checks passed",
	)
}
