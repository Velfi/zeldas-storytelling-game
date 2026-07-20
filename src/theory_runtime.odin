package main

import "core:fmt"
import "core:math"

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
