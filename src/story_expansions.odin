package main

import "core:fmt"
import "core:os"
import "core:strings"

story_resolved_environment_destroy :: proc(environment: ^Resolved_Story_Environment) {delete(
		environment.expansions,
	)
	environment^ = {}}

story_expansion_registry_path :: proc() -> (string, bool) {data_dir, data_error :=
		os.user_data_dir(context.temp_allocator)
	if data_error != nil do return "", false
	path, path_error := os.join_path(
		[]string{data_dir, APP_STORAGE_NAME, "Expansions", "catalog-registry.toml"},
		context.allocator,
	)
	return path, path_error == nil}

story_resolve_environment :: proc(project: ^Story_Project) -> Validation {
	if project == nil do return {false, "story project is required"}
	story_resolved_environment_destroy(&project.resolved_environment)
	if len(project.expansion_requirements) == 0 do return {true, "STORY HAS NO EXPANSION DEPENDENCIES"}
	path, path_ok := story_expansion_registry_path(

	); if !path_ok || !os.is_file(path) {for requirement in project.expansion_requirements do if !requirement.optional do return {false, fmt.tprintf("required expansion is not installed and enabled: %s@%s", requirement.id, requirement.version)}; return {true, "OPTIONAL EXPANSIONS OMITTED"}}
	cpath, clone_error := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if clone_error != nil do return {false, "invalid expansion registry path"}; parsed := toml_parse_file_ex(cpath); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "expansion registry", &parsed)
	for requirement in project.expansion_requirements {found := false; for table in toml_tables(parsed.toptab, "expansions") {id := toml_case_string(table, "id"); version := toml_case_string(table, "version"); if id != requirement.id || version != requirement.version do continue; namespace := toml_case_string(table, "namespace"); content_hash := toml_case_string(table, "content_hash"); if namespace == "" || content_hash == "" do return {false, "resolved expansion identity is incomplete"}; append(&project.resolved_environment.expansions, Resolved_Story_Expansion{id = id, namespace = namespace, version = version, content_hash = content_hash, enabled = true}); found = true; break}; if !found && !requirement.optional do return {false, fmt.tprintf("required expansion is not installed and enabled: %s@%s", requirement.id, requirement.version)}}
	hash: u64 = 1469598103934665603; for item in project.resolved_environment.expansions {record := story_hash_text(story_record_hash(), item.id); record = story_hash_text(record, item.namespace); record = story_hash_text(record, item.version); record = story_hash_text(record, item.content_hash); hash ~= record}; project.resolved_environment.identity = hash
	return {true, "STORY EXPANSIONS RESOLVED"}
}
