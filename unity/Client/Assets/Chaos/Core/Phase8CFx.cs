// Phase 8, track C: the numbers behind the shaders of the visual effect rows (game_chaosshaders, game_nameshaders, game_levelwings, game_lootbeams,
// game_cosmeticfx, game_visualfx). Pure C#, no Unity types: the shaders (Assets/Chaos/Resources/Shaders) only draw what these classes say, the Unity glue
// (Unity/Phase8CFx.cs) copies the numbers into materials. Sources: client/overlay/data/shaders/*.frag and the Lua logic files of the modules.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>The mode numbers the map shaders read from the second UV channel (x = mode, y = strength 0..1). 0 draws the sprite as it is.</summary>
    public static class FxMode
    {
        public const int None = 0;
        // the store families (bloohs, dortmond, energizer, pixent): one function each, the colour comes with the quad
        public const int Haze = 1, Waves = 2, Pulse = 3, Sparks = 4;
        // the Chaos outfit shaders (chaos_outfit_*.frag)
        public const int Ember = 10, Frost = 11, Void = 12, Holy = 13, Blood = 14, Ghost = 15, Ash = 16, Crown = 17;
        // flashes and silhouettes
        public const int HitWhite = 20, HitRed = 21, Solid = 22;
        // phase 9, track D: the soft rarity glow of an item (a silhouette that pulses by itself) and the Divine metal look
        public const int ItemGlow = 23, Metal = 24;
        // living ground (chaos_liquid_*.frag)
        public const int Water = 30, Lava = 31;

        public static bool IsOutfit(int m) => m >= Haze && m <= Crown && !(m > Sparks && m < Ember);
        public static bool IsKnown(int m) => m == None || IsOutfit(m) || m == HitWhite || m == HitRed || m == Solid || m == ItemGlow || m == Metal || m == Water || m == Lava;
    }

    /// <summary>One outfit shader as the shader sees it: a mode and the colour of its family (0..1).</summary>
    public sealed class OutfitFx
    {
        public string Name = "";
        public int Mode;
        public float R = 1, G = 1, B = 1;
        public bool Family => Mode >= FxMode.Haze && Mode <= FxMode.Sparks;
    }

    /// <summary>The 26 outfit shaders of shaders.xml (game_chaosshaders/outfitshaderlist.lua LABELS) by name. A creature's look carries the name (GameParser.ReadOutfit).</summary>
    public static class OutfitFxTable
    {
        static readonly Dictionary<string, OutfitFx> table = Build();

        static void Add(Dictionary<string, OutfitFx> d, string name, int mode, float r, float g, float b)
        {
            d[name] = new OutfitFx { Name = name, Mode = mode, R = r, G = g, B = b };
        }

        static Dictionary<string, OutfitFx> Build()
        {
            var d = new Dictionary<string, OutfitFx>();
            // the colours are the _color of the frag file of each store shader
            Add(d, "blue_loohs", FxMode.Haze, 0.0471f, 0.2510f, 0.6941f);
            Add(d, "bloohs_green", FxMode.Haze, 0.2549f, 0.8824f, 0.0980f);
            Add(d, "bloohs_red", FxMode.Haze, 0.8706f, 0.2157f, 0.0510f);
            Add(d, "bloohs_white", FxMode.Haze, 0.9333f, 0.9412f, 0.9490f);
            Add(d, "blue Dortmond", FxMode.Waves, 0.1020f, 0.1922f, 0.5294f);
            Add(d, "red_dortmond", FxMode.Waves, 0.8824f, 0.2196f, 0.1333f);
            Add(d, "white_dortmond", FxMode.Waves, 0.9490f, 0.9490f, 0.9608f);
            Add(d, "green_dortmond", FxMode.Waves, 0.2275f, 0.7922f, 0.1020f);
            Add(d, "pink_energizer", FxMode.Pulse, 0.5294f, 0.1020f, 0.5216f);
            Add(d, "blue_energizer", FxMode.Pulse, 0.2275f, 0.1294f, 0.7804f);
            Add(d, "red_energizer", FxMode.Pulse, 1.0000f, 0.0000f, 0.0000f);
            Add(d, "yellow _energizer", FxMode.Pulse, 0.9961f, 0.8980f, 0.0118f);
            Add(d, "white_Energizer", FxMode.Pulse, 1.0000f, 1.0000f, 1.0000f);
            Add(d, "orange_energizer", FxMode.Pulse, 0.9412f, 0.4745f, 0.0902f);
            Add(d, "yellow_pixent", FxMode.Sparks, 0.5294f, 0.4157f, 0.1020f);
            Add(d, "green_pixent", FxMode.Sparks, 0.2784f, 0.9373f, 0.0196f);
            Add(d, "blue_pixent", FxMode.Sparks, 0.0000f, 0.7333f, 1.0000f);
            Add(d, "ember_pixent", FxMode.Sparks, 1.0000f, 0.4196f, 0.0627f);
            Add(d, "chaos_ember_glow", FxMode.Ember, 1, 1, 1);
            Add(d, "chaos_frost_rime", FxMode.Frost, 1, 1, 1);
            Add(d, "chaos_void_flicker", FxMode.Void, 1, 1, 1);
            Add(d, "chaos_holy_radiance", FxMode.Holy, 1, 1, 1);
            Add(d, "chaos_blood_pulse", FxMode.Blood, 1, 1, 1);
            Add(d, "chaos_spectral_ghost", FxMode.Ghost, 1, 1, 1);
            Add(d, "chaos_ash_drift", FxMode.Ash, 1, 1, 1);
            Add(d, "chaos_cinder_crown", FxMode.Crown, 1, 1, 1);
            return d;
        }

        /// <summary>The shader of a name, null for none or an unknown name (the creature then draws plain).</summary>
        public static OutfitFx For(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;
            return table.TryGetValue(name, out var f) ? f : null;
        }

        public static IEnumerable<string> Names => table.Keys;
        public static int Count => table.Count;
    }

    /// <summary>The hit flash as a mode (game_visualfx chaos_outfit_hit_white / hit_red): the strength is HitFlasher.Strength of the moment.</summary>
    public static class HitFlashFx
    {
        public static int ModeOf(bool red) => red ? FxMode.HitRed : FxMode.HitWhite;
        /// <summary>How far the outfit is turned to the flash colour: 0.78 white, 0.62 red at full strength (the shader's mix).</summary>
        public static float Mix(bool red, float strength) => Math.Max(0f, Math.Min(1f, strength)) * (red ? 0.62f : 0.78f);
    }

    /// <summary>The water and lava grounds that shimmer (visualfx_logic.lua L.LIQUID, the client ids of the pair).</summary>
    public static class LiquidGrounds
    {
        static readonly int[][] Water = { new[] { 629, 634 }, new[] { 4597, 4602 }, new[] { 4609, 4614 }, new[] { 33456, 33463 }, new[] { 35101, 35101 } };
        static readonly int[][] Lava = { new[] { 728, 730 }, new[] { 35059, 35059 }, new[] { 35070, 35073 } };

        static bool In(int[][] ranges, int id)
        {
            foreach (var r in ranges) if (id >= r[0] && id <= r[1]) return true;
            return false;
        }

        /// <summary>FxMode.Water, FxMode.Lava or FxMode.None for a ground item's client id.</summary>
        public static int ModeOf(int clientId) => In(Water, clientId) ? FxMode.Water : In(Lava, clientId) ? FxMode.Lava : FxMode.None;
    }

    /// <summary>The colour grade of the map (chaos_map_grade.frag) and the area mood added to it (grademood_logic.lua), and the soft glow (chaos_bloom_*.frag).</summary>
    public static class MapGradeFx
    {
        public const string GradePref = "chaos.fx.grade", BloomPref = "chaos.fx.bloom", LiquidPref = "chaos.fx.liquid";
        // the engine clamps what the mood adds
        public const float MaxTint = 0.15f, MaxSat = 0.35f, MaxCon = 0.35f;
        // the plain grade: the colour kept goes down by this, contrast up by this, the vignette darkens the corners by this
        public const float BaseDesat = 0.12f, BaseContrast = 1.06f, VignetteDark = 0.44f;
        public const float VignetteFrom = 0.50f, VignetteTo = 1.28f, VignetteX = 0.88f, VignetteY = 0.95f;
        // soft glow: a pixel glows from this luma, fully from the next; the halo's weight; the blur's taps (offset in small pixels, weight)
        public const float BloomThreshold = 0.80f, BloomFull = 0.96f, BloomStrength = 0.35f, BloomMaxStrength = 0.5f;
        public static readonly float[][] BlurTaps = { new[] { 0f, 0.2270270270f }, new[] { 1.3846153846f, 0.3162162162f }, new[] { 3.2307692308f, 0.0702702703f } };

        /// <summary>The five values of the mood (r, g, b, sat, con) cut to the engine's limits.</summary>
        public static float[] Clamp(double[] mood)
        {
            var v = new float[5];
            for (int i = 0; i < 5; i++)
            {
                double x = mood != null && i < mood.Length && !double.IsNaN(mood[i]) ? mood[i] : 0;
                double lim = i < 3 ? MaxTint : i == 3 ? MaxSat : MaxCon;
                v[i] = (float)Math.Max(-lim, Math.Min(lim, x));
            }
            return v;
        }

        /// <summary>Strength of the halo when the option is on, 0 when off, inside 0..BloomMaxStrength.</summary>
        public static float Bloom(bool on, float asked = BloomStrength) => !on ? 0f : Math.Max(0f, Math.Min(BloomMaxStrength, asked));

        /// <summary>The CPU twin of the grade shader on one colour (0..1 each): for the tests and for a check of the numbers.</summary>
        public static void Grade(float r, float g, float b, float[] mood, bool on, out float outR, out float outG, out float outB)
        {
            if (!on) { outR = r; outG = g; outB = b; return; }
            float[] m = Clamp(null);
            if (mood != null) m = Clamp(new[] { (double)mood[0], mood[1], mood[2], mood[3], mood[4] });
            float l = r * 0.299f + g * 0.587f + b * 0.114f;
            float keep = Math.Max(0f, Math.Min(1f, BaseDesat - m[3]));
            r += (l - r) * keep; g += (l - g) * keep; b += (l - b) * keep;
            l = r * 0.299f + g * 0.587f + b * 0.114f;
            r += -0.010f * (1 - l) + 0.024f * l + m[0]; g += 0.004f * (1 - l) + 0.010f * l + m[1]; b += 0.020f * (1 - l) - 0.014f * l + m[2];
            float c = BaseContrast + m[4];
            outR = Sat((r - 0.5f) * c + 0.5f); outG = Sat((g - 0.5f) * c + 0.5f); outB = Sat((b - 0.5f) * c + 0.5f);
        }

        static float Sat(float v) => Math.Max(0f, Math.Min(1f, v));

        /// <summary>The vignette factor (1 = no darkening) at a place of the picture, nx and ny in -1..1.</summary>
        public static float Vignette(float nx, float ny)
        {
            float x = nx * VignetteX, y = ny * VignetteY;
            float r = (float)Math.Sqrt(x * x + y * y);
            float t = Math.Max(0f, Math.Min(1f, (r - VignetteFrom) / (VignetteTo - VignetteFrom)));
            return 1f - VignetteDark * (t * t * (3 - 2 * t));
        }
    }

    /// <summary>The silhouette outlines of creatures: the attacked, the followed (game_visualfx OUTLINE) and a bought one (game_cosmeticfx OUTLINES).</summary>
    public sealed class OutlineSpec
    {
        public float R, G, B, A, TopR, TopG, TopB;
        public bool Gradient;
        public float WidthPx;       // sprite pixels
        public double PulseMs;      // 0 steady
        public string Kind = "";
    }

    public static class OutlineFx
    {
        public const float CosmeticWidth = 2f, CosmeticAlpha = 235f / 255f;
        public const double CosmeticPulseMs = 1800, CosmeticPulseLow = 0.45;
        /// <summary>The eight steps of a ring of one pixel (the silhouette is drawn at each, behind the sprite).</summary>
        public static readonly int[][] Ring = { new[] { -1, 0 }, new[] { 1, 0 }, new[] { 0, -1 }, new[] { 0, 1 }, new[] { -1, -1 }, new[] { 1, -1 }, new[] { -1, 1 }, new[] { 1, 1 } };

        static OutlineSpec Mk(string kind, int r, int g, int b, int a, float w, double pulse) =>
            new OutlineSpec { Kind = kind, R = r / 255f, G = g / 255f, B = b / 255f, A = a / 255f, WidthPx = w, PulseMs = pulse };

        public static OutlineSpec Target() => Mk("target", 235, 45, 40, 235, 2, 1600);
        public static OutlineSpec Follow() => Mk("follow", 70, 220, 95, 225, 2, 0);

        static readonly Dictionary<string, int[]> cosmetic = new Dictionary<string, int[]>
        {
            { "gold", new[] { 255, 208, 64 } }, { "crimson", new[] { 232, 52, 48 } }, { "void", new[] { 160, 84, 236 } }, { "frost", new[] { 128, 204, 255 } },
            { "verdant", new[] { 110, 228, 112 } }, { "ember", new[] { 228, 48, 12, 255, 214, 70 } }, { "storm", new[] { 40, 96, 232, 236, 250, 255 } },
            { "radiant", new[] { 255, 238, 150 } }, { "abyssal", new[] { 128, 70, 216 } }, { "absolute", new[] { 255, 210, 90, 255, 255, 248 } },
            { "chronicle", new[] { 92, 204, 194 } }, { "corona", new[] { 70, 20, 120, 176, 96, 255 } }, { "cinder", new[] { 230, 60, 0, 255, 190, 60 } },
        };

        /// <summary>The outline of a bought look (art key of the look's glow), null for an art without one.</summary>
        public static OutlineSpec Cosmetic(string art, bool pulse)
        {
            if (art == null || !cosmetic.TryGetValue(art, out var c)) return null;
            var o = Mk("cosmetic", c[0], c[1], c[2], 235, CosmeticWidth, pulse ? CosmeticPulseMs : 0);
            if (c.Length >= 6) { o.Gradient = true; o.TopR = c[3] / 255f; o.TopG = c[4] / 255f; o.TopB = c[5] / 255f; }
            return o;
        }

        public static IEnumerable<string> CosmeticArts => cosmetic.Keys;

        /// <summary>Opacity 0.45..1 of a pulsing outline at a time (ms); 1 for a steady one (pulseMs 0).</summary>
        public static float PulseAlpha(double now, double pulseMs)
        {
            if (pulseMs <= 0) return 1f;
            double ph = (now % pulseMs) / pulseMs;
            double wave = 0.5 - 0.5 * Math.Cos(ph * 2 * Math.PI);
            return (float)(CosmeticPulseLow + (1 - CosmeticPulseLow) * wave);
        }

        /// <summary>The outline a creature wears: the attacked one (red), else the followed (green), else a bought one when allowed; none for the player's own target outline rules
        /// (the local player never gets the target kinds). cosmeticAllowed: the options of the cosmetics (own and others).</summary>
        public static OutlineSpec Of(uint id, uint self, uint attack, uint follow, bool targetOption, OutlineSpec bought)
        {
            if (id == 0 || id == self) return bought;
            if (targetOption && id == attack) return Target();
            if (targetOption && id == follow) return Follow();
            return bought;
        }

        /// <summary>The colour of an outline at a place of the silhouette: t 0 at the feet, 1 at the top.</summary>
        public static void ColorAt(OutlineSpec o, float t, out float r, out float g, out float b)
        {
            if (!o.Gradient) { r = o.R; g = o.G; b = o.B; return; }
            t = Math.Max(0f, Math.Min(1f, t));
            r = o.R + (o.TopR - o.R) * t; g = o.G + (o.TopG - o.G) * t; b = o.B + (o.TopB - o.B) * t;
        }
    }

    /// <summary>The effects of the client pair that the main client adds to a tile: the level-up effect and the loot beams (pair 36). Unity draws them from the dat,
    /// frame by frame (PackFx.Phase); a pair without them keeps the drawn stand-ins.</summary>
    public static class PackFx
    {
        public const int LevelUpId = 4047, LevelUpDx = 1, LevelUpDy = 1;
        public const double DefaultFrameMs = 70, BeamLoopMs = 1750;
        static readonly Dictionary<string, int> beams = new Dictionary<string, int>
        {
            { "white", 4101 }, { "blue", 4098 }, { "orange", 4095 }, { "divine", 4097 }, { "unique", 4092 }, { "orb", 4090 },
        };

        /// <summary>The beam effect id of a beam group, 0 for an unknown group.</summary>
        public static int BeamId(string group) => group != null && beams.TryGetValue(group, out int id) ? id : 0;
        public static IEnumerable<string> BeamGroups => beams.Keys;

        /// <summary>Total length (ms) of one play of an effect: the sum of the frame durations (70 ms where the dat has none).</summary>
        public static double Length(FrameGroup g)
        {
            if (g == null || g.Phases <= 0) return 0;
            double t = 0;
            for (int i = 0; i < g.Phases; i++) t += FrameMs(g, i);
            return t;
        }

        static double FrameMs(FrameGroup g, int i)
        {
            if (g.MinDuration != null && i < g.MinDuration.Length && g.MinDuration[i] > 0)
            {
                int lo = g.MinDuration[i], hi = g.MaxDuration != null && i < g.MaxDuration.Length && g.MaxDuration[i] >= lo ? g.MaxDuration[i] : lo;
                return (lo + hi) / 2.0;
            }
            return DefaultFrameMs;
        }

        /// <summary>The frame of an effect `elapsed` ms after it started; -1 when it is over.</summary>
        public static int Phase(FrameGroup g, double elapsed)
        {
            if (g == null || g.Phases <= 0 || elapsed < 0) return -1;
            double t = elapsed;
            for (int i = 0; i < g.Phases; i++)
            {
                double d = FrameMs(g, i);
                if (t < d) return i;
                t -= d;
            }
            return -1;
        }

        /// <summary>A looping effect (a loot beam is added again at the end of each play): the frame at a clock time (ms). `loop` is the period (BeamLoopMs).</summary>
        public static int LoopPhase(FrameGroup g, double now, double loop = BeamLoopMs)
        {
            if (g == null || g.Phases <= 0 || loop <= 0) return -1;
            double t = now % loop;
            if (t < 0) t += loop;
            return Phase(g, t);
        }

        /// <summary>The tile a cell of an effect covers: the art's bottom-right cell is the effect's tile, a cell (w, h) lies w tiles west and h north of it.</summary>
        public static void CellTile(int x, int y, int w, int h, out int cx, out int cy) { cx = x - w; cy = y - h; }
    }

    /// <summary>The pulse on a hotkey slot when a long cooldown ends (game_visualfx cooldownpulse_logic.lua).</summary>
    public sealed class CooldownPulseFx
    {
        public const double Duration = 280, Rise = 40, MinCooldown = 3000, Tolerance = 150;
        public const float Peak = 0.55f;
        public const int MaxAlive = 24;
        readonly Dictionary<string, double> starts = new Dictionary<string, double>();

        public static bool ShouldPulse(double duration, double elapsed) => duration >= MinCooldown && duration - elapsed <= Tolerance;

        public static float Opacity(double t)
        {
            if (t < 0 || t >= Duration) return 0f;
            if (t < Rise) return (float)(Peak * t / Rise);
            double k = 1 - (t - Rise) / (Duration - Rise);
            return (float)(Peak * k * k);
        }

        public bool Start(string key, double now)
        {
            if (!starts.ContainsKey(key) && starts.Count >= MaxAlive) return false;
            starts[key] = now;
            return true;
        }

        public float Now(string key, double now)
        {
            if (!starts.TryGetValue(key, out double t0)) return 0f;
            if (now - t0 >= Duration) { starts.Remove(key); return 0f; }
            return Opacity(now - t0);
        }

        public int Alive => starts.Count;
        public void Clear() { starts.Clear(); }
    }
}
