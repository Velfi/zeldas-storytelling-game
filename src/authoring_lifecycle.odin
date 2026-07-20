package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"

AUTHORING_PROJECT_MANIFEST :: "authoring-project.toml"
AUTHORING_LIFECYCLE_VERSION :: "1"
AUTHORING_MAX_RECENTS :: 32

Authoring_Template_Kind :: enum {
	General_Story,
	Mystery,
}

Authoring_Lifecycle_Result :: struct {
	ok:      bool,
	message: string,
}

Authoring_Save_Document :: struct {
	kind:       Authoring_Document_Kind,
	revision:   u64,
	serialized: string,
}

Authoring_Recovery_Document :: struct {
	kind:                          Authoring_Document_Kind,
	base_revision, draft_revision: u64,
	serialized:                    string,
}

Authoring_Recovery_Bundle :: struct {
	project_id, case_id: string,
	documents:           [Authoring_Document_Kind]Authoring_Recovery_Document,
}

Authoring_Recent_Project :: struct {
	id, title, root_path: string,
	opened_sequence:      u64,
}
Authoring_Recent_Projects :: struct {
	items: [AUTHORING_MAX_RECENTS]Authoring_Recent_Project,
	count: int,
}

Authoring_Case_Operation_Kind :: enum {
	Duplicate,
	Rename,
	Move,
	Delete,
	Editable_Copy,
}
Authoring_Case_Operation :: struct {
	kind:                                                                               Authoring_Case_Operation_Kind,
	source_case,
	target_case:                                                           int,
	target_id,
	target_title,
	source_directory,
	target_directory,
	recoverable_directory: string,
	allowed:                                                                            bool,
	message:                                                                            string,
	inbound:                                                                            Authoring_Case_Inbound_Preview,
}

Authoring_Case_Inbound_Reference :: struct {
	owner_id, field_path, value: string,
}
Authoring_Case_Inbound_Preview :: struct {
	items:     [128]Authoring_Case_Inbound_Reference,
	count:     int,
	truncated: bool,
}

authoring_lifecycle_escape :: proc(value: string) -> string {
	result := ""
	for ch in value {if ch == '\\' do result = fmt.tprintf("%s\\\\", result)
		else if ch == '\"' do result = fmt.tprintf("%s\\\"", result)
		else if ch == '\n' do result = fmt.tprintf("%s\\n", result)
		else do result = fmt.tprintf("%s%c", result, ch)}
	return result
}

authoring_project_manifest_relative :: proc() -> string {return AUTHORING_PROJECT_MANIFEST}

authoring_project_serialize :: proc(project: ^Authoring_Project) -> string {
	text := fmt.tprintf(
		"version = \"%s\"\nid = \"%s\"\ntitle = \"%s\"\ncampaign = \"%s\"\nexport_directory = \"%s\"\nactive_case = %d\n",
		AUTHORING_LIFECYCLE_VERSION,
		authoring_lifecycle_escape(project.id),
		authoring_lifecycle_escape(project.title),
		authoring_lifecycle_escape(project.campaign_path),
		authoring_lifecycle_escape(project.export_directory),
		project.active_case,
	)
	for item in project.cases[:project.case_count] do text = fmt.tprintf("%s\n[[cases]]\nid = \"%s\"\ntitle = \"%s\"\ndirectory = \"%s\"\nstory = \"%s\"\nlevel = \"%s\"\ngraph_layout = \"%s\"\nstory_autosave = \"%s\"\nlevel_autosave = \"%s\"\ngraph_layout_autosave = \"%s\"\n", text, authoring_lifecycle_escape(item.id), authoring_lifecycle_escape(item.title), authoring_lifecycle_escape(item.directory), authoring_lifecycle_escape(item.paths.story), authoring_lifecycle_escape(item.paths.level), authoring_lifecycle_escape(item.paths.graph_layout), authoring_lifecycle_escape(item.paths.story_autosave), authoring_lifecycle_escape(item.paths.level_autosave), authoring_lifecycle_escape(item.paths.graph_layout_autosave))
	return text
}

authoring_atomic_write :: proc(path, contents: string) -> bool {
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, transmute([]u8)contents) != nil do return false
	if os.rename(temporary, path) != nil {_ = os.remove(temporary); return false}
	return true
}

authoring_project_save_manifest :: proc(
	project: ^Authoring_Project,
) -> Authoring_Lifecycle_Result {
	if project == nil do return {false, "project is missing"}
	path, ok := authoring_resolve_path(
		project,
		authoring_project_manifest_relative(),
	); if !ok do return {false, "project manifest path is invalid"}
	if !os.exists(project.root_path) && os.make_directory_all(project.root_path) != nil do return {false, "could not create project root"}
	if !authoring_atomic_write(path, authoring_project_serialize(project)) do return {false, "could not atomically save project manifest"}
	return {true, "PROJECT MANIFEST SAVED"}
}

authoring_project_load_manifest :: proc(
	root_path: string,
	out: ^Authoring_Project,
) -> Authoring_Lifecycle_Result {
	if root_path == "" || out == nil do return {false, "project root is missing"}
	path := fmt.tprintf("%s/%s", strings.trim_right(root_path, "/"), AUTHORING_PROJECT_MANIFEST)
	cpath, error := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if error != nil do return {false, "project manifest path is invalid"}
	parsed := toml_parse_file_ex(
		cpath,
	); defer toml_free(parsed); if !parsed.ok do return {false, "project manifest could not be parsed"}
	top :=
		parsed.toptab; id := toml_case_string(top, "id"); title := toml_case_string(top, "title"); project, valid := authoring_project_new(id, title, root_path); if !valid do return {false, "project manifest identity is invalid"}
	campaign := toml_case_string(
		top,
		"campaign",
	); exports := toml_case_string(top, "export_directory"); if campaign != "" do project.campaign_path = campaign; if exports != "" do project.export_directory = exports
	if !authoring_relative_path_valid(project.campaign_path) || !authoring_relative_path_valid(project.export_directory) do return {false, "project manifest contains an unsafe campaign or export path"}
	for table in toml_tables(top, "cases") {
		case_id := toml_case_string(
			table,
			"id",
		); if !authoring_project_add_case(&project, case_id, toml_case_string(table, "title")) {return {false, "project manifest contains an invalid or duplicate case"}}
		item := &project.cases[project.case_count - 1]; item.directory = toml_case_string(table, "directory"); item.paths = {
			story                 = toml_case_string(table, "story"),
			level                 = toml_case_string(table, "level"),
			graph_layout          = toml_case_string(table, "graph_layout"),
			story_autosave        = toml_case_string(table, "story_autosave"),
			level_autosave        = toml_case_string(table, "level_autosave"),
			graph_layout_autosave = toml_case_string(table, "graph_layout_autosave"),
		}
		if !authoring_relative_path_valid(item.directory) || !authoring_relative_path_valid(item.paths.story) || !authoring_relative_path_valid(item.paths.level) || !authoring_relative_path_valid(item.paths.graph_layout) || !authoring_relative_path_valid(item.paths.story_autosave) || !authoring_relative_path_valid(item.paths.level_autosave) || !authoring_relative_path_valid(item.paths.graph_layout_autosave) do return {false, "project manifest contains an unsafe path"}
	}
	active := toml_case_int(
		top,
		"active_case",
	); project.active_case = (active >= 0 && active < project.case_count) ? active : (project.case_count > 0 ? 0 : -1); out^ = project
	assets_loaded := project_asset_registry_load_project(out, &out.asset_registry)
	if !assets_loaded.ok do return {false, assets_loaded.message}
	out.asset_registry_pending = true
	return {true, "PROJECT MANIFEST LOADED"}
}

authoring_minimal_story :: proc(
	id, title: string,
	kind: Authoring_Template_Kind,
) -> Story_Project {
	project := Story_Project {
		version          = STORY_PROJECT_VERSION,
		id               = id,
		title            = title,
		creator          = "",
		description      = "",
		content_version  = "1.0.0",
		default_space_id = "level",
		revision         = 1,
	}
	if kind == .Mystery do append(&project.capabilities, Story_Capability_Requirement{id = "mystery", version = MYSTERY_DOMAIN_VERSION})
	append(&project.conditions, Story_Condition{id = "always", kind = .Always})
	append(
		&project.scenes,
		Story_Scene{id = "opening", display_name = "Opening", entry_node = "opening_end"},
	)
	append(&project.nodes, Story_Node{id = "opening_end", scene_id = "opening", kind = .End})
	if kind == .Mystery {
		mystery_domain_register()
		append(
			&project.entities,
			Story_Entity {
				id = "culprit",
				kind = "person",
				display_name = "Culprit",
				spatial = {space_id = "level", target_kind = .Marker, target_id = "culprit_spawn"},
			},
		)
		append(
			&project.entities,
			Story_Entity {
				id = "suspect_a",
				kind = "person",
				display_name = "Suspect A",
				spatial = {
					space_id = "level",
					target_kind = .Marker,
					target_id = "suspect_a_spawn",
				},
			},
		)
		append(
			&project.entities,
			Story_Entity {
				id = "suspect_b",
				kind = "person",
				display_name = "Suspect B",
				spatial = {
					space_id = "level",
					target_kind = .Marker,
					target_id = "suspect_b_spawn",
				},
			},
		)
		append(
			&project.entities,
			Story_Entity {
				id = "evidence_source",
				kind = "object",
				display_name = "Evidence Source",
				spatial = {
					space_id = "level",
					target_kind = .Marker,
					target_id = "evidence_spawn",
				},
			},
		)
		append(
			&project.propositions,
			Story_Proposition {
				id = "case_support",
				text = "The initial evidence supports the authored solution.",
				canonical_truth = .True,
			},
		)
		payload := new(
			Mystery_Project,
		); mem.dynamic_arena_init(&payload.arena); allocator := mem.dynamic_arena_allocator(&payload.arena)
		payload.action_budget = 1; payload.clues = make([]Mystery_Clue, 1, allocator); payload.clues[0] = {
			id             = "initial_clue",
			source_id      = "evidence_source",
			description    = "Initial evidence",
			proposition_id = "case_support",
			skill          = "Observation",
			check_kind     = "white",
			cost           = 1,
			essential      = true,
		}
		payload.solution.culprit_id = "culprit"; payload.solution.requirements[0] = "initial_clue"; payload.solution.requirement_count = 1; payload.solution.exclusions[0] = "suspect_a"; payload.solution.exclusions[1] = "suspect_b"; payload.solution.exclusion_count = 2; project.capabilities[0].payload = payload
	}
	return project
}

authoring_minimal_level_text :: proc(id, title: string) -> string {return fmt.tprintf(
		"version = \"%s\"\nid = \"%s\"\nname = \"%s\"\nwidth = 16\nheight = 16\nstory_limit = 1\ndefault_snap = 0.5\nfine_snap = 0.1\nangle_snap = 15.0\nterrain = []\n\n[[stories]]\nid = \"ground\"\nname = \"Ground\"\nbase_elevation = 0.0\nfloor_height = 3.0\n\n[[markers]]\nid = \"spawn_player\"\nkind = \"player_spawn\"\nstory = 0\nposition = [[8.0, 8.0]]\nradius = 0.5\n",
		LEVEL_FORMAT_VERSION,
		authoring_lifecycle_escape(id),
		authoring_lifecycle_escape(title),
	)}

authoring_minimal_graph_layout_text :: proc(case_id: string) -> string {return fmt.tprintf(
		"version = \"1\"\ncase_id = \"%s\"\n",
		authoring_lifecycle_escape(case_id),
	)}

authoring_create_case_template :: proc(
	project: ^Authoring_Project,
	id, title: string,
	kind: Authoring_Template_Kind,
) -> Authoring_Lifecycle_Result {
	if project == nil || !authoring_project_add_case(project, id, title) do return {false, "case identity is invalid or already exists"}
	item := &project.cases[project.case_count - 1]; directory, ok := authoring_resolve_path(project, item.directory); if !ok || os.make_directory_all(directory) != nil {project.case_count -= 1; return {false, "could not create case directory"}}
	story := authoring_minimal_story(id, title, kind); defer story_project_destroy(&story)
	documents := [3]Authoring_Save_Document {
		{.Story, story.revision, story_project_serialize(&story)},
		{.Level, 1, authoring_minimal_level_text(id, title)},
		{.Graph_Layout, 1, authoring_minimal_graph_layout_text(id)},
	}
	result := authoring_save_all(
		project,
		item,
		documents[:],
	); if !result.ok {project.case_count -= 1; return result}
	_ = authoring_project_save_manifest(
		project,
	); return {true, kind == .Mystery ? "MYSTERY TEMPLATE CREATED" : "STORY TEMPLATE CREATED"}
}

authoring_bind_case_paths :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
) -> Authoring_Lifecycle_Result {
	if project == nil || item == nil do return {false, "active case is missing"}
	story, _ := authoring_resolve_path(
		project,
		item.paths.story,
	); story_auto, _ := authoring_resolve_path(project, item.paths.story_autosave)
	level, _ := authoring_resolve_path(
		project,
		item.paths.level,
	); level_auto, _ := authoring_resolve_path(project, item.paths.level_autosave)
	graph, _ := authoring_resolve_path(
		project,
		item.paths.graph_layout,
	); graph_auto, _ := authoring_resolve_path(project, item.paths.graph_layout_autosave)
	if !level_set_active_paths(level, level_auto).ok || !graph_set_document_paths(graph, graph_auto) do return {false, "editor document paths could not be bound"}
	_ = story; _ = story_auto
	return {true, "CASE DOCUMENT PATHS BOUND"}
}

authoring_save_all :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
	documents: []Authoring_Save_Document,
) -> Authoring_Lifecycle_Result {return authoring_save_all_testable(project, item, documents, -1)}

// The commit limit is an internal deterministic fault-injection seam used to
// prove transaction rollback. Production callers always pass -1 through
// authoring_save_all.
authoring_save_all_testable :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
	documents: []Authoring_Save_Document,
	fail_before_commit: int,
) -> Authoring_Lifecycle_Result {
	if project == nil || item == nil || len(documents) == 0 do return {false, "save transaction has no documents"}
	paths: [Authoring_Document_Kind]string; seen, had_original, committed: [Authoring_Document_Kind]bool
	cleanup := proc(
		paths: [Authoring_Document_Kind]string,
		documents: []Authoring_Save_Document,
	) {for 		document in documents {path := paths[document.kind]; if path == "" do continue; staged := fmt.tprintf(
				"%s.save-new",
				path,
			)
			backup := fmt.tprintf("%s.save-old", path)
			if os.exists(staged) do _ = os.remove(staged)
			if os.exists(backup) do _ = os.remove(backup)}}
	for document in documents {if seen[document.kind] {cleanup(paths, documents); return {false, "save transaction contains a duplicate document"}}
		seen[document.kind] = true
		relative := authoring_case_document_path(item, document.kind)
		path, ok := authoring_resolve_path(project, relative)
		if !ok {cleanup(paths, documents); return {false, "save transaction contains an unsafe path"}}
		paths[document.kind] = path
		directory := os.dir(path)
		if !os.exists(directory) &&
		   os.make_directory_all(directory) != nil {cleanup(paths, documents)
			return {false, "could not create document directory"}}
		if os.write_entire_file(
			   fmt.tprintf("%s.save-new", path),
			   transmute([]u8)document.serialized,
		   ) !=
		   nil {cleanup(paths, documents); return {false, "could not stage save transaction"}}}
	// Back up every original before replacing any file. A backup failure thus
	// cannot leave a partially committed set.
	for document in documents {path := paths[document.kind]
		if os.exists(
			path,
		) {had_original[document.kind] = true; data, error := os.read_entire_file_from_path(path, context.temp_allocator); if error != nil || os.write_entire_file(fmt.tprintf("%s.save-old", path), data) != nil {cleanup(paths, documents); return {false, "could not back up save transaction"}}}}
	failed := false
	for document, index in documents {path := paths[document.kind]
		staged := fmt.tprintf("%s.save-new", path)
		if fail_before_commit >= 0 && index == fail_before_commit {failed = true; break}
		if os.rename(staged, path) != nil {failed = true; break}
		committed[document.kind] = true}
	if failed {
		for document in documents {path := paths[document.kind]
			backup := fmt.tprintf("%s.save-old", path)
			if committed[document.kind] {if had_original[document.kind] {if os.exists(path) do _ = os.remove(path); _ = os.rename(backup, path)} else if os.exists(path) do _ = os.remove(path)}}
		cleanup(paths, documents); return {false, "save transaction rolled back"}
	}
	for document in documents {path := paths[document.kind]
		backup := fmt.tprintf("%s.save-old", path)
		if os.exists(backup) do _ = os.remove(backup)
		authoring_case_mark_saved(item, document.kind, document.revision)}
	return {true, "ALL DOCUMENTS SAVED"}
}

authoring_case_inbound_preview :: proc(
	project: ^Authoring_Project,
	campaign: ^Campaign_Definition,
	id: string,
) -> Authoring_Case_Inbound_Preview {
	result: Authoring_Case_Inbound_Preview; index := authoring_project_case_index(project, id); if index < 0 || campaign == nil do return result; source := project.cases[index]
	add := proc(
		result: ^Authoring_Case_Inbound_Preview,
		owner, field, value: string,
	) {if result.count >= len(result.items) {result.truncated = true; return}; result.items[result.count] =
			{owner, field, value}
		result.count += 1}
	for item in campaign.cases {if item.id == source.id do add(&result, item.id, "id", item.id); if item.story_path == source.paths.story do add(&result, item.id, "story_path", item.story_path); if item.level_path == source.paths.level do add(&result, item.id, "level_path", item.level_path)}
	for condition, i in campaign.conditions do if condition.case_id == source.id do add(&result, fmt.tprintf("condition_%d", i), "case_id", condition.case_id)
	return result
}

authoring_case_repair_inbound :: proc(
	project: ^Authoring_Project,
	campaign: ^Campaign_Definition,
	source_id, replacement_id: string,
) -> Authoring_Lifecycle_Result {
	source_index, replacement_index :=
		authoring_project_case_index(project, source_id),
		authoring_project_case_index(
			project,
			replacement_id,
		); if source_index < 0 || replacement_index < 0 || campaign == nil do return {false, "source, replacement, and campaign are required"}; source, replacement := project.cases[source_index], project.cases[replacement_index]
	for &item in campaign.cases {if item.id == source.id do item.id = replacement.id; if item.story_path == source.paths.story do item.story_path = replacement.paths.story; if item.level_path == source.paths.level do item.level_path = replacement.paths.level}; for &condition in campaign.conditions do if condition.case_id == source.id do condition.case_id = replacement.id
	return {true, "INBOUND CASE REFERENCES REPAIRED"}
}

authoring_installed_create_editable_project :: proc(
	installed: ^Authoring_Project,
	destination: string,
	out: ^Authoring_Project,
) -> Authoring_Lifecycle_Result {
	if installed == nil || out == nil do return {false, "installed project and editable destination are required"}; copy := installed^; copy.root_path = installed.root_path; result := authoring_project_save_as(&copy, destination); if !result.ok do return result; loaded := authoring_project_load_manifest(destination, out); if !loaded.ok {if os.exists(destination) do _ = os.remove_all(destination); return loaded}; return {true, "EDITABLE SOURCE PROJECT CREATED OUTSIDE INSTALLED CONTENT"}
}

authoring_recovery_save :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
	bundle: ^Authoring_Recovery_Bundle,
) -> Authoring_Lifecycle_Result {
	if project == nil || item == nil || bundle == nil || bundle.project_id != project.id || bundle.case_id != item.id do return {false, "recovery bundle identity does not match"}
	manifest := "version = \"1\"\n"
	for kind in Authoring_Document_Kind {document := bundle.documents[kind]
		if document.draft_revision < document.base_revision do return {false, "recovery draft revision is stale"}
		relative := authoring_case_document_path(item, kind, true)
		path, ok := authoring_resolve_path(project, relative)
		if !ok do return {false, "recovery path is unsafe"}
		if !os.exists(os.dir(path)) && os.make_directory_all(os.dir(path)) != nil do return {false, "could not create recovery directory"}
		if !authoring_atomic_write(path, document.serialized) do return {false, "could not save recovery document"}
		manifest = fmt.tprintf(
			"%s%s_base = %d\n%s_draft = %d\n",
			manifest,
			fmt.tprintf("%v", kind),
			document.base_revision,
			fmt.tprintf("%v", kind),
			document.draft_revision,
		)}
	manifest_path := fmt.tprintf(
		".autosave/%s/%s/recovery.toml",
		project.id,
		item.id,
	); resolved, _ := authoring_resolve_path(project, manifest_path); if !authoring_atomic_write(resolved, manifest) do return {false, "could not save recovery manifest"}; return {true, "RECOVERY BUNDLE SAVED"}
}

authoring_recovery_can_restore :: proc(
	item: ^Authoring_Case,
	bundle: ^Authoring_Recovery_Bundle,
) -> Authoring_Lifecycle_Result {
	if item == nil || bundle == nil || bundle.case_id != item.id do return {false, "recovery bundle identity does not match"}
	for kind in Authoring_Document_Kind {document := bundle.documents[kind]
		current := item.documents[kind].revision
		if document.base_revision != item.documents[kind].saved_revision || document.draft_revision < current do return {false, "recovery bundle is stale"}}
	return {true, "RECOVERY BUNDLE IS CURRENT"}
}

authoring_recovery_load :: proc(
	project: ^Authoring_Project,
	item: ^Authoring_Case,
	out: ^Authoring_Recovery_Bundle,
) -> Authoring_Lifecycle_Result {
	if project == nil || item == nil || out == nil do return {false, "recovery target is missing"}
	manifest_relative := fmt.tprintf(
		".autosave/%s/%s/recovery.toml",
		project.id,
		item.id,
	); manifest_path, ok := authoring_resolve_path(project, manifest_relative); if !ok || !os.exists(manifest_path) do return {false, "recovery manifest does not exist"}
	cpath, error := strings.clone_to_cstring(
		manifest_path,
		context.temp_allocator,
	); if error != nil do return {false, "recovery manifest path is invalid"}; parsed := toml_parse_file_ex(cpath); defer toml_free(parsed); if !parsed.ok do return {false, "recovery manifest could not be parsed"}
	bundle := Authoring_Recovery_Bundle {
		project_id = project.id,
		case_id    = item.id,
	}; top := parsed.toptab
	for kind in Authoring_Document_Kind {name := fmt.tprintf("%v", kind)
		document := &bundle.documents[kind]
		document.base_revision = u64(max(0, toml_case_int(top, fmt.tprintf("%s_base", name))))
		document.draft_revision = u64(max(0, toml_case_int(top, fmt.tprintf("%s_draft", name))))
		path, _ := authoring_resolve_path(project, authoring_case_document_path(item, kind, true))
		data, read_error := os.read_entire_file_from_path(path, context.allocator)
		if read_error != nil do return {false, "recovery document is missing"}
		document.serialized = string(data)}
	if current := authoring_recovery_can_restore(item, &bundle); !current.ok do return current
	out^ = bundle; return {true, "RECOVERY BUNDLE LOADED"}
}

authoring_recent_record :: proc(
	recents: ^Authoring_Recent_Projects,
	project: ^Authoring_Project,
	sequence: u64,
) {
	if recents == nil || project == nil do return
	index := -1; for item, i in recents.items[:recents.count] do if item.id == project.id || item.root_path == project.root_path do index = i
	if index >=
	   0 {for i in index + 1 ..< recents.count do recents.items[i - 1] = recents.items[i]; recents.count -= 1}
	if recents.count >=
	   AUTHORING_MAX_RECENTS {for i in 1 ..< recents.count do recents.items[i - 1] = recents.items[i]; recents.count -= 1}
	recents.items[recents.count] = {
		project.id,
		project.title,
		project.root_path,
		sequence,
	}; recents.count += 1
}

authoring_recents_serialize :: proc(recents: ^Authoring_Recent_Projects) -> string {
	text := "version = \"1\"\n"
	if recents == nil do return text
	for item in recents.items[:recents.count] do text = fmt.tprintf("%s\n[[projects]]\nid = \"%s\"\ntitle = \"%s\"\nroot_path = \"%s\"\nopened_sequence = %d\n", text, authoring_lifecycle_escape(item.id), authoring_lifecycle_escape(item.title), authoring_lifecycle_escape(item.root_path), item.opened_sequence)
	return text
}

authoring_recents_save :: proc(
	recents: ^Authoring_Recent_Projects,
	path: string,
) -> Authoring_Lifecycle_Result {
	if recents == nil || path == "" do return {false, "recent-project destination is missing"}
	parent := os.dir(
		path,
	); if !os.exists(parent) && os.make_directory_all(parent) != nil do return {false, "recent-project directory could not be created"}
	if !authoring_atomic_write(path, authoring_recents_serialize(recents)) do return {false, "recent projects could not be saved"}
	return {true, "RECENT PROJECTS SAVED"}
}

authoring_recents_load :: proc(
	path: string,
	out: ^Authoring_Recent_Projects,
) -> Authoring_Lifecycle_Result {
	if out == nil || path == "" do return {false, "recent-project source is missing"}; out^ = {}
	if !os.exists(path) do return {true, "NO RECENT PROJECTS YET"}
	cpath, error := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if error != nil do return {false, "recent-project path is invalid"}; parsed := toml_parse_file_ex(cpath); defer toml_free(parsed); if !parsed.ok do return {false, "recent projects could not be parsed"}
	for table in toml_tables(
		parsed.toptab,
		"projects",
	) {if out.count >= AUTHORING_MAX_RECENTS do break; id := toml_case_string(table, "id"); root := toml_case_string(table, "root_path"); if !authoring_stable_id_valid(id) || root == "" do continue; out.items[out.count] = {
			id              = id,
			title           = toml_case_string(table, "title"),
			root_path       = root,
			opened_sequence = u64(max(0, toml_case_int(table, "opened_sequence"))),
		}; out.count += 1}
	return {true, "RECENT PROJECTS LOADED"}
}

authoring_recents_default_path :: proc() -> (string, bool) {data, error := os.user_data_dir(
		context.temp_allocator,
	)
	if error != nil do return "", false
	path, joined := os.join_path(
		[]string{data, APP_STORAGE_NAME, "Authoring", "recent-projects.toml"},
		context.allocator,
	)
	return path, joined == nil}

authoring_case_rename_title :: proc(
	project: ^Authoring_Project,
	id, title: string,
) -> Authoring_Lifecycle_Result {
	index := authoring_project_case_index(project, id); next := strings.trim_space(title)
	if project == nil || index < 0 do return {false, "source case does not exist"}; if next == "" do return {false, "case title cannot be empty"}
	old := project.cases[index].title; project.cases[index].title = next
	if saved := authoring_project_save_manifest(project);
	   !saved.ok {project.cases[index].title = old; return saved}
	return {true, "CASE TITLE RENAMED · STABLE ID PRESERVED"}
}

authoring_project_save_as :: proc(
	project: ^Authoring_Project,
	destination: string,
) -> Authoring_Lifecycle_Result {
	if project == nil || destination == "" do return {false, "Save As destination is missing"}
	if destination == project.root_path do return {false, "Save As destination must differ from the source"}
	if os.exists(destination) do return {false, "Save As destination already exists"}
	if os.copy_directory_all(destination, project.root_path) !=
	   nil {if os.exists(destination) do _ = os.remove_all(destination); return {false, "whole source project could not be copied"}}
	old_root := project.root_path; project.root_path = strings.clone(destination)
	if saved := authoring_project_save_manifest(project);
	   !saved.ok {project.root_path = old_root; _ = os.remove_all(destination); return saved}
	return {true, "WHOLE PROJECT SAVED AS NEW SOURCE COPY"}
}

// Relocate a case within its source project without changing its stable ID.
// Autosaves remain keyed by project/case identity; only source-document paths
// move. This is deliberately project-relative so a case cannot escape into an
// installed package or player-save tree.
authoring_case_move_directory :: proc(
	project: ^Authoring_Project,
	id, target_directory: string,
) -> Authoring_Lifecycle_Result {
	index := authoring_project_case_index(project, id)
	if project == nil || index < 0 do return {false, "source case does not exist"}
	if !authoring_relative_path_valid(target_directory) do return {false, "case destination must be project-relative"}
	item := &project.cases[index]
	if item.directory == target_directory do return {true, "CASE ALREADY USES THAT DIRECTORY"}
	for other, i in project.cases[:project.case_count] do if i != index && other.directory == target_directory do return {false, "case destination is already in use"}
	from, from_ok := authoring_resolve_path(
		project,
		item.directory,
	); to, to_ok := authoring_resolve_path(project, target_directory)
	if !from_ok || !to_ok || !os.exists(from) do return {false, "case source directory is missing"}
	if os.exists(to) do return {false, "case destination already exists"}
	if !os.exists(os.dir(to)) && os.make_directory_all(os.dir(to)) != nil do return {false, "case destination parent could not be created"}
	original_directory := item.directory; original_paths := item.paths
	if os.rename(from, to) != nil do return {false, "case directory could not be moved"}
	item.directory = target_directory
	item.paths.story = fmt.tprintf("%s/story.toml", target_directory)
	item.paths.level = fmt.tprintf("%s/level.toml", target_directory)
	item.paths.graph_layout = fmt.tprintf("%s/graph.layout.toml", target_directory)
	if saved := authoring_project_save_manifest(project); !saved.ok {
		// Best-effort rollback keeps an in-memory/project-manifest mismatch from
		// becoming the normal failure mode.
		_ = os.rename(to, from)
		item.directory = original_directory; item.paths = original_paths
		return saved
	}
	return {true, "CASE SOURCE DIRECTORY MOVED"}
}

authoring_case_operation_plan :: proc(
	project: ^Authoring_Project,
	kind: Authoring_Case_Operation_Kind,
	source_id, target_id, target_title: string,
	installed: bool = false,
	campaign: ^Campaign_Definition = nil,
) -> Authoring_Case_Operation {
	result := Authoring_Case_Operation {
		kind         = kind,
		source_case  = authoring_project_case_index(project, source_id),
		target_case  = -1,
		target_id    = target_id,
		target_title = target_title,
	}
	if project == nil ||
	   result.source_case <
		   0 {result.message = "source case does not exist"; return result}; source := &project.cases[result.source_case]; result.source_directory = source.directory
	if kind ==
	   .Delete {result.inbound = authoring_case_inbound_preview(project, campaign, source_id); if result.inbound.count > 0 || result.inbound.truncated {result.message = "case deletion is blocked by inbound campaign references"; return result}; result.recoverable_directory = fmt.tprintf(".trash/%s/%s-%d", project.id, source.id, source.documents[.Story].revision); result.allowed = true; result.message = "case will be moved to recoverable trash"; return result}
	if !authoring_stable_id_valid(target_id) ||
	   authoring_project_case_index(project, target_id) >=
		   0 {result.message = "target case identity is invalid or already exists"; return result}
	result.target_directory = fmt.tprintf(
		"cases/%s",
		target_id,
	); result.allowed = true; result.message = installed ? "installed content will be copied into editable source" : "case operation is safe to execute"; return result
}

authoring_case_operation_execute :: proc(
	project: ^Authoring_Project,
	plan: ^Authoring_Case_Operation,
) -> Authoring_Lifecycle_Result {
	if project == nil || plan == nil || !plan.allowed || plan.source_case < 0 || plan.source_case >= project.case_count do return {false, "case operation is not allowed"}
	source := project.cases[plan.source_case]
	if plan.kind ==
	   .Delete {from, _ := authoring_resolve_path(project, source.directory); to, _ := authoring_resolve_path(project, plan.recoverable_directory); if os.make_directory_all(os.dir(to)) != nil || os.rename(from, to) != nil do return {false, "case could not be moved to recoverable trash"}; for i in plan.source_case + 1 ..< project.case_count do project.cases[i - 1] = project.cases[i]; project.case_count -= 1; project.active_case = project.case_count > 0 ? clamp(project.active_case, 0, project.case_count - 1) : -1; _ = authoring_project_save_manifest(project); return {true, "CASE MOVED TO RECOVERABLE TRASH"}}
	if plan.kind == .Rename ||
	   plan.kind ==
		   .Move {from, _ := authoring_resolve_path(project, source.directory); to, _ := authoring_resolve_path(project, plan.target_directory); if os.rename(from, to) != nil do return {false, "case directory could not be moved"}; replacement, _ := authoring_case_new(project.id, plan.target_id, plan.target_title); replacement.documents = source.documents; project.cases[plan.source_case] = replacement; _ = authoring_project_save_manifest(project); return {true, "CASE MOVED AND REIDENTIFIED"}}
	if !authoring_project_add_case(project, plan.target_id, plan.target_title) do return {false, "editable case could not be registered"}; target := &project.cases[project.case_count - 1]; target_dir, _ := authoring_resolve_path(project, target.directory); if os.make_directory_all(target_dir) != nil {project.case_count -= 1; return {false, "editable case directory could not be created"}}
	for kind in Authoring_Document_Kind {source_path, _ := authoring_resolve_path(
			project,
			authoring_case_document_path(&source, kind),
		)
		target_path, _ := authoring_resolve_path(
			project,
			authoring_case_document_path(target, kind),
		)
		data, error := os.read_entire_file_from_path(source_path, context.temp_allocator)
		if error != nil ||
		   !authoring_atomic_write(
				   target_path,
				   string(data),
			   ) {project.case_count -= 1; return {false, "case copy was incomplete"}}}
	_ = authoring_project_save_manifest(
		project,
	); return {true, plan.kind == .Editable_Copy ? "EDITABLE COPY CREATED" : "CASE DUPLICATED"}
}
