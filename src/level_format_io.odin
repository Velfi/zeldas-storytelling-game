package main

import "core:fmt"
import "core:os"
import "core:strings"

level_toml_float :: proc(table: Toml_Datum, key: string) -> f32 {
	d := toml_seek_key(
		table,
		key,
	); if d.type == .FP64 do return f32(d.u.fp64); if d.type == .INT64 do return f32(d.u.int64); return 0
}
level_toml_bool_default :: proc(table: Toml_Datum, key: string, default: bool) -> bool {d :=
		toml_seek_key(table, key)
	if d.type != .BOOLEAN do return default
	return d.u.boolean}

level_toml_vec2s :: proc(table: Toml_Datum, key: string) -> [dynamic]Vec2 {
	result := make(
		[dynamic]Vec2,
		0,
		8,
	); d := toml_seek_key(table, key); if d.type != .ARRAY || d.u.arr.elem == nil do return result
	elements := (cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)]
	for element in elements {
		if element.type != .ARRAY || element.u.arr.elem == nil || element.u.arr.size < 2 do continue
		pair := (cast([^]Toml_Datum)element.u.arr.elem)[:int(element.u.arr.size)]
		x, y: f32; if pair[0].type == .FP64 do x = f32(pair[0].u.fp64)
		else if pair[0].type == .INT64 do x = f32(pair[0].u.int64); if pair[1].type == .FP64 do y = f32(pair[1].u.fp64)
		else if pair[1].type == .INT64 do y = f32(pair[1].u.int64)
		append(&result, Vec2{x, y})
	}
	return result
}
level_toml_floats :: proc(table: Toml_Datum, key: string) -> [dynamic]f32 {result := make(
		[dynamic]f32,
		0,
	)
	d := toml_seek_key(table, key)
	if d.type != .ARRAY || d.u.arr.elem == nil do return result
	elements := (cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)]
	for 	e in elements {if e.type == .FP64 do append(&result, f32(e.u.fp64))
		else if e.type == .INT64 do append(&result, f32(e.u.int64))}
	return result}
level_toml_vec3 :: proc(
	table: Toml_Datum,
	key: string,
	default: [3]f32 = {0, 0, 0},
) -> [3]f32 {result := default; values := level_toml_floats(table, key); for value, i in values do if i < 3 do result[i] = value
	return result}
level_toml_color :: proc(table: Toml_Datum, key: string) -> [4]u8 {result := [4]u8 {
		255,
		255,
		255,
		255,
	}
	d := toml_seek_key(table, key)
	if d.type != .ARRAY || d.u.arr.elem == nil do return result
	elements := (cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)]
	for i in 0 ..< min(4, len(elements)) do if elements[i].type == .INT64 do result[i] = u8(clamp(elements[i].u.int64, 0, 255))
	return result}

level_path_kind :: proc(value: string) -> Level_Path_Kind {switch value {case "freestanding_wall":
		return .Freestanding_Wall; case "half_wall":
		return .Half_Wall; case "fence":
		return .Fence; case "road":
		return .Road; case "footpath":
		return .Footpath}; return .Wall}
level_opening_kind :: proc(value: string) -> Level_Opening_Kind {switch value {case "window":
		return .Window; case "arch":
		return .Arch; case "gate":
		return .Gate}; return .Door}
interaction_behavior_from_name :: proc(value: string) -> Interaction_Behavior {switch
	value {case "door":
		return .Door; case "toggle":
		return .Toggle; case "shutter":
		return .Shutter}
	return .None}
interaction_behavior_name :: proc(value: Interaction_Behavior) -> string {switch value {case .Door:
		return "door"; case .Toggle:
		return "toggle"; case .Shutter:
		return "shutter"; case .None:
		return "none"}; return "none"}
door_material_from_name :: proc(value: string) -> Door_Material {switch value {case "painted":
		return .Painted; case "walnut":
		return .Walnut}; return .Oak}
door_material_name :: proc(value: Door_Material) -> string {#partial switch value {case .Painted:
		return "painted"; case .Walnut:
		return "walnut"}; return "oak"}
door_style_from_name :: proc(value: string) -> Door_Style {switch value {case "double":
		return .Double; case "sliding":
		return .Sliding}; return .Hinged}
door_style_name :: proc(value: Door_Style) -> string {#partial switch value {case .Double:
		return "double"; case .Sliding:
		return "sliding"}; return "hinged"}
door_style_label :: proc(value: Door_Style) -> string {return strings.to_upper(
		door_style_name(value),
	)}
window_style_from_name :: proc(value: string) -> Window_Style {switch value {case "casement":
		return .Casement; case "awning":
		return .Awning; case "picture":
		return .Picture; case "double_hung":
		return .Double_Hung}; return .Fixed}
window_style_name :: proc(value: Window_Style) -> string {switch value {case .Casement:
		return "casement"; case .Awning:
		return "awning"; case .Picture:
		return "picture"; case .Double_Hung:
		return "double_hung"; case .Fixed:
		return "fixed"}; return "fixed"}
window_style_label :: proc(value: Window_Style) -> string {if value == .Double_Hung do return "DOUBLE"
	return strings.to_upper(window_style_name(value))}
level_marker_kind :: proc(value: string) -> Level_Marker_Kind {switch
	value {case "character_spawn":
		return .Character_Spawn; case "interaction":
		return .Interaction; case "clue":
		return .Clue; case "trigger":
		return .Trigger; case "transition":
		return .Transition; case "camera":
		return .Camera; case "staging":
		return .Staging}
	return .Player_Spawn}
level_light_kind :: proc(value: string) -> Level_Light_Kind {switch value {case "spot":
		return .Spot; case "area":
		return .Area}; return .Point}
level_roof_style :: proc(value: string) -> Level_Roof_Style {switch value {case "hip":
		return .Hip; case "mansard":
		return .Mansard; case "flat":
		return .Flat; case "parapet":
		return .Parapet}; return .Gable}
level_link_kind :: proc(value: string) -> Level_Vertical_Link_Kind {switch value {case "ladder":
		return .Ladder; case "elevator":
		return .Elevator}; return .Stairs}
level_foundation_kind :: proc(value: string) -> Level_Foundation_Kind {switch value {case "raised":
		return .Raised; case "basement":
		return .Basement}; return .Slab}

// content_offset is a one-shot authoring migration aid.  It lets a compact
// existing build be moved as a rigid unit when the lot grows; saves emit the
// canonical, already-translated coordinates and deliberately omit the key.
level_apply_content_offset :: proc(doc: ^Level_Document, offset: Vec2) {
	if offset.x == 0 && offset.y == 0 do return
	for &room in doc.rooms do for &point in room.points {point.x += offset.x; point.y += offset.y}
	for &path in doc.paths do for &point in path.points {point.x += offset.x; point.y += offset.y}
	for &object in doc.objects {object.position.x += offset.x; object.position.y += offset.y}
	for &light in doc.lights {light.position.x += offset.x; light.position.y += offset.y}
	for &water in doc.waters do for &point in water.points {point.x += offset.x; point.y += offset.y}
	for &foundation in doc.foundations do for &point in foundation.points {point.x += offset.x; point.y += offset.y}
	for &link in doc.vertical_links {link.start.x += offset.x; link.start.y += offset.y; link.finish.x += offset.x; link.finish.y += offset.y}
	for &marker in doc.markers {marker.position.x += offset.x; marker.position.y += offset.y}
}

level_load :: proc(path: string, out: ^Level_Document) -> Validation {
	cpath, err := strings.clone_to_cstring(
		path,
		context.temp_allocator,
	); if err != nil do return {false, "invalid level path"}
	parsed := toml_parse_file_ex(
		cpath,
	); defer toml_free(parsed); if !parsed.ok do return toml_parse_diagnostic(path, "level", &parsed)
	top := parsed.toptab; doc := Level_Document{}
	doc.version = toml_case_string(
		top,
		"version",
	); doc.id = toml_case_string(top, "id"); doc.name = toml_case_string(top, "name"); doc.width = toml_case_int(top, "width"); doc.height = toml_case_int(top, "height"); doc.story_limit = toml_case_int(top, "story_limit"); doc.default_snap = level_toml_float(top, "default_snap"); doc.fine_snap = level_toml_float(top, "fine_snap"); doc.angle_snap = level_toml_float(top, "angle_snap")
	if doc.version != LEVEL_FORMAT_VERSION do return {false, "unsupported level format"}; if doc.id == "" || doc.width < 4 || doc.height < 4 do return {false, "malformed level metadata"}; if doc.story_limit <= 0 || doc.story_limit > LEVEL_MAX_STORIES do return {false, "story limit must be between one and eight"}
	doc.stories = make(
		[dynamic]Level_Story,
		0,
		doc.story_limit,
	); for t in toml_tables(top, "stories") {floor_height := level_toml_float(t, "floor_height"); if floor_height <= 0 do floor_height = level_toml_float(t, "wall_height"); append(&doc.stories, Level_Story{toml_case_string(t, "id"), toml_case_string(t, "name"), level_toml_float(t, "base_elevation"), floor_height})}
	doc.rooms = make(
		[dynamic]Level_Room,
		0,
		16,
	); for t in toml_tables(top, "rooms") {floor_tint := level_toml_color(t, "floor_tint"); wall_tint := level_toml_color(t, "wall_tint"); if floor_tint[3] == 0 do floor_tint = {255, 255, 255, 255}; if wall_tint[3] == 0 do wall_tint = {255, 255, 255, 255}; room := Level_Room {
			id              = toml_case_string(t, "id"),
			name            = toml_case_string(t, "name"),
			story           = toml_case_int(t, "story"),
			points          = level_toml_vec2s(t, "points"),
			platform_height = level_toml_float(t, "platform_height"),
			floor_material  = toml_case_string(t, "floor_material"),
			wall_material   = toml_case_string(t, "wall_material"),
			ceiling_style   = toml_case_string(t, "ceiling_style"),
			floor_tint      = floor_tint,
			wall_tint       = wall_tint,
			exterior        = toml_case_bool(t, "exterior"),
		}; append(&doc.rooms, room)}
	doc.paths = make(
		[dynamic]Level_Path,
		0,
		24,
	); for t in toml_tables(top, "paths") do append(&doc.paths, Level_Path{id = toml_case_string(t, "id"), story = toml_case_int(t, "story"), kind = level_path_kind(toml_case_string(t, "kind")), points = level_toml_vec2s(t, "points"), material = toml_case_string(t, "material"), width = level_toml_float(t, "width")})
	doc.openings = make(
		[dynamic]Level_Opening,
		0,
		16,
	); for t in toml_tables(top, "openings") {kind := level_opening_kind(toml_case_string(t, "kind")); sill_height := level_toml_float(t, "sill_height"); if kind == .Window && sill_height <= 0 do sill_height = .72; behavior := interaction_behavior_from_name(toml_case_string(t, "interaction")); if kind == .Door && behavior == .None do behavior = .Door; interaction_range := level_toml_float(t, "interaction_range"); if interaction_range <= 0 do interaction_range = 1.8; item := Level_Opening {
			id                 = toml_case_string(t, "id"),
			host_path          = toml_case_string(t, "host_path"),
			kind               = kind,
			door_material      = door_material_from_name(toml_case_string(t, "material")),
			door_style         = door_style_from_name(toml_case_string(t, "door_style")),
			window_style       = window_style_from_name(toml_case_string(t, "style")),
			window_flipped     = toml_case_bool(t, "flipped"),
			window_hinge_right = toml_case_bool(t, "hinge_right"),
			interaction        = behavior,
			interaction_prompt = toml_case_string(t, "interaction_prompt"),
			condition_id       = toml_case_string(t, "condition"),
			focused_scene      = toml_case_string(t, "focused_scene"),
			interaction_range  = interaction_range,
			initially_active   = toml_case_bool(t, "initially_active"),
			locked             = toml_case_bool(t, "locked"),
			powered            = level_toml_bool_default(t, "powered", true),
			segment            = toml_case_int(t, "segment"),
			position           = level_toml_float(t, "position"),
			width              = level_toml_float(t, "width"),
			height             = level_toml_float(t, "height"),
			sill_height        = sill_height,
		}; effects := toml_case_strings(
			t,
			"effects",
		); item.effect_id_count = min(len(effects), len(item.effect_ids)); for effect, i in effects do if i < item.effect_id_count do item.effect_ids[i] = effect; append(&doc.openings, item)}
	doc.objects = make(
		[dynamic]Level_Object,
		0,
		32,
	); for t in toml_tables(top, "objects") {p := level_toml_vec2s(t, "position"); position := len(p) > 0 ? p[0] : Vec2{}; tint := level_toml_color(t, "tint"); bark_tint := level_toml_color(t, "bark_tint"); foliage_tint := level_toml_color(t, "foliage_tint"); if tint[3] == 0 do tint = {255, 255, 255, 255}; if bark_tint[3] == 0 do bark_tint = {255, 255, 255, 255}; if foliage_tint[3] == 0 do foliage_tint = {255, 255, 255, 255}; behavior := interaction_behavior_from_name(toml_case_string(t, "interaction")); interaction_range := level_toml_float(t, "interaction_range"); if interaction_range <= 0 do interaction_range = 1.8; item := Level_Object {
			id                 = toml_case_string(t, "id"),
			catalog_id         = toml_case_string(t, "catalog_id"),
			support_id         = toml_case_string(t, "support_id"),
			model_asset_ref    = toml_case_string(t, "model_asset_ref"),
			material_asset_ref = toml_case_string(t, "material_asset_ref"),
			texture_asset_ref  = toml_case_string(t, "texture_asset_ref"),
			interaction_prompt = toml_case_string(t, "interaction_prompt"),
			condition_id       = toml_case_string(t, "condition"),
			focused_scene      = toml_case_string(t, "focused_scene"),
			interaction        = behavior,
			initially_active   = toml_case_bool(t, "initially_active"),
			locked             = toml_case_bool(t, "locked"),
			powered            = level_toml_bool_default(t, "powered", true),
			interaction_range  = interaction_range,
			story              = toml_case_int(t, "story"),
			position           = position,
			elevation          = level_toml_float(t, "elevation"),
			rotation           = level_toml_float(t, "rotation"),
			tint               = tint,
			bark_tint          = bark_tint,
			foliage_tint       = foliage_tint,
		}; effects := toml_case_strings(
			t,
			"effects",
		); item.effect_id_count = min(len(effects), len(item.effect_ids)); for effect, i in effects do if i < item.effect_id_count do item.effect_ids[i] = effect; append(&doc.objects, item)}
	doc.lights = make(
		[dynamic]Level_Light,
		0,
		16,
	); for t in toml_tables(top, "lights") {p := level_toml_vec2s(t, "position"); position := len(p) > 0 ? p[0] : Vec2{}; light := Level_Light {
			id         = toml_case_string(t, "id"),
			kind       = level_light_kind(toml_case_string(t, "kind")),
			story      = toml_case_int(t, "story"),
			position   = position,
			elevation  = level_toml_float(t, "elevation"),
			range      = level_toml_float(t, "range"),
			intensity  = level_toml_float(t, "intensity"),
			facing     = level_toml_float(t, "facing"),
			cone_angle = level_toml_float(t, "cone_angle"),
			color      = level_toml_color(t, "color"),
		}; if light.range <= 0 do light.range = 4; if light.intensity <= 0 do light.intensity = 1; if light.elevation <= 0 do light.elevation = 2.2; if light.cone_angle <= 0 do light.cone_angle = 45; append(&doc.lights, light)}
	doc.roofs = make(
		[dynamic]Level_Roof,
		0,
		8,
	); for t in toml_tables(top, "roofs") do append(&doc.roofs, Level_Roof{id = toml_case_string(t, "id"), room_id = toml_case_string(t, "room_id"), story = toml_case_int(t, "story"), style = level_roof_style(toml_case_string(t, "style")), pitch = level_toml_float(t, "pitch"), overhang = level_toml_float(t, "overhang"), ridge_angle = level_toml_float(t, "ridge_angle"), gutters = toml_case_bool(t, "gutters")})
	doc.waters = make(
		[dynamic]Level_Water,
		0,
		4,
	); for t in toml_tables(top, "waters") do append(&doc.waters, Level_Water{id = toml_case_string(t, "id"), points = level_toml_vec2s(t, "points"), elevation = level_toml_float(t, "elevation")})
	doc.foundations = make(
		[dynamic]Level_Foundation,
		0,
		8,
	); for t in toml_tables(top, "foundations") {kind := level_foundation_kind(toml_case_string(t, "kind")); story := -1; if kind == .Basement do story = toml_case_int(t, "story"); append(&doc.foundations, Level_Foundation{id = toml_case_string(t, "id"), kind = kind, story = story, points = level_toml_vec2s(t, "points"), elevation = level_toml_float(t, "elevation"), depth = level_toml_float(t, "depth")})}; for &foundation in doc.foundations {if foundation.kind != .Basement do continue; if foundation.story >= 0 && foundation.story < len(doc.stories) && doc.stories[foundation.story].base_elevation < 0 do continue; basement_story := -1; for story, i in doc.stories do if story.base_elevation < 0 {basement_story = i; break}; if basement_story < 0 && len(doc.stories) < doc.story_limit {basement_story = len(doc.stories); depth := max(foundation.depth, 2.5); append(&doc.stories, Level_Story{id = "basement", name = "Basement", base_elevation = -depth, wall_height = max(depth, 2.4)})}; foundation.story = basement_story}
	doc.vertical_links = make(
		[dynamic]Level_Vertical_Link,
		0,
		8,
	); for t in toml_tables(top, "vertical_links") {starts := level_toml_vec2s(t, "start"); finishes := level_toml_vec2s(t, "finish"); append(&doc.vertical_links, Level_Vertical_Link{id = toml_case_string(t, "id"), kind = level_link_kind(toml_case_string(t, "kind")), from_story = toml_case_int(t, "from_story"), to_story = toml_case_int(t, "to_story"), start = len(starts) > 0 ? starts[0] : Vec2{}, finish = len(finishes) > 0 ? finishes[0] : Vec2{}, width = level_toml_float(t, "width")})}
	doc.markers = make(
		[dynamic]Level_Marker,
		0,
		16,
	); for t in toml_tables(top, "markers") {p := level_toml_vec2s(t, "position"); position := len(p) > 0 ? p[0] : Vec2{}; interaction_range := level_toml_float(t, "interaction_range"); if interaction_range <= 0 do interaction_range = 1.8; item := Level_Marker {
			id                 = toml_case_string(t, "id"),
			reference          = toml_case_string(t, "reference"),
			destination        = toml_case_string(t, "destination"),
			interaction_prompt = toml_case_string(t, "interaction_prompt"),
			condition_id       = toml_case_string(t, "condition"),
			focused_scene      = toml_case_string(t, "focused_scene"),
			kind               = level_marker_kind(toml_case_string(t, "kind")),
			interaction        = interaction_behavior_from_name(
				toml_case_string(t, "interaction"),
			),
			initially_active   = toml_case_bool(t, "initially_active"),
			locked             = toml_case_bool(t, "locked"),
			powered            = level_toml_bool_default(t, "powered", true),
			story              = toml_case_int(t, "story"),
			position           = position,
			radius             = level_toml_float(t, "radius"),
			facing             = level_toml_float(t, "facing"),
			camera_height      = level_toml_float(t, "camera_height"),
			interaction_range  = interaction_range,
		}; effects := toml_case_strings(
			t,
			"effects",
		); item.effect_id_count = min(len(effects), len(item.effect_ids)); for effect, i in effects do if i < item.effect_id_count do item.effect_ids[i] = effect; append(&doc.markers, item)}
	offsets := level_toml_vec2s(
		top,
		"content_offset",
	); if len(offsets) > 0 do level_apply_content_offset(&doc, offsets[0])
	doc.terrain = level_toml_floats(
		top,
		"terrain",
	); terrain_count := (doc.width + 1) * (doc.height + 1); if len(doc.terrain) == 0 do doc.terrain = make([dynamic]f32, terrain_count); if len(doc.terrain) != terrain_count do return {false, "terrain height count does not match lot dimensions"}; doc.diagnostics = make([dynamic]Level_Diagnostic, 0, 32); doc.revision = 1
	validation := level_validate(
		&doc,
	); if !validation.ok do return validation; out^ = doc; return {true, "LEVEL VALID"}
}

level_quote :: proc(value: string) -> string {result, _ := strings.replace_all(value, "\"", "\\\"")
	return result}
level_points_toml :: proc(points: []Vec2) -> string {builder := strings.builder_make()
	defer strings.builder_destroy(&builder)
	_ = strings.write_string(&builder, "[")
	for p, i in points {if i > 0 do _ = strings.write_string(&builder, ", ")
		_ = strings.write_string(&builder, fmt.tprintf("[%.3f, %.3f]", p.x, p.y))}
	_ = strings.write_string(&builder, "]")
	result, _ := strings.clone(strings.to_string(builder))
	return result}
level_path_kind_name :: proc(kind: Level_Path_Kind) -> string {#partial switch
	kind {case .Freestanding_Wall:
		return "freestanding_wall"; case .Half_Wall:
		return "half_wall"; case .Fence:
		return "fence"; case .Road:
		return "road"; case .Footpath:
		return "footpath"}
	return "wall"}
level_opening_kind_name :: proc(kind: Level_Opening_Kind) -> string {#partial switch
	kind {case .Window:
		return "window"; case .Arch:
		return "arch"; case .Gate:
		return "gate"}
	return "door"}
level_marker_kind_name :: proc(kind: Level_Marker_Kind) -> string {#partial switch
	kind {case .Character_Spawn:
		return "character_spawn"; case .Interaction:
		return "interaction"; case .Clue:
		return "clue"; case .Trigger:
		return "trigger"; case .Transition:
		return "transition"; case .Camera:
		return "camera"; case .Staging:
		return "staging"}
	return "player_spawn"}
level_marker_uses_binding :: proc(kind: Level_Marker_Kind) -> bool {return(
		kind == .Character_Spawn ||
		kind == .Interaction ||
		kind == .Clue ||
		kind == .Trigger ||
		kind == .Transition \
	)}

level_marker_binding_compatible :: proc(a, b: Level_Marker_Kind) -> bool {
	if a == b do return true
	// Transition destinations are stored separately. All other bound marker
	// kinds use references with different target types and must be re-bound.
	return false
}
level_light_kind_name :: proc(kind: Level_Light_Kind) -> string {switch kind {case .Spot:
		return "spot"; case .Area:
		return "area"; case .Point:
		return "point"}; return "point"}
level_roof_style_name :: proc(style: Level_Roof_Style) -> string {switch style {case .Hip:
		return "hip"; case .Mansard:
		return "mansard"; case .Flat:
		return "flat"; case .Parapet:
		return "parapet"; case .Gable:
		return "gable"}; return "gable"}
level_link_kind_name :: proc(kind: Level_Vertical_Link_Kind) -> string {switch kind {case .Ladder:
		return "ladder"; case .Elevator:
		return "elevator"; case .Stairs:
		return "stairs"}; return "stairs"}
level_foundation_kind_name :: proc(kind: Level_Foundation_Kind) -> string {switch
	kind {case .Raised:
		return "raised"; case .Basement:
		return "basement"; case .Slab:
		return "slab"}
	return "slab"}
level_floats_toml :: proc(values: []f32) -> string {b := strings.builder_make()
	defer strings.builder_destroy(&b)
	_ = strings.write_string(&b, "[")
	for value, i in values {if i > 0 do _ = strings.write_string(&b, ", ")
		_ = strings.write_string(&b, fmt.tprintf("%.3f", value))}
	_ = strings.write_string(&b, "]")
	result, _ := strings.clone(strings.to_string(b))
	return result}

level_serialize :: proc(doc: ^Level_Document) -> string {
	b := strings.builder_make(); defer strings.builder_destroy(&b)
	_ = strings.write_string(
		&b,
		fmt.tprintf(
			"version = \"%s\"\nid = \"%s\"\nname = \"%s\"\nwidth = %d\nheight = %d\nstory_limit = %d\ndefault_snap = %.3f\nfine_snap = %.3f\nangle_snap = %.3f\nterrain = %s\n",
			LEVEL_FORMAT_VERSION,
			level_quote(doc.id),
			level_quote(doc.name),
			doc.width,
			doc.height,
			doc.story_limit,
			doc.default_snap,
			doc.fine_snap,
			doc.angle_snap,
			level_floats_toml(doc.terrain[:]),
		),
	)
	for story in doc.stories do _ = strings.write_string(&b, fmt.tprintf("\n[[stories]]\nid = \"%s\"\nname = \"%s\"\nbase_elevation = %.3f\nfloor_height = %.3f\n", level_quote(story.id), level_quote(story.name), story.base_elevation, story.wall_height))
	for room in doc.rooms do _ = strings.write_string(&b, fmt.tprintf("\n[[rooms]]\nid = \"%s\"\nname = \"%s\"\nstory = %d\npoints = %s\nplatform_height = %.3f\nfloor_material = \"%s\"\nwall_material = \"%s\"\nfloor_tint = [%d, %d, %d, %d]\nwall_tint = [%d, %d, %d, %d]\nceiling_style = \"%s\"\nexterior = %s\n", level_quote(room.id), level_quote(room.name), room.story, level_points_toml(room.points[:]), room.platform_height, level_quote(room.floor_material), level_quote(room.wall_material), room.floor_tint[0], room.floor_tint[1], room.floor_tint[2], room.floor_tint[3], room.wall_tint[0], room.wall_tint[1], room.wall_tint[2], room.wall_tint[3], level_quote(room.ceiling_style), room.exterior ? "true" : "false"))
	for path in doc.paths do _ = strings.write_string(&b, fmt.tprintf("\n[[paths]]\nid = \"%s\"\nstory = %d\nkind = \"%s\"\npoints = %s\nmaterial = \"%s\"\nwidth = %.3f\n", level_quote(path.id), path.story, level_path_kind_name(path.kind), level_points_toml(path.points[:]), level_quote(path.material), path.width))
	for opening in doc.openings {effects := ""; for i in 0 ..< opening.effect_id_count {if i > 0 do effects = fmt.tprintf("%s, ", effects); effects = fmt.tprintf("%s\"%s\"", effects, level_quote(opening.effect_ids[i]))}; _ = strings.write_string(&b, fmt.tprintf("\n[[openings]]\nid = \"%s\"\nhost_path = \"%s\"\nkind = \"%s\"\nmaterial = \"%s\"\ndoor_style = \"%s\"\nstyle = \"%s\"\nflipped = %s\nhinge_right = %s\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nsegment = %d\nposition = %.3f\nwidth = %.3f\nheight = %.3f\nsill_height = %.3f\n", level_quote(opening.id), level_quote(opening.host_path), level_opening_kind_name(opening.kind), door_material_name(opening.door_material), door_style_name(opening.door_style), window_style_name(opening.window_style), opening.window_flipped ? "true" : "false", opening.window_hinge_right ? "true" : "false", interaction_behavior_name(opening.interaction), level_quote(opening.interaction_prompt), level_quote(opening.condition_id), level_quote(opening.focused_scene), effects, opening.interaction_range, opening.initially_active ? "true" : "false", opening.locked ? "true" : "false", opening.powered ? "true" : "false", opening.segment, opening.position, opening.width, opening.height, opening.sill_height))}
	for object in doc.objects {effects := ""; for i in 0 ..< object.effect_id_count {if i > 0 do effects = fmt.tprintf("%s, ", effects); effects = fmt.tprintf("%s\"%s\"", effects, level_quote(object.effect_ids[i]))}; _ = strings.write_string(&b, fmt.tprintf("\n[[objects]]\nid = \"%s\"\ncatalog_id = \"%s\"\nsupport_id = \"%s\"\nmodel_asset_ref = \"%s\"\nmaterial_asset_ref = \"%s\"\ntexture_asset_ref = \"%s\"\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nstory = %d\nposition = [[%.3f, %.3f]]\nelevation = %.3f\nrotation = %.3f\ntint = [%d, %d, %d, %d]\nbark_tint = [%d, %d, %d, %d]\nfoliage_tint = [%d, %d, %d, %d]\n", level_quote(object.id), level_quote(object.catalog_id), level_quote(object.support_id), level_quote(object.model_asset_ref), level_quote(object.material_asset_ref), level_quote(object.texture_asset_ref), interaction_behavior_name(object.interaction), level_quote(object.interaction_prompt), level_quote(object.condition_id), level_quote(object.focused_scene), effects, object.interaction_range, object.initially_active ? "true" : "false", object.locked ? "true" : "false", object.powered ? "true" : "false", object.story, object.position.x, object.position.y, object.elevation, object.rotation, object.tint[0], object.tint[1], object.tint[2], object.tint[3], object.bark_tint[0], object.bark_tint[1], object.bark_tint[2], object.bark_tint[3], object.foliage_tint[0], object.foliage_tint[1], object.foliage_tint[2], object.foliage_tint[3]))}
	for light in doc.lights do _ = strings.write_string(&b, fmt.tprintf("\n[[lights]]\nid = \"%s\"\nkind = \"%s\"\nstory = %d\nposition = [[%.3f, %.3f]]\nelevation = %.3f\nrange = %.3f\nintensity = %.3f\nfacing = %.3f\ncone_angle = %.3f\ncolor = [%d, %d, %d, %d]\n", level_quote(light.id), level_light_kind_name(light.kind), light.story, light.position.x, light.position.y, light.elevation, light.range, light.intensity, light.facing, light.cone_angle, light.color[0], light.color[1], light.color[2], light.color[3]))
	for roof in doc.roofs do _ = strings.write_string(&b, fmt.tprintf("\n[[roofs]]\nid = \"%s\"\nroom_id = \"%s\"\nstory = %d\nstyle = \"%s\"\npitch = %.3f\noverhang = %.3f\nridge_angle = %.3f\ngutters = %s\n", level_quote(roof.id), level_quote(roof.room_id), roof.story, level_roof_style_name(roof.style), roof.pitch, roof.overhang, roof.ridge_angle, roof.gutters ? "true" : "false"))
	for water in doc.waters do _ = strings.write_string(&b, fmt.tprintf("\n[[waters]]\nid = \"%s\"\npoints = %s\nelevation = %.3f\n", level_quote(water.id), level_points_toml(water.points[:]), water.elevation))
	for foundation in doc.foundations do _ = strings.write_string(&b, fmt.tprintf("\n[[foundations]]\nid = \"%s\"\nkind = \"%s\"\nstory = %d\npoints = %s\nelevation = %.3f\ndepth = %.3f\n", level_quote(foundation.id), level_foundation_kind_name(foundation.kind), foundation.story, level_points_toml(foundation.points[:]), foundation.elevation, foundation.depth))
	for link in doc.vertical_links do _ = strings.write_string(&b, fmt.tprintf("\n[[vertical_links]]\nid = \"%s\"\nkind = \"%s\"\nfrom_story = %d\nto_story = %d\nstart = [[%.3f, %.3f]]\nfinish = [[%.3f, %.3f]]\nwidth = %.3f\n", level_quote(link.id), level_link_kind_name(link.kind), link.from_story, link.to_story, link.start.x, link.start.y, link.finish.x, link.finish.y, link.width))
	for marker in doc.markers {effects := ""; for i in 0 ..< marker.effect_id_count {if i > 0 do effects = fmt.tprintf("%s, ", effects); effects = fmt.tprintf("%s\"%s\"", effects, level_quote(marker.effect_ids[i]))}; _ = strings.write_string(&b, fmt.tprintf("\n[[markers]]\nid = \"%s\"\nreference = \"%s\"\ndestination = \"%s\"\nkind = \"%s\"\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nstory = %d\nposition = [[%.3f, %.3f]]\nradius = %.3f\nfacing = %.3f\ncamera_height = %.3f\n", level_quote(marker.id), level_quote(marker.reference), level_quote(marker.destination), level_marker_kind_name(marker.kind), interaction_behavior_name(marker.interaction), level_quote(marker.interaction_prompt), level_quote(marker.condition_id), level_quote(marker.focused_scene), effects, marker.interaction_range, marker.initially_active ? "true" : "false", marker.locked ? "true" : "false", marker.powered ? "true" : "false", marker.story, marker.position.x, marker.position.y, marker.radius, marker.facing, marker.camera_height))}
	result, _ := strings.clone(strings.to_string(b)); return result
}

level_save :: proc(path: string, doc: ^Level_Document) -> Validation {
	validation := level_validate(doc); if !validation.ok do return validation
	text := level_serialize(
		doc,
	); temporary := fmt.tprintf("%s.tmp", path); if os.write_entire_file(temporary, transmute([]byte)text) != nil do return {false, "could not write level temporary file"}
	if os.rename(temporary, path) != nil do return {false, "could not atomically replace level file"}
	doc.dirty = false; return {true, "LEVEL SAVED"}
}
level_autosave :: proc(doc: ^Level_Document) -> bool {
	if synced := level_sync_legacy_source_path(); !synced.ok do return false
	return(
		os.write_entire_file(level_active_autosave_path, transmute([]byte)level_serialize(doc)) ==
		nil \
	)
}
