#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 metaballMask(
    float2 position,
    half4 color,
    float2 pillEdge,
    float2 circleCenter,
    float radius
) {
    float r2 = radius * radius;
    float2 dEdge = position - pillEdge;
    float2 dCircle = position - circleCenter;

    float fieldEdge   = r2 / max(dot(dEdge, dEdge), 0.5);
    float fieldCircle = r2 / max(dot(dCircle, dCircle), 0.5);
    float field = fieldEdge + fieldCircle;

    float alpha = smoothstep(0.85, 1.15, field);
    return half4(color.rgb, color.a * half(alpha));
}
