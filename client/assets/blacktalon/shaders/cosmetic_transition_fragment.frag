uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform sampler2D u_Tex1;
uniform float u_Time;
uniform float u_var0;

void main()
{
    vec4 base = texture2D(u_Tex0, v_TexCoord) * u_Color[0];
    if (base.a < 0.01) {
        discard;
    }

    float mask = texture2D(u_Tex1, fract(v_TexCoord3)).r;
    bool appearMode = u_var0 > 1.0;
    float progress = appearMode ? clamp(u_var0 - 1.0, 0.0, 1.0) : clamp(u_var0, 0.0, 1.0);
    float shimmer = 0.82 + 0.18 * sin(u_Time * 18.0 + (v_TexCoord3.x + v_TexCoord3.y) * 10.0);

    if (!appearMode) {
        float cutoff = progress;
        if (mask < cutoff) {
            discard;
        }

        float edgeBand = 1.0 - smoothstep(0.0, 0.14, abs(mask - cutoff));
        vec3 edgeGlow = vec3(0.52, 1.0, 0.9) * edgeBand * shimmer * 0.45;
        vec3 cooledBase = mix(base.rgb * 0.7, base.rgb, 1.0 - progress);
        gl_FragColor = vec4(cooledBase + edgeGlow, base.a);
        return;
    }

    float cutoff = 0.85 - progress * 0.85;
    float edgeBand = 1.0 - smoothstep(0.0, 0.18, abs(mask - cutoff));
    float activated = step(cutoff, mask);
    vec3 edgeGlow = vec3(0.52, 1.0, 0.9) * edgeBand * shimmer * 0.55;
    vec3 activatedBase = mix(base.rgb * 0.85, base.rgb, 0.35 + activated * 0.65);
    vec3 cooledBase = mix(activatedBase * 0.92, activatedBase, progress);

    gl_FragColor = vec4(cooledBase + edgeGlow, base.a);
}
