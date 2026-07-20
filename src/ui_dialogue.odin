package main

import "core:fmt"
import "core:math"
import "core:strings"
import ui "zelda_engine:ui"

vk_dialogue_ledger_line :: proc(
	r: ^Vulkan_Backend,
	x, y, width: f32,
	speaker, text: string,
	color: [4]u8,
) -> f32 {
	// A turn reads as a paragraph, with one stable text edge. The colored rule
	// makes speaker changes visible without forcing the eye across two columns.
	vulkan_ui_rect(r, x, y + 2, 3, 14, color)
	vk_text(r, x + 12, y, strings.to_upper(speaker), color, .68)
	return vk_text_wrapped(r, x + 12, y + 19, width - 12, text, {248, 247, 242, 255}, .70, 3) + 7
}

dialogue_transcript_entry_height :: proc(entry: ^Dialogue_Transcript_Entry, width: f32) -> f32 {
	if entry == nil do return 0
	return dialogue_ledger_line_height(dialogue_semantic_text(entry.text, entry.kind), width)
}

vk_draw_character_transcript :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	conversation_id: string,
) -> bool {
	indices: [256]int; count := 0
	for entry, i in g.conversation_transcript[:g.conversation_transcript_count] do if entry.conversation_id == conversation_id && count < len(indices) {indices[count] = i; count += 1}
	if count == 0 do return false
	max_scroll := max(
		0,
		count - 1,
	); scroll := clamp(g.dialogue_ledger_scroll, 0, max_scroll); end := count - scroll; start := end - 1; latest := &g.conversation_transcript[indices[end - 1]]; latest_entity := world_entity_index(latest.speaker); latest_portrait := latest.kind == "dialogue" && latest_entity >= 0 && WORLD_ENTITIES[latest_entity].kind == "person"; latest_width := latest_portrait ? f32(375) : f32(445); used := dialogue_transcript_entry_height(latest, latest_width); if latest_portrait do used = max(used, 100)
	for start >
	    0 {candidate := dialogue_transcript_entry_height(&g.conversation_transcript[indices[start - 1]], 445); if used + candidate > 360 do break; start -= 1; used += candidate}
	// The transcript and response block share one bottom-anchored stack.
	y := dialogue_conversation_top_y(g, conversation_id)
	for position in start ..< end {entry := &g.conversation_transcript[indices[position]]; color := dialogue_semantic_color(entry.kind, {255, 218, 112, 255}, 1); speaker_entity := world_entity_index(entry.speaker); portrait := position == end - 1 && entry.kind == "dialogue" && speaker_entity >= 0 && WORLD_ENTITIES[speaker_entity].kind == "person"; if portrait {vk_dialogue_portrait(r, 646, y, WORLD_ENTITIES[speaker_entity]); line_y := vk_dialogue_ledger_line(r, 730, y, 375, dialogue_semantic_label(g, entry.speaker, entry.kind), dialogue_semantic_text(entry.text, entry.kind), color); y = max(line_y, y + 100)} else do y = vk_dialogue_ledger_line(r, 660, y, 445, dialogue_semantic_label(g, entry.speaker, entry.kind), dialogue_semantic_text(entry.text, entry.kind), color)}
	return true
}

dialogue_evidence_type :: proc(entity: World_Entity) -> string {
	switch entity.source_id {
	case "ledger":
		return "DOCUMENT"
	case "memo_stub", "burned_note":
		return "DOCUMENT FRAGMENT"
	case "shutter_crank":
		return "MECHANISM"
	case "dining_room":
		return "SCENE ARRANGEMENT"
	case "edgar_watch":
		return "TIMEPIECE"
	case "garden":
		return "SCENE TRACE"
	case "pond_reflection":
		return "REFLECTION"
	case:
		return "PHYSICAL OBJECT"
	}
}

dialogue_full_evidence_art :: proc(source_id: string) -> (UI_Art, bool) {
	switch source_id {
	case "statuette":
		return .Evidence_Statuette, true
	case "shutter_crank", "shutter_thread":
		return .Evidence_Silk, true
	case "edgar_watch":
		return .Evidence_Watch, true
	case "dining_room":
		return .Evidence_Place_Setting, true
	case "ledger":
		return .Evidence_Ledger, true
	case "memo_stub", "burned_note":
		return .Evidence_Ledger, true
	case "cloth":
		return .Evidence_Cloth, true
	}
	return {}, false
}

vk_dialogue_portrait :: proc(r: ^Vulkan_Backend, x, y: f32, entity: World_Entity) {
	vulkan_ui_rect(
		r,
		x,
		y,
		72,
		92,
		{15, 17, 20, 220},
	); vulkan_ui_outline(r, x, y, 72, 92, {139, 107, 55, 210}, 1)
	if entity.kind == "person" {
		// A generated dossier portrait anchors the speaker without obscuring the scene.
		vk_art_fit(r, portrait_art(entity.source_id), x + 3, y + 3, 66, 86)
		return
	}
	// Evidence gets its own archival card; never imply that an object is a person.
	vulkan_ui_rect(r, x + 3, y + 3, 66, 86, {25, 28, 32, 255})
	vulkan_ui_outline(r, x + 7, y + 7, 58, 78, {78, 68, 50, 230}, 1)
	vk_text(r, x + 13, y + 14, "EVIDENCE", {202, 166, 92, 255}, .42)
	vulkan_ui_rect(r, x + 13, y + 29, 46, 1, {139, 107, 55, 210})
	vk_text(r, x + 25, y + 34, "◇", {202, 166, 92, 255}, 1.55)
	vk_text(r, x + 14, y + 70, "CASE FILE", {190, 194, 198, 255}, .38)
}

vk_dialogue_footer_button :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	label: string,
	accent: [4]u8,
	enabled := true,
) {
	focused :=
		enabled &&
		vk_focused_button ==
			button_id(
				box,
			); surface := enabled ? (focused ? [4]u8{48, 53, 64, 250} : [4]u8{22, 26, 33, 242}) : [4]u8{19, 22, 28, 210}; edge := enabled ? (focused ? accent : [4]u8{106, 113, 126, 220}) : [4]u8{66, 72, 82, 180}; text_color := enabled ? (focused ? [4]u8{248, 247, 242, 255} : [4]u8{205, 207, 210, 255}) : [4]u8{116, 122, 133, 210}
	vulkan_ui_rect(r, box.x, box.y, box.w, box.h, surface)
	if enabled do vulkan_ui_rect(r, box.x, box.y, focused ? f32(7) : f32(3), box.h, accent)
	vulkan_ui_outline(r, box.x, box.y, box.w, box.h, edge, focused ? f32(2) : f32(1))
	if focused do vulkan_ui_triangle(r, {box.x - 11, box.y + box.h * .5}, {box.x - 2, box.y + box.h * .5 - 6}, {box.x - 2, box.y + box.h * .5 + 6}, accent)
	vk_text(r, box.x + 15, box.y + 7, strings.to_upper(label), text_color, .66)
}

vk_dialogue_end_choice :: proc(r: ^Vulkan_Backend, box: Rect) {
	focused := vk_focused_button == button_id(box)
	if focused do vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {38, 43, 52, 220})
	vulkan_ui_rect(
		r,
		box.x,
		box.y,
		box.w,
		1,
		focused ? [4]u8{255, 211, 92, 225} : [4]u8{112, 118, 128, 155},
	)
	if focused do vulkan_ui_rect(r, box.x, box.y, 3, box.h, {255, 211, 92, 235})
	vk_text(
		r,
		box.x + 15,
		box.y + 8,
		"END CONVERSATION",
		focused ? [4]u8{248, 247, 242, 255} : [4]u8{170, 176, 184, 255},
		.58,
	)
}

vk_dialogue_page_nav :: proc(
	r: ^Vulkan_Backend,
	prev, next: Rect,
	page, pages: int,
	y: f32,
	color: [4]u8 = {170, 176, 184, 255},
) {
	prev_active :=
		vk_focused_button == button_id(prev); next_active := vk_focused_button == button_id(next)
	if prev_active {vulkan_ui_rect(r, prev.x, prev.y, prev.w, prev.h, {38, 43, 52, 220}); vulkan_ui_outline(r, prev.x, prev.y, prev.w, prev.h, {255, 211, 92, 210}, 1)}
	if next_active {vulkan_ui_rect(r, next.x, next.y, next.w, next.h, {38, 43, 52, 220}); vulkan_ui_outline(r, next.x, next.y, next.w, next.h, {255, 211, 92, 210}, 1)}
	vulkan_ui_triangle(
		r,
		{prev.x + 18, prev.y + 5},
		{prev.x + 10, prev.y + 10},
		{prev.x + 18, prev.y + 15},
		prev_active ? [4]u8{255, 211, 92, 255} : color,
	)
	vulkan_ui_triangle(
		r,
		{next.x + 12, next.y + 5},
		{next.x + 20, next.y + 10},
		{next.x + 12, next.y + 15},
		next_active ? [4]u8{255, 211, 92, 255} : color,
	)
	label := fmt.tprintf(
		"%d OF %d",
		page + 1,
		pages,
	); vk_text(r, 1058 - f32(utf8_glyph_count(label)) * 3.1, y, label, color, .42)
}

dialogue_pointer_over_control :: proc(g: ^Game) -> bool {
	return dialogue_pointer_focus_id(g) != ui.GUI_ID_NONE
}
dialogue_control_focused :: proc(g: ^Game, box: Rect) -> bool {
	if dialogue_pointer_over_control(g) do return contains(box, g.input.mouse_pos)
	return g.gui.focused == button_id(box)
}

vk_draw_disposition :: proc(r: ^Vulkan_Backend, g: ^Game, index: int) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || index < 0 || index >= len(payload.characters) do return
	box := disposition_rect(

	); value := mystery_game_disposition(g, payload.characters[index].entity_id); hovered := g.active_device == .Keyboard_Mouse && contains(box, g.input.mouse_pos); color := value > 0 ? [4]u8{102, 205, 143, 255} : value < 0 ? [4]u8{255, 144, 119, 255} : [4]u8{170, 190, 205, 255}; state_label := value > 0 ? "RECEPTIVE" : value < 0 ? "GUARDED" : "NEUTRAL"
	if hovered {vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {42, 47, 57, 220}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {205, 207, 210, 190}, 1)}
	vulkan_ui_rect(
		r,
		box.x + 2,
		box.y + 11,
		4,
		4,
		color,
	); vk_text(r, box.x + 14, box.y + 7, dialogue_disposition_label(value), hovered ? color : [4]u8{190, 184, 181, 235}, .56)
	if !hovered do return
	tx, ty, tw, th :=
		f32(850),
		f32(98),
		f32(300),
		f32(
			96,
		); vk_panel(r, tx, ty, tw, th); vk_text(r, tx + 16, ty + 13, state_label, color, .9); _ = vk_text_wrapped(r, tx + 16, ty + 37, tw - 32, disposition_summary(g, index), {248, 247, 242, 255}, .68, 1); vk_text(r, tx + 16, ty + 76, fmt.tprintf("CHECK MODIFIER  %+d", clamp(value, -2, 2)), color, .64)
}

vk_draw_dialogue :: proc(r: ^Vulkan_Backend, g: ^Game) {
	// There is one dialogue component. Authored story beats contribute their
	// transcript and current actions to it just like interactive conversations.
	if g.story_presentation.active {vk_draw_story_dialogue(r, g); return}
	if g.pending_dialogue_approach >
	   0 {if node := mystery_dialogue_approach_at(mystery_game_payload(g), g.pending_dialogue_approach - 1); node != nil {texture := vulkan_dialogue_asset_texture(r, node.node_id); if texture >= 0 do vulkan_ui_quad(r, 650, 105, 490, 190, {255, 255, 255, 255}, texture, {}, {1, 1}, true)}}
	if g.dialogue_entity < 0 || g.dialogue_entity >= len(WORLD_ENTITIES) do return
	entity :=
		WORLD_ENTITIES[g.dialogue_entity]; clue_index := clue_for_source(g, entity.source_id); payload := mystery_game_payload(g)
	// One continuous conversation surface holds played beats, checks, available
	// responses, and the exit action in reading order.
	vulkan_ui_rect(r, 0, 0, 1200, 720, {0, 0, 0, 118})
	if evidence_art, has_evidence_art := dialogue_full_evidence_art(entity.source_id);
	   has_evidence_art {
		vulkan_ui_rect(
			r,
			38,
			88,
			548,
			544,
			{12, 14, 17, 238},
		); vulkan_ui_outline(r, 38, 88, 548, 544, {139, 107, 55, 220}, 2)
		vk_text(r, 62, 108, "CASE EVIDENCE  ·  PHYSICAL EXAMINATION", {202, 166, 92, 255}, .62)
		vulkan_ui_rect(r, 62, 137, 500, 1, {139, 107, 55, 180})
		vk_art_fit(r, evidence_art, 62, 154, 500, 402)
		vk_text(r, 62, 583, strings.to_upper(entity.name), {255, 218, 112, 255}, .86)
		vk_text(
			r,
			62,
			608,
			strings.to_upper(dialogue_evidence_type(entity)),
			{190, 194, 198, 255},
			.52,
		)
	}
	standard_conversation := entity.kind == "person"
	shell_x := f32(625); shell_w := standard_conversation ? f32(540) : f32(555)
	// Ordinary character dialogue is one tall transcript column. Evidence and
	// special-purpose interactions retain their dedicated identity treatment.
	if !standard_conversation {vulkan_ui_rect(r, 625, 26, 555, 120, {12, 14, 17, 232}); vulkan_ui_outline(r, 625, 26, 555, 120, {213, 184, 111, 205}, 1)}
	action_bottom := standard_conversation ? f32(694) : f32(642)
	if !standard_conversation &&
	   !g.check_from_dialogue &&
	   entity.kind ==
		   "person" {end_box := dialogue_end_rect_for(g); action_bottom = end_box.y + end_box.h + 12; if g.end_confirm do action_bottom = 642}
	body_top :=
		standard_conversation ? f32(26) : f32(198); vulkan_ui_rect(r, shell_x, body_top, shell_w, action_bottom - body_top, {12, 14, 17, 226}); vulkan_ui_outline(r, shell_x, body_top, shell_w, action_bottom - body_top, {105, 108, 112, 178}, 1)
	if entity.kind != "person" &&
	   !g.check_from_dialogue {vulkan_ui_rect(r, 625, 646, 555, 48, {12, 14, 17, 226}); vulkan_ui_outline(r, 625, 646, 555, 48, {105, 108, 112, 178}, 1)}
	if !standard_conversation {vk_text(r, 660, 45, entity.name, {255, 218, 112, 255}, 1.25); _ = vk_text_wrapped(r, 660, 75, 360, public_source_description(g, entity.source_id), {205, 207, 210, 255}, .68, 2)}
	// Rolls belong to the spoken line. This compact state keeps the character,
	// prior exchanges, odds, and consequence in one uninterrupted ledger.
	if payload != nil &&
	   g.check_from_dialogue &&
	   g.pending_clue >= 0 &&
	   g.pending_clue < len(payload.clues) {
		clue := &payload.clues[g.pending_clue]; check_heading := entity.kind == "person" ? "PRESS THE CONVERSATION" : "INVESTIGATIVE CHECK"; vk_text(r, 660, 218, check_heading, {255, 211, 92, 255}, .8); _ = vk_text_wrapped(r, 660, 246, 445, dialogue_check_prompt(g), {248, 247, 242, 255}, .9, 2)
		if !g.check_done {cancel_box := dialogue_check_cancel_rect(); vk_dialogue_footer_button(r, cancel_box, dialogue_check_cancel_label(g), {148, 155, 168, 255}); vk_prompt_icon(r, g, .Back, cancel_box.x + cancel_box.w - 27, cancel_box.y + 5, 20); helper, helper_line, color := skill_helper(clue.skill); modifier := check_modifier(skill_index(clue.skill), clue_evidence_bonus(g, g.pending_clue), clue_disposition(g, g.pending_clue), clue_situational_bonus(g, g.pending_clue)); cost := clue_action_cost(g, g.pending_clue); chance := check_success_percent(g.check_preview, modifier); vk_text(r, 660, 326, strings.to_upper(clue.skill), color, 1.18); _ = vk_text_wrapped(r, 660, 352, 445, helper_line, color, .68, 2); vulkan_ui_rect(r, 660, 407, 445, 1, {139, 107, 55, 170}); vk_draw_die_face(r, 660, 420, 31, 0); vk_draw_die_face(r, 699, 420, 31, 0); vk_text(r, 744, 430, fmt.tprintf("MOD %+d  ·  NEED %d+ TOTAL  ·  %d%% SUCCESS", modifier, g.check_preview, chance), {255, 211, 92, 255}, .64); vk_text(r, 660, 470, helper, {205, 207, 210, 255}, .62); vk_text(r, 660, 492, clue.check_kind == "red" ? "ONE-SHOT CHECK  ·  ONE ATTEMPT" : "RETRYABLE CHECK  ·  PAY PER ATTEMPT", clue.check_kind == "red" ? [4]u8{255, 144, 119, 255} : [4]u8{155, 201, 255, 255}, .64); vk_text(r, 660, 520, dialogue_check_cost_summary(g, g.pending_clue), cost > 0 ? [4]u8{255, 211, 92, 255} : [4]u8{102, 205, 143, 255}, .62); vk_button(r, {650, 590, 490, 42}, dialogue_check_commit_label(g, cost), true)} else {helper, helper_line, color := skill_helper(clue.skill); modifier := check_modifier(skill_index(clue.skill), clue_evidence_bonus(g, g.pending_clue), clue_disposition(g, g.pending_clue), clue_situational_bonus(g, g.pending_clue)); vk_text(r, 660, 326, strings.to_upper(clue.skill), color, 1.18); _ = vk_text_wrapped(r, 660, 352, 445, helper_line, color, .68, 2); vulkan_ui_rect(r, 660, 407, 445, 1, {139, 107, 55, 170}); vk_draw_die_face(r, 660, 420, 31, g.check_result.die_a); vk_draw_die_face(r, 699, 420, 31, g.check_result.die_b); vk_text(r, 744, 430, fmt.tprintf("%+d   ·   TARGET %d", modifier, g.check_preview), {255, 211, 92, 255}, .82); vk_text(r, 660, 470, helper, {205, 207, 210, 255}, .62); elapsed := max(0, g.animation_time - g.check_roll_started); settled := elapsed >= CHECK_REVEAL_DURATION; if !settled {vulkan_ui_rect(r, 0, 0, 1200, 720, {4, 6, 8, 158}); _ = vk_draw_check_roll(r, g, 300, 220, 600)} else {vulkan_ui_rect(r, 650, 407, 490, 150, {12, 14, 17, 255}); vulkan_ui_outline(r, 650, 407, 490, 150, {139, 107, 55, 170}, 1); status := g.check_result.success ? "THE CHECK SUCCEEDS." : "THE CHECK FAILS."; status_color := g.check_result.success ? [4]u8{102, 205, 143, 255} : [4]u8{255, 144, 119, 255}; vk_text(r, 670, 425, status, status_color, 1.05); vk_text(r, 670, 459, dialogue_check_roll_summary(g.check_result), {255, 211, 92, 255}, .62); vulkan_ui_rect(r, 670, 480, 450, 1, {106, 113, 126, 170}); _ = vk_text_wrapped(r, 670, 493, 450, g.check_result.success ? mystery_clue_proposition_text(g.story_project, clue) : dialogue_check_failure_text(g, clue.check_kind), {248, 247, 242, 255}, .72, 2); disposition_result := dialogue_check_disposition_result(g); if entity.kind == "person" && disposition_result != "" do vk_text(r, 670, 537, disposition_result, status_color, .56); continue_label := entity.kind == "person" ? "CONTINUE CONVERSATION" : "RETURN TO INVESTIGATION"; vk_button(r, {650, 590, 490, 42}, fmt.tprintf("[%s]  %s", dialogue_accept_prompt(g), continue_label), true)}}
		return
	}
	if world_entity_has_tag(&entity, "body_examination_dialogue") {
		vulkan_ui_rect(
			r,
			660,
			350,
			445,
			1,
			{139, 107, 55, 150},
		); vk_text(r, 660, 360, "EDGAR'S BODY", {255, 211, 92, 255}, .60)
		watch := dialogue_body_watch_clue(
			g,
		); if watch >= 0 && !mystery_game_clue_discovered(g, watch) && clue_available(g, watch) {watch_box := dialogue_body_watch_rect(g); vk_dialogue_choice_surface(r, watch_box, dialogue_control_focused(g, watch_box)); vk_text(r, watch_box.x + 18, watch_box.y + 18, "1.  Examine the crushed wristwatch", {248, 247, 242, 255}, .76)} else if watch >= 0 && mystery_game_clue_discovered(g, watch) {vk_text(r, 660, 522, "WRISTWATCH EXAMINED  ·  8:24", {102, 205, 143, 255}, .62)}
		leave_box := dialogue_object_leave_rect(

		); vk_dialogue_footer_button(r, leave_box, "Return to investigation", {148, 155, 168, 255}); vk_prompt_icon(r, g, .Back, leave_box.x + leave_box.w - 27, leave_box.y + 4, 20); return
	}
	if entity.kind == "person" {
		opening_y := dialogue_choices_start_y(g, entity.source_id) - 128
		vulkan_ui_rect(r, 660, opening_y - 18, 465, 1, {139, 107, 55, 190})
		completed_count := 0; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == entity.source_id && mystery_game_dialogue_completed(g, i) do completed_count += 1}
		case_note := dialogue_case_note_active(g, clue_index)
		if !case_note && vk_draw_character_transcript(r, g, entity.source_id) {
			// The persistent log owns player-facing history. Mystery dialogue
			// summaries remain state metadata and never substitute for played beats.
		} else if completed_count == 0 {
			if case_note {vk_text(r, 660, opening_y, "CASE NOTE", {119, 190, 213, 255}, .72); _ = vk_text_wrapped(r, 660, opening_y + 22, 445, g.dialogue_response, {248, 247, 242, 255}, .78)} else if g.dialogue_response != "" {fresh := g.animation_time - g.dialogue_text_started >= 0 && g.animation_time - g.dialogue_text_started < 1.25; vk_text(r, 660, opening_y - 2, fresh ? "OPENING STATEMENT  ·  JUST NOW" : "OPENING STATEMENT", fresh ? [4]u8{119, 190, 213, 255} : [4]u8{205, 207, 210, 255}, .52); vulkan_ui_rect(r, 650, opening_y + 20, 3, 82, {119, 190, 213, fresh ? u8(230) : u8(110)}); vk_text(r, 660, opening_y + 22, strings.to_upper(entity.name), {255, 218, 112, 255}, .70); _ = vk_text_wrapped(r, 674, opening_y + 42, 431, g.dialogue_response, {248, 247, 242, 255}, .78)} else {vk_text(r, 660, opening_y, "THE CONVERSATION BEGINS", {205, 207, 210, 255}, .72); _ = vk_text_wrapped(r, 660, opening_y + 22, 445, known_claim_text(g, entity.source_id), {248, 247, 242, 255}, .78)}
		} else {
			max_scroll :=
				case_note ? completed_count : max(0, completed_count - 1); if max_scroll > 0 {rail_hover := g.active_device == .Keyboard_Mouse && contains(dialogue_ledger_scroll_hit_rect(), g.input.mouse_pos); heading := case_note && g.dialogue_ledger_scroll == 0 ? "CASE NOTE" : g.dialogue_ledger_scroll == 0 ? "CONVERSATION  ·  NEWEST" : "CONVERSATION  ·  EARLIER"; heading_color := case_note && g.dialogue_ledger_scroll == 0 ? [4]u8{119, 190, 213, 255} : [4]u8{205, 207, 210, 255}; vk_text(r, 660, 48, heading, heading_color, .52); position := dialogue_history_position_label(g.dialogue_ledger_scroll, max_scroll); vk_text(r, 1098 - f32(utf8_glyph_count(position)) * 6, 48, position, {170, 176, 184, 255}, .52); thumb_y := dialogue_ledger_thumb_y(g.dialogue_ledger_scroll, max_scroll); vulkan_ui_rect(r, rail_hover ? f32(1149) : f32(1151), DIALOGUE_LEDGER_RAIL_Y, rail_hover ? f32(5) : f32(1), DIALOGUE_LEDGER_RAIL_H, rail_hover ? [4]u8{148, 155, 168, 210} : [4]u8{116, 91, 48, 180}); vulkan_ui_rect(r, rail_hover ? f32(1146) : f32(1148), thumb_y, rail_hover ? f32(11) : f32(7), DIALOGUE_LEDGER_THUMB_H, {255, 211, 92, rail_hover ? u8(255) : u8(220)})}
			if case_note &&
			   g.dialogue_ledger_scroll ==
				   0 {vulkan_ui_rect(r, 650, 238, 3, 86, {119, 190, 213, 230}); vk_text(r, 660, 240, "EVIDENCE PRESENTED", {119, 190, 213, 255}, .66); _ = vk_text_wrapped(r, 660, 268, 445, g.dialogue_response, {248, 247, 242, 255}, .78, 5)} else {
				completed_indices: [32]int; count := 0; for i in 0 ..< mystery_dialogue_approach_count(payload) {node := mystery_dialogue_approach_at(payload, i); if node.character_id == entity.source_id && mystery_game_dialogue_completed(g, i) && count < len(completed_indices) {completed_indices[count] = i; count += 1}}
				if max_scroll ==
				   0 {fresh := dialogue_exchange_fresh_visible(g, count - 1, count, clue_index); vk_text(r, 660, 48, fresh ? "CONVERSATION  ·  JUST NOW" : "CONVERSATION  ·  NEWEST", fresh ? [4]u8{119, 190, 213, 255} : [4]u8{205, 207, 210, 255}, .52)}
				ledger_scroll :=
					case_note ? g.dialogue_ledger_scroll - 1 : g.dialogue_ledger_scroll; y := dialogue_conversation_top_y(g, entity.source_id); end := clamp(count - ledger_scroll, 1, count); start := end - 1; used := dialogue_legacy_entry_layout_height(g, completed_indices[start]); for start > 0 && end - start < 3 {candidate := dialogue_legacy_entry_layout_height(g, completed_indices[start - 1]); if used + candidate > 379 do break; start -= 1; used += candidate}; for end < count && end - start < 3 {candidate := dialogue_legacy_entry_layout_height(g, completed_indices[end]); if used + candidate > 379 do break; used += candidate; end += 1}
				for position in start ..< end {i := completed_indices[position]; node := mystery_dialogue_approach_at(payload, i); if node == nil do continue; failed := mystery_game_dialogue_failed(g, i); if dialogue_exchange_fresh_visible(g, position, count, clue_index) {freshness := clamp(1 - (g.animation_time - g.dialogue_text_started) / 1.25, 0, 1); bar_h := min(dialogue_legacy_entry_layout_height(g, i) - 8, 449 - y); vulkan_ui_rect(r, 650, y, 3, bar_h, {119, 190, 213, u8(70 + int(freshness * 170))})}; y = vk_dialogue_ledger_line(r, 660, y, 445, "DETECTIVE  ·  SPOKEN", node.prompt, {119, 190, 213, 255}); if node.clue_id != "" {check_index := mystery_clue_index(payload, node.clue_id); if check_index >= 0 {clue := &payload.clues[check_index]; state := failed ? "FAILED" : "SUCCESS"; check_color := failed ? [4]u8{255, 144, 119, 255} : [4]u8{102, 205, 143, 255}; cost := clue_action_cost(g, check_index); y = vk_dialogue_ledger_line(r, 660, y, 445, fmt.tprintf("%s  ·  SKILL CHECK  ·  %s", strings.to_upper(clue.skill), state), fmt.tprintf("%s · %s", strings.to_lower(check_retry_label(clue.check_kind)), strings.to_lower(dialogue_tick_cost_label(cost))), check_color)}}}
			}
		}
		has_approach := dialogue_has_available_approach(
			g,
			entity.source_id,
		); evidence_available := dialogue_can_present_evidence(g, clue_index); evidence_just_presented := g.dialogue_node == 3 && clue_index >= 0 && mystery_game_evidence_presented(g, clue_index); failed_check := dialogue_failed_check_active(g, clue_index); retry_available := failed_check && clue_index >= 0 && clue_index < len(payload.clues) && payload.clues[clue_index].check_kind != "red" && clue_available(g, clue_index); section_label := evidence_just_presented ? "EVIDENCE PRESENTED  ·  +1 RELATED CHECKS" : retry_available ? "CHECK FAILED  ·  RETRY AVAILABLE" : failed_check && has_approach ? "CHECK CLOSED  ·  OTHER APPROACHES AVAILABLE" : has_approach ? "YOUR RESPONSE" : evidence_available ? "EVIDENCE AVAILABLE" : failed_check ? "CHECK CLOSED  ·  TRY ANOTHER APPROACH" : "CONVERSATION COMPLETE"; section_color := evidence_just_presented || failed_check ? [4]u8{119, 190, 213, 255} : has_approach ? [4]u8{205, 207, 210, 255} : evidence_available ? [4]u8{119, 190, 213, 255} : [4]u8{102, 205, 143, 255}; choices_y := dialogue_choices_start_y(g, entity.source_id); vk_text(r, 660, choices_y - 19, section_label, section_color, .60)
		tooltip := -1; tooltip_box := Rect{}; visible := dialogue_response_visible_count(g, entity.source_id, clue_index); view_bottom := dialogue_response_view_bottom(g, entity.source_id, clue_index); vulkan_ui_scissor(r, 650, choices_y, 490, max(0, view_bottom - choices_y)); for slot in 0 ..< visible {choice := dialogue_response_rect(g, entity.source_id, clue_index, slot); if choice.y >= view_bottom do break; index := dialogue_response_approach(g, entity.source_id, clue_index, slot); focused := dialogue_control_focused(g, choice); if index >= 0 {check := dialogue_check_clue_index(g, index) >= 0; vk_dialogue_approach_choice(r, g, choice, index, slot, focused); if check && focused {tooltip = index; tooltip_box = choice}} else if dialogue_response_is_evidence(g, entity.source_id, clue_index, slot) do vk_dialogue_evidence_choice(r, g, choice, clue_index, slot, focused)}; vulkan_ui_scissor_reset(r); response_total := dialogue_response_count(g, entity.source_id, clue_index); content_height := dialogue_response_content_height(g, entity.source_id, clue_index); if choices_y + content_height > DIALOGUE_RESPONSE_VIEW_BOTTOM {track_h := view_bottom - choices_y; thumb_h := max(f32(24), track_h / f32(response_total)); thumb_y := choices_y + (track_h - thumb_h) * f32(g.dialogue_choice_page) / f32(max(1, response_total - 1)); vulkan_ui_rect(r, 1136, choices_y, 2, track_h, {78, 82, 90, 150}); vulkan_ui_rect(r, 1134, thumb_y, 6, thumb_h, {255, 211, 92, 220})}
		if !has_approach {
			if failed_check && !evidence_available {
				vulkan_ui_rect(
					r,
					660,
					493,
					445,
					78,
					{35, 28, 25, 210},
				); vulkan_ui_outline(r, 660, 493, 445, 78, {208, 126, 91, 190}, 1); vk_text(r, 676, 505, "ANOTHER APPROACH NEEDED", {255, 144, 119, 255}, .58); vk_text(r, 676, 529, "This line of questioning is closed.", {248, 247, 242, 255}, .72); vk_text(r, 676, 551, "QUESTION ANOTHER ACCOUNT OR EXAMINE A RELATED OBJECT", {205, 176, 168, 255}, .52)
			} else if !evidence_available do _ = vk_text_wrapped(r, 674, 500, 415, "Every available line of inquiry with this person has been exhausted.", {170, 176, 184, 255}, .70, 2)
		}
		end_box := dialogue_end_rect_for(
			g,
		); vk_dialogue_end_choice(r, end_box); vk_prompt_icon(r, g, .Back, end_box.x + end_box.w - 27, end_box.y + 4, 20)
		if tooltip >= 0 do vk_draw_check_tooltip(r, g, tooltip, tooltip_box)
	} else {if world_entity_has_tag(
			&entity,
			"shutter_sightline_dialogue",
		) {vulkan_ui_rect(r, 660, 214, 445, 1, {139, 107, 55, 150})
			vk_text(
				r,
				660,
				224,
				g.shutter_sightline_failed ? "SIGHTLINE TEST COMPLETE" : "PHYSICAL SIGHTLINE TEST",
				g.shutter_sightline_failed ? [4]u8{102, 205, 143, 255} : [4]u8{205, 207, 210, 255},
				.68,
			)
			_ = vk_text_wrapped(
				r,
				660,
				254,
				445,
				g.dialogue_response != "" ? g.dialogue_response : "Operate the interior crank and test what remains visible from the dining room when the study shutter closes.",
				{248, 247, 242, 255},
				.76,
				5,
			)
			choice := Rect{650, 420, 490, 58}
			vk_dialogue_choice_surface(r, choice, dialogue_control_focused(g, choice))
			label :=
				g.shutter_demonstrating ? "WAIT FOR SHUTTER" : !g.shutter_sightline_failed ? "1.  Test the dining-room sightline" : g.shutter_target >= .5 ? "1.  Crank shutter closed" : "1.  Crank shutter open"
			vk_text(r, choice.x + 18, choice.y + 18, label, {248, 247, 242, 255}, .76)
			leave_box := dialogue_object_leave_rect()
			vk_dialogue_footer_button(
				r,
				leave_box,
				"Return to investigation",
				{148, 155, 168, 255},
			)
			vk_prompt_icon(
				r,
				g,
				.Back,
				leave_box.x + leave_box.w - 27,
				leave_box.y + 4,
				20,
			)} else if world_entity_has_tag(&entity, "reflection_dialogue") {vulkan_ui_rect(r, 660, 214, 445, 1, {139, 107, 55, 150})
			vk_text(r, 660, 224, "A QUIET MOMENT", {119, 190, 213, 255}, .68)
			_ = vk_text_wrapped(
				r,
				660,
				254,
				445,
				g.dialogue_response != "" ? g.dialogue_response : "Rain dimples the pond. Your reflection appears only in the intervals between drops.",
				{248, 247, 242, 255},
				.76,
				5,
			)
			choice := reflective_interaction_rect()
			vk_dialogue_choice_surface(r, choice, dialogue_control_focused(g, choice))
			vk_text(
				r,
				choice.x + 18,
				choice.y + 18,
				"1.  Contemplate your reflection",
				{248, 247, 242, 255},
				.76,
			)
			leave_box := dialogue_object_leave_rect()
			vk_dialogue_footer_button(
				r,
				leave_box,
				"Return to investigation",
				{148, 155, 168, 255},
			)
			vk_prompt_icon(
				r,
				g,
				.Back,
				leave_box.x + leave_box.w - 27,
				leave_box.y + 4,
				20,
			)} else if payload != nil && clue_index >= 0 {section_label := mystery_game_clue_discovered(g, clue_index) ? "EXAMINATION RESULT" : clue_available(g, clue_index) ? "AVAILABLE APPROACH" : "APPROACH UNAVAILABLE"
			vulkan_ui_rect(r, 660, 390, 445, 1, {139, 107, 55, 150})
			vk_text(r, 660, 398, section_label, {205, 207, 210, 255}, .60)
			choice :=
				clue_available(g, clue_index) ? dialogue_object_check_rect(g, clue_index) : Rect{650, 420, 490, 58}
			if mystery_game_clue_discovered(
				g,
				clue_index,
			) {result_box := choice; result_box.h = dialogue_object_result_height(g, clue_index)
				vk_dialogue_status_surface(r, result_box, {102, 205, 143, 210})
				vk_text(
					r,
					result_box.x + 18,
					result_box.y + 9,
					"EVIDENCE ACQUIRED",
					{102, 205, 143, 255},
					.78,
				)
				_ = vk_text_wrapped(
					r,
					result_box.x + 18,
					result_box.y + 31,
					result_box.w - 36,
					g.dialogue_response != "" ? g.dialogue_response : mystery_clue_proposition_text(g.story_project, &payload.clues[clue_index]),
					{248, 247, 242, 255},
					.64,
				)
				vk_text(
					r,
					result_box.x + 18,
					result_box.y + result_box.h - 17,
					"RECORDED IN NOTEBOOK  ·  AVAILABLE FOR THEORY",
					{157, 210, 176, 255},
					.52,
				)
				if world_entity_has_tag(
					&entity,
					"dining_walkthrough",
				) {walk := dining_walkthrough_rect()
					vk_dialogue_choice_surface(r, walk, dialogue_control_focused(g, walk))
					vk_text(
						r,
						walk.x + 18,
						walk.y + 15,
						"1.  Talk through the place settings",
						{248, 247, 242, 255},
						.74,
					)}} else if clue_available(g, clue_index) {focused := dialogue_control_focused(g, choice)
				vk_dialogue_object_check_choice(r, g, choice, clue_index, focused)
				if focused do vk_draw_check_tooltip_clue(r, g, clue_index, choice)} else {red := payload.clues[clue_index].check_kind == "red"; locked := clue_locked_label(g, clue_index)
				vk_dialogue_status_surface(
					r,
					choice,
					red ? [4]u8{150, 91, 78, 210} : [4]u8{98, 105, 118, 210},
				)
				vk_text(
					r,
					choice.x + 18,
					choice.y + 8,
					red ? "ONE-SHOT CHECK EXPIRED" : "APPROACH UNAVAILABLE",
					red ? [4]u8{255, 144, 119, 255} : [4]u8{170, 176, 184, 255},
					.68,
				)
				_ = vk_text_wrapped(
					r,
					choice.x + 18,
					choice.y + 32,
					choice.w - 36,
					locked,
					{205, 207, 210, 255},
					.58,
					2,
				)}}
		leave_box := dialogue_object_leave_rect()
		vk_dialogue_footer_button(r, leave_box, "Return to investigation", {148, 155, 168, 255})
		vk_prompt_icon(r, g, .Back, leave_box.x + leave_box.w - 27, leave_box.y + 4, 20)}
}

// Give the throw a readable dramatic shape: anticipation, tumble, result, release.
CHECK_LAUNCH_HOLD :: f32(.28)
CHECK_ROLL_DURATION :: f32(1.75)
CHECK_REVEAL_DURATION :: f32(2.65)
check_roll_ease :: proc(elapsed: f32) -> f32 {
	// Hold for the initial toss, then let the dice lose energy continuously.
	t := clamp((elapsed - CHECK_LAUNCH_HOLD) / (CHECK_ROLL_DURATION - CHECK_LAUNCH_HOLD), 0, 1)
	// The integrated trapezoid gives the tumble a fast middle and gentle settle.
	accel_time: f32 = .30; cruise_end: f32 = .70; max_speed := 1 / (cruise_end - accel_time + accel_time)
	if t < accel_time do return .5 * max_speed * t * t / accel_time
	accel_distance := .5 * max_speed * accel_time
	if t < cruise_end do return accel_distance + max_speed * (t - accel_time)
	brake_time := 1 - cruise_end; brake_elapsed := t - cruise_end
	return(
		accel_distance +
		max_speed * (cruise_end - accel_time) +
		max_speed * brake_elapsed -
		.5 * max_speed * brake_elapsed * brake_elapsed / brake_time \
	)
}

check_roll_animating :: proc(g: ^Game) -> bool {
	return(
		g != nil &&
		g.check_done &&
		g.animation_time - g.check_roll_started >= 0 &&
		g.animation_time - g.check_roll_started < CHECK_REVEAL_DURATION \
	)
}

update_check_result_cue :: proc(g: ^Game) {
	// Fire on the reveal, then leave the result on screen long enough to land.
	if g == nil || !g.check_done || g.check_result_cue_played || g.animation_time - g.check_roll_started < CHECK_ROLL_DURATION do return
	play_sound(g, g.check_result.success ? .Fact : .Reject); g.check_result_cue_played = true
}

vk_draw_die_pip :: proc(r: ^Vulkan_Backend, x, y, size: f32) {vulkan_ui_rect(
		r,
		x - size * .5,
		y - size * .5,
		size,
		size,
		{30, 32, 33, 255},
	)}
vk_draw_die_face :: proc(
	r: ^Vulkan_Backend,
	x, y, size: f32,
	value: int,
	tint: [4]u8 = {238, 232, 216, 255},
) {
	shadow: f32 = 5; vulkan_ui_rect(r, x + shadow, y + shadow, size, size, {0, 0, 0, 105}); vulkan_ui_rect(r, x, y, size, size, tint); vulkan_ui_outline(r, x, y, size, size, {24, 27, 29, 230}, 2)
	if value <=
	   0 {vk_text(r, x + size * .34, y + size * .18, "?", {34, 37, 39, 220}, size / 32); return}
	pip := max(
		f32(3),
		size * .12,
	); left, center, right := x + size * .24, x + size * .5, x + size * .76; top, middle, bottom := y + size * .24, y + size * .5, y + size * .76
	if value == 1 || value == 3 || value == 5 do vk_draw_die_pip(r, center, middle, pip)
	if value >= 2 {vk_draw_die_pip(r, left, top, pip); vk_draw_die_pip(r, right, bottom, pip)}
	if value >= 4 {vk_draw_die_pip(r, right, top, pip); vk_draw_die_pip(r, left, bottom, pip)}
	if value == 6 {vk_draw_die_pip(r, left, middle, pip); vk_draw_die_pip(r, right, middle, pip)}
}

vk_draw_check_roll :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	x: f32 = 230,
	y: f32 = 300,
	w: f32 = 740,
) -> bool {
	elapsed := max(0, g.animation_time - g.check_roll_started); ease := check_roll_ease(elapsed)
	// Resolution is one physical 2d6 throw; both faces settle to the values used
	// by the rules, and the modifier is applied only after they stop.
	shown_a :=
		elapsed >= CHECK_ROLL_DURATION ? g.check_result.die_a : 1 + (int(elapsed * 23) % 6); shown_b := elapsed >= CHECK_ROLL_DURATION ? g.check_result.die_b : 1 + (int(elapsed * 29 + 3) % 6)
	cx := x + w * .5; die_y := y + 8
	die_values := [2]int{shown_a, shown_b}
	for value, index in die_values {
		size: f32 = 66; jitter_x := f32(math.sin(f64(elapsed * 31 + f32(index) * 2.4))) * (1 - ease) * 18; lift := f32(math.sin(f64(elapsed * 17 + f32(index) * 2))) * (1 - ease) * 28; dx := cx - 76 + f32(index) * 86 + jitter_x
		vk_draw_die_face(
			r,
			dx,
			die_y + lift,
			size,
			value,
			index == 0 ? [4]u8{226, 218, 196, 255} : [4]u8{244, 238, 218, 255},
		)
	}
	if elapsed >=
	   CHECK_ROLL_DURATION {status := g.check_result.success ? "CHECK SUCCESS" : "CHECK FAILURE"; color := g.check_result.success ? [4]u8{102, 205, 143, 255} : [4]u8{255, 112, 91, 255}; vulkan_ui_rect(r, x + 60, y + 94, w - 120, 92, {10, 12, 14, 255}); vulkan_ui_outline(r, x + 60, y + 94, w - 120, 92, {139, 107, 55, 190}, 1); label_w := f32(utf8_glyph_count(status)) * f32(COURIER_CELL_WIDTH) * 1.08; vk_text(r, cx - label_w * .5, y + 105, status, color, 1.08); roll := fmt.tprintf("%d + %d  %+d  =  %d     TARGET  %d", g.check_result.die_a, g.check_result.die_b, g.check_result.modifier, g.check_result.total, g.check_result.target); roll_w := f32(utf8_glyph_count(roll)) * f32(COURIER_CELL_WIDTH) * .64; vk_text(r, cx - roll_w * .5, y + 151, roll, {205, 207, 210, 255}, .64)}
	return elapsed >= CHECK_REVEAL_DURATION
}

vk_draw_check :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if !g.check_done do vk_heading(r, "DETECTIVE CHECK", "")
	payload := mystery_game_payload(
		g,
	); if g.check_done {vk_panel(r, 120, 70, 960, 550)} else {vk_panel(r, 250, 130, 700, 450)}; if payload == nil || g.pending_clue < 0 || g.pending_clue >= len(payload.clues) do return; clue := &payload.clues[g.pending_clue]
	if g.check_done {
		_, helper_line, helper_color := skill_helper(
			clue.skill,
		); vk_text(r, 190, 116, strings.to_upper(clue.skill), helper_color, 1.65); _ = vk_text_wrapped(r, 190, 151, 820, helper_line, helper_color, .72, 2)
		elapsed := clamp(
			g.animation_time - g.check_roll_started,
			0,
			CHECK_REVEAL_DURATION,
		); fade_in := clamp(elapsed / .18, 0, 1); fade_out := clamp((CHECK_REVEAL_DURATION - elapsed) / .20, 0, 1); fade := min(fade_in, fade_out); if fade > 0 do vk_ui_spotlight(r, nil, u8(178 * fade), 0)
		settled := vk_draw_check_roll(r, g); if !settled do return
		status :=
			g.check_result.success ? "SUCCESS — FACT ESTABLISHED" : clue.check_kind == "red" ? "FAILED — APPROACH CLOSED" : "FAILED — RETRY AVAILABLE"
		status_w :=
			f32(utf8_glyph_count(status)) *
			f32(COURIER_CELL_WIDTH) *
			1.05; vk_text(r, 600 - status_w * .5, 430, status, g.check_result.success ? [4]u8{102, 205, 143, 255} : [4]u8{208, 126, 91, 255}, 1.05); if g.check_result.success {_ = vk_text_wrapped(r, 300, 466, 600, mystery_clue_proposition_text(g.story_project, clue), {205, 232, 213, 255}, .64, 1)} else if clue.check_kind != "red" {_ = vk_text_wrapped(r, 300, 466, 600, "You may spend another tick to try again.", {205, 207, 210, 255}, .68, 1)}; vk_button(r, {430, 500, 340, 50}, g.check_from_dialogue ? "RETURN TO CONVERSATION" : "RETURN TO INVESTIGATION"); return
	}
	helper, helper_line, helper_color := skill_helper(clue.skill)
	vk_draw_helper_badge(r, 285, 165, clue.skill, helper_color)
	vk_text(
		r,
		430,
		175,
		strings.to_upper(clue.skill),
		helper_color,
		2,
	); vk_text(r, 430, 215, helper, {205, 207, 210, 255}, .85); _ = vk_text_wrapped(r, 430, 240, 450, helper_line, helper_color, .8); vk_text(r, 335, 290, fmt.tprintf("[ROLL]  %s", strings.to_upper(clue.description))); modifier := check_modifier(skill_index(clue.skill), clue_evidence_bonus(g, g.pending_clue), clue_disposition(g, g.pending_clue), clue_situational_bonus(g, g.pending_clue)); vk_text(r, 470, 326, fmt.tprintf("2D6  %+d  /  NEED %d+", modifier, g.check_preview), {248, 247, 242, 255}, 1.2)
	vk_text(
		r,
		390,
		400,
		"ROLL TWO SIX-SIDED DICE. ADD THE MODIFIER. MEET THE TARGET.",
		{205, 207, 210, 255},
		.68,
	)
	cost := clue_action_cost(
		g,
		g.pending_clue,
	); vk_button(r, {430, 510, 340, 58}, cost == 0 ? "ROLL DICE  [OVERTIME — FREE]" : fmt.tprintf("ROLL DICE  [-%d TICK%s]", cost, cost == 1 ? "" : "S"), true)
}
