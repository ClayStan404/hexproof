#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 uItem;
    vec4 uPad;
};

layout(binding = 1) uniform sampler2D source;

float sdRoundBox(vec2 point, vec2 halfSize, float radius)
{
    vec2 q = abs(point) - halfSize + vec2(radius);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

vec2 toTex(vec2 itemUv)
{
    return uPad.xy + itemUv * (vec2(1.0) - 2.0 * uPad.xy);
}

vec3 sampleBackdrop(vec2 texUv, vec2 tap)
{
    vec3 color = texture(source, texUv).rgb * 0.28;
    color += texture(source, texUv + vec2(tap.x, 0.0)).rgb * 0.14;
    color += texture(source, texUv - vec2(tap.x, 0.0)).rgb * 0.14;
    color += texture(source, texUv + vec2(0.0, tap.y)).rgb * 0.14;
    color += texture(source, texUv - vec2(0.0, tap.y)).rgb * 0.14;
    color += texture(source, texUv + tap * 1.6).rgb * 0.08;
    color += texture(source, texUv - tap * 1.6).rgb * 0.08;
    return color;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 itemSize = max(uItem.xy, vec2(1.0));
    float cornerRadius = uItem.z;
    float quiet = uPad.z;
    float well = uPad.w;
    vec2 pixel = uv * itemSize;
    vec2 halfSize = itemSize * 0.5;
    float radius = min(cornerRadius, min(halfSize.x, halfSize.y));
    float sdf = sdRoundBox(pixel - halfSize, halfSize, radius);
    float aa = max(fwidth(sdf), 0.85);
    float alpha = 1.0 - smoothstep(-aa, aa, sdf);
    if (alpha <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    float inward = max(-sdf, 0.0);
    float rimWidth = well > 0.5 ? 3.2 : mix(10.0, 3.0, quiet);
    float rim = 1.0 - smoothstep(0.0, rimWidth, inward);
    float lens = well > 0.5 ? 0.0 : mix(0.018, 0.0, quiet);
    vec2 warped = uv - vec2(0.0, 0.22) * rim * lens;
    vec2 tap = (vec2(1.0) - 2.0 * uPad.xy) * mix(24.0, 11.0, max(quiet, well)) / itemSize;

    vec3 color = sampleBackdrop(toTex(warped), tap);
    if (well > 0.5)
        color *= 1.65;
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float sat = well > 0.5 ? 1.10 : mix(1.24, 1.08, quiet);
    color = mix(vec3(luma), color, sat);
    float darken = well > 0.5 ? 0.02 : mix(0.18, 0.08, quiet);
    float frost = well > 0.5 ? 0.28 : mix(0.16, 0.10, quiet);
    color = mix(color, vec3(0.05, 0.07, 0.09), darken);
    color = mix(color, vec3(0.90, 0.94, 0.97), frost);

    vec2 fromCenter = pixel - halfSize;
    vec2 light = normalize(vec2(-0.42, -0.90));
    float facing = dot(normalize(fromCenter + vec2(0.001)), light);
    float spec = rim * smoothstep(0.05, 0.85, facing) * mix(0.18, 0.08, max(quiet, well));
    color += vec3(1.0) * spec;
    color *= 1.0 - rim * smoothstep(0.15, -0.85, facing) * mix(0.16, 0.08, max(quiet, well));

    // Preserve light-label contrast over bright snow, paper and other playmats.
    float peak = max(color.r, max(color.g, color.b));
    color *= min(1.0, 0.42 / max(peak, 0.001));

    fragColor = vec4(color, 1.0) * (alpha * qt_Opacity);
}
