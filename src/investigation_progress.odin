package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

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
