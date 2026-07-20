package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"

Authoring_Library_Service_Config :: struct {
	python, repository_root, story_tool, campaign_tool, expansion_tool: string,
}
Authoring_Service_Progress :: struct {
	phase:                        string,
	completed, total:             int,
	bytes_completed, bytes_total: u64,
}
Authoring_Service_Result :: struct {
	ok:        bool,
	message:   string,
	artifact:  Authoring_Portable_Package,
	installed: Authoring_Installed_Version,
	progress:  Authoring_Service_Progress,
}
Authoring_Service_Export :: struct {
	kind:                                  Authoring_Artifact_Kind,
	source_root, config_path, output_path: string,
	skip_engine_validation:                bool,
	asset_plan:                            ^Project_Asset_Stage_Plan,
	campaign_rule:                         ^Authoring_Campaign_Bundle_Rule,
}
Authoring_Service_Install :: struct {
	inspection:                                ^Authoring_Package_Inspection,
	package_path, library_root, editable_root: string,
	decision:                                  Authoring_Import_Decision,
}
Authoring_Service_Resolution :: struct {
	compatible:                                      bool,
	missing_dependencies, incompatible_capabilities: [dynamic]string,
}
Authoring_Campaign_Bundle_Case :: struct {
	id, version, package_path: string,
	external:                  bool,
}
Authoring_Campaign_Bundle_Rule :: struct {
	cases:                       [dynamic]Authoring_Campaign_Bundle_Case,
	allow_external_dependencies: bool,
}

authoring_library_service_counter: u64

authoring_library_service_default_config :: proc(
	root: string,
) -> Authoring_Library_Service_Config {return{
		python = "python3",
		repository_root = root,
		story_tool = "tools/interactive_story_package.py",
		campaign_tool = "tools/campaign_package.py",
		expansion_tool = "tools/expansion_package.py",
	}}

authoring_service_package_tool :: proc(
	config: ^Authoring_Library_Service_Config,
	kind: Authoring_Artifact_Kind,
) -> string {
	switch kind {
	case .Story:
		return config.story_tool
	case .Campaign:
		return config.campaign_tool
	case .Expansion:
		return config.expansion_tool
	}
	return ""
}

authoring_service_tool_path :: proc(
	config: ^Authoring_Library_Service_Config,
	tool: string,
) -> string {if filepath.is_abs(tool) do return tool; joined, error := filepath.join(
		[]string{config.repository_root, tool},
		context.allocator,
	)
	if error != nil do return tool
	return joined}

authoring_service_run :: proc(
	config: ^Authoring_Library_Service_Config,
	args: []string,
) -> (
	bool,
	string,
) {
	if config == nil || len(args) == 0 do return false, "service command is empty"
	state, out, err, run_error := os.process_exec(
		{working_dir = config.repository_root, command = args},
		context.allocator,
	); defer delete(out); defer delete(err)
	if run_error != nil do return false, "could not start package service"
	message := strings.trim_space(
		string(out),
	); if !state.success || state.exit_code != 0 {message = strings.trim_space(string(err)); if message == "" do message = "package service failed"; return false, strings.clone(message)}
	return true, strings.clone(message)
}

authoring_json_string :: proc(text, key: string) -> string {
	needle := fmt.tprintf(
		"\"%s\"",
		key,
	); at := strings.index(text, needle); if at < 0 do return ""; at += len(needle); for at < len(text) && text[at] != ':' do at += 1; at += 1; for at < len(text) && (text[at] == ' ' || text[at] == '\n' || text[at] == '\r' || text[at] == '\t') do at += 1; if at >= len(text) || text[at] != '\"' do return ""; at += 1; result := ""; for at < len(text) {c := text[at]; if c == '\"' do break; if c == '\\' && at + 1 < len(text) {at += 1; c = text[at]; if c == 'n' do result = fmt.tprintf("%s\n", result)
			else do result = fmt.tprintf("%s%c", result, c)} else do result = fmt.tprintf("%s%c", result, c); at += 1}; return result
}

// Inspect output may contain nested case manifests before the campaign's own
// content_version. The campaign tool emits the top-level field last, so retain
// the final occurrence rather than accidentally identifying the first case.
authoring_json_string_last :: proc(text, key: string) -> string {
	needle := fmt.tprintf("\"%s\"", key); remaining := text; result := ""
	for {at := strings.index(remaining, needle); if at < 0 do break; value := authoring_json_string(remaining[at:], key); if value != "" do result = value; remaining = remaining[at + len(needle):]}
	return result
}

authoring_json_int :: proc(text, key: string) -> int {needle := fmt.tprintf("\"%s\"", key); at :=
		strings.index(text, needle)
	if at < 0 do return 0
	at += len(needle)
	for at < len(text) && text[at] != ':' do at += 1
	at += 1
	for at < len(text) && (text[at] == ' ' || text[at] == '\n') do at += 1
	end := at
	for end < len(text) && text[end] >= '0' && text[end] <= '9' do end += 1
	value, ok := strconv.parse_i64(text[at:end])
	return ok ? int(value) : 0}
authoring_json_bool :: proc(text, key: string, default := false) -> bool {needle := fmt.tprintf(
		"\"%s\"",
		key,
	)
	at := strings.index(text, needle)
	if at < 0 do return default
	at += len(needle)
	for at < len(text) && text[at] != ':' do at += 1
	at += 1
	for at < len(text) && (text[at] == ' ' || text[at] == '\n' || text[at] == '\r' || text[at] == '\t') do at += 1
	return strings.has_prefix(text[at:], "true")}

authoring_json_section :: proc(text, key: string, opening, closing: u8) -> string {
	needle := fmt.tprintf(
		"\"%s\"",
		key,
	); at := strings.index(text, needle); if at < 0 do return ""; at += len(needle); for at < len(text) && text[at] != ':' do at += 1; for at < len(text) && text[at] != opening do at += 1; if at >= len(text) do return ""
	start := at; depth := 0; quoted, escaped := false, false
	for at < len(text) {c := text[at]; if quoted {if escaped do escaped = false
			else if c == '\\' do escaped = true
			else if c == '\"' do quoted = false} else if c == '\"' do quoted = true
		else if c == opening do depth += 1
		else if c == closing {depth -= 1; if depth == 0 do return text[start:at + 1]}; at += 1}; return ""
}
authoring_json_count_key :: proc(text, key: string) -> int {needle := fmt.tprintf("\"%s\"", key)
	remaining := text
	count := 0
	for {at := strings.index(remaining, needle); if at < 0 do break; count += 1
		remaining = remaining[at + len(needle):]}
	return count}
authoring_package_path_is_asset :: proc(path: string) -> bool {lower := strings.to_lower(path)
	return(
		strings.has_prefix(lower, "assets/") ||
		strings.has_suffix(lower, ".png") ||
		strings.has_suffix(lower, ".jpg") ||
		strings.has_suffix(lower, ".jpeg") ||
		strings.has_suffix(lower, ".glb") ||
		strings.has_suffix(lower, ".gltf") ||
		strings.has_suffix(lower, ".ogg") ||
		strings.has_suffix(lower, ".wav") \
	)}

authoring_inspection_parse_capabilities :: proc(
	json: string,
	inspection: ^Authoring_Package_Inspection,
) {
	section := authoring_json_section(json, "capabilities", '[', ']'); if section == "" do return
	if strings.contains(
		section,
		"{",
	) {remaining := section; for {at := strings.index(remaining, "\"id\""); if at < 0 do break; id := authoring_json_string(remaining[at:], "id"); version := authoring_json_string(remaining[at:], "version"); if id != "" do append(&inspection.capabilities, version != "" ? fmt.tprintf("%s@%s", id, version) : id); remaining = remaining[at + 4:]}} else {at := 0; for at < len(section) {for at < len(section) && section[at] != '\"' do at += 1; if at >= len(section) do break; start := at + 1; at = start; for at < len(section) && section[at] != '\"' do at += 1; if at > start do append(&inspection.capabilities, strings.clone(section[start:at])); at += 1}}
}
authoring_inspection_parse_dependencies :: proc(
	json: string,
	inspection: ^Authoring_Package_Inspection,
) {section := authoring_json_section(json, "expansions", '[', ']'); if section == "" do return
	remaining := section
	for {at := strings.index(remaining, "\"id\""); if at < 0 do break; fragment := remaining[at:]
		id := authoring_json_string(fragment, "id")
		version := authoring_json_string(fragment, "version")
		if id != "" do append(&inspection.dependencies, Authoring_Package_Dependency{id, version, authoring_json_bool(fragment, "optional")})
		remaining = remaining[at + 4:]}}
authoring_inspection_parse_files :: proc(
	json: string,
	inspection: ^Authoring_Package_Inspection,
) {section := authoring_json_section(json, "files", '[', ']'); if section == "" do return
	remaining := section
	for {at := strings.index(remaining, "\"path\""); if at < 0 do break; fragment := remaining[at:]
		path := authoring_json_string(fragment, "path")
		size := authoring_json_int(fragment, "size")
		sha := authoring_json_string(fragment, "sha256")
		if path !=
		   "" {asset := authoring_package_path_is_asset(path); append(&inspection.files, Authoring_Package_File{path, sha, u64(max(size, 0)), asset})
			inspection.total_bytes += u64(max(size, 0))
			if asset do inspection.asset_count += 1}
		remaining = remaining[at + 6:]}}
authoring_inspection_parse_cases :: proc(json: string, inspection: ^Authoring_Package_Inspection) {
	section := authoring_json_section(json, "cases", '[', ']'); if section == "" do return
	remaining := section
	for {
		at := strings.index(remaining, "\"story_id\""); if at < 0 do break
		start := strings.last_index(remaining[:at], "{"); if start < 0 do break
		close := strings.index(remaining[at:], "}"); if close < 0 do break
		fragment := remaining[start:at + close + 1]
		id := authoring_json_string(
			fragment,
			"story_id",
		); version := authoring_json_string(fragment, "content_version")
		if id !=
		   "" {append(&inspection.cases, Authoring_Content_Identity{id, version, .Story}); inspection.case_count += 1; path := authoring_json_string(fragment, "path"); size := authoring_json_int(fragment, "size"); sha := authoring_json_string(fragment, "sha256"); if path != "" {append(&inspection.files, Authoring_Package_File{path, sha, u64(max(size, 0)), false}); inspection.total_bytes += u64(max(size, 0))} else if authoring_json_bool(fragment, "external") do append(&inspection.dependencies, Authoring_Package_Dependency{id, version, false})}
		remaining = remaining[at + close + 1:]
	}
}

authoring_service_inspect :: proc(
	config: ^Authoring_Library_Service_Config,
	path: string,
	kind: Authoring_Artifact_Kind,
	out: ^Authoring_Package_Inspection,
) -> Validation {
	if out == nil || !os.is_file(path) do return {false, "package file and inspection destination are required"}; tool := authoring_service_tool_path(config, authoring_service_package_tool(config, kind)); ok, json := authoring_service_run(config, []string{config.python, tool, "inspect", path}); defer delete(json); if !ok do return {false, strings.clone(json)}
	id_key := "story_id"; version_key := "content_version"; if kind == .Campaign do id_key = "campaign_id"; if kind == .Expansion {id_key = "expansion_id"; version_key = "version"}; id := authoring_json_string(json, id_key); version := kind == .Campaign ? authoring_json_string_last(json, version_key) : authoring_json_string(json, version_key); if id == "" || version == "" do return {false, "package inspection did not return an identity"}; hash, hashed := project_asset_sha256_file(path); if !hashed.ok do return hashed
	authoring_package_inspection_destroy(out); out.artifact = {
		identity       = {id, version, kind},
		package_path   = strings.clone(path),
		artifact_hash  = hash,
		format         = authoring_json_string(json, "format"),
		format_version = fmt.tprintf("%d", authoring_json_int(json, "format_version")),
	}; out.title = authoring_json_string(
		json,
		"title",
	); out.author = authoring_json_string(json, "author"); if out.author == "" do out.author = authoring_json_string(json, "creator"); out.description = authoring_json_string(json, "description"); out.thumbnail_path = authoring_json_string(json, "thumbnail"); if out.thumbnail_path == "" do out.thumbnail_path = authoring_json_string(authoring_json_section(json, "thumbnail", '{', '}'), "path"); out.integrity = .Valid; out.compatibility = .Compatible; out.manifest_json = strings.clone(json); out.integrity_summary = fmt.tprintf("SHA-256 %s · %d verified integrity records", hash, authoring_json_count_key(json, "sha256"))
	authoring_inspection_parse_capabilities(
		json,
		out,
	); authoring_inspection_parse_dependencies(json, out); authoring_inspection_parse_files(json, out); authoring_inspection_parse_cases(json, out)
	if kind == .Story {out.case_count = 1; append(&out.cases, out.artifact.identity)}
	if !authoring_json_bool(
		authoring_json_section(json, "validation", '{', '}'),
		"required_invariants_proven",
		true,
	) {warning := "package acknowledges incomplete invariant proof"; authoring_package_warning_add(out, warning, .Creator_Only); append(&out.diagnostics, authoring_diagnostic_init(.Packaging, "package", id, "validation.required_invariants_proven", .Warning, warning))}
	if out.thumbnail_path ==
	   "" {warning := "package does not provide a thumbnail"; authoring_package_warning_add(out, warning, .Player_Safe); append(&out.diagnostics, authoring_diagnostic_init(.Packaging, "package", id, "thumbnail", .Info, warning))}
	authoring_package_inspection_finalize(out); return {true, "PACKAGE INSPECTED AND VERIFIED"}
}

authoring_semver_part :: proc(value: string, index: int) -> int {parts := strings.split(
		value,
		".",
		context.temp_allocator,
	)
	if index >= len(parts) do return 0
	end := 0
	for end < len(parts[index]) && parts[index][end] >= '0' && parts[index][end] <= '9' do end += 1
	if end == 0 do return 0
	number, ok := strconv.parse_i64(parts[index][:end])
	return ok ? int(number) : 0}
authoring_semver_compare :: proc(a, b: string) -> int {for 	i in 0 ..< 3 {av, bv := authoring_semver_part(a, i), authoring_semver_part(b, i); if av < bv do return -1
		if av > bv do return 1}
	if a == b do return 0
	return strings.compare(a, b)}

authoring_service_resolve :: proc(
	inspection: ^Authoring_Package_Inspection,
	library: ^Authoring_Library,
	supported_capabilities: []string,
) -> Authoring_Service_Resolution {
	result := Authoring_Service_Resolution {
		compatible = true,
	}; if inspection == nil {result.compatible = false; return result}
	for dependency in inspection.dependencies {found := false; for installed in library.installed do if installed.identity.id == dependency.id && authoring_semver_compare(installed.identity.content_version, dependency.version) >= 0 {found = true; break}; if !found && !dependency.optional {append(&result.missing_dependencies, dependency.id); result.compatible = false}}
	for capability in inspection.capabilities {found := false; for supported in supported_capabilities do if supported == capability {found = true; break}; if !found {append(&result.incompatible_capabilities, capability); result.compatible = false}}
	return result
}
authoring_service_resolution_destroy :: proc(result: ^Authoring_Service_Resolution) {delete(
		result.missing_dependencies,
	)
	delete(result.incompatible_capabilities)
	result^ = {}}
authoring_service_apply_resolution :: proc(
	inspection: ^Authoring_Package_Inspection,
	library: ^Authoring_Library,
	supported_capabilities: []string,
) -> bool {
	if inspection == nil || library == nil do return false
	// Resolution is repeatable: installing a dependency and resolving again
	// must remove stale compatibility blockers while preserving independent
	// package warnings such as thumbnail or creator-only validation notices.
	for i := len(inspection.diagnostics) - 1; i >= 0; i -= 1 do if inspection.diagnostics[i].domain == .Compatibility do ordered_remove(&inspection.diagnostics, i)
	for i := len(inspection.compatibility_warnings) - 1;
	    i >= 0;
	    i -= 1 {message := inspection.compatibility_warnings[i]; if strings.has_prefix(message, "missing required dependency:") || strings.has_prefix(message, "unsupported required capability:") do ordered_remove(&inspection.compatibility_warnings, i)}
	for i := len(inspection.typed_warnings) - 1;
	    i >= 0;
	    i -= 1 {message := inspection.typed_warnings[i].message; if strings.has_prefix(message, "missing required dependency:") || strings.has_prefix(message, "unsupported required capability:") do ordered_remove(&inspection.typed_warnings, i)}
	resolved := authoring_service_resolve(
		inspection,
		library,
		supported_capabilities,
	); defer authoring_service_resolution_destroy(&resolved)
	inspection.compatibility = .Compatible
	if len(resolved.missing_dependencies) > 0 {
		inspection.compatibility = .Missing_Dependency
		for id in resolved.missing_dependencies {message := fmt.tprintf("missing required dependency: %s", id); authoring_package_warning_add(inspection, message, .Player_Safe); append(&inspection.diagnostics, authoring_diagnostic_init(.Compatibility, "package", inspection.artifact.identity.id, "dependencies", .Blocking, message))}
	}
	if len(resolved.incompatible_capabilities) > 0 {
		if inspection.compatibility == .Compatible do inspection.compatibility = .Incompatible
		for capability in resolved.incompatible_capabilities {message := fmt.tprintf("unsupported required capability: %s", capability); authoring_package_warning_add(inspection, message, .Player_Safe); append(&inspection.diagnostics, authoring_diagnostic_init(.Compatibility, "package", inspection.artifact.identity.id, "capabilities", .Blocking, message))}
	}
	return resolved.compatible
}

// Rebuild the installed-version index from the physical library. Source
// projects and player saves deliberately remain untouched and live elsewhere.
authoring_service_scan_library :: proc(root: string, library: ^Authoring_Library) -> Validation {
	if library == nil || root == "" || !os.is_dir(root) do return {false, "installed library root is missing"}
	delete(
		library.installed,
	); library.installed = {}; delete(library.dependency_edges); library.dependency_edges = {}
	ids, ids_error := os.read_directory_by_path(
		root,
		-1,
		context.temp_allocator,
	); if ids_error != nil do return {false, "installed library could not be read"}
	for id_entry in ids {if id_entry.type != .Directory do continue
		id_root, join_error := os.join_path({root, id_entry.name}, context.temp_allocator)
		if join_error != nil do continue
		versions, versions_error := os.read_directory_by_path(id_root, -1, context.temp_allocator)
		if versions_error != nil do continue
		for version_entry in versions {if version_entry.type != .Directory do continue
			install_root, error := os.join_path({id_root, version_entry.name}, context.allocator)
			if error != nil do continue
			manifest := ""
			kind := Authoring_Artifact_Kind.Story
			names := [3]string {
				"interactive-story-manifest.json",
				"campaign-manifest.json",
				"expansion-manifest.json",
			}
			for name, index in names {candidate, e := os.join_path(
					{install_root, name},
					context.temp_allocator,
				)
				if e == nil &&
				   os.is_file(
					   candidate,
				   ) {manifest = candidate; kind = Authoring_Artifact_Kind(index)
					break}}
			if manifest == "" {delete(install_root); continue}
			bytes, read_error := os.read_entire_file_from_path(manifest, context.temp_allocator)
			if read_error != nil {delete(install_root); continue}
			json := string(bytes)
			id_key := "story_id"
			version_key := "content_version"
			if kind == .Campaign do id_key = "campaign_id"
			if kind == .Expansion {id_key = "expansion_id"; version_key = "version"}
			id := authoring_json_string(json, id_key)
			version :=
				kind == .Campaign ? authoring_json_string_last(json, version_key) : authoring_json_string(json, version_key)
			if id == "" do id = id_entry.name
			if version == "" do version = version_entry.name
			identity := Authoring_Content_Identity{id, version, kind}
			append(
				&library.installed,
				Authoring_Installed_Version {
					identity = identity,
					install_root = install_root,
					active = true,
				},
			)
			parsed := Authoring_Package_Inspection{}
			authoring_inspection_parse_dependencies(json, &parsed)
			authoring_inspection_parse_cases(json, &parsed)
			for dependency in parsed.dependencies do append(&library.dependency_edges, Authoring_Library_Dependency_Edge{dependent = identity, requirement = {dependency.id, dependency.version, .Expansion}, optional = dependency.optional})
			for case_identity in parsed.cases do append(&library.dependency_edges, Authoring_Library_Dependency_Edge{dependent = identity, requirement = case_identity})
			authoring_package_inspection_destroy(&parsed)
		}
	}
	library.revision += 1; return {true, fmt.tprintf("INSTALLED LIBRARY REFRESHED · %d VERSIONS", len(library.installed))}
}

authoring_service_unique_path :: proc(
	parent, label: string,
) -> string {authoring_library_service_counter += 1; joined, error := filepath.join(
		[]string {
			parent,
			fmt.tprintf(".%s-%d-%d", label, os.get_pid(), authoring_library_service_counter),
		},
		context.allocator,
	)
	if error != nil do return ""
	return joined}

authoring_service_stage_assets :: proc(
	plan: ^Project_Asset_Stage_Plan,
	destination: string,
) -> Validation {
	if plan == nil do return {true, "NO PROJECT ASSETS TO STAGE"}; if !plan.allowed do return {false, "asset staging plan is blocked"}; if destination == "" do return {false, "asset staging destination is required"}
	staging := authoring_service_unique_path(
		destination,
		"asset-stage",
	); if staging == "" || os.make_directory_all(staging) != nil do return {false, "could not create asset staging directory"}; committed := false; defer if !committed do _ = os.remove_all(staging)
	for item in plan.items {target, error := filepath.join([]string{staging, item.package_path}, context.allocator); if error != nil || !project_asset_path_within_root(staging, target) do return {false, "asset package path escapes staging root"}; parent, _ := filepath.split(target); if os.make_directory_all(parent) != nil || os.copy_file(target, item.source_path) != nil do return {false, "could not stage package asset"}; hash, checked := project_asset_sha256_file(target); if !checked.ok || hash != item.sha256 do return {false, "staged asset integrity check failed"}}
	manifest, error := filepath.join(
		[]string{staging, "asset-attribution.toml"},
		context.allocator,
	); if error != nil || os.write_entire_file(manifest, transmute([]byte)plan.attribution_manifest) != nil do return {false, "could not stage asset attribution manifest"}
	final, final_error := filepath.join(
		[]string{destination, "project-assets"},
		context.allocator,
	); if final_error != nil do return {false, "could not resolve asset destination"}; if os.exists(final) do return {false, "asset staging destination already exists"}; if os.rename(staging, final) != nil do return {false, "could not commit staged assets"}; committed = true; return {true, "PROJECT ASSETS STAGED"}
}

// Materialize the verified package view inside the source root before invoking
// the package tool. The exporter only accepts paths below --root, so staging
// beside the finished archive cannot make assets or attribution part of it.
authoring_service_materialize_assets :: proc(
	plan: ^Project_Asset_Stage_Plan,
	source_root: string,
) -> Validation {
	if plan == nil do return {true, "NO PROJECT ASSETS TO MATERIALIZE"}
	if !plan.allowed do return {false, "asset staging plan is blocked"}
	if source_root == "" || !os.is_dir(source_root) do return {false, "asset package source root is missing"}
	for item in plan.items {
		target, error := filepath.join([]string{source_root, item.package_path}, context.allocator)
		if error != nil || !project_asset_path_within_root(source_root, target) do return {false, "asset package path escapes source root"}
		parent, _ := filepath.split(target)
		if !os.is_dir(parent) && os.make_directory_all(parent) != nil do return {false, "could not create package asset directory"}
		if os.is_file(target) {
			hash, checked := project_asset_sha256_file(target)
			if checked.ok && hash == item.sha256 do continue
		}
		temporary := fmt.tprintf("%s.package-new", target)
		if os.copy_file(temporary, item.source_path) != nil do return {false, "could not materialize package asset"}
		hash, checked := project_asset_sha256_file(temporary)
		if !checked.ok ||
		   hash !=
			   item.sha256 {_ = os.remove(temporary); return {false, "materialized asset integrity check failed"}}
		if os.exists(target) do _ = os.remove(target)
		if os.rename(temporary, target) !=
		   nil {_ = os.remove(temporary); return {false, "could not commit package asset"}}
	}
	manifest, error := filepath.join(
		[]string{source_root, "assets", "asset-attribution.toml"},
		context.allocator,
	)
	if error != nil || !project_asset_path_within_root(source_root, manifest) do return {false, "asset attribution path is unsafe"}
	if !os.is_dir(os.dir(manifest)) && os.make_directory_all(os.dir(manifest)) != nil do return {false, "could not create asset attribution directory"}
	if !authoring_atomic_write(manifest, plan.attribution_manifest) do return {false, "could not materialize asset attribution manifest"}
	return {true, "PROJECT ASSETS MATERIALIZED FOR EXPORT"}
}

authoring_service_export :: proc(
	config: ^Authoring_Library_Service_Config,
	request: Authoring_Service_Export,
) -> Authoring_Service_Result {
	result := Authoring_Service_Result {
		progress = {phase = "validating", total = 3},
	}; if request.kind ==
	   .Campaign {rule := authoring_service_validate_campaign_rule(request.campaign_rule); if !rule.ok {result.message = rule.message; return result}}; source_root := request.source_root; if source_root == "" do source_root = os.dir(request.config_path); if request.asset_plan != nil {staged := authoring_service_materialize_assets(request.asset_plan, source_root); if !staged.ok {result.message = staged.message; return result}}; tool := authoring_service_tool_path(config, authoring_service_package_tool(config, request.kind)); args := make([dynamic]string, 0, 9); defer delete(args); append(&args, config.python, tool, "export", request.output_path, "--config", request.config_path); if request.kind == .Story {append(&args, "--root", source_root); if request.skip_engine_validation do append(&args, "--skip-engine-validation")}; result.progress.completed = 1; ok, message := authoring_service_run(config, args[:]); if !ok {result.message = message; return result}; delete(message); result.progress.phase = "inspecting"; result.progress.completed = 2; inspection: Authoring_Package_Inspection; checked := authoring_service_inspect(config, request.output_path, request.kind, &inspection); if !checked.ok {result.message = checked.message; return result}; result.artifact = inspection.artifact; inspection.artifact = {}; authoring_package_inspection_destroy(&inspection)
	result.ok = true; result.message = "PACKAGE EXPORTED AND VERIFIED"; result.progress = {
		phase     = "complete",
		completed = 3,
		total     = 3,
	}; return result
}

authoring_service_identity_root :: proc(
	library_root: string,
	identity: Authoring_Content_Identity,
) -> string {joined, error := filepath.join(
		[]string{library_root, identity.id, identity.content_version},
		context.allocator,
	)
	if error != nil do return ""
	return joined}

authoring_service_install :: proc(
	config: ^Authoring_Library_Service_Config,
	request: Authoring_Service_Install,
) -> Authoring_Service_Result {
	result := Authoring_Service_Result {
		progress = {phase = "planning", total = 3},
	}; if request.inspection == nil ||
	   !authoring_package_inspection_installable(
			   request.inspection,
		   ) {result.message = "package is not installable"; return result}; identity := request.inspection.artifact.identity; destination := authoring_service_identity_root(request.library_root, identity); if destination == "" || !project_asset_path_within_root(request.library_root, destination) {result.message = "unsafe install destination"; return result}; exists := os.exists(destination)
	if request.decision == .Coexist &&
	   exists {result.message = "exact package version is already installed"; return result}; if request.decision == .Upgrade {if exists {result.message = "upgrade requires a distinct content version"; return result}; identity_parent, _ := filepath.split(destination); if !os.is_dir(identity_parent) {result.message = "upgrade requires a previously installed version"; return result}}; if request.decision == .Replace && !exists {result.message = "replace requires an installed exact version"; return result}
	backup := ""; if exists && request.decision == .Replace {backup = authoring_service_unique_path(request.library_root, "install-backup"); if os.rename(destination, backup) != nil {result.message = "could not stage installed version for replacement"; return result}}
	committed, installed_written :=
		false,
		false; defer {if committed {if backup != "" do _ = os.remove_all(backup)} else {if installed_written && os.exists(destination) do _ = os.remove_all(destination); if backup != "" && !os.exists(destination) do _ = os.rename(backup, destination)}}
	result.progress = {
		phase     = "installing",
		completed = 1,
		total     = 3,
	}; tool := authoring_service_tool_path(
		config,
		authoring_service_package_tool(config, identity.kind),
	); args := make([dynamic]string, 0, 9); defer delete(args); command := "install"; if identity.kind == .Campaign do command = "import"; append(&args, config.python, tool, command, request.package_path, "--library", request.library_root); if (identity.kind == .Story || identity.kind == .Expansion) && request.decision == .Replace do append(&args, "--replace"); ok, message := authoring_service_run(config, args[:]); if !ok {result.message = message; return result}; delete(message); destination = authoring_service_identity_root(request.library_root, identity); if !os.exists(destination) {result.message = fmt.tprintf("package service did not create expected identity root %s (%s %s)", destination, identity.id, identity.content_version); return result}; installed_written = true
	if request.decision ==
	   .Editable_Copy {if request.editable_root == "" {result.message = "editable-copy destination is required"; return result}; source := destination; runtime, error := filepath.join([]string{destination, "runtime"}, context.allocator); if error == nil && os.exists(runtime) do source = runtime; if os.exists(request.editable_root) {result.message = "editable-copy destination already exists"; return result}; if os.copy_directory_all(request.editable_root, source) != nil {result.message = "could not create editable source copy"; return result}}
	committed = true; result.ok = true; result.message = "PACKAGE INSTALLED"; result.installed = {
		identity     = identity,
		install_root = destination,
		package_hash = request.inspection.artifact.artifact_hash,
		active       = true,
	}; result.progress = {
		phase     = "complete",
		completed = 3,
		total     = 3,
	}; return result
}

authoring_service_uninstall :: proc(
	library: ^Authoring_Library,
	plan: ^Authoring_Uninstall_Plan,
) -> Authoring_Service_Result {
	result := Authoring_Service_Result {
		progress = {phase = "uninstalling", total = 2},
	}; if library == nil ||
	   plan == nil ||
	   !plan.allowed ||
	   plan.installed_index < 0 ||
	   plan.installed_index >=
		   len(
			   library.installed,
		   ) {result.message = "uninstall plan is blocked or invalid"; return result}; item := library.installed[plan.installed_index]; if item.install_root == "" || !os.exists(item.install_root) {result.message = "installed content root is missing"; return result}; parent, _ := filepath.split(item.install_root); tombstone := authoring_service_unique_path(parent, "uninstall"); if os.rename(item.install_root, tombstone) != nil {result.message = "could not isolate installed content for uninstall"; return result}; result.progress.completed = 1; if os.remove_all(tombstone) != nil {_ = os.rename(tombstone, item.install_root); result.message = "uninstall failed and was rolled back"; return result}; ordered_remove(&library.installed, plan.installed_index); library.revision += 1; result.ok = true; result.message = "CONTENT UNINSTALLED; PLAYER SAVES PRESERVED"; result.progress = {
		phase     = "complete",
		completed = 2,
		total     = 2,
	}; return result
}

authoring_service_validate_campaign_rule :: proc(
	rule: ^Authoring_Campaign_Bundle_Rule,
) -> Validation {if rule == nil || len(rule.cases) == 0 do return {false, "campaign bundle requires case pins"}
	for 	item, index in rule.cases {if item.id == "" || item.version == "" do return {false, "campaign case identity is incomplete"}
		for prior in rule.cases[:index] do if prior.id == item.id && prior.version == item.version do return {false, "campaign bundle contains a duplicate case pin"}
		if item.external {if !rule.allow_external_dependencies do return {false, "campaign external dependencies are not permitted by this bundle rule"}}
		else if !os.is_file(item.package_path) do return {false, "campaign embedded case package is missing"}}
	return{true, "CAMPAIGN BUNDLE RULE SATISFIED"}
}
