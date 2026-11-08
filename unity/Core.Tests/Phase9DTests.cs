// Phase 9, track D: the rules of the visual outline and shader rows (Core/Phase9D.cs) against the main client's Lua numbers, and a read of the shader and view sources
// for what a text read can check (the shaders compile only in the CI Unity build): the new modes, the one fx entry per vertex of every quad path, the fallbacks.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase9DTests
    {
        static string FindRoot()
        {
            foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
                for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                    if (Directory.Exists(Path.Combine(d.FullName, "server", "data", "monster")) && File.Exists(Path.Combine(d.FullName, "ROADMAP.md"))) return d.FullName;
            return null;
        }

        static Item It(int rarity, bool unique)
        {
            var a = new Dictionary<ushort, ulong>();
            if (rarity > 0) a[ItemAttr.Rarity] = (ulong)rarity;
            if (unique) a[ItemAttr.Unique] = 1;
            return new Item { Id = 3264, Count = 1, Type = new ThingType(), Attrs = a };
        }

        static bool Near(float a, float b, float eps = 0.002f) => Math.Abs(a - b) <= eps;

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            ItemChecks(check);
            StepChecks(check);
            OutlineChecks(check);
            SpellLightChecks(check);
            SpellFxChecks(check);
            OptionChecks(check);
            SourceChecks(check);
            LocChecks(check);
        }

        static void ItemChecks(Action<bool, string> check)
        {
            check(ItemGlowFx.For(It(0, false)) == null && ItemGlowFx.For(It(1, false)) == null && ItemGlowFx.For(null) == null, "item glow: none for no rarity, Common and no item");
            var un = ItemGlowFx.For(It(2, false));
            check(un != null && Near(un.R, 0x5c / 255f) && Near(un.G, 0xcf / 255f) && Near(un.B, 0x5c / 255f) && Near(un.A, 225f / 255f) && un.PulseMs == 0 && !un.Metal, "item glow: Uncommon is steady green at 225/255");
            check(ItemGlowFx.For(It(4, false)).PulseMs == 0, "item glow: Rare is steady");
            var leg = ItemGlowFx.For(It(5, false));
            check(leg.PulseMs == ItemGlowFx.PulseMs && ItemGlowFx.PulseMs == 2200 && !leg.Metal, "item glow: Legendary pulses every 2.2 s, no metal");
            check(ItemGlowFx.For(It(8, false)).PulseMs == 2200, "item glow: an old Legendary id pulses too");
            var divine = ItemGlowFx.For(It(10, false));
            check(divine.PulseMs == 2200 && divine.Metal && Near(divine.MetalStrength, 0.5f) && Near(divine.MetalR, 0x22 / 255f) && Near(divine.MetalG, 0xe5 / 255f) && Near(divine.MetalB, 1f), "item glow: Divine pulses and has the metal look (tint #22e5ff, strength 0.5)");
            check(ItemGlowFx.For(It(13, false)).Metal, "item glow: an old Divine id has the metal look");
            var uq = ItemGlowFx.For(It(1, true));
            check(uq != null && Near(uq.R, 0xe0 / 255f) && uq.PulseMs == 2200 && !uq.Metal, "item glow: a unique item has the unique colour first, pulses, no metal");
            check(!ItemGlowFx.For(It(10, true)).Metal, "item glow: a unique Divine item is a unique one (no metal)");
            check(ItemGlowFx.ParseHex("#ff8000", out float r, out float g, out float b) && Near(r, 1f) && Near(g, 128 / 255f) && b == 0f && !ItemGlowFx.ParseHex("ff8000", out _, out _, out _) && !ItemGlowFx.ParseHex("#zz0000", out _, out _, out _) && !ItemGlowFx.ParseHex(null, out _, out _, out _), "item glow: colour parsing");
        }

        static void StepChecks(Action<bool, string> check)
        {
            var st = ItemGlowFx.Steps(ItemGlowFx.Width);
            check(ItemGlowFx.Width == 3 && st.Length == 24, "glow steps: three rings of eight: " + st.Length);
            check(ItemGlowFx.Steps(0).Length == 8 && ItemGlowFx.Steps(9).Length == 32, "glow steps: the reach is held to 1 .. 4");
            check(ItemGlowFx.Fall(1, 3) > 0.9f && Near(ItemGlowFx.Fall(2, 3), 0.5f) && ItemGlowFx.Fall(3, 3) < 0.1f && ItemGlowFx.Fall(1, 0) == 0f, "glow falloff: strong at the edge, half in the middle, nearly out at the reach: " + ItemGlowFx.Fall(1, 3) + " " + ItemGlowFx.Fall(3, 3));
            check(st[0].Fall < st[8].Fall && st[8].Fall < st[16].Fall, "glow steps: the outer ring comes first, the nearest is drawn last");
            bool dist = true;
            for (int i = 0; i < st.Length; i++)
            {
                int ring = 3 - i / 8;
                dist &= Near((float)Math.Sqrt(st[i].Dx * st[i].Dx + st[i].Dy * st[i].Dy), ring, 0.01f);
            }
            check(dist, "glow steps: every copy lies on its ring of one pixel");
            check(Near(ItemGlowFx.PulseAlpha(0, 2200), 0.5f) && Near(ItemGlowFx.PulseAlpha(1100, 2200), 1f) && ItemGlowFx.PulseAlpha(500, 0) == 1f, "glow pulse: 0.5 at the start, full at the middle, steady for 0");
            float lo = 9, hi = 0;
            for (int t = 0; t < 4400; t += 25) { float a = ItemGlowFx.PulseAlpha(t, 2200); lo = Math.Min(lo, a); hi = Math.Max(hi, a); }
            check(lo >= 0.499f && hi <= 1.001f && hi - lo > 0.45f, "glow pulse: between 0.5 and 1: " + lo + " " + hi);
            check(Near(ItemGlowFx.PulseParam(2200), 0.55f) && ItemGlowFx.PulseParam(0) == 0f && ItemGlowFx.PulseParam(99999) == 1f && Near(ItemGlowFx.PulseParam(2200) * 4f, 2.2f), "glow pulse: the shader reads the period as seconds / 4");
        }

        static void OutlineChecks(Action<bool, string> check)
        {
            var bought = new OutlineSpec { Kind = "cosmetic" };
            check(OutlineRules.Of(7, 7, 7, 7, 7, true, true, bought) == bought, "outline rules: the player's own creature keeps the bought one only");
            check(OutlineRules.Of(0, 7, 0, 0, 0, true, true, null) == null, "outline rules: id 0 gets none");
            check(OutlineRules.Of(5, 1, 5, 5, 5, true, true, bought).Kind == "target", "outline rules: the attacked one is a target first");
            check(OutlineRules.Of(5, 1, 9, 5, 5, true, true, bought).Kind == "follow", "outline rules: then the followed one");
            check(OutlineRules.Of(5, 1, 9, 9, 5, true, true, bought).Kind == "hover", "outline rules: then the one under the mouse");
            check(OutlineRules.Of(5, 1, 9, 9, 5, true, false, bought) == bought && OutlineRules.Of(5, 1, 9, 9, 5, true, false, null) == null, "outline rules: the hover option off");
            check(OutlineRules.Of(5, 1, 5, 5, 5, false, false, bought) == bought, "outline rules: the target option off leaves the bought one");
            check(OutlineRules.Of(5, 1, 5, 9, 5, false, true, bought).Kind == "hover", "outline rules: hover works without the target option");
            var h = OutlineRules.Hover();
            check(h.R == 1f && h.G == 1f && h.B == 1f && Near(h.A, 110f / 255f) && h.WidthPx == 1f && h.PulseMs == 0, "outline rules: the hover outline is faint white, one pixel, steady (visualfx_logic.lua 255,255,255,110,1,0)");
            OutlineRules.Dim(OutlineFx.Target(), 0.5f, 0f, out float r, out float g, out float b);
            check(Near(r, 235f / 255f * 0.5f * (235f / 255f)) && g < r && b < r, "outline rules: the colour carries the pulse and the alpha");
            OutlineRules.Dim(OutlineFx.Cosmetic("ember", false), 1f, 1f, out float tr, out float tg, out float tb);
            check(tb > 0.1f && tg > tr * 0.6f, "outline rules: a gradient outline is lighter at the top");
        }

        static void SpellLightChecks(Action<bool, string> check)
        {
            check(SpellLightFx.ThemeOf(1) == "blood" && SpellLightFx.ThemeOf(5) == "fire" && SpellLightFx.ThemeOf(376) == "fire" && SpellLightFx.ThemeOf(836) == "frost" && SpellLightFx.ThemeOf(9999) == null && SpellLightFx.ThemeOf(0) == null, "spell light: effect ids to themes");
            check(SpellLightFx.IdCount > 200 && SpellLightFx.Themes.Count() == 13, "spell light: 13 themes, " + SpellLightFx.IdCount + " ids");
            check(SpellLightFx.ColorOf("fire", out float r, out float g, out float b) && Near(r, 1f) && Near(g, 0.4f) && b == 0f && SpellLightFx.ColorOf("holy", out r, out g, out b) && Near(r, 1f) && Near(b, 0.4f) && !SpellLightFx.ColorOf("nope", out _, out _, out _) && !SpellLightFx.ColorOf(null, out _, out _, out _), "spell light: theme colours of the engine palette");
            check(SpellLightFx.Fade(-1) == 0f && SpellLightFx.Fade(0) == 0f && Near(SpellLightFx.Fade(48), 1f) && SpellLightFx.Fade(320) == 0f && SpellLightFx.Fade(100) > SpellLightFx.Fade(200) && SpellLightFx.Fade(200) > SpellLightFx.Fade(300), "spell light: a rise to full at 48 ms, then a fall to nothing at 320 ms");
            check(Near(SpellLightFx.Fade(24), 0.5f), "spell light: the rise is linear");
            check(SpellLightFx.RadiusAt(2, 1f) == 2f && SpellLightFx.RadiusAt(2, 0.2f) == 1f && SpellLightFx.RadiusAt(9, 1f) == 3f, "spell light: the radius shrinks with the light, 1 .. 3");

            var s = new SpellLightState();
            var p = new Pos(100, 100, 7);
            check(s.Add(0, p, 5, false) == null && s.Add(0, p, 9999, true) == null, "spell light state: off and unknown effects add nothing");
            var l = s.Add(0, p, 5, true);
            check(l != null && l.Effect == 5 && Near(l.R, 1f) && s.Count == 1, "spell light state: a fire effect lights");
            check(s.Add(50, p, 5, true) == null && s.Add(95, p, 5, true) != null && s.Add(50, new Pos(101, 100, 7), 5, true) != null, "spell light state: the same effect on the same tile within 90 ms is one light");
            var t = new SpellLightState();
            int added = 0;
            for (int i = 0; i < 20; i++) if (t.Add(0, new Pos(i, 0, 7), 5, true) != null) added++;
            check(added == 12 && t.Count == 12, "spell light state: at most 12 alive: " + added);
            check(t.Add(400, new Pos(50, 0, 7), 5, true) != null && t.Count == 1, "spell light state: finished lights make room");
            var u = new SpellLightState();
            u.Add(0, p, 5, true);
            check(u.Now(100).Count == 1 && u.Now(100)[0].Value > 0.5f && u.Now(310).Count == 0 && u.Now(330).Count == 0 && u.Count == 0, "spell light state: dropped under 12% and after 320 ms");
        }

        static void SpellFxChecks(Action<bool, string> check)
        {
            var t = new SpellFxTrack();
            var p = new Pos(10, 10, 7);
            check(!t.Add(0, p, 0) && !t.Add(-3, p, 0), "spell fx: no effect 0");
            check(!t.Add(PackFx.LevelUpId, p, 0) && !t.Add(PackFx.BeamId("divine"), p, 0) && !t.Add(PackFx.BeamId("orb"), p, 0), "spell fx: the level-up effect and the beams have their own paths");
            check(SpellFxTrack.IsPackManaged(4097) && !SpellFxTrack.IsPackManaged(5), "spell fx: pack managed ids");
            check(t.Add(5, p, 0) && t.Marks.Count == 1, "spell fx: an effect is listed");
            t.NoArt(5);
            check(t.Marks.Count == 0 && !t.Add(5, p, 10), "spell fx: an effect the art file lacks is dropped and not listed again");
            for (int i = 0; i < 50; i++) t.Add(100 + i, p, i);
            check(t.Marks.Count == SpellFxTrack.Max, "spell fx: at most " + SpellFxTrack.Max + " alive: " + t.Marks.Count);
            t.Add(300, p, 100000);
            check(t.Marks.Count == 1, "spell fx: old marks are pruned on the next add");
        }

        static void OptionChecks(Action<bool, string> check)
        {
            check(FxMode.ItemGlow == 23 && FxMode.Metal == 24 && FxMode.IsKnown(FxMode.ItemGlow) && FxMode.IsKnown(FxMode.Metal) && !FxMode.IsOutfit(FxMode.Metal), "fx modes: the item glow and the metal look");
            var d = new VisualFxOptions();
            check(!d.HoverOutline && d.SpellLight && !d.Get("hoverOutline") && d.Get("spellLight"), "visual options: hover outline off and spell light on by default (the main client's)");
            var o = VisualFxOptions.From(Json.TryParse(new VisualFxOptions { HoverOutline = true, SpellLight = false }.ToJson()));
            check(o.HoverOutline && !o.SpellLight && VisualFxOptions.From(null).SpellLight, "visual options: the two options round trip");
            o.Set("hoverOutline", false); o.Set("spellLight", true);
            check(!o.HoverOutline && o.SpellLight, "visual options: set by name");
        }

        static int Count(string s, string needle) { int n = 0, i = 0; while ((i = s.IndexOf(needle, i, StringComparison.Ordinal)) >= 0) { n++; i += needle.Length; } return n; }

        static void SourceChecks(Action<bool, string> check)
        {
            string root = FindRoot();
            if (root == null) { check(true, "phase 9d sources: repo root not found, skipped"); return; }
            string chaos = Path.Combine(root, "unity", "Client", "Assets", "Chaos");
            string inc = File.ReadAllText(Path.Combine(chaos, "Resources", "Shaders", "ChaosFx.cginc"));
            check(Regex.IsMatch(inc, "^#define FX_ITEMGLOW 23", RegexOptions.Multiline) && Regex.IsMatch(inc, "^#define FX_METAL 24", RegexOptions.Multiline), "phase 9d sources: the include defines the two new modes with the FxMode numbers");
            check(Regex.IsMatch(inc, "m == FX_ITEMGLOW\\b") && Regex.IsMatch(inc, "m == FX_METAL\\b"), "phase 9d sources: the include draws both");
            string hd = File.ReadAllText(Path.Combine(chaos, "Unity", "Resources", "Hd2dSprite.shader"));
            check(Count(hd, "FX_ITEMGLOW") >= 2, "phase 9d sources: Hd2dSprite lights an item glow as flat colour");
            string fa = File.ReadAllText(Path.Combine(chaos, "Unity", "Resources", "FrontArtSprite.shader"));
            check(fa.Contains("_FxTop") && fa.Contains("o.Emission = c.rgb") && Count(fa, "{") == Count(fa, "}"), "phase 9d sources: FrontArtSprite has the outline gradient colour and draws a silhouette unlit");

            // every quad path adds one fx entry per vertex (UV2 and colour) in the scene views: the same line adds the vertex, its normal, its mode and its colour
            foreach (string f in new[] { "Hd2dView.cs", "FrontLiveView.cs" })
            {
                string src = File.ReadAllText(Path.Combine(chaos, "Unity", f));
                check(Count(src, "b.V.Add(") == Count(src, "b.UV2.Add(") && Count(src, "b.UV2.Add(") == Count(src, "b.Col.Add(") && Count(src, "b.UV2.Add(") >= 1, "phase 9d sources: " + f + " adds an fx entry for every vertex");
                check(src.Contains("ItemGlowFx.Steps") && src.Contains("FxMode.Metal") && src.Contains("ItemGlowReal"), "phase 9d sources: " + f + " draws the item outline and the metal look");
                check(src.Contains("UV2.Clear()") && src.Contains("Col.Clear()"), "phase 9d sources: " + f + " clears the fx lists with the batch");
            }
            string mv = File.ReadAllText(Path.Combine(chaos, "Unity", "MapView.cs"));
            check(mv.Contains("ItemGlowFx.Steps") && mv.Contains("FxMode.Metal") && mv.Contains("else if (outline != null"), "phase 9d sources: MapView draws the glow rings and keeps the tinted copies as the fallback");
            check(mv.Contains("if (FxOn) for (int k = 0; k < 4; k++) fxs.Add(Vector4.zero)") && mv.Contains("if (FxOn) { var fx = new Vector4(fxMode, fxStrength"), "phase 9d sources: MapView adds an fx entry on both quad paths while FxOn");
            string flc = File.ReadAllText(Path.Combine(chaos, "Unity", "FrontLiveCreatures.cs"));
            check(flc.Contains("FxShaderOk") && flc.Contains("OutlineRules.Dim") && flc.Contains("SetRing"), "phase 9d sources: the live creatures draw the outline ring behind the sprite");
            string app = File.ReadAllText(Path.Combine(chaos, "Unity", "ChaosApp.Phase8A.cs"));
            check(app.Contains("if (ItemGlowRealOn) return;"), "phase 9d sources: the ground ring stands down when the shader draws the outline");
            check(File.ReadAllText(Path.Combine(chaos, "Unity", "ChaosApp.Phase8C.cs")).Contains("OutlineRules.Of("), "phase 9d sources: the creature outline asks the rules with the hover kind");

            // a surface shader with `uv_X` in its Input gets `X_ST` from Unity: declaring it again does not compile and the sprites vanish in the player (the phase 8 build)
            foreach (string sh in Directory.GetFiles(chaos, "*.shader", SearchOption.AllDirectories))
            {
                string text = File.ReadAllText(sh);
                if (!text.Contains("#pragma surface")) continue;
                foreach (Match m in Regex.Matches(text, @"\buv_(\w+)"))
                    check(!Regex.IsMatch(text, @"^\s*(float|half|fixed)4\s[^;]*\b_" + m.Groups[1].Value + @"_ST\b", RegexOptions.Multiline), "shader sources: " + Path.GetFileName(sh) + " leaves " + m.Groups[1].Value + "_ST to the surface shader");
            }
        }

        static void LocChecks(Action<bool, string> check)
        {
            Loc.Set("pt-BR");
            foreach (var kv in LocPhase9D.PtBr) check(Loc.T(kv.Key) == kv.Value && kv.Value != kv.Key, "loc: " + kv.Key);
            Loc.Set("en");
            check(Loc.T("Light around spell effects") == "Light around spell effects", "loc: English is the key");
        }
    }
}
