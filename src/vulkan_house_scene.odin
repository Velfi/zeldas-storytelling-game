package main

import "core:math"
import "core:time"
import engine "zelda_engine:engine"

house_wall_tint :: proc(x, z: f32) -> [4]u8 {
	// Room-specific wall coverings establish purpose before any HUD text is read.
	if z < 5 do return {176, 164, 143, 255} // warm dining plaster
	if z < 9 && x < 12 do return {118, 139, 125, 255} // quiet green study
	if z < 9 && x < 17 do return {126, 140, 153, 255} // blue-gray gallery
	if z < 9 do return {169, 157, 124, 255} // pantry ochre
	return {148, 151, 145, 255} // garden stone
}

// The background is a deliberately separate world layer beneath the dollhouse.
// Its palette follows the room occupied by the investigator, so the surrounding
// negative space belongs to the current interior instead of reading as a void.
house_background_tint :: proc(g: ^Game) -> [4]u8 {
	switch world_location_index(g) {
	// These are deliberately near-black sRGB palette values. The world shader
	// decodes draw tints to linear light before rendering to the sRGB target.
	case 0:
		return {7, 4, 3, 255} // dining: warm walnut/cloth
	case 1:
		return {4, 5, 7, 255} // gallery: blue slate
	case 2:
		return {3, 7, 5, 255} // study: ink green
	case 3:
		return {4, 7, 5, 255} // garden: moonlit foliage
	case:
		return {7, 6, 3, 255} // pantry: muted ochre
	}
}

house_cutaway_amount :: proc(g: ^Game) -> f32 {
	if g.capture_cutaway_override {amount := clamp(g.capture_cutaway_amount, 0, 1); return amount * amount * (3 - 2 * amount)}
	explicit := g.top_down_camera || editor_state.view == .Cutaway
	amount :=
		explicit ? f32(1) : g.wall_view == .Walls_Up ? f32(0) : g.wall_view == .Walls_Down ? f32(1) : (g.editor_mode != .Build ? clamp(g.cutaway_transition, 0, 1) : f32(0))
	return amount * amount * (3 - 2 * amount)
}

house_render_wall_height :: proc(g: ^Game) -> f32 {
	amount := house_cutaway_amount(g)
	height := house_authored_wall_height(

	); return height + (min(HOUSE_CUTAWAY_HEIGHT, height) - height) * amount
}

// Structural wall meshes are already authored at their final plan dimensions.
// Supplying that span as the draw width keeps X/Z at unit scale while the
// cutaway transition changes only their vertical height.
house_render_wall_width :: proc(mesh: ^Glb_Mesh) -> f32 {
	return max(mesh.max.x - mesh.min.x, .0001)
}

house_wall_cap_tint :: proc(amount: f32) -> [4]u8 {
	t := clamp(amount, 0, 1)
	return {u8(132 + 36 * t), u8(138 + 36 * t), u8(134 + 36 * t), 255}
}

// Horizontal cut planes share one material ramp.
house_wall_section_tint :: proc(amount: f32) -> [4]u8 {return house_wall_cap_tint(amount)}

// Vertical reveals receive less overhead light than the horizontal plane.
// Darkening the same base material gives mixed-height boundaries readable
// depth without introducing a separate architectural finish.
house_wall_junction_tint :: proc(amount: f32) -> [4]u8 {
	cap := house_wall_section_tint(amount)
	return {u8(f32(cap[0]) * .76), u8(f32(cap[1]) * .76), u8(f32(cap[2]) * .76), 255}
}

house_wall_cap_edge_tint :: proc(amount: f32) -> [4]u8 {
	cap := house_wall_section_tint(amount); t := clamp(amount, 0, 1)
	return {
		u8(f32(cap[0]) * (1 - .18 * t)),
		u8(f32(cap[1]) * (1 - .18 * t)),
		u8(f32(cap[2]) * (1 - .18 * t)),
		255,
	}
}

HOUSE_WALL_CAP_EDGE_OVERHANG :: f32(.036)

house_wall_cap_draw_height :: proc(mesh: ^Glb_Mesh) -> f32 {return max(
		mesh.max.y - mesh.min.y,
		.001,
	)}

house_wall_section_amount :: proc(g: ^Game, index: int) -> f32 {
	if index < 0 || index >= HOUSE_WALL_SECTION_CAPACITY do return 0
	t := clamp(g.wall_cutaways[index], 0, 1); return t * t * (3 - 2 * t)
}

house_wall_section_height :: proc(g: ^Game, index: int) -> f32 {
	amount := house_wall_section_amount(
		g,
		index,
	); height := house_authored_wall_height(); return height + (min(HOUSE_CUTAWAY_HEIGHT, height) - height) * amount
}

house_wall_uniform_amount :: proc(g: ^Game) -> (f32, bool) {
	if len(house_walls) == 0 do return 0, false
	amount := house_wall_section_amount(
		g,
		0,
	); for i in 1 ..< len(house_walls) do if math.abs(house_wall_section_amount(g, i) - amount) > .001 do return 0, false
	return amount, true
}

house_wall_junction_reveal_height :: proc(g: ^Game, index: int, endpoint: Vec2) -> f32 {
	if index < 0 || index >= len(house_walls) do return 0
	section_height := house_wall_section_height(g, index); neighbor_height := section_height
	for other, j in house_walls {
		if j == index do continue
		// Endpoints may meet another endpoint or terminate into the middle of a
		// run at a T junction, so test against the complete neighboring segment.
		if point_segment_distance_sq(endpoint.x, endpoint.y, other.a, other.b) <= .025 * .025 do neighbor_height = max(neighbor_height, house_wall_section_height(g, j))
	}
	return max(neighbor_height - section_height, f32(0))
}

house_wall_finish_light_anchor :: proc(index: int, face_point: Vec2) -> Vec2 {
	if index < 0 || index >= len(house_walls) do return face_point
	host :=
		house_walls[index]; dx, dz := host.b.x - host.a.x, host.b.y - host.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .001 do return face_point
	tx, tz := dx / length, dz / length; nx, nz := -tz, tx; minimum, maximum := f32(0), length
	for wall in house_walls {wdx, wdz := wall.b.x - wall.a.x, wall.b.y - wall.a.y
		wall_length := f32(math.sqrt(f64(wdx * wdx + wdz * wdz)))
		if wall_length <= .001 do continue
		if math.abs((wdx * tz - wdz * tx) / wall_length) > .01 do continue
		line_distance := math.abs((wall.a.x - host.a.x) * nz - (wall.a.y - host.a.y) * nx)
		if line_distance > .03 do continue
		points := [2]Vec2{}
		points[0] = wall.a
		points[1] = wall.b
		for point in points {projection := (point.x - host.a.x) * tx + (point.y - host.a.y) * tz
			minimum = min(minimum, projection)
			maximum = max(maximum, projection)}}
	face_offset :=
		(face_point.x - host.a.x) * nx +
		(face_point.y - host.a.y) *
			nz; mid := (minimum + maximum) * .5; return {host.a.x + tx * mid + nx * face_offset, host.a.y + tz * mid + nz * face_offset}
}

house_wall_finish_light_group :: proc(index: int, face_point: Vec2) -> (Vec2, u64) {
	anchor := house_wall_finish_light_anchor(
		index,
		face_point,
	); if index < 0 || index >= len(house_walls) do return anchor, 0
	host :=
		house_walls[index]; dx, dz := host.b.x - host.a.x, host.b.y - host.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .001 do return anchor, 0
	tx, tz :=
		dx /
		length,
		dz /
		length; if tx < -.001 || (math.abs(tx) <= .001 && tz < 0) {tx = -tx; tz = -tz}
	qx := u64(
		clamp(int(math.round(f64(anchor.x * 100))), 0, 0xfffff),
	); qz := u64(clamp(int(math.round(f64(anchor.y * 100))), 0, 0xfffff))
	qtx := u64(
		clamp(int(math.round(f64((tx + 1) * 500))), 0, 0x3ff),
	); qtz := u64(clamp(int(math.round(f64((tz + 1) * 500))), 0, 0x3ff)); room := u64(clamp(vk_world_room_at(anchor) + 2, 0, 0xff))
	return anchor, 1 + qx + (qz << 20) + (qtx << 40) + (qtz << 50) + (room << 60)
}

house_opening_wall_height :: proc(g: ^Game, opening: Plan_Opening) -> f32 {
	index := house_opening_host_wall_index(
		opening,
	); if index >= 0 do return house_wall_section_height(g, index); return house_authored_wall_height()
}

house_aperture_top_for_height :: proc(opening: Plan_Opening, host_height: f32) -> f32 {
	if opening.id ==
	   "window_study_courtyard" {sill := opening.sill_height > 0 ? opening.sill_height : f32(.72); glazing := opening.height > 0 ? opening.height : f32(1.4); return min(house_authored_wall_height(), sill + glazing + HOUSE_WINDOW_FRAME_RAIL_HEIGHT)}
	return host_height
}

house_opening_aperture_top :: proc(g: ^Game, opening: Plan_Opening) -> f32 {
	return house_aperture_top_for_height(opening, house_opening_wall_height(g, opening))
}

house_wall_height_at_point :: proc(g: ^Game, point: Vec2) -> f32 {
	for wall, i in house_walls do if point_segment_distance_sq(point.x, point.y, wall.a, wall.b) < .12 * .12 do return house_wall_section_height(g, i)
	return house_authored_wall_height()
}

house_wall_height_near_point :: proc(g: ^Game, point: Vec2, max_distance: f32 = .35) -> f32 {
	index := house_wall_index_near_point(point, max_distance)
	return index >= 0 ? house_wall_section_height(g, index) : house_authored_wall_height()
}

house_wall_index_near_point :: proc(point: Vec2, max_distance: f32 = .35) -> int {
	best := max_distance * max_distance; index := -1
	for wall, i in house_walls {distance := point_segment_distance_sq(
			point.x,
			point.y,
			wall.a,
			wall.b,
		)
		if distance < best {best = distance; index = i}}
	return index
}

house_wall_attachment_pose :: proc(index: int, authored: Vec2) -> (x, z, yaw: f32, ok: bool) {
	if index < 0 || index >= len(house_walls) do return 0, 0, 0, false
	wall :=
		house_walls[index]; dx, dz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; length_sq := dx * dx + dz * dz
	if length_sq <= .0001 do return 0, 0, 0, false
	t := clamp(((authored.x - wall.a.x) * dx + (authored.y - wall.a.y) * dz) / length_sq, 0, 1)
	px, pz :=
		wall.a.x +
		dx * t,
		wall.a.y +
		dz * t; length := f32(math.sqrt(f64(length_sq))); nx, nz := -dz / length, dx / length
	side := (authored.x - px) * nx + (authored.y - pz) * nz; positive := side >= 0
	// Authored points occasionally sit almost exactly on the centerline. Prefer
	// the wall's sole interior face in that case, and never mount art outdoors.
	if math.abs(side) <
	   .01 {if wall.positive_interior && !wall.negative_interior do positive = true
		else if wall.negative_interior && !wall.positive_interior do positive = false}
	if positive && !wall.positive_interior && wall.negative_interior do positive = false
	if !positive && !wall.negative_interior && wall.positive_interior do positive = true
	sign := positive ? f32(1) : f32(-1); offset := f32(HOUSE_WALL_THICKNESS * .5 + .012)
	return px + nx * offset * sign,
		pz + nz * offset * sign,
		f32(math.atan2(f64(dz), f64(dx))) + (positive ? 0 : f32(math.PI)),
		true
}

HOUSE_WALL_ART_FADE_BOTTOM :: f32(1.52)
HOUSE_WALL_ART_FADE_TOP :: f32(2.42)

house_wall_art_opacity :: proc(wall_height: f32) -> u8 {
	t := clamp(
		(wall_height - HOUSE_WALL_ART_FADE_BOTTOM) /
		(HOUSE_WALL_ART_FADE_TOP - HOUSE_WALL_ART_FADE_BOTTOM),
		0,
		1,
	)
	t = t * t * (3 - 2 * t)
	return u8(math.round(f64(t * 255)))
}

house_wall_art_supported :: proc(wall_height: f32) -> bool {return(
		house_wall_art_opacity(wall_height) >
		0 \
	)}

house_door_render_height :: proc(opening: Plan_Opening) -> f32 {
	return opening.height > 0 ? opening.height : f32(2.1)
}

house_door_render_width :: proc(aperture_width: f32) -> f32 {
	return max(aperture_width, f32(.001))
}

// Casing belongs to the movable/readable door assembly, not to the masonry
// being sectioned. Keeping this separate makes that policy explicit at call sites.
house_door_casing_height :: proc(opening: Plan_Opening) -> f32 {return house_door_render_height(
		opening,
	)}
HOUSE_DOOR_CASING_RAIL :: f32(.085)

house_door_casing_jamb_height :: proc(opening: Plan_Opening, host_height: f32) -> f32 {
	return clamp(host_height, 0, house_door_casing_height(opening))
}

house_door_casing_head_base :: proc(opening: Plan_Opening) -> f32 {
	return house_door_casing_height(opening) - HOUSE_DOOR_CASING_RAIL * .5
}

house_door_casing_head_height :: proc(opening: Plan_Opening, host_height: f32) -> f32 {
	return clamp(host_height - house_door_casing_head_base(opening), 0, HOUSE_DOOR_CASING_RAIL)
}

house_door_handle_height :: proc(opening: Plan_Opening) -> f32 {return min(
		f32(1.02),
		house_door_render_height(opening) * .5,
	)}
HOUSE_DOOR_HANDLE_ALONG :: f32(.78)

house_window_lower_masonry_height :: proc(sill_height, host_height: f32) -> f32 {
	return max(min(sill_height, host_height), f32(0))
}

house_window_light_columns :: proc(width: f32) -> int {
	if width < 1.1 do return 1
	if width < 2.4 do return 2
	if width < 3.6 do return 3
	return clamp(int(math.round(f64(width / 1.15))), 3, 6)
}

house_window_light_rows :: proc(height: f32) -> int {
	if height < 1.1 do return 1
	if height < 2.2 do return 2
	return 3
}

house_window_muntin_width :: proc(rail: f32) -> f32 {return max(rail * .55, f32(.022))}
house_window_internal_vertical_width :: proc(style: Window_Style, rail: f32) -> f32 {if style == .Casement do return rail
	return house_window_muntin_width(rail)}
house_window_internal_horizontal_width :: proc(style: Window_Style, rail: f32) -> f32 {if style == .Awning || style == .Double_Hung do return rail
	return house_window_muntin_width(rail)}
house_window_glazing_bead_width :: proc(rail: f32) -> f32 {return clamp(
		rail * .28,
		f32(.014),
		f32(.022),
	)}
house_window_casing_width :: proc(interior: bool) -> f32 {return interior ? f32(.085) : f32(.065)}
house_window_head_flashing_overhang :: proc() -> f32 {return .12}
house_window_head_flashing_end_dam_width :: proc() -> f32 {return .022}
house_window_head_flashing_end_dam_height :: proc() -> f32 {return .055}
house_window_operable_sash_offset :: proc(style: Window_Style) -> f32 {if style == .Casement || style == .Awning do return .006
	return 0}
house_window_operable_frame_width :: proc(rail: f32) -> f32 {return clamp(
		rail * .48,
		f32(.022),
		f32(.032),
	)}
house_window_operable_mullion_count :: proc(style: Window_Style, columns: int) -> int {if style == .Casement do return max(columns - 1, 0)
	return 0}
house_window_perimeter_sealant_width :: proc() -> f32 {return .010}
house_window_interior_caulk_width :: proc() -> f32 {return .007}
house_window_hardware_offset :: proc() -> f32 {return house_window_frame_v_mesh.max.z + .012}
house_window_casement_hardware_count :: proc(
	columns: int,
) -> (
	handles, hinge_sides: int,
) {if columns <= 1 do return 1, 1; return 2, 2}
house_window_casement_handle_along :: proc(
	columns, index: int,
	side, rail: f32,
	hinge_right: bool = false,
) -> f32 {if columns <= 1 do return hinge_right ? -side + rail * .65 : side - rail * .65; return(
		(index == 0 ? -1 : 1) *
		rail *
		.65 \
	)}
house_window_casement_hinge_along :: proc(
	columns, index: int,
	side, rail: f32,
	hinge_right: bool = false,
) -> f32 {if columns <= 1 do return hinge_right ? side - rail * .5 : -side + rail * .5; return(
		(index == 0 ? -1 : 1) *
		(side - rail * .5) \
	)}
house_window_double_hung_sash_offset :: proc() -> f32 {return .012}
house_window_double_hung_upper_bead_offset :: proc(frame_offset: f32) -> f32 {return(
		frame_offset -
		house_window_double_hung_sash_offset() * 2 \
	)}
house_window_double_hung_stile_along :: proc(glass_width, rail: f32) -> f32 {return max(
		glass_width * .5 - rail * .5,
		f32(0),
	)}
house_window_double_hung_parting_bead_width :: proc(rail: f32) -> f32 {return clamp(
		rail * .26,
		f32(.012),
		f32(.018),
	)}
house_window_double_hung_parting_bead_along :: proc(glass_width, rail: f32) -> f32 {return max(
		glass_width * .5 - rail * .12,
		f32(0),
	)}
house_window_room_sign :: proc(a, b: Vec2) -> f32 {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do return 1
	mx, mz :=
		(a.x + b.x) *
		.5,
		(a.y + b.y) *
		.5; nx, nz := -dz / length, dx / length; sample := f32(HOUSE_WALL_THICKNESS * .5 + .16)
	positive_x, positive_z :=
		mx +
		nx * sample,
		mz +
		nz * sample; negative_x, negative_z := mx - nx * sample, mz - nz * sample
	positive_inside :=
		positive_x >= 0 &&
		positive_x < f32(HOUSE_SURFACE_WIDTH) &&
		positive_z >= 0 &&
		positive_z < f32(HOUSE_SURFACE_HEIGHT) &&
		house_space_kind_at(positive_x, positive_z) == .Interior
	negative_inside :=
		negative_x >= 0 &&
		negative_x < f32(HOUSE_SURFACE_WIDTH) &&
		negative_z >= 0 &&
		negative_z < f32(HOUSE_SURFACE_HEIGHT) &&
		house_space_kind_at(negative_x, negative_z) == .Interior
	if positive_inside != negative_inside do return positive_inside ? 1 : -1
	return 1
}

house_window_style_grid :: proc(style: Window_Style, width, height: f32) -> (int, int) {
	switch style {
	case .Picture:
		return 1, 1
	case .Casement:
		return house_window_light_columns(width), 1
	case .Awning:
		return 1, house_window_light_rows(height)
	case .Double_Hung:
		return house_window_light_columns(width), 2
	case .Fixed:
		return house_window_light_columns(width), house_window_light_rows(height)
	}
	return house_window_light_columns(width), house_window_light_rows(height)
}

vk_world_build_house :: proc(scene: ^Vk_World_Scene, ctx: ^engine.Vk_Context, g: ^Game) {
	house_phase_started := time.tick_now()
	scene.profile_house_structure_ms = 0; scene.profile_house_surfaces_ms = 0; scene.profile_house_walls_ms = 0; scene.profile_house_openings_ms = 0; scene.profile_house_objects_ms = 0; scene.profile_house_characters_ms = 0
	active_base := f32(
		0,
	); if level_document.active_story >= 0 && level_document.active_story < len(level_document.stories) do active_base = level_document.stories[level_document.active_story].base_elevation
	show_below :=
		g.editor_mode == .Build &&
		(editor_state.view == .Stories_Below ||
				editor_state.view == .Cutaway ||
				editor_state.view == .Roof)
	// Surface kind 3 is the background shader layer. It sits just below the
	// authored floor and extends beyond the cutaway in every camera direction.
	vk_world_add(
		scene,
		ctx,
		&house_floor_mesh,
		12,
		8,
		240,
		0,
		house_background_tint(g),
		true,
		3,
		-.08,
	)
	if level_document.active_story ==
	   0 {for i in 0 ..< generated_terrain_count {mesh := &generated_terrain_meshes[i]; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {255, 255, 255, 255}, false, 7, mesh.min.y)}; for space in Plan_Space_Kind {for surface in Room_Surface {
				// The Moon Garden Patio is open to the sky but still owns a finished floor.
				// Other exterior grounds remain continuous lawn.
				if space == .Grounds && surface != .Garden do continue
				batch := &house_floor_batches[space][surface]; if !batch.ready do continue
				cx, cz :=
					(batch.min.x + batch.max.x) *
					.5,
					(batch.min.z + batch.max.z) *
					.5; tint := space == .Grounds ? [4]u8{214, 218, 211, 255} : [4]u8{255, 255, 255, 255}; floor_base := active_base + .012
				vk_world_add(scene, ctx, batch, cx, cz, 1, 0, tint, false, 1, floor_base)
			}}}
	for &draw in personal_floor_draws do vk_world_add(scene, ctx, &draw.mesh, draw.x, draw.z, max(draw.mesh.max.y - draw.mesh.min.y, .001), draw.yaw, draw.tint, false, 1, draw.base)
	// Enclosed rooms always keep a watertight ceiling in the directional shadow
	// pass. This is independent of whether the presentation camera cuts away the
	// visible ceiling or roof.
	for &draw in personal_ceiling_draws do vk_world_add(scene, ctx, &draw.mesh, draw.x, draw.z, max(draw.mesh.max.y - draw.mesh.min.y, .001), draw.yaw, {255, 255, 255, 255}, false, 15, draw.base, shadow_only = true)
	if g.first_person_camera do for &draw in personal_ceiling_draws do vk_world_add(scene, ctx, &draw.mesh, draw.x, draw.z, max(draw.mesh.max.y - draw.mesh.min.y, .001), draw.yaw, {222, 220, 210, 255}, false, 15, draw.base)
	if level_document.active_story == 0 do for i in 0 ..< generated_foundation_count {mesh := &generated_foundation_meshes[i]; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {255, 255, 255, 255}, false, 0, mesh.min.y)}
	if level_document.active_story >
	   0 {for i in 0 ..< generated_story_slab_count {if generated_story_slab_story[i] != level_document.active_story do continue; mesh := &generated_story_slab_meshes[i]; if !mesh.ready do continue; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {255, 255, 255, 255}, false, 0, generated_story_slab_base_y[i])}}
	if show_below {for i in 0 ..< generated_story_slab_count {story := generated_story_slab_story[i]; if story >= level_document.active_story do continue; mesh := &generated_story_slab_meshes[i]; if !mesh.ready do continue; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {174, 184, 188, 210}, false, 0, generated_story_slab_base_y[i])}; for i in 0 ..< generated_story_wall_count {story := generated_story_wall_story[i]; if story >= level_document.active_story do continue; mesh := &generated_story_wall_meshes[i]; if !mesh.ready do continue; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {116, 126, 132, 210}, false, 0, generated_story_wall_base_y[i])}}
	// Automatic mode lowers only the active room's camera-facing sections. This
	// preserves the far walls and neighboring rooms as visual context.
	scene.profile_house_surfaces_ms =
		time.duration_seconds(time.tick_diff(house_phase_started, time.tick_now())) * 1000
	structure_phase_started := time.tick_now()
	uniform_amount, uniform_walls := house_wall_uniform_amount(g)
	finish_bands := house_wall_finish_bands()
	// At a uniform height, draw the regularized wall union instead of separate
	// butt-ended section prisms. The union owns continuous exterior corners and
	// opening cuts, so L junctions cannot expose half-thickness corner notches.
	// Mixed-height cutaways still need the independently scalable sections below.
	if uniform_walls && house_wall_solid.ready {
		authored_height := house_authored_wall_height(

		); uniform_height := authored_height + (min(HOUSE_CUTAWAY_HEIGHT, authored_height) - authored_height) * uniform_amount
		cx, cz :=
			(house_wall_solid.min.x + house_wall_solid.max.x) *
			.5,
			(house_wall_solid.min.z + house_wall_solid.max.z) *
			.5
		// The union is authored in world X/Z coordinates. Always provide its X span
		// so changing wall height can only scale Y; the generic height-only draw
		// path scales all three axes and would create a miniature wall plan.
		vk_world_add_sized(
			scene,
			ctx,
			&house_wall_solid,
			cx,
			cz,
			house_render_wall_width(&house_wall_solid),
			uniform_height,
			0,
			{255, 255, 255, 255},
			0,
			active_base,
		)
	}
	for &wall, i in house_walls {
		mx, mz :=
			(wall.a.x + wall.b.x) *
			.5,
			(wall.a.y + wall.b.y) *
			.5; dx, dz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do continue
		yaw := f32(
			math.atan2(f64(dz), f64(dx)),
		); height := house_wall_section_height(g, i); amount := house_wall_section_amount(g, i)
		if !uniform_walls {core_band_drawn := false; for band in 0 ..< len(wall.core_bands) {region_base := finish_bands[band]; if height <= region_base + .001 do continue; region_height := min(finish_bands[band + 1] - region_base, height - region_base); if region_height > .001 && wall.core_bands[band].ready {vk_world_add_sized(scene, ctx, &wall.core_bands[band], mx, mz, length, region_height, yaw, {255, 255, 255, 255}, 0, active_base + region_base); core_band_drawn = true}}; if !core_band_drawn do vk_world_add_sized(scene, ctx, &wall.core, mx, mz, length, height, yaw, {255, 255, 255, 255}, 0, active_base)}
		section_tint := house_wall_section_tint(amount)
		if !uniform_walls {cap_edge_mesh := house_wall_cap_edge_mesh_for_width(wall.width); vk_world_add_sized(scene, ctx, cap_edge_mesh, mx, mz, length + HOUSE_WALL_CAP_EDGE_OVERHANG, house_wall_cap_draw_height(cap_edge_mesh), yaw, house_wall_cap_edge_tint(amount), 6, active_base + height + .004); vk_world_add_sized(scene, ctx, &wall.cap, mx, mz, length, house_wall_cap_draw_height(&wall.cap), yaw, section_tint, 6, active_base + height + .008)}
		// Close mixed-height junctions with a vertical section reveal. Door leaves
		// remain independent, full-height objects and are never scaled by this path.
		if !uniform_walls {endpoints := [2]Vec2{wall.a, wall.b}; for endpoint in endpoints {reveal_height := house_wall_junction_reveal_height(g, i, endpoint); if reveal_height > .001 do vk_world_add_sized(scene, ctx, &house_wall_junction_reveal_mesh, endpoint.x, endpoint.y, wall.width + .012, reveal_height, yaw + f32(math.PI) / 2, house_wall_junction_tint(amount), 6, active_base + height)}}
		// Interior coverings and exterior opening patches are emitted below from one
		// aperture-aware finish list.
	}
	if uniform_walls &&
	   house_wall_cap_batch_full.ready {authored_height := house_authored_wall_height(); uniform_height := authored_height + (min(HOUSE_CUTAWAY_HEIGHT, authored_height) - authored_height) * uniform_amount; if house_wall_cap_union_edge.ready {edge_x, edge_z := (house_wall_cap_union_edge.min.x + house_wall_cap_union_edge.max.x) * .5, (house_wall_cap_union_edge.min.z + house_wall_cap_union_edge.max.z) * .5; vk_world_add(scene, ctx, &house_wall_cap_union_edge, edge_x, edge_z, .001, 0, house_wall_cap_edge_tint(uniform_amount), false, 6, active_base + uniform_height + .004)}; cx, cz := (house_wall_cap_batch_full.min.x + house_wall_cap_batch_full.max.x) * .5, (house_wall_cap_batch_full.min.z + house_wall_cap_batch_full.max.z) * .5; vk_world_add(scene, ctx, &house_wall_cap_batch_full, cx, cz, .001, 0, house_wall_section_tint(uniform_amount), false, 6, active_base + uniform_height + .008)}
	for &draw in wall_finish_draws {wall_height := house_wall_section_height(g, draw.wall_index)
		region_height := wall_height
		region_base := f32(0)
		if draw.region_height >
		   0 {region_base = draw.region_base; if wall_height <= region_base + .001 do continue
			region_height = min(draw.region_height, wall_height - region_base)}
		if region_height >
		   .001 {anchor := Vec2{draw.x, draw.z}; group: u64; anchored := draw.wall_index >= 0 && draw.wall_index < len(house_walls); if anchored do anchor, group = house_wall_finish_light_group(draw.wall_index, anchor); tint := draw.tint; if tint[3] == 0 do tint = {255, 255, 255, 255}; vk_world_add_sized(scene, ctx, &draw.mesh, draw.x, draw.z, house_render_wall_width(&draw.mesh), region_height, draw.yaw, tint, 2, draw.base + region_base, light_anchor = anchor, use_light_anchor = anchored, light_group = group)}}
	show_roof := house_roof_visible(g)
	if show_roof {for i in 0 ..< generated_roof_count {story := generated_roof_story[i]; if story != level_document.active_story && !(show_below && story < level_document.active_story) do continue; roof := &generated_roof_meshes[i]; if !roof.ready do continue; alpha := u8(clamp(int((1 - g.cutaway_transition) * 255), 0, 255)); if alpha < 255 do continue; cx, cz := (roof.min.x + roof.max.x) * .5, (roof.min.z + roof.max.z) * .5; height := max(roof.max.y - roof.min.y, .001); vk_world_add(scene, ctx, roof, cx, cz, height, 0, {235, 239, 242, 255}, false, 16, generated_roof_base_y[i]); if generated_roof_has_gutters[i] {gutter := &generated_roof_gutter_meshes[i]; gx, gz := (gutter.min.x + gutter.max.x) * .5, (gutter.min.z + gutter.max.z) * .5; vk_world_add(scene, ctx, gutter, gx, gz, .14, 0, {105, 116, 120, 255}, false, 16, generated_roof_base_y[i] - .10)}}}
	if g.editor_mode ==
	   .Build {for i in 0 ..< generated_link_count {story := generated_link_story[i]; if story != level_document.active_story && !(show_below && story < level_document.active_story) do continue; stairs := &generated_link_meshes[i]; if !stairs.ready do continue; cx, cz := (stairs.min.x + stairs.max.x) * .5, (stairs.min.z + stairs.max.z) * .5; height := max(stairs.max.y - stairs.min.y, .001); vk_world_add(scene, ctx, stairs, cx, cz, height, 0, {151, 104, 66, 255}, false, 0, generated_link_base_y[i])}}
	for i in 0 ..< generated_path_count {mesh := &generated_path_meshes[i]; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {118, 130, 137, 255}, false, 11, mesh.min.y)}; if level_document.active_story == 0 {for i in 0 ..< generated_water_count {mesh := &generated_water_meshes[i]; cx, cz := (mesh.min.x + mesh.max.x) * .5, (mesh.min.z + mesh.max.z) * .5; vk_world_add(scene, ctx, mesh, cx, cz, max(mesh.max.y - mesh.min.y, .001), 0, {255, 255, 255, 255}, false, 17, mesh.min.y)}}
	scene.profile_house_structure_ms =
		time.duration_seconds(time.tick_diff(house_phase_started, time.tick_now())) * 1000
	scene.profile_house_walls_ms =
		time.duration_seconds(time.tick_diff(structure_phase_started, time.tick_now())) * 1000
	house_phase_started = time.tick_now()
	for opening in house_plan.openings {
		dx, dz :=
			opening.b.x -
			opening.a.x,
			opening.b.y -
			opening.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do continue
		wall_yaw := f32(
			math.atan2(f64(dz), f64(dx)),
		); wall_height := house_opening_wall_height(g, opening)
		if opening.kind == .Window {
			mx, mz := (opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5
			opening_sill_mesh := house_opening_sill_mesh(
				opening,
			); opening_header_mesh := house_opening_header_mesh(opening)
			nx, nz :=
				-dz /
				length,
				dx /
				length; face_offset := house_wall_width(opening.wall_width) * .5 + .026
			// Cutaway changes only the masonry aperture. A window is an authored object,
			// like a door leaf, so it keeps its complete proportions and may remain
			// suspended after the host wall descends below it.
			wall_aperture_top := house_opening_aperture_top(g, opening)
			sill_height :=
				opening.sill_height > 0 ? opening.sill_height : f32(.72); glass_height := max(opening.height, f32(0)); rail := f32(HOUSE_WINDOW_FRAME_RAIL_HEIGHT)
			aperture_top := sill_height + glass_height + rail + .10
			glass_width := max(
				length - rail * 2,
				.01,
			); vertical_height := max(min(glass_height + rail * 2, aperture_top - (sill_height - .04)), f32(0)); side_offset := max(length * .5 - rail * .5, f32(0)); light_columns, light_rows := house_window_style_grid(opening.window_style, length, glass_height)
			// Restore opaque masonry only below and above the unioned aperture.
			masonry_width := length + HOUSE_OPENING_CUT_END_EXTENSION * 2
			lower_masonry_height := house_window_lower_masonry_height(
				sill_height,
				wall_height,
			); if lower_masonry_height > .001 do vk_world_add_sized(scene, ctx, opening_sill_mesh, mx, mz, masonry_width, lower_masonry_height, wall_yaw, {255, 255, 255, 255}, 0, active_base, no_shadow = true)
			header_base :=
				active_base +
				sill_height +
				glass_height; header_height := max(wall_aperture_top - (sill_height + glass_height), f32(0)); if header_height > 0 {
				vk_world_add_sized(
					scene,
					ctx,
					opening_header_mesh,
					mx,
					mz,
					masonry_width,
					header_height,
					wall_yaw,
					{255, 255, 255, 255},
					0,
					header_base,
					no_shadow = true,
				)
				// Window apertures split the host wall and its cap at both jambs. Close
				// the restored masonry header with the same two-layer section cap.
				host := house_opening_host_wall_index(
					opening,
				); amount := house_wall_section_amount(g, host); cap_y := active_base + wall_aperture_top; cap_mesh := &house_window_header_cap_mesh; if host >= 0 && host < len(house_walls) do cap_mesh = &house_walls[host].cap
				// Reuse the host section's cap mesh so authored thin walls retain their
				// actual depth; a house-wide default-depth cap visibly overhung them.
				vk_world_add_sized(
					scene,
					ctx,
					cap_mesh,
					mx,
					mz,
					length + HOUSE_WALL_CAP_EDGE_OVERHANG,
					house_wall_cap_draw_height(cap_mesh),
					wall_yaw,
					house_wall_cap_edge_tint(amount),
					6,
					cap_y + .004,
				)
				vk_world_add_sized(
					scene,
					ctx,
					cap_mesh,
					mx,
					mz,
					length,
					house_wall_cap_draw_height(cap_mesh),
					wall_yaw,
					house_wall_section_tint(amount),
					6,
					cap_y + .008,
				)
			}
			// The square-capped plan cut also extends beyond both authored jambs.
			// Restore those vertical masonry shoulders through the glazing band; the
			// sill/header above already own the same overlap at their elevations.
			jamb_masonry_base :=
				active_base +
				sill_height -
				.04; jamb_masonry_height := max(min(glass_height + .08, wall_aperture_top - (sill_height - .04)), f32(.08)); jamb_half := HOUSE_OPENING_CUT_END_EXTENSION * .5; tx, tz := dx / length, dz / length
			vk_world_add_sized(
				scene,
				ctx,
				opening_header_mesh,
				opening.a.x - tx * jamb_half,
				opening.a.y - tz * jamb_half,
				HOUSE_OPENING_CUT_END_EXTENSION,
				jamb_masonry_height,
				wall_yaw,
				{255, 255, 255, 255},
				0,
				jamb_masonry_base,
				no_shadow = true,
			)
			vk_world_add_sized(
				scene,
				ctx,
				opening_header_mesh,
				opening.b.x + tx * jamb_half,
				opening.b.y + tz * jamb_half,
				HOUSE_OPENING_CUT_END_EXTENSION,
				jamb_masonry_height,
				wall_yaw,
				{255, 255, 255, 255},
				0,
				jamb_masonry_base,
				no_shadow = true,
			)
			// The host wall is already split at the window jambs, so its section caps
			// stop on either side of the opening. Do not bridge those caps across the
			// aperture when the cutaway drops below the glazing: that would intersect
			// the sash and read as a solid wall slab passing through the window.
			// Full-depth returns bridge the two face-mounted frames and give the
			// opening a readable sill, jamb, and head instead of an exposed wall cut.
			if glass_height >
			   .12 {trim_tint := [4]u8{196, 198, 190, 255}; sill_cap_base := active_base + sill_height - .055; vk_world_add_sized(scene, ctx, &house_window_sill_cap_mesh, mx, mz, length + .20, .07, wall_yaw, trim_tint, 14, sill_cap_base); head_trim_base := active_base + min(sill_height + glass_height - .025, aperture_top - .08); vk_world_add_sized(scene, ctx, &house_window_head_return_mesh, mx, mz, length + .16, .08, wall_yaw, trim_tint, 14, head_trim_base); jamb_base := active_base + sill_height - .04; jamb_height := max(min(glass_height + .08, aperture_top - (sill_height - .04)), f32(.08)); vk_world_add_sized(scene, ctx, &house_window_jamb_return_mesh, opening.a.x, opening.a.y, .08, jamb_height, wall_yaw, trim_tint, 14, jamb_base); vk_world_add_sized(scene, ctx, &house_window_jamb_return_mesh, opening.b.x, opening.b.y, .08, jamb_height, wall_yaw, trim_tint, 14, jamb_base)}
			if opening.id == "window_study_courtyard" && wall_height < wall_aperture_top - .001 {
				return_height :=
					wall_aperture_top -
					wall_height; return_width := f32(.12); return_base := active_base + wall_height
				vk_world_add_sized(
					scene,
					ctx,
					opening_header_mesh,
					opening.a.x,
					opening.a.y,
					return_width,
					return_height,
					wall_yaw,
					{255, 255, 255, 255},
					0,
					return_base,
				)
				vk_world_add_sized(
					scene,
					ctx,
					opening_header_mesh,
					opening.b.x,
					opening.b.y,
					return_width,
					return_height,
					wall_yaw,
					{255, 255, 255, 255},
					0,
					return_base,
				)
			}
			// One sash and glazing unit sits within the opening depth. Interior and
			// exterior finish casing remain separate, but the rear sash is no longer
			// visible through a duplicate pane.
			nominal_top :=
				sill_height +
				.01 +
				glass_height; top_base := min(nominal_top, aperture_top - rail); clipped_head := top_base < nominal_top - .001; top_tint := clipped_head ? [4]u8{168, 174, 170, 255} : [4]u8{49, 57, 59, 255}; top_kind := clipped_head ? 6 : 14
			room_sign := house_window_room_sign(
				opening.a,
				opening.b,
			); if opening.window_flipped do room_sign = -room_sign
			sash_plane_offset := house_window_operable_sash_offset(
				opening.window_style,
			); sash_x, sash_z := mx + nx * sash_plane_offset * room_sign, mz + nz * sash_plane_offset * room_sign
			// Glazing is submitted after the opaque window assembly below. The world
			// pipeline still writes depth for blended materials, so drawing glass here
			// would hide an exterior shutter when the window is viewed from indoors.
			if opening.window_style == .Double_Hung && glass_height > .20 {
				sash_offset := house_window_double_hung_sash_offset(

				); lower_x, lower_z := mx + nx * sash_offset * room_sign, mz + nz * sash_offset * room_sign; upper_x, upper_z := mx - nx * sash_offset * room_sign, mz - nz * sash_offset * room_sign
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					lower_x,
					lower_z,
					length,
					rail,
					wall_yaw,
					{49, 57, 59, 255},
					14,
					active_base + sill_height - .03,
				)
				if top_base >= sill_height - .03 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, upper_x, upper_z, length, rail, wall_yaw, top_tint, top_kind, active_base + top_base)
			} else {
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					sash_x,
					sash_z,
					length,
					rail,
					wall_yaw,
					{49, 57, 59, 255},
					14,
					active_base + sill_height - .03,
				)
				if top_base >= sill_height - .03 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, sash_x, sash_z, length, rail, wall_yaw, top_tint, top_kind, active_base + top_base)
			}
			horizontal_member := house_window_internal_horizontal_width(
				opening.window_style,
				rail,
			); if opening.window_style == .Double_Hung && glass_height > .20 {meeting_y := sill_height + glass_height * .5; meeting_offset := house_window_double_hung_sash_offset(); lower_x, lower_z := mx + nx * meeting_offset * room_sign, mz + nz * meeting_offset * room_sign; upper_x, upper_z := mx - nx * meeting_offset * room_sign, mz - nz * meeting_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, lower_x, lower_z, length, rail, wall_yaw, {49, 57, 59, 255}, 14, active_base + meeting_y - rail * .42); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, upper_x, upper_z, length, rail, wall_yaw, {55, 63, 65, 255}, 14, active_base + meeting_y - rail * .58)} else {for row in 1 ..< light_rows {middle_base := sill_height - horizontal_member * .5 + glass_height * f32(row) / f32(light_rows); if middle_base + horizontal_member <= aperture_top do vk_world_add_sized(scene, ctx, &house_window_muntin_h_mesh, sash_x, sash_z, length, horizontal_member, wall_yaw, {55, 63, 65, 255}, 14, active_base + middle_base)}}
			if vertical_height > 0 {
				internal_vertical := house_window_internal_vertical_width(
					opening.window_style,
					rail,
				)
				if opening.window_style == .Double_Hung && glass_height > .20 {
					// The outer jamb remains continuous while each movable sash gets its
					// own half-height stiles and muntins in the sash's actual depth plane.
					jamb_signs := [2]f32 {
						-1,
						1,
					}; for sign in jamb_signs do vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + dx / length * side_offset * sign, mz + dz / length * side_offset * sign, rail, vertical_height, wall_yaw, {49, 57, 59, 255}, 14, active_base + sill_height - .04)
					half_glass :=
						glass_height *
						.5; sash_offset := house_window_double_hung_sash_offset(); sash_side := house_window_double_hung_stile_along(glass_width, rail); lower_x, lower_z := mx + nx * sash_offset * room_sign, mz + nz * sash_offset * room_sign; upper_x, upper_z := mx - nx * sash_offset * room_sign, mz - nz * sash_offset * room_sign
					for column in 0 ..= light_columns {along := -sash_side + sash_side * 2 * f32(column) / f32(light_columns); edge := column == 0 || column == light_columns; tint := edge ? [4]u8{49, 57, 59, 255} : [4]u8{55, 63, 65, 255}; member_width := edge ? rail : internal_vertical; member_mesh := edge ? &house_window_frame_v_mesh : &house_window_muntin_v_mesh; vk_world_add_sized(scene, ctx, member_mesh, lower_x + dx / length * along, lower_z + dz / length * along, member_width, half_glass, wall_yaw, tint, 14, active_base + sill_height); vk_world_add_sized(scene, ctx, member_mesh, upper_x + dx / length * along, upper_z + dz / length * along, member_width, half_glass, wall_yaw, tint, 14, active_base + sill_height + half_glass)}
				} else {for column in 0 ..= light_columns {along := -side_offset + side_offset * 2 * f32(column) / f32(light_columns); edge := column == 0 || column == light_columns; tint := edge ? [4]u8{49, 57, 59, 255} : [4]u8{55, 63, 65, 255}; member_width := edge ? rail : internal_vertical; member_mesh := edge ? &house_window_frame_v_mesh : &house_window_muntin_v_mesh; vk_world_add_sized(scene, ctx, member_mesh, sash_x + dx / length * along, sash_z + dz / length * along, member_width, vertical_height, wall_yaw, tint, 14, active_base + sill_height - .04)}}
			}
			if (opening.window_style == .Casement || opening.window_style == .Awning) &&
			   glass_height >
				   .12 {outer_width := house_window_operable_frame_width(rail); outer_side := max(length * .5 - outer_width * .5, f32(0)); outer_tint := [4]u8{66, 73, 74, 255}; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx - dx / length * outer_side, mz - dz / length * outer_side, outer_width, vertical_height, wall_yaw, outer_tint, 14, active_base + sill_height - .04); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + dx / length * outer_side, mz + dz / length * outer_side, outer_width, vertical_height, wall_yaw, outer_tint, 14, active_base + sill_height - .04); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx, mz, length, outer_width, wall_yaw, outer_tint, 14, active_base + sill_height - .03); if top_base >= sill_height - .03 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx, mz, length, outer_width, wall_yaw, outer_tint, 14, active_base + top_base + rail - outer_width); mullion_count := house_window_operable_mullion_count(opening.window_style, light_columns); if mullion_count > 0 {for mullion in 1 ..= mullion_count {along := -side_offset + side_offset * 2 * f32(mullion) / f32(mullion_count + 1); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + dx / length * along, mz + dz / length * along, outer_width, vertical_height, wall_yaw, outer_tint, 14, active_base + sill_height - .04)}}}
			if opening.window_style == .Double_Hung &&
			   glass_height >
				   .20 {parting_width := house_window_double_hung_parting_bead_width(rail); parting_along := house_window_double_hung_parting_bead_along(glass_width, rail); parting_tint := [4]u8{62, 69, 70, 255}; vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, mx - dx / length * parting_along, mz - dz / length * parting_along, parting_width, glass_height, wall_yaw, parting_tint, 14, active_base + sill_height); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, mx + dx / length * parting_along, mz + dz / length * parting_along, parting_width, glass_height, wall_yaw, parting_tint, 14, active_base + sill_height)}
			// A narrow room-side glazing stop overlaps the pane perimeter. The small
			// proud offset gives the glass a seated edge and a readable shadow line.
			if glass_height > .04 && glass_width > .04 {
				bead := house_window_glazing_bead_width(
					rail,
				); frame_bead_offset := house_window_frame_v_mesh.max.z + .004; bead_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); bead_tint := [4]u8{72, 80, 81, 255}; bead_along := max(glass_width * .5 - bead * .5, f32(0))
				if opening.window_style == .Double_Hung && glass_height > .20 {
					half_glass :=
						glass_height *
						.5; lower_x, lower_z := mx + nx * frame_bead_offset * room_sign, mz + nz * frame_bead_offset * room_sign; upper_offset := house_window_double_hung_upper_bead_offset(frame_bead_offset); upper_x, upper_z := mx + nx * upper_offset * room_sign, mz + nz * upper_offset * room_sign
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_h_mesh,
						lower_x,
						lower_z,
						glass_width,
						bead,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height,
					); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, lower_x, lower_z, glass_width, bead, bead_yaw, bead_tint, 14, active_base + sill_height + half_glass - bead); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, lower_x - dx / length * bead_along, lower_z - dz / length * bead_along, bead, half_glass, bead_yaw, bead_tint, 14, active_base + sill_height); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, lower_x + dx / length * bead_along, lower_z + dz / length * bead_along, bead, half_glass, bead_yaw, bead_tint, 14, active_base + sill_height)
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_h_mesh,
						upper_x,
						upper_z,
						glass_width,
						bead,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height + half_glass,
					); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, upper_x, upper_z, glass_width, bead, bead_yaw, bead_tint, 14, active_base + sill_height + glass_height - bead); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, upper_x - dx / length * bead_along, upper_z - dz / length * bead_along, bead, half_glass, bead_yaw, bead_tint, 14, active_base + sill_height + half_glass); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, upper_x + dx / length * bead_along, upper_z + dz / length * bead_along, bead, half_glass, bead_yaw, bead_tint, 14, active_base + sill_height + half_glass)
				} else {bead_x, bead_z :=
						mx +
						nx * (frame_bead_offset + sash_plane_offset) * room_sign,
						mz +
						nz * (frame_bead_offset + sash_plane_offset) * room_sign
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_h_mesh,
						bead_x,
						bead_z,
						glass_width,
						bead,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height,
					)
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_h_mesh,
						bead_x,
						bead_z,
						glass_width,
						bead,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height + glass_height - bead,
					)
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_v_mesh,
						bead_x - dx / length * bead_along,
						bead_z - dz / length * bead_along,
						bead,
						glass_height,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height,
					)
					vk_world_add_sized(
						scene,
						ctx,
						&house_window_bead_v_mesh,
						bead_x + dx / length * bead_along,
						bead_z + dz / length * bead_along,
						bead,
						glass_height,
						bead_yaw,
						bead_tint,
						14,
						active_base + sill_height,
					)}
			}
			// The room face receives a flat stool and apron; the weather face receives
			// a projecting, sloped sill and a separate underside drip edge.
			apron_height := min(
				f32(.16),
				max(sill_height - .08, f32(0)),
			); drip_height := f32(.045); drip_base := top_base + rail; inside_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); inside_x, inside_z := mx + nx * face_offset * room_sign, mz + nz * face_offset * room_sign
			if apron_height > .01 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, inside_x, inside_z, max(length - .10, f32(.08)), apron_height, inside_yaw, {181, 184, 178, 255}, 14, active_base + sill_height - .07 - apron_height)
			stool_offset :=
				face_offset +
				.075; stool_x, stool_z := mx + nx * stool_offset * room_sign, mz + nz * stool_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, stool_x, stool_z, length + .24, .038, inside_yaw, {202, 203, 197, 255}, 14, active_base + sill_height - .038)
			exterior_sign := -room_sign; exterior_yaw := exterior_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); exterior_sill_offset := face_offset + .07; exterior_x, exterior_z := mx + nx * exterior_sill_offset * exterior_sign, mz + nz * exterior_sill_offset * exterior_sign; vk_world_add_sized(scene, ctx, &house_window_exterior_sill_mesh, exterior_x, exterior_z, length + .24, .07, exterior_yaw, {188, 192, 188, 255}, 14, active_base + sill_height - .055); drip_x, drip_z := mx + nx * (face_offset + .145) * exterior_sign, mz + nz * (face_offset + .145) * exterior_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, drip_x, drip_z, length + .20, .018, exterior_yaw, {162, 168, 166, 255}, 14, active_base + sill_height - .071)
			// A compact head casing remains readable from both faces.
			// Face-applied jamb casing overlaps the finish cut on both sides. Interior
			// trim is broader; the weather face uses a tighter brick-mould profile.
			casing_base :=
				sill_height -
				.07; casing_top := min(aperture_top, top_base + rail + drip_height); casing_height := max(casing_top - casing_base, f32(0)); face_signs := [2]f32{1, -1}; for sign in face_signs {interior := sign == room_sign; casing_width := house_window_casing_width(interior); casing_offset := face_offset + .012; ox, oz := nx * casing_offset * sign, nz * casing_offset * sign; yaw := sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); casing_tint := interior ? [4]u8{198, 200, 194, 255} : [4]u8{176, 181, 178, 255}; if casing_height > .01 {left_x, left_z := opening.a.x + ox - dx / length * casing_width * .5, opening.a.y + oz - dz / length * casing_width * .5; right_x, right_z := opening.b.x + ox + dx / length * casing_width * .5, opening.b.y + oz + dz / length * casing_width * .5; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, left_x, left_z, casing_width, casing_height, yaw, casing_tint, 14, active_base + casing_base); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, right_x, right_z, casing_width, casing_height, yaw, casing_tint, 14, active_base + casing_base)}; if !clipped_head && drip_base + drip_height <= aperture_top + .001 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx + ox, mz + oz, length + casing_width * 2, drip_height, yaw, casing_tint, 14, active_base + drip_base)}
			if casing_height >
			   .01 {sealant_width := house_window_perimeter_sealant_width(); exterior_casing := house_window_casing_width(false); sealant_offset := face_offset + .004; sealant_x, sealant_z := mx + nx * sealant_offset * exterior_sign, mz + nz * sealant_offset * exterior_sign; sealant_along := length * .5 + exterior_casing + sealant_width * .5; sealant_tint := [4]u8{104, 110, 108, 255}; vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, sealant_x - dx / length * sealant_along, sealant_z - dz / length * sealant_along, sealant_width, casing_height, exterior_yaw, sealant_tint, 14, active_base + casing_base); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, sealant_x + dx / length * sealant_along, sealant_z + dz / length * sealant_along, sealant_width, casing_height, exterior_yaw, sealant_tint, 14, active_base + casing_base); sealant_head_width := length + (exterior_casing + sealant_width) * 2; vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, sealant_x, sealant_z, sealant_head_width, sealant_width, exterior_yaw, sealant_tint, 14, active_base + casing_top - sealant_width)}
			if casing_height >
			   .01 {caulk_width := house_window_interior_caulk_width(); interior_casing := house_window_casing_width(true); caulk_offset := face_offset + .004; caulk_x, caulk_z := mx + nx * caulk_offset * room_sign, mz + nz * caulk_offset * room_sign; caulk_along := length * .5 + interior_casing + caulk_width * .5; caulk_tint := [4]u8{181, 184, 178, 255}; vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, caulk_x - dx / length * caulk_along, caulk_z - dz / length * caulk_along, caulk_width, casing_height, inside_yaw, caulk_tint, 14, active_base + casing_base); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, caulk_x + dx / length * caulk_along, caulk_z + dz / length * caulk_along, caulk_width, casing_height, inside_yaw, caulk_tint, 14, active_base + casing_base); caulk_head_width := length + (interior_casing + caulk_width) * 2; vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, caulk_x, caulk_z, caulk_head_width, caulk_width, inside_yaw, caulk_tint, 14, active_base + casing_top - caulk_width)}
			if !clipped_head && drip_base + drip_height <= aperture_top + .001 {
				flashing_offset :=
					face_offset +
					.06; flashing_x, flashing_z := mx + nx * flashing_offset * exterior_sign, mz + nz * flashing_offset * exterior_sign; flashing_width := length + house_window_head_flashing_overhang() * 2; flashing_base := active_base + drip_base + drip_height - .004
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					flashing_x,
					flashing_z,
					flashing_width,
					.022,
					exterior_yaw,
					{154, 162, 162, 255},
					14,
					flashing_base,
				); flashing_lip_x, flashing_lip_z := mx + nx * (flashing_offset + .028) * exterior_sign, mz + nz * (flashing_offset + .028) * exterior_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, flashing_lip_x, flashing_lip_z, flashing_width, .026, exterior_yaw, {142, 150, 150, 255}, 14, active_base + drip_base + .012)
				dam_width := house_window_head_flashing_end_dam_width(

				); dam_height := house_window_head_flashing_end_dam_height(); dam_along := flashing_width * .5 - dam_width * .5; dam_tint := [4]u8{148, 156, 156, 255}; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, flashing_x - dx / length * dam_along, flashing_z - dz / length * dam_along, dam_width, dam_height, exterior_yaw, dam_tint, 14, flashing_base); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, flashing_x + dx / length * dam_along, flashing_z + dz / length * dam_along, dam_width, dam_height, exterior_yaw, dam_tint, 14, flashing_base)
			}
			// Operable hardware is mounted only on the room-facing side.
			hardware_offset := house_window_hardware_offset(

			); hardware_x, hardware_z := mx + nx * hardware_offset * room_sign, mz + nz * hardware_offset * room_sign; hardware_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); hardware_tint := [4]u8{151, 121, 66, 255}; switch opening.window_style {
			case .Casement:
				if glass_height >
				   .30 {handle_count, hinge_side_count := house_window_casement_hardware_count(light_columns); for handle_index in 0 ..< handle_count {handle_along := house_window_casement_handle_along(light_columns, handle_index, side_offset, rail, opening.window_hinge_right); vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hardware_x + dx / length * handle_along, hardware_z + dz / length * handle_along, .025, .16, hardware_yaw, hardware_tint, 14, active_base + sill_height + glass_height * .46)}; for hinge_index in 0 ..< hinge_side_count {hinge_along := house_window_casement_hinge_along(light_columns, hinge_index, side_offset, rail, opening.window_hinge_right); hinge_x, hinge_z := hardware_x + dx / length * hinge_along, hardware_z + dz / length * hinge_along; vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hinge_x, hinge_z, .028, .07, hardware_yaw, hardware_tint, 14, active_base + sill_height + glass_height * .24); vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hinge_x, hinge_z, .028, .07, hardware_yaw, hardware_tint, 14, active_base + sill_height + glass_height * .72)}}
			case .Awning:
				if glass_height >
				   .30 {vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x, hardware_z, .20, .025, hardware_yaw, hardware_tint, 14, active_base + sill_height + .10); pivot_offset := min(length * .24, f32(.42)); pivot_base := active_base + sill_height + glass_height - .055; vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x - dx / length * pivot_offset, hardware_z - dz / length * pivot_offset, .08, .024, hardware_yaw, hardware_tint, 14, pivot_base); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x + dx / length * pivot_offset, hardware_z + dz / length * pivot_offset, .08, .024, hardware_yaw, hardware_tint, 14, pivot_base)}
			case .Double_Hung:
				if glass_height >
				   .45 {lift_offset := min(length * .18, f32(.28)); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x - dx / length * lift_offset, hardware_z - dz / length * lift_offset, .12, .022, hardware_yaw, hardware_tint, 14, active_base + sill_height + .10); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x + dx / length * lift_offset, hardware_z + dz / length * lift_offset, .12, .022, hardware_yaw, hardware_tint, 14, active_base + sill_height + .10); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x, hardware_z, .14, .026, hardware_yaw, hardware_tint, 14, active_base + sill_height + glass_height * .5 - .013)}
			case .Fixed, .Picture:
			}
			if opening.id == "window_study_courtyard" {
				outside_sign := f32(
					-1,
				); ox, oz := nx * (face_offset + .07) * outside_sign, nz * (face_offset + .07) * outside_sign
				shutter_x, shutter_z :=
					mx +
					ox,
					mz +
					oz; shutter_yaw := outside_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI)
				// Dedicated rails and a shallow top cassette turn the louvers into a
				// coherent exterior mechanism instead of a stack of floating boards.
				rail_tint := [4]u8 {
					42,
					48,
					46,
					255,
				}; rail_width := f32(.07); rail_height := min(aperture_top - sill_height, f32(1.42)); rail_along := length * .5 + rail_width * .36
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_v_mesh,
					shutter_x - dx / length * rail_along,
					shutter_z - dz / length * rail_along,
					rail_width,
					rail_height,
					shutter_yaw,
					rail_tint,
					15,
					active_base + sill_height,
				)
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_v_mesh,
					shutter_x + dx / length * rail_along,
					shutter_z + dz / length * rail_along,
					rail_width,
					rail_height,
					shutter_yaw,
					rail_tint,
					15,
					active_base + sill_height,
				)
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					shutter_x,
					shutter_z,
					length + rail_width * 2,
					.16,
					shutter_yaw,
					{47, 54, 51, 255},
					15,
					active_base + aperture_top - .08,
				)
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					shutter_x,
					shutter_z,
					length + rail_width * 1.2,
					.045,
					shutter_yaw,
					{67, 73, 69, 255},
					15,
					active_base + sill_height - .022,
				)
				// Paired locking dogs slide into the bottom catch at full closure and
				// retract toward their guide rails as the louvers open.
				lock_phase := clamp(
					(.12 - g.shutter_position) / .12,
					0,
					1,
				); engagement := lock_phase * lock_phase * (3 - 2 * lock_phase); latch_travel := (1 - engagement) * .065; latch_tint := [4]u8{u8(70 + 120 * engagement), u8(75 + 75 * engagement), u8(68 + 10 * engagement), 255}; latch_offsets := [2]f32{-length * .5 + .11 - latch_travel, length * .5 - .11 + latch_travel}; for latch_along in latch_offsets {latch_x, latch_z := shutter_x + dx / length * latch_along, shutter_z + dz / length * latch_along; vk_world_add(scene, ctx, &shutter_crank_link_mesh, latch_x, latch_z, .065, wall_yaw, latch_tint, false, 15, active_base + sill_height + .012)}
				// Interlocked rolling-shutter slats remain in one curtain as they rise;
				// they flex slightly under load but do not rotate open like Venetian
				// blinds. The flex returns to zero at both travel limits.
				travel_position := clamp(
					g.shutter_position,
					0,
					1,
				); slat_pitch := f32(math.sin(f64(travel_position * f32(math.PI)))) * .10
				slat_travel := travel_position * rail_height
				// The weighted terminal bar is the leading edge of a real rolling
				// shutter. It makes partial travel unambiguous and keeps both sides
				// synchronized in their guide rails.
				terminal_y :=
					active_base +
					sill_height +
					slat_travel; if terminal_y + .06 < active_base + aperture_top - .02 {
					terminal_x, terminal_z :=
						shutter_x +
						nx * .014 * outside_sign,
						shutter_z +
						nz *
							.014 *
							outside_sign; terminal_tint := [4]u8{116, 105, 76, 255}; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, terminal_x, terminal_z, length - .015, .066, shutter_yaw, terminal_tint, 15, terminal_y)
					shoe_offsets := [2]f32 {
						-length * .5 + .035,
						length * .5 - .035,
					}; for shoe_along in shoe_offsets {shoe_x, shoe_z := shutter_x + dx / length * shoe_along, shutter_z + dz / length * shoe_along; vk_world_add(scene, ctx, &shutter_crank_link_mesh, shoe_x, shoe_z, .068, wall_yaw, {116, 91, 48, 255}, false, 15, terminal_y - .005)}
				}
				for slat in 0 ..< 11 {
					slat_y := active_base + sill_height + .005 + f32(slat) * .127 + slat_travel
					if slat_y + .124 <= active_base + aperture_top + .001 {
						slat_tint :=
							slat % 2 == 0 ? [4]u8{54, 61, 57, 255} : [4]u8{59, 66, 62, 255}; vk_world_add(scene, ctx, &house_shutter_slat_mesh, shutter_x, shutter_z, .124, wall_yaw, slat_tint, false, 15, slat_y, slat_pitch)
						// A recessed lower-edge seam keeps each interlocking steel slat
						// legible when the shutter is face-on and fully closed.
						if g.shutter_position < .92 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, shutter_x, shutter_z, length - .035, .009, shutter_yaw, {31, 37, 35, 255}, 15, slat_y + .116)
					}
				}
			}
			// Composite the transparent pane over the complete opaque assembly. Depth
			// testing keeps nearer slats in front from outside, while the pane blends
			// over the same solid slats instead of erasing them from the room side.
			if glass_height >
			   0 {if opening.window_style == .Double_Hung && glass_height > .20 {sash_offset := house_window_double_hung_sash_offset(); half_glass := glass_height * .5; lower_x, lower_z := mx + nx * sash_offset * room_sign, mz + nz * sash_offset * room_sign; upper_x, upper_z := mx - nx * sash_offset * room_sign, mz - nz * sash_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_mesh, lower_x, lower_z, glass_width, half_glass, wall_yaw, {94, 145, 174, 122}, 12, active_base + sill_height); vk_world_add_sized(scene, ctx, &house_window_mesh, upper_x, upper_z, glass_width, half_glass, wall_yaw, {94, 145, 174, 122}, 12, active_base + sill_height + half_glass)} else do vk_world_add_sized(scene, ctx, &house_window_mesh, sash_x, sash_z, glass_width, glass_height, wall_yaw, {94, 145, 174, 122}, 12, active_base + sill_height)}
		} else {
			door_openness := runtime_door_opening(g, opening)
			// The plan union removes openings through the full wall height. Put back
			// the lintel masonry above the authored door, clipped by cutaway height.
			header_x, header_z :=
				(opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5
			leaf_height := house_door_render_height(
				opening,
			); header_height := max(wall_height - leaf_height, f32(0))
			if header_height >
			   .001 {vk_world_add_sized(scene, ctx, house_opening_header_mesh(opening), header_x, header_z, length + .18, header_height, wall_yaw, {255, 255, 255, 255}, 0, active_base + leaf_height); vk_world_add_sized(scene, ctx, house_opening_cap_edge_mesh(opening), header_x, header_z, length + .18, .001, wall_yaw, house_wall_section_tint(house_wall_section_amount(g, house_opening_host_wall_index(opening))), 6, active_base + wall_height + .012)}
			// The leaf remains complete and readable during cutaway, while its
			// wall-mounted casing is clipped continuously by the host wall plane.
			frame_rail :=
				HOUSE_DOOR_CASING_RAIL; jamb_height := house_door_casing_jamb_height(opening, wall_height); head_base := house_door_casing_head_base(opening); head_height := house_door_casing_head_height(opening, wall_height); nx, nz := -dz / length, dx / length; face_offset := house_wall_width(opening.wall_width) * .5 + .028; along := max(length * .5 - frame_rail * .5, f32(0)); frame_tint := [4]u8{91, 68, 50, 255}
			frame_signs := [2]f32{1, -1}; for sign in frame_signs {
				ox, oz :=
					nx *
					face_offset *
					sign,
					nz *
					face_offset *
					sign; yaw := sign > 0 ? wall_yaw : wall_yaw + f32(math.PI)
				if jamb_height >
				   .001 {vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, header_x + ox - dx / length * along, header_z + oz - dz / length * along, frame_rail, jamb_height, yaw, frame_tint, 14, active_base); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, header_x + ox + dx / length * along, header_z + oz + dz / length * along, frame_rail, jamb_height, yaw, frame_tint, 14, active_base)}
				if head_height > .001 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, header_x + ox, header_z + oz, length + frame_rail, head_height, yaw, frame_tint, 14, active_base + head_base)
			}
			// Leaves are authored objects. Cutaway never changes either axis; style
			// controls only how the complete aperture width is divided and posed.
			leaf_widths: [2]f32; leaf_x, leaf_z: [2]f32; leaf_yaws: [2]f32; handle_xs, handle_zs: [2]f32; leaf_count := 1
			switch opening.door_style {
			case .Double:
				leaf_count = 2; half := house_door_render_width(length) * .5
				left_yaw := wall_yaw + f32(math.PI) * .42 * door_openness
				right_yaw := wall_yaw + f32(math.PI) - f32(math.PI) * .42 * door_openness
				leaf_widths = {half, half}
				leaf_yaws = {left_yaw, right_yaw}
				leaf_x = {
					opening.a.x + f32(math.cos(f64(left_yaw))) * half * .5,
					opening.b.x + f32(math.cos(f64(right_yaw))) * half * .5,
				}
				leaf_z = {
					opening.a.y + f32(math.sin(f64(left_yaw))) * half * .5,
					opening.b.y + f32(math.sin(f64(right_yaw))) * half * .5,
				}
				for i in 0 ..< 2 {handle_xs[i] = leaf_x[i] + f32(math.cos(f64(leaf_yaws[i]))) * half * (HOUSE_DOOR_HANDLE_ALONG - .5); handle_zs[i] = leaf_z[i] + f32(math.sin(f64(leaf_yaws[i]))) * half * (HOUSE_DOOR_HANDLE_ALONG - .5)}
			case .Sliding:
				leaf_count = 2; half := house_door_render_width(length) * .5
				ux, uz := dx / length, dz / length
				track_offset := f32(.038)
				// Stack the moving panel over the fixed panel. The other half of the
				// aperture stays visibly open and matches the authored navigation gap.
				closed_x, closed_z := opening.b.x - ux * half * .5, opening.b.y - uz * half * .5
				stack_x, stack_z := opening.a.x + ux * half * .5, opening.a.y + uz * half * .5
				moving_x, moving_z :=
					closed_x +
					(stack_x - closed_x) * door_openness,
					closed_z +
					(stack_z - closed_z) * door_openness
				leaf_widths = {half, half}
				leaf_yaws = {wall_yaw, wall_yaw}
				leaf_x = {moving_x + nx * track_offset, stack_x - nx * track_offset}
				leaf_z = {moving_z + nz * track_offset, stack_z - nz * track_offset}
				handle_xs = {
					leaf_x[0] + ux * (half * .5 - .10),
					leaf_x[1] + ux * (half * .5 - .16),
				}
				handle_zs = {
					leaf_z[0] + uz * (half * .5 - .10),
					leaf_z[1] + uz * (half * .5 - .16),
				}
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					header_x,
					header_z,
					length + .08,
					.045,
					wall_yaw,
					frame_tint,
					14,
					active_base + .01,
				)
				vk_world_add_sized(
					scene,
					ctx,
					&house_window_frame_h_mesh,
					header_x,
					header_z,
					length + .08,
					.045,
					wall_yaw,
					frame_tint,
					14,
					active_base + leaf_height - .045,
				)
			case .Hinged:
				width := house_door_render_width(length)
				swing_sign := opening.window_hinge_right ? f32(-1) : f32(1)
				hinge := opening.window_hinge_right ? opening.b : opening.a
				yaw := wall_yaw + swing_sign * f32(math.PI) * .42 * door_openness
				if opening.window_hinge_right do yaw += f32(math.PI)
				leaf_widths[0] = width
				leaf_yaws[0] = yaw
				leaf_x[0] = hinge.x + f32(math.cos(f64(yaw))) * width * .5
				leaf_z[0] = hinge.y + f32(math.sin(f64(yaw))) * width * .5
				handle_xs[0] = hinge.x + f32(math.cos(f64(yaw))) * width * HOUSE_DOOR_HANDLE_ALONG
				handle_zs[0] = hinge.y + f32(math.sin(f64(yaw))) * width * HOUSE_DOOR_HANDLE_ALONG
			}
			handle_y :=
				active_base +
				house_door_handle_height(opening); handle_tint := [4]u8{157, 121, 57, 255}
			for i in 0 ..< leaf_count {
				vk_world_add_sized(
					scene,
					ctx,
					&house_door_meshes[opening.door_material],
					leaf_x[i],
					leaf_z[i],
					leaf_widths[i],
					leaf_height,
					leaf_yaws[i],
					{255, 255, 255, 255},
					0,
					active_base + .015,
				)
				handle_nx := -f32(
					math.sin(f64(leaf_yaws[i])),
				); handle_nz := f32(math.cos(f64(leaf_yaws[i]))); handle_signs := [2]f32{1, -1}; for sign in handle_signs {hx, hz := handle_xs[i] + handle_nx * .047 * sign, handle_zs[i] + handle_nz * .047 * sign; hyaw := sign > 0 ? leaf_yaws[i] : leaf_yaws[i] + f32(math.PI); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, hx, hz, .045, .14, hyaw, handle_tint, 14, handle_y - .07); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, hx + f32(math.cos(f64(leaf_yaws[i]))) * .045, hz + f32(math.sin(f64(leaf_yaws[i]))) * .045, .13, .025, hyaw, handle_tint, 14, handle_y - .0125)}
			}
		}
	}
	if g.editor_mode == .Build &&
	   (g.build_tool == .Door || g.build_tool == .Window) &&
	   editor_state.opening_active {
		command :=
			editor_state.opening_command; path_index := level_path_index(&level_document, command.material)
		if path_index >=
		   0 {path := level_document.paths[path_index]; segment := int(command.value); if segment >= 0 && segment < len(path.points) - 1 {a, b := path.points[segment], path.points[segment + 1]; dx, dz := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length > .001 {
					t :=
						command.c.x; mx, mz := a.x + dx * t, a.y + dz * t; wall_yaw := f32(math.atan2(f64(dz), f64(dx))); blocked := editor_state.opening_preview.state == .Blocked; tint := blocked ? [4]u8{244, 91, 91, 255} : [4]u8{96, 224, 156, 255}
					if g.build_tool == .Window {
						nx, nz :=
							-dz /
							length,
							dx /
							length; preview_width := command.b.y > 0 ? command.b.y : f32(1.6); preview_height := command.c.y > 0 ? command.c.y : f32(1.4); preview_sill := active_base + (command.points[0].x > 0 ? command.points[0].x : f32(.72)); preview_rail := f32(HOUSE_WINDOW_FRAME_RAIL_HEIGHT); preview_side := max(preview_width * .5 - preview_rail * .5, f32(0)); preview_vertical := preview_height + preview_rail * 2; preview_style := Window_Style(clamp(int(command.points[0].y), 0, int(Window_Style.Double_Hung))); preview_columns, preview_rows := house_window_style_grid(preview_style, preview_width, preview_height); room_sign := house_window_room_sign(a, b); if command.points[1].x > 0 do room_sign = -room_sign; preview_sash_offset := house_window_operable_sash_offset(preview_style); preview_sash_x, preview_sash_z := mx + nx * preview_sash_offset * room_sign, mz + nz * preview_sash_offset * room_sign
						// Double-hung previews expose the same overlapping sash depths as the
						// committed assembly; fixed glazing stays centered while casement and
						// awning sashes use their shallow operable offset.
						preview_glass_width := max(preview_width - preview_rail * 2, .01)
						if preview_style == .Double_Hung &&
						   preview_height >
							   .20 {sash_offset := house_window_double_hung_sash_offset(); half_glass := preview_height * .5; lower_x, lower_z := mx + nx * sash_offset * room_sign, mz + nz * sash_offset * room_sign; upper_x, upper_z := mx - nx * sash_offset * room_sign, mz - nz * sash_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_mesh, lower_x, lower_z, preview_glass_width, half_glass, wall_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_mesh, upper_x, upper_z, preview_glass_width, half_glass, wall_yaw, tint, 0, preview_sill + half_glass); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, lower_x, lower_z, preview_width, preview_rail, wall_yaw, tint, 0, preview_sill - preview_rail * .5); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, upper_x, upper_z, preview_width, preview_rail, wall_yaw, tint, 0, preview_sill + preview_height - preview_rail * .5)} else {vk_world_add_sized(scene, ctx, &house_window_mesh, preview_sash_x, preview_sash_z, preview_glass_width, preview_height, wall_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, preview_sash_x, preview_sash_z, preview_width, preview_rail, wall_yaw, tint, 0, preview_sill - preview_rail * .5); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, preview_sash_x, preview_sash_z, preview_width, preview_rail, wall_yaw, tint, 0, preview_sill + preview_height - preview_rail * .5)}
						preview_jamb_x, preview_jamb_z :=
							preview_style == .Double_Hung ? mx : preview_sash_x,
							preview_style == .Double_Hung ? mz : preview_sash_z; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, preview_jamb_x - dx / length * preview_side, preview_jamb_z - dz / length * preview_side, preview_rail, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, preview_jamb_x + dx / length * preview_side, preview_jamb_z + dz / length * preview_side, preview_rail, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail)
						preview_vertical_member := house_window_internal_vertical_width(
							preview_style,
							preview_rail,
						); preview_horizontal_member := house_window_internal_horizontal_width(preview_style, preview_rail)
						if preview_style == .Double_Hung &&
						   preview_height >
							   .20 {half_glass := preview_height * .5; sash_offset := house_window_double_hung_sash_offset(); sash_side := house_window_double_hung_stile_along(preview_glass_width, preview_rail); lower_x, lower_z := mx + nx * sash_offset * room_sign, mz + nz * sash_offset * room_sign; upper_x, upper_z := mx - nx * sash_offset * room_sign, mz - nz * sash_offset * room_sign; for column in 0 ..= preview_columns {along := -sash_side + sash_side * 2 * f32(column) / f32(preview_columns); edge := column == 0 || column == preview_columns; member_width := edge ? preview_rail : preview_vertical_member; member_mesh := edge ? &house_window_frame_v_mesh : &house_window_muntin_v_mesh; vk_world_add_sized(scene, ctx, member_mesh, lower_x + dx / length * along, lower_z + dz / length * along, member_width, half_glass, wall_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, member_mesh, upper_x + dx / length * along, upper_z + dz / length * along, member_width, half_glass, wall_yaw, tint, 0, preview_sill + half_glass)}} else {for column in 1 ..< preview_columns {along := -preview_side + preview_side * 2 * f32(column) / f32(preview_columns); vk_world_add_sized(scene, ctx, &house_window_muntin_v_mesh, preview_sash_x + dx / length * along, preview_sash_z + dz / length * along, preview_vertical_member, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail)}}
						if (preview_style == .Casement || preview_style == .Awning) &&
						   preview_height >
							   .12 {outer_width := house_window_operable_frame_width(preview_rail); outer_side := max(preview_width * .5 - outer_width * .5, f32(0)); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx - dx / length * outer_side, mz - dz / length * outer_side, outer_width, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + dx / length * outer_side, mz + dz / length * outer_side, outer_width, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx, mz, preview_width, outer_width, wall_yaw, tint, 0, preview_sill - preview_rail * .5); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx, mz, preview_width, outer_width, wall_yaw, tint, 0, preview_sill + preview_height + preview_rail * .5 - outer_width); mullion_count := house_window_operable_mullion_count(preview_style, preview_columns); if mullion_count > 0 {for mullion in 1 ..= mullion_count {along := -preview_side + preview_side * 2 * f32(mullion) / f32(mullion_count + 1); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + dx / length * along, mz + dz / length * along, outer_width, preview_vertical, wall_yaw, tint, 0, preview_sill - preview_rail)}}}
						if preview_style == .Double_Hung &&
						   preview_height >
							   .20 {parting_width := house_window_double_hung_parting_bead_width(preview_rail); parting_along := house_window_double_hung_parting_bead_along(preview_glass_width, preview_rail); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, mx - dx / length * parting_along, mz - dz / length * parting_along, parting_width, preview_height, wall_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, mx + dx / length * parting_along, mz + dz / length * parting_along, parting_width, preview_height, wall_yaw, tint, 0, preview_sill)}
						if preview_style == .Double_Hung &&
						   preview_height >
							   .20 {meeting_y := preview_sill + preview_height * .5; meeting_offset := house_window_double_hung_sash_offset(); lower_x, lower_z := mx + nx * meeting_offset * room_sign, mz + nz * meeting_offset * room_sign; upper_x, upper_z := mx - nx * meeting_offset * room_sign, mz - nz * meeting_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, lower_x, lower_z, preview_width, preview_rail, wall_yaw, tint, 0, meeting_y - preview_rail * .42); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, upper_x, upper_z, preview_width, preview_rail, wall_yaw, tint, 0, meeting_y - preview_rail * .58)} else {for row in 1 ..< preview_rows {row_base := preview_sill - preview_horizontal_member * .5 + preview_height * f32(row) / f32(preview_rows); vk_world_add_sized(scene, ctx, &house_window_muntin_h_mesh, preview_sash_x, preview_sash_z, preview_width, preview_horizontal_member, wall_yaw, tint, 0, row_base)}}
						bead := house_window_glazing_bead_width(
							preview_rail,
						); frame_bead_offset := house_window_frame_v_mesh.max.z + .004; bead_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); bead_along := max(preview_glass_width * .5 - bead * .5, f32(0))
						if preview_style == .Double_Hung &&
						   preview_height >
							   .20 {half_glass := preview_height * .5; lower_x, lower_z := mx + nx * (frame_bead_offset + preview_sash_offset) * room_sign, mz + nz * (frame_bead_offset + preview_sash_offset) * room_sign; upper_offset := house_window_double_hung_upper_bead_offset(frame_bead_offset); upper_x, upper_z := mx + nx * upper_offset * room_sign, mz + nz * upper_offset * room_sign; vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, lower_x, lower_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, lower_x, lower_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill + half_glass - bead); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, lower_x - dx / length * bead_along, lower_z - dz / length * bead_along, bead, half_glass, bead_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, lower_x + dx / length * bead_along, lower_z + dz / length * bead_along, bead, half_glass, bead_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, upper_x, upper_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill + half_glass); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, upper_x, upper_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill + preview_height - bead); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, upper_x - dx / length * bead_along, upper_z - dz / length * bead_along, bead, half_glass, bead_yaw, tint, 0, preview_sill + half_glass); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, upper_x + dx / length * bead_along, upper_z + dz / length * bead_along, bead, half_glass, bead_yaw, tint, 0, preview_sill + half_glass)} else {bead_x, bead_z := mx + nx * (frame_bead_offset + preview_sash_offset) * room_sign, mz + nz * (frame_bead_offset + preview_sash_offset) * room_sign; vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, bead_x, bead_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, bead_x, bead_z, preview_glass_width, bead, bead_yaw, tint, 0, preview_sill + preview_height - bead); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, bead_x - dx / length * bead_along, bead_z - dz / length * bead_along, bead, preview_height, bead_yaw, tint, 0, preview_sill); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, bead_x + dx / length * bead_along, bead_z + dz / length * bead_along, bead, preview_height, bead_yaw, tint, 0, preview_sill)}
						preview_face_offset := f32(
							HOUSE_WALL_THICKNESS * .5 + .038,
						); preview_casing_height := preview_height + preview_rail + .115; preview_signs := [2]f32{1, -1}; for sign in preview_signs {casing_width := house_window_casing_width(sign == room_sign); ox, oz := nx * preview_face_offset * sign, nz * preview_face_offset * sign; yaw := sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); casing_along := preview_width * .5 + casing_width * .5; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + ox - dx / length * casing_along, mz + oz - dz / length * casing_along, casing_width, preview_casing_height, yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, mx + ox + dx / length * casing_along, mz + oz + dz / length * casing_along, casing_width, preview_casing_height, yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, mx + ox, mz + oz, preview_width + casing_width * 2, .045, yaw, tint, 0, preview_sill + preview_height + preview_rail)}
						preview_apron := min(
							f32(.16),
							max(preview_sill - active_base - .08, f32(0)),
						); inside_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); caulk_width := house_window_interior_caulk_width(); interior_casing := house_window_casing_width(true); caulk_x, caulk_z := mx + nx * (preview_face_offset - .008) * room_sign, mz + nz * (preview_face_offset - .008) * room_sign; caulk_along := preview_width * .5 + interior_casing + caulk_width * .5; vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, caulk_x - dx / length * caulk_along, caulk_z - dz / length * caulk_along, caulk_width, preview_casing_height, inside_yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, caulk_x + dx / length * caulk_along, caulk_z + dz / length * caulk_along, caulk_width, preview_casing_height, inside_yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, caulk_x, caulk_z, preview_width + (interior_casing + caulk_width) * 2, caulk_width, inside_yaw, tint, 0, preview_sill + preview_height + preview_rail + .038); inside_x, inside_z := mx + nx * preview_face_offset * room_sign, mz + nz * preview_face_offset * room_sign; if preview_apron > .01 do vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, inside_x, inside_z, max(preview_width - .10, f32(.08)), preview_apron, inside_yaw, tint, 0, preview_sill - .07 - preview_apron); stool_x, stool_z := mx + nx * (preview_face_offset + .075) * room_sign, mz + nz * (preview_face_offset + .075) * room_sign; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, stool_x, stool_z, preview_width + .24, .038, inside_yaw, tint, 0, preview_sill - .038)
						exterior_sign := -room_sign; exterior_yaw := exterior_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); sealant_width := house_window_perimeter_sealant_width(); exterior_casing := house_window_casing_width(false); sealant_x, sealant_z := mx + nx * (preview_face_offset - .008) * exterior_sign, mz + nz * (preview_face_offset - .008) * exterior_sign; sealant_along := preview_width * .5 + exterior_casing + sealant_width * .5; vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, sealant_x - dx / length * sealant_along, sealant_z - dz / length * sealant_along, sealant_width, preview_casing_height, exterior_yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_bead_v_mesh, sealant_x + dx / length * sealant_along, sealant_z + dz / length * sealant_along, sealant_width, preview_casing_height, exterior_yaw, tint, 0, preview_sill - .07); vk_world_add_sized(scene, ctx, &house_window_bead_h_mesh, sealant_x, sealant_z, preview_width + (exterior_casing + sealant_width) * 2, sealant_width, exterior_yaw, tint, 0, preview_sill + preview_height + preview_rail + .035); exterior_x, exterior_z := mx + nx * (preview_face_offset + .07) * exterior_sign, mz + nz * (preview_face_offset + .07) * exterior_sign; vk_world_add_sized(scene, ctx, &house_window_exterior_sill_mesh, exterior_x, exterior_z, preview_width + .24, .07, exterior_yaw, tint, 0, preview_sill - .055); flashing_x, flashing_z := mx + nx * (preview_face_offset + .06) * exterior_sign, mz + nz * (preview_face_offset + .06) * exterior_sign; flashing_width := preview_width + house_window_head_flashing_overhang() * 2; flashing_base := preview_sill + preview_height + preview_rail + .041; vk_world_add_sized(scene, ctx, &house_window_frame_h_mesh, flashing_x, flashing_z, flashing_width, .022, exterior_yaw, tint, 0, flashing_base); dam_width := house_window_head_flashing_end_dam_width(); dam_along := flashing_width * .5 - dam_width * .5; vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, flashing_x - dx / length * dam_along, flashing_z - dz / length * dam_along, dam_width, house_window_head_flashing_end_dam_height(), exterior_yaw, tint, 0, flashing_base); vk_world_add_sized(scene, ctx, &house_window_frame_v_mesh, flashing_x + dx / length * dam_along, flashing_z + dz / length * dam_along, dam_width, house_window_head_flashing_end_dam_height(), exterior_yaw, tint, 0, flashing_base)
						hardware_offset := house_window_hardware_offset(

						); hardware_x, hardware_z := mx + nx * hardware_offset * room_sign, mz + nz * hardware_offset * room_sign; hardware_yaw := room_sign > 0 ? wall_yaw : wall_yaw + f32(math.PI); preview_hinge_right := command.points[1].y > 0; switch preview_style {case .Casement:
							if preview_height >
							   .30 {handle_count, hinge_side_count := house_window_casement_hardware_count(preview_columns); for handle_index in 0 ..< handle_count {handle_along := house_window_casement_handle_along(preview_columns, handle_index, preview_side, preview_rail, preview_hinge_right); vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hardware_x + dx / length * handle_along, hardware_z + dz / length * handle_along, .025, .16, hardware_yaw, tint, 0, preview_sill + preview_height * .46)}; for hinge_index in 0 ..< hinge_side_count {hinge_along := house_window_casement_hinge_along(preview_columns, hinge_index, preview_side, preview_rail, preview_hinge_right); hinge_x, hinge_z := hardware_x + dx / length * hinge_along, hardware_z + dz / length * hinge_along; vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hinge_x, hinge_z, .028, .07, hardware_yaw, tint, 0, preview_sill + preview_height * .24); vk_world_add_sized(scene, ctx, &house_window_hardware_v_mesh, hinge_x, hinge_z, .028, .07, hardware_yaw, tint, 0, preview_sill + preview_height * .72)}}; case .Awning:
							if preview_height >
							   .30 {vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x, hardware_z, .20, .025, hardware_yaw, tint, 0, preview_sill + .10); pivot_offset := min(preview_width * .24, f32(.42)); pivot_base := preview_sill + preview_height - .055; vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x - dx / length * pivot_offset, hardware_z - dz / length * pivot_offset, .08, .024, hardware_yaw, tint, 0, pivot_base); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x + dx / length * pivot_offset, hardware_z + dz / length * pivot_offset, .08, .024, hardware_yaw, tint, 0, pivot_base)}; case .Double_Hung:
							if preview_height >
							   .45 {lift_offset := min(preview_width * .18, f32(.28)); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x - dx / length * lift_offset, hardware_z - dz / length * lift_offset, .12, .022, hardware_yaw, tint, 0, preview_sill + .10); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x + dx / length * lift_offset, hardware_z + dz / length * lift_offset, .12, .022, hardware_yaw, tint, 0, preview_sill + .10); vk_world_add_sized(scene, ctx, &house_window_hardware_h_mesh, hardware_x, hardware_z, .14, .026, hardware_yaw, tint, 0, preview_sill + preview_height * .5 - .013)}; case .Fixed, .Picture:}
						vk_world_add_sized(
							scene,
							ctx,
							&house_window_sill_cap_mesh,
							mx,
							mz,
							preview_width + .20,
							.07,
							wall_yaw,
							tint,
							0,
							preview_sill - .055,
						)
					} else {open_yaw := wall_yaw + f32(math.PI) * .42
						leaf_length := command.b.y > 0 ? command.b.y : f32(1.2)
						leaf_x :=
							mx -
							dx / length * leaf_length * .5 +
							f32(math.cos(f64(open_yaw))) * leaf_length * .5
						leaf_z :=
							mz -
							dz / length * leaf_length * .5 +
							f32(math.sin(f64(open_yaw))) * leaf_length * .5
						preview_height := command.c.y > 0 ? command.c.y : f32(2.1)
						vk_world_add_sized(
							scene,
							ctx,
							&house_door_meshes[editor_state.door_material],
							leaf_x,
							leaf_z,
							leaf_length,
							preview_height,
							open_yaw,
							tint,
							0,
							.02,
						)}
				}}}
	}
	scene.profile_house_openings_ms =
		time.duration_seconds(time.tick_diff(house_phase_started, time.tick_now())) * 1000
	house_phase_started = time.tick_now()
	for item in house_plan.furniture {base := active_base + item.elevation; position := Vec2{item.x, item.y}; if level_terrain_supports_position(&level_document, position, level_document.active_story) do base += level_terrain_height(&level_document, position); vk_world_add(scene, ctx, &furniture_meshes[item.kind], item.x, item.y, item.height, item.yaw, item.tint, false, 0, base)}
	object_shadow_stride := max(
		(len(level_document.objects) + 255) / 256,
		1,
	); for object, object_index in level_document.objects {no_shadow := object_shadow_stride > 1 && object_index % object_shadow_stride != 0; visible_story := object.story == level_document.active_story || show_below && object.story < level_document.active_story; if !visible_story do continue; mesh, found := catalog_object_mesh(object.catalog_id); if !found do continue; base := object.elevation; if object.story >= 0 && object.story < len(level_document.stories) do base += level_document.stories[object.story].base_elevation; if level_terrain_supports_position(&level_document, object.position, object.story) do base += level_terrain_height(&level_document, object.position); entry, entry_found := catalog_object_entry(object.catalog_id); if entry_found && entry.presentation_component_count > 0 {object_yaw := object.rotation * f32(math.PI) / 180; state_value := clamp(g.shutter_position, 0, 1); for component in entry.presentation_components[:entry.presentation_component_count] {phase := component.state == "interaction_output" ? state_value : f32(0); local_x := component.offset[0] + component.state_offset[0] * phase; local_z := component.offset[2] + component.state_offset[2] * phase; world_x := object.position.x + local_x * f32(math.cos(f64(object_yaw))) - local_z * f32(math.sin(f64(object_yaw))); world_z := object.position.y + local_x * f32(math.sin(f64(object_yaw))) + local_z * f32(math.cos(f64(object_yaw))); world_y := base + component.offset[1] + component.state_offset[1] * phase; yaw := object_yaw + (component.rotation + component.state_rotation * phase) * f32(math.PI) / 180; component_mesh := mesh; switch component.mesh {case "blood_decal":
					component_mesh = &bloodstain_mesh; case "drag_decal":
					component_mesh = &drag_trace_mesh; case "housing":
					component_mesh = &shutter_crank_housing_mesh; case "link":
					component_mesh = &shutter_crank_link_mesh; case "arm":
					component_mesh = &shutter_crank_arm_mesh; case "grip":
					component_mesh = &shutter_crank_grip_mesh; case "model":
					component_mesh =
						mesh; case:}; if component.animated || component.mesh == "character" {clip := glb_clip_index(&character_meshes[0], component.pose == "" ? "Idle_A" : component.pose); roll := component.rotation * f32(math.PI) / 180; vk_world_add_animated(scene, ctx, &character_meshes[0], world_x, world_z, component.scale[1], object_yaw, component.tint, clip, -1, 0, 0, 0, world_y, component.layer, roll)} else {vk_world_add(scene, ctx, component_mesh, world_x, world_z, component.scale[1], yaw, component.tint, component.decal, component.layer, world_y, 0, 0, false, no_shadow)}}; continue}; render_height := catalog_object_render_height(mesh, entry_found ? entry : nil); if entry_found && entry.category == "foliage" {vk_world_add_foliage(scene, ctx, mesh, object.position.x, object.position.y, render_height, object.rotation * f32(math.PI) / 180, object.bark_tint, object.foliage_tint, base, no_shadow)} else {vk_world_add(scene, ctx, mesh, object.position.x, object.position.y, render_height, object.rotation * f32(math.PI) / 180, object.tint, false, 0, base, 0, 0, false, no_shadow)}}
	scene.profile_house_objects_ms =
		time.duration_seconds(time.tick_diff(house_phase_started, time.tick_now())) * 1000
	house_phase_started = time.tick_now()
	if g.editor_mode == .Build && g.build_tool == .Plant && editor_state.placement_active {
		room_index := vk_world_room_at(editor_state.placement_position)
		if room_index >= 0 {
			room :=
				level_document.rooms[room_index]; min_x, min_z, max_x, max_z := room.points[0].x, room.points[0].y, room.points[0].x, room.points[0].y
			for point in room.points {min_x = min(min_x, point.x); min_z = min(min_z, point.y); max_x = max(max_x, point.x); max_z = max(max_z, point.y)}
			cell := f32(.5); x := f32(math.floor(f64(min_x / cell))) * cell + cell * .5
			for x <
			    max_x {z := f32(math.floor(f64(min_z / cell))) * cell + cell * .5; for z < max_z {point := Vec2{x, z}; if level_point_in_polygon(point, room.points[:]) {cost := level_circulation_cost(&level_document, point); tint := [4]u8{78, 190, 126, 72}; if cost >= .78 {tint = {239, 68, 68, 126}} else if cost >= .32 {tint = {245, 170, 55, 100}}; vk_world_add_sized(scene, ctx, &catalog_thumbnail_floor, x, z, cell * .92, cell * .92, 0, tint, 0, active_base + .012)}; z += cell}; x += cell}
		}
	}
	// Case props share their interaction anchors with StoryCore. Props behind
	// authored gates appear only when the desk, room search, or closet reveals them.
	staging_preview :=
		g.editor_mode == .Build && (g.build_tool == .Marker || editor_state.view == .Markers)
	if g.editor_mode != .Build || staging_preview {
		rug_position := Vec2 {
			13.6,
			24.5,
		}; rug_mesh := g.study_rug_lifted ? &case_rug_folded_mesh : &case_rug_unfolded_mesh
		vk_world_add(
			scene,
			ctx,
			rug_mesh,
			rug_position.x,
			rug_position.y,
			catalog_object_height(rug_mesh),
			.08,
			{255, 255, 255, 255},
			false,
			0,
			active_base + .012,
		)
		if g.study_rug_lifted do vk_world_add(scene, ctx, &bloodstain_mesh, rug_position.x - .18, rug_position.y + .04, 1.10, .08, {255, 255, 255, 255}, true, 0, active_base + .018)
		for &entity in WORLD_ENTITIES {
			if !entity_visible(g, &entity) && !staging_preview do continue
			if entity.appearance !=
			   "" {mesh, found := catalog_object_mesh(entity.appearance); if found {entry, entry_found := catalog_object_entry(entity.appearance); height := catalog_object_render_height(mesh, entry_found ? entry : nil); vk_world_add(scene, ctx, mesh, entity.x, entity.y, height, entity.facing, {255, 255, 255, 255}, false, 0, active_base + entity.elevation)}}
		}
	}
	if g.editor_mode == .Build && g.build_tool == .Plant && editor_state.placement_active {
		mesh, found := catalog_object_mesh(
			editor_state.catalog_id,
		); entry, entry_found := catalog_object_entry(editor_state.catalog_id); if found {state := editor_state.placement_preview.state; status_tint := state == .Blocked ? [4]u8{244, 91, 91, 255} : state == .Warning ? [4]u8{244, 190, 75, 255} : [4]u8{96, 224, 156, 255}; position := editor_state.placement_position; base := level_terrain_height(&level_document, position) + editor_state.placement_elevation; radius := f32(.4); if entry_found do radius = max(entry.footprint, .2); vk_world_add(scene, ctx, &catalog_thumbnail_floor, position.x, position.y, radius * 2, editor_state.placement_rotation * f32(math.PI) / 180, status_tint, true, 0, base + .008); vk_world_add(scene, ctx, mesh, position.x, position.y, catalog_object_render_height(mesh, entry_found ? entry : nil), editor_state.placement_rotation * f32(math.PI) / 180, {255, 255, 255, 255}, false, 0, base + .018)}
	}
	// The investigator is deliberately rendered in the same space as the world,
	// rather than represented by a HUD marker, so the aerial camera remains a
	// genuine third-person view.
	if !g.first_person_camera {player := &g.player_animation; vk_world_add_animated(scene, ctx, &character_meshes[0], g.player_x, g.player_y, 1.65, character_render_yaw(g.player_angle), {255, 255, 255, 255}, player.current, player.transitioning ? player.next : -1, player.time, player.next_time, player.transitioning ? player.transition : 0, g.player_elevation, 9)}
	// The lieutenant arrives after uniforms have begun working the house. These
	// background officers keep the opening inside the playable crime scene and
	// provide human activity without handing the player an explanation.
	if g.editor_mode !=
	   .Build {idle := glb_clip_index(&character_meshes[0], "Idle_A"); officer_index := 0; for &entity in WORLD_ENTITIES {if !world_entity_has_tag(&entity, "officer") do continue; position := Vec2{entity.x, entity.y}; base := level_terrain_supports_position(&level_document, position, level_document.active_story) ? level_terrain_height(&level_document, position) : f32(0); vk_world_add_animated(scene, ctx, &character_meshes[0], position.x, position.y, 1.65, character_render_yaw(entity.facing), {67, 91, 126, 255}, idle, -1, g.animation_time + f32(officer_index) * .73, 0, 0, base, 9); officer_index += 1}}
	for &entity, entity_index in WORLD_ENTITIES {
		if !entity_visible(g, &entity) || entity.kind != "person" do continue
		_, tint, _ := character_presentation(
			entity.source_id,
		); if entity_index == g.hover_entity do tint = entity_examination_complete(g, entity_index) ? [4]u8{102, 205, 143, 255} : [4]u8{255, 224, 116, 255}; index := character_index(g, entity.source_id); heading: f32 = 0
		// Persistent blocking turns authored reactions into visible performance:
		// Daniel checks Miriam before answering, Miriam turns toward him when her
		// denial is exposed, and late-case Elsie keeps facing the desk/cash box.
		if world_entity_has_tag(&entity, "turn_on_alibi_claim") && claim_known(g, "claim_daniel_alibi") do heading = math.PI
		if world_entity_has_tag(&entity, "face_on_appointment_contradiction") && topic_unlocked(g, "appointment_contradiction") do heading = 0
		if world_entity_has_tag(&entity, "turn_on_threshold_eight") && g.threshold_eight_spent do heading = math.PI / 2
		if index >= 0 &&
		   index <
			   len(
				   g.character_animations,
			   ) {state := &g.character_animations[index]; position := Vec2{entity.x, entity.y}; base := level_terrain_supports_position(&level_document, position, level_document.active_story) ? level_terrain_height(&level_document, position) : f32(0); vk_world_add_animated(scene, ctx, character_mesh_for(entity.source_id), entity.x, entity.y, 1.65, character_render_yaw(heading), tint, state.current, state.transitioning ? state.next : -1, state.time, state.next_time, state.transitioning ? state.transition : 0, base)}
	}
	scene.profile_house_characters_ms =
		time.duration_seconds(time.tick_diff(house_phase_started, time.tick_now())) * 1000
}

house_roof_visible :: proc(g: ^Game) -> bool {
	if g.capture_hide_roofs do return false
	if g.editor_mode == .Build && (g.build_tool == .Roof || editor_state.view == .Roof) do return true
	// The boom eye commonly sits beyond the building footprint while looking into
	// a room. Roof cutaway follows the camera's subject, not the eye or player, so
	// zooming and orbiting cannot re-enable a roof between camera and subject.
	camera_focus := Vec2{g.camera_x, g.camera_y}
	if g.first_person_camera do camera_focus = {g.player_x, g.player_y}
	if g.camera_pose_override do camera_focus = {g.camera_target_override.x, g.camera_target_override.z}
	return house_room_at_point(camera_focus) < 0
}

vk_world_build_character_studio :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	g: ^Game,
) {
	vk_world_add(
		scene,
		ctx,
		&catalog_thumbnail_floor,
		0,
		0,
		14,
		0,
		{92, 99, 108, 255},
		true,
		7,
		-.025,
	)
	positions := [4]f32{-3, -1, 1, 3}
	for &mesh, i in character_meshes {
		clip := glb_clip_index(&mesh, i == 2 ? "Idle_B" : "Idle_A")
		vk_world_add_animated(
			scene,
			ctx,
			&mesh,
			positions[i],
			0,
			2.25,
			0,
			{255, 255, 255, 255},
			clip,
			-1,
			f32(i) * .37,
			0,
			0,
			0,
			i == 0 ? 9 : 5,
		)
	}
}
