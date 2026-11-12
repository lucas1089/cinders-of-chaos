// Phase 8, track C: the shader numbers of the visual effect rows (Core/Phase8CFx.cs) against the main client's Lua files, and a read of the shader sources (no Unity here:
// the shaders compile only in the CI Unity build, so this checks what a text read can: braces, includes, the mode numbers, the fallback lines).
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase8CTests
    {
        static string FindRoot()
        {
            foreach (var start in new[] { Directory.GetCurrentDirectory(), AppContext.BaseDirectory })
                for (var d = new DirectoryInfo(start); d != null; d = d.Parent)
                    if (Directory.Exists(Path.Combine(d.FullName, "server", "data", "monster")) && File.Exists(Path.Combine(d.FullName, "ROADMAP.md"))) return d.FullName;
            return null;
        }

        static string Read(string root, params string[] rel)
        {
            string p = Path.Combine(new[] { root }.Concat(rel).ToArray());
            return File.Exists(p) ? File.ReadAllText(p) : null;
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            OutfitChecks(check);
            GradeChecks(check);
            LiquidChecks(check);
            OutlineChecks(check);
            PackChecks(check);
            PulseChecks(check);
            BeamMessageChecks(check);
            ShaderSourceChecks(check);
            LocChecks(check);
        }

        static void OutfitChecks(Action<bool, string> check)
        {
            check(OutfitFxTable.Count == 26, "outfit fx: 26 shaders, " + OutfitFxTable.Count);
            check(OutfitFxTable.For(null) == null && OutfitFxTable.For("") == null && OutfitFxTable.For("no such shader") == null, "outfit fx: none and unknown names draw plain");
            bool modes = true, colours = true;
            foreach (string n in OutfitFxTable.Names)
            {
                var f = OutfitFxTable.For(n);
                modes &= FxMode.IsOutfit(f.Mode) && f.Name == n;
                colours &= f.R >= 0 && f.R <= 1 && f.G >= 0 && f.G <= 1 && f.B >= 0 && f.B <= 1;
            }
            check(modes, "outfit fx: every entry has an outfit mode and its own name");
            check(colours, "outfit fx: colours inside 0..1");
            check(OutfitFxTable.For("red_energizer").Mode == FxMode.Pulse && OutfitFxTable.For("red_energizer").R == 1f && OutfitFxTable.For("red_energizer").G == 0f, "outfit fx: red_energizer is a red pulse");
            check(OutfitFxTable.For("chaos_cinder_crown").Mode == FxMode.Crown && !OutfitFxTable.For("chaos_cinder_crown").Family, "outfit fx: the Chaos shaders have their own modes");
            check(OutfitFxTable.For("green_pixent").Family && OutfitFxTable.For("green_pixent").Mode == FxMode.Sparks, "outfit fx: the store families keep their colour");
            check(FxMode.IsKnown(FxMode.Water) && FxMode.IsKnown(FxMode.Solid) && !FxMode.IsKnown(5) && !FxMode.IsKnown(99), "fx modes: known and unknown numbers");
            // the names are those of the main client's list
            string root = FindRoot();
            string lua = root == null ? null : Read(root, "client", "overlay", "modules", "game_chaosshaders", "outfitshaderlist.lua");
            if (lua == null) { check(true, "outfit fx: lua list not found, skipped"); return; }
            var names = new List<string>();
            foreach (Match m in Regex.Matches(lua, "^\\s*(?:\\[\"([^\"]+)\"\\]|(\\w+)) = \\{ id = \\d+, label", RegexOptions.Multiline)) names.Add(m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value);
            check(names.Count == 26, "outfit fx: the Lua list has 26 names, " + names.Count);
            check(names.All(n => OutfitFxTable.For(n) != null), "outfit fx: every name of outfitshaderlist.lua is in the table: " + string.Join(",", names.Where(n => OutfitFxTable.For(n) == null)));
            check(OutfitFxTable.Names.All(n => names.Contains(n)), "outfit fx: the table holds no name the Lua list lacks");
            // the hit flash numbers are those of chaos_outfit_hit_white / hit_red
            check(Math.Abs(HitFlashFx.Mix(false, 1f) - 0.78f) < 1e-6 && Math.Abs(HitFlashFx.Mix(true, 1f) - 0.62f) < 1e-6 && HitFlashFx.Mix(true, 0f) == 0f && HitFlashFx.Mix(false, 2f) == 0.78f, "hit flash: the mix of the two shaders");
            check(HitFlashFx.ModeOf(true) == FxMode.HitRed && HitFlashFx.ModeOf(false) == FxMode.HitWhite, "hit flash: modes");
        }

        static void GradeChecks(Action<bool, string> check)
        {
            var v = MapGradeFx.Clamp(new[] { 0.5, -0.5, 0.0, 0.9, -0.9 });
            check(v[0] == MapGradeFx.MaxTint && v[1] == -MapGradeFx.MaxTint && v[2] == 0f && v[3] == MapGradeFx.MaxSat && v[4] == -MapGradeFx.MaxCon, "grade: the mood is cut to the engine's limits");
            var z = MapGradeFx.Clamp(null);
            check(z.All(x => x == 0f), "grade: no mood is neutral");
            check(MapGradeFx.Clamp(new[] { double.NaN, 0.01 })[0] == 0f && MapGradeFx.Clamp(new[] { double.NaN, 0.01 })[1] == 0.01f, "grade: a bad number counts as 0");
            MapGradeFx.Grade(0.5f, 0.5f, 0.5f, null, false, out float r0, out float g0, out float b0);
            check(r0 == 0.5f && g0 == 0.5f && b0 == 0.5f, "grade: off leaves the colour");
            MapGradeFx.Grade(0.8f, 0.2f, 0.2f, null, true, out float r1, out float g1, out float b1);
            float sat0 = 0.8f - 0.2f, sat1 = Math.Max(r1, Math.Max(g1, b1)) - Math.Min(r1, Math.Min(g1, b1));
            check(sat1 > 0f && r1 > g1 && r1 <= 1f && b1 >= 0f, "grade: the plain grade keeps the hue " + r1 + "," + g1 + "," + b1);
            check(sat1 >= sat0 * 0.9f - 0.2f, "grade: a little less colour, a little more contrast");
            var ice = MapGradeFx.Clamp(new[] { -0.020, 0.004, 0.034, -0.02, 0.0 });
            MapGradeFx.Grade(0.5f, 0.5f, 0.5f, ice, true, out float ir, out float ig, out float ib);
            MapGradeFx.Grade(0.5f, 0.5f, 0.5f, null, true, out float pr, out float pg, out float pb);
            check(ib - ir > pb - pr, "grade: the ice mood is bluer than the plain grade");
            check(MapGradeFx.Vignette(0f, 0f) > 0.999f, "grade: the vignette leaves the middle");
            check(Math.Abs(MapGradeFx.Vignette(1f, 1f) - (1f - MapGradeFx.VignetteDark)) < 0.01f, "grade: the corner is darkened by the full amount");
            check(MapGradeFx.Vignette(0.6f, 0f) > MapGradeFx.Vignette(1f, 0f), "grade: the vignette deepens toward the edge");
            check(MapGradeFx.Bloom(false) == 0f && MapGradeFx.Bloom(true) == MapGradeFx.BloomStrength && MapGradeFx.Bloom(true, 5f) == MapGradeFx.BloomMaxStrength, "bloom: off is 0, on is the strength, capped");
            check(MapGradeFx.BloomThreshold < MapGradeFx.BloomFull && Math.Abs(MapGradeFx.BlurTaps.Sum(t => t[1] * (t[0] == 0f ? 1 : 2)) - 1f) < 1e-4f, "bloom: the blur weights add up to 1");
            // the numbers are those of the Lua files
            string root = FindRoot();
            string mood = root == null ? null : Read(root, "client", "overlay", "modules", "game_visualfx", "grademood_logic.lua");
            if (mood != null)
                foreach (var kv in WeatherState.Moods)
                {
                    var m = Regex.Match(mood, kv.Key + "\\s*=\\s*\\{ r =\\s*(-?[0-9.]+), g =\\s*(-?[0-9.]+), b =\\s*(-?[0-9.]+), sat =\\s*(-?[0-9.]+), con =\\s*(-?[0-9.]+)");
                    bool same = m.Success;
                    for (int i = 0; same && i < 5; i++) same = Math.Abs(double.Parse(m.Groups[i + 1].Value, System.Globalization.CultureInfo.InvariantCulture) - kv.Value[i]) < 1e-9;
                    check(same, "grade: the mood " + kv.Key + " is the one of grademood_logic.lua");
                }
            string logic = root == null ? null : Read(root, "client", "overlay", "modules", "game_visualfx", "visualfx_logic.lua");
            if (logic != null)
            {
                check(Regex.IsMatch(logic, "threshold = " + MapGradeFx.BloomThreshold.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)) && Regex.IsMatch(logic, "full = " + MapGradeFx.BloomFull.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)), "bloom: the luma limits of visualfx_logic.lua");
                check(Regex.IsMatch(logic, "strength = " + MapGradeFx.BloomStrength.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)) && Regex.IsMatch(logic, "maxStrength = " + MapGradeFx.BloomMaxStrength.ToString("0.0", System.Globalization.CultureInfo.InvariantCulture)), "bloom: the strengths of visualfx_logic.lua");
            }
        }

        static void LiquidChecks(Action<bool, string> check)
        {
            check(LiquidGrounds.ModeOf(629) == FxMode.Water && LiquidGrounds.ModeOf(634) == FxMode.Water && LiquidGrounds.ModeOf(635) == FxMode.None, "liquids: stock shallow water");
            check(LiquidGrounds.ModeOf(4609) == FxMode.Water && LiquidGrounds.ModeOf(33463) == FxMode.Water && LiquidGrounds.ModeOf(35101) == FxMode.Water, "liquids: pack water");
            check(LiquidGrounds.ModeOf(728) == FxMode.Lava && LiquidGrounds.ModeOf(730) == FxMode.Lava && LiquidGrounds.ModeOf(35059) == FxMode.Lava && LiquidGrounds.ModeOf(35073) == FxMode.Lava && LiquidGrounds.ModeOf(35074) == FxMode.None, "liquids: lava");
            check(LiquidGrounds.ModeOf(0) == FxMode.None && LiquidGrounds.ModeOf(-5) == FxMode.None && LiquidGrounds.ModeOf(100) == FxMode.None, "liquids: other grounds are plain");
            // every range is the one of visualfx_logic.lua
            string root = FindRoot();
            string logic = root == null ? null : Read(root, "client", "overlay", "modules", "game_visualfx", "visualfx_logic.lua");
            if (logic == null) return;
            foreach (string kind in new[] { "water", "lava" })
            {
                var line = Regex.Match(logic, "^  " + kind + " = \\{ (\\{ \\d+.*)\\},\\s*$", RegexOptions.Multiline);
                check(line.Success, "liquids: " + kind + " line found in visualfx_logic.lua");
                if (!line.Success) continue;
                int want = kind == "water" ? FxMode.Water : FxMode.Lava, n = 0;
                bool all = true;
                foreach (Match r in Regex.Matches(line.Groups[1].Value, "\\{ (\\d+), (\\d+) \\}"))
                    for (int id = int.Parse(r.Groups[1].Value); id <= int.Parse(r.Groups[2].Value); id++) { all &= LiquidGrounds.ModeOf(id) == want; n++; }
                check(all && n > 5, "liquids: all " + n + " ids of " + kind + " in visualfx_logic.lua shimmer");
            }
        }

        static void OutlineChecks(Action<bool, string> check)
        {
            var t = OutlineFx.Target(); var f = OutlineFx.Follow();
            check(Math.Abs(t.R - 235 / 255f) < 1e-6 && Math.Abs(t.G - 45 / 255f) < 1e-6 && t.PulseMs == 1600 && t.WidthPx == 2 && f.PulseMs == 0 && Math.Abs(f.G - 220 / 255f) < 1e-6, "outline: target red and pulsing, follow green and steady");
            var cosmeticArts = OutlineFx.CosmeticArts.ToList();
            check(cosmeticArts.Count == 13, "outline: 13 bought outlines, " + cosmeticArts.Count);
            check(OutlineFx.Cosmetic("ember", true).Gradient && !OutlineFx.Cosmetic("gold", false).Gradient && OutlineFx.Cosmetic("gold", true).PulseMs == 1800 && OutlineFx.Cosmetic("gold", false).PulseMs == 0, "outline: gradients and pulses of bought outlines");
            check(OutlineFx.Cosmetic("nothing", true) == null && OutlineFx.Cosmetic(null, false) == null, "outline: an unknown art has none");
            OutlineFx.ColorAt(OutlineFx.Cosmetic("ember", false), 0f, out float r0, out float g0, out float b0);
            OutlineFx.ColorAt(OutlineFx.Cosmetic("ember", false), 1f, out float r1, out float g1, out float b1);
            check(Math.Abs(r0 - 228 / 255f) < 1e-6 && Math.Abs(g1 - 214 / 255f) < 1e-6 && g1 > g0, "outline: the gradient runs from the feet to the top");
            OutlineFx.ColorAt(OutlineFx.Cosmetic("gold", false), 0.7f, out float r2, out float g2, out float b2);
            check(Math.Abs(r2 - 255 / 255f) < 1e-6 && Math.Abs(g2 - 208 / 255f) < 1e-6, "outline: one colour without a top");
            check(OutlineFx.Ring.Length == 8 && OutlineFx.Ring.All(d => Math.Abs(d[0]) <= 1 && Math.Abs(d[1]) <= 1 && (d[0] != 0 || d[1] != 0)), "outline: a ring of eight steps");
            // who wears which
            var gold = OutlineFx.Cosmetic("gold", false);
            check(OutlineFx.Of(5, 1, 5, 0, true, gold).Kind == "target", "outline: the attacked one is red");
            check(OutlineFx.Of(6, 1, 5, 6, true, gold).Kind == "follow", "outline: the followed one is green");
            check(OutlineFx.Of(7, 1, 5, 6, true, gold) == gold && OutlineFx.Of(7, 1, 5, 6, true, null) == null, "outline: others keep a bought one, or none");
            check(OutlineFx.Of(1, 1, 1, 1, true, gold) == gold, "outline: the player never gets the target outline");
            check(OutlineFx.Of(5, 1, 5, 6, false, gold) == gold, "outline: the option off leaves the bought outline");
            check(OutlineFx.Of(0, 1, 0, 0, true, null) == null, "outline: creature 0 has none");
            check(OutlineFx.PulseAlpha(123, 0) == 1f, "outline: a steady outline is fully opaque");
            float lo = 9f, hi = 0f;
            for (double ms = 0; ms < 1800; ms += 25) { float a = OutlineFx.PulseAlpha(ms, 1800); lo = Math.Min(lo, a); hi = Math.Max(hi, a); }
            check(lo >= 0.45f - 1e-4f && lo < 0.5f && hi > 0.99f && hi <= 1.0001f, "outline: a pulse breathes between 0.45 and 1: " + lo + " " + hi);
            // the colours are those of cosmeticfxlogic.lua
            string root = FindRoot();
            string cf = root == null ? null : Read(root, "client", "overlay", "modules", "game_cosmeticfx", "cosmeticfxlogic.lua");
            if (cf == null) return;
            var arts = new List<string>();
            foreach (Match m in Regex.Matches(cf, "^  (\\w+) = \\{ c = \\{ (\\d+), (\\d+), (\\d+) \\}(?:, top = \\{ (\\d+), (\\d+), (\\d+) \\})? \\},", RegexOptions.Multiline))
            {
                string art = m.Groups[1].Value;
                arts.Add(art);
                var o = OutlineFx.Cosmetic(art, false);
                bool same = o != null && Math.Abs(o.R - int.Parse(m.Groups[2].Value) / 255f) < 1e-6 && Math.Abs(o.G - int.Parse(m.Groups[3].Value) / 255f) < 1e-6 && Math.Abs(o.B - int.Parse(m.Groups[4].Value) / 255f) < 1e-6
                    && o.Gradient == m.Groups[5].Success && (!m.Groups[5].Success || Math.Abs(o.TopR - int.Parse(m.Groups[5].Value) / 255f) < 1e-6);
                check(same, "outline: " + art + " is the colour of cosmeticfxlogic.lua");
            }
            check(arts.Count == 13 && arts.OrderBy(x => x).SequenceEqual(cosmeticArts.OrderBy(x => x)), "outline: the same 13 arts as cosmeticfxlogic.lua");
        }

        static FrameGroup Group(int phases, int[] ms = null) => new FrameGroup { Phases = phases, MinDuration = ms, MaxDuration = ms, Width = 1, Height = 1, Layers = 1, PatternX = 1, PatternY = 1, PatternZ = 1 };

        static void PackChecks(Action<bool, string> check)
        {
            var g = Group(4);
            check(Math.Abs(PackFx.Length(g) - 280) < 1e-9, "pack fx: four frames of 70 ms are 280 ms");
            check(PackFx.Phase(g, 0) == 0 && PackFx.Phase(g, 69.9) == 0 && PackFx.Phase(g, 70) == 1 && PackFx.Phase(g, 279) == 3 && PackFx.Phase(g, 280) == -1 && PackFx.Phase(g, -1) == -1, "pack fx: the frame at a time, -1 when over");
            var d = Group(3, new[] { 100, 50, 200 });
            check(Math.Abs(PackFx.Length(d) - 350) < 1e-9 && PackFx.Phase(d, 99) == 0 && PackFx.Phase(d, 100) == 1 && PackFx.Phase(d, 150) == 2 && PackFx.Phase(d, 349) == 2 && PackFx.Phase(d, 350) == -1, "pack fx: frame durations of the dat");
            var r = new FrameGroup { Phases = 2, MinDuration = new[] { 40, 40 }, MaxDuration = new[] { 80, 80 } };
            check(Math.Abs(PackFx.Length(r) - 120) < 1e-9, "pack fx: a duration range counts at its middle");
            var z = Group(0);
            check(PackFx.Length(z) == 0 && PackFx.Phase(z, 10) == -1 && PackFx.Phase(null, 10) == -1 && PackFx.LoopPhase(null, 5) == -1, "pack fx: an empty or missing group draws nothing");
            var beam = Group(24);
            check(PackFx.LoopPhase(beam, 0) == 0 && PackFx.LoopPhase(beam, PackFx.BeamLoopMs) == 0 && PackFx.LoopPhase(beam, 70) == 1 && PackFx.LoopPhase(beam, 24 * 70 + 10) == -1 && PackFx.LoopPhase(beam, PackFx.BeamLoopMs + 140) == 2, "pack fx: a beam plays 24 frames, rests, then plays again");
            check(PackFx.LoopPhase(beam, -70) >= -1, "pack fx: a negative clock does not crash");
            PackFx.CellTile(10, 20, 2, 1, out int cx, out int cy);
            check(cx == 8 && cy == 19, "pack fx: a cell lies west and north of the effect's tile");
            check(PackFx.BeamId("white") == 4101 && PackFx.BeamId("orb") == 4090 && PackFx.BeamId("zzz") == 0 && PackFx.BeamId(null) == 0, "pack fx: beam ids by group");
            check(PackFx.BeamGroups.All(k => LootBeams.Colors.ContainsKey(k)) && LootBeams.Colors.Keys.All(k => PackFx.BeamId(k) != 0), "pack fx: every beam group of the loot rules has an effect");
            var full = new FrameGroup { Width = PackFx.BeamFullW, Height = PackFx.BeamFullH };
            var half = new FrameGroup { Width = 1, Height = 2 };
            var at = new Pos(100, 200, 7);
            check(PackFx.BeamTile(at, full) == new Pos(101, 201, 7), "pack fx: a 3 x 5 beam (pair 65) is drawn one tile south-east of its tile");
            check(PackFx.BeamTile(at, half) == at && PackFx.BeamTile(at, null) == at, "pack fx: a 1 x 2 beam (pair 36 to 64) or none is drawn on its tile");
            string root = FindRoot();
            string lb = root == null ? null : Read(root, "client", "overlay", "modules", "game_lootbeams", "lootbeamslogic.lua");
            if (lb != null)
            {
                var m = Regex.Match(lb, "LB\\.EFFECTS = \\{\\s*(.*?)\\}", RegexOptions.Singleline);
                int n = 0; bool same = m.Success;
                if (m.Success)
                    foreach (Match e in Regex.Matches(m.Groups[1].Value, "(\\w+) = (\\d+)")) { same &= PackFx.BeamId(e.Groups[1].Value) == int.Parse(e.Groups[2].Value); n++; }
                check(same && n == 6, "pack fx: the six beam ids are those of lootbeamslogic.lua");
                check(Regex.IsMatch(lb, "LB\\.EFFECT_MS = " + (int)PackFx.BeamLoopMs + "\\b"), "pack fx: the beam loop is lootbeamslogic.lua EFFECT_MS");
                var fs = Regex.Match(lb, "LB\\.FULL_SIZE = \\{ w = (\\d+), h = (\\d+), dx = (\\d+), dy = (\\d+) \\}");
                check(fs.Success && int.Parse(fs.Groups[1].Value) == PackFx.BeamFullW && int.Parse(fs.Groups[2].Value) == PackFx.BeamFullH && int.Parse(fs.Groups[3].Value) == PackFx.BeamFullDx && int.Parse(fs.Groups[4].Value) == PackFx.BeamFullDy, "pack fx: the full size beam and its offset are those of lootbeamslogic.lua");
            }
            string lw = root == null ? null : Read(root, "client", "overlay", "modules", "game_levelwings", "levelwingsmath.lua");
            if (lw != null)
            {
                var m = Regex.Match(lw, "M\\.EFFECT = \\{ id = (\\d+), dx = (\\d+), dy = (\\d+) \\}");
                check(m.Success && int.Parse(m.Groups[1].Value) == PackFx.LevelUpId && int.Parse(m.Groups[2].Value) == PackFx.LevelUpDx && int.Parse(m.Groups[3].Value) == PackFx.LevelUpDy, "pack fx: the level-up effect and its offset are those of levelwingsmath.lua");
            }
            check(Math.Abs(LevelWingsState.LifeMs - 25 * PackFx.DefaultFrameMs) < 1e-9, "pack fx: the level-up play is 25 frames of 70 ms, the life of the drawn stand-in");
        }

        static void BeamMessageChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var lf = new LootFilterModel(ext);
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":7,\"p\":[100,200,7],\"i\":[{\"r\":4,\"g\":\"equipment\"},{\"r\":1,\"u\":true,\"g\":\"equipment\"}]}}");
            check(lf.Beams.Count == 1 && lf.Beams[7].Pos.X == 100 && lf.Beams[7].Pos.Y == 200 && lf.Beams[7].Pos.Z == 7 && lf.Beams[7].Items.Count == 2 && lf.Beams[7].Items[1].U, "beam message: a corpse with two items that may beam");
            var s = new LootFilterSettings { Highlight = 1 };
            var look = LootBeams.BeamOf(lf.Beams[7].Items, s, new LootBeamSettings());
            check(look != null && look.Group == "unique", "beam message: the best item (a unique) gives the beam its group");
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":7,\"p\":[100,200,7],\"i\":[{\"r\":4}]}}");
            check(lf.Beams.Count == 1 && lf.Beams[7].Items.Count == 1, "beam message: a later message replaces the items");
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":7,\"i\":[]}}");
            check(lf.Beams.Count == 0, "beam message: an empty list ends the beam");
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":8,\"i\":[{\"r\":4}]}}");
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"p\":[1,2,3],\"i\":[{\"r\":4}]}}");
            ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":9,\"p\":[\"a\",2,3],\"i\":[{\"r\":4}]}}");
            check(lf.Beams.Count == 0, "beam message: no tile, no kill number or a bad tile is ignored");
            for (int k = 0; k < LootFilterModel.MaxServerBeams + 5; k++) ext.Receive(238, "{\"action\":\"beam\",\"data\":{\"k\":" + (100 + k) + ",\"p\":[1,2,7],\"i\":[{\"r\":4}]}}");
            check(lf.Beams.Count == LootFilterModel.MaxServerBeams, "beam message: at most " + LootFilterModel.MaxServerBeams + " corpses");
            ext.Receive(238, "{\"action\":\"decay\",\"data\":{\"k\":100}}");
            check(!lf.Beams.ContainsKey(100), "beam message: a decayed corpse loses its beam");
            lf.Reset();
            check(lf.Beams.Count == 0, "beam message: a reset clears the beams");
        }

        static void PulseChecks(Action<bool, string> check)
        {
            check(CooldownPulseFx.ShouldPulse(5000, 5000) && CooldownPulseFx.ShouldPulse(5000, 4900) && !CooldownPulseFx.ShouldPulse(5000, 4000) && !CooldownPulseFx.ShouldPulse(2000, 2000) && CooldownPulseFx.ShouldPulse(3000, 3000), "cooldown pulse: only a long cooldown at its end");
            check(CooldownPulseFx.Opacity(-1) == 0f && CooldownPulseFx.Opacity(0) == 0f && Math.Abs(CooldownPulseFx.Opacity(40) - CooldownPulseFx.Peak) < 1e-6f && CooldownPulseFx.Opacity(280) == 0f && CooldownPulseFx.Opacity(160) < CooldownPulseFx.Opacity(80), "cooldown pulse: rises in 40 ms, falls to 0 at 280 ms");
            var p = new CooldownPulseFx();
            check(p.Start("a", 1000) && p.Alive == 1 && p.Now("a", 1040) > 0.5f && p.Now("a", 1300) == 0f && p.Alive == 0, "cooldown pulse: a pulse starts, shows and ends");
            bool dropped = false;
            for (int i = 0; i < CooldownPulseFx.MaxAlive + 3; i++) if (!p.Start("k" + i, 5000)) dropped = true;
            check(dropped && p.Alive == CooldownPulseFx.MaxAlive, "cooldown pulse: at most " + CooldownPulseFx.MaxAlive + " at once");
            check(p.Start("k0", 6000), "cooldown pulse: a slot that pulses again restarts");
            p.Clear();
            check(p.Alive == 0 && p.Now("k0", 6000) == 0f, "cooldown pulse: cleared");
        }

        // ------------------------------------------------------------------------------------ the shader sources
        static int Count(string s, char c) { int n = 0; foreach (char x in s) if (x == c) n++; return n; }

        static string StripComments(string s)
        {
            s = Regex.Replace(s, "/\\*.*?\\*/", "", RegexOptions.Singleline);
            return Regex.Replace(s, "//[^\n]*", "");
        }

        static void ShaderSourceChecks(Action<bool, string> check)
        {
            string root = FindRoot();
            if (root == null) { check(true, "shader sources: repo root not found, skipped"); return; }
            string dir = Path.Combine(root, "unity", "Client", "Assets", "Chaos", "Resources", "Shaders");
            var files = new[] { "ChaosMapFx.shader", "ChaosGrade.shader", "ChaosFx.cginc" };
            foreach (string f in files)
            {
                string p = Path.Combine(dir, f);
                check(File.Exists(p), "shader sources: " + f + " exists");
                if (!File.Exists(p)) continue;
                string text = StripComments(File.ReadAllText(p));
                check(Count(text, '{') == Count(text, '}') && Count(text, '(') == Count(text, ')') && Count(text, '[') == Count(text, ']'), "shader sources: " + f + " has balanced braces");
                check(!text.Contains("vec2") && !text.Contains("vec3") && !text.Contains("vec4") && !text.Contains("texture2D") && !text.Contains("gl_FragColor"), "shader sources: " + f + " has no GLSL left");
            }
            string map = StripComments(File.ReadAllText(Path.Combine(dir, "ChaosMapFx.shader")));
            string grade = StripComments(File.ReadAllText(Path.Combine(dir, "ChaosGrade.shader")));
            check(Regex.IsMatch(map, "Shader \"Chaos/MapFx\"") && map.Contains("Fallback \"Sprites/Default\"") && map.Contains("#include \"ChaosFx.cginc\"") && map.Contains("TEXCOORD1"), "shader sources: MapFx has its name, a fallback, the include and the fx channel");
            check(Regex.IsMatch(grade, "Shader \"Chaos/MapGrade\"") && Count(grade, '\n') > 10 && Regex.Matches(grade, "\\bPass\\b").Count == 3 && grade.Contains("fragBright") && grade.Contains("fragBlur") && grade.Contains("fragComposite"), "shader sources: MapGrade has three passes");
            check(FxShaders_Names("Chaos/MapFx", "Chaos/MapGrade"), "shader sources: the names the code looks up");
            // the mode numbers of the include are those of FxMode
            string inc = File.ReadAllText(Path.Combine(dir, "ChaosFx.cginc"));
            var defs = new Dictionary<string, int>();
            foreach (Match m in Regex.Matches(inc, "^#define FX_(\\w+) (\\d+)", RegexOptions.Multiline)) defs[m.Groups[1].Value] = int.Parse(m.Groups[2].Value);
            var want = new Dictionary<string, int>
            {
                { "HAZE", FxMode.Haze }, { "WAVES", FxMode.Waves }, { "PULSE", FxMode.Pulse }, { "SPARKS", FxMode.Sparks }, { "EMBER", FxMode.Ember }, { "FROST", FxMode.Frost },
                { "VOID", FxMode.Void }, { "HOLY", FxMode.Holy }, { "BLOOD", FxMode.Blood }, { "GHOST", FxMode.Ghost }, { "ASH", FxMode.Ash }, { "CROWN", FxMode.Crown },
                { "HITWHITE", FxMode.HitWhite }, { "HITRED", FxMode.HitRed }, { "SOLID", FxMode.Solid }, { "ITEMGLOW", FxMode.ItemGlow }, { "METAL", FxMode.Metal }, { "WATER", FxMode.Water }, { "LAVA", FxMode.Lava },
            };
            check(defs.Count == want.Count && want.All(kv => defs.TryGetValue(kv.Key, out int v) && v == kv.Value), "shader sources: the FX_ defines of ChaosFx.cginc are the FxMode numbers");
            // the effects the Chaos outfit shaders have in the include: one branch each
            foreach (string m in new[] { "EMBER", "FROST", "VOID", "HOLY", "BLOOD", "GHOST", "ASH", "CROWN" })
                check(Regex.IsMatch(inc, "mode == FX_" + m + "\\b"), "shader sources: ChaosFx.cginc draws " + m);
            check(inc.Contains("#ifndef CHAOS_FX_INCLUDED") && inc.TrimEnd().EndsWith("#endif"), "shader sources: the include has a guard");
            // the edited surface shaders still include it by a path that exists, and read their fx channel
            foreach (string rel in new[] { "Hd2dSprite.shader", "FrontArtSprite.shader" })
            {
                string p = Path.Combine(root, "unity", "Client", "Assets", "Chaos", "Unity", "Resources", rel);
                string text = File.ReadAllText(p);
                var inclm = Regex.Match(text, "#include \"(Assets/[^\"]+)\"");
                check(inclm.Success && File.Exists(Path.Combine(root, "unity", "Client", inclm.Groups[1].Value)), "shader sources: " + rel + " includes ChaosFx.cginc by an existing path");
                string st = StripComments(text);
                check(Count(st, '{') == Count(st, '}') && st.Contains("FxApply"), "shader sources: " + rel + " balanced and calls FxApply");
            }
            check(File.ReadAllText(Path.Combine(root, "unity", "Client", "Assets", "Chaos", "Unity", "Resources", "Hd2dSprite.shader")).Contains("uv2_MainTex"), "shader sources: Hd2dSprite reads the second UV set");
            check(File.ReadAllText(Path.Combine(root, "unity", "Client", "Assets", "Chaos", "Unity", "Resources", "FrontArtSprite.shader")).Contains("_FxMode"), "shader sources: FrontArtSprite has _FxMode");
        }

        static bool FxShaders_Names(params string[] names)
        {
            // the glue (Unity/Phase8CFx.cs) is not in Core: read it as text
            string root = FindRoot();
            string p = root == null ? null : Path.Combine(root, "unity", "Client", "Assets", "Chaos", "Unity", "Phase8CFx.cs");
            if (p == null || !File.Exists(p)) return true;
            string t = File.ReadAllText(p);
            return names.All(n => t.Contains("\"" + n + "\""));
        }

        static void LocChecks(Action<bool, string> check)
        {
            Loc.Set("pt-BR");
            foreach (var kv in LocPhase8C.PtBr)
            {
                check(Loc.T(kv.Key) == kv.Value && kv.Value != kv.Key, "loc: " + kv.Key);
            }
            Loc.Set("en");
            check(Loc.T("Living water and lava") == "Living water and lava", "loc: English is the key");
        }
    }
}
