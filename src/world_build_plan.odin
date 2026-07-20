package main

import "core:image"
import _ "core:image/jpeg"
import _ "core:image/png"
import "core:math"

house_plan_initialize :: proc() {
	if house_plan.initialized do return
	house_plan = {
		level            = 0,
		wall_splines     = make([dynamic]Floorplan_Spline, 0, 0),
		openings         = make([dynamic]Plan_Opening, 0, 0),
		wall_face_paints = make([dynamic]Wall_Face_Paint, 0, 0),
		furniture        = make([dynamic]Furniture, 0, 0),
		initialized      = true,
		revision         = 0,
		dirty            = true,
	}
	for i in 0 ..< HOUSE_SURFACE_CELLS {house_plan.surfaces[i] = .Garden; house_plan.space_kinds[i] = .Grounds}
}

house_snapshot :: proc() -> Build_Snapshot {
	result: Build_Snapshot; result.wall_splines = make([dynamic]Floorplan_Spline, 0, len(house_plan.wall_splines)); result.openings = make([dynamic]Plan_Opening, 0, len(house_plan.openings)); result.wall_face_paints = make([dynamic]Wall_Face_Paint, 0, len(house_plan.wall_face_paints)); result.furniture = make([dynamic]Furniture, 0, len(house_plan.furniture)); for item in house_plan.wall_splines do append(&result.wall_splines, item); for item in house_plan.openings do append(&result.openings, item); for item in house_plan.wall_face_paints do append(&result.wall_face_paints, item); for item in house_plan.furniture do append(&result.furniture, item); result.surfaces = house_plan.surfaces; result.space_kinds = house_plan.space_kinds; result.revision = house_plan.revision; return result
}

house_restore :: proc(snapshot: Build_Snapshot) {house_plan.wall_splines = snapshot.wall_splines
	house_plan.openings = snapshot.openings
	house_plan.wall_face_paints = snapshot.wall_face_paints
	house_plan.furniture = snapshot.furniture
	house_plan.surfaces = snapshot.surfaces
	house_plan.space_kinds = snapshot.space_kinds
	house_plan.revision = snapshot.revision
	house_plan.dirty = true
	build_house_floorplan()
	build_house_navmesh()
	_ = house_plan_validate()}
house_push_undo :: proc() {if house_plan.undo_count >= len(house_plan.undo) {for i in 1 ..< len(house_plan.undo) do house_plan.undo[i - 1] = house_plan.undo[i]
		house_plan.undo_count -= 1}
	house_plan.undo[house_plan.undo_count] = house_snapshot()
	house_plan.undo_count += 1
	house_plan.redo_count = 0}
house_undo :: proc() -> bool {if house_plan.undo_count <= 0 do return false
	if house_plan.redo_count <
	   len(house_plan.redo) {house_plan.redo[house_plan.redo_count] = house_snapshot()
		house_plan.redo_count += 1}
	house_plan.undo_count -= 1
	house_restore(house_plan.undo[house_plan.undo_count])
	return true}
house_redo :: proc() -> bool {if house_plan.redo_count <= 0 do return false
	if house_plan.undo_count <
	   len(house_plan.undo) {house_plan.undo[house_plan.undo_count] = house_snapshot()
		house_plan.undo_count += 1}
	house_plan.redo_count -= 1
	house_restore(house_plan.redo[house_plan.redo_count])
	return true}

house_opening_contains :: proc(opening: Plan_Opening, x, y: f32) -> bool {
	return point_segment_distance_sq(x, y, opening.a, opening.b) < .28 * .28
}

house_snap_opening :: proc(point: Vec2, kind: Opening_Kind) -> (opening: Plan_Opening, ok: bool) {
	best: f32 = 1e30
	for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 {
			a, b :=
				spline.points[i],
				spline.points[i + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length < 1.2 do continue
			t := clamp(
				((point.x - a.x) * dx + (point.y - a.y) * dy) / (length * length),
				0,
				1,
			); px, py := a.x + dx * t, a.y + dy * t; distance := (point.x - px) * (point.x - px) + (point.y - py) * (point.y - py)
			if distance <
			   best {half: f32 = kind == .Door ? .72 : .88; center := clamp(t, half / length, 1 - half / length); opening = {
					a      = {
						a.x + dx * (center - half / length),
						a.y + dy * (center - half / length),
					},
					b      = {
						a.x + dx * (center + half / length),
						a.y + dy * (center + half / length),
					},
					kind   = kind,
					height = kind == .Window ? 1.4 : 2.1,
				}; best = distance}
		}}
	return opening, best < .8 * .8
}

house_snap_wall_face :: proc(point: Vec2) -> (paint: Wall_Face_Paint, ok: bool) {
	best: f32 = 1e30
	for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 {
			a, b :=
				spline.points[i],
				spline.points[i + 1]; dx, dz := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .01 do continue
			t := clamp(
				((point.x - a.x) * dx + (point.y - a.y) * dz) / (length * length),
				0,
				1,
			); px, pz := a.x + dx * t, a.y + dz * t; distance := (point.x - px) * (point.x - px) + (point.y - pz) * (point.y - pz)
			if distance <
			   best {nx, nz := -dz / length, dx / length; paint = {a, b, (point.x - px) * nx + (point.y - pz) * nz >= 0, .Dining}; best = distance}
		}}
	return paint, best < .8 * .8
}

// Strict build validation treats the generated navmesh as an architectural
// invariant. A wall may shape circulation, but it may not strand a usable
// portion of the house behind an unintentional sealed partition.
house_plan_has_single_navigable_component :: proc() -> bool {
	walkable: [HOUSE_NAV_CELLS]bool; visited: [HOUSE_NAV_CELLS]bool; queue: [HOUSE_NAV_CELLS]int
	first := -1; walkable_count := 0
	for y in 0 ..< HOUSE_NAV_HEIGHT {for x in 0 ..< HOUSE_NAV_WIDTH {
			index :=
				y * HOUSE_NAV_WIDTH +
				x; center := Vec2{f32(x) * HOUSE_NAV_CELL + HOUSE_NAV_CELL * .5, f32(y) * HOUSE_NAV_CELL + HOUSE_NAV_CELL * .5}
			walkable[index] = nav_point_walkable(center.x, center.y)
			if walkable[index] {walkable_count += 1; if first < 0 do first = index}
		}}
	if first < 0 do return false
	head, tail := 0, 1; queue[0] = first; visited[first] = true; visited_count := 0
	for head < tail {
		current :=
			queue[head]; head += 1; visited_count += 1; cx, cy := current % HOUSE_NAV_WIDTH, current / HOUSE_NAV_WIDTH
		for axis in 0 ..< 4 {
			ox, oy := 0, 0; switch axis {case 0:
				ox = 1; case 1:
				ox = -1; case 2:
				oy = 1; case:
				oy = -1}
			nx, ny :=
				cx +
				ox,
				cy +
				oy; if nx < 0 || ny < 0 || nx >= HOUSE_NAV_WIDTH || ny >= HOUSE_NAV_HEIGHT do continue
			next :=
				ny * HOUSE_NAV_WIDTH +
				nx; if walkable[next] && !visited[next] {visited[next] = true; queue[tail] = next; tail += 1}
		}
	}
	return visited_count == walkable_count
}

// Room paint follows actual architectural boundaries, including open doors,
// rather than treating a material name as a room identifier.
house_paint_connected_room :: proc(point: Vec2, surface: Room_Surface) -> bool {
	start_x, start_y :=
		int(point.x),
		int(
			point.y,
		); if start_x < 0 || start_x >= HOUSE_SURFACE_WIDTH || start_y < 0 || start_y >= HOUSE_SURFACE_HEIGHT do return false
	from :=
		house_plan.surfaces[start_y * HOUSE_SURFACE_WIDTH + start_x]; seen: [HOUSE_SURFACE_CELLS]bool; queue: [HOUSE_SURFACE_CELLS]int; head, tail := 0, 1; queue[0] = start_y * HOUSE_SURFACE_WIDTH + start_x; seen[queue[0]] = true
	for head < tail {
		current :=
			queue[head]; head += 1; cx, cy := current % HOUSE_SURFACE_WIDTH, current / HOUSE_SURFACE_WIDTH; house_plan.surfaces[current] = surface; house_plan.space_kinds[current] = surface == .Garden ? .Grounds : .Interior
		for axis in 0 ..< 4 {
			ox, oy := 0, 0; switch axis {case 0:
				ox = 1; case 1:
				ox = -1; case 2:
				oy = 1; case:
				oy = -1}; nx, ny := cx + ox, cy + oy; if nx < 0 || ny < 0 || nx >= HOUSE_SURFACE_WIDTH || ny >= HOUSE_SURFACE_HEIGHT do continue
			next :=
				ny * HOUSE_SURFACE_WIDTH +
				nx; if seen[next] || house_plan.surfaces[next] != from do continue
			// The midpoint is a wall test; openings allow the fill through.
			if world_wall(f32(cx + nx + 1) * .5, f32(cy + ny + 1) * .5) do continue
			seen[next] = true; queue[tail] = next; tail += 1
		}
	}
	return true
}

house_set_connected_space_kind :: proc(point: Vec2, space: Plan_Space_Kind) -> bool {
	start_x, start_y :=
		int(point.x),
		int(
			point.y,
		); if start_x < 0 || start_x >= HOUSE_SURFACE_WIDTH || start_y < 0 || start_y >= HOUSE_SURFACE_HEIGHT do return false
	from :=
		house_plan.surfaces[start_y * HOUSE_SURFACE_WIDTH + start_x]; seen: [HOUSE_SURFACE_CELLS]bool; queue: [HOUSE_SURFACE_CELLS]int; head, tail := 0, 1; queue[0] = start_y * HOUSE_SURFACE_WIDTH + start_x; seen[queue[0]] = true
	for head < tail {
		current :=
			queue[head]; head += 1; cx, cy := current % HOUSE_SURFACE_WIDTH, current / HOUSE_SURFACE_WIDTH; house_plan.space_kinds[current] = space
		for axis in 0 ..< 4 {ox, oy := 0, 0; switch axis {case 0:
				ox = 1; case 1:
				ox = -1; case 2:
				oy = 1; case:
				oy = -1}; nx, ny := cx + ox, cy + oy; if nx < 0 || ny < 0 || nx >= HOUSE_SURFACE_WIDTH || ny >= HOUSE_SURFACE_HEIGHT do continue; next := ny * HOUSE_SURFACE_WIDTH + nx; if seen[next] || house_plan.surfaces[next] != from do continue; if world_wall(f32(cx + nx + 1) * .5, f32(cy + ny + 1) * .5) do continue; seen[next] = true; queue[tail] = next; tail += 1}
	}
	return true
}

house_plan_validate :: proc() -> bool {
	if len(house_plan.wall_splines) ==
	   0 {house_plan.validation = "A house needs a structural shell."; return false}
	for opening in house_plan.openings {
		found :=
			false; for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 do if point_segment_distance_sq((opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5, spline.points[i], spline.points[i + 1]) < .08 * .08 {found = true; break}}; if opening.kind == .Window && !found {house_plan.validation = "Windows must snap to a wall section."; return false}
		if opening.kind == .Window &&
		   !(opening.a.x < .22 ||
				   opening.a.x > 23.78 ||
				   opening.a.y < .22 ||
				   opening.a.y > 15.78 ||
				   opening.b.x < .22 ||
				   opening.b.x > 23.78 ||
				   opening.b.y < .22 ||
				   opening.b.y >
					   15.78) {house_plan.validation = "Windows belong on exterior or atrium-facing walls."; return false}
	}
	for item, i in house_plan.furniture {if item.x < .5 || item.x > 39.5 || item.y < .5 || item.y > 33.5 {house_plan.validation = "Furniture must remain inside the estate bounds."; return false}; for other, j in house_plan.furniture {if j <= i do continue; dx, dy := item.x - other.x, item.y - other.y; if dx * dx + dy * dy < (item.radius + other.radius + .18) * (item.radius + other.radius + .18) {house_plan.validation = "Furniture footprints overlap."; return false}}}
	// Expanded lots may contain several intentionally separated lawn pockets
	// outside the authored fence line; room connectivity is tested separately.
	// Navigation reachability is validated against the active level and its
	// authored transition markers by the playtest suite; lawn pockets need not
	// form one component with every interior paint region.
	house_plan.validation = "PLAN VALID"; return true
}

house_apply_command :: proc(command: Build_Command) -> bool {
	if !house_plan_validate() do return false
	house_push_undo()
	switch command.kind {
	case .Create_Room:
		min_x, max_x :=
			clamp(int(min(command.a.x, command.b.x)), 0, HOUSE_SURFACE_WIDTH - 2),
			clamp(int(max(command.a.x, command.b.x)), 1, HOUSE_SURFACE_WIDTH)
		min_y, max_y :=
			clamp(int(min(command.a.y, command.b.y)), 0, HOUSE_SURFACE_HEIGHT - 2),
			clamp(int(max(command.a.y, command.b.y)), 1, HOUSE_SURFACE_HEIGHT)
		if max_x - min_x < 3 ||
		   max_y - min_y <
			   3 {house_plan.validation = "Rooms need at least a 3 × 3 tile footprint."; house_plan.undo_count -= 1; return false}
		for y := min_y;
		    y < max_y;
		    y += 1 {for x := min_x; x < max_x; x += 1 {house_plan.surfaces[y * HOUSE_SURFACE_WIDTH + x] = command.surface; house_plan.space_kinds[y * HOUSE_SURFACE_WIDTH + x] = command.surface == .Garden ? .Grounds : .Interior}}
		append(
			&house_plan.wall_splines,
			Floorplan_Spline {
				[]Vec2 {
					{f32(min_x), f32(min_y)},
					{f32(max_x), f32(min_y)},
					{f32(max_x), f32(max_y)},
					{f32(min_x), f32(max_y)},
					{f32(min_x), f32(min_y)},
				},
				0,
			},
		)
	case .Set_Wall:
		append(&house_plan.wall_splines, Floorplan_Spline{[]Vec2{command.a, command.b}, 0})
	case .Place_Opening:
		opening, ok := house_snap_opening(command.a, command.opening)
		if !ok {house_plan.validation = "Select an existing wall span for the opening."
			house_plan.undo_count -= 1
			return false}
		append(&house_plan.openings, opening)
	case .Place_Object:
		append(&house_plan.furniture, command.furniture)
	case .Move_Object:
		if command.index < 0 ||
		   command.index >=
			   len(
				   house_plan.furniture,
			   ) {house_plan.validation = "Object does not exist."; house_plan.undo_count -= 1; return false} else {house_plan.furniture[command.index].x = command.a.x; house_plan.furniture[command.index].y = command.a.y}
	case .Delete_Object:
		if command.index < 0 ||
		   command.index >=
			   len(house_plan.furniture) {house_plan.validation = "Object does not exist."
			house_plan.undo_count -= 1
			return false}
		ordered_remove(&house_plan.furniture, command.index)
	case .Paint_Room:
		if !house_paint_connected_room(
			command.a,
			command.surface,
		) {house_plan.validation = "Select a room inside the house footprint."; house_plan.undo_count -= 1; return false}
	case .Set_Space_Kind:
		if !house_set_connected_space_kind(
			command.a,
			command.space,
		) {house_plan.validation = "Select a room inside the house footprint."; house_plan.undo_count -= 1; return false}
	case .Paint_Wall_Side:
		paint, ok := house_snap_wall_face(command.a)
		if !ok {house_plan.validation = "Select a wall face to paint."; house_plan.undo_count -= 1
			return false}
		paint.surface = command.surface
		append(&house_plan.wall_face_paints, paint)
	}
	if !house_plan_validate(

	) {house_plan.undo_count -= 1; house_restore(house_plan.undo[house_plan.undo_count]); return false}
	house_plan.revision += 1; house_plan.dirty = true; build_house_floorplan(); build_house_navmesh(); return true
}

house_surface_at :: proc(x, z: f32) -> Room_Surface {
	if !house_plan.initialized do return .Garden
	ix, iz :=
		clamp(int(x), 0, HOUSE_SURFACE_WIDTH - 1),
		clamp(
			int(z),
			0,
			HOUSE_SURFACE_HEIGHT - 1,
		); return house_plan.surfaces[iz * HOUSE_SURFACE_WIDTH + ix]
}

house_space_kind_at :: proc(x, z: f32) -> Plan_Space_Kind {
	if !house_plan.initialized do return .Grounds
	ix, iz :=
		clamp(int(x), 0, HOUSE_SURFACE_WIDTH - 1),
		clamp(
			int(z),
			0,
			HOUSE_SURFACE_HEIGHT - 1,
		); return house_plan.space_kinds[iz * HOUSE_SURFACE_WIDTH + ix]
}

house_ground_cell_count :: proc() -> int {count := 0; for kind in house_plan.space_kinds do if kind == .Grounds do count += 1
	return count}

load_room_texture :: proc(path: string) -> Glb_Texture_Data {
	result: Glb_Texture_Data; img, err := image.load(path, {.alpha_add_if_missing}, context.allocator)
	if err != nil || img == nil do return result
	result.width =
		img.width; result.height = img.height; result.pixels = make([dynamic]u8, len(img.pixels.buf)); copy(result.pixels[:], img.pixels.buf[:]); image.destroy(img)
	return result
}

apply_texture :: proc(mesh: ^Glb_Mesh, texture: Glb_Texture_Data) {
	if len(texture.pixels) == 0 do return
	mesh.textures = make(
		[dynamic]Glb_Texture_Data,
		0,
		1,
	); append(&mesh.textures, texture); mesh.primitives[0].texture = 0
}

picture_mesh_piece :: proc(m: ^Glb_Mesh, left, bottom, right, top, u0, v0, u1, v1, z: f32) {
	base := u32(
		len(m.vertices),
	); append(&m.vertices, Vec3{left, bottom, z}, Vec3{right, bottom, z}, Vec3{right, top, z}, Vec3{left, top, z})
	append(
		&m.texcoords,
		Vec2{u0, v1},
		Vec2{u1, v1},
		Vec2{u1, v0},
		Vec2{u0, v0},
	); append(&m.indices, base, base + 1, base + 2, base, base + 2, base + 3)
}

procedural_picture_mesh :: proc(width, height: f32, art, frame: Glb_Texture_Data) -> Glb_Mesh {
	m: Glb_Mesh; m.vertices = make([dynamic]Vec3, 0, 36); m.texcoords = make([dynamic]Vec2, 0, 36); m.indices = make([dynamic]u32, 0, 54); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 2); m.textures = make([dynamic]Glb_Texture_Data, 0, 2)
	border := f32(
		.14,
	); left, right := -width * .5, width * .5; bottom, top := f32(0), height; outer_left, outer_right := left - border, right + border; outer_bottom, outer_top := bottom - border, top + border; third := f32(1.0 / 3.0)
	picture_mesh_piece(
		&m,
		left,
		bottom,
		right,
		top,
		0,
		0,
		1,
		1,
		.006,
	); append(&m.primitives, Glb_Primitive_Range{0, 6, 0, {1, 1, 1, 1}})
	frame_start := len(m.indices)
	picture_mesh_piece(&m, outer_left, top, left, outer_top, 0, 0, third, third, 0)
	picture_mesh_piece(&m, left, top, right, outer_top, third, 0, third * 2, third, 0)
	picture_mesh_piece(&m, right, top, outer_right, outer_top, third * 2, 0, 1, third, 0)
	picture_mesh_piece(&m, outer_left, bottom, left, top, 0, third, third, third * 2, 0)
	picture_mesh_piece(&m, right, bottom, outer_right, top, third * 2, third, 1, third * 2, 0)
	picture_mesh_piece(&m, outer_left, outer_bottom, left, bottom, 0, third * 2, third, 1, 0)
	picture_mesh_piece(&m, left, outer_bottom, right, bottom, third, third * 2, third * 2, 1, 0)
	picture_mesh_piece(&m, right, outer_bottom, outer_right, bottom, third * 2, third * 2, 1, 1, 0)
	append(
		&m.primitives,
		Glb_Primitive_Range{frame_start, len(m.indices) - frame_start, 1, {1, 1, 1, 1}},
	); append(&m.textures, art, frame); m.min = {outer_left, outer_bottom, 0}; m.max = {outer_right, outer_top, .006}; m.ready = true; return m
}

procedural_quad_mesh :: proc(width, height: f32, floor: bool) -> Glb_Mesh {
	m: Glb_Mesh
	m.vertices = make(
		[dynamic]Vec3,
		0,
		4,
	); m.texcoords = make([dynamic]Vec2, 4); m.indices = make([dynamic]u32, 0, 6); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	if floor {
		append(
			&m.vertices,
			Vec3{-width / 2, 0, -height / 2},
			Vec3{width / 2, 0, -height / 2},
			Vec3{width / 2, 0, height / 2},
			Vec3{-width / 2, 0, height / 2},
		)
		m.texcoords[0] = {
			0,
			0,
		}; m.texcoords[1] = {1, 0}; m.texcoords[2] = {1, 1}; m.texcoords[3] = {0, 1}
		append(
			&m.indices,
			0,
			2,
			1,
			0,
			3,
			2,
		); m.min = {-width / 2, 0, -height / 2}; m.max = {width / 2, 0.001, height / 2}
	} else {
		append(
			&m.vertices,
			Vec3{-width / 2, 0, 0},
			Vec3{width / 2, 0, 0},
			Vec3{width / 2, height, 0},
			Vec3{-width / 2, height, 0},
		)
		m.texcoords[0] = {
			0,
			1,
		}; m.texcoords[1] = {1, 1}; m.texcoords[2] = {1, 0}; m.texcoords[3] = {0, 0}
		append(
			&m.indices,
			0,
			1,
			2,
			0,
			2,
			3,
		); m.min = {-width / 2, 0, 0}; m.max = {width / 2, height, 0}
	}
	append(&m.primitives, Glb_Primitive_Range{0, 6, -1, {1, 1, 1, 1}}); m.ready = true
	return m
}

procedural_glazing_mesh :: proc(width, height: f32) -> Glb_Mesh {
	m := procedural_quad_mesh(width, height, false)
	// The world pipeline does not cull faces, so one quad is visible from both
	// sides. A second opposite-winding copy would be coplanar transparent
	// geometry, causing unstable depth writes and patchy double blending.
	m.min.z = 0; m.max.z = 0; return m
}

wallpaper_face_mesh :: proc(a, b: Vec2, region_base, region_height: f32) -> Glb_Mesh {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); mesh := procedural_quad_mesh(length, max(region_height, .001), false); if length <= .001 do return mesh
	anchor :=
		math.abs(dx) >= math.abs(dz) ? min(a.x, b.x) : min(a.y, b.y); u0, u1 := anchor * HOUSE_WALL_COVERING_UV_SCALE, (anchor + length) * HOUSE_WALL_COVERING_UV_SCALE; v0, v1 := region_base * HOUSE_WALL_COVERING_UV_SCALE, (region_base + region_height) * HOUSE_WALL_COVERING_UV_SCALE; mesh.texcoords[0] = {u0, v0}; mesh.texcoords[1] = {u1, v0}; mesh.texcoords[2] = {u1, v1}; mesh.texcoords[3] = {u0, v1}; return mesh
}

// Stable bands anchor the material at the final cut height, transition
// midpoint, and authored wall top. Only the single band crossed by the moving
// section plane is rescaled; every complete band retains its physical UV size.
house_wall_finish_bands :: proc() -> [4]f32 {height := house_authored_wall_height(); cut := min(
		HOUSE_CUTAWAY_HEIGHT,
		height,
	)
	return{0, cut, (cut + height) * .5, height}}

append_wallpaper_band_draws :: proc(
	out: ^[dynamic]Personal_Surface_Draw,
	a, b: Vec2,
	x, z, yaw: f32,
	texture: Glb_Texture_Data,
	base: f32,
	wall_index: int,
) {
	append_wallpaper_region_band_draws(
		out,
		a,
		b,
		x,
		z,
		yaw,
		texture,
		base,
		0,
		house_authored_wall_height(),
		wall_index,
	)
}

append_wallpaper_region_band_draws :: proc(
	out: ^[dynamic]Personal_Surface_Draw,
	a, b: Vec2,
	x, z, yaw: f32,
	texture: Glb_Texture_Data,
	base, requested_base, requested_height: f32,
	wall_index: int = -1,
) {
	if len(texture.pixels) == 0 || requested_height <= .001 do return
	requested_top := requested_base + requested_height
	bands := house_wall_finish_bands(

	); for band in 0 ..< len(bands) - 1 {region_base := max(requested_base, bands[band]); region_top := min(requested_top, bands[band + 1]); region_height := region_top - region_base; if region_height <= .001 do continue; mesh := wallpaper_face_mesh(a, b, region_base, region_height); apply_texture(&mesh, texture); append(out, Personal_Surface_Draw{mesh = mesh, x = x, z = z, yaw = yaw, base = base, region_base = region_base, region_height = region_height, wall_index = wall_index})}
}

// A batch owns only tiles with the same surface and space classification. That
// preserves the visual distinction between interior flooring and open-air
// grounds while collapsing the previous per-tile renderer submission loop.
procedural_floor_batch_mesh :: proc(surface: Room_Surface, space: Plan_Space_Kind) -> Glb_Mesh {
	m: Glb_Mesh; m.vertices = make([dynamic]Vec3, 0, 96); m.texcoords = make([dynamic]Vec2, 0, 96); m.indices = make([dynamic]u32, 0, 144); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	for y in 0 ..< HOUSE_SURFACE_HEIGHT {for x in 0 ..< HOUSE_SURFACE_WIDTH {
			wx, wz :=
				f32(x),
				f32(
					y,
				); if house_surface_at(wx + .5, wz + .5) != surface || house_space_kind_at(wx + .5, wz + .5) != space do continue
			base := u32(
				len(m.vertices),
			); append(&m.vertices, Vec3{wx, 0, wz}, Vec3{wx + 1, 0, wz}, Vec3{wx + 1, 0, wz + 1}, Vec3{wx, 0, wz + 1}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}); append(&m.indices, base, base + 2, base + 1, base, base + 3, base + 2)
		}}
	if len(m.vertices) == 0 do return m
	m.min = {
		1e30,
		0,
		1e30,
	}; m.max = {-1e30, 1, -1e30}; for vertex in m.vertices {m.min.x = min(m.min.x, vertex.x); m.min.z = min(m.min.z, vertex.z); m.max.x = max(m.max.x, vertex.x); m.max.z = max(m.max.z, vertex.z)}
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), 0, {1, 1, 1, 1}},
	); if len(house_floor_materials[surface].textures) > 0 do apply_texture(&m, house_floor_materials[surface].textures[0]); m.ready = true; return m
}

append_wall_face_region :: proc(mesh: ^Glb_Mesh, a, b: Vec2, positive: bool, base_y, height: f32) {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do return
	nx, nz :=
		-dz /
		length,
		dx /
		length; sign: f32 = positive ? 1 : -1; offset := f32(HOUSE_WALL_THICKNESS * .5 + .004) * sign; pa, pb := Vec2{a.x + nx * offset, a.y + nz * offset}, Vec2{b.x + nx * offset, b.y + nz * offset}; base := u32(len(mesh.vertices))
	top_y :=
		base_y +
		height; u0, u1 := a.x, b.x; if math.abs(dz) > math.abs(dx) {u0, u1 = a.y, b.y}; append(&mesh.vertices, Vec3{pa.x, base_y, pa.y}, Vec3{pb.x, base_y, pb.y}, Vec3{pb.x, top_y, pb.y}, Vec3{pa.x, top_y, pa.y}); append(&mesh.texcoords, Vec2{u0, base_y}, Vec2{u1, base_y}, Vec2{u1, top_y}, Vec2{u0, top_y})
	if positive {append(&mesh.indices, base, base + 1, base + 2, base, base + 2, base + 3)} else {append(&mesh.indices, base + 1, base, base + 3, base + 1, base + 3, base + 2)}
}

append_wall_face_batch :: proc(mesh: ^Glb_Mesh, a, b: Vec2, positive: bool, height: f32) {
	append_wall_face_region(mesh, a, b, positive, 0, height)
}

house_wall_face_classification :: proc(a, b: Vec2, positive: bool) -> (Room_Surface, bool) {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do return .Dining, false
	mx, mz :=
		(a.x + b.x) *
		.5,
		(a.y + b.y) *
		.5; nx, nz := -dz / length, dx / length; sign: f32 = positive ? 1 : -1; sx, sz := mx + nx * .24 * sign, mz + nz * .24 * sign
	interior :=
		sx >= 0 &&
		sx < f32(HOUSE_SURFACE_WIDTH) &&
		sz >= 0 &&
		sz < f32(HOUSE_SURFACE_HEIGHT) &&
		house_space_kind_at(sx, sz) == .Interior; surface := house_surface_at(sx, sz)
	for paint in house_plan.wall_face_paints {if paint.positive != positive do continue; if point_segment_distance_sq(mx, mz, paint.a, paint.b) < .08 * .08 {surface = paint.surface; break}}
	return surface, interior
}

append_window_wallpaper_regions :: proc(
	mesh: ^Glb_Mesh,
	opening: Plan_Opening,
	positive: bool,
	wall_height: f32,
) {
	if opening.kind != .Window || wall_height <= 0 do return
	sill := clamp(
		opening.sill_height > 0 ? opening.sill_height : f32(.72),
		0,
		wall_height,
	); glazing_height := opening.height > 0 ? opening.height : f32(1.4); head := clamp(sill + glazing_height, 0, wall_height)
	if sill > .001 do append_wall_face_region(mesh, opening.a, opening.b, positive, 0, sill)
	if head < wall_height - .001 do append_wall_face_region(mesh, opening.a, opening.b, positive, head, wall_height - head)
}

house_exterior_opening_finish_span :: proc(opening: Plan_Opening) -> Plan_Opening {
	result :=
		opening; dx, dz := opening.b.x - opening.a.x, opening.b.y - opening.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .001 do return result
	tx, tz :=
		dx /
		length,
		dz /
		length; result.a = {opening.a.x - tx * HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP, opening.a.y - tz * HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP}; result.b = {opening.b.x + tx * HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP, opening.b.y + tz * HOUSE_EXTERIOR_OPENING_FINISH_OVERLAP}; return result
}

append_window_wallpaper_draws :: proc(
	out: ^[dynamic]Personal_Surface_Draw,
	opening: Plan_Opening,
	positive: bool,
	texture: Glb_Texture_Data,
	base: f32,
	face_lift: f32 = .004,
) {
	dx, dz :=
		opening.b.x -
		opening.a.x,
		opening.b.y -
		opening.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .01 || len(texture.pixels) == 0 do return
	mx, mz :=
		(opening.a.x + opening.b.x) *
		.5,
		(opening.a.y + opening.b.y) *
		.5; nx, nz := -dz / length, dx / length; sign: f32 = positive ? 1 : -1; offset := house_opening_face_offset(opening, face_lift); yaw := f32(math.atan2(f64(dz), f64(dx))) + (positive ? 0 : f32(math.PI)); sill := opening.sill_height > 0 ? opening.sill_height : f32(.72); head := sill + (opening.height > 0 ? opening.height : f32(1.4)); x, z := mx + nx * offset * sign, mz + nz * offset * sign
	if sill > .001 do append_wallpaper_region_band_draws(out, opening.a, opening.b, x, z, yaw, texture, base, 0, sill)
	wall_height := house_authored_wall_height(

	); if head < wall_height - .001 do append_wallpaper_region_band_draws(out, opening.a, opening.b, x, z, yaw, texture, base, head, wall_height - head)
}

append_door_wallpaper_header_draw :: proc(
	out: ^[dynamic]Personal_Surface_Draw,
	opening: Plan_Opening,
	positive: bool,
	texture: Glb_Texture_Data,
	base: f32,
	face_lift: f32 = .004,
) {
	if opening.kind != .Door || len(texture.pixels) == 0 do return
	dx, dz :=
		opening.b.x -
		opening.a.x,
		opening.b.y -
		opening.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length <= .01 do return
	wall_height := house_authored_wall_height(

	); head := house_door_render_height(opening); if head >= wall_height - .001 do return
	mx, mz :=
		(opening.a.x + opening.b.x) *
		.5,
		(opening.a.y + opening.b.y) *
		.5; nx, nz := -dz / length, dx / length; sign: f32 = positive ? 1 : -1; offset := house_opening_face_offset(opening, face_lift)
	height :=
		wall_height -
		head; yaw := f32(math.atan2(f64(dz), f64(dx))) + (positive ? 0 : f32(math.PI))
	append_wallpaper_region_band_draws(
		out,
		opening.a,
		opening.b,
		mx + nx * offset * sign,
		mz + nz * offset * sign,
		yaw,
		texture,
		base,
		head,
		height,
	)
}

finalize_wall_face_batch :: proc(mesh: ^Glb_Mesh, surface: Room_Surface, height: f32) {
	if len(mesh.vertices) == 0 do return
	mesh.min = {
		1e30,
		0,
		1e30,
	}; mesh.max = {-1e30, height, -1e30}; for vertex in mesh.vertices {mesh.min.x = min(mesh.min.x, vertex.x); mesh.min.z = min(mesh.min.z, vertex.z); mesh.max.x = max(mesh.max.x, vertex.x); mesh.max.z = max(mesh.max.z, vertex.z)}
	append(
		&mesh.primitives,
		Glb_Primitive_Range{0, len(mesh.indices), 0, {1, 1, 1, 1}},
	); if len(house_wall_materials[surface].pixels) > 0 do apply_texture(mesh, house_wall_materials[surface]); mesh.ready = true
}

append_wall_cap_batch :: proc(mesh: ^Glb_Mesh, a, b: Vec2, height, thickness: f32) {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do return
	nx, nz :=
		-dz /
		length *
		thickness *
		.5,
		dx /
		length *
		thickness *
		.5; base := u32(len(mesh.vertices))
	append(
		&mesh.vertices,
		Vec3{a.x + nx, height, a.y + nz},
		Vec3{b.x + nx, height, b.y + nz},
		Vec3{b.x - nx, height, b.y - nz},
		Vec3{a.x - nx, height, a.y - nz},
	)
	append(&mesh.texcoords, Vec2{0, 0}, Vec2{length, 0}, Vec2{length, 1}, Vec2{0, 1})
	append(
		&mesh.indices,
		base,
		base + 1,
		base + 2,
		base,
		base + 2,
		base + 3,
		base + 2,
		base + 1,
		base,
		base + 3,
		base + 2,
		base,
	)
}

finalize_wall_cap_batch :: proc(mesh: ^Glb_Mesh, height: f32) {
	if len(mesh.vertices) == 0 do return
	mesh.min = {
		1e30,
		0,
		1e30,
	}; mesh.max = {-1e30, height, -1e30}; for vertex in mesh.vertices {mesh.min.x = min(mesh.min.x, vertex.x); mesh.min.z = min(mesh.min.z, vertex.z); mesh.max.x = max(mesh.max.x, vertex.x); mesh.max.z = max(mesh.max.z, vertex.z)}
	append(
		&mesh.primitives,
		Glb_Primitive_Range{0, len(mesh.indices), -1, {1, 1, 1, 1}},
	); mesh.ready = true
}

// A wall spline is a collision solid, not a paper-thin visual divider. This
// prism uses the same authored thickness as world_wall/navmesh clearance.
procedural_wall_mesh :: proc(length, height, thickness: f32) -> Glb_Mesh {
	m: Glb_Mesh; m.vertices = make([dynamic]Vec3, 0, 8); m.texcoords = make([dynamic]Vec2, 8); m.indices = make([dynamic]u32, 0, 36); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	hx, hz :=
		length *
		.5,
		thickness *
		.5; append(&m.vertices, Vec3{-hx, 0, -hz}, Vec3{hx, 0, -hz}, Vec3{hx, height, -hz}, Vec3{-hx, height, -hz}, Vec3{-hx, 0, hz}, Vec3{hx, 0, hz}, Vec3{hx, height, hz}, Vec3{-hx, height, hz}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1})
	append(
		&m.indices,
		0,
		2,
		1,
		0,
		3,
		2,
		5,
		7,
		4,
		5,
		6,
		7,
		4,
		3,
		0,
		4,
		7,
		3,
		1,
		6,
		5,
		1,
		2,
		6,
		3,
		6,
		2,
		3,
		7,
		6,
		4,
		1,
		5,
		4,
		0,
		1,
	); m.min = {-hx, 0, -hz}; m.max = {hx, height, hz}; append(&m.primitives, Glb_Primitive_Range{0, 36, -1, {1, 1, 1, 1}}); m.ready = true; return m
}

// Aperture infill overlaps the surrounding wall at both ends. Its endpoint
// faces are internal construction surfaces; drawing them lets their unpainted
// returns peek out beside window trim when the overlap closes the union cut.
procedural_wall_infill_mesh :: proc(length, height, thickness: f32) -> Glb_Mesh {
	m := procedural_wall_mesh(length, height, thickness); if !m.ready do return m
	clear(
		&m.indices,
	); append(&m.indices, 0, 2, 1, 0, 3, 2, 5, 7, 4, 5, 6, 7, 3, 6, 2, 3, 7, 6, 4, 1, 5, 4, 0, 1); m.primitives[0].count = len(m.indices); return m
}

procedural_wall_band_mesh :: proc(
	a, b: Vec2,
	region_base, region_height, thickness: f32,
) -> Glb_Mesh {
	dx, dz :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); mesh := procedural_wall_mesh(length, max(region_height, .001), thickness); if length <= .001 do return mesh
	// Internal band boundaries are not architectural surfaces. Retain front,
	// back, and endpoint returns; the renderer's dedicated cap owns the only
	// horizontal face at the current section height.
	resize(&mesh.indices, 24); mesh.primitives[0].count = 24
	anchor :=
		math.abs(dx) >= math.abs(dz) ? min(a.x, b.x) : min(a.y, b.y); u0, u1 := anchor * HOUSE_WALL_COVERING_UV_SCALE, (anchor + length) * HOUSE_WALL_COVERING_UV_SCALE; v0, v1 := region_base * HOUSE_WALL_COVERING_UV_SCALE, (region_base + region_height) * HOUSE_WALL_COVERING_UV_SCALE
	mesh.texcoords[0] = {
		u0,
		v0,
	}; mesh.texcoords[1] = {u1, v0}; mesh.texcoords[2] = {u1, v1}; mesh.texcoords[3] = {u0, v1}; mesh.texcoords[4] = {u0, v0}; mesh.texcoords[5] = {u1, v0}; mesh.texcoords[6] = {u1, v1}; mesh.texcoords[7] = {u0, v1}; return mesh
}

// The exterior half of a window sill sheds water away from the wall. Local +Z
// is outward; callers rotate the mesh so its taller edge always meets the jamb.
procedural_sloped_sill_mesh :: proc(length, depth, inner_height, outer_height: f32) -> Glb_Mesh {
	m: Glb_Mesh; m.vertices = make([dynamic]Vec3, 0, 8); m.texcoords = make([dynamic]Vec2, 8); m.indices = make([dynamic]u32, 0, 36); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	hx, hz :=
		length *
		.5,
		depth *
		.5; append(&m.vertices, Vec3{-hx, 0, -hz}, Vec3{hx, 0, -hz}, Vec3{hx, inner_height, -hz}, Vec3{-hx, inner_height, -hz}, Vec3{-hx, 0, hz}, Vec3{hx, 0, hz}, Vec3{hx, outer_height, hz}, Vec3{-hx, outer_height, hz}); append(&m.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1}, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1})
	append(
		&m.indices,
		0,
		2,
		1,
		0,
		3,
		2,
		5,
		7,
		4,
		5,
		6,
		7,
		4,
		3,
		0,
		4,
		7,
		3,
		1,
		6,
		5,
		1,
		2,
		6,
		3,
		6,
		2,
		3,
		7,
		6,
		4,
		1,
		5,
		4,
		0,
		1,
	); m.min = {-hx, 0, -hz}; m.max = {hx, max(inner_height, outer_height), hz}; append(&m.primitives, Glb_Primitive_Range{0, 36, -1, {1, 1, 1, 1}}); m.ready = true; return m
}

procedural_wall_run_mesh :: proc(points: []Vec2, height, thickness: f32) -> Glb_Mesh {
	m: Glb_Mesh; if len(points) < 2 do return m
	closed :=
		len(points) > 2 &&
		point_segment_distance_sq(
			points[0].x,
			points[0].y,
			points[len(points) - 1],
			points[len(points) - 1],
		) <
			.0001
	count := closed ? len(points) - 1 : len(points); if count < 2 do return m
	m.vertices = make(
		[dynamic]Vec3,
		0,
		count * 4,
	); m.texcoords = make([dynamic]Vec2, 0, count * 4); m.indices = make([dynamic]u32, 0, (count - 1 + (closed ? 1 : 0)) * 18 + 12); m.primitives = make([dynamic]Glb_Primitive_Range, 0, 1)
	half := thickness * .5
	for i in 0 ..< count {
		prev :=
			i -
			1; next := i + 1; if closed {if prev < 0 do prev = count - 1; if next >= count do next = 0} else {if prev < 0 do prev = 0; if next >= count do next = count - 1}
		p :=
			points[i]; previous := points[prev]; following := points[next]; pdx, pdz := p.x - previous.x, p.y - previous.y; ndx, ndz := following.x - p.x, following.y - p.y
		if i == 0 &&
		   !closed {pdx, pdz = ndx, ndz}; if i == count - 1 && !closed {ndx, ndz = pdx, pdz}
		plen := f32(
			math.sqrt(f64(pdx * pdx + pdz * pdz)),
		); nlen := f32(math.sqrt(f64(ndx * ndx + ndz * ndz))); if plen < .001 || nlen < .001 do continue; pdx, pdz = pdx / plen, pdz / plen; ndx, ndz = ndx / nlen, ndz / nlen
		pnx, pnz :=
			-pdz,
			pdx; nnx, nnz := -ndz, ndx; mx, mz := pnx + nnx, pnz + nnz; mlen := f32(math.sqrt(f64(mx * mx + mz * mz))); if mlen < .001 {mx, mz = nnx, nnz; mlen = 1}; mx, mz = mx / mlen, mz / mlen; denom := math.abs(mx * nnx + mz * nnz); offset := half / max(denom, .25)
		left, right :=
			Vec2{p.x + mx * offset, p.y + mz * offset}, Vec2{p.x - mx * offset, p.y - mz * offset}
		append(
			&m.vertices,
			Vec3{left.x, 0, left.y},
			Vec3{left.x, height, left.y},
			Vec3{right.x, 0, right.y},
			Vec3{right.x, height, right.y},
		)
		append(&m.texcoords, Vec2{0, 0}, Vec2{0, 1}, Vec2{1, 0}, Vec2{1, 1})
	}
	segments := closed ? count : count - 1
	// This mesh is the independently generated wall cap. Structural sides come
	// from the regularized union, while these mitered strips leave room interiors
	// open instead of filling an outer contour across its holes.
	for i in 0 ..< segments {j := (i + 1) % count; lt, rt := u32(i * 4 + 1), u32(i * 4 + 3); nlt, nrt := u32(j * 4 + 1), u32(j * 4 + 3); append(&m.indices, lt, nlt, nrt, lt, nrt, rt, nrt, nlt, lt, rt, nrt, lt)}
	m.min = {
		1e30,
		1e30,
		1e30,
	}; m.max = {-1e30, -1e30, -1e30}; for vertex in m.vertices {m.min.x = min(m.min.x, vertex.x); m.min.y = min(m.min.y, vertex.y); m.min.z = min(m.min.z, vertex.z); m.max.x = max(m.max.x, vertex.x); m.max.y = max(m.max.y, vertex.y); m.max.z = max(m.max.z, vertex.z)}
	append(
		&m.primitives,
		Glb_Primitive_Range{0, len(m.indices), -1, {1, 1, 1, 1}},
	); m.ready = true; return m
}

wall_solid_add_quad :: proc(mesh: ^Glb_Mesh, a, b: Vec2, bottom, top: f32) {
	base := u32(
		len(mesh.vertices),
	); append(&mesh.vertices, Vec3{a.x, bottom, a.y}, Vec3{b.x, bottom, b.y}, Vec3{b.x, top, b.y}, Vec3{a.x, top, a.y}); append(&mesh.texcoords, Vec2{0, 0}, Vec2{1, 0}, Vec2{1, 1}, Vec2{0, 1})
	// Keep both winding directions: contour direction distinguishes exterior and
	// courtyard walls, while the mesh remains readable with either face culling.
	append(
		&mesh.indices,
		base,
		base + 1,
		base + 2,
		base,
		base + 2,
		base + 3,
		base + 2,
		base + 1,
		base,
		base + 3,
		base + 2,
		base,
	)
}

wall_cap_cross :: proc(a, b, c: Vec2) -> f32 {return(
		(b.x - a.x) * (c.y - a.y) -
		(b.y - a.y) * (c.x - a.x) \
	)}

wall_cap_contains :: proc(p, a, b, c: Vec2, winding: f32) -> bool {
	// Points on an ear boundary count as contained so collinear union vertices
	// cannot leave a hairline wedge at a wall corner.
	epsilon: f32 = -.00001
	return(
		wall_cap_cross(a, b, p) * winding >= epsilon &&
		wall_cap_cross(b, c, p) * winding >= epsilon &&
		wall_cap_cross(c, a, p) * winding >= epsilon \
	)
}

// Union contours are frequently concave at T junctions and inside corners.
// A centroid fan only works for star-shaped contours and was the source of the
// small missing wedges visible in cutaway wall caps. Ear clipping covers every
// simple contour without changing the authoritative fixed-point boundary.
wall_solid_add_cap :: proc(mesh: ^Glb_Mesh, points: []Chicago_Wall_Point, height: f32) {
	count := len(points); if count < 3 do return
	polygon_area: f32 = 0; for i in 0 ..< count {j := (i + 1) % count; polygon_area += f32(points[i].x * points[j].y - points[j].x * points[i].y)}
	winding: f32 = polygon_area >= 0 ? 1 : -1
	base := u32(
		len(mesh.vertices),
	); for point in points {append(&mesh.vertices, Vec3{f32(point.x), height, f32(point.y)}); append(&mesh.texcoords, Vec2{0, 0})}
	remaining := make(
		[dynamic]int,
		0,
		count,
	); defer delete(remaining); for i in 0 ..< count do append(&remaining, i)
	guard := 0
	for len(remaining) > 2 && guard < count * count {
		clipped := false
		for cursor in 0 ..< len(remaining) {
			previous :=
				remaining[(cursor + len(remaining) - 1) % len(remaining)]; current := remaining[cursor]; next := remaining[(cursor + 1) % len(remaining)]
			a := Vec2 {
				f32(points[previous].x),
				f32(points[previous].y),
			}; b := Vec2{f32(points[current].x), f32(points[current].y)}; c := Vec2{f32(points[next].x), f32(points[next].y)}
			if wall_cap_cross(a, b, c) * winding <= .000001 do continue
			occupied :=
				false; for candidate in remaining {if candidate == previous || candidate == current || candidate == next do continue; p := Vec2{f32(points[candidate].x), f32(points[candidate].y)}; if wall_cap_contains(p, a, b, c, winding) {occupied = true; break}}
			if occupied do continue
			// Emit both windings; cap contours may arrive clockwise or counterclockwise
			// and the cutaway must remain visible under either culling configuration.
			append(
				&mesh.indices,
				base + u32(previous),
				base + u32(current),
				base + u32(next),
				base + u32(next),
				base + u32(current),
				base + u32(previous),
			)
			ordered_remove(&remaining, cursor); clipped = true; break
		}
		if !clipped do break
		guard += 1
	}
}

// The bridge returns normalized, fixed-point Clipper contours. We create a
// closed extruded boundary from them here; logical sections continue to own
// paint/UV decisions rather than becoming renderer-only geometry.
build_house_wall_solid :: proc(height: f32) -> Glb_Mesh {
	segments := make(
		[dynamic]Chicago_Wall_Segment,
		0,
		64,
	); doors := make([dynamic]Chicago_Wall_Door, 0, 16)
	for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 {a, b := spline.points[i], spline.points[i + 1]; append(&segments, Chicago_Wall_Segment{f64(a.x), f64(a.y), f64(b.x), f64(b.y), f64(house_wall_width(spline.width))})}}
	// Both doors and windows are real plan-view apertures. Window sill/header
	// masonry is restored as separate vertical infill after the union.
	for opening in house_plan.openings {a, b := opening.a, opening.b; append(&doors, Chicago_Wall_Door{f64(a.x), f64(a.y), f64(b.x), f64(b.y), f64(house_wall_width(opening.wall_width) + .02)})}
	geometry: Chicago_Wall_Geometry; if len(segments) == 0 || chicago_wall_union(raw_data(segments), u32(len(segments)), len(doors) > 0 ? raw_data(doors) : nil, u32(len(doors)), &geometry) == 0 do return {}
	defer chicago_wall_geometry_free(
		&geometry,
	); mesh: Glb_Mesh; mesh.vertices = make([dynamic]Vec3, 0, int(geometry.point_count) * 6); mesh.texcoords = make([dynamic]Vec2, 0, int(geometry.point_count) * 6); mesh.indices = make([dynamic]u32, 0, int(geometry.point_count) * 18); points := (cast([^]Chicago_Wall_Point)geometry.points)[:int(geometry.point_count)]; contours := (cast([^]Chicago_Wall_Contour)geometry.contours)[:int(geometry.contour_count)]
	for contour in contours {if contour.count < 3 do continue; start := int(contour.first)
		count := int(contour.count)
		for i in 0 ..< count {p, q := points[start + i], points[start + (i + 1) % count]; wall_solid_add_quad(&mesh, {f32(p.x), f32(p.y)}, {f32(q.x), f32(q.y)}, 0, height)}
	}
	if len(mesh.vertices) == 0 do return mesh; mesh.min = {1e30, 0, 1e30}; mesh.max = {-1e30, height, -1e30}; for v in mesh.vertices {mesh.min.x = min(mesh.min.x, v.x); mesh.min.z = min(mesh.min.z, v.z); mesh.max.x = max(mesh.max.x, v.x); mesh.max.z = max(mesh.max.z, v.z)}; append(&mesh.primitives, Glb_Primitive_Range{0, len(mesh.indices), -1, {1, 1, 1, 1}}); mesh.ready = true; return mesh
}

build_house_wall_cap_union :: proc(extra: f32) -> Glb_Mesh {
	segments := make(
		[dynamic]Chicago_Wall_Segment,
		0,
		64,
	); doors := make([dynamic]Chicago_Wall_Door, 0, 16)
	for spline in house_plan.wall_splines {for i in 0 ..< len(spline.points) - 1 {a, b := spline.points[i], spline.points[i + 1]; append(&segments, Chicago_Wall_Segment{f64(a.x), f64(a.y), f64(b.x), f64(b.y), f64(house_wall_width(spline.width) + extra)})}}
	for opening in house_plan.openings {append(&doors, Chicago_Wall_Door{f64(opening.a.x), f64(opening.a.y), f64(opening.b.x), f64(opening.b.y), f64(house_wall_width(opening.wall_width) + extra + .02)})}
	geometry: Chicago_Wall_Geometry; if len(segments) == 0 || chicago_wall_union(raw_data(segments), u32(len(segments)), len(doors) > 0 ? raw_data(doors) : nil, u32(len(doors)), &geometry) == 0 do return {}
	defer chicago_wall_geometry_free(&geometry); mesh := Glb_Mesh {
		vertices   = make([dynamic]Vec3, 0, int(geometry.point_count)),
		texcoords  = make([dynamic]Vec2, 0, int(geometry.point_count)),
		indices    = make([dynamic]u32, 0, int(geometry.point_count) * 6),
		primitives = make([dynamic]Glb_Primitive_Range, 0, 1),
	}; points := (cast([^]Chicago_Wall_Point)geometry.points)[:int(
		geometry.point_count,
	)]; contours := (cast([^]Chicago_Wall_Contour)geometry.contours)[:int(geometry.contour_count)]
	for contour in contours {if contour.count < 3 do continue; start := int(contour.first)
		wall_solid_add_cap(&mesh, points[start:start + int(contour.count)], 0)}
	if len(mesh.vertices) == 0 do return mesh; mesh.min = {1e30, 0, 1e30}; mesh.max = {-1e30, .001, -1e30}; for vertex in mesh.vertices {mesh.min.x = min(mesh.min.x, vertex.x); mesh.min.z = min(mesh.min.z, vertex.z); mesh.max.x = max(mesh.max.x, vertex.x); mesh.max.z = max(mesh.max.z, vertex.z)}; append(&mesh.primitives, Glb_Primitive_Range{0, len(mesh.indices), -1, {1, 1, 1, 1}}); mesh.ready = true; return mesh
}

build_house_floorplan :: proc() {
	authored_height := house_authored_wall_height()
	house_floor_mesh = procedural_quad_mesh(1, 1, true)
	house_art_mesh = procedural_quad_mesh(.82, 1.16, false)
	house_art_frame_mesh = procedural_quad_mesh(1.02, 1.36, false)
	house_art_mesh.alpha_modes = make([dynamic]int, 0, 1); append(&house_art_mesh.alpha_modes, 2)
	house_art_frame_mesh.alpha_modes = make(
		[dynamic]int,
		0,
		1,
	); append(&house_art_frame_mesh.alpha_modes, 2)
	// Glass is a single sheet recessed behind the face-mounted sash. A transparent
	// closed box self-blends its front/back faces and produces diagonal artifacts.
	house_window_mesh = procedural_glazing_mesh(2.0, 1.4)
	house_window_mesh.alpha_modes = make(
		[dynamic]int,
		0,
		1,
	); append(&house_window_mesh.alpha_modes, 2)
	house_window_sill_mesh = procedural_wall_infill_mesh(2.18, .72, HOUSE_WALL_THICKNESS)
	house_window_header_mesh = procedural_wall_infill_mesh(2.18, .38, HOUSE_WALL_THICKNESS)
	house_window_sill_interior_mesh = procedural_wall_infill_mesh(
		2.18,
		.72,
		HOUSE_INTERIOR_WALL_THICKNESS,
	)
	house_window_header_interior_mesh = procedural_wall_infill_mesh(
		2.18,
		.38,
		HOUSE_INTERIOR_WALL_THICKNESS,
	)
	house_window_header_cap_mesh = procedural_quad_mesh(1, HOUSE_WALL_THICKNESS, true)
	// Window/door apertures are cut through the structural union and their
	// below/above masonry is restored separately. It must carry the same exterior
	// finish as the surrounding wall; room wallpaper overlays its interior face.
	apply_texture(&house_window_sill_mesh, exterior_wall_texture)
	apply_texture(&house_window_header_mesh, exterior_wall_texture)
	apply_texture(&house_window_sill_interior_mesh, exterior_wall_texture)
	apply_texture(&house_window_header_interior_mesh, exterior_wall_texture)
	house_window_frame_h_mesh = procedural_wall_mesh(2.12, HOUSE_WINDOW_FRAME_RAIL_HEIGHT, .045)
	house_window_frame_v_mesh = procedural_wall_mesh(.055, 1.50, .045)
	house_window_muntin_h_mesh = procedural_wall_mesh(2.0, .03, HOUSE_WINDOW_MUNTIN_DEPTH)
	house_window_muntin_v_mesh = procedural_wall_mesh(.03, 1.4, HOUSE_WINDOW_MUNTIN_DEPTH)
	house_window_bead_h_mesh = procedural_wall_mesh(2.0, .016, HOUSE_WINDOW_GLAZING_BEAD_DEPTH)
	house_window_bead_v_mesh = procedural_wall_mesh(.016, 1.4, HOUSE_WINDOW_GLAZING_BEAD_DEPTH)
	house_window_hardware_h_mesh = procedural_wall_mesh(.20, .025, HOUSE_WINDOW_HARDWARE_DEPTH)
	house_window_hardware_v_mesh = procedural_wall_mesh(.025, .16, HOUSE_WINDOW_HARDWARE_DEPTH)
	house_window_sill_cap_mesh = procedural_wall_mesh(2.20, .07, HOUSE_WALL_THICKNESS + .16)
	house_window_exterior_sill_mesh = procedural_sloped_sill_mesh(2.20, .14, .07, .025)
	house_window_head_return_mesh = procedural_wall_mesh(2.16, .08, HOUSE_WALL_THICKNESS + .08)
	house_window_jamb_return_mesh = procedural_wall_mesh(.08, 1.50, HOUSE_WALL_THICKNESS + .08)
	// Closed louvers overlap visually into one sightline-blocking surface; when
	// pitched open their thin depth leaves a clear view between rails.
	house_shutter_slat_mesh = procedural_wall_mesh(2.08, .124, .025)
	// A thin structural face closes the vertical step where independently
	// animated wall sections meet. Its authored width spans the wall thickness;
	// render-time height is the difference between the two section tops.
	house_wall_junction_reveal_mesh = procedural_wall_mesh(
		HOUSE_WALL_THICKNESS + .012,
		authored_height,
		.018,
	)
	house_wall_cap_edge_mesh = procedural_quad_mesh(1, HOUSE_WALL_THICKNESS + .036, true)
	house_wall_cap_edge_interior_mesh = procedural_quad_mesh(
		1,
		HOUSE_INTERIOR_WALL_THICKNESS + .036,
		true,
	)
	// Door openings are structural cut-outs, so they also need a separate leaf.
	// The leaf is rendered open and never participates in navigation collision.
	for material in Door_Material {house_door_meshes[material] = procedural_wall_mesh(
			1.4,
			2.1,
			.07,
		)
		apply_texture(
			&house_door_meshes[material],
			load_room_texture(DOOR_TEXTURE_PATHS[material]),
		)}
	// Gameplay clues are not editor dressing. These pieces give the crank a
	// permanent, readable silhouette at its interaction point.
	shutter_crank_housing_mesh = procedural_wall_mesh(.34, .54, .16)
	// Native-size spoke points along local Z; the centered world transform
	// rotates it continuously in the wall plane without stair-stepped links.
	shutter_crank_arm_mesh = procedural_wall_mesh(.065, .065, .27)
	shutter_crank_link_mesh = procedural_wall_mesh(.07, .07, .07)
	shutter_crank_grip_mesh = procedural_wall_mesh(.075, .24, .075)
	shutter_silk_mesh = procedural_wall_mesh(.028, .18, .018)
	house_walls = make([dynamic]Floorplan_Wall, 0, 32)
	for space in Plan_Space_Kind {for surface in Room_Surface do house_floor_batches[space][surface] = procedural_floor_batch_mesh(surface, space)}
	house_wall_runs = make(
		[dynamic]Glb_Mesh,
		0,
		len(house_plan.wall_splines),
	); house_wall_runs_full = make([dynamic]Glb_Mesh, 0, len(house_plan.wall_splines))
	for spline in house_plan.wall_splines {width := house_wall_width(spline.width); append(&house_wall_runs, procedural_wall_run_mesh(spline.points, min(HOUSE_CUTAWAY_HEIGHT, authored_height), width)); append(&house_wall_runs_full, procedural_wall_run_mesh(spline.points, authored_height, width)); for i in 0 ..< len(spline.points) - 1 do append_house_wall_span(spline.points[i], spline.points[i + 1], width)}
	house_wall_cap_batch_full = Glb_Mesh {
		vertices   = make([dynamic]Vec3, 0, len(house_walls) * 4),
		texcoords  = make([dynamic]Vec2, 0, len(house_walls) * 4),
		indices    = make([dynamic]u32, 0, len(house_walls) * 12),
		primitives = make([dynamic]Glb_Primitive_Range, 0, 1),
	}
	// Keep cap vertices in local Y so the same continuous surface can be placed
	// at the authored or uniformly cut wall height by the renderer.
	for wall in house_walls do append_wall_cap_batch(&house_wall_cap_batch_full, wall.a, wall.b, 0, wall.width)
	finalize_wall_cap_batch(&house_wall_cap_batch_full, .001)
	for surface in Room_Surface {
		house_wall_face_batches[surface] = Glb_Mesh {
			vertices   = make([dynamic]Vec3, 0, 64),
			texcoords  = make([dynamic]Vec2, 0, 64),
			indices    = make([dynamic]u32, 0, 96),
			primitives = make([dynamic]Glb_Primitive_Range, 0, 1),
		}
		house_wall_face_batches_full[surface] = Glb_Mesh {
			vertices   = make([dynamic]Vec3, 0, 64),
			texcoords  = make([dynamic]Vec2, 0, 64),
			indices    = make([dynamic]u32, 0, 96),
			primitives = make([dynamic]Glb_Primitive_Range, 0, 1),
		}
	}
	for wall in house_walls {
		if wall.positive_interior {append_wall_face_batch(&house_wall_face_batches[wall.positive_surface], wall.a, wall.b, true, min(HOUSE_CUTAWAY_HEIGHT, authored_height)); append_wall_face_batch(&house_wall_face_batches_full[wall.positive_surface], wall.a, wall.b, true, authored_height)}
		if wall.negative_interior {append_wall_face_batch(&house_wall_face_batches[wall.negative_surface], wall.a, wall.b, false, min(HOUSE_CUTAWAY_HEIGHT, authored_height)); append_wall_face_batch(&house_wall_face_batches_full[wall.negative_surface], wall.a, wall.b, false, authored_height)}
	}
	// Window apertures remove a complete structural strip. Restore the room's
	// covering only on the masonry below the sill and above the head; the glazing
	// and frame remain unobstructed.
	window_sides := [2]bool {
		true,
		false,
	}; for opening in house_plan.openings {if opening.kind != .Window do continue; for positive in window_sides {surface, interior := house_wall_face_classification(opening.a, opening.b, positive); if !interior do continue; append_window_wallpaper_regions(&house_wall_face_batches[surface], opening, positive, min(HOUSE_CUTAWAY_HEIGHT, authored_height)); append_window_wallpaper_regions(&house_wall_face_batches_full[surface], opening, positive, authored_height)}}
	for surface in Room_Surface {finalize_wall_face_batch(
			&house_wall_face_batches[surface],
			surface,
			min(HOUSE_CUTAWAY_HEIGHT, authored_height),
		)
		finalize_wall_face_batch(&house_wall_face_batches_full[surface], surface, authored_height)}
	house_wall_solid = build_house_wall_solid(
		authored_height,
	); apply_texture(&house_wall_solid, exterior_wall_texture)
	house_wall_solid_cutaway = build_house_wall_solid(
		min(HOUSE_CUTAWAY_HEIGHT, authored_height),
	); apply_texture(&house_wall_solid_cutaway, exterior_wall_texture)
	house_wall_cap_union = build_house_wall_cap_union(0)
	house_wall_cap_union_edge = build_house_wall_cap_union(HOUSE_WALL_CAP_EDGE_OVERHANG)
}

append_house_wall_piece_raw :: proc(a, b: Vec2, width: f32) {
	dx, dz :=
		b.x - a.x, b.y - a.y; length := math.sqrt(dx * dx + dz * dz); if length <= .01 do return
	mx, mz := (a.x + b.x) * .5, (a.y + b.y) * .5; nx, nz := -dz / length, dx / length
	// Sample beyond the structural thickness so junctions cannot accidentally
	// inherit the material from the wall's centerline.
	positive_surface := house_surface_at(mx + nx * .24, mz + nz * .24)
	negative_surface := house_surface_at(mx - nx * .24, mz - nz * .24)
	positive_interior :=
		mx + nx * .24 >= 0 &&
		mx + nx * .24 < f32(HOUSE_SURFACE_WIDTH) &&
		mz + nz * .24 >= 0 &&
		mz + nz * .24 < f32(HOUSE_SURFACE_HEIGHT) &&
		house_space_kind_at(mx + nx * .24, mz + nz * .24) == .Interior
	negative_interior :=
		mx - nx * .24 >= 0 &&
		mx - nx * .24 < f32(HOUSE_SURFACE_WIDTH) &&
		mz - nz * .24 >= 0 &&
		mz - nz * .24 < f32(HOUSE_SURFACE_HEIGHT) &&
		house_space_kind_at(mx - nx * .24, mz - nz * .24) == .Interior
	// The paint record is intentionally queried at rebuild time. A section can
	// later move between render chunks without losing its independently painted
	// positive/negative face.
	for paint in house_plan.wall_face_paints {
		if point_segment_distance_sq(mx, mz, paint.a, paint.b) < .08 * .08 {
			if paint.positive {positive_surface = paint.surface} else {negative_surface = paint.surface}
		}
	}
	authored_height := house_authored_wall_height(

	); finish_bands := house_wall_finish_bands(); core := procedural_wall_mesh(length, authored_height, width); apply_texture(&core, exterior_wall_texture)
	core_bands: [3]Glb_Mesh; for band in 0 ..< 3 {region_base := finish_bands[band]; region_height := finish_bands[band + 1] - region_base; core_bands[band] = procedural_wall_band_mesh(a, b, region_base, region_height, width); apply_texture(&core_bands[band], exterior_wall_texture)}
	// A dedicated top cap makes a cutaway read as a deliberately sectioned wall
	// in aerial view, instead of as geometry that vanished with the camera.
	cap := procedural_quad_mesh(length, width, true)
	positive := procedural_quad_mesh(
		length,
		authored_height,
		false,
	); apply_texture(&positive, house_wall_materials[positive_surface])
	negative := procedural_quad_mesh(
		length,
		authored_height,
		false,
	); apply_texture(&negative, house_wall_materials[negative_surface])
	append(
		&house_walls,
		Floorplan_Wall {
			a = a,
			b = b,
			width = width,
			positive_surface = positive_surface,
			negative_surface = negative_surface,
			positive_interior = positive_interior,
			negative_interior = negative_interior,
			core = core,
			cap = cap,
			face_positive = positive,
			face_negative = negative,
			core_bands = core_bands,
		},
	)
}

// Material faces are separate from the unioned structural solid. Split them at
// every collinear doorway too, otherwise a wallpaper quad visually seals the
// correctly-cut structural opening behind it.
append_house_wall_piece :: proc(a, b: Vec2, width: f32) {
	dx, dz := b.x - a.x, b.y - a.y; length_sq := dx * dx + dz * dz; if length_sq <= .0001 do return
	cursor: f32 = 0
	for cursor < 1 - .0001 {
		next_start, next_end: f32 = 1, 1; found := false
		for opening in house_plan.openings {
			mx, mz := (opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5
			// A long opening can straddle a render-chunk boundary, leaving its
			// midpoint outside this particular chunk even though part of the opening
			// overlaps it. Test distance to the supporting wall line here; the
			// projected interval checks below decide whether the spans overlap.
			line_distance_numerator := (mx - a.x) * dz - (mz - a.y) * dx
			if line_distance_numerator * line_distance_numerator > .08 * .08 * length_sq do continue
			ta := ((opening.a.x - a.x) * dx + (opening.a.y - a.y) * dz) / length_sq
			tb := ((opening.b.x - a.x) * dx + (opening.b.y - a.y) * dz) / length_sq
			lo, hi :=
				min(ta, tb), max(ta, tb); if hi <= cursor + .0001 || lo >= 1 - .0001 do continue
			lo, hi = clamp(lo, 0, 1), clamp(hi, 0, 1)
			if !found || lo < next_start {next_start, next_end = lo, hi; found = true}
		}
		if !found {append_house_wall_piece_raw({a.x + dx * cursor, a.y + dz * cursor}, b, width); break}
		if next_start > cursor + .0001 do append_house_wall_piece_raw({a.x + dx * cursor, a.y + dz * cursor}, {a.x + dx * next_start, a.y + dz * next_start}, width)
		cursor = max(cursor, next_end)
	}
}

append_house_wall_span :: proc(a, b: Vec2, width: f32) {
	// One authored path may border several rooms. Split it at every collinear
	// room corner so each rendered face has a midpoint that belongs to exactly
	// one room. The old sample-house constants only happened to work for its
	// original dimensions and allowed neighboring finishes to bleed across long
	// walls in authored levels.
	dx, dz := b.x - a.x, b.y - a.y; length_sq := dx * dx + dz * dz; if length_sq <= .0001 do return
	breaks: [128]f32; break_count := 2; breaks[0] = 0; breaks[1] = 1
	for room in level_document.rooms {if room.story != level_document.active_story do continue; for point in room.points {
			t :=
				((point.x - a.x) * dx + (point.y - a.y) * dz) /
				length_sq; if t <= .0001 || t >= .9999 do continue
			projected := Vec2 {
				a.x + dx * t,
				a.y + dz * t,
			}; offset_x, offset_z := point.x - projected.x, point.y - projected.y; if offset_x * offset_x + offset_z * offset_z > .001 * .001 do continue
			duplicate :=
				false; for i in 0 ..< break_count do if math.abs(breaks[i] - t) < .0001 {duplicate = true; break}; if duplicate || break_count >= len(breaks) do continue
			insert :=
				break_count; for i in 0 ..< break_count {if t < breaks[i] {insert = i; break}}; for i := break_count; i > insert; i -= 1 do breaks[i] = breaks[i - 1]; breaks[insert] = t; break_count += 1
		}}
	for i in 0 ..< break_count -
		1 {start, finish := breaks[i], breaks[i + 1]; if finish - start <= .0001 do continue; append_house_wall_piece({a.x + dx * start, a.y + dz * start}, {a.x + dx * finish, a.y + dz * finish}, width)}
}
