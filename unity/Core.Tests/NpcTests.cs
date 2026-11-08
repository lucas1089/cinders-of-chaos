// Checks of NPC dialogue and NPC trade (Core/NpcTrade.cs and the parser's 0x7A / 0x7B / 0x7C / 0xAA of NPCs): byte-level packets
// in and out, the model rules (lists, search, quantity bounds, totals, currency), {keywords}, the talk log and its channel rule.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class NpcTests
    {
        static string Hex(byte[] b) => string.Concat(b.Select(x => x.ToString("x2")));

        static ByteWriter U64(ByteWriter w, ulong v) => w.U32((uint)v).U32((uint)(v >> 32));

        static byte[] ShopPacket()
        {
            var w = new ByteWriter().U8(0x7A).Str("Rowan").U16(4);
            // id, sub type, name, weight (hundredths), buy, sell
            w.U16(2002).U8(0).Str("health potion").U32(1000).U32(50).U32(0xFFFFFFFF);
            w.U16(2003).U8(0).Str("mana potion").U32(1000).U32(60).U32(0xFFFFFFFF);
            w.U16(2160).U8(0).Str("crystal coin").U32(10).U32(0xFFFFFFFF).U32(10000);
            w.U16(3031).U8(0).Str("gold ingot").U32(5000).U32(0).U32(5);
            return w.ToArray();
        }

        static byte[] GoodsPacket(ulong money)
        {
            var w = U64(new ByteWriter().U8(0x7B), money).U8(2);
            w.U16(2160).U8(7).U16(3031).U8(255);
            return w.ToArray();
        }

        static NpcTradeState Loaded(ulong money = 1000)
        {
            var s = new NpcTradeState();
            var r = new ByteReader(ShopPacket()); r.U8();
            s.ReadShop(r, 0);
            var g = new ByteReader(GoodsPacket(money)); g.U8();
            s.ReadGoods(g);
            return s;
        }

        public static void Run(Action<bool, string> check)
        {
            Wire(check);
            Model(check);
            Currency(check);
            Packets(check);
            Talk(check);
            Parser(check);
        }

        static void Wire(Action<bool, string> check)
        {
            var s = Loaded(123456789012);
            check(s.Open && s.Npc == "Rowan" && s.Items.Count == 4, "shop: npc name and four items (0x7A)");
            var potion = s.Items[0];
            check(potion.Id == 2002 && potion.Name == "health potion" && potion.Weight == 1000 && potion.Buy == 50 && potion.Sell == ShopItem.NoPrice,
                  "shop: item fields (id, name, weight, buy, sell)");
            check(s.Money == 123456789012UL && s.Goods.Count == 2 && s.GoodsCount(2160) == 7 && s.GoodsCount(3031) == 255,
                  "goods: u64 money and the carried counts (0x7B)");
            s.Close();
            check(!s.Open && s.Items.Count == 0 && s.Goods.Count == 0, "close (0x7C) empties the shop");

            bool threw = false;
            try { var r = new ByteReader(new ByteWriter().U8(0x7A).Str("Rowan").U16(2).U16(1).ToArray()); r.U8(); new NpcTradeState().ReadShop(r, 0); }
            catch (ProtocolException) { threw = true; }
            check(threw, "a cut shop packet is refused");
        }

        static void Model(Action<bool, string> check)
        {
            var s = Loaded(1000);
            check(s.BuyList("").Select(i => i.Name).SequenceEqual(new[] { "health potion", "mana potion" }),
                  "buy list: items with a buy price, by name; 0xFFFFFFFF and 0 are not for sale");
            check(s.SellList("").Select(i => i.Name).SequenceEqual(new[] { "crystal coin", "gold ingot" }),
                  "sell list: items the NPC buys and the player carries");
            check(s.BuyList("MANA").Count == 1 && s.BuyList("zzz").Count == 0 && s.SellList(" coin ").Count == 1, "search is case blind and trimmed");

            var hp = s.Items[0];   // 50 gold, 10 oz
            check(s.MaxBuy(hp, 100000, false) == 20, "max buy: 1000 gold / 50 = 20");
            check(s.MaxBuy(hp, 2500, false) == 2, "max buy: capacity 25 oz holds 2 potions of 10 oz");
            check(s.MaxBuy(hp, 0, true) == 20, "max buy: ignore capacity");
            s.SetGoods(1000000, new KeyValuePair<ushort, int>[0]);
            check(s.MaxBuy(hp, 1000000, false) == 100, "max buy: 100 at a time");
            s.SetGoods(30, new KeyValuePair<ushort, int>[0]);
            check(s.MaxBuy(hp, 100000, false) == 0, "max buy: not enough money for one");
            check(s.MaxBuy(s.Items[2], 100000, false) == 0 && s.MaxBuy(null, 100000, false) == 0, "max buy: a row that is not for sale");

            var s2 = Loaded(1000);
            check(s2.MaxSell(s2.Items[2]) == 7 && s2.MaxSell(s2.Items[3]) == 100 && s2.MaxSell(s2.Items[0]) == 0, "max sell: carried count, 100 at a time, not bought = 0");
            check(NpcTradeState.ClampAmount(0, 5) == 1 && NpcTradeState.ClampAmount(9, 5) == 5 && NpcTradeState.ClampAmount(3, 0) == 0, "amount clamp");
            check(NpcTradeState.Total(hp, 3, TradeMode.Buy) == 150 && NpcTradeState.Total(s2.Items[2], 7, TradeMode.Sell) == 70000 && NpcTradeState.Total(null, 3, TradeMode.Buy) == 0,
                  "total price");
            check(NpcTradeState.Total(hp, 100, TradeMode.Buy) == 5000, "total of 100 is 100 times the price, in 64 bits");

            check(s2.BuyBlock(hp, 21, 100000, false) == "money" && s2.BuyBlock(hp, 3, 2500, false) == "capacity" && s2.BuyBlock(hp, 3, 2500, true) == null
                  && s2.BuyBlock(hp, 0, 100000, false) == "none" && s2.BuyBlock(hp, 101, 100000, true) == "none", "buy blocks: money, capacity, amount");
            check(s2.SellBlock(s2.Items[2], 7) == null && s2.SellBlock(s2.Items[2], 8) == "none" && s2.SellBlock(s2.Items[0], 1) == "none", "sell blocks: more than carried, not bought");
            check(s2.BuyRequest(hp, 21, 100000, false) == null && s2.SellRequest(s2.Items[2], 8) == null, "a request the rules forbid is not built");
        }

        static void Currency(Action<bool, string> check)
        {
            var ext = new ExtOpcodes();
            var s = new NpcTradeState();
            ext.On(NpcTradeState.OpcodeCurrency, m => s.ReceiveCurrency(NpcTradeState.ParseCurrency(m), 100));
            ext.Receive(113, ExtOpcodes.ToWire("{\"action\":\"currency\",\"data\":{\"code\":\"azure\",\"name\":\"azure coins\",\"item\":3040,\"amount\":42}}"));
            var r = new ByteReader(ShopPacket()); r.U8();
            s.ReadShop(r, 5000);
            check(s.Currency != null && s.Currency.Name == "Azure Coins" && s.Currency.Item == 3040 && s.Balance == 42 && !s.Gold, "currency before the shop is the shop's currency");
            s.Items[0].Buy = 10;
            check(s.MaxBuy(s.Items[0], 100000, true) == 4, "the balance of the currency bounds a purchase, not the gold");
            ext.Receive(113, ExtOpcodes.ToWire("{\"action\":\"currency\",\"data\":{\"name\":\"azure coins\",\"amount\":7,\"again\":true}}"));
            check(s.Balance == 7, "the balance after a purchase updates the open shop");
            s.Close();
            check(s.Gold, "closing goes back to gold");
            ext.Receive(113, ExtOpcodes.ToWire("{\"action\":\"currency\",\"data\":{\"name\":\"azure coins\",\"amount\":7,\"again\":true}}"));
            var r2 = new ByteReader(ShopPacket()); r2.U8();
            s.ReadShop(r2, 5000);
            check(s.Gold, "a balance for a window that is not open is ignored");
            s.Close();
            ext.Receive(113, ExtOpcodes.ToWire("{\"action\":\"currency\",\"data\":{\"name\":\"azure coins\",\"amount\":7}}"));
            var r3 = new ByteReader(ShopPacket()); r3.U8();
            s.ReadShop(r3, 100 + NpcTradeState.CurrencyTtlMs + 1);
            check(s.Gold, "a pending currency older than 15 s is dropped");
            check(NpcTradeState.ParseCurrency(new ExtMessage { Action = "currency", Data = new Dictionary<string, object> { { "amount", 1.0 } } }) == null
                  && NpcTradeState.ParseCurrency(new ExtMessage { Action = "other", Data = new Dictionary<string, object>() }) == null, "a currency without a name or of another action is none");
        }

        static void Packets(Action<bool, string> check)
        {
            check(Hex(NpcPackets.Buy(2002, 0, 5, false, false)) == "7ad207" + "00" + "05" + "00" + "00", "buy 0x7A: id u16, sub u8, amount u8, ignore cap u8, in backpacks u8: " + Hex(NpcPackets.Buy(2002, 0, 5, false, false)));
            check(Hex(NpcPackets.Buy(0x1234, 3, 100, true, true)) == "7a341203" + "64" + "01" + "01", "buy flags");
            check(Hex(NpcPackets.Sell(2160, 0, 7, true)) == "7b700800" + "07" + "01", "sell 0x7B: id, sub, amount, ignore equipped");
            check(Hex(NpcPackets.Sell(2160, 0, 7, false)).EndsWith("0700", StringComparison.Ordinal), "sell without ignoring equipped");
            check(Hex(NpcPackets.Look(2002, 0)) == "79d20700", "look 0x79: id and sub type");
            check(Hex(NpcPackets.Close()) == "7c", "close 0x7C");
            check(Hex(NpcPackets.SayToNpc("trade")) == "960c0500" + "7472616465", "words to the NPC: 0x96, talk type 12, text");
            var s = Loaded(1000);
            check(Hex(s.BuyRequest(s.Items[0], 2, 100000, false)) == "7ad20700" + "02" + "00" + "00", "BuyRequest builds the packet when the rules allow");
            check(Hex(s.SellRequest(s.Items[2], 7)) == "7b700800" + "07" + "01", "SellRequest builds the packet (equipped ignored by default)");
        }

        static void Talk(Action<bool, string> check)
        {
            var segs = NpcTalkState.Segments("Welcome, {Hero}! I {sell} {potions}, {} and {sell}.");
            check(segs.Count(p => p.Key) == 4 && segs[0].Text == "Welcome, " && !segs[0].Key && segs[1].Text == "Hero" && segs[1].Key, "segments: keywords and plain text");
            check(NpcTalkState.Plain("a {b} c {} d") == "a b c  d", "plain text has no braces");
            check(NpcTalkState.Keywords("Do you {trade}? {Trade} or {bye}, {x}{y}").SequenceEqual(new[] { "trade", "bye", "x", "y" }), "keywords: in order, once, case blind");
            check(NpcTalkState.Plain("open { never closed") == "open { never closed" && NpcTalkState.Plain("a { b {c} d") == "a { b c d", "unbalanced braces stay text");
            check(NpcTalkState.Keywords(string.Join(" ", Enumerable.Range(0, 30).Select(i => "{k" + i + "}"))).Count == NpcTalkState.MaxChips, "at most 12 chips");

            var t = new NpcTalkState();
            check(!t.Focused(0) && !t.ToNpcChannel("trade", 0), "no conversation: words go to the default channel");
            t.FromNpc("Rowan", "Welcome! {trade}?", 1000);
            check(t.Focused(2000) && t.Npc == "Rowan" && t.ToNpcChannel("trade", 2000) && !t.ToNpcChannel("hi", 2000), "focused: keywords go to the NPC channel, a greeting does not");
            check(t.CurrentKeywords().SequenceEqual(new[] { "trade" }), "keywords of the last NPC line");
            check(!t.Focused(1000 + NpcTalkState.IdleMs + 1), "an idle conversation is forgotten after 120 s");
            t.FromPlayer("Hero", "bye", 3000);
            check(!t.Focused(3001) && t.Lines.Count == 2 && !t.Lines[1].FromNpc, "bye ends the conversation");
            for (int i = 0; i < 300; i++) t.FromNpc("Rowan", "line " + i, 4000 + i);
            check(t.Lines.Count == NpcTalkState.MaxLines && t.Lines[t.Lines.Count - 1].Text == "line 299", "the log keeps the last 200 lines");

            // the position check of a private NPC line
            var withPos = new ByteWriter().U16(1000).U16(1000).U8(7).Str("hello");
            var rp = new ByteReader(withPos.ToArray());
            check(NpcTalkState.HasPosition(rp), "an NPC line with a position is told apart");
            var plain = new ByteWriter().Str("hello");
            check(!NpcTalkState.HasPosition(new ByteReader(plain.ToArray())), "an NPC line without a position is told apart");
        }

        static byte[] Say(string name, byte type, bool pos, string text)
        {
            var w = new ByteWriter().U8(0xAA).U32(1).Str(name).U16(0).U8(type);
            if (pos) w.U16(1000).U16(1000).U8(7);
            return w.Str(text).ToArray();
        }

        static void Parser(Action<bool, string> check)
        {
            var world = new World(DatFile.Parse(Program.SyntheticDat()));
            double now = 10000;
            var parser = new GameParser(world) { Clock = () => now };
            var chats = new List<string>();
            parser.Chat = (who, text, type) => chats.Add(who + "|" + text + "|" + type);

            parser.Parse(Say("Rowan", 10, true, "Welcome, {Hero}! Want to {trade}?"));
            check(parser.NpcTalk.Lines.Count == 1 && parser.NpcTalk.Lines[0].FromNpc && parser.NpcTalk.Npc == "Rowan"
                  && parser.NpcTalk.Lines[0].Text.StartsWith("Welcome", StringComparison.Ordinal), "0xAA type 10 with a position: the NPC's answer");
            parser.Parse(Say("Rowan", 10, false, "Here you go."));
            check(parser.NpcTalk.Lines.Count == 2 && parser.NpcTalk.Lines[1].Text == "Here you go.", "0xAA type 10 without a position");
            parser.Parse(Say("Rowan", 10, true, "one").Concat(Say("Rowan", 10, true, "two")).ToArray());
            check(parser.NpcTalk.Lines.Count == 4 && parser.NpcTalk.Lines[3].Text == "two", "two NPC lines in one packet");
            check(chats.Count == 4 && chats[0].EndsWith("|10", StringComparison.Ordinal), "the chat event still fires for an NPC line");

            // a plain say of an NPC creature joins the log only while we talk to it; a player's say never
            world.Creatures[77] = new Creature { Id = 77, Name = "Rowan", Type = 2 };
            world.Creatures[78] = new Creature { Id = 78, Name = "Bob", Type = 0 };
            int n = parser.NpcTalk.Lines.Count;
            parser.Parse(Say("Rowan", 1, true, "Fresh potions!"));
            parser.Parse(Say("Bob", 1, true, "hello"));
            check(parser.NpcTalk.Lines.Count == n + 1 && parser.NpcTalk.Lines[n].Text == "Fresh potions!", "an NPC's public say joins the log while focused; a player's does not");
            now += NpcTalkState.IdleMs + 1;
            parser.Parse(Say("Rowan", 1, true, "Buy my wares!"));
            check(parser.NpcTalk.Lines.Count == n + 1, "an NPC's public say of a stranger stays out of the log");

            parser.Parse(ShopPacket());
            parser.Parse(GoodsPacket(500));
            check(parser.Trade.Open && parser.Trade.Items.Count == 4 && parser.Trade.Money == 500 && parser.Trade.SellList("").Count == 2, "parser: 0x7A then 0x7B fill the trade state");
            parser.Parse(ShopPacket().Concat(GoodsPacket(900)).Concat(new byte[] { 0x1D }).ToArray());
            check(parser.Trade.Money == 900, "0x7A, 0x7B and a ping in one packet");
            parser.Parse(new byte[] { 0x7C });
            check(!parser.Trade.Open && parser.Trade.Items.Count == 0, "parser: 0x7C closes the shop");
            // the inventory clear 0x79 (server to client) is not a shop packet
            parser.Parse(new byte[] { 0x79, 5 });
            check(!parser.Trade.Open, "0x79 from the server stays an inventory slot clear");
        }
    }
}
