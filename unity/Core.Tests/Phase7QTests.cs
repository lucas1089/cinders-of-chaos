// Phase 7, track Q: UI, map and visual rows. The wide aware range views, the interface scale option, the window theme, the map mark pictures, the name plate pictures,
// the explored map file, the death note, the tiled weather pictures and the pt-BR texts.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class Phase7QTests
    {
        public static void Run(Action<bool, string> check)
        {
            View(check);
            UiScale(check);
            Theme(check);
            Marks(check);
            MapFile(check);
            Death(check);
            Tiled(check);
            Boss(check);
            Chat(check);
            Texts(check);
        }

        static string Repo() => Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", ".."));

        static void View(Action<bool, string> check)
        {
            check(ViewZoom.MaxRowsFor(17, 13) == 11, "q view: the default area 17 x 13 holds 11 rows, as before");
            check(ViewZoom.MaxRowsFor(29, 21) == 19, "q view: the largest area 29 x 21 holds 19 rows (two tiles stay unused)");
            check(ViewZoom.MaxRowsFor(21, 17) == 13 && ViewZoom.MaxRowsFor(1, 1) == ViewZoom.MaxRows, "q view: a middle area, and a broken one keeps the old maximum");
            check(ViewZoom.Cols(19) > 25f && ViewZoom.Cols(19, 29) <= 27f && ViewZoom.Cols(11, 17) <= 15f && Math.Abs(ViewZoom.Cols(11) - 15f) < 1e-4, "q view: the columns keep the 15 : 11 shape inside the width");
            check(ViewZoom.Clamp(19, 19) == 19 && ViewZoom.Clamp(22, 19) == 19 && ViewZoom.Clamp(13, 11) == 11 && ViewZoom.Clamp(2, 21) == 7, "q view: rows kept inside 7 and the maximum");
            check(ViewZoom.Step(11, 1, 19) == 13 && ViewZoom.Step(19, 1, 19) == 19 && ViewZoom.Step(9, -1, 21) == 7, "q view: a step is two rows");
            var wide = ViewZoom.Wanted(true); var narrow = ViewZoom.Wanted(false);
            check(wide.Width == 29 && wide.Height == 21 && narrow.Width == 17 && narrow.Height == 13, "q view: Wide view asks for 29 x 21, off for the default");
            check(ViewZoom.CharKey("Ana Maria") == "chaos.viewrows.ana maria" && ViewZoom.CharKey("") == null, "q view: the zoom key is per character");
            check(ViewZoom.StartRows(0, 1080, 19) == 15 && ViewZoom.StartRows(0, 540, 19) == 11 && ViewZoom.StartRows(19, 540, 11) == 11 && ViewZoom.StartRows(9, 1080, 19) == 9, "q view: a new character starts near 72 px a tile, a saved zoom is kept inside the area");
            var r = new AwareRange(29, 21);
            check(r.Left == 14 && r.Right == 15 && r.Top == 10 && r.Bottom == 11 && r.Horizontal == 30 && r.Vertical == 22, "q view: the 29 x 21 area covers 30 x 22 tiles from 14 left and 10 above");
        }

        static void UiScale(Action<bool, string> check)
        {
            check(UiScaleOption.ParseSaved(1) == 1 && UiScaleOption.ParseSaved(150) == 3 && UiScaleOption.ParseSaved(-5) == UiScaleOption.DefaultIndex && UiScaleOption.ParseSaved(99) == 1, "q uiscale: saved value as an index or a percent");
            check(UiScaleOption.Percent(1) == 100 && UiScaleOption.Percent(99) == 300 && UiScaleOption.Percent(-3) == 75, "q uiscale: percent of a step, kept in range");
            check(Math.Abs(UiScaleOption.Factor(1, 1920, 1080, 1.5f) - 1.5f) < 1e-4, "q uiscale: 100 percent is the automatic scale");
            check(Math.Abs(UiScaleOption.Factor(2, 1920, 1080, 1.5f) - 1.875f) < 1e-4 && Math.Abs(UiScaleOption.Factor(3, 1920, 1080, 1.5f) - 1.875f) < 1e-4, "q uiscale: 125 percent on a full HD window, 150 is lowered to it");
            check(UiScaleOption.MaxIndex(1920, 1080, 1.5f) == 2 && UiScaleOption.MaxIndex(960, 540, 1f) == 1, "q uiscale: a bigger step needs the room of 960 x 540 units");
            check(UiScaleOption.Effective(5, 1280, 720, 1f) == 2 && UiScaleOption.Effective(5, 960, 540, 1f) == 1, "q uiscale: a step the window cannot hold is lowered to the automatic scale");
            check(Math.Abs(UiScaleOption.Factor(0, 1280, 720, 1f) - 0.75f) < 1e-4 && UiScaleOption.Factor(0, 400, 300, 0.5f) >= UiScaleOption.Floor, "q uiscale: a smaller step shrinks, never below the floor");
        }

        static void Theme(Action<bool, string> check)
        {
            check(UiTheme.Skins.Length == 3 && UiTheme.Skins.All(UiTheme.Known) && UiTheme.Normalize("x") == "classic" && UiTheme.Normalize(null) == "classic", "q theme: three skins, unknown names fall back to classic");
            check(UiTheme.Next("classic") == "forge" && UiTheme.Next("abyss") == "classic" && UiTheme.Next("zzz") == "forge", "q theme: the button cycles the skins");
            check(UiTheme.Window("classic") == "../data/images/chaos/skin/window.png" && UiTheme.Window("forge") == "../data/skins/forge/images/chaos/skin/window.png", "q theme: window picture of the skin");
            check(UiTheme.Corner("abyss", "br").EndsWith("orn_corner_br.png") && UiTheme.Corner("abyss", "zz").EndsWith("orn_corner_tl.png") && UiTheme.Crest("classic").EndsWith("orn_crest.png"), "q theme: corner pieces and crest");
            check(UiTheme.StateRow(96, 0) == 72 && UiTheme.StateRow(96, 3) == 0 && UiTheme.StateRow(96, 9) == 0 && UiTheme.ButtonSheet("abyss").EndsWith("skins/abyss/images/chaos/skin/button.png") && UiTheme.FieldPicture(true).EndsWith("textedit_focus.png"), "q theme: the button sheet cuts into four states from the top");
            check(UiTheme.PaletteOf("forge").Gold == "#ff7a1a" && UiTheme.PaletteOf("nope").Title == "#e8c477", "q theme: palette of the skin");
            check(UiTheme.ShowCrest(200) && !UiTheme.ShowCrest(160) && UiTheme.ShowCorners(300, 200) && !UiTheme.ShowCorners(80, 200) && !UiTheme.ShowCorners(300, 60), "q theme: small windows lose the ornaments");
            string data = Path.Combine(Repo(), "client", "overlay", "data");
            if (!Directory.Exists(data)) { check(true, "q theme: art files not found, skipped"); return; }
            var missing = new List<string>();
            foreach (string skin in UiTheme.Skins)
            {
                var files = new List<string> { UiTheme.Window(skin), UiTheme.Crest(skin), UiTheme.ButtonSheet(skin) };
                foreach (string c in UiTheme.Corners) files.Add(UiTheme.Corner(skin, c));
                foreach (string f in files) if (!File.Exists(Path.Combine(data, f.Substring("../data/".Length)))) missing.Add(f);
            }
            check(missing.Count == 0, "q theme: every skin has its pictures; missing: " + string.Join(", ", missing));
        }

        static void Marks(Action<bool, string> check)
        {
            check(MarkArt.Poi("temple") == "../data/images/chaos/mapmarkers/poi_temple.png" && MarkArt.Poi("bogus") == null && MarkArt.Poi(null) == null, "q marks: point of interest pictures");
            check(MarkArt.Overlay("worldboss") == "../data/images/chaos/mapoverlay/worldboss.png" && MarkArt.Overlay("self") != null && MarkArt.Overlay("poi") == null, "q marks: overlay pictures");
            check(MarkArt.PartyArrow("ne") == "../data/images/chaos/mapmarkers/party_arrow_ne.png" && MarkArt.PartyArrow("up") == null && MarkArt.Floor("down").EndsWith("floor_down.png") && MarkArt.Floor("") == null, "q marks: party arrows and floor arrows");
            check(MarkArt.NpcMark("ready").EndsWith("npcmark_ready.png") && MarkArt.NpcMark("x") == null, "q marks: NPC head marks");
            check(MarkArt.Fit(14, 20) == 14f && MarkArt.Fit(14, 30) == 28f && MarkArt.Fit(14, 9) == 9f, "q marks: pixel art is drawn at whole multiples");
            var noPic = MapMarkMath.KindCategory.Keys.Where(k => MarkArt.Poi(k) == null).ToList();
            check(noPic.Count == 0, "q marks: every point of interest kind has a picture; missing: " + string.Join(", ", noPic));
            var overlayMissing = MapOverlayState.Category.Keys.Where(k => MarkArt.Overlay(k) == null).ToList();
            check(overlayMissing.Count == 0, "q marks: every overlay kind has a picture; missing: " + string.Join(", ", overlayMissing));
            check(NameplateState.Frames.All(f => PlateArt.Path(f) == "game_nameplate/images/plate_" + f + ".png") && PlateArt.Path("zz").EndsWith("plate_default.png"), "q plate: a picture for each of the 23 frames");
            var bundle = new PreviewOption { Kind = "bundle", Parts = new List<PreviewOption> { PreviewOption.Of("mount", 5), new PreviewOption { Kind = "nameplate", Frame = "frost" } } };
            check(PlateTry.Frame(new PreviewOption { Kind = "nameplate", Frame = "gold" }) == "gold" && PlateTry.Frame(bundle) == "frost" && PlateTry.Frame(new PreviewOption { Kind = "nameplate", Frame = "zz" }) == null && PlateTry.Frame(PreviewOption.Of("wings", 1)) == null && PlateTry.Frame(null) == null, "q plate: the frame a store offer would show on the own plate");
            check(PlateArt.Edge(60, 17) == 6f && PlateArt.Edge(8, 8) == 3f && PlateArt.Edge(1, 1) == 1f, "q plate: the border shrinks on a tiny box");
            string mods = Path.Combine(Repo(), "client", "overlay", "modules"), data = Path.Combine(Repo(), "client", "overlay", "data");
            if (Directory.Exists(mods))
            {
                var miss = new List<string>();
                foreach (string f in NameplateState.Frames) if (!File.Exists(Path.Combine(mods, PlateArt.Path(f)))) miss.Add(f);
                foreach (string k in MarkArt.PoiKinds) if (!File.Exists(Path.Combine(data, MarkArt.Poi(k).Substring(8)))) miss.Add("poi " + k);
                foreach (string k in MarkArt.OverlayKinds) if (!File.Exists(Path.Combine(data, MarkArt.Overlay(k).Substring(8)))) miss.Add("overlay " + k);
                foreach (string d in MarkArt.Directions) if (!File.Exists(Path.Combine(data, MarkArt.PartyArrow(d).Substring(8)))) miss.Add("arrow " + d);
                check(miss.Count == 0, "q marks: the picture files exist in client/overlay; missing: " + string.Join(", ", miss.Take(6)));
            }
        }

        static void MapFile(Action<bool, string> check)
        {
            var mem = new MinimapMemory();
            mem.SetKey(7, MinimapMemory.PackKey(32000, 32100), 5);
            mem.SetKey(7, MinimapMemory.PackKey(32001, 32100), 200);
            mem.SetKey(7, MinimapMemory.PackKey(31999, 31000), 36);
            mem.SetKey(8, MinimapMemory.PackKey(0, 0), 1);
            mem.SetKey(6, MinimapMemory.PackKey(65000, 65000), 0);   // colour 0 is no tile
            byte[] data = MinimapStore.Save(mem);
            var back = new MinimapMemory();
            check(MinimapStore.Load(data, back), "q map file: a saved map loads");
            check(back.Get(32000, 32100, 7) == 5 && back.Get(32001, 32100, 7) == 200 && back.Get(31999, 31000, 7) == 36 && back.Get(0, 0, 8) == 1 && back.Count(7) == 3 && back.Count(6) == 0, "q map file: every tile and floor comes back");
            check(MinimapStore.Save(back).SequenceEqual(data), "q map file: save, load, save gives the same bytes");
            check(!MinimapStore.Load(new byte[] { 1, 2, 3, 4, 5, 6 }, new MinimapMemory()) && !MinimapStore.Load(null, new MinimapMemory()) && !MinimapStore.Load(data.Take(data.Length - 2).ToArray(), new MinimapMemory()), "q map file: junk and a cut file are refused");
            var untouched = new MinimapMemory();
            MinimapStore.Load(data.Take(data.Length - 2).ToArray(), untouched);
            check(untouched.Count(7) == 0, "q map file: a cut file leaves the map as it was");
            check(MinimapStore.FileName("Ana Maria") == "minimap_ana_maria.bin" && MinimapStore.FileName("../x") == "minimap____x.bin" && MinimapStore.FileName("") == null, "q map file: a safe file name per character");
            check(!MinimapStore.DueForSave(5, 5, 100000, 0) && !MinimapStore.DueForSave(6, 5, 30000, 0) && MinimapStore.DueForSave(6, 5, 61000, 0), "q map file: saved at most once a minute and only when changed");
            var big = new MinimapMemory();
            for (int x = 0; x < 200; x++) for (int y = 0; y < 200; y++) big.SetKey(7, MinimapMemory.PackKey(32000 + x, 32000 + y), (byte)((x + y) % 200 + 1));
            byte[] bigData = MinimapStore.Save(big);
            var bigBack = new MinimapMemory();
            check(bigData.Length < 40000 * 3 && MinimapStore.Load(bigData, bigBack) && bigBack.Count(7) == 40000, "q map file: 40000 tiles are under 3 bytes each");
        }

        static void Death(Action<bool, string> check)
        {
            var n = new DeathNote { Name = "Ana", AtMs = 1000000, Overlay = true, Minimap = false };
            var back = DeathNote.Parse(n.Serialize());
            check(back.Name == "Ana" && back.AtMs == 1000000 && back.Overlay && !back.Minimap && back.Any, "q death: the note round trips");
            check(n.Reopens("Ana", 1060000) && !n.Reopens("Bob", 1060000) && !n.Reopens("Ana", 1000000 + MapOverlayState.DeathReopenMs + 1) && !n.Reopens("Ana", 999000), "q death: only the same character within two minutes");
            check(!DeathNote.Parse("").Any && !DeathNote.Parse("a|b|c").Any && !DeathNote.Parse("a|1|1").Any && !new DeathNote { Name = "x", AtMs = 1 }.Reopens("x", 2), "q death: broken or empty notes open nothing");
            check(DeathNote.Parse(new DeathNote { Name = "a|b", AtMs = 5, Minimap = true }.Serialize()).Name == "a b", "q death: a bar in the name cannot break the note");
        }

        static void Tiled(Action<bool, string> check)
        {
            TiledArt.Uv(256, 0, 0, 512, 256, out double u, out double v, out double du, out double dv);
            check(Math.Abs(u) < 1e-9 && Math.Abs(du - 2.0) < 1e-9 && Math.Abs(dv - 1.0) < 1e-9 && Math.Abs(v) < 1e-9, "q tiled: no offset shows the tile from its corner, twice across");
            TiledArt.Uv(256, 64, 0, 256, 256, out u, out v, out du, out dv);
            check(Math.Abs(u - 0.75) < 1e-9, "q tiled: an offset to the right shows the tile from the left of its end");
            TiledArt.Uv(256, 0, 64, 256, 64, out u, out v, out du, out dv);
            check(Math.Abs(v + dv - 0.25) < 1e-9, "q tiled: an offset down moves the top of the box up the picture");
            check(TiledArt.RainImage.Count == 3 && TiledArt.AmbientImage.Count == 6 && WeatherState.RainLayers.All(l => TiledArt.RainImage.ContainsKey(l.Name)) && WeatherState.AmbientLayers.All(l => TiledArt.AmbientImage.ContainsKey(l.Name)), "q tiled: a picture for every rain and ambient layer");
            string mods = Path.Combine(Repo(), "client", "overlay", "modules");
            if (Directory.Exists(mods))
            {
                var miss = TiledArt.RainImage.Values.Concat(TiledArt.AmbientImage.Values).Where(i => !File.Exists(Path.Combine(mods, TiledArt.Path(i)))).ToList();
                check(miss.Count == 0, "q tiled: the weather pictures exist; missing: " + string.Join(", ", miss));
            }
        }

        static IEnumerable<KeyValuePair<uint, int>> B(params int[] idHp)
        {
            for (int i = 0; i < idHp.Length; i += 2) yield return new KeyValuePair<uint, int>((uint)idHp[i], idHp[i + 1]);
        }

        static void Boss(Action<bool, string> check)
        {
            var w = new BossKillWatch();
            check(w.Step(0, 7, B(7, 100)) == 0 && w.Step(1000, 7, B(7, 40)) == 0 && w.Step(2000, 7, B(7, 0)) == 1, "q boss: a boss you attacked that reaches 0 is a kill");
            check(w.Step(3000, 7, B(7, 0)) == 0, "q boss: the same kill is not counted twice");
            var w2 = new BossKillWatch();
            check(w2.Step(0, 0, B(9, 50)) == 0 && w2.Step(500, 0, B(9, 0)) == 0, "q boss: a boss you never attacked does not count");
            var w3 = new BossKillWatch();
            w3.Step(0, 5, B(5, 30)); w3.Step(100, 5, B(5, 4));
            check(w3.Step(200, 5, B()) == 1, "q boss: a boss that leaves the view at 4 percent counts as dead");
            var w4 = new BossKillWatch();
            w4.Step(0, 5, B(5, 80));
            check(w4.Step(100, 5, B()) == 0, "q boss: a boss that walks out of view at 80 percent is not dead");
            var w5 = new BossKillWatch();
            w5.Step(0, 5, B(5, 60));
            check(w5.Step(BossKillWatch.EngagedMs + 10, 0, B(5, 0)) == 0, "q boss: an attack longer than two minutes ago is not yours");
            // the screenshot model asks for the picture when the option is on
            var ext = new ExtOpcodes();
            var shots = new ShotsState(ext) { Clock = 0 };
            shots.SetOption("shots_boss", true);
            shots.TargetNow = () => 3u;
            int step = 0;
            shots.BossesNow = () => step++ == 0 ? B(3, 50) : B(3, 0);
            shots.LevelNow = () => 100;
            shots.Poll(1000, true);
            shots.Poll(1100, true);
            check(shots.Pending == "boss", "q boss: Boss Defeated asks for a picture");
        }

        static void Chat(Action<bool, string> check)
        {
            var colors = new Dictionary<string, string> { { "Ana", "#ff8800" }, { "Bob", "bad" } };
            string rich = ChatTint.Rich("12:00", "Ana [30]: hello <b>", "Ana [30]", colors, "#f0f000");
            check(rich == "<color=#f0f000>12:00 </color><color=#ff8800>Ana</color><color=#f0f000> [30]: hello <\u200bb></color>", "q chat: the speaker's name takes its colour: " + rich);
            check(ChatTint.Rich("12:00", "Bob [30]: hi", "Bob [30]", colors, "#fff") == null && ChatTint.Rich("12:00", "Cy [3]: hi", "Cy [3]", colors, "#fff") == null && ChatTint.Rich("12:00", "hi", "", colors, "#fff") == null, "q chat: no colour, a bad colour or no speaker leave the line alone");
            check(ChatTint.Rich("1", "Ana: x", "Ana", new Dictionary<string, string> { { "Ana", "#11223344" } }, "#fff").Contains("<color=#112233>Ana"), "q chat: the alpha of an eight digit colour is dropped");
            check(ChatTint.Rich("1", "Ana: Ana wins", "Ana", colors, "#fff").Contains("<color=#ff8800>Ana</color><color=#fff>: Ana wins"), "q chat: only the speaker's own name is coloured, not the same word in the text");
            check(ChatTint.SpeakerName("Ana Maria [12]") == "Ana Maria" && ChatTint.SpeakerName("Zed") == "Zed" && ChatTint.SpeakerName(null) == "", "q chat: the name of a speaker");
        }

        static void Texts(Action<bool, string> check)
        {
            string root = Path.GetFullPath(Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "Client", "Assets", "Chaos"));
            if (!Directory.Exists(root)) { check(true, "q texts: sources not found, skipped"); return; }
            var keys = new HashSet<string>();
            var pat = new Regex("Loc\\.T\\(\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
            foreach (string f in new[] { "Unity/ChaosApp.Phase7Q.cs", "Unity/Windows/VisualWindows.cs", "Unity/Windows/StoreWindow.cs" })
                foreach (Match m in pat.Matches(File.ReadAllText(Path.Combine(root, f))))
                    keys.Add(m.Groups[1].Value.Substring(1, m.Groups[1].Value.Length - 2).Replace("\\\"", "\""));
            foreach (string s in UiTheme.SkinNames.Values) keys.Add(s);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "q texts: every text has a pt-BR entry; missing: " + string.Join(" | ", missing.Take(8)));
            var bad = LocPhase7Q.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "q texts: placeholders match: " + string.Join(" | ", bad.Take(5)));
            check(!LocPhase7Q.PtBr.Any(kv => kv.Value.Contains("—") || kv.Value.Contains("–")), "q texts: no long dashes in the pt-BR texts");
            Loc.Set("pt-BR");
            check(Loc.T("Interface scale") == "Escala da interface" && Loc.T("Window skin: {0}", "x") == "Aparência das janelas: x", "q texts: pt-BR through Loc.T");
            Loc.Set("en");
        }
    }
}
