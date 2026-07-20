package main

import ui "zelda_engine:ui"

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
