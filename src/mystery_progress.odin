package main

import "core:fmt"
import "core:strings"
import ui "zelda_engine:ui"

learn_observation :: proc(g: ^Game, index: int, play_cue := true) {if index < 0 || index >= len(OBSERVATION_TEXT) || mystery_game_observation_known(g, index) do return
	if !mystery_game_mark_observation(g, index) do return
	log_line(g, fmt.tprintf("Observed: %s", OBSERVATION_TEXT[index]))
	if play_cue do play_sound(g, .Evidence)}

cycle_string :: proc(current: string, values: []string, delta: int) -> string {index := 0; for value, i in values do if value == current do index = i
	index = (index + delta + len(values)) % len(values)
	return values[index]}
workbench_action_label :: proc(action: string) -> string {switch action {case "open_shutter":
		return "OPEN SHUTTER"; case "close_shutter":
		return "CLOSE SHUTTER"; case "move_body":
		return "MOVE BODY"; case:
		return strings.to_upper(action)}; return strings.to_upper(action)}
workbench_action_short :: proc(action: string) -> string {switch action {case "open_shutter":
		return "OPEN"; case "close_shutter":
		return "CLOSE"; case "move_body":
		return "CARRY BODY"; case:
		return strings.to_upper(action)}; return strings.to_upper(action)}
workbench_noun_label :: proc(value: string) -> string {switch value {case "dining_room":
		return "DINING ROOM"; case "unknown place":
		return "UNKNOWN PLACE"; case "unknown object":
		return "UNKNOWN OBJECT"; case "cloth_oil":
		return "OILED CLOTH"; case "shutter_crank":
		return "SHUTTER CRANK"; case:
		return strings.to_upper(value)}; return strings.to_upper(value)}
workbench_default_event :: proc(index: int) -> Workbench_Event {return{
		time = 495 + index,
		actor = "someone",
		action = "move",
		prop = "unknown object",
		room = "unknown place",
		pinned_observation = -1,
	}}

event_chain_find_action :: proc(g: ^Game, action: string) -> int {for event, i in g.workbench_events[:g.workbench_event_count] do if event.action == action do return i
	return -1}
event_chain_append :: proc(g: ^Game, event: Workbench_Event) {if g.workbench_event_count >= len(g.workbench_events) do return
	g.workbench_events[g.workbench_event_count] = event
	g.workbench_event_count += 1}
mystery_game_has_block :: proc(g: ^Game, block_id: string) -> bool {payload :=
		mystery_game_payload(g)
	if payload == nil do return false
	for &clue in payload.clues do if knowledge_piece_known(g, clue.id) {for i in 0 ..< clue.block_count do if clue.blocks[i] == block_id do return true}
	return false}
mystery_knowledge_piece_type :: proc(g: ^Game, id: string) -> string {payload :=
		mystery_game_payload(g)
	if payload == nil do return ""
	if mystery_clue_index(payload, id) >= 0 do return "clue"
	if mystery_claim_index(payload, id) >= 0 do return "statement"
	if mystery_deduction_index(payload, id) >= 0 do return "deduction"
	return ""}

// Evidence proposes event fragments; it never silently repairs fields the
// player has already assembled. Later observations may only fill a genuinely
// unknown object or place on an existing fragment.
event_chain_from_evidence :: proc(g: ^Game) {
	if knowledge_piece_known(g, "ded_daniel_affair") && event_chain_find_action(g, "lie") < 0 do event_chain_append(g, {509, "daniel", "lie", "miriam", "dining_room", -1})
	if knowledge_piece_known(g, "ded_scene_staged") && event_chain_find_action(g, "stage") < 0 do event_chain_append(g, {509, "someone", "stage", "cane", "garden", -1})
	if knowledge_piece_known(g, "ded_death_time") && event_chain_find_action(g, "strike") < 0 do event_chain_append(g, {504, "someone", "strike", "unknown object", "unknown place", -1})
	strike := event_chain_find_action(
		g,
		"strike",
	); if strike >= 0 {if knowledge_piece_known(g, "ded_statuette_weapon") && g.workbench_events[strike].prop == "unknown object" do g.workbench_events[strike].prop = "statuette"; if knowledge_piece_known(g, "ded_study_murder") && g.workbench_events[strike].room == "unknown place" do g.workbench_events[strike].room = "study"}
	if knowledge_piece_known(g, "ded_body_moved") && event_chain_find_action(g, "move_body") < 0 do event_chain_append(g, {507, "someone", "move_body", "body", "garden", -1})
	if mystery_game_has_block(g, "action_clean") && event_chain_find_action(g, "clean") < 0 do event_chain_append(g, {505, "someone", "clean", "cloth_oil", "study", -1})
	if claim_known(g, "claim_miriam_summons_denial") && event_chain_find_action(g, "deny") < 0 do event_chain_append(g, {510, "miriam", "deny", "none", "dining_room", -1})
	g.workbench_selected = clamp(
		g.workbench_selected,
		0,
		max(0, g.workbench_event_count - 1),
	); sync_theory_from_workbench(g)
}

event_chain_disputed :: proc(g: ^Game, index: int) -> bool {
	if index < 0 || index >= g.workbench_event_count do return false; event := g.workbench_events[index]
	if event.action == "deny" && knowledge_piece_known(g, "clue_burned_fragment") do return true
	if event.action == "lie" && knowledge_piece_known(g, "clue_dinner_settings") do return true
	return false
}
event_chain_fragment_label :: proc(g: ^Game, index: int) -> string {if index < 0 || index >= g.workbench_event_count do return "NO EVENT"
	event := g.workbench_events[index]
	if event_chain_disputed(g, index) do return "EVIDENCE DISAGREES"
	if !workbench_event_complete(event) do return "MISSING FIELDS"
	return workbench_support_event(g, index) ? "SUPPORTED FRAGMENT" : "UNSUPPORTED VERSION"}
workbench_event_complete :: proc(event: Workbench_Event) -> bool {return(
		event.actor != "someone" &&
		event.prop != "unknown object" &&
		event.room != "unknown place" \
	)}
workbench_first_incomplete :: proc(g: ^Game) -> int {for event, i in g.workbench_events[:g.workbench_event_count] do if !workbench_event_complete(event) do return i
	return -1}
workbench_supported_count :: proc(g: ^Game) -> int {count := 0; for event, i in g.workbench_events[:g.workbench_event_count] do if workbench_event_complete(event) && workbench_support_event(g, i) do count += 1
	return count}
workbench_ready_to_present :: proc(g: ^Game) -> bool {return(
		g.workbench_event_count > 0 &&
		mystery_game_accusation(g) != "" &&
		g.workbench_test_current \
	)}
workbench_snapshot :: proc(g: ^Game) -> Workbench_Snapshot {return{
		events = g.workbench_events,
		count = g.workbench_event_count,
		selected = g.workbench_selected,
		accused = mystery_game_accusation(g),
	}}
workbench_restore :: proc(g: ^Game, s: Workbench_Snapshot) {g.workbench_events = s.events
	g.workbench_event_count = s.count
	g.workbench_selected = clamp(s.selected, 0, max(0, s.count - 1))
	mystery_game_set_accusation(g, s.accused)
	g.workbench_test_current = false
	sync_theory_from_workbench(g)}
workbench_remember :: proc(g: ^Game) {if g.workbench_undo_count == len(g.workbench_undo) {for i in 1 ..< len(g.workbench_undo) do g.workbench_undo[i - 1] = g.workbench_undo[i]
		g.workbench_undo_count -= 1}
	g.workbench_undo[g.workbench_undo_count] = workbench_snapshot(g)
	g.workbench_undo_count += 1
	g.workbench_redo_count = 0}
workbench_undo_edit :: proc(g: ^Game) {if g.workbench_undo_count <= 0 do return
	if g.workbench_redo_count <
	   len(g.workbench_redo) {g.workbench_redo[g.workbench_redo_count] = workbench_snapshot(g)
		g.workbench_redo_count += 1}
	g.workbench_undo_count -= 1
	workbench_restore(g, g.workbench_undo[g.workbench_undo_count])
	g.workbench_feedback = "The clockwork rewinds one edit."
	play_sound(g, .Pick_Up)}
workbench_redo_edit :: proc(g: ^Game) {if g.workbench_redo_count <= 0 do return
	if g.workbench_undo_count <
	   len(g.workbench_undo) {g.workbench_undo[g.workbench_undo_count] = workbench_snapshot(g)
		g.workbench_undo_count += 1}
	g.workbench_redo_count -= 1
	workbench_restore(g, g.workbench_redo[g.workbench_redo_count])
	g.workbench_feedback = "The clockwork reapplies the edit."
	play_sound(g, .Snap)}
sync_theory_from_workbench :: proc(g: ^Game) {
	for section in 0 ..< 5 do for socket in 0 ..< 3 do g.board_sockets[section][socket] = false
	if g.mystery_state !=
	   nil {clear(&g.mystery_state.reconstruction_order); for event in g.workbench_events[:g.workbench_event_count] do append(&g.mystery_state.reconstruction_order, fmt.tprintf("%d|%s|%s|%s|%s", event.time, event.actor, event.action, event.prop, event.room))}
	clean, move_body, stage := false, false, false
	for event in g.workbench_events[:g.workbench_event_count] {
		if event.action == "motive" && event.actor == mystery_game_accusation(g) && event.prop == "ledger" do g.board_sockets[0][0] = true
		if event.action == "strike" &&
		   event.actor ==
			   mystery_game_accusation(
				   g,
			   ) {if event.prop == "statuette" do g.board_sockets[1][0] = true; if event.room == "study" do g.board_sockets[1][1] = true; if event.time >= 503 && event.time <= 505 do g.board_sockets[1][2] = true}
		if event.action == "clean" &&
		   event.actor == mystery_game_accusation(g) {clean = true; g.board_sockets[2][2] = true}
		if event.action == "move_body" &&
		   event.actor ==
			   mystery_game_accusation(g) {move_body = true; g.board_sockets[2][0] = true}
		if event.action == "stage" &&
		   event.actor == mystery_game_accusation(g) &&
		   event.room == "garden" {stage = true; g.board_sockets[2][1] = true}
		if event.action == "lie" && event.actor == "daniel" do g.board_sockets[3][0] = true
		if event.action == "deny" &&
		   event.actor == "miriam" &&
		   event.room == "dining_room" &&
		   event.time >= 510 {g.board_sockets[4][0] = true; g.board_sockets[4][1] = true}
	}
	_ = clean; _ = move_body; _ = stage
}
configure_complete_workbench :: proc(g: ^Game) {
	g.workbench_events = {
		{495, "miriam", "motive", "ledger", "study", -1},
		{504, "miriam", "strike", "statuette", "study", -1},
		{505, "miriam", "clean", "cloth_oil", "study", -1},
		{507, "miriam", "move_body", "body", "garden", -1},
		{509, "miriam", "stage", "cane", "garden", -1},
		{509, "daniel", "lie", "miriam", "dining_room", -1},
		{510, "miriam", "deny", "none", "dining_room", -1},
		{},
		{},
	}; g.workbench_event_count = 7; g.workbench_selected = 6; mystery_game_set_accusation(g, "miriam"); g.workbench_test_current = false; sync_theory_from_workbench(g)
}
workbench_add_event_simple :: proc(g: ^Game) {if g.workbench_event_count >= len(g.workbench_events) do return
	workbench_remember(g)
	g.workbench_events[g.workbench_event_count] = workbench_default_event(g.workbench_event_count)
	g.workbench_selected = g.workbench_event_count
	g.workbench_event_count += 1
	g.workbench_test_current = false
	sync_theory_from_workbench(g)
	g.workbench_feedback = "Choose who acted, what they did, what they used, and where."
	play_sound(g, .Pick_Up)}
workbench_remove_event_simple :: proc(g: ^Game) {if g.workbench_event_count <= 0 do return
	workbench_remember(g)
	index := clamp(g.workbench_selected, 0, g.workbench_event_count - 1)
	for i in index ..< g.workbench_event_count - 1 do g.workbench_events[i] = g.workbench_events[i + 1]
	g.workbench_event_count -= 1
	g.workbench_selected = clamp(index, 0, max(0, g.workbench_event_count - 1))
	g.workbench_test_current = false
	sync_theory_from_workbench(g)
	g.workbench_feedback = "Beat removed. Test the revised sequence when you are ready."}
workbench_swap :: proc(g: ^Game, delta: int) {if g.workbench_event_count < 2 do return; from :=
		clamp(g.workbench_selected, 0, g.workbench_event_count - 1)
	to := clamp(from + delta, 0, g.workbench_event_count - 1)
	if from == to do return
	workbench_remember(g)
	g.workbench_events[from], g.workbench_events[to] =
		g.workbench_events[to], g.workbench_events[from]
	g.workbench_selected = to
	g.workbench_test_current = false
	sync_theory_from_workbench(g)
	play_sound(g, .Pick_Up)}
workbench_move_event :: proc(g: ^Game, from, to: int) -> bool {if from < 0 || from >= g.workbench_event_count || to < 0 || to >= g.workbench_event_count || from == to do return false
	workbench_remember(g)
	moving := g.workbench_events[from]
	if from < to {for i in from ..< to do g.workbench_events[i] = g.workbench_events[i + 1]}
	else {for i := from; i > to; i -= 1 do g.workbench_events[i] = g.workbench_events[i - 1]}
	g.workbench_events[to] = moving
	g.workbench_selected = to
	g.workbench_test_current = false
	sync_theory_from_workbench(g)
	g.workbench_feedback = "Sequence changed. Test it again to confirm the new order."
	play_sound(g, .Snap)
	return true}
workbench_cycle :: proc(g: ^Game, field, delta: int) {if g.workbench_event_count == 0 do workbench_add_event_simple(g)
	workbench_remember(g)
	event := &g.workbench_events[g.workbench_selected]
	switch
	field {case 0:
		event.time = clamp(event.time + delta, 495, 520); case 1:
		event.actor = cycle_string(event.actor, WORKBENCH_ACTORS[:], delta); case 2:
		event.action = cycle_string(event.action, WORKBENCH_ACTIONS[:], delta); case 3:
		event.prop = cycle_string(event.prop, WORKBENCH_PROPS[:], delta); case 4:
		event.room = cycle_string(event.room, WORKBENCH_ROOMS[:], delta)}
	g.workbench_test_current = false
	sync_theory_from_workbench(g)
	g.workbench_field = field
	g.workbench_feedback =
		workbench_event_complete(event^) ? "Beat changed. Test the sequence to see its consequences." : "Finish the highlighted beat before testing the sequence."}
workbench_controller_edit :: proc(g: ^Game) {
	if g.active_device != .Gamepad || g.workbench_event_count <= 0 do return
	if g.input.left do g.workbench_field = (g.workbench_field + 4) % 5
	if g.input.right do g.workbench_field = (g.workbench_field + 1) % 5
	if g.input.up do workbench_cycle(g, g.workbench_field, -1)
	if g.input.down do workbench_cycle(g, g.workbench_field, 1)
}
workbench_support_event :: proc(g: ^Game, index: int) -> bool {if index < 0 || index >= g.workbench_event_count do return false
	event := g.workbench_events[index]
	switch
	event.action {case "motive":
		return knowledge_piece_known(g, "ded_miriam_motive"); case "strike":
		return(
			knowledge_piece_known(g, "ded_statuette_weapon") &&
			knowledge_piece_known(g, "ded_study_murder") \
		); case "clean":
		return mystery_game_has_block(g, "action_clean"); case "move_body":
		return knowledge_piece_known(g, "ded_body_moved"); case "stage":
		return knowledge_piece_known(g, "ded_scene_staged"); case "lie":
		return knowledge_piece_known(g, "ded_daniel_affair"); case "deny":
		return knowledge_piece_known(
			g,
			"ded_miriam_denial_disproved",
		); case "open_shutter", "close_shutter":
		return false; case:
		return true}
	return false}
workbench_source_text :: proc(g: ^Game, index: int) -> string {
	if index < 0 || index >= g.workbench_event_count do return "No event selected."
	event :=
		g.workbench_events[index]; if !workbench_event_complete(event) do return "UNFINISHED BEAT: replace the red unknowns before the dollhouse can test it."
	supported := workbench_support_event(
		g,
		index,
	); prefix := supported ? "SUPPORTED BY: " : "NEEDS EVIDENCE: "; source: string
	switch event.action {case "motive":
		source = "the household ledger and missing accounts"; case "strike":
		source = "the statuette, wound match, and study scene"; case "clean":
		source = "lamp oil and blood trapped in the base seam"; case "open_shutter", "close_shutter":
		source = "the mechanism can be tested, but no evidence identifies its operator"; case "move_body":
		source = "the study blood and terrace-to-garden drag trace"; case "stage":
		source = "Edgar's cane beneath the wrong hand"; case "lie":
		source = "Daniel's disturbed dinner setting and admission"; case "deny":
		source = "Miriam's denial and the rejoined appointment note"; case:
		return "PROPOSED MOTION: physical simulation can test this without an evidence block."}
	return fmt.tprintf("%s%s", prefix, source)
}
run_workbench :: proc(g: ^Game) {if g.workbench_event_count ==
	   0 {g.workbench_feedback = "Add at least one beat before testing."; play_sound(g, .Reject)
		return}
	incomplete := workbench_first_incomplete(g)
	if incomplete >= 0 {g.workbench_selected = incomplete; g.workbench_feedback = fmt.tprintf(
			"Beat %d is unfinished. Replace every UNKNOWN before testing.",
			incomplete + 1,
		)
		play_sound(g, .Reject)
		return}
	sync_theory_from_workbench(g)
	for i in 0 ..< len(g.workbench_supported) do g.workbench_supported[i] = false
	for i in 0 ..< g.workbench_event_count do g.workbench_supported[i] = workbench_support_event(g, i)
	g.workbench_result = simulate_workbench(
		g.workbench_events[:g.workbench_event_count],
		g.workbench_supported[:],
	)
	g.workbench_test_current = true
	g.recreate_runs += 1
	g.recreate_started = g.animation_time
	if g.workbench_result.first_failed_event >= 0 do g.workbench_selected = g.workbench_result.first_failed_event
	play_sound(g, .Recreate)
	g.screen = .Recreate}
evaluate_workbench :: proc(g: ^Game) -> Outcome {
	if mystery_game_accusation(g) == "" do return .Unresolved
	payload := mystery_game_payload(g); if payload == nil do return .Unresolved
	if mystery_game_accusation(g) != payload.solution.culprit_id do return .Wrong_Accusation
	unsupported := false
	for _, i in g.workbench_events[:g.workbench_event_count] do if !workbench_support_event(g, i) do unsupported = true
	decisive := g.workbench_result.decisive_contradiction
	physical_or_proof := g.workbench_result.physically_possible || decisive
	diagnosis := Mystery_Diagnosis{}
	if g.mystery_state !=
	   nil {g.mystery_state.accusation_id = mystery_game_accusation(g); diagnosis = mystery_diagnose_player(g.story_project, g.mystery_state)}
	if physical_or_proof && !unsupported && decisive && diagnosis.evidence_supported && diagnosis.complete && diagnosis.exclusive do return .Airtight
	for pillar in 0 ..< 3 do if mystery_game_theory_pillar(g, pillar) != "" do return .Correct_But_Unproven
	return .Plausible_Incomplete
}

question_index_by_id :: proc(g: ^Game, id: string) -> int {payload := mystery_game_payload(g)
	if payload != nil {for question, i in payload.questions do if question.id == id do return i}
	return -1}
mystery_question_progress :: proc(
	g: ^Game,
	index: int,
	create := false,
) -> ^Mystery_Question_Progress {payload := mystery_game_payload(g); if payload == nil || g.mystery_state == nil || index < 0 || index >= len(payload.questions) do return nil
	id := payload.questions[index].id
	for &progress in g.mystery_state.question_progress do if progress.question_id == id do return &progress
	if !create do return nil
	append(
		&g.mystery_state.question_progress,
		Mystery_Question_Progress{question_id = id, state = int(Hypothesis_State.Locked)},
	)
	return &g.mystery_state.question_progress[len(g.mystery_state.question_progress) - 1]}
mystery_question_state :: proc(g: ^Game, index: int) -> Hypothesis_State {progress :=
		mystery_question_progress(g, index)
	return progress == nil ? .Locked : Hypothesis_State(progress.state)}
mystery_question_set_state :: proc(g: ^Game, index: int, state: Hypothesis_State) {progress :=
		mystery_question_progress(g, index, true)
	if progress != nil do progress.state = int(state)}
mystery_question_slot :: proc(g: ^Game, index, slot: int) -> string {progress :=
		mystery_question_progress(g, index)
	if progress == nil || slot < 0 || slot >= len(progress.slots) do return ""
	return progress.slots[slot]}
mystery_question_set_slot :: proc(g: ^Game, index, slot: int, value: string) {progress :=
		mystery_question_progress(g, index, true)
	if progress != nil && slot >= 0 && slot < len(progress.slots) do progress.slots[slot] = value}
mystery_question_slots :: proc(g: ^Game, index: int) -> [3]string {progress :=
		mystery_question_progress(g, index)
	if progress == nil do return {}
	return progress.slots}
demonstration_for_question :: proc(g: ^Game, question_index: int) -> int {payload :=
		mystery_game_payload(g)
	if payload == nil || question_index < 0 || question_index >= len(payload.questions) do return -1
	id := payload.questions[question_index].id
	for demonstration, i in payload.demonstrations do if demonstration.question_id == id do return i
	return -1}
deduction_index_by_id :: proc(g: ^Game, id: string) -> int {payload := mystery_game_payload(g)
	if payload != nil {for deduction, i in payload.deductions do if deduction.id == id do return i}
	return -1}
knowledge_piece_known :: proc(g: ^Game, id: string) -> bool {
	return g.mystery_state != nil && mystery_state_knows(g.mystery_state, id)
}
knowledge_piece_text :: proc(g: ^Game, id: string) -> string {
	payload := mystery_game_payload(g); if payload == nil do return "Unknown piece"
	for &clue in payload.clues do if clue.id == id do return mystery_clue_proposition_text(g.story_project, &clue)
	for claim in payload.claims do if claim.id == id {index := story_proposition_index(g.story_project, claim.proposition_id); return index >= 0 ? g.story_project.propositions[index].text : claim.proposition_id}
	for deduction in payload.deductions do if deduction.id == id {index := story_proposition_index(g.story_project, deduction.proposition_id); return index >= 0 ? g.story_project.propositions[index].text : deduction.proposition_id}
	return "Unknown piece"
}
knowledge_piece_kind :: proc(g: ^Game, id: string) -> string {
	payload := mystery_game_payload(
		g,
	); if payload != nil {clue_index := mystery_clue_index(payload, id); if clue_index >= 0 {source := payload.clues[clue_index].source_id; entity := story_entity_index(g.story_project, source); return entity >= 0 && g.story_project.entities[entity].kind == "character" ? "TESTIMONY" : "OBSERVATION"}; if mystery_claim_index(payload, id) >= 0 do return "STATEMENT"; if mystery_deduction_index(payload, id) >= 0 do return "DEDUCTION"}
	return "INFERENCE"
}
question_is_resolved :: proc(g: ^Game, index: int) -> bool {payload := mystery_game_payload(g)
	if payload == nil || index < 0 || index >= len(payload.questions) do return false
	state := mystery_question_state(g, index)
	return state == .Substantiated || state == .Eliminated || state == .Explained}
question_unlocked :: proc(g: ^Game, index: int) -> bool {
	payload := mystery_game_payload(
		g,
	); if payload == nil || index < 0 || index >= len(payload.questions) do return false; q := payload.questions[index]
	for id in q.requires_clues[:q.require_clue_count] do if !knowledge_piece_known(g, id) do return false
	for id in q.requires_claims[:q.require_claim_count] do if !knowledge_piece_known(g, id) do return false
	for id in q.requires_deductions[:q.require_deduction_count] do if !knowledge_piece_known(g, id) do return false
	for id in q.dependencies[:q.dependency_count] {prior := question_index_by_id(g, id); if prior < 0 || !question_is_resolved(g, prior) do return false}
	return true
}
refresh_questions :: proc(g: ^Game) {payload := mystery_game_payload(g); if payload == nil do return
	first_open := -1
	opened := false
	for 	_, i in payload.questions {if mystery_question_state(g, i) == .Locked &&
		   question_unlocked(g, i) {mystery_question_set_state(g, i, .Unsubstantiated); log_line(
				g,
				fmt.tprintf("Question opened: %s", payload.questions[i].prompt),
			)
			opened = true}
		if first_open < 0 && question_unlocked(g, i) do first_open = i}
	if first_open >= 0 && (g.question_selected < 0 || g.question_selected >= len(payload.questions) || !question_unlocked(g, g.question_selected)) do g.question_selected = first_open
	if opened do _ = game_story_milestone(g, "investigation.question_opened")}
known_piece_count :: proc(g: ^Game) -> int {if g.mystery_state == nil do return 0; return(
		len(g.mystery_state.acquired_evidence) +
		len(g.mystery_state.established_claims) +
		len(g.mystery_state.earned_deductions) \
	)}
known_piece_id :: proc(g: ^Game, wanted: int) -> string {if wanted < 0 || g.mystery_state == nil do return ""
	cursor := wanted
	if cursor < len(g.mystery_state.acquired_evidence) do return g.mystery_state.acquired_evidence[cursor]
	cursor -= len(g.mystery_state.acquired_evidence)
	if cursor < len(g.mystery_state.established_claims) do return g.mystery_state.established_claims[cursor]
	cursor -= len(g.mystery_state.established_claims)
	if cursor < len(g.mystery_state.earned_deductions) do return g.mystery_state.earned_deductions[cursor]
	return ""}
question_slot_piece_type :: proc(g: ^Game) -> string {payload := mystery_game_payload(g)
	if payload == nil || g.question_selected < 0 || g.question_selected >= len(payload.questions) do return ""
	demo_index := demonstration_for_question(g, g.question_selected)
	if demo_index < 0 do return ""
	demo := payload.demonstrations[demo_index]
	return demo.slot_types[clamp(g.question_slot, 0, demo.slot_count - 1)]}
question_slot_piece_kind :: proc(g: ^Game) -> string {piece_type := question_slot_piece_type(g)
	return piece_type == "" ? "" : strings.to_upper(piece_type)}
question_slot_piece_count :: proc(g: ^Game) -> int {kind := question_slot_piece_kind(g); if kind == "" do return 0
	count := 0
	for i in 0 ..< known_piece_count(g) do if knowledge_piece_kind(g, known_piece_id(g, i)) == kind do count += 1
	return count}
knowledge_piece_topics_overlap :: proc(payload: ^Mystery_Project, a, b: string) -> int {ai, bi :=
		mystery_clue_index(payload, a), mystery_clue_index(payload, b)
	if ai < 0 || bi < 0 do return 0
	score := 0
	for left in payload.clues[ai].topics[:payload.clues[ai].topic_count] do for right in payload.clues[bi].topics[:payload.clues[bi].topic_count] do if left == right do score += 1
	return score}
demonstration_candidate_score :: proc(g: ^Game, demo: ^Mystery_Demonstration, id: string) -> int {
	payload := mystery_game_payload(g); if payload == nil do return 0; score := 0
	for accepted in demo.accepted[:demo.accepted_count] do if accepted == id do score += 1000
	anchor := demo.subject; if anchor == "" && demo.accepted_count > 0 do anchor = demo.accepted[0]
	score += knowledge_piece_topics_overlap(payload, anchor, id) * 40
	ai, bi :=
		mystery_clue_index(payload, anchor),
		mystery_clue_index(
			payload,
			id,
		); if ai >= 0 && bi >= 0 && payload.clues[ai].source_id == payload.clues[bi].source_id do score += 20
	for &other in payload.demonstrations {has_anchor, has_id := false, false; for piece in other.accepted[:other.accepted_count] {if piece == anchor do has_anchor = true; if piece == id do has_id = true}; if has_anchor && has_id do score += 10}
	return score
}
question_slot_piece_id :: proc(g: ^Game, wanted: int) -> string {
	if wanted < 0 do return ""; kind := question_slot_piece_kind(g); if kind == "" do return ""
	payload := mystery_game_payload(
		g,
	); demo_index := demonstration_for_question(g, g.question_selected); if payload == nil || demo_index < 0 do return ""; demo := &payload.demonstrations[demo_index]
	chosen: [MYSTERY_MAX_REFS]string; chosen_count := 0
	for rank in 0 ..= wanted {
		best := ""; best_score := -1
		for i in 0 ..< known_piece_count(
			g,
		) {id := known_piece_id(g, i); if knowledge_piece_kind(g, id) != kind do continue; already := false; for prior in chosen[:chosen_count] do if prior == id do already = true; if already do continue; score := demonstration_candidate_score(g, demo, id); if score > best_score {best = id; best_score = score}}
		if best == "" do return ""; chosen[chosen_count] = best; chosen_count += 1; if rank == wanted do return best
	}
	return ""
}
mystery_demonstration_route_piece :: proc(
	demo: ^Mystery_Demonstration,
	route, slot: int,
) -> string {if route < 0 || route >= demo.route_count || slot < 0 || slot >= demo.route_counts[route] do return ""
	index := demo.route_firsts[route] + slot
	if index < 0 || index >= demo.accepted_count do return ""
	return demo.accepted[index]}
mystery_demonstration_matches :: proc(
	demo: ^Mystery_Demonstration,
	placed: [3]string,
) -> bool {for 	route in 0 ..< demo.route_count {correct := true; for slot in 0 ..< demo.route_counts[route] do if placed[slot] != mystery_demonstration_route_piece(demo, route, slot) do correct = false
		if correct do return true}
	return false}
question_place_piece :: proc(g: ^Game, piece: string) {payload := mystery_game_payload(g)
	if payload == nil || g.question_selected < 0 || g.question_selected >= len(payload.questions) || piece == "" do return
	demo_index := demonstration_for_question(g, g.question_selected)
	if demo_index < 0 do return
	demo := &payload.demonstrations[demo_index]
	slot_count := demo.slot_count
	slot := clamp(g.question_slot, 0, slot_count - 1)
	needed := demo.slot_types[slot]
	if !knowledge_piece_known(g, piece) ||
	   strings.to_lower(knowledge_piece_kind(g, piece)) !=
		   needed {g.question_feedback = fmt.tprintf("This part of the test needs evidence recorded as %s.", strings.to_upper(needed))
		play_sound(g, .Reject)
		return}
	tutorial_complete(g, .Board_Place)
	mystery_question_set_slot(g, g.question_selected, slot, piece)
	g.question_slot = (slot + 1) % slot_count
	g.knowledge_cursor = 0
	g.question_feedback = "Evidence placed. Demonstrate the combination to test the claim."
	play_sound(g, .Snap)}
question_clear_slot :: proc(g: ^Game) {payload := mystery_game_payload(g); if payload == nil || g.question_selected < 0 || g.question_selected >= len(payload.questions) do return
	mystery_question_set_slot(g, g.question_selected, clamp(g.question_slot, 0, 2), "")
	g.question_feedback = "Evidence removed from this test."
	play_sound(g, .Pick_Up)}
question_slots_full :: proc(g: ^Game, question_index: int) -> bool {payload :=
		mystery_game_payload(g)
	demo_index := demonstration_for_question(g, question_index)
	if payload == nil || demo_index < 0 do return false
	for slot in 0 ..< payload.demonstrations[demo_index].slot_count do if mystery_question_slot(g, question_index, slot) == "" do return false
	return true}
sync_theory_from_questions :: proc(g: ^Game) {
	for pillar in 0 ..< 3 {id := mystery_game_theory_pillar(g, pillar); if id != "" && !deduction_supports(g, id, mystery_game_accusation(g), pillar) do mystery_game_set_theory_pillar(g, pillar, "")}
}
proof_pillar_name :: proc(pillar: int) -> string {switch pillar {case 0:
		return "motive"; case 1:
		return "means"; case 2:
		return "opportunity"}; return ""}
deduction_supports :: proc(g: ^Game, id, candidate: string, pillar: int) -> bool {payload :=
		mystery_game_payload(g)
	if payload == nil || g.mystery_state == nil do return false
	wanted := fmt.tprintf("%s:%s", candidate, proof_pillar_name(pillar))
	for deduction in payload.deductions do if deduction.id == id && mystery_string_set_has(g.mystery_state.earned_deductions[:], id) {for support_index in 0 ..< deduction.support_count do if deduction.supports[support_index] == wanted do return true}
	return false}
proof_pillar_piece_count :: proc(g: ^Game, candidate: string, pillar: int) -> int {payload :=
		mystery_game_payload(g)
	if payload == nil do return 0
	count := 0
	for deduction in payload.deductions do if knowledge_piece_known(g, deduction.id) && deduction_supports(g, deduction.id, candidate, pillar) do count += 1
	return count}
proof_pillar_piece :: proc(g: ^Game, candidate: string, pillar, wanted: int) -> string {payload :=
		mystery_game_payload(g)
	if payload == nil do return ""
	seen := 0
	for deduction in payload.deductions do if knowledge_piece_known(g, deduction.id) && deduction_supports(g, deduction.id, candidate, pillar) {if seen == wanted do return deduction.id; seen += 1}
	return ""}
demonstration_route_known :: proc(g: ^Game, demo: ^Mystery_Demonstration, route: int) -> bool {for slot in 0 ..< demo.route_counts[route] do if !knowledge_piece_known(g, mystery_demonstration_route_piece(demo, route, slot)) do return false
	return true}
proof_pillar_attainable :: proc(
	g: ^Game,
	candidate: string,
	pillar: int,
) -> bool {if proof_pillar_piece_count(g, candidate, pillar) > 0 do return true; payload :=
		mystery_game_payload(g)
	if payload == nil do return false
	wanted := fmt.tprintf("%s:%s", candidate, proof_pillar_name(pillar))
	for 	&demo in payload.demonstrations {supports := false; for 		result_index in 0 ..< demo.result_count {result := demo.result_deductions[result_index]; for deduction in payload.deductions do if deduction.id == result {for support_index in 0 ..< deduction.support_count do if deduction.supports[support_index] == wanted do supports = true}}
		if supports {for route in 0 ..< demo.route_count do if demonstration_route_known(g, &demo, route) do return true}}
	return false}
proof_framework_attainable :: proc(g: ^Game, candidate: string) -> bool {for pillar in 0 ..< 3 do if !proof_pillar_attainable(g, candidate, pillar) do return false
	return true}
cycle_proof_pillar :: proc(g: ^Game, pillar: int) {count := proof_pillar_piece_count(
		g,
		mystery_game_accusation(g),
		pillar,
	)
	if count == 0 {mystery_game_set_theory_pillar(g, pillar, ""); return}
	current := -1
	for i in 0 ..< count do if proof_pillar_piece(g, mystery_game_accusation(g), pillar, i) == mystery_game_theory_pillar(g, pillar) do current = i
	mystery_game_set_theory_pillar(
		g,
		pillar,
		proof_pillar_piece(g, mystery_game_accusation(g), pillar, (current + 1) % count),
	)
	play_sound(g, .Snap)}
question_required_complete :: proc(g: ^Game) -> bool {return true}
question_framework_complete :: proc(g: ^Game) -> bool {for pillar in 0 ..< 3 do if !deduction_supports(g, mystery_game_theory_pillar(g, pillar), mystery_game_accusation(g), pillar) do return false
	return true}
question_ready_to_present :: proc(g: ^Game) -> bool {return(
		mystery_game_accusation(g) != "" &&
		question_framework_complete(g) \
	)}
visible_question_index :: proc(g: ^Game, slot: int) -> int {payload := mystery_game_payload(g)
	if payload == nil do return -1
	seen := 0
	for _, i in payload.questions do if question_unlocked(g, i) && !question_is_resolved(g, i) {if seen == slot do return i; seen += 1; if seen == 3 do break}
	for _, i in payload.questions do if question_unlocked(g, i) && question_is_resolved(g, i) {if seen == slot do return i; seen += 1; if seen == 5 do break}
	return -1}
active_question_index :: proc(g: ^Game, slot: int) -> int {payload := mystery_game_payload(g)
	if payload == nil do return -1
	seen := 0
	for _, i in payload.questions do if question_unlocked(g, i) && !question_is_resolved(g, i) {if seen == slot do return i; seen += 1}
	return -1}
resolved_question_count :: proc(g: ^Game) -> int {payload := mystery_game_payload(g); if payload == nil do return 0
	count := 0
	for _, i in payload.questions do if question_is_resolved(g, i) do count += 1
	return count}
begin_question_demonstration :: proc(g: ^Game) {
	payload := mystery_game_payload(
		g,
	); demo_index := demonstration_for_question(g, g.question_selected); if payload == nil || demo_index < 0 do return; demo := &payload.demonstrations[demo_index]
	if demo.presentation == "" ||
	   demo.presentation == "slots" {run_question_demonstration(g); return}
	if !question_slots_full(
		g,
		g.question_selected,
	) {g.question_feedback = "Choose evidence for every part of the test."; play_sound(g, .Reject); return}
	g.active_demonstration =
		demo_index; g.interaction_step = 0; g.interaction_active = true; g.interaction_mismatch = false; g.question_feedback = ""; g.screen = .Recreate; play_sound(g, .Pick_Up)
}
advance_question_interaction :: proc(g: ^Game) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || g.active_demonstration < 0 || g.active_demonstration >= len(payload.demonstrations) do return; demo := &payload.demonstrations[g.active_demonstration]
	steps := max(
		1,
		demo.gesture_step_count,
	); if g.interaction_step + 1 < steps {g.interaction_step += 1; play_sound(g, .Snap); return}
	placed := mystery_question_slots(
		g,
		g.question_selected,
	); if !mystery_demonstration_matches(demo, placed) {g.interaction_active = false; g.interaction_mismatch = true; mystery_question_set_state(g, g.question_selected, .Unsubstantiated); g.question_feedback = "The relationship does not hold. The selected evidence disagrees without identifying an alternative."; play_sound(g, .Reject); return}
	g.interaction_active = false; g.interaction_mismatch = false; run_question_demonstration(g)
}
run_question_demonstration :: proc(g: ^Game) {
	tutorial_complete(g, .Board_Test)
	payload := mystery_game_payload(
		g,
	); q := g.question_selected; demo_index := demonstration_for_question(g, q); if payload == nil || demo_index < 0 do return; demo := payload.demonstrations[demo_index]
	all_filled := true
	for slot in 0 ..< demo.slot_count do if mystery_question_slot(g, q, slot) == "" do all_filled = false
	if !all_filled {g.question_feedback = "Choose evidence for every part of the test."; play_sound(g, .Reject); return}
	placed := mystery_question_slots(
		g,
		q,
	); if !mystery_demonstration_matches(&demo, placed) {mystery_question_set_state(g, q, .Unsubstantiated); g.question_feedback = "These facts do not establish a conclusion together."; play_sound(g, .Reject); return}
	switch demo.resolution {case "substantiated":
		mystery_question_set_state(g, q, .Substantiated); case "eliminated":
		mystery_question_set_state(g, q, .Eliminated); case "explained":
		mystery_question_set_state(g, q, .Explained)}
	if g.mystery_state != nil do _ = mystery_complete_demonstration(g.story_project, g.mystery_state, payload.questions[q].id)
	for id in demo.result_deductions[:demo.result_count] {index := deduction_index_by_id(g, id); if index >= 0 {if g.mystery_state != nil do _ = mystery_string_set_add(&g.mystery_state.earned_deductions, id); log_line(g, fmt.tprintf("Deduction: %s", knowledge_piece_text(g, id))); deduction := payload.deductions[index]; for topic in deduction.unlock_topics[:deduction.unlock_topic_count] do unlock_topic(g, topic)}}
	g.active_demonstration =
		demo_index; g.question_feedback = demo.result; sync_theory_from_questions(g); refresh_questions(g); if question_ready_to_present(g) do _ = game_story_milestone(g, "investigation.explanation_ready"); g.recreate_runs += 1; g.recreate_started = g.animation_time; play_sound(g, .Recreate); g.screen = .Recreate
}
evaluate_questions :: proc(g: ^Game) -> Outcome {if g.story_project == nil || g.mystery_state == nil do return .Unresolved
	return mystery_evaluate_outcome(g.story_project, g.mystery_state)}
configure_complete_questions :: proc(g: ^Game) {payload := mystery_game_payload(g); if payload == nil do return
	mystery_game_mark_all_clues(g)
	for claim in payload.claims do _ = learn_claim(g, claim.id)
	refresh_questions(g)
	for 	_, i in payload.questions {demo_index := demonstration_for_question(g, i); if demo_index < 0 do continue
		demo := payload.demonstrations[demo_index]
		for slot in 0 ..< demo.slot_count do mystery_question_set_slot(g, i, slot, mystery_demonstration_route_piece(&demo, 0, slot))
		g.question_selected = i
		run_question_demonstration(g)}
	mystery_game_set_accusation(g, payload.solution.culprit_id)
	for pillar in 0 ..< 3 do cycle_proof_pillar(g, pillar)}
Vec2 :: ui.Vec2
Rect :: struct {
	x, y, w, h: f32,
}
Horizontal_Anchor :: enum {
	Left,
	Right,
}
Input_State :: struct {
	mouse_pos:                                                                                                                                                                                                                                                                                                                                                                                                            Vec2,
	mouse_wheel:                                                                                                                                                                                                                                                                                                                                                                                                          f32,
	dialogue_choice_slot:                                                                                                                                                                                                                                                                                                                                                                                                 int,
	mouse_down,
	mouse_pressed,
	mouse_released,
	mouse_middle_down,
	mouse_middle_pressed,
	mouse_middle_released,
	activate,
	vehicle_action,
	back,
	left,
	right,
	up,
	down,
	recreate,
	notebook,
	attributes,
	case_sense,
	case_sense_release,
	camera_toggle,
	wall_view_cycle,
	shoulder_left,
	shoulder_right,
	save_document,
	undo_document,
	redo_document,
	delete_selection,
	copy_selection,
	paste_selection,
	duplicate_selection: bool,
	text_input:                                                                                                                                                                                                                                                                                                                                                                                                           [32]u8,
	text_input_len:                                                                                                                                                                                                                                                                                                                                                                                                       int,
	clipboard_paste:                                                                                                                                                                                                                                                                                                                                                                                                      [256]u8,
	clipboard_paste_len:                                                                                                                                                                                                                                                                                                                                                                                                  int,
	key_shift,
	key_ctrl,
	key_super,
	key_enter,
	key_escape,
	key_backspace,
	key_delete,
	key_tab,
	key_home,
	key_end,
	key_left,
	key_right,
	key_a,
	key_x,
	key_v,
	key_c:                                                                                                                                                                                                                                                        bool,
}
