package main

when ODIN_OS == .Windows {
	foreign import courier_textshape "../third_party/textshape.lib"
} else {
	foreign import courier_textshape "../third_party/libtextshape.a"
}
@(default_calling_convention = "c")
foreign courier_textshape {
	vo_textshape_init :: proc(font_kind: i32, font_path: cstring, logical_height: f32) -> i32 ---
	vo_textshape_width :: proc(font_kind: i32, text: [^]u8, len: i32, text_scale, fallback_advance: f32) -> f32 ---
	vo_textshape_shape :: proc(font_kind: i32, text: [^]u8, len: i32, text_scale: f32, out: [^]Textshape_Glyph, out_cap: i32) -> i32 ---
	vo_textshape_render_ascii_atlas :: proc(font_kind: i32, glyph_first, glyph_last, pixel_height, cell_width, cell_height, columns: i32, out_rgba: [^]u8, out_len: i32) -> i32 ---
}

Textshape_Glyph :: struct {
	glyph_id:                                 u32,
	x_offset, y_offset, x_advance, y_advance: f32,
}
when ODIN_OS != .Windows {
	foreign import stb_vorbis "../third_party/libstb_vorbis.a"
} else {
	foreign import stb_vorbis "../third_party/stb_vorbis.lib"
}
when ODIN_OS == .Darwin {
	foreign import chicago_editor_menu "../third_party/libchicago_editor_menu.a"
	@(default_calling_convention = "c")
	foreign chicago_editor_menu {chicago_editor_menu_install :: proc() ---
		chicago_editor_menu_poll :: proc() -> i32 ---
		chicago_editor_open_file :: proc(title: cstring) -> cstring ---
		chicago_editor_save_file :: proc(title, suggested: cstring) -> cstring ---
		chicago_editor_select_directory :: proc(title: cstring) -> cstring ---
		chicago_editor_reveal_path :: proc(path: cstring) -> bool ---}
}
@(default_calling_convention = "c")
foreign stb_vorbis {
	stb_vorbis_decode_filename :: proc(filename: cstring, channels, sample_rate: ^i32, output: ^[^]i16) -> i32 ---
	chicago_vorbis_free :: proc(samples: [^]i16) ---
}

Screen :: enum {
	Title,
	Campaign,
	Campaign_Action,
	Campaign_Cases,
	Authoring,
	Options,
	Pause,
	Introduction,
	Exterior,
	Investigate,
	Dialogue,
	Check,
	Attributes,
	Notebook,
	Board,
	Challenge,
	Recreate,
	Reveal_Prep,
	Reveal,
	Result,
	Game_Over,
	Diagnostics,
	Loading,
	Theme_Knoll,
	Theme_Knoll_Details,
}
Scene_Transition_Style :: enum {
	Horizontal,
	Vertical,
	Diagonal,
	Iris,
	Fade,
}
Editor_Mode :: enum {
	None,
	Build,
	Graph,
}
Case_Phase :: enum {
	Introduction,
	Investigation,
	Reveal_Preparation,
	Final_Reveal,
	Case_Result,
}
Sound_Cue :: enum {
	Evidence,
	Fact,
	Pick_Up,
	Snap,
	Reject,
	Recreate,
	Shutter,
	Sightline_Fail,
	Tick,
	Reveal_Proven,
	Door_Open,
	Door_Close,
	Switch,
	Decisive_Clue,
	Candle_Out,
	Shutter_Close,
}
Character_Animation :: struct {
	current, next, idle_clip, action_clip:                int,
	time, next_time, transition:                          f32,
	transitioning, interacting, action_loop, action_hold: bool,
}
Runtime_Interactive :: struct {
	id, prompt, condition_id, focused_scene:          string,
	behavior:                                         Interaction_Behavior,
	openness, target, light_level, interaction_range: f32,
	effect_ids:                                       [STORY_MAX_NODE_EFFECTS]string,
	effect_id_count:                                  int,
	active, locked, powered:                          bool,
}
Context_Target_Kind :: enum {
	None,
	Story_Entity,
	Runtime_Interactive,
	Landmark,
	Vehicle,
	Transition,
}
Context_Status :: enum {
	Available,
	Complete,
	Locked,
	No_Power,
	Obstructed,
	Unavailable,
}
Context_Target :: struct {
	valid:                                 bool,
	kind:                                  Context_Target_Kind,
	status:                                Context_Status,
	stable_id, label, action:              string,
	world:                                 Vec2,
	source_index, runtime_index, priority: int,
	distance:                              f32,
	reachable:                             bool,
}
Context_State :: struct {
	current, previous:              Context_Target,
	targets:                        [10]Context_Target,
	target_count, selected:         int,
	focus_started, last_valid_time: f32,
	feedback, feedback_id:          string,
	feedback_status:                Context_Status,
	feedback_expires:               f32,
	location_index:                 int,
	location_changed_at:            f32,
}
Dialogue_Interaction_Item :: enum {
	None,
	Statuette,
	Desk,
	Cloth,
}
Dialogue_Interaction_Discovery_Phase :: enum {
	Hidden,
	Candidate,
	Focusing,
	Revealing,
	Revealed,
}
Dialogue_Interaction_Region :: enum {
	Model,
	Tools,
	Dialogue,
}
Dialogue_Interaction_State :: struct {
	item:                                                                                           Dialogue_Interaction_Item,
	yaw,
	pitch,
	zoom,
	yaw_velocity,
	pitch_velocity,
	candidate_time,
	phase_time,
	drawer:             f32,
	phase:                                                                                          Dialogue_Interaction_Discovery_Phase,
	region:                                                                                         Dialogue_Interaction_Region,
	selected_tool:                                                                                  int,
	mouse_last:                                                                                     Vec2,
	mouse_dragging,
	key_inserted,
	lock_turned,
	catch_found,
	catch_pressed,
	new_dialogue,
	completed: bool,
	feedback,
	ledger:                                                                               string,
}
Dialogue_Transcript_Entry :: struct {
	speaker, text, kind, conversation_id: string,
}
Story_Presentation_State :: struct {
	active:                                                    bool,
	step:                                                      Story_Runtime_Step,
	scene, beat:                                               int,
	beat_entered:                                              bool,
	beat_elapsed:                                              f32,
	ui_opacity, ui_from, ui_target, ui_transition, ui_elapsed: f32,
	interaction_active:                                        bool,
	camera_active:                                             bool,
	camera_start, camera_target:                               Vec2,
	camera_orbit_start, camera_orbit_target:                   f32,
	actor_entity:                                              int,
	actor_start, actor_target:                                 Vec2,
	error:                                                     string,
}
Workbench_Snapshot :: struct {
	events:          [9]Workbench_Event,
	count, selected: int,
	accused:         string,
}
Drag_Kind :: enum {
	None,
	Event,
	Miniature,
}
Hypothesis_State :: enum {
	Locked,
	Unsubstantiated,
	Supported,
	Substantiated,
	Eliminated,
	Explained,
}
Build_Tool :: enum {
	Select,
	Foundation,
	Paint,
	Wall_Paint,
	Plant,
	Light,
	Door,
	Window,
	Wall,
	Room,
	Roof,
	Stairs,
	Path,
	Water,
	Terrain,
	Marker,
}
BUILD_TOOL_GRID := [16]Build_Tool {
	.Select,
	.Room,
	.Foundation,
	.Wall,
	.Door,
	.Window,
	.Paint,
	.Plant,
	.Light,
	.Roof,
	.Stairs,
	.Path,
	.Water,
	.Terrain,
	.Marker,
	.Wall_Paint,
}
BUILD_TOOL_ICONS := [16][2]int {
	{0, 0},
	{1, 1},
	{1, 6},
	{1, 0},
	{2, 0},
	{2, 3},
	{3, 0},
	{7, 0},
	{7, 4},
	{5, 0},
	{2, 4},
	{7, 1},
	{4, 5},
	{4, 0},
	{7, 2},
	{3, 2},
}
BUILD_MODE_GRID := [11]Build_Tool {
	.Select,
	.Room,
	.Foundation,
	.Paint,
	.Plant,
	.Roof,
	.Stairs,
	.Path,
	.Water,
	.Terrain,
	.Marker,
}
BUILD_MODE_SHORTCUTS := [11]string{"1", "2", "3", "4", "5", "6", "8", "9", "0", "7", "M"}
BUILD_MODE_ICONS := [11][2]int {
	{0, 0},
	{1, 1},
	{1, 6},
	{3, 0},
	{7, 0},
	{5, 0},
	{2, 4},
	{7, 1},
	{4, 5},
	{4, 0},
	{7, 2},
}
MARKER_KIND_ICONS := [8][2]int{{7, 6}, {6, 6}, {6, 5}, {7, 5}, {5, 6}, {4, 6}, {3, 6}, {2, 6}}
BUILD_TOOL_NAMES := [16]string {
	"SELECT",
	"ROOM",
	"FOUNDATION",
	"WALL",
	"DOOR",
	"WINDOW",
	"SURFACES",
	"OBJECTS",
	"LIGHTS",
	"ROOFS",
	"STAIRS",
	"PATHS",
	"WATER",
	"TERRAIN",
	"MARKERS",
	"WALL STYLE",
}
