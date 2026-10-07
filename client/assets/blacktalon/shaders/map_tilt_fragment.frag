
// 2.5D perspective tilt for the map floor. Post-process warp of the map FBO:
// samples the framebuffer so the flat top-down floor reads as a floor receding
// away from the viewer. Free-standing things (creatures/effects/missiles) are
// corrected on the CPU in thingtype.cpp so they stay upright inside this warp.
//
// The warp is derived from v_TexCoord (map texture coords). Because u_TiltCenter
// is normalized by the SAME framebuffer size the blit uses, the map scroll
// cancels out of ny, so the warp is stable during walking. (An earlier attempt to
// anchor only the vertical axis to gl_FragCoord mixed coordinate systems and made
// it WORSE — keep both axes on v_TexCoord.)
//
// Stays numerically in lock-step with src/client/tilt.h: ny here == s/hy there,
// so the CPU sprite/overlay/picking corrections match. The OTClientV8 map FBO is
// v-UP, hence ny = -q.y and uv.y = c.y - vy.

varying vec2 v_TexCoord;
uniform vec4 u_Color;
uniform sampler2D u_Tex0;

uniform vec2 u_TiltCenter;   // visible-window center in texture uv
uniform vec4 u_TiltParams;   // x = K, y = vp (vertical perspective 0..1), z = half-height in uv, w = unused

void main()
{
    // u_TiltCenter is fed in y-DOWN framebuffer coords, but v_TexCoord is v-UP
    // (the FBO texture is flipped). Statically the window sits ~centered so the
    // difference is invisible — but while WALKING the srcRect slides, and an
    // unflipped center slides the WRONG WAY in texture space: the warped floor
    // drifts at ~(1-K)x the true rate and snaps back one tile at every step
    // boundary (K-proportional, vertical-only lurch; names/overlays stay put).
    // Flipping v here puts the center in the same v-up space as v_TexCoord.
    vec2  c     = vec2(u_TiltCenter.x, 1.0 - u_TiltCenter.y);
    float K     = u_TiltParams.x;
    float vp    = u_TiltParams.y;
    float halfV = max(u_TiltParams.z, 1e-4);

    vec2  q  = v_TexCoord - c;
    float ny = -q.y / halfV;                 // -1 = top (far), +1 = bottom (near); v-up texture
    float D  = max(1.0 + K * ny, 0.05);      // matches Tilt::Dof_s

    // Horizontal: trapezoid narrowing toward the top (this alone reads as a tilt).
    float m  = (1.0 - K) / D;
    // Vertical: blend projective (vp=1, foreshortens) and linear (vp=0, rigid).
    // Matches Tilt::inv().
    float vy = (1.0 - K) * ny * halfV * ((1.0 - vp) + vp / D);

    vec2 uv;
    uv.x = c.x + q.x * m;
    uv.y = c.y - vy;                         // v-up texture: subtract the y-down offset
    uv = clamp(uv, vec2(0.0005), vec2(0.9995));

    vec4 color = texture2D(u_Tex0, uv) * u_Color;

    // Optional cosmetic depth haze on the far rows. Purely aesthetic.
    float haze = clamp((-ny - 0.6) / 0.4, 0.0, 1.0) * 0.14;
    color.rgb = mix(color.rgb, vec3(0.05, 0.06, 0.08), haze);

    if (color.a < 0.01)
        discard;
    gl_FragColor = color;
}
