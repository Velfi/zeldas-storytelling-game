package main

import "core:fmt"
import "core:os"
import "core:strings"

Authoring_Workspace_Tab :: enum {
	Project,
	Story_Data,
	Mystery,
	Diagnostics,
	Assets,
	Packages,
	Library,
}
Authoring_Form_Action :: enum {
	Add,
	Rename,
	Story_Field,
	Story_List_Add,
	Story_List_Create,
	Mystery_Text,
	Mystery_Number,
	Mystery_List_Add,
	Mystery_List_Create,
	Mystery_Route_Add,
	Project_Metadata,
	Project_Requirement_Add,
	Project_Requirement_Update,
	Case_Rename,
	Case_Move,
	Diagnostic_Search,
	Asset_Source_URI,
	Asset_Source_Name,
	Asset_Creator,
	Asset_Attribution,
	Asset_License_ID,
	Asset_License_Text,
	Asset_Usage,
}
Authoring_Pending_Lifecycle :: enum {
	None,
	Switch_Case,
	Open_Project,
	Close_Workspace,
}
Authoring_Playtest_Start_Mode :: enum {
	Opening,
	Selected_Scene,
	Selected_Node,
	Spatial_Position,
	Question,
	Reveal,
}
Authoring_Pending_Asset_Action :: enum {
	None,
	Replacement,
	Relink,
}
Authoring_Asset_Authored_Snapshot :: struct {
	story_entity,
	graph_node,
	level_object,
	catalog_entry:                                                                                                 int,
	story_appearance,
	story_font,
	graph_image,
	graph_sound,
	graph_animation,
	level_model,
	level_material,
	level_texture,
	catalog_model_ref,
	catalog_model: string,
}
Authoring_Workspace_State :: struct {
	tab:                                                                                                                                                                                   Authoring_Workspace_Tab,
	selected_category,
	selected_record,
	import_decision,
	asset_kind,
	asset_mode,
	asset_policy,
	selected_asset,
	selected_asset_usage,
	selected_library:                                     int,
	confirm_delete,
	asset_redistribution,
	form_active,
	recents_loaded,
	diagnostic_filter_ready,
	scenario_recording,
	playtest_spatial_saved,
	export_campaign:                               bool,
	playtest_player_x,
	playtest_player_y:                                                                                                                                                  f32,
	playtest_screen:                                                                                                                                                                       Screen,
	form_action:                                                                                                                                                                           Authoring_Form_Action,
	sequence:                                                                                                                                                                              int,
	pending_lifecycle:                                                                                                                                                                     Authoring_Pending_Lifecycle,
	pending_asset_action:                                                                                                                                                                  Authoring_Pending_Asset_Action,
	pending_case,
	selected_recent,
	diagnostic_domain,
	diagnostic_page,
	creator_category,
	creator_cursor,
	playtest_start_mode:                                                              int,
	feedback,
	picked_path,
	library_root,
	editable_root,
	pending_project_root,
	asset_source_uri,
	asset_source_name,
	asset_creator,
	asset_attribution,
	asset_license_id,
	asset_license_text: string,
	form_buffer:                                                                                                                                                                           [128]u8,
	form_count:                                                                                                                                                                            int,
	recents:                                                                                                                                                                               Authoring_Recent_Projects,
	diagnostic_filter:                                                                                                                                                                     Authoring_Diagnostic_Filter,
	creator_setup:                                                                                                                                                                         Authoring_Creator_State_Setup,
	scenario_record:                                                                                                                                                                       Authoring_Scenario_Record,
	scenario_last:                                                                                                                                                                         Authoring_Scenario_Replay_Result,
	story_history:                                                                                                                                                                         Story_Authoring_History,
	mystery_history:                                                                                                                                                                       Mystery_Authoring_History,
	asset_history:                                                                                                                                                                         Project_Asset_History,
	asset_campaign_undo,
	asset_campaign_redo:                                                                                                                                              [dynamic]string,
	assets:                                                                                                                                                                                Project_Asset_Registry,
	pending_asset_replacement:                                                                                                                                                             Project_Asset_Replacement_Preview,
	pending_asset_relink:                                                                                                                                                                  Project_Asset_Relink_Plan,
	diagnostics:                                                                                                                                                                           Story_Validation,
	production_validation:                                                                                                                                                                 Authoring_Validation_Snapshot,
	inspection:                                                                                                                                                                            Authoring_Package_Inspection,
	library:                                                                                                                                                                               Authoring_Library,
	playtest:                                                                                                                                                                              Authoring_Playtest_Coordinator,
	export_wizard:                                                                                                                                                                         Authoring_Export_Wizard,
	last_artifact:                                                                                                                                                                         Authoring_Portable_Package,
	package_progress:                                                                                                                                                                      Authoring_Service_Progress,
}
authoring_workspace: Authoring_Workspace_State
authoring_asset_authored_undo, authoring_asset_authored_redo: [dynamic]Authoring_Asset_Authored_Snapshot
authoring_story_field_cursor, authoring_story_list_cursor, authoring_story_list_item, authoring_story_picker_kind: int
authoring_mystery_field_cursor, authoring_mystery_list_cursor, authoring_mystery_list_item: int
authoring_project_metadata_cursor, authoring_project_requirement_kind, authoring_project_requirement_index: int

authoring_asset_audition_selected :: proc(g: ^Game) -> string {i :=
		authoring_workspace.selected_asset
	if i < 0 || i >= len(authoring_workspace.assets.assets) do return "SELECT AN AUDIO ASSET"
	asset := authoring_workspace.assets.assets[i]
	if asset.kind != .Audio do return "SELECTED ASSET IS NOT AUDIO"
	return(
		play_project_asset_audio(g, &authoring_workspace.assets, asset.id) ? "AUDITIONING SELECTED AUDIO" : "AUDIO PREVIEW COULD NOT START · VERIFY 44.1 KHZ PCM16 WAV OR OGG" \
	)}

authoring_asset_preview_project :: proc(
	v, min_v, max_v: Vec3,
	box: Rect,
	scale: f32,
) -> Vec2 {nx := v.x - (min_v.x + max_v.x) * .5; ny := v.y - (min_v.y + max_v.y) * .5; nz :=
		v.z - (min_v.z + max_v.z) * .5
	return{
		box.x + box.w * .5 + (nx - nz * .35) * scale,
		box.y + box.h * .5 - (ny + nz * .18) * scale,
	}}

vk_authoring_model_preview :: proc(
	r: ^Vulkan_Backend,
	asset: Project_Asset_Record,
	box: Rect,
) -> bool {
	path := project_asset_record_path(
		active_authoring_project.root_path,
		asset,
	); if !os.is_file(path) do return false
	mesh, ok := glb_load(
		path,
		context.temp_allocator,
	); if !ok || !mesh.ready || len(mesh.indices) < 3 do return false
	span_x := max(
		mesh.max.x - mesh.min.x,
		f32(.001),
	); span_y := max(mesh.max.y - mesh.min.y, f32(.001)); span_z := max(mesh.max.z - mesh.min.z, f32(.001)); scale := min(box.w / (span_x + span_z * .45), box.h / (span_y + span_z * .25)) * .82
	step := max(
		1,
		len(mesh.indices) / (240 * 3),
	); for triangle := 0; triangle + 2 < len(mesh.indices); triangle += 3 * step {a_i, b_i, c_i := int(mesh.indices[triangle]), int(mesh.indices[triangle + 1]), int(mesh.indices[triangle + 2]); if a_i >= len(mesh.vertices) || b_i >= len(mesh.vertices) || c_i >= len(mesh.vertices) do continue; a, b, c := authoring_asset_preview_project(mesh.vertices[a_i], mesh.min, mesh.max, box, scale), authoring_asset_preview_project(mesh.vertices[b_i], mesh.min, mesh.max, box, scale), authoring_asset_preview_project(mesh.vertices[c_i], mesh.min, mesh.max, box, scale); vk_editor_line(r, a, b, {102, 205, 235, 150}, 1); vk_editor_line(r, b, c, {117, 229, 169, 150}, 1); vk_editor_line(r, c, a, {255, 218, 112, 120}, 1)}
	return true
}
authoring_creator_truth_revealed: bool

Authoring_Story_Used_By_Target :: struct {
	workspace, record_kind, record_id, field: string,
	category, index:                          int,
	focusable:                                bool,
}
authoring_creator_truth_access :: proc(reveal: bool) -> string {authoring_creator_truth_revealed =
		reveal
	return reveal ? "CREATOR-ONLY TRUTH REVEALED" : "CREATOR-ONLY TRUTH HIDDEN"}

authoring_story_filter_indices :: proc(
	kind: Story_Authoring_Record_Kind,
	query: string,
) -> [dynamic]int {result: [dynamic]int; needle := strings.to_lower(strings.trim_space(query)); for 	i in 0 ..< authoring_story_count(kind) {id := authoring_story_id(kind, i); if needle == "" || strings.contains(strings.to_lower(id), needle) do append(&result, i)}
	return result}

authoring_story_used_by_target :: proc(
	kind: Story_Authoring_Record_Kind,
	id: string,
	dependency_index: int = 0,
) -> (
	Authoring_Story_Used_By_Target,
	bool,
) {preview := story_authoring_dependency_preview(&active_story_project, kind, id)
	if dependency_index < 0 || dependency_index >= preview.dependency_count do return {}, false
	dependency := preview.dependencies[dependency_index]
	target := Authoring_Story_Used_By_Target {
		workspace   = "story",
		record_kind = dependency.record_kind,
		record_id   = dependency.record_id,
		field       = dependency.field,
		category    = -1,
		index       = -1,
	}
	for candidate in Story_Authoring_Record_Kind {if strings.to_lower(
			   fmt.tprintf("%v", candidate),
		   ) ==
		   dependency.record_kind {target.category = int(candidate); for i in 0 ..< authoring_story_count(candidate) do if authoring_story_id(candidate, i) == dependency.record_id {target.index = i; target.focusable = true}
			return target, true}}
	if dependency.record_kind == "node" || dependency.record_kind == "scene" do target.workspace = "graph"
	else if strings.has_prefix(dependency.record_kind, "mystery.") do target.workspace = "mystery"
	return target, true}

authoring_story_focus_first_usage :: proc(
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> string {target, ok := authoring_story_used_by_target(kind, id); if !ok do return "RECORD HAS NO USAGES"
	if target.focusable {authoring_workspace.tab = .Story_Data
		authoring_workspace.selected_category = target.category
		authoring_workspace.selected_record = target.index}
	return fmt.tprintf(
		"USED BY · %s / %s / %s / %s",
		target.workspace,
		target.record_kind,
		target.record_id,
		target.field,
	)}

// Production action boundary for Story data. Automation and acceptance use the
// same atomic command transaction, undo history, validation invalidation, and
// Graph synchronization as the interactive workspace.
authoring_workspace_apply_story_commands :: proc(
	commands: []Story_Authoring_Command,
) -> Story_Authoring_Result {
	result := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		commands,
	)
	if result.ok {
		graph_import_story(&active_story_project)
		authoring_workspace.feedback = result.message
	}
	return result
}

authoring_project_commit :: proc(command: Story_Authoring_Command) -> string {commands :=
		[1]Story_Authoring_Command{command}
	result := authoring_workspace_apply_story_commands(commands[:])
	message := result.message
	story_authoring_result_destroy(&result)
	return message}
authoring_project_metadata_field :: proc() -> (string, string) {switch
	authoring_project_metadata_cursor %
	6 {case 0:
		return "id", active_story_project.id; case 1:
		return "title", active_story_project.title; case 2:
		return "creator", active_story_project.creator; case 3:
		return "description", active_story_project.description; case 4:
		return "content version", active_story_project.content_version; case:
		return "default space", active_story_project.default_space_id}}
authoring_project_set_metadata :: proc(value: string) -> string {m := Story_Authoring_Metadata {
		active_story_project.id,
		active_story_project.title,
		active_story_project.creator,
		active_story_project.description,
		active_story_project.content_version,
		active_story_project.default_space_id,
	}
	switch
	authoring_project_metadata_cursor %
	6 {case 0:
		m.id = value; case 1:
		m.title = value; case 2:
		m.creator = value; case 3:
		m.description = value; case 4:
		m.content_version = value; case 5:
		m.default_space_id = value}
	return authoring_project_commit({kind = .Set_Metadata, metadata = m})}
authoring_project_requirement_count :: proc() -> int {return(
		authoring_project_requirement_kind == 0 ? len(active_story_project.expansion_requirements) : len(active_story_project.capabilities) \
	)}
authoring_project_requirement_label :: proc() -> string {count :=
		authoring_project_requirement_count()
	if count == 0 do return "NONE"
	i := clamp(authoring_project_requirement_index, 0, count - 1)
	if authoring_project_requirement_kind == 0 {r := active_story_project.expansion_requirements[i]
		return fmt.tprintf(
			"%s@%s · %v / %v / %v",
			r.id,
			r.version,
			r.optional,
			r.distribution,
			r.fallback,
		)}
	r := active_story_project.capabilities[i]
	return fmt.tprintf("%s@%s%s", r.id, r.version, r.payload != nil ? " · PAYLOAD" : "")}
authoring_project_requirement_parse :: proc(value: string) -> (string, string, bool) {parts :=
		strings.split(strings.trim_space(value), "@")
	if len(parts) != 2 do return "", "", false
	id := strings.trim_space(parts[0])
	version := strings.trim_space(parts[1])
	return id, version, story_authoring_valid_id(id) && version != ""}
authoring_project_requirement_commit :: proc(
	value: string,
	update: bool,
) -> string {id, version, ok := authoring_project_requirement_parse(value); if !ok do return "USE ID@VERSION"
	i := authoring_project_requirement_index
	if authoring_project_requirement_kind == 0 {r := Story_Expansion_Requirement {
				id       = id,
				version  = version,
				optional = true,
				fallback = .Omit,
			}; if update {if i < 0 || i >= len(active_story_project.expansion_requirements) do return "NO EXPANSION SELECTED"; old := active_story_project.expansion_requirements[i]; r.optional = old.optional; r.distribution = old.distribution; r.fallback = old.fallback}; return authoring_project_commit(
			{kind = update ? .Update_Expansion : .Add_Expansion, expansion = r, from = i},
		)}
	r := Story_Capability_Requirement {
			id      = id,
			version = version,
		}
	if update {if i < 0 || i >= len(active_story_project.capabilities) do return "NO CAPABILITY SELECTED"
		old := active_story_project.capabilities[i]
		if old.id == id && old.version == version do r.payload = old.payload}
	return authoring_project_commit(
		{kind = update ? .Update_Capability : .Add_Capability, capability = r, from = i},
	)}
authoring_project_requirement_action :: proc(
	kind: Story_Authoring_Command_Kind,
	delta: int = 0,
) -> string {count := authoring_project_requirement_count(); if count == 0 do return "NO REQUIREMENT SELECTED"
	i := clamp(authoring_project_requirement_index, 0, count - 1)
	command := Story_Authoring_Command {
			kind = kind,
			from = i,
			to   = clamp(i + delta, 0, count - 1),
		}
	message := authoring_project_commit(command)
	if strings.contains(message, "committed") do authoring_project_requirement_index = clamp(command.to, 0, max(0, authoring_project_requirement_count() - 1))
	return message}
authoring_project_expansion_toggle :: proc(field: int) -> string {if len(active_story_project.expansion_requirements) == 0 do return "NO EXPANSION SELECTED"
	i := clamp(
		authoring_project_requirement_index,
		0,
		len(active_story_project.expansion_requirements) - 1,
	)
	r := active_story_project.expansion_requirements[i]
	switch
	field {case 0:
		r.optional = !r.optional
		if r.optional && r.fallback == .None do r.fallback = .Omit; case 1:
		r.distribution = r.distribution == .Reference ? .Embed : .Reference; case 2:
		r.fallback = r.fallback == .None ? .Omit : .None; if r.fallback == .None do r.optional = false}
	return authoring_project_commit({kind = .Update_Expansion, expansion = r, from = i})}
authoring_project_begin_form :: proc(
	action: Authoring_Form_Action,
	value: string = "",
) {authoring_workspace.form_active = true; authoring_workspace.form_action = action
	authoring_workspace.form_count = min(len(value), len(authoring_workspace.form_buffer))
	copy(authoring_workspace.form_buffer[:authoring_workspace.form_count], transmute([]u8)value)}

authoring_mystery_support_record :: proc(
	id: string,
) -> (
	Mystery_Authoring_Record_Kind,
	int,
	bool,
) {
	payload := mystery_payload(&active_story_project); if payload == nil do return {}, 0, false
	for item, i in payload.clues do if item.id == id do return .Clue, i, true
	for item, i in payload.claims do if item.id == id do return .Claim, i, true
	for item, i in payload.deductions do if item.id == id do return .Deduction, i, true
	for item, i in payload.questions do if item.id == id do return .Question, i, true
	if id == "solution" do return .Solution, 0, true
	return {}, 0, false
}

authoring_mystery_focus_support_record :: proc(kind: Mystery_Authoring_Record_Kind, index: int) {
	authoring_workspace.selected_category = int(kind); authoring_workspace.selected_record = index
	authoring_workspace.feedback = fmt.tprintf(
		"FOCUSED %v · %s",
		kind,
		authoring_mystery_id(kind, index),
	)
}

// Returns one directed evidence edge for the route/support inspectors. Unknown
// references remain visible with a -1 source so broken authoring links can be seen.
authoring_mystery_panel_edge :: proc(
	panel, row: int,
) -> (
	string,
	Mystery_Authoring_Record_Kind,
	int,
	string,
	Mystery_Authoring_Record_Kind,
	int,
	bool,
) {
	payload := mystery_payload(
		&active_story_project,
	); if payload == nil || row < 0 do return "", {}, -1, "", {}, -1, false
	n := 0
	if panel == 16 {
		for clue, ci in payload.clues {for i in 0 ..< clue.prerequisite_count {if n == row {id := clue.prerequisites[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, clue.id, .Clue, ci, true}; n += 1}}
	}
	for deduction, di in payload.deductions {for i in 0 ..< deduction.support_count {if n == row {id := deduction.supports[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, deduction.id, .Deduction, di, true}; n += 1}}
	for question, qi in payload.questions {
		for i in 0 ..< question.require_clue_count {if n == row {id := question.requires_clues[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, question.id, .Question, qi, true}; n += 1}
		for i in 0 ..< question.require_claim_count {if n == row {id := question.requires_claims[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, question.id, .Question, qi, true}; n += 1}
		for i in 0 ..< question.require_deduction_count {if n == row {id := question.requires_deductions[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, question.id, .Question, qi, true}; n += 1}
		if panel ==
		   16 {for i in 0 ..< question.dependency_count {if n == row {id := question.dependencies[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, question.id, .Question, qi, true}; n += 1}}
	}
	for i in 0 ..< payload.solution.requirement_count {if n == row {id := payload.solution.requirements[i]; kind, index, found := authoring_mystery_support_record(id); return id, kind, found ? index : -1, "solution", .Solution, 0, true}; n += 1}
	if panel ==
	   17 {for i in 0 ..< payload.solution.exclusion_count {if n == row {id := payload.solution.exclusions[i]; index := mystery_authoring_character_index(payload, id); return id, .Character, index, "solution", .Solution, 0, true}; n += 1}}
	return "", {}, -1, "", {}, -1, false
}

authoring_mystery_panel_edge_count :: proc(panel: int) -> int {for row := 0;;
	    row += 1 {_, _, _, _, _, _, ok := authoring_mystery_panel_edge(panel, row)
		if !ok do return row}
	return 0}

authoring_native_open_file :: proc(title: string) -> string {when ODIN_OS ==
	.Darwin {c, _ := strings.clone_to_cstring(title, context.temp_allocator); path :=
			chicago_editor_open_file(c)
		if path != nil do return strings.clone(string(path))}
	return ""}
authoring_native_save_file :: proc(title, suggested: string) -> string {when ODIN_OS ==
	.Darwin {a, _ := strings.clone_to_cstring(title, context.temp_allocator); b, _ :=
			strings.clone_to_cstring(suggested, context.temp_allocator)
		path := chicago_editor_save_file(a, b)
		if path != nil do return strings.clone(string(path))}
	return ""}
authoring_native_select_directory :: proc(title: string) -> string {when ODIN_OS ==
	.Darwin {c, _ := strings.clone_to_cstring(title, context.temp_allocator); path :=
			chicago_editor_select_directory(c)
		if path != nil do return strings.clone(string(path))}
	return ""}
authoring_native_reveal_path :: proc(path: string) -> bool {when ODIN_OS ==
	.Darwin {c, error := strings.clone_to_cstring(path, context.temp_allocator); if error == nil do return chicago_editor_reveal_path(c)}
	return false}

authoring_workspace_begin :: proc(g: ^Game) {authoring_workspace.tab = .Project
	if !authoring_workspace.recents_loaded {if path, ok := authoring_recents_default_path(); ok {_ = authoring_recents_load(path, &authoring_workspace.recents)}
		authoring_workspace.recents_loaded = true}
	if len(authoring_workspace.creator_setup.variables) == 0 &&
	   len(authoring_workspace.creator_setup.knowledge) == 0 &&
	   authoring_workspace.creator_setup.action_budget == 0 &&
	   authoring_workspace.creator_setup.time_minutes ==
		   0 {authoring_workspace.creator_setup.action_budget = -1
		authoring_workspace.creator_setup.time_minutes = -1}
	authoring_workspace.feedback = "AUTHORING PROJECT READY"
	g.screen = .Authoring}
authoring_workspace_case :: proc() -> ^Authoring_Case {return authoring_project_active_case(
		&active_authoring_project,
	)}
authoring_workspace_next_id :: proc(prefix: string) -> string {authoring_workspace.sequence += 1
	return fmt.tprintf("%s_%d", prefix, authoring_workspace.sequence)}

// Production create-and-return bridge used by Graph reference pickers. Graph
// definitions stay in the live graph document; spatial and mystery records use
// their normal transactional authoring paths.
authoring_graph_picker_create :: proc(
	field: Graph_Field,
	suggested_id: string,
	userdata: rawptr,
) -> (
	string,
	bool,
) {
	id := strings.trim_space(suggested_id); if !story_authoring_valid_id(id) do return "", false
	if field ==
	   .Condition {if story_condition_index_in_document(id) >= 0 || !graph_add_condition() do return "", false; graph_document.conditions[graph_state.selected_condition].id = id; graph_changed(); return id, true}
	if field ==
	   .Effects {if story_effect_index_in_document(id) >= 0 || !graph_add_effect() do return "", false; graph_document.effects[graph_state.selected_effect].id = id; graph_changed(); return id, true}
	if field ==
	   .Clue {payload := mystery_payload(&active_story_project); if payload == nil || mystery_clue_index(payload, id) >= 0 do return "", false; old_category, old_record := authoring_workspace.selected_category, authoring_workspace.selected_record; authoring_workspace.selected_category = int(Mystery_Authoring_Record_Kind.Clue); authoring_workspace.selected_record = max(0, len(payload.clues) - 1); message := authoring_workspace_add_mystery_from_selected(id); authoring_workspace.selected_category, authoring_workspace.selected_record = old_category, old_record; return id, strings.contains(message, "committed")}
	kind := Level_Marker_Kind.Camera; reference := ""; result := id
	#partial switch field {case .Camera:
		kind = .Camera; case .Actor_Mark:
		kind = .Staging; case .Interaction:
		kind = .Interaction; reference = id; result = id
		id = fmt.tprintf("marker_%s", id); case .Event:
		kind = .Trigger; reference = id; result = id; id = fmt.tprintf("marker_%s", id); case:
		return "", false}
	if level_marker_index(&level_document, id) >= 0 do return "", false
	position := Vec2{}; command := Level_Command {
			kind      = .Add_Marker,
			entity_id = id,
			a         = position,
			b         = {1, 0},
			c         = {2, f32(kind)},
			material  = reference,
			value     = f32(level_document.active_story),
		}
	if !level_commit_transaction(&level_document, command, "Create Graph picker marker") do return "", false
	return result, true
}

authoring_story_count :: proc(kind: Story_Authoring_Record_Kind) -> int {#partial switch
	kind {case .Entity:
		return len(active_story_project.entities); case .Role:
		return len(active_story_project.roles); case .Variable:
		return len(active_story_project.variables); case .Fact:
		return len(active_story_project.facts); case .Proposition:
		return len(active_story_project.propositions); case .Knowledge:
		return len(active_story_project.initial_knowledge); case .Relationship:
		return len(active_story_project.relationships); case .Event:
		return len(active_story_project.events); case .Objective:
		return len(active_story_project.objectives); case .Ending:
		return len(active_story_project.endings); case .Storylet_Group:
		return len(active_story_project.storylet_groups); case .Storylet:
		return len(active_story_project.storylets); case .Invariant:
		return len(active_story_project.invariants); case .Condition:
		return len(active_story_project.conditions); case .Effect:
		return len(active_story_project.effects)}
	return 0}
authoring_story_id :: proc(kind: Story_Authoring_Record_Kind, index: int) -> string {if index < 0 || index >= authoring_story_count(kind) do return ""
	#partial switch
	kind {case .Entity:
		return active_story_project.entities[index].id; case .Role:
		return active_story_project.roles[index].id; case .Variable:
		return active_story_project.variables[index].id; case .Fact:
		return active_story_project.facts[index].id; case .Proposition:
		return active_story_project.propositions[index].id; case .Knowledge:
		return fmt.tprintf(
			"%s/%s",
			active_story_project.initial_knowledge[index].actor_id,
			active_story_project.initial_knowledge[index].proposition_id,
		); case .Relationship:
		return active_story_project.relationships[index].id; case .Event:
		return active_story_project.events[index].id; case .Objective:
		return active_story_project.objectives[index].id; case .Ending:
		return active_story_project.endings[index].id; case .Storylet_Group:
		return active_story_project.storylet_groups[index].id; case .Storylet:
		return active_story_project.storylets[index].id; case .Invariant:
		return active_story_project.invariants[index].id; case .Condition:
		return active_story_project.conditions[index].id; case .Effect:
		return active_story_project.effects[index].id}
	return ""}
authoring_mystery_count :: proc(kind: Mystery_Authoring_Record_Kind) -> int {payload :=
		mystery_payload(&active_story_project)
	if payload == nil do return 0
	#partial switch
	kind {case .Setup, .Solution:
		return 1; case .Character:
		return len(payload.characters); case .Location:
		return len(payload.locations); case .POI:
		return len(payload.pois); case .Event:
		return len(payload.events); case .Clue:
		return len(payload.clues); case .Claim:
		return len(payload.claims); case .Contradiction:
		return len(payload.contradictions); case .Deduction:
		return len(payload.deductions); case .Question:
		return len(payload.questions); case .Demonstration:
		return len(payload.demonstrations); case .Dialogue:
		return len(payload.dialogue); case .Ending:
		return len(payload.endings); case .City_Label:
		return len(payload.city_labels); case .Tutorial_Lesson:
		return len(payload.tutorial_lessons)}
	return 0}
authoring_mystery_id :: proc(
	kind: Mystery_Authoring_Record_Kind,
	index: int,
) -> string {payload := mystery_payload(&active_story_project); if payload == nil || index < 0 || index >= authoring_mystery_count(kind) do return ""
	#partial switch
	kind {case .Setup:
		return "setup"; case .Solution:
		return "solution"; case .Character:
		return payload.characters[index].entity_id; case .Location:
		return payload.locations[index].entity_id; case .POI:
		return payload.pois[index].entity_id; case .Event:
		return payload.events[index].event_id; case .Clue:
		return payload.clues[index].id; case .Claim:
		return payload.claims[index].id; case .Contradiction:
		return payload.contradictions[index].id; case .Deduction:
		return payload.deductions[index].id; case .Question:
		return payload.questions[index].id; case .Demonstration:
		return payload.demonstrations[index].id; case .Dialogue:
		return payload.dialogue[index].node_id; case .Ending:
		return payload.endings[index].ending_id; case .City_Label:
		return payload.city_labels[index].id; case .Tutorial_Lesson:
		return payload.tutorial_lessons[index].id}
	return ""}
authoring_workspace_story_command :: proc(
	kind: Story_Authoring_Command_Kind,
	value: string = "",
) -> string {record_kind := Story_Authoring_Record_Kind(
		clamp(authoring_workspace.selected_category, 0, int(Story_Authoring_Record_Kind.Effect)),
	)
	count := authoring_story_count(record_kind)
	if count == 0 do return "NO SELECTED RECORD"
	authoring_workspace.selected_record = clamp(authoring_workspace.selected_record, 0, count - 1)
	id := authoring_story_id(record_kind, authoring_workspace.selected_record)
	if record_kind == .Knowledge && (kind == .Rename || kind == .Duplicate) do return "KNOWLEDGE USES ACTOR / PROPOSITION FIELDS"
	command := Story_Authoring_Command {
		kind        = kind,
		record_kind = record_kind,
		id          = id,
		new_id      = value,
		from        = authoring_workspace.selected_record,
		to          = authoring_workspace.selected_record,
	}
	if kind == .Reorder {command.to = clamp(
			authoring_workspace.selected_record + (value == "up" ? -1 : 1),
			0,
			count - 1,
		)}
	commands := [1]Story_Authoring_Command{command}
	result := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		commands[:],
	)
	ok := result.ok
	message := result.message
	story_authoring_result_destroy(&result)
	if ok {authoring_workspace.selected_record = command.to; graph_import_story(
			&active_story_project,
		)}
	return message}
authoring_workspace_mystery_command :: proc(
	kind: Mystery_Authoring_Command_Kind,
	value: string = "",
) -> string {record_kind := Mystery_Authoring_Record_Kind(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Mystery_Authoring_Record_Kind.Solution),
		),
	)
	count := authoring_mystery_count(record_kind)
	if count == 0 do return "NO SELECTED RECORD"
	if record_kind == .Setup || record_kind == .Solution do return "SETUP AND SOLUTION ARE SINGLETON FIELD EDITORS"
	authoring_workspace.selected_record = clamp(authoring_workspace.selected_record, 0, count - 1)
	command := Mystery_Authoring_Command {
		kind        = kind,
		record_kind = record_kind,
		id          = authoring_mystery_id(record_kind, authoring_workspace.selected_record),
		new_id      = value,
		from        = authoring_workspace.selected_record,
		to          = authoring_workspace.selected_record,
	}
	if kind == .Reorder do command.to = clamp(authoring_workspace.selected_record + (value == "up" ? -1 : 1), 0, count - 1)
	commands := [1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	ok := result.ok
	message := result.message
	mystery_authoring_result_destroy(&result)
	if ok do authoring_workspace.selected_record = command.to
	return message}

authoring_workspace_duplicate_story :: proc() -> string {kind := Story_Authoring_Record_Kind(
		clamp(authoring_workspace.selected_category, 0, int(Story_Authoring_Record_Kind.Effect)),
	)
	index := authoring_workspace.selected_record
	if index < 0 || index >= authoring_story_count(kind) do return "NO SELECTED RECORD"
	if kind == .Knowledge do return "KNOWLEDGE IS CREATED BY ACTOR / PROPOSITION PICKERS"
	command := Story_Authoring_Command {
		kind        = .Duplicate,
		record_kind = kind,
		new_id      = authoring_workspace_next_id(authoring_story_id(kind, index)),
	}
	#partial switch
	kind {case .Entity:
		command.entity = active_story_project.entities[index]; case .Role:
		command.role = active_story_project.roles[index]; case .Variable:
		command.variable = active_story_project.variables[index]; case .Fact:
		command.fact = active_story_project.facts[index]; case .Proposition:
		command.proposition = active_story_project.propositions[index]; case .Relationship:
		command.relationship = active_story_project.relationships[index]; case .Event:
		command.event = active_story_project.events[index]; case .Objective:
		command.objective = active_story_project.objectives[index]; case .Ending:
		command.ending = active_story_project.endings[index]; case .Storylet_Group:
		command.storylet_group = active_story_project.storylet_groups[index]; case .Storylet:
		command.storylet = active_story_project.storylets[index]; case .Invariant:
		command.invariant = active_story_project.invariants[index]; case .Condition:
		command.condition = active_story_project.conditions[index]; case .Effect:
		command.effect = active_story_project.effects[index]; case .Knowledge:
		return "KNOWLEDGE IS CREATED BY ACTOR / PROPOSITION PICKERS"}
	commands := [1]Story_Authoring_Command{command}
	result := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		commands[:],
	)
	ok := result.ok
	message := result.message
	story_authoring_result_destroy(&result)
	if ok {authoring_workspace.selected_record = authoring_story_count(kind) - 1
		graph_import_story(&active_story_project)}
	return message}
