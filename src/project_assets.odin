package main

import "core:os"
import "core:strings"

Project_Asset_Kind :: enum {
	Model,
	Texture,
	Material,
	Image,
	Audio,
	Animation,
	Font,
	Thumbnail,
}

Project_Asset_Source_Mode :: enum {Copy, Link}
Project_Asset_Embed_Policy :: enum {Embed, External, Prohibited}
Project_Asset_Reference_Kind :: enum {Owned, External_Catalog}
Project_Asset_Semantic_Target :: enum {Catalog_Model, Character_Appearance, Prop_Model, Material, UI_Image, Sound_Cue, Campaign_Thumbnail, Animation, Font}

project_asset_resolve_owned_path :: proc(registry:^Project_Asset_Registry,id:string)->(string,bool) {if registry==nil||id=="" do return "",false;index:=project_asset_index(registry,id);if index<0 do return "",false;asset:=registry.assets[index];path:=asset.project_path!=""?asset.project_path:asset.source_path;return path,path!=""}
project_asset_story_node_index :: proc(project:^Story_Project,id:string)->int {if project!=nil do for node,index in project.nodes do if node.id==id do return index;return -1}

story_entity_appearance_path :: proc(project:^Story_Project,registry:^Project_Asset_Registry,entity_id:string)->(string,bool) {if project==nil do return "",false;index:=story_entity_index(project,entity_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,project.entities[index].appearance_model_asset_ref)}
story_node_ui_image_path :: proc(project:^Story_Project,registry:^Project_Asset_Registry,node_id:string)->(string,bool) {index:=project_asset_story_node_index(project,node_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,project.nodes[index].ui_image_asset_ref)}
story_node_sound_path :: proc(project:^Story_Project,registry:^Project_Asset_Registry,node_id:string)->(string,bool) {index:=project_asset_story_node_index(project,node_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,project.nodes[index].sound_cue_asset_ref)}
story_node_animation_path :: proc(project:^Story_Project,registry:^Project_Asset_Registry,node_id:string)->(string,bool) {index:=project_asset_story_node_index(project,node_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,project.nodes[index].animation_asset_ref)}
story_ui_font_path :: proc(project:^Story_Project,registry:^Project_Asset_Registry)->(string,bool) {if project==nil do return "",false;return project_asset_resolve_owned_path(registry,project.ui_font_asset_ref)}
level_object_model_path :: proc(doc:^Level_Document,registry:^Project_Asset_Registry,object_id:string)->(string,bool) {if doc==nil do return "",false;index:=level_object_index(doc,object_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,doc.objects[index].model_asset_ref)}
level_object_material_path :: proc(doc:^Level_Document,registry:^Project_Asset_Registry,object_id:string)->(string,bool) {if doc==nil do return "",false;index:=level_object_index(doc,object_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,doc.objects[index].material_asset_ref)}
level_object_texture_path :: proc(doc:^Level_Document,registry:^Project_Asset_Registry,object_id:string)->(string,bool) {if doc==nil do return "",false;index:=level_object_index(doc,object_id);if index<0 do return "",false;return project_asset_resolve_owned_path(registry,doc.objects[index].texture_asset_ref)}

project_asset_preview_source :: proc(project_root:string,registry:^Project_Asset_Registry,index:int)->(string,Project_Asset_Kind,bool) {if registry==nil||index<0||index>=len(registry.assets) do return "",{},false;asset:=registry.assets[index];path:=project_asset_record_path(project_root,asset);return path,asset.kind,os.is_file(path)}

Project_Asset_Image_Metadata :: struct {
	width, height: int,
	color_space: string,
	has_alpha: bool,
}

Project_Asset_Audio_Metadata :: struct {
	duration_seconds: f64,
	channels, sample_rate: int,
}

Project_Asset_Model_Metadata :: struct {
	bounds_min, bounds_max: [3]f32,
	meters_per_unit: f32,
	up_axis, forward_axis: string,
	mesh_count, material_count: int,
}

Project_Asset_Animation_Metadata :: struct {
	clip_count: int,
	duration_seconds: f64,
}

Project_Asset_Technical_Metadata :: struct {
	format: string,
	byte_size: u64,
	image: Project_Asset_Image_Metadata,
	audio: Project_Asset_Audio_Metadata,
	model: Project_Asset_Model_Metadata,
	animation: Project_Asset_Animation_Metadata,
}

Project_Asset_Provenance :: struct {
	source_uri, source_name, creator, attribution, license_id, license_text: string,
	redistribution_permitted: bool,
}

Project_Asset_Record :: struct {
	id: string,
	kind: Project_Asset_Kind,
	project_path, source_path, sha256: string,
	source_mode: Project_Asset_Source_Mode,
	embed_policy: Project_Asset_Embed_Policy,
	provenance: Project_Asset_Provenance,
	technical: Project_Asset_Technical_Metadata,
}

Project_External_Asset_Reference :: struct {
	namespace, catalog_id, version: string,
}

Project_Asset_Reference :: struct {
	kind: Project_Asset_Reference_Kind,
	owned_id: string,
	external: Project_External_Asset_Reference,
}

Project_External_Catalog_Usage :: struct {
	reference: Project_External_Asset_Reference,
	document, entity_id, field_path: string,
}

Project_Asset_Usage :: struct {
	asset_id, document, entity_id, field_path: string,
}

Project_Asset_Dependency :: struct {
	asset_id, depends_on_id, purpose: string,
}

Project_Asset_Registry :: struct {
	assets: [dynamic]Project_Asset_Record,
	usages: [dynamic]Project_Asset_Usage,
	dependencies: [dynamic]Project_Asset_Dependency,
	external_catalog_usages: [dynamic]Project_External_Catalog_Usage,
	revision: u64,
}

// Asset authoring uses whole-registry snapshots deliberately. Registries are
// small authoring documents, and a snapshot makes compound changes (record,
// usage and dependency edits) atomic without leaving half-applied references.
Project_Asset_History :: struct {
	undo, redo: [dynamic]Project_Asset_Registry,
}

Project_Asset_Change_Preview :: struct {
	asset_id: string,
	usages: [dynamic]Project_Asset_Usage,
	dependents: [dynamic]Project_Asset_Dependency,
}

Project_Asset_Package_Size_Report :: struct {
	embedded_bytes, external_bytes, prohibited_bytes: u64,
	embedded_count, external_count, prohibited_count: int,
}

project_asset_id_valid :: proc(id: string) -> bool {
	if id == "" do return false
	for rune in id do if !(rune >= 'a' && rune <= 'z' || rune >= '0' && rune <= '9' || rune == '_' || rune == '-') do return false
	return true
}

project_external_asset_reference_valid :: proc(reference: Project_External_Asset_Reference) -> bool {
	return reference.namespace != "" && reference.catalog_id != "" && reference.version != "" &&
		!strings.contains(reference.namespace, ":")
}

project_owned_asset_reference :: proc(id: string) -> Project_Asset_Reference {
	return {kind = .Owned, owned_id = id}
}

project_external_asset_reference :: proc(namespace, catalog_id, version: string) -> Project_Asset_Reference {
	return {kind = .External_Catalog, external = {namespace, catalog_id, version}}
}

// Convert a semantic authoring choice into a canonical, typed usage. This is
// intentionally stricter than accepting arbitrary document/field strings.
project_asset_semantic_usage :: proc(asset: Project_Asset_Record, target: Project_Asset_Semantic_Target, entity_id: string) -> (Project_Asset_Usage, Validation) {
	if entity_id == "" do return {}, {false, "semantic asset mapping requires a selected target entity"}
	document, field := "", ""
	switch target {
	case .Catalog_Model:
		if asset.kind != .Model do return {}, {false, "catalog models require a model asset"}
		document, field = "catalog", "model_asset_ref"
	case .Character_Appearance:
		if asset.kind != .Model do return {}, {false, "character appearances require a model asset"}
		document, field = "story", "appearance.model_asset_ref"
	case .Prop_Model:
		if asset.kind != .Model do return {}, {false, "props require a model asset"}
		document, field = "level", "prop.model_asset_ref"
	case .Material:
		if asset.kind != .Material && asset.kind != .Texture do return {}, {false, "material mappings require a material or texture asset"}
		document, field = "level", asset.kind == .Texture ? "material.texture_asset_ref" : "material_asset_ref"
	case .UI_Image:
		if asset.kind != .Image do return {}, {false, "UI images require an image asset"}
		document, field = "graph", "ui.image_asset_ref"
	case .Sound_Cue:
		if asset.kind != .Audio do return {}, {false, "sound cues require an audio asset"}
		document, field = "story", "sound_cue_asset_ref"
	case .Campaign_Thumbnail:
		if asset.kind != .Thumbnail && asset.kind != .Image do return {}, {false, "campaign thumbnails require an image or thumbnail asset"}
		document, field = "campaign", "thumbnail"
	case .Animation:
		if asset.kind != .Animation && asset.kind != .Model do return {}, {false, "animation mappings require an animation or animated model asset"}
		document, field = "graph", "animation_asset_ref"
	case .Font:
		if asset.kind != .Font do return {}, {false, "font mappings require a font asset"}
		document, field = "story", "ui.font_asset_ref"
	}
	return {asset.id, document, entity_id, field}, {true, "TYPED ASSET USAGE READY"}
}

project_asset_registry_destroy :: proc(registry: ^Project_Asset_Registry) {
	delete(registry.assets)
	delete(registry.usages)
	delete(registry.dependencies)
	delete(registry.external_catalog_usages)
	registry^ = {}
}

project_asset_clone_string :: proc(value: string) -> string {
	if value == "" do return ""
	return strings.clone(value)
}

project_asset_record_clone :: proc(asset: Project_Asset_Record) -> Project_Asset_Record {
	result := asset
	result.id = project_asset_clone_string(asset.id)
	result.project_path = project_asset_clone_string(asset.project_path)
	result.source_path = project_asset_clone_string(asset.source_path)
	result.sha256 = project_asset_clone_string(asset.sha256)
	result.provenance.source_uri = project_asset_clone_string(asset.provenance.source_uri)
	result.provenance.source_name = project_asset_clone_string(asset.provenance.source_name)
	result.provenance.creator = project_asset_clone_string(asset.provenance.creator)
	result.provenance.attribution = project_asset_clone_string(asset.provenance.attribution)
	result.provenance.license_id = project_asset_clone_string(asset.provenance.license_id)
	result.provenance.license_text = project_asset_clone_string(asset.provenance.license_text)
	result.technical.format = project_asset_clone_string(asset.technical.format)
	result.technical.image.color_space = project_asset_clone_string(asset.technical.image.color_space)
	result.technical.model.up_axis = project_asset_clone_string(asset.technical.model.up_axis)
	result.technical.model.forward_axis = project_asset_clone_string(asset.technical.model.forward_axis)
	return result
}

project_asset_registry_clone :: proc(registry: ^Project_Asset_Registry) -> Project_Asset_Registry {
	result := Project_Asset_Registry{revision = registry.revision}
	for asset in registry.assets do append(&result.assets, project_asset_record_clone(asset))
	for usage in registry.usages do append(&result.usages, Project_Asset_Usage{
		project_asset_clone_string(usage.asset_id), project_asset_clone_string(usage.document),
		project_asset_clone_string(usage.entity_id), project_asset_clone_string(usage.field_path),
	})
	for dependency in registry.dependencies do append(&result.dependencies, Project_Asset_Dependency{
		project_asset_clone_string(dependency.asset_id), project_asset_clone_string(dependency.depends_on_id),
		project_asset_clone_string(dependency.purpose),
	})
	for usage in registry.external_catalog_usages do append(&result.external_catalog_usages, Project_External_Catalog_Usage{
		{project_asset_clone_string(usage.reference.namespace), project_asset_clone_string(usage.reference.catalog_id), project_asset_clone_string(usage.reference.version)},
		project_asset_clone_string(usage.document), project_asset_clone_string(usage.entity_id), project_asset_clone_string(usage.field_path),
	})
	return result
}

project_asset_history_clear :: proc(stack: ^[dynamic]Project_Asset_Registry) {
	for &snapshot in stack do project_asset_registry_destroy(&snapshot)
	delete(stack^)
	stack^ = nil
}

project_asset_history_destroy :: proc(history: ^Project_Asset_History) {
	project_asset_history_clear(&history.undo)
	project_asset_history_clear(&history.redo)
	history^ = {}
}

// Begin before a UI mutation. Call cancel if validation or filesystem work
// fails; otherwise the snapshot becomes one undo step.
project_asset_history_begin :: proc(history: ^Project_Asset_History, registry: ^Project_Asset_Registry) {
	append(&history.undo, project_asset_registry_clone(registry))
	project_asset_history_clear(&history.redo)
}

project_asset_history_cancel :: proc(history: ^Project_Asset_History, registry: ^Project_Asset_Registry) -> bool {
	if len(history.undo) == 0 do return false
	project_asset_registry_destroy(registry)
	last := len(history.undo)-1
	registry^ = history.undo[last]
	ordered_remove(&history.undo, last)
	return true
}

project_asset_history_restore :: proc(history: ^Project_Asset_History, registry: ^Project_Asset_Registry, undo: bool) -> bool {
	source := undo ? &history.undo : &history.redo
	destination := undo ? &history.redo : &history.undo
	if len(source^) == 0 do return false
	append(destination, project_asset_registry_clone(registry))
	project_asset_registry_destroy(registry)
	last := len(source^)-1
	registry^ = source^[last]
	ordered_remove(source, last)
	return true
}

project_asset_history_undo :: proc(history: ^Project_Asset_History, registry: ^Project_Asset_Registry) -> bool {
	return project_asset_history_restore(history, registry, true)
}

project_asset_history_redo :: proc(history: ^Project_Asset_History, registry: ^Project_Asset_Registry) -> bool {
	return project_asset_history_restore(history, registry, false)
}

project_asset_index :: proc(registry: ^Project_Asset_Registry, id: string) -> int {
	for asset, index in registry.assets do if asset.id == id do return index
	return -1
}

project_asset_hash_index :: proc(registry: ^Project_Asset_Registry, sha256: string) -> int {
	if sha256 == "" do return -1
	for asset, index in registry.assets do if asset.sha256 == sha256 do return index
	return -1
}

project_asset_validate_record :: proc(asset: Project_Asset_Record) -> Validation {
	if !project_asset_id_valid(asset.id) do return {false, "asset ID must use lowercase letters, digits, hyphens, or underscores"}
	if asset.sha256 == "" do return {false, "asset hash is required"}
	if asset.source_mode == .Copy && asset.project_path == "" do return {false, "copied asset requires a project path"}
	if asset.source_mode == .Link && asset.source_path == "" do return {false, "linked asset requires a source path"}
	if asset.embed_policy == .Embed && !asset.provenance.redistribution_permitted do return {false, "embedded asset is not permitted for redistribution"}
	if asset.embed_policy == .Embed && asset.source_mode == .Link && asset.project_path == "" do return {false, "embedded linked asset requires a package source path"}
	if asset.technical.byte_size == 0 do return {false, "asset byte size is required"}
	return {true, "ASSET VALID"}
}

project_asset_registry_add :: proc(registry: ^Project_Asset_Registry, asset: Project_Asset_Record) -> Validation {
	if valid := project_asset_validate_record(asset); !valid.ok do return valid
	if project_asset_index(registry, asset.id) >= 0 do return {false, "asset ID already exists"}
	if duplicate := project_asset_hash_index(registry, asset.sha256); duplicate >= 0 do return {false, "asset content already exists under another stable ID"}
	append(&registry.assets, asset)
	registry.revision += 1
	return {true, "ASSET ADDED"}
}

project_asset_registry_register_usage :: proc(registry: ^Project_Asset_Registry, usage: Project_Asset_Usage) -> bool {
	if project_asset_index(registry, usage.asset_id) < 0 || usage.document == "" || usage.field_path == "" do return false
	for known in registry.usages do if known == usage do return true
	append(&registry.usages, usage)
	registry.revision += 1
	return true
}

project_asset_registry_register_dependency :: proc(registry: ^Project_Asset_Registry, dependency: Project_Asset_Dependency) -> bool {
	if dependency.asset_id == dependency.depends_on_id || project_asset_index(registry, dependency.asset_id) < 0 || project_asset_index(registry, dependency.depends_on_id) < 0 do return false
	for known in registry.dependencies do if known == dependency do return true
	append(&registry.dependencies, dependency)
	registry.revision += 1
	return true
}

project_asset_registry_register_external_catalog_usage :: proc(registry: ^Project_Asset_Registry, usage: Project_External_Catalog_Usage) -> Validation {
	if registry == nil || !project_external_asset_reference_valid(usage.reference) do return {false, "external catalog reference requires a namespace, catalog ID, and pinned version"}
	if usage.document == "" || usage.entity_id == "" || usage.field_path == "" do return {false, "external catalog reference requires a typed consumer location"}
	for known in registry.external_catalog_usages do if known == usage do return {true, "EXTERNAL CATALOG REFERENCE ALREADY REGISTERED"}
	append(&registry.external_catalog_usages, usage)
	registry.revision += 1
	return {true, "EXTERNAL CATALOG REFERENCE REGISTERED"}
}

project_asset_change_preview :: proc(registry: ^Project_Asset_Registry, id: string) -> Project_Asset_Change_Preview {
	result := Project_Asset_Change_Preview{asset_id = id}
	for usage in registry.usages do if usage.asset_id == id do append(&result.usages, usage)
	for dependency in registry.dependencies do if dependency.depends_on_id == id do append(&result.dependents, dependency)
	return result
}

project_asset_change_preview_destroy :: proc(preview: ^Project_Asset_Change_Preview) {
	delete(preview.usages)
	delete(preview.dependents)
	preview^ = {}
}

project_asset_registry_replace :: proc(registry: ^Project_Asset_Registry, id: string, replacement: Project_Asset_Record) -> Validation {
	index := project_asset_index(registry, id)
	if index < 0 do return {false, "asset does not exist"}
	if replacement.id != id do return {false, "replacement must preserve the stable asset ID"}
	if valid := project_asset_validate_record(replacement); !valid.ok do return valid
	duplicate := project_asset_hash_index(registry, replacement.sha256)
	if duplicate >= 0 && duplicate != index do return {false, "replacement duplicates another asset"}
	registry.assets[index] = replacement
	registry.revision += 1
	return {true, "ASSET REPLACED"}
}

project_asset_registry_remove :: proc(registry: ^Project_Asset_Registry, id: string) -> Validation {
	index := project_asset_index(registry, id)
	if index < 0 do return {false, "asset does not exist"}
	preview := project_asset_change_preview(registry, id); defer project_asset_change_preview_destroy(&preview)
	if len(preview.usages) > 0 || len(preview.dependents) > 0 do return {false, "asset is still used; inspect the dependency preview before removal"}
	ordered_remove(&registry.assets, index)
	for dependency_index := len(registry.dependencies) - 1; dependency_index >= 0; dependency_index -= 1 do if registry.dependencies[dependency_index].asset_id == id do ordered_remove(&registry.dependencies, dependency_index)
	registry.revision += 1
	return {true, "ASSET REMOVED"}
}

project_asset_package_size_report :: proc(registry: ^Project_Asset_Registry) -> Project_Asset_Package_Size_Report {
	result: Project_Asset_Package_Size_Report
	for asset in registry.assets {
		switch asset.embed_policy {
		case .Embed: result.embedded_bytes += asset.technical.byte_size; result.embedded_count += 1
		case .External: result.external_bytes += asset.technical.byte_size; result.external_count += 1
		case .Prohibited: result.prohibited_bytes += asset.technical.byte_size; result.prohibited_count += 1
		}
	}
	return result
}

project_asset_registry_diagnostics :: proc(registry: ^Project_Asset_Registry) -> [dynamic]Authoring_Diagnostic {
	result: [dynamic]Authoring_Diagnostic
	for asset in registry.assets {
		valid := project_asset_validate_record(asset)
		if !valid.ok do append(&result, authoring_diagnostic_init(.Assets, "project-assets", asset.id, "", .Error, valid.message))
		if asset.provenance.license_id == "" do append(&result, authoring_diagnostic_init(.Assets, "project-assets", asset.id, "provenance.license_id", .Warning, "asset license metadata is missing"))
		if asset.embed_policy == .Prohibited do append(&result, authoring_diagnostic_init(.Assets, "project-assets", asset.id, "embed_policy", .Blocking, "asset policy prohibits packaging"))
	}
	for usage in registry.usages do if project_asset_index(registry, usage.asset_id) < 0 do append(&result, authoring_diagnostic_init(.Assets, usage.document, usage.entity_id, usage.field_path, .Error, "asset reference is missing"))
	for usage in registry.external_catalog_usages do if !project_external_asset_reference_valid(usage.reference) do append(&result, authoring_diagnostic_init(.Compatibility, usage.document, usage.entity_id, usage.field_path, .Blocking, "external catalog reference must be namespaced and version-pinned"))
	return result
}
