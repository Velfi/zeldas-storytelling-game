package main

import "core:fmt"
import "core:os"
import "core:strings"

authoring_asset_begin_form :: proc(
	action: Authoring_Form_Action,
	value: string = "",
) {authoring_workspace.form_active = true; authoring_workspace.form_action = action
	authoring_workspace.form_count = min(len(value), len(authoring_workspace.form_buffer))
	copy(authoring_workspace.form_buffer[:authoring_workspace.form_count], transmute([]u8)value)}
authoring_asset_provenance :: proc() -> Project_Asset_Provenance {return{
		source_uri = authoring_workspace.asset_source_uri,
		source_name = authoring_workspace.asset_source_name,
		creator = authoring_workspace.asset_creator,
		attribution = authoring_workspace.asset_attribution,
		license_id = authoring_workspace.asset_license_id,
		license_text = authoring_workspace.asset_license_text,
		redistribution_permitted = authoring_workspace.asset_redistribution,
	}}
authoring_asset_cancel_pending :: proc() {project_asset_replacement_preview_destroy(
		&authoring_workspace.pending_asset_replacement,
	)
	project_asset_relink_plan_destroy(&authoring_workspace.pending_asset_relink)
	authoring_workspace.pending_asset_action = .None}
authoring_asset_authored_capture :: proc() -> Authoring_Asset_Authored_Snapshot {s :=
		Authoring_Asset_Authored_Snapshot {
			story_entity  = -1,
			graph_node    = -1,
			level_object  = -1,
			catalog_entry = -1,
			story_font    = active_story_project.ui_font_asset_ref,
		}
	if authoring_workspace.selected_category == int(Story_Authoring_Record_Kind.Entity) &&
	   authoring_workspace.selected_record >= 0 &&
	   authoring_workspace.selected_record < len(active_story_project.entities) {s.story_entity =
			authoring_workspace.selected_record
		s.story_appearance =
			active_story_project.entities[s.story_entity].appearance_model_asset_ref}
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node < graph_document.node_count {s.graph_node =
			graph_state.selected_node
		beat := graph_document.nodes[s.graph_node].beat
		s.graph_image = beat.ui_image_asset_ref
		s.graph_sound = beat.sound_cue_asset_ref
		s.graph_animation = beat.animation_asset_ref}
	if editor_state.selection_count > 0 &&
	   editor_state.selection[0].kind == .Object {s.level_object = level_object_index(
			&level_document,
			editor_state.selection[0].entity_id,
		)
		if s.level_object >= 0 {item := level_document.objects[s.level_object]; s.level_model =
				item.model_asset_ref
			s.level_material = item.material_asset_ref
			s.level_texture = item.texture_asset_ref}}
	for item, index in editor_catalog.entries do if item.id == editor_state.catalog_id {s.catalog_entry = index; s.catalog_model_ref = item.model_asset_ref; s.catalog_model = item.model; break}
	return s}
authoring_asset_authored_capture_targets :: proc(
	target: Authoring_Asset_Authored_Snapshot,
) -> Authoring_Asset_Authored_Snapshot {s := Authoring_Asset_Authored_Snapshot {
		story_entity  = target.story_entity,
		graph_node    = target.graph_node,
		level_object  = target.level_object,
		catalog_entry = target.catalog_entry,
		story_font    = active_story_project.ui_font_asset_ref,
	}; if s.story_entity >= 0 && s.story_entity < len(active_story_project.entities) do s.story_appearance = active_story_project.entities[s.story_entity].appearance_model_asset_ref; if s.graph_node >= 0 && s.graph_node < graph_document.node_count {beat := graph_document.nodes[s.graph_node].beat; s.graph_image = beat.ui_image_asset_ref; s.graph_sound = beat.sound_cue_asset_ref; s.graph_animation = beat.animation_asset_ref}; if s.level_object >= 0 && s.level_object < len(level_document.objects) {item := level_document.objects[s.level_object]; s.level_model = item.model_asset_ref; s.level_material = item.material_asset_ref; s.level_texture = item.texture_asset_ref}; if s.catalog_entry >= 0 && s.catalog_entry < len(editor_catalog.entries) {item := editor_catalog.entries[s.catalog_entry]; s.catalog_model_ref = item.model_asset_ref; s.catalog_model = item.model}; return s}
authoring_asset_authored_apply :: proc(
	s: Authoring_Asset_Authored_Snapshot,
) {active_story_project.ui_font_asset_ref = s.story_font; if s.story_entity >= 0 && s.story_entity < len(active_story_project.entities) do active_story_project.entities[s.story_entity].appearance_model_asset_ref = s.story_appearance
	if s.graph_node >= 0 && s.graph_node < graph_document.node_count {graph_document.nodes[s.graph_node].beat.ui_image_asset_ref =
			s.graph_image
		graph_document.nodes[s.graph_node].beat.sound_cue_asset_ref = s.graph_sound
		graph_document.nodes[s.graph_node].beat.animation_asset_ref = s.graph_animation}
	if s.level_object >= 0 && s.level_object < len(level_document.objects) {level_document.objects[s.level_object].model_asset_ref =
			s.level_model
		level_document.objects[s.level_object].material_asset_ref = s.level_material
		level_document.objects[s.level_object].texture_asset_ref = s.level_texture}
	if s.catalog_entry >= 0 &&
	   s.catalog_entry < len(editor_catalog.entries) {editor_catalog.entries[s.catalog_entry].model_asset_ref =
			s.catalog_model_ref
		editor_catalog.entries[s.catalog_entry].model = s.catalog_model}}
authoring_asset_history_begin :: proc() {project_asset_history_begin(
		&authoring_workspace.asset_history,
		&authoring_workspace.assets,
	)
	append(
		&authoring_workspace.asset_campaign_undo,
		strings.clone(campaign_workspace.draft.thumbnail),
	)
	delete(authoring_workspace.asset_campaign_redo)
	authoring_workspace.asset_campaign_redo = nil
	append(&authoring_asset_authored_undo, authoring_asset_authored_capture())
	delete(authoring_asset_authored_redo)
	authoring_asset_authored_redo = nil}
authoring_asset_sync_campaign :: proc() {campaign_workspace.dirty = true
	campaign_workspace.diagnostics = campaign_validate(&campaign_workspace.draft)
	campaign_workspace.simulated = campaign_playthrough
	_ = campaign_recalculate(&campaign_workspace.draft, &campaign_workspace.simulated)
	if campaign_workspace.history.ready {campaign_destroy(&campaign_workspace.history.current)
		campaign_workspace.history.current = campaign_clone(&campaign_workspace.draft)}}
authoring_asset_history_cancel :: proc() -> bool {if !project_asset_history_cancel(&authoring_workspace.asset_history, &authoring_workspace.assets) do return false
	if len(authoring_workspace.asset_campaign_undo) > 0 {last :=
			len(authoring_workspace.asset_campaign_undo) - 1
		thumbnail := authoring_workspace.asset_campaign_undo[last]
		ordered_remove(&authoring_workspace.asset_campaign_undo, last)
		campaign_workspace.draft.thumbnail = thumbnail
		campaign_document.thumbnail = thumbnail
		authoring_asset_sync_campaign()}
	if len(authoring_asset_authored_undo) > 0 {last := len(authoring_asset_authored_undo) - 1
		authoring_asset_authored_apply(authoring_asset_authored_undo[last])
		ordered_remove(&authoring_asset_authored_undo, last)}
	return true}
authoring_asset_history_restore :: proc(undo: bool) -> bool {source :=
		undo ? &authoring_workspace.asset_campaign_undo : &authoring_workspace.asset_campaign_redo
	destination :=
		undo ? &authoring_workspace.asset_campaign_redo : &authoring_workspace.asset_campaign_undo
	authored_source := undo ? &authoring_asset_authored_undo : &authoring_asset_authored_redo
	authored_destination := undo ? &authoring_asset_authored_redo : &authoring_asset_authored_undo
	if len(source^) == 0 || len(authored_source^) == 0 do return false
	ok :=
		undo ? project_asset_history_undo(&authoring_workspace.asset_history, &authoring_workspace.assets) : project_asset_history_redo(&authoring_workspace.asset_history, &authoring_workspace.assets)
	if !ok do return false
	append(destination, strings.clone(campaign_workspace.draft.thumbnail))
	last := len(source^) - 1
	thumbnail := source^[last]
	ordered_remove(source, last)
	campaign_workspace.draft.thumbnail = thumbnail
	campaign_document.thumbnail = thumbnail
	authoring_asset_sync_campaign()
	authored_last := len(authored_source^) - 1
	append(
		authored_destination,
		authoring_asset_authored_capture_targets(authored_source^[authored_last]),
	)
	authoring_asset_authored_apply(authored_source^[authored_last])
	ordered_remove(authored_source, authored_last)
	_ = authoring_invalidate_after_edit(.Assets, authoring_workspace.assets.revision)
	return true}
authoring_asset_finish_transaction :: proc(result: Validation) -> string {if !result.ok do _ = authoring_asset_history_cancel()
	else do _ = authoring_invalidate_after_edit(.Assets, authoring_workspace.assets.revision)
	return result.message}
authoring_asset_import_selected :: proc(path: string) -> string {request :=
		Project_Asset_Import_Request {
			project_root          = active_authoring_project.root_path,
			source_path           = path,
			destination_directory = "assets/imported",
			requested_id          = authoring_workspace_next_id("asset"),
			kind                  = Project_Asset_Kind(
				authoring_workspace.asset_kind % len(Project_Asset_Kind),
			),
			mode                  = Project_Asset_Source_Mode(authoring_workspace.asset_mode % 2),
			embed_policy          = Project_Asset_Embed_Policy(
				authoring_workspace.asset_policy % 3,
			),
			provenance            = authoring_asset_provenance(),
		}
	authoring_asset_history_begin()
	result := project_asset_import(&authoring_workspace.assets, request)
	message := authoring_asset_finish_transaction(result)
	if result.ok do authoring_workspace.selected_asset = len(authoring_workspace.assets.assets) - 1
	return message}
authoring_asset_preview_replacement_selected :: proc(path: string) -> string {i :=
		authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN ASSET"
	authoring_asset_cancel_pending()
	authoring_workspace.pending_asset_replacement = project_asset_preview_replacement(
		&authoring_workspace.assets,
		authoring_workspace.assets.assets[i].id,
		path,
	)
	if !authoring_workspace.pending_asset_replacement.valid do return authoring_workspace.pending_asset_replacement.message
	authoring_workspace.pending_asset_action = .Replacement
	return authoring_workspace.pending_asset_replacement.message}
authoring_asset_preview_relink :: proc(
	search_root: string,
) -> string {authoring_asset_cancel_pending(); authoring_workspace.pending_asset_relink =
		project_asset_plan_relink(
			&authoring_workspace.assets,
			active_authoring_project.root_path,
			search_root,
		)
	if len(authoring_workspace.pending_asset_relink.candidates) == 0 do return fmt.tprintf("NO EXACT-HASH CANDIDATE · %d ASSETS STILL MISSING", len(authoring_workspace.pending_asset_relink.missing))
	authoring_workspace.pending_asset_action = .Relink
	c := authoring_workspace.pending_asset_relink.candidates[0]
	return fmt.tprintf("REVIEW RELINK · %s → %s · EXACT SHA256", c.asset_id, c.candidate_path)}
authoring_asset_confirm_pending :: proc() -> string {switch
	authoring_workspace.pending_asset_action {case .Replacement:
		authoring_asset_history_begin()
		result := project_asset_commit_replacement(
			&authoring_workspace.assets,
			active_authoring_project.root_path,
			&authoring_workspace.pending_asset_replacement,
		)
		message := authoring_asset_finish_transaction(result)
		if result.ok do authoring_asset_cancel_pending()
		return message; case .Relink:
		if len(authoring_workspace.pending_asset_relink.candidates) == 0 do return "NO RELINK CANDIDATE"
		authoring_asset_history_begin()
		result := project_asset_apply_relink(
			&authoring_workspace.assets,
			active_authoring_project.root_path,
			authoring_workspace.pending_asset_relink.candidates[0],
		)
		message := authoring_asset_finish_transaction(result)
		if result.ok do authoring_asset_cancel_pending()
		return message; case .None:
		return "NO ASSET CHANGE TO CONFIRM"}
	return "NO ASSET CHANGE TO CONFIRM"}
authoring_asset_add_usage :: proc(value: string) -> string {i := authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN ASSET"
	parts := strings.split(value, "|")
	if len(parts) != 3 do return "USE DOCUMENT|ENTITY|FIELD"
	usage := Project_Asset_Usage {
		asset_id   = authoring_workspace.assets.assets[i].id,
		document   = strings.trim_space(parts[0]),
		entity_id  = strings.trim_space(parts[1]),
		field_path = strings.trim_space(parts[2]),
	}
	authoring_asset_history_begin()
	if project_asset_registry_register_usage(
		&authoring_workspace.assets,
		usage,
	) {_ = authoring_invalidate_after_edit(.Assets, authoring_workspace.assets.revision)
		return "ASSET USAGE REGISTERED"}
	_ = authoring_asset_history_cancel()
	return "ASSET USAGE REJECTED"}
authoring_asset_load_selected :: proc() {i := authoring_workspace.selected_asset; if i < 0 || i >= len(authoring_workspace.assets.assets) do return
	asset := authoring_workspace.assets.assets[i]
	authoring_workspace.asset_kind = int(asset.kind)
	authoring_workspace.asset_mode = int(asset.source_mode)
	authoring_workspace.asset_policy = int(asset.embed_policy)
	authoring_workspace.asset_redistribution = asset.provenance.redistribution_permitted
	authoring_workspace.asset_source_uri = asset.provenance.source_uri
	authoring_workspace.asset_source_name = asset.provenance.source_name
	authoring_workspace.asset_creator = asset.provenance.creator
	authoring_workspace.asset_attribution = asset.provenance.attribution
	authoring_workspace.asset_license_id = asset.provenance.license_id
	authoring_workspace.asset_license_text = asset.provenance.license_text}
authoring_asset_apply_selected_metadata :: proc() -> string {i :=
		authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN ASSET"
	replacement := authoring_workspace.assets.assets[i]
	replacement.kind = Project_Asset_Kind(authoring_workspace.asset_kind % len(Project_Asset_Kind))
	replacement.embed_policy = Project_Asset_Embed_Policy(authoring_workspace.asset_policy % 3)
	replacement.provenance = authoring_asset_provenance()
	authoring_asset_history_begin()
	result := project_asset_registry_replace(
		&authoring_workspace.assets,
		replacement.id,
		replacement,
	)
	message := authoring_asset_finish_transaction(result)
	return result.ok ? "ASSET METADATA AND PACKAGE POLICY UPDATED" : message}
authoring_asset_map_selected_by_kind :: proc() -> string {
	i := authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN ASSET"
	asset := authoring_workspace.assets.assets[i]
	authoring_asset_history_begin()
	target := Project_Asset_Semantic_Target.Catalog_Model
	entity := asset.id
	authored := false
	switch asset.kind {
	case .Model:
		if editor_state.selection_count > 0 &&
		   editor_state.selection[0].kind ==
			   .Object {target = .Prop_Model; entity = editor_state.selection[0].entity_id; if object_index := level_object_index(&level_document, entity); object_index >= 0 {level_document.objects[object_index].model_asset_ref = asset.id; authored = true}} else if authoring_workspace.tab == .Story_Data && authoring_workspace.selected_category == int(Story_Authoring_Record_Kind.Entity) && authoring_workspace.selected_record >= 0 && authoring_workspace.selected_record < len(active_story_project.entities) {target = .Character_Appearance; entity = active_story_project.entities[authoring_workspace.selected_record].id; active_story_project.entities[authoring_workspace.selected_record].appearance_model_asset_ref = asset.id; active_story_project.revision += 1; authored = true} else if entry, found := catalog_object_entry(editor_state.catalog_id); found {entity = entry.id; for &candidate in editor_catalog.entries do if candidate.id == entry.id {candidate.model_asset_ref = asset.id; candidate.model = asset.project_path != "" ? asset.project_path : asset.source_path; authored = true; break}; if authored {saved := catalog_asset_overrides_save(active_authoring_project.root_path, &editor_catalog); if !saved.ok do return saved.message}}
	case .Texture, .Material:
		target = .Material
		if editor_state.selection_count > 0 &&
		   editor_state.selection[0].kind ==
			   .Object {entity = editor_state.selection[0].entity_id; if object_index := level_object_index(&level_document, entity); object_index >= 0 {if asset.kind == .Texture do level_document.objects[object_index].texture_asset_ref = asset.id
				else do level_document.objects[object_index].material_asset_ref = asset.id; authored = true}}
	case .Image:
		target = .UI_Image
		if graph_state.selected_node >= 0 &&
		   graph_state.selected_node <
			   graph_document.node_count {entity = graph_document.nodes[graph_state.selected_node].beat.id; graph_document.nodes[graph_state.selected_node].beat.ui_image_asset_ref = asset.id; graph_changed(); authored = true}
	case .Audio:
		target = .Sound_Cue
		if graph_state.selected_node >= 0 &&
		   graph_state.selected_node <
			   graph_document.node_count {entity = graph_document.nodes[graph_state.selected_node].beat.id; graph_document.nodes[graph_state.selected_node].beat.sound_cue_asset_ref = asset.id; graph_changed(); authored = true}
	case .Animation:
		target = .Animation
		if graph_state.selected_node >= 0 &&
		   graph_state.selected_node <
			   graph_document.node_count {entity = graph_document.nodes[graph_state.selected_node].beat.id; graph_document.nodes[graph_state.selected_node].beat.animation_asset_ref = asset.id; graph_changed(); authored = true}
	case .Font:
		target = .Font; entity = active_story_project.id
		if entity == "" do entity = "active_story"
		active_story_project.ui_font_asset_ref = asset.id
		active_story_project.revision += 1
		authored = true
	case .Thumbnail:
		target = .Campaign_Thumbnail; entity = campaign_document.id
		path := asset.project_path != "" ? asset.project_path : asset.source_path
		campaign_document.thumbnail = path; campaign_workspace.draft.thumbnail = path
		authoring_asset_sync_campaign(); authored = true
	}
	usage, valid := project_asset_semantic_usage(asset, target, entity)
	if !valid.ok {_ = authoring_asset_history_cancel(); return valid.message}
	if !project_asset_registry_register_usage(
		&authoring_workspace.assets,
		usage,
	) {_ = authoring_asset_history_cancel(); return "ASSET MAPPING REJECTED"}
	_ = authoring_invalidate_after_edit(.Assets, authoring_workspace.assets.revision)
	if authored do return fmt.tprintf("ASSET MAPPED INTO AUTHORED FIELD · %s / %s / %s", usage.document, usage.entity_id, usage.field_path)
	return fmt.tprintf(
		"TYPED OWNED-ASSET REFERENCE REGISTERED · %s / %s / %s",
		usage.document,
		usage.entity_id,
		usage.field_path,
	)
}
authoring_asset_open_first_usage :: proc(g: ^Game) -> string {i :=
		authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN ASSET"
	id := authoring_workspace.assets.assets[i].id
	for usage in authoring_workspace.assets.usages do if usage.asset_id == id {workspace := "assets"; if usage.document == "story" do workspace = "story"
		else if usage.document == "graph" do workspace = "graph"
		else if usage.document == "level" || usage.document == "catalog" do workspace = "build"
		else if usage.document == "campaign" do workspace = "campaign"; diagnostic := authoring_diagnostic_init(.Assets, usage.document, usage.entity_id, usage.field_path, .Info, "asset usage"); if workspace == "story" do diagnostic.domain = .Story_Core
		else if workspace == "graph" do diagnostic.domain = .Graph
		else if workspace == "build" do diagnostic.domain = .Level
		else if workspace == "campaign" do diagnostic.domain = .Campaign; _ = authoring_navigation_dispatch(diagnostic, g); return fmt.tprintf("OPENED ASSET USAGE · %s / %s", usage.entity_id, usage.field_path)}
	return "ASSET HAS NO REGISTERED USAGE"}

authoring_json_escape_value :: proc(value: string) -> string {a, _ := strings.replace_all(
		value,
		"\\",
		"\\\\",
	)
	b, _ := strings.replace_all(a, "\"", "\\\"")
	c, _ := strings.replace_all(b, "\n", "\\n")
	d, _ := strings.replace_all(c, "\r", "\\r")
	return d}
Authoring_Story_Export_Snapshot :: struct {
	story:  Story_Project,
	level:  Level_Document,
	graph:  Graph_Document,
	loaded: bool,
}

authoring_story_export_snapshot_destroy :: proc(
	snapshot: ^Authoring_Story_Export_Snapshot,
) {if snapshot == nil do return; if snapshot.loaded {story_project_destroy(&snapshot.story)
		authoring_level_document_destroy(&snapshot.level)
		authoring_graph_document_destroy(&snapshot.graph)}
	snapshot^ = {}}

// Export validation deliberately reloads the committed files. Save All may
// compile unsaved Graph changes into Story, so validating the pre-save Story
// object would validate different bytes than the package tool reads.
authoring_story_export_snapshot_load :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
	out: ^Authoring_Story_Export_Snapshot,
) -> Authoring_Lifecycle_Result {
	if project == nil || item == nil || out == nil do return {false, "export snapshot target is incomplete"}
	story_path, story_ok := authoring_resolve_path(
		project,
		item.paths.story,
	); level_path, level_ok := authoring_resolve_path(project, item.paths.level)
	if !story_ok || !level_ok do return {false, "export snapshot paths are outside the project"}
	story: Story_Project; if loaded := load_story_project(story_path, &story); !loaded.ok do return {false, fmt.tprintf("saved story snapshot is invalid: %s", loaded.message)}
	level: Level_Document; if loaded := level_load(level_path, &level); !loaded.ok {story_project_destroy(&story); return {false, fmt.tprintf("saved level snapshot is invalid: %s", loaded.message)}}
	graph := authoring_graph_from_story(&story)
	out^ = {
		story  = story,
		level  = level,
		graph  = graph,
		loaded = true,
	}
	return {true, "SAVED EXPORT SNAPSHOT LOADED"}
}

authoring_workspace_export_story_case :: proc(
	item: ^Authoring_Case,
	output_path, config_relative: string,
	save_active: bool,
	record_artifact: bool,
) -> string {
	if item == nil do return "NO CASE TO EXPORT"
	if save_active {saved := authoring_app_save_all(); if !saved.ok do return saved.message}
	snapshot := new(
		Authoring_Story_Export_Snapshot,
	); defer free(snapshot); if loaded := authoring_story_export_snapshot_load(&active_authoring_project, item, snapshot); !loaded.ok do return loaded.message; defer authoring_story_export_snapshot_destroy(snapshot)
	validation := authoring_production_validate(
		.Exportable,
		&snapshot.story,
		&snapshot.graph,
		&snapshot.level,
		nil,
		&authoring_workspace.assets,
		nil,
	); defer authoring_validation_snapshot_destroy(&validation)
	if authoring_validation_is_blocked(&validation) do return fmt.tprintf("EXPORT BLOCKED FOR %s BY SAVED-SNAPSHOT VALIDATION", item.id)
	config_path, ok := authoring_resolve_path(
		&active_authoring_project,
		config_relative,
	); if !ok do return "PACKAGE CONFIG PATH IS OUTSIDE PROJECT"
	if !os.exists(os.dir(config_path)) && os.make_directory_all(os.dir(config_path)) != nil do return "COULD NOT CREATE PACKAGE CONFIG DIRECTORY"
	assets := project_asset_plan_stage(
		&authoring_workspace.assets,
		active_authoring_project.root_path,
		"assets",
	); defer project_asset_stage_plan_destroy(&assets); if !assets.allowed do return "EXPORT BLOCKED BY ASSET REDISTRIBUTION OR INTEGRITY"
	include := len(assets.items) > 0 ? ",\"include\":[\"assets\"]" : ""
	config_text := fmt.tprintf(
		"{{\"author\":\"%s\",\"description\":\"%s\",\"content_version\":\"%s\",\"story\":\"%s\",\"level\":\"%s\",\"acknowledge_incomplete_validation\":true%s}}",
		authoring_json_escape_value(snapshot.story.creator),
		authoring_json_escape_value(snapshot.story.description),
		authoring_json_escape_value(snapshot.story.content_version),
		authoring_json_escape_value(item.paths.story),
		authoring_json_escape_value(item.paths.level),
		include,
	)
	if !authoring_atomic_write(config_path, config_text) do return "COULD NOT WRITE PACKAGE CONFIG"
	assembly := authoring_package_export_assemble(
		&active_authoring_project,
		.Story,
		{true, output_path},
		config_relative,
		&assets,
	); if !assembly.valid do return assembly.message
	result := authoring_workspace_action_export(
		assembly.export_request,
	); authoring_workspace.package_progress = result.progress; if result.ok && record_artifact do authoring_workspace.last_artifact = result.artifact; return result.message
}

authoring_workspace_export_package :: proc(
	output_path: string,
) -> string {return authoring_workspace_export_story_case(
		authoring_workspace_case(),
		output_path,
		"story.package.json",
		true,
		true,
	)}

authoring_workspace_export_wizard_begin :: proc(campaign: bool) {
	authoring_workspace.export_campaign =
		campaign; authoring_workspace.last_artifact = {}; authoring_workspace.package_progress = {}
	title :=
		active_story_project.title; version := active_story_project.content_version; dependencies := len(active_story_project.expansion_requirements); kind := Authoring_Artifact_Kind.Story; thumbnail := ""
	for asset in authoring_workspace.assets.assets do if asset.kind == .Thumbnail {thumbnail = asset.project_path; break}
	if campaign {title = campaign_document.title; version = campaign_document.content_version; dependencies = len(campaign_document.cases); kind = .Campaign; thumbnail = campaign_document.thumbnail}
	authoring_workspace.export_wizard = authoring_export_wizard_begin(
		title,
		version,
		thumbnail,
		dependencies,
		{kind = kind, source_root = active_authoring_project.root_path},
	)
	authoring_workspace.feedback = authoring_workspace.export_wizard.message
}

authoring_workspace_inspect_package :: proc(
	kind: Authoring_Artifact_Kind,
	title: string,
) -> string {path := authoring_native_open_file(title); if path == "" do return "PACKAGE SELECTION CANCELLED"
	result := authoring_workspace_action_inspect(path, kind)
	return result.message}

authoring_workspace_launch_selected :: proc() -> string {
	if len(authoring_workspace.library.installed) == 0 do return "SELECT AN INSTALLED STORY OR CAMPAIGN"
	item :=
		authoring_workspace.library.installed[clamp(authoring_workspace.selected_library, 0, len(authoring_workspace.library.installed) - 1)]
	if item.identity.kind ==
	   .Campaign {step := authoring_workspace_action_launch_campaign(); return step.ok ? "INSTALLED CAMPAIGN LAUNCHED AND COMPLETED" : step.message}
	if item.identity.kind != .Story do return "SELECTED CONTENT IS NOT DIRECTLY PLAYABLE"
	if authoring_workspace.inspection.artifact.identity != item.identity do return "INSPECT THE SELECTED STORY PACKAGE BEFORE LAUNCHING"
	story_path := ""; for file in authoring_workspace.inspection.files do if strings.has_suffix(file.path, ".story.toml") {story_path = file.path; break}
	if story_path == "" do return "INSTALLED STORY MANIFEST HAS NO PLAYABLE STORY PATH"
	step := authoring_workspace_action_launch_story(
		story_path,
	); return step.ok ? "INSTALLED STORY LAUNCHED AND COMPLETED" : step.message
}

authoring_workspace_discover_update :: proc() -> string {
	inspection := &authoring_workspace.inspection; if inspection.artifact.identity.id == "" do return "INSPECT A CANDIDATE PACKAGE TO CHECK FOR UPDATES"
	found :=
		false; newer := true; for installed in authoring_workspace.library.installed do if installed.identity.kind == inspection.artifact.identity.kind && installed.identity.id == inspection.artifact.identity.id {found = true; if authoring_semver_compare(inspection.artifact.identity.content_version, installed.identity.content_version) <= 0 do newer = false}
	if !found do return "NO INSTALLED VERSION MATCHES THIS CANDIDATE · USE COEXIST"
	if !newer do return "CANDIDATE IS NOT NEWER THAN EVERY INSTALLED VERSION"
	authoring_workspace.import_decision = int(
		Authoring_Import_Decision.Upgrade,
	); return fmt.tprintf("UPDATE AVAILABLE · %s@%s · UPGRADE ACTION SELECTED", inspection.artifact.identity.id, inspection.artifact.identity.content_version)
}

authoring_workspace_export_wizard_advance :: proc() -> string {
	wizard := &authoring_workspace.export_wizard
	switch wizard.stage {
	case .Summary, .Dependencies:
		result := authoring_export_wizard_advance(wizard); return result.message
	case .Validation:
		if authoring_workspace.export_campaign do authoring_workspace.production_validation = authoring_production_validate(.Exportable, &active_story_project, &graph_document, &level_document, &campaign_document, &authoring_workspace.assets, nil)
		else do authoring_workspace.production_validation = authoring_production_validate(.Exportable, &active_story_project, &graph_document, &level_document, nil, &authoring_workspace.assets, nil)
		result := authoring_export_wizard_advance(
			wizard,
			&authoring_workspace.production_validation,
		)
		return result.message
	case .Destination:
		suggested :=
			authoring_workspace.export_campaign ? fmt.tprintf("%s.mystery-campaign", campaign_document.id) : fmt.tprintf("%s.interactive-story", active_story_project.id)
		path := authoring_native_save_file(
			authoring_workspace.export_campaign ? "Export Campaign Package" : "Export Story Package",
			suggested,
		)
		result := authoring_export_wizard_advance(wizard, destination = path)
		return result.message
	case .Exporting:
		message :=
			authoring_workspace.export_campaign ? authoring_workspace_export_campaign_package(wizard.destination) : authoring_workspace_export_package(wizard.destination)
		service_result := Authoring_Service_Result {
			ok       = authoring_workspace.last_artifact.identity.id != "",
			message  = message,
			artifact = authoring_workspace.last_artifact,
			progress = authoring_workspace.package_progress,
		}
		result := authoring_export_wizard_advance(wizard, service_result = &service_result)
		if !result.ok do return message
		return result.message
	case .Result:
		return "EXPORT WIZARD COMPLETE"
	}
	return "EXPORT WIZARD UNAVAILABLE"
}

authoring_workspace_export_campaign_package :: proc(output_path: string) -> string {
	if !active_authoring_ready do return "NO ACTIVE SOURCE PROJECT"
	if active_authoring_read_only do return "INSTALLED CONTENT IS READ-ONLY"
	if saved := authoring_app_save_all(); !saved.ok do return saved.message
	campaign := &campaign_document; if campaign_workspace.open do campaign = &campaign_workspace.draft
	if valid := campaign_validate(campaign); !valid.ok do return fmt.tprintf("CAMPAIGN EXPORT BLOCKED: %s", valid.message)
	campaign_relative :=
		active_authoring_project.campaign_path; if campaign_relative == "" do campaign_relative = "campaign.toml"
	campaign_path, path_ok := authoring_resolve_path(
		&active_authoring_project,
		campaign_relative,
	); if !path_ok do return "CAMPAIGN PATH IS OUTSIDE PROJECT"
	if saved := save_campaign_manifest(campaign_path, campaign); !saved.ok do return saved.message
	export_relative :=
		active_authoring_project.export_directory; if export_relative == "" do export_relative = "exports"
	export_root, root_ok := authoring_resolve_path(
		&active_authoring_project,
		export_relative,
	); if !root_ok do return "EXPORT DIRECTORY IS OUTSIDE PROJECT"
	if !os.exists(export_root) && os.make_directory_all(export_root) != nil do return "COULD NOT CREATE CAMPAIGN EXPORT STAGING DIRECTORY"
	case_paths := ""; bundle := Authoring_Campaign_Bundle_Rule{}; defer delete(bundle.cases)
	for campaign_case, index in campaign.cases {
		project_index := authoring_project_case_index(
			&active_authoring_project,
			campaign_case.id,
		); if project_index < 0 do return fmt.tprintf("CAMPAIGN CASE %s HAS NO SOURCE PROJECT CASE", campaign_case.id)
		item := &active_authoring_project.cases[project_index]; artifact_relative := fmt.tprintf("%s/%s-%s.interactive-story", export_relative, campaign_case.id, campaign_case.case_content_version); artifact_path, artifact_ok := authoring_resolve_path(&active_authoring_project, artifact_relative); if !artifact_ok do return "CASE ARTIFACT PATH IS OUTSIDE PROJECT"
		config_relative := fmt.tprintf(".authoring/export/%s.package.json", campaign_case.id)
		message := authoring_workspace_export_story_case(
			item,
			artifact_path,
			config_relative,
			false,
			false,
		); if !strings.contains(strings.to_upper(message), "EXPORTED") do return fmt.tprintf("CAMPAIGN CASE %s: %s", campaign_case.id, message)
		snapshot := new(
			Authoring_Story_Export_Snapshot,
		); if loaded := authoring_story_export_snapshot_load(&active_authoring_project, item, snapshot); !loaded.ok {free(snapshot); return loaded.message}
		if snapshot.story.id != campaign_case.id ||
		   snapshot.story.content_version !=
			   campaign_case.case_content_version {authoring_story_export_snapshot_destroy(snapshot); free(snapshot); return fmt.tprintf("CAMPAIGN CASE PIN DOES NOT MATCH SAVED STORY: %s", campaign_case.id)}
		authoring_story_export_snapshot_destroy(snapshot); free(snapshot)
		if index > 0 do case_paths = fmt.tprintf("%s,", case_paths); case_paths = fmt.tprintf("%s\"%s\"", case_paths, authoring_json_escape_value(artifact_relative)); append(&bundle.cases, Authoring_Campaign_Bundle_Case{id = campaign_case.id, version = campaign_case.case_content_version, package_path = artifact_path})
	}
	config_relative := "campaign.package.json"; config_path, config_ok := authoring_resolve_path(&active_authoring_project, config_relative); if !config_ok do return "CAMPAIGN PACKAGE CONFIG PATH IS OUTSIDE PROJECT"
	config_text := fmt.tprintf(
		"{{\"campaign\":\"%s\",\"author\":\"%s\",\"description\":\"%s\",\"content_version\":\"%s\",\"cases\":[%s]}}",
		authoring_json_escape_value(campaign_relative),
		authoring_json_escape_value(campaign.creator),
		authoring_json_escape_value(campaign.description),
		authoring_json_escape_value(campaign.content_version),
		case_paths,
	)
	if !authoring_atomic_write(config_path, config_text) do return "COULD NOT WRITE CAMPAIGN PACKAGE CONFIG"
	assembly := authoring_package_export_assemble(
		&active_authoring_project,
		.Campaign,
		{true, output_path},
		config_relative,
		nil,
		&bundle,
	); if !assembly.valid do return assembly.message
	result := authoring_workspace_action_export(
		assembly.export_request,
	); authoring_workspace.package_progress = result.progress; if result.ok do authoring_workspace.last_artifact = result.artifact; return result.message
}
