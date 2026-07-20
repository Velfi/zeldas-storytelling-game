package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

LEVEL_FORMAT_VERSION :: "LevelFormat v1"
LEVEL_FALLBACK_SOURCE_PATH :: "assets/levels/vale_house.toml"
LEVEL_FALLBACK_AUTOSAVE_PATH :: "assets/levels/.vale_house.autosave.toml"
// Compatibility aliases for launch and UI code which has not yet adopted the
// project-path setter. Persistence inside this module uses the active paths.
LEVEL_DEFAULT_PATH := LEVEL_FALLBACK_SOURCE_PATH
LEVEL_AUTOSAVE_PATH := LEVEL_FALLBACK_AUTOSAVE_PATH
level_active_source_path := LEVEL_FALLBACK_SOURCE_PATH
level_active_autosave_path := LEVEL_FALLBACK_AUTOSAVE_PATH
LEVEL_MAX_STORIES :: 8
LEVEL_HISTORY_CAPACITY :: 256

level_set_active_paths :: proc(source_path, autosave_path:string)->Validation {
	if source_path=="" do return {false,"level source path cannot be empty"}
	if autosave_path=="" do return {false,"level autosave path cannot be empty"}
	if source_path==autosave_path do return {false,"level source and autosave paths must be distinct"}
	owned_source,source_error:=strings.clone(source_path);if source_error!=nil do return {false,"could not retain level source path"}
	owned_autosave,autosave_error:=strings.clone(autosave_path);if autosave_error!=nil do return {false,"could not retain level autosave path"}
	level_active_source_path=owned_source
	level_active_autosave_path=owned_autosave
	LEVEL_DEFAULT_PATH=level_active_source_path
	LEVEL_AUTOSAVE_PATH=level_active_autosave_path
	return {true,"LEVEL PROJECT PATHS UPDATED"}
}

level_sync_legacy_source_path :: proc()->Validation {
	if LEVEL_DEFAULT_PATH==level_active_source_path do return {true,"LEVEL PROJECT PATHS CURRENT"}
	autosave_path:=LEVEL_AUTOSAVE_PATH
	if autosave_path==level_active_autosave_path do autosave_path=fmt.tprintf("%s.autosave.toml",LEVEL_DEFAULT_PATH)
	return level_set_active_paths(LEVEL_DEFAULT_PATH,autosave_path)
}

Level_Story :: struct {id, name:string, base_elevation, wall_height:f32}
Level_Room :: struct {
	id, name:string,
	story:int,
	points:[dynamic]Vec2,
	platform_height:f32,
	floor_material, wall_material, ceiling_style:string,
	floor_tint, wall_tint:[4]u8,
	exterior:bool,
}
Level_Path_Kind :: enum {Wall, Freestanding_Wall, Half_Wall, Fence, Road, Footpath}
Level_Path :: struct {id:string, story:int, kind:Level_Path_Kind, points:[dynamic]Vec2, material:string, width:f32}
Level_Opening_Kind :: enum {Door, Window, Arch, Gate}
Interaction_Behavior :: enum {None, Door, Toggle, Shutter}
Door_Material :: enum {Oak, Painted, Walnut}
Door_Style :: enum {Hinged, Double, Sliding}
Window_Style :: enum {Fixed, Casement, Awning, Picture, Double_Hung}
Level_Opening :: struct {id, host_path:string, kind:Level_Opening_Kind, door_material:Door_Material, door_style:Door_Style, window_style:Window_Style, window_flipped,window_hinge_right:bool, interaction:Interaction_Behavior, interaction_prompt,condition_id,focused_scene:string, effect_ids:[STORY_MAX_NODE_EFFECTS]string,effect_id_count:int, interaction_range:f32, initially_active,locked,powered:bool, segment:int, position, width, height, sill_height:f32}
Level_Object :: struct {id, catalog_id, support_id, model_asset_ref, material_asset_ref, texture_asset_ref:string, interaction_prompt,condition_id,focused_scene:string, effect_ids:[STORY_MAX_NODE_EFFECTS]string,effect_id_count:int, interaction:Interaction_Behavior, initially_active,locked,powered:bool, interaction_range:f32, story:int, position:Vec2, elevation, rotation:f32, tint, bark_tint, foliage_tint:[4]u8}
Level_Light_Kind :: enum {Point, Spot, Area}
Level_Light :: struct {id:string, kind:Level_Light_Kind, story:int, position:Vec2, elevation, range, intensity, facing, cone_angle:f32, color:[4]u8}
Level_Roof_Style :: enum {Gable, Hip, Mansard, Flat, Parapet}
Level_Roof :: struct {id, room_id:string, story:int, style:Level_Roof_Style, pitch, overhang, ridge_angle:f32, gutters:bool}
Level_Water :: struct {id:string, points:[dynamic]Vec2, elevation:f32}
Level_Foundation_Kind :: enum {Slab, Raised, Basement}
Level_Foundation :: struct {id:string, kind:Level_Foundation_Kind, story:int, points:[dynamic]Vec2, elevation, depth:f32}
Level_Vertical_Link_Kind :: enum {Stairs, Ladder, Elevator}
Level_Vertical_Link :: struct {id:string, kind:Level_Vertical_Link_Kind, from_story, to_story:int, start, finish:Vec2, width:f32}
Level_Marker_Kind :: enum {Player_Spawn, Character_Spawn, Interaction, Clue, Trigger, Transition, Camera, Staging}
Level_Marker :: struct {id, reference, destination,interaction_prompt,condition_id,focused_scene:string, effect_ids:[STORY_MAX_NODE_EFFECTS]string,effect_id_count:int, kind:Level_Marker_Kind, interaction:Interaction_Behavior, initially_active,locked,powered:bool, story:int, position:Vec2, radius, facing, camera_height,interaction_range:f32}
Level_Diagnostic_Severity :: enum {Info, Warning, Error}
Level_Diagnostic :: struct {severity:Level_Diagnostic_Severity, entity_id, message:string, story:int, position:Vec2}

Level_Document :: struct {
	version, id, name:string,
	width, height:int,
	story_limit, active_story:int,
	default_snap, fine_snap, angle_snap:f32,
	revision:u64,
	dirty:bool,
	stories:[dynamic]Level_Story,
	rooms:[dynamic]Level_Room,
	paths:[dynamic]Level_Path,
	openings:[dynamic]Level_Opening,
	objects:[dynamic]Level_Object,
	lights:[dynamic]Level_Light,
	roofs:[dynamic]Level_Roof,
	waters:[dynamic]Level_Water,
	foundations:[dynamic]Level_Foundation,
	vertical_links:[dynamic]Level_Vertical_Link,
	markers:[dynamic]Level_Marker,
	terrain:[dynamic]f32,
	diagnostics:[dynamic]Level_Diagnostic,
}

Placement_State :: enum {Valid, Warning, Blocked}
Placement_Result :: struct {state:Placement_State, message:string, bounds_min, bounds_max:Vec2}
Terrain_Brush_Mode :: enum {Raise, Lower, Smooth, Flatten, Slope}
Level_Command_Kind :: enum {Set_Metadata, Add_Story, Update_Story, Delete_Story, Reorder_Story, Set_Story_Height, Create_Foundation, Set_Foundation, Move_Foundation_Point, Delete_Foundation, Create_Room, Create_Room_Polygon, Split_Room, Merge_Rooms, Insert_Room_Vertex, Remove_Room_Vertex, Duplicate_Room, Move_Room, Rotate_Room, Move_Room_Vertex, Move_Room_Edge, Resize_Room, Set_Platform, Delete_Room, Add_Path, Set_Path, Move_Path_Point, Add_Opening, Set_Opening, Delete_Opening, Set_Interaction, Place_Object, Duplicate_Object, Move_Object, Set_Object_Elevation, Set_Object_Color, Delete_Object, Add_Light, Set_Light, Delete_Light, Paint_Floor, Paint_Walls, Paint_Room, Set_Room_Tint, Create_Roof, Set_Roof, Delete_Roof, Create_Vertical_Link, Set_Vertical_Link, Move_Vertical_Link_Point, Delete_Vertical_Link, Create_Water, Set_Water, Move_Water_Point, Delete_Water, Sculpt_Terrain, Add_Marker, Set_Marker, Delete_Marker}
Level_Command :: struct {kind:Level_Command_Kind, entity_id:string, a,b,c:Vec2, value:f32, material, destination,interaction_prompt,condition_id,focused_scene:string, effect_ids:[STORY_MAX_NODE_EFFECTS]string,effect_id_count:int, interaction:Interaction_Behavior, initially_active,locked,powered:bool, interaction_range:f32, color:[4]u8, brush:Terrain_Brush_Mode, points:[32]Vec2, point_count:int, metadata_id,metadata_name:string,metadata_width,metadata_height,from,to:int,story:Level_Story}

Level_Reference :: struct {kind,owner_id,field:string}
Level_Reference_Preview :: struct {items:[128]Level_Reference,count:int,truncated:bool}
Level_City_Destination :: struct {id,display_name,city_site,level_spawn:string}
Level_Template :: struct {id,name:string,document:Level_Document}
Level_Room_Prefab :: struct {id,name:string,room:Level_Room,objects:[dynamic]Level_Object}
Level_Prop_Prefab :: struct {id,name:string,object:Level_Object}
Level_Reuse_Action_Kind :: enum {Create_Level_From_Template, Instantiate_Room_Prefab, Instantiate_Prop_Prefab}
Dirty_Regions :: struct {terrain, architecture, navigation, lighting, ui:bool, min, max:Vec2}
Editor_Selection_Kind :: enum {None, Foundation, Room, Vertex, Edge, Path, Opening, Object, Light, Roof, Vertical_Link, Water, Marker, Terrain}
Editor_Selection :: struct {kind:Editor_Selection_Kind, entity_id:string, sub_index:int}
Editor_Tool :: enum {Select, Room, Wall, Opening, Paint, Object, Terrain, Water, Roof, Vertical_Link, Marker, Diagnostics}
Editor_View_Mode :: enum {Isometric, Top_Down, Active_Story, Stories_Below, Cutaway, Roof, Collision, Navmesh, Lighting, Markers}
Editor_Snap_Mode :: enum {Construction, Fine, Off}
Editor_Numeric_Field :: enum {None, Object_Height, Object_Angle, Object_X, Object_Y, Opening_Position, Opening_Width, Opening_Height, Opening_Sill, Room_Level, Foundation_Measure, Path_Width, Water_Surface, Link_Width, Roof_Pitch, Roof_Overhang, Roof_Ridge, Light_Range, Light_Intensity, Light_Height, Light_Facing, Light_Cone, Marker_X, Marker_Y, Marker_Radius, Marker_Facing, Marker_Height}
Room_Draw_Mode :: enum {Rectangle, Polygon}
Paint_Target :: enum {Floor, Walls, Room}
Editor_State :: struct {
	tool:Editor_Tool, view:Editor_View_Mode,
	snap_mode:Editor_Snap_Mode, snap_suspended:bool,
	selection:[16]Editor_Selection, selection_count:int,
	catalog_id, catalog_category, search:string, search_buffer:[32]u8, search_count, catalog_page:int, search_active:bool, catalog_recent:[8]string, catalog_recent_count:int, catalog_pinned:[16]string, catalog_pinned_count:int, dirty:Dirty_Regions,
	recovery_available, playtesting, shortcut_help_visible, exit_confirm_visible, view_menu_visible:bool,
	numeric_field:Editor_Numeric_Field, numeric_buffer:[24]u8, numeric_count:int, numeric_replace_on_input:bool,
	marker_name_active:bool, marker_name_buffer:[64]u8, marker_name_count:int,
	diagnostics_visible:bool, diagnostic_selected:int,
	feedback:string, feedback_frames:int, feedback_error:bool,
	drag_active:bool, drag_selection:Editor_Selection,
	drag_origin_world, drag_current_world, drag_delta:Vec2,
	drag_preview:Placement_Result,
	object_rotate_active:bool, object_rotate_id:string, object_rotate_original, object_rotate_preview:f32,
	terrain_mode:Terrain_Brush_Mode, terrain_radius, terrain_strength, terrain_sample:f32,
	terrain_stroke_active:bool, terrain_stroke_start, terrain_stroke_current:Vec2,
	room_mode:Room_Draw_Mode,
	room_exterior:bool,
	room_draw_points:[32]Vec2, room_draw_count:int,
	room_rectangle_active:bool, room_rectangle_start, room_rectangle_current:Vec2,
	room_rectangle_preview:Placement_Result,
	wall_preview_active:bool, wall_preview_point:Vec2,
	foundation_kind:Level_Foundation_Kind, foundation_mode:Room_Draw_Mode, foundation_elevation, foundation_depth:f32,
	foundation_draw_points:[32]Vec2, foundation_draw_count:int, foundation_polygon_preview:Placement_Result,
	foundation_rectangle_active:bool, foundation_rectangle_start, foundation_rectangle_current:Vec2,
	foundation_rectangle_preview:Placement_Result,
	placement_active:bool, placement_position:Vec2, placement_rotation, placement_elevation:f32, placement_support_id:string,
	placement_preview:Placement_Result, placement_rotate_left_latch, placement_rotate_right_latch:bool,
	paint_target:Paint_Target, paint_eyedropper:bool,
	paint_hover:Editor_Selection, paint_hover_active:bool,
	opening_active:bool, opening_host:Editor_Selection, opening_position:Vec2,
	opening_command:Level_Command, opening_preview:Placement_Result, opening_width, opening_height, opening_sill_height:f32, door_material:Door_Material, door_style:Door_Style, window_style:Window_Style,
	roof_style:Level_Roof_Style, roof_pitch, roof_overhang, roof_ridge_angle:f32, roof_gutters:bool,
	roof_hover:Editor_Selection, roof_hover_active:bool, roof_preview:Placement_Result,
	link_anchor_active:bool, link_anchor, link_finish:Vec2, link_width:f32,
	link_kind:Level_Vertical_Link_Kind, link_preview:Placement_Result,
	path_kind:Level_Path_Kind, path_width:f32, path_draw_points:[32]Vec2, path_draw_count:int,
	water_draw_points:[32]Vec2, water_draw_count:int, water_elevation:f32,
	marker_kind:Level_Marker_Kind, marker_radius, marker_facing, marker_camera_height:f32,
	marker_reference, marker_destination:string,
	light_kind:Level_Light_Kind, light_range, light_intensity, light_elevation, light_facing, light_cone_angle:f32, light_color:[4]u8,
	cursor_world:Vec2, cursor_world_valid:bool,
	box_select_active, box_select_additive:bool, box_select_start, box_select_current:Vec2,
}
Catalog_Entry_Kind :: enum {Object, Material}
Catalog_Entry :: struct {
	id, category, model, thumbnail, placement, floor, wall, image, source_namespace, source_version:string,
	model_asset_ref, material_asset_ref, texture_asset_ref:string,
	front_direction:string,
	dimensions:[3]f32,
	clearance_front, clearance_back, clearance_left, clearance_right:f32,
	floor_repeat_m, wall_repeat_m:f32,
	surfaces, styles, affordances:[]string,
	kind:Catalog_Entry_Kind,
	footprint, surface_height, default_elevation:f32,
	emits_light:bool,
	light_kind:Level_Light_Kind,
	light_height, light_range, light_intensity, light_facing, light_cone_angle:f32,
	light_color:[4]u8,
	thumbnail_index, catalog_index, mesh_index:int,
	valid, thumbnail_missing, thumbnail_stale:bool,
}
Editor_Catalog :: struct {entries:[dynamic]Catalog_Entry, selected:int, loaded:bool}
Level_Change_Set :: struct {before, after:Level_Document, label:string}
Level_History :: struct {undo, redo:[LEVEL_HISTORY_CAPACITY]Level_Change_Set, undo_count, redo_count:int}

level_document:Level_Document
level_history:Level_History
// Document-only tools and tests can suppress the expensive renderer/navigation
// projection while still exercising the same validated transaction history.
level_transaction_projection_enabled:=true
editor_state:Editor_State
editor_catalog:Editor_Catalog

level_toml_float :: proc(table:Toml_Datum,key:string)->f32 {
	d:=toml_seek_key(table,key);if d.type==.FP64 do return f32(d.u.fp64);if d.type==.INT64 do return f32(d.u.int64);return 0
}
level_toml_bool_default :: proc(table:Toml_Datum,key:string,default:bool)->bool {d:=toml_seek_key(table,key);if d.type!=.BOOLEAN do return default;return d.u.boolean}

level_toml_vec2s :: proc(table:Toml_Datum,key:string)->[dynamic]Vec2 {
	result:=make([dynamic]Vec2,0,8);d:=toml_seek_key(table,key);if d.type!=.ARRAY||d.u.arr.elem==nil do return result
	elements:=(cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)]
	for element in elements {
		if element.type!=.ARRAY||element.u.arr.elem==nil||element.u.arr.size<2 do continue
		pair:=(cast([^]Toml_Datum)element.u.arr.elem)[:int(element.u.arr.size)]
		x,y:f32;if pair[0].type==.FP64 do x=f32(pair[0].u.fp64);else if pair[0].type==.INT64 do x=f32(pair[0].u.int64);if pair[1].type==.FP64 do y=f32(pair[1].u.fp64);else if pair[1].type==.INT64 do y=f32(pair[1].u.int64)
		append(&result,Vec2{x,y})
	}
	return result
}
level_toml_floats :: proc(table:Toml_Datum,key:string)->[dynamic]f32 {result:=make([dynamic]f32,0);d:=toml_seek_key(table,key);if d.type!=.ARRAY||d.u.arr.elem==nil do return result;elements:=(cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)];for e in elements {if e.type==.FP64 do append(&result,f32(e.u.fp64));else if e.type==.INT64 do append(&result,f32(e.u.int64))};return result}
level_toml_color :: proc(table:Toml_Datum,key:string)->[4]u8 {result:=[4]u8{255,255,255,255};d:=toml_seek_key(table,key);if d.type!=.ARRAY||d.u.arr.elem==nil do return result;elements:=(cast([^]Toml_Datum)d.u.arr.elem)[:int(d.u.arr.size)];for i in 0..<min(4,len(elements)) do if elements[i].type==.INT64 do result[i]=u8(clamp(elements[i].u.int64,0,255));return result}

level_path_kind :: proc(value:string)->Level_Path_Kind {switch value {case "freestanding_wall":return .Freestanding_Wall;case "half_wall":return .Half_Wall;case "fence":return .Fence;case "road":return .Road;case "footpath":return .Footpath};return .Wall}
level_opening_kind :: proc(value:string)->Level_Opening_Kind {switch value {case "window":return .Window;case "arch":return .Arch;case "gate":return .Gate};return .Door}
interaction_behavior_from_name :: proc(value:string)->Interaction_Behavior {switch value {case "door":return .Door;case "toggle":return .Toggle;case "shutter":return .Shutter};return .None}
interaction_behavior_name :: proc(value:Interaction_Behavior)->string {switch value {case .Door:return "door";case .Toggle:return "toggle";case .Shutter:return "shutter";case .None:return "none"};return "none"}
door_material_from_name :: proc(value:string)->Door_Material {switch value {case "painted":return .Painted;case "walnut":return .Walnut};return .Oak}
door_material_name :: proc(value:Door_Material)->string {#partial switch value {case .Painted:return "painted";case .Walnut:return "walnut"};return "oak"}
door_style_from_name :: proc(value:string)->Door_Style {switch value {case "double":return .Double;case "sliding":return .Sliding};return .Hinged}
door_style_name :: proc(value:Door_Style)->string {#partial switch value {case .Double:return "double";case .Sliding:return "sliding"};return "hinged"}
door_style_label :: proc(value:Door_Style)->string {return strings.to_upper(door_style_name(value))}
window_style_from_name :: proc(value:string)->Window_Style {switch value {case "casement":return .Casement;case "awning":return .Awning;case "picture":return .Picture;case "double_hung":return .Double_Hung};return .Fixed}
window_style_name :: proc(value:Window_Style)->string {switch value {case .Casement:return "casement";case .Awning:return "awning";case .Picture:return "picture";case .Double_Hung:return "double_hung";case .Fixed:return "fixed"};return "fixed"}
window_style_label :: proc(value:Window_Style)->string {if value==.Double_Hung do return "DOUBLE";return strings.to_upper(window_style_name(value))}
level_marker_kind :: proc(value:string)->Level_Marker_Kind {switch value {case "character_spawn":return .Character_Spawn;case "interaction":return .Interaction;case "clue":return .Clue;case "trigger":return .Trigger;case "transition":return .Transition;case "camera":return .Camera;case "staging":return .Staging};return .Player_Spawn}
level_light_kind :: proc(value:string)->Level_Light_Kind {switch value {case "spot":return .Spot;case "area":return .Area};return .Point}
level_roof_style :: proc(value:string)->Level_Roof_Style {switch value {case "hip":return .Hip;case "mansard":return .Mansard;case "flat":return .Flat;case "parapet":return .Parapet};return .Gable}
level_link_kind :: proc(value:string)->Level_Vertical_Link_Kind {switch value {case "ladder":return .Ladder;case "elevator":return .Elevator};return .Stairs}
level_foundation_kind :: proc(value:string)->Level_Foundation_Kind {switch value {case "raised":return .Raised;case "basement":return .Basement};return .Slab}

// content_offset is a one-shot authoring migration aid.  It lets a compact
// existing build be moved as a rigid unit when the lot grows; saves emit the
// canonical, already-translated coordinates and deliberately omit the key.
level_apply_content_offset :: proc(doc:^Level_Document,offset:Vec2) {
	if offset.x==0&&offset.y==0 do return
	for &room in doc.rooms do for &point in room.points {point.x+=offset.x;point.y+=offset.y}
	for &path in doc.paths do for &point in path.points {point.x+=offset.x;point.y+=offset.y}
	for &object in doc.objects {object.position.x+=offset.x;object.position.y+=offset.y}
	for &light in doc.lights {light.position.x+=offset.x;light.position.y+=offset.y}
	for &water in doc.waters do for &point in water.points {point.x+=offset.x;point.y+=offset.y}
	for &foundation in doc.foundations do for &point in foundation.points {point.x+=offset.x;point.y+=offset.y}
	for &link in doc.vertical_links {link.start.x+=offset.x;link.start.y+=offset.y;link.finish.x+=offset.x;link.finish.y+=offset.y}
	for &marker in doc.markers {marker.position.x+=offset.x;marker.position.y+=offset.y}
}

level_load :: proc(path:string,out:^Level_Document)->Validation {
	cpath,err:=strings.clone_to_cstring(path,context.temp_allocator);if err!=nil do return {false,"invalid level path"}
	parsed:=toml_parse_file_ex(cpath);defer toml_free(parsed);if !parsed.ok do return toml_parse_diagnostic(path,"level",&parsed)
	top:=parsed.toptab;doc:=Level_Document{}
	doc.version=toml_case_string(top,"version");doc.id=toml_case_string(top,"id");doc.name=toml_case_string(top,"name");doc.width=toml_case_int(top,"width");doc.height=toml_case_int(top,"height");doc.story_limit=toml_case_int(top,"story_limit");doc.default_snap=level_toml_float(top,"default_snap");doc.fine_snap=level_toml_float(top,"fine_snap");doc.angle_snap=level_toml_float(top,"angle_snap")
	if doc.version!=LEVEL_FORMAT_VERSION do return {false,"unsupported level format"};if doc.id==""||doc.width<4||doc.height<4 do return {false,"malformed level metadata"};if doc.story_limit<=0||doc.story_limit>LEVEL_MAX_STORIES do return {false,"story limit must be between one and eight"}
	doc.stories=make([dynamic]Level_Story,0,doc.story_limit);for t in toml_tables(top,"stories") {floor_height:=level_toml_float(t,"floor_height");if floor_height<=0 do floor_height=level_toml_float(t,"wall_height");append(&doc.stories,Level_Story{toml_case_string(t,"id"),toml_case_string(t,"name"),level_toml_float(t,"base_elevation"),floor_height})}
	doc.rooms=make([dynamic]Level_Room,0,16);for t in toml_tables(top,"rooms") {floor_tint:=level_toml_color(t,"floor_tint");wall_tint:=level_toml_color(t,"wall_tint");if floor_tint[3]==0 do floor_tint={255,255,255,255};if wall_tint[3]==0 do wall_tint={255,255,255,255};room:=Level_Room{id=toml_case_string(t,"id"),name=toml_case_string(t,"name"),story=toml_case_int(t,"story"),points=level_toml_vec2s(t,"points"),platform_height=level_toml_float(t,"platform_height"),floor_material=toml_case_string(t,"floor_material"),wall_material=toml_case_string(t,"wall_material"),ceiling_style=toml_case_string(t,"ceiling_style"),floor_tint=floor_tint,wall_tint=wall_tint,exterior=toml_case_bool(t,"exterior")};append(&doc.rooms,room)}
	doc.paths=make([dynamic]Level_Path,0,24);for t in toml_tables(top,"paths") do append(&doc.paths,Level_Path{id=toml_case_string(t,"id"),story=toml_case_int(t,"story"),kind=level_path_kind(toml_case_string(t,"kind")),points=level_toml_vec2s(t,"points"),material=toml_case_string(t,"material"),width=level_toml_float(t,"width")})
	doc.openings=make([dynamic]Level_Opening,0,16);for t in toml_tables(top,"openings") {kind:=level_opening_kind(toml_case_string(t,"kind"));sill_height:=level_toml_float(t,"sill_height");if kind==.Window&&sill_height<=0 do sill_height=.72;behavior:=interaction_behavior_from_name(toml_case_string(t,"interaction"));if kind==.Door&&behavior==.None do behavior=.Door;interaction_range:=level_toml_float(t,"interaction_range");if interaction_range<=0 do interaction_range=1.8;item:=Level_Opening{id=toml_case_string(t,"id"),host_path=toml_case_string(t,"host_path"),kind=kind,door_material=door_material_from_name(toml_case_string(t,"material")),door_style=door_style_from_name(toml_case_string(t,"door_style")),window_style=window_style_from_name(toml_case_string(t,"style")),window_flipped=toml_case_bool(t,"flipped"),window_hinge_right=toml_case_bool(t,"hinge_right"),interaction=behavior,interaction_prompt=toml_case_string(t,"interaction_prompt"),condition_id=toml_case_string(t,"condition"),focused_scene=toml_case_string(t,"focused_scene"),interaction_range=interaction_range,initially_active=toml_case_bool(t,"initially_active"),locked=toml_case_bool(t,"locked"),powered=level_toml_bool_default(t,"powered",true),segment=toml_case_int(t,"segment"),position=level_toml_float(t,"position"),width=level_toml_float(t,"width"),height=level_toml_float(t,"height"),sill_height=sill_height};effects:=toml_case_strings(t,"effects");item.effect_id_count=min(len(effects),len(item.effect_ids));for effect,i in effects do if i<item.effect_id_count do item.effect_ids[i]=effect;append(&doc.openings,item)}
	doc.objects=make([dynamic]Level_Object,0,32);for t in toml_tables(top,"objects") {p:=level_toml_vec2s(t,"position");position:=len(p)>0?p[0]:Vec2{};tint:=level_toml_color(t,"tint");bark_tint:=level_toml_color(t,"bark_tint");foliage_tint:=level_toml_color(t,"foliage_tint");if tint[3]==0 do tint={255,255,255,255};if bark_tint[3]==0 do bark_tint={255,255,255,255};if foliage_tint[3]==0 do foliage_tint={255,255,255,255};behavior:=interaction_behavior_from_name(toml_case_string(t,"interaction"));interaction_range:=level_toml_float(t,"interaction_range");if interaction_range<=0 do interaction_range=1.8;item:=Level_Object{id=toml_case_string(t,"id"),catalog_id=toml_case_string(t,"catalog_id"),support_id=toml_case_string(t,"support_id"),model_asset_ref=toml_case_string(t,"model_asset_ref"),material_asset_ref=toml_case_string(t,"material_asset_ref"),texture_asset_ref=toml_case_string(t,"texture_asset_ref"),interaction_prompt=toml_case_string(t,"interaction_prompt"),condition_id=toml_case_string(t,"condition"),focused_scene=toml_case_string(t,"focused_scene"),interaction=behavior,initially_active=toml_case_bool(t,"initially_active"),locked=toml_case_bool(t,"locked"),powered=level_toml_bool_default(t,"powered",true),interaction_range=interaction_range,story=toml_case_int(t,"story"),position=position,elevation=level_toml_float(t,"elevation"),rotation=level_toml_float(t,"rotation"),tint=tint,bark_tint=bark_tint,foliage_tint=foliage_tint};effects:=toml_case_strings(t,"effects");item.effect_id_count=min(len(effects),len(item.effect_ids));for effect,i in effects do if i<item.effect_id_count do item.effect_ids[i]=effect;append(&doc.objects,item)}
	doc.lights=make([dynamic]Level_Light,0,16);for t in toml_tables(top,"lights") {p:=level_toml_vec2s(t,"position");position:=len(p)>0?p[0]:Vec2{};light:=Level_Light{id=toml_case_string(t,"id"),kind=level_light_kind(toml_case_string(t,"kind")),story=toml_case_int(t,"story"),position=position,elevation=level_toml_float(t,"elevation"),range=level_toml_float(t,"range"),intensity=level_toml_float(t,"intensity"),facing=level_toml_float(t,"facing"),cone_angle=level_toml_float(t,"cone_angle"),color=level_toml_color(t,"color")};if light.range<=0 do light.range=4;if light.intensity<=0 do light.intensity=1;if light.elevation<=0 do light.elevation=2.2;if light.cone_angle<=0 do light.cone_angle=45;append(&doc.lights,light)}
	doc.roofs=make([dynamic]Level_Roof,0,8);for t in toml_tables(top,"roofs") do append(&doc.roofs,Level_Roof{id=toml_case_string(t,"id"),room_id=toml_case_string(t,"room_id"),story=toml_case_int(t,"story"),style=level_roof_style(toml_case_string(t,"style")),pitch=level_toml_float(t,"pitch"),overhang=level_toml_float(t,"overhang"),ridge_angle=level_toml_float(t,"ridge_angle"),gutters=toml_case_bool(t,"gutters")})
	doc.waters=make([dynamic]Level_Water,0,4);for t in toml_tables(top,"waters") do append(&doc.waters,Level_Water{id=toml_case_string(t,"id"),points=level_toml_vec2s(t,"points"),elevation=level_toml_float(t,"elevation")})
	doc.foundations=make([dynamic]Level_Foundation,0,8);for t in toml_tables(top,"foundations") {kind:=level_foundation_kind(toml_case_string(t,"kind"));story:=-1;if kind==.Basement do story=toml_case_int(t,"story");append(&doc.foundations,Level_Foundation{id=toml_case_string(t,"id"),kind=kind,story=story,points=level_toml_vec2s(t,"points"),elevation=level_toml_float(t,"elevation"),depth=level_toml_float(t,"depth")})};for &foundation in doc.foundations {if foundation.kind!=.Basement do continue;if foundation.story>=0&&foundation.story<len(doc.stories)&&doc.stories[foundation.story].base_elevation<0 do continue;basement_story:=-1;for story,i in doc.stories do if story.base_elevation<0 {basement_story=i;break};if basement_story<0&&len(doc.stories)<doc.story_limit {basement_story=len(doc.stories);depth:=max(foundation.depth,2.5);append(&doc.stories,Level_Story{id="basement",name="Basement",base_elevation=-depth,wall_height=max(depth,2.4)})};foundation.story=basement_story}
	doc.vertical_links=make([dynamic]Level_Vertical_Link,0,8);for t in toml_tables(top,"vertical_links") {starts:=level_toml_vec2s(t,"start");finishes:=level_toml_vec2s(t,"finish");append(&doc.vertical_links,Level_Vertical_Link{id=toml_case_string(t,"id"),kind=level_link_kind(toml_case_string(t,"kind")),from_story=toml_case_int(t,"from_story"),to_story=toml_case_int(t,"to_story"),start=len(starts)>0?starts[0]:Vec2{},finish=len(finishes)>0?finishes[0]:Vec2{},width=level_toml_float(t,"width")})}
	doc.markers=make([dynamic]Level_Marker,0,16);for t in toml_tables(top,"markers") {p:=level_toml_vec2s(t,"position");position:=len(p)>0?p[0]:Vec2{};interaction_range:=level_toml_float(t,"interaction_range");if interaction_range<=0 do interaction_range=1.8;item:=Level_Marker{id=toml_case_string(t,"id"),reference=toml_case_string(t,"reference"),destination=toml_case_string(t,"destination"),interaction_prompt=toml_case_string(t,"interaction_prompt"),condition_id=toml_case_string(t,"condition"),focused_scene=toml_case_string(t,"focused_scene"),kind=level_marker_kind(toml_case_string(t,"kind")),interaction=interaction_behavior_from_name(toml_case_string(t,"interaction")),initially_active=toml_case_bool(t,"initially_active"),locked=toml_case_bool(t,"locked"),powered=level_toml_bool_default(t,"powered",true),story=toml_case_int(t,"story"),position=position,radius=level_toml_float(t,"radius"),facing=level_toml_float(t,"facing"),camera_height=level_toml_float(t,"camera_height"),interaction_range=interaction_range};effects:=toml_case_strings(t,"effects");item.effect_id_count=min(len(effects),len(item.effect_ids));for effect,i in effects do if i<item.effect_id_count do item.effect_ids[i]=effect;append(&doc.markers,item)}
	offsets:=level_toml_vec2s(top,"content_offset");if len(offsets)>0 do level_apply_content_offset(&doc,offsets[0])
	doc.terrain=level_toml_floats(top,"terrain");terrain_count:=(doc.width+1)*(doc.height+1);if len(doc.terrain)==0 do doc.terrain=make([dynamic]f32,terrain_count);if len(doc.terrain)!=terrain_count do return {false,"terrain height count does not match lot dimensions"};doc.diagnostics=make([dynamic]Level_Diagnostic,0,32);doc.revision=1
	validation:=level_validate(&doc);if !validation.ok do return validation;out^=doc;return {true,"LEVEL VALID"}
}

level_quote :: proc(value:string)->string {result,_:=strings.replace_all(value,"\"","\\\"");return result}
level_points_toml :: proc(points:[]Vec2)->string {builder:=strings.builder_make();defer strings.builder_destroy(&builder);_=strings.write_string(&builder,"[");for p,i in points {if i>0 do _=strings.write_string(&builder,", ");_=strings.write_string(&builder,fmt.tprintf("[%.3f, %.3f]",p.x,p.y))};_=strings.write_string(&builder,"]");result,_:=strings.clone(strings.to_string(builder));return result}
level_path_kind_name :: proc(kind:Level_Path_Kind)->string {#partial switch kind {case .Freestanding_Wall:return "freestanding_wall";case .Half_Wall:return "half_wall";case .Fence:return "fence";case .Road:return "road";case .Footpath:return "footpath"};return "wall"}
level_opening_kind_name :: proc(kind:Level_Opening_Kind)->string {#partial switch kind {case .Window:return "window";case .Arch:return "arch";case .Gate:return "gate"};return "door"}
level_marker_kind_name :: proc(kind:Level_Marker_Kind)->string {#partial switch kind {case .Character_Spawn:return "character_spawn";case .Interaction:return "interaction";case .Clue:return "clue";case .Trigger:return "trigger";case .Transition:return "transition";case .Camera:return "camera";case .Staging:return "staging"};return "player_spawn"}
level_marker_uses_binding :: proc(kind:Level_Marker_Kind)->bool {return kind==.Character_Spawn||kind==.Interaction||kind==.Clue||kind==.Trigger||kind==.Transition}

level_marker_binding_compatible :: proc(a,b:Level_Marker_Kind)->bool {
	if a==b do return true
	// Transition destinations are stored separately. All other bound marker
	// kinds use references with different target types and must be re-bound.
	return false
}
level_light_kind_name :: proc(kind:Level_Light_Kind)->string {switch kind {case .Spot:return "spot";case .Area:return "area";case .Point:return "point"};return "point"}
level_roof_style_name :: proc(style:Level_Roof_Style)->string {switch style {case .Hip:return "hip";case .Mansard:return "mansard";case .Flat:return "flat";case .Parapet:return "parapet";case .Gable:return "gable"};return "gable"}
level_link_kind_name :: proc(kind:Level_Vertical_Link_Kind)->string {switch kind {case .Ladder:return "ladder";case .Elevator:return "elevator";case .Stairs:return "stairs"};return "stairs"}
level_foundation_kind_name :: proc(kind:Level_Foundation_Kind)->string {switch kind {case .Raised:return "raised";case .Basement:return "basement";case .Slab:return "slab"};return "slab"}
level_floats_toml :: proc(values:[]f32)->string {b:=strings.builder_make();defer strings.builder_destroy(&b);_=strings.write_string(&b,"[");for value,i in values {if i>0 do _=strings.write_string(&b,", ");_=strings.write_string(&b,fmt.tprintf("%.3f",value))};_=strings.write_string(&b,"]");result,_:=strings.clone(strings.to_string(b));return result}

level_serialize :: proc(doc:^Level_Document)->string {
	b:=strings.builder_make();defer strings.builder_destroy(&b)
	_=strings.write_string(&b,fmt.tprintf("version = \"%s\"\nid = \"%s\"\nname = \"%s\"\nwidth = %d\nheight = %d\nstory_limit = %d\ndefault_snap = %.3f\nfine_snap = %.3f\nangle_snap = %.3f\nterrain = %s\n",LEVEL_FORMAT_VERSION,level_quote(doc.id),level_quote(doc.name),doc.width,doc.height,doc.story_limit,doc.default_snap,doc.fine_snap,doc.angle_snap,level_floats_toml(doc.terrain[:])))
	for story in doc.stories do _=strings.write_string(&b,fmt.tprintf("\n[[stories]]\nid = \"%s\"\nname = \"%s\"\nbase_elevation = %.3f\nfloor_height = %.3f\n",level_quote(story.id),level_quote(story.name),story.base_elevation,story.wall_height))
	for room in doc.rooms do _=strings.write_string(&b,fmt.tprintf("\n[[rooms]]\nid = \"%s\"\nname = \"%s\"\nstory = %d\npoints = %s\nplatform_height = %.3f\nfloor_material = \"%s\"\nwall_material = \"%s\"\nfloor_tint = [%d, %d, %d, %d]\nwall_tint = [%d, %d, %d, %d]\nceiling_style = \"%s\"\nexterior = %s\n",level_quote(room.id),level_quote(room.name),room.story,level_points_toml(room.points[:]),room.platform_height,level_quote(room.floor_material),level_quote(room.wall_material),room.floor_tint[0],room.floor_tint[1],room.floor_tint[2],room.floor_tint[3],room.wall_tint[0],room.wall_tint[1],room.wall_tint[2],room.wall_tint[3],level_quote(room.ceiling_style),room.exterior?"true":"false"))
	for path in doc.paths do _=strings.write_string(&b,fmt.tprintf("\n[[paths]]\nid = \"%s\"\nstory = %d\nkind = \"%s\"\npoints = %s\nmaterial = \"%s\"\nwidth = %.3f\n",level_quote(path.id),path.story,level_path_kind_name(path.kind),level_points_toml(path.points[:]),level_quote(path.material),path.width))
	for opening in doc.openings {effects:="";for i in 0..<opening.effect_id_count {if i>0 do effects=fmt.tprintf("%s, ",effects);effects=fmt.tprintf("%s\"%s\"",effects,level_quote(opening.effect_ids[i]))};_=strings.write_string(&b,fmt.tprintf("\n[[openings]]\nid = \"%s\"\nhost_path = \"%s\"\nkind = \"%s\"\nmaterial = \"%s\"\ndoor_style = \"%s\"\nstyle = \"%s\"\nflipped = %s\nhinge_right = %s\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nsegment = %d\nposition = %.3f\nwidth = %.3f\nheight = %.3f\nsill_height = %.3f\n",level_quote(opening.id),level_quote(opening.host_path),level_opening_kind_name(opening.kind),door_material_name(opening.door_material),door_style_name(opening.door_style),window_style_name(opening.window_style),opening.window_flipped?"true":"false",opening.window_hinge_right?"true":"false",interaction_behavior_name(opening.interaction),level_quote(opening.interaction_prompt),level_quote(opening.condition_id),level_quote(opening.focused_scene),effects,opening.interaction_range,opening.initially_active?"true":"false",opening.locked?"true":"false",opening.powered?"true":"false",opening.segment,opening.position,opening.width,opening.height,opening.sill_height))}
	for object in doc.objects {effects:="";for i in 0..<object.effect_id_count {if i>0 do effects=fmt.tprintf("%s, ",effects);effects=fmt.tprintf("%s\"%s\"",effects,level_quote(object.effect_ids[i]))};_=strings.write_string(&b,fmt.tprintf("\n[[objects]]\nid = \"%s\"\ncatalog_id = \"%s\"\nsupport_id = \"%s\"\nmodel_asset_ref = \"%s\"\nmaterial_asset_ref = \"%s\"\ntexture_asset_ref = \"%s\"\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nstory = %d\nposition = [[%.3f, %.3f]]\nelevation = %.3f\nrotation = %.3f\ntint = [%d, %d, %d, %d]\nbark_tint = [%d, %d, %d, %d]\nfoliage_tint = [%d, %d, %d, %d]\n",level_quote(object.id),level_quote(object.catalog_id),level_quote(object.support_id),level_quote(object.model_asset_ref),level_quote(object.material_asset_ref),level_quote(object.texture_asset_ref),interaction_behavior_name(object.interaction),level_quote(object.interaction_prompt),level_quote(object.condition_id),level_quote(object.focused_scene),effects,object.interaction_range,object.initially_active?"true":"false",object.locked?"true":"false",object.powered?"true":"false",object.story,object.position.x,object.position.y,object.elevation,object.rotation,object.tint[0],object.tint[1],object.tint[2],object.tint[3],object.bark_tint[0],object.bark_tint[1],object.bark_tint[2],object.bark_tint[3],object.foliage_tint[0],object.foliage_tint[1],object.foliage_tint[2],object.foliage_tint[3]))}
	for light in doc.lights do _=strings.write_string(&b,fmt.tprintf("\n[[lights]]\nid = \"%s\"\nkind = \"%s\"\nstory = %d\nposition = [[%.3f, %.3f]]\nelevation = %.3f\nrange = %.3f\nintensity = %.3f\nfacing = %.3f\ncone_angle = %.3f\ncolor = [%d, %d, %d, %d]\n",level_quote(light.id),level_light_kind_name(light.kind),light.story,light.position.x,light.position.y,light.elevation,light.range,light.intensity,light.facing,light.cone_angle,light.color[0],light.color[1],light.color[2],light.color[3]))
	for roof in doc.roofs do _=strings.write_string(&b,fmt.tprintf("\n[[roofs]]\nid = \"%s\"\nroom_id = \"%s\"\nstory = %d\nstyle = \"%s\"\npitch = %.3f\noverhang = %.3f\nridge_angle = %.3f\ngutters = %s\n",level_quote(roof.id),level_quote(roof.room_id),roof.story,level_roof_style_name(roof.style),roof.pitch,roof.overhang,roof.ridge_angle,roof.gutters?"true":"false"))
	for water in doc.waters do _=strings.write_string(&b,fmt.tprintf("\n[[waters]]\nid = \"%s\"\npoints = %s\nelevation = %.3f\n",level_quote(water.id),level_points_toml(water.points[:]),water.elevation))
	for foundation in doc.foundations do _=strings.write_string(&b,fmt.tprintf("\n[[foundations]]\nid = \"%s\"\nkind = \"%s\"\nstory = %d\npoints = %s\nelevation = %.3f\ndepth = %.3f\n",level_quote(foundation.id),level_foundation_kind_name(foundation.kind),foundation.story,level_points_toml(foundation.points[:]),foundation.elevation,foundation.depth))
	for link in doc.vertical_links do _=strings.write_string(&b,fmt.tprintf("\n[[vertical_links]]\nid = \"%s\"\nkind = \"%s\"\nfrom_story = %d\nto_story = %d\nstart = [[%.3f, %.3f]]\nfinish = [[%.3f, %.3f]]\nwidth = %.3f\n",level_quote(link.id),level_link_kind_name(link.kind),link.from_story,link.to_story,link.start.x,link.start.y,link.finish.x,link.finish.y,link.width))
	for marker in doc.markers {effects:="";for i in 0..<marker.effect_id_count {if i>0 do effects=fmt.tprintf("%s, ",effects);effects=fmt.tprintf("%s\"%s\"",effects,level_quote(marker.effect_ids[i]))};_=strings.write_string(&b,fmt.tprintf("\n[[markers]]\nid = \"%s\"\nreference = \"%s\"\ndestination = \"%s\"\nkind = \"%s\"\ninteraction = \"%s\"\ninteraction_prompt = \"%s\"\ncondition = \"%s\"\nfocused_scene = \"%s\"\neffects = [%s]\ninteraction_range = %.3f\ninitially_active = %s\nlocked = %s\npowered = %s\nstory = %d\nposition = [[%.3f, %.3f]]\nradius = %.3f\nfacing = %.3f\ncamera_height = %.3f\n",level_quote(marker.id),level_quote(marker.reference),level_quote(marker.destination),level_marker_kind_name(marker.kind),interaction_behavior_name(marker.interaction),level_quote(marker.interaction_prompt),level_quote(marker.condition_id),level_quote(marker.focused_scene),effects,marker.interaction_range,marker.initially_active?"true":"false",marker.locked?"true":"false",marker.powered?"true":"false",marker.story,marker.position.x,marker.position.y,marker.radius,marker.facing,marker.camera_height))}
	result,_:=strings.clone(strings.to_string(b));return result
}

level_save :: proc(path:string,doc:^Level_Document)->Validation {
	validation:=level_validate(doc);if !validation.ok do return validation
	text:=level_serialize(doc);temporary:=fmt.tprintf("%s.tmp",path);if os.write_entire_file(temporary,transmute([]byte)text)!=nil do return {false,"could not write level temporary file"}
	if os.rename(temporary,path)!=nil do return {false,"could not atomically replace level file"}
	doc.dirty=false;return {true,"LEVEL SAVED"}
}
level_autosave :: proc(doc:^Level_Document)->bool {
	if synced:=level_sync_legacy_source_path();!synced.ok do return false
	return os.write_entire_file(level_active_autosave_path,transmute([]byte)level_serialize(doc))==nil
}

level_polygon_area :: proc(points:[]Vec2)->f32 {area:f32;for p,i in points {q:=points[(i+1)%len(points)];area+=p.x*q.y-q.x*p.y};return area*.5}
level_opening_finish_extension :: proc(kind:Level_Opening_Kind)->f32 {return kind==.Window?f32(.12):f32(.06)}
level_opening_finish_clearance :: proc(a,b:Level_Opening_Kind)->f32 {return level_opening_finish_extension(a)+level_opening_finish_extension(b)}
level_opening_end_clearance :: proc(kind:Level_Opening_Kind)->f32 {return max(f32(.10),level_opening_finish_extension(kind))}
level_opening_crosses_wall_junction :: proc(doc:^Level_Document,opening:Level_Opening,host:^Level_Path)->bool {
	if host==nil||opening.segment<0||opening.segment>=len(host.points)-1 do return false
	a,b:=host.points[opening.segment],host.points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;span_sq:=dx*dx+dy*dy;span:=f32(math.sqrt(f64(span_sq)));if span<=.001 do return false
	center_distance:=opening.position*span;protected_half:=opening.width*.5+level_opening_finish_extension(opening.kind)+.18
	for path in doc.paths {
		if path.kind!=.Wall||path.story!=host.story||path.id==host.id do continue
		for point in path.points {
			// A point from another wall lying in the middle of this host is a T
			// junction. Keep the aperture and its trim clear of that structure.
			if point_segment_distance_sq(point.x,point.y,a,b)>.02*.02 do continue
			t:=clamp(((point.x-a.x)*dx+(point.y-a.y)*dy)/span_sq,0,1);along:=t*span
			if t>.001&&t<.999&&math.abs(along-center_distance)<protected_half do return true
		}
	}
	return false
}
level_window_head_finish_height :: proc(sill,glazing:f32)->f32 {return sill+glazing+.13}
level_clone_points :: proc(source:[dynamic]Vec2)->[dynamic]Vec2 {result:=make([dynamic]Vec2,0,len(source));for value in source do append(&result,value);return result}
level_clone_document :: proc(source:^Level_Document)->Level_Document {result:=source^;result.stories=make([dynamic]Level_Story,0,len(source.stories));for v in source.stories do append(&result.stories,v);result.rooms=make([dynamic]Level_Room,0,len(source.rooms));for v in source.rooms {copy:=v;copy.points=level_clone_points(v.points);append(&result.rooms,copy)};result.paths=make([dynamic]Level_Path,0,len(source.paths));for v in source.paths {copy:=v;copy.points=level_clone_points(v.points);append(&result.paths,copy)};result.openings=make([dynamic]Level_Opening,0,len(source.openings));for v in source.openings do append(&result.openings,v);result.objects=make([dynamic]Level_Object,0,len(source.objects));for v in source.objects do append(&result.objects,v);result.lights=make([dynamic]Level_Light,0,len(source.lights));for v in source.lights do append(&result.lights,v);result.roofs=make([dynamic]Level_Roof,0,len(source.roofs));for v in source.roofs do append(&result.roofs,v);result.waters=make([dynamic]Level_Water,0,len(source.waters));for v in source.waters {copy:=v;copy.points=level_clone_points(v.points);append(&result.waters,copy)};result.foundations=make([dynamic]Level_Foundation,0,len(source.foundations));for v in source.foundations {copy:=v;copy.points=level_clone_points(v.points);append(&result.foundations,copy)};result.vertical_links=make([dynamic]Level_Vertical_Link,0,len(source.vertical_links));for v in source.vertical_links do append(&result.vertical_links,v);result.markers=make([dynamic]Level_Marker,0,len(source.markers));for v in source.markers do append(&result.markers,v);result.terrain=make([dynamic]f32,0,len(source.terrain));for v in source.terrain do append(&result.terrain,v);result.diagnostics=make([dynamic]Level_Diagnostic,0,len(source.diagnostics));for v in source.diagnostics do append(&result.diagnostics,v);return result}
level_validate_id :: proc(doc:^Level_Document,ids:^[dynamic]string,id:string,story:int,position:Vec2)->bool {if id=="" {append(&doc.diagnostics,Level_Diagnostic{.Error,id,"Entity needs a stable ID.",story,position});return false};for known in ids^ do if known==id {append(&doc.diagnostics,Level_Diagnostic{.Error,id,fmt.tprintf("Duplicate stable ID: %s",id),story,position});return false};append(ids,id);return true}
level_validate_interaction_refs :: proc(doc:^Level_Document,id,condition,scene:string,effects:[STORY_MAX_NODE_EFFECTS]string,effect_count,story:int,position:Vec2) {if condition!=""&&story_condition_index_in_document(condition)<0 do append(&doc.diagnostics,Level_Diagnostic{.Error,id,fmt.tprintf("Interaction references missing condition: %s",condition),story,position});if scene!=""&&graph_scene_index(scene)<0 do append(&doc.diagnostics,Level_Diagnostic{.Error,id,fmt.tprintf("Interaction references missing focused scene: %s",scene),story,position});for i in 0..<effect_count do if story_effect_index_in_document(effects[i])<0 do append(&doc.diagnostics,Level_Diagnostic{.Error,id,fmt.tprintf("Interaction references missing effect: %s",effects[i]),story,position})}
level_validate :: proc(doc:^Level_Document)->Validation {
	clear(&doc.diagnostics);ids:=make([dynamic]string,0,64,context.temp_allocator)
	for foundation in doc.foundations {position:=len(foundation.points)>0?foundation.points[0]:Vec2{};_=level_validate_id(doc,&ids,foundation.id,max(foundation.story,0),position);if len(foundation.points)<3||!level_polygon_simple(foundation.points[:])||math.abs(level_polygon_area(foundation.points[:]))<1 do append(&doc.diagnostics,Level_Diagnostic{.Error,foundation.id,"Foundation footprint is invalid.",max(foundation.story,0),position});if foundation.kind==.Basement&&(foundation.depth<1.8||foundation.story<0||foundation.story>=len(doc.stories)||doc.stories[foundation.story].base_elevation>=0) do append(&doc.diagnostics,Level_Diagnostic{.Error,foundation.id,"Basement must reference a valid below-grade story at least 1.8 meters deep.",max(foundation.story,0),position})}
	for room in doc.rooms {position:=len(room.points)>0?room.points[0]:Vec2{};_=level_validate_id(doc,&ids,room.id,room.story,position);if room.story<0||room.story>=len(doc.stories) do append(&doc.diagnostics,Level_Diagnostic{.Error,room.id,"Room references a missing story.",room.story,position});if len(room.points)<3||math.abs(level_polygon_area(room.points[:]))<.25 do append(&doc.diagnostics,Level_Diagnostic{.Error,room.id,"Room polygon is degenerate.",room.story,position});if !level_room_has_foundation(doc,room) do append(&doc.diagnostics,Level_Diagnostic{.Warning,room.id,"Ground-floor room has no supporting foundation.",room.story,position});for p in room.points do if p.x<0||p.y<0||p.x>f32(doc.width)||p.y>f32(doc.height) do append(&doc.diagnostics,Level_Diagnostic{.Error,room.id,"Room extends outside the lot.",room.story,p})}
	for path in doc.paths {position:=len(path.points)>0?path.points[0]:Vec2{};_=level_validate_id(doc,&ids,path.id,path.story,position);if len(path.points)<2 do append(&doc.diagnostics,Level_Diagnostic{.Error,path.id,"Path needs at least two points.",path.story,position})}
	for opening in doc.openings {
		host:^Level_Path;for &path in doc.paths do if path.id==opening.host_path do host=&path
		story:=0;position:=Vec2{};if host!=nil do story=host.story
		_=level_validate_id(doc,&ids,opening.id,story,position)
		if host==nil||opening.segment<0||opening.segment>=len(host.points)-1 {
			append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening references an invalid wall segment.",story,position})
			continue
		}
		a,b:=host.points[opening.segment],host.points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;span:=f32(math.sqrt(f64(dx*dx+dy*dy)));position={a.x+dx*opening.position,a.y+dy*opening.position}
		if opening.width<.4||opening.width>6 do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening width must be between 0.4 and 6 meters.",story,position})
		if opening.height<.4||opening.height>4 do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening height must be between 0.4 and 4 meters.",story,position})
		if opening.kind==.Window {wall_height:=story>=0&&story<len(doc.stories)?doc.stories[story].wall_height:f32(0);if opening.sill_height<.2||opening.sill_height>2 do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Window sill height must be between 0.2 and 2 meters.",story,position});if wall_height>0&&level_window_head_finish_height(opening.sill_height,opening.height)>wall_height+.001 do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Window head trim and flashing must remain below the wall top.",story,position})}
		if opening.interaction!=.None&&(opening.kind!=.Door||opening.interaction!=.Door) do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Only door openings may use door interaction behavior.",story,position})
		if opening.interaction!=.None&&(opening.interaction_range<.5||opening.interaction_range>6) do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Interaction range must be between 0.5 and 6 meters.",story,position})
		if opening.interaction!=.None do level_validate_interaction_refs(doc,opening.id,opening.condition_id,opening.focused_scene,opening.effect_ids,opening.effect_id_count,story,position)
		end_clearance:=level_opening_end_clearance(opening.kind);if opening.width>span-end_clearance*2 do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening and finished trim are too wide for the wall span.",story,position})
		half:=(opening.width*.5+end_clearance)/max(span,.001);if opening.position<half||opening.position>1-half do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening trim extends beyond its wall span.",story,position})
		if level_opening_crosses_wall_junction(doc,opening,host) do append(&doc.diagnostics,Level_Diagnostic{.Error,opening.id,"Opening and finished trim must stay clear of wall junctions.",story,position})
	}
	for opening,i in doc.openings {for other,j in doc.openings {if j<=i||opening.host_path!=other.host_path||opening.segment!=other.segment do continue;host_index:=level_path_index(doc,opening.host_path);if host_index<0||opening.segment<0||opening.segment>=len(doc.paths[host_index].points)-1 do continue;a,b:=doc.paths[host_index].points[opening.segment],doc.paths[host_index].points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;span:=f32(math.sqrt(f64(dx*dx+dy*dy)));clearance:=math.abs(opening.position-other.position)*span-(opening.width+other.width)*.5;if clearance<level_opening_finish_clearance(opening.kind,other.kind) {position:=Vec2{a.x+dx*other.position,a.y+dy*other.position};append(&doc.diagnostics,Level_Diagnostic{.Error,other.id,"Finished opening trim overlaps or lacks clear wall.",doc.paths[host_index].story,position})}}}
	for room in doc.rooms {position:=len(room.points)>0?room.points[0]:Vec2{};if room.floor_material!=""&&!catalog_qualified_id(room.floor_material) do append(&doc.diagnostics,Level_Diagnostic{.Error,room.id,"Floor material ID must be namespace-qualified.",room.story,position});if room.wall_material!=""&&!catalog_qualified_id(room.wall_material) do append(&doc.diagnostics,Level_Diagnostic{.Error,room.id,"Wall material ID must be namespace-qualified.",room.story,position})}
	for object in doc.objects do if object.catalog_id!=""&&!catalog_qualified_id(object.catalog_id) do append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Object catalog ID must be namespace-qualified.",object.story,object.position})
	for object in doc.objects {_=level_validate_id(doc,&ids,object.id,object.story,object.position);if object.catalog_id=="" do append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Object needs a catalog ID.",object.story,object.position});if object.interaction==.Door do append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Objects cannot use door interaction behavior.",object.story,object.position});if object.interaction!=.None&&(object.interaction_range<.5||object.interaction_range>6) do append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Interaction range must be between 0.5 and 6 meters.",object.story,object.position});if object.interaction!=.None do level_validate_interaction_refs(doc,object.id,object.condition_id,object.focused_scene,object.effect_ids,object.effect_id_count,object.story,object.position);if object.support_id!="" {support_index:=level_object_index(doc,object.support_id);if support_index<0||object.support_id==object.id {append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Object references missing furniture support.",object.story,object.position})} else if doc.objects[support_index].story!=object.story {append(&doc.diagnostics,Level_Diagnostic{.Error,object.id,"Object and furniture support must share a story.",object.story,object.position})}}}
	for light in doc.lights {_=level_validate_id(doc,&ids,light.id,light.story,light.position);if light.story<0||light.story>=len(doc.stories) do append(&doc.diagnostics,Level_Diagnostic{.Error,light.id,"Light references a missing story.",light.story,light.position});if light.position.x<0||light.position.y<0||light.position.x>f32(doc.width)||light.position.y>f32(doc.height) do append(&doc.diagnostics,Level_Diagnostic{.Error,light.id,"Light is outside the lot.",light.story,light.position});if light.range<=0||light.intensity<=0 do append(&doc.diagnostics,Level_Diagnostic{.Error,light.id,"Light range and intensity must be positive.",light.story,light.position});if light.elevation<0 do append(&doc.diagnostics,Level_Diagnostic{.Warning,light.id,"Light is below its story floor.",light.story,light.position})}
	for roof in doc.roofs {_=level_validate_id(doc,&ids,roof.id,roof.story,{});if level_room_index(doc,roof.room_id)<0 do append(&doc.diagnostics,Level_Diagnostic{.Error,roof.id,"Roof references a missing room.",roof.story,{}});if roof.pitch<0||roof.pitch>75 do append(&doc.diagnostics,Level_Diagnostic{.Warning,roof.id,"Roof pitch is outside the recommended range.",roof.story,{}})}
	for water in doc.waters {position:=len(water.points)>0?water.points[0]:Vec2{};_=level_validate_id(doc,&ids,water.id,0,position);if len(water.points)<3||!level_polygon_simple(water.points[:])||math.abs(level_polygon_area(water.points[:]))<.5 do append(&doc.diagnostics,Level_Diagnostic{.Error,water.id,"Pond shoreline is invalid.",0,position});for point in water.points do if point.x<0||point.y<0||point.x>f32(doc.width)||point.y>f32(doc.height) {append(&doc.diagnostics,Level_Diagnostic{.Error,water.id,"Pond shoreline extends outside the lot.",0,point});break}}
	for link in doc.vertical_links {_=level_validate_id(doc,&ids,link.id,link.from_story,link.start);if link.from_story<0||link.to_story<0||link.to_story>=len(doc.stories)||level_story_above(doc,link.from_story)!=link.to_story do append(&doc.diagnostics,Level_Diagnostic{.Error,link.id,"Vertical link must connect adjacent stories by elevation.",link.from_story,link.start})}
	spawn_count:=0;for marker in doc.markers {_ = level_validate_id(doc,&ids,marker.id,marker.story,marker.position);if marker.position.x<0||marker.position.y<0||marker.position.x>f32(doc.width)||marker.position.y>f32(doc.height) do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Marker is outside the lot.",marker.story,marker.position});if marker.story<0||marker.story>=len(doc.stories) do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Marker references a missing story.",marker.story,marker.position});if marker.kind==.Player_Spawn {spawn_count+=1;if marker.radius<.3 do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Player spawn radius is unsafe.",marker.story,marker.position})};if marker.kind==.Camera&&(marker.camera_height<.5||marker.camera_height>20) do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Camera marker height cannot frame the scene safely.",marker.story,marker.position});if marker.kind==.Transition&&!strings.contains(marker.destination,":") do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Transition destination must be a qualified space:target reference.",marker.story,marker.position});if marker.interaction!=.None {if marker.kind!=.Interaction&&marker.kind!=.Staging do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Only interaction or staging markers may define behavior.",marker.story,marker.position});if marker.interaction==.Door do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Markers cannot use door interaction behavior.",marker.story,marker.position});if marker.interaction_range<.5||marker.interaction_range>6 do append(&doc.diagnostics,Level_Diagnostic{.Error,marker.id,"Interaction range must be between 0.5 and 6 meters.",marker.story,marker.position});level_validate_interaction_refs(doc,marker.id,marker.condition_id,marker.focused_scene,marker.effect_ids,marker.effect_id_count,marker.story,marker.position)}};if spawn_count==0 do append(&doc.diagnostics,Level_Diagnostic{.Error,doc.id,"Level requires a player spawn.",0,{}})
	for issue in doc.diagnostics do if issue.severity==.Error do return {false,issue.message};return {true,"LEVEL VALID"}
}

level_reference_add :: proc(out:^Level_Reference_Preview,kind,owner,field:string) {if out.count>=len(out.items) {out.truncated=true;return};out.items[out.count]={kind,owner,field};out.count+=1}
level_reference_preview :: proc(doc:^Level_Document,project:^Story_Project,id:string)->Level_Reference_Preview {result:Level_Reference_Preview;if project!=nil {for entity in project.entities do if entity.spatial.space_id==doc.id&&entity.spatial.target_id==id do level_reference_add(&result,"entity",entity.id,"spatial");for condition in project.conditions {if condition.spatial_a.space_id==doc.id&&condition.spatial_a.target_id==id do level_reference_add(&result,"condition",condition.id,"spatial_a");if condition.spatial_b.space_id==doc.id&&condition.spatial_b.target_id==id do level_reference_add(&result,"condition",condition.id,"spatial_b")};for effect in project.effects {if effect.spatial_target.space_id==doc.id&&effect.spatial_target.target_id==id do level_reference_add(&result,"effect",effect.id,"spatial_target");if effect.spatial_destination.space_id==doc.id&&effect.spatial_destination.target_id==id do level_reference_add(&result,"effect",effect.id,"spatial_destination")};if payload:=mystery_payload(project);payload!=nil {for item in payload.city_labels do if item.level_spawn==id do level_reference_add(&result,"city_label",item.id,"level_spawn")}};for object in doc.objects do if object.id!=id&&object.support_id==id do level_reference_add(&result,"object",object.id,"support_id");for opening in doc.openings do if opening.host_path==id do level_reference_add(&result,"opening",opening.id,"host_path");for roof in doc.roofs do if roof.room_id==id do level_reference_add(&result,"roof",roof.id,"room_id");for marker in doc.markers do if marker.id!=id&&marker.destination==fmt.tprintf("%s:%s",doc.id,id) do level_reference_add(&result,"marker",marker.id,"destination");for node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera==id do level_reference_add(&result,"graph_node",node.beat.id,"camera");if node.beat.actor_mark==id do level_reference_add(&result,"graph_node",node.beat.id,"actor_mark")};return result}
level_reference_repair :: proc(doc:^Level_Document,project:^Story_Project,missing,replacement:string)->bool {if missing==""||missing==replacement||level_selection_for_id(doc,replacement).kind==.None do return false;if project!=nil {for &entity in project.entities do if entity.spatial.space_id==doc.id&&entity.spatial.target_id==missing do entity.spatial.target_id=replacement;for &condition in project.conditions {if condition.spatial_a.space_id==doc.id&&condition.spatial_a.target_id==missing do condition.spatial_a.target_id=replacement;if condition.spatial_b.space_id==doc.id&&condition.spatial_b.target_id==missing do condition.spatial_b.target_id=replacement};for &effect in project.effects {if effect.spatial_target.space_id==doc.id&&effect.spatial_target.target_id==missing do effect.spatial_target.target_id=replacement;if effect.spatial_destination.space_id==doc.id&&effect.spatial_destination.target_id==missing do effect.spatial_destination.target_id=replacement};if payload:=mystery_payload(project);payload!=nil do for &item in payload.city_labels do if item.level_spawn==missing do item.level_spawn=replacement};old_qualified:=fmt.tprintf("%s:%s",doc.id,missing);new_qualified:=fmt.tprintf("%s:%s",doc.id,replacement);for &marker in doc.markers do if marker.destination==old_qualified do marker.destination=new_qualified;for &node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera==missing do node.beat.camera=replacement;if node.beat.actor_mark==missing do node.beat.actor_mark=replacement};return true}
level_reference_rename :: proc(doc:^Level_Document,project:^Story_Project,old,new:string)->bool {if !graph_valid_id(new)||old==new||level_selection_for_id(doc,new).kind!=.None do return false;selection:=level_selection_for_id(doc,old);#partial switch selection.kind {case .Marker:index:=level_marker_index(doc,old);if index<0 do return false;doc.markers[index].id=new;case .Object:index:=level_object_index(doc,old);if index<0 do return false;doc.objects[index].id=new;for &item in doc.objects do if item.support_id==old do item.support_id=new;case .Room:index:=level_room_index(doc,old);if index<0 do return false;doc.rooms[index].id=new;for &roof in doc.roofs do if roof.room_id==old do roof.room_id=new;case .Opening:index:=level_opening_index(doc,old);if index<0 do return false;doc.openings[index].id=new;case .Path:index:=level_path_index(doc,old);if index<0 do return false;doc.paths[index].id=new;for &opening in doc.openings do if opening.host_path==old do opening.host_path=new;case:return false};_=level_reference_repair(doc,project,old,new);return true}
level_reference_remove :: proc(doc:^Level_Document,project:^Story_Project,id:string)->(Level_Reference_Preview,bool) {preview:=level_reference_preview(doc,project,id);if preview.count>0||preview.truncated do return preview,false;selection:=level_selection_for_id(doc,id);#partial switch selection.kind {case .Marker:index:=level_marker_index(doc,id);if index<0 {return preview,false};ordered_remove(&doc.markers,index);case .Object:index:=level_object_index(doc,id);if index<0 {return preview,false};ordered_remove(&doc.objects,index);case .Opening:index:=level_opening_index(doc,id);if index<0 {return preview,false};ordered_remove(&doc.openings,index);case .Room:index:=level_room_index(doc,id);if index<0 {return preview,false};ordered_remove(&doc.rooms,index);case .Path:index:=level_path_index(doc,id);if index<0 {return preview,false};ordered_remove(&doc.paths,index);case:return preview,false};return preview,true}

level_template_capture :: proc(id,name:string,source:^Level_Document)->Level_Template {return {id,name,level_clone_document(source)}}
level_template_instantiate :: proc(template:^Level_Template,new_id,new_name:string)->Level_Document {result:=level_clone_document(&template.document);result.id=new_id;result.name=new_name;result.revision=1;result.dirty=true;return result}
level_template_destroy :: proc(template:^Level_Template) {authoring_level_document_destroy(&template.document);template^={}}
level_room_prefab_capture :: proc(doc:^Level_Document,room_id,id,name:string)->(Level_Room_Prefab,bool) {index:=level_room_index(doc,room_id);if index<0 do return {},false;result:=Level_Room_Prefab{id=id,name=name,room=doc.rooms[index]};result.room.points=level_clone_points(doc.rooms[index].points);for object in doc.objects do if object.story==result.room.story&&level_point_in_polygon(object.position,result.room.points[:]) do append(&result.objects,object);return result,true}
level_room_prefab_destroy :: proc(prefab:^Level_Room_Prefab) {delete(prefab.room.points);delete(prefab.objects);prefab^={}}
level_room_prefab_instantiate :: proc(doc:^Level_Document,prefab:^Level_Room_Prefab,room_id:string,offset:Vec2)->bool {if level_room_index(doc,room_id)>=0 do return false;room:=prefab.room;room.id=room_id;room.story=doc.active_story;room.points=level_clone_points(prefab.room.points);for &point in room.points {point.x+=offset.x;point.y+=offset.y};append(&doc.rooms,room);for object,i in prefab.objects {copy:=object;copy.id=level_next_id(fmt.tprintf("%s_prop_%d",room_id,i+1),doc.revision+u64(i));copy.story=doc.active_story;copy.position.x+=offset.x;copy.position.y+=offset.y;copy.support_id="";append(&doc.objects,copy)};return true}
level_prop_prefab_capture :: proc(doc:^Level_Document,object_id,id,name:string)->(Level_Prop_Prefab,bool) {index:=level_object_index(doc,object_id);if index<0 do return {},false;return {id,name,doc.objects[index]},true}
level_prop_prefab_instantiate :: proc(doc:^Level_Document,prefab:^Level_Prop_Prefab,object_id:string,position:Vec2)->bool {if level_object_index(doc,object_id)>=0 do return false;object:=prefab.object;object.id=object_id;object.story=doc.active_story;object.position=position;object.support_id="";append(&doc.objects,object);return true}

// Single production action boundary for the reusable-content buttons. Capture
// and instantiate remain atomic from the caller's perspective, so UI code does
// not retain borrowed prefab/template storage between frames.
level_reuse_action :: proc(doc:^Level_Document,kind:Level_Reuse_Action_Kind,source_id,new_id,new_name:string,position:Vec2)->bool {
	if doc==nil||new_id=="" do return false
	switch kind {
	case .Create_Level_From_Template:
		template:=level_template_capture(fmt.tprintf("%s_template",doc.id),new_name,doc);replacement:=level_template_instantiate(&template,new_id,new_name);level_template_destroy(&template);authoring_level_document_destroy(doc);doc^=replacement;return true
	case .Instantiate_Room_Prefab:
		prefab,ok:=level_room_prefab_capture(doc,source_id,fmt.tprintf("%s_prefab",source_id),new_name);if !ok do return false;created:=level_room_prefab_instantiate(doc,&prefab,new_id,position);level_room_prefab_destroy(&prefab);return created
	case .Instantiate_Prop_Prefab:
		prefab,ok:=level_prop_prefab_capture(doc,source_id,fmt.tprintf("%s_prefab",source_id),new_name);if !ok do return false;return level_prop_prefab_instantiate(doc,&prefab,new_id,position)
	}
	return false
}

level_marker_candidates :: proc(doc:^Level_Document,story:int,kind:Level_Marker_Kind,include_other_stories:bool,out:^[256]Story_Spatial_Id)->int {count:=0;for marker in doc.markers {if marker.kind!=kind||(!include_other_stories&&marker.story!=story)||count>=len(out^) do continue;out[count]={doc.id,marker.id};count+=1};return count}
level_city_site_exists :: proc(id:string)->bool {for site in CITY_CASE_LOCATION_SITES do if site.id==id do return true;return false}
level_city_destinations_validate :: proc(doc:^Level_Document,destinations:[]Level_City_Destination)->Validation {for item,i in destinations {if !graph_valid_id(item.id)||item.display_name==""||!level_city_site_exists(item.city_site) do return {false,"city destination metadata or reserved site is invalid"};spawn:=level_marker_index(doc,item.level_spawn);if spawn<0||doc.markers[spawn].kind!=.Player_Spawn do return {false,"city destination must use a player-spawn marker in this level"};for other in destinations[i+1:] do if other.id==item.id||other.city_site==item.city_site do return {false,"city destination IDs and reserved sites must be unique"}};return {true,"CITY DESTINATIONS VALID"}}
level_character_create_and_place :: proc(doc:^Level_Document,project:^Story_Project,id,display_name:string,story:int,position:Vec2)->bool {if project==nil||!graph_valid_id(id)||display_name==""||story<0||story>=len(doc.stories)||position.x<0||position.y<0||position.x>f32(doc.width)||position.y>f32(doc.height)||story_entity_index(project,id)>=0 do return false;marker_id:=fmt.tprintf("spawn_%s",id);if level_marker_index(doc,marker_id)>=0 do return false;append(&project.entities,Story_Entity{id=id,kind="person",display_name=display_name,spatial={doc.id,.Marker,marker_id}});append(&doc.markers,Level_Marker{id=marker_id,reference=id,kind=.Character_Spawn,story=story,position=position,radius=.75});return true}


level_segments_cross :: proc(a,b,c,d:Vec2)->bool {
	ab:=wall_cap_cross(a,b,c);ac:=wall_cap_cross(a,b,d);cd:=wall_cap_cross(c,d,a);ca:=wall_cap_cross(c,d,b)
	return (ab>0&&ac<0||ab<0&&ac>0)&&(cd>0&&ca<0||cd<0&&ca>0)
}

level_polygon_simple :: proc(points:[]Vec2)->bool {
	if len(points)<3||math.abs(level_polygon_area(points))<.25 do return false
	for i in 0..<len(points) {a,b:=points[i],points[(i+1)%len(points)];dx,dy:=b.x-a.x,b.y-a.y;if dx*dx+dy*dy<.01 do return false;for j in i+1..<len(points) {if j==i||(j+1)%len(points)==i||(i+1)%len(points)==j do continue;c,d:=points[j],points[(j+1)%len(points)];if level_segments_cross(a,b,c,d) do return false}}
	return true
}

level_split_polygon :: proc(source:[]Vec2,a,b:Vec2,out_a:^[34]Vec2,count_a:^int,out_b:^[34]Vec2,count_b:^int)->bool {
	count_a^=0;count_b^=0;if len(source)<3||len(source)>32||(a.x-b.x)*(a.x-b.x)+(a.y-b.y)*(a.y-b.y)<.04 do return false
	edge_a,edge_b:=-1,-1;for point,i in source {next:=source[(i+1)%len(source)];if edge_a<0&&point_segment_distance_sq(a.x,a.y,point,next)<=.002 do edge_a=i;if edge_b<0&&point_segment_distance_sq(b.x,b.y,point,next)<=.002 do edge_b=i};if edge_a<0||edge_b<0||edge_a==edge_b do return false
	expanded:[34]Vec2;expanded_count:=0;for point,i in source {next:=source[(i+1)%len(source)];expanded[expanded_count]=point;expanded_count+=1;on_a:=point_segment_distance_sq(a.x,a.y,point,next)<=.002&&(a.x-point.x)*(a.x-point.x)+(a.y-point.y)*(a.y-point.y)>.002&&(a.x-next.x)*(a.x-next.x)+(a.y-next.y)*(a.y-next.y)>.002;on_b:=point_segment_distance_sq(b.x,b.y,point,next)<=.002&&(b.x-point.x)*(b.x-point.x)+(b.y-point.y)*(b.y-point.y)>.002&&(b.x-next.x)*(b.x-next.x)+(b.y-next.y)*(b.y-next.y)>.002;if on_a {expanded[expanded_count]=a;expanded_count+=1};if on_b {expanded[expanded_count]=b;expanded_count+=1}}
	index_a,index_b:=-1,-1;for point,i in expanded[:expanded_count] {if (point.x-a.x)*(point.x-a.x)+(point.y-a.y)*(point.y-a.y)<=.002 do index_a=i;if (point.x-b.x)*(point.x-b.x)+(point.y-b.y)*(point.y-b.y)<=.002 do index_b=i};if index_a<0||index_b<0||index_a==index_b do return false
	i:=index_a;for {out_a[count_a^]=expanded[i];count_a^+=1;if i==index_b do break;i=(i+1)%expanded_count};i=index_b;for {out_b[count_b^]=expanded[i];count_b^+=1;if i==index_a do break;i=(i+1)%expanded_count};return count_a^>=3&&count_b^>=3&&level_polygon_simple(out_a[:count_a^])&&level_polygon_simple(out_b[:count_b^])
}

level_points_near :: proc(a,b:Vec2)->bool {dx,dy:=a.x-b.x,a.y-b.y;return dx*dx+dy*dy<=.002}
level_merge_polygons :: proc(a,b:[]Vec2,out:^[64]Vec2,count:^int,shared_start,shared_finish:^Vec2)->bool {
	count^=0;if len(a)<3||len(b)<3 do return false;edge_a,edge_b:=-1,-1;for point,i in a {next:=a[(i+1)%len(a)];for other,j in b {other_next:=b[(j+1)%len(b)];if level_points_near(point,other_next)&&level_points_near(next,other) {edge_a=i;edge_b=j;break}};if edge_a>=0 do break};if edge_a<0 do return false;shared_start^=a[edge_a];shared_finish^=a[(edge_a+1)%len(a)]
	raw:[64]Vec2;raw_count:=0;for step in 0..<len(a) {raw[raw_count]=a[(edge_a+1+step)%len(a)];raw_count+=1};j:=(edge_b+2)%len(b);for j!=edge_b {raw[raw_count]=b[j];raw_count+=1;j=(j+1)%len(b)};if raw_count<3 do return false
	for i in 0..<raw_count {previous,current,next:=raw[(i-1+raw_count)%raw_count],raw[i],raw[(i+1)%raw_count];cross:=wall_cap_cross(previous,current,next);dx1,dy1:=current.x-previous.x,current.y-previous.y;dx2,dy2:=next.x-current.x,next.y-current.y;if math.abs(cross)<.001&&dx1*dx2+dy1*dy2>=0 do continue;out[count^]=current;count^+=1};return count^>=3&&count^<=32&&level_polygon_simple(out[:count^])
}

level_merge_room_command :: proc(primary,secondary:string)->Level_Command {return {kind=.Merge_Rooms,entity_id=primary,destination=secondary}}

level_wall_command :: proc(doc:^Level_Document,a,b:Vec2)->(Level_Command,bool) {start,finish:=level_snap_point(doc,a,true),level_snap_point(doc,b,true);for room in doc.rooms {if room.story!=doc.active_story||room.exterior do continue;first,second:[34]Vec2;first_count,second_count:=0,0;if level_split_polygon(room.points[:],start,finish,&first,&first_count,&second,&second_count) do return Level_Command{kind=.Split_Room,entity_id=room.id,a=start,b=finish,material=level_next_id("wall",doc.revision),destination=level_next_id("room_split",doc.revision)},true};return Level_Command{kind=.Add_Path,a=start,b=finish,c={f32(Level_Path_Kind.Freestanding_Wall),0},material="structure"},false}

level_point_on_polygon_boundary :: proc(point:Vec2,points:[]Vec2)->bool {for p,i in points do if point_segment_distance_sq(point.x,point.y,p,points[(i+1)%len(points)])<.0001 do return true;return false}
level_polygons_overlap :: proc(a,b:[]Vec2)->bool {
	if len(a)<3||len(b)<3 do return false
	all_a_boundary,all_b_boundary:=true,true;for point in a do if !level_point_on_polygon_boundary(point,b) {all_a_boundary=false;break};for point in b do if !level_point_on_polygon_boundary(point,a) {all_b_boundary=false;break};if all_a_boundary&&all_b_boundary do return true
	for point in a do if !level_point_on_polygon_boundary(point,b)&&level_point_in_polygon(point,b) do return true
	for point in b do if !level_point_on_polygon_boundary(point,a)&&level_point_in_polygon(point,a) do return true
	for pa,i in a {pb:=a[(i+1)%len(a)];for qa,j in b do if level_segments_cross(pa,pb,qa,b[(j+1)%len(b)]) do return true}
	return false
}

level_preview_room_reshape :: proc(doc:^Level_Document,command:Level_Command,result:^Placement_Result) {
	index:=level_room_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected room no longer exists.";return};room:=doc.rooms[index];points:=make([]Vec2,len(room.points),context.temp_allocator);copy(points,room.points[:]);handle:=int(command.value)
	if handle<0||handle>=len(points) {result.state=.Blocked;result.message="The selected handle no longer exists.";return}
	if command.kind==.Move_Room_Vertex {points[handle]=command.a}else{next:=(handle+1)%len(points);points[handle].x+=command.a.x;points[handle].y+=command.a.y;points[next].x+=command.a.x;points[next].y+=command.a.y}
	for point in points {if point.x<0||point.y<0||point.x>f32(doc.width)||point.y>f32(doc.height) {result.state=.Blocked;result.message="The room would leave the lot.";return}}
	if !level_polygon_simple(points) {result.state=.Blocked;result.message="Room edges cannot cross or collapse.";return};if !room.exterior&&!level_points_have_foundation(doc,points,room.story) {result.state=.Blocked;result.message="The room would leave its supporting foundation."}
}

level_room_center :: proc(room:^Level_Room)->Vec2 {center:=Vec2{};if len(room.points)==0 do return center;for point in room.points {center.x+=point.x;center.y+=point.y};center.x/=f32(len(room.points));center.y/=f32(len(room.points));return center}

level_rotated_point :: proc(point,center:Vec2,degrees:f32)->Vec2 {radians:=degrees*f32(math.PI)/180;c,s:=f32(math.cos(f64(radians))),f32(math.sin(f64(radians)));x,y:=point.x-center.x,point.y-center.y;return {center.x+x*c-y*s,center.y+x*s+y*c}}

level_preview_room_transform :: proc(doc:^Level_Document,command:Level_Command,result:^Placement_Result) {
	index:=level_room_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected room no longer exists.";return};room:=&doc.rooms[index];center:=level_room_center(room);points:=make([]Vec2,len(room.points),context.temp_allocator)
	for point,i in room.points {transformed:=point;if command.kind==.Rotate_Room do transformed=level_rotated_point(point,center,command.value);if command.kind==.Duplicate_Room {transformed.x+=command.a.x;transformed.y+=command.a.y};points[i]=transformed;if transformed.x<0||transformed.y<0||transformed.x>f32(doc.width)||transformed.y>f32(doc.height) {result.state=.Blocked;result.message=command.kind==.Duplicate_Room?"The copy would leave the lot.":"The rotated room would leave the lot.";return}};if !room.exterior&&!level_points_have_foundation(doc,points,room.story) {result.state=.Blocked;result.message="The room would leave its supporting foundation."}
}

level_command_preview :: proc(doc:^Level_Document,command:Level_Command)->Placement_Result {
	result:=Placement_Result{.Valid,"READY",command.a,command.b}
	if command.kind==.Create_Foundation {
		if command.point_count<3||command.point_count>len(command.points) {result.state=.Blocked;result.message="A foundation needs at least three corners.";return result};points:=make([]Vec2,command.point_count,context.temp_allocator);for i in 0..<command.point_count {points[i]=command.points[i];point:=points[i];if point.x<0||point.y<0||point.x>f32(doc.width)||point.y>f32(doc.height) {result.state=.Blocked;result.message="The foundation would leave the lot.";return result}};if !level_polygon_simple(points)||math.abs(level_polygon_area(points))<1 {result.state=.Blocked;result.message="The foundation footprint is invalid.";return result};if command.c.x==f32(Level_Foundation_Kind.Basement)&&command.c.y<1.8 {result.state=.Blocked;result.message="A basement needs at least 1.8 meters of depth."}
		if command.c.x==f32(Level_Foundation_Kind.Basement)&&level_basement_story(doc)<0&&len(doc.stories)>=doc.story_limit {result.state=.Blocked;result.message="The story limit leaves no room for a basement.";return result}
	} else if command.kind==.Set_Foundation {
		index:=level_foundation_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected foundation no longer exists.";return result};foundation:=doc.foundations[index];if foundation.kind==.Raised&&(command.value<.25||command.value>3) {result.state=.Blocked;result.message="Raised foundation height must be between 0.25 and 3 meters."}else if foundation.kind==.Basement&&(command.c.y<1.8||command.c.y>6) {result.state=.Blocked;result.message="Basement depth must be between 1.8 and 6 meters."}else if foundation.kind==.Slab&&(command.c.y<.1||command.c.y>1) {result.state=.Blocked;result.message="Slab thickness must be between 0.1 and 1 meter."}
	} else if command.kind==.Move_Foundation_Point {
		index:=level_foundation_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.foundations[index].points) {result.state=.Blocked;result.message="The foundation corner no longer exists.";return result};if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="The foundation would leave the lot.";return result};foundation:=doc.foundations[index];points:=make([]Vec2,len(foundation.points),context.temp_allocator);copy(points,foundation.points[:]);points[point_index]=command.a;if !level_polygon_simple(points)||math.abs(level_polygon_area(points))<1 {result.state=.Blocked;result.message="The foundation footprint is invalid.";return result};for room in doc.rooms {if room.exterior||!level_foundation_supports_story(doc,foundation,room.story) do continue;was_supported:=true;for p in room.points do if !level_foundation_contains_point(foundation,p) {was_supported=false;break};if !was_supported do continue;for p in room.points {if level_point_in_polygon(p,points) do continue;supported_elsewhere:=false;for other,i in doc.foundations {if i!=index&&level_foundation_supports_story(doc,other,room.story)&&level_foundation_contains_point(other,p) {supported_elsewhere=true;break}};if !supported_elsewhere {result.state=.Blocked;result.message="The corner would leave a room without foundation support.";return result}}}
	} else if command.kind==.Delete_Foundation {
		index:=level_foundation_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected foundation no longer exists.";return result};for room in doc.rooms {if room.exterior do continue;supported_elsewhere:=false;for foundation,i in doc.foundations {if i==index||!level_foundation_supports_story(doc,foundation,room.story) do continue;supported:=true;for point in room.points do if !level_foundation_contains_point(foundation,point) {supported=false;break};if supported {supported_elsewhere=true;break}};if !supported_elsewhere&&!level_story_needs_foundation(doc,room.story) do supported_elsewhere=true;if !supported_elsewhere {result.state=.Blocked;result.message="Move or remove supported rooms before deleting this foundation.";return result}}
	} else if command.kind==.Create_Room_Polygon {
		if command.point_count<3||command.point_count>len(command.points) {result.state=.Blocked;result.message="A room needs at least three corners.";return result};points:=make([]Vec2,command.point_count,context.temp_allocator);for i in 0..<command.point_count {points[i]=command.points[i];point:=points[i];if point.x<0||point.y<0||point.x>f32(doc.width)||point.y>f32(doc.height) {result.state=.Blocked;result.message="The room would leave the lot.";return result}};if !level_polygon_simple(points) {result.state=.Blocked;result.message="Room edges cannot cross or collapse.";return result};if command.entity_id==""&&command.material!="" {for room in doc.rooms do if room.story==doc.active_story&&!room.exterior&&level_polygons_overlap(points,room.points[:]) {result.state=.Blocked;result.message="Rooms may share walls but cannot overlap.";return result}}
		if command.destination!="patio"&&!level_points_have_foundation(doc,points,doc.active_story) {result.state=.Blocked;result.message="Lay a foundation before drawing this room.";return result}
	} else if command.kind==.Split_Room {
		index:=level_room_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The room to split no longer exists.";return result};first,second:[34]Vec2;first_count,second_count:=0,0;if !level_split_polygon(doc.rooms[index].points[:],level_snap_point(doc,command.a,true),level_snap_point(doc,command.b,true),&first,&first_count,&second,&second_count) {result.state=.Blocked;result.message="Start and end the divider on different room edges.";return result};if !level_points_have_foundation(doc,first[:first_count],doc.rooms[index].story)||!level_points_have_foundation(doc,second[:second_count],doc.rooms[index].story) {result.state=.Blocked;result.message="Both new rooms must remain supported.";return result};result.message="The wall will divide this into two editable rooms."
	} else if command.kind==.Merge_Rooms {
		first_index,second_index:=level_room_index(doc,command.entity_id),level_room_index(doc,command.destination);if first_index<0||second_index<0||first_index==second_index {result.state=.Blocked;result.message="Select two different rooms to merge.";return result};first,second:=doc.rooms[first_index],doc.rooms[second_index];if first.story!=second.story {result.state=.Blocked;result.message="Rooms must be on the same story.";return result};if first.exterior!=second.exterior {result.state=.Blocked;result.message="Indoor and outdoor rooms cannot be merged.";return result};if math.abs(first.platform_height-second.platform_height)>.01 {result.state=.Blocked;result.message="Match platform heights before merging rooms.";return result};merged:[64]Vec2;merged_count:=0;shared_start,shared_finish:=Vec2{},Vec2{};if !level_merge_polygons(first.points[:],second.points[:],&merged,&merged_count,&shared_start,&shared_finish) {result.state=.Blocked;result.message="The selected rooms need one shared wall.";return result};if first.floor_material!=second.floor_material||first.wall_material!=second.wall_material {result.state=.Warning;result.message="The primary room's finishes will cover the merged room."}else{result.message="The shared wall will be removed."}
	} else if command.kind==.Insert_Room_Vertex||command.kind==.Remove_Room_Vertex {
		index:=level_room_index(doc,command.entity_id);handle:=int(command.value);if index<0||handle<0||handle>=len(doc.rooms[index].points) {result.state=.Blocked;result.message="The selected corner no longer exists.";return result};source:=doc.rooms[index].points;new_count:=command.kind==.Insert_Room_Vertex?len(source)+1:len(source)-1;if new_count<3||new_count>32 {result.state=.Blocked;result.message="Rooms need between three and thirty-two corners.";return result};points:=make([]Vec2,new_count,context.temp_allocator);write:=0;for point,i in source {if command.kind==.Remove_Room_Vertex&&i==handle do continue;points[write]=point;write+=1;if command.kind==.Insert_Room_Vertex&&i==handle {points[write]=command.a;write+=1}};if !level_polygon_simple(points) {result.state=.Blocked;result.message="That corner would collapse or cross the room."}
	} else if command.kind==.Move_Room {
		index:=level_room_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected room no longer exists.";return result}
		points:=make([]Vec2,len(doc.rooms[index].points),context.temp_allocator);for point,i in doc.rooms[index].points {moved:=Vec2{point.x+command.a.x,point.y+command.a.y};points[i]=moved;if moved.x<0||moved.y<0||moved.x>f32(doc.width)||moved.y>f32(doc.height) {result.state=.Blocked;result.message="The room would leave the lot.";return result}};if !doc.rooms[index].exterior&&!level_points_have_foundation(doc,points,doc.rooms[index].story) {result.state=.Blocked;result.message="The room would leave its supporting foundation."}
	} else if command.kind==.Duplicate_Room||command.kind==.Rotate_Room {
		level_preview_room_transform(doc,command,&result)
	} else if command.kind==.Move_Room_Vertex||command.kind==.Move_Room_Edge {
		level_preview_room_reshape(doc,command,&result)
	} else if command.kind==.Duplicate_Object {
		index:=level_object_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected object no longer exists."}else{target:=Vec2{doc.objects[index].position.x+command.a.x,doc.objects[index].position.y+command.a.y};if target.x<0||target.y<0||target.x>f32(doc.width)||target.y>f32(doc.height) {result.state=.Blocked;result.message="The copy would leave the lot."}}
	} else if command.kind==.Add_Light||command.kind==.Set_Light {
		if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="The light would leave the lot.";return result};if command.b.x<=0||command.b.x>40 {result.state=.Blocked;result.message="Light range must be between 0 and 40 meters.";return result};if command.b.y<=0||command.b.y>100 {result.state=.Blocked;result.message="Light intensity must be between 0 and 100.";return result};if command.c.x<0||command.c.x>20 {result.state=.Blocked;result.message="Light elevation must be between 0 and 20 meters.";return result};if command.kind==.Set_Light&&level_light_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected light no longer exists."}
	} else if command.kind==.Delete_Light {
		if level_light_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected light no longer exists."}
	} else if command.kind==.Add_Path {
		count:=command.point_count;if count==0 do count=2;if count<2||count>len(command.points) {result.state=.Blocked;result.message="A path needs at least two control points.";return result};width:=command.value;if width<=0 do width=HOUSE_WALL_THICKNESS;if width<.2||width>8 {result.state=.Blocked;result.message="Path width must be between 0.2 and 8 meters.";return result};for i in 0..<count {p:=count==2&&command.point_count==0?(i==0?command.a:command.b):command.points[i];if p.x<0||p.y<0||p.x>f32(doc.width)||p.y>f32(doc.height) {result.state=.Blocked;result.message="The path leaves the lot.";return result};if i>0 {previous:=count==2&&command.point_count==0?(i-1==0?command.a:command.b):command.points[i-1];dx,dy:=p.x-previous.x,p.y-previous.y;if dx*dx+dy*dy<.04 {result.state=.Blocked;result.message="Path control points are too close.";return result}}}
		kind:=Level_Path_Kind(clamp(int(command.c.x),0,int(Level_Path_Kind.Footpath)));if kind==.Road||kind==.Footpath {for i in 0..<count {p:=count==2&&command.point_count==0?(i==0?command.a:command.b):command.points[i];for room in doc.rooms {if room.story==doc.active_story&&!room.exterior&&level_point_in_polygon(p,room.points[:]) {result.state=.Warning;result.message="The path crosses an interior room.";break}}}}
	} else if command.kind==.Set_Path {
		index:=level_path_index(doc,command.entity_id);if index<0 {result.state=.Blocked;result.message="The selected path no longer exists.";return result};path:=doc.paths[index];minimum:=path.kind==.Wall?f32(.1):f32(.2);maximum:=path.kind==.Wall?f32(1):f32(8);if command.value<minimum||command.value>maximum {result.state=.Blocked;result.message=path.kind==.Wall?"Wall width must be between 0.1 and 1 meter.":"Path width must be between 0.2 and 8 meters."}
	} else if command.kind==.Move_Path_Point {
		index:=level_path_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.paths[index].points) {result.state=.Blocked;result.message="The path control point no longer exists.";return result};if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="The path point would leave the lot.";return result};path:=doc.paths[index];neighbors:=[2]int{point_index-1,point_index+1};for neighbor in neighbors {if neighbor>=0&&neighbor<len(path.points) {dx,dy:=command.a.x-path.points[neighbor].x,command.a.y-path.points[neighbor].y;if dx*dx+dy*dy<.04 {result.state=.Blocked;result.message="Path control points are too close.";return result}}}
	} else if command.kind==.Create_Water {
		if command.point_count<3||command.point_count>len(command.points) {result.state=.Blocked;result.message="A pond needs at least three shoreline points.";return result};points:=make([]Vec2,command.point_count,context.temp_allocator);for i in 0..<command.point_count {points[i]=command.points[i];p:=points[i];if p.x<0||p.y<0||p.x>f32(doc.width)||p.y>f32(doc.height) {result.state=.Blocked;result.message="The shoreline leaves the lot.";return result}};if !level_polygon_simple(points) {result.state=.Blocked;result.message="The shoreline cannot cross itself.";return result};if math.abs(level_polygon_area(points))<.5 {result.state=.Blocked;result.message="The pond is too small."}
		if result.state!=.Blocked {for p in points {for room in doc.rooms {if !room.exterior&&level_point_in_polygon(p,room.points[:]) {result.state=.Warning;result.message="The pond overlaps an interior room.";break}}}}
	} else if command.kind==.Set_Water {
		if level_water_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected pond no longer exists."}else if command.value< -5||command.value>5 {result.state=.Blocked;result.message="Water elevation must be between -5 and 5 meters."}
	} else if command.kind==.Move_Water_Point {
		index:=level_water_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.waters[index].points) {result.state=.Blocked;result.message="The shoreline point no longer exists.";return result};if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="The shoreline would leave the lot.";return result};points:=make([]Vec2,len(doc.waters[index].points),context.temp_allocator);copy(points,doc.waters[index].points[:]);points[point_index]=command.a;if !level_polygon_simple(points) {result.state=.Blocked;result.message="The shoreline cannot cross itself.";return result};if math.abs(level_polygon_area(points))<.5 {result.state=.Blocked;result.message="The pond is too small."}
	} else if command.kind==.Delete_Water {
		if level_water_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected pond no longer exists."}
	} else if command.kind==.Add_Opening||command.kind==.Set_Opening {
		if command.kind==.Set_Opening&&level_opening_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected opening no longer exists.";return result};path_index:=level_path_index(doc,command.material);segment:=int(command.value);if path_index<0||segment<0||segment>=len(doc.paths[path_index].points)-1 {result.state=.Blocked;result.message="Choose a valid wall span.";return result};path:=doc.paths[path_index];if path.story!=doc.active_story {result.state=.Blocked;result.message="The wall is on another story.";return result};a,b:=path.points[segment],path.points[segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));kind:=Level_Opening_Kind(clamp(int(command.b.x),0,int(Level_Opening_Kind.Gate)));default_width:=kind==.Window?f32(1.6):kind==.Arch?f32(1.5):kind==.Gate?f32(1.4):f32(1.2);default_height:=kind==.Window?f32(1.4):kind==.Arch?f32(2.2):kind==.Gate?f32(1.5):f32(2.1);width:=command.b.y>0?command.b.y:default_width;height:=command.c.y>0?command.c.y:default_height;if width<.4||width>6 {result.state=.Blocked;result.message="Opening width must be between 0.4 and 6 meters.";return result};if height<.4||height>4 {result.state=.Blocked;result.message="Opening height must be between 0.4 and 4 meters.";return result};end_clearance:=level_opening_end_clearance(kind);if length<width+end_clearance*2 {result.state=.Blocked;result.message="This wall span is too short for the opening and its trim.";return result};position:=clamp(command.c.x,(width*.5+end_clearance)/length,1-(width*.5+end_clearance)/length);center:=position*length;for opening in doc.openings {if opening.id==command.entity_id||opening.host_path!=command.material||opening.segment!=segment do continue;other_center:=opening.position*length;if math.abs(center-other_center)<(width+opening.width)*.5+level_opening_finish_clearance(kind,opening.kind) {result.state=.Blocked;result.message="Finished opening trim needs clear wall between openings.";return result}};result.bounds_min={a.x+dx*position,a.y+dy*position};result.bounds_max=result.bounds_min
		if kind==.Window {sill_height:=command.points[0].x;if sill_height<=0 do sill_height=.72;wall_height:=doc.stories[path.story].wall_height;if sill_height<.2||sill_height>2 {result.state=.Blocked;result.message="Window sill height must be between 0.2 and 2 meters.";return result};if wall_height>0&&level_window_head_finish_height(sill_height,height)>wall_height+.001 {result.state=.Blocked;result.message="Window head trim and flashing must remain below the wall top.";return result}}
	} else if command.kind==.Create_Roof||command.kind==.Set_Roof {
		room_index:=level_room_index(doc,command.material);if room_index<0 {result.state=.Blocked;result.message="Choose a room footprint for the roof.";return result};room:=doc.rooms[room_index];if len(room.points)<3||!level_polygon_simple(room.points[:]) {result.state=.Blocked;result.message="The room footprint cannot generate a roof.";return result};if command.value<1||command.value>75 {result.state=.Blocked;result.message="Roof pitch must be between 1 and 75 degrees.";return result};if command.b.x<0||command.b.x>2 {result.state=.Blocked;result.message="Roof overhang must be between 0 and 2 meters.";return result};if command.kind==.Create_Roof&&level_roof_for_room(doc,command.material)>=0 {result.state=.Blocked;result.message="This room already has a roof."}
	} else if command.kind==.Delete_Roof {
		if level_roof_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected roof no longer exists."}
	} else if command.kind==.Create_Vertical_Link {
		to_story:=level_story_above(doc,doc.active_story);if doc.active_story<0||to_story<0 {result.state=.Blocked;result.message="Add or select a story above this one.";return result}
		if command.value<.6||command.value>3 {result.state=.Blocked;result.message="Stair width must be between 0.6 and 3 meters.";return result}
		landings:=[2]Vec2{command.a,command.b};for p in landings {if p.x<0||p.y<0||p.x>f32(doc.width)||p.y>f32(doc.height) {result.state=.Blocked;result.message="Both landings must stay inside the lot.";return result}}
		dx,dy:=command.b.x-command.a.x,command.b.y-command.a.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));if distance<command.value*1.5 {result.state=.Blocked;result.message="The landings are too close for a valid stair turn.";return result};rise:=doc.stories[to_story].base_elevation-doc.stories[doc.active_story].base_elevation;if rise<1.8||rise>6 {result.state=.Blocked;result.message="The adjacent story elevation cannot be reached by stairs.";return result};required:=rise/.18*.28;if distance<required*.55 {result.state=.Warning;result.message="A compact U-shaped stair will be generated."}else if distance<required*.9 {result.state=.Warning;result.message="An L-shaped stair will be generated."};result.bounds_min={min(command.a.x,command.b.x)-command.value*.5,min(command.a.y,command.b.y)-command.value*.5};result.bounds_max={max(command.a.x,command.b.x)+command.value*.5,max(command.a.y,command.b.y)+command.value*.5}
	} else if command.kind==.Set_Vertical_Link {
		if level_vertical_link_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected vertical link no longer exists."}else if command.value<.6||command.value>3 {result.state=.Blocked;result.message="Link width must be between 0.6 and 3 meters."}
	} else if command.kind==.Move_Vertical_Link_Point {
		index:=level_vertical_link_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>1 {result.state=.Blocked;result.message="The selected landing no longer exists.";return result};link:=doc.vertical_links[index];if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="The landing must stay inside the lot.";return result};other:=point_index==0?link.finish:link.start;dx,dy:=command.a.x-other.x,command.a.y-other.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)));if distance<link.width*1.5 {result.state=.Blocked;result.message="The landings are too close for a valid stair turn.";return result};if link.from_story<0||link.to_story<0||link.from_story>=len(doc.stories)||link.to_story>=len(doc.stories) {result.state=.Blocked;result.message="The linked stories no longer exist.";return result};rise:=doc.stories[link.to_story].base_elevation-doc.stories[link.from_story].base_elevation;required:=rise/.18*.28;if distance<required*.55 {result.state=.Warning;result.message="A compact U-shaped stair will be generated."}else if distance<required*.9 {result.state=.Warning;result.message="An L-shaped stair will be generated."};result.bounds_min={min(command.a.x,other.x)-link.width*.5,min(command.a.y,other.y)-link.width*.5};result.bounds_max={max(command.a.x,other.x)+link.width*.5,max(command.a.y,other.y)+link.width*.5}
	} else if command.kind==.Delete_Vertical_Link {
		if level_vertical_link_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected vertical link no longer exists."}
	} else if command.kind==.Delete_Marker {
		if level_marker_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected marker no longer exists."}
	} else if command.kind==.Create_Room||command.kind==.Place_Object||command.kind==.Move_Object||command.kind==.Sculpt_Terrain||command.kind==.Add_Marker||command.kind==.Set_Marker {
		if command.a.x<0||command.a.y<0||command.a.x>f32(doc.width)||command.a.y>f32(doc.height) {result.state=.Blocked;result.message="Placement is outside the lot."}
		if command.kind==.Set_Marker&&level_marker_index(doc,command.entity_id)<0 {result.state=.Blocked;result.message="The selected marker no longer exists.";return result}
		if command.kind==.Set_Marker&&command.interaction_prompt!=""&&command.interaction_prompt!=command.entity_id {if !graph_valid_id(command.interaction_prompt) {result.state=.Blocked;result.message="Marker names use letters, numbers, and underscores.";return result};if level_marker_index(doc,command.interaction_prompt)>=0 {result.state=.Blocked;result.message="That marker name is already in use.";return result}}
		if (command.kind==.Add_Marker||command.kind==.Set_Marker)&&command.b.x<=0 {result.state=.Blocked;result.message="Marker radius must be greater than zero.";return result}
		if command.kind==.Add_Marker||command.kind==.Set_Marker {kind:=Level_Marker_Kind(clamp(int(command.c.y),0,int(Level_Marker_Kind.Staging)));if (kind==.Character_Spawn||kind==.Interaction||kind==.Clue)&&command.material=="" {result.state=.Warning;result.message="Bind this marker to a qualified StoryCore spatial target."}else if kind==.Trigger&&command.material=="" {result.state=.Warning;result.message="Bind this trigger to a story event."}else if kind==.Transition&&command.destination=="" {result.state=.Warning;result.message="Choose a destination marker."}}
		if command.kind==.Sculpt_Terrain&&(command.b.x<0||command.b.y<0||command.b.x>f32(doc.width)||command.b.y>f32(doc.height)) {result.state=.Blocked;result.message="The terrain stroke leaves the lot."}
		if command.kind==.Sculpt_Terrain&&result.state!=.Blocked {radius:=max(command.value,.25);for y in 0..=doc.height {for x in 0..=doc.width {point:=Vec2{f32(x),f32(y)};distance,_:=level_segment_distance(point,command.a,command.b);if distance<=radius&&level_terrain_reserved_by_foundation(doc,point) {result.state=.Blocked;result.message="Terrain beneath a foundation or basement is locked.";return result}}}}
		if command.kind==.Place_Object&&result.state!=.Blocked&&editor_catalog.loaded {
			entry,found:=catalog_object_entry(command.material);if !found||!entry.valid {result.state=.Blocked;result.message="This catalog model is unavailable.";return result}
			radius:=max(entry.footprint,.2);if command.a.x-radius<0||command.a.y-radius<0||command.a.x+radius>f32(doc.width)||command.a.y+radius>f32(doc.height) {result.state=.Blocked;result.message="The object's footprint leaves the lot.";return result}
			if command.destination!="" {support_index:=level_object_index(doc,command.destination);if support_index<0||doc.objects[support_index].story!=doc.active_story {result.state=.Blocked;result.message="The furniture support is no longer available.";return result};if command.c.x<=doc.objects[support_index].elevation {result.state=.Blocked;result.message="The furniture surface height is invalid.";return result};result.message="Place on furniture."}
			inside:=false;for room in doc.rooms do if room.story==doc.active_story&&!room.exterior&&level_point_in_polygon(command.a,room.points[:]) do inside=true
			if entry.placement=="indoor"&&!inside {result.state=.Warning;result.message="This object is authored for indoor placement."}
			for object in doc.objects {if object.story!=doc.active_story||object.id==command.destination do continue;other_entry,other_found:=catalog_object_entry(object.catalog_id);other_radius:=f32(.35);if other_found do other_radius=max(other_entry.footprint,.2);dx,dy:=object.position.x-command.a.x,object.position.y-command.a.y;if dx*dx+dy*dy<(radius+other_radius)*(radius+other_radius) {result.state=.Warning;result.message="Object footprints overlap.";break}}
			if command.destination=="" {
				doorway_badness:=level_furniture_doorway_badness(doc,command.a,radius)
				// A warning is intentionally overridable, so agents were allowed to
				// commit furniture whose footprint actually crossed the opening.  Keep
				// the softer approach/circulation ring as a warning, but make contact
				// with the doorway itself a hard placement failure.
				if doorway_badness>=.999 {result.state=.Blocked;result.message="Furniture footprint obstructs a doorway.";return result}
				if level_furniture_circulation_cost(doc,command.a,radius)>=.78 {result.state=.Warning;result.message="Furniture blocks a door approach or circulation space."}
			}
			if level_catalog_entry_uses_surface(entry,"wall") {wall_score:=level_wall_hanging_badness(doc,command.a,command.c.x,command.value,entry,command.entity_id);if wall_score.total>=.5 {result.state=.Warning;if wall_score.opening_overlap>=.5 do result.message="Wall hanging overlaps a door or window.";else if wall_score.wall_penetration>=.5 do result.message="Wall hanging intersects the wall.";else if wall_score.vertical_fit>=.5 do result.message="Wall hanging does not fit between the floor and wall top.";else if wall_score.hanging_overlap>=.5 do result.message="Wall hangings overlap.";else if wall_score.wall_distance>=.5 do result.message="Wall hanging is not attached to a wall.";else do result.message="Wall hanging is not aligned with its wall."}}
		}
	}
	if command.kind==.Create_Room {if math.abs((command.b.x-command.a.x)*(command.b.y-command.a.y))<1 {result.state=.Blocked;result.message="Room needs at least one square meter.";return result};a,b:=level_snap_point(doc,command.a),level_snap_point(doc,command.b);points:=[4]Vec2{{min(a.x,b.x),min(a.y,b.y)},{max(a.x,b.x),min(a.y,b.y)},{max(a.x,b.x),max(a.y,b.y)},{min(a.x,b.x),max(a.y,b.y)}};if command.destination!="patio"&&!level_points_have_foundation(doc,points[:],doc.active_story) {result.state=.Blocked;result.message="Lay a foundation before drawing this room.";return result};if command.entity_id==""&&command.material!="" {for room in doc.rooms do if room.story==doc.active_story&&!room.exterior&&level_polygons_overlap(points[:],room.points[:]) {result.state=.Blocked;result.message="Rooms may share walls but cannot overlap.";return result}}}
	return result
}

level_room_index :: proc(doc:^Level_Document,id:string)->int {for room,i in doc.rooms do if room.id==id do return i;return -1}

// Furniture placement uses the same circulation field that the editor draws on
// the floor.  Keeping this in the level domain makes the warning and heatmap
// agree, and gives agents a cheap score they can query before committing.
LEVEL_CIRCULATION_DOOR_CLEARANCE :: f32(1.35)
LEVEL_CIRCULATION_FURNITURE_CLEARANCE :: f32(.45)

Wall_Hanging_Badness :: struct {wall_distance, wall_penetration, alignment, opening_overlap, vertical_fit, hanging_overlap, total:f32}

level_catalog_entry_uses_surface :: proc(entry:^Catalog_Entry,surface:string)->bool {for candidate in entry.surfaces do if candidate==surface do return true;return false}

level_wall_hanging_badness :: proc(doc:^Level_Document,point:Vec2,elevation,rotation:f32,entry:^Catalog_Entry,ignore_object_id:="")->Wall_Hanging_Badness {
	result:=Wall_Hanging_Badness{wall_distance=1,alignment=1}
	best_path,best_segment:=-1,-1;best_distance:=f32(1e30);best_t:=f32(0);best_length:=f32(0);best_heading:=f32(0)
	for path,path_index in doc.paths {if path.story!=doc.active_story||(path.kind!=.Wall&&path.kind!=.Freestanding_Wall&&path.kind!=.Half_Wall) do continue;for segment in 0..<len(path.points)-1 {a,b:=path.points[segment],path.points[segment+1];distance,t:=level_segment_distance(point,a,b);if distance<best_distance {dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<=.001 do continue;best_path=path_index;best_segment=segment;best_distance=distance;best_t=t;best_length=length;best_heading=f32(math.atan2(f64(dy),f64(dx)))*180/f32(math.PI)}}}
	if best_path<0 {result.total=1;return result}
	// Measure the valid attachment band from the actual wall face and model back,
	// rather than from a fixed centerline distance. This works for both thin room
	// partitions and thick exterior masonry.
	path:=doc.paths[best_path];wall_half_depth:=house_wall_width(path.width)*.5;object_half_depth:=max(entry.dimensions.z*.5,f32(.01));mounting_allowance:=min(object_half_depth,f32(.015));minimum_center_distance:=wall_half_depth+object_half_depth-mounting_allowance
	result.wall_penetration=clamp((minimum_center_distance-best_distance)/max(object_half_depth,f32(.05)),0,1)
	maximum_center_distance:=wall_half_depth+object_half_depth+.12;result.wall_distance=clamp((best_distance-maximum_center_distance)/.28,0,1)
	delta:=math.abs(rotation-best_heading);for delta>=180 do delta-=180;if delta>90 do delta=180-delta;result.alignment=clamp((delta-5)/25,0,1)
	half_width:=max(entry.dimensions.x*.5,.1);bottom:=elevation;top:=elevation+max(entry.dimensions.y,.1);wall_height:=doc.stories[doc.active_story].wall_height
	if bottom<.25 do result.vertical_fit=max(result.vertical_fit,clamp((.25-bottom)/.25,0,1));if top>wall_height-.1 do result.vertical_fit=max(result.vertical_fit,clamp((top-(wall_height-.1))/.3,0,1))
	center_along:=best_t*best_length
	for opening in doc.openings {if opening.host_path!=path.id||opening.segment!=best_segment do continue;opening_center:=opening.position*best_length;horizontal_overlap:=half_width+opening.width*.5-math.abs(center_along-opening_center);if horizontal_overlap<=0 do continue;opening_bottom:=opening.kind==.Window?opening.sill_height:f32(0);opening_top:=opening_bottom+opening.height;vertical_overlap:=min(top,opening_top)-max(bottom,opening_bottom);if vertical_overlap>0 do result.opening_overlap=max(result.opening_overlap,clamp(min(horizontal_overlap/(half_width+.01),vertical_overlap/max(entry.dimensions.y,.1)),0,1))}
	for object in doc.objects {if object.id==ignore_object_id||object.story!=doc.active_story do continue;other,found:=catalog_object_entry(object.catalog_id);if !found||!level_catalog_entry_uses_surface(other,"wall") do continue;distance,other_t:=level_segment_distance(object.position,path.points[best_segment],path.points[best_segment+1]);if distance>.4 do continue;other_half_width:=max(other.dimensions.x*.5,.1);horizontal_overlap:=half_width+other_half_width-math.abs(center_along-other_t*best_length);vertical_overlap:=min(top,object.elevation+max(other.dimensions.y,.1))-max(bottom,object.elevation);if horizontal_overlap>0&&vertical_overlap>0 do result.hanging_overlap=max(result.hanging_overlap,clamp(min(horizontal_overlap/(half_width+.01),vertical_overlap/max(entry.dimensions.y,.1)),0,1))}
	result.total=max(result.wall_distance,result.wall_penetration,result.alignment,result.opening_overlap,result.vertical_fit,result.hanging_overlap)
	return result
}

level_opening_position :: proc(doc:^Level_Document,opening:Level_Opening)->(Vec2,bool) {
	path_index:=level_path_index(doc,opening.host_path);if path_index<0 do return {},false
	path:=doc.paths[path_index];if path.story!=doc.active_story||opening.segment<0||opening.segment>=len(path.points)-1 do return {},false
	a,b:=path.points[opening.segment],path.points[opening.segment+1]
	return {a.x+(b.x-a.x)*opening.position,a.y+(b.y-a.y)*opening.position},true
}

level_furniture_doorway_badness :: proc(doc:^Level_Document,point:Vec2,radius:f32)->f32 {
	result:=f32(0)
	for opening in doc.openings {
		if opening.kind!=.Door do continue
		path_index:=level_path_index(doc,opening.host_path);if path_index<0 do continue
		path:=doc.paths[path_index];if path.story!=doc.active_story||opening.segment<0||opening.segment>=len(path.points)-1 do continue
		a,b:=path.points[opening.segment],path.points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<=.001 do continue
		center:=opening.position*length;half_width:=opening.width*.5
		start:=Vec2{a.x+dx*(center-half_width)/length,a.y+dy*(center-half_width)/length}
		finish:=Vec2{a.x+dx*(center+half_width)/length,a.y+dy*(center+half_width)/length}
		distance,_:=level_segment_distance(point,start,finish)
		// One means the circular catalog footprint reaches the threshold line.
		// The short falloff is useful to callers that want to rank near misses.
		result=max(result,clamp(1-(distance-radius)/.35,0,1))
	}
	return result
}

level_object_blocks_circulation :: proc(object:Level_Object,entry:^Catalog_Entry,found:bool)->bool {
	if object.support_id!=""||object.elevation>.05 do return false
	if found&&(entry.category=="rugs"||entry.placement=="wall") do return false
	return true
}

level_circulation_cost :: proc(doc:^Level_Document,point:Vec2,ignore_object_id:="")->f32 {
	cost:=f32(0)
	for opening in doc.openings {
		if opening.kind!=.Door do continue
		position,ok:=level_opening_position(doc,opening);if !ok do continue
		dx,dy:=point.x-position.x,point.y-position.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)))
		// The inner disk protects the doorway itself.  The soft outer ring keeps a
		// readable approach lane without making an entire small room look invalid.
		cost=max(cost,clamp(1-(distance-LEVEL_CIRCULATION_DOOR_CLEARANCE)/1.25,0,1))
	}
	for object in doc.objects {
		if object.story!=doc.active_story||object.id==ignore_object_id do continue
		entry,found:=catalog_object_entry(object.catalog_id);if !level_object_blocks_circulation(object,entry,found) do continue;radius:=f32(.35);if found do radius=max(entry.footprint,.2)
		dx,dy:=point.x-object.position.x,point.y-object.position.y;distance:=f32(math.sqrt(f64(dx*dx+dy*dy)))
		cost=max(cost,clamp(1-(distance-radius)/LEVEL_CIRCULATION_FURNITURE_CLEARANCE,0,1))
	}
	return cost
}

level_furniture_circulation_cost :: proc(doc:^Level_Document,point:Vec2,radius:f32,ignore_object_id:="")->f32 {
	// Sample the center and four footprint edges so large furniture cannot hide a
	// blocked door behind a harmless-looking center point.
	result:=level_circulation_cost(doc,point,ignore_object_id);samples:=[4]Vec2{{point.x-radius,point.y},{point.x+radius,point.y},{point.x,point.y-radius},{point.x,point.y+radius}}
	for sample in samples do result=max(result,level_circulation_cost(doc,sample,ignore_object_id))
	return result
}
level_foundation_index :: proc(doc:^Level_Document,id:string)->int {for foundation,i in doc.foundations do if foundation.id==id do return i;return -1}
level_basement_story :: proc(doc:^Level_Document)->int {best:=-1;best_elevation:=f32(-1000000);for story,i in doc.stories do if story.base_elevation<-.01&&story.base_elevation>best_elevation {best=i;best_elevation=story.base_elevation};return best}
level_ground_story :: proc(doc:^Level_Document)->int {best:=-1;best_distance:=f32(1000000);for story,i in doc.stories {distance:=math.abs(story.base_elevation);if distance<best_distance {best=i;best_distance=distance}};return best}
level_story_needs_foundation :: proc(doc:^Level_Document,story:int)->bool {if story<0||story>=len(doc.stories) do return true;return doc.stories[story].base_elevation<=.01}
level_foundation_supports_story :: proc(doc:^Level_Document,foundation:Level_Foundation,story:int)->bool {if story<0||story>=len(doc.stories) do return false;elevation:=doc.stories[story].base_elevation;if elevation<-.01 do return foundation.kind==.Basement&&foundation.story==story;if elevation<=.01 do return true;return false}
level_path_index :: proc(doc:^Level_Document,id:string)->int {for path,i in doc.paths do if path.id==id do return i;return -1}
level_opening_index :: proc(doc:^Level_Document,id:string)->int {for opening,i in doc.openings do if opening.id==id do return i;return -1}
level_object_index :: proc(doc:^Level_Document,id:string)->int {for object,i in doc.objects do if object.id==id do return i;return -1}
level_light_index :: proc(doc:^Level_Document,id:string)->int {for light,i in doc.lights do if light.id==id do return i;return -1}
level_roof_index :: proc(doc:^Level_Document,id:string)->int {for roof,i in doc.roofs do if roof.id==id do return i;return -1}
level_roof_for_room :: proc(doc:^Level_Document,room_id:string)->int {for roof,i in doc.roofs do if roof.room_id==room_id do return i;return -1}
level_vertical_link_index :: proc(doc:^Level_Document,id:string)->int {for link,i in doc.vertical_links do if link.id==id do return i;return -1}
level_water_index :: proc(doc:^Level_Document,id:string)->int {for water,i in doc.waters do if water.id==id do return i;return -1}
level_marker_index :: proc(doc:^Level_Document,id:string)->int {for marker,i in doc.markers do if marker.id==id do return i;return -1}
level_foundation_contains_point :: proc(foundation:Level_Foundation,point:Vec2)->bool {if level_point_in_polygon(point,foundation.points[:]) do return true;for i in 0..<len(foundation.points) do if point_segment_distance_sq(point.x,point.y,foundation.points[i],foundation.points[(i+1)%len(foundation.points)])<=.001 do return true;return false}
level_foundation_contains_polygon :: proc(foundation:Level_Foundation,points:[]Vec2)->bool {if len(points)<3 do return false;for point in points do if !level_foundation_contains_point(foundation,point) do return false;for point,i in points {next:=points[(i+1)%len(points)];mid:=Vec2{(point.x+next.x)*.5,(point.y+next.y)*.5};if !level_foundation_contains_point(foundation,mid) do return false;for edge,j in foundation.points {if level_segments_cross(point,next,edge,foundation.points[(j+1)%len(foundation.points)]) do return false}};return true}
level_room_has_foundation :: proc(doc:^Level_Document,room:Level_Room)->bool {if room.exterior||!level_story_needs_foundation(doc,room.story) do return true;return level_points_have_foundation(doc,room.points[:],room.story)}
level_points_have_foundation :: proc(doc:^Level_Document,points:[]Vec2,story:int)->bool {if !level_story_needs_foundation(doc,story) do return true;for foundation in doc.foundations do if level_foundation_supports_story(doc,foundation,story)&&level_foundation_contains_polygon(foundation,points) do return true;return false}
level_terrain_reserved_by_foundation :: proc(doc:^Level_Document,point:Vec2)->bool {for foundation in doc.foundations do if level_foundation_contains_point(foundation,point) do return true;return false}
level_selection_for_id :: proc(doc:^Level_Document,id:string)->Editor_Selection {if id=="" do return {};if level_marker_index(doc,id)>=0 do return {.Marker,id,-1};if level_light_index(doc,id)>=0 do return {.Light,id,-1};if level_opening_index(doc,id)>=0 do return {.Opening,id,-1};if level_object_index(doc,id)>=0 do return {.Object,id,-1};if level_roof_index(doc,id)>=0 do return {.Roof,id,-1};if level_vertical_link_index(doc,id)>=0 do return {.Vertical_Link,id,-1};if level_water_index(doc,id)>=0 do return {.Water,id,-1};if level_path_index(doc,id)>=0 do return {.Path,id,-1};if level_foundation_index(doc,id)>=0 do return {.Foundation,id,-1};if level_room_index(doc,id)>=0 do return {.Room,id,-1};return {}}
level_selection_position :: proc(doc:^Level_Document,selection:Editor_Selection)->(Vec2,bool) {#partial switch selection.kind {case .Room,.Edge,.Vertex:index:=level_room_index(doc,selection.entity_id);if index>=0 do return level_room_center(&doc.rooms[index]),true;case .Foundation:index:=level_foundation_index(doc,selection.entity_id);if index>=0&&len(doc.foundations[index].points)>0 {center:=Vec2{};for p in doc.foundations[index].points {center.x+=p.x;center.y+=p.y};return {center.x/f32(len(doc.foundations[index].points)),center.y/f32(len(doc.foundations[index].points))},true};case .Opening:index:=level_opening_index(doc,selection.entity_id);if index>=0 {opening:=doc.openings[index];path_index:=level_path_index(doc,opening.host_path);if path_index>=0&&opening.segment>=0&&opening.segment<len(doc.paths[path_index].points)-1 {a,b:=doc.paths[path_index].points[opening.segment],doc.paths[path_index].points[opening.segment+1];return {a.x+(b.x-a.x)*opening.position,a.y+(b.y-a.y)*opening.position},true}};case .Object:index:=level_object_index(doc,selection.entity_id);if index>=0 do return doc.objects[index].position,true;case .Light:index:=level_light_index(doc,selection.entity_id);if index>=0 do return doc.lights[index].position,true;case .Marker:index:=level_marker_index(doc,selection.entity_id);if index>=0 do return doc.markers[index].position,true;case .Path:index:=level_path_index(doc,selection.entity_id);if index>=0&&len(doc.paths[index].points)>0 {center:=Vec2{};for p in doc.paths[index].points {center.x+=p.x;center.y+=p.y};return {center.x/f32(len(doc.paths[index].points)),center.y/f32(len(doc.paths[index].points))},true};case .Water:index:=level_water_index(doc,selection.entity_id);if index>=0&&len(doc.waters[index].points)>0 {center:=Vec2{};for p in doc.waters[index].points {center.x+=p.x;center.y+=p.y};return {center.x/f32(len(doc.waters[index].points)),center.y/f32(len(doc.waters[index].points))},true};case .Vertical_Link:index:=level_vertical_link_index(doc,selection.entity_id);if index>=0 {link:=doc.vertical_links[index];return {(link.start.x+link.finish.x)*.5,(link.start.y+link.finish.y)*.5},true}};return {},false}
level_next_id :: proc(prefix:string,revision:u64)->string {return fmt.tprintf("%s_%d",prefix,revision+1)}
level_snap_point :: proc(doc:^Level_Document,p:Vec2,fine:=false)->Vec2 {if editor_state.snap_mode==.Off||editor_state.snap_suspended do return p;step:=editor_state.snap_mode==.Fine?doc.fine_snap:doc.default_snap;if step<=0 do return p;return {f32(math.round(f64(p.x/step)))*step,f32(math.round(f64(p.y/step)))*step}}
level_terrain_sample :: proc(doc:^Level_Document,x,y:int)->f32 {sample_x,sample_y:=clamp(x,0,doc.width),clamp(y,0,doc.height);index:=sample_y*(doc.width+1)+sample_x;if index<0||index>=len(doc.terrain) do return 0;return doc.terrain[index]}
level_terrain_height :: proc(doc:^Level_Document,p:Vec2)->f32 {
	x:=clamp(p.x,0,f32(doc.width));y:=clamp(p.y,0,f32(doc.height));x0,y0:=int(math.floor(f64(x))),int(math.floor(f64(y)));x1,y1:=min(x0+1,doc.width),min(y0+1,doc.height);tx,ty:=x-f32(x0),y-f32(y0)
	a:=level_terrain_sample(doc,x0,y0)+(level_terrain_sample(doc,x1,y0)-level_terrain_sample(doc,x0,y0))*tx
	b:=level_terrain_sample(doc,x0,y1)+(level_terrain_sample(doc,x1,y1)-level_terrain_sample(doc,x0,y1))*tx
	return a+(b-a)*ty
}
level_terrain_supports_position :: proc(doc:^Level_Document,p:Vec2,story:int)->bool {if story!=0 do return false;for room in doc.rooms do if room.story==story&&room.exterior&&level_point_in_polygon(p,room.points[:]) do return true;return false}

level_segment_distance :: proc(point,a,b:Vec2)->(distance,t:f32) {dx,dy:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dy*dy;if length_sq<=.0001 {ex,ey:=point.x-a.x,point.y-a.y;return f32(math.sqrt(f64(ex*ex+ey*ey))),0};t=clamp(((point.x-a.x)*dx+(point.y-a.y)*dy)/length_sq,0,1);ex,ey:=point.x-(a.x+dx*t),point.y-(a.y+dy*t);return f32(math.sqrt(f64(ex*ex+ey*ey))),t}

level_apply_raw :: proc(doc:^Level_Document,command:Level_Command)->(inverse:Level_Command,ok:bool) {
	preview:=level_command_preview(doc,command);if preview.state==.Blocked do return {},false
	#partial switch command.kind {
	case .Set_Metadata:
		if command.metadata_id==""||command.metadata_width<=0||command.metadata_height<=0 do return {},false;old:=Level_Command{kind=.Set_Metadata,metadata_id=doc.id,metadata_name=doc.name,metadata_width=doc.width,metadata_height=doc.height};doc.id=command.metadata_id;doc.name=command.metadata_name;if doc.width!=command.metadata_width||doc.height!=command.metadata_height {doc.width=command.metadata_width;doc.height=command.metadata_height;delete(doc.terrain);doc.terrain=make([dynamic]f32,(doc.width+1)*(doc.height+1))};return old,true
	case .Add_Story:
		if !graph_valid_id(command.story.id)||len(doc.stories)>=doc.story_limit do return {},false;for story in doc.stories do if story.id==command.story.id do return {},false;append(&doc.stories,command.story);return Level_Command{kind=.Delete_Story,entity_id=command.story.id},true
	case .Update_Story:
		index:=-1;for story,i in doc.stories do if story.id==command.entity_id do index=i;if index<0 do return {},false;old:=doc.stories[index];doc.stories[index]=command.story;for &room in doc.rooms do if room.story==index do room.story=index;return Level_Command{kind=.Update_Story,entity_id=command.story.id,story=old},true
	case .Delete_Story:
		index:=-1;for story,i in doc.stories do if story.id==command.entity_id do index=i;if index<0||len(doc.stories)<=1 do return {},false;for room in doc.rooms do if room.story==index do return {},false;for object in doc.objects do if object.story==index do return {},false;for marker in doc.markers do if marker.story==index do return {},false;old:=doc.stories[index];ordered_remove(&doc.stories,index);for &room in doc.rooms do if room.story>index do room.story-=1;for &object in doc.objects do if object.story>index do object.story-=1;for &marker in doc.markers do if marker.story>index do marker.story-=1;return Level_Command{kind=.Add_Story,story=old},true
	case .Reorder_Story:
		if command.from<0||command.to<0||command.from>=len(doc.stories)||command.to>=len(doc.stories) do return {},false;item:=doc.stories[command.from];if command.from<command.to {for i in command.from..<command.to do doc.stories[i]=doc.stories[i+1]}else{for i:=command.from;i>command.to;i-=1 do doc.stories[i]=doc.stories[i-1]};doc.stories[command.to]=item;for &room in doc.rooms {if room.story==command.from do room.story=command.to;else if command.from<command.to&&room.story>command.from&&room.story<=command.to do room.story-=1;else if command.from>command.to&&room.story>=command.to&&room.story<command.from do room.story+=1};for &object in doc.objects {if object.story==command.from do object.story=command.to;else if command.from<command.to&&object.story>command.from&&object.story<=command.to do object.story-=1;else if command.from>command.to&&object.story>=command.to&&object.story<command.from do object.story+=1};for &marker in doc.markers {if marker.story==command.from do marker.story=command.to;else if command.from<command.to&&marker.story>command.from&&marker.story<=command.to do marker.story-=1;else if command.from>command.to&&marker.story>=command.to&&marker.story<command.from do marker.story+=1};return Level_Command{kind=.Reorder_Story,from=command.to,to=command.from},true
	case .Set_Story_Height:
		index:=-1;for story,i in doc.stories do if story.id==command.entity_id {index=i;break};if index<0||command.value<2.2||command.value>6 do return {},false;old:=doc.stories[index].wall_height;delta:=command.value-old;base:=doc.stories[index].base_elevation;doc.stories[index].wall_height=command.value;for &story,i in doc.stories do if i!=index&&story.base_elevation>base do story.base_elevation+=delta;return Level_Command{kind=.Set_Story_Height,entity_id=command.entity_id,value=old},true
	case .Create_Foundation:
		id:=command.entity_id;if id=="" do id=level_next_id("foundation",doc.revision);points:=make([dynamic]Vec2,0,command.point_count);for i in 0..<command.point_count do append(&points,level_snap_point(doc,command.points[i],true));kind:=Level_Foundation_Kind(clamp(int(command.c.x),0,int(Level_Foundation_Kind.Basement)));story:=-1;if kind==.Basement {story=level_basement_story(doc);if story<0 {if len(doc.stories)>=doc.story_limit do return {},false;story=len(doc.stories);append(&doc.stories,Level_Story{id="basement",name="Basement",base_elevation=-max(command.c.y,1.8),wall_height=max(command.c.y,2.4)})}};append(&doc.foundations,Level_Foundation{id=id,kind=kind,story=story,points=points,elevation=command.value,depth=command.c.y});return Level_Command{kind=.Delete_Foundation,entity_id=id},true
	case .Set_Foundation:
		index:=level_foundation_index(doc,command.entity_id);if index<0 do return {},false;foundation:=&doc.foundations[index];old:=Level_Command{kind=.Set_Foundation,entity_id=foundation.id,value=foundation.elevation,c={f32(foundation.kind),foundation.depth}};foundation.elevation=command.value;foundation.depth=command.c.y;if foundation.kind==.Basement&&foundation.story>=0&&foundation.story<len(doc.stories) {doc.stories[foundation.story].base_elevation=-foundation.depth;doc.stories[foundation.story].wall_height=max(foundation.depth,2.4)};return old,true
	case .Move_Foundation_Point:
		index:=level_foundation_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.foundations[index].points) do return {},false;old:=doc.foundations[index].points[point_index];doc.foundations[index].points[point_index]=level_snap_point(doc,command.a,true);return Level_Command{kind=.Move_Foundation_Point,entity_id=command.entity_id,a=old,value=command.value},true
	case .Delete_Foundation:
		index:=level_foundation_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.foundations[index];ordered_remove(&doc.foundations,index);inverse:=Level_Command{kind=.Create_Foundation,entity_id=old.id,value=old.elevation,c={f32(old.kind),old.depth},point_count=min(len(old.points),32)};for point,i in old.points {if i>=len(inverse.points) do break;inverse.points[i]=point};return inverse,true
	case .Create_Room_Polygon:
		exterior:=command.destination=="patio";id:=command.entity_id;if id=="" do id=level_next_id(exterior?"patio":"room",doc.revision);points:=make([dynamic]Vec2,0,command.point_count);for i in 0..<command.point_count do append(&points,level_snap_point(doc,command.points[i],true));append(&doc.rooms,Level_Room{id=id,name=exterior?"New Patio":"New Room",story=doc.active_story,points=points,floor_material=catalog_resolve_id(command.material),wall_material=catalog_resolve_id(command.material),ceiling_style=exterior?"open":"flat",floor_tint={255,255,255,255},wall_tint={255,255,255,255},exterior=exterior});return Level_Command{kind=.Delete_Room,entity_id=id},true
	case .Split_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;first,second:[34]Vec2;first_count,second_count:=0,0;if !level_split_polygon(doc.rooms[index].points[:],level_snap_point(doc,command.a,true),level_snap_point(doc,command.b,true),&first,&first_count,&second,&second_count) do return {},false;original:=doc.rooms[index];keep_first:=math.abs(level_polygon_area(first[:first_count]))>=math.abs(level_polygon_area(second[:second_count]));kept:=keep_first?first[:first_count]:second[:second_count];created:=keep_first?second[:second_count]:first[:first_count];doc.rooms[index].points=make([dynamic]Vec2,0,len(kept));for point in kept do append(&doc.rooms[index].points,point);copy_room:=original;copy_room.id=command.destination;if copy_room.id=="" do copy_room.id=level_next_id("room_split",doc.revision);copy_room.name=fmt.tprintf("%s B",original.name);copy_room.points=make([dynamic]Vec2,0,len(created));for point in created do append(&copy_room.points,point);append(&doc.rooms,copy_room);wall_points:=make([dynamic]Vec2,0,2);append(&wall_points,level_snap_point(doc,command.a,true),level_snap_point(doc,command.b,true));wall_id:=command.material;if wall_id=="" do wall_id=level_next_id("wall",doc.revision);append(&doc.paths,Level_Path{id=wall_id,story=original.story,kind=.Wall,points=wall_points,material="structure",width=HOUSE_WALL_THICKNESS});return Level_Command{kind=.Delete_Room,entity_id=copy_room.id},true
	case .Merge_Rooms:
		first_index,second_index:=level_room_index(doc,command.entity_id),level_room_index(doc,command.destination);if first_index<0||second_index<0||first_index==second_index do return {},false;merged:[64]Vec2;merged_count:=0;shared_start,shared_finish:=Vec2{},Vec2{};if !level_merge_polygons(doc.rooms[first_index].points[:],doc.rooms[second_index].points[:],&merged,&merged_count,&shared_start,&shared_finish) do return {},false;doc.rooms[first_index].points=make([dynamic]Vec2,0,merged_count);for point in merged[:merged_count] do append(&doc.rooms[first_index].points,point);ordered_remove(&doc.rooms,second_index);divider_id:="";for path in doc.paths {if path.story!=doc.rooms[first_index-(second_index<first_index?1:0)].story||path.kind!=.Wall||len(path.points)!=2 do continue;if level_points_near(path.points[0],shared_start)&&level_points_near(path.points[1],shared_finish)||level_points_near(path.points[1],shared_start)&&level_points_near(path.points[0],shared_finish) {divider_id=path.id;break}};if divider_id!="" {i:=0;for i<len(doc.openings) {if doc.openings[i].host_path==divider_id {ordered_remove(&doc.openings,i)}else{i+=1}};path_index:=level_path_index(doc,divider_id);if path_index>=0 do ordered_remove(&doc.paths,path_index)};i:=0;for i<len(doc.roofs) {if doc.roofs[i].room_id==command.destination {ordered_remove(&doc.roofs,i)}else{i+=1}};return {},true
	case .Insert_Room_Vertex:
		index:=level_room_index(doc,command.entity_id);handle:=int(command.value);if index<0||handle<0||handle>=len(doc.rooms[index].points) do return {},false;target:=handle+1;append(&doc.rooms[index].points,Vec2{});for i:=len(doc.rooms[index].points)-1;i>target;i-=1 do doc.rooms[index].points[i]=doc.rooms[index].points[i-1];doc.rooms[index].points[target]=level_snap_point(doc,command.a,true);return Level_Command{kind=.Remove_Room_Vertex,entity_id=command.entity_id,value=f32(target)},true
	case .Remove_Room_Vertex:
		index:=level_room_index(doc,command.entity_id);handle:=int(command.value);if index<0||handle<0||handle>=len(doc.rooms[index].points)||len(doc.rooms[index].points)<=3 do return {},false;old:=doc.rooms[index].points[handle];ordered_remove(&doc.rooms[index].points,handle);previous:=(handle-1+len(doc.rooms[index].points))%len(doc.rooms[index].points);return Level_Command{kind=.Insert_Room_Vertex,entity_id=command.entity_id,a=old,value=f32(previous)},true
	case .Create_Room:
		exterior:=command.destination=="patio";id:=command.entity_id;if id=="" do id=level_next_id(exterior?"patio":"room",doc.revision);a,b:=level_snap_point(doc,command.a),level_snap_point(doc,command.b);points:=make([dynamic]Vec2,0,4);append(&points,Vec2{min(a.x,b.x),min(a.y,b.y)},Vec2{max(a.x,b.x),min(a.y,b.y)},Vec2{max(a.x,b.x),max(a.y,b.y)},Vec2{min(a.x,b.x),max(a.y,b.y)});append(&doc.rooms,Level_Room{id=id,name=exterior?"New Patio":"New Room",story=doc.active_story,points=points,floor_material=catalog_resolve_id(command.material),wall_material=catalog_resolve_id(command.material),ceiling_style=exterior?"open":"flat",floor_tint={255,255,255,255},wall_tint={255,255,255,255},exterior=exterior});return Level_Command{kind=.Delete_Room,entity_id=id},true
	case .Delete_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;room:=doc.rooms[index];if len(room.points)<2 do return {},false;a:=room.points[0];b:=room.points[2];ordered_remove(&doc.rooms,index);return Level_Command{kind=.Create_Room,entity_id=room.id,a=a,b=b,material=room.floor_material,destination=room.exterior?"patio":""},true
	case .Move_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;for &p in doc.rooms[index].points {p.x+=command.a.x;p.y+=command.a.y};return Level_Command{kind=.Move_Room,entity_id=command.entity_id,a={-command.a.x,-command.a.y}},true
	case .Duplicate_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;source:=doc.rooms[index];copy_room:=source;copy_room.id=command.material;if copy_room.id=="" do copy_room.id=level_next_id("room_copy",doc.revision);copy_room.name=fmt.tprintf("%s Copy",source.name);copy_room.points=make([dynamic]Vec2,0,len(source.points));for point in source.points do append(&copy_room.points,level_snap_point(doc,{point.x+command.a.x,point.y+command.a.y},true));append(&doc.rooms,copy_room);return Level_Command{kind=.Delete_Room,entity_id=copy_room.id},true
	case .Rotate_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;center:=level_room_center(&doc.rooms[index]);for &point in doc.rooms[index].points do point=level_snap_point(doc,level_rotated_point(point,center,command.value),true);return Level_Command{kind=.Rotate_Room,entity_id=command.entity_id,value=-command.value},true
	case .Move_Room_Vertex:
		index:=level_room_index(doc,command.entity_id);handle:=int(command.value);if index<0||handle<0||handle>=len(doc.rooms[index].points) do return {},false;old:=doc.rooms[index].points[handle];doc.rooms[index].points[handle]=level_snap_point(doc,command.a,true);return Level_Command{kind=.Move_Room_Vertex,entity_id=command.entity_id,a=old,value=command.value},true
	case .Move_Room_Edge:
		index:=level_room_index(doc,command.entity_id);handle:=int(command.value);if index<0||handle<0||handle>=len(doc.rooms[index].points) do return {},false;next:=(handle+1)%len(doc.rooms[index].points);doc.rooms[index].points[handle].x+=command.a.x;doc.rooms[index].points[handle].y+=command.a.y;doc.rooms[index].points[next].x+=command.a.x;doc.rooms[index].points[next].y+=command.a.y;return Level_Command{kind=.Move_Room_Edge,entity_id=command.entity_id,a={-command.a.x,-command.a.y},value=command.value},true
	case .Set_Platform:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.rooms[index].platform_height;doc.rooms[index].platform_height=command.value;return Level_Command{kind=.Set_Platform,entity_id=command.entity_id,value=old},true
	case .Add_Path:
		kind:=Level_Path_Kind(clamp(int(command.c.x),0,int(Level_Path_Kind.Footpath)));id:=command.entity_id;if id=="" do id=level_next_id(kind==.Road?"road":kind==.Footpath?"footpath":"wall",doc.revision);count:=command.point_count;if count==0 do count=2;points:=make([dynamic]Vec2,0,count);for i in 0..<count {p:=count==2&&command.point_count==0?(i==0?command.a:command.b):command.points[i];append(&points,level_snap_point(doc,p,true))};width:=command.value;if width<=0 do width=kind==.Road?4:kind==.Footpath?1.2:HOUSE_WALL_THICKNESS;append(&doc.paths,Level_Path{id=id,story=doc.active_story,kind=kind,points=points,material=command.material,width=width});return Level_Command{kind=.Delete_Object,entity_id=id,material="path"},true
	case .Set_Path:
		index:=level_path_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.paths[index].width;doc.paths[index].width=command.value;return Level_Command{kind=.Set_Path,entity_id=command.entity_id,value=old},true
	case .Move_Path_Point:
		index:=level_path_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.paths[index].points) do return {},false;old:=doc.paths[index].points[point_index];doc.paths[index].points[point_index]=level_snap_point(doc,command.a,true);return Level_Command{kind=.Move_Path_Point,entity_id=command.entity_id,a=old,value=command.value},true
	case .Delete_Object:
		if command.material=="path" {index:=level_path_index(doc,command.entity_id);if index<0 do return {},false;path:=doc.paths[index];ordered_remove(&doc.paths,index);inverse:=Level_Command{kind=.Add_Path,entity_id=path.id,material=path.material,c={f32(path.kind),0},value=path.width,point_count=min(len(path.points),32)};for p,i in path.points {if i>=len(inverse.points) do break;inverse.points[i]=p};return inverse,true}
		index:=level_object_index(doc,command.entity_id);if index<0 do return {},false;object:=doc.objects[index];for &child in doc.objects do if child.support_id==object.id {child.support_id="";child.elevation=0};ordered_remove(&doc.objects,index);return Level_Command{kind=.Place_Object,entity_id=object.id,a=object.position,c={object.elevation,0},value=object.rotation,material=object.catalog_id,destination=object.support_id},true
	case .Add_Marker:
		kind:=Level_Marker_Kind(clamp(int(command.c.y),0,int(Level_Marker_Kind.Staging)));id:=command.entity_id;if id=="" do id=level_next_id(level_marker_kind_name(kind),doc.revision);story:=doc.active_story;if command.value>=0 do story=int(command.value);append(&doc.markers,Level_Marker{id=id,reference=command.material,destination=command.destination,kind=kind,story=story,position=level_snap_point(doc,command.a,true),radius=command.b.x,facing=command.b.y,camera_height=command.c.x});return Level_Command{kind=.Delete_Marker,entity_id=id},true
	case .Set_Marker:
		index:=level_marker_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.markers[index];new_id:=command.interaction_prompt;if new_id=="" do new_id=old.id;doc.markers[index].id=new_id;doc.markers[index].reference=command.material;doc.markers[index].destination=command.destination;doc.markers[index].kind=Level_Marker_Kind(clamp(int(command.c.y),0,int(Level_Marker_Kind.Staging)));doc.markers[index].position=level_snap_point(doc,command.a,true);doc.markers[index].radius=command.b.x;doc.markers[index].facing=command.b.y;doc.markers[index].camera_height=command.c.x;if new_id!=old.id {for &marker in doc.markers do if marker.kind==.Transition&&marker.destination==old.id do marker.destination=new_id};return Level_Command{kind=.Set_Marker,entity_id=new_id,interaction_prompt=old.id,a=old.position,b={old.radius,old.facing},c={old.camera_height,f32(old.kind)},material=old.reference,destination=old.destination,value=f32(old.story)},true
	case .Delete_Marker:
		index:=level_marker_index(doc,command.entity_id);if index<0 do return {},false;marker:=doc.markers[index];ordered_remove(&doc.markers,index);return Level_Command{kind=.Add_Marker,entity_id=marker.id,a=marker.position,b={marker.radius,marker.facing},c={marker.camera_height,f32(marker.kind)},material=marker.reference,destination=marker.destination,value=f32(marker.story)},true
	case .Place_Object:
		id:=command.entity_id;if id=="" do id=level_next_id("object",doc.revision);append(&doc.objects,Level_Object{id=id,catalog_id=catalog_resolve_id(command.material),support_id=command.destination,story=doc.active_story,position=level_snap_point(doc,command.a,true),elevation=command.c.x,rotation=command.value,tint={255,255,255,255},bark_tint={255,255,255,255},foliage_tint={255,255,255,255}});return {},true
	case .Duplicate_Object:
		index:=level_object_index(doc,command.entity_id);if index<0 do return {},false;source:=doc.objects[index];copy_object:=source;copy_object.id=command.material;if copy_object.id=="" do copy_object.id=level_next_id("object_copy",doc.revision);copy_object.position=level_snap_point(doc,{source.position.x+command.a.x,source.position.y+command.a.y},true);append(&doc.objects,copy_object);return Level_Command{kind=.Delete_Object,entity_id=copy_object.id,material="object"},true
	case .Move_Object:
		index:=level_object_index(doc,command.entity_id);if index<0 do return {},false;old_position:=doc.objects[index].position;new_position:=level_snap_point(doc,command.a,true);delta:=Vec2{new_position.x-old_position.x,new_position.y-old_position.y};doc.objects[index].position=new_position;doc.objects[index].rotation=command.value;support_id,support_height,supported:=level_object_support_at(doc,new_position,doc.objects[index].catalog_id);if supported&&support_id!=command.entity_id {doc.objects[index].support_id=support_id;doc.objects[index].elevation=support_height}else if doc.objects[index].support_id!="" {host_index:=level_object_index(doc,doc.objects[index].support_id);if host_index<0 {doc.objects[index].support_id="";doc.objects[index].elevation=0}else{host_entry,host_ok:=catalog_object_entry(doc.objects[host_index].catalog_id);radius:=host_ok?max(host_entry.footprint,.2):f32(.35);dx,dy:=new_position.x-doc.objects[host_index].position.x,new_position.y-doc.objects[host_index].position.y;if dx*dx+dy*dy>radius*radius {doc.objects[index].support_id="";doc.objects[index].elevation=0}}};for &child in doc.objects do if child.support_id==command.entity_id {child.position.x+=delta.x;child.position.y+=delta.y};return {},true
	case .Set_Object_Elevation:
		index:=level_object_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.objects[index].elevation;delta:=command.value-old;doc.objects[index].elevation=command.value;for &child in doc.objects do if child.support_id==command.entity_id do child.elevation+=delta;return Level_Command{kind=.Set_Object_Elevation,entity_id=command.entity_id,value=old},true
	case .Set_Object_Color:
		index:=level_object_index(doc,command.entity_id);if index<0 do return {},false;if command.destination=="bark" {old:=doc.objects[index].bark_tint;doc.objects[index].bark_tint=command.color;return Level_Command{kind=.Set_Object_Color,entity_id=command.entity_id,destination="bark",color=old},true};old:=doc.objects[index].foliage_tint;doc.objects[index].foliage_tint=command.color;return Level_Command{kind=.Set_Object_Color,entity_id=command.entity_id,destination="foliage",color=old},true
	case .Add_Light:
		id:=command.entity_id;if id=="" do id=level_next_id("light",doc.revision);story:=doc.active_story;if command.value>=0 do story=int(command.value);kind:=Level_Light_Kind(clamp(int(command.c.y),0,int(Level_Light_Kind.Area)));color:=command.color;if color[3]==0 do color={255,236,196,255};cone:=command.points[0].x;if cone<=0 do cone=45;append(&doc.lights,Level_Light{id=id,kind=kind,story=story,position=level_snap_point(doc,command.a,true),elevation=command.c.x,range=command.b.x,intensity=command.b.y,facing=command.points[0].y,cone_angle=cone,color=color});return Level_Command{kind=.Delete_Light,entity_id=id},true
	case .Set_Light:
		index:=level_light_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.lights[index];color:=command.color;if color[3]==0 do color=old.color;doc.lights[index].kind=Level_Light_Kind(clamp(int(command.c.y),0,int(Level_Light_Kind.Area)));doc.lights[index].position=level_snap_point(doc,command.a,true);doc.lights[index].elevation=command.c.x;doc.lights[index].range=command.b.x;doc.lights[index].intensity=command.b.y;doc.lights[index].facing=command.value;doc.lights[index].cone_angle=command.points[0].x;doc.lights[index].color=color;inverse:=Level_Command{kind=.Set_Light,entity_id=old.id,a=old.position,b={old.range,old.intensity},c={old.elevation,f32(old.kind)},value=old.facing,color=old.color};inverse.points[0]={old.cone_angle,0};return inverse,true
	case .Delete_Light:
		index:=level_light_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.lights[index];ordered_remove(&doc.lights,index);inverse:=Level_Command{kind=.Add_Light,entity_id=old.id,a=old.position,b={old.range,old.intensity},c={old.elevation,f32(old.kind)},value=f32(old.story),color=old.color};inverse.points[0]={old.cone_angle,old.facing};return inverse,true
	case .Paint_Floor:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;doc.rooms[index].floor_material=catalog_resolve_id(command.material);return {},true
	case .Paint_Walls:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;doc.rooms[index].wall_material=catalog_resolve_id(command.material);return {},true
	case .Paint_Room:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;if command.material=="__grounds__" {doc.rooms[index].exterior=true}else if command.material=="__interior__" {doc.rooms[index].exterior=false}else{doc.rooms[index].floor_material=catalog_resolve_id(command.material);doc.rooms[index].wall_material=catalog_resolve_id(command.material)};return {},true
	case .Set_Room_Tint:
		index:=level_room_index(doc,command.entity_id);if index<0 do return {},false;if command.destination=="walls" {old:=doc.rooms[index].wall_tint;doc.rooms[index].wall_tint=command.color;return Level_Command{kind=.Set_Room_Tint,entity_id=command.entity_id,destination="walls",color=old},true};old:=doc.rooms[index].floor_tint;doc.rooms[index].floor_tint=command.color;return Level_Command{kind=.Set_Room_Tint,entity_id=command.entity_id,destination="floor",color=old},true
	case .Add_Opening:
		path_index:=level_path_index(doc,command.material);if path_index<0 do return {},false;id:=command.entity_id;if id=="" do id=level_next_id("opening",doc.revision);kind:=Level_Opening_Kind(clamp(int(command.b.x),0,int(Level_Opening_Kind.Gate)));segment:=int(command.value);a,b:=doc.paths[path_index].points[segment],doc.paths[path_index].points[segment+1];length:=f32(math.sqrt(f64((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y))));default_width:=kind==.Window?f32(1.6):kind==.Arch?f32(1.5):kind==.Gate?f32(1.4):f32(1.2);default_height:=kind==.Window?f32(1.4):kind==.Arch?f32(2.2):kind==.Gate?f32(1.5):f32(2.1);width:=command.b.y>0?command.b.y:default_width;height:=command.c.y>0?command.c.y:default_height;sill_height:=command.points[0].x;if kind==.Window&&sill_height<=0 do sill_height=.72;window_style:=Window_Style(clamp(int(command.points[0].y),0,int(Window_Style.Double_Hung)));door_style:=Door_Style(clamp(int(command.points[2].x),0,int(Door_Style.Sliding)));window_flipped:=command.points[1].x>0;window_hinge_right:=command.points[1].y>0;position:=command.c.x;if position<=0 do position=.5;end_clearance:=level_opening_end_clearance(kind);position=clamp(position,(width*.5+end_clearance)/length,1-(width*.5+end_clearance)/length);behavior:=command.interaction;if kind==.Door&&behavior==.None do behavior=.Door;interaction_range:=command.interaction_range;if interaction_range<=0 do interaction_range=1.8;append(&doc.openings,Level_Opening{id=id,host_path=command.material,kind=kind,door_material=door_material_from_name(command.destination),door_style=door_style,window_style=window_style,window_flipped=window_flipped,window_hinge_right=window_hinge_right,interaction=behavior,interaction_prompt=command.interaction_prompt,interaction_range=interaction_range,initially_active=command.initially_active,locked=command.locked,powered=true,segment=segment,position=position,width=width,height=height,sill_height=sill_height});return Level_Command{kind=.Delete_Opening,entity_id=id},true
	case .Set_Opening:
		index:=level_opening_index(doc,command.entity_id);path_index:=level_path_index(doc,command.material);if index<0||path_index<0 do return {},false;old:=doc.openings[index];kind:=Level_Opening_Kind(clamp(int(command.b.x),0,int(Level_Opening_Kind.Gate)));segment:=int(command.value);a,b:=doc.paths[path_index].points[segment],doc.paths[path_index].points[segment+1];length:=f32(math.sqrt(f64((b.x-a.x)*(b.x-a.x)+(b.y-a.y)*(b.y-a.y))));width:=command.b.y;height:=command.c.y;sill_height:=command.points[0].x;if kind==.Window&&sill_height<=0 do sill_height=.72;window_style:=Window_Style(clamp(int(command.points[0].y),0,int(Window_Style.Double_Hung)));door_style:=Door_Style(clamp(int(command.points[2].x),0,int(Door_Style.Sliding)));window_flipped:=command.points[1].x>0;window_hinge_right:=command.points[1].y>0;end_clearance:=level_opening_end_clearance(kind);position:=clamp(command.c.x,(width*.5+end_clearance)/length,1-(width*.5+end_clearance)/length);door_material:=old.door_material;if command.destination!="" do door_material=door_material_from_name(command.destination);doc.openings[index]={id=old.id,host_path=command.material,kind=kind,door_material=door_material,door_style=door_style,window_style=window_style,window_flipped=window_flipped,window_hinge_right=window_hinge_right,interaction=old.interaction,interaction_prompt=old.interaction_prompt,interaction_range=old.interaction_range,initially_active=old.initially_active,locked=old.locked,powered=old.powered,segment=segment,position=position,width=width,height=height,sill_height=sill_height};inverse:=Level_Command{kind=.Set_Opening,entity_id=old.id,material=old.host_path,destination=door_material_name(old.door_material),value=f32(old.segment),b={f32(old.kind),old.width},c={old.position,old.height}};inverse.points[0]={old.sill_height,f32(old.window_style)};inverse.points[1]={old.window_flipped?1:0,old.window_hinge_right?1:0};inverse.points[2].x=f32(old.door_style);return inverse,true
	case .Delete_Opening:
		index:=level_opening_index(doc,command.entity_id);if index<0 do return {},false;opening:=doc.openings[index];ordered_remove(&doc.openings,index);inverse:=Level_Command{kind=.Add_Opening,entity_id=opening.id,material=opening.host_path,destination=door_material_name(opening.door_material),interaction=opening.interaction,interaction_prompt=opening.interaction_prompt,interaction_range=opening.interaction_range,initially_active=opening.initially_active,locked=opening.locked,powered=opening.powered,value=f32(opening.segment),b={f32(opening.kind),opening.width},c={opening.position,opening.height}};inverse.points[0]={opening.sill_height,f32(opening.window_style)};inverse.points[1]={opening.window_flipped?1:0,opening.window_hinge_right?1:0};inverse.points[2].x=f32(opening.door_style);return inverse,true
	case .Set_Interaction:
		opening_index:=level_opening_index(doc,command.entity_id);if opening_index>=0 {old:=doc.openings[opening_index];target:=&doc.openings[opening_index];target.interaction=command.interaction;target.interaction_prompt=command.interaction_prompt;target.condition_id=command.condition_id;target.focused_scene=command.focused_scene;target.effect_id_count=min(command.effect_id_count,len(target.effect_ids));for effect_i in 0..<target.effect_id_count do target.effect_ids[effect_i]=command.effect_ids[effect_i];target.interaction_range=command.interaction_range;target.initially_active=command.initially_active;target.locked=command.locked;target.powered=command.powered;inverse:=Level_Command{kind=.Set_Interaction,entity_id=old.id,interaction=old.interaction,interaction_prompt=old.interaction_prompt,condition_id=old.condition_id,focused_scene=old.focused_scene,effect_id_count=old.effect_id_count,interaction_range=old.interaction_range,initially_active=old.initially_active,locked=old.locked,powered=old.powered};copy(inverse.effect_ids[:old.effect_id_count],old.effect_ids[:old.effect_id_count]);return inverse,true};object_index:=level_object_index(doc,command.entity_id);if object_index>=0 {old:=doc.objects[object_index];target:=&doc.objects[object_index];target.interaction=command.interaction;target.interaction_prompt=command.interaction_prompt;target.condition_id=command.condition_id;target.focused_scene=command.focused_scene;target.effect_id_count=min(command.effect_id_count,len(target.effect_ids));for effect_i in 0..<target.effect_id_count do target.effect_ids[effect_i]=command.effect_ids[effect_i];target.interaction_range=command.interaction_range;target.initially_active=command.initially_active;target.locked=command.locked;target.powered=command.powered;inverse:=Level_Command{kind=.Set_Interaction,entity_id=old.id,interaction=old.interaction,interaction_prompt=old.interaction_prompt,condition_id=old.condition_id,focused_scene=old.focused_scene,effect_id_count=old.effect_id_count,interaction_range=old.interaction_range,initially_active=old.initially_active,locked=old.locked,powered=old.powered};copy(inverse.effect_ids[:old.effect_id_count],old.effect_ids[:old.effect_id_count]);return inverse,true};return {},false
	case .Create_Roof:
		id:=command.entity_id;if id=="" do id=level_next_id("roof",doc.revision);room_index:=level_room_index(doc,command.material);if room_index<0 do return {},false;append(&doc.roofs,Level_Roof{id=id,room_id=command.material,story=doc.rooms[room_index].story,style=Level_Roof_Style(clamp(int(command.a.x),0,int(Level_Roof_Style.Parapet))),pitch=command.value,overhang=command.b.x,ridge_angle=command.a.y,gutters=command.b.y>0});return Level_Command{kind=.Delete_Roof,entity_id=id},true
	case .Set_Roof:
		index:=level_roof_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.roofs[index];doc.roofs[index].room_id=command.material;doc.roofs[index].style=Level_Roof_Style(clamp(int(command.a.x),0,int(Level_Roof_Style.Parapet)));doc.roofs[index].pitch=command.value;doc.roofs[index].overhang=command.b.x;doc.roofs[index].ridge_angle=command.a.y;doc.roofs[index].gutters=command.b.y>0;return Level_Command{kind=.Set_Roof,entity_id=old.id,material=old.room_id,a={f32(old.style),old.ridge_angle},b={old.overhang,old.gutters?1:0},value=old.pitch},true
	case .Delete_Roof:
		index:=level_roof_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.roofs[index];ordered_remove(&doc.roofs,index);return Level_Command{kind=.Create_Roof,entity_id=old.id,material=old.room_id,a={f32(old.style),old.ridge_angle},b={old.overhang,old.gutters?1:0},value=old.pitch},true
	case .Create_Vertical_Link:
		id:=command.entity_id;if id=="" do id=level_next_id("stairs",doc.revision);kind:=Level_Vertical_Link_Kind(clamp(int(command.c.x),0,int(Level_Vertical_Link_Kind.Elevator)));to_story:=level_story_above(doc,doc.active_story);if to_story<0 do return {},false;append(&doc.vertical_links,Level_Vertical_Link{id=id,kind=kind,from_story=doc.active_story,to_story=to_story,start=level_snap_point(doc,command.a,true),finish=level_snap_point(doc,command.b,true),width=command.value});return Level_Command{kind=.Delete_Vertical_Link,entity_id=id},true
	case .Set_Vertical_Link:
		index:=level_vertical_link_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.vertical_links[index].width;doc.vertical_links[index].width=command.value;return Level_Command{kind=.Set_Vertical_Link,entity_id=command.entity_id,value=old},true
	case .Move_Vertical_Link_Point:
		index:=level_vertical_link_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>1 do return {},false;old:=point_index==0?doc.vertical_links[index].start:doc.vertical_links[index].finish;if point_index==0 do doc.vertical_links[index].start=level_snap_point(doc,command.a,true);else do doc.vertical_links[index].finish=level_snap_point(doc,command.a,true);return Level_Command{kind=.Move_Vertical_Link_Point,entity_id=command.entity_id,a=old,value=command.value},true
	case .Delete_Vertical_Link:
		index:=level_vertical_link_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.vertical_links[index];ordered_remove(&doc.vertical_links,index);return Level_Command{kind=.Create_Vertical_Link,entity_id=old.id,a=old.start,b=old.finish,c={f32(old.kind),0},value=old.width},true
	case .Create_Water:
		id:=command.entity_id;if id=="" do id=level_next_id("water",doc.revision);points:=make([dynamic]Vec2,0,command.point_count);for i in 0..<command.point_count do append(&points,level_snap_point(doc,command.points[i],true));append(&doc.waters,Level_Water{id=id,points=points,elevation=command.value});return Level_Command{kind=.Delete_Water,entity_id=id},true
	case .Set_Water:
		index:=level_water_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.waters[index].elevation;doc.waters[index].elevation=command.value;return Level_Command{kind=.Set_Water,entity_id=command.entity_id,value=old},true
	case .Move_Water_Point:
		index:=level_water_index(doc,command.entity_id);point_index:=int(command.value);if index<0||point_index<0||point_index>=len(doc.waters[index].points) do return {},false;old:=doc.waters[index].points[point_index];doc.waters[index].points[point_index]=level_snap_point(doc,command.a,true);return Level_Command{kind=.Move_Water_Point,entity_id=command.entity_id,a=old,value=command.value},true
	case .Delete_Water:
		index:=level_water_index(doc,command.entity_id);if index<0 do return {},false;old:=doc.waters[index];ordered_remove(&doc.waters,index);inverse:=Level_Command{kind=.Create_Water,entity_id=old.id,value=old.elevation,point_count=min(len(old.points),32)};for p,i in old.points {if i>=len(inverse.points) do break;inverse.points[i]=p};return inverse,true
	case .Sculpt_Terrain:
		radius:=max(command.value,.25);strength:=command.c.x;if strength<=0 do strength=.25;source:=make([]f32,len(doc.terrain),context.temp_allocator);copy(source,doc.terrain[:]);start_height,end_height:=level_terrain_height(doc,command.a),level_terrain_height(doc,command.b)
		for y in 0..=doc.height {for x in 0..=doc.width {index:=y*(doc.width+1)+x;distance,t:=level_segment_distance({f32(x),f32(y)},command.a,command.b);if distance>radius do continue;falloff:=1-distance/radius;falloff*=falloff;current:=source[index];next:=current
			switch command.brush {case .Raise:next=current+strength*falloff;case .Lower:next=current-strength*falloff;case .Flatten:next=current+(command.c.y-current)*clamp(strength*falloff,0,1);case .Slope:target:=start_height+(end_height-start_height)*t;next=current+(target-current)*clamp(strength*falloff,0,1);case .Smooth:sum:=f32(0);count:=0;for oy:=-1;oy<=1;oy+=1 {for ox:=-1;ox<=1;ox+=1 {nx,ny:=x+ox,y+oy;if nx<0||ny<0||nx>doc.width||ny>doc.height do continue;sum+=source[ny*(doc.width+1)+nx];count+=1}};if count>0 {average:=sum/f32(count);next=current+(average-current)*clamp(strength*falloff,0,1)}}
			doc.terrain[index]=f32(math.round(f64(next/.25)))*.25
		}};return {},true
	case: return {},false
	}
}

level_point_in_polygon :: proc(point:Vec2,points:[]Vec2)->bool {if len(points)<3 do return false;inside:=false;j:=len(points)-1;for i in 0..<len(points) {a,b:=points[i],points[j];if (a.y>point.y)!=(b.y>point.y)&&point.x<(b.x-a.x)*(point.y-a.y)/(b.y-a.y)+a.x do inside=!inside;j=i};return inside}
level_pick_room_handle :: proc(doc:^Level_Document,point:Vec2,current:Editor_Selection)->(Editor_Selection,bool) {
	if current.kind!=.Room&&current.kind!=.Vertex&&current.kind!=.Edge do return {},false
	index:=level_room_index(doc,current.entity_id);if index<0 do return {},false;room:=doc.rooms[index]
	for vertex,i in room.points {dx,dy:=point.x-vertex.x,point.y-vertex.y;if dx*dx+dy*dy<=.32*.32 do return {.Vertex,room.id,i},true}
	for i in 0..<len(room.points) {a,b:=room.points[i],room.points[(i+1)%len(room.points)];if point_segment_distance_sq(point.x,point.y,a,b)<=.16*.16 do return {.Edge,room.id,i},true}
	return {},false
}
level_pick :: proc(doc:^Level_Document,point:Vec2)->Editor_Selection {for marker in doc.markers do if marker.story==doc.active_story&&(marker.position.x-point.x)*(marker.position.x-point.x)+(marker.position.y-point.y)*(marker.position.y-point.y)<=max(marker.radius,.3)*max(marker.radius,.3) do return {.Marker,marker.id,-1};for light in doc.lights do if light.story==doc.active_story&&(light.position.x-point.x)*(light.position.x-point.x)+(light.position.y-point.y)*(light.position.y-point.y)<=.45*.45 do return {.Light,light.id,-1};for object in doc.objects do if object.story==doc.active_story&&(object.position.x-point.x)*(object.position.x-point.x)+(object.position.y-point.y)*(object.position.y-point.y)<=.5*.5 do return {.Object,object.id,-1};for opening in doc.openings {path_index:=level_path_index(doc,opening.host_path);if path_index>=0 {path:=doc.paths[path_index];if path.story==doc.active_story&&opening.segment>=0&&opening.segment<len(path.points)-1 {a,b:=path.points[opening.segment],path.points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length>.001 {half:=opening.width*.5/length;start:=Vec2{a.x+dx*(opening.position-half),a.y+dy*(opening.position-half)};finish:=Vec2{a.x+dx*(opening.position+half),a.y+dy*(opening.position+half)};if point_segment_distance_sq(point.x,point.y,start,finish)<.3*.3 do return {.Opening,opening.id,opening.segment}}}}};for path in doc.paths {if path.story!=doc.active_story do continue;for i in 0..<len(path.points)-1 do if point_segment_distance_sq(point.x,point.y,path.points[i],path.points[i+1])<.25*.25 do return {.Path,path.id,i}};if doc.active_story==0 do for water in doc.waters do if level_point_in_polygon(point,water.points[:]) do return {.Water,water.id,-1};for room in doc.rooms do if room.story==doc.active_story&&level_point_in_polygon(point,room.points[:]) do return {.Room,room.id,-1};if doc.active_story==0 do for foundation in doc.foundations do if level_foundation_contains_point(foundation,point) do return {.Foundation,foundation.id,-1};return {.Terrain,"",-1}}
level_pick_path_segment :: proc(doc:^Level_Document,point:Vec2,max_distance:f32=.8)->(Editor_Selection,bool) {best:=max_distance*max_distance;result:=Editor_Selection{};found:=false;for path in doc.paths {if path.story!=doc.active_story do continue;for i in 0..<len(path.points)-1 {distance:=point_segment_distance_sq(point.x,point.y,path.points[i],path.points[i+1]);if distance<best {best=distance;result={.Path,path.id,i};found=true}}};return result,found}
editor_control_point_index :: proc(selection:Editor_Selection)->int {return selection.sub_index<=-2?-selection.sub_index-2:-1}
level_pick_control_point :: proc(doc:^Level_Document,point:Vec2,selected:Editor_Selection)->(Editor_Selection,bool) {best:=f32(.45*.45);result:=Editor_Selection{};found:=false;if selected.kind==.Path {index:=level_path_index(doc,selected.entity_id);if index>=0 {for p,i in doc.paths[index].points {dx,dy:=p.x-point.x,p.y-point.y;distance:=dx*dx+dy*dy;if distance<=best {best=distance;result={.Path,selected.entity_id,-i-2};found=true}}}}else if selected.kind==.Water {index:=level_water_index(doc,selected.entity_id);if index>=0 {for p,i in doc.waters[index].points {dx,dy:=p.x-point.x,p.y-point.y;distance:=dx*dx+dy*dy;if distance<=best {best=distance;result={.Water,selected.entity_id,-i-2};found=true}}}}else if selected.kind==.Foundation {index:=level_foundation_index(doc,selected.entity_id);if index>=0 {for p,i in doc.foundations[index].points {dx,dy:=p.x-point.x,p.y-point.y;distance:=dx*dx+dy*dy;if distance<=best {best=distance;result={.Foundation,selected.entity_id,-i-2};found=true}}}}else if selected.kind==.Vertical_Link {index:=level_vertical_link_index(doc,selected.entity_id);if index>=0 {points:=[2]Vec2{doc.vertical_links[index].start,doc.vertical_links[index].finish};for p,i in points {dx,dy:=p.x-point.x,p.y-point.y;distance:=dx*dx+dy*dy;if distance<=best {best=distance;result={.Vertical_Link,selected.entity_id,-i-2};found=true}}}};return result,found}
level_opening_command_at :: proc(doc:^Level_Document,host:Editor_Selection,point:Vec2,kind:Level_Opening_Kind,width:f32=0,height:f32=0,sill_height:f32=0,window_style:Window_Style=.Fixed)->(Level_Command,bool) {if host.kind!=.Path do return {},false;path_index:=level_path_index(doc,host.entity_id);if path_index<0||host.sub_index<0||host.sub_index>=len(doc.paths[path_index].points)-1 do return {},false;a,b:=doc.paths[path_index].points[host.sub_index],doc.paths[path_index].points[host.sub_index+1];dx,dy:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dy*dy;if length_sq<=.0001 do return {},false;t:=clamp(((point.x-a.x)*dx+(point.y-a.y)*dy)/length_sq,0,1);default_width:=kind==.Window?f32(1.6):kind==.Arch?f32(1.5):kind==.Gate?f32(1.4):f32(1.2);default_height:=kind==.Window?f32(1.4):kind==.Arch?f32(2.2):kind==.Gate?f32(1.5):f32(2.1);opening_width:=width;opening_height:=height;opening_sill:=sill_height;if opening_width<=0 do opening_width=default_width;if opening_height<=0 do opening_height=default_height;if kind==.Window&&opening_sill<=0 do opening_sill=.72;length:=f32(math.sqrt(f64(length_sq)));end_clearance:=level_opening_end_clearance(kind);t=clamp(t,(opening_width*.5+end_clearance)/length,1-(opening_width*.5+end_clearance)/length);command:=Level_Command{kind=.Add_Opening,material=host.entity_id,value=f32(host.sub_index),b={f32(kind),opening_width},c={t,opening_height}};command.points[0]={opening_sill,f32(window_style)};return command,true}
level_opening_edit_command :: proc(opening:Level_Opening)->Level_Command {command:=Level_Command{kind=.Set_Opening,entity_id=opening.id,material=opening.host_path,destination=door_material_name(opening.door_material),value=f32(opening.segment),b={f32(opening.kind),opening.width},c={opening.position,opening.height}};command.points[0]={opening.sill_height,f32(opening.window_style)};command.points[1]={opening.window_flipped?1:0,opening.window_hinge_right?1:0};command.points[2].x=f32(opening.door_style);return command}
level_opening_resize_command :: proc(doc:^Level_Document,id:string,width_delta,height_delta:f32)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0 do return {},false;opening:=doc.openings[index];command:=level_opening_edit_command(opening);command.b.y=clamp(opening.width+width_delta,.4,6);command.c.y=clamp(opening.height+height_delta,.4,4);return command,true}
level_door_style_command :: proc(doc:^Level_Document,id:string,style:Door_Style)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0||doc.openings[index].kind!=.Door do return {},false;command:=level_opening_edit_command(doc.openings[index]);command.points[2].x=f32(style);return command,true}
level_window_sill_command :: proc(doc:^Level_Document,id:string,delta:f32)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0||doc.openings[index].kind!=.Window do return {},false;opening:=doc.openings[index];command:=level_opening_edit_command(opening);command.points[0].x=clamp(opening.sill_height+delta,.2,2);return command,true}
level_window_style_command :: proc(doc:^Level_Document,id:string,style:Window_Style)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0||doc.openings[index].kind!=.Window do return {},false;command:=level_opening_edit_command(doc.openings[index]);command.points[0].y=f32(style);return command,true}
level_window_flip_command :: proc(doc:^Level_Document,id:string)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0||doc.openings[index].kind!=.Window do return {},false;opening:=doc.openings[index];command:=level_opening_edit_command(opening);command.points[1].x=opening.window_flipped?0:1;return command,true}
level_window_handing_command :: proc(doc:^Level_Document,id:string)->(Level_Command,bool) {index:=level_opening_index(doc,id);if index<0||doc.openings[index].kind!=.Window||doc.openings[index].window_style!=.Casement do return {},false;opening:=doc.openings[index];command:=level_opening_edit_command(opening);command.points[1].y=opening.window_hinge_right?0:1;return command,true}

catalog_refresh_preview_state :: proc(entry:^Catalog_Entry) {
	if entry==nil||entry.kind!=.Object do return
	entry.thumbnail_missing=!os.exists(entry.thumbnail)
	entry.thumbnail_stale=false
	if entry.thumbnail_missing||!entry.valid||entry.image!="" do return
	model_info,model_error:=os.stat(entry.model,context.temp_allocator)
	thumbnail_info,thumbnail_error:=os.stat(entry.thumbnail,context.temp_allocator)
	if model_error==nil&&thumbnail_error==nil do entry.thumbnail_stale=time.to_unix_nanoseconds(model_info.modification_time)>time.to_unix_nanoseconds(thumbnail_info.modification_time)
}

painting_catalog_id :: proc(name:string,index:int)->string {
	stem,_:=os.split_filename(name);builder:strings.Builder;strings.builder_init(&builder,context.allocator);_=strings.write_string(&builder,"painting_")
	for value in stem {ch:=value;if ch>='A'&&ch<='Z' do ch=ch-'A'+'a';if (ch>='a'&&ch<='z')||(ch>='0'&&ch<='9') {_=strings.write_byte(&builder,u8(ch))} else if builder.buf[len(builder.buf)-1]!='_' do _=strings.write_byte(&builder,'_')}
	result:=strings.to_string(builder);if result=="painting_" do result=fmt.tprintf("painting_%d",index+1);return fmt.tprintf("personal:%s",result)
}

catalog_personal_id :: proc(prefix,name:string,index:int)->string {
	stem,_:=os.split_filename(name);builder:strings.Builder;strings.builder_init(&builder,context.allocator);_=strings.write_string(&builder,prefix);_=strings.write_byte(&builder,'_')
	for value in stem {ch:=value;if ch>='A'&&ch<='Z' do ch=ch-'A'+'a';if (ch>='a'&&ch<='z')||(ch>='0'&&ch<='9') {_=strings.write_byte(&builder,u8(ch))} else if builder.buf[len(builder.buf)-1]!='_' do _=strings.write_byte(&builder,'_')}
	result:=strings.to_string(builder);if len(result)==len(prefix)+1&&strings.has_prefix(result,prefix)&&result[len(result)-1]=='_' do result=fmt.tprintf("%s_%d",prefix,index+1);return fmt.tprintf("personal:%s",result)
}

catalog_discover_coverings :: proc(out:^Editor_Catalog,folder_name,prefix:string,floor:bool)->int {
	if out==nil||!out.loaded do return 0
	pictures,pictures_error:=os.user_pictures_dir(context.temp_allocator);if pictures_error!=nil do return 0
	folder,join_error:=os.join_path({pictures,"MysteryGame",folder_name},context.temp_allocator);if join_error!=nil||!os.is_dir(folder) do return 0
	files,read_error:=os.read_directory_by_path(folder,-1,context.temp_allocator);if read_error!=nil do return 0
	for i in 0..<len(files) {best:=i;for j in i+1..<len(files) do if strings.to_lower(files[j].name)<strings.to_lower(files[best].name) do best=j;if best!=i do files[i],files[best]=files[best],files[i]}
	count:=0
	for file in files {
		if file.type==.Directory||strings.has_prefix(strings.to_upper(file.name),"_TEMPLATE") do continue
		ext:=strings.to_lower(os.ext(file.name));if ext!=".png"&&ext!=".jpg"&&ext!=".jpeg" do continue
		path,path_error:=os.join_path({folder,file.name},context.allocator);if path_error!=nil do continue
		id:=catalog_personal_id(prefix,file.name,count);duplicate:=false;for existing in out.entries do if existing.id==id do duplicate=true;if duplicate do id=fmt.tprintf("%s_%d",id,count+1)
		entry:=Catalog_Entry{id=id,category=floor?"floor coverings":"wall coverings",kind=.Material,thumbnail_index=-1,catalog_index=len(out.entries),mesh_index=-1,valid=true};if floor do entry.floor=path;else do entry.wall=path;append(&out.entries,entry);count+=1
	}
	return count
}

catalog_discover_paintings :: proc(out:^Editor_Catalog)->int {
	if out==nil||!out.loaded do return 0
	pictures,home_error:=os.user_pictures_dir(context.temp_allocator);if home_error!=nil do return 0
	folder,join_error:=os.join_path({pictures,"MysteryGame","Paintings"},context.temp_allocator);if join_error!=nil||!os.is_dir(folder) do return 0
	files,read_error:=os.read_directory_by_path(folder,-1,context.temp_allocator);if read_error!=nil do return 0
	for i in 0..<len(files) {best:=i;for j in i+1..<len(files) do if strings.to_lower(files[j].name)<strings.to_lower(files[best].name) do best=j;if best!=i do files[i],files[best]=files[best],files[i]}
	count:=0
	for file in files {
		if file.type==.Directory do continue
		ext:=strings.to_lower(os.ext(file.name));if ext!=".png"&&ext!=".jpg"&&ext!=".jpeg" do continue
		path,path_error:=os.join_path({folder,file.name},context.allocator);if path_error!=nil do continue
		id:=painting_catalog_id(file.name,count);duplicate:=false;for entry in out.entries do if entry.id==id do duplicate=true;if duplicate do id=fmt.tprintf("%s_%d",id,count+1)
		entry:=Catalog_Entry{id=id,category="paintings",thumbnail=path,image=path,placement="indoor",front_direction="+z",dimensions={.36,.48,.03},clearance_front=.15,surfaces=[]string{"wall"},styles=[]string{"custom"},affordances=[]string{"display","wall_decoration"},kind=.Object,footprint=.18,default_elevation=1.2,thumbnail_index=0,catalog_index=len(out.entries),mesh_index=-1,valid=true}
		object_count:=0;for existing in out.entries do if existing.kind==.Object do object_count+=1;entry.thumbnail_index=object_count;catalog_refresh_preview_state(&entry);append(&out.entries,entry);count+=1
	}
	return count
}

catalog_model_unit_scale :: proc(model:string)->f32 {return strings.contains(model,"assets/kenney_furniture-kit/")?2:1}

catalog_load_file :: proc(path:string,out:^Editor_Catalog)->Validation {cpath,err:=strings.clone_to_cstring(path,context.temp_allocator);if err!=nil do return {false,"invalid catalog path"};parsed:=toml_parse_file_ex(cpath);defer toml_free(parsed);if !parsed.ok do return toml_parse_diagnostic(path,"editor catalog",&parsed);out.entries=make([dynamic]Catalog_Entry,0,64);object_index:=0;for t in toml_tables(parsed.toptab,"objects") {id:=toml_case_string(t,"id");thumbnail:=toml_case_string(t,"thumbnail");if thumbnail=="" do thumbnail=fmt.tprintf("assets/ui/catalog/%s.png",catalog_local_id(id));emits_light:=toml_case_bool(t,"emits_light");dimensions:=level_toml_floats(t,"dimensions");entry:=Catalog_Entry{id=id,category=toml_case_string(t,"category"),model=toml_case_string(t,"model"),thumbnail=thumbnail,placement=toml_case_string(t,"placement"),front_direction=toml_case_string(t,"front_direction"),clearance_front=level_toml_float(t,"clearance_front"),clearance_back=level_toml_float(t,"clearance_back"),clearance_left=level_toml_float(t,"clearance_left"),clearance_right=level_toml_float(t,"clearance_right"),surfaces=toml_case_strings(t,"surfaces"),styles=toml_case_strings(t,"styles"),affordances=toml_case_strings(t,"affordances"),kind=.Object,footprint=level_toml_float(t,"footprint_radius"),surface_height=level_toml_float(t,"surface_height"),default_elevation=level_toml_float(t,"default_elevation"),emits_light=emits_light,light_kind=level_light_kind(toml_case_string(t,"light_kind")),light_height=level_toml_float(t,"light_height"),light_range=level_toml_float(t,"light_range"),light_intensity=level_toml_float(t,"light_intensity"),light_facing=level_toml_float(t,"light_facing"),light_cone_angle=level_toml_float(t,"light_cone_angle"),light_color=level_toml_color(t,"light_color"),thumbnail_index=object_index,catalog_index=len(out.entries),mesh_index=-1};if len(dimensions)==3 {unit_scale:=catalog_model_unit_scale(entry.model);entry.dimensions={dimensions[0]*unit_scale,dimensions[1]*unit_scale,dimensions[2]*unit_scale}};if entry.emits_light {if entry.light_range<=0 do entry.light_range=4;if entry.light_intensity<=0 do entry.light_intensity=1;if entry.light_cone_angle<=0 do entry.light_cone_angle=45};entry.valid=entry.id!=""&&entry.model!=""&&os.exists(entry.model);catalog_refresh_preview_state(&entry);append(&out.entries,entry);object_index+=1};for t in toml_tables(parsed.toptab,"materials") {floor:=toml_case_string(t,"floor");wall:=toml_case_string(t,"wall");floor_repeat:=level_toml_float(t,"floor_repeat_m");wall_repeat:=level_toml_float(t,"wall_repeat_m");if floor_repeat<=0 do floor_repeat=5;if wall_repeat<=0 do wall_repeat=2;entry:=Catalog_Entry{id=toml_case_string(t,"id"),category=toml_case_string(t,"category"),floor=floor,wall=wall,floor_repeat_m=floor_repeat,wall_repeat_m=wall_repeat,kind=.Material,thumbnail_index=-1,catalog_index=len(out.entries),mesh_index=-1,valid=(floor!=""&&os.exists(floor))||(wall!=""&&os.exists(wall))};append(&out.entries,entry)};out.loaded=true;return {true,"CATALOG READY"}}

catalog_load :: proc(path:string,out:^Editor_Catalog)->Validation {loaded:=catalog_load_file(path,out);if !loaded.ok do return loaded;for &entry in out.entries {if !catalog_qualified_id(entry.id) do return {false,"catalog IDs must be namespace-qualified"};for &other in out.entries do if &entry!=&other&&entry.id==other.id do return {false,"catalog contains a duplicate qualified ID"};separator:=strings.index(entry.id,":");entry.source_namespace=entry.id[:separator];entry.source_version="1"};return loaded}

catalog_asset_overrides_path :: proc(project_root:string)->string {return fmt.tprintf("%s/assets/project-catalog-assets.toml",strings.trim_right(project_root,"/"))}
catalog_asset_overrides_serialize :: proc(catalog:^Editor_Catalog)->string {text:="version = \"1\"\n";if catalog==nil do return text;for entry in catalog.entries {if entry.model_asset_ref==""&&entry.material_asset_ref==""&&entry.texture_asset_ref=="" do continue;text=fmt.tprintf("%s\n[[entries]]\nid = \"%s\"\nmodel_asset_ref = \"%s\"\nmaterial_asset_ref = \"%s\"\ntexture_asset_ref = \"%s\"\n",text,level_quote(entry.id),level_quote(entry.model_asset_ref),level_quote(entry.material_asset_ref),level_quote(entry.texture_asset_ref))};return text}
catalog_asset_overrides_save :: proc(project_root:string,catalog:^Editor_Catalog)->Validation {if project_root==""||catalog==nil do return {false,"project catalog asset overrides require a source project"};path:=catalog_asset_overrides_path(project_root);directory:=os.dir(path);if !os.is_dir(directory)&&os.make_directory_all(directory)!=nil do return {false,"could not create project catalog asset directory"};if os.write_entire_file(path,transmute([]u8)catalog_asset_overrides_serialize(catalog))!=nil do return {false,"could not save project catalog asset overrides"};return {true,"PROJECT CATALOG ASSET REFERENCES SAVED"}}
catalog_asset_overrides_load :: proc(project_root:string,catalog:^Editor_Catalog)->Validation {if project_root==""||catalog==nil do return {false,"project catalog asset overrides require a source project"};path:=catalog_asset_overrides_path(project_root);if !os.is_file(path) do return {true,"NO PROJECT CATALOG ASSET OVERRIDES"};cpath,err:=strings.clone_to_cstring(path,context.temp_allocator);if err!=nil do return {false,"invalid project catalog asset override path"};parsed:=toml_parse_file_ex(cpath);defer toml_free(parsed);if !parsed.ok do return toml_parse_diagnostic(path,"project catalog asset overrides",&parsed);for table in toml_tables(parsed.toptab,"entries") {id:=toml_case_string(table,"id");for &entry in catalog.entries do if entry.id==id {entry.model_asset_ref=toml_case_string(table,"model_asset_ref");entry.material_asset_ref=toml_case_string(table,"material_asset_ref");entry.texture_asset_ref=toml_case_string(table,"texture_asset_ref");break}};return {true,"PROJECT CATALOG ASSET REFERENCES LOADED"}}

catalog_qualified_id :: proc(id:string)->bool {separator:=strings.index(id,":");return separator>0&&separator<len(id)-1&&strings.index(id[separator+1:],":")<0}
catalog_local_id :: proc(id:string)->string {separator:=strings.index(id,":");if separator>=0&&separator<len(id)-1 do return id[separator+1:];return id}
catalog_resolve_id :: proc(id:string)->string {if catalog_qualified_id(id) do return id;return fmt.tprintf("core:%s",id)}
catalog_merge :: proc(path:string,out:^Editor_Catalog,namespace,version:string)->Validation {if out==nil||namespace==""||namespace=="core" do return {false,"expansion catalog requires a non-core namespace"};incoming:Editor_Catalog;if loaded:=catalog_load(path,&incoming);!loaded.ok do return loaded;defer delete(incoming.entries);prefix:=fmt.tprintf("%s:",namespace);for &entry in incoming.entries {if !catalog_qualified_id(entry.id)||!strings.has_prefix(entry.id,prefix) do return {false,"expansion catalog contains an ID outside its namespace"};for existing in out.entries do if existing.id==entry.id do return {false,"catalog merge contains a duplicate qualified ID"}};object_index:=0;for existing in out.entries do if existing.kind==.Object do object_index+=1;for entry in incoming.entries {copy:=entry;copy.source_namespace=namespace;copy.source_version=version;copy.catalog_index=len(out.entries);if copy.kind==.Object {copy.thumbnail_index=object_index;object_index+=1};append(&out.entries,copy)};out.loaded=true;return {true,"CATALOG MERGED"}}

catalog_merge_installed :: proc(out:^Editor_Catalog)->Validation {data_dir,data_error:=os.user_data_dir(context.temp_allocator);if data_error!=nil do return {true,"NO EXPANSION CATALOGS"};registry,path_error:=os.join_path([]string{data_dir,APP_STORAGE_NAME,"Expansions","catalog-registry.toml"},context.temp_allocator);if path_error!=nil||!os.is_file(registry) do return {true,"NO EXPANSION CATALOGS"};cpath,clone_error:=strings.clone_to_cstring(registry,context.temp_allocator);if clone_error!=nil do return {false,"invalid expansion catalog registry path"};parsed:=toml_parse_file_ex(cpath);defer toml_free(parsed);if !parsed.ok do return toml_parse_diagnostic(registry,"expansion catalog registry",&parsed);for table in toml_tables(parsed.toptab,"expansions") {namespace:=toml_case_string(table,"namespace");version:=toml_case_string(table,"version");for path in toml_case_strings(table,"catalogs") {merged:=catalog_merge(path,out,namespace,version);if !merged.ok do return merged}};return {true,"EXPANSION CATALOGS MERGED"}}

catalog_is_recent :: proc(state:^Editor_State,id:string)->bool {resolved:=catalog_resolve_id(id);for recent in state.catalog_recent[:state.catalog_recent_count] do if recent==resolved do return true;return false}
catalog_record_recent :: proc(state:^Editor_State,id:string) {if id=="" do return;resolved:=catalog_resolve_id(id);write:=0;next:[8]string;next[write]=resolved;write+=1;for recent in state.catalog_recent[:state.catalog_recent_count] {if recent==resolved do continue;if write>=len(next) do break;next[write]=recent;write+=1};state.catalog_recent=next;state.catalog_recent_count=write}
catalog_is_pinned :: proc(state:^Editor_State,id:string)->bool {resolved:=catalog_resolve_id(id);for pinned in state.catalog_pinned[:state.catalog_pinned_count] do if pinned==resolved do return true;return false}
catalog_toggle_pinned :: proc(state:^Editor_State,id:string)->bool {if id=="" do return false;resolved:=catalog_resolve_id(id);for pinned,i in state.catalog_pinned[:state.catalog_pinned_count] {if pinned!=resolved do continue;for j in i..<state.catalog_pinned_count-1 do state.catalog_pinned[j]=state.catalog_pinned[j+1];state.catalog_pinned_count-=1;state.catalog_pinned[state.catalog_pinned_count]="";return false};if state.catalog_pinned_count<len(state.catalog_pinned) {state.catalog_pinned[state.catalog_pinned_count]=resolved;state.catalog_pinned_count+=1;return true};return false}
catalog_search_text :: proc(state:^Editor_State)->string {return string(state.search_buffer[:state.search_count])}
catalog_clear_search :: proc(state:^Editor_State) {state.search_count=0;state.catalog_page=0;state.search_active=true}
catalog_append_search_char :: proc(state:^Editor_State,ch:u8)->bool {
	if state.search_count>=len(state.search_buffer) do return false
	value:=ch
	if value>='A'&&value<='Z' do value=value-'A'+'a'
	if !((value>='a'&&value<='z')||(value>='0'&&value<='9')||value=='_'||value=='-') do return false
	state.search_buffer[state.search_count]=value
	state.search_count+=1
	state.catalog_page=0
	return true
}
catalog_object_entry :: proc(id:string)->(^Catalog_Entry,bool) {resolved:=catalog_resolve_id(id);for &entry in editor_catalog.entries do if entry.kind==.Object&&entry.id==resolved do return &entry,true;return nil,false}
level_object_support_at :: proc(doc:^Level_Document,point:Vec2,placed_catalog_id:string)->(string,f32,bool) {
	placed,placed_ok:=catalog_object_entry(placed_catalog_id);if !placed_ok do return "",0,false
	best_id:="";best_height:=f32(-1);best_distance:=f32(1e30)
	for object in doc.objects {
		if object.story!=doc.active_story||object.support_id!="" do continue
		host,host_ok:=catalog_object_entry(object.catalog_id);if !host_ok||host.surface_height<=0 do continue
		host_radius:=max(host.footprint,.2);placed_radius:=max(placed.footprint,.2);dx,dy:=point.x-object.position.x,point.y-object.position.y;distance:=dx*dx+dy*dy
		if placed_radius>host_radius*.72||distance>(host_radius-placed_radius*.55)*(host_radius-placed_radius*.55) do continue
		height:=object.elevation+host.surface_height
		if height>best_height+.001||math.abs(height-best_height)<=.001&&distance<best_distance {best_id=object.id;best_height=height;best_distance=distance}
	}
	return best_id,best_height,best_id!=""
}
catalog_entry_kind :: proc(id:string)->(Catalog_Entry_Kind,bool) {for entry in editor_catalog.entries do if entry.id==id do return entry.kind,true;return .Object,false}
catalog_entry_selectable :: proc(entry:Catalog_Entry)->bool {return entry.valid}

editor_select_first_catalog_match :: proc(g:^Game)->bool {
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry,&editor_state)||!catalog_entry_selectable(entry) do continue
		editor_state.catalog_id=entry.id;editor_state.paint_eyedropper=false;editor_state.search_active=false;catalog_record_recent(&editor_state,entry.id)
		if entry.kind==.Object {g.build_tool=.Plant;editor_state.placement_rotation=0}else do g.build_tool=.Paint
		return true
	}
	return false
}
catalog_entry_matches :: proc(entry:Catalog_Entry,state:^Editor_State)->bool {
	category:=state.catalog_category;if category!=""&&category!="all" {if category=="objects"&&entry.kind!=.Object do return false;if category=="materials"&&entry.kind!=.Material do return false;if category=="recent"&&!catalog_is_recent(state,entry.id) do return false;if category=="pinned"&&!catalog_is_pinned(state,entry.id) do return false;if category!="objects"&&category!="materials"&&category!="recent"&&category!="pinned"&&entry.category!=category do return false}
	query:=catalog_search_text(state);if query!=""&&!strings.contains(strings.to_lower(entry.id),query)&&!strings.contains(strings.to_lower(entry.category),query) do return false
	return true
}
catalog_match_count :: proc(state:^Editor_State)->int {count:=0;for entry in editor_catalog.entries do if catalog_entry_matches(entry,state) do count+=1;return count}
catalog_page_count :: proc(state:^Editor_State,page_size:=9)->int {return max(1,(catalog_match_count(state)+page_size-1)/page_size)}
catalog_clamp_page :: proc(state:^Editor_State,page_size:=9) {state.catalog_page=clamp(state.catalog_page,0,catalog_page_count(state,page_size)-1)}

level_commit :: proc(doc:^Level_Document,command:Level_Command,label:string)->bool {
	before:=level_clone_document(doc);_,ok:=level_apply_raw(doc,command);if !ok do return false
	if level_history.undo_count>=LEVEL_HISTORY_CAPACITY {for i in 1..<LEVEL_HISTORY_CAPACITY do level_history.undo[i-1]=level_history.undo[i];level_history.undo_count-=1}
	doc.revision+=1;doc.dirty=true;_=level_validate(doc);_=authoring_invalidate_after_edit(.Level,doc.revision);after:=level_clone_document(doc);level_history.undo[level_history.undo_count]=Level_Change_Set{before,after,label};level_history.undo_count+=1;level_history.redo_count=0;editor_state.dirty={terrain=command.kind==.Sculpt_Terrain,architecture=true,navigation=true,lighting=true,ui=true,min={min(command.a.x,command.b.x),min(command.a.y,command.b.y)},max={max(command.a.x,command.b.x),max(command.a.y,command.b.y)}};if command.kind==.Sculpt_Terrain {editor_state.dirty.min.x-=command.value;editor_state.dirty.min.y-=command.value;editor_state.dirty.max.x+=command.value;editor_state.dirty.max.y+=command.value};if level_transaction_projection_enabled do level_project_to_runtime(doc);_=level_autosave(doc);return true
}
level_undo :: proc(doc:^Level_Document)->bool {if level_history.undo_count<=0 do return false;level_history.undo_count-=1;change:=level_history.undo[level_history.undo_count];doc^=level_clone_document(&change.before);doc.dirty=true;level_history.redo[level_history.redo_count]=change;level_history.redo_count+=1;editor_state.dirty={terrain=true,architecture=true,navigation=true,lighting=true,ui=true,min={},max={f32(doc.width),f32(doc.height)}};if level_transaction_projection_enabled do level_project_to_runtime(doc);return true}
level_redo :: proc(doc:^Level_Document)->bool {if level_history.redo_count<=0 do return false;level_history.redo_count-=1;change:=level_history.redo[level_history.redo_count];doc^=level_clone_document(&change.after);doc.dirty=true;level_history.undo[level_history.undo_count]=change;level_history.undo_count+=1;editor_state.dirty={terrain=true,architecture=true,navigation=true,lighting=true,ui=true,min={},max={f32(doc.width),f32(doc.height)}};if level_transaction_projection_enabled do level_project_to_runtime(doc);return true}

level_preview_transaction :: proc(doc:^Level_Document,command:Level_Command)->Placement_Result {return level_command_preview(doc,command)}
level_commit_transaction :: proc(doc:^Level_Document,command:Level_Command,label:string)->bool {return level_commit(doc,command,label)}

// Stable headless boundary for agent object edits. This intentionally shares
// Build Mode's preview, apply, validation, snapping, catalog, and serializer.
agent_object_transaction :: proc(args:[]string)->int {
	// mode level catalog_manifest id catalog_id x y elevation rotation support story
	if len(args)!=11 {fmt.eprintln("usage: --agent-object-transaction preview|commit LEVEL CATALOG_MANIFEST ID CATALOG_ID X Y ELEVATION ROTATION SUPPORT STORY");return 2}
	mode,level_path,catalog_path,object_id,catalog_id:=args[0],args[1],args[2],args[3],args[4]
	x,x_ok:=strconv.parse_f32(args[5]);y,y_ok:=strconv.parse_f32(args[6]);elevation,elevation_ok:=strconv.parse_f32(args[7]);rotation,rotation_ok:=strconv.parse_f32(args[8]);story64,story_ok:=strconv.parse_i64(args[10])
	if !x_ok||!y_ok||!elevation_ok||!rotation_ok||!story_ok {fmt.eprintln("invalid numeric agent transaction argument");return 2}
	doc:Level_Document;if loaded:=level_load(level_path,&doc);!loaded.ok {fmt.eprintln(loaded.message);return 2}
	catalog:Editor_Catalog;if loaded:=catalog_load(catalog_path,&catalog);!loaded.ok {fmt.eprintln(loaded.message);return 2};editor_catalog=catalog
	if level_object_index(&doc,object_id)>=0 {fmt.eprintln("duplicate object ID: ",object_id);return 2}
	doc.active_story=clamp(int(story64),0,max(len(doc.stories)-1,0))
	command:=Level_Command{kind=.Place_Object,entity_id=object_id,a={x,y},c={elevation,0},value=rotation,material=catalog_id,destination=args[9]}
	result:=level_preview_transaction(&doc,command);state:="valid";if result.state==.Warning do state="warning";else if result.state==.Blocked do state="blocked";snapped:=level_snap_point(&doc,command.a,true)
	fmt.printf("{{\"state\":\"%s\",\"message\":\"%s\",\"position\":[%.3f,%.3f]}}\n",state,level_quote(result.message),snapped.x,snapped.y)
	if result.state==.Blocked do return 2
	if mode=="preview" do return 0
	if mode!="commit" {fmt.eprintln("transaction mode must be preview or commit");return 2}
	_,applied:=level_apply_raw(&doc,command);if !applied {fmt.eprintln("could not apply object transaction");return 2};doc.revision+=1
	if checked:=level_validate(&doc);!checked.ok {fmt.eprintln(checked.message);return 2}
	if saved:=level_save(level_path,&doc);!saved.ok {fmt.eprintln(saved.message);return 2}
	return 0
}

agent_level_validate :: proc(path:string)->int {
	doc:Level_Document;if loaded:=level_load(path,&doc);!loaded.ok {fmt.printf("{{\"valid\":false,\"message\":\"%s\"}}\n",level_quote(loaded.message));return 2}
	checked:=level_validate(&doc);fmt.printf("{{\"valid\":%s,\"message\":\"%s\",\"diagnostic_count\":%d}}\n",checked.ok?"true":"false",level_quote(checked.message),len(doc.diagnostics));return checked.ok?0:2
}
level_commit_transactions :: proc(doc:^Level_Document,commands:[]Level_Command,label:string)->bool {
	if len(commands)==0 do return false;before:=level_clone_document(doc);work:=level_clone_document(doc);for command in commands {if level_preview_transaction(&work,command).state==.Blocked do return false;_,ok:=level_apply_raw(&work,command);if !ok do return false;work.revision+=1};work.dirty=true;_=level_validate(&work);if level_history.undo_count>=LEVEL_HISTORY_CAPACITY {for i in 1..<LEVEL_HISTORY_CAPACITY do level_history.undo[i-1]=level_history.undo[i];level_history.undo_count-=1};after:=level_clone_document(&work);level_history.undo[level_history.undo_count]=Level_Change_Set{before,after,label};level_history.undo_count+=1;level_history.redo_count=0;doc^=work;_=authoring_invalidate_after_edit(.Level,doc.revision);editor_state.dirty={architecture=true,navigation=true,lighting=true,ui=true};if level_transaction_projection_enabled do level_project_to_runtime(doc);_=level_autosave(doc);return true
}

editor_selection_index :: proc(state:^Editor_State,selection:Editor_Selection)->int {for known,i in state.selection[:state.selection_count] do if known.kind==selection.kind&&known.entity_id==selection.entity_id&&known.sub_index==selection.sub_index do return i;return -1}
editor_selection_toggle :: proc(state:^Editor_State,selection:Editor_Selection)->bool {index:=editor_selection_index(state,selection);if index>=0 {for i in index+1..<state.selection_count do state.selection[i-1]=state.selection[i];state.selection_count-=1;return false};if state.selection_count>=len(state.selection) do return false;state.selection[state.selection_count]=selection;state.selection_count+=1;return true}
level_box_append :: proc(out:^[16]Editor_Selection,count:^int,selection:Editor_Selection,point,min_bound,max_bound:Vec2) {if count^>=len(out^)||point.x<min_bound.x||point.x>max_bound.x||point.y<min_bound.y||point.y>max_bound.y do return;out[count^]=selection;count^+=1}
level_select_box :: proc(doc:^Level_Document,a,b:Vec2,out:^[16]Editor_Selection)->int {
	min_bound:=Vec2{min(a.x,b.x),min(a.y,b.y)};max_bound:=Vec2{max(a.x,b.x),max(a.y,b.y)};count:=0
	for marker in doc.markers do if marker.story==doc.active_story do level_box_append(out,&count,{.Marker,marker.id,-1},marker.position,min_bound,max_bound)
	for light in doc.lights do if light.story==doc.active_story do level_box_append(out,&count,{.Light,light.id,-1},light.position,min_bound,max_bound)
	for object in doc.objects do if object.story==doc.active_story do level_box_append(out,&count,{.Object,object.id,-1},object.position,min_bound,max_bound)
	for &room in doc.rooms do if room.story==doc.active_story do level_box_append(out,&count,{.Room,room.id,-1},level_room_center(&room),min_bound,max_bound)
	for path in doc.paths do if path.story==doc.active_story&&len(path.points)>0 {center:=Vec2{};for p in path.points {center.x+=p.x;center.y+=p.y};center.x/=f32(len(path.points));center.y/=f32(len(path.points));level_box_append(out,&count,{.Path,path.id,-1},center,min_bound,max_bound)}
	return count
}

level_nudge_selection :: proc(doc:^Level_Document,selection:Editor_Selection,delta:Vec2)->bool {
	#partial switch selection.kind {
	case .Foundation:return level_commit_transaction(doc,Level_Command{kind=.Delete_Foundation,entity_id=selection.entity_id},"Delete foundation")
	case .Room:return level_commit_transaction(doc,Level_Command{kind=.Move_Room,entity_id=selection.entity_id,a=delta},"Move room")
	case .Object:
		index:=level_object_index(doc,selection.entity_id);if index<0 do return false;object:=doc.objects[index]
		return level_commit_transaction(doc,Level_Command{kind=.Move_Object,entity_id=selection.entity_id,a={object.position.x+delta.x,object.position.y+delta.y},value=object.rotation},"Move object")
	case .Marker:
		index:=level_marker_index(doc,selection.entity_id);if index<0 do return false;command:=marker_edit_command(doc.markers[index]);command.a.x+=delta.x;command.a.y+=delta.y
		return level_commit_transaction(doc,command,"Move marker")
	case .Light:
		index:=level_light_index(doc,selection.entity_id);if index<0 do return false;command:=light_edit_command(doc.lights[index]);command.a.x+=delta.x;command.a.y+=delta.y;return level_commit_transaction(doc,command,"Move light")
	case:return false
	}
}

level_selection_move_command :: proc(doc:^Level_Document,selection:Editor_Selection,delta:Vec2)->(Level_Command,bool) {
	#partial switch selection.kind {
	case .Room:return Level_Command{kind=.Move_Room,entity_id=selection.entity_id,a=delta},true
	case .Foundation:
		point_index:=editor_control_point_index(selection);index:=level_foundation_index(doc,selection.entity_id);if index<0||point_index<0||point_index>=len(doc.foundations[index].points) do return {},false;point:=doc.foundations[index].points[point_index];return Level_Command{kind=.Move_Foundation_Point,entity_id=selection.entity_id,a=level_snap_point(doc,{point.x+delta.x,point.y+delta.y},true),value=f32(point_index)},true
	case .Vertex:
		index:=level_room_index(doc,selection.entity_id);if index<0||selection.sub_index<0||selection.sub_index>=len(doc.rooms[index].points) do return {},false;point:=doc.rooms[index].points[selection.sub_index]
		return Level_Command{kind=.Move_Room_Vertex,entity_id=selection.entity_id,a=level_snap_point(doc,{point.x+delta.x,point.y+delta.y},true),value=f32(selection.sub_index)},true
	case .Edge:return Level_Command{kind=.Move_Room_Edge,entity_id=selection.entity_id,a=delta,value=f32(selection.sub_index)},true
	case .Path:
		point_index:=editor_control_point_index(selection);index:=level_path_index(doc,selection.entity_id);if index<0||point_index<0||point_index>=len(doc.paths[index].points) do return {},false;point:=doc.paths[index].points[point_index];return Level_Command{kind=.Move_Path_Point,entity_id=selection.entity_id,a=level_snap_point(doc,{point.x+delta.x,point.y+delta.y},true),value=f32(point_index)},true
	case .Water:
		point_index:=editor_control_point_index(selection);index:=level_water_index(doc,selection.entity_id);if index<0||point_index<0||point_index>=len(doc.waters[index].points) do return {},false;point:=doc.waters[index].points[point_index];return Level_Command{kind=.Move_Water_Point,entity_id=selection.entity_id,a=level_snap_point(doc,{point.x+delta.x,point.y+delta.y},true),value=f32(point_index)},true
	case .Vertical_Link:
		point_index:=editor_control_point_index(selection);index:=level_vertical_link_index(doc,selection.entity_id);if index<0||point_index<0||point_index>1 do return {},false;point:=point_index==0?doc.vertical_links[index].start:doc.vertical_links[index].finish;return Level_Command{kind=.Move_Vertical_Link_Point,entity_id=selection.entity_id,a=level_snap_point(doc,{point.x+delta.x,point.y+delta.y},true),value=f32(point_index)},true
	case .Object:
		index:=level_object_index(doc,selection.entity_id);if index<0 do return {},false;object:=doc.objects[index]
		return Level_Command{kind=.Move_Object,entity_id=selection.entity_id,a={object.position.x+delta.x,object.position.y+delta.y},value=object.rotation},true
	case .Marker:
		index:=level_marker_index(doc,selection.entity_id);if index<0 do return {},false;command:=marker_edit_command(doc.markers[index]);command.a.x+=delta.x;command.a.y+=delta.y
		return command,true
	case .Light:
		index:=level_light_index(doc,selection.entity_id);if index<0 do return {},false;command:=light_edit_command(doc.lights[index]);command.a.x+=delta.x;command.a.y+=delta.y;return command,true
	case .Opening:
		index:=level_opening_index(doc,selection.entity_id);if index<0 do return {},false;opening:=doc.openings[index];path_index:=level_path_index(doc,opening.host_path);if path_index<0||opening.segment<0||opening.segment>=len(doc.paths[path_index].points)-1 do return {},false;a,b:=doc.paths[path_index].points[opening.segment],doc.paths[path_index].points[opening.segment+1];dx,dy:=b.x-a.x,b.y-a.y;length_sq:=dx*dx+dy*dy;if length_sq<=.0001 do return {},false;center:=Vec2{a.x+dx*opening.position+delta.x,a.y+dy*opening.position+delta.y};position:=((center.x-a.x)*dx+(center.y-a.y)*dy)/length_sq;command:=level_opening_edit_command(opening);command.c.x=position;return command,true
	case:return {},false
	}
}

level_snap_delta :: proc(doc:^Level_Document,delta:Vec2)->Vec2 {if editor_state.snap_mode==.Off||editor_state.snap_suspended do return delta;step:=editor_state.snap_mode==.Fine?doc.fine_snap:doc.default_snap;if step<=0 do return delta;return {f32(math.round(f64(delta.x/step)))*step,f32(math.round(f64(delta.y/step)))*step}}
level_story_below :: proc(doc:^Level_Document,story:int)->int {if story<0||story>=len(doc.stories) do return -1;current:=doc.stories[story].base_elevation;best:=-1;best_elevation:=f32(-1000000);for candidate,i in doc.stories do if candidate.base_elevation<current-.01&&candidate.base_elevation>best_elevation {best=i;best_elevation=candidate.base_elevation};return best}
level_story_above :: proc(doc:^Level_Document,story:int)->int {if story<0||story>=len(doc.stories) do return -1;current:=doc.stories[story].base_elevation;best:=-1;best_elevation:=f32(1000000);for candidate,i in doc.stories do if candidate.base_elevation>current+.01&&candidate.base_elevation<best_elevation {best=i;best_elevation=candidate.base_elevation};return best}
level_can_create_attic :: proc(doc:^Level_Document)->bool {return len(doc.stories)>0&&len(doc.stories)<doc.story_limit&&level_story_above(doc,doc.active_story)<0}
level_create_attic_story :: proc(doc:^Level_Document)->bool {if !level_can_create_attic(doc) do return false;source:=doc.stories[doc.active_story];index:=len(doc.stories);append(&doc.stories,Level_Story{id=fmt.tprintf("attic_%d",index),name="Attic",base_elevation=source.base_elevation+source.wall_height,wall_height=2.4});doc.active_story=index;doc.revision+=1;doc.dirty=true;editor_state.selection_count=0;level_project_to_runtime(doc);_=level_autosave(doc);return true}
level_story_label :: proc(doc:^Level_Document,story:int)->string {if story<0||story>=len(doc.stories) do return "STORY";elevation:=doc.stories[story].base_elevation;if math.abs(elevation)<=.01 do return "GROUND";if elevation<0 {rank:=1;for candidate in doc.stories do if candidate.base_elevation<-.01&&candidate.base_elevation>elevation+.01 do rank+=1;return fmt.tprintf("B%d",rank)};rank:=1;for candidate in doc.stories do if candidate.base_elevation>.01&&candidate.base_elevation<elevation-.01 do rank+=1;return fmt.tprintf("FLOOR %d",rank+1)}
level_set_active_story :: proc(doc:^Level_Document,story:int)->bool {if len(doc.stories)==0||story<0||story>=len(doc.stories) do return false;if story==doc.active_story do return false;doc.active_story=story;editor_state.selection_count=0;editor_state.room_draw_count=0;level_project_to_runtime(doc);return true}

level_delete_selection :: proc(doc:^Level_Document,selection:Editor_Selection)->bool {
	#partial switch selection.kind {
	case .Room:return editor_delete_command(doc,Level_Command{kind=.Delete_Room,entity_id=selection.entity_id},"Delete room","ROOM")
	case .Object:return editor_delete_command(doc,Level_Command{kind=.Delete_Object,entity_id=selection.entity_id,material="object"},"Delete object","OBJECT")
	case .Path:return editor_delete_command(doc,Level_Command{kind=.Delete_Object,entity_id=selection.entity_id,material="path"},"Delete path","PATH")
	case .Opening:return editor_delete_command(doc,Level_Command{kind=.Delete_Opening,entity_id=selection.entity_id},"Delete opening","OPENING")
	case .Roof:return editor_delete_command(doc,Level_Command{kind=.Delete_Roof,entity_id=selection.entity_id},"Delete roof","ROOF")
	case .Vertical_Link:return editor_delete_command(doc,Level_Command{kind=.Delete_Vertical_Link,entity_id=selection.entity_id},"Delete vertical link","VERTICAL LINK")
	case .Water:return editor_delete_command(doc,Level_Command{kind=.Delete_Water,entity_id=selection.entity_id},"Delete pond","POND")
	case .Marker:return editor_delete_command(doc,Level_Command{kind=.Delete_Marker,entity_id=selection.entity_id},"Delete marker","MARKER")
	case .Light:return editor_delete_command(doc,Level_Command{kind=.Delete_Light,entity_id=selection.entity_id},"Delete light","LIGHT")
	case:return false
	}
}
level_rebuild_dirty :: proc(doc:^Level_Document,dirty:Dirty_Regions) {if dirty.architecture||dirty.navigation||dirty.terrain do level_project_to_runtime(doc);editor_state.dirty={}}
level_project_runtime :: proc(doc:^Level_Document) {level_project_to_runtime(doc)}
level_material_surface :: proc(material:string)->Room_Surface {if strings.contains(material,"study") do return .Study;if strings.contains(material,"gallery") do return .Gallery;if strings.contains(material,"pantry") do return .Pantry;if strings.contains(material,"garden") do return .Garden;return .Dining}

level_project_to_runtime :: proc(doc:^Level_Document) {
	house_plan.level=doc.active_story
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
	for y in 0..<HOUSE_SURFACE_HEIGHT {for x in 0..<HOUSE_SURFACE_WIDTH {house_plan.surfaces[y*HOUSE_SURFACE_WIDTH+x]=.Dining;house_plan.space_kinds[y*HOUSE_SURFACE_WIDTH+x]=.Grounds}}
	for room in doc.rooms {if room.story!=doc.active_story||len(room.points)<3 do continue
		surface:=level_material_surface(room.floor_material)
		for y in 0..<HOUSE_SURFACE_HEIGHT {for x in 0..<HOUSE_SURFACE_WIDTH {px,py:=f32(x)+.5,f32(y)+.5;inside:=false;j:=len(room.points)-1;for i in 0..<len(room.points) {a,b:=room.points[i],room.points[j];if (a.y>py)!=(b.y>py)&&px<(b.x-a.x)*(py-a.y)/(b.y-a.y)+a.x do inside=!inside;j=i};if inside {house_plan.surfaces[y*HOUSE_SURFACE_WIDTH+x]=surface;house_plan.space_kinds[y*HOUSE_SURFACE_WIDTH+x]=room.exterior?.Grounds:.Interior}}}
	}
	rebuild_house_wall_splines(doc,doc.active_story)
	clear(&house_plan.wall_face_paints);for spline in house_plan.wall_splines {for i in 0..<len(spline.points)-1 {a,b:=spline.points[i],spline.points[i+1];dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<=.01 do continue;mx,my:=(a.x+b.x)*.5,(a.y+b.y)*.5;nx,ny:= -dy/length,dx/length;for side in 0..<2 {positive:=side==0;sign:=positive?f32(1):f32(-1);sample:=Vec2{mx+nx*.24*sign,my+ny*.24*sign};for room in doc.rooms {if room.story==doc.active_story&&level_point_in_polygon(sample,room.points[:]) {append(&house_plan.wall_face_paints,Wall_Face_Paint{a,b,positive,level_material_surface(room.wall_material)});break}}}}}
	clear(&house_plan.openings);for opening in doc.openings {for path in doc.paths do if path.story==doc.active_story&&path.id==opening.host_path&&opening.segment>=0&&opening.segment<len(path.points)-1 {a,b:=path.points[opening.segment],path.points[opening.segment+1];t:=clamp(opening.position,0,1);dx,dy:=b.x-a.x,b.y-a.y;length:=f32(math.sqrt(f64(dx*dx+dy*dy)));if length<=.01 do continue;half:=opening.width*.5/length;center:=clamp(t,half,1-half);kind:=Opening_Kind.Door;if opening.kind==.Window do kind=.Window;append(&house_plan.openings,Plan_Opening{a={a.x+dx*(center-half),a.y+dy*(center-half)},b={a.x+dx*(center+half),a.y+dy*(center+half)},kind=kind,id=opening.id,height=opening.height,sill_height=opening.sill_height,wall_width=house_wall_width(path.width),door_material=opening.door_material,door_style=opening.door_style,window_style=opening.window_style,window_flipped=opening.window_flipped,window_hinge_right=opening.window_hinge_right})}}
	house_plan.revision=int(doc.revision);house_plan.dirty=true;build_house_floorplan();rebuild_personal_surfaces(doc);rebuild_generated_roofs(doc);build_house_navmesh();rebuild_generated_links(doc);rebuild_generated_ground(doc);rebuild_generated_stories(doc);if len(active_story_project.entities)>0 do _=world_entities_rebuild(&active_story_project,doc)
}

level_editor_initialize :: proc()->Validation {if synced:=level_sync_legacy_source_path();!synced.ok do return synced;validation:=level_load(level_active_source_path,&level_document);if !validation.ok do return validation;catalog_validation:=catalog_load("assets/catalog/editor_catalog.toml",&editor_catalog);if !catalog_validation.ok do return catalog_validation;if merged:=catalog_merge_installed(&editor_catalog);!merged.ok do return merged;_=catalog_discover_paintings(&editor_catalog);_=catalog_discover_coverings(&editor_catalog,"Floor Coverings","floor",true);_=catalog_discover_coverings(&editor_catalog,"Wall Coverings","wall",false);editor_state={tool=.Select,view=.Isometric,snap_mode=.Construction,room_mode=.Rectangle,paint_target=.Floor,catalog_id=len(editor_catalog.entries)>0?editor_catalog.entries[0].id:"",catalog_category="all",foundation_kind=.Slab,foundation_depth=.25,terrain_mode=.Raise,terrain_radius=2,terrain_strength=.5,opening_width=1.6,opening_height=1.4,opening_sill_height=.72,window_style=.Fixed,roof_style=.Gable,roof_pitch=30,roof_overhang=.4,link_kind=.Stairs,link_width=1,path_kind=.Road,path_width=3,water_elevation=.25,marker_kind=.Staging,marker_radius=.5,marker_camera_height=2,light_kind=.Point,light_range=4,light_intensity=1,light_elevation=2.2,light_cone_angle=45,light_color={255,236,196,255},recovery_available=os.exists(level_active_autosave_path)};if editor_state.catalog_id!="" do catalog_record_recent(&editor_state,editor_state.catalog_id);level_project_to_runtime(&level_document);return validation}
