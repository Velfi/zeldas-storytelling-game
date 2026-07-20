package main

import "core:math"
import engine "zelda_engine:engine"

vk_world_build_city :: proc(scene: ^Vk_World_Scene, ctx: ^engine.Vk_Context, g: ^Game) {
	city_center_x, city_center_z := CITY_WORLD_WIDTH * .5, CITY_WORLD_HEIGHT * .5
	// As with an interior cutaway, authored ground ends over a distinct negative-
	// space layer instead of visually promising terrain past an invisible wall.
	// The interior background shader returns a fully composed color and is only
	// safe beneath the compact dollhouse. Keep the city's much larger border on
	// the ordinary depth-tested terrain path so it can never paint over geometry.
	vk_world_add_sized(
		scene,
		ctx,
		&city_background_mesh,
		city_center_x,
		city_center_z,
		CITY_WORLD_WIDTH + city_world(240),
		.001,
		0,
		{19, 77, 87, 255},
		7,
		-.08,
	)
	// Preserve the authored terrain mesh's Y range. The generic sized-floor path
	// intentionally flattens a mesh to its requested height.
	vk_world_add(
		scene,
		ctx,
		&city_ground_mesh,
		city_center_x,
		city_center_z,
		city_ground_mesh.max.y - city_ground_mesh.min.y,
		0,
		{92, 142, 96, 255},
		false,
		7,
		-.045,
	)
	// Road vertices are baked against the same height function as the ground,
	// preserving markings and curbs while removing rigid-tile steps.
	for &road in city_bent_road_meshes {if !road.ready do continue
		cx, cz := (road.min.x + road.max.x) * .5, (road.min.z + road.max.z) * .5
		vk_world_add(
			scene,
			ctx,
			&road,
			cx,
			cz,
			road.max.y - road.min.y,
			0,
			{255, 255, 255, 255},
			false,
			7,
			road.min.y + .01,
		)}
	for by in 0 ..< CITY_HEIGHT /
		CITY_BLOCK {for bx in 0 ..< CITY_WIDTH / CITY_BLOCK {layout_x, layout_z, place := city_building_site(bx, by); wx, wz := city_world(layout_x), city_world(layout_z); if !place || !city_render_chunk_visible(g, wx, wz, CITY_BUILDING_DRAW_DISTANCE, CITY_DRIVING_BEHIND_DISTANCE) do continue; mesh_index, height, yaw, tint := city_building_style(bx, by, layout_x); vk_world_add(scene, ctx, &city_meshes[mesh_index], wx, wz, city_world(height), yaw, tint, false, 8, city_elevation(wx, wz))}}
	payload := mystery_game_payload(
		g,
	); quest_index := payload == nil ? -1 : city_landmark_index(g, payload.city_destination); if quest_index >= 0 {quest, ok := city_landmark_at(g, quest_index); if ok && city_quest_marker_visible(g, quest) {dx, dz := quest.x - g.city_x, quest.y - g.city_y; if dx * dx + dz * dz <= CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE {center := Vec2{quest.x, quest.y}; if !city_quest_marker_built || city_quest_marker_center != center {city_quest_marker_mesh = procedural_city_quest_marker_mesh(center, 3.2); city_quest_marker_center = center; city_quest_marker_built = true; _ = vk_world_refresh_mesh(scene, ctx, &city_quest_marker_mesh)}; marker_base := city_surface_elevation(quest.x, quest.y) + city_quest_marker_mesh.min.y + .035; vk_world_add(scene, ctx, &city_quest_marker_mesh, quest.x, quest.y, 6.4, 0, {255, 202, 72, 205}, true, 7, marker_base)}}}
	for mark in g.vehicle_skid_marks {if !mark.active || mark.age >= VEHICLE_SKID_LIFETIME do continue; fade := 1 - mark.age / VEHICLE_SKID_LIFETIME; alpha := u8(clamp(mark.strength * fade * 125, 0, 125)); vk_world_add(scene, ctx, &vehicle_skid_mesh, mark.position.x, mark.position.y, .62, mark.heading, {8, 10, 12, alpha}, true, 7, city_elevation(mark.position.x, mark.position.y) + .022)}
	for prop in g.city_furniture {dx, dz := prop.x - g.city_x, prop.y - g.city_y; if dx * dx + dz * dz > CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE do continue; template := city_furniture_template(prop.kind); vk_world_add(scene, ctx, &city_furniture_meshes[int(prop.kind)], prop.x, prop.y, template.height, prop.heading, template.tint, false, 9, city_elevation(prop.x, prop.y), prop.roll, prop.pitch)}
	// Kenney's car meshes face model-space -Z. Rotate that axis onto the
	// simulation heading (+X at zero) without reversing the visible vehicle.
	for car, i in g.vehicles {dx, dz := car.x - g.city_x, car.y - g.city_y; if dx * dx + dz * dz > CITY_DYNAMIC_DRAW_DISTANCE * CITY_DYNAMIC_DRAW_DISTANCE do continue; rough_roll, rough_pitch := vehicle_rough_body_pose(car); vk_world_add(scene, ctx, &city_car_meshes[i], car.x, car.y, 1.05, car.heading - f32(math.PI / 2), {255, 255, 255, 255}, false, 10, city_elevation(car.x, car.y), car.body_roll + rough_roll, car.body_pitch + rough_pitch)}
	if g.driving_vehicle <
	   0 {player := &g.player_animation; vk_world_add_animated(scene, ctx, &character_meshes[0], g.city_x, g.city_y, 1.65, character_render_yaw(g.city_angle), {255, 255, 255, 255}, player.current, player.transitioning ? player.next : -1, player.time, player.next_time, player.transitioning ? player.transition : 0, city_surface_elevation(g.city_x, g.city_y), 9)}
}

vk_world_build_catalog_thumbnail :: proc(
	scene: ^Vk_World_Scene,
	ctx: ^engine.Vk_Context,
	g: ^Game,
) {
	if g.catalog_bake_index < 0 || g.catalog_bake_index >= len(editor_catalog.entries) do return
	entry :=
		editor_catalog.entries[g.catalog_bake_index]; mesh, ok := catalog_object_mesh(entry.id); if !ok do return; span_x := mesh.max.x - mesh.min.x; span_y := mesh.max.y - mesh.min.y; span_z := mesh.max.z - mesh.min.z
	// Normalize by the complete bounds, not just height. This keeps broad tables and
	// tall bookcases at the same visual scale without catalog-specific camera hacks.
	max_span := max(span_x, max(span_y, span_z)); if max_span <= 0 do max_span = 1
	normalized_height := 2.5 * span_y / max_span
	vk_world_add(
		scene,
		ctx,
		&catalog_thumbnail_floor,
		0,
		0,
		12,
		0,
		{226, 220, 203, 255},
		true,
		0,
		-.035,
	)
	vk_world_add(
		scene,
		ctx,
		mesh,
		0,
		0,
		normalized_height,
		-f32(math.PI) / 8,
		{255, 255, 255, 255},
		false,
		0,
		0,
	)
}
