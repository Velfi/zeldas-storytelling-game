package main

import "core:math"
import ui "zelda_engine:ui"

Text_Effect :: ui.Text_Effect
Text_Span :: ui.Text_Span
text_effect_default :: proc(color := [4]u8{226, 220, 198, 255}, scale: f32 = 1.25) -> Text_Effect {
	effect := ui.text_effect_default(color, scale)
	effect.wave_frequency = .65
	effect.wave_speed = 5
	effect.pulse_speed = 4
	return effect
}
text_effect_lerp :: ui.text_effect_lerp
text_effect_visible_glyphs :: ui.text_effect_visible_glyphs
text_effect_span_visible_glyphs :: ui.text_effect_span_visible_glyphs
text_effect_span_duration :: ui.text_effect_span_duration
text_effect_reveal_glyph_count :: ui.text_effect_reveal_glyph_count
text_effect_line_scale :: ui.text_effect_line_scale
text_effect_hash :: ui.text_effect_hash

vk_rich_text :: proc(r: ^Vulkan_Backend, x, y: f32, spans: []Text_Span, elapsed: f32) -> Vec2 {
	cursor := Vec2{x, y}; global_glyph, line := 0, 0; timeline_cursor: f32 = 0
	for span in spans {
		effect := span.effect; if effect.scale <= 0 do effect.scale = 1
		span_count := text_effect_reveal_glyph_count(
			span.text,
		); visible := text_effect_span_visible_glyphs(effect, elapsed, timeline_cursor, span_count); span_glyph := 0
		for ch in span.text {
			if ch ==
			   '\n' {cursor.x = x; cursor.y += f32(COURIER_CELL_HEIGHT) * text_effect_line_scale(spans, line); line += 1; continue}
			advance := f32(COURIER_CELL_WIDTH) * effect.scale + effect.letter_spacing
			if span_glyph >=
			   visible {cursor.x += advance; span_glyph += 1; global_glyph += 1; continue}
			phase := f32(global_glyph) * effect.wave_frequency + elapsed * effect.wave_speed
			position := Vec2 {
				cursor.x + effect.offset.x + effect.drift.x * elapsed,
				cursor.y + effect.offset.y + effect.drift.y * elapsed,
			}
			position.y += f32(math.sin(f64(phase))) * effect.wave_amplitude
			if effect.shake >
			   0 {tick := int(elapsed * 30); position.x += text_effect_hash(global_glyph * 2 + tick * 131) * effect.shake; position.y += text_effect_hash(global_glyph * 2 + tick * 131 + 1) * effect.shake}
			glyph_scale :=
				effect.scale *
				(1 +
						f32(
							math.sin(f64(elapsed * effect.pulse_speed + f32(global_glyph) * .15)),
						) *
							effect.pulse_amount)
			color := effect.color
			italic_offset := effect.italic ? f32(3) * glyph_scale : f32(0)
			bold_offset := max(glyph_scale * .8, .5)
			if effect.shadow_color[3] > 0 {
				vulkan_ui_glyph_slanted(
					r,
					position.x + effect.shadow_offset.x,
					position.y + effect.shadow_offset.y,
					ch,
					effect.shadow_color,
					glyph_scale,
					glyph_scale,
					italic_offset,
				)
				if effect.bold do vulkan_ui_glyph_slanted(r, position.x + effect.shadow_offset.x + bold_offset, position.y + effect.shadow_offset.y, ch, effect.shadow_color, glyph_scale, glyph_scale, italic_offset)
			}
			vulkan_ui_glyph_slanted(
				r,
				position.x,
				position.y,
				ch,
				color,
				glyph_scale,
				glyph_scale,
				italic_offset,
			)
			if effect.bold do vulkan_ui_glyph_slanted(r, position.x + bold_offset, position.y, ch, color, glyph_scale, glyph_scale, italic_offset)
			if effect.underline {
				underline_y :=
					position.y + f32(COURIER_CELL_HEIGHT) * glyph_scale - f32(2) * glyph_scale
				vulkan_ui_rect(
					r,
					position.x,
					underline_y,
					advance,
					max(glyph_scale, effect.bold ? f32(2) : f32(1)),
					color,
				)
			}
			cursor.x += advance; span_glyph += 1; global_glyph += 1
		}
		timeline_cursor += text_effect_span_duration(effect, span_count)
	}
	return cursor
}

vk_text_effect_line :: proc(
	r: ^Vulkan_Backend,
	x, y: f32,
	line: string,
	effect: Text_Effect,
	elapsed: f32,
	glyph_offset: int,
) {
	line_effect := effect
	if line_effect.typewriter_characters_per_second > 0 do line_effect.typewriter_delay += f32(glyph_offset) / line_effect.typewriter_characters_per_second
	_ = vk_rich_text(r, x, y, []Text_Span{{line, line_effect}}, elapsed)
}

vk_text_effect_wrapped :: proc(
	r: ^Vulkan_Backend,
	x, y, max_width: f32,
	value: string,
	effect: Text_Effect,
	elapsed: f32,
	line_spacing: f32 = 4,
) -> f32 {
	if value == "" do return y
	advance :=
		f32(COURIER_CELL_WIDTH) * effect.scale +
		effect.letter_spacing; line_height := f32(COURIER_CELL_HEIGHT) * effect.scale + line_spacing; cursor_y := y; plan := text_layout_plan(value, text_layout_columns(max_width, advance))
	for line in plan {vk_text_effect_line(
			r,
			x,
			cursor_y,
			value[line.start:line.end],
			effect,
			elapsed,
			line.glyph_offset,
		)
		cursor_y += line_height}
	return cursor_y
}
