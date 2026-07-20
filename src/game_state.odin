package main

import "core:fmt"
import "core:crypto"
import "core:math"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:time"
import sdl "vendor:sdl3"
import ui "zelda_engine:ui"

when ODIN_OS == .Windows {
	foreign import courier_textshape "../../zelda-engine/third_party/textshape/textshape.lib"
} else {
	foreign import courier_textshape "../../zelda-engine/third_party/textshape/libtextshape.a"
}
@(default_calling_convention = "c")
foreign courier_textshape {
	vo_textshape_init :: proc(font_kind: i32, font_path: cstring, logical_height: f32) -> i32 ---
	vo_textshape_width :: proc(font_kind: i32, text: [^]u8, len: i32, text_scale, fallback_advance: f32) -> f32 ---
	vo_textshape_shape :: proc(font_kind: i32, text: [^]u8, len: i32, text_scale: f32, out: [^]Textshape_Glyph, out_cap: i32) -> i32 ---
	vo_textshape_render_ascii_atlas :: proc(font_kind: i32, glyph_first, glyph_last, pixel_height, cell_width, cell_height, columns: i32, out_rgba: [^]u8, out_len: i32) -> i32 ---
}

Textshape_Glyph :: struct {glyph_id:u32,x_offset,y_offset,x_advance,y_advance:f32}
when ODIN_OS != .Windows {
	foreign import stb_vorbis "../third_party/libstb_vorbis.a"
} else {
	foreign import stb_vorbis "../third_party/stb_vorbis.lib"
}
when ODIN_OS==.Darwin {
	foreign import chicago_editor_menu "../third_party/libchicago_editor_menu.a"
	@(default_calling_convention="c")
foreign chicago_editor_menu {chicago_editor_menu_install :: proc() ---;chicago_editor_menu_poll :: proc()->i32 ---;chicago_editor_open_file :: proc(title:cstring)->cstring ---;chicago_editor_save_file :: proc(title,suggested:cstring)->cstring ---;chicago_editor_select_directory :: proc(title:cstring)->cstring ---;chicago_editor_reveal_path :: proc(path:cstring)->bool ---}
}
@(default_calling_convention = "c")
foreign stb_vorbis {
	stb_vorbis_decode_filename :: proc(filename:cstring,channels,sample_rate:^i32,output:^[^]i16)->i32 ---
	chicago_vorbis_free :: proc(samples:[^]i16) ---
}

Screen :: enum { Title, Campaign, Campaign_Action, Campaign_Cases, Authoring, Options, Pause, Introduction, Exterior, Investigate, Dialogue, Check, Attributes, Notebook, Board, Challenge, Recreate, Reveal_Prep, Reveal, Result, Game_Over, Diagnostics, Loading, Theme_Knoll, Theme_Knoll_Details }
Scene_Transition_Style :: enum { Horizontal, Vertical, Diagonal, Iris, Fade }
Editor_Mode :: enum {None, Build, Graph}
Case_Phase :: enum { Introduction, Investigation, Reveal_Preparation, Final_Reveal, Case_Result }
Sound_Cue :: enum { Evidence, Fact, Pick_Up, Snap, Reject, Recreate, Shutter, Sightline_Fail, Tick, Reveal_Proven, Door_Open, Door_Close, Switch, Decisive_Clue, Candle_Out, Shutter_Close }
Character_Animation :: struct {current,next,idle_clip,action_clip:int,time,next_time,transition:f32,transitioning,interacting,action_loop,action_hold:bool}
Runtime_Interactive :: struct {id,prompt,condition_id,focused_scene:string,behavior:Interaction_Behavior,openness,target,light_level,interaction_range:f32,effect_ids:[STORY_MAX_NODE_EFFECTS]string,effect_id_count:int,active,locked,powered:bool}
Context_Target_Kind :: enum {None, Story_Entity, Runtime_Interactive, Landmark, Vehicle, Transition}
Context_Status :: enum {Available, Complete, Locked, No_Power, Obstructed, Unavailable}
Context_Target :: struct {
	valid:bool,
	kind:Context_Target_Kind,
	status:Context_Status,
	stable_id,label,action:string,
	world:Vec2,
	source_index,runtime_index,priority:int,
	distance:f32,
	reachable:bool,
}
Context_State :: struct {
	current,previous:Context_Target,
	targets:[10]Context_Target,
	target_count,selected:int,
	focus_started,last_valid_time:f32,
	feedback,feedback_id:string,
	feedback_status:Context_Status,
	feedback_expires:f32,
	location_index:int,
	location_changed_at:f32,
}
Dialogue_Interaction_Item :: enum {None, Statuette, Desk, Cloth}
Dialogue_Interaction_Discovery_Phase :: enum {Hidden, Candidate, Focusing, Revealing, Revealed}
Dialogue_Interaction_Region :: enum {Model, Tools, Dialogue}
Dialogue_Interaction_State :: struct {
	item:Dialogue_Interaction_Item,
	yaw,pitch,zoom,yaw_velocity,pitch_velocity,candidate_time,phase_time,drawer:f32,
	phase:Dialogue_Interaction_Discovery_Phase,
	region:Dialogue_Interaction_Region,
	selected_tool:int,
	mouse_last:Vec2,
	mouse_dragging,key_inserted,lock_turned,catch_found,catch_pressed,new_dialogue:bool,
	feedback,ledger:string,
}
Dialogue_Transcript_Entry :: struct {speaker,text,kind,conversation_id:string}
Story_Presentation_State :: struct {
	active:bool,
	step:Story_Runtime_Step,
	scene,beat:int,
	beat_entered:bool,
	beat_elapsed:f32,
	ui_opacity,ui_from,ui_target,ui_transition,ui_elapsed:f32,
	interaction_active:bool,
	camera_active:bool,
	camera_start,camera_target:Vec2,
	camera_orbit_start,camera_orbit_target:f32,
	actor_entity:int,
	actor_start,actor_target:Vec2,
	transcript:[64]Dialogue_Transcript_Entry,
	transcript_count:int,
	error:string,
}
Workbench_Snapshot :: struct {events:[9]Workbench_Event,count,selected:int,accused:string}
Drag_Kind :: enum {None, Event, Miniature}
Hypothesis_State :: enum {Locked, Unsubstantiated, Supported, Substantiated, Eliminated, Explained}
Build_Tool :: enum {Select,Foundation,Paint,Wall_Paint,Plant,Light,Door,Window,Wall,Room,Roof,Stairs,Path,Water,Terrain,Marker}
BUILD_TOOL_GRID := [16]Build_Tool{.Select,.Room,.Foundation,.Wall,.Door,.Window,.Paint,.Plant,.Light,.Roof,.Stairs,.Path,.Water,.Terrain,.Marker,.Wall_Paint}
BUILD_TOOL_ICONS := [16][2]int{{0,0},{1,1},{1,6},{1,0},{2,0},{2,3},{3,0},{7,0},{7,4},{5,0},{2,4},{7,1},{4,5},{4,0},{7,2},{3,2}}
BUILD_MODE_GRID := [11]Build_Tool{.Select,.Room,.Foundation,.Paint,.Plant,.Roof,.Stairs,.Path,.Water,.Terrain,.Marker}
BUILD_MODE_SHORTCUTS := [11]string{"1","2","3","4","5","6","8","9","0","7","M"}
BUILD_MODE_ICONS := [11][2]int{{0,0},{1,1},{1,6},{3,0},{7,0},{5,0},{2,4},{7,1},{4,5},{4,0},{7,2}}
MARKER_KIND_ICONS := [8][2]int{{7,6},{6,6},{6,5},{7,5},{5,6},{4,6},{3,6},{2,6}}
BUILD_TOOL_NAMES := [16]string{"SELECT","ROOM","FOUNDATION","WALL","DOOR","WINDOW","SURFACES","OBJECTS","LIGHTS","ROOFS","STAIRS","PATHS","WATER","TERRAIN","MARKERS","WALL STYLE"}
editor_build_tool_name :: proc(tool:Build_Tool)->string {for known,i in BUILD_TOOL_GRID do if known==tool do return BUILD_TOOL_NAMES[i];return "SELECT"}
editor_build_tool_shortcut :: proc(tool:Build_Tool)->string {for known,i in BUILD_MODE_GRID do if known==tool do return BUILD_MODE_SHORTCUTS[i];return ""}
editor_build_tool_idle_hint :: proc(tool:Build_Tool)->string {
	#partial switch tool {
	case .Select:return "Click or drag to select · Shift adds or removes items"
	case .Foundation:return "Step 1 · Drag a footprint or choose polygon mode"
	case .Paint:return "Step 1 · Choose a surface and material · Step 2 · Click a room"
	case .Wall_Paint:return "Choose a wall material, then click a room"
	case .Plant:return "Step 1 · Choose an object · Step 2 · Click to place it"
	case .Light:if editor_state.selection_count==1&&editor_state.selection[0].kind==.Light do return "Editing selected light · click empty space to place a new light";return "Click to place a light · select one to fine-tune it"
	case .Door:return "Step 1 · Move over a wall · Step 2 · Click to place a door"
	case .Window:return "Step 1 · Move over a wall · Step 2 · Click to place a window"
	case .Wall:return "Step 1 · Click wall start · Step 2 · Click wall end"
	case .Room:return "Step 1 · Drag a room footprint · Step 2 · Release to create"
	case .Roof:return "Step 1 · Move over a room · Step 2 · Adjust roof · Apply or click room"
	case .Stairs:return "Step 1 · Click lower landing · Step 2 · Click upper landing"
	case .Path:return "Step 1 · Click path start · Step 2 · Add points · Enter finishes"
	case .Water:return "Step 1 · Click shoreline start · Step 2 · Add 2+ points · Enter closes"
	case .Terrain:return "Drag on the lot to sculpt · Ctrl reverses the brush"
	case .Marker:if editor_state.selection_count==1&&editor_state.selection[0].kind==.Marker do return "Editing selected marker · click empty space to place a new marker";return "Choose a marker type, then click to place it"
	}
	return "Choose a tool to begin"
}
editor_selection_shortcut_hint :: proc(count:int)->string {if count>1 do return "Drag selection · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete";return "Drag to move · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete"}
editor_selection_status_hint :: proc(selection:Editor_Selection,count:int)->string {
	if editor_state.object_rotate_active do return "Drag to rotate · 15° snap · hold Alt for free angle · Esc cancels"
	if count>1 do return editor_selection_shortcut_hint(count)
	#partial switch selection.kind {
	case .Foundation:return editor_control_point_index(selection)>=0?"Drag foundation corner · Alt suspends snap · Esc cancels":"Drag a visible corner to reshape · adjust height in inspector"
	case .Edge:return "Drag edge · Insert corner from toolbar"
	case .Vertex:return "Drag corner · Remove corner from toolbar"
	case .Opening:return "Drag to slide · Resize from toolbar · Delete"
	case .Path:return editor_control_point_index(selection)>=0?"Drag path point · Alt suspends snap · Esc cancels":"Drag a visible point to reshape · adjust width in inspector"
	case .Water:return editor_control_point_index(selection)>=0?"Drag shoreline point · Alt suspends snap · Esc cancels":"Drag a visible point to reshape · adjust surface in inspector"
	case .Vertical_Link:return editor_control_point_index(selection)>=0?"Drag landing · Alt suspends snap · Esc cancels":"Drag either landing to reshape · adjust width in inspector"
	case .Roof:return "Edit with the Roof tool · Delete"
	}
	return editor_selection_shortcut_hint(1)
}
editor_escape_target :: proc(tool:Build_Tool)->Build_Tool {
	#partial switch tool {
	case .Wall,.Door,.Window:return .Room
	case .Light:return .Plant
	case .Wall_Paint:return .Paint
	case:return .Select
	}
}
editor_show_feedback :: proc(message:string,error:=false) {editor_state.feedback=message;editor_state.feedback_frames=240;editor_state.feedback_error=error}
editor_request_build_exit :: proc(g:^Game) {if level_document.dirty {editor_state.exit_confirm_visible=true;editor_state.shortcut_help_visible=false}else{g.editor_mode=.None;g.interactive_count=0};g.move_target_active=false}
editor_delete_command :: proc(doc:^Level_Document,command:Level_Command,label,noun:string)->bool {if !level_commit_transaction(doc,command,label) do return false;editor_show_feedback(fmt.tprintf("DELETED %s  ·  CTRL/CMD Z TO UNDO",noun));return true}
Editor_Box_Model :: struct {padding,border,gap:f32}
EDITOR_TOOL_RAIL_BOX := Editor_Box_Model{padding=10,border=1,gap=6}
EDITOR_TOOL_BUTTON_SIZE := Vec2{44,44}
EDITOR_TOOL_RAIL_ORIGIN := Vec2{8,76}

editor_vertical_stack_bounds :: proc(origin,item_size:Vec2,count:int,box:Editor_Box_Model)->Rect {
	content_height:=f32(max(count,0))*item_size.y+f32(max(count-1,0))*box.gap
	inset:=box.padding+box.border
	return {origin.x,origin.y,item_size.x+inset*2,content_height+inset*2}
}

editor_vertical_stack_item :: proc(bounds:Rect,index:int,item_size:Vec2,box:Editor_Box_Model)->Rect {
	inset:=box.padding+box.border
	return {bounds.x+inset,bounds.y+inset+f32(max(index,0))*(item_size.y+box.gap),item_size.x,item_size.y}
}

editor_tool_rail_rect :: proc()->Rect {return editor_vertical_stack_bounds(EDITOR_TOOL_RAIL_ORIGIN,EDITOR_TOOL_BUTTON_SIZE,len(BUILD_MODE_GRID),EDITOR_TOOL_RAIL_BOX)}
build_tool_grid_rect :: proc(index:int)->Rect {return editor_vertical_stack_item(editor_tool_rail_rect(),index,EDITOR_TOOL_BUTTON_SIZE,EDITOR_TOOL_RAIL_BOX)}
build_mode_for_tool :: proc(tool:Build_Tool)->Build_Tool {#partial switch tool {case .Room,.Wall,.Door,.Window:return .Room;case .Paint,.Wall_Paint:return .Paint;case .Plant,.Light:return .Plant};return tool}
editor_activate_build_mode :: proc(g:^Game,mode:Build_Tool) {
	g.build_tool=mode;current_kind,current_found:=catalog_entry_kind(editor_state.catalog_id);wanted:Catalog_Entry_Kind=mode==.Plant?.Object:mode==.Paint?.Material:current_kind
	if (mode==.Plant||mode==.Paint)&&(!current_found||current_kind!=wanted) {for entry in editor_catalog.entries do if entry.kind==wanted {editor_state.catalog_id=entry.id;break}}
	editor_show_feedback(fmt.tprintf("TOOL  ·  %s",editor_build_tool_name(mode)))
}
build_subtool_rect :: proc(index:int)->Rect {return {82+f32(index)*52,144,42,42}}
editor_opening_parameter_rect :: proc(index:int)->Rect {x:=[4]f32{78,180,224,326};return {x[clamp(index,0,3)],188,38,26}}
editor_paint_target_rect :: proc(index:int)->Rect {return {78+f32(index)*48,144,42,42}}
editor_paint_eyedropper_rect :: proc()->Rect {return {238,144,42,42}}
editor_foundation_kind_rect :: proc(index:int)->Rect {return {78+f32(index)*48,140,42,42}}
editor_foundation_mode_rect :: proc(index:int)->Rect {return {334+f32(index)*46,144,38,38}}
editor_foundation_measure_rect :: proc(index:int)->Rect {return {238+f32(index)*46,144,38,30}}
editor_terrain_mode_rect :: proc(index:int)->Rect {return {78+f32(index)*44,140,38,38}}
editor_terrain_parameter_rect :: proc(index:int)->Rect {x:=[4]f32{78,180,224,326};return {x[clamp(index,0,3)],184,38,28}}
editor_marker_kind_rect :: proc(index:int)->Rect {return {78+f32(index)*42,140,38,38}}
editor_marker_parameter_rect :: proc(index:int)->Rect {return {78+f32(index)*42+(index>=2?4:0),202,38,26}}
editor_light_kind_rect :: proc()->Rect {return {78,206,82,30}}
editor_light_parameter_rect :: proc(index:int)->Rect {return {168+f32(index)*46,206,38,30}}
editor_light_panel_rect :: proc()->Rect {return {74,194,328,78}}
editor_roof_style_rect :: proc()->Rect {return {78,144,82,30}}
editor_roof_parameter_rect :: proc(index:int)->Rect {width:=index==4?f32(46):f32(38);return {168+f32(index)*46,144,width,30}}
editor_roof_panel_rect :: proc()->Rect {return {74,132,418,78}}
editor_link_kind_rect :: proc()->Rect {return {78,144,92,30}}
editor_link_width_rect :: proc(index:int)->Rect {return {178+f32(index)*46,144,38,30}}
editor_water_height_rect :: proc(index:int)->Rect {return {78+f32(index)*62,144,54,30}}
editor_catalog_search_rect :: proc()->Rect {return {86,238,226,30}}
editor_catalog_search_clear_rect :: proc()->Rect {return {316,238,30,30}}
editor_catalog_card_rect :: proc(index:int)->Rect {return {86+f32(index%3)*88,276+f32(index/3)*80,80,70}}
editor_catalog_pin_rect :: proc(index:int)->Rect {card:=editor_catalog_card_rect(index);return {card.x+card.w-22,card.y+4,18,18}}
editor_catalog_empty_action_rect :: proc()->Rect {return {132,316,168,30}}
editor_selection_inspector_rect :: proc()->Rect {return {938,124,250,128}}
editor_roof_inspector_rect :: proc()->Rect {return {938,124,250,238}}
editor_roof_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Roof_Pitch?174:field==.Roof_Overhang?210:f32(246);return {952,y,222,30}}
editor_roof_edit_rect :: proc()->Rect {return {952,318,178,28}}
editor_roof_delete_rect :: proc()->Rect {return {1138,318,36,28}}
editor_begin_roof_edit :: proc(g:^Game,roof_id:string)->bool {index:=level_roof_index(&level_document,roof_id);if index<0 do return false;roof:=level_document.roofs[index];editor_state.roof_style=roof.style;editor_state.roof_pitch=roof.pitch;editor_state.roof_overhang=roof.overhang;editor_state.roof_ridge_angle=roof.ridge_angle;editor_state.roof_gutters=roof.gutters;g.build_tool=.Roof;editor_state.roof_hover={.Room,roof.room_id,-1};editor_state.roof_hover_active=true;editor_state.roof_preview=level_preview_transaction(&level_document,Level_Command{kind=.Set_Roof,entity_id=roof.id,material=roof.room_id,a={f32(roof.style),roof.ridge_angle},b={roof.overhang,roof.gutters?1:0},value=roof.pitch});return true}
editor_view_pick_selection :: proc(doc:^Level_Document,view:Editor_View_Mode,picked:Editor_Selection)->Editor_Selection {if view==.Roof&&picked.kind==.Room {roof_index:=level_roof_for_room(doc,picked.entity_id);if roof_index>=0 do return {.Roof,doc.roofs[roof_index].id,-1}};return picked}
editor_object_inspector_rect :: proc()->Rect {return {938,124,250,244}}
editor_opening_inspector_rect :: proc()->Rect {return {938,124,250,230}}
editor_room_inspector_rect :: proc()->Rect {return {938,124,250,210}}
editor_compact_inspector_step_rect :: proc(y:f32,direction:int)->Rect {return {direction<0?f32(946):f32(1142),y,38,30}}
editor_room_material_rect :: proc(walls:bool)->Rect {return {walls?f32(1066):f32(946),202,112,24}}
editor_room_roof_rect :: proc()->Rect {return {946,230,232,24}}
editor_inspector_step_rect :: proc(y:f32,direction:int)->Rect {return {direction<0?f32(920):f32(1138),y,38,30}}
editor_light_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Light_Range?248:field==.Light_Intensity?294:field==.Light_Height?340:field==.Light_Facing?386:f32(432);return {964,y,170,30}}
editor_light_duplicate_rect :: proc()->Rect {return {1098,136,34,28}}
editor_light_delete_rect :: proc()->Rect {return {1140,136,34,28}}
editor_light_color_rect :: proc(kind:Level_Light_Kind,index:int)->Rect {return {990+f32(index)*30,214,24,22}}
editor_light_current_color_rect :: proc()->Rect {return {958,214,24,22}}
editor_marker_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Marker_Radius?318:field==.Marker_Facing?354:f32(390);return {964,y,170,30}}
editor_marker_position_rect :: proc(field:Editor_Numeric_Field)->Rect {return {field==.Marker_X?f32(920):f32(1040),286,114,26}}
editor_marker_duplicate_rect :: proc()->Rect {return {1098,136,34,28}}
editor_marker_delete_rect :: proc()->Rect {return {1140,136,34,28}}
editor_marker_open_graph_rect :: proc()->Rect {return {920,438,254,28}}
editor_inspector_clear_rect :: proc(y:f32)->Rect {return {1096,y,38,30}}
editor_diagnostic_rect :: proc(index:int)->Rect {return {820,132+f32(max(index,0))*48,354,42}}
editor_view_menu_panel_rect :: proc()->Rect {return {308,52,218,184}}
editor_view_menu_rect :: proc(index:int)->Rect {i:=clamp(index,0,len(Editor_View_Mode)-1);return {314+f32(i/5)*104,58+f32(i%5)*34,100,30}}
editor_snap_rect :: proc()->Rect {return {1034,648,150,32}}
editor_shortcut_help_rect :: proc()->Rect {return {994,648,32,32}}
editor_multi_action_rect :: proc(index:int)->Rect {x:=[7]f32{514,556,598,660,730,772,814};width:=[7]f32{36,36,56,64,38,36,36};i:=clamp(index,0,6);return {x[i],608,width[i],28}}
FOLIAGE_COLOR_PALETTE := [6][4]u8{{255,255,255,255},{111,76,48,255},{67,43,30,255},{74,132,70,255},{130,169,74,255},{184,91,67,255}}
LIGHT_COLOR_PALETTE := [6][4]u8{{255,236,196,255},{255,255,255,255},{200,225,255,255},{255,184,112,255},{255,142,126,255},{154,184,255,255}}
ROOM_TINT_PALETTE := [6][4]u8{{255,255,255,255},{232,218,196,255},{207,177,142,255},{194,211,218,255},{179,204,177,255},{196,178,204,255}}
editor_room_tint_rect :: proc(walls:bool,index:int)->Rect {return {1018+f32(index)*25,walls?f32(294):f32(270),20,18}}
editor_object_color_rect :: proc(row,index:int)->Rect {return {1018+f32(index)*25,326+f32(row)*24,20,18}}
editor_object_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Object_Height?174:field==.Object_Angle?210:field==.Object_X?246:f32(282);return {990,y,144,30}}
editor_opening_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Opening_Position?198:field==.Opening_Width?234:field==.Opening_Height?270:f32(306);return {952,y,222,30}}
editor_compact_numeric_rect :: proc(field:Editor_Numeric_Field)->Rect {y:=field==.Room_Level?174:f32(198);return {990,y,144,30}}
editor_numeric_text :: proc()->string {return string(editor_state.numeric_buffer[:editor_state.numeric_count])}
editor_cancel_numeric_edit :: proc() {editor_state.numeric_field=.None;editor_state.numeric_count=0;editor_state.numeric_replace_on_input=false}
editor_begin_numeric_edit :: proc(field:Editor_Numeric_Field,value:f32) {
	editor_state.numeric_field=field;editor_state.numeric_count=0;editor_state.numeric_replace_on_input=true
	formatted:=field==.Object_Angle||field==.Roof_Pitch||field==.Roof_Ridge||field==.Light_Facing||field==.Light_Cone||field==.Marker_Facing?fmt.tprintf("%.0f",value):fmt.tprintf("%.2f",value)
	for byte in transmute([]u8)formatted {if editor_state.numeric_count>=len(editor_state.numeric_buffer) do break;editor_state.numeric_buffer[editor_state.numeric_count]=byte;editor_state.numeric_count+=1}
}
editor_append_numeric_char :: proc(value:u8)->bool {if editor_state.numeric_replace_on_input {editor_state.numeric_count=0;editor_state.numeric_replace_on_input=false};if editor_state.numeric_count>=len(editor_state.numeric_buffer) do return false;if value=='.' {for byte in editor_state.numeric_buffer[:editor_state.numeric_count] do if byte=='.' do return false};if value=='-'&&editor_state.numeric_count!=0 do return false;editor_state.numeric_buffer[editor_state.numeric_count]=value;editor_state.numeric_count+=1;return true}
editor_commit_numeric_edit :: proc()->bool {
	if editor_state.numeric_field==.None do return false
	value,ok:=strconv.parse_f32(editor_numeric_text());if !ok {editor_show_feedback("ENTER A VALID NUMBER",true);return false}
	if editor_state.selection_count!=1 {editor_cancel_numeric_edit();return false};selected:=editor_state.selection[0];command:=Level_Command{};label:="Edit value"
	if selected.kind==.Object {index:=level_object_index(&level_document,selected.entity_id);if index<0 {editor_cancel_numeric_edit();return false};object:=level_document.objects[index];#partial switch editor_state.numeric_field {case .Object_Height:command={kind=.Set_Object_Elevation,entity_id=object.id,value=clamp(value,-5,20)};label="Set object height";case .Object_Angle:command={kind=.Move_Object,entity_id=object.id,a=object.position,value=value};label="Set object angle";case .Object_X:command={kind=.Move_Object,entity_id=object.id,a={value,object.position.y},value=object.rotation};label="Set object X";case .Object_Y:command={kind=.Move_Object,entity_id=object.id,a={object.position.x,value},value=object.rotation};label="Set object Y";case:editor_cancel_numeric_edit();return false}}
	else if selected.kind==.Opening {index:=level_opening_index(&level_document,selected.entity_id);if index<0 {editor_cancel_numeric_edit();return false};opening:=level_document.openings[index];command={kind=.Set_Opening,entity_id=opening.id,material=opening.host_path,destination=door_material_name(opening.door_material),value=f32(opening.segment),b={f32(opening.kind),opening.width},c={opening.position,opening.height}};command.points[0]={opening.sill_height,f32(opening.window_style)};command.points[1]={opening.window_flipped?1:0,opening.window_hinge_right?1:0};#partial switch editor_state.numeric_field {case .Opening_Position:command.c.x=clamp(value,0,100)/100;label="Set opening position";case .Opening_Width:command.b.y=clamp(value,.4,6);label="Set opening width";case .Opening_Height:command.c.y=clamp(value,.4,4);label="Set opening height";case .Opening_Sill:if opening.kind!=.Window {editor_cancel_numeric_edit();return false};command.points[0].x=clamp(value,.2,2);label="Set window sill";case:editor_cancel_numeric_edit();return false}}
	else if selected.kind==.Room||selected.kind==.Edge||selected.kind==.Vertex {index:=level_room_index(&level_document,selected.entity_id);if index<0||editor_state.numeric_field!=.Room_Level {editor_cancel_numeric_edit();return false};room:=level_document.rooms[index];command={kind=.Set_Platform,entity_id=room.id,value=clamp(value,-5,10)};label="Set room level"}
	else if selected.kind==.Foundation {index:=level_foundation_index(&level_document,selected.entity_id);if index<0||editor_state.numeric_field!=.Foundation_Measure {editor_cancel_numeric_edit();return false};foundation:=level_document.foundations[index];minimum:=foundation.kind==.Basement?f32(1.8):foundation.kind==.Raised?f32(.25):f32(.1);maximum:=foundation.kind==.Basement?f32(6):foundation.kind==.Raised?f32(3):f32(1);measure:=clamp(value,minimum,maximum);command={kind=.Set_Foundation,entity_id=foundation.id,value=foundation.elevation,c={f32(foundation.kind),foundation.depth}};if foundation.kind==.Raised do command.value=measure;else do command.c.y=measure;label="Set foundation measure"}
	else if selected.kind==.Path {index:=level_path_index(&level_document,selected.entity_id);if index<0||editor_state.numeric_field!=.Path_Width {editor_cancel_numeric_edit();return false};path:=level_document.paths[index];minimum:=path.kind==.Wall?f32(.1):f32(.2);maximum:=path.kind==.Wall?f32(1):f32(8);command={kind=.Set_Path,entity_id=path.id,value=clamp(value,minimum,maximum)};label="Set path width"}
	else if selected.kind==.Water {index:=level_water_index(&level_document,selected.entity_id);if index<0||editor_state.numeric_field!=.Water_Surface {editor_cancel_numeric_edit();return false};water:=level_document.waters[index];command={kind=.Set_Water,entity_id=water.id,value=clamp(value,-5,5)};label="Set water surface"}
	else if selected.kind==.Vertical_Link {index:=level_vertical_link_index(&level_document,selected.entity_id);if index<0||editor_state.numeric_field!=.Link_Width {editor_cancel_numeric_edit();return false};link:=level_document.vertical_links[index];command={kind=.Set_Vertical_Link,entity_id=link.id,value=clamp(value,.6,3)};label="Set link width"}
	else if selected.kind==.Roof {index:=level_roof_index(&level_document,selected.entity_id);if index<0 {editor_cancel_numeric_edit();return false};roof:=level_document.roofs[index];command={kind=.Set_Roof,entity_id=roof.id,material=roof.room_id,a={f32(roof.style),roof.ridge_angle},b={roof.overhang,roof.gutters?1:0},value=roof.pitch};#partial switch editor_state.numeric_field {case .Roof_Pitch:command.value=clamp(value,1,75);label="Set roof pitch";case .Roof_Overhang:command.b.x=clamp(value,0,2);label="Set roof overhang";case .Roof_Ridge:command.a.y=value;label="Set roof ridge angle";case:editor_cancel_numeric_edit();return false}}
	else if selected.kind==.Light {index:=level_light_index(&level_document,selected.entity_id);if index<0 {editor_cancel_numeric_edit();return false};light:=level_document.lights[index];command={kind=.Set_Light,entity_id=light.id,a=light.position,b={light.range,light.intensity},c={light.elevation,f32(light.kind)},value=light.facing,color=light.color};command.points[0]={light.cone_angle,0};#partial switch editor_state.numeric_field {case .Light_Range:command.b.x=clamp(value,.5,40);label="Set light range";case .Light_Intensity:command.b.y=clamp(value,.1,100);label="Set light intensity";case .Light_Height:command.c.x=clamp(value,0,20);label="Set light height";case .Light_Facing:if light.kind==.Point {editor_cancel_numeric_edit();return false};command.value=value;label="Set light facing";case .Light_Cone:if light.kind!=.Spot {editor_cancel_numeric_edit();return false};command.points[0].x=clamp(value,5,160);label="Set spotlight cone";case:editor_cancel_numeric_edit();return false}}
	else if selected.kind==.Marker {index:=level_marker_index(&level_document,selected.entity_id);if index<0 {editor_cancel_numeric_edit();return false};marker:=level_document.markers[index];command=marker_edit_command(marker);#partial switch editor_state.numeric_field {case .Marker_X:command.a.x=clamp(value,0,f32(level_document.width));label="Set marker X";case .Marker_Y:command.a.y=clamp(value,0,f32(level_document.height));label="Set marker Y";case .Marker_Radius:command.b.x=clamp(value,.1,12);label="Set marker radius";case .Marker_Facing:command.b.y=value;label="Set marker facing";case .Marker_Height:if marker.kind!=.Camera {editor_cancel_numeric_edit();return false};command.c.x=clamp(value,.1,20);label="Set camera marker height";case:editor_cancel_numeric_edit();return false}}
	else {editor_cancel_numeric_edit();return false}
	if !level_commit_transaction(&level_document,command,label) {editor_show_feedback("VALUE BLOCKED BY PLACEMENT RULES",true);return false};editor_cancel_numeric_edit();editor_show_feedback("VALUE UPDATED  ·  CTRL/CMD Z TO UNDO");return true
}
editor_advance_numeric_edit :: proc(direction:int)->bool {
	current:=editor_state.numeric_field;if current==.None do return false
	if !editor_commit_numeric_edit() do return false
	if editor_state.selection_count!=1 do return true;selected:=editor_state.selection[0]
	if selected.kind==.Object {index:=level_object_index(&level_document,selected.entity_id);if index<0 do return true;object:=level_document.objects[index];fields:=[4]Editor_Numeric_Field{.Object_Height,.Object_Angle,.Object_X,.Object_Y};values:=[4]f32{object.elevation,object.rotation,object.position.x,object.position.y};current_index:=0;for field,i in fields do if field==current {current_index=i;break};next:=(current_index+(direction<0?-1:1)+len(fields))%len(fields);editor_begin_numeric_edit(fields[next],values[next]);return true}
	if selected.kind==.Opening {index:=level_opening_index(&level_document,selected.entity_id);if index<0 do return true;opening:=level_document.openings[index];fields:=[4]Editor_Numeric_Field{.Opening_Position,.Opening_Width,.Opening_Height,.Opening_Sill};values:=[4]f32{opening.position*100,opening.width,opening.height,opening.sill_height};count:=opening.kind==.Window?4:3;current_index:=0;for i in 0..<count do if fields[i]==current {current_index=i;break};next:=(current_index+(direction<0?-1:1)+count)%count;editor_begin_numeric_edit(fields[next],values[next]);return true}
	if selected.kind==.Roof {index:=level_roof_index(&level_document,selected.entity_id);if index<0 do return true;roof:=level_document.roofs[index];fields:=[3]Editor_Numeric_Field{.Roof_Pitch,.Roof_Overhang,.Roof_Ridge};values:=[3]f32{roof.pitch,roof.overhang,roof.ridge_angle};current_index:=0;for field,i in fields do if field==current {current_index=i;break};next:=(current_index+(direction<0?-1:1)+len(fields))%len(fields);editor_begin_numeric_edit(fields[next],values[next]);return true}
	if selected.kind==.Light {index:=level_light_index(&level_document,selected.entity_id);if index<0 do return true;light:=level_document.lights[index];fields:=[5]Editor_Numeric_Field{.Light_Range,.Light_Intensity,.Light_Height,.Light_Facing,.Light_Cone};values:=[5]f32{light.range,light.intensity,light.elevation,light.facing,light.cone_angle};count:=light.kind==.Spot?5:light.kind==.Area?4:3;current_index:=0;for i in 0..<count do if fields[i]==current {current_index=i;break};next:=(current_index+(direction<0?-1:1)+count)%count;editor_begin_numeric_edit(fields[next],values[next]);return true}
	if selected.kind==.Marker {index:=level_marker_index(&level_document,selected.entity_id);if index<0 do return true;marker:=level_document.markers[index];fields:=[5]Editor_Numeric_Field{.Marker_X,.Marker_Y,.Marker_Radius,.Marker_Facing,.Marker_Height};values:=[5]f32{marker.position.x,marker.position.y,marker.radius,marker.facing,marker.camera_height};count:=marker.kind==.Camera?5:4;current_index:=0;for i in 0..<count do if fields[i]==current {current_index=i;break};next:=(current_index+(direction<0?-1:1)+count)%count;editor_begin_numeric_edit(fields[next],values[next]);return true}
	return true
}
editor_selection_uses_compact_inspector :: proc(kind:Editor_Selection_Kind)->bool {return kind==.Room||kind==.Vertex||kind==.Edge||kind==.Opening||kind==.Object||kind==.Foundation||kind==.Path||kind==.Water||kind==.Vertical_Link||kind==.Roof}
editor_selection_toolbar_position :: proc(screen:Vec2)->Vec2 {return {clamp(screen.x-120,f32(90),f32(944)),clamp(screen.y+10,f32(94),f32(614))}}
gameplay_attributes_rect :: proc()->Rect {return {846,660,108,42}}
gameplay_notebook_rect :: proc()->Rect {return {958,660,108,42}}
gameplay_theory_rect :: proc()->Rect {return {1070,660,114,42}}
editor_status_hint_x :: proc(width:f32)->f32 {return clamp(547-width*.5,f32(82),f32(1018)-width)}
editor_segment_length :: proc(a,b:Vec2)->f32 {dx,dy:=b.x-a.x,b.y-a.y;return f32(math.sqrt(f64(dx*dx+dy*dy)))}
editor_polyline_length :: proc(points:[]Vec2)->f32 {total:f32=0;for i in 1..<len(points) do total+=editor_segment_length(points[i-1],points[i]);return total}
editor_polygon_preview_area :: proc(points:[]Vec2,cursor:Vec2)->f32 {
	if len(points)<2 do return 0
	preview:[33]Vec2
	count:=min(len(points),32)
	copy(preview[:count],points[:count])
	preview[count]=cursor
	return math.abs(level_polygon_area(preview[:count+1]))
}
editor_top_close_rect :: proc()->Rect {return {14,14,44,34}}
editor_top_save_rect :: proc()->Rect {return {68,14,82,34}}
editor_top_undo_rect :: proc()->Rect {return {160,14,68,34}}
editor_top_redo_rect :: proc()->Rect {return {236,14,68,34}}
editor_top_view_rect :: proc()->Rect {return {314,14,108,34}}
editor_top_validate_rect :: proc()->Rect {return {432,14,90,34}}
editor_top_story_down_rect :: proc()->Rect {return {780,11,40,40}}
editor_top_story_up_rect :: proc()->Rect {return {930,11,40,40}}
editor_top_story_height_down_rect :: proc()->Rect {return {822,11,28,40}}
editor_top_story_height_up_rect :: proc()->Rect {return {900,11,28,40}}
editor_top_recovery_rect :: proc()->Rect {return {980,14,102,34}}
editor_exit_save_rect :: proc()->Rect {return {330,438,166,38}}
editor_exit_autosave_rect :: proc()->Rect {return {516,438,238,38}}
editor_exit_cancel_rect :: proc()->Rect {return {774,438,96,38}}
editor_top_play_rect :: proc()->Rect {return {1090,14,92,34}}
editor_roof_gutters_rect :: proc()->Rect {return {406,144,82,30}}
editor_roof_apply_rect :: proc()->Rect {return {406,176,82,28}}
editor_apply_roof_preview :: proc()->bool {if !editor_state.roof_hover_active||editor_state.roof_preview.state==.Blocked do return false;room_id:=editor_state.roof_hover.entity_id;existing:=level_roof_for_room(&level_document,room_id);kind:=existing>=0?Level_Command_Kind.Set_Roof:.Create_Roof;id:=existing>=0?level_document.roofs[existing].id:"";if !level_commit_transaction(&level_document,Level_Command{kind=kind,entity_id=id,material=room_id,a={f32(editor_state.roof_style),editor_state.roof_ridge_angle},b={editor_state.roof_overhang,editor_state.roof_gutters?1:0},value=editor_state.roof_pitch},existing>=0?"Update roof":"Create roof") do return false;editor_show_feedback(existing>=0?"ROOF UPDATED  ·  CTRL/CMD Z TO UNDO":"ROOF CREATED  ·  CTRL/CMD Z TO UNDO");return true}
editor_submenu_block_rect :: proc()->Rect {return {74,128,426,90}}
editor_placement_rotated :: proc(rotation:f32,steps:int)->f32 {value:=rotation+f32(steps)*15;for value<0 do value+=360;for value>=360 do value-=360;return value}
editor_wheel_steps :: proc(delta:f32)->int {if delta==0 do return 0;steps:=int(math.round(f64(delta)));if steps==0 do steps=delta>0?1:-1;return clamp(steps,-6,6)}
editor_catalog_visible :: proc(tool:Build_Tool)->bool {return tool==.Plant||tool==.Paint||tool==.Wall_Paint}
editor_catalog_visible_count :: proc()->int {total:=catalog_match_count(&editor_state);return clamp(total-editor_state.catalog_page*9,0,9)}
editor_catalog_rows :: proc()->int {return max(1,(editor_catalog_visible_count()+2)/3)}
editor_catalog_footer_y :: proc()->f32 {return 274+f32(editor_catalog_rows())*80}
editor_catalog_panel_bottom :: proc(tool:Build_Tool)->f32 {footer:=editor_catalog_footer_y();return tool==.Plant?footer+76:footer+38}
editor_viewport_contains :: proc(point:Vec2,tool:Build_Tool)->bool {if point.x<=76||point.x>=1190||point.y<=62||point.y>=688 do return false;if editor_state.view_menu_visible&&contains(editor_view_menu_panel_rect(),point) do return false;if contains(editor_submenu_block_rect(),point)||tool==.Light&&contains(editor_light_panel_rect(),point) do return false;if point.x>=1028&&point.y>=640&&point.y<=684 do return false;if editor_state.selection_count>1&&point.x>=350&&point.x<=860&&point.y>=600&&point.y<=648 do return false;if editor_state.diagnostics_visible&&point.x>=806&&point.y>=70&&point.y<=610 do return false;if editor_state.selection_count>0&&(editor_state.selection[0].kind==.Marker||editor_state.selection[0].kind==.Light)&&point.x>=906&&point.y>=124&&point.y<=470 do return false;if editor_state.selection_count>0&&(editor_state.selection[0].kind==.Room||editor_state.selection[0].kind==.Edge||editor_state.selection[0].kind==.Vertex)&&contains(editor_room_inspector_rect(),point) do return false;if editor_state.selection_count>0&&editor_state.selection[0].kind==.Object&&contains(editor_object_inspector_rect(),point) do return false;if editor_state.selection_count>0&&editor_state.selection[0].kind==.Opening&&contains(editor_opening_inspector_rect(),point) do return false;if editor_state.selection_count>0&&editor_state.selection[0].kind==.Roof&&contains(editor_roof_inspector_rect(),point) do return false;if editor_state.selection_count>0&&editor_selection_uses_compact_inspector(editor_state.selection[0].kind)&&contains(editor_selection_inspector_rect(),point) do return false;if editor_catalog_visible(tool)&&point.x<370&&point.y>190&&point.y<editor_catalog_panel_bottom(tool) do return false;return true}
EDITOR_CAMERA_MIN_ZOOM :: f32(.2)
editor_camera_scale :: proc(g:^Game)->f32 {return g.camera_orbit_initialized?clamp(g.camera_zoom,EDITOR_CAMERA_MIN_ZOOM,2.5):1}
editor_mouse_ground :: proc(g:^Game,mouse:Vec2)->(x,y:f32,ok:bool) {if !g.top_down_camera do return gameplay_mouse_ground(g,mouse);half:=f32(math.tan(f64(math.PI/6)));aspect:=f32(WINDOW_WIDTH)/f32(WINDOW_HEIGHT);scale:=editor_camera_scale(g);nx:=mouse.x/f32(WINDOW_WIDTH)*2-1;ny:=1-mouse.y/f32(WINDOW_HEIGHT)*2;return g.camera_x+nx*27.5*scale*half*aspect,g.camera_y-ny*27.5*scale*half,true}
editor_world_screen :: proc(g:^Game,point:Vec2)->(screen:Vec2,visible:bool) {if !g.top_down_camera do return aerial_world_point_screen(g,point);half:=f32(math.tan(f64(math.PI/6)));aspect:=f32(WINDOW_WIDTH)/f32(WINDOW_HEIGHT);scale:=editor_camera_scale(g);ndc_x:=(point.x-g.camera_x)/(27.5*scale*half*aspect);ndc_y:=(g.camera_y-point.y)/(27.5*scale*half);return {(ndc_x+1)*.5*f32(WINDOW_WIDTH),(1-ndc_y)*.5*f32(WINDOW_HEIGHT)},ndc_x>=-1&&ndc_x<=1&&ndc_y>=-1&&ndc_y<=1}
editor_update_build_camera :: proc(g:^Game) {
	if !g.top_down_camera||editor_state.search_active||editor_state.numeric_field!=.None||editor_state.shortcut_help_visible||editor_state.exit_confirm_visible||editor_state.view_menu_visible do return
	control:=g.keys[.LCTRL]||g.keys[.RCTRL]||g.keys[.LGUI]||g.keys[.RGUI]
	if !control {dx:=f32(0);dy:=f32(0);if g.keys[.A] do dx-=1;if g.keys[.D] do dx+=1;if g.keys[.W] do dy-=1;if g.keys[.S] do dy+=1;if dx!=0||dy!=0 {length:=f32(math.sqrt(f64(dx*dx+dy*dy)));speed:=.18*editor_camera_scale(g);g.camera_x+=dx/length*speed;g.camera_y+=dy/length*speed;g.camera_initialized=true}}
	if g.input.mouse_wheel==0||g.build_tool==.Plant||!editor_viewport_contains(g.input.mouse_pos,g.build_tool) do return
	before_x,before_y,before_ok:=editor_mouse_ground(g,g.input.mouse_pos)
	g.camera_zoom=clamp(editor_camera_scale(g)-g.input.mouse_wheel*.1,EDITOR_CAMERA_MIN_ZOOM,2.5);g.camera_orbit_initialized=true
	after_x,after_y,after_ok:=editor_mouse_ground(g,g.input.mouse_pos)
	if before_ok&&after_ok {g.camera_x+=before_x-after_x;g.camera_y+=before_y-after_y}
}
editor_frame_zoom :: proc(minimum,maximum:Vec2,count:int)->f32 {if count<=1 do return .65;span_x,span_y:=maximum.x-minimum.x,maximum.y-minimum.y;return clamp(max(span_x/25,span_y/16)*1.2,.45,1.65)}
editor_frame_selection :: proc(g:^Game)->bool {
	if editor_state.selection_count<=0 {editor_show_feedback("SELECT SOMETHING TO FRAME",true);return false}
	minimum:=Vec2{1e30,1e30};maximum:=Vec2{-1e30,-1e30};count:=0
	for selection in editor_state.selection[:editor_state.selection_count] {position,ok:=level_selection_position(&level_document,selection);if !ok do continue;minimum.x=min(minimum.x,position.x);minimum.y=min(minimum.y,position.y);maximum.x=max(maximum.x,position.x);maximum.y=max(maximum.y,position.y);count+=1}
	if count==0 {editor_show_feedback("SELECTION CANNOT BE FRAMED",true);return false}
	g.camera_x=(minimum.x+maximum.x)*.5;g.camera_y=(minimum.y+maximum.y)*.5;g.camera_zoom=editor_frame_zoom(minimum,maximum,count);g.camera_initialized=true;g.camera_orbit_initialized=true;editor_show_feedback(count==1?"FRAMED SELECTION":"FRAMED SELECTION SET");return true
}

marker_edit_command :: proc(marker:Level_Marker)->Level_Command {return {kind=.Set_Marker,entity_id=marker.id,a=marker.position,b={marker.radius,marker.facing},c={marker.camera_height,f32(marker.kind)},material=marker.reference,destination=marker.destination,value=f32(marker.story)}}
editor_marker_name_rect :: proc()->Rect {return {918,153,210,26}}
editor_marker_name_text :: proc()->string {return string(editor_state.marker_name_buffer[:editor_state.marker_name_count])}
editor_begin_marker_name_edit :: proc(marker:Level_Marker) {editor_state.marker_name_active=true;editor_state.marker_name_count=min(len(marker.id),len(editor_state.marker_name_buffer));copy(editor_state.marker_name_buffer[:editor_state.marker_name_count],transmute([]u8)marker.id)}
editor_cancel_marker_name_edit :: proc() {editor_state.marker_name_active=false;editor_state.marker_name_count=0}
editor_commit_marker_name_edit :: proc()->bool {if !editor_state.marker_name_active||editor_state.selection_count!=1 do return false;old_id:=editor_state.selection[0].entity_id;index:=level_marker_index(&level_document,old_id);if index<0 do return false;new_id:=strings.trim_space(editor_marker_name_text());marker:=level_document.markers[index];command:=marker_edit_command(marker);command.interaction_prompt=new_id;if !level_commit_transaction(&level_document,command,"Rename marker") {editor_show_feedback("MARKER NAME MUST BE UNIQUE AND USE A-Z, 0-9, _",true);return false};graph_refs_changed:=false;for &node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera==old_id {if !graph_refs_changed do graph_history_push("Rename spatial marker");node.beat.camera=new_id;graph_refs_changed=true};if node.beat.actor_mark==old_id {if !graph_refs_changed do graph_history_push("Rename spatial marker");node.beat.actor_mark=new_id;graph_refs_changed=true}};if graph_refs_changed do graph_changed();editor_state.selection[0].entity_id=new_id;editor_cancel_marker_name_edit();editor_show_feedback("MARKER RENAMED  ·  GRAPH REFERENCES UPDATED");return true}
light_edit_command :: proc(light:Level_Light)->Level_Command {command:=Level_Command{kind=.Set_Light,entity_id=light.id,a=light.position,b={light.range,light.intensity},c={light.elevation,f32(light.kind)},value=light.facing,color=light.color};command.points[0]={light.cone_angle,0};return command}
marker_binding_next_in :: proc(doc:^Level_Document,g:^Game,marker:Level_Marker,direction:int)->string {
	options:[128]string;count:=0
	payload:=mystery_game_payload(g)
	#partial switch marker.kind {
	case .Character_Spawn:if g.story_project!=nil do for value in g.story_project.entities {if value.kind=="character"&&count<len(options) {options[count]=value.id;count+=1}}
	case .Interaction:if payload!=nil do for value in payload.pois {if count<len(options) {options[count]=value.entity_id;count+=1}}
	case .Clue:if payload!=nil do for value in payload.clues {if count<len(options) {options[count]=value.id;count+=1}}
	case .Trigger:if g.story_project!=nil do for value in g.story_project.events {if count<len(options) {options[count]=value.id;count+=1}}
	case .Transition:for value in doc.markers {if value.id!=marker.id&&count<len(options) {options[count]=value.id;count+=1}}
	case:return ""
	}
	if count==0 do return "";current:=-1;binding:=marker.kind==.Transition?marker.destination:marker.reference;for value,i in options[:count] do if value==binding do current=i;if current<0 do return direction<0?options[count-1]:options[0];return options[(current+direction+count)%count]
}
marker_binding_next :: proc(g:^Game,marker:Level_Marker,direction:int)->string {return marker_binding_next_in(&level_document,g,marker,direction)}
editor_open_marker_in_graph :: proc(g:^Game,marker:Level_Marker)->bool {
	for &node,i in graph_document.nodes[:graph_document.node_count] {
		matches:=node.beat.camera==marker.id||node.beat.actor_mark==marker.id
		if marker.kind==.Interaction&&marker.reference!="" do matches=matches||node.beat.interaction==marker.reference
		if marker.kind==.Trigger&&marker.reference!="" do matches=matches||node.beat.event_id==marker.reference
		if !matches do continue
		scene:=graph_scene_index(node.beat.scene);if scene<0 do continue
		graph_state.active_scene=scene;graph_state.view=.Graph;graph_select_only(i);_=graph_frame_nodes(true);g.editor_mode=.Graph;g.move_target_active=false;graph_feedback(fmt.tprintf("OPENED FROM BUILD  ·  %s",strings.to_upper(marker.id)));return true
	}
	editor_show_feedback("NO GRAPH NODE REFERENCES THIS MARKER",true);return false
}
editor_open_marker_in_mystery :: proc(g:^Game,marker:Level_Marker)->bool {
	payload:=mystery_payload(&active_story_project);if payload==nil||marker.reference=="" do return false
	kind:=Mystery_Authoring_Record_Kind.Clue;index:=-1
	#partial switch marker.kind {
	case .Character_Spawn:kind=.Character;index=mystery_authoring_character_index(payload,marker.reference)
	case .Interaction:kind=.POI;index=mystery_authoring_poi_index(payload,marker.reference)
	case .Clue:kind=.Clue;index=mystery_clue_index(payload,marker.reference)
	case .Trigger:kind=.Event;index=mystery_authoring_event_index(payload,marker.reference)
	case:return false
	}
	if index<0 do return false
	authoring_workspace.tab=.Mystery;authoring_workspace.selected_category=int(kind);authoring_workspace.selected_record=index;authoring_workspace.feedback=fmt.tprintf("OPENED FROM BUILD · %v · %s",kind,marker.reference);g.editor_mode=.None;g.screen=.Authoring;g.move_target_active=false;return true
}
editor_view_name :: proc(view:Editor_View_Mode)->string {#partial switch view {case .Top_Down:return "TOP DOWN";case .Active_Story:return "ACTIVE";case .Stories_Below:return "BELOW";case .Cutaway:return "CUTAWAY";case .Roof:return "ROOF";case .Collision:return "COLLISION";case .Navmesh:return "NAVMESH";case .Lighting:return "LIGHTING";case .Markers:return "MARKERS"};return "ISOMETRIC"}
editor_snap_name :: proc()->string {if editor_state.snap_suspended do return "NO SNAP  ALT";switch editor_state.snap_mode {case .Fine:return fmt.tprintf("SNAP %.2fm",level_document.fine_snap);case .Off:return "SNAP OFF";case .Construction:return fmt.tprintf("SNAP %.2fm",level_document.default_snap)};return "SNAP"}
editor_paint_command_kind :: proc(target:Paint_Target,whole_room:=false)->Level_Command_Kind {if whole_room||target==.Room do return .Paint_Room;if target==.Walls do return .Paint_Walls;return .Paint_Floor}
editor_room_sample_material :: proc(room:Level_Room,target:Paint_Target)->string {if target==.Walls do return room.wall_material;return room.floor_material}
editor_effective_terrain_mode :: proc(mode:Terrain_Brush_Mode,invert:bool)->Terrain_Brush_Mode {if !invert do return mode;if mode==.Raise do return .Lower;if mode==.Lower do return .Raise;return mode}
editor_set_view :: proc(g:^Game,view:Editor_View_Mode) {editor_state.view=view;#partial switch view {case .Isometric,.Cutaway,.Roof:g.top_down_camera=false;case:g.top_down_camera=true}}
editor_adjacent_view :: proc(view:Editor_View_Mode,direction:=1)->Editor_View_Mode {count:=len(Editor_View_Mode);return Editor_View_Mode((int(view)+direction%count+count)%count)}
editor_cycle_view :: proc(g:^Game,direction:=1) {next:=editor_adjacent_view(editor_state.view,direction);editor_set_view(g,next);editor_show_feedback(fmt.tprintf("VIEW  ·  %s",editor_view_name(next)))}
editor_reset_story_transients :: proc(g:^Game) {editor_cancel_object_rotation();editor_cancel_drag();editor_state.box_select_active=false;editor_state.terrain_stroke_active=false;editor_state.foundation_rectangle_active=false;editor_state.foundation_draw_count=0;editor_state.room_rectangle_active=false;editor_state.room_draw_count=0;editor_state.link_anchor_active=false;editor_state.path_draw_count=0;editor_state.water_draw_count=0;editor_state.opening_active=false;editor_state.roof_hover_active=false;editor_state.paint_hover_active=false;editor_state.placement_active=false;g.build_has_anchor=false;editor_state.wall_preview_active=false}
editor_switch_story :: proc(g:^Game,story:int)->bool {if story<0||story>=len(level_document.stories)||story==level_document.active_story do return false;editor_reset_story_transients(g);if !level_set_active_story(&level_document,story) do return false;editor_show_feedback(fmt.tprintf("ACTIVE STORY  ·  %s  ·  %s",strings.to_upper(level_document.stories[story].name),level_story_label(&level_document,story)));return true}
editor_focus_diagnostic :: proc(g:^Game,index:int)->bool {
	if index<0||index>=len(level_document.diagnostics) do return false;issue:=level_document.diagnostics[index];_=level_set_active_story(&level_document,issue.story);g.camera_x=issue.position.x;g.camera_y=issue.position.y;g.camera_initialized=true;selection:=level_selection_for_id(&level_document,issue.entity_id);if selection.kind!=.None {editor_state.selection[0]=selection;editor_state.selection_count=1}else do editor_state.selection_count=0;editor_state.diagnostic_selected=index;editor_state.diagnostics_visible=false;g.build_tool=.Select;message:=strings.to_upper(issue.message);if len(message)>48 do message=message[:48];editor_show_feedback(fmt.tprintf("ISSUE %d / %d  ·  %s",index+1,len(level_document.diagnostics),message),issue.severity==.Error);return true
}
editor_diagnostic_window_start :: proc(count,selected,capacity:int)->int {if count<=capacity do return 0;return clamp(max(selected,0)-capacity/2,0,count-capacity)}
editor_focus_adjacent_diagnostic :: proc(g:^Game,direction:int)->bool {count:=len(level_document.diagnostics);if count==0 {editor_show_feedback("NO LEVEL ISSUES");return false};current:=editor_state.diagnostic_selected;if current<0||current>=count do current=direction<0?0:-1;next:=(current+(direction<0?-1:1)+count)%count;return editor_focus_diagnostic(g,next)}
editor_begin_playtest :: proc(g:^Game)->bool {
	validation:=level_validate(&level_document);if !validation.ok {editor_state.diagnostics_visible=true;house_plan.validation=validation.message;return false}
	if g.story_project!=nil {registry:Story_Spatial_Registry;defer story_spatial_registry_destroy(&registry);assert(story_spatial_registry_register(&registry,story_level_space(&level_document)));_=story_spatial_registry_register(&registry,story_city_space());bindings:=story_spatial_validate_project(g.story_project,&registry);defer story_validation_destroy(&bindings);if !bindings.ok {editor_state.diagnostics_visible=true;house_plan.validation="Story spatial bindings are invalid for this level.";return false}}
	editor_playtest_snapshot={active=true,document=level_clone_document(&level_document),camera_x=g.camera_x,camera_y=g.camera_y,top_down=g.top_down_camera,selection=editor_state.selection,selection_count=editor_state.selection_count,tool=g.build_tool}
	spawn:=Vec2{g.player_x,g.player_y};facing:=g.player_angle;if editor_state.cursor_world_valid do spawn=editor_state.cursor_world
	if editor_state.selection_count>0&&editor_state.selection[0].kind==.Marker {index:=level_marker_index(&level_document,editor_state.selection[0].entity_id);if index>=0&&level_document.markers[index].kind==.Player_Spawn {marker:=level_document.markers[index];spawn=marker.position;facing=marker.facing*f32(math.PI)/180}}
	g.player_x=spawn.x;g.player_y=spawn.y;g.player_angle=facing;g.camera_x=spawn.x;g.camera_y=spawn.y;g.camera_initialized=true;g.top_down_camera=false;g.move_target_active=false;g.editor_mode=.None;g.interactive_count=0;editor_state.playtesting=true;editor_state.diagnostics_visible=false;return true
}
editor_end_playtest :: proc(g:^Game)->bool {
	if !editor_state.playtesting||!editor_playtest_snapshot.active do return false;level_document=level_clone_document(&editor_playtest_snapshot.document);level_project_runtime(&level_document);g.camera_x=editor_playtest_snapshot.camera_x;g.camera_y=editor_playtest_snapshot.camera_y;g.camera_initialized=true;g.top_down_camera=editor_playtest_snapshot.top_down;g.build_tool=editor_playtest_snapshot.tool;g.editor_mode=.Build;editor_state.selection=editor_playtest_snapshot.selection;editor_state.selection_count=editor_playtest_snapshot.selection_count;editor_state.playtesting=false;editor_playtest_snapshot.active=false;g.move_target_active=false;return true
}

editor_cancel_drag :: proc() {editor_state.drag_active=false;editor_state.drag_delta={};editor_state.drag_preview={.Valid,"READY",{}, {}}}
editor_cancel_object_rotation :: proc() {if editor_state.object_rotate_active {index:=level_object_index(&level_document,editor_state.object_rotate_id);if index>=0 do level_document.objects[index].rotation=editor_state.object_rotate_original};editor_state.object_rotate_active=false;editor_state.object_rotate_id=""}
editor_object_rotation_angle :: proc(center,cursor:Vec2,snap:bool)->f32 {angle:=f32(math.atan2(f64(cursor.y-center.y),f64(cursor.x-center.x)))*180/f32(math.PI);if snap do angle=f32(math.round(f64(angle/15)))*15;for angle<0 do angle+=360;for angle>=360 do angle-=360;return angle}
editor_object_rotate_handle_rect :: proc(g:^Game,angle:f32)->(Rect,bool) {if editor_state.selection_count!=1||editor_state.selection[0].kind!=.Object do return {},false;index:=level_object_index(&level_document,editor_state.selection[0].entity_id);if index<0 do return {},false;object:=level_document.objects[index];radians:=angle*f32(math.PI)/180;point:=Vec2{object.position.x+f32(math.cos(f64(radians)))*1.5,object.position.y+f32(math.sin(f64(radians)))*1.5};screen,visible:=editor_world_screen(g,point);return {screen.x-8,screen.y-8,16,16},visible}
editor_begin_object_rotation :: proc(g:^Game)->bool {if g.build_tool!=.Select||editor_state.drag_active||editor_state.object_rotate_active do return false;index:=editor_state.selection_count==1&&editor_state.selection[0].kind==.Object?level_object_index(&level_document,editor_state.selection[0].entity_id):-1;if index<0 do return false;object:=level_document.objects[index];handle,visible:=editor_object_rotate_handle_rect(g,object.rotation);if !visible||!contains(handle,g.input.mouse_pos) do return false;editor_state.object_rotate_active=true;editor_state.object_rotate_id=object.id;editor_state.object_rotate_original=object.rotation;editor_state.object_rotate_preview=object.rotation;return true}
editor_update_object_rotation :: proc(g:^Game) {if !editor_state.object_rotate_active do return;index:=level_object_index(&level_document,editor_state.object_rotate_id);if index<0 {editor_cancel_object_rotation();return};object:=&level_document.objects[index];if g.input.mouse_down {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.object_rotate_preview=editor_object_rotation_angle(object.position,{wx,wy},!(g.keys[.LALT]||g.keys[.RALT]));object.rotation=editor_state.object_rotate_preview}};if !g.input.mouse_released do return;preview:=editor_state.object_rotate_preview;original:=editor_state.object_rotate_original;position,id:=object.position,object.id;object.rotation=original;editor_state.object_rotate_active=false;editor_state.object_rotate_id="";if math.abs(preview-original)>.001 {if level_commit_transaction(&level_document,Level_Command{kind=.Move_Object,entity_id=id,a=position,value=preview},"Rotate object") do editor_show_feedback("OBJECT ROTATED  ·  CTRL/CMD Z TO UNDO")}}
editor_cancel_terrain_stroke :: proc() {editor_state.terrain_stroke_active=false;editor_state.terrain_stroke_start={};editor_state.terrain_stroke_current={}}

editor_selection_movable :: proc(selection:Editor_Selection)->bool {return selection.kind==.Room||selection.kind==.Object||selection.kind==.Light||selection.kind==.Marker||selection.kind==.Vertex||selection.kind==.Edge||selection.kind==.Opening||(selection.kind==.Foundation||selection.kind==.Path||selection.kind==.Water||selection.kind==.Vertical_Link)&&editor_control_point_index(selection)>=0}
editor_drag_commands :: proc(delta:Vec2,out:^[16]Level_Command)->int {count:=0;for selection in editor_state.selection[:editor_state.selection_count] {command,ok:=level_selection_move_command(&level_document,selection,delta);if ok&&count<len(out^) {out[count]=command;count+=1}};return count}
editor_align_selection :: proc(axis_x:bool)->bool {
	if editor_state.selection_count<2 do return false
	anchor,ok:=level_selection_position(&level_document,editor_state.selection[0]);if !ok do return false
	commands:[16]Level_Command;count:=0
	for selection in editor_state.selection[:editor_state.selection_count] {
		position,position_ok:=level_selection_position(&level_document,selection);if !position_ok {editor_show_feedback("ALIGNMENT REQUIRES MOVABLE ITEMS",true);return false}
		delta:=axis_x?Vec2{anchor.x-position.x,0}:Vec2{0,anchor.y-position.y}
		if math.abs(delta.x)<.0001&&math.abs(delta.y)<.0001 do continue
		command,move_ok:=level_selection_move_command(&level_document,selection,delta);if !move_ok {editor_show_feedback("ALIGNMENT REQUIRES MOVABLE ITEMS",true);return false}
		commands[count]=command;count+=1
	}
	if count==0 {editor_show_feedback(axis_x?"ALREADY ALIGNED ON X":"ALREADY ALIGNED ON Y");return true}
	if !level_commit_transactions(&level_document,commands[:count],axis_x?"Align selection on X":"Align selection on Y") {editor_show_feedback("ALIGNMENT BLOCKED BY PLACEMENT RULES",true);return false}
	editor_show_feedback(axis_x?"ALIGNED SELECTION ON X  ·  CTRL/CMD Z TO UNDO":"ALIGNED SELECTION ON Y  ·  CTRL/CMD Z TO UNDO");return true
}
editor_distribute_selection :: proc(axis_x:bool)->bool {
	count:=editor_state.selection_count;if count<3 do return false
	positions:[16]Vec2;order:[16]int
	for selection,i in editor_state.selection[:count] {position,ok:=level_selection_position(&level_document,selection);if !ok {editor_show_feedback("DISTRIBUTION REQUIRES MOVABLE ITEMS",true);return false};_,move_ok:=level_selection_move_command(&level_document,selection,{});if !move_ok {editor_show_feedback("DISTRIBUTION REQUIRES MOVABLE ITEMS",true);return false};positions[i]=position;order[i]=i}
	for i in 1..<count {candidate:=order[i];candidate_value:=axis_x?positions[candidate].x:positions[candidate].y;j:=i;for j>0 {previous:=order[j-1];previous_value:=axis_x?positions[previous].x:positions[previous].y;if previous_value<=candidate_value do break;order[j]=previous;j-=1};order[j]=candidate}
	first,last:=positions[order[0]],positions[order[count-1]];minimum:=axis_x?first.x:first.y;maximum:=axis_x?last.x:last.y;span:=maximum-minimum;if math.abs(span)<.0001 {editor_show_feedback(axis_x?"ALIGN X BEFORE DISTRIBUTING":"ALIGN Y BEFORE DISTRIBUTING",true);return false}
	commands:[16]Level_Command;command_count:=0
	for rank in 1..<count-1 {selection_index:=order[rank];target:=minimum+span*f32(rank)/f32(count-1);position:=positions[selection_index];delta:=axis_x?Vec2{target-position.x,0}:Vec2{0,target-position.y};if math.abs(delta.x)<.0001&&math.abs(delta.y)<.0001 do continue;command,ok:=level_selection_move_command(&level_document,editor_state.selection[selection_index],delta);if !ok do return false;commands[command_count]=command;command_count+=1}
	if command_count==0 {editor_show_feedback(axis_x?"ALREADY SPACED EVENLY ON X":"ALREADY SPACED EVENLY ON Y");return true}
	if !level_commit_transactions(&level_document,commands[:command_count],axis_x?"Distribute selection on X":"Distribute selection on Y") {editor_show_feedback("DISTRIBUTION BLOCKED BY PLACEMENT RULES",true);return false};editor_show_feedback(axis_x?"DISTRIBUTED EVENLY ON X  ·  CTRL/CMD Z TO UNDO":"DISTRIBUTED EVENLY ON Y  ·  CTRL/CMD Z TO UNDO");return true
}
editor_select_pointer :: proc(g:^Game,picked:Editor_Selection,point:Vec2) {
	additive:=g.keys[.LSHIFT]||g.keys[.RSHIFT]
	if picked.kind==.Terrain {if !additive do editor_state.selection_count=0;editor_state.box_select_active=true;editor_state.box_select_additive=additive;editor_state.box_select_start=point;editor_state.box_select_current=point;return}
	if additive {_=editor_selection_toggle(&editor_state,picked);return}
	if editor_selection_index(&editor_state,picked)<0||editor_state.selection_count<=1 {editor_state.selection[0]=picked;editor_state.selection_count=1}
	if editor_selection_movable(picked) {editor_state.drag_active=true;editor_state.drag_selection=picked;editor_state.drag_origin_world=point;editor_state.drag_current_world=point;editor_state.drag_delta={};editor_state.drag_preview={.Valid,"READY",point,point}}
}
editor_update_box_selection :: proc(g:^Game) {
	if !editor_state.box_select_active do return;if g.input.mouse_down {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok do editor_state.box_select_current={wx,wy}};if !g.input.mouse_released do return;found:[16]Editor_Selection;count:=level_select_box(&level_document,editor_state.box_select_start,editor_state.box_select_current,&found);if !editor_state.box_select_additive do editor_state.selection_count=0;for selection in found[:count] do if editor_selection_index(&editor_state,selection)<0&&editor_state.selection_count<len(editor_state.selection) {editor_state.selection[editor_state.selection_count]=selection;editor_state.selection_count+=1};editor_state.box_select_active=false
}
editor_copy_selection :: proc()->bool {if editor_state.selection_count<=0 do return false;editor_clipboard={active=true,document=level_clone_document(&level_document),selection=editor_state.selection,selection_count=editor_state.selection_count};editor_show_feedback(editor_state.selection_count==1?"COPIED 1 ITEM":fmt.tprintf("COPIED %d ITEMS",editor_state.selection_count));return true}
editor_paste_selection :: proc(offset:Vec2={.5,.5},verb:="PASTED")->bool {
	if !editor_clipboard.active||editor_clipboard.selection_count<=0 do return false;commands:[16]Level_Command;next_selection:[16]Editor_Selection;count:=0
	for selection,i in editor_clipboard.selection[:editor_clipboard.selection_count] {if count>=len(commands) do break;id:=fmt.tprintf("paste_%d_%d",level_document.revision+1,i);command:=Level_Command{};next:=Editor_Selection{}
		#partial switch selection.kind {
		case .Room:if level_room_index(&level_document,selection.entity_id)<0 do continue;command={kind=.Duplicate_Room,entity_id=selection.entity_id,a=offset,material=id};next={.Room,id,-1}
		case .Object:if level_object_index(&level_document,selection.entity_id)<0 do continue;command={kind=.Duplicate_Object,entity_id=selection.entity_id,a=offset,material=id};next={.Object,id,-1}
		case .Light:index:=level_light_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;light:=editor_clipboard.document.lights[index];command={kind=.Add_Light,entity_id=id,a={light.position.x+offset.x,light.position.y+offset.y},b={light.range,light.intensity},c={light.elevation,f32(light.kind)},value=f32(level_document.active_story),color=light.color};command.points[0]={light.cone_angle,light.facing};next={.Light,id,-1}
		case .Marker:index:=level_marker_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;marker:=editor_clipboard.document.markers[index];command={kind=.Add_Marker,entity_id=id,a={marker.position.x+offset.x,marker.position.y+offset.y},b={marker.radius,marker.facing},c={marker.camera_height,f32(marker.kind)},material=marker.reference,destination=marker.destination,value=f32(level_document.active_story)};next={.Marker,id,-1}
		case .Path:index:=level_path_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;path:=editor_clipboard.document.paths[index];command={kind=.Add_Path,entity_id=id,material=path.material,c={f32(path.kind),0},value=path.width,point_count=min(len(path.points),32)};for p,j in path.points {if j>=len(command.points) do break;command.points[j]={p.x+offset.x,p.y+offset.y}};next={.Path,id,-1}
		case .Water:index:=level_water_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;water:=editor_clipboard.document.waters[index];command={kind=.Create_Water,entity_id=id,value=water.elevation,point_count=min(len(water.points),32)};for p,j in water.points {if j>=len(command.points) do break;command.points[j]={p.x+offset.x,p.y+offset.y}};next={.Water,id,-1}
		case .Roof:index:=level_roof_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;roof:=editor_clipboard.document.roofs[index];command={kind=.Create_Roof,entity_id=id,material=roof.room_id,a={f32(roof.style),roof.ridge_angle},b={roof.overhang,0},value=roof.pitch};next={.Roof,id,-1}
		case .Vertical_Link:index:=level_vertical_link_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;link:=editor_clipboard.document.vertical_links[index];command={kind=.Create_Vertical_Link,entity_id=id,a={link.start.x+offset.x,link.start.y+offset.y},b={link.finish.x+offset.x,link.finish.y+offset.y},c={f32(link.kind),0},value=link.width};next={.Vertical_Link,id,-1}
		case .Opening:index:=level_opening_index(&editor_clipboard.document,selection.entity_id);if index<0 do continue;opening:=editor_clipboard.document.openings[index];command={kind=.Add_Opening,entity_id=id,material=opening.host_path,destination=door_material_name(opening.door_material),value=f32(opening.segment),b={f32(opening.kind),opening.width},c={opening.position,opening.height}};command.points[0]={opening.sill_height,f32(opening.window_style)};command.points[1]={opening.window_flipped?1:0,opening.window_hinge_right?1:0};next={.Opening,id,opening.segment}
		case:continue
		};commands[count]=command;next_selection[count]=next;count+=1}
	if count==0||!level_commit_transactions(&level_document,commands[:count],fmt.tprintf("%s %s",verb,count>1?"selection set":"selection")) do return false;editor_state.selection_count=count;copy(editor_state.selection[:],next_selection[:count]);editor_show_feedback(fmt.tprintf("%s %d ITEM%s  ·  CTRL/CMD Z TO UNDO",verb,count,count==1?"":"S"));return true
}
editor_delete_selection_set :: proc()->bool {if editor_state.selection_count<=0 do return false;for selection in editor_state.selection[:editor_state.selection_count] {if editor_control_point_index(selection)>=0&&(selection.kind==.Foundation||selection.kind==.Path||selection.kind==.Water||selection.kind==.Vertical_Link) {editor_show_feedback("SELECT THE PARENT SHAPE TO DELETE IT",true);return false}};commands:[16]Level_Command;count:=0;for selection in editor_state.selection[:editor_state.selection_count] {command:=Level_Command{};#partial switch selection.kind {case .Room:command={kind=.Delete_Room,entity_id=selection.entity_id};case .Object:command={kind=.Delete_Object,entity_id=selection.entity_id,material="object"};case .Light:command={kind=.Delete_Light,entity_id=selection.entity_id};case .Path:command={kind=.Delete_Object,entity_id=selection.entity_id,material="path"};case .Opening:command={kind=.Delete_Opening,entity_id=selection.entity_id};case .Roof:command={kind=.Delete_Roof,entity_id=selection.entity_id};case .Vertical_Link:command={kind=.Delete_Vertical_Link,entity_id=selection.entity_id};case .Water:command={kind=.Delete_Water,entity_id=selection.entity_id};case .Marker:command={kind=.Delete_Marker,entity_id=selection.entity_id};case:continue};commands[count]=command;count+=1};if count==0||!level_commit_transactions(&level_document,commands[:count],count>1?"Delete selection set":"Delete selection") do return false;editor_state.selection_count=0;editor_show_feedback(count>1?fmt.tprintf("DELETED %d ITEMS  ·  CTRL/CMD Z TO UNDO",count):"DELETED ITEM  ·  CTRL/CMD Z TO UNDO");return true}

editor_update_drag :: proc(g:^Game) {
	if !editor_state.drag_active do return
	if g.input.mouse_down {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok {editor_state.drag_current_world={wx,wy};editor_state.drag_delta=level_snap_delta(&level_document,{wx-editor_state.drag_origin_world.x,wy-editor_state.drag_origin_world.y});commands:[16]Level_Command;count:=editor_drag_commands(editor_state.drag_delta,&commands);editor_state.drag_preview={.Valid,"READY",{}, {}};for command in commands[:count] {preview:=level_preview_transaction(&level_document,command);if preview.state==.Blocked {editor_state.drag_preview=preview;break}else if preview.state==.Warning do editor_state.drag_preview=preview}}}
	if !g.input.mouse_released do return
	if editor_state.drag_preview.state!=.Blocked&&(editor_state.drag_delta.x!=0||editor_state.drag_delta.y!=0) {commands:[16]Level_Command;count:=editor_drag_commands(editor_state.drag_delta,&commands);if count>0 do _=level_commit_transactions(&level_document,commands[:count],count>1?"Drag selection set":"Drag selection")}
	editor_cancel_drag()
}

editor_update_terrain_stroke :: proc(g:^Game) {
	if !editor_state.terrain_stroke_active do return
	if g.input.mouse_down {wx,wy,ok:=editor_mouse_ground(g,g.input.mouse_pos);if ok do editor_state.terrain_stroke_current={wx,wy}}
	if !g.input.mouse_released do return
	mode:=editor_effective_terrain_mode(editor_state.terrain_mode,g.keys[.LCTRL]||g.keys[.RCTRL]);command:=Level_Command{kind=.Sculpt_Terrain,a=editor_state.terrain_stroke_start,b=editor_state.terrain_stroke_current,c={editor_state.terrain_strength,editor_state.terrain_sample},value=editor_state.terrain_radius,brush=mode};preview:=level_preview_transaction(&level_document,command);if preview.state!=.Blocked do _=level_commit_transaction(&level_document,command,fmt.tprintf("%v terrain stroke",mode));editor_cancel_terrain_stroke()
}
Drag_State :: struct {kind:Drag_Kind,index,hover_index:int,start,offset:Vec2,active:bool,origin_screen:Screen}
Guidance_Mode :: enum { Full, Adaptive, Minimal }
Tutorial_Capability :: enum { Move, Look, Contextual_Interaction, Travel, Examine, Converse, Notebook, Case_Sense, Board_Place, Board_Test, Briefing }
Tutorial_Progress :: struct {
	completed:[Tutorial_Capability]bool,
	guidance:Guidance_Mode,
	case_sense_reminder_dismissed:bool,
}

tutorial_complete :: proc(g:^Game,capability:Tutorial_Capability) {g.tutorial.completed[capability]=true}
tutorial_completed :: proc(g:^Game,capability:Tutorial_Capability)->bool {return g.tutorial.completed[capability]}
guidance_mode_label :: proc(mode:Guidance_Mode)->string {switch mode {case .Full:return "FULL";case .Adaptive:return "ADAPTIVE";case .Minimal:return "MINIMAL"};return "ADAPTIVE"}
tutorial_capability_id :: proc(capability:Tutorial_Capability)->string {switch capability {case .Move:return "move";case .Look:return "look";case .Contextual_Interaction:return "contextual_interaction";case .Travel:return "travel";case .Examine:return "examine";case .Converse:return "converse";case .Notebook:return "notebook";case .Case_Sense:return "case_sense";case .Board_Place:return "board_place";case .Board_Test:return "board_test";case .Briefing:return "briefing"};return ""}
tutorial_lesson_prompt :: proc(g:^Game,capability:Tutorial_Capability,fallback:string)->string {id:=tutorial_capability_id(capability);payload:=mystery_game_payload(g);if payload!=nil {for lesson in payload.tutorial_lessons do if lesson.capability==id&&lesson.prompt!="" do return lesson.prompt};return fallback}

game_story_milestone :: proc(g:^Game,id:string)->bool {
	if g.story_project==nil||g.story_state==nil||id=="" do return false
	indices:[dynamic]int;defer delete(indices)
	for effect,index in g.story_project.effects do if effect.kind==.Set_Objective&&effect.content_id==id do append(&indices,index)
	if len(indices)==0 do return false
	result:=story_apply_transaction(g.story_project,g.story_state,indices[:],g.spatial_service)
	return result.ok
}
Game :: struct {
	running,window_resized,character_studio,controller_disconnected,input_resume_blocked: bool, input: Input_State, keys: #sparse [sdl.Scancode]bool,
	pad_buttons: #sparse [sdl.GamepadButton]bool, pad_left_x,pad_left_y,pad_right_x,pad_right_y,pad_left_trigger,pad_right_trigger:f32,
	gamepad:^sdl.Gamepad, gamepad_type:sdl.GamepadType, active_device:Input_Device, axis_nav_x,axis_nav_y:i8,
	mouse_device_motion:Vec2,
	vehicle_haptics_active,vehicle_haptics_failed:bool,
	audio_stream,vehicle_audio_stream:^sdl.AudioStream,
	vehicle_audio_phase,vehicle_audio_frequency,vehicle_audio_gain,vehicle_audio_tire_phase_a,vehicle_audio_tire_phase_b,vehicle_audio_tire_frequency_a,vehicle_audio_tire_frequency_b,vehicle_audio_tire_gain,vehicle_audio_rough_phase,vehicle_audio_rough_gain:f32,
	vehicle_camera_reverse_blend:f32,
	vehicle_camera_follow_distance:f32,
	vehicle_impact_sound_cooldown:f32,
	vehicle_skid_marks:[VEHICLE_SKID_CAPACITY]Vehicle_Skid_Mark,
	vehicle_skid_next:int,
	vehicle_skid_emit_distance:f32,
	sounds:[Sound_Cue][dynamic]f32,
	gui: ui.Gui_Context,
	story_project:^Story_Project,
	story_state:^Story_State,
	compiled_story:^Compiled_Story,
	story_runtime:^Story_Runtime,
	mystery_state:^Mystery_State,
	spatial_service:^Story_Spatial_Service,
	screen: Screen, phase: Case_Phase, location, ap, selected_section, introduction_step: int,
	scene_transition_active:bool, scene_transition_style:Scene_Transition_Style, scene_transition_elapsed:f32, scene_transition_sequence:int, scene_transition_target:Screen,
	map_loading_active:bool, map_loading_target:Screen, map_loading_progress,map_loading_elapsed:f32, map_loading_stage:int,
	case_loading_active:bool, case_loading_index:int, case_loading_title:string,
	map_ready:[2]bool,
	run_seed:u64, game_over_reason:string,
	menu_return, pause_return: Screen, pause_feedback:string, mute: bool, aa_mode:Anti_Aliasing_Mode, lighting_quality:Lighting_Quality, guidance_mode:Guidance_Mode, aa_restart_required:bool,
	tutorial:Tutorial_Progress,
	focus_screen: Screen, focus_screen_initialized: bool,
	notebook_return_focus, menu_detail_return_focus: ui.Gui_Id,
	menu_overlay_focus_pending: bool, menu_overlay_pending_screen: Screen, menu_overlay_pending_focus: ui.Gui_Id,
	theory: Theory, seed: u64, persist_seed:bool, log: [4]string, result: Outcome, active_ending:int,
	board_sockets:[5][3]bool, board_clear_confirm:bool, board_inspect_socket,board_view:int,
	board_last_section, board_last_socket: int, board_snap_started: f32, board_feedback:string,
	recreate_section, recreate_runs: int, recreate_started: f32,
	workbench_events:[9]Workbench_Event, workbench_event_count, workbench_selected:int,
	workbench_result:Reconstruction_Result, workbench_supported:[16]bool,
	workbench_field:int, workbench_feedback:string, workbench_test_current:bool,
	drag:Drag_State,
	workbench_undo,workbench_redo:[32]Workbench_Snapshot,workbench_undo_count,workbench_redo_count:int,
	question_selected, question_slot, knowledge_cursor, active_demonstration:int,
	interaction_step:int, interaction_active, interaction_mismatch:bool,
	question_feedback:string,
	pending_dialogue_approach:int, dialogue_response:string, dialogue_text_started:f32,
	story_presentation:Story_Presentation_State,
	conversation_transcript:[256]Dialogue_Transcript_Entry,
	conversation_transcript_count:int,
	location_result:string,
	service_closet_entered, desk_key_found, desk_open:bool,
	memo_stub_found, burned_note_found, appointment_note_joined:bool,
	overtime_clue_plus_one, overtime_lead_plus_one: int,
	pending_clue, case_sense_level: int, case_sense_hold_started,case_sense_hint_until:f32, case_sense_hold_active:bool, check_preview, check_disposition_delta: int, check_result: Check_Result, check_roll_started:f32, check_done, check_from_dialogue, check_result_cue_played: bool,
	shutter_view, shutter_time: int,
	shutter_open, shutter_operated, shutter_sightline_failed, shutter_thread_found, shutter_demonstrating: bool,
	shutter_position, shutter_target: f32,
	shutter_feedback: string,
	study_rug_lifted, study_statuette_held, study_wound_matched, study_seam_found, study_oil_found, cloth_acquired: bool,
	diagnostics: Theory_Diagnostics, timeline_order: [3]int,
	end_confirm, show_canonical, investigation_locked, threshold_four_spent, threshold_eight_spent: bool,
	case_pacing_mask:u8, case_pacing_times:[6]f32,
	attribute_selected, notebook_tab, history_count, reveal_act, finale_demo_step: int, menu_detail_return, notebook_return: Screen, history: [64]string,
	notebook_scroll, notebook_scroll_target, notebook_scroll_max:f32,
	quest_observed:[64]Story_Objective_Status, quest_observed_count:int,
	quest_transition_ids:[dynamic]string, quest_transition_status:[dynamic]Story_Objective_Status,
	quest_transition_started:f32, quest_tracker_initialized:bool,
	quest_completion_pending:bool, quest_completion_started:f32,
	player_x, player_y, player_angle, first_person_pitch: f32,
	player_elevation: f32,
	player_velocity_x, player_velocity_y: f32,
	player_is_walking: bool,
	player_walk_speed: f32,
	camera_x, camera_y: f32,
	camera_initialized, top_down_camera, build_key_latch: bool,
	editor_mode:Editor_Mode,
	camera_orbit, camera_zoom:f32,
	camera_orbit_initialized, first_person_camera:bool,
	camera_pose_override:bool,
	camera_eye_override, camera_target_override:Vec3,
	capture_hide_roofs:bool,
	catalog_bake_index:int,
	catalog_thumbnail_process:os.Process,
	catalog_thumbnail_baking, catalog_thumbnail_autoload_attempted:bool,
	catalog_thumbnail_status:string,
	build_surface:Room_Surface,build_tool:Build_Tool,build_anchor:Vec2,build_has_anchor:bool,
	move_target_x, move_target_y: f32,
	move_target_active: bool,
	nav_path: [256]Vec2, nav_path_count, nav_path_index: int,
	environment_blend,cutaway_transition:f32,
	capture_cutaway_override:bool,
	capture_cutaway_amount:f32,
	wall_view:House_Wall_View,wall_cutaways:[HOUSE_WALL_SECTION_CAPACITY]f32,
	camera_reverse:bool,
	pending_world_interaction,pending_interactive: int,
	interactives:[64]Runtime_Interactive,interactive_count,hover_interactive,near_interactive,auto_door:int,interaction_feedback:string,
	hover_entity, near_entity, dialogue_entity, dialogue_node, dialogue_ledger_scroll, dialogue_choice_page: int,
	context_ui:Context_State,
	dialogue_interaction:Dialogue_Interaction_State,
	city_x, city_y, city_angle: f32,
	city_return_x,city_return_y,city_return_angle:f32,
	city_velocity_x, city_velocity_y, city_camera_x, city_camera_y: f32,
	city_camera_initialized: bool,
	near_landmark: int,
	vehicles: [dynamic]Vehicle_State,
	city_furniture: [dynamic]City_Furniture_State,
	driving_vehicle, near_vehicle: int,
	vehicles_initialized, city_furniture_initialized: bool,
	animation_time: f32,
	player_animation: Character_Animation,
	character_animations:[4]Character_Animation,
}

catalog_thumbnail_start :: proc(g:^Game,missing_only:bool)->bool {
	if g.catalog_thumbnail_baking do return false
	command:[66]string;count:=0;command[count]="./tools/bake_catalog_thumbnails.sh";count+=1
	if missing_only {
		for entry in editor_catalog.entries {
			if entry.kind!=.Object||!entry.valid||(!entry.thumbnail_missing&&!entry.thumbnail_stale)||count>=len(command) do continue
			command[count]=entry.id;count+=1
		}
	} else {
		entry,found:=catalog_object_entry(editor_state.catalog_id);if !found||!entry.valid {g.catalog_thumbnail_status="SELECT A VALID MODEL";return false}
		command[count]=entry.id;count+=1
	}
	if count==1 {g.catalog_thumbnail_status="ALL PREVIEWS CURRENT";return false}
	environment,_:=os.environ(context.temp_allocator);process,err:=os.process_start({working_dir=".",command=command[:count],env=environment});if err!=nil {g.catalog_thumbnail_status="THUMBNAIL RENDER FAILED";return false}
	g.catalog_thumbnail_process=process;g.catalog_thumbnail_baking=true;g.catalog_thumbnail_status=missing_only?fmt.tprintf("UPDATING %d PREVIEWS…",count-1):"RENDERING PREVIEW…";return true
}

editor_update_catalog_ui :: proc(g:^Game) {
	// Preview cards are a cache: populate missing or stale entries the first time
	// the object catalog is opened instead of requiring a separate bake step.
	if g.build_tool==.Plant&&!g.catalog_thumbnail_autoload_attempted {
		g.catalog_thumbnail_autoload_attempted=true
		_=catalog_thumbnail_start(g,true)
	}
	categories:=[4]string{"all",g.build_tool==.Plant?"objects":"materials","recent","pinned"}
	for category,i in categories do if button(g,{86+f32(i)*65,202,60,28}) {editor_state.catalog_category=category;editor_state.catalog_page=0}
	if button(g,editor_catalog_search_rect()) do editor_state.search_active=true
	if button(g,editor_catalog_search_clear_rect()) do catalog_clear_search(&editor_state)
	catalog_clamp_page(&editor_state);shown,matched:=0,0;start:=editor_state.catalog_page*9
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry,&editor_state) do continue
		if matched>=start&&shown<9 {pin_clicked:=button(g,editor_catalog_pin_rect(shown));if pin_clicked {_=catalog_toggle_pinned(&editor_state,entry.id);if editor_state.catalog_category=="pinned" do editor_state.catalog_page=0}else if button(g,editor_catalog_card_rect(shown))&&catalog_entry_selectable(entry) {editor_state.catalog_id=entry.id;editor_state.paint_eyedropper=false;catalog_record_recent(&editor_state,entry.id);if entry.kind==.Object {g.build_tool=.Plant;editor_state.placement_rotation=0;editor_state.placement_elevation=entry.default_elevation}else do g.build_tool=.Paint};shown+=1}
		matched+=1
	}
	if matched==0&&editor_state.search_count>0&&button(g,editor_catalog_empty_action_rect()) do catalog_clear_search(&editor_state)
	pages:=catalog_page_count(&editor_state);footer:=editor_catalog_footer_y()
	if button(g,{86,footer,38,30})&&editor_state.catalog_page>0 do editor_state.catalog_page-=1
	if button(g,{308,footer,38,30})&&editor_state.catalog_page+1<pages do editor_state.catalog_page+=1
	if contains(Rect{74,194,284,editor_catalog_panel_bottom(g.build_tool)-194},g.input.mouse_pos)&&g.input.mouse_wheel!=0 do editor_state.catalog_page=clamp(editor_state.catalog_page-editor_wheel_steps(g.input.mouse_wheel),0,pages-1)
	if g.build_tool==.Plant&&!g.catalog_thumbnail_baking {actions_y:=footer+38;if button(g,{86,actions_y,126,30}) do _=catalog_thumbnail_start(g,false);if button(g,{220,actions_y,126,30}) do _=catalog_thumbnail_start(g,true)}
}
Editor_Playtest_Snapshot :: struct {active:bool,document:Level_Document,camera_x,camera_y:f32,top_down:bool,selection:[16]Editor_Selection,selection_count:int,tool:Build_Tool}
editor_playtest_snapshot:Editor_Playtest_Snapshot
Editor_Clipboard :: struct {active:bool,document:Level_Document,selection:[16]Editor_Selection,selection_count:int}
editor_clipboard:Editor_Clipboard

WORKBENCH_ACTORS := [5]string{"someone","edgar","miriam","daniel","elsie"}
WORKBENCH_ACTIONS := [14]string{"move","enter","leave","follow","motive","strike","clean","open_shutter","close_shutter","move_body","stage","lie","deny","observe"}
WORKBENCH_PROPS := [9]string{"unknown object","none","statuette","cloth_oil","ledger","cane","body","shutter_crank","miriam"}
WORKBENCH_ROOMS := [5]string{"unknown place","dining_room","hall","study","garden"}
OBSERVATION_TEXT := [12]string{
	"Diluted blood lies beneath the shifted study rug. A wrist-width scuff in the floor varnish holds tiny watch-glass fragments.",
	"The statuette base matches Edgar's wound profile.",
	"Blood remains trapped inside the statuette's base seam.",
	"Lamp oil residue coats the unnaturally clean bronze.",
	"The shutter automatically closes at 8:15.",
	"The shutter crank can only be reached from inside the study.",
	"Closed slats completely seal the study window from the dining room.",
	"Fresh wear on the crank shows the shutter was operated recently.",
	"Miriam's 8:20 fish course is untouched; her wine trails from a displaced chair.",
	"Daniel's 8:20 fish course is untouched; his napkin is missing and his chair displaced.",
	"Blood lies beneath Edgar's crushed watch crystal; a bronze fleck rests beside the hands stopped at 8:24.",
	"Edgar's cane lies beneath his left hand, though he was right-handed.",
}
learn_observation :: proc(g:^Game,index:int,play_cue:=true){if index<0||index>=len(OBSERVATION_TEXT)||mystery_game_observation_known(g,index) do return;if !mystery_game_mark_observation(g,index) do return;log_line(g,fmt.tprintf("Observed: %s",OBSERVATION_TEXT[index]));if play_cue do play_sound(g,.Evidence)}

cycle_string :: proc(current:string,values:[]string,delta:int)->string {index:=0;for value,i in values do if value==current do index=i;index=(index+delta+len(values))%len(values);return values[index]}
workbench_action_label :: proc(action:string)->string {switch action {case "open_shutter":return "OPEN SHUTTER";case "close_shutter":return "CLOSE SHUTTER";case "move_body":return "MOVE BODY";case:return strings.to_upper(action)};return strings.to_upper(action)}
workbench_action_short :: proc(action:string)->string {switch action {case "open_shutter":return "OPEN";case "close_shutter":return "CLOSE";case "move_body":return "CARRY BODY";case:return strings.to_upper(action)};return strings.to_upper(action)}
workbench_noun_label :: proc(value:string)->string {switch value {case "dining_room":return "DINING ROOM";case "unknown place":return "UNKNOWN PLACE";case "unknown object":return "UNKNOWN OBJECT";case "cloth_oil":return "OILED CLOTH";case "shutter_crank":return "SHUTTER CRANK";case:return strings.to_upper(value)};return strings.to_upper(value)}
workbench_default_event :: proc(index:int)->Workbench_Event {return {time=495+index,actor="someone",action="move",prop="unknown object",room="unknown place",pinned_observation=-1}}

event_chain_find_action :: proc(g:^Game,action:string)->int {for event,i in g.workbench_events[:g.workbench_event_count] do if event.action==action do return i;return -1}
event_chain_append :: proc(g:^Game,event:Workbench_Event) {if g.workbench_event_count>=len(g.workbench_events) do return;g.workbench_events[g.workbench_event_count]=event;g.workbench_event_count+=1}
mystery_game_has_block :: proc(g:^Game,block_id:string)->bool {payload:=mystery_game_payload(g);if payload==nil do return false;for &clue in payload.clues do if knowledge_piece_known(g,clue.id) {for i in 0..<clue.block_count do if clue.blocks[i]==block_id do return true};return false}
mystery_knowledge_piece_type :: proc(g:^Game,id:string)->string {payload:=mystery_game_payload(g);if payload==nil do return "";if mystery_clue_index(payload,id)>=0 do return "clue";if mystery_claim_index(payload,id)>=0 do return "statement";if mystery_deduction_index(payload,id)>=0 do return "deduction";return ""}

// Evidence proposes event fragments; it never silently repairs fields the
// player has already assembled. Later observations may only fill a genuinely
// unknown object or place on an existing fragment.
event_chain_from_evidence :: proc(g:^Game) {
	if knowledge_piece_known(g,"ded_daniel_affair")&&event_chain_find_action(g,"lie")<0 do event_chain_append(g,{509,"daniel","lie","miriam","dining_room",-1})
	if knowledge_piece_known(g,"ded_scene_staged")&&event_chain_find_action(g,"stage")<0 do event_chain_append(g,{509,"someone","stage","cane","garden",-1})
	if knowledge_piece_known(g,"ded_death_time")&&event_chain_find_action(g,"strike")<0 do event_chain_append(g,{504,"someone","strike","unknown object","unknown place",-1})
	strike:=event_chain_find_action(g,"strike");if strike>=0 {if knowledge_piece_known(g,"ded_statuette_weapon")&&g.workbench_events[strike].prop=="unknown object" do g.workbench_events[strike].prop="statuette";if knowledge_piece_known(g,"ded_study_murder")&&g.workbench_events[strike].room=="unknown place" do g.workbench_events[strike].room="study"}
	if knowledge_piece_known(g,"ded_body_moved")&&event_chain_find_action(g,"move_body")<0 do event_chain_append(g,{507,"someone","move_body","body","garden",-1})
	if mystery_game_has_block(g,"action_clean")&&event_chain_find_action(g,"clean")<0 do event_chain_append(g,{505,"someone","clean","cloth_oil","study",-1})
	if claim_known(g,"claim_miriam_summons_denial")&&event_chain_find_action(g,"deny")<0 do event_chain_append(g,{510,"miriam","deny","none","dining_room",-1})
	g.workbench_selected=clamp(g.workbench_selected,0,max(0,g.workbench_event_count-1));sync_theory_from_workbench(g)
}

event_chain_disputed :: proc(g:^Game,index:int)->bool {
	if index<0||index>=g.workbench_event_count do return false;event:=g.workbench_events[index]
	if event.action=="deny"&&knowledge_piece_known(g,"clue_burned_fragment") do return true
	if event.action=="lie"&&knowledge_piece_known(g,"clue_dinner_settings") do return true
	return false
}
event_chain_fragment_label :: proc(g:^Game,index:int)->string {if index<0||index>=g.workbench_event_count do return "NO EVENT";event:=g.workbench_events[index];if event_chain_disputed(g,index) do return "EVIDENCE DISAGREES";if !workbench_event_complete(event) do return "MISSING FIELDS";return workbench_support_event(g,index)?"SUPPORTED FRAGMENT":"UNSUPPORTED VERSION"}
workbench_event_complete :: proc(event:Workbench_Event)->bool {return event.actor!="someone"&&event.prop!="unknown object"&&event.room!="unknown place"}
workbench_first_incomplete :: proc(g:^Game)->int {for event,i in g.workbench_events[:g.workbench_event_count] do if !workbench_event_complete(event) do return i;return -1}
workbench_supported_count :: proc(g:^Game)->int {count:=0;for event,i in g.workbench_events[:g.workbench_event_count] do if workbench_event_complete(event)&&workbench_support_event(g,i) do count+=1;return count}
workbench_ready_to_present :: proc(g:^Game)->bool {return g.workbench_event_count>0&&mystery_game_accusation(g)!=""&&g.workbench_test_current}
workbench_snapshot :: proc(g:^Game)->Workbench_Snapshot {return {events=g.workbench_events,count=g.workbench_event_count,selected=g.workbench_selected,accused=mystery_game_accusation(g)}}
workbench_restore :: proc(g:^Game,s:Workbench_Snapshot) {g.workbench_events=s.events;g.workbench_event_count=s.count;g.workbench_selected=clamp(s.selected,0,max(0,s.count-1));mystery_game_set_accusation(g,s.accused);g.workbench_test_current=false;sync_theory_from_workbench(g)}
workbench_remember :: proc(g:^Game) {if g.workbench_undo_count==len(g.workbench_undo) {for i in 1..<len(g.workbench_undo) do g.workbench_undo[i-1]=g.workbench_undo[i];g.workbench_undo_count-=1};g.workbench_undo[g.workbench_undo_count]=workbench_snapshot(g);g.workbench_undo_count+=1;g.workbench_redo_count=0}
workbench_undo_edit :: proc(g:^Game) {if g.workbench_undo_count<=0 do return;if g.workbench_redo_count<len(g.workbench_redo) {g.workbench_redo[g.workbench_redo_count]=workbench_snapshot(g);g.workbench_redo_count+=1};g.workbench_undo_count-=1;workbench_restore(g,g.workbench_undo[g.workbench_undo_count]);g.workbench_feedback="The clockwork rewinds one edit.";play_sound(g,.Pick_Up)}
workbench_redo_edit :: proc(g:^Game) {if g.workbench_redo_count<=0 do return;if g.workbench_undo_count<len(g.workbench_undo) {g.workbench_undo[g.workbench_undo_count]=workbench_snapshot(g);g.workbench_undo_count+=1};g.workbench_redo_count-=1;workbench_restore(g,g.workbench_redo[g.workbench_redo_count]);g.workbench_feedback="The clockwork reapplies the edit.";play_sound(g,.Snap)}
sync_theory_from_workbench :: proc(g:^Game) {
	for section in 0..<5 do for socket in 0..<3 do g.board_sockets[section][socket]=false
	if g.mystery_state!=nil {clear(&g.mystery_state.reconstruction_order);for event in g.workbench_events[:g.workbench_event_count] do append(&g.mystery_state.reconstruction_order,fmt.tprintf("%d|%s|%s|%s|%s",event.time,event.actor,event.action,event.prop,event.room))}
	clean,move_body,stage:=false,false,false
	for event in g.workbench_events[:g.workbench_event_count] {
		if event.action=="motive"&&event.actor==mystery_game_accusation(g)&&event.prop=="ledger" do g.board_sockets[0][0]=true
		if event.action=="strike"&&event.actor==mystery_game_accusation(g) {if event.prop=="statuette" do g.board_sockets[1][0]=true;if event.room=="study" do g.board_sockets[1][1]=true;if event.time>=503&&event.time<=505 do g.board_sockets[1][2]=true}
		if event.action=="clean"&&event.actor==mystery_game_accusation(g) {clean=true;g.board_sockets[2][2]=true}
		if event.action=="move_body"&&event.actor==mystery_game_accusation(g) {move_body=true;g.board_sockets[2][0]=true}
		if event.action=="stage"&&event.actor==mystery_game_accusation(g)&&event.room=="garden" {stage=true;g.board_sockets[2][1]=true}
		if event.action=="lie"&&event.actor=="daniel" do g.board_sockets[3][0]=true
		if event.action=="deny"&&event.actor=="miriam"&&event.room=="dining_room"&&event.time>=510 {g.board_sockets[4][0]=true;g.board_sockets[4][1]=true}
	}
	_=clean;_=move_body;_=stage
}
configure_complete_workbench :: proc(g:^Game) {
	g.workbench_events={
		{495,"miriam","motive","ledger","study",-1},
		{504,"miriam","strike","statuette","study",-1},
		{505,"miriam","clean","cloth_oil","study",-1},
		{507,"miriam","move_body","body","garden",-1},
		{509,"miriam","stage","cane","garden",-1},
		{509,"daniel","lie","miriam","dining_room",-1},
		{510,"miriam","deny","none","dining_room",-1},
		{},
		{},
	};g.workbench_event_count=7;g.workbench_selected=6;mystery_game_set_accusation(g,"miriam");g.workbench_test_current=false;sync_theory_from_workbench(g)
}
workbench_add_event_simple :: proc(g:^Game){if g.workbench_event_count>=len(g.workbench_events) do return;workbench_remember(g);g.workbench_events[g.workbench_event_count]=workbench_default_event(g.workbench_event_count);g.workbench_selected=g.workbench_event_count;g.workbench_event_count+=1;g.workbench_test_current=false;sync_theory_from_workbench(g);g.workbench_feedback="Choose who acted, what they did, what they used, and where.";play_sound(g,.Pick_Up)}
workbench_remove_event_simple :: proc(g:^Game){if g.workbench_event_count<=0 do return;workbench_remember(g);index:=clamp(g.workbench_selected,0,g.workbench_event_count-1);for i in index..<g.workbench_event_count-1 do g.workbench_events[i]=g.workbench_events[i+1];g.workbench_event_count-=1;g.workbench_selected=clamp(index,0,max(0,g.workbench_event_count-1));g.workbench_test_current=false;sync_theory_from_workbench(g);g.workbench_feedback="Beat removed. Test the revised sequence when you are ready."}
workbench_swap :: proc(g:^Game,delta:int){if g.workbench_event_count<2 do return;from:=clamp(g.workbench_selected,0,g.workbench_event_count-1);to:=clamp(from+delta,0,g.workbench_event_count-1);if from==to do return;workbench_remember(g);g.workbench_events[from],g.workbench_events[to]=g.workbench_events[to],g.workbench_events[from];g.workbench_selected=to;g.workbench_test_current=false;sync_theory_from_workbench(g);play_sound(g,.Pick_Up)}
workbench_move_event :: proc(g:^Game,from,to:int)->bool {if from<0||from>=g.workbench_event_count||to<0||to>=g.workbench_event_count||from==to do return false;workbench_remember(g);moving:=g.workbench_events[from];if from<to {for i in from..<to do g.workbench_events[i]=g.workbench_events[i+1]}else{for i:=from;i>to;i-=1 do g.workbench_events[i]=g.workbench_events[i-1]};g.workbench_events[to]=moving;g.workbench_selected=to;g.workbench_test_current=false;sync_theory_from_workbench(g);g.workbench_feedback="Sequence changed. Test it again to confirm the new order.";play_sound(g,.Snap);return true}
workbench_cycle :: proc(g:^Game,field,delta:int){if g.workbench_event_count==0 do workbench_add_event_simple(g);workbench_remember(g);event:=&g.workbench_events[g.workbench_selected];switch field {case 0:event.time=clamp(event.time+delta,495,520);case 1:event.actor=cycle_string(event.actor,WORKBENCH_ACTORS[:],delta);case 2:event.action=cycle_string(event.action,WORKBENCH_ACTIONS[:],delta);case 3:event.prop=cycle_string(event.prop,WORKBENCH_PROPS[:],delta);case 4:event.room=cycle_string(event.room,WORKBENCH_ROOMS[:],delta)};g.workbench_test_current=false;sync_theory_from_workbench(g);g.workbench_field=field;g.workbench_feedback=workbench_event_complete(event^)?"Beat changed. Test the sequence to see its consequences.":"Finish the highlighted beat before testing the sequence."}
workbench_controller_edit :: proc(g:^Game) {
	if g.active_device!=.Gamepad||g.workbench_event_count<=0 do return
	if g.input.left do g.workbench_field=(g.workbench_field+4)%5
	if g.input.right do g.workbench_field=(g.workbench_field+1)%5
	if g.input.up do workbench_cycle(g,g.workbench_field,-1)
	if g.input.down do workbench_cycle(g,g.workbench_field,1)
}
workbench_support_event :: proc(g:^Game,index:int)->bool {if index<0||index>=g.workbench_event_count do return false;event:=g.workbench_events[index];switch event.action {case "motive":return knowledge_piece_known(g,"ded_miriam_motive");case "strike":return knowledge_piece_known(g,"ded_statuette_weapon")&&knowledge_piece_known(g,"ded_study_murder");case "clean":return mystery_game_has_block(g,"action_clean");case "move_body":return knowledge_piece_known(g,"ded_body_moved");case "stage":return knowledge_piece_known(g,"ded_scene_staged");case "lie":return knowledge_piece_known(g,"ded_daniel_affair");case "deny":return knowledge_piece_known(g,"ded_miriam_denial_disproved");case "open_shutter","close_shutter":return false;case:return true};return false}
workbench_source_text :: proc(g:^Game,index:int)->string {
	if index<0||index>=g.workbench_event_count do return "No event selected."
	event:=g.workbench_events[index];if !workbench_event_complete(event) do return "UNFINISHED BEAT: replace the red unknowns before the dollhouse can test it."
	supported:=workbench_support_event(g,index);prefix:=supported?"SUPPORTED BY: ":"NEEDS EVIDENCE: ";source:string
	switch event.action {case "motive":source="the household ledger and missing accounts";case "strike":source="the statuette, wound match, and study scene";case "clean":source="lamp oil and blood trapped in the base seam";case "open_shutter","close_shutter":source="the mechanism can be tested, but no evidence identifies its operator";case "move_body":source="the study blood and terrace-to-garden drag trace";case "stage":source="Edgar's cane beneath the wrong hand";case "lie":source="Daniel's disturbed dinner setting and admission";case "deny":source="Miriam's denial and the rejoined appointment note";case:return "PROPOSED MOTION: physical simulation can test this without an evidence block."}
	return fmt.tprintf("%s%s",prefix,source)
}
run_workbench :: proc(g:^Game){if g.workbench_event_count==0 {g.workbench_feedback="Add at least one beat before testing.";play_sound(g,.Reject);return};incomplete:=workbench_first_incomplete(g);if incomplete>=0 {g.workbench_selected=incomplete;g.workbench_feedback=fmt.tprintf("Beat %d is unfinished. Replace every UNKNOWN before testing.",incomplete+1);play_sound(g,.Reject);return};sync_theory_from_workbench(g);for i in 0..<len(g.workbench_supported) do g.workbench_supported[i]=false;for i in 0..<g.workbench_event_count do g.workbench_supported[i]=workbench_support_event(g,i);g.workbench_result=simulate_workbench(g.workbench_events[:g.workbench_event_count],g.workbench_supported[:]);g.workbench_test_current=true;g.recreate_runs+=1;g.recreate_started=g.animation_time;if g.workbench_result.first_failed_event>=0 do g.workbench_selected=g.workbench_result.first_failed_event;play_sound(g,.Recreate);g.screen=.Recreate}
evaluate_workbench :: proc(g:^Game)->Outcome {
	if mystery_game_accusation(g)=="" do return .Unresolved
	payload:=mystery_game_payload(g);if payload==nil do return .Unresolved
	if mystery_game_accusation(g)!=payload.solution.culprit_id do return .Wrong_Accusation
	unsupported:=false
	for _,i in g.workbench_events[:g.workbench_event_count] do if !workbench_support_event(g,i) do unsupported=true
	decisive:=g.workbench_result.decisive_contradiction
	physical_or_proof:=g.workbench_result.physically_possible||decisive
	diagnosis:=Mystery_Diagnosis{}
	if g.mystery_state!=nil {g.mystery_state.accusation_id=mystery_game_accusation(g);diagnosis=mystery_diagnose_player(g.story_project,g.mystery_state)}
	if physical_or_proof&&!unsupported&&decisive&&diagnosis.evidence_supported&&diagnosis.complete&&diagnosis.exclusive do return .Airtight
	for pillar in 0..<3 do if mystery_game_theory_pillar(g,pillar)!="" do return .Correct_But_Unproven
	return .Plausible_Incomplete
}

question_index_by_id :: proc(g:^Game,id:string)->int {payload:=mystery_game_payload(g);if payload!=nil {for question,i in payload.questions do if question.id==id do return i};return -1}
mystery_question_progress :: proc(g:^Game,index:int,create:=false)->^Mystery_Question_Progress {payload:=mystery_game_payload(g);if payload==nil||g.mystery_state==nil||index<0||index>=len(payload.questions) do return nil;id:=payload.questions[index].id;for &progress in g.mystery_state.question_progress do if progress.question_id==id do return &progress;if !create do return nil;append(&g.mystery_state.question_progress,Mystery_Question_Progress{question_id=id,state=int(Hypothesis_State.Locked)});return &g.mystery_state.question_progress[len(g.mystery_state.question_progress)-1]}
mystery_question_state :: proc(g:^Game,index:int)->Hypothesis_State {progress:=mystery_question_progress(g,index);return progress==nil?.Locked:Hypothesis_State(progress.state)}
mystery_question_set_state :: proc(g:^Game,index:int,state:Hypothesis_State) {progress:=mystery_question_progress(g,index,true);if progress!=nil do progress.state=int(state)}
mystery_question_slot :: proc(g:^Game,index,slot:int)->string {progress:=mystery_question_progress(g,index);if progress==nil||slot<0||slot>=len(progress.slots) do return "";return progress.slots[slot]}
mystery_question_set_slot :: proc(g:^Game,index,slot:int,value:string) {progress:=mystery_question_progress(g,index,true);if progress!=nil&&slot>=0&&slot<len(progress.slots) do progress.slots[slot]=value}
mystery_question_slots :: proc(g:^Game,index:int)->[3]string {progress:=mystery_question_progress(g,index);if progress==nil do return {};return progress.slots}
demonstration_for_question :: proc(g:^Game,question_index:int)->int {payload:=mystery_game_payload(g);if payload==nil||question_index<0||question_index>=len(payload.questions) do return -1;id:=payload.questions[question_index].id;for demonstration,i in payload.demonstrations do if demonstration.question_id==id do return i;return -1}
deduction_index_by_id :: proc(g:^Game,id:string)->int {payload:=mystery_game_payload(g);if payload!=nil {for deduction,i in payload.deductions do if deduction.id==id do return i};return -1}
knowledge_piece_known :: proc(g:^Game,id:string)->bool {
	return g.mystery_state!=nil&&mystery_state_knows(g.mystery_state,id)
}
knowledge_piece_text :: proc(g:^Game,id:string)->string {
	payload:=mystery_game_payload(g);if payload==nil do return "Unknown piece"
	for &clue in payload.clues do if clue.id==id do return mystery_clue_proposition_text(g.story_project,&clue)
	for claim in payload.claims do if claim.id==id {index:=story_proposition_index(g.story_project,claim.proposition_id);return index>=0?g.story_project.propositions[index].text:claim.proposition_id}
	for deduction in payload.deductions do if deduction.id==id {index:=story_proposition_index(g.story_project,deduction.proposition_id);return index>=0?g.story_project.propositions[index].text:deduction.proposition_id}
	return "Unknown piece"
}
knowledge_piece_kind :: proc(g:^Game,id:string)->string {
	payload:=mystery_game_payload(g);if payload!=nil {clue_index:=mystery_clue_index(payload,id);if clue_index>=0 {source:=payload.clues[clue_index].source_id;entity:=story_entity_index(g.story_project,source);return entity>=0&&g.story_project.entities[entity].kind=="character"?"TESTIMONY":"OBSERVATION"};if mystery_claim_index(payload,id)>=0 do return "STATEMENT";if mystery_deduction_index(payload,id)>=0 do return "DEDUCTION"}
	return "INFERENCE"
}
question_is_resolved :: proc(g:^Game,index:int)->bool {payload:=mystery_game_payload(g);if payload==nil||index<0||index>=len(payload.questions) do return false;state:=mystery_question_state(g,index);return state==.Substantiated||state==.Eliminated||state==.Explained}
question_unlocked :: proc(g:^Game,index:int)->bool {
	payload:=mystery_game_payload(g);if payload==nil||index<0||index>=len(payload.questions) do return false;q:=payload.questions[index]
	for id in q.requires_clues[:q.require_clue_count] do if !knowledge_piece_known(g,id) do return false
	for id in q.requires_claims[:q.require_claim_count] do if !knowledge_piece_known(g,id) do return false
	for id in q.requires_deductions[:q.require_deduction_count] do if !knowledge_piece_known(g,id) do return false
	for id in q.dependencies[:q.dependency_count] {prior:=question_index_by_id(g,id);if prior<0||!question_is_resolved(g,prior) do return false}
	return true
}
refresh_questions :: proc(g:^Game) {payload:=mystery_game_payload(g);if payload==nil do return;first_open:=-1;opened:=false;for _,i in payload.questions {if mystery_question_state(g,i)==.Locked&&question_unlocked(g,i) {mystery_question_set_state(g,i,.Unsubstantiated);log_line(g,fmt.tprintf("Question opened: %s",payload.questions[i].prompt));opened=true};if first_open<0&&question_unlocked(g,i) do first_open=i};if first_open>=0&&(g.question_selected<0||g.question_selected>=len(payload.questions)||!question_unlocked(g,g.question_selected)) do g.question_selected=first_open;if opened do _=game_story_milestone(g,"investigation.question_opened")}
known_piece_count :: proc(g:^Game)->int {if g.mystery_state==nil do return 0;return len(g.mystery_state.acquired_evidence)+len(g.mystery_state.established_claims)+len(g.mystery_state.earned_deductions)}
known_piece_id :: proc(g:^Game,wanted:int)->string {if wanted<0||g.mystery_state==nil do return "";cursor:=wanted;if cursor<len(g.mystery_state.acquired_evidence) do return g.mystery_state.acquired_evidence[cursor];cursor-=len(g.mystery_state.acquired_evidence);if cursor<len(g.mystery_state.established_claims) do return g.mystery_state.established_claims[cursor];cursor-=len(g.mystery_state.established_claims);if cursor<len(g.mystery_state.earned_deductions) do return g.mystery_state.earned_deductions[cursor];return ""}
question_slot_piece_type :: proc(g:^Game)->string {payload:=mystery_game_payload(g);if payload==nil||g.question_selected<0||g.question_selected>=len(payload.questions) do return "";demo_index:=demonstration_for_question(g,g.question_selected);if demo_index<0 do return "";demo:=payload.demonstrations[demo_index];return demo.slot_types[clamp(g.question_slot,0,demo.slot_count-1)]}
question_slot_piece_kind :: proc(g:^Game)->string {piece_type:=question_slot_piece_type(g);return piece_type==""?"":strings.to_upper(piece_type)}
question_slot_piece_count :: proc(g:^Game)->int {kind:=question_slot_piece_kind(g);if kind=="" do return 0;count:=0;for i in 0..<known_piece_count(g) do if knowledge_piece_kind(g,known_piece_id(g,i))==kind do count+=1;return count}
knowledge_piece_topics_overlap :: proc(payload:^Mystery_Project,a,b:string)->int {ai,bi:=mystery_clue_index(payload,a),mystery_clue_index(payload,b);if ai<0||bi<0 do return 0;score:=0;for left in payload.clues[ai].topics[:payload.clues[ai].topic_count] do for right in payload.clues[bi].topics[:payload.clues[bi].topic_count] do if left==right do score+=1;return score}
demonstration_candidate_score :: proc(g:^Game,demo:^Mystery_Demonstration,id:string)->int {
	payload:=mystery_game_payload(g);if payload==nil do return 0;score:=0
	for accepted in demo.accepted[:demo.accepted_count] do if accepted==id do score+=1000
	anchor:=demo.subject;if anchor==""&&demo.accepted_count>0 do anchor=demo.accepted[0]
	score+=knowledge_piece_topics_overlap(payload,anchor,id)*40
	ai,bi:=mystery_clue_index(payload,anchor),mystery_clue_index(payload,id);if ai>=0&&bi>=0&&payload.clues[ai].source_id==payload.clues[bi].source_id do score+=20
	for &other in payload.demonstrations {has_anchor,has_id:=false,false;for piece in other.accepted[:other.accepted_count] {if piece==anchor do has_anchor=true;if piece==id do has_id=true};if has_anchor&&has_id do score+=10}
	return score
}
question_slot_piece_id :: proc(g:^Game,wanted:int)->string {
	if wanted<0 do return "";kind:=question_slot_piece_kind(g);if kind=="" do return ""
	payload:=mystery_game_payload(g);demo_index:=demonstration_for_question(g,g.question_selected);if payload==nil||demo_index<0 do return "";demo:=&payload.demonstrations[demo_index]
	chosen:[MYSTERY_MAX_REFS]string;chosen_count:=0
	for rank in 0..=wanted {
		best:="";best_score:=-1
		for i in 0..<known_piece_count(g) {id:=known_piece_id(g,i);if knowledge_piece_kind(g,id)!=kind do continue;already:=false;for prior in chosen[:chosen_count] do if prior==id do already=true;if already do continue;score:=demonstration_candidate_score(g,demo,id);if score>best_score {best=id;best_score=score}}
		if best=="" do return "";chosen[chosen_count]=best;chosen_count+=1;if rank==wanted do return best
	}
	return ""
}
mystery_demonstration_route_piece :: proc(demo:^Mystery_Demonstration,route,slot:int)->string {if route<0||route>=demo.route_count||slot<0||slot>=demo.route_counts[route] do return "";index:=demo.route_firsts[route]+slot;if index<0||index>=demo.accepted_count do return "";return demo.accepted[index]}
mystery_demonstration_matches :: proc(demo:^Mystery_Demonstration,placed:[3]string)->bool {for route in 0..<demo.route_count {correct:=true;for slot in 0..<demo.route_counts[route] do if placed[slot]!=mystery_demonstration_route_piece(demo,route,slot) do correct=false;if correct do return true};return false}
question_place_piece :: proc(g:^Game,piece:string) {payload:=mystery_game_payload(g);if payload==nil||g.question_selected<0||g.question_selected>=len(payload.questions)||piece=="" do return;demo_index:=demonstration_for_question(g,g.question_selected);if demo_index<0 do return;demo:=&payload.demonstrations[demo_index];slot_count:=demo.slot_count;slot:=clamp(g.question_slot,0,slot_count-1);needed:=demo.slot_types[slot];if !knowledge_piece_known(g,piece)||strings.to_lower(knowledge_piece_kind(g,piece))!=needed {g.question_feedback=fmt.tprintf("This part of the test needs evidence recorded as %s.",strings.to_upper(needed));play_sound(g,.Reject);return};tutorial_complete(g,.Board_Place);mystery_question_set_slot(g,g.question_selected,slot,piece);g.question_slot=(slot+1)%slot_count;g.knowledge_cursor=0;g.question_feedback="Evidence placed. Demonstrate the combination to test the claim.";play_sound(g,.Snap)}
question_clear_slot :: proc(g:^Game) {payload:=mystery_game_payload(g);if payload==nil||g.question_selected<0||g.question_selected>=len(payload.questions) do return;mystery_question_set_slot(g,g.question_selected,clamp(g.question_slot,0,2),"");g.question_feedback="Evidence removed from this test.";play_sound(g,.Pick_Up)}
question_slots_full :: proc(g:^Game,question_index:int)->bool {payload:=mystery_game_payload(g);demo_index:=demonstration_for_question(g,question_index);if payload==nil||demo_index<0 do return false;for slot in 0..<payload.demonstrations[demo_index].slot_count do if mystery_question_slot(g,question_index,slot)=="" do return false;return true}
sync_theory_from_questions :: proc(g:^Game) {
	for pillar in 0..<3 {id:=mystery_game_theory_pillar(g,pillar);if id!=""&&!deduction_supports(g,id,mystery_game_accusation(g),pillar) do mystery_game_set_theory_pillar(g,pillar,"")}
}
proof_pillar_name :: proc(pillar:int)->string {switch pillar {case 0:return "motive";case 1:return "means";case 2:return "opportunity"};return ""}
deduction_supports :: proc(g:^Game,id,candidate:string,pillar:int)->bool {payload:=mystery_game_payload(g);if payload==nil||g.mystery_state==nil do return false;wanted:=fmt.tprintf("%s:%s",candidate,proof_pillar_name(pillar));for deduction in payload.deductions do if deduction.id==id&&mystery_string_set_has(g.mystery_state.earned_deductions[:],id) {for support_index in 0..<deduction.support_count do if deduction.supports[support_index]==wanted do return true};return false}
proof_pillar_piece_count :: proc(g:^Game,candidate:string,pillar:int)->int {payload:=mystery_game_payload(g);if payload==nil do return 0;count:=0;for deduction in payload.deductions do if knowledge_piece_known(g,deduction.id)&&deduction_supports(g,deduction.id,candidate,pillar) do count+=1;return count}
proof_pillar_piece :: proc(g:^Game,candidate:string,pillar,wanted:int)->string {payload:=mystery_game_payload(g);if payload==nil do return "";seen:=0;for deduction in payload.deductions do if knowledge_piece_known(g,deduction.id)&&deduction_supports(g,deduction.id,candidate,pillar) {if seen==wanted do return deduction.id;seen+=1};return ""}
demonstration_route_known :: proc(g:^Game,demo:^Mystery_Demonstration,route:int)->bool {for slot in 0..<demo.route_counts[route] do if !knowledge_piece_known(g,mystery_demonstration_route_piece(demo,route,slot)) do return false;return true}
proof_pillar_attainable :: proc(g:^Game,candidate:string,pillar:int)->bool {if proof_pillar_piece_count(g,candidate,pillar)>0 do return true;payload:=mystery_game_payload(g);if payload==nil do return false;wanted:=fmt.tprintf("%s:%s",candidate,proof_pillar_name(pillar));for &demo in payload.demonstrations {supports:=false;for result_index in 0..<demo.result_count {result:=demo.result_deductions[result_index];for deduction in payload.deductions do if deduction.id==result {for support_index in 0..<deduction.support_count do if deduction.supports[support_index]==wanted do supports=true}};if supports {for route in 0..<demo.route_count do if demonstration_route_known(g,&demo,route) do return true}};return false}
proof_framework_attainable :: proc(g:^Game,candidate:string)->bool {for pillar in 0..<3 do if !proof_pillar_attainable(g,candidate,pillar) do return false;return true}
cycle_proof_pillar :: proc(g:^Game,pillar:int) {count:=proof_pillar_piece_count(g,mystery_game_accusation(g),pillar);if count==0 {mystery_game_set_theory_pillar(g,pillar,"");return};current:=-1;for i in 0..<count do if proof_pillar_piece(g,mystery_game_accusation(g),pillar,i)==mystery_game_theory_pillar(g,pillar) do current=i;mystery_game_set_theory_pillar(g,pillar,proof_pillar_piece(g,mystery_game_accusation(g),pillar,(current+1)%count));play_sound(g,.Snap)}
question_required_complete :: proc(g:^Game)->bool {return true}
question_framework_complete :: proc(g:^Game)->bool {for pillar in 0..<3 do if !deduction_supports(g,mystery_game_theory_pillar(g,pillar),mystery_game_accusation(g),pillar) do return false;return true}
question_ready_to_present :: proc(g:^Game)->bool {return mystery_game_accusation(g)!=""&&question_framework_complete(g)}
visible_question_index :: proc(g:^Game,slot:int)->int {payload:=mystery_game_payload(g);if payload==nil do return -1;seen:=0;for _,i in payload.questions do if question_unlocked(g,i)&&!question_is_resolved(g,i) {if seen==slot do return i;seen+=1;if seen==3 do break};for _,i in payload.questions do if question_unlocked(g,i)&&question_is_resolved(g,i) {if seen==slot do return i;seen+=1;if seen==5 do break};return -1}
active_question_index :: proc(g:^Game,slot:int)->int {payload:=mystery_game_payload(g);if payload==nil do return -1;seen:=0;for _,i in payload.questions do if question_unlocked(g,i)&&!question_is_resolved(g,i) {if seen==slot do return i;seen+=1};return -1}
resolved_question_count :: proc(g:^Game)->int {payload:=mystery_game_payload(g);if payload==nil do return 0;count:=0;for _,i in payload.questions do if question_is_resolved(g,i) do count+=1;return count}
begin_question_demonstration :: proc(g:^Game) {
	payload:=mystery_game_payload(g);demo_index:=demonstration_for_question(g,g.question_selected);if payload==nil||demo_index<0 do return;demo:=&payload.demonstrations[demo_index]
	if demo.presentation==""||demo.presentation=="slots" {run_question_demonstration(g);return}
	if !question_slots_full(g,g.question_selected) {g.question_feedback="Choose evidence for every part of the test.";play_sound(g,.Reject);return}
	g.active_demonstration=demo_index;g.interaction_step=0;g.interaction_active=true;g.interaction_mismatch=false;g.question_feedback="";g.screen=.Recreate;play_sound(g,.Pick_Up)
}
advance_question_interaction :: proc(g:^Game) {
	payload:=mystery_game_payload(g);if payload==nil||g.active_demonstration<0||g.active_demonstration>=len(payload.demonstrations) do return;demo:=&payload.demonstrations[g.active_demonstration]
	steps:=max(1,demo.gesture_step_count);if g.interaction_step+1<steps {g.interaction_step+=1;play_sound(g,.Snap);return}
	placed:=mystery_question_slots(g,g.question_selected);if !mystery_demonstration_matches(demo,placed) {g.interaction_active=false;g.interaction_mismatch=true;mystery_question_set_state(g,g.question_selected,.Unsubstantiated);g.question_feedback="The relationship does not hold. The selected evidence disagrees without identifying an alternative.";play_sound(g,.Reject);return}
	g.interaction_active=false;g.interaction_mismatch=false;run_question_demonstration(g)
}
run_question_demonstration :: proc(g:^Game) {
	tutorial_complete(g,.Board_Test)
	payload:=mystery_game_payload(g);q:=g.question_selected;demo_index:=demonstration_for_question(g,q);if payload==nil||demo_index<0 do return;demo:=payload.demonstrations[demo_index]
	all_filled:=true
	for slot in 0..<demo.slot_count do if mystery_question_slot(g,q,slot)=="" do all_filled=false
	if !all_filled {g.question_feedback="Choose evidence for every part of the test.";play_sound(g,.Reject);return}
	placed:=mystery_question_slots(g,q);if !mystery_demonstration_matches(&demo,placed) {mystery_question_set_state(g,q,.Unsubstantiated);g.question_feedback="These facts do not establish a conclusion together.";play_sound(g,.Reject);return}
	switch demo.resolution {case "substantiated":mystery_question_set_state(g,q,.Substantiated);case "eliminated":mystery_question_set_state(g,q,.Eliminated);case "explained":mystery_question_set_state(g,q,.Explained)}
	if g.mystery_state!=nil do _=mystery_complete_demonstration(g.story_project,g.mystery_state,payload.questions[q].id)
	for id in demo.result_deductions[:demo.result_count] {index:=deduction_index_by_id(g,id);if index>=0 {if g.mystery_state!=nil do _=mystery_string_set_add(&g.mystery_state.earned_deductions,id);log_line(g,fmt.tprintf("Deduction: %s",knowledge_piece_text(g,id)));deduction:=payload.deductions[index];for topic in deduction.unlock_topics[:deduction.unlock_topic_count] do unlock_topic(g,topic)}}
	g.active_demonstration=demo_index;g.question_feedback=demo.result;sync_theory_from_questions(g);refresh_questions(g);if question_ready_to_present(g) do _=game_story_milestone(g,"investigation.explanation_ready");g.recreate_runs+=1;g.recreate_started=g.animation_time;play_sound(g,.Recreate);g.screen=.Recreate
}
evaluate_questions :: proc(g:^Game)->Outcome {if g.story_project==nil||g.mystery_state==nil do return .Unresolved;return mystery_evaluate_outcome(g.story_project,g.mystery_state)}
configure_complete_questions :: proc(g:^Game) {payload:=mystery_game_payload(g);if payload==nil do return;mystery_game_mark_all_clues(g);for claim in payload.claims do _=learn_claim(g,claim.id);refresh_questions(g);for _,i in payload.questions {demo_index:=demonstration_for_question(g,i);if demo_index<0 do continue;demo:=payload.demonstrations[demo_index];for slot in 0..<demo.slot_count do mystery_question_set_slot(g,i,slot,mystery_demonstration_route_piece(&demo,0,slot));g.question_selected=i;run_question_demonstration(g)};mystery_game_set_accusation(g,payload.solution.culprit_id);for pillar in 0..<3 do cycle_proof_pillar(g,pillar)}
Vec2 :: ui.Vec2
Rect :: struct {x,y,w,h:f32}
Horizontal_Anchor :: enum {Left, Right}
Input_State :: struct {
	mouse_pos:Vec2,mouse_wheel:f32,dialogue_choice_slot:int,mouse_down,mouse_pressed,mouse_released,mouse_middle_down,mouse_middle_pressed,mouse_middle_released,activate,vehicle_action,back,left,right,up,down,recreate,notebook,attributes,case_sense,case_sense_release,camera_toggle,wall_view_cycle,shoulder_left,shoulder_right,save_document,undo_document,redo_document,delete_selection,copy_selection,paste_selection,duplicate_selection:bool,
	text_input:[32]u8,text_input_len:int,clipboard_paste:[256]u8,clipboard_paste_len:int,
	key_shift,key_ctrl,key_super,key_enter,key_escape,key_backspace,key_delete,key_tab,key_home,key_end,key_left,key_right,key_a,key_x,key_v,key_c:bool,
}
