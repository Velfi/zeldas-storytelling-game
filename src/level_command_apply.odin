package main

import "core:fmt"
import "core:math"

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
