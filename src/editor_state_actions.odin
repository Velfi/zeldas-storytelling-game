package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

editor_build_tool_name :: proc(tool: Build_Tool) -> string {for known, i in BUILD_TOOL_GRID do if known == tool do return BUILD_TOOL_NAMES[i]
	return "SELECT"}
editor_build_tool_shortcut :: proc(tool: Build_Tool) -> string {for known, i in BUILD_MODE_GRID do if known == tool do return BUILD_MODE_SHORTCUTS[i]
	return ""}
editor_build_tool_idle_hint :: proc(tool: Build_Tool) -> string {
	#partial switch tool {
	case .Select:
		return "Click or drag to select · Shift adds or removes items"
	case .Foundation:
		return "Step 1 · Drag a footprint or choose polygon mode"
	case .Paint:
		return "Step 1 · Choose a surface and material · Step 2 · Click a room"
	case .Wall_Paint:
		return "Choose a wall material, then click a room"
	case .Plant:
		return "Step 1 · Choose an object · Step 2 · Click to place it"
	case .Light:
		if editor_state.selection_count == 1 && editor_state.selection[0].kind == .Light do return "Editing selected light · click empty space to place a new light"
		return "Click to place a light · select one to fine-tune it"
	case .Door:
		return "Step 1 · Move over a wall · Step 2 · Click to place a door"
	case .Window:
		return "Step 1 · Move over a wall · Step 2 · Click to place a window"
	case .Wall:
		return "Step 1 · Click wall start · Step 2 · Click wall end"
	case .Room:
		return "Step 1 · Drag a room footprint · Step 2 · Release to create"
	case .Roof:
		return "Step 1 · Move over a room · Step 2 · Adjust roof · Apply or click room"
	case .Stairs:
		return "Step 1 · Click lower landing · Step 2 · Click upper landing"
	case .Path:
		return "Step 1 · Click path start · Step 2 · Add points · Enter finishes"
	case .Water:
		return "Step 1 · Click shoreline start · Step 2 · Add 2+ points · Enter closes"
	case .Terrain:
		return "Drag on the lot to sculpt · Ctrl reverses the brush"
	case .Marker:
		if editor_state.selection_count == 1 && editor_state.selection[0].kind == .Marker do return "Editing selected marker · click empty space to place a new marker"
		return "Choose a marker type, then click to place it"
	}
	return "Choose a tool to begin"
}
editor_selection_shortcut_hint :: proc(count: int) -> string {if count > 1 do return "Drag selection · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete"
	return "Drag to move · Shift add/remove · Ctrl/Cmd C copy · Ctrl/Cmd D duplicate · Delete"}
editor_selection_status_hint :: proc(selection: Editor_Selection, count: int) -> string {
	if editor_state.object_rotate_active do return "Drag to rotate · 15° snap · hold Alt for free angle · Esc cancels"
	if count > 1 do return editor_selection_shortcut_hint(count)
	#partial switch selection.kind {
	case .Foundation:
		return(
			editor_control_point_index(selection) >= 0 ? "Drag foundation corner · Alt suspends snap · Esc cancels" : "Drag a visible corner to reshape · adjust height in inspector" \
		)
	case .Edge:
		return "Drag edge · Insert corner from toolbar"
	case .Vertex:
		return "Drag corner · Remove corner from toolbar"
	case .Opening:
		return "Drag to slide · Resize from toolbar · Delete"
	case .Path:
		return(
			editor_control_point_index(selection) >= 0 ? "Drag path point · Alt suspends snap · Esc cancels" : "Drag a visible point to reshape · adjust width in inspector" \
		)
	case .Water:
		return(
			editor_control_point_index(selection) >= 0 ? "Drag shoreline point · Alt suspends snap · Esc cancels" : "Drag a visible point to reshape · adjust surface in inspector" \
		)
	case .Vertical_Link:
		return(
			editor_control_point_index(selection) >= 0 ? "Drag landing · Alt suspends snap · Esc cancels" : "Drag either landing to reshape · adjust width in inspector" \
		)
	case .Roof:
		return "Edit with the Roof tool · Delete"
	}
	return editor_selection_shortcut_hint(1)
}
editor_escape_target :: proc(tool: Build_Tool) -> Build_Tool {
	#partial switch tool {
	case .Wall, .Door, .Window:
		return .Room
	case .Light:
		return .Plant
	case .Wall_Paint:
		return .Paint
	case:
		return .Select
	}
}
editor_show_feedback :: proc(message: string, error := false) {editor_state.feedback = message
	editor_state.feedback_frames = 240
	editor_state.feedback_error = error}
editor_request_build_exit :: proc(
	g: ^Game,
) {if level_document.dirty {editor_state.exit_confirm_visible = true
		editor_state.shortcut_help_visible =
			false} else {g.editor_mode = .None; g.interactive_count = 0}
	g.move_target_active = false}
editor_delete_command :: proc(
	doc: ^Level_Document,
	command: Level_Command,
	label, noun: string,
) -> bool {if !level_commit_transaction(doc, command, label) do return false; editor_show_feedback(
		fmt.tprintf("DELETED %s  ·  CTRL/CMD Z TO UNDO", noun),
	)
	return true}
Editor_Box_Model :: struct {
	padding, border, gap: f32,
}
EDITOR_TOOL_RAIL_BOX := Editor_Box_Model {
	padding = 10,
	border  = 1,
	gap     = 6,
}
EDITOR_TOOL_BUTTON_SIZE := Vec2{44, 44}
EDITOR_TOOL_RAIL_ORIGIN := Vec2{8, 76}

editor_vertical_stack_bounds :: proc(
	origin, item_size: Vec2,
	count: int,
	box: Editor_Box_Model,
) -> Rect {
	content_height := f32(max(count, 0)) * item_size.y + f32(max(count - 1, 0)) * box.gap
	inset := box.padding + box.border
	return {origin.x, origin.y, item_size.x + inset * 2, content_height + inset * 2}
}

editor_vertical_stack_item :: proc(
	bounds: Rect,
	index: int,
	item_size: Vec2,
	box: Editor_Box_Model,
) -> Rect {
	inset := box.padding + box.border
	return {
		bounds.x + inset,
		bounds.y + inset + f32(max(index, 0)) * (item_size.y + box.gap),
		item_size.x,
		item_size.y,
	}
}

editor_tool_rail_rect :: proc() -> Rect {return editor_vertical_stack_bounds(
		EDITOR_TOOL_RAIL_ORIGIN,
		EDITOR_TOOL_BUTTON_SIZE,
		len(BUILD_MODE_GRID),
		EDITOR_TOOL_RAIL_BOX,
	)}
build_tool_grid_rect :: proc(index: int) -> Rect {return editor_vertical_stack_item(
		editor_tool_rail_rect(),
		index,
		EDITOR_TOOL_BUTTON_SIZE,
		EDITOR_TOOL_RAIL_BOX,
	)}
build_mode_for_tool :: proc(tool: Build_Tool) -> Build_Tool {#partial switch
	tool {case .Room, .Wall, .Door, .Window:
		return .Room; case .Paint, .Wall_Paint:
		return .Paint; case .Plant, .Light:
		return .Plant}
	return tool}
editor_activate_build_mode :: proc(g: ^Game, mode: Build_Tool) {
	g.build_tool =
		mode; current_kind, current_found := catalog_entry_kind(editor_state.catalog_id); wanted: Catalog_Entry_Kind = mode == .Plant ? .Object : mode == .Paint ? .Material : current_kind
	if (mode == .Plant || mode == .Paint) &&
	   (!current_found ||
			   current_kind !=
				   wanted) {for entry in editor_catalog.entries do if entry.kind == wanted {editor_state.catalog_id = entry.id; break}}
	editor_show_feedback(fmt.tprintf("TOOL  ·  %s", editor_build_tool_name(mode)))
}
build_subtool_rect :: proc(index: int) -> Rect {return {82 + f32(index) * 52, 144, 42, 42}}
editor_opening_parameter_rect :: proc(index: int) -> Rect {x := [4]f32{78, 180, 224, 326}; return{
		x[clamp(index, 0, 3)],
		188,
		38,
		26,
	}}
editor_paint_target_rect :: proc(index: int) -> Rect {return {78 + f32(index) * 48, 144, 42, 42}}
editor_paint_eyedropper_rect :: proc() -> Rect {return {238, 144, 42, 42}}
editor_foundation_kind_rect :: proc(index: int) -> Rect {return{78 + f32(index) * 48, 140, 42, 42}}
editor_foundation_mode_rect :: proc(index: int) -> Rect {return{
		334 + f32(index) * 46,
		144,
		38,
		38,
	}}
editor_foundation_measure_rect :: proc(index: int) -> Rect {return{
		238 + f32(index) * 46,
		144,
		38,
		30,
	}}
editor_terrain_mode_rect :: proc(index: int) -> Rect {return {78 + f32(index) * 44, 140, 38, 38}}
editor_terrain_parameter_rect :: proc(index: int) -> Rect {x := [4]f32{78, 180, 224, 326}; return{
		x[clamp(index, 0, 3)],
		184,
		38,
		28,
	}}
editor_marker_kind_rect :: proc(index: int) -> Rect {return {78 + f32(index) * 42, 140, 38, 38}}
editor_marker_parameter_rect :: proc(index: int) -> Rect {return{
		78 + f32(index) * 42 + (index >= 2 ? 4 : 0),
		202,
		38,
		26,
	}}
editor_light_kind_rect :: proc() -> Rect {return {78, 206, 82, 30}}
editor_light_parameter_rect :: proc(index: int) -> Rect {return{
		168 + f32(index) * 46,
		206,
		38,
		30,
	}}
editor_light_panel_rect :: proc() -> Rect {return {74, 194, 328, 78}}
editor_roof_style_rect :: proc() -> Rect {return {78, 144, 82, 30}}
editor_roof_parameter_rect :: proc(index: int) -> Rect {width := index == 4 ? f32(46) : f32(38)
	return {168 + f32(index) * 46, 144, width, 30}}
editor_roof_panel_rect :: proc() -> Rect {return {74, 132, 418, 78}}
editor_link_kind_rect :: proc() -> Rect {return {78, 144, 92, 30}}
editor_link_width_rect :: proc(index: int) -> Rect {return {178 + f32(index) * 46, 144, 38, 30}}
editor_water_height_rect :: proc(index: int) -> Rect {return {78 + f32(index) * 62, 144, 54, 30}}
editor_catalog_search_rect :: proc() -> Rect {return {86, 238, 226, 30}}
editor_catalog_search_clear_rect :: proc() -> Rect {return {316, 238, 30, 30}}
editor_catalog_card_rect :: proc(index: int) -> Rect {return{
		86 + f32(index % 3) * 88,
		276 + f32(index / 3) * 80,
		80,
		70,
	}}
editor_catalog_pin_rect :: proc(index: int) -> Rect {card := editor_catalog_card_rect(index)
	return {card.x + card.w - 22, card.y + 4, 18, 18}}
editor_catalog_empty_action_rect :: proc() -> Rect {return {132, 316, 168, 30}}
editor_selection_inspector_rect :: proc() -> Rect {return {938, 124, 250, 128}}
editor_roof_inspector_rect :: proc() -> Rect {return {938, 124, 250, 238}}
editor_roof_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Roof_Pitch ? 174 : field == .Roof_Overhang ? 210 : f32(246)
	return{952, y, 222, 30}}
editor_roof_edit_rect :: proc() -> Rect {return {952, 318, 178, 28}}
editor_roof_delete_rect :: proc() -> Rect {return {1138, 318, 36, 28}}
editor_begin_roof_edit :: proc(g: ^Game, roof_id: string) -> bool {index := level_roof_index(
		&level_document,
		roof_id,
	)
	if index < 0 do return false
	roof := level_document.roofs[index]
	editor_state.roof_style = roof.style
	editor_state.roof_pitch = roof.pitch
	editor_state.roof_overhang = roof.overhang
	editor_state.roof_ridge_angle = roof.ridge_angle
	editor_state.roof_gutters = roof.gutters
	g.build_tool = .Roof
	editor_state.roof_hover = {.Room, roof.room_id, -1}
	editor_state.roof_hover_active = true
	editor_state.roof_preview = level_preview_transaction(
		&level_document,
		Level_Command {
			kind = .Set_Roof,
			entity_id = roof.id,
			material = roof.room_id,
			a = {f32(roof.style), roof.ridge_angle},
			b = {roof.overhang, roof.gutters ? 1 : 0},
			value = roof.pitch,
		},
	)
	return true}
editor_view_pick_selection :: proc(
	doc: ^Level_Document,
	view: Editor_View_Mode,
	picked: Editor_Selection,
) -> Editor_Selection {if view == .Roof && picked.kind == .Room {roof_index := level_roof_for_room(
			doc,
			picked.entity_id,
		)
		if roof_index >= 0 do return {.Roof, doc.roofs[roof_index].id, -1}}
	return picked}
editor_object_inspector_rect :: proc() -> Rect {return {938, 124, 250, 244}}
editor_opening_inspector_rect :: proc() -> Rect {return {938, 124, 250, 230}}
editor_room_inspector_rect :: proc() -> Rect {return {938, 124, 250, 210}}
editor_compact_inspector_step_rect :: proc(y: f32, direction: int) -> Rect {return{
		direction < 0 ? f32(946) : f32(1142),
		y,
		38,
		30,
	}}
editor_room_material_rect :: proc(walls: bool) -> Rect {return{
		walls ? f32(1066) : f32(946),
		202,
		112,
		24,
	}}
editor_room_roof_rect :: proc() -> Rect {return {946, 230, 232, 24}}
editor_inspector_step_rect :: proc(y: f32, direction: int) -> Rect {return{
		direction < 0 ? f32(920) : f32(1138),
		y,
		38,
		30,
	}}
editor_light_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Light_Range ? 248 : field == .Light_Intensity ? 294 : field == .Light_Height ? 340 : field == .Light_Facing ? 386 : f32(432)
	return{964, y, 170, 30}}
editor_light_duplicate_rect :: proc() -> Rect {return {1098, 136, 34, 28}}
editor_light_delete_rect :: proc() -> Rect {return {1140, 136, 34, 28}}
editor_light_color_rect :: proc(kind: Level_Light_Kind, index: int) -> Rect {return{
		990 + f32(index) * 30,
		214,
		24,
		22,
	}}
editor_light_current_color_rect :: proc() -> Rect {return {958, 214, 24, 22}}
editor_marker_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Marker_Radius ? 318 : field == .Marker_Facing ? 354 : f32(390)
	return{964, y, 170, 30}}
editor_marker_position_rect :: proc(field: Editor_Numeric_Field) -> Rect {return{
		field == .Marker_X ? f32(920) : f32(1040),
		286,
		114,
		26,
	}}
editor_marker_duplicate_rect :: proc() -> Rect {return {1098, 136, 34, 28}}
editor_marker_delete_rect :: proc() -> Rect {return {1140, 136, 34, 28}}
editor_marker_open_graph_rect :: proc() -> Rect {return {920, 438, 254, 28}}
editor_inspector_clear_rect :: proc(y: f32) -> Rect {return {1096, y, 38, 30}}
editor_diagnostic_rect :: proc(index: int) -> Rect {return{
		820,
		132 + f32(max(index, 0)) * 48,
		354,
		42,
	}}
editor_view_menu_panel_rect :: proc() -> Rect {return {308, 52, 218, 184}}
editor_view_menu_rect :: proc(index: int) -> Rect {i := clamp(index, 0, len(Editor_View_Mode) - 1)
	return {314 + f32(i / 5) * 104, 58 + f32(i % 5) * 34, 100, 30}}
editor_snap_rect :: proc() -> Rect {return {1034, 648, 150, 32}}
editor_shortcut_help_rect :: proc() -> Rect {return {994, 648, 32, 32}}
editor_multi_action_rect :: proc(index: int) -> Rect {x := [7]f32 {
		514,
		556,
		598,
		660,
		730,
		772,
		814,
	}
	width := [7]f32{36, 36, 56, 64, 38, 36, 36}
	i := clamp(index, 0, 6)
	return{x[i], 608, width[i], 28}}
FOLIAGE_COLOR_PALETTE := [6][4]u8 {
	{255, 255, 255, 255},
	{111, 76, 48, 255},
	{67, 43, 30, 255},
	{74, 132, 70, 255},
	{130, 169, 74, 255},
	{184, 91, 67, 255},
}
LIGHT_COLOR_PALETTE := [6][4]u8 {
	{255, 236, 196, 255},
	{255, 255, 255, 255},
	{200, 225, 255, 255},
	{255, 184, 112, 255},
	{255, 142, 126, 255},
	{154, 184, 255, 255},
}
ROOM_TINT_PALETTE := [6][4]u8 {
	{255, 255, 255, 255},
	{232, 218, 196, 255},
	{207, 177, 142, 255},
	{194, 211, 218, 255},
	{179, 204, 177, 255},
	{196, 178, 204, 255},
}
editor_room_tint_rect :: proc(walls: bool, index: int) -> Rect {return{
		1018 + f32(index) * 25,
		walls ? f32(294) : f32(270),
		20,
		18,
	}}
editor_object_color_rect :: proc(row, index: int) -> Rect {return{
		1018 + f32(index) * 25,
		326 + f32(row) * 24,
		20,
		18,
	}}
editor_object_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Object_Height ? 174 : field == .Object_Angle ? 210 : field == .Object_X ? 246 : f32(282)
	return{990, y, 144, 30}}
editor_opening_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Opening_Position ? 198 : field == .Opening_Width ? 234 : field == .Opening_Height ? 270 : f32(306)
	return{952, y, 222, 30}}
editor_compact_numeric_rect :: proc(field: Editor_Numeric_Field) -> Rect {y :=
		field == .Room_Level ? 174 : f32(198)
	return{990, y, 144, 30}}
editor_numeric_text :: proc() -> string {return string(
		editor_state.numeric_buffer[:editor_state.numeric_count],
	)}
editor_cancel_numeric_edit :: proc() {editor_state.numeric_field = .None
	editor_state.numeric_count = 0
	editor_state.numeric_replace_on_input = false}
editor_begin_numeric_edit :: proc(field: Editor_Numeric_Field, value: f32) {
	editor_state.numeric_field =
		field; editor_state.numeric_count = 0; editor_state.numeric_replace_on_input = true
	formatted :=
		field == .Object_Angle || field == .Roof_Pitch || field == .Roof_Ridge || field == .Light_Facing || field == .Light_Cone || field == .Marker_Facing ? fmt.tprintf("%.0f", value) : fmt.tprintf("%.2f", value)
	for byte in transmute([]u8)formatted {if editor_state.numeric_count >= len(editor_state.numeric_buffer) do break
		editor_state.numeric_buffer[editor_state.numeric_count] = byte
		editor_state.numeric_count += 1}
}
editor_append_numeric_char :: proc(
	value: u8,
) -> bool {if editor_state.numeric_replace_on_input {editor_state.numeric_count = 0
		editor_state.numeric_replace_on_input = false}
	if editor_state.numeric_count >= len(editor_state.numeric_buffer) do return false
	if value ==
	   '.' {for byte in editor_state.numeric_buffer[:editor_state.numeric_count] do if byte == '.' do return false}
	if value == '-' && editor_state.numeric_count != 0 do return false
	editor_state.numeric_buffer[editor_state.numeric_count] = value
	editor_state.numeric_count += 1
	return true}
editor_commit_numeric_edit :: proc() -> bool {
	if editor_state.numeric_field == .None do return false
	value, ok := strconv.parse_f32(
		editor_numeric_text(),
	); if !ok {editor_show_feedback("ENTER A VALID NUMBER", true); return false}
	if editor_state.selection_count !=
	   1 {editor_cancel_numeric_edit(); return false}; selected := editor_state.selection[0]; command := Level_Command{}; label := "Edit value"
	if selected.kind ==
	   .Object {index := level_object_index(&level_document, selected.entity_id); if index < 0 {editor_cancel_numeric_edit(); return false}; object := level_document.objects[index]; #partial switch editor_state.numeric_field {case .Object_Height:
			command = {
				kind      = .Set_Object_Elevation,
				entity_id = object.id,
				value     = clamp(value, -5, 20),
			}; label = "Set object height"; case .Object_Angle:
			command = {
				kind      = .Move_Object,
				entity_id = object.id,
				a         = object.position,
				value     = value,
			}; label = "Set object angle"; case .Object_X:
			command = {
				kind      = .Move_Object,
				entity_id = object.id,
				a         = {value, object.position.y},
				value     = object.rotation,
			}; label = "Set object X"; case .Object_Y:
			command = {
				kind      = .Move_Object,
				entity_id = object.id,
				a         = {object.position.x, value},
				value     = object.rotation,
			}; label = "Set object Y"; case:
			editor_cancel_numeric_edit()
			return(
				false \
			)}} else if selected.kind == .Opening {index := level_opening_index(&level_document, selected.entity_id); if index < 0 {editor_cancel_numeric_edit(); return false}; opening := level_document.openings[index]; command = {
			kind        = .Set_Opening,
			entity_id   = opening.id,
			material    = opening.host_path,
			destination = door_material_name(opening.door_material),
			value       = f32(opening.segment),
			b           = {f32(opening.kind), opening.width},
			c           = {opening.position, opening.height},
		}; command.points[0] = {
			opening.sill_height,
			f32(opening.window_style),
		}; command.points[1] = {opening.window_flipped ? 1 : 0, opening.window_hinge_right ? 1 : 0}; #partial switch editor_state.numeric_field {case .Opening_Position:
			command.c.x = clamp(value, 0, 100) / 100
			label = "Set opening position"; case .Opening_Width:
			command.b.y = clamp(value, .4, 6); label = "Set opening width"; case .Opening_Height:
			command.c.y = clamp(value, .4, 4); label = "Set opening height"; case .Opening_Sill:
			if opening.kind != .Window {editor_cancel_numeric_edit(); return false}
			command.points[0].x = clamp(value, .2, 2)
			label = "Set window sill"; case:
			editor_cancel_numeric_edit()
			return(
				false \
			)}} else if selected.kind == .Room || selected.kind == .Edge || selected.kind == .Vertex {index := level_room_index(&level_document, selected.entity_id); if index < 0 || editor_state.numeric_field != .Room_Level {editor_cancel_numeric_edit(); return false}; room := level_document.rooms[index]; command = {
			kind      = .Set_Platform,
			entity_id = room.id,
			value     = clamp(value, -5, 10),
		}; label = "Set room level"} else if selected.kind == .Foundation {index := level_foundation_index(&level_document, selected.entity_id); if index < 0 || editor_state.numeric_field != .Foundation_Measure {editor_cancel_numeric_edit(); return false}; foundation := level_document.foundations[index]; minimum := foundation.kind == .Basement ? f32(1.8) : foundation.kind == .Raised ? f32(.25) : f32(.1); maximum := foundation.kind == .Basement ? f32(6) : foundation.kind == .Raised ? f32(3) : f32(1); measure := clamp(value, minimum, maximum); command = {
			kind      = .Set_Foundation,
			entity_id = foundation.id,
			value     = foundation.elevation,
			c         = {f32(foundation.kind), foundation.depth},
		}; if foundation.kind == .Raised do command.value = measure
		else do command.c.y = measure; label = "Set foundation measure"} else if selected.kind == .Path {index := level_path_index(&level_document, selected.entity_id); if index < 0 || editor_state.numeric_field != .Path_Width {editor_cancel_numeric_edit(); return false}; path := level_document.paths[index]; minimum := path.kind == .Wall ? f32(.1) : f32(.2); maximum := path.kind == .Wall ? f32(1) : f32(8); command = {
			kind      = .Set_Path,
			entity_id = path.id,
			value     = clamp(value, minimum, maximum),
		}; label = "Set path width"} else if selected.kind == .Water {index := level_water_index(&level_document, selected.entity_id); if index < 0 || editor_state.numeric_field != .Water_Surface {editor_cancel_numeric_edit(); return false}; water := level_document.waters[index]; command = {
			kind      = .Set_Water,
			entity_id = water.id,
			value     = clamp(value, -5, 5),
		}; label = "Set water surface"} else if selected.kind == .Vertical_Link {index := level_vertical_link_index(&level_document, selected.entity_id); if index < 0 || editor_state.numeric_field != .Link_Width {editor_cancel_numeric_edit(); return false}; link := level_document.vertical_links[index]; command = {
			kind      = .Set_Vertical_Link,
			entity_id = link.id,
			value     = clamp(value, .6, 3),
		}; label = "Set link width"} else if selected.kind == .Roof {index := level_roof_index(&level_document, selected.entity_id); if index < 0 {editor_cancel_numeric_edit(); return false}; roof := level_document.roofs[index]; command = {
			kind      = .Set_Roof,
			entity_id = roof.id,
			material  = roof.room_id,
			a         = {f32(roof.style), roof.ridge_angle},
			b         = {roof.overhang, roof.gutters ? 1 : 0},
			value     = roof.pitch,
		}; #partial switch editor_state.numeric_field {case .Roof_Pitch:
			command.value = clamp(value, 1, 75); label = "Set roof pitch"; case .Roof_Overhang:
			command.b.x = clamp(value, 0, 2); label = "Set roof overhang"; case .Roof_Ridge:
			command.a.y = value; label = "Set roof ridge angle"; case:
			editor_cancel_numeric_edit()
			return(
				false \
			)}} else if selected.kind == .Light {index := level_light_index(&level_document, selected.entity_id); if index < 0 {editor_cancel_numeric_edit(); return false}; light := level_document.lights[index]; command = {
			kind      = .Set_Light,
			entity_id = light.id,
			a         = light.position,
			b         = {light.range, light.intensity},
			c         = {light.elevation, f32(light.kind)},
			value     = light.facing,
			color     = light.color,
		}; command.points[0] = {
			light.cone_angle,
			0,
		}; #partial switch editor_state.numeric_field {case .Light_Range:
			command.b.x = clamp(value, .5, 40); label = "Set light range"; case .Light_Intensity:
			command.b.y = clamp(value, .1, 100); label = "Set light intensity"; case .Light_Height:
			command.c.x = clamp(value, 0, 20); label = "Set light height"; case .Light_Facing:
			if light.kind == .Point {editor_cancel_numeric_edit(); return false}
			command.value = value
			label = "Set light facing"; case .Light_Cone:
			if light.kind != .Spot {editor_cancel_numeric_edit(); return false}
			command.points[0].x = clamp(value, 5, 160)
			label = "Set spotlight cone"; case:
			editor_cancel_numeric_edit()
			return(
				false \
			)}} else if selected.kind == .Marker {index := level_marker_index(&level_document, selected.entity_id); if index < 0 {editor_cancel_numeric_edit(); return false}; marker := level_document.markers[index]; command = marker_edit_command(marker); #partial switch editor_state.numeric_field {case .Marker_X:
			command.a.x = clamp(value, 0, f32(level_document.width))
			label = "Set marker X"; case .Marker_Y:
			command.a.y = clamp(value, 0, f32(level_document.height))
			label = "Set marker Y"; case .Marker_Radius:
			command.b.x = clamp(value, .1, 12); label = "Set marker radius"; case .Marker_Facing:
			command.b.y = value; label = "Set marker facing"; case .Marker_Height:
			if marker.kind != .Camera {editor_cancel_numeric_edit(); return false}
			command.c.x = clamp(value, .1, 20)
			label = "Set camera marker height"; case:
			editor_cancel_numeric_edit()
			return false}} else {editor_cancel_numeric_edit(); return false}
	if !level_commit_transaction(
		&level_document,
		command,
		label,
	) {editor_show_feedback("VALUE BLOCKED BY PLACEMENT RULES", true); return false}; editor_cancel_numeric_edit(); editor_show_feedback("VALUE UPDATED  ·  CTRL/CMD Z TO UNDO"); return true
}
editor_advance_numeric_edit :: proc(direction: int) -> bool {
	current := editor_state.numeric_field; if current == .None do return false
	if !editor_commit_numeric_edit() do return false
	if editor_state.selection_count != 1 do return true; selected := editor_state.selection[0]
	if selected.kind ==
	   .Object {index := level_object_index(&level_document, selected.entity_id); if index < 0 do return true; object := level_document.objects[index]; fields := [4]Editor_Numeric_Field{.Object_Height, .Object_Angle, .Object_X, .Object_Y}; values := [4]f32{object.elevation, object.rotation, object.position.x, object.position.y}; current_index := 0; for field, i in fields do if field == current {current_index = i; break}; next := (current_index + (direction < 0 ? -1 : 1) + len(fields)) % len(fields); editor_begin_numeric_edit(fields[next], values[next]); return true}
	if selected.kind ==
	   .Opening {index := level_opening_index(&level_document, selected.entity_id); if index < 0 do return true; opening := level_document.openings[index]; fields := [4]Editor_Numeric_Field{.Opening_Position, .Opening_Width, .Opening_Height, .Opening_Sill}; values := [4]f32{opening.position * 100, opening.width, opening.height, opening.sill_height}; count := opening.kind == .Window ? 4 : 3; current_index := 0; for i in 0 ..< count do if fields[i] == current {current_index = i; break}; next := (current_index + (direction < 0 ? -1 : 1) + count) % count; editor_begin_numeric_edit(fields[next], values[next]); return true}
	if selected.kind ==
	   .Roof {index := level_roof_index(&level_document, selected.entity_id); if index < 0 do return true; roof := level_document.roofs[index]; fields := [3]Editor_Numeric_Field{.Roof_Pitch, .Roof_Overhang, .Roof_Ridge}; values := [3]f32{roof.pitch, roof.overhang, roof.ridge_angle}; current_index := 0; for field, i in fields do if field == current {current_index = i; break}; next := (current_index + (direction < 0 ? -1 : 1) + len(fields)) % len(fields); editor_begin_numeric_edit(fields[next], values[next]); return true}
	if selected.kind ==
	   .Light {index := level_light_index(&level_document, selected.entity_id); if index < 0 do return true; light := level_document.lights[index]; fields := [5]Editor_Numeric_Field{.Light_Range, .Light_Intensity, .Light_Height, .Light_Facing, .Light_Cone}; values := [5]f32{light.range, light.intensity, light.elevation, light.facing, light.cone_angle}; count := light.kind == .Spot ? 5 : light.kind == .Area ? 4 : 3; current_index := 0; for i in 0 ..< count do if fields[i] == current {current_index = i; break}; next := (current_index + (direction < 0 ? -1 : 1) + count) % count; editor_begin_numeric_edit(fields[next], values[next]); return true}
	if selected.kind ==
	   .Marker {index := level_marker_index(&level_document, selected.entity_id); if index < 0 do return true; marker := level_document.markers[index]; fields := [5]Editor_Numeric_Field{.Marker_X, .Marker_Y, .Marker_Radius, .Marker_Facing, .Marker_Height}; values := [5]f32{marker.position.x, marker.position.y, marker.radius, marker.facing, marker.camera_height}; count := marker.kind == .Camera ? 5 : 4; current_index := 0; for i in 0 ..< count do if fields[i] == current {current_index = i; break}; next := (current_index + (direction < 0 ? -1 : 1) + count) % count; editor_begin_numeric_edit(fields[next], values[next]); return true}
	return true
}
editor_selection_uses_compact_inspector :: proc(kind: Editor_Selection_Kind) -> bool {return(
		kind == .Room ||
		kind == .Vertex ||
		kind == .Edge ||
		kind == .Opening ||
		kind == .Object ||
		kind == .Foundation ||
		kind == .Path ||
		kind == .Water ||
		kind == .Vertical_Link ||
		kind == .Roof \
	)}
editor_selection_toolbar_position :: proc(screen: Vec2) -> Vec2 {return{
		clamp(screen.x - 120, f32(90), f32(944)),
		clamp(screen.y + 10, f32(94), f32(614)),
	}}
gameplay_attributes_rect :: proc() -> Rect {return {846, 660, 108, 42}}
gameplay_notebook_rect :: proc() -> Rect {return {958, 660, 108, 42}}
gameplay_theory_rect :: proc() -> Rect {return {1070, 660, 114, 42}}
editor_status_hint_x :: proc(width: f32) -> f32 {return clamp(
		547 - width * .5,
		f32(82),
		f32(1018) - width,
	)}
editor_segment_length :: proc(a, b: Vec2) -> f32 {dx, dy := b.x - a.x, b.y - a.y; return f32(
		math.sqrt(f64(dx * dx + dy * dy)),
	)}
editor_polyline_length :: proc(points: []Vec2) -> f32 {total: f32 = 0; for i in 1 ..< len(points) do total += editor_segment_length(points[i - 1], points[i])
	return total}
editor_polygon_preview_area :: proc(points: []Vec2, cursor: Vec2) -> f32 {
	if len(points) < 2 do return 0
	preview: [33]Vec2
	count := min(len(points), 32)
	copy(preview[:count], points[:count])
	preview[count] = cursor
	return math.abs(level_polygon_area(preview[:count + 1]))
}
editor_top_close_rect :: proc() -> Rect {return {14, 14, 44, 34}}
editor_top_save_rect :: proc() -> Rect {return {68, 14, 82, 34}}
editor_top_undo_rect :: proc() -> Rect {return {160, 14, 68, 34}}
editor_top_redo_rect :: proc() -> Rect {return {236, 14, 68, 34}}
editor_top_view_rect :: proc() -> Rect {return {314, 14, 108, 34}}
editor_top_validate_rect :: proc() -> Rect {return {432, 14, 90, 34}}
editor_top_story_down_rect :: proc() -> Rect {return {780, 11, 40, 40}}
editor_top_story_up_rect :: proc() -> Rect {return {930, 11, 40, 40}}
editor_top_story_height_down_rect :: proc() -> Rect {return {822, 11, 28, 40}}
editor_top_story_height_up_rect :: proc() -> Rect {return {900, 11, 28, 40}}
editor_top_recovery_rect :: proc() -> Rect {return {980, 14, 102, 34}}
editor_exit_save_rect :: proc() -> Rect {return {330, 438, 166, 38}}
editor_exit_autosave_rect :: proc() -> Rect {return {516, 438, 238, 38}}
editor_exit_cancel_rect :: proc() -> Rect {return {774, 438, 96, 38}}
editor_top_play_rect :: proc() -> Rect {return {1090, 14, 92, 34}}
editor_roof_gutters_rect :: proc() -> Rect {return {406, 144, 82, 30}}
editor_roof_apply_rect :: proc() -> Rect {return {406, 176, 82, 28}}
editor_apply_roof_preview :: proc() -> bool {if !editor_state.roof_hover_active || editor_state.roof_preview.state == .Blocked do return false
	room_id := editor_state.roof_hover.entity_id
	existing := level_roof_for_room(&level_document, room_id)
	kind := existing >= 0 ? Level_Command_Kind.Set_Roof : .Create_Roof
	id := existing >= 0 ? level_document.roofs[existing].id : ""
	if !level_commit_transaction(&level_document, Level_Command{kind = kind, entity_id = id, material = room_id, a = {f32(editor_state.roof_style), editor_state.roof_ridge_angle}, b = {editor_state.roof_overhang, editor_state.roof_gutters ? 1 : 0}, value = editor_state.roof_pitch}, existing >= 0 ? "Update roof" : "Create roof") do return false
	editor_show_feedback(
		existing >= 0 ? "ROOF UPDATED  ·  CTRL/CMD Z TO UNDO" : "ROOF CREATED  ·  CTRL/CMD Z TO UNDO",
	)
	return true}
editor_submenu_block_rect :: proc() -> Rect {return {74, 128, 426, 90}}
editor_placement_rotated :: proc(rotation: f32, steps: int) -> f32 {value :=
		rotation + f32(steps) * 15
	for value < 0 do value += 360
	for value >= 360 do value -= 360
	return value}
editor_wheel_steps :: proc(delta: f32) -> int {if delta == 0 do return 0; steps := int(
		math.round(f64(delta)),
	)
	if steps == 0 do steps = delta > 0 ? 1 : -1
	return clamp(steps, -6, 6)}
editor_catalog_visible :: proc(tool: Build_Tool) -> bool {return(
		tool == .Plant ||
		tool == .Paint ||
		tool == .Wall_Paint \
	)}
editor_catalog_visible_count :: proc() -> int {total := catalog_match_count(&editor_state)
	return clamp(total - editor_state.catalog_page * 9, 0, 9)}
editor_catalog_rows :: proc() -> int {return max(1, (editor_catalog_visible_count() + 2) / 3)}
editor_catalog_footer_y :: proc() -> f32 {return 274 + f32(editor_catalog_rows()) * 80}
editor_catalog_panel_bottom :: proc(tool: Build_Tool) -> f32 {footer := editor_catalog_footer_y()
	return tool == .Plant ? footer + 76 : footer + 38}
editor_viewport_contains :: proc(point: Vec2, tool: Build_Tool) -> bool {if point.x <= 76 || point.x >= 1190 || point.y <= 62 || point.y >= 688 do return false
	if editor_state.view_menu_visible && contains(editor_view_menu_panel_rect(), point) do return false
	if contains(editor_submenu_block_rect(), point) || tool == .Light && contains(editor_light_panel_rect(), point) do return false
	if point.x >= 1028 && point.y >= 640 && point.y <= 684 do return false
	if editor_state.selection_count > 1 && point.x >= 350 && point.x <= 860 && point.y >= 600 && point.y <= 648 do return false
	if editor_state.diagnostics_visible && point.x >= 806 && point.y >= 70 && point.y <= 610 do return false
	if editor_state.selection_count > 0 && (editor_state.selection[0].kind == .Marker || editor_state.selection[0].kind == .Light) && point.x >= 906 && point.y >= 124 && point.y <= 470 do return false
	if editor_state.selection_count > 0 && (editor_state.selection[0].kind == .Room || editor_state.selection[0].kind == .Edge || editor_state.selection[0].kind == .Vertex) && contains(editor_room_inspector_rect(), point) do return false
	if editor_state.selection_count > 0 && editor_state.selection[0].kind == .Object && contains(editor_object_inspector_rect(), point) do return false
	if editor_state.selection_count > 0 && editor_state.selection[0].kind == .Opening && contains(editor_opening_inspector_rect(), point) do return false
	if editor_state.selection_count > 0 && editor_state.selection[0].kind == .Roof && contains(editor_roof_inspector_rect(), point) do return false
	if editor_state.selection_count > 0 && editor_selection_uses_compact_inspector(editor_state.selection[0].kind) && contains(editor_selection_inspector_rect(), point) do return false
	if editor_catalog_visible(tool) && point.x < 370 && point.y > 190 && point.y < editor_catalog_panel_bottom(tool) do return false
	return true}
EDITOR_CAMERA_MIN_ZOOM :: f32(.2)
editor_camera_scale :: proc(g: ^Game) -> f32 {return(
		g.camera_orbit_initialized ? clamp(g.camera_zoom, EDITOR_CAMERA_MIN_ZOOM, 2.5) : 1 \
	)}
editor_mouse_ground :: proc(
	g: ^Game,
	mouse: Vec2,
) -> (
	x, y: f32,
	ok: bool,
) {if !g.top_down_camera do return gameplay_mouse_ground(g, mouse); half := f32(
		math.tan(f64(math.PI / 6)),
	)
	aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT)
	scale := editor_camera_scale(g)
	nx := mouse.x / f32(WINDOW_WIDTH) * 2 - 1
	ny := 1 - mouse.y / f32(WINDOW_HEIGHT) * 2
	return g.camera_x + nx * 27.5 * scale * half * aspect,
		g.camera_y - ny * 27.5 * scale * half,
		true}
editor_world_screen :: proc(
	g: ^Game,
	point: Vec2,
) -> (
	screen: Vec2,
	visible: bool,
) {if !g.top_down_camera do return aerial_world_point_screen(g, point); half := f32(
		math.tan(f64(math.PI / 6)),
	)
	aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT)
	scale := editor_camera_scale(g)
	ndc_x := (point.x - g.camera_x) / (27.5 * scale * half * aspect)
	ndc_y := (g.camera_y - point.y) / (27.5 * scale * half)
	return {(ndc_x + 1) * .5 * f32(WINDOW_WIDTH), (1 - ndc_y) * .5 * f32(WINDOW_HEIGHT)},
		ndc_x >= -1 && ndc_x <= 1 && ndc_y >= -1 && ndc_y <= 1}
editor_update_build_camera :: proc(g: ^Game) {
	if !g.top_down_camera || editor_state.search_active || editor_state.numeric_field != .None || editor_state.shortcut_help_visible || editor_state.exit_confirm_visible || editor_state.view_menu_visible do return
	control := g.keys[.LCTRL] || g.keys[.RCTRL] || g.keys[.LGUI] || g.keys[.RGUI]
	if !control {dx := f32(0); dy := f32(0); if g.keys[.A] do dx -= 1; if g.keys[.D] do dx += 1; if g.keys[.W] do dy -= 1; if g.keys[.S] do dy += 1; if dx != 0 || dy != 0 {length := f32(math.sqrt(f64(dx * dx + dy * dy))); speed := .18 * editor_camera_scale(g); g.camera_x += dx / length * speed; g.camera_y += dy / length * speed; g.camera_initialized = true}}
	if g.input.mouse_wheel == 0 || g.build_tool == .Plant || !editor_viewport_contains(g.input.mouse_pos, g.build_tool) do return
	before_x, before_y, before_ok := editor_mouse_ground(g, g.input.mouse_pos)
	g.camera_zoom = clamp(
		editor_camera_scale(g) - g.input.mouse_wheel * .1,
		EDITOR_CAMERA_MIN_ZOOM,
		2.5,
	); g.camera_orbit_initialized = true
	after_x, after_y, after_ok := editor_mouse_ground(g, g.input.mouse_pos)
	if before_ok && after_ok {g.camera_x += before_x - after_x; g.camera_y += before_y - after_y}
}
editor_frame_zoom :: proc(minimum, maximum: Vec2, count: int) -> f32 {if count <= 1 do return .65
	span_x, span_y := maximum.x - minimum.x, maximum.y - minimum.y
	return clamp(max(span_x / 25, span_y / 16) * 1.2, .45, 1.65)}
editor_frame_selection :: proc(g: ^Game) -> bool {
	if editor_state.selection_count <=
	   0 {editor_show_feedback("SELECT SOMETHING TO FRAME", true); return false}
	minimum := Vec2{1e30, 1e30}; maximum := Vec2{-1e30, -1e30}; count := 0
	for selection in editor_state.selection[:editor_state.selection_count] {position, ok := level_selection_position(&level_document, selection); if !ok do continue; minimum.x = min(minimum.x, position.x); minimum.y = min(minimum.y, position.y); maximum.x = max(maximum.x, position.x); maximum.y = max(maximum.y, position.y); count += 1}
	if count == 0 {editor_show_feedback("SELECTION CANNOT BE FRAMED", true); return false}
	g.camera_x =
		(minimum.x + maximum.x) *
		.5; g.camera_y = (minimum.y + maximum.y) * .5; g.camera_zoom = editor_frame_zoom(minimum, maximum, count); g.camera_initialized = true; g.camera_orbit_initialized = true; editor_show_feedback(count == 1 ? "FRAMED SELECTION" : "FRAMED SELECTION SET"); return true
}

marker_edit_command :: proc(marker: Level_Marker) -> Level_Command {return{
		kind = .Set_Marker,
		entity_id = marker.id,
		a = marker.position,
		b = {marker.radius, marker.facing},
		c = {marker.camera_height, f32(marker.kind)},
		material = marker.reference,
		destination = marker.destination,
		value = f32(marker.story),
	}}
editor_marker_name_rect :: proc() -> Rect {return {918, 153, 210, 26}}
editor_marker_name_text :: proc() -> string {return string(
		editor_state.marker_name_buffer[:editor_state.marker_name_count],
	)}
editor_begin_marker_name_edit :: proc(marker: Level_Marker) {editor_state.marker_name_active = true
	editor_state.marker_name_count = min(len(marker.id), len(editor_state.marker_name_buffer))
	copy(
		editor_state.marker_name_buffer[:editor_state.marker_name_count],
		transmute([]u8)marker.id,
	)}
editor_cancel_marker_name_edit :: proc() {editor_state.marker_name_active = false
	editor_state.marker_name_count = 0}
editor_commit_marker_name_edit :: proc() -> bool {if !editor_state.marker_name_active || editor_state.selection_count != 1 do return false
	old_id := editor_state.selection[0].entity_id
	index := level_marker_index(&level_document, old_id)
	if index < 0 do return false
	new_id := strings.trim_space(editor_marker_name_text())
	marker := level_document.markers[index]
	command := marker_edit_command(marker)
	command.interaction_prompt = new_id
	if !level_commit_transaction(&level_document, command, "Rename marker") {editor_show_feedback(
			"MARKER NAME MUST BE UNIQUE AND USE A-Z, 0-9, _",
			true,
		)
		return false}
	graph_refs_changed := false
	for 	&node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera ==
		   old_id {if !graph_refs_changed do graph_history_push("Rename spatial marker")
			node.beat.camera = new_id
			graph_refs_changed = true}
		if node.beat.actor_mark == old_id {if !graph_refs_changed do graph_history_push("Rename spatial marker")
			node.beat.actor_mark = new_id
			graph_refs_changed = true}}
	if graph_refs_changed do graph_changed()
	editor_state.selection[0].entity_id = new_id
	editor_cancel_marker_name_edit()
	editor_show_feedback("MARKER RENAMED  ·  GRAPH REFERENCES UPDATED")
	return true}
light_edit_command :: proc(light: Level_Light) -> Level_Command {command := Level_Command {
		kind      = .Set_Light,
		entity_id = light.id,
		a         = light.position,
		b         = {light.range, light.intensity},
		c         = {light.elevation, f32(light.kind)},
		value     = light.facing,
		color     = light.color,
	}; command.points[0] = {light.cone_angle, 0}; return command}
marker_binding_next_in :: proc(
	doc: ^Level_Document,
	g: ^Game,
	marker: Level_Marker,
	direction: int,
) -> string {
	options: [128]string; count := 0
	payload := mystery_game_payload(g)
	#partial switch marker.kind {
	case .Character_Spawn:
		if g.story_project != nil do for value in g.story_project.entities {if value.kind == "character" && count < len(options) {options[count] = value.id; count += 1}}
	case .Interaction:
		if payload != nil do for value in payload.pois {if count < len(options) {options[count] = value.entity_id; count += 1}}
	case .Clue:
		if payload != nil do for value in payload.clues {if count < len(options) {options[count] = value.id; count += 1}}
	case .Trigger:
		if g.story_project != nil do for value in g.story_project.events {if count < len(options) {options[count] = value.id; count += 1}}
	case .Transition:
		for value in doc.markers {if value.id != marker.id && count < len(options) {options[count] = value.id; count += 1}}
	case:
		return ""
	}
	if count == 0 do return ""; current := -1; binding := marker.kind == .Transition ? marker.destination : marker.reference; for value, i in options[:count] do if value == binding do current = i; if current < 0 do return direction < 0 ? options[count - 1] : options[0]; return options[(current + direction + count) % count]
}
marker_binding_next :: proc(
	g: ^Game,
	marker: Level_Marker,
	direction: int,
) -> string {return marker_binding_next_in(&level_document, g, marker, direction)}
editor_open_marker_in_graph :: proc(g: ^Game, marker: Level_Marker) -> bool {
	for &node, i in graph_document.nodes[:graph_document.node_count] {
		matches := node.beat.camera == marker.id || node.beat.actor_mark == marker.id
		if marker.kind == .Interaction && marker.reference != "" do matches = matches || node.beat.interaction == marker.reference
		if marker.kind == .Trigger && marker.reference != "" do matches = matches || node.beat.event_id == marker.reference
		if !matches do continue
		scene := graph_scene_index(node.beat.scene); if scene < 0 do continue
		graph_state.active_scene =
			scene; graph_state.view = .Graph; graph_select_only(i); _ = graph_frame_nodes(true); g.editor_mode = .Graph; g.move_target_active = false; graph_feedback(fmt.tprintf("OPENED FROM BUILD  ·  %s", strings.to_upper(marker.id))); return true
	}
	editor_show_feedback("NO GRAPH NODE REFERENCES THIS MARKER", true); return false
}
editor_open_marker_in_mystery :: proc(g: ^Game, marker: Level_Marker) -> bool {
	payload := mystery_payload(
		&active_story_project,
	); if payload == nil || marker.reference == "" do return false
	kind := Mystery_Authoring_Record_Kind.Clue; index := -1
	#partial switch marker.kind {
	case .Character_Spawn:
		kind = .Character; index = mystery_authoring_character_index(payload, marker.reference)
	case .Interaction:
		kind = .POI; index = mystery_authoring_poi_index(payload, marker.reference)
	case .Clue:
		kind = .Clue; index = mystery_clue_index(payload, marker.reference)
	case .Trigger:
		kind = .Event; index = mystery_authoring_event_index(payload, marker.reference)
	case:
		return false
	}
	if index < 0 do return false
	authoring_workspace.tab = .Mystery; authoring_workspace.selected_category = int(kind); authoring_workspace.selected_record = index; authoring_workspace.feedback = fmt.tprintf("OPENED FROM BUILD · %v · %s", kind, marker.reference); g.editor_mode = .None; g.screen = .Authoring; g.move_target_active = false; return true
}
editor_view_name :: proc(view: Editor_View_Mode) -> string {#partial switch view {case .Top_Down:
		return "TOP DOWN"; case .Active_Story:
		return "ACTIVE"; case .Stories_Below:
		return "BELOW"; case .Cutaway:
		return "CUTAWAY"; case .Roof:
		return "ROOF"; case .Collision:
		return "COLLISION"; case .Navmesh:
		return "NAVMESH"; case .Lighting:
		return "LIGHTING"; case .Markers:
		return "MARKERS"}; return "ISOMETRIC"}
editor_snap_name :: proc() -> string {if editor_state.snap_suspended do return "NO SNAP  ALT"
	switch editor_state.snap_mode {case .Fine:
		return fmt.tprintf("SNAP %.2fm", level_document.fine_snap); case .Off:
		return "SNAP OFF"; case .Construction:
		return fmt.tprintf("SNAP %.2fm", level_document.default_snap)}
	return "SNAP"}
editor_paint_command_kind :: proc(
	target: Paint_Target,
	whole_room := false,
) -> Level_Command_Kind {if whole_room || target == .Room do return .Paint_Room; if target == .Walls do return .Paint_Walls
	return .Paint_Floor}
editor_room_sample_material :: proc(
	room: Level_Room,
	target: Paint_Target,
) -> string {if target == .Walls do return room.wall_material; return room.floor_material}
editor_effective_terrain_mode :: proc(
	mode: Terrain_Brush_Mode,
	invert: bool,
) -> Terrain_Brush_Mode {if !invert do return mode; if mode == .Raise do return .Lower; if mode == .Lower do return .Raise
	return mode}
editor_set_view :: proc(g: ^Game, view: Editor_View_Mode) {editor_state.view = view
	#partial switch view {case .Isometric, .Cutaway, .Roof:
		g.top_down_camera = false; case:
		g.top_down_camera = true}}
editor_adjacent_view :: proc(view: Editor_View_Mode, direction := 1) -> Editor_View_Mode {count :=
		len(Editor_View_Mode)
	return Editor_View_Mode((int(view) + direction % count + count) % count)}
editor_cycle_view :: proc(g: ^Game, direction := 1) {next := editor_adjacent_view(
		editor_state.view,
		direction,
	)
	editor_set_view(g, next)
	editor_show_feedback(fmt.tprintf("VIEW  ·  %s", editor_view_name(next)))}
editor_reset_story_transients :: proc(g: ^Game) {editor_cancel_object_rotation()
	editor_cancel_drag()
	editor_state.box_select_active = false
	editor_state.terrain_stroke_active = false
	editor_state.foundation_rectangle_active = false
	editor_state.foundation_draw_count = 0
	editor_state.room_rectangle_active = false
	editor_state.room_draw_count = 0
	editor_state.link_anchor_active = false
	editor_state.path_draw_count = 0
	editor_state.water_draw_count = 0
	editor_state.opening_active = false
	editor_state.roof_hover_active = false
	editor_state.paint_hover_active = false
	editor_state.placement_active = false
	g.build_has_anchor = false
	editor_state.wall_preview_active = false}
editor_switch_story :: proc(g: ^Game, story: int) -> bool {if story < 0 || story >= len(level_document.stories) || story == level_document.active_story do return false
	editor_reset_story_transients(g)
	if !level_set_active_story(&level_document, story) do return false
	editor_show_feedback(
		fmt.tprintf(
			"ACTIVE STORY  ·  %s  ·  %s",
			strings.to_upper(level_document.stories[story].name),
			level_story_label(&level_document, story),
		),
	)
	return true}
editor_focus_diagnostic :: proc(g: ^Game, index: int) -> bool {
	if index < 0 || index >= len(level_document.diagnostics) do return false; issue := level_document.diagnostics[index]; _ = level_set_active_story(&level_document, issue.story); g.camera_x = issue.position.x; g.camera_y = issue.position.y; g.camera_initialized = true; selection := level_selection_for_id(&level_document, issue.entity_id); if selection.kind != .None {editor_state.selection[0] = selection; editor_state.selection_count = 1} else do editor_state.selection_count = 0; editor_state.diagnostic_selected = index; editor_state.diagnostics_visible = false; g.build_tool = .Select; message := strings.to_upper(issue.message); if len(message) > 48 do message = message[:48]; editor_show_feedback(fmt.tprintf("ISSUE %d / %d  ·  %s", index + 1, len(level_document.diagnostics), message), issue.severity == .Error); return true
}
editor_diagnostic_window_start :: proc(count, selected, capacity: int) -> int {if count <= capacity do return 0
	return clamp(max(selected, 0) - capacity / 2, 0, count - capacity)}
editor_focus_adjacent_diagnostic :: proc(g: ^Game, direction: int) -> bool {count := len(
		level_document.diagnostics,
	)
	if count == 0 {editor_show_feedback("NO LEVEL ISSUES"); return false}
	current := editor_state.diagnostic_selected
	if current < 0 || current >= count do current = direction < 0 ? 0 : -1
	next := (current + (direction < 0 ? -1 : 1) + count) % count
	return editor_focus_diagnostic(g, next)}
editor_begin_playtest :: proc(g: ^Game) -> bool {
	validation := level_validate(
		&level_document,
	); if !validation.ok {editor_state.diagnostics_visible = true; house_plan.validation = validation.message; return false}
	if g.story_project !=
	   nil {registry: Story_Spatial_Registry; defer story_spatial_registry_destroy(&registry); assert(story_spatial_registry_register(&registry, story_level_space(&level_document))); _ = story_spatial_registry_register(&registry, story_city_space()); bindings := story_spatial_validate_project(g.story_project, &registry); defer story_validation_destroy(&bindings); if !bindings.ok {editor_state.diagnostics_visible = true; house_plan.validation = "Story spatial bindings are invalid for this level."; return false}}
	editor_playtest_snapshot = {
		active          = true,
		document        = level_clone_document(&level_document),
		camera_x        = g.camera_x,
		camera_y        = g.camera_y,
		top_down        = g.top_down_camera,
		selection       = editor_state.selection,
		selection_count = editor_state.selection_count,
		tool            = g.build_tool,
	}
	spawn := Vec2 {
		g.player_x,
		g.player_y,
	}; facing := g.player_angle; if editor_state.cursor_world_valid do spawn = editor_state.cursor_world
	if editor_state.selection_count > 0 &&
	   editor_state.selection[0].kind ==
		   .Marker {index := level_marker_index(&level_document, editor_state.selection[0].entity_id); if index >= 0 && level_document.markers[index].kind == .Player_Spawn {marker := level_document.markers[index]; spawn = marker.position; facing = marker.facing * f32(math.PI) / 180}}
	g.player_x =
		spawn.x; g.player_y = spawn.y; g.player_angle = facing; g.camera_x = spawn.x; g.camera_y = spawn.y; g.camera_initialized = true; g.top_down_camera = false; g.move_target_active = false; g.editor_mode = .None; g.interactive_count = 0; editor_state.playtesting = true; editor_state.diagnostics_visible = false; return true
}
editor_end_playtest :: proc(g: ^Game) -> bool {
	if !editor_state.playtesting || !editor_playtest_snapshot.active do return false; level_document = level_clone_document(&editor_playtest_snapshot.document); level_project_runtime(&level_document); g.camera_x = editor_playtest_snapshot.camera_x; g.camera_y = editor_playtest_snapshot.camera_y; g.camera_initialized = true; g.top_down_camera = editor_playtest_snapshot.top_down; g.build_tool = editor_playtest_snapshot.tool; g.editor_mode = .Build; editor_state.selection = editor_playtest_snapshot.selection; editor_state.selection_count = editor_playtest_snapshot.selection_count; editor_state.playtesting = false; editor_playtest_snapshot.active = false; g.move_target_active = false; return true
}

editor_cancel_drag :: proc() {editor_state.drag_active = false; editor_state.drag_delta = {}
	editor_state.drag_preview = {.Valid, "READY", {}, {}}}
editor_cancel_object_rotation :: proc() {if editor_state.object_rotate_active {index :=
			level_object_index(&level_document, editor_state.object_rotate_id)
		if index >= 0 do level_document.objects[index].rotation = editor_state.object_rotate_original}
	editor_state.object_rotate_active = false
	editor_state.object_rotate_id = ""}
editor_object_rotation_angle :: proc(center, cursor: Vec2, snap: bool) -> f32 {angle :=
		f32(math.atan2(f64(cursor.y - center.y), f64(cursor.x - center.x))) * 180 / f32(math.PI)
	if snap do angle = f32(math.round(f64(angle / 15))) * 15
	for angle < 0 do angle += 360
	for angle >= 360 do angle -= 360
	return angle}
editor_object_rotate_handle_rect :: proc(
	g: ^Game,
	angle: f32,
) -> (
	Rect,
	bool,
) {if editor_state.selection_count != 1 || editor_state.selection[0].kind != .Object do return {}, false
	index := level_object_index(&level_document, editor_state.selection[0].entity_id)
	if index < 0 do return {}, false
	object := level_document.objects[index]
	radians := angle * f32(math.PI) / 180
	point := Vec2 {
		object.position.x + f32(math.cos(f64(radians))) * 1.5,
		object.position.y + f32(math.sin(f64(radians))) * 1.5,
	}
	screen, visible := editor_world_screen(g, point)
	return {screen.x - 8, screen.y - 8, 16, 16}, visible}
editor_begin_object_rotation :: proc(g: ^Game) -> bool {if g.build_tool != .Select || editor_state.drag_active || editor_state.object_rotate_active do return false
	index :=
		editor_state.selection_count == 1 && editor_state.selection[0].kind == .Object ? level_object_index(&level_document, editor_state.selection[0].entity_id) : -1
	if index < 0 do return false
	object := level_document.objects[index]
	handle, visible := editor_object_rotate_handle_rect(g, object.rotation)
	if !visible || !contains(handle, g.input.mouse_pos) do return false
	editor_state.object_rotate_active = true
	editor_state.object_rotate_id = object.id
	editor_state.object_rotate_original = object.rotation
	editor_state.object_rotate_preview = object.rotation
	return true}
editor_update_object_rotation :: proc(g: ^Game) {if !editor_state.object_rotate_active do return
	index := level_object_index(&level_document, editor_state.object_rotate_id)
	if index < 0 {editor_cancel_object_rotation(); return}
	object := &level_document.objects[index]
	if g.input.mouse_down {wx, wy, ok := editor_mouse_ground(g, g.input.mouse_pos)
		if ok {editor_state.object_rotate_preview = editor_object_rotation_angle(object.position, {wx, wy}, !(g.keys[.LALT] || g.keys[.RALT]))
			object.rotation = editor_state.object_rotate_preview}}
	if !g.input.mouse_released do return
	preview := editor_state.object_rotate_preview
	original := editor_state.object_rotate_original
	position, id := object.position, object.id
	object.rotation = original
	editor_state.object_rotate_active = false
	editor_state.object_rotate_id = ""
	if math.abs(preview - original) >
	   .001 {if level_commit_transaction(&level_document, Level_Command{kind = .Move_Object, entity_id = id, a = position, value = preview}, "Rotate object") do editor_show_feedback("OBJECT ROTATED  ·  CTRL/CMD Z TO UNDO")}}
editor_cancel_terrain_stroke :: proc() {editor_state.terrain_stroke_active = false
	editor_state.terrain_stroke_start = {}
	editor_state.terrain_stroke_current = {}}

editor_selection_movable :: proc(selection: Editor_Selection) -> bool {return(
		selection.kind == .Room ||
		selection.kind == .Object ||
		selection.kind == .Light ||
		selection.kind == .Marker ||
		selection.kind == .Vertex ||
		selection.kind == .Edge ||
		selection.kind == .Opening ||
		(selection.kind == .Foundation ||
				selection.kind == .Path ||
				selection.kind == .Water ||
				selection.kind == .Vertical_Link) &&
			editor_control_point_index(selection) >= 0 \
	)}
editor_drag_commands :: proc(delta: Vec2, out: ^[16]Level_Command) -> int {count := 0; for 	selection in editor_state.selection[:editor_state.selection_count] {command, ok :=
			level_selection_move_command(&level_document, selection, delta)
		if ok && count < len(out^) {out[count] = command; count += 1}}
	return count}
editor_align_selection :: proc(axis_x: bool) -> bool {
	if editor_state.selection_count < 2 do return false
	anchor, ok := level_selection_position(
		&level_document,
		editor_state.selection[0],
	); if !ok do return false
	commands: [16]Level_Command; count := 0
	for selection in editor_state.selection[:editor_state.selection_count] {
		position, position_ok := level_selection_position(
			&level_document,
			selection,
		); if !position_ok {editor_show_feedback("ALIGNMENT REQUIRES MOVABLE ITEMS", true); return false}
		delta := axis_x ? Vec2{anchor.x - position.x, 0} : Vec2{0, anchor.y - position.y}
		if math.abs(delta.x) < .0001 && math.abs(delta.y) < .0001 do continue
		command, move_ok := level_selection_move_command(
			&level_document,
			selection,
			delta,
		); if !move_ok {editor_show_feedback("ALIGNMENT REQUIRES MOVABLE ITEMS", true); return false}
		commands[count] = command; count += 1
	}
	if count ==
	   0 {editor_show_feedback(axis_x ? "ALREADY ALIGNED ON X" : "ALREADY ALIGNED ON Y"); return true}
	if !level_commit_transactions(
		&level_document,
		commands[:count],
		axis_x ? "Align selection on X" : "Align selection on Y",
	) {editor_show_feedback("ALIGNMENT BLOCKED BY PLACEMENT RULES", true); return false}
	editor_show_feedback(
		axis_x ? "ALIGNED SELECTION ON X  ·  CTRL/CMD Z TO UNDO" : "ALIGNED SELECTION ON Y  ·  CTRL/CMD Z TO UNDO",
	); return true
}
editor_distribute_selection :: proc(axis_x: bool) -> bool {
	count := editor_state.selection_count; if count < 3 do return false
	positions: [16]Vec2; order: [16]int
	for selection, i in editor_state.selection[:count] {position, ok := level_selection_position(&level_document, selection); if !ok {editor_show_feedback("DISTRIBUTION REQUIRES MOVABLE ITEMS", true); return false}; _, move_ok := level_selection_move_command(&level_document, selection, {}); if !move_ok {editor_show_feedback("DISTRIBUTION REQUIRES MOVABLE ITEMS", true); return false}; positions[i] = position; order[i] = i}
	for i in 1 ..< count {candidate := order[i]; candidate_value := axis_x ? positions[candidate].x : positions[candidate].y; j := i; for j > 0 {previous := order[j - 1]; previous_value := axis_x ? positions[previous].x : positions[previous].y; if previous_value <= candidate_value do break; order[j] = previous; j -= 1}; order[j] = candidate}
	first, last :=
		positions[order[0]],
		positions[order[count - 1]]; minimum := axis_x ? first.x : first.y; maximum := axis_x ? last.x : last.y; span := maximum - minimum; if math.abs(span) < .0001 {editor_show_feedback(axis_x ? "ALIGN X BEFORE DISTRIBUTING" : "ALIGN Y BEFORE DISTRIBUTING", true); return false}
	commands: [16]Level_Command; command_count := 0
	for rank in 1 ..< count -
		1 {selection_index := order[rank]; target := minimum + span * f32(rank) / f32(count - 1); position := positions[selection_index]; delta := axis_x ? Vec2{target - position.x, 0} : Vec2{0, target - position.y}; if math.abs(delta.x) < .0001 && math.abs(delta.y) < .0001 do continue; command, ok := level_selection_move_command(&level_document, editor_state.selection[selection_index], delta); if !ok do return false; commands[command_count] = command; command_count += 1}
	if command_count ==
	   0 {editor_show_feedback(axis_x ? "ALREADY SPACED EVENLY ON X" : "ALREADY SPACED EVENLY ON Y"); return true}
	if !level_commit_transactions(
		&level_document,
		commands[:command_count],
		axis_x ? "Distribute selection on X" : "Distribute selection on Y",
	) {editor_show_feedback("DISTRIBUTION BLOCKED BY PLACEMENT RULES", true); return false}; editor_show_feedback(axis_x ? "DISTRIBUTED EVENLY ON X  ·  CTRL/CMD Z TO UNDO" : "DISTRIBUTED EVENLY ON Y  ·  CTRL/CMD Z TO UNDO"); return true
}
editor_select_pointer :: proc(g: ^Game, picked: Editor_Selection, point: Vec2) {
	additive := g.keys[.LSHIFT] || g.keys[.RSHIFT]
	if picked.kind ==
	   .Terrain {if !additive do editor_state.selection_count = 0; editor_state.box_select_active = true; editor_state.box_select_additive = additive; editor_state.box_select_start = point; editor_state.box_select_current = point; return}
	if additive {_ = editor_selection_toggle(&editor_state, picked); return}
	if editor_selection_index(&editor_state, picked) < 0 ||
	   editor_state.selection_count <=
		   1 {editor_state.selection[0] = picked; editor_state.selection_count = 1}
	if editor_selection_movable(
		picked,
	) {editor_state.drag_active = true; editor_state.drag_selection = picked; editor_state.drag_origin_world = point; editor_state.drag_current_world = point; editor_state.drag_delta = {}; editor_state.drag_preview = {.Valid, "READY", point, point}}
}
editor_update_box_selection :: proc(g: ^Game) {
	if !editor_state.box_select_active do return; if g.input.mouse_down {wx, wy, ok := editor_mouse_ground(g, g.input.mouse_pos); if ok do editor_state.box_select_current = {wx, wy}}; if !g.input.mouse_released do return; found: [16]Editor_Selection; count := level_select_box(&level_document, editor_state.box_select_start, editor_state.box_select_current, &found); if !editor_state.box_select_additive do editor_state.selection_count = 0; for selection in found[:count] do if editor_selection_index(&editor_state, selection) < 0 && editor_state.selection_count < len(editor_state.selection) {editor_state.selection[editor_state.selection_count] = selection; editor_state.selection_count += 1}; editor_state.box_select_active = false
}
editor_copy_selection :: proc() -> bool {if editor_state.selection_count <= 0 do return false
	editor_clipboard = {
		active          = true,
		document        = level_clone_document(&level_document),
		selection       = editor_state.selection,
		selection_count = editor_state.selection_count,
	}
	editor_show_feedback(
		editor_state.selection_count == 1 ? "COPIED 1 ITEM" : fmt.tprintf("COPIED %d ITEMS", editor_state.selection_count),
	)
	return true}
editor_paste_selection :: proc(offset: Vec2 = {.5, .5}, verb := "PASTED") -> bool {
	if !editor_clipboard.active || editor_clipboard.selection_count <= 0 do return false; commands: [16]Level_Command; next_selection: [16]Editor_Selection; count := 0
	for selection, i in editor_clipboard.selection[:editor_clipboard.selection_count] {if count >= len(commands) do break; id := fmt.tprintf("paste_%d_%d", level_document.revision + 1, i); command := Level_Command{}; next := Editor_Selection{}
		#partial switch selection.kind {
		case .Room:
			if level_room_index(&level_document, selection.entity_id) < 0 do continue; command = {
				kind      = .Duplicate_Room,
				entity_id = selection.entity_id,
				a         = offset,
				material  = id,
			}; next = {.Room, id, -1}
		case .Object:
			if level_object_index(&level_document, selection.entity_id) < 0 do continue
			command = {
				kind      = .Duplicate_Object,
				entity_id = selection.entity_id,
				a         = offset,
				material  = id,
			}
			next = {.Object, id, -1}
		case .Light:
			index := level_light_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			light := editor_clipboard.document.lights[index]
			command = {
				kind      = .Add_Light,
				entity_id = id,
				a         = {light.position.x + offset.x, light.position.y + offset.y},
				b         = {light.range, light.intensity},
				c         = {light.elevation, f32(light.kind)},
				value     = f32(level_document.active_story),
				color     = light.color,
			}
			command.points[0] = {light.cone_angle, light.facing}
			next = {.Light, id, -1}
		case .Marker:
			index := level_marker_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			marker := editor_clipboard.document.markers[index]
			command = {
				kind        = .Add_Marker,
				entity_id   = id,
				a           = {marker.position.x + offset.x, marker.position.y + offset.y},
				b           = {marker.radius, marker.facing},
				c           = {marker.camera_height, f32(marker.kind)},
				material    = marker.reference,
				destination = marker.destination,
				value       = f32(level_document.active_story),
			}
			next = {.Marker, id, -1}
		case .Path:
			index := level_path_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			path := editor_clipboard.document.paths[index]
			command = {
				kind        = .Add_Path,
				entity_id   = id,
				material    = path.material,
				c           = {f32(path.kind), 0},
				value       = path.width,
				point_count = min(len(path.points), 32),
			}
			for p, j in path.points {if j >= len(command.points) do break; command.points[j] = {p.x + offset.x, p.y + offset.y}}
			next = {.Path, id, -1}
		case .Water:
			index := level_water_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			water := editor_clipboard.document.waters[index]
			command = {
				kind        = .Create_Water,
				entity_id   = id,
				value       = water.elevation,
				point_count = min(len(water.points), 32),
			}
			for p, j in water.points {if j >= len(command.points) do break; command.points[j] = {p.x + offset.x, p.y + offset.y}}
			next = {.Water, id, -1}
		case .Roof:
			index := level_roof_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			roof := editor_clipboard.document.roofs[index]
			command = {
				kind      = .Create_Roof,
				entity_id = id,
				material  = roof.room_id,
				a         = {f32(roof.style), roof.ridge_angle},
				b         = {roof.overhang, 0},
				value     = roof.pitch,
			}
			next = {.Roof, id, -1}
		case .Vertical_Link:
			index := level_vertical_link_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			link := editor_clipboard.document.vertical_links[index]
			command = {
				kind      = .Create_Vertical_Link,
				entity_id = id,
				a         = {link.start.x + offset.x, link.start.y + offset.y},
				b         = {link.finish.x + offset.x, link.finish.y + offset.y},
				c         = {f32(link.kind), 0},
				value     = link.width,
			}
			next = {.Vertical_Link, id, -1}
		case .Opening:
			index := level_opening_index(&editor_clipboard.document, selection.entity_id)
			if index < 0 do continue
			opening := editor_clipboard.document.openings[index]
			command = {
				kind        = .Add_Opening,
				entity_id   = id,
				material    = opening.host_path,
				destination = door_material_name(opening.door_material),
				value       = f32(opening.segment),
				b           = {f32(opening.kind), opening.width},
				c           = {opening.position, opening.height},
			}
			command.points[0] = {opening.sill_height, f32(opening.window_style)}
			command.points[1] = {
				opening.window_flipped ? 1 : 0,
				opening.window_hinge_right ? 1 : 0,
			}
			next = {.Opening, id, opening.segment}
		case:
			continue
		}; commands[count] = command; next_selection[count] = next; count += 1}
	if count == 0 || !level_commit_transactions(&level_document, commands[:count], fmt.tprintf("%s %s", verb, count > 1 ? "selection set" : "selection")) do return false; editor_state.selection_count = count; copy(editor_state.selection[:], next_selection[:count]); editor_show_feedback(fmt.tprintf("%s %d ITEM%s  ·  CTRL/CMD Z TO UNDO", verb, count, count == 1 ? "" : "S")); return true
}
editor_delete_selection_set :: proc() -> bool {if editor_state.selection_count <= 0 do return false
	for selection in editor_state.selection[:editor_state.selection_count] {if editor_control_point_index(selection) >= 0 && (selection.kind == .Foundation || selection.kind == .Path || selection.kind == .Water || selection.kind == .Vertical_Link) {editor_show_feedback("SELECT THE PARENT SHAPE TO DELETE IT", true)
			return false}}
	commands: [16]Level_Command
	count := 0
	for selection in editor_state.selection[:editor_state.selection_count] {command := Level_Command{}
		#partial switch selection.kind {case .Room:
			command = {
				kind      = .Delete_Room,
				entity_id = selection.entity_id,
			}; case .Object:
			command = {
				kind      = .Delete_Object,
				entity_id = selection.entity_id,
				material  = "object",
			}; case .Light:
			command = {
				kind      = .Delete_Light,
				entity_id = selection.entity_id,
			}; case .Path:
			command = {
				kind      = .Delete_Object,
				entity_id = selection.entity_id,
				material  = "path",
			}; case .Opening:
			command = {
				kind      = .Delete_Opening,
				entity_id = selection.entity_id,
			}; case .Roof:
			command = {
				kind      = .Delete_Roof,
				entity_id = selection.entity_id,
			}; case .Vertical_Link:
			command = {
				kind      = .Delete_Vertical_Link,
				entity_id = selection.entity_id,
			}; case .Water:
			command = {
				kind      = .Delete_Water,
				entity_id = selection.entity_id,
			}; case .Marker:
			command = {
				kind      = .Delete_Marker,
				entity_id = selection.entity_id,
			}; case:
			continue}
		commands[count] = command
		count += 1}
	if count == 0 || !level_commit_transactions(&level_document, commands[:count], count > 1 ? "Delete selection set" : "Delete selection") do return false
	editor_state.selection_count = 0
	editor_show_feedback(
		count > 1 ? fmt.tprintf("DELETED %d ITEMS  ·  CTRL/CMD Z TO UNDO", count) : "DELETED ITEM  ·  CTRL/CMD Z TO UNDO",
	)
	return true}

editor_update_drag :: proc(g: ^Game) {
	if !editor_state.drag_active do return
	if g.input.mouse_down {wx, wy, ok := editor_mouse_ground(g, g.input.mouse_pos); if ok {editor_state.drag_current_world = {wx, wy}; editor_state.drag_delta = level_snap_delta(&level_document, {wx - editor_state.drag_origin_world.x, wy - editor_state.drag_origin_world.y}); commands: [16]Level_Command; count := editor_drag_commands(editor_state.drag_delta, &commands); editor_state.drag_preview = {.Valid, "READY", {}, {}}; for command in commands[:count] {preview := level_preview_transaction(&level_document, command); if preview.state == .Blocked {editor_state.drag_preview = preview; break} else if preview.state == .Warning do editor_state.drag_preview = preview}}}
	if !g.input.mouse_released do return
	if editor_state.drag_preview.state != .Blocked &&
	   (editor_state.drag_delta.x != 0 ||
			   editor_state.drag_delta.y !=
				   0) {commands: [16]Level_Command; count := editor_drag_commands(editor_state.drag_delta, &commands); if count > 0 do _ = level_commit_transactions(&level_document, commands[:count], count > 1 ? "Drag selection set" : "Drag selection")}
	editor_cancel_drag()
}

editor_update_terrain_stroke :: proc(g: ^Game) {
	if !editor_state.terrain_stroke_active do return
	if g.input.mouse_down {wx, wy, ok := editor_mouse_ground(g, g.input.mouse_pos); if ok do editor_state.terrain_stroke_current = {wx, wy}}
	if !g.input.mouse_released do return
	mode := editor_effective_terrain_mode(
		editor_state.terrain_mode,
		g.keys[.LCTRL] || g.keys[.RCTRL],
	); command := Level_Command {
		kind  = .Sculpt_Terrain,
		a     = editor_state.terrain_stroke_start,
		b     = editor_state.terrain_stroke_current,
		c     = {editor_state.terrain_strength, editor_state.terrain_sample},
		value = editor_state.terrain_radius,
		brush = mode,
	}; preview := level_preview_transaction(
		&level_document,
		command,
	); if preview.state != .Blocked do _ = level_commit_transaction(&level_document, command, fmt.tprintf("%v terrain stroke", mode)); editor_cancel_terrain_stroke()
}
