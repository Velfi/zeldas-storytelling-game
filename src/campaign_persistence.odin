package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

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
