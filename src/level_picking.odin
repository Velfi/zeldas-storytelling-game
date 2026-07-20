package main

import "core:math"

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
