// Phase 7 track Y (P1 systems): loot filter rule sounds, the rarity outline of map items, the monster bar's world side, bitmap fonts of the damage numbers,
// toast art, store look icons, the Paragon panel, another character's tree, the ground label tooltip and accent.
using System;
using System.Collections.Generic;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Phase7YTests
    {
        static object J(string json) => Json.TryParse(json);

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            RuleSoundChecks(check);
            OutlineChecks(check);
            MonsterChecks(check);
            FontChecks(check);
            PlateChecks(check);
            ToastChecks(check);
            StoreLookChecks(check);
            ParagonChecks(check);
            ViewOtherChecks(check);
            GroundChecks(check);
            Loc.Set("en");
        }

        static void RuleSoundChecks(Action<bool, string> check)
        {
            var snd = new LootSoundSettings();   // unique 5 (Fanfare), power 1 (Chime), the rest none, volume 70
            string file, rule; float gain;
            var hits = new Dictionary<string, int> { { "unique", 1 }, { "power", 2 } };
            check(LootRuleSounds.Pick(hits, snd, out file, out gain, out rule) && file == "game_lootfilter/sounds/fanfare.ogg" && rule == "unique" && Math.Abs(gain - 0.7f) < 0.001f, "rule sound: the first rule that matched wins, at the volume: " + file);
            hits = new Dictionary<string, int> { { "power", 1 }, { "orb", 3 } };
            check(LootRuleSounds.Pick(hits, snd, out file, out gain, out rule) && file == "game_lootfilter/sounds/chime.ogg" && rule == "power", "rule sound: power plays the chime");
            hits = new Dictionary<string, int> { { "orb", 3 }, { "rarity", 1 } };
            check(!LootRuleSounds.Pick(hits, snd, out file, out gain, out rule) && file == null, "rule sound: matching rules without a sound stay silent");
            snd.Rules["orb"] = 3;
            check(LootRuleSounds.Pick(hits, snd, out file, out gain, out rule) && file.EndsWith("ping.ogg", StringComparison.Ordinal) && rule == "orb", "rule sound: a rule given a sound plays it");
            snd.Mute = true;
            check(!LootRuleSounds.Pick(hits, snd, out file, out gain, out rule), "rule sound: mute");
            snd.Mute = false; snd.Volume = 0;
            check(!LootRuleSounds.Pick(hits, snd, out file, out gain, out rule), "rule sound: volume 0");
            snd.Volume = 100;
            check(LootRuleSounds.Pick(hits, snd, out file, out gain, out rule) && gain == 1f, "rule sound: full volume is gain 1");
            check(LootRuleSounds.File(0) == null && LootRuleSounds.File(6) == null && LootRuleSounds.File(2) == "game_lootfilter/sounds/bell.ogg" && LootRuleSounds.File(4) == "game_lootfilter/sounds/drum.ogg", "rule sound: files of the five sounds");
            check(!LootRuleSounds.Pick(null, snd, out file, out gain, out rule) && !LootRuleSounds.Pick(hits, null, out file, out gain, out rule), "rule sound: nothing without hits or settings");

            // the model: a kill message picks the sound and marks the kill alerted
            var ext = new ExtOpcodes();
            ext.Transmit = p => { };
            var f = new LootFilterModel(ext) { Clock = () => 0 };
            ext.Receive(238, "{\"action\":\"settings\",\"data\":{\"s\":{},\"snd\":{\"rules\":{\"unique\":5,\"power\":1,\"rarity\":0,\"tier\":0,\"orb\":0},\"vol\":50,\"mute\":false,\"hunt\":true}}}");
            ext.Receive(238, "{\"action\":\"kill\",\"data\":{\"k\":7,\"m\":\"rat\",\"items\":[{\"id\":1,\"nm\":\"sword\",\"c\":1}],\"hits\":{\"power\":1}}}");
            check(f.SoundPending && f.SoundFile.EndsWith("chime.ogg", StringComparison.Ordinal) && Math.Abs(f.SoundGain - 0.5f) < 0.001f && f.AlertedKill == 7, "rule sound: a kill with a hit queues the sound and alerts the kill");
            f.SoundPending = false;
            var rows = LootHuntRows.Rows(f);
            check(rows.Count == 5 && rows[0].Key == "unique" && rows[0].Text == "Filter rule: Uniques" && rows[1].Session == 0, "hunt rows: every rule while the option is on: " + rows.Count);
            ext.Receive(238, "{\"action\":\"settings\",\"data\":{\"s\":{},\"counts\":{\"session\":{\"unique\":3},\"total\":{\"unique\":1234}},\"snd\":{\"hunt\":false}}}");
            check(LootHuntRows.Rows(f).Count == 0, "hunt rows: none when the option is off");
            ext.Receive(238, "{\"action\":\"settings\",\"data\":{\"s\":{},\"counts\":{\"session\":{\"unique\":3},\"total\":{\"unique\":1234}},\"snd\":{\"hunt\":true}}}");
            rows = LootHuntRows.Rows(f);
            check(rows[0].Session == 3 && rows[0].Total == 1234 && rows[0].Tip == "Since login: 3   Total: 1,234" && LootHuntRows.Rows(null).Count == 0, "hunt rows: the counters: " + rows[0].Tip);
            ext.Receive(238, "{\"action\":\"kill\",\"data\":{\"k\":8,\"m\":\"rat\",\"items\":[{\"id\":1,\"nm\":\"sword\",\"c\":1}],\"hits\":{}}}");
            check(!f.SoundPending && f.AlertedKill == 7, "rule sound: a kill without a hit queues nothing");
        }

        static void OutlineChecks(Action<bool, string> check)
        {
            var ty = new ThingType();
            Func<int, bool, Item> it = (r, u) =>
            {
                var a = new Dictionary<ushort, ulong>();
                if (r > 0) a[ItemAttr.Rarity] = (ulong)r;
                if (u) a[ItemAttr.Unique] = 1;
                return new Item { Id = 3264, Count = 1, Type = ty, Attrs = a };
            };
            check(MapItemOutline.Color(it(0, false)) == null && MapItemOutline.Color(it(1, false)) == null, "map outline: no rarity and Common get none");
            check(MapItemOutline.Color(it(2, false)) == "#5ccf5c" && MapItemOutline.Color(it(3, false)) == "#4a90ff" && MapItemOutline.Color(it(4, false)) == "#a35cf0", "map outline: the rarity colours");
            check(MapItemOutline.Color(it(5, false)) == "#ffd040" && MapItemOutline.Color(it(8, false)) == "#ffd040" && MapItemOutline.Color(it(10, false)) == "#c8e8ff", "map outline: Legendary, an old Legendary id and Divine");
            check(MapItemOutline.Color(it(1, true)) == ItemRarity.UniqueColor && MapItemOutline.Color(it(0, true)) == ItemRarity.UniqueColor, "map outline: a unique item has the unique colour first");
            check(MapItemOutline.Color(null) == null && MapItemOutline.Color(new Item { Id = 1, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Rarity, 4 } } }) == null, "map outline: no item or no type, none");
            check(MapItemOutline.Alpha(it(3, false), 0) == 0.85f && MapItemOutline.Alpha(it(3, false), 99999) == 0.85f, "map outline: up to Rare the outline is steady");
            float lo = 9, hi = 0;
            for (int t = 0; t < 6000; t += 50) { float a = MapItemOutline.Alpha(it(5, false), t); lo = Math.Min(lo, a); hi = Math.Max(hi, a); }
            check(lo >= 0.59f && hi <= 1.01f && hi - lo > 0.3f, "map outline: Legendary pulses between 0.6 and 1: " + lo + " " + hi);
            check(MapItemOutline.Offsets.Length == 4, "map outline: four offsets");
        }

        static void MonsterChecks(Action<bool, string> check)
        {
            check(MonsterWorld.DrawScale(60, 60, null, null) == 1f && MonsterWorld.DrawScale(96, 68, null, null) == 1f, "monster scale: a body that fits keeps its size");
            check(MonsterWorld.DrawScale(111, 111, null, null) == 0.61f, "monster scale: a 111 px look is shrunk to fit: " + MonsterWorld.DrawScale(111, 111, null, null));
            check(MonsterWorld.DrawScale(200, 200, null, null) == 0.5f, "monster scale: never below the floor");
            check(MonsterWorld.DrawScale(150, 60, null, null) == 0.64f, "monster scale: a wide body is fitted by its width: " + MonsterWorld.DrawScale(150, 60, null, null));
            check(MonsterWorld.DrawScale(111, 111, "boss", null) == 1.5f && MonsterWorld.DrawScale(20, 20, "boss", null) == 1.5f && MonsterWorld.DrawScale(20, 20, null, "omen") == 1.5f, "monster scale: a boss and an omen guardian are bigger");
            check(MonsterWorld.DrawScale(111, 111, null, "guardian") == 1f, "monster scale: a rift guardian keeps its art");
            check(MonsterWorld.DrawScale(0, 0, null, null) == 1f, "monster scale: an unknown body keeps its size");
            var box = BodyBox.None;
            check(box.Empty && box.Width == 0, "body box: starts empty");
            var sprite = new byte[32 * 32 * 4];
            for (int y = 10; y < 20; y++) for (int x = 4; x < 9; x++) sprite[(y * 32 + x) * 4 + 3] = 255;
            sprite[(0 * 32 + 31) * 4 + 3] = 8;   // a faint pixel is not body
            box.Add(sprite, 32, 32, 0, 0);
            box.Add(sprite, 32, 32, 32, 32);
            check(!box.Empty && box.MinX == 4 && box.MaxX == 40 && box.MinY == 10 && box.MaxY == 51 && box.Width == 37 && box.Height == 42, "body box: opaque pixels of every sprite at its place: " + box.Width + "x" + box.Height);
            check(!MonsterWorld.IsOversized(box) && MonsterWorld.IsOversized(new BodyBox { MinX = 0, MinY = 0, MaxX = 130, MaxY = 110 }), "monster scale: oversized by the box");

            var lines = MonsterWorld.ModLines(new List<string> { "blazing", "swift", "brutal" });
            check(lines.Count == 2 && lines[0] == "Blazing - Swift" && lines[1] == "Brutal", "monster labels: two modifiers to a line");
            check(MonsterWorld.ModLines(null).Count == 0 && MonsterWorld.ModLines(new List<string>()).Count == 0, "monster labels: none without modifiers");
            check(MonsterWorld.NameColor(new MonsterInfo { Tier = "rare" }) == "#f6cf72" && MonsterWorld.NameColor(new MonsterInfo { Tier = "magic" }) == "#7fb0ff", "monster labels: tier colours");
            check(MonsterWorld.NameColor(new MonsterInfo { Tier = "normal" }) == null && MonsterWorld.NameColor(null) == null, "monster labels: a plain monster keeps its colour");
            check(MonsterWorld.NameColor(new MonsterInfo { Tier = "rare", Role = "guardian" }) == "#ff6a50", "monster labels: a role's colour wins");
            check(MonsterWorld.TierWord(new MonsterInfo { Tier = "legendary" }) == "Legendary" && MonsterWorld.TierWord(new MonsterInfo { Tier = "rare", Label = "Frenzied" }) == "Frenzied", "monster labels: the tier word, the server's label first");
            check(MonsterWorld.TierWord(new MonsterInfo { Tier = "rare", Role = "omen", Label = "Frenzied" }) == "Omen Guardian" && MonsterWorld.TierWord(new MonsterInfo { Tier = "normal" }) == "", "monster labels: a role's tag wins, a plain tier has none");
        }

        static BitmapFont Font(out int sw, out int sh)
        {
            const int sheetW = 16, sheetH = 12;   // four glyphs a row, glyph 32 and up: 32..35 in row 0, 36..39 in row 1
            sw = sheetW; sh = sheetH;
            var f = BitmapFont.ParseDef("// a comment\nFont\n  name: test-font\n  texture: test-font\n  height: 6\n  glyph-size: 4 6\n  first-glyph: 32\n  y-offset: 1\n  spacing: -1 1\n  space-width: 3\n");
            var rgba = new byte[sheetW * sheetH * 4];
            Action<int, int, int, int> dot = (glyph, gx, gy, v) =>
            {
                int cols = sheetW / 4, cx = ((glyph - 32) % cols) * 4, cy = ((glyph - 32) / cols) * 6;
                int i = ((cy + gy) * sheetW + cx + gx) * 4;
                rgba[i] = (byte)v; rgba[i + 1] = (byte)v; rgba[i + 2] = (byte)v; rgba[i + 3] = 255;
            };
            for (int y = 0; y < 6; y++) dot('!', 0, y, 200);   // '!' (33): a bar one pixel wide
            for (int y = 0; y < 6; y++) { dot('"', 0, y, 255); dot('"', 2, y, 255); }   // '"' (34): two bars, three wide
            f.SetSheet(rgba, sheetW, sheetH);
            return f;
        }

        static void FontChecks(Action<bool, string> check)
        {
            int sw, sh;
            var f = Font(out sw, out sh);
            check(f != null && f.Name == "test-font" && f.CellW == 4 && f.CellH == 6 && f.FirstGlyph == 32 && f.YOffset == 1 && f.SpacingX == -1 && f.SpacingY == 1 && f.SpaceWidth == 3, "font: the definition is read");
            check(f.Ready, "font: ready after the sheet");
            check(f.GlyphWidth('!') == 1 && f.GlyphWidth('"') == 3 && f.GlyphWidth(' ') == 3, "font: a glyph is as wide as its last opaque column, a space has the space width");
            check(f.Measure("!") == 1 && f.Measure("!!") == 1 && f.Measure("\"\"") == 5 && f.Measure("") == 0, "font: the width of a text is its glyphs and the spacing between: " + f.Measure("!!") + " " + f.Measure("\"\""));
            int w, h;
            var px = f.Render("\"", 1f, 0.5f, 0f, out w, out h);
            check(w == 3 && h == 6 && px.Length == 3 * 6 * 4, "font: the picture is the text wide and a cell high");
            // rows bottom first: the bar pixel of the sheet's top row ends in the last picture row; the tint multiplies the colour, the alpha stays
            int top = ((6 - 1) * 3 + 0) * 4;
            check(px[top] == 255 && px[top + 1] == 128 && px[top + 2] == 0 && px[top + 3] == 255, "font: colour times tint, rows bottom first: " + px[top] + "," + px[top + 1] + "," + px[top + 2]);
            check(px[(0 * 3 + 1) * 4 + 3] == 0, "font: the gap between the bars is clear");
            check(BitmapFont.ParseDef("Font\n  name: x\n") == null && BitmapFont.ParseDef(null) == null, "font: a definition without a glyph size is none");
            var other = BitmapFont.ParseDef("Font\n  glyph-size: 4 6\n");
            other.SetSheet(new byte[10], 16, 12);
            check(!other.Ready, "font: a sheet too small is refused");
            check(ScatterFonts.FontFor(ImpactType.Critical) == "chaos-display-16px" && ScatterFonts.FontFor(ImpactType.Condition) == "chaos-outline-11px", "scatter fonts: critical and condition have a font");
            check(ScatterFonts.FontFor(ImpactType.Normal) == null && ScatterFonts.FontFor(ImpactType.ManaDrain) == null && ScatterFonts.FontFor(9) == null, "scatter fonts: the others keep the stock number");
            check(ScatterFonts.DefPath("chaos-display-16px") == "../data/fonts/chaos/chaos-display-16px.otfont" && ScatterFonts.SheetPath("chaos-display-16px") == "../data/fonts/chaos/chaos-display-16px.png", "scatter fonts: the files of the data folder");
            check(ScatterFonts.SizeFactor(ImpactType.Critical) == ImpactType.CritSize && ScatterFonts.SizeFactor(ImpactType.Condition) == ImpactType.ConditionSize && ScatterFonts.SizeFactor(0) == 1f, "scatter fonts: the typed size of the stock number is taken out");
        }

        static void PlateChecks(Action<bool, string> check)
        {
            var r = TooltipPlates.Place(100, 50, 300, 200, 1280, 720, 2, i => 180 + i * 10);
            check(r.Count == 2 && r[0].x == 406 && r[1].x == 712 && r[0].y == 50 && r[0].height == 180 && r[1].height == 190, "plates: two to the right of the main one when they fit: " + r[0].x + " " + r[1].x);
            r = TooltipPlates.Place(900, 50, 300, 200, 1280, 720, 2, null);
            check(r[0].x == 594 && r[1].x == 288, "plates: to the left when the right has no room: " + r[0].x + " " + r[1].x);
            r = TooltipPlates.Place(100, 600, 300, 200, 1280, 720, 1, i => 200);
            check(r[0].y == 516, "plates: moved up to stay on screen: " + r[0].y);
            r = TooltipPlates.Place(200, 10, 300, 100, 700, 720, 3, null);
            check(r.Count == 3 && r[0].x >= 4 && r[2].x + 300 <= 696, "plates: always inside the screen");
            check(TooltipPlates.Place(0, 0, 300, 100, 1000, 700, 0, null).Count == 0, "plates: none to place");
        }

        static void ToastChecks(Action<bool, string> check)
        {
            check(ToastArt.ClipY(ToastArt.ButtonState.Normal) == 0 && ToastArt.ClipY(ToastArt.ButtonState.Hover) == 24 && ToastArt.ClipY(ToastArt.ButtonState.Pressed) == 48 && ToastArt.ClipY(ToastArt.ButtonState.Disabled) == 72, "toast art: the four states of the strip");
            check(ToastArt.StateOf(true, false, false) == ToastArt.ButtonState.Normal && ToastArt.StateOf(true, true, false) == ToastArt.ButtonState.Hover && ToastArt.StateOf(true, true, true) == ToastArt.ButtonState.Pressed && ToastArt.StateOf(false, true, true) == ToastArt.ButtonState.Disabled, "toast art: the state of a button");
            check(ToastArt.LabelColor(ToastArt.ButtonState.Hover) == "#fff3cf" && ToastArt.LabelColor(ToastArt.ButtonState.Disabled) == "#7d7176" && ToastArt.LabelColor(ToastArt.ButtonState.Normal) == "#e9dcc0", "toast art: label colours");
            check(ToastArt.HasMonsterLook(new Toast { MonsterLook = 12 }) && !ToastArt.HasMonsterLook(new Toast()) && !ToastArt.HasMonsterLook(null), "toast art: a monster look only when the server sent one");
            var ext = new ExtOpcodes();
            var tc = new ToastCenter(ext) { Clock = () => 0 };
            ext.Receive(79, "{\"action\":\"taskComplete\",\"taskName\":\"Rats\",\"taskPoints\":5,\"killCount\":100,\"monsterLookType\":21}");
            check(tc.Active.Count + tc.Queue.Count == 1 && ToastArt.HasMonsterLook(tc.Active.Count > 0 ? tc.Active[0] : tc.Queue[0]), "toast art: a task toast keeps its monster look");
            check(ToastArt.Plate == "game_chaosnotify/images/Background.png" && ToastArt.AcceptStrip.EndsWith("toast/accept.png", StringComparison.Ordinal), "toast art: the files of the module");
        }

        static void StoreLookChecks(Action<bool, string> check)
        {
            var p = StoreLookIcon.Plan(J("{\"kind\":\"footprint\",\"art\":\"ember\"}"));
            check(p.Mode == StoreLookIcon.Image && p.Path == "game_cosmeticfx/images/prints/ember.png" && !p.Fixed, "store look: a footprint is its print");
            p = StoreLookIcon.Plan(J("{\"kind\":\"nameplate\",\"frame\":\"amber\"}"));
            check(p.Mode == StoreLookIcon.Image && p.Path == "game_nameplate/images/plate_amber.png" && p.Fixed, "store look: a plate frame keeps its ratio");
            p = StoreLookIcon.Plan(J("{\"kind\":\"swatch\",\"color\":\"#ff8800\"}"));
            check(p.Mode == StoreLookIcon.Swatch && p.Color == "#ff8800" && !p.Accent && StoreLookIcon.SampleText(p) == "Aa", "store look: a chat colour is a sample");
            p = StoreLookIcon.Plan(J("{\"kind\":\"swatch\",\"color\":\"#0a1632f0\",\"accent\":true}"));
            check(p.Mode == StoreLookIcon.Swatch && p.Accent && StoreLookIcon.SampleText(p) == "", "store look: a loot label accent is a bar");
            check(StoreLookIcon.Plan(J("{\"kind\":\"footprint\",\"art\":\"../evil\"}")).Mode == StoreLookIcon.Native, "store look: a bad art name is refused");
            check(StoreLookIcon.Plan(J("{\"kind\":\"swatch\",\"color\":\"url(x)\"}")).Mode == StoreLookIcon.Native, "store look: a bad colour is refused");
            check(StoreLookIcon.Plan(J("{\"kind\":\"outfit\",\"look\":5}")).Mode == StoreLookIcon.Native && StoreLookIcon.Plan(null).Mode == StoreLookIcon.Native, "store look: a creature look keeps the native icon");
            var o = StoreOffer.From(J("{\"type\":\"item\",\"title\":\"Fire print\",\"cost\":10,\"look\":{\"kind\":\"footprint\",\"art\":\"frost\"}}"), 1, 1, 1);
            check(o.LookIcon.Mode == StoreLookIcon.Image && o.LookIcon.Path.EndsWith("frost.png", StringComparison.Ordinal), "store look: an offer reads its look");
        }

        const string ParagonJson = "{\"unlocked\":true,\"level\":1010,\"startLevel\":1000,\"total\":10,\"spent\":2,\"free\":8,\"resetCost\":252500,"
            + "\"categories\":[{\"key\":\"off\",\"name\":\"Offence\",\"stats\":[{\"key\":\"dmg\",\"name\":\"Damage\",\"desc\":\"More damage.\",\"perPoint\":0.25,\"maxPoints\":20,\"points\":2},"
            + "{\"key\":\"spd\",\"name\":\"Speed\",\"perPoint\":0.5,\"maxPoints\":3,\"points\":0}]}]}";

        static void ParagonChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var tree = new PassiveTree(ext);
            var pg = tree.Paragon;
            check(!pg.Known, "paragon: unknown before the server answers");
            pg.Request();
            check(sent.Count == 1 && sent[0].Contains("paragonRequest"), "paragon: the request");
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":" + ParagonJson + "}");
            check(pg.Known && pg.Unlocked && pg.Total == 10 && pg.Spent == 2 && pg.Free() == 8 && pg.Categories.Count == 1 && pg.Categories[0].Stats.Count == 2 && pg.ResetCost == 252500, "paragon: the state is read through the tree's opcode");
            var dmg = pg.Categories[0].Stats[0]; var spd = pg.Categories[0].Stats[1];
            check(pg.Add(spd, 5) == 3 && pg.Free() == 5 && pg.PointsOf(spd) == 3 && !pg.CanAdd(spd), "paragon: adds are limited by the room of the stat");
            check(pg.Add(dmg, 99) == 5 && pg.Free() == 0 && !pg.CanAdd(dmg), "paragon: adds are limited by the free points");
            check(pg.Remove(dmg, 2) == 2 && pg.Free() == 2 && pg.PointsOf(dmg) == 5 && pg.CanRemove(dmg), "paragon: pending points come back");
            check(pg.Remove(dmg, 99) == 3 && !pg.CanRemove(dmg) && pg.PointsOf(dmg) == 2, "paragon: applied points do not come back");
            var alloc = pg.Alloc();
            check(alloc.Count == 1 && alloc.ContainsKey("spd") && (int)alloc["spd"] == 3, "paragon: the allocation holds the absolute points of the changed stats");
            sent.Clear();
            check(pg.Apply() && sent.Count == 1 && sent[0].Contains("paragonApply") && sent[0].Contains("\"spd\":3"), "paragon: Apply sends paragonApply");
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":" + ParagonJson.Replace("\"spent\":2", "\"spent\":5").Replace("\"free\":8", "\"free\":5") + "}");
            check(pg.PendingSum() == 0 && pg.Free() == 5, "paragon: a new state clears the pending points");
            check(!pg.Apply(), "paragon: nothing pending, nothing sent");
            sent.Clear();
            check(pg.Reset() && sent.Count == 1 && sent[0].Contains("paragonReset"), "paragon: Reset");
            check(ParagonPanel.Fmt(0.25) == "0.25" && ParagonPanel.Fmt(1.5) == "1.5" && ParagonPanel.Fmt(20) == "20" && ParagonPanel.Fmt(0.1) == "0.1", "paragon: numbers without trailing zeros");
            check(ParagonPanel.ValueText(dmg, 2) == "+0.5% / 5%" && ParagonPanel.ValueText(dmg, 99) == "+5% / 5%", "paragon: the value text is capped");
            check(ParagonPanel.Tip(dmg).StartsWith("More damage.\n+0.25% per point, up to +5% (20 points).", StringComparison.Ordinal), "paragon: the stat tip: " + ParagonPanel.Tip(dmg));
            check(pg.Summary() == "Available: 5     Spent: 5     Total: 10", "paragon: the summary: " + pg.Summary());
            pg.Add(spd, 1);
            check(pg.Summary().Contains("Spent: 6 (+1)"), "paragon: the summary shows the pending points");
            check(pg.ResetAsk == "Refund all 5 Paragon points for 252,500 gold coins? Proceed?", "paragon: the reset question: " + pg.ResetAsk);
            var lines = pg.BonusLines();
            check(lines.Count == 1 && lines[0] == "+0.5% Damage (Paragon).", "paragon: the applied bonuses");
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":{\"unlocked\":false,\"level\":300,\"startLevel\":1000,\"categories\":[]}}");
            check(!pg.Unlocked && pg.Summary() == "Level 300" && pg.LockedTitle == "Unlocks at level 1000" && !pg.CanAdd(dmg), "paragon: locked below the start level");
        }

        static void ViewOtherChecks(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            var tree = new PassiveTree(ext);
            tree.Data = new TreeData();
            ext.Receive(65, "{\"action\":\"sendNodes\",\"data\":{\"nodes\":[1,2,3],\"masteries\":[{\"id\":9,\"choice\":2}],\"preset\":1,\"presetsTable\":[{\"name\":\"a\"}],\"cls\":\"warrior\",\"line\":\"warrior\",\"vocation\":\"knight\"}}");
            check(tree.Allocated.Count == 3 && tree.Cls == "warrior" && tree.Viewing == null, "view other: the own tree");
            check(!tree.ShowOther(null) && !tree.ShowOther(J("{\"name\":\"x\"}")) && tree.Viewing == null, "view other: a packet without nodes is refused");
            check(tree.ShowOther(J("{\"name\":\"Mia\",\"nodes\":[1,5,6,7],\"masteries\":[{\"id\":12,\"choice\":1}],\"cls\":\"ranger\",\"line\":\"ranger\",\"vocation\":\"paladin\",\"spent\":3,\"total\":40}")), "view other: a tree opens");
            check(tree.Viewing != null && tree.Viewing.Name == "Mia" && tree.Viewing.Count == 4 && tree.Viewing.Spent == 3 && tree.Viewing.Total == 40, "view other: the banner data");
            check(tree.Viewing.Banner == "Mia: 4 passive nodes (read-only)", "view other: the banner: " + tree.Viewing.Banner);
            check(tree.Allocated.Count == 4 && tree.Allocated.Contains(7) && tree.Cls == "ranger" && tree.Vocation == "paladin" && tree.Masteries.ContainsKey(12) && !tree.Masteries.ContainsKey(9), "view other: the allocation, class and masteries shown are the other character's");
            sent.Clear();
            tree.RefundNode(5); tree.ResetTree(); tree.ChangeSavedMastery(12, 1); tree.Apply(); tree.ApplyBuild(); tree.PreviewBuild("PT1.abc");
            check(sent.Count == 0, "view other: nothing is sent while another tree shows");
            check(tree.ClickNode(5) == PassiveTree.Click.None, "view other: a click plans nothing");
            tree.CloseOther();
            check(tree.Viewing == null && tree.Allocated.Count == 3 && tree.Allocated.Contains(2) && tree.Cls == "warrior" && tree.Vocation == "knight" && tree.Masteries.ContainsKey(9), "view other: back to the own tree");
            tree.ShowOther(J("{\"name\":\"Mia\",\"nodes\":[1],\"cls\":\"ranger\"}"));
            ext.Receive(65, "{\"action\":\"sendNodes\",\"data\":{\"nodes\":[1,2],\"preset\":1,\"presetsTable\":[],\"cls\":\"warrior\"}}");
            check(tree.Viewing == null && tree.Allocated.Count == 2 && tree.Cls == "warrior", "view other: a sync of the own tree ends the view");
            check(new TreeViewing { Name = "Al", Count = 1 }.Banner == "Al: 1 passive node (read-only)", "view other: one node");
        }

        static void GroundChecks(Action<bool, string> check)
        {
            // the accent cosmetic: only the background of highlighted labels
            var hi = new GroundDecision { Highlight = true };
            string text, border, bg;
            GroundLabelRules.Style(hi, "#ff0000", out text, out border, out bg, "#0a1632f0");
            check(bg == "#0a1632f0" && border == "#ff0000" && text == "#ff0000", "ground labels: the accent sits behind a highlighted label, the rarity colour stays");
            GroundLabelRules.Style(hi, "#ff0000", out text, out border, out bg);
            check(bg == GroundLabelRules.HighlightBackground, "ground labels: no accent, the default background");
            GroundLabelRules.Style(new GroundDecision(), "#ff0000", out text, out border, out bg, "#0a1632f0");
            check(bg == GroundLabelRules.PlainBackground, "ground labels: a plain label ignores the accent");

            var ext = new ExtOpcodes();
            var sent = new List<string>(); ext.Transmit = p => sent.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            double now = 0;
            var gm = new GroundLabelsModel(ext) { Clock = () => now };
            var label = new GroundLabel { Tile = new Pos(101, 100, 7), Row = new GroundRow { Info = new LootInfo { S = 2, Id = 3264, C = 1, Nm = "fire sword", R = 4 } } };
            check(GroundLabelsModel.TipKey(label) == "gl:101,100,7:2:3264:1", "ground tip: the cache key: " + GroundLabelsModel.TipKey(label));
            check(gm.Tip(label) == null && sent.Count == 1 && sent[0].Contains("\"tip\"") && sent[0].Contains("[101,100,7]") && sent[0].Contains("\"s\":2") && sent[0].Contains("\"id\":3264"), "ground tip: the first hover asks the server");
            check(gm.Tip(label) == null && sent.Count == 1, "ground tip: not asked again within the retry time");
            now = 4;
            check(gm.Tip(label) == null && sent.Count == 2, "ground tip: asked again after the retry time");
            ext.Receive(230, "{\"action\":\"tip\",\"data\":{\"p\":[101,100,7],\"s\":2,\"id\":3264,\"tip\":{\"name\":\"Fire Sword\",\"rarity\":4}}}");
            var tip = gm.Tip(label);
            check(tip != null && Json.Text(tip, "name") == "Fire Sword" && sent.Count == 2, "ground tip: the answer is cached, no more questions");
            var other = new GroundLabel { Tile = new Pos(101, 100, 7), Row = new GroundRow { Info = new LootInfo { S = 3, Id = 3264, C = 1 } } };
            check(gm.Tip(other) == null, "ground tip: another stack index is another item");
            ext.Receive(230, "{\"action\":\"tip\",\"data\":{\"p\":[101,100,7],\"s\":3,\"id\":3264,\"gone\":1}}");
            check(gm.Tip(other) == null && gm.Tip(other) == null, "ground tip: a gone answer caches nothing");
            var corpse = new GroundLabel { Tile = new Pos(1, 1, 7), Row = new GroundRow { Corpse = true, Items = 3, Info = new LootInfo { S = 1, Id = 5 } } };
            sent.Clear();
            check(gm.Tip(corpse) == null && sent.Count == 0, "ground tip: a corpse has no tip to ask");
            var row = new GroundRow { Corpse = true, Items = 4 };
            row.Inside.Add(new LootInfo { Nm = "fire axe", R = 5, C = 1 });
            row.Inside.Add(new LootInfo { Nm = "gold coin", C = 40 });
            var lines = GroundLabelsModel.CorpseTip(row);
            check(lines[0] == "[Legendary] Fire Axe" && lines[1] == "40x Gold Coin" && lines[2] == "... and 2 more" && lines[3] == "Click: open the corpse", "ground tip: the corpse's items, the rest and the hint: " + string.Join(" | ", lines));
            gm.Reset();
            check(gm.Tip(label) == null, "ground tip: Reset forgets the cache");
        }
    }
}
