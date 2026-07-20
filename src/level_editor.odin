package main

import "core:fmt"
import "core:strings"

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

level_set_active_paths :: proc(source_path, autosave_path: string) -> Validation {
	if source_path == "" do return {false, "level source path cannot be empty"}
	if autosave_path == "" do return {false, "level autosave path cannot be empty"}
	if source_path == autosave_path do return {false, "level source and autosave paths must be distinct"}
	owned_source, source_error := strings.clone(
		source_path,
	); if source_error != nil do return {false, "could not retain level source path"}
	owned_autosave, autosave_error := strings.clone(
		autosave_path,
	); if autosave_error != nil do return {false, "could not retain level autosave path"}
	level_active_source_path = owned_source
	level_active_autosave_path = owned_autosave
	LEVEL_DEFAULT_PATH = level_active_source_path
	LEVEL_AUTOSAVE_PATH = level_active_autosave_path
	return {true, "LEVEL PROJECT PATHS UPDATED"}
}

level_sync_legacy_source_path :: proc() -> Validation {
	if LEVEL_DEFAULT_PATH == level_active_source_path do return {true, "LEVEL PROJECT PATHS CURRENT"}
	autosave_path := LEVEL_AUTOSAVE_PATH
	if autosave_path == level_active_autosave_path do autosave_path = fmt.tprintf("%s.autosave.toml", LEVEL_DEFAULT_PATH)
	return level_set_active_paths(LEVEL_DEFAULT_PATH, autosave_path)
}

Level_Story :: struct {
	id, name:                    string,
	base_elevation, wall_height: f32,
}
Level_Room :: struct {
	id, name:                                     string,
	story:                                        int,
	points:                                       [dynamic]Vec2,
	platform_height:                              f32,
	floor_material, wall_material, ceiling_style: string,
	floor_tint, wall_tint:                        [4]u8,
	exterior:                                     bool,
}
Level_Path_Kind :: enum {
	Wall,
	Freestanding_Wall,
	Half_Wall,
	Fence,
	Road,
	Footpath,
}
Level_Path :: struct {
	id:       string,
	story:    int,
	kind:     Level_Path_Kind,
	points:   [dynamic]Vec2,
	material: string,
	width:    f32,
}
Level_Opening_Kind :: enum {
	Door,
	Window,
	Arch,
	Gate,
}
Interaction_Behavior :: enum {
	None,
	Door,
	Toggle,
	Shutter,
}
Door_Material :: enum {
	Oak,
	Painted,
	Walnut,
}
Door_Style :: enum {
	Hinged,
	Double,
	Sliding,
}
Window_Style :: enum {
	Fixed,
	Casement,
	Awning,
	Picture,
	Double_Hung,
}
Level_Opening :: struct {
	id, host_path:                                   string,
	kind:                                            Level_Opening_Kind,
	door_material:                                   Door_Material,
	door_style:                                      Door_Style,
	window_style:                                    Window_Style,
	window_flipped, window_hinge_right:              bool,
	interaction:                                     Interaction_Behavior,
	interaction_prompt, condition_id, focused_scene: string,
	effect_ids:                                      [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                 int,
	interaction_range:                               f32,
	initially_active, locked, powered:               bool,
	segment:                                         int,
	position, width, height, sill_height:            f32,
}
Level_Object :: struct {
	id, catalog_id, support_id, model_asset_ref, material_asset_ref, texture_asset_ref: string,
	interaction_prompt, condition_id, focused_scene:                                    string,
	effect_ids:                                                                         [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                                                    int,
	interaction:                                                                        Interaction_Behavior,
	initially_active, locked, powered:                                                  bool,
	interaction_range:                                                                  f32,
	story:                                                                              int,
	position:                                                                           Vec2,
	elevation, rotation:                                                                f32,
	tint, bark_tint, foliage_tint:                                                      [4]u8,
}
Level_Light_Kind :: enum {
	Point,
	Spot,
	Area,
}
Level_Light :: struct {
	id:                                              string,
	kind:                                            Level_Light_Kind,
	story:                                           int,
	position:                                        Vec2,
	elevation, range, intensity, facing, cone_angle: f32,
	color:                                           [4]u8,
}
Level_Roof_Style :: enum {
	Gable,
	Hip,
	Mansard,
	Flat,
	Parapet,
}
Level_Roof :: struct {
	id, room_id:                  string,
	story:                        int,
	style:                        Level_Roof_Style,
	pitch, overhang, ridge_angle: f32,
	gutters:                      bool,
}
Level_Water :: struct {
	id:        string,
	points:    [dynamic]Vec2,
	elevation: f32,
}
Level_Foundation_Kind :: enum {
	Slab,
	Raised,
	Basement,
}
Level_Foundation :: struct {
	id:               string,
	kind:             Level_Foundation_Kind,
	story:            int,
	points:           [dynamic]Vec2,
	elevation, depth: f32,
}
Level_Vertical_Link_Kind :: enum {
	Stairs,
	Ladder,
	Elevator,
}
Level_Vertical_Link :: struct {
	id:                   string,
	kind:                 Level_Vertical_Link_Kind,
	from_story, to_story: int,
	start, finish:        Vec2,
	width:                f32,
}
Level_Marker_Kind :: enum {
	Player_Spawn,
	Character_Spawn,
	Interaction,
	Clue,
	Trigger,
	Transition,
	Camera,
	Staging,
}
Level_Marker :: struct {
	id, reference, destination, interaction_prompt, condition_id, focused_scene: string,
	effect_ids:                                                                  [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                                             int,
	kind:                                                                        Level_Marker_Kind,
	interaction:                                                                 Interaction_Behavior,
	initially_active, locked, powered:                                           bool,
	story:                                                                       int,
	position:                                                                    Vec2,
	radius, facing, camera_height, interaction_range:                            f32,
}
Level_Diagnostic_Severity :: enum {
	Info,
	Warning,
	Error,
}
Level_Diagnostic :: struct {
	severity:           Level_Diagnostic_Severity,
	entity_id, message: string,
	story:              int,
	position:           Vec2,
}

Level_Document :: struct {
	version, id, name:                   string,
	width, height:                       int,
	story_limit, active_story:           int,
	default_snap, fine_snap, angle_snap: f32,
	revision:                            u64,
	dirty:                               bool,
	stories:                             [dynamic]Level_Story,
	rooms:                               [dynamic]Level_Room,
	paths:                               [dynamic]Level_Path,
	openings:                            [dynamic]Level_Opening,
	objects:                             [dynamic]Level_Object,
	lights:                              [dynamic]Level_Light,
	roofs:                               [dynamic]Level_Roof,
	waters:                              [dynamic]Level_Water,
	foundations:                         [dynamic]Level_Foundation,
	vertical_links:                      [dynamic]Level_Vertical_Link,
	markers:                             [dynamic]Level_Marker,
	terrain:                             [dynamic]f32,
	diagnostics:                         [dynamic]Level_Diagnostic,
}

Placement_State :: enum {
	Valid,
	Warning,
	Blocked,
}
Placement_Result :: struct {
	state:                  Placement_State,
	message:                string,
	bounds_min, bounds_max: Vec2,
}
Terrain_Brush_Mode :: enum {
	Raise,
	Lower,
	Smooth,
	Flatten,
	Slope,
}
Level_Command_Kind :: enum {
	Set_Metadata,
	Add_Story,
	Update_Story,
	Delete_Story,
	Reorder_Story,
	Set_Story_Height,
	Create_Foundation,
	Set_Foundation,
	Move_Foundation_Point,
	Delete_Foundation,
	Create_Room,
	Create_Room_Polygon,
	Split_Room,
	Merge_Rooms,
	Insert_Room_Vertex,
	Remove_Room_Vertex,
	Duplicate_Room,
	Move_Room,
	Rotate_Room,
	Move_Room_Vertex,
	Move_Room_Edge,
	Resize_Room,
	Set_Platform,
	Delete_Room,
	Add_Path,
	Set_Path,
	Move_Path_Point,
	Add_Opening,
	Set_Opening,
	Delete_Opening,
	Set_Interaction,
	Place_Object,
	Duplicate_Object,
	Move_Object,
	Set_Object_Elevation,
	Set_Object_Color,
	Delete_Object,
	Add_Light,
	Set_Light,
	Delete_Light,
	Paint_Floor,
	Paint_Walls,
	Paint_Room,
	Set_Room_Tint,
	Create_Roof,
	Set_Roof,
	Delete_Roof,
	Create_Vertical_Link,
	Set_Vertical_Link,
	Move_Vertical_Link_Point,
	Delete_Vertical_Link,
	Create_Water,
	Set_Water,
	Move_Water_Point,
	Delete_Water,
	Sculpt_Terrain,
	Add_Marker,
	Set_Marker,
	Delete_Marker,
}
Level_Command :: struct {
	kind:                                                                   Level_Command_Kind,
	entity_id:                                                              string,
	a, b, c:                                                                Vec2,
	value:                                                                  f32,
	material, destination, interaction_prompt, condition_id, focused_scene: string,
	effect_ids:                                                             [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                                        int,
	interaction:                                                            Interaction_Behavior,
	initially_active, locked, powered:                                      bool,
	interaction_range:                                                      f32,
	color:                                                                  [4]u8,
	brush:                                                                  Terrain_Brush_Mode,
	points:                                                                 [32]Vec2,
	point_count:                                                            int,
	metadata_id, metadata_name:                                             string,
	metadata_width, metadata_height, from, to:                              int,
	story:                                                                  Level_Story,
}

Level_Reference :: struct {
	kind, owner_id, field: string,
}
Level_Reference_Preview :: struct {
	items:     [128]Level_Reference,
	count:     int,
	truncated: bool,
}
Level_City_Destination :: struct {
	id, display_name, city_site, level_spawn: string,
}
Level_Template :: struct {
	id, name: string,
	document: Level_Document,
}
Level_Room_Prefab :: struct {
	id, name: string,
	room:     Level_Room,
	objects:  [dynamic]Level_Object,
}
Level_Prop_Prefab :: struct {
	id, name: string,
	object:   Level_Object,
}
Level_Reuse_Action_Kind :: enum {
	Create_Level_From_Template,
	Instantiate_Room_Prefab,
	Instantiate_Prop_Prefab,
}
Dirty_Regions :: struct {
	terrain, architecture, navigation, lighting, ui: bool,
	min, max:                                        Vec2,
}
Editor_Selection_Kind :: enum {
	None,
	Foundation,
	Room,
	Vertex,
	Edge,
	Path,
	Opening,
	Object,
	Light,
	Roof,
	Vertical_Link,
	Water,
	Marker,
	Terrain,
}
Editor_Selection :: struct {
	kind:      Editor_Selection_Kind,
	entity_id: string,
	sub_index: int,
}
Editor_Tool :: enum {
	Select,
	Room,
	Wall,
	Opening,
	Paint,
	Object,
	Terrain,
	Water,
	Roof,
	Vertical_Link,
	Marker,
	Diagnostics,
}
Editor_View_Mode :: enum {
	Isometric,
	Top_Down,
	Active_Story,
	Stories_Below,
	Cutaway,
	Roof,
	Collision,
	Navmesh,
	Lighting,
	Markers,
}
Editor_Snap_Mode :: enum {
	Construction,
	Fine,
	Off,
}
Editor_Numeric_Field :: enum {
	None,
	Object_Height,
	Object_Angle,
	Object_X,
	Object_Y,
	Opening_Position,
	Opening_Width,
	Opening_Height,
	Opening_Sill,
	Room_Level,
	Foundation_Measure,
	Path_Width,
	Water_Surface,
	Link_Width,
	Roof_Pitch,
	Roof_Overhang,
	Roof_Ridge,
	Light_Range,
	Light_Intensity,
	Light_Height,
	Light_Facing,
	Light_Cone,
	Marker_X,
	Marker_Y,
	Marker_Radius,
	Marker_Facing,
	Marker_Height,
}
Room_Draw_Mode :: enum {
	Rectangle,
	Polygon,
}
Paint_Target :: enum {
	Floor,
	Walls,
	Room,
}
Editor_State :: struct {
	tool:                                                                                            Editor_Tool,
	view:                                                                                            Editor_View_Mode,
	snap_mode:                                                                                       Editor_Snap_Mode,
	snap_suspended:                                                                                  bool,
	selection:                                                                                       [16]Editor_Selection,
	selection_count:                                                                                 int,
	catalog_id,
	catalog_category,
	search:                                                            string,
	search_buffer:                                                                                   [32]u8,
	search_count,
	catalog_page:                                                                      int,
	search_active:                                                                                   bool,
	catalog_recent:                                                                                  [8]string,
	catalog_recent_count:                                                                            int,
	catalog_pinned:                                                                                  [16]string,
	catalog_pinned_count:                                                                            int,
	dirty:                                                                                           Dirty_Regions,
	recovery_available,
	playtesting,
	shortcut_help_visible,
	exit_confirm_visible,
	view_menu_visible: bool,
	numeric_field:                                                                                   Editor_Numeric_Field,
	numeric_buffer:                                                                                  [24]u8,
	numeric_count:                                                                                   int,
	numeric_replace_on_input:                                                                        bool,
	marker_name_active:                                                                              bool,
	marker_name_buffer:                                                                              [64]u8,
	marker_name_count:                                                                               int,
	diagnostics_visible:                                                                             bool,
	diagnostic_selected:                                                                             int,
	feedback:                                                                                        string,
	feedback_frames:                                                                                 int,
	feedback_error:                                                                                  bool,
	drag_active:                                                                                     bool,
	drag_selection:                                                                                  Editor_Selection,
	drag_origin_world,
	drag_current_world,
	drag_delta:                                               Vec2,
	drag_preview:                                                                                    Placement_Result,
	object_rotate_active:                                                                            bool,
	object_rotate_id:                                                                                string,
	object_rotate_original,
	object_rotate_preview:                                                   f32,
	terrain_mode:                                                                                    Terrain_Brush_Mode,
	terrain_radius,
	terrain_strength,
	terrain_sample:                                                f32,
	terrain_stroke_active:                                                                           bool,
	terrain_stroke_start,
	terrain_stroke_current:                                                    Vec2,
	room_mode:                                                                                       Room_Draw_Mode,
	room_exterior:                                                                                   bool,
	room_draw_points:                                                                                [32]Vec2,
	room_draw_count:                                                                                 int,
	room_rectangle_active:                                                                           bool,
	room_rectangle_start,
	room_rectangle_current:                                                    Vec2,
	room_rectangle_preview:                                                                          Placement_Result,
	wall_preview_active:                                                                             bool,
	wall_preview_point:                                                                              Vec2,
	foundation_kind:                                                                                 Level_Foundation_Kind,
	foundation_mode:                                                                                 Room_Draw_Mode,
	foundation_elevation,
	foundation_depth:                                                          f32,
	foundation_draw_points:                                                                          [32]Vec2,
	foundation_draw_count:                                                                           int,
	foundation_polygon_preview:                                                                      Placement_Result,
	foundation_rectangle_active:                                                                     bool,
	foundation_rectangle_start,
	foundation_rectangle_current:                                        Vec2,
	foundation_rectangle_preview:                                                                    Placement_Result,
	placement_active:                                                                                bool,
	placement_position:                                                                              Vec2,
	placement_rotation,
	placement_elevation:                                                         f32,
	placement_support_id:                                                                            string,
	placement_preview:                                                                               Placement_Result,
	placement_rotate_left_latch,
	placement_rotate_right_latch:                                       bool,
	paint_target:                                                                                    Paint_Target,
	paint_eyedropper:                                                                                bool,
	paint_hover:                                                                                     Editor_Selection,
	paint_hover_active:                                                                              bool,
	opening_active:                                                                                  bool,
	opening_host:                                                                                    Editor_Selection,
	opening_position:                                                                                Vec2,
	opening_command:                                                                                 Level_Command,
	opening_preview:                                                                                 Placement_Result,
	opening_width,
	opening_height,
	opening_sill_height:                                              f32,
	door_material:                                                                                   Door_Material,
	door_style:                                                                                      Door_Style,
	window_style:                                                                                    Window_Style,
	roof_style:                                                                                      Level_Roof_Style,
	roof_pitch,
	roof_overhang,
	roof_ridge_angle:                                                     f32,
	roof_gutters:                                                                                    bool,
	roof_hover:                                                                                      Editor_Selection,
	roof_hover_active:                                                                               bool,
	roof_preview:                                                                                    Placement_Result,
	link_anchor_active:                                                                              bool,
	link_anchor,
	link_finish:                                                                        Vec2,
	link_width:                                                                                      f32,
	link_kind:                                                                                       Level_Vertical_Link_Kind,
	link_preview:                                                                                    Placement_Result,
	path_kind:                                                                                       Level_Path_Kind,
	path_width:                                                                                      f32,
	path_draw_points:                                                                                [32]Vec2,
	path_draw_count:                                                                                 int,
	water_draw_points:                                                                               [32]Vec2,
	water_draw_count:                                                                                int,
	water_elevation:                                                                                 f32,
	marker_kind:                                                                                     Level_Marker_Kind,
	marker_radius,
	marker_facing,
	marker_camera_height:                                              f32,
	marker_reference,
	marker_destination:                                                            string,
	light_kind:                                                                                      Level_Light_Kind,
	light_range,
	light_intensity,
	light_elevation,
	light_facing,
	light_cone_angle:                   f32,
	light_color:                                                                                     [4]u8,
	cursor_world:                                                                                    Vec2,
	cursor_world_valid:                                                                              bool,
	box_select_active,
	box_select_additive:                                                          bool,
	box_select_start,
	box_select_current:                                                            Vec2,
}
Catalog_Entry_Kind :: enum {
	Object,
	Material,
}
Catalog_Presentation_Component :: struct {
	mesh, pose, state:        string,
	offset, state_offset:     [3]f32,
	scale:                    [3]f32,
	rotation, state_rotation: f32,
	tint:                     [4]u8,
	layer:                    int,
	decal, animated:          bool,
}
Catalog_Entry :: struct {
	id,
	category,
	model,
	thumbnail,
	placement,
	floor,
	wall,
	image,
	source_namespace,
	source_version: string,
	model_asset_ref,
	material_asset_ref,
	texture_asset_ref:                                          string,
	front_direction:                                                                                 string,
	dimensions:                                                                                      [3]f32,
	clearance_front,
	clearance_back,
	clearance_left,
	clearance_right:                                f32,
	floor_repeat_m,
	wall_repeat_m:                                                                   f32,
	surfaces,
	styles,
	affordances:                                                                   []string,
	kind:                                                                                            Catalog_Entry_Kind,
	footprint,
	surface_height,
	default_elevation:                                                    f32,
	emits_light:                                                                                     bool,
	light_kind:                                                                                      Level_Light_Kind,
	light_height,
	light_range,
	light_intensity,
	light_facing,
	light_cone_angle:                      f32,
	light_color:                                                                                     [4]u8,
	thumbnail_index,
	catalog_index,
	mesh_index:                                                      int,
	presentation_components:                                                                         [32]Catalog_Presentation_Component,
	presentation_component_count:                                                                    int,
	valid,
	thumbnail_missing,
	thumbnail_stale:                                                       bool,
}
Editor_Catalog :: struct {
	entries:  [dynamic]Catalog_Entry,
	selected: int,
	loaded:   bool,
}
Level_Change_Set :: struct {
	before, after: Level_Document,
	label:         string,
}
Level_History :: struct {
	undo, redo:             [LEVEL_HISTORY_CAPACITY]Level_Change_Set,
	undo_count, redo_count: int,
}

level_document: Level_Document
level_history: Level_History
// Document-only tools and tests can suppress the expensive renderer/navigation
// projection while still exercising the same validated transaction history.
level_transaction_projection_enabled := true
editor_state: Editor_State
editor_catalog: Editor_Catalog
