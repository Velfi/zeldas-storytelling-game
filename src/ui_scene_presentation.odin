package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

scene_transition_is_story_screen :: proc(screen: Screen) -> bool {
	#partial switch screen {
	case .Introduction,
	     .Loading,
	     .Exterior,
	     .Investigate,
	     .Dialogue,
	     .Check,
	     .Board,
	     .Challenge,
	     .Recreate,
	     .Reveal_Prep,
	     .Reveal,
	     .Result,
	     .Game_Over:
		return true
	}
	return false
}

map_loading_index :: proc(screen: Screen) -> int {if screen == .Exterior do return 0; if screen == .Investigate do return 1
	return -1}

map_loading_required :: proc(g: ^Game, from, to: Screen) -> bool {
	if from == .Loading do return false
	index := map_loading_index(to)
	return index >= 0 && !g.map_ready[index] && (from != .Dialogue && from != .Check)
}

map_loading_begin :: proc(g: ^Game, target: Screen) {
	g.map_loading_active = true; g.map_loading_target = target; g.map_loading_progress = 0
	g.map_loading_elapsed = 0; g.map_loading_stage = 0; g.screen = .Loading
}

map_loading_update :: proc(g: ^Game, dt: f32) {
	if !g.map_loading_active do return
	g.map_loading_elapsed += dt
	if g.case_loading_active {
		state := sync.atomic_load_explicit(&case_load_work.state, .Acquire)
		g.map_loading_stage = clamp(int(state) - 1, 0, 3)
		targets := [5]f32{0, .12, .38, .78, 1}; target := targets[clamp(int(state), 0, 4)]
		g.map_loading_progress += (target - g.map_loading_progress) * min(1, dt * 10)
		if state ==
		   6 {campaign_case_load_reap(); g.case_loading_active = false; g.map_loading_active = false; g.screen = .Campaign_Cases; campaign_workspace.feedback = case_load_work.result.message; return}
		if state == 5 && g.map_loading_progress >= .995 && g.map_loading_elapsed >= .25 {
			campaign_case_load_reap(); loaded := campaign_finish_prepared_case(g)
			if !loaded.ok {g.case_loading_active = false; g.map_loading_active = false; g.screen = .Campaign_Cases; campaign_workspace.feedback = loaded.message; return}
			destination :=
				g.screen; g.case_loading_active = false; g.map_loading_active = false; index := map_loading_index(destination); if index >= 0 do g.map_ready[index] = true; g.screen = destination
		}
		return
	}
	target_progress := clamp(g.map_loading_elapsed / .52, 0, 1)
	g.map_loading_progress += (target_progress - g.map_loading_progress) * min(1, dt * 14)
	if target_progress < .28 do g.map_loading_stage = 0
	else if target_progress < .62 do g.map_loading_stage = 1
	else if target_progress < 1 do g.map_loading_stage = 2
	else {g.map_loading_stage = 3; g.map_loading_progress = 1; index := map_loading_index(g.map_loading_target); if index >= 0 do g.map_ready[index] = true; g.case_loading_active = false; g.map_loading_active = false; g.screen = g.map_loading_target}
}

vk_draw_map_loading :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {3, 5, 9, 255})
	vulkan_ui_rect(
		r,
		154,
		120,
		892,
		480,
		{13, 17, 25, 255},
	); vulkan_ui_outline(r, 154, 120, 892, 480, {72, 78, 89, 220}, 1)
	vulkan_ui_rect(
		r,
		154,
		120,
		8,
		480,
		{255, 211, 92, 255},
	); vulkan_ui_rect(r, 198, 178, 804, 2, {116, 91, 48, 220})
	vk_text(r, 198, 148, "STORYCORE  /  SCENE TRANSFER", {152, 196, 214, 255}, .58)
	destination :=
		g.case_loading_active ? strings.to_upper(g.case_loading_title) : g.map_loading_target == .Exterior ? "VALE CITY" : "CASE LOCATION"
	vk_text(
		r,
		198,
		225,
		g.case_loading_active ? "LOADING CASE" : "LOADING MAP",
		{248, 247, 242, 255},
		2.15,
	); vk_text(r, 200, 278, destination, {255, 211, 92, 255}, .82)
	stages := [4]string {
		"READING LOCATION",
		"PREPARING GEOMETRY",
		"PLACING EVIDENCE",
		"SCENE READY",
	}; stage := clamp(g.map_loading_stage, 0, len(stages) - 1); stage_label := stage == 0 && g.case_loading_active ? "READING CASE FILE" : stages[stage]
	vk_text(
		r,
		198,
		380,
		stage_label,
		stage == 3 ? [4]u8{117, 229, 169, 255} : [4]u8{205, 207, 210, 255},
		.66,
	)
	x, y, w, h :=
		f32(198), f32(425), f32(804), f32(22); progress := clamp(g.map_loading_progress, 0, 1)
	vulkan_ui_rect(
		r,
		x,
		y,
		w,
		h,
		{24, 29, 38, 255},
	); vulkan_ui_outline(r, x, y, w, h, {90, 89, 84, 255}, 1)
	if progress > 0 do vulkan_ui_rect(r, x + 3, y + 3, (w - 6) * progress, h - 6, {255, 211, 92, 255})
	vk_text(
		r,
		198,
		470,
		fmt.tprintf("%03d%%", int(progress * 100 + .5)),
		{248, 247, 242, 255},
		.72,
	); vk_text(r, 842, 532, "PLEASE STAND BY", {125, 132, 143, 255}, .52)
}

scene_transition_begin :: proc(g: ^Game, from, to: Screen) {
	if from == to || g.editor_mode != .None || (!scene_transition_is_story_screen(from) && to != .Loading) || !scene_transition_is_story_screen(to) do return
	// The theory board is a frequently opened utility screen, so present it
	// immediately in both directions instead of interrupting navigation.
	if from == .Board || to == .Board do return
	// Dialogue and checks retain the same physical scene; wiping those small UI
	// changes would make ordinary investigation feel sluggish.
	if (from == .Investigate || from == .Dialogue || from == .Check) && (to == .Investigate || to == .Dialogue || to == .Check) do return
	target := to
	if map_loading_required(g, from, to) {map_loading_begin(g, to); target = .Loading}
	g.scene_transition_style = Scene_Transition_Style(g.scene_transition_sequence % 5)
	g.scene_transition_sequence += 1
	g.scene_transition_elapsed = 0
	g.scene_transition_active = true
	g.scene_transition_target = target
	// A fade needs the outgoing image for its first half. The destination state
	// has already been prepared, so hold only its presentation until full black.
	if g.scene_transition_style == .Fade do g.screen = from
}

scene_transition_update :: proc(g: ^Game, dt: f32) {
	if !g.scene_transition_active do return
	g.scene_transition_elapsed += dt
	if g.scene_transition_style == .Fade && g.screen != g.scene_transition_target && g.scene_transition_elapsed >= SCENE_TRANSITION_DURATION * .5 do g.screen = g.scene_transition_target
	if g.scene_transition_elapsed >=
	   SCENE_TRANSITION_DURATION {g.scene_transition_elapsed = SCENE_TRANSITION_DURATION; g.scene_transition_active = false}
}

vk_draw_scene_transition :: proc(r: ^Vulkan_Backend, g: ^Game) {
	if !g.scene_transition_active do return
	t := clamp(
		g.scene_transition_elapsed / SCENE_TRANSITION_DURATION,
		0,
		1,
	); t = t * t * (3 - 2 * t)
	ink := [4]u8{3, 5, 9, 255}
	switch g.scene_transition_style {
	case .Horizontal:
		x := WINDOW_WIDTH * t; vulkan_ui_rect(r, x, 0, WINDOW_WIDTH - x, WINDOW_HEIGHT, ink)
	case .Vertical:
		y := WINDOW_HEIGHT * t; vulkan_ui_rect(r, 0, y, WINDOW_WIDTH, WINDOW_HEIGHT - y, ink)
	case .Diagonal:
		strips := 24; strip_h := f32(WINDOW_HEIGHT) / f32(strips)
		travel := f32(WINDOW_WIDTH) + f32(WINDOW_HEIGHT) * .48
		for i in 0 ..< strips {y := f32(i) * strip_h; edge := clamp(t * travel - y * .48, 0, WINDOW_WIDTH); vulkan_ui_rect(r, edge, y, WINDOW_WIDTH - edge, strip_h + 1, ink)}
	case .Iris:
		// A banded ellipse gives the classic expanding aperture without a
		// one-off shader or extra render target.
		bands := 32; band_h := WINDOW_HEIGHT / f32(bands); radius_x := WINDOW_WIDTH * .72 * t; radius_y := WINDOW_HEIGHT * .72 * t
		for i in 0 ..< bands {y := f32(i) * band_h; dy := math.abs((y + band_h * .5) - WINDOW_HEIGHT * .5); half: f32 = 0; if radius_y > 0 && dy < radius_y do half = radius_x * f32(math.sqrt(f64(max(0, 1 - dy * dy / (radius_y * radius_y))))); left := clamp(WINDOW_WIDTH * .5 - half, 0, WINDOW_WIDTH * .5); right := clamp(WINDOW_WIDTH * .5 + half, WINDOW_WIDTH * .5, WINDOW_WIDTH); vulkan_ui_rect(r, 0, y, left, band_h + 1, ink); vulkan_ui_rect(r, right, y, WINDOW_WIDTH - right, band_h + 1, ink)}
	case .Fade:
		alpha := u8(clamp(int((1 - math.abs(t * 2 - 1)) * 255), 0, 255))
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {ink[0], ink[1], ink[2], alpha})
	}
}

weather_hash :: proc(value: f32) -> f32 {scrambled :=
		f32(math.sin(f64(value * 12.9898 + 78.233))) * 43758.547
	return scrambled - f32(math.floor(f64(scrambled)))}

vk_draw_weather :: proc(r: ^Vulkan_Backend, g: ^Game) {
	strength: f32 = 0
	if g.screen == .Exterior do strength = 1
	if g.screen == .Investigate do strength = clamp(g.environment_blend, 0, 1)
	if strength <= .01 || g.editor_mode == .Build do return
	// Three depth layers move at different rates. Drops gather loosely into
	// passing curtains, while jittered angles and sparse gaps break any grid.
	for i in 0 ..< 96 {
		index := f32(i); depth := f32(i % 3) / 2
		seed := weather_hash(index + 4.7); vertical_seed := weather_hash(index * 2.31 + 19.4)
		cluster := f32(i % 9); cluster_center := weather_hash(cluster * 5.17 + 11.8) * WINDOW_WIDTH
		scatter := (weather_hash(index * 7.13 + 2.4) - .5) * (150 + depth * 310)
		independent_x := weather_hash(index * 3.91 + 44.2) * WINDOW_WIDTH
		x := cluster_center + scatter; x = x * .72 + independent_x * .28
		speed := 210 + depth * 330 + seed * 145
		y :=
			f32(
				math.mod(
					f64(vertical_seed * (WINDOW_HEIGHT + 140) + g.animation_time * speed),
					f64(WINDOW_HEIGHT + 140),
				),
			) -
			70
		gust := f32(math.sin(f64(g.animation_time * .72 + y * .004 + cluster * 1.7)))
		wind := .10 + depth * .10 + gust * .045 + (seed - .5) * .08
		x += g.animation_time * (18 + depth * 25) + gust * 24
		x = f32(math.mod(f64(x + WINDOW_WIDTH + 100), f64(WINDOW_WIDTH + 100))) - 50
		length := 5 + depth * 14 + seed * 13
		thickness := .7 + depth * .75 + seed * .35
		catch_light := weather_hash(index * 11.29 + 91.7) > .94 ? f32(25) : f32(0)
		alpha := u8(clamp(int((10 + depth * 24 + seed * 14 + catch_light) * strength), 0, 255))
		vk_editor_line(
			r,
			{x, y},
			{x + length * wind, y + length},
			{174, 211, 224, alpha},
			thickness,
		)
	}
}

// Production frame compositor. SDL remains the window/event provider only;
// every command below is recorded into the Vulkan command buffer.
draw_vulkan :: proc(r: ^Vulkan_Backend, g: ^Game) {
	draw_phase_started := time.tick_now()
	r.profile_draw_setup_ms = 0; r.profile_draw_refresh_ms = 0; r.profile_draw_world_build_ms = 0; r.profile_draw_weather_ms = 0; r.profile_draw_overlay_ms = 0
	if g.catalog_thumbnail_baking {
		state, _ := os.process_wait(g.catalog_thumbnail_process, 0)
		if state.exited {
			g.catalog_thumbnail_baking = false
			if state.success &&
			   state.exit_code ==
				   0 {count := vulkan_catalog_refresh_thumbnails(r); g.catalog_thumbnail_status = fmt.tprintf("%d PREVIEW%s UPDATED", count, count == 1 ? "" : "S")} else {g.catalog_thumbnail_status = "THUMBNAIL RENDER FAILED"}
		}
	}
	vk_focused_button = g.gui.focused
	vulkan_ui_begin(r)
	r.profile_draw_setup_ms =
		time.duration_seconds(time.tick_diff(draw_phase_started, time.tick_now())) * 1000
	draw_phase_started = time.tick_now()
	if generated_roof_gpu_revision !=
	   generated_roof_revision {for i in 0 ..< generated_roof_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_roof_meshes[i]); generated_roof_gpu_revision = generated_roof_revision}
	if generated_link_gpu_revision !=
	   generated_link_revision {for i in 0 ..< generated_link_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_link_meshes[i]); generated_link_gpu_revision = generated_link_revision}
	if generated_ground_gpu_revision !=
	   generated_ground_revision {for i in 0 ..< generated_terrain_count do if generated_terrain_dirty[i] {_ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_terrain_meshes[i]); generated_terrain_dirty[i] = false}; for i in 0 ..< generated_water_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_water_meshes[i]); for i in 0 ..< generated_path_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_path_meshes[i]); generated_ground_gpu_revision = generated_ground_revision}
	if generated_story_gpu_revision !=
	   generated_story_revision {for i in 0 ..< generated_foundation_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_foundation_meshes[i]); for i in 0 ..< generated_story_slab_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_story_slab_meshes[i]); for i in 0 ..< generated_story_wall_count do _ = vk_world_refresh_mesh(&r.world, &r.ctx, &generated_story_wall_meshes[i]); generated_story_gpu_revision = generated_story_revision}
	r.profile_draw_refresh_ms =
		time.duration_seconds(time.tick_diff(draw_phase_started, time.tick_now())) * 1000
	draw_phase_started = time.tick_now()
	vk_world_begin(
		&r.world,
	); if g.catalog_bake_index >= 0 {vk_world_build_catalog_thumbnail(&r.world, &r.ctx, g)} else if g.character_studio {vk_world_build_character_studio(&r.world, &r.ctx, g)} else {presentation := g.screen == .Pause ? g.pause_return : g.screen; exterior_dialogue := presentation == .Dialogue && dialogue_returns_to_exterior(g); if presentation == .Exterior || exterior_dialogue do vk_world_build_city(&r.world, &r.ctx, g); if presentation == .Investigate || presentation == .Dialogue && !exterior_dialogue && !g.story_presentation.interaction_active do vk_world_build_house(&r.world, &r.ctx, g); if presentation == .Dialogue && !exterior_dialogue && g.story_presentation.interaction_active do vk_world_build_dialogue_interaction(&r.world, &r.ctx, g)}
	r.profile_draw_world_build_ms =
		time.duration_seconds(time.tick_diff(draw_phase_started, time.tick_now())) * 1000
	if g.catalog_bake_index >= 0 do return
	if g.character_studio do return
	draw_phase_started = time.tick_now()
	vk_draw_weather(r, g)
	r.profile_draw_weather_ms =
		time.duration_seconds(time.tick_diff(draw_phase_started, time.tick_now())) * 1000
	draw_phase_started = time.tick_now()
	#partial switch g.screen {
	case .Theme_Knoll:
		vk_draw_theme_knoll(r, g)
	case .Theme_Knoll_Details:
		vk_draw_theme_knoll_details(r, g)
	case .Title:
		vk_art_cover(r, .Title, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 90})
		vulkan_ui_rect(r, 132, 48, 936, 624, {13, 17, 25, 218})
		vulkan_ui_outline(r, 132, 48, 936, 624, {255, 211, 92, 255}, 2)
		vulkan_ui_outline(r, 138, 54, 924, 612, {72, 78, 89, 220}, 1)
		vulkan_ui_rect(r, 156, 96, 888, 5, {255, 211, 92, 255})
		vk_text(r, 291, 132, "C H I C A G O   S T O R Y   S T U D I O", {255, 211, 92, 255}, 1.65)
		vk_text(r, 414, 217, "YOUR STORIES", {248, 247, 242, 255}, 2.55)
		vk_text(r, 390, 286, "ONE WORLD  •  MANY POSSIBILITIES", {205, 207, 210, 255}, .88)
		vk_button(r, {410, 400, 380, 48}, "STORY LIBRARY", true)
		vk_button(r, {410, 456, 380, 48}, "CONTINUE STORY")
		vk_button(r, {410, 512, 380, 48}, "OPTIONS")
		vk_button(r, {410, 568, 380, 48}, "QUIT")
		vk_text(r, 410, 632, "CORE READY  •  CONTENT COMBINES FREELY", {255, 211, 92, 255}, .62)
	case .Campaign:
		vk_art_cover(r, .Title, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 190})
		vk_panel(r, 82, 48, 1036, 624)
		vk_text(r, 120, 78, "STORY LIBRARY", {255, 211, 92, 255}, 1.75)
		vk_text(
			r,
			122,
			116,
			"Standalone stories and collections share one library.",
			{205, 207, 210, 255},
			.66,
		)
		vulkan_ui_rect(r, 120, 143, 116, 24, {44, 51, 61, 235})
		vulkan_ui_outline(r, 120, 143, 116, 24, {255, 211, 92, 220}, 1)
		vk_text(r, 135, 150, "ALL STORIES", {255, 211, 92, 255}, .44)
		vk_text(r, 256, 150, "ITEM TYPES:  COLLECTION  •  STANDALONE", {152, 196, 214, 255}, .44)
		viewport := campaign_browser_viewport()
		content_height := campaign_browser_content_height()
		vulkan_ui_scissor(r, viewport.x, viewport.y, viewport.w, viewport.h)
		for i in 0 ..< campaign_browser.count {item := campaign_browser.entries[i]; box := campaign_browser_card_rect(i)
			if box.y + box.h < viewport.y || box.y > viewport.y + viewport.h do continue
			y := box.y
			selected := i == campaign_browser.selected
			focused := vk_focused_button == campaign_browser_card_id(i)
			highlighted := selected || focused
			vulkan_ui_rect(
				r,
				box.x,
				box.y,
				box.w,
				box.h,
				highlighted ? [4]u8{28, 38, 49, 248} : [4]u8{17, 23, 31, 235},
			)
			_ = vk_campaign_hero_cover(
				r,
				i,
				122,
				y + 2,
				226,
				80,
				highlighted ? [4]u8{255, 255, 255, 255} : [4]u8{178, 184, 192, 255},
			)
			vulkan_ui_rect(
				r,
				348,
				y + 2,
				714,
				80,
				highlighted ? [4]u8{28, 38, 49, 232} : [4]u8{17, 23, 31, 220},
			)
			if focused do vulkan_ui_rect(r, box.x, box.y, 7, box.h, UI_ACCENT)
			vulkan_ui_outline(
				r,
				box.x,
				box.y,
				box.w,
				box.h,
				focused ? UI_ACCENT : selected ? [4]u8{255, 211, 92, 235} : [4]u8{72, 78, 89, 190},
				focused ? 4 : selected ? 2 : 1,
			)
			kind := item.kind == .Collection ? "COLLECTION" : "STANDALONE"
			count_label :=
				item.kind == .Collection ? fmt.tprintf("%d %s", item.story_count, item.story_count == 1 ? "STORY" : "STORIES") : "1 STORY"
			vk_text(
				r,
				374,
				y + 10,
				strings.to_upper(item.title),
				highlighted ? [4]u8{255, 211, 92, 255} : [4]u8{248, 247, 242, 255},
				.78,
			)
			vk_text(
				r,
				374,
				y + 35,
				fmt.tprintf("%s  •  %s", kind, count_label),
				{152, 196, 214, 255},
				.46,
			)
			vk_text(r, 374, y + 55, item.description, {190, 195, 202, 255}, .45)
			badge_w := max(
				f32(128),
				f32(utf8_glyph_count(item.requirements)) * COURIER_CELL_WIDTH * .43 + 24,
			)
			vulkan_ui_rect(r, 1038 - badge_w, y + 45, badge_w, 24, {37, 43, 51, 245})
			vulkan_ui_outline(r, 1038 - badge_w, y + 45, badge_w, 24, {139, 107, 55, 210}, 1)
			vk_text(r, 1050 - badge_w, y + 52, item.requirements, {255, 211, 92, 255}, .42)
			vk_text(r, 902, y + 10, item.creator, {152, 196, 214, 255}, .42)}
		vulkan_ui_scissor_reset(r)
		max_scroll := max(content_height - viewport.h, 0)
		if max_scroll >
		   0 {rail_x := viewport.x + viewport.w - 8; thumb_h := max(48, viewport.h * viewport.h / content_height)
			thumb_y := viewport.y + (viewport.h - thumb_h) * campaign_browser.scroll / max_scroll
			vulkan_ui_rect(r, rail_x, viewport.y, 3, viewport.h, {116, 122, 136, 180})
			vulkan_ui_rect(r, rail_x - 4, thumb_y, 11, thumb_h, {255, 211, 92, 230})}
		vk_button(r, {120, 610, 180, 52}, "OPTIONS")
		vk_button(r, {310, 610, 150, 52}, "QUIT")
		if campaign_browser.feedback != "" do vk_text(r, 720, 578, campaign_browser.feedback, {152, 196, 214, 255}, .48)
	case .Campaign_Action:
		if campaign_workspace.open {vk_draw_campaign_workspace(r, g); break}
		if !vk_campaign_hero_cover(r, campaign_browser.selected, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT) do vk_art_cover(r, .Title, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT); vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 155}); vk_panel(r, 250, 72, 700, 576)
		vk_text(
			r,
			310,
			112,
			campaign_document.title,
			{255, 211, 92, 255},
			1.8,
		); vk_text(r, 312, 158, campaign_document.description, {205, 207, 210, 255}, .68); vk_text(r, 312, 205, fmt.tprintf("%d CASE%s  •  %d COMPLETE", len(campaign_document.cases), len(campaign_document.cases) == 1 ? "" : "S", campaign_playthrough.completion_count), {152, 196, 214, 255}, .60)
		vk_button(
			r,
			{410, 286, 380, 52},
			campaign_can_continue() ? "NEW INVESTIGATION" : "BEGIN NEW INVESTIGATION",
			true,
		); if campaign_can_continue() do vk_button(r, {410, 354, 380, 52}, fmt.tprintf("CONTINUE  ·  %s", strings.to_upper(campaign_document.cases[campaign_playthrough.active_case].title)))
		else {vulkan_ui_rect(r, 410, 354, 380, 52, {38, 42, 48, 225}); vulkan_ui_outline(r, 410, 354, 380, 52, {82, 88, 98, 180}, 1); vk_text(r, 476, 372, "CONTINUE  ·  NO ACTIVE CASE", {132, 138, 146, 255}, .57)}; vk_text(r, 410, 418, "CREATOR TOOLS", {152, 196, 214, 255}, .52); if !player_package_mode do vk_button(r, {410, 438, 380, 42}, "EDIT CAMPAIGN"); vk_button(r, {410, 488, 380, 42}, player_package_mode ? "CREATE EDITABLE COPY / AUTHORING" : "STORY AUTHORING"); vk_button(r, {410, 570, 380, 48}, "CHOOSE ANOTHER CAMPAIGN")
	case .Authoring:
		vk_draw_authoring_workspace(r, g)
	case .Campaign_Cases:
		vk_art_cover(r, .Title, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 190})
		vk_panel(r, 82, 48, 1036, 624)
		vk_text(r, 120, 82, "CHOOSE A CASE", {255, 211, 92, 255}, 1.75)
		vk_text(r, 122, 126, campaign_document.title, {205, 207, 210, 255}, .78)
		case_first := campaign_case_page * 4
		case_last := min(case_first + 4, len(campaign_document.cases))
		for i in case_first ..< case_last {item := campaign_document.cases[i]; box := campaign_case_card_rect(i - case_first)
			y := box.y
			unlocked := campaign_case_unlocked(&campaign_document, &campaign_playthrough, i)
			selected := campaign_playthrough.active_case == i
			focused := unlocked && vk_focused_button == button_id(box)
			highlighted := selected || focused
			vulkan_ui_rect(
				r,
				box.x,
				box.y,
				box.w,
				box.h,
				highlighted ? [4]u8{28, 38, 49, 248} : unlocked ? [4]u8{22, 30, 39, 240} : [4]u8{16, 20, 26, 225},
			)
			if focused do vulkan_ui_rect(r, box.x, box.y, 7, box.h, UI_ACCENT)
			vulkan_ui_outline(
				r,
				box.x,
				box.y,
				box.w,
				box.h,
				focused ? UI_ACCENT : selected ? [4]u8{255, 211, 92, 235} : unlocked ? [4]u8{139, 107, 55, 200} : [4]u8{64, 70, 78, 180},
				focused ? 4 : selected ? 2 : 1,
			)
			vk_text(
				r,
				148,
				y + 17,
				fmt.tprintf("CASE %d  ·  %s", i + 1, strings.to_upper(item.title)),
				unlocked ? [4]u8{248, 247, 242, 255} : [4]u8{128, 132, 138, 255},
				.88,
			)
			vk_text(
				r,
				900,
				y + 20,
				unlocked ? "AVAILABLE" : "LOCKED",
				unlocked ? [4]u8{255, 211, 92, 255} : [4]u8{128, 132, 138, 255},
				.58,
			)
			vk_text(
				r,
				148,
				y + 48,
				item.required ? "REQUIRED CASE" : "OPTIONAL CASE",
				{152, 196, 214, 255},
				.52,
			)}
		case_pages := max((len(campaign_document.cases) + 3) / 4, 1)
		if case_pages >
		   1 {vk_button(r, {500, 558, 48, 34}, "‹"); vk_text(r, 566, 568, fmt.tprintf("%d / %d", campaign_case_page + 1, case_pages), {205, 207, 210, 255}, .54)
			vk_button(r, {650, 558, 48, 34}, "›")}
		vk_button(r, {130, 610, 220, 52}, "BACK")
		if campaign_playthrough.active_case >= 0 do vk_button(r, {760, 610, 310, 52}, "START NEW CASE", true)
		else {vulkan_ui_rect(r, 760, 610, 310, 52, {38, 42, 48, 225}); vulkan_ui_outline(r, 760, 610, 310, 52, {82, 88, 98, 180}, 1); vk_text(r, 821, 628, "CHOOSE A CASE TO START", {132, 138, 146, 255}, .55)}
		if campaign_workspace.feedback !=
		   "" {vulkan_ui_rect(r, 354, 548, 492, 46, {48, 25, 24, 245}); vulkan_ui_outline(r, 354, 548, 492, 46, {255, 211, 92, 230}, 2); vk_text(r, 378, 563, campaign_workspace.feedback, {248, 247, 242, 255}, .62)}
	case .Options:
		vk_art_cover(r, .Title, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT)
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 8, 14, 165})
		vk_panel(r, 250, 60, 700, 620)
		vk_heading(r, "OPTIONS", "Audio, video, and controls")
		vk_text(r, 410, 115, "AUDIO", {255, 211, 92, 255}, .82)
		vk_button(r, {410, 145, 380, 48}, g.mute ? "MUTED" : "ON", true)
		vk_text(r, 410, 215, "ANTI-ALIASING", {255, 211, 92, 255}, .82)
		vk_button(r, {410, 245, 380, 48}, anti_aliasing_label(g.aa_mode), true)
		vk_text(r, 410, 315, "LIGHTING QUALITY", {255, 211, 92, 255}, .82)
		vk_button(r, {410, 345, 380, 48}, lighting_quality_label(g.lighting_quality), true)
		vk_text(r, 410, 415, "GUIDANCE", {255, 211, 92, 255}, .82)
		vk_button(r, {410, 445, 380, 48}, guidance_mode_label(g.guidance_mode), true)
		vk_text(
			r,
			410,
			501,
			"Changes control prompts only. Room hints stay neutral.",
			{205, 207, 210, 255},
			.50,
		)
		if g.aa_restart_required do vk_text(r, 442, 548, "ANTI-ALIASING SAVED — APPLIES NEXT LAUNCH", {205, 207, 210, 255}, .58)
		options_hint := fmt.tprintf(
			"%s NAVIGATE  •  %s SELECT",
			prompt_label(g, .Navigate),
			prompt_label(g, .Accept),
		)
		hint_width := f32(utf8_glyph_count(options_hint)) * f32(COURIER_CELL_WIDTH) * .66
		vk_text(r, (WINDOW_WIDTH - hint_width) * .5, 602, options_hint, {205, 207, 210, 255}, .66)
		vk_button(r, {410, 630, 380, 42}, "BACK", true)
	case .Pause:
		vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {2, 4, 7, 180})
		vk_panel(r, 320, 74, 560, 580)
		vk_text(r, 503, 108, "GAME PAUSED", {255, 211, 92, 255}, 1.35)
		vk_text(r, 443, 154, "THE STORY WAITS FOR YOU", {205, 207, 210, 255}, .60)
		load_available :=
			pause_snapshot_available &&
			(pause_snapshot_content_identity == 0 ||
					g.story_runtime != nil &&
						g.story_runtime.compiled.content_identity ==
							pause_snapshot_content_identity)
		vk_button(r, {410, 210, 380, 48}, "RESUME", true)
		vk_button(r, {410, 266, 380, 48}, "SAVE GAME")
		vk_button(r, {410, 322, 380, 48}, load_available ? "LOAD GAME" : "LOAD GAME  ·  EMPTY")
		vk_button(r, {410, 378, 380, 48}, "OPTIONS")
		vk_button(r, {410, 434, 380, 48}, "MAIN MENU")
		vk_button(r, {410, 490, 380, 48}, "QUIT")
		if g.pause_feedback != "" do vk_text(r, 522, 564, g.pause_feedback, g.pause_feedback == "GAME SAVED" ? [4]u8{152, 196, 214, 255} : [4]u8{255, 211, 92, 255}, .58)
	case .Introduction:
		vk_draw_introduction(r, g)
	case .Loading:
		vk_draw_map_loading(r, g)
	case .Exterior:
		vk_draw_city_overlay(r, g)
	case .Investigate, .Dialogue:
		if g.screen == .Investigate && !g.story_presentation.active do vk_draw_house_overlay(r, g)
		if g.screen == .Dialogue do vk_draw_dialogue(r, g)
		if graph_state.playtesting {vk_draw_graph_debugger(r, g); vk_button(r, graph_debugger_editor_rect(), g.editor_mode == .Graph ? "GAME" : "EDITOR", g.editor_mode == .Graph)}
	case .Attributes:
		vk_draw_attributes(r, g)
	case .Notebook:
		vk_draw_notebook(r, g)
	case .Check:
		vk_draw_check(r, g)
	case .Board:
		if g.board_view == 0 do vk_draw_workbench(r, g)
		else do vk_draw_event_chain(r, g)
	case .Challenge:
		vk_draw_challenge(r, g)
	case .Recreate:
		if g.workbench_event_count > 0 do vk_draw_event_chain_test(r, g)
		else do vk_draw_workbench_recreate(r, g)
	case .Reveal_Prep:
		vk_draw_reveal_prep(r, g)
	case .Reveal:
		vk_draw_reveal(r, g)
	case .Result:
		vk_draw_result(r, g)
	case .Game_Over:
		vk_draw_game_over(r, g)
	case .Diagnostics:
		vk_draw_diagnostics(r, g)
	}
	if g.screen != .Loading && g.active_device == .Keyboard_Mouse && !check_roll_animating(g) do vulkan_ui_outline(r, g.input.mouse_pos.x - 5, g.input.mouse_pos.y - 5, 10, 10, {255, 218, 112, 255})
	vk_draw_quest_transition_overlay(r, g)
	vk_draw_scene_transition(r, g)
	if g.controller_disconnected {
		vulkan_ui_rect(
			r,
			0,
			0,
			WINDOW_WIDTH,
			WINDOW_HEIGHT,
			{2, 4, 7, 190},
		); vk_panel(r, 330, 252, 540, 216)
		vk_text(r, 416, 294, "CONTROLLER DISCONNECTED", {255, 211, 92, 255}, 1.05)
		vk_text(r, 421, 350, "GAMEPLAY IS PAUSED", {248, 247, 242, 255}, .78)
		vk_text(
			r,
			370,
			395,
			"Reconnect and use it, or press a keyboard or mouse button.",
			{205, 207, 210, 255},
			.48,
		)
	}
	r.profile_draw_overlay_ms =
		time.duration_seconds(time.tick_diff(draw_phase_started, time.tick_now())) * 1000
}
