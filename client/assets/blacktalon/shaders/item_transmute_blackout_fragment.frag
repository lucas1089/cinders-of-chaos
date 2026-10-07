// Transmute Result - Blackout Shader Fragment
// Dark silhouette with inner glow near edges.

uniform sampler2D u_Tex0;
uniform float u_var0; // 0.0 = fully dark, 1.0 = fully revealed color
varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.01;
const vec3 DARK_GRAY = vec3(0.14, 0.14, 0.14);
const vec3 GLOW_COLOR = vec3(0.6, 0.62, 0.68);
const float GLOW_RADIUS = 1.7;
const float GLOW_INTENSITY = 0.8;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a < ALPHA_THRESHOLD) {
        discard;
    }

    float reveal = clamp(u_var0, 0.0, 1.0);

    // Inner glow: measure distance to nearest transparent pixel
    // Use dFdx/dFdy to estimate pixel size (GLSL 1.10 compatible, no textureSize needed)
    vec2 pixel = vec2(dFdx(v_TexCoord.x), dFdy(v_TexCoord.y));
    pixel = abs(pixel);
    if (pixel.x < 0.0001) pixel.x = 0.005;
    if (pixel.y < 0.0001) pixel.y = 0.005;

    float minDist = GLOW_RADIUS;
    for (float y = -GLOW_RADIUS; y <= GLOW_RADIUS; y += 1.0) {
        for (float x = -GLOW_RADIUS; x <= GLOW_RADIUS; x += 1.0) {
            float d = length(vec2(x, y));
            if (d > GLOW_RADIUS) continue;
            float a = texture2D(u_Tex0, v_TexCoord + vec2(x, y) * pixel).a;
            if (a < ALPHA_THRESHOLD) {
                minDist = min(minDist, d);
            }
        }
    }

    // Glow falloff: strongest at edge (dist=0), fades inward
    float glow = (1.0 - smoothstep(0.0, GLOW_RADIUS, minDist)) * GLOW_INTENSITY;

    // Blend: dark base + glow at edges, revealed color overrides
    vec3 darkWithGlow = DARK_GRAY + GLOW_COLOR * glow;
    vec3 mixedRgb = mix(darkWithGlow, texColor.rgb, reveal);
    gl_FragColor = vec4(mixedRgb, texColor.a);
}
