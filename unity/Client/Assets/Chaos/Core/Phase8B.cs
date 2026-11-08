// Phase 8, track B: gaps of the P2 partial rows of docs/UNITY_PARITY.md (ground effects under the creatures, ...). Pure logic, no UnityEngine.
// Tests: Core.Tests/Phase8BTests.cs. pt-BR texts: LocPhase8B.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    // ---------------------------------------------------------------------------------------------------- game_charms: the slot art per shape
    /// <summary>The slot pictures of the charm tiles (charmsview.lua V.slotImage): 1x1, 2x1, 1x2 and 2x2 cells have their own file in client/overlay/data/images/chaos, drawn at the tile's
    /// exact size; any other shape stays on the plain frame.</summary>
    public static class CharmSlots
    {
        public static readonly string[] Shapes = { "1x1", "2x1", "1x2", "2x2" };
        public static string Key(int w, int h) => w + "x" + h;
        public static bool Has(int w, int h) => Array.IndexOf(Shapes, Key(w, h)) >= 0;
        /// <summary>The overlay path of the picture (read as ../data/... by OverlayFiles), null for a shape without one.</summary>
        public static string Path(int w, int h) => Has(w, h) ? ArtPaths.Data("images/chaos/charmslot_" + Key(w, h) + ".png") : null;
    }

    // ---------------------------------------------------------------------------------------------------- game_outfitextras: the card grid, the preview, the strip
    /// <summary>The rules of the Customise Character window beyond the rows (customisecore.lua cards, outfitextras.lua): the search over one category's cards (every word typed must be in the name),
    /// what a card or the chosen option shows on the large look preview, and the "Equipped now" strip.</summary>
    public static class ExtrasView
    {
        /// <summary>The option indices whose text holds every word of the search (empty search: all), in order.</summary>
        public static List<int> Filter(OutfitExtrasPanel.ExtraRow row, string search)
        {
            var o = new List<int>();
            if (row == null) return o;
            var words = new List<string>();
            foreach (var w in (search ?? "").ToLowerInvariant().Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries)) words.Add(w);
            for (int i = 0; i < row.Options.Count; i++)
            {
                string name = row.Options[i].Text.ToLowerInvariant();
                bool hit = true;
                foreach (var w in words) if (name.IndexOf(w, StringComparison.Ordinal) < 0) { hit = false; break; }
                if (hit) o.Add(i);
            }
            return o;
        }

        /// <summary>What an option draws on the look preview: an outline glow or footprints (its art), a plate frame (the name plate); null for the rest (a spell effect or a chat colour is not
        /// drawn on the figure).</summary>
        public static PreviewOption Preview(OutfitExtrasPanel.ExtraRow row, int index)
        {
            if (row == null || index < 0 || index >= row.Options.Count) return null;
            var opt = row.Options[index];
            if (row.Key == "outline" || row.Key == "footprint")
            {
                if (opt.Row == null || string.IsNullOrEmpty(opt.Row.Art) || opt.Value == "0") return null;
                return new PreviewOption { Kind = row.Key, Art = opt.Row.Art, Pulse = opt.Row.Pulse > 0 };
            }
            if (row.Key == "frame") return opt.Value.Length == 0 ? null : new PreviewOption { Kind = "nameplate", Frame = opt.Value };
            return null;
        }

        /// <summary>The look preview option of the window: the chosen option of every row, the hovered one (row key and index) in place of its row's.</summary>
        public static PreviewOption Bundle(IList<OutfitExtrasPanel.ExtraRow> rows, Func<string, int> chosen, string hoverKey, int hoverIndex)
        {
            var parts = new List<PreviewOption>();
            foreach (var row in rows)
            {
                var p = Preview(row, row.Key == hoverKey ? hoverIndex : chosen(row.Key));
                if (p != null) parts.Add(p);
            }
            return parts.Count == 0 ? null : new PreviewOption { Kind = "bundle", Parts = parts };
        }

        /// <summary>The Equipped now strip: the label and the chosen option's name of a row ("Default" for none).</summary>
        public static string Equipped(OutfitExtrasPanel.ExtraRow row, int chosenIndex)
            => row.Label + ": " + (chosenIndex >= 0 && chosenIndex < row.Options.Count ? row.Options[chosenIndex].Text : Loc.T("Default"));

        /// <summary>The outfit the large preview draws: the character's own, with the layers the checkboxes turned off removed.</summary>
        public static Outfit Layers(Outfit worn, bool mount, bool wings, bool aura, bool shader)
        {
            var o = LookPreview.Copy(worn ?? LookPreview.Neutral());
            if (!mount) o.Mount = 0;
            if (!wings) o.Wings = 0;
            if (!aura) o.Aura = 0;
            if (!shader) o.Shader = "";
            return o;
        }
    }

    // ---------------------------------------------------------------------------------------------------- game_mapoverlay: keys
    /// <summary>A key held down repeats like the engine's bindKeyPress: one step at the press, then after FirstMs one every EveryMs.</summary>
    public sealed class KeyRepeat
    {
        public const double FirstMs = 250, EveryMs = 50;
        bool held;
        double next;

        /// <summary>True when a step is due now. down: the key is held; call it every frame.</summary>
        public bool Step(bool down, double nowMs)
        {
            if (!down) { held = false; return false; }
            if (!held) { held = true; next = nowMs + FirstMs; return true; }
            if (nowMs < next) return false;
            next = nowMs + EveryMs;
            return true;
        }

        public void Reset() { held = false; }
    }

    /// <summary>The keys of the map overlay (mapoverlay.lua bindKeys): Tab toggles it (the hotkey "Minimap: Map Overlay" defaults to Tab; the chat's next channel moves to Ctrl+Tab),
    /// Shift + an arrow pans it by about 48 pixels (Ctrl+Shift+arrows too), so the arrows must not walk while it is open and Shift is held.</summary>
    public static class OverlayKeys
    {
        public const double PanPixels = 48;
        /// <summary>The direction of the arrow keys held: x -1 left, +1 right, y -1 up, +1 down; (0, 0) none.</summary>
        public static void Dir(bool up, bool down, bool left, bool right, out int dx, out int dy)
        {
            dx = (right ? 1 : 0) - (left ? 1 : 0);
            dy = (down ? 1 : 0) - (up ? 1 : 0);
        }

        /// <summary>Does Shift + the arrows pan, so that the walk leaves the arrows alone? Only while the overlay is shown and the keys are not typing into a text field.</summary>
        public static bool Pans(bool overlayShown, bool shift, bool typing) => overlayShown && shift && !typing;

        /// <summary>The chat's channel step: Tab with the line focused, or Ctrl+Tab at any time (plain Tab outside the line belongs to the overlay).</summary>
        public static bool ChatTab(bool chatFocused, bool ctrl, bool typing) => chatFocused || (ctrl && !typing);

        /// <summary>Tab toggles the overlay: not in the chat line, not with Ctrl, not while a text field is edited.</summary>
        public static bool ToggleTab(bool chatFocused, bool ctrl, bool typing) => !chatFocused && !ctrl && !typing;
    }

    // ---------------------------------------------------------------------------------------------------- game_cosmetics: the effect icons
    /// <summary>The picture of a Cosmetics row (cosmetics.lua drawIcon): the generated icon of its main effect (images/fx/{name}.png of game_cosmetics, client/tools/sprites/gen_cosmetic_fx_icons.py),
    /// else a footprint's print (game_cosmeticfx images/prints), else none (the caller draws the item or the colour).</summary>
    public static class CosmeticIcons
    {
        /// <summary>The row's main effect (lookpreview_core.lua P.mainEffect): the longest non-missile skin effect, else the first one. play: the steps { a, b }.</summary>
        public static object MainEffect(List<object> play)
        {
            object best = null;
            if (play == null) return null;
            foreach (var step in play)
            {
                var b = Json.Get(step, "b");
                if (!(b is Dictionary<string, object>) || Json.Bool(b, "m")) continue;
                if (best == null || Json.Number(b, "ms") > Json.Number(best, "ms")) best = b;
            }
            if (best != null) return best;
            if (play.Count > 0) { var first = Json.Get(play[0], "b"); return first is Dictionary<string, object> ? first : null; }
            return null;
        }

        static bool Word(string s)
        {
            if (string.IsNullOrEmpty(s)) return false;
            foreach (char c in s) if (!(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_')) return false;
            return true;
        }

        /// <summary>The icon file of an effect spec under the "modules" folder of OverlayFiles; null for a spec without a safe name.</summary>
        public static string FxPath(object spec)
        {
            string n = Json.Text(spec, "n");
            return Word(n) ? "game_cosmetics/images/fx/" + n + ".png" : null;
        }

        /// <summary>A footprint print picture (the art name with or without .png).</summary>
        public static string PrintPath(string art)
        {
            if (string.IsNullOrEmpty(art) || art.IndexOf('/') >= 0 || art.IndexOf("..", StringComparison.Ordinal) >= 0) return null;
            return "game_cosmeticfx/images/prints/" + (art.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? art : art + ".png");
        }

        /// <summary>The file a row's list icon and sample come from, null when it has none.</summary>
        public static string Path(CosRow r)
        {
            if (r == null) return null;
            if (r.Play != null) { string p = FxPath(MainEffect(r.Play)); if (p != null) return p; }
            if (r.Kind == "footprint" && r.Id != "0") return PrintPath(r.Art);
            return null;
        }
    }

    // ---------------------------------------------------------------------------------------------------- game_groundfx: drawn under the creatures
    /// <summary>The ring and the glow of a ground effect (game_groundfx) as flat quads of the map mesh and the live view: the size and the opacity over the life of the mark,
    /// and the two 32 x 32 pictures (white, alpha only; the tint is the vertex colour). The classic view puts the quad into the tile's draw order before its creatures.</summary>
    public static class GroundRing
    {
        public const int Cell = 32;
        /// <summary>Width of the ring in tiles at t (0 to 1 of the life): 0.8 growing to 2.7. The height is Flat of it (the floor seen at a slant).</summary>
        public static float Size(float t) => 0.8f + 1.9f * Clamp01(t);
        public const float Flat = 0.55f, GlowWidth = 0.8f, GlowFlat = 0.45f, GlowAlpha = 0.25f, RingAlpha = 0.75f, FootDrop = 0.1f;
        public static float Alpha(float t) => (1f - Clamp01(t)) * RingAlpha;
        public static float GlowOpacity(float t) => (1f - Clamp01(t)) * GlowAlpha;
        static float Clamp01(float t) => t < 0f ? 0f : t > 1f ? 1f : t;

        /// <summary>The picture of the ring or of the soft glow as RGBA bytes, white with the shape in alpha.</summary>
        public static byte[] Rgba(bool ring)
        {
            var b = new byte[Cell * Cell * 4];
            for (int y = 0; y < Cell; y++)
                for (int x = 0; x < Cell; x++)
                {
                    float u = (x + 0.5f) / Cell - 0.5f, v = (y + 0.5f) / Cell - 0.5f;
                    float d = (float)Math.Sqrt(u * u + v * v) * 2f;
                    float a = ring ? Math.Max(0f, 1f - Math.Abs(d - 0.85f) / 0.12f) : Math.Max(0f, 1f - d * d);
                    int i = (y * Cell + x) * 4;
                    b[i] = b[i + 1] = b[i + 2] = 255; b[i + 3] = (byte)Math.Round(Math.Min(1f, a) * 255f);
                }
            return b;
        }

        /// <summary>The quads of a mark at age t: ring then glow (draw order), each as { width, height, alpha, ring 1 or glow 0 } in tiles.</summary>
        public static void Quads(float t, List<float[]> into)
        {
            float s = Size(t);
            into.Add(new[] { s, s * Flat, Alpha(t), 1f });
            into.Add(new[] { s * GlowWidth, s * GlowFlat, GlowOpacity(t), 0f });
        }
    }
}
