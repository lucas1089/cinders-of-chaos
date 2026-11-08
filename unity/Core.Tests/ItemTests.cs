// Items and economy: rarity and tooltips (opcode 242), the outfit window (0xC8, 0xD2, 0xD3), modal windows (0xFA, 0xF9), text windows (0x96, 0x97,
// 0x89, 0x8D), the bank (60), the stash (110) and the store (218). Wire layouts: Core/Dialogs.cs and the files named there.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class ItemTests
    {
        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));
        static string Text(byte[] sent) => Encoding.UTF8.GetString(sent, 4, sent.Length - 4);

        public static void Run(Action<bool, string> check)
        {
            Rarity(check);
            Tooltip(check);
            TipRequests(check);
            OutfitWindow(check);
            Modal(check);
            TextWindow(check);
            Bank(check);
            Stash(check);
            Store(check);
            Labels(check);
        }

        static GameParser ChaosParser(DatFile dat)
        {
            var p = new GameParser(new World(dat)) { Identity = ClientIdentity.Chaos(1) };
            p.Parse(new ByteWriter().U8(0x43).U16(1).U8(126).U8(1).ToArray());
            return p;
        }

        static void Rarity(Action<bool, string> check)
        {
            check(ItemRarity.Canon(1) == 1 && ItemRarity.Canon(7) == 5 && ItemRarity.Canon(13) == 10 && ItemRarity.Canon(0) == 0 && ItemRarity.Canon(99) == 0, "rarity: ids 6 .. 9 are Legendary, 11 .. 15 Divine, unknown is none");
            check(ItemRarity.Name(4) == "Rare" && ItemRarity.Color(4) == "#a35cf0" && ItemRarity.Color(10) == "#c8e8ff" && ItemRarity.Color(0) == null, "rarity: names and colours");
            var plain = new Item { Id = 100 };
            var rare = new Item { Id = 100, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Rarity, 4 } } };
            var unique = new Item { Id = 100, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Rarity, 3 }, { ItemAttr.Unique, 1 }, { ItemAttr.Locked, 1 } } };
            var old = new Item { Id = 100, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Rarity, 8 } } };
            check(ItemRarity.FrameColor(plain) == null && ItemRarity.FrameColor(null) == null && ItemRarity.Of(plain) == 0, "rarity: an item without attributes has no frame");
            check(ItemRarity.FrameColor(rare) == "#a35cf0" && ItemRarity.FrameColor(unique) == ItemRarity.UniqueColor && ItemRarity.IsLocked(unique) && !ItemRarity.IsLocked(rare), "rarity: the unique colour wins, locked is its own flag");
            check(ItemRarity.Of(old) == 5 && ItemRarity.FrameColor(old) == "#ffd040", "rarity: an old Legendary id draws as Legendary");
            check(ItemRarity.FrameColor(3, false) == "#4a90ff" && ItemRarity.FrameColor(0, false) == null && ItemRarity.FrameColor(3, true) == ItemRarity.UniqueColor, "rarity: the stash list's rarity id");

            // attributes read by the parser reach the frame: a text window's item carries them
            var dat = DatFile.Parse(Program.SyntheticDat());
            var p = ChaosParser(dat);
            p.Parse(new ByteWriter().U8(0x78).U8(4).U16(100).U8(0xFF).U16(2).U16(1).U32(4).U32(0).U16(4).U32(1).U32(0).ToArray());
            check(ItemRarity.FrameColor(p.Inventory[4]) == ItemRarity.UniqueColor && ItemRarity.Of(p.Inventory[4]) == 4, "rarity: 0x78 carries the attributes into the equipment slot");
        }

        static void Tooltip(Action<bool, string> check)
        {
            Loc.Set("en");
            string json = "{\"id\":101,\"name\":\"fiery wand\",\"count\":1,\"rarity\":4,\"rarityName\":\"Rare\",\"slot\":\"Wand\",\"level\":120,\"maxTier\":6," +
                "\"quality\":{\"q\":8,\"cap\":20},\"base\":[{\"k\":\"attack\",\"l\":\"Attack\",\"v\":14,\"fmt\":\"num\"},{\"k\":\"speed\",\"l\":\"Attack speed\",\"v\":0.5,\"fmt\":\"sec\"}]," +
                "\"sides\":{\"p\":1,\"s\":1,\"max\":3},\"mods\":[{\"t\":\"+12 fire damage\",\"tr\":5,\"sd\":\"p\",\"lo\":10,\"hi\":14,\"g\":\"element\"},{\"t\":\"+3% haste\",\"tr\":2,\"sd\":\"s\",\"lo\":3,\"hi\":3,\"bd\":true}]," +
                "\"sockets\":{\"count\":2,\"list\":[{\"name\":\"Ruby\",\"text\":\"+4 fire\",\"color\":\"#ff4040\"},{}]},\"req\":{\"level\":150,\"magic\":40,\"voc\":\"Sorcerer\"}," +
                "\"desc\":\"A wand that is warm to the touch and never goes out.\",\"locked\":true,\"charges\":{\"n\":1200,\"max\":14400},\"weight\":23.5}";
            object tip = Json.Parse(json);
            var lines = TipLines.Lines(tip, 100);
            string all = string.Join("\n", lines.Select(l => l.Text));
            check(lines[0].Text == "Rare Wand" && lines[0].Color == "#a35cf0", "tooltip: the kind line is rarity and slot in the rarity colour");
            check(all.Contains("Item Level 120  (up to T6)") && all.Contains("Quality +8%  (up to 20%)"), "tooltip: item level and quality");
            check(all.Contains("Attack: 14") && all.Contains("Attack speed: 0.5s (2/s)"), "tooltip: base rows, the interval with swings per second");
            check(all.Contains("Prefixes 1/3") && all.Contains("Suffixes 1/3") && all.Contains("T5 +12 fire damage [10-14]") && all.Contains("T2 +3% haste [3] [bound]"), "tooltip: side headers with counts, tier, range, bound");
            var fire = lines.First(l => l.Text.StartsWith("T5 ", StringComparison.Ordinal));
            check(fire.Color == TipLines.Element && fire.Parts != null && fire.Parts[1] == TipLines.TierColor(5), "tooltip: an element modifier is orange, its tier tag has the tier colour");
            check(all.Contains("Sockets 1/2") && all.Contains("  Ruby: +4 fire") && all.Contains("  empty socket"), "tooltip: sockets and gems");
            var need = lines.First(l => l.Text.StartsWith("Requires level", StringComparison.Ordinal));
            check(need.Text == "Requires level 150" && need.Color == TipLines.Red && TipLines.Lines(tip, 200).First(l => l.Text.StartsWith("Requires level", StringComparison.Ordinal)).Color == TipLines.Dim,
                  "tooltip: a level requirement above the character's is red");
            check(all.Contains("Requires magic level 40") && all.Contains("For Sorcerer") && all.Contains("Locked") && all.Contains("Charges: 1,200 of 14,400") && all.Contains("Weight 23.5 oz"), "tooltip: requirements, locked, charges, weight");
            check(lines.All(l => l.Text.Length > 0) && lines.Count(l => l.Sep) >= 4, "tooltip: no empty line, blocks are separated");

            // unique with a passive and a set, no rarity name
            object uniq = Json.Parse("{\"id\":100,\"name\":\"relic\",\"unique\":{\"name\":\"X\",\"set\":{\"name\":\"Dawn\",\"have\":2,\"total\":4,\"pieces\":[{\"n\":\"Helm\",\"eq\":true},{\"n\":\"Boots\",\"low\":true,\"lv\":300}],\"bonuses\":[{\"n\":2,\"t\":\"+5% speed\",\"on\":true}]}}," +
                "\"passive\":{\"name\":\"Ember\",\"text\":\"Burns what it hits.\",\"flavor\":\"Old.\"}}");
            var ul = TipLines.Lines(uniq, 1);
            string ua = string.Join("\n", ul.Select(l => l.Text));
            check(ul[0].Text == "Set" && TipLines.TitleColor(uniq) == TipLines.SetC && ua.Contains("Set: Dawn (2/4)") && ua.Contains("  Helm") && ua.Contains("  Boots (level 300)") && ua.Contains("(2) +5% speed") && ua.Contains("Ember") && ua.Contains("Burns what it hits."),
                  "tooltip: a set piece shows the set block and the passive");
            check(TipLines.Title("magic sword") == "Magic sword" && TipLines.WrapText("one two three four", 9).Count == 3 && TipLines.Int(12345.7) == "12,345" && TipLines.Trim(2.5) == "2.5" && TipLines.Trim(3) == "3", "tooltip: helpers");
            Loc.Set("pt-BR");
            check(TipLines.Lines(tip, 100)[0].Text.StartsWith("Rara", StringComparison.Ordinal), "tooltip: the rarity name follows the language");
            Loc.Set("en");
        }

        static void TipRequests(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            double now = 1000;
            var tips = new ItemTips(ext) { Clock = () => now };
            var coin = new Item { Id = 101, Count = 9, Type = DatFile.Parse(Program.SyntheticDat()).Item(101), Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Id, 123456789012UL }, { ItemAttr.Version, 3 } } };
            var d = ItemTips.Describe(coin, new Pos(0xFFFF, 0x41, 2));
            check(d.Key == "123456789012:3" && !d.Plain && d.Count == 9 && d.Cid == 101 && d.PosKey == "65535,65,2,123456789012", "tips: a per-item id and version make the cache key, a stackable names its count");
            var plain = ItemTips.Describe(new Item { Id = 100 }, new Pos(0xFFFF, 4, 0));
            check(plain.Plain && plain.Key == "p:65535:4:0:100:1" && plain.Count == 0, "tips: a plain item is cached under its position");
            check(ItemTips.Askable(new Pos(0xFFFF, 4, 0)) && ItemTips.Askable(new Pos(0xFFFF, 0x42, 1)) && !ItemTips.Askable(new Pos(100, 100, 7)) && !ItemTips.Askable(new Pos(0xFFFF, 0x50, 0)), "tips: only the inventory and open containers");

            check(tips.Lookup(d, now) == null && sent.Count == 0, "tips: the first look waits for the hover delay");
            now += 30;
            check(tips.Lookup(d, now) == null && sent.Count == 0, "tips: still no request under 60 ms");
            now += 40;
            check(tips.Lookup(d, now) == null && sent.Count == 1 && tips.Asked == 1, "tips: after 60 ms one request goes out");
            check(Text(sent[0]) == "{\"action\":\"get\",\"data\":{\"items\":[{\"pos\":{\"x\":65535,\"y\":65,\"z\":2},\"iid\":\"123456789012\",\"cid\":101,\"n\":9}]}}", "tips: the request names position, per-item id as a string, client id and count: " + Text(sent[0]));
            now += 100;
            tips.Lookup(d, now);
            check(sent.Count == 1, "tips: no second request while one is open");

            // an answer for another item (the slots shifted) is not kept, the hover asks again after a short wait
            string wrong = "{\"action\":\"tips\",\"data\":{\"items\":[{\"pos\":{\"x\":65535,\"y\":65,\"z\":2},\"iid\":\"123456789012\",\"tip\":{\"id\":100,\"count\":1,\"name\":\"rope\"}}]}}";
            ext.Receive(242, ExtOpcodes.ToWire(wrong));
            check(tips.Mismatches == 1 && tips.CacheCount == 0, "tips: an answer for another item is dropped");
            now += 400;
            tips.Lookup(d, now);
            check(sent.Count == 2, "tips: the hover asks again");
            string right = "{\"action\":\"tips\",\"data\":{\"items\":[{\"pos\":{\"x\":65535,\"y\":65,\"z\":2},\"iid\":\"123456789012\",\"tip\":{\"id\":101,\"count\":9,\"name\":\"coin\",\"rarity\":2}}]}}";
            ext.Receive(242, ExtOpcodes.ToWire(right));
            var got = tips.Lookup(d, now);
            check(got != null && Json.Text(got, "name") == "coin" && tips.CacheCount == 1 && tips.Answers == 2, "tips: the right answer is cached and found");
            check(tips.Lookup(d, now + 1000000) != null, "tips: an item with a per-item id never expires");

            // a plain item expires after 30 s
            var pd = ItemTips.Describe(new Item { Id = 100 }, new Pos(0xFFFF, 4, 0));
            tips.Lookup(pd, now); now += 100; tips.Lookup(pd, now);
            ext.Receive(242, ExtOpcodes.ToWire("{\"action\":\"tips\",\"data\":{\"items\":[{\"pos\":{\"x\":65535,\"y\":4,\"z\":0},\"iid\":\"0\",\"tip\":{\"id\":100,\"name\":\"club\"}}]}}"));
            check(tips.Lookup(pd, now + 1000) != null && tips.Lookup(pd, now + 31000) == null, "tips: a plain item's tooltip is kept 30 s");

            // set pieces are dropped when the equipment changes
            string setTip = "{\"action\":\"tips\",\"data\":{\"items\":[{\"pos\":{\"x\":65535,\"y\":3,\"z\":0},\"iid\":\"0\",\"tip\":{\"id\":100,\"name\":\"helm\",\"set\":{\"name\":\"Dawn\"}}}]}}";
            var sd = ItemTips.Describe(new Item { Id = 100 }, new Pos(0xFFFF, 3, 0));
            tips.Lookup(sd, now + 40000); tips.Lookup(sd, now + 40100);
            ext.Receive(242, ExtOpcodes.ToWire(setTip));
            int before = tips.CacheCount;
            check(tips.DropSetTips() == 1 && tips.CacheCount == before - 1, "tips: a set piece's tooltip goes when the equipment changes");

            // a position outside the inventory and the containers is never asked
            sent.Clear();
            var ground = ItemTips.Describe(new Item { Id = 100 }, new Pos(100, 100, 7));
            tips.Lookup(ground, now + 50000); tips.Lookup(ground, now + 50100);
            check(sent.Count == 0, "tips: the ground is not asked about");
            tips.Reset();
            check(tips.CacheCount == 0, "tips: reset forgets everything");
        }

        static void OutfitWindow(Action<bool, string> check)
        {
            var dat = DatFile.Parse(Program.SyntheticDat());
            // plain 10.98 window: the outfit, 2 outfits, 1 mount
            var plain = new GameParser(new World(dat));
            var w = new ByteWriter().U8(0xC8).U16(1).U8(1).U8(2).U8(3).U8(4).U8(1).U16(0)
                .U8(2).U16(1).Str("Citizen").U8(0).U16(2).Str("Hunter").U8(3)
                .U8(1).U16(368).Str("Racing Bird");
            plain.Parse(w.ToArray());
            var st = plain.Outfits;
            check(st.Open && st.Opens == 1 && st.Current.LookType == 1 && st.Current.Head == 1 && st.Current.Addons == 1 && st.Outfits.Count == 2 && st.Outfits[1].Name == "Hunter" && st.Outfits[1].Addons == 3 &&
                  st.Mounts.Count == 1 && st.Mounts[0].Id == 368 && !st.HasExtras, "outfit window: 0xC8 of the plain wire");
            check(st.AddonsOf(2) == 3 && st.AddonsOf(1) == 0 && st.AddonsOf(9) == 0, "outfit window: the addons a look allows");
            var worn = new Outfit(1, 1, 2, 3, 4, 3);
            var moved = st.WithLook(worn, 1);
            check(moved.Addons == 0 && moved.Head == 1 && st.WithLook(worn, 2).Addons == 3, "outfit window: switching the look clears addons it does not allow");

            // Chaos wire: the current outfit has wings, aura and shader, then the lists
            var chaos = new GameParser(new World(dat)) { Identity = ClientIdentity.Chaos(1) };
            var c = new ByteWriter().U8(0xC8).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0).U16(7).U16(9).Str("fire")
                .U8(1).U16(1).Str("Citizen").U8(3).U8(0)
                .U8(1).U16(2200).Str("Angel Wings").U8(2).U16(30).Str("Flame").U16(31).Str("Frost").U8(1).U8(21).Str("blue_Dortmond");
            chaos.Parse(c.ToArray());
            var cs = chaos.Outfits;
            check(cs.HasExtras && cs.Current.Wings == 7 && cs.Current.Shader == "fire" && cs.Wings[0].Id == 2200 && cs.Wings[0].Name == "Angel Wings" && cs.Auras.Count == 2 && cs.Auras[1].Name == "Frost" &&
                  cs.Shaders.Count == 1 && cs.Shaders[0].Id == 21 && cs.Shaders[0].Name == "blue_Dortmond", "outfit window: wings, auras (u16 ids) and shaders (byte ids) on the Chaos wire");
            // shaders with u16 ids: the fallback width
            var wide = new GameParser(new World(dat)) { Identity = ClientIdentity.Chaos(1) };
            var wd = new ByteWriter().U8(0xC8).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0).U16(0).U16(0).Str("")
                .U8(0).U8(0).U8(0).U8(0).U8(1).U16(300).Str("gold");
            wide.Parse(wd.ToArray());
            check(wide.Outfits.Shaders.Count == 1 && wide.Outfits.Shaders[0].Id == 300 && wide.Outfits.Shaders[0].Name == "gold", "outfit window: a shader id of 16 bits is read when the byte width does not fit");
            // a following message in the same payload is still read
            var two = new GameParser(new World(dat));
            two.Parse(new ByteWriter().U8(0xC8).U16(1).U8(1).U8(2).U8(3).U8(4).U8(0).U16(0).U8(0).U8(0).U8(0x1D).ToArray());
            check(two.Outfits.Open && two.Seen.ContainsKey(0x1D), "outfit window: the message ends where it should");
            // the window smoke's fake server answers 0xD2 with it (the window was empty, "Asking the server...")
            var smoke = new GameParser(new World(dat));
            var tourArt = TourArt.FromDemo(DemoIds.Synthetic());
            smoke.Parse(new ByteWriter().Raw(FakeGameServer.OutfitWindow(tourArt)).U8(0x1D).ToArray());
            check(smoke.Outfits.Opens == 1 && smoke.Outfits.Current.LookType == tourArt.OutfitHero && smoke.Outfits.Outfits.Count == 2 && smoke.Outfits.Outfits[1].Name == "Warden" && smoke.Outfits.Mounts.Count == 0 && smoke.Seen.ContainsKey(0x1D),
                  "outfit window: the fake server's answer to 0xD2 reads whole, two outfits, no mounts");

            // packets
            check(Hex(OutfitWindowState.RequestPacket()) == "d2" && Hex(OutfitWindowState.ToggleMountPacket(true)) == "d401", "outfit window: request 0xD2 and mount toggle 0xD4");
            check(Hex(OutfitWindowState.SetPacket(new Outfit(2, 10, 20, 30, 40, 3, 368), false)) == "d3" + "0200" + "0a141e28" + "03" + "7001", "outfit window: 0xD3 of the plain wire: look, colours, addons, mount");
            var look = new Outfit(2, 1, 2, 3, 4, 0, 0) { Wings = 7, Aura = 9, Shader = "fire" };
            check(Hex(OutfitWindowState.SetPacket(look, true)) == "d3" + "0200" + "01020304" + "00" + "0000" + "0700" + "0900" + "0400" + "66697265", "outfit window: 0xD3 with the markers adds wings, aura and the shader name");
            var sentPackets = new List<byte[]>();
            st.Send = p => sentPackets.Add(p);
            st.Request(); st.Apply(worn, false);
            check(sentPackets.Count == 2 && sentPackets[0][0] == 0xD2 && sentPackets[1][0] == 0xD3 && !st.Open, "outfit window: Apply sends and closes");
        }

        static void Modal(Action<bool, string> check)
        {
            var p = new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));
            var w = new ByteWriter().U8(0xFA).U32(77).Str("Choose").Str("Pick one.").U8(2).Str("Ok").U8(1).Str("Cancel").U8(2).U8(2).Str("Red").U8(1).Str("Blue").U8(2).U8(2).U8(1).U8(1);
            p.Parse(w.ToArray());
            var m = p.Modals.Current;
            check(m != null && m.Id == 77 && m.Title == "Choose" && m.Message == "Pick one." && m.Buttons.Count == 2 && m.Buttons[1].Text == "Cancel" && m.Buttons[1].Id == 2 && m.Choices.Count == 2 && m.Choices[1].Id == 2 &&
                  m.EscapeButton == 2 && m.EnterButton == 1 && m.Priority, "modal: 0xFA layout");
            // a second window with the same id replaces it, a priority one goes first
            p.Parse(new ByteWriter().U8(0xFA).U32(78).Str("B").Str("later").U8(0).U8(0).U8(0).U8(0).U8(0).ToArray());
            check(p.Modals.Queue.Count == 2 && p.Modals.Current.Id == 77, "modal: windows queue in order, the priority one first");
            check(Hex(ModalWindows.AnswerPacket(77, 1, 2)) == "f9" + "4d000000" + "01" + "02", "modal: the answer is 0xF9, id, button, choice");
            var sent = new List<byte[]>();
            p.Modals.Send = s => sent.Add(s);
            p.Modals.Answer(1, 2);
            check(Hex(sent[0]) == "f94d0000000102" && p.Modals.Current.Id == 78, "modal: answering sends and shows the next");
            p.Modals.Cancel();
            check(Hex(sent[1]) == "f94e00000000" + "ff" && p.Modals.Current == null && !p.Modals.Cancel(), "modal: escape answers with the escape button and no choice");
        }

        static void TextWindow(Action<bool, string> check)
        {
            var dat = DatFile.Parse(Program.SyntheticDat());
            var p = ChaosParser(dat);
            // a read-only sign: item 100 with one attribute, length = text length
            var w = new ByteWriter().U8(0x96).U32(5).U16(100).U8(0xFF).U16(1).U16(4).U32(2).U32(0).U16(5).Str("Hello").Str("Ann").Str("2026-11-01");
            p.Parse(w.ToArray());
            var t = p.Texts.Current;
            check(t != null && t.Id == 5 && t.Item.Id == 100 && t.Item.Attr(ItemAttr.Rarity) == 0 && t.Item.Attr(4) == 2 && t.Text == "Hello" && t.Writer == "Ann" && t.Date == "2026-11-01" && !t.CanWrite, "text window: 0x96 of a sign, the item carries attributes");
            // a writable book: max length above the text length
            p.Parse(new ByteWriter().U8(0x96).U32(6).U16(100).U8(0xFF).U16(0).U16(100).Str("Draft").U16(0).U16(0).ToArray());
            t = p.Texts.Current;
            check(t.CanWrite && t.MaxLength == 100 && t.Text == "Draft" && t.Writer == "" && t.Date == "", "text window: 0x96 of a book you can write in");
            var sent = new List<byte[]>();
            p.Texts.Send = s => sent.Add(s);
            p.Texts.Close("Done");
            check(Hex(sent[0]) == "89" + "06000000" + "0400" + "446f6e65" && p.Texts.Current == null, "text window: 0x89 write text");
            p.Texts.Close("again");
            check(sent.Count == 1, "text window: closing with no window sends nothing");
            p.Parse(new ByteWriter().U8(0x96).U32(7).U16(100).U8(0xFF).U16(0).U16(4).Str("Read").U16(0).U16(0).ToArray());
            p.Texts.Close("x");
            check(sent.Count == 1, "text window: a read-only window sends nothing back");
            p.Parse(new ByteWriter().U8(0x96).U32(8).U16(100).U8(0xFF).U16(0).U16(200).Str("").U16(0).U16(0).ToArray());
            p.Texts.Close(null);
            check(sent.Count == 1, "text window: cancel sends nothing");
            p.Parse(new ByteWriter().U8(0x96).U32(9).U16(100).U8(0xFF).U16(0).U16(4).Str("").U16(0).U16(0).ToArray());
            p.Texts.Close("abcdefgh");
            check(sent.Count == 2 && Hex(sent[1]) == "89" + "09000000" + "0400" + "61626364", "text window: the text is cut to the max length");

            // house window 0x97
            p.Parse(new ByteWriter().U8(0x97).U8(0).U32(21).Str("Ann\nBob").ToArray());
            t = p.Texts.Current;
            check(t.House && t.Id == 21 && t.Text == "Ann\nBob" && t.CanWrite, "text window: 0x97 door list");
            p.Texts.Close("Ann");
            check(Hex(sent[2]) == "8d" + "00" + "15000000" + "0300" + "416e6e", "text window: the door list answer is 0x8D");

            // the plain wire has no attribute list after the item
            var plain = new GameParser(new World(dat));
            plain.Parse(new ByteWriter().U8(0x96).U32(3).U16(100).U8(0xFF).U16(3).Str("abc").Str("").Str("").ToArray());
            check(plain.Texts.Current.Text == "abc" && plain.Texts.Current.Item.Attrs == null, "text window: the plain wire has no attributes");
        }

        static void Bank(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var bank = new BankState(ext);
            bank.Show();
            check(bank.Visible && bank.Pending && Text(sent[0]) == "{\"action\":\"openBank\"}", "bank: Show asks for the state at once");
            ext.Receive(60, ExtOpcodes.ToWire("{\"action\":\"open\",\"data\":[1500,250000,0,0]}"));
            check(bank.HasState && bank.GoldCarried == 1500 && bank.GoldBank == 250000 && bank.Visible && !bank.Pending && bank.Limit(BankMode.Deposit) == 1500 && bank.Limit(BankMode.Withdraw) == 250000 && bank.Limit(BankMode.Transfer) == 250000,
                  "bank: the open reply fills the balances and limits");
            sent.Clear();
            check(bank.Do(BankMode.Deposit, 99999, null) && Text(sent[0]) == "{\"action\":\"deposit\",\"data\":[\"gold\",1500]}", "bank: a deposit is clamped to the gold carried: " + Text(sent[0]));
            check(bank.Do(BankMode.Withdraw, 40, null) && Text(sent[1]) == "{\"action\":\"withdraw\",\"data\":[\"gold\",40]}", "bank: withdraw");
            check(!bank.Do(BankMode.Transfer, 10, " x ") && bank.Do(BankMode.Transfer, 10, " Anna ") && Text(sent[2]) == "{\"action\":\"transfer\",\"data\":[\"gold\",\"Anna\",10]}", "bank: a transfer needs a name of two letters, spaces are trimmed");
            check(!bank.Do(BankMode.Deposit, 0, null) && sent.Count == 3, "bank: nothing to send for zero");
            bank.DepositAll(); bank.WithdrawAll();
            check(Text(sent[3]) == "{\"action\":\"depositAll\",\"data\":[\"gold\"]}" && Text(sent[4]) == "{\"action\":\"withdrawAll\",\"data\":[\"gold\"]}", "bank: deposit all and withdraw all");
            bank.Hide();
            ext.Receive(60, ExtOpcodes.ToWire("{\"action\":\"open\",\"data\":[1,2,0,0]}"));
            check(!bank.Visible && bank.GoldCarried == 1 && bank.GoldBank == 2, "bank: a reply to nobody keeps the state and does not open the window");
            ext.Receive(60, ExtOpcodes.ToWire("{\"action\":\"npc\",\"data\":{}}"));
            check(bank.Visible && bank.Pending, "bank: the banker NPC opens the window");
            check(BankMath.Digits("a1b2c3") == "123" && BankMath.Digits("12345678901234") == "1234567890" && BankMath.Parse("500", 300) == 300 && BankMath.Parse("", 300) == 0 && BankMath.QuickAmount(1001, 25) == 250 && BankMath.QuickAmount(1001, 100) == 1001, "bank: digits, clamp and quick amounts");
            bank.Clear();
            check(!bank.HasState && !bank.Visible && bank.GoldBank == 0, "bank: a new character does not see the old balance");
        }

        static void Stash(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var st = new StashState(ext);
            st.Prefetch(); st.Show();
            check(Text(sent[0]) == "{\"action\":\"Stash\",\"data\":{\"make\":\"SendCategories\",\"sendBlocks\":true}}" && Text(sent[1]) == "{\"action\":\"Stash\",\"data\":{\"make\":\"SendItems\"}}" && st.Visible && st.Opening, "stash: categories and items are asked for");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"tabs\",\"tabs\":[{\"id\":1,\"name\":\"General\",\"used\":2,\"size\":30},{\"id\":2,\"name\":\"Weapons\",\"used\":1,\"size\":25,\"affinity\":true,\"icon\":3264}]," +
                "\"canWithdraw\":true,\"canDeposit\":false,\"depositWhy\":\"pz\",\"store\":\"Storage & Slots\",\"inbox\":3,\"slots\":30}}"));
            check(st.HasTabs && st.Tabs.Count == 2 && st.Tabs[1].Affinity && st.Tabs[1].Icon == 3264 && st.CanWithdraw && !st.CanDeposit && st.StoreCategory == "Storage & Slots" && st.InboxCount == 3 && StashState.TabLabel(st.Tabs[0]) == "General 2/30", "stash: tabs and what is allowed");
            // the item list comes in batches, shown when the last one has arrived
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"addItems\",\"isFirst\":true,\"isLast\":false,\"items\":[{\"sprite\":2160,\"count\":120,\"name\":\"Crystal Coin\",\"tooltip\":\"x\",\"id\":2160,\"uniqueId\":2160,\"typee\":\"supplies\",\"tab\":1}]}}"));
            check(!st.ItemsLoaded && st.Items.Count == 0, "stash: items are held until the last batch");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"addItems\",\"isFirst\":false,\"isLast\":true,\"items\":[{\"sprite\":3264,\"count\":1,\"name\":\"Fire Sword\",\"tooltip\":\"Fire Sword\\nAmount: 1\",\"id\":3264,\"uniqueId\":3264,\"typee\":\"weapons\",\"tab\":2,\"row\":55,\"rarity\":4}]}}"));
            check(st.ItemsLoaded && st.Items.Count == 2 && !st.Opening && st.Items[1].Row == 55 && st.Items[1].Rarity == 4 && st.Items[0].Row == -1, "stash: both batches are in");
            // a new first batch replaces the list
            check(st.View(0, "", false)[0].Name == "Crystal Coin" && st.View(2, "", false).Count == 1 && st.View(0, "fire", false).Count == 1 && st.View(0, "", true)[0].Name == "Crystal Coin", "stash: filter by tab and search, sorted by amount or name");

            sent.Clear();
            check(!st.Deposit(new Pos(0xFFFF, 0x41, 3), 3, 101, 9), "stash: no deposit while the server says it is closed");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"access\",\"canDeposit\":true}}"));
            check(st.CanDeposit && st.Deposit(new Pos(0xFFFF, 0x41, 3), 3, 101, 9) && Text(sent[0]) == "{\"action\":\"Stash\",\"data\":{\"make\":\"Stash\",\"Pos\":{\"x\":65535,\"y\":65,\"z\":3,\"stackpos\":3},\"ItemId\":101,\"Count\":9,\"UpdateList\":true}}", "stash: a deposit names the position, item id and count: " + (sent.Count > 0 ? Text(sent[0]) : ""));
            check(st.Redeem(st.Items[1], 1) && Text(sent[1]) == "{\"action\":\"Stash\",\"data\":{\"make\":\"Redeem\",\"row\":55}}", "stash: a stored item is taken out by its row");
            check(st.Redeem(st.Items[0], 500) && Text(sent[2]) == "{\"action\":\"Stash\",\"data\":{\"make\":\"Redeem\",\"item\":2160,\"id\":2160,\"count\":120}}", "stash: a stack is taken out by item id, the count capped to the stack");
            check(st.StowAll() && Text(sent[3]).Contains("StashAllRequest") && st.CollectInbox() && Text(sent[4]).Contains("CollectInbox"), "stash: stow everything and collect inbox");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"access\",\"canWithdraw\":false}}"));
            check(!st.CanWithdraw && !st.Redeem(st.Items[0], 1) && st.LockedLine(true).Length > 0 && st.LockedLine(false) == "", "stash: a refused withdrawal shuts the button and says why");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"StowReport\",\"stowed\":12,\"kept\":3,\"reasons\":[{\"reason\":\"locked\",\"label\":\"locked items\",\"count\":3}]}}"));
            check(st.StowReport == "Stowed 12, kept 3. locked items (3)", "stash: the stow report: " + st.StowReport);
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"Toggle\",\"remote\":false}}"));
            check(!st.Visible, "stash: Toggle while open closes it (as the main client)");
            ext.Receive(110, ExtOpcodes.ToWire("{\"action\":\"Stash\",\"data\":{\"make\":\"Toggle\",\"open\":true}}"));
            check(st.Visible, "stash: a keeper NPC's Toggle opens it");
            st.Clear();
            check(st.Items.Count == 0 && !st.Visible && !st.HasTabs, "stash: clear");
        }

        static void Store(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var sent = new List<byte[]>();
            ext.Transmit = p => sent.Add(p);
            var st = new StoreState(ext);
            st.Show();
            check(st.Visible && Text(sent[0]) == "{\"action\":\"init\",\"data\":{}}", "store: Show sends init");
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"category_groups\",\"data\":[{\"name\":\"Cosmetics\",\"type\":\"item\",\"item\":1,\"size\":5}]}"));
            string cats = "{\"action\":\"categories\",\"data\":[{\"name\":\"Featured\",\"type\":\"item\",\"item\":2160,\"count\":1,\"pages\":1,\"size\":4}," +
                "{\"name\":\"Wings\",\"type\":\"outfit\",\"outfit\":{\"type\":128,\"head\":2},\"pages\":2,\"size\":3,\"parent\":\"Cosmetics\"},{\"name\":\"Auras\",\"type\":\"item\",\"item\":5,\"pages\":1,\"size\":2,\"parent\":\"Cosmetics\"}]," +
                "\"status\":{\"points\":1250,\"buyUrl\":\"https://example.invalid/coins\",\"ad\":{}}}";
            ext.Receive(218, ExtOpcodes.ToWire(cats));
            check(st.Categories.Count == 3 && st.Coins == 1250 && st.Selected == 1 && st.Tree.Count == 2 && st.Tree[1].Group && st.Tree[1].Children.Count == 2 && st.Tree[1].Size == 5, "store: categories make a tree, the group's size is the server's, the coin balance is read");
            check(Text(sent[1]) == "{\"action\":\"get_page\",\"data\":{\"category\":1,\"page\":1}}", "store: the first category's first page is asked for: " + Text(sent[1]));
            string page = "{\"action\":\"category_page\",\"data\":{\"category\":1,\"page\":1,\"offers\":[{\"type\":\"item\",\"item\":2160,\"count\":10,\"title\":\"Orb Pack\",\"description\":\"Ten orbs.\",\"cost\":300,\"oldCost\":400,\"tags\":[\"SALE\"],\"gift\":true}," +
                "{\"type\":\"outfit\",\"outfit\":{\"type\":128,\"head\":2,\"wings\":7},\"title\":\"Wings\",\"description\":\"d\",\"cost\":900,\"owned\":true}]}}";
            ext.Receive(218, ExtOpcodes.ToWire(page));
            check(st.Offers.Count == 2 && st.Offers[0].Title == "Orb Pack" && st.Offers[0].Cost == 300 && st.Offers[0].OldCost == 400 && st.Offers[0].Tags[0] == "SALE" && st.Offers[0].Buyable && st.Offers[1].Owned && st.Offers[1].Outfit.Wings == 7 && st.Offers[1].Row == 2, "store: a page of offers");
            check(!st.AskBuy(st.Offers[1]) && st.AskBuy(st.Offers[0]) && st.ConfirmOffer == st.Offers[0], "store: an owned offer cannot be bought, a buy asks first");
            st.CancelBuy();
            check(st.ConfirmOffer == null && sent.Count == 2, "store: cancel sends nothing");
            st.AskBuy(st.Offers[0]);
            check(st.ConfirmBuy() && Text(sent[2]) == "{\"action\":\"buy\",\"data\":{\"category\":1,\"page\":1,\"offer\":1,\"title\":\"Orb Pack\",\"cost\":300}}" && st.ConfirmOffer == null, "store: the confirmed buy echoes title and cost: " + Text(sent[2]));
            check(!st.ConfirmBuy(), "store: nothing to confirm twice");
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"message\",\"data\":{\"title\":\"Bought\",\"msg\":\"You bought Orb Pack.\"},\"status\":{\"points\":950}}"));
            check(st.Messages == 1 && st.MessageText == "You bought Orb Pack." && st.Coins == 950, "store: the answer of a purchase and the new balance");

            // the group click opens its first subcategory
            sent.Clear();
            st.ClickGroup("Cosmetics");
            check(st.Expanded == "Cosmetics" && st.Selected == 2 && Text(sent[0]) == "{\"action\":\"get_page\",\"data\":{\"category\":2,\"page\":1}}" && StoreTree.Rows(st.Tree, st.Expanded).Count == 4, "store: a group opens and selects its first subcategory");
            check(st.TotalPages == 2, "store: pages of the selected category");
            st.GoPage(1);
            check(Text(sent[1]) == "{\"action\":\"get_page\",\"data\":{\"category\":2,\"page\":2}}", "store: next page");
            st.ClickGroup("Cosmetics");
            check(st.Expanded == "", "store: a click on the open group closes it");

            // search
            sent.Clear();
            st.Search("w");
            check(sent.Count == 0, "store: a search under 2 letters sends nothing");
            st.Search(" wings ");
            check(Text(sent[0]) == "{\"action\":\"search\",\"data\":{\"text\":\"wings\"}}" && st.Searching == "wings", "store: search is trimmed");
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"search_results\",\"data\":{\"text\":\"wings\",\"offers\":[{\"type\":\"item\",\"item\":1,\"title\":\"Angel Wings\",\"description\":\"Big.\",\"cost\":500,\"at\":{\"category\":2,\"page\":1,\"offer\":3},\"path\":[\"Cosmetics\",\"Wings\"]}]}}"));
            check(st.Offers.Count == 1 && st.Offers[0].Category == 2 && st.Offers[0].Row == 3 && st.Offers[0].Description == "Cosmetics > Wings: Big.", "store: search results know where the server has them");
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"search_results\",\"data\":{\"text\":\"old\",\"offers\":[]}}"));
            check(st.Offers.Count == 1, "store: results of an old search are dropped");
            sent.Clear();
            st.ShowHistory();
            check(Text(sent[0]) == "{\"action\":\"history\",\"data\":{}}" && st.BrowsingHistory, "store: history");
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"history\",\"data\":[{\"type\":\"item\",\"item\":1,\"title\":\"Orb Pack\",\"description\":\"2026-11-01\",\"cost\":300}]}"));
            check(st.Offers.Count == 1 && !st.Offers[0].Buyable, "store: a history line has no buy button");

            // payment messages and the buy URL are never used
            int msgs = st.Messages;
            ext.Receive(218, ExtOpcodes.ToWire("{\"action\":\"pay_qr\",\"data\":{\"code\":\"000201\"},\"status\":{\"points\":999999}}"));
            check(st.Messages == msgs && st.Coins == 950, "store: pay_ messages (donations) are ignored in full");
            check(Regex.IsMatch(File.ReadAllText(SourcePath("Store.cs")), "buyUrl") && !Regex.IsMatch(StripComments(File.ReadAllText(SourcePath("Store.cs"))), "openURL|OpenURL|Application\\.OpenURL"), "store: nothing opens the buy URL");
            st.Clear();
            check(!st.Visible && st.Categories.Count == 0 && st.Coins < 0, "store: clear");
        }

        static string StripComments(string s) => Regex.Replace(s, "//[^\n]*", "");

        static string SourcePath(string file)
        {
            string a = Path.GetFullPath(Path.Combine("..", "Client", "Assets", "Chaos", "Core", file));
            if (File.Exists(a)) return a;
            return Path.GetFullPath(Path.Combine("unity", "Client", "Assets", "Chaos", "Core", file));
        }

        static void Labels(Action<bool, string> check)
        {
            // the Core files name their texts with Loc.T: each needs a pt-BR text (the Unity sources are scanned by the loc check in ExtTests)
            var missing = new List<string>();
            foreach (string file in new[] { "ItemInfo.cs", "Stash.cs" })
            {
                string path = SourcePath(file);
                if (!File.Exists(path)) continue;
                foreach (Match m in Regex.Matches(File.ReadAllText(path), "\\bLoc\\.T\\(\"((?:[^\"\\\\]|\\\\.)*)\""))
                {
                    string key = m.Groups[1].Value.Replace("\\\"", "\"");
                    if (!LocStrings.PtBr.ContainsKey(key)) missing.Add(key);
                }
            }
            check(missing.Count == 0, "items: every Loc.T key of the Core item files has a pt-BR text" + (missing.Count > 0 ? ": " + string.Join(" | ", missing) : ""));
            check(LocStrings.PtBr["Bank"] == "Banco" && LocStrings.PtBr["Stash"] == "Baú", "items: pt-BR texts of LocItems are merged into LocStrings");
        }
    }
}
