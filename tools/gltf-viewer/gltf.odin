package main

import "core:encoding/json"
import "core:image"
import _ "core:image/png"
import "core:math"
import "core:os"
import "core:path/filepath"

GLB_MAGIC :: u32(0x46546c67)
GLB_JSON_CHUNK :: u32(0x4e4f534a)
GLB_BIN_CHUNK :: u32(0x004e4942)

Vec2 :: struct {
	x, y: f32,
}
Vec3 :: struct {
	x, y, z: f32,
}
Vec4 :: struct {
	x, y, z, w: f32,
}
Mat4 :: [16]f32

Gltf_Vertex :: struct {
	position: Vec3,
	normal:   Vec3,
	uv:       Vec2,
	color:    Vec4,
}

Gltf_Primitive_Draw :: struct {
	first_index, index_count: u32,
	base_color:               Vec4,
	metallic, roughness:      f32,
	double_sided:             bool,
	base_color_texture:       int,
}

Gltf_Image_Data :: struct {
	pixels:        [dynamic]u8,
	width, height: int,
}

Gltf_Scene :: struct {
	vertices: [dynamic]Gltf_Vertex,
	indices:  [dynamic]u32,
	draws:    [dynamic]Gltf_Primitive_Draw,
	images:   [dynamic]Gltf_Image_Data,
	min, max: Vec3,
}

Gltf_Buffer_View :: struct {
	buffer:      int,
	byte_offset: int `json:"byteOffset"`,
	byte_length: int `json:"byteLength"`,
	byte_stride: int `json:"byteStride"`,
}
Gltf_Accessor :: struct {
	buffer_view:    int `json:"bufferView"`,
	byte_offset:    int `json:"byteOffset"`,
	component_type: int `json:"componentType"`,
	count:          int,
	kind:           string `json:"type"`,
	normalized:     bool,
}
Gltf_Attributes :: struct {
	position: int `json:"POSITION"`,
	normal:   int `json:"NORMAL"`,
	uv:       int `json:"TEXCOORD_0"`,
	color:    int `json:"COLOR_0"`,
}
Gltf_Primitive :: struct {
	attributes:              Gltf_Attributes,
	indices, material, mode: int,
}
Gltf_Mesh :: struct {
	primitives: []Gltf_Primitive,
}
Gltf_Node :: struct {
	mesh:                         int,
	children:                     []int,
	transform:                    []f32 `json:"matrix"`,
	translation, rotation, scale: []f32,
}
Gltf_Scene_Def :: struct {
	nodes: []int,
}
Gltf_Pbr :: struct {
	base_color:         []f32 `json:"baseColorFactor"`,
	metallic:           f32 `json:"metallicFactor"`,
	roughness:          f32 `json:"roughnessFactor"`,
	base_color_texture: struct {
		index: int,
	} `json:"baseColorTexture"`,
}
Gltf_Material :: struct {
	pbr:          Gltf_Pbr `json:"pbrMetallicRoughness"`,
	double_sided: bool `json:"doubleSided"`,
}
Gltf_Image :: struct {
	buffer_view:    int `json:"bufferView"`,
	uri, mime_type: string `json:"mimeType"`,
}
Gltf_Texture :: struct {
	source: int,
}
Gltf_Document :: struct {
	asset:        struct {
		version: string,
	},
	buffer_views: []Gltf_Buffer_View `json:"bufferViews"`,
	accessors:    []Gltf_Accessor,
	meshes:       []Gltf_Mesh,
	nodes:        []Gltf_Node,
	scenes:       []Gltf_Scene_Def,
	scene:        int,
	materials:    []Gltf_Material,
	images:       []Gltf_Image,
	textures:     []Gltf_Texture,
}

read_u32 :: proc(data: []u8, offset: int) -> (u32, bool) {
	if offset < 0 || offset + 4 > len(data) do return 0, false
	return u32(data[offset]) |
		u32(data[offset + 1]) << 8 |
		u32(data[offset + 2]) << 16 |
		u32(data[offset + 3]) << 24,
		true
}
read_f32 :: proc(data: []u8, offset: int) -> (f32, bool) {
	v, ok := read_u32(data, offset)
	return transmute(f32)v, ok
}

mat_identity :: proc() -> Mat4 {return {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}}
mat_mul :: proc(a, b: Mat4) -> Mat4 {
	r: Mat4
	for col in 0 ..< 4 {for row in 0 ..< 4 {for k in 0 ..< 4 {r[col * 4 + row] += a[k * 4 + row] * b[col * 4 + k]}}}
	return r
}
mat_transform_point :: proc(m: Mat4, p: Vec3) -> Vec3 {
	return {
		m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
		m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
		m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
	}
}
mat_transform_vector :: proc(m: Mat4, p: Vec3) -> Vec3 {
	return normalize3(
		{
			m[0] * p.x + m[4] * p.y + m[8] * p.z,
			m[1] * p.x + m[5] * p.y + m[9] * p.z,
			m[2] * p.x + m[6] * p.y + m[10] * p.z,
		},
	)
}
normalize3 :: proc(v: Vec3) -> Vec3 {l := math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z); if l < 0.000001 do return {0, 1, 0}
	return{v.x / l, v.y / l, v.z / l}}

node_matrix :: proc(n: Gltf_Node) -> Mat4 {
	if len(n.transform) == 16 {r: Mat4; for i in 0 ..< 16 do r[i] = n.transform[i]; return r}
	t := Vec3{0, 0, 0}; s := Vec3{1, 1, 1}; q := Vec4{0, 0, 0, 1}
	if len(n.translation) == 3 do t = {n.translation[0], n.translation[1], n.translation[2]}
	if len(n.scale) == 3 do s = {n.scale[0], n.scale[1], n.scale[2]}
	if len(n.rotation) == 4 do q = {n.rotation[0], n.rotation[1], n.rotation[2], n.rotation[3]}
	x, y, z, w := q.x, q.y, q.z, q.w
	return {
		(1 - 2 * y * y - 2 * z * z) * s.x,
		(2 * x * y + 2 * w * z) * s.x,
		(2 * x * z - 2 * w * y) * s.x,
		0,
		(2 * x * y - 2 * w * z) * s.y,
		(1 - 2 * x * x - 2 * z * z) * s.y,
		(2 * y * z + 2 * w * x) * s.y,
		0,
		(2 * x * z + 2 * w * y) * s.z,
		(2 * y * z - 2 * w * x) * s.z,
		(1 - 2 * x * x - 2 * y * y) * s.z,
		0,
		t.x,
		t.y,
		t.z,
		1,
	}
}

accessor_start_stride :: proc(
	doc: ^Gltf_Document,
	accessor_index: int,
	component_count, component_size: int,
) -> (
	Gltf_Accessor,
	int,
	int,
	bool,
) {
	if accessor_index < 0 || accessor_index >= len(doc.accessors) do return {}, 0, 0, false
	a :=
		doc.accessors[accessor_index]; if a.buffer_view < 0 || a.buffer_view >= len(doc.buffer_views) do return {}, 0, 0, false
	v :=
		doc.buffer_views[a.buffer_view]; stride := v.byte_stride; if stride == 0 do stride = component_count * component_size
	return a, v.byte_offset + a.byte_offset, stride, stride >= component_count * component_size
}

read_vec3_accessor :: proc(
	doc: ^Gltf_Document,
	bin: []u8,
	index: int,
	expected_count: int,
) -> (
	[]Vec3,
	bool,
) {
	a, start, stride, ok := accessor_start_stride(
		doc,
		index,
		3,
		4,
	); if !ok || a.kind != "VEC3" || a.component_type != 5126 || a.count != expected_count do return nil, false
	out := make(
		[]Vec3,
		a.count,
	); for i in 0 ..< a.count {x, xok := read_f32(bin, start + i * stride); y, yok := read_f32(bin, start + i * stride + 4); z, zok := read_f32(bin, start + i * stride + 8); if !xok || !yok || !zok do return nil, false; out[i] = {x, y, z}}
	return out, true
}

read_vec2_accessor :: proc(doc: ^Gltf_Document, bin: []u8, index, count: int) -> ([]Vec2, bool) {
	a, start, stride, ok := accessor_start_stride(
		doc,
		index,
		2,
		4,
	); if !ok || a.kind != "VEC2" || a.component_type != 5126 || a.count != count do return nil, false
	out := make(
		[]Vec2,
		count,
	); for i in 0 ..< count {x, xok := read_f32(bin, start + i * stride); y, yok := read_f32(bin, start + i * stride + 4); if !xok || !yok do return nil, false; out[i] = {x, y}}
	return out, true
}

read_indices :: proc(doc: ^Gltf_Document, bin: []u8, index, count: int) -> ([]u32, bool) {
	if index <
	   0 {out := make([]u32, count); for i in 0 ..< count do out[i] = u32(i); return out, true}
	if index >= len(doc.accessors) do return nil, false; source := doc.accessors[index]; size := source.component_type == 5121 ? 1 : source.component_type == 5123 ? 2 : source.component_type == 5125 ? 4 : 0
	a, start, stride, ok := accessor_start_stride(
		doc,
		index,
		1,
		size,
	); if !ok || a.kind != "SCALAR" do return nil, false
	out := make(
		[]u32,
		a.count,
	); for item in 0 ..< a.count {at := start + item * stride; switch size {case 1:
			if at >= len(bin) do return nil, false; out[item] = u32(bin[at]); case 2:
			if at + 2 > len(bin) do return nil, false
			out[item] = u32(bin[at]) | u32(bin[at + 1]) << 8; case 4:
			v, vok := read_u32(bin, at); if !vok do return nil, false; out[item] = v}}
	return out, true
}

append_mesh :: proc(
	scene: ^Gltf_Scene,
	doc: ^Gltf_Document,
	bin: []u8,
	mesh_index: int,
	transform: Mat4,
) -> bool {
	if mesh_index < 0 || mesh_index >= len(doc.meshes) do return false
	for p in doc.meshes[mesh_index].primitives {
		if p.mode != 0 && p.mode != 4 do continue
		if p.attributes.position < 0 || p.attributes.position >= len(doc.accessors) do continue
		count :=
			doc.accessors[p.attributes.position].count; positions, ok := read_vec3_accessor(doc, bin, p.attributes.position, count); if !ok do return false
		normals, normals_ok := read_vec3_accessor(
			doc,
			bin,
			p.attributes.normal,
			count,
		); uvs, uv_ok := read_vec2_accessor(doc, bin, p.attributes.uv, count); local_indices, indices_ok := read_indices(doc, bin, p.indices, count); if !indices_ok do return false
		base := u32(
			len(scene.vertices),
		); for i in 0 ..< count {normal := Vec3{0, 0, 0}; if normals_ok do normal = mat_transform_vector(transform, normals[i]); uv := Vec2{}; if uv_ok do uv = uvs[i]; pos := mat_transform_point(transform, positions[i]); append(&scene.vertices, Gltf_Vertex{pos, normal, uv, {1, 1, 1, 1}}); scene.min = {min(scene.min.x, pos.x), min(scene.min.y, pos.y), min(scene.min.z, pos.z)}; scene.max = {max(scene.max.x, pos.x), max(scene.max.y, pos.y), max(scene.max.z, pos.z)}}
		first := u32(
			len(scene.indices),
		); for idx in local_indices {if idx >= u32(count) do return false; append(&scene.indices, base + idx)}
		if !normals_ok {for i := 0; i + 2 < len(local_indices); i += 3 {ia := int(base + local_indices[i]); ib := int(base + local_indices[i + 1]); ic := int(base + local_indices[i + 2]); a, b, c := scene.vertices[ia].position, scene.vertices[ib].position, scene.vertices[ic].position; ab := Vec3{b.x - a.x, b.y - a.y, b.z - a.z}; ac := Vec3{c.x - a.x, c.y - a.y, c.z - a.z}; n := normalize3({ab.y * ac.z - ab.z * ac.y, ab.z * ac.x - ab.x * ac.z, ab.x * ac.y - ab.y * ac.x}); scene.vertices[ia].normal = n; scene.vertices[ib].normal = n; scene.vertices[ic].normal = n}}
		draw := Gltf_Primitive_Draw {
			first_index        = first,
			index_count        = u32(len(local_indices)),
			base_color         = {1, 1, 1, 1},
			metallic           = 1,
			roughness          = 1,
			base_color_texture = -1,
		}
		if p.material >= 0 &&
		   p.material <
			   len(
				   doc.materials,
			   ) {m := doc.materials[p.material]; draw.double_sided = m.double_sided; draw.metallic = m.pbr.metallic; draw.roughness = m.pbr.roughness; if len(m.pbr.base_color) == 4 do draw.base_color = {m.pbr.base_color[0], m.pbr.base_color[1], m.pbr.base_color[2], m.pbr.base_color[3]}; ti := m.pbr.base_color_texture.index; if ti >= 0 && ti < len(doc.textures) {source := doc.textures[ti].source; if source >= 0 && source < len(doc.images) do draw.base_color_texture = source}}
		append(&scene.draws, draw)
	}
	return true
}

visit_node :: proc(
	scene: ^Gltf_Scene,
	doc: ^Gltf_Document,
	bin: []u8,
	node_index: int,
	parent: Mat4,
	depth: int,
) -> bool {
	if depth > 256 || node_index < 0 || node_index >= len(doc.nodes) do return false; n := doc.nodes[node_index]; world := mat_mul(parent, node_matrix(n)); if n.mesh >= 0 && !append_mesh(scene, doc, bin, n.mesh, world) do return false; for child in n.children do if !visit_node(scene, doc, bin, child, world, depth + 1) do return false; return true
}

gltf_load_glb :: proc(path: string) -> (Gltf_Scene, bool) {
	result := Gltf_Scene {
		min = {math.inf_f32(1), math.inf_f32(1), math.inf_f32(1)},
		max = {math.inf_f32(-1), math.inf_f32(-1), math.inf_f32(-1)},
	}
	data, err := os.read_entire_file_from_path(
		path,
		context.allocator,
	); if err != nil || len(data) < 20 do return result, false
	magic, mok := read_u32(
		data,
		0,
	); version, vok := read_u32(data, 4); total, tok := read_u32(data, 8); if !mok || !vok || !tok || magic != GLB_MAGIC || version != 2 || int(total) > len(data) do return result, false
	json_bytes, bin: []u8; offset := 12; for offset + 8 <= int(total) {size, sok := read_u32(data, offset); kind, kok := read_u32(data, offset + 4); if !sok || !kok || offset + 8 + int(size) > int(total) do return result, false; chunk := data[offset + 8:offset + 8 + int(size)]; if kind == GLB_JSON_CHUNK do json_bytes = chunk; if kind == GLB_BIN_CHUNK do bin = chunk; offset += 8 + int(size)}
	if len(json_bytes) == 0 || len(bin) == 0 do return result, false; doc: Gltf_Document; if json.unmarshal(json_bytes, &doc) != nil || doc.asset.version != "2.0" do return result, false
	for source in doc.images {
		decoded: Gltf_Image_Data
		if source.buffer_view >= 0 &&
		   source.buffer_view <
			   len(
				   doc.buffer_views,
			   ) {view := doc.buffer_views[source.buffer_view]; start := view.byte_offset; end := start + view.byte_length; if start >= 0 && end <= len(bin) {loaded, load_error := image.load_from_bytes(bin[start:end], {.alpha_add_if_missing}); if load_error == nil && loaded != nil {decoded.width = loaded.width; decoded.height = loaded.height; decoded.pixels = make([dynamic]u8, len(loaded.pixels.buf)); copy(decoded.pixels[:], loaded.pixels.buf[:]); image.destroy(loaded)}}}
		if len(decoded.pixels) == 0 &&
		   source.uri !=
			   "" {parent := "."; for i := len(path) - 1; i >= 0; i -= 1 do if path[i] == '/' || path[i] == '\\' {parent = path[:i]; break}; image_path, path_error := filepath.join([]string{parent, source.uri}); if path_error == nil {loaded, load_error := image.load(image_path, {.alpha_add_if_missing}); if load_error == nil && loaded != nil {decoded.width = loaded.width; decoded.height = loaded.height; decoded.pixels = make([dynamic]u8, len(loaded.pixels.buf)); copy(decoded.pixels[:], loaded.pixels.buf[:]); image.destroy(loaded)}}}
		append(&result.images, decoded)
	}
	identity := mat_identity(

	); if len(doc.scenes) > 0 && doc.scene >= 0 && doc.scene < len(doc.scenes) {for node in doc.scenes[doc.scene].nodes do if !visit_node(&result, &doc, bin, node, identity, 0) do return result, false} else {for node, i in doc.nodes {if node.mesh >= 0 && !visit_node(&result, &doc, bin, i, identity, 0) do return result, false}}
	return result, len(result.vertices) > 0 && len(result.indices) > 0 && len(result.draws) > 0
}
