package main

import "core:fmt"
import "core:math"
import "core:strings"

authoring_spatial_add :: proc(
	result: ^[dynamic]Authoring_Diagnostic,
	doc: ^Level_Document,
	entity, field: string,
	severity: Authoring_Diagnostic_Severity,
	message: string,
	story: int,
	position: Vec2,
) {
	item := authoring_diagnostic_init(.Level, "level", entity, field, severity, message)
	authoring_diagnostic_set_location(&item, doc.id, story, position)
	append(result, item)
}

authoring_spatial_point_obstructed :: proc(
	doc: ^Level_Document,
	story: int,
	position: Vec2,
	ignore_id: string = "",
) -> (
	string,
	string,
) {
	for object in doc.objects {
		if object.story != story || object.id == ignore_id do continue
		dx, dy := object.position.x - position.x, object.position.y - position.y
		if dx * dx + dy * dy < .45 * .45 do return object.id, "object"
	}
	for water in doc.waters do if story == 0 && len(water.points) >= 3 && level_point_in_polygon(position, water.points[:]) do return water.id, "water"
	return "", ""
}

authoring_spatial_marker_reference_compatible :: proc(
	project: ^Story_Project,
	doc: ^Level_Document,
	marker: Level_Marker,
) -> bool {
	if marker.reference == "" do return marker.kind != .Character_Spawn && marker.kind != .Clue
	if project == nil do return true
	switch marker.kind {
	case .Character_Spawn:
		return story_entity_index(project, marker.reference) >= 0
	case .Clue:
		payload := mystery_payload(project)
		if payload != nil && mystery_clue_index(payload, marker.reference) >= 0 do return true
		// A clue marker may bind the physical StoryCore source entity while the
		// MysteryDomain clue keeps its own stable record ID.
		return story_entity_index(project, marker.reference) >= 0
	case .Camera, .Staging, .Player_Spawn, .Interaction, .Trigger, .Transition:
		return true
	}
	return true
}

// Produces authoring-only spatial diagnostics. The LevelFormat validator stays
// concerned with serialization and local geometry; this pass verifies the
// creator-facing semantics which join markers, authored spaces, and runtime use.
authoring_spatial_validate_levels :: proc(
	levels: []^Level_Document,
	project: ^Story_Project = nil,
) -> [dynamic]Authoring_Diagnostic {
	result := [dynamic]Authoring_Diagnostic{}
	registry: Story_Spatial_Registry; defer story_spatial_registry_destroy(&registry)
	for doc in levels do if doc != nil {space := story_level_space(doc); if !story_spatial_registry_register(&registry, space) do authoring_spatial_add(&result, doc, doc.id, "id", .Blocking, "spatial space ID is duplicated across the active case", 0, {})}
	for doc in levels {
		if doc == nil do continue
		for marker, index in doc.markers {
			field := "position"
			if marker.kind == .Player_Spawn || marker.kind == .Character_Spawn {
				if blocker, kind := authoring_spatial_point_obstructed(doc, marker.story, marker.position, marker.id); blocker != "" do authoring_spatial_add(&result, doc, marker.id, field, .Error, fmt.tprintf("spawn is obstructed by %s %s", kind, blocker), marker.story, marker.position)
			}
			if marker.kind == .Character_Spawn || marker.kind == .Clue {
				if !authoring_spatial_marker_reference_compatible(project, doc, marker) do authoring_spatial_add(&result, doc, marker.id, "reference", .Error, "marker reference is missing or incompatible with its typed marker kind", marker.story, marker.position)
			}
			if marker.reference !=
			   "" {for other in doc.markers[index + 1:] do if other.kind == marker.kind && other.reference == marker.reference && other.story != marker.story do authoring_spatial_add(&result, doc, other.id, "reference", .Error, "typed marker reference is duplicated across story scopes", other.story, other.position)}
			if marker.kind == .Transition {
				destination, qualified := story_spatial_id_parse(marker.destination)
				if !qualified {authoring_spatial_add(&result, doc, marker.id, "destination", .Error, "transition destination must be explicitly qualified as space:target", marker.story, marker.position); continue}
				space, target, status, _ := story_spatial_registry_resolve(&registry, destination)
				if status == .Missing ||
				   (status == .Unavailable &&
						   destination.space_id ==
							   doc.id) {authoring_spatial_add(&result, doc, marker.id, "destination", .Error, "transition destination does not resolve in its qualified space", marker.story, marker.position)} else if status == .Available && (target.kind != .Transition && target.kind != .Marker) {authoring_spatial_add(&result, doc, marker.id, "destination", .Error, "transition destination must resolve to a transition or marker", marker.story, marker.position)} else if status == .Available && space == &registry.spaces[story_spatial_registry_space(registry.spaces[:], doc.id)] && target.id == marker.id {authoring_spatial_add(&result, doc, marker.id, "destination", .Error, "transition cannot resolve to itself", marker.story, marker.position)}
			}
			if marker.kind == .Camera {
				if marker.facing != marker.facing || math.abs(marker.facing) > 360000 || marker.radius <= 0 do authoring_spatial_add(&result, doc, marker.id, "facing", .Error, "camera framing requires a finite heading and positive framing radius", marker.story, marker.position)
				staged :=
					false; for candidate in doc.markers do if candidate.kind == .Staging && candidate.story == marker.story && story_target_distance(candidate.position, marker.position) <= max(marker.radius, 6) {staged = true; break}; if !staged do authoring_spatial_add(&result, doc, marker.id, "reference", .Warning, "camera has no staging marker in its framing scope", marker.story, marker.position)
			}
		}
		for object in doc.objects {
			if object.support_id !=
			   "" {support := level_object_index(doc, object.support_id); if support >= 0 && doc.objects[support].story == object.story {distance := story_target_distance(object.position, doc.objects[support].position); if distance > 3 do authoring_spatial_add(&result, doc, object.id, "support_id", .Error, "contained object is spatially separated from its authored support", object.story, object.position)}}
			if object.interaction != .None && object.initially_active {
				if blocker, _ := authoring_spatial_point_obstructed(doc, object.story, object.position, object.id); blocker != "" do authoring_spatial_add(&result, doc, object.id, "position", .Error, "active interaction is obstructed and cannot be reached", object.story, object.position)
			}
		}
	}
	return result
}

authoring_spatial_validate_level :: proc(
	doc: ^Level_Document,
	project: ^Story_Project = nil,
) -> [dynamic]Authoring_Diagnostic {levels := [1]^Level_Document{doc}
	return authoring_spatial_validate_levels(levels[:], project)}
