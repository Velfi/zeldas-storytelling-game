static const uint MAX_LIGHTS = 64;
static const uint MAX_DRAW_LIGHTS = 8;
static const uint MAX_SHADOW_CASTERS = 16;
struct Camera {
    float4x4 view_projection;
    float4 camera_position;
    float4 lighting;
    float4 atmosphere;
    float4x4 directional_shadow_matrices[4];
    float4 directional_shadow_splits;
    float4 directional_shadow_params;
    float4x4 point_shadow_matrices[24];
    float4x4 local_shadow_matrices[10];
    float4 light_positions[MAX_LIGHTS];
    float4 light_colors[MAX_LIGHTS];
    float4 light_params[MAX_LIGHTS];
    float4 light_shadow_meta[MAX_LIGHTS];
    float4 shadow_casters[MAX_SHADOW_CASTERS];
    float4 shadow_params[MAX_SHADOW_CASTERS];
};
struct Draw { float4x4 model; float4 tint; float4 material; float4 pbr; uint4 skin; };
struct DrawLights { uint4 indices_a; uint4 indices_b; float4 weights_a; float4 weights_b; uint4 meta; };

[[vk::binding(0, 0)]] ConstantBuffer<Camera> camera;
[[vk::binding(1, 0)]] Texture2D<float4> base_texture;
[[vk::binding(2, 0)]] SamplerState base_sampler;
[[vk::binding(3, 0)]] StructuredBuffer<float4x4> joint_palettes;
[[vk::binding(4, 0)]] StructuredBuffer<DrawLights> draw_light_lists;
[[vk::binding(5, 0)]] Texture2DArray<float> directional_shadow_map;
[[vk::binding(6, 0)]] Texture2DArray<float> point_shadow_map;
[[vk::binding(7, 0)]] Texture2DArray<float> spot_shadow_map;
[[vk::binding(8, 0)]] SamplerComparisonState shadow_sampler;
[[vk::binding(9, 0)]] Texture2D<float4> normal_texture;
[[vk::binding(10, 0)]] Texture2D<float4> roughness_texture;
[[vk::binding(11, 0)]] StructuredBuffer<Draw> world_instances;
[[vk::push_constant]] ConstantBuffer<Draw> draw;

struct VertexInput { float3 position : POSITION; float2 uv : TEXCOORD0; uint4 joints : JOINTS0; float4 weights : WEIGHTS0; uint instance_id : SV_InstanceID; };
struct VertexOutput { float4 position : SV_Position; float3 world_position : WORLD_POSITION; float2 uv : TEXCOORD0; nointerpolation uint instance_id : INSTANCE_ID; };

// Texture samples arrive in linear light because their Vulkan images use an
// sRGB format. Draw tints, on the other hand, originate as ordinary 8-bit sRGB
// palette colors, so decode only those before doing lighting.
float srgb_channel_to_linear(float color) {
    return color <= 0.04045
        ? color / 12.92
        : pow((color + 0.055) / 1.055, 2.4);
}

float3 srgb_to_linear(float3 color) {
    return float3(srgb_channel_to_linear(color.r),
                  srgb_channel_to_linear(color.g),
                  srgb_channel_to_linear(color.b));
}

float sample_directional_shadow(float3 world_position, float3 normal, float3 light_direction) {
    uint cascade_count = (uint)camera.directional_shadow_params.x;
    if (cascade_count == 0) return 1.0;
    float bias = max(camera.directional_shadow_params.z * (1.0 - saturate(dot(normal, light_direction))), camera.directional_shadow_params.y);
    float texel = camera.directional_shadow_params.w;
    // Local authored lights and ambient fill carry vertical interior surfaces.
    // Directional cascades are reserved for upward/downward receivers, where
    // their footprint transitions are hidden in natural ground-plane shadow
    // variation instead of appearing as full-height bands across walls.
    if (abs(normal.y) < 0.25) return 1.0;
    // Select the tightest cascade whose actual light-space footprint contains
    // the receiver. Camera-distance selection cuts a sphere through the floor,
    // exposing cascade differences as the camera-centered "shadow ball."
    [unroll] for (uint cascade = 0; cascade < cascade_count; ++cascade) {
        float4 clip = mul(camera.directional_shadow_matrices[cascade], float4(world_position, 1.0));
        float3 projected = clip.xyz / max(clip.w, 0.0001);
        float2 uv = projected.xy * 0.5 + 0.5;
        float sample_border = texel * 1.5;
        bool covered = all(uv >= sample_border) && all(uv <= 1.0 - sample_border) &&
                       projected.z >= 0.0 && projected.z <= 1.0;
        if (!covered) continue;
        float visibility = 0.0;
        [unroll] for (int y = -1; y <= 1; ++y) {
            [unroll] for (int x = -1; x <= 1; ++x) {
                visibility += directional_shadow_map.SampleCmpLevelZero(shadow_sampler, float3(uv + float2(x, y) * texel, cascade), projected.z - bias);
            }
        }
        visibility /= 9.0;
        // Adjacent cascade footprints overlap. Blend to the broader cascade
        // near the current footprint edge instead of switching shadow maps at
        // one exact world-space line, which reads as a vertical lighting seam.
        float edge_distance = min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y));
        float cascade_blend_width = max(texel * 8.0, 0.004);
        if (cascade + 1 < cascade_count && edge_distance < cascade_blend_width) {
            float4 next_clip = mul(camera.directional_shadow_matrices[cascade + 1], float4(world_position, 1.0));
            float3 next_projected = next_clip.xyz / max(next_clip.w, 0.0001);
            float2 next_uv = next_projected.xy * 0.5 + 0.5;
            bool next_covered = all(next_uv >= sample_border) && all(next_uv <= 1.0 - sample_border) &&
                                next_projected.z >= 0.0 && next_projected.z <= 1.0;
            if (next_covered) {
                float next_visibility = 0.0;
                [unroll] for (int y = -1; y <= 1; ++y) {
                    [unroll] for (int x = -1; x <= 1; ++x) {
                        next_visibility += directional_shadow_map.SampleCmpLevelZero(shadow_sampler, float3(next_uv + float2(x, y) * texel, cascade + 1), next_projected.z - bias);
                    }
                }
                next_visibility /= 9.0;
                return lerp(next_visibility, visibility, smoothstep(0.0, cascade_blend_width, edge_distance));
            }
        }
        return visibility;
    }
    return 1.0;
}

float sample_local_shadow(uint light_index, float3 world_position, float3 normal, float3 toward_light) {
    float4 meta = camera.light_shadow_meta[light_index];
    uint type = (uint)meta.x;
    if (type == 0) return 1.0;
    uint slot = (uint)meta.y;
    float far_plane = max(meta.z, 0.1);
    if (type == 1) {
        float3 from_light = world_position - camera.light_positions[light_index].xyz;
        float distance = length(from_light);
        float3 direction = from_light / max(distance, 0.0001);
        float3 magnitude = abs(direction);
        uint face;
        float2 face_uv;
        if (magnitude.x >= magnitude.y && magnitude.x >= magnitude.z) {
            if (direction.x > 0.0) { face = 0; face_uv = float2(-direction.z, direction.y) / magnitude.x; }
            else { face = 1; face_uv = float2(direction.z, direction.y) / magnitude.x; }
        } else if (magnitude.y >= magnitude.z) {
            if (direction.y > 0.0) { face = 2; face_uv = float2(direction.x, -direction.z) / magnitude.y; }
            else { face = 3; face_uv = float2(direction.x, direction.z) / magnitude.y; }
        } else {
            if (direction.z > 0.0) { face = 4; face_uv = float2(direction.x, direction.y) / magnitude.z; }
            else { face = 5; face_uv = float2(-direction.x, direction.y) / magnitude.z; }
        }
        float4 clip = mul(camera.point_shadow_matrices[slot * 6 + face], float4(world_position, 1.0));
        float3 projected = clip.xyz / max(clip.w, 0.0001);
        float2 uv = projected.xy * 0.5 + 0.5;
        if (any(uv < 0.0) || any(uv > 1.0) || projected.z < 0.0 || projected.z > 1.0) return 1.0;
        float bias = max(meta.w * (1.0 - saturate(dot(normal, toward_light))), 0.0025);
        return point_shadow_map.SampleCmpLevelZero(shadow_sampler, float3(uv, slot * 6 + face), projected.z - bias);
    }
    float4 clip = mul(camera.local_shadow_matrices[slot], float4(world_position, 1.0));
    float3 projected = clip.xyz / max(clip.w, 0.0001);
    float2 uv = projected.xy * 0.5 + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || projected.z < 0.0 || projected.z > 1.0) return 1.0;
    float bias = max(meta.w * (1.0 - saturate(dot(normal, toward_light))), 0.001);
    float texel = 1.0 / 1024.0;
    float visibility = 0.0;
    [unroll] for (int y = -1; y <= 1; ++y) {
        [unroll] for (int x = -1; x <= 1; ++x) visibility += spot_shadow_map.SampleCmpLevelZero(shadow_sampler, float3(uv + float2(x, y) * texel, slot), projected.z - bias);
    }
    return visibility / 9.0;
}

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    Draw active_draw = draw;
    if (draw.skin.w != 0) active_draw = world_instances[draw.skin.z + input.instance_id];
    float4 local = float4(input.position, 1.0);
    if (active_draw.skin.x != 0) {
        uint base = active_draw.skin.y;
        float4 skinned = mul(joint_palettes[base + input.joints.x], local) * input.weights.x;
        skinned += mul(joint_palettes[base + input.joints.y], local) * input.weights.y;
        skinned += mul(joint_palettes[base + input.joints.z], local) * input.weights.z;
        skinned += mul(joint_palettes[base + input.joints.w], local) * input.weights.w;
        local = skinned;
    }
    float4 world = mul(active_draw.model, local);
    output.position = mul(camera.view_projection, world);
    output.world_position = world.xyz;
    output.uv = input.uv;
    output.instance_id = input.instance_id;
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input, bool front_face : SV_IsFrontFace) : SV_Target {
    Draw active_draw = draw;
    if (draw.skin.w != 0) active_draw = world_instances[draw.skin.z + input.instance_id];
    // Background layer: low-contrast woven grain and broad mottling. The draw
    // tint supplies the active interior's palette; this remains intentionally
    // dark beneath the dollhouse geometry.
    if (active_draw.material.y > 2.5 && active_draw.material.y < 3.5) {
        float2 p = input.world_position.xz;
        // Two pattern planes drift at different rates as the camera tracks the
        // investigator. Keeping the offsets small makes the motion perceptible
        // at the edges without making the background feel detached from space.
        float2 camera_drift = camera.camera_position.xz;
        float2 far_pattern = p + camera_drift * 0.065;
        float2 near_pattern = p - camera_drift * 0.16;
        float fine = sin(p.x * 3.7 + p.y * 1.1) * sin(p.y * 4.3 - p.x * 0.8);
        float broad = sin(p.x * 0.31 + p.y * 0.23) * 0.5 + sin(p.y * 0.19 - p.x * 0.17) * 0.5;
        float fibers = sin((p.x + p.y) * 13.0) * 0.5 + sin((p.x - p.y) * 11.0) * 0.5;
        float far_weave = sin(far_pattern.x * 0.72 + far_pattern.y * 0.41) *
                          sin(far_pattern.y * 0.66 - far_pattern.x * 0.29);
        float near_weave = sin((near_pattern.x + near_pattern.y) * 1.18) *
                           sin((near_pattern.x - near_pattern.y) * 0.94);
        float parallax_pattern = far_weave * 0.038 + near_weave * 0.027;
        float background_texture = 0.90 + fine * 0.035 + broad * 0.095 + fibers * 0.014 + parallax_pattern;
        return float4(saturate(active_draw.tint.rgb * background_texture), 1.0);
    }
    float3 dpdx = ddx(input.world_position);
    float3 dpdy = ddy(input.world_position);
    float3 normal = normalize(cross(dpdx, dpdy));
    float3 view_direction = normalize(camera.camera_position.xyz - input.world_position);
    if (dot(normal, view_direction) < 0.0) normal = -normal;
    uint texture_flags = (uint)(active_draw.material.x + 0.5);
    bool has_base_texture = (texture_flags & 1) != 0;
    bool has_normal_texture = (texture_flags & 2) != 0;
    bool has_roughness_texture = (texture_flags & 4) != 0;
    bool is_thin_wall = (texture_flags & 8) != 0;
    float4 sampled = has_base_texture ? base_texture.Sample(base_sampler, input.uv) : float4(1.0);
    uint alpha_mode = (uint)floor(active_draw.material.w + 0.001);
    float alpha_cutoff = frac(active_draw.material.w) * 10.0;
    float material_alpha = sampled.a * active_draw.tint.a;
    // Some legacy foliage meshes describe their card material as OPAQUE even
    // though the base-color texture contains transparent texels. Reject those
    // texels before enforcing glTF's opaque-material output, otherwise the RGB
    // stored beneath alpha zero is rendered as the rectangular leaf card.
    if (has_base_texture && sampled.a <= (0.5 / 255.0)) discard;
    if (alpha_mode == 1 && material_alpha < alpha_cutoff) discard;
    if (alpha_mode == 0) material_alpha = 1.0;
    // R8G8B8A8_SRGB textures are decoded by the sampler. Only palette tints
    // arrive encoded, so decoding the sample again crushes colored diffuse
    // light and lets even a tiny neutral highlight dominate dark materials.
    float3 albedo = max(sampled.rgb * srgb_to_linear(active_draw.tint.rgb), 0.0);
    float metallic = saturate(active_draw.pbr.x);
    float roughness = clamp(active_draw.pbr.y, 0.045, 1.0);
    if (has_roughness_texture) {
        float4 packed_material = roughness_texture.Sample(base_sampler, input.uv);
        roughness = clamp(roughness * packed_material.g, 0.045, 1.0);
        metallic = saturate(metallic * packed_material.b);
    }
    if (has_normal_texture) {
        float2 duvdx = ddx(input.uv);
        float2 duvdy = ddy(input.uv);
        float determinant = duvdx.x * duvdy.y - duvdx.y * duvdy.x;
        if (abs(determinant) > 0.000001) {
            float3 tangent = normalize((dpdx * duvdy.y - dpdy * duvdx.y) / determinant);
            tangent = normalize(tangent - normal * dot(normal, tangent));
            float3 bitangent = normalize(cross(normal, tangent)) * (determinant < 0.0 ? -1.0 : 1.0);
            float3 mapped = normal_texture.Sample(base_sampler, input.uv).xyz * 2.0 - 1.0;
            mapped.xy *= active_draw.pbr.z;
            normal = normalize(tangent * mapped.x + bitangent * mapped.y + normal * mapped.z);
        }
    }
    bool is_window = (active_draw.material.y > 3.5 && active_draw.material.y < 4.5) || (active_draw.material.y > 11.5 && active_draw.material.y < 12.5);
    bool is_wet_yard = active_draw.material.y > 10.5 && active_draw.material.y < 11.5;
    bool is_player = active_draw.material.y > 8.5 && active_draw.material.y < 9.5;
    bool is_character = (active_draw.material.y > 4.5 && active_draw.material.y < 5.5) || is_player;
    bool is_vehicle = active_draw.material.y > 9.5 && active_draw.material.y < 10.5;
    bool is_wall_cap = active_draw.material.y > 5.5 && active_draw.material.y < 6.5;
    bool is_terrain = active_draw.material.y > 6.5 && active_draw.material.y < 7.5 && !has_base_texture;
    bool is_pond = active_draw.material.y > 16.5 && active_draw.material.y < 17.5;
    // Procedural ground is an authored horizontal plane. Derivative normals on
    // the two city-sized triangles can diverge under the oblique aerial camera,
    // exposing their shared diagonal as a false lighting boundary.
    if (is_terrain) normal = float3(0.0, 1.0, 0.0);
    // The procedural pond mesh also contains a green shelf and brown bank.
    // Identify water by its blue-dominant tint; a simple red threshold also
    // classified the dark shelf as water and produced a hard shader seam.
    bool is_pond_surface = is_pond && active_draw.tint.b > active_draw.tint.r * 2.0;
    float pond_depth_pattern = 0.0;
    if (is_pond_surface) {
        // Offset two world-space bottom patterns in the view direction. Their
        // different apparent depths provide stable parallax without a height
        // texture or the silhouette swimming of full relief mapping.
        float2 view_slope = view_direction.xz / max(abs(view_direction.y), 0.35);
        float2 deep_uv = input.world_position.xz + view_slope * 0.34;
        float2 mid_uv = input.world_position.xz + view_slope * 0.14;
        float deep_silt = sin(deep_uv.x * 1.17 + deep_uv.y * 0.43) *
                          sin(deep_uv.y * 1.31 - deep_uv.x * 0.38);
        float mid_silt = sin(mid_uv.x * 2.11 - mid_uv.y * 0.72) *
                         sin(mid_uv.y * 1.83 + mid_uv.x * 0.51);
        pond_depth_pattern = deep_silt * 0.58 + mid_silt * 0.27;
        float ripple_x = sin(input.world_position.x * 3.7 + input.world_position.z * 1.4) * 0.060 +
                         sin(input.world_position.z * 7.1 - input.world_position.x * 2.3) * 0.020;
        float ripple_z = cos(input.world_position.z * 3.2 - input.world_position.x * 1.2) * 0.055 +
                         cos(input.world_position.x * 6.4 + input.world_position.z * 2.7) * 0.018;
        normal = normalize(float3(ripple_x, 1.0, ripple_z));
        float bottom_light = 0.88 + pond_depth_pattern * 0.13;
        albedo = float3(0.010, 0.075, 0.082) * bottom_light;
        roughness = 0.12;
    }
    if (is_character) {
        float luminance = dot(albedo, float3(0.2126, 0.7152, 0.0722));
        // Preserve costume color while compressing high-contrast texture marks
        // that otherwise read as metallic flashes at the aerial camera scale.
        albedo = saturate(lerp(luminance.xxx, albedo, 1.06) * 1.04);
        if (is_player) albedo = saturate(albedo * 1.10 + float3(0.018, 0.014, 0.008));
    }
    if (is_vehicle) {
        float luminance = dot(albedo, float3(0.2126, 0.7152, 0.0722));
        albedo = saturate(lerp(luminance.xxx, albedo, 1.08) * 1.03);
    }
    if (is_terrain) {
        float grass_variation = 0.92 + 0.035 * sin(input.world_position.x * 0.34) *
                                sin(input.world_position.z * 0.29);
        albedo *= grass_variation;
    }
    if (camera.lighting.x > 0.5 && active_draw.material.y > 0.5 && active_draw.material.y < 1.5) {
        float grain = 0.94 + 0.06 * sin(input.world_position.x * 8.5 + input.world_position.z * 1.7);
        albedo *= grain;
    } else if (camera.lighting.x > 0.5 && active_draw.material.y > 1.5 && active_draw.material.y < 2.5 && !is_wall_cap) {
        float lower_panel = 1.0 - smoothstep(1.02, 1.14, input.world_position.y);
        float chair_rail = 1.0 - smoothstep(0.025, 0.06, abs(input.world_position.y - 1.14));
        float vertical_variation = 0.94 + 0.06 * sin((input.world_position.x + input.world_position.z) * 2.4);
        albedo *= vertical_variation * lerp(1.0, 0.58, lower_panel);
        albedo += chair_rail * float3(0.028, 0.024, 0.018);
    }

    float day_angle = camera.atmosphere.z * 6.28318530718;
    float sun_height = sin(day_angle - 1.57079632679);
    float daylight = smoothstep(-0.16, 0.20, sun_height);
    float twilight = (1.0 - smoothstep(0.02, 0.38, abs(sun_height))) * smoothstep(-0.28, -0.02, sun_height);
    float3 simulated_sun = normalize(float3(cos(day_angle), max(abs(sun_height), 0.08), sin(day_angle) * 0.72));
    float3 key_direction = normalize(lerp(float3(-0.42, 0.82, 0.38), simulated_sun, camera.atmosphere.x));
    float3 fill_direction = normalize(float3(0.68, 0.34, -0.62));
    float key_raw = saturate(dot(normal, key_direction));
    float fill_raw = saturate(dot(normal, fill_direction));
    // Broad stepped bands keep forms readable at a distance without harsh
    // toon outlines or losing the texture work.
    float key = smoothstep(0.18, 0.30, key_raw) * 0.34 +
                smoothstep(0.52, 0.66, key_raw) * 0.40 +
                smoothstep(0.82, 0.92, key_raw) * 0.26;
    float fill = smoothstep(0.20, 0.72, fill_raw);
    float up = saturate(normal.y * 0.5 + 0.5);
    float3 night_ambient = lerp(float3(0.006, 0.011, 0.025), float3(0.018, 0.028, 0.045), up);
    float3 day_ambient = lerp(float3(0.020, 0.028, 0.040), float3(0.075, 0.071, 0.058), up);
    float3 ambient = lerp(float3(0.014, 0.020, 0.034), lerp(night_ambient, day_ambient, daylight), camera.atmosphere.x);
    // The city ground is one enormous untextured receiver beneath independently
    // drawn roads and parcels. Cascade projection across that mega-quad can turn
    // one triangle into a half-city shadow wedge. Keep the base fill unshadowed;
    // textured terrain, roads, buildings, props, and characters still receive
    // directional shadows normally.
    float directional_visibility = sample_directional_shadow(input.world_position, normal, key_direction);
    float3 outdoor_sun_color = lerp(float3(0.32, 0.42, 0.62), float3(1.02, 0.92, 0.76), daylight) +
                               twilight * float3(0.34, 0.10, 0.015);
    // Crossing the threshold should shed the rainy atmosphere without revealing
    // a warm, full-strength sun indoors. Fade to a cool, weak architectural key
    // while authored room lights provide the warmth and visual focus.
    float3 sun_color = lerp(float3(0.40, 0.47, 0.58), outdoor_sun_color, camera.atmosphere.x);
    float sun_strength = lerp(0.22, 0.12 + daylight * 0.52, camera.atmosphere.x);
    float3 illumination = ambient + key * directional_visibility * sun_strength * sun_color +
                          fill * float3(0.035, 0.052, 0.085);
    if (is_thin_wall) {
        float key_transmission = smoothstep(0.04, 0.92, saturate(dot(-normal, key_direction)));
        illumination += key_transmission * directional_visibility * sun_strength * sun_color * 0.58;
    }
    float rim = pow(1.0 - saturate(dot(normal, view_direction)), 3.0);
    bool exterior = camera.lighting.x < 0.5;
    illumination += rim * (exterior ? float3(0.052, 0.075, 0.105) : float3(0.025, 0.040, 0.070));

    // Authored editor lights become warm, soft local pools. Position.w stores
    // range; color.w stores intensity, keeping the uniform layout compact.
    uint light_count = min((uint)camera.lighting.z, MAX_LIGHTS);
    DrawLights assigned = draw_light_lists[active_draw.skin.z];
    uint assigned_count = min(assigned.meta.x, MAX_DRAW_LIGHTS);
    int selected_light = (int)assigned.meta.y - 1;
    for (uint assigned_index = 0; assigned_index < assigned_count; ++assigned_index) {
        uint light_index = assigned_index < 4 ? assigned.indices_a[assigned_index] : assigned.indices_b[assigned_index - 4];
        float room_weight = assigned_index < 4 ? assigned.weights_a[assigned_index] : assigned.weights_b[assigned_index - 4];
        if (light_index >= light_count) continue;
        float3 delta = camera.light_positions[light_index].xyz - input.world_position;
        float distance = length(delta);
        float range = max(camera.light_positions[light_index].w, 0.01);
        float falloff = saturate(1.0 - distance / range);
        falloff = falloff * falloff * (3.0 - 2.0 * falloff);
        float diffuse = saturate(dot(normal, delta / max(distance, 0.001)));
        float wrapped = saturate((diffuse + 0.28) / 1.28);
        if (is_thin_wall) {
            float back_diffuse = saturate(dot(-normal, delta / max(distance, 0.001)));
            // Broad diffuse transmission reveals a soft bulb glow without
            // turning an opaque paper or fabric shade into transparent glass.
            wrapped += smoothstep(0.0, 0.86, back_diffuse) * 0.72;
        }
        float cone = 1.0;
        if (camera.light_params[light_index].x > 0.5 && camera.light_params[light_index].x < 1.5) {
            float2 facing = float2(cos(camera.light_params[light_index].y), sin(camera.light_params[light_index].y));
            float2 toward_fragment = normalize(input.world_position.xz - camera.light_positions[light_index].xz);
            cone = smoothstep(camera.light_params[light_index].z, min(1.0, camera.light_params[light_index].z + 0.08), dot(facing, toward_fragment));
        }
        float local_shadow = sample_local_shadow(light_index, input.world_position, normal, delta / max(distance, 0.001));
        illumination += camera.light_colors[light_index].rgb *
                        camera.light_colors[light_index].w * falloff * wrapped * room_weight * cone * local_shadow;
    }

    // Specular belongs to the light that produces it. The former universal,
    // neutral N.H band added the same gray value to walls, floors, and props,
    // even in shadow. Keep architecture matte and reserve highlights for
    // surfaces whose material presentation calls for them.
    float specular_weight = 0.0;
    float specular_power = 24.0;
    if (is_window) { specular_weight = 0.72; specular_power = 72.0; }
    else if (is_wet_yard) { specular_weight = 0.34; specular_power = 40.0; }
    else if (is_vehicle) { specular_weight = 0.20; specular_power = 48.0; }
    else if (is_character) { specular_weight = 0.025; specular_power = 28.0; }
    else if (is_pond_surface) { specular_weight = 0.90; specular_power = 72.0; }
    else if (active_draw.material.y < 0.5) { specular_weight = 0.055; specular_power = 32.0; }
    if (active_draw.pbr.w > 0.5) {
        specular_weight = lerp(0.34, 0.018, roughness);
        specular_power = lerp(96.0, 4.0, roughness);
    }
    float halfway_alignment = saturate(dot(normal, normalize(key_direction + view_direction)));
    float specular_lobe = pow(halfway_alignment, specular_power);
    float3 dielectric_f0 = lerp(is_vehicle ? lerp(float3(0.028), saturate(albedo), 0.16) : float3(0.028), albedo, metallic);
    float3 key_radiance = key * directional_visibility * sun_strength * sun_color;
    float3 specular_light = specular_lobe * specular_weight * dielectric_f0 * key_radiance;

    if (is_wall_cap) {
        // A restrained world-space grain keeps long cut runs from looking like
        // flat UI strokes while remaining stable as the camera rotates.
        float cap_grain = 0.96 + 0.025 * sin(input.world_position.x * 17.0 + input.world_position.z * 13.0) *
                                    sin(input.world_position.z * 19.0 - input.world_position.x * 11.0);
        albedo *= 0.68 * cap_grain;
    }

    float3 lit = albedo * illumination + specular_light;
    if (is_thin_wall) {
        // Local illumination remains responsible for lighting the room. This
        // restrained self-luminance only keeps the shade itself readable.
        float selected_lamp = selected_light >= 0 ? 1.0 : 0.0;
        lit += albedo * float3(1.0, 0.78, 0.48) * (0.055 + selected_lamp * 0.11);
    }
    if (is_window) {
        float fresnel = pow(1.0 - saturate(abs(dot(normal, view_direction))), 4.0);
        // Narrow, restrained highlights suggest polished glass without filling
        // most of a large pane. Broad UV bands read as separate opaque panels
        // beside clear ones, especially on picture and casement windows.
        float diagonal = input.uv.x + input.uv.y * 0.22;
        float band_a = exp(-pow((diagonal - 0.32) * 28.0, 2.0));
        float band_b = exp(-pow((diagonal - 0.72) * 36.0, 2.0));
        float reflection_band = (band_a + band_b * 0.45) * 0.012;
        float3 sky = float3(0.08, 0.18, 0.34);
        float3 warm_transmission = float3(0.92, 0.57, 0.27) * (0.10 + illumination * 0.045);
        lit = warm_transmission + sky * (0.12 + fresnel * 0.58 + reflection_band);
    }
    if (is_pond_surface) {
        float facing = saturate(abs(dot(normal, view_direction)));
        float fresnel = pow(1.0 - facing, 3.5);
        float radial_edge = saturate(length((input.uv - 0.5) * 2.0));
        float center_depth = 1.0 - smoothstep(0.12, 0.88, radial_edge);
        float caustic = smoothstep(0.48, 0.94, pond_depth_pattern) * (1.0 - fresnel) * 0.035;
        float bottom_variation = 0.72 + pond_depth_pattern * 0.24;
        float wave_a = sin(input.world_position.x * 3.1 + input.world_position.z * 2.4);
        float wave_b = sin(input.world_position.z * 5.2 - input.world_position.x * 1.7);
        float crest_a = pow(saturate(1.0 - abs(wave_a)), 22.0);
        float breakup = 0.20 + 0.80 * pow(saturate(wave_b * 0.5 + 0.5), 3.0);
        float ripple_glint = crest_a * 0.022 * breakup;
        float3 deep_water = lit * bottom_variation + float3(0.003, 0.018, 0.022);
        float3 reflected_sky = float3(0.030, 0.075, 0.115);
        lit = lerp(deep_water, reflected_sky, 0.08 + fresnel * 0.76) +
              caustic * float3(0.32, 0.52, 0.39) + ripple_glint * float3(0.28, 0.48, 0.58);
        lit *= lerp(1.08, 0.58, center_depth * (1.0 - fresnel * 0.45));
    }
    if (is_wet_yard) {float grazing=pow(1.0-saturate(abs(dot(normal,view_direction))),3.0);lit=lit*.62+float3(.08,.14,.22)*(grazing*.32);}
    float weather = saturate(camera.atmosphere.x);
    // The storm remains visible through doors and windows after the camera moves
    // indoors. Retain a light overcast grade, but keep the stronger distance haze
    // and rain wash tied to the outdoor transition.
    float overcast_grade = lerp(0.35, 1.0, weather);
    float view_distance = distance(camera.camera_position.xyz, input.world_position);
    float distance_fog = 1.0 - exp(-max(view_distance - 5.0, 0.0) * 0.026);
    float low_mist = exp(-max(input.world_position.y, 0.0) * 0.55) * 0.10;
    float fog_amount = saturate((distance_fog * 0.30 + low_mist * 0.45) * weather);
    float3 rain_haze = lerp(float3(0.012, 0.026, 0.045), float3(0.035, 0.060, 0.068), daylight);
    lit = lerp(lit, rain_haze, fog_amount);
    lit = lerp(dot(lit, float3(0.2126, 0.7152, 0.0722)).xxx, lit, 1.0 - overcast_grade * 0.10);
    lit = 1.0 - exp(-lit * camera.lighting.y);
    float3 contrast_curve = lit * lit * (3.0 - 2.0 * lit);
    lit = lerp(lit, contrast_curve, 0.20);
    float graded_luminance = dot(lit, float3(0.2126, 0.7152, 0.0722));
    lit = saturate(lerp(graded_luminance.xxx, lit, 1.02));
    // The render target uses an sRGB Vulkan format, which performs the single
    // linear-to-sRGB conversion on write. Keep shader output in linear light.
    return float4(max(lit, 0.0), material_alpha);
}
