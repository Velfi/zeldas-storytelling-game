package main

import "core:fmt"
import "core:strings"

hypothesis_state_text :: proc(state: Hypothesis_State) -> string {switch state {case .Locked:
		return "LOCKED"; case .Unsubstantiated:
		return "OPEN / UNTESTED"; case .Supported:
		return "EVIDENCE INCOMPLETE"; case .Substantiated:
		return "ESTABLISHED"; case .Eliminated:
		return "DISPROVED"; case .Explained:
		return "EXPLAINED"}; return "LOCKED"}
hypothesis_state_color :: proc(state: Hypothesis_State) -> [4]u8 {switch
	state {case .Substantiated, .Explained:
		return {102, 205, 143, 255}; case .Eliminated:
		return {255, 144, 119, 255}; case .Supported:
		return {255, 211, 92, 255}; case .Unsubstantiated:
		return {205, 207, 210, 255}; case .Locked:
		return{90, 89, 84, 255}}
	return{90, 89, 84, 255}}
knowledge_type_color :: proc(kind: string) -> [4]u8 {switch kind {case "OBSERVATION":
		return {255, 211, 92, 255}; case "TESTIMONY":
		return {206, 154, 255, 255}; case "STATEMENT":
		return {155, 201, 255, 255}; case "DEDUCTION":
		return {102, 205, 143, 255}}; return {205, 207, 210, 255}}

vk_draw_workbench :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(r, "OPEN QUESTIONS", "Turn observations and statements into facts you can apply.")
	vk_button(
		r,
		{40, 70, 210, 38},
		"QUESTIONS",
		true,
	); vk_button(r, {265, 70, 250, 38}, "EVENT CHAIN", true)
	vk_text(r, 120, 105, "CHOOSE ONE QUESTION TO CHALLENGE", {255, 211, 92, 255}, .78)
	visible := 0
	payload := mystery_game_payload(
		g,
	); for slot in 0 ..< 3 {i := visible_question_index(g, slot); if payload != nil && i >= 0 {question := payload.questions[i]; state := mystery_question_state(g, i); color := hypothesis_state_color(state); y := 145 + f32(slot) * 135; vk_button(r, {120, y, 960, 112}, ""); vulkan_ui_outline(r, 120, y, 960, 112, color, 3); vk_text(r, 150, y + 17, fmt.tprintf("◇  %s", hypothesis_state_text(state)), color, .66); _ = vk_text_wrapped(r, 150, y + 52, 880, question.prompt, {248, 247, 242, 255}, 1.0, 2); visible += 1}}
	if visible ==
	   0 {vk_text(r, 385, 260, "NO OPEN QUESTIONS", {102, 205, 143, 255}, 1.0); vk_text(r, 385, 315, "You may apply the facts you have or keep investigating.", {248, 247, 242, 255}, .82)}
	resolved := resolved_question_count(
		g,
	); vk_text(r, 120, 565, fmt.tprintf("◆  %d RESOLVED QUESTION%s", resolved, resolved == 1 ? "" : "S"), {102, 205, 143, 255}, .72); if visible == 3 do vk_text(r, 765, 565, "MORE QUESTIONS APPEAR AS THESE RESOLVE", {205, 207, 210, 255}, .58)
	vk_button(
		r,
		{40, 640, 200, 48},
		"BACK",
	); vk_button(r, {400, 610, 400, 58}, "BUILD ACCUSATION", true)
}

event_chain_card_rect :: proc(index: int) -> Rect {return{
		45 + f32(index % 3) * 380,
		112 + f32(index / 3) * 100,
		350,
		82,
	}}
event_chain_field_rect :: proc(index: int) -> Rect {return {45 + f32(index) * 280, 470, 255, 58}}

vk_draw_event_chain :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(
		r,
		"EVENT CHAIN",
		"Evidence proposes fragments. Resolve disagreements, then put the night in order.",
	)
	vk_button(
		r,
		{40, 70, 210, 38},
		"QUESTIONS",
		true,
	); vk_button(r, {265, 70, 250, 38}, "EVENT CHAIN", true)
	if g.workbench_event_count ==
	   0 {vk_panel(r, 190, 185, 820, 245); vk_text(r, 350, 245, "NO EVENTS INFERRED YET", {205, 207, 210, 255}, 1.05); _ = vk_text_wrapped(r, 300, 300, 600, "Interview the household and examine the scene. Events will form here when evidence suggests that something happened.", {248, 247, 242, 255}, .78, 4); vk_button(r, {40, 640, 200, 48}, "BACK"); return}
	for i in 0 ..< g.workbench_event_count {event := g.workbench_events[i]; box := event_chain_card_rect(i); selected := i == g.workbench_selected; disputed := event_chain_disputed(g, i); complete := workbench_event_complete(event); color := disputed ? [4]u8{255, 144, 119, 255} : complete ? [4]u8{102, 205, 143, 255} : [4]u8{255, 211, 92, 255}; vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {37, 42, 49, 255}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, selected ? [4]u8{255, 211, 92, 255} : color, selected ? 4 : 2); vk_text(r, box.x + 14, box.y + 11, fmt.tprintf("%d  ·  %02d:%02d", i + 1, event.time / 60, event.time % 60), {255, 211, 92, 255}, .58); sentence := fmt.tprintf("%s  %s  ·  %s", strings.to_upper(event.actor), workbench_action_label(event.action), workbench_noun_label(event.room)); if len(sentence) > 39 do sentence = sentence[:39]; vk_text(r, box.x + 14, box.y + 38, sentence, {248, 247, 242, 255}, .62); vk_text(r, box.x + 220, box.y + 11, event_chain_fragment_label(g, i), color, .40)}
	event :=
		g.workbench_events[g.workbench_selected]; vk_text(r, 45, 420, fmt.tprintf("EVENT %d  ·  COMPLETE THE PROPOSITION", g.workbench_selected + 1), {255, 211, 92, 255}, .72)
	labels := [4]string {
		"WHEN",
		"WHO",
		"DID WHAT",
		"WHERE",
	}; values := [4]string{fmt.tprintf("%02d:%02d", event.time / 60, event.time % 60), strings.to_upper(event.actor), workbench_action_label(event.action), workbench_noun_label(event.room)}
	for value, i in values {box := event_chain_field_rect(i)
		missing := i == 1 && event.actor == "someone" || i == 3 && event.room == "unknown place"
		color := missing ? [4]u8{255, 144, 119, 255} : [4]u8{155, 201, 255, 255}
		vk_text(r, box.x, box.y - 22, labels[i], color, .52)
		vk_button(r, box, fmt.tprintf("‹  %s  ›", value), g.workbench_field == i)
		if missing do vulkan_ui_outline(r, box.x, box.y, box.w, box.h, color, 3)}
	if event_chain_disputed(
		g,
		g.workbench_selected,
	) {vulkan_ui_rect(r, 45, 548, 1110, 42, {89, 52, 68, 220}); vk_text(r, 65, 561, "CONFLICT  ·  THIS VERSION CANNOT AGREE WITH ALL ATTACHED EVIDENCE", {255, 144, 119, 255}, .62)} else {vulkan_ui_rect(r, 45, 548, 1110, 42, {35, 65, 48, 180}); vk_text(r, 65, 561, workbench_source_text(g, g.workbench_selected), {102, 205, 143, 255}, .58)}
	vk_button(
		r,
		{45, 600, 190, 44},
		"MOVE EARLIER",
		g.workbench_selected > 0,
	); vk_button(r, {250, 600, 190, 44}, "MOVE LATER", g.workbench_selected < g.workbench_event_count - 1); vk_text(r, 480, 614, "Ordering and testing are free.", {205, 207, 210, 255}, .55); vk_button(r, {40, 660, 180, 42}, "BACK"); vk_button(r, {900, 610, 255, 52}, workbench_first_incomplete(g) < 0 ? "TEST CHAIN" : "RESOLVE MISSING FIELDS", workbench_first_incomplete(g) < 0)
}

vk_draw_event_chain_test :: proc(r: ^Vulkan_Backend, g: ^Game) {
	result := g.workbench_result; failed := result.first_failed_event
	vk_heading(
		r,
		"DOLLHOUSE TEST",
		"The chain runs in order. The first impossible event stops the reconstruction.",
	)
	for i in 0 ..< g.workbench_event_count {event := g.workbench_events[i]; x := 45 + f32(i) * 128; color := i == failed ? [4]u8{255, 144, 119, 255} : failed < 0 || i < failed ? [4]u8{102, 205, 143, 255} : [4]u8{90, 89, 84, 255}; vulkan_ui_rect(r, x, 105, 116, 66, {37, 42, 49, 255}); vulkan_ui_outline(r, x, 105, 116, 66, color, i == failed ? 4 : 2); vk_text(r, x + 10, 117, fmt.tprintf("%02d:%02d", event.time / 60, event.time % 60), color, .52); vk_text(r, x + 10, 142, workbench_action_short(event.action), color, .52)}
	rooms := [4]string {
		"DINING ROOM",
		"HALL",
		"STUDY",
		"GARDEN",
	}; room_tints := [4][4]u8{{67, 58, 52, 255}, {55, 58, 63, 255}, {47, 54, 62, 255}, {48, 63, 53, 255}}
	for room, i in rooms {x := 65 + f32(i) * 285
		vulkan_ui_rect(r, x, 230, 250, 220, room_tints[i])
		vulkan_ui_outline(r, x, 230, 250, 220, {139, 107, 55, 255}, 3)
		vk_text(r, x + 18, 247, room, {255, 211, 92, 255}, .62)}
	active :=
		failed >= 0 ? failed : max(0, g.workbench_event_count - 1); if g.workbench_event_count > 0 {event := g.workbench_events[active]; room_index := 0; for room, i in WORKBENCH_ROOMS do if room == event.room && i > 0 do room_index = i - 1; x := 125 + f32(room_index) * 285; art := mini_actor_art(event.actor); vk_art_fit(r, art, x, 295, 105, 130); vk_text(r, x + 105, 330, workbench_action_label(event.action), failed >= 0 ? [4]u8{255, 144, 119, 255} : [4]u8{102, 205, 143, 255}, .62); if event.prop != "none" do vk_text(r, x + 105, 360, workbench_noun_label(event.prop), {255, 211, 92, 255}, .52)}
	color :=
		failed >= 0 ? [4]u8{255, 144, 119, 255} : [4]u8{102, 205, 143, 255}; vulkan_ui_rect(r, 120, 500, 960, 72, failed >= 0 ? [4]u8{89, 52, 68, 220} : [4]u8{35, 65, 48, 200}); vulkan_ui_outline(r, 120, 500, 960, 72, color, 3); vk_text(r, 155, 515, failed >= 0 ? "CHAIN BREAKS" : "CHAIN HOLDS", color, .72); _ = vk_text_wrapped(r, 155, 540, 875, result.message, {248, 247, 242, 255}, .62, 2); vk_button(r, {440, 630, 320, 54}, failed >= 0 ? "RETURN TO CONFLICT" : "RETURN TO EVENT CHAIN", true)
}

vk_draw_challenge :: proc(r: ^Vulkan_Backend, g: ^Game) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || g.question_selected < 0 || g.question_selected >= len(payload.questions) {vk_heading(r, "CHALLENGE", "No question selected."); vk_button(r, {40, 640, 220, 48}, "BACK"); return}
	question :=
		payload.questions[g.question_selected]; demo_index := demonstration_for_question(g, g.question_selected); if demo_index < 0 do return; demo := payload.demonstrations[demo_index]
	vk_heading(
		r,
		"CHALLENGE THE HYPOTHESIS",
		"Combine discovered evidence to test the claim. Demonstrations cost no ticks.",
	)
	vk_text(
		r,
		70,
		105,
		fmt.tprintf(
			"◇  %s",
			hypothesis_state_text(mystery_question_state(g, g.question_selected)),
		),
		hypothesis_state_color(mystery_question_state(g, g.question_selected)),
		.7,
	); _ = vk_text_wrapped(r, 70, 135, 1060, mystery_question_hypothesis_text(g, &question), {248, 247, 242, 255}, 1.05, 2)
	for slot in 0 ..< demo.slot_count {label := demo.slot_labels[slot]; x := 70 + f32(slot) * 365; selected := slot == g.question_slot; piece := mystery_question_slot(g, g.question_selected, slot); kind := strings.to_upper(demo.slot_types[slot]); type_color := knowledge_type_color(kind); glow := type_color; glow[3] = 110; vulkan_ui_rect(r, x, 205, 330, 104, {37, 42, 49, 255}); if selected do vulkan_ui_outline(r, x - 5, 200, 340, 114, glow, 6); vulkan_ui_outline(r, x, 205, 330, 104, type_color, selected ? 4 : 2); vk_text(r, x + 16, 220, fmt.tprintf("%s%s", selected ? "▶  " : "◇  ", label), type_color, .62); if piece == "" {vk_text(r, x + 16, 267, fmt.tprintf("CHOOSE %s", kind), {205, 207, 210, 255}, .67)} else {vk_text(r, x + 16, 257, fmt.tprintf("◆  %s", knowledge_piece_kind(g, piece)), type_color, .58); vk_text(r, x + 16, 282, "EVIDENCE PLACED", {102, 205, 143, 255}, .7)}}
	filter_kind := question_slot_piece_kind(
		g,
	); filter_color := knowledge_type_color(filter_kind); vk_text(r, 70, 340, fmt.tprintf("SHOWING: %s", filter_kind), filter_color, .72); piece_count := question_slot_piece_count(g); start := clamp(g.knowledge_cursor, 0, max(0, piece_count - 3)); for shown in 0 ..< min(3, piece_count - start) {piece := question_slot_piece_id(g, start + shown); x := 70 + f32(shown) * 365; kind := knowledge_piece_kind(g, piece); kind_color := knowledge_type_color(kind); vk_button(r, {x, 380, 330, 150}, ""); vulkan_ui_outline(r, x, 380, 330, 150, kind_color, 2); vk_text(r, x + 18, 397, fmt.tprintf("◆  %s", kind), kind_color, .62); _ = vk_text_wrapped(r, x + 18, 433, 294, knowledge_piece_text(g, piece), {248, 247, 242, 255}, .7, 3)}
	vk_button(
		r,
		{70, 555, 150, 48},
		"← PREV",
		start > 0,
	); vk_button(r, {235, 555, 150, 48}, "NEXT →", start + 3 < piece_count); vk_text(r, 430, 570, fmt.tprintf("%d EVIDENCE ITEMS", piece_count), {205, 207, 210, 255}, .62); if g.question_feedback != "" do _ = vk_text_wrapped(r, 610, 557, 530, g.question_feedback, {255, 211, 92, 255}, .62, 2); vk_button(r, {40, 640, 220, 48}, "BACK TO QUESTIONS"); full := question_slots_full(g, g.question_selected); vk_button(r, {845, 625, 300, 58}, full ? "DEMONSTRATE" : "FILL EVERY SLOT", full)
}

interaction_action_label :: proc(demo: ^Mystery_Demonstration, step: int) -> string {
	gesture :=
		demo.gesture; if step >= 0 && step < demo.gesture_step_count && demo.gesture_steps[step] != "" do gesture = demo.gesture_steps[step]
	switch gesture {case "rotate":
		return "ROTATE TO THE FOCUS POINT"; case "reveal":
		return "REVEAL THE RECORDED PROPERTY"; case "unfold":
		return "UNFOLD THE EVIDENCE"; case "operate":
		return "OPERATE THE MECHANISM"; case "join":
		return "BRING THE EDGES TOGETHER"; case "overlay":
		return "ALIGN THE OVERLAY"; case "contrast":
		return "COMPARE THE DISAGREEMENT"; case "align":
		return "ALIGN THE EVIDENCE"; case "order":
		return "TEST THIS ORDER"; case "resolve_conflict":
		return "RUN THE DISPUTED ACCOUNT"}
	return "TEST THE RELATIONSHIP"
}

vk_draw_investigation_interaction :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	demo: ^Mystery_Demonstration,
) {
	title := strings.to_upper(
		demo.presentation,
	); vk_heading(r, fmt.tprintf("%s EVIDENCE", title), "One deliberate gesture tests the relationship. Back preserves the selected evidence.")
	vk_panel(
		r,
		90,
		105,
		1020,
		465,
	); vk_text(r, 145, 132, strings.to_upper(demo.prompt), {255, 211, 92, 255}, .82); step_total := max(1, demo.gesture_step_count); vk_text(r, 880, 132, fmt.tprintf("STEP %d / %d", min(g.interaction_step + 1, step_total), step_total), {205, 207, 210, 255}, .62)
	placed := mystery_question_slots(
		g,
		g.question_selected,
	); if demo.presentation == "inspect" {vulkan_ui_rect(r, 400, 205, 400, 245, {37, 42, 49, 255}); vulkan_ui_outline(r, 400, 205, 400, 245, {255, 211, 92, 255}, 3); vk_text(r, 425, 228, "FOCUSED EVIDENCE", {205, 207, 210, 255}, .58); _ = vk_text_wrapped(r, 425, 280, 350, knowledge_piece_text(g, demo.subject), {248, 247, 242, 255}, .76, 5)} else {for slot in 0 ..< demo.slot_count {x := 150 + f32(slot) * 340; vulkan_ui_rect(r, x, 225, 290, 205, {37, 42, 49, 255}); vulkan_ui_outline(r, x, 225, 290, 205, slot == 0 ? [4]u8{255, 211, 92, 255} : [4]u8{155, 201, 255, 255}, 3); vk_text(r, x + 18, 245, strings.to_upper(demo.slot_labels[slot]), {205, 207, 210, 255}, .58); _ = vk_text_wrapped(r, x + 18, 290, 254, knowledge_piece_text(g, placed[slot]), {248, 247, 242, 255}, .72, 4)}}
	if demo.presentation ==
	   "connect" {progress := g.interaction_active ? f32(g.interaction_step + 1) / f32(step_total) : f32(1); left: f32 = 440; right: f32 = 760; gap := (right - left) * (1 - progress); vulkan_ui_rect(r, 520 - gap * .5, 455, 80 + gap, 4, {102, 205, 143, 255}); vk_text(r, 535, 475, strings.to_upper(demo.gesture), {102, 205, 143, 255}, .75)} else if demo.presentation == "inspect" {vulkan_ui_outline(r, 460, 200, 280, 260, {102, 205, 143, 180}, 5); vk_text(r, 505, 465, "FOCUS ASSIST · SNAP ENABLED", {102, 205, 143, 255}, .62)} else {vk_text(r, 430, 465, "FIRST CONFLICT STOPS THE RECONSTRUCTION", {255, 144, 119, 255}, .62)}
	if g.interaction_mismatch {vulkan_ui_rect(r, 130, 505, 940, 58, {89, 52, 68, 220}); _ = vk_text_wrapped(r, 155, 520, 890, g.question_feedback, {255, 184, 162, 255}, .65, 2); vk_button(r, {440, 630, 320, 54}, "CHANGE THE EVIDENCE", true)} else {vk_button(r, {440, 630, 320, 54}, interaction_action_label(demo, g.interaction_step), true)}
}

vk_draw_workbench_recreate :: proc(r: ^Vulkan_Backend, g: ^Game) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || g.active_demonstration < 0 || g.active_demonstration >= len(payload.demonstrations) {vk_heading(r, "DEMONSTRATION", "No authored demonstration is active."); vk_button(r, {440, 630, 320, 54}, "RETURN TO QUESTIONS"); return}
	demo :=
		payload.demonstrations[g.active_demonstration]; q := question_index_by_id(g, demo.question_id); state := q >= 0 ? mystery_question_state(g, q) : .Unsubstantiated; color := hypothesis_state_color(state)
	if g.interaction_active ||
	   g.interaction_mismatch {vk_draw_investigation_interaction(r, g, &demo); return}
	vk_heading(
		r,
		fmt.tprintf("%s DEMONSTRATION", strings.to_upper(demo.mode)),
		"The chosen evidence is tested against the claim.",
	); vk_panel(r, 90, 105, 1020, 465); vk_text(r, 145, 130, hypothesis_state_text(state), color, 1.0); if q >= 0 do _ = vk_text_wrapped(r, 145, 170, 900, mystery_question_hypothesis_text(g, &payload.questions[q]), {248, 247, 242, 255}, 1.0, 2)
	switch demo.mode {
	case "physical":
		if demo.question_id ==
		   "q_fragment_source" {vulkan_ui_rect(r, 180, 245, 330, 210, {47, 54, 62, 255}); vulkan_ui_outline(r, 225, 285, 230, 120, {173, 127, 63, 255}, 3); vk_text(r, 245, 310, "MIRIAM—STUDY, 8:20—", {248, 247, 242, 255}, .62); vulkan_ui_rect(r, 470, 335, 245, 5, {255, 211, 92, 255}); vulkan_ui_rect(r, 745, 245, 330, 210, {55, 48, 43, 255}); vulkan_ui_outline(r, 790, 285, 230, 120, {134, 101, 72, 255}, 3); vk_text(r, 810, 310, "—BRING THE ACCOUNTS", {248, 247, 242, 255}, .62); vk_text(r, 225, 470, "MEMO-PAD STUB", {255, 211, 92, 255}, .72); vk_text(r, 785, 470, "BURNED FRAGMENT", {102, 205, 143, 255}, .68)} else {vulkan_ui_rect(r, 145, 260, 310, 180, {47, 54, 62, 255}); vulkan_ui_rect(r, 745, 260, 310, 180, {48, 63, 53, 255}); vk_art_fit(r, .Evidence_Rug, 210, 300, 150, 100); vulkan_ui_rect(r, 455, 340, 290, 5, {255, 144, 119, 255}); for i in 0 ..< 6 do vulkan_ui_rect(r, 505 + f32(i) * 38, 330 + f32(i % 2) * 18, 14, 7, {102, 205, 143, 255}); vk_text(r, 505, 375, "BODY ROUTE", {102, 205, 143, 255}, .72)}
	case "timeline":
		if demo.question_id ==
		   "q_miriam_alibi" {vulkan_ui_rect(r, 190, 250, 820, 205, {67, 58, 52, 255}); vulkan_ui_outline(r, 320, 285, 560, 120, {139, 107, 55, 255}, 3); vk_art_fit(r, .Mini_Miriam, 245, 300, 90, 110); vk_art_fit(r, .Mini_Daniel, 865, 300, 90, 110); vulkan_ui_rect(r, 480, 340, 240, 5, {255, 144, 119, 255}); vk_text(r, 505, 295, "8:24", {255, 211, 92, 255}, 1.35); vk_text(r, 430, 430, "BOTH SETTINGS ABANDONED", {255, 144, 119, 255}, .75)} else if demo.question_id == "q_when_death" {vk_art_fit(r, .Evidence_Watch, 210, 270, 190, 190); vulkan_ui_rect(r, 470, 345, 500, 5, {125, 132, 143, 255}); vulkan_ui_rect(r, 635, 310, 6, 75, {255, 144, 119, 255}); vk_text(r, 585, 270, "8:24", {255, 211, 92, 255}, 1.35); vk_text(r, 855, 300, "8:20", {205, 207, 210, 255}, 1.0); vk_text(r, 510, 410, "8:20 MEMO PRECEDES THE FATAL STRIKE", {255, 144, 119, 255}, .7)} else {vulkan_ui_rect(r, 145, 260, 260, 180, {67, 58, 52, 255}); vulkan_ui_rect(r, 795, 260, 260, 180, {47, 54, 62, 255}); vulkan_ui_rect(r, 490, 250, 220, 200, {29, 31, 35, 255}); vk_text(r, 205, 320, "MIRIAM'S DENIAL", {255, 144, 119, 255}, .68); vk_text(r, 515, 320, "JOINED NOTE", {102, 205, 143, 255}, .72); vk_text(r, 515, 365, "STUDY · 8:20", {255, 211, 92, 255}, .82); vk_text(r, 445, 460, "DENIAL DISPROVED", {255, 144, 119, 255}, .75)}
	case "comparison":
		if demo.question_id ==
		   "q_miriam_motive" {vk_art_fit(r, .Evidence_Ledger, 210, 245, 190, 210); vulkan_ui_rect(r, 455, 340, 290, 4, {255, 211, 92, 255}); vulkan_ui_rect(r, 790, 265, 230, 150, {218, 205, 174, 255}); vulkan_ui_outline(r, 790, 265, 230, 150, {105, 82, 57, 255}, 3); vk_text(r, 815, 300, "MIRIAM—STUDY, 8:20—", {68, 53, 42, 255}, .55); vk_text(r, 815, 335, "TORN LOWER EDGE", {68, 53, 42, 255}, .48); vk_text(r, 175, 455, "UNRECEIPTED M.V. PAYMENTS", {255, 211, 92, 255}, .62); vk_text(r, 790, 455, "8:20 MEMO ENTRY", {102, 205, 143, 255}, .62)} else if demo.question_id == "q_miriam_study_meeting" {vulkan_ui_rect(r, 145, 260, 270, 170, {67, 58, 52, 255}); vulkan_ui_outline(r, 145, 260, 270, 170, {255, 144, 119, 255}, 3); vk_text(r, 185, 295, "MIRIAM'S DENIAL", {255, 144, 119, 255}, .7); _ = vk_text_wrapped(r, 175, 335, 210, "Edgar did not summon me.", {248, 247, 242, 255}, .62, 2); vulkan_ui_rect(r, 480, 270, 240, 150, {218, 205, 174, 255}); vulkan_ui_outline(r, 480, 270, 240, 150, {105, 82, 57, 255}, 3); vk_text(r, 500, 300, "MIRIAM—STUDY, 8:20—", {68, 53, 42, 255}, .52); vk_text(r, 520, 345, "TORN EDGE", {105, 82, 57, 255}, .55); vulkan_ui_rect(r, 785, 270, 270, 150, {187, 171, 142, 255}); vulkan_ui_outline(r, 785, 270, 270, 150, {105, 82, 57, 255}, 3); vk_text(r, 805, 300, "—BRING THE ACCOUNT BOOKS", {68, 53, 42, 255}, .48); vk_text(r, 825, 345, "MATCHING EDGE", {102, 105, 73, 255}, .55); vk_text(r, 485, 455, "JOINED SUMMONS DISPROVES THE DENIAL", {102, 205, 143, 255}, .62)} else {vk_art_fit(r, .Evidence_Cane, 250, 245, 110, 210); vk_art_fit(r, .Evidence_Statuette, 770, 245, 190, 210); vulkan_ui_rect(r, 450, 340, 300, 4, {255, 211, 92, 255}); vk_text(r, 485, 305, "WOUND PROFILE", {255, 211, 92, 255}, .7); vk_text(r, 505, 365, "MATCHES BRONZE BASE", {102, 205, 143, 255}, .7)}
	case "confrontation":
		vk_art_fit(
			r,
			demo.question_id == "q_daniel_lie" ? .Mini_Daniel : .Mini_Elsie,
			210,
			240,
			170,
			215,
		)
		vulkan_ui_rect(r, 430, 250, 570, 170, {37, 42, 49, 255})
		vulkan_ui_outline(r, 430, 250, 570, 170, color, 3)
		vk_text(r, 460, 275, "STATEMENT CHALLENGED", {155, 201, 255, 255}, .72)
		_ = vk_text_wrapped(r, 460, 315, 500, demo.result, {248, 247, 242, 255}, .72, 3)
	}
	vulkan_ui_rect(
		r,
		130,
		490,
		940,
		58,
		{35, 65, 48, 190},
	); _ = vk_text_wrapped(r, 155, 505, 890, demo.result, color, .65, 2); vk_button(r, {440, 630, 320, 54}, "RETURN TO QUESTIONS", true)
}

vk_recreate_figure :: proc(
	r: ^Vulkan_Backend,
	x, y: f32,
	label: string,
	tint: [4]u8,
	solid: bool,
) {
	alpha: u8 = solid ? 255 : 105; color := tint; color[3] = alpha
	vulkan_ui_rect(
		r,
		x,
		y + 21,
		28,
		55,
		color,
	); skin := [4]u8{226, 183, 150, alpha}; vulkan_ui_rect(r, x + 5, y, 18, 20, skin); vk_text(r, x - 12, y + 86, label, solid ? [4]u8{255, 218, 112, 255} : [4]u8{205, 207, 210, 180}, .65)
}

vk_draw_reveal_prep :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(
		r,
		"BUILD YOUR ACCUSATION",
		"Choose a candidate, then apply one established fact to each proof pillar.",
	)
	vk_text(
		r,
		80,
		105,
		"MURDER CANDIDATE",
		{255, 211, 92, 255},
		.72,
	); for i in 0 ..< 3 do vk_button(r, {330 + f32(i) * 190, 88, 175, 48}, suspect_name(g, i), mystery_game_accusation(g) == suspect_id(g, i))
	labels := [3]string {
		"MOTIVE",
		"MEANS",
		"OPPORTUNITY",
	}; for label, pillar in labels {y := 180 + f32(pillar) * 125; vulkan_ui_rect(r, 100, y, 1000, 100, {37, 42, 49, 255}); vulkan_ui_outline(r, 100, y, 1000, 100, mystery_game_theory_pillar(g, pillar) != "" ? [4]u8{102, 205, 143, 255} : [4]u8{90, 89, 84, 255}, 2); vk_text(r, 125, y + 18, label, {255, 211, 92, 255}, .72); id := mystery_game_theory_pillar(g, pillar); if id != "" {vk_text(r, 330, y + 15, "◆ ESTABLISHED FACT", {102, 205, 143, 255}, .58); _ = vk_text_wrapped(r, 330, y + 43, 650, known_deduction_proposition(g, id), {248, 247, 242, 255}, .64, 2)} else if mystery_game_accusation(g) == "" {vk_text(r, 330, y + 37, "Choose a candidate first.", {205, 207, 210, 255}, .66)} else if proof_pillar_piece_count(g, mystery_game_accusation(g), pillar) == 0 {vk_text(r, 330, y + 37, "No established fact supports this pillar yet.", {255, 144, 119, 255}, .66)} else {vk_text(r, 330, y + 37, "Choose an unlocked fact.", {255, 211, 92, 255}, .66)}; vk_button(r, {990, y + 24, 80, 50}, id == "" ? "ADD" : "NEXT", mystery_game_accusation(g) != "" && proof_pillar_piece_count(g, mystery_game_accusation(g), pillar) > 0)}
	ready := question_ready_to_present(
		g,
	); action_label := ready ? "PRESENT SUPPORTED ACCUSATION" : mystery_game_accusation(g) != "" ? "ACCUSE ANYWAY" : "END WITHOUT ACCUSATION"; vk_button(r, {40, 640, 200, 48}, "EDIT BOARD"); vk_button(r, {400, 620, 400, 58}, action_label, true); vk_button(r, {930, 640, 220, 48}, "NOTEBOOK")
}

finale_demo_label :: proc(step: int) -> string {
	labels := [3]string {
		"PLACE MIRIAM'S EXACT DENIAL",
		"PRESENT THE JOINED APPOINTMENT",
		"ANCHOR THE STRIKE AT 8:24",
	}
	return labels[clamp(step, 0, 2)]
}

finale_demo_message :: proc(g: ^Game) -> string {
	messages := [3]string {
		"Miriam's recorded words remain exact: 'He did not.' The room has already heard the denial the player chose to preserve.",
		"The proof returns already earned: two rooms, two scraps, one joined summons at 8:20. Miriam reaches to square the paper, then leaves it crooked.",
		"Blood and bronze in Edgar's crushed watch place the fatal strike at 8:24—four minutes after the appointment Miriam denied.",
	}
	message := messages[clamp(g.finale_demo_step, 0, 2)]
	if g.finale_demo_step >= 2 && !knowledge_piece_known(g, "ded_miriam_denial_disproved") do return "The fragments point toward Miriam, but your account has not established both her denial and the matching note."
	return message
}

vk_draw_finale_demonstration :: proc(r: ^Vulkan_Backend, g: ^Game) {
	supported := knowledge_piece_known(g, "ded_miriam_denial_disproved")
	vk_heading(r, "THE FINAL REVEAL", "Act V of 5 — perform the decisive proof.")
	vk_panel(
		r,
		105,
		105,
		990,
		470,
	); vk_text(r, 150, 135, "ACT V — THE TORN APPOINTMENT", {255, 211, 92, 255}, 1.6)
	if g.finale_demo_step >= 1 do vk_text(r, 535, 180, "8:20", {255, 211, 92, 255}, 2)
	vulkan_ui_rect(
		r,
		155,
		235,
		260,
		205,
		{67, 58, 52, 255},
	); vulkan_ui_outline(r, 155, 235, 260, 205, {139, 107, 55, 255}, 3); vk_text(r, 170, 255, "MIRIAM'S SITTING ROOM", {255, 211, 92, 255}, .8)
	vulkan_ui_rect(
		r,
		785,
		235,
		260,
		205,
		{47, 54, 62, 255},
	); vulkan_ui_outline(r, 785, 235, 260, 205, {139, 107, 55, 255}, 3); vk_text(r, 880, 255, "STUDY", {255, 211, 92, 255}, .8)
	vk_art_fit(r, .Mini_Miriam, 220, 285, 90, 110)
	if g.finale_demo_step >= 1 {
		vulkan_ui_rect(
			r,
			505,
			225,
			190,
			225,
			{29, 31, 35, 255},
		); vulkan_ui_outline(r, 505, 225, 190, 225, {173, 127, 63, 255}, 4)
		for y in 0 ..< 7 do vulkan_ui_rect(r, 520, 245 + f32(y) * 27, 160, 19, {68, 71, 77, 255})
	}
	vulkan_ui_rect(
		r,
		275,
		327,
		225,
		4,
		{255, 144, 119, 255},
	); vulkan_ui_rect(r, 500, 314, 9, 30, {255, 144, 119, 255}); vk_text(r, 350, 350, "HE DID NOT", {255, 144, 119, 255}, .8)
	if g.finale_demo_step >=
	   1 {vk_art_fit(r, .Evidence_Ledger, 875, 285, 92, 92); vk_text(r, 840, 410, supported ? "TORN EDGES — MATCH" : "NOTE NOT SUPPORTED", supported ? [4]u8{102, 205, 143, 255} : [4]u8{208, 126, 91, 255}, .7)}
	if g.finale_demo_step >=
	   2 {vk_art_fit(r, .Evidence_Watch, 675, 275, 85, 105); vk_text(r, 625, 400, "WATCH STOPPED 8:24", {255, 211, 92, 255}, .7)}
	_ = vk_text_wrapped(
		r,
		155,
		480,
		890,
		finale_demo_message(g),
		g.finale_demo_step >= 2 && supported ? [4]u8{102, 205, 143, 255} : [4]u8{248, 247, 242, 255},
		1,
	)
	vk_button(r, {440, 630, 320, 54}, finale_demo_label(g.finale_demo_step), true)
}

vk_draw_reveal_act_stage :: proc(r: ^Vulkan_Backend, g: ^Game, act: int, supported: bool) {
	x, y :=
		f32(755),
		f32(
			255,
		); vulkan_ui_rect(r, x, y, 275, 220, {35, 39, 45, 255}); vulkan_ui_outline(r, x, y, 275, 220, supported ? [4]u8{102, 205, 143, 255} : [4]u8{116, 91, 48, 255}, 3); vk_text(r, x + 18, y + 15, "YOUR CLOCKWORK SCENE", {255, 211, 92, 255}, .72)
	for socket in 0 ..< board_socket_count(
		act,
	) {placed := g.board_sockets[act][socket]; vk_text(r, x + 20, y + 43 + f32(socket) * 22, fmt.tprintf("%s %s", placed ? "◆" : "◇", board_socket_label(act, socket)), placed ? [4]u8{102, 205, 143, 255} : [4]u8{205, 207, 210, 255}, .58)}
	switch act {
	case 0:
		vulkan_ui_rect(r, x + 35, y + 125, 62, 43, {64, 91, 76, 220})
		vk_text(r, x + 44, y + 139, "LEDGER", {248, 247, 242, 255}, .5)
		vk_recreate_figure(r, x + 188, y + 115, "MIRIAM", {122, 67, 91, 255}, supported)
	case 1:
		vk_recreate_figure(r, x + 55, y + 125, "MIRIAM", {122, 67, 91, 255}, supported)
		vk_recreate_figure(r, x + 190, y + 125, "EDGAR", {92, 87, 72, 255}, supported)
		vulkan_ui_rect(r, x + 126, y + 148, 38, 12, {151, 109, 57, 255})
		vk_text(r, x + 112, y + 180, "8:24", {255, 211, 92, 255}, .65)
	case 2:
		vulkan_ui_rect(r, x + 32, y + 145, 48, 15, {151, 109, 57, 255})
		vulkan_ui_rect(r, x + 112, y + 156, 68, 12, {92, 87, 72, 200})
		vulkan_ui_rect(r, x + 220, y + 135, 10, 48, {92, 87, 72, 200})
		vk_text(
			r,
			x + 25,
			y + 185,
			"CLEAN  →  MOVE  →  STAGE",
			supported ? [4]u8{102, 205, 143, 255} : [4]u8{205, 207, 210, 255},
			.55,
		)
	case 3:
		vulkan_ui_rect(r, x + 35, y + 125, 205, 70, {102, 70, 47, 255})
		vk_recreate_figure(r, x + 70, y + 112, "DANIEL", {58, 88, 121, 255}, supported)
		vk_recreate_figure(r, x + 175, y + 112, "ELSIE", {92, 87, 72, 255}, supported)
		vulkan_ui_rect(r, x + 100, y + 184, 75, 5, {118, 35, 42, 220})
	}
}

vk_draw_reveal :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if g.reveal_act == 4 {vk_draw_finale_demonstration(r, g); return}
	subtitles := [4]string {
		"Act I of 5 — establish the pressure behind the murder.",
		"Act II of 5 — reconstruct where, when, and how Edgar died.",
		"Act III of 5 — turn the garden accident back into a deliberate scene.",
		"Act IV of 5 — separate the lies that concealed other crimes.",
	}
	subtitle := subtitles[clamp(g.reveal_act, 0, 3)]
	vk_heading(r, "THE FINAL REVEAL", subtitle)
	acts := [5]string{"MOTIVE", "THE MURDER", "THE FALSE SCENE", "THE OTHER LIES", ""}
	first, second := reveal_act_lines(
		g,
		g.reveal_act,
	); third := reveal_act_third_line(g, g.reveal_act); supported := reveal_act_supported(g, g.reveal_act); presented := mystery_game_reveal_presented(g, g.reveal_act)
	vk_panel(
		r,
		120,
		120,
		960,
		430,
	); vk_text(r, 170, 155, acts[g.reveal_act], {255, 211, 92, 255}, 2)
	status :=
		supported ? (presented ? "EVIDENCE PRESENTED" : "CHALLENGED / EVIDENCE READY") : "WEAK OR MISSING"
	vk_text(
		r,
		170,
		220,
		status,
		supported ? (presented ? [4]u8{102, 205, 143, 255} : [4]u8{255, 211, 92, 255}) : [4]u8{208, 126, 91, 255},
	); vk_text(r, 170, 270, "DETECTIVE:", {255, 211, 92, 255})
	body_scale :=
		g.reveal_act == 3 ? f32(.72) : f32(1); line_y := vk_text_wrapped(r, 170, 305, 535, first, {248, 247, 242, 255}, body_scale, 3)
	if second != "" do line_y = vk_text_wrapped(r, 170, line_y, 535, second, {248, 247, 242, 255}, body_scale, 3)
	if third != "" do line_y = vk_text_wrapped(r, 170, line_y, 535, third, {248, 247, 242, 255}, body_scale, 3)
	response_label_y :=
		g.reveal_act == 3 ? max(line_y + 5, f32(430)) : max(line_y + 8, f32(410)); vk_text(r, 170, response_label_y, "RESPONSE:", {255, 211, 92, 255})
	response := reveal_act_response(g, g.reveal_act, supported, presented)
	_ = vk_text_wrapped(
		r,
		170,
		response_label_y + 28,
		535,
		response,
		{248, 247, 242, 255},
		g.reveal_act == 3 ? f32(.72) : f32(1),
		3,
	)
	vk_draw_reveal_act_stage(
		r,
		g,
		g.reveal_act,
		supported,
	); button_label := supported && !presented ? "PRESENT ESTABLISHED EVIDENCE" : "CONTINUE REVEAL"; vk_button(r, {440, 630, 320, 54}, button_label, true)
}

vk_draw_result :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if ending := active_case_ending(g); ending != nil {
		core_ending := mystery_core_ending(
			g.story_project,
			ending,
		); title, summary := "CASE END", ""; if core_ending != nil {title = core_ending.title; summary = core_ending.summary}
		accent := [4]u8{205, 207, 210, 255}; switch ending.tone {case "success":
			accent = {102, 205, 143, 255}; case "warning":
			accent = {255, 211, 92, 255}; case "failure":
			accent = {255, 144, 119, 255}; case:}
		vk_heading(
			r,
			"CASE END",
			ending.subtitle,
		); vk_panel(r, 120, 105, 960, 470); vk_text(r, 170, 135, title, accent, 1.35); _ = vk_text_wrapped(r, 170, 180, 860, summary, {248, 247, 242, 255}, .88, 3)
		vulkan_ui_rect(
			r,
			170,
			260,
			860,
			1,
			{139, 107, 55, 170},
		); if ending.epilogue != "" && !g.show_canonical {vk_text(r, 170, 285, "WHAT FOLLOWS", {255, 211, 92, 255}, .72); _ = vk_text_wrapped(r, 170, 320, 860, ending.epilogue, {205, 207, 210, 255}, .76, 5)}
		if g.show_canonical &&
		   ending.canonical_timeline !=
			   "" {vulkan_ui_rect(r, 155, 270, 890, 260, {24, 28, 34, 254}); vulkan_ui_outline(r, 155, 270, 890, 260, {139, 107, 55, 210}, 1); vk_text(r, 185, 295, "POST-CASE CANONICAL ACCOUNT", {255, 211, 92, 255}, .82); _ = vk_text_wrapped(r, 185, 340, 830, ending.canonical_timeline, {248, 247, 242, 255}, .8, 7)}
		primary :=
			ending.primary_action == "reveal" && g.show_canonical ? "TIMELINE REVEALED" : ending.primary_label; vk_button(r, {300, 630, 280, 54}, primary, ending.primary_action != "reveal" || !g.show_canonical); if ending.secondary_label != "" do vk_button(r, {620, 630, 280, 54}, ending.secondary_label)
		return
	}
	vk_heading(
		r,
		"CASE OUTCOME",
		fmt.tprintf(
			"Accused: %s",
			mystery_game_accusation(g) == "" ? "none" : character_display_name(g, mystery_game_accusation(g)),
		),
	); labels := [5]string{"AIRTIGHT SOLUTION", "CORRECT, BUT UNPROVEN", "PLAUSIBLE, BUT INCOMPLETE", "WRONG ACCUSATION", "CASE UNRESOLVED"}; summaries := [5]string{"The joined note defeats Miriam's denial. Daniel's affair and Elsie's theft explain their lies without sharing her guilt.", "Your account points to Miriam, but a material gap remains in the proof, a competing lie, or the physical sequence.", "You name Miriam, but too much of the night remains unproved for the accusation to hold.", "The night you describe cannot be reconciled with the person you accuse.", "You bring no complete accusation to the table."}; vk_panel(r, 120, 105, 960, 470); vk_text(r, 170, 130, labels[int(g.result)], g.result == .Airtight ? [4]u8{102, 205, 143, 255} : [4]u8{208, 126, 91, 255}, 1.35); _ = vk_text_wrapped(r, 170, 170, 860, summaries[int(g.result)])
	section_labels := [5]string {
		"WHO",
		"WHAT HAPPENED",
		"WHERE / WHEN",
		"CONCEALMENT",
		"CONTRADICTION",
	}; categories := [5]string{"who", "what", "where_when", "concealment", "contradiction"}; vk_text(r, 170, 235, "YOUR DEMONSTRATED FRAMEWORK", {255, 211, 92, 255}, .9); for label, i in section_labels {count := final_category_count(g, categories[i]); color := count > 0 ? [4]u8{102, 205, 143, 255} : [4]u8{208, 126, 91, 255}; vk_text(r, 185, 270 + f32(i) * 34, label, {248, 247, 242, 255}, .72); vk_text(r, 405, 270 + f32(i) * 34, count > 0 ? fmt.tprintf("%d ESTABLISHED", count) : "MISSING", color, .62)}
	excluded, total := exclusion_progress(
		g,
	); vk_text(r, 185, 450, fmt.tprintf("INNOCENT SUSPECTS EXCLUDED  %d / %d", excluded, total), excluded == total ? [4]u8{102, 205, 143, 255} : [4]u8{255, 211, 92, 255}, .72); chronology_ok := mystery_timeline_order_possible(g, g.timeline_order); vk_text(r, 185, 482, chronology_ok ? "CHRONOLOGY  POSSIBLE" : "CHRONOLOGY  CONTRADICTED", chronology_ok ? [4]u8{102, 205, 143, 255} : [4]u8{208, 126, 91, 255}, .72)
	if g.show_canonical {vk_text(r, 605, 235, "POST-CASE CANONICAL TIMELINE", {255, 211, 92, 255}, .9); _ = vk_text_wrapped(r, 605, 275, 420, "Edgar summoned Miriam to the study at 8:20. She killed him at 8:24, cleaned the statuette at 8:25, moved his body at 8:27, and staged the garden fall at 8:29. In her sitting room she tried to burn her half of the summons at 8:30, hid the surviving fragment at 8:31, and returned to dinner at 8:33. Daniel saw her return. The joined fragments expose her denial.", {248, 247, 242, 255}, .82)} else {diagnosis := g.mystery_state != nil ? mystery_diagnose_player(g.story_project, g.mystery_state) : Mystery_Diagnosis{}; vk_text(r, 605, 235, "WHY THIS RESULT", {255, 211, 92, 255}, .9); lines := [3]string{diagnosis.complete ? "The accusation names a supported suspect." : "The accusation remains incomplete.", diagnosis.evidence_supported ? "The required evidence routes are supported." : fmt.tprintf("%d required support route%s remain open.", diagnosis.missing_requirement_count, diagnosis.missing_requirement_count == 1 ? "" : "s"), diagnosis.exclusive ? "The established account excludes competing suspects." : "Competing explanations have not all been excluded."}; for line, i in lines do _ = vk_text_wrapped(r, 620, 275 + f32(i) * 50, 390, fmt.tprintf("• %s", line), {205, 207, 210, 255}, .68)}
	vk_button(
		r,
		{300, 630, 280, 54},
		g.show_canonical ? "TIMELINE REVEALED" : "REVEAL CANONICAL TIMELINE",
	); vk_button(r, {620, 630, 280, 54}, "RESTART CASE")
}

vk_draw_game_over :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_art_cover(
		r,
		.Title,
		0,
		0,
		WINDOW_WIDTH,
		WINDOW_HEIGHT,
	); vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 190}); vk_panel(r, 250, 105, 700, 510)
	vk_text(
		r,
		460,
		145,
		"OUT OF TIME",
		{255, 144, 119, 255},
		2.2,
	); vulkan_ui_rect(r, 350, 200, 500, 2, {116, 91, 48, 220})
	vk_text(
		r,
		420,
		235,
		"THE INVESTIGATION CLOCK REACHED ZERO",
		{255, 211, 92, 255},
		.72,
	); reason := g.game_over_reason; if reason == "" do reason = "Time expired before a complete reconstruction was prepared."; _ = vk_text_wrapped(r, 330, 275, 540, reason, {248, 247, 242, 255}, .88, 4)
	vk_text(r, 382, 350, "Choose how to continue.", {205, 207, 210, 255}, .78)
	vk_button(
		r,
		{410, 410, 380, 52},
		"RELOAD CASE",
		true,
	); vk_button(r, {410, 478, 380, 52}, "MAIN MENU"); vk_button(r, {410, 546, 380, 52}, "QUIT")
}

block_route_stats :: proc(g: ^Game, block: string) -> (routes, guaranteed, min_cost: int) {
	min_cost = 999; payload := mystery_game_payload(g); if payload == nil do return
	for &clue in payload.clues {found := false; for i in 0 ..< clue.block_count do if clue.blocks[i] == block do found = true; if found {routes += 1; if clue.essential do guaranteed += 1; min_cost = min(min_cost, clue.cost)}}
	if min_cost == 999 do min_cost = 0
	return
}

vk_draw_diagnostics :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(
		r,
		"DEVELOPMENT DIAGNOSTICS",
		"F12 only | canonical state and route safety; never shown to players",
	)
	vk_text(
		r,
		30,
		95,
		"CANONICAL  20:15 close → 20:24 murder → 20:25 clean → 20:27 move → 20:29 stage → 20:30 burn → 20:31 hide → 20:33 return",
		{255, 211, 92, 255},
		.9,
	)
	vk_text(
		r,
		30,
		125,
		fmt.tprintf(
			"STATE  %d clues | %d actions left | phase %v",
			count_discovered(g),
			g.ap,
			g.phase,
		),
		{248, 247, 242, 255},
		.9,
	)
	vk_text(r, 30, 165, "REQUIRED ROUTE REPORT", {255, 211, 92, 255}, 1.1)
	payload := mystery_game_payload(
		g,
	); if payload == nil do return; solution := &payload.solution; labels := [7]string{"Weapon", "Murder place", "Death time", "Body movement", "Staging", "Cleaning", "False alibi"}; blocks := [7]string{solution.weapon_block, solution.murder_place_block, solution.death_time_block, solution.body_movement_block, solution.staging_block, solution.cleaning_block, solution.alibi_block}
	for label, i in labels {routes, guaranteed, cost := block_route_stats(g, blocks[i])
		color := guaranteed > 0 ? [4]u8{102, 205, 143, 255} : [4]u8{255, 144, 119, 255}
		vk_text(r, 55, 205 + f32(i) * 34, label)
		vk_text(
			r,
			300,
			205 + f32(i) * 34,
			fmt.tprintf(
				"%d route%s | %d guaranteed | cheapest %d",
				routes,
				routes == 1 ? "" : "s",
				guaranteed,
				cost,
			),
			color,
			.9,
		)}
	essential_cost := 0; for clue in payload.clues do if clue.essential do essential_cost += clue.cost
	vk_text(
		r,
		700,
		205,
		"SAFETY GATES",
		{255, 211, 92, 255},
		1.1,
	); vk_text(r, 720, 245, fmt.tprintf("Protected white-check route: %d / %d actions", essential_cost, payload.action_budget), essential_cost <= payload.action_budget ? [4]u8{102, 205, 143, 255} : [4]u8{255, 144, 119, 255}, .9)
	vk_text(
		r,
		720,
		280,
		"Essential failures: explicit free fallback",
		{102, 205, 143, 255},
		.9,
	); vk_text(r, 720, 315, "Repeated discoveries: no time cost", {102, 205, 143, 255}, .9); vk_text(r, 720, 350, "Innocent complete solutions: rejected", {102, 205, 143, 255}, .9)
	vk_text(
		r,
		700,
		395,
		"DESTROYED EVIDENCE",
		{255, 211, 92, 255},
		1.1,
	); _ = vk_text_wrapped(r, 720, 430, 440, "Daniel protects the affair. Elsie protects an earlier theft. Miriam denies Edgar's summons, but the fragment from the metal wastebin in her sitting room joins his 8:20 memo stub.", {205, 207, 210, 255}, .9)
	vk_text(
		r,
		30,
		475,
		"FIRST-PLAYTHROUGH PACE",
		{255, 211, 92, 255},
		.82,
	); pace_labels := [6]string{"ARRIVE", "3 ACCOUNTS", "FALSE SCENE", "OTHER LIES", "TORN NOTE", "OUTCOME"}; for label, i in pace_labels {recorded := (g.case_pacing_mask & (u8(1) << u8(i))) != 0; value := recorded ? pacing_time_label(g.case_pacing_times[i]) : "--:--"; vk_text(r, 55 + f32(i % 2) * 260, 505 + f32(i / 2) * 28, fmt.tprintf("%s  %s", value, label), recorded ? [4]u8{102, 205, 143, 255} : [4]u8{150, 153, 158, 255}, .58)}; vk_button(r, {550, 505, 300, 42}, "COPY PLAYTEST REPORT")
	vk_button(r, {20, 650, 180, 42}, "CLOSE DIAGNOSTICS")
}

question_resolved :: proc(g: ^Game, index: int) -> bool {
	return question_is_resolved(g, index)
}

ATTRIBUTE_NAMES := [4]string{"OBSERVATION", "ANALYSIS", "EMPATHY", "PRESSURE"}
ATTRIBUTE_SKILLS := [4]string{"Observation", "Analysis", "Empathy", "Pressure"}
ATTRIBUTE_DOMAINS := [4]string {
	"SENSE THE SCENE",
	"CONNECT THE FACTS",
	"READ THE PERSON",
	"CONTROL THE ROOM",
}
ATTRIBUTE_DESCRIPTIONS := [4]string {
	"Notices small physical details: disturbed objects, hidden traces, and the one thing in a room that does not belong.",
	"Tests whether facts agree. Reconstructs sequence, motive, timing, and the contradictions between separate accounts.",
	"Listens beneath an answer for fear, loyalty, shame, or grief. Finds what a person is protecting without forcing them.",
	"Applies nerve and authority when silence must break. Pushes guarded people and commits to confrontational approaches.",
}

vk_draw_attribute_portrait :: proc(r: ^Vulkan_Backend, index: int, x, y, size: f32, color: [4]u8) {
	texture := vulkan_ui_art_texture(r, .Attribute_Portraits)
	if texture <
	   0 {vk_draw_helper_badge(r, x, y, ATTRIBUTE_SKILLS[clamp(index, 0, 3)], color); return}
	column, row :=
		index %
		2,
		index /
		2; cell_min := Vec2{.014 + f32(column) * .5, .014 + f32(row) * .5}; cell_max := Vec2{.486 + f32(column) * .5, .486 + f32(row) * .5}
	vulkan_ui_quad(
		r,
		x,
		y,
		size,
		size,
		{255, 255, 255, 255},
		texture,
		cell_min,
		cell_max,
		true,
	); vulkan_ui_outline(r, x, y, size, size, color, 3)
}

vk_menu_overlay_back_button :: proc(r: ^Vulkan_Backend, g: ^Game, return_screen: Screen) {
	box := menu_overlay_back_rect(

	); vk_button(r, box, menu_overlay_back_label(return_screen)); vk_prompt_icon(r, g, .Back, box.x + box.w - 27, box.y + 5, 20); context_label := menu_overlay_context_label(return_screen); if context_label != "" do vk_text(r, 850, 660, context_label, {170, 176, 184, 255}, .56)
}

vk_draw_attributes :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(
		r,
		"DETECTIVE ATTRIBUTES",
		"Four voices shape every check — select one to hear what it does",
	)
	for name, i in ATTRIBUTE_NAMES {
		skill :=
			ATTRIBUTE_SKILLS[i]; x, y := f32(42), 145 + f32(i) * 117; _, voice, color := skill_helper(skill); selected := i == g.attribute_selected
		vk_button(
			r,
			{x, y, 250, 105},
			"",
			selected,
		); vk_draw_attribute_portrait(r, i, x + 10, y + 1, 105, color)
		vk_text(
			r,
			x + 122,
			y + 12,
			name,
			color,
			.58,
		); vulkan_ui_rect(r, x + 122, y + 34, 108, 2, color); vk_text(r, x + 122, y + 43, fmt.tprintf("%+d", skill_index(skill)), color, 1.75); vk_text(r, x + 122, y + 77, "CHECK MODIFIER", {205, 207, 210, 255}, .46)
		if selected {vk_panel(r, 330, 145, 828, 456); vulkan_ui_outline(r, 330, 145, 828, 456, color, 3); vk_text(r, 380, 188, name, color, 2.5); vk_text(r, 382, 240, ATTRIBUTE_DOMAINS[i], {255, 211, 92, 255}, .85); vk_draw_attribute_portrait(r, i, 970, 174, 155, color); _ = vk_text_wrapped(r, 380, 300, 550, ATTRIBUTE_DESCRIPTIONS[i], {248, 247, 242, 255}, 1.0, 4); vulkan_ui_rect(r, 380, 430, 690, 1, {139, 107, 55, 190}); vk_text(r, 380, 458, "INNER VOICE", {205, 207, 210, 255}, .62); _ = vk_text_wrapped(r, 380, 490, 690, voice, color, .9, 2); vk_text(r, 380, 558, fmt.tprintf("BASE CHECK MODIFIER  %+d", skill_index(skill)), color, .72)}
	}
	vk_menu_overlay_back_button(r, g, g.menu_detail_return)
}

vk_draw_notebook :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vk_heading(
		r,
		"POCKET NOTEBOOK",
		"Observations record what was found; objectives recall where the story left off.",
	); tabs := [6]string{"KNOWLEDGE", "STATEMENTS", "PEOPLE", "QUESTIONS", "OBJECTIVES", "HISTORY"}; vk_tab_bar(r, {20, 91, 1126, 54}); for label, i in tabs do vk_tab(r, {20 + f32(i) * 190, 95, 176, 46}, label, i == g.notebook_tab); vk_panel(r, 20, 158, 1160, 462); vulkan_ui_scissor(r, 26, 164, 1148, 450); y: f32 = 180 - g.notebook_scroll; shown := 0
	payload := mystery_game_payload(g)
	switch g.notebook_tab {
	case 0:
		if payload !=
		   nil {for &clue in payload.clues do if knowledge_piece_known(g, clue.id) {vk_text(r, 40, y, "OBSERVED", {255, 211, 92, 255}); y = max(vk_text_wrapped(r, 160, y, 980, mystery_clue_proposition_text(g.story_project, &clue)), y + 38); shown += 1}; for deduction in payload.deductions do if knowledge_piece_known(g, deduction.id) {vk_text(r, 40, y, "DEDUCED", {102, 205, 143, 255}); y = max(vk_text_wrapped(r, 160, y, 980, mystery_story_proposition_text(g.story_project, deduction.proposition_id)), y + 38); shown += 1}}
	case 1:
		if payload != nil do for claim in payload.claims do if claim_known(g, claim.id) {vk_text(r, 40, y, "SAID", {155, 201, 255, 255}); y = max(vk_text_wrapped(r, 160, y, 980, mystery_story_proposition_text(g.story_project, claim.proposition_id)), y + 38); shown += 1}
	case 2:
		if g.story_project != nil do for character in g.story_project.entities do if character.kind == "character" && character.tag_count > 0 && character.tags[0] == "suspect" {vk_text(r, 40, y, character.display_name, {255, 211, 92, 255}); y = max(vk_text_wrapped(r, 260, y, 870, character.description), y + 55); shown += 1}
	case 3:
		if payload != nil do for question, i in payload.questions do if question_unlocked(g, i) {state := mystery_question_state(g, i); resolved := question_is_resolved(g, i); vk_text(r, 40, y, hypothesis_state_text(state), hypothesis_state_color(state), .5); vk_text(r, 210, y, question.prompt, resolved ? [4]u8{205, 207, 210, 255} : [4]u8{248, 247, 242, 255}, .7); y += 45; shown += 1}
	case 4:
		if g.story_project != nil && g.story_state != nil {
			for objective in g.story_project.objectives {state_index := story_state_objective_index(g.story_state, objective.id); if objective.hidden || state_index < 0 || g.story_state.objectives[state_index].status != .Active do continue; vk_text(r, 40, y, "ACTIVE", {255, 211, 92, 255}, .48); vk_text(r, 160, y, objective.display_name, {248, 247, 242, 255}, .72); y = max(vk_text_wrapped(r, 160, y + 25, 950, objective.description, {205, 207, 210, 255}, .58, 3), y + 68); shown += 1}
			last_sequence: u64 = 0; for state in g.story_state.objectives do if state.status == .Completed && state.completed_sequence > last_sequence do last_sequence = state.completed_sequence
			for pass in 0 ..< len(
				g.story_state.objectives,
			) {wanted: u64 = 0; wanted_index := -1; for state, state_index in g.story_state.objectives {if state.status != .Completed || state.completed_sequence == 0 || state.completed_sequence > last_sequence || state.completed_sequence <= wanted do continue; wanted = state.completed_sequence; wanted_index = state_index}; if wanted_index < 0 do break; state := g.story_state.objectives[wanted_index]; objective_index := story_objective_index(g.story_project, state.objective_id); if objective_index >= 0 && !g.story_project.objectives[objective_index].hidden {objective := g.story_project.objectives[objective_index]; vk_text(r, 40, y, "COMPLETE", {117, 229, 169, 255}, .42); vk_text(r, 160, y, objective.display_name, {205, 207, 210, 255}, .66); y += 42; shown += 1}; last_sequence = wanted - 1}
			for reverse in 0 ..< len(
				g.story_state.objectives,
			) {state_index := len(g.story_state.objectives) - 1 - reverse; state := g.story_state.objectives[state_index]; if state.status != .Completed || state.completed_sequence != 0 do continue; objective_index := story_objective_index(g.story_project, state.objective_id); if objective_index >= 0 && !g.story_project.objectives[objective_index].hidden {vk_text(r, 40, y, "COMPLETE", {117, 229, 169, 255}, .42); vk_text(r, 160, y, g.story_project.objectives[objective_index].display_name, {205, 207, 210, 255}, .66); y += 42; shown += 1}}
		}
	case 5:
		for i in 0 ..< g.history_count {vk_text(r, 40, y, fmt.tprintf("%02d", i + 1), {205, 207, 210, 255}); y = max(vk_text_wrapped(r, 90, y, 1040, g.history[i]), y + 38); shown += 1}
	}
	g.notebook_scroll_max = max(
		0,
		y + g.notebook_scroll - 596,
	); g.notebook_scroll_target = clamp(g.notebook_scroll_target, 0, g.notebook_scroll_max); vulkan_ui_scissor_reset(r)
	if shown == 0 do vk_text(r, 430, 350, "Nothing established in this category yet.", {205, 207, 210, 255})
	if g.notebook_scroll_max >
	   0 {rail_y: f32 = 174; rail_h: f32 = 426; thumb_h := max(48, rail_h * rail_h / (rail_h + g.notebook_scroll_max)); thumb_y := rail_y + (rail_h - thumb_h) * g.notebook_scroll / g.notebook_scroll_max; vulkan_ui_rect(r, 1160, rail_y, 3, rail_h, {116, 122, 136, 180}); vulkan_ui_rect(r, 1156, thumb_y, 11, thumb_h, {255, 211, 92, 230}); vk_text(r, 1075, 630, "SCROLL  ↕", {205, 207, 210, 255}, .48)}
	vk_menu_overlay_back_button(r, g, g.notebook_return)
}

SCENE_TRANSITION_DURATION :: f32(.68)
