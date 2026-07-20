package main

import "core:fmt"
import "core:math"
import "core:strings"

load_furniture_meshes :: proc() -> bool {
	for path, kind in FURNITURE_PATHS {furniture_meshes[kind], _ = glb_load(path)}
	assets_ok := true; ok: bool
	case_statuette_mesh, ok = glb_load(
		"assets/models/bronze-statuette.glb",
	); assets_ok = assets_ok && ok && case_statuette_mesh.ready
	case_cane_mesh, ok = glb_load(
		"assets/models/edgars-cane.glb",
	); assets_ok = assets_ok && ok && case_cane_mesh.ready
	case_ledger_mesh, ok = glb_load(
		"assets/models/private-ledger.glb",
	); assets_ok = assets_ok && ok && case_ledger_mesh.ready
	case_cloth_mesh, ok = glb_load(
		"assets/models/polishing-cloth.glb",
	); assets_ok = assets_ok && ok && case_cloth_mesh.ready
	case_oil_mesh, ok = glb_load(
		"assets/models/lamp-oil-bottle.glb",
	); assets_ok = assets_ok && ok && case_oil_mesh.ready
	case_watch_mesh, ok = glb_load(
		"assets/models/stopped-watch-824.glb",
	); assets_ok = assets_ok && ok && case_watch_mesh.ready
	case_wastebin_mesh, ok = glb_load(
		"assets/models/miriam-metal-wastebin.glb",
	); assets_ok = assets_ok && ok && case_wastebin_mesh.ready
	case_rug_unfolded_mesh, ok = glb_load(
		"assets/rugs/study_rug_unfolded.glb",
	); assets_ok = assets_ok && ok && case_rug_unfolded_mesh.ready
	case_rug_folded_mesh, ok = glb_load(
		"assets/rugs/study_rug_folded.glb",
	); assets_ok = assets_ok && ok && case_rug_folded_mesh.ready
	bloodstain_mesh = procedural_quad_mesh(1.6, 1.6, true)
	apply_texture(
		&bloodstain_mesh,
		load_room_texture("assets/models/crime-scene/bloodstain-decal.png"),
	)
	drag_trace_mesh = procedural_quad_mesh(5.6, 2.2, true)
	apply_texture(&drag_trace_mesh, load_room_texture("assets/decals/garden-drag-trace.png"))
	catalog_thumbnail_floor = procedural_quad_mesh(1, 1, true)
	vehicle_skid_mesh = procedural_quad_mesh(.12, .62, true)
	yard_grass_texture = load_room_texture(
		YARD_GRASS_TEXTURE_PATH,
	); yard_gravel_texture = load_room_texture(YARD_GRAVEL_TEXTURE_PATH); yard_dirt_texture = load_room_texture(YARD_DIRT_TEXTURE_PATH); yard_flagstone_texture = load_room_texture(YARD_FLAGSTONE_TEXTURE_PATH)
	roof_texture = load_room_texture(
		ROOF_TEXTURE_PATH,
	); exterior_wall_texture = load_room_texture(EXTERIOR_WALL_TEXTURE_PATH)
	for surface in Room_Surface {house_wall_materials[surface] = load_room_texture(
			WALL_COVERING_PATHS[surface],
		)
		house_floor_materials[surface] = procedural_quad_mesh(1, 1, true)
		apply_texture(
			&house_floor_materials[surface],
			load_room_texture(FLOOR_COVERING_PATHS[surface]),
		)}
	house_plan_initialize(); _ = house_plan_validate()
	level_validation := level_editor_initialize(

	); if !level_validation.ok {fmt.eprintln("level editor: ", level_validation.message); return false}
	load_catalog_object_meshes()
	build_house_floorplan()
	build_house_navmesh()
	return assets_ok
}
vertical_ranges_overlap :: proc(a_min, a_max, b_min, b_max: f32) -> bool {return(
		a_min < b_max &&
		a_max > b_min \
	)}

catalog_object_collision_bounds :: proc(object: Level_Object) -> (radius, base, top: f32) {
	entry, found := catalog_object_entry(object.catalog_id); radius = .35; height := f32(.5)
	if found {radius = max(entry.footprint, .2); mesh, mesh_found := catalog_object_mesh(object.catalog_id); if mesh_found do height = catalog_object_render_height(mesh, entry)
		else if entry.dimensions.y > 0 do height = entry.dimensions.y}
	base = object.elevation
	if level_terrain_supports_position(&level_document, object.position, object.story) do base += level_terrain_height(&level_document, object.position)
	return radius, base, base + height
}

catalog_object_blocks_movement :: proc(object: Level_Object) -> bool {
	entry, found := catalog_object_entry(object.catalog_id)
	// Rugs, runners, and doormats are authored floor coverings. Their footprint
	// is useful for selection, but it is not a collision volume.
	return !found || entry.category != "rugs"
}

furniture_blocked :: proc(x, y: f32) -> bool {
	ground := house_player_ground_height(
		{x, y},
	); player_min, player_max := ground + .05, ground + 1.65
	for item in house_plan.furniture {dx := x - item.x; dy := y - item.y; if dx * dx + dy * dy < item.radius * item.radius && vertical_ranges_overlap(player_min, player_max, item.elevation, item.elevation + item.height) do return true}
	for object in level_document.objects {
		if object.story != level_document.active_story || !catalog_object_blocks_movement(object) do continue
		radius, base, top := catalog_object_collision_bounds(
			object,
		); dx, dy := x - object.position.x, y - object.position.y
		if dx * dx + dy * dy < radius * radius && vertical_ranges_overlap(player_min, player_max, base, top) do return true
	}
	return false
}
water_blocked :: proc(x, y: f32) -> bool {if level_document.active_story != 0 do return false
	point := Vec2{x, y}
	for water in level_document.waters do if level_point_in_polygon(point, water.points[:]) do return true
	return false}
nav_cell_index :: proc(x, y: int) -> int {return y * HOUSE_NAV_WIDTH + x}
nav_cell_center :: proc(index: int) -> Vec2 {return{
		f32(index % HOUSE_NAV_WIDTH) * HOUSE_NAV_CELL + HOUSE_NAV_CELL * .5,
		f32(index / HOUSE_NAV_WIDTH) * HOUSE_NAV_CELL + HOUSE_NAV_CELL * .5,
	}}
nav_attic_roof_clearance :: proc(point: Vec2) -> (f32, bool) {
	story :=
		level_document.active_story; if story < 0 || story >= len(level_document.stories) do return 0, false
	active :=
		level_document.stories[story]; if active.name != "Attic" && !strings.has_prefix(active.id, "attic_") do return 0, false
	below := level_story_below(&level_document, story); if below < 0 do return 0, true
	best := f32(-1); for roof_index in 0 ..< generated_roof_count {
		if generated_roof_story[roof_index] != below do continue
		mesh := &generated_roof_meshes[roof_index]; for triangle := 0; triangle + 2 < len(mesh.indices); triangle += 3 {
			a, b, c :=
				mesh.vertices[mesh.indices[triangle]],
				mesh.vertices[mesh.indices[triangle + 1]],
				mesh.vertices[mesh.indices[triangle + 2]]
			denominator :=
				(b.z - c.z) * (a.x - c.x) +
				(c.x - b.x) * (a.z - c.z); if math.abs(denominator) < .00001 do continue
			u :=
				((b.z - c.z) * (point.x - c.x) + (c.x - b.x) * (point.y - c.z)) /
				denominator; v := ((c.z - a.z) * (point.x - c.x) + (a.x - c.x) * (point.y - c.z)) / denominator; w := 1 - u - v
			if u < -.0001 || v < -.0001 || w < -.0001 do continue
			height :=
				generated_roof_base_y[roof_index] +
				a.y * u +
				b.y * v +
				c.y * w -
				active.base_elevation; best = max(best, height)
		}
	}
	return best, true
}
nav_point_walkable :: proc(x, y: f32) -> bool {clearance := [5]Vec2 {
		{0, 0},
		{.24, 0},
		{-.24, 0},
		{0, .24},
		{0, -.24},
	}
	for 	offset in clearance {point := Vec2{x + offset.x, y + offset.y}; roof_height, attic :=
			nav_attic_roof_clearance(point)
		if attic && roof_height < HOUSE_ATTIC_NAV_CLEARANCE do return false
		if world_wall(point.x, point.y) || furniture_blocked(point.x, point.y) || water_blocked(point.x, point.y) do return false}
	return true}
nav_traversal_cost :: proc(point: Vec2) -> f32 {
	for path in level_document.paths {
		if path.story != level_document.active_story || (path.kind != .Footpath && path.kind != .Road) do continue
		radius := max(
			path.width * .5,
			HOUSE_NAV_CELL * .5,
		); for i in 0 ..< len(path.points) - 1 do if point_segment_distance_sq(point.x, point.y, path.points[i], path.points[i + 1]) <= radius * radius do return HOUSE_AUTHORED_PATH_COST
	}
	return 1
}
build_house_navmesh :: proc() {
	for y in 0 ..< HOUSE_NAV_HEIGHT {
		for x in 0 ..< HOUSE_NAV_WIDTH {center := nav_cell_center(nav_cell_index(x, y)); house_nav_walkable[nav_cell_index(x, y)] = nav_point_walkable(center.x, center.y)}}}
nav_nearest_walkable :: proc(point: Vec2) -> int {base_x := clamp(
		int(point.x / HOUSE_NAV_CELL),
		0,
		HOUSE_NAV_WIDTH - 1,
	)
	base_y := clamp(int(point.y / HOUSE_NAV_CELL), 0, HOUSE_NAV_HEIGHT - 1)
	for 	radius in 0 ..< max(HOUSE_NAV_WIDTH, HOUSE_NAV_HEIGHT) {for y := max(0, base_y - radius);
		    y <= min(HOUSE_NAV_HEIGHT - 1, base_y + radius);
		    y += 1 {for x := max(0, base_x - radius);
			    x <= min(HOUSE_NAV_WIDTH - 1, base_x + radius);
			    x += 1 {if x != base_x - radius && x != base_x + radius && y != base_y - radius && y != base_y + radius do continue
				index := nav_cell_index(x, y)
				if house_nav_walkable[index] do return index}}}
	return -1}
nav_build_path :: proc(g: ^Game, start, goal: Vec2) -> bool {
	start_index := nav_nearest_walkable(
		start,
	); goal_index := nav_nearest_walkable(goal); g.nav_path_count = 0; g.nav_path_index = 0; if start_index < 0 || goal_index < 0 do return false
	cost: [HOUSE_NAV_CELLS]f32; parent: [HOUSE_NAV_CELLS]int; closed: [HOUSE_NAV_CELLS]bool; for i in 0 ..< HOUSE_NAV_CELLS {cost[i] = 1e30; parent[i] = -1}; cost[start_index] = 0
	for _ in 0 ..< HOUSE_NAV_CELLS {current := -1; best: f32 = 1e30; for i in 0 ..< HOUSE_NAV_CELLS do if house_nav_walkable[i] && !closed[i] && cost[i] < best {best = cost[i]; current = i}; if current < 0 || current == goal_index do break; closed[current] = true; cx, cy := current % HOUSE_NAV_WIDTH, current / HOUSE_NAV_WIDTH; for oy := -1; oy <= 1; oy += 1 {for ox := -1; ox <= 1; ox += 1 {if ox == 0 && oy == 0 do continue; nx, ny := cx + ox, cy + oy; if nx < 0 || ny < 0 || nx >= HOUSE_NAV_WIDTH || ny >= HOUSE_NAV_HEIGHT do continue; neighbor := nav_cell_index(nx, ny); if !house_nav_walkable[neighbor] || closed[neighbor] do continue; if ox != 0 && oy != 0 && (!house_nav_walkable[nav_cell_index(cx + ox, cy)] || !house_nav_walkable[nav_cell_index(cx, cy + oy)]) do continue; step: f32 = ox != 0 && oy != 0 ? 1.4142135 : 1.0; candidate := cost[current] + step * nav_traversal_cost(nav_cell_center(neighbor)); if candidate < cost[neighbor] {cost[neighbor] = candidate; parent[neighbor] = current}}}}
	if goal_index != start_index && parent[goal_index] < 0 do return false; reverse: [256]Vec2; count := 0; node := goal_index; for node != start_index && count < len(reverse) {reverse[count] = nav_cell_center(node); count += 1; node = parent[node]}; for i := count - 1; i >= 0; i -= 1 {g.nav_path[g.nav_path_count] = reverse[i]; g.nav_path_count += 1}; if g.nav_path_count == 0 || g.nav_path[g.nav_path_count - 1].x != goal.x || g.nav_path[g.nav_path_count - 1].y != goal.y {if g.nav_path_count < len(g.nav_path) {g.nav_path[g.nav_path_count] = nav_cell_center(goal_index); g.nav_path_count += 1}}; return g.nav_path_count > 0
}
character_presentation :: proc(
	source_id: string,
) -> (
	animation: string,
	tint: [4]u8,
	phase_offset: f32,
) {
	if active_story_project.id !=
	   "" {if index := story_entity_index(&active_story_project, source_id); index >= 0 {entity := active_story_project.entities[index]; animation = entity.default_animation; if animation == "" do animation = "Idle_A"; tint = entity.presentation_tint; if tint[3] == 0 do tint = {255, 255, 255, 255}; return animation, tint, entity.animation_phase}}
	return "Idle_A", {255, 255, 255, 255}, 0
}

character_mesh_index :: proc(source_id: string) -> int {payload := mystery_payload(
		&active_story_project,
	)
	if payload != nil do for character, i in payload.characters do if character.entity_id == source_id && i + 1 < len(character_meshes) do return i + 1
	return 0}
character_mesh_for :: proc(source_id: string) -> ^Glb_Mesh {return(
		&character_meshes[character_mesh_index(source_id)] \
	)}
Character_Action :: enum {
	Interact,
	Sit,
	Jump,
	React,
	Death,
}
character_action_clip :: proc(mesh: ^Glb_Mesh, action: Character_Action) -> int {switch
	action {case .Interact:
		return glb_clip_index(mesh, "Interact"); case .Sit:
		return glb_clip_index_suffix(mesh, "_Sitting"); case .Jump:
		return glb_clip_index_suffix(mesh, "_Jump"); case .React:
		return glb_clip_index_suffix(mesh, "_Punch"); case .Death:
		return glb_clip_index_suffix(mesh, "_Death")}
	return -1}

initialize_character_animations :: proc(g: ^Game) {player_mesh := &character_meshes[0]
	player_idle := glb_clip_index(player_mesh, "Idle_A")
	g.player_animation = {
		current     = player_idle,
		next        = -1,
		idle_clip   = player_idle,
		action_clip = -1,
	}
	payload := mystery_game_payload(g)
	if payload == nil do return
	for character, i in payload.characters {if i >= len(g.character_animations) do break; mesh := character_mesh_for(character.entity_id)
		name, _, phase := character_presentation(character.entity_id)
		clip := glb_clip_index(mesh, name)
		duration := clip >= 0 ? mesh.clips[clip].duration : 0
		t := phase
		if duration > 0 do t -= f32(math.floor(f64(t / duration))) * duration
		g.character_animations[i] = {
			current     = clip,
			next        = -1,
			idle_clip   = clip,
			action_clip = -1,
			time        = t,
		}}}
character_animation_transition :: proc(state: ^Character_Animation, next: int) {if next < 0 || state.next == next && state.transitioning do return
	state.next = next
	state.next_time = 0
	state.transition = 0
	state.transitioning = true}
trigger_character_action :: proc(
	g: ^Game,
	source_id: string,
	action: Character_Action,
) -> bool {index := character_index(g, source_id); if index < 0 || index >= len(g.character_animations) do return false
	clip := character_action_clip(character_mesh_for(source_id), action)
	if clip < 0 do return false
	state := &g.character_animations[index]
	state.action_clip = clip
	state.action_loop = action == .Sit
	state.action_hold = action == .Death
	state.interacting = action == .Interact
	character_animation_transition(state, clip)
	return true}
trigger_character_interact :: proc(g: ^Game, source_id: string) {_ = trigger_character_action(
		g,
		source_id,
		.Interact,
	)}
stop_character_action :: proc(g: ^Game, source_id: string) -> bool {index := character_index(
		g,
		source_id,
	)
	if index < 0 || index >= len(g.character_animations) do return false
	state := &g.character_animations[index]
	if state.action_clip < 0 do return false
	state.action_clip = -1
	state.action_loop = false
	state.action_hold = false
	state.interacting = false
	next_idle := state.idle_clip
	if next_idle < 0 do next_idle = glb_clip_index(character_mesh_for(source_id), "Idle_A")
	character_animation_transition(state, next_idle)
	return true}
update_one_character_animation :: proc(
	mesh: ^Glb_Mesh,
	state: ^Character_Animation,
	dt: f32,
	idle_a, idle_b: int,
) {if state.current < 0 do return; state.time += dt; if state.transitioning {state.next_time += dt
		state.transition += dt / .25
		if state.transition >= 1 {state.current = state.next; state.time = state.next_time
			state.next = -1
			state.transition = 0
			state.transitioning = false}}
	if state.transitioning do return
	duration := mesh.clips[state.current].duration
	if state.current ==
	   state.action_clip {if duration > 0 && state.time >= duration {if state.action_loop do state.time -= f32(math.floor(f64(state.time / duration))) * duration
			else if state.action_hold do state.time = duration
			else {state.interacting = false; state.action_clip = -1; next_idle := state.idle_clip; if next_idle < 0 do next_idle = idle_a; character_animation_transition(state, next_idle)}}} else if state.current == idle_a || state.current == idle_b {state.idle_clip = state.current
		if duration > 0 &&
		   state.time >=
			   max(0, duration - .25) {next_idle := state.current == idle_a ? idle_b : idle_a
			state.idle_clip = next_idle
			character_animation_transition(state, next_idle)}}}
update_player_animation :: proc(g: ^Game, dt: f32) {mesh := &character_meshes[0]
	state := &g.player_animation
	idle := glb_clip_index(mesh, "Idle_A")
	walk := glb_clip_index(mesh, "Walking_B")
	run := glb_clip_index(mesh, "Running_A")
	running :=
		g.player_is_walking && g.player_walk_speed > HOUSE_MANUAL_MOVE_SPEED * 1.15 && run >= 0
	target := running ? run : (g.player_is_walking && walk >= 0 ? walk : idle)
	if target >=
	   0 {if state.transitioning && state.next != target {if state.current == target {state.current, state.next = state.next, state.current
				state.time, state.next_time = state.next_time, state.time
				state.transition =
					1 -
					state.transition} else {character_animation_transition(state, target)}} else if !state.transitioning && state.current != target do character_animation_transition(state, target)}
	reference_speed: f32 = running ? HOUSE_MANUAL_MOVE_SPEED * 1.5 : HOUSE_MANUAL_MOVE_SPEED
	clip_dt :=
		g.player_is_walking ? dt * clamp(g.player_walk_speed / reference_speed, .38, 1.35) : dt
	state.time += clip_dt
	if state.transitioning {state.next_time += clip_dt; state.transition += dt / .18
		if state.transition >= 1 {state.current = state.next; state.time = state.next_time
			state.next = -1
			state.transition = 0
			state.transitioning = false}}
	if !state.transitioning {duration := mesh.clips[state.current].duration; if duration > 0 && state.time >= duration do state.time -= f32(math.floor(f64(state.time / duration))) * duration}}
update_character_animations :: proc(g: ^Game, dt: f32) {update_player_animation(g, dt); payload :=
		mystery_game_payload(g)
	if payload == nil do return
	for 	&state, i in g.character_animations {if i >= len(payload.characters) do break; mesh := character_mesh_for(
			payload.characters[i].entity_id,
		)
		idle_a := glb_clip_index(mesh, "Idle_A")
		idle_b := glb_clip_index(mesh, "Idle_B")
		update_one_character_animation(mesh, &state, dt, idle_a, idle_b)}}

clue_for_source :: proc(g: ^Game, source_id: string) -> int {
	canonical := source_id
	if g != nil &&
	   g.story_project !=
		   nil {entity := story_entity_index(g.story_project, source_id); if entity >= 0 do for tag in g.story_project.entities[entity].tags[:g.story_project.entities[entity].tag_count] do if strings.has_prefix(tag, "clue_source=") do canonical = tag[len("clue_source="):]}
	payload := mystery_game_payload(
		g,
	); if payload != nil do for clue, i in payload.clues do if clue.source_id == canonical do return i; return -1
}

world_entity_binding_position :: proc(
	doc: ^Level_Document,
	entity: ^Story_Entity,
) -> (
	Vec2,
	bool,
) {
	if entity.spatial.space_id != doc.id || entity.spatial.target_id == "" do return {}, false
	switch entity.spatial.target_kind {
	case .Marker:
		index := level_marker_index(doc, entity.spatial.target_id)
		if index >= 0 do return doc.markers[index].position, true
	case .Room:
		index := level_room_index(doc, entity.spatial.target_id)
		if index >=
		   0 {room := doc.rooms[index]; center := Vec2{}; for point in room.points {center.x += point.x; center.y += point.y}; if len(room.points) > 0 {center.x /= f32(len(room.points)); center.y /= f32(len(room.points)); return center, true}}
	case .Entity:
		index := level_object_index(doc, entity.spatial.target_id)
		if index >= 0 do return doc.objects[index].position, true
	case .Interaction:
		if index := level_object_index(doc, entity.spatial.target_id); index >= 0 do return doc.objects[index].position, true
		if index := level_marker_index(doc, entity.spatial.target_id); index >= 0 do return doc.markers[index].position, true
		if index := level_opening_index(doc, entity.spatial.target_id); index >= 0 do return level_opening_position(doc, doc.openings[index])
	case .Transition:
		index := level_marker_index(doc, entity.spatial.target_id)
		if index >= 0 do return doc.markers[index].position, true
	}
	return {}, false
}

world_entities_rebuild :: proc(project: ^Story_Project, doc: ^Level_Document) -> Validation {
	clear(&WORLD_ENTITIES)
	if project == nil do return {false, "world entities require a StoryCore project"}
	for &entity in project.entities {
		if !story_entity_has_role(project, entity.id, "world_entity") do continue
		position, found := world_entity_binding_position(
			doc,
			&entity,
		); if !found do return {false, fmt.tprintf("world entity %s requires a valid LevelFormat spatial binding", entity.id)}
		if world_entity_index(entity.id) >= 0 do return {false, fmt.tprintf("duplicate world entity binding: %s", entity.id)}
		kind := entity.kind == "character" || entity.kind == "person" ? "person" : "object"
		elevation, facing, scale := f32(0), f32(0), f32(1)
		if index := level_marker_index(doc, entity.spatial.target_id);
		   index >=
		   0 {elevation = doc.markers[index].camera_height; facing = doc.markers[index].facing * f32(math.PI) / 180; if doc.markers[index].radius > 0 do scale = doc.markers[index].radius}
		item := World_Entity {
			x           = position.x,
			y           = position.y,
			elevation   = elevation,
			facing      = facing,
			scale       = scale,
			kind        = kind,
			source_id   = entity.id,
			name        = entity.display_name,
			description = entity.description,
			appearance  = entity.appearance_model_asset_ref,
			tag_count   = entity.tag_count,
		}
		for tag, i in entity.tags[:entity.tag_count] do item.tags[i] = tag
		append(&WORLD_ENTITIES, item)
	}
	if len(WORLD_ENTITIES) == 0 do return {false, "story defines no world_entity roles"}
	return {true, fmt.tprintf("projected %d authored world entities", len(WORLD_ENTITIES))}
}

world_entity_index :: proc(source_id: string) -> int {for entity, i in WORLD_ENTITIES do if entity.source_id == source_id do return i
	return -1}
world_entity_id_has_tag :: proc(source_id, tag: string) -> bool {index := world_entity_index(
		source_id,
	)
	if index >= 0 do return world_entity_has_tag(&WORLD_ENTITIES[index], tag)
	if active_story_project.id != "" do return story_entity_has_tag(&active_story_project, source_id, tag)
	return false}
game_entity_has_tag :: proc(g: ^Game, source_id, tag: string) -> bool {if g != nil && g.story_project != nil && story_entity_has_tag(g.story_project, source_id, tag) do return true
	return world_entity_id_has_tag(source_id, tag)}
game_entity_id_with_tag :: proc(g: ^Game, tag: string) -> string {if g != nil && g.story_project != nil do for entity in g.story_project.entities do if story_entity_has_tag(g.story_project, entity.id, tag) do return entity.id
	return ""}
world_marker_pose :: proc(
	id: string,
	fallback_position: Vec2,
	fallback_radius, fallback_facing: f32,
) -> (
	Vec2,
	f32,
	f32,
) {
	index := level_marker_index(
		&level_document,
		id,
	); if index < 0 do return fallback_position, fallback_radius, fallback_facing
	marker :=
		level_document.markers[index]; return marker.position, max(marker.radius, .01), marker.facing * f32(math.PI) / 180
}
world_rotated_object_anchor :: proc(
	object: Level_Object,
	offset: Vec2,
	authored_rotation: f32,
) -> Vec2 {angle := (object.rotation - authored_rotation) * f32(math.PI) / 180; c, s :=
		f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))
	return{
		object.position.x + offset.x * c - offset.y * s,
		object.position.y + offset.x * s + offset.y * c,
	}}
open_evidence_dialogue :: proc(g: ^Game, index: int) -> bool {
	if index < 0 || index >= len(WORLD_ENTITIES) || WORLD_ENTITIES[index].kind == "person" do return false
	g.dialogue_entity =
		index; g.dialogue_node = 0; g.dialogue_ledger_scroll = 0; g.dialogue_choice_page = 0; g.dialogue_response = ""; g.dialogue_text_started = g.animation_time; g.pending_dialogue_approach = 0; g.check_from_dialogue = false; g.screen = .Dialogue; dialogue_focus_default(g)
	return true
}
entity_examination_complete :: proc(g: ^Game, entity_index: int) -> bool {
	if entity_index < 0 || entity_index >= len(WORLD_ENTITIES) do return false
	clue := clue_for_source(g, WORLD_ENTITIES[entity_index].source_id)
	return clue >= 0 && mystery_game_clue_discovered(g, clue)
}
world_authored_room_at_point :: proc(point: Vec2) -> int {
	story := max(level_document.active_story, 0)
	for room, i in level_document.rooms do if room.story == story && level_point_in_polygon(point, room.points[:]) do return i
	return -1
}

world_location_id_for_room :: proc(room_id: string) -> string {
	// Most authored room IDs are the investigative location IDs. These two
	// names predate that convention in the Vale House source document.
	switch room_id {case "gallery":
		return "hall"; case "moon_garden":
		return "garden"}
	return room_id
}

world_room_open_connection :: proc(a_index, b_index: int) -> bool {
	if a_index < 0 || b_index < 0 || a_index >= len(level_document.rooms) || b_index >= len(level_document.rooms) do return false
	a_room, b_room := &level_document.rooms[a_index], &level_document.rooms[b_index]
	if a_room.story != b_room.story do return false
	for a, i in a_room.points {b := a_room.points[(i + 1) % len(a_room.points)]; adx, ady := b.x - a.x, b.y - a.y; length_sq := adx * adx + ady * ady; if length_sq < .0001 do continue
		for c, j in b_room.points {d := b_room.points[(j + 1) % len(b_room.points)]; cdx, cdy := d.x - c.x, d.y - c.y
			if math.abs(adx * cdy - ady * cdx) > .001 || point_segment_distance_sq(c.x, c.y, a, b) > .001 && point_segment_distance_sq(d.x, d.y, a, b) > .001 do continue
			t0 :=
				((c.x - a.x) * adx + (c.y - a.y) * ady) /
				length_sq; t1 := ((d.x - a.x) * adx + (d.y - a.y) * ady) / length_sq; start, end := max(0, min(t0, t1)), min(1, max(t0, t1)); if end - start < .02 do continue
			// An authored wall path means the rooms meet through a doorway or arch.
			// With no wall across their shared edge, they form one visual search area.
			mid := Vec2 {
				a.x + adx * (start + end) * .5,
				a.y + ady * (start + end) * .5,
			}; wall_present := false
			for path in level_document.paths {if path.story != a_room.story || path.kind != .Wall && path.kind != .Freestanding_Wall do continue; for k in 0 ..< len(path.points) - 1 {p, q := path.points[k], path.points[k + 1]; pdx, pdy := q.x - p.x, q.y - p.y; if math.abs(adx * pdy - ady * pdx) > .001 do continue; if point_segment_distance_sq(mid.x, mid.y, p, q) < .001 {wall_present = true; break}}; if wall_present do break}
			if !wall_present do return true
		}
	}
	return false
}

world_room_location_index :: proc(g: ^Game, room_index: int) -> int {
	if room_index < 0 || room_index >= len(level_document.rooms) do return -1
	id := world_location_id_for_room(
		level_document.rooms[room_index].id,
	); payload := mystery_game_payload(g); if payload != nil do for location, i in payload.locations do if location.entity_id == id do return i
	return -1
}

world_location_index :: proc(g: ^Game) -> int {
	room_index := world_authored_room_at_point({g.player_x, g.player_y})
	if room_index < 0 do return -1
	location_id := world_location_id_for_room(level_document.rooms[room_index].id)
	payload := mystery_game_payload(
		g,
	); if payload != nil do for location, i in payload.locations do if location.entity_id == location_id do return i
	return -1
}

world_location_label :: proc(g: ^Game) -> string {
	location := world_location_index(g)
	payload := mystery_game_payload(
		g,
	); if payload != nil && location >= 0 && location < len(payload.locations) do return character_display_name(g, payload.locations[location].entity_id)
	room := world_authored_room_at_point({g.player_x, g.player_y})
	if room >= 0 do return level_document.rooms[room].name
	return fmt.tprintf("%s · GROUNDS", level_document.name)
}
poi_index :: proc(g: ^Game, id: string) -> int {payload := mystery_game_payload(g); if payload != nil do for poi, i in payload.pois do if poi.entity_id == id do return i
	return -1}
entity_visible :: proc(g: ^Game, e: ^World_Entity) -> bool {
	if g.story_project !=
	   nil {if index := story_entity_index(g.story_project, e.source_id); index >= 0 {condition := g.story_project.entities[index].visibility_condition_id; if condition != "" && g.story_runtime != nil do return story_runtime_condition_eval(g.story_runtime, condition).value}}
	if world_entity_has_tag(e, "visible_when_desk_open") do return g.desk_open
	if world_entity_has_tag(e, "initially_hidden") do return false
	i := poi_index(g, e.source_id); if i < 0 do return true; return mystery_game_poi_revealed(g, i)
}
location_reveals_pois :: proc(g: ^Game, index: int) -> bool {payload := mystery_game_payload(g)
	if payload == nil || index < 0 || index >= len(payload.locations) do return false
	location := &payload.locations[index]
	for i in 0 ..< location.search_action_count do if location.search_actions[i] == "search" do return true
	return false}
reveal_location_pois :: proc(g: ^Game, index: int) -> bool {payload := mystery_game_payload(g)
	if payload == nil || g.mystery_state == nil || index < 0 || index >= len(payload.locations) || !location_reveals_pois(g, index) do return false
	rooms := make([]bool, len(level_document.rooms), context.temp_allocator)
	pending := make([dynamic]int, 0, len(level_document.rooms), context.temp_allocator)
	for _, i in level_document.rooms do if world_room_location_index(g, i) == index {rooms[i] = true; append(&pending, i)}
	for cursor := 0;
	    cursor < len(pending);
	    cursor += 1 {room := pending[cursor]; for _, other in level_document.rooms {if rooms[other] || !world_room_open_connection(room, other) do continue
			rooms[other] = true
			append(&pending, other)}}
	locations := make([]bool, len(payload.locations), context.temp_allocator)
	locations[index] = true
	for connected, room in rooms do if connected {location := world_room_location_index(g, room); if location >= 0 && location < len(locations) do locations[location] = true}
	changed := false
	revealed := 0
	for connected, location in locations do if connected && mystery_game_mark_location_searched(g, location) do changed = true
	for poi, i in payload.pois {location := false; for connected, location_index in locations do if connected && poi.location_id == payload.locations[location_index].entity_id {location = true; break}
		if location {
			// The ledger remains inside its locked desk, and the cloth belongs to the
			// service closet rather than the pantry's general arrival reveal.
			if poi.entity_id == "ledger" || poi.entity_id == "cloth" do continue
			if mystery_game_mark_poi_revealed(g, i) {revealed += 1; changed = true}
		}}
	if !changed do return false
	g.location_result = fmt.tprintf(
		"%s — %d point%s of interest revealed.",
		character_display_name(g, payload.locations[index].entity_id),
		revealed,
		revealed == 1 ? "" : "s",
	)
	log_line(g, g.location_result)
	return true}

reveal_service_closet :: proc(g: ^Game) -> bool {
	if g.service_closet_entered do return false
	// The rear bay of the service wing reads as a closet through its shelving
	// and narrow approach. Crossing into it is the search action.
	if g.player_x < 28 || g.player_y < 18 do return false
	g.service_closet_entered =
		true; index := poi_index(g, "cloth"); if index < 0 || !mystery_game_mark_poi_revealed(g, index) do return false
	g.location_result = "SERVICE CLOSET — A damp polishing cloth is tucked among the supplies."; log_line(g, g.location_result); context_feedback(g, "POLISHING CLOTH DISCOVERED", .Available, "cloth"); return true
}
public_source_description :: proc(g: ^Game, source_id: string) -> string {
	if index := world_entity_index(source_id); index >= 0 && WORLD_ENTITIES[index].description != "" do return WORLD_ENTITIES[index].description
	if g.story_project !=
	   nil {if index := story_entity_index(g.story_project, source_id); index >= 0 && g.story_project.entities[index].description != "" do return g.story_project.entities[index].description}
	return "There is more here than first appears."
}
reflective_interaction_rect :: proc() -> Rect {return {650, 420, 490, 58}}
dining_walkthrough_rect :: proc() -> Rect {return {650, 574, 490, 52}}
pond_reflection_line :: proc(g: ^Game) -> string {
	known := known_piece_count(g)
	if knowledge_piece_known(g, "ded_miriam_denial_disproved") do return "The pond joins the shuttered window to its reflection without a seam. The appointment has done the same to two scraps of paper. What remains is to make the room live through the joined account."
	daniel_explained := knowledge_piece_known(g, "ded_daniel_affair")
	elsie_explained := knowledge_piece_known(g, "ded_elsie_theft")
	if daniel_explained && elsie_explained do return "Two lies have opened instead of closed: one leaves a chair unwatched, the other puts someone at the study door. Neither is the lie the fire was meant to erase."
	if daniel_explained || elsie_explained do return "One polished account has cracked and revealed a private fear beneath it. The other voices in Vale House may be protecting wrongs that are not murder, too."
	if knowledge_piece_known(g, "ded_scene_staged") || knowledge_piece_known(g, "ded_body_moved") do return "The garden is no longer a death scene; it is a performance left in the rain. The useful question is not what the audience saw, but who needed them to see it."
	if topic_unlocked(g, "edgar_controlled_by_correction") && topic_unlocked(g, "edgar_kept_leverage") && topic_unlocked(g, "edgar_household_power") do return "Three portraits of Edgar align in the water: clocks corrected, drafts retained, a bell pulled twice before blame. He made control look like order. The useful question is who learned to imitate him—and who merely learned to fear him."
	if known == 0 do return "Rain breaks your reflection into pieces before it can settle. The house behind you is much the same: a collection of surfaces, not yet an account."
	if known < 5 do return fmt.tprintf("Your reflection gathers between the raindrops. %d facts now hold their shape; the spaces between them are what trouble you.", known)
	return(
		"The pond gives you back a tired but recognizable face. Enough facts are on record to distrust the picture; now they must be made to belong to the same night." \
	)
}
dining_walkthrough_line :: proc(g: ^Game) -> string {
	if claim_known(g, "claim_miriam_dinner") && claim_known(g, "claim_daniel_alibi") do return "You speak the table aloud: fish at 8:20; Miriam's chair pushed back, her wine trailing; Daniel's napkin gone. Their two accounts depend on two empty places pretending to witness each other."
	return(
		"You speak the arrangement aloud: fish served at 8:20, two untouched settings, one chair pushed back and one napkin missing. The table records absence more faithfully than the household does." \
	)
}
apply_player_spawn_marker :: proc(g: ^Game, id := "spawn_player") -> bool {
	index := level_marker_index(&level_document, id); if index < 0 do return false
	spawn :=
		level_document.markers[index]; g.player_x = spawn.position.x; g.player_y = spawn.position.y; g.player_angle = spawn.facing * f32(math.PI) / 180; g.camera_x = g.player_x; g.camera_y = g.player_y; g.camera_initialized = true; g.move_target_active = false; g.nav_path_count = 0; g.nav_path_index = 0
	return true
}
investigation_unresolved_summary :: proc(g: ^Game) -> string {
	payload := mystery_game_payload(g)
	if payload == nil do return "The house is secured. No witness accounts or scene findings have been entered in the record."
	if !claim_known(g, "claim_miriam_dinner") || !claim_known(g, "claim_daniel_alibi") || !claim_known(g, "claim_elsie_study") do return "Miriam Vale, Daniel Cross, and Elsie Ward remain separated. Their first accounts are not all in the record."
	if !g.desk_key_found do return "The body and Edgar's effects remain under guard. His pockets and watch have not yet been entered in the case record."
	disputed := 0; for i in 0 ..< g.workbench_event_count do if event_chain_disputed(g, i) do disputed += 1
	if disputed > 0 do return fmt.tprintf("The evidence board still contains %d disputed event%s. No sequence in the record has cleared %s.", disputed, disputed == 1 ? "" : "s", disputed == 1 ? "it" : "them")
	for &question, i in payload.questions do if question_unlocked(g, i) && !question_resolved(g, i) do return fmt.tprintf("The case board still carries one unanswered point: %s", question.prompt)
	clue, _ := case_sense_target(
		g,
	); if clue >= 0 do return fmt.tprintf("One secured source remains unexamined: %s.", case_sense_source_name(g, clue))
	sources := [3]string {
		"miriam",
		"daniel",
		"elsie",
	}; for source in sources {if dialogue_available_approach_count(g, source) > 0 do return fmt.tprintf("%s's account still has a question supported by facts already in the record.", character_display_name(g, source))}
	if g.workbench_event_count > 0 do return "The chronology on the board has no unresolved conflicts. Everyone remains assembled and the house is secure."
	return(
		"No new statement or scene result has entered the record since the last review. The house remains secure." \
	)
}
known_claim_text :: proc(g: ^Game, source_id: string) -> string {
	payload := mystery_game_payload(
		g,
	); if payload != nil {character := mystery_character_metadata(payload, source_id); if character != nil do for i in 0 ..< character.initial_claim_count {claim_id := character.initial_claims[i]; if claim_known(g, claim_id) {claim_index := mystery_claim_index(payload, claim_id); if claim_index >= 0 do return mystery_story_proposition_text(g.story_project, payload.claims[claim_index].proposition_id)}}}
	return "No statement has been established yet."
}
character_reentry_line :: proc(g: ^Game, source_id: string) -> string {
	known := proc(g: ^Game, id: string) -> bool {return knowledge_piece_known(g, id)}
	switch source_id {
	case "miriam":
		if known(g, "ded_miriam_denial_disproved") do return "Miriam leaves the corner of Edgar's blotter crooked. 'You have your scrap of paper, Lieutenant. I suppose you mean to make it speak for the whole house.'"
		if known(g, "ded_daniel_affair") && known(g, "ded_elsie_theft") do return "Miriam's gaze moves from Daniel to Elsie and back to you. 'How industrious. You have taught confession to everyone except the person you came to accuse.'"
		if known(g, "ded_scene_staged") do return "Miriam straightens a chair that was already square. 'You have decided the garden is a performance. Do try not to confuse an audience with an author.'"
		return(
			"Miriam makes room for exactly one question. 'You have returned. I assume that means you can now ask it precisely.'" \
		)
	case "daniel":
		if known(g, "ded_miriam_denial_disproved") do return "Daniel does not reach for the joined paper. 'That is Edgar's habit exactly: tear a meeting in half, then let the missing piece frighten you.'"
		if known(g, "ded_daniel_affair") do return "Daniel folds Miriam's note along its old crease. 'You know what I was protecting. That does not make me proud of how well I protected it.'"
		if known(g, "ded_scene_staged") do return "Daniel watches the study door. 'A false garden death is an accusation with the name omitted. I imagine you are here to supply it.'"
		if topic_unlocked(g, "failed_daniel_affair") do return "Daniel keeps one hand clear of his coat by visible effort. 'You may ask about dinner, Lieutenant. My pockets are not part of the estate.'"
		return(
			"Daniel closes his watch before you can read it. 'Another question, Lieutenant? I will attempt a less professionally useless answer.'" \
		)
	case "elsie":
		if known(g, "ded_miriam_denial_disproved") do return "Elsie looks toward Miriam's sitting room. 'Paper burns from the edges inward. People seem to do it the other way round.'"
		if known(g, "ded_elsie_theft") do return "Elsie's hand passes over the now-empty pocket of her apron. 'You know the worst thing I did tonight. That makes the rest easier to say, though not much easier.'"
		if known(g, "ded_scene_staged") do return "Elsie glances toward the terrace. 'Gardens do not tidy themselves, Lieutenant. Nor do dead gentlemen.'"
		if topic_unlocked(g, "failed_elsie_theft") do return "Elsie stands between you and Edgar's desk without appearing to. 'If you have another question, ask it without deciding the answer first.'"
		return(
			"Elsie dries her hands on an apron already dry. 'Ask, then. The work will still be waiting when we have finished.'" \
		)
	}
	return ""
}
dialogue_summary :: proc(value: string) -> string {if len(value) <= 43 do return value
	return fmt.tprintf("%s...", value[:40])}

point_segment_distance_sq :: proc(px, py: f32, a, b: Vec2) -> f32 {
	dx, dy := b.x - a.x, b.y - a.y; length_sq := dx * dx + dy * dy
	if length_sq <= 0.0001 {ex, ey := px - a.x, py - a.y; return ex * ex + ey * ey}
	t := clamp(
		((px - a.x) * dx + (py - a.y) * dy) / length_sq,
		0,
		1,
	); ex, ey := px - (a.x + dx * t), py - (a.y + dy * t); return ex * ex + ey * ey
}
shutter_crank_world_position :: proc() -> (Vec2, bool) {
	for &entity in WORLD_ENTITIES do if world_entity_has_tag(&entity, "shutter_mechanism") do return {entity.x, entity.y}, true
	return {}, false
}
