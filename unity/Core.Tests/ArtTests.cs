// Art of the main client's modules in the Unity client (O433 phase 6, track U): spell icon cells, buff, toast, orb and monster bar pictures (Core/OverlayArt.cs), and the
// item and rune slots of the hotkey bar (Core/HotbarSlots.cs). The module files are read from client/overlay when the repository is around.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class ArtTests
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

        /// <summary>Width and height from the IHDR chunk of a PNG, false when the file is not one.</summary>
        static bool PngSize(string path, out int w, out int h)
        {
            w = h = 0;
            if (path == null || !File.Exists(path)) return false;
            byte[] b = new byte[24];
            using (var f = File.OpenRead(path)) if (f.Read(b, 0, 24) < 24) return false;
            if (b[0] != 0x89 || b[1] != 'P' || b[2] != 'N' || b[3] != 'G') return false;
            w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
            h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
            return true;
        }

        static string Modules => FindUp("client/overlay/modules");
        static string Data => FindUp("client/overlay/data");

        /// <summary>The file a module-relative art path names ("../data/..." is a data file), null when the repository is not around.</summary>
        static string Resolve(string rel)
        {
            if (rel.StartsWith("../data/", StringComparison.Ordinal)) return Data == null ? null : Path.Combine(Data, rel.Substring(8));
            return Modules == null ? null : Path.Combine(Modules, rel);
        }

        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            Spells(check);
            Buffs(check);
            Toasts(check);
            Orbs(check);
            MonsterBars(check);
            Slots(check);
            Press(check);
            Menu(check);
            Texts(check);
        }

        // ---------------------------------------------------------------------------------------------- spell icons
        static void Spells(Action<bool, string> check)
        {
            check(SpellIcons.Count >= 150, "spell icons: the table has the Chaos spells (" + SpellIcons.Count + ")");
            check(SpellIcons.CellByWords("kah pyr vesh") == 202 && SpellIcons.CellByWords("  KAH PYR VESH ") == 202, "spell icons: Witchfire Bolt is cell 202, words are not case sensitive");
            check(SpellIcons.CellByWords("exura") == 0 && SpellIcons.CellByWords("") == 0 && SpellIcons.CellByWords(null) == 0, "spell icons: a stock spell has no cell");
            check(SpellIcons.CellById(98) == 281 && SpellIcons.CellById(200) == 201 && SpellIcons.CellById(1) == 0, "spell icons: by server id, a remapped spell keeps its own cell");
            check(SpellIcons.Cell("", 203) == 204 && SpellIcons.Cell("kah pyr vesh", 0) == 202 && SpellIcons.Cell("nothing", 0) == 0, "spell icons: the words first, then the id");
            check(SpellIcons.Path(SpellIcons.Sheet32) == "../data/images/game/spells/spell-icons-32x32.png", "spell icons: the sheet path");
            // cell geometry on the real 640 x 608 sheet: 20 columns of 32 px
            float u, v, w, h;
            check(SpellIcons.CellUv(1, 32, 32, 640, 608, out u, out v, out w, out h) && Math.Abs(u) < 1e-6 && Math.Abs(w - 0.05f) < 1e-6 && Math.Abs(h - 32f / 608f) < 1e-6 && Math.Abs(v - (1f - 32f / 608f)) < 1e-6,
                "spell icons: cell 1 is the top left cell (bottom-up texture coordinates)");
            check(SpellIcons.CellUv(22, 32, 32, 640, 608, out u, out v, out w, out h) && Math.Abs(u - 32f / 640f) < 1e-6 && Math.Abs(v - (1f - 64f / 608f)) < 1e-6, "spell icons: cell 22 is column 2, row 2");
            check(SpellIcons.CellUv(380, 32, 32, 640, 608, out u, out v, out w, out h), "spell icons: the last cell of the sheet");
            check(!SpellIcons.CellUv(381, 32, 32, 640, 608, out u, out v, out w, out h) && !SpellIcons.CellUv(0, 32, 32, 640, 608, out u, out v, out w, out h) && !SpellIcons.CellUv(5, 32, 32, 0, 0, out u, out v, out w, out h),
                "spell icons: a cell past the sheet, cell 0 and an empty sheet give nothing");

            // against the module data: spelldata.lua rows are the table, and each cell lies inside all three sheets
            string lua = FindUp("client/overlay/modules/game_chaosspells/spelldata.lua");
            if (lua == null || Data == null) { check(true, "spell icons: repository files not found, skipped"); return; }
            var rows = new List<Tuple<int, string, int>>();
            foreach (string line in File.ReadAllLines(lua))
            {
                var m = Regex.Match(line, "^\\s*\\{ id = (\\d+), name = \"[^\"]+\", words = \"([^\"]+)\"");
                var c = Regex.Match(line, "clientId = (\\d+)");
                if (m.Success && c.Success) rows.Add(Tuple.Create(int.Parse(m.Groups[1].Value), m.Groups[2].Value, int.Parse(c.Groups[1].Value)));
            }
            check(rows.Count == SpellIcons.Count, "spell icons: the table has every spelldata.lua row (" + rows.Count + " and " + SpellIcons.Count + ")");
            check(rows.All(r => SpellIcons.CellByWords(r.Item2) == r.Item3 && SpellIcons.CellById(r.Item1) == r.Item3), "spell icons: every row maps by words and by id to its clientId");
            var dims = new Dictionary<string, int[]> { { SpellIcons.Sheet32, new[] { 32, 32 } }, { SpellIcons.Sheet22, new[] { 22, 24 } }, { SpellIcons.Sheet20, new[] { 20, 20 } } };
            foreach (var kv in dims)
            {
                bool ok = PngSize(Resolve(SpellIcons.Path(kv.Key)), out int sw, out int sh);
                check(ok && rows.All(r => SpellIcons.CellUv(r.Item3, kv.Value[0], kv.Value[1], sw, sh, out _, out _, out _, out _)), "spell icons: every cell lies inside " + kv.Key + " (" + sw + "x" + sh + ")");
            }
        }

        // ---------------------------------------------------------------------------------------------- buff icons
        static void Buffs(Action<bool, string> check)
        {
            check(BuffIcons.OwnName("buff:regen", "x") == "regen", "buff icons: buff:name is that name");
            check(BuffIcons.OwnName("cond:05", "bleeding") == "bleeding" && BuffIcons.OwnName("spell:utani hur", "haste") == "haste", "buff icons: an older spec draws the key's own icon");
            check(BuffIcons.OwnName("", "") == "spellbuff" && BuffIcons.OwnName("buff:../x", "a b") == "spellbuff", "buff icons: no valid name falls back to spellbuff");
            check(BuffIcons.OwnName("buff:ok_1", null) == "ok_1", "buff icons: letters, digits and underscores are names");
            check(BuffIcons.ParseIcon("buff:regen", out var k, out var a) && k == "buff" && a == "regen" && !BuffIcons.ParseIcon("regen", out _, out _) && !BuffIcons.ParseIcon("x:y", out _, out _) && !BuffIcons.ParseIcon("buff:", out _, out _), "buff icons: the spec parser");
            check(BuffIcons.Path("burning") == "../data/images/game/buffs/burning.png", "buff icons: the file path");
            if (Data == null) { check(true, "buff icons: repository files not found, skipped"); return; }
            check(PngSize(Resolve(BuffIcons.Path(BuffIcons.Fallback)), out int w, out int h) && w == BuffIcons.Size && h == BuffIcons.Size, "buff icons: the fallback icon is 26 x 26");
            string dir = Path.Combine(Data, "images/game/buffs");
            var bad = Directory.GetFiles(dir, "*.png").Where(f => !PngSize(f, out int fw, out int fh) || fw != BuffIcons.Size || fh != BuffIcons.Size).Select(Path.GetFileName).ToList();
            check(bad.Count == 0, "buff icons: every icon file is 26 x 26 (" + string.Join(",", bad) + ")");
        }

        // ---------------------------------------------------------------------------------------------- toast icons
        static void Toasts(Action<bool, string> check)
        {
            check(ToastIcons.Path("TASK_COMPLETE") == "game_chaosnotify/images/toast/task.png" && ToastIcons.Path("SALE") == ToastIcons.Path("MARKET"), "toast icons: paths of the notification types");
            check(ToastIcons.Path("ACHIEVEMENT") == "../data/images/chaos/topbutton_ranking.png", "toast icons: the achievement uses the top bar picture");
            check(ToastIcons.Path("NOPE") == "game_chaosnotify/images/toast/announce.png" && ToastIcons.Path(null) == ToastIcons.Path("GM_BROADCAST"), "toast icons: an unknown type gets the announcement icon");
            check(ToastKinds.Styles.Keys.All(t => ToastIcons.Files.ContainsKey(t)), "toast icons: every toast type of the HUD has an icon row");
            string lua = FindUp("client/overlay/modules/game_chaosnotify/notifications.lua");
            if (lua == null || Modules == null) { check(true, "toast icons: repository files not found, skipped"); return; }
            string text = File.ReadAllText(lua);
            foreach (var kv in ToastIcons.Files)
            {
                // the Lua table of the type names the same icon
                var m = Regex.Match(text, "\\n    " + kv.Key + " = \\{\\s*icon = \"([^\"]+)\"");
                string want = m.Success ? m.Groups[1].Value : null;
                if (kv.Value == null) check(want == "/images/chaos/topbutton_ranking", "toast icons: " + kv.Key + " is the top bar picture in the module (" + want + ")");
                else check(want == kv.Value, "toast icons: " + kv.Key + " icon matches notifications.lua (" + want + " / " + kv.Value + ")");
                string file = Resolve(ToastIcons.Path(kv.Key));
                int want2 = kv.Key == "ACHIEVEMENT" ? 64 : ToastIcons.Size;
                check(PngSize(file, out int w, out int h) && w == want2 && h == want2, "toast icons: " + kv.Key + " file is " + want2 + " px square");
            }
        }

        // ---------------------------------------------------------------------------------------------- orbs
        static void Orbs(Action<bool, string> check)
        {
            check(OrbArt.Liquid(76) == 50 && OrbArt.Liquid(150) == 99 && OrbArt.Liquid(190) == 125, "orbs: the liquid keeps the ring opening (50, 99, 125)");
            check(OrbArt.NearestSize(60) == 76 && OrbArt.NearestSize(96) == 76 && OrbArt.NearestSize(120) == 150 && OrbArt.NearestSize(300) == 190, "orbs: the nearest art size of a diameter");
            check(OrbArt.RingFile(150) == "game_shaderfx/images/orb_ring_150.png" && OrbArt.MaskFile(150) == "game_shaderfx/images/orb_mask_99.png", "orbs: ring and mask file names");
            check(OrbArt.Fill(50, 100) == 0.5 && OrbArt.Fill(5, 0) == 0 && OrbArt.Fill(-3, 10) == 0 && OrbArt.Fill(200, 100) == 1, "orbs: fill from value and maximum");
            OrbArt.PlainClip(0.5, 100, 50, out int clip, out int drawn);
            check(clip == 50 && drawn == 25, "orbs: half full clips half the mask");
            OrbArt.PlainClip(0, 100, 50, out clip, out drawn);
            check(clip == 0 && drawn == 0, "orbs: empty draws nothing");
            OrbArt.PlainClip(1.7, 100, 50, out clip, out drawn);
            check(clip == 100 && drawn == 50, "orbs: over full is full");
            check(OrbArt.Short(950) == "950" && OrbArt.Short(1234) == "1.2k" && OrbArt.Short(20000) == "20k" && OrbArt.Short(1500000) == "1.5m" && OrbArt.Short(-4) == "0", "orbs: the number in the globe");
            if (Modules == null) { check(true, "orbs: repository files not found, skipped"); return; }
            foreach (int s in OrbArt.Sizes)
            {
                check(PngSize(Resolve(OrbArt.RingFile(s)), out int rw, out int rh) && rw == 2 * s && rh == 2 * s, "orbs: ring " + s + " is " + 2 * s + " px (2x)");
                int l = OrbArt.Liquid(s);
                check(PngSize(Resolve(OrbArt.MaskFile(s)), out int mw, out int mh) && mw == 2 * l && mh == 2 * l, "orbs: mask " + l + " is " + 2 * l + " px (2x)");
            }
            string lua = FindUp("client/overlay/modules/game_shaderfx/shaderfxlogic.lua");
            string text = lua == null ? "" : File.ReadAllText(lua);
            check(text.Contains("health = '" + OrbArt.HealthColor + "'") && text.Contains("mana = '" + OrbArt.ManaColor + "'"), "orbs: the colours are those of shaderfxlogic.lua");
            check(Regex.Matches(text, "size = (\\d+)").Cast<Match>().Select(m => int.Parse(m.Groups[1].Value)).SequenceEqual(OrbArt.Sizes), "orbs: the sizes are those of shaderfxlogic.lua");
        }

        // ---------------------------------------------------------------------------------------------- monster bar
        static void MonsterBars(Action<bool, string> check)
        {
            check(MonsterBarArt.Frame("rare") == "../data/images/chaos/monsterbar/frame_rare.png" && MonsterBarArt.Fill("nope") == "../data/images/chaos/monsterbar/fill_normal.png" && MonsterBarArt.Plaque(null).EndsWith("plaque_normal.png"), "monster bar: art names by style key, unknown is normal");
            check(MonsterBarArt.ModKey("Blazing") == "blazing" && MonsterBarArt.ModKey("Iron-Hide") == "unknown" && MonsterBarArt.ModKey(null) == "unknown", "monster bar: modifier chip keys");
            check(MonsterBarArt.PlateWidth(10, 120, 300) == 120 && MonsterBarArt.PlateWidth(100, 120, 300) == 128 && MonsterBarArt.PlateWidth(900, 120, 300) == 300, "monster bar: a plate is its text plus the borders between min and max");
            check(MonsterBarArt.ChipsWidth(0) == 0 && MonsterBarArt.ChipsWidth(1) == 26 && MonsterBarArt.ChipsWidth(3) == 84, "monster bar: the width of the chip row");
            if (Data == null) { check(true, "monster bar: repository files not found, skipped"); return; }
            foreach (string key in MonsterBar.Styles.Keys)
            {
                check(PngSize(Resolve(MonsterBarArt.Frame(key)), out int fw, out int fh) && fw == MonsterBarArt.PanelW && fh == MonsterBarArt.FrameH, "monster bar: frame " + key + " is 420 x 58");
                check(PngSize(Resolve(MonsterBarArt.Fill(key)), out int sw, out int sh) && sw == MonsterBarArt.SocketW && sh == MonsterBarArt.SocketH, "monster bar: fill " + key + " is 344 x 16");
                check(PngSize(Resolve(MonsterBarArt.Plaque(key)), out int pw, out int ph) && pw > 2 * MonsterBarArt.PlateBorderX && ph == MonsterBarArt.PlateH, "monster bar: plaque " + key + " is 22 high");
            }
            check(PngSize(Resolve(MonsterBarArt.Trail), out int tw, out int th) && tw == MonsterBarArt.SocketW && th == MonsterBarArt.SocketH, "monster bar: the trail is 344 x 16");
            var noChip = MonsterBar.Mods.Keys.Concat(new[] { "unknown" }).Where(m => !File.Exists(Resolve(MonsterBarArt.Chip(m)))).ToList();
            check(noChip.Count == 0, "monster bar: every modifier has a chip picture (" + string.Join(",", noChip) + ")");
            // geometry against the module's otui
            string otui = FindUp("client/overlay/modules/game_monsterbar/monsterbar.otui");
            string o = otui == null ? "" : File.ReadAllText(otui);
            check(o.Contains("size: 420 90") && o.Contains("margin-left: 38") && o.Contains("margin-top: 38") && o.Contains("size: 344 16") && o.Contains("size: 420 58"), "monster bar: the panel and socket numbers are those of monsterbar.otui");
            check(o.Contains("margin-top: 63") && o.Contains("size: 26 26") && o.Contains("spacing: 3") && o.Contains("image-border-left: 10") && o.Contains("image-border-top: 6"), "monster bar: chips and plate borders are those of monsterbar.otui");
        }

        // ---------------------------------------------------------------------------------------------- hotbar slots
        static void Slots(Action<bool, string> check)
        {
            var empty = HotbarModel.Parse("");
            check(empty.Kind == HotKind.Empty && HotbarModel.Parse("   ").Kind == HotKind.Empty && HotbarModel.Parse(null).Kind == HotKind.Empty, "hotbar: an empty string is an empty slot");
            var text = HotbarModel.Parse("exura vita");
            check(text.Kind == HotKind.Text && text.Text == "exura vita" && HotbarModel.Encode(text) == "exura vita", "hotbar: a saved line from an older client is a text slot");
            var item = HotbarModel.Parse("item:3160:3");
            check(item.Kind == HotKind.Item && item.ItemId == 3160 && item.Mode == ItemMode.WithCrosshair && HotbarModel.Encode(item) == "item:3160:3", "hotbar: an item slot round-trips");
            check(HotbarModel.Parse("item:3160").Mode == ItemMode.Use && HotbarModel.Parse("item:3160:9").Mode == ItemMode.Use && HotbarModel.Parse("item:3160:x").Kind == HotKind.Item, "hotbar: a missing or bad mode is Use");
            check(HotbarModel.Parse("item:0:1").Kind == HotKind.Text && HotbarModel.Parse("item:70000:1").Kind == HotKind.Text && HotbarModel.Parse("item:abc").Kind == HotKind.Text && HotbarModel.Parse("item:-4:1").Kind == HotKind.Text, "hotbar: a bad item id is plain text");

            var bar = new HotbarModel();
            var saved = new[] { "exura", "", "item:2268:3", "item:2874:1", "hello world" };
            bar.Load(i => i < saved.Length ? saved[i] : "");
            check(bar[0].Kind == HotKind.Text && bar[1].IsEmpty && bar[2].ItemId == 2268 && bar[3].Mode == ItemMode.OnSelf && bar[4].Text == "hello world" && bar[11].IsEmpty && bar[-1].IsEmpty && bar[12].IsEmpty, "hotbar: load reads every slot");
            check(bar.FirstEmpty() == 1, "hotbar: the first empty slot");
            check(bar.SetItem(1, 3160, true) && bar[1].Mode == ItemMode.WithCrosshair && bar.SetItem(5, 3003, false) && bar[5].Mode == ItemMode.Use, "hotbar: a multi-use item starts a use with, other items are used");
            check(!bar.SetItem(-1, 5, false) && !bar.SetItem(14, 5, false) && !bar.SetItem(6, 0, false) && !bar.SetItem(6, 65536, false) && bar[6].IsEmpty, "hotbar: bad slot or item id changes nothing");
            check(bar.SetMode(5, ItemMode.OnTarget) && bar[5].Mode == ItemMode.OnTarget && !bar.SetMode(0, ItemMode.OnSelf) && bar[0].Kind == HotKind.Text, "hotbar: a mode only applies to an item slot");
            bar.SetText(5, "utani hur");
            check(bar[5].Kind == HotKind.Text && bar[5].ItemId == 0 && bar.Saved(5) == "utani hur", "hotbar: a line over an item replaces it");
            bar.SetText(6, "item:2268:3");
            check(bar[6].Kind == HotKind.Text && bar[6].Text == "item:2268:3", "hotbar: typed text never becomes an item slot");
            bar.SetText(6, "");
            check(bar[6].IsEmpty && bar.Saved(6) == "", "hotbar: an empty line clears the slot");
            bar.ClearSlot(2);
            check(bar[2].IsEmpty && bar.Saved(2) == "", "hotbar: remove clears a slot");
            for (int i = 0; i < HotbarModel.Count; i++) bar.SetItem(i, 100 + i, false);
            check(bar.FirstEmpty() == -1, "hotbar: a full bar has no empty slot");
            check(HotbarModel.Modes.Length == 4 && HotbarModel.ModeLabel(ItemMode.OnSelf) == "Use on yourself" && HotbarModel.ModeLabel(ItemMode.WithCrosshair) == "Use with ..." && HotbarModel.ModeMark(ItemMode.Use) == "" && HotbarModel.ModeMark(ItemMode.OnTarget) == "T",
                "hotbar: mode labels and marks");
            // the saved text of every slot parses back to the same slot
            var again = new HotbarModel();
            again.Load(i => bar.Saved(i));
            bool same = true;
            for (int i = 0; i < HotbarModel.Count; i++) same &= again[i].Kind == bar[i].Kind && again[i].ItemId == bar[i].ItemId && again[i].Mode == bar[i].Mode;
            check(same, "hotbar: save then load gives the same bar");
        }

        sealed class FakeHost : IHotbarHost
        {
            public Dictionary<int, int> Have = new Dictionary<int, int>();
            public uint Target, Self = 77;
            public List<string> Log = new List<string>();
            public bool CrosshairOk = true;
            public int CountItem(int id) => Have.TryGetValue(id, out int n) ? n : 0;
            public bool UseItem(int id) { Log.Add("use " + id); return true; }
            public bool UseOnCreature(int id, uint cr) { Log.Add("on " + id + " " + cr); return true; }
            public bool StartCrosshair(int id) { Log.Add("cross " + id); return CrosshairOk; }
            public uint AttackTarget => Target;
            public uint SelfId => Self;
            public void Say(string text) { Log.Add("say " + text); }
        }

        static void Press(Action<bool, string> check)
        {
            var bar = new HotbarModel();
            var host = new FakeHost();
            host.Have[3160] = 40; host.Have[2874] = 3; host.Have[3003] = 1;
            bar.SetText(0, "exura vita");
            bar.SetItem(1, 3160, true);                     // a rune: crosshair
            bar.SetItem(2, 2874, false); bar.SetMode(2, ItemMode.OnSelf);
            bar.SetItem(3, 3003, false);                    // the rope: plain use
            bar.SetItem(4, 3160, true); bar.SetMode(4, ItemMode.OnTarget);
            bar.SetItem(5, 9999, false);                    // not carried
            check(bar.Press(6, host) == HotOutcome.None && bar.Press(0, null) == HotOutcome.None && host.Log.Count == 0, "press: an empty slot and a missing host do nothing");
            check(bar.Press(0, host) == HotOutcome.Said && host.Log.Last() == "say exura vita", "press: a line is said");
            check(bar.Press(1, host) == HotOutcome.Crosshair && host.Log.Last() == "cross 3160", "press: a rune starts the crosshair");
            check(bar.Press(2, host) == HotOutcome.UsedOnSelf && host.Log.Last() == "on 2874 77", "press: on yourself uses it on your own creature id");
            check(bar.Press(3, host) == HotOutcome.Used && host.Log.Last() == "use 3003", "press: a plain item is used");
            int before = host.Log.Count;
            check(bar.Press(4, host) == HotOutcome.NoTarget && host.Log.Count == before, "press: on target needs a monster you attack, else nothing is sent");
            host.Target = 4242;
            check(bar.Press(4, host) == HotOutcome.UsedOnTarget && host.Log.Last() == "on 3160 4242", "press: on target uses it on the attacked monster");
            before = host.Log.Count;
            check(bar.Press(5, host) == HotOutcome.NotCarried && host.Log.Count == before, "press: an item you do not carry sends nothing");
            host.Have[3160] = 0;
            check(bar.Press(1, host) == HotOutcome.NotCarried, "press: a used-up rune is not carried");
            host.Have[3160] = 5; host.CrosshairOk = false;
            check(bar.Press(1, host) == HotOutcome.NotCarried, "press: a crosshair that cannot start reports not carried");
            host.Self = 0; host.Have[2874] = 1;
            check(bar.Press(2, host) == HotOutcome.NotCarried, "press: on yourself needs your creature id");
        }

        // ---------------------------------------------------------------------------------------------- item menu
        static void Menu(Action<bool, string> check)
        {
            Func<ItemRef, string> acts = r => string.Join(",", ItemMenu.Build(r, new ItemMenuContext()).Select(e => e.Separator ? "|" : e.Action.ToString()));
            Func<int, Action<ThingType>, Item> it = (id, f) => { var t = new ThingType { Id = id }; f?.Invoke(t); return new Item { Id = id, Type = t }; };
            var inBag = new ItemRef(new Pos(0xFFFF, 0x41, 1), 1, it(3160, t => { t.Pickupable = true; t.MultiUse = true; }));
            check(acts(inBag).Contains("AddToHotbar"), "menu: an item in a bag can be added to the hotbar (" + acts(inBag) + ")");
            var worn = new ItemRef(GameSession.InventoryPos(6), 6, it(3160, t => t.Pickupable = true));
            check(!acts(worn).Contains("AddToHotbar"), "menu: a worn item is not offered the hotbar");
            var onMap = new ItemRef(new Pos(100, 100, 7), 2, it(3160, t => t.Pickupable = true));
            check(!acts(onMap).Contains("AddToHotbar"), "menu: a map item is not offered the hotbar");
            var bagItem = new ItemRef(new Pos(0xFFFF, 0x41, 2), 2, it(2854, t => { t.Pickupable = true; t.Container = true; }));
            check(!acts(bagItem).Contains("AddToHotbar"), "menu: a bag is opened, not put on the hotbar");
            Loc.Set("pt-BR");
            check(ItemMenu.Build(inBag, new ItemMenuContext()).Any(e => e.Action == ItemAction.AddToHotbar && e.Label == "Adicionar à barra"), "menu: Add to hotbar in pt-BR");
            Loc.Set("en");
        }

        // ---------------------------------------------------------------------------------------------- texts
        static void Texts(Action<bool, string> check)
        {
            Loc.Set("pt-BR");
            var texts = new List<string>
            {
                "Add to hotbar", "Remove from hotbar", "That item is not in your equipment or an open bag.", "Attack a monster first.", "Added to hotbar slot F{0}.",
                "The hotbar is full.", "Drop an item on a slot to keep it there.", "Health and mana globes",
            };
            texts.AddRange(HotbarModel.Modes.Select(HotbarModel.ModeLabel));
            var missing = texts.Where(t => Loc.T(t) == t).ToList();
            check(missing.Count == 0, "texts: every hotbar text has pt-BR (" + string.Join(" | ", missing) + ")");
            check(Loc.T("Added to hotbar slot F{0}.", 3) == "Adicionado ao espaço F3 da barra.", "texts: placeholders keep their index");
            check(LocPhase6U.PtBr.All(kv => Regex.Matches(kv.Key, "\\{\\d+\\}").Count == Regex.Matches(kv.Value, "\\{\\d+\\}").Count), "texts: pt-BR keeps the placeholders of the English text");
            Loc.Set("en");
        }
    }
}
