// Phase 9, track D: the rules behind the visual outline and shader rows (game_itemrarity, game_visualfx, game_cosmeticfx). Pure C#, no Unity types: the shaders
// (Assets/Chaos/Resources/Shaders/ChaosFx.cginc) and the views only draw what these classes say. Sources: client/overlay/modules/game_itemrarity/itemrarity.lua (the
// outline plan), client/base-patches/0044-item-rarity-outline-ui-shaders.patch (reach, falloff, pulse), game_visualfx/visualfx_logic.lua (hover outline, spell light).
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>What one item asks of the sprite outline shader: the glow colour, its pulse, and the Divine metal look.</summary>
    public sealed class ItemGlowSpec
    {
        public float R, G, B, A;
        public double PulseMs;                  // 0 steady
        public bool Metal;                      // Divine: the metal shader on the sprite itself
        public float MetalR, MetalG, MetalB, MetalStrength;
    }

    /// <summary>One copy of the sprite in the ring of the outline: the offset in sprite pixels and how much of the glow it keeps (1 at the edge, 0 at the reach).</summary>
    public struct GlowStep
    {
        public float Dx, Dy, Fall;
        public GlowStep(float dx, float dy, float fall) { Dx = dx; Dy = dy; Fall = fall; }
    }

    /// <summary>The soft rarity outline of items on the map and its Divine metal look, for the views that draw the sprite itself (classic mesh, HD-2D, live).
    /// The main client's engine draws the sprite once more, grown by the reach, with a smooth falloff (patch 0044); a mesh view cannot grow a quad inside the atlas, so
    /// it draws the silhouette at rings of one pixel up to the reach, outer ring first, each ring dimmer: the same look in steps.</summary>
    public static class ItemGlowFx
    {
        /// <summary>The reach in sprite pixels (itemrarity.lua OUTLINE.width), the glow opacity (225 of 255), the lowest opacity of a pulse, the pulse period.</summary>
        public const int Width = 3;
        public const float Alpha = 225f / 255f, PulseLow = 0.5f;
        public const double PulseMs = 2200;
        /// <summary>Legendary and up breathe (itemrarity.lua OUTLINE.pulseFrom), a unique item too.</summary>
        public const int PulseFromRarity = 5;
        /// <summary>The metal look of Divine (itemrarity.lua DIVINE.metal: tint #22e5ff, strength 0.5).</summary>
        public const float MetalStrength = 0.5f, MetalR = 0x22 / 255f, MetalG = 0xe5 / 255f, MetalB = 1f;
        /// <summary>The shader reads the pulse period from the strength channel: seconds divided by this.</summary>
        public const float PulseUnitMs = 4000f;

        /// <summary>(r, g, b) 0..1 of "#rrggbb"; false for anything else.</summary>
        public static bool ParseHex(string hex, out float r, out float g, out float b)
        {
            r = g = b = 1f;
            if (hex == null || hex.Length != 7 || hex[0] != '#') return false;
            try
            {
                r = Convert.ToInt32(hex.Substring(1, 2), 16) / 255f;
                g = Convert.ToInt32(hex.Substring(3, 2), 16) / 255f;
                b = Convert.ToInt32(hex.Substring(5, 2), 16) / 255f;
                return true;
            }
            catch (FormatException) { return false; }
        }

        /// <summary>What an item asks for, null for none (Common and unrated items get no glow, as the main client's minRarity). The colour is the unique colour first.</summary>
        public static ItemGlowSpec For(Item it)
        {
            string hex = MapItemOutline.Color(it);
            if (hex == null || !ParseHex(hex, out float r, out float g, out float b)) return null;
            bool unique = ItemRarity.IsUnique(it);
            int rarity = ItemRarity.Of(it);
            var s = new ItemGlowSpec { R = r, G = g, B = b, A = Alpha, PulseMs = unique || rarity >= PulseFromRarity ? PulseMs : 0 };
            if (RarityGlow.IsDivine(it)) { s.Metal = true; s.MetalR = MetalR; s.MetalG = MetalG; s.MetalB = MetalB; s.MetalStrength = MetalStrength; }
            return s;
        }

        /// <summary>The share of the glow a pulse leaves at a time (ms): PulseLow .. 1 on a cosine, 1 for a steady one.</summary>
        public static float PulseAlpha(double now, double pulseMs)
        {
            if (pulseMs <= 0) return 1f;
            double ph = (now % pulseMs) / pulseMs;
            if (ph < 0) ph += 1;
            double wave = 0.5 - 0.5 * Math.Cos(ph * 2 * Math.PI);
            return (float)(PulseLow + (1 - PulseLow) * wave);
        }

        /// <summary>The value the shader's strength channel carries for a pulse period: 0 steady.</summary>
        public static float PulseParam(double pulseMs) => pulseMs <= 0 ? 0f : (float)Math.Min(1.0, Math.Max(0.05, pulseMs / PulseUnitMs));

        /// <summary>The falloff of a ring i (1..reach) of a glow of the given reach: the smooth step of the engine shader at the middle of the ring.</summary>
        public static float Fall(int ring, int reach)
        {
            if (reach <= 0) return 0f;
            float t = Math.Max(0f, Math.Min(1f, (ring - 0.5f) / reach));
            return 1f - t * t * (3f - 2f * t);
        }

        /// <summary>The copies of the sprite round it, outer ring first (the nearer rings are drawn over the farther): eight directions on each ring of one pixel up to the reach.</summary>
        public static GlowStep[] Steps(int reach)
        {
            reach = Math.Max(1, Math.Min(4, reach));
            var l = new List<GlowStep>();
            const float d = 0.70710678f;
            for (int ring = reach; ring >= 1; ring--)
            {
                float fall = Fall(ring, reach);
                l.Add(new GlowStep(-ring, 0, fall)); l.Add(new GlowStep(ring, 0, fall)); l.Add(new GlowStep(0, -ring, fall)); l.Add(new GlowStep(0, ring, fall));
                l.Add(new GlowStep(-ring * d, -ring * d, fall)); l.Add(new GlowStep(ring * d, -ring * d, fall)); l.Add(new GlowStep(-ring * d, ring * d, fall)); l.Add(new GlowStep(ring * d, ring * d, fall));
            }
            return l.ToArray();
        }
    }

    /// <summary>The creature outlines with the hover kind (visualfx_logic.lua L.OUTLINE.hover, L.outlineWanted): the attacked one first, the followed one, then the one under the mouse.</summary>
    public static class OutlineRules
    {
        /// <summary>A faint white, one pixel, steady (visualfx_logic.lua: 255, 255, 255, 110, 1, 0).</summary>
        public static OutlineSpec Hover() => new OutlineSpec { Kind = "hover", R = 1f, G = 1f, B = 1f, A = 110f / 255f, WidthPx = 1f, PulseMs = 0 };

        /// <summary>The outline a creature wears. The local player never gets target, follow or hover; a bought one stays for every creature. Strongest first: target, follow, hover,
        /// then the bought one. targetOption covers target and follow, hoverOption the mouse.</summary>
        public static OutlineSpec Of(uint id, uint self, uint attack, uint follow, uint hover, bool targetOption, bool hoverOption, OutlineSpec bought)
        {
            if (id == 0 || id == self) return bought;
            if (targetOption && id == attack) return OutlineFx.Target();
            if (targetOption && id == follow) return OutlineFx.Follow();
            if (hoverOption && id == hover) return Hover();
            return bought;
        }

        /// <summary>The colour of a creature outline in a view with no alpha blending (the cut-out scenes): the colour dimmed by the pulse, the alpha folded in.</summary>
        public static void Dim(OutlineSpec o, float pulse, float t, out float r, out float g, out float b)
        {
            OutlineFx.ColorAt(o, t, out r, out g, out b);
            float k = Math.Max(0f, Math.Min(1f, pulse * o.A));
            r *= k; g *= k; b *= k;
        }
    }

    // ------------------------------------------------------------------------------------------------------------------------------------ spell light
    /// <summary>The light round a spell effect (game_visualfx spell light, O205): an effect of a theme lights the tiles about it for 320 ms in the theme's colour. The numbers
    /// and the id lists are visualfx_logic.lua's (L.LIGHT, L.THEME_COLOR, L.THEME_IDS).</summary>
    public static class SpellLightFx
    {
        public const int Max = 12;
        public const double Ms = 320, MinGap = 90;
        public const float Attack = 0.15f, MinFade = 0.12f;
        public const int Radius = 2, MinRadius = 1, MaxRadius = 3;

        static readonly Dictionary<string, int[]> colors = new Dictionary<string, int[]>
        {
            // r, g, b of the engine palette (each 0..5): fire 5,2,0 ...
            { "fire", new[] { 5, 2, 0 } }, { "blood", new[] { 5, 0, 0 } }, { "energy", new[] { 3, 4, 5 } }, { "frost", new[] { 1, 3, 5 } }, { "water", new[] { 0, 3, 5 } },
            { "holy", new[] { 5, 5, 2 } }, { "poison", new[] { 1, 5, 1 } }, { "physical", new[] { 4, 4, 4 } }, { "arcane", new[] { 4, 1, 5 } }, { "healing", new[] { 2, 5, 2 } },
            { "death", new[] { 3, 0, 3 } }, { "shadow", new[] { 2, 0, 4 } }, { "earth", new[] { 3, 2, 0 } },
        };

        static readonly string[][] themeIds =
        {
            new[] { "blood", "1,14,167,223,388-392,597-598,716,719-726,730,760,831" },
            new[] { "water", "2,26,54,660,840" },
            new[] { "fire", "5-7,16,37,200,213,216,221,226,248,372-378,709,739,761,834,851-852" },
            new[] { "holy", "8,40,50,201,224-225,262,264,403-405,619-621,624,656,672,686,711-714,748,753,755,835" },
            new[] { "poison", "9,17,21,47,399-402,729,767,839,853-854" },
            new[] { "physical", "10,32,173" },
            new[] { "arcane", "11,13,48,187,244,288,291,309,312,406-408,607,768-769,771,775,777-778,830" },
            new[] { "energy", "12,38,41,49,204,217,219,246,384-387,671,685,710,759,833,837" },
            new[] { "healing", "15,185,411-412,605,665-667,741,776" },
            new[] { "death", "18,39,158,203,218,220,222" },
            new[] { "earth", "35,45-46,51,182-183,367,593,601,668-669,674,717-718,765-766" },
            new[] { "frost", "42-44,53,202,205,215,359,379-383,662,708,762,836" },
            new[] { "shadow", "393-398,614-615,617,657,659,727,731-738,742-743,757,770,772-774,779,832" },
        };

        static Dictionary<int, string> byEffect;

        static Dictionary<int, string> Table
        {
            get
            {
                if (byEffect != null) return byEffect;
                var d = new Dictionary<int, string>();
                foreach (var row in themeIds)
                    foreach (string run in row[1].Split(','))
                    {
                        int dash = run.IndexOf('-');
                        int a = int.Parse(dash < 0 ? run : run.Substring(0, dash)), b = dash < 0 ? a : int.Parse(run.Substring(dash + 1));
                        for (int i = a; i <= b; i++) d[i] = row[0];
                    }
                return byEffect = d;
            }
        }

        public static IEnumerable<string> Themes => colors.Keys;
        public static int IdCount => Table.Count;

        /// <summary>The theme of an effect id, null for an effect with no light.</summary>
        public static string ThemeOf(int effectId) => Table.TryGetValue(effectId, out var t) ? t : null;

        /// <summary>The colour (0..1 each) of a theme's light; false for an unknown theme.</summary>
        public static bool ColorOf(string theme, out float r, out float g, out float b)
        {
            r = g = b = 0f;
            if (theme == null || !colors.TryGetValue(theme, out var c)) return false;
            r = c[0] / 5f; g = c[1] / 5f; b = c[2] / 5f;
            return true;
        }

        /// <summary>Strength 0..1 at an age (ms): a short rise, then a smooth fall to nothing; 0 outside the life.</summary>
        public static float Fade(double age)
        {
            if (age < 0 || age >= Ms) return 0f;
            double t = age / Ms;
            if (t < Attack) return (float)(t / Attack);
            double u = (t - Attack) / (1 - Attack);
            return (float)((1 - u) * (1 - u));
        }

        /// <summary>The radius (tiles) at strength f: it shrinks with the light, never under MinRadius while the light shows.</summary>
        public static float RadiusAt(float radius, float f) => Math.Max(MinRadius, Math.Min(MaxRadius, (float)Math.Floor(radius * f + 0.5f)));
    }

    /// <summary>One spell light in flight.</summary>
    public sealed class SpellLight
    {
        public Pos Pos;
        public int Effect;
        public float R, G, B;
        public double Born;
    }

    /// <summary>The live spell lights (visualfx_logic.lua lightAdd / lightsNow): at most 12 alive, the same effect on the same tile within 90 ms is one light, a light under 12%
    /// of full is dropped.</summary>
    public sealed class SpellLightState
    {
        readonly List<SpellLight> list = new List<SpellLight>();
        readonly Dictionary<string, double> last = new Dictionary<string, double>();

        public int Count => list.Count;

        void Prune(double now) { list.RemoveAll(l => now - l.Born >= SpellLightFx.Ms); }

        /// <summary>An effect plays on a tile. Returns the new light, or null: the option is off, the effect has no light, the same effect on the same tile just now, the table is full.</summary>
        public SpellLight Add(double now, Pos pos, int effect, bool enabled)
        {
            if (!enabled) return null;
            if (!SpellLightFx.ColorOf(SpellLightFx.ThemeOf(effect), out float r, out float g, out float b)) return null;
            string key = pos.X + ":" + pos.Y + ":" + pos.Z + ":" + effect;
            if (last.TryGetValue(key, out double at) && now - at < SpellLightFx.MinGap) return null;
            Prune(now);
            if (list.Count >= SpellLightFx.Max) return null;
            last[key] = now;
            if (last.Count > 256)
            {
                var old = new List<string>();
                foreach (var kv in last) if (now - kv.Value > SpellLightFx.Ms) old.Add(kv.Key);
                foreach (var k in old) last.Remove(k);
            }
            var light = new SpellLight { Pos = pos, Effect = effect, R = r, G = g, B = b, Born = now };
            list.Add(light);
            return light;
        }

        /// <summary>The lights to draw now: each with its strength (Fade) 0.12 or more, the dropped ones gone.</summary>
        public List<KeyValuePair<SpellLight, float>> Now(double now)
        {
            Prune(now);
            var o = new List<KeyValuePair<SpellLight, float>>();
            foreach (var l in list)
            {
                float f = SpellLightFx.Fade(now - l.Born);
                if (f >= SpellLightFx.MinFade) o.Add(new KeyValuePair<SpellLight, float>(l, f));
            }
            return o;
        }

        public void Clear() { list.Clear(); last.Clear(); }
    }

    // ------------------------------------------------------------------------------------------------------------------------------------ spell effects from the art
    /// <summary>One magic effect that plays on a tile (a 0x83 message), for the classic view to draw from the dat.</summary>
    public sealed class SpellFxMark
    {
        public Pos Pos;
        public int Id;
        public double Born;
    }

    /// <summary>The magic effects the classic view draws from the art file frame by frame (the live view has its own look, FrontLiveFx). The level-up effect and the loot beams of the
    /// pair are drawn by their own paths (PackFx), so they are not listed here.</summary>
    public sealed class SpellFxTrack
    {
        public const int Max = 32;
        public const double LongestMs = 4000;
        readonly List<SpellFxMark> list = new List<SpellFxMark>();
        readonly HashSet<int> missing = new HashSet<int>();

        public IReadOnlyList<SpellFxMark> Marks => list;

        /// <summary>The effects other code draws: the level-up effect and the beam effects of the pair.</summary>
        public static bool IsPackManaged(int id)
        {
            if (id == PackFx.LevelUpId) return true;
            foreach (string g in PackFx.BeamGroups) if (PackFx.BeamId(g) == id) return true;
            return false;
        }

        public bool Add(int id, Pos pos, double now)
        {
            if (id <= 0 || IsPackManaged(id) || missing.Contains(id)) return false;
            list.RemoveAll(m => now - m.Born > LongestMs);
            if (list.Count >= Max) list.RemoveAt(0);
            list.Add(new SpellFxMark { Id = id, Pos = pos, Born = now });
            return true;
        }

        /// <summary>The art file has no such effect: it is never listed again and the marks of it go.</summary>
        public void NoArt(int id) { missing.Add(id); list.RemoveAll(m => m.Id == id); }

        public void Remove(SpellFxMark m) { list.Remove(m); }
        public void Clear() { list.Clear(); }
    }
}
