package main

Authoring_Artifact_Kind :: enum {
	Story,
	Campaign,
	Expansion,
}
Authoring_Package_Integrity :: enum {
	Unknown,
	Valid,
	Corrupt,
}
Authoring_Package_Compatibility :: enum {
	Compatible,
	Missing_Dependency,
	Incompatible,
	Unsupported_Format,
}
Authoring_Import_Decision :: enum {
	Coexist,
	Upgrade,
	Replace,
	Editable_Copy,
}
Authoring_Package_Warning_Audience :: enum {
	Player_Safe,
	Creator_Only,
}
Authoring_Package_Warning :: struct {
	message:  string,
	audience: Authoring_Package_Warning_Audience,
}

Authoring_Content_Identity :: struct {
	id, content_version: string,
	kind:                Authoring_Artifact_Kind,
}

Authoring_Source_Project :: struct {
	identity:                    Authoring_Content_Identity,
	project_root, manifest_path: string,
}

Authoring_Portable_Package :: struct {
	identity:                    Authoring_Content_Identity,
	package_path, artifact_hash: string,
	format, format_version:      string,
}

Authoring_Installed_Version :: struct {
	identity:                   Authoring_Content_Identity,
	install_root, package_hash: string,
	active:                     bool,
}

Authoring_Player_Save :: struct {
	content:            Authoring_Content_Identity,
	save_id, save_root: string,
}

Authoring_Package_Dependency :: struct {
	id, version: string,
	optional:    bool,
}

Authoring_Package_File :: struct {
	path, sha256: string,
	size:         u64,
	asset:        bool,
}
Authoring_Library_Dependency_Edge :: struct {
	dependent, requirement: Authoring_Content_Identity,
	optional:               bool,
}

Authoring_Package_Inspection :: struct {
	artifact:                                   Authoring_Portable_Package,
	title, author, description, thumbnail_path: string,
	integrity:                                  Authoring_Package_Integrity,
	compatibility:                              Authoring_Package_Compatibility,
	capabilities:                               [dynamic]string,
	dependencies:                               [dynamic]Authoring_Package_Dependency,
	files:                                      [dynamic]Authoring_Package_File,
	cases:                                      [dynamic]Authoring_Content_Identity,
	manifest_json, integrity_summary:           string,
	compatibility_warnings:                     [dynamic]string,
	typed_warnings:                             [dynamic]Authoring_Package_Warning,
	asset_count, case_count:                    int,
	total_bytes:                                u64,
	diagnostics:                                [dynamic]Authoring_Diagnostic,
}

Authoring_Library :: struct {
	installed:        [dynamic]Authoring_Installed_Version,
	sources:          [dynamic]Authoring_Source_Project,
	saves:            [dynamic]Authoring_Player_Save,
	dependency_edges: [dynamic]Authoring_Library_Dependency_Edge,
	revision:         u64,
}

Authoring_Import_Plan :: struct {
	allowed:                               bool,
	decision:                              Authoring_Import_Decision,
	artifact:                              Authoring_Portable_Package,
	existing_index:                        int,
	destination_root:                      string,
	preserve_existing, create_source_copy: bool,
	diagnostics:                           [dynamic]Authoring_Diagnostic,
}

Authoring_Uninstall_Plan :: struct {
	allowed:           bool,
	installed_index:   int,
	dependent_indices: [dynamic]int,
	save_indices:      [dynamic]int,
	diagnostics:       [dynamic]Authoring_Diagnostic,
}

Authoring_Export_Request :: struct {
	source:           Authoring_Source_Project,
	destination_path: string,
	validation:       ^Authoring_Validation_Snapshot,
	assets:           ^Project_Asset_Registry,
}

Authoring_Export_Plan :: struct {
	allowed:                             bool,
	identity:                            Authoring_Content_Identity,
	destination_path:                    string,
	asset_sizes:                         Project_Asset_Package_Size_Report,
	validation_revision, asset_revision: u64,
	diagnostics:                         [dynamic]Authoring_Diagnostic,
}

authoring_content_identity_valid :: proc(identity: Authoring_Content_Identity) -> bool {
	return identity.id != "" && identity.content_version != ""
}

authoring_content_identity_equal :: proc(a, b: Authoring_Content_Identity) -> bool {
	return a.kind == b.kind && a.id == b.id && a.content_version == b.content_version
}

authoring_library_installed_index :: proc(
	library: ^Authoring_Library,
	identity: Authoring_Content_Identity,
) -> int {
	for item, index in library.installed do if authoring_content_identity_equal(item.identity, identity) do return index
	return -1
}

authoring_library_installed_versions :: proc(
	library: ^Authoring_Library,
	kind: Authoring_Artifact_Kind,
	id: string,
) -> [dynamic]int {
	result: [dynamic]int
	for item, index in library.installed do if item.identity.kind == kind && item.identity.id == id do append(&result, index)
	return result
}

authoring_package_inspection_destroy :: proc(inspection: ^Authoring_Package_Inspection) {
	delete(inspection.capabilities)
	delete(inspection.dependencies)
	delete(inspection.files)
	delete(inspection.cases)
	delete(inspection.compatibility_warnings)
	delete(inspection.typed_warnings)
	delete(inspection.diagnostics)
	inspection^ = {}
}

authoring_package_warning_add :: proc(
	inspection: ^Authoring_Package_Inspection,
	message: string,
	audience: Authoring_Package_Warning_Audience,
) {append(&inspection.compatibility_warnings, message); append(
		&inspection.typed_warnings,
		Authoring_Package_Warning{message, audience},
	)}

authoring_package_inspection_finalize :: proc(inspection: ^Authoring_Package_Inspection) {
	if !authoring_content_identity_valid(inspection.artifact.identity) do append(&inspection.diagnostics, authoring_diagnostic_init(.Packaging, "package", "", "manifest.identity", .Blocking, "package identity is incomplete"))
	if inspection.artifact.artifact_hash == "" do append(&inspection.diagnostics, authoring_diagnostic_init(.Packaging, "package", inspection.artifact.identity.id, "integrity.hash", .Error, "package hash is missing"))
	switch inspection.integrity {
	case .Unknown:
		append(
			&inspection.diagnostics,
			authoring_diagnostic_init(
				.Packaging,
				"package",
				inspection.artifact.identity.id,
				"integrity",
				.Blocking,
				"package integrity has not been verified",
			),
		)
	case .Corrupt:
		append(
			&inspection.diagnostics,
			authoring_diagnostic_init(
				.Packaging,
				"package",
				inspection.artifact.identity.id,
				"integrity",
				.Blocking,
				"package integrity verification failed",
			),
		)
	case .Valid:
	}
	switch inspection.compatibility {
	case .Compatible:
	case .Missing_Dependency:
		append(
			&inspection.diagnostics,
			authoring_diagnostic_init(
				.Compatibility,
				"package",
				inspection.artifact.identity.id,
				"dependencies",
				.Blocking,
				"package dependencies are missing",
			),
		)
	case .Incompatible:
		append(
			&inspection.diagnostics,
			authoring_diagnostic_init(
				.Compatibility,
				"package",
				inspection.artifact.identity.id,
				"capabilities",
				.Blocking,
				"package capabilities are incompatible",
			),
		)
	case .Unsupported_Format:
		append(
			&inspection.diagnostics,
			authoring_diagnostic_init(
				.Compatibility,
				"package",
				inspection.artifact.identity.id,
				"format_version",
				.Blocking,
				"package format is unsupported",
			),
		)
	}
}

authoring_package_inspection_installable :: proc(
	inspection: ^Authoring_Package_Inspection,
) -> bool {
	if inspection.integrity != .Valid || inspection.compatibility != .Compatible do return false
	for diagnostic in inspection.diagnostics do if diagnostic.severity >= .Error do return false
	return authoring_content_identity_valid(inspection.artifact.identity)
}

authoring_import_plan_destroy :: proc(plan: ^Authoring_Import_Plan) {
	delete(plan.diagnostics)
	plan^ = {}
}

authoring_library_plan_import :: proc(
	library: ^Authoring_Library,
	inspection: ^Authoring_Package_Inspection,
	decision: Authoring_Import_Decision,
	destination_root: string,
) -> Authoring_Import_Plan {
	plan := Authoring_Import_Plan {
		decision         = decision,
		artifact         = inspection.artifact,
		existing_index   = -1,
		destination_root = destination_root,
	}
	if destination_root == "" do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "destination_root", .Blocking, "import destination is required"))
	if !authoring_package_inspection_installable(inspection) do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "package", inspection.artifact.identity.id, "", .Blocking, "package is not installable"))
	plan.existing_index = authoring_library_installed_index(library, inspection.artifact.identity)
	versions := authoring_library_installed_versions(
		library,
		inspection.artifact.identity.kind,
		inspection.artifact.identity.id,
	); defer delete(versions)
	switch decision {
	case .Coexist:
		plan.preserve_existing = true
		if plan.existing_index >= 0 do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "content_version", .Blocking, "this exact version is already installed"))
	case .Upgrade:
		plan.preserve_existing = true
		if len(versions) == 0 do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "content_version", .Error, "upgrade requires an installed version"))
		if plan.existing_index >= 0 do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "content_version", .Blocking, "upgrade target must have a different version"))
		for version_index in versions do if authoring_semver_compare(inspection.artifact.identity.content_version, library.installed[version_index].identity.content_version) <= 0 {append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "content_version", .Blocking, "upgrade content version must be newer than every installed version")); break}
	case .Replace:
		if plan.existing_index < 0 do append(&plan.diagnostics, authoring_diagnostic_init(.Packaging, "library", inspection.artifact.identity.id, "content_version", .Error, "replace requires the same installed identity"))
	case .Editable_Copy:
		plan.preserve_existing = true
		plan.create_source_copy = true
	}
	plan.allowed = len(plan.diagnostics) == 0
	return plan
}

authoring_uninstall_plan_destroy :: proc(plan: ^Authoring_Uninstall_Plan) {
	delete(plan.dependent_indices)
	delete(plan.save_indices)
	delete(plan.diagnostics)
	plan^ = {}
}

authoring_library_plan_uninstall :: proc(
	library: ^Authoring_Library,
	identity: Authoring_Content_Identity,
) -> Authoring_Uninstall_Plan {
	result := Authoring_Uninstall_Plan {
		installed_index = authoring_library_installed_index(library, identity),
	}
	if result.installed_index < 0 {
		append(
			&result.diagnostics,
			authoring_diagnostic_init(
				.Packaging,
				"library",
				identity.id,
				"",
				.Error,
				"installed version was not found",
			),
		)
		return result
	}
	for save, index in library.saves do if authoring_content_identity_equal(save.content, identity) do append(&result.save_indices, index)
	for edge in library.dependency_edges {
		if edge.optional || edge.requirement.kind != identity.kind || edge.requirement.id != identity.id || authoring_semver_compare(identity.content_version, edge.requirement.content_version) < 0 do continue
		alternate :=
			false; for candidate in library.installed do if !authoring_content_identity_equal(candidate.identity, identity) && candidate.identity.kind == identity.kind && candidate.identity.id == identity.id && authoring_semver_compare(candidate.identity.content_version, edge.requirement.content_version) >= 0 {alternate = true; break}
		if alternate do continue
		dependent := authoring_library_installed_index(
			library,
			edge.dependent,
		); if dependent >= 0 {already := false; for index in result.dependent_indices do if index == dependent do already = true; if !already do append(&result.dependent_indices, dependent)}
	}
	if len(result.dependent_indices) > 0 do append(&result.diagnostics, authoring_diagnostic_init(.Compatibility, "library", identity.id, "dependencies", .Blocking, "installed content is required by another installed package"))
	// Saves are preserved outside the install root by default.
	result.allowed = len(result.dependent_indices) == 0
	return result
}

authoring_export_plan_destroy :: proc(plan: ^Authoring_Export_Plan) {
	delete(plan.diagnostics)
	plan^ = {}
}

authoring_plan_export :: proc(request: Authoring_Export_Request) -> Authoring_Export_Plan {
	result := Authoring_Export_Plan {
		identity         = request.source.identity,
		destination_path = request.destination_path,
	}
	if request.destination_path == "" do append(&result.diagnostics, authoring_diagnostic_init(.Packaging, "source-project", request.source.identity.id, "destination_path", .Blocking, "export destination is required"))
	if request.source.project_root == "" || request.source.manifest_path == "" do append(&result.diagnostics, authoring_diagnostic_init(.Packaging, "source-project", request.source.identity.id, "project_root", .Blocking, "source project paths are incomplete"))
	if !authoring_content_identity_valid(request.source.identity) do append(&result.diagnostics, authoring_diagnostic_init(.Packaging, "source-project", request.source.identity.id, "identity", .Blocking, "source identity is incomplete"))
	if request.validation == nil {
		append(
			&result.diagnostics,
			authoring_diagnostic_init(
				.Packaging,
				"source-project",
				request.source.identity.id,
				"validation",
				.Blocking,
				"export validation snapshot is required",
			),
		)
	} else {
		result.validation_revision = request.validation.revision
		if request.validation.profile != .Exportable do append(&result.diagnostics, authoring_diagnostic_init(.Packaging, "source-project", request.source.identity.id, "validation.profile", .Blocking, "export requires an exportable validation profile"))
		if authoring_validation_is_blocked(request.validation) do append(&result.diagnostics, authoring_diagnostic_init(.Packaging, "source-project", request.source.identity.id, "validation", .Blocking, "export validation is stale or blocking"))
	}
	if request.assets == nil {
		append(
			&result.diagnostics,
			authoring_diagnostic_init(
				.Assets,
				"source-project",
				request.source.identity.id,
				"assets",
				.Blocking,
				"asset registry is required",
			),
		)
	} else {
		result.asset_revision = request.assets.revision
		result.asset_sizes = project_asset_package_size_report(request.assets)
		if result.asset_sizes.prohibited_count > 0 do append(&result.diagnostics, authoring_diagnostic_init(.Assets, "project-assets", "", "embed_policy", .Blocking, "one or more assets prohibit packaging"))
		asset_diagnostics := project_asset_registry_diagnostics(
			request.assets,
		); defer delete(asset_diagnostics)
		for diagnostic in asset_diagnostics do if diagnostic.severity >= .Error do append(&result.diagnostics, diagnostic)
	}
	result.allowed = len(result.diagnostics) == 0
	return result
}
