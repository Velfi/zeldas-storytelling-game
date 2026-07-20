package main

import "core:fmt"
import "core:math"
import "core:strings"

level_polygon_area :: proc(points: []Vec2) -> f32 {area: f32; for 	p, i in points {q := points[(i + 1) % len(points)]; area += p.x * q.y - q.x * p.y}
	return area * .5}
level_opening_finish_extension :: proc(kind: Level_Opening_Kind) -> f32 {return(
		kind == .Window ? f32(.12) : f32(.06) \
	)}
level_opening_finish_clearance :: proc(a, b: Level_Opening_Kind) -> f32 {return(
		level_opening_finish_extension(a) +
		level_opening_finish_extension(b) \
	)}
level_opening_end_clearance :: proc(kind: Level_Opening_Kind) -> f32 {return max(
		f32(.10),
		level_opening_finish_extension(kind),
	)}
level_opening_crosses_wall_junction :: proc(
	doc: ^Level_Document,
	opening: Level_Opening,
	host: ^Level_Path,
) -> bool {
	if host == nil || opening.segment < 0 || opening.segment >= len(host.points) - 1 do return false
	a, b :=
		host.points[opening.segment],
		host.points[opening.segment + 1]; dx, dy := b.x - a.x, b.y - a.y; span_sq := dx * dx + dy * dy; span := f32(math.sqrt(f64(span_sq))); if span <= .001 do return false
	center_distance :=
		opening.position *
		span; protected_half := opening.width * .5 + level_opening_finish_extension(opening.kind) + .18
	for path in doc.paths {
		if path.kind != .Wall || path.story != host.story || path.id == host.id do continue
		for point in path.points {
			// A point from another wall lying in the middle of this host is a T
			// junction. Keep the aperture and its trim clear of that structure.
			if point_segment_distance_sq(point.x, point.y, a, b) > .02 * .02 do continue
			t := clamp(
				((point.x - a.x) * dx + (point.y - a.y) * dy) / span_sq,
				0,
				1,
			); along := t * span
			if t > .001 && t < .999 && math.abs(along - center_distance) < protected_half do return true
		}
	}
	return false
}
level_window_head_finish_height :: proc(sill, glazing: f32) -> f32 {return sill + glazing + .13}
level_clone_points :: proc(source: [dynamic]Vec2) -> [dynamic]Vec2 {result := make(
		[dynamic]Vec2,
		0,
		len(source),
	)
	for value in source do append(&result, value)
	return result}
level_clone_document :: proc(source: ^Level_Document) -> Level_Document {result := source^
	result.stories = make([dynamic]Level_Story, 0, len(source.stories))
	for v in source.stories do append(&result.stories, v)
	result.rooms = make([dynamic]Level_Room, 0, len(source.rooms))
	for v in source.rooms {copy := v; copy.points = level_clone_points(v.points); append(&result.rooms, copy)}
	result.paths = make([dynamic]Level_Path, 0, len(source.paths))
	for v in source.paths {copy := v; copy.points = level_clone_points(v.points); append(&result.paths, copy)}
	result.openings = make([dynamic]Level_Opening, 0, len(source.openings))
	for v in source.openings do append(&result.openings, v)
	result.objects = make([dynamic]Level_Object, 0, len(source.objects))
	for v in source.objects do append(&result.objects, v)
	result.lights = make([dynamic]Level_Light, 0, len(source.lights))
	for v in source.lights do append(&result.lights, v)
	result.roofs = make([dynamic]Level_Roof, 0, len(source.roofs))
	for v in source.roofs do append(&result.roofs, v)
	result.waters = make([dynamic]Level_Water, 0, len(source.waters))
	for v in source.waters {copy := v; copy.points = level_clone_points(v.points); append(&result.waters, copy)}
	result.foundations = make([dynamic]Level_Foundation, 0, len(source.foundations))
	for v in source.foundations {copy := v; copy.points = level_clone_points(v.points); append(&result.foundations, copy)}
	result.vertical_links = make([dynamic]Level_Vertical_Link, 0, len(source.vertical_links))
	for v in source.vertical_links do append(&result.vertical_links, v)
	result.markers = make([dynamic]Level_Marker, 0, len(source.markers))
	for v in source.markers do append(&result.markers, v)
	result.terrain = make([dynamic]f32, 0, len(source.terrain))
	for v in source.terrain do append(&result.terrain, v)
	result.diagnostics = make([dynamic]Level_Diagnostic, 0, len(source.diagnostics))
	for v in source.diagnostics do append(&result.diagnostics, v)
	return result}
level_validate_id :: proc(
	doc: ^Level_Document,
	ids: ^[dynamic]string,
	id: string,
	story: int,
	position: Vec2,
) -> bool {if id == "" {append(
			&doc.diagnostics,
			Level_Diagnostic{.Error, id, "Entity needs a stable ID.", story, position},
		)
		return false}
	for known in ids^ do if known == id {append(&doc.diagnostics, Level_Diagnostic{.Error, id, fmt.tprintf("Duplicate stable ID: %s", id), story, position}); return false}
	append(ids, id)
	return true}
level_validate_interaction_refs :: proc(
	doc: ^Level_Document,
	id, condition, scene: string,
	effects: [STORY_MAX_NODE_EFFECTS]string,
	effect_count, story: int,
	position: Vec2,
) {if condition != "" && story_condition_index_in_document(condition) < 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, id, fmt.tprintf("Interaction references missing condition: %s", condition), story, position})
	if scene != "" && graph_scene_index(scene) < 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, id, fmt.tprintf("Interaction references missing focused scene: %s", scene), story, position})
	for i in 0 ..< effect_count do if story_effect_index_in_document(effects[i]) < 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, id, fmt.tprintf("Interaction references missing effect: %s", effects[i]), story, position})}
level_validate :: proc(doc: ^Level_Document) -> Validation {
	clear(&doc.diagnostics); ids := make([dynamic]string, 0, 64, context.temp_allocator)
	for foundation in doc.foundations {position := len(foundation.points) > 0 ? foundation.points[0] : Vec2{}; _ = level_validate_id(doc, &ids, foundation.id, max(foundation.story, 0), position); if len(foundation.points) < 3 || !level_polygon_simple(foundation.points[:]) || math.abs(level_polygon_area(foundation.points[:])) < 1 do append(&doc.diagnostics, Level_Diagnostic{.Error, foundation.id, "Foundation footprint is invalid.", max(foundation.story, 0), position}); if foundation.kind == .Basement && (foundation.depth < 1.8 || foundation.story < 0 || foundation.story >= len(doc.stories) || doc.stories[foundation.story].base_elevation >= 0) do append(&doc.diagnostics, Level_Diagnostic{.Error, foundation.id, "Basement must reference a valid below-grade story at least 1.8 meters deep.", max(foundation.story, 0), position})}
	for room in doc.rooms {position := len(room.points) > 0 ? room.points[0] : Vec2{}; _ = level_validate_id(doc, &ids, room.id, room.story, position); if room.story < 0 || room.story >= len(doc.stories) do append(&doc.diagnostics, Level_Diagnostic{.Error, room.id, "Room references a missing story.", room.story, position}); if len(room.points) < 3 || math.abs(level_polygon_area(room.points[:])) < .25 do append(&doc.diagnostics, Level_Diagnostic{.Error, room.id, "Room polygon is degenerate.", room.story, position}); if !level_room_has_foundation(doc, room) do append(&doc.diagnostics, Level_Diagnostic{.Warning, room.id, "Ground-floor room has no supporting foundation.", room.story, position}); for p in room.points do if p.x < 0 || p.y < 0 || p.x > f32(doc.width) || p.y > f32(doc.height) do append(&doc.diagnostics, Level_Diagnostic{.Error, room.id, "Room extends outside the lot.", room.story, p})}
	for path in doc.paths {position := len(path.points) > 0 ? path.points[0] : Vec2{}; _ = level_validate_id(doc, &ids, path.id, path.story, position); if len(path.points) < 2 do append(&doc.diagnostics, Level_Diagnostic{.Error, path.id, "Path needs at least two points.", path.story, position})}
	for opening in doc.openings {
		host: ^Level_Path; for &path in doc.paths do if path.id == opening.host_path do host = &path
		story := 0; position := Vec2{}; if host != nil do story = host.story
		_ = level_validate_id(doc, &ids, opening.id, story, position)
		if host == nil || opening.segment < 0 || opening.segment >= len(host.points) - 1 {
			append(
				&doc.diagnostics,
				Level_Diagnostic {
					.Error,
					opening.id,
					"Opening references an invalid wall segment.",
					story,
					position,
				},
			)
			continue
		}
		a, b :=
			host.points[opening.segment],
			host.points[opening.segment + 1]; dx, dy := b.x - a.x, b.y - a.y; span := f32(math.sqrt(f64(dx * dx + dy * dy))); position = {a.x + dx * opening.position, a.y + dy * opening.position}
		if opening.width < .4 || opening.width > 6 do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Opening width must be between 0.4 and 6 meters.", story, position})
		if opening.height < .4 || opening.height > 4 do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Opening height must be between 0.4 and 4 meters.", story, position})
		if opening.kind ==
		   .Window {wall_height := story >= 0 && story < len(doc.stories) ? doc.stories[story].wall_height : f32(0); if opening.sill_height < .2 || opening.sill_height > 2 do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Window sill height must be between 0.2 and 2 meters.", story, position}); if wall_height > 0 && level_window_head_finish_height(opening.sill_height, opening.height) > wall_height + .001 do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Window head trim and flashing must remain below the wall top.", story, position})}
		if opening.interaction != .None && (opening.kind != .Door || opening.interaction != .Door) do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Only door openings may use door interaction behavior.", story, position})
		if opening.interaction != .None && (opening.interaction_range < .5 || opening.interaction_range > 6) do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Interaction range must be between 0.5 and 6 meters.", story, position})
		if opening.interaction != .None do level_validate_interaction_refs(doc, opening.id, opening.condition_id, opening.focused_scene, opening.effect_ids, opening.effect_id_count, story, position)
		end_clearance := level_opening_end_clearance(
			opening.kind,
		); if opening.width > span - end_clearance * 2 do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Opening and finished trim are too wide for the wall span.", story, position})
		half :=
			(opening.width * .5 + end_clearance) /
			max(
				span,
				.001,
			); if opening.position < half || opening.position > 1 - half do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Opening trim extends beyond its wall span.", story, position})
		if level_opening_crosses_wall_junction(doc, opening, host) do append(&doc.diagnostics, Level_Diagnostic{.Error, opening.id, "Opening and finished trim must stay clear of wall junctions.", story, position})
	}
	for opening, i in doc.openings {for other, j in doc.openings {if j <= i || opening.host_path != other.host_path || opening.segment != other.segment do continue; host_index := level_path_index(doc, opening.host_path); if host_index < 0 || opening.segment < 0 || opening.segment >= len(doc.paths[host_index].points) - 1 do continue; a, b := doc.paths[host_index].points[opening.segment], doc.paths[host_index].points[opening.segment + 1]; dx, dy := b.x - a.x, b.y - a.y; span := f32(math.sqrt(f64(dx * dx + dy * dy))); clearance := math.abs(opening.position - other.position) * span - (opening.width + other.width) * .5; if clearance < level_opening_finish_clearance(opening.kind, other.kind) {position := Vec2{a.x + dx * other.position, a.y + dy * other.position}; append(&doc.diagnostics, Level_Diagnostic{.Error, other.id, "Finished opening trim overlaps or lacks clear wall.", doc.paths[host_index].story, position})}}}
	for room in doc.rooms {position := len(room.points) > 0 ? room.points[0] : Vec2{}; if room.floor_material != "" && !catalog_qualified_id(room.floor_material) do append(&doc.diagnostics, Level_Diagnostic{.Error, room.id, "Floor material ID must be namespace-qualified.", room.story, position}); if room.wall_material != "" && !catalog_qualified_id(room.wall_material) do append(&doc.diagnostics, Level_Diagnostic{.Error, room.id, "Wall material ID must be namespace-qualified.", room.story, position})}
	for object in doc.objects do if object.catalog_id != "" && !catalog_qualified_id(object.catalog_id) do append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Object catalog ID must be namespace-qualified.", object.story, object.position})
	for object in doc.objects {_ = level_validate_id(doc, &ids, object.id, object.story, object.position); if object.catalog_id == "" do append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Object needs a catalog ID.", object.story, object.position}); if object.interaction == .Door do append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Objects cannot use door interaction behavior.", object.story, object.position}); if object.interaction != .None && (object.interaction_range < .5 || object.interaction_range > 6) do append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Interaction range must be between 0.5 and 6 meters.", object.story, object.position}); if object.interaction != .None do level_validate_interaction_refs(doc, object.id, object.condition_id, object.focused_scene, object.effect_ids, object.effect_id_count, object.story, object.position); if object.support_id != "" {support_index := level_object_index(doc, object.support_id); if support_index < 0 || object.support_id == object.id {append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Object references missing furniture support.", object.story, object.position})} else if doc.objects[support_index].story != object.story {append(&doc.diagnostics, Level_Diagnostic{.Error, object.id, "Object and furniture support must share a story.", object.story, object.position})}}}
	for light in doc.lights {_ = level_validate_id(doc, &ids, light.id, light.story, light.position); if light.story < 0 || light.story >= len(doc.stories) do append(&doc.diagnostics, Level_Diagnostic{.Error, light.id, "Light references a missing story.", light.story, light.position}); if light.position.x < 0 || light.position.y < 0 || light.position.x > f32(doc.width) || light.position.y > f32(doc.height) do append(&doc.diagnostics, Level_Diagnostic{.Error, light.id, "Light is outside the lot.", light.story, light.position}); if light.range <= 0 || light.intensity <= 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, light.id, "Light range and intensity must be positive.", light.story, light.position}); if light.elevation < 0 do append(&doc.diagnostics, Level_Diagnostic{.Warning, light.id, "Light is below its story floor.", light.story, light.position})}
	for roof in doc.roofs {_ = level_validate_id(doc, &ids, roof.id, roof.story, {}); if level_room_index(doc, roof.room_id) < 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, roof.id, "Roof references a missing room.", roof.story, {}}); if roof.pitch < 0 || roof.pitch > 75 do append(&doc.diagnostics, Level_Diagnostic{.Warning, roof.id, "Roof pitch is outside the recommended range.", roof.story, {}})}
	for water in doc.waters {position := len(water.points) > 0 ? water.points[0] : Vec2{}; _ = level_validate_id(doc, &ids, water.id, 0, position); if len(water.points) < 3 || !level_polygon_simple(water.points[:]) || math.abs(level_polygon_area(water.points[:])) < .5 do append(&doc.diagnostics, Level_Diagnostic{.Error, water.id, "Pond shoreline is invalid.", 0, position}); for point in water.points do if point.x < 0 || point.y < 0 || point.x > f32(doc.width) || point.y > f32(doc.height) {append(&doc.diagnostics, Level_Diagnostic{.Error, water.id, "Pond shoreline extends outside the lot.", 0, point}); break}}
	for link in doc.vertical_links {_ = level_validate_id(doc, &ids, link.id, link.from_story, link.start); if link.from_story < 0 || link.to_story < 0 || link.to_story >= len(doc.stories) || level_story_above(doc, link.from_story) != link.to_story do append(&doc.diagnostics, Level_Diagnostic{.Error, link.id, "Vertical link must connect adjacent stories by elevation.", link.from_story, link.start})}
	spawn_count := 0; for marker in doc.markers {_ = level_validate_id(doc, &ids, marker.id, marker.story, marker.position); if marker.position.x < 0 || marker.position.y < 0 || marker.position.x > f32(doc.width) || marker.position.y > f32(doc.height) do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Marker is outside the lot.", marker.story, marker.position}); if marker.story < 0 || marker.story >= len(doc.stories) do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Marker references a missing story.", marker.story, marker.position}); if marker.kind == .Player_Spawn {spawn_count += 1; if marker.radius < .3 do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Player spawn radius is unsafe.", marker.story, marker.position})}; if marker.kind == .Camera && (marker.camera_height < .5 || marker.camera_height > 20) do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Camera marker height cannot frame the scene safely.", marker.story, marker.position}); if marker.kind == .Transition && !strings.contains(marker.destination, ":") do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Transition destination must be a qualified space:target reference.", marker.story, marker.position}); if marker.interaction != .None {if marker.kind != .Interaction && marker.kind != .Staging do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Only interaction or staging markers may define behavior.", marker.story, marker.position}); if marker.interaction == .Door do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Markers cannot use door interaction behavior.", marker.story, marker.position}); if marker.interaction_range < .5 || marker.interaction_range > 6 do append(&doc.diagnostics, Level_Diagnostic{.Error, marker.id, "Interaction range must be between 0.5 and 6 meters.", marker.story, marker.position}); level_validate_interaction_refs(doc, marker.id, marker.condition_id, marker.focused_scene, marker.effect_ids, marker.effect_id_count, marker.story, marker.position)}}; if spawn_count == 0 do append(&doc.diagnostics, Level_Diagnostic{.Error, doc.id, "Level requires a player spawn.", 0, {}})
	for issue in doc.diagnostics do if issue.severity == .Error do return {false, issue.message}; return {true, "LEVEL VALID"}
}

level_reference_add :: proc(
	out: ^Level_Reference_Preview,
	kind, owner, field: string,
) {if out.count >= len(out.items) {out.truncated = true; return}; out.items[out.count] = {
		kind,
		owner,
		field,
	}
	out.count += 1}
level_reference_preview :: proc(
	doc: ^Level_Document,
	project: ^Story_Project,
	id: string,
) -> Level_Reference_Preview {result: Level_Reference_Preview; if project != nil {for entity in project.entities do if entity.spatial.space_id == doc.id && entity.spatial.target_id == id do level_reference_add(&result, "entity", entity.id, "spatial")
		for 		condition in project.conditions {if condition.spatial_a.space_id == doc.id && condition.spatial_a.target_id == id do level_reference_add(&result, "condition", condition.id, "spatial_a")
			if condition.spatial_b.space_id == doc.id && condition.spatial_b.target_id == id do level_reference_add(&result, "condition", condition.id, "spatial_b")}
		for 		effect in project.effects {if effect.spatial_target.space_id == doc.id && effect.spatial_target.target_id == id do level_reference_add(&result, "effect", effect.id, "spatial_target")
			if effect.spatial_destination.space_id == doc.id && effect.spatial_destination.target_id == id do level_reference_add(&result, "effect", effect.id, "spatial_destination")}
		if payload := mystery_payload(project); payload != nil {for item in payload.city_labels do if item.level_spawn == id do level_reference_add(&result, "city_label", item.id, "level_spawn")}}
	for object in doc.objects do if object.id != id && object.support_id == id do level_reference_add(&result, "object", object.id, "support_id")
	for opening in doc.openings do if opening.host_path == id do level_reference_add(&result, "opening", opening.id, "host_path")
	for roof in doc.roofs do if roof.room_id == id do level_reference_add(&result, "roof", roof.id, "room_id")
	for marker in doc.markers do if marker.id != id && marker.destination == fmt.tprintf("%s:%s", doc.id, id) do level_reference_add(&result, "marker", marker.id, "destination")
	for 	node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera == id do level_reference_add(&result, "graph_node", node.beat.id, "camera")
		if node.beat.actor_mark == id do level_reference_add(&result, "graph_node", node.beat.id, "actor_mark")}
	return result}
level_reference_repair :: proc(
	doc: ^Level_Document,
	project: ^Story_Project,
	missing, replacement: string,
) -> bool {if missing == "" || missing == replacement || level_selection_for_id(doc, replacement).kind == .None do return false
	if project != nil {for &entity in project.entities do if entity.spatial.space_id == doc.id && entity.spatial.target_id == missing do entity.spatial.target_id = replacement
		for 		&condition in project.conditions {if condition.spatial_a.space_id == doc.id && condition.spatial_a.target_id == missing do condition.spatial_a.target_id = replacement
			if condition.spatial_b.space_id == doc.id && condition.spatial_b.target_id == missing do condition.spatial_b.target_id = replacement}
		for 		&effect in project.effects {if effect.spatial_target.space_id == doc.id && effect.spatial_target.target_id == missing do effect.spatial_target.target_id = replacement
			if effect.spatial_destination.space_id == doc.id && effect.spatial_destination.target_id == missing do effect.spatial_destination.target_id = replacement}
		if payload := mystery_payload(project); payload != nil do for &item in payload.city_labels do if item.level_spawn == missing do item.level_spawn = replacement}
	old_qualified := fmt.tprintf("%s:%s", doc.id, missing)
	new_qualified := fmt.tprintf("%s:%s", doc.id, replacement)
	for &marker in doc.markers do if marker.destination == old_qualified do marker.destination = new_qualified
	for 	&node in graph_document.nodes[:graph_document.node_count] {if node.beat.camera == missing do node.beat.camera = replacement
		if node.beat.actor_mark == missing do node.beat.actor_mark = replacement}
	return true}
level_reference_rename :: proc(
	doc: ^Level_Document,
	project: ^Story_Project,
	old, new: string,
) -> bool {if !graph_valid_id(new) || old == new || level_selection_for_id(doc, new).kind != .None do return false
	selection := level_selection_for_id(doc, old)
	#partial switch
	selection.kind {case .Marker:
		index := level_marker_index(doc, old); if index < 0 do return false
		doc.markers[index].id = new; case .Object:
		index := level_object_index(doc, old); if index < 0 do return false
		doc.objects[index].id = new
		for &item in doc.objects do if item.support_id == old do item.support_id = new; case .Room:
		index := level_room_index(doc, old); if index < 0 do return false
		doc.rooms[index].id = new
		for &roof in doc.roofs do if roof.room_id == old do roof.room_id = new; case .Opening:
		index := level_opening_index(doc, old); if index < 0 do return false
		doc.openings[index].id = new; case .Path:
		index := level_path_index(doc, old); if index < 0 do return false
		doc.paths[index].id = new
		for &opening in doc.openings do if opening.host_path == old do opening.host_path = new; case:
		return false}
	_ = level_reference_repair(doc, project, old, new)
	return true}
level_reference_remove :: proc(
	doc: ^Level_Document,
	project: ^Story_Project,
	id: string,
) -> (
	Level_Reference_Preview,
	bool,
) {preview := level_reference_preview(doc, project, id); if preview.count > 0 || preview.truncated do return preview, false
	selection := level_selection_for_id(doc, id)
	#partial switch
	selection.kind {case .Marker:
		index := level_marker_index(doc, id); if index < 0 {return preview, false}
		ordered_remove(&doc.markers, index); case .Object:
		index := level_object_index(doc, id); if index < 0 {return preview, false}
		ordered_remove(&doc.objects, index); case .Opening:
		index := level_opening_index(doc, id); if index < 0 {return preview, false}
		ordered_remove(&doc.openings, index); case .Room:
		index := level_room_index(doc, id); if index < 0 {return preview, false}
		ordered_remove(&doc.rooms, index); case .Path:
		index := level_path_index(doc, id); if index < 0 {return preview, false}
		ordered_remove(&doc.paths, index); case:
		return preview, false}
	return preview, true}

level_template_capture :: proc(
	id, name: string,
	source: ^Level_Document,
) -> Level_Template {return {id, name, level_clone_document(source)}}
level_template_instantiate :: proc(
	template: ^Level_Template,
	new_id, new_name: string,
) -> Level_Document {result := level_clone_document(&template.document); result.id = new_id
	result.name = new_name
	result.revision = 1
	result.dirty = true
	return result}
level_template_destroy :: proc(template: ^Level_Template) {authoring_level_document_destroy(
		&template.document,
	)
	template^ = {}}
level_room_prefab_capture :: proc(
	doc: ^Level_Document,
	room_id, id, name: string,
) -> (
	Level_Room_Prefab,
	bool,
) {index := level_room_index(doc, room_id); if index < 0 do return {}, false; result :=
		Level_Room_Prefab {
			id   = id,
			name = name,
			room = doc.rooms[index],
		}
	result.room.points = level_clone_points(doc.rooms[index].points)
	for object in doc.objects do if object.story == result.room.story && level_point_in_polygon(object.position, result.room.points[:]) do append(&result.objects, object)
	return result, true}
level_room_prefab_destroy :: proc(prefab: ^Level_Room_Prefab) {delete(prefab.room.points); delete(
		prefab.objects,
	)
	prefab^ = {}}
level_room_prefab_instantiate :: proc(
	doc: ^Level_Document,
	prefab: ^Level_Room_Prefab,
	room_id: string,
	offset: Vec2,
) -> bool {if level_room_index(doc, room_id) >= 0 do return false; room := prefab.room; room.id =
		room_id
	room.story = doc.active_story
	room.points = level_clone_points(prefab.room.points)
	for 	&point in room.points {point.x += offset.x; point.y += offset.y}
	append(&doc.rooms, room)
	for 	object, i in prefab.objects {copy := object; copy.id = level_next_id(
			fmt.tprintf("%s_prop_%d", room_id, i + 1),
			doc.revision + u64(i),
		)
		copy.story = doc.active_story
		copy.position.x += offset.x
		copy.position.y += offset.y
		copy.support_id = ""
		append(&doc.objects, copy)}
	return true}
level_prop_prefab_capture :: proc(
	doc: ^Level_Document,
	object_id, id, name: string,
) -> (
	Level_Prop_Prefab,
	bool,
) {index := level_object_index(doc, object_id); if index < 0 do return {}, false; return {
			id,
			name,
			doc.objects[index],
		},
		true}
level_prop_prefab_instantiate :: proc(
	doc: ^Level_Document,
	prefab: ^Level_Prop_Prefab,
	object_id: string,
	position: Vec2,
) -> bool {if level_object_index(doc, object_id) >= 0 do return false; object := prefab.object
	object.id = object_id
	object.story = doc.active_story
	object.position = position
	object.support_id = ""
	append(&doc.objects, object)
	return true}

// Single production action boundary for the reusable-content buttons. Capture
// and instantiate remain atomic from the caller's perspective, so UI code does
// not retain borrowed prefab/template storage between frames.
level_reuse_action :: proc(
	doc: ^Level_Document,
	kind: Level_Reuse_Action_Kind,
	source_id, new_id, new_name: string,
	position: Vec2,
) -> bool {
	if doc == nil || new_id == "" do return false
	switch kind {
	case .Create_Level_From_Template:
		template := level_template_capture(fmt.tprintf("%s_template", doc.id), new_name, doc)
		replacement := level_template_instantiate(&template, new_id, new_name)
		level_template_destroy(&template)
		authoring_level_document_destroy(doc)
		doc^ = replacement
		return true
	case .Instantiate_Room_Prefab:
		prefab, ok := level_room_prefab_capture(
			doc,
			source_id,
			fmt.tprintf("%s_prefab", source_id),
			new_name,
		)
		if !ok do return false
		created := level_room_prefab_instantiate(doc, &prefab, new_id, position)
		level_room_prefab_destroy(&prefab)
		return created
	case .Instantiate_Prop_Prefab:
		prefab, ok := level_prop_prefab_capture(
			doc,
			source_id,
			fmt.tprintf("%s_prefab", source_id),
			new_name,
		)
		if !ok do return false
		return level_prop_prefab_instantiate(doc, &prefab, new_id, position)
	}
	return false
}

level_marker_candidates :: proc(
	doc: ^Level_Document,
	story: int,
	kind: Level_Marker_Kind,
	include_other_stories: bool,
	out: ^[256]Story_Spatial_Id,
) -> int {count := 0; for 	marker in doc.markers {if marker.kind != kind || (!include_other_stories && marker.story != story) || count >= len(out^) do continue
		out[count] = {doc.id, marker.id}
		count += 1}
	return count}
level_city_site_exists :: proc(id: string) -> bool {for site in CITY_CASE_LOCATION_SITES do if site.id == id do return true
	return false}
level_city_destinations_validate :: proc(
	doc: ^Level_Document,
	destinations: []Level_City_Destination,
) -> Validation {for 	item, i in destinations {if !graph_valid_id(item.id) || item.display_name == "" || !level_city_site_exists(item.city_site) do return {false, "city destination metadata or reserved site is invalid"}
		spawn := level_marker_index(doc, item.level_spawn)
		if spawn < 0 || doc.markers[spawn].kind != .Player_Spawn do return {false, "city destination must use a player-spawn marker in this level"}
		for other in destinations[i + 1:] do if other.id == item.id || other.city_site == item.city_site do return {false, "city destination IDs and reserved sites must be unique"}}
	return{true, "CITY DESTINATIONS VALID"}}
level_character_create_and_place :: proc(
	doc: ^Level_Document,
	project: ^Story_Project,
	id, display_name: string,
	story: int,
	position: Vec2,
) -> bool {if project == nil || !graph_valid_id(id) || display_name == "" || story < 0 || story >= len(doc.stories) || position.x < 0 || position.y < 0 || position.x > f32(doc.width) || position.y > f32(doc.height) || story_entity_index(project, id) >= 0 do return false
	marker_id := fmt.tprintf("spawn_%s", id)
	if level_marker_index(doc, marker_id) >= 0 do return false
	append(
		&project.entities,
		Story_Entity {
			id = id,
			kind = "person",
			display_name = display_name,
			spatial = {doc.id, .Marker, marker_id},
		},
	)
	append(
		&doc.markers,
		Level_Marker {
			id = marker_id,
			reference = id,
			kind = .Character_Spawn,
			story = story,
			position = position,
			radius = .75,
		},
	)
	return true}


level_segments_cross :: proc(a, b, c, d: Vec2) -> bool {
	ab := wall_cap_cross(
		a,
		b,
		c,
	); ac := wall_cap_cross(a, b, d); cd := wall_cap_cross(c, d, a); ca := wall_cap_cross(c, d, b)
	return (ab > 0 && ac < 0 || ab < 0 && ac > 0) && (cd > 0 && ca < 0 || cd < 0 && ca > 0)
}

level_polygon_simple :: proc(points: []Vec2) -> bool {
	if len(points) < 3 || math.abs(level_polygon_area(points)) < .25 do return false
	for i in 0 ..< len(
		points,
	) {a, b := points[i], points[(i + 1) % len(points)]; dx, dy := b.x - a.x, b.y - a.y; if dx * dx + dy * dy < .01 do return false; for j in i + 1 ..< len(points) {if j == i || (j + 1) % len(points) == i || (i + 1) % len(points) == j do continue; c, d := points[j], points[(j + 1) % len(points)]; if level_segments_cross(a, b, c, d) do return false}}
	return true
}

level_split_polygon :: proc(
	source: []Vec2,
	a, b: Vec2,
	out_a: ^[34]Vec2,
	count_a: ^int,
	out_b: ^[34]Vec2,
	count_b: ^int,
) -> bool {
	count_a^ = 0; count_b^ = 0; if len(source) < 3 || len(source) > 32 || (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y) < .04 do return false
	edge_a, edge_b :=
		-1,
		-1; for point, i in source {next := source[(i + 1) % len(source)]; if edge_a < 0 && point_segment_distance_sq(a.x, a.y, point, next) <= .002 do edge_a = i; if edge_b < 0 && point_segment_distance_sq(b.x, b.y, point, next) <= .002 do edge_b = i}; if edge_a < 0 || edge_b < 0 || edge_a == edge_b do return false
	expanded: [34]Vec2; expanded_count := 0; for point, i in source {next := source[(i + 1) % len(source)]; expanded[expanded_count] = point; expanded_count += 1; on_a := point_segment_distance_sq(a.x, a.y, point, next) <= .002 && (a.x - point.x) * (a.x - point.x) + (a.y - point.y) * (a.y - point.y) > .002 && (a.x - next.x) * (a.x - next.x) + (a.y - next.y) * (a.y - next.y) > .002; on_b := point_segment_distance_sq(b.x, b.y, point, next) <= .002 && (b.x - point.x) * (b.x - point.x) + (b.y - point.y) * (b.y - point.y) > .002 && (b.x - next.x) * (b.x - next.x) + (b.y - next.y) * (b.y - next.y) > .002; if on_a {expanded[expanded_count] = a; expanded_count += 1}; if on_b {expanded[expanded_count] = b; expanded_count += 1}}
	index_a, index_b :=
		-1,
		-1; for point, i in expanded[:expanded_count] {if (point.x - a.x) * (point.x - a.x) + (point.y - a.y) * (point.y - a.y) <= .002 do index_a = i; if (point.x - b.x) * (point.x - b.x) + (point.y - b.y) * (point.y - b.y) <= .002 do index_b = i}; if index_a < 0 || index_b < 0 || index_a == index_b do return false
	i :=
		index_a; for {out_a[count_a^] = expanded[i]; count_a^ += 1; if i == index_b do break; i = (i + 1) % expanded_count}; i = index_b; for {out_b[count_b^] = expanded[i]; count_b^ += 1; if i == index_a do break; i = (i + 1) % expanded_count}; return count_a^ >= 3 && count_b^ >= 3 && level_polygon_simple(out_a[:count_a^]) && level_polygon_simple(out_b[:count_b^])
}

level_points_near :: proc(a, b: Vec2) -> bool {dx, dy := a.x - b.x, a.y - b.y; return(
		dx * dx + dy * dy <=
		.002 \
	)}
level_merge_polygons :: proc(
	a, b: []Vec2,
	out: ^[64]Vec2,
	count: ^int,
	shared_start, shared_finish: ^Vec2,
) -> bool {
	count^ = 0; if len(a) < 3 || len(b) < 3 do return false; edge_a, edge_b := -1, -1; for point, i in a {next := a[(i + 1) % len(a)]; for other, j in b {other_next := b[(j + 1) % len(b)]; if level_points_near(point, other_next) && level_points_near(next, other) {edge_a = i; edge_b = j; break}}; if edge_a >= 0 do break}; if edge_a < 0 do return false; shared_start^ = a[edge_a]; shared_finish^ = a[(edge_a + 1) % len(a)]
	raw: [64]Vec2; raw_count := 0; for step in 0 ..< len(a) {raw[raw_count] = a[(edge_a + 1 + step) % len(a)]; raw_count += 1}; j := (edge_b + 2) % len(b); for j != edge_b {raw[raw_count] = b[j]; raw_count += 1; j = (j + 1) % len(b)}; if raw_count < 3 do return false
	for i in 0 ..< raw_count {previous, current, next := raw[(i - 1 + raw_count) % raw_count], raw[i], raw[(i + 1) % raw_count]; cross := wall_cap_cross(previous, current, next); dx1, dy1 := current.x - previous.x, current.y - previous.y; dx2, dy2 := next.x - current.x, next.y - current.y; if math.abs(cross) < .001 && dx1 * dx2 + dy1 * dy2 >= 0 do continue; out[count^] = current; count^ += 1}; return count^ >= 3 && count^ <= 32 && level_polygon_simple(out[:count^])
}

level_merge_room_command :: proc(primary, secondary: string) -> Level_Command {return{
		kind = .Merge_Rooms,
		entity_id = primary,
		destination = secondary,
	}}

level_wall_command :: proc(
	doc: ^Level_Document,
	a, b: Vec2,
) -> (
	Level_Command,
	bool,
) {start, finish := level_snap_point(doc, a, true), level_snap_point(doc, b, true); for 	room in doc.rooms {if room.story != doc.active_story || room.exterior do continue
		first, second: [34]Vec2
		first_count, second_count := 0, 0
		if level_split_polygon(room.points[:], start, finish, &first, &first_count, &second, &second_count) do return Level_Command{kind = .Split_Room, entity_id = room.id, a = start, b = finish, material = level_next_id("wall", doc.revision), destination = level_next_id("room_split", doc.revision)}, true}
	return Level_Command {
			kind = .Add_Path,
			a = start,
			b = finish,
			c = {f32(Level_Path_Kind.Freestanding_Wall), 0},
			material = "structure",
		},
		false}

level_point_on_polygon_boundary :: proc(point: Vec2, points: []Vec2) -> bool {for p, i in points do if point_segment_distance_sq(point.x, point.y, p, points[(i + 1) % len(points)]) < .0001 do return true
	return false}
level_polygons_overlap :: proc(a, b: []Vec2) -> bool {
	if len(a) < 3 || len(b) < 3 do return false
	all_a_boundary, all_b_boundary :=
		true,
		true; for point in a do if !level_point_on_polygon_boundary(point, b) {all_a_boundary = false; break}; for point in b do if !level_point_on_polygon_boundary(point, a) {all_b_boundary = false; break}; if all_a_boundary && all_b_boundary do return true
	for point in a do if !level_point_on_polygon_boundary(point, b) && level_point_in_polygon(point, b) do return true
	for point in b do if !level_point_on_polygon_boundary(point, a) && level_point_in_polygon(point, a) do return true
	for pa, i in a {pb := a[(i + 1) % len(a)]
		for qa, j in b do if level_segments_cross(pa, pb, qa, b[(j + 1) % len(b)]) do return true}
	return false
}

level_preview_room_reshape :: proc(
	doc: ^Level_Document,
	command: Level_Command,
	result: ^Placement_Result,
) {
	index := level_room_index(
		doc,
		command.entity_id,
	); if index < 0 {result.state = .Blocked; result.message = "The selected room no longer exists."; return}; room := doc.rooms[index]; points := make([]Vec2, len(room.points), context.temp_allocator); copy(points, room.points[:]); handle := int(command.value)
	if handle < 0 ||
	   handle >=
		   len(
			   points,
		   ) {result.state = .Blocked; result.message = "The selected handle no longer exists."; return}
	if command.kind ==
	   .Move_Room_Vertex {points[handle] = command.a} else {next := (handle + 1) % len(points); points[handle].x += command.a.x; points[handle].y += command.a.y; points[next].x += command.a.x; points[next].y += command.a.y}
	for point in points {if point.x < 0 ||
		   point.y < 0 ||
		   point.x > f32(doc.width) ||
		   point.y >
			   f32(
				   doc.height,
			   ) {result.state = .Blocked; result.message = "The room would leave the lot."; return}}
	if !level_polygon_simple(
		points,
	) {result.state = .Blocked; result.message = "Room edges cannot cross or collapse."; return}; if !room.exterior && !level_points_have_foundation(doc, points, room.story) {result.state = .Blocked; result.message = "The room would leave its supporting foundation."}
}

level_room_center :: proc(room: ^Level_Room) -> Vec2 {center := Vec2{}; if len(room.points) == 0 do return center
	for 	point in room.points {center.x += point.x; center.y += point.y}
	center.x /= f32(len(room.points))
	center.y /= f32(len(room.points))
	return center}

level_rotated_point :: proc(point, center: Vec2, degrees: f32) -> Vec2 {radians :=
		degrees * f32(math.PI) / 180
	c, s := f32(math.cos(f64(radians))), f32(math.sin(f64(radians)))
	x, y := point.x - center.x, point.y - center.y
	return{center.x + x * c - y * s, center.y + x * s + y * c}}

level_preview_room_transform :: proc(
	doc: ^Level_Document,
	command: Level_Command,
	result: ^Placement_Result,
) {
	index := level_room_index(
		doc,
		command.entity_id,
	); if index < 0 {result.state = .Blocked; result.message = "The selected room no longer exists."; return}; room := &doc.rooms[index]; center := level_room_center(room); points := make([]Vec2, len(room.points), context.temp_allocator)
	for point, i in room.points {transformed := point; if command.kind == .Rotate_Room do transformed = level_rotated_point(point, center, command.value); if command.kind == .Duplicate_Room {transformed.x += command.a.x; transformed.y += command.a.y}; points[i] = transformed; if transformed.x < 0 || transformed.y < 0 || transformed.x > f32(doc.width) || transformed.y > f32(doc.height) {result.state = .Blocked; result.message = command.kind == .Duplicate_Room ? "The copy would leave the lot." : "The rotated room would leave the lot."; return}}; if !room.exterior && !level_points_have_foundation(doc, points, room.story) {result.state = .Blocked; result.message = "The room would leave its supporting foundation."}
}

level_command_preview :: proc(doc: ^Level_Document, command: Level_Command) -> Placement_Result {
	result := Placement_Result{.Valid, "READY", command.a, command.b}
	if command.kind == .Create_Foundation {
		if command.point_count < 3 ||
		   command.point_count >
			   len(
				   command.points,
			   ) {result.state = .Blocked; result.message = "A foundation needs at least three corners."; return result}; points := make([]Vec2, command.point_count, context.temp_allocator); for i in 0 ..< command.point_count {points[i] = command.points[i]; point := points[i]; if point.x < 0 || point.y < 0 || point.x > f32(doc.width) || point.y > f32(doc.height) {result.state = .Blocked; result.message = "The foundation would leave the lot."; return result}}; if !level_polygon_simple(points) || math.abs(level_polygon_area(points)) < 1 {result.state = .Blocked; result.message = "The foundation footprint is invalid."; return result}; if command.c.x == f32(Level_Foundation_Kind.Basement) && command.c.y < 1.8 {result.state = .Blocked; result.message = "A basement needs at least 1.8 meters of depth."}
		if command.c.x == f32(Level_Foundation_Kind.Basement) &&
		   level_basement_story(doc) < 0 &&
		   len(doc.stories) >=
			   doc.story_limit {result.state = .Blocked; result.message = "The story limit leaves no room for a basement."; return result}
	} else if command.kind == .Set_Foundation {
		index := level_foundation_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The selected foundation no longer exists."; return result}; foundation := doc.foundations[index]; if foundation.kind == .Raised && (command.value < .25 || command.value > 3) {result.state = .Blocked; result.message = "Raised foundation height must be between 0.25 and 3 meters."} else if foundation.kind == .Basement && (command.c.y < 1.8 || command.c.y > 6) {result.state = .Blocked; result.message = "Basement depth must be between 1.8 and 6 meters."} else if foundation.kind == .Slab && (command.c.y < .1 || command.c.y > 1) {result.state = .Blocked; result.message = "Slab thickness must be between 0.1 and 1 meter."}
	} else if command.kind == .Move_Foundation_Point {
		index := level_foundation_index(
			doc,
			command.entity_id,
		); point_index := int(command.value); if index < 0 || point_index < 0 || point_index >= len(doc.foundations[index].points) {result.state = .Blocked; result.message = "The foundation corner no longer exists."; return result}; if command.a.x < 0 || command.a.y < 0 || command.a.x > f32(doc.width) || command.a.y > f32(doc.height) {result.state = .Blocked; result.message = "The foundation would leave the lot."; return result}; foundation := doc.foundations[index]; points := make([]Vec2, len(foundation.points), context.temp_allocator); copy(points, foundation.points[:]); points[point_index] = command.a; if !level_polygon_simple(points) || math.abs(level_polygon_area(points)) < 1 {result.state = .Blocked; result.message = "The foundation footprint is invalid."; return result}; for room in doc.rooms {if room.exterior || !level_foundation_supports_story(doc, foundation, room.story) do continue; was_supported := true; for p in room.points do if !level_foundation_contains_point(foundation, p) {was_supported = false; break}; if !was_supported do continue; for p in room.points {if level_point_in_polygon(p, points) do continue; supported_elsewhere := false; for other, i in doc.foundations {if i != index && level_foundation_supports_story(doc, other, room.story) && level_foundation_contains_point(other, p) {supported_elsewhere = true; break}}; if !supported_elsewhere {result.state = .Blocked; result.message = "The corner would leave a room without foundation support."; return result}}}
	} else if command.kind == .Delete_Foundation {
		index := level_foundation_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The selected foundation no longer exists."; return result}; for room in doc.rooms {if room.exterior do continue; supported_elsewhere := false; for foundation, i in doc.foundations {if i == index || !level_foundation_supports_story(doc, foundation, room.story) do continue; supported := true; for point in room.points do if !level_foundation_contains_point(foundation, point) {supported = false; break}; if supported {supported_elsewhere = true; break}}; if !supported_elsewhere && !level_story_needs_foundation(doc, room.story) do supported_elsewhere = true; if !supported_elsewhere {result.state = .Blocked; result.message = "Move or remove supported rooms before deleting this foundation."; return result}}
	} else if command.kind == .Create_Room_Polygon {
		if command.point_count < 3 ||
		   command.point_count >
			   len(
				   command.points,
			   ) {result.state = .Blocked; result.message = "A room needs at least three corners."; return result}; points := make([]Vec2, command.point_count, context.temp_allocator); for i in 0 ..< command.point_count {points[i] = command.points[i]; point := points[i]; if point.x < 0 || point.y < 0 || point.x > f32(doc.width) || point.y > f32(doc.height) {result.state = .Blocked; result.message = "The room would leave the lot."; return result}}; if !level_polygon_simple(points) {result.state = .Blocked; result.message = "Room edges cannot cross or collapse."; return result}; if command.entity_id == "" && command.material != "" {for room in doc.rooms do if room.story == doc.active_story && !room.exterior && level_polygons_overlap(points, room.points[:]) {result.state = .Blocked; result.message = "Rooms may share walls but cannot overlap."; return result}}
		if command.destination != "patio" &&
		   !level_points_have_foundation(
				   doc,
				   points,
				   doc.active_story,
			   ) {result.state = .Blocked; result.message = "Lay a foundation before drawing this room."; return result}
	} else if command.kind == .Split_Room {
		index := level_room_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The room to split no longer exists."; return result}; first, second: [34]Vec2; first_count, second_count := 0, 0; if !level_split_polygon(doc.rooms[index].points[:], level_snap_point(doc, command.a, true), level_snap_point(doc, command.b, true), &first, &first_count, &second, &second_count) {result.state = .Blocked; result.message = "Start and end the divider on different room edges."; return result}; if !level_points_have_foundation(doc, first[:first_count], doc.rooms[index].story) || !level_points_have_foundation(doc, second[:second_count], doc.rooms[index].story) {result.state = .Blocked; result.message = "Both new rooms must remain supported."; return result}; result.message = "The wall will divide this into two editable rooms."
	} else if command.kind == .Merge_Rooms {
		first_index, second_index :=
			level_room_index(doc, command.entity_id),
			level_room_index(
				doc,
				command.destination,
			); if first_index < 0 || second_index < 0 || first_index == second_index {result.state = .Blocked; result.message = "Select two different rooms to merge."; return result}; first, second := doc.rooms[first_index], doc.rooms[second_index]; if first.story != second.story {result.state = .Blocked; result.message = "Rooms must be on the same story."; return result}; if first.exterior != second.exterior {result.state = .Blocked; result.message = "Indoor and outdoor rooms cannot be merged."; return result}; if math.abs(first.platform_height - second.platform_height) > .01 {result.state = .Blocked; result.message = "Match platform heights before merging rooms."; return result}; merged: [64]Vec2; merged_count := 0; shared_start, shared_finish := Vec2{}, Vec2{}; if !level_merge_polygons(first.points[:], second.points[:], &merged, &merged_count, &shared_start, &shared_finish) {result.state = .Blocked; result.message = "The selected rooms need one shared wall."; return result}; if first.floor_material != second.floor_material || first.wall_material != second.wall_material {result.state = .Warning; result.message = "The primary room's finishes will cover the merged room."} else {result.message = "The shared wall will be removed."}
	} else if command.kind == .Insert_Room_Vertex || command.kind == .Remove_Room_Vertex {
		index := level_room_index(
			doc,
			command.entity_id,
		); handle := int(command.value); if index < 0 || handle < 0 || handle >= len(doc.rooms[index].points) {result.state = .Blocked; result.message = "The selected corner no longer exists."; return result}; source := doc.rooms[index].points; new_count := command.kind == .Insert_Room_Vertex ? len(source) + 1 : len(source) - 1; if new_count < 3 || new_count > 32 {result.state = .Blocked; result.message = "Rooms need between three and thirty-two corners."; return result}; points := make([]Vec2, new_count, context.temp_allocator); write := 0; for point, i in source {if command.kind == .Remove_Room_Vertex && i == handle do continue; points[write] = point; write += 1; if command.kind == .Insert_Room_Vertex && i == handle {points[write] = command.a; write += 1}}; if !level_polygon_simple(points) {result.state = .Blocked; result.message = "That corner would collapse or cross the room."}
	} else if command.kind == .Move_Room {
		index := level_room_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The selected room no longer exists."; return result}
		points := make(
			[]Vec2,
			len(doc.rooms[index].points),
			context.temp_allocator,
		); for point, i in doc.rooms[index].points {moved := Vec2{point.x + command.a.x, point.y + command.a.y}; points[i] = moved; if moved.x < 0 || moved.y < 0 || moved.x > f32(doc.width) || moved.y > f32(doc.height) {result.state = .Blocked; result.message = "The room would leave the lot."; return result}}; if !doc.rooms[index].exterior && !level_points_have_foundation(doc, points, doc.rooms[index].story) {result.state = .Blocked; result.message = "The room would leave its supporting foundation."}
	} else if command.kind == .Duplicate_Room || command.kind == .Rotate_Room {
		level_preview_room_transform(doc, command, &result)
	} else if command.kind == .Move_Room_Vertex || command.kind == .Move_Room_Edge {
		level_preview_room_reshape(doc, command, &result)
	} else if command.kind == .Duplicate_Object {
		index := level_object_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The selected object no longer exists."} else {target := Vec2{doc.objects[index].position.x + command.a.x, doc.objects[index].position.y + command.a.y}; if target.x < 0 || target.y < 0 || target.x > f32(doc.width) || target.y > f32(doc.height) {result.state = .Blocked; result.message = "The copy would leave the lot."}}
	} else if command.kind == .Add_Light || command.kind == .Set_Light {
		if command.a.x < 0 ||
		   command.a.y < 0 ||
		   command.a.x > f32(doc.width) ||
		   command.a.y >
			   f32(
				   doc.height,
			   ) {result.state = .Blocked; result.message = "The light would leave the lot."; return result}; if command.b.x <= 0 || command.b.x > 40 {result.state = .Blocked; result.message = "Light range must be between 0 and 40 meters."; return result}; if command.b.y <= 0 || command.b.y > 100 {result.state = .Blocked; result.message = "Light intensity must be between 0 and 100."; return result}; if command.c.x < 0 || command.c.x > 20 {result.state = .Blocked; result.message = "Light elevation must be between 0 and 20 meters."; return result}; if command.kind == .Set_Light && level_light_index(doc, command.entity_id) < 0 {result.state = .Blocked; result.message = "The selected light no longer exists."}
	} else if command.kind == .Delete_Light {
		if level_light_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected light no longer exists."}
	} else if command.kind == .Add_Path {
		count :=
			command.point_count; if count == 0 do count = 2; if count < 2 || count > len(command.points) {result.state = .Blocked; result.message = "A path needs at least two control points."; return result}; width := command.value; if width <= 0 do width = HOUSE_WALL_THICKNESS; if width < .2 || width > 8 {result.state = .Blocked; result.message = "Path width must be between 0.2 and 8 meters."; return result}; for i in 0 ..< count {p := count == 2 && command.point_count == 0 ? (i == 0 ? command.a : command.b) : command.points[i]; if p.x < 0 || p.y < 0 || p.x > f32(doc.width) || p.y > f32(doc.height) {result.state = .Blocked; result.message = "The path leaves the lot."; return result}; if i > 0 {previous := count == 2 && command.point_count == 0 ? (i - 1 == 0 ? command.a : command.b) : command.points[i - 1]; dx, dy := p.x - previous.x, p.y - previous.y; if dx * dx + dy * dy < .04 {result.state = .Blocked; result.message = "Path control points are too close."; return result}}}
		kind := Level_Path_Kind(
			clamp(int(command.c.x), 0, int(Level_Path_Kind.Footpath)),
		); if kind == .Road || kind == .Footpath {for i in 0 ..< count {p := count == 2 && command.point_count == 0 ? (i == 0 ? command.a : command.b) : command.points[i]; for room in doc.rooms {if room.story == doc.active_story && !room.exterior && level_point_in_polygon(p, room.points[:]) {result.state = .Warning; result.message = "The path crosses an interior room."; break}}}}
	} else if command.kind == .Set_Path {
		index := level_path_index(
			doc,
			command.entity_id,
		); if index < 0 {result.state = .Blocked; result.message = "The selected path no longer exists."; return result}; path := doc.paths[index]; minimum := path.kind == .Wall ? f32(.1) : f32(.2); maximum := path.kind == .Wall ? f32(1) : f32(8); if command.value < minimum || command.value > maximum {result.state = .Blocked; result.message = path.kind == .Wall ? "Wall width must be between 0.1 and 1 meter." : "Path width must be between 0.2 and 8 meters."}
	} else if command.kind == .Move_Path_Point {
		index := level_path_index(
			doc,
			command.entity_id,
		); point_index := int(command.value); if index < 0 || point_index < 0 || point_index >= len(doc.paths[index].points) {result.state = .Blocked; result.message = "The path control point no longer exists."; return result}; if command.a.x < 0 || command.a.y < 0 || command.a.x > f32(doc.width) || command.a.y > f32(doc.height) {result.state = .Blocked; result.message = "The path point would leave the lot."; return result}; path := doc.paths[index]; neighbors := [2]int{point_index - 1, point_index + 1}; for neighbor in neighbors {if neighbor >= 0 && neighbor < len(path.points) {dx, dy := command.a.x - path.points[neighbor].x, command.a.y - path.points[neighbor].y; if dx * dx + dy * dy < .04 {result.state = .Blocked; result.message = "Path control points are too close."; return result}}}
	} else if command.kind == .Create_Water {
		if command.point_count < 3 ||
		   command.point_count >
			   len(
				   command.points,
			   ) {result.state = .Blocked; result.message = "A pond needs at least three shoreline points."; return result}; points := make([]Vec2, command.point_count, context.temp_allocator); for i in 0 ..< command.point_count {points[i] = command.points[i]; p := points[i]; if p.x < 0 || p.y < 0 || p.x > f32(doc.width) || p.y > f32(doc.height) {result.state = .Blocked; result.message = "The shoreline leaves the lot."; return result}}; if !level_polygon_simple(points) {result.state = .Blocked; result.message = "The shoreline cannot cross itself."; return result}; if math.abs(level_polygon_area(points)) < .5 {result.state = .Blocked; result.message = "The pond is too small."}
		if result.state !=
		   .Blocked {for p in points {for room in doc.rooms {if !room.exterior && level_point_in_polygon(p, room.points[:]) {result.state = .Warning; result.message = "The pond overlaps an interior room."; break}}}}
	} else if command.kind == .Set_Water {
		if level_water_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected pond no longer exists."} else if command.value < -5 || command.value > 5 {result.state = .Blocked; result.message = "Water elevation must be between -5 and 5 meters."}
	} else if command.kind == .Move_Water_Point {
		index := level_water_index(
			doc,
			command.entity_id,
		); point_index := int(command.value); if index < 0 || point_index < 0 || point_index >= len(doc.waters[index].points) {result.state = .Blocked; result.message = "The shoreline point no longer exists."; return result}; if command.a.x < 0 || command.a.y < 0 || command.a.x > f32(doc.width) || command.a.y > f32(doc.height) {result.state = .Blocked; result.message = "The shoreline would leave the lot."; return result}; points := make([]Vec2, len(doc.waters[index].points), context.temp_allocator); copy(points, doc.waters[index].points[:]); points[point_index] = command.a; if !level_polygon_simple(points) {result.state = .Blocked; result.message = "The shoreline cannot cross itself."; return result}; if math.abs(level_polygon_area(points)) < .5 {result.state = .Blocked; result.message = "The pond is too small."}
	} else if command.kind == .Delete_Water {
		if level_water_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected pond no longer exists."}
	} else if command.kind == .Add_Opening || command.kind == .Set_Opening {
		if command.kind == .Set_Opening &&
		   level_opening_index(doc, command.entity_id) <
			   0 {result.state = .Blocked; result.message = "The selected opening no longer exists."; return result}; path_index := level_path_index(doc, command.material); segment := int(command.value); if path_index < 0 || segment < 0 || segment >= len(doc.paths[path_index].points) - 1 {result.state = .Blocked; result.message = "Choose a valid wall span."; return result}; path := doc.paths[path_index]; if path.story != doc.active_story {result.state = .Blocked; result.message = "The wall is on another story."; return result}; a, b := path.points[segment], path.points[segment + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); kind := Level_Opening_Kind(clamp(int(command.b.x), 0, int(Level_Opening_Kind.Gate))); default_width := kind == .Window ? f32(1.6) : kind == .Arch ? f32(1.5) : kind == .Gate ? f32(1.4) : f32(1.2); default_height := kind == .Window ? f32(1.4) : kind == .Arch ? f32(2.2) : kind == .Gate ? f32(1.5) : f32(2.1); width := command.b.y > 0 ? command.b.y : default_width; height := command.c.y > 0 ? command.c.y : default_height; if width < .4 || width > 6 {result.state = .Blocked; result.message = "Opening width must be between 0.4 and 6 meters."; return result}; if height < .4 || height > 4 {result.state = .Blocked; result.message = "Opening height must be between 0.4 and 4 meters."; return result}; end_clearance := level_opening_end_clearance(kind); if length < width + end_clearance * 2 {result.state = .Blocked; result.message = "This wall span is too short for the opening and its trim."; return result}; position := clamp(command.c.x, (width * .5 + end_clearance) / length, 1 - (width * .5 + end_clearance) / length); center := position * length; for opening in doc.openings {if opening.id == command.entity_id || opening.host_path != command.material || opening.segment != segment do continue; other_center := opening.position * length; if math.abs(center - other_center) < (width + opening.width) * .5 + level_opening_finish_clearance(kind, opening.kind) {result.state = .Blocked; result.message = "Finished opening trim needs clear wall between openings."; return result}}; result.bounds_min = {a.x + dx * position, a.y + dy * position}; result.bounds_max = result.bounds_min
		if kind ==
		   .Window {sill_height := command.points[0].x; if sill_height <= 0 do sill_height = .72; wall_height := doc.stories[path.story].wall_height; if sill_height < .2 || sill_height > 2 {result.state = .Blocked; result.message = "Window sill height must be between 0.2 and 2 meters."; return result}; if wall_height > 0 && level_window_head_finish_height(sill_height, height) > wall_height + .001 {result.state = .Blocked; result.message = "Window head trim and flashing must remain below the wall top."; return result}}
	} else if command.kind == .Create_Roof || command.kind == .Set_Roof {
		room_index := level_room_index(
			doc,
			command.material,
		); if room_index < 0 {result.state = .Blocked; result.message = "Choose a room footprint for the roof."; return result}; room := doc.rooms[room_index]; if len(room.points) < 3 || !level_polygon_simple(room.points[:]) {result.state = .Blocked; result.message = "The room footprint cannot generate a roof."; return result}; if command.value < 1 || command.value > 75 {result.state = .Blocked; result.message = "Roof pitch must be between 1 and 75 degrees."; return result}; if command.b.x < 0 || command.b.x > 2 {result.state = .Blocked; result.message = "Roof overhang must be between 0 and 2 meters."; return result}; if command.kind == .Create_Roof && level_roof_for_room(doc, command.material) >= 0 {result.state = .Blocked; result.message = "This room already has a roof."}
	} else if command.kind == .Delete_Roof {
		if level_roof_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected roof no longer exists."}
	} else if command.kind == .Create_Vertical_Link {
		to_story := level_story_above(
			doc,
			doc.active_story,
		); if doc.active_story < 0 || to_story < 0 {result.state = .Blocked; result.message = "Add or select a story above this one."; return result}
		if command.value < .6 ||
		   command.value >
			   3 {result.state = .Blocked; result.message = "Stair width must be between 0.6 and 3 meters."; return result}
		landings := [2]Vec2 {
			command.a,
			command.b,
		}; for p in landings {if p.x < 0 || p.y < 0 || p.x > f32(doc.width) || p.y > f32(doc.height) {result.state = .Blocked; result.message = "Both landings must stay inside the lot."; return result}}
		dx, dy :=
			command.b.x -
			command.a.x,
			command.b.y -
			command.a.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy))); if distance < command.value * 1.5 {result.state = .Blocked; result.message = "The landings are too close for a valid stair turn."; return result}; rise := doc.stories[to_story].base_elevation - doc.stories[doc.active_story].base_elevation; if rise < 1.8 || rise > 6 {result.state = .Blocked; result.message = "The adjacent story elevation cannot be reached by stairs."; return result}; required := rise / .18 * .28; if distance < required * .55 {result.state = .Warning; result.message = "A compact U-shaped stair will be generated."} else if distance < required * .9 {result.state = .Warning; result.message = "An L-shaped stair will be generated."}; result.bounds_min = {min(command.a.x, command.b.x) - command.value * .5, min(command.a.y, command.b.y) - command.value * .5}; result.bounds_max = {max(command.a.x, command.b.x) + command.value * .5, max(command.a.y, command.b.y) + command.value * .5}
	} else if command.kind == .Set_Vertical_Link {
		if level_vertical_link_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected vertical link no longer exists."} else if command.value < .6 || command.value > 3 {result.state = .Blocked; result.message = "Link width must be between 0.6 and 3 meters."}
	} else if command.kind == .Move_Vertical_Link_Point {
		index := level_vertical_link_index(
			doc,
			command.entity_id,
		); point_index := int(command.value); if index < 0 || point_index < 0 || point_index > 1 {result.state = .Blocked; result.message = "The selected landing no longer exists."; return result}; link := doc.vertical_links[index]; if command.a.x < 0 || command.a.y < 0 || command.a.x > f32(doc.width) || command.a.y > f32(doc.height) {result.state = .Blocked; result.message = "The landing must stay inside the lot."; return result}; other := point_index == 0 ? link.finish : link.start; dx, dy := command.a.x - other.x, command.a.y - other.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy))); if distance < link.width * 1.5 {result.state = .Blocked; result.message = "The landings are too close for a valid stair turn."; return result}; if link.from_story < 0 || link.to_story < 0 || link.from_story >= len(doc.stories) || link.to_story >= len(doc.stories) {result.state = .Blocked; result.message = "The linked stories no longer exist."; return result}; rise := doc.stories[link.to_story].base_elevation - doc.stories[link.from_story].base_elevation; required := rise / .18 * .28; if distance < required * .55 {result.state = .Warning; result.message = "A compact U-shaped stair will be generated."} else if distance < required * .9 {result.state = .Warning; result.message = "An L-shaped stair will be generated."}; result.bounds_min = {min(command.a.x, other.x) - link.width * .5, min(command.a.y, other.y) - link.width * .5}; result.bounds_max = {max(command.a.x, other.x) + link.width * .5, max(command.a.y, other.y) + link.width * .5}
	} else if command.kind == .Delete_Vertical_Link {
		if level_vertical_link_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected vertical link no longer exists."}
	} else if command.kind == .Delete_Marker {
		if level_marker_index(doc, command.entity_id) <
		   0 {result.state = .Blocked; result.message = "The selected marker no longer exists."}
	} else if command.kind == .Create_Room ||
	   command.kind == .Place_Object ||
	   command.kind == .Move_Object ||
	   command.kind == .Sculpt_Terrain ||
	   command.kind == .Add_Marker ||
	   command.kind == .Set_Marker {
		if command.a.x < 0 ||
		   command.a.y < 0 ||
		   command.a.x > f32(doc.width) ||
		   command.a.y >
			   f32(
				   doc.height,
			   ) {result.state = .Blocked; result.message = "Placement is outside the lot."}
		if command.kind == .Set_Marker &&
		   level_marker_index(doc, command.entity_id) <
			   0 {result.state = .Blocked; result.message = "The selected marker no longer exists."; return result}
		if command.kind == .Set_Marker &&
		   command.interaction_prompt != "" &&
		   command.interaction_prompt !=
			   command.entity_id {if !graph_valid_id(command.interaction_prompt) {result.state = .Blocked; result.message = "Marker names use letters, numbers, and underscores."; return result}; if level_marker_index(doc, command.interaction_prompt) >= 0 {result.state = .Blocked; result.message = "That marker name is already in use."; return result}}
		if (command.kind == .Add_Marker || command.kind == .Set_Marker) &&
		   command.b.x <=
			   0 {result.state = .Blocked; result.message = "Marker radius must be greater than zero."; return result}
		if command.kind == .Add_Marker ||
		   command.kind ==
			   .Set_Marker {kind := Level_Marker_Kind(clamp(int(command.c.y), 0, int(Level_Marker_Kind.Staging))); if (kind == .Character_Spawn || kind == .Interaction || kind == .Clue) && command.material == "" {result.state = .Warning; result.message = "Bind this marker to a qualified StoryCore spatial target."} else if kind == .Trigger && command.material == "" {result.state = .Warning; result.message = "Bind this trigger to a story event."} else if kind == .Transition && command.destination == "" {result.state = .Warning; result.message = "Choose a destination marker."}}
		if command.kind == .Sculpt_Terrain &&
		   (command.b.x < 0 ||
				   command.b.y < 0 ||
				   command.b.x > f32(doc.width) ||
				   command.b.y >
					   f32(
						   doc.height,
					   )) {result.state = .Blocked; result.message = "The terrain stroke leaves the lot."}
		if command.kind == .Sculpt_Terrain &&
		   result.state !=
			   .Blocked {radius := max(command.value, .25); for y in 0 ..= doc.height {for x in 0 ..= doc.width {point := Vec2{f32(x), f32(y)}; distance, _ := level_segment_distance(point, command.a, command.b); if distance <= radius && level_terrain_reserved_by_foundation(doc, point) {result.state = .Blocked; result.message = "Terrain beneath a foundation or basement is locked."; return result}}}}
		if command.kind == .Place_Object && result.state != .Blocked && editor_catalog.loaded {
			entry, found := catalog_object_entry(
				command.material,
			); if !found || !entry.valid {result.state = .Blocked; result.message = "This catalog model is unavailable."; return result}
			radius := max(
				entry.footprint,
				.2,
			); if command.a.x - radius < 0 || command.a.y - radius < 0 || command.a.x + radius > f32(doc.width) || command.a.y + radius > f32(doc.height) {result.state = .Blocked; result.message = "The object's footprint leaves the lot."; return result}
			if command.destination !=
			   "" {support_index := level_object_index(doc, command.destination); if support_index < 0 || doc.objects[support_index].story != doc.active_story {result.state = .Blocked; result.message = "The furniture support is no longer available."; return result}; if command.c.x <= doc.objects[support_index].elevation {result.state = .Blocked; result.message = "The furniture surface height is invalid."; return result}; result.message = "Place on furniture."}
			inside :=
				false; for room in doc.rooms do if room.story == doc.active_story && !room.exterior && level_point_in_polygon(command.a, room.points[:]) do inside = true
			if entry.placement == "indoor" &&
			   !inside {result.state = .Warning; result.message = "This object is authored for indoor placement."}
			for object in doc.objects {if object.story != doc.active_story || object.id == command.destination do continue; other_entry, other_found := catalog_object_entry(object.catalog_id); other_radius := f32(.35); if other_found do other_radius = max(other_entry.footprint, .2); dx, dy := object.position.x - command.a.x, object.position.y - command.a.y; if dx * dx + dy * dy < (radius + other_radius) * (radius + other_radius) {result.state = .Warning; result.message = "Object footprints overlap."; break}}
			if command.destination == "" {
				doorway_badness := level_furniture_doorway_badness(doc, command.a, radius)
				// A warning is intentionally overridable, so agents were allowed to
				// commit furniture whose footprint actually crossed the opening.  Keep
				// the softer approach/circulation ring as a warning, but make contact
				// with the doorway itself a hard placement failure.
				if doorway_badness >=
				   .999 {result.state = .Blocked; result.message = "Furniture footprint obstructs a doorway."; return result}
				if level_furniture_circulation_cost(doc, command.a, radius) >=
				   .78 {result.state = .Warning; result.message = "Furniture blocks a door approach or circulation space."}
			}
			if level_catalog_entry_uses_surface(
				entry,
				"wall",
			) {wall_score := level_wall_hanging_badness(doc, command.a, command.c.x, command.value, entry, command.entity_id); if wall_score.total >= .5 {result.state = .Warning; if wall_score.opening_overlap >= .5 do result.message = "Wall hanging overlaps a door or window."
					else if wall_score.wall_penetration >= .5 do result.message = "Wall hanging intersects the wall."
					else if wall_score.vertical_fit >= .5 do result.message = "Wall hanging does not fit between the floor and wall top."
					else if wall_score.hanging_overlap >= .5 do result.message = "Wall hangings overlap."
					else if wall_score.wall_distance >= .5 do result.message = "Wall hanging is not attached to a wall."
					else do result.message = "Wall hanging is not aligned with its wall."}}
		}
	}
	if command.kind ==
	   .Create_Room {if math.abs((command.b.x - command.a.x) * (command.b.y - command.a.y)) < 1 {result.state = .Blocked; result.message = "Room needs at least one square meter."; return result}; a, b := level_snap_point(doc, command.a), level_snap_point(doc, command.b); points := [4]Vec2{{min(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), max(a.y, b.y)}, {min(a.x, b.x), max(a.y, b.y)}}; if command.destination != "patio" && !level_points_have_foundation(doc, points[:], doc.active_story) {result.state = .Blocked; result.message = "Lay a foundation before drawing this room."; return result}; if command.entity_id == "" && command.material != "" {for room in doc.rooms do if room.story == doc.active_story && !room.exterior && level_polygons_overlap(points[:], room.points[:]) {result.state = .Blocked; result.message = "Rooms may share walls but cannot overlap."; return result}}}
	return result
}

level_room_index :: proc(doc: ^Level_Document, id: string) -> int {for room, i in doc.rooms do if room.id == id do return i
	return -1}

// Furniture placement uses the same circulation field that the editor draws on
// the floor.  Keeping this in the level domain makes the warning and heatmap
// agree, and gives agents a cheap score they can query before committing.
LEVEL_CIRCULATION_DOOR_CLEARANCE :: f32(1.35)
LEVEL_CIRCULATION_FURNITURE_CLEARANCE :: f32(.45)

Wall_Hanging_Badness :: struct {
	wall_distance,
	wall_penetration,
	alignment,
	opening_overlap,
	vertical_fit,
	hanging_overlap,
	total: f32,
}

level_catalog_entry_uses_surface :: proc(entry: ^Catalog_Entry, surface: string) -> bool {for candidate in entry.surfaces do if candidate == surface do return true
	return false}

level_wall_hanging_badness :: proc(
	doc: ^Level_Document,
	point: Vec2,
	elevation, rotation: f32,
	entry: ^Catalog_Entry,
	ignore_object_id := "",
) -> Wall_Hanging_Badness {
	result := Wall_Hanging_Badness {
		wall_distance = 1,
		alignment     = 1,
	}
	best_path, best_segment :=
		-1,
		-1; best_distance := f32(1e30); best_t := f32(0); best_length := f32(0); best_heading := f32(0)
	for path, path_index in doc.paths {if path.story != doc.active_story || (path.kind != .Wall && path.kind != .Freestanding_Wall && path.kind != .Half_Wall) do continue; for segment in 0 ..< len(path.points) - 1 {a, b := path.points[segment], path.points[segment + 1]; distance, t := level_segment_distance(point, a, b); if distance < best_distance {dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length <= .001 do continue; best_path = path_index; best_segment = segment; best_distance = distance; best_t = t; best_length = length; best_heading = f32(math.atan2(f64(dy), f64(dx))) * 180 / f32(math.PI)}}}
	if best_path < 0 {result.total = 1; return result}
	// Measure the valid attachment band from the actual wall face and model back,
	// rather than from a fixed centerline distance. This works for both thin room
	// partitions and thick exterior masonry.
	path :=
		doc.paths[best_path]; wall_half_depth := house_wall_width(path.width) * .5; object_half_depth := max(entry.dimensions.z * .5, f32(.01)); mounting_allowance := min(object_half_depth, f32(.015)); minimum_center_distance := wall_half_depth + object_half_depth - mounting_allowance
	result.wall_penetration = clamp(
		(minimum_center_distance - best_distance) / max(object_half_depth, f32(.05)),
		0,
		1,
	)
	maximum_center_distance :=
		wall_half_depth +
		object_half_depth +
		.12; result.wall_distance = clamp((best_distance - maximum_center_distance) / .28, 0, 1)
	delta := math.abs(
		rotation - best_heading,
	); for delta >= 180 do delta -= 180; if delta > 90 do delta = 180 - delta; result.alignment = clamp((delta - 5) / 25, 0, 1)
	half_width := max(
		entry.dimensions.x * .5,
		.1,
	); bottom := elevation; top := elevation + max(entry.dimensions.y, .1); wall_height := doc.stories[doc.active_story].wall_height
	if bottom < .25 do result.vertical_fit = max(result.vertical_fit, clamp((.25 - bottom) / .25, 0, 1)); if top > wall_height - .1 do result.vertical_fit = max(result.vertical_fit, clamp((top - (wall_height - .1)) / .3, 0, 1))
	center_along := best_t * best_length
	for opening in doc.openings {if opening.host_path != path.id || opening.segment != best_segment do continue; opening_center := opening.position * best_length; horizontal_overlap := half_width + opening.width * .5 - math.abs(center_along - opening_center); if horizontal_overlap <= 0 do continue; opening_bottom := opening.kind == .Window ? opening.sill_height : f32(0); opening_top := opening_bottom + opening.height; vertical_overlap := min(top, opening_top) - max(bottom, opening_bottom); if vertical_overlap > 0 do result.opening_overlap = max(result.opening_overlap, clamp(min(horizontal_overlap / (half_width + .01), vertical_overlap / max(entry.dimensions.y, .1)), 0, 1))}
	for object in doc.objects {if object.id == ignore_object_id || object.story != doc.active_story do continue; other, found := catalog_object_entry(object.catalog_id); if !found || !level_catalog_entry_uses_surface(other, "wall") do continue; distance, other_t := level_segment_distance(object.position, path.points[best_segment], path.points[best_segment + 1]); if distance > .4 do continue; other_half_width := max(other.dimensions.x * .5, .1); horizontal_overlap := half_width + other_half_width - math.abs(center_along - other_t * best_length); vertical_overlap := min(top, object.elevation + max(other.dimensions.y, .1)) - max(bottom, object.elevation); if horizontal_overlap > 0 && vertical_overlap > 0 do result.hanging_overlap = max(result.hanging_overlap, clamp(min(horizontal_overlap / (half_width + .01), vertical_overlap / max(entry.dimensions.y, .1)), 0, 1))}
	result.total = max(
		result.wall_distance,
		result.wall_penetration,
		result.alignment,
		result.opening_overlap,
		result.vertical_fit,
		result.hanging_overlap,
	)
	return result
}

level_opening_position :: proc(doc: ^Level_Document, opening: Level_Opening) -> (Vec2, bool) {
	path_index := level_path_index(doc, opening.host_path); if path_index < 0 do return {}, false
	path :=
		doc.paths[path_index]; if path.story != doc.active_story || opening.segment < 0 || opening.segment >= len(path.points) - 1 do return {}, false
	a, b := path.points[opening.segment], path.points[opening.segment + 1]
	return {a.x + (b.x - a.x) * opening.position, a.y + (b.y - a.y) * opening.position}, true
}

level_furniture_doorway_badness :: proc(doc: ^Level_Document, point: Vec2, radius: f32) -> f32 {
	result := f32(0)
	for opening in doc.openings {
		if opening.kind != .Door do continue
		path_index := level_path_index(doc, opening.host_path); if path_index < 0 do continue
		path :=
			doc.paths[path_index]; if path.story != doc.active_story || opening.segment < 0 || opening.segment >= len(path.points) - 1 do continue
		a, b :=
			path.points[opening.segment],
			path.points[opening.segment + 1]; dx, dy := b.x - a.x, b.y - a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length <= .001 do continue
		center := opening.position * length; half_width := opening.width * .5
		start := Vec2 {
			a.x + dx * (center - half_width) / length,
			a.y + dy * (center - half_width) / length,
		}
		finish := Vec2 {
			a.x + dx * (center + half_width) / length,
			a.y + dy * (center + half_width) / length,
		}
		distance, _ := level_segment_distance(point, start, finish)
		// One means the circular catalog footprint reaches the threshold line.
		// The short falloff is useful to callers that want to rank near misses.
		result = max(result, clamp(1 - (distance - radius) / .35, 0, 1))
	}
	return result
}

level_object_blocks_circulation :: proc(
	object: Level_Object,
	entry: ^Catalog_Entry,
	found: bool,
) -> bool {
	if object.support_id != "" || object.elevation > .05 do return false
	if found && (entry.category == "rugs" || entry.placement == "wall") do return false
	return true
}

level_circulation_cost :: proc(doc: ^Level_Document, point: Vec2, ignore_object_id := "") -> f32 {
	cost := f32(0)
	for opening in doc.openings {
		if opening.kind != .Door do continue
		position, ok := level_opening_position(doc, opening); if !ok do continue
		dx, dy :=
			point.x -
			position.x,
			point.y -
			position.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
		// The inner disk protects the doorway itself.  The soft outer ring keeps a
		// readable approach lane without making an entire small room look invalid.
		cost = max(cost, clamp(1 - (distance - LEVEL_CIRCULATION_DOOR_CLEARANCE) / 1.25, 0, 1))
	}
	for object in doc.objects {
		if object.story != doc.active_story || object.id == ignore_object_id do continue
		entry, found := catalog_object_entry(
			object.catalog_id,
		); if !level_object_blocks_circulation(object, entry, found) do continue; radius := f32(.35); if found do radius = max(entry.footprint, .2)
		dx, dy :=
			point.x -
			object.position.x,
			point.y -
			object.position.y; distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
		cost = max(
			cost,
			clamp(1 - (distance - radius) / LEVEL_CIRCULATION_FURNITURE_CLEARANCE, 0, 1),
		)
	}
	return cost
}

level_furniture_circulation_cost :: proc(
	doc: ^Level_Document,
	point: Vec2,
	radius: f32,
	ignore_object_id := "",
) -> f32 {
	// Sample the center and four footprint edges so large furniture cannot hide a
	// blocked door behind a harmless-looking center point.
	result := level_circulation_cost(
		doc,
		point,
		ignore_object_id,
	); samples := [4]Vec2{{point.x - radius, point.y}, {point.x + radius, point.y}, {point.x, point.y - radius}, {point.x, point.y + radius}}
	for sample in samples do result = max(result, level_circulation_cost(doc, sample, ignore_object_id))
	return result
}
level_foundation_index :: proc(doc: ^Level_Document, id: string) -> int {for foundation, i in doc.foundations do if foundation.id == id do return i
	return -1}
level_basement_story :: proc(doc: ^Level_Document) -> int {best := -1; best_elevation := f32(
		-1000000,
	)
	for story, i in doc.stories do if story.base_elevation < -.01 && story.base_elevation > best_elevation {best = i; best_elevation = story.base_elevation}
	return best}
level_ground_story :: proc(doc: ^Level_Document) -> int {best := -1; best_distance := f32(1000000)
	for story, i in doc.stories {distance := math.abs(story.base_elevation); if distance < best_distance {best = i
			best_distance = distance}}
	return best}
level_story_needs_foundation :: proc(doc: ^Level_Document, story: int) -> bool {if story < 0 || story >= len(doc.stories) do return true
	return doc.stories[story].base_elevation <= .01}
level_foundation_supports_story :: proc(
	doc: ^Level_Document,
	foundation: Level_Foundation,
	story: int,
) -> bool {if story < 0 || story >= len(doc.stories) do return false; elevation :=
		doc.stories[story].base_elevation
	if elevation < -.01 do return foundation.kind == .Basement && foundation.story == story
	if elevation <= .01 do return true
	return false}
level_path_index :: proc(doc: ^Level_Document, id: string) -> int {for path, i in doc.paths do if path.id == id do return i
	return -1}
level_opening_index :: proc(doc: ^Level_Document, id: string) -> int {for opening, i in doc.openings do if opening.id == id do return i
	return -1}
level_object_index :: proc(doc: ^Level_Document, id: string) -> int {for object, i in doc.objects do if object.id == id do return i
	return -1}
level_light_index :: proc(doc: ^Level_Document, id: string) -> int {for light, i in doc.lights do if light.id == id do return i
	return -1}
level_roof_index :: proc(doc: ^Level_Document, id: string) -> int {for roof, i in doc.roofs do if roof.id == id do return i
	return -1}
level_roof_for_room :: proc(doc: ^Level_Document, room_id: string) -> int {for roof, i in doc.roofs do if roof.room_id == room_id do return i
	return -1}
level_vertical_link_index :: proc(doc: ^Level_Document, id: string) -> int {for link, i in doc.vertical_links do if link.id == id do return i
	return -1}
level_water_index :: proc(doc: ^Level_Document, id: string) -> int {for water, i in doc.waters do if water.id == id do return i
	return -1}
level_marker_index :: proc(doc: ^Level_Document, id: string) -> int {for marker, i in doc.markers do if marker.id == id do return i
	return -1}
level_foundation_contains_point :: proc(
	foundation: Level_Foundation,
	point: Vec2,
) -> bool {if level_point_in_polygon(point, foundation.points[:]) do return true; for i in 0 ..< len(foundation.points) do if point_segment_distance_sq(point.x, point.y, foundation.points[i], foundation.points[(i + 1) % len(foundation.points)]) <= .001 do return true
	return false}
level_foundation_contains_polygon :: proc(
	foundation: Level_Foundation,
	points: []Vec2,
) -> bool {if len(points) < 3 do return false; for point in points do if !level_foundation_contains_point(foundation, point) do return false
	for 	point, i in points {next := points[(i + 1) % len(points)]; mid := Vec2 {
			(point.x + next.x) * .5,
			(point.y + next.y) * .5,
		}
		if !level_foundation_contains_point(foundation, mid) do return false
		for 		edge, j in foundation.points {if level_segments_cross(point, next, edge, foundation.points[(j + 1) % len(foundation.points)]) do return false}}
	return true}
level_room_has_foundation :: proc(
	doc: ^Level_Document,
	room: Level_Room,
) -> bool {if room.exterior || !level_story_needs_foundation(doc, room.story) do return true
	return level_points_have_foundation(doc, room.points[:], room.story)}
level_points_have_foundation :: proc(
	doc: ^Level_Document,
	points: []Vec2,
	story: int,
) -> bool {if !level_story_needs_foundation(doc, story) do return true; for foundation in doc.foundations do if level_foundation_supports_story(doc, foundation, story) && level_foundation_contains_polygon(foundation, points) do return true
	return false}
level_terrain_reserved_by_foundation :: proc(doc: ^Level_Document, point: Vec2) -> bool {for foundation in doc.foundations do if level_foundation_contains_point(foundation, point) do return true
	return false}
level_selection_for_id :: proc(doc: ^Level_Document, id: string) -> Editor_Selection {if id == "" do return {}
	if level_marker_index(doc, id) >= 0 do return {.Marker, id, -1}
	if level_light_index(doc, id) >= 0 do return {.Light, id, -1}
	if level_opening_index(doc, id) >= 0 do return {.Opening, id, -1}
	if level_object_index(doc, id) >= 0 do return {.Object, id, -1}
	if level_roof_index(doc, id) >= 0 do return {.Roof, id, -1}
	if level_vertical_link_index(doc, id) >= 0 do return {.Vertical_Link, id, -1}
	if level_water_index(doc, id) >= 0 do return {.Water, id, -1}
	if level_path_index(doc, id) >= 0 do return {.Path, id, -1}
	if level_foundation_index(doc, id) >= 0 do return {.Foundation, id, -1}
	if level_room_index(doc, id) >= 0 do return {.Room, id, -1}
	return{}}
level_selection_position :: proc(
	doc: ^Level_Document,
	selection: Editor_Selection,
) -> (
	Vec2,
	bool,
) {#partial switch selection.kind {case .Room, .Edge, .Vertex:
		index := level_room_index(doc, selection.entity_id)
		if index >= 0 do return level_room_center(&doc.rooms[index]), true; case .Foundation:
		index := level_foundation_index(doc, selection.entity_id)
		if index >= 0 &&
		   len(doc.foundations[index].points) >
			   0 {center := Vec2{}; for p in doc.foundations[index].points {center.x += p.x; center.y += p.y}; return {center.x / f32(len(doc.foundations[index].points)), center.y / f32(len(doc.foundations[index].points))}, true}; case .Opening:
		index := level_opening_index(doc, selection.entity_id)
		if index >=
		   0 {opening := doc.openings[index]; path_index := level_path_index(doc, opening.host_path); if path_index >= 0 && opening.segment >= 0 && opening.segment < len(doc.paths[path_index].points) - 1 {a, b := doc.paths[path_index].points[opening.segment], doc.paths[path_index].points[opening.segment + 1]; return {a.x + (b.x - a.x) * opening.position, a.y + (b.y - a.y) * opening.position}, true}}; case .Object:
		index := level_object_index(doc, selection.entity_id)
		if index >= 0 do return doc.objects[index].position, true; case .Light:
		index := level_light_index(doc, selection.entity_id)
		if index >= 0 do return doc.lights[index].position, true; case .Marker:
		index := level_marker_index(doc, selection.entity_id)
		if index >= 0 do return doc.markers[index].position, true; case .Path:
		index := level_path_index(doc, selection.entity_id)
		if index >= 0 &&
		   len(doc.paths[index].points) >
			   0 {center := Vec2{}; for p in doc.paths[index].points {center.x += p.x; center.y += p.y}; return {center.x / f32(len(doc.paths[index].points)), center.y / f32(len(doc.paths[index].points))}, true}; case .Water:
		index := level_water_index(doc, selection.entity_id)
		if index >= 0 &&
		   len(doc.waters[index].points) >
			   0 {center := Vec2{}; for p in doc.waters[index].points {center.x += p.x; center.y += p.y}; return {center.x / f32(len(doc.waters[index].points)), center.y / f32(len(doc.waters[index].points))}, true}; case .Vertical_Link:
		index := level_vertical_link_index(doc, selection.entity_id)
		if index >=
		   0 {link := doc.vertical_links[index]; return {(link.start.x + link.finish.x) * .5, (link.start.y + link.finish.y) * .5}, true}}; return {}, false}
level_next_id :: proc(prefix: string, revision: u64) -> string {return fmt.tprintf(
		"%s_%d",
		prefix,
		revision + 1,
	)}
level_snap_point :: proc(
	doc: ^Level_Document,
	p: Vec2,
	fine := false,
) -> Vec2 {if editor_state.snap_mode == .Off || editor_state.snap_suspended do return p; step :=
		editor_state.snap_mode == .Fine ? doc.fine_snap : doc.default_snap
	if step <= 0 do return p
	return{f32(math.round(f64(p.x / step))) * step, f32(math.round(f64(p.y / step))) * step}}
level_terrain_sample :: proc(doc: ^Level_Document, x, y: int) -> f32 {sample_x, sample_y :=
		clamp(x, 0, doc.width), clamp(y, 0, doc.height)
	index := sample_y * (doc.width + 1) + sample_x
	if index < 0 || index >= len(doc.terrain) do return 0
	return doc.terrain[index]}
level_terrain_height :: proc(doc: ^Level_Document, p: Vec2) -> f32 {
	x := clamp(
		p.x,
		0,
		f32(doc.width),
	); y := clamp(p.y, 0, f32(doc.height)); x0, y0 := int(math.floor(f64(x))), int(math.floor(f64(y))); x1, y1 := min(x0 + 1, doc.width), min(y0 + 1, doc.height); tx, ty := x - f32(x0), y - f32(y0)
	a :=
		level_terrain_sample(doc, x0, y0) +
		(level_terrain_sample(doc, x1, y0) - level_terrain_sample(doc, x0, y0)) * tx
	b :=
		level_terrain_sample(doc, x0, y1) +
		(level_terrain_sample(doc, x1, y1) - level_terrain_sample(doc, x0, y1)) * tx
	return a + (b - a) * ty
}
level_terrain_supports_position :: proc(
	doc: ^Level_Document,
	p: Vec2,
	story: int,
) -> bool {if story != 0 do return false; for room in doc.rooms do if room.story == story && room.exterior && level_point_in_polygon(p, room.points[:]) do return true
	return false}

level_segment_distance :: proc(point, a, b: Vec2) -> (distance, t: f32) {dx, dy :=
		b.x - a.x, b.y - a.y
	length_sq := dx * dx + dy * dy
	if length_sq <= .0001 {ex, ey := point.x - a.x, point.y - a.y; return f32(
				math.sqrt(f64(ex * ex + ey * ey)),
			),
			0}
	t = clamp(((point.x - a.x) * dx + (point.y - a.y) * dy) / length_sq, 0, 1)
	ex, ey := point.x - (a.x + dx * t), point.y - (a.y + dy * t)
	return f32(math.sqrt(f64(ex * ex + ey * ey))), t}

level_apply_raw :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> (
	inverse: Level_Command,
	ok: bool,
) {
	preview := level_command_preview(
		doc,
		command,
	); if preview.state == .Blocked do return {}, false
	#partial switch command.kind {
	case .Set_Metadata:
		if command.metadata_id == "" || command.metadata_width <= 0 || command.metadata_height <= 0 do return {}, false
		old := Level_Command {
			kind            = .Set_Metadata,
			metadata_id     = doc.id,
			metadata_name   = doc.name,
			metadata_width  = doc.width,
			metadata_height = doc.height,
		}
		doc.id = command.metadata_id
		doc.name = command.metadata_name
		if doc.width != command.metadata_width ||
		   doc.height !=
			   command.metadata_height {doc.width = command.metadata_width; doc.height = command.metadata_height
			delete(doc.terrain)
			doc.terrain = make([dynamic]f32, (doc.width + 1) * (doc.height + 1))}
		return old, true
	case .Add_Story:
		if !graph_valid_id(command.story.id) || len(doc.stories) >= doc.story_limit do return {}, false
		for story in doc.stories do if story.id == command.story.id do return {}, false
		append(&doc.stories, command.story)
		return Level_Command{kind = .Delete_Story, entity_id = command.story.id}, true
	case .Update_Story:
		index := -1; for story, i in doc.stories do if story.id == command.entity_id do index = i
		if index < 0 do return {}, false
		old := doc.stories[index]
		doc.stories[index] = command.story
		for &room in doc.rooms do if room.story == index do room.story = index
		return Level_Command{kind = .Update_Story, entity_id = command.story.id, story = old}, true
	case .Delete_Story:
		index := -1; for story, i in doc.stories do if story.id == command.entity_id do index = i
		if index < 0 || len(doc.stories) <= 1 do return {}, false
		for room in doc.rooms do if room.story == index do return {}, false
		for object in doc.objects do if object.story == index do return {}, false
		for marker in doc.markers do if marker.story == index do return {}, false
		old := doc.stories[index]
		ordered_remove(&doc.stories, index)
		for &room in doc.rooms do if room.story > index do room.story -= 1
		for &object in doc.objects do if object.story > index do object.story -= 1
		for &marker in doc.markers do if marker.story > index do marker.story -= 1
		return Level_Command{kind = .Add_Story, story = old}, true
	case .Reorder_Story:
		if command.from < 0 || command.to < 0 || command.from >= len(doc.stories) || command.to >= len(doc.stories) do return {}, false
		item := doc.stories[command.from]
		if command.from <
		   command.to {for i in command.from ..< command.to do doc.stories[i] = doc.stories[i + 1]} else {for i := command.from; i > command.to; i -= 1 do doc.stories[i] = doc.stories[i - 1]}
		doc.stories[command.to] = item
		for &room in doc.rooms {if room.story == command.from do room.story = command.to
			else if command.from < command.to && room.story > command.from && room.story <= command.to do room.story -= 1
			else if command.from > command.to && room.story >= command.to && room.story < command.from do room.story += 1}
		for &object in doc.objects {if object.story == command.from do object.story = command.to
			else if command.from < command.to && object.story > command.from && object.story <= command.to do object.story -= 1
			else if command.from > command.to && object.story >= command.to && object.story < command.from do object.story += 1}
		for &marker in doc.markers {if marker.story == command.from do marker.story = command.to
			else if command.from < command.to && marker.story > command.from && marker.story <= command.to do marker.story -= 1
			else if command.from > command.to && marker.story >= command.to && marker.story < command.from do marker.story += 1}
		return Level_Command{kind = .Reorder_Story, from = command.to, to = command.from}, true
	case .Set_Story_Height:
		index := -1
		for story, i in doc.stories do if story.id == command.entity_id {index = i; break}
		if index < 0 || command.value < 2.2 || command.value > 6 do return {}, false
		old := doc.stories[index].wall_height
		delta := command.value - old
		base := doc.stories[index].base_elevation
		doc.stories[index].wall_height = command.value
		for &story, i in doc.stories do if i != index && story.base_elevation > base do story.base_elevation += delta
		return Level_Command{kind = .Set_Story_Height, entity_id = command.entity_id, value = old},
			true
	case .Create_Foundation:
		id := command.entity_id; if id == "" do id = level_next_id("foundation", doc.revision)
		points := make([dynamic]Vec2, 0, command.point_count)
		for i in 0 ..< command.point_count do append(&points, level_snap_point(doc, command.points[i], true))
		kind := Level_Foundation_Kind(
			clamp(int(command.c.x), 0, int(Level_Foundation_Kind.Basement)),
		)
		story := -1
		if kind ==
		   .Basement {story = level_basement_story(doc); if story < 0 {if len(doc.stories) >= doc.story_limit do return {}, false
				story = len(doc.stories)
				append(
					&doc.stories,
					Level_Story {
						id = "basement",
						name = "Basement",
						base_elevation = -max(command.c.y, 1.8),
						wall_height = max(command.c.y, 2.4),
					},
				)}}
		append(
			&doc.foundations,
			Level_Foundation {
				id = id,
				kind = kind,
				story = story,
				points = points,
				elevation = command.value,
				depth = command.c.y,
			},
		)
		return Level_Command{kind = .Delete_Foundation, entity_id = id}, true
	case .Set_Foundation:
		index := level_foundation_index(doc, command.entity_id); if index < 0 do return {}, false
		foundation := &doc.foundations[index]
		old := Level_Command {
			kind      = .Set_Foundation,
			entity_id = foundation.id,
			value     = foundation.elevation,
			c         = {f32(foundation.kind), foundation.depth},
		}
		foundation.elevation = command.value
		foundation.depth = command.c.y
		if foundation.kind == .Basement &&
		   foundation.story >= 0 &&
		   foundation.story <
			   len(doc.stories) {doc.stories[foundation.story].base_elevation = -foundation.depth
			doc.stories[foundation.story].wall_height = max(foundation.depth, 2.4)}
		return old, true
	case .Move_Foundation_Point:
		index := level_foundation_index(doc, command.entity_id); point_index := int(command.value)
		if index < 0 || point_index < 0 || point_index >= len(doc.foundations[index].points) do return {}, false
		old := doc.foundations[index].points[point_index]
		doc.foundations[index].points[point_index] = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Move_Foundation_Point,
				entity_id = command.entity_id,
				a = old,
				value = command.value,
			},
			true
	case .Delete_Foundation:
		index := level_foundation_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.foundations[index]
		ordered_remove(&doc.foundations, index)
		inverse := Level_Command {
			kind        = .Create_Foundation,
			entity_id   = old.id,
			value       = old.elevation,
			c           = {f32(old.kind), old.depth},
			point_count = min(len(old.points), 32),
		}
		for point, i in old.points {if i >= len(inverse.points) do break; inverse.points[i] = point}
		return inverse, true
	case .Create_Room_Polygon:
		exterior := command.destination == "patio"; id := command.entity_id
		if id == "" do id = level_next_id(exterior ? "patio" : "room", doc.revision)
		points := make([dynamic]Vec2, 0, command.point_count)
		for i in 0 ..< command.point_count do append(&points, level_snap_point(doc, command.points[i], true))
		append(
			&doc.rooms,
			Level_Room {
				id = id,
				name = exterior ? "New Patio" : "New Room",
				story = doc.active_story,
				points = points,
				floor_material = catalog_resolve_id(command.material),
				wall_material = catalog_resolve_id(command.material),
				ceiling_style = exterior ? "open" : "flat",
				floor_tint = {255, 255, 255, 255},
				wall_tint = {255, 255, 255, 255},
				exterior = exterior,
			},
		)
		return Level_Command{kind = .Delete_Room, entity_id = id}, true
	case .Split_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		first, second: [34]Vec2
		first_count, second_count := 0, 0
		if !level_split_polygon(doc.rooms[index].points[:], level_snap_point(doc, command.a, true), level_snap_point(doc, command.b, true), &first, &first_count, &second, &second_count) do return {}, false
		original := doc.rooms[index]
		keep_first :=
			math.abs(level_polygon_area(first[:first_count])) >=
			math.abs(level_polygon_area(second[:second_count]))
		kept := keep_first ? first[:first_count] : second[:second_count]
		created := keep_first ? second[:second_count] : first[:first_count]
		doc.rooms[index].points = make([dynamic]Vec2, 0, len(kept))
		for point in kept do append(&doc.rooms[index].points, point)
		copy_room := original
		copy_room.id = command.destination
		if copy_room.id == "" do copy_room.id = level_next_id("room_split", doc.revision)
		copy_room.name = fmt.tprintf("%s B", original.name)
		copy_room.points = make([dynamic]Vec2, 0, len(created))
		for point in created do append(&copy_room.points, point)
		append(&doc.rooms, copy_room)
		wall_points := make([dynamic]Vec2, 0, 2)
		append(
			&wall_points,
			level_snap_point(doc, command.a, true),
			level_snap_point(doc, command.b, true),
		)
		wall_id := command.material
		if wall_id == "" do wall_id = level_next_id("wall", doc.revision)
		append(
			&doc.paths,
			Level_Path {
				id = wall_id,
				story = original.story,
				kind = .Wall,
				points = wall_points,
				material = "structure",
				width = HOUSE_WALL_THICKNESS,
			},
		)
		return Level_Command{kind = .Delete_Room, entity_id = copy_room.id}, true
	case .Merge_Rooms:
		first_index, second_index :=
			level_room_index(doc, command.entity_id), level_room_index(doc, command.destination)
		if first_index < 0 || second_index < 0 || first_index == second_index do return {}, false
		merged: [64]Vec2
		merged_count := 0
		shared_start, shared_finish := Vec2{}, Vec2{}
		if !level_merge_polygons(doc.rooms[first_index].points[:], doc.rooms[second_index].points[:], &merged, &merged_count, &shared_start, &shared_finish) do return {}, false
		doc.rooms[first_index].points = make([dynamic]Vec2, 0, merged_count)
		for point in merged[:merged_count] do append(&doc.rooms[first_index].points, point)
		ordered_remove(&doc.rooms, second_index)
		divider_id := ""
		for path in doc.paths {if path.story != doc.rooms[first_index - (second_index < first_index ? 1 : 0)].story || path.kind != .Wall || len(path.points) != 2 do continue
			if level_points_near(path.points[0], shared_start) &&
				   level_points_near(path.points[1], shared_finish) ||
			   level_points_near(path.points[1], shared_start) &&
				   level_points_near(path.points[0], shared_finish) {divider_id = path.id; break}}
		if divider_id !=
		   "" {i := 0; for i < len(doc.openings) {if doc.openings[i].host_path == divider_id {ordered_remove(&doc.openings, i)} else {i += 1}}
			path_index := level_path_index(doc, divider_id)
			if path_index >= 0 do ordered_remove(&doc.paths, path_index)}
		i := 0
		for i <
		    len(
			    doc.roofs,
		    ) {if doc.roofs[i].room_id == command.destination {ordered_remove(&doc.roofs, i)} else {i += 1}}
		return {}, true
	case .Insert_Room_Vertex:
		index := level_room_index(doc, command.entity_id); handle := int(command.value)
		if index < 0 || handle < 0 || handle >= len(doc.rooms[index].points) do return {}, false
		target := handle + 1
		append(&doc.rooms[index].points, Vec2{})
		for i := len(doc.rooms[index].points) - 1; i > target; i -= 1 do doc.rooms[index].points[i] = doc.rooms[index].points[i - 1]
		doc.rooms[index].points[target] = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Remove_Room_Vertex,
				entity_id = command.entity_id,
				value = f32(target),
			},
			true
	case .Remove_Room_Vertex:
		index := level_room_index(doc, command.entity_id); handle := int(command.value)
		if index < 0 || handle < 0 || handle >= len(doc.rooms[index].points) || len(doc.rooms[index].points) <= 3 do return {}, false
		old := doc.rooms[index].points[handle]
		ordered_remove(&doc.rooms[index].points, handle)
		previous := (handle - 1 + len(doc.rooms[index].points)) % len(doc.rooms[index].points)
		return Level_Command {
				kind = .Insert_Room_Vertex,
				entity_id = command.entity_id,
				a = old,
				value = f32(previous),
			},
			true
	case .Create_Room:
		exterior := command.destination == "patio"; id := command.entity_id
		if id == "" do id = level_next_id(exterior ? "patio" : "room", doc.revision)
		a, b := level_snap_point(doc, command.a), level_snap_point(doc, command.b)
		points := make([dynamic]Vec2, 0, 4)
		append(
			&points,
			Vec2{min(a.x, b.x), min(a.y, b.y)},
			Vec2{max(a.x, b.x), min(a.y, b.y)},
			Vec2{max(a.x, b.x), max(a.y, b.y)},
			Vec2{min(a.x, b.x), max(a.y, b.y)},
		)
		append(
			&doc.rooms,
			Level_Room {
				id = id,
				name = exterior ? "New Patio" : "New Room",
				story = doc.active_story,
				points = points,
				floor_material = catalog_resolve_id(command.material),
				wall_material = catalog_resolve_id(command.material),
				ceiling_style = exterior ? "open" : "flat",
				floor_tint = {255, 255, 255, 255},
				wall_tint = {255, 255, 255, 255},
				exterior = exterior,
			},
		)
		return Level_Command{kind = .Delete_Room, entity_id = id}, true
	case .Delete_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		room := doc.rooms[index]
		if len(room.points) < 2 do return {}, false
		a := room.points[0]
		b := room.points[2]
		ordered_remove(&doc.rooms, index)
		return Level_Command {
				kind = .Create_Room,
				entity_id = room.id,
				a = a,
				b = b,
				material = room.floor_material,
				destination = room.exterior ? "patio" : "",
			},
			true
	case .Move_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		for &p in doc.rooms[index].points {p.x += command.a.x; p.y += command.a.y}
		return Level_Command {
				kind = .Move_Room,
				entity_id = command.entity_id,
				a = {-command.a.x, -command.a.y},
			},
			true
	case .Duplicate_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		source := doc.rooms[index]
		copy_room := source
		copy_room.id = command.material
		if copy_room.id == "" do copy_room.id = level_next_id("room_copy", doc.revision)
		copy_room.name = fmt.tprintf("%s Copy", source.name)
		copy_room.points = make([dynamic]Vec2, 0, len(source.points))
		for point in source.points do append(&copy_room.points, level_snap_point(doc, {point.x + command.a.x, point.y + command.a.y}, true))
		append(&doc.rooms, copy_room)
		return Level_Command{kind = .Delete_Room, entity_id = copy_room.id}, true
	case .Rotate_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		center := level_room_center(&doc.rooms[index])
		for &point in doc.rooms[index].points do point = level_snap_point(doc, level_rotated_point(point, center, command.value), true)
		return Level_Command {
				kind = .Rotate_Room,
				entity_id = command.entity_id,
				value = -command.value,
			},
			true
	case .Move_Room_Vertex:
		index := level_room_index(doc, command.entity_id); handle := int(command.value)
		if index < 0 || handle < 0 || handle >= len(doc.rooms[index].points) do return {}, false
		old := doc.rooms[index].points[handle]
		doc.rooms[index].points[handle] = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Move_Room_Vertex,
				entity_id = command.entity_id,
				a = old,
				value = command.value,
			},
			true
	case .Move_Room_Edge:
		index := level_room_index(doc, command.entity_id); handle := int(command.value)
		if index < 0 || handle < 0 || handle >= len(doc.rooms[index].points) do return {}, false
		next := (handle + 1) % len(doc.rooms[index].points)
		doc.rooms[index].points[handle].x += command.a.x
		doc.rooms[index].points[handle].y += command.a.y
		doc.rooms[index].points[next].x += command.a.x
		doc.rooms[index].points[next].y += command.a.y
		return Level_Command {
				kind = .Move_Room_Edge,
				entity_id = command.entity_id,
				a = {-command.a.x, -command.a.y},
				value = command.value,
			},
			true
	case .Set_Platform:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.rooms[index].platform_height
		doc.rooms[index].platform_height = command.value
		return Level_Command{kind = .Set_Platform, entity_id = command.entity_id, value = old},
			true
	case .Add_Path:
		kind := Level_Path_Kind(clamp(int(command.c.x), 0, int(Level_Path_Kind.Footpath)))
		id := command.entity_id
		if id == "" do id = level_next_id(kind == .Road ? "road" : kind == .Footpath ? "footpath" : "wall", doc.revision)
		count := command.point_count
		if count == 0 do count = 2
		points := make([dynamic]Vec2, 0, count)
		for i in 0 ..< count {p := count == 2 && command.point_count == 0 ? (i == 0 ? command.a : command.b) : command.points[i]
			append(&points, level_snap_point(doc, p, true))}
		width := command.value
		if width <= 0 do width = kind == .Road ? 4 : kind == .Footpath ? 1.2 : HOUSE_WALL_THICKNESS
		append(
			&doc.paths,
			Level_Path {
				id = id,
				story = doc.active_story,
				kind = kind,
				points = points,
				material = command.material,
				width = width,
			},
		)
		return Level_Command{kind = .Delete_Object, entity_id = id, material = "path"}, true
	case .Set_Path:
		index := level_path_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.paths[index].width
		doc.paths[index].width = command.value
		return Level_Command{kind = .Set_Path, entity_id = command.entity_id, value = old}, true
	case .Move_Path_Point:
		index := level_path_index(doc, command.entity_id); point_index := int(command.value)
		if index < 0 || point_index < 0 || point_index >= len(doc.paths[index].points) do return {}, false
		old := doc.paths[index].points[point_index]
		doc.paths[index].points[point_index] = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Move_Path_Point,
				entity_id = command.entity_id,
				a = old,
				value = command.value,
			},
			true
	case .Delete_Object:
		if command.material == "path" {index := level_path_index(doc, command.entity_id)
			if index < 0 do return {}, false
			path := doc.paths[index]
			ordered_remove(&doc.paths, index)
			inverse := Level_Command {
				kind        = .Add_Path,
				entity_id   = path.id,
				material    = path.material,
				c           = {f32(path.kind), 0},
				value       = path.width,
				point_count = min(len(path.points), 32),
			}
			for p, i in path.points {if i >= len(inverse.points) do break; inverse.points[i] = p}
			return inverse, true}
		index := level_object_index(doc, command.entity_id)
		if index < 0 do return {}, false
		object := doc.objects[index]
		for &child in doc.objects do if child.support_id == object.id {child.support_id = ""; child.elevation = 0}
		ordered_remove(&doc.objects, index)
		return Level_Command {
				kind = .Place_Object,
				entity_id = object.id,
				a = object.position,
				c = {object.elevation, 0},
				value = object.rotation,
				material = object.catalog_id,
				destination = object.support_id,
			},
			true
	case .Add_Marker:
		kind := Level_Marker_Kind(clamp(int(command.c.y), 0, int(Level_Marker_Kind.Staging)))
		id := command.entity_id
		if id == "" do id = level_next_id(level_marker_kind_name(kind), doc.revision)
		story := doc.active_story
		if command.value >= 0 do story = int(command.value)
		append(
			&doc.markers,
			Level_Marker {
				id = id,
				reference = command.material,
				destination = command.destination,
				kind = kind,
				story = story,
				position = level_snap_point(doc, command.a, true),
				radius = command.b.x,
				facing = command.b.y,
				camera_height = command.c.x,
			},
		)
		return Level_Command{kind = .Delete_Marker, entity_id = id}, true
	case .Set_Marker:
		index := level_marker_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.markers[index]
		new_id := command.interaction_prompt
		if new_id == "" do new_id = old.id
		doc.markers[index].id = new_id
		doc.markers[index].reference = command.material
		doc.markers[index].destination = command.destination
		doc.markers[index].kind = Level_Marker_Kind(
			clamp(int(command.c.y), 0, int(Level_Marker_Kind.Staging)),
		)
		doc.markers[index].position = level_snap_point(doc, command.a, true)
		doc.markers[index].radius = command.b.x
		doc.markers[index].facing = command.b.y
		doc.markers[index].camera_height = command.c.x
		if new_id !=
		   old.id {for &marker in doc.markers do if marker.kind == .Transition && marker.destination == old.id do marker.destination = new_id}
		return Level_Command {
				kind = .Set_Marker,
				entity_id = new_id,
				interaction_prompt = old.id,
				a = old.position,
				b = {old.radius, old.facing},
				c = {old.camera_height, f32(old.kind)},
				material = old.reference,
				destination = old.destination,
				value = f32(old.story),
			},
			true
	case .Delete_Marker:
		index := level_marker_index(doc, command.entity_id); if index < 0 do return {}, false
		marker := doc.markers[index]
		ordered_remove(&doc.markers, index)
		return Level_Command {
				kind = .Add_Marker,
				entity_id = marker.id,
				a = marker.position,
				b = {marker.radius, marker.facing},
				c = {marker.camera_height, f32(marker.kind)},
				material = marker.reference,
				destination = marker.destination,
				value = f32(marker.story),
			},
			true
	case .Place_Object:
		id := command.entity_id; if id == "" do id = level_next_id("object", doc.revision)
		append(
			&doc.objects,
			Level_Object {
				id = id,
				catalog_id = catalog_resolve_id(command.material),
				support_id = command.destination,
				story = doc.active_story,
				position = level_snap_point(doc, command.a, true),
				elevation = command.c.x,
				rotation = command.value,
				tint = {255, 255, 255, 255},
				bark_tint = {255, 255, 255, 255},
				foliage_tint = {255, 255, 255, 255},
			},
		)
		return {}, true
	case .Duplicate_Object:
		index := level_object_index(doc, command.entity_id); if index < 0 do return {}, false
		source := doc.objects[index]
		copy_object := source
		copy_object.id = command.material
		if copy_object.id == "" do copy_object.id = level_next_id("object_copy", doc.revision)
		copy_object.position = level_snap_point(
			doc,
			{source.position.x + command.a.x, source.position.y + command.a.y},
			true,
		)
		append(&doc.objects, copy_object)
		return Level_Command {
				kind = .Delete_Object,
				entity_id = copy_object.id,
				material = "object",
			},
			true
	case .Move_Object:
		index := level_object_index(doc, command.entity_id); if index < 0 do return {}, false
		old_position := doc.objects[index].position
		new_position := level_snap_point(doc, command.a, true)
		delta := Vec2{new_position.x - old_position.x, new_position.y - old_position.y}
		doc.objects[index].position = new_position
		doc.objects[index].rotation = command.value
		support_id, support_height, supported := level_object_support_at(
			doc,
			new_position,
			doc.objects[index].catalog_id,
		)
		if supported && support_id != command.entity_id {doc.objects[index].support_id = support_id
			doc.objects[index].elevation =
				support_height} else if doc.objects[index].support_id != "" {host_index := level_object_index(doc, doc.objects[index].support_id)
			if host_index <
			   0 {doc.objects[index].support_id = ""; doc.objects[index].elevation = 0} else {host_entry, host_ok := catalog_object_entry(doc.objects[host_index].catalog_id)
				radius := host_ok ? max(host_entry.footprint, .2) : f32(.35)
				dx, dy :=
					new_position.x -
					doc.objects[host_index].position.x,
					new_position.y -
					doc.objects[host_index].position.y
				if dx * dx + dy * dy > radius * radius {doc.objects[index].support_id = ""
					doc.objects[index].elevation = 0}}}
		for &child in doc.objects do if child.support_id == command.entity_id {child.position.x += delta.x; child.position.y += delta.y}
		return {}, true
	case .Set_Object_Elevation:
		index := level_object_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.objects[index].elevation
		delta := command.value - old
		doc.objects[index].elevation = command.value
		for &child in doc.objects do if child.support_id == command.entity_id do child.elevation += delta
		return Level_Command {
				kind = .Set_Object_Elevation,
				entity_id = command.entity_id,
				value = old,
			},
			true
	case .Set_Object_Color:
		index := level_object_index(doc, command.entity_id); if index < 0 do return {}, false
		if command.destination ==
		   "bark" {old := doc.objects[index].bark_tint; doc.objects[index].bark_tint = command.color
			return Level_Command {
					kind = .Set_Object_Color,
					entity_id = command.entity_id,
					destination = "bark",
					color = old,
				},
				true}
		old := doc.objects[index].foliage_tint
		doc.objects[index].foliage_tint = command.color
		return Level_Command {
				kind = .Set_Object_Color,
				entity_id = command.entity_id,
				destination = "foliage",
				color = old,
			},
			true
	case .Add_Light:
		id := command.entity_id; if id == "" do id = level_next_id("light", doc.revision)
		story := doc.active_story
		if command.value >= 0 do story = int(command.value)
		kind := Level_Light_Kind(clamp(int(command.c.y), 0, int(Level_Light_Kind.Area)))
		color := command.color
		if color[3] == 0 do color = {255, 236, 196, 255}
		cone := command.points[0].x
		if cone <= 0 do cone = 45
		append(
			&doc.lights,
			Level_Light {
				id = id,
				kind = kind,
				story = story,
				position = level_snap_point(doc, command.a, true),
				elevation = command.c.x,
				range = command.b.x,
				intensity = command.b.y,
				facing = command.points[0].y,
				cone_angle = cone,
				color = color,
			},
		)
		return Level_Command{kind = .Delete_Light, entity_id = id}, true
	case .Set_Light:
		index := level_light_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.lights[index]
		color := command.color
		if color[3] == 0 do color = old.color
		doc.lights[index].kind = Level_Light_Kind(
			clamp(int(command.c.y), 0, int(Level_Light_Kind.Area)),
		)
		doc.lights[index].position = level_snap_point(doc, command.a, true)
		doc.lights[index].elevation = command.c.x
		doc.lights[index].range = command.b.x
		doc.lights[index].intensity = command.b.y
		doc.lights[index].facing = command.value
		doc.lights[index].cone_angle = command.points[0].x
		doc.lights[index].color = color
		inverse := Level_Command {
			kind      = .Set_Light,
			entity_id = old.id,
			a         = old.position,
			b         = {old.range, old.intensity},
			c         = {old.elevation, f32(old.kind)},
			value     = old.facing,
			color     = old.color,
		}
		inverse.points[0] = {old.cone_angle, 0}
		return inverse, true
	case .Delete_Light:
		index := level_light_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.lights[index]
		ordered_remove(&doc.lights, index)
		inverse := Level_Command {
			kind      = .Add_Light,
			entity_id = old.id,
			a         = old.position,
			b         = {old.range, old.intensity},
			c         = {old.elevation, f32(old.kind)},
			value     = f32(old.story),
			color     = old.color,
		}
		inverse.points[0] = {old.cone_angle, old.facing}
		return inverse, true
	case .Paint_Floor:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		doc.rooms[index].floor_material = catalog_resolve_id(command.material)
		return {}, true
	case .Paint_Walls:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		doc.rooms[index].wall_material = catalog_resolve_id(command.material)
		return {}, true
	case .Paint_Room:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		if command.material ==
		   "__grounds__" {doc.rooms[index].exterior = true} else if command.material == "__interior__" {doc.rooms[index].exterior = false} else {doc.rooms[index].floor_material = catalog_resolve_id(command.material); doc.rooms[index].wall_material = catalog_resolve_id(command.material)}
		return {}, true
	case .Set_Room_Tint:
		index := level_room_index(doc, command.entity_id); if index < 0 do return {}, false
		if command.destination ==
		   "walls" {old := doc.rooms[index].wall_tint; doc.rooms[index].wall_tint = command.color
			return Level_Command {
					kind = .Set_Room_Tint,
					entity_id = command.entity_id,
					destination = "walls",
					color = old,
				},
				true}
		old := doc.rooms[index].floor_tint
		doc.rooms[index].floor_tint = command.color
		return Level_Command {
				kind = .Set_Room_Tint,
				entity_id = command.entity_id,
				destination = "floor",
				color = old,
			},
			true
	case .Add_Opening:
		path_index := level_path_index(doc, command.material)
		if path_index < 0 do return {}, false
		id := command.entity_id
		if id == "" do id = level_next_id("opening", doc.revision)
		kind := Level_Opening_Kind(clamp(int(command.b.x), 0, int(Level_Opening_Kind.Gate)))
		segment := int(command.value)
		a, b := doc.paths[path_index].points[segment], doc.paths[path_index].points[segment + 1]
		length := f32(math.sqrt(f64((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))))
		default_width :=
			kind == .Window ? f32(1.6) : kind == .Arch ? f32(1.5) : kind == .Gate ? f32(1.4) : f32(1.2)
		default_height :=
			kind == .Window ? f32(1.4) : kind == .Arch ? f32(2.2) : kind == .Gate ? f32(1.5) : f32(2.1)
		width := command.b.y > 0 ? command.b.y : default_width
		height := command.c.y > 0 ? command.c.y : default_height
		sill_height := command.points[0].x
		if kind == .Window && sill_height <= 0 do sill_height = .72
		window_style := Window_Style(
			clamp(int(command.points[0].y), 0, int(Window_Style.Double_Hung)),
		)
		door_style := Door_Style(clamp(int(command.points[2].x), 0, int(Door_Style.Sliding)))
		window_flipped := command.points[1].x > 0
		window_hinge_right := command.points[1].y > 0
		position := command.c.x
		if position <= 0 do position = .5
		end_clearance := level_opening_end_clearance(kind)
		position = clamp(
			position,
			(width * .5 + end_clearance) / length,
			1 - (width * .5 + end_clearance) / length,
		)
		behavior := command.interaction
		if kind == .Door && behavior == .None do behavior = .Door
		interaction_range := command.interaction_range
		if interaction_range <= 0 do interaction_range = 1.8
		append(
			&doc.openings,
			Level_Opening {
				id = id,
				host_path = command.material,
				kind = kind,
				door_material = door_material_from_name(command.destination),
				door_style = door_style,
				window_style = window_style,
				window_flipped = window_flipped,
				window_hinge_right = window_hinge_right,
				interaction = behavior,
				interaction_prompt = command.interaction_prompt,
				interaction_range = interaction_range,
				initially_active = command.initially_active,
				locked = command.locked,
				powered = true,
				segment = segment,
				position = position,
				width = width,
				height = height,
				sill_height = sill_height,
			},
		)
		return Level_Command{kind = .Delete_Opening, entity_id = id}, true
	case .Set_Opening:
		index := level_opening_index(doc, command.entity_id)
		path_index := level_path_index(doc, command.material)
		if index < 0 || path_index < 0 do return {}, false
		old := doc.openings[index]
		kind := Level_Opening_Kind(clamp(int(command.b.x), 0, int(Level_Opening_Kind.Gate)))
		segment := int(command.value)
		a, b := doc.paths[path_index].points[segment], doc.paths[path_index].points[segment + 1]
		length := f32(math.sqrt(f64((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y))))
		width := command.b.y
		height := command.c.y
		sill_height := command.points[0].x
		if kind == .Window && sill_height <= 0 do sill_height = .72
		window_style := Window_Style(
			clamp(int(command.points[0].y), 0, int(Window_Style.Double_Hung)),
		)
		door_style := Door_Style(clamp(int(command.points[2].x), 0, int(Door_Style.Sliding)))
		window_flipped := command.points[1].x > 0
		window_hinge_right := command.points[1].y > 0
		end_clearance := level_opening_end_clearance(kind)
		position := clamp(
			command.c.x,
			(width * .5 + end_clearance) / length,
			1 - (width * .5 + end_clearance) / length,
		)
		door_material := old.door_material
		if command.destination != "" do door_material = door_material_from_name(command.destination)
		doc.openings[index] = {
			id                 = old.id,
			host_path          = command.material,
			kind               = kind,
			door_material      = door_material,
			door_style         = door_style,
			window_style       = window_style,
			window_flipped     = window_flipped,
			window_hinge_right = window_hinge_right,
			interaction        = old.interaction,
			interaction_prompt = old.interaction_prompt,
			interaction_range  = old.interaction_range,
			initially_active   = old.initially_active,
			locked             = old.locked,
			powered            = old.powered,
			segment            = segment,
			position           = position,
			width              = width,
			height             = height,
			sill_height        = sill_height,
		}
		inverse := Level_Command {
			kind        = .Set_Opening,
			entity_id   = old.id,
			material    = old.host_path,
			destination = door_material_name(old.door_material),
			value       = f32(old.segment),
			b           = {f32(old.kind), old.width},
			c           = {old.position, old.height},
		}
		inverse.points[0] = {old.sill_height, f32(old.window_style)}
		inverse.points[1] = {old.window_flipped ? 1 : 0, old.window_hinge_right ? 1 : 0}
		inverse.points[2].x = f32(old.door_style)
		return inverse, true
	case .Delete_Opening:
		index := level_opening_index(doc, command.entity_id); if index < 0 do return {}, false
		opening := doc.openings[index]
		ordered_remove(&doc.openings, index)
		inverse := Level_Command {
			kind               = .Add_Opening,
			entity_id          = opening.id,
			material           = opening.host_path,
			destination        = door_material_name(opening.door_material),
			interaction        = opening.interaction,
			interaction_prompt = opening.interaction_prompt,
			interaction_range  = opening.interaction_range,
			initially_active   = opening.initially_active,
			locked             = opening.locked,
			powered            = opening.powered,
			value              = f32(opening.segment),
			b                  = {f32(opening.kind), opening.width},
			c                  = {opening.position, opening.height},
		}
		inverse.points[0] = {opening.sill_height, f32(opening.window_style)}
		inverse.points[1] = {opening.window_flipped ? 1 : 0, opening.window_hinge_right ? 1 : 0}
		inverse.points[2].x = f32(opening.door_style)
		return inverse, true
	case .Set_Interaction:
		opening_index := level_opening_index(doc, command.entity_id)
		if opening_index >= 0 {old := doc.openings[opening_index]
			target := &doc.openings[opening_index]
			target.interaction = command.interaction
			target.interaction_prompt = command.interaction_prompt
			target.condition_id = command.condition_id
			target.focused_scene = command.focused_scene
			target.effect_id_count = min(command.effect_id_count, len(target.effect_ids))
			for effect_i in 0 ..< target.effect_id_count do target.effect_ids[effect_i] = command.effect_ids[effect_i]
			target.interaction_range = command.interaction_range
			target.initially_active = command.initially_active
			target.locked = command.locked
			target.powered = command.powered
			inverse := Level_Command {
				kind               = .Set_Interaction,
				entity_id          = old.id,
				interaction        = old.interaction,
				interaction_prompt = old.interaction_prompt,
				condition_id       = old.condition_id,
				focused_scene      = old.focused_scene,
				effect_id_count    = old.effect_id_count,
				interaction_range  = old.interaction_range,
				initially_active   = old.initially_active,
				locked             = old.locked,
				powered            = old.powered,
			}
			copy(inverse.effect_ids[:old.effect_id_count], old.effect_ids[:old.effect_id_count])
			return inverse, true}
		object_index := level_object_index(doc, command.entity_id)
		if object_index >=
		   0 {old := doc.objects[object_index]; target := &doc.objects[object_index]
			target.interaction = command.interaction
			target.interaction_prompt = command.interaction_prompt
			target.condition_id = command.condition_id
			target.focused_scene = command.focused_scene
			target.effect_id_count = min(command.effect_id_count, len(target.effect_ids))
			for effect_i in 0 ..< target.effect_id_count do target.effect_ids[effect_i] = command.effect_ids[effect_i]
			target.interaction_range = command.interaction_range
			target.initially_active = command.initially_active
			target.locked = command.locked
			target.powered = command.powered
			inverse := Level_Command {
				kind               = .Set_Interaction,
				entity_id          = old.id,
				interaction        = old.interaction,
				interaction_prompt = old.interaction_prompt,
				condition_id       = old.condition_id,
				focused_scene      = old.focused_scene,
				effect_id_count    = old.effect_id_count,
				interaction_range  = old.interaction_range,
				initially_active   = old.initially_active,
				locked             = old.locked,
				powered            = old.powered,
			}
			copy(inverse.effect_ids[:old.effect_id_count], old.effect_ids[:old.effect_id_count])
			return inverse, true}
		return {}, false
	case .Create_Roof:
		id := command.entity_id; if id == "" do id = level_next_id("roof", doc.revision)
		room_index := level_room_index(doc, command.material)
		if room_index < 0 do return {}, false
		append(
			&doc.roofs,
			Level_Roof {
				id = id,
				room_id = command.material,
				story = doc.rooms[room_index].story,
				style = Level_Roof_Style(
					clamp(int(command.a.x), 0, int(Level_Roof_Style.Parapet)),
				),
				pitch = command.value,
				overhang = command.b.x,
				ridge_angle = command.a.y,
				gutters = command.b.y > 0,
			},
		)
		return Level_Command{kind = .Delete_Roof, entity_id = id}, true
	case .Set_Roof:
		index := level_roof_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.roofs[index]
		doc.roofs[index].room_id = command.material
		doc.roofs[index].style = Level_Roof_Style(
			clamp(int(command.a.x), 0, int(Level_Roof_Style.Parapet)),
		)
		doc.roofs[index].pitch = command.value
		doc.roofs[index].overhang = command.b.x
		doc.roofs[index].ridge_angle = command.a.y
		doc.roofs[index].gutters = command.b.y > 0
		return Level_Command {
				kind = .Set_Roof,
				entity_id = old.id,
				material = old.room_id,
				a = {f32(old.style), old.ridge_angle},
				b = {old.overhang, old.gutters ? 1 : 0},
				value = old.pitch,
			},
			true
	case .Delete_Roof:
		index := level_roof_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.roofs[index]
		ordered_remove(&doc.roofs, index)
		return Level_Command {
				kind = .Create_Roof,
				entity_id = old.id,
				material = old.room_id,
				a = {f32(old.style), old.ridge_angle},
				b = {old.overhang, old.gutters ? 1 : 0},
				value = old.pitch,
			},
			true
	case .Create_Vertical_Link:
		id := command.entity_id; if id == "" do id = level_next_id("stairs", doc.revision)
		kind := Level_Vertical_Link_Kind(
			clamp(int(command.c.x), 0, int(Level_Vertical_Link_Kind.Elevator)),
		)
		to_story := level_story_above(doc, doc.active_story)
		if to_story < 0 do return {}, false
		append(
			&doc.vertical_links,
			Level_Vertical_Link {
				id = id,
				kind = kind,
				from_story = doc.active_story,
				to_story = to_story,
				start = level_snap_point(doc, command.a, true),
				finish = level_snap_point(doc, command.b, true),
				width = command.value,
			},
		)
		return Level_Command{kind = .Delete_Vertical_Link, entity_id = id}, true
	case .Set_Vertical_Link:
		index := level_vertical_link_index(doc, command.entity_id)
		if index < 0 do return {}, false
		old := doc.vertical_links[index].width
		doc.vertical_links[index].width = command.value
		return Level_Command {
				kind = .Set_Vertical_Link,
				entity_id = command.entity_id,
				value = old,
			},
			true
	case .Move_Vertical_Link_Point:
		index := level_vertical_link_index(doc, command.entity_id)
		point_index := int(command.value)
		if index < 0 || point_index < 0 || point_index > 1 do return {}, false
		old :=
			point_index == 0 ? doc.vertical_links[index].start : doc.vertical_links[index].finish
		if point_index == 0 do doc.vertical_links[index].start = level_snap_point(doc, command.a, true)
		else do doc.vertical_links[index].finish = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Move_Vertical_Link_Point,
				entity_id = command.entity_id,
				a = old,
				value = command.value,
			},
			true
	case .Delete_Vertical_Link:
		index := level_vertical_link_index(doc, command.entity_id)
		if index < 0 do return {}, false
		old := doc.vertical_links[index]
		ordered_remove(&doc.vertical_links, index)
		return Level_Command {
				kind = .Create_Vertical_Link,
				entity_id = old.id,
				a = old.start,
				b = old.finish,
				c = {f32(old.kind), 0},
				value = old.width,
			},
			true
	case .Create_Water:
		id := command.entity_id; if id == "" do id = level_next_id("water", doc.revision)
		points := make([dynamic]Vec2, 0, command.point_count)
		for i in 0 ..< command.point_count do append(&points, level_snap_point(doc, command.points[i], true))
		append(&doc.waters, Level_Water{id = id, points = points, elevation = command.value})
		return Level_Command{kind = .Delete_Water, entity_id = id}, true
	case .Set_Water:
		index := level_water_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.waters[index].elevation
		doc.waters[index].elevation = command.value
		return Level_Command{kind = .Set_Water, entity_id = command.entity_id, value = old}, true
	case .Move_Water_Point:
		index := level_water_index(doc, command.entity_id); point_index := int(command.value)
		if index < 0 || point_index < 0 || point_index >= len(doc.waters[index].points) do return {}, false
		old := doc.waters[index].points[point_index]
		doc.waters[index].points[point_index] = level_snap_point(doc, command.a, true)
		return Level_Command {
				kind = .Move_Water_Point,
				entity_id = command.entity_id,
				a = old,
				value = command.value,
			},
			true
	case .Delete_Water:
		index := level_water_index(doc, command.entity_id); if index < 0 do return {}, false
		old := doc.waters[index]
		ordered_remove(&doc.waters, index)
		inverse := Level_Command {
			kind        = .Create_Water,
			entity_id   = old.id,
			value       = old.elevation,
			point_count = min(len(old.points), 32),
		}
		for p, i in old.points {if i >= len(inverse.points) do break; inverse.points[i] = p}
		return inverse, true
	case .Sculpt_Terrain:
		radius := max(command.value, .25); strength := command.c.x
		if strength <= 0 do strength = .25
		source := make([]f32, len(doc.terrain), context.temp_allocator)
		copy(source, doc.terrain[:])
		start_height, end_height :=
			level_terrain_height(doc, command.a), level_terrain_height(doc, command.b)
		for y in 0 ..= doc.height {for x in 0 ..= doc.width {index := y * (doc.width + 1) + x; distance, t := level_segment_distance({f32(x), f32(y)}, command.a, command.b)
				if distance > radius do continue
				falloff := 1 - distance / radius
				falloff *= falloff
				current := source[index]
				next := current
				switch command.brush {case .Raise:
					next = current + strength * falloff; case .Lower:
					next = current - strength * falloff; case .Flatten:
					next =
						current +
						(command.c.y - current) * clamp(strength * falloff, 0, 1); case .Slope:
					target := start_height + (end_height - start_height) * t
					next =
						current +
						(target - current) * clamp(strength * falloff, 0, 1); case .Smooth:
					sum := f32(0); count := 0
					for oy := -1;
					    oy <= 1;
					    oy += 1 {for ox := -1; ox <= 1; ox += 1 {nx, ny := x + ox, y + oy; if nx < 0 || ny < 0 || nx > doc.width || ny > doc.height do continue
							sum += source[ny * (doc.width + 1) + nx]
							count += 1}}
					if count >
					   0 {average := sum / f32(count); next = current + (average - current) * clamp(strength * falloff, 0, 1)}}
				doc.terrain[index] = f32(math.round(f64(next / .25))) * .25
			}}
		return {}, true
	case:
		return {}, false
	}
}

level_point_in_polygon :: proc(point: Vec2, points: []Vec2) -> bool {if len(points) < 3 do return false
	inside := false
	j := len(points) - 1
	for 	i in 0 ..< len(points) {a, b := points[i], points[j]; if (a.y > point.y) != (b.y > point.y) && point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x do inside = !inside
		j = i}
	return inside}
level_pick_room_handle :: proc(
	doc: ^Level_Document,
	point: Vec2,
	current: Editor_Selection,
) -> (
	Editor_Selection,
	bool,
) {
	if current.kind != .Room && current.kind != .Vertex && current.kind != .Edge do return {}, false
	index := level_room_index(
		doc,
		current.entity_id,
	); if index < 0 do return {}, false; room := doc.rooms[index]
	for vertex, i in room.points {dx, dy := point.x - vertex.x, point.y - vertex.y; if dx * dx + dy * dy <= .32 * .32 do return {.Vertex, room.id, i}, true}
	for i in 0 ..< len(
		room.points,
	) {a, b := room.points[i], room.points[(i + 1) % len(room.points)]; if point_segment_distance_sq(point.x, point.y, a, b) <= .16 * .16 do return {.Edge, room.id, i}, true}
	return {}, false
}
level_pick :: proc(doc: ^Level_Document, point: Vec2) -> Editor_Selection {for marker in doc.markers do if marker.story == doc.active_story && (marker.position.x - point.x) * (marker.position.x - point.x) + (marker.position.y - point.y) * (marker.position.y - point.y) <= max(marker.radius, .3) * max(marker.radius, .3) do return {.Marker, marker.id, -1}
	for light in doc.lights do if light.story == doc.active_story && (light.position.x - point.x) * (light.position.x - point.x) + (light.position.y - point.y) * (light.position.y - point.y) <= .45 * .45 do return {.Light, light.id, -1}
	for object in doc.objects do if object.story == doc.active_story && (object.position.x - point.x) * (object.position.x - point.x) + (object.position.y - point.y) * (object.position.y - point.y) <= .5 * .5 do return {.Object, object.id, -1}
	for 	opening in doc.openings {path_index := level_path_index(doc, opening.host_path); if path_index >=
		   0 {path := doc.paths[path_index]; if path.story == doc.active_story &&
			   opening.segment >= 0 &&
			   opening.segment < len(path.points) - 1 {a, b :=
					path.points[opening.segment], path.points[opening.segment + 1]
				dx, dy := b.x - a.x, b.y - a.y
				length := f32(math.sqrt(f64(dx * dx + dy * dy)))
				if length > .001 {half := opening.width * .5 / length; start := Vec2 {
						a.x + dx * (opening.position - half),
						a.y + dy * (opening.position - half),
					}
					finish := Vec2 {
						a.x + dx * (opening.position + half),
						a.y + dy * (opening.position + half),
					}
					if point_segment_distance_sq(point.x, point.y, start, finish) < .3 * .3 do return {.Opening, opening.id, opening.segment}}}}}
	for 	path in doc.paths {if path.story != doc.active_story do continue; for i in 0 ..< len(path.points) - 1 do if point_segment_distance_sq(point.x, point.y, path.points[i], path.points[i + 1]) < .25 * .25 do return {.Path, path.id, i}}
	if doc.active_story == 0 do for water in doc.waters do if level_point_in_polygon(point, water.points[:]) do return {.Water, water.id, -1}
	for room in doc.rooms do if room.story == doc.active_story && level_point_in_polygon(point, room.points[:]) do return {.Room, room.id, -1}
	if doc.active_story == 0 do for foundation in doc.foundations do if level_foundation_contains_point(foundation, point) do return {.Foundation, foundation.id, -1}
	return{.Terrain, "", -1}}
level_pick_path_segment :: proc(
	doc: ^Level_Document,
	point: Vec2,
	max_distance: f32 = .8,
) -> (
	Editor_Selection,
	bool,
) {best := max_distance * max_distance; result := Editor_Selection{}; found := false; for 	path in doc.paths {if path.story != doc.active_story do continue; for 		i in 0 ..< len(path.points) - 1 {distance := point_segment_distance_sq(
				point.x,
				point.y,
				path.points[i],
				path.points[i + 1],
			)
			if distance < best {best = distance; result = {.Path, path.id, i}; found = true}}}
	return result, found}
editor_control_point_index :: proc(selection: Editor_Selection) -> int {return(
		selection.sub_index <= -2 ? -selection.sub_index - 2 : -1 \
	)}
level_pick_control_point :: proc(
	doc: ^Level_Document,
	point: Vec2,
	selected: Editor_Selection,
) -> (
	Editor_Selection,
	bool,
) {best := f32(.45 * .45); result := Editor_Selection{}; found := false; if selected.kind ==
	   .Path {index := level_path_index(doc, selected.entity_id); if index >= 0 {for 			p, i in doc.paths[index].points {dx, dy := p.x - point.x, p.y - point.y; distance :=
					dx * dx + dy * dy
				if distance <= best {best = distance; result = {.Path, selected.entity_id, -i - 2}
					found = true}}}}
	else if selected.kind == .Water {index := level_water_index(doc, selected.entity_id)
		if index >= 0 {for 			p, i in doc.waters[index].points {dx, dy := p.x - point.x, p.y - point.y; distance :=
					dx * dx + dy * dy
				if distance <= best {best = distance; result = {.Water, selected.entity_id, -i - 2}
					found = true}}}}
	else if selected.kind == .Foundation {index := level_foundation_index(doc, selected.entity_id)
		if index >= 0 {for 			p, i in doc.foundations[index].points {dx, dy := p.x - point.x, p.y - point.y; distance :=
					dx * dx + dy * dy
				if distance <= best {best = distance; result = {
						.Foundation,
						selected.entity_id,
						-i - 2,
					}
					found = true}}}}
	else if selected.kind == .Vertical_Link {index := level_vertical_link_index(
			doc,
			selected.entity_id,
		)
		if index >= 0 {points := [2]Vec2 {
				doc.vertical_links[index].start,
				doc.vertical_links[index].finish,
			}
			for 			p, i in points {dx, dy := p.x - point.x, p.y - point.y; distance := dx * dx + dy * dy
				if distance <= best {best = distance; result = {
						.Vertical_Link,
						selected.entity_id,
						-i - 2,
					}
					found = true}}}}
	return result, found}
level_opening_command_at :: proc(
	doc: ^Level_Document,
	host: Editor_Selection,
	point: Vec2,
	kind: Level_Opening_Kind,
	width: f32 = 0,
	height: f32 = 0,
	sill_height: f32 = 0,
	window_style: Window_Style = .Fixed,
) -> (
	Level_Command,
	bool,
) {if host.kind != .Path do return {}, false; path_index := level_path_index(doc, host.entity_id)
	if path_index < 0 || host.sub_index < 0 || host.sub_index >= len(doc.paths[path_index].points) - 1 do return {}, false
	a, b :=
		doc.paths[path_index].points[host.sub_index],
		doc.paths[path_index].points[host.sub_index + 1]
	dx, dy := b.x - a.x, b.y - a.y
	length_sq := dx * dx + dy * dy
	if length_sq <= .0001 do return {}, false
	t := clamp(((point.x - a.x) * dx + (point.y - a.y) * dy) / length_sq, 0, 1)
	default_width :=
		kind == .Window ? f32(1.6) : kind == .Arch ? f32(1.5) : kind == .Gate ? f32(1.4) : f32(1.2)
	default_height :=
		kind == .Window ? f32(1.4) : kind == .Arch ? f32(2.2) : kind == .Gate ? f32(1.5) : f32(2.1)
	opening_width := width
	opening_height := height
	opening_sill := sill_height
	if opening_width <= 0 do opening_width = default_width
	if opening_height <= 0 do opening_height = default_height
	if kind == .Window && opening_sill <= 0 do opening_sill = .72
	length := f32(math.sqrt(f64(length_sq)))
	end_clearance := level_opening_end_clearance(kind)
	t = clamp(
		t,
		(opening_width * .5 + end_clearance) / length,
		1 - (opening_width * .5 + end_clearance) / length,
	)
	command := Level_Command {
		kind     = .Add_Opening,
		material = host.entity_id,
		value    = f32(host.sub_index),
		b        = {f32(kind), opening_width},
		c        = {t, opening_height},
	}
	command.points[0] = {opening_sill, f32(window_style)}
	return command, true}
level_opening_edit_command :: proc(opening: Level_Opening) -> Level_Command {command :=
		Level_Command {
			kind        = .Set_Opening,
			entity_id   = opening.id,
			material    = opening.host_path,
			destination = door_material_name(opening.door_material),
			value       = f32(opening.segment),
			b           = {f32(opening.kind), opening.width},
			c           = {opening.position, opening.height},
		}
	command.points[0] = {opening.sill_height, f32(opening.window_style)}
	command.points[1] = {opening.window_flipped ? 1 : 0, opening.window_hinge_right ? 1 : 0}
	command.points[2].x = f32(opening.door_style)
	return command}
level_opening_resize_command :: proc(
	doc: ^Level_Document,
	id: string,
	width_delta, height_delta: f32,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 do return {}, false; opening :=
		doc.openings[index]
	command := level_opening_edit_command(opening)
	command.b.y = clamp(opening.width + width_delta, .4, 6)
	command.c.y = clamp(opening.height + height_delta, .4, 4)
	return command, true}
level_door_style_command :: proc(
	doc: ^Level_Document,
	id: string,
	style: Door_Style,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 || doc.openings[index].kind != .Door do return {}, false
	command := level_opening_edit_command(doc.openings[index])
	command.points[2].x = f32(style)
	return command, true}
level_window_sill_command :: proc(
	doc: ^Level_Document,
	id: string,
	delta: f32,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 || doc.openings[index].kind != .Window do return {}, false
	opening := doc.openings[index]
	command := level_opening_edit_command(opening)
	command.points[0].x = clamp(opening.sill_height + delta, .2, 2)
	return command, true}
level_window_style_command :: proc(
	doc: ^Level_Document,
	id: string,
	style: Window_Style,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 || doc.openings[index].kind != .Window do return {}, false
	command := level_opening_edit_command(doc.openings[index])
	command.points[0].y = f32(style)
	return command, true}
level_window_flip_command :: proc(
	doc: ^Level_Document,
	id: string,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 || doc.openings[index].kind != .Window do return {}, false
	opening := doc.openings[index]
	command := level_opening_edit_command(opening)
	command.points[1].x = opening.window_flipped ? 0 : 1
	return command, true}
level_window_handing_command :: proc(
	doc: ^Level_Document,
	id: string,
) -> (
	Level_Command,
	bool,
) {index := level_opening_index(doc, id); if index < 0 || doc.openings[index].kind != .Window || doc.openings[index].window_style != .Casement do return {}, false
	opening := doc.openings[index]
	command := level_opening_edit_command(opening)
	command.points[1].y = opening.window_hinge_right ? 0 : 1
	return command, true}
