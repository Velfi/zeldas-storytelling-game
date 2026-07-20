package main

import "core:strings"

run_build_validation_closure_tests :: proc() {
	// Spatial fixtures cover obstruction, containment, transition resolution,
	// camera framing, typed scope, reachability/visibility, and identical local
	// IDs in independently qualified spaces.
	a := Level_Document {
		version     = LEVEL_FORMAT_VERSION,
		id          = "space_a",
		name        = "A",
		width       = 20,
		height      = 20,
		story_limit = 2,
	}; append(
		&a.stories,
		Level_Story{"ground", "Ground", 0, 3},
		Level_Story{"upper", "Upper", 3, 3},
	)
	room_points := make(
		[dynamic]Vec2,
		0,
		4,
	); append(&room_points, Vec2{0, 0}, Vec2{10, 0}, Vec2{10, 10}, Vec2{0, 10}); append(&a.rooms, Level_Room{id = "room", story = 0, points = room_points})
	append(
		&a.objects,
		Level_Object{id = "blocker", catalog_id = "core:blocker", story = 0, position = {2, 2}},
		Level_Object{id = "support", catalog_id = "core:support", story = 0, position = {3, 3}},
		Level_Object {
			id = "contained_far",
			catalog_id = "core:item",
			support_id = "support",
			story = 0,
			position = {9, 9},
		},
		Level_Object {
			id = "active_obstructed",
			catalog_id = "core:button",
			interaction = .Toggle,
			initially_active = true,
			interaction_range = 1,
			story = 0,
			position = {2.1, 2},
		},
	)
	append(
		&a.markers,
		Level_Marker {
			id = "spawn",
			kind = .Player_Spawn,
			story = 0,
			position = {2, 2},
			radius = .5,
		},
		Level_Marker {
			id = "camera",
			kind = .Camera,
			story = 0,
			position = {5, 5},
			radius = 1,
			camera_height = 2,
		},
		Level_Marker {
			id = "bad_local",
			kind = .Transition,
			story = 0,
			position = {6, 6},
			destination = "space_a:missing",
		},
		Level_Marker {
			id = "to_b",
			kind = .Transition,
			story = 0,
			position = {7, 7},
			destination = "space_b:arrival",
		},
		Level_Marker {
			id = "scoped_lower",
			kind = .Character_Spawn,
			story = 0,
			position = {1, 1},
			reference = "missing_actor",
		},
		Level_Marker {
			id = "scoped_upper",
			kind = .Character_Spawn,
			story = 1,
			position = {1, 1},
			reference = "missing_actor",
		},
	)
	b := Level_Document {
		version     = LEVEL_FORMAT_VERSION,
		id          = "space_b",
		name        = "B",
		width       = 20,
		height      = 20,
		story_limit = 1,
	}; append(
		&b.stories,
		Level_Story{"ground", "Ground", 0, 3},
	); append(&b.markers, Level_Marker{id = "arrival", kind = .Transition, story = 0, position = {1, 1}, destination = "space_a:to_b"}, Level_Marker{id = "same_local_id", kind = .Staging, story = 0, position = {19, 19}}); append(&a.markers, Level_Marker{id = "same_local_id", kind = .Staging, story = 1, position = {19, 19}})
	levels := [2]^Level_Document {
		&a,
		&b,
	}; issues := authoring_spatial_validate_levels(levels[:], &active_story_project); defer delete(issues)
	found_spawn, found_containment, found_transition, found_camera, found_scope :=
		false, false, false, false, false
	for issue in issues {assert(issue.location.present && issue.field_path != "")
		if issue.entity_id == "spawn" && issue.field_path == "position" do found_spawn = true
		if issue.entity_id == "contained_far" && issue.field_path == "support_id" do found_containment = true
		if issue.entity_id == "bad_local" && issue.field_path == "destination" do found_transition = true
		if issue.entity_id == "camera" do found_camera = true
		if issue.entity_id == "scoped_upper" && issue.field_path == "reference" do found_scope = true
		if issue.entity_id == "to_b" do assert(!strings.contains(issue.message, "does not resolve"))
		if issue.entity_id == "same_local_id" do assert(!strings.contains(issue.message, "duplicated"))}; assert(found_spawn && found_containment && found_transition && found_camera && found_scope)
	registry: Story_Spatial_Registry; assert(story_spatial_registry_register(&registry, story_level_space(&a)) && story_spatial_registry_register(&registry, story_level_space(&b))); service := story_spatial_registry_service(&registry); visible := story_spatial_query(&service, {.Visible, {"space_a", "support"}, {"space_a", "room"}}); reachable := story_spatial_query(&service, {.Reachable, {"space_a", "support"}, {"space_b", "arrival"}}); isolated := story_spatial_query(&service, {.Distance, {"space_a", "same_local_id"}, {"space_b", "same_local_id"}}); assert(visible.status == .Available && visible.boolean_value && reachable.status == .Available && reachable.boolean_value && isolated.status == .Unavailable); story_spatial_registry_destroy(&registry)
	authoring_level_document_destroy(&a); authoring_level_document_destroy(&b)

	// Navigation focuses both the entity and its field rather than merely
	// switching tabs.
	navigation_level: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &navigation_level).ok); saved_level := level_document; level_document = navigation_level; game := Game{}; marker := level_document.markers[0]; diagnostic := authoring_diagnostic_init(.Level, "level", marker.id, "radius", .Blocking, "unsafe spawn"); authoring_diagnostic_set_location(&diagnostic, level_document.id, marker.story, marker.position); dispatch := authoring_navigation_dispatch(diagnostic, &game); assert(dispatch.applied && editor_state.selection_count == 1 && editor_state.selection[0].entity_id == marker.id && authoring_navigation_focused_field == "radius" && game.camera_x == marker.position.x && game.camera_y == marker.position.y); authoring_level_document_destroy(&level_document); level_document = saved_level
	if len(active_story_project.scenes) >
	   0 {story_issue := authoring_diagnostic_init(.Story_Core, "story", active_story_project.scenes[0].id, "entry_node", .Blocking, "blocking story probe"); story_dispatch := authoring_navigation_dispatch(story_issue, &game); assert(story_dispatch.applied && authoring_workspace.tab == .Story_Data && authoring_navigation_focused_field == "entry_node")}
	navigation_graph := authoring_graph_from_story(
		&active_story_project,
	); saved_graph := graph_document; graph_document = navigation_graph; if graph_document.node_count > 0 {graph_issue := authoring_diagnostic_init(.Graph, "graph", graph_document.nodes[0].beat.id, "next", .Blocking, "blocking graph probe"); graph_dispatch := authoring_navigation_dispatch(graph_issue, &game); assert(graph_dispatch.applied && game.editor_mode == .Graph && graph_state.selected_node == 0 && authoring_navigation_focused_field == "next")}; authoring_graph_document_destroy(&graph_document); graph_document = saved_graph
	payload := mystery_payload(
		&active_story_project,
	); if payload != nil && len(payload.clues) > 0 {clue := payload.clues[0]; mystery_issue := authoring_diagnostic_init(.Mystery, "mystery", clue.id, "description", .Blocking, "missing clue description"); mystery_dispatch := authoring_navigation_dispatch(mystery_issue, &game); field, _, _ := authoring_mystery_scalar_field(.Clue, authoring_mystery_field_cursor); assert(mystery_dispatch.applied && authoring_workspace.tab == .Mystery && authoring_workspace.selected_category == int(Mystery_Authoring_Record_Kind.Clue) && authoring_mystery_id(.Clue, authoring_workspace.selected_record) == clue.id && field == "description")}
	if len(campaign_document.cases) >
	   0 {case_id := campaign_document.cases[0].id; campaign_issue := authoring_diagnostic_init(.Campaign, "campaign", case_id, "condition_root", .Blocking, "broken campaign condition"); campaign_dispatch := authoring_navigation_dispatch(campaign_issue, &game); assert(campaign_dispatch.applied && game.screen == .Campaign_Action && campaign_workspace.tab == .Conditions && campaign_workspace.draft.cases[campaign_workspace.selected_case].id == case_id)}
	asset_index := len(
		authoring_workspace.assets.assets,
	); append(&authoring_workspace.assets.assets, Project_Asset_Record{id = "navigation_asset"}); asset_issue := authoring_diagnostic_init(.Assets, "assets", "navigation_asset", "provenance.license_id", .Blocking, "missing license"); asset_dispatch := authoring_navigation_dispatch(asset_issue, &game); assert(asset_dispatch.applied && authoring_workspace.tab == .Assets && authoring_workspace.selected_asset == asset_index && authoring_navigation_focused_field == "provenance.license_id"); ordered_remove(&authoring_workspace.assets.assets, asset_index)
	package_issue := authoring_diagnostic_init(
		.Packaging,
		"package",
		"artifact",
		"destination",
		.Blocking,
		"destination required",
	); assert(authoring_navigation_dispatch(package_issue, &game).applied && authoring_workspace.tab == .Packages && authoring_navigation_focused_field == "destination"); compatibility_issue := authoring_diagnostic_init(.Compatibility, "package", "artifact", "capabilities", .Blocking, "unsupported capability"); assert(authoring_navigation_dispatch(compatibility_issue, &game).applied && authoring_workspace.tab == .Library && authoring_navigation_focused_field == "capabilities")

	// Every mutable subsystem captured by whole-project playtest is restored:
	// StoryCore source, runtime state, graph layout, level, campaign definition,
	// and campaign/player progress.
	scenario: Scenario_Context; assert(scenario_context_init("assets/stories/mysteries/the_torn_appointment.story.toml", "assets/levels/vale_house.toml", &scenario).ok); defer scenario_context_destroy(&scenario)
	story := story_project_clone(
		&scenario.compiled.runtime,
	); defer story_project_destroy(&story); graph := authoring_graph_from_story(&story); defer authoring_graph_document_destroy(&graph); level: Level_Document; assert(level_load("assets/levels/vale_house.toml", &level).ok); defer authoring_level_document_destroy(&level)
	campaign := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "restore",
		title           = "Original",
		content_version = "1",
	}; defer campaign_destroy(
		&campaign,
	); append(&campaign.cases, Campaign_Case{id = "case", title = "Case", story_path = "case/story.toml", case_content_version = "1", required = true, condition_root = -1}); playthrough := Campaign_Playthrough {
		campaign_id              = "restore",
		campaign_content_version = "1",
		active_case              = -1,
	}
	state := new(
		Authoring_Playtest_Coordinator,
	); defer free(state); state.active = true; state.snapshot = authoring_playtest_snapshot_create(&story, &scenario.runtime, &level, &graph, &campaign, &playthrough, {})
	original_story_title :=
		story.title; original_level_revision := level.revision; original_graph_position := graph.nodes[0].position; original_runtime_scene := scenario.runtime.current_scene
	story.title = "MUTATED"; story.revision += 1; level.revision += 10; level.markers[0].position = {19, 19}; graph.nodes[0].position = {999, 999}; campaign.title = "MUTATED"; playthrough.active_case = 0; scenario.runtime.current_scene = "mutated"
	restored := authoring_playtest_end(
		state,
		&story,
		&scenario.runtime,
		&graph,
		&level,
		&campaign,
		&playthrough,
	); assert(restored.ok && !state.active && story.title == original_story_title && level.revision == original_level_revision && graph.nodes[0].position == original_graph_position && campaign.title == "Original" && playthrough.active_case == -1 && scenario.runtime.current_scene == original_runtime_scene)

	unsafe := story_project_clone(
		&story,
	); assert(len(unsafe.nodes) > 0); original_ui := unsafe.nodes[0].ui; unsafe.nodes[0].ui = "creator-only solution key"; audit := authoring_player_safe_audit(&unsafe, nil, 1); found_leak := false; for issue in audit.diagnostics do if issue.entity_id == unsafe.nodes[0].id && issue.field_path == "ui" do found_leak = true; assert(found_leak && authoring_validation_is_blocked(&audit)); authoring_validation_snapshot_destroy(&audit); unsafe.nodes[0].ui = original_ui; audit = authoring_player_safe_audit(&unsafe, nil, 2); for issue in audit.diagnostics do assert(!(issue.entity_id == unsafe.nodes[0].id && strings.contains(issue.message, "creator-only solution"))); authoring_validation_snapshot_destroy(&audit); story_project_destroy(&unsafe)

	// Editing invalidates only the edited domain and declared dependents.
	saved_validation :=
		authoring_workspace.production_validation; authoring_workspace.production_validation = authoring_validation_snapshot_init(.Playable, 1); for domain in Authoring_Validation_Domain {assert(authoring_validation_touch_domain(&authoring_workspace.production_validation, domain, 1)); assert(authoring_validation_mark_domain_valid(&authoring_workspace.production_validation, domain, 1))}; plan := authoring_invalidate_after_edit(.Level, 2); assert(plan.count == 4 && !authoring_validation_domain_fresh(&authoring_workspace.production_validation, .Level) && !authoring_validation_domain_fresh(&authoring_workspace.production_validation, .Story_Core) && !authoring_validation_domain_fresh(&authoring_workspace.production_validation, .Mystery) && !authoring_validation_domain_fresh(&authoring_workspace.production_validation, .Packaging) && authoring_validation_domain_fresh(&authoring_workspace.production_validation, .Graph)); authoring_validation_snapshot_destroy(&authoring_workspace.production_validation); authoring_workspace.production_validation = saved_validation
}
