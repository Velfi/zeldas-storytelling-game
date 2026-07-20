package main

import "core:math"
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
