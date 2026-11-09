// Phase 8 track A: the hotbar frame and its key labels, the Equip mode, the painted icons option, toast pause and phone filter, rarity rings and scene draw size, top menu icons
// and the Admin button, the helper's preset key, the store's look preview try-on, the item tooltip card, the vocation trials, the auto build, the Paragon masteries,
// node icons, node frames and curved links of the passive tree.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

namespace Chaos.Core.Tests
{
    static class Phase8ATests
    {
        public static void Run(Action<bool, string> check)
        {
            Loc.Set("en");
            HotbarChecks(check);
            PaintedChecks(check);
            ToastChecks(check);
            SceneChecks(check);
            TopbarChecks(check);
            HelperChecks(check);
            StoreChecks(check);
            CardChecks(check);
            TrialChecks(check);
            AutoBuildChecks(check);
            MasteryChecks(check);
            TreeArtChecks(check);
            TextChecks(check);
            Loc.Set("en");
        }

        static string Find(params string[] parts)
        {
            string dir = Directory.GetCurrentDirectory();
            for (int i = 0; i < 8 && dir != null; i++)
            {
                string p = Path.Combine(new[] { dir }.Concat(parts).ToArray());
                if (File.Exists(p) || Directory.Exists(p)) return p;
                dir = Path.GetDirectoryName(dir);
            }
            return null;
        }

        static ExtOpcodes Ext(out List<string> sent)
        {
            var ext = new ExtOpcodes();
            var list = new List<string>();
            ext.Transmit = p => list.Add(Encoding.UTF8.GetString(p, 4, p.Length - 4));
            sent = list;
            return ext;
        }

        // ------------------------------------------------------------------------------------ hotbar
        sealed class EqHost : IHotbarEquipHost
        {
            public HashSet<int> Worn = new HashSet<int>();
            public HashSet<int> Bag = new HashSet<int>();
            public List<string> Log = new List<string>();
            public int CountItem(int id) => (Worn.Contains(id) ? 1 : 0) + (Bag.Contains(id) ? 1 : 0);
            public bool IsWorn(int id) => Worn.Contains(id);
            public bool UseItem(int id) { Log.Add("use " + id); return true; }
            public bool UseOnCreature(int id, uint c) => true;
            public bool StartCrosshair(int id) => true;
            public uint AttackTarget => 0;
            public uint SelfId => 1;
            public void Say(string t) { }
        }

        static void HotbarChecks(Action<bool, string> check)
        {
            // the key label: tall enough for its font, whatever the skin pads (the Q and E read as O and F in a 14 px box)
            var k = HotbarFrame.KeyLabel(100, 20, 34, 10);
            check(k.H >= 16 && k.X == 102 && k.Y == 20 && k.W == 32, "hotbar: the key label is 16 high for a 10 px font, never the old 14: " + k.H);
            check(HotbarFrame.KeyLabel(0, 0, 34, 14).H >= 22, "hotbar: a bigger font gets a taller label");
            check(HotbarFrame.KeyLabel(0, 0, 4, 10).W >= 10, "hotbar: a tiny slot keeps a usable label width");
            check(HotbarLayout.KeyLabel(HotbarModel.SideQ) == "Q" && HotbarLayout.KeyLabel(HotbarModel.SideE) == "E" && HotbarLayout.KeyLabel(0) == "1", "hotbar: the key labels of the sockets and the row");
            // the frame geometry of hotbar_logic.lua: the base button is 36 of the 44 pixel frame
            var f = HotbarFrame.SlotFrameOf(10, 10, 36, 36);
            check(f.X == 6 && f.Y == 6 && f.W == 44 && f.H == 44, "hotbar: the slot frame is the 36 px slot grown to 44");
            var f2 = HotbarFrame.SlotFrameOf(0, 0, 27, 30);
            check(Math.Abs(f2.W - 33) < 1e-9 && f2.X < 0, "hotbar: the frame follows the scale");
            var body = HotbarFrame.BodyOf(4, 4, 300, 40, 5);
            check(body.X == -1 && body.Y == -1 && body.W == 310 && body.H == 50, "hotbar: the iron body surrounds the row");
            var box = HotbarFrame.KeyBox(0, 0, 34, "F12");
            check(box.W <= 34 && box.H == 14, "hotbar: the key box fits the slot");
            var full = new HotSlot { Kind = HotKind.Text, Text = "exura" };
            check(HotbarFrame.Ready(full, 0, false) && !HotbarFrame.Ready(full, 3, false) && !HotbarFrame.Ready(default(HotSlot), 0, false) && !HotbarFrame.Ready(full, 0, true), "hotbar: ready frame: filled, off cooldown, in the row");
            check(HotbarFrame.FramePath(true, true) == HotbarFrame.Socket && HotbarFrame.FramePath(false, true) == HotbarFrame.SlotReady && HotbarFrame.FramePath(false, false) == HotbarFrame.Slot, "hotbar: the frame pictures");
            // the art files, when the client folder is next to the tests
            string dir = Find("client", "overlay", "modules", "game_hotbar", "images");
            if (dir != null)
                foreach (string rel in new[] { HotbarFrame.Body, HotbarFrame.Slot, HotbarFrame.SlotReady, HotbarFrame.Socket, HotbarFrame.Key, HotbarFrame.Gem })
                    check(File.Exists(Path.Combine(dir, "..", "..", rel.Replace('/', Path.DirectorySeparatorChar))), "hotbar: picture " + rel + " exists");

            // the Equip mode
            var bar = new HotbarModel();
            check(HotbarModel.Parse("item:3160:4").Mode == ItemMode.Equip && HotbarModel.Parse("item:3160:5").Mode == ItemMode.Use, "equip: the saved mode 4 parses, 5 falls back to Use");
            check(HotbarModel.Modes.Contains(ItemMode.Equip) && HotbarModel.ModeLabel(ItemMode.Equip) == "Equip" && HotbarModel.ModeMark(ItemMode.Equip) == "=", "equip: label and mark");
            check(HotbarModel.Encode(new HotSlot { Kind = HotKind.Item, ItemId = 3160, Mode = ItemMode.Equip, Text = "" }).EndsWith(":4", StringComparison.Ordinal), "equip: the mode is saved");
            bar.Load(i => i == 0 ? "item:3360:4" : "");
            var host = new EqHost();
            check(bar.Press(0, host) == HotOutcome.NotCarried, "equip: not carried");
            host.Bag.Add(3360);
            check(bar.Press(0, host) == HotOutcome.Used && host.Log.Count == 1, "equip: an item in a bag is used, the server equips it");
            host.Bag.Clear(); host.Worn.Add(3360); host.Log.Clear();
            check(bar.Press(0, host) == HotOutcome.AlreadyWorn && host.Log.Count == 0, "equip: a worn item is left alone");
        }

        // ------------------------------------------------------------------------------------ painted icons
        static void PaintedChecks(Action<bool, string> check)
        {
            check(PaintedIcons.SpellPath(201) == "../data/images/game/spells_painted/201.png" && PaintedIcons.SpellPath(0) == null, "painted: the spell path by cell");
            check(PaintedIcons.BuffPath("regen") == "../data/images/game/buffs_painted/regen.png" && PaintedIcons.BuffPath("../x") == null && PaintedIcons.BuffPath(null) == null, "painted: the buff path, no path tricks");
            check(PaintedIcons.NodePath == "../data/images/passivetree/painted_nodes.png", "painted: the node sheet");
            Func<string, bool> has = p => p == "a.png";
            check(PaintedIcons.Choose(true, "a.png", has, "n.png") == "a.png" && PaintedIcons.Choose(false, "a.png", has, "n.png") == "n.png" && PaintedIcons.Choose(true, "b.png", has, "n.png") == "n.png", "painted: off or missing keeps the normal icon");
            check(PaintedIcons.NodeKey("ksA", "ksB", false, k => true) == "ksB" && PaintedIcons.NodeKey("ksA", "ksB", true, k => true) == "ksA" && PaintedIcons.NodeKey("ksA", "x", false, k => false) == "ksA", "painted: a class variant's key wins, never on a start node");
            string spells = Find("client", "overlay", "data", "images", "game", "spells_painted");
            if (spells != null) check(File.Exists(Path.Combine(spells, "201.png")), "painted: the spell icon files are in the client folder");
            check(!VisualPrefsDefault(), "painted: off by default");
        }

        static bool VisualPrefsDefault() => false;

        // ------------------------------------------------------------------------------------ toasts
        static void ToastChecks(Action<bool, string> check)
        {
            var tc = new ToastCenter(null) { Clock = () => 1000 };
            var t = tc.Add("SALE", "sold");
            check(t != null && tc.Active.Count == 1 && t.EndAt == 13000, "toast: a sale shows for 12 s");
            ToastPause.Press(t, 5000);
            tc.Tick(30000);
            check(tc.Active.Count == 1 && ToastPause.Left(t, 30000) == 8000 && Math.Abs(ToastPause.Fraction(t, 30000) - 8000.0 / 12000.0) < 1e-9, "toast: a pressed toast stops its timer");
            check(ToastPause.Resume(t, 20000) && t.PausedAt < 0 && t.StartAt == 16000, "toast: the pause time is added back when released");
            tc.Tick(27000);
            check(tc.Active.Count == 1, "toast: still there before the new end");
            tc.Tick(28000);
            check(tc.Active.Count == 0, "toast: gone at the new end");
            check(!ToastPause.Resume(t, 1), "toast: nothing to resume when running");
            ToastCenter.Phone = true;
            var tp = new ToastCenter(null) { Clock = () => 0 };
            check(tp.Add("SALE", "x") == null && tp.Active.Count == 0 && tp.Queue.Count == 0, "toast: a phone drops a sale");
            var inv = tp.Add("PARTY_INVITE", "x");
            check(inv != null && tp.Active.Count == 1, "toast: a phone keeps an invitation");
            ToastCenter.Phone = false;
            check(ToastPause.Shown("SALE", false) && ToastPause.Shown("CATACOMB_FREE", true) && !ToastPause.Shown("BOUNTY", true), "toast: the phone filter");
        }

        // ------------------------------------------------------------------------------------ scene views
        static void SceneChecks(Action<bool, string> check)
        {
            var ty = new ThingType();
            Func<int, bool, Item> it = (r, u) =>
            {
                var a = new Dictionary<ushort, ulong>();
                if (r > 0) a[ItemAttr.Rarity] = (ulong)r;
                if (u) a[ItemAttr.Unique] = 1;
                return new Item { Id = 3264, Count = 1, Type = ty, Attrs = a };
            };
            var things = new List<Thing> { new Thing { Item = it(0, false) }, new Thing { Item = it(3, false) }, new Thing { Item = it(5, false) }, new Thing { Creature = new Creature() } };
            check(RarityGlow.Best(things) == things[2].Item, "ring: the rarest item of a pile gives the colour");
            check(RarityGlow.Best(new List<Thing> { new Thing { Item = it(1, false) } }) == null, "ring: common items get none");
            check(RarityGlow.Best(new List<Thing> { new Thing { Item = it(5, false) }, new Thing { Item = it(2, true) } }).Attrs.ContainsKey(ItemAttr.Unique), "ring: a unique outranks a legendary");
            check(RarityGlow.RingColor(it(4, false)) == "#a35cf0", "ring: the classic outline colour");
            check(RarityGlow.Shimmer(it(10, false), 0) == 0.5f && RarityGlow.Shimmer(it(5, false), 100) == 0f && RarityGlow.Shimmer(it(10, true), 100) == 0f, "ring: only Divine shimmers");
            check(Math.Abs(RarityGlow.Alpha(it(2, false), 0) - 0.85f) < 1e-6 && RarityGlow.Alpha(it(5, false), 0) >= 0.6f, "ring: the pulse of the classic outline");
            var rr = RarityGlow.Ring(100, 100, 32);
            check(rr.W > rr.H && Math.Abs(rr.X + rr.W / 2 - 100) < 1e-9, "ring: wider than high, centred on the tile");

            float x = 3, y = 0, z = 0;
            SceneScale.About(ref x, ref y, ref z, 1, 0, 0, 1.5f);
            check(Math.Abs(x - 4) < 1e-6 && y == 0 && z == 0, "scale: a point is scaled about the feet");
            float x2 = 5, y2 = 2, z2 = 1;
            SceneScale.About(ref x2, ref y2, ref z2, 5, 0, 1, 1f);
            check(x2 == 5 && y2 == 2 && z2 == 1, "scale: 1 changes nothing");
            var mon = new Creature { Type = 1 }; var npc = new Creature { Type = 2 };
            check(SceneScale.For(mon, c => 1.5f) == 1.5f && SceneScale.For(npc, c => 1.5f) == 1f && SceneScale.For(mon, null) == 1f && SceneScale.For(mon, c => 0.1f) == MonsterWorld.ScaleMin && SceneScale.For(null, c => 2f) == 1f, "scale: only monsters, within limits");
            check(SceneScale.Head(2f, 1.5f) == 3f, "scale: the head moves with it");
        }

        // ------------------------------------------------------------------------------------ top menu
        static void TopbarChecks(Action<bool, string> check)
        {
            check(TopMenuIcons.Of("Skills") == "skills" && TopMenuIcons.Of("Passive Tree") == "passivetree" && TopMenuIcons.Of("Logout") == "logout" && TopMenuIcons.Of("Nope") == null, "topbar: icons by entry text");
            check(TopMenuIcons.OfCategory("hunt") == "battlelist" && TopMenuIcons.OfCategory("admin") == "admin" && TopMenuIcons.OfCategory("windows") == null, "topbar: icons by category");
            check(TopMenuIcons.Path("skills") == "../data/images/chaos/small/topbutton_skills.png" && TopMenuIcons.Path("skills", true).EndsWith("skills_hover.png", StringComparison.Ordinal), "topbar: the icon files");
            // every entry of the menu that has a Unity window has an icon or is a separator
            var noIcon = new List<string>();
            foreach (var c in TopMenu.Categories)
                foreach (var e in TopMenu.Leaves(c)) if (!e.Separator && e.Text.Length > 0 && TopMenuIcons.Of(e.Text) == null) noIcon.Add(e.Text);
            check(noIcon.Count == 0, "topbar: every menu entry has an icon: " + string.Join(", ", noIcon));
            string dir = Find("client", "overlay", "data", "images", "chaos", "small");
            if (dir != null)
                foreach (string n in TopMenuIcons.Names()) check(File.Exists(Path.Combine(dir, "topbutton_" + n + ".png")), "topbar: icon file " + n);
            int cats = TopMenu.Categories.Length;
            check(TopMenuAdmin.ButtonCount(cats, false) == cats + 1 && TopMenuAdmin.ButtonCount(cats, true) == cats + 2 && TopMenuAdmin.Index(cats, true) == cats + 1 && TopMenuAdmin.Index(cats, false) == -1, "topbar: the Admin button only for staff, after Windows");
        }

        // ------------------------------------------------------------------------------------ helper preset key
        static void HelperChecks(Action<bool, string> check)
        {
            check(HelperPresetKey.Valid("G") && HelperPresetKey.Valid("Alpha5") && HelperPresetKey.Valid("Keypad1") && HelperPresetKey.Valid("Insert"), "preset key: letters, digits, keypad and insert can bind");
            check(!HelperPresetKey.Valid("W") && !HelperPresetKey.Valid("Q") && !HelperPresetKey.Valid("E") && !HelperPresetKey.Valid("F3") && !HelperPresetKey.Valid("Escape") && !HelperPresetKey.Valid("LeftShift") && !HelperPresetKey.Valid("Mouse0") && !HelperPresetKey.Valid("") && !HelperPresetKey.Valid(null), "preset key: movement, hotbar, F keys and modifiers are refused");
            check(HelperPresetKey.PrefKey("Ann Lee") == "chaos.helper.presetkey.ann lee" && HelperPresetKey.Label("") == "None" && HelperPresetKey.Label("G") == "G", "preset key: per character, labelled");
            var cfg = new HelperConfig();
            string first = cfg.SelectedProfile;
            check(HelperPresetKey.Cycle(cfg) != null || HelperProfiles.Names(cfg).Count == 1, "preset key: one preset cycles to itself");
            check(cfg.AddProfile("Boss", false) == null && cfg.AddProfile("Aoe", false) == null, "preset key: two more presets");
            var names = HelperProfiles.Names(cfg);
            cfg.SelectProfile(names[0]);
            var seen = new List<string>();
            for (int i = 0; i < names.Count; i++) { string msg = HelperPresetKey.Cycle(cfg); seen.Add(cfg.SelectedProfile); check(msg == "Preset: " + cfg.SelectedProfile, "preset key: tells the new preset: " + msg); }
            check(seen.SequenceEqual(names.Skip(1).Concat(names.Take(1))), "preset key: alphabetical order, round the list: " + string.Join(",", seen));
            check(HelperPresetKey.Cycle(null) == null, "preset key: no config, no message");
        }

        // ------------------------------------------------------------------------------------ store try-on
        static void StoreChecks(Action<bool, string> check)
        {
            var outfit = PreviewOption.Of("outfit", 130);
            var bundle = new PreviewOption { Kind = "bundle", Parts = new List<PreviewOption> { PreviewOption.Of("item"), PreviewOption.Of("wings") } };
            var plain = new PreviewOption { Kind = "bundle", Parts = new List<PreviewOption> { PreviewOption.Of("item") } };
            check(StoreTryPanel.IsWorn(outfit) && StoreTryPanel.IsWorn(bundle) && !StoreTryPanel.IsWorn(plain) && !StoreTryPanel.IsWorn(PreviewOption.Of("swatch")) && !StoreTryPanel.IsWorn(PreviewOption.Of("subject")) && !StoreTryPanel.IsWorn(null), "try-on: which looks are worn");
            var worn = new StoreOffer { Look = outfit };
            var server = new StoreOffer { PreviewEffect = true, Look = outfit };
            var chat = new StoreOffer { Look = PreviewOption.Of("swatch") };
            check(StoreTryPanel.PlanOf(worn, true, false).Show && StoreTryPanel.PlanOf(worn, true, false).Panel && !StoreTryPanel.PlanOf(worn, false, false).Show, "try-on: the panel plan needs the panel");
            check(StoreTryPanel.PlanOf(server, true, false).Server && StoreTryPanel.PlanOf(server, true, false).Panel, "try-on: an effect offer plays on the server and shows in the panel");
            check(!StoreTryPanel.PlanOf(chat, true, true).Show && !StoreTryPanel.PlanOf(null, true, true).Show, "try-on: a chat colour has no button");
            var tried = outfit;
            check(StoreTryPanel.OptionAt(tried, 10000, 5000) == tried && StoreTryPanel.OptionAt(tried, 10000, 10000) == null && StoreTryPanel.OptionAt(null, 10000, 5000) == null, "try-on: the panel goes back to the character as worn after ten seconds");
            check(StoreTryPanel.Over(10000, 10000) && !StoreTryPanel.Over(10000, 9999) && !StoreTryPanel.Over(0, 99999), "try-on: over at the end time");
            check(StoreTryPanel.Ms == 10000, "try-on: ten seconds");
        }

        // ------------------------------------------------------------------------------------ the tooltip card
        const string TipJson = "{\"name\":\"blazing staff\",\"rarity\":4,\"rarityName\":\"Epic\",\"slot\":\"Weapon: Wand\",\"level\":120,\"maxTier\":6,"
            + "\"quality\":{\"q\":10,\"cap\":20},"
            + "\"base\":[{\"k\":\"dps\",\"l\":\"DPS\",\"v\":123.4},{\"k\":\"attack\",\"l\":\"Attack\",\"v\":50},{\"k\":\"yourinterval\",\"l\":\"Interval\",\"v\":1.5,\"fmt\":\"sec\"},{\"k\":\"critchance\",\"l\":\"Crit\",\"v\":5,\"fmt\":\"pct\"}],"
            + "\"mods\":[{\"sd\":\"p\",\"t\":\"+10 fire\",\"tr\":6,\"lo\":8,\"hi\":12,\"g\":\"element\"},{\"sd\":\"s\",\"t\":\"+5 mana\",\"tr\":3,\"bd\":true}],\"sides\":{\"p\":1,\"s\":1,\"max\":3},"
            + "\"sockets\":{\"count\":2,\"list\":[{\"name\":\"Ruby\",\"text\":\"+3 fire\",\"color\":\"#ff6060\"}]},"
            + "\"req\":{\"level\":150,\"voc\":\"Mage, Druid\"},\"desc\":\"A hot staff.\",\"charges\":{\"n\":3,\"max\":5},"
            + "\"src\":{\"s\":[{\"k\":\"monster\",\"n\":\"Fire Imp\",\"v\":1.5}]},\"weight\":24.9,"
            + "\"cmp\":[5],\"kind\":\"wand\",\"stats\":[1]}";

        static void CardChecks(Action<bool, string> check)
        {
            var tip = Json.TryParse(TipJson);
            var c = TipCard.Build(tip, 100);
            check(c.Title == "Blazing staff" && c.Kind == "EPIC WAND" && c.SlotLine == "Weapon: Wand" && c.TitleColor == "#a35cf0" && c.KindColor == c.TitleColor, "card: head: " + c.Title + " / " + c.Kind);
            check(c.Level == "Item Level 120 - up to T6", "card: item level line: " + c.Level);
            check(c.Flags.Count == 1 && c.Flags[0].Text == "Quality +10%  (up to 20%)", "card: quality flag");
            check(c.Tiles.Count == 3 && c.Tiles[0].Key == "dps" && c.Tiles[0].Hero && c.Tiles[0].Value == "123.4" && c.Tiles[1].Key == "attack" && c.Tiles[2].Key == "speed" && c.Tiles[2].Caption == "Speed", "card: DPS the hero tile, then attack and speed: " + string.Join(",", c.Tiles.Select(t => t.Key)));
            check(c.ExtraLines.Count == 1 && c.ExtraLines[0][0] == "Crit " && c.ExtraLines[0][2] == "+5%", "card: the rest of the base stats in one line: " + string.Join("|", c.ExtraLines[0]));
            check(c.Mods.Count == 2 && c.Mods[0].Caption == "PREFIXES 1/3" && c.Mods[1].Caption == "SUFFIXES 1/3", "card: modifier groups with side counts: " + string.Join(",", c.Mods.Select(g => g.Caption)));
            var p = c.Mods[0].Rows[0];
            check(p.IsMod && p.Tag == "T6" && p.Top && p.Range == "8-12" && p.Color == TipLines.Element && p.TagColor == TipLines.TierColor(6), "card: a prefix row: tag, top tier, range, colour");
            var s = c.Mods[1].Rows[0];
            check(s.Tag == "T3" && !s.Top && s.Parts != null && s.Parts[2] == " [bound]", "card: a bound suffix keeps a gold tag");
            check(c.Extras.Count >= 3, "card: extra groups: " + c.Extras.Count);
            check(c.Extras[0].Caption == "SOCKETS 1/2" && c.Extras[0].Rows.Count == 2 && c.Extras[0].Rows[1].Text == "empty socket", "card: sockets group");
            check(c.Chips.Count == 3 && c.Chips[0].Text == "Level 150" && c.Chips[0].Low && c.Chips[0].Color == TipLines.Red && c.Chips[1].Text == "Mage" && c.Chips[2].Text == "Druid", "card: requirement chips, the level in red");
            check(!TipCard.Build(tip, 200).Chips[0].Low, "card: the level chip is plain when you reach it");
            check(c.Foot.Count == 1 && c.Foot[0].Text == "Drops from: Fire Imp (1.5) - Weight 24.9 oz", "card: the weight joins the sources line: " + string.Join("|", c.Foot.Select(f => f.Text)));
            check(c.Comparable && c.HasStats, "card: comparable gear with stats");
            check(TipCard.Build(null, 1).Title == "" && !TipCard.Build(Json.TryParse("{\"name\":\"stone\"}"), 1).HasStats, "card: a bare item has a title and nothing else");
            // a support rune: the effect is a wide tile, the spell kinds are chips
            var rune = Json.TryParse("{\"name\":\"rune\",\"desc\":\"A support rune for a spell socket: mana cost -9%, refunded after the cast. Fits single target, area spells. Three of them combine into one of the next level: x (!supports)\"}");
            var rc = TipCard.Build(rune, 1);
            check(rc.Kind == "SUPPORT RUNE" && rc.Effect == "Mana cost -9%, refunded after the cast" && rc.FitChips.Count == 2 && rc.FitChips[0].Text == "single target" && rc.FitCaption == "FITS SPELLS", "card: support rune: " + rc.Effect + " / " + string.Join(",", rc.FitChips.Select(f => f.Text)));
            check(rc.Foot.Count == 2 && rc.Foot[0].Text == "Three combine into one of the next level." && rc.Foot[1].Text.Contains("!supports"), "card: the rune's rules are dim foot lines");
            check(rc.Extras.Count == 0, "card: the rune's description is not repeated as flavour");
            // a unique with a passive and a set
            var uq = Json.TryParse("{\"name\":\"ember\",\"unique\":{\"set\":{\"name\":\"Cinder\",\"have\":1,\"total\":3,\"pieces\":[{\"n\":\"Ring\",\"eq\":true}],\"bonuses\":[{\"n\":2,\"t\":\"+5 luck\"}]}},\"passive\":{\"name\":\"Ash\",\"text\":\"Burns.\",\"flavor\":\"Old.\"},\"locked\":true}");
            var uc = TipCard.Build(uq, 1);
            check(uc.TitleColor == TipLines.SetC && uc.Kind == "SET", "card: a set piece: green title, Set kind");
            check(uc.Extras.Any(g => g.Caption.StartsWith("Set: Cinder", StringComparison.Ordinal)) && uc.Extras.Any(g => g.Caption == "Ash" && g.CapColor == TipLines.PassiveC) && uc.Extras.Any(g => g.Rows.Any(r => r.Text == "Locked")), "card: set, passive and locked groups");

            // the layout
            Func<string, int, double> measure = (t, size) => t.Length * 6.0 + size;
            var notes = new List<TipLine> { new TipLine { Text = "Hold Ctrl to compare", Color = TipLines.Dim, Sep = true } };
            var boxes = TipCardLayout.Plan(c, 320, measure, out double h, notes);
            check(h > 150 && boxes.Count > 20 && boxes[0].Kind == "title" && boxes[0].R.W == 300, "layout: a card has a height and boxes");
            check(boxes.Count(b => b.Kind == "tile") == 3 && boxes.Count(b => b.Kind == "row") >= 5 && boxes.Count(b => b.Kind == "chip") == 3 && boxes.Any(b => b.Kind == "foot" && b.Text.StartsWith("Hold Ctrl", StringComparison.Ordinal)), "layout: tiles, rows, chips and the notes");
            double lastBottom = boxes.Max(b => b.R.Bottom);
            check(lastBottom <= h && h - lastBottom <= TipCardLayout.Pad + 1, "layout: nothing past the card's bottom");
            var ys = boxes.Where(b => b.Kind == "row" || b.Kind == "caption").Select(b => b.R.Y).ToList();
            check(ys.SequenceEqual(ys.OrderBy(v => v)), "layout: boxes run top to bottom");
            var tiles = TipCardLayout.TileRects(c.Tiles, 10, 0, 300);
            check(tiles.Count == 3 && Math.Abs(tiles.Sum(t => t.W) + 2 * TipCardLayout.Gap - 300) < 1e-6 && tiles[0].W > tiles[1].W && tiles[0].H > tiles[1].H, "layout: the hero tile is wider and taller, the row fills the width");
            var rows = TipCardLayout.ChipRows(new double[] { 60, 60, 60, 60 }, 4, 200);
            check(rows.Count == 2 && rows[0].Count == 3 && rows[1].Count == 1, "layout: chips wrap into rows");
            check(TipCardLayout.ChipRows(new double[0], 4, 200).Count == 0 && TipCardLayout.ChipRows(new double[] { 500 }, 4, 200).Count == 1, "layout: an empty list and a too wide chip");
        }

        // ------------------------------------------------------------------------------------ trials
        const string TrialsJson = "{\"supported\":true,\"trial\":\"Trial of Ash\",\"story\":\"Climb.\",\"level\":300,\"tier\":1,\"tokens\":2,\"maxTokens\":10,\"switchGold\":150000,\"running\":false,"
            + "\"tiers\":[{\"name\":\"Normal\",\"minLevel\":100,\"cleared\":true,\"time\":600,\"lives\":3,\"bossHealth\":1500000},{\"name\":\"Hard\",\"minLevel\":300,\"cleared\":false,\"problem\":\"Level 300 needed\",\"time\":600,\"lives\":2,\"bossHealth\":9000000},{\"name\":\"Insane\",\"minLevel\":500,\"cleared\":false,\"time\":600,\"lives\":1,\"bossHealth\":1}],"
            + "\"pairs\":[{\"pair\":1,\"tier\":\"Normal\",\"locked\":false,\"held\":0,\"clear\":{\"can\":false},\"nodes\":[{\"id\":1,\"name\":\"Fury\",\"lore\":\"Rage.\",\"lines\":[{\"text\":\"+10% damage\",\"good\":true},{\"text\":\"-5% armour\",\"good\":false}],\"can\":true},{\"id\":2,\"name\":\"Calm\",\"lines\":[],\"can\":false,\"why\":\"Not yet\"}]},"
            + "{\"pair\":2,\"tier\":\"Hard\",\"locked\":true,\"held\":0,\"nodes\":[{\"name\":\"A\"},{\"name\":\"B\"}]},"
            + "{\"pair\":3,\"tier\":\"Normal\",\"locked\":false,\"held\":1,\"clear\":{\"can\":true},\"nodes\":[{\"name\":\"C\",\"can\":false},{\"name\":\"D\",\"can\":true}]}]}";

        static void TrialChecks(Action<bool, string> check)
        {
            var ext = Ext(out var sent);
            var tree = new PassiveTree(ext);
            var tr = tree.Trials;
            tr.Request();
            check(sent.Count == 1 && sent[0].Contains("trialRequest"), "trials: the request");
            check(!tr.Known, "trials: unknown before the server answers");
            ext.Receive(65, "{\"action\":\"trialState\",\"data\":" + TrialsJson + "}");
            check(tr.Known && tr.Supported && tr.Trial == "Trial of Ash" && tr.Tokens == 2 && tr.SwitchGold == 150000 && tr.Tiers.Count == 3 && tr.Pairs.Count == 3, "trials: the state is read through the tree's opcode");
            check(tr.TokensLine == "Trial Tokens: 2 / 10     Changing a held node costs 1 token and 150,000 gold", "trials: tokens line: " + tr.TokensLine);
            var open = tr.Card(tr.Pairs[0], 1);
            check(open.Action == "Choose" && open.Enabled && open.Status == "Free to choose" && open.StatusColor == TreeTrials.Good, "trials: the first choice is free");
            var cant = tr.Card(tr.Pairs[0], 2);
            check(cant.Action == "Choose" && !cant.Enabled && cant.Status == "Not yet" && cant.StatusColor == TreeTrials.Bad, "trials: a node that cannot be chosen says why");
            var locked = tr.Card(tr.Pairs[1], 1);
            check(locked.Action == "Locked" && !locked.Enabled && locked.Status == "Locked: clear on Hard" && locked.Tooltip == "Clear Trial of Ash on Hard to open this pair of nodes.", "trials: a locked pair");
            var held = tr.Card(tr.Pairs[2], 1);
            check(held.Action == "Held" && !held.Enabled && held.StatusColor == TreeTrials.Held, "trials: the held node");
            var sw = tr.Card(tr.Pairs[2], 2);
            check(sw.Action == "Switch" && sw.Enabled && sw.Status == "1 token + gold" && sw.Tooltip == "Replaces C. Costs 1 Trial Token and 150,000 gold.", "trials: switching costs a token and gold: " + sw.Tooltip);
            check(!tr.ClearCard(tr.Pairs[0]).Enabled && tr.ClearCard(tr.Pairs[2]).Enabled && !tr.ClearCard(tr.Pairs[1]).Enabled, "trials: clear needs a held node, an open pair and a token");
            check(tr.TierButton(0).Action == "Enter Normal (cleared)" && tr.TierButton(0).Enabled && !tr.TierButton(1).Enabled && tr.TierButton(1).Tooltip.EndsWith("Level 300 needed", StringComparison.Ordinal) && tr.TierButton(2).Tooltip.EndsWith("The first clear opens a pair of nodes.", StringComparison.Ordinal), "trials: the Enter buttons");
            check(tr.TierButton(0).Tooltip.StartsWith("Normal: level 100, 10 minutes, 3 lives, guardian about 1,500,000 health.", StringComparison.Ordinal), "trials: the tier tooltip");
            // choosing asks first, then sends
            sent.Clear();
            check(tr.AskChoose(1, 1) && tr.Asking && tr.AskTitle == "Choose a node" && tr.AskText.StartsWith("Choose Fury?", StringComparison.Ordinal) && tr.AskText.Contains("+ +10% damage") && tr.AskText.Contains("- -5% armour"), "trials: the question lists the node's lines");
            check(sent.Count == 0, "trials: nothing is sent before Ok");
            tr.Confirm();
            check(sent.Count == 1 && sent[0].Contains("trialChoose") && sent[0].Contains("\"pair\":1") && sent[0].Contains("\"side\":1") && !tr.Asking, "trials: Ok sends the choice");
            check(!tr.AskChoose(1, 2) && !tr.AskChoose(2, 1) && !tr.AskChoose(9, 1), "trials: a node that cannot be chosen, a locked pair and a missing pair ask nothing");
            sent.Clear();
            check(tr.AskClear(3) && tr.AskTitle == "Give up a node" && tr.AskText.StartsWith("Give up C", StringComparison.Ordinal), "trials: clear asks first");
            tr.Confirm();
            check(sent.Count == 1 && sent[0].Contains("\"side\":0") && sent[0].Contains("\"pair\":3"), "trials: clear is a choice of side 0");
            tr.AskClear(3); tr.Cancel();
            check(!tr.Asking && sent.Count == 1, "trials: Cancel sends nothing");
            sent.Clear();
            check(tr.Enter(1) && sent[0].Contains("trialEnter") && sent[0].Contains("\"tier\":1") && !tr.Enter(2) && !tr.Enter(7), "trials: enter a tier");
            tr.Leave();
            check(sent.Count == 2 && sent[1].Contains("trialLeave"), "trials: leave");
            // a running trial blocks everything
            ext.Receive(65, "{\"action\":\"trialState\",\"data\":" + TrialsJson.Replace("\"running\":false", "\"running\":true") + "}");
            check(tr.Running && !tr.Card(tr.Pairs[0], 1).Enabled && tr.Card(tr.Pairs[0], 1).Status == "Not during a trial" && tr.Card(tr.Pairs[2], 1).Action == "Held" && tr.Card(tr.Pairs[2], 2).Action == "In a trial" && !tr.TierButton(0).Enabled && !tr.Enter(1), "trials: while a trial runs nothing changes");
            ext.Receive(65, "{\"action\":\"trialState\",\"data\":{\"supported\":false}}");
            check(tr.Known && !tr.Supported && !tr.AskChoose(1, 1), "trials: an unsupported vocation");
            check(TreeTrials.Fit("abcdefghij", 6) == "abc..." && TreeTrials.Fit("abc", 6) == "abc" && TreeTrials.Gold(1234567) == "1,234,567", "trials: fit and gold");
        }

        // ------------------------------------------------------------------------------------ auto build
        static string List(string group, string builds) => "{\"action\":\"autobuildList\",\"data\":{\"group\":\"" + group + "\",\"builds\":" + builds + ",\"owned\":40,\"held\":30,\"free\":10,\"cap\":120}}";

        static void AutoBuildChecks(Action<bool, string> check)
        {
            var ext = Ext(out var sent);
            var tree = new PassiveTree(ext);
            double now = 0;
            var ab = tree.Auto;
            ab.Clock = () => now;
            ab.Open();
            check(sent.Count == 1 && sent[0].Contains("autobuildList") && ab.Opened, "auto build: opening asks for the list");
            check(ab.Detail(out _) == "Pick a build. The tree shows what it would take.", "auto build: no list, no pick");
            ext.Receive(65, List("role", "[{\"id\":\"tank\",\"name\":\"Tank\",\"text\":\"Takes hits.\",\"summary\":\"Life.\",\"points\":80,\"fit\":\"primary\"},{\"id\":\"burst\",\"name\":\"Burst\",\"points\":60,\"fit\":\"secondary\"}]"));
            check(ab.Role.Count == 2 && ab.Selected == "tank" && ab.Owned == 40 && ab.Free == 10 && ab.Cap == 120, "auto build: the first build is picked when the list comes");
            check(sent.Count == 2 && sent[1].Contains("autobuildPreview") && sent[1].Contains("\"build\":\"tank\""), "auto build: the pick's preview is asked for at once");
            ext.Receive(65, List("focus", "[{\"id\":\"fire\",\"name\":\"Fire\",\"points\":50}]"));
            var rows = ab.Rows();
            check(rows.Count == 5 && rows[0].Heading && rows[0].Text == "- Recommended -" && rows[3].Heading && rows[3].Text == "- Focus -" && rows[1].Text == "Tank - 80 points [Primary]" && rows[2].Text == "Burst - 60 points [Secondary]" && rows[4].Text == "Fire - 50 points", "auto build: the rows: headings, builds, fit tags: " + string.Join(" / ", rows.Select(r => r.Text)));
            check(sent.Count == 2, "auto build: a second list does not ask again for the shown pick");
            string d = ab.Detail(out string col);
            check(d.Contains("Takes hits.") && d.Contains("The build uses 80 points. You own 40 and 10 are free.") && d.Contains("Asking the server for a preview...") && col == AutoBuild.Text, "auto build: detail while waiting: " + d);
            const string PreviewJson = "{\"action\":\"autobuildPreview\",\"data\":{\"build\":\"tank\",\"name\":\"Tank\",\"owned\":40,\"held\":30,\"wanted\":80,\"add\":{\"nodes\":[1,2,3],\"added\":3,\"skipped\":5,\"other\":2},\"reset\":{\"nodes\":[1,2,3,4,5],\"added\":5,\"removed\":4,\"cost\":250000,\"free\":0}}}";
            ext.Receive(65, "{\"action\":\"autobuildPreview\",\"data\":{\"build\":\"burst\",\"add\":{\"added\":9}}}");
            check(ab.Preview == null, "auto build: the answer to another pick is ignored");
            ext.Receive(65, PreviewJson);
            check(ab.Preview != null && ab.Preview.AddAdded == 3 && ab.Preview.ResetRemoved == 4 && ab.Preview.ResetCost == 250000 && ab.CanApply && ab.CanReset, "auto build: the preview is read");
            check(tree.PreviewNodes != null && tree.PreviewNodes.SetEquals(new[] { 1, 2, 3, 4, 5 }), "auto build: the tree shows what Reset and apply would build when it takes something back");
            d = ab.Detail(out col);
            check(d.Contains("Apply: adds 3 nodes, takes nothing back, free.") && d.Contains("5 more nodes of the build need points you do not have yet.") && d.Contains("2 nodes your class cannot hold are left out.") && d.Contains("Reset and apply: takes back 4 nodes and builds this one (5 nodes). Price: 250,000 gold coins."), "auto build: detail after the preview: " + d);
            sent.Clear();
            check(ab.Apply() && sent.Count == 1 && sent[0].Contains("autobuildApply") && sent[0].Contains("\"mode\":\"add\"") && sent[0].Contains("\"cost\":0"), "auto build: Apply adds, free");
            sent.Clear();
            check(ab.AskReset() && ab.ConfirmTextShown == "Reset your tree and apply Tank?\nNodes taken back: 4. Price: 250,000 gold coins." && sent.Count == 0, "auto build: Reset and apply asks with the price");
            ab.ConfirmReset();
            check(sent.Count == 1 && sent[0].Contains("\"mode\":\"reset\"") && sent[0].Contains("\"cost\":250000") && ab.ConfirmTextShown == "", "auto build: the price shown is the price sent");
            ab.AskReset(); ab.CancelReset();
            check(ab.ConfirmTextShown == "" && sent.Count == 1, "auto build: Cancel sends nothing");
            // a preview that adds nothing and takes nothing back
            ext.Receive(65, PreviewJson.Replace("\"added\":3,\"skipped\":5", "\"added\":0,\"skipped\":0").Replace("\"added\":5,\"removed\":4", "\"added\":0,\"removed\":0"));
            check(!ab.CanApply && !ab.CanReset && ab.Detail(out _).Contains("your tree already fits this build"), "auto build: nothing to do");
            // picking another build asks again
            sent.Clear();
            ab.Pick("burst");
            check(ab.Selected == "burst" && ab.Preview == null && tree.PreviewNodes == null && sent.Count == 1 && sent[0].Contains("\"build\":\"burst\""), "auto build: a new pick drops the preview and asks");
            // timeouts: asked again twice, then an error line
            sent.Clear();
            now += 3999; ab.Tick(now);
            check(sent.Count == 0, "auto build: no answer yet, wait");
            now += 2; ab.Tick(now);
            check(sent.Count == 1 && sent[0].Contains("autobuildPreview"), "auto build: asked again after 4 s");
            now += 4001; ab.Tick(now);
            check(sent.Count == 2, "auto build: asked a third time");
            now += 4001; ab.Tick(now);
            check(sent.Count == 2 && ab.Failed == "burst" && ab.NoteColor == AutoBuild.Red && ab.NoteText.StartsWith("The server did not answer the preview.", StringComparison.Ordinal), "auto build: then an error line, no more asking");
            check(!ab.NeedsPreview(), "auto build: a failed pick is not asked again until picked again");
            // an error answer: too fast asks again after a short wait
            ab.Pick("fire");
            sent.Clear();
            ext.Receive(65, "{\"action\":\"autobuildError\",\"data\":{\"message\":\"Too fast\",\"build\":\"fire\",\"retry\":true}}");
            now += 100; ab.Tick(now);
            check(sent.Count == 0, "auto build: too fast waits for the retry delay");
            now += 700; ab.Tick(now);
            check(sent.Count == 1, "auto build: then asks again");
            ext.Receive(65, "{\"action\":\"autobuildError\",\"data\":{\"message\":\"Nope\",\"build\":\"other\"}}");
            check(ab.NoteText == "" || ab.NoteText != "Nope", "auto build: the error of another pick is ignored");
            ext.Receive(65, "{\"action\":\"autobuildError\",\"data\":{\"message\":\"Broken\",\"build\":\"fire\"}}");
            check(ab.Failed == "fire" && ab.NoteText == "Broken" && ab.NoteColor == AutoBuild.Red, "auto build: an error fails the pick");
            // applied: the list is asked for again
            sent.Clear();
            ext.Receive(65, "{\"action\":\"autobuildApplied\",\"data\":{\"message\":\"Done\"}}");
            check(ab.NoteText == "Done" && ab.NoteColor == AutoBuild.GoodColor && ab.Preview == null && sent.Count == 1 && sent[0].Contains("autobuildList"), "auto build: applied: the note and a new list");
            // closing takes the preview back
            ext.Receive(65, "{\"action\":\"autobuildPreview\",\"data\":{\"build\":\"fire\",\"add\":{\"nodes\":[7],\"added\":1}}}");
            sent.Clear();
            ab.Close();
            check(!ab.Opened && ab.Preview == null && tree.PreviewNodes == null && sent.Count == 2 && sent[0].Contains("requestNodesUnlocked") && sent[1].Contains("requestPoints"), "auto build: closing shows the saved allocation again");
            ext.Receive(65, "{\"action\":\"autobuildError\",\"data\":{\"message\":\"Late\"}}");
            check(tree.BoxText == "Late" && tree.BoxTitle == "Auto build", "auto build: an error with the panel closed is a message box");
        }

        // ------------------------------------------------------------------------------------ Paragon masteries
        const string MasteryJson = "{\"unlocked\":true,\"level\":1010,\"startLevel\":1000,\"total\":10,\"spent\":2,\"free\":8,\"resetCost\":252500,\"categories\":[],"
            + "\"mastery\":{\"maxRanks\":1000,\"rows\":[{\"key\":\"dmg\",\"name\":\"Damage\",\"desc\":\"More.\",\"ranks\":700,\"value\":11.67,\"next\":0.0167},{\"key\":\"hp\",\"name\":\"Health\",\"ranks\":0,\"value\":0,\"next\":0.02}]},"
            + "\"exchange\":{\"ratio\":2,\"treeFree\":12.9,\"converted\":4}}";

        static void MasteryChecks(Action<bool, string> check)
        {
            var ext = Ext(out var sent);
            var pg = new PassiveTree(ext).Paragon;
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":" + MasteryJson + "}");
            check(pg.HasMastery && pg.MasteryRows.Count == 2 && pg.MasteryMaxRanks == 1000 && pg.HasExchange && pg.ExchangeRatio == 2, "mastery: rows and exchange are read");
            var dmg = pg.MasteryRows[0]; var hp = pg.MasteryRows[1];
            check(ParagonPanel.MasteryValueText(dmg) == "+11.67%" && ParagonPanel.MasteryNextText(dmg) == "+0.017%" && ParagonPanel.Fmt3(0.02) == "0.02" && ParagonPanel.Fmt3(1) == "1", "mastery: the number texts");
            check(pg.MasteryBuy(dmg, 1) == 1 && pg.MasteryBuy(dmg, 10) == 8 && pg.MasteryBuy(dmg, 100) == 8, "mastery: a buy is limited by the free points: " + pg.MasteryBuy(dmg, 10));
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":" + MasteryJson.Replace("\"ranks\":700", "\"ranks\":995") + "}");
            dmg = pg.MasteryRows[0];
            check(pg.MasteryBuy(dmg, 10) == 5 && pg.MasteryBuy(null, 1) == 0, "mastery: and by the room under the rank limit");
            sent.Clear();
            check(pg.BuyMastery(hp, 1) && sent.Count == 1 && sent[0].Contains("paragonMastery") && sent[0].Contains("\"key\":\"hp\"") && sent[0].Contains("\"n\":1"), "mastery: a buy is sent");
            check(!pg.BuyMastery(dmg, 10) && sent.Count == 1, "mastery: a buy that does not fit sends nothing");
            check(pg.Exchangeable == 12 && pg.ExchangeGain(12) == 24 && pg.ExchangeAsk == "Turn 12 free passive tree points into 24 Paragon points? This cannot be undone: the points stay Paragon points. Proceed?", "mastery: the exchange: " + pg.ExchangeAsk);
            check(pg.ExchangeLine == "Free passive tree points: 12. Each one becomes 2 Paragon point(s), for good. Already exchanged: 4.", "mastery: the exchange line: " + pg.ExchangeLine);
            sent.Clear();
            check(pg.Exchange() && sent[0].Contains("paragonConvert") && sent[0].Contains("\"n\":12"), "mastery: the exchange is sent");
            var lines = pg.MasteryLines();
            check(lines.Count == 1 && lines[0] == "+11.67% Damage (995 ranks).", "mastery: the bonus lines of ranked masteries: " + string.Join("|", lines));
            ext.Receive(65, "{\"action\":\"paragonState\",\"data\":{\"unlocked\":false,\"level\":10,\"startLevel\":1000,\"categories\":[]}}");
            check(!pg.HasMastery && pg.Exchangeable == 0 && !pg.Exchange() && pg.MasteryBuy(hp, 1) == 0, "mastery: locked, nothing to buy or exchange");
        }

        // ------------------------------------------------------------------------------------ node icons and curved links
        static void TreeArtChecks(Action<bool, string> check)
        {
            // node frames and sizes: passivetree.otui
            var c = TreeNodeArt.Of('c'); var d = TreeNodeArt.Of('d'); var m = TreeNodeArt.Of('M');
            check(c.Size == 27 && c.FrameW == 56 && d.Size == 60 && d.FrameW == 143 && d.FrameH == 149 && m.Size == 44 && TreeNodeArt.Of('?').Size == 27, "node art: sizes of the node kinds");
            check(TreeNodeArt.FramePath('d', TreeNodeArt.State.Allocated) == "../data/images/passivetree/KeystoneFrameAllocated.png" && TreeNodeArt.FramePath('c', TreeNodeArt.State.CanAllocate) == "../data/images/passivetree/commont_canallocate.png" && TreeNodeArt.FramePath('v', TreeNodeArt.State.Unallocated) == "../data/images/passivetree/veryrare_notallocate.png", "node art: frame files (the main client's spellings)");
            check(TreeNodeArt.StateOf(true, true) == TreeNodeArt.State.Allocated && TreeNodeArt.StateOf(false, true) == TreeNodeArt.State.CanAllocate && TreeNodeArt.StateOf(false, false) == TreeNodeArt.State.Unallocated, "node art: the state of a node");
            string frames = Find("client", "overlay", "data", "images", "passivetree");
            if (frames != null)
                foreach (char t in "cuMrvmd")
                    foreach (var st in new[] { TreeNodeArt.State.Unallocated, TreeNodeArt.State.CanAllocate, TreeNodeArt.State.Allocated })
                        check(File.Exists(Path.Combine(frames, Path.GetFileName(TreeNodeArt.FramePath(t, st)))), "node art: frame " + t + " " + st + " exists");

            // arcs: two nodes on one orbit of a group
            var a = new TreeNode { Id = 1, X = 0, Y = -100, Group = 5, Orbit = 2 };
            var b = new TreeNode { Id = 2, X = 100, Y = 0, Group = 5, Orbit = 2 };
            var arc = TreeArcs.Arc(a, b, 0, 0);
            check(arc != null && arc.Count >= 5 && Math.Abs(arc[0][0] - 0) < 1e-6 && Math.Abs(arc[0][1] + 100) < 1e-6 && Math.Abs(arc[arc.Count - 1][0] - 100) < 1e-6 && Math.Abs(arc[arc.Count - 1][1]) < 1e-6, "arc: runs from one node to the other");
            check(arc.All(p => Math.Abs(Math.Sqrt(p[0] * p[0] + p[1] * p[1]) - 100) < 1e-6), "arc: every point is on the orbit");
            check(arc.All(p => p[0] >= -1e-6 && p[1] <= 1e-6), "arc: the short way round (north to east)");
            var far = new TreeNode { Id = 3, X = 0, Y = 100, Group = 5, Orbit = 2 };
            check(TreeArcs.Arc(a, far, 0, 0) == null, "arc: opposite nodes (180 degrees) are a straight line");
            check(TreeArcs.Arc(a, new TreeNode { X = 100, Y = 0, Group = 6, Orbit = 2 }, 0, 0) == null && TreeArcs.Arc(a, new TreeNode { X = 100, Y = 0, Group = 5, Orbit = 3 }, 0, 0) == null && TreeArcs.Arc(new TreeNode { X = 0, Y = -100, Group = 5 }, b, 0, 0) == null && TreeArcs.Arc(null, b, 0, 0) == null, "arc: another group, another orbit or no orbit is a line");
            var wrap = TreeArcs.Arc(new TreeNode { X = -50f, Y = -86.6f, Group = 5, Orbit = 2 }, new TreeNode { X = 50f, Y = -86.6f, Group = 5, Orbit = 2 }, 0, 0);
            check(wrap != null && wrap.All(p => p[1] < -80), "arc: across the north line takes the short way");

            // the icon clips
            var icons = TreeIcons.Parse("{\"version\":1,\"icons\":{\"strength\":{\"x\":810,\"y\":0,\"w\":27,\"h\":27},\"ksWrath\":{\"f\":\"keystones.png\",\"x\":0,\"y\":0,\"w\":64,\"h\":64}},\"painted\":{\"ksWrath\":[0,64]}}");
            check(icons.Resolve("strength", false, out string path, out int x, out int y, out int w, out int h) && path == "../data/images/passivetree/skills.png" && x == 810 && w == 27 && h == 27, "icons: the default sheet is skills");
            check(icons.Resolve("ksWrath", false, out path, out x, out y, out w, out h) && path == "../data/images/passivetree/keystones.png" && w == 64, "icons: a keystone has its own sheet");
            check(icons.Resolve("ksWrath", true, out path, out x, out y, out w, out h) && path == PaintedIcons.NodePath && x == 0 && y == 64 && w == 64, "icons: the painted option takes the painted cell");
            check(icons.Resolve("strength", true, out path, out x, out y, out w, out h) && path.EndsWith("skills.png", StringComparison.Ordinal), "icons: a node with no painted cell keeps its normal icon");
            check(!icons.Resolve("nope", false, out path, out x, out y, out w, out h) && !icons.Resolve("", false, out path, out x, out y, out w, out h), "icons: an unknown key has none");
            var n = new TreeNode { Icon = "strength", VariantIcons = new Dictionary<string, string> { { "mage", "intelligence" } } };
            check(TreeIcons.KeyFor(n, "mage") == "intelligence" && TreeIcons.KeyFor(n, "knight") == "strength" && TreeIcons.KeyFor(n, "") == "strength" && TreeIcons.KeyFor(null, "x") == "", "icons: a class variant's own icon key");
            n.Type = 's';
            check(TreeIcons.KeyFor(n, "mage") == "strength", "icons: never on a start node");

            // the generated data, when the Resources are next to the tests
            string treePath = Find("unity", "Client", "Assets", "Chaos", "Resources", "PassiveTree.json") ?? Find("Client", "Assets", "Chaos", "Resources", "PassiveTree.json");
            if (treePath != null)
            {
                var data = TreeData.Parse(File.ReadAllText(treePath));
                var all = TreeIcons.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(treePath), "PassiveTreeIcons.json")));
                check(data.Groups.Count > 20 && data.Groups.ContainsKey(1), "tree data: the group centres are there: " + data.Groups.Count);
                int withIcon = 0, withGroup = 0, missingClip = 0;
                foreach (var node in data.Ordered)
                {
                    if (node.Icon.Length > 0) { withIcon++; if (!all.Clips.ContainsKey(node.Icon)) missingClip++; }
                    foreach (var vi in node.VariantIcons.Values) if (!all.Clips.ContainsKey(vi)) missingClip++;
                    if (node.Group != 0 && data.Groups.ContainsKey(node.Group)) withGroup++;
                }
                check(withIcon >= data.Ordered.Count * 0.9 && missingClip == 0 && withGroup >= data.Ordered.Count * 0.9, "tree data: every icon key has a clip (" + withIcon + " icons, " + missingClip + " missing, " + withGroup + " in a group)");
                int arcs = 0;
                foreach (var node in data.Ordered)
                    foreach (int o in node.Links)
                        if (node.Id < o && data.Nodes.TryGetValue(o, out var other) && node.Group != 0 && data.Groups.TryGetValue(node.Group, out var gc) && TreeArcs.Arc(node, other, gc[0], gc[1]) != null) arcs++;
                check(arcs > 50, "tree data: many links are arcs: " + arcs);
                int painted = all.Painted.Count;
                check(painted >= 20, "tree data: the painted cells of keystones and masteries: " + painted);
            }
            string sheets = Find("client", "overlay", "data", "images", "passivetree");
            if (sheets != null)
                foreach (string f in new[] { "skills.png", "keystones.png", "painted_nodes.png" }) check(File.Exists(Path.Combine(sheets, f)), "icons: sheet " + f + " exists");
        }

        // ------------------------------------------------------------------------------------ texts
        static void TextChecks(Action<bool, string> check)
        {
            Loc.Set("pt-BR");
            check(Loc.T("Equip") == "Equipar" && Loc.T("That item is already worn.") == "Esse item já está equipado.", "pt-BR: equip texts");
            check(Loc.T("Trial Tokens: {0} / {1}     Changing a held node costs 1 token and {2} gold", 2, 10, "1,500") == "Trial Tokens: 2 / 10     Trocar um nó escolhido custa 1 token e 1,500 de ouro", "pt-BR: arguments keep their indexes");
            check(Loc.T("Reset your tree and apply {0}?\nNodes taken back: {1}. Price: {2}.", "X", 1, "free") == "Resetar sua árvore e aplicar X?\nNós devolvidos: 1. Preço: free.", "pt-BR: the reset question");
            check(Loc.T("Key: {0}", "G") == "Tecla: G" && Loc.T("Pair {0}", 2) == "Par 2" && Loc.T("Press a key...") == "Aperte uma tecla...", "pt-BR: helper key and trials");
            check(Loc.T("Painted icons (bar, spellbook, passive tree)").StartsWith("Ícones pintados", StringComparison.Ordinal), "pt-BR: the painted option");
            Loc.Set("en");
            var keys = new HashSet<string>(LocPhase8A.PtBr.Keys);
            check(keys.Count > 70, "pt-BR: the phase 8A table has its entries: " + keys.Count);
            // the {n} placeholders of every entry match
            int bad = 0;
            foreach (var kv in LocPhase8A.PtBr)
            {
                var a = System.Text.RegularExpressions.Regex.Matches(kv.Key, @"\{\d+\}").Cast<System.Text.RegularExpressions.Match>().Select(mm => mm.Value).OrderBy(s => s).ToList();
                var b = System.Text.RegularExpressions.Regex.Matches(kv.Value, @"\{\d+\}").Cast<System.Text.RegularExpressions.Match>().Select(mm => mm.Value).OrderBy(s => s).ToList();
                if (!a.SequenceEqual(b)) bad++;
            }
            check(bad == 0, "pt-BR: the placeholders of the phase 8A texts match: " + bad);
        }
    }
}
