package main

import "core:fmt"
import "core:os"
import "core:strings"

authoring_workspace_validation_profile :: proc(
) -> Authoring_Validation_Profile {return Authoring_Validation_Profile(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Authoring_Validation_Profile.Player_Safe),
		),
	)}
authoring_workspace_recheck :: proc() {story_validation_destroy(&authoring_workspace.diagnostics)
	authoring_workspace.diagnostics = story_project_validate(&active_story_project)
	authoring_validation_snapshot_destroy(&authoring_workspace.production_validation)
	authoring_workspace.production_validation = authoring_production_validate(
		authoring_workspace_validation_profile(),
		&active_story_project,
		&graph_document,
		&level_document,
		&campaign_document,
		&authoring_workspace.assets,
		&authoring_workspace.inspection,
	)
	authoring_workspace.feedback =
		!authoring_validation_is_blocked(&authoring_workspace.production_validation) ? "VALIDATION PASSED" : "VALIDATION FOUND BLOCKING ISSUES"}

authoring_workspace_diagnostic_filter_ensure :: proc(
) {if !authoring_workspace.diagnostic_filter_ready {authoring_workspace.diagnostic_filter =
			authoring_diagnostic_filter_all()
		authoring_workspace.diagnostic_filter_ready = true}}
authoring_workspace_diagnostic_stale_count :: proc() -> int {count := 0; revisions :=
		authoring_production_revisions(
			&active_story_project,
			&graph_document,
			&level_document,
			&campaign_document,
			&authoring_workspace.assets,
		)
	for 	domain in Authoring_Validation_Domain {index := authoring_validation_domain_index(
			&authoring_workspace.production_validation,
			domain,
		)
		if index < 0 || !authoring_validation_domain_fresh(&authoring_workspace.production_validation, domain) || authoring_workspace.production_validation.domains[index].source_revision != revisions[domain] do count += 1}
	return count}
authoring_workspace_diagnostic_indices :: proc(
) -> [dynamic]int {authoring_workspace_diagnostic_filter_ensure()
	return authoring_validation_filtered_indices(
		&authoring_workspace.production_validation,
		&authoring_workspace.diagnostic_filter,
	)}

authoring_workspace_creator_add :: proc(category: int) -> string {
	setup := &authoring_workspace.creator_setup; payload := mystery_payload(&active_story_project)
	switch category {
	case 0:
		if len(active_story_project.variables) == 0 do return "NO STORY VARIABLES"
		item :=
			active_story_project.variables[authoring_workspace.creator_cursor % len(active_story_project.variables)]
		for &existing in setup.variables do if existing.id == item.id {switch existing.value.kind {case .Boolean:
				existing.value.boolean_value = !existing.value.boolean_value; case .Integer:
				existing.value.integer_value += 1; case .Enumeration, .Entity:
				existing.value.text_value = "creator_override"}; return "STORY VARIABLE OVERRIDE CHANGED"}
		append(&setup.variables, Authoring_Creator_Variable{item.id, item.default_value})
		return "STORY VARIABLE OVERRIDE ADDED"
	case 1:
		if payload == nil do return "NO MYSTERY KNOWLEDGE"
		total := len(payload.clues) + len(payload.claims) + len(payload.dialogue)
		if total == 0 do return "NO CLUES, CLAIMS, OR TOPICS"
		cursor := authoring_workspace.creator_cursor % total
		if cursor < len(payload.clues) do append(&setup.knowledge, Authoring_Creator_Knowledge{.Clue, payload.clues[cursor].id, true})
		else if cursor < len(payload.clues) + len(payload.claims) do append(&setup.knowledge, Authoring_Creator_Knowledge{.Claim, payload.claims[cursor - len(payload.clues)].id, true})
		else do append(&setup.knowledge, Authoring_Creator_Knowledge{.Topic, payload.dialogue[cursor - len(payload.clues) - len(payload.claims)].interaction, true})
		return "KNOWLEDGE OVERRIDE ADDED"
	case 2:
		if len(active_story_project.objectives) == 0 do return "NO OBJECTIVES"
		item :=
			active_story_project.objectives[authoring_workspace.creator_cursor % len(active_story_project.objectives)]
		for &existing in setup.objectives do if existing.id == item.id {existing.status = Story_Objective_Status((int(existing.status) + 1) % len(Story_Objective_Status)); existing.stage += 1; return "OBJECTIVE STATUS / STAGE CHANGED"}
		append(&setup.objectives, Authoring_Creator_Objective{item.id, .Active, 0})
		return "OBJECTIVE OVERRIDE ADDED"
	case 3:
		if len(active_story_project.events) == 0 do return "NO EVENTS"
		append(
			&setup.events,
			active_story_project.events[authoring_workspace.creator_cursor % len(active_story_project.events)].id,
		)
		return "EMITTED EVENT OVERRIDE ADDED"
	case 4:
		if payload == nil do return "NO MYSTERY PROGRESS"
		total := len(payload.deductions) + len(payload.questions) * 2
		if total == 0 do return "NO DEDUCTIONS OR QUESTIONS"
		cursor := authoring_workspace.creator_cursor % total
		if cursor < len(payload.deductions) do append(&setup.mystery_progress, Authoring_Creator_Mystery_Progress{.Deduction, payload.deductions[cursor].id, 1})
		else if cursor < len(payload.deductions) + len(payload.questions) {i := cursor - len(payload.deductions); append(&setup.mystery_progress, Authoring_Creator_Mystery_Progress{.Question, payload.questions[i].id, 1})} else {i := cursor - len(payload.deductions) - len(payload.questions); append(&setup.mystery_progress, Authoring_Creator_Mystery_Progress{.Investigation, payload.questions[i].id, 1})}
		return "MYSTERY PROGRESS OVERRIDE ADDED"
	case 5:
		total := len(campaign_document.variables) + len(campaign_document.cases) * 2
		if total == 0 do return "NO CAMPAIGN STATE"
		cursor := authoring_workspace.creator_cursor % total
		if cursor < len(campaign_document.variables) {item := campaign_document.variables[cursor]
			for &existing in setup.campaign_values do if existing.id == item.id {if existing.value.kind == .Boolean do existing.value.boolean_value = !existing.value.boolean_value
				else if existing.value.kind == .Integer do existing.value.integer_value += 1; return "CAMPAIGN VARIABLE OVERRIDE CHANGED"}
			value := Campaign_Value {
				kind          = item.kind,
				boolean_value = item.default_boolean,
				integer_value = item.default_integer,
				enum_value    = item.default_enum,
			}
			append(&setup.campaign_values, Authoring_Creator_Campaign_Value{item.id, value})
			return "CAMPAIGN VARIABLE OVERRIDE ADDED"}
		cursor -= len(campaign_document.variables)
		if cursor <
		   len(
			   campaign_document.cases,
		   ) {append(&setup.started_cases, campaign_document.cases[cursor].id)
			return "CAMPAIGN CASE MARKED STARTED"}
		cursor -= len(campaign_document.cases)
		append(&setup.completed_cases, campaign_document.cases[cursor].id)
		return "CAMPAIGN CASE MARKED COMPLETED"
	case 6:
		setup.action_budget = max(-1, setup.action_budget + 1)
		setup.time_minutes = max(-1, setup.time_minutes + 15)
		return "TIME / BUDGET OVERRIDE UPDATED"
	}
	return "UNKNOWN CREATOR STATE CATEGORY"
}

authoring_workspace_start_playtest :: proc(g: ^Game) -> string {
	mode := Authoring_Playtest_Start_Mode(
		authoring_workspace.playtest_start_mode % len(Authoring_Playtest_Start_Mode),
	); if g != nil {authoring_workspace.playtest_player_x = g.player_x; authoring_workspace.playtest_player_y = g.player_y; authoring_workspace.playtest_screen = g.screen; authoring_workspace.playtest_spatial_saved = true}; started := authoring_playtest_begin(&authoring_workspace.playtest, &active_story_project, &active_story_runtime, &graph_document, &level_document, &campaign_document, &campaign_playthrough, &authoring_workspace.assets, &authoring_workspace.creator_setup); if !started.ok {authoring_workspace.playtest_spatial_saved = false; return started.message}
	switch mode {
	case .Opening:
		if len(active_story_project.scenes) >
		   0 {_ = story_runtime_enter_scene(&active_story_runtime, active_story_project.scenes[0].id); if g != nil do g.screen = .Dialogue}
	case .Selected_Scene:
		if graph_state.active_scene >= 0 &&
		   graph_state.active_scene <
			   graph_document.scene_count {_ = story_runtime_enter_scene(&active_story_runtime, graph_document.scenes[graph_state.active_scene].scene.id); if g != nil do g.screen = .Dialogue}
	case .Selected_Node:
		if graph_state.selected_node >= 0 &&
		   graph_state.selected_node <
			   graph_document.node_count {node := graph_document.nodes[graph_state.selected_node].beat; _ = story_runtime_enter_scene(&active_story_runtime, node.scene); active_story_runtime.current_node = node.id; if g != nil do g.screen = .Dialogue}
	case .Spatial_Position:
		if g !=
		   nil {if editor_state.cursor_world_valid {g.player_x = editor_state.cursor_world.x; g.player_y = editor_state.cursor_world.y} else if len(level_document.markers) > 0 {g.player_x = level_document.markers[0].position.x; g.player_y = level_document.markers[0].position.y}; g.screen = .Investigate}
	case .Question:
		if state := cast(^Mystery_State)story_runtime_capability_state(
			   &active_story_runtime,
			   "mystery",
			   MYSTERY_DOMAIN_VERSION,
		   );
		   state !=
		   nil {payload := mystery_payload(&active_story_project); if payload != nil && len(payload.questions) > 0 do append(&state.question_progress, Mystery_Question_Progress{question_id = payload.questions[authoring_workspace.creator_cursor % len(payload.questions)].id, state = 1}); if g != nil do g.screen = .Board}
	case .Reveal:
		if state := cast(^Mystery_State)story_runtime_capability_state(
			   &active_story_runtime,
			   "mystery",
			   MYSTERY_DOMAIN_VERSION,
		   ); state != nil {state.reveal_progress = 1; if g != nil do g.screen = .Reveal_Prep}
	}
	return fmt.tprintf("PLAYTEST STARTED FROM %v · SOURCE SNAPSHOT ISOLATED", mode)
}
authoring_workspace_restore_spatial_playtest :: proc(g: ^Game) -> bool {if g == nil || !authoring_workspace.playtest_spatial_saved do return false
	g.player_x = authoring_workspace.playtest_player_x
	g.player_y = authoring_workspace.playtest_player_y
	g.screen = authoring_workspace.playtest_screen
	authoring_workspace.playtest_spatial_saved = false
	return true}
authoring_workspace_end_playtest :: proc(g: ^Game) -> string {ended := authoring_playtest_end(
		&authoring_workspace.playtest,
		&active_story_project,
		&active_story_runtime,
		&graph_document,
		&level_document,
		&campaign_document,
		&campaign_playthrough,
	)
	if ended.ok do _ = authoring_workspace_restore_spatial_playtest(g)
	return ended.message}

authoring_workspace_preview_demonstration :: proc(g: ^Game) -> string {
	if g == nil do return "GAME PREVIEW IS UNAVAILABLE"; payload := mystery_payload(&active_story_project); if payload == nil || len(payload.demonstrations) == 0 do return "NO DEMONSTRATION TO PREVIEW"; index := clamp(authoring_workspace.selected_record, 0, len(payload.demonstrations) - 1); demo := &payload.demonstrations[index]
	if authoring_workspace.playtest.active {ended := authoring_workspace_end_playtest(g); if !strings.contains(ended, "ENDED") && !strings.contains(ended, "RESTORED") do return ended}
	authoring_workspace.playtest_start_mode = int(
		Authoring_Playtest_Start_Mode.Question,
	); question := mystery_question_index(payload, demo.question_id); if question < 0 do return "DEMONSTRATION QUESTION IS MISSING"; authoring_workspace.creator_cursor = question
	message := authoring_workspace_start_playtest(
		g,
	); if !authoring_workspace.playtest.active do return message
	state := cast(^Mystery_State)story_runtime_capability_state(
		&active_story_runtime,
		"mystery",
		MYSTERY_DOMAIN_VERSION,
	); if state == nil do return "MYSTERY PREVIEW STATE IS UNAVAILABLE"; g.story_project = &active_story_project; g.story_runtime = &active_story_runtime; g.mystery_state = state; g.question_selected = question
	for slot in 0 ..< demo.slot_count {piece := mystery_demonstration_route_piece(demo, 0, slot); if clue := mystery_clue_index(payload, piece); clue >= 0 do _ = mystery_acquire_evidence_free(&active_story_project, state, piece)
		else if mystery_claim_index(payload, piece) >= 0 do _ = mystery_establish_claim(&active_story_project, state, piece)
		else do _ = mystery_string_set_add(&state.earned_deductions, piece); mystery_question_set_slot(g, question, slot, piece)}
	begin_question_demonstration(
		g,
	); return fmt.tprintf("%s · %s PREVIEW READY", message, strings.to_upper(demo.presentation))
}

authoring_workspace_record_step :: proc(
	step: Scenario_Step,
) -> string {if !authoring_workspace.scenario_recording do return "BEGIN RECORDING FIRST"
	if authoring_workspace.scenario_record.id == "" do authoring_workspace.scenario_record = authoring_scenario_record_init("creator_recording", "Recorded from unified playtest")
	return(
		authoring_scenario_record_action(&authoring_workspace.scenario_record, step) ? "SCENARIO ACTION RECORDED" : "SCENARIO ACTION REJECTED" \
	)}
authoring_workspace_replay_scenario :: proc() -> string {item := authoring_workspace_case()
	if item == nil || len(authoring_workspace.scenario_record.actions) == 0 do return "RECORDED SCENARIO IS EMPTY"
	story_path, _ := authoring_resolve_path(&active_authoring_project, item.paths.story)
	level_path, _ := authoring_resolve_path(&active_authoring_project, item.paths.level)
	scenario: Scenario_Context
	if ready := scenario_context_init(story_path, level_path, &scenario); !ready.ok do return ready.message
	defer scenario_context_destroy(&scenario)
	authoring_workspace.scenario_last = authoring_scenario_replay(
		&authoring_workspace.scenario_record,
		&scenario,
	)
	return(
		authoring_workspace.scenario_last.ok ? fmt.tprintf("DETERMINISTIC REPLAY PASSED · %d ACTIONS", authoring_workspace.scenario_last.executed) : fmt.tprintf("REPLAY FAILED AT %d · %s", authoring_workspace.scenario_last.failure.action_index, authoring_workspace.scenario_last.failure.message) \
	)}
authoring_workspace_export_failure :: proc(
	path: string,
) -> string {if !authoring_workspace.scenario_last.failure.failed do return "NO SCENARIO FAILURE TO EXPORT"
	text := authoring_scenario_failure_serialize(
		&authoring_workspace.scenario_record,
		&authoring_workspace.scenario_last,
	)
	return(
		authoring_atomic_write(path, text) ? "SCENARIO FAILURE TRACE EXPORTED" : "FAILURE TRACE EXPORT FAILED" \
	)}

authoring_workspace_apply_recovery :: proc() -> string {item := authoring_workspace_case()
	if item == nil do return "NO ACTIVE CASE"
	bundle: Authoring_Recovery_Bundle
	loaded := authoring_recovery_load(&active_authoring_project, item, &bundle)
	if !loaded.ok do return loaded.message
	applied := authoring_recovery_apply(
		&active_authoring_project,
		item,
		&bundle,
		&active_story_project,
		&graph_document,
		&level_document,
	)
	return applied.message}

authoring_workspace_load_case_documents :: proc(
	project: ^Authoring_Project,
	index: int,
	story: ^Story_Project,
	level: ^Level_Document,
	graph: ^Graph_Document,
) -> Authoring_Lifecycle_Result {
	if project == nil || story == nil || level == nil || graph == nil || index < 0 || index >= project.case_count do return {false, "authoring case is unavailable"}
	item := &project.cases[index]
	story_path, story_ok := authoring_resolve_path(
		project,
		item.paths.story,
	); level_path, level_ok := authoring_resolve_path(project, item.paths.level); graph_path, graph_ok := authoring_resolve_path(project, item.paths.graph_layout)
	if !story_ok || !level_ok || !graph_ok do return {false, "case contains an unsafe document path"}
	if loaded := load_story_project(story_path, story); !loaded.ok do return {false, fmt.tprintf("story source is missing or invalid · %s", loaded.message)}
	if loaded := level_load(level_path, level);
	   !loaded.ok {story_project_destroy(story); return {false, fmt.tprintf("level source is missing or invalid · %s", loaded.message)}}
	graph^ = authoring_graph_from_story(story)
	if os.exists(
		graph_path,
	) {data, error := os.read_entire_file_from_path(graph_path, context.temp_allocator); if error != nil {story_project_destroy(story); authoring_level_document_destroy(level); authoring_graph_document_destroy(graph); return {false, "graph layout source could not be read"}}; if applied := authoring_graph_layout_apply_text(graph, string(data)); !applied.ok {story_project_destroy(story); authoring_level_document_destroy(level); authoring_graph_document_destroy(graph); return {false, applied.message}}}
	return {true, "CASE DOCUMENTS LOADED"}
}

authoring_workspace_activate_case :: proc(index: int) -> Authoring_Lifecycle_Result {
	if !active_authoring_ready do return {false, "authoring project is unavailable"}
	next_story: Story_Project; next_level: Level_Document; next_graph: Graph_Document
	if loaded := authoring_workspace_load_case_documents(&active_authoring_project, index, &next_story, &next_level, &next_graph); !loaded.ok do return loaded
	if bound := authoring_app_bind_case(index);
	   !bound.ok {story_project_destroy(&next_story); authoring_level_document_destroy(&next_level); authoring_graph_document_destroy(&next_graph); return bound}
	graph_path, _ := authoring_resolve_path(
		&active_authoring_project,
		active_authoring_project.cases[index].paths.graph_layout,
	); _ = graph_set_layout_path(graph_path)
	story_project_destroy(
		&active_story_project,
	); authoring_level_document_destroy(&level_document); authoring_graph_document_destroy(&graph_document)
	active_story_project =
		next_story; level_document = next_level; graph_document = next_graph; graph_source_project = &active_story_project; level_project_runtime(&level_document)
	item := &active_authoring_project.cases[index]; authoring_case_mark_saved(item, .Story, active_story_project.revision); authoring_case_mark_saved(item, .Level, level_document.revision); authoring_case_mark_saved(item, .Graph_Layout, graph_document.revision)
	return {true, fmt.tprintf("OPENED CASE · %s", active_authoring_project.cases[index].title)}
}

authoring_workspace_open_project_now :: proc(root: string) -> Authoring_Lifecycle_Result {
	loaded_project: Authoring_Project; if loaded := authoring_project_load_manifest(root, &loaded_project); !loaded.ok do return loaded
	if loaded_project.case_count == 0 do return {false, "project contains no cases"}
	next_story: Story_Project; next_level: Level_Document; next_graph: Graph_Document
	if loaded := authoring_workspace_load_case_documents(
		&loaded_project,
		loaded_project.active_case,
		&next_story,
		&next_level,
		&next_graph,
	); !loaded.ok {project_asset_registry_destroy(&loaded_project.asset_registry); return loaded}
	story_project_destroy(
		&active_story_project,
	); authoring_level_document_destroy(&level_document); authoring_graph_document_destroy(&graph_document); authoring_asset_cancel_pending(); project_asset_history_destroy(&authoring_workspace.asset_history); delete(authoring_workspace.asset_campaign_undo); delete(authoring_workspace.asset_campaign_redo); authoring_workspace.asset_campaign_undo = nil; authoring_workspace.asset_campaign_redo = nil; delete(authoring_asset_authored_undo); delete(authoring_asset_authored_redo); authoring_asset_authored_undo = nil; authoring_asset_authored_redo = nil; project_asset_registry_destroy(&authoring_workspace.assets)
	active_authoring_project =
		loaded_project; active_authoring_ready = true; authoring_workspace.assets = active_authoring_project.asset_registry; active_authoring_project.asset_registry = {}; active_authoring_project.asset_registry_pending = false
	active_story_project =
		next_story; level_document = next_level; graph_document = next_graph; graph_source_project = &active_story_project
	if bound := authoring_app_bind_case(active_authoring_project.active_case); !bound.ok do return bound
	graph_path, _ := authoring_resolve_path(
		&active_authoring_project,
		authoring_workspace_case().paths.graph_layout,
	); _ = graph_set_layout_path(graph_path); level_project_runtime(&level_document)
	item := authoring_workspace_case(

	); authoring_case_mark_saved(item, .Story, active_story_project.revision); authoring_case_mark_saved(item, .Level, level_document.revision); authoring_case_mark_saved(item, .Graph_Layout, graph_document.revision)
	authoring_workspace.sequence += 1; authoring_recent_record(&authoring_workspace.recents, &active_authoring_project, u64(authoring_workspace.sequence)); authoring_workspace.selected_recent = authoring_workspace.recents.count - 1
	if recent_path, path_ok := authoring_recents_default_path(); path_ok do _ = authoring_recents_save(&authoring_workspace.recents, recent_path)
	return {true, "PROJECT OPENED WITH ACTIVE CASE"}
}

authoring_workspace_request_lifecycle :: proc(
	kind: Authoring_Pending_Lifecycle,
	index: int = -1,
	root: string = "",
) -> Authoring_Lifecycle_Result {
	authoring_app_sync_dirty()
	if active_authoring_ready &&
	   authoring_project_dirty(
		   &active_authoring_project,
	   ) {authoring_workspace.pending_lifecycle = kind; authoring_workspace.pending_case = index; authoring_workspace.pending_project_root = strings.clone(root); return {false, "UNSAVED DRAFTS · SAVE ALL, KEEP RECOVERY, OR CANCEL"}}
	switch kind {case .Switch_Case:
		return authoring_workspace_activate_case(index); case .Open_Project:
		return authoring_workspace_open_project_now(root); case .Close_Workspace:
		return {true, "AUTHORING WORKSPACE CLOSED"}; case .None:}
	return {false, "no lifecycle action was requested"}
}

authoring_workspace_resolve_lifecycle :: proc(
	g: ^Game,
	preserve: bool,
) -> Authoring_Lifecycle_Result {
	kind :=
		authoring_workspace.pending_lifecycle; if kind == .None do return {false, "no pending lifecycle decision"}
	prepared :=
		preserve ? authoring_app_save_recovery() : authoring_app_save_all(); if !prepared.ok do return prepared
	authoring_workspace.pending_lifecycle = .None
	result: Authoring_Lifecycle_Result
	switch kind {case .Switch_Case:
		result = authoring_workspace_activate_case(
			authoring_workspace.pending_case,
		); case .Open_Project:
		result = authoring_workspace_open_project_now(
			authoring_workspace.pending_project_root,
		); case .Close_Workspace:
		result = {true, "AUTHORING WORKSPACE CLOSED"}; case .None:
		result = {false, "no pending lifecycle action"}}
	if result.ok && kind == .Close_Workspace && g != nil do g.screen = .Campaign_Action
	return result
}

authoring_workspace_case_identity_change :: proc(value: string, move: bool) -> string {
	item := authoring_workspace_case(); if item == nil do return "NO ACTIVE CASE"
	if guard := authoring_app_dirty_guard(); !guard.ok do return "SAVE OR KEEP RECOVERY BEFORE RENAMING / MOVING THIS CASE"
	if move {result := authoring_case_move_directory(&active_authoring_project, item.id, strings.trim_space(value)); if result.ok {index := active_authoring_project.active_case; _ = authoring_app_bind_case(index); graph_path, _ := authoring_resolve_path(&active_authoring_project, item.paths.graph_layout); _ = graph_set_layout_path(graph_path)}; return result.message}
	return authoring_case_rename_title(&active_authoring_project, item.id, value).message
}

authoring_workspace_mystery_setup_delta :: proc(delta: int) -> string {payload := mystery_payload(
		&active_story_project,
	)
	if payload == nil do return "ACTIVE STORY IS NOT A MYSTERY"
	command := Mystery_Authoring_Command {
		kind = .Update,
		record_kind = .Setup,
		setup = {
			action_budget = max(1, payload.action_budget + delta),
			seed = payload.seed,
			tutorial_id = payload.tutorial_id,
			city_start = payload.city_start,
			city_destination = payload.city_destination,
			reveal_location = payload.reveal_location,
		},
	}
	commands := [1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	message := result.message
	mystery_authoring_result_destroy(&result)
	return message}

authoring_workspace_cycle_culprit :: proc() -> string {payload := mystery_payload(
		&active_story_project,
	)
	if payload == nil || len(active_story_project.entities) == 0 do return "CREATE A CHARACTER ENTITY FIRST"
	current := story_entity_index(&active_story_project, payload.solution.culprit_id)
	current = (current + 1) % len(active_story_project.entities)
	solution := payload.solution
	solution.culprit_id = active_story_project.entities[current].id
	command := Mystery_Authoring_Command {
		kind        = .Update,
		record_kind = .Solution,
		solution    = solution,
	}
	commands := [1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	message := result.message
	mystery_authoring_result_destroy(&result)
	return message}

authoring_workspace_resolve_inspection :: proc() -> bool {capabilities := story_capabilities()
	supported: [STORY_MAX_DOMAIN_ADAPTERS]string
	for item, i in capabilities.domains[:capabilities.domain_count] do supported[i] = fmt.tprintf("%s@%s", item.id, item.version)
	return authoring_service_apply_resolution(
		&authoring_workspace.inspection,
		&authoring_workspace.library,
		supported[:capabilities.domain_count],
	)}
authoring_workspace_resolution_counts :: proc() -> (int, int, bool) {capabilities :=
		story_capabilities()
	supported: [STORY_MAX_DOMAIN_ADAPTERS]string
	for item, i in capabilities.domains[:capabilities.domain_count] do supported[i] = fmt.tprintf("%s@%s", item.id, item.version)
	resolution := authoring_service_resolve(
		&authoring_workspace.inspection,
		&authoring_workspace.library,
		supported[:capabilities.domain_count],
	)
	defer authoring_service_resolution_destroy(&resolution)
	return len(resolution.missing_dependencies),
		len(resolution.incompatible_capabilities),
		resolution.compatible}
authoring_workspace_refresh_library :: proc() -> string {if authoring_workspace.library_root == "" do return "CHOOSE AN INSTALLED LIBRARY ROOT"
	result := authoring_service_scan_library(
		authoring_workspace.library_root,
		&authoring_workspace.library,
	)
	authoring_workspace.selected_library = clamp(
		authoring_workspace.selected_library,
		0,
		max(0, len(authoring_workspace.library.installed) - 1),
	)
	if authoring_workspace.inspection.artifact.identity.id != "" do _ = authoring_workspace_resolve_inspection()
	return result.message}
authoring_workspace_uninstall_selected :: proc() -> string {if len(authoring_workspace.library.installed) == 0 do return "NO INSTALLED VERSION SELECTED"
	i := clamp(
		authoring_workspace.selected_library,
		0,
		len(authoring_workspace.library.installed) - 1,
	)
	plan := authoring_library_plan_uninstall(
		&authoring_workspace.library,
		authoring_workspace.library.installed[i].identity,
	)
	defer authoring_uninstall_plan_destroy(&plan)
	if !plan.allowed {if len(plan.diagnostics) > 0 do return plan.diagnostics[0].message; return(
			"UNINSTALL IS BLOCKED" \
		)}
	result := authoring_service_uninstall(&authoring_workspace.library, &plan)
	authoring_workspace.selected_library = clamp(
		i,
		0,
		max(0, len(authoring_workspace.library.installed) - 1),
	)
	return result.message}
authoring_workspace_reveal_selected :: proc() -> string {if len(authoring_workspace.library.installed) == 0 do return "NO INSTALLED VERSION SELECTED"
	root :=
		authoring_workspace.library.installed[clamp(authoring_workspace.selected_library, 0, len(authoring_workspace.library.installed) - 1)].install_root
	return(
		authoring_native_reveal_path(root) ? "REVEALED INSTALLED VERSION IN FINDER" : "INSTALLED VERSION COULD NOT BE REVEALED" \
	)}
authoring_workspace_install :: proc() -> string {if authoring_workspace.picked_path == "" do return "INSPECT A PACKAGE FIRST"
	if authoring_workspace.library_root == "" do authoring_workspace.library_root = authoring_native_select_directory("Choose Installed Story Library")
	if authoring_workspace.library_root != "" && os.is_dir(authoring_workspace.library_root) do _ = authoring_service_scan_library(authoring_workspace.library_root, &authoring_workspace.library)
	_ = authoring_workspace_resolve_inspection()
	decision := Authoring_Import_Decision(clamp(authoring_workspace.import_decision, 0, 3))
	if decision == .Editable_Copy && authoring_workspace.editable_root == "" do authoring_workspace.editable_root = authoring_native_select_directory("Choose Editable Copy Destination")
	return(
		authoring_workspace_action_install(authoring_workspace.library_root, decision, authoring_workspace.editable_root).message \
	)}
