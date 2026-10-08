// Transmute Result - Fail Glow (inner rim, no clipping)
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
varying vec2 v_TexCoord;

const float ALPHA_THRESHOLD = 0.01;
const vec3 GLOW_COLOR = vec3(1.0, 0.24, 0.24);

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    float alpha = texColor.a;

    vec2 texel = vec2(1.0 / 64.0, 1.0 / 64.0);
    if (u_Resolution.x > 0.0 && u_Resolution.y > 0.0) {
        texel = vec2(1.0 / u_Resolution.x, 1.0 / u_Resolution.y);
    }

    float nearAvg =
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, 0.0)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(0.0, -texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2( texel.x, -texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x,  texel.y)).a +
        texture2D(u_Tex0, v_TexCoord + vec2(-texel.x, -texel.y)).a;
    nearAvg /= 8.0;

    if (alpha < ALPHA_THRESHOLD) {
        discard;
    }

    float edgeFactor = clamp((nearAvg - alpha) * 4.2 + (1.0 - alpha) * 0.28, 0.0, 1.0);
    vec3 finalColor = texColor.rgb + (GLOW_COLOR * edgeFactor * 0.30);
    gl_FragColor = vec4(finalColor, alpha);
}
