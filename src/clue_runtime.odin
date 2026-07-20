package main

import "core:fmt"

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
