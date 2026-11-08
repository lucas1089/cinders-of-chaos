// Phase 15, track B: the numbers of the additive drawing of game_visualfx in the classic view. The immediate-mode GUI cannot add colour onto the picture, so the
// glowing spell effects (base patch 0152, visualfx_logic.lua L.glows) and the spell light (base patch 0127) are drawn with Graphics.DrawTexture and an additive
// material (Resources/Shaders/ChaosAdd.shader). Rules here, glue in Unity/ChaosApp.Phase15B.cs.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    /// <summary>Which effects glow, and how strongly the added light and glow are drawn.</summary>
    public static class AddFx
    {
        /// <summary>Themes of visualfx_logic.lua L.GLOW_THEMES: bright and energetic. The rest (blood, water, frost, ...) keep the normal blend.</summary>
        public static bool GlowTheme(string theme) => theme == "fire" || theme == "energy" || theme == "holy" || theme == "arcane";

        /// <summary>The stock explosion area and hit carry dark smoke: they keep the normal blend (L.GLOW_SKIP).</summary>
        public static bool Skipped(int id) => id == 5 || id == 6;

        /// <summary>Does this effect id glow (L.glows).</summary>
        public static bool Glows(int id) => id > 0 && id < 65536 && !Skipped(id) && GlowTheme(SpellLightFx.ThemeOf(id));

        /// <summary>The glowing ids, ascending (L.glowIds).</summary>
        public static int[] GlowIds()
        {
            var l = new List<int>();
            for (int id = 1; id < 65536; id++) if (Glows(id)) l.Add(id);
            return l.ToArray();
        }

        /// <summary>Added light at full strength: a spell light adds this share of its colour to the map under the soft disc. The engine adds the full colour to the light
        /// view, which then lights the tiles; a disc added straight onto the picture would burn out at full, so it is held lower.</summary>
        public const float LightGain = 0.7f;

        /// <summary>Alpha of the added disc of a spell light at strength f (0..1), the colour being the theme colour. 0 outside the light's life.</summary>
        public static float LightAlpha(float f) => f <= 0f ? 0f : Math.Min(1f, LightGain * Math.Min(1f, f));

        /// <summary>The disc of a light: width in tiles at strength f (the radius of SpellLightFx times two, as the soft fallback disc).</summary>
        public static float LightTiles(float f) => 2f * SpellLightFx.RadiusAt(SpellLightFx.Radius, f);

        /// <summary>Glow alpha of an effect sprite: the effect opacity option, as the others.</summary>
        public static float GlowAlpha(float effectAlpha) => Math.Max(0f, Math.Min(1f, effectAlpha));

        /// <summary>Cuts a quad (screen rect, texture rect in 0..1 with v up) to a clip rect; the texture rect shrinks in step. False when nothing is left.</summary>
        public static bool Clip(float x, float y, float w, float h, float u, float v, float uw, float vh,
            float cx, float cy, float cw, float ch, out float ox, out float oy, out float ow, out float oh, out float ou, out float ov, out float ouw, out float ovh)
        {
            ox = oy = ow = oh = ou = ov = ouw = ovh = 0f;
            if (w <= 0f || h <= 0f) return false;
            float x0 = Math.Max(x, cx), x1 = Math.Min(x + w, cx + cw), y0 = Math.Max(y, cy), y1 = Math.Min(y + h, cy + ch);
            if (x1 <= x0 || y1 <= y0) return false;
            ox = x0; oy = y0; ow = x1 - x0; oh = y1 - y0;
            ou = u + uw * ((x0 - x) / w);
            ouw = uw * (ow / w);
            // screen y runs down, texture v runs up: the top of the screen rect is the top of the texture rect
            ov = v + vh * ((y + h - y1) / h);
            ovh = vh * (oh / h);
            return true;
        }
    }
}
