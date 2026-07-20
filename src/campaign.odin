package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

CAMPAIGN_MAX_CASES :: 16
CAMPAIGN_MAX_VARIABLES :: 64
CAMPAIGN_MAX_ENUM_VALUES :: 16
CAMPAIGN_MAX_CONDITIONS :: 256
CAMPAIGN_MAX_EFFECTS :: 256
CAMPAIGN_RECALCULATE_LIMIT :: CAMPAIGN_MAX_CASES + 1
CAMPAIGN_MAX_PLAYTHROUGHS :: 32
CAMPAIGN_MAX_CATALOG :: 16
CAMPAIGN_HISTORY_LIMIT :: 32

Campaign_Value_Kind :: enum {
	Boolean,
	Integer,
	Enumeration,
}
Campaign_Condition_Kind :: enum {
	Always,
	Never,
	All,
	Any,
	Not,
	Boolean_Equals,
	Integer_Compare,
	Enum_Equals,
	Case_Started,
	Case_Completed,
	Case_Outcome,
}
Campaign_Integer_Comparison :: enum {
	Equal,
	Not_Equal,
	Less,
	Less_Equal,
	Greater,
	Greater_Equal,
}
Campaign_Effect_Kind :: enum {
	Set_Boolean,
	Set_Integer,
	Add_Integer,
	Set_Enum,
}
Campaign_Unavailable_Presentation :: enum {
	Hidden,
	Locked_Message,
	Requirements,
}
Campaign_Replay_Mode :: enum {
	Disabled,
	Effectless,
	Replace_Outcome,
}
Campaign_Invalid_Result_Policy :: enum {
	Preserve,
	Clear,
}

Campaign_Variable :: struct {
	id, display_name, description: string,
	kind:                          Campaign_Value_Kind,
	default_boolean:               bool,
	default_integer:               int,
	default_enum:                  string,
	enum_values:                   [CAMPAIGN_MAX_ENUM_VALUES]string,
	enum_value_count:              int,
}

// Conditions are stored as a flat pre-order tree. Group children occupy the
// contiguous range [first_child, first_child+child_count). Child nodes may in
// turn point at later ranges, keeping the persisted document non-recursive.
Campaign_Condition :: struct {
	kind:                             Campaign_Condition_Kind,
	first_child, child_count:         int,
	variable_id, case_id, enum_value: string,
	boolean_value:                    bool,
	integer_value:                    int,
	integer_comparison:               Campaign_Integer_Comparison,
	outcome:                          Outcome,
}

Campaign_Effect :: struct {
	kind:          Campaign_Effect_Kind,
	variable_id:   string,
	boolean_value: bool,
	integer_value: int,
	enum_value:    string,
}

Campaign_Outcome_Effects :: struct {
	outcome:                    Outcome,
	first_effect, effect_count: int,
}

Campaign_Case :: struct {
	id, title, story_path, level_path, case_content_version, locked_message: string,
	condition_root:                                                          int,
	required, optional:                                                      bool,
	unavailable_presentation:                                                Campaign_Unavailable_Presentation,
	replay_mode:                                                             Campaign_Replay_Mode,
	invalid_result_policy:                                                   Campaign_Invalid_Result_Policy,
	outcome_effects:                                                         [5]Campaign_Outcome_Effects,
	outcome_effect_count:                                                    int,
}

Campaign_Definition :: struct {
	version, id, title, creator, description, content_version, thumbnail: string,
	variables:                                                            [dynamic]Campaign_Variable,
	conditions:                                                           [dynamic]Campaign_Condition,
	effects:                                                              [dynamic]Campaign_Effect,
	cases:                                                                [dynamic]Campaign_Case,
}

Campaign_Value :: struct {
	kind:          Campaign_Value_Kind,
	boolean_value: bool,
	integer_value: int,
	enum_value:    string,
}
Campaign_Case_Result :: struct {
	present, started:              bool,
	case_id, case_content_version: string,
	outcome:                       Outcome,
	completion_sequence:           u64,
}
Campaign_Playthrough :: struct {
	campaign_id, campaign_content_version, id, name: string,
	results:                                         [CAMPAIGN_MAX_CASES]Campaign_Case_Result,
	values:                                          [CAMPAIGN_MAX_VARIABLES]Campaign_Value,
	completion_count:                                int,
	next_completion_sequence:                        u64,
	active_case:                                     int,
	derived_hash:                                    u64,
}
Campaign_Condition_Trace :: struct {
	value:   bool,
	message: string,
}
// A condition path addresses nodes by logical child ordinals from a case root.
// Authoring callers never need to retain serialization-array indices, which
// are intentionally free to change after insert/remove/compaction.
Campaign_Condition_Path :: struct {
	children: [CAMPAIGN_MAX_CONDITIONS]int,
	depth:    int,
}
Campaign_Workspace_Action_Kind :: enum {
	Set_Metadata,
	Add_Variable,
	Add_Condition,
	Add_Effect,
	Add_Case,
}
Campaign_Workspace_Metadata :: struct {
	version, id, title, creator, description, content_version, thumbnail: string,
}
Campaign_Workspace_Action :: struct {
	kind:       Campaign_Workspace_Action_Kind,
	metadata:   Campaign_Workspace_Metadata,
	variable:   Campaign_Variable,
	condition:  Campaign_Condition,
	effect:     Campaign_Effect,
	case_value: Campaign_Case,
}
Campaign_Recalculation :: struct {
	ok:                    bool,
	message:               string,
	cleared:               [CAMPAIGN_MAX_CASES]string,
	cleared_count, passes: int,
}
Campaign_Playthrough_Library :: struct {
	items:           [CAMPAIGN_MAX_PLAYTHROUGHS]Campaign_Playthrough,
	count, selected: int,
}
Campaign_Workspace_Tab :: enum {
	Overview,
	Cases,
	Variables,
	Conditions,
	Effects,
	Simulation,
	Diagnostics,
}
Campaign_Workspace_Text_Field :: enum {
	None,
	Campaign_Format,
	Campaign_ID,
	Campaign_Title,
	Campaign_Creator,
	Campaign_Description,
	Campaign_Version,
	Campaign_Thumbnail,
	Case_ID,
	Case_Title,
	Case_Content_Version,
	Story_Path,
	Level_Path,
	Locked_Message,
	Variable_ID,
	Variable_Name,
	Variable_Description,
	Enum_Value,
}
Campaign_Workspace_History :: struct {
	undo, redo:             [CAMPAIGN_HISTORY_LIMIT]Campaign_Definition,
	undo_count, redo_count: int,
	current:                Campaign_Definition,
	ready:                  bool,
}
Campaign_Workspace_State :: struct {
	open,
	renaming_playthrough,
	delete_confirm,
	exit_confirm:                                                     bool,
	tab:                                                                                                          Campaign_Workspace_Tab,
	text_field:                                                                                                   Campaign_Workspace_Text_Field,
	selected_case,
	selected_variable,
	selected_condition,
	selected_effect,
	selected_outcome,
	selected_enum_value: int,
	dirty:                                                                                                        bool,
	feedback,
	simulation_trace:                                                                                   string,
	diagnostics:                                                                                                  Validation,
	simulated:                                                                                                    Campaign_Playthrough,
	draft:                                                                                                        Campaign_Definition,
	history:                                                                                                      Campaign_Workspace_History,
	rename_buffer:                                                                                                [64]u8,
	rename_count:                                                                                                 int,
	text_buffer:                                                                                                  [256]u8,
	text_count:                                                                                                   int,
}
Story_Library_Kind :: enum {
	Collection,
	Standalone,
}
Campaign_Catalog_Entry :: struct {
	path, id, title, creator, description, thumbnail, requirements: string,
	kind:                                                           Story_Library_Kind,
	story_count:                                                    int,
	installed:                                                      bool,
}
Campaign_Browser_State :: struct {
	entries:         [CAMPAIGN_MAX_CATALOG]Campaign_Catalog_Entry,
	count, selected: int,
	scroll:          f32,
	feedback:        string,
}

campaign_document: Campaign_Definition
campaign_playthrough: Campaign_Playthrough
campaign_playthroughs: Campaign_Playthrough_Library
campaign_workspace: Campaign_Workspace_State
campaign_browser: Campaign_Browser_State
campaign_manifest_path: string
campaign_case_page: int
campaign_storage_override: string

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

campaign_clone :: proc(source: ^Campaign_Definition) -> Campaign_Definition {
	result := source^
	result.variables = nil; result.conditions = nil; result.effects = nil; result.cases = nil
	append(
		&result.variables,
		..source.variables[:],
	); append(&result.conditions, ..source.conditions[:]); append(&result.effects, ..source.effects[:]); append(&result.cases, ..source.cases[:])
	return result
}
campaign_destroy :: proc(doc: ^Campaign_Definition) {if doc == nil do return; delete(doc.variables)
	delete(doc.conditions)
	delete(doc.effects)
	delete(doc.cases)
	doc^ = {}}
campaign_history_clear_stack :: proc(
	items: ^[CAMPAIGN_HISTORY_LIMIT]Campaign_Definition,
	count: ^int,
) {for i in 0 ..< count^ do campaign_destroy(&items[i]); count^ = 0}
campaign_workspace_history_initialize :: proc() {h := &campaign_workspace.history
	campaign_history_clear_stack(&h.undo, &h.undo_count)
	campaign_history_clear_stack(&h.redo, &h.redo_count)
	campaign_destroy(&h.current)
	h.current = campaign_clone(&campaign_workspace.draft)
	h.ready = true}
campaign_workspace_history_record :: proc() {h := &campaign_workspace.history
	if !h.ready {campaign_workspace_history_initialize(); return}
	if h.undo_count ==
	   CAMPAIGN_HISTORY_LIMIT {campaign_destroy(&h.undo[0]); for i in 1 ..< h.undo_count do h.undo[i - 1] = h.undo[i]
		h.undo_count -= 1}
	h.undo[h.undo_count] = h.current
	h.undo_count += 1
	h.current = campaign_clone(&campaign_workspace.draft)
	campaign_history_clear_stack(&h.redo, &h.redo_count)}
campaign_workspace_history_restore :: proc(undo: bool) -> bool {h := &campaign_workspace.history
	source_count := undo ? &h.undo_count : &h.redo_count
	destination := undo ? &h.redo : &h.undo
	destination_count := undo ? &h.redo_count : &h.undo_count
	if source_count^ <= 0 do return false
	if destination_count^ ==
	   CAMPAIGN_HISTORY_LIMIT {campaign_destroy(&destination[0]); for i in 1 ..< destination_count^ do destination[i - 1] = destination[i]
		destination_count^ -= 1}
	destination[destination_count^] = campaign_clone(&campaign_workspace.draft)
	destination_count^ += 1
	campaign_destroy(&campaign_workspace.draft)
	source_count^ -= 1
	campaign_workspace.draft = (undo ? &h.undo : &h.redo)[source_count^]
	(undo ? &h.undo : &h.redo)[source_count^] = {}
	campaign_destroy(&h.current)
	h.current = campaign_clone(&campaign_workspace.draft)
	campaign_workspace.dirty = true
	campaign_workspace.diagnostics = campaign_validate(&campaign_workspace.draft)
	campaign_workspace.feedback = undo ? "CAMPAIGN UNDO" : "CAMPAIGN REDO"
	revision :=
		authoring_production_revisions(nil, nil, nil, &campaign_workspace.draft, nil)[int(Authoring_Validation_Domain.Campaign)] +
		1
	_ = authoring_invalidate_after_edit(.Campaign, revision)
	return true}
campaign_workspace_undo :: proc() -> bool {return campaign_workspace_history_restore(true)}
campaign_workspace_redo :: proc() -> bool {return campaign_workspace_history_restore(false)}

campaign_case_index :: proc(c: ^Campaign_Definition, id: string) -> int {for item, i in c.cases do if item.id == id do return i
	return -1}
campaign_first_unlocked_case :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
) -> int {for _, i in c.cases do if campaign_case_unlocked(c, p, i) do return i; return -1}
campaign_can_continue :: proc() -> bool {i := campaign_playthrough.active_case; return(
		i >= 0 &&
		i < len(campaign_document.cases) &&
		campaign_case_unlocked(&campaign_document, &campaign_playthrough, i) \
	)}
campaign_playthrough_unused :: proc(p: ^Campaign_Playthrough) -> bool {if p.completion_count != 0 do return false
	for result in p.results do if result.started || result.present do return false
	return true}
campaign_variable_index :: proc(c: ^Campaign_Definition, id: string) -> int {for item, i in c.variables do if item.id == id do return i
	return -1}
campaign_result_index :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	id: string,
) -> int {index := campaign_case_index(c, id); if index >= 0 && p.results[index].present do return index
	return -1}
campaign_enum_valid :: proc(variable: Campaign_Variable, value: string) -> bool {for i in 0 ..< clamp(variable.enum_value_count, 0, len(variable.enum_values)) do if variable.enum_values[i] == value do return true
	return false}

// Structural authoring helpers keep the flat campaign arrays internally
// consistent. They intentionally do not touch workspace selection or UI state.
campaign_variable_remove :: proc(c: ^Campaign_Definition, index: int) -> Validation {
	if c == nil || index < 0 || index >= len(c.variables) do return {false, "campaign variable index is invalid"}
	id := c.variables[index].id
	for node in c.conditions do if node.variable_id == id do return {false, fmt.tprintf("variable %s is still referenced by a condition", id)}
	for effect in c.effects do if effect.variable_id == id do return {false, fmt.tprintf("variable %s is still referenced by an effect", id)}
	ordered_remove(&c.variables, index); return {true, "CAMPAIGN VARIABLE REMOVED"}
}

campaign_variable_reorder :: proc(c: ^Campaign_Definition, from, to: int) -> bool {
	if c == nil || from < 0 || to < 0 || from >= len(c.variables) || to >= len(c.variables) do return false
	if from == to do return true
	item := c.variables[from]
	if from <
	   to {for i in from ..< to do c.variables[i] = c.variables[i + 1]} else {for i := from; i > to; i -= 1 do c.variables[i] = c.variables[i - 1]}
	c.variables[to] = item; return true
}

campaign_variable_conversion_boolean :: proc(variable: Campaign_Variable) -> bool {switch
	variable.kind {case .Boolean:
		return variable.default_boolean; case .Integer:
		return variable.default_integer != 0; case .Enumeration:
		return variable.default_enum != ""}
	return false}
campaign_variable_conversion_integer :: proc(variable: Campaign_Variable) -> int {switch
	variable.kind {case .Boolean:
		return variable.default_boolean ? 1 : 0; case .Integer:
		return variable.default_integer; case .Enumeration:
		for i in 0 ..< variable.enum_value_count do if variable.enum_values[i] == variable.default_enum do return i}
	return 0}

// Replacement carries the target type, defaults, and enum values. Its ID must
// remain stable. When repair_references is false, a type change with users is
// rejected; when true, condition/effect kinds and values are converted.
campaign_variable_convert :: proc(
	c: ^Campaign_Definition,
	index: int,
	replacement: Campaign_Variable,
	repair_references: bool,
) -> Validation {
	if c == nil || index < 0 || index >= len(c.variables) do return {false, "campaign variable index is invalid"}
	old :=
		c.variables[index]; if replacement.id != old.id do return {false, "campaign variable conversion cannot rename the variable"}
	if replacement.kind == .Enumeration && (replacement.enum_value_count <= 0 || !campaign_enum_valid(replacement, replacement.default_enum)) do return {false, "campaign enum conversion requires a valid default"}
	if !repair_references {
		if old.kind !=
		   replacement.kind {for node in c.conditions do if node.variable_id == old.id do return {false, "variable type conversion would invalidate a condition"}; for effect in c.effects do if effect.variable_id == old.id do return {false, "variable type conversion would invalidate an effect"}}
		if replacement.kind ==
		   .Enumeration {for node in c.conditions do if node.variable_id == old.id && !campaign_enum_valid(replacement, node.enum_value) do return {false, "enum conversion would invalidate a condition value"}; for effect in c.effects do if effect.variable_id == old.id && !campaign_enum_valid(replacement, effect.enum_value) do return {false, "enum conversion would invalidate an effect value"}}
	}
	for &node in c.conditions do if node.variable_id == old.id {
		switch replacement.kind {
		case .Boolean:
			if node.kind != .Boolean_Equals {node.kind = .Boolean_Equals; node.boolean_value = campaign_variable_conversion_boolean(old)}
		case .Integer:
			if node.kind != .Integer_Compare {node.kind = .Integer_Compare; node.integer_value = campaign_variable_conversion_integer(old); node.integer_comparison = .Equal}
		case .Enumeration:
			node.kind = .Enum_Equals; if !campaign_enum_valid(replacement, node.enum_value) do node.enum_value = replacement.default_enum
		}
	}
	for &effect in c.effects do if effect.variable_id == old.id {
		switch replacement.kind {
		case .Boolean:
			effect.kind = .Set_Boolean; effect.boolean_value = campaign_variable_conversion_boolean(old)
		case .Integer:
			if effect.kind != .Set_Integer && effect.kind != .Add_Integer do effect.kind = .Set_Integer; effect.integer_value = campaign_variable_conversion_integer(old)
		case .Enumeration:
			effect.kind = .Set_Enum; if !campaign_enum_valid(replacement, effect.enum_value) do effect.enum_value = replacement.default_enum
		}
	}
	c.variables[index] = replacement; return {true, "CAMPAIGN VARIABLE TYPE CONVERTED"}
}

campaign_effect_mapping_contains :: proc(
	mapping: Campaign_Outcome_Effects,
	index: int,
) -> bool {return(
		index >= mapping.first_effect &&
		index < mapping.first_effect + mapping.effect_count \
	)}

campaign_effect_remove :: proc(c: ^Campaign_Definition, index: int) -> bool {
	if c == nil || index < 0 || index >= len(c.effects) do return false
	for &item in c.cases do for mapping_index in 0 ..< item.outcome_effect_count {
		mapping := &item.outcome_effects[mapping_index]
		if index < mapping.first_effect {mapping.first_effect -= 1} else if campaign_effect_mapping_contains(mapping^, index) {mapping.effect_count -= 1}
	}
	ordered_remove(&c.effects, index); return true
}

campaign_effect_membership_equal :: proc(c: ^Campaign_Definition, a, b: int) -> bool {
	for item in c.cases do for mapping_index in 0 ..< item.outcome_effect_count {mapping := item.outcome_effects[mapping_index]; if campaign_effect_mapping_contains(mapping, a) != campaign_effect_mapping_contains(mapping, b) do return false}
	return true
}

// Moving across an outcome boundary would change which outcome owns an effect.
// Such moves are blocked; callers can remove and explicitly re-add instead.
campaign_effect_reorder :: proc(c: ^Campaign_Definition, from, to: int) -> Validation {
	if c == nil || from < 0 || to < 0 || from >= len(c.effects) || to >= len(c.effects) do return {false, "campaign effect index is invalid"}
	if from == to do return {true, "CAMPAIGN EFFECT ORDER UNCHANGED"}
	low, high :=
		min(from, to),
		max(
			from,
			to,
		); for i in low ..= high do if !campaign_effect_membership_equal(c, from, i) do return {false, "effect move crosses an outcome mapping boundary"}
	item :=
		c.effects[from]; if from < to {for i in from ..< to do c.effects[i] = c.effects[i + 1]} else {for i := from; i > to; i -= 1 do c.effects[i] = c.effects[i - 1]}; c.effects[to] = item
	return {true, "CAMPAIGN EFFECT ORDER UPDATED"}
}

campaign_condition_mark_subtree :: proc(
	c: ^Campaign_Definition,
	index: int,
	marked: []bool,
	depth: int,
) -> bool {
	if index < 0 || index >= len(c.conditions) || depth > CAMPAIGN_MAX_CONDITIONS do return false
	if marked[index] do return true; marked[index] = true; node := c.conditions[index]
	if node.kind == .All ||
	   node.kind == .Any ||
	   node.kind ==
		   .Not {if node.first_child < 0 || node.first_child + node.child_count > len(c.conditions) do return false; for child in node.first_child ..< node.first_child + node.child_count do if !campaign_condition_mark_subtree(c, child, marked, depth + 1) do return false}
	return true
}

campaign_condition_rebuild_without :: proc(c: ^Campaign_Definition, removed: []bool) -> bool {
	if len(removed) != len(c.conditions) do return false
	remap := make([]int, len(c.conditions)); defer delete(remap); for &value in remap do value = -1
	rebuilt := make(
		[dynamic]Campaign_Condition,
		0,
		len(c.conditions),
	); for node, old_index in c.conditions {if removed[old_index] do continue; remap[old_index] = len(rebuilt); append(&rebuilt, node)}
	for &node in rebuilt {if node.kind != .All && node.kind != .Any && node.kind != .Not do continue
		new_first := -1
		new_count := 0
		for old_child in node.first_child ..< node.first_child + node.child_count {if old_child < 0 || old_child >= len(remap) do return false
			if remap[old_child] < 0 do continue
			if new_first < 0 do new_first = remap[old_child]
			if remap[old_child] != new_first + new_count do return false
			new_count += 1}
		node.first_child = new_first
		node.child_count = new_count}
	for &item in c.cases {if item.condition_root < 0 do continue; if item.condition_root >= len(remap) do return false; item.condition_root = remap[item.condition_root]}
	delete(c.conditions); c.conditions = rebuilt; return true
}

campaign_condition_remove_subtree :: proc(c: ^Campaign_Definition, index: int) -> Validation {
	if c == nil || index < 0 || index >= len(c.conditions) do return {false, "campaign condition index is invalid"}
	removed := make(
		[]bool,
		len(c.conditions),
	); defer delete(removed); if !campaign_condition_mark_subtree(c, index, removed, 0) do return {false, "campaign condition subtree is malformed"}
	// A descendant shared from outside the subtree cannot be deleted safely.
	for node, parent in c.conditions {if removed[parent] || node.kind != .All && node.kind != .Any && node.kind != .Not do continue; for child in node.first_child ..< node.first_child + node.child_count do if child >= 0 && child < len(removed) && removed[child] {if child != index do return {false, "condition subtree contains a child shared by another parent"}; if node.kind == .Not || node.child_count <= 1 do return {false, "condition removal would leave its parent invalid"}}}
	for item in c.cases do if item.condition_root >= 0 && item.condition_root < len(removed) && removed[item.condition_root] && item.condition_root != index do return {false, "condition subtree is shared by another case"}
	if !campaign_condition_rebuild_without(c, removed) do return {false, "condition subtree could not be compacted"}
	return {true, "CAMPAIGN CONDITION SUBTREE REMOVED"}
}

campaign_condition_compact :: proc(c: ^Campaign_Definition) -> Validation {
	if c == nil do return {false, "campaign definition is missing"}; reachable := make([]bool, len(c.conditions)); defer delete(reachable)
	for item in c.cases do if item.condition_root >= 0 && !campaign_condition_mark_subtree(c, item.condition_root, reachable, 0) do return {false, "campaign condition tree is malformed"}
	removed := make(
		[]bool,
		len(c.conditions),
	); defer delete(removed); for value, i in reachable do removed[i] = !value
	if !campaign_condition_rebuild_without(c, removed) do return {false, "campaign conditions could not be compacted"}
	return {true, "CAMPAIGN CONDITIONS COMPACTED"}
}

campaign_reset_values :: proc(c: ^Campaign_Definition, p: ^Campaign_Playthrough) {
	for variable, i in c.variables {if i >= len(p.values) do break; p.values[i] = {
			kind          = variable.kind,
			boolean_value = variable.default_boolean,
			integer_value = variable.default_integer,
			enum_value    = variable.default_enum,
		}}
}

campaign_compare_integer :: proc(
	actual, expected: int,
	comparison: Campaign_Integer_Comparison,
) -> bool {switch comparison {case .Equal:
		return actual == expected; case .Not_Equal:
		return actual != expected; case .Less:
		return actual < expected; case .Less_Equal:
		return actual <= expected; case .Greater:
		return actual > expected; case .Greater_Equal:
		return actual >= expected}; return false}

campaign_evaluate_condition_at :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	index, depth: int,
) -> Campaign_Condition_Trace {
	if index < 0 || index >= len(c.conditions) do return {false, "missing condition"}
	if depth > CAMPAIGN_MAX_CONDITIONS do return {false, "condition nesting is too deep"}
	node := c.conditions[index]
	switch node.kind {
	case .Always:
		return {true, "always"}
	case .Never:
		return {false, "never"}
	case .All, .Any:
		if node.child_count <= 0 do return {false, "condition group is empty"}
		value := node.kind == .All; detail := ""
		for child in node.first_child ..< node.first_child + node.child_count {evaluated := campaign_evaluate_condition_at(c, p, child, depth + 1); if node.kind == .All {value = value && evaluated.value; if !evaluated.value && detail == "" do detail = evaluated.message} else {value = value || evaluated.value; if detail == "" do detail = evaluated.message; if evaluated.value do detail = evaluated.message}}
		if detail == "" do detail = node.kind == .All ? "all conditions" : "any condition"
		return {
			value,
			node.kind == .All ? (value ? "all conditions met" : fmt.tprintf("blocked by %s", detail)) : (value ? fmt.tprintf("met by %s", detail) : fmt.tprintf("none met; first check: %s", detail)),
		}
	case .Not:
		if node.child_count != 1 do return {false, "NOT requires one child"}
		child := campaign_evaluate_condition_at(
			c,
			p,
			node.first_child,
			depth + 1,
		); return {!child.value, fmt.tprintf("not (%s)", child.message)}
	case .Boolean_Equals, .Integer_Compare, .Enum_Equals:
		variable := campaign_variable_index(c, node.variable_id)
		if variable < 0 do return {false, fmt.tprintf("unknown variable %s", node.variable_id)}
		actual := p.values[variable]
		if node.kind == .Boolean_Equals do return {actual.boolean_value == node.boolean_value, fmt.tprintf("%s is %t", node.variable_id, node.boolean_value)}
		if node.kind == .Integer_Compare do return {campaign_compare_integer(actual.integer_value, node.integer_value, node.integer_comparison), fmt.tprintf("%s compared with %d", node.variable_id, node.integer_value)}
		return {
			actual.enum_value == node.enum_value,
			fmt.tprintf("%s is %s", node.variable_id, node.enum_value),
		}
	case .Case_Started, .Case_Completed, .Case_Outcome:
		case_index := campaign_case_index(c, node.case_id)
		if case_index < 0 do return {false, fmt.tprintf("unknown case %s", node.case_id)}
		result := p.results[case_index]
		if node.kind == .Case_Started do return {result.started || result.present, fmt.tprintf("%s started", node.case_id)}
		if node.kind == .Case_Completed do return {result.present, fmt.tprintf("%s completed", node.case_id)}
		return {
			result.present && result.outcome == node.outcome,
			fmt.tprintf("%s outcome", node.case_id),
		}
	}
	return {false, "unsupported condition"}
}

campaign_evaluate_condition :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	root: int,
) -> Campaign_Condition_Trace {return campaign_evaluate_condition_at(c, p, root, 0)}
campaign_case_unlocked :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	index: int,
) -> bool {if index < 0 || index >= len(c.cases) do return false; item := c.cases[index]
	if item.condition_root < 0 do return true
	return campaign_evaluate_condition(c, p, item.condition_root).value}

campaign_effect_range :: proc(item: Campaign_Case, outcome: Outcome) -> (int, int) {for 	i in 0 ..< clamp(item.outcome_effect_count, 0, len(item.outcome_effects)) {entry :=
			item.outcome_effects[i]
		if entry.outcome == outcome do return entry.first_effect, entry.effect_count}
	return 0, 0}
campaign_apply_effect :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	effect: Campaign_Effect,
) -> bool {
	index := campaign_variable_index(c, effect.variable_id); if index < 0 do return false
	value := &p.values[index]
	switch effect.kind {case .Set_Boolean:
		value.boolean_value = effect.boolean_value; case .Set_Integer:
		value.integer_value = effect.integer_value; case .Add_Integer:
		value.integer_value += effect.integer_value; case .Set_Enum:
		value.enum_value = effect.enum_value}
	return true
}

campaign_rebuild_values :: proc(c: ^Campaign_Definition, p: ^Campaign_Playthrough) {
	campaign_reset_values(c, p)
	// Completion sequence makes replay recalculation independent of case display order.
	for sequence in 1 ..< p.next_completion_sequence {for result, i in p.results do if result.present && result.completion_sequence == sequence {first, count := campaign_effect_range(c.cases[i], result.outcome); for effect_index in first ..< first + count do if effect_index >= 0 && effect_index < len(c.effects) do _ = campaign_apply_effect(c, p, c.effects[effect_index])}}
}

campaign_recalculate :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
) -> Campaign_Recalculation {
	result := Campaign_Recalculation {
		ok      = true,
		message = "CAMPAIGN RECALCULATED",
	}
	for pass in 0 ..< CAMPAIGN_RECALCULATE_LIMIT {
		result.passes = pass + 1; campaign_rebuild_values(c, p); changed := false
		for item, i in c.cases {if p.results[i].present && !campaign_case_unlocked(c, p, i) && item.invalid_result_policy == .Clear {result.cleared[result.cleared_count] = item.id; result.cleared_count += 1; p.results[i] = {}; p.completion_count -= 1; changed = true}}
		if !changed {campaign_rebuild_values(c, p); return result}
	}
	return {ok = false, message = "campaign result invalidation did not stabilize"}
}

campaign_apply_result :: proc(
	c: ^Campaign_Definition,
	p: ^Campaign_Playthrough,
	new_result: Campaign_Case_Result,
) -> Validation {
	result_record := new_result
	index := campaign_case_index(
		c,
		new_result.case_id,
	); if index < 0 do return {false, "result references an unknown campaign case"}
	existing := p.results[index]; item := c.cases[index]
	if new_result.case_content_version != "" && new_result.case_content_version != item.case_content_version do return {false, "case result version is incompatible with the campaign"}
	if existing.present && item.replay_mode != .Replace_Outcome do return item.replay_mode == .Effectless ? Validation{true, "REPLAY HAS NO CAMPAIGN EFFECT"} : Validation{false, "campaign case cannot replace its result"}
	if !existing.present && !campaign_case_unlocked(c, p, index) do return {false, "case result cannot be applied before the case unlocks"}
	before := p^
	if !existing.present {p.completion_count += 1; result_record.completion_sequence = p.next_completion_sequence; p.next_completion_sequence += 1} else do result_record.completion_sequence = existing.completion_sequence
	result_record.present =
		true; result_record.started = true; if result_record.case_content_version == "" do result_record.case_content_version = item.case_content_version; p.results[index] = result_record
	recalculated := campaign_recalculate(
		c,
		p,
	); if !recalculated.ok {p^ = before; return {false, recalculated.message}}
	return {true, "RESULT APPLIED"}
}

campaign_validate_condition :: proc(c: ^Campaign_Definition, index, depth: int) -> Validation {
	if index < 0 || index >= len(c.conditions) do return {false, "case has a missing unlock condition"}; if depth > CAMPAIGN_MAX_CONDITIONS do return {false, "campaign condition nesting is too deep"}; node := c.conditions[index]
	if node.kind == .All ||
	   node.kind ==
		   .Any {if node.child_count <= 0 do return {false, "campaign condition group is empty"}}
	if node.kind == .Not && node.child_count != 1 do return {false, "campaign NOT condition requires one child"}
	if node.kind == .All ||
	   node.kind == .Any ||
	   node.kind ==
		   .Not {if node.first_child < 0 || node.first_child + node.child_count > len(c.conditions) do return {false, "campaign condition child range is invalid"}; for child in node.first_child ..< node.first_child + node.child_count {valid := campaign_validate_condition(c, child, depth + 1); if !valid.ok do return valid}}
	if node.kind == .Boolean_Equals ||
	   node.kind == .Integer_Compare ||
	   node.kind ==
		   .Enum_Equals {variable_index := campaign_variable_index(c, node.variable_id); if variable_index < 0 do return {false, fmt.tprintf("condition references unknown variable %s", node.variable_id)}; variable := c.variables[variable_index]; expected: Campaign_Value_Kind = .Boolean; if node.kind == .Integer_Compare do expected = .Integer
		else if node.kind == .Enum_Equals do expected = .Enumeration; if variable.kind != expected do return {false, fmt.tprintf("condition type does not match variable %s", node.variable_id)}; if expected == .Enumeration && !campaign_enum_valid(variable, node.enum_value) do return {false, "condition uses an invalid enum value"}}
	if node.kind == .Case_Started ||
	   node.kind == .Case_Completed ||
	   node.kind ==
		   .Case_Outcome {if campaign_case_index(c, node.case_id) < 0 do return {false, fmt.tprintf("condition references unknown case %s", node.case_id)}}
	return {true, ""}
}

campaign_validate :: proc(c: ^Campaign_Definition) -> Validation {
	if c.version != "MysteryCampaign v2" do return {false, "unsupported campaign version"}
	if c.id == "" || c.title == "" || c.content_version == "" do return {false, "campaign metadata is incomplete"}
	if len(c.cases) == 0 || len(c.cases) > CAMPAIGN_MAX_CASES do return {false, "campaign requires one to sixteen cases"}
	if len(c.variables) > CAMPAIGN_MAX_VARIABLES || len(c.conditions) > CAMPAIGN_MAX_CONDITIONS || len(c.effects) > CAMPAIGN_MAX_EFFECTS do return {false, "campaign exceeds format limits"}
	for variable, i in c.variables {if variable.id == "" || variable.display_name == "" do return {false, "campaign variable metadata is incomplete"}; for prior in 0 ..< i do if c.variables[prior].id == variable.id do return {false, "campaign contains a duplicate variable ID"}; if variable.kind == .Enumeration {if variable.enum_value_count <= 0 || !campaign_enum_valid(variable, variable.default_enum) do return {false, "campaign enum default is invalid"}; for value_index in 0 ..< variable.enum_value_count {if variable.enum_values[value_index] == "" do return {false, "campaign enum value is empty"}; for prior in 0 ..< value_index do if variable.enum_values[prior] == variable.enum_values[value_index] do return {false, "campaign enum values must be unique"}}}}
	for item, i in c.cases {if item.id == "" || item.title == "" || item.story_path == "" || item.case_content_version == "" do return {false, "campaign case metadata is incomplete"}; for prior in 0 ..< i do if c.cases[prior].id == item.id do return {false, "campaign contains a duplicate case ID"}; if item.required == item.optional do return {false, "campaign case must be either required or optional"}; if item.condition_root >= 0 {valid := campaign_validate_condition(c, item.condition_root, 0); if !valid.ok do return valid}; for mapping_index in 0 ..< item.outcome_effect_count {mapping := item.outcome_effects[mapping_index]; if mapping.first_effect < 0 || mapping.effect_count < 0 || mapping.first_effect + mapping.effect_count > len(c.effects) do return {false, "campaign case effect range is invalid"}}}
	for effect in c.effects {variable_index := campaign_variable_index(c, effect.variable_id); if variable_index < 0 do return {false, fmt.tprintf("effect references unknown variable %s", effect.variable_id)}; variable := c.variables[variable_index]; expected: Campaign_Value_Kind = .Integer; if effect.kind == .Set_Boolean do expected = .Boolean
		else if effect.kind == .Set_Enum do expected = .Enumeration; if variable.kind != expected do return {false, "campaign effect type does not match its variable"}; if expected == .Enumeration && !campaign_enum_valid(variable, effect.enum_value) do return {false, "campaign effect uses an invalid enum value"}}
	probe := Campaign_Playthrough {
		campaign_id              = c.id,
		campaign_content_version = c.content_version,
		next_completion_sequence = 1,
	}; campaign_reset_values(
		c,
		&probe,
	); startable := false; for _, i in c.cases do if campaign_case_unlocked(c, &probe, i) do startable = true; if !startable do return {false, "campaign has no initially available case"}
	return {true, "CAMPAIGN VALID"}
}

load_campaign_manifest :: proc(
	path: string,
	out: ^Campaign_Definition,
) -> Validation {cpath, error := strings.clone_to_cstring(path, context.temp_allocator)
	if error != nil do return {false, "invalid campaign path"}
	parsed := toml_parse_file_ex(cpath)
	defer toml_free(parsed)
	if !parsed.ok do return toml_parse_diagnostic(path, "campaign", &parsed)
	top := parsed.toptab
	out^ = {
		version         = toml_case_string(top, "version"),
		id              = toml_case_string(top, "id"),
		title           = toml_case_string(top, "title"),
		creator         = toml_case_string(top, "creator"),
		description     = toml_case_string(top, "description"),
		content_version = toml_case_string(top, "content_version"),
		thumbnail       = toml_case_string(top, "thumbnail"),
	}
	for table in toml_tables(top, "variables") {variable := Campaign_Variable {
			id              = toml_case_string(table, "id"),
			display_name    = toml_case_string(table, "display_name"),
			description     = toml_case_string(table, "description"),
			kind            = Campaign_Value_Kind(clamp(toml_case_int(table, "kind"), 0, 2)),
			default_boolean = toml_case_bool(table, "default_boolean"),
			default_integer = toml_case_int(table, "default_integer"),
			default_enum    = toml_case_string(table, "default_enum"),
		}; values := toml_case_strings(
			table,
			"enum_values",
		); variable.enum_value_count = min(len(values), len(variable.enum_values)); for value, i in values do if i < variable.enum_value_count do variable.enum_values[i] = value; append(&out.variables, variable)}
	for table in toml_tables(top, "conditions") do append(&out.conditions, Campaign_Condition{kind = Campaign_Condition_Kind(clamp(toml_case_int(table, "kind"), 0, int(Campaign_Condition_Kind.Case_Outcome))), first_child = toml_case_int(table, "first_child"), child_count = toml_case_int(table, "child_count"), variable_id = toml_case_string(table, "variable_id"), case_id = toml_case_string(table, "case_id"), enum_value = toml_case_string(table, "enum_value"), boolean_value = toml_case_bool(table, "boolean_value"), integer_value = toml_case_int(table, "integer_value"), integer_comparison = Campaign_Integer_Comparison(clamp(toml_case_int(table, "comparison"), 0, 5)), outcome = Outcome(clamp(toml_case_int(table, "outcome"), 0, 4))})
	for table in toml_tables(top, "effects") do append(&out.effects, Campaign_Effect{kind = Campaign_Effect_Kind(clamp(toml_case_int(table, "kind"), 0, 3)), variable_id = toml_case_string(table, "variable_id"), boolean_value = toml_case_bool(table, "boolean_value"), integer_value = toml_case_int(table, "integer_value"), enum_value = toml_case_string(table, "enum_value")})
	for table in toml_tables(
		top,
		"cases",
	) {condition := toml_case_int(table, "condition_root"); if len(out.conditions) == 0 {condition = 0; append(&out.conditions, Campaign_Condition{kind = .Always})}
		item := Campaign_Case {
			id                       = toml_case_string(table, "id"),
			title                    = toml_case_string(table, "title"),
			story_path               = toml_case_string(table, "story_path"),
			level_path               = toml_case_string(table, "level_path"),
			case_content_version     = toml_case_string(table, "content_version"),
			locked_message           = toml_case_string(table, "locked_message"),
			condition_root           = condition,
			required                 = toml_case_bool(table, "required"),
			optional                 = toml_case_bool(table, "optional"),
			unavailable_presentation = Campaign_Unavailable_Presentation(
				clamp(toml_case_int(table, "presentation"), 0, 2),
			),
			replay_mode              = Campaign_Replay_Mode(
				clamp(toml_case_int(table, "replay_mode"), 0, 2),
			),
			invalid_result_policy    = Campaign_Invalid_Result_Policy(
				clamp(toml_case_int(table, "invalid_policy"), 0, 1),
			),
		}
		outcomes := toml_case_ints(table, "effect_outcomes")
		firsts := toml_case_ints(table, "effect_firsts")
		counts := toml_case_ints(table, "effect_counts")
		item.outcome_effect_count = min(
			min(len(outcomes), len(firsts)),
			min(len(counts), len(item.outcome_effects)),
		)
		for i in 0 ..< item.outcome_effect_count do item.outcome_effects[i] = {
			outcome      = Outcome(clamp(outcomes[i], 0, 4)),
			first_effect = firsts[i],
			effect_count = counts[i],
		}
		append(&out.cases, item)}
	return campaign_validate(out)}

campaign_toml_escape :: proc(value: string) -> string {result := ""; for 	rune in value {if rune == '\\' do result = fmt.tprintf("%s\\\\", result)
		else if rune == '\"' do result = fmt.tprintf("%s\\\"", result)
		else if rune == '\n' do result = fmt.tprintf("%s\\n", result)
		else do result = fmt.tprintf("%s%c", result, rune)}
	return result}
campaign_serialize :: proc(c: ^Campaign_Definition) -> string {text := fmt.tprintf(
		"version = \"%s\"\nid = \"%s\"\ntitle = \"%s\"\ncreator = \"%s\"\ndescription = \"%s\"\ncontent_version = \"%s\"\nthumbnail = \"%s\"\n",
		campaign_toml_escape(c.version),
		campaign_toml_escape(c.id),
		campaign_toml_escape(c.title),
		campaign_toml_escape(c.creator),
		campaign_toml_escape(c.description),
		campaign_toml_escape(c.content_version),
		campaign_toml_escape(c.thumbnail),
	)
	for 	variable in c.variables {values := ""; for 		i in 0 ..< variable.enum_value_count {if i > 0 do values = fmt.tprintf("%s, ", values); values =
				fmt.tprintf("%s\"%s\"", values, campaign_toml_escape(variable.enum_values[i]))}
		text = fmt.tprintf(
			"%s\n[[variables]]\nid = \"%s\"\ndisplay_name = \"%s\"\ndescription = \"%s\"\nkind = %d\ndefault_boolean = %t\ndefault_integer = %d\ndefault_enum = \"%s\"\nenum_values = [%s]\n",
			text,
			campaign_toml_escape(variable.id),
			campaign_toml_escape(variable.display_name),
			campaign_toml_escape(variable.description),
			int(variable.kind),
			variable.default_boolean,
			variable.default_integer,
			campaign_toml_escape(variable.default_enum),
			values,
		)}
	for node in c.conditions do text = fmt.tprintf("%s\n[[conditions]]\nkind = %d\nfirst_child = %d\nchild_count = %d\nvariable_id = \"%s\"\ncase_id = \"%s\"\nenum_value = \"%s\"\nboolean_value = %t\ninteger_value = %d\ncomparison = %d\noutcome = %d\n", text, int(node.kind), node.first_child, node.child_count, campaign_toml_escape(node.variable_id), campaign_toml_escape(node.case_id), campaign_toml_escape(node.enum_value), node.boolean_value, node.integer_value, int(node.integer_comparison), int(node.outcome))
	for effect in c.effects do text = fmt.tprintf("%s\n[[effects]]\nkind = %d\nvariable_id = \"%s\"\nboolean_value = %t\ninteger_value = %d\nenum_value = \"%s\"\n", text, int(effect.kind), campaign_toml_escape(effect.variable_id), effect.boolean_value, effect.integer_value, campaign_toml_escape(effect.enum_value))
	for 	item in c.cases {outcomes, firsts, counts := "", "", ""; for 		i in 0 ..< item.outcome_effect_count {if i > 0 {outcomes = fmt.tprintf("%s, ", outcomes); firsts =
					fmt.tprintf("%s, ", firsts)
				counts = fmt.tprintf("%s, ", counts)}
			outcomes = fmt.tprintf("%s%d", outcomes, int(item.outcome_effects[i].outcome))
			firsts = fmt.tprintf("%s%d", firsts, item.outcome_effects[i].first_effect)
			counts = fmt.tprintf("%s%d", counts, item.outcome_effects[i].effect_count)}
		text = fmt.tprintf(
			"%s\n[[cases]]\nid = \"%s\"\ntitle = \"%s\"\nstory_path = \"%s\"\nlevel_path = \"%s\"\ncontent_version = \"%s\"\ncondition_root = %d\nrequired = %t\noptional = %t\npresentation = %d\nlocked_message = \"%s\"\nreplay_mode = %d\ninvalid_policy = %d\neffect_outcomes = [%s]\neffect_firsts = [%s]\neffect_counts = [%s]\n",
			text,
			campaign_toml_escape(item.id),
			campaign_toml_escape(item.title),
			campaign_toml_escape(item.story_path),
			campaign_toml_escape(item.level_path),
			campaign_toml_escape(item.case_content_version),
			item.condition_root,
			item.required,
			item.optional,
			int(item.unavailable_presentation),
			campaign_toml_escape(item.locked_message),
			int(item.replay_mode),
			int(item.invalid_result_policy),
			outcomes,
			firsts,
			counts,
		)}
	return text}
save_campaign_manifest :: proc(path: string, c: ^Campaign_Definition) -> Validation {valid :=
		campaign_validate(c)
	if !valid.ok do return valid
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, transmute([]u8)campaign_serialize(c)) != nil do return {false, "could not write campaign"}
	if os.rename(temporary, path) != nil do return {false, "could not replace campaign"}
	campaign_workspace.dirty = false
	return{true, "CAMPAIGN SAVED"}}

campaign_requirement_label :: proc(doc: ^Campaign_Definition) -> string {label := "CORE"
	seen: [STORY_MAX_CAPABILITIES]string
	seen_count := 0
	for item in doc.cases {story: Story_Project; if !load_story_project(item.story_path, &story).ok do continue
		for capability in story.capabilities {duplicate := false; for existing in seen[:seen_count] do if existing == capability.id do duplicate = true
			if duplicate do continue
			if seen_count < len(seen) {seen[seen_count] = capability.id; seen_count += 1}
			label = fmt.tprintf("%s + %s", label, strings.to_upper(capability.id))}
		for requirement in story.expansion_requirements {duplicate := false; for existing in seen[:seen_count] do if existing == requirement.id do duplicate = true
			if duplicate do continue
			if seen_count < len(seen) {seen[seen_count] = requirement.id; seen_count += 1}
			label = fmt.tprintf("%s + %s", label, strings.to_upper(requirement.id))}
		story_project_destroy(&story)}
	return label}

campaign_discover_add :: proc(path: string, installed: bool = false) {if campaign_browser.count >= CAMPAIGN_MAX_CATALOG do return
	doc: Campaign_Definition
	loaded := load_campaign_manifest(path, &doc)
	if !loaded.ok || !campaign_validate(&doc).ok do return
	for existing in campaign_browser.entries[:campaign_browser.count] do if existing.id == doc.id && existing.path == path do return
	owned_path := strings.clone(path, context.allocator)
	campaign_browser.entries[campaign_browser.count] = {
			path         = owned_path,
			id           = doc.id,
			title        = doc.title,
			creator      = doc.creator,
			description  = doc.description,
			thumbnail    = doc.thumbnail,
			requirements = campaign_requirement_label(&doc),
			kind         = .Collection,
			story_count  = len(doc.cases),
			installed    = installed,
		}
	campaign_browser.count += 1}

campaign_discover :: proc() {
	campaign_browser =
		{}; source := "assets/campaigns"; files, source_error := os.read_directory_by_path(source, -1, context.temp_allocator); if source_error == nil {for file in files {if file.type == .Directory || strings.to_lower(os.ext(file.name)) != ".toml" do continue; path, error := os.join_path({source, file.name}, context.temp_allocator); if error == nil do campaign_discover_add(path, false)}}
	data_dir, data_error := os.user_data_dir(
		context.temp_allocator,
	); if data_error == nil {installed, error := os.join_path([]string{data_dir, APP_STORAGE_NAME, "Campaigns"}, context.temp_allocator); if error == nil && os.exists(installed) {campaign_ids, id_error := os.read_directory_by_path(installed, -1, context.temp_allocator); if id_error == nil {for campaign_id in campaign_ids {if campaign_id.type != .Directory do continue; id_path, e := os.join_path({installed, campaign_id.name}, context.temp_allocator); if e != nil do continue; versions, version_error := os.read_directory_by_path(id_path, -1, context.temp_allocator); if version_error != nil do continue; for version in versions {if version.type != .Directory do continue; manifest, e2 := os.join_path({id_path, version.name, "runtime", "campaign.toml"}, context.temp_allocator); if e2 == nil && os.exists(manifest) do campaign_discover_add(manifest, true)}}}}}
	if data_error ==
	   nil {stories, error := os.join_path([]string{data_dir, APP_STORAGE_NAME, "Stories"}, context.temp_allocator); if error == nil && os.exists(stories) {story_ids, id_error := os.read_directory_by_path(stories, -1, context.temp_allocator); if id_error == nil {for story_id in story_ids {if story_id.type != .Directory do continue; id_path, e := os.join_path({stories, story_id.name}, context.temp_allocator); if e != nil do continue; versions, version_error := os.read_directory_by_path(id_path, -1, context.temp_allocator); if version_error != nil do continue; for version in versions {if version.type != .Directory do continue; manifest, e2 := os.join_path({id_path, version.name, "standalone-campaign.toml"}, context.temp_allocator); if e2 == nil && os.exists(manifest) do campaign_discover_add(manifest, true)}}}}}
	if campaign_browser.count == 0 do campaign_browser.feedback = "NO VALID CAMPAIGNS FOUND"
}

campaign_choose :: proc(index: int) -> Validation {
	if index < 0 || index >= campaign_browser.count do return {false, "campaign is unavailable"}
	// The story library is outside the Authoring workspace, so it cannot show
	// that workspace's pending-lifecycle modal. Preserve dirty drafts
	// automatically before replacing the active source documents; otherwise a
	// library card can leave the player trapped on an unactionable warning.
	preserved_recovery := false
	if active_authoring_ready {guard := authoring_app_dirty_guard(); if !guard.ok {preserved := authoring_app_save_recovery(); if !preserved.ok do return {false, fmt.tprintf("could not preserve authoring drafts before opening campaign: %s", preserved.message)}; preserved_recovery = true}}
	next: Campaign_Definition; loaded := load_campaign_manifest(campaign_browser.entries[index].path, &next); if !loaded.ok do return loaded; if valid := campaign_validate(&next); !valid.ok do return valid
	campaign_document =
		next; campaign_manifest_path = campaign_browser.entries[index].path; campaign_browser.selected = index; campaign_case_page = 0; player_package_mode = player_package_forced || campaign_browser.entries[index].installed; graph_autosave_enabled = !player_package_mode; campaign_load_library(); campaign_workspace.feedback = ""; if active_authoring_ready {_ = authoring_app_initialize(campaign_document.cases[0].story_path, campaign_document.cases[0].level_path)}; return {true, preserved_recovery ? "CAMPAIGN SELECTED · UNSAVED DRAFTS PRESERVED IN RECOVERY" : "CAMPAIGN SELECTED"}
}

campaign_initialize :: proc() {campaign_discover(); if campaign_browser.count > 0 {selected :=
			campaign_choose(0)
		if !selected.ok do fmt.eprintln(selected.message)}
	else do fmt.eprintln(campaign_browser.feedback)}

campaign_outcome_from_text :: proc(value: string) -> (Outcome, bool) {upper := strings.to_upper(
		value,
	)
	switch
	upper {case "AIRTIGHT":
		return .Airtight, true; case "CORRECT_BUT_UNPROVEN":
		return .Correct_But_Unproven, true; case "PLAUSIBLE_INCOMPLETE":
		return .Plausible_Incomplete, true; case "WRONG_ACCUSATION":
		return .Wrong_Accusation, true; case "UNRESOLVED":
		return .Unresolved, true}
	return .Unresolved, false}

campaign_outcome_text :: proc(value: Outcome) -> string {switch value {case .Airtight:
		return "airtight"; case .Correct_But_Unproven:
		return "correct_but_unproven"; case .Plausible_Incomplete:
		return "plausible_incomplete"; case .Wrong_Accusation:
		return "wrong_accusation"; case .Unresolved:
		return "unresolved"}; return "unresolved"}

campaign_safe_id :: proc(value: string) -> bool {if value == "" do return false; for rune in value do if !(rune >= 'a' && rune <= 'z' || rune >= 'A' && rune <= 'Z' || rune >= '0' && rune <= '9' || rune == '-' || rune == '_') do return false
	return true}
campaign_progress_filename :: proc(id: string) -> string {return fmt.tprintf(
		"campaign-%s-%s.progress",
		campaign_document.id,
		id,
	)}
campaign_storage_path_for :: proc(filename, storage_name: string) -> (string, bool) {dir :=
		campaign_storage_override
	if dir == "" {data_dir, data_error := os.user_data_dir(context.temp_allocator)
		if data_error != nil do return "", false
		join_error: os.Error
		dir, join_error = os.join_path(
			[]string{data_dir, storage_name, "Campaign Progress"},
			context.temp_allocator,
		)
		if join_error != nil do return "", false}
	if !os.exists(dir) && os.make_directory_all(dir) != nil do return "", false
	path, path_error := os.join_path([]string{dir, filename}, context.temp_allocator)
	return path, path_error == nil}
campaign_storage_path :: proc(
	filename: string,
) -> (
	string,
	bool,
) {return campaign_storage_path_for(filename, APP_STORAGE_NAME)}
campaign_write_storage :: proc(filename: string, data: []u8) -> bool {path, ok :=
		campaign_storage_path(filename)
	if !ok {fmt.eprintln("campaign storage path unavailable"); return false}
	if error := os.write_entire_file(path, data); error != nil {fmt.eprintln(
			"campaign storage write failed: ",
			path,
			" ",
			error,
		)
		return false}
	return true}
campaign_read_storage :: proc(filename: string) -> ([]byte, bool) {path, ok :=
		campaign_storage_path(filename)
	if !ok do return nil, false
	data, error := os.read_entire_file_from_path(path, context.temp_allocator)
	return data, error == nil}

campaign_save_playthrough :: proc(p: ^Campaign_Playthrough) -> bool {
	if !campaign_safe_id(p.id) || strings.contains(p.name, "|") || strings.contains(p.name, "\n") do return false
	text := fmt.tprintf(
		"version=1\ncampaign_id=%s\ncampaign_version=%s\nplaythrough_id=%s\nname=%s\nactive_case=%d\nnext_sequence=%d\n",
		p.campaign_id,
		p.campaign_content_version,
		p.id,
		p.name,
		p.active_case,
		p.next_completion_sequence,
	)
	for result in p.results do if result.present do text = fmt.tprintf("%sresult=%s|%s|%s|%d\n", text, result.case_id, result.case_content_version, campaign_outcome_text(result.outcome), result.completion_sequence)
	return campaign_write_storage(campaign_progress_filename(p.id), transmute([]u8)text)
}

campaign_load_playthrough_id :: proc(id: string, out: ^Campaign_Playthrough) -> bool {
	if !campaign_safe_id(id) do return false; data, found := campaign_read_storage(campaign_progress_filename(id)); if !found do return false; text := string(data)
	loaded := Campaign_Playthrough {
		campaign_id              = campaign_document.id,
		campaign_content_version = campaign_document.content_version,
		id                       = id,
		name                     = "Investigation",
		active_case              = -1,
		next_completion_sequence = 1,
	}; campaign_reset_values(&campaign_document, &loaded)
	stored_version := ""; for line in strings.split_lines_iterator(&text) {if strings.has_prefix(line, "campaign_id=") && line[12:] != campaign_document.id do return false; if strings.has_prefix(line, "campaign_version=") do stored_version = line[17:]; if strings.has_prefix(line, "playthrough_id=") && line[15:] != id do return false; if strings.has_prefix(line, "name=") do loaded.name = line[5:]; if strings.has_prefix(line, "active_case=") {value, ok := strconv.parse_i64(line[12:]); if ok do loaded.active_case = clamp(int(value), -1, len(campaign_document.cases) - 1)}; if strings.has_prefix(line, "next_sequence=") {value, ok := strconv.parse_u64(line[14:]); if ok do loaded.next_completion_sequence = value}; if strings.has_prefix(line, "result=") {parts, _ := strings.split(line[7:], "|", context.temp_allocator); if len(parts) != 4 do return false; index := campaign_case_index(&campaign_document, parts[0]); if index < 0 || parts[1] != campaign_document.cases[index].case_content_version do return false; outcome, valid := campaign_outcome_from_text(parts[2]); sequence, sequence_ok := strconv.parse_u64(parts[3]); if !valid || !sequence_ok do return false; loaded.results[index] = {
				present              = true,
				started              = true,
				case_id              = parts[0],
				case_content_version = parts[1],
				outcome              = outcome,
				completion_sequence  = sequence,
			}; loaded.completion_count += 1}}
	loaded.campaign_content_version =
		campaign_document.content_version; out^ = loaded; recalculated := campaign_recalculate(&campaign_document, out); if !recalculated.ok do return false; if stored_version != "" && stored_version != campaign_document.content_version do _ = campaign_save_playthrough(out); return true
}

campaign_library_filename :: proc() -> string {return fmt.tprintf(
		"campaign-%s-playthroughs.index",
		campaign_document.id,
	)}
campaign_save_library_index :: proc() -> bool {text := "version=1\n"; for i in 0 ..< campaign_playthroughs.count do text = fmt.tprintf("%splaythrough=%s\n", text, campaign_playthroughs.items[i].id)
	text = fmt.tprintf("%sselected=%d\n", text, campaign_playthroughs.selected)
	return campaign_write_storage(campaign_library_filename(), transmute([]u8)text)}
campaign_select_playthrough :: proc(index: int) -> bool {if index < 0 || index >= campaign_playthroughs.count do return false
	before := campaign_playthroughs.selected
	campaign_playthroughs.selected = index
	if !campaign_save_library_index() {campaign_playthroughs.selected = before; return false}
	campaign_playthrough = campaign_playthroughs.items[index]
	return true}
campaign_create_playthrough :: proc(name: string) -> bool {if campaign_playthroughs.count >= CAMPAIGN_MAX_PLAYTHROUGHS || name == "" do return false
	before := campaign_playthroughs
	before_active := campaign_playthrough
	number := 1
	id := ""
	for {id = fmt.tprintf("run-%d", number); duplicate := false; for i in 0 ..< campaign_playthroughs.count do if campaign_playthroughs.items[i].id == id do duplicate = true
		if !duplicate do break
		number += 1}
	p := Campaign_Playthrough {
		campaign_id              = campaign_document.id,
		campaign_content_version = campaign_document.content_version,
		id                       = id,
		name                     = name,
		active_case              = -1,
		next_completion_sequence = 1,
	}
	campaign_reset_values(&campaign_document, &p)
	campaign_playthroughs.items[campaign_playthroughs.count] = p
	campaign_playthroughs.count += 1
	campaign_playthroughs.selected = campaign_playthroughs.count - 1
	campaign_playthrough = p
	if !campaign_save_playthrough(&p) || !campaign_save_library_index() {campaign_playthroughs =
			before
		campaign_playthrough = before_active
		return false}
	return true}
campaign_rename_playthrough :: proc(index: int, name: string) -> bool {if index < 0 || index >= campaign_playthroughs.count || name == "" || strings.contains(name, "\n") || strings.contains(name, "|") do return false
	old_name := campaign_playthroughs.items[index].name
	campaign_playthroughs.items[index].name = name
	if !campaign_save_playthrough(
		&campaign_playthroughs.items[index],
	) {campaign_playthroughs.items[index].name = old_name; return false}
	if index == campaign_playthroughs.selected do campaign_playthrough.name = name
	return true}
campaign_delete_playthrough :: proc(index: int) -> bool {if campaign_playthroughs.count <= 1 || index < 0 || index >= campaign_playthroughs.count do return false
	before := campaign_playthroughs
	before_active := campaign_playthrough
	deleted_id := campaign_playthroughs.items[index].id
	for i in index + 1 ..< campaign_playthroughs.count do campaign_playthroughs.items[i - 1] = campaign_playthroughs.items[i]
	campaign_playthroughs.count -= 1
	campaign_playthroughs.selected = clamp(
		campaign_playthroughs.selected,
		0,
		campaign_playthroughs.count - 1,
	)
	campaign_playthrough = campaign_playthroughs.items[campaign_playthroughs.selected]
	if !campaign_save_library_index() {campaign_playthroughs = before; campaign_playthrough =
			before_active
		return false}
	path, ok := campaign_storage_path(campaign_progress_filename(deleted_id))
	if ok && os.exists(path) do _ = os.remove(path)
	return true}
campaign_load_library :: proc() {campaign_playthroughs = {}; data, found := campaign_read_storage(
		campaign_library_filename(),
	)
	if found {text := string(data); selected := 0; for 		line in strings.split_lines_iterator(&text) {if strings.has_prefix(line, "playthrough=") &&
			   campaign_playthroughs.count < CAMPAIGN_MAX_PLAYTHROUGHS {p: Campaign_Playthrough
				if campaign_load_playthrough_id(line[12:], &p) {campaign_playthroughs.items[campaign_playthroughs.count] =
						p
					campaign_playthroughs.count += 1}}
			if strings.has_prefix(line, "selected=") {value, ok := strconv.parse_i64(line[9:])
				if ok do selected = int(value)}}
		campaign_playthroughs.selected = clamp(
			selected,
			0,
			max(campaign_playthroughs.count - 1, 0),
		)}
	if campaign_playthroughs.count == 0 {_ = campaign_create_playthrough("Investigation 1")}
	else do _ = campaign_select_playthrough(campaign_playthroughs.selected)}

campaign_workspace_record_project_path :: proc(path: string) {
	if !active_authoring_ready || path == "" do return
	root := strings.trim_right(
		active_authoring_project.root_path,
		"/",
	); prefix := fmt.tprintf("%s/", root)
	if !strings.has_prefix(path, prefix) do return
	relative := path[len(prefix):]
	if !authoring_relative_path_valid(relative) do return
	active_authoring_project.campaign_path = strings.clone(relative)
	if active_authoring_project.export_directory == "" do active_authoring_project.export_directory = "exports"
	_ = authoring_project_save_manifest(&active_authoring_project)
}
campaign_workspace_begin :: proc() {draft := Campaign_Definition{}; loaded :=
		load_campaign_manifest(campaign_manifest_path, &draft)
	if !loaded.ok do draft = campaign_clone(&campaign_document)
	campaign_workspace = {
		open               = true,
		tab                = .Overview,
		selected_case      = 0,
		selected_variable  = 0,
		selected_condition = 0,
		simulated          = campaign_playthrough,
		draft              = draft,
	}
	campaign_workspace.diagnostics = campaign_validate(&campaign_workspace.draft)
	campaign_workspace_history_initialize()
	campaign_workspace_record_project_path(campaign_manifest_path)}
campaign_workspace_request_close :: proc(
) {if campaign_workspace.dirty {campaign_workspace.exit_confirm = true}
	else {campaign_workspace.open = false; campaign_workspace.renaming_playthrough = false}}
campaign_workspace_discard_and_close :: proc() {campaign_workspace.exit_confirm = false
	campaign_workspace.open = false
	campaign_workspace.renaming_playthrough = false}
campaign_workspace_new_manifest :: proc(path: string) -> Validation {if path == "" do return {false, "campaign destination is required"}
	doc := Campaign_Definition {
		version         = "MysteryCampaign v2",
		id              = "new_campaign",
		title           = "New Campaign",
		creator         = "Creator",
		description     = "New authored campaign",
		content_version = "1.0.0",
	}
	append(&doc.conditions, Campaign_Condition{kind = .Always})
	append(
		&doc.cases,
		Campaign_Case {
			id = "case_1",
			title = "Case 1",
			story_path = "cases/case_1/story.toml",
			level_path = "cases/case_1/level.toml",
			case_content_version = "1.0.0",
			condition_root = 0,
			required = true,
			unavailable_presentation = .Requirements,
			replay_mode = .Disabled,
			invalid_result_policy = .Preserve,
		},
	)
	saved := save_campaign_manifest(path, &doc)
	if !saved.ok do return saved
	campaign_manifest_path = strings.clone(path)
	campaign_document = campaign_clone(&doc)
	campaign_workspace.draft = doc
	campaign_workspace.selected_case = 0
	campaign_workspace.selected_condition = 0
	campaign_workspace.dirty = false
	campaign_workspace_history_initialize()
	campaign_workspace_record_project_path(path)
	return{true, "NEW CAMPAIGN CREATED"}}
campaign_workspace_open_manifest :: proc(path: string) -> Validation {loaded: Campaign_Definition
	result := load_campaign_manifest(path, &loaded)
	if !result.ok do return result
	campaign_manifest_path = strings.clone(path)
	campaign_document = campaign_clone(&loaded)
	campaign_workspace.draft = loaded
	campaign_workspace.selected_case = 0
	campaign_workspace.selected_condition = loaded.cases[0].condition_root
	campaign_workspace.dirty = false
	campaign_workspace_history_initialize()
	campaign_workspace_record_project_path(path)
	return {true, "CAMPAIGN OPENED FOR EDITING"}}
campaign_workspace_save_as :: proc(
	path: string,
	duplicate: bool = false,
) -> Validation {if path == "" do return {false, "campaign destination is required"}; copy :=
		campaign_clone(&campaign_workspace.draft)
	if duplicate {base := copy.id; copy.id = fmt.tprintf("%s_copy", base); suffix := 2
		for copy.id == campaign_document.id {copy.id = fmt.tprintf("%s_copy_%d", base, suffix)
			suffix += 1}}
	saved := save_campaign_manifest(path, &copy)
	if !saved.ok do return saved
	campaign_manifest_path = strings.clone(path)
	campaign_workspace.draft = copy
	campaign_document = campaign_clone(&copy)
	campaign_workspace_history_initialize()
	campaign_workspace_record_project_path(path)
	return{true, duplicate ? "CAMPAIGN DUPLICATED" : "CAMPAIGN SAVED AS"}}
campaign_workspace_move_manifest :: proc(path: string) -> Validation {
	old := campaign_manifest_path
	if old == "" || path == "" do return {false, "campaign source and destination are required"}
	if !os.is_file(old) do return {false, "campaign manifest is missing"}
	if old == path do return {true, "CAMPAIGN ALREADY AT DESTINATION"}
	if os.exists(path) do return {false, "campaign destination already exists"}
	parent := os.dir(
		path,
	); if !os.exists(parent) && os.make_directory_all(parent) != nil do return {false, "campaign destination directory could not be created"}
	if os.rename(old, path) != nil do return {false, "campaign manifest could not be moved"}
	campaign_manifest_path = strings.clone(path); campaign_workspace_record_project_path(path)
	return {true, "CAMPAIGN MOVED"}
}
campaign_workspace_rename_manifest :: proc(filename: string) -> Validation {
	if filename == "" || strings.contains(filename, "/") || strings.contains(filename, "\\") || filename == "." || filename == ".." do return {false, "campaign filename is invalid"}
	if !strings.has_suffix(filename, ".toml") do return {false, "campaign filename must end in .toml"}
	if campaign_manifest_path == "" do return {false, "campaign manifest is missing"}
	return campaign_workspace_move_manifest(
		fmt.tprintf("%s/%s", os.dir(campaign_manifest_path), filename),
	)
}
campaign_workspace_delete_manifest :: proc() -> Validation {
	path :=
		campaign_manifest_path; if path == "" || !os.is_file(path) do return {false, "campaign manifest is missing"}
	trash_dir := fmt.tprintf(
		"%s/.trash",
		os.dir(path),
	); if os.make_directory_all(trash_dir) != nil do return {false, "campaign trash directory could not be created"}
	stem := fmt.tprintf(
		"%s-%s",
		campaign_workspace.draft.id,
		campaign_workspace.draft.content_version,
	); trash := fmt.tprintf("%s/%s.toml", trash_dir, stem)
	for suffix := 2; os.exists(trash); suffix += 1 do trash = fmt.tprintf("%s/%s-%d.toml", trash_dir, stem, suffix)
	if os.rename(path, trash) != nil do return {false, "campaign could not be moved to recoverable trash"}
	campaign_manifest_path = ""; campaign_workspace.open = false; campaign_workspace.dirty = false
	return {true, "CAMPAIGN MOVED TO RECOVERABLE TRASH"}
}
campaign_workspace_begin_text :: proc(
	field: Campaign_Workspace_Text_Field,
	value: string,
) {campaign_workspace.text_field = field; campaign_workspace.text_count = min(
		len(value),
		len(campaign_workspace.text_buffer),
	)
	copy(campaign_workspace.text_buffer[:campaign_workspace.text_count], transmute([]u8)value)}
campaign_workspace_commit_text :: proc() -> bool {doc := &campaign_workspace.draft; field :=
		campaign_workspace.text_field
	if field == .None do return false
	value := string(campaign_workspace.text_buffer[:campaign_workspace.text_count])
	if value == "" {campaign_workspace.feedback = "VALUE CANNOT BE EMPTY"; return false}
	case_index := campaign_workspace.selected_case
	variable_index := campaign_workspace.selected_variable
	switch
	field {case .Campaign_Format:
		doc.version = value; case .Campaign_ID:
		doc.id = value; case .Campaign_Title:
		doc.title = value; case .Campaign_Creator:
		doc.creator = value; case .Campaign_Description:
		doc.description = value; case .Campaign_Version:
		doc.content_version = value; case .Campaign_Thumbnail:
		doc.thumbnail = value; case .Case_ID:
		old := doc.cases[case_index].id; doc.cases[case_index].id = value
		for &node in doc.conditions do if node.case_id == old do node.case_id = value; case .Case_Title:
		doc.cases[case_index].title = value; case .Case_Content_Version:
		doc.cases[case_index].case_content_version = value; case .Story_Path:
		doc.cases[case_index].story_path = value; case .Level_Path:
		doc.cases[case_index].level_path = value; case .Locked_Message:
		doc.cases[case_index].locked_message = value; case .Variable_ID:
		old := doc.variables[variable_index].id; doc.variables[variable_index].id = value
		for &node in doc.conditions do if node.variable_id == old do node.variable_id = value
		for &effect in doc.effects do if effect.variable_id == old do effect.variable_id = value; case .Variable_Name:
		doc.variables[variable_index].display_name = value; case .Variable_Description:
		doc.variables[variable_index].description = value; case .Enum_Value:
		v := &doc.variables[variable_index]
		old := v.enum_values[campaign_workspace.selected_enum_value]
		v.enum_values[campaign_workspace.selected_enum_value] = value
		if v.default_enum == old do v.default_enum = value
		for &node in doc.conditions do if node.variable_id == v.id && node.enum_value == old do node.enum_value = value
		for &effect in doc.effects do if effect.variable_id == v.id && effect.enum_value == old do effect.enum_value = value; case .None:}
	campaign_workspace.text_field = .None
	campaign_workspace_mark_changed("TEXT UPDATED")
	return true}
campaign_workspace_mark_changed :: proc(message: string) {campaign_workspace_history_record()
	campaign_workspace.dirty = true
	campaign_workspace.feedback = message
	campaign_workspace.diagnostics = campaign_validate(&campaign_workspace.draft)
	campaign_workspace.simulated = campaign_playthrough
	_ = campaign_recalculate(&campaign_workspace.draft, &campaign_workspace.simulated)
	revision :=
		authoring_production_revisions(nil, nil, nil, &campaign_workspace.draft, nil)[int(Authoring_Validation_Domain.Campaign)] +
		1
	_ = authoring_invalidate_after_edit(.Campaign, revision)}

// Apply a complete logical authoring operation atomically. This is the shared
// production boundary for UI, automation, and program acceptance: rejected
// batches leave the draft and history untouched; committed batches are one
// undo step and acquire normal dirty/invalidation semantics.
campaign_workspace_apply_actions :: proc(actions: []Campaign_Workspace_Action) -> Validation {
	if len(actions) == 0 do return {false, "campaign action batch is empty"}
	if !campaign_workspace.history.ready do campaign_workspace_history_initialize()
	working := campaign_clone(&campaign_workspace.draft)
	defer campaign_destroy(&working)
	for action in actions {
		switch action.kind {
		case .Set_Metadata:
			working.version = action.metadata.version; working.id = action.metadata.id
			working.title = action.metadata.title
			working.creator = action.metadata.creator
			working.description = action.metadata.description
			working.content_version = action.metadata.content_version
			working.thumbnail = action.metadata.thumbnail
		case .Add_Variable:
			if len(working.variables) >= CAMPAIGN_MAX_VARIABLES do return {false, "campaign variable limit reached"}
			for item in working.variables do if item.id == action.variable.id do return {false, "campaign variable id already exists"}
			append(&working.variables, action.variable)
		case .Add_Condition:
			if len(working.conditions) >= CAMPAIGN_MAX_CONDITIONS do return {false, "campaign condition limit reached"}
			append(&working.conditions, action.condition)
		case .Add_Effect:
			if len(working.effects) >= CAMPAIGN_MAX_EFFECTS do return {false, "campaign effect limit reached"}
			append(&working.effects, action.effect)
		case .Add_Case:
			if len(working.cases) >= CAMPAIGN_MAX_CASES do return {false, "campaign case limit reached"}
			for item in working.cases do if item.id == action.case_value.id do return {false, "campaign case id already exists"}
			append(&working.cases, action.case_value)
		}
	}
	valid := campaign_validate(&working); if !valid.ok do return valid
	campaign_destroy(
		&campaign_workspace.draft,
	); campaign_workspace.draft = campaign_clone(&working)
	campaign_workspace.selected_case = clamp(
		campaign_workspace.selected_case,
		0,
		max(0, len(campaign_workspace.draft.cases) - 1),
	)
	if len(campaign_workspace.draft.cases) > 0 do campaign_workspace.selected_condition = campaign_workspace.draft.cases[campaign_workspace.selected_case].condition_root
	campaign_workspace_mark_changed("CAMPAIGN ACTION TRANSACTION COMMITTED")
	return {true, "CAMPAIGN ACTION TRANSACTION COMMITTED"}
}
campaign_workspace_add_variable :: proc() -> bool {doc := &campaign_workspace.draft; if len(doc.variables) >= CAMPAIGN_MAX_VARIABLES do return false
	index := len(doc.variables) + 1
	append(
		&doc.variables,
		Campaign_Variable {
			id = fmt.tprintf("flag_%d", index),
			display_name = fmt.tprintf("Flag %d", index),
			kind = .Boolean,
		},
	)
	campaign_workspace.selected_variable = len(doc.variables) - 1
	campaign_workspace_mark_changed("VARIABLE ADDED")
	return true}
campaign_workspace_add_case :: proc() -> bool {doc := &campaign_workspace.draft; if len(doc.cases) >= CAMPAIGN_MAX_CASES do return false
	index := len(doc.cases) + 1
	condition := len(doc.conditions)
	append(&doc.conditions, Campaign_Condition{kind = .Always})
	template := Campaign_Case {
		id                       = fmt.tprintf("case_%d", index),
		title                    = fmt.tprintf("Case %d", index),
		case_content_version     = "1.0.0",
		condition_root           = condition,
		required                 = true,
		replay_mode              = .Disabled,
		invalid_result_policy    = .Preserve,
		unavailable_presentation = .Requirements,
	}
	if len(doc.cases) > 0 {source := doc.cases[campaign_workspace.selected_case]
		template.story_path = source.story_path
		template.level_path = source.level_path}
	append(&doc.cases, template)
	campaign_workspace.selected_case = len(doc.cases) - 1
	campaign_workspace.selected_condition = condition
	campaign_workspace_mark_changed("CASE ADDED — UPDATE ITS PACKAGE PATHS")
	return true}
campaign_workspace_ensure_source_project :: proc() -> Validation {
	if active_authoring_ready do return {true, "AUTHORING PROJECT READY"}
	if campaign_manifest_path == "" do return {false, "save the campaign before creating its source project"}
	root := os.dir(
		campaign_manifest_path,
	); project, valid := authoring_project_new(campaign_workspace.draft.id, campaign_workspace.draft.title, root); if !valid do return {false, "campaign identity cannot create a source project"}
	project.campaign_path = os.base(
		campaign_manifest_path,
	); project.export_directory = "exports"; active_authoring_project = project; active_authoring_ready = true; active_authoring_read_only = false
	if saved := authoring_project_save_manifest(&active_authoring_project);
	   !saved.ok {active_authoring_ready = false; return {false, saved.message}}
	return {true, "SOURCE PROJECT CREATED"}
}
campaign_workspace_create_case_source :: proc(
	mystery: bool,
) -> Validation {doc := &campaign_workspace.draft; i := campaign_workspace.selected_case; if i < 0 || i >= len(doc.cases) do return {false, "a campaign case must be selected"}
	if ready := campaign_workspace_ensure_source_project(); !ready.ok do return ready
	item := &doc.cases[i]
	created := authoring_app_new_case(item.id, item.title, mystery)
	if !created.ok do return {false, created.message}
	source_index := authoring_project_case_index(&active_authoring_project, item.id)
	if source_index < 0 do return {false, "created case source could not be selected"}
	active_authoring_project.active_case = source_index
	opened := authoring_workspace_activate_case(source_index)
	if !opened.ok do return {false, opened.message}
	source := &active_authoring_project.cases[source_index]
	item.story_path = source.paths.story
	item.level_path = source.paths.level
	item.case_content_version = "1.0.0"
	campaign_workspace_mark_changed("CASE SOURCE CREATED AND OPENED")
	return{true, "CASE SOURCE PROJECT CREATED AND OPENED"}}
campaign_workspace_case_source_index :: proc(
	project: ^Authoring_Project,
	item: Campaign_Case,
) -> int {
	if project == nil do return -1
	for source, index in project.cases[:project.case_count] do if source.id == item.id || source.paths.story == item.story_path || source.paths.level == item.level_path do return index
	return -1
}
campaign_workspace_open_case_source :: proc() -> Validation {
	doc := &campaign_workspace.draft; i := campaign_workspace.selected_case
	if i < 0 || i >= len(doc.cases) do return {false, "a campaign case must be selected"}
	if !active_authoring_ready do return {false, "open the source authoring project first"}
	guard := authoring_app_dirty_guard(); if !guard.ok do return {false, guard.message}
	item :=
		doc.cases[i]; matched := campaign_workspace_case_source_index(&active_authoring_project, item)
	if matched < 0 do return {false, "selected case is not part of the open authoring project"}
	opened := authoring_workspace_activate_case(
		matched,
	); if !opened.ok do return {false, opened.message}
	return {true, "CASE SOURCE OPENED FOR EDITING"}
}

campaign_workspace_simulation_start :: proc(index: int) -> Validation {
	doc := &campaign_workspace.draft; if index < 0 || index >= len(doc.cases) do return {false, "simulation case index is invalid"}
	result := &campaign_workspace.simulated.results[index]; result.started = true; result.case_id = doc.cases[index].id; result.case_content_version = doc.cases[index].case_content_version
	campaign_workspace.selected_case =
		index; campaign_workspace.simulation_trace = fmt.tprintf("START TRACE · %s MARKED STARTED; NO EFFECTS APPLIED", doc.cases[index].id); return {true, "SIMULATED CASE STARTED WITHOUT A RESULT"}
}

campaign_workspace_simulation_trace :: proc(
	doc: ^Campaign_Definition,
	before, after: ^Campaign_Playthrough,
) -> string {
	trace := "EFFECT TRACE"
	for variable, i in doc.variables {old, new := before.values[i], after.values[i]; changed := variable.kind == .Boolean ? old.boolean_value != new.boolean_value : variable.kind == .Integer ? old.integer_value != new.integer_value : old.enum_value != new.enum_value; if changed {value := variable.kind == .Boolean ? fmt.tprintf("%t", new.boolean_value) : variable.kind == .Integer ? fmt.tprintf("%d", new.integer_value) : new.enum_value; trace = fmt.tprintf("%s · %s → %s", trace, variable.id, value)}}
	for item, i in doc.cases {old, new := before.results[i], after.results[i]; if !old.started && new.started do trace = fmt.tprintf("%s · STARTED %s", trace, item.id); if !old.present && new.present do trace = fmt.tprintf("%s · COMPLETED %s AS %v", trace, item.id, new.outcome); if old.present && new.present && old.outcome != new.outcome do trace = fmt.tprintf("%s · REPLAYED %s %v → %v", trace, item.id, old.outcome, new.outcome); if old.started && !new.started do trace = fmt.tprintf("%s · CLEARED START %s", trace, item.id); if old.present && !new.present do trace = fmt.tprintf("%s · CLEARED RESULT %s", trace, item.id)}
	if trace == "EFFECT TRACE" do trace = "EFFECT TRACE · NO STATE MUTATIONS"
	return trace
}
campaign_workspace_simulation_change_variable :: proc(
	index, direction: int,
) -> Validation {doc := &campaign_workspace.draft; if index < 0 || index >= len(doc.variables) do return {false, "simulation variable index is invalid"}
	before := campaign_workspace.simulated
	v := doc.variables[index]
	state := &campaign_workspace.simulated.values[index]
	switch
	v.kind {case .Boolean:
		state.boolean_value = !state.boolean_value; case .Integer:
		state.integer_value += direction; case .Enumeration:
		if v.enum_value_count <= 0 do return {false, "simulation enum has no values"}; current := 0
		for value, i in v.enum_values[:v.enum_value_count] do if value == state.enum_value do current = i
		current = (current + max(direction, 1)) % v.enum_value_count
		state.enum_value = v.enum_values[current]}
	campaign_workspace.simulation_trace = campaign_workspace_simulation_trace(
		doc,
		&before,
		&campaign_workspace.simulated,
	)
	return{true, "DIRECT CREATOR VARIABLE MUTATION APPLIED"}}

campaign_workspace_simulation_complete :: proc(index: int) -> Validation {
	doc := &campaign_workspace.draft; if index < 0 || index >= len(doc.cases) do return {false, "simulation case index is invalid"}
	p := &campaign_workspace.simulated; before := p^; item := doc.cases[index]; existing := p.results[index]; outcome := existing.present ? Outcome((int(existing.outcome) + 1) % len(Outcome)) : Outcome.Airtight
	applied := campaign_apply_result(
		doc,
		p,
		Campaign_Case_Result {
			case_id = item.id,
			case_content_version = item.case_content_version,
			outcome = outcome,
		},
	); campaign_workspace.selected_case = index
	if !applied.ok do return applied
	campaign_workspace.simulation_trace = campaign_workspace_simulation_trace(doc, &before, p)
	return {
		true,
		fmt.tprintf("SIMULATED RESULT APPLIED · %v · DEPENDENCIES RECALCULATED", outcome),
	}
}

campaign_workspace_simulation_clear :: proc(index: int) -> Validation {
	doc := &campaign_workspace.draft; if index < 0 || index >= len(doc.cases) do return {false, "simulation case index is invalid"}
	p := &campaign_workspace.simulated; before := p^; if p.results[index].present do p.completion_count = max(0, p.completion_count - 1); p.results[index] = {}; recalculated := campaign_recalculate(doc, p); if !recalculated.ok do return {false, recalculated.message}; campaign_workspace.selected_case = index; campaign_workspace.simulation_trace = campaign_workspace_simulation_trace(doc, &before, p)
	return {
		true,
		fmt.tprintf(
			"SIMULATED CASE CLEARED · %d DEPENDENT RESULTS INVALIDATED",
			recalculated.cleared_count,
		),
	}
}
campaign_workspace_move_case :: proc(direction: int) -> bool {doc := &campaign_workspace.draft
	i := campaign_workspace.selected_case
	j := i + direction
	if i < 0 || j < 0 || i >= len(doc.cases) || j >= len(doc.cases) do return false
	doc.cases[i], doc.cases[j] = doc.cases[j], doc.cases[i]
	campaign_workspace.selected_case = j
	campaign_workspace_mark_changed("CASE ORDER UPDATED")
	return true}
campaign_workspace_remove_case :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_case
	if len(doc.cases) <= 1 || i < 0 || i >= len(doc.cases) do return false
	removed := doc.cases[i].id
	for node in doc.conditions do if (node.kind == .Case_Started || node.kind == .Case_Completed || node.kind == .Case_Outcome) && node.case_id == removed {campaign_workspace.feedback = "CASE IS STILL REFERENCED BY A CONDITION"; return false}
	ordered_remove(&doc.cases, i)
	campaign_workspace.selected_case = clamp(i, 0, len(doc.cases) - 1)
	campaign_workspace.selected_condition =
		doc.cases[campaign_workspace.selected_case].condition_root
	campaign_workspace_mark_changed("CASE REMOVED")
	return true}
campaign_workspace_add_enum_value :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_variable
	if i < 0 || i >= len(doc.variables) do return false
	v := &doc.variables[i]
	if v.kind != .Enumeration || v.enum_value_count >= len(v.enum_values) do return false
	value := fmt.tprintf("value_%d", v.enum_value_count + 1)
	v.enum_values[v.enum_value_count] = value
	v.enum_value_count += 1
	campaign_workspace.selected_enum_value = v.enum_value_count - 1
	if v.default_enum == "" do v.default_enum = value
	campaign_workspace_mark_changed("ENUM VALUE ADDED")
	return true}
campaign_workspace_remove_enum_value :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_variable
	if i < 0 || i >= len(doc.variables) do return false
	v := &doc.variables[i]
	j := campaign_workspace.selected_enum_value
	if v.kind != .Enumeration || v.enum_value_count <= 1 || j < 0 || j >= v.enum_value_count do return false
	removed := v.enum_values[j]
	for k in j + 1 ..< v.enum_value_count do v.enum_values[k - 1] = v.enum_values[k]
	v.enum_value_count -= 1
	v.enum_values[v.enum_value_count] = ""
	fallback := v.enum_values[0]
	if v.default_enum == removed do v.default_enum = fallback
	for &node in doc.conditions do if node.variable_id == v.id && node.enum_value == removed do node.enum_value = fallback
	for &effect in doc.effects do if effect.variable_id == v.id && effect.enum_value == removed do effect.enum_value = fallback
	campaign_workspace.selected_enum_value = clamp(j, 0, v.enum_value_count - 1)
	campaign_workspace_mark_changed("ENUM VALUE REMOVED AND REFERENCES REPAIRED")
	return true}
campaign_first_variable_of_kind :: proc(
	c: ^Campaign_Definition,
	kind: Campaign_Value_Kind,
) -> int {for variable, i in c.variables do if variable.kind == kind do return i; return -1}
campaign_next_variable_of_kind :: proc(
	c: ^Campaign_Definition,
	current: string,
	kind: Campaign_Value_Kind,
) -> int {start := campaign_variable_index(c, current); for 	offset in 1 ..= len(c.variables) {i := (max(start, 0) + offset) % len(c.variables); if c.variables[i].kind == kind do return i}
	return campaign_first_variable_of_kind(c, kind)}
campaign_workspace_add_condition :: proc(
	kind: Campaign_Condition_Kind,
) -> bool {doc := &campaign_workspace.draft; case_index := campaign_workspace.selected_case
	if case_index < 0 || case_index >= len(doc.cases) || len(doc.conditions) + 2 > CAMPAIGN_MAX_CONDITIONS do return false
	target := campaign_workspace.selected_condition
	if target < 0 || target >= len(doc.conditions) {target = doc.cases[case_index].condition_root}
	if target <
	   0 {target = len(doc.conditions); append(&doc.conditions, Campaign_Condition{kind = .Always})
		doc.cases[case_index].condition_root = target}
	old := doc.conditions[target]
	if kind == .All ||
	   kind ==
		   .Any {first := len(doc.conditions); append(&doc.conditions, old, Campaign_Condition{kind = .Always})
		doc.conditions[target] = {
			kind        = kind,
			first_child = first,
			child_count = 2,
		}} else if kind == .Not {first := len(doc.conditions); append(&doc.conditions, old)
		doc.conditions[target] = {
			kind        = .Not,
			first_child = first,
			child_count = 1,
		}} else {node := Campaign_Condition {
			kind = kind,
		}; value_kind :=
			Campaign_Value_Kind.Boolean; if kind == .Integer_Compare do value_kind = .Integer
		else if kind == .Enum_Equals do value_kind = .Enumeration; if kind == .Boolean_Equals || kind == .Integer_Compare || kind == .Enum_Equals {variable_index := campaign_first_variable_of_kind(doc, value_kind); if variable_index < 0 {campaign_workspace.feedback = "ADD A COMPATIBLE VARIABLE FIRST"; return false}; node.variable_id = doc.variables[variable_index].id; node.enum_value = doc.variables[variable_index].default_enum}; if len(doc.cases) > 0 do node.case_id = doc.cases[0].id; doc.conditions[target] = node}
	campaign_workspace.selected_condition = target
	campaign_workspace_mark_changed("CONDITION TREE UPDATED")
	return true}
campaign_workspace_insert_condition_child :: proc() -> bool {
	doc := &campaign_workspace.draft; parent := campaign_workspace.selected_condition; if parent < 0 || parent >= len(doc.conditions) || len(doc.conditions) >= CAMPAIGN_MAX_CONDITIONS do return false
	p := &doc.conditions[parent]; if p.kind != .All && p.kind != .Any do return false
	insert_at := p.first_child + p.child_count; append(&doc.conditions, Campaign_Condition{})
	for i := len(doc.conditions) - 1; i > insert_at; i -= 1 do doc.conditions[i] = doc.conditions[i - 1]
	doc.conditions[insert_at] = {
		kind = .Always,
	}
	for &node, index in doc.conditions {if index == parent do continue; if (node.kind == .All || node.kind == .Any || node.kind == .Not) && node.first_child >= insert_at do node.first_child += 1}
	for &item in doc.cases do if item.condition_root >= insert_at do item.condition_root += 1
	doc.conditions[parent].child_count += 1; campaign_workspace.selected_condition = insert_at; campaign_workspace_mark_changed("CONDITION CHILD INSERTED"); return true
}
campaign_workspace_condition_parent :: proc(c: ^Campaign_Definition, index: int) -> int {for node, i in c.conditions do if (node.kind == .All || node.kind == .Any || node.kind == .Not) && index >= node.first_child && index < node.first_child + node.child_count do return i
	return -1}
campaign_condition_collect :: proc(
	c: ^Campaign_Definition,
	index: int,
	out: ^[CAMPAIGN_MAX_CONDITIONS]int,
	count: ^int,
	depth: int,
) {if index < 0 || index >= len(c.conditions) || count^ >= len(out^) || depth > CAMPAIGN_MAX_CONDITIONS do return
	for i in 0 ..< count^ do if out[i] == index do return
	out[count^] = index
	count^ += 1
	node := c.conditions[index]
	if node.kind == .All || node.kind == .Any || node.kind == .Not {for child in node.first_child ..< node.first_child + node.child_count do campaign_condition_collect(c, child, out, count, depth + 1)}}
campaign_workspace_condition_nodes :: proc(
	c: ^Campaign_Definition,
	case_index: int,
) -> (
	[CAMPAIGN_MAX_CONDITIONS]int,
	int,
) {nodes: [CAMPAIGN_MAX_CONDITIONS]int; count := 0; if case_index >= 0 && case_index < len(c.cases) do campaign_condition_collect(c, c.cases[case_index].condition_root, &nodes, &count, 0)
	return nodes, count}
campaign_condition_path_resolve :: proc(
	c: ^Campaign_Definition,
	case_id: string,
	path: Campaign_Condition_Path,
) -> (
	int,
	bool,
) {if c == nil || path.depth < 0 || path.depth > len(path.children) do return -1, false
	case_index := -1
	for item, i in c.cases do if item.id == case_id {case_index = i; break}
	if case_index < 0 do return -1, false
	index := c.cases[case_index].condition_root
	if index < 0 || index >= len(c.conditions) do return -1, false
	for depth in 0 ..< path.depth {node := c.conditions[index]; if node.kind != .All && node.kind != .Any && node.kind != .Not do return -1, false
		ordinal := path.children[depth]
		if ordinal < 0 || ordinal >= node.child_count do return -1, false
		index = node.first_child + ordinal
		if index < 0 || index >= len(c.conditions) do return -1, false}
	return index, true}
campaign_workspace_select_condition_path :: proc(
	case_id: string,
	path: Campaign_Condition_Path,
) -> bool {index, ok := campaign_condition_path_resolve(&campaign_workspace.draft, case_id, path)
	if !ok do return false
	for item, i in campaign_workspace.draft.cases do if item.id == case_id {campaign_workspace.selected_case = i; break}
	campaign_workspace.selected_condition = index
	return true}
campaign_workspace_set_condition_at_path :: proc(
	case_id: string,
	path: Campaign_Condition_Path,
	kind: Campaign_Condition_Kind,
) -> bool {if !campaign_workspace_select_condition_path(case_id, path) do return false
	return campaign_workspace_add_condition(kind)}
campaign_workspace_insert_condition_child_at_path :: proc(
	case_id: string,
	parent: Campaign_Condition_Path,
) -> bool {if !campaign_workspace_select_condition_path(case_id, parent) do return false
	return campaign_workspace_insert_condition_child()}
campaign_workspace_remove_condition_at_path :: proc(
	case_id: string,
	path: Campaign_Condition_Path,
) -> bool {if !campaign_workspace_select_condition_path(case_id, path) do return false
	return campaign_workspace_remove_condition()}
campaign_workspace_move_condition_at_path :: proc(
	case_id: string,
	path: Campaign_Condition_Path,
	direction: int,
) -> bool {if !campaign_workspace_select_condition_path(case_id, path) do return false
	return campaign_workspace_move_condition(direction)}
campaign_workspace_select_condition :: proc(
	direction: int,
) -> bool {doc := &campaign_workspace.draft; nodes, count := campaign_workspace_condition_nodes(
		doc,
		campaign_workspace.selected_case,
	)
	if count == 0 do return false
	position := 0
	for node, i in nodes[:count] do if node == campaign_workspace.selected_condition do position = i
	position = clamp(position + direction, 0, count - 1)
	campaign_workspace.selected_condition = nodes[position]
	return true}
campaign_workspace_reset_condition :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_condition
	nodes, count := campaign_workspace_condition_nodes(doc, campaign_workspace.selected_case)
	reachable := false
	for node in nodes[:count] do if node == i do reachable = true
	if !reachable do return false
	doc.conditions[i] = {
		kind = .Always,
	}
	compacted := campaign_condition_compact(doc)
	if !compacted.ok {campaign_workspace.feedback = compacted.message; return false}
	campaign_workspace.selected_condition =
		doc.cases[campaign_workspace.selected_case].condition_root
	campaign_workspace_mark_changed("CONDITION NODE RESET AND UNREACHABLE DESCENDANTS REMOVED")
	return true}
campaign_workspace_move_condition :: proc(
	direction: int,
) -> bool {doc := &campaign_workspace.draft; i := campaign_workspace.selected_condition; parent :=
		campaign_workspace_condition_parent(doc, i)
	if parent < 0 do return false
	p := doc.conditions[parent]
	j := i + direction
	if j < p.first_child || j >= p.first_child + p.child_count do return false
	doc.conditions[i], doc.conditions[j] = doc.conditions[j], doc.conditions[i]
	campaign_workspace.selected_condition = j
	campaign_workspace_mark_changed("CONDITION NODE MOVED")
	return true}
campaign_workspace_remove_condition :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_condition
	if i < 0 || i >= len(doc.conditions) do return false
	parent := campaign_workspace_condition_parent(doc, i)
	if parent < 0 {doc.conditions[i] = {
				kind = .Always,
			}; campaign_workspace_mark_changed("ROOT CONDITION RESET"); return true}
	removed := campaign_condition_remove_subtree(doc, i)
	if !removed.ok {campaign_workspace.feedback = removed.message; return false}
	campaign_workspace.selected_condition = clamp(parent, 0, len(doc.conditions) - 1)
	campaign_workspace_mark_changed("CONDITION SUBTREE REMOVED")
	return true}
campaign_workspace_add_effect :: proc() -> bool {doc := &campaign_workspace.draft; case_index :=
		campaign_workspace.selected_case
	if case_index < 0 || case_index >= len(doc.cases) || len(doc.effects) >= CAMPAIGN_MAX_EFFECTS || len(doc.variables) == 0 do return false
	item := &doc.cases[case_index]
	outcome := Outcome(clamp(campaign_workspace.selected_outcome, 0, len(Outcome) - 1))
	mapping := -1
	for i in 0 ..< item.outcome_effect_count do if item.outcome_effects[i].outcome == outcome do mapping = i
	if mapping < 0 && item.outcome_effect_count >= len(item.outcome_effects) do return false
	insert_at := len(doc.effects)
	if mapping >= 0 do insert_at = item.outcome_effects[mapping].first_effect + item.outcome_effects[mapping].effect_count
	variable := doc.variables[0]
	kind: Campaign_Effect_Kind = .Set_Boolean
	if variable.kind == .Integer do kind = .Set_Integer
	else if variable.kind == .Enumeration do kind = .Set_Enum
	append(&doc.effects, Campaign_Effect{})
	for i := len(doc.effects) - 1; i > insert_at; i -= 1 do doc.effects[i] = doc.effects[i - 1]
	doc.effects[insert_at] = {
			kind        = kind,
			variable_id = variable.id,
			enum_value  = variable.default_enum,
		}
	for 	&other_case in doc.cases {for 		other_index in 0 ..< other_case.outcome_effect_count {other := &other_case.outcome_effects[other_index]
			if &other_case == item && other_index == mapping do continue
			if other.first_effect >= insert_at do other.first_effect += 1}}
	if mapping < 0 {mapping = item.outcome_effect_count; item.outcome_effect_count += 1
		item.outcome_effects[mapping] = {
				outcome      = outcome,
				first_effect = insert_at,
				effect_count = 1,
			}}
	else do item.outcome_effects[mapping].effect_count += 1
	campaign_workspace.selected_effect = insert_at
	campaign_workspace_mark_changed("OUTCOME EFFECT ADDED")
	return true}
campaign_workspace_remove_effect :: proc() -> bool {i := campaign_workspace.selected_effect
	if !campaign_effect_remove(&campaign_workspace.draft, i) do return false
	campaign_workspace.selected_effect = clamp(
		i,
		0,
		max(0, len(campaign_workspace.draft.effects) - 1),
	)
	campaign_workspace_mark_changed("OUTCOME EFFECT REMOVED")
	return true}
campaign_workspace_move_effect :: proc(direction: int) -> bool {from :=
		campaign_workspace.selected_effect
	to := from + direction
	moved := campaign_effect_reorder(&campaign_workspace.draft, from, to)
	if !moved.ok {campaign_workspace.feedback = moved.message; return false}
	campaign_workspace.selected_effect = to
	campaign_workspace_mark_changed("OUTCOME EFFECT MOVED")
	return true}
campaign_workspace_effect_mapping_index :: proc() -> int {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_case
	if i < 0 || i >= len(doc.cases) do return -1
	outcome := Outcome(clamp(campaign_workspace.selected_outcome, 0, len(Outcome) - 1))
	for mapping, index in doc.cases[i].outcome_effects[:doc.cases[i].outcome_effect_count] do if mapping.outcome == outcome do return index
	return -1}
campaign_workspace_move_effect_mapping :: proc(
	direction: int,
) -> bool {doc := &campaign_workspace.draft; i := campaign_workspace.selected_case; mapping :=
		campaign_workspace_effect_mapping_index()
	if i < 0 || mapping < 0 do return false
	target := mapping + direction
	item := &doc.cases[i]
	if target < 0 || target >= item.outcome_effect_count do return false
	item.outcome_effects[mapping], item.outcome_effects[target] =
		item.outcome_effects[target], item.outcome_effects[mapping]
	campaign_workspace_mark_changed("OUTCOME MAPPING MOVED")
	return true}
campaign_workspace_remove_effect_mapping :: proc() -> bool {doc := &campaign_workspace.draft; i :=
		campaign_workspace.selected_case
	mapping := campaign_workspace_effect_mapping_index()
	if i < 0 || mapping < 0 do return false
	item := &doc.cases[i]
	entry := item.outcome_effects[mapping]
	for offset := entry.effect_count - 1; offset >= 0; offset -= 1 do if !campaign_effect_remove(doc, entry.first_effect + offset) do return false
	for j in mapping + 1 ..< item.outcome_effect_count do item.outcome_effects[j - 1] = item.outcome_effects[j]
	item.outcome_effect_count -= 1
	item.outcome_effects[item.outcome_effect_count] = {}
	campaign_workspace.selected_effect = -1
	campaign_workspace_mark_changed("OUTCOME MAPPING REMOVED")
	return true}
campaign_workspace_navigate_validation :: proc() -> bool {message := strings.to_lower(
		campaign_workspace.diagnostics.message,
	)
	if strings.contains(message, "variable") {campaign_workspace.tab = .Variables
		campaign_workspace.selected_variable = clamp(
			campaign_workspace.selected_variable,
			0,
			max(0, len(campaign_workspace.draft.variables) - 1),
		)}
	else if strings.contains(message, "effect") {campaign_workspace.tab = .Effects}
	else if strings.contains(message, "condition") ||
	   strings.contains(message, "initially available") {campaign_workspace.tab = .Conditions
		if len(campaign_workspace.draft.cases) > 0 do campaign_workspace.selected_condition = campaign_workspace.draft.cases[clamp(campaign_workspace.selected_case, 0, len(campaign_workspace.draft.cases) - 1)].condition_root}
	else if strings.contains(message, "case") {campaign_workspace.tab = .Cases}
	else {campaign_workspace.tab = .Overview}
	campaign_workspace.feedback = fmt.tprintf(
		"FOCUSED CAMPAIGN DIAGNOSTIC · %s",
		campaign_workspace.diagnostics.message,
	)
	return true}
campaign_workspace_navigate_dependency :: proc(
	case_index: int,
) -> bool {doc := &campaign_workspace.draft; if case_index < 0 || case_index >= len(doc.cases) do return false
	campaign_workspace.selected_case = case_index
	campaign_workspace.selected_condition = doc.cases[case_index].condition_root
	campaign_workspace.tab = .Conditions
	campaign_workspace.feedback = fmt.tprintf(
		"FOCUSED DEPENDENCY CONDITION · %s",
		doc.cases[case_index].id,
	)
	return true}

save_campaign_playthrough :: proc() -> bool {
	ok := campaign_save_playthrough(
		&campaign_playthrough,
	); if campaign_playthroughs.selected >= 0 && campaign_playthroughs.selected < campaign_playthroughs.count do campaign_playthroughs.items[campaign_playthroughs.selected] = campaign_playthrough; _ = campaign_save_library_index(); return ok
}

load_campaign_playthrough :: proc() -> bool {data, found := read_with_local_fallback(
		"",
		"campaign-default.progress",
	)
	if !found do return false
	text := string(data)
	loaded := Campaign_Playthrough {
		campaign_id              = campaign_document.id,
		campaign_content_version = campaign_document.content_version,
		id                       = "default",
		name                     = "Investigation",
		active_case              = -1,
		next_completion_sequence = 1,
	}
	campaign_reset_values(&campaign_document, &loaded)
	for 	line in strings.split_lines_iterator(&text) {if strings.has_prefix(line, "campaign_id=") && line[12:] != campaign_document.id do return false
		if strings.has_prefix(line, "campaign_version=") && line[17:] != campaign_document.content_version do return false
		if strings.has_prefix(line, "next_sequence=") {value, ok := strconv.parse_u64(line[14:])
			if ok do loaded.next_completion_sequence = value}
		if strings.has_prefix(line, "result=") {parts, _ := strings.split(
				line[7:],
				"|",
				context.temp_allocator,
			)
			if len(parts) != 4 do return false
			index := campaign_case_index(&campaign_document, parts[0])
			if index < 0 do return false
			outcome, valid := campaign_outcome_from_text(parts[2])
			sequence, sequence_ok := strconv.parse_u64(parts[3])
			if !valid || !sequence_ok do return false
			loaded.results[index] = {
				present              = true,
				started              = true,
				case_id              = parts[0],
				case_content_version = parts[1],
				outcome              = outcome,
				completion_sequence  = sequence,
			}
			loaded.completion_count += 1}}
	if loaded.next_completion_sequence == 0 do loaded.next_completion_sequence = 1
	campaign_playthrough = loaded
	recalculated := campaign_recalculate(&campaign_document, &campaign_playthrough)
	return recalculated.ok}
