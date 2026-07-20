package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import ui "zelda_engine:ui"

update_vehicle_haptics :: proc(g: ^Game) {
	if g.gamepad == nil || g.vehicle_haptics_failed {g.vehicle_haptics_active = false; return}
	low, high: f32
	if g.screen == .Exterior && g.driving_vehicle >= 0 && g.driving_vehicle < len(g.vehicles) {
		v := g.vehicles[g.driving_vehicle]
		throttle, _ := vehicle_control_inputs(
			g,
		); drive_demand := clamp(throttle, 0, 1) * vehicle_requested_drive_authority(v, throttle)
		low, high = vehicle_haptic_strengths_blended(
			v,
			v.surface_blend,
			v.handbrake_slip,
			vehicle_tune(g.driving_vehicle),
			drive_demand,
		); high = vehicle_assisted_high_haptic(v, high, v.driver_assist, v.driver_assist_strength, v.driver_assist_time)
	}
	if low > .005 || high > .005 {
		ok := sdl.RumbleGamepad(g.gamepad, u16(low * 65535), u16(high * 65535), 40)
		g.vehicle_haptics_active = ok; g.vehicle_haptics_failed = !ok
	} else if g.vehicle_haptics_active {
		_ = sdl.RumbleGamepad(g.gamepad, 0, 0, 0); g.vehicle_haptics_active = false
	}
}

begin_frame :: proc(g: ^Game) {g.input.mouse_wheel = 0; g.input.dialogue_choice_slot = 0
	g.input.mouse_pressed = false
	g.input.mouse_released = false
	g.input.mouse_middle_pressed = false
	g.input.mouse_middle_released = false
	g.input.activate = false
	g.input.vehicle_action = false
	g.input.back = false
	g.input.left = false
	g.input.right = false
	g.input.up = false
	g.input.down = false
	g.input.recreate = false
	g.input.notebook = false
	g.input.attributes = false
	g.input.case_sense = false
	g.input.case_sense_release = false
	g.input.camera_toggle = false
	g.input.wall_view_cycle = false
	g.input.shoulder_left = false
	g.input.shoulder_right = false
	g.input.save_document = false
	g.input.undo_document = false
	g.input.redo_document = false
	g.input.delete_selection = false
	g.input.copy_selection = false
	g.input.paste_selection = false
	g.input.duplicate_selection = false
	g.input.text_input_len = 0
	g.input.clipboard_paste_len = 0
	g.input.key_enter = false
	g.input.key_escape = false
	g.input.key_backspace = false
	g.input.key_delete = false
	g.input.key_tab = false
	g.input.key_home = false
	g.input.key_end = false
	g.input.key_left = false
	g.input.key_right = false
	g.input.key_a = false
	g.input.key_x = false
	g.input.key_v = false
	g.input.key_c = false}
normalize_gamepad_axis :: proc(value: i16) -> f32 {v := f32(value) / 32767.0; if math.abs(v) < 0.18 do return 0
	return clamp(v, -1, 1)}
gamepad_disconnect_should_pause :: proc(screen: Screen) -> bool {return(
		screen != .Title &&
		screen != .Campaign &&
		screen != .Campaign_Action &&
		screen != .Campaign_Cases &&
		screen != .Options &&
		screen != .Pause \
	)}
clear_gamepad_input :: proc(g: ^Game) {g.pad_left_x = 0; g.pad_left_y = 0; g.pad_right_x = 0
	g.pad_right_y = 0
	g.pad_left_trigger = 0
	g.pad_right_trigger = 0
	g.axis_nav_x = 0
	g.axis_nav_y = 0
	for &pressed in g.pad_buttons do pressed = false}
resume_from_controller_disconnect :: proc(
	g: ^Game,
) {if g.controller_disconnected {g.controller_disconnected = false; g.input_resume_blocked = true}}
activate_keyboard_mouse :: proc(g: ^Game) {resume_from_controller_disconnect(g)
	g.active_device = .Keyboard_Mouse}
activate_gamepad :: proc(g: ^Game) {resume_from_controller_disconnect(g)
	g.active_device = .Gamepad
	g.mouse_device_motion = {}}
prepare_input_poll :: proc(g: ^Game) {if g.input_resume_blocked {begin_frame(g)
		g.input_resume_blocked = false}}
poll :: proc(g: ^Game, window: ^sdl.Window) {
	prepare_input_poll(g)
	e: sdl.Event; for sdl.PollEvent(&e) {#partial switch e.type {
		case .QUIT:
			g.running = false
		case .WINDOW_PIXEL_SIZE_CHANGED:
			g.window_resized = true
		case .MOUSE_MOTION:
			g.input.mouse_pos = window_mouse_to_logical(window, e.motion.x, e.motion.y)
			g.mouse_device_motion.x += e.motion.xrel
			g.mouse_device_motion.y += e.motion.yrel
			if g.active_device == .Keyboard_Mouse || g.mouse_device_motion.x * g.mouse_device_motion.x + g.mouse_device_motion.y * g.mouse_device_motion.y >= 4 do activate_keyboard_mouse(g)
		case .MOUSE_WHEEL:
			g.input.mouse_wheel += e.wheel.y; activate_keyboard_mouse(g)
		case .MOUSE_BUTTON_DOWN:
			g.input.mouse_pos = window_mouse_to_logical(window, e.button.x, e.button.y)
			if e.button.button == 2 {g.input.mouse_middle_down = true
				g.input.mouse_middle_pressed =
					true} else if e.button.button == 1 {g.input.mouse_down = true; g.input.mouse_pressed = true}
			activate_keyboard_mouse(g)
		case .MOUSE_BUTTON_UP:
			g.input.mouse_pos = window_mouse_to_logical(window, e.button.x, e.button.y)
			if e.button.button ==
			   2 {g.input.mouse_middle_down = false; g.input.mouse_middle_released = true} else if e.button.button == 1 {g.input.mouse_down = false; g.input.mouse_released = true}
		case .TEXT_INPUT:
			bytes := transmute([]u8)string(e.text.text)
			count := min(len(bytes), len(g.input.text_input) - g.input.text_input_len)
			copy(g.input.text_input[g.input.text_input_len:], bytes[:count])
			g.input.text_input_len += count
		case .KEY_DOWN:
			activate_keyboard_mouse(g); key_was_down := g.keys[e.key.scancode]
			g.keys[e.key.scancode] = true
			control := g.keys[.LCTRL] || g.keys[.RCTRL] || g.keys[.LGUI] || g.keys[.RGUI]
			shift := g.keys[.LSHIFT] || g.keys[.RSHIFT]
			g.input.key_ctrl = g.keys[.LCTRL] || g.keys[.RCTRL]
			g.input.key_super = g.keys[.LGUI] || g.keys[.RGUI]
			g.input.key_shift = shift
			search_was_active := g.editor_mode == .Build && editor_state.search_active
			numeric_was_active := g.editor_mode == .Build && editor_state.numeric_field != .None
			editing_was_active :=
				search_was_active || numeric_was_active || graph_state.field_edit.active
			if search_was_active && (e.key.scancode == .RETURN || e.key.scancode == .KP_ENTER) do _ = editor_select_first_catalog_match(g)
			if g.editor_mode == .Build &&
			   editor_catalog_visible(g.build_tool) &&
			   !editing_was_active &&
			   !editor_state.object_rotate_active &&
			   e.key.scancode ==
				   .SLASH {editor_state.search_active = true; editor_state.catalog_page = 0}
			if g.editor_mode == .Build && !editing_was_active && !editor_state.object_rotate_active && !key_was_down && e.key.scancode == .F1 do editor_state.shortcut_help_visible = !editor_state.shortcut_help_visible
			if g.editor_mode == .Graph && !editing_was_active && !key_was_down && e.key.scancode == .F1 do graph_state.help_visible = !graph_state.help_visible
			if g.editor_mode == .Graph && !editing_was_active && !key_was_down && control && e.key.scancode == .F do graph_begin_edit(.Search, graph_state.search_query)
			if g.editor_mode == .Graph && !editing_was_active && !key_was_down && !control && e.key.scancode == .F do _ = graph_frame_nodes(graph_state.selection_count > 0)
			if g.editor_mode == .Graph && !editing_was_active && !key_was_down && !control && e.key.scancode == .LEFTBRACKET do _ = graph_focus_search_result(-1)
			if g.editor_mode == .Graph && !editing_was_active && !key_was_down && !control && e.key.scancode == .RIGHTBRACKET do _ = graph_focus_search_result(1)
			if g.editor_mode == .Graph &&
			   !editing_was_active &&
			   !key_was_down &&
			   !control &&
			   e.key.scancode == ._0 {graph_state.pan = {}; graph_state.zoom = 1}
			if g.editor_mode == .Build &&
			   !editing_was_active &&
			   !editor_state.object_rotate_active {if control && e.key.scancode == .S do g.input.save_document = true; if control && e.key.scancode == .Z {if shift do g.input.redo_document = true
					else do g.input.undo_document = true}; if control && e.key.scancode == .Y do g.input.redo_document = true; if e.key.scancode == .DELETE || e.key.scancode == .BACKSPACE do g.input.delete_selection = true; if control && e.key.scancode == .C do g.input.copy_selection = true; if control && e.key.scancode == .V do g.input.paste_selection = true; if control && e.key.scancode == .D do g.input.duplicate_selection = true}
			if g.editor_mode == .Build &&
			   !editing_was_active &&
			   !editor_state.object_rotate_active &&
			   !control &&
			   !key_was_down {#partial switch e.key.scancode {case ._1:
					editor_activate_build_mode(g, .Select); case ._2:
					editor_activate_build_mode(g, .Room); case ._3:
					editor_activate_build_mode(g, .Foundation); case ._4:
					editor_activate_build_mode(g, .Paint); case ._5:
					editor_activate_build_mode(g, .Plant); case ._6:
					editor_activate_build_mode(g, .Roof); case ._7:
					editor_activate_build_mode(g, .Terrain); case ._8:
					editor_activate_build_mode(g, .Stairs); case ._9:
					editor_activate_build_mode(g, .Path); case ._0:
					editor_activate_build_mode(g, .Water); case .M:
					editor_activate_build_mode(g, .Marker)}}
			if g.editor_mode == .Build && !editing_was_active && !editor_state.object_rotate_active && !control && !key_was_down && e.key.scancode == .F do _ = editor_frame_selection(g)
			if g.editor_mode == .Build && !editing_was_active && !editor_state.object_rotate_active && !control && !key_was_down && e.key.scancode == .LEFTBRACKET do _ = editor_focus_adjacent_diagnostic(g, -1)
			if g.editor_mode == .Build && !editing_was_active && !editor_state.object_rotate_active && !control && !key_was_down && e.key.scancode == .RIGHTBRACKET do _ = editor_focus_adjacent_diagnostic(g, 1)
			if g.editor_mode == .Build &&
			   !editing_was_active &&
			   !editor_state.object_rotate_active &&
			   !control &&
			   !key_was_down &&
			   e.key.scancode ==
				   .PAGEUP {above := level_story_above(&level_document, level_document.active_story); if above >= 0 do _ = editor_switch_story(g, above)}
			if g.editor_mode == .Build &&
			   !editing_was_active &&
			   !editor_state.object_rotate_active &&
			   !control &&
			   !key_was_down &&
			   e.key.scancode ==
				   .PAGEDOWN {below := level_story_below(&level_document, level_document.active_story); if below >= 0 do _ = editor_switch_story(g, below)}
			if graph_state.field_edit.active {#partial switch e.key.scancode {case .RETURN, .KP_ENTER:
					g.input.key_enter = true; case .ESCAPE:
					g.input.key_escape = true; case .BACKSPACE:
					g.input.key_backspace = true; case .DELETE:
					g.input.key_delete = true; case .TAB:
					g.input.key_tab = true; case .UP:
					g.input.up = true; case .DOWN:
					g.input.down = true; case .HOME:
					g.input.key_home = true; case .END:
					g.input.key_end = true; case .LEFT:
					g.input.key_left = true; case .RIGHT:
					g.input.key_right = true; case .A:
					g.input.key_a = true; case .X:
					g.input.key_x = true; case .V:
					g.input.key_v = true
					if control {clip := sdl.GetClipboardText(); if clip != nil {bytes := transmute([]u8)string(cstring(clip)); g.input.clipboard_paste_len = min(len(bytes), len(g.input.clipboard_paste)); copy(g.input.clipboard_paste[:], bytes[:g.input.clipboard_paste_len])}}; case .C:
					g.input.key_c = true}}
			if g.editor_mode == .Graph &&
			   !graph_state.field_edit.active &&
			   !key_was_down {if control && e.key.scancode == .S do g.input.save_document = true; if control && e.key.scancode == .Z {if shift do g.input.redo_document = true
					else do g.input.undo_document = true}; if control && e.key.scancode == .Y do g.input.redo_document = true; if e.key.scancode == .DELETE || e.key.scancode == .BACKSPACE do g.input.delete_selection = true; if control && e.key.scancode == .C do g.input.copy_selection = true; if control && e.key.scancode == .V do g.input.paste_selection = true; if control && e.key.scancode == .D do g.input.duplicate_selection = true; if shift && e.key.scancode == .A && contains(graph_canvas_rect(), g.input.mouse_pos) {graph_state.quick_add = true; graph_state.quick_add_at = g.input.mouse_pos; graph_state.quick_add_selected = 0}}
			if search_was_active {if e.key.scancode == .BACKSPACE {if editor_state.search_count > 0 {editor_state.search_count -= 1; editor_state.catalog_page = 0}} else if e.key.scancode == .RETURN || e.key.scancode == .KP_ENTER {editor_state.search_active = false} else if e.key.scancode == .SPACE {_ = catalog_append_search_char(&editor_state, '_')} else if int(e.key.scancode) >= int(sdl.Scancode.A) && int(e.key.scancode) <= int(sdl.Scancode.Z) {_ = catalog_append_search_char(&editor_state, u8('a' + int(e.key.scancode) - int(sdl.Scancode.A)))} else if int(e.key.scancode) >= int(sdl.Scancode._1) && int(e.key.scancode) <= int(sdl.Scancode._9) {_ = catalog_append_search_char(&editor_state, u8('1' + int(e.key.scancode) - int(sdl.Scancode._1)))} else if e.key.scancode == ._0 {_ = catalog_append_search_char(&editor_state, '0')}}
			if numeric_was_active {if e.key.scancode == .BACKSPACE {if editor_state.numeric_replace_on_input {editor_state.numeric_count = 0; editor_state.numeric_replace_on_input = false} else if editor_state.numeric_count > 0 do editor_state.numeric_count -= 1} else if e.key.scancode == .RETURN || e.key.scancode == .KP_ENTER {_ = editor_commit_numeric_edit()} else if e.key.scancode == .TAB {_ = editor_advance_numeric_edit(shift ? -1 : 1)} else if e.key.scancode == .ESCAPE {editor_cancel_numeric_edit()} else if e.key.scancode == .PERIOD || e.key.scancode == .KP_PERIOD {_ = editor_append_numeric_char('.')} else if e.key.scancode == .MINUS || e.key.scancode == .KP_MINUS {_ = editor_append_numeric_char('-')} else if int(e.key.scancode) >= int(sdl.Scancode._1) && int(e.key.scancode) <= int(sdl.Scancode._9) {_ = editor_append_numeric_char(u8('1' + int(e.key.scancode) - int(sdl.Scancode._1)))} else if e.key.scancode == ._0 {_ = editor_append_numeric_char('0')} else if int(e.key.scancode) >= int(sdl.Scancode.KP_1) && int(e.key.scancode) <= int(sdl.Scancode.KP_9) {_ = editor_append_numeric_char(u8('1' + int(e.key.scancode) - int(sdl.Scancode.KP_1)))} else if e.key.scancode == .KP_0 {_ = editor_append_numeric_char('0')}}
			#partial switch e.key.scancode {case .RETURN, .KP_ENTER, .SPACE:
				if !editing_was_active do g.input.activate = true; case .E:
				if !editing_was_active do g.input.activate = true; case .F:
				if !editing_was_active &&
				   !control &&
				   !key_was_down {if g.screen == .Exterior do g.input.vehicle_action = true
					else do g.input.camera_toggle = true}; case .N:
				if !editing_was_active && !control && !key_was_down do g.input.notebook = true; case .C:
				if !editing_was_active && !control && !key_was_down do g.input.attributes = true; case .Q:
				if !editing_was_active && !key_was_down do g.input.case_sense = true; case .V:
				if !editing_was_active && !control do g.input.wall_view_cycle = true; case .ESCAPE:
				if !editing_was_active do g.input.back = true; case .LEFT:
				if !editing_was_active do g.input.left = true; case .RIGHT:
				if !editing_was_active do g.input.right = true; case .UP:
				if !editing_was_active do g.input.up = true; case .DOWN:
				if !editing_was_active do g.input.down = true; case .A:
				if !editing_was_active && menu_screen(g.screen) do g.input.left = true; case .D:
				if !editing_was_active && menu_screen(g.screen) do g.input.right = true; case .W:
				if !editing_was_active && menu_screen(g.screen) do g.input.up = true; case .S:
				if !editing_was_active && menu_screen(g.screen) do g.input.down = true}
			if !editing_was_active &&
			   !key_was_down &&
			   g.screen == .Dialogue {if e.key.scancode == .PAGEUP do g.input.shoulder_left = true
				else if e.key.scancode == .PAGEDOWN do g.input.shoulder_right = true}
			if !editing_was_active &&
			   !key_was_down &&
			   g.screen == .Dialogue {#partial switch e.key.scancode {case ._1, .KP_1:
					g.input.dialogue_choice_slot = 1; case ._2, .KP_2:
					g.input.dialogue_choice_slot = 2; case ._3, .KP_3:
					g.input.dialogue_choice_slot = 3}}
		case .KEY_UP:
			g.keys[e.key.scancode] = false
			if e.key.scancode == .Q do g.input.case_sense_release = true
		case .GAMEPAD_ADDED:
			if g.gamepad ==
			   nil {g.gamepad = sdl.OpenGamepad(e.gdevice.which); g.vehicle_haptics_failed = false; if g.gamepad != nil do g.gamepad_type = sdl.GetGamepadType(g.gamepad)}
		case .GAMEPAD_REMOVED:
			if g.gamepad != nil &&
			   sdl.GetGamepadID(g.gamepad) ==
				   e.gdevice.which {was_active := g.active_device == .Gamepad; pause := was_active && gamepad_disconnect_should_pause(g.screen); sdl.CloseGamepad(g.gamepad); g.gamepad = nil; g.gamepad_type = .UNKNOWN; g.vehicle_haptics_active = false; g.vehicle_haptics_failed = false; clear_gamepad_input(g); g.active_device = .Keyboard_Mouse; g.controller_disconnected = pause}
		case .GAMEPAD_AXIS_MOTION:
			v := normalize_gamepad_axis(e.gaxis.value); if v != 0 do activate_gamepad(g)
			axis := sdl.GamepadAxis(e.gaxis.axis)
			#partial switch axis {
			case .LEFTX:
				g.pad_left_x = v; step: i8 = v > 0.55 ? 1 : v < -0.55 ? -1 : 0
				if menu_screen(g.screen) &&
				   step != 0 &&
				   g.axis_nav_x == 0 {g.input.right = step > 0; g.input.left = step < 0}
				g.axis_nav_x = step
			case .LEFTY:
				g.pad_left_y = v; step: i8 = v > 0.55 ? 1 : v < -0.55 ? -1 : 0
				if menu_screen(g.screen) &&
				   step != 0 &&
				   g.axis_nav_y == 0 {g.input.down = step > 0; g.input.up = step < 0}
				g.axis_nav_y = step
			case .RIGHTX:
				g.pad_right_x = v
			case .RIGHTY:
				g.pad_right_y = v
			case .LEFT_TRIGGER:
				g.pad_left_trigger = max(v, 0)
			case .RIGHT_TRIGGER:
				g.pad_right_trigger = max(v, 0)}
		case .GAMEPAD_BUTTON_DOWN:
			activate_gamepad(g); b := sdl.GamepadButton(e.gbutton.button); g.pad_buttons[b] = true
			#partial switch b {case .SOUTH:
				g.input.activate = true; case .EAST:
				g.input.back = true; case .WEST:
				g.input.recreate = true; case .NORTH:
				if g.screen == .Exterior do g.input.vehicle_action = true
				else do g.input.notebook = true; case .BACK:
				g.input.wall_view_cycle = true; case .LEFT_STICK:
				g.input.case_sense = true; case .RIGHT_STICK:
				g.input.camera_toggle = true; case .LEFT_SHOULDER:
				g.input.shoulder_left = true; case .RIGHT_SHOULDER:
				g.input.shoulder_right = true; case .DPAD_LEFT:
				if menu_screen(g.screen) do g.input.left = true; case .DPAD_RIGHT:
				if menu_screen(g.screen) do g.input.right = true; case .DPAD_UP:
				if menu_screen(g.screen) || g.screen == .Investigate do g.input.up = true; case .DPAD_DOWN:
				if menu_screen(g.screen) || g.screen == .Investigate do g.input.down = true}
		case .GAMEPAD_BUTTON_UP:
			b := sdl.GamepadButton(e.gbutton.button); g.pad_buttons[b] = false
			if b == .LEFT_STICK do g.input.case_sense_release = true
		}}}

button_id :: proc(r: Rect) -> ui.Gui_Id {
	x := u64(int(r.x) + 2048); y := u64(int(r.y) + 2048)
	w := u64(int(r.w)); h := u64(int(r.h))
	return ui.Gui_Id((x << 44) ~ (y << 24) ~ (w << 12) ~ h)
}
button :: proc(g: ^Game, r: Rect) -> bool {
	return ui.gui_button_at(&g.gui, button_id(r), {r.x, r.y, r.w, r.h}, "", true)
}
menu_screen :: proc(screen: Screen) -> bool {return screen != .Exterior && screen != .Investigate}
menu_default_rect :: proc(g: ^Game) -> Rect {
	#partial switch g.screen {
	case .Title:
		return {410, 400, 380, 48}
	case .Campaign:
		return campaign_browser_card_logical_rect(0)
	case .Campaign_Action:
		return {410, 286, 380, 52}
	case .Campaign_Cases:
		return {760, 610, 310, 52}
	case .Options:
		return {410, 145, 380, 48}
	case .Pause:
		return {410, 210, 380, 48}
	case .Introduction:
		return {410, 625, 380, 58}
	case .Dialogue:
		return dialogue_default_rect(g)
	case .Check:
		if g.check_done do return {430, 500, 340, 50}; return {430, 510, 340, 58}
	case .Attributes:
		return {42, 145, 250, 105}
	case .Notebook:
		return {20, 95, 205, 46}
	case .Board:
		return {25, 125, 325, 66}
	case .Challenge:
		return {70, 205, 330, 104}
	case .Recreate:
		return {440, 630, 320, 54}
	case .Reveal_Prep:
		return {440, 630, 320, 54}
	case .Reveal:
		return {440, 630, 320, 54}
	case .Result:
		return {300, 630, 280, 54}
	case .Game_Over:
		return {410, 410, 380, 52}
	case .Diagnostics:
		return {20, 650, 180, 42}
	}
	return {}
}
log_line :: proc(g: ^Game, s: string) {g.log[3] = g.log[2]; g.log[2] = g.log[1]; g.log[1] =
		g.log[0]
	g.log[0] = s
	if g.history_count < len(g.history) {g.history[g.history_count] = s; g.history_count += 1}}
case_pacing_record :: proc(g: ^Game, index: int, ready: bool) {if !ready || index < 0 || index >= len(g.case_pacing_times) || (g.case_pacing_mask & (u8(1) << u8(index))) != 0 do return
	g.case_pacing_mask |= u8(1) << u8(index)
	g.case_pacing_times[index] = g.animation_time}
update_case_pacing :: proc(g: ^Game) {
	if g.story_project == nil || g.story_project.id != "the_torn_appointment" do return
	case_pacing_record(
		g,
		0,
		g.screen == .Investigate || g.screen == .Dialogue || g.phase >= .Investigation,
	)
	case_pacing_record(
		g,
		1,
		claim_known(g, "claim_miriam_dinner") &&
		claim_known(g, "claim_daniel_alibi") &&
		claim_known(g, "claim_elsie_study"),
	)
	case_pacing_record(g, 2, knowledge_piece_known(g, "ded_scene_staged"))
	case_pacing_record(
		g,
		3,
		knowledge_piece_known(g, "ded_daniel_affair") &&
		knowledge_piece_known(g, "ded_elsie_theft"),
	)
	case_pacing_record(g, 4, knowledge_piece_known(g, "ded_miriam_denial_disproved"))
	case_pacing_record(g, 5, g.phase == .Case_Result || g.screen == .Result)
}
pacing_time_label :: proc(seconds: f32) -> string {whole := max(0, int(seconds))
	return fmt.tprintf("%02d:%02d", whole / 60, whole % 60)}
pacing_band_status :: proc(seconds, min_seconds, max_seconds: f32) -> string {if seconds < min_seconds do return "EARLY"
	if seconds > max_seconds do return "LATE"
	return "ON TARGET"}
case_optional_beat_completed :: proc(g: ^Game, id: string) -> bool {payload :=
		mystery_game_payload(g)
	if payload == nil do return false
	for 	i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i)
		if node != nil && node.node_id == id do return mystery_game_dialogue_completed(g, i) && !mystery_game_dialogue_failed(g, i)}
	return false}
case_pacing_report_text :: proc(g: ^Game) -> string {
	labels := [6]string {
		"Arrival",
		"Three accounts",
		"False scene",
		"Other lies",
		"Torn note",
		"Outcome",
	}
	band_mins := [6]f32 {
		0,
		5 * 60,
		15 * 60,
		30 * 60,
		45 * 60,
		55 * 60,
	}; band_maxes := [6]f32{5 * 60, 15 * 60, 30 * 60, 45 * 60, 55 * 60, 60 * 60}
	result := "The Torn Appointment — first-playthrough pace"
	for label, i in labels {recorded := (g.case_pacing_mask & (u8(1) << u8(i))) != 0
		value := recorded ? pacing_time_label(g.case_pacing_times[i]) : "--:--"
		target := fmt.tprintf(
			"%s–%s",
			pacing_time_label(band_mins[i]),
			pacing_time_label(band_maxes[i]),
		)
		status :=
			recorded ? pacing_band_status(g.case_pacing_times[i], band_mins[i], band_maxes[i]) : "PENDING"
		result = fmt.tprintf(
			"%s\n%s: %s · target %s · %s",
			result,
			label,
			value,
			target,
			status,
		)}
	optional_ids := [7]string {
		"approach_miriam_edgar",
		"approach_daniel_edgar",
		"approach_elsie_edgar",
		"approach_daniel_memo_habit",
		"approach_elsie_burned_paper",
		"approach_elsie_explanation",
		"approach_miriam_other_lies",
	}; optional_labels := [7]string{"Miriam's clock memory", "Daniel's leverage memory", "Elsie's bell memory", "Edgar's memo habit", "Miriam's burning habit", "Elsie's sixteen pounds", "Three-way dinner confrontation"}; optional_count := 0; optional_text := ""; for id, i in optional_ids do if case_optional_beat_completed(g, id) {optional_count += 1; optional_text = fmt.tprintf("%s%s%s", optional_text, optional_text == "" ? "" : ", ", optional_labels[i])}; if optional_text == "" do optional_text = "none"
	return fmt.tprintf(
		"%s\nDesigned optional beats: %d/7 — %s\nOther optional scenes encountered:\nConfusion or dead air:\nFinal outcome:",
		result,
		optional_count,
		optional_text,
	)
}
copy_case_pacing_report :: proc(g: ^Game) {
	value := case_pacing_report_text(
		g,
	); clipboard, err := strings.clone_to_cstring(value, context.temp_allocator); if err == nil {_ = sdl.SetClipboardText(clipboard); log_line(g, "First-playthrough pace report copied to the clipboard.")} else do log_line(g, "The pace report could not be copied; open diagnostics to read the timestamps.")
}
topic_unlocked :: proc(g: ^Game, topic: string) -> bool {return(
		g.mystery_state != nil &&
		mystery_string_set_has(g.mystery_state.unlocked_topics[:], topic) \
	)}
unlock_topic :: proc(g: ^Game, topic: string) {if topic == "" || topic_unlocked(g, topic) || g.mystery_state == nil do return
	_ = mystery_string_set_add(&g.mystery_state.unlocked_topics, topic)}
claim_index :: proc(g: ^Game, id: string) -> int {return mystery_claim_index(
		mystery_game_payload(g),
		id,
	)}
claim_known :: proc(g: ^Game, id: string) -> bool {return(
		g.mystery_state != nil &&
		mystery_string_set_has(g.mystery_state.established_claims[:], id) \
	)}
learn_claim :: proc(g: ^Game, id: string) -> bool {i := claim_index(g, id); payload :=
		mystery_game_payload(g)
	if payload == nil || g.mystery_state == nil || i < 0 || claim_known(g, id) do return false
	if !mystery_establish_claim(g.story_project, g.mystery_state, id) do return false
	tutorial_complete(g, .Converse)
	claim := &payload.claims[i]
	log_line(
		g,
		fmt.tprintf(
			"Statement recorded: %s",
			mystery_story_proposition_text(g.story_project, claim.proposition_id),
		),
	)
	refresh_questions(g)
	if overtime_active(g) && proof_framework_attainable(g, payload.solution.culprit_id) do finish_overtime(g)
	return true}
learn_initial_claims :: proc(g: ^Game, character_id: string) -> int {
	learned := 0; payload := mystery_game_payload(g); if payload == nil do return 0
	metadata := mystery_character_metadata(
		payload,
		character_id,
	); if metadata != nil {for id in metadata.initial_claims[:metadata.initial_claim_count] {if learn_claim(g, id) do learned += 1}}
	refresh_questions(g)
	return learned
}
dialogue_approach_available :: proc(g: ^Game, index: int) -> bool {
	payload := mystery_game_payload(g); node := mystery_dialogue_approach_at(payload, index)
	if node == nil || (mystery_game_dialogue_completed(g, index) && !mystery_game_dialogue_failed(g, index)) do return false
	if g.mystery_state != nil && !mystery_node_requirements_met(g.story_project, g.mystery_state, node.node_id) do return false
	if node.clue_id !=
	   "" {clue := mystery_clue_index(payload, node.clue_id); return clue >= 0 && clue_available(g, clue)}
	return true
}
dialogue_approach_flow_priority :: proc(g: ^Game, index: int) -> int {
	payload := mystery_game_payload(
		g,
	); node := mystery_dialogue_approach_at(payload, index); if node == nil do return -1
	// Checks create evidence and should never be hidden behind optional color.
	priority := node.require_count * 10; if node.clue_id != "" do priority += 1000
	// Prefer a question whose discoveries unlock another currently unfinished
	// conversation. This keeps gateway accounts ahead of flavor while remaining
	// data-driven for other authored mysteries.
	for unlock in node.unlocks[:node.unlock_count] {
		for candidate_index in 0 ..< mystery_dialogue_approach_count(payload) {
			if candidate_index == index || mystery_game_dialogue_completed(g, candidate_index) do continue
			candidate := mystery_dialogue_approach_at(
				payload,
				candidate_index,
			); if candidate == nil do continue
			for requirement in candidate.requires[:candidate.require_count] do if requirement == unlock {priority += 100; break}
		}
	}
	return priority
}
visible_dialogue_approach :: proc(g: ^Game, character: string, slot: int) -> int {
	payload := mystery_game_payload(g); if slot < 0 do return -1
	selected: [32]bool
	for rank in 0 ..= slot {
		best, best_priority := -1, -1
		for i in 0 ..< mystery_dialogue_approach_count(payload) {
			if i >= len(selected) || selected[i] do continue
			node := mystery_dialogue_approach_at(
				payload,
				i,
			); if node == nil || node.character_id != character || !dialogue_approach_available(g, i) do continue
			priority := dialogue_approach_flow_priority(
				g,
				i,
			); if priority > best_priority {best = i; best_priority = priority}
		}
		if best < 0 do return -1
		if rank == slot do return best
		selected[best] = true
	}
	return -1
}
dialogue_approach_failure_topic :: proc(id: string) -> string {switch
	id {case "approach_daniel_affair":
		return "failed_daniel_affair"; case "approach_elsie_theft":
		return "failed_elsie_theft"}
	return ""}
dialogue_approach_failure_response :: proc(g: ^Game, index: int) -> string {
	payload := mystery_game_payload(
		g,
	); node := mystery_dialogue_approach_at(payload, index); if node == nil do return "The question lands badly. Try another angle."
	switch node.node_id {
	case "approach_daniel_affair":
		return(
			"'I have given you my account.' Daniel checks his inner pocket before meeting your eye. The sentence is rehearsed; the hand is not." \
		)
	case "approach_elsie_theft":
		return(
			"'You decided what I am before you asked.' Elsie's gaze returns to Edgar's desk, and one thumb counts silently against the side of her apron." \
		)
	}
	clue_index := mystery_clue_index(
		payload,
		node.clue_id,
	); if clue_index >= 0 {clue := &payload.clues[clue_index]; if clue.check_kind == "red" do return "They end that line of questioning. Their reaction remains part of the conversation."; return "They refuse the premise. Watch what they protect, then try another angle."}
	return "The question lands badly. Try another angle."
}
complete_dialogue_approach :: proc(g: ^Game, index: int) {payload := mystery_game_payload(g)
	node := mystery_dialogue_approach_at(payload, index)
	if node == nil do return
	_ = mystery_game_mark_dialogue(g, index, false)
	if g.mystery_state != nil do _ = mystery_apply_node_metadata(g.story_project, g.mystery_state, node.node_id)
	for id in node.unlocks[:node.unlock_count] {if clue := mystery_clue_index(payload, id); clue >= 0 do _ = discover_clue_free(g, clue)
		else if mystery_claim_index(payload, id) >= 0 do _ = learn_claim(g, id)
		else do unlock_topic(g, id)}
	g.dialogue_node = 0
	g.dialogue_response = ""
	g.dialogue_text_started = g.animation_time
	if g.screen == .Dialogue {g.dialogue_ledger_scroll = 0; g.dialogue_choice_page = 0}
	_ = apply_story_node_animation_asset(g, node.node_id)
	_ = play_story_node_sound(g, node.node_id)
	dialogue_focus_default(g)}
fail_dialogue_approach :: proc(g: ^Game, index: int) {node := mystery_dialogue_approach_at(
		mystery_game_payload(g),
		index,
	)
	if node == nil do return
	response := dialogue_approach_failure_response(g, index)
	topic := dialogue_approach_failure_topic(node.node_id)
	if topic != "" do unlock_topic(g, topic)
	_ = mystery_game_mark_dialogue(g, index, true)
	g.dialogue_node = 0
	g.dialogue_response = ""
	conversation_transcript_append(g, node.character_id, response, "action", node.character_id)
	g.dialogue_text_started = g.animation_time
	if g.screen == .Dialogue {g.dialogue_ledger_scroll = 0; g.dialogue_choice_page = 0}
	log_line(g, response)
	dialogue_focus_default(g)}
initialize_dispositions :: proc(g: ^Game) {payload := mystery_game_payload(g); if payload != nil && g.mystery_state != nil do for character in payload.characters {found := false; for disposition in g.mystery_state.dispositions do if disposition.entity_id == character.entity_id do found = true; if !found do mystery_game_set_disposition(g, character.entity_id, character.initial_disposition)}}
character_index :: proc(g: ^Game, id: string) -> int {payload := mystery_game_payload(g)
	if payload != nil do for character, i in payload.characters do if character.entity_id == id do return i
	return -1}
disposition_rect :: proc() -> Rect {return {976, 52, 174, 32}}
dialogue_disposition_label :: proc(value: int) -> string {state :=
		value > 0 ? "RECEPTIVE" : value < 0 ? "GUARDED" : "NEUTRAL"
	return fmt.tprintf("%s  ·  CHECK %+d", state, clamp(value, -2, 2))}
disposition_summary :: proc(g: ^Game, character_index: int) -> string {
	payload := mystery_game_payload(
		g,
	); if payload == nil || character_index < 0 || character_index >= len(payload.characters) do return "Their feelings are difficult to read."
	character := &payload.characters[character_index]; current := mystery_game_disposition(g, character.entity_id)
	if current > character.initial_disposition do return "Your successful approaches have made them more willing to engage."
	if current < character.initial_disposition do return "A failed approach left them guarded and less receptive."
	switch character.entity_id {
	case "miriam":
		return "She is composed and confident she can control the conversation."
	case "daniel":
		return "He is cautious, but has not decided whether you are a threat."
	case "elsie":
		return "She expects suspicion and is protecting herself from accusation."
	}
	return current > 0 ? "They are presently receptive." : "They are presently guarded."
}
clue_disposition :: proc(g: ^Game, clue_index: int) -> int {payload := mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return 0
	i := character_index(g, payload.clues[clue_index].source_id)
	if i < 0 do return 0
	return mystery_game_disposition(g, payload.characters[i].entity_id)}
apply_check_disposition :: proc(g: ^Game, clue_index: int, success: bool) -> int {payload :=
		mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return 0
	i := character_index(g, payload.clues[clue_index].source_id)
	if i < 0 do return 0
	delta := success ? 1 : -1
	id := payload.characters[i].entity_id
	before := mystery_game_disposition(g, id)
	mystery_game_set_disposition(g, id, before + delta)
	return mystery_game_disposition(g, id) - before}
action_warning_text :: proc(g: ^Game) -> string {if g.ap <= 2 do return "DEADLINE IMMINENT — only two clock ticks remain"
	if g.ap <= 4 do return "Time is narrowing — four clock ticks remain"
	return ""}
load_sound_assets :: proc(g: ^Game) -> int {
	paths := [Sound_Cue]string {
			.Evidence       = "assets/audio/cues/clue-revealed.ogg",
			.Fact           = "assets/audio/cues/fact-established.ogg",
			.Pick_Up        = "assets/kenney_ui-audio/Audio/click3.ogg",
			.Snap           = "assets/kenney_ui-audio/Audio/switch31.ogg",
			.Reject         = "assets/kenney_ui-audio/Audio/switch8.ogg",
			.Recreate       = "assets/kenney_ui-audio/Audio/switch20.ogg",
			.Shutter        = "assets/audio/cues/crank-resistance.ogg",
			.Sightline_Fail = "assets/kenney_ui-audio/Audio/switch10.ogg",
			.Tick           = "assets/kenney_ui-audio/Audio/switch7.ogg",
			.Reveal_Proven  = "assets/audio/cues/reveal-section-proven.ogg",
			.Door_Open      = "assets/audio/cues/wood-open.ogg",
			.Door_Close     = "assets/audio/cues/wood-close.ogg",
			.Switch         = "assets/kenney_ui-audio/Audio/switch13.ogg",
			.Decisive_Clue  = "assets/audio/cues/decisive-clue.ogg",
			.Candle_Out     = "assets/audio/cues/candle-extinguished.ogg",
			.Shutter_Close  = "assets/audio/cues/wood-close.ogg",
		}; loaded := 0
	for cue in Sound_Cue {path := paths[cue]; channels, sample_rate: i32; decoded: [^]i16
		frames := stb_vorbis_decode_filename(
			strings.clone_to_cstring(path, context.temp_allocator),
			&channels,
			&sample_rate,
			&decoded,
		)
		if frames <= 0 || decoded == nil || channels <= 0 {continue}
		defer chicago_vorbis_free(decoded)
		if sample_rate != 44100 do continue
		frame_count := int(frames)
		g.sounds[cue] = make([dynamic]f32, frame_count)
		for frame in 0 ..< frame_count {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768
			g.sounds[cue][frame] = mixed / f32(channels)}
		loaded += 1}
	return loaded
}
destroy_sound_assets :: proc(g: ^Game) {for &samples in g.sounds do if samples != nil do delete(samples)}
play_sound :: proc(g: ^Game, cue: Sound_Cue) {
	if g.mute || g.audio_stream == nil do return
	if len(g.sounds[cue]) >
	   0 {samples := g.sounds[cue]; _ = sdl.PutAudioStreamData(g.audio_stream, rawptr(&samples[0]), i32(len(samples) * size_of(f32))); return}
	// A generated click remains as a defensive fallback if an asset is missing.
	frequencies := [Sound_Cue]f32 {
		.Evidence       = 880,
		.Fact           = 660,
		.Pick_Up        = 420,
		.Snap           = 760,
		.Reject         = 145,
		.Recreate       = 330,
		.Shutter        = 95,
		.Sightline_Fail = 180,
		.Tick           = 120,
		.Reveal_Proven  = 990,
		.Door_Open      = 260,
		.Door_Close     = 220,
		.Switch         = 520,
		.Decisive_Clue  = 740,
		.Candle_Out     = 80,
		.Shutter_Close  = 110,
	}; durations := [Sound_Cue]f32 {
		.Evidence       = .16,
		.Fact           = .22,
		.Pick_Up        = .08,
		.Snap           = .12,
		.Reject         = .13,
		.Recreate       = .22,
		.Shutter        = .28,
		.Sightline_Fail = .18,
		.Tick           = .24,
		.Reveal_Proven  = .25,
		.Door_Open      = .18,
		.Door_Close     = .18,
		.Switch         = .1,
		.Decisive_Clue  = .32,
		.Candle_Out     = .14,
		.Shutter_Close  = .3,
	}; frequency :=
		frequencies[cue]; sample_count := min(int(44100 * durations[cue]), 12000); samples: [12000]f32
	for i in 0 ..< sample_count {t := f32(i) / 44100; envelope := 1 - f32(i) / f32(sample_count); wave := f32(math.sin(f64(2 * math.PI * frequency * t))); if cue == .Shutter do wave = wave * .55 + f32(math.sin(f64(2 * math.PI * (frequency * .5) * t))) * .45; if cue == .Reject || cue == .Sightline_Fail do frequency *= .99994; samples[i] = wave * envelope * .16}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(sample_count * size_of(f32)),
	)
}

play_story_node_sound :: proc(g: ^Game, node_id: string) -> bool {if g == nil || g.mute || g.audio_stream == nil do return false
	path, ok := story_node_sound_path(g.story_project, &authoring_workspace.assets, node_id)
	if !ok || !os.is_file(path) do return false
	channels, sample_rate: i32
	decoded: [^]i16
	frames := stb_vorbis_decode_filename(
		strings.clone_to_cstring(path, context.temp_allocator),
		&channels,
		&sample_rate,
		&decoded,
	)
	if frames <= 0 || decoded == nil || channels <= 0 || sample_rate != 44100 do return false
	defer chicago_vorbis_free(decoded)
	samples := make([]f32, int(frames), context.temp_allocator)
	for 	frame in 0 ..< int(frames) {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768
		samples[frame] = mixed / f32(channels)}
	return sdl.PutAudioStreamData(
		g.audio_stream,
		raw_data(samples),
		i32(len(samples) * size_of(f32)),
	)}

project_asset_audio_preview_info :: proc(
	project_root: string,
	registry: ^Project_Asset_Registry,
	id: string,
) -> (
	frames, channels, sample_rate: int,
	ready: bool,
) {if registry == nil do return; index := project_asset_index(registry, id); if index < 0 || registry.assets[index].kind != .Audio do return
	path := project_asset_record_path(project_root, registry.assets[index])
	if !os.is_file(path) do return
	if strings.to_lower(os.ext(path)) == ".ogg" {decoded_channels, decoded_rate: i32
		decoded: [^]i16
		decoded_frames := stb_vorbis_decode_filename(
			strings.clone_to_cstring(path, context.temp_allocator),
			&decoded_channels,
			&decoded_rate,
			&decoded,
		)
		if decoded != nil do chicago_vorbis_free(decoded)
		return int(decoded_frames),
			int(decoded_channels),
			int(decoded_rate),
			decoded_frames > 0 && decoded_channels > 0 && decoded_rate == 44100}
	data, err := os.read_entire_file_from_path(path, context.temp_allocator)
	if err != nil || len(data) < 44 || string(data[:4]) != "RIFF" do return
	channels = int(project_asset_u16_le(data, 22))
	sample_rate = int(project_asset_u32_le(data, 24))
	bits := int(project_asset_u16_le(data, 34))
	if channels <= 0 || sample_rate != 44100 || bits != 16 do return
	at := 12
	for at + 8 <= len(data) {size := int(project_asset_u32_le(data, at + 4)); if at + 8 + size > len(data) do break
		if string(data[at:at + 4]) == "data" {frames = size / (channels * 2); return frames,
				channels,
				sample_rate,
				frames > 0}
		at += 8 + size + (size & 1)}
	return}

apply_story_node_animation_asset :: proc(g: ^Game, node_id: string) -> bool {if g == nil || g.story_project == nil do return false
	path, ok := story_node_animation_path(g.story_project, &authoring_workspace.assets, node_id)
	if !ok || !os.is_file(path) do return false
	mesh, loaded := glb_load(path)
	if !loaded || !mesh.ready do return false
	node_index := project_asset_story_node_index(g.story_project, node_id)
	if node_index < 0 do return false
	actor := g.story_project.nodes[node_index].actor
	if actor == "" do actor = g.story_project.nodes[node_index].speaker_id
	payload := mystery_game_payload(g)
	if payload == nil do return false
	for character, i in payload.characters do if character.entity_id == actor && i + 1 < len(character_meshes) {character_meshes[i + 1] = mesh; return true}
	return false}

play_project_asset_audio :: proc(g: ^Game, registry: ^Project_Asset_Registry, id: string) -> bool {
	if g == nil || registry == nil || g.mute || g.audio_stream == nil do return false
	_, _, _, ready := project_asset_audio_preview_info(
		active_authoring_project.root_path,
		registry,
		id,
	); if !ready do return false
	index := project_asset_index(
		registry,
		id,
	); if index < 0 || registry.assets[index].kind != .Audio do return false
	path := project_asset_record_path(
		active_authoring_project.root_path,
		registry.assets[index],
	); if !os.is_file(path) do return false
	// OGG is decoded through the same production path used by authored sound
	// cues. WAV PCM16 previews are converted directly from the validated RIFF
	// payload so every supported authoring audio format can be auditioned.
	if strings.to_lower(os.ext(path)) ==
	   ".ogg" {channels, sample_rate: i32; decoded: [^]i16; frames := stb_vorbis_decode_filename(strings.clone_to_cstring(path, context.temp_allocator), &channels, &sample_rate, &decoded); if frames <= 0 || decoded == nil || channels <= 0 || sample_rate != 44100 do return false; defer chicago_vorbis_free(decoded); samples := make([]f32, int(frames), context.temp_allocator); for frame in 0 ..< int(frames) {mixed: f32 = 0; for channel in 0 ..< int(channels) do mixed += f32(decoded[frame * int(channels) + channel]) / 32768; samples[frame] = mixed / f32(channels)}; return sdl.PutAudioStreamData(g.audio_stream, raw_data(samples), i32(len(samples) * size_of(f32)))}
	data, err := os.read_entire_file_from_path(
		path,
		context.temp_allocator,
	); if err != nil || len(data) < 44 || string(data[:4]) != "RIFF" do return false
	channels := int(
		project_asset_u16_le(data, 22),
	); sample_rate := int(project_asset_u32_le(data, 24)); bits := int(project_asset_u16_le(data, 34)); if channels <= 0 || sample_rate != 44100 || bits != 16 do return false
	at := 12; payload: []u8; for at + 8 <= len(data) {size := int(project_asset_u32_le(data, at + 4)); if at + 8 + size > len(data) do break; if string(data[at:at + 4]) == "data" {payload = data[at + 8:at + 8 + size]; break}; at += 8 + size + (size & 1)}; if len(payload) < channels * 2 do return false
	frames :=
		len(payload) /
		(channels *
				2); samples := make([]f32, frames, context.temp_allocator); for frame in 0 ..< frames {mixed: f32 = 0; for channel in 0 ..< channels {sample_at := (frame * channels + channel) * 2; raw := i16(u16(payload[sample_at]) | u16(payload[sample_at + 1]) << 8); mixed += f32(raw) / 32768}; samples[frame] = mixed / f32(channels)}; return sdl.PutAudioStreamData(g.audio_stream, raw_data(samples), i32(len(samples) * size_of(f32)))
}

update_vehicle_drive_audio :: proc(g: ^Game, v: Vehicle_State, tune: Vehicle_Tune, throttle: f32) {
	if g == nil || g.mute || g.vehicle_audio_stream == nil do return
	target_frequency, target_gain := vehicle_engine_targets(v, tune, throttle)
	if g.vehicle_audio_frequency <= 0 do g.vehicle_audio_frequency = target_frequency
	g.vehicle_audio_frequency += (target_frequency - g.vehicle_audio_frequency) * .10
	g.vehicle_audio_gain += (target_gain - g.vehicle_audio_gain) * .14
	target_tire_gain := max(
		vehicle_tire_audio_target_blended(v, v.handbrake_slip),
		vehicle_assist_audio_gain(v.driver_assist, v.driver_assist_strength, v.driver_assist_time),
	); g.vehicle_audio_tire_gain += (target_tire_gain - g.vehicle_audio_tire_gain) * .18
	target_tire_frequency_a, target_tire_frequency_b := vehicle_tire_audio_frequencies_for_vehicle(
		v,
		v.traction_state,
		v.driver_assist,
		v.driver_assist_strength,
	); g.vehicle_audio_tire_frequency_a = vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_a, target_tire_frequency_a); g.vehicle_audio_tire_frequency_b = vehicle_tire_frequency_step(g.vehicle_audio_tire_frequency_b, target_tire_frequency_b)
	target_rough_gain :=
		vehicle_rough_feedback_blended(v, v.surface_blend) *
		.026; g.vehicle_audio_rough_gain += (target_rough_gain - g.vehicle_audio_rough_gain) * .16
	rough_frequency := vehicle_rough_audio_frequency(v)
	// One exact fixed-tick chunk keeps latency bounded and makes synthesis
	// deterministic regardless of render rate. A dedicated stream lets UI cues
	// overlap the engine instead of waiting behind it in a shared queue.
	samples: [735]f32
	for i in 0 ..< len(samples) {
		phase :=
			g.vehicle_audio_phase; fundamental := f32(math.sin(f64(phase))); second := f32(math.sin(f64(phase * 2))); fourth := f32(math.sin(f64(phase * 4)))
		pulse := fundamental * .58 + second * .28 + fourth * .14
		// Independent incommensurate phases produce a stable scrub texture. Each
		// oscillator wraps on its own full cycle, avoiding discontinuities.
		tire_a := f32(
			math.sin(f64(g.vehicle_audio_tire_phase_a)),
		); tire_b := f32(math.sin(f64(g.vehicle_audio_tire_phase_b))); tire := tire_a * .62 + tire_b * .38
		rough :=
			f32(math.sin(f64(g.vehicle_audio_rough_phase))) * .72 +
			f32(math.sin(f64(g.vehicle_audio_rough_phase * 2))) * .28
		samples[i] =
			pulse * g.vehicle_audio_gain +
			tire * g.vehicle_audio_tire_gain +
			rough * g.vehicle_audio_rough_gain
		g.vehicle_audio_phase += f32(2 * math.PI) * g.vehicle_audio_frequency / 44100
		if g.vehicle_audio_phase > f32(2 * math.PI) do g.vehicle_audio_phase -= f32(2 * math.PI)
		g.vehicle_audio_tire_phase_a +=
			f32(2 * math.PI) *
			g.vehicle_audio_tire_frequency_a /
			44100; g.vehicle_audio_tire_phase_b += f32(2 * math.PI) * g.vehicle_audio_tire_frequency_b / 44100
		if g.vehicle_audio_tire_phase_a > f32(2 * math.PI) do g.vehicle_audio_tire_phase_a -= f32(2 * math.PI)
		if g.vehicle_audio_tire_phase_b > f32(2 * math.PI) do g.vehicle_audio_tire_phase_b -= f32(2 * math.PI)
		g.vehicle_audio_rough_phase +=
			f32(2 * math.PI) *
			rough_frequency /
			44100; if g.vehicle_audio_rough_phase > f32(2 * math.PI) do g.vehicle_audio_rough_phase -= f32(2 * math.PI)
	}
	_ = sdl.PutAudioStreamData(
		g.vehicle_audio_stream,
		rawptr(&samples[0]),
		i32(len(samples) * size_of(f32)),
	)
}

play_vehicle_impact_sound :: proc(g: ^Game, impact: f32) {
	if g == nil || g.mute || g.audio_stream == nil do return
	frequency, gain, duration := vehicle_impact_audio_parameters(
		impact,
	); sample_count := min(int(duration * 44100), 7056); samples: [7056]f32
	for i in 0 ..< sample_count {
		t :=
			f32(i) /
			44100; envelope := f32(math.exp(f64(-t * (24 + impact * 18)))); body := f32(math.sin(f64(2 * math.PI * frequency * t))); knock := f32(math.sin(f64(2 * math.PI * (frequency * 2.73) * t)))
		// A deterministic high partial supplies the initial contact without noise
		// generators or assets; the low body carries perceived impact weight.
		attack := clamp(
			1 - t / .006,
			0,
			1,
		); samples[i] = (body * .72 + knock * .28 * attack) * envelope * gain
	}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(sample_count * size_of(f32)),
	)
}

play_check_dice_sound :: proc(g: ^Game) {
	if g == nil || g.audio_stream == nil do return
	// A short deterministic wooden rattle: six decaying impacts accelerate,
	// then leave room for the settled result cue.
	sample_rate: f32 = 44100; sample_count := int(CHECK_ROLL_DURATION * sample_rate); samples := make([]f32, sample_count, context.temp_allocator)
	impacts := [6]f32{.05, .17, .31, .48, .70, 1.02}
	for i in 0 ..< sample_count {t := f32(i) / sample_rate; value: f32 = 0; for impact, index in impacts {age := t - impact; if age < 0 || age > .09 do continue; decay := f32(math.exp(f64(-age * 55))); frequency := f32(520 + index * 73); value += f32(math.sin(f64(2 * math.PI * frequency * age))) * decay * .11}; samples[i] = value}
	_ = sdl.PutAudioStreamData(
		g.audio_stream,
		rawptr(&samples[0]),
		i32(len(samples) * size_of(f32)),
	)
}

late_case_clock_line :: proc(g: ^Game) -> string {
	elsie :=
		knowledge_piece_known(g, "clue_elsie") ? "Elsie keeps clear of the cash box now." : "Elsie hovers near Edgar's cash box, a folded banknote in hand."
	miriam :=
		knowledge_piece_known(g, "clue_burned_fragment") ? "Miriam watches the scorched fragment without speaking." : "Miriam watches each new piece of evidence without speaking."
	return fmt.tprintf("The clock advances again. %s %s", elsie, miriam)
}

consume_action :: proc(g: ^Game, cost: int) {
	if cost <= 0 || cost > g.ap do return
	before := g.ap
	g.ap -= cost; play_sound(g, .Tick); play_sound(g, .Candle_Out)
	if !g.threshold_four_spent && before > 8 && g.ap <= 8 {
		g.threshold_four_spent = true
		unlock_topic(g, "household_tension")
		log_line(
			g,
			"The clock advances. Daniel grows visibly nervous; Miriam warns the room against speculation.",
		)
	}
	if !g.threshold_eight_spent && before > 4 && g.ap <= 4 {
		g.threshold_eight_spent = true
		unlock_topic(g, "late_case_changes")
		log_line(g, late_case_clock_line(g))
	}
	if before > 4 && g.ap <= 4 do log_line(g, "Four clock ticks remain. Test your reconstruction while time remains.")
	if before > 2 && g.ap <= 2 do log_line(g, "Two clock ticks remain. Prepare your final account.")
	if g.ap <=
	   0 {g.ap = 0; payload := mystery_game_payload(g); culprit := payload != nil ? payload.solution.culprit_id : ""; if !proof_framework_attainable(g, culprit) && begin_proof_overtime(g) {log_line(g, "Protected overtime is active for the shortest remaining proof route.")} else {g.investigation_locked = true; g.phase = .Reveal_Preparation; g.game_over_reason = ""; if !g.check_from_dialogue {g.board_view = 0; g.screen = .Board; log_line(g, "The investigation clock is spent. Use the facts already gathered to prepare an accusation.")}}}
}
spend :: proc(g: ^Game, clue: int) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue < 0 || clue >= len(payload.clues) || g.ap <= 0 || mystery_game_clue_discovered(g, clue) || payload.clues[clue].cost > g.ap do return
	_ = mystery_game_mark_clue(
		g,
		clue,
	); mystery_game_mark_clue_attempted(g, clue); g.case_sense_level = 0; play_sound(g, .Evidence)
	if g.mystery_state != nil do _ = mystery_acquire_evidence(g.story_project, g.mystery_state, payload.clues[clue].id)
	refresh_questions(g)
	consume_action(g, payload.clues[clue].cost)
	for topic in payload.clues[clue].topics[:payload.clues[clue].topic_count] do unlock_topic(g, topic)
	log_line(g, mystery_clue_proposition_text(g.story_project, &payload.clues[clue]))
}

source_location :: proc(g: ^Game, clue: int) -> int {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue < 0 || clue >= len(payload.clues) do return -1; source := payload.clues[clue].source_id
	for &location, i in payload.locations {
		if location.entity_id == source do return i
		for j in 0 ..< location.character_count do if location.characters[j] == source do return i
		for j in 0 ..< location.poi_count do if location.pois[j] == source do return i
	}
	return -1
}
overtime_active :: proc(g: ^Game) -> bool {if g.overtime_clue_plus_one > 0 do return true
	payload := mystery_game_payload(g)
	if payload != nil do for _, i in payload.clues do if mystery_game_clue_overtime_free(g, i) do return true
	return false}
overtime_clue :: proc(g: ^Game) -> int {return g.overtime_clue_plus_one - 1}
overtime_lead :: proc(g: ^Game) -> int {return g.overtime_lead_plus_one - 1}
clue_is_overtime_action :: proc(g: ^Game, clue: int) -> bool {return(
		mystery_game_clue_overtime_free(g, clue) ||
		g.overtime_clue_plus_one > 0 && (clue == overtime_clue(g) || clue == overtime_lead(g)) \
	)}
clue_action_cost :: proc(g: ^Game, clue: int) -> int {if clue_is_overtime_action(g, clue) do return 0
	payload := mystery_game_payload(g)
	if payload == nil || clue < 0 || clue >= len(payload.clues) do return 0
	return payload.clues[clue].cost}

mark_overtime_prerequisites :: proc(g: ^Game, clue_index: int) {payload := mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return
	target := &payload.clues[clue_index]
	for j in 0 ..< target.prerequisite_count {prerequisite := target.prerequisites[j]; for clue, i in payload.clues do if clue.id == prerequisite && !mystery_game_clue_discovered(g, i) {mystery_game_set_clue_overtime_free(g, i, true); mark_overtime_prerequisites(g, i)}}}
mark_recovery_prerequisites :: proc(g: ^Game, clue_index: int, used: ^[16]bool) {payload :=
		mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return
	target := &payload.clues[clue_index]
	for 	k in 0 ..< target.prerequisite_count {prerequisite := target.prerequisites[k]; for clue, i in payload.clues do if clue.id == prerequisite && !mystery_game_clue_discovered(g, i) && !used[i] {used[i] = true; mark_recovery_prerequisites(g, i, used)}}}
mark_recovery_route :: proc(g: ^Game, demo_index, route: int, used: ^[16]bool) -> bool {
	payload := mystery_game_payload(
		g,
	); if demo_index < 0 do return true; if payload == nil || demo_index >= len(payload.demonstrations) do return false
	demo := &payload.demonstrations[demo_index]
	for slot in 0 ..< demo.route_counts[route] {ref := mystery_demonstration_route_piece(demo, route, slot); clue_found := false; for clue, ci in payload.clues do if clue.id == ref {clue_found = true; if !mystery_game_clue_discovered(g, ci) && !used[ci] {used[ci] = true; mark_recovery_prerequisites(g, ci, used)}}; if !clue_found && !knowledge_piece_known(g, ref) && mystery_knowledge_piece_type(g, ref) == "deduction" do return false}
	return true
}
begin_proof_overtime :: proc(g: ^Game) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil do return false; bad_luck := false; for _, i in payload.clues do if mystery_game_clue_attempted(g, i) && !mystery_game_clue_discovered(g, i) && payload.clues[i].essential do bad_luck = true
	if !bad_luck do return false
	routes: [3][32][2]int; counts: [3]int
	for pillar in 0 ..< 3 {
		if proof_pillar_attainable(
			g,
			payload.solution.culprit_id,
			pillar,
		) {routes[pillar][0] = {-1, -1}; counts[pillar] = 1; continue}
		wanted := fmt.tprintf(
			"%s:%s",
			payload.solution.culprit_id,
			proof_pillar_name(pillar),
		); for &demo, di in payload.demonstrations {supports := false; for ri in 0 ..< demo.result_count {result := demo.result_deductions[ri]; for &deduction in payload.deductions do if deduction.id == result {for si in 0 ..< deduction.support_count do if deduction.supports[si] == wanted do supports = true}}; if supports do for route in 0 ..< demo.route_count {probe: [16]bool; if mark_recovery_route(g, di, route, &probe) && counts[pillar] < 32 {routes[pillar][counts[pillar]] = {di, route}; counts[pillar] += 1}}}; if counts[pillar] == 0 do return false
	}
	best_cost := 1 << 20; best_used: [16]bool
	for mi in 0 ..< counts[0] do for wi in 0 ..< counts[1] do for oi in 0 ..< counts[2] {used: [16]bool; chosen := [3][2]int{routes[0][mi], routes[1][wi], routes[2][oi]}; viable := true; for pair in chosen do if !mark_recovery_route(g, pair[0], pair[1], &used) do viable = false; cost := 0; for selected, i in used do if selected && i < len(payload.clues) do cost += payload.clues[i].cost; if viable && cost < best_cost {best_cost = cost; best_used = used}}
	if best_cost == 1 << 20 do return false
	mystery_game_clear_overtime_free(
		g,
	); first := -1; for free, i in best_used do if free {mystery_game_set_clue_overtime_free(g, i, true); if first < 0 do first = i}; if first < 0 do return false
	g.overtime_clue_plus_one =
		first +
		1; g.overtime_lead_plus_one = 0; g.investigation_locked = false; g.phase = .Investigation; g.game_over_reason = ""; if !g.check_from_dialogue do g.screen = .Investigate
	return true
}
next_failure_lead :: proc(g: ^Game, clue_index: int) -> int {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return -1
	for &candidate, i in payload.clues do if i != clue_index && !mystery_game_clue_discovered(g, i) && !mystery_game_clue_attempted(g, i) && clues_semantically_related(&payload.clues[clue_index], &candidate) {
		ready := true; for k in 0 ..< candidate.prerequisite_count {prerequisite := candidate.prerequisites[k]; found := false; for known, j in payload.clues do if known.id == prerequisite && mystery_game_clue_discovered(g, j) do found = true; if !found do ready = false}
		if ready do return i
	}
	return -1
}
begin_overtime :: proc(g: ^Game, clue_index: int) {
	g.overtime_clue_plus_one =
		clue_index +
		1; lead := next_failure_lead(g, clue_index); g.overtime_lead_plus_one = lead + 1
	g.investigation_locked =
		false; g.phase = .Investigation; g.game_over_reason = ""; if !g.check_from_dialogue do g.screen = .Check
	payload := mystery_game_payload(
		g,
	); if lead >= 0 && payload != nil {log_line(g, fmt.tprintf("OVERTIME — examine %s. %s Then retry the failed check.", case_sense_source_name(g, lead), payload.clues[lead].description))} else {log_line(g, "OVERTIME — all supporting leads have been pursued. Reconsider the evidence and retry the failed check.")}
}
finish_overtime :: proc(g: ^Game) {mystery_game_clear_overtime_free(g)
	g.overtime_clue_plus_one = 0
	g.overtime_lead_plus_one = 0
	g.investigation_locked = true
	g.phase = .Reveal_Preparation
	g.board_view = 0
	g.screen = .Board}
overtime_guidance :: proc(g: ^Game) -> string {lead := overtime_lead(g); payload :=
		mystery_game_payload(g)
	if payload != nil && lead >= 0 && !mystery_game_clue_discovered(g, lead) && !mystery_game_clue_attempted(g, lead) do return fmt.tprintf("OVERTIME: examine %s. %s Then retry this check.", case_sense_source_name(g, lead), payload.clues[lead].description)
	return "OVERTIME: reconsider the gathered evidence and retry this check."}
clue_available :: proc(g: ^Game, clue: int) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue < 0 || clue >= len(payload.clues) do return false
	if overtime_active(g) && !clue_is_overtime_action(g, clue) do return false
	if mystery_game_clue_discovered(g, clue) || clue_action_cost(g, clue) > g.ap do return false
	// The statuette conclusion combines two separately authored observations:
	// blood beneath the shifted rug and blood missed inside the polished base
	// seam. Do not let the final wound-match check invent either discovery.
	if game_entity_has_tag(g, payload.clues[clue].source_id, "statuette_examination") && (!g.study_rug_lifted || !g.study_seam_found) do return false
	// One-shot checks close after an attempt. Retryable checks remain available
	// while the player can afford their tick cost.
	if !clue_is_overtime_action(g, clue) && mystery_game_clue_attempted(g, clue) && payload.clues[clue].check_kind == "red" do return false
	for k in 0 ..< payload.clues[clue].prerequisite_count {prerequisite := payload.clues[clue].prerequisites[k]
		found := false
		for known, i in payload.clues do if known.id == prerequisite && mystery_game_clue_discovered(g, i) do found = true
		if !found do return false
	}
	return true
}

clue_source_in_current_room :: proc(g: ^Game, clue_index: int) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return false
	player_room := world_authored_room_at_point({g.player_x, g.player_y})
	if player_room < 0 do return false
	entity := world_entity_index(payload.clues[clue_index].source_id)
	if entity >= 0 {
		source_room := world_authored_room_at_point(
			{WORLD_ENTITIES[entity].x, WORLD_ENTITIES[entity].y},
		)
		return source_room == player_room
	}
	// Non-spatial sources retain their authored investigative-location fallback.
	location := world_location_index(g)
	return location >= 0 && source_location(g, clue_index) == location
}

case_sense_target :: proc(g: ^Game) -> (clue_index: int, local: bool) {
	payload := mystery_game_payload(
		g,
	); if payload == nil do return -1, false; for _, i in payload.clues do if clue_available(g, i) && clue_source_in_current_room(g, i) do return i, true
	for _, i in payload.clues do if clue_available(g, i) do return i, false
	return -1, false
}

room_has_available_lead :: proc(g: ^Game) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload != nil do for _, i in payload.clues do if clue_available(g, i) && clue_source_in_current_room(g, i) do return true
	return false
}

case_sense_source_name :: proc(g: ^Game, clue_index: int) -> string {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return "the case"
	source := payload.clues[clue_index].source_id
	if g.story_project !=
	   nil {index := story_entity_index(g.story_project, source); if index >= 0 do return g.story_project.entities[index].display_name}
	return source
}

vk_draw_case_sense :: proc(r: ^Vulkan_Backend, g: ^Game) {
	local := room_has_available_lead(g)
	control := fmt.tprintf("[%s] ROOM HINT", prompt_label(g, .Room_Hint))
	if g.case_sense_level ==
	   0 {status := local ? "MORE TO LEARN HERE" : "NOTHING TO SEE HERE"; color := local ? [4]u8{255, 211, 92, 255} : [4]u8{117, 229, 169, 225}; vk_text(r, 20, 158, fmt.tprintf("%s  ·  %s", status, control), color, .62); return}
	body :=
		local ? "There is still something to investigate in this room." : "Nothing currently available here; another room may hold a lead."
	body_scale: f32 = .74; body_y := f32(122); body_line_spacing := f32(4); body_bottom := body_y + f32(wrapped_line_count(body, 372, body_scale)) * (f32(COURIER_CELL_HEIGHT) * body_scale + body_line_spacing); footer_y := body_bottom + 4; height := footer_y + f32(COURIER_CELL_HEIGHT) * .58 + 9 - 88
	body_y += 62; footer_y += 62; vulkan_ui_rect(r, 18, 150, 410, height, {14, 16, 20, 222}); vulkan_ui_outline(r, 18, 150, 410, height, {116, 91, 48, 210}, 1); vk_text(r, 34, 165, "ROOM HINT", {255, 211, 92, 255}, .72); _ = vk_text_wrapped(r, 34, body_y, 372, body, {248, 247, 242, 255}, body_scale, body_line_spacing); footer := fmt.tprintf("5 SEC  ·  TAP [%s] TO CLOSE", prompt_label(g, .Room_Hint)); vk_text(r, 34, footer_y, footer, {205, 207, 210, 255}, .58)
}
clues_semantically_related :: proc(target, candidate: ^Mystery_Clue) -> bool {for i in 0 ..< target.prerequisite_count do if candidate.id == target.prerequisites[i] do return true
	for 	i in 0 ..< target.topic_count {for j in 0 ..< candidate.topic_count do if target.topics[i] == candidate.topics[j] do return true}
	return false}
relevant_evidence_for_clue :: proc(g: ^Game, clue_index: int) -> int {payload :=
		mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return -1
	if character_index(g, payload.clues[clue_index].source_id) < 0 do return -1
	for &candidate, i in payload.clues do if i != clue_index && mystery_game_clue_discovered(g, i) && clues_semantically_related(&payload.clues[clue_index], &candidate) do return i
	return -1}
present_evidence :: proc(g: ^Game, clue_index: int) -> bool {payload := mystery_game_payload(g)
	if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) || mystery_game_evidence_presented(g, clue_index) do return false
	source := relevant_evidence_for_clue(g, clue_index)
	if source < 0 do return false
	_ = mystery_game_mark_evidence_presented(g, clue_index)
	log_line(
		g,
		fmt.tprintf(
			"Evidence presented: %s",
			mystery_clue_proposition_text(g.story_project, &payload.clues[source]),
		),
	)
	return true}
clue_situational_bonus :: proc(g: ^Game, clue_index: int) -> int {if clue_index >= 0 && mystery_game_evidence_presented(g, clue_index) do return 10
	return 0}
clue_reopen_score :: proc(g: ^Game, clue_index: int) -> int {score :=
		clue_evidence_bonus(g, clue_index) +
		(mystery_game_evidence_presented(g, clue_index) ? 1 : 0)
	payload := mystery_game_payload(g)
	if payload != nil do for &candidate, i in payload.clues do if i != clue_index && mystery_game_clue_attempted(g, i) && !mystery_game_clue_discovered(g, i) && clues_semantically_related(&payload.clues[clue_index], &candidate) do score += 1
	return score}
check_retry_label :: proc(kind: string) -> string {return kind == "red" ? "ONE-SHOT" : "RETRYABLE"}
clue_evidence_bonus :: proc(g: ^Game, clue_index: int) -> int {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return 0; target := &payload.clues[clue_index]; bonus := 0
	for &candidate, i in payload.clues do if i != clue_index && mystery_game_clue_discovered(g, i) && clues_semantically_related(target, &candidate) do bonus += 1
	return min(bonus, 3)
}
clue_locked_label :: proc(g: ^Game, clue: int) -> string {
	if overtime_active(g) && !clue_is_overtime_action(g, clue) do return "LOCKED — OVERTIME IS LIMITED TO THE ACTIVE LEAD"
	if clue_action_cost(g, clue) > g.ap do return "LOCKED — NOT ENOUGH TICKS"
	payload := mystery_game_payload(
		g,
	); if payload != nil && mystery_game_clue_attempted(g, clue) && payload.clues[clue].check_kind == "red" do return "NON-RETRYABLE CHECK EXPIRED"
	if payload != nil &&
	   clue >= 0 &&
	   clue < len(payload.clues) &&
	   game_entity_has_tag(g, payload.clues[clue].source_id, "statuette_examination") {
		if !g.study_rug_lifted do return "LOCKED — EXPOSE WHAT THE SHIFTED RUG CONCEALS"
		if !g.study_seam_found do return "LOCKED — FIND THE DETAIL MISSED ON THE POLISHED BRONZE"
	}
	return "LOCKED — NEED PRIOR EVIDENCE"
}
resolve_clue_check :: proc(g: ^Game, clue_index: int) -> Check_Result {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) || !clue_available(g, clue_index) do return {}
	clue := &payload.clues[clue_index]; cost := clue_action_cost(g, clue_index); was_overtime_target := overtime_active(g) && clue_index == overtime_clue(g); result := skill_check(&g.seed, skill_index(clue.skill), clue.difficulty, clue_evidence_bonus(g, clue_index), clue_disposition(g, clue_index), clue_situational_bonus(g, clue_index))
	if g.persist_seed && !persist_story_seed(g.seed) do fmt.eprintln("warning: could not persist advanced story RNG state")
	g.check_disposition_delta = apply_check_disposition(g, clue_index, result.success)
	mystery_game_mark_clue_attempted(g, clue_index)
	if result.success {
		if clue_is_overtime_action(
			g,
			clue_index,
		) {_ = discover_clue_free(g, clue_index); mystery_game_set_clue_overtime_free(g, clue_index, false); if proof_framework_attainable(g, payload.solution.culprit_id) do finish_overtime(g)} else {spend(g, clue_index)}
		if game_entity_has_tag(
			g,
			clue.source_id,
			"statuette_examination",
		) {g.study_statuette_held = true; g.study_wound_matched = true; g.study_seam_found = true; g.study_oil_found = true}
		if game_entity_has_tag(g, clue.source_id, "shutter_mechanism") do g.shutter_thread_found = true
	} else {
		consume_action(g, cost)
		failure_line :=
			clue.check_kind == "red" ? "ONE-SHOT CHECK FAILED — this approach is permanently closed." : "RETRYABLE CHECK FAILED — you may spend another tick to try again."
		log_line(g, failure_line)
		if clue.essential &&
		   g.ap <= 0 &&
		   !overtime_active(g) &&
		   !proof_framework_attainable(
				   g,
				   payload.solution.culprit_id,
			   ) {if !begin_proof_overtime(g) do begin_overtime(g, clue_index)}
	}
	if g.pending_dialogue_approach >
	   0 {approach := g.pending_dialogue_approach - 1; if result.success {complete_dialogue_approach(g, approach); _ = dialogue_start_dialogue_approach_scene(g, approach)} else do fail_dialogue_approach(g, approach); g.pending_dialogue_approach = 0}
	return result
}

dialogue_pointer_focus_id :: proc(g: ^Game) -> ui.Gui_Id {
	if g.screen != .Dialogue || g.active_device != .Keyboard_Mouse || g.dialogue_entity < 0 || g.dialogue_entity >= len(WORLD_ENTITIES) do return ui.GUI_ID_NONE
	point := g.input.mouse_pos
	if g.check_from_dialogue {
		if !g.check_done {if contains(dialogue_check_cancel_rect(), point) do return button_id(dialogue_check_cancel_rect()); roll := Rect{650, 590, 490, 42}; if contains(roll, point) do return button_id(roll)} else if g.animation_time - g.check_roll_started >= CHECK_REVEAL_DURATION {next := Rect{650, 590, 490, 42}; if contains(next, point) do return button_id(next)}
		return ui.GUI_ID_NONE
	}
	entity := WORLD_ENTITIES[g.dialogue_entity]
	if game_entity_has_tag(
		g,
		entity.source_id,
		"shutter_mechanism",
	) {approach := Rect{650, 420, 490, 58}; if contains(approach, point) do return button_id(approach); leave := dialogue_object_leave_rect(); if contains(leave, point) do return button_id(leave); return ui.GUI_ID_NONE}
	if game_entity_has_tag(
		g,
		entity.source_id,
		"reflection_dialogue",
	) {if contains(reflective_interaction_rect(), point) do return button_id(reflective_interaction_rect()); if contains(dialogue_object_leave_rect(), point) do return button_id(dialogue_object_leave_rect()); return ui.GUI_ID_NONE}
	if entity.kind == "person" {
		clue := clue_for_source(
			g,
			entity.source_id,
		); view_bottom := dialogue_response_view_bottom(g, entity.source_id, clue); visible := dialogue_response_visible_count(g, entity.source_id, clue); for slot in 0 ..< visible {choice := dialogue_response_rect(g, entity.source_id, clue, slot); if choice.y < view_bottom && choice.y + choice.h > dialogue_choices_start_y(g, entity.source_id) && contains(choice, point) do return button_id(choice)}
		end := dialogue_end_rect_for(g); if contains(end, point) do return button_id(end)
		return ui.GUI_ID_NONE
	}
	clue := clue_for_source(
		g,
		entity.source_id,
	); approach := dialogue_object_check_rect(g, clue); if game_entity_has_tag(g, entity.source_id, "dining_walkthrough") && clue >= 0 && mystery_game_clue_discovered(g, clue) && contains(dining_walkthrough_rect(), point) do return button_id(dining_walkthrough_rect()); if clue >= 0 && !mystery_game_clue_discovered(g, clue) && clue_available(g, clue) && contains(approach, point) do return button_id(approach)
	leave := dialogue_object_leave_rect(); if contains(leave, point) do return button_id(leave)
	return ui.GUI_ID_NONE
}
dialogue_overlay_return_focus :: proc(g: ^Game) -> ui.Gui_Id {pointer_focus :=
		dialogue_pointer_focus_id(g)
	return pointer_focus != ui.GUI_ID_NONE ? pointer_focus : g.gui.focused}
open_notebook :: proc(g: ^Game) {tutorial_complete(g, .Notebook); g.notebook_return = g.screen
	g.notebook_return_focus = dialogue_overlay_return_focus(g)
	g.screen = .Notebook}
open_attributes :: proc(g: ^Game) {g.menu_detail_return = g.screen; g.menu_detail_return_focus =
		dialogue_overlay_return_focus(g)
	g.screen = .Attributes}
return_from_menu_overlay :: proc(g: ^Game, screen: Screen, focus: ui.Gui_Id) {
	g.screen = screen
	g.menu_overlay_focus_pending = true
	g.menu_overlay_pending_screen = screen
	g.menu_overlay_pending_focus = focus
	// The overlay's gui_end_frame rejects controls which were not registered on
	// that overlay. Restore on the returned screen's next frame instead.
	g.focus_screen_initialized = false
}
dialogue_focus_id_valid :: proc(g: ^Game, focus: ui.Gui_Id) -> bool {
	if g.story_presentation.active {if !dialogue_ui_interactive(g) do return false; beat := story_presentation_node(g); if beat == nil do return false; if cinematic_can_leave(g) && focus == button_id(cinematic_leave_rect(beat)) do return true; if beat.kind == .Choice {pages := cinematic_choice_page_count(beat); if pages > 1 && (focus == button_id(cinematic_choice_prev_rect(g)) || focus == button_id(cinematic_choice_next_rect(g))) do return true; visible := cinematic_choice_visible_count(g, beat); for i in 0 ..< visible do if focus == button_id(cinematic_choice_rect(g, i)) do return true; return false}; if beat.kind == .Interaction do return focus == button_id(dialogue_interaction_action_rect()) || focus == button_id(dialogue_interaction_tool_rect()) || focus == button_id(dialogue_interaction_leave_rect()); return focus == button_id(cinematic_continue_rect(g))}
	if focus == ui.GUI_ID_NONE || g.dialogue_entity < 0 || g.dialogue_entity >= len(WORLD_ENTITIES) do return false
	if g.check_from_dialogue {
		if !g.check_done do return focus == button_id(Rect{650, 590, 490, 42}) || focus == button_id(dialogue_check_cancel_rect())
		settled := g.animation_time - g.check_roll_started >= CHECK_REVEAL_DURATION
		return settled && focus == button_id(Rect{650, 590, 490, 42})
	}
	entity := WORLD_ENTITIES[g.dialogue_entity]
	if game_entity_has_tag(g, entity.source_id, "shutter_mechanism") do return focus == button_id(Rect{650, 420, 490, 58}) || focus == button_id(dialogue_object_leave_rect())
	if game_entity_has_tag(g, entity.source_id, "reflection_dialogue") do return focus == button_id(reflective_interaction_rect()) || focus == button_id(dialogue_object_leave_rect())
	if entity.kind == "person" {
		clue := clue_for_source(
			g,
			entity.source_id,
		); view_bottom := dialogue_response_view_bottom(g, entity.source_id, clue); visible := dialogue_response_visible_count(g, entity.source_id, clue); for slot in 0 ..< visible {choice := dialogue_response_rect(g, entity.source_id, clue, slot); if choice.y < view_bottom && focus == button_id(choice) do return true}
		return focus == button_id(dialogue_end_rect_for(g))
	}
	clue := clue_for_source(
		g,
		entity.source_id,
	); if game_entity_has_tag(g, entity.source_id, "dining_walkthrough") && clue >= 0 && mystery_game_clue_discovered(g, clue) && focus == button_id(dining_walkthrough_rect()) do return true; if clue >= 0 && !mystery_game_clue_discovered(g, clue) && clue_available(g, clue) && focus == button_id(dialogue_object_check_rect(g, clue)) do return true
	return focus == button_id(dialogue_object_leave_rect())
}
apply_pending_menu_overlay_focus :: proc(g: ^Game) {
	if !g.menu_overlay_focus_pending do return
	g.menu_overlay_focus_pending = false
	if g.screen != g.menu_overlay_pending_screen do return
	focus := g.menu_overlay_pending_focus
	if g.screen == .Dialogue && !dialogue_focus_id_valid(g, focus) do focus = button_id(dialogue_default_rect(g))
	if focus != ui.GUI_ID_NONE {
		g.gui.focused = focus
		g.focus_screen = g.screen
		g.focus_screen_initialized = true
	} else {
		g.focus_screen_initialized = false
	}
}
menu_overlay_back_rect :: proc() -> Rect {return {20, 650, 320, 42}}
menu_overlay_back_label :: proc(return_screen: Screen) -> string {return(
		return_screen == .Dialogue ? "BACK TO CONVERSATION" : "BACK" \
	)}
menu_overlay_context_label :: proc(return_screen: Screen) -> string {return(
		return_screen == .Dialogue ? "CONVERSATION PAUSED  ·  BACK RESUMES" : "" \
	)}
theory_has_section :: proc(g: ^Game, act: int) -> bool {return(
		act >= 0 &&
		act < 3 &&
		mystery_game_theory_pillar(g, act) != "" \
	)}
known_proposition_for_clue :: proc(g: ^Game, id: string) -> string {payload :=
		mystery_game_payload(g)
	if payload != nil do for &clue, i in payload.clues do if clue.id == id && knowledge_piece_known(g, id) do return mystery_clue_proposition_text(g.story_project, &clue)
	return ""}
known_proposition_for_block :: proc(g: ^Game, block_id: string) -> string {payload :=
		mystery_game_payload(g)
	if payload != nil do for &clue in payload.clues do if knowledge_piece_known(g, clue.id) {for i in 0 ..< clue.block_count do if clue.blocks[i] == block_id do return mystery_clue_proposition_text(g.story_project, &clue)}
	return ""}
known_deduction_proposition :: proc(g: ^Game, id: string) -> string {payload :=
		mystery_game_payload(g)
	if payload != nil do for &deduction in payload.deductions do if deduction.id == id && knowledge_piece_known(g, id) do return mystery_story_proposition_text(g.story_project, deduction.proposition_id)
	return ""}
mystery_question_hypothesis_text :: proc(g: ^Game, question: ^Mystery_Question) -> string {
	if question == nil || question.hypothesis_id == "" do return ""
	if g.story_project != nil && story_proposition_index(g.story_project, question.hypothesis_id) >= 0 do return mystery_story_proposition_text(g.story_project, question.hypothesis_id)
	return question.hypothesis_id
}
reveal_act_lines :: proc(g: ^Game, act: int) -> (string, string) {
	if act == 3 {
		daniel := knowledge_piece_known(g, "ded_daniel_affair")
		elsie := knowledge_piece_known(g, "ded_elsie_theft")
		if daniel && elsie do return "Daniel's false alibi concealed his intended meeting with Miriam, not Edgar's murder.", "Elsie denied entering the study because she had stolen sixteen pounds—and her confession places Miriam at the study door."
		if daniel do return "Daniel's false alibi concealed his intended meeting with Miriam, not Edgar's murder.", "Elsie's account remains unexplained."
		if elsie do return "Elsie's denial concealed the sixteen pounds she stole, not Edgar's murder.", "Daniel's false alibi remains unexplained."
		return "You have not separated the household's other lies from the murder.", ""
	}
	if !theory_has_section(g, act) do return "You left this part of the night unexplained.", ""
	return known_deduction_proposition(g, mystery_game_theory_pillar(g, act)), ""
}
reveal_act_third_line :: proc(g: ^Game, act: int) -> string {if act == 3 && knowledge_piece_known(g, "ded_daniel_affair") && knowledge_piece_known(g, "ded_elsie_theft") do return "Their secrets explain the smoke around the dinner table. Neither explains the blood in Edgar's study."
	return ""}
reveal_act_supported :: proc(g: ^Game, act: int) -> bool {if act == 3 do return knowledge_piece_known(g, "ded_daniel_affair") && knowledge_piece_known(g, "ded_elsie_theft")
	first, _ := reveal_act_lines(g, act)
	return(
		theory_has_section(g, act) &&
		first != "" &&
		first != "The accusation outruns the evidence you brought." \
	)}
reveal_act_response :: proc(g: ^Game, act: int, supported, presented: bool) -> string {
	if mystery_game_accusation(g) == "" do return "No suspect stands accused; the room waits in silence."
	if act == 3 {
		if !supported do return "Daniel and Elsie both seize on the omissions. The room still has two alternative stories."
		if !presented do return "Two lesser crimes still crowd the accusation. Show the room why they are not Edgar's murder."
		return(
			"Daniel lowers his eyes. Elsie leaves the sixteen pounds on the table. Neither lie can shelter Miriam now." \
		)
	}
	if !supported do return "The room catches at the gap. This part of your account cannot hold."
	if !presented {
		switch act {
		case 0:
			return(
				"Miriam folds her hands. 'A missing sum is a grievance, detective. It is not a murder.'" \
			)
		case 1:
			return(
				"Miriam glances toward the study. 'An object in my husband's room was available to everyone in this house.'" \
			)
		case 2:
			return(
				"'You have made a sequence out of separate untidiness,' Miriam says. 'Sequence is not proof.'" \
			)
		}
	}
	switch act {
	case 0:
		return(
			"Miriam's gaze rests on the circled sums. 'They purchased the only thing Edgar never allowed: an unaccounted-for hour.' It is her first answer that does not correct the question." \
		)
	case 1:
		return(
			"Elsie studies the bronze. 'I polished that seam yesterday. Someone cleaned it again after.' Miriam does not look at her." \
		)
	case 2:
		return(
			"Cane, cloth, terrace, and body lock into order. Daniel stops watching Miriam and starts watching the door." \
		)
	}
	return "No answer dislodges what you have shown."
}
board_socket_count :: proc(section: int) -> int {counts := [5]int{1, 3, 3, 1, 3}; if section < 0 || section >= len(counts) do return 0
	return counts[section]}
board_socket_id :: proc(g: ^Game, section, socket: int) -> string {payload := mystery_game_payload(
		g,
	)
	if payload == nil do return ""
	solution := &payload.solution
	switch
	section {case 0:
		if socket == 0 do return solution.motive_id; case 1:
		ids := [3]string {
			solution.weapon_block,
			solution.murder_place_block,
			solution.death_time_block,
		}
		if socket >= 0 && socket < 3 do return ids[socket]; case 2:
		ids := [3]string {
			solution.body_movement_block,
			solution.staging_block,
			solution.cleaning_block,
		}
		if socket >= 0 && socket < 3 do return ids[socket]; case 3:
		if socket == 0 do return solution.alibi_block; case 4:
		for &contradiction in payload.contradictions do if contradiction.id == solution.decisive_contradiction_id {if socket == 0 do return contradiction.claim_id; if socket == 1 do return contradiction.fact_id; if socket == 2 {clue_index := mystery_clue_index(payload, contradiction.fact_id); if clue_index >= 0 && payload.clues[clue_index].prerequisite_count > 0 do return payload.clues[clue_index].prerequisites[0]}}}
	return ""}
board_socket_label :: proc(section, socket: int) -> string {labels := [5][3]string {
		{"MOTIVE / FACT", "", ""},
		{"OBJECT / WEAPON", "PLACE / SCENE", "TIME / WINDOW"},
		{"ACTION / MOVE", "FACT / STAGING", "ACTION / CLEAN"},
		{"CLAIM / ALIBI", "", ""},
		{"CLAIM / DENIAL", "BURNED FRAGMENT", "MEMO STUB"},
	}
	if section < 0 || section >= 5 || socket < 0 || socket >= 3 do return "SOCKET"
	return labels[section][socket]}
board_socket_available :: proc(g: ^Game, section, socket: int) -> bool {id := board_socket_id(
		g,
		section,
		socket,
	)
	if id == "" do return false
	if section == 0 || (section == 4 && socket > 0) do return knowledge_piece_known(g, id)
	return mystery_game_has_block(g, id)}
board_socket_source :: proc(g: ^Game, section, socket: int) -> string {id := board_socket_id(
		g,
		section,
		socket,
	)
	if section == 0 || (section == 4 && socket > 0) do return known_proposition_for_clue(g, id)
	return known_proposition_for_block(g, id)}
board_source_summary :: proc(value: string) -> string {if len(value) <= 75 do return value
	return fmt.tprintf("%s…", value[:72])}
board_section_available :: proc(g: ^Game, section: int) -> bool {count := board_socket_count(
		section,
	)
	if count == 0 do return false
	for socket in 0 ..< count do if !board_socket_available(g, section, socket) do return false
	return true}
board_section_filled :: proc(g: ^Game, section: int) -> bool {count := board_socket_count(section)
	if count == 0 do return false
	for socket in 0 ..< count do if !g.board_sockets[section][socket] do return false
	return true}
set_theory_section :: proc(g: ^Game, section: int, value: bool) {if section >= 0 && section < 3 && !value do mystery_game_set_theory_pillar(g, section, "")}
sync_board_from_theory :: proc(g: ^Game) {for section in 0 ..< 3 do if theory_has_section(g, section) {for socket in 0 ..< board_socket_count(section) do g.board_sockets[section][socket] = true}}
sync_theory_from_board :: proc(g: ^Game) {for section in 0 ..< 3 do set_theory_section(g, section, board_section_filled(g, section))}
clear_board_section :: proc(g: ^Game, section: int) {if section < 0 || section >= 5 do return; for socket in 0 ..< 3 do g.board_sockets[section][socket] = false
	set_theory_section(g, section, false)
	g.board_clear_confirm = false}
toggle_board_socket :: proc(g: ^Game, section, socket: int) -> bool {
	if section < 0 || section >= 5 || socket < 0 || socket >= board_socket_count(section) do return false
	g.board_inspect_socket = socket
	if !board_socket_available(
		g,
		section,
		socket,
	) {g.board_feedback = "No discovered evidence supports this part of the account yet."; play_sound(g, .Reject); return false}
	g.board_sockets[section][socket] = !g.board_sockets[section][socket]
	g.board_last_section =
		section; g.board_last_socket = socket; g.board_snap_started = g.animation_time
	g.board_feedback =
		g.board_sockets[section][socket] ? "Evidence placed. The reconstruction gains one supported detail." : "Evidence removed. That detail is open again."
	play_sound(g, g.board_sockets[section][socket] ? .Snap : .Pick_Up)
	g.board_clear_confirm = false; sync_theory_from_board(g); g.diagnostics = {}
	return true
}
board_source_text :: proc(g: ^Game, section: int) -> string {
	if !board_section_available(g, section) do return "Discover the evidence for this part of the account first."
	payload := mystery_game_payload(
		g,
	); if payload == nil do return "No supporting evidence is available."; solution := &payload.solution
	switch section {case 0:
		return known_proposition_for_clue(g, solution.motive_id); case 1:
		return known_proposition_for_block(g, solution.weapon_block); case 2:
		return known_proposition_for_block(g, solution.body_movement_block); case 3:
		return known_proposition_for_block(g, solution.alibi_block); case 4:
		for contradiction in payload.contradictions do if contradiction.id == solution.decisive_contradiction_id do return contradiction.explanation}
	return "No supporting evidence is available."
}
Readiness_State :: enum {
	Missing,
	Unsupported,
	Supported,
}
story_event_time_by_id :: proc(project: ^Story_Project, id: string) -> int {if project != nil do for event in project.events do if event.id == id do return clock_minutes(event.fictional_time)
	return -1}
mystery_timeline_order_possible :: proc(g: ^Game, order: [3]int) -> bool {payload :=
		mystery_game_payload(g)
	if payload == nil || payload.solution.cover_up_event_count < 3 do return false
	seen: [3]bool
	previous := -1
	for 	slot in order {if slot < 0 || slot >= 3 || seen[slot] do return false; seen[slot] = true; minutes :=
			story_event_time_by_id(g.story_project, payload.solution.cover_up_events[slot])
		if minutes < 0 || minutes < previous do return false
		previous = minutes}
	return true}
readiness_state :: proc(g: ^Game, section: int) -> Readiness_State {if !theory_has_section(g, section) do return .Missing
	if !board_section_available(g, section) do return .Unsupported
	if section == 2 && !mystery_timeline_order_possible(g, g.timeline_order) do return .Unsupported
	return .Supported}
readiness_text :: proc(state: Readiness_State) -> string {switch state {case .Missing:
		return "MISSING"; case .Unsupported:
		return "SELECTED / UNSUPPORTED"; case .Supported:
		return "SUPPORTED"}; return "MISSING"}
final_category_count :: proc(g: ^Game, category: string) -> int {count := 0; payload :=
		mystery_game_payload(g)
	if payload != nil do for deduction in payload.deductions do if deduction.category == category && knowledge_piece_known(g, deduction.id) do count += 1
	return count}
exclusion_progress :: proc(g: ^Game) -> (known, total: int) {payload := mystery_game_payload(g)
	if payload == nil do return
	total = payload.solution.exclusion_count
	for i in 0 ..< total {suspect := payload.solution.exclusions[i]; if suspect == "daniel" && knowledge_piece_known(g, "ded_daniel_excluded") {known += 1} else if suspect == "elsie" && knowledge_piece_known(g, "ded_elsie_theft") {known += 1}}
	return}
character_display_name :: proc(g: ^Game, id: string) -> string {if g.story_project != nil {index :=
			story_entity_index(g.story_project, id)
		if index >= 0 do return g.story_project.entities[index].display_name}
	return id}
suspect_id :: proc(g: ^Game, index: int) -> string {seen := 0; if g.story_project != nil do for character in g.story_project.entities do if character.kind == "character" && character.tag_count > 0 && character.tags[0] == "suspect" {if seen == index do return character.id; seen += 1}
	return ""}
suspect_name :: proc(g: ^Game, index: int) -> string {id := suspect_id(g, index); if id != "" do return character_display_name(g, id)
	return "UNKNOWN"}
return_from_board :: proc(g: ^Game) {if g.investigation_locked do route_locked_investigation(g)
	else do g.screen = .Investigate}
workbench_event_rect :: proc(index: int) -> Rect {return {25 + f32(index) * 128, 485, 118, 48}}
workbench_room_rect :: proc(index: int) -> Rect {return {25 + f32(index) * 290, 145, 265, 150}}
workbench_selected_figure_rect :: proc(g: ^Game) -> Rect {if g.workbench_event_count <= 0 do return {}
	event := g.workbench_events[g.workbench_selected]
	if event.actor == "someone" do return {}
	room_index := -1
	for room, i in WORKBENCH_ROOMS do if room == event.room && i > 0 do room_index = i - 1
	if room_index < 0 do return {}
	return{85 + f32(room_index) * 290, 185, 70, 92}}
drag_begin :: proc(g: ^Game, kind: Drag_Kind, index: int, box: Rect) {g.drag = {
			kind          = kind,
			index         = index,
			hover_index   = -1,
			start         = g.input.mouse_pos,
			offset        = {g.input.mouse_pos.x - box.x, g.input.mouse_pos.y - box.y},
			origin_screen = g.screen,
		}}
drag_cancel :: proc(g: ^Game) {g.drag = {
			index       = -1,
			hover_index = -1,
		}}
drag_update_threshold :: proc(g: ^Game) -> bool {if g.drag.kind == .None do return false
	if !g.input.mouse_down && !g.input.mouse_released {drag_cancel(g); return false}
	dx := g.input.mouse_pos.x - g.drag.start.x
	dy := g.input.mouse_pos.y - g.drag.start.y
	if !g.drag.active && dx * dx + dy * dy >= 36 {g.drag.active = true; play_sound(g, .Pick_Up)}
	return g.drag.active}
drag_cancel_if_screen_changed :: proc(g: ^Game) {if g.drag.kind != .None && g.screen != g.drag.origin_screen do drag_cancel(g)}
workbench_insertion_index :: proc(count: int, x: f32) -> int {if count <= 0 do return -1
	return clamp(int(math.floor(f64((x - 25 + 64) / 128))), 0, count - 1)}
update_workbench_drag :: proc(g: ^Game) {
	if g.active_device != .Keyboard_Mouse {drag_cancel(g); return}
	if g.drag.kind == .None && g.input.mouse_pressed {
		for i in 0 ..< g.workbench_event_count {box := workbench_event_rect(i); if contains(box, g.input.mouse_pos) {g.workbench_selected = i; drag_begin(g, .Event, i, box); return}}
		figure := workbench_selected_figure_rect(
			g,
		); if figure.w > 0 && contains(figure, g.input.mouse_pos) {drag_begin(g, .Miniature, g.workbench_selected, figure); return}
	}
	if g.drag.kind == .None do return
	if drag_update_threshold(g) && g.workbench_feedback != "Move along the rail; release over a numbered slot." && g.workbench_feedback != "Carry the miniature into a highlighted room." do g.workbench_feedback = g.drag.kind == .Event ? "Move along the rail; release over a numbered slot." : "Carry the miniature into a highlighted room."
	g.drag.hover_index = -1
	if g.drag.active {if g.drag.kind == .Event {if g.input.mouse_pos.y >= 467 && g.input.mouse_pos.y <= 551 do g.drag.hover_index = workbench_insertion_index(g.workbench_event_count, g.input.mouse_pos.x)} else {for i in 0 ..< 4 do if contains(workbench_room_rect(i), g.input.mouse_pos) do g.drag.hover_index = i}}
	if !g.input.mouse_released do return
	if g.drag.active &&
	   g.drag.hover_index >=
		   0 {if g.drag.kind == .Event {if !workbench_move_event(g, g.drag.index, g.drag.hover_index) {g.workbench_feedback = "The event settles back into the same timeline slot."; play_sound(g, .Pick_Up)}} else {rooms := [4]string{"dining_room", "hall", "study", "garden"}; event := &g.workbench_events[g.drag.index]; if event.room != rooms[g.drag.hover_index] {workbench_remember(g); event.room = rooms[g.drag.hover_index]; g.workbench_test_current = false; sync_theory_from_workbench(g); g.workbench_feedback = "Room changed. Test the sequence again to confirm it."; play_sound(g, .Snap)} else {g.workbench_feedback = "The miniature returns to its original room."; play_sound(g, .Pick_Up)}}} else if g.drag.active {g.workbench_feedback = "Release the piece over a highlighted room or timeline slot."; play_sound(g, .Reject)}
	drag_cancel(g)
}
shutter_clue_index :: proc(g: ^Game) -> int {
	payload := mystery_game_payload(
		g,
	); if payload != nil do for clue, i in payload.clues do if game_entity_has_tag(g, clue.source_id, "shutter_mechanism") do return i
	return -1
}

update_shutter_motion :: proc(g: ^Game, dt: f32) {
	difference := g.shutter_target - g.shutter_position
	if math.abs(difference) <
	   .002 {g.shutter_position = g.shutter_target; g.shutter_demonstrating = false; return}
	// Slow start and stop, with a firm minimum travel speed, gives the mechanism weight.
	speed := clamp(
		math.abs(difference) * 3.6,
		.34,
		1.5,
	); g.shutter_position += clamp(difference, -speed * dt, speed * dt)
}

toggle_shutter_crank :: proc(g: ^Game) {
	opening := g.shutter_target < .5
	g.shutter_target = opening ? 1 : 0; g.shutter_open = opening; g.shutter_operated = true
	g.shutter_feedback =
		opening ? "The resistant crank turns as the heavy slats climb through the frame." : "The crank reverses and the heavy shutter descends across the window."
	play_sound(g, .Shutter); play_sound(g, opening ? .Door_Open : .Shutter_Close)
}

demonstrate_shutter_folly :: proc(g: ^Game) {
	already_demonstrated := g.shutter_sightline_failed
	if already_demonstrated && g.shutter_target == 0 && g.shutter_position > .002 {
		g.shutter_feedback = "The shutter is still falling. Let the demonstration finish."
		return
	}
	g.shutter_view = 0; g.shutter_time = 2; g.shutter_open = false; g.shutter_operated = true
	// Start open so the automatic fall itself makes the failed sightline visible.
	g.shutter_position = 1; g.shutter_target = 0; g.shutter_sightline_failed = true; g.shutter_demonstrating = true
	learn_observation(g, 4, false); learn_observation(g, 5, false); learn_observation(g, 6, false)
	play_sound(g, .Shutter); play_sound(g, .Shutter_Close); play_sound(g, .Decisive_Clue)
	g.shutter_feedback =
		already_demonstrated ? "The shutter repeats its automatic fall, sealing the study window from the dining room." : "The shutter falls across the study window. From the dining room, the closed slats hide the glass completely."
}

lift_study_rug :: proc(g: ^Game) {
	if g.study_rug_lifted {context_feedback(g, "BLOOD AND WATCH-GLASS EXPOSED", .Complete, "study_rug"); return}
	g.study_rug_lifted = true; learn_observation(g, 0)
	message := "The rug peels back with a wet drag. Beside the diluted blood, a wrist-width scuff in the varnish holds tiny watch-glass fragments."
	log_line(
		g,
		message,
	); context_feedback(g, "BLOOD AND WATCH-GLASS EXPOSED", .Complete, "study_rug"); play_sound(g, .Pick_Up)
}
