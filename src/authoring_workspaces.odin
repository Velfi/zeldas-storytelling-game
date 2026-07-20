package main

import "core:fmt"
import "core:os"
import "core:strconv"
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

authoring_mystery_default_add :: proc(
	kind: Mystery_Authoring_Record_Kind,
	id: string,
	payload: ^Mystery_Project,
) -> (
	Mystery_Authoring_Command,
	string,
) {
	command := Mystery_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}; first_entity :=
		len(active_story_project.entities) > 0 ? active_story_project.entities[0].id : ""; first_proposition := len(active_story_project.propositions) > 0 ? active_story_project.propositions[0].id : ""
	#partial switch kind {
	case .Character:
		command.character = {
			entity_id = id,
		}
	case .Location:
		command.location = {
			entity_id = id,
		}
	case .POI:
		command.poi = {
			entity_id          = id,
			location_id        = len(payload.locations) > 0 ? payload.locations[0].entity_id : "",
			examination_action = "examine",
		}
	case .Event:
		command.event = {
			event_id       = id,
			destination_id = len(payload.locations) > 0 ? payload.locations[0].entity_id : "",
		}
	case .Clue:
		command.clue = {
			id             = id,
			source_id      = first_entity,
			description    = "New evidence",
			proposition_id = first_proposition,
			skill          = "Observation",
			check_kind     = "white",
			cost           = 0,
		}
	case .Claim:
		if first_entity == "" do return {}, "ADD A STORY ENTITY BEFORE A CLAIM"; command.claim = {
			id             = id,
			speaker_id     = first_entity,
			proposition_id = first_proposition,
		}
	case .Contradiction:
		if len(payload.claims) == 0 do return {}, "ADD A CLAIM BEFORE A CONTRADICTION"
		command.contradiction = {
			id            = id,
			claim_id      = payload.claims[0].id,
			conclusion_id = first_proposition,
			explanation   = "New contradiction",
		}
	case .Deduction:
		command.deduction = {
			id       = id,
			category = "general",
		}
	case .Question:
		command.question = {
			id       = id,
			prompt   = "New question",
			category = "general",
		}
	case .Demonstration:
		if len(payload.questions) == 0 do return {}, "ADD A QUESTION BEFORE A DEMONSTRATION"
		command.demonstration = {
			id              = id,
			question_id     = payload.questions[0].id,
			mode            = "evidence",
			presentation    = "slots",
			candidate_limit = 5,
			resolution      = "resolve",
			result          = "result",
			prompt          = "Demonstrate",
		}
	case .Dialogue:
		command.dialogue = {
			node_id = id,
		}
	case .Ending:
		command.ending = {
			ending_id      = id,
			trigger        = "solution",
			outcome        = "resolved",
			subtitle       = "Resolved",
			epilogue       = "Case closed",
			primary_label  = "Continue",
			primary_action = "continue",
		}
	case .City_Label:
		command.city_label = {
			id           = id,
			display_name = "New Destination",
			level_spawn  = "spawn_player",
			city_site    = id,
		}
	case .Tutorial_Lesson:
		command.tutorial_lesson = {
			id         = id,
			capability = fmt.tprintf("lesson.%s", id),
			prompt     = "New tutorial lesson",
		}
	case .Setup, .Solution:
		return {}, "SETUP AND SOLUTION ALREADY EXIST"
	}; return command, ""
}

authoring_workspace_add_mystery_from_selected :: proc(id: string) -> string {payload :=
		mystery_payload(&active_story_project)
	kind := Mystery_Authoring_Record_Kind(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Mystery_Authoring_Record_Kind.Solution),
		),
	)
	if payload == nil do return "ACTIVE STORY IS NOT A MYSTERY"
	if kind == .Setup || kind == .Solution do return "SETUP AND SOLUTION ALREADY EXIST"
	index := authoring_workspace.selected_record
	command := Mystery_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}
	if authoring_mystery_count(kind) > 0 {index = clamp(
			index,
			0,
			authoring_mystery_count(kind) - 1,
		)
		#partial switch
		kind {case .Character:
			command.character = payload.characters[index]
			command.character.entity_id = id; case .Location:
			command.location = payload.locations[index]
			command.location.entity_id = id; case .POI:
			command.poi = payload.pois[index]; command.poi.entity_id = id; case .Event:
			command.event = payload.events[index]; command.event.event_id = id; case .Clue:
			command.clue = payload.clues[index]; command.clue.id = id; case .Claim:
			command.claim = payload.claims[index]; command.claim.id = id; case .Contradiction:
			command.contradiction = payload.contradictions[index]
			command.contradiction.id = id; case .Deduction:
			command.deduction = payload.deductions[index]
			command.deduction.id = id; case .Question:
			command.question = payload.questions[index]
			command.question.id = id; case .Demonstration:
			command.demonstration = payload.demonstrations[index]
			command.demonstration.id = id; case .Dialogue:
			command.dialogue = payload.dialogue[index]
			command.dialogue.node_id = id; case .Ending:
			command.ending = payload.endings[index]
			command.ending.ending_id = id; case .City_Label:
			command.city_label = payload.city_labels[index]
			command.city_label.id = id; case .Tutorial_Lesson:
			command.tutorial_lesson = payload.tutorial_lessons[index]
			command.tutorial_lesson.id = id; case .Setup, .Solution:}}
	else {message: string; command, message = authoring_mystery_default_add(kind, id, payload)
		if message != "" do return message}
	prepared_story := false
	if (kind == .Character || kind == .Location || kind == .POI) &&
	   story_entity_index(&active_story_project, id) < 0 {prep := [1]Story_Authoring_Command {
			{
				kind = .Add,
				record_kind = .Entity,
				entity = {
					id = id,
					kind = kind == .Character ? "person" : "place",
					display_name = id,
				},
			},
		}
		prepared := story_authoring_apply(
			&active_story_project,
			&authoring_workspace.story_history,
			prep[:],
		)
		prepared_story = prepared.ok
		message := prepared.message
		story_authoring_result_destroy(&prepared)
		if !prepared_story do return message}
	if kind == .Ending {found := false; for ending in active_story_project.endings do if ending.id == id do found = true
		if !found {prep := [1]Story_Authoring_Command {
				{
					kind = .Add,
					record_kind = .Ending,
					ending = {id = id, title = "New Ending", condition_id = "always"},
				},
			}
			prepared := story_authoring_apply(
				&active_story_project,
				&authoring_workspace.story_history,
				prep[:],
			)
			prepared_story = prepared.ok
			message := prepared.message
			story_authoring_result_destroy(&prepared)
			if !prepared_story do return message}}
	commands := [1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	ok := result.ok
	message := result.message
	if !ok && len(result.validation.diagnostics) > 0 do message = fmt.tprintf("%s · %s", message, result.validation.diagnostics[0].message)
	mystery_authoring_result_destroy(&result)
	if !ok && prepared_story do _ = story_authoring_undo(&active_story_project, &authoring_workspace.story_history)
	if ok do authoring_workspace.selected_record = authoring_mystery_count(kind) - 1
	return message}

// Shared by every typed adapter. Counts remain authoritative, unused slots are
// cleared, and callers commit the containing record through an Update command.
authoring_reference_insert :: proc(
	values: ^[$N]string,
	count: ^int,
	at: int,
	value: string,
) -> bool {if value == "" || count^ < 0 || count^ >= N do return false; for i in 0 ..< count^ do if values[i] == value do return false
	index := clamp(at, 0, count^)
	for i := count^; i > index; i -= 1 do values[i] = values[i - 1]
	values[index] = value
	count^ += 1
	return true}
authoring_reference_remove :: proc(
	values: ^[$N]string,
	count: ^int,
	at: int,
) -> bool {if count^ <= 0 || at < 0 || at >= count^ do return false; for i in at + 1 ..< count^ do values[i - 1] = values[i]
	count^ -= 1
	values[count^] = ""
	return true}
authoring_reference_reorder :: proc(
	values: ^[$N]string,
	count: int,
	from, to: int,
) -> bool {if from < 0 || to < 0 || from >= count || to >= count do return false; item :=
		values[from]
	if from < to {for i in from ..< to do values[i] = values[i + 1]}
	else {for i := from; i > to; i -= 1 do values[i] = values[i - 1]}
	values[to] = item
	return true}

authoring_mystery_selected_update :: proc() -> (Mystery_Authoring_Command, bool) {payload :=
		mystery_payload(&active_story_project)
	kind := Mystery_Authoring_Record_Kind(
		clamp(
			authoring_workspace.selected_category,
			0,
			int(Mystery_Authoring_Record_Kind.Solution),
		),
	)
	if payload == nil do return {}, false
	index := clamp(
		authoring_workspace.selected_record,
		0,
		max(0, authoring_mystery_count(kind) - 1),
	)
	command := Mystery_Authoring_Command {
		kind        = .Update,
		record_kind = kind,
	}
	#partial switch
	kind {case .Setup:
		command.setup = {
			payload.action_budget,
			payload.seed,
			payload.tutorial_id,
			payload.city_start,
			payload.city_destination,
			payload.reveal_location,
		}; case .Character:
		if len(payload.characters) == 0 do return {}, false
		command.character = payload.characters[index]; case .Location:
		if len(payload.locations) == 0 do return {}, false
		command.location = payload.locations[index]; case .POI:
		if len(payload.pois) == 0 do return {}, false
		command.poi = payload.pois[index]; case .Event:
		if len(payload.events) == 0 do return {}, false
		command.event = payload.events[index]; case .Clue:
		if len(payload.clues) == 0 do return {}, false
		command.clue = payload.clues[index]; case .Claim:
		if len(payload.claims) == 0 do return {}, false
		command.claim = payload.claims[index]; case .Contradiction:
		if len(payload.contradictions) == 0 do return {}, false
		command.contradiction = payload.contradictions[index]; case .Deduction:
		if len(payload.deductions) == 0 do return {}, false
		command.deduction = payload.deductions[index]; case .Question:
		if len(payload.questions) == 0 do return {}, false
		command.question = payload.questions[index]; case .Demonstration:
		if len(payload.demonstrations) == 0 do return {}, false
		command.demonstration = payload.demonstrations[index]; case .Dialogue:
		if len(payload.dialogue) == 0 do return {}, false
		command.dialogue = payload.dialogue[index]; case .Ending:
		if len(payload.endings) == 0 do return {}, false
		command.ending = payload.endings[index]; case .City_Label:
		if len(payload.city_labels) == 0 do return {}, false
		command.city_label = payload.city_labels[index]; case .Tutorial_Lesson:
		if len(payload.tutorial_lessons) == 0 do return {}, false
		command.tutorial_lesson = payload.tutorial_lessons[index]; case .Solution:
		command.solution = payload.solution}
	return command, true}
authoring_mystery_commit_update :: proc(command: Mystery_Authoring_Command) -> string {commands :=
		[1]Mystery_Authoring_Command{command}
	result := mystery_authoring_apply(
		&active_story_project,
		&authoring_workspace.mystery_history,
		commands[:],
	)
	message := result.message
	mystery_authoring_result_destroy(&result)
	return message}
authoring_mystery_set_text :: proc(field, value: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	switch
	command.record_kind {
	case .Setup:
		switch
		field {case "tutorial_id":
			command.setup.tutorial_id = value; case "city_start":
			command.setup.city_start = value; case "city_destination":
			command.setup.city_destination = value; case "reveal_location":
			command.setup.reveal_location = value; case:
			return "FIELD IS NOT TEXT"}
	case .Character:
		switch
		field {case "private_secret":
			command.character.private_secret = value; case "motive":
			command.character.motive = value; case:
			return "USE RENAME FOR ENTITY ID"}
	case .Location:
		return "LOCATION SCALAR ID USES RENAME"
	case .POI:
		switch
		field {case "location_id":
			command.poi.location_id = value; case "owner_id":
			command.poi.owner_id = value; case "relevant_state":
			command.poi.relevant_state = value; case "examination_action":
			command.poi.examination_action = value; case:
			return "USE RENAME FOR ENTITY ID"}
	case .Event:
		switch
		field {case "destination_id":
			command.event.destination_id = value; case "tool_id":
			command.event.tool_id = value; case:
			return "USE RENAME FOR EVENT ID"}
	case .Clue:
		switch
		field {case "source_id":
			command.clue.source_id = value; case "description":
			command.clue.description = value; case "proposition_id":
			command.clue.proposition_id = value; case "skill":
			command.clue.skill = value; case "check_kind":
			command.clue.check_kind = value; case:
			return "USE RENAME FOR ID"}
	case .Claim:
		switch
		field {case "speaker_id":
			command.claim.speaker_id = value; case "proposition_id":
			command.claim.proposition_id = value; case "protects":
			command.claim.protects = value; case "response":
			command.claim.response = value; case:
			return "USE RENAME FOR ID"}
	case .Contradiction:
		switch
		field {case "claim_id":
			command.contradiction.claim_id = value; case "fact_id":
			command.contradiction.fact_id = value; case "conclusion_id":
			command.contradiction.conclusion_id = value; case "explanation":
			command.contradiction.explanation = value; case:
			return "USE RENAME FOR ID"}
	case .Deduction:
		switch
		field {case "proposition_id":
			command.deduction.proposition_id = value; case "category":
			command.deduction.category = value; case:
			return "USE RENAME FOR ID"}
	case .Question:
		switch
		field {case "prompt":
			command.question.prompt = value; case "hypothesis_id":
			command.question.hypothesis_id = value; case "category":
			command.question.category = value; case:
			return "USE RENAME FOR ID"}
	case .Demonstration:
		switch
		field {case "question_id":
			command.demonstration.question_id = value; case "mode":
			command.demonstration.mode = value; case "presentation":
			command.demonstration.presentation = value; case "gesture":
			command.demonstration.gesture = value; case "subject":
			command.demonstration.subject = value; case "art":
			command.demonstration.art = value; case "completion_cue":
			command.demonstration.completion_cue = value; case "resolution":
			command.demonstration.resolution = value; case "result":
			command.demonstration.result = value; case "prompt":
			command.demonstration.prompt = value; case:
			return "USE RENAME FOR ID"}
	case .Dialogue:
		switch
		field {case "character_id":
			command.dialogue.character_id = value; case "prompt":
			command.dialogue.prompt = value; case "response":
			command.dialogue.response = value; case "clue_id":
			command.dialogue.clue_id = value; case "interaction":
			command.dialogue.interaction = value; case:
			return "USE RENAME FOR NODE ID"}
	case .Ending:
		switch
		field {case "trigger":
			command.ending.trigger = value; case "outcome":
			command.ending.outcome = value; case "subtitle":
			command.ending.subtitle = value; case "epilogue":
			command.ending.epilogue = value; case "canonical_timeline":
			command.ending.canonical_timeline = value; case "tone":
			command.ending.tone = value; case "primary_label":
			command.ending.primary_label = value; case "primary_action":
			command.ending.primary_action = value; case "secondary_label":
			command.ending.secondary_label = value; case "secondary_action":
			command.ending.secondary_action = value; case:
			return "USE RENAME FOR ENDING ID"}
	case .City_Label:
		switch
		field {case "display_name":
			command.city_label.display_name = value; case "level_spawn":
			command.city_label.level_spawn = value; case "city_site":
			command.city_label.city_site = value; case:
			return "USE RENAME FOR ID"}
	case .Tutorial_Lesson:
		switch
		field {case "capability":
			command.tutorial_lesson.capability = value; case "prompt":
			command.tutorial_lesson.prompt = value; case:
			return "USE RENAME FOR ID"}
	case .Solution:
		switch
		field {case "culprit_id":
			command.solution.culprit_id = value; case "motive_id":
			command.solution.motive_id = value; case "decisive_contradiction_id":
			command.solution.decisive_contradiction_id = value; case "weapon_block":
			command.solution.weapon_block = value; case "murder_place_block":
			command.solution.murder_place_block = value; case "death_time_block":
			command.solution.death_time_block = value; case "body_movement_block":
			command.solution.body_movement_block = value; case "staging_block":
			command.solution.staging_block = value; case "cleaning_block":
			command.solution.cleaning_block = value; case "alibi_block":
			command.solution.alibi_block = value; case:
			return "UNKNOWN SOLUTION FIELD"}
	}
	return authoring_mystery_commit_update(command)}

authoring_mystery_set_number :: proc(field, value: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	number, parsed := strconv.parse_i64(strings.trim_space(value))
	if !parsed do return "EXPECTED INTEGER"
	n := int(number)
	#partial switch
	command.record_kind {case .Setup:
		if field == "action_budget" do command.setup.action_budget = max(1, n)
		else if field == "seed" do command.setup.seed = u64(max(0, n))
		else do return "UNKNOWN NUMERIC FIELD"; case .Character:
		if field == "initial_disposition" do command.character.initial_disposition = n
		else do return "UNKNOWN NUMERIC FIELD"; case .Clue:
		if field == "difficulty" do command.clue.difficulty = n
		else if field == "cost" do command.clue.cost = n
		else do return "UNKNOWN NUMERIC FIELD"; case .Demonstration:
		if field == "candidate_limit" do command.demonstration.candidate_limit = n
		else do return "UNKNOWN NUMERIC FIELD"; case:
		return "SELECTED FAMILY HAS NO NUMERIC SCALAR"}
	return authoring_mystery_commit_update(command)}
authoring_mystery_toggle_bool :: proc(field: string) -> string {command, ok :=
		authoring_mystery_selected_update()
	if !ok do return "NO SELECTED RECORD"
	if command.record_kind == .Claim && field == "canonical_truth" && !authoring_creator_truth_revealed do return "REVEAL CREATOR-ONLY TRUTH BEFORE EDITING"
	#partial switch
	command.record_kind {case .Clue:
		if field != "essential" do return "UNKNOWN BOOLEAN FIELD"
		command.clue.essential = !command.clue.essential; case .Claim:
		if field != "canonical_truth" do return "UNKNOWN BOOLEAN FIELD"
		command.claim.canonical_truth = !command.claim.canonical_truth; case .Question:
		if field != "required_for_final" do return "UNKNOWN BOOLEAN FIELD"
		command.question.required_for_final = !command.question.required_for_final; case:
		return "SELECTED FAMILY HAS NO BOOLEAN SCALAR"}
	return authoring_mystery_commit_update(command)}

authoring_mystery_update_list :: proc(
	field: string,
	edit: Story_List_Edit,
	at: int,
	value: string = "",
) -> string {command, ok := authoring_mystery_selected_update(); if !ok do return "NO SELECTED RECORD"
	changed := false
	#partial switch
	command.record_kind {
	case .Character:
		if field == "initial_claims" do changed = authoring_story_list_strings(&command.character.initial_claims, &command.character.initial_claim_count, edit, at, value)
	case .Location:
		if field == "connections" do changed = authoring_story_list_strings(&command.location.connections, &command.location.connection_count, edit, at, value)
		else if field == "characters" do changed = authoring_story_list_strings(&command.location.characters, &command.location.character_count, edit, at, value)
		else if field == "pois" do changed = authoring_story_list_strings(&command.location.pois, &command.location.poi_count, edit, at, value)
		else if field == "search_actions" do changed = authoring_story_list_strings(&command.location.search_actions, &command.location.search_action_count, edit, at, value)
	case .Event:
		if field == "effects" do changed = authoring_story_list_strings(&command.event.effects, &command.event.effect_count, edit, at, value)
	case .Clue:
		if field == "prerequisites" do changed = authoring_story_list_strings(&command.clue.prerequisites, &command.clue.prerequisite_count, edit, at, value)
		else if field == "blocks" do changed = authoring_story_list_strings(&command.clue.blocks, &command.clue.block_count, edit, at, value)
		else if field == "topics" do changed = authoring_story_list_strings(&command.clue.topics, &command.clue.topic_count, edit, at, value)
	case .Deduction:
		if field == "supports" do changed = authoring_story_list_strings(&command.deduction.supports, &command.deduction.support_count, edit, at, value)
		else if field == "unlock_questions" do changed = authoring_story_list_strings(&command.deduction.unlock_questions, &command.deduction.unlock_question_count, edit, at, value)
		else if field == "unlock_topics" do changed = authoring_story_list_strings(&command.deduction.unlock_topics, &command.deduction.unlock_topic_count, edit, at, value)
		else if field == "unlock_investigations" do changed = authoring_story_list_strings(&command.deduction.unlock_investigations, &command.deduction.unlock_investigation_count, edit, at, value)
	case .Question:
		if field == "requires_clues" do changed = authoring_story_list_strings(&command.question.requires_clues, &command.question.require_clue_count, edit, at, value)
		else if field == "requires_claims" do changed = authoring_story_list_strings(&command.question.requires_claims, &command.question.require_claim_count, edit, at, value)
		else if field == "requires_deductions" do changed = authoring_story_list_strings(&command.question.requires_deductions, &command.question.require_deduction_count, edit, at, value)
		else if field == "dependencies" do changed = authoring_story_list_strings(&command.question.dependencies, &command.question.dependency_count, edit, at, value)
	case .Demonstration:
		if field == "gesture_steps" do changed = authoring_story_list_strings(&command.demonstration.gesture_steps, &command.demonstration.gesture_step_count, edit, at, value)
		else if field == "slot_labels" do changed = authoring_story_list_strings(&command.demonstration.slot_labels, &command.demonstration.slot_count, edit, at, value)
		else if field == "slot_types" do changed = authoring_story_list_strings(&command.demonstration.slot_types, &command.demonstration.slot_count, edit, at, value)
		else if field == "accepted" do changed = authoring_story_list_strings(&command.demonstration.accepted, &command.demonstration.accepted_count, edit, at, value)
		else if field == "result_deductions" do changed = authoring_story_list_strings(&command.demonstration.result_deductions, &command.demonstration.result_count, edit, at, value)
	case .Dialogue:
		if field == "requires" do changed = authoring_story_list_strings(&command.dialogue.requires, &command.dialogue.require_count, edit, at, value)
		else if field == "unlocks" do changed = authoring_story_list_strings(&command.dialogue.unlocks, &command.dialogue.unlock_count, edit, at, value)
	case .Solution:
		if field == "requirements" do changed = authoring_story_list_strings(&command.solution.requirements, &command.solution.requirement_count, edit, at, value)
		else if field == "murder_events" do changed = authoring_story_list_strings(&command.solution.murder_events, &command.solution.murder_event_count, edit, at, value)
		else if field == "cover_up_events" do changed = authoring_story_list_strings(&command.solution.cover_up_events, &command.solution.cover_up_event_count, edit, at, value)
		else if field == "false_alibis" do changed = authoring_story_list_strings(&command.solution.false_alibis, &command.solution.false_alibi_count, edit, at, value)
		else if field == "exclusions" do changed = authoring_story_list_strings(&command.solution.exclusions, &command.solution.exclusion_count, edit, at, value)
	case:}
	if !changed do return "UNKNOWN, FULL, OR INVALID MYSTERY LIST EDIT"
	return authoring_mystery_commit_update(command)}

authoring_mystery_demonstration_route_edit :: proc(
	edit: Story_List_Edit,
	at, first, count: int,
) -> string {command, ok := authoring_mystery_selected_update(); if !ok || command.record_kind != .Demonstration do return "SELECT A DEMONSTRATION"
	r := &command.demonstration
	if edit == .Add {if r.route_count >= MYSTERY_MAX_REFS do return "ROUTE LIST FULL"; insert :=
			clamp(at, 0, r.route_count)
		for i := r.route_count; i > insert; i -= 1 {r.route_firsts[i] = r.route_firsts[i - 1]
			r.route_counts[i] = r.route_counts[i - 1]}
		r.route_firsts[insert] = first
		r.route_counts[insert] = count
		r.route_count += 1}
	else {if at < 0 || at >= r.route_count do return "INVALID ROUTE"; if edit == .Remove {for 			i in at + 1 ..< r.route_count {r.route_firsts[i - 1] = r.route_firsts[i]; r.route_counts[i - 1] =
					r.route_counts[i]}
			r.route_count -= 1
			r.route_firsts[r.route_count] = 0
			r.route_counts[r.route_count] = 0}
		else {to := edit == .Move_Up ? at - 1 : at + 1; if to < 0 || to >= r.route_count do return "INVALID ROUTE MOVE"
			r.route_firsts[at], r.route_firsts[to] = r.route_firsts[to], r.route_firsts[at]
			r.route_counts[at], r.route_counts[to] = r.route_counts[to], r.route_counts[at]}}
	return authoring_mystery_commit_update(command)}

authoring_mystery_picker_kind :: proc(
	field: string,
) -> (
	Mystery_Authoring_Record_Kind,
	bool,
) {switch field {case "initial_claims":
		return .Claim, true; case "connections":
		return .Location, true; case "characters", "exclusions":
		return .Character, true; case "pois", "search_actions":
		return .POI, true; case "prerequisites", "blocks", "requires_clues":
		return .Clue, true; case "unlock_questions", "dependencies":
		return .Question, true; case "requires_claims", "false_alibis":
		return .Claim, true; case "requires_deductions", "result_deductions", "requirements":
		return .Deduction, true; case "murder_events", "cover_up_events":
		return .Event, true}; return {}, false}
authoring_mystery_create_in_picker :: proc(field, id: string) -> string {target, typed :=
		authoring_mystery_picker_kind(field)
	if !typed do return "THIS LIST ACCEPTS FREE TEXT OR STORY DATA REFERENCES"
	owner_kind := clamp(
		authoring_workspace.selected_category,
		0,
		int(Mystery_Authoring_Record_Kind.Solution),
	)
	owner_index := authoring_workspace.selected_record
	authoring_workspace.selected_category = int(target)
	authoring_workspace.selected_record = 0
	created := authoring_workspace_add_mystery_from_selected(id)
	if !strings.contains(created, "committed") {authoring_workspace.selected_category = owner_kind
		authoring_workspace.selected_record = owner_index
		return created}
	created_index := authoring_mystery_count(target) - 1
	authoring_workspace.selected_category = owner_kind
	authoring_workspace.selected_record = owner_index
	linked := authoring_mystery_update_list(field, .Add, authoring_mystery_list_item, id)
	if !strings.contains(linked, "committed") {_ = mystery_authoring_undo(
			&active_story_project,
			&authoring_workspace.mystery_history,
		)
		return fmt.tprintf("CREATE ROLLED BACK · %s", linked)}
	authoring_workspace.selected_category = int(target)
	authoring_workspace.selected_record = created_index
	return fmt.tprintf("CREATED, LINKED, AND FOCUSED %v · %s", target, id)}

authoring_workspace_add_story_record :: proc() {
	kind := Story_Authoring_Record_Kind(
		clamp(authoring_workspace.selected_category, 0, int(Story_Authoring_Record_Kind.Effect)),
	); id := string(authoring_workspace.form_buffer[:authoring_workspace.form_count]); if id == "" do id = authoring_workspace_next_id(strings.to_lower(fmt.tprintf("%v", kind))); command := Story_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}
	#partial switch kind {case .Entity:
		command.entity = {
			id           = id,
			kind         = "object",
			display_name = "New Entity",
		}; case .Role:
		command.role = {
			id           = id,
			display_name = "New Role",
		}; case .Variable:
		command.variable = {
			id            = id,
			display_name  = "New Variable",
			kind          = .Boolean,
			default_value = story_value_boolean(false),
		}; case .Fact:
		command.fact = {
			id           = id,
			display_name = "New Fact",
		}; case .Proposition:
		command.proposition = {
			id   = id,
			text = "New proposition",
		}; case .Knowledge:
		authoring_workspace.feedback = "ADD REQUIRES AN ACTOR AND PROPOSITION"
		return; case .Relationship:
		command.relationship = {
			id   = id,
			kind = "relationship",
		}; case .Event:
		command.event = {
			id     = id,
			action = "event",
		}; case .Objective:
		command.objective = {
			id           = id,
			display_name = "New Objective",
		}; case .Ending:
		command.ending = {
			id           = id,
			title        = "New Ending",
			condition_id = "always",
		}; case .Storylet_Group:
		command.storylet_group = {
			id          = id,
			allow_empty = true,
		}; case .Storylet:
		command.storylet = {
			id            = id,
			fallback      = true,
			repeat_policy = .Always,
		}; case .Invariant:
		command.invariant = {
			id           = id,
			description  = "New invariant",
			condition_id = "always",
			kind         = .Always,
		}; case .Condition:
		command.condition = {
			id   = id,
			kind = .Always,
		}; case .Effect:
		command.effect = {
			id       = id,
			kind     = .Emit_Event,
			event_id = id,
		}}
	commands := [1]Story_Authoring_Command {
		command,
	}; result := story_authoring_apply(&active_story_project, &authoring_workspace.story_history, commands[:]); committed := result.ok; authoring_workspace.feedback = result.message; story_authoring_result_destroy(&result); if committed do graph_import_story(&active_story_project)
}

// ---- Story typed record editor -------------------------------------------------
// Presentation code can enumerate fields however it likes; these helpers keep all
// edits typed, transactional, undoable, and independent of widget state.
Story_List_Edit :: enum {
	Add,
	Remove,
	Move_Up,
	Move_Down,
}

authoring_story_parse_int :: proc(text: string) -> (int, bool) {v, ok := strconv.parse_i64(
		strings.trim_space(text),
	)
	return int(v), ok}
authoring_story_parse_bool :: proc(text: string) -> (bool, bool) {v := strings.to_lower(
		strings.trim_space(text),
	)
	if v == "true" || v == "1" do return true, true
	if v == "false" || v == "0" do return false, true
	return false, false}

authoring_story_selected_command :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
) -> (
	Story_Authoring_Command,
	bool,
) {
	command := Story_Authoring_Command {
		kind        = .Update,
		record_kind = kind,
	}
	if index < 0 || index >= authoring_story_count(kind) do return command, false
	#partial switch kind {
	case .Entity:
		command.entity = active_story_project.entities[index]
	case .Role:
		command.role = active_story_project.roles[index]
	case .Variable:
		command.variable = active_story_project.variables[index]
	case .Fact:
		command.fact = active_story_project.facts[index]
	case .Proposition:
		command.proposition = active_story_project.propositions[index]
	case .Knowledge:
		command.knowledge = active_story_project.initial_knowledge[index]
	case .Relationship:
		command.relationship = active_story_project.relationships[index]
	case .Event:
		command.event = active_story_project.events[index]
	case .Objective:
		command.objective = active_story_project.objectives[index]
	case .Ending:
		command.ending = active_story_project.endings[index]
	case .Storylet_Group:
		command.storylet_group = active_story_project.storylet_groups[index]
	case .Storylet:
		command.storylet = active_story_project.storylets[index]
	case .Invariant:
		command.invariant = active_story_project.invariants[index]
	case .Condition:
		command.condition = active_story_project.conditions[index]
	case .Effect:
		command.effect = active_story_project.effects[index]
	}
	return command, true
}

authoring_story_commit_commands :: proc(commands: []Story_Authoring_Command) -> string {
	result := story_authoring_apply(
		&active_story_project,
		&authoring_workspace.story_history,
		commands,
	)
	ok := result.ok; message := result.message; story_authoring_result_destroy(&result)
	if ok do graph_import_story(&active_story_project)
	return message
}

authoring_story_update_field :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field, value: string,
) -> string {
	command, ok := authoring_story_selected_command(
		kind,
		index,
	); if !ok do return "NO SELECTED STORY RECORD"
	if (kind == .Fact || kind == .Proposition) && field == "canonical_truth" && !authoring_creator_truth_revealed do return "REVEAL CREATOR-ONLY TRUTH BEFORE EDITING"
	if field == "id" {
		if kind == .Knowledge do return "KNOWLEDGE ID IS ITS ACTOR / PROPOSITION PAIR"
		rename := Story_Authoring_Command {
			kind        = .Rename,
			record_kind = kind,
			id          = authoring_story_id(kind, index),
			new_id      = value,
		}; commands := [1]Story_Authoring_Command {
			rename,
		}; return authoring_story_commit_commands(commands[:])
	}
	int_value, int_ok := authoring_story_parse_int(
		value,
	); bool_value, bool_ok := authoring_story_parse_bool(value)
	#partial switch kind {
	case .Entity:
		r := &command.entity; switch field {case "kind":
			r.kind = value; case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "spatial.space_id":
			r.spatial.space_id = value; case "spatial.target_kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.spatial.target_kind = Story_Spatial_Target_Kind(
				clamp(int_value, 0, int(Story_Spatial_Target_Kind.Entity)),
			); case "spatial.target_id":
			r.spatial.target_id = value; case "volume":
			if !int_ok do return "EXPECTED INTEGER"
			r.volume = int_value; case "container_capacity":
			if !int_ok do return "EXPECTED INTEGER"
			r.container_capacity = int_value; case "initially_locked":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.initially_locked = bool_value; case "owner_id":
			r.owner_id = value; case "initial_container_id":
			r.initial_container_id = value; case:
			return "UNKNOWN ENTITY FIELD"}
	case .Role:
		r := &command.role; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "minimum":
			if !int_ok do return "EXPECTED INTEGER"; r.minimum = int_value; case "maximum":
			if !int_ok do return "EXPECTED INTEGER"; r.maximum = int_value; case:
			return "UNKNOWN ROLE FIELD"}
	case .Variable:
		r := &command.variable; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Value_Kind(clamp(int_value, 0, int(Story_Value_Kind.Entity)))
			r.default_value.kind = r.kind; case "default_value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.default_value.boolean_value = bool_value; case "default_value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.default_value.integer_value = int_value; case "default_value.text":
			r.default_value.text_value = value; case "minimum":
			if !int_ok do return "EXPECTED INTEGER"; r.minimum = int_value; case "maximum":
			if !int_ok do return "EXPECTED INTEGER"; r.maximum = int_value; case:
			return "UNKNOWN VARIABLE FIELD"}
	case .Fact:
		r := &command.fact; switch field {case "display_name":
			r.display_name = value; case "proposition":
			r.proposition = value; case "variable_id":
			r.variable_id = value; case "canonical_truth":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.canonical_truth = Story_Truth(
				clamp(int_value, int(Story_Truth.Undetermined), int(Story_Truth.True)),
			); case "player_visible":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.player_visible = bool_value; case:
			return "UNKNOWN FACT FIELD"}
	case .Proposition:
		r := &command.proposition; switch field {case "text":
			r.text = value; case "canonical_truth":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.canonical_truth = Story_Truth(
				clamp(int_value, int(Story_Truth.Undetermined), int(Story_Truth.True)),
			); case:
			return "UNKNOWN PROPOSITION FIELD"}
	case .Knowledge:
		// Pair members are the stable key in StoryCore; use create/remove to change them.
		if field == "actor_id" || field == "proposition_id" do return "KNOWLEDGE KEY FIELDS REQUIRE CREATE / REMOVE"
		if field != "stance" || !int_ok do return "UNKNOWN KNOWLEDGE FIELD OR EXPECTED ENUM NUMBER"
		command.knowledge.stance = Story_Belief_Stance(
			clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
		)
	case .Relationship:
		r := &command.relationship; switch field {case "source_id":
			r.source_id = value; case "target_id":
			r.target_id = value; case "kind":
			r.kind = value; case "variable_id":
			r.variable_id = value; case:
			return "UNKNOWN RELATIONSHIP FIELD"}
	case .Event:
		r := &command.event; switch field {case "subject_id":
			r.subject_id = value; case "action":
			r.action = value; case "object_id":
			r.object_id = value; case "location_id":
			r.location_id = value; case "fictional_time":
			r.fictional_time = value; case "provenance":
			r.provenance = value; case:
			return "UNKNOWN EVENT FIELD"}
	case .Objective:
		r := &command.objective; switch field {case "display_name":
			r.display_name = value; case "description":
			r.description = value; case "hidden":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.hidden = bool_value; case "initial_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.initial_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "stage_count":
			if !int_ok do return "EXPECTED INTEGER"
			r.stage_count = int_value; case "completion_condition_id":
			r.completion_condition_id = value; case "failure_condition_id":
			r.failure_condition_id = value; case "completion_condition":
			if !int_ok do return "EXPECTED INTEGER"
			r.completion_condition = int_value; case "failure_condition":
			if !int_ok do return "EXPECTED INTEGER"; r.failure_condition = int_value; case:
			return "UNKNOWN OBJECTIVE FIELD"}
	case .Ending:
		r := &command.ending; switch field {case "title":
			r.title = value; case "summary":
			r.summary = value; case "condition_id":
			r.condition_id = value; case "condition_root":
			if !int_ok do return "EXPECTED INTEGER"; r.condition_root = int_value; case "priority":
			if !int_ok do return "EXPECTED INTEGER"; r.priority = int_value; case:
			return "UNKNOWN ENDING FIELD"}
	case .Storylet_Group:
		r := &command.storylet_group; switch field {case "allow_empty":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.allow_empty = bool_value; case "seeded_random_ties":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.seeded_random_ties = bool_value; case:
			return "UNKNOWN STORYLET GROUP FIELD"}
	case .Storylet:
		r := &command.storylet; switch field {case "group":
			r.group = value; case "scene_id":
			r.scene_id = value; case "dramatic_priority":
			if !int_ok do return "EXPECTED INTEGER"
			r.dramatic_priority = int_value; case "specificity":
			if !int_ok do return "EXPECTED INTEGER"; r.specificity = int_value; case "cooldown":
			if !int_ok do return "EXPECTED INTEGER"; r.cooldown = int_value; case "authored_order":
			if !int_ok do return "EXPECTED INTEGER"
			r.authored_order = int_value; case "repeat_policy":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.repeat_policy = Story_Repeat_Policy(
				clamp(int_value, 0, int(Story_Repeat_Policy.Once)),
			); case "fallback":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.fallback = bool_value; case:
			return "UNKNOWN STORYLET FIELD"}
	case .Invariant:
		r := &command.invariant; switch field {case "description":
			r.description = value; case "condition_id":
			r.condition_id = value; case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Invariant_Kind(
				clamp(int_value, 0, int(Story_Invariant_Kind.Always)),
			); case "condition_root":
			if !int_ok do return "EXPECTED INTEGER"; r.condition_root = int_value; case "required":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.required = bool_value; case:
			return "UNKNOWN INVARIANT FIELD"}
	case .Condition:
		r := &command.condition; switch field {case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Condition_Kind(
				clamp(int_value, 0, int(Story_Condition_Kind.Capability_State)),
			); case "first_child":
			if !int_ok do return "EXPECTED INTEGER"; r.first_child = int_value; case "child_count":
			if !int_ok do return "EXPECTED INTEGER"; r.child_count = int_value; case "variable_id":
			r.variable_id = value; case "entity_id":
			r.entity_id = value; case "other_entity_id":
			r.other_entity_id = value; case "proposition_id":
			r.proposition_id = value; case "objective_id":
			r.objective_id = value; case "event_id":
			r.event_id = value; case "content_id":
			r.content_id = value; case "text_value":
			r.text_value = value; case "value.kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.value.kind = Story_Value_Kind(
				clamp(int_value, 0, int(Story_Value_Kind.Entity)),
			); case "value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.value.boolean_value = bool_value; case "value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.value.integer_value = int_value; case "value.text":
			r.value.text_value = value; case "comparison":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.comparison = Story_Integer_Comparison(
				clamp(int_value, 0, int(Story_Integer_Comparison.Greater_Equal)),
			); case "objective_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.objective_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "belief_stance":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.belief_stance = Story_Belief_Stance(
				clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
			); case "spatial_a.space_id":
			r.spatial_a.space_id = value; case "spatial_a.target_id":
			r.spatial_a.target_id = value; case "spatial_b.space_id":
			r.spatial_b.space_id = value; case "spatial_b.target_id":
			r.spatial_b.target_id = value; case "distance":
			parsed, pok := strconv.parse_f32(strings.trim_space(value))
			if !pok do return "EXPECTED NUMBER"
			r.distance = parsed; case:
			return "UNKNOWN CONDITION FIELD"}
	case .Effect:
		r := &command.effect; switch field {case "kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.kind = Story_Effect_Kind(
				clamp(int_value, 0, int(Story_Effect_Kind.Spatial_Command)),
			); case "variable_id":
			r.variable_id = value; case "actor_id":
			r.actor_id = value; case "other_actor_id":
			r.other_actor_id = value; case "proposition_id":
			r.proposition_id = value; case "objective_id":
			r.objective_id = value; case "event_id":
			r.event_id = value; case "content_id":
			r.content_id = value; case "world_id":
			r.world_id = value; case "value.kind":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.value.kind = Story_Value_Kind(
				clamp(int_value, 0, int(Story_Value_Kind.Entity)),
			); case "value.boolean":
			if !bool_ok do return "EXPECTED BOOLEAN"
			r.value.boolean_value = bool_value; case "value.integer":
			if !int_ok do return "EXPECTED INTEGER"
			r.value.integer_value = int_value; case "value.text":
			r.value.text_value = value; case "belief_stance":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.belief_stance = Story_Belief_Stance(
				clamp(int_value, 0, int(Story_Belief_Stance.Disbelieves)),
			); case "objective_status":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.objective_status = Story_Objective_Status(
				clamp(int_value, 0, int(Story_Objective_Status.Failed)),
			); case "spatial_command":
			if !int_ok do return "EXPECTED ENUM NUMBER"
			r.spatial_command = Story_Spatial_Command_Kind(
				clamp(int_value, 0, int(Story_Spatial_Command_Kind.Set_Interaction)),
			); case "spatial_target.space_id":
			r.spatial_target.space_id = value; case "spatial_target.target_id":
			r.spatial_target.target_id = value; case "spatial_destination.space_id":
			r.spatial_destination.space_id = value; case "spatial_destination.target_id":
			r.spatial_destination.target_id = value; case "world_enabled":
			if !bool_ok do return "EXPECTED BOOLEAN"; r.world_enabled = bool_value; case:
			return "UNKNOWN EFFECT FIELD"}
	}
	commands := [1]Story_Authoring_Command {
		command,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_list_strings :: proc(
	values: ^[$N]string,
	count: ^int,
	edit: Story_List_Edit,
	at: int,
	value: string,
) -> bool {
	if edit ==
	   .Add {if count^ >= N do return false; insert := clamp(at, 0, count^); for i := count^; i > insert; i -= 1 do values[i] = values[i - 1]; values[insert] = value; count^ += 1; return true}
	if at < 0 || at >= count^ do return false
	if edit ==
	   .Remove {for i in at + 1 ..< count^ do values[i - 1] = values[i]; count^ -= 1; values[count^] = ""; return true}
	to :=
		edit == .Move_Up ? at - 1 : at + 1; if to < 0 || to >= count^ do return false; values[at], values[to] = values[to], values[at]; return true
}

authoring_story_update_list :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field: string,
	edit: Story_List_Edit,
	at: int,
	value: string = "",
) -> string {
	command, ok := authoring_story_selected_command(
		kind,
		index,
	); if !ok do return "NO SELECTED STORY RECORD"
	changed := false
	#partial switch kind {
	case .Entity:
		if field == "tags" do changed = authoring_story_list_strings(&command.entity.tags, &command.entity.tag_count, edit, at, value)
		else if field == "roles" do changed = authoring_story_list_strings(&command.entity.roles, &command.entity.role_count, edit, at, value)
	case .Variable:
		if field == "enum_values" do changed = authoring_story_list_strings(&command.variable.enum_values, &command.variable.enum_value_count, edit, at, value)
	case .Event:
		if field == "witnesses" do changed = authoring_story_list_strings(&command.event.witnesses, &command.event.witness_count, edit, at, value)
	case .Condition:
		if field == "child_ids" do changed = authoring_story_list_strings(&command.condition.child_ids, &command.condition.child_id_count, edit, at, value)
	case .Storylet:
		if field == "condition_ids" do changed = authoring_story_list_strings(&command.storylet.condition_ids, &command.storylet.condition_count, edit, at, value)
		else if field == "effect_ids" do changed = authoring_story_list_strings(&command.storylet.effect_ids, &command.storylet.effect_count, edit, at, value)
	case:
	}
	if !changed do return "UNKNOWN, FULL, OR INVALID STORY LIST EDIT"
	commands := [1]Story_Authoring_Command {
		command,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_create_reference_command :: proc(
	kind: Story_Authoring_Record_Kind,
	id: string,
) -> (
	Story_Authoring_Command,
	bool,
) {
	c := Story_Authoring_Command {
		kind        = .Add,
		record_kind = kind,
	}; #partial switch kind {case .Entity:
		c.entity = {
			id           = id,
			kind         = "person",
			display_name = id,
		}; case .Role:
		c.role = {
			id           = id,
			display_name = id,
		}; case .Variable:
		c.variable = {
			id = id,
			display_name = id,
			kind = .Boolean,
			default_value = {kind = .Boolean},
		}; case .Proposition:
		c.proposition = {
			id   = id,
			text = id,
		}; case .Condition:
		c.condition = {
			id   = id,
			kind = .Always,
		}; case .Effect:
		c.effect = {
			id         = id,
			kind       = .Complete_Scene,
			content_id = id,
		}; case:
		return c, false}; return c, true
}

// Picker convenience: create a missing selectable record and add its id to a
// fixed-capacity list in one validation/undo transaction.
authoring_story_list_create_in_picker :: proc(
	owner_kind: Story_Authoring_Record_Kind,
	owner_index: int,
	field: string,
	at: int,
	reference_kind: Story_Authoring_Record_Kind,
	id: string,
) -> string {
	if story_authoring_record_exists(&active_story_project, reference_kind, id) do return authoring_story_update_list(owner_kind, owner_index, field, .Add, at, id)
	create, ok := authoring_story_create_reference_command(
		reference_kind,
		id,
	); if !ok do return "REFERENCE KIND CANNOT BE CREATED IN THIS PICKER"
	update, found := authoring_story_selected_command(
		owner_kind,
		owner_index,
	); if !found do return "NO SELECTED STORY RECORD"
	changed := false; #partial switch owner_kind {case .Entity:
		if field == "roles" do changed = authoring_story_list_strings(&update.entity.roles, &update.entity.role_count, .Add, at, id); case .Event:
		if field == "witnesses" do changed = authoring_story_list_strings(&update.event.witnesses, &update.event.witness_count, .Add, at, id); case .Condition:
		if field == "child_ids" do changed = authoring_story_list_strings(&update.condition.child_ids, &update.condition.child_id_count, .Add, at, id); case .Storylet:
		if field == "condition_ids" do changed = authoring_story_list_strings(&update.storylet.condition_ids, &update.storylet.condition_count, .Add, at, id)
		else if field == "effect_ids" do changed = authoring_story_list_strings(&update.storylet.effect_ids, &update.storylet.effect_count, .Add, at, id); case:}
	if !changed do return "PICKER DOES NOT ACCEPT THAT REFERENCE KIND"
	commands := [2]Story_Authoring_Command {
		create,
		update,
	}; return authoring_story_commit_commands(commands[:])
}

authoring_story_scalar_field :: proc(
	kind: Story_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {
	#partial switch kind {
	case .Entity:
		items := [12]string {
			"id",
			"kind",
			"display_name",
			"description",
			"spatial.space_id",
			"spatial.target_kind",
			"spatial.target_id",
			"volume",
			"container_capacity",
			"initially_locked",
			"owner_id",
			"initial_container_id",
		}
		return items[cursor % len(items)], len(items)
	case .Role:
		items := [5]string{"id", "display_name", "description", "minimum", "maximum"}
		return items[cursor % len(items)], len(items)
	case .Variable:
		items := [9]string {
			"id",
			"display_name",
			"description",
			"kind",
			"default_value.boolean",
			"default_value.integer",
			"default_value.text",
			"minimum",
			"maximum",
		}
		return items[cursor % len(items)], len(items)
	case .Fact:
		items := [6]string {
			"id",
			"display_name",
			"proposition",
			"variable_id",
			"canonical_truth",
			"player_visible",
		}
		return items[cursor % len(items)], len(items)
	case .Proposition:
		items := [3]string{"id", "text", "canonical_truth"}
		return items[cursor % len(items)], len(items)
	case .Knowledge:
		items := [3]string{"actor_id", "proposition_id", "stance"}
		return items[cursor % len(items)], len(items)
	case .Relationship:
		items := [5]string{"id", "source_id", "target_id", "kind", "variable_id"}
		return items[cursor % len(items)], len(items)
	case .Event:
		items := [7]string {
			"id",
			"subject_id",
			"action",
			"object_id",
			"location_id",
			"fictional_time",
			"provenance",
		}
		return items[cursor % len(items)], len(items)
	case .Objective:
		items := [10]string {
			"id",
			"display_name",
			"description",
			"hidden",
			"initial_status",
			"stage_count",
			"completion_condition_id",
			"failure_condition_id",
			"completion_condition",
			"failure_condition",
		}
		return items[cursor % len(items)], len(items)
	case .Ending:
		items := [6]string{"id", "title", "summary", "condition_id", "condition_root", "priority"}
		return items[cursor % len(items)], len(items)
	case .Storylet_Group:
		items := [3]string{"id", "allow_empty", "seeded_random_ties"}
		return items[cursor % len(items)], len(items)
	case .Storylet:
		items := [9]string {
			"id",
			"group",
			"scene_id",
			"dramatic_priority",
			"specificity",
			"cooldown",
			"authored_order",
			"repeat_policy",
			"fallback",
		}
		return items[cursor % len(items)], len(items)
	case .Invariant:
		items := [6]string {
			"id",
			"description",
			"condition_id",
			"kind",
			"condition_root",
			"required",
		}
		return items[cursor % len(items)], len(items)
	case .Condition:
		items := [24]string {
			"id",
			"kind",
			"first_child",
			"child_count",
			"variable_id",
			"entity_id",
			"other_entity_id",
			"proposition_id",
			"objective_id",
			"event_id",
			"content_id",
			"text_value",
			"value.kind",
			"value.boolean",
			"value.integer",
			"value.text",
			"comparison",
			"objective_status",
			"belief_stance",
			"spatial_a.space_id",
			"spatial_a.target_id",
			"spatial_b.space_id",
			"spatial_b.target_id",
			"distance",
		}
		return items[cursor % len(items)], len(items)
	case .Effect:
		items := [22]string {
			"id",
			"kind",
			"variable_id",
			"actor_id",
			"other_actor_id",
			"proposition_id",
			"objective_id",
			"event_id",
			"content_id",
			"world_id",
			"value.kind",
			"value.boolean",
			"value.integer",
			"value.text",
			"belief_stance",
			"objective_status",
			"spatial_command",
			"spatial_target.space_id",
			"spatial_target.target_id",
			"spatial_destination.space_id",
			"spatial_destination.target_id",
			"world_enabled",
		}
		return items[cursor % len(items)], len(items)
	}
	return "", 0
}

authoring_story_list_field :: proc(
	kind: Story_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {#partial switch kind {case .Entity:
		items := [2]string{"tags", "roles"}; return items[cursor % 2], 2; case .Variable:
		return "enum_values", 1; case .Event:
		return "witnesses", 1; case .Condition:
		return "child_ids", 1; case .Storylet:
		items := [2]string{"condition_ids", "effect_ids"}
		return items[cursor % 2], 2}; return "", 0}
authoring_story_list_count :: proc(
	kind: Story_Authoring_Record_Kind,
	index: int,
	field: string,
) -> int {if index < 0 || index >= authoring_story_count(kind) do return 0; #partial switch
	kind {case .Entity:
		return(
			field == "tags" ? active_story_project.entities[index].tag_count : active_story_project.entities[index].role_count \
		); case .Variable:
		return active_story_project.variables[index].enum_value_count; case .Event:
		return active_story_project.events[index].witness_count; case .Condition:
		return active_story_project.conditions[index].child_id_count; case .Storylet:
		return(
			field == "condition_ids" ? active_story_project.storylets[index].condition_count : active_story_project.storylets[index].effect_count \
		)}
	return 0}
authoring_story_begin_form :: proc(
	action: Authoring_Form_Action,
) {authoring_workspace.form_active = true; authoring_workspace.form_action = action
	authoring_workspace.form_count = 0}

// Mystery descriptors use a one-byte editor type: t=text, n=number, b=toggle.
authoring_mystery_scalar_field :: proc(
	kind: Mystery_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	u8,
	int,
) {#partial switch kind {
	case .Setup:
		a := [6]string {
			"action_budget",
			"seed",
			"tutorial_id",
			"city_start",
			"city_destination",
			"reveal_location",
		}
		types := [6]u8{'n', 'n', 't', 't', 't', 't'}
		i := cursor % 6
		return a[i], types[i], 6
	case .Character:
		a := [3]string{"private_secret", "motive", "initial_disposition"}; i := cursor % 3
		return a[i], i == 2 ? 'n' : 't', 3
	case .Location:
		return "id (rename)", 't', 1
	case .POI:
		a := [4]string{"location_id", "owner_id", "relevant_state", "examination_action"}
		return a[cursor % 4], 't', 4
	case .Event:
		a := [2]string{"destination_id", "tool_id"}; return a[cursor % 2], 't', 2
	case .Clue:
		a := [8]string {
			"source_id",
			"description",
			"proposition_id",
			"skill",
			"check_kind",
			"difficulty",
			"cost",
			"essential",
		}
		types := [8]u8{'t', 't', 't', 't', 't', 'n', 'n', 'b'}
		i := cursor % 8
		return a[i], types[i], 8
	case .Claim:
		a := [5]string{"speaker_id", "proposition_id", "protects", "response", "canonical_truth"}
		i := cursor % 5
		return a[i], i == 4 ? 'b' : 't', 5
	case .Contradiction:
		a := [4]string{"claim_id", "fact_id", "conclusion_id", "explanation"}
		return a[cursor % 4], 't', 4
	case .Deduction:
		a := [2]string{"proposition_id", "category"}; return a[cursor % 2], 't', 2
	case .Question:
		a := [4]string{"prompt", "hypothesis_id", "category", "required_for_final"}
		i := cursor % 4
		return a[i], i == 3 ? 'b' : 't', 4
	case .Demonstration:
		a := [12]string {
			"question_id",
			"mode",
			"presentation",
			"gesture",
			"subject",
			"art",
			"completion_cue",
			"candidate_limit",
			"resolution",
			"result",
			"prompt",
			"routes",
		}
		i := cursor % 12
		return a[i], i == 7 ? 'n' : 't', 12
	case .Dialogue:
		a := [5]string{"character_id", "prompt", "response", "clue_id", "interaction"}
		return a[cursor % 5], 't', 5
	case .Ending:
		a := [10]string {
			"trigger",
			"outcome",
			"subtitle",
			"epilogue",
			"canonical_timeline",
			"tone",
			"primary_label",
			"primary_action",
			"secondary_label",
			"secondary_action",
		}
		return a[cursor % 10], 't', 10
	case .City_Label:
		a := [3]string{"display_name", "level_spawn", "city_site"}; return a[cursor % 3], 't', 3
	case .Tutorial_Lesson:
		a := [2]string{"capability", "prompt"}; return a[cursor % 2], 't', 2
	case .Solution:
		a := [10]string {
			"culprit_id",
			"motive_id",
			"decisive_contradiction_id",
			"weapon_block",
			"murder_place_block",
			"death_time_block",
			"body_movement_block",
			"staging_block",
			"cleaning_block",
			"alibi_block",
		}
		return a[cursor % 10], 't', 10
	}; return "", 't', 0}

authoring_mystery_list_field :: proc(
	kind: Mystery_Authoring_Record_Kind,
	cursor: int,
) -> (
	string,
	int,
) {#partial switch kind {case .Character:
		return "initial_claims", 1; case .Location:
		a := [4]string{"connections", "characters", "pois", "search_actions"}
		return a[cursor % 4], 4; case .Event:
		return "effects", 1; case .Clue:
		a := [3]string{"prerequisites", "blocks", "topics"}
		return a[cursor % 3], 3; case .Deduction:
		a := [4]string{"supports", "unlock_questions", "unlock_topics", "unlock_investigations"}
		return a[cursor % 4], 4; case .Question:
		a := [4]string{"requires_clues", "requires_claims", "requires_deductions", "dependencies"}
		return a[cursor % 4], 4; case .Demonstration:
		a := [5]string {
			"gesture_steps",
			"slot_labels",
			"slot_types",
			"accepted",
			"result_deductions",
		}
		return a[cursor % 5], 5; case .Dialogue:
		a := [2]string{"requires", "unlocks"}; return a[cursor % 2], 2; case .Solution:
		a := [5]string {
			"requirements",
			"murder_events",
			"cover_up_events",
			"false_alibis",
			"exclusions",
		}
		return a[cursor % 5], 5}; return "", 0}

authoring_mystery_selected_list_count :: proc(field: string) -> int {c, ok :=
		authoring_mystery_selected_update()
	if !ok do return 0
	#partial switch
	c.record_kind {case .Character:
		return c.character.initial_claim_count; case .Location:
		if field == "connections" do return c.location.connection_count
		if field == "characters" do return c.location.character_count
		if field == "pois" do return c.location.poi_count
		return c.location.search_action_count; case .Event:
		return c.event.effect_count; case .Clue:
		if field == "prerequisites" do return c.clue.prerequisite_count
		if field == "blocks" do return c.clue.block_count
		return c.clue.topic_count; case .Deduction:
		if field == "supports" do return c.deduction.support_count
		if field == "unlock_questions" do return c.deduction.unlock_question_count
		if field == "unlock_topics" do return c.deduction.unlock_topic_count
		return c.deduction.unlock_investigation_count; case .Question:
		if field == "requires_clues" do return c.question.require_clue_count
		if field == "requires_claims" do return c.question.require_claim_count
		if field == "requires_deductions" do return c.question.require_deduction_count
		return c.question.dependency_count; case .Demonstration:
		if field == "gesture_steps" do return c.demonstration.gesture_step_count
		if field == "slot_labels" || field == "slot_types" do return c.demonstration.slot_count
		if field == "accepted" do return c.demonstration.accepted_count
		return c.demonstration.result_count; case .Dialogue:
		return(
			field == "requires" ? c.dialogue.require_count : c.dialogue.unlock_count \
		); case .Solution:
		if field == "requirements" do return c.solution.requirement_count; if field == "murder_events" do return c.solution.murder_event_count
		if field == "cover_up_events" do return c.solution.cover_up_event_count
		if field == "false_alibis" do return c.solution.false_alibi_count
		return c.solution.exclusion_count}
	return 0}

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
