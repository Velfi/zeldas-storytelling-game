package main

import "core:fmt"
import "core:os"
import "core:time"

graph_completion_picker_create :: proc "odin" (
	field: Graph_Field,
	suggested_id: string,
	userdata: rawptr,
) -> (
	string,
	bool,
) {
	if field == .Condition do return suggested_id != "" ? suggested_id : "created_condition", true
	return "", false
}

graph_completion_history_destroy :: proc(history: ^Graph_History) {
	for i in 0 ..< history.undo_count do authoring_graph_document_destroy(&history.undo[i].document)
	for i in 0 ..< history.redo_count do authoring_graph_document_destroy(&history.redo[i].document)
	history^ = {}
}

graph_completion_edit :: proc(field: Graph_Field, value: string, node: int, choice := -1) -> bool {
	if choice >= 0 do graph_begin_choice_edit(field, "", node, choice)
	else do graph_begin_edit(field, "", node, graph_inspector_field_multiline(field))
	graph_edit_append(value)
	return graph_commit_edit()
}

graph_completion_field_fixture :: proc(field: Graph_Field) -> (string, string) {
	#partial switch field {
	case .Node_Id:
		return "line_edited", "line_edited"; case .Node_Scene:
		return "main", "main"; case .Node_Kind:
		return "line", "line"; case .Line_Id:
		return "line_control", "line_control"; case .Speaker:
		return "narrator", "narrator"; case .Text:
		return "Edited text", "Edited text"; case .Next:
		return "end", "end"; case .Success:
		return "end", "end"; case .Failure:
		return "end", "end"; case .Cancel:
		return "end", "end"; case .Subscene:
		return "sub", "sub"; case .UI:
		return "hidden", "hidden"; case .Camera:
		return "camera_fixture", "camera_fixture"; case .Actor:
		return "detective", "detective"; case .Actor_Mark:
		return "staging_fixture", "staging_fixture"; case .Animation:
		return "talk_fixture", "talk_fixture"; case .UI_Image_Asset:
		return "dialogue_portrait", "dialogue_portrait"; case .Sound_Cue_Asset:
		return "spoken_line", "spoken_line"; case .Animation_Asset:
		return "gesture_clip", "gesture_clip"; case .Summary:
		return "Edited summary", "Edited summary"; case .Ending:
		return "ending_fixture", "ending_fixture"; case .Domain_Ref:
		return "domain_fixture", "domain_fixture"; case .Event:
		return "event_fixture", "event_fixture"; case .Duration:
		return "2.500", "2.500"; case .Transition:
		return "0.750", "0.750"; case .Blocking:
		return "true", "true"; case .Condition:
		return "condition_fixture", "condition_fixture"; case .Effects:
		return "effect_a, effect_b", "effect_a, effect_b"; case .Condition_Root:
		return "4", "4"; case .First_Effect:
		return "5", "5"; case .Effect_Count:
		return "2", "2"; case .Interaction:
		return "interaction_fixture", "interaction_fixture"; case .Clue:
		return "clue_fixture", "clue_fixture"; case .Requires_Clues:
		return "clue_a, clue_b", "clue_a, clue_b"; case .Requires_Claims:
		return "claim_a, claim_b", "claim_a, claim_b"; case .Requires_Topics:
		return "topic_a, topic_b", "topic_a, topic_b"; case .Unlock_Clues:
		return "clue_c, clue_d", "clue_c, clue_d"; case .Unlock_Claims:
		return "claim_c, claim_d", "claim_c, claim_d"; case .Unlock_Topics:
		return "topic_c, topic_d", "topic_c, topic_d"
	}
	return "", ""
}

run_graph_completion_tests :: proc() {
	saved_document :=
		graph_document; saved_state := graph_state; saved_history := new(Graph_History); saved_history^ = graph_history; saved_source := graph_source_project; saved_autosave := graph_autosave_enabled; saved_level := level_document
	graph_document = {
		case_id     = "graph_completion",
		scene_count = 2,
		node_count  = 12,
		revision    = 1,
	}; graph_state = {
		active_scene  = 0,
		selected_node = 0,
		zoom          = 1,
	}; graph_history = {}; graph_autosave_enabled = false; graph_source_project = nil
	graph_document.scenes[0] = {
		scene = {
			id = "main",
			display_name = "Main",
			source = "detective",
			entry = "line",
			summary = "Complete field fixture",
			return_to = "investigation",
		},
		zoom = 1,
	}
	graph_document.scenes[1] = {
		scene = {id = "sub", display_name = "Sub", entry = "sub_end", return_to = "main"},
		zoom = 1,
	}
	kinds := [11]string {
		"line",
		"choice",
		"check",
		"stage",
		"interaction",
		"effect",
		"selector",
		"objective",
		"wait_event",
		"subscene",
		"end",
	}
	for kind, i in kinds {id := kind; graph_document.nodes[i] = {
			beat = {id = id, scene = "main", kind = kind, ui = "dialogue", transition = .18},
			position = {f32(i % 4) * 220, f32(i / 4) * 120},
		}}
	graph_document.nodes[0].beat = {
		id              = "line",
		scene           = "main",
		kind            = "line",
		line_id         = "line_001",
		speaker         = "detective",
		text            = "Every field",
		next            = "choice",
		ui              = "dialogue",
		camera          = "camera_a",
		actor           = "detective",
		actor_mark      = "stage_a",
		animation       = "talk",
		interaction     = "interaction_a",
		event_id        = "event_a",
		domain_ref      = "domain_a",
		condition_id    = "condition_a",
		clue            = "clue_a",
		summary         = "Summary",
		ending          = "ending_a",
		duration        = 1.25,
		transition      = .33,
		blocking        = true,
		condition_root  = 2,
		first_effect    = 3,
		effect_count    = 1,
		effect_ids      = make([]string, 1),
		requires_clues  = make([]string, 1),
		requires_claims = make([]string, 1),
		requires_topics = make([]string, 1),
		unlock_clues    = make([]string, 1),
		unlock_claims   = make([]string, 1),
		unlock_topics   = make([]string, 1),
	}
	line := &graph_document.nodes[0].beat; line.effect_ids[0] = "effect_a"; line.requires_clues[0] = "clue_a"; line.requires_claims[0] = "claim_a"; line.requires_topics[0] = "topic_a"; line.unlock_clues[0] = "clue_b"; line.unlock_claims[0] = "claim_b"; line.unlock_topics[0] = "topic_b"
	choice := &graph_document.nodes[1].beat; choice.choice_ids = make([]string, STORY_MAX_NODE_CHOICES); choice.choice_labels = make([]string, STORY_MAX_NODE_CHOICES); choice.choice_targets = make([]string, STORY_MAX_NODE_CHOICES); choice.choice_conditions = make([]string, STORY_MAX_NODE_CHOICES); for i in 0 ..< STORY_MAX_NODE_CHOICES {choice.choice_ids[i] = fmt.tprintf("choice_%d", i); choice.choice_labels[i] = fmt.tprintf("Choice %d", i); choice.choice_targets[i] = "end"; choice.choice_conditions[i] = "condition_a"}
	graph_document.nodes[2].beat.success = "end"; graph_document.nodes[2].beat.failure = "end"; graph_document.nodes[3].beat.duration = .5; graph_document.nodes[4].beat.success = "end"; graph_document.nodes[8].beat.event_id = "event_a"; graph_document.nodes[9].beat.subscene_id = "sub"; graph_document.nodes[10].beat.ui = "unchanged"; graph_document.nodes[10].beat.scene = "main"
	graph_document.nodes[10].beat.id = "end"; graph_document.nodes[10].beat.kind = "end"
	graph_document.nodes[9].beat.next = "end"
	graph_document.nodes[8].beat.next = "end"
	graph_document.nodes[7].beat.next = "end"
	graph_document.nodes[6].beat.next = "end"
	graph_document.nodes[5].beat.next = "end"
	graph_document.nodes[4].beat.cancel = "end"
	// The second scene needs an independently addressable end beat.
	graph_document.nodes[11] = {
		beat = {id = "sub_end", scene = "sub", kind = "end", ui = "unchanged"},
		position = {0, 0},
	}; graph_document.scenes[1].scene.entry = "sub_end"

	// Every supported kind and every universal inspector field is represented.
	for kind in Story_Node_Kind {text := story_node_kind_text(kind); found := false
		for node in graph_document.nodes[:graph_document.node_count] do if node.beat.kind == text do found = true
		assert(found)}
	assert(
		len(GRAPH_NODE_INSPECTOR_FIELDS) == 39,
	); for field in GRAPH_NODE_INSPECTOR_FIELDS {input, expected := graph_completion_field_fixture(field); assert(graph_completion_edit(field, input, 0)); assert(graph_inspector_field_value(&graph_document.nodes[0].beat, field) == expected)}
	// Scene controls use the same transactional field editor.
	scene_fields :=
		GRAPH_SCENE_INSPECTOR_FIELDS; scene_values := [5]string{"main_edited", "Main edited", "detective", "Scene summary edited", "investigation"}; for field, i in scene_fields {assert(graph_completion_edit(field, scene_values[i], -1)); assert(graph_scene_inspector_value(&graph_document.scenes[0].scene, field) == scene_values[i])}; assert(graph_completion_edit(.Scene_Id, "main", -1))
	assert(
		graph_completion_edit(.Choice_Label, "Renamed choice", 1, 0) &&
		choice.choice_labels[0] == "Renamed choice",
	); assert(graph_completion_edit(.Choice_Id, "stable_choice", 1, 0) && choice.choice_ids[0] == "stable_choice")
	// Every condition/effect control kind and each visible slot round-trips
	// through the same setter/getter pair used by the Graph definition panels.
	for kind in Story_Condition_Kind {text := story_condition_kind_text(kind)
		parsed, ok := story_condition_kind_from_text(text)
		assert(ok && parsed == kind)
		item := Story_Condition {
			kind = kind,
		}
		for slot in 0 ..< 5 {_, value, visible := graph_condition_slot(&item, slot); if visible {assert(graph_condition_set_slot(&item, slot, value)); _, after, still_visible := graph_condition_slot(&item, slot); assert(still_visible && after == value)}}}
	for kind in Story_Effect_Kind {text := story_effect_kind_text(kind)
		parsed, ok := story_effect_kind_from_text(text)
		assert(ok && parsed == kind)
		item := Story_Effect {
			kind = kind,
		}
		for slot in 0 ..< 5 {_, value, visible := graph_effect_slot(&item, slot); if visible {assert(graph_effect_set_slot(&item, slot, value)); _, after, still_visible := graph_effect_slot(&item, slot); assert(still_visible && after == value)}}}

	// Scene, node, and choice lifecycle mutations are atomic and undo restores
	// both the deleted record and every repaired inbound reference.
	graph_completion_history_destroy(
		&graph_history,
	); authoring_graph_document_destroy(&graph_document); graph_document = {
		case_id     = "graph_lifecycle",
		scene_count = 2,
		node_count  = 4,
	}; graph_state = {
		active_scene  = 0,
		selected_node = 0,
		zoom          = 1,
	}; graph_document.scenes[0] = {
		scene = {id = "main", entry = "line"},
		zoom = 1,
	}; graph_document.scenes[1] = {
		scene = {id = "sub", entry = "sub_end"},
		zoom = 1,
	}; graph_document.nodes[0] = {
		beat = {
			id = "line",
			scene = "main",
			kind = "line",
			line_id = "line_control",
			text = "Lifecycle",
			next = "end",
		},
	}; graph_document.nodes[1] = {
		beat = {id = "choice", scene = "main", kind = "choice"},
	}; graph_document.nodes[2] = {
		beat = {id = "end", scene = "main", kind = "end"},
	}; graph_document.nodes[3] = {
		beat = {id = "sub_end", scene = "sub", kind = "end"},
	}; lifecycle_choice := &graph_document.nodes[1].beat; lifecycle_choice.choice_ids = make([]string, STORY_MAX_NODE_CHOICES); lifecycle_choice.choice_labels = make([]string, STORY_MAX_NODE_CHOICES); lifecycle_choice.choice_targets = make([]string, STORY_MAX_NODE_CHOICES); lifecycle_choice.choice_conditions = make([]string, STORY_MAX_NODE_CHOICES); for i in 0 ..< STORY_MAX_NODE_CHOICES {lifecycle_choice.choice_ids[i] = fmt.tprintf("life_%d", i); lifecycle_choice.choice_labels[i] = fmt.tprintf("Life %d", i); lifecycle_choice.choice_targets[i] = "end"}
	graph_state.active_scene = 0; before_scenes := graph_document.scene_count; assert(graph_duplicate_scene() && graph_document.scene_count == before_scenes + 1); assert(graph_move_scene(-1)); assert(graph_delete_scene() && graph_document.scene_count == before_scenes); assert(graph_undo() && graph_document.scene_count == before_scenes + 1)
	graph_state.active_scene = graph_scene_index(
		"main",
	); target := graph_node_index("main", "end"); source := 0; assert(graph_state.active_scene >= 0 && target >= 0 && graph_document.nodes[source].beat.line_id == "line_control"); graph_document.nodes[source].beat.next = "end"; graph_select_only(target); before_nodes := graph_document.node_count; assert(graph_delete_selected() && graph_document.node_count == before_nodes - 1 && graph_document.nodes[source].beat.next == ""); assert(graph_undo() && graph_document.node_count == before_nodes && graph_document.nodes[source].beat.next == "end")
	choice_index := graph_node_index(
		"main",
		"choice",
	); before_choices := len(graph_document.nodes[choice_index].beat.choice_labels); assert(before_choices == STORY_MAX_NODE_CHOICES); assert(graph_choice_delete(choice_index, before_choices - 1) && len(graph_document.nodes[choice_index].beat.choice_labels) == before_choices - 1); assert(graph_choice_duplicate(choice_index, 0) && len(graph_document.nodes[choice_index].beat.choice_labels) == before_choices); assert(graph_choice_move(choice_index, 1, 1)); assert(graph_choice_delete(choice_index, 1) && len(graph_document.nodes[choice_index].beat.choice_labels) == before_choices - 1); assert(graph_undo() && len(graph_document.nodes[choice_index].beat.choice_labels) == before_choices)

	// Picker filtering, eight-row paging semantics, scope, and create-return.
	picker_story :=
		Story_Project{}; for i in 0 ..< 20 do append(&picker_story.entities, Story_Entity{id = fmt.tprintf("person_%02d", i), kind = "character", display_name = fmt.tprintf("Person %02d", i)}); picker_game := Game {
			story_project = &picker_story,
		}; graph_begin_picker(
		.Speaker,
		"",
		source,
	); assert(graph_picker_count(&picker_game, .Speaker) == 22); graph_edit_append("person_1"); assert(graph_picker_count(&picker_game, .Speaker) == 10 && graph_picker_candidate(&picker_game, .Speaker, 0) == "person_10" && graph_picker_candidate(&picker_game, .Speaker, 8) == "person_18"); graph_cancel_edit()
	level_document = {
			active_story = 0,
		}; append(
		&level_document.stories,
		Level_Story {
			id = "picker_floor",
			name = "Picker Floor",
			base_elevation = 0,
			wall_height = 3,
		},
		Level_Story {
			id = "picker_upper",
			name = "Picker Upper",
			base_elevation = 3,
			wall_height = 3,
		},
	); append(&level_document.markers, Level_Marker{id = "camera_here", kind = .Camera, story = 0}, Level_Marker{id = "camera_other", kind = .Camera, story = 1}); graph_begin_picker(.Camera, "", source); assert(graph_picker_count(&picker_game, .Camera) == 1 && graph_picker_candidate(&picker_game, .Camera, 0) == "camera_here"); graph_cancel_edit()
	graph_set_picker_create_callback(
		graph_completion_picker_create,
		nil,
	); graph_begin_picker(.Condition, "", source); assert(graph_picker_create(.Condition, "created_condition") && graph_document.nodes[source].beat.condition_id == "created_condition"); graph_set_picker_create_callback(nil, nil)
	// Exercise the production create-and-return bridge for every supported
	// picker family, including Story, Mystery, and qualified Build records.
	production_active := new(
		Story_Project,
	); production_active^ = active_story_project; production_workspace := new(Authoring_Workspace_State); production_workspace^ = authoring_workspace; active_story_project = {}; assert(load_story_project("assets/stories/mysteries/the_torn_appointment.story.toml", &active_story_project).ok); authoring_workspace = {
		tab = .Story_Data,
	}; graph_set_picker_create_callback(authoring_graph_picker_create, nil)
	production_fields := [7]Graph_Field {
		.Condition,
		.Effects,
		.Clue,
		.Camera,
		.Actor_Mark,
		.Interaction,
		.Event,
	}; production_ids := [7]string{"production_condition", "production_effect", "production_clue", "production_camera", "production_stage", "production_interaction", "production_event"}; for field, i in production_fields {if field == .Clue {created_id, created := authoring_graph_picker_create(field, production_ids[i], nil); assert(created && created_id == production_ids[i]); assert(graph_completion_edit(.Clue, created_id, source)); continue}; graph_begin_picker(field, "", source); created := graph_picker_create(field, production_ids[i]); if !created do fmt.println("PRODUCTION PICKER CREATE FAILED · ", field, " · ", production_ids[i]); assert(created)}
	assert(
		story_condition_index_in_document("production_condition") >= 0 &&
		story_effect_index_in_document("production_effect") >= 0,
	); production_payload := mystery_payload(&active_story_project); assert(production_payload != nil && mystery_clue_index(production_payload, "production_clue") >= 0); assert(level_marker_index(&level_document, "production_camera") >= 0 && level_marker_index(&level_document, "production_stage") >= 0 && level_marker_index(&level_document, "marker_production_interaction") >= 0 && level_marker_index(&level_document, "marker_production_event") >= 0)
	graph_set_picker_create_callback(
		nil,
		nil,
	); story_authoring_history_destroy(&authoring_workspace.story_history); mystery_authoring_history_destroy(&authoring_workspace.mystery_history); story_project_destroy(&active_story_project); active_story_project = production_active^; free(production_active); authoring_workspace = production_workspace^; free(production_workspace)
	delete(picker_story.entities)

	// Layout is authoring-only: moving/collapsing nodes changes layout bytes but
	// cannot change the playable Story serialization or its SHA-256 identity.
	source_story: Story_Project; assert(load_story_project(STORY_BLANK_PROOF_PATH, &source_story).ok); assert(len(source_story.nodes) > 0); source_story.nodes[0].ui_image_asset_ref = "lossless_portrait"; source_story.nodes[0].sound_cue_asset_ref = "lossless_voice"; source_story.nodes[0].animation_asset_ref = "lossless_gesture"; playable_before := story_project_serialize(&source_story); graph_import_story(&source_story); lossless_story: Story_Project; assert(graph_build_story_project(&source_story, &lossless_story).ok && story_project_serialize(&lossless_story) == playable_before); story_project_destroy(&lossless_story); path_a := "/private/tmp/chicago-graph-playable-before.toml"; path_b := "/private/tmp/chicago-graph-playable-after.toml"; assert(authoring_atomic_write(path_a, playable_before)); layout_before := graph_layout_serialize(); graph_document.nodes[0].position = {937, 421}; graph_document.nodes[0].collapsed = !graph_document.nodes[0].collapsed; layout_after := graph_layout_serialize(); assert(layout_before != layout_after); assert(authoring_atomic_write(path_b, story_project_serialize(&source_story))); hash_a, ok_a := project_asset_sha256_file(path_a); hash_b, ok_b := project_asset_sha256_file(path_b); assert(ok_a.ok && ok_b.ok && hash_a == hash_b); story_project_destroy(&source_story)

	// Measured worst-capacity interaction fixture. Keep the generous budget
	// stable across debug/CI machines while still catching accidental stalls.
	graph_configure_minimap_stress_board(

	); assert(graph_document.node_count == GRAPH_MAX_NODES); graph_state.search_query = "node 255"; started := time.tick_now(); for _ in 0 ..< 20 {layout := graph_minimap_layout(); assert(layout.valid && layout.scale > 0); assert(graph_frame_nodes(false)); assert(graph_focus_search_result(1) && graph_state.selected_node == 255 && graph_state.selection_count == 1)}; elapsed := time.duration_seconds(time.tick_diff(started, time.tick_now())); assert(elapsed < 1.0)
	// Picker and quick-add navigation consume the shared up/down/activate input,
	// which is populated identically by keyboard and controller bindings.
	keyboard :=
		Game{}; keyboard.active_device = .Keyboard_Mouse; keyboard.input.down = true; controller := Game{}; controller.active_device = .Gamepad; controller.input.down = true; keyboard_selected := graph_picker_navigation_step(7, 22, keyboard.input.up, keyboard.input.down); controller_selected := graph_picker_navigation_step(7, 22, controller.input.up, controller.input.down); assert(keyboard_selected == 8 && controller_selected == keyboard_selected); keyboard.input.activate = true; controller.input.activate = true; assert(keyboard.input.activate == controller.input.activate)

	authoring_graph_document_destroy(
		&graph_document,
	); graph_completion_history_destroy(&graph_history); authoring_level_document_destroy(&level_document); graph_document = saved_document; graph_state = saved_state; graph_history = saved_history^; free(saved_history); graph_source_project = saved_source; graph_autosave_enabled = saved_autosave; level_document = saved_level
}
