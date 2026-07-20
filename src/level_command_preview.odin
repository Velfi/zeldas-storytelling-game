package main

import "core:fmt"
import "core:math"

level_command_preview :: proc(doc: ^Level_Document, command: Level_Command) -> Placement_Result {
	#partial switch command.kind {
	case .Create_Foundation, .Set_Foundation, .Move_Foundation_Point, .Delete_Foundation:
		return level_command_preview_foundation(doc, command)
	case .Create_Room,
	     .Create_Room_Polygon,
	     .Split_Room,
	     .Merge_Rooms,
	     .Insert_Room_Vertex,
	     .Remove_Room_Vertex,
	     .Duplicate_Room,
	     .Move_Room,
	     .Rotate_Room,
	     .Move_Room_Vertex,
	     .Move_Room_Edge:
		return level_command_preview_room(doc, command)
	case .Add_Path,
	     .Set_Path,
	     .Move_Path_Point,
	     .Create_Water,
	     .Set_Water,
	     .Move_Water_Point,
	     .Delete_Water:
		return level_command_preview_path_and_water(doc, command)
	case .Add_Opening, .Set_Opening:
		return level_command_preview_opening(doc, command)
	case .Place_Object, .Duplicate_Object, .Move_Object:
		return level_command_preview_object(doc, command)
	case .Add_Light, .Set_Light, .Delete_Light:
		return level_command_preview_light(doc, command)
	case .Create_Roof, .Set_Roof, .Delete_Roof:
		return level_command_preview_roof(doc, command)
	case .Create_Vertical_Link,
	     .Set_Vertical_Link,
	     .Move_Vertical_Link_Point,
	     .Delete_Vertical_Link:
		return level_command_preview_vertical_link(doc, command)
	case .Sculpt_Terrain:
		return level_command_preview_terrain(doc, command)
	case .Add_Marker, .Set_Marker, .Delete_Marker:
		return level_command_preview_marker(doc, command)
	case:
		return level_command_preview_general(doc, command)
	}
}

level_command_preview_foundation :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_room :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_path_and_water :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_opening :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_object :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_light :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_roof :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_vertical_link :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_terrain :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_marker :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_general :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
	return level_command_preview_command(doc, command)
}

level_command_preview_command :: proc(
	doc: ^Level_Document,
	command: Level_Command,
) -> Placement_Result {
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
	for point, i in points {next := points[(i + 1) % len(points)]; mid := Vec2 {
			(point.x + next.x) * .5,
			(point.y + next.y) * .5,
		}
		if !level_foundation_contains_point(foundation, mid) do return false
		for edge, j in foundation.points {if level_segments_cross(point, next, edge, foundation.points[(j + 1) % len(foundation.points)]) do return false}}
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
