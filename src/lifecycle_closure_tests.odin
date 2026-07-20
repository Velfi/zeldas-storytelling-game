package main

import "core:fmt"
import "core:os"

lifecycle_test_read :: proc(path: string) -> string {data, error := os.read_entire_file_from_path(
		path,
		context.temp_allocator,
	)
	assert(error == nil)
	return string(data)}

run_lifecycle_closure_tests :: proc() {
	root := "/private/tmp/chicago-lifecycle-closure"; if os.exists(root) do assert(os.remove_all(root) == nil); assert(os.make_directory_all(root) == nil)
	project, ok := authoring_project_new(
		"lifecycle_closure",
		"Lifecycle Closure",
		root,
	); assert(ok); assert(authoring_create_case_template(&project, "case_a", "Case A", .General_Story).ok); assert(authoring_create_case_template(&project, "case_b", "Case B", .General_Story).ok)
	a := &project.cases[authoring_project_case_index(&project, "case_a")]; b := &project.cases[authoring_project_case_index(&project, "case_b")]
	a_story, _ := authoring_resolve_path(
		&project,
		a.paths.story,
	); a_level, _ := authoring_resolve_path(&project, a.paths.level); a_graph, _ := authoring_resolve_path(&project, a.paths.graph_layout); a_before := [3]string{lifecycle_test_read(a_story), lifecycle_test_read(a_level), lifecycle_test_read(a_graph)}
	b_documents := [3]Authoring_Save_Document {
		{.Story, 7, "CASE B STORY BYTES"},
		{.Level, 8, "CASE B LEVEL BYTES"},
		{.Graph_Layout, 9, "CASE B GRAPH BYTES"},
	}; assert(authoring_save_all(&project, b, b_documents[:]).ok); assert(lifecycle_test_read(a_story) == a_before[0] && lifecycle_test_read(a_level) == a_before[1] && lifecycle_test_read(a_graph) == a_before[2])

	// All originals and document revisions survive a deterministic failure after
	// the first replacement has committed.
	b_story, _ := authoring_resolve_path(
		&project,
		b.paths.story,
	); b_level, _ := authoring_resolve_path(&project, b.paths.level); b_graph, _ := authoring_resolve_path(&project, b.paths.graph_layout); b_before := [3]string{lifecycle_test_read(b_story), lifecycle_test_read(b_level), lifecycle_test_read(b_graph)}; states_before := b.documents
	failing := [3]Authoring_Save_Document {
		{.Story, 10, "NEW STORY"},
		{.Level, 11, "NEW LEVEL"},
		{.Graph_Layout, 12, "NEW GRAPH"},
	}; rolled_back := authoring_save_all_testable(&project, b, failing[:], 1); assert(!rolled_back.ok && lifecycle_test_read(b_story) == b_before[0] && lifecycle_test_read(b_level) == b_before[1] && lifecycle_test_read(b_graph) == b_before[2] && b.documents == states_before); assert(!os.exists(fmt.tprintf("%s.save-new", b_story)) && !os.exists(fmt.tprintf("%s.save-old", b_story)))

	// Duplicate copies all three source documents byte-for-byte while assigning
	// independent case identity and paths. A later edit diverges only the copy.
	duplicate := authoring_case_operation_plan(
		&project,
		.Duplicate,
		"case_a",
		"case_a_copy",
		"Case A Copy",
	); assert(duplicate.allowed && authoring_case_operation_execute(&project, &duplicate).ok); copy := &project.cases[authoring_project_case_index(&project, "case_a_copy")]; assert(copy.id != "case_a" && copy.paths.story != a.paths.story && copy.paths.level != a.paths.level && copy.paths.graph_layout != a.paths.graph_layout)
	for kind in Authoring_Document_Kind {source_path, _ := authoring_resolve_path(
			&project,
			authoring_case_document_path(a, kind),
		)
		copy_path, _ := authoring_resolve_path(&project, authoring_case_document_path(copy, kind))
		assert(
			lifecycle_test_read(source_path) == lifecycle_test_read(copy_path),
		)}; copy_story, _ := authoring_resolve_path(&project, copy.paths.story); assert(authoring_atomic_write(copy_story, "DIVERGED COPY")); assert(lifecycle_test_read(a_story) == a_before[0] && lifecycle_test_read(copy_story) == "DIVERGED COPY")

	// One recovery manifest owns Story, Level, and Graph drafts and restores them
	// atomically into three live workspaces.
	recovery_story: Story_Project; assert(load_story_project(a_story, &recovery_story).ok); recovery_story.title = "Recovered Story"; recovery_story.revision = 21
	recovery_level: Level_Document; assert(level_load(a_level, &recovery_level).ok); recovery_level.name = "Recovered Level"; recovery_level.revision = 22
	recovery_graph := authoring_graph_from_story(&recovery_story); recovery_graph.revision = 23
	bundle := Authoring_Recovery_Bundle {
		project_id = project.id,
		case_id    = a.id,
	}; bundle.documents[.Story] = {
		.Story,
		a.documents[.Story].saved_revision,
		21,
		story_project_serialize(&recovery_story),
	}; bundle.documents[.Level] = {.Level, a.documents[.Level].saved_revision, 22, level_serialize(&recovery_level)}; bundle.documents[.Graph_Layout] = {.Graph_Layout, a.documents[.Graph_Layout].saved_revision, 23, fmt.tprintf("version = \"1\"\ncase\t%s\nrevision = 23\n", a.id)}; assert(authoring_recovery_save(&project, a, &bundle).ok)
	loaded_bundle: Authoring_Recovery_Bundle; loaded_recovery := authoring_recovery_load(&project, a, &loaded_bundle); if !loaded_recovery.ok do fmt.println("LIFECYCLE RECOVERY LOAD · ", loaded_recovery.message); assert(loaded_recovery.ok); live_story: Story_Project; live_level: Level_Document; live_graph: Graph_Document; loaded_live := authoring_workspace_load_case_documents(&project, authoring_project_case_index(&project, "case_a"), &live_story, &live_level, &live_graph); if !loaded_live.ok do fmt.println("LIFECYCLE LIVE LOAD · ", loaded_live.message); assert(loaded_live.ok); applied := authoring_recovery_apply(&project, a, &loaded_bundle, &live_story, &live_graph, &live_level); if !applied.ok do fmt.println("LIFECYCLE RECOVERY APPLY · ", applied.message); assert(applied.ok && live_story.title == "Recovered Story" && live_story.revision == 21 && live_level.name == "Recovered Level" && live_level.revision == 22 && live_graph.revision == 23); story_project_destroy(&live_story); authoring_level_document_destroy(&live_level); authoring_graph_document_destroy(&live_graph); story_project_destroy(&recovery_story); authoring_level_document_destroy(&recovery_level); authoring_graph_document_destroy(&recovery_graph)

	// Campaign references are previewed, block deletion, and can be repaired to
	// another case before deletion is planned.
	campaign :=
		Campaign_Definition{}; append(&campaign.conditions, Campaign_Condition{kind = .Case_Completed, case_id = "case_a"}); append(&campaign.cases, Campaign_Case{id = "case_a", story_path = a.paths.story, level_path = a.paths.level}); preview := authoring_case_inbound_preview(&project, &campaign, "case_a"); assert(preview.count == 4); blocked := authoring_case_operation_plan(&project, .Delete, "case_a", "", "", campaign = &campaign); assert(!blocked.allowed && blocked.inbound.count == 4); assert(authoring_case_repair_inbound(&project, &campaign, "case_a", "case_b").ok); assert(authoring_case_inbound_preview(&project, &campaign, "case_a").count == 0 && campaign.cases[0].id == "case_b" && campaign.cases[0].story_path == b.paths.story && campaign.conditions[0].case_id == "case_b"); unblocked := authoring_case_operation_plan(&project, .Delete, "case_a", "", "", campaign = &campaign); assert(unblocked.allowed); campaign_destroy(&campaign)

	// Installed sources reject every authoring mutation. The escape hatch copies
	// the whole project to a distinct source root and leaves installed bytes intact.
	installed_manifest := lifecycle_test_read(
		fmt.tprintf("%s/%s", root, AUTHORING_PROJECT_MANIFEST),
	); saved_project, saved_ready, saved_read_only, saved_package := active_authoring_project, active_authoring_ready, active_authoring_read_only, player_package_mode; active_authoring_project = project; active_authoring_ready = true; active_authoring_read_only = true; player_package_mode = true; assert(!authoring_app_new_case("forbidden", "Forbidden", false).ok && !authoring_app_duplicate_case("case_b", "forbidden_copy", "Forbidden Copy").ok && !authoring_app_delete_case("case_b").ok && !authoring_app_save_all().ok); active_authoring_project = saved_project; active_authoring_ready = saved_ready; active_authoring_read_only = saved_read_only; player_package_mode = saved_package; assert(lifecycle_test_read(fmt.tprintf("%s/%s", root, AUTHORING_PROJECT_MANIFEST)) == installed_manifest)
	editable_root := "/private/tmp/chicago-lifecycle-editable"; if os.exists(editable_root) do assert(os.remove_all(editable_root) == nil); editable: Authoring_Project; assert(authoring_installed_create_editable_project(&project, editable_root, &editable).ok && editable.root_path == editable_root && editable.root_path != project.root_path); editable_case := &editable.cases[authoring_project_case_index(&editable, "case_b")]; editable_case_path, _ := authoring_resolve_path(&editable, editable_case.paths.story); assert(authoring_atomic_write(editable_case_path, "EDITABLE SOURCE")); assert(lifecycle_test_read(b_story) == b_before[0]); project_asset_registry_destroy(&editable.asset_registry)
}
