package main

import "core:fmt"

authoring_app_initialize :: proc(story_path, level_path: string) -> Authoring_Lifecycle_Result {
	id :=
		campaign_document.id != "" ? campaign_document.id : "local_project"; title := campaign_document.title != "" ? campaign_document.title : "Local Story Project"
	project, ok := authoring_project_new(
		id,
		title,
		".",
	); if !ok do return {false, "could not initialize authoring project identity"}
	for campaign_case in campaign_document.cases {
		if !authoring_project_add_case(&project, campaign_case.id, campaign_case.title) do continue
		item := &project.cases[project.case_count - 1]
		if authoring_relative_path_valid(campaign_case.story_path) do item.paths.story = campaign_case.story_path
		if authoring_relative_path_valid(campaign_case.level_path) do item.paths.level = campaign_case.level_path
		item.paths.graph_layout = fmt.tprintf(
			".authoring/%s/%s.graph.layout.toml",
			project.id,
			item.id,
		)
		item.paths.story_autosave = fmt.tprintf(
			".autosave/%s/%s/story.autosave.toml",
			project.id,
			item.id,
		)
		item.paths.level_autosave = fmt.tprintf(
			".autosave/%s/%s/level.autosave.toml",
			project.id,
			item.id,
		)
		item.paths.graph_layout_autosave = fmt.tprintf(
			".autosave/%s/%s/graph.autosave.toml",
			project.id,
			item.id,
		)
	}
	if project.case_count ==
	   0 {if !authoring_project_add_case(&project, "active_case", "Active Case") do return {false, "could not initialize active authoring case"}; project.cases[0].paths.story = story_path; project.cases[0].paths.level = level_path}
	active_authoring_project =
		project; active_authoring_ready = true; active_authoring_read_only = player_package_mode
	selected := 0; for item, i in active_authoring_project.cases[:active_authoring_project.case_count] do if item.paths.story == story_path || item.paths.level == level_path do selected = i; active_authoring_project.active_case = selected
	return authoring_app_bind_case(selected)
}

authoring_app_bind_case :: proc(index: int) -> Authoring_Lifecycle_Result {
	if !active_authoring_ready || index < 0 || index >= active_authoring_project.case_count do return {false, "authoring case is unavailable"}
	if active_authoring_project.asset_registry_pending {
		authoring_asset_cancel_pending()
		project_asset_history_destroy(&authoring_workspace.asset_history)
		delete(
			authoring_workspace.asset_campaign_undo,
		); delete(authoring_workspace.asset_campaign_redo)
		authoring_workspace.asset_campaign_undo =
			nil; authoring_workspace.asset_campaign_redo = nil
		project_asset_registry_destroy(&authoring_workspace.assets)
		authoring_workspace.assets = active_authoring_project.asset_registry
		active_authoring_project.asset_registry = {}
		active_authoring_project.asset_registry_pending = false
	}
	item := &active_authoring_project.cases[index]; active_authoring_project.active_case = index
	story_path, _ := authoring_resolve_path(
		&active_authoring_project,
		item.paths.story,
	); story_auto, _ := authoring_resolve_path(&active_authoring_project, item.paths.story_autosave); level_path, _ := authoring_resolve_path(&active_authoring_project, item.paths.level); level_auto, _ := authoring_resolve_path(&active_authoring_project, item.paths.level_autosave)
	if !graph_set_document_paths(story_path, story_auto) do return {false, "graph paths could not be bound"}; if !level_set_active_paths(level_path, level_auto).ok do return {false, "level paths could not be bound"}
	active_authoring_read_only =
		player_package_mode; graph_autosave_enabled = !active_authoring_read_only; return {true, "AUTHORING CASE BOUND"}
}

authoring_app_sync_dirty :: proc() {
	if !active_authoring_ready do return; item := authoring_project_active_case(&active_authoring_project); if item == nil do return
	// Revision ownership is per document. In particular, Graph's dirty flag
	// must never clear an independently edited Story draft.
	authoring_case_mark_dirty(item, .Story, active_story_project.revision)
	authoring_case_mark_dirty(item, .Level, level_document.revision)
	authoring_case_mark_dirty(item, .Graph_Layout, graph_document.revision)
}

authoring_app_dirty_guard :: proc() -> Authoring_Lifecycle_Result {authoring_app_sync_dirty()
	if active_authoring_ready && authoring_project_dirty(&active_authoring_project) do return {false, "unsaved story, graph, or level drafts must be saved or preserved before switching"}
	return {true, "AUTHORING DRAFTS CLEAN"}}

authoring_app_save_all :: proc() -> Authoring_Lifecycle_Result {
	if !active_authoring_ready do return {false, "authoring project is unavailable"}; if active_authoring_read_only do return {false, "installed content is read-only; create an editable copy"}; item := authoring_project_active_case(&active_authoring_project); if item == nil do return {false, "authoring case is unavailable"}
	story :=
		active_story_project; if graph_document.dirty {built := graph_build_story_project(&active_story_project, &story); if !built.ok do return {false, built.message}; defer story_project_destroy(&story)}
	documents := [3]Authoring_Save_Document {
		{.Story, story.revision, story_project_serialize(&story)},
		{.Level, level_document.revision, level_serialize(&level_document)},
		{
			.Graph_Layout,
			graph_document.revision,
			fmt.tprintf(
				"version = \"1\"\ncase_id = \"%s\"\nrevision = %d\n",
				item.id,
				graph_document.revision,
			),
		},
	}; saved := authoring_save_all(&active_authoring_project, item, documents[:]); if !saved.ok do return saved
	assets_saved := project_asset_registry_save_project(
		&active_authoring_project,
		&authoring_workspace.assets,
	); if !assets_saved.ok do return {false, assets_saved.message}
	level_document.dirty =
		false; graph_document.dirty = false; return {true, "ALL DOCUMENTS AND ASSETS SAVED"}
}

authoring_app_save_recovery :: proc() -> Authoring_Lifecycle_Result {
	if !active_authoring_ready || active_authoring_read_only do return {false, "recovery writes are unavailable"}; item := authoring_project_active_case(&active_authoring_project); if item == nil do return {false, "authoring case is unavailable"}; bundle := Authoring_Recovery_Bundle {
		project_id = active_authoring_project.id,
		case_id    = item.id,
	}; bundle.documents[.Story] = {
		kind           = .Story,
		base_revision  = item.documents[.Story].saved_revision,
		draft_revision = active_story_project.revision,
		serialized     = story_project_serialize(&active_story_project),
	}; bundle.documents[.Level] = {
		kind           = .Level,
		base_revision  = item.documents[.Level].saved_revision,
		draft_revision = level_document.revision,
		serialized     = level_serialize(&level_document),
	}; bundle.documents[.Graph_Layout] = {
		kind           = .Graph_Layout,
		base_revision  = item.documents[.Graph_Layout].saved_revision,
		draft_revision = graph_document.revision,
		serialized     = fmt.tprintf("revision = %d\n", graph_document.revision),
	}; return authoring_recovery_save(&active_authoring_project, item, &bundle)
}

authoring_app_new_case :: proc(
	id, title: string,
	mystery: bool,
) -> Authoring_Lifecycle_Result {if active_authoring_read_only do return {false, "installed content is read-only; create an editable copy"}
	return authoring_create_case_template(
		&active_authoring_project,
		id,
		title,
		mystery ? .Mystery : .General_Story,
	)}
authoring_app_duplicate_case :: proc(
	source_id, target_id, target_title: string,
) -> Authoring_Lifecycle_Result {if active_authoring_read_only do return {false, "installed content is read-only; create an editable copy"}
	plan := authoring_case_operation_plan(
		&active_authoring_project,
		.Duplicate,
		source_id,
		target_id,
		target_title,
	)
	return authoring_case_operation_execute(&active_authoring_project, &plan)}
authoring_app_delete_case :: proc(
	id: string,
) -> Authoring_Lifecycle_Result {if active_authoring_read_only do return {false, "installed content is read-only"}
	plan := authoring_case_operation_plan(
		&active_authoring_project,
		.Delete,
		id,
		"",
		"",
		campaign = &campaign_document,
	)
	return authoring_case_operation_execute(&active_authoring_project, &plan)}
authoring_app_create_editable_copy :: proc(
	source_id, target_id, target_title: string,
) -> Authoring_Lifecycle_Result {plan := authoring_case_operation_plan(
		&active_authoring_project,
		.Editable_Copy,
		source_id,
		target_id,
		target_title,
		true,
	)
	result := authoring_case_operation_execute(&active_authoring_project, &plan)
	if result.ok {active_authoring_read_only = false; player_package_mode = false
		graph_autosave_enabled = true}
	return result}
