package main

import "core:math"
import "core:strings"

runtime_interactive_index :: proc(g: ^Game, id: string) -> int {for interactive, i in g.interactives[:g.interactive_count] do if interactive.id == id do return i
	return -1}
runtime_interactive_position :: proc(g: ^Game, index: int) -> (Vec2, bool) {if index < 0 || index >= g.interactive_count do return {}, false
	item := g.interactives[index]
	if world_entity_id_has_tag(item.id, "shutter_mechanism") {position, found :=
			shutter_crank_world_position()
		if found do return position, true}
	for opening in house_plan.openings do if opening.id == item.id do return {(opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5}, true
	for object in level_document.objects do if object.id == item.id do return object.position, true
	for marker in level_document.markers do if marker.reference == item.id do return marker.position, true
	return {}, false}
runtime_interactives_rebuild :: proc(g: ^Game) {
	g.interactive_count = 0; g.hover_interactive = -1; g.near_interactive = -1; g.auto_door = -1
	for opening in level_document.openings {if opening.kind != .Door || opening.interaction != .Door || g.interactive_count >= len(g.interactives) do continue; open := opening.initially_active ? f32(1) : f32(0); item := Runtime_Interactive {
				id                = opening.id,
				prompt            = opening.interaction_prompt,
				condition_id      = opening.condition_id,
				focused_scene     = opening.focused_scene,
				behavior          = .Door,
				openness          = open,
				target            = open,
				interaction_range = opening.interaction_range,
				effect_id_count   = opening.effect_id_count,
				active            = opening.initially_active,
				locked            = opening.locked,
				powered           = opening.powered,
			}; for effect, i in opening.effect_ids do item.effect_ids[i] = effect; g.interactives[g.interactive_count] = item; g.interactive_count += 1}
	for object in level_document.objects {if object.interaction == .None || g.interactive_count >= len(g.interactives) do continue; level := object.initially_active ? f32(1) : f32(0); item := Runtime_Interactive {
				id                = object.id,
				prompt            = object.interaction_prompt,
				condition_id      = object.condition_id,
				focused_scene     = object.focused_scene,
				behavior          = object.interaction,
				openness          = level,
				target            = level,
				light_level       = level,
				interaction_range = object.interaction_range,
				effect_id_count   = object.effect_id_count,
				active            = object.initially_active,
				locked            = object.locked,
				powered           = object.powered,
			}; for effect, i in object.effect_ids do item.effect_ids[i] = effect; g.interactives[g.interactive_count] = item; g.interactive_count += 1}
	for marker in level_document.markers {if marker.interaction == .None || g.interactive_count >= len(g.interactives) do continue; level := marker.initially_active ? f32(1) : f32(0); id := marker.reference; if id == "" do id = marker.id; item := Runtime_Interactive {
				id                = id,
				prompt            = marker.interaction_prompt,
				condition_id      = marker.condition_id,
				focused_scene     = marker.focused_scene,
				behavior          = marker.interaction,
				openness          = level,
				target            = level,
				interaction_range = marker.interaction_range,
				effect_id_count   = marker.effect_id_count,
				active            = marker.initially_active,
				locked            = marker.locked,
				powered           = marker.powered,
			}; for effect, i in marker.effect_ids do item.effect_ids[i] = effect; g.interactives[g.interactive_count] = item; g.interactive_count += 1}
}
runtime_door_opening :: proc(g: ^Game, opening: Plan_Opening) -> f32 {index :=
		runtime_interactive_index(g, opening.id)
	if index < 0 do return 1
	return g.interactives[index].openness}
runtime_interactive_prompt :: proc(g: ^Game, index: int) -> string {if index < 0 || index >= g.interactive_count do return "INTERACT"
	item := g.interactives[index]
	if item.locked do return "LOCKED"
	if !item.powered do return "NO POWER"
	if item.prompt != "" do return item.prompt
	switch
	item.behavior {case .Door:
		return item.target >= .5 ? "CLOSE DOOR" : "OPEN DOOR"; case .Toggle:
		return item.active ? "TURN OFF LAMP" : "TURN ON LAMP"; case .Shutter:
		return g.shutter_target >= .5 ? "CRANK SHUTTER CLOSED" : "CRANK SHUTTER OPEN"; case .None:}
	return "INTERACT"}

context_runtime_authored :: proc(id: string) -> (label, prompt: string) {
	for opening in level_document.openings do if opening.id == id {prompt = opening.interaction_prompt; label = strings.to_upper(prompt); if strings.has_prefix(label, "OPEN ") do label = label[5:]
		else if strings.has_prefix(label, "CLOSE ") do label = label[6:]
		else if strings.has_prefix(label, "USE ") do label = label[4:]; if label == "" do label = "DOOR"; return}
	for object in level_document.objects do if object.id == id {
		prompt = object.interaction_prompt
		if prompt != "" {label = strings.to_upper(prompt); if strings.has_prefix(label, "USE ") do label = label[4:]}
		if label == "" {clean, _ := strings.replace_all(object.catalog_id, "_", " "); label = strings.to_upper(clean)}
		return
	}
	for entity in WORLD_ENTITIES do if entity.source_id == id do return entity.name, ""
	clean, _ := strings.replace_all(id, "_", " "); return strings.to_upper(clean), ""
}

context_runtime_target :: proc(g: ^Game, index: int) -> Context_Target {
	if index < 0 || index >= g.interactive_count do return {}
	item :=
		g.interactives[index]; position, found := runtime_interactive_position(g, index); if !found do return {}
	label, _ := context_runtime_authored(
		item.id,
	); action := runtime_interactive_prompt(g, index); status := Context_Status.Available
	if item.behavior == .Shutter do label = "STUDY SHUTTER"
	if item.locked do status = .Locked
	else if !item.powered do status = .No_Power
	if item.behavior == .Door &&
	   item.target >=
		   .5 {dx, dy := position.x - g.player_x, position.y - g.player_y; if dx * dx + dy * dy < 1.05 * 1.05 {status = .Obstructed; action = "STEP CLEAR TO CLOSE"}}
	dx, dy :=
		position.x -
		g.player_x,
		position.y -
		g.player_y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
	return {
		valid = true,
		kind = .Runtime_Interactive,
		status = status,
		stable_id = item.id,
		label = label,
		action = action,
		world = position,
		source_index = -1,
		runtime_index = index,
		priority = 30,
		distance = distance,
		reachable = runtime_near_interactive_candidate(g, index),
	}
}

runtime_near_interactive_candidate :: proc(g: ^Game, index: int) -> bool {
	if index < 0 || index >= g.interactive_count do return false
	item :=
		g.interactives[index]; position, found := runtime_interactive_position(g, index); if !found do return false; interaction_range := item.interaction_range; if interaction_range <= 0 do interaction_range = 1.8
	dx, dy := position.x - g.player_x, position.y - g.player_y
	return(
		dx * dx + dy * dy <= interaction_range * interaction_range &&
		world_interaction_line_clear(g, g.player_x, g.player_y, position.x, position.y, item.id) \
	)
}

context_entity_target :: proc(g: ^Game, index: int) -> Context_Target {
	if index < 0 || index >= len(WORLD_ENTITIES) || !entity_visible(g, &WORLD_ENTITIES[index]) do return {}
	entity :=
		WORLD_ENTITIES[index]; position := Vec2{entity.x, entity.y}; if world_entity_has_tag(&entity, "shutter_mechanism") {anchor, found := shutter_crank_world_position(); if found do position = anchor}; dx, dy := position.x - g.player_x, position.y - g.player_y; distance := f32(math.sqrt(f64(dx * dx + dy * dy))); complete := entity_examination_complete(g, index)
	action := entity.kind == "person" ? "TALK" : "EXAMINE"; status := Context_Status.Available
	if g.story_project !=
	   nil {if story_index := story_entity_index(g.story_project, entity.source_id); story_index >= 0 {authored := g.story_project.entities[story_index]; if authored.interaction_prompt != "" do action = authored.interaction_prompt; if authored.availability_condition_id != "" && g.story_runtime != nil && !story_runtime_condition_eval(g.story_runtime, authored.availability_condition_id).value {status = .Locked; if authored.unavailable_prompt != "" do action = authored.unavailable_prompt}; if authored.completion_condition_id != "" && g.story_runtime != nil && story_runtime_condition_eval(g.story_runtime, authored.completion_condition_id).value {status = .Complete; if authored.completion_prompt != "" do action = authored.completion_prompt}}}
	if complete {action = "EXAMINED"; status = .Complete}
	if world_entity_has_tag(
		&entity,
		"liftable_rug",
	) {action = g.study_rug_lifted ? "BLOOD EXPOSED" : "LIFT RUG"; if g.study_rug_lifted do status = .Complete}
	if world_entity_has_tag(&entity, "shutter_mechanism") {
		moving := math.abs(g.shutter_target - g.shutter_position) > .01
		action =
			moving ? (g.shutter_target > .5 ? "CRANKING SHUTTER OPEN" : "CRANKING SHUTTER CLOSED") : (g.shutter_target >= .5 ? "CRANK SHUTTER CLOSED" : "CRANK SHUTTER OPEN")
		status = .Available
	}
	priority :=
		world_entity_has_tag(&entity, "initially_hidden") ? 40 : entity.kind == "person" ? 24 : 20
	return {
		valid = true,
		kind = .Story_Entity,
		status = status,
		stable_id = entity.source_id,
		label = entity.name,
		action = action,
		world = position,
		source_index = index,
		runtime_index = -1,
		priority = priority,
		distance = distance,
		reachable = world_interaction_reachable(g, index),
	}
}

context_transition_target :: proc(g: ^Game, index: int) -> Context_Target {
	if index < 0 || index >= len(level_document.markers) do return {}
	marker :=
		level_document.markers[index]; if marker.kind != .Transition || marker.story != level_document.active_story do return {}
	dx, dy :=
		marker.position.x -
		g.player_x,
		marker.position.y -
		g.player_y; distance := f32(math.sqrt(f64(dx * dx + dy * dy))); reachable := distance <= marker.radius && world_line_clear(g.player_x, g.player_y, marker.position.x, marker.position.y)
	label :=
		marker.destination == "city:vale_house" ? "VALE CITY" : "PASSAGE"; action := marker.destination == "city:vale_house" ? "LEAVE HOUSE" : "TRAVEL"
	return {
		valid = true,
		kind = .Transition,
		status = .Available,
		stable_id = marker.id,
		label = label,
		action = action,
		world = marker.position,
		source_index = index,
		runtime_index = -1,
		priority = 35,
		distance = distance,
		reachable = reachable,
	}
}

context_transition_at_cursor :: proc(g: ^Game) -> int {
	if g.input.mouse_pos.y >= 590 do return -1; wx, wy, ok := gameplay_mouse_ground(g, g.input.mouse_pos); if !ok do return -1
	best := f32(
		.8,
	); result := -1; for marker, i in level_document.markers {if marker.kind != .Transition || marker.story != level_document.active_story do continue; dx, dy := marker.position.x - wx, marker.position.y - wy; distance := f32(math.sqrt(f64(dx * dx + dy * dy))); if distance < best {best = distance; result = i}}
	return result
}

context_target_facing :: proc(g: ^Game, target: Context_Target) -> f32 {dx, dy :=
		target.world.x - g.player_x, target.world.y - g.player_y
	if target.distance <= .001 do return 1
	return(
		(f32(math.cos(f64(g.player_angle))) * dx + f32(math.sin(f64(g.player_angle))) * dy) /
		target.distance \
	)}
context_target_better :: proc(
	g: ^Game,
	candidate, best: Context_Target,
	facing_only: bool,
) -> bool {if !candidate.valid || !candidate.reachable do return false; if facing_only && context_target_facing(g, candidate) < .2 do return false
	if !best.valid do return true
	candidate_facing := context_target_facing(g, candidate)
	best_facing := context_target_facing(g, best)
	if facing_only && math.abs(candidate_facing - best_facing) > .12 do return candidate_facing > best_facing
	if candidate.priority != best.priority do return candidate.priority > best.priority
	return candidate.distance < best.distance}

context_target_add :: proc(g: ^Game, target: Context_Target) {
	if !target.valid || !target.reachable do return
	for &existing in g.context_ui.targets[:g.context_ui.target_count] {
		if existing.stable_id ==
		   target.stable_id {if context_target_better(g, target, existing, false) do existing = target; return}
	}
	if g.context_ui.target_count >= len(g.context_ui.targets) do return
	g.context_ui.targets[g.context_ui.target_count] = target; g.context_ui.target_count += 1
}

context_targets_sort :: proc(g: ^Game) {
	for i in 1 ..< g.context_ui.target_count {candidate := g.context_ui.targets[i]; j := i; for j > 0 && context_target_better(g, candidate, g.context_ui.targets[j - 1], false) {g.context_ui.targets[j] = g.context_ui.targets[j - 1]; j -= 1}; g.context_ui.targets[j] = candidate}
}

context_navigation_index :: proc(selected, count: int, up, down: bool) -> int {
	if count <= 1 do return selected
	if up do return (selected + count - 1) % count
	if down do return (selected + 1) % count
	return selected
}

context_resolve_house :: proc(g: ^Game, apply_navigation := true) {
	previous_id := g.context_ui.current.stable_id; g.context_ui.target_count = 0
	for _, i in g.interactives[:g.interactive_count] do context_target_add(g, context_runtime_target(g, i))
	for &entity, i in WORLD_ENTITIES {if entity_visible(g, &entity) do context_target_add(g, context_entity_target(g, i))}
	for _, i in level_document.markers do context_target_add(g, context_transition_target(g, i))
	context_targets_sort(g); g.context_ui.selected = 0
	for target, i in g.context_ui.targets[:g.context_ui.target_count] do if target.stable_id == previous_id {g.context_ui.selected = i; break}
	if g.active_device ==
	   .Keyboard_Mouse {pointer, pointer_found := context_pointer_target(g); if pointer_found && pointer.reachable {for target, i in g.context_ui.targets[:g.context_ui.target_count] do if target.stable_id == pointer.stable_id {g.context_ui.selected = i; break}}}
	if apply_navigation do g.context_ui.selected = context_navigation_index(g.context_ui.selected, g.context_ui.target_count, g.input.up, g.input.down)
	next :=
		Context_Target{}; if g.context_ui.target_count > 0 do next = g.context_ui.targets[g.context_ui.selected]
	if !next.valid && g.context_ui.current.valid && g.animation_time - g.context_ui.last_valid_time < .18 do next = g.context_ui.current
	if next.valid {g.context_ui.last_valid_time = g.animation_time; if !g.context_ui.current.valid || g.context_ui.current.kind != next.kind || g.context_ui.current.stable_id != next.stable_id {g.context_ui.previous = g.context_ui.current; g.context_ui.focus_started = g.animation_time; play_sound(g, .Pick_Up)}}
	g.context_ui.current = next
}

context_feedback :: proc(
	g: ^Game,
	message: string,
	status: Context_Status,
	id: string,
) {g.context_ui.feedback = message; g.context_ui.feedback_status = status
	g.context_ui.feedback_id = id
	g.context_ui.feedback_expires = g.animation_time + 2.2}
context_activate_house :: proc(g: ^Game, target: Context_Target) -> bool {
	// UI focus is cached briefly to avoid flicker. Resolve it again here so a
	// cached target cannot bypass the current range or line-of-sight check.
	resolved := target
	#partial switch resolved.kind {
	case .Runtime_Interactive:
		resolved = context_runtime_target(g, resolved.runtime_index)
	case .Story_Entity:
		resolved = context_entity_target(g, resolved.source_index)
	case .Transition:
		resolved = context_transition_target(g, resolved.source_index)
	case:
		return false
	}
	if !resolved.valid || !resolved.reachable do return false
	if resolved.kind ==
	   .Runtime_Interactive {ok := runtime_interactive_activate(g, resolved.runtime_index); if ok && g.screen == .Investigate {if g.interactives[resolved.runtime_index].behavior != .Shutter do context_feedback(g, resolved.action, .Available, resolved.stable_id)} else if !ok {context_feedback(g, g.interaction_feedback, resolved.status, resolved.stable_id)}; return ok}
	if resolved.kind ==
	   .Story_Entity {begin_world_interaction(g, resolved.source_index); return true}
	if resolved.kind ==
	   .Transition {marker := level_document.markers[resolved.source_index]; if strings.has_prefix(marker.destination, "city:") {if g.city_return_x != 0 || g.city_return_y != 0 {g.city_x = g.city_return_x; g.city_y = g.city_return_y; g.city_angle = g.city_return_angle} else if !city_place_at_landmark(g, marker.destination[len("city:"):]) do return false; g.city_camera_initialized = false; g.screen = .Exterior; return true}}
	return false
}
context_pointer_target :: proc(g: ^Game) -> (Context_Target, bool) {
	best: Context_Target
	if g.hover_interactive >=
	   0 {candidate := context_runtime_target(g, g.hover_interactive); if context_target_better(g, candidate, best, false) do best = candidate}
	if g.hover_entity >=
	   0 {candidate := context_entity_target(g, g.hover_entity); if context_target_better(g, candidate, best, false) do best = candidate}
	transition := context_transition_at_cursor(
		g,
	); if transition >= 0 {candidate := context_transition_target(g, transition); if context_target_better(g, candidate, best, false) do best = candidate}
	return best, best.valid
}
doorway_object_obstructs :: proc(opening: Plan_Opening) -> bool {
	middle := Vec2 {
		(opening.a.x + opening.b.x) * .5,
		(opening.a.y + opening.b.y) * .5,
	}; door_base := house_player_ground_height(middle); door_top := door_base + max(opening.height, f32(2.1))
	for item in house_plan.furniture {if point_segment_distance_sq(item.x, item.y, opening.a, opening.b) < (item.radius + .28) * (item.radius + .28) && vertical_ranges_overlap(door_base, door_top, item.elevation, item.elevation + item.height) do return true}
	for object in level_document.objects {
		if object.story != level_document.active_story || !catalog_object_blocks_movement(object) do continue
		radius, base, top := catalog_object_collision_bounds(object)
		if point_segment_distance_sq(object.position.x, object.position.y, opening.a, opening.b) < (radius + .28) * (radius + .28) && vertical_ranges_overlap(door_base, door_top, base, top) do return true
	}
	return false
}

runtime_doorway_obstructed :: proc(g: ^Game, index: int) -> bool {
	item := &g.interactives[index]; position, found := runtime_interactive_position(g, index); if found {dx, dy := position.x - g.player_x, position.y - g.player_y; if dx * dx + dy * dy < 1.05 * 1.05 do return true}
	for opening in house_plan.openings do if opening.id == item.id do return doorway_object_obstructs(opening)
	return false
}

runtime_interactive_activate :: proc(g: ^Game, index: int, automatic := false) -> bool {if index < 0 || index >= g.interactive_count do return false
	item := &g.interactives[index]
	if item.locked {g.interaction_feedback = "The door is locked."; play_sound(g, .Reject); return(
			false \
		)}
	if !item.powered {g.interaction_feedback = "There is no power."; play_sound(g, .Reject)
		return false}
	switch
	item.behavior {case .Door:
		if automatic ||
		   item.target <
			   .5 {item.target = 1; item.active = true; play_sound(g, .Door_Open)} else {if runtime_doorway_obstructed(g, index) {g.interaction_feedback = "The doorway is obstructed."; play_sound(g, .Reject); return false}; item.target = 0; item.active = false; play_sound(g, .Door_Close)}; case .Toggle:
		item.active = !item.active; item.target = item.active ? 1 : 0
		play_sound(g, .Switch); case .Shutter:
		toggle_shutter_crank(g); g.interaction_feedback = g.shutter_feedback
		context_feedback(
			g,
			g.shutter_target >= .5 ? "SHUTTER OPENING" : "SHUTTER CLOSING",
			.Available,
			"shutter_crank",
		); case .None:
		return false}
	return true}
runtime_interactives_update :: proc(g: ^Game) {if g.interactive_count == 0 do runtime_interactives_rebuild(g)
	for 	&item in g.interactives[:g.interactive_count] {item.openness = approach_scalar(
			item.openness,
			item.target,
			.055,
		)
		item.light_level = approach_scalar(item.light_level, item.active ? 1 : 0, .08)}}
runtime_interactive_at_cursor :: proc(g: ^Game) -> int {if g.input.mouse_pos.y >= 590 do return -1
	wx, wy, ok := gameplay_mouse_ground(g, g.input.mouse_pos)
	if !ok do return -1
	best := f32(1.0)
	result := -1
	for _, i in g.interactives[:g.interactive_count] {position, found := runtime_interactive_position(g, i)
		if !found do continue
		dx, dy := position.x - wx, position.y - wy
		distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
		if distance < best {best = distance; result = i}}
	return result}
runtime_near_interactive :: proc(g: ^Game) -> int {best := f32(1e9); result := -1; for 	item, i in g.interactives[:g.interactive_count] {position, found := runtime_interactive_position(g, i)
		if !found do continue
		range := f32(1.8)
		for opening in level_document.openings do if opening.id == item.id do range = opening.interaction_range
		for object in level_document.objects do if object.id == item.id do range = object.interaction_range
		dx, dy := position.x - g.player_x, position.y - g.player_y
		distance_sq := dx * dx + dy * dy
		if distance_sq <= range * range &&
		   distance_sq < best &&
		   world_interaction_line_clear(
			   g,
			   g.player_x,
			   g.player_y,
			   position.x,
			   position.y,
			   item.id,
		   ) {best = distance_sq; result = i}}
	return result}
world_wall :: proc(x, y: f32) -> bool {
	max_x, max_y :=
		f32(level_document.width) -
		.18,
		f32(level_document.height) -
		.18; if x < .18 || x > max_x || y < .18 || y > max_y do return true
	for opening in house_plan.openings do if opening.kind == .Door && house_opening_contains(opening, x, y) {return false}
	for spline in house_plan.wall_splines {radius := house_wall_width(spline.width) * .5; for i in 0 ..< len(spline.points) - 1 do if point_segment_distance_sq(x, y, spline.points[i], spline.points[i + 1]) < radius * radius do return true}
	return false
}

world_closed_door_blocked :: proc(g: ^Game, x, y: f32) -> bool {for 	opening in house_plan.openings {if opening.kind != .Door || runtime_door_opening(g, opening) >= .75 do continue
		if house_opening_contains(opening, x, y) do return true}
	return false}
world_closed_door_blocked_except :: proc(g: ^Game, x, y: f32, except_id: string) -> bool {for 	opening in house_plan.openings {if opening.id == except_id || opening.kind != .Door || runtime_door_opening(g, opening) >= .75 do continue
		if house_opening_contains(opening, x, y) do return true}
	return false}

house_player_blocked :: proc(g: ^Game, x, y: f32) -> bool {
	// Manual movement needs the same body clearance as the navmesh. Testing only
	// the character origin lets the visible mesh enter a wall when backing up.
	clearance := [5]Vec2{{0, 0}, {.24, 0}, {-.24, 0}, {0, .24}, {0, -.24}}
	for offset in clearance {px, py := x + offset.x, y + offset.y
		if world_wall(px, py) || world_closed_door_blocked(g, px, py) || furniture_blocked(px, py) || water_blocked(px, py) do return true}
	// A capsule may climb a curb or low platform, but a taller discontinuity is
	// a ledge. Compare against the support beneath the current body rather than
	// the render offset, which can still be catching up during a step animation.
	current_height := house_player_ground_height({g.player_x, g.player_y})
	if !house_step_height_allowed(current_height, house_player_ground_height({x, y})) do return true
	return false
}

house_step_height_allowed :: proc(current, target: f32) -> bool {return(
		target - current <=
		HOUSE_PLAYER_MAX_STEP_HEIGHT \
	)}

house_player_ground_height :: proc(position: Vec2) -> f32 {
	story := level_document.active_story
	for room in level_document.rooms do if room.story == story && level_point_in_polygon(position, room.points[:]) do return room.platform_height
	if level_terrain_supports_position(&level_document, position, story) do return level_terrain_height(&level_document, position)
	return 0
}

house_update_player_elevation :: proc(g: ^Game) {
	target := house_player_ground_height({g.player_x, g.player_y})
	delta := target - g.player_elevation
	if math.abs(delta) <= HOUSE_PLAYER_STEP_SPEED {g.player_elevation = target; return}
	g.player_elevation += delta > 0 ? HOUSE_PLAYER_STEP_SPEED : -HOUSE_PLAYER_STEP_SPEED
}
world_line_clear :: proc(x0, y0, x1, y1: f32) -> bool {dx := x1 - x0; dy := y1 - y0; distance :=
		math.sqrt(dx * dx + dy * dy)
	if distance <= 0.05 do return true
	steps := int(math.ceil(distance / 0.05))
	for 	step in 1 ..< steps {t := f32(step) / f32(steps); if world_wall(x0 + dx * t, y0 + dy * t) do return false}
	return true}
world_interaction_line_clear :: proc(
	g: ^Game,
	x0, y0, x1, y1: f32,
	except_id: string,
) -> bool {dx := x1 - x0; dy := y1 - y0; distance := math.sqrt(dx * dx + dy * dy); if distance <= .05 do return true
	steps := int(math.ceil(distance / .05))
	for 	step in 1 ..< steps {t := f32(step) / f32(steps); x, y := x0 + dx * t, y0 + dy * t; if world_wall(x, y) || world_closed_door_blocked_except(g, x, y, except_id) do return false}
	return true}

runtime_door_on_active_path :: proc(g: ^Game) -> int {
	if !g.move_target_active || g.nav_path_index < 0 || g.nav_path_index >= g.nav_path_count do return -1
	segment_start := Vec2{g.player_x, g.player_y}
	for path_index in g.nav_path_index ..< g.nav_path_count {
		segment_end := g.nav_path[path_index]
		for item, i in g.interactives[:g.interactive_count] {
			if item.behavior != .Door || item.locked || item.target >= .5 || i == g.pending_interactive do continue
			for opening in house_plan.openings {
				if opening.id != item.id do continue
				center := Vec2 {
					(opening.a.x + opening.b.x) * .5,
					(opening.a.y + opening.b.y) * .5,
				}; door_dx, door_dy := opening.b.x - opening.a.x, opening.b.y - opening.a.y; path_dx, path_dy := segment_end.x - segment_start.x, segment_end.y - segment_start.y
				// The route must cross the doorway's host line and pass through the
				// authored aperture, not merely pass near its center.
				side_a :=
					door_dx * (segment_start.y - opening.a.y) -
					door_dy *
						(segment_start.x -
								opening.a.x); side_b := door_dx * (segment_end.y - opening.a.y) - door_dy * (segment_end.x - opening.a.x)
				if side_a * side_b > 0 do continue
				path_length_sq :=
					path_dx * path_dx +
					path_dy *
						path_dy; if path_length_sq <= .0001 do continue; t := clamp(((center.x - segment_start.x) * path_dx + (center.y - segment_start.y) * path_dy) / path_length_sq, 0, 1); closest := Vec2{segment_start.x + path_dx * t, segment_start.y + path_dy * t}; cx, cy := closest.x - center.x, closest.y - center.y; aperture_dx, aperture_dy := opening.b.x - opening.a.x, opening.b.y - opening.a.y; aperture_length := f32(math.sqrt(f64(aperture_dx * aperture_dx + aperture_dy * aperture_dy)))
				if cx * cx + cy * cy <= (aperture_length * .5 + .3) * (aperture_length * .5 + .3) do return i
			}
		}
		segment_start = segment_end
	}
	return -1
}

world_interaction_reachable :: proc(g: ^Game, index: int) -> bool {
	if index < 0 || index >= len(WORLD_ENTITIES) do return false
	entity :=
		WORLD_ENTITIES[index]; position := Vec2{entity.x, entity.y}; if world_entity_has_tag(&entity, "shutter_mechanism") {anchor, found := shutter_crank_world_position(); if found do position = anchor}; dx, dy := position.x - g.player_x, position.y - g.player_y
	return(
		dx * dx + dy * dy <= 1.8 * 1.8 &&
		world_interaction_line_clear(
			g,
			g.player_x,
			g.player_y,
			position.x,
			position.y,
			entity.source_id,
		) \
	)
}

aerial_camera_pose :: proc(g: ^Game, focus_x, focus_y, story_y: f32) -> (eye, target, up: Vec3) {
	up = {0, 1, 0}; target = {focus_x, story_y, focus_y}
	if g.camera_pose_override {
		dx, dz :=
			g.camera_target_override.x -
			g.camera_eye_override.x,
			g.camera_target_override.z -
			g.camera_eye_override.z
		if dx * dx + dz * dz < .0001 do up = {0, 0, -1}
		return g.camera_eye_override, g.camera_target_override, up
	}
	zoom := g.camera_orbit_initialized ? g.camera_zoom : f32(1)
	if g.top_down_camera {return {focus_x, story_y + 27.5 * zoom, focus_y}, target, {0, 0, -1}}
	side :=
		g.camera_reverse ? f32(-1) : f32(1); orbit := g.camera_orbit_initialized ? g.camera_orbit : f32(math.PI / 4); distance, height := gameplay_camera_boom(g)
	return {
			focus_x + f32(math.cos(f64(orbit))) * distance * side,
			story_y + height,
			focus_y + f32(math.sin(f64(orbit))) * distance * side,
		},
		target,
		up
}

camera_story_y :: proc(g: ^Game) -> f32 {
	if g.editor_mode == .Build && level_document.active_story >= 0 && level_document.active_story < len(level_document.stories) do return level_document.stories[level_document.active_story].base_elevation
	return 0
}

camera_world_point_screen :: proc(eye, target, up, point: Vec3) -> (screen: Vec2, visible: bool) {
	forward := vk_world_normalize(
		Vec3{target.x - eye.x, target.y - eye.y, target.z - eye.z},
	); right := vk_world_normalize(Vec3{forward.y * up.z - forward.z * up.y, forward.z * up.x - forward.x * up.z, forward.x * up.y - forward.y * up.x}); camera_up := Vec3{right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x}; to := Vec3{point.x - eye.x, point.y - eye.y, point.z - eye.z}; depth := to.x * forward.x + to.y * forward.y + to.z * forward.z; if depth <= .01 do return {}, false
	half := f32(
		math.tan(f64(math.PI / 6)),
	); aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT); ndc_x := (to.x * right.x + to.y * right.y + to.z * right.z) / (depth * half * aspect); ndc_y := (to.x * camera_up.x + to.y * camera_up.y + to.z * camera_up.z) / (depth * half)
	return {(ndc_x + 1) * .5 * f32(WINDOW_WIDTH), (1 - ndc_y) * .5 * f32(WINDOW_HEIGHT)},
		ndc_x >= -1 && ndc_x <= 1 && ndc_y >= -1 && ndc_y <= 1
}

aerial_world_point_screen :: proc(g: ^Game, point: Vec2) -> (screen: Vec2, visible: bool) {
	story_y := camera_story_y(
		g,
	); eye, target, up := aerial_camera_pose(g, g.camera_x, g.camera_y, story_y)
	return camera_world_point_screen(eye, target, up, {point.x, story_y, point.y})
}

gameplay_mouse_ground :: proc(g: ^Game, mouse: Vec2) -> (x, y: f32, ok: bool) {
	story_y := camera_story_y(
		g,
	); eye, target, up := aerial_camera_pose(g, g.camera_x, g.camera_y, story_y)
	forward := vk_world_normalize(
		Vec3{target.x - eye.x, target.y - eye.y, target.z - eye.z},
	); right := vk_world_normalize(Vec3{forward.y * up.z - forward.z * up.y, forward.z * up.x - forward.x * up.z, forward.x * up.y - forward.y * up.x}); camera_up := Vec3{right.y * forward.z - right.z * forward.y, right.z * forward.x - right.x * forward.z, right.x * forward.y - right.y * forward.x}
	nx :=
		mouse.x / f32(WINDOW_WIDTH) * 2 -
		1; ny := 1 - mouse.y / f32(WINDOW_HEIGHT) * 2; half := f32(math.tan(f64(math.PI / 6))); aspect := f32(WINDOW_WIDTH) / f32(WINDOW_HEIGHT); direction := vk_world_normalize(Vec3{forward.x + right.x * nx * half * aspect + camera_up.x * ny * half, forward.y + right.y * nx * half * aspect + camera_up.y * ny * half, forward.z + right.z * nx * half * aspect + camera_up.z * ny * half})
	if direction.y >= -.001 do return 0, 0, false
	t :=
		(story_y - eye.y) /
		direction.y; return eye.x + direction.x * t, eye.z + direction.z * t, true
}

context_world_position_screen :: proc(g: ^Game, point: Vec3) -> (screen: Vec2, visible: bool) {
	eye, target, up := Vec3{}, Vec3{}, Vec3{0, 1, 0}
	if g.screen == .Exterior &&
	   g.driving_vehicle >=
		   0 {eye = {g.city_x, 1.15, g.city_y}; target = {g.city_x + f32(math.cos(f64(g.city_angle))), 1.15, g.city_y + f32(math.sin(f64(g.city_angle)))}} else if g.screen == .Investigate && g.first_person_camera {pitch_scale := f32(math.cos(f64(g.first_person_pitch))); eye = {g.player_x, 1.15, g.player_y}; target = {g.player_x + f32(math.cos(f64(g.player_angle))) * pitch_scale, 1.15 + f32(math.sin(f64(g.first_person_pitch))), g.player_y + f32(math.sin(f64(g.player_angle))) * pitch_scale}} else {focus_x, focus_y := g.screen == .Exterior ? g.city_camera_x : g.camera_x, g.screen == .Exterior ? g.city_camera_y : g.camera_y; eye, target, up = aerial_camera_pose(g, focus_x, focus_y, 0)}
	return camera_world_point_screen(eye, target, up, point)
}

context_world_point_screen :: proc(g: ^Game, point: Vec2) -> (screen: Vec2, visible: bool) {
	return context_world_position_screen(g, {point.x, 0, point.y})
}

world_entity_at_cursor :: proc(g: ^Game) -> int {
	if g.input.mouse_pos.y >= 590 do return -1
	wx, wy, valid := gameplay_mouse_ground(g, g.input.mouse_pos); if !valid do return -1
	best: f32 = 1.15; result := -1
	for &entity, i in WORLD_ENTITIES {if !entity_visible(g, &entity) do continue
		ex, ey := wx - entity.x, wy - entity.y
		distance := math.sqrt(ex * ex + ey * ey)
		if distance < best {best = distance; result = i}}
	return result
}

approach_scalar :: proc(value, target, amount: f32) -> f32 {if value < target do return min(value + amount, target)
	return max(value - amount, target)}
turn_toward :: proc(current, target, amount: f32) -> f32 {delta := target - current; for delta > math.PI do delta -= 2 * math.PI
	for delta < -math.PI do delta += 2 * math.PI
	return current + clamp(delta, -amount, amount)}
update_aerial_camera :: proc(g: ^Game) {
	if !g.camera_initialized {g.camera_x = g.player_x; g.camera_y = g.player_y; g.camera_initialized = true}
	if !g.camera_orbit_initialized {g.camera_orbit = math.PI / 4; g.camera_zoom = 1; g.camera_orbit_initialized = true}
	if !g.first_person_camera {g.camera_orbit += g.pad_right_x * .035; if g.camera_orbit > math.PI do g.camera_orbit -= 2 * math.PI; if g.camera_orbit < -math.PI do g.camera_orbit += 2 * math.PI; minimum_zoom := g.editor_mode == .Build ? EDITOR_CAMERA_MIN_ZOOM : f32(.55); g.camera_zoom = clamp(g.camera_zoom + g.pad_right_y * .025 - g.input.mouse_wheel * .1, minimum_zoom, 1.65)}
	// A small velocity lead keeps the protagonist in the playable lower-middle
	// frame without the harsh, perfectly locked camera of the earlier version.
	desired_x :=
		g.player_x + g.player_velocity_x * 2.8; desired_y := g.player_y + g.player_velocity_y * 2.8
	g.camera_x += (desired_x - g.camera_x) * .105; g.camera_y += (desired_y - g.camera_y) * .105
}

// A locked, character-centered spring arm. Pulling back raises the camera into a
// tactical view; pushing in lowers it toward a closer third-person composition.
// Build mode keeps its original uniform scale and cursor-anchored zoom behavior.
gameplay_camera_boom :: proc(g: ^Game) -> (distance, height: f32) {
	zoom := g.camera_orbit_initialized ? g.camera_zoom : f32(1)
	if g.editor_mode == .Build {return 11.314 * zoom, 10 * zoom}
	t := clamp((zoom - .55) / 1.10, 0, 1)
	return 6.2 + (18.7 - 6.2) * t, 4 + (16.5 - 4) * t
}

begin_world_interaction :: proc(g: ^Game, index: int) {
	if index < 0 || index >= len(WORLD_ENTITIES) do return; entity := WORLD_ENTITIES[index]
	tutorial_complete(
		g,
		.Contextual_Interaction,
	); if entity.kind == "person" do tutorial_complete(g, .Converse)
	if g.story_project !=
	   nil {if story_index := story_entity_index(g.story_project, entity.source_id); story_index >= 0 {authored := g.story_project.entities[story_index]; if authored.availability_condition_id != "" && g.story_runtime != nil && !story_runtime_condition_eval(g.story_runtime, authored.availability_condition_id).value {g.interaction_feedback = authored.unavailable_prompt; context_feedback(g, authored.unavailable_prompt, .Locked, entity.source_id); return}; scene_completed := world_entity_has_tag(&entity, "evidence_dialogue_after_scene") && g.desk_key_found; if authored.interaction_scene_id != "" && !scene_completed {g.dialogue_entity = index; _ = dialogue_start_scene(g, story_scene_index(g.story_project, authored.interaction_scene_id)); return}}}
	if world_entity_has_tag(&entity, "evidence_dialogue_after_scene") && g.desk_key_found {
		_ = open_evidence_dialogue(g, index)
	} else if world_entity_has_tag(&entity, "shutter_mechanism") {
		toggle_shutter_crank(
			g,
		); g.interaction_feedback = g.shutter_feedback; context_feedback(g, g.shutter_target >= .5 ? "SHUTTER OPENING" : "SHUTTER CLOSING", .Available, "shutter_crank")
	} else if world_entity_has_tag(&entity, "liftable_rug") {
		lift_study_rug(g)
	} else if entity.kind != "person" {
		_ = open_evidence_dialogue(g, index)
	} else {
		g.dialogue_entity = index
		if entity.kind == "person" && dialogue_start_character_introduction(g, entity.source_id) do return
		g.dialogue_node = 0; g.dialogue_ledger_scroll = 0; g.dialogue_choice_page = 0; g.dialogue_response = ""; if entity.kind == "person" do conversation_transcript_append(g, entity.source_id, character_reentry_line(g, entity.source_id), "dialogue", entity.source_id); g.dialogue_text_started = g.animation_time; g.pending_dialogue_approach = 0
		if entity.kind == "person" do trigger_character_interact(g, entity.source_id)
		g.screen = .Dialogue; dialogue_focus_default(g)
	}
}

appointment_fragment_recover :: proc(g: ^Game, source_id: string) {
	if game_entity_has_tag(g, source_id, "appointment_memo_fragment") {
		if g.memo_stub_found {context_feedback(g, "MEMO STUB ALREADY RECOVERED", .Complete, source_id); return}
		g.memo_stub_found =
			true; clue := clue_for_source(g, source_id); if clue >= 0 do spend(g, clue)
		g.interaction_feedback = "The stub in Edgar's memo pad reads: 'Miriam—study, 8:20—'. Its irregular lower edge was torn away."; context_feedback(g, "EDGAR'S 8:20 MEMO STUB RECOVERED", .Complete, source_id)
	} else if game_entity_has_tag(g, source_id, "appointment_burned_fragment") {
		if g.burned_note_found {context_feedback(g, "BURNED FRAGMENT ALREADY RECOVERED", .Complete, source_id); return}
		g.burned_note_found =
			true; g.interaction_feedback = "One fragment survived in Miriam's metal wastebin: '—bring the account books. We settle this tonight. —E.'"; context_feedback(g, "BURNED NOTE FRAGMENT RECOVERED", .Complete, source_id)
	} else do return
	if g.memo_stub_found && g.burned_note_found && !g.appointment_note_joined {
		g.appointment_note_joined =
			true; joined_source := game_entity_id_with_tag(g, "appointment_burned_fragment"); clue := clue_for_source(g, joined_source); if clue >= 0 do spend(g, clue)
		g.interaction_feedback = "Both note fragments are recovered: Edgar's memo stub and the burned fragment from Miriam's wastebin. Compare their torn edges on the evidence board."; log_line(g, g.interaction_feedback); context_feedback(g, "NOTE FRAGMENTS READY TO COMPARE", .Complete, source_id); play_sound(g, .Decisive_Clue)
	}
}

acquire_desk_key :: proc(g: ^Game) {
	if g.desk_key_found do return
	g.desk_key_found =
		true; g.dialogue_response = "A small brass key rests in Edgar's waistcoat pocket, worn bright at the teeth."; g.dialogue_text_started = g.animation_time; log_line(g, g.dialogue_response); context_feedback(g, "BRASS KEY ACQUIRED", .Complete, "body"); play_sound(g, .Pick_Up)
}

house_room_at_point :: proc(point: Vec2) -> int {
	story := max(
		level_document.active_story,
		0,
	); for room, i in level_document.rooms do if room.story == story && !room.exterior && level_point_in_polygon(point, room.points[:]) do return i
	return -1
}

house_outdoor_exposure_at_point :: proc(point: Vec2) -> f32 {
	story := max(level_document.active_story, 0)
	for room in level_document.rooms {
		if room.story == story && level_point_in_polygon(point, room.points[:]) do return room.exterior ? f32(1) : f32(0)
	}
	// Positions outside an authored room footprint are open terrain.
	return 1
}

house_wall_camera_position :: proc(g: ^Game) -> Vec2 {
	if g.first_person_camera do return {g.player_x, g.player_y}
	if g.camera_pose_override do return {g.camera_eye_override.x, g.camera_eye_override.z}
	camera_side :=
		g.camera_reverse ? f32(-1) : f32(1); orbit := g.camera_orbit_initialized ? g.camera_orbit : f32(math.PI / 4)
	distance, _ := gameplay_camera_boom(g)
	return {
		g.camera_x + f32(math.cos(f64(orbit))) * distance * camera_side,
		g.camera_y + f32(math.sin(f64(orbit))) * distance * camera_side,
	}
}

house_wall_sightline_crosses_window :: proc(wall: ^Floorplan_Wall, from, to: Vec2) -> bool {
	wdx, wdz := wall.b.x - wall.a.x, wall.b.y - wall.a.y; sdx, sdz := to.x - from.x, to.y - from.y
	denominator := sdx * wdz - sdz * wdx; if math.abs(denominator) < .0001 do return false
	t := ((wall.a.x - from.x) * wdz - (wall.a.y - from.y) * wdx) / denominator
	u := ((wall.a.x - from.x) * sdz - (wall.a.y - from.y) * sdx) / denominator
	if t < 0 || t > 1 || u < 0 || u > 1 do return false
	crossing := Vec2{from.x + sdx * t, from.y + sdz * t}
	for opening in house_plan.openings {
		if opening.kind != .Window do continue
		odx, odz :=
			opening.b.x -
			opening.a.x,
			opening.b.y -
			opening.a.y; opening_length_sq := odx * odx + odz * odz
		if opening_length_sq < .0001 do continue
		parallel := math.abs(
			odx * wdz - odz * wdx,
		); if parallel > .01 * f32(math.sqrt(f64(opening_length_sq * (wdx * wdx + wdz * wdz)))) do continue
		if point_segment_distance_sq((opening.a.x + opening.b.x) * .5, (opening.a.y + opening.b.y) * .5, wall.a, wall.b) > .08 * .08 do continue
		if point_segment_distance_sq(crossing.x, crossing.y, opening.a, opening.b) <= .01 * .01 do return true
	}
	return false
}

house_wall_cutaway_target :: proc(g: ^Game, wall: ^Floorplan_Wall) -> f32 {
	if g.editor_mode ==
	   .Build {if g.top_down_camera || editor_state.view == .Cutaway do return 1; return 0}
	if g.wall_view == .Walls_Up || g.first_person_camera do return 0
	if g.wall_view == .Walls_Down do return 1
	player_room := house_room_at_point({g.player_x, g.player_y}); if player_room < 0 do return 0
	dx, dz :=
		wall.b.x -
		wall.a.x,
		wall.b.y -
		wall.a.y; length := f32(math.sqrt(f64(dx * dx + dz * dz))); if length < .001 do return 0
	mx, mz :=
		(wall.a.x + wall.b.x) * .5, (wall.a.y + wall.b.y) * .5; nx, nz := -dz / length, dx / length
	positive_room := house_room_at_point(
		{mx + nx * .24, mz + nz * .24},
	); negative_room := house_room_at_point({mx - nx * .24, mz - nz * .24})
	if positive_room != player_room && negative_room != player_room do return 0
	// Use the room classification, rather than the player's instantaneous wall
	// side, as the stable interior half-plane. At door thresholds and near wall
	// ends the player can sit on the centerline (or briefly cross it while the
	// camera eases), which used to leave one leg of a foreground corner raised.
	camera := house_wall_camera_position(
		g,
	); camera_side := dx * (camera.y - wall.a.y) - dz * (camera.x - wall.a.x)
	active_side := positive_room == player_room ? f32(1) : f32(-1)
	if camera_side * active_side >= 0 do return 0
	// Glazing does not occlude the view. Keep the host wall raised when the
	// camera-to-player sightline passes through one of its window apertures.
	if house_wall_sightline_crosses_window(wall, {g.player_x, g.player_y}, camera) do return 0
	return 1
}

house_update_wall_cutaways :: proc(g: ^Game) {
	for &wall, i in house_walls {if i >= HOUSE_WALL_SECTION_CAPACITY do break
		target := house_wall_cutaway_target(g, &wall)
		g.wall_cutaways[i] = approach_scalar(g.wall_cutaways[i], target, .09)}
}
update_world :: proc(g: ^Game) {
	runtime_interactives_update(g)
	if g.input.camera_toggle do g.first_person_camera = !g.first_person_camera
	if g.input.wall_view_cycle do g.wall_view = House_Wall_View((int(g.wall_view) + 1) % len(House_Wall_View))
	previous_location := world_location_index(g)
	previous_room := house_room_at_point({g.player_x, g.player_y})
	target_environment := house_outdoor_exposure_at_point(
		{g.player_x, g.player_y},
	); g.environment_blend = approach_scalar(g.environment_blend, target_environment, .065); g.cutaway_transition = approach_scalar(g.cutaway_transition, 1 - target_environment, .065)
	turn: f32 = 0; if g.keys[.LEFT] do turn -= 1; if g.keys[.RIGHT] do turn += 1; if g.first_person_camera {turn += g.pad_right_x; g.first_person_pitch = clamp(g.first_person_pitch - g.pad_right_y * .035, -.45, .45)}; g.player_angle += turn * .045
	stick := house_radial_input(
		{g.pad_left_x, -g.pad_left_y},
	); forward, strafe := stick.y, stick.x; if g.keys[.W] || g.keys[.UP] do forward += 1; if g.keys[.S] || g.keys[.DOWN] do forward -= 1; if g.keys[.A] do strafe -= 1; if g.keys[.D] do strafe += 1
	manual :=
		math.abs(forward) + math.abs(strafe) >
		.05; if manual {g.move_target_active = false; g.pending_world_interaction = -1; g.pending_interactive = -1}
	g.hover_entity = world_entity_at_cursor(g)
	g.hover_interactive = runtime_interactive_at_cursor(
		g,
	); if g.hover_interactive >= 0 do g.hover_entity = -1
	// Populate targets for click-to-walk without consuming the D-pad edge. The
	// final resolve below applies navigation once after movement/proximity updates.
	context_resolve_house(g, false)
	if g.input.mouse_pressed &&
	   g.input.mouse_pos.y <
		   590 {wx, wy, valid := gameplay_mouse_ground(g, g.input.mouse_pos); target, pointer_target := context_pointer_target(g); if pointer_target && target.kind == .Transition && target.reachable {_ = context_activate_house(g, target); return}; if pointer_target {wx, wy = target.world.x, target.world.y; valid = true; g.pending_world_interaction = target.kind == .Story_Entity ? target.source_index : -1; g.pending_interactive = target.kind == .Runtime_Interactive ? target.runtime_index : -1} else {g.pending_world_interaction = -1; g.pending_interactive = -1}; if valid {g.move_target_x = wx; g.move_target_y = wy; g.move_target_active = nav_build_path(g, {g.player_x, g.player_y}, {wx, wy})}}
	desired_x, desired_y := f32(0), f32(0); moving := false
	if manual {length := f32(math.sqrt(f64(forward * forward + strafe * strafe))); if length > .001 {magnitude := min(length, f32(1)); forward /= length; strafe /= length; if g.first_person_camera {view_x := f32(math.cos(f64(g.player_angle))); view_y := f32(math.sin(f64(g.player_angle))); desired_x = (forward * view_x - strafe * view_y) * HOUSE_MANUAL_MOVE_SPEED * magnitude; desired_y = (forward * view_y + strafe * view_x) * HOUSE_MANUAL_MOVE_SPEED * magnitude} else {view_x := -f32(math.cos(f64(g.camera_orbit))); view_y := -f32(math.sin(f64(g.camera_orbit))); desired_x = (forward * view_x - strafe * view_y) * HOUSE_MANUAL_MOVE_SPEED * magnitude; desired_y = (forward * view_y + strafe * view_x) * HOUSE_MANUAL_MOVE_SPEED * magnitude}; moving = true}}
	if g.move_target_active {door := runtime_door_on_active_path(g); if door >= 0 {position, found := runtime_interactive_position(g, door); if found {ex, ey := position.x - g.player_x, position.y - g.player_y; if ex * ex + ey * ey < 1.15 * 1.15 {_ = runtime_interactive_activate(g, door, true); g.auto_door = door}}}}
	if g.move_target_active {waypoint := g.nav_path[g.nav_path_index]; tx, ty := waypoint.x - g.player_x, waypoint.y - g.player_y; distance := math.sqrt(tx * tx + ty * ty); stop_distance: f32 = .14; if (g.pending_world_interaction >= 0 || g.pending_interactive >= 0) && g.nav_path_index == g.nav_path_count - 1 do stop_distance = 1.25; if distance <= stop_distance {g.nav_path_index += 1; if g.nav_path_index >= g.nav_path_count {g.move_target_active = false; if g.pending_interactive >= 0 {index := g.pending_interactive; g.pending_interactive = -1; _ = runtime_interactive_activate(g, index)} else if g.pending_world_interaction >= 0 {index := g.pending_world_interaction; g.pending_world_interaction = -1; if world_interaction_reachable(g, index) do begin_world_interaction(g, index)}}} else {speed := min(HOUSE_PATH_MOVE_MAX_SPEED, max(HOUSE_PATH_MOVE_MIN_SPEED, distance * .06)); desired_x = tx / distance * speed; desired_y = ty / distance * speed; moving = true}}
	if moving &&
	   !g.first_person_camera {desired_speed := f32(math.sqrt(f64(desired_x * desired_x + desired_y * desired_y))); turn_rate := .10 + .16 * clamp(desired_speed / HOUSE_MANUAL_MOVE_SPEED, 0, 1); g.player_angle = turn_toward(g.player_angle, f32(math.atan2(f64(desired_y), f64(desired_x))), turn_rate)}
	velocity := house_approach_velocity(
		{g.player_velocity_x, g.player_velocity_y},
		{desired_x, desired_y},
		moving,
	); g.player_velocity_x, g.player_velocity_y = velocity.x, velocity.y
	// Preserve momentum but steer around a nearby furnishing instead of letting
	// click navigation repeatedly ram the same collision circle.
	dx, dy :=
		g.player_velocity_x,
		g.player_velocity_y; if g.move_target_active && house_player_blocked(g, g.player_x + dx, g.player_y + dy) {angle: f32 = .58; c, s := f32(math.cos(f64(angle))), f32(math.sin(f64(angle))); sx, sy := dx * c - dy * s, dx * s + dy * c; if house_player_blocked(g, g.player_x + sx, g.player_y + sy) {angle = -.58; c, s = f32(math.cos(f64(angle))), f32(math.sin(f64(angle))); sx, sy = dx * c - dy * s, dx * s + dy * c}; if !house_player_blocked(g, g.player_x + sx, g.player_y + sy) {dx, dy = sx, sy; g.player_velocity_x, g.player_velocity_y = dx, dy}}; if !house_player_blocked(g, g.player_x + dx, g.player_y) {g.player_x += dx} else {g.player_velocity_x = 0}; if !house_player_blocked(g, g.player_x, g.player_y + dy) {g.player_y += dy} else {g.player_velocity_y = 0}; house_update_player_elevation(g); speed := f32(math.sqrt(f64(g.player_velocity_x * g.player_velocity_x + g.player_velocity_y * g.player_velocity_y))); g.player_walk_speed = speed; g.player_is_walking = speed > .006; update_aerial_camera(g); house_update_wall_cutaways(g)
	g.near_entity = -1; best: f32 = 1.7; for &e, i in WORLD_ENTITIES {if !entity_visible(g, &e) do continue; ex := e.x - g.player_x; ey := e.y - g.player_y; d := math.sqrt(ex * ex + ey * ey); if d < best && math.cos(g.player_angle) * ex + math.sin(g.player_angle) * ey > 0 && world_interaction_line_clear(g, g.player_x, g.player_y, e.x, e.y, e.source_id) {best = d; g.near_entity = i}}
	g.near_interactive = runtime_near_interactive(
		g,
	); if g.near_interactive >= 0 do g.near_entity = -1
	for marker in level_document.markers {if marker.kind != .Interaction || marker.story != level_document.active_story do continue; dx, dy := marker.position.x - g.player_x, marker.position.y - g.player_y; if dx * dx + dy * dy > marker.radius * marker.radius || !world_line_clear(g.player_x, g.player_y, marker.position.x, marker.position.y) do continue; for &entity, i in WORLD_ENTITIES do if entity.source_id == marker.reference && world_interaction_reachable(g, i) {g.near_entity = i; break}}
	location := world_location_index(
		g,
	); if location != previous_location {if location >= 0 do _ = reveal_location_pois(g, location); g.context_ui.location_index = location; g.context_ui.location_changed_at = g.animation_time}; _ = reveal_service_closet(g)
	if previous_room < 0 &&
	   house_room_at_point({g.player_x, g.player_y}) >= 0 &&
	   !dialogue_scene_completed(g, "scene_arrival") {
		arrival_scene := story_scene_index(g.story_project, "scene_arrival")
		if arrival_scene >= 0 && dialogue_start_scene(g, arrival_scene) do return
	}
	if g.case_sense_level != 0 && g.animation_time >= g.case_sense_hint_until do g.case_sense_level = 0
	case_sense_clicked := button(g, {20, 88, 410, 26})
	if case_sense_clicked {
		if g.case_sense_level ==
		   0 {g.case_sense_level = 1; g.case_sense_hint_until = g.animation_time + 5} else do g.case_sense_level = 0; tutorial_complete(g, .Case_Sense)
	}
	if g.input.case_sense {
		if g.case_sense_level ==
		   0 {g.case_sense_level = 1; g.case_sense_hint_until = g.animation_time + 5} else do g.case_sense_level = 0; tutorial_complete(g, .Case_Sense)
	}
	context_resolve_house(g)
	if g.context_ui.feedback != "" &&
	   g.animation_time >=
		   g.context_ui.feedback_expires {g.context_ui.feedback = ""; g.interaction_feedback = ""}
	if g.input.activate do _ = context_activate_house(g, g.context_ui.current)
}
