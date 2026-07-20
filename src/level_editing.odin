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
