// Name Gothic Shader - WHITE letters wrapped by a living BLACK OUTLINE: dark
// energy flows around the edge of each letter (the outline thickens/crawls with
// animated noise) like a black aura hugging the glyph shapes. Everything stays
// ON the letters (no box, no companion canvas).
// donor client MMORPG.
//
// Uses name_sweep_vertex: v_TexCoord = per-glyph atlas coord (glyph sample),
// v_LocalPos = text-local pixel position (drives coherent flow across the name).
// The verdana-11px-rounded font bakes a black outline into the atlas; `fill`
// (luminance) separates the white body from that outline/edge.

varying vec2 v_TexCoord;
varying vec2 v_LocalPos;
uniform sampler2D u_Tex0;
uniform float u_Time;
uniform vec4 u_Color;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p)
{
    float v = 0.0;
    float a = 0.5;
    for (int k = 0; k < 4; k++) {
        v += a * vnoise(p);
        p *= 2.02;
        a *= 0.5;
    }
    return v;
}

void main()
{
    vec4 texColor = texture2D(u_Tex0, v_TexCoord);
    if (texColor.a < 0.01) {
        discard;
    }

    float t = mod(u_Time, 6000.0);

    // fill: 1 in the white body, 0 in the baked outline / at the edge.
    float luminance = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));
    float fill = smoothstep(0.25, 0.6, luminance);

    // Flowing noise that drifts across the whole name over time (drives both the
    // living outline and the dissolve transition below).
    float flow = fbm(v_LocalPos * 0.45 + vec2(t * 0.9, -t * 1.2));

    // Living outline: gated to the edge/outline band (fill low), the flow makes it
    // crawl and pulse its thickness inward from the letter edge.
    float edgeGate = 1.0 - smoothstep(0.25, 0.65, fill); // 1 at outline/edge -> 0 in body
    float auraOutline = edgeGate * smoothstep(0.30, 0.75, flow);
    float outlineAmt = clamp(max(1.0 - fill, auraOutline), 0.0, 1.0);

    // The two colour schemes the name alternates between.
    vec3 black = vec3(0.02, 0.02, 0.03);
    vec3 white = vec3(0.95, 0.95, 0.98);
    vec3 colA = mix(black, white, outlineAmt); // state A: BLACK body + WHITE outline
    vec3 colB = mix(white, black, outlineAmt); // state B: WHITE body + BLACK outline

    // Alternation: dwell ~20s in each scheme, then flip. The flip is a NOISE
    // DISSOLVE - each pixel switches as the global 'blend' crosses its drifting
    // noise value - so the name keeps its contrast during the transition instead
    // of washing out to grey. A little wobble keeps the timing feeling ~15-25s.
    float CYCLE = 40.0;                        // full A->B->A seconds (~flip every 20s)
    float tPhase = t + 3.0 * sin(t * 0.05);    // organic wobble on the timing
    float cyc = fract(tPhase / CYCLE);
    float tri = abs(cyc * 2.0 - 1.0);          // 1 at ends (A), 0 in the middle (B)
    float blend = smoothstep(0.30, 0.70, tri); // 1 = colA, 0 = colB (dwell + transition)
    float diss = smoothstep(flow - 0.10, flow + 0.10, blend);

    vec3 col = mix(colB, colA, diss);
    gl_FragColor = vec4(col, texColor.a * u_Color.a);
}
