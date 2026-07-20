package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

catalog_refresh_preview_state :: proc(entry: ^Catalog_Entry) {
	if entry == nil || entry.kind != .Object do return
	entry.thumbnail_missing = !os.exists(entry.thumbnail)
	entry.thumbnail_stale = false
	if entry.thumbnail_missing || !entry.valid || entry.image != "" do return
	model_info, model_error := os.stat(entry.model, context.temp_allocator)
	thumbnail_info, thumbnail_error := os.stat(entry.thumbnail, context.temp_allocator)
	if model_error == nil && thumbnail_error == nil do entry.thumbnail_stale = time.to_unix_nanoseconds(model_info.modification_time) > time.to_unix_nanoseconds(thumbnail_info.modification_time)
}

painting_catalog_id :: proc(name: string, index: int) -> string {
	stem, _ := os.split_filename(
		name,
	); builder: strings.Builder; strings.builder_init(&builder, context.allocator); _ = strings.write_string(&builder, "painting_")
	for value in stem {ch := value; if ch >= 'A' && ch <= 'Z' do ch = ch - 'A' + 'a'
		if (ch >= 'a' && ch <= 'z') ||
		   (ch >= '0' &&
				   ch <=
					   '9') {_ = strings.write_byte(&builder, u8(ch))} else if builder.buf[len(builder.buf) - 1] != '_' do _ = strings.write_byte(&builder, '_')}
	result := strings.to_string(
		builder,
	); if result == "painting_" do result = fmt.tprintf("painting_%d", index + 1); return fmt.tprintf("personal:%s", result)
}

catalog_personal_id :: proc(prefix, name: string, index: int) -> string {
	stem, _ := os.split_filename(
		name,
	); builder: strings.Builder; strings.builder_init(&builder, context.allocator); _ = strings.write_string(&builder, prefix); _ = strings.write_byte(&builder, '_')
	for value in stem {ch := value; if ch >= 'A' && ch <= 'Z' do ch = ch - 'A' + 'a'
		if (ch >= 'a' && ch <= 'z') ||
		   (ch >= '0' &&
				   ch <=
					   '9') {_ = strings.write_byte(&builder, u8(ch))} else if builder.buf[len(builder.buf) - 1] != '_' do _ = strings.write_byte(&builder, '_')}
	result := strings.to_string(
		builder,
	); if len(result) == len(prefix) + 1 && strings.has_prefix(result, prefix) && result[len(result) - 1] == '_' do result = fmt.tprintf("%s_%d", prefix, index + 1); return fmt.tprintf("personal:%s", result)
}

catalog_discover_coverings :: proc(
	out: ^Editor_Catalog,
	folder_name, prefix: string,
	floor: bool,
) -> int {
	if out == nil || !out.loaded do return 0
	pictures, pictures_error := os.user_pictures_dir(
		context.temp_allocator,
	); if pictures_error != nil do return 0
	folder, join_error := os.join_path(
		{pictures, "MysteryGame", folder_name},
		context.temp_allocator,
	); if join_error != nil || !os.is_dir(folder) do return 0
	files, read_error := os.read_directory_by_path(
		folder,
		-1,
		context.temp_allocator,
	); if read_error != nil do return 0
	for i in 0 ..< len(
		files,
	) {best := i; for j in i + 1 ..< len(files) do if strings.to_lower(files[j].name) < strings.to_lower(files[best].name) do best = j; if best != i do files[i], files[best] = files[best], files[i]}
	count := 0
	for file in files {
		if file.type == .Directory || strings.has_prefix(strings.to_upper(file.name), "_TEMPLATE") do continue
		ext := strings.to_lower(
			os.ext(file.name),
		); if ext != ".png" && ext != ".jpg" && ext != ".jpeg" do continue
		path, path_error := os.join_path(
			{folder, file.name},
			context.allocator,
		); if path_error != nil do continue
		id := catalog_personal_id(
			prefix,
			file.name,
			count,
		); duplicate := false; for existing in out.entries do if existing.id == id do duplicate = true; if duplicate do id = fmt.tprintf("%s_%d", id, count + 1)
		entry := Catalog_Entry {
			id              = id,
			category        = floor ? "floor coverings" : "wall coverings",
			kind            = .Material,
			thumbnail_index = -1,
			catalog_index   = len(out.entries),
			mesh_index      = -1,
			valid           = true,
		}; if floor do entry.floor = path
		else do entry.wall = path; append(&out.entries, entry); count += 1
	}
	return count
}

catalog_discover_paintings :: proc(out: ^Editor_Catalog) -> int {
	if out == nil || !out.loaded do return 0
	pictures, home_error := os.user_pictures_dir(
		context.temp_allocator,
	); if home_error != nil do return 0
	folder, join_error := os.join_path(
		{pictures, "MysteryGame", "Paintings"},
		context.temp_allocator,
	); if join_error != nil || !os.is_dir(folder) do return 0
	files, read_error := os.read_directory_by_path(
		folder,
		-1,
		context.temp_allocator,
	); if read_error != nil do return 0
	for i in 0 ..< len(
		files,
	) {best := i; for j in i + 1 ..< len(files) do if strings.to_lower(files[j].name) < strings.to_lower(files[best].name) do best = j; if best != i do files[i], files[best] = files[best], files[i]}
	count := 0
	for file in files {
		if file.type == .Directory do continue
		ext := strings.to_lower(
			os.ext(file.name),
		); if ext != ".png" && ext != ".jpg" && ext != ".jpeg" do continue
		path, path_error := os.join_path(
			{folder, file.name},
			context.allocator,
		); if path_error != nil do continue
		id := painting_catalog_id(
			file.name,
			count,
		); duplicate := false; for entry in out.entries do if entry.id == id do duplicate = true; if duplicate do id = fmt.tprintf("%s_%d", id, count + 1)
		entry := Catalog_Entry {
			id                = id,
			category          = "paintings",
			thumbnail         = path,
			image             = path,
			placement         = "indoor",
			front_direction   = "+z",
			dimensions        = {.36, .48, .03},
			clearance_front   = .15,
			surfaces          = []string{"wall"},
			styles            = []string{"custom"},
			affordances       = []string{"display", "wall_decoration"},
			kind              = .Object,
			footprint         = .18,
			default_elevation = 1.2,
			thumbnail_index   = 0,
			catalog_index     = len(out.entries),
			mesh_index        = -1,
			valid             = true,
		}
		object_count := 0; for existing in out.entries do if existing.kind == .Object do object_count += 1; entry.thumbnail_index = object_count; catalog_refresh_preview_state(&entry); append(&out.entries, entry); count += 1
	}
	return count
}

catalog_model_unit_scale :: proc(model: string) -> f32 {return(
		strings.contains(model, "assets/kenney_furniture-kit/") ? 2 : 1 \
	)}

catalog_load_file :: proc(path: string, out: ^Editor_Catalog) -> Validation {cpath, err :=
		strings.clone_to_cstring(path, context.temp_allocator)
	if err != nil do return {false, "invalid catalog path"}
	parsed := toml_parse_file_ex(cpath)
	defer toml_free(parsed)
	if !parsed.ok do return toml_parse_diagnostic(path, "editor catalog", &parsed)
	out.entries = make([dynamic]Catalog_Entry, 0, 64)
	object_index := 0
	for 	t in toml_tables(parsed.toptab, "objects") {id := toml_case_string(t, "id"); thumbnail :=
			toml_case_string(t, "thumbnail")
		if thumbnail == "" do thumbnail = fmt.tprintf("assets/ui/catalog/%s.png", catalog_local_id(id))
		emits_light := toml_case_bool(t, "emits_light")
		dimensions := level_toml_floats(t, "dimensions")
		entry := Catalog_Entry {
			id                = id,
			category          = toml_case_string(t, "category"),
			model             = toml_case_string(t, "model"),
			thumbnail         = thumbnail,
			placement         = toml_case_string(t, "placement"),
			front_direction   = toml_case_string(t, "front_direction"),
			clearance_front   = level_toml_float(t, "clearance_front"),
			clearance_back    = level_toml_float(t, "clearance_back"),
			clearance_left    = level_toml_float(t, "clearance_left"),
			clearance_right   = level_toml_float(t, "clearance_right"),
			surfaces          = toml_case_strings(t, "surfaces"),
			styles            = toml_case_strings(t, "styles"),
			affordances       = toml_case_strings(t, "affordances"),
			kind              = .Object,
			footprint         = level_toml_float(t, "footprint_radius"),
			surface_height    = level_toml_float(t, "surface_height"),
			default_elevation = level_toml_float(t, "default_elevation"),
			emits_light       = emits_light,
			light_kind        = level_light_kind(toml_case_string(t, "light_kind")),
			light_height      = level_toml_float(t, "light_height"),
			light_range       = level_toml_float(t, "light_range"),
			light_intensity   = level_toml_float(t, "light_intensity"),
			light_facing      = level_toml_float(t, "light_facing"),
			light_cone_angle  = level_toml_float(t, "light_cone_angle"),
			light_color       = level_toml_color(t, "light_color"),
			thumbnail_index   = object_index,
			catalog_index     = len(out.entries),
			mesh_index        = -1,
		}
		if len(dimensions) == 3 {unit_scale := catalog_model_unit_scale(entry.model)
			entry.dimensions = {
				dimensions[0] * unit_scale,
				dimensions[1] * unit_scale,
				dimensions[2] * unit_scale,
			}}
		if entry.emits_light {if entry.light_range <= 0 do entry.light_range = 4
			if entry.light_intensity <= 0 do entry.light_intensity = 1
			if entry.light_cone_angle <= 0 do entry.light_cone_angle = 45}
		entry.valid = entry.id != "" && entry.model != "" && os.exists(entry.model)
		catalog_refresh_preview_state(&entry)
		append(&out.entries, entry)
		object_index += 1}
	for 	t in toml_tables(parsed.toptab, "materials") {floor := toml_case_string(t, "floor"); wall :=
			toml_case_string(t, "wall")
		floor_repeat := level_toml_float(t, "floor_repeat_m")
		wall_repeat := level_toml_float(t, "wall_repeat_m")
		if floor_repeat <= 0 do floor_repeat = 5
		if wall_repeat <= 0 do wall_repeat = 2
		entry := Catalog_Entry {
				id              = toml_case_string(t, "id"),
				category        = toml_case_string(t, "category"),
				floor           = floor,
				wall            = wall,
				floor_repeat_m  = floor_repeat,
				wall_repeat_m   = wall_repeat,
				kind            = .Material,
				thumbnail_index = -1,
				catalog_index   = len(out.entries),
				mesh_index      = -1,
				valid           = (floor != "" &&
					os.exists(floor)) || (wall != "" && os.exists(wall)),
			}
		append(&out.entries, entry)}
	out.loaded = true
	return{true, "CATALOG READY"}}

catalog_load_presentations :: proc(path: string, out: ^Editor_Catalog) -> Validation {
	cpath, err := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if err != nil do return {false, "invalid catalog path"}; parsed := toml_parse_file_ex(cpath); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "catalog presentations", &parsed)
	for t in toml_tables(parsed.toptab, "presentation_components") {
		owner := toml_case_string(
			t,
			"owner",
		); entry_index := -1; for candidate, i in out.entries do if candidate.id == owner do entry_index = i
		if entry_index < 0 do return {false, "presentation component references a missing catalog object"}; entry := &out.entries[entry_index]
		if entry.presentation_component_count >= len(entry.presentation_components) do return {false, "catalog presentation has too many components"}
		component := Catalog_Presentation_Component {
			mesh           = toml_case_string(t, "mesh"),
			pose           = toml_case_string(t, "pose"),
			state          = toml_case_string(t, "state"),
			offset         = level_toml_vec3(t, "offset"),
			state_offset   = level_toml_vec3(t, "state_offset"),
			scale          = level_toml_vec3(t, "scale", {1, 1, 1}),
			rotation       = level_toml_float(t, "rotation"),
			state_rotation = level_toml_float(t, "state_rotation"),
			tint           = level_toml_color(t, "tint"),
			layer          = toml_case_int(t, "layer"),
			decal          = toml_case_bool(t, "decal"),
			animated       = toml_case_bool(t, "animated"),
		}
		entry.presentation_components[entry.presentation_component_count] =
			component; entry.presentation_component_count += 1
	}
	return {true, "CATALOG PRESENTATIONS READY"}
}

catalog_load :: proc(path: string, out: ^Editor_Catalog) -> Validation {loaded :=
		catalog_load_file(path, out)
	if !loaded.ok do return loaded
	if presentations := catalog_load_presentations(path, out); !presentations.ok do return presentations
	for 	&entry in out.entries {if !catalog_qualified_id(entry.id) do return {false, "catalog IDs must be namespace-qualified"}
		for &other in out.entries do if &entry != &other && entry.id == other.id do return {false, "catalog contains a duplicate qualified ID"}
		separator := strings.index(entry.id, ":")
		entry.source_namespace = entry.id[:separator]
		entry.source_version = "1"}
	return loaded}

catalog_asset_overrides_path :: proc(project_root: string) -> string {return fmt.tprintf(
		"%s/assets/project-catalog-assets.toml",
		strings.trim_right(project_root, "/"),
	)}
catalog_asset_overrides_serialize :: proc(
	catalog: ^Editor_Catalog,
) -> string {text := "version = \"1\"\n"; if catalog == nil do return text; for 	entry in catalog.entries {if entry.model_asset_ref == "" && entry.material_asset_ref == "" && entry.texture_asset_ref == "" do continue
		text = fmt.tprintf(
			"%s\n[[entries]]\nid = \"%s\"\nmodel_asset_ref = \"%s\"\nmaterial_asset_ref = \"%s\"\ntexture_asset_ref = \"%s\"\n",
			text,
			level_quote(entry.id),
			level_quote(entry.model_asset_ref),
			level_quote(entry.material_asset_ref),
			level_quote(entry.texture_asset_ref),
		)}
	return text}
catalog_asset_overrides_save :: proc(
	project_root: string,
	catalog: ^Editor_Catalog,
) -> Validation {if project_root == "" || catalog == nil do return {false, "project catalog asset overrides require a source project"}
	path := catalog_asset_overrides_path(project_root)
	directory := os.dir(path)
	if !os.is_dir(directory) && os.make_directory_all(directory) != nil do return {false, "could not create project catalog asset directory"}
	if os.write_entire_file(path, transmute([]u8)catalog_asset_overrides_serialize(catalog)) != nil do return {false, "could not save project catalog asset overrides"}
	return{true, "PROJECT CATALOG ASSET REFERENCES SAVED"}}
catalog_asset_overrides_load :: proc(
	project_root: string,
	catalog: ^Editor_Catalog,
) -> Validation {if project_root == "" || catalog == nil do return {false, "project catalog asset overrides require a source project"}
	path := catalog_asset_overrides_path(project_root)
	if !os.is_file(path) do return {true, "NO PROJECT CATALOG ASSET OVERRIDES"}
	cpath, err := strings.clone_to_cstring(path, context.temp_allocator)
	if err != nil do return {false, "invalid project catalog asset override path"}
	parsed := toml_parse_file_ex(cpath)
	defer toml_free(parsed)
	if !parsed.ok do return toml_parse_diagnostic(path, "project catalog asset overrides", &parsed)
	for 	table in toml_tables(parsed.toptab, "entries") {id := toml_case_string(table, "id"); for &entry in catalog.entries do if entry.id == id {entry.model_asset_ref = toml_case_string(table, "model_asset_ref"); entry.material_asset_ref = toml_case_string(table, "material_asset_ref"); entry.texture_asset_ref = toml_case_string(table, "texture_asset_ref"); break}}
	return{true, "PROJECT CATALOG ASSET REFERENCES LOADED"}}

catalog_qualified_id :: proc(id: string) -> bool {separator := strings.index(id, ":"); return(
		separator > 0 &&
		separator < len(id) - 1 &&
		strings.index(id[separator + 1:], ":") < 0 \
	)}
catalog_local_id :: proc(id: string) -> string {separator := strings.index(id, ":")
	if separator >= 0 && separator < len(id) - 1 do return id[separator + 1:]
	return id}
catalog_resolve_id :: proc(id: string) -> string {if catalog_qualified_id(id) do return id
	return fmt.tprintf("core:%s", id)}
catalog_merge :: proc(
	path: string,
	out: ^Editor_Catalog,
	namespace, version: string,
) -> Validation {if out == nil || namespace == "" || namespace == "core" do return {false, "expansion catalog requires a non-core namespace"}
	incoming: Editor_Catalog
	if loaded := catalog_load(path, &incoming); !loaded.ok do return loaded
	defer delete(incoming.entries)
	prefix := fmt.tprintf("%s:", namespace)
	for 	&entry in incoming.entries {if !catalog_qualified_id(entry.id) || !strings.has_prefix(entry.id, prefix) do return {false, "expansion catalog contains an ID outside its namespace"}
		for existing in out.entries do if existing.id == entry.id do return {false, "catalog merge contains a duplicate qualified ID"}}
	object_index := 0
	for existing in out.entries do if existing.kind == .Object do object_index += 1
	for 	entry in incoming.entries {copy := entry; copy.source_namespace = namespace; copy.source_version =
			version
		copy.catalog_index = len(out.entries)
		if copy.kind == .Object {copy.thumbnail_index = object_index; object_index += 1}
		append(&out.entries, copy)}
	out.loaded = true
	return{true, "CATALOG MERGED"}}

catalog_merge_installed :: proc(out: ^Editor_Catalog) -> Validation {data_dir, data_error :=
		os.user_data_dir(context.temp_allocator)
	if data_error != nil do return {true, "NO EXPANSION CATALOGS"}
	registry, path_error := os.join_path(
		[]string{data_dir, APP_STORAGE_NAME, "Expansions", "catalog-registry.toml"},
		context.temp_allocator,
	)
	if path_error != nil || !os.is_file(registry) do return {true, "NO EXPANSION CATALOGS"}
	cpath, clone_error := strings.clone_to_cstring(registry, context.temp_allocator)
	if clone_error != nil do return {false, "invalid expansion catalog registry path"}
	parsed := toml_parse_file_ex(cpath)
	defer toml_free(parsed)
	if !parsed.ok do return toml_parse_diagnostic(registry, "expansion catalog registry", &parsed)
	for 	table in toml_tables(parsed.toptab, "expansions") {namespace := toml_case_string(table, "namespace")
		version := toml_case_string(table, "version")
		for 		path in toml_case_strings(table, "catalogs") {merged := catalog_merge(
				path,
				out,
				namespace,
				version,
			)
			if !merged.ok do return merged}}
	return{true, "EXPANSION CATALOGS MERGED"}}

catalog_is_recent :: proc(state: ^Editor_State, id: string) -> bool {resolved :=
		catalog_resolve_id(id)
	for recent in state.catalog_recent[:state.catalog_recent_count] do if recent == resolved do return true
	return false}
catalog_record_recent :: proc(state: ^Editor_State, id: string) {if id == "" do return; resolved :=
		catalog_resolve_id(id)
	write := 0
	next: [8]string
	next[write] = resolved
	write += 1
	for 	recent in state.catalog_recent[:state.catalog_recent_count] {if recent == resolved do continue
		if write >= len(next) do break
		next[write] = recent
		write += 1}
	state.catalog_recent = next
	state.catalog_recent_count = write}
catalog_is_pinned :: proc(state: ^Editor_State, id: string) -> bool {resolved :=
		catalog_resolve_id(id)
	for pinned in state.catalog_pinned[:state.catalog_pinned_count] do if pinned == resolved do return true
	return false}
catalog_toggle_pinned :: proc(state: ^Editor_State, id: string) -> bool {if id == "" do return false
	resolved := catalog_resolve_id(id)
	for 	pinned, i in state.catalog_pinned[:state.catalog_pinned_count] {if pinned != resolved do continue; for j in i ..< state.catalog_pinned_count - 1 do state.catalog_pinned[j] = state.catalog_pinned[j + 1]
		state.catalog_pinned_count -= 1
		state.catalog_pinned[state.catalog_pinned_count] = ""
		return false}
	if state.catalog_pinned_count < len(state.catalog_pinned) {state.catalog_pinned[state.catalog_pinned_count] =
			resolved
		state.catalog_pinned_count += 1
		return true}
	return false}
catalog_search_text :: proc(state: ^Editor_State) -> string {return string(
		state.search_buffer[:state.search_count],
	)}
catalog_clear_search :: proc(state: ^Editor_State) {state.search_count = 0; state.catalog_page = 0
	state.search_active = true}
catalog_append_search_char :: proc(state: ^Editor_State, ch: u8) -> bool {
	if state.search_count >= len(state.search_buffer) do return false
	value := ch
	if value >= 'A' && value <= 'Z' do value = value - 'A' + 'a'
	if !((value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') || value == '_' || value == '-') do return false
	state.search_buffer[state.search_count] = value
	state.search_count += 1
	state.catalog_page = 0
	return true
}
catalog_object_entry :: proc(id: string) -> (^Catalog_Entry, bool) {resolved := catalog_resolve_id(
		id,
	)
	for &entry in editor_catalog.entries do if entry.kind == .Object && entry.id == resolved do return &entry, true
	return nil, false}
level_object_support_at :: proc(
	doc: ^Level_Document,
	point: Vec2,
	placed_catalog_id: string,
) -> (
	string,
	f32,
	bool,
) {
	placed, placed_ok := catalog_object_entry(
		placed_catalog_id,
	); if !placed_ok do return "", 0, false
	best_id := ""; best_height := f32(-1); best_distance := f32(1e30)
	for object in doc.objects {
		if object.story != doc.active_story || object.support_id != "" do continue
		host, host_ok := catalog_object_entry(
			object.catalog_id,
		); if !host_ok || host.surface_height <= 0 do continue
		host_radius := max(
			host.footprint,
			.2,
		); placed_radius := max(placed.footprint, .2); dx, dy := point.x - object.position.x, point.y - object.position.y; distance := dx * dx + dy * dy
		if placed_radius > host_radius * .72 || distance > (host_radius - placed_radius * .55) * (host_radius - placed_radius * .55) do continue
		height := object.elevation + host.surface_height
		if height > best_height + .001 ||
		   math.abs(height - best_height) <= .001 &&
			   distance <
				   best_distance {best_id = object.id; best_height = height; best_distance = distance}
	}
	return best_id, best_height, best_id != ""
}
catalog_entry_kind :: proc(id: string) -> (Catalog_Entry_Kind, bool) {for entry in editor_catalog.entries do if entry.id == id do return entry.kind, true
	return .Object, false}
catalog_entry_selectable :: proc(entry: Catalog_Entry) -> bool {return entry.valid}

editor_select_first_catalog_match :: proc(g: ^Game) -> bool {
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry, &editor_state) || !catalog_entry_selectable(entry) do continue
		editor_state.catalog_id =
			entry.id; editor_state.paint_eyedropper = false; editor_state.search_active = false; catalog_record_recent(&editor_state, entry.id)
		if entry.kind ==
		   .Object {g.build_tool = .Plant; editor_state.placement_rotation = 0} else do g.build_tool = .Paint
		return true
	}
	return false
}
catalog_entry_matches :: proc(entry: Catalog_Entry, state: ^Editor_State) -> bool {
	category :=
		state.catalog_category; if category != "" && category != "all" {if category == "objects" && entry.kind != .Object do return false; if category == "materials" && entry.kind != .Material do return false; if category == "recent" && !catalog_is_recent(state, entry.id) do return false; if category == "pinned" && !catalog_is_pinned(state, entry.id) do return false; if category != "objects" && category != "materials" && category != "recent" && category != "pinned" && entry.category != category do return false}
	query := catalog_search_text(
		state,
	); if query != "" && !strings.contains(strings.to_lower(entry.id), query) && !strings.contains(strings.to_lower(entry.category), query) do return false
	return true
}
catalog_match_count :: proc(state: ^Editor_State) -> int {count := 0; for entry in editor_catalog.entries do if catalog_entry_matches(entry, state) do count += 1
	return count}
catalog_page_count :: proc(state: ^Editor_State, page_size := 9) -> int {return max(
		1,
		(catalog_match_count(state) + page_size - 1) / page_size,
	)}
catalog_clamp_page :: proc(state: ^Editor_State, page_size := 9) {state.catalog_page = clamp(
		state.catalog_page,
		0,
		catalog_page_count(state, page_size) - 1,
	)}

level_commit :: proc(doc: ^Level_Document, command: Level_Command, label: string) -> bool {
	before := level_clone_document(
		doc,
	); _, ok := level_apply_raw(doc, command); if !ok do return false
	if level_history.undo_count >=
	   LEVEL_HISTORY_CAPACITY {for i in 1 ..< LEVEL_HISTORY_CAPACITY do level_history.undo[i - 1] = level_history.undo[i]; level_history.undo_count -= 1}
	doc.revision += 1; doc.dirty = true; _ = level_validate(doc); _ = authoring_invalidate_after_edit(.Level, doc.revision); after := level_clone_document(doc); level_history.undo[level_history.undo_count] = Level_Change_Set{before, after, label}; level_history.undo_count += 1; level_history.redo_count = 0; editor_state.dirty = {
		terrain      = command.kind == .Sculpt_Terrain,
		architecture = true,
		navigation   = true,
		lighting     = true,
		ui           = true,
		min          = {min(command.a.x, command.b.x), min(command.a.y, command.b.y)},
		max          = {max(command.a.x, command.b.x), max(command.a.y, command.b.y)},
	}; if command.kind ==
	   .Sculpt_Terrain {editor_state.dirty.min.x -= command.value; editor_state.dirty.min.y -= command.value; editor_state.dirty.max.x += command.value; editor_state.dirty.max.y += command.value}; if level_transaction_projection_enabled do level_project_to_runtime(doc); _ = level_autosave(doc); return true
}
level_undo :: proc(doc: ^Level_Document) -> bool {if level_history.undo_count <= 0 do return false
	level_history.undo_count -= 1
	change := level_history.undo[level_history.undo_count]
	doc^ = level_clone_document(&change.before)
	doc.dirty = true
	level_history.redo[level_history.redo_count] = change
	level_history.redo_count += 1
	editor_state.dirty = {
		terrain      = true,
		architecture = true,
		navigation   = true,
		lighting     = true,
		ui           = true,
		min          = {},
		max          = {f32(doc.width), f32(doc.height)},
	}
	if level_transaction_projection_enabled do level_project_to_runtime(doc)
	return true}
level_redo :: proc(doc: ^Level_Document) -> bool {if level_history.redo_count <= 0 do return false
	level_history.redo_count -= 1
	change := level_history.redo[level_history.redo_count]
	doc^ = level_clone_document(&change.after)
	doc.dirty = true
	level_history.undo[level_history.undo_count] = change
	level_history.undo_count += 1
	editor_state.dirty = {
		terrain      = true,
		architecture = true,
		navigation   = true,
		lighting     = true,
		ui           = true,
		min          = {},
		max          = {f32(doc.width), f32(doc.height)},
	}
	if level_transaction_projection_enabled do level_project_to_runtime(doc)
	return true}

level_preview_transaction :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {return level_command_preview(doc, command)}
level_commit_transaction :: proc(
	doc: ^Level_Document,
	command: Level_Command,
	label: string,
) -> bool {return level_commit(doc, command, label)}

// Stable headless boundary for agent object edits. This intentionally shares
// Build Mode's preview, apply, validation, snapping, catalog, and serializer.
agent_object_transaction :: proc(args: []string) -> int {
	// mode level catalog_manifest id catalog_id x y elevation rotation support story
	if len(args) !=
	   11 {fmt.eprintln("usage: --agent-object-transaction preview|commit LEVEL CATALOG_MANIFEST ID CATALOG_ID X Y ELEVATION ROTATION SUPPORT STORY"); return 2}
	mode, level_path, catalog_path, object_id, catalog_id :=
		args[0], args[1], args[2], args[3], args[4]
	x, x_ok := strconv.parse_f32(
		args[5],
	); y, y_ok := strconv.parse_f32(args[6]); elevation, elevation_ok := strconv.parse_f32(args[7]); rotation, rotation_ok := strconv.parse_f32(args[8]); story64, story_ok := strconv.parse_i64(args[10])
	if !x_ok ||
	   !y_ok ||
	   !elevation_ok ||
	   !rotation_ok ||
	   !story_ok {fmt.eprintln("invalid numeric agent transaction argument"); return 2}
	doc: Level_Document; if loaded := level_load(level_path, &doc); !loaded.ok {fmt.eprintln(loaded.message); return 2}
	catalog: Editor_Catalog; if loaded := catalog_load(catalog_path, &catalog); !loaded.ok {fmt.eprintln(loaded.message); return 2}; editor_catalog = catalog
	if level_object_index(&doc, object_id) >=
	   0 {fmt.eprintln("duplicate object ID: ", object_id); return 2}
	doc.active_story = clamp(int(story64), 0, max(len(doc.stories) - 1, 0))
	command := Level_Command {
		kind        = .Place_Object,
		entity_id   = object_id,
		a           = {x, y},
		c           = {elevation, 0},
		value       = rotation,
		material    = catalog_id,
		destination = args[9],
	}
	result := level_preview_transaction(
		&doc,
		command,
	); state := "valid"; if result.state == .Warning do state = "warning"
	else if result.state == .Blocked do state = "blocked"; snapped := level_snap_point(&doc, command.a, true)
	fmt.printf(
		"{{\"state\":\"%s\",\"message\":\"%s\",\"position\":[%.3f,%.3f]}}\n",
		state,
		level_quote(result.message),
		snapped.x,
		snapped.y,
	)
	if result.state == .Blocked do return 2
	if mode == "preview" do return 0
	if mode != "commit" {fmt.eprintln("transaction mode must be preview or commit"); return 2}
	_, applied := level_apply_raw(
		&doc,
		command,
	); if !applied {fmt.eprintln("could not apply object transaction"); return 2}; doc.revision += 1
	if checked := level_validate(&doc); !checked.ok {fmt.eprintln(checked.message); return 2}
	if saved := level_save(level_path, &doc); !saved.ok {fmt.eprintln(saved.message); return 2}
	return 0
}

agent_level_validate :: proc(path: string) -> int {
	doc: Level_Document; if loaded := level_load(path, &doc); !loaded.ok {fmt.printf("{{\"valid\":false,\"message\":\"%s\"}}\n", level_quote(loaded.message)); return 2}
	checked := level_validate(
		&doc,
	); fmt.printf("{{\"valid\":%s,\"message\":\"%s\",\"diagnostic_count\":%d}}\n", checked.ok ? "true" : "false", level_quote(checked.message), len(doc.diagnostics)); return checked.ok ? 0 : 2
}
level_commit_transactions :: proc(
	doc: ^Level_Document,
	commands: []Level_Command,
	label: string,
) -> bool {
	if len(commands) == 0 do return false; before := level_clone_document(doc); work := level_clone_document(doc); for command in commands {if level_preview_transaction(&work, command).state == .Blocked do return false; _, ok := level_apply_raw(&work, command); if !ok do return false; work.revision += 1}; work.dirty = true; _ = level_validate(&work); if level_history.undo_count >= LEVEL_HISTORY_CAPACITY {for i in 1 ..< LEVEL_HISTORY_CAPACITY do level_history.undo[i - 1] = level_history.undo[i]; level_history.undo_count -= 1}; after := level_clone_document(&work); level_history.undo[level_history.undo_count] = Level_Change_Set{before, after, label}; level_history.undo_count += 1; level_history.redo_count = 0; doc^ = work; _ = authoring_invalidate_after_edit(.Level, doc.revision); editor_state.dirty = {
		architecture = true,
		navigation   = true,
		lighting     = true,
		ui           = true,
	}; if level_transaction_projection_enabled do level_project_to_runtime(doc); _ = level_autosave(doc); return true
}

editor_selection_index :: proc(state: ^Editor_State, selection: Editor_Selection) -> int {for known, i in state.selection[:state.selection_count] do if known.kind == selection.kind && known.entity_id == selection.entity_id && known.sub_index == selection.sub_index do return i
	return -1}
editor_selection_toggle :: proc(
	state: ^Editor_State,
	selection: Editor_Selection,
) -> bool {index := editor_selection_index(state, selection); if index >= 0 {for i in index + 1 ..< state.selection_count do state.selection[i - 1] = state.selection[i]
		state.selection_count -= 1
		return false}
	if state.selection_count >= len(state.selection) do return false
	state.selection[state.selection_count] = selection
	state.selection_count += 1
	return true}
level_box_append :: proc(
	out: ^[16]Editor_Selection,
	count: ^int,
	selection: Editor_Selection,
	point, min_bound, max_bound: Vec2,
) {if count^ >= len(out^) || point.x < min_bound.x || point.x > max_bound.x || point.y < min_bound.y || point.y > max_bound.y do return
	out[count^] = selection
	count^ += 1}
level_select_box :: proc(doc: ^Level_Document, a, b: Vec2, out: ^[16]Editor_Selection) -> int {
	min_bound := Vec2 {
		min(a.x, b.x),
		min(a.y, b.y),
	}; max_bound := Vec2{max(a.x, b.x), max(a.y, b.y)}; count := 0
	for marker in doc.markers do if marker.story == doc.active_story do level_box_append(out, &count, {.Marker, marker.id, -1}, marker.position, min_bound, max_bound)
	for light in doc.lights do if light.story == doc.active_story do level_box_append(out, &count, {.Light, light.id, -1}, light.position, min_bound, max_bound)
	for object in doc.objects do if object.story == doc.active_story do level_box_append(out, &count, {.Object, object.id, -1}, object.position, min_bound, max_bound)
	for &room in doc.rooms do if room.story == doc.active_story do level_box_append(out, &count, {.Room, room.id, -1}, level_room_center(&room), min_bound, max_bound)
	for path in doc.paths do if path.story == doc.active_story && len(path.points) > 0 {center := Vec2{}; for p in path.points {center.x += p.x; center.y += p.y}; center.x /= f32(len(path.points)); center.y /= f32(len(path.points)); level_box_append(out, &count, {.Path, path.id, -1}, center, min_bound, max_bound)}
	return count
}

level_nudge_selection :: proc(
	doc: ^Level_Document,
	selection: Editor_Selection,
	delta: Vec2,
) -> bool {
	#partial switch selection.kind {
	case .Foundation:
		return level_commit_transaction(
			doc,
			Level_Command{kind = .Delete_Foundation, entity_id = selection.entity_id},
			"Delete foundation",
		)
	case .Room:
		return level_commit_transaction(
			doc,
			Level_Command{kind = .Move_Room, entity_id = selection.entity_id, a = delta},
			"Move room",
		)
	case .Object:
		index := level_object_index(doc, selection.entity_id); if index < 0 do return false
		object := doc.objects[index]
		return level_commit_transaction(
			doc,
			Level_Command {
				kind = .Move_Object,
				entity_id = selection.entity_id,
				a = {object.position.x + delta.x, object.position.y + delta.y},
				value = object.rotation,
			},
			"Move object",
		)
	case .Marker:
		index := level_marker_index(doc, selection.entity_id); if index < 0 do return false
		command := marker_edit_command(doc.markers[index])
		command.a.x += delta.x
		command.a.y += delta.y
		return level_commit_transaction(doc, command, "Move marker")
	case .Light:
		index := level_light_index(doc, selection.entity_id); if index < 0 do return false
		command := light_edit_command(doc.lights[index])
		command.a.x += delta.x
		command.a.y += delta.y
		return level_commit_transaction(doc, command, "Move light")
	case:
		return false
	}
}

level_selection_move_command :: proc(
	doc: ^Level_Document,
	selection: Editor_Selection,
	delta: Vec2,
) -> (
	Level_Command,
	bool,
) {
	#partial switch selection.kind {
	case .Room:
		return Level_Command{kind = .Move_Room, entity_id = selection.entity_id, a = delta}, true
	case .Foundation:
		point_index := editor_control_point_index(selection)
		index := level_foundation_index(doc, selection.entity_id)
		if index < 0 || point_index < 0 || point_index >= len(doc.foundations[index].points) do return {}, false
		point := doc.foundations[index].points[point_index]
		return Level_Command {
				kind = .Move_Foundation_Point,
				entity_id = selection.entity_id,
				a = level_snap_point(doc, {point.x + delta.x, point.y + delta.y}, true),
				value = f32(point_index),
			},
			true
	case .Vertex:
		index := level_room_index(doc, selection.entity_id)
		if index < 0 || selection.sub_index < 0 || selection.sub_index >= len(doc.rooms[index].points) do return {}, false
		point := doc.rooms[index].points[selection.sub_index]
		return Level_Command {
				kind = .Move_Room_Vertex,
				entity_id = selection.entity_id,
				a = level_snap_point(doc, {point.x + delta.x, point.y + delta.y}, true),
				value = f32(selection.sub_index),
			},
			true
	case .Edge:
		return Level_Command {
				kind = .Move_Room_Edge,
				entity_id = selection.entity_id,
				a = delta,
				value = f32(selection.sub_index),
			},
			true
	case .Path:
		point_index := editor_control_point_index(selection)
		index := level_path_index(doc, selection.entity_id)
		if index < 0 || point_index < 0 || point_index >= len(doc.paths[index].points) do return {}, false
		point := doc.paths[index].points[point_index]
		return Level_Command {
				kind = .Move_Path_Point,
				entity_id = selection.entity_id,
				a = level_snap_point(doc, {point.x + delta.x, point.y + delta.y}, true),
				value = f32(point_index),
			},
			true
	case .Water:
		point_index := editor_control_point_index(selection)
		index := level_water_index(doc, selection.entity_id)
		if index < 0 || point_index < 0 || point_index >= len(doc.waters[index].points) do return {}, false
		point := doc.waters[index].points[point_index]
		return Level_Command {
				kind = .Move_Water_Point,
				entity_id = selection.entity_id,
				a = level_snap_point(doc, {point.x + delta.x, point.y + delta.y}, true),
				value = f32(point_index),
			},
			true
	case .Vertical_Link:
		point_index := editor_control_point_index(selection)
		index := level_vertical_link_index(doc, selection.entity_id)
		if index < 0 || point_index < 0 || point_index > 1 do return {}, false
		point :=
			point_index == 0 ? doc.vertical_links[index].start : doc.vertical_links[index].finish
		return Level_Command {
				kind = .Move_Vertical_Link_Point,
				entity_id = selection.entity_id,
				a = level_snap_point(doc, {point.x + delta.x, point.y + delta.y}, true),
				value = f32(point_index),
			},
			true
	case .Object:
		index := level_object_index(doc, selection.entity_id); if index < 0 do return {}, false
		object := doc.objects[index]
		return Level_Command {
				kind = .Move_Object,
				entity_id = selection.entity_id,
				a = {object.position.x + delta.x, object.position.y + delta.y},
				value = object.rotation,
			},
			true
	case .Marker:
		index := level_marker_index(doc, selection.entity_id); if index < 0 do return {}, false
		command := marker_edit_command(doc.markers[index])
		command.a.x += delta.x
		command.a.y += delta.y
		return command, true
	case .Light:
		index := level_light_index(doc, selection.entity_id); if index < 0 do return {}, false
		command := light_edit_command(doc.lights[index])
		command.a.x += delta.x
		command.a.y += delta.y
		return command, true
	case .Opening:
		index := level_opening_index(doc, selection.entity_id); if index < 0 do return {}, false
		opening := doc.openings[index]
		path_index := level_path_index(doc, opening.host_path)
		if path_index < 0 || opening.segment < 0 || opening.segment >= len(doc.paths[path_index].points) - 1 do return {}, false
		a, b :=
			doc.paths[path_index].points[opening.segment],
			doc.paths[path_index].points[opening.segment + 1]
		dx, dy := b.x - a.x, b.y - a.y
		length_sq := dx * dx + dy * dy
		if length_sq <= .0001 do return {}, false
		center := Vec2 {
			a.x + dx * opening.position + delta.x,
			a.y + dy * opening.position + delta.y,
		}
		position := ((center.x - a.x) * dx + (center.y - a.y) * dy) / length_sq
		command := level_opening_edit_command(opening)
		command.c.x = position
		return command, true
	case:
		return {}, false
	}
}

level_snap_delta :: proc(doc: ^Level_Document, delta: Vec2) -> Vec2 {if editor_state.snap_mode == .Off || editor_state.snap_suspended do return delta
	step := editor_state.snap_mode == .Fine ? doc.fine_snap : doc.default_snap
	if step <= 0 do return delta
	return{
		f32(math.round(f64(delta.x / step))) * step,
		f32(math.round(f64(delta.y / step))) * step,
	}}
level_story_below :: proc(doc: ^Level_Document, story: int) -> int {if story < 0 || story >= len(doc.stories) do return -1
	current := doc.stories[story].base_elevation
	best := -1
	best_elevation := f32(-1000000)
	for candidate, i in doc.stories do if candidate.base_elevation < current - .01 && candidate.base_elevation > best_elevation {best = i; best_elevation = candidate.base_elevation}
	return best}
level_story_above :: proc(doc: ^Level_Document, story: int) -> int {if story < 0 || story >= len(doc.stories) do return -1
	current := doc.stories[story].base_elevation
	best := -1
	best_elevation := f32(1000000)
	for candidate, i in doc.stories do if candidate.base_elevation > current + .01 && candidate.base_elevation < best_elevation {best = i; best_elevation = candidate.base_elevation}
	return best}
level_can_create_attic :: proc(doc: ^Level_Document) -> bool {return(
		len(doc.stories) > 0 &&
		len(doc.stories) < doc.story_limit &&
		level_story_above(doc, doc.active_story) < 0 \
	)}
level_create_attic_story :: proc(doc: ^Level_Document) -> bool {if !level_can_create_attic(doc) do return false
	source := doc.stories[doc.active_story]
	index := len(doc.stories)
	append(
		&doc.stories,
		Level_Story {
			id = fmt.tprintf("attic_%d", index),
			name = "Attic",
			base_elevation = source.base_elevation + source.wall_height,
			wall_height = 2.4,
		},
	)
	doc.active_story = index
	doc.revision += 1
	doc.dirty = true
	editor_state.selection_count = 0
	level_project_to_runtime(doc)
	_ = level_autosave(doc)
	return true}
level_story_label :: proc(doc: ^Level_Document, story: int) -> string {if story < 0 || story >= len(doc.stories) do return "STORY"
	elevation := doc.stories[story].base_elevation
	if math.abs(elevation) <= .01 do return "GROUND"
	if elevation < 0 {rank := 1; for candidate in doc.stories do if candidate.base_elevation < -.01 && candidate.base_elevation > elevation + .01 do rank += 1
		return fmt.tprintf("B%d", rank)}
	rank := 1
	for candidate in doc.stories do if candidate.base_elevation > .01 && candidate.base_elevation < elevation - .01 do rank += 1
	return fmt.tprintf("FLOOR %d", rank + 1)}
level_set_active_story :: proc(doc: ^Level_Document, story: int) -> bool {if len(doc.stories) == 0 || story < 0 || story >= len(doc.stories) do return false
	if story == doc.active_story do return false
	doc.active_story = story
	editor_state.selection_count = 0
	editor_state.room_draw_count = 0
	level_project_to_runtime(doc)
	return true}

level_delete_selection :: proc(doc: ^Level_Document, selection: Editor_Selection) -> bool {
	#partial switch selection.kind {
	case .Room:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Room, entity_id = selection.entity_id},
			"Delete room",
			"ROOM",
		)
	case .Object:
		return editor_delete_command(
			doc,
			Level_Command {
				kind = .Delete_Object,
				entity_id = selection.entity_id,
				material = "object",
			},
			"Delete object",
			"OBJECT",
		)
	case .Path:
		return editor_delete_command(
			doc,
			Level_Command {
				kind = .Delete_Object,
				entity_id = selection.entity_id,
				material = "path",
			},
			"Delete path",
			"PATH",
		)
	case .Opening:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Opening, entity_id = selection.entity_id},
			"Delete opening",
			"OPENING",
		)
	case .Roof:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Roof, entity_id = selection.entity_id},
			"Delete roof",
			"ROOF",
		)
	case .Vertical_Link:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Vertical_Link, entity_id = selection.entity_id},
			"Delete vertical link",
			"VERTICAL LINK",
		)
	case .Water:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Water, entity_id = selection.entity_id},
			"Delete pond",
			"POND",
		)
	case .Marker:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Marker, entity_id = selection.entity_id},
			"Delete marker",
			"MARKER",
		)
	case .Light:
		return editor_delete_command(
			doc,
			Level_Command{kind = .Delete_Light, entity_id = selection.entity_id},
			"Delete light",
			"LIGHT",
		)
	case:
		return false
	}
}
level_rebuild_dirty :: proc(doc: ^Level_Document, dirty: Dirty_Regions) {if dirty.architecture || dirty.navigation || dirty.terrain do level_project_to_runtime(doc)
	editor_state.dirty = {}}
level_project_runtime :: proc(doc: ^Level_Document) {level_project_to_runtime(doc)}
level_material_surface :: proc(material: string) -> Room_Surface {if strings.contains(material, "study") do return .Study
	if strings.contains(material, "gallery") do return .Gallery
	if strings.contains(material, "pantry") do return .Pantry
	if strings.contains(material, "garden") do return .Garden
	return .Dining}

level_project_to_runtime :: proc(doc: ^Level_Document) {
	house_plan.initialized = true
	house_plan.level = doc.active_story
	// Document objects are the sole furniture source. Keep the legacy runtime
	// collection empty so authored pieces are never duplicated behind the editor.
	clear(&house_plan.furniture)
	// Project room material and open-air state before building geometry. This
	// makes the level document authoritative for both floor finishes and Sims-
	// style interior exteriors instead of relying on the sample-house classifier.
	// Unauthored exterior cells are terrain, not a Garden-finished room. Give
	// them a non-Garden sentinel surface so the floor-batch renderer leaves the
	// grass terrain visible; authored exterior rooms below still project their
	// requested finish (the Moon Garden uses Garden flagstone).
	for y in 0 ..< HOUSE_SURFACE_HEIGHT {for x in 0 ..< HOUSE_SURFACE_WIDTH {house_plan.surfaces[y * HOUSE_SURFACE_WIDTH + x] = .Dining; house_plan.space_kinds[y * HOUSE_SURFACE_WIDTH + x] = .Grounds}}
	for room in doc.rooms {if room.story != doc.active_story || len(room.points) < 3 do continue
		surface := level_material_surface(room.floor_material)
		for y in 0 ..< HOUSE_SURFACE_HEIGHT {for x in 0 ..< HOUSE_SURFACE_WIDTH {px, py := f32(x) + .5, f32(y) + .5; inside := false; j := len(room.points) - 1; for i in 0 ..< len(room.points) {a, b := room.points[i], room.points[j]; if (a.y > py) != (b.y > py) && px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x do inside = !inside; j = i}; if inside {house_plan.surfaces[y * HOUSE_SURFACE_WIDTH + x] = surface; house_plan.space_kinds[y * HOUSE_SURFACE_WIDTH + x] = room.exterior ? .Grounds : .Interior}}}
	}
	rebuild_house_wall_splines(doc, doc.active_story)
	clear(
		&house_plan.wall_face_paints,
	); for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 {a, b := spline.points[i], spline.points[i + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length <= .01 do continue; mx, my := (a.x + b.x) * .5, (a.y + b.y) * .5; nx, ny := -dy / length, dx / length; for side in 0 ..< 2 {positive := side == 0; sign := positive ? f32(1) : f32(-1); sample := Vec2{mx + nx * .24 * sign, my + ny * .24 * sign}; for room in doc.rooms {if room.story == doc.active_story && level_point_in_polygon(sample, room.points[:]) {append(&house_plan.wall_face_paints, Wall_Face_Paint{a, b, positive, level_material_surface(room.wall_material)}); break}}}}}
	clear(
		&house_plan.openings,
	); for opening in doc.openings {for path in doc.paths do if path.story == doc.active_story && path.id == opening.host_path && opening.segment >= 0 && opening.segment < len(path.points) - 1 {a, b := path.points[opening.segment], path.points[opening.segment + 1]; t := clamp(opening.position, 0, 1); dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length <= .01 do continue; half := opening.width * .5 / length; center := clamp(t, half, 1 - half); kind := Opening_Kind.Door; if opening.kind == .Window do kind = .Window; append(&house_plan.openings, Plan_Opening{a = {a.x + dx * (center - half), a.y + dy * (center - half)}, b = {a.x + dx * (center + half), a.y + dy * (center + half)}, kind = kind, id = opening.id, height = opening.height, sill_height = opening.sill_height, wall_width = house_wall_width(path.width), door_material = opening.door_material, door_style = opening.door_style, window_style = opening.window_style, window_flipped = opening.window_flipped, window_hinge_right = opening.window_hinge_right})}}
	house_plan.revision = int(
		doc.revision,
	); house_plan.dirty = true; build_house_floorplan(); rebuild_personal_surfaces(doc); rebuild_generated_roofs(doc); build_house_navmesh(); rebuild_generated_links(doc); rebuild_generated_ground(doc); rebuild_generated_stories(doc); if len(active_story_project.entities) > 0 do _ = world_entities_rebuild(&active_story_project, doc)
}

level_editor_initialize :: proc() -> Validation {if synced := level_sync_legacy_source_path(); !synced.ok do return synced
	validation := level_load(level_active_source_path, &level_document)
	if !validation.ok do return validation
	catalog_validation := catalog_load("assets/catalog/editor_catalog.toml", &editor_catalog)
	if !catalog_validation.ok do return catalog_validation
	if merged := catalog_merge_installed(&editor_catalog); !merged.ok do return merged
	_ = catalog_discover_paintings(&editor_catalog)
	_ = catalog_discover_coverings(&editor_catalog, "Floor Coverings", "floor", true)
	_ = catalog_discover_coverings(&editor_catalog, "Wall Coverings", "wall", false)
	editor_state = {
		tool                 = .Select,
		view                 = .Isometric,
		snap_mode            = .Construction,
		room_mode            = .Rectangle,
		paint_target         = .Floor,
		catalog_id           = len(editor_catalog.entries) > 0 ? editor_catalog.entries[0].id : "",
		catalog_category     = "all",
		foundation_kind      = .Slab,
		foundation_depth     = .25,
		terrain_mode         = .Raise,
		terrain_radius       = 2,
		terrain_strength     = .5,
		opening_width        = 1.6,
		opening_height       = 1.4,
		opening_sill_height  = .72,
		window_style         = .Fixed,
		roof_style           = .Gable,
		roof_pitch           = 30,
		roof_overhang        = .4,
		link_kind            = .Stairs,
		link_width           = 1,
		path_kind            = .Road,
		path_width           = 3,
		water_elevation      = .25,
		marker_kind          = .Staging,
		marker_radius        = .5,
		marker_camera_height = 2,
		light_kind           = .Point,
		light_range          = 4,
		light_intensity      = 1,
		light_elevation      = 2.2,
		light_cone_angle     = 45,
		light_color          = {255, 236, 196, 255},
		recovery_available   = os.exists(level_active_autosave_path),
	}
	if editor_state.catalog_id != "" do catalog_record_recent(&editor_state, editor_state.catalog_id)
	level_project_to_runtime(&level_document)
	return validation}
