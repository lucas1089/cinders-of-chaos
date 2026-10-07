// Rarity: Prismatic (animated rainbow)
// Flows the seven rainbow colors across the item's own sprite, scrolling over
// time. Used for the upcoming Divine rarity (currently testing on Strange).
// Vertex shader: item_transmute_blackout_vertex (standard item vertex).
uniform float u_Time;
uniform sampler2D u_Tex0;
varying vec2 v_TexCoord;

// How strongly the rainbow overrides the sprite's own colors (0 = original, 1 = full rainbow).
const float STRENGTH = 0.85;
// Spatial frequency of the gradient across the sprite (higher = more color bands at once).
const float FREQ = 1.1;
// Scroll speed of the rainbow (hue cycles per second).
const float SPEED = 0.18;

// Cheap HSV hue -> RGB (h in 0..1). Produces a smooth rainbow sweep.
vec3 hue2rgb(float h) {
    h = fract(h);
    return clamp(vec3(
        abs(h * 6.0 - 3.0) - 1.0,
        2.0 - abs(h * 6.0 - 2.0),
        2.0 - abs(h * 6.0 - 4.0)
    ), 0.0, 1.0);
}

void main()
{
    vec4 col = texture2D(u_Tex0, v_TexCoord);
    // Skip fully-transparent texels so only the item body is tinted.
    if (col.a < 0.01) {
        discard;
    }

    // Diagonal spatial gradient + time scroll => the seven colors flow across the sprite.
    float hue = fract((v_TexCoord.x + v_TexCoord.y) * FREQ - u_Time * SPEED);
    vec3 rainbow = hue2rgb(hue);

    // Keep the sprite's own shading (light/dark detail) by modulating the rainbow
    // with the sprite luminance, so the item stays readable instead of a flat blob.
    float lum = dot(col.rgb, vec3(0.299, 0.587, 0.114));
    vec3 prismatic = rainbow * (0.35 + 0.85 * lum);

    // Blend the prismatic color over the original sprite.
    vec3 outColor = mix(col.rgb, prismatic, STRENGTH);

    gl_FragColor = vec4(outColor, col.a);
}
