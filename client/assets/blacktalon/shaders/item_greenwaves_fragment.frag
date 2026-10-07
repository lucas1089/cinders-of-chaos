// Item shader: animated green "soul energy" waves overlaid on the sprite.
// Unlike the UI-fill greenwaves shader, this one samples the item texture and
// keeps its alpha, so the sprite stays visible (used by the awakened
// Soulbound Pearl from the Eternal Depths storyline).

uniform sampler2D u_Tex0;
uniform float u_Time;

varying vec2 v_TexCoord;

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);

    // Preserve the sprite silhouette: fully transparent pixels stay empty
    if (texColor.a < 0.01)
        discard;

    // Diagonal energy waves flowing across the sprite
    float wave = sin((v_TexCoord.x + v_TexCoord.y) * 60.0 - u_Time * 2.0) * 0.5 + 0.5;

    // Slow breathing pulse so the effect reads even on tiny sprites
    float pulse = sin(u_Time * 1.5) * 0.5 + 0.5;

    vec3 greenLight = vec3(0.35, 1.0, 0.35);
    vec3 greenDark  = vec3(0.0, 0.55, 0.1);
    vec3 waveColor  = mix(greenDark, greenLight, wave);

    // Tint strength oscillates between subtle and pronounced, never opaque
    float tint = 0.25 + 0.30 * (0.5 * wave + 0.5 * pulse);
    vec3 finalColor = mix(texColor.rgb, waveColor, tint);

    gl_FragColor = vec4(finalColor, texColor.a);
}
