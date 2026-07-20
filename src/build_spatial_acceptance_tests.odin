package main

import "core:os"

run_build_spatial_acceptance_tests :: proc() {
	ensure_test_torn_story(); graph_import_story(&test_story_project)
	doc: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &doc).ok)
	defer authoring_level_document_destroy(&doc)

	// Every interaction field survives the same LevelFormat representation
	// consumed by runtime playtest.
	opening_index := level_opening_index(&doc, "door_front"); assert(opening_index >= 0)
	append(
		&graph_document.conditions,
		Story_Condition{id = "build_condition", kind = .Always},
	); graph_document.condition_count = len(graph_document.conditions); append(&graph_document.effects, Story_Effect{id = "build_effect", kind = .Spatial_Command, spatial_command = .Set_Interaction, spatial_target = {doc.id, "door_front"}, world_enabled = true}); graph_document.effect_count = len(graph_document.effects)
	interaction := Level_Command {
		kind               = .Set_Interaction,
		entity_id          = "door_front",
		interaction        = .Door,
		interaction_prompt = "ENTER THE AUTHORED ROOM",
		condition_id       = "build_condition",
		focused_scene      = test_story_project.scenes[0].id,
		interaction_range  = 2.75,
		initially_active   = true,
		locked             = true,
		powered            = false,
		effect_id_count    = 1,
	}; interaction.effect_ids[0] = "build_effect"
	level_history = {}; assert(level_commit_transaction(&doc, interaction, "complete interaction"))
	text := level_serialize(
		&doc,
	); roundtrip_path := "/private/tmp/chicago-build-spatial-roundtrip.toml"; assert(os.write_entire_file(roundtrip_path, transmute([]byte)text) == nil)
	roundtrip: Level_Document; assert(level_load(roundtrip_path, &roundtrip).ok); defer authoring_level_document_destroy(&roundtrip); loaded := roundtrip.openings[level_opening_index(&roundtrip, "door_front")]; assert(loaded.interaction == .Door && loaded.interaction_prompt == interaction.interaction_prompt && loaded.condition_id == interaction.condition_id && loaded.focused_scene == interaction.focused_scene && loaded.effect_id_count == 1 && loaded.effect_ids[0] == interaction.effect_ids[0] && loaded.interaction_range == 2.75 && loaded.initially_active && loaded.locked && !loaded.powered)
	level_document = level_clone_document(
		&roundtrip,
	); defer authoring_level_document_destroy(&level_document); runtime_game := Game{}; runtime_interactives_rebuild(&runtime_game); runtime_index := runtime_interactive_index(&runtime_game, "door_front"); assert(runtime_index >= 0); runtime_item := runtime_game.interactives[runtime_index]; assert(runtime_item.prompt == interaction.interaction_prompt && runtime_item.condition_id == interaction.condition_id && runtime_item.focused_scene == interaction.focused_scene && runtime_item.effect_id_count == 1 && runtime_item.effect_ids[0] == interaction.effect_ids[0] && runtime_item.interaction_range == 2.75 && runtime_item.active && runtime_item.locked && !runtime_item.powered)

	// Default pickers remain scoped to one story; an explicit request is needed
	// to expose qualified records from another floor.
	append(
		&doc.stories,
		Level_Story {
			id = "acceptance_upper",
			name = "Acceptance Upper",
			base_elevation = 3,
			wall_height = 3,
		},
	); append(&doc.markers, Level_Marker{id = "upper_camera", kind = .Camera, story = len(doc.stories) - 1, position = {2, 2}, camera_height = 2})
	candidates: [256]Story_Spatial_Id; local_count := level_marker_candidates(&doc, 0, .Camera, false, &candidates); for candidate in candidates[:local_count] do assert(candidate.target_id != "upper_camera"); qualified_count := level_marker_candidates(&doc, 0, .Camera, true, &candidates); found_upper := false; for candidate in candidates[:qualified_count] do if candidate.target_id == "upper_camera" {found_upper = true; assert(candidate.space_id == doc.id)}; assert(found_upper)

	// Character placement is a single handoff: StoryCore identity and the typed
	// Build marker are either both created or neither is.
	project :=
		Story_Project{}; defer story_project_destroy(&project); assert(level_character_create_and_place(&doc, &project, "witness_build", "Build Witness", 0, {4, 4})); entity_index := story_entity_index(&project, "witness_build"); marker_index := level_marker_index(&doc, "spawn_witness_build"); assert(entity_index >= 0 && marker_index >= 0 && project.entities[entity_index].spatial.space_id == doc.id && project.entities[entity_index].spatial.target_id == doc.markers[marker_index].id && doc.markers[marker_index].reference == "witness_build" && !level_character_create_and_place(&doc, &project, "witness_build", "Duplicate", 0, {5, 5}))

	// Build records hand off directly to their authored Graph or Mystery record.
	handoff_game :=
		Game{}; assert(graph_document.node_count > 0); old_camera := graph_document.nodes[0].beat.camera; graph_document.nodes[0].beat.camera = "handoff_camera"; graph_marker := Level_Marker {
			id   = "handoff_camera",
			kind = .Camera,
		}; assert(
		editor_open_marker_in_graph(&handoff_game, graph_marker) &&
		handoff_game.editor_mode == .Graph &&
		graph_state.selected_node == 0,
	); graph_document.nodes[0].beat.camera = old_camera
	old_active :=
		active_story_project; active_story_project = test_story_project; payload := mystery_payload(&active_story_project); assert(payload != nil && len(payload.clues) > 0); mystery_marker := Level_Marker {
			id        = "handoff_clue",
			kind      = .Clue,
			reference = payload.clues[0].id,
		}; assert(
		editor_open_marker_in_mystery(&handoff_game, mystery_marker) &&
		handoff_game.screen == .Authoring &&
		authoring_workspace.tab == .Mystery &&
		authoring_workspace.selected_category == int(Mystery_Authoring_Record_Kind.Clue) &&
		authoring_mystery_id(.Clue, authoring_workspace.selected_record) == payload.clues[0].id,
	); active_story_project = old_active

	// Reference previews include cross-domain bindings and block deletion. Rename
	// and repair update every qualified StoryCore reference atomically.
	project.entities[entity_index].spatial.target_id = "spawn_player"; preview := level_reference_preview(&doc, &project, "spawn_player"); assert(preview.count > 0); _, removed := level_reference_remove(&doc, &project, "spawn_player"); assert(!removed); assert(level_reference_rename(&doc, &project, "spawn_player", "spawn_player_renamed") && project.entities[entity_index].spatial.target_id == "spawn_player_renamed"); project.entities[entity_index].spatial.target_id = "missing_spawn"; assert(level_reference_repair(&doc, &project, "missing_spawn", "spawn_player_renamed") && project.entities[entity_index].spatial.target_id == "spawn_player_renamed")
	// Graph and Mystery references independently participate in the same
	// preview/block/atomic-repair contract, not only StoryCore spatial bindings.
	append(
		&doc.markers,
		Level_Marker{id = "graph_repair_marker", kind = .Camera, story = 0, position = {3, 3}},
	); graph_camera_before := graph_document.nodes[0].beat.camera; graph_document.nodes[0].beat.camera = "graph_repair_marker"; graph_preview := level_reference_preview(&doc, nil, "graph_repair_marker"); graph_found := false; for item in graph_preview.items[:graph_preview.count] do if item.kind == "graph_node" && item.field == "camera" do graph_found = true; assert(graph_found); _, graph_removed := level_reference_remove(&doc, nil, "graph_repair_marker"); assert(!graph_removed); assert(level_reference_rename(&doc, nil, "graph_repair_marker", "graph_repair_marker_renamed") && graph_document.nodes[0].beat.camera == "graph_repair_marker_renamed"); graph_document.nodes[0].beat.camera = graph_camera_before
	mystery_refs := story_project_clone(
		&test_story_project,
	); mystery_refs_payload := mystery_payload(&mystery_refs); assert(mystery_refs_payload != nil && len(mystery_refs_payload.city_labels) > 0); append(&doc.markers, Level_Marker{id = "mystery_repair_marker", kind = .Player_Spawn, story = 0, position = {4, 3}}); mystery_refs_payload.city_labels[0].level_spawn = "mystery_repair_marker"; mystery_preview := level_reference_preview(&doc, &mystery_refs, "mystery_repair_marker"); mystery_found := false; for item in mystery_preview.items[:mystery_preview.count] do if item.kind == "city_label" && item.field == "level_spawn" do mystery_found = true; assert(mystery_found); _, mystery_removed := level_reference_remove(&doc, &mystery_refs, "mystery_repair_marker"); assert(!mystery_removed); assert(level_reference_rename(&doc, &mystery_refs, "mystery_repair_marker", "mystery_repair_marker_renamed") && mystery_refs_payload.city_labels[0].level_spawn == "mystery_repair_marker_renamed"); story_project_destroy(&mystery_refs)

	// Multiple case labels require distinct reserved city sites and exact local
	// player-spawn bindings.
	assert(
		len(CITY_CASE_LOCATION_SITES) > 0,
	); destinations := [1]Level_City_Destination{{"build_destination", "BUILD DESTINATION", CITY_CASE_LOCATION_SITES[0].id, "spawn_player_renamed"}}; assert(level_city_destinations_validate(&doc, destinations[:]).ok); duplicate := [2]Level_City_Destination{destinations[0], {"other_destination", "OTHER", CITY_CASE_LOCATION_SITES[0].id, "spawn_player_renamed"}}; assert(!level_city_destinations_validate(&doc, duplicate[:]).ok)

	// Templates and both prefab families preserve authored spatial content while
	// assigning new stable IDs in the destination document.
	template_action_doc := level_clone_document(
		&doc,
	); template_story_count := len(template_action_doc.stories); assert(level_reuse_action(&template_action_doc, .Create_Level_From_Template, "", "instantiated_level", "Instantiated Level", {}) && template_action_doc.id == "instantiated_level" && template_action_doc.name == "Instantiated Level" && len(template_action_doc.stories) == template_story_count); authoring_level_document_destroy(&template_action_doc)
	room_count := len(
		doc.rooms,
	); assert(level_reuse_action(&doc, .Instantiate_Room_Prefab, doc.rooms[0].id, "room_prefab_copy", "Room Prefab", {.5, .5}) && len(doc.rooms) == room_count + 1)
	object_count := len(
		doc.objects,
	); assert(level_reuse_action(&doc, .Instantiate_Prop_Prefab, doc.objects[0].id, "prop_prefab_copy", "Prop Prefab", {6, 6}) && len(doc.objects) == object_count + 1)
}
