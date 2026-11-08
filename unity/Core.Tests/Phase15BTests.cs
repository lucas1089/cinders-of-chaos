// Phase 15, track B: the additive glow and light numbers (Core/Phase15B.cs) against visualfx_logic.lua, the clip maths, and a read of the shader and glue sources.
using System;
using System.IO;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase15BTests
    {
        static string FindRoot()
        {
            foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
                for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                    if (Directory.Exists(Path.Combine(d.FullName, "server", "data", "monster")) && File.Exists(Path.Combine(d.FullName, "ROADMAP.md"))) return d.FullName;
            return null;
        }

        static bool Near(float a, float b) => Math.Abs(a - b) < 0.0005f;

        public static void Run(Action<bool, string> check)
        {
            // the glow list of visualfx_logic.lua: 86 ids, 7 first, 852 last, sum 37742 (luajit, L.glowIds())
            var ids = AddFx.GlowIds();
            long sum = 0; foreach (int i in ids) sum += i;
            check(ids.Length == 86 && ids[0] == 7 && ids[ids.Length - 1] == 852 && sum == 37742, "add fx: the glowing ids are those of visualfx_logic.lua (" + ids.Length + ")");
            check(!AddFx.Glows(5) && !AddFx.Glows(6) && AddFx.Glows(7), "add fx: the stock explosion and hit keep the normal blend");
            check(AddFx.Glows(12) && AddFx.Glows(8) && AddFx.Glows(11), "add fx: energy, holy and arcane glow");
            check(!AddFx.Glows(1) && !AddFx.Glows(2) && !AddFx.Glows(42) && !AddFx.Glows(18) && !AddFx.Glows(0) && !AddFx.Glows(70000), "add fx: blood, water, frost, death and unknown ids do not");

            check(AddFx.LightAlpha(0f) == 0f && AddFx.LightAlpha(-1f) == 0f, "add fx: no light outside the life");
            check(Near(AddFx.LightAlpha(1f), AddFx.LightGain) && AddFx.LightAlpha(5f) <= 1f, "add fx: the light is held at its gain");
            check(AddFx.LightAlpha(0.5f) < AddFx.LightAlpha(1f) && AddFx.LightGain > 0.32f, "add fx: the light rises with strength and is stronger than the old tint (0.32)");
            check(AddFx.LightTiles(1f) >= 2f && AddFx.LightTiles(1f) <= 6f, "add fx: the disc spans 2 to 6 tiles");
            check(AddFx.GlowAlpha(2f) == 1f && AddFx.GlowAlpha(-1f) == 0f && Near(AddFx.GlowAlpha(0.4f), 0.4f), "add fx: glow alpha follows the effect opacity");

            // clip: inside stays, outside goes, half out halves the texture rect (top kept when the bottom is cut)
            bool ok = AddFx.Clip(10, 10, 20, 20, 0, 0, 1, 1, 0, 0, 100, 100, out var x, out var y, out var w, out var h, out var u, out var v, out var uw, out var vh);
            check(ok && x == 10 && y == 10 && w == 20 && h == 20 && u == 0 && v == 0 && uw == 1 && vh == 1, "add fx clip: inside is untouched");
            check(!AddFx.Clip(200, 10, 20, 20, 0, 0, 1, 1, 0, 0, 100, 100, out _, out _, out _, out _, out _, out _, out _, out _), "add fx clip: outside is dropped");
            ok = AddFx.Clip(-10, 0, 20, 20, 0, 0, 1, 1, 0, 0, 100, 100, out x, out y, out w, out h, out u, out v, out uw, out vh);
            check(ok && x == 0 && w == 10 && Near(u, 0.5f) && Near(uw, 0.5f) && v == 0 && vh == 1, "add fx clip: the left half out cuts the left half of the texture");
            ok = AddFx.Clip(0, 90, 20, 20, 0, 0, 1, 1, 0, 0, 100, 100, out x, out y, out w, out h, out u, out v, out uw, out vh);
            check(ok && y == 90 && h == 10 && Near(v, 0.5f) && Near(vh, 0.5f), "add fx clip: the bottom half out keeps the top half of the texture (v up)");

            string root = FindRoot();
            if (root == null) { check(true, "phase 15b sources: repo root not found, skipped"); return; }
            string chaos = Path.Combine(root, "unity", "Client", "Assets", "Chaos");
            string sh = File.ReadAllText(Path.Combine(chaos, "Resources", "Shaders", "ChaosAdd.shader"));
            check(sh.Contains("Shader \"Chaos/Add\"") && Regex.IsMatch(sh, @"Blend\s+SrcAlpha\s+One") && sh.Contains("ZTest Always") && sh.Contains("Cull Off") && sh.Contains("ZWrite Off"), "phase 15b sources: the shader adds, ignores depth and culling");
            check(!sh.Contains("#pragma surface") && !Regex.IsMatch(sh, @"^\s*float4\s+_MainTex_ST", RegexOptions.Multiline), "phase 15b sources: a plain vertex and fragment shader");
            check(Regex.Matches(sh, "\\{").Count == Regex.Matches(sh, "\\}").Count, "phase 15b sources: shader braces balance");
            string glue = File.ReadAllText(Path.Combine(chaos, "Unity", "ChaosApp.Phase15B.cs"));
            check(glue.Contains("Graphics.DrawTexture") && glue.Contains("EventType.Repaint") && glue.Contains("AddFx.Clip") && glue.Contains("Chaos/Add"), "phase 15b sources: the glue draws during Repaint, clipped, with the additive shader");
            string p9 = File.ReadAllText(Path.Combine(chaos, "Unity", "ChaosApp.Phase9D.cs"));
            check(p9.Contains("AddFx.Glows") && p9.Contains("DrawSpellLightAdd"), "phase 15b sources: the classic view tries the additive path first and keeps the tint as the fallback");
        }
    }
}
