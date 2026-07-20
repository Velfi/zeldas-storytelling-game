#version 450

layout(set = 0, binding = 0) uniform texture2D source_image;
layout(set = 0, binding = 1) uniform sampler source_sampler;
layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 color;
#define SAMPLE(position) texture(sampler2D(source_image, source_sampler), position)

void main() {
    vec2 texel = 1.0 / vec2(textureSize(sampler2D(source_image, source_sampler), 0));
    vec3 rgb_m = SAMPLE(uv).rgb;
    vec3 rgb_nw = SAMPLE(uv + vec2(-1.0, -1.0) * texel).rgb;
    vec3 rgb_ne = SAMPLE(uv + vec2( 1.0, -1.0) * texel).rgb;
    vec3 rgb_sw = SAMPLE(uv + vec2(-1.0,  1.0) * texel).rgb;
    vec3 rgb_se = SAMPLE(uv + vec2( 1.0,  1.0) * texel).rgb;
    vec3 luma = vec3(0.299, 0.587, 0.114);
    float luma_m = dot(rgb_m, luma);
    float luma_min = min(luma_m, min(min(dot(rgb_nw,luma),dot(rgb_ne,luma)), min(dot(rgb_sw,luma),dot(rgb_se,luma))));
    float luma_max = max(luma_m, max(max(dot(rgb_nw,luma),dot(rgb_ne,luma)), max(dot(rgb_sw,luma),dot(rgb_se,luma))));
    vec2 direction = vec2(-((dot(rgb_nw,luma)+dot(rgb_ne,luma))-(dot(rgb_sw,luma)+dot(rgb_se,luma))),
                           (dot(rgb_nw,luma)+dot(rgb_sw,luma))-(dot(rgb_ne,luma)+dot(rgb_se,luma)));
    float reduce = max((dot(rgb_nw+rgb_ne+rgb_sw+rgb_se,luma) * 0.25) * 0.03125, 0.0078125);
    float reciprocal = 1.0 / (min(abs(direction.x), abs(direction.y)) + reduce);
    direction = clamp(direction * reciprocal, vec2(-8.0), vec2(8.0)) * texel;
    vec3 a = 0.5 * (SAMPLE(uv + direction * (1.0/3.0 - 0.5)).rgb + SAMPLE(uv + direction * (2.0/3.0 - 0.5)).rgb);
    vec3 b = a * 0.5 + 0.25 * (SAMPLE(uv + direction * -0.5).rgb + SAMPLE(uv + direction * 0.5).rgb);
    float luma_b = dot(b, luma);
    color = vec4((luma_b < luma_min || luma_b > luma_max) ? a : b, 1.0);
}
