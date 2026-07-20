package main

import "core:fmt"
import "core:os"

run_authoring_library_backend_tests :: proc() {
	// The export boundary must validate the same committed bytes consumed by
	// the package tools. In particular, an unsaved Graph edit is compiled into
	// Story by Save All and the export snapshot reloads that compiled file,
	// never the stale pre-build Story object.
	snapshot_root := "/private/tmp/chicago-export-snapshot-contract"; if os.exists(snapshot_root) do assert(os.remove_all(snapshot_root) == nil); assert(os.make_directory_all(snapshot_root) == nil)
	snapshot_project, snapshot_ok := authoring_project_new(
		"snapshot_story",
		"Snapshot Story",
		snapshot_root,
	); assert(snapshot_ok && authoring_project_add_case(&snapshot_project, "snapshot_case", "Snapshot Case"))
	snapshot_item := &snapshot_project.cases[0]; snapshot_story_path, _ := authoring_resolve_path(&snapshot_project, snapshot_item.paths.story); snapshot_level_path, _ := authoring_resolve_path(&snapshot_project, snapshot_item.paths.level)
	stale_story: Story_Project; assert(load_story_project(STORY_BLANK_PROOF_PATH, &stale_story).ok); defer story_project_destroy(&stale_story); assert(os.make_directory_all(os.dir(snapshot_story_path)) == nil && authoring_atomic_write(snapshot_story_path, story_project_serialize(&stale_story)))
	snapshot_graph := authoring_graph_from_story(
		&stale_story,
	); assert(snapshot_graph.scene_count > 0); snapshot_graph.scenes[0].scene.display_name = "UNSAVED GRAPH SNAPSHOT TITLE"; snapshot_graph.dirty = true; snapshot_graph.revision += 1
	saved_global_graph :=
		graph_document; graph_document = snapshot_graph; compiled_story: Story_Project; compiled := graph_build_story_project(&stale_story, &compiled_story); snapshot_graph = graph_document; graph_document = saved_global_graph; assert(compiled.ok); defer story_project_destroy(&compiled_story)
	snapshot_level: Level_Document; assert(level_load(LEVEL_DEFAULT_PATH, &snapshot_level).ok); defer authoring_level_document_destroy(&snapshot_level); assert(authoring_atomic_write(snapshot_level_path, level_serialize(&snapshot_level)))
	documents := [3]Authoring_Save_Document {
		{.Story, compiled_story.revision, story_project_serialize(&compiled_story)},
		{.Level, snapshot_level.revision, level_serialize(&snapshot_level)},
		{
			.Graph_Layout,
			snapshot_graph.revision,
			fmt.tprintf("revision = %d\n", snapshot_graph.revision),
		},
	}; assert(authoring_save_all(&snapshot_project, snapshot_item, documents[:]).ok)
	committed := new(
		Authoring_Story_Export_Snapshot,
	); assert(authoring_story_export_snapshot_load(&snapshot_project, snapshot_item, committed).ok && committed.story.scenes[0].display_name == "UNSAVED GRAPH SNAPSHOT TITLE" && stale_story.scenes[0].display_name != "UNSAVED GRAPH SNAPSHOT TITLE"); authoring_story_export_snapshot_destroy(committed); free(committed); authoring_graph_document_destroy(&snapshot_graph)

	identity_v1 := Authoring_Content_Identity {
		"library_story",
		"1.0.0",
		.Story,
	}; identity_v2 := Authoring_Content_Identity{"library_story", "2.0.0", .Story}; identity_old := Authoring_Content_Identity{"library_story", "0.9.0", .Story}
	inspection := Authoring_Package_Inspection {
		artifact = {
			identity = identity_v2,
			package_path = "package.story",
			artifact_hash = "hash",
			format = "InteractiveStoryPackage",
			format_version = "1",
		},
		integrity = .Valid,
		compatibility = .Compatible,
	}
	library :=
		Authoring_Library{}; append(&library.installed, Authoring_Installed_Version{identity = identity_v1, install_root = "/installed/library_story/1.0.0", package_hash = "old", active = true})
	coexist := authoring_library_plan_import(
		&library,
		&inspection,
		.Coexist,
		"/library",
	); assert(coexist.allowed && coexist.preserve_existing); authoring_import_plan_destroy(&coexist)
	upgrade := authoring_library_plan_import(
		&library,
		&inspection,
		.Upgrade,
		"/library",
	); assert(upgrade.allowed && upgrade.preserve_existing); authoring_import_plan_destroy(&upgrade)
	downgrade_inspection :=
		inspection; downgrade_inspection.artifact.identity = identity_old; downgrade := authoring_library_plan_import(&library, &downgrade_inspection, .Upgrade, "/library"); assert(!downgrade.allowed); authoring_import_plan_destroy(&downgrade)
	replace_missing := authoring_library_plan_import(
		&library,
		&inspection,
		.Replace,
		"/library",
	); assert(!replace_missing.allowed); authoring_import_plan_destroy(&replace_missing)
	exact_inspection :=
		inspection; exact_inspection.artifact.identity = identity_v1; replace := authoring_library_plan_import(&library, &exact_inspection, .Replace, "/library"); assert(replace.allowed && !replace.preserve_existing); authoring_import_plan_destroy(&replace); exact_coexist := authoring_library_plan_import(&library, &exact_inspection, .Coexist, "/library"); assert(!exact_coexist.allowed); authoring_import_plan_destroy(&exact_coexist)

	// Inspection exposes the complete manifest-facing surface rather than only
	// identity and counts.
	json := "{\"format\":\"InteractiveStoryPackage\",\"capabilities\":[{\"id\":\"mystery\",\"version\":\"1\"}],\"expansions\":[{\"id\":\"props\",\"version\":\"2.0.0\",\"optional\":false}],\"files\":[{\"path\":\"assets/clue.png\",\"size\":12,\"sha256\":\"abc\"},{\"path\":\"story.toml\",\"size\":8,\"sha256\":\"def\"}],\"cases\":[{\"story_id\":\"case_a\",\"content_version\":\"1.2.0\"}]}"
	parsed :=
		Authoring_Package_Inspection{}; authoring_inspection_parse_capabilities(json, &parsed); authoring_inspection_parse_dependencies(json, &parsed); authoring_inspection_parse_files(json, &parsed); authoring_inspection_parse_cases(json, &parsed); assert(len(parsed.capabilities) == 1 && parsed.capabilities[0] == "mystery@1" && len(parsed.dependencies) == 1 && parsed.dependencies[0].id == "props" && !parsed.dependencies[0].optional && len(parsed.files) == 2 && parsed.asset_count == 1 && parsed.total_bytes == 20 && parsed.case_count == 1 && parsed.cases[0].id == "case_a"); authoring_package_inspection_destroy(&parsed)

	resolution_inspection := Authoring_Package_Inspection {
			artifact = {identity = {"resolution_story", "1.0.0", .Story}},
			integrity = .Valid,
			compatibility = .Compatible,
		}; append(
		&resolution_inspection.dependencies,
		Authoring_Package_Dependency{"required_expansion", "2.0.0", false},
		Authoring_Package_Dependency{"optional_expansion", "1.0.0", true},
	); append(&resolution_inspection.capabilities, "mystery@1", "unsupported@9"); resolution := authoring_service_resolve(&resolution_inspection, &library, []string{"mystery@1"}); assert(!resolution.compatible && len(resolution.missing_dependencies) == 1 && resolution.missing_dependencies[0] == "required_expansion" && len(resolution.incompatible_capabilities) == 1 && resolution.incompatible_capabilities[0] == "unsupported@9"); authoring_service_resolution_destroy(&resolution); assert(!authoring_service_apply_resolution(&resolution_inspection, &library, []string{"mystery@1"}) && resolution_inspection.compatibility == .Missing_Dependency && len(resolution_inspection.compatibility_warnings) == 2 && len(resolution_inspection.typed_warnings) == 2 && resolution_inspection.typed_warnings[0].audience == .Player_Safe && resolution_inspection.typed_warnings[1].audience == .Player_Safe && !authoring_package_inspection_installable(&resolution_inspection)); authoring_package_inspection_destroy(&resolution_inspection)

	// Required dependency edges block uninstall unless another installed version
	// satisfies the minimum; player saves are reported but preserved.
	dependent := Authoring_Content_Identity {
		"campaign",
		"1.0.0",
		.Campaign,
	}; append(&library.installed, Authoring_Installed_Version{identity = dependent}); append(&library.saves, Authoring_Player_Save{content = identity_v1, save_id = "save", save_root = "/saves/save"}); append(&library.dependency_edges, Authoring_Library_Dependency_Edge{dependent, identity_v1, false}); blocked_uninstall := authoring_library_plan_uninstall(&library, identity_v1); assert(!blocked_uninstall.allowed && len(blocked_uninstall.dependent_indices) == 1 && len(blocked_uninstall.save_indices) == 1); authoring_uninstall_plan_destroy(&blocked_uninstall); append(&library.installed, Authoring_Installed_Version{identity = identity_v2}); unblocked_uninstall := authoring_library_plan_uninstall(&library, identity_v1); assert(unblocked_uninstall.allowed && len(unblocked_uninstall.dependent_indices) == 0 && len(unblocked_uninstall.save_indices) == 1); authoring_uninstall_plan_destroy(&unblocked_uninstall)

	root := "/private/tmp/chicago-library-backend-tests"; if os.exists(root) do assert(os.remove_all(root) == nil); assert(os.make_directory_all(root) == nil)
	tool_path := fmt.tprintf(
		"%s/mock_install.py",
		root,
	); tool := "import os,sys\nlib=sys.argv[sys.argv.index('--library')+1]\nroot=os.path.join(lib,'mock_story','1.0.0')\nos.makedirs(root,exist_ok=True)\nopen(os.path.join(root,'runtime.txt'),'w').write('installed')\n"; assert(os.write_entire_file(tool_path, tool) == nil)
	fail_tool_path := fmt.tprintf(
		"%s/mock_fail.py",
		root,
	); fail_tool := "import sys\nsys.stderr.write('intentional install failure')\nsys.exit(3)\n"; assert(os.write_entire_file(fail_tool_path, fail_tool) == nil)
	config := authoring_library_service_default_config(
		root,
	); config.story_tool = tool_path; library_root := fmt.tprintf("%s/installed", root); source_root := fmt.tprintf("%s/source", root); assert(os.make_directory_all(source_root) == nil); source_marker := fmt.tprintf("%s/source.toml", source_root); assert(os.write_entire_file(source_marker, "source-owned") == nil)
	mock_inspection := Authoring_Package_Inspection {
		artifact = {
			identity = {"mock_story", "1.0.0", .Story},
			package_path = fmt.tprintf("%s/mock.story", root),
			artifact_hash = "mock-hash",
			format = "InteractiveStoryPackage",
			format_version = "1",
		},
		integrity = .Valid,
		compatibility = .Compatible,
	}
	installed := authoring_service_install(
		&config,
		{
			inspection = &mock_inspection,
			package_path = mock_inspection.artifact.package_path,
			library_root = library_root,
			decision = .Coexist,
		},
	); assert(installed.ok && os.is_file(fmt.tprintf("%s/runtime.txt", installed.installed.install_root))); source_bytes, source_error := os.read_entire_file_from_path(source_marker, context.temp_allocator); assert(source_error == nil && string(source_bytes) == "source-owned")
	manifest_path := fmt.tprintf(
		"%s/interactive-story-manifest.json",
		installed.installed.install_root,
	); assert(os.write_entire_file(manifest_path, "{\"format\":\"InteractiveStoryPackage\",\"story_id\":\"mock_story\",\"content_version\":\"1.0.0\",\"expansions\":[]}") == nil); scanned := Authoring_Library{}; append(&scanned.sources, Authoring_Source_Project{identity = mock_inspection.artifact.identity, project_root = source_root}); append(&scanned.saves, Authoring_Player_Save{content = mock_inspection.artifact.identity, save_id = "scan-save", save_root = "separate"}); scan_result := authoring_service_scan_library(library_root, &scanned); assert(scan_result.ok && len(scanned.installed) == 1 && scanned.installed[0].identity == mock_inspection.artifact.identity && len(scanned.sources) == 1 && len(scanned.saves) == 1); delete(scanned.installed); delete(scanned.sources); delete(scanned.saves); delete(scanned.dependency_edges)
	service_library :=
		Authoring_Library{}; append(&service_library.installed, installed.installed); append(&service_library.saves, Authoring_Player_Save{content = mock_inspection.artifact.identity, save_id = "separate-save", save_root = fmt.tprintf("%s/saves/separate-save", root)}); plan := authoring_library_plan_uninstall(&service_library, mock_inspection.artifact.identity); assert(plan.allowed); uninstalled := authoring_service_uninstall(&service_library, &plan); assert(uninstalled.ok && len(service_library.installed) == 0 && len(service_library.saves) == 1 && os.is_file(source_marker)); authoring_uninstall_plan_destroy(&plan)

	// A post-install editable-copy error removes the new install. A failed
	// Replace restores the exact prior bytes from its backup.
	editable_existing := fmt.tprintf(
		"%s/editable",
		root,
	); assert(os.make_directory_all(editable_existing) == nil); rolled_back := authoring_service_install(&config, {inspection = &mock_inspection, package_path = mock_inspection.artifact.package_path, library_root = library_root, editable_root = editable_existing, decision = .Editable_Copy}); assert(!rolled_back.ok && !os.exists(authoring_service_identity_root(library_root, mock_inspection.artifact.identity)))
	prior_root := authoring_service_identity_root(
		library_root,
		mock_inspection.artifact.identity,
	); assert(os.make_directory_all(prior_root) == nil); prior_marker := fmt.tprintf("%s/prior.txt", prior_root); assert(os.write_entire_file(prior_marker, "prior-version") == nil); config.story_tool = fail_tool_path; replace_failed := authoring_service_install(&config, {inspection = &mock_inspection, package_path = mock_inspection.artifact.package_path, library_root = library_root, decision = .Replace}); assert(!replace_failed.ok && os.is_file(prior_marker)); prior_bytes, prior_error := os.read_entire_file_from_path(prior_marker, context.temp_allocator); assert(prior_error == nil && string(prior_bytes) == "prior-version")

	delete(
		library.installed,
	); delete(library.sources); delete(library.saves); delete(library.dependency_edges); delete(service_library.installed); delete(service_library.saves); authoring_package_inspection_destroy(&inspection); authoring_package_inspection_destroy(&mock_inspection)
}
