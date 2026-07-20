package main

import "core:crypto/sha2"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

PROJECT_ASSET_REGISTRY_RELATIVE :: "assets/registry.toml"

Project_Asset_Import_Request :: struct {
	project_root, source_path, destination_directory, requested_id: string,
	kind: Project_Asset_Kind,
	mode: Project_Asset_Source_Mode,
	embed_policy: Project_Asset_Embed_Policy,
	provenance: Project_Asset_Provenance,
}

Project_Asset_Missing_Record :: struct {asset_id, expected_path: string}
Project_Asset_Relink_Candidate :: struct {asset_id, candidate_path, sha256: string, exact_hash: bool}
Project_Asset_Relink_Plan :: struct {
	missing: [dynamic]Project_Asset_Missing_Record,
	candidates: [dynamic]Project_Asset_Relink_Candidate,
}
Project_Asset_Replacement_Preview :: struct {
	valid: bool,
	asset_id, candidate_path, candidate_sha256: string,
	replacement: Project_Asset_Record,
	change: Project_Asset_Change_Preview,
	message: string,
}
Project_Asset_Stage_Item :: struct {asset_id, source_path, package_path, sha256: string, byte_size: u64}
Project_Asset_Stage_Plan :: struct {
	allowed: bool,
	items: [dynamic]Project_Asset_Stage_Item,
	attribution_manifest: string,
	diagnostics: [dynamic]Authoring_Diagnostic,
	total_bytes: u64,
	external_catalog_requirements: [dynamic]Project_External_Asset_Reference,
}

project_asset_io_escape :: proc(value: string) -> string {
	result := ""
	for rune in value {
		if rune == '\\' do result = fmt.tprintf("%s\\\\", result)
		else if rune == '"' do result = fmt.tprintf("%s\\\"", result)
		else if rune == '\n' do result = fmt.tprintf("%s\\n", result)
		else do result = fmt.tprintf("%s%c", result, rune)
	}
	return result
}

project_asset_registry_serialize :: proc(registry: ^Project_Asset_Registry) -> string {
	text := fmt.tprintf("format = \"ProjectAssetRegistry v1\"\nrevision = %d\n", registry.revision)
	for asset in registry.assets {
		text = fmt.tprintf("%s\n[[assets]]\nid = \"%s\"\nkind = %d\nproject_path = \"%s\"\nsource_path = \"%s\"\nsha256 = \"%s\"\nsource_mode = %d\nembed_policy = %d\nsource_uri = \"%s\"\nsource_name = \"%s\"\ncreator = \"%s\"\nattribution = \"%s\"\nlicense_id = \"%s\"\nlicense_text = \"%s\"\nredistribution_permitted = %t\nformat = \"%s\"\nbyte_size = %d\nimage_width = %d\nimage_height = %d\ncolor_space = \"%s\"\nhas_alpha = %t\naudio_duration = %g\naudio_channels = %d\naudio_sample_rate = %d\nmodel_min_x = %g\nmodel_min_y = %g\nmodel_min_z = %g\nmodel_max_x = %g\nmodel_max_y = %g\nmodel_max_z = %g\nmeters_per_unit = %g\nup_axis = \"%s\"\nforward_axis = \"%s\"\nmesh_count = %d\nmaterial_count = %d\nclip_count = %d\nanimation_duration = %g\n",
			text, project_asset_io_escape(asset.id), int(asset.kind), project_asset_io_escape(asset.project_path), project_asset_io_escape(asset.source_path), asset.sha256, int(asset.source_mode), int(asset.embed_policy),
			project_asset_io_escape(asset.provenance.source_uri), project_asset_io_escape(asset.provenance.source_name), project_asset_io_escape(asset.provenance.creator), project_asset_io_escape(asset.provenance.attribution), project_asset_io_escape(asset.provenance.license_id), project_asset_io_escape(asset.provenance.license_text), asset.provenance.redistribution_permitted,
			project_asset_io_escape(asset.technical.format), asset.technical.byte_size, asset.technical.image.width, asset.technical.image.height, project_asset_io_escape(asset.technical.image.color_space), asset.technical.image.has_alpha, asset.technical.audio.duration_seconds, asset.technical.audio.channels, asset.technical.audio.sample_rate,
			asset.technical.model.bounds_min[0], asset.technical.model.bounds_min[1], asset.technical.model.bounds_min[2], asset.technical.model.bounds_max[0], asset.technical.model.bounds_max[1], asset.technical.model.bounds_max[2], asset.technical.model.meters_per_unit, project_asset_io_escape(asset.technical.model.up_axis), project_asset_io_escape(asset.technical.model.forward_axis), asset.technical.model.mesh_count, asset.technical.model.material_count, asset.technical.animation.clip_count, asset.technical.animation.duration_seconds)
	}
	for usage in registry.usages do text = fmt.tprintf("%s\n[[usages]]\nasset_id = \"%s\"\ndocument = \"%s\"\nentity_id = \"%s\"\nfield_path = \"%s\"\n", text, project_asset_io_escape(usage.asset_id), project_asset_io_escape(usage.document), project_asset_io_escape(usage.entity_id), project_asset_io_escape(usage.field_path))
	for dependency in registry.dependencies do text = fmt.tprintf("%s\n[[dependencies]]\nasset_id = \"%s\"\ndepends_on_id = \"%s\"\npurpose = \"%s\"\n", text, project_asset_io_escape(dependency.asset_id), project_asset_io_escape(dependency.depends_on_id), project_asset_io_escape(dependency.purpose))
	for usage in registry.external_catalog_usages do text = fmt.tprintf("%s\n[[external_catalog_usages]]\nnamespace = \"%s\"\ncatalog_id = \"%s\"\nversion = \"%s\"\ndocument = \"%s\"\nentity_id = \"%s\"\nfield_path = \"%s\"\n", text, project_asset_io_escape(usage.reference.namespace), project_asset_io_escape(usage.reference.catalog_id), project_asset_io_escape(usage.reference.version), project_asset_io_escape(usage.document), project_asset_io_escape(usage.entity_id), project_asset_io_escape(usage.field_path))
	return text
}

project_asset_registry_save :: proc(path: string, registry: ^Project_Asset_Registry) -> Validation {
	if path == "" || registry == nil do return {false, "asset registry path and data are required"}
	for asset in registry.assets {if valid := project_asset_validate_record(asset); !valid.ok do return valid}
	directory := os.dir(path)
	if directory == "" || (!os.exists(directory) && os.make_directory_all(directory) != nil) do return {false, "could not create asset registry directory"}
	temporary := fmt.tprintf("%s.tmp", path)
	if os.write_entire_file(temporary, transmute([]byte)project_asset_registry_serialize(registry)) != nil do return {false, "could not write asset registry temporary file"}
	if os.rename(temporary, path) != nil { _ = os.remove(temporary); return {false, "could not replace asset registry"} }
	return {true, "ASSET REGISTRY SAVED"}
}

project_asset_registry_load :: proc(path: string, out: ^Project_Asset_Registry) -> Validation {
	if out == nil do return {false, "asset registry destination is required"}
	cpath, error := strings.clone_to_cstring(path, context.temp_allocator); if error != nil do return {false, "invalid asset registry path"}
	parsed := toml_parse_file_ex(cpath); defer toml_free(parsed)
	if !parsed.ok do return toml_parse_diagnostic(path, "project asset registry", &parsed)
	top := parsed.toptab
	if toml_case_string(top, "format") != "ProjectAssetRegistry v1" do return {false, "project asset registry format is unsupported"}
	stored_revision := u64(max(toml_case_int(top, "revision"), 0)); next := Project_Asset_Registry{}
	for table in toml_tables(top, "assets") {
		asset := Project_Asset_Record{id=toml_case_string(table,"id"),kind=Project_Asset_Kind(clamp(toml_case_int(table,"kind"),0,int(Project_Asset_Kind.Thumbnail))),project_path=toml_case_string(table,"project_path"),source_path=toml_case_string(table,"source_path"),sha256=toml_case_string(table,"sha256"),source_mode=Project_Asset_Source_Mode(clamp(toml_case_int(table,"source_mode"),0,1)),embed_policy=Project_Asset_Embed_Policy(clamp(toml_case_int(table,"embed_policy"),0,2))}
		asset.provenance={source_uri=toml_case_string(table,"source_uri"),source_name=toml_case_string(table,"source_name"),creator=toml_case_string(table,"creator"),attribution=toml_case_string(table,"attribution"),license_id=toml_case_string(table,"license_id"),license_text=toml_case_string(table,"license_text"),redistribution_permitted=toml_case_bool(table,"redistribution_permitted")}
		asset.technical.format=toml_case_string(table,"format"); asset.technical.byte_size=u64(max(toml_case_int(table,"byte_size"),0)); asset.technical.image={width=toml_case_int(table,"image_width"),height=toml_case_int(table,"image_height"),color_space=toml_case_string(table,"color_space"),has_alpha=toml_case_bool(table,"has_alpha")}; asset.technical.audio={duration_seconds=f64(toml_case_float(table,"audio_duration")),channels=toml_case_int(table,"audio_channels"),sample_rate=toml_case_int(table,"audio_sample_rate")}
		asset.technical.model.bounds_min={toml_case_float(table,"model_min_x"),toml_case_float(table,"model_min_y"),toml_case_float(table,"model_min_z")};asset.technical.model.bounds_max={toml_case_float(table,"model_max_x"),toml_case_float(table,"model_max_y"),toml_case_float(table,"model_max_z")}
		asset.technical.model.meters_per_unit=toml_case_float(table,"meters_per_unit"); asset.technical.model.up_axis=toml_case_string(table,"up_axis"); asset.technical.model.forward_axis=toml_case_string(table,"forward_axis"); asset.technical.model.mesh_count=toml_case_int(table,"mesh_count"); asset.technical.model.material_count=toml_case_int(table,"material_count"); asset.technical.animation={clip_count=toml_case_int(table,"clip_count"),duration_seconds=f64(toml_case_float(table,"animation_duration"))}
		if valid:=project_asset_registry_add(&next,asset); !valid.ok {project_asset_registry_destroy(&next);return valid}
	}
	for table in toml_tables(top,"usages") {usage:=Project_Asset_Usage{toml_case_string(table,"asset_id"),toml_case_string(table,"document"),toml_case_string(table,"entity_id"),toml_case_string(table,"field_path")};if !project_asset_registry_register_usage(&next,usage) {project_asset_registry_destroy(&next);return {false,"asset registry contains an invalid usage"}}}
	for table in toml_tables(top,"dependencies") {dependency:=Project_Asset_Dependency{toml_case_string(table,"asset_id"),toml_case_string(table,"depends_on_id"),toml_case_string(table,"purpose")};if !project_asset_registry_register_dependency(&next,dependency) {project_asset_registry_destroy(&next);return {false,"asset registry contains an invalid dependency"}}}
	for table in toml_tables(top,"external_catalog_usages") {usage:=Project_External_Catalog_Usage{reference={toml_case_string(table,"namespace"),toml_case_string(table,"catalog_id"),toml_case_string(table,"version")},document=toml_case_string(table,"document"),entity_id=toml_case_string(table,"entity_id"),field_path=toml_case_string(table,"field_path")};if valid:=project_asset_registry_register_external_catalog_usage(&next,usage);!valid.ok {project_asset_registry_destroy(&next);return valid}}
	next.revision=stored_revision;project_asset_registry_destroy(out); out^=next; return {true,"ASSET REGISTRY LOADED"}
}

project_asset_registry_path :: proc(project:^Authoring_Project)->(string,bool) {
	return authoring_resolve_path(project, PROJECT_ASSET_REGISTRY_RELATIVE)
}

// A missing registry is the backward-compatible representation of an older
// source project with no project-owned assets. Malformed registries remain a
// hard error so opening a project never silently discards attribution data.
project_asset_registry_load_project :: proc(project:^Authoring_Project, out:^Project_Asset_Registry)->Validation {
	if project == nil || out == nil do return {false, "project and asset registry destination are required"}
	path, ok := project_asset_registry_path(project)
	if !ok do return {false, "project asset registry path is invalid"}
	if !os.is_file(path) {
		project_asset_registry_destroy(out)
		return {true, "PROJECT HAS NO ASSET REGISTRY"}
	}
	return project_asset_registry_load(path, out)
}

project_asset_registry_save_project :: proc(project:^Authoring_Project, registry:^Project_Asset_Registry)->Validation {
	if project == nil || registry == nil do return {false, "project and asset registry are required"}
	path, ok := project_asset_registry_path(project)
	if !ok do return {false, "project asset registry path is invalid"}
	return project_asset_registry_save(path, registry)
}

project_asset_sha256_file :: proc(path: string) -> (string, Validation) {
	data, error := os.read_entire_file_from_path(path, context.temp_allocator); if error != nil do return "", {false,"could not read asset for hashing"}
	ctx: sha2.Context_256; digest: [sha2.DIGEST_SIZE_256]byte; sha2.init_256(&ctx); sha2.update(&ctx,data); sha2.final(&ctx,digest[:])
	encoded, allocation_error := hex.encode(digest[:]); if allocation_error != nil do return "", {false,"could not encode asset hash"}
	return string(encoded), {true,"ASSET HASHED"}
}

project_asset_stable_id :: proc(source_path: string, registry: ^Project_Asset_Registry) -> string {
	base := strings.to_lower(filepath.stem(source_path)); id := ""
	for rune in base {if rune>='a'&&rune<='z'||rune>='0'&&rune<='9'||rune=='_'||rune=='-' do id=fmt.tprintf("%s%c",id,rune);else if id!=""&&!strings.has_suffix(id,"-") do id=fmt.tprintf("%s-",id)}
	if id=="" do id="asset"; candidate:=id
	for suffix:=2; project_asset_index(registry,candidate)>=0; suffix+=1 do candidate=fmt.tprintf("%s-%d",id,suffix)
	return candidate
}

project_asset_path_within_root :: proc(root, target: string) -> bool {
	if root==""||target=="" do return false
	clean_root,clean_root_error:=filepath.clean(root,context.allocator);if clean_root_error!=nil do return false;defer delete(clean_root)
	clean_target,clean_target_error:=filepath.clean(target,context.allocator);if clean_target_error!=nil do return false;defer delete(clean_target)
	if filepath.is_abs(clean_root)!=filepath.is_abs(clean_target) do return false
	if clean_target==clean_root do return true
	prefix:=fmt.tprintf("%s/",strings.trim_right(clean_root,"/\\"))
	return strings.has_prefix(clean_target,prefix)
}

project_asset_u32_be :: proc(data: []byte, at: int)->u32 {return u32(data[at])<<24|u32(data[at+1])<<16|u32(data[at+2])<<8|u32(data[at+3])}
project_asset_u32_le :: proc(data: []byte, at: int)->u32 {return u32(data[at])|u32(data[at+1])<<8|u32(data[at+2])<<16|u32(data[at+3])<<24}
project_asset_u16_le :: proc(data: []byte, at: int)->u16 {return u16(data[at])|u16(data[at+1])<<8}
project_asset_u64_le :: proc(data: []byte, at: int)->u64 {result:u64;for i in 0..<8 do result|=u64(data[at+i])<<u64(i*8);return result}

project_asset_inspect_file :: proc(path: string, technical: ^Project_Asset_Technical_Metadata) -> Validation {
	data,error:=os.read_entire_file_from_path(path,context.temp_allocator);if error!=nil do return {false,"could not read asset metadata"};technical^={byte_size=u64(len(data))};ext:=strings.to_lower(filepath.ext(path));technical.format=ext
	if ext==".png" {if len(data)<33||string(data[:8])!="\x89PNG\r\n\x1a\n" do return {false,"invalid PNG signature"};technical.image.width=int(project_asset_u32_be(data,16));technical.image.height=int(project_asset_u32_be(data,20));color:=data[25];technical.image.has_alpha=color==4||color==6;technical.image.color_space="sRGB";return {true,"PNG METADATA INSPECTED"}}
	if ext==".jpg"||ext==".jpeg" {if len(data)<4||data[0]!=0xff||data[1]!=0xd8 do return {false,"invalid JPEG signature"};at:=2;for at+9<len(data) {if data[at]!=0xff {at+=1;continue};marker:=data[at+1];if marker==0xd8||marker==0xd9 {at+=2;continue};size:=int(data[at+2])<<8|int(data[at+3]);if size<2||at+2+size>len(data) do break;if marker>=0xc0&&marker<=0xc3 {technical.image.height=int(data[at+5])<<8|int(data[at+6]);technical.image.width=int(data[at+7])<<8|int(data[at+8]);technical.image.color_space="sRGB";return {true,"JPEG METADATA INSPECTED"}};at+=2+size};return {false,"JPEG dimensions were not found"}}
	if ext==".wav" {if len(data)<44||string(data[:4])!="RIFF"||string(data[8:12])!="WAVE" do return {false,"invalid WAV signature"};at:=12;byte_rate:u32;data_size:u32;for at+8<=len(data) {size:=project_asset_u32_le(data,at+4);if string(data[at:at+4])=="fmt "&&size>=16&&at+24<=len(data) {technical.audio.channels=int(project_asset_u16_le(data,at+10));technical.audio.sample_rate=int(project_asset_u32_le(data,at+12));byte_rate=project_asset_u32_le(data,at+16)}else if string(data[at:at+4])=="data" do data_size=size;at+=8+int(size)+(int(size)&1)};if byte_rate>0 do technical.audio.duration_seconds=f64(data_size)/f64(byte_rate);return {true,"WAV METADATA INSPECTED"}}
	if ext==".ogg" {if len(data)<32||string(data[:4])!="OggS" do return {false,"invalid OGG signature"};header_found:=false;last_granule:u64;for at in 0..<len(data)-16 {if at+14<=len(data)&&string(data[at:at+4])=="OggS" {granule:=project_asset_u64_le(data,at+6);if granule!=0xffffffffffffffff do last_granule=max(last_granule,granule)};if data[at]==1&&string(data[at+1:at+7])=="vorbis" {technical.audio.channels=int(data[at+11]);technical.audio.sample_rate=int(project_asset_u32_le(data,at+12));header_found=true}};if !header_found do return {false,"OGG Vorbis identification header was not found"};if technical.audio.sample_rate>0 do technical.audio.duration_seconds=f64(last_granule)/f64(technical.audio.sample_rate);return {true,"OGG VORBIS METADATA INSPECTED"}}
	if ext==".glb" {if len(data)<20||project_asset_u32_le(data,0)!=u32(0x46546c67) do return {false,"invalid GLB signature"};mesh,loaded:=glb_load(path,context.temp_allocator);if !loaded||!mesh.ready do return {false,"GLB geometry could not be decoded"};technical.model.bounds_min={mesh.min.x,mesh.min.y,mesh.min.z};technical.model.bounds_max={mesh.max.x,mesh.max.y,mesh.max.z};technical.model.meters_per_unit=1;technical.model.up_axis="+Y";technical.model.forward_axis="+Z";technical.model.mesh_count=len(mesh.primitives);technical.model.material_count=len(mesh.material_names);technical.animation.clip_count=len(mesh.clips);for clip in mesh.clips do technical.animation.duration_seconds=max(technical.animation.duration_seconds,f64(clip.duration));return {true,"GLB GEOMETRY, MATERIAL, AXIS, AND ANIMATION METADATA INSPECTED"}}
	if ext==".ttf" {if len(data)<12||!(string(data[:4])=="\x00\x01\x00\x00"||string(data[:4])=="true") do return {false,"invalid TrueType font signature"};return {true,"TRUETYPE FONT VALIDATED"}}
	if ext==".otf" {if len(data)<12||string(data[:4])!="OTTO" do return {false,"invalid OpenType font signature"};return {true,"OPENTYPE FONT VALIDATED"}}
	return {false,fmt.tprintf("unsupported project asset format %s; use PNG, JPEG, WAV, OGG Vorbis, GLB, TTF, or OTF",ext)}
}

project_asset_import :: proc(registry:^Project_Asset_Registry,request:Project_Asset_Import_Request)->Validation {
	if registry==nil||!os.is_file(request.source_path) do return {false,"asset import source is not a file"}
	hash,hashed:=project_asset_sha256_file(request.source_path);if !hashed.ok do return hashed;if project_asset_hash_index(registry,hash)>=0 do return {false,"asset content is already registered"}
	id:=request.requested_id;if id=="" do id=project_asset_stable_id(request.source_path,registry);if !project_asset_id_valid(id) do return {false,"requested asset ID is invalid"}
	record:=Project_Asset_Record{id=id,kind=request.kind,source_path=request.source_path,sha256=hash,source_mode=request.mode,embed_policy=request.embed_policy,provenance=request.provenance};inspected:=project_asset_inspect_file(request.source_path,&record.technical);if !inspected.ok do return inspected
	if request.mode==.Copy {if request.destination_directory=="" do return {false,"copied asset destination is required"};destination,join_error:=filepath.join([]string{request.project_root,request.destination_directory,filepath.base(request.source_path)},context.allocator);if join_error!=nil do return {false,"could not join asset destination"};defer delete(destination);if !project_asset_path_within_root(request.project_root,destination) do return {false,fmt.tprintf("asset destination escapes project root: %s -> %s",request.project_root,destination)};relative,rel_error:=filepath.rel(request.project_root,destination,context.allocator);if rel_error!=.None do return {false,"could not record project-relative asset path"};record.project_path=relative;if valid:=project_asset_validate_record(record);!valid.ok do return valid;copy_needed:=true;if os.is_file(destination) {existing_hash,existing_valid:=project_asset_sha256_file(destination);if !existing_valid.ok||existing_hash!=hash do return {false,"asset destination already contains different content"};copy_needed=false};if copy_needed {parent,_:=filepath.split(destination);if !os.is_dir(parent)&&os.make_directory_all(parent)!=nil do return {false,"could not create asset destination"};if os.copy_file(destination,request.source_path)!=nil do return {false,"could not copy asset into project"}}}else if request.embed_policy==.Embed do return {false,"linked embedded assets require an explicit project package source"}
	return project_asset_registry_add(registry,record)
}

project_asset_record_path :: proc(root:string,asset:Project_Asset_Record)->string {path:=asset.source_path;if asset.project_path!="" {joined,error:=filepath.join([]string{root,asset.project_path},context.allocator);if error==nil do path=joined};return path}

project_asset_plan_relink :: proc(registry:^Project_Asset_Registry,project_root,search_root:string)->Project_Asset_Relink_Plan {
	result:Project_Asset_Relink_Plan
	for asset in registry.assets {expected:=project_asset_record_path(project_root,asset);if !os.is_file(expected) do append(&result.missing,Project_Asset_Missing_Record{asset.id,expected})}
	if len(result.missing)==0||search_root=="" do return result
	walker:=os.walker_create(search_root);defer os.walker_destroy(&walker)
	for info in os.walker_walk(&walker) {if info.type==.Regular {hash,valid:=project_asset_sha256_file(info.fullpath);if !valid.ok do continue;for missing in result.missing {index:=project_asset_index(registry,missing.asset_id);if index>=0&&registry.assets[index].sha256==hash do append(&result.candidates,Project_Asset_Relink_Candidate{missing.asset_id,strings.clone(info.fullpath),hash,true})}}}
	return result
}

project_asset_relink_plan_destroy :: proc(plan:^Project_Asset_Relink_Plan){for &item in plan.candidates do delete(item.candidate_path);delete(plan.missing);delete(plan.candidates);plan^={}}

project_asset_preview_replacement :: proc(registry:^Project_Asset_Registry,id,candidate_path:string)->Project_Asset_Replacement_Preview {
	result:=Project_Asset_Replacement_Preview{asset_id=strings.clone(id),candidate_path=strings.clone(candidate_path)}
	index:=project_asset_index(registry,id)
	if index<0 {result.message="asset does not exist";return result}
	if !os.is_file(candidate_path) {result.message="replacement file does not exist";return result}
	hash,hashed:=project_asset_sha256_file(candidate_path)
	if !hashed.ok {result.message=hashed.message;return result}
	replacement:=project_asset_record_clone(registry.assets[index])
	replacement.source_path=strings.clone(candidate_path)
	replacement.sha256=strings.clone(hash)
	if inspected:=project_asset_inspect_file(candidate_path,&replacement.technical);!inspected.ok {result.message=inspected.message;return result}
	if valid:=project_asset_validate_record(replacement);!valid.ok {result.message=valid.message;return result}
	duplicate:=project_asset_hash_index(registry,hash)
	if duplicate>=0&&duplicate!=index {result.message="replacement duplicates another asset";return result}
	result.candidate_sha256=strings.clone(hash)
	result.replacement=replacement
	result.change=project_asset_change_preview(registry,id)
	result.valid=true
	result.message=fmt.tprintf("READY · %d REFERENCES AND %d DEPENDENTS PRESERVED",len(result.change.usages),len(result.change.dependents))
	return result
}

project_asset_replacement_preview_destroy :: proc(preview:^Project_Asset_Replacement_Preview) {
	project_asset_change_preview_destroy(&preview.change)
	preview^={}
}

project_asset_commit_replacement :: proc(registry:^Project_Asset_Registry,project_root:string,preview:^Project_Asset_Replacement_Preview)->Validation {
	if preview==nil||!preview.valid do return {false,"replacement preview is not ready"}
	index:=project_asset_index(registry,preview.asset_id)
	if index<0 do return {false,"asset changed after replacement preview"}
	hash,hashed:=project_asset_sha256_file(preview.candidate_path)
	if !hashed.ok||hash!=preview.candidate_sha256 do return {false,"replacement candidate changed after preview; review it again"}
	replacement:=preview.replacement
	if replacement.source_mode==.Copy {
		old_destination:=project_asset_record_path(project_root,registry.assets[index])
		directory,_:=filepath.split(old_destination)
		ext:=filepath.ext(preview.candidate_path)
		name:=fmt.tprintf("%s-%s%s",preview.asset_id,hash[:12],ext)
		destination,join_error:=filepath.join([]string{directory,name},context.allocator)
		if join_error!=nil do return {false,"could not create immutable replacement path"}
		if !project_asset_path_within_root(project_root,destination) do return {false,"replacement destination escapes project root"}
		parent,_:=filepath.split(destination);if !os.is_dir(parent)&&os.make_directory_all(parent)!=nil do return {false,"could not create replacement directory"}
		temporary:=fmt.tprintf("%s.asset-replacement.tmp",destination)
		if os.copy_file(temporary,preview.candidate_path)!=nil do return {false,"could not stage replacement in project"}
		staged_hash,checked:=project_asset_sha256_file(temporary)
		if !checked.ok||staged_hash!=hash {_=os.remove(temporary);return {false,"staged replacement failed integrity verification"}}
		if os.rename(temporary,destination)!=nil {_=os.remove(temporary);return {false,"could not atomically install replacement"}}
		replacement.source_path=destination
		relative,rel_error:=filepath.rel(project_root,destination,context.allocator)
		if rel_error!=.None do return {false,"could not record replacement project path"}
		replacement.project_path=relative
	}
	return project_asset_registry_replace(registry,preview.asset_id,replacement)
}

project_asset_apply_relink :: proc(registry:^Project_Asset_Registry,project_root:string,candidate:Project_Asset_Relink_Candidate)->Validation {
	index:=project_asset_index(registry,candidate.asset_id);if index<0||!candidate.exact_hash do return {false,"relink requires an exact hash match"};hash,valid:=project_asset_sha256_file(candidate.candidate_path);if !valid.ok||hash!=registry.assets[index].sha256 do return {false,"relink candidate content has changed"};asset:=&registry.assets[index]
	if asset.source_mode==.Copy {
		if project_asset_path_within_root(project_root,candidate.candidate_path) {
			relative,error:=filepath.rel(project_root,candidate.candidate_path,context.allocator);if error!=.None do return {false,"could not make relink path relative"};asset.project_path=relative
		} else {
		destination:=project_asset_record_path(project_root,asset^);if !project_asset_path_within_root(project_root,destination) do return {false,"copied asset relink destination escapes project root"}
			parent,_:=filepath.split(destination);if !os.is_dir(parent)&&os.make_directory_all(parent)!=nil do return {false,"could not recreate copied asset directory"}
			if os.copy_file(destination,candidate.candidate_path)!=nil do return {false,"could not restore copied asset from exact-hash candidate"}
		}
	} else do asset.source_path=strings.clone(candidate.candidate_path)
	registry.revision+=1;return {true,"ASSET RELINKED"}
}

project_asset_plan_stage :: proc(registry:^Project_Asset_Registry,project_root,package_asset_root:string)->Project_Asset_Stage_Plan {
	result:=Project_Asset_Stage_Plan{allowed=true,attribution_manifest="format = \"ProjectAssetAttribution v1\"\n"}
	for asset in registry.assets {
		if asset.embed_policy==.External do continue
		if asset.embed_policy==.Prohibited||!asset.provenance.redistribution_permitted {result.allowed=false;append(&result.diagnostics,authoring_diagnostic_init(.Assets,"project-assets",asset.id,"embed_policy",.Blocking,"asset cannot be redistributed"));continue}
		source:=project_asset_record_path(project_root,asset);if !os.is_file(source) {result.allowed=false;append(&result.diagnostics,authoring_diagnostic_init(.Assets,"project-assets",asset.id,"project_path",.Blocking,"embedded asset file is missing"));continue}
		hash,valid:=project_asset_sha256_file(source);if !valid.ok||hash!=asset.sha256 {result.allowed=false;append(&result.diagnostics,authoring_diagnostic_init(.Assets,"project-assets",asset.id,"sha256",.Blocking,"embedded asset hash does not match the registry"));continue}
		ext:=filepath.ext(source);package_path,join_error:=filepath.join([]string{package_asset_root,fmt.tprintf("%s%s",asset.id,ext)},context.allocator);if join_error!=nil {result.allowed=false;continue};append(&result.items,Project_Asset_Stage_Item{asset.id,source,package_path,hash,asset.technical.byte_size});result.total_bytes+=asset.technical.byte_size
		result.attribution_manifest=fmt.tprintf("%s\n[[assets]]\nid = \"%s\"\nsha256 = \"%s\"\nsource_uri = \"%s\"\nsource_name = \"%s\"\ncreator = \"%s\"\nattribution = \"%s\"\nlicense_id = \"%s\"\nlicense_text = \"%s\"\n",result.attribution_manifest,project_asset_io_escape(asset.id),asset.sha256,project_asset_io_escape(asset.provenance.source_uri),project_asset_io_escape(asset.provenance.source_name),project_asset_io_escape(asset.provenance.creator),project_asset_io_escape(asset.provenance.attribution),project_asset_io_escape(asset.provenance.license_id),project_asset_io_escape(asset.provenance.license_text))
	}
	for usage in registry.usages do result.attribution_manifest=fmt.tprintf("%s\n[[usages]]\nasset_id = \"%s\"\ndocument = \"%s\"\nentity_id = \"%s\"\nfield_path = \"%s\"\n",result.attribution_manifest,project_asset_io_escape(usage.asset_id),project_asset_io_escape(usage.document),project_asset_io_escape(usage.entity_id),project_asset_io_escape(usage.field_path))
	for usage in registry.external_catalog_usages {
		if !project_external_asset_reference_valid(usage.reference) {result.allowed=false;append(&result.diagnostics,authoring_diagnostic_init(.Compatibility,usage.document,usage.entity_id,usage.field_path,.Blocking,"external catalog requirement is not namespaced and version-pinned"));continue}
		duplicate:=false;for known in result.external_catalog_requirements do if known==usage.reference {duplicate=true;break};if !duplicate do append(&result.external_catalog_requirements,usage.reference)
		result.attribution_manifest=fmt.tprintf("%s\n[[external_catalog_requirements]]\nnamespace = \"%s\"\ncatalog_id = \"%s\"\nversion = \"%s\"\ndocument = \"%s\"\nentity_id = \"%s\"\nfield_path = \"%s\"\n",result.attribution_manifest,project_asset_io_escape(usage.reference.namespace),project_asset_io_escape(usage.reference.catalog_id),project_asset_io_escape(usage.reference.version),project_asset_io_escape(usage.document),project_asset_io_escape(usage.entity_id),project_asset_io_escape(usage.field_path))
	}
	return result
}

project_asset_stage_plan_destroy :: proc(plan:^Project_Asset_Stage_Plan){delete(plan.items);delete(plan.diagnostics);delete(plan.external_catalog_requirements);plan^={}}
