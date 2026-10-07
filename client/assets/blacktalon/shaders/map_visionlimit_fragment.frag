uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;
varying vec2 v_WorldPos;
uniform vec2 u_Resolution;
uniform float u_Time;

// Vision parameters - adjust these to customize the effect
const float VISION_RADIUS = 120.0;      // Size of the visible area around player (in pixels)
const float VISION_FALLOFF = 80.0;      // How soft the edge transition is
const float DARKNESS_INTENSITY = 0.50;  // How dark the outer area is (0.0 = visible, 1.0 = pitch black)
const vec3 DARKNESS_COLOR = vec3(0.0, 0.0, 0.0); // Color of the darkness (black)

// Optional: Add subtle noise to the edge for a more organic look
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    // Sample the map texture
    vec4 mapColor = texture2D(u_Tex0, v_TexCoord);

    // Calculate distance from center (player position is at origin 0,0)
    float distFromCenter = length(v_WorldPos);

    // Add subtle noise to the edge for organic feel (optional)
    float edgeNoise = noise(v_WorldPos * 0.05 + u_Time * 0.5) * 15.0;
    float adjustedDist = distFromCenter + edgeNoise;

    // Calculate visibility factor with smooth falloff
    // 1.0 = fully visible, 0.0 = fully dark
    float visibility = 1.0 - smoothstep(VISION_RADIUS, VISION_RADIUS + VISION_FALLOFF, adjustedDist);

    // Apply darkness based on visibility
    vec3 finalColor = mix(
        DARKNESS_COLOR,           // Dark area color
        mapColor.rgb,             // Original map color
        visibility                // Blend factor
    );

    // Also darken alpha slightly in dark areas for extra effect
    float finalAlpha = mix(mapColor.a * DARKNESS_INTENSITY, mapColor.a, visibility);

    gl_FragColor = vec4(finalColor, finalAlpha);
}
