// Phase 8, track C: the outfit shaders, hit flash, silhouette and living ground of the main client's GLSL files (client/overlay/data/shaders) as
// one HLSL function, so the classic map shader (ChaosMapFx.shader) and the surface shaders of the HD-2D and live views share them.
// The mode numbers are Core/Phase8CFx.cs FxMode (Phase8CTests keeps them in step with the defines here). Noise is laid out in sprite pixels (px), time in seconds.
#ifndef CHAOS_FX_INCLUDED
#define CHAOS_FX_INCLUDED

#define FX_HAZE 1
#define FX_WAVES 2
#define FX_PULSE 3
#define FX_SPARKS 4
#define FX_EMBER 10
#define FX_FROST 11
#define FX_VOID 12
#define FX_HOLY 13
#define FX_BLOOD 14
#define FX_GHOST 15
#define FX_ASH 16
#define FX_CROWN 17
#define FX_HITWHITE 20
#define FX_HITRED 21
#define FX_SOLID 22
#define FX_ITEMGLOW 23
#define FX_METAL 24
#define FX_WATER 30
#define FX_LAVA 31

float FxLuma(float3 c) { return dot(c, float3(0.30, 0.58, 0.12)); }

float FxHash(float2 c)
{
    c = frac(c * float2(0.2713, 0.4127) + float2(0.11, 0.73));
    c += dot(c, c.yx + 23.17);
    return frac((c.x + 0.37) * (c.y + 0.61) * 47.3);
}

float FxNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    float2 s = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(FxHash(i), FxHash(i + float2(1.0, 0.0)), s.x),
                lerp(FxHash(i + float2(0.0, 1.0)), FxHash(i + float2(1.0, 1.0)), s.x), s.y);
}

// the store families (bloohs "turn metal", dortmond / energizer / pixent "emboss"); uv is 0..1 over the sprite cell
float4 FxFamily(int mode, float4 c, float2 uv, float4 tint, float t)
{
    float time = t * 0.25;
    float3 tex = c.rgb;
    float4 r;
    float2 q = uv * 2.5;
    if (mode == FX_HAZE)
    {
        float a = time * 0.05 * 50.0;
        float n = sin(a + 2.0 * q.x) + sin(a - 2.0 * q.x) + sin(a + 2.0 * q.y) + sin(a + 5.0 * q.y);
        n += tex.r * 0.21 + tex.g * 0.4 + tex.b * 0.2;
        n = n - floor(n);
        float tx = n * 6.0;
        float m = saturate(tx - 2.0) + saturate(2.0 - tx);
        float3 s = float3(1.0, 1.0, 1.0) * (1.0 - m);
        s = 0.05 + s * 0.5 + dot(s, float3(0.2126, 0.2152, 0.1722)) * 0.5;
        r = float4(s * tint.rgb, c.a);
    }
    else
    {
        float k = mode == FX_WAVES ? 1.0 : (mode == FX_PULSE ? 5.0 : 10.0);
        float a = time * k;
        float metal = length(float2(sin(a + 2.0 * q.x), sin(a - 2.0 * q.x) + sin(a + 2.0 * q.y) + sin(a + 5.0 * q.y)));
        metal += tex.r * 0.21 + tex.g * 0.4 + tex.b * 0.2;
        metal = metal - floor(metal);
        float lo = mode == FX_WAVES ? 0.45 : 0.001;
        float hi = mode == FX_WAVES ? 0.55 : 0.05;
        metal = smoothstep(lo, hi, metal);
        float fx = mode == FX_WAVES ? 2.0 : 300.0;
        float fy = mode == FX_WAVES ? 2.0 : 250.0;
        float spd = mode == FX_WAVES ? 1.0 : 3.0;
        float n = abs(sin(q.x * fx + t * spd) + cos(q.y * fy + t * spd));
        float i = mode == FX_WAVES ? n * n : pow(max(n, 0.0001), mode == FX_PULSE ? 0.1 : 0.2);
        float3 s = float3(1.0, 1.0, 1.0) * (1.0 - metal);
        s = 0.05 + s * 0.5 + dot(s, float3(0.2126, 0.2152, 0.1722)) * 0.5;
        s = lerp(tint.rgb, s, metal);
        r = float4(s * tint.rgb * min(i * 6.0, 2.0), c.a);
    }
    // a trace of the sprite's own shading keeps the figure readable
    r.rgb = saturate(r.rgb) * 0.85 + tex * 0.15;
    return r;
}

// px: pixel inside the atlas (noise coordinates), cellY: 0 at the bottom of the cell, 1 at the top; rim: 1 at the silhouette's inner edge
float4 FxOutfit(int mode, float4 c, float2 px, float cellY, float rim, float t)
{
    float l = FxLuma(c.rgb);
    float3 col = c.rgb;
    float a = c.a;
    if (mode == FX_EMBER)
    {
        float flick = FxNoise(px * 0.18 + float2(0.0, t * 2.4));
        float3 ember = lerp(float3(1.0, 0.32, 0.05), float3(1.0, 0.78, 0.25), flick);
        float warm = 0.18 + 0.22 * FxNoise(px * 0.07 + float2(t * 0.3, t * 0.9));
        col = c.rgb * (1.0 + warm * float3(0.55, 0.22, 0.0));
        col = lerp(col, ember, rim * (0.55 + 0.45 * flick));
        float spark = FxNoise(float2(px.x * 0.9, px.y * 0.35 + t * 6.0));
        col += float3(1.0, 0.65, 0.2) * smoothstep(0.93, 0.99, spark) * 0.9;
    }
    else if (mode == FX_FROST)
    {
        float3 ice = lerp(float3(0.20, 0.38, 0.62), float3(0.85, 0.95, 1.0), l);
        col = lerp(c.rgb, ice, 0.55);
        col = lerp(col, float3(0.88, 0.97, 1.0), rim * 0.75);
        float2 cell = floor(px / 3.0);
        float seed = FxHash(cell);
        float glint = pow(max(0.0, sin(t * 2.0 + seed * 40.0)), 24.0) * step(0.82, seed);
        col += float3(0.9, 0.97, 1.0) * glint * 0.85;
        float frost = smoothstep(0.55, 0.85, FxNoise(px * 0.22 + float2(t * 0.05, 0.0)));
        col = lerp(col, float3(0.92, 0.97, 1.0), frost * 0.25);
    }
    else if (mode == FX_VOID)
    {
        col = lerp(float3(0.03, 0.0, 0.06), float3(0.42, 0.18, 0.62), l * 0.9) + c.rgb * 0.18;
        float flick = step(0.35, FxNoise(float2(t * 9.0, 3.1)));
        col = lerp(col, float3(0.72, 0.38, 1.0), rim * (0.35 + 0.65 * flick));
        float slot = floor(t * 3.0);
        float bandY = FxHash(float2(slot, 7.0)) * 64.0;
        float band = smoothstep(2.5, 0.0, abs(fmod(px.y, 64.0) - bandY)) * step(0.6, FxHash(float2(slot, 1.0)));
        float specks = step(0.9, FxNoise(px * 0.6 + float2(t * 4.0, -t * 3.0)));
        a = c.a * (1.0 - 0.75 * band) * (1.0 - 0.5 * specks);
    }
    else if (mode == FX_HOLY)
    {
        float breath = 0.5 + 0.5 * sin(t * 1.6);
        float3 gold = float3(1.0, 0.86, 0.45);
        col = c.rgb * (1.0 + 0.25 * breath) + gold * 0.12 * breath;
        float ray = sin((px.x * 0.8 - px.y * 0.35) * 0.35 + t * 1.3);
        col += gold * smoothstep(0.75, 1.0, ray) * 0.35;
        col = lerp(col, float3(1.0, 0.97, 0.82), rim * (0.45 + 0.35 * breath));
    }
    else if (mode == FX_BLOOD)
    {
        float ph = frac(t / 1.15);
        float b1 = (ph - 0.08) / 0.05;
        float b2 = (ph - 0.26) / 0.05;
        float beat = exp(-b1 * b1) + 0.7 * exp(-b2 * b2);
        float3 blood = float3(0.75, 0.04, 0.06);
        col = lerp(c.rgb, c.rgb * float3(1.0, 0.45, 0.45) + blood * 0.35, 0.35 + 0.4 * beat);
        float n = FxNoise(px * 0.16 + float2(0.0, t * 0.1));
        float vein = smoothstep(0.06, 0.0, abs(n - 0.5));
        col = lerp(col, float3(1.0, 0.15, 0.12), vein * (0.25 + 0.6 * beat));
        col = lerp(col, float3(0.9, 0.08, 0.1), rim * 0.5 * beat);
    }
    else if (mode == FX_GHOST)
    {
        col = lerp(float3(0.55, 0.85, 0.85), float3(0.92, 1.0, 1.0), l);
        float wave = 0.5 + 0.5 * sin(px.y * 0.45 + t * 3.0);
        col += float3(0.2, 0.35, 0.35) * wave * 0.4;
        col = lerp(col, float3(0.75, 1.0, 1.0), rim * 0.7);
        a = c.a * (0.42 + 0.22 * wave + 0.25 * rim) * (0.85 + 0.15 * sin(t * 2.2));
    }
    else if (mode == FX_ASH)
    {
        col = lerp(c.rgb, float3(l * 0.92, l * 0.88, l * 0.84), 0.5);
        float breath = 0.5 + 0.5 * sin(t * 1.6);
        col = lerp(col, float3(0.86, 0.80, 0.72), rim * (0.35 + 0.30 * breath));
        // the atlas has y up: the flakes fall when the pattern moves toward smaller y
        float flake = FxNoise(float2(px.x * 0.6 + sin(t * 0.7) * 2.0, px.y * 0.6 + t * 3.5));
        col = lerp(col, float3(0.78, 0.76, 0.74), smoothstep(0.90, 0.97, flake) * 0.75);
        float ember = FxNoise(px * 0.25 + float2(t * 0.4, t * 1.1));
        col += float3(0.9, 0.35, 0.08) * smoothstep(0.95, 0.995, ember) * 0.8;
    }
    else if (mode == FX_CROWN)
    {
        float up = saturate(cellY);
        float heat = FxNoise(float2(px.x * 0.12 + t * 0.5, px.y * 0.2 + t * 2.0));
        float3 coal = lerp(float3(0.75, 0.12, 0.02), float3(1.0, 0.62, 0.18), heat);
        col = lerp(c.rgb, c.rgb * 0.6 + coal * 0.6, smoothstep(0.35, 0.9, up) * (0.45 + 0.35 * heat));
        col = lerp(col, float3(1.0, 0.72, 0.30), rim * smoothstep(0.4, 1.0, up) * (0.6 + 0.4 * sin(t * 3.0 + px.x * 0.3)));
        col += float3(0.25, 0.08, 0.0) * (0.5 + 0.5 * sin(t * 2.2)) * l;
    }
    return float4(min(col, float3(1.0, 1.0, 1.0)), a);
}

// one entry for every mode but the liquids (they move the texture read, see ChaosMapFx.shader).
// strength 0..1 is the second number of the mode, tint the colour of the family or of the silhouette.
float4 FxApply(float mode, float strength, float4 c, float2 px, float2 cellUv, float rim, float4 tint, float t)
{
    int m = (int)(mode + 0.5);
    if (m == 0) return c;
    if (m >= FX_EMBER && m <= FX_CROWN) return FxOutfit(m, c, px, cellUv.y, rim, t);
    if (m >= FX_HAZE && m <= FX_SPARKS) return FxFamily(m, c, cellUv, tint, t);
    if (m == FX_HITWHITE)
    {
        float l = FxLuma(c.rgb);
        return float4(lerp(c.rgb, float3(1.0, 1.0, 1.0) * (0.80 + 0.35 * l), 0.78 * strength), c.a);
    }
    if (m == FX_HITRED)
    {
        float l = FxLuma(c.rgb);
        return float4(lerp(c.rgb, float3(1.0, 0.16, 0.12) * (0.80 + 0.35 * l), 0.62 * strength), c.a);
    }
    if (m == FX_SOLID) return float4(tint.rgb, c.a * tint.a);
    // phase 9, track D. The rarity glow of an item: the silhouette in the rarity colour. strength 0 is steady; above 0 it is the pulse period in 4 s units (0.55 = 2.2 s),
    // the colour breathing between half and full. Views that cut out by alpha get the falloff in the colour (tint already dimmed), the classic view in tint.a.
    if (m == FX_ITEMGLOW)
    {
        float k = 1.0;
        if (strength > 0.001)
        {
            float period = max(0.2, strength * 4.0);
            k = 0.5 + 0.5 * (0.5 - 0.5 * cos(6.2831853 * frac(t / period)));
        }
        return float4(tint.rgb * k, c.a * tint.a);
    }
    // The Divine metal look (game_itemrarity metal style: tint #22e5ff, strength 0.5): the sprite's own colours turned to a moving metal in the tint, strength says how far,
    // and a thin bright band sweeps across it. The store family "haze" is the metal of the main client's own shader families.
    if (m == FX_METAL)
    {
        float4 f = FxFamily(FX_HAZE, c, cellUv, tint, t);
        float sw = sin((cellUv.x + cellUv.y) * 7.0 - t * 2.4);
        float3 col = lerp(c.rgb, f.rgb, saturate(strength));
        col += float3(0.8, 1.0, 1.0) * smoothstep(0.92, 1.0, sw) * saturate(strength);
        return float4(min(col, float3(1.0, 1.0, 1.0)), c.a);
    }
    return c;
}

// the living ground: a ripple of one texel at most and a brightness wave; norm is -1..1 across the tile
float2 FxLiquidShift(int mode, float2 norm, float2 texel, float t)
{
    float2 edge = saturate((1.0 - abs(norm)) * 8.0);
    float w = edge.x * edge.y;
    float2 ph = 3.14159 * norm;
    if (mode == FX_LAVA)
        return float2(sin(t * 0.8 + ph.x + ph.y), cos(t * 0.7 + ph.x - 2.0 * ph.y)) * texel * w;
    return float2(sin(t * 1.3 + ph.x + 2.0 * ph.y), cos(t * 1.1 + 2.0 * ph.x - ph.y)) * texel * w;
}

float FxLiquidGain(int mode, float2 norm, float t)
{
    float2 ph = 3.14159 * norm;
    if (mode == FX_LAVA)
    {
        float swell = 0.5 + 0.5 * sin(t * 1.2 + ph.x + 2.0 * ph.y);
        return 0.94 + 0.18 * swell;
    }
    return 1.0 + 0.035 * sin(t * 0.9 + ph.x + ph.y);
}

#endif
