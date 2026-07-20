struct Camera {
    float4x4 view_projection;
    float4 camera_position;
};

struct Draw {
    float4x4 model;
    float4 base_color_factor;
    float4 material; // metallic, roughness, alpha cutoff, flags
};

[[vk::binding(0, 0)]] ConstantBuffer<Camera> camera;
[[vk::binding(1, 0)]] Texture2D<float4> base_color_texture;
[[vk::binding(2, 0)]] SamplerState base_color_sampler;
[[vk::push_constant]] ConstantBuffer<Draw> draw;

struct VertexInput {
    float3 position : POSITION;
    float3 normal : NORMAL;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float3 world_position : WORLD_POSITION;
    float3 world_normal : WORLD_NORMAL;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    float4 world = mul(draw.model, float4(input.position, 1.0));
    output.position = mul(camera.view_projection, world);
    output.world_position = world.xyz;
    output.world_normal = normalize(mul((float3x3)draw.model, input.normal));
    output.uv = input.uv;
    output.color = input.color * draw.base_color_factor;
    return output;
}

float3 fresnel_schlick(float cos_theta, float3 f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float3 n = normalize(input.world_normal);
    // Foliage cards remain two-sided at the rasterizer; retain authored normals.
    float3 v = normalize(camera.camera_position.xyz - input.world_position);
    float3 l = normalize(float3(-0.45, 0.82, 0.34));
    float3 h = normalize(v + l);
    float metallic = saturate(draw.material.x);
    float roughness = clamp(draw.material.y, 0.045, 1.0);
    float4 sampled = (draw.material.w > 0.5) ? base_color_texture.Sample(base_color_sampler, input.uv) : float4(1.0);
    if (sampled.a < 0.5) discard;
    float3 albedo = input.color.rgb * sampled.rgb;
    float3 f0 = lerp(float3(0.04), albedo, metallic);
    float ndotl = saturate(dot(n, l));
    float ndoth = saturate(dot(n, h));
    float vdoth = saturate(dot(v, h));
    float alpha = roughness * roughness;
    float alpha2 = alpha * alpha;
    float denom = ndoth * ndoth * (alpha2 - 1.0) + 1.0;
    float distribution = alpha2 / max(3.14159265 * denom * denom, 0.0001);
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float geometry = ndotl / (ndotl * (1.0 - k) + k);
    geometry *= saturate(dot(n, v)) / (saturate(dot(n, v)) * (1.0 - k) + k);
    float3 specular = distribution * geometry * fresnel_schlick(vdoth, f0) /
        max(4.0 * ndotl * saturate(dot(n, v)), 0.0001);
    float3 diffuse = (1.0 - metallic) * albedo / 3.14159265;
    float3 color = (diffuse + specular) * ndotl * float3(3.2, 3.0, 2.8) + albedo * 0.055;
    color = color / (color + 1.0);
    color = pow(color, 1.0 / 2.2);
    return float4(color, input.color.a * sampled.a);
}
