package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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
