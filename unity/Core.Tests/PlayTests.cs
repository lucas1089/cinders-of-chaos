// Checks of the base gameplay actions (track P): the packets the client sends (look, use with, use on a creature, rotate, trade, VIP, quest log) and the ones it reads
// (trade 0x7D / 0x7E / 0x7F, VIP 0xD2 / 0xD3, quest log 0xF0 / 0xF1, the badge slot 0x78 with slot 13), the picking rules of a map tile, the item menu, the crosshair,
// the guards (dead monsters, summons, Auto Target class order) and the look preview.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

namespace Chaos.Core.Tests
{
    static class PlayTests
    {
        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));

        public static void Run(Action<bool, string> check)
        {
            Packets(check);
            Picking(check);
            Menu(check);
            Crosshair(check);
            Trade(check);
            Vip(check);
            Quests(check);
            Guards(check);
            AutoTarget(check);
            Engine(check);
            Badge(check);
            Preview(check);
            Texts(check);
        }

        // ---------------------------------------------------------------------------------------------- packets out
        static void Packets(Action<bool, string> check)
        {
            var bag = new Pos(0xFFFF, 0x41, 3);
            check(Hex(PlayPackets.Look(new Pos(100, 200, 7), 2160, 2)) == "8c6400c80007700802", "play: look 0x8C pos, id, stack");
            check(Hex(PlayPackets.Look(bag, 3031, 3)) == "8cffff410003d70b03", "play: look in a bag");
            check(Hex(PlayPackets.LookCreature(0x10000001)) == "8d01000010", "play: look at a creature 0x8D");
            check(Hex(PlayPackets.Rotate(new Pos(1, 2, 3), 0x0102, 4)) == "850100020003" + "0201" + "04", "play: rotate 0x85");
            check(Hex(PlayPackets.UseWith(new Pos(0xFFFF, 5, 0), 100, 5, new Pos(10, 11, 7), 200, 1)) == "83ffff0500" + "00" + "6400" + "05" + "0a000b0007" + "c800" + "01", "play: use with 0x83 " + Hex(PlayPackets.UseWith(new Pos(0xFFFF, 5, 0), 100, 5, new Pos(10, 11, 7), 200, 1)));
            check(Hex(PlayPackets.UseOnCreature(new Pos(0xFFFF, 6, 0), 266, 6, 0x40000001)) == Hex(HelperPackets.UseWithCreature(new Pos(0xFFFF, 6, 0), 266, 6, 0x40000001)), "play: use on a creature is the helper's 0x84");
            check(Hex(PlayPackets.TradeRequest(new Pos(0xFFFF, 0x40, 1), 2160, 1, 7)) == "7dffff400001700801" + "07000000", "play: trade request 0x7D: pos, id, stack, player");
            check(Hex(PlayPackets.TradeLookIn(true, 2)) == "7e0102" && Hex(PlayPackets.TradeLookIn(false, 0)) == "7e0000", "play: look in trade 0x7E side, index");
            check(Hex(PlayPackets.TradeAccept()) == "7f" && Hex(PlayPackets.TradeClose()) == "80", "play: accept 0x7F, close 0x80");
            check(Hex(PlayPackets.VipAdd("Bob")) == "dc0300426f62", "play: VIP add 0xDC name");
            check(Hex(PlayPackets.VipRemove(0x01020304)) == "dd04030201", "play: VIP remove 0xDD guid");
            check(Hex(PlayPackets.VipEdit(5, "hi", 3, true)) == "de05000000" + "02006869" + "03000000" + "01", "play: VIP edit 0xDE guid, description, icon, notify");
            check(Hex(PlayPackets.QuestLog()) == "f0" && Hex(PlayPackets.QuestLine(0x0102)) == "f10201", "play: quest log 0xF0, quest line 0xF1 id");
        }

        // ---------------------------------------------------------------------------------------------- picking on a tile
        static Item It(int id, Action<ThingType> f = null) { var t = new ThingType { Id = id }; f?.Invoke(t); return new Item { Id = id, Type = t }; }
        static Thing Th(Item i) => new Thing { Item = i };
        static Thing Cr(Creature c) => new Thing { Creature = c };

        static void Picking(Action<bool, string> check)
        {
            var tile = new Tile(new Pos(50, 60, 7));
            var ground = It(100, t => t.Ground = true);
            var border = It(101, t => t.GroundBorder = true);
            var wall = It(102, t => t.OnBottom = true);
            var splash = It(103, t => t.Splash = true);
            var chest = It(104, t => { t.Container = true; t.Pickupable = false; });
            var coin = It(105, t => { t.Pickupable = true; t.Stackable = true; });
            var cr = new Creature { Id = 9, Type = 1 };
            foreach (var th in new[] { Th(ground), Th(border), Th(wall), Cr(cr), Th(splash), Th(chest), Th(coin) }) tile.Things.Add(th);
            check(TilePick.LookIndex(tile) == 3, "pick: look takes the first plain thing, a creature counts (" + TilePick.LookIndex(tile) + ")");
            check(TilePick.UseIndex(tile) == 5, "pick: use skips ground, wall, creature and splash: the chest (" + TilePick.UseIndex(tile) + ")");
            check(TilePick.TopCreature(tile) == cr, "pick: the top creature");
            var onlyGround = new Tile(new Pos(1, 1, 7)); onlyGround.Things.Add(Th(ground)); onlyGround.Things.Add(Th(border));
            check(TilePick.LookIndex(onlyGround) == 0 && TilePick.UseIndex(onlyGround) == 1, "pick: a tile of ground only: look the ground, use the last item");
            var empty = new Tile(new Pos(2, 2, 7));
            check(TilePick.LookIndex(empty) == -1 && TilePick.UseIndex(empty) == -1 && TilePick.TopCreature(empty) == null && !TilePick.ItemAt(empty, 0).HasValue, "pick: an empty tile");
            var force = It(106, t => t.ForceUse = true);
            var t2 = new Tile(new Pos(3, 3, 7)); t2.Things.Add(Th(ground)); t2.Things.Add(Th(coin)); t2.Things.Add(Th(force));
            check(TilePick.UseIndex(t2) == 1 || TilePick.UseIndex(t2) == 2, "pick: a force-use item is a use target");
            var ign = It(107, t => t.IgnoreLook = true);
            var t3 = new Tile(new Pos(4, 4, 7)); t3.Things.Add(Th(ground)); t3.Things.Add(Th(ign)); t3.Things.Add(Th(coin));
            check(TilePick.LookIndex(t3) == 2, "pick: look skips an ignore-look item");
            var r = TilePick.ItemAt(tile, 5);
            check(r.HasValue && r.Value.Stack == 5 && r.Value.Pos == tile.Pos && r.Value.Item == chest && !r.Value.Own, "pick: the item reference of a map thing");
            check(!TilePick.ItemAt(tile, 3).HasValue, "pick: a creature is not an item reference");
        }

        // ---------------------------------------------------------------------------------------------- item menu
        static void Menu(Action<bool, string> check)
        {
            Loc.Set("en");
            var ctx = new ItemMenuContext();
            Func<ItemRef, ItemMenuContext, string> acts = (r, c) => string.Join(",", ItemMenu.Build(r, c).Select(e => e.Separator ? "|" : e.Action.ToString()));
            var bag = new Pos(0xFFFF, 0x40, 2);
            var backpack = new ItemRef(bag, 2, It(2854, t => { t.Container = true; t.Pickupable = true; }));
            check(acts(backpack, ctx) == "Open,Look,|,WhereToFind", "menu: a bag in a bag: Open, Look, Where to find (" + acts(backpack, ctx) + ")");
            var tool = new ItemRef(bag, 0, It(3003, t => { t.MultiUse = true; t.Pickupable = true; t.Usable = true; }));
            check(acts(tool, ctx) == "Use,UseWith,Look,|,WhereToFind,LootAdd", "menu: a rope: Use, Use with, Look + hooks (" + acts(tool, ctx) + ")");
            ctx.OnLootList = true;
            check(acts(tool, ctx).EndsWith("LootRemove"), "menu: an item on the loot list offers Remove");
            ctx.OnLootList = false;
            var table = new ItemRef(new Pos(10, 10, 7), 2, It(1616, t => { t.Rotateable = true; t.Pickupable = false; t.NotMoveable = false; }));
            check(acts(table, ctx) == "Use,Rotate,Look,|,WhereToFind", "menu: a rotatable map item: Rotate, no loot entry for what cannot be picked up (" + acts(table, ctx) + ")");
            var trade = new ItemRef(bag, 1, It(2160, t => t.Pickupable = true));
            check(!acts(trade, ctx).Contains("Trade") && acts(trade, new ItemMenuContext { AnotherPlayerInView = true }).Contains("Trade"), "menu: Trade with only for an own item with another player in view");
            check(!acts(new ItemRef(new Pos(10, 10, 7), 1, It(2160, t => t.Pickupable = true)), new ItemMenuContext { AnotherPlayerInView = true }).Contains("Trade"), "menu: a map item is not traded");
            var ground = new ItemRef(new Pos(10, 10, 7), 0, It(100, t => t.Ground = true));
            check(acts(ground, ctx) == "Use,Look", "menu: ground has no hooks (" + acts(ground, ctx) + ")");
            // hooks: pouch, transmog, lock
            var locked = new Item { Id = 2400, Type = new ThingType { Id = 2400, Pickupable = true }, Attrs = new Dictionary<ushort, ulong> { { ItemAttr.Locked, 1 } } };
            var worn = new ItemRef(GameSession.InventoryPos(4), 4, locked);
            string a = acts(worn, ctx);
            check(a.Contains("Transmog") && a.Contains("Unlock") && !a.Contains("Lock,") && !a.EndsWith("Lock"), "menu: a locked worn armor: Transmog and Unlock item (" + a + ")");
            var rare = new ItemRef(GameSession.InventoryPos(5), 5, new Item { Id = 2401, Type = new ThingType { Id = 2401, Pickupable = true } });
            string b = acts(rare, new ItemMenuContext { RarityOf = 3 });
            check(b.Contains("Transmog") && b.EndsWith("Lock"), "menu: a rare worn weapon: Transmog and Lock item (" + b + ")");
            check(!acts(rare, ctx).Contains("Lock"), "menu: a plain item has no lock entry");
            var badge = new ItemRef(GameSession.InventoryPos(13), 13, new Item { Id = 2402, Type = new ThingType { Id = 2402, Pickupable = true } });
            check(acts(badge, new ItemMenuContext { RarityOf = 2 }).EndsWith("Lock") && !acts(badge, ctx).Contains("Transmog"), "menu: the badge slot can be locked, not transmogrified");
            check(!acts(new ItemRef(new Pos(10, 10, 7), 1, new Item { Id = 2403, Type = new ThingType { Id = 2403, Pickupable = true } }), new ItemMenuContext { RarityOf = 3 }).Contains("Lock"), "menu: the lock is for own items only");
            check(acts(new ItemRef(bag, 0, It(2500, t => t.Pickupable = true)), new ItemMenuContext { IsLootPouch = true }).Contains("PouchSettings"), "menu: the loot pouch has Pouch settings");
            check(ItemMenu.TransmogSlot(GameSession.InventoryPos(1)) && ItemMenu.TransmogSlot(GameSession.InventoryPos(4)) && !ItemMenu.TransmogSlot(GameSession.InventoryPos(2)) && !ItemMenu.TransmogSlot(GameSession.InventoryPos(3)) &&
                  !ItemMenu.TransmogSlot(GameSession.InventoryPos(9)) && !ItemMenu.TransmogSlot(bag), "menu: the transmog slots are head, armor, hands, legs and feet");
            // the plain right click
            var multi = It(3004, t => t.MultiUse = true);
            check(ItemMenu.RightClickIsUseWith(multi, new HashSet<int>(), true), "right click: a multi-use item starts Use with");
            check(!ItemMenu.RightClickIsUseWith(multi, new HashSet<int> { 3004 }, true), "right click: a multi-use weapon on the server's list is a plain use (it equips)");
            check(ItemMenu.RightClickIsUseWith(multi, new HashSet<int> { 3004 }, false), "right click: the list only counts with the option on");
            check(!ItemMenu.RightClickIsUseWith(It(3005), new HashSet<int>(), true) && !ItemMenu.RightClickIsUseWith(null, null, true), "right click: other items are used");
            Loc.Set("pt-BR");
            check(ItemMenu.Build(backpack, ctx)[0].Label == "Abrir" && ItemMenu.Build(tool, ctx)[1].Label == "Usar com ...", "menu: pt-BR labels");
            Loc.Set("en");
        }

        // ---------------------------------------------------------------------------------------------- crosshair
        static void Crosshair(Action<bool, string> check)
        {
            var src = new ItemRef(new Pos(0xFFFF, 0x40, 1), 1, new Item { Id = 3003 });
            var x = new CrosshairState();
            check(!x.Active && x.Click(null, null, 1) == null, "crosshair: idle by default");
            x.Start(CrosshairState.Kind.UseWith, src);
            var target = new ItemRef(new Pos(10, 11, 7), 2, new Item { Id = 1616 });
            var p = x.Click(target, null, 1);
            check(p != null && Hex(p) == Hex(PlayPackets.UseWith(src.Pos, 3003, 1, target.Pos, 1616, 2)) && !x.Active, "crosshair: use with on a map item sends 0x83 and ends");
            x.Start(CrosshairState.Kind.UseWith, src);
            p = x.Click(null, new Creature { Id = 77, Type = 1 }, 1);
            check(p != null && p[0] == 0x84 && !x.Active, "crosshair: use with on a creature sends 0x84");
            x.Start(CrosshairState.Kind.UseWith, src);
            check(x.Click(null, null, 1) == null && x.Active, "crosshair: a click on nothing keeps it");
            x.Cancel();
            x.Start(CrosshairState.Kind.Trade, src);
            check(x.Click(target, null, 1) == null && x.Active, "crosshair: a trade needs a player, an item is no target");
            check(x.Click(null, new Creature { Id = 5, Type = 1 }, 1) == null && x.Active, "crosshair: a monster is no trade partner");
            check(x.Click(null, new Creature { Id = 1, Type = 0 }, 1) == null && x.Active, "crosshair: yourself is no trade partner");
            p = x.Click(null, new Creature { Id = 8, Type = 0 }, 1);
            check(p != null && Hex(p) == Hex(PlayPackets.TradeRequest(src.Pos, 3003, 1, 8)) && !x.Active, "crosshair: a player: 0x7D and the crosshair ends");
        }

        // ---------------------------------------------------------------------------------------------- trade
        static GameParser Parser() => new GameParser(new World(DatFile.Parse(Program.SyntheticDat())));

        static void Trade(Action<bool, string> check)
        {
            var p = Parser();
            var sent = new List<byte[]>();
            p.PlayerTrade.Send = sent.Add;
            int changed = 0;
            p.PlayerTrade.Changed = () => changed++;
            check(!p.PlayerTrade.Open, "trade: closed at the start");
            // 0x7D: own offer: name, 2 items (a coin x5 and a ground item as a plain stand-in)
            var own = new ByteWriter().U8(0x7D).Str("Alice").U8(2).U16(101).U8(0xFF).U8(5).U8(0).U16(100).U8(0xFF);
            p.Parse(own.ToArray());
            var t = p.PlayerTrade;
            check(t.Open && t.Own.Name == "Alice" && t.Own.Items.Count == 2 && t.Own.Items[0].Id == 101 && t.Own.Items[0].Count == 5 && t.Counter.Items.Count == 0 && changed == 1, "trade: 0x7D reads the own offer and opens the window");
            check(!t.Accept() && sent.Count == 0, "trade: nothing to accept before the other offer");
            p.Parse(new ByteWriter().U8(0x7E).Str("Bob").U8(1).U16(100).U8(0xFF).ToArray());
            check(t.Counter.Name == "Bob" && t.Counter.Items.Count == 1 && t.OfferChanges == 1, "trade: 0x7E reads the counter offer");
            check(t.Accept() && sent.Count == 1 && Hex(sent[0]) == "7f" && t.Accepted, "trade: accept sends 0x7F once");
            check(!t.Accept() && sent.Count == 1, "trade: a second accept is not sent");
            p.Parse(new ByteWriter().U8(0x7E).Str("Bob").U8(2).U16(100).U8(0xFF).U16(100).U8(0xFF).ToArray());
            check(!t.Accepted && t.Counter.Items.Count == 2 && t.OfferChanges == 2, "trade: a changed counter offer clears your accept");
            check(t.LookAt(true, 1) && Hex(sent[1]) == "7e0101" && t.LookAt(false, 0) && Hex(sent[2]) == "7e0000", "trade: look at an item sends 0x7E side, index");
            check(!t.LookAt(true, 2) && !t.LookAt(false, -1) && sent.Count == 3, "trade: a look outside the list is not sent");
            check(PlayerTradeState.Header(t.Own, true) == "Your offer" && PlayerTradeState.Header(t.Counter, false) == "Bob's offer", "trade: the side headers");
            t.Close();
            check(!t.Open && sent.Count == 4 && Hex(sent[3]) == "80" && t.Own.Items.Count == 0 && t.Counter.Items.Count == 0, "trade: reject sends 0x80 and clears");
            t.Close();
            check(sent.Count == 4, "trade: a closed trade sends nothing more");
            p.Parse(own.ToArray());
            p.Parse(new byte[] { 0x7F });
            check(!t.Open && t.Own.Items.Count == 0 && sent.Count == 4, "trade: the server's 0x7F closes without a reply");
            // a bag offered: the item count byte covers the bag and what is inside
            p.Parse(new ByteWriter().U8(0x7D).Str("Alice").U8(3).U16(100).U8(0xFF).U16(100).U8(0xFF).U16(100).U8(0xFF).ToArray());
            check(t.Own.Items.Count == 3, "trade: a container comes as its items");
            // the same bytes after the trade through other messages in one packet
            var two = new ByteWriter().U8(0x7F).U8(0x7D).Str("C").U8(1).U16(100).U8(0xFF);
            p.Parse(two.ToArray());
            check(t.Open && t.Own.Name == "C" && t.Own.Items.Count == 1, "trade: two messages in one packet");
        }

        // ---------------------------------------------------------------------------------------------- VIP
        static void Vip(Action<bool, string> check)
        {
            Loc.Set("en");
            var p = Parser();
            var sent = new List<byte[]>();
            p.Vip.Send = sent.Add;
            var w = new ByteWriter().U8(0xD2).U32(10).Str("Zed").Str("my friend").U32(3).U8(1).U8(0);
            w.U8(0xD2).U32(11).Str("anna").Str("").U32(99).U8(0).U8(1);
            w.U8(0xD2).U32(12).Str("Bea").Str("").U32(0).U8(0).U8(2);
            p.Parse(w.ToArray());
            var v = p.Vip;
            check(v.Count == 3 && v.Get(10).Name == "Zed" && v.Get(10).Description == "my friend" && v.Get(10).Icon == 3 && v.Get(10).Notify && !v.Get(10).Online, "vip: 0xD2 entries");
            check(v.Get(11).Icon == 10 && v.Get(11).Online && v.Get(12).Status == 2, "vip: the icon is at most 10, status online and pending");
            check(string.Join(",", v.Sorted().Select(e => e.Name)) == "anna,Bea,Zed", "vip: online first, then by name");
            check(v.OnlineCount() == 1, "vip: online count");
            p.Parse(new ByteWriter().U8(0xD3).U32(10).U8(1).ToArray());
            check(v.Get(10).Online && string.Join(",", v.Sorted().Select(e => e.Name)) == "anna,Zed,Bea", "vip: 0xD3 status moves an entry up");
            p.Parse(new ByteWriter().U8(0xD3).U32(999).U8(1).ToArray());
            check(v.Count == 3, "vip: a status for an unknown guid is ignored");
            p.Parse(new ByteWriter().U8(0xD4).U32(10).ToArray());
            check(!v.Get(10).Online, "vip: 0xD4 (the old logout) sets the entry offline");
            p.Parse(new ByteWriter().U8(0xD3).U32(10).U8(1).ToArray());
            check(string.Join(",", v.Sorted("an").Select(e => e.Name)) == "anna", "vip: the filter");
            check(v.CheckName("x").Length > 0 && v.CheckName("Zed").Length > 0 && v.CheckName("zed").Length > 0 && v.CheckName("A1").Length > 0 && v.CheckName(new string('a', 30)).Length > 0 && v.CheckName("Mary Ann").Length == 0 && v.CheckName("O'Neil-Jo").Length == 0, "vip: name rules");
            check(v.Add("  Carl ") && sent.Count == 1 && Hex(sent[0]) == "dc04" + "00" + "4361726c" && !v.Add("Zed") && sent.Count == 1, "vip: add sends 0xDC with the trimmed name, a duplicate is refused");
            check(v.Remove(11) && v.Count == 2 && Hex(sent[1]) == "dd0b000000" && !v.Remove(11) && sent.Count == 2, "vip: remove sends 0xDD and drops the entry");
            check(v.Edit(10, "  new text  ", 55, false) && Hex(sent[2]) == "de0a000000" + "0800" + Hex(System.Text.Encoding.ASCII.GetBytes("new text")) + "0a000000" + "00" && v.Get(10).Icon == 10 && !v.Get(10).Notify, "vip: edit sends 0xDE, the icon is clamped");
            check(!v.Edit(404, "x", 1, true) && sent.Count == 3, "vip: edit of an unknown guid sends nothing");
            check(v.Edit(10, new string('d', 300), 0, true) && v.Get(10).Description.Length == VipState.MaxDescription, "vip: a long description is cut");
            v.Clear();
            check(v.Count == 0, "vip: clear");
        }

        // ---------------------------------------------------------------------------------------------- quest log
        static void Quests(Action<bool, string> check)
        {
            Loc.Set("en");
            var p = Parser();
            var sent = new List<byte[]>();
            p.Quests.Send = sent.Add;
            var q = p.Quests;
            q.Request();
            check(Hex(sent[0]) == "f0", "quests: the request is 0xF0");
            p.Parse(new ByteWriter().U8(0xF0).U16(3).U16(1).Str("The Rat Cellar").U8(1).U16(2).Str("Lost Ring").U8(0).U16(300).Str("Mines").U8(0).ToArray());
            check(q.Loaded && q.Quests.Count == 3 && q.Quests[0].Name == "The Rat Cellar" && q.Quests[0].Completed && q.Quests[2].Id == 300 && !q.Quests[1].Completed, "quests: 0xF0 reads the log");
            check(q.Done() == 1 && q.Summary() == "1 of 3 quests done", "quests: summary");
            q.Select(2);
            check(Hex(sent[1]) == "f10200" && q.Selected == 2 && q.Missions(2) == null, "quests: a pick asks 0xF1 and has no lines yet");
            p.Parse(new ByteWriter().U8(0xF1).U16(2).U8(2).Str("Find it").Str("Look in the cave.").Str("Return it").Str("Bring it back.").ToArray());
            var ms = q.Missions(2);
            check(ms != null && ms.Count == 2 && ms[0].Name == "Find it" && ms[1].Description == "Bring it back.", "quests: 0xF1 reads the missions");
            q.HideCompleted = true;
            check(q.Visible().Count == 2 && q.Visible().All(x => !x.Completed), "quests: hide completed");
            p.Parse(new ByteWriter().U8(0xF0).U16(1).U16(300).Str("Mines").U8(0).ToArray());
            check(q.Selected == -1 && q.Quests.Count == 1, "quests: a quest that left the log loses the pick");
            // an empty log
            p.Parse(new ByteWriter().U8(0xF0).U16(0).ToArray());
            check(q.Loaded && q.Quests.Count == 0 && q.Summary() == "0 of 0 quests done", "quests: an empty log");
        }

        // ---------------------------------------------------------------------------------------------- guards
        static DeadGuard.Seen Mon(uint id, int hp, bool player = false, bool self = false, bool onMap = true) => new DeadGuard.Seen { Id = id, Health = hp, IsPlayer = player, IsSelf = self, OnMap = onMap };

        static void Guards(Action<bool, string> check)
        {
            // dead guard: the numbers of deadguard_logic_test.lua
            check(DeadGuard.GraceMs == 3000 && DeadGuard.SweepMs == 1000, "deadguard: 3 s grace, 1 s sweep");
            check(DeadGuard.Decide(Mon(1, 0), 0) == "wait" && DeadGuard.Decide(Mon(1, 0), 2999) == "wait" && DeadGuard.Decide(Mon(1, 0), 3000) == "remove" && DeadGuard.Decide(Mon(1, 0), 60000) == "remove", "deadguard: wait, then remove at 3000");
            check(DeadGuard.Decide(Mon(1, 0, player: true), 60000) == "skip" && DeadGuard.Decide(Mon(1, 0, self: true), 60000) == "skip" && DeadGuard.Decide(Mon(1, 1), 60000) == "skip" && DeadGuard.Decide(Mon(1, 0, onMap: false), 60000) == "skip", "deadguard: players, yourself, the living and off-map are skipped");
            var g = new DeadGuard();
            check(g.Sweep(new[] { Mon(8, 0), Mon(9, 80) }, 1000).Count == 0, "deadguard: first sight at 0 waits");
            check(g.Sweep(new[] { Mon(8, 0), Mon(9, 80) }, 3999).Count == 0, "deadguard: inside the grace");
            var gone = g.Sweep(new[] { Mon(8, 0), Mon(9, 80) }, 4000);
            check(gone.Count == 1 && gone[0] == 8, "deadguard: removed after 3 s at 0");
            check(g.Sweep(new[] { Mon(8, 0) }, 4100).Count == 0, "deadguard: a removed id starts again if it comes back");
            g = new DeadGuard();
            g.Sweep(new[] { Mon(8, 0) }, 1000);
            g.Sweep(new DeadGuard.Seen[0], 2000);
            check(g.Sweep(new[] { Mon(8, 0) }, 4500).Count == 0, "deadguard: leaving the list restarts the clock");
            g = new DeadGuard();
            g.Sweep(new[] { Mon(8, 0) }, 1000);
            g.Sweep(new[] { Mon(8, 50) }, 2000);
            check(g.Sweep(new[] { Mon(8, 0) }, 4000).Count == 0, "deadguard: healing restarts the clock");
            g.Reset();

            // target guard
            var own = new Creature { Id = 1, Type = 3 }; var other = new Creature { Id = 2, Type = 4 }; var mon = new Creature { Id = 3, Type = 1 };
            check(TargetGuard.IsOwnSummon(3) && !TargetGuard.IsOwnSummon(4) && TargetGuard.IsSummon(4) && !TargetGuard.IsSummon(1), "targetguard: summon types");
            check(!TargetGuard.KeepLock(own) && TargetGuard.KeepLock(other) && TargetGuard.KeepLock(mon) && !TargetGuard.KeepLock(null), "targetguard: a lock on the own summon is dropped");
            check(TargetGuard.AttackCycle(new[] { own, other, mon }).Count == 2 && !TargetGuard.AttackCycle(new[] { own, other, mon }).Contains(own), "targetguard: attack next skips the own summons");
            var l = new TargetLock();
            check(l.Action(0, 0, 0) == LockAction.Keep && l.Action(5, 5, 0) == LockAction.Keep, "targetguard: no lock, or attacking it: keep");
            check(l.Action(5, 0, 0) == LockAction.Attack && l.Action(5, 0, 250) == LockAction.Attack && l.Action(5, 0, 500) == LockAction.Attack, "targetguard: three re-sends");
            check(l.Action(5, 0, 750) == LockAction.Drop, "targetguard: the fourth within 3 s drops the lock");
            check(l.Action(5, 0, 5000) == LockAction.Attack, "targetguard: after a drop it can start again");
            check(l.Action(6, 0, 5100) == LockAction.Attack && l.Action(6, 0, 5200) == LockAction.Attack && l.Action(6, 0, 5300) == LockAction.Attack && l.Action(6, 0, 8400) == LockAction.Attack, "targetguard: a new lock starts its own count, old sends age out");
        }

        // ---------------------------------------------------------------------------------------------- auto target
        static AutoCand C(uint id, double dist, int hp, int rank = AutoTargetCore.RankNormal, bool? reach = null) => new AutoCand { Id = id, Dist = dist, Health = hp, Rank = rank, Reachable = reach };

        static void AutoTarget(Action<bool, string> check)
        {
            check(AutoTargetCore.BaseName("Gem Goblin [25]") == "gem goblin" && AutoTargetCore.BaseName("  Rat ") == "rat" && AutoTargetCore.BaseName(null) == "" && AutoTargetCore.BaseName("Troll [x]") == "troll [x]", "autotarget: the name without the level suffix");
            check(AutoTargetCore.IsLootGoblin("Treasure Goblin [3]") && AutoTargetCore.IsLootGoblin("shard goblin") && !AutoTargetCore.IsLootGoblin("Goblin") && !AutoTargetCore.IsLootGoblin("Goblin Scavenger"), "autotarget: the loot goblins by name");
            check(AutoTargetCore.ClassOf("Treasure Goblin", "normal", null) == 1 && AutoTargetCore.ClassOf("Troll", "boss", null) == 2 && AutoTargetCore.ClassOf("Troll", "normal", "guardian") == 2 && AutoTargetCore.ClassOf("Troll", "omen", null) == 4 &&
                  AutoTargetCore.ClassOf("Troll", "magic", null) == 3 && AutoTargetCore.ClassOf("Troll", "rare", null) == 3 && AutoTargetCore.ClassOf("Troll", "legendary", "") == 3 && AutoTargetCore.ClassOf("Troll", null, null) == 4 && AutoTargetCore.ClassOf("Troll", "normal", "omen") == 2, "autotarget: goblin, boss, special, normal");
            check(AutoTargetCore.IsRanged(3) && AutoTargetCore.IsRanged(22) && !AutoTargetCore.IsRanged(4) && !AutoTargetCore.IsRanged(0), "autotarget: the ranged lines");
            check(AutoTargetCore.Distance(new Pos(10, 10, 7), new Pos(13, 8, 7)) == 3 && AutoTargetCore.Distance(new Pos(10, 10, 7), new Pos(10, 10, 6)) == -1, "autotarget: straight distance, nothing on another floor");
            double d;
            check(AutoTargetCore.Assess(5, false, 3, false, out d) && d == 5 && !AutoTargetCore.Assess(17, false, 3, false, out d) && !AutoTargetCore.Assess(-1, false, 3, false, out d) &&
                  AutoTargetCore.Assess(-1, true, 4, true, out d) && d == 4 && !AutoTargetCore.Assess(-1, true, 4, false, out d), "autotarget: reach by path (16 steps), or by sight for a ranged class");
            var cands = new List<AutoCand> { C(1, 2, 50), C(2, 5, 100, AutoTargetCore.RankSpecial), C(3, 9, 100, AutoTargetCore.RankGoblin), C(4, 1, 10, AutoTargetCore.RankBoss), C(5, 2, 20) };
            check(string.Join(",", AutoTargetCore.Sorted(cands, true).Select(c => c.Id)) == "3,4,2,5,1", "autotarget: class order, then distance, then lowest health");
            check(string.Join(",", AutoTargetCore.Sorted(cands, false).Select(c => c.Id)) == "4,5,1,2,3", "autotarget: without priority only distance, health, id");
            var tie = new List<AutoCand> { C(9, 3, 40), C(7, 3, 40) };
            check(AutoTargetCore.Sorted(tie, true)[0].Id == 7, "autotarget: a full tie goes to the lowest id");
            check(AutoTargetCore.PickPriority(cands, null).Id == 3 && AutoTargetCore.PickPriority(new[] { C(1, 1, 1), C(2, 2, 2) }, null) == null, "autotarget: the best priority monster, none among normals");
            Func<AutoCand, bool?> reach = c => c.Id == 3 ? false : c.Id == 4 ? (bool?)null : true;
            check(AutoTargetCore.PickPriority(cands, reach).Id == 2, "autotarget: an unreachable or unknown priority monster is skipped");
            bool keep;
            var pick = AutoTargetCore.Choose(cands, true, null, 0, out keep);
            check(pick.Id == 3 && !keep, "autotarget: choose picks the goblin");
            pick = AutoTargetCore.Choose(cands, true, null, 3, out keep);
            check(pick.Id == 3 && keep, "autotarget: the current best stays");
            pick = AutoTargetCore.Choose(cands, true, null, 1, out keep);
            check(pick.Id == 3 && !keep, "autotarget: a normal current target gives way to a goblin");
            pick = AutoTargetCore.Choose(cands, false, null, 1, out keep);
            check(pick.Id == 1 && keep, "autotarget: without priority the current target stays");
            pick = AutoTargetCore.Choose(cands, true, c => c.Id == 3 ? (bool?)false : true, 3, out keep);
            check(pick.Id == 4 && !keep, "autotarget: an unreachable current target is replaced");
            check(AutoTargetCore.Choose(new List<AutoCand>(), true, null, 0, out keep) == null, "autotarget: nobody to pick");
            check(AutoTargetCore.Choose(new[] { C(1, 2, 2) }, true, c => false, 0, out keep) == null, "autotarget: nobody reachable");
            check(!AutoTargetCore.KeepLock(C(1, 2, 50), cands, null, true) && AutoTargetCore.KeepLock(C(3, 9, 100, 1), cands, null, true) && AutoTargetCore.KeepLock(C(1, 2, 50), cands, null, false), "autotarget: keep the lock unless a better class is in reach");
            check(!AutoTargetCore.KeepLock(C(1, 2, 50), cands, c => false, false), "autotarget: an unreachable lock is dropped");
        }

        // ---------------------------------------------------------------------------------------------- the helper engine with the guards
        sealed class Host : IHelperHost
        {
            public double Now { get; set; }
            public int Health { get; set; } = 100;
            public int MaxHealth { get; set; } = 100;
            public int Mana { get; set; } = 500;
            public int MaxMana { get; set; } = 500;
            public int Level { get; set; } = 100;
            public Pos Position { get; set; } = new Pos(100, 100, 7);
            public Dir Facing { get; set; } = Dir.North;
            public bool InProtectionZone { get; set; }
            public bool Hasted { get; set; }
            public uint AttackTarget { get; set; }
            public bool Following { get; set; }
            public double MsSinceLastRead { get; set; }
            public bool Obey = true;
            public List<HelperCreature> Mon = new List<HelperCreature>();
            public List<string> Log = new List<string>();
            public IList<HelperCreature> Monsters() { return Mon; }
            public void Say(string words) { }
            public void Attack(uint id) { if (Obey) AttackTarget = id; Log.Add("attack " + id); }
            public void CancelAttack() { AttackTarget = 0; }
            public void Turn(Dir d) { }
            public int ItemCount(int id) { return 0; }
            public void UseOnSelf(int id) { }
        }

        static void Engine(Action<bool, string> check)
        {
            var host = new Host();
            var e = new HelperEngine(new SpellBook(new ExtOpcodes()) { Clock = () => host.Now }, host);
            e.Config.AutoTarget = true; e.Config.Enabled = true;
            host.Mon.Add(new HelperCreature(1, new Pos(101, 100, 7), 100));
            host.Mon.Add(new HelperCreature(2, new Pos(104, 100, 7), 100));
            for (double t = 1000; t <= 1300; t += 50) { host.Now = t; e.Tick(); }
            check(host.AttackTarget == 1, "engine: without a class rule the nearest is taken");
            // with the class rule a goblin farther away wins, and a lock on a normal one gives way when it shows
            var host2 = new Host();
            var e2 = new HelperEngine(new SpellBook(new ExtOpcodes()) { Clock = () => host2.Now }, host2);
            e2.Config.AutoTarget = true; e2.Config.Enabled = true;
            e2.RankOf = id => id == 2 ? AutoTargetCore.RankGoblin : AutoTargetCore.RankNormal;
            host2.Mon.Add(new HelperCreature(1, new Pos(101, 100, 7), 100));
            for (double t = 1000; t <= 1200; t += 50) { host2.Now = t; e2.Tick(); }
            check(host2.AttackTarget == 1 && e2.LockedTarget == 1, "engine: a lone normal monster is the target");
            host2.Mon.Add(new HelperCreature(2, new Pos(106, 100, 7), 100));
            for (double t = 1250; t <= 1600; t += 50) { host2.Now = t; e2.Tick(); }
            check(host2.AttackTarget == 2 && e2.LockedTarget == 2, "engine: a goblin in reach takes the target from a normal monster (" + host2.AttackTarget + ")");
            // the server refuses the attack: the lock is dropped after three re-sends in three seconds
            var host3 = new Host { Obey = false };
            var e3 = new HelperEngine(new SpellBook(new ExtOpcodes()) { Clock = () => host3.Now }, host3);
            e3.Config.AutoTarget = true; e3.Config.Enabled = true;
            host3.Mon.Add(new HelperCreature(1, new Pos(101, 100, 7), 100));
            for (double t = 1000; t <= 2400; t += 50) { host3.Now = t; e3.Tick(); }
            int sends = host3.Log.Count(s => s == "attack 1");
            check(sends >= 3 && sends <= 12, "engine: a refused lock is not re-sent every tick (" + sends + " sends in 1.4 s)");
        }

        // ---------------------------------------------------------------------------------------------- badge slot, loot screen
        static void Badge(Action<bool, string> check)
        {
            var p = Parser();
            p.Parse(new ByteWriter().U8(0x78).U8(13).U16(100).U8(0xFF).ToArray());
            check(p.Inventory.Length == 14 && p.Inventory[13] != null && p.Inventory[13].Id == 100, "badge: 0x78 slot 13 fills the badge slot");
            p.Parse(new ByteWriter().U8(0x79).U8(13).ToArray());
            check(p.Inventory[13] == null, "badge: 0x79 empties it");
            p.Parse(new ByteWriter().U8(0x78).U8(14).U16(100).U8(0xFF).ToArray());
            check(p.Inventory.All(i => i == null), "badge: a slot past the array is ignored");
            Loc.Set("en");
            check(BadgeSlot.SlotTooltip(13, false) == "Badge" && BadgeSlot.SlotTooltip(13, true) == "" && BadgeSlot.SlotTooltip(4, false) == null, "badge: the tooltip of the empty slot");
            check(LootScreen.OnScreen(30) && !LootScreen.OnScreen(31) && LootScreen.OnScreen(22), "lootscreen: the loot line stays off the screen");
            // the loot text still reaches the chat tabs
            string lastScreen = null; string lastChat = null;
            p.Text = t => lastScreen = t; p.Chat = (who, text, type) => lastChat = text;
            p.Parse(new ByteWriter().U8(0xB4).U8(31).Str("Loot of a rat: 3 gold coins.").ToArray());
            check(lastScreen == null && lastChat == "Loot of a rat: 3 gold coins.", "lootscreen: not on the screen, still in the chat");
            p.Parse(new ByteWriter().U8(0xB4).U8(22).Str("You see a rat.").ToArray());
            check(lastScreen == "You see a rat." && lastChat == "You see a rat.", "lootscreen: a look answer goes everywhere");
        }

        // ---------------------------------------------------------------------------------------------- look preview
        static void Preview(Action<bool, string> check)
        {
            Loc.Set("en");
            var own = new Outfit(128, 10, 20, 30, 40, 1, 7) { Wings = 3, Aura = 4, Shader = "gold" };
            string note;
            var o = LookPreview.Compose(false, own, null, null, out note);
            check(o.LookType == 128 && o.Mount == 7 && o.Wings == 3 && o.Aura == 4 && o.Shader == "gold" && note == null && o != own, "preview: no option shows the character as worn, as a copy");
            o = LookPreview.Compose(true, own, null, null, out note);
            check(o.LookType == 128 && o.Head == 76 && o.Mount == 0 && o.Wings == 0 && o.Shader == "", "preview: the plain figure has nothing extra");
            o = LookPreview.Compose(false, own, new PreviewOption { Kind = "outfit", Look = 300, Addons = 2 }, null, out note);
            check(o.LookType == 300 && o.Addons == 2 && o.Head == 10 && o.Wings == 3, "preview: an outfit keeps the colours and the extras");
            o = LookPreview.Compose(false, own, new PreviewOption { Kind = "addons", Look = 300 }, null, out note);
            check(o.Addons == 3, "preview: addons means both");
            o = LookPreview.Compose(true, own, PreviewOption.Of("wings", 9), null, out note);
            check(o.Wings == 9 && o.LookType == 128 && o.Head == 76, "preview: wings on the plain figure");
            o = LookPreview.Compose(false, own, PreviewOption.Of("mount", 55), null, out note);
            check(o.Mount == 55, "preview: a mount");
            o = LookPreview.Compose(false, own, new PreviewOption { Kind = "shader", Shader = "ghost" }, n => n == "gold", out note);
            check(o.Shader == "" && note == "This shader is not in your client yet.", "preview: an unknown shader is left off with a note");
            o = LookPreview.Compose(false, own, new PreviewOption { Kind = "shader", Shader = "gold" }, n => n == "gold", out note);
            check(o.Shader == "gold" && note == null, "preview: a known shader");
            o = LookPreview.Compose(false, own, PreviewOption.Of("subject", 42), null, out note);
            check(o.LookType == 42 && o.Mount == 0 && o.Wings == 0 && !LookPreview.HasWearer(PreviewOption.Of("subject", 1)) && LookPreview.HasWearer(null), "preview: a pet is drawn alone");
            var bundle = new PreviewOption { Kind = "bundle", Parts = new List<PreviewOption> { new PreviewOption { Kind = "outfit", Look = 200, Addons = 3 }, PreviewOption.Of("aura", 8), PreviewOption.Of("footprint"), PreviewOption.Of("subject", 5) } };
            o = LookPreview.Compose(true, own, bundle, null, out note);
            check(o.LookType == 200 && o.Addons == 3 && o.Aura == 8 && o.Mount == 0, "preview: a bundle composes its worn parts on the plain figure");
            o = LookPreview.Compose(false, own, new PreviewOption { Kind = "look", Outfit = new Outfit(99, 1, 2, 3, 4, 0, 0) { Aura = 2 } }, null, out note);
            check(o.LookType == 99 && o.Aura == 2 && o.Wings == 0, "preview: a whole look replaces the outfit");
            o = LookPreview.Compose(true, own, new PreviewOption { Kind = "look", Outfit = new Outfit(99, 1, 2, 3, 4, 0, 6) { Aura = 2 } }, null, out note);
            check(o.LookType == 128 && o.Mount == 6 && o.Aura == 2, "preview: on the plain figure a whole look keeps only its extras");
            LookPreview.Compose(false, own, PreviewOption.Of("footprint"), null, out note);
            check(note == "Footprints are left on the ground as you walk.", "preview: a note for a kind the figure cannot show");
            check(LookPreview.Showable(null) && LookPreview.Showable(PreviewOption.Of("bundle")) && !LookPreview.Showable(PreviewOption.Of("footprint")), "preview: showable kinds");

            // from the store's look table
            var json = Json.Parse("{\"kind\":\"bundle\",\"parts\":[{\"kind\":\"addons\",\"look\":130},{\"kind\":\"wings\",\"look\":4},{\"kind\":\"shader\",\"shader\":\"gold\"},{\"kind\":\"outline\",\"art\":\"flame\",\"pulse\":true},{\"kind\":\"bogus\"},{\"kind\":\"outfit\",\"look\":0}]}");
            var opt = LookPreview.FromStoreLook(json);
            check(opt != null && opt.Kind == "bundle" && opt.Parts.Count == 4 && opt.Parts[0].Look == 130 && opt.Parts[0].Addons == 3 && opt.Parts[3].Art == "flame" && opt.Parts[3].Pulse, "preview: a store bundle, bad parts dropped");
            check(LookPreview.FromStoreLook(Json.Parse("{\"kind\":\"outline\",\"art\":\"bad;name\"}")) == null && LookPreview.FromStoreLook(Json.Parse("{\"kind\":\"mount\",\"look\":0}")) == null && LookPreview.FromStoreLook(null) == null, "preview: bad names and looks are refused");
            check(LookPreview.FromStoreLook(Json.Parse("{\"kind\":\"bundle\",\"parts\":[{\"kind\":\"bundle\",\"parts\":[{\"kind\":\"bundle\",\"parts\":[{\"kind\":\"mount\",\"look\":1}]}]}]}")) == null, "preview: bundles nest only one deep");
            var fromRow = LookPreview.FromOutfitButton("aura", own);
            check(fromRow.Kind == "aura" && fromRow.Look == 4 && LookPreview.FromOutfitButton("outfit", own).Addons == 1 && LookPreview.FromOutfitButton("shader", own).Shader == "gold" && LookPreview.FromOutfitButton("x", own) == null, "preview: options of the outfit window's buttons");
            check(LookPreview.Key(own) == "128,10,20,30,40,1,7,3,4,gold" && LookPreview.Key(null) == "", "preview: the outfit key");
            check(LookPreview.Turn(2, 1) == 3 && LookPreview.Turn(3, 1) == 0 && LookPreview.Turn(0, -1) == 3 && LookPreview.Turn(2, 4) == 2, "preview: turning goes round the four directions");
        }

        // ---------------------------------------------------------------------------------------------- texts
        static void Texts(Action<bool, string> check)
        {
            string root = FindUp("unity/Client/Assets/Chaos");
            var keys = new HashSet<string>();
            var pat = new Regex("Loc\\.T\\(\\s*(\"(?:[^\"\\\\]|\\\\.)*\")");
            foreach (string f in new[] { "Core/Play.cs", "Core/PlayLists.cs", "Core/PlayLook.cs", "Core/PlayGuards.cs", "Unity/ChaosApp.Play.cs", "Unity/Windows/PlayWindows.cs" })
                foreach (Match m in pat.Matches(File.ReadAllText(Path.Combine(root, f))))
                    keys.Add(m.Groups[1].Value.Substring(1, m.Groups[1].Value.Length - 2).Replace("\\n", "\n").Replace("\\\"", "\""));
            keys.Add(LookPreview.UnknownShader); keys.Add(BadgeSlot.Tooltip);
            var missing = keys.Where(k => !LocStrings.PtBr.ContainsKey(k)).ToList();
            check(missing.Count == 0, "play: every text has a pt-BR entry; missing: " + string.Join(" | ", missing.Take(8)));
            var bad = LocPlay.PtBr.Where(kv => Regex.Matches(kv.Key, "\\{\\d\\}").Count != Regex.Matches(kv.Value, "\\{\\d\\}").Count).Select(kv => kv.Key).ToList();
            check(bad.Count == 0, "play: placeholders of the pt-BR texts match: " + string.Join(" | ", bad.Take(5)));
            Loc.Set("pt-BR");
            check(Loc.T("{0} online of {1}", 2, 5) == "2 online de 5" && Loc.T("Quest Log") == "Diário de quests", "play: pt-BR text through Loc.T");
            Loc.Set("en");
            check(!LocPlay.PtBr.Any(kv => kv.Value.Contains("—") || kv.Value.Contains("–")), "play: no em dashes in the pt-BR texts");
        }

        static string FindUp(string rel)
        {
            string dir = AppContext.BaseDirectory;
            for (int i = 0; i < 10 && dir != null; i++)
            {
                string p = Path.Combine(dir, rel);
                if (Directory.Exists(p)) return p;
                dir = Path.GetDirectoryName(dir);
            }
            return Path.GetFullPath(Path.Combine(Directory.GetCurrentDirectory(), "..", "Client", "Assets", "Chaos"));
        }
    }
}
