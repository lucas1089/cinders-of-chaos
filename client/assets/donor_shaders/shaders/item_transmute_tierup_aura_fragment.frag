// Transmute Result - Tier Up Aura (pulsing golden energy rings)
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform float u_var0; // intensity (0..1)
varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.01;
const float PI = 3.14159265;

float random(vec2 st) {
    return fract(sin(dot(st, vec2(12.9898, 78.233))) * 43758.5453123);
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    float alpha = texColor.a;

    if (alpha < ALPHA_THRESHOLD) {
        discard;
    }

    float intensity = clamp(u_var0, 0.0, 1.0);

    // Distance from center of sprite
    vec2 center = vec2(0.5, 0.5);
    vec2 uv = v_TexCoord - center;
    float dist = length(uv);
    float angle = atan(uv.y, uv.x);

    // --- Pulsing aura rings expanding outward ---
    float ringSpeed = 2.5;
    float ringCount = 3.0;
    float ringWidth = 0.08;
    float auraGlow = 0.0;
    for (int i = 0; i < 3; i++) {
        float offset = float(i) / ringCount;
        float ringDist = fract(dist * 2.5 - u_Time * ringSpeed * 0.3 + offset);
        float ring = smoothstep(ringWidth, 0.0, abs(ringDist - 0.5) - 0.15);
        auraGlow += ring * 0.35;
    }

    // --- Golden sparkle particles ---
    float sparkle = 0.0;
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float sparkleAngle = fi * PI * 2.0 / 6.0 + u_Time * (0.8 + fi * 0.15);
        float sparkleDist = 0.15 + 0.12 * sin(u_Time * 1.5 + fi * 2.0);
        vec2 sparklePos = center + vec2(cos(sparkleAngle), sin(sparkleAngle)) * sparkleDist;
        float d = distance(v_TexCoord, sparklePos);
        float s = smoothstep(0.04, 0.0, d);
        float flicker = 0.5 + 0.5 * sin(u_Time * (6.0 + fi * 1.3) + fi * 3.14);
        sparkle += s * flicker;
    }

    // --- Pulsing edge glow (inner rim) ---
    vec2 texel = vec2(1.0 / 64.0);
    float nearAvg =
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a;
    nearAvg /= 4.0;
    float edgeFactor = clamp((nearAvg - alpha) * 3.5 + (1.0 - alpha) * 0.3, 0.0, 1.0);
    float edgePulse = 0.5 + 0.5 * sin(u_Time * 3.0);
    float edgeGlow = edgeFactor * edgePulse * 0.6;

    // --- Global pulse (breathing) ---
    float breathe = 0.08 * sin(u_Time * 2.0) + 0.08;

    // --- Color composition ---
    // Golden-yellow aura with warm white highlights
    vec3 auraColor = vec3(1.0, 0.85, 0.2);       // Gold
    vec3 sparkleColor = vec3(1.0, 0.95, 0.6);     // Warm white
    vec3 edgeColor = vec3(1.0, 0.75, 0.15);       // Deep gold

    vec3 finalColor = texColor.rgb;
    finalColor += auraColor * auraGlow * intensity * alpha;
    finalColor += sparkleColor * sparkle * intensity * 0.7 * alpha;
    finalColor += edgeColor * edgeGlow * intensity;
    finalColor += finalColor * breathe * intensity;

    // Slight overall golden tint
    finalColor.r += 0.06 * intensity;
    finalColor.g += 0.04 * intensity;

    gl_FragColor = vec4(finalColor, alpha);
}
