package main

import "core:fmt"
import "core:math"
import "core:strings"

Story_Space_Target :: struct {
	id, container_id:                                              string,
	kind:                                                          Story_Spatial_Target_Kind,
	position:                                                      Vec2,
	present, visible, reachable, interaction_enabled, access_open: bool,
}
Story_Space_Transition :: struct {
	id, destination_space, destination_target: string,
	position:                                  Vec2,
	cost:                                      f32,
	enabled:                                   bool,
}
Story_Space_Snapshot :: struct {
	id:          string,
	loaded:      bool,
	targets:     [dynamic]Story_Space_Target,
	transitions: [dynamic]Story_Space_Transition,
}
Story_Spatial_Registry :: struct {
	spaces:             [dynamic]Story_Space_Snapshot,
	staged:             [dynamic]Story_Space_Snapshot,
	transaction_active: bool,
}
Story_City_Destination_Binding :: struct {
	id, display_name, city_site, level_space, level_spawn: string,
}

story_space_destroy :: proc(space: ^Story_Space_Snapshot) {delete(space.targets); delete(
		space.transitions,
	)
	space^ = {}}
story_space_clone :: proc(
	source: ^Story_Space_Snapshot,
) -> Story_Space_Snapshot {result := source^; result.targets = make(
		[dynamic]Story_Space_Target,
		len(source.targets),
	)
	copy(result.targets[:], source.targets[:])
	result.transitions = make([dynamic]Story_Space_Transition, len(source.transitions))
	copy(result.transitions[:], source.transitions[:])
	return result}
story_spatial_registry_destroy :: proc(registry: ^Story_Spatial_Registry) {for &space in registry.spaces do story_space_destroy(&space)
	for &space in registry.staged do story_space_destroy(&space)
	delete(registry.spaces)
	delete(registry.staged)
	registry^ = {}}
story_spatial_registry_space :: proc(spaces: []Story_Space_Snapshot, id: string) -> int {for space, i in spaces do if space.id == id do return i
	return -1}
story_space_target :: proc(space: ^Story_Space_Snapshot, id: string) -> int {for target, i in space.targets do if target.id == id do return i
	return -1}
story_space_target_at :: proc(space: ^Story_Space_Snapshot, position: Vec2) -> int {best := -1
	distance := f32(-1)
	for target, i in space.targets {
		candidate := story_target_distance(target.position, position)
		if best < 0 || candidate < distance {best = i; distance = candidate}
	}
	return best}

story_spatial_target_kind_compatible :: proc(expected, actual: Story_Spatial_Target_Kind) -> bool {
	if expected == actual do return true
	// An authored interaction marker and an interaction-bearing object/opening
	// both satisfy an interaction binding, but no other target families are
	// interchangeable. This keeps pickers and validation aligned.
	return expected == .Marker && actual == .Interaction
}

story_space_transition_exists :: proc(
	space: ^Story_Space_Snapshot,
	id, destination_space, destination_target: string,
) -> bool {for transition in space.transitions do if transition.id == id && transition.destination_space == destination_space && transition.destination_target == destination_target do return true
	return false}
story_spatial_registry_register :: proc(
	registry: ^Story_Spatial_Registry,
	space: Story_Space_Snapshot,
) -> bool {
	if space.id == "" || story_spatial_registry_space(registry.spaces[:], space.id) >= 0 do return false
	append(&registry.spaces, space); added := &registry.spaces[len(registry.spaces) - 1]
	// Authored connections are traversable in both directions. Materialize the
	// reverse edge only after both qualified spaces and targets are registered.
	for other_index in 0 ..< len(registry.spaces) - 1 {
		other := &registry.spaces[other_index]
		for transition in other.transitions do if transition.destination_space == added.id {arrival := story_space_target(added, transition.destination_target); source := story_space_target_at(other, transition.position); if arrival >= 0 && source >= 0 {reverse_id := transition.destination_target; source_id := other.targets[source].id; if !story_space_transition_exists(added, reverse_id, other.id, source_id) do append(&added.transitions, Story_Space_Transition{reverse_id, other.id, source_id, added.targets[arrival].position, transition.cost, transition.enabled})}}
		for transition in added.transitions do if transition.destination_space == other.id {arrival := story_space_target(other, transition.destination_target); source := story_space_target_at(added, transition.position); if arrival >= 0 && source >= 0 {reverse_id := transition.destination_target; source_id := added.targets[source].id; if !story_space_transition_exists(other, reverse_id, added.id, source_id) do append(&other.transitions, Story_Space_Transition{reverse_id, added.id, source_id, other.targets[arrival].position, transition.cost, transition.enabled})}}
	}
	return true
}
story_spatial_registry_resolve :: proc(
	registry: ^Story_Spatial_Registry,
	id: Story_Spatial_Id,
	staged := false,
) -> (
	^Story_Space_Snapshot,
	^Story_Space_Target,
	Story_Spatial_Status,
	string,
) {spaces := registry.spaces[:]; if staged && registry.transaction_active do spaces = registry.staged[:]
	space_index := story_spatial_registry_space(spaces, id.space_id)
	if space_index < 0 do return nil, nil, .Unavailable, fmt.tprintf("space %s is not registered", id.space_id)
	space := &spaces[space_index]
	if !space.loaded do return space, nil, .Unavailable, fmt.tprintf("space %s is unloaded", id.space_id)
	target_index := story_space_target(space, id.target_id)
	if target_index < 0 do return space, nil, .Missing, fmt.tprintf("target %s:%s is missing", id.space_id, id.target_id)
	return space, &space.targets[target_index], .Available, "target resolved"}
story_spatial_marker_candidates :: proc(
	registry: ^Story_Spatial_Registry,
	space_id: string,
	kind: Story_Spatial_Target_Kind,
	out: ^[256]Story_Spatial_Id,
) -> int {space_index := story_spatial_registry_space(registry.spaces[:], space_id)
	if space_index < 0 do return 0
	count := 0
	for target in registry.spaces[space_index].targets {if target.kind != kind || count >= len(out^) do continue
		out[count] = {space_id, target.id}
		count += 1}
	return count}
story_spatial_qualified_candidates :: proc(
	registry: ^Story_Spatial_Registry,
	space_id: string,
	kind: Story_Spatial_Target_Kind,
	include_other_spaces: bool,
	out: ^[256]Story_Spatial_Id,
) -> int {
	count := 0
	for &space in registry.spaces {
		if !space.loaded || (!include_other_spaces && space.id != space_id) do continue
		for target in space.targets {
			if !story_spatial_target_kind_compatible(kind, target.kind) || count >= len(out^) do continue
			out[count] = {space.id, target.id}; count += 1
		}
	}
	return count
}
story_city_destination_bind :: proc(
	registry: ^Story_Spatial_Registry,
	binding: Story_City_Destination_Binding,
) -> bool {
	if binding.id == "" || binding.city_site == "" || binding.level_space == "" || binding.level_space == "city" || binding.level_spawn == "" do return false
	city_index := story_spatial_registry_space(
		registry.spaces[:],
		"city",
	); level_index := story_spatial_registry_space(registry.spaces[:], binding.level_space); if city_index < 0 || level_index < 0 do return false
	city := &registry.spaces[city_index]; level := &registry.spaces[level_index]; site := story_space_target(city, binding.city_site); spawn := story_space_target(level, binding.level_spawn); if site < 0 || spawn < 0 do return false
	if city.targets[site].kind != .Marker || (level.targets[spawn].kind != .Marker && level.targets[spawn].kind != .Transition) do return false
	for transition in city.transitions do if transition.id == binding.id || transition.position == city.targets[site].position do return false
	append(
		&city.transitions,
		Story_Space_Transition {
			binding.id,
			binding.level_space,
			binding.level_spawn,
			city.targets[site].position,
			1,
			true,
		},
	)
	reverse_id := fmt.tprintf(
		"%s_return",
		binding.id,
	); if !story_space_transition_exists(level, reverse_id, "city", binding.city_site) do append(&level.transitions, Story_Space_Transition{reverse_id, "city", binding.city_site, level.targets[spawn].position, 1, true})
	return true
}

story_spatial_registry_validate :: proc(registry: ^Story_Spatial_Registry) -> Story_Validation {
	result := Story_Validation{}
	for &space in registry.spaces {
		if !space.loaded do story_validation_add(&result, .Warning, space.id, "space is unloaded")
		for target, target_i in space.targets {
			for other_i in target_i + 1 ..< len(space.targets) do if space.targets[other_i].id == target.id do story_validation_add(&result, .Error, target.id, "spatial target ID is duplicated within its qualified space")
			if target.container_id != "" {
				container := story_space_target(&space, target.container_id)
				if container < 0 do story_validation_add(&result, .Error, target.id, "spatial container is missing")
				else if space.targets[container].kind != .Room && space.targets[container].kind != .Entity do story_validation_add(&result, .Error, target.id, "spatial container has an incompatible target kind")
				else if target.container_id == target.id do story_validation_add(&result, .Error, target.id, "spatial target cannot contain itself")
			}
			if target.interaction_enabled && !target.present do story_validation_add(&result, .Error, target.id, "enabled interaction target is not present")
			if target.interaction_enabled && !target.reachable do story_validation_add(&result, .Error, target.id, "enabled interaction target is unreachable")
			if target.kind == .Interaction && !target.visible do story_validation_add(&result, .Warning, target.id, "interaction target is not visible")
		}
		for transition in space.transitions {
			if transition.id == "" do story_validation_add(&result, .Error, space.id, "transition needs a stable ID")
			if transition.cost < 0 do story_validation_add(&result, .Error, transition.id, "transition travel cost cannot be negative")
			destination_space := story_spatial_registry_space(
				registry.spaces[:],
				transition.destination_space,
			); if destination_space < 0 {story_validation_add(&result, .Error, transition.id, "transition destination space is missing"); continue}
			destination := story_space_target(
				&registry.spaces[destination_space],
				transition.destination_target,
			); if destination < 0 {story_validation_add(&result, .Error, transition.id, "transition destination target is missing"); continue}
			if registry.spaces[destination_space].targets[destination].kind != .Transition && registry.spaces[destination_space].targets[destination].kind != .Marker do story_validation_add(&result, .Error, transition.id, "transition destination has an incompatible target kind")
		}
	}
	result.ok = result.error_count == 0; return result
}

story_spatial_registry_query :: proc(
	userdata: rawptr,
	query: Story_Spatial_Query,
) -> Story_Spatial_Result {
	registry := cast(^Story_Spatial_Registry)userdata; space_a, a, status, message := story_spatial_registry_resolve(registry, query.a); if status != .Available do return {status, false, 0, message}
	if query.kind == .Present do return {.Available, a.present, 0, fmt.tprintf("%s:%s presence is %t", query.a.space_id, query.a.target_id, a.present)}
	space_b, b, status_b, message_b := story_spatial_registry_resolve(
		registry,
		query.b,
	); if status_b != .Available do return {status_b, false, 0, message_b}
	same_space := space_a == space_b
	switch query.kind {
	case .Contained_By:
		return {
			.Available,
			same_space && a.container_id == b.id,
			0,
			"authored containment checked",
		}
	case .Distance:
		if !same_space do return {.Unavailable, false, 0, "distance is undefined across spaces"}
		dx := a.position.x - b.position.x
		dy := a.position.y - b.position.y
		return {
			.Available,
			false,
			f32(math.sqrt(f64(dx * dx + dy * dy))),
			"within-space distance measured",
		}
	case .Visible:
		return {
			.Available,
			a.present && b.present && a.visible && b.visible && same_space,
			0,
			"visibility state checked",
		}
	case .Reachable:
		return {
			.Available,
			a.present &&
			b.present &&
			a.reachable &&
			b.reachable &&
			(same_space || story_spatial_registry_route(registry, query.a, query.b) >= 0),
			0,
			"navigation and access state checked",
		}
	case .Travel_Time:
		cost := story_spatial_registry_route(registry, query.a, query.b)
		if cost < 0 do return {.Unavailable, false, 0, "no authored transition route connects the spaces"}
		return {.Available, false, cost, "authored route travel time measured"}
	case .Present:
	}
	return {.Missing, false, 0, "unsupported spatial query"}
}

story_target_distance :: proc(a, b: Vec2) -> f32 {dx := a.x - b.x; dy := a.y - b.y; return f32(
		math.sqrt(f64(dx * dx + dy * dy)),
	)}
story_spatial_route_visit :: proc(
	registry: ^Story_Spatial_Registry,
	space_index: int,
	position: Vec2,
	to_space: int,
	to_position: Vec2,
	visited: ^[64]bool,
) -> f32 {
	if space_index < 0 || space_index >= len(registry.spaces) || space_index >= len(visited) do return -1
	space := &registry.spaces[space_index]; if !space.loaded do return -1; if space_index == to_space do return story_target_distance(position, to_position)
	if visited[space_index] do return -1; visited[space_index] = true; defer visited[space_index] = false
	best := f32(-1)
	for transition in space.transitions {
		if !transition.enabled do continue; next_space := story_spatial_registry_space(registry.spaces[:], transition.destination_space); if next_space < 0 || next_space >= len(visited) || visited[next_space] do continue
		destination := story_space_target(
			&registry.spaces[next_space],
			transition.destination_target,
		); if destination < 0 do continue
		remainder := story_spatial_route_visit(
			registry,
			next_space,
			registry.spaces[next_space].targets[destination].position,
			to_space,
			to_position,
			visited,
		); if remainder < 0 do continue
		cost :=
			story_target_distance(position, transition.position) +
			transition.cost +
			remainder; if best < 0 || cost < best do best = cost
	}
	return best
}
story_spatial_registry_route :: proc(
	registry: ^Story_Spatial_Registry,
	from, to: Story_Spatial_Id,
) -> f32 {space_a, a, status_a, _ := story_spatial_registry_resolve(registry, from)
	space_b, b, status_b, _ := story_spatial_registry_resolve(registry, to)
	if status_a != .Available || status_b != .Available do return -1
	from_index := story_spatial_registry_space(registry.spaces[:], space_a.id)
	to_index := story_spatial_registry_space(registry.spaces[:], space_b.id)
	visited: [64]bool
	return story_spatial_route_visit(
		registry,
		from_index,
		a.position,
		to_index,
		b.position,
		&visited,
	)}

story_spatial_registry_begin :: proc(
	userdata: rawptr,
) -> bool {registry := cast(^Story_Spatial_Registry)userdata
	if registry.transaction_active do return false
	clear(&registry.staged)
	for &space in registry.spaces do append(&registry.staged, story_space_clone(&space))
	registry.transaction_active = true
	return true}
story_spatial_registry_stage :: proc(
	userdata: rawptr,
	command: Story_Spatial_Command,
) -> bool {registry := cast(^Story_Spatial_Registry)userdata
	if !registry.transaction_active do return false
	_, target, status, _ := story_spatial_registry_resolve(registry, command.target, true)
	if status != .Available do return false
	switch command.kind {case .Set_Interaction:
		target.interaction_enabled = command.enabled; case .Set_Visible:
		target.visible = command.enabled; case .Set_Access:
		target.access_open = command.enabled; target.reachable = command.enabled; case .Spawn:
		target.present = true; case .Despawn:
		target.present = false; case .Move:
		_, destination, destination_status, _ := story_spatial_registry_resolve(
			registry,
			command.destination,
			true,
		)
		if destination_status != .Available do return false
		target.position = destination.position
		target.container_id = destination.container_id}
	return true}
story_spatial_registry_rollback :: proc(
	userdata: rawptr,
) {registry := cast(^Story_Spatial_Registry)userdata; for &space in registry.staged do story_space_destroy(&space)
	clear(&registry.staged)
	registry.transaction_active = false}
story_spatial_registry_commit :: proc(
	userdata: rawptr,
) -> bool {registry := cast(^Story_Spatial_Registry)userdata
	if !registry.transaction_active do return false
	for &space in registry.spaces do story_space_destroy(&space)
	delete(registry.spaces)
	registry.spaces = registry.staged
	registry.staged = {}
	registry.transaction_active = false
	return true}
story_spatial_registry_service :: proc(
	registry: ^Story_Spatial_Registry,
) -> Story_Spatial_Service {return{
		registry,
		story_spatial_registry_query,
		story_spatial_registry_begin,
		story_spatial_registry_stage,
		story_spatial_registry_commit,
		story_spatial_registry_rollback,
	}}

story_spatial_validate_id :: proc(
	registry: ^Story_Spatial_Registry,
	id: Story_Spatial_Id,
	owner: string,
	result: ^Story_Validation,
	expected: Story_Spatial_Target_Kind = .Entity,
	check_kind := false,
) {
	if !story_spatial_id_valid(id) do return
	_, target, status, message := story_spatial_registry_resolve(
		registry,
		id,
	); if status != .Available {story_validation_add(result, .Error, owner, message); return}
	if check_kind && !story_spatial_target_kind_compatible(expected, target.kind) do story_validation_add(result, .Error, owner, fmt.tprintf("target %s has incompatible spatial kind", story_spatial_id_text(id)))
}
story_spatial_validate_project :: proc(
	project: ^Story_Project,
	registry: ^Story_Spatial_Registry,
) -> Story_Validation {result := Story_Validation{}; for entity in project.entities do story_spatial_validate_id(registry, {entity.spatial.space_id, entity.spatial.target_id}, entity.id, &result, entity.spatial.target_kind, true)
	for 	&condition in project.conditions {#partial switch
		condition.kind {case .Spatial_Present,
		                     .Spatial_Contained_By,
		                     .Spatial_Distance,
		                     .Spatial_Visible,
		                     .Spatial_Reachable,
		                     .Spatial_Travel_Time:
			story_spatial_validate_id(registry, condition.spatial_a, condition.id, &result)
			if condition.kind != .Spatial_Present do story_spatial_validate_id(registry, condition.spatial_b, condition.id, &result)}}
	for effect in project.effects do if effect.kind == .Spatial_Command {story_spatial_validate_id(registry, effect.spatial_target, effect.id, &result); if effect.spatial_command == .Move do story_spatial_validate_id(registry, effect.spatial_destination, effect.id, &result)}
	result.ok = result.error_count == 0
	return result}

story_level_space :: proc(doc: ^Level_Document) -> Story_Space_Snapshot {
	space := Story_Space_Snapshot {
		id     = doc.id,
		loaded = true,
	}
	for &room in doc.rooms {
		center :=
			Vec2{}; for point in room.points {center.x += point.x; center.y += point.y}; if len(room.points) > 0 {center.x /= f32(len(room.points)); center.y /= f32(len(room.points))}
		append(
			&space.targets,
			Story_Space_Target{room.id, "", .Room, center, true, true, true, false, true},
		)
	}
	for object in doc.objects do append(&space.targets, Story_Space_Target{object.id, object.support_id, .Entity, object.position, true, true, !object.locked, object.initially_active, !object.locked})
	// A wall path hosts opening geometry but is not a StoryCore containment
	// target. Keep that structural relationship in LevelFormat rather than
	// exposing a dangling spatial container binding.
	for opening in doc.openings do append(&space.targets, Story_Space_Target{opening.id, "", .Interaction, {}, true, true, !opening.locked, opening.initially_active, !opening.locked})
	for marker in doc.markers {
		kind :=
			Story_Spatial_Target_Kind.Marker; if marker.kind == .Interaction do kind = .Interaction
		else if marker.kind == .Transition do kind = .Transition
		append(
			&space.targets,
			Story_Space_Target{marker.id, "", kind, marker.position, true, true, true, true, true},
		)
		if marker.kind ==
		   .Transition {qualified, ok := story_spatial_id_parse(marker.destination, doc.id); if ok do append(&space.transitions, Story_Space_Transition{marker.id, qualified.space_id, qualified.target_id, marker.position, 1, true})}
	}
	return space
}

story_city_space :: proc() -> Story_Space_Snapshot {space := Story_Space_Snapshot {
			id     = "city",
			loaded = true,
		}; for landmark in CITY_FIXED_LANDMARKS do append(&space.targets, Story_Space_Target{landmark.id, "", .Marker, {landmark.arrival_x, landmark.arrival_y}, true, true, true, true, true}); for site in CITY_CASE_LOCATION_SITES do append(&space.targets, Story_Space_Target{site.id, "", .Marker, {site.arrival_x, site.arrival_y}, true, true, true, true, true}); return space}

run_story_spatial_registry_tests :: proc() {
	registry: Story_Spatial_Registry; defer story_spatial_registry_destroy(&registry)
	city := Story_Space_Snapshot {
			id     = "city",
			loaded = true,
		}; append(
		&city.targets,
		Story_Space_Target {
			id = "station",
			kind = .Marker,
			position = {0, 0},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "house_site",
			kind = .Transition,
			position = {10, 0},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "annex_site",
			kind = .Marker,
			position = {20, 0},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
	); append(&city.transitions, Story_Space_Transition{id = "to_house", destination_space = "house", destination_target = "front_door", position = {10, 0}, cost = 5, enabled = true})
	house := Story_Space_Snapshot {
			id     = "house",
			loaded = true,
		}; append(
		&house.targets,
		Story_Space_Target {
			id = "front_door",
			kind = .Transition,
			position = {0, 0},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "desk",
			container_id = "study",
			kind = .Entity,
			position = {3, 4},
			present = true,
			visible = true,
			reachable = true,
			interaction_enabled = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "study",
			kind = .Room,
			position = {3, 3},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "basement_door",
			kind = .Transition,
			position = {6, 4},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "annex_spawn",
			kind = .Marker,
			position = {9, 4},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
	); append(&house.transitions, Story_Space_Transition{id = "basement_door", destination_space = "cellar", destination_target = "stairs", position = {6, 4}, cost = 2, enabled = true})
	cellar := Story_Space_Snapshot {
			id     = "cellar",
			loaded = true,
		}; append(
		&cellar.targets,
		Story_Space_Target {
			id = "stairs",
			kind = .Transition,
			position = {0, 0},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
		Story_Space_Target {
			id = "vault",
			kind = .Entity,
			position = {0, 3},
			present = true,
			visible = true,
			reachable = true,
			access_open = true,
		},
	)
	assert(
		story_spatial_registry_register(&registry, city) &&
		story_spatial_registry_register(&registry, house) &&
		story_spatial_registry_register(&registry, cellar),
	); service := story_spatial_registry_service(&registry)
	qualified: [256]Story_Spatial_Id; qualified_count := story_spatial_qualified_candidates(&registry, "house", .Entity, false, &qualified); assert(qualified_count == 1); for candidate in qualified[:qualified_count] do assert(candidate.space_id == "house")
	qualified_count = story_spatial_qualified_candidates(
		&registry,
		"house",
		.Entity,
		true,
		&qualified,
	); assert(qualified_count == 2)
	assert(
		story_city_destination_bind(
			&registry,
			{"annex", "Annex", "annex_site", "house", "annex_spawn"},
		),
	); assert(!story_city_destination_bind(&registry, {"annex_duplicate", "Duplicate", "annex_site", "house", "annex_spawn"})); assert(story_space_transition_exists(&registry.spaces[story_spatial_registry_space(registry.spaces[:], "house")], "annex_return", "city", "annex_site"))
	registry_validation := story_spatial_registry_validate(
		&registry,
	); assert(registry_validation.ok)
	contained := story_spatial_query(
		&service,
		{.Contained_By, {"house", "desk"}, {"house", "study"}},
	); assert(contained.status == .Available && contained.boolean_value)
	travel := story_spatial_query(
		&service,
		{.Travel_Time, {"city", "station"}, {"house", "desk"}},
	); assert(travel.status == .Available && math.abs(f64(travel.number_value - 20)) < .001)
	multi_hop := story_spatial_query(
		&service,
		{.Travel_Time, {"city", "station"}, {"cellar", "vault"}},
	); reverse := story_spatial_query(&service, {.Travel_Time, {"cellar", "vault"}, {"city", "station"}}); assert(multi_hop.status == .Available && reverse.status == .Available && math.abs(f64(multi_hop.number_value - reverse.number_value)) < .001)
	missing := story_spatial_query(
		&service,
		{.Present, {"house", "missing"}, {}},
	); assert(missing.status == .Missing)
	unavailable := story_spatial_query(
		&service,
		{.Present, {"unloaded", "target"}, {}},
	); assert(unavailable.status == .Unavailable)
	assert(
		service.begin(service.userdata),
	); assert(service.stage(service.userdata, {.Set_Visible, {"house", "desk"}, {}, false})); service.rollback(service.userdata); visible := story_spatial_query(&service, {.Visible, {"house", "desk"}, {"house", "study"}}); assert(visible.boolean_value)
	assert(
		service.begin(service.userdata),
	); assert(service.stage(service.userdata, {.Set_Visible, {"house", "desk"}, {}, false})); assert(service.commit(service.userdata)); visible = story_spatial_query(&service, {.Visible, {"house", "desk"}, {"house", "study"}}); assert(!visible.boolean_value)
	project :=
		Story_Project{}; append(&project.entities, Story_Entity{id = "misbound", spatial = {"house", .Room, "desk"}}); binding_validation := story_spatial_validate_project(&project, &registry); assert(!binding_validation.ok && binding_validation.error_count > 0); delete(project.entities)
	broken := story_space_clone(
		&registry.spaces[story_spatial_registry_space(registry.spaces[:], "house")],
	); broken.id = "broken"; broken.targets[story_space_target(&broken, "desk")].reachable = false; broken_validation_registry := Story_Spatial_Registry{}; append(&broken_validation_registry.spaces, broken); broken_validation := story_spatial_registry_validate(&broken_validation_registry); assert(!broken_validation.ok); story_spatial_registry_destroy(&broken_validation_registry)
}
