// Ground and sprite classification by pixels (World3d, Unity only). Pure C#, no Unity types, so it builds in Core.Tests.
// The real maps use thousands of ground and nature items; no table of ids. Every sprite is read from the atlas as raw RGBA
// and measured (Stats): mean colour of the opaque pixels, its hue / saturation / value, the spread of the luma, the opaque share,
// the direction of the luma gradient (Grain: planks have lines, dirt is noise) and the share of green, grey and brown pixels.
// Ground (Classify), in this order, hue in degrees, all numbers of the mean colour unless said:
//   mostly clear (opaque share < 0.5)                              Unknown
//   value < 0.14                                                   Dark     (void, black ground)
//   orange-red, bright (R >= 0.7, sat >= 0.7, value >= 0.7;        Lava     (animated or lit by the dat: R >= 0.55, sat >= 0.6, value >= 0.55)
//   blue to cyan (hue 170..255), sat >= 0.4 (animated: 0.25)       Water    (animated = more than one phase in the dat)
//   bright and grey-white (value >= 0.78, sat < 0.22)              Snow
//   grey (sat < 0.17)                                              Stone
//   green (hue 65..165, sat >= 0.22)                               Grass
//   pale yellow-brown (hue 36..65, value >= 0.62, sat < 0.65)      Sand
//   brown (hue 8..65): lines (Grain >= 0.3), sat >= 0.35           Wood, else Dirt
//   anything else with sat < 0.3                                   Stone, else Unknown
// The class of an item is cached by item id (SpriteClassifier). Upright things use the shares (Hd2dWorld3d.RoleOf).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public enum GroundClass { Unknown, Stone, Grass, Dirt, Sand, Water, Lava, Snow, Wood, Dark }

    /// <summary>What the pixels of a sprite (or a few) say. Colours are 0..1 sRGB, hue in degrees.</summary>
    public struct SpriteStats
    {
        public float R, G, B;                 // mean of the opaque pixels
        public float Hue, Sat, Value;         // of the mean colour
        public float Spread;                  // standard deviation of the luma of the opaque pixels
        public float Alpha;                   // share of opaque pixels (alpha >= 128)
        public float Grain;                   // 0 noise .. 1 lines in one direction
        public float GreenShare, GreyShare, BrownShare;
    }

    /// <summary>The cached look of an item type.</summary>
    public struct SpriteInfo
    {
        public SpriteStats Stats;
        public GroundClass Class;   // meaningful for ground
        public bool Animated;
    }

    /// <summary>Sums sprites into one SpriteStats.</summary>
    public sealed class StatsBuilder
    {
        double sr, sg, sb, sl, sl2, gx, gy;
        long n, total, green, grey, brown;

        public void Add(byte[] rgba, int w, int h)
        {
            if (rgba == null || rgba.Length < w * h * 4) return;
            total += w * h;
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    int i = (y * w + x) * 4;
                    if (rgba[i + 3] < 128) continue;
                    float r = rgba[i] / 255f, g = rgba[i + 1] / 255f, b = rgba[i + 2] / 255f;
                    float l = Luma(r, g, b);
                    n++; sr += r; sg += g; sb += b; sl += l; sl2 += l * l;
                    Hsv(r, g, b, out float hue, out float sat, out float val);
                    if (val >= 0.12f)
                    {
                        if (sat >= 0.25f && hue >= 65f && hue <= 170f) green++;
                        else if (sat < 0.15f) grey++;
                        else if (sat >= 0.15f && sat <= 0.75f && hue >= 12f && hue <= 50f && val <= 0.75f) brown++;
                    }
                    if (x + 1 < w && rgba[i + 7] >= 128) gx += Math.Abs(Luma(rgba[i + 4] / 255f, rgba[i + 5] / 255f, rgba[i + 6] / 255f) - l);
                    if (y + 1 < h && rgba[i + w * 4 + 3] >= 128) gy += Math.Abs(Luma(rgba[i + w * 4] / 255f, rgba[i + w * 4 + 1] / 255f, rgba[i + w * 4 + 2] / 255f) - l);
                }
        }

        public static float Luma(float r, float g, float b) => 0.299f * r + 0.587f * g + 0.114f * b;

        public static void Hsv(float r, float g, float b, out float hue, out float sat, out float val)
        {
            float mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b)), d = mx - mn;
            val = mx;
            sat = mx <= 0f ? 0f : d / mx;
            if (d <= 1e-6f) { hue = 0f; return; }
            if (mx == r) hue = 60f * (((g - b) / d) % 6f);
            else if (mx == g) hue = 60f * ((b - r) / d + 2f);
            else hue = 60f * ((r - g) / d + 4f);
            if (hue < 0f) hue += 360f;
        }

        public SpriteStats Result()
        {
            var s = new SpriteStats();
            if (total == 0 || n == 0) return s;
            s.Alpha = (float)n / total;
            s.R = (float)(sr / n); s.G = (float)(sg / n); s.B = (float)(sb / n);
            Hsv(s.R, s.G, s.B, out s.Hue, out s.Sat, out s.Value);
            double mean = sl / n;
            s.Spread = (float)Math.Sqrt(Math.Max(0.0, sl2 / n - mean * mean));
            double g = gx + gy;
            s.Grain = g > 1e-6 ? (float)(Math.Abs(gx - gy) / g) : 0f;
            s.GreenShare = (float)green / n; s.GreyShare = (float)grey / n; s.BrownShare = (float)brown / n;
            return s;
        }
    }

    public static class Hd2dTerrain
    {
        /// <summary>Stats of one 32 x 32 (or w x h) RGBA block.</summary>
        public static SpriteStats Stats(byte[] rgba, int w = 32, int h = 32)
        {
            var b = new StatsBuilder();
            b.Add(rgba, w, h);
            return b.Result();
        }

        /// <summary>The ground class of measured pixels. `animated`: the dat has several phases; `lit`: the dat gives it a light.</summary>
        public static GroundClass Classify(SpriteStats s, bool animated = false, bool lit = false)
        {
            if (s.Alpha < 0.5f) return GroundClass.Unknown;
            float h = s.Hue, sat = s.Sat, v = s.Value;
            if (v < 0.14f) return GroundClass.Dark;
            bool warm = h <= 42f || h >= 345f;
            bool glow = animated || lit;
            if (warm && (s.R >= 0.7f && sat >= 0.7f && v >= 0.7f || glow && s.R >= 0.55f && sat >= 0.6f && v >= 0.55f)) return GroundClass.Lava;
            if (h >= 170f && h <= 255f && sat >= (animated ? 0.25f : 0.4f)) return GroundClass.Water;
            if (v >= 0.78f && sat < 0.22f) return GroundClass.Snow;
            if (sat < 0.17f) return GroundClass.Stone;
            if (h >= 65f && h <= 165f && sat >= 0.22f) return GroundClass.Grass;
            if (h >= 36f && h < 65f && v >= 0.62f && sat < 0.65f) return GroundClass.Sand;
            if (h >= 8f && h < 65f) return s.Grain >= 0.3f && sat >= 0.35f ? GroundClass.Wood : GroundClass.Dirt;
            return sat < 0.3f ? GroundClass.Stone : GroundClass.Unknown;
        }

        // ---- the 3D tile look ----------------------------------------------------------------------------------------

        /// <summary>The top of a terrain tile sits a little under the flat sprites (like the ruins floor); water and lava lie lower.</summary>
        public const float TileTop = Hd2dRuins.FloorY, WaterY = -0.16f, LavaY = -0.12f, TileThickness = 0.25f;

        /// <summary>How a terrain tile is drawn: the sprite's mean colour keeps the map's palette, then the dark fantasy restyle
        /// (a little less saturated, darker per class). Water is a deep blue only a little tinted by the sprite, glossy; lava is
        /// emissive orange. Only Grass, Dirt, Sand, Snow, Dark, Water and Lava have a tile (Stone and Wood use the ruins floors).</summary>
        public static RuinsStyle TileStyle(GroundClass c, float r, float g, float b)
        {
            float lum = StatsBuilder.Luma(r, g, b);
            if (c == GroundClass.Water)
            {
                float k = 0.4f;
                return new RuinsStyle { R = Hd2dRuinsMath.Lerp(0.04f, r * 0.5f, k), G = Hd2dRuinsMath.Lerp(0.10f, g * 0.5f, k), B = Hd2dRuinsMath.Lerp(0.20f, b * 0.55f, k), Smoothness = 0.85f };
            }
            if (c == GroundClass.Lava)
            {
                float mx = Math.Max(0.01f, Math.Max(r, Math.Max(g, b)));
                return new RuinsStyle { R = r * 0.45f, G = g * 0.3f, B = b * 0.3f, EmitR = r / mx * 1.8f, EmitG = g / mx * 1.8f * 0.8f, EmitB = b / mx * 1.8f * 0.5f, Smoothness = 0.1f };
            }
            float keep = 0.85f, dark;
            switch (c)
            {
                case GroundClass.Grass: dark = 0.62f; break;
                case GroundClass.Snow: dark = 0.7f; keep = 0.9f; break;
                case GroundClass.Sand: dark = 0.62f; break;
                case GroundClass.Dark: dark = 0.8f; break;
                default: dark = 0.6f; break;
            }
            float mr = lum + (r - lum) * keep, mg = lum + (g - lum) * keep, mb = lum + (b - lum) * keep;
            return new RuinsStyle { R = Hd2dRuinsMath.Clamp01(mr * dark), G = Hd2dRuinsMath.Clamp01(mg * dark), B = Hd2dRuinsMath.Clamp01(mb * dark), Smoothness = 0.04f };
        }
    }

    /// <summary>Measures item types through a sprite source and remembers the result by item id.</summary>
    public sealed class SpriteClassifier
    {
        readonly Func<uint, byte[]> sprite;
        readonly Dictionary<int, SpriteInfo> cache = new Dictionary<int, SpriteInfo>();
        /// <summary>Items measured so far (the cache size).</summary>
        public int Count => cache.Count;

        /// <summary>`sprite` gives a sprite's 32 x 32 RGBA, or null.</summary>
        public SpriteClassifier(Func<uint, byte[]> sprite) { this.sprite = sprite; }

        public SpriteInfo Info(ThingType t)
        {
            if (t == null || t.Idle == null || t.Idle.Sprites == null) return default;
            if (cache.TryGetValue(t.Id, out var v)) return v;
            var g = t.Idle;
            var b = new StatsBuilder();
            bool animated = g.Phases > 1;
            if (t.Ground)
            {
                // a ground tile: the first cell, every phase (water moves), up to 8
                int phases = Math.Min(8, Math.Max(1, g.Phases));
                for (int ph = 0; ph < phases; ph++) b.Add(sprite(g.Sprite(0, 0, 0, 0, 0, 0, ph)), 32, 32);
            }
            else
                for (int hh = 0; hh < g.Height; hh++)
                    for (int ww = 0; ww < g.Width; ww++)
                        b.Add(sprite(g.Sprite(ww, hh, 0, 0, 0, 0, 0)), 32, 32);
            v.Stats = b.Result();
            v.Animated = animated;
            v.Class = t.Ground ? Hd2dTerrain.Classify(v.Stats, animated, t.LightLevel > 0) : GroundClass.Unknown;
            cache[t.Id] = v;
            return v;
        }

        public GroundClass Ground(ThingType t) => Info(t).Class;
    }

    static class Hd2dRuinsMath
    {
        public static float Clamp01(float v) => v < 0f ? 0f : v > 1f ? 1f : v;
        public static float Lerp(float a, float b, float k) => a + (b - a) * k;
    }
}
