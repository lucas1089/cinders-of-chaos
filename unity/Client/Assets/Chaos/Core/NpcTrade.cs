// NPC dialogue and NPC trade, engine-free. The model of the main client's game_npctalk and game_npctradewindow
// (client/overlay/modules/game_npctradewindow/tradewindowlogic.lua and the base game_npctrade rules):
//  - NpcTradeState: the shop of 0x7A, the player's goods of 0x7B, buy and sell lists, quantity bounds (money, capacity,
//    stock, 100 at a time), totals, search, and the currency of extended opcode 113 for NPCs that do not trade for gold.
//  - NpcTalkState: what the NPC said (private NPC speech, talk type 10 / 11) and what we said to it, {keywords}, quick words.
//  - NpcPackets: the requests to the server (look 0x79, buy 0x7A, sell 0x7B, close 0x7C, words to the NPC as talk type 12).
// Wire layout (protocol 10.98, TFS 1.4 sendShop and sendSaleItemList, read from server/tools/testers.py parse_shop):
//  0x7A  string npc name, u16 count, per item: u16 client id, u8 sub type, string name, u32 weight, u32 buy, u32 sell
//  0x7B  u64 money (cash plus bank), u8 count, per item: u16 client id, u8 count (255 at most)
//  0x7C  nothing
// Weight is in hundredths of an ounce like the free capacity of 0xA0. A price of 0xFFFFFFFF is "not traded".
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public enum TradeMode { Buy, Sell }

    public sealed class ShopItem
    {
        public ushort Id;
        public byte SubType;
        public string Name = "";
        public uint Weight, Buy, Sell;
        public const uint NoPrice = 0xFFFFFFFF;
        public bool Buyable => Buy > 0 && Buy != NoPrice;
        public bool Sellable => Sell > 0 && Sell != NoPrice;
    }

    /// <summary>The currency of an NPC that trades for something else than gold (extended opcode 113, action "currency").</summary>
    public sealed class NpcCurrency
    {
        public string Name = "";
        public int Item;
        public ulong Amount;
        public bool Again;
    }

    public sealed class NpcTradeState
    {
        /// <summary>The most one request buys or sells: the main client's limit without the double sell amount feature.</summary>
        public const int MaxAmount = 100;
        public const double CurrencyTtlMs = 15000;
        public const int OpcodeCurrency = 113;

        public bool Open;
        public string Npc = "";
        public readonly List<ShopItem> Items = new List<ShopItem>();
        /// <summary>The player's goods the NPC may buy: client id to count.</summary>
        public readonly Dictionary<ushort, int> Goods = new Dictionary<ushort, int>();
        public ulong Money;
        public NpcCurrency Currency;
        /// <summary>Counts every change: a window rebuilds its list when this moves.</summary>
        public int Version;
        NpcCurrency pending;
        double pendingAt;

        public void SetShop(string npc, IEnumerable<ShopItem> items, double nowMs)
        {
            Open = true;
            Npc = npc ?? "";
            Items.Clear();
            Items.AddRange(items);
            Goods.Clear();
            Currency = null;
            if (pending != null && nowMs - pendingAt <= CurrencyTtlMs) Currency = pending;
            pending = null;
            Version++;
        }

        public void SetGoods(ulong money, IEnumerable<KeyValuePair<ushort, int>> goods)
        {
            Money = money;
            Goods.Clear();
            foreach (var g in goods) Goods[g.Key] = Goods.TryGetValue(g.Key, out int have) ? have + g.Value : g.Value;
            Version++;
        }

        public void Close()
        {
            Open = false;
            Items.Clear();
            Goods.Clear();
            Currency = null;
            Version++;
        }

        /// <summary>A currency message: the balance of the open shop, or the currency of the shop that opens next.</summary>
        public void ReceiveCurrency(NpcCurrency c, double nowMs)
        {
            if (c == null) return;
            if (Open)
            {
                if (Currency == null) Currency = c; else Currency.Amount = c.Amount;
                Version++;
                return;
            }
            if (c.Again) return;
            pending = c;
            pendingAt = nowMs;
        }

        /// <summary>Opcode 113 payload data ({code, name, item, amount, again}) to a currency, null when it is no currency.</summary>
        public static NpcCurrency ParseCurrency(ExtMessage m)
        {
            if (m == null || m.Action != "currency" || m.Data == null) return null;
            string name = Json.Text(m.Data, "name");
            if (name.Length == 0) return null;
            double amount = Json.Number(m.Data, "amount", -1);
            if (amount < 0) return null;
            int item = Json.Int(m.Data, "item");
            return new NpcCurrency { Name = TitleCase(name), Item = item > 0 ? item : 0, Amount = (ulong)amount, Again = Json.Bool(m.Data, "again") };
        }

        public static string TitleCase(string s)
        {
            var sb = new System.Text.StringBuilder(s.Length);
            bool start = true;
            foreach (char c in s)
            {
                sb.Append(start ? char.ToUpperInvariant(c) : c);
                start = c == ' ';
            }
            return sb.ToString();
        }

        /// <summary>The balance the buttons read: the currency's when the NPC has one, else the player's money.</summary>
        public ulong Balance => Currency != null ? Currency.Amount : Money;
        public bool Gold => Currency == null;

        public int GoodsCount(ushort id) => Goods.TryGetValue(id, out int n) ? n : 0;

        /// <summary>What the NPC sells, by name, filtered by a search text (case does not matter, empty shows all).</summary>
        public List<ShopItem> BuyList(string filter) => Filter(Items.FindAll(i => i.Buyable), filter);

        /// <summary>What the NPC buys and the player carries, by name.</summary>
        public List<ShopItem> SellList(string filter) => Filter(Items.FindAll(i => i.Sellable && GoodsCount(i.Id) > 0), filter);

        public List<ShopItem> List(TradeMode mode, string filter) => mode == TradeMode.Buy ? BuyList(filter) : SellList(filter);

        static List<ShopItem> Filter(List<ShopItem> list, string filter)
        {
            if (!string.IsNullOrWhiteSpace(filter))
            {
                string f = filter.Trim();
                list = list.FindAll(i => i.Name.IndexOf(f, StringComparison.OrdinalIgnoreCase) >= 0);
            }
            list.Sort((a, b) => string.Compare(a.Name, b.Name, StringComparison.OrdinalIgnoreCase));
            return list;
        }

        public static uint Price(ShopItem it, TradeMode mode) => mode == TradeMode.Buy ? it.Buy : it.Sell;

        /// <summary>The most the player can buy now: money, capacity (unless ignored), 100 at a time. 0 when nothing.</summary>
        public int MaxBuy(ShopItem it, uint freeCap, bool ignoreCap)
        {
            if (it == null || !it.Buyable) return 0;
            ulong byMoney = Balance / it.Buy;
            ulong n = Math.Min(byMoney, (ulong)MaxAmount);
            if (!ignoreCap && it.Weight > 0) n = Math.Min(n, freeCap / it.Weight);
            return (int)n;
        }

        /// <summary>The most the player can sell of one row: what the player carries, 100 at a time.</summary>
        public int MaxSell(ShopItem it)
        {
            if (it == null || !it.Sellable) return 0;
            return Math.Min(GoodsCount(it.Id), MaxAmount);
        }

        public int Max(ShopItem it, TradeMode mode, uint freeCap, bool ignoreCap) =>
            mode == TradeMode.Buy ? MaxBuy(it, freeCap, ignoreCap) : MaxSell(it);

        public static int ClampAmount(int amount, int max) => max <= 0 ? 0 : Math.Max(1, Math.Min(amount, max));

        public static ulong Total(ShopItem it, int amount, TradeMode mode) => it == null || amount <= 0 ? 0 : (ulong)Price(it, mode) * (ulong)amount;

        /// <summary>Why a buy cannot go, null when it can: "money", "capacity" or "none".</summary>
        public string BuyBlock(ShopItem it, int amount, uint freeCap, bool ignoreCap)
        {
            if (it == null || !it.Buyable || amount < 1 || amount > MaxAmount) return "none";
            if (Total(it, amount, TradeMode.Buy) > Balance) return "money";
            if (!ignoreCap && (ulong)it.Weight * (ulong)amount > freeCap) return "capacity";
            return null;
        }

        public string SellBlock(ShopItem it, int amount)
        {
            if (it == null || !it.Sellable || amount < 1 || amount > MaxAmount) return "none";
            if (amount > GoodsCount(it.Id)) return "none";
            return null;
        }

        /// <summary>The packet for a buy, null when the rules forbid it.</summary>
        public byte[] BuyRequest(ShopItem it, int amount, uint freeCap, bool ignoreCap, bool inBackpacks = false) =>
            BuyBlock(it, amount, freeCap, ignoreCap) != null ? null : NpcPackets.Buy(it.Id, it.SubType, (byte)amount, ignoreCap, inBackpacks);

        public byte[] SellRequest(ShopItem it, int amount, bool ignoreEquipped = true) =>
            SellBlock(it, amount) != null ? null : NpcPackets.Sell(it.Id, it.SubType, (byte)amount, ignoreEquipped);

        // ---- the parsers of 0x7A and 0x7B (the reader is after the opcode)

        public void ReadShop(ByteReader r, double nowMs)
        {
            string npc = r.Str();
            int n = r.U16();
            var items = new List<ShopItem>(Math.Min(n, 512));
            for (int i = 0; i < n; i++)
            {
                var it = new ShopItem { Id = r.U16(), SubType = r.U8(), Name = r.Str(), Weight = r.U32(), Buy = r.U32(), Sell = r.U32() };
                items.Add(it);
            }
            SetShop(npc, items, nowMs);
        }

        public void ReadGoods(ByteReader r)
        {
            ulong money = r.U64();
            int n = r.U8();
            var goods = new List<KeyValuePair<ushort, int>>(n);
            for (int i = 0; i < n; i++)
            {
                ushort id = r.U16();
                int count = r.U8();
                goods.Add(new KeyValuePair<ushort, int>(id, count));
            }
            SetGoods(money, goods);
        }
    }

    public static class NpcPackets
    {
        /// <summary>0x79: look at a shop row.</summary>
        public static byte[] Look(ushort id, byte subType) => new ByteWriter().U8(0x79).U16(id).U8(subType).ToArray();
        /// <summary>0x7A: buy. 10.98: u16 id, u8 sub type, u8 amount, u8 ignore capacity, u8 in backpacks.</summary>
        public static byte[] Buy(ushort id, byte subType, byte amount, bool ignoreCap, bool inBackpacks) =>
            new ByteWriter().U8(0x7A).U16(id).U8(subType).U8(amount).U8((byte)(ignoreCap ? 1 : 0)).U8((byte)(inBackpacks ? 1 : 0)).ToArray();
        /// <summary>0x7B: sell. u16 id, u8 sub type, u8 amount, u8 ignore equipped.</summary>
        public static byte[] Sell(ushort id, byte subType, byte amount, bool ignoreEquipped) =>
            new ByteWriter().U8(0x7B).U16(id).U8(subType).U8(amount).U8((byte)(ignoreEquipped ? 1 : 0)).ToArray();
        /// <summary>0x7C: close the shop.</summary>
        public static byte[] Close() => new byte[] { 0x7C };
        /// <summary>0x96, talk type 12 (player to NPC, the NPC channel): the words of a player the NPC is focused on.</summary>
        public static byte[] SayToNpc(string text) => new ByteWriter().U8(0x96).U8(NpcTalkState.TalkToNpc).Str(text).ToArray();
    }

    public sealed class NpcLine
    {
        public string Speaker = "", Text = "";
        public bool FromNpc;
        public double At;
    }

    public struct NpcSegment
    {
        public string Text;
        public bool Key;
    }

    public sealed class NpcTalkState
    {
        public const byte TalkNpcFrom = 10, TalkNpcFromConsole = 11, TalkToNpc = 12;
        public const int MaxLines = 200;
        public const int MaxChips = 12;
        /// <summary>The stock NpcHandler forgets an idle player after 120 seconds.</summary>
        public const double IdleMs = 120000;
        public static readonly string[] QuickWords = { "hi", "trade", "bye" };
        public static readonly string[] AnswerWords = { "yes", "no" };

        public readonly List<NpcLine> Lines = new List<NpcLine>();
        public string Npc = "";
        public int Version;
        double lastAt = -1e12;
        bool focused;

        /// <summary>The NPC spoke to us lately and we did not say goodbye.</summary>
        public bool Focused(double nowMs) => focused && nowMs - lastAt <= IdleMs;

        public static bool IsNpcTalkType(byte type) => type == TalkNpcFrom || type == TalkNpcFromConsole;

        public void FromNpc(string npc, string text, double nowMs)
        {
            Npc = npc ?? "";
            focused = true;
            lastAt = nowMs;
            Add(Npc, text, true, nowMs);
        }

        public void FromPlayer(string player, string text, double nowMs)
        {
            lastAt = nowMs;
            if (IsFarewell(text)) focused = false;
            Add(player, text, false, nowMs);
        }

        void Add(string who, string text, bool npc, double nowMs)
        {
            Lines.Add(new NpcLine { Speaker = who ?? "", Text = text ?? "", FromNpc = npc, At = nowMs });
            if (Lines.Count > MaxLines) Lines.RemoveRange(0, Lines.Count - MaxLines);
            Version++;
        }

        public void Clear() { Lines.Clear(); Npc = ""; focused = false; Version++; }

        public static bool IsGreeting(string text)
        {
            string t = (text ?? "").Trim().ToLowerInvariant();
            return t == "hi" || t == "hello" || t == "hail";
        }

        public static bool IsFarewell(string text)
        {
            string t = (text ?? "").Trim().ToLowerInvariant();
            return t == "bye" || t == "farewell" || t == "goodbye" || t == "good bye";
        }

        /// <summary>Where a line goes: the default channel to start a conversation (and for a greeting), the NPC channel
        /// once the NPC is focused on us (the stock NPC library takes keywords of a focused player only from there).</summary>
        public bool ToNpcChannel(string text, double nowMs) => Focused(nowMs) && !IsGreeting(text);

        // ---- {keywords} in the NPC's text, as game_npctalk's npctalk_logic.lua

        public static List<NpcSegment> Segments(string text)
        {
            var parts = new List<NpcSegment>();
            text = text ?? "";
            int cursor = 0;
            while (cursor < text.Length)
            {
                int open = text.IndexOf('{', cursor);
                int close = open < 0 ? -1 : text.IndexOf('}', open + 1);
                if (open < 0 || close < 0 || text.IndexOf('{', open + 1, close - open - 1) >= 0)
                {
                    if (open >= 0 && close >= 0)
                    {   // a nested open brace: the first one is plain text
                        AddPart(parts, text.Substring(cursor, open + 1 - cursor), false);
                        cursor = open + 1;
                        continue;
                    }
                    AddPart(parts, text.Substring(cursor), false);
                    break;
                }
                if (open > cursor) AddPart(parts, text.Substring(cursor, open - cursor), false);
                string word = text.Substring(open + 1, close - open - 1).Trim();
                if (word.Length > 0) parts.Add(new NpcSegment { Text = word, Key = true });
                cursor = close + 1;
            }
            return parts;
        }

        static void AddPart(List<NpcSegment> parts, string s, bool key)
        {
            if (s.Length == 0) return;
            if (!key && parts.Count > 0 && !parts[parts.Count - 1].Key)
            {
                var last = parts[parts.Count - 1];
                last.Text += s;
                parts[parts.Count - 1] = last;
                return;
            }
            parts.Add(new NpcSegment { Text = s, Key = key });
        }

        /// <summary>The line as the player reads it: no braces.</summary>
        public static string Plain(string text)
        {
            var sb = new System.Text.StringBuilder();
            foreach (var p in Segments(text)) sb.Append(p.Text);
            return sb.ToString();
        }

        /// <summary>The keywords of a text, in order, each once (case does not matter), at most MaxChips.</summary>
        public static List<string> Keywords(string text)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var list = new List<string>();
            foreach (var p in Segments(text))
                if (p.Key && seen.Add(p.Text) && list.Count < MaxChips) list.Add(p.Text);
            return list;
        }

        /// <summary>The keywords of the last NPC line (what the player can answer now).</summary>
        public List<string> CurrentKeywords()
        {
            for (int i = Lines.Count - 1; i >= 0; i--)
                if (Lines[i].FromNpc) return Keywords(Lines[i].Text);
            return new List<string>();
        }

        /// <summary>For a private NPC line (talk type 10 / 11) in a payload: does a position (u16 x, u16 y, u8 z) come before the text?
        /// TFS sends one for creature speech; a line without is also accepted. The reader is right after the type byte.</summary>
        public static bool HasPosition(ByteReader r)
        {
            int rem = r.Remaining;
            var b = r.Buffer;
            int p = r.Pos;
            bool plain = rem >= 2 && 2 + (b[p] | (b[p + 1] << 8)) <= rem;
            bool withPos = rem >= 7 && b[p + 4] <= 15 && 7 + (b[p + 5] | (b[p + 6] << 8)) <= rem;
            if (withPos && !plain) return true;
            if (plain && !withPos) return false;
            if (!withPos) return false;
            // both fit: an exact fit decides, else the position (what the server sends)
            bool exactPos = 7 + (b[p + 5] | (b[p + 6] << 8)) == rem;
            bool exactPlain = 2 + (b[p] | (b[p + 1] << 8)) == rem;
            return exactPos || !exactPlain;
        }
    }
}
