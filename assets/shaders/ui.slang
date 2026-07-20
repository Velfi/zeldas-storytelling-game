struct UiPush {
    float2 logical_viewport;
    float2 framebuffer;
    float use_texture;
    float padding;
};

[[vk::binding(0, 0)]] Texture2D<float4> ui_texture;
[[vk::binding(1, 0)]] SamplerState ui_sampler;
[[vk::push_constant]] ConstantBuffer<UiPush> push;

struct VertexInput {
    float2 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

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

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    // Resolve logical UI coordinates onto exact swapchain pixel boundaries.
    // This prevents half-pixel shimmer and soft stems at arbitrary window DPI.
    float2 pixel = round(input.position / push.logical_viewport * push.framebuffer);
    float2 ndc = pixel / push.framebuffer * 2.0 - 1.0;
    output.position = float4(ndc, 0.0, 1.0);
    output.uv = input.uv;
    output.color = input.color;
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float4 sampled = push.use_texture > 0.5
        ? ui_texture.Sample(ui_sampler, input.uv)
        : float4(1.0);
    // UI textures are sampled from sRGB images and therefore arrive linear.
    // Vertex colors originate as ordinary 8-bit sRGB palette values; decode
    // them before modulation and blending. The sRGB attachment encodes once.
    float4 linear_tint = float4(srgb_to_linear(input.color.rgb), input.color.a);
    return linear_tint * sampled;
}
