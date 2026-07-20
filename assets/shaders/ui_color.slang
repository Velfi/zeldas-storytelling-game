struct Push { float2 viewport; float2 padding; };
[[vk::push_constant]] ConstantBuffer<Push> push;
struct Input { float2 position : POSITION; float4 color : COLOR0; };
struct Output { float4 position : SV_Position; float4 color : COLOR0; };
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
Output vertex_main(Input input) {
    Output output;
    float2 ndc = float2(input.position.x / push.viewport.x * 2.0 - 1.0,
                        1.0 - input.position.y / push.viewport.y * 2.0);
    output.position = float4(ndc, 0.0, 1.0);
    output.color = input.color;
    return output;
}
[shader("fragment")]
float4 fragment_main(Output input) : SV_Target {
    return float4(srgb_to_linear(input.color.rgb), input.color.a);
}
