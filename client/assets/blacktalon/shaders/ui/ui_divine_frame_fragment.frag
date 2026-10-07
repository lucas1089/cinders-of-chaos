// UI Divine Frame - fragment
// Recolors a rarity frame/border image (e.g. the green rarity square) to a
// silver/white with a gentle diagonal shimmer, keeping the image's shape (alpha).
// Pairs with ui_prismatic_vertex (provides normalized v_TexCoord).
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

varying vec2 v_TexCoord;

void main()
{
    vec4 tex = texture2D(u_Tex0, v_TexCoord);

    // Gentle diagonal shimmer over a bright silver, driven by the frame's own
    // luminance so its shading/detail is preserved (not a flat white fill).
    float lum = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    float shimmer = 0.85 + 0.15 * sin((v_TexCoord.x + v_TexCoord.y) * 3.14159265 - u_Time * 2.0);
    vec3 silver = vec3(0.95, 0.97, 1.00) * (0.45 + 0.75 * lum) * shimmer;

    gl_FragColor = vec4(silver, tex.a) * u_Color;
}
