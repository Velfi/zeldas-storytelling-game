package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import ui "zelda_engine:ui"

system_courier_path :: proc() -> string {
	when ODIN_OS == .Darwin {
		candidates := [?]string {
			"/System/Library/Fonts/SFNSMono.ttf",
			"/System/Library/Fonts/Courier.ttc",
			"/System/Library/Fonts/Supplemental/Courier New.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string{"C:/Windows/Fonts/cour.ttf", "C:/Windows/Fonts/couri.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else {
		// Common Courier-compatible system faces provided by fontconfig packages.
		candidates := [?]string {
			"/usr/share/fonts/opentype/urw-base35/NimbusMonoPS-Regular.otf",
			"/usr/share/fonts/truetype/liberation2/LiberationMono-Regular.ttf",
			"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
			"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	}
	return ""
}

system_ui_font_path :: proc() -> string {
	if path, ok := story_ui_font_path(&active_story_project, &authoring_workspace.assets); ok && os.is_file(path) do return path
	when ODIN_OS == .Darwin {
		candidates := [?]string {
			"/System/Library/Fonts/SFNS.ttf",
			"/System/Library/Fonts/Helvetica.ttc",
		}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string{"C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"}
		for path in candidates do if os.is_file(path) do return path
	} else {
		candidates := [?]string {
			"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
			"/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	}
	return system_courier_path()
}

system_symbol_path :: proc() -> string {
	when ODIN_OS == .Darwin {
		candidates := [?]string {
			"/System/Library/Fonts/Apple Symbols.ttf",
			"/System/Library/Fonts/SFNSMono.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	} else when ODIN_OS == .Windows {
		candidates := [?]string {
			"C:/Windows/Fonts/seguisym.ttf",
			"C:/Windows/Fonts/seguisymbol.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	} else {
		candidates := [?]string {
			"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
			"/usr/share/fonts/truetype/noto/NotoSansSymbols2-Regular.ttf",
		}
		for path in candidates do if os.is_file(path) do return path
	}
	return system_courier_path()
}

skill_helper :: proc(skill: string) -> (name, line: string, color: [4]u8) {
	switch skill {
	case "Observation":
		return "MAGPIE", "Something small is asking to be noticed.", {155, 201, 255, 255}
	case "Analysis":
		return "OWL", "Two facts can share a board without agreeing.", {176, 145, 218, 255}
	case "Empathy":
		return "HOUND", "Listen for what the answer is protecting.", {102, 205, 143, 255}
	case "Pressure":
		return "LION", "Give the silence somewhere dramatic to land.", {255, 144, 119, 255}
	}
	return "INSTINCT", "There is a useful question here.", {255, 211, 92, 255}
}

vk_draw_helper_badge :: proc(r: ^Vulkan_Backend, x, y: f32, skill: string, color: [4]u8) {
	vulkan_ui_rect(
		r,
		x,
		y,
		105,
		105,
		{34, 38, 43, 255},
	); vulkan_ui_outline(r, x, y, 105, 105, color, 3)
	switch skill {
	case "Observation":
		vulkan_ui_rect(r, x + 28, y + 29, 42, 45, color)
		vulkan_ui_rect(r, x + 70, y + 43, 22, 10, {255, 211, 92, 255})
		vulkan_ui_rect(r, x + 57, y + 39, 7, 7, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 20, y + 20, 18, 18, color)
	case "Analysis":
		vulkan_ui_rect(r, x + 25, y + 29, 55, 50, color)
		vulkan_ui_rect(r, x + 16, y + 18, 26, 26, color)
		vulkan_ui_rect(r, x + 63, y + 18, 26, 26, color)
		vulkan_ui_rect(r, x + 34, y + 43, 10, 10, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 61, y + 43, 10, 10, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 49, y + 60, 8, 12, {255, 211, 92, 255})
	case "Empathy":
		vulkan_ui_rect(r, x + 27, y + 31, 51, 49, color)
		vulkan_ui_rect(r, x + 14, y + 23, 20, 48, color)
		vulkan_ui_rect(r, x + 71, y + 23, 20, 48, color)
		vulkan_ui_rect(r, x + 48, y + 55, 10, 9, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 37, y + 43, 6, 6, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 63, y + 43, 6, 6, {20, 22, 25, 255})
	case "Pressure":
		vulkan_ui_rect(r, x + 17, y + 17, 71, 71, color)
		vulkan_ui_rect(r, x + 29, y + 29, 47, 47, {94, 58, 43, 255})
		vulkan_ui_rect(r, x + 38, y + 44, 7, 7, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 61, y + 44, 7, 7, {20, 22, 25, 255})
		vulkan_ui_rect(r, x + 47, y + 62, 12, 4, {255, 211, 92, 255})
	}
}

character_stage_direction :: proc(g: ^Game, id: string) -> string {
	if id == "miriam" {
		if topic_unlocked(g, "appointment_contradiction") do return "The rejoined note remains crooked before her. For once, she does not look toward Daniel."
		if topic_unlocked(g, "appointment_denial") do return "She denies Edgar sent for her before you mention the time written on his memo stub."
		if g.threshold_eight_spent do return "She keeps her hands folded beneath the table and watches every new piece of evidence."
		return "Composed, she supplies more detail than the question requires."
	}
	if id == "daniel" {
		if topic_unlocked(g, "affair_admitted") do return "Relief softens him once the affair is separated from Edgar's death."
		if claim_known(g, "claim_daniel_alibi") do return "He looks to Miriam before committing himself to her account."
		if g.threshold_four_spent do return "He worries a thumbnail against his watch chain."
	}
	if id == "elsie" {
		if topic_unlocked(g, "theft_explained") do return "She stops straightening the table and finally meets your eyes."
		if topic_unlocked(g, "miriam_sighting") do return "The fear drains from her voice when the theft is named separately."
		if g.threshold_eight_spent do return "A folded banknote protrudes from the cash box she is trying to put back."
		return "She aligns a crooked frame while insisting she never entered the study."
	}
	return "The room waits for the next question."
}
// Shared UI theme. Keep the palette semantic: screens should choose a role
// (ink, muted, accent, danger) instead of inventing another near-identical
// blue-black or brass. This also gives creator and player tools one visual
// language while preserving their distinct blue/gold accents.
UI_INK := [4]u8{232, 224, 207, 255}
UI_INK_STRONG := [4]u8{250, 242, 220, 255}
// Secondary copy still needs to survive presentation scaling and dark rooms.
// Keep it quieter than body ink through hue, not insufficient luminance.
UI_MUTED := [4]u8{210, 205, 192, 255}
UI_MUTED_DIM := [4]u8{190, 187, 177, 255}
UI_CANVAS := [4]u8{3, 4, 5, 255}
UI_SURFACE := [4]u8{7, 8, 9, 250}
UI_SURFACE_RAISED := [4]u8{12, 13, 14, 252}
UI_SURFACE_HOVER := [4]u8{22, 23, 22, 255}
UI_BORDER := [4]u8{74, 68, 56, 230}
UI_BORDER_STRONG := [4]u8{128, 112, 82, 255}
UI_ACCENT := [4]u8{207, 162, 74, 255}
UI_ACCENT_SOFT := [4]u8{59, 43, 18, 255}
UI_ACCENT_DARK := [4]u8{104, 78, 36, 255}
UI_INFO := [4]u8{132, 161, 164, 255}
UI_SUCCESS := [4]u8{127, 166, 126, 255}
UI_WARNING := [4]u8{207, 162, 74, 255}
UI_DANGER := [4]u8{181, 83, 70, 255}
UI_SHADOW := [4]u8{0, 0, 0, 165}
UI_CONSOLE_CAPTION_SCALE :: f32(.76)
UI_CONSOLE_LABEL_SCALE :: f32(.82)
UI_CONSOLE_BODY_SCALE :: f32(.90)

ui_success_chance_color :: proc(chance: int) -> [4]u8 {
	if chance < 50 do return UI_DANGER
	if chance < 75 do return UI_WARNING
	return UI_SUCCESS
}

vk_text :: proc(r: ^Vulkan_Backend, x, y: f32, value: string, color := UI_INK, scale: f32 = 1.25) {
	vulkan_ui_text(r, r.font_texture, x, y, value, color, scale)
}
// Editor copy is often displayed over a detailed 3D scene and the window may
// be shorter than the 1200x720 logical canvas. Below this size the mono glyph
// stems collapse after presentation scaling, so compact editor labels must
// spend space on legibility rather than becoming miniature annotations.
EDITOR_MIN_TEXT_SCALE :: f32(.70)
vk_editor_text :: proc(
	r: ^Vulkan_Backend,
	x, y: f32,
	value: string,
	color := UI_INK,
	scale: f32 = .65,
) {
	vk_text(r, x, y, value, color, max(scale, EDITOR_MIN_TEXT_SCALE))
}
vk_editor_text_wrapped :: proc(
	r: ^Vulkan_Backend,
	x, y, max_width: f32,
	value: string,
	color := UI_INK,
	scale: f32 = .65,
	line_spacing: f32 = 1,
) -> f32 {
	return vk_text_wrapped(
		r,
		x,
		y,
		max_width,
		value,
		color,
		max(scale, EDITOR_MIN_TEXT_SCALE),
		line_spacing,
	)
}
vk_graph_ui_text :: proc(
	r: ^Vulkan_Backend,
	x, y: f32,
	value: string,
	color := UI_INK,
	scale: f32 = .65,
) {
	vulkan_ui_system_text(r, x, y, value, color, max(scale, EDITOR_MIN_TEXT_SCALE))
}
vk_art_fit :: proc(
	r: ^Vulkan_Backend,
	art: UI_Art,
	x, y, w, h: f32,
	tint := [4]u8{255, 255, 255, 255},
) {
	texture := vulkan_ui_art_texture(r, art); if texture < 0 || texture >= len(r.images) do return
	image :=
		r.images[texture]; source_aspect := f32(image.width) / f32(max(image.height, 1)); box_aspect := w / max(h, .001); dw, dh := w, h
	if source_aspect > box_aspect {dh = w / source_aspect} else {dw = h * source_aspect}
	vulkan_ui_quad(r, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh, tint, texture, {}, {1, 1}, true)
}
vk_art_cover :: proc(
	r: ^Vulkan_Backend,
	art: UI_Art,
	x, y, w, h: f32,
	tint := [4]u8{255, 255, 255, 255},
) {
	texture := vulkan_ui_art_texture(r, art); if texture < 0 || texture >= len(r.images) do return
	image :=
		r.images[texture]; source_aspect := f32(image.width) / f32(max(image.height, 1)); box_aspect := w / max(h, .001); uv0, uv1 := Vec2{}, Vec2{1, 1}
	if source_aspect >
	   box_aspect {visible := box_aspect / source_aspect; uv0.x = (1 - visible) / 2; uv1.x = 1 - uv0.x} else {visible := source_aspect / box_aspect; uv0.y = (1 - visible) / 2; uv1.y = 1 - uv0.y}
	vulkan_ui_quad(r, x, y, w, h, tint, texture, uv0, uv1, true)
}
vk_art_stretch :: proc(
	r: ^Vulkan_Backend,
	art: UI_Art,
	x, y, w, h: f32,
	tint := [4]u8{255, 255, 255, 255},
) {
	texture := vulkan_ui_art_texture(r, art); if texture < 0 || texture >= len(r.images) do return
	vulkan_ui_quad(r, x, y, w, h, tint, texture, {}, {1, 1}, true)
}

vk_campaign_hero_cover :: proc(
	r: ^Vulkan_Backend,
	index: int,
	x, y, w, h: f32,
	tint := [4]u8{255, 255, 255, 255},
) -> bool {
	if index < 0 || index >= len(r.campaign_textures) do return false; texture := r.campaign_textures[index]; if texture < 0 || texture >= len(r.images) do return false
	img :=
		r.images[texture]; source_aspect := f32(img.width) / f32(max(img.height, 1)); box_aspect := w / max(h, .001); uv0, uv1 := Vec2{}, Vec2{1, 1}; if source_aspect > box_aspect {visible := box_aspect / source_aspect; uv0.x = (1 - visible) / 2; uv1.x = 1 - uv0.x} else {visible := source_aspect / box_aspect; uv0.y = (1 - visible) / 2; uv1.y = 1 - uv0.y}; vulkan_ui_quad(r, x, y, w, h, tint, texture, uv0, uv1, true); return true
}

vk_prompt_icon :: proc(r: ^Vulkan_Backend, g: ^Game, kind: Prompt_Kind, x, y, size: f32) {
	art :=
		UI_Art.Prompt_Keyboard; sheet_w, sheet_h := f32(1088), f32(1024); cell_x, cell_y := f32(0), f32(0); mapped := false
	if g.active_device == .Keyboard_Mouse {
		#partial switch kind {case .Accept, .Interact:
			cell_x = 320; cell_y = 320; mapped = true; case .Board:
			cell_x = 192; cell_y = 192; mapped = true; case .Notebook:
			cell_x = 896; cell_y = 512; mapped = true; case .Back:
			cell_x = 832; cell_y = 320; mapped = true; case:}
	} else {
		switch gamepad_family(g.gamepad_type) {
		case 1:
			art = .Prompt_PlayStation; sheet_w = 768; sheet_h = 768
			#partial switch kind {case .Accept, .Interact:
				cell_x = 320; cell_y = 64; mapped = true; case .Board, .Attributes, .Handbrake:
				cell_x = 704; cell_y = 64; mapped = true; case .Notebook:
				cell_x = 64; cell_y = 128; mapped = true; case .Back:
				cell_x = 448; cell_y = 0; mapped = true; case:}
		case 2:
			art = .Prompt_Switch; sheet_w = 704; sheet_h = 704
			#partial switch kind {case .Accept, .Interact:
				cell_x = 384; cell_y = 0; mapped = true; case .Board, .Attributes, .Handbrake:
				cell_x = 256; cell_y = 128; mapped = true; case .Notebook:
				cell_x = 128; cell_y = 128; mapped = true; case .Back:
				cell_x = 256; cell_y = 0; mapped = true; case:}
		case:
			art = .Prompt_Xbox; sheet_w = 640; sheet_h = 640
			#partial switch kind {case .Accept, .Interact:
				cell_x = 256; cell_y = 0; mapped = true; case .Board, .Attributes, .Handbrake:
				cell_x = 0; cell_y = 192; mapped = true; case .Notebook:
				cell_x = 128; cell_y = 192; mapped = true; case .Back:
				cell_x = 384; cell_y = 0; mapped = true; case:}
		}
	}
	if !mapped {label := prompt_label(g, kind); width := max(size, f32(utf8_glyph_count(label)) * 6 + 14); vulkan_ui_rect(r, x, y, width, size, {38, 43, 52, 245}); vulkan_ui_outline(r, x, y, width, size, {205, 207, 210, 220}, 2); scale := min(f32(.46), (width - 8) / (max(f32(utf8_glyph_count(label)), 1) * f32(COURIER_CELL_WIDTH))); vk_text(r, x + 7, y + (size - f32(COURIER_CELL_HEIGHT) * scale) / 2, label, {248, 247, 242, 255}, scale); return}
	texture := vulkan_ui_art_texture(r, art); if texture < 0 do return
	// Kenney atlas XML uses a top-left origin; Vulkan samples these uploaded
	// sheets from the bottom-left.
	cell_y = sheet_h - cell_y - 64
	uv0 := Vec2 {
		cell_x / sheet_w,
		cell_y / sheet_h,
	}; uv1 := Vec2{(cell_x + 64) / sheet_w, (cell_y + 64) / sheet_h}
	vulkan_ui_quad(r, x, y, size, size, {255, 255, 255, 255}, texture, uv0, uv1, true)
}

vk_level_icon :: proc(
	r: ^Vulkan_Backend,
	row, column: int,
	x, y, size: f32,
	tint := [4]u8{255, 255, 255, 255},
) {texture := vulkan_ui_art_texture(r, .Level_Builder_Atlas); if texture < 0 do return; cell: f32 =
		1.0 / 8.0
	inset: f32 = .004
	uv0 := Vec2{f32(column) * cell + inset, f32(row) * cell + inset}
	uv1 := Vec2{f32(column + 1) * cell - inset, f32(row + 1) * cell - inset}
	vulkan_ui_quad(r, x, y, size, size, tint, texture, uv0, uv1, true)}
EDITOR_INK := UI_INK
EDITOR_MUTED := UI_MUTED
EDITOR_SURFACE := UI_SURFACE
EDITOR_SURFACE_STRONG := UI_SURFACE_RAISED
EDITOR_BORDER := UI_BORDER
EDITOR_BLUE := UI_INFO
EDITOR_BLUE_SOFT := [4]u8{37, 72, 86, 255}
editor_ui_mouse := Vec2{-1000, -1000}

vk_editor_surface :: proc(r: ^Vulkan_Backend, box: Rect, strong := false) {vulkan_ui_rect(
		r,
		box.x + 3,
		box.y + 5,
		box.w,
		box.h,
		{31, 38, 43, 70},
	)
	vulkan_ui_rect(r, box.x, box.y, box.w, box.h, strong ? EDITOR_SURFACE_STRONG : EDITOR_SURFACE)
	vulkan_ui_outline(r, box.x, box.y, box.w, box.h, EDITOR_BORDER, 1)}

vk_tab_bar_surface :: proc(r: ^Vulkan_Backend, box: Rect) {
	vulkan_ui_rect(r, box.x + 3, box.y + 5, box.w, box.h, UI_SHADOW)
	vulkan_ui_rect(r, box.x, box.y, box.w, box.h, UI_SURFACE)
	vulkan_ui_outline(r, box.x, box.y, box.w, box.h, UI_BORDER, 1)
	vulkan_ui_rect(r, box.x + 1, box.y + box.h - 4, box.w - 2, 3, UI_ACCENT_DARK)
}

vk_tab_surface :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	label: string,
	active, focused: bool,
	enabled := true,
) {
	draw_box := box
	if active {draw_box.y -= 4; draw_box.h += 5}
	fill := active ? UI_SURFACE_HOVER : focused ? UI_SURFACE_RAISED : UI_SURFACE
	text_color := active ? UI_INK_STRONG : focused ? UI_INK : UI_MUTED_DIM
	edge := UI_ACCENT_DARK
	if !enabled {fill = {10, 11, 12, 235}; text_color = {110, 108, 102, 220}; edge = UI_BORDER}
	vulkan_ui_rect(r, draw_box.x, draw_box.y, draw_box.w, draw_box.h, fill)
	vulkan_ui_rect(
		r,
		draw_box.x + draw_box.w - 1,
		draw_box.y + 8,
		1,
		max(0, draw_box.h - 16),
		edge,
	)
	if active {
		vulkan_ui_rect(r, draw_box.x, draw_box.y, draw_box.w, 3, UI_ACCENT)
		vulkan_ui_rect(
			r,
			draw_box.x,
			draw_box.y,
			2,
			draw_box.h,
			edge,
		); vulkan_ui_rect(r, draw_box.x + draw_box.w - 2, draw_box.y, 2, draw_box.h, edge)
		vulkan_ui_rect(r, draw_box.x + 2, draw_box.y + draw_box.h - 4, draw_box.w - 4, 4, fill)
	} else if focused {
		vulkan_ui_rect(
			r,
			draw_box.x + 12,
			draw_box.y + draw_box.h - 5,
			draw_box.w - 24,
			3,
			UI_ACCENT,
		)
	}
	glyphs := utf8_glyph_count(label); scale: f32 = 1.0
	if glyphs > 0 do scale = min(scale, max((box.w - 22) / (f32(glyphs) * COURIER_CELL_WIDTH), .72))
	width := f32(glyphs) * COURIER_CELL_WIDTH * scale
	vk_text(
		r,
		draw_box.x + (draw_box.w - width) * .5,
		draw_box.y + (draw_box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2,
		label,
		text_color,
		scale,
	)
}

vk_editor_pill :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	label: string,
	on := false,
	enabled := true,
) {
	hovered := enabled && contains(box, editor_ui_mouse)
	fill := on ? EDITOR_BLUE_SOFT : hovered ? [4]u8{48, 60, 70, 252} : EDITOR_SURFACE_STRONG
	border := on ? EDITOR_BLUE : hovered ? [4]u8{126, 151, 169, 255} : EDITOR_BORDER
	text_color := on ? [4]u8{221, 246, 252, 255} : hovered ? [4]u8{255, 255, 255, 255} : EDITOR_INK
	if !enabled {fill = {31, 37, 44, 235}; border = {62, 70, 79, 220}; text_color = {110, 120, 130, 220}}
	vulkan_ui_rect(
		r,
		box.x + 2,
		box.y + 3,
		box.w,
		box.h,
		{0, 0, 0, 80},
	); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, fill); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, border, on || hovered ? 2 : 1)
	if on {vulkan_ui_rect(r, box.x + 5, box.y + box.h - 4, box.w - 10, 3, EDITOR_INK); vulkan_ui_rect(r, box.x + 7, box.y + 7, 4, 4, EDITOR_INK)}
	scale :=
		EDITOR_MIN_TEXT_SCALE; glyphs := utf8_glyph_count(label); vk_editor_text(r, box.x + (box.w - f32(glyphs) * COURIER_CELL_WIDTH * scale) / 2, box.y + (box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2, label, text_color, scale)
}
vk_level_icon_button :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	row, column: int,
	on := false,
	enabled := true,
	hovered := false,
) {
	is_hovered := (hovered || contains(box, editor_ui_mouse)) && enabled
	background :=
		on ? EDITOR_BLUE_SOFT : is_hovered ? [4]u8{48, 60, 70, 252} : EDITOR_SURFACE_STRONG
	outline := on ? EDITOR_BLUE : is_hovered ? [4]u8{126, 151, 169, 255} : EDITOR_BORDER
	tint := on ? [4]u8{220, 246, 252, 255} : is_hovered ? [4]u8{255, 255, 255, 255} : EDITOR_INK
	if !enabled {background = {31, 37, 44, 235}; outline = {62, 70, 79, 220}; tint = {110, 120, 130, 170}}
	vulkan_ui_rect(
		r,
		box.x + 2,
		box.y + 3,
		box.w,
		box.h,
		{0, 0, 0, 80},
	); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, background); vk_level_icon(r, row, column, box.x + 5, box.y + 5, min(box.w, box.h) - 10, tint); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, outline, on || is_hovered ? 2 : 1)
}
vk_editor_cycle_button :: proc(r: ^Vulkan_Backend, box: Rect, direction: int, enabled := true) {
	hovered :=
		enabled &&
		contains(
			box,
			editor_ui_mouse,
		); fill := hovered ? EDITOR_BLUE_SOFT : enabled ? EDITOR_SURFACE_STRONG : [4]u8{31, 37, 44, 235}; border := hovered ? EDITOR_BLUE : enabled ? EDITOR_BORDER : [4]u8{62, 70, 79, 220}; c := enabled ? EDITOR_INK : [4]u8{110, 120, 130, 170}
	vulkan_ui_rect(
		r,
		box.x + 2,
		box.y + 3,
		box.w,
		box.h,
		{0, 0, 0, 80},
	); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, fill); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, border, hovered ? 2 : 1)
	center := Vec2{box.x + box.w * .5, box.y + box.h * .5}; half := min(box.w, box.h) * .18
	if direction < 0 do vulkan_ui_triangle(r, {center.x + half, center.y - half}, {center.x - half, center.y}, {center.x + half, center.y + half}, c)
	else do vulkan_ui_triangle(r, {center.x - half, center.y - half}, {center.x + half, center.y}, {center.x - half, center.y + half}, c)
}
Editor_Parameter_Icon :: enum {
	Height,
	Radius,
	Strength,
	Range,
	Intensity,
	Pitch,
	Overhang,
	Width,
	Rotate,
	Cone,
}
vk_editor_parameter_button :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	icon: Editor_Parameter_Icon,
	direction: int,
	mouse: Vec2,
	enabled := true,
) {
	hovered :=
		enabled &&
		contains(
			box,
			mouse,
		); fill := hovered ? EDITOR_BLUE_SOFT : enabled ? EDITOR_SURFACE_STRONG : [4]u8{31, 37, 44, 235}; border := hovered ? EDITOR_BLUE : enabled ? EDITOR_BORDER : [4]u8{62, 70, 79, 220}
	vulkan_ui_rect(
		r,
		box.x + 2,
		box.y + 3,
		box.w,
		box.h,
		{0, 0, 0, 80},
	); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, fill); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, border, hovered ? 2 : 1)
	c :=
		enabled ? EDITOR_INK : [4]u8{110, 120, 130, 170}; x := box.x + 8; y := box.y + 7; w := min(f32(15), box.w - 20); h := box.h - 14
	atlas_column := -1; #partial switch icon {case .Range:
		atlas_column = 3; case .Intensity:
		atlas_column = 4; case .Height:
		atlas_column = 5; case .Rotate:
		atlas_column = 6; case .Cone:
		atlas_column = 7}
	if atlas_column >=
	   0 {size := min(box.h - 8, box.w - 18); vk_level_icon(r, 0, atlas_column, box.x + 4, box.y + (box.h - size) * .5, size, enabled ? [4]u8{255, 255, 255, 255} : [4]u8{125, 132, 138, 170})} else {switch icon {
		case .Height:
			vulkan_ui_rect(r, x + w * .45, y, 2, h, c); vulkan_ui_rect(r, x + w * .2, y, 8, 2, c)
			vulkan_ui_rect(r, x + w * .2, y + h - 2, 8, 2, c)
		case .Radius:
			center := Vec2{x + w * .5, y + h * .5}; radius := min(w, h) * .42
			for i in 0 ..< 16 {a := f32(i) * f32(math.PI * 2) / 16; b := f32(i + 1) * f32(math.PI * 2) / 16
				vk_editor_line(
					r,
					{
						center.x + f32(math.cos(f64(a))) * radius,
						center.y + f32(math.sin(f64(a))) * radius,
					},
					{
						center.x + f32(math.cos(f64(b))) * radius,
						center.y + f32(math.sin(f64(b))) * radius,
					},
					c,
					1,
				)}
			vk_editor_line(r, center, {center.x + radius, center.y}, c, 2)
		case .Strength:
			for i in 0 ..< 3 do vulkan_ui_rect(r, x + f32(i) * 5, y + h - f32(i + 1) * 4, 3, f32(i + 1) * 4, c)
		case .Range:
			center := Vec2{x + 2, y + h * .5}
			for ring in 1 ..= 2 {radius := f32(ring) * 4; for i in -3 ..= 3 {a := f32(i) * f32(math.PI) / 7; b := f32(i + 1) * f32(math.PI) / 7; vk_editor_line(r, {center.x + f32(math.cos(f64(a))) * radius, center.y + f32(math.sin(f64(a))) * radius}, {center.x + f32(math.cos(f64(b))) * radius, center.y + f32(math.sin(f64(b))) * radius}, c, 1)}}
		case .Intensity:
			vulkan_ui_rect(r, x + 5, y + 4, 7, 7, c); vulkan_ui_rect(r, x + 7, y, 2, 3, c)
			vulkan_ui_rect(r, x + 7, y + 12, 2, 3, c)
			vulkan_ui_rect(r, x + 1, y + 6, 3, 2, c)
			vulkan_ui_rect(r, x + 13, y + 6, 3, 2, c)
		case .Pitch:
			vk_editor_line(r, {x, y + h - 2}, {x + w * .5, y + 1}, c, 2)
			vk_editor_line(r, {x + w * .5, y + 1}, {x + w, y + h - 2}, c, 2)
		case .Overhang:
			vk_editor_line(r, {x, y + 5}, {x + w * .5, y + 1}, c, 2)
			vk_editor_line(r, {x + w * .5, y + 1}, {x + w, y + 5}, c, 2)
			vulkan_ui_rect(r, x + 3, y + 7, w - 6, 2, c)
			vulkan_ui_rect(r, x + 5, y + 9, 2, h - 9, c)
			vulkan_ui_rect(r, x + w - 7, y + 9, 2, h - 9, c)
		case .Width:
			vulkan_ui_rect(r, x, y + h * .5, w, 2, c)
			vulkan_ui_rect(r, x, y + h * .5 - 3, 2, 8, c)
			vulkan_ui_rect(r, x + w - 2, y + h * .5 - 3, 2, 8, c)
		case .Rotate:
			center := Vec2{x + w * .5, y + h * .5}; radius := min(w, h) * .42
			for i in 0 ..< 12 {a := f32(i) * f32(math.PI * 1.65) / 12 - f32(math.PI * .75); b := f32(i + 1) * f32(math.PI * 1.65) / 12 - f32(math.PI * .75)
				vk_editor_line(
					r,
					{
						center.x + f32(math.cos(f64(a))) * radius,
						center.y + f32(math.sin(f64(a))) * radius,
					},
					{
						center.x + f32(math.cos(f64(b))) * radius,
						center.y + f32(math.sin(f64(b))) * radius,
					},
					c,
					2,
				)}
			vulkan_ui_rect(r, x + w - 4, y + 1, 5, 3, c)
		case .Cone:
			vk_editor_line(r, {x, y + h * .5}, {x + w, y + 1}, c, 2)
			vk_editor_line(r, {x, y + h * .5}, {x + w, y + h - 1}, c, 2)
			vulkan_ui_rect(r, x, y + h * .5 - 1, 3, 3, c)
		}
	}
	delta :=
		direction < 0 ? "-" : "+"; delta_color := enabled ? (direction < 0 ? EDITOR_MUTED : [4]u8{117, 229, 169, 255}) : [4]u8{100, 108, 116, 150}; vk_editor_text(r, box.x + box.w - 12, box.y + box.h - 15, delta, delta_color, .52)
}
vk_editor_icon_tooltip :: proc(r: ^Vulkan_Backend, box: Rect, label: string, mouse: Vec2) {
	if !contains(box, mouse) do return
	width := f32(utf8_glyph_count(label)) * 7 + 16
	x := clamp(box.x, f32(74), f32(418) - width)
	vk_editor_surface(r, {x, 102, width, 24}, true)
	vk_editor_text(r, x + 8, 108, label, EDITOR_INK, .36)
}
vk_catalog_thumbnail :: proc(
	r: ^Vulkan_Backend,
	entry: Catalog_Entry,
	box: Rect,
) {if entry.kind == .Object &&
	   entry.thumbnail_index >= 0 &&
	   entry.thumbnail_index < len(r.catalog_textures) {texture :=
			r.catalog_textures[entry.thumbnail_index]
		if texture >= 0 do vulkan_ui_quad(r, box.x + 3, box.y + 3, box.w - 6, 48, {255, 255, 255, 255}, texture, {}, {1, 1}, true)}
	else if entry.kind == .Material &&
	   entry.catalog_index >= 0 &&
	   entry.catalog_index < len(r.catalog_floor_textures) {half := (box.w - 6) * .5
		floor_texture, wall_texture :=
			r.catalog_floor_textures[entry.catalog_index],
			r.catalog_wall_textures[entry.catalog_index]
		if floor_texture >= 0 do vulkan_ui_quad(r, box.x + 3, box.y + 3, half, 48, {255, 255, 255, 255}, floor_texture, {}, {1, 1}, true)
		if wall_texture >= 0 do vulkan_ui_quad(r, box.x + 3 + half, box.y + 3, half, 48, {255, 255, 255, 255}, wall_texture, {}, {1, 1}, true)}}

vk_draw_editor_catalog :: proc(r: ^Vulkan_Backend, g: ^Game) {
	catalog_clamp_page(
		&editor_state,
	); footer := editor_catalog_footer_y(); bottom := editor_catalog_panel_bottom(g.build_tool); vk_editor_surface(r, {74, 194, 284, bottom - 194}, true)
	categories := [4]string {
		"all",
		g.build_tool == .Plant ? "objects" : "materials",
		"recent",
		"pinned",
	}; vk_tab_bar_surface(r, {86, 198, 255, 36}); for category, i in categories {box := Rect{86 + f32(i) * 65, 202, 60, 28}; vk_tab_surface(r, box, category == "pinned" ? "PIN" : strings.to_upper(category), editor_state.catalog_category == category, contains(box, editor_ui_mouse))}
	search_text := catalog_search_text(
		&editor_state,
	); vk_editor_pill(r, editor_catalog_search_rect(), search_text == "" ? (editor_state.search_active ? "SEARCH  |" : "SEARCH  [ / ]") : fmt.tprintf("SEARCH  %s%s", strings.to_upper(search_text), editor_state.search_active ? "|" : ""), editor_state.search_active); vk_editor_pill(r, editor_catalog_search_clear_rect(), "X", search_text != "")
	if editor_state.search_active &&
	   search_text != "" &&
	   catalog_match_count(&editor_state) >
		   0 {vk_panel(r, 370, 238, 214, 30); vk_editor_text(r, 382, 247, "ENTER SELECTS FIRST RESULT", {117, 229, 169, 255}, .60)}
	catalog_clamp_page(
		&editor_state,
	); shown, matched := 0, 0; start := editor_state.catalog_page * 9
	for entry in editor_catalog.entries {
		if !catalog_entry_matches(entry, &editor_state) do continue
		if matched >= start &&
		   shown <
			   9 {box := editor_catalog_card_rect(shown); on := entry.id == editor_state.catalog_id; vulkan_ui_rect(r, box.x, box.y, box.w, box.h, on ? [4]u8{67, 130, 151, 255} : [4]u8{238, 235, 221, 245}); vk_catalog_thumbnail(r, entry, box); vulkan_ui_rect(r, box.x + 3, box.y + 49, box.w - 6, 18, {15, 20, 25, 245}); card_ok := entry.valid && !entry.thumbnail_missing && !entry.thumbnail_stale; outline := card_ok ? [4]u8{160, 165, 155, 255} : entry.thumbnail_stale ? [4]u8{255, 211, 92, 255} : [4]u8{255, 144, 119, 255}; vulkan_ui_outline(r, box.x, box.y, box.w, box.h, on ? [4]u8{107, 206, 235, 255} : outline, on ? 3 : 1); if entry.thumbnail_missing do vk_editor_text(r, box.x + box.w - 14, box.y + 6, "!", {255, 144, 119, 255}, .60); if entry.thumbnail_stale do vk_editor_text(r, box.x + box.w - 17, box.y + 6, "R", {255, 211, 92, 255}, .48); pinned := catalog_is_pinned(&editor_state, entry.id); pin := editor_catalog_pin_rect(shown); vulkan_ui_rect(r, pin.x, pin.y, pin.w, pin.h, pinned ? [4]u8{255, 218, 112, 245} : [4]u8{20, 28, 34, 220}); vulkan_ui_outline(r, pin.x, pin.y, pin.w, pin.h, pinned ? [4]u8{255, 245, 190, 255} : [4]u8{205, 207, 210, 220}, 1); vk_editor_text(r, pin.x + 5, pin.y + 1, "*", pinned ? [4]u8{20, 28, 34, 255} : [4]u8{255, 218, 112, 255}, .66); vk_editor_action_tooltip(r, pin, pinned ? "UNPIN FROM SESSION SHELF" : "PIN FOR THIS EDITING SESSION", g.input.mouse_pos); label := strings.to_upper(entry.id); if len(label) > 11 do label = label[:11]; vk_editor_text(r, box.x + 5, box.y + 52, label, entry.valid ? [4]u8{255, 255, 255, 255} : [4]u8{255, 144, 119, 255}, .60); if contains(box, g.input.mouse_pos) && !contains(pin, g.input.mouse_pos) {status := entry.valid ? (entry.thumbnail_missing ? "PREVIEW MISSING" : entry.thumbnail_stale ? "PREVIEW OUTDATED" : strings.to_upper(entry.category)) : "ASSET UNAVAILABLE"; status_color := entry.valid ? (entry.thumbnail_missing || entry.thumbnail_stale ? [4]u8{255, 211, 92, 255} : [4]u8{205, 207, 210, 255}) : [4]u8{255, 144, 119, 255}; detail_width := max(f32(150), f32(max(utf8_glyph_count(entry.id), utf8_glyph_count(status))) * 7 + 20); vk_panel(r, 370, box.y, detail_width, 42); vk_editor_text(r, 380, box.y + 6, strings.to_upper(entry.id), {255, 255, 255, 255}, .60); vk_editor_text(r, 380, box.y + 23, status, status_color, .52)}; shown += 1}
		matched += 1
	}
	if shown ==
	   0 {query := catalog_search_text(&editor_state); empty_label := query != "" ? "NO SEARCH RESULTS" : editor_state.catalog_category == "recent" ? "NO RECENT ASSETS" : editor_state.catalog_category == "pinned" ? "NO PINNED ASSETS" : "NO ASSETS AVAILABLE"; vk_editor_text(r, 98, 292, empty_label, query != "" ? [4]u8{255, 144, 119, 255} : [4]u8{205, 207, 210, 255}, .52); if query != "" do vk_button(r, editor_catalog_empty_action_rect(), "CLEAR SEARCH", true)}
	pages := catalog_page_count(
		&editor_state,
	); vk_editor_pill(r, {86, footer, 38, 30}, "<", false, editor_state.catalog_page > 0); vk_editor_pill(r, {132, footer, 168, 30}, fmt.tprintf("%d-%d OF %d", matched == 0 ? 0 : start + 1, min(start + shown, matched), matched)); vk_editor_pill(r, {308, footer, 38, 30}, ">", false, editor_state.catalog_page + 1 < pages)
	if g.build_tool ==
	   .Plant {actions_y := footer + 38; if g.catalog_thumbnail_baking {vk_button(r, {86, actions_y, 260, 30}, g.catalog_thumbnail_status, true)} else {vk_button(r, {86, actions_y, 126, 30}, "RENDER ITEM"); vk_button(r, {220, actions_y, 126, 30}, "UPDATE PREVIEWS")}}
}
portrait_art :: proc(id: string) -> UI_Art {switch id {case "miriam":
		return .Portrait_Miriam; case "daniel":
		return .Portrait_Daniel; case "elsie":
		return .Portrait_Elsie; case:
		return .Portrait_Edgar}}
mini_actor_art :: proc(id: string) -> UI_Art {switch id {case "miriam":
		return .Mini_Miriam; case "daniel":
		return .Mini_Daniel; case "elsie":
		return .Mini_Elsie; case:
		return .Mini_Edgar}}
vk_text_wrapped :: proc(
	r: ^Vulkan_Backend,
	x, y, max_width: f32,
	value: string,
	color := [4]u8{248, 247, 242, 255},
	scale: f32 = 1.25,
	line_spacing: f32 = 4,
) -> f32 {
	if value == "" do return y
	line_height :=
		f32(COURIER_CELL_HEIGHT) * scale +
		line_spacing; cursor_y := y; plan := text_layout_plan(value, text_layout_columns(max_width, f32(COURIER_CELL_WIDTH) * scale))
	for line in plan {vk_text(r, x, cursor_y, value[line.start:line.end], color, scale)
		cursor_y += line_height}
	return cursor_y
}
vk_panel :: proc(r: ^Vulkan_Backend, x, y, w, h: f32) {
	// Opaque, layered surfaces keep copy readable over both bright exterior shots
	// and the darker house. The inset highlight gives panels a console-card feel.
	vulkan_ui_rect(r, x + 6, y + 8, w, h, UI_SHADOW)
	vulkan_ui_rect(r, x, y, w, h, UI_SURFACE)
	texture := vulkan_ui_art_texture(
		r,
		.Theme_Materials,
	); if texture >= 0 do vulkan_ui_quad(r, x + 2, y + 2, w - 4, h - 4, {96, 91, 80, 68}, texture, {0, 0}, {.5, .5}, true)
	vulkan_ui_outline(r, x, y, w, h, UI_BORDER_STRONG, 1)
	// One pair of registration corners carries the case-board motif without
	// surrounding every content region in a second decorative frame.
	corner := f32(18); weight := f32(2); c := UI_ACCENT_DARK
	vulkan_ui_rect(r, x, y, corner, weight, c); vulkan_ui_rect(r, x, y, weight, corner, c)
	vulkan_ui_rect(
		r,
		x + w - corner,
		y + h - weight,
		corner,
		weight,
		c,
	); vulkan_ui_rect(r, x + w - weight, y + h - corner, weight, corner, c)
}

UI_SPOTLIGHT_MAX_FOCI :: 4
vk_ui_spotlight :: proc(
	r: ^Vulkan_Backend,
	focuses: []Rect,
	dim_alpha: u8 = 178,
	padding: f32 = 8,
	outline_color := [4]u8{255, 211, 92, 0},
) {
	// Split the screen at every focus edge and dim only cells outside all focus
	// rectangles. Existing widgets remain bright through the resulting holes,
	// so tutorials do not need a second rendering path for highlighted controls.
	count := min(
		len(focuses),
		UI_SPOTLIGHT_MAX_FOCI,
	); if count <= 0 {vulkan_ui_rect(r, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {5, 7, 11, dim_alpha}); return}
	expanded: [UI_SPOTLIGHT_MAX_FOCI]Rect; xs, ys: [UI_SPOTLIGHT_MAX_FOCI * 2 + 2]f32; xs[0] = 0; xs[1] = WINDOW_WIDTH; ys[0] = 0; ys[1] = WINDOW_HEIGHT; xn, yn := 2, 2
	for i in 0 ..< count {box := focuses[i]; left := clamp(box.x - padding, 0, WINDOW_WIDTH); top := clamp(box.y - padding, 0, WINDOW_HEIGHT); right := clamp(box.x + box.w + padding, 0, WINDOW_WIDTH); bottom := clamp(box.y + box.h + padding, 0, WINDOW_HEIGHT); expanded[i] = {left, top, right - left, bottom - top}; xs[xn] = left; xs[xn + 1] = right; ys[yn] = top; ys[yn + 1] = bottom; xn += 2; yn += 2}
	for i in 1 ..< xn {value := xs[i]; j := i; for j > 0 && xs[j - 1] > value {xs[j] = xs[j - 1]; j -= 1}; xs[j] = value}; for i in 1 ..< yn {value := ys[i]; j := i; for j > 0 && ys[j - 1] > value {ys[j] = ys[j - 1]; j -= 1}; ys[j] = value}
	for yi in 0 ..< yn -
		1 {for xi in 0 ..< xn - 1 {x0, x1, y0, y1 := xs[xi], xs[xi + 1], ys[yi], ys[yi + 1]; if x1 <= x0 || y1 <= y0 do continue; cx, cy := (x0 + x1) * .5, (y0 + y1) * .5; inside := false; for i in 0 ..< count {box := expanded[i]; if cx >= box.x && cx <= box.x + box.w && cy >= box.y && cy <= box.y + box.h do inside = true}; if !inside do vulkan_ui_rect(r, x0, y0, x1 - x0, y1 - y0, {5, 7, 11, dim_alpha})}}
	// Three chunky alpha steps soften the cutout without abandoning the game's
	// pixel-grid language or requiring a blur pass.
	for i in 0 ..< count {box := expanded[i]; for step in 0 ..< 3 {inset := f32(step) * 4; alpha := u8((3 - step) * 10); vulkan_ui_outline(r, box.x + inset, box.y + inset, max(0, box.w - inset * 2), max(0, box.h - inset * 2), {5, 7, 11, alpha}, 4)}}
	if outline_color[3] > 0 do for i in 0 ..< count {box := expanded[i]; vulkan_ui_outline(r, box.x, box.y, box.w, box.h, outline_color, 2)}
}

vk_focused_button: ui.Gui_Id

// Tabs share one recessed rail instead of reading as a row of unrelated
// action buttons. The active page rises slightly and opens into the content
// below; focus remains a separate gold cue for keyboard/gamepad navigation.
vk_tab_bar :: proc(r: ^Vulkan_Backend, box: Rect) {
	vk_tab_bar_surface(r, box)
}

vk_tab :: proc(r: ^Vulkan_Backend, box: Rect, label: string, active := false) {
	vk_tab_surface(r, box, label, active, vk_focused_button == button_id(box))
}

vk_button_surface :: proc(r: ^Vulkan_Backend, box: Rect, label: string, selected, primary: bool) {
	// Selection communicates persistent choice. Primary communicates action
	// hierarchy. Focus remains transient input location and is intentionally
	// independent from both.
	focused := vk_focused_button == button_id(box)
	is_previous := label == "<" || label == "‹"
	is_next := label == ">" || label == "›"
	vulkan_ui_rect(r, box.x + 4, box.y + 5, box.w, box.h, UI_SHADOW)
	color :=
		focused ? UI_SURFACE_HOVER : selected ? UI_ACCENT_SOFT : primary ? UI_ACCENT_SOFT : UI_SURFACE_RAISED; vulkan_ui_rect(r, box.x, box.y, box.w, box.h, color)
	if focused {rail_width := f32(9); vulkan_ui_rect(r, is_next ? box.x + box.w - rail_width : box.x, box.y, rail_width, box.h, UI_ACCENT)}
	vulkan_ui_outline(
		r,
		box.x,
		box.y,
		box.w,
		box.h,
		focused ? UI_ACCENT : primary ? UI_ACCENT_DARK : UI_BORDER_STRONG,
		focused ? f32(4) : primary ? f32(2) : f32(1),
	)
	// Selection gets its own shape marker; focus remains the heavy gold rail.
	if selected &&
	   !focused {vulkan_ui_rect(r, box.x + 11, box.y + box.h * .5 - 3, 6, 6, UI_INK_STRONG); vulkan_ui_rect(r, box.x + box.w - 5, box.y + 5, 3, box.h - 10, UI_ACCENT)}
	if is_previous ||
	   is_next {center := Vec2{box.x + box.w * .5, box.y + box.h * .5}; half := min(box.w, box.h) * .18; if is_previous do vulkan_ui_triangle(r, {center.x + half, center.y - half}, {center.x - half, center.y}, {center.x + half, center.y + half}, {248, 247, 242, 255})
		else do vulkan_ui_triangle(r, {center.x - half, center.y - half}, {center.x + half, center.y}, {center.x - half, center.y + half}, {248, 247, 242, 255}); return}
	text_inset :=
		selected && !focused ? f32(30) : f32(16); right_inset := selected && !focused ? f32(14) : f32(16)
	scale: f32 = 1.3; glyphs := utf8_glyph_count(label); if glyphs > 0 do scale = min(scale, max((box.w - text_inset - right_inset) / (f32(glyphs) * COURIER_CELL_WIDTH), .72)); vk_text(r, box.x + text_inset, box.y + (box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2, label, selected || primary || focused ? UI_INK_STRONG : UI_INK, scale)
}

// Use selected only when the control represents the current persistent choice
// (tab, mode, toggle, chosen item). Action hierarchy belongs here instead.
vk_button :: proc(r: ^Vulkan_Backend, box: Rect, label: string, selected := false) {
	vk_button_surface(r, box, label, selected, false)
}

vk_primary_button :: proc(r: ^Vulkan_Backend, box: Rect, label: string, primary := true) {
	vk_button_surface(r, box, label, false, primary)
}

vk_danger_button :: proc(r: ^Vulkan_Backend, box: Rect, label: string) {
	focused := vk_focused_button == button_id(box)
	vulkan_ui_rect(r, box.x + 4, box.y + 5, box.w, box.h, UI_SHADOW)
	vulkan_ui_rect(r, box.x, box.y, box.w, box.h, focused ? UI_SURFACE_HOVER : UI_SURFACE_RAISED)
	vulkan_ui_outline(r, box.x, box.y, box.w, box.h, UI_DANGER, focused ? f32(4) : f32(2))
	if focused do vulkan_ui_rect(r, box.x, box.y, 9, box.h, UI_DANGER)
	scale: f32 = 1.3; glyphs := utf8_glyph_count(label); if glyphs > 0 do scale = min(scale, max((box.w - 32) / (f32(glyphs) * COURIER_CELL_WIDTH), .72))
	vk_text(
		r,
		box.x + 16,
		box.y + (box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2,
		label,
		UI_DANGER,
		scale,
	)
}
vk_graph_button :: proc(r: ^Vulkan_Backend, box: Rect, label: string, on := false) {
	focused :=
		vk_focused_button ==
		button_id(box); vulkan_ui_rect(r, box.x + 4, box.y + 5, box.w, box.h, UI_SHADOW)
	color :=
		focused ? UI_SURFACE_HOVER : on ? UI_ACCENT_SOFT : UI_SURFACE_RAISED; vulkan_ui_rect(r, box.x, box.y, box.w, box.h, color)
	if focused do vulkan_ui_rect(r, box.x, box.y, 9, box.h, UI_ACCENT)
	vulkan_ui_outline(
		r,
		box.x,
		box.y,
		box.w,
		box.h,
		focused ? UI_ACCENT : UI_BORDER_STRONG,
		focused ? f32(4) : f32(1),
	)
	if on &&
	   !focused {vulkan_ui_rect(r, box.x + 11, box.y + box.h * .5 - 3, 6, 6, UI_INK_STRONG); vulkan_ui_rect(r, box.x + box.w - 5, box.y + 5, 3, box.h - 10, UI_ACCENT)}
	text_inset :=
		on && !focused ? f32(30) : f32(16); right_inset := on && !focused ? f32(14) : f32(16); scale: f32 = 1.3; glyphs := utf8_glyph_count(label)
	if glyphs > 0 do scale = min(scale, max((box.w - text_inset - right_inset) / (f32(glyphs) * COURIER_CELL_WIDTH), .72))
	vulkan_ui_system_text(
		r,
		box.x + text_inset,
		box.y + (box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2,
		label,
		on || focused ? UI_INK_STRONG : UI_INK,
		scale,
	)
}
vk_graph_tab :: proc(r: ^Vulkan_Backend, box: Rect, label: string, active := false) {
	vk_tab_surface(r, box, label, active, vk_focused_button == button_id(box))
}
vk_graph_tab_bar :: proc(r: ^Vulkan_Backend, box: Rect) {
	vk_tab_bar_surface(r, box)
}
vk_compact_button :: proc(r: ^Vulkan_Backend, box: Rect, label: string, on := false) {
	focused := vk_focused_button == button_id(box)
	vulkan_ui_rect(
		r,
		box.x + 4,
		box.y + 5,
		box.w,
		box.h,
		{0, 0, 0, 120},
	); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, focused ? [4]u8{58, 62, 73, 255} : on ? [4]u8{74, 57, 20, 255} : [4]u8{40, 46, 58, 255})
	if on || focused do vulkan_ui_rect(r, box.x, box.y, 6, box.h, {255, 211, 92, 255})
	vulkan_ui_outline(
		r,
		box.x,
		box.y,
		box.w,
		box.h,
		on || focused ? [4]u8{255, 211, 92, 255} : [4]u8{148, 155, 168, 255},
		on || focused ? 3 : 2,
	)
	glyphs := utf8_glyph_count(
		label,
	); scale: f32 = .78; if glyphs > 0 do scale = min(scale, (box.w - 16) / (f32(glyphs) * COURIER_CELL_WIDTH)); scale = max(scale, EDITOR_MIN_TEXT_SCALE)
	vk_editor_text(
		r,
		box.x + 8,
		box.y + (box.h - f32(COURIER_CELL_HEIGHT) * scale) / 2,
		label,
		{255, 255, 255, 255},
		scale,
	)
}
vk_dialogue_choice_surface :: proc(r: ^Vulkan_Backend, box: Rect, focused: bool) {
	if focused {
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			{38, 43, 52, 248},
		); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {255, 211, 92, 235}, 2); vulkan_ui_rect(r, box.x, box.y, 5, box.h, {255, 211, 92, 255})
	} else {
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			{22, 27, 34, 150},
		); vulkan_ui_rect(r, box.x, box.y + box.h - 1, box.w, 1, {118, 124, 134, 145}); vulkan_ui_rect(r, box.x, box.y, 2, box.h, {180, 156, 96, 150})
	}
}
vk_dialogue_status_surface :: proc(r: ^Vulkan_Backend, box: Rect, accent: [4]u8) {
	vulkan_ui_rect(
		r,
		box.x,
		box.y,
		box.w,
		box.h,
		{20, 24, 31, 232},
	); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, accent, 1); vulkan_ui_rect(r, box.x, box.y, 5, box.h, accent)
	// Semantic notch patterns provide a non-color cue: info=one, success=two,
	// warning=three, danger=four. They remain visible in monochrome captures.
	notches := 1; if accent == UI_SUCCESS do notches = 2
	else if accent == UI_WARNING do notches = 3
	else if accent == UI_DANGER do notches = 4
	for i in 0 ..< notches do vulkan_ui_rect(r, box.x + 11 + f32(i) * 8, box.y + 6, 5, 3, accent)
}

vk_dialogue_object_check_choice :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	box: Rect,
	clue_index: int,
	focused: bool,
) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return; vk_dialogue_choice_surface(r, box, focused); clue := &payload.clues[clue_index]; _, _, skill_color := skill_helper(clue.skill); kind_color := clue.check_kind == "red" ? [4]u8{255, 144, 119, 255} : [4]u8{155, 201, 255, 255}
	number := text_effect_default(
		{255, 211, 92, 255},
		.9,
	); skill := text_effect_default(skill_color, .78); skill.letter_spacing = 1; kind := text_effect_default(kind_color, .72); meta := text_effect_default({205, 207, 210, 255}, .68)
	modifier := check_modifier(
		skill_index(clue.skill),
		clue_evidence_bonus(g, clue_index),
		clue_disposition(g, clue_index),
		clue_situational_bonus(g, clue_index),
	); chance := check_success_percent(check_target(clue.difficulty), modifier); odds := text_effect_default(ui_success_chance_color(chance), .72); cost := clue_action_cost(g, clue_index); _ = vk_rich_text(r, box.x + 17, box.y + 8, []Text_Span{{fmt.tprintf("%s  ", dialogue_choice_marker(g, 0)), number}, {strings.to_upper(clue.skill), skill}, {fmt.tprintf("  %d%%", chance), odds}, {fmt.tprintf("  %s", check_retry_label(clue.check_kind)), kind}, {fmt.tprintf("   %s", dialogue_tick_cost_label(cost)), meta}}, g.animation_time)
	body := text_effect_default(
		{248, 247, 242, 255},
		.9,
	); body.shadow_color = {0, 0, 0, 180}; body.shadow_offset = {1, 1}; _ = vk_text_effect_wrapped(r, box.x + 48, box.y + 30, box.w - 64, strings.to_upper(clue.description), body, g.animation_time, 2)
}

vk_dialogue_approach_choice :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	box: Rect,
	index, slot: int,
	focused: bool,
) {
	payload := mystery_game_payload(
		g,
	); node := mystery_dialogue_approach_at(payload, index); if node == nil do return
	if focused {vulkan_ui_rect(r, box.x + 11, box.y + 4, 3, box.h - 8, {255, 211, 92, 255}); vulkan_ui_rect(r, box.x + 18, box.y + box.h - 1, box.w - 36, 1, {255, 211, 92, 100})}
	number := text_effect_default({255, 211, 92, 255}, .9); number.letter_spacing = 1
	if node.clue_id ==
	   "" {_ = vk_rich_text(r, box.x + 17, box.y + 10, []Text_Span{{dialogue_choice_marker(g, slot), number}}, g.animation_time); body := text_effect_default({248, 247, 242, 255}, .9); body.shadow_color = {0, 0, 0, 180}; body.shadow_offset = {1, 1}; _ = vk_text_effect_wrapped(r, box.x + 48, box.y + 10, box.w - 64, dialogue_semantic_text(node.prompt, "choice"), body, g.animation_time, 2); return}
	clue_index := dialogue_check_clue_index(
		g,
		index,
	); if clue_index < 0 do return; clue := &payload.clues[clue_index]; _, _, skill_color := skill_helper(clue.skill); kind_color := clue.check_kind == "red" ? [4]u8{255, 144, 119, 255} : [4]u8{155, 201, 255, 255}
	skill := text_effect_default(
		skill_color,
		.78,
	); skill.letter_spacing = 1; skill.shadow_color = {0, 0, 0, 180}; skill.shadow_offset = {1, 1}; meta := text_effect_default({205, 207, 210, 255}, .68); kind := text_effect_default(kind_color, .72)
	modifier := check_modifier(
		skill_index(clue.skill),
		clue_evidence_bonus(g, clue_index),
		clue_disposition(g, clue_index),
		clue_situational_bonus(g, clue_index),
	); chance := check_success_percent(check_target(clue.difficulty), modifier); odds := text_effect_default(ui_success_chance_color(chance), .72); cost := clue_action_cost(g, clue_index); _ = vk_rich_text(r, box.x + 17, box.y + 8, []Text_Span{{fmt.tprintf("%s  ", dialogue_choice_marker(g, slot)), number}, {strings.to_upper(clue.skill), skill}, {fmt.tprintf("  %d%%", chance), odds}, {fmt.tprintf("  %s", check_retry_label(clue.check_kind)), kind}, {fmt.tprintf("   %s", dialogue_tick_cost_label(cost)), meta}}, g.animation_time)
	body := text_effect_default(
		{248, 247, 242, 255},
		.9,
	); body.shadow_color = {0, 0, 0, 180}; body.shadow_offset = {1, 1}; _ = vk_text_effect_wrapped(r, box.x + 48, box.y + 30, box.w - 64, dialogue_semantic_text(node.prompt, "choice"), body, g.animation_time, 2)
}

vk_dialogue_evidence_choice :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	box: Rect,
	clue_index, slot: int,
	focused: bool,
) {
	vk_dialogue_choice_surface(
		r,
		box,
		focused,
	); source := relevant_evidence_for_clue(g, clue_index); name := source >= 0 ? case_sense_source_name(g, source) : "relevant evidence"
	number := text_effect_default(
		{255, 211, 92, 255},
		.9,
	); challenge := text_effect_default({119, 190, 213, 255}, .74); challenge.letter_spacing = 1; body := text_effect_default({248, 247, 242, 255}, .9); body.shadow_color = {0, 0, 0, 180}; body.shadow_offset = {1, 1}
	_ = vk_rich_text(
		r,
		box.x + 17,
		box.y + 10,
		[]Text_Span {
			{fmt.tprintf("%s  ", dialogue_choice_marker(g, slot)), number},
			{"CHALLENGE  ·  ", challenge},
			{fmt.tprintf("Use %s", name), body},
		},
		g.animation_time,
	)
}

dialogue_check_clue_index :: proc(g: ^Game, node_index: int) -> int {
	payload := mystery_game_payload(
		g,
	); node := mystery_dialogue_approach_at(payload, node_index); if node == nil || node.clue_id == "" do return -1; return mystery_clue_index(payload, node.clue_id)
}

vk_draw_check_tooltip_clue :: proc(r: ^Vulkan_Backend, g: ^Game, clue_index: int, anchor: Rect) {
	payload := mystery_game_payload(
		g,
	); if payload == nil || clue_index < 0 || clue_index >= len(payload.clues) do return
	clue := &payload.clues[clue_index]; skill := skill_index(clue.skill); evidence := clue_evidence_bonus(g, clue_index); disposition := clue_disposition(g, clue_index); presented := clue_situational_bonus(g, clue_index)
	target := check_target(
		clue.difficulty,
	); modifier := check_modifier(skill, evidence, disposition, presented); chance := check_success_percent(target, modifier); cost := clue_action_cost(g, clue_index); verdict_color := [4]u8{255, 211, 92, 255}
	person_check :=
		g.dialogue_entity >= 0 &&
		g.dialogue_entity < len(WORLD_ENTITIES) &&
		WORLD_ENTITIES[g.dialogue_entity].kind ==
			"person"; breakdown_rows := 2 + (person_check ? 1 : 0) + (presented > 0 ? 1 : 0)
	target_y :=
		anchor.y +
		anchor.h *
			.5; x, w := f32(310), f32(285); h := f32(260 + 21 * (breakdown_rows - 2)); y := clamp(target_y - h * .5, f32(170), f32(710) - h); vk_panel(r, x, y, w, h)
	vulkan_ui_rect(
		r,
		x + 2,
		y + 2,
		w - 4,
		40,
		verdict_color,
	); vk_text(r, x + 18, y + 11, fmt.tprintf("%s  •  %s", strings.to_upper(clue.skill), check_retry_label(clue.check_kind)), {14, 16, 20, 255}, .92)
	vk_text(
		r,
		x + 20,
		y + 55,
		"ROLL TWO DICE",
		verdict_color,
		.9,
	); vk_text(r, x + 20, y + 78, fmt.tprintf("2D6  %+d", modifier), {248, 247, 242, 255}, 1.75); vk_text(r, x + 20, y + 115, dialogue_check_threshold_label(target), {255, 211, 92, 255}, .72); vk_text(r, x + 166, y + 117, fmt.tprintf("%d%% SUCCESS", chance), ui_success_chance_color(chance), .68)
	vulkan_ui_rect(r, x + 20, y + 137, w - 40, 1, {148, 155, 168, 210})
	row_y :=
		y +
		f32(
			151,
		); vk_text(r, x + 20, row_y, fmt.tprintf("SKILL        %+d", skill), {248, 247, 242, 255}, .74); row_y += 21
	vk_text(
		r,
		x + 20,
		row_y,
		fmt.tprintf("EVIDENCE     %+d", evidence),
		evidence > 0 ? [4]u8{102, 205, 143, 255} : [4]u8{205, 207, 210, 255},
		.74,
	); row_y += 21
	if person_check {vk_text(r, x + 20, row_y, fmt.tprintf("DISPOSITION  %+d", disposition), disposition > 0 ? [4]u8{102, 205, 143, 255} : disposition < 0 ? [4]u8{255, 144, 119, 255} : [4]u8{205, 207, 210, 255}, .74); row_y += 21}
	if presented >
	   0 {vk_text(r, x + 20, row_y, fmt.tprintf("PRESENTED   +%d", presented / 10), {102, 205, 143, 255}, .74); row_y += 21}
	cost_y :=
		row_y +
		8; vk_text(r, x + 20, cost_y, dialogue_check_tooltip_cost(cost, max(0, g.ap - cost)), cost <= 0 ? [4]u8{102, 205, 143, 255} : verdict_color, .62)
	failure := clue.check_kind == "red" ? "YOU MAY TRY ONCE" : "YOU MAY RETRY."
	_ = vk_text_wrapped(r, x + 20, cost_y + 22, w - 40, failure, verdict_color, .62, 1)
	// A single leader meets the row's focus arrow without adding a second marker.
	card_edge :=
		x +
		w; vulkan_ui_rect(r, card_edge, target_y - 2, anchor.x - card_edge - 14, 4, {255, 211, 92, 255})
}
vk_draw_check_tooltip :: proc(
	r: ^Vulkan_Backend,
	g: ^Game,
	node_index: int,
	anchor: Rect,
) {vk_draw_check_tooltip_clue(r, g, dialogue_check_clue_index(g, node_index), anchor)}
