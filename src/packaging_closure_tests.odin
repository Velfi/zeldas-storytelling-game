package main

import "core:fmt"
import "core:os"
import "core:strings"

packaging_closure_config :: proc(root, version: string) -> string {return fmt.tprintf(
		"{{\"author\":\"Closure\",\"description\":\"Packaging closure fixture\",\"content_version\":\"%s\",\"story\":\"story.toml\",\"level\":\"level.toml\",\"acknowledge_incomplete_validation\":true,\"include\":[],\"exclude\":[]}}",
		version,
	)}

packaging_closure_export :: proc(
	config: ^Authoring_Library_Service_Config,
	root, version, output: string,
	capability: bool = false,
	external_dependency: bool = false,
) -> Authoring_Service_Result {
	story := authoring_minimal_story(
		"packaging_closure",
		"Packaging Closure",
		.General_Story,
	); story.content_version = version; if capability do append(&story.capabilities, Story_Capability_Requirement{id = "future_domain", version = "99"}); if external_dependency do append(&story.expansion_requirements, Story_Expansion_Requirement{id = "closure_external", version = "4.2.0", distribution = .Reference}); assert(authoring_atomic_write(fmt.tprintf("%s/story.toml", root), story_project_serialize(&story))); story_project_destroy(&story); assert(authoring_atomic_write(fmt.tprintf("%s/level.toml", root), authoring_minimal_level_text("packaging_closure", "Packaging Closure"))); config_path := fmt.tprintf("%s/package.json", root); assert(authoring_atomic_write(config_path, packaging_closure_config(root, version))); return authoring_service_export(config, {kind = .Story, source_root = root, config_path = config_path, output_path = output, skip_engine_validation = true})
}

run_packaging_closure_tests :: proc() {
	root := "/private/tmp/chicago-packaging-closure"; if os.exists(root) do assert(os.remove_all(root) == nil); assert(os.make_directory_all(root) == nil); config := authoring_library_service_default_config(".")
	v1 := fmt.tprintf(
		"%s/closure-v1.interactive-story",
		root,
	); exported_v1 := packaging_closure_export(&config, root, "1.0.0", v1); if !exported_v1.ok do fmt.println("PACKAGING V1 EXPORT · ", exported_v1.message); assert(exported_v1.ok && os.is_file(v1) && exported_v1.artifact.identity == Authoring_Content_Identity{"packaging_closure", "1.0.0", .Story})
	// The UI service and direct CLI produce byte-identical deterministic archives.
	direct := fmt.tprintf(
		"%s/closure-v1-cli.interactive-story",
		root,
	); tool := authoring_service_tool_path(&config, config.story_tool); direct_ok, direct_message := authoring_service_run(&config, []string{config.python, tool, "export", direct, "--config", fmt.tprintf("%s/package.json", root), "--root", root, "--skip-engine-validation"}); delete(direct_message); assert(direct_ok); service_hash, service_hashed := project_asset_sha256_file(v1); direct_hash, direct_hashed := project_asset_sha256_file(direct); assert(service_hashed.ok && direct_hashed.ok && service_hash == direct_hash)
	inspection_v1: Authoring_Package_Inspection; assert(authoring_service_inspect(&config, v1, .Story, &inspection_v1).ok && inspection_v1.integrity == .Valid && inspection_v1.artifact.artifact_hash == service_hash && len(inspection_v1.files) > 0)

	// A damaged real archive fails the same full inspection service with an
	// actionable non-empty message.
	corrupt := fmt.tprintf(
		"%s/corrupt.interactive-story",
		root,
	); bytes, read_error := os.read_entire_file_from_path(v1, context.allocator); assert(read_error == nil && len(bytes) > 32); corrupt_at := len(bytes) / 3; bytes[corrupt_at] = bytes[corrupt_at] ~ u8(0x5a); assert(os.write_entire_file(corrupt, bytes) == nil); delete(bytes); corrupt_inspection: Authoring_Package_Inspection; corrupt_result := authoring_service_inspect(&config, corrupt, .Story, &corrupt_inspection); assert(!corrupt_result.ok && corrupt_result.message != "")

	// Real versions coexist as distinct physical roots. Installing them never
	// changes source bytes, the package archives, or player-save bytes.
	source_before := lifecycle_test_read(
		fmt.tprintf("%s/story.toml", root),
	); package_before := lifecycle_test_read(v1); library_root := fmt.tprintf("%s/library", root); saves_root := fmt.tprintf("%s/saves", root); assert(os.make_directory_all(saves_root) == nil); save_path := fmt.tprintf("%s/player.save", saves_root); assert(os.write_entire_file(save_path, "PLAYER PROGRESS") == nil)
	installed_v1 := authoring_service_install(
		&config,
		{
			inspection = &inspection_v1,
			package_path = v1,
			library_root = library_root,
			decision = .Coexist,
		},
	); assert(installed_v1.ok && os.is_dir(installed_v1.installed.install_root) && lifecycle_test_read(fmt.tprintf("%s/story.toml", root)) == source_before)
	v2 := fmt.tprintf(
		"%s/closure-v2.interactive-story",
		root,
	); exported_v2 := packaging_closure_export(&config, root, "2.0.0", v2); assert(exported_v2.ok); inspection_v2: Authoring_Package_Inspection; assert(authoring_service_inspect(&config, v2, .Story, &inspection_v2).ok); installed_v2 := authoring_service_install(&config, {inspection = &inspection_v2, package_path = v2, library_root = library_root, decision = .Coexist}); assert(installed_v2.ok && installed_v1.installed.install_root != installed_v2.installed.install_root && os.is_dir(installed_v1.installed.install_root) && os.is_dir(installed_v2.installed.install_root)); assert(lifecycle_test_read(v1) == package_before && lifecycle_test_read(save_path) == "PLAYER PROGRESS")
	upgrade_root := fmt.tprintf(
		"%s/upgrade-library",
		root,
	); assert(authoring_service_install(&config, {inspection = &inspection_v1, package_path = v1, library_root = upgrade_root, decision = .Coexist}).ok); upgraded := authoring_service_install(&config, {inspection = &inspection_v2, package_path = v2, library_root = upgrade_root, decision = .Upgrade}); assert(upgraded.ok && os.is_dir(upgraded.installed.install_root) && os.is_dir(authoring_service_identity_root(upgrade_root, inspection_v1.artifact.identity)))
	replace_root := fmt.tprintf(
		"%s/replace-library",
		root,
	); assert(authoring_service_install(&config, {inspection = &inspection_v1, package_path = v1, library_root = replace_root, decision = .Coexist}).ok); replaced := authoring_service_install(&config, {inspection = &inspection_v1, package_path = v1, library_root = replace_root, decision = .Replace}); assert(replaced.ok && os.is_dir(replaced.installed.install_root))
	editable_library := fmt.tprintf(
		"%s/editable-library",
		root,
	); editable_root := fmt.tprintf("%s/editable-source", root); editable := authoring_service_install(&config, {inspection = &inspection_v1, package_path = v1, library_root = editable_library, editable_root = editable_root, decision = .Editable_Copy}); assert(editable.ok && os.is_dir(editable_root) && os.is_dir(editable.installed.install_root))
	library: Authoring_Library; append(&library.sources, Authoring_Source_Project{identity = inspection_v2.artifact.identity, project_root = root}); append(&library.saves, Authoring_Player_Save{content = inspection_v1.artifact.identity, save_id = "player", save_root = saves_root}); assert(authoring_service_scan_library(library_root, &library).ok && len(library.installed) == 2 && len(library.sources) == 1 && len(library.saves) == 1); assert(lifecycle_test_read(save_path) == "PLAYER PROGRESS")

	// A real inspected package with a future capability reaches the resolution
	// service and is rejected as incompatible before install.
	incompatible_path := fmt.tprintf(
		"%s/incompatible.interactive-story",
		root,
	); incompatible_export := packaging_closure_export(&config, root, "3.0.0", incompatible_path, true); assert(incompatible_export.ok); incompatible: Authoring_Package_Inspection; assert(authoring_service_inspect(&config, incompatible_path, .Story, &incompatible).ok && len(incompatible.capabilities) == 1); assert(!authoring_service_apply_resolution(&incompatible, &library, []string{}) && incompatible.compatibility == .Incompatible && !authoring_package_inspection_installable(&incompatible)); rejected := authoring_service_install(&config, {inspection = &incompatible, package_path = incompatible_path, library_root = library_root, decision = .Coexist}); assert(!rejected.ok)

	// A real campaign bundle can carry a case whose expansion remains an exact
	// external dependency. Inspection exposes both the missing dependency and
	// acknowledged incomplete proof; install remains blocked.
	external_case := fmt.tprintf(
		"%s/external-case.interactive-story",
		root,
	); external_export := packaging_closure_export(&config, root, "4.0.0", external_case, false, true); assert(external_export.ok)
	campaign_text := "version=\"MysteryCampaign v2\"\nid=\"closure_campaign\"\ntitle=\"Closure Campaign\"\ncreator=\"Closure\"\ndescription=\"External dependency fixture\"\ncontent_version=\"1.0.0\"\n[[conditions]]\nkind=0\n[[cases]]\nid=\"packaging_closure\"\ntitle=\"Packaging Closure\"\nstory_path=\"story.toml\"\nlevel_path=\"level.toml\"\ncontent_version=\"4.0.0\"\ncondition_root=0\nrequired=true\noptional=false\n"; assert(authoring_atomic_write(fmt.tprintf("%s/campaign.toml", root), campaign_text)); campaign_config := fmt.tprintf("%s/campaign.package.json", root); assert(authoring_atomic_write(campaign_config, "{\"campaign\":\"campaign.toml\",\"author\":\"Closure\",\"description\":\"External dependency fixture\",\"content_version\":\"1.0.0\",\"cases\":[\"external-case.interactive-story\"]}")); campaign_path := fmt.tprintf("%s/external-dependency.mystery-campaign", root); bundle := Authoring_Campaign_Bundle_Rule{}; defer delete(bundle.cases); append(&bundle.cases, Authoring_Campaign_Bundle_Case{id = "packaging_closure", version = "4.0.0", package_path = external_case}); campaign_export := authoring_service_export(&config, {kind = .Campaign, source_root = root, config_path = campaign_config, output_path = campaign_path, campaign_rule = &bundle}); assert(campaign_export.ok)
	campaign_inspection: Authoring_Package_Inspection; assert(authoring_service_inspect(&config, campaign_path, .Campaign, &campaign_inspection).ok && campaign_inspection.case_count == 1 && len(campaign_inspection.dependencies) == 1 && campaign_inspection.dependencies[0].id == "closure_external" && len(campaign_inspection.compatibility_warnings) > 0); assert(!authoring_service_apply_resolution(&campaign_inspection, &library, []string{}) && campaign_inspection.compatibility == .Missing_Dependency && !authoring_package_inspection_installable(&campaign_inspection)); campaign_install := authoring_service_install(&config, {inspection = &campaign_inspection, package_path = campaign_path, library_root = library_root, decision = .Coexist}); assert(!campaign_install.ok); authoring_package_inspection_destroy(&campaign_inspection)
	external_rule := Authoring_Campaign_Bundle_Rule {
		allow_external_dependencies = true,
	}; defer delete(
		external_rule.cases,
	); append(&external_rule.cases, Authoring_Campaign_Bundle_Case{id = "remote_case", version = "7.0.0", external = true}); assert(authoring_service_validate_campaign_rule(&external_rule).ok); external_rule.allow_external_dependencies = false; assert(!authoring_service_validate_campaign_rule(&external_rule).ok)
	// Exercise the external-case branch as a real archive. The case bytes are
	// absent from the campaign, inspection exposes an exact required pin,
	// installation blocks until that story version is installed, and the
	// installed campaign runtime resolves to the separately installed case.
	external_only_config := fmt.tprintf(
		"%s/external-only.package.json",
		root,
	); assert(authoring_atomic_write(external_only_config, "{\"campaign\":\"campaign.toml\",\"author\":\"Closure\",\"description\":\"External case only\",\"content_version\":\"1.0.0\",\"cases\":[{\"id\":\"packaging_closure\",\"content_version\":\"4.0.0\",\"external\":true}]}")); external_only_path := fmt.tprintf("%s/external-only.mystery-campaign", root); external_only_rule := Authoring_Campaign_Bundle_Rule {
		allow_external_dependencies = true,
	}; defer delete(
		external_only_rule.cases,
	); append(&external_only_rule.cases, Authoring_Campaign_Bundle_Case{id = "packaging_closure", version = "4.0.0", external = true}); external_only_export := authoring_service_export(&config, {kind = .Campaign, source_root = root, config_path = external_only_config, output_path = external_only_path, campaign_rule = &external_only_rule}); assert(external_only_export.ok)
	external_only_inspection: Authoring_Package_Inspection; defer authoring_package_inspection_destroy(&external_only_inspection); external_only_checked := authoring_service_inspect(&config, external_only_path, .Campaign, &external_only_inspection); if !(external_only_checked.ok && external_only_inspection.case_count == 1 && len(external_only_inspection.dependencies) == 1 && external_only_inspection.dependencies[0].id == "packaging_closure" && external_only_inspection.dependencies[0].version == "4.0.0" && len(external_only_inspection.files) == 0) do fmt.println("EXTERNAL ONLY INSPECTION · ", external_only_checked, " · cases ", external_only_inspection.case_count, " · deps ", len(external_only_inspection.dependencies), " · files ", len(external_only_inspection.files)); assert(external_only_checked.ok && external_only_inspection.case_count == 1 && len(external_only_inspection.dependencies) == 1 && external_only_inspection.dependencies[0].id == "packaging_closure" && external_only_inspection.dependencies[0].version == "4.0.0" && len(external_only_inspection.files) == 0)
	assert(
		!authoring_service_apply_resolution(&external_only_inspection, &library, []string{}) &&
		!authoring_package_inspection_installable(&external_only_inspection),
	); external_case_clean := fmt.tprintf("%s/external-case-clean.interactive-story", root); assert(packaging_closure_export(&config, root, "4.0.0", external_case_clean).ok); external_case_inspection: Authoring_Package_Inspection; defer authoring_package_inspection_destroy(&external_case_inspection); assert(authoring_service_inspect(&config, external_case_clean, .Story, &external_case_inspection).ok); installed_external_case := authoring_service_install(&config, {inspection = &external_case_inspection, package_path = external_case_clean, library_root = library_root, decision = .Coexist}); assert(installed_external_case.ok); assert(authoring_service_scan_library(library_root, &library).ok && authoring_service_apply_resolution(&external_only_inspection, &library, []string{})); external_only_install := authoring_service_install(&config, {inspection = &external_only_inspection, package_path = external_only_path, library_root = library_root, decision = .Coexist}); if !external_only_install.ok do fmt.println("EXTERNAL CAMPAIGN INSTALL · ", external_only_install.message); assert(external_only_install.ok && os.is_file(fmt.tprintf("%s/runtime/campaign.toml", external_only_install.installed.install_root))); runtime_campaign := lifecycle_test_read(fmt.tprintf("%s/runtime/campaign.toml", external_only_install.installed.install_root)); assert(strings.contains(runtime_campaign, installed_external_case.installed.install_root))
	assert(
		authoring_atomic_write(
			fmt.tprintf("%s/package-incomplete.json", root),
			"{\"author\":\"Closure\",\"description\":\"Incomplete-only fixture\",\"content_version\":\"5.0.0\",\"story\":\"story.toml\",\"level\":\"level.toml\",\"acknowledge_incomplete_validation\":false}",
		),
	); incomplete_result := authoring_service_export(&config, {kind = .Story, source_root = root, config_path = fmt.tprintf("%s/package-incomplete.json", root), output_path = fmt.tprintf("%s/incomplete.interactive-story", root), skip_engine_validation = true}); assert(!incomplete_result.ok && incomplete_result.message != "")

	// Explicit staged wizard gates dependency review, exportable validation,
	// destination choice, and verified artifact identity.
	request := Authoring_Service_Export {
		kind        = .Story,
		source_root = root,
		config_path = fmt.tprintf("%s/package.json", root),
	}; wizard := authoring_export_wizard_begin(
		"Packaging Closure",
		"3.0.0",
		"thumbnail.png",
		1,
		request,
	); assert(authoring_export_wizard_advance(&wizard).ok && wizard.stage == .Dependencies); assert(authoring_export_wizard_advance(&wizard).ok && wizard.stage == .Validation); blocked_validation := authoring_validation_snapshot_init(.Exportable, 1); authoring_validation_add(&blocked_validation, authoring_diagnostic_init(.Packaging, "package", "fixture", "validation", .Blocking, "blocked")); assert(!authoring_export_wizard_advance(&wizard, &blocked_validation).ok && wizard.stage == .Validation); authoring_validation_snapshot_destroy(&blocked_validation); clear_validation := authoring_validation_snapshot_init(.Exportable, 2); for domain in Authoring_Validation_Domain {assert(authoring_validation_touch_domain(&clear_validation, domain, 2)); assert(authoring_validation_mark_domain_valid(&clear_validation, domain, 2))}; assert(authoring_export_wizard_advance(&wizard, &clear_validation).ok && wizard.stage == .Destination && wizard.validation_revision == 2 && wizard.validation_domain_count == len(Authoring_Validation_Domain)); authoring_validation_snapshot_destroy(&clear_validation); assert(!authoring_export_wizard_advance(&wizard, destination = "").ok); assert(authoring_export_wizard_advance(&wizard, destination = incompatible_path).ok && wizard.stage == .Exporting); assert(authoring_export_wizard_advance(&wizard, service_result = &incompatible_export).ok && authoring_export_wizard_ready(&wizard))

	assert(lifecycle_test_read(fmt.tprintf("%s/story.toml", root)) != source_before) // v2/v3 authoring changed source intentionally; installs did not.
	delete(
		library.installed,
	); delete(library.sources); delete(library.saves); delete(library.dependency_edges); authoring_package_inspection_destroy(&inspection_v1); authoring_package_inspection_destroy(&inspection_v2); authoring_package_inspection_destroy(&incompatible)
}
