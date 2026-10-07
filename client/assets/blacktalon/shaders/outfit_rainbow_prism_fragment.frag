uniform mat4 u_Color;
varying vec2 v_TexCoord;
varying vec2 v_TexCoord2;
varying vec2 v_TexCoord3;
uniform sampler2D u_Tex0;
uniform vec2 u_Resolution;
uniform float u_Time;

// How much of the rainbow overrides the outfit's own colors (0 = keep outfit, 1 = full rainbow).
float rainbowIntensity = 0.85;

// Pure-hue color from a 0..1 value. Produces the full arco-iris spectrum
// (red -> orange -> yellow -> green -> blue -> indigo -> violet) with smooth blends.
vec3 hue2rgb(float h) {
    h = fract(h);
    float r = abs(h * 6.0 - 3.0) - 1.0;
    float g = 2.0 - abs(h * 6.0 - 2.0);
    float b = 2.0 - abs(h * 6.0 - 4.0);
    return clamp(vec3(r, g, b), 0.0, 1.0);
}

void main() {
    // Sample the sprite; skip fully transparent pixels.
    vec4 baseColor = texture2D(u_Tex0, v_TexCoord);
    if (baseColor.a < 0.01) {
        discard;
    }

    // Animated time coming from the vertex shader (u_Time * rainbowSpeed).
    float t = v_TexCoord3.x;

    // Diagonal rainbow band flowing across the body and scrolling over time.
    // The large multiplier makes several color bands visible over a single sprite.
    float hue = (v_TexCoord.x + v_TexCoord.y) * 6.0 - t;
    vec3 rainbow = hue2rgb(hue);

    // Preserve the sprite's own shading (light/dark detail) by modulating the
    // rainbow with the original pixel luminance instead of flat-filling it.
    float luminance = dot(baseColor.rgb, vec3(0.299, 0.587, 0.114));
    vec3 tinted = rainbow * (0.35 + 0.65 * luminance);

    // Blend toward the rainbow while keeping a hint of the original detail.
    vec3 finalColor = mix(baseColor.rgb, tinted, rainbowIntensity);

    gl_FragColor = vec4(finalColor, baseColor.a);
}
