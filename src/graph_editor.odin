package main

GRAPH_LEGACY_DEFAULT_PATH :: "assets/stories/mysteries/the_torn_appointment.story.toml"
GRAPH_LEGACY_AUTOSAVE_PATH :: "assets/stories/mysteries/.the_torn_appointment.story.autosave.toml"
GRAPH_MAX_NODES :: 256
GRAPH_MAX_SCENES :: 64
GRAPH_HISTORY_CAPACITY :: 64
GRAPH_SELECTION_CAPACITY :: 64
GRAPH_CLIPBOARD_CAPACITY :: 64
GRAPH_MAX_DEFINITIONS :: 512
GRAPH_MAX_LOCALIZATIONS :: 512

Graph_View :: enum {
	Graph,
	Script,
	Localization,
	Conditions,
	Effects,
}
Graph_Confirm :: enum {
	None,
	Delete_Scene,
}
Graph_Diagnostic_Severity :: enum {
	Warning,
	Error,
}
Graph_Field :: enum {
	None,
	Scene_Id,
	Scene_Display_Name,
	Scene_Bound_Entity,
	Scene_Summary,
	Scene_Return,
	Node_Id,
	Node_Scene,
	Node_Kind,
	Line_Id,
	Text,
	Summary,
	Speaker,
	Camera,
	Actor,
	Actor_Mark,
	Animation,
	UI_Image_Asset,
	Sound_Cue_Asset,
	Animation_Asset,
	Interaction,
	Event,
	Subscene,
	Domain_Ref,
	Condition,
	Effects,
	Condition_Root,
	First_Effect,
	Effect_Count,
	Clue,
	Ending,
	UI,
	Next,
	Success,
	Failure,
	Cancel,
	Blocking,
	Requires_Clues,
	Requires_Claims,
	Requires_Topics,
	Unlock_Clues,
	Unlock_Claims,
	Unlock_Topics,
	Duration,
	Transition,
	Choice_Id,
	Choice_Label,
	Choice_Target,
	Choice_Condition,
	Localization_Language,
	Localization_Text,
	Localization_Status,
	Localization_Note,
	Localization_Voice,
	Localization_Filter_Language,
	Localization_Filter_Status,
	Condition_Id,
	Condition_Kind,
	Condition_Value,
	Condition_Value_2,
	Condition_Value_3,
	Condition_Value_4,
	Condition_Value_5,
	Effect_Id,
	Effect_Kind,
	Effect_Value,
	Effect_Value_2,
	Effect_Value_3,
	Effect_Value_4,
	Effect_Value_5,
	Search,
}
Graph_Port_Kind :: enum {
	None,
	Next,
	Success,
	Failure,
	Cancel,
	Choice,
}
Graph_Field_Edit :: struct {
	active, multiline, picker:                          bool,
	field:                                              Graph_Field,
	node, choice_index, picker_selected, picker_offset: int,
	buffer:                                             [2048]u8,
	count:                                              int,
	error:                                              string,
}
Graph_Edge_Selection :: struct {
	active:       bool,
	node:         int,
	port:         Graph_Port_Kind,
	choice_index: int,
}
Graph_Edge_Drag :: struct {
	active:       bool,
	node:         int,
	port:         Graph_Port_Kind,
	choice_index: int,
	start:        Vec2,
}
Graph_Clipboard :: struct {
	nodes:              [GRAPH_CLIPBOARD_CAPACITY]Graph_Node,
	node_count:         int,
	localizations:      [256]Graph_Localization,
	localization_count: int,
	anchor:             Vec2,
}
Graph_Debugger :: struct {
	paused, step_requested, completed: bool,
	page:                              int,
	last_node:                         string,
	recent:                            [16]string,
	recent_count:                      int,
}
Graph_Topic_List :: struct {
	values: [64]string,
	count:  int,
}
Graph_Marquee :: struct {
	active:         bool,
	start, current: Vec2,
}
Graph_Minimap_Layout :: struct {
	valid:          bool,
	world, content: Rect,
	scale:          f32,
}
Graph_Beat :: struct {
	id,
	scene,
	kind,
	line_id,
	speaker,
	text,
	next,
	success,
	failure,
	cancel,
	subscene_id:                             string,
	ui,
	camera,
	actor,
	actor_mark,
	animation,
	interaction,
	event_id,
	domain_ref,
	condition_id,
	clue,
	summary,
	ending: string,
	ui_image_asset_ref,
	sound_cue_asset_ref,
	animation_asset_ref:                                                     string,
	duration,
	transition:                                                                                             f32,
	condition_root,
	first_effect,
	effect_count:                                                                       int,
	blocking:                                                                                                         bool,
	choice_ids,
	choice_labels,
	choice_targets,
	choice_conditions:                                                     []string,
	effect_ids:                                                                                                       []string,
	requires_clues,
	requires_claims,
	requires_topics:                                                                 []string,
	unlock_clues,
	unlock_claims,
	unlock_topics:                                                                       []string,
	metadata_requires,
	metadata_unlocks:                                                                              []string,
	metadata_refs_dirty:                                                                                              bool,
}
Graph_Scene_Data :: struct {
	id, display_name, source, entry, summary, return_to: string,
}
Graph_Node :: struct {
	beat:      Graph_Beat,
	position:  Vec2,
	collapsed: bool,
}
Graph_Scene :: struct {
	scene: Graph_Scene_Data,
	pan:   Vec2,
	zoom:  f32,
}
Graph_Localization :: struct {
	node_id, language, text, status, note, voice: string,
}
Graph_Diagnostic :: struct {
	severity:                   Graph_Diagnostic_Severity,
	scene_id, node_id, message: string,
}
Graph_Reference :: struct {
	kind, scene_id, node_id, field: string,
	choice_index:                   int,
}
Graph_Reference_List :: struct {
	items:     [256]Graph_Reference,
	count:     int,
	truncated: bool,
}
Graph_Picker_Create_Callback :: #type proc "odin" (
	field: Graph_Field,
	suggested_id: string,
	userdata: rawptr,
) -> (
	string,
	bool,
)
Graph_Document :: struct {
	case_id:                       string,
	revision:                      u64,
	dirty:                         bool,
	scenes:                        [GRAPH_MAX_SCENES]Graph_Scene,
	scene_count:                   int,
	nodes:                         [GRAPH_MAX_NODES]Graph_Node,
	node_count:                    int,
	conditions:                    [dynamic]Story_Condition,
	condition_count:               int,
	effects:                       [dynamic]Story_Effect,
	effect_count:                  int,
	localizations:                 [512]Graph_Localization,
	localization_count:            int,
	diagnostics:                   [512]Graph_Diagnostic,
	diagnostic_count, error_count: int,
}
Graph_State :: struct {
	active_scene, selected_node, hover_node:                                        int,
	selection:                                                                      [GRAPH_SELECTION_CAPACITY]int,
	selection_count:                                                                int,
	view:                                                                           Graph_View,
	pan:                                                                            Vec2,
	zoom:                                                                           f32,
	panning:                                                                        bool,
	pan_origin, pan_start:                                                          Vec2,
	search_active, diagnostics_visible, help_visible:                               bool,
	search_query:                                                                   string,
	search_result:                                                                  int,
	localization_scene_only, localization_missing_text, localization_missing_voice: bool,
	localization_language, localization_status:                                     string,
	autosave_status:                                                                string,
	confirm:                                                                        Graph_Confirm,
	selected_condition, selected_effect, selected_localization:                     int,
	quick_add, quick_add_latch:                                                     bool,
	quick_add_at:                                                                   Vec2,
	quick_add_selected:                                                             int,
	dragging:                                                                       bool,
	drag_origin, drag_node_origin:                                                  Vec2,
	drag_node_origins:                                                              [GRAPH_SELECTION_CAPACITY]Vec2,
	choice_reorder:                                                                 Graph_Choice_Reorder,
	field_edit:                                                                     Graph_Field_Edit,
	edge_selection, edge_hover:                                                     Graph_Edge_Selection,
	edge_drag:                                                                      Graph_Edge_Drag,
	marquee:                                                                        Graph_Marquee,
	feedback:                                                                       string,
	feedback_error:                                                                 bool,
	feedback_frames:                                                                int,
	inspector_scroll, inspector_scroll_max:                                         f32,
	inspector_field_index, choice_page:                                             int,
	playtesting:                                                                    bool,
	play_scene, play_node:                                                          int,
	debugger:                                                                       Graph_Debugger,
}
Graph_Choice_Reorder :: struct {
	active, history_started: bool,
	node, index:             int,
}
Graph_Snapshot :: struct {
	document: Graph_Document,
	label:    string,
}
Graph_History :: struct {
	undo, redo:             [GRAPH_HISTORY_CAPACITY]Graph_Snapshot,
	undo_count, redo_count: int,
}
Graph_Playtest_Snapshot :: struct {
	active:                                                                    bool,
	game:                                                                      Game,
	scene, node:                                                               int,
	pan:                                                                       Vec2,
	zoom:                                                                      f32,
	view:                                                                      Graph_View,
	search_query:                                                              string,
	search_result, selected_condition, selected_effect, selected_localization: int,
	diagnostics_visible, help_visible:                                         bool,
}

graph_document: Graph_Document
graph_state: Graph_State
graph_history: Graph_History
graph_playtest_snapshot: Graph_Playtest_Snapshot
graph_clipboard: Graph_Clipboard
graph_autosave_enabled: bool
graph_active_source_path := GRAPH_LEGACY_DEFAULT_PATH
graph_active_autosave_path := GRAPH_LEGACY_AUTOSAVE_PATH
graph_playtest_project: Story_Project
graph_playtest_compiled: Compiled_Story
graph_playtest_runtime: Story_Runtime
graph_source_project: ^Story_Project
graph_picker_create_callback: Graph_Picker_Create_Callback
graph_picker_create_userdata: rawptr
graph_active_layout_path: string
graph_import_error: string
