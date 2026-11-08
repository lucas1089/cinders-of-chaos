// Visuals, audio and layout (phase 5, track R): the sound mixer and the files of game_chaossound, the region music rules and the files of game_chaosmusic,
// effect opacity, the error colour, level-up wings (191), loot beams, combat decals, chest and Templar auras (118), cosmetic prints (225 looks), ground effect
// ids, boss looks, hit flash and screen shake, name shaders (96), the map zoom, movable HUD pieces, screen fit, window fade and the saved window layout,
// and a session that wires them to the combat feed. The module files are read from client/overlay/modules when the repository is around.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class VisualTests
    {
        static string FindUp(string rel)
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++, dir = Path.GetDirectoryName(dir))
            {
                string p = Path.Combine(dir, rel);
                if (Directory.Exists(p) || File.Exists(p)) return p;
            }
            string alt = Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "..", rel));
            return Directory.Exists(alt) || File.Exists(alt) ? alt : null;
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Sounds(check);
            Music(check);
            Opacity(check);
            Wings(check);
            Beams(check);
            Decals(check);
            Auras(check);
            Cosmetic(check);
            GroundAndBoss(check);
            Flash(check);
            Shaders(check);
            Layouts(check);
            Session(check);
            Texts(check);
        }

        // ---------------------------------------------------------------------------------------------------- sounds
        static void Sounds(Action<bool, string> check)
        {
            var st = new SoundSettings();
            var m = new SoundMixer();
            Func<int, int> first = n => 0;
            check(m.Request("hit", 1000, st, out var p, 0, 1f, first) && p.File == "hit_1" && Math.Abs(p.Gain - 0.55f * 0.7f) < 1e-4, "sound: a hit plays its first variant at normal volume");
            check(!m.Request("hit", 1050, st, out _, 0, 1f, first) && m.Reason == "gap", "sound: a second hit inside the gap is one sound");
            check(m.Request("hit", 1100, st, out p, 0, 1f, first) && p.File == "hit_2", "sound: the variant is never the one before");
            check(!m.Request("hit", 5000, new SoundSettings { Enabled = false }, out _) && m.Reason == "off", "sound: the main switch");
            check(!m.Request("ui_open", 5000, st, out _) && m.Reason == "off", "sound: the window sounds are off by default");
            check(!m.Request("fire", 5000, st, out _, 12) && m.Reason == "far", "sound: an event 12 tiles away is skipped");
            check(m.Request("fire", 5000, st, out p, 9, 1f, first) && Math.Abs(p.Gain - 0.6f * 0.7f * 0.35f) < 1e-4, "sound: it fades to 35 percent at 9 tiles");
            check(SoundLogic.DistanceGain(1) == 1f && SoundLogic.DistanceGain(9.5) < 0, "sound: no fade up to 1 tile, nothing past 9");
            check(!m.Request("nope", 1, st, out _) && m.Reason == "unknown", "sound: an unknown event");
            check(!m.Request("hit", 9000, new SoundSettings { Volume = "quiet" }, out _, 0, 0f) && m.Reason == "mute", "sound: a channel gain of 0 is mute");
            // burst and cap: a spray of different events
            var b = new SoundMixer();
            string[] keys = { "fire", "ice", "energy", "holy", "death", "earth", "physical" };
            int played = 0;
            foreach (string k in keys) if (b.Request(k, 100, st, out _, 0, 1f, first)) played++;
            check(played == 3, "sound: at most 3 sounds start inside 400 ms: " + played);
            check(b.Request("levelup", 110, st, out _, 0, 1f, first) && b.Request("loot_rare", 111, st, out _, 0, 1f, first), "sound: important events may use the bonus");
            check(!b.Request("loot_unique", 112, st, out _, 0, 1f, first) && b.Reason == "burst", "sound: the bonus is 2 more");
            var c = new SoundMixer();
            int ok = 0;
            for (int i = 0; i < 20; i++) if (c.Request(keys[i % keys.Length], 1000.0 + i * 450, st, out _, 0, 1f, first)) ok++;
            check(ok >= 5, "sound: spread out, sounds keep playing: " + ok);
            var cap = new SoundMixer();
            int capped = 0;
            for (int i = 0; i < 10; i++) if (cap.Request(i % 2 == 0 ? "fire" : "death", 100.0 + i * 410, st, out _, 0, 1f, first)) capped++;
            check(capped >= 1 && cap.Active <= SoundLogic.MaxActive, "sound: the number of sounding files stays under the cap");
            // events
            check(SoundLogic.ImpactEvent(23, 0, 5, true) == "hit" && SoundLogic.ImpactEvent(23, 1, 5, true) == "crit" && SoundLogic.ImpactEvent(24, 0, 5, true) == "hurt", "sound: damage numbers: hit, crit, hurt");
            check(SoundLogic.ImpactEvent(23, 2, 5, true) == null && SoundLogic.ImpactEvent(27, 0, 5, true) == null && SoundLogic.ImpactEvent(23, 0, 0, true) == null && SoundLogic.ImpactEvent(25, 0, 5, false) == null, "sound: ticks, others, zero and heals are silent");
            check(SoundLogic.EffectEvent(3, out bool own) == "block" && own && SoundLogic.EffectEvent(416, out own) == "dodge" && own, "sound: block and dodge are the player's own");
            check(SoundLogic.EffectEvent(372, out own) == "fire" && !own && SoundLogic.EffectEvent(1, out own) == null, "sound: a fire effect plays fire, blood nothing");
            check(SoundLogic.ElementSound(FxElement.Arcane) == "energy" && SoundLogic.ElementSound(FxElement.Poison) == "earth" && SoundLogic.ElementSound(FxElement.Water) == null, "sound: element to sound set");
            var common = new LootInfo { R = 1 }; var rare = new LootInfo { R = 4 }; var great = new LootInfo { R = 10 }; var uniq = new LootInfo { R = 3, U = true };
            check(SoundLogic.LootEvent(new[] { common }, false) == null && SoundLogic.LootEvent(new[] { common, rare }, false) == "loot_rare" && SoundLogic.LootEvent(new[] { rare, great }, false) == "loot_great" && SoundLogic.LootEvent(new[] { great, uniq }, false) == "loot_unique" && SoundLogic.LootEvent(new[] { uniq }, true) == null, "sound: loot events by the best item");
            var hits = new SoundLogic.Hits();
            hits.Note(7, 1000);
            check(hits.IsMyKill(7, 2000) && !hits.IsMyKill(7, 2100), "sound: a kill counts once");
            hits.Note(8, 1000);
            check(!hits.IsMyKill(8, 4000) && !hits.IsMyKill(9, 1), "sound: a death long after the last hit is not yours");
            // settings
            var back = SoundSettings.From(Json.TryParse(new SoundSettings { Volume = "loud", Ui = true, Spells = false }.ToJson()));
            check(back.Volume == "loud" && back.Ui && !back.Spells && back.Combat && back.Enabled, "sound: settings round trip");
            check(SoundSettings.From(Json.TryParse("{\"volume\":\"deafening\"}")).Volume == "normal" && SoundSettings.From(null).Enabled, "sound: a junk volume word is normal");
            // the files of the module
            string dir = FindUp("client/overlay/modules/game_chaossound/sounds");
            if (dir == null) { check(true, "sound: module files not found (skipped)"); return; }
            var missing = SoundLogic.AllFiles().Where(f => !File.Exists(Path.Combine(dir, f + ".ogg"))).ToList();
            check(missing.Count == 0, "sound: every file of every set is in the module: " + string.Join(", ", missing.Take(5)));
            var extra = Directory.GetFiles(dir, "*.ogg").Select(Path.GetFileNameWithoutExtension).Where(f => !SoundLogic.AllFiles().Contains(f)).ToList();
            check(extra.Count == 0, "sound: no file of the module is without a set: " + string.Join(", ", extra.Take(5)));
            // the sets match soundlogic.lua
            string lua = FindUp("client/overlay/modules/game_chaossound/soundlogic.lua");
            if (lua == null) return;
            string text = File.ReadAllText(lua);
            int mismatched = 0;
            foreach (Match mm in Regex.Matches(text, @"^  (\w+)\s+= \{ group = '(\w+)', files = \{([^}]*)\}, gain = ([\d.]+), gap = (\d+),\s+ms = (\d+),\s+prio = (\d)", RegexOptions.Multiline))
            {
                var set = SoundLogic.Sets.TryGetValue(mm.Groups[1].Value, out var s) ? s : null;
                var files = Regex.Matches(mm.Groups[3].Value, "'(\\w+)'").Cast<Match>().Select(x => x.Groups[1].Value).ToArray();
                if (set == null || set.Group != mm.Groups[2].Value || !set.Files.SequenceEqual(files) || Math.Abs(set.Gain - float.Parse(mm.Groups[4].Value, System.Globalization.CultureInfo.InvariantCulture)) > 1e-4 ||
                    set.Gap != int.Parse(mm.Groups[5].Value) || set.Ms != int.Parse(mm.Groups[6].Value) || set.Prio != int.Parse(mm.Groups[7].Value)) mismatched++;
            }
            int luaSets = Regex.Matches(text, @"^  \w+\s+= \{ group = '", RegexOptions.Multiline).Count;
            check(mismatched == 0 && luaSets == SoundLogic.Sets.Count, "sound: the sets are the ones of soundlogic.lua (" + luaSets + " there, " + SoundLogic.Sets.Count + " here, " + mismatched + " differ)");
        }

        // ---------------------------------------------------------------------------------------------------- music
        static void Music(Action<bool, string> check)
        {
            var temple = new MapMark { Kind = "temple", X = 1000, Y = 1000, Z = 7 };
            var dungeon = new MapMark { Kind = "dungeon", X = 1100, Y = 1000, Z = 7 };
            var pois = new List<MapMark> { temple, dungeon };
            check(MusicLogic.PoiRegion(new Pos(1010, 1000, 7), pois) == "town" && MusicLogic.PoiRegion(new Pos(1010, 1000, 6), pois) == null, "music: a temple 10 tiles away is town, on the same floor only");
            check(MusicLogic.PoiRegion(new Pos(1090, 1000, 7), pois) == "dungeon" && MusicLogic.PoiRegion(new Pos(1050, 1050, 7), pois) == null, "music: a dungeon entrance within 14 tiles");
            var snap = new MusicSnap { Online = true, Pos = new Pos(1500, 1500, 7), Pois = pois };
            check(MusicLogic.Wanted(snap) == "hunt", "music: far from everything is hunt");
            snap.ProtectionZone = true;
            check(MusicLogic.Wanted(snap) == "town", "music: a protection zone is town");
            snap.Activity = "arena";
            check(MusicLogic.Wanted(snap) == "arena", "music: an activity beats the zone");
            snap.Boss = true;
            check(MusicLogic.Wanted(snap) == "boss" && MusicLogic.Wanted(new MusicSnap()) == "login", "music: a boss beats all, offline is login");
            var me = new Pos(100, 100, 7);
            check(MusicLogic.BossEngaged(true, 50, null, me) && !MusicLogic.BossEngaged(true, 0, null, me), "music: a boss target with health");
            var near = new List<KeyValuePair<Pos, int>> { new KeyValuePair<Pos, int>(new Pos(105, 100, 7), 80) };
            var full = new List<KeyValuePair<Pos, int>> { new KeyValuePair<Pos, int>(new Pos(105, 100, 7), 100) };
            var far = new List<KeyValuePair<Pos, int>> { new KeyValuePair<Pos, int>(new Pos(130, 100, 7), 80) };
            check(MusicLogic.BossEngaged(false, 0, near, me) && !MusicLogic.BossEngaged(false, 0, full, me) && !MusicLogic.BossEngaged(false, 0, far, me), "music: a hurt boss near is a fight, a full one or a far one is not");
            // the hysteresis
            var s = new MusicState();
            string r = MusicLogic.Step(s, "login", 0, out bool ch);
            check(ch && r == "login", "music: the first track starts at once");
            r = MusicLogic.Step(s, "hunt", 100, out ch);
            check(ch && r == "hunt", "music: login to hunt at once");
            r = MusicLogic.Step(s, "town", 200, out ch);
            check(!ch && r == "hunt", "music: a short step into town does not switch (min hold)");
            r = MusicLogic.Step(s, "town", 3199, out ch);
            check(!ch && r == "hunt", "music: hunt to town holds 3 s from the first sight");
            r = MusicLogic.Step(s, "town", 3200, out ch);
            check(ch && r == "town", "music: town after 3 s");
            r = MusicLogic.Step(s, "hunt", 3400, out ch);
            check(!ch, "music: leaving town waits");
            r = MusicLogic.Step(s, "hunt", 11399, out ch);
            check(!ch && r == "town", "music: leaving town waits 8 s");
            r = MusicLogic.Step(s, "hunt", 11400, out ch);
            check(ch && r == "hunt", "music: back to hunt after 8 s");
            r = MusicLogic.Step(s, "boss", 20000, out ch);
            check(ch && r == "boss", "music: a boss starts its track at once");
            r = MusicLogic.Step(s, "hunt", 30000, out ch);
            check(!ch, "music: the boss track stays 10 s after the fight");
            r = MusicLogic.Step(s, "hunt", 40100, out ch);
            check(ch && r == "hunt", "music: and then ends");
            check(MusicLogic.Delay("hunt", "arena") == 1000 && MusicLogic.Delay("hunt", "dungeon") == 1000 && MusicLogic.Delay("dungeon", "hunt") == 4000 && MusicLogic.Delay(null, "town") == 0, "music: the delays");
            // volume and silence
            var set = new MusicSettings { Volume = 100 };
            check(Math.Abs(set.Gain - 1f) < 1e-5 && Math.Abs(new MusicSettings { Volume = 50 }.Gain - 0.35355f) < 1e-3 && new MusicSettings { Volume = 0 }.Gain == 0f && new MusicSettings { Enabled = false }.Gain == 0f, "music: the volume curve");
            check(MusicLogic.SilentReason(new MusicSettings { Enabled = false }, true, true, true) == "off" && MusicLogic.SilentReason(new MusicSettings { Volume = 0 }, true, true, true) == "volume" &&
                  MusicLogic.SilentReason(new MusicSettings(), false, true, true) == "hidden" && MusicLogic.SilentReason(new MusicSettings { Background = true }, true, false, true) == "unfocused" &&
                  MusicLogic.SilentReason(new MusicSettings(), true, true, false) == "file" && MusicLogic.SilentReason(new MusicSettings(), true, false, true) == null, "music: the reasons for silence");
            MusicLogic.Fade(1.25, MusicLogic.Crossfade, out float o, out float i);
            check(Math.Abs(o - 0.5f) < 1e-5 && Math.Abs(i - 0.5f) < 1e-5, "music: a cross-fade is a straight line");
            var back = MusicSettings.From(Json.TryParse(new MusicSettings { Volume = 30, Background = true, Enabled = false }.ToJson()));
            check(back.Volume == 30 && back.Background && !back.Enabled && MusicSettings.From(Json.TryParse("{\"volume\":900}")).Volume == 100, "music: settings round trip and clamp");
            check(MusicLogic.File("boss") == "game_chaosmusic/music/music_boss.ogg" && MusicLogic.File("nowhere") == null, "music: the file of a region");
            // where the files are
            var roots = OverlayFiles.Candidates("/env", "/sa", "/exe", "/repo/unity/Client");
            check(roots.SequenceEqual(new[] { "/env", "/sa/overlay/modules", "/exe/overlay/modules", "/repo/client/overlay/modules" }), "music: the folders tried for the files: " + string.Join(" ", roots));
            check(OverlayFiles.Find(roots, "game_chaosmusic/music/music_town.ogg", p => p == "/exe/overlay/modules/game_chaosmusic/music/music_town.ogg") == "/exe/overlay/modules/game_chaosmusic/music/music_town.ogg" && OverlayFiles.Find(roots, "x", p => false) == null, "music: the first folder that has the file wins");
            string dir = FindUp("client/overlay/modules/game_chaosmusic/music");
            if (dir == null) { check(true, "music: module files not found (skipped)"); return; }
            var missing = MusicLogic.Regions.Where(x => !File.Exists(Path.Combine(dir, "music_" + x + ".ogg"))).ToList();
            check(missing.Count == 0, "music: every region has its file in the module: " + string.Join(", ", missing));
            string lua = FindUp("client/overlay/modules/game_chaosmusic/musiclogic.lua");
            if (lua == null) return;
            string text = File.ReadAllText(lua);
            int mm = 0;
            foreach (Match x in Regex.Matches(text, @"^  (\w+) = '(music_\w+)',", RegexOptions.Multiline)) if (MusicLogic.File(x.Groups[1].Value) != MusicLogic.Dir + x.Groups[2].Value + ".ogg") mm++;
            check(mm == 0 && Regex.Matches(text, @"^  \w+ = 'music_", RegexOptions.Multiline).Count == MusicLogic.Regions.Length, "music: the tracks are the ones of musiclogic.lua");
        }

        // ---------------------------------------------------------------------------------------------------- opacity, error colour
        static void Opacity(Action<bool, string> check)
        {
            check(EffectOpacity.Clamp(0) == 25 && EffectOpacity.Clamp(23) == 25 && EffectOpacity.Clamp(63) == 65 && EffectOpacity.Clamp(500) == 100 && EffectOpacity.Clamp(double.NaN) == 100 && EffectOpacity.Clamp(72) == 70, "opacity: clamped to 25..100 in steps of 5");
            check(Math.Abs(EffectOpacity.Alpha(50) - 0.5f) < 1e-5, "opacity: alpha of a percent");
            ErrorColor.Enabled = true;
            check(ChatModel.TextColor(21) == ErrorColor.Rgb && ErrorColor.Hex == "#ff7a5c" && ErrorColor.Rgb == 0xFF7A5C, "error colour: the status small lines are coloured");
            check(ChatModel.TextColor(4) == 0x5FF7F7 && ChatModel.TextColor(13) == 0xF55E5E, "error colour: the other kinds are as before");
            ErrorColor.Enabled = false;
            check(ChatModel.TextColor(21) == 0xFFFFFF, "error colour: off means white");
            ErrorColor.Enabled = true;
        }

        // ---------------------------------------------------------------------------------------------------- wings
        static void Wings(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            double now = 1000;
            uint self = 5;
            var w = new LevelWingsState(ext) { Clock = () => now, SelfId = () => self };
            var played = new List<uint>();
            w.Played = id => played.Add(id);
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":5,\"lv\":101,\"n\":1}}"));
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":9,\"lv\":50,\"n\":2}}"));
            check(played.SequenceEqual(new uint[] { 5, 9 }) && w.Active.Count == 2 && w.Active[1].Levels == 2, "wings: a play message starts the effect on that creature");
            w.Own = false;
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":5}}"));
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":0}}"));
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"stop\",\"data\":{\"id\":9}}"));
            ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":9.5}}"));
            check(played.Count == 2, "wings: the own option off, bad ids and other actions do nothing");
            check(LevelWingsState.Progress(1000, 1000) == 0f && LevelWingsState.Progress(1000 + 875, 1000) > 0.49f && LevelWingsState.Progress(1000 + 1750, 1000) < 0f, "wings: the effect lasts 1.75 s");
            now = 5000;
            w.Tick(now);
            check(w.Active.Count == 0, "wings: a play that is over is dropped");
        }

        // ---------------------------------------------------------------------------------------------------- loot beams
        static void Beams(Action<bool, string> check)
        {
            var filter = new LootFilterSettings();
            var s = new LootBeamSettings();
            check(LootBeams.RarityGroup(1) == "white" && LootBeams.RarityGroup(4) == "blue" && LootBeams.RarityGroup(7) == "orange" && LootBeams.RarityGroup(12) == "divine" && LootBeams.RarityGroup(0) == null, "beams: rarity to group");
            check(LootBeams.GroupOf(new LootInfo { U = true }) == "unique" && LootBeams.GroupOf(new LootInfo { Pw = true }) == "orange" && LootBeams.GroupOf(new LootInfo { O = true }) == "orb" && LootBeams.GroupOf(new LootInfo()) == null, "beams: unique, power, orb, none");
            check(LootBeams.Rank(new LootInfo { U = true }) == 100 && LootBeams.Rank(new LootInfo { R = 5, Pw = true }) == 5.5f && LootBeams.Rank(new LootInfo { O = true }) == 0.5f, "beams: the rank of an item");
            var power = LootBeams.BeamOf(new[] { new LootInfo { R = 1 }, new LootInfo { R = 5, Pw = true } }, filter, s);
            check(power != null && power.Group == "orange" && power.Color == "#ff8c1a" && Math.Abs(power.Height - 3.5f) < 1e-4, "beams: a legendary power always glows, orange, 3.5 tiles");
            var uniq = LootBeams.BeamOf(new[] { new LootInfo { R = 5, Pw = true }, new LootInfo { U = true, R = 3 } }, filter, new LootBeamSettings { Height = "tall", Intensity = "bright" });
            check(uniq != null && uniq.Group == "unique" && Math.Abs(uniq.Height - 4.5f * 1.15f) < 1e-4 && uniq.Intensity == 1f, "beams: the unique wins and the height and light follow the options");
            check(LootBeams.BeamOf(new[] { new LootInfo { O = true } }, filter, s) == null && LootBeams.BeamOf(new[] { new LootInfo { O = true } }, filter, new LootBeamSettings { Orbs = true }).Group == "orb", "beams: orbs only when asked");
            check(LootBeams.BeamOf(new LootInfo[0], filter, s) == null && LootBeams.BeamOf(null, filter, s) == null, "beams: nothing, no beam");
            var all = new List<KeyValuePair<Pos, BeamLook>>();
            for (int i = 0; i < 30; i++) all.Add(new KeyValuePair<Pos, BeamLook>(new Pos(100 + i, 100, 7), new BeamLook { Rank = i < 5 ? 100 : 5 }));
            var capped = LootBeams.Cap(all, p => Math.Abs(p.X - 100));
            check(capped.Count == 24 && capped.Take(5).All(k => k.Value.Rank == 100) && capped[5].Key.X == 105, "beams: at most 24, the best groups first, then the nearest");
            var back = LootBeamSettings.From(Json.TryParse(new LootBeamSettings { Height = "short", Orbs = true, Ground = false, Enabled = false }.ToJson()));
            check(back.Height == "short" && back.Orbs && !back.Ground && !back.Enabled && LootBeamSettings.From(Json.TryParse("{\"height\":\"huge\"}")).Height == "normal", "beams: settings round trip");
        }

        // ---------------------------------------------------------------------------------------------------- combat decals
        static void Decals(Action<bool, string> check)
        {
            // TFS text colours: 180 orange fire (255,153,0 is not on the grid), 215 white; use palette cells
            CombatDecals.PaletteRgb(0, out int r, out int g, out int b);
            check(r == 0 && g == 0 && b == 0, "decals: palette cell 0 is black");
            CombatDecals.PaletteRgb(215, out r, out g, out b);
            check(r == 255 && g == 255 && b == 255, "decals: palette cell 215 is white");
            check(CombatDecals.KindOfColor(255, 153, 0) == "fire" && CombatDecals.KindOfColor(0, 255, 255) == "ice" && CombatDecals.KindOfColor(0, 255, 0) == "poison", "decals: orange fire, cyan ice, green poison");
            check(CombatDecals.KindOfColor(255, 0, 0) == null && CombatDecals.KindOfColor(128, 128, 128) == null && CombatDecals.KindOfColor(30, 20, 0) == null && CombatDecals.KindOfColor(150, 0, 255) == null, "decals: red, grey, dark and purple name no element");
            int fireCell = 5 * 36 + 3 * 6 + 0, iceCell = 0 * 36 + 5 * 6 + 5, greenCell = 0 * 36 + 5 * 6 + 0;
            check(CombatDecals.HitKind(23, 0, 10, fireCell) == "fire" && CombatDecals.HitKind(24, 2, 10, iceCell) == "ice" && CombatDecals.HitKind(27, 1, 3, greenCell) == "poison", "decals: a damage number asks for a decal by its colour");
            check(CombatDecals.HitKind(25, 0, 10, fireCell) == null && CombatDecals.HitKind(23, 3, 10, fireCell) == null && CombatDecals.HitKind(23, 0, 0, fireCell) == null, "decals: heals, mana drain and zero leave none");
            check(CombatDecals.Art("fire", 0) == "scorch1" && CombatDecals.Art("ice", 3) == "frost2" && CombatDecals.Art("poison", 1) == "stain2" && CombatDecals.Art("blood", 2) == "blood1", "decals: the picture names");
            check(CombatDecals.Bleeds("Rat") && !CombatDecals.Bleeds("Skeleton Warrior") && !CombatDecals.Bleeds("Fire Elemental") && CombatDecals.Bleeds(""), "decals: bones and elementals bleed no red");
            check(CombatDecals.LifeFor(0) == 20000 && CombatDecals.LifeFor(1) == 29999 && CombatDecals.LifeFor(0.5) == 25000, "decals: a life of 20 to 30 s");
            check(CombatDecals.AlphaAt(0, 20000) == 0.8f && CombatDecals.AlphaAt(3999, 20000) == 0.8f && CombatDecals.AlphaAt(12000, 20000) < 0.8f && CombatDecals.AlphaAt(12000, 20000) > 0f && CombatDecals.AlphaAt(20000, 20000) < 0f, "decals: it holds, then fades out");
            var f = new DecalField();
            check(f.Add("fire", new Pos(1, 1, 7), 1000, 0) != null && f.Add("fire", new Pos(2, 1, 7), 1100, 0) == null && f.Add("fire", new Pos(2, 1, 7), 1300, 0) != null, "decals: a hit stain at most every 250 ms");
            for (int i = 0; i < 40; i++) f.Add("blood", new Pos(i, 0, 7), 2000 + i, 0.5);
            check(f.Decals.Count == 24 && f.Decals[23].Pos.X == 39, "decals: 24 at most, a death stain pushes the oldest out");
            var full = new DecalField();
            for (int i = 0; i < 24; i++) full.Add("blood", new Pos(i, 0, 7), i, 0);
            check(!full.MayAdd("fire", 9000) && full.MayAdd("blood", 9000), "decals: a hit stain waits for room, a death stain does not");
            f.Step(2000 + 40 + 40000);
            check(f.Decals.Count == 0, "decals: all gone after their life");
        }

        // ---------------------------------------------------------------------------------------------------- auras
        static void Auras(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var a = new ChestAuraState(ext);
            ext.Receive(118, ExtOpcodes.ToWire("{\"action\":\"sync\",\"data\":{\"t\":[{\"i\":10,\"l\":1,\"r\":3,\"p\":1},{\"i\":11,\"l\":2,\"r\":99},{\"i\":12,\"l\":9,\"r\":2},{\"i\":0,\"l\":1,\"r\":1}]}}"));
            check(a.Rows.Count == 2 && a.Rows[10].Party && a.Rows[10].Radius == 3 && a.Rows[11].Radius == 8 && !a.Rows[11].Party && a.Rows[11].Line == 2, "aura: sync rows, radius capped at 8, bad rows skipped");
            ext.Receive(118, ExtOpcodes.ToWire("{\"action\":\"sync\",\"data\":{\"t\":[]}}"));
            check(a.Rows.Count == 0, "aura: an empty sync removes them");
            ext.Receive(118, ExtOpcodes.ToWire("{\"action\":\"cursed\",\"data\":{\"c\":[7,8,\"x\",-1]}}"));
            check(a.Cursed.SetEquals(new uint[] { 7, 8 }), "aura: the cursed monsters");
            check(ChestAuraState.Chests[38758].Px == 64 && ChestAuraState.Chests[38657].Big && ChestAuraState.Chests[38657].Px == 128, "aura: the chests and their strips");
            check(ChestAuraState.FrameIndex(0, 200, 12) == 0 && ChestAuraState.FrameIndex(450, 200, 12) == 2 && ChestAuraState.FrameIndex(2400, 200, 12) == 0, "aura: loop frames");
            check(ChestAuraState.InSquare(new Pos(13, 8, 7), new Pos(10, 10, 7), 3) && !ChestAuraState.InSquare(new Pos(14, 10, 7), new Pos(10, 10, 7), 3) && !ChestAuraState.InSquare(new Pos(10, 10, 6), new Pos(10, 10, 7), 3), "aura: the range square is Chebyshev on one floor");
            check(ChestAuraState.FootPath(2) == "game_chestaura/images/foot/inquisitor_sigil.png" && ChestAuraState.FramePath(3) == "game_chestaura/images/frame/sentinel.png" && ChestAuraState.FootPath(4) == null, "aura: picture paths");
            string dir = FindUp("client/overlay/modules/game_chestaura");
            if (dir == null) { check(true, "aura: module files not found (skipped)"); return; }
            var paths = ChestAuraState.Chests.Values.Select(c => ChestAuraState.ChestPath(c.Art)).Concat(new[] { 1, 2, 3 }.SelectMany(l => new[] { ChestAuraState.FootPath(l), ChestAuraState.FramePath(l) })).ToList();
            string root = Path.GetDirectoryName(dir);
            var missing = paths.Where(p => !File.Exists(Path.Combine(root, p))).ToList();
            check(missing.Count == 0, "aura: every picture is in the module: " + string.Join(", ", missing));
            // the strips have the frame counts of the constants: width = frames * frame size
            foreach (var c in ChestAuraState.Chests.Values)
                check(PngWidth(Path.Combine(root, ChestAuraState.ChestPath(c.Art))) == ChestAuraState.ChestFrames * c.Px, "aura: " + c.Art + " is 12 frames of " + c.Px + " px");
            foreach (int l in new[] { 1, 2, 3 })
                check(PngWidth(Path.Combine(root, ChestAuraState.FootPath(l))) == ChestAuraState.FootFrames * ChestAuraState.FootPx, "aura: foot strip " + l + " is 24 frames of 64 px");
        }

        static int PngWidth(string path)
        {
            var b = File.ReadAllBytes(path);
            return b.Length < 24 ? -1 : b[16] << 24 | b[17] << 16 | b[18] << 8 | b[19];
        }

        // ---------------------------------------------------------------------------------------------------- cosmetic prints and glows
        static void Cosmetic(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var c = new CosmeticFxState(ext);
            var cos = new CosmeticsState(ext);
            ext.Receive(225, ExtOpcodes.ToWire("{\"action\":\"looks\",\"data\":{\"full\":true,\"names\":{\"Ana\":{\"f\":\"ember\",\"o\":\"gold\",\"p\":1},\"Bo\":{\"f\":\"bad name!\"},\"Cy\":{\"o\":\"frost\"}}}}"));
            check(c.Looks.Count == 2 && c.Looks["Ana"].Print == "ember" && c.Looks["Ana"].Pulse && c.Looks["Cy"].Print == null && c.Looks["Cy"].Glow == "frost" && !c.Looks.ContainsKey("Bo"), "cosmetic: the looks of the server, a bad art name is dropped");
            ext.Receive(225, ExtOpcodes.ToWire("{\"action\":\"looks\",\"data\":{\"names\":{\"Ana\":false,\"Di\":{\"f\":\"rime\"}}}}"));
            check(!c.Looks.ContainsKey("Ana") && c.Looks["Cy"] != null && c.Looks["Di"].Print == "rime", "cosmetic: a later message adds and removes");
            ext.Receive(225, ExtOpcodes.ToWire("{\"action\":\"looks\",\"data\":{\"full\":true,\"names\":{}}}"));
            check(c.Looks.Count == 0, "cosmetic: a full list replaces");
            check(CosmeticFxState.ValidArt("ash_2") && !CosmeticFxState.ValidArt("") && !CosmeticFxState.ValidArt("../x") && !CosmeticFxState.ValidArt(new string('a', 25)), "cosmetic: art names");
            check(CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(5, 4, 7)) == 0 && CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(6, 5, 7)) == 90 && CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(5, 6, 7)) == 180 &&
                  CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(4, 5, 7)) == 270 && CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(6, 4, 7)) == 45 && CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(7, 5, 7)) < 0 && CosmeticFxState.StepRotation(new Pos(5, 5, 7), new Pos(5, 5, 6)) < 0, "cosmetic: the turn of a step");
            check(Math.Abs(CosmeticFxState.PrintOpacity(0) - 0.9f) < 1e-5 && CosmeticFxState.PrintOpacity(3200) < 0 && Math.Abs(CosmeticFxState.PrintOpacity(1600) - 0.45f) < 1e-5, "cosmetic: a print fades over 3.2 s");
            check(Math.Abs(CosmeticFxState.PulseOpacity(0) - 0.45f) < 1e-5 && Math.Abs(CosmeticFxState.PulseOpacity(900) - 1f) < 1e-5, "cosmetic: an outline breathes between 45 and 100 percent");
            for (int i = 0; i < 12; i++) c.AddPrint("Ana", "ember", new Pos(i, 0, 7), 0, i);
            check(c.Prints.Count == 8 && c.Prints[0].Pos.X == 4, "cosmetic: 8 prints per walker, the oldest go first");
            for (int i = 0; i < 200; i++) c.AddPrint("W" + i, "ash", new Pos(0, i, 7), 0, 100 + i);
            check(c.Prints.Count == 160, "cosmetic: 160 prints at most");
            c.Tick(100000);
            check(c.Prints.Count == 0, "cosmetic: old prints are swept");
            check(c.Allowed(true, true) && !new CosmeticFxState(ext) { OthersPrints = false }.Allowed(true, false) && new CosmeticFxState(ext) { OthersPrints = false }.Allowed(true, true) && new CosmeticFxState(ext).Allowed(false, false), "cosmetic: the options of others, the own always");
            check(cos != null, "cosmetic: the cosmetics window model still takes the same opcode");
            string dir = FindUp("client/overlay/modules/game_cosmeticfx/images");
            if (dir == null) { check(true, "cosmetic: module files not found (skipped)"); return; }
            check(Directory.GetFiles(Path.Combine(dir, "prints"), "*.png").Length >= 10 && Directory.GetFiles(Path.Combine(dir, "glows"), "*.png").Length >= 10, "cosmetic: the module has its prints and glows");
        }

        // ---------------------------------------------------------------------------------------------------- ground fx, boss looks
        static void GroundAndBoss(Action<bool, string> check)
        {
            check(GroundFx.Ids.Count == 223 && GroundFx.IsGround(8) && GroundFx.IsGround(450) && !GroundFx.IsGround(9) && !GroundFx.IsGround(851), "groundfx: the ids of the table");
            string lua = FindUp("client/overlay/modules/game_groundfx/groundfx_data.lua");
            if (lua != null)
            {
                string body = Regex.Match(File.ReadAllText(lua), @"ids = \{(.*?)\},\s*names", RegexOptions.Singleline).Groups[1].Value;
                var want = new HashSet<int>(Regex.Matches(body, @"\d+").Cast<Match>().Select(x => int.Parse(x.Value)));
                check(want.SetEquals(GroundFx.Ids), "groundfx: the ids are the ones of groundfx_data.lua");
            }
            check(BossAnimate.Animates(1534) && !BossAnimate.Animates(1) && BossAnimate.Phase(0, 4) == 0 && BossAnimate.Phase(280, 4) == 2 && BossAnimate.Phase(560, 4) == 0 && BossAnimate.Phase(500, 1) == 0, "boss: Skaldra beats her wings on a clock");
            BossAnimate.Shift(2127, out int dx, out int dy);
            BossAnimate.Shift(5, out int ex, out int ey);
            check(dx == -28 && dy == -28 && ex == 0 && ey == 0, "boss: Gravewarden Ulthar's art is shifted down and right");
            string ba = FindUp("client/overlay/modules/game_bossanimate/bossanimatelogic.lua");
            if (ba != null)
            {
                string t = File.ReadAllText(ba);
                check(t.Contains("L.LOOKS = { 1534 }") && t.Contains("[2127] = { -28, -28 }"), "boss: the looks are the ones of bossanimatelogic.lua");
            }
            // the live view's idle clip of a boss look
            var look = new ThingType { Id = 1534, Category = ThingCategory.Outfit, Groups = new[] { new FrameGroup { Phases = 4, PatternX = 4, Width = 1, Height = 1, Layers = 1, PatternY = 1, PatternZ = 1 } } };
            BossAnimate.Clock = () => 280;
            FrontOutfit.Group(look, false, 0f, out int phase);
            BossAnimate.Clock = () => Environment.TickCount;
            check(phase == 2, "boss: the front-art view plays the standing look's phases");
            FrontOutfit.Group(new ThingType { Id = 7, Category = ThingCategory.Outfit, Groups = look.Groups }, false, 0f, out phase);
            check(phase == 0, "boss: another look stands still");
        }

        // ---------------------------------------------------------------------------------------------------- flash and shake
        static void Flash(Action<bool, string> check)
        {
            var f = new HitFlasher();
            var p = f.Plan(1000, 7, 23, 0, 12, false);
            check(p != null && !p.Red && p.Ms == 80, "flash: a plain hit flashes white for 80 ms");
            check(f.Plan(1100, 7, 23, 0, 12, false) == null && f.Plan(1200, 7, 23, 1, 12, false) != null, "flash: the same creature not inside 140 ms");
            var crit = f.Plan(2000, 8, 24, 1, 12, true);
            check(crit != null && crit.Red && crit.Ms == 110, "flash: a critical hit on the player is red for 110 ms");
            check(f.Plan(3000, 9, 23, 2, 12, false) == null && f.Plan(3000, 9, 25, 0, 12, false) == null && f.Plan(3000, 0, 23, 0, 12, false) == null && f.Plan(3000, 9, 23, 0, 0, false) == null, "flash: ticks, heals, no creature and zero do not");
            var many = new HitFlasher();
            int n = 0;
            for (uint i = 1; i <= 12; i++) if (many.Plan(100, i, 23, 0, 5, false) != null) n++;
            check(n == 8, "flash: 8 alive at once");
            check(HitFlasher.Strength(1000, 1000, 80) == 1f && HitFlasher.Strength(1040, 1000, 80) == 0.5f && HitFlasher.Strength(1080, 1000, 80) == 0f, "flash: it fades out");
            check(ScreenShake.Amp(0, 100) == 0 && ScreenShake.Amp(0, 1500) == 2 && ScreenShake.Amp(0, 3000) == 3 && ScreenShake.Amp(0, 5000) == 4 && ScreenShake.Amp(1, 300) == 2 && ScreenShake.Amp(1, 299) == 0 && ScreenShake.Amp(0, 0) == 0, "shake: big hits and big crits");
            var s = new ScreenShake();
            check(s.Start(1000, 3) && s.Now(1000) == 3 && !s.Start(1050, 2) && s.Start(1050, 4) && s.Now(1050 + 90) == 2 && s.Now(1300) == 0, "shake: a stronger hit restarts it, it falls off to nothing");
            var late = new ScreenShake();
            late.Start(1000, 3);
            check(!late.Start(1190, 2), "shake: not inside the gap of 300 ms after a start");
            var rnd = new Random(1);
            late.Offset(1010, () => rnd.NextDouble(), out int x, out int y);
            check((x != 0 || y != 0) && Math.Abs(x) <= 3 && Math.Abs(y) <= 3, "shake: every frame moves at least one pixel while it runs");
            late.Offset(5000, () => 0.5, out x, out y);
            check(x == 0 && y == 0 && !late.Running(5000), "shake: and then stops");
            var o = VisualFxOptions.From(Json.TryParse(new VisualFxOptions { HitFlash = false, ScreenShake = false }.ToJson()));
            check(!o.HitFlash && !o.ScreenShake && VisualFxOptions.From(null).HitFlash && o.Get("hitFlash") == false && o.Get("nothing") == false, "flash: the options round trip");
        }

        // ---------------------------------------------------------------------------------------------------- name shaders
        static void Shaders(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>();
            ext.Transmit = pk => sent.Add(Encoding.UTF8.GetString(pk, 4, pk.Length - 4));
            var n = new NameShaderState(ext);
            var notes = new List<string>();
            n.Notified = (name, sel) => notes.Add((sel ? "sel:" : "unl:") + name);
            ext.Receive(96, ExtOpcodes.ToWire("{\"action\":\"update\",\"shaders\":[{\"id\":1,\"name\":\"Ember Flow\",\"available\":true},{\"id\":2,\"name\":\"Frost Veil\",\"available\":false,\"descriptionId\":4}],\"current\":1}"));
            check(n.Shaders.Count == 2 && n.Current == 1 && n.Shaders[0].Available && !n.Shaders[1].Available && n.Shaders[1].DescriptionId == 4, "shaders: the list and the current one");
            ext.Receive(96, ExtOpcodes.ToWire("{\"action\":\"unlocked\",\"id\":2,\"name\":\"Frost Veil\"}"));
            check(n.Find(2).Available && notes.SequenceEqual(new[] { "unl:Frost Veil" }), "shaders: an unlock notice");
            ext.Receive(96, ExtOpcodes.ToWire("{\"action\":\"selected\",\"id\":2,\"name\":\"Frost Veil\"}"));
            check(n.Current == 2 && notes.Count == 2 && notes[1] == "sel:Frost Veil", "shaders: the server confirms a pick");
            ext.Receive(96, ExtOpcodes.ToWire("{\"action\":\"open\"}"));
            check(n.OpenRequested, "shaders: the server opens the window");
            n.Select(1);
            check(sent[sent.Count - 1].Contains("\"action\":\"select\"") && sent[sent.Count - 1].Contains("\"id\":1"), "shaders: select goes to the server");
            check(n.Filter("fro").Count == 1 && n.Filter("").Count == 2 && n.Filter("").All(s => s.Available) && n.Filter("zzz").Count == 0, "shaders: search by name, owned first");
            n.Shaders[0].Available = false;
            check(n.Filter("")[0].Id == 2, "shaders: an owned one is listed before a locked one");
            NameShaderState.Colors("Ember Flow", out uint a1, out uint b1);
            NameShaderState.Colors("ember flow", out uint a2, out uint b2);
            NameShaderState.Colors("Frost Veil", out uint a3, out _);
            check(a1 == a2 && b1 == b2 && a1 != a3, "shaders: a name always has the same colours, case blind");
            check(NameShaderState.At("Ember Flow", 0) == a1 && NameShaderState.At("Ember Flow", 1400) == b1 && NameShaderState.At("Ember Flow", 700) != a1, "shaders: the name swings between its two colours");
        }

        // ---------------------------------------------------------------------------------------------------- layout
        static void Layouts(Action<bool, string> check)
        {
            check(ViewZoom.Clamp(5) == 7 && ViewZoom.Clamp(8) == 9 && ViewZoom.Clamp(13) == 11 && ViewZoom.Step(11, -1) == 9 && ViewZoom.Step(7, -1) == 7 && ViewZoom.Step(11, 1) == 11 && ViewZoom.Step(9, 0) == 9, "view: whole odd rows from 7 to 11");
            check(Math.Abs(ViewZoom.Cols(11) - 15f) < 1e-4 && Math.Abs(ViewZoom.Cols(7) - 7 * 15f / 11f) < 1e-4, "view: the shape of the 15 x 11 view is kept");
            check(ViewZoom.MaxZoomOut(29, 21, 1.5) == 19 && ViewZoom.MaxZoomOut(17, 13, 1.5) == 11 && ViewZoom.MaxZoomOut(1, 13, 1.5) == 3, "view: the furthest zoom out the area allows");
            check(ViewZoom.DefaultZoom(1080, 29) == 15 && ViewZoom.DefaultZoom(540, 29) == 11 && ViewZoom.DefaultZoom(1080, 11) == 11 && ViewZoom.DefaultZoom(800, 29) == 11, "view: about 72 px per tile, 11 to 15 rows");
            // the HUD pieces
            HudLayout.ResetAll();
            float x = 8, y = 8;
            HudLayout.Place("status", ref x, ref y, 248, 92, 960, 540);
            check(x == 8 && y == 8, "hud: an unmoved piece is at its default");
            HudLayout.Drag("status", 8, 8, 248, 92, 960, 540, 100, 50);
            x = 8; y = 8;
            HudLayout.Place("status", ref x, ref y, 248, 92, 960, 540);
            check(x == 108 && y == 58 && HudLayout.Moved("status"), "hud: a drag moves the piece");
            HudLayout.Drag("status", 8, 8, 248, 92, 960, 540, 5000, 5000);
            x = 8; y = 8;
            HudLayout.Place("status", ref x, ref y, 248, 92, 960, 540);
            check(x == 960 - 248 && y == 540 - 92, "hud: a piece stays fully on screen");
            string json = HudLayout.ToJson();
            HudLayout.ResetAll();
            check(!HudLayout.Moved("status"), "hud: reset puts it back");
            HudLayout.Load(json);
            x = 8; y = 8;
            HudLayout.Place("status", ref x, ref y, 248, 92, 960, 540);
            check(x == 712 && y == 448, "hud: the saved place comes back");
            HudLayout.Load("{\"status\":[1e9,2],\"nope\":[1,2],\"chat\":\"x\"}");
            check(!HudLayout.Moved("status") && !HudLayout.Moved("chat") && !HudLayout.Moved("nope"), "hud: junk and unknown pieces are ignored");
            HudLayout.Drag("logout", 864, 8, 88, 30, 960, 540, 0.2f, 0.2f);
            check(!HudLayout.Moved("logout"), "hud: a drag of under a pixel is no move");
            HudLayout.ResetAll();
            check(HudLayout.Key("Ana") == "chaos.hudpos.ana" && HudLayout.Key("") == null, "hud: the key per character");
            // screen fit
            check(ScreenFit.Overflows(700, 540) && !ScreenFit.Overflows(500, 540) && !ScreenFit.Overflows(500, 0), "screenfit: which windows overflow");
            check(ScreenFit.Clamp(50, 700, 0, 540) == 0 && ScreenFit.Clamp(-400, 700, 0, 540) == -160 && ScreenFit.Clamp(-100, 700, 0, 540) == -100, "screenfit: a tall window covers the screen");
            check(ScreenFit.Clamp(-20, 300, 0, 540) == 0 && ScreenFit.Clamp(400, 300, 0, 540) == 240, "screenfit: a window that fits stays inside");
            check(ScreenFit.OpenStart(120, 700, 0, 540) == 0 && ScreenFit.OpenStart(120, 300, 0, 540) == 120, "screenfit: a tall window opens at its title");
            check(ScreenFit.Wheel(0, 700, 0, 540, false) == -48 && ScreenFit.Wheel(-48, 700, 0, 540, true) == 0 && ScreenFit.Wheel(-150, 700, 0, 540, false) == -160 && ScreenFit.Wheel(10, 300, 0, 540, false) == 10, "screenfit: the wheel scrolls 48 px, only inside the limits");
            // fade
            var fade = new UiFade();
            fade.Snap(false);
            fade.Begin(true, 0);
            check(fade.Step(70) && fade.Value > 0.5f && fade.Value < 1f, "fade: in is quick at the start");
            check(!fade.Step(140) && fade.Value == 1f, "fade: in takes 140 ms");
            fade.Begin(false, 1000);
            check(fade.Step(1050) && fade.Value > 0.1f && fade.Value < 0.9f, "fade: out");
            fade.Begin(true, 1050);   // turn round half way: only the time that is left
            float mid = fade.Value;
            check(!fade.Step(1050 + 140) && fade.Value == 1f && mid < 1f, "fade: a turn round starts from where it is");
            fade.Begin(false, 2000);
            check(!fade.Step(2100) && fade.Value == 0f && !fade.Running, "fade: out takes 100 ms");
            check(UiFade.Eligible(true, 300, 200) && !UiFade.Eligible(true, 100, 200) && !UiFade.Eligible(true, 300, 50) && !UiFade.Eligible(false, 300, 200), "fade: small popups do not fade");
            // the saved layout
            var l = new WindowLayout();
            l.Note("MinimapWindow", 10, 20, true);
            l.Note("HuntWindow", 200.4f, 100, false);
            l.Note("", 1, 1, false);
            check(l.Count == 2 && l.Dirty, "layout: windows are noted");
            var back = WindowLayout.From(l.ToJson());
            check(!l.Dirty && back.Count == 2 && back.TryGet("MinimapWindow", out var m) && m.X == 10 && m.Y == 20 && m.Open && back.TryGet("HuntWindow", out m) && m.X == 200 && !m.Open, "layout: round trip");
            back.Note("MinimapWindow", 10.2f, 20.1f, true);
            check(!back.Dirty, "layout: a sub-pixel move is no change");
            back.Note("MinimapWindow", 40, 20, true);
            check(back.Dirty, "layout: a move is");
            check(WindowLayout.From("[1,2]").Count == 0 && WindowLayout.From("{\"A\":[\"x\",1],\"B\":[1e9,1],\"C\":[5,6]}").Count == 1 && WindowLayout.From("nonsense").Count == 0, "layout: junk is skipped");
            check(WindowLayout.Key("Ana") == "chaos.layout.ana", "layout: the key per character");
        }

        // ---------------------------------------------------------------------------------------------------- session
        static void Session(Action<bool, string> check)
        {
            var w = new World(DatFile.Parse(Program.SyntheticDat()));
            var s = new GameSession(w, new GameSession.Options());
            var v = s.Visual;
            check(v != null && v.Wings != null && v.Aura != null && v.Cosmetic != null && v.Names != null, "session: a session holds the visual models");
            var me = new Creature { Id = 1, Name = "Hero", Type = 0 };
            w.Creatures[1] = me; w.PlayerId = 1; w.AddThing(new Pos(100, 100, 7), new Thing { Creature = me });
            var mob = new Creature { Id = 2, Name = "Rat", Type = 1 };
            w.Creatures[2] = mob; w.AddThing(new Pos(101, 100, 7), new Thing { Creature = mob });
            check(w.Fx.Enabled, "session: the feed is on for the models without the live view");
            w.Fx.Push(FxEvent.TypedNumber(23, new Pos(101, 100, 7), 20, 198, 0, 0, "A Rat loses 20 hitpoints due to your attack.", 500, 0, 2));
            check(v.DequeueCue(out var pick) && pick.File.StartsWith("hit_"), "session: your hit is a cue");
            check(v.Flashes.Count == 1 && !v.Flashes[0].Red && v.Flashes[0].Creature == 2, "session: and a white flash on the rat");
            check(v.Decals.Decals.Count == 1 && v.Decals.Decals[0].Kind == "fire" && v.Decals.Decals[0].Pos.X == 101, "session: and a scorch stain by the orange number");
            w.Fx.Push(FxEvent.TypedNumber(24, new Pos(100, 100, 7), 900, 215, 0, 0, "You lose 900 hitpoints.", 4000, 1, 1));
            check(v.Flashes.Count == 2 && v.Flashes[1].Red && v.Flashes[1].Creature == 1, "session: a hit on you flashes red");
            check(v.Shake.Running(s.Now), "session: a big hit shakes the view");
            w.Fx.Push(FxEvent.Effect(new Pos(100, 100, 7), 372));
            check(v.Grounds.Count == 1 && v.Grounds[0].Id == 372, "session: a ground effect id makes a ring");
            w.Fx.Push(FxEvent.Effect(new Pos(100, 100, 7), 9));
            check(v.Grounds.Count == 1, "session: another effect does not");
            // the level-up wings message and its sound
            s.Ext.Receive(191, ExtOpcodes.ToWire("{\"action\":\"play\",\"data\":{\"id\":1,\"lv\":101,\"n\":1}}"));
            bool lvl = false;
            while (v.DequeueCue(out pick)) lvl |= pick.File == "levelup";
            check(lvl && v.Wings.Active.Count == 1, "session: wings play the level up sound");
            // a monster that dies after your hit: a kill sound and a blood stain
            mob.HealthPercent = 0;
            w.Creatures.Remove(2);
            v.Tick(s.Now + 10);
            // the creature was seen on a Tick before it went: the first Tick above only saw it gone, so run the sequence the way the game does
            var mob2 = new Creature { Id = 3, Name = "Wolf", Type = 1 };
            w.Creatures[3] = mob2; w.AddThing(new Pos(102, 100, 7), new Thing { Creature = mob2 });
            w.Fx.Push(FxEvent.TypedNumber(23, new Pos(102, 100, 7), 20, 5, 0, 0, "hit", 500, 0, 3));
            while (v.DequeueCue(out pick)) { }
            v.Tick(s.Now + 20);
            mob2.HealthPercent = 5;
            v.Tick(s.Now + 30);
            w.Creatures.Remove(3);
            v.Tick(s.Now + 40);
            bool kill = false;
            while (v.DequeueCue(out pick)) kill |= pick.File.StartsWith("kill_");
            check(kill && v.Decals.Decals.Any(d => d.Kind == "blood" && d.Pos.X == 102), "session: a creature you hit that dies gives a kill sound and blood");
            // chests in view
            w.AddThing(new Pos(103, 101, 7), new Thing { Item = w.MakeItem(38758, 1) });
            v.Tick(s.Now + 700);
            check(v.Chests.Count == 1 && v.Chests[0].Def.Art == "reward_sigil", "session: a chest with an aura is found in view");
            // the cosmetic print of a step
            s.Ext.Receive(225, ExtOpcodes.ToWire("{\"action\":\"looks\",\"data\":{\"names\":{\"Hero\":{\"f\":\"ember\"}}}}"));
            w.Creatures[1].Position = new Pos(100, 100, 7);
            v.Tick(s.Now + 710);
            me.Position = new Pos(100, 99, 7);
            v.Tick(s.Now + 720);
            check(v.Cosmetic.Prints.Count == 1 && v.Cosmetic.Prints[0].Rotation == 0 && v.Cosmetic.Prints[0].Art == "ember", "session: a step leaves a footprint of the bought art");
            // music follows the world
            check(v.Region == "hunt" || v.Region == "login", "session: the music region starts at hunt");
            v.Clear();
            check(v.Chests.Count == 0 && v.Decals.Decals.Count == 0, "session: clear");
        }

        // ---------------------------------------------------------------------------------------------------- texts
        static void Texts(Action<bool, string> check)
        {
            string root = FindUp("unity/Client/Assets/Chaos");
            if (root == null) { check(true, "visual texts: sources not found (skipped)"); return; }
            var keys = new HashSet<string>();
            var pat = new Regex("Loc\\.T\\(\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
            foreach (string f in new[] { "Unity/ChaosApp.Visual.cs", "Unity/ChaosApp.Audio.cs", "Unity/Windows/VisualWindows.cs" })
                foreach (Match m in pat.Matches(File.ReadAllText(Path.Combine(root, f))))
                    keys.Add(m.Groups[1].Value.Substring(1, m.Groups[1].Value.Length - 2).Replace("\\\"", "\""));
            foreach (string p in VisualOptionsPages) keys.Add(p);
            foreach (string r in new[] { "Town", "Hunt", "Dungeon", "Boss", "Arena", "Login" }) keys.Add(r);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "visual texts: every text has a pt-BR entry; missing: " + string.Join(" | ", missing.Take(8)));
            var bad = LocVisual.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "visual texts: placeholders match: " + string.Join(" | ", bad.Take(5)));
            check(!LocVisual.PtBr.Any(kv => kv.Value.Contains("\u2014") || kv.Value.Contains("\u2013")), "visual texts: no dashes of the long kind in the pt-BR texts");
            Loc.Set("pt-BR");
            check(Loc.T("Region music") == "Música da região" && Loc.T("Now playing: {0}", "Cidade") == "Tocando: Cidade", "visual texts: pt-BR through Loc.T");
            Loc.Set("en");
        }

        static readonly string[] VisualOptionsPages = { "General", "Sound", "Visuals", "Layout" };
    }
}
