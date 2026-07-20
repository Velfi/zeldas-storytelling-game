package main

import "core:fmt"
import "core:math"
import "core:strings"
import ui "zelda_engine:ui"

graph_edge_cubic_point :: proc(a, b, c, d: Vec2, t: f32) -> Vec2 {
	u := 1 - t; uu, tt := u * u, t * t
	return {
		a.x * uu * u + 3 * b.x * uu * t + 3 * c.x * u * tt + d.x * tt * t,
		a.y * uu * u + 3 * b.y * uu * t + 3 * c.y * u * tt + d.y * tt * t,
	}
}

vk_graph_cubic :: proc(r: ^Vulkan_Backend, a, b, c, d: Vec2, color: [4]u8, thickness: f32) {
	// Screen-space subdivision keeps tight bends smooth without spending the
	// same number of UI quads on short, nearly straight connections.
	control_length :=
		f32(math.sqrt(f64((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)))) +
		f32(math.sqrt(f64((c.x - b.x) * (c.x - b.x) + (c.y - b.y) * (c.y - b.y)))) +
		f32(math.sqrt(f64((d.x - c.x) * (d.x - c.x) + (d.y - c.y) * (d.y - c.y))))
	steps := clamp(int(control_length / 9), 8, 64); previous := a
	for i in 1 ..= steps {point := graph_edge_cubic_point(a, b, c, d, f32(i) / f32(steps)); vk_graph_aa_segment(r, previous, point, color, thickness); previous = point}
}

vk_graph_aa_segment :: proc(r: ^Vulkan_Backend, a, b: Vec2, color: [4]u8, thickness: f32) {
	// A solid ribbon plus a one-pixel coverage fringe gives graph wires stable
	// antialiasing at every zoom level.  Overlapping round caps hide tiny cracks
	// between adaptively-subdivided curve segments.
	dx, dy :=
		b.x -
		a.x,
		b.y -
		a.y; length := f32(math.sqrt(f64(dx * dx + dy * dy))); if length < .01 do return
	n := Vec2{-dy / length, dx / length}; half := thickness * .5; outer := half + 1
	ai, ao := Vec2{a.x + n.x * half, a.y + n.y * half}, Vec2{a.x + n.x * outer, a.y + n.y * outer}
	bi, bo := Vec2{b.x + n.x * half, b.y + n.y * half}, Vec2{b.x + n.x * outer, b.y + n.y * outer}
	aj, ap := Vec2{a.x - n.x * half, a.y - n.y * half}, Vec2{a.x - n.x * outer, a.y - n.y * outer}
	bj, bp := Vec2{b.x - n.x * half, b.y - n.y * half}, Vec2{b.x - n.x * outer, b.y - n.y * outer}
	vulkan_ui_triangle(r, ai, aj, bi, color); vulkan_ui_triangle(r, bi, aj, bj, color)
	transparent := color; transparent[3] = 0
	vulkan_ui_triangle_colors(
		r,
		ao,
		ai,
		bo,
		transparent,
		color,
		transparent,
	); vulkan_ui_triangle_colors(r, bo, ai, bi, transparent, color, color)
	vulkan_ui_triangle_colors(
		r,
		aj,
		ap,
		bj,
		color,
		transparent,
		color,
	); vulkan_ui_triangle_colors(r, bj, ap, bp, color, transparent, transparent)
	segments := 8
	for end in 0 ..< 2 {center := end == 0 ? a : b; for i in 0 ..< segments {angle0 := f32(i) * f32(math.PI) / f32(segments) + f32(math.PI) * .5; angle1 := f32(i + 1) * f32(math.PI) / f32(segments) + f32(math.PI) * .5; if end == 1 {angle0 += f32(math.PI); angle1 += f32(math.PI)}; p0 := Vec2{center.x + f32(math.cos(f64(angle0))) * half, center.y + f32(math.sin(f64(angle0))) * half}; p1 := Vec2{center.x + f32(math.cos(f64(angle1))) * half, center.y + f32(math.sin(f64(angle1))) * half}; vulkan_ui_triangle(r, center, p0, p1, color)}}
}

vk_graph_smooth_path :: proc(r: ^Vulkan_Backend, points: []Vec2, color: [4]u8, thickness: f32) {
	// Catmull-Rom converted to cubic Beziers.  Shared derivatives make every
	// routed bend continuous, so obstacle lanes never introduce hard corners.
	if len(points) < 2 do return
	for i in 0 ..< len(points) -
		1 {p0 := i > 0 ? points[i - 1] : points[i]; p1, p2 := points[i], points[i + 1]; p3 := i + 2 < len(points) ? points[i + 2] : points[i + 1]; b := Vec2{p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6}; c := Vec2{p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6}; vk_graph_cubic(r, p1, b, c, p2, color, thickness)}
}

vk_graph_orthogonal_path :: proc(
	r: ^Vulkan_Backend,
	a, d: Vec2,
	lane_y: f32,
	color: [4]u8,
	thickness: f32,
) {
	// Horizontal port normals are inviolate. Straight runs meet the clearance
	// lane through rounded quarter turns, so cards are always entered at 90°.
	lead := clamp(math.abs(d.x - a.x) * .18, f32(28), f32(54)); x1, x2 := a.x + lead, d.x - lead
	radius := min(
		f32(22),
		min(math.abs(lane_y - a.y) * .45, math.abs(lane_y - d.y) * .45),
	); radius = max(radius, f32(4))
	sy :=
		lane_y >= a.y ? f32(1) : f32(-1); ty := d.y >= lane_y ? f32(1) : f32(-1); k := f32(.55228475)
	vk_graph_aa_segment(r, a, {x1 - radius, a.y}, color, thickness)
	vk_graph_cubic(
		r,
		{x1 - radius, a.y},
		{x1 - radius + k * radius, a.y},
		{x1, lane_y - sy * radius - k * sy * radius},
		{x1, lane_y - sy * radius},
		color,
		thickness,
	)
	vk_graph_aa_segment(r, {x1, lane_y - sy * radius}, {x1, lane_y}, color, thickness)
	vk_graph_aa_segment(r, {x1, lane_y}, {x2, lane_y}, color, thickness)
	vk_graph_aa_segment(r, {x2, lane_y}, {x2, lane_y + ty * radius}, color, thickness)
	vk_graph_cubic(
		r,
		{x2, lane_y + ty * radius},
		{x2, lane_y + ty * radius + k * ty * radius},
		{x2 + radius - k * radius, d.y},
		{x2 + radius, d.y},
		color,
		thickness,
	)
	vk_graph_aa_segment(r, {x2 + radius, d.y}, d, color, thickness)
}

graph_edge_rect_hit :: proc(a, b: Vec2, box: Rect) -> bool {
	// Conservative samples are intentional: routing a harmless extra bend is
	// preferable to drawing a connection through a card.
	for i in 0 ..= 16 {t := f32(i) / 16; point := Vec2{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t}; if contains(box, point) do return true}; return false
}

graph_edge_direct_clear :: proc(scene: string, a, b: Vec2, from_index, to_index: int) -> bool {
	for node, i in graph_document.nodes[:graph_document.node_count] {if i == from_index || i == to_index || node.beat.scene != scene do continue; box := graph_node_rect(node); box = {box.x - 14, box.y - 14, box.w + 28, box.h + 28}; if graph_edge_rect_hit(a, b, box) do return false}; return true
}

graph_edge_segments_clear :: proc(
	scene: string,
	points: []Vec2,
	from_index, to_index: int,
) -> bool {
	for node, i in graph_document.nodes[:graph_document.node_count] {
		if i == from_index || i == to_index || node.beat.scene != scene do continue
		box := graph_node_rect(node); box = {box.x - 14, box.y - 14, box.w + 28, box.h + 28}
		for segment in 1 ..< len(points) do if graph_edge_rect_hit(points[segment - 1], points[segment], box) do return false
	}
	return true
}

graph_edge_local_lane :: proc(
	scene: string,
	a, d: Vec2,
	from_index, to_index: int,
) -> (
	f32,
	bool,
) {
	// Prefer a corridor immediately above or below the cards that actually
	// obstruct this edge. This keeps detours local and leaves the canvas
	// perimeter available for genuine back edges.
	top, bottom := f32(1e9), f32(-1e9); blocked := false
	for node, i in graph_document.nodes[:graph_document.node_count] {
		if i == from_index || i == to_index || node.beat.scene != scene do continue
		box := graph_node_rect(node); box = {box.x - 14, box.y - 14, box.w + 28, box.h + 28}
		if !graph_edge_rect_hit(a, d, box) do continue
		blocked = true; top = min(top, box.y - 18); bottom = max(bottom, box.y + box.h + 18)
	}
	if !blocked do return 0, false
	lead := f32(
		28,
	); candidates := [2]f32{top, bottom}; best, best_cost := f32(0), f32(1e9); canvas := graph_canvas_rect()
	for lane in candidates {
		if lane < canvas.y + 10 || lane > canvas.y + canvas.h - 10 do continue
		points := [4]Vec2{a, {a.x + lead, lane}, {d.x - lead, lane}, d}
		if !graph_edge_segments_clear(scene, points[:], from_index, to_index) do continue
		cost := math.abs(a.y - lane) + math.abs(d.y - lane)
		if cost < best_cost {best = lane; best_cost = cost}
	}
	return best, best_cost < f32(1e9)
}

graph_edge_back_lane :: proc(scene: string, a, d: Vec2, from_index, to_index: int) -> (f32, bool) {
	from, to :=
		graph_node_rect(graph_document.nodes[from_index]),
		graph_node_rect(graph_document.nodes[to_index])
	candidates := [2]f32{min(from.y, to.y) - 22, max(from.y + from.h, to.y + to.h) + 22}
	best, best_cost :=
		f32(0),
		f32(
			1e9,
		); canvas := graph_canvas_rect(); right_x := min(a.x + 28, canvas.x + canvas.w - 4); left_x := max(d.x - 28, canvas.x + 4)
	for lane in candidates {
		if lane < canvas.y + 10 || lane > canvas.y + canvas.h - 10 do continue
		points := [4]Vec2{a, {right_x, lane}, {left_x, lane}, d}
		if !graph_edge_segments_clear(scene, points[:], from_index, to_index) do continue
		cost := math.abs(a.y - lane) + math.abs(d.y - lane)
		if cost < best_cost {best = lane; best_cost = cost}
	}
	return best, best_cost < f32(1e9)
}

vk_graph_arrow :: proc(r: ^Vulkan_Backend, tip, tangent: Vec2, color: [4]u8, size: f32 = 10) {
	length := f32(
		math.sqrt(f64(tangent.x * tangent.x + tangent.y * tangent.y)),
	); if length < .01 do return
	d := Vec2 {
		tangent.x / length,
		tangent.y / length,
	}; n := Vec2{-d.y, d.x}; base := Vec2{tip.x - d.x * size, tip.y - d.y * size}; half := size * .45
	vulkan_ui_triangle(
		r,
		tip,
		{base.x + n.x * half, base.y + n.y * half},
		{base.x - n.x * half, base.y - n.y * half},
		color,
	)
}

graph_edge_cubic_tangent :: proc(a, b, c, d: Vec2, t: f32) -> Vec2 {
	u := 1 - t
	return {
		3 * u * u * (b.x - a.x) + 6 * u * t * (c.x - b.x) + 3 * t * t * (d.x - c.x),
		3 * u * u * (b.y - a.y) + 6 * u * t * (c.y - b.y) + 3 * t * t * (d.y - c.y),
	}
}

vk_graph_direction_marker :: proc(r: ^Vulkan_Backend, point, tangent: Vec2, color: [4]u8) {
	// A single marker only appears on the active route. Its outline isolates a
	// clean silhouette without turning every wire into a repeated-arrow
	// diagram. An open chevron preserves the cable's continuity; a filled
	// triangle in the same highlight color reads as a gap instead of direction.
	length := f32(
		math.sqrt(f64(tangent.x * tangent.x + tangent.y * tangent.y)),
	); if length < .01 do return
	d := Vec2 {
		tangent.x / length,
		tangent.y / length,
	}; n := Vec2{-d.y, d.x}; back := Vec2{point.x - d.x * 9, point.y - d.y * 9}; wing_a, wing_b := Vec2{back.x + n.x * 5, back.y + n.y * 5}, Vec2{back.x - n.x * 5, back.y - n.y * 5}; outline := [4]u8{7, 10, 15, 245}
	vk_graph_aa_segment(
		r,
		wing_a,
		point,
		outline,
		5,
	); vk_graph_aa_segment(r, wing_b, point, outline, 5)
	vk_graph_aa_segment(
		r,
		wing_a,
		point,
		color,
		2,
	); vk_graph_aa_segment(r, wing_b, point, color, 2)
}

vk_graph_edge :: proc(
	r: ^Vulkan_Backend,
	scene: string,
	from_index, to_index, port_index: int,
	color: [4]u8,
	thickness: f32 = 2,
	direction_marker := false,
) {
	from_node, to_node := graph_document.nodes[from_index], graph_document.nodes[to_index]
	from_port, to_port := graph_port_rect(from_node, port_index), graph_input_rect(to_node)
	a := Vec2 {
		from_port.x + from_port.w * .5,
		from_port.y + from_port.h * .5,
	}; d := Vec2{to_port.x + to_port.w * .5, to_port.y + to_port.h * .5}; dx := d.x - a.x
	if dx > 2 && graph_edge_direct_clear(scene, a, d, from_index, to_index) {
		// Keep the body fluid, but reserve a clearly perpendicular lead at each
		// port so the connection meets both card edges at exactly 90 degrees.
		if math.abs(d.y - a.y) <
		   1 {vk_graph_aa_segment(r, a, d, color, thickness); if direction_marker do vk_graph_direction_marker(r, {a.x + (d.x - a.x) * .68, a.y + (d.y - a.y) * .68}, {d.x - a.x, d.y - a.y}, color); vk_graph_arrow(r, d, {1, 0}, color); return}
		lead := min(
			f32(14),
			dx * .18,
		); start, finish := Vec2{a.x + lead, a.y}, Vec2{d.x - lead, d.y}; h := max(f32(2), (finish.x - start.x) * .46); b, c := Vec2{start.x + h, start.y}, Vec2{finish.x - h, finish.y}; vk_graph_aa_segment(r, a, start, color, thickness); vk_graph_cubic(r, start, b, c, finish, color, thickness); vk_graph_aa_segment(r, finish, d, color, thickness); if direction_marker {t := f32(.68); point := graph_edge_cubic_point(start, b, c, finish, t); vk_graph_direction_marker(r, point, graph_edge_cubic_tangent(start, b, c, finish, t), color)}; vk_graph_arrow(r, d, {1, 0}, color); return
	}
	if dx > 2 {
		if lane_y, ok := graph_edge_local_lane(scene, a, d, from_index, to_index); ok {
			vk_graph_orthogonal_path(
				r,
				a,
				d,
				lane_y,
				color,
				thickness,
			); if direction_marker do vk_graph_direction_marker(r, {a.x + (d.x - a.x) * .68, lane_y}, {d.x - a.x, 0}, color); vk_graph_arrow(r, d, {1, 0}, color); return
		}
	}
	if dx <= 2 {
		if lane_y, ok := graph_edge_back_lane(scene, a, d, from_index, to_index); ok {
			canvas := graph_canvas_rect(

			); right_x := min(a.x + 28, canvas.x + canvas.w - 4); left_x := max(d.x - 28, canvas.x + 4); p1, p2 := Vec2{right_x, lane_y}, Vec2{left_x, lane_y}; span := p2.x - p1.x
			vk_graph_cubic(r, a, {right_x, a.y}, {p1.x, lane_y}, p1, color, thickness)
			vk_graph_cubic(
				r,
				p1,
				{p1.x + span * .28, p1.y},
				{p2.x - span * .28, p2.y},
				p2,
				color,
				thickness,
			)
			if direction_marker {b, c_mid := Vec2{p1.x + span * .28, p1.y}, Vec2{p2.x - span * .28, p2.y}; t := f32(.68); point := graph_edge_cubic_point(p1, b, c_mid, p2, t); vk_graph_direction_marker(r, point, graph_edge_cubic_tangent(p1, b, c_mid, p2, t), color)}
			c := Vec2 {
				left_x,
				d.y,
			}; vk_graph_cubic(r, p2, {p2.x, lane_y}, {c.x, d.y}, d, color, thickness); vk_graph_arrow(r, d, {d.x - c.x, d.y - c.y}, color); return
		}
	}
	// Back edges and obstructed forward edges use an outside lane. The two
	// boundary corridors form the useful part of the visibility graph here;
	// choose the shortest route deterministically.
	canvas := graph_canvas_rect(); top_y, bottom_y := canvas.y + 12, canvas.y + canvas.h - 12
	top_cost :=
		math.abs(a.y - top_y) +
		math.abs(
			d.y - top_y,
		); bottom_cost := math.abs(a.y - bottom_y) + math.abs(d.y - bottom_y); lane_y := top_cost <= bottom_cost ? top_y : bottom_y
	vk_graph_orthogonal_path(r, a, d, lane_y, color, thickness)
	if direction_marker do vk_graph_direction_marker(r, {a.x + (d.x - a.x) * .68, lane_y}, {d.x - a.x, 0}, color)
	vk_graph_arrow(r, d, {1, 0}, color)
}

vk_graph_edge_ports_foreground :: proc(
	r: ^Vulkan_Backend,
	from_index, to_index, port_index: int,
	color: [4]u8,
) {
	// Card bodies stay above routed wires, but the final few pixels cross above
	// their port blocks so ports read as sockets beneath a continuous cable.
	from_node, to_node := graph_document.nodes[from_index], graph_document.nodes[to_index]
	from_port, to_port := graph_port_rect(from_node, port_index), graph_input_rect(to_node)
	a := Vec2 {
		from_port.x + from_port.w * .5,
		from_port.y + from_port.h * .5,
	}; d := Vec2{to_port.x + to_port.w * .5, to_port.y + to_port.h * .5}
	vk_graph_aa_segment(
		r,
		{a.x - from_port.w * .5, a.y},
		{a.x + from_port.w * .5 + 2, a.y},
		color,
		2,
	)
	vk_graph_aa_segment(r, {d.x - to_port.w * .5 - 3, d.y}, {d.x + to_port.w * .5, d.y}, color, 2)
	vk_graph_arrow(r, d, {1, 0}, color)
}

graph_cubic_hit :: proc(point, a, b, c, d: Vec2) -> bool {
	previous := a
	for sample in 1 ..= 32 {current := graph_edge_cubic_point(a, b, c, d, f32(sample) / 32); if graph_point_segment_distance(point, previous, current) <= 8 do return true; previous = current}
	return false
}

graph_smooth_path_hit :: proc(point: Vec2, points: []Vec2) -> bool {
	for i in 0 ..< len(points) -
		1 {p0 := i > 0 ? points[i - 1] : points[i]; p1, p2 := points[i], points[i + 1]; p3 := i + 2 < len(points) ? points[i + 2] : points[i + 1]; b := Vec2{p1.x + (p2.x - p0.x) / 6, p1.y + (p2.y - p0.y) / 6}; c := Vec2{p2.x - (p3.x - p1.x) / 6, p2.y - (p3.y - p1.y) / 6}; if graph_cubic_hit(point, p1, b, c, p2) do return true}
	return false
}

graph_segment_hit :: proc(point, a, b: Vec2) -> bool {return(
		graph_point_segment_distance(point, a, b) <=
		8 \
	)}

graph_orthogonal_path_hit :: proc(point, a, d: Vec2, lane_y: f32) -> bool {
	lead := clamp(math.abs(d.x - a.x) * .18, f32(28), f32(54)); x1, x2 := a.x + lead, d.x - lead
	radius := min(
		f32(22),
		min(math.abs(lane_y - a.y) * .45, math.abs(lane_y - d.y) * .45),
	); radius = max(radius, f32(4))
	sy :=
		lane_y >= a.y ? f32(1) : f32(-1); ty := d.y >= lane_y ? f32(1) : f32(-1); k := f32(.55228475)
	if graph_segment_hit(point, a, {x1 - radius, a.y}) do return true
	if graph_cubic_hit(point, {x1 - radius, a.y}, {x1 - radius + k * radius, a.y}, {x1, lane_y - sy * radius - k * sy * radius}, {x1, lane_y - sy * radius}) do return true
	if graph_segment_hit(point, {x1, lane_y - sy * radius}, {x1, lane_y}) || graph_segment_hit(point, {x1, lane_y}, {x2, lane_y}) || graph_segment_hit(point, {x2, lane_y}, {x2, lane_y + ty * radius}) do return true
	if graph_cubic_hit(point, {x2, lane_y + ty * radius}, {x2, lane_y + ty * radius + k * ty * radius}, {x2 + radius - k * radius, d.y}, {x2 + radius, d.y}) do return true
	return graph_segment_hit(point, {x2 + radius, d.y}, d)
}

graph_rendered_edge_hit :: proc(
	point: Vec2,
	scene: string,
	from_index, to_index, port_index: int,
) -> bool {
	from_node, to_node :=
		graph_document.nodes[from_index],
		graph_document.nodes[to_index]; from_port, to_port := graph_port_rect(from_node, port_index), graph_input_rect(to_node)
	a := Vec2 {
		from_port.x + from_port.w * .5,
		from_port.y + from_port.h * .5,
	}; d := Vec2{to_port.x + to_port.w * .5, to_port.y + to_port.h * .5}; dx := d.x - a.x
	if dx > 2 &&
	   graph_edge_direct_clear(
		   scene,
		   a,
		   d,
		   from_index,
		   to_index,
	   ) {if math.abs(d.y - a.y) < 1 do return graph_segment_hit(point, a, d); lead := min(f32(14), dx * .18); start, finish := Vec2{a.x + lead, a.y}, Vec2{d.x - lead, d.y}; h := max(f32(2), (finish.x - start.x) * .46); if graph_segment_hit(point, a, start) || graph_segment_hit(point, finish, d) do return true; return graph_cubic_hit(point, start, {start.x + h, start.y}, {finish.x - h, finish.y}, finish)}
	if dx >
	   2 {if lane_y, ok := graph_edge_local_lane(scene, a, d, from_index, to_index); ok do return graph_orthogonal_path_hit(point, a, d, lane_y)}
	if dx <=
	   2 {if lane_y, ok := graph_edge_back_lane(scene, a, d, from_index, to_index); ok {canvas := graph_canvas_rect(); right_x := min(a.x + 28, canvas.x + canvas.w - 4); left_x := max(d.x - 28, canvas.x + 4); p1, p2 := Vec2{right_x, lane_y}, Vec2{left_x, lane_y}; span := p2.x - p1.x; if graph_cubic_hit(point, a, {right_x, a.y}, {p1.x, lane_y}, p1) do return true; if graph_cubic_hit(point, p1, {p1.x + span * .28, p1.y}, {p2.x - span * .28, p2.y}, p2) do return true; return graph_cubic_hit(point, p2, {p2.x, lane_y}, {left_x, d.y}, d)}}
	canvas := graph_canvas_rect(

	); top_y, bottom_y := canvas.y + 12, canvas.y + canvas.h - 12; top_cost := math.abs(a.y - top_y) + math.abs(d.y - top_y); bottom_cost := math.abs(a.y - bottom_y) + math.abs(d.y - bottom_y); lane_y := top_cost <= bottom_cost ? top_y : bottom_y; return graph_orthogonal_path_hit(point, a, d, lane_y)
}

vk_draw_graph_node :: proc(r: ^Vulkan_Backend, node: ^Graph_Node, index: int) {
	box := graph_node_rect(
		node^,
	); accent := graph_kind_color(node.beat.kind); selected := graph_is_selected(index); zoom := graph_state.zoom
	header_h := min(box.h, f32(24) * zoom); body_y := box.y + header_h
	vulkan_ui_rect(r, box.x + 3, box.y + 4, box.w, box.h, {0, 0, 0, 88})
	vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {24, 31, 40, 255})
	vulkan_ui_outline(
		r,
		box.x,
		box.y,
		box.w,
		box.h,
		selected ? accent : [4]u8{69, 80, 94, 255},
		selected ? 3 : 1,
	)
	vulkan_ui_rect(r, box.x, box.y, 4 * zoom, box.h, accent)
	vulkan_ui_rect(r, box.x, box.y, box.w, header_h, {31, 39, 49, 255})
	vulkan_ui_rect(r, box.x, body_y, box.w, 1, accent)
	vk_editor_text(
		r,
		box.x + 10 * zoom,
		box.y + 6 * zoom,
		graph_kind_label(node.beat.kind),
		accent,
		.70 * zoom,
	)
	id := node.beat.id; if len(id) > 14 do id = id[:14]
	id_width := f32(utf8_glyph_count(id)) * COURIER_CELL_WIDTH * .70 * zoom
	vk_editor_text(
		r,
		max(box.x + 62 * zoom, box.x + box.w - id_width - 9 * zoom),
		box.y + 7 * zoom,
		id,
		{174, 184, 196, 255},
		.70 * zoom,
	)
	if !node.collapsed {
		preview :=
			node.beat.text; if preview == "" do preview = node.beat.summary; if preview == "" do preview = node.beat.speaker; if preview == "" do preview = node.beat.camera
		preview_limit :=
			node.beat.kind == "choice" ? 10 : 14; if len(preview) > preview_limit do preview = preview[:preview_limit]
		if preview != "" do vk_editor_text(r, box.x + 10 * zoom, body_y + 10 * zoom, preview, {178, 211, 220, 255}, .70 * zoom)
	}
	input := graph_input_rect(
		node^,
	); vulkan_ui_rect(r, input.x, input.y, input.w, input.h, {214, 222, 231, 255}); vulkan_ui_outline(r, input.x, input.y, input.w, input.h, {92, 105, 120, 255}, 1)
	for port_index in 0 ..< graph_output_count(&node.beat) {
		port, choice := graph_output_port(
			&node.beat,
			port_index,
		); port_box := graph_port_rect(node^, port_index); port_color := graph_port_color(port)
		vulkan_ui_rect(r, port_box.x, port_box.y, port_box.w, port_box.h, port_color)
		label :=
			port == .Choice && choice >= 0 && choice < len(node.beat.choice_labels) ? node.beat.choice_labels[choice] : strings.to_upper(fmt.tprintf("%v", port)); if len(label) > 8 do label = label[:8]
		label_width :=
			f32(utf8_glyph_count(label)) *
			COURIER_CELL_WIDTH *
			.70 *
			zoom; label_x := port_box.x - label_width - 6 * zoom
		vulkan_ui_rect(
			r,
			label_x - 4 * zoom,
			port_box.y - 3 * zoom,
			label_width + 7 * zoom,
			port_box.h + 6 * zoom,
			{20, 26, 34, 230},
		)
		vk_editor_text(r, label_x, port_box.y + 1 * zoom, label, port_color, .70 * zoom)
	}
}

graph_node_screen_visible :: proc(node: Graph_Node) -> bool {box := graph_node_rect(node)
	canvas := graph_canvas_rect()
	return graph_rects_overlap(box, {canvas.x - 12, canvas.y - 12, canvas.w + 24, canvas.h + 24})}
graph_edge_screen_visible :: proc(from_node, to_node: Graph_Node) -> bool {a, b :=
		graph_node_rect(from_node), graph_node_rect(to_node)
	bounds := Rect {
		min(a.x, b.x) - 64,
		min(a.y, b.y) - 64,
		max(a.x + a.w, b.x + b.w) - min(a.x, b.x) + 128,
		max(a.y + a.h, b.y + b.h) - min(a.y, b.y) + 128,
	}
	return graph_rects_overlap(bounds, graph_canvas_rect())}

vk_graph_endpoint_emphasis :: proc(r: ^Vulkan_Backend, edge: Graph_Edge_Selection, color: [4]u8) {
	if !edge.active || edge.node < 0 || edge.node >= graph_document.node_count do return
	source := &graph_document.nodes[edge.node]; target := graph_port_target(&source.beat, edge.port, edge.choice_index); if target == nil do return
	to := graph_node_index(source.beat.scene, target^); if to < 0 do return
	port_index := -1; for i in 0 ..< graph_output_count(&source.beat) {port, choice := graph_output_port(&source.beat, i); if port == edge.port && choice == edge.choice_index {port_index = i; break}}
	if port_index < 0 do return
	from_box, to_box :=
		graph_port_rect(source^, port_index),
		graph_input_rect(graph_document.nodes[to]); boxes := [2]Rect{from_box, to_box}
	for box in boxes {vulkan_ui_outline(
			r,
			box.x - 5,
			box.y - 5,
			box.w + 10,
			box.h + 10,
			{color[0], color[1], color[2], 80},
			3,
		)
		vulkan_ui_outline(r, box.x - 2, box.y - 2, box.w + 4, box.h + 4, color, 2)}
	arrow_size := clamp(
		f32(8) * graph_state.zoom,
		f32(6),
		f32(9),
	); tip := Vec2{to_box.x - 9, to_box.y + to_box.h * .5}; vk_graph_arrow(r, tip, {1, 0}, {7, 10, 15, 235}, arrow_size + 3); vk_graph_arrow(r, tip, {1, 0}, color, arrow_size)
}

graph_edge_footer_id :: proc(id: string) -> string {
	// Node IDs are ASCII by validation. Preserve both distinguishing ends while
	// bounding the active-route label before the fixed Search controls.
	if len(id) <= 13 do return id
	return fmt.tprintf("%s…%s", id[:6], id[len(id) - 6:])
}

Graph_Choice_Icon :: enum {
	Edit_Id,
	Duplicate,
	Delete,
	Drag_Handle,
}

vk_graph_choice_icon_button :: proc(
	r: ^Vulkan_Backend,
	box: Rect,
	icon: Graph_Choice_Icon,
	active := false,
) {
	vk_graph_button(
		r,
		box,
		"",
		active,
	); c := UI_INK_STRONG; cx, cy := box.x + box.w * .5, box.y + box.h * .5
	switch icon {
	case .Edit_Id:
		// Tag silhouette: stable IDs name authored choice branches.
		vulkan_ui_outline(
			r,
			cx - 8,
			cy - 5,
			12,
			10,
			c,
			2,
		); vk_graph_aa_segment(r, {cx + 4, cy - 5}, {cx + 9, cy}, c, 2); vk_graph_aa_segment(r, {cx + 9, cy}, {cx + 4, cy + 5}, c, 2); vulkan_ui_rect(r, cx - 5, cy - 1, 2, 2, c)
	case .Duplicate:
		vulkan_ui_outline(r, cx - 6, cy - 6, 9, 10, c, 2)
		vulkan_ui_outline(r, cx - 2, cy - 2, 9, 10, c, 2)
	case .Delete:
		vulkan_ui_outline(r, cx - 6, cy - 4, 12, 11, c, 2)
		vulkan_ui_rect(r, cx - 8, cy - 8, 16, 2, c)
		vulkan_ui_rect(r, cx - 3, cy - 10, 6, 2, c)
		vulkan_ui_rect(r, cx - 2, cy - 1, 2, 6, c)
	case .Drag_Handle:
		for row in 0 ..< 3 do for column in 0 ..< 2 do vulkan_ui_rect(r, cx - 5 + f32(column) * 8, cy - 5 + f32(row) * 5, 3, 3, c)
	}
}

vk_graph_choice_tooltip :: proc(r: ^Vulkan_Backend, box: Rect, label: string) {
	if label == "" do return; width := f32(utf8_glyph_count(label)) * 6 + 18; x := min(box.x + box.w - width, f32(1188) - width); y := box.y + box.h + 4
	vulkan_ui_rect(
		r,
		x + 3,
		y + 3,
		width,
		24,
		UI_SHADOW,
	); vulkan_ui_rect(r, x, y, width, 24, {24, 31, 40, 255}); vulkan_ui_outline(r, x, y, width, 24, UI_ACCENT, 1); vk_editor_text(r, x + 9, y + 7, label, UI_INK_STRONG, .28)
}

vk_draw_graph_help :: proc(r: ^Vulkan_Backend) {vulkan_ui_rect(
		r,
		272,
		112,
		656,
		492,
		{20, 27, 35, 250},
	)
	vulkan_ui_outline(r, 272, 112, 656, 492, {102, 205, 235, 255}, 3)
	vk_editor_text(r, 304, 140, "DIALOGUE GRAPH SHORTCUTS", {255, 218, 112, 255}, .72)
	vk_editor_text(r, 746, 142, "F1 TO CLOSE", {170, 218, 228, 255}, .42)
	columns := [3][6]string {
		{
			"WHEEL  ZOOM AT CURSOR",
			"MIDDLE DRAG  PAN",
			"F  FRAME SELECTION",
			"CTRL/CMD F  SEARCH",
			"[ / ]  SEARCH RESULTS",
			"MINIMAP CLICK  NAVIGATE",
		},
		{
			"CTRL/CMD Z  UNDO",
			"CTRL/CMD SHIFT Z  REDO",
			"CTRL/CMD S  SAVE",
			"CTRL/CMD C/V  COPY/PASTE",
			"CTRL/CMD D  DUPLICATE",
			"DELETE  REMOVE",
		},
		{
			"SHIFT A  QUICK ADD",
			"DRAG PORT  CONNECT",
			"DRAG EMPTY  MARQUEE",
			"SHIFT CLICK  MULTISELECT",
			"LAYOUT  SELECTION/SCENE",
			"PLAY  SELECTED/ENTRY",
		},
	}
	heads := [3]string{"NAVIGATE", "EDIT", "AUTHOR"}
	for 	column in 0 ..< 3 {x := f32(304 + column * 202); vk_editor_text(
			r,
			x,
			188,
			heads[column],
			{102, 205, 235, 255},
			.48,
		)
		for row in 0 ..< 6 do vk_editor_text(r, x, 224 + f32(row) * 42, columns[column][row], {235, 237, 238, 255}, .34)}
	vk_editor_text(
		r,
		304,
		526,
		"Graph, Script, Localization, Conditions, and Effects share one undoable document.",
		{117, 229, 169, 255},
		.34,
	)
	vk_editor_text(
		r,
		304,
		558,
		"Check opens diagnostics; warnings never disable Play.",
		{205, 211, 218, 255},
		.34,
	)}

vk_draw_graph_overlay :: proc(r: ^Vulkan_Backend, g: ^Game) {
	vulkan_ui_rect(
		r,
		0,
		0,
		1200,
		720,
		{10, 13, 18, 255},
	); vulkan_ui_rect(r, 0, 0, 1200, 58, {22, 28, 36, 255}); vulkan_ui_rect(r, 0, 58, 214, 662, {16, 21, 28, 255}); vulkan_ui_rect(r, 950, 58, 250, 662, {18, 23, 30, 255}); vulkan_ui_rect(r, 214, 676, 736, 44, {20, 26, 33, 255})
	if graph_state.view ==
	   .Graph {vk_button(r, {966, 492, 68, 28}, "DUP SCN"); vk_button(r, {1040, 492, 68, 28}, graph_state.confirm == .Delete_Scene ? "CONFIRM" : "DEL SCN", graph_state.confirm == .Delete_Scene); vk_button(r, {1114, 492, 34, 28}, "UP"); vk_button(r, {1152, 492, 34, 28}, "DN")}
	search_label :=
		graph_state.search_query == "" ? "SEARCH" : graph_state.search_query; vk_button(r, graph_search_rect(), search_label); vk_button(r, graph_search_next_rect(), "NEXT")
	if graph_state.autosave_status != "" do vk_editor_text(r, 480, 690, graph_state.autosave_status, graph_state.autosave_status == "AUTOSAVE FAILED" ? [4]u8{255, 144, 119, 255} : [4]u8{170, 218, 228, 255}, .30)
	if graph_state.view == .Graph && graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count do vk_button(r, {966, 532, 104, 28}, graph_document.nodes[graph_state.selected_node].collapsed ? "EXPAND" : "COLLAPSE")
	if graph_state.view == .Graph &&
	   graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {field := graph_inspector_field(); beat := &graph_document.nodes[graph_state.selected_node].beat; vk_graph_button(r, {958, 660, 38, 28}, "<"); vk_graph_button(r, {1000, 660, 150, 28}, fmt.tprintf("%s  %s", graph_inspector_field_label(field), graph_inspector_field_value(beat, field))); vk_graph_button(r, {1154, 660, 38, 28}, ">")} else if graph_state.view == .Graph && graph_state.active_scene >= 0 && graph_state.active_scene < graph_document.scene_count {field := graph_scene_inspector_field(); scene := &graph_document.scenes[graph_state.active_scene].scene; vk_graph_button(r, {958, 660, 38, 28}, "<"); vk_graph_button(r, {1000, 660, 150, 28}, fmt.tprintf("%s  %s", graph_scene_inspector_label(field), graph_scene_inspector_value(scene, field))); vk_graph_button(r, {1154, 660, 38, 28}, ">")}
	if graph_state.view == .Graph &&
	   graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {beat := graph_document.nodes[graph_state.selected_node].beat; if beat.kind == "stage" {vk_graph_button(r, {966, 568, 220, 26}, fmt.tprintf("ACTOR  %s", beat.actor)); vk_graph_button(r, {966, 598, 220, 26}, fmt.tprintf("ANIMATION  %s", beat.animation)); vk_graph_button(r, {966, 628, 220, 26}, fmt.tprintf("UI  %s", beat.ui))} else {vk_graph_button(r, {966, 568, 220, 26}, fmt.tprintf("CONDITION  %s", beat.condition_id)); vk_graph_button(r, {966, 598, 220, 26}, fmt.tprintf("EFFECTS  %s", graph_join_strings(beat.effect_ids))); if beat.kind == "selector" || beat.kind == "objective" || beat.kind == "effect" || beat.kind == "interaction" do vk_graph_button(r, {966, 628, 220, 26}, fmt.tprintf("DOMAIN  %s", beat.domain_ref))}}
	vk_graph_ui_text(
		r,
		16,
		20,
		"GRAPH MODE",
		{255, 218, 112, 255},
		.82,
	); active := graph_active_scene_id(); vk_editor_text(r, 16, 48, active, {170, 218, 228, 255}, .36)
	vk_graph_tab_bar(
		r,
		graph_tab_bar_rect(),
	); views := [5]string{"GRAPH", "SCRIPT", "LOCALIZE", "CONDITIONS", "EFFECTS"}; for label, i in views do vk_graph_tab(r, graph_view_tab_rect(i), label, graph_state.view == Graph_View(i)); vk_graph_button(r, {854, 14, 72, 34}, "SAVE"); vk_graph_button(r, {934, 14, 72, 34}, "CHECK"); vk_primary_button(r, {1014, 14, 68, 34}, "PLAY", graph_document.error_count == 0); vk_graph_button(r, {1090, 14, 96, 34}, "CLOSE")
	vk_graph_ui_text(
		r,
		14,
		72,
		"SCENES",
		{158, 168, 180, 255},
		.48,
	); scene_start := graph_scene_window_start(); for row in 0 ..< min(8, graph_document.scene_count - scene_start) {i := scene_start + row; scene_item := graph_document.scenes[i]; box := graph_scene_rect(row); if graph_state.active_scene == i do vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {49, 66, 82, 255}); vulkan_ui_rect(r, box.x + 5, box.y + 6, 4, 18, {82, 158, 220, 255}); label := strings.to_upper(scene_item.scene.id); if len(label) > 25 do label = label[:25]; vk_editor_text(r, box.x + 16, box.y + 9, label, graph_state.active_scene == i ? [4]u8{248, 247, 242, 255} : [4]u8{175, 183, 192, 255}, .36)}
	if graph_state.view ==
	   .Script {vk_draw_graph_script(r); return} else if graph_state.view == .Localization {vk_draw_graph_localization(r); if graph_state.selected_localization >= 0 && graph_state.selected_localization < graph_document.localization_count {note := graph_document.localizations[graph_state.selected_localization].note; if note == "" do note = "CLICK TO ADD TRANSLATOR NOTE"; vk_graph_button(r, {238, 618, 400, 24}, fmt.tprintf("NOTE  %s", note))}; return} else if graph_state.view == .Conditions {vk_draw_graph_conditions(r); vk_graph_button(r, {786, 610, 134, 28}, "DUPLICATE"); return} else if graph_state.view == .Effects {vk_draw_graph_effects(r); vk_graph_button(r, {786, 610, 134, 28}, "DUPLICATE"); return}
	vk_graph_button(
		r,
		{14, 356, 58, 28},
		"+SCENE",
	); vk_graph_button(r, {76, 356, 58, 28}, "FIT"); vk_graph_button(r, {138, 356, 68, 28}, "LAYOUT"); vk_graph_ui_text(r, 14, 390, "ADD NODE", {158, 168, 180, 255}, .42); kinds := [11]string{"line", "choice", "check", "stage", "interaction", "effect", "selector", "objective", "wait_event", "subscene", "end"}; for kind, i in kinds {box := graph_palette_rect(i); color := graph_kind_color(kind); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {25, 31, 40, 255}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, color, 2); vulkan_ui_rect(r, box.x, box.y, 5, box.h, color); label := strings.to_upper(kind); if kind == "wait_event" do label = "WAIT EVENT"; vk_editor_text(r, box.x + 10, box.y + 10, label, color, .30)}
	canvas := graph_canvas_rect(

	); vulkan_ui_rect(r, canvas.x, canvas.y, canvas.w, canvas.h, {12, 16, 22, 255}); for x := canvas.x; x < canvas.x + canvas.w; x += 24 do for y := canvas.y; y < canvas.y + canvas.h; y += 24 do vulkan_ui_rect(r, x, y, 1, 1, {76, 88, 102, 85})
	// Everything authored in graph space is clipped to the viewport. Route
	// lanes may travel beyond visible nodes, but must never paint over chrome.
	vulkan_ui_scissor(r, canvas.x, canvas.y, canvas.w, canvas.h)
	scene := graph_active_scene_id(

	); for &node, from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; for port_index in 0 ..< graph_output_count(&node.beat) {port, choice := graph_output_port(&node.beat, port_index); target := graph_port_target(&node.beat, port, choice); if target == nil || target^ == "" do continue; to_index := graph_node_index(scene, target^); if to_index < 0 || !graph_edge_screen_visible(node, graph_document.nodes[to_index]) do continue; vk_graph_edge(r, scene, from_index, to_index, port_index, {7, 10, 15, 238}, 6); color := graph_port_color(port); color[3] = 220; vk_graph_edge(r, scene, from_index, to_index, port_index, color)}}
	if graph_state.edge_hover.active &&
	   !graph_state.edge_drag.active &&
	   !graph_state.edge_selection.active {edge := graph_state.edge_hover; if edge.node >= 0 && edge.node < graph_document.node_count {source := &graph_document.nodes[edge.node]; target := graph_port_target(&source.beat, edge.port, edge.choice_index); if target != nil {to := graph_node_index(scene, target^); if to >= 0 {for port_index in 0 ..< graph_output_count(&source.beat) {port, choice := graph_output_port(&source.beat, port_index); if port == edge.port && choice == edge.choice_index {vk_graph_edge(r, scene, edge.node, to, port_index, {205, 238, 255, 255}, 4, true); break}}}}}}
	for &node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene == scene && graph_node_screen_visible(node) do vk_draw_graph_node(r, &node, i)}
	for &node, from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; for port_index in 0 ..< graph_output_count(&node.beat) {port, choice := graph_output_port(&node.beat, port_index); target := graph_port_target(&node.beat, port, choice); if target == nil || target^ == "" do continue; to_index := graph_node_index(scene, target^); if to_index < 0 || !graph_edge_screen_visible(node, graph_document.nodes[to_index]) do continue; color := graph_port_color(port); color[3] = 220; vk_graph_edge_ports_foreground(r, from_index, to_index, port_index, color)}}
	minimap := graph_minimap_rect(

	); vulkan_ui_rect(r, minimap.x, minimap.y, minimap.w, minimap.h, {7, 11, 16, 242}); vulkan_ui_outline(r, minimap.x, minimap.y, minimap.w, minimap.h, {102, 205, 235, 180}, 1)
	mini := graph_minimap_layout()
	if mini.valid {
		// Only authored graph-world data enters this pass. The minimap and other
		// editor overlays are never sampled or recursively represented.
		for &node, from_index in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; from_h := graph_node_world_height(node); for port_index in 0 ..< graph_output_count(&node.beat) {port, choice := graph_output_port(&node.beat, port_index); target := graph_port_target(&node.beat, port, choice); if target == nil || target^ == "" do continue; to_index := graph_node_index(scene, target^); if to_index < 0 do continue; count := max(1, graph_output_count(&node.beat)); from_world := Vec2{node.position.x + GRAPH_NODE_WIDTH, node.position.y + GRAPH_NODE_HEADER_HEIGHT + (f32(port_index) + .5) * (from_h - GRAPH_NODE_HEADER_HEIGHT) / f32(count)}; to_node := graph_document.nodes[to_index]; to_world := Vec2{to_node.position.x, to_node.position.y + GRAPH_NODE_HEADER_HEIGHT + (graph_node_world_height(to_node) - GRAPH_NODE_HEADER_HEIGHT) * .5}; a, b := graph_minimap_project(mini, from_world), graph_minimap_project(mini, to_world); edge_color := graph_port_color(port); edge_color[3] = 120; vk_graph_aa_segment(r, a, b, edge_color, 1)}}
		for node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue; p := graph_minimap_project(mini, node.position); w := max(f32(2), GRAPH_NODE_WIDTH * mini.scale); h := max(f32(2), graph_node_world_height(node) * mini.scale); color := graph_kind_color(node.beat.kind); fill := [4]u8{32, 40, 51, 255}; vulkan_ui_rect(r, p.x, p.y, w, h, fill); vulkan_ui_rect(r, p.x, p.y, max(f32(1), 2 * mini.scale), h, color); if graph_is_selected(i) do vulkan_ui_outline(r, p.x - 1, p.y - 1, w + 2, h + 2, {235, 244, 250, 255}, 1)}
		canvas := graph_canvas_rect(

		); view_a := graph_screen_to_world({canvas.x, canvas.y}); view_b := graph_screen_to_world({canvas.x + canvas.w, canvas.y + canvas.h}); view_min := Vec2{max(view_a.x, mini.world.x), max(view_a.y, mini.world.y)}; view_max := Vec2{min(view_b.x, mini.world.x + mini.world.w), min(view_b.y, mini.world.y + mini.world.h)}
		if view_max.x > view_min.x &&
		   view_max.y >
			   view_min.y {a, b := graph_minimap_project(mini, view_min), graph_minimap_project(mini, view_max); vulkan_ui_rect(r, a.x, a.y, b.x - a.x, b.y - a.y, {102, 205, 235, 22}); vulkan_ui_outline(r, a.x, a.y, b.x - a.x, b.y - a.y, {205, 238, 255, 230}, 1)}
	}
	if !graph_state.edge_selection.active do vk_graph_endpoint_emphasis(r, graph_state.edge_hover, {205, 238, 255, 255})
	if graph_state.edge_drag.active {edge := graph_state.edge_drag; color := graph_port_color(edge.port); a, d := edge.start, g.input.mouse_pos; span := math.abs(d.x - a.x); handle := clamp(span * .46, f32(32), f32(180)); direction := d.x >= a.x ? f32(1) : f32(-1); vk_graph_cubic(r, a, {a.x + handle * direction, a.y}, {d.x - handle * direction, d.y}, d, color, 3); for node in graph_document.nodes[:graph_document.node_count] do if node.beat.scene == scene && node.beat.id != graph_document.nodes[edge.node].beat.id {box := graph_input_rect(node); vulkan_ui_outline(r, box.x - 3, box.y - 3, box.w + 6, box.h + 6, color, 2)}}
	if graph_state.edge_selection.active &&
	   !graph_state.edge_drag.active {edge := graph_state.edge_selection; if edge.node >= 0 && edge.node < graph_document.node_count {source := graph_document.nodes[edge.node]; target := graph_port_target(&source.beat, edge.port, edge.choice_index); if target != nil {to := graph_node_index(scene, target^); if to >= 0 {selected_port := -1; for j in 0 ..< graph_output_count(&source.beat) {port, choice := graph_output_port(&source.beat, j); if port == edge.port && choice == edge.choice_index {selected_port = j; break}}; if selected_port >= 0 do vk_graph_edge(r, scene, edge.node, to, selected_port, {255, 245, 190, 255}, 5, true)}}}}
	if graph_state.edge_selection.active && !graph_state.edge_drag.active do vk_graph_endpoint_emphasis(r, graph_state.edge_selection, {255, 245, 190, 255})
	if graph_state.marquee.active {box := graph_rect_normalized(graph_state.marquee.start, graph_state.marquee.current); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {82, 158, 220, 35}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {119, 190, 230, 230}, 1)}
	if graph_state.quick_add {x, y := graph_state.quick_add_at.x, graph_state.quick_add_at.y; vulkan_ui_rect(r, x, y, 176, 34 + f32(len(kinds)) * 31, {24, 31, 40, 255}); vulkan_ui_outline(r, x, y, 176, 34 + f32(len(kinds)) * 31, {255, 218, 112, 255}, 2); vk_graph_ui_text(r, x + 10, y + 11, "QUICK ADD", {255, 218, 112, 255}, .42); for kind, i in kinds {box := graph_quick_rect(i); color := graph_kind_color(kind); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, i == graph_state.quick_add_selected ? [4]u8{55, 66, 80, 255} : [4]u8{31, 39, 49, 255}); vulkan_ui_rect(r, box.x, box.y, 5, box.h, color); vk_editor_text(r, box.x + 13, box.y + 9, strings.to_upper(kind), color, .38)}}
	vulkan_ui_scissor_reset(r)
	inspector_view := graph_inspector_viewport(

	); inspector_y := graph_state.inspector_scroll; if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count && graph_document.nodes[graph_state.selected_node].beat.kind == "choice" do inspector_y = 0; vulkan_ui_scissor(r, inspector_view.x, inspector_view.y, inspector_view.w, inspector_view.h); inspector_bottom := f32(0)
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node <
		   graph_document.node_count {node := graph_document.nodes[graph_state.selected_node]; color := graph_kind_color(node.beat.kind); vk_graph_ui_text(r, 966, 82 - inspector_y, "NODE INSPECTOR", color, .54); id_bottom := vk_editor_text_wrapped(r, 966, 112 - inspector_y, 222, node.beat.id, {248, 247, 242, 255}, .42); vk_editor_text(r, 966, 142 - inspector_y, fmt.tprintf("TYPE  %s", strings.to_upper(node.beat.kind)), color, .38); speaker_bottom := vk_editor_text_wrapped(r, 966, 174 - inspector_y, 222, fmt.tprintf("SPEAKER  %s", node.beat.speaker), {205, 211, 218, 255}, .34); text_bottom := vk_editor_text_wrapped(r, 966, 204 - inspector_y, 222, fmt.tprintf("TEXT  %s", node.beat.text), {170, 218, 228, 255}, .34); summary_bottom := vk_editor_text_wrapped(r, 966, 274 - inspector_y, 222, fmt.tprintf("SUMMARY  %s", node.beat.summary), {205, 211, 218, 255}, .31); vk_editor_text(r, 966, 328 - inspector_y, fmt.tprintf("DURATION %.2f", node.beat.duration), {205, 211, 218, 255}, .31); picker_a := node.beat.kind == "stage" ? fmt.tprintf("CAMERA  %s", node.beat.camera) : node.beat.kind == "wait_event" ? fmt.tprintf("TRIGGER EVENT  %s", node.beat.event_id) : node.beat.kind == "check" ? fmt.tprintf("CLUE  %s", node.beat.clue) : fmt.tprintf("INTERACTION  %s", node.beat.interaction); picker_b := node.beat.kind == "stage" ? fmt.tprintf("STAGING  %s", node.beat.actor_mark) : fmt.tprintf("UI  %s", node.beat.ui); picker_a_bottom := vk_editor_text_wrapped(r, 966, 369 - inspector_y, 222, picker_a, {65, 194, 210, 255}, .31); picker_b_bottom := vk_editor_text_wrapped(r, 966, 399 - inspector_y, 222, picker_b, {117, 229, 169, 255}, .31); inspector_bottom = max(max(max(id_bottom, speaker_bottom), max(text_bottom, summary_bottom)), max(picker_a_bottom, picker_b_bottom)) + inspector_y; vk_graph_button(r, {966, 440, 102, 30}, "SET ENTRY"); vk_graph_button(r, {1078, 440, 110, 30}, node.beat.blocking ? "BLOCKING" : "LEAVEABLE", node.beat.blocking); _, has_spatial := graph_node_spatial_marker(&node); vk_graph_button(r, {966, 530, 222, 30}, has_spatial ? "OPEN IN BUILD MODE" : "NO SPATIAL BINDING", false)} else {vk_graph_ui_text(r, 966, 82 - inspector_y, "SCENE INSPECTOR", {255, 218, 112, 255}, .54); if graph_state.active_scene >= 0 {scene_data := graph_document.scenes[graph_state.active_scene].scene; id_bottom := vk_editor_text_wrapped(r, 966, 114 - inspector_y, 222, scene_data.id, {248, 247, 242, 255}, .38); entry_bottom := vk_editor_text_wrapped(r, 966, 144 - inspector_y, 222, fmt.tprintf("ENTRY  %s", scene_data.entry), {82, 158, 220, 255}, .34); source_bottom := vk_editor_text_wrapped(r, 966, 174 - inspector_y, 222, fmt.tprintf("SOURCE  %s", scene_data.source), {205, 211, 218, 255}, .34); inspector_bottom = max(id_bottom, max(entry_bottom, source_bottom)) + inspector_y}}
	graph_state.inspector_scroll_max = max(
		0,
		inspector_bottom - (inspector_view.y + inspector_view.h - 8),
	); if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count && graph_document.nodes[graph_state.selected_node].beat.kind == "choice" do graph_state.inspector_scroll_max = 0; graph_state.inspector_scroll = clamp(graph_state.inspector_scroll, 0, graph_state.inspector_scroll_max); vulkan_ui_scissor_reset(r); if graph_state.selected_node >= 0 && graph_state.selected_node < graph_document.node_count && graph_document.nodes[graph_state.selected_node].beat.kind != "choice" {node := graph_document.nodes[graph_state.selected_node]; vk_graph_button(r, {966, 440, 102, 30}, "SET ENTRY"); vk_graph_button(r, {1078, 440, 110, 30}, node.beat.blocking ? "BLOCKING" : "LEAVEABLE", node.beat.blocking); _, has_spatial := graph_node_spatial_marker(&node); vk_graph_button(r, {966, 530, 222, 30}, has_spatial ? "OPEN IN BUILD MODE" : "NO SPATIAL BINDING", false)}; if graph_state.inspector_scroll_max > 0 {track := Rect{1192, inspector_view.y + 4, 3, inspector_view.h - 8}; thumb_h := max(f32(28), track.h * track.h / (track.h + graph_state.inspector_scroll_max)); thumb_y := track.y + (track.h - thumb_h) * (graph_state.inspector_scroll / graph_state.inspector_scroll_max); vulkan_ui_rect(r, track.x, track.y, track.w, track.h, {56, 66, 78, 180}); vulkan_ui_rect(r, track.x, thumb_y, track.w, thumb_h, {102, 205, 235, 240})}
	if graph_state.selected_node >= 0 &&
	   graph_state.selected_node < graph_document.node_count &&
	   graph_document.nodes[graph_state.selected_node].beat.kind ==
		   "choice" {beat := graph_document.nodes[graph_state.selected_node].beat; vulkan_ui_rect(r, 958, 156, 234, 326, {18, 23, 30, 255}); vk_graph_ui_text(r, 966, 162, "PLAYER CHOICES", {226, 173, 64, 255}, .40); tooltip := ""; tooltip_box := Rect{}; page_count := max(1, (len(beat.choice_labels) + 4) / 5); choice_start := clamp(graph_state.choice_page, 0, page_count - 1) * 5; choice_end := min(choice_start + 5, len(beat.choice_labels)); for i in choice_start ..< choice_end {row := i - choice_start; label := beat.choice_labels[i]; y := f32(184 + row * 48); dragging := graph_state.choice_reorder.active && graph_state.choice_reorder.node == graph_state.selected_node && graph_state.choice_reorder.index == i; if dragging do vulkan_ui_rect(r, 956, y - 2, 234, 48, {49, 66, 82, 255}); vulkan_ui_rect(r, 958, y, 122, 24, {28, 35, 44, 255}); vulkan_ui_outline(r, 958, y, 122, 24, dragging ? UI_ACCENT : [4]u8{226, 173, 64, 180}, dragging ? 2 : 1); display := label; if len(display) > 14 do display = display[:14]; vk_editor_text(r, 966, y + 8, display, {248, 247, 242, 255}, .28); id_box, duplicate_box, delete_box := Rect{1082, y, 38, 24}, Rect{1122, y, 26, 24}, Rect{1152, y, 36, 24}; handle_box := Rect{1122, y + 25, 66, 20}; vk_graph_choice_icon_button(r, id_box, .Edit_Id); vk_graph_choice_icon_button(r, duplicate_box, .Duplicate); vk_graph_choice_icon_button(r, delete_box, .Delete); condition := beat.choice_conditions[i]; if condition == "" do condition = "ALWAYS"; detail := fmt.tprintf("%s · %s", beat.choice_ids[i], condition); if len(detail) > 22 do detail = detail[:22]; vk_editor_text(r, 968, y + 29, detail, {205, 153, 235, 255}, .22); vk_graph_choice_icon_button(r, handle_box, .Drag_Handle, dragging); if contains(id_box, g.input.mouse_pos) {tooltip = "EDIT CHOICE ID"; tooltip_box = id_box} else if contains(duplicate_box, g.input.mouse_pos) {tooltip = "DUPLICATE CHOICE"; tooltip_box = duplicate_box} else if contains(delete_box, g.input.mouse_pos) {tooltip = "DELETE CHOICE"; tooltip_box = delete_box} else if contains(handle_box, g.input.mouse_pos) {tooltip = dragging ? "RELEASE TO PLACE" : "DRAG TO REORDER"; tooltip_box = handle_box}}; vk_graph_button(r, {966, 430, 104, 28}, "+ CHOICE"); vk_graph_button(r, {1076, 460, 52, 24}, "PREV"); vk_graph_button(r, {1132, 460, 52, 24}, fmt.tprintf("%d/%d", graph_state.choice_page + 1, page_count)); vk_graph_choice_tooltip(r, tooltip_box, tooltip)}
	if graph_state.diagnostics_visible {vulkan_ui_rect(r, 706, 70, 486, 366, {8, 12, 18, 248}); vulkan_ui_outline(r, 706, 70, 486, 366, {255, 218, 112, 255}, 2); vk_graph_ui_text(r, 724, 80, "GRAPH DIAGNOSTICS", {255, 218, 112, 255}, .48); for item, i in graph_document.diagnostics[:min(8, graph_document.diagnostic_count)] {box := Rect{720, 104 + f32(i) * 40, 462, 36}; fill := item.severity == .Error ? [4]u8{67, 31, 34, 255} : [4]u8{58, 50, 27, 255}; vulkan_ui_rect(r, box.x, box.y, box.w, box.h, fill); title := fmt.tprintf("%s · %s", item.scene_id, item.node_id); vk_editor_text(r, box.x + 8, box.y + 6, title, {248, 247, 242, 255}, .27); message := item.message; if len(message) > 58 do message = message[:58]; vk_editor_text(r, box.x + 8, box.y + 20, message, item.severity == .Error ? [4]u8{255, 144, 119, 255} : [4]u8{255, 218, 112, 255}, .25)}}
	if graph_state.field_edit.active {box := graph_edit_rect(); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {8, 12, 18, 255}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {255, 218, 112, 255}, 2); text := graph_edit_text(); cell := f32(COURIER_CELL_WIDTH * .38); if ui.gui_text_edit_has_selection(&g.gui) {selection_start, selection_end := ui.gui_text_edit_selection(&g.gui); selection_x := box.x + 8 + f32(utf8_glyph_count(string(graph_state.field_edit.buffer[:selection_start]))) * cell; selection_w := max(f32(2), f32(utf8_glyph_count(string(graph_state.field_edit.buffer[selection_start:selection_end]))) * cell); vulkan_ui_rect(r, selection_x, box.y + 7, selection_w, 24, {82, 158, 220, 105})}; vk_editor_text(r, box.x + 8, box.y + 12, text, {248, 247, 242, 255}, .38); caret_x := box.x + 8 + f32(utf8_glyph_count(string(graph_state.field_edit.buffer[:g.gui.text_edit_caret]))) * cell; vulkan_ui_rect(r, caret_x, box.y + 8, 2, 22, {255, 218, 112, 255}); if graph_state.field_edit.multiline do vk_editor_text(r, box.x, box.y + 44, "CMD/CTRL+ENTER TO COMMIT", {135, 142, 151, 255}, .30); if graph_state.field_edit.error != "" do vk_editor_text(r, box.x, box.y + 58, graph_state.field_edit.error, {255, 144, 119, 255}, .32)}
	if graph_state.field_edit.active &&
	   graph_state.field_edit.picker {count := graph_picker_count(g, graph_state.field_edit.field); vk_editor_text(r, 966, 91, "TYPE TO FILTER  ·  ↑↓ OR WHEEL", {170, 218, 228, 255}, .28); if count == 0 do vk_editor_text(r, 966, 153, "NO MATCHING AUTHORED TARGETS", {255, 190, 92, 255}, .30); for i in 0 ..< 8 {candidate_index := graph_state.field_edit.picker_offset + i; label := graph_picker_label(g, graph_state.field_edit.field, candidate_index); if label == "" do break; box := graph_picker_rect(i); vulkan_ui_rect(r, box.x, box.y, box.w, box.h, candidate_index == graph_state.field_edit.picker_selected ? [4]u8{55, 66, 80, 255} : [4]u8{20, 27, 36, 255}); vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {76, 88, 102, 255}, 1); if len(label) > 31 do label = label[:31]; vk_editor_text(r, box.x + 9, box.y + 9, label, {205, 225, 232, 255}, .31)}; if count > 8 do vk_editor_text(r, 966, 392, fmt.tprintf("%d OF %d  ·  SCROLL FOR MORE", graph_state.field_edit.picker_selected + 1, count), {170, 218, 228, 255}, .28)}
	vk_editor_text(
		r,
		230,
		690,
		fmt.tprintf(
			"%d NODES  ·  %d ERRORS  ·  %d WARNINGS",
			graph_document.node_count,
			graph_document.error_count,
			graph_document.diagnostic_count - graph_document.error_count,
		),
		graph_document.error_count > 0 ? [4]u8{255, 144, 119, 255} : [4]u8{117, 229, 169, 255},
		.42,
	); if graph_state.feedback_frames > 0 do vk_editor_text(r, 540, 690, graph_state.feedback, graph_state.feedback_error ? [4]u8{255, 144, 119, 255} : [4]u8{117, 229, 169, 255}, .42)
	else if graph_state.edge_hover.active {edge := graph_state.edge_hover; if edge.node >= 0 && edge.node < graph_document.node_count {source := &graph_document.nodes[edge.node]; target := graph_port_target(&source.beat, edge.port, edge.choice_index); if target != nil do vk_editor_text(r, 520, 690, fmt.tprintf("%s  →  %s", graph_edge_footer_id(source.beat.id), graph_edge_footer_id(target^)), {205, 238, 255, 255}, .38)}}
}

vk_draw_graph_script :: proc(r: ^Vulkan_Backend) {vulkan_ui_rect(
		r,
		220,
		64,
		724,
		610,
		{238, 233, 220, 255},
	)
	vk_graph_ui_text(r, 242, 76, "EDITABLE SCRIPT", {77, 61, 46, 255}, .58)
	scene := graph_active_scene_id()
	row := 0
	for 	node, i in graph_document.nodes[:graph_document.node_count] {if node.beat.scene != scene do continue
		box := graph_script_row_rect(row)
		selected := graph_state.selected_node == i
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{226, 217, 196, 255} : [4]u8{246, 241, 228, 255},
		)
		vulkan_ui_outline(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? graph_kind_color(node.beat.kind) : [4]u8{190, 181, 164, 255},
			selected ? 2 : 1,
		)
		target := node.beat.next
		if node.beat.kind == "check" do target = fmt.tprintf("%s / %s", node.beat.success, node.beat.failure)
		else if node.beat.kind == "choice" do target = graph_join_strings(node.beat.choice_targets)
		else if node.beat.kind == "subscene" do target = node.beat.subscene_id
		if len(target) > 22 do target = target[:22]
		vk_editor_text(
			r,
			box.x + 8,
			box.y + 8,
			fmt.tprintf("[%s] %s", strings.to_upper(node.beat.kind), node.beat.id),
			graph_kind_color(node.beat.kind),
			.31,
		)
		vk_editor_text(
			r,
			box.x + 360,
			box.y + 8,
			fmt.tprintf("TARGET  %s", target),
			{92, 115, 135, 255},
			.25,
		)
		speaker := node.beat.speaker
		if speaker == "" do speaker = "—"
		vk_editor_text(r, box.x + 8, box.y + 38, strings.to_upper(speaker), {92, 72, 52, 255}, .27)
		preview := node.beat.text
		if node.beat.kind == "choice" do preview = graph_join_strings(node.beat.choice_labels)
		if preview == "" do preview = node.beat.summary
		if len(preview) > 58 do preview = preview[:58]
		vk_editor_text(r, box.x + 92, box.y + 38, preview, {52, 46, 40, 255}, .31)
		if selected {vk_graph_button(r, {box.x + 496, box.y + 5, 54, 24}, "UP"); vk_graph_button(
				r,
				{box.x + 554, box.y + 5, 54, 24},
				"DOWN",
			)
			vk_graph_button(r, {box.x + 612, box.y + 5, 62, 24}, "DELETE")}
		row += 1
		if row >= 8 do break}
	vk_graph_button(r, {790, 646, 130, 28}, "+ LINE BEAT")}
vk_draw_graph_localization :: proc(r: ^Vulkan_Backend) {vulkan_ui_rect(
		r,
		220,
		64,
		724,
		610,
		{15, 20, 27, 255},
	)
	vk_graph_ui_text(r, 242, 82, "LOCALIZATION & VO", {255, 218, 112, 255}, .56)
	vk_graph_button(r, {238, 104, 80, 26}, "SCENE", graph_state.localization_scene_only)
	vk_graph_button(
		r,
		{322, 104, 96, 26},
		graph_state.localization_language == "" ? "ALL LANG" : graph_state.localization_language,
	)
	vk_graph_button(
		r,
		{422, 104, 96, 26},
		graph_state.localization_status == "" ? "ALL STATUS" : graph_state.localization_status,
	)
	vk_graph_button(r, {522, 104, 116, 26}, "MISSING TEXT", graph_state.localization_missing_text)
	vk_graph_button(r, {642, 104, 116, 26}, "MISSING VO", graph_state.localization_missing_voice)
	headers := [5]string{"NODE", "LANGUAGE", "TRANSLATION", "STATUS", "VOICE"}
	xs := [5]f32{242, 388, 482, 724, 806}
	for label, i in headers do vk_graph_ui_text(r, xs[i], 140, label, {170, 218, 228, 255}, .31)
	visible := 0
	for 	row in 0 ..< 10 {i := graph_localization_visible_index(row); if i < 0 do break; visible += 1; item :=
			graph_document.localizations[i]
		box := graph_localization_row_rect(row)
		selected := graph_state.selected_localization == i
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{43, 57, 70, 255} : [4]u8{24, 31, 40, 255},
		)
		vulkan_ui_outline(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{255, 218, 112, 255} : [4]u8{70, 82, 94, 255},
			selected ? 2 : 1,
		)
		node := item.node_id
		if len(node) > 19 do node = node[:19]
		text := item.text
		if len(text) > 30 do text = text[:30]
		vk_editor_text(r, box.x + 6, box.y + 14, node, {235, 237, 238, 255}, .27)
		vk_editor_text(r, box.x + 154, box.y + 14, item.language, {205, 211, 218, 255}, .27)
		vk_editor_text(r, box.x + 248, box.y + 14, text, {205, 225, 232, 255}, .27)
		vk_editor_text(
			r,
			box.x + 490,
			box.y + 14,
			item.status,
			item.status == "final" ? [4]u8{117, 229, 169, 255} : [4]u8{255, 218, 112, 255},
			.27,
		)
		vk_editor_text(
			r,
			box.x + 572,
			box.y + 14,
			item.voice,
			item.voice != "" ? [4]u8{117, 229, 169, 255} : [4]u8{135, 142, 151, 255},
			.27,
		)}
	if visible == 0 {vk_editor_text(
			r,
			366,
			270,
			"NO TRANSLATIONS MATCH THESE FILTERS",
			{135, 142, 151, 255},
			.40,
		)}
	vk_graph_button(r, {666, 646, 122, 28}, "+ TRANSLATION")
	vk_graph_button(r, {794, 646, 126, 28}, "DELETE")}
vk_draw_graph_conditions :: proc(r: ^Vulkan_Backend) {vulkan_ui_rect(
		r,
		220,
		64,
		724,
		610,
		{15, 20, 27, 255},
	)
	vk_graph_ui_text(r, 242, 82, "REUSABLE CONDITIONS", {255, 218, 112, 255}, .56)
	for 	item, i in graph_document.conditions[:min(13, graph_document.condition_count)] {box :=
			graph_definition_row_rect(i)
		selected := graph_state.selected_condition == i
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{55, 49, 72, 255} : [4]u8{25, 31, 40, 255},
		)
		vulkan_ui_outline(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{174, 116, 215, 255} : [4]u8{70, 82, 94, 255},
			selected ? 2 : 1,
		)
		vk_editor_text(r, box.x + 8, box.y + 11, item.id, {235, 237, 238, 255}, .29)
		vk_editor_text(
			r,
			box.x + 232,
			box.y + 11,
			strings.to_upper(story_condition_kind_text(item.kind)),
			{205, 153, 235, 255},
			.27,
		)}
	if graph_state.selected_condition >= 0 &&
	   graph_state.selected_condition <
		   graph_document.condition_count {item := &graph_document.conditions[graph_state.selected_condition]
		vk_graph_ui_text(r, 650, 112, "CONDITION INSPECTOR", {205, 153, 235, 255}, .42)
		vk_button(r, {650, 144, 270, 32}, item.id)
		vk_button(r, {650, 190, 270, 32}, strings.to_upper(story_condition_kind_text(item.kind)))
		field_count := 0
		for 		slot in 0 ..< 5 {label, value, visible := graph_condition_slot(item, slot); if !visible do continue
			field_count += 1
			box := Rect{650, 236 + f32(slot) * 58, 270, 52}
			vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {25, 31, 40, 255})
			vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {174, 116, 215, 180}, 1)
			vk_editor_text(r, box.x + 8, box.y + 7, label, {205, 153, 235, 255}, .24)
			display := value
			if display == "" do display = "CLICK TO SET"
			if len(display) > 31 do display = display[:31]
			vk_editor_text(r, box.x + 8, box.y + 27, display, {235, 237, 238, 255}, .29)}
		if field_count == 0 do vk_editor_text(r, 650, 244, "THIS CONDITION HAS NO PARAMETERS", {135, 142, 151, 255}, .30)}
	vk_graph_button(r, {650, 646, 128, 28}, "+ CONDITION")
	vk_graph_button(r, {786, 646, 134, 28}, "DELETE")}
vk_draw_graph_effects :: proc(r: ^Vulkan_Backend) {vulkan_ui_rect(
		r,
		220,
		64,
		724,
		610,
		{15, 20, 27, 255},
	)
	vk_graph_ui_text(r, 242, 82, "REUSABLE EFFECTS", {255, 218, 112, 255}, .56)
	for 	item, i in graph_document.effects[:min(13, graph_document.effect_count)] {box :=
			graph_definition_row_rect(i)
		selected := graph_state.selected_effect == i
		vulkan_ui_rect(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{39, 66, 56, 255} : [4]u8{25, 31, 40, 255},
		)
		vulkan_ui_outline(
			r,
			box.x,
			box.y,
			box.w,
			box.h,
			selected ? [4]u8{80, 181, 119, 255} : [4]u8{70, 82, 94, 255},
			selected ? 2 : 1,
		)
		vk_editor_text(r, box.x + 8, box.y + 11, item.id, {235, 237, 238, 255}, .29)
		vk_editor_text(
			r,
			box.x + 232,
			box.y + 11,
			strings.to_upper(story_effect_kind_text(item.kind)),
			{117, 229, 169, 255},
			.27,
		)}
	if graph_state.selected_effect >= 0 &&
	   graph_state.selected_effect < graph_document.effect_count {item := &graph_document.effects[graph_state.selected_effect]
		vk_graph_ui_text(r, 650, 112, "EFFECT INSPECTOR", {117, 229, 169, 255}, .42)
		vk_button(r, {650, 144, 270, 32}, item.id)
		vk_button(r, {650, 190, 270, 32}, strings.to_upper(story_effect_kind_text(item.kind)))
		for 		slot in 0 ..< 5 {label, value, visible := graph_effect_slot(item, slot); if !visible do continue; box :=
				Rect{650, 236 + f32(slot) * 58, 270, 52}
			vulkan_ui_rect(r, box.x, box.y, box.w, box.h, {25, 31, 40, 255})
			vulkan_ui_outline(r, box.x, box.y, box.w, box.h, {80, 181, 119, 180}, 1)
			vk_editor_text(r, box.x + 8, box.y + 7, label, {117, 229, 169, 255}, .24)
			display := value
			if display == "" do display = "CLICK TO SET"
			if len(display) > 31 do display = display[:31]
			vk_editor_text(r, box.x + 8, box.y + 27, display, {235, 237, 238, 255}, .29)}}
	vk_graph_button(r, {650, 646, 128, 28}, "+ EFFECT")
	vk_graph_button(r, {786, 646, 134, 28}, "DELETE")}
