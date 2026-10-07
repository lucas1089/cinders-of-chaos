// Golden glow border shader for BlackTalon - DEBUG VERSION
// Uniforms from border system: u_BorderColor, u_WidgetSize, u_BorderRadii, u_BorderWidth
// Uniforms from shader system: u_Time, u_var0
precision mediump float;

varying vec2 v_WidgetUV;
uniform vec4 u_BorderColor;
uniform vec2 u_WidgetSize;
uniform vec4 u_BorderRadii;
uniform float u_BorderWidth;
uniform float u_Time;
uniform float u_var0;

void main() {
    // DEBUG: Simple red/green flashing border to verify shader is active
    float pulse = sin(u_Time * 5.0) * 0.5 + 0.5;
    vec3 debugColor = mix(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), pulse);

    // Simple border mask using UV coordinates
    vec2 uv = v_WidgetUV;
    float bw = u_BorderWidth / min(u_WidgetSize.x, u_WidgetSize.y);

    // Distance from edges in UV space
    float left = uv.x;
    float right = 1.0 - uv.x;
    float top = uv.y;
    float bottom = 1.0 - uv.y;
    float edgeDist = min(min(left, right), min(top, bottom));

    // Border mask: 1.0 inside border, 0.0 outside
    float borderMask = 1.0 - smoothstep(0.0, bw, edgeDist);

    // Glow extends a bit beyond border
    float glowMask = 1.0 - smoothstep(0.0, bw * 3.0, edgeDist);
    float glowOnly = glowMask * (1.0 - borderMask) * 0.5 * pulse;

    float alpha = (borderMask + glowOnly) * u_var0;
    gl_FragColor = vec4(debugColor * (borderMask + glowOnly), alpha);
}
