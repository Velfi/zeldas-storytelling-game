struct ShadowPush { float4x4 model; uint4 data; };
[[vk::binding(0, 0)]] StructuredBuffer<float4x4> shadow_matrices;
[[vk::binding(1, 0)]] StructuredBuffer<float4x4> joint_palettes;
[[vk::push_constant]] ConstantBuffer<ShadowPush> push;

struct VertexInput { float3 position : POSITION; float2 uv : TEXCOORD0; uint4 joints : JOINTS0; float4 weights : WEIGHTS0; };

[shader("vertex")]
float4 vertex_main(VertexInput input) : SV_Position {
    float4 local = float4(input.position, 1.0);
    if (push.data.x != 0) {
        uint base = push.data.y;
        float4 skinned = mul(joint_palettes[base + input.joints.x], local) * input.weights.x;
        skinned += mul(joint_palettes[base + input.joints.y], local) * input.weights.y;
        skinned += mul(joint_palettes[base + input.joints.z], local) * input.weights.z;
        skinned += mul(joint_palettes[base + input.joints.w], local) * input.weights.w;
        local = skinned;
    }
    return mul(shadow_matrices[push.data.z], mul(push.model, local));
}
