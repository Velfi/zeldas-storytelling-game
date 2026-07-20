package main

import "core:fmt"
import "core:strings"

begin_dialogue_approach_check :: proc(g: ^Game, node_index: int) {payload := mystery_game_payload(
		g,
	)
	node := mystery_dialogue_approach_at(payload, node_index)
	if node == nil do return
	clue_index := mystery_clue_index(payload, node.clue_id)
	if clue_index >= 0 {g.pending_dialogue_approach = node_index + 1; g.pending_clue = clue_index
		g.check_preview = check_target(payload.clues[clue_index].difficulty)
		g.check_done = false
		g.check_disposition_delta = 0
		g.check_from_dialogue = true
		dialogue_focus_default(g)}}
dialogue_approach_rect :: proc(g: ^Game, index: int, y: f32) -> Rect {
	node := mystery_dialogue_approach_at(
		mystery_game_payload(g),
		index,
	); if node == nil do return {650, y, 490, 38}; spoken := dialogue_semantic_text(node.prompt, "choice"); lines := wrapped_line_count(spoken, 426, .9)
	return {
		650,
		y,
		490,
		node.clue_id != "" ? max(f32(58), 31 + f32(lines) * 19) : max(f32(40), 12 + f32(lines) * 19),
	}
}
dialogue_object_check_rect :: proc(g: ^Game, clue_index: int) -> Rect {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return {650, 420, 490, 58}
	lines := wrapped_line_count(strings.to_upper(payload.clues[clue_index].description), 426, .9)
	return {650, 420, 490, max(f32(58), 31 + f32(lines) * 19)}
}
dialogue_transcript_layout_height :: proc(g: ^Game, conversation_id: string) -> f32 {
	indices: [256]int; count := 0
	for entry, i in g.conversation_transcript[:g.conversation_transcript_count] do if entry.conversation_id == conversation_id && count < len(indices) {indices[count] = i; count += 1}
	if count == 0 do return 0
	max_scroll := max(
		0,
		count - 1,
	); scroll := clamp(g.dialogue_ledger_scroll, 0, max_scroll); end := count - scroll; start := end - 1
	latest := &g.conversation_transcript[indices[start]]; latest_entity := world_entity_index(latest.speaker); latest_portrait := latest.kind == "dialogue" && latest_entity >= 0 && WORLD_ENTITIES[latest_entity].kind == "person"
	latest_width :=
		latest_portrait ? f32(375) : f32(445); used := dialogue_ledger_line_height(dialogue_semantic_text(latest.text, latest.kind), latest_width)
	if latest_portrait do used = max(used, 100)
	for start >
	    0 {candidate := dialogue_ledger_line_height(dialogue_semantic_text(g.conversation_transcript[indices[start - 1]].text, g.conversation_transcript[indices[start - 1]].kind), 445); if used + candidate > 360 do break; start -= 1; used += candidate}
	return used
}
dialogue_legacy_entry_layout_height :: proc(g: ^Game, node_index: int) -> f32 {
	node := mystery_dialogue_approach_at(
		mystery_game_payload(g),
		node_index,
	); if node == nil do return 0
	height := dialogue_ledger_line_height(node.prompt, 445)
	if node.clue_id != "" do height += dialogue_ledger_line_height("retryable · 1 tick", 445)
	return height
}
dialogue_legacy_layout_height :: proc(g: ^Game, source_id: string) -> f32 {
	payload := mystery_game_payload(g); if payload == nil do return 0
	indices: [32]int; count := 0; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == source_id && mystery_game_dialogue_completed(g, i) && count < len(indices) {indices[count] = i; count += 1}}
	if count == 0 do return 0
	clue_index := clue_for_source(
		g,
		source_id,
	); case_note := dialogue_case_note_active(g, clue_index); if case_note && g.dialogue_ledger_scroll == 0 do return 0; ledger_scroll := case_note ? g.dialogue_ledger_scroll - 1 : g.dialogue_ledger_scroll; end := clamp(count - ledger_scroll, 1, count); start := end - 1; used := dialogue_legacy_entry_layout_height(g, indices[start])
	for start > 0 &&
	    end - start <
		    3 {candidate := dialogue_legacy_entry_layout_height(g, indices[start - 1]); if used + candidate > 379 do break; start -= 1; used += candidate}
	for end < count &&
	    end - start <
		    3 {candidate := dialogue_legacy_entry_layout_height(g, indices[end]); if used + candidate > 379 do break; used += candidate; end += 1}
	return used
}
dialogue_choices_start_y :: proc(g: ^Game, source_id: string) -> f32 {
	used := dialogue_transcript_layout_height(
		g,
		source_id,
	); if used <= 0 do used = dialogue_legacy_layout_height(g, source_id)
	if used <=
	   0 {clue_index := clue_for_source(g, source_id); return max(f32(198), DIALOGUE_RESPONSE_VIEW_BOTTOM - dialogue_response_content_height(g, source_id, clue_index))}
	return dialogue_conversation_top_y(g, source_id) + used + 31
}
DIALOGUE_RESPONSE_VIEW_BOTTOM :: f32(646)
DIALOGUE_CONVERSATION_TOP :: f32(48)
DIALOGUE_RESPONSES_PER_PAGE :: 3 // Cinematic choice beats still use their authored paging layout.
dialogue_available_approach_count :: proc(g: ^Game, source_id: string) -> int {count := 0
	payload := mystery_game_payload(g)
	for i in 0 ..< mystery_dialogue_approach_count(
		payload,
	) {node := mystery_dialogue_approach_at(payload, i)
		if node.character_id == source_id && dialogue_approach_available(g, i) do count += 1}
	return count}
dialogue_response_count :: proc(g: ^Game, source_id: string, clue_index: int) -> int {return(
		dialogue_available_approach_count(g, source_id) +
		(dialogue_can_present_evidence(g, clue_index) ? 1 : 0) \
	)}
dialogue_response_page_clamp :: proc(
	g: ^Game,
	source_id: string,
	clue_index: int,
) {g.dialogue_choice_page = clamp(
		g.dialogue_choice_page,
		0,
		max(0, dialogue_response_count(g, source_id, clue_index) - 1),
	)}
dialogue_response_visible_count :: proc(
	g: ^Game,
	source_id: string,
	clue_index: int,
) -> int {dialogue_response_page_clamp(g, source_id, clue_index); return max(
		0,
		dialogue_response_count(g, source_id, clue_index) - g.dialogue_choice_page,
	)}
dialogue_response_global_slot :: proc(g: ^Game, local_slot: int) -> int {return(
		g.dialogue_choice_page +
		local_slot \
	)}
dialogue_response_approach :: proc(
	g: ^Game,
	source_id: string,
	clue_index, local_slot: int,
) -> int {global := dialogue_response_global_slot(g, local_slot); if global >= dialogue_available_approach_count(g, source_id) do return -1
	return visible_dialogue_approach(g, source_id, global)}
dialogue_response_is_evidence :: proc(
	g: ^Game,
	source_id: string,
	clue_index, local_slot: int,
) -> bool {return(
		dialogue_can_present_evidence(g, clue_index) &&
		dialogue_response_global_slot(g, local_slot) ==
			dialogue_available_approach_count(g, source_id) \
	)}
dialogue_response_rect :: proc(
	g: ^Game,
	source_id: string,
	clue_index, local_slot: int,
) -> Rect {y := dialogue_choices_start_y(g, source_id); for 	slot in 0 ..< local_slot {index := dialogue_response_approach(g, source_id, clue_index, slot); y +=
			index >= 0 ? dialogue_approach_rect(g, index, y).h + 4 : f32(44)}
	index := dialogue_response_approach(g, source_id, clue_index, local_slot)
	if index >= 0 do return dialogue_approach_rect(g, index, y)
	return{650, y, 490, 40}}
dialogue_response_content_height :: proc(g: ^Game, source_id: string, clue_index: int) -> f32 {
	y := f32(
		0,
	); count := dialogue_response_count(g, source_id, clue_index); approaches := dialogue_available_approach_count(g, source_id)
	for global in 0 ..< count {if global < approaches {index := visible_dialogue_approach(g, source_id, global); if index >= 0 do y += dialogue_approach_rect(g, index, 0).h + 4} else do y += 44}
	return max(0, y - 4)
}
dialogue_conversation_top_y :: proc(g: ^Game, source_id: string) -> f32 {
	// Keep short conversations against the action footer, like a DE-style
	// dialogue column. Long conversations grow upward to the top of the rail.
	used := dialogue_transcript_layout_height(
		g,
		source_id,
	); if used <= 0 do used = dialogue_legacy_layout_height(g, source_id)
	clue_index := clue_for_source(
		g,
		source_id,
	); responses := dialogue_response_content_height(g, source_id, clue_index)
	return max(DIALOGUE_CONVERSATION_TOP, DIALOGUE_RESPONSE_VIEW_BOTTOM - (used + 31 + responses))
}
dialogue_response_view_bottom :: proc(
	g: ^Game,
	source_id: string,
	clue_index: int,
) -> f32 {return min(
		DIALOGUE_RESPONSE_VIEW_BOTTOM,
		dialogue_choices_start_y(g, source_id) +
		dialogue_response_content_height(g, source_id, clue_index),
	)}
dialogue_object_result_height :: proc(g: ^Game, clue_index: int) -> f32 {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return 78
	lines := wrapped_line_count(
		mystery_clue_proposition_text(g.story_project, &payload.clues[clue_index]),
		454,
		.64,
	)
	return clamp(f32(62 + max(1, lines) * 14), 78, 176)
}
dialogue_has_available_approach :: proc(g: ^Game, source_id: string) -> bool {
	return dialogue_available_approach_count(g, source_id) > 0
}
dialogue_approaches_bottom :: proc(g: ^Game, source_id: string) -> f32 {
	clue := clue_for_source(
		g,
		source_id,
	); count := dialogue_response_visible_count(g, source_id, clue); if count <= 0 do return dialogue_choices_start_y(g, source_id); last := dialogue_response_rect(g, source_id, clue, count - 1); return last.y + last.h
}
dialogue_choice_marker :: proc(g: ^Game, slot: int) -> string {return(
		g.active_device == .Gamepad ? "◇" : fmt.tprintf("%d.", dialogue_response_global_slot(g, slot) + 1) \
	)}
dialogue_shortcut_selected :: proc(g: ^Game, slot: int) -> bool {return(
		g.active_device == .Keyboard_Mouse &&
		g.input.dialogue_choice_slot == dialogue_response_global_slot(g, slot) + 1 \
	)}
dialogue_approaches_heading :: proc(g: ^Game) -> string {
	return "CHOOSE YOUR APPROACH"
}
dialogue_authored_choice_limit :: proc(g: ^Game, clue_index: int) -> int {if g.dialogue_entity < 0 || g.dialogue_entity >= len(WORLD_ENTITIES) do return 0
	return dialogue_response_visible_count(
		g,
		WORLD_ENTITIES[g.dialogue_entity].source_id,
		clue_index,
	)}
dialogue_evidence_choice_rect :: proc(g: ^Game, source_id: string, clue_index: int) -> Rect {
	count := dialogue_response_visible_count(
		g,
		source_id,
		clue_index,
	); for slot in 0 ..< count do if dialogue_response_is_evidence(g, source_id, clue_index, slot) do return dialogue_response_rect(g, source_id, clue_index, slot); return {}
}
dialogue_end_rect_for :: proc(g: ^Game) -> Rect {
	if g.dialogue_entity >= 0 && g.dialogue_entity < len(WORLD_ENTITIES) {
		e := WORLD_ENTITIES[g.dialogue_entity]
		if e.kind == "person" {
			return {650, 654, 490, 28}
		}
	}
	return {650, 654, 490, 28}
}
dialogue_object_leave_rect :: proc() -> Rect {return {650, 654, 490, 28}}
dialogue_body_watch_clue :: proc(g: ^Game) -> int {entity := world_entity_index("edgar_watch")
	if entity < 0 || !entity_visible(g, &WORLD_ENTITIES[entity]) do return -1
	return clue_for_source(g, "edgar_watch")}
dialogue_body_watch_rect :: proc(g: ^Game) -> Rect {return{
		650,
		g.desk_key_found ? f32(420) : f32(482),
		490,
		58,
	}}
dialogue_check_cancel_rect :: proc() -> Rect {return {650, 548, 490, 30}}
DIALOGUE_LEDGER_RAIL_Y :: f32(46)
DIALOGUE_LEDGER_RAIL_H :: f32(398)
DIALOGUE_LEDGER_THUMB_H :: f32(54)
dialogue_ledger_scroll_hit_rect :: proc() -> Rect {return{
		1140,
		DIALOGUE_LEDGER_RAIL_Y,
		20,
		DIALOGUE_LEDGER_RAIL_H,
	}}
dialogue_ledger_thumb_y :: proc(scroll, max_scroll: int) -> f32 {
	if max_scroll <= 0 do return DIALOGUE_LEDGER_RAIL_Y
	return(
		DIALOGUE_LEDGER_RAIL_Y +
		(DIALOGUE_LEDGER_RAIL_H - DIALOGUE_LEDGER_THUMB_H) *
			(1 - f32(clamp(scroll, 0, max_scroll)) / f32(max_scroll)) \
	)
}
dialogue_history_position_label :: proc(scroll, max_scroll: int) -> string {
	if scroll <= 0 do return "↑ OLDER"
	if scroll >= max_scroll do return "↓ NEWER"
	return "↑ OLDER  ·  ↓ NEWER"
}
dialogue_history_input_hint :: proc(g: ^Game) -> string {
	return g.active_device == .Gamepad ? "SHOULDERS" : "PGUP / PGDN / WHEEL"
}
dialogue_reference_hint :: proc(g: ^Game) -> string {
	if g.active_device == .Gamepad {
		family := gamepad_family(g.gamepad_type)
		return fmt.tprintf(
			"%s  NOTEBOOK  ·  %s  ATTRIBUTES",
			gamepad_prompt_label(.Notebook, family),
			gamepad_prompt_label(.Board, family),
		)
	}
	return "N  NOTEBOOK  ·  C  ATTRIBUTES"
}
dialogue_exchange_is_fresh :: proc(g: ^Game, position, count: int) -> bool {
	elapsed := g.animation_time - g.dialogue_text_started
	return position == count - 1 && elapsed >= 0 && elapsed < 1.25
}
dialogue_exchange_fresh_visible :: proc(
	g: ^Game,
	position, count, clue_index: int,
) -> bool {return(
		!dialogue_case_note_active(g, clue_index) &&
		dialogue_exchange_is_fresh(g, position, count) \
	)}
dialogue_ledger_line_height :: proc(text: string, width: f32) -> f32 {
	return(
		26 +
		f32(wrapped_line_count(text, width - 12, .70)) * (f32(COURIER_CELL_HEIGHT) * .70 + 3) \
	)
}
dialogue_ledger_exchange_height :: proc(g: ^Game, node_index: int) -> f32 {
	node := mystery_dialogue_approach_at(
		mystery_game_payload(g),
		node_index,
	); if node == nil do return 0; response := mystery_game_dialogue_failed(g, node_index) ? dialogue_approach_failure_response(g, node_index) : node.response; height := dialogue_ledger_line_height(node.prompt, 445) + dialogue_ledger_line_height(response, 445)
	if node.clue_id != "" do height += dialogue_ledger_line_height("retryable · 1 tick", 445)
	return height + 9
}
dialogue_can_present_evidence :: proc(g: ^Game, clue_index: int) -> bool {
	payload := mystery_game_payload(
		g,
	); return payload != nil && clue_index >= 0 && clue_index < len(payload.clues) && !mystery_game_evidence_presented(g, clue_index) && relevant_evidence_for_clue(g, clue_index) >= 0
}
dialogue_case_note_active :: proc(g: ^Game, clue_index: int) -> bool {return(
		g.dialogue_node == 3 &&
		g.dialogue_response != "" &&
		clue_index >= 0 &&
		mystery_game_evidence_presented(g, clue_index) \
	)}
dialogue_failed_check_active :: proc(g: ^Game, clue_index: int) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) || mystery_game_clue_discovered(g, clue_index) do return false
	clue_id := payload.clues[clue_index].id
	for i in 0 ..< mystery_dialogue_approach_count(
		payload,
	) {node := mystery_dialogue_approach_at(payload, i); if node.clue_id == clue_id && mystery_game_dialogue_failed(g, i) do return true}
	return false
}
dialogue_evidence_label :: proc(g: ^Game, clue_index: int) -> string {
	payload := mystery_game_payload(
		g,
	); if payload != nil && clue_index >= 0 && clue_index < len(payload.clues) && mystery_game_evidence_presented(g, clue_index) do return "Evidence presented"
	source := relevant_evidence_for_clue(g, clue_index)
	if source <
	   0 {if payload != nil && dialogue_failed_check_active(g, clue_index) && payload.clues[clue_index].check_kind != "red" do return "Question another account or examine a related object"; return "Nothing applicable to present"}
	return fmt.tprintf("Present · %s", case_sense_source_name(g, source))
}
dialogue_evidence_feedback :: proc(g: ^Game, clue_index: int) -> string {
	payload := mystery_game_payload(g)
	source := relevant_evidence_for_clue(g, clue_index)
	if payload != nil &&
	   clue_index >= 0 &&
	   clue_index < len(payload.clues) &&
	   source >= 0 &&
	   source < len(payload.clues) {
		target_id := payload.clues[clue_index].id
		source_id := payload.clues[source].id
		if target_id == "clue_daniel" && source_id == "clue_dinner_settings" do return "You place the disturbed dinner settings beside Daniel's immaculate account. His thumb finds the crease of the note inside his coat. 'An empty chair proves absence, Lieutenant. It does not tell you what occupied it.'"
		if target_id == "clue_elsie" && source_id == "clue_ledger" do return "You set Edgar's red-circled ledger beside the locked cash drawer. Elsie reads every marked sum before looking up. 'Household money goes missing in more than one direction, Lieutenant.'"
		if target_id == "clue_elsie" && source_id == "clue_appointment_stub" do return "You show Elsie the words 'Miriam—study, 8:20—'. She reads the name once and the time twice. 'If you are asking whether I saw the study door, ask me that.'"
	}
	name := source >= 0 ? case_sense_source_name(g, source) : "Relevant evidence"
	return fmt.tprintf("%s presented. Related checks gain +1 modifier.", name)
}
dialogue_return_from_check :: proc(g: ^Game) {
	object_check :=
		g.dialogue_entity >= 0 &&
		g.dialogue_entity < len(WORLD_ENTITIES) &&
		WORLD_ENTITIES[g.dialogue_entity].kind != "person"
	cancelled_approach :=
		!g.check_done && g.pending_dialogue_approach > 0 ? g.pending_dialogue_approach - 1 : -1
	g.check_from_dialogue = false; g.check_done = false
	g.pending_dialogue_approach = 0
	body_tree :=
		object_check &&
		game_entity_has_tag(
			g,
			WORLD_ENTITIES[g.dialogue_entity].source_id,
			"body_examination_dialogue",
		)
	if g.investigation_locked &&
	   !overtime_active(
			   g,
		   ) {route_locked_investigation(g)} else if object_check && !body_tree do g.screen = .Investigate
	if g.screen == .Dialogue {
		if cancelled_approach >= 0 {
			source :=
				WORLD_ENTITIES[g.dialogue_entity].source_id; clue := clue_for_source(g, source); count := dialogue_available_approach_count(g, source); for absolute in 0 ..< count {index := visible_dialogue_approach(g, source, absolute); if index != cancelled_approach do continue; g.dialogue_choice_page = absolute; choice := dialogue_response_rect(g, source, clue, 0); g.gui.focused = button_id(choice); g.focus_screen = .Dialogue; g.focus_screen_initialized = true; return}
		}
		dialogue_focus_default(g)
	}
}
dialogue_check_cancel_label :: proc(g: ^Game) -> string {
	person :=
		g.dialogue_entity >= 0 &&
		g.dialogue_entity < len(WORLD_ENTITIES) &&
		WORLD_ENTITIES[g.dialogue_entity].kind == "person"
	body_tree :=
		g.dialogue_entity >= 0 &&
		g.dialogue_entity < len(WORLD_ENTITIES) &&
		game_entity_has_tag(
			g,
			WORLD_ENTITIES[g.dialogue_entity].source_id,
			"body_examination_dialogue",
		)
	return(
		person || body_tree ? "Cancel · Return to discoveries" : "Cancel · Return to investigation" \
	)
}
dialogue_accept_prompt :: proc(g: ^Game) -> string {
	if g.active_device == .Gamepad do return gamepad_prompt_label(.Accept, gamepad_family(g.gamepad_type))
	return keyboard_prompt_label(.Accept)
}
dialogue_check_roll_summary :: proc(result: Check_Result) -> string {
	return fmt.tprintf(
		"DICE %d + %d   ·   MODIFIER %+d   ·   TOTAL %d / TARGET %d",
		result.die_a,
		result.die_b,
		result.modifier,
		result.total,
		result.target,
	)
}
physical_check_failure_prefix :: proc(clue_id: string) -> string {
	switch clue_id {
	case "clue_ledger":
		return(
			"The figures suggest a grievance, but Edgar's red pencil could still be emphasis rather than accusation." \
		)
	case "clue_appointment_stub":
		return "The ragged stub preserves an appointment, but only half of its meaning."
	case "clue_cloth":
		return "The cloth carries oil and a darkened fold, but neither yet says what it polished."
	case "clue_clock":
		return "The broken watch gives you a time, but not yet a trustworthy reason it stopped."
	case "clue_cane":
		return "The garden pose looks composed; neatness alone cannot prove who composed it."
	case "clue_statuette":
		return "Fresh polish invites suspicion, but suspicion is not yet a wound match."
	case "clue_drag":
		return "The rain-softened thyme preserves a route, but not yet what traveled it."
	case "clue_dinner_settings":
		return "The table remembers departures, but not yet whose absence mattered."
	case "clue_burned_fragment":
		return "The fire spared words and an edge, but neither can answer alone."
	}
	return "The detail will not hold yet."
}
dialogue_check_failure_text :: proc(g: ^Game, check_kind: string) -> string {
	if g.pending_dialogue_approach > 0 && g.pending_dialogue_approach <= mystery_dialogue_approach_count(mystery_game_payload(g)) do return dialogue_approach_failure_response(g, g.pending_dialogue_approach - 1)
	if check_kind == "red" do return "This approach is closed, but the reaction remains evidence for another line of inquiry."
	payload := mystery_game_payload(
		g,
	); prefix := "The detail will not hold yet."; if payload != nil && g.pending_clue >= 0 && g.pending_clue < len(payload.clues) do prefix = physical_check_failure_prefix(payload.clues[g.pending_clue].id)
	return fmt.tprintf("%s You may spend another tick to try again.", prefix)
}
dialogue_check_threshold_label :: proc(target: int) -> string {return fmt.tprintf(
		"TOTAL %d+ NEEDED",
		target,
	)}
dialogue_check_tooltip_cost :: proc(cost, remaining: int) -> string {if cost <= 0 do return "NO COST  ·  OVERTIME"
	return fmt.tprintf(
		"COST %d %s  ·  %d %s REMAIN",
		cost,
		cost == 1 ? "TICK" : "TICKS",
		remaining,
		remaining == 1 ? "TICK" : "TICKS",
	)}
dialogue_check_prompt :: proc(g: ^Game) -> string {
	payload := mystery_game_payload(
		g,
	); if g.pending_dialogue_approach > 0 {index := g.pending_dialogue_approach - 1; node := mystery_dialogue_approach_at(payload, index); if node != nil do return node.prompt}
	if payload != nil && g.pending_clue >= 0 && g.pending_clue < len(payload.clues) do return strings.to_upper(payload.clues[g.pending_clue].description)
	return "INVESTIGATIVE CHECK"
}
dialogue_check_commit_label :: proc(g: ^Game, cost: int) -> string {payload :=
		mystery_game_payload(g)
	skill := "INVESTIGATIVE"
	if payload != nil && g.pending_clue >= 0 && g.pending_clue < len(payload.clues) do skill = strings.to_upper(payload.clues[g.pending_clue].skill)
	return fmt.tprintf(
		"[%s]  ROLL %s CHECK  ·  %s",
		dialogue_accept_prompt(g),
		skill,
		dialogue_tick_cost_label(cost),
	)}
dialogue_check_disposition_result :: proc(g: ^Game) -> string {if g.check_disposition_delta > 0 do return "DISPOSITION +1  ·  MORE RECEPTIVE"
	if g.check_disposition_delta < 0 do return "DISPOSITION -1  ·  MORE GUARDED"
	return ""}
dialogue_check_cost_summary :: proc(g: ^Game, clue_index: int) -> string {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return ""
	cost := clue_action_cost(g, clue_index)
	if cost <= 0 do return "NO TICK COST"
	return fmt.tprintf(
		"COST %d TICK%s   ·   %d REMAINING AFTER ROLL",
		cost,
		cost == 1 ? "" : "S",
		max(0, g.ap - cost),
	)
}
dialogue_tick_cost_label :: proc(cost: int) -> string {
	if cost <= 0 do return "NO COST"
	return fmt.tprintf("%d TICK%s", cost, cost == 1 ? "" : "S")
}
dialogue_scroll_ledger :: proc(g: ^Game, max_scroll: int) {
	// Directional input belongs to menu focus. Giving it to the ledger as well
	// made one D-pad press both change the selected response and move history.
	source_id := ""; if g.dialogue_entity >= 0 && g.dialogue_entity < len(WORLD_ENTITIES) do source_id = WORLD_ENTITIES[g.dialogue_entity].source_id
	history_pointer :=
		g.input.mouse_pos.y <
		dialogue_choices_start_y(
			g,
			source_id,
		); delta := g.input.shoulder_left ? 1 : g.input.shoulder_right ? -1 : history_pointer && g.input.mouse_wheel > 0 ? 1 : history_pointer && g.input.mouse_wheel < 0 ? -1 : 0
	g.dialogue_ledger_scroll = clamp(g.dialogue_ledger_scroll + delta, 0, max_scroll)
	if max_scroll > 0 &&
	   g.input.mouse_pressed &&
	   contains(dialogue_ledger_scroll_hit_rect(), g.input.mouse_pos) {
		track :=
			DIALOGUE_LEDGER_RAIL_H -
			DIALOGUE_LEDGER_THUMB_H; position := clamp((g.input.mouse_pos.y - DIALOGUE_LEDGER_RAIL_Y - DIALOGUE_LEDGER_THUMB_H * .5) / track, 0, 1)
		g.dialogue_ledger_scroll = clamp(int((1 - position) * f32(max_scroll) + .5), 0, max_scroll)
	}
}
dialogue_back :: proc(g: ^Game) {
	if g.story_presentation.active {beat := story_presentation_node(g); if beat != nil && beat.kind == .Interaction && beat.cancel != "" {dialogue_complete_current(g, beat.cancel)} else if cinematic_can_leave(g) do dialogue_end_scene(g); return}
	if g.end_confirm {g.end_confirm = false; dialogue_focus_default(g); return}
	if !g.check_from_dialogue {g.screen = .Investigate; return}
	if g.check_done && g.animation_time - g.check_roll_started < CHECK_REVEAL_DURATION do return
	dialogue_return_from_check(g)
}
dialogue_default_rect :: proc(g: ^Game) -> Rect {
	if g.story_presentation.active do return cinematic_default_rect(g)
	if g.check_from_dialogue do return {650, 590, 490, 42}
	if g.dialogue_entity < 0 || g.dialogue_entity >= len(WORLD_ENTITIES) do return {650, 610, 490, 42}
	e := WORLD_ENTITIES[g.dialogue_entity]
	if game_entity_has_tag(g, e.source_id, "shutter_mechanism") do return {650, 420, 490, 58}
	if game_entity_has_tag(
		g,
		e.source_id,
		"body_examination_dialogue",
	) {watch := dialogue_body_watch_clue(g); if watch >= 0 && !mystery_game_clue_discovered(g, watch) && clue_available(g, watch) do return dialogue_body_watch_rect(g); return dialogue_object_leave_rect()}
	if e.kind !=
	   "person" {if game_entity_has_tag(g, e.source_id, "reflection_dialogue") do return reflective_interaction_rect(); clue := clue_for_source(g, e.source_id); if game_entity_has_tag(g, e.source_id, "dining_walkthrough") && clue >= 0 && mystery_game_clue_discovered(g, clue) do return dining_walkthrough_rect(); if clue >= 0 && !mystery_game_clue_discovered(g, clue) && clue_available(g, clue) do return dialogue_object_check_rect(g, clue); return dialogue_object_leave_rect()}
	clue := clue_for_source(
		g,
		e.source_id,
	); if dialogue_response_visible_count(g, e.source_id, clue) > 0 do return dialogue_response_rect(g, e.source_id, clue, 0)
	return dialogue_end_rect_for(g)
}
dialogue_focus_default :: proc(g: ^Game) {
	if g.screen != .Dialogue do return
	g.gui.focused = button_id(
		dialogue_default_rect(g),
	); g.focus_screen = .Dialogue; g.focus_screen_initialized = true
}
update_dialogue :: proc(g: ^Game) {
	if graph_state.playtesting &&
	   !g.story_presentation.active {graph_debugger_update_editor_toggle(g); update_graph_debugger(g); return}
	if g.quest_completion_pending {if g.animation_time - g.quest_completion_started >= 1.5 {g.quest_completion_pending = false; g.investigation_locked = true; g.phase = .Reveal_Preparation; g.screen = .Reveal_Prep; g.end_confirm = false}; return}
	if g.story_presentation.active {
		if g.input.notebook {open_notebook(g); return}
		if g.input.attributes || g.input.recreate {open_attributes(g); return}
		_ = update_cinematic_dialogue(g); return
	}
	if g.check_from_dialogue {
		update_check_result_cue(g)
		settled := g.check_done && g.animation_time - g.check_roll_started >= CHECK_REVEAL_DURATION
		if !g.check_done {if button(g, dialogue_check_cancel_rect()) {dialogue_return_from_check(g); return}; if button(g, {650, 590, 490, 42}) {g.check_result = resolve_clue_check(g, g.pending_clue); g.check_roll_started = g.animation_time; g.check_result_cue_played = false; play_check_dice_sound(g); g.check_done = true}}
		if settled && button(g, {650, 590, 490, 42}) do dialogue_return_from_check(g)
		return
	}
	if g.input.notebook {open_notebook(g); return}
	if g.input.attributes || g.input.recreate {open_attributes(g); return}
	e := WORLD_ENTITIES[g.dialogue_entity]; clue := clue_for_source(g, e.source_id)
	if e.kind == "person" {
		character := character_index(g, e.source_id)
		payload := mystery_game_payload(
			g,
		); completed_count := 0; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == e.source_id && mystery_game_dialogue_completed(g, i) do completed_count += 1}; case_note := dialogue_case_note_active(g, clue); max_scroll := case_note ? completed_count : max(0, completed_count - 1); dialogue_scroll_ledger(g, max_scroll)
		dialogue_response_page_clamp(
			g,
			e.source_id,
			clue,
		); view_bottom := dialogue_response_view_bottom(g, e.source_id, clue); if g.input.mouse_pos.x >= 650 && g.input.mouse_pos.x <= 1140 && g.input.mouse_pos.y >= dialogue_choices_start_y(g, e.source_id) && g.input.mouse_pos.y < view_bottom && g.input.mouse_wheel != 0 {delta := g.input.mouse_wheel > 0 ? -1 : 1; g.dialogue_choice_page = clamp(g.dialogue_choice_page + delta, 0, max(0, dialogue_response_count(g, e.source_id, clue) - 1)); dialogue_focus_default(g)}
		visible := dialogue_response_visible_count(
			g,
			e.source_id,
			clue,
		); for slot in 0 ..< visible {choice := dialogue_response_rect(g, e.source_id, clue, slot); index := dialogue_response_approach(g, e.source_id, clue, slot); activated := button(g, choice) || dialogue_shortcut_selected(g, slot); if !activated do continue; if index >= 0 {node := mystery_dialogue_approach_at(payload, index); if node != nil && node.clue_id == "" {complete_dialogue_approach(g, index); _ = dialogue_start_dialogue_approach_scene(g, index)} else do begin_dialogue_approach_check(g, index)} else if dialogue_response_is_evidence(g, e.source_id, clue, slot) {feedback := dialogue_evidence_feedback(g, clue); if present_evidence(g, clue) {g.dialogue_node = 3; g.dialogue_response = feedback; g.dialogue_text_started = g.animation_time; g.dialogue_ledger_scroll = 0; g.dialogue_choice_page = 0; g.gui.focused = button_id(dialogue_default_rect(g))}}; break}
		if button(g, dialogue_end_rect_for(g)) do g.screen = .Investigate
	} else {
		if game_entity_has_tag(g, e.source_id, "reflection_dialogue") {
			if button(g, reflective_interaction_rect()) ||
			   dialogue_shortcut_selected(
				   g,
				   0,
			   ) {g.dialogue_response = pond_reflection_line(g); g.dialogue_text_started = g.animation_time; log_line(g, g.dialogue_response); dialogue_focus_default(g)}
			if button(g, dialogue_object_leave_rect()) do g.screen = .Investigate
			return
		}
		if game_entity_has_tag(g, e.source_id, "body_examination_dialogue") {
			watch := dialogue_body_watch_clue(g)
			payload := mystery_game_payload(
				g,
			); if payload != nil && watch >= 0 && !mystery_game_clue_discovered(g, watch) && clue_available(g, watch) && (button(g, dialogue_body_watch_rect(g)) || dialogue_shortcut_selected(g, 0)) {g.pending_clue = watch; g.pending_dialogue_approach = 0; authored := &payload.clues[watch]; g.check_preview = check_target(authored.difficulty); g.check_done = false; g.check_disposition_delta = 0; g.check_from_dialogue = true; dialogue_focus_default(g)}
			if button(g, dialogue_object_leave_rect()) do g.screen = .Investigate
			return
		}
		if game_entity_has_tag(g, e.source_id, "shutter_mechanism") {
			if button(g, {650, 420, 490, 58}) || dialogue_shortcut_selected(g, 0) {
				if g.shutter_demonstrating {g.dialogue_response = "The shutter is still falling. Let the demonstration finish."} else if !g.shutter_sightline_failed {demonstrate_shutter_folly(g); g.dialogue_response = "The shutter drops across the study window. From the dining room, the garden and study window disappear behind solid slats."} else {toggle_shutter_crank(g); g.dialogue_response = g.shutter_target >= .5 ? "The crank raises the shutter, reopening the garden sightline." : "The crank lowers the shutter. The garden sightline disappears again."}
				g.dialogue_text_started = g.animation_time; dialogue_focus_default(g)
			}
			if button(g, dialogue_object_leave_rect()) do g.screen = .Investigate
			return
		}
		if game_entity_has_tag(g, e.source_id, "dining_walkthrough") &&
		   clue >= 0 &&
		   mystery_game_clue_discovered(g, clue) &&
		   (button(g, dining_walkthrough_rect()) ||
				   dialogue_shortcut_selected(
					   g,
					   0,
				   )) {g.dialogue_response = dining_walkthrough_line(g); g.dialogue_text_started = g.animation_time; log_line(g, g.dialogue_response); dialogue_focus_default(g)}
		payload := mystery_game_payload(
			g,
		); if payload != nil && clue >= 0 && !mystery_game_clue_discovered(g, clue) && clue_available(g, clue) && (button(g, dialogue_object_check_rect(g, clue)) || dialogue_shortcut_selected(g, 0)) {g.pending_clue = clue; g.pending_dialogue_approach = 0; authored := &payload.clues[clue]; g.check_preview = check_target(authored.difficulty); g.check_done = false; g.check_disposition_delta = 0; g.check_from_dialogue = true; dialogue_focus_default(g)}
		if button(g, dialogue_object_leave_rect()) do g.screen = .Investigate
	}
}
