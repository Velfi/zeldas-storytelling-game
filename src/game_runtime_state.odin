package main

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"
import ui "zelda_engine:ui"

Drag_State :: struct {
	kind:               Drag_Kind,
	index, hover_index: int,
	start, offset:      Vec2,
	active:             bool,
	origin_screen:      Screen,
}
Guidance_Mode :: enum {
	Full,
	Adaptive,
	Minimal,
}
Tutorial_Capability :: enum {
	Move,
	Look,
	Contextual_Interaction,
	Travel,
	Examine,
	Converse,
	Notebook,
	Case_Sense,
	Board_Place,
	Board_Test,
	Briefing,
}
Tutorial_Progress :: struct {
	completed:                     [Tutorial_Capability]bool,
	guidance:                      Guidance_Mode,
	case_sense_reminder_dismissed: bool,
}

tutorial_complete :: proc(g: ^Game, capability: Tutorial_Capability) {g.tutorial.completed[capability] =
		true}
tutorial_completed :: proc(g: ^Game, capability: Tutorial_Capability) -> bool {return(
		g.tutorial.completed[capability] \
	)}
guidance_mode_label :: proc(mode: Guidance_Mode) -> string {switch mode {case .Full:
		return "FULL"; case .Adaptive:
		return "ADAPTIVE"; case .Minimal:
		return "MINIMAL"}; return "ADAPTIVE"}
tutorial_capability_id :: proc(capability: Tutorial_Capability) -> string {switch
	capability {case .Move:
		return "move"; case .Look:
		return "look"; case .Contextual_Interaction:
		return "contextual_interaction"; case .Travel:
		return "travel"; case .Examine:
		return "examine"; case .Converse:
		return "converse"; case .Notebook:
		return "notebook"; case .Case_Sense:
		return "case_sense"; case .Board_Place:
		return "board_place"; case .Board_Test:
		return "board_test"; case .Briefing:
		return "briefing"}
	return ""}
tutorial_lesson_prompt :: proc(
	g: ^Game,
	capability: Tutorial_Capability,
	fallback: string,
) -> string {id := tutorial_capability_id(capability); payload := mystery_game_payload(g)
	if payload !=
	   nil {for lesson in payload.tutorial_lessons do if lesson.capability == id && lesson.prompt != "" do return lesson.prompt}
	return fallback}

game_story_milestone :: proc(g: ^Game, id: string) -> bool {
	if g.story_project == nil || g.story_state == nil || id == "" do return false
	indices: [dynamic]int; defer delete(indices)
	for effect, index in g.story_project.effects do if effect.kind == .Set_Objective && effect.content_id == id do append(&indices, index)
	if len(indices) == 0 do return false
	result := story_apply_transaction(
		g.story_project,
		g.story_state,
		indices[:],
		g.spatial_service,
	)
	return result.ok
}
Game :: struct {
	running,
	window_resized,
	character_studio,
	controller_disconnected,
	input_resume_blocked:                                                                                                                                                                               bool,
	input:                                                                                                                                                                                                                                                                  Input_State,
	keys:                                                                                                                                                                                                                                                                   #sparse[sdl.Scancode]bool,
	pad_buttons:                                                                                                                                                                                                                                                            #sparse[sdl.GamepadButton]bool,
	pad_left_x,
	pad_left_y,
	pad_right_x,
	pad_right_y,
	pad_left_trigger,
	pad_right_trigger:                                                                                                                                                                                  f32,
	gamepad:                                                                                                                                                                                                                                                                ^sdl.Gamepad,
	gamepad_type:                                                                                                                                                                                                                                                           sdl.GamepadType,
	active_device:                                                                                                                                                                                                                                                          Input_Device,
	axis_nav_x,
	axis_nav_y:                                                                                                                                                                                                                                                 i8,
	mouse_device_motion:                                                                                                                                                                                                                                                    Vec2,
	vehicle_haptics_active,
	vehicle_haptics_failed:                                                                                                                                                                                                                         bool,
	audio_stream,
	vehicle_audio_stream:                                                                                                                                                                                                                                     ^sdl.AudioStream,
	vehicle_audio_phase,
	vehicle_audio_frequency,
	vehicle_audio_gain,
	vehicle_audio_tire_phase_a,
	vehicle_audio_tire_phase_b,
	vehicle_audio_tire_frequency_a,
	vehicle_audio_tire_frequency_b,
	vehicle_audio_tire_gain,
	vehicle_audio_rough_phase,
	vehicle_audio_rough_gain: f32,
	vehicle_camera_reverse_blend:                                                                                                                                                                                                                                           f32,
	vehicle_camera_follow_distance:                                                                                                                                                                                                                                         f32,
	vehicle_impact_sound_cooldown:                                                                                                                                                                                                                                          f32,
	vehicle_skid_marks:                                                                                                                                                                                                                                                     [VEHICLE_SKID_CAPACITY]Vehicle_Skid_Mark,
	vehicle_skid_next:                                                                                                                                                                                                                                                      int,
	vehicle_skid_emit_distance:                                                                                                                                                                                                                                             f32,
	sounds:                                                                                                                                                                                                                                                                 [Sound_Cue][dynamic]f32,
	gui:                                                                                                                                                                                                                                                                    ui.Gui_Context,
	story_project:                                                                                                                                                                                                                                                          ^Story_Project,
	story_state:                                                                                                                                                                                                                                                            ^Story_State,
	compiled_story:                                                                                                                                                                                                                                                         ^Compiled_Story,
	story_runtime:                                                                                                                                                                                                                                                          ^Story_Runtime,
	mystery_state:                                                                                                                                                                                                                                                          ^Mystery_State,
	spatial_service:                                                                                                                                                                                                                                                        ^Story_Spatial_Service,
	screen:                                                                                                                                                                                                                                                                 Screen,
	phase:                                                                                                                                                                                                                                                                  Case_Phase,
	location,
	ap,
	selected_section,
	introduction_step:                                                                                                                                                                                                                      int,
	scene_transition_active:                                                                                                                                                                                                                                                bool,
	scene_transition_style:                                                                                                                                                                                                                                                 Scene_Transition_Style,
	scene_transition_elapsed:                                                                                                                                                                                                                                               f32,
	scene_transition_sequence:                                                                                                                                                                                                                                              int,
	scene_transition_target:                                                                                                                                                                                                                                                Screen,
	map_loading_active:                                                                                                                                                                                                                                                     bool,
	map_loading_target:                                                                                                                                                                                                                                                     Screen,
	map_loading_progress,
	map_loading_elapsed:                                                                                                                                                                                                                              f32,
	map_loading_stage:                                                                                                                                                                                                                                                      int,
	case_loading_active:                                                                                                                                                                                                                                                    bool,
	case_loading_index:                                                                                                                                                                                                                                                     int,
	case_loading_title:                                                                                                                                                                                                                                                     string,
	map_ready:                                                                                                                                                                                                                                                              [2]bool,
	run_seed:                                                                                                                                                                                                                                                               u64,
	game_over_reason:                                                                                                                                                                                                                                                       string,
	menu_return,
	pause_return:                                                                                                                                                                                                                                              Screen,
	pause_feedback:                                                                                                                                                                                                                                                         string,
	mute:                                                                                                                                                                                                                                                                   bool,
	aa_mode:                                                                                                                                                                                                                                                                Anti_Aliasing_Mode,
	lighting_quality:                                                                                                                                                                                                                                                       Lighting_Quality,
	guidance_mode:                                                                                                                                                                                                                                                          Guidance_Mode,
	aa_restart_required:                                                                                                                                                                                                                                                    bool,
	tutorial:                                                                                                                                                                                                                                                               Tutorial_Progress,
	focus_screen:                                                                                                                                                                                                                                                           Screen,
	focus_screen_initialized:                                                                                                                                                                                                                                               bool,
	notebook_return_focus,
	menu_detail_return_focus:                                                                                                                                                                                                                        ui.Gui_Id,
	menu_overlay_focus_pending:                                                                                                                                                                                                                                             bool,
	menu_overlay_pending_screen:                                                                                                                                                                                                                                            Screen,
	menu_overlay_pending_focus:                                                                                                                                                                                                                                             ui.Gui_Id,
	theory:                                                                                                                                                                                                                                                                 Theory,
	seed:                                                                                                                                                                                                                                                                   u64,
	persist_seed:                                                                                                                                                                                                                                                           bool,
	log:                                                                                                                                                                                                                                                                    [4]string,
	result:                                                                                                                                                                                                                                                                 Outcome,
	active_ending:                                                                                                                                                                                                                                                          int,
	board_sockets:                                                                                                                                                                                                                                                          [5][3]bool,
	board_clear_confirm:                                                                                                                                                                                                                                                    bool,
	board_inspect_socket,
	board_view:                                                                                                                                                                                                                                       int,
	board_last_section,
	board_last_socket:                                                                                                                                                                                                                                  int,
	board_snap_started:                                                                                                                                                                                                                                                     f32,
	board_feedback:                                                                                                                                                                                                                                                         string,
	recreate_section,
	recreate_runs:                                                                                                                                                                                                                                        int,
	recreate_started:                                                                                                                                                                                                                                                       f32,
	workbench_events:                                                                                                                                                                                                                                                       [9]Workbench_Event,
	workbench_event_count,
	workbench_selected:                                                                                                                                                                                                                              int,
	workbench_result:                                                                                                                                                                                                                                                       Reconstruction_Result,
	workbench_supported:                                                                                                                                                                                                                                                    [16]bool,
	workbench_field:                                                                                                                                                                                                                                                        int,
	workbench_feedback:                                                                                                                                                                                                                                                     string,
	workbench_test_current:                                                                                                                                                                                                                                                 bool,
	drag:                                                                                                                                                                                                                                                                   Drag_State,
	workbench_undo,
	workbench_redo:                                                                                                                                                                                                                                         [32]Workbench_Snapshot,
	workbench_undo_count,
	workbench_redo_count:                                                                                                                                                                                                                             int,
	question_selected,
	question_slot,
	knowledge_cursor,
	active_demonstration:                                                                                                                                                                                               int,
	interaction_step:                                                                                                                                                                                                                                                       int,
	interaction_active,
	interaction_mismatch:                                                                                                                                                                                                                               bool,
	question_feedback:                                                                                                                                                                                                                                                      string,
	pending_dialogue_approach:                                                                                                                                                                                                                                              int,
	dialogue_response:                                                                                                                                                                                                                                                      string,
	dialogue_text_started:                                                                                                                                                                                                                                                  f32,
	story_presentation:                                                                                                                                                                                                                                                     Story_Presentation_State,
	conversation_transcript:                                                                                                                                                                                                                                                [256]Dialogue_Transcript_Entry,
	conversation_transcript_count:                                                                                                                                                                                                                                          int,
	location_result:                                                                                                                                                                                                                                                        string,
	service_closet_entered,
	desk_key_found,
	desk_open:                                                                                                                                                                                                                      bool,
	memo_stub_found,
	burned_note_found,
	appointment_note_joined:                                                                                                                                                                                                            bool,
	overtime_clue_plus_one,
	overtime_lead_plus_one:                                                                                                                                                                                                                         int,
	pending_clue,
	case_sense_level:                                                                                                                                                                                                                                         int,
	case_sense_hold_started,
	case_sense_hint_until:                                                                                                                                                                                                                         f32,
	case_sense_hold_active:                                                                                                                                                                                                                                                 bool,
	check_preview,
	check_disposition_delta:                                                                                                                                                                                                                                 int,
	check_result:                                                                                                                                                                                                                                                           Check_Result,
	check_roll_started:                                                                                                                                                                                                                                                     f32,
	check_done,
	check_from_dialogue,
	check_result_cue_played:                                                                                                                                                                                                               bool,
	shutter_view,
	shutter_time:                                                                                                                                                                                                                                             int,
	shutter_open,
	shutter_operated,
	shutter_sightline_failed,
	shutter_thread_found,
	shutter_demonstrating:                                                                                                                                                                  bool,
	shutter_position,
	shutter_target:                                                                                                                                                                                                                                       f32,
	shutter_feedback:                                                                                                                                                                                                                                                       string,
	study_rug_lifted,
	study_statuette_held,
	study_wound_matched,
	study_seam_found,
	study_oil_found,
	cloth_acquired:                                                                                                                                                         bool,
	diagnostics:                                                                                                                                                                                                                                                            Theory_Diagnostics,
	timeline_order:                                                                                                                                                                                                                                                         [3]int,
	end_confirm,
	show_canonical,
	investigation_locked,
	threshold_four_spent,
	threshold_eight_spent:                                                                                                                                                                         bool,
	case_pacing_mask:                                                                                                                                                                                                                                                       u8,
	case_pacing_times:                                                                                                                                                                                                                                                      [6]f32,
	attribute_selected,
	notebook_tab,
	history_count,
	reveal_act,
	finale_demo_step:                                                                                                                                                                                          int,
	menu_detail_return,
	notebook_return:                                                                                                                                                                                                                                    Screen,
	history:                                                                                                                                                                                                                                                                [64]string,
	notebook_scroll,
	notebook_scroll_target,
	notebook_scroll_max:                                                                                                                                                                                                           f32,
	quest_observed:                                                                                                                                                                                                                                                         [64]Story_Objective_Status,
	quest_observed_count:                                                                                                                                                                                                                                                   int,
	quest_transition_ids:                                                                                                                                                                                                                                                   [dynamic]string,
	quest_transition_status:                                                                                                                                                                                                                                                [dynamic]Story_Objective_Status,
	quest_transition_started:                                                                                                                                                                                                                                               f32,
	quest_tracker_initialized:                                                                                                                                                                                                                                              bool,
	quest_completion_pending:                                                                                                                                                                                                                                               bool,
	quest_completion_started:                                                                                                                                                                                                                                               f32,
	player_x,
	player_y,
	player_angle,
	first_person_pitch:                                                                                                                                                                                                                   f32,
	player_elevation:                                                                                                                                                                                                                                                       f32,
	player_velocity_x,
	player_velocity_y:                                                                                                                                                                                                                                   f32,
	player_is_walking:                                                                                                                                                                                                                                                      bool,
	player_walk_speed:                                                                                                                                                                                                                                                      f32,
	camera_x,
	camera_y:                                                                                                                                                                                                                                                     f32,
	camera_initialized,
	top_down_camera,
	build_key_latch:                                                                                                                                                                                                                   bool,
	editor_mode:                                                                                                                                                                                                                                                            Editor_Mode,
	camera_orbit,
	camera_zoom:                                                                                                                                                                                                                                              f32,
	camera_orbit_initialized,
	first_person_camera:                                                                                                                                                                                                                          bool,
	camera_pose_override:                                                                                                                                                                                                                                                   bool,
	camera_eye_override,
	camera_target_override:                                                                                                                                                                                                                            Vec3,
	capture_hide_roofs:                                                                                                                                                                                                                                                     bool,
	catalog_bake_index:                                                                                                                                                                                                                                                     int,
	catalog_thumbnail_process:                                                                                                                                                                                                                                              os.Process,
	catalog_thumbnail_baking,
	catalog_thumbnail_autoload_attempted:                                                                                                                                                                                                         bool,
	catalog_thumbnail_status:                                                                                                                                                                                                                                               string,
	build_surface:                                                                                                                                                                                                                                                          Room_Surface,
	build_tool:                                                                                                                                                                                                                                                             Build_Tool,
	build_anchor:                                                                                                                                                                                                                                                           Vec2,
	build_has_anchor:                                                                                                                                                                                                                                                       bool,
	move_target_x,
	move_target_y:                                                                                                                                                                                                                                           f32,
	move_target_active:                                                                                                                                                                                                                                                     bool,
	nav_path:                                                                                                                                                                                                                                                               [256]Vec2,
	nav_path_count,
	nav_path_index:                                                                                                                                                                                                                                         int,
	environment_blend,
	cutaway_transition:                                                                                                                                                                                                                                  f32,
	capture_cutaway_override:                                                                                                                                                                                                                                               bool,
	capture_cutaway_amount:                                                                                                                                                                                                                                                 f32,
	wall_view:                                                                                                                                                                                                                                                              House_Wall_View,
	wall_cutaways:                                                                                                                                                                                                                                                          [HOUSE_WALL_SECTION_CAPACITY]f32,
	camera_reverse:                                                                                                                                                                                                                                                         bool,
	pending_world_interaction,
	pending_interactive:                                                                                                                                                                                                                         int,
	interactives:                                                                                                                                                                                                                                                           [64]Runtime_Interactive,
	interactive_count,
	hover_interactive,
	near_interactive,
	auto_door:                                                                                                                                                                                                      int,
	interaction_feedback:                                                                                                                                                                                                                                                   string,
	hover_entity,
	near_entity,
	dialogue_entity,
	dialogue_node,
	dialogue_ledger_scroll,
	dialogue_choice_page:                                                                                                                                                                int,
	context_ui:                                                                                                                                                                                                                                                             Context_State,
	dialogue_interaction:                                                                                                                                                                                                                                                   Dialogue_Interaction_State,
	city_x,
	city_y,
	city_angle:                                                                                                                                                                                                                                             f32,
	city_return_x,
	city_return_y,
	city_return_angle:                                                                                                                                                                                                                        f32,
	city_velocity_x,
	city_velocity_y,
	city_camera_x,
	city_camera_y:                                                                                                                                                                                                         f32,
	city_camera_initialized:                                                                                                                                                                                                                                                bool,
	near_landmark:                                                                                                                                                                                                                                                          int,
	vehicles:                                                                                                                                                                                                                                                               [dynamic]Vehicle_State,
	city_furniture:                                                                                                                                                                                                                                                         [dynamic]City_Furniture_State,
	driving_vehicle,
	near_vehicle:                                                                                                                                                                                                                                          int,
	vehicles_initialized,
	city_furniture_initialized:                                                                                                                                                                                                                       bool,
	animation_time:                                                                                                                                                                                                                                                         f32,
	player_animation:                                                                                                                                                                                                                                                       Character_Animation,
	character_animations:                                                                                                                                                                                                                                                   [4]Character_Animation,
}

catalog_thumbnail_start :: proc(g: ^Game, missing_only: bool) -> bool {
	if g.catalog_thumbnail_baking do return false
	command: [66]string; count := 0; command[count] = "./tools/bake_catalog_thumbnails.sh"; count += 1
	if missing_only {
		for entry in editor_catalog.entries {
			if entry.kind != .Object || !entry.valid || (!entry.thumbnail_missing && !entry.thumbnail_stale) || count >= len(command) do continue
			command[count] = entry.id; count += 1
		}
	} else {
		entry, found := catalog_object_entry(
			editor_state.catalog_id,
		); if !found || !entry.valid {g.catalog_thumbnail_status = "SELECT A VALID MODEL"; return false}
		command[count] = entry.id; count += 1
	}
	if count == 1 {g.catalog_thumbnail_status = "ALL PREVIEWS CURRENT"; return false}
	environment, _ := os.environ(
		context.temp_allocator,
	); process, err := os.process_start({working_dir = ".", command = command[:count], env = environment}); if err != nil {g.catalog_thumbnail_status = "THUMBNAIL RENDER FAILED"; return false}
	g.catalog_thumbnail_process =
		process; g.catalog_thumbnail_baking = true; g.catalog_thumbnail_status = missing_only ? fmt.tprintf("UPDATING %d PREVIEWS…", count - 1) : "RENDERING PREVIEW…"; return true
}

editor_update_catalog_ui :: proc(g: ^Game) {
	// Preview cards are a cache: populate missing or stale entries the first time
	// the object catalog is opened instead of requiring a separate bake step.
	if g.build_tool == .Plant && !g.catalog_thumbnail_autoload_attempted {
		g.catalog_thumbnail_autoload_attempted = true
		_ = catalog_thumbnail_start(g, true)
	}
	categories := [4]string {
		"all",
		g.build_tool == .Plant ? "objects" : "materials",
		"recent",
		"pinned",
	}
	for category, i in categories do if button(g, {86 + f32(i) * 65, 202, 60, 28}) {editor_state.catalog_category = category; editor_state.catalog_page = 0}
	if button(g, editor_catalog_search_rect()) do editor_state.search_active = true
	if button(g, editor_catalog_search_clear_rect()) do catalog_clear_search(&editor_state)
	catalog_clamp_page(
		&editor_state,
	); shown, matched := 0, 0; start := editor_state.catalog_page * 9
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry, &editor_state) do continue
		if matched >= start &&
		   shown <
			   9 {pin_clicked := button(g, editor_catalog_pin_rect(shown)); if pin_clicked {_ = catalog_toggle_pinned(&editor_state, entry.id); if editor_state.catalog_category == "pinned" do editor_state.catalog_page = 0} else if button(g, editor_catalog_card_rect(shown)) && catalog_entry_selectable(entry) {editor_state.catalog_id = entry.id; editor_state.paint_eyedropper = false; catalog_record_recent(&editor_state, entry.id); if entry.kind == .Object {g.build_tool = .Plant; editor_state.placement_rotation = 0; editor_state.placement_elevation = entry.default_elevation} else do g.build_tool = .Paint}; shown += 1}
		matched += 1
	}
	if matched == 0 && editor_state.search_count > 0 && button(g, editor_catalog_empty_action_rect()) do catalog_clear_search(&editor_state)
	pages := catalog_page_count(&editor_state); footer := editor_catalog_footer_y()
	if button(g, {86, footer, 38, 30}) && editor_state.catalog_page > 0 do editor_state.catalog_page -= 1
	if button(g, {308, footer, 38, 30}) && editor_state.catalog_page + 1 < pages do editor_state.catalog_page += 1
	if contains(Rect{74, 194, 284, editor_catalog_panel_bottom(g.build_tool) - 194}, g.input.mouse_pos) && g.input.mouse_wheel != 0 do editor_state.catalog_page = clamp(editor_state.catalog_page - editor_wheel_steps(g.input.mouse_wheel), 0, pages - 1)
	if g.build_tool == .Plant &&
	   !g.catalog_thumbnail_baking {actions_y := footer + 38; if button(g, {86, actions_y, 126, 30}) do _ = catalog_thumbnail_start(g, false); if button(g, {220, actions_y, 126, 30}) do _ = catalog_thumbnail_start(g, true)}
}
Editor_Playtest_Snapshot :: struct {
	active:             bool,
	document:           Level_Document,
	camera_x, camera_y: f32,
	top_down:           bool,
	selection:          [16]Editor_Selection,
	selection_count:    int,
	tool:               Build_Tool,
}
editor_playtest_snapshot: Editor_Playtest_Snapshot
Editor_Clipboard :: struct {
	active:          bool,
	document:        Level_Document,
	selection:       [16]Editor_Selection,
	selection_count: int,
}
editor_clipboard: Editor_Clipboard

WORKBENCH_ACTORS := [5]string{"someone", "edgar", "miriam", "daniel", "elsie"}
WORKBENCH_ACTIONS := [14]string {
	"move",
	"enter",
	"leave",
	"follow",
	"motive",
	"strike",
	"clean",
	"open_shutter",
	"close_shutter",
	"move_body",
	"stage",
	"lie",
	"deny",
	"observe",
}
WORKBENCH_PROPS := [9]string {
	"unknown object",
	"none",
	"statuette",
	"cloth_oil",
	"ledger",
	"cane",
	"body",
	"shutter_crank",
	"miriam",
}
WORKBENCH_ROOMS := [5]string{"unknown place", "dining_room", "hall", "study", "garden"}
OBSERVATION_TEXT := [12]string {
	"Diluted blood lies beneath the shifted study rug. A wrist-width scuff in the floor varnish holds tiny watch-glass fragments.",
	"The statuette base matches Edgar's wound profile.",
	"Blood remains trapped inside the statuette's base seam.",
	"Lamp oil residue coats the unnaturally clean bronze.",
	"The shutter automatically closes at 8:15.",
	"The shutter crank can only be reached from inside the study.",
	"Closed slats completely seal the study window from the dining room.",
	"Fresh wear on the crank shows the shutter was operated recently.",
	"Miriam's 8:20 fish course is untouched; her wine trails from a displaced chair.",
	"Daniel's 8:20 fish course is untouched; his napkin is missing and his chair displaced.",
	"Blood lies beneath Edgar's crushed watch crystal; a bronze fleck rests beside the hands stopped at 8:24.",
	"Edgar's cane lies beneath his left hand, though he was right-handed.",
}
