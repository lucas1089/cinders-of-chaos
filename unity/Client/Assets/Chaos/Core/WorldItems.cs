// Item and economy utilities, part 1 (client game_autoloot 216, game_pouches 226, game_orbexchange 209, game_gamble 199, game_embercache 174). Pure models.
//
// autoloot 216    client open | add {name} | add {clientId, quiet} | remove {name} | remove {clientId, quiet} | clear | sync; server open {itemsTable = [[clientId, name]], currentSlot, maxSlot} | list {..}
// pouches 226     client open | sync | set {rules} | as_open | as_sync | sell | asrar {tier, on} | aslist {op = add|remove|clear, item} | aspause {on} | asevery {minutes}
//                 server settings {rules, ids = {loot, orbs, keys}, titles, owned, rarities, open} | autoseller {unlocked, needs, paused, interval, intervals, nextIn, tiers, list, slots, cooldown, cooldownMax, last, notice, open}
// orbexchange 209 client open | book {base, quote, seq} | place {give, giveQty, want, wantQty, days} | cancel {id} | mine | wallet
//                 server meta {orbs, fees, min, max, durations, defaultDuration, maxOpen, realmName, gold, have} | book {...} | mine {open, closed, fills, owed, max} | wallet {gold, have} | done {what, text} | error {text}
// gamble 199      client open | close | buy {i, w, id} | reroll {w}; server state {...} | result {ok, text, reveal} | npc {}
// embercache 174  client open | close | get | offerQuote | offer; server state {open?, week, day, src, book} | offer {orbs, points, room, per, carried}
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>Shared number and text helpers of the item utilities.</summary>
    public static class WorldText
    {
        /// <summary>1234567 as "1,234,567".</summary>
        public static string Thousands(double v)
        {
            long n = (long)Math.Floor(Math.Abs(v));
            string s = n.ToString(CultureInfo.InvariantCulture), o = "";
            for (int i = 0; i < s.Length; i++) { if (i > 0 && (s.Length - i) % 3 == 0) o += ","; o += s[i]; }
            return (v < 0 ? "-" : "") + o;
        }

        /// <summary>1500 as "1.5k", 2000000 as "2M" (T, B, M, k).</summary>
        public static string Short(double n)
        {
            n = Math.Max(0, Math.Floor(n));
            var units = new[] { new KeyValuePair<double, string>(1e12, "T"), new KeyValuePair<double, string>(1e9, "B"), new KeyValuePair<double, string>(1e6, "M"), new KeyValuePair<double, string>(1e3, "k") };
            foreach (var u in units)
                if (n >= u.Key)
                {
                    double v = n / u.Key;
                    string s = v >= 100 ? ((long)Math.Floor(v)).ToString(CultureInfo.InvariantCulture) : (Math.Floor(v * 10) / 10).ToString("0.#", CultureInfo.InvariantCulture);
                    return s + u.Value;
                }
            return ((long)n).ToString(CultureInfo.InvariantCulture);
        }

        public static string Cap(string s) => string.IsNullOrEmpty(s) ? "" : char.ToUpperInvariant(s[0]) + s.Substring(1);

        /// <summary>Words wrapped to n characters a line.</summary>
        public static List<string> Wrap(string text, int n)
        {
            var lines = new List<string>();
            string line = "";
            foreach (string w in (text ?? "").Split(new[] { ' ', '\t', '\n' }, StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.Length == 0) line = w;
                else if (line.Length + 1 + w.Length <= n) line += " " + w;
                else { lines.Add(line); line = w; }
            }
            if (line.Length > 0) lines.Add(line);
            return lines;
        }

        public static int N(object o, string key) => Json.Int(o, key);
        public static int ClientId(object v)
        {
            if (!(v is double d) || double.IsNaN(d) || d < 1 || d > 65535 || d != Math.Floor(d)) return 0;
            return (int)d;
        }
    }

    // ------------------------------------------------------------------------------------------------ auto loot
    public sealed class AutoLootRow { public int ClientId; public string Name = ""; }

    public sealed class AutoLootState
    {
        public const byte Opcode = 216;
        readonly ExtOpcodes ext;
        public readonly List<AutoLootRow> Rows = new List<AutoLootRow>();
        readonly HashSet<int> known = new HashSet<int>();
        public int CurrentSlot, MaxSlot;
        public bool Visible;
        public Action Changed = delegate { };

        public AutoLootState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public void Sync() { known.Clear(); Send("sync"); }
        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void Clear() { Send("clear"); }
        public bool IsOnList(int clientId) => known.Contains(clientId);

        /// <summary>The text of the add box: a number is a client id, anything else an item name.</summary>
        public bool AddText(string text)
        {
            text = (text ?? "").Trim();
            if (text.Length == 0) return false;
            if (int.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out int id)) Send("add", new Dictionary<string, object> { { "clientId", id } });
            else Send("add", new Dictionary<string, object> { { "name", text } });
            return true;
        }

        public void RemoveName(string name) { Send("remove", new Dictionary<string, object> { { "name", name } }); }

        /// <summary>The item menu: add or remove one item by client id; the window stays closed (the server answers "list").</summary>
        public bool AddItem(int clientId) { if (clientId <= 0) return false; Send("add", new Dictionary<string, object> { { "clientId", clientId }, { "quiet", true } }); return true; }
        public bool RemoveItem(int clientId) { if (clientId <= 0) return false; Send("remove", new Dictionary<string, object> { { "clientId", clientId }, { "quiet", true } }); return true; }

        public string SlotsText() => Loc.T("Current Slots: {0}/{1}", CurrentSlot, MaxSlot);

        public void Handle(string action, object data)
        {
            if (action != "open" && action != "list") return;
            Rows.Clear(); known.Clear();
            foreach (object r in Json.List(data, "itemsTable"))
            {
                if (!(r is List<object> a) || a.Count < 2 || !(a[0] is double cid)) continue;
                Rows.Add(new AutoLootRow { ClientId = (int)cid, Name = a[1] as string ?? "" });
                known.Add((int)cid);
            }
            CurrentSlot = Json.Int(data, "currentSlot"); MaxSlot = Json.Int(data, "maxSlot");
            if (action == "open") Visible = true;
            Changed();
        }

        public void Clean() { Rows.Clear(); known.Clear(); Visible = false; }
    }

    // ------------------------------------------------------------------------------------------------ pouches and auto seller
    public sealed class PouchRules
    {
        public bool List, Gold, Uniques, Gear, Supplies, Gems, Other, Overflow = true;
        public int MinRarity = 5;
    }

    public sealed class AutoSellTier { public string Key = "", Name = "", Color = ""; public bool On; }
    public sealed class AutoSellItem { public int Id; public string Name = ""; public long Price; }

    public sealed class AutoSellerState
    {
        public const string Needs = "Needs the Auto Seller (Store > Convenience) or an active Chaos Pact.";
        public static readonly string[] TierKeys = { "common", "uncommon", "magic", "rare", "legendary", "divine" };
        public static readonly string[] TierNames = { "Common", "Uncommon", "Magic", "Rare", "Legendary", "Divine" };
        public static readonly string[] TierColors = { "#c8c8c8", "#5ccf5c", "#4a90ff", "#a35cf0", "#ffd040", "#c8e8ff" };
        public static readonly int[] Intervals = { 5, 10, 15, 30, 60 };

        public bool Unlocked, Paused, Open;
        public string NeedsText = Needs, Notice = "";
        public int Interval, Slots = 40, Cooldown, CooldownMax = 30;
        public List<int> IntervalChoices = new List<int>(Intervals);
        public readonly List<AutoSellTier> Tiers = new List<AutoSellTier>();
        public readonly List<AutoSellItem> List = new List<AutoSellItem>();
        public bool HasLast;
        public long LastGold;
        public int LastCount;
        public double StateAt;   // ms when the state came (the cooldown counts down from it)

        public AutoSellerState() { Normalize(null, 0); }

        public static int IntervalOf(double? v)
        {
            if (v == null) return -1;
            if (v == 0) return 0;
            foreach (int m in Intervals) if (v == m) return m;
            return -1;
        }

        public void Normalize(object s, double now)
        {
            Unlocked = Json.Truthy(s, "unlocked"); Paused = Json.Truthy(s, "paused"); Open = Json.Truthy(s, "open");
            NeedsText = Json.Text(s, "needs", Needs); Notice = Json.Text(s, "notice");
            Interval = Math.Max(0, IntervalOf(Json.Get(s, "interval") as double?));
            Slots = Math.Max(0, Json.Get(s, "slots") is double sl ? (int)sl : 40);
            Cooldown = Math.Max(0, Json.Int(s, "cooldown")); CooldownMax = Math.Max(1, Json.Get(s, "cooldownMax") is double cm ? (int)cm : 30);
            IntervalChoices = new List<int>();
            foreach (object m in Json.List(s, "intervals")) { int v = IntervalOf(m as double?); if (v > 0) IntervalChoices.Add(v); }
            if (IntervalChoices.Count == 0) IntervalChoices = new List<int>(Intervals);
            var on = new Dictionary<string, bool>();
            foreach (object t in Json.List(s, "tiers")) if (t is Dictionary<string, object>) on[Json.Text(t, "key")] = Json.Truthy(t, "on");
            Tiers.Clear();
            for (int i = 0; i < TierKeys.Length; i++)
            {
                bool v = on.TryGetValue(TierKeys[i], out bool b) ? b : (TierKeys[i] == "common" || TierKeys[i] == "uncommon");
                Tiers.Add(new AutoSellTier { Key = TierKeys[i], Name = TierNames[i], Color = TierColors[i], On = v });
            }
            List.Clear();
            foreach (object e in Json.List(s, "list"))
                if (e is Dictionary<string, object> && Json.Get(e, "name") != null)
                    List.Add(new AutoSellItem { Id = Json.Int(e, "id"), Name = Json.Text(e, "name"), Price = (long)Json.Number(e, "price") });
            var last = Json.Get(s, "last");
            HasLast = last is Dictionary<string, object> && Json.Get(last, "gold") is double;
            if (HasLast) { LastGold = (long)Json.Number(last, "gold"); LastCount = Json.Int(last, "count"); }
            StateAt = now;
        }

        public int CooldownLeft(double now) => Math.Max(0, Cooldown - (int)Math.Floor((now - StateAt) / 1000));
        public string SellText(int left) => left > 0 ? Loc.T("Sell all ({0} s)", left) : Loc.T("Sell all");
        public bool SellEnabled(int left) => Unlocked && left <= 0;
        public string LastSaleText() => !HasLast ? Loc.T("Last sale: none yet.") : Loc.T("Last sale: {0} gold ({1} item{2}).", WorldText.Thousands(LastGold), LastCount, LastCount == 1 ? "" : "s");
        public string ListText()
        {
            var parts = new List<string>();
            foreach (var e in List) parts.Add(e.Name + " (" + WorldText.Thousands(e.Price) + ")");
            string head = Loc.T("{0}/{1} items", parts.Count, Slots);
            return parts.Count == 0 ? Loc.T("{0}: none. Add items an NPC buys.", head) : head + ": " + string.Join(", ", parts);
        }
        public string LockedTip() => Unlocked ? "" : NeedsText;
        public string IntervalLabel(int minutes) => minutes == 0 ? Loc.T("Off") : Loc.T("{0} minutes", minutes);
    }

    public sealed class PouchesState
    {
        public const byte Opcode = 226;
        public static readonly string[] Flags = { "list", "gold", "uniques", "gear", "supplies", "gems", "other", "overflow" };
        public static readonly int[] RarityIds = { 1, 2, 3, 4, 5, 10 };
        public static readonly string[] RarityNames = { "Common", "Uncommon", "Magic", "Rare", "Legendary", "Divine" };

        readonly ExtOpcodes ext;
        public PouchRules Rules = new PouchRules();
        public readonly Dictionary<string, int> Ids = new Dictionary<string, int>();
        public readonly Dictionary<string, string> Titles = new Dictionary<string, string>();
        public readonly Dictionary<string, bool> Owned = new Dictionary<string, bool>();
        public readonly List<string> Rarities = new List<string>();
        public readonly AutoSellerState Seller = new AutoSellerState();
        public bool Visible, SellerVisible, SellerKnown;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public PouchesState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        /// <summary>An id of today's rarity: 6..9 are Legendary (5), 10..15 are Divine (10); at least 1.</summary>
        public static int CanonRarity(double id)
        {
            int i = (int)Math.Floor(id);
            if (i <= 1) return 1;
            if (i <= 5) return i;
            return i <= 9 ? 5 : 10;
        }

        public static PouchRules Normalize(object r)
        {
            var o = new PouchRules();
            bool F(string k, bool dflt) => Json.Get(r, k) == null ? dflt : Json.Truthy(r, k);
            o.List = F("list", false); o.Gold = F("gold", false); o.Uniques = F("uniques", false); o.Gear = F("gear", false);
            o.Supplies = F("supplies", false); o.Gems = F("gems", false); o.Other = F("other", false); o.Overflow = F("overflow", true);
            o.MinRarity = CanonRarity(Json.Get(r, "minRarity") is double d ? d : 5);
            return o;
        }

        public static Dictionary<string, object> RulesMessage(PouchRules r) => new Dictionary<string, object>
        {
            { "list", r.List }, { "gold", r.Gold }, { "uniques", r.Uniques }, { "gear", r.Gear }, { "supplies", r.Supplies }, { "gems", r.Gems }, { "other", r.Other },
            { "overflow", r.Overflow }, { "minRarity", r.MinRarity },
        };

        public bool Flag(string k)
        {
            switch (k) { case "list": return Rules.List; case "gold": return Rules.Gold; case "uniques": return Rules.Uniques; case "gear": return Rules.Gear; case "supplies": return Rules.Supplies; case "gems": return Rules.Gems; case "other": return Rules.Other; default: return Rules.Overflow; }
        }

        public void SetFlag(string k, bool on)
        {
            switch (k) { case "list": Rules.List = on; break; case "gold": Rules.Gold = on; break; case "uniques": Rules.Uniques = on; break; case "gear": Rules.Gear = on; break; case "supplies": Rules.Supplies = on; break; case "gems": Rules.Gems = on; break; case "other": Rules.Other = on; break; default: Rules.Overflow = on; break; }
            SendRules();
        }

        public void SetMinRarity(int id) { Rules.MinRarity = CanonRarity(id); SendRules(); }
        public void SendRules() { Send("set", new Dictionary<string, object> { { "rules", RulesMessage(Rules) } }); }
        public static int RarityIndex(int minRarity) { int c = CanonRarity(minRarity); for (int i = 0; i < RarityIds.Length; i++) if (RarityIds[i] == c) return i; return 0; }
        public string RarityName(int i) => Loc.T(i < Rarities.Count && Rarities[i].Length > 0 ? Rarities[i] : RarityNames[Math.Max(0, Math.Min(RarityNames.Length - 1, i))]);

        /// <summary>The line under the title: whether this character has the Loot Bag.</summary>
        public string StatusText()
        {
            if (Owned.Count == 0) return "";
            string title = Titles.TryGetValue("loot", out string t) && t.Length > 0 ? t : Loc.T("Loot Bag");
            if (Owned.TryGetValue("loot", out bool has) && has) return Loc.T("You have a {0}. It collects while you carry it (backpack or a bag inside it).", title);
            return Loc.T("You have no {0} yet: Store > Convenience. These rules are kept for when you do.", title);
        }

        /// <summary>The item looks like the Loot Bag (client id from the server) and carries the item lock flag the server sets on every store pouch.</summary>
        public bool IsLootPouch(int clientId, ulong lockFlag) => Ids.TryGetValue("loot", out int id) && id != 0 && clientId == id && lockFlag != 0;

        public void Open() { Visible = true; Send("open"); }
        public void Sync() { Send("sync"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void SellerOpen() { SellerVisible = true; Send("as_open"); }
        public void SellerToggle() { if (SellerVisible) SellerVisible = false; else SellerOpen(); }
        public void Sell() { Send("sell"); }
        public void SetTier(string key, bool on) { Send("asrar", new Dictionary<string, object> { { "tier", key }, { "on", on } }); }
        public void SetPaused(bool on) { Send("aspause", new Dictionary<string, object> { { "on", on } }); }
        public void SetEvery(int minutes) { if (AutoSellerState.IntervalOf(minutes) >= 0) Send("asevery", new Dictionary<string, object> { { "minutes", minutes } }); }

        public bool ListRequest(string op, string text)
        {
            if (op == "clear") { Send("aslist", new Dictionary<string, object> { { "op", "clear" } }); return true; }
            if (op != "add" && op != "remove") return false;
            text = (text ?? "").Trim();
            if (text.Length == 0) return false;
            if (text.Length > 80) text = text.Substring(0, 80);
            Send("aslist", new Dictionary<string, object> { { "op", op }, { "item", text } });
            return true;
        }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            if (action == "autoseller")
            {
                Seller.Normalize(d, Clock());
                SellerKnown = true;
                if (Seller.Open) SellerVisible = true;
                Changed();
                return;
            }
            if (action != "settings") return;
            Rules = Normalize(Json.Get(d, "rules"));
            var ids = Json.Get(d, "ids");
            if (ids is Dictionary<string, object> im) { Ids.Clear(); foreach (var kv in im) if (kv.Value is double v) Ids[kv.Key] = (int)v; }
            var titles = Json.Get(d, "titles");
            if (titles is Dictionary<string, object> tm) { Titles.Clear(); foreach (var kv in tm) if (kv.Value is string s) Titles[kv.Key] = s; }
            var rar = Json.Get(d, "rarities");
            if (rar is List<object> rl) { Rarities.Clear(); foreach (object o in rl) Rarities.Add(o as string ?? ""); }
            var own = Json.Get(d, "owned");
            if (own is Dictionary<string, object> om) { Owned.Clear(); foreach (var kv in om) if (kv.Value != null) Owned[kv.Key] = Json.Truthy(kv.Value); }
            if (Json.Truthy(d, "open")) Visible = true;
            Changed();
        }

        public void Clear() { Visible = false; SellerVisible = false; SellerKnown = false; Rules = new PouchRules(); Owned.Clear(); }
    }

    // ------------------------------------------------------------------------------------------------ orb exchange
    public sealed class OrbBookRow { public string Kind = "", Price = "", Qty = "", Orders = "", Total = ""; public double P, Q, Bar; }

    public sealed class OrbForm { public string Side = "buy", Qty = "", Price = ""; public int Days; }

    public sealed class OrbExchangeState
    {
        public const byte Opcode = 209;
        public const string Gold = "gold";
        public const double RefreshSeconds = 5;

        readonly ExtOpcodes ext;
        public object Meta, Book, Mine;
        public string Base = "", Quote = Gold, Status = "";
        public bool StatusGood, Visible;
        public int Tab;   // 0 book, 1 mine
        int seq;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public OrbExchangeState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        // ---- text and numbers (orbexchangeview.lua)
        public static string Money(double n)
        {
            if (double.IsNaN(n)) return "0";
            return WorldText.Thousands(Math.Floor(n));
        }

        /// <summary>"1.5k", "2m", "3b" or a plain number to a whole amount; -1 when it is no number.</summary>
        public static double ParseAmount(string text)
        {
            double v = ParsePrice(text);
            return v < 0 ? -1 : Math.Floor(v + 0.5);
        }

        public static double ParsePrice(string text)
        {
            string s = (text ?? "").ToLowerInvariant().Replace(" ", "").Replace(",", "");
            if (s.Length == 0) return -1;
            double mult = 1;
            char last = s[s.Length - 1];
            if (last == 'k') { mult = 1e3; s = s.Substring(0, s.Length - 1); }
            else if (last == 'm') { mult = 1e6; s = s.Substring(0, s.Length - 1); }
            else if (last == 'b') { mult = 1e9; s = s.Substring(0, s.Length - 1); }
            if (!double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out double num) || num <= 0 || s.StartsWith("-", StringComparison.Ordinal)) return -1;
            return num * mult;
        }

        public static string PriceText(double p)
        {
            if (double.IsNaN(p)) return "-";
            if (p >= 1000) return Money(Math.Floor(p + 0.5));
            string s = p >= 100 ? p.ToString("0.0", CultureInfo.InvariantCulture) : p >= 1 ? p.ToString("0.00", CultureInfo.InvariantCulture) : p >= 0.01 ? p.ToString("0.0000", CultureInfo.InvariantCulture) : p.ToString("0.000000", CultureInfo.InvariantCulture);
            if (s.Contains(".")) s = s.TrimEnd('0').TrimEnd('.');
            return s;
        }

        public static string Compact(double n)
        {
            if (n >= 1e9) return PriceText(n / 1e9) + "b";
            if (n >= 1e6) return PriceText(n / 1e6) + "m";
            if (n >= 10000) return PriceText(n / 1e3) + "k";
            return Money(n);
        }

        public static string Ago(double s) => s < 60 ? "now" : s < 3600 ? ((int)(s / 60)) + "m" : s < 86400 ? ((int)(s / 3600)) + "h" : ((int)(s / 86400)) + "d";

        public static string TimeLeft(double s)
        {
            if (s <= 0) return "ending";
            if (s >= 86400) return (int)(s / 86400) + "d " + (int)(s % 86400 / 3600) + "h";
            if (s >= 3600) return (int)(s / 3600) + "h " + (int)(s % 3600 / 60) + "m";
            return Math.Max(1, (int)(s / 60)) + "m";
        }

        public string AssetName(string key)
        {
            if (key == Gold) return "gold";
            foreach (object o in Json.List(Meta, "orbs")) if (Json.Text(o, "k") == key) return Json.Text(o, "n", key);
            return key ?? "?";
        }

        public string ShortName(string key)
        {
            string n = AssetName(key);
            return n.StartsWith("Orbs of ", StringComparison.Ordinal) ? n.Substring(8) : n.StartsWith("Orb of ", StringComparison.Ordinal) ? n.Substring(7) : n;
        }

        public string Amount(string key, double n) => Money(n) + " " + AssetName(key);

        public int OrbItem(string key)
        {
            foreach (object o in Json.List(Meta, "orbs")) if (Json.Text(o, "k") == key) return Json.Int(o, "item");
            return 0;
        }

        public List<string> Quotes(string baseKey)
        {
            var q = new List<string> { Gold };
            foreach (object o in Json.List(Meta, "orbs")) { string k = Json.Text(o, "k"); if (k != baseKey) q.Add(k); }
            return q;
        }

        public List<string> OrbKeys()
        {
            var l = new List<string>();
            foreach (object o in Json.List(Meta, "orbs")) l.Add(Json.Text(o, "k"));
            return l;
        }

        public double Have(string key) { var h = Json.Get(Meta, "have"); return h is Dictionary<string, object> ? Json.Number(h, key) : 0; }
        public double GoldHeld() => Json.Number(Meta, "gold");

        /// <summary>Checks the order form; gives the request or the reason, and a preview of the total, fee and what you receive.</summary>
        public bool Form(OrbForm f, string baseKey, string quote, out Dictionary<string, object> req, out string why, out double total, out double fee, out double placeFee, out double receive)
        {
            req = null; why = ""; total = fee = placeFee = receive = 0;
            double qty = ParseAmount(f.Qty);
            if (qty < 1) { why = Loc.T("Enter how many {0}.", AssetName(baseKey)); return false; }
            double price = ParsePrice(f.Price);
            if (price <= 0) { why = Loc.T("Enter a price per {0} in {1}.", ShortName(baseKey), AssetName(quote)); return false; }
            total = f.Side == "sell" ? Math.Floor(qty * price + 1e-9) : Math.Ceiling(qty * price - 1e-9);
            if (total < 1) { why = Loc.T("The total is less than one {0}.", AssetName(quote)); return false; }
            string give, want; double giveQty, wantQty;
            if (f.Side == "sell") { give = baseKey; giveQty = qty; want = quote; wantQty = total; }
            else { give = quote; giveQty = total; want = baseKey; wantQty = qty; }
            int days = f.Days > 0 ? f.Days : Json.Get(Meta, "defaultDuration") is double dd ? (int)dd : 7;
            req = new Dictionary<string, object> { { "give", give }, { "giveQty", giveQty }, { "want", want }, { "wantQty", wantQty }, { "days", days } };
            string Limits(string asset, double n)
            {
                string kind = asset == Gold ? "gold" : "orb";
                double lo = Json.Get(Json.Get(Meta, "min"), kind) is double l ? l : 1;
                if (n < lo) return Loc.T("At least {0} {1} per order.", Money(lo), AssetName(asset));
                if (Json.Get(Json.Get(Meta, "max"), kind) is double hi && n > hi) return Loc.T("At most {0} {1} per order.", Money(hi), AssetName(asset));
                return null;
            }
            string bad = Limits(give, giveQty) ?? Limits(want, wantQty);
            if (bad != null) { req = null; why = bad; return false; }
            var fees = Json.Get(Meta, "fees");
            if (quote == Gold) { if (f.Side == "sell") fee = Math.Floor(total * Json.Number(fees, "goldBps") / 10000); }
            else if (baseKey != Gold) placeFee = Json.Number(fees, "orbPairGold");
            receive = (f.Side == "sell" ? total : qty) - fee;
            return true;
        }

        public string PreviewText(Dictionary<string, object> req, string side, string baseKey, string quote, double total, double qty, double fee, double placeFee)
        {
            if (req == null) return "";
            var parts = new List<string>();
            double each = total / Math.Max(1, qty);
            if (side == "sell") parts.Add(Loc.T("You give {0} for at least {1} ({2} each).", Amount(baseKey, (double)req["giveQty"]), Amount(quote, (double)req["wantQty"]), PriceText(each)));
            else parts.Add(Loc.T("You give up to {0} for at least {1} ({2} each).", Amount(quote, (double)req["giveQty"]), Amount(baseKey, (double)req["wantQty"]), PriceText(each)));
            if (fee > 0) parts.Add(Loc.T("Fee {0} gold ({1}%) on the gold you receive.", Money(fee), PriceText(Json.Number(Json.Get(Meta, "fees"), "goldBps") / 100)));
            else if (quote == Gold && side == "buy") parts.Add(Loc.T("No fee for the buyer."));
            if (placeFee > 0) parts.Add(Loc.T("Orb-for-orb orders cost {0} gold from your bank.", Money(placeFee)));
            return string.Join(" ", parts);
        }

        /// <summary>The book as rows: asks (highest first), the spread row, then bids.</summary>
        public static List<OrbBookRow> BookRows(object book, int rowsPerSide = 8)
        {
            var asks = new List<object>(); var bids = new List<object>();
            foreach (object o in Json.List(book, "asks")) if (asks.Count < rowsPerSide) asks.Add(o);
            foreach (object o in Json.List(book, "bids")) if (bids.Count < rowsPerSide) bids.Add(o);
            double biggest = 0;
            foreach (object o in asks) biggest = Math.Max(biggest, Json.Number(o, "q"));
            foreach (object o in bids) biggest = Math.Max(biggest, Json.Number(o, "q"));
            OrbBookRow Row(string kind, object l) => new OrbBookRow
            {
                Kind = kind, P = Json.Number(l, "p"), Q = Json.Number(l, "q"), Price = PriceText(Json.Number(l, "p")), Qty = Money(Json.Number(l, "q")),
                Orders = Json.Get(l, "n") == null ? "1" : Json.Int(l, "n").ToString(CultureInfo.InvariantCulture), Total = Compact(Json.Number(l, "t")), Bar = biggest > 0 ? Json.Number(l, "q") / biggest : 0,
            };
            var rows = new List<OrbBookRow>();
            for (int i = asks.Count - 1; i >= 0; i--) rows.Add(Row("ask", asks[i]));
            var sp = new OrbBookRow { Kind = "spread" };
            if (asks.Count > 0 && bids.Count > 0)
            {
                double a = Json.Number(asks[0], "p"), b = Json.Number(bids[0], "p"), mid = (a + b) / 2;
                sp.Price = Loc.T("Spread {0}", PriceText(a - b));
                sp.Qty = mid > 0 ? PriceText((a - b) / mid * 100) + "%" : "";
            }
            else sp.Price = asks.Count + bids.Count == 0 ? Loc.T("No orders") : Loc.T("One side only");
            rows.Add(sp);
            for (int i = 0; i < bids.Count; i++) rows.Add(Row("bid", bids[i]));
            return rows;
        }

        public static string ChangeText(object change, out string color)
        {
            if (!(change is double c)) { color = "#8c8070"; return "-"; }
            color = c > 0 ? "#6cc46c" : c < 0 ? "#e05a4a" : "#8c8070";
            return (c >= 0 ? "+" : "") + c.ToString("0.0", CultureInfo.InvariantCulture) + "%";
        }

        public string OrderTitle(object o) => Loc.T("{0} for {1}", Amount(Json.Text(o, "give"), Json.Number(o, "giveQty")), Amount(Json.Text(o, "want"), Json.Number(o, "wantQty")));

        public string OrderPrice(object o)
        {
            double give = Json.Number(o, "giveQty"), want = Json.Number(o, "wantQty");
            if (give <= 0 || want <= 0) return "";
            string g = Json.Text(o, "give"), w = Json.Text(o, "want");
            if (g == Gold) return Loc.T("{0} gold per {1}", PriceText(give / want), ShortName(w));
            if (w == Gold) return Loc.T("{0} gold per {1}", PriceText(want / give), ShortName(g));
            if (want >= give) return Loc.T("{0} {1} per {2}", PriceText(want / give), ShortName(w), ShortName(g));
            return Loc.T("{0} {1} per {2}", PriceText(give / want), ShortName(g), ShortName(w));
        }

        public string OrderSub(object o)
        {
            string done = Loc.T("{0} / {1} given, {2} received", Money(Json.Number(o, "given")), Money(Json.Number(o, "giveQty")), Money(Json.Number(o, "got")));
            string state = Json.Text(o, "state");
            if (state == "active") return done + "  |  " + OrderPrice(o) + "  |  " + TimeLeft(Json.Number(o, "left")) + " left";
            if (state == "pending") return done + "  |  " + OrderPrice(o) + "  |  being placed";
            return (state.Length > 0 ? state : "?") + (Json.Get(o, "refunded") is double r ? ", " + Money(r) + " back" : "") + "  |  " + done;
        }

        public static double Progress(object o)
        {
            double g = Json.Number(o, "giveQty");
            return g <= 0 ? 0 : Math.Min(1, Json.Number(o, "given") / g);
        }

        public string FillText(object f)
        {
            string when = Ago(Json.Number(f, "ago"));
            string s = Loc.T("{0}: gave {1}, got {2}", when == "now" ? Loc.T("just now") : when + " ago", Amount(Json.Text(f, "gave"), Json.Number(f, "gaveQty")), Amount(Json.Text(f, "got"), Json.Number(f, "gotQty")));
            if (Json.Get(f, "fee") is double fee) s += Loc.T(" (fee {0})", Money(fee));
            return s;
        }

        /// <summary>A clicked book row fills the form: asks buy (price rounded up), bids sell.</summary>
        public static bool FromRow(OrbBookRow row, out OrbForm form)
        {
            form = null;
            if (row == null || (row.Kind != "ask" && row.Kind != "bid")) return false;
            bool buy = row.Kind == "ask";
            double scaled = row.P * 1000000;
            double n = buy ? Math.Ceiling(scaled - 1e-6) : Math.Floor(scaled + 1e-6);
            string s = (n / 1000000).ToString("0.000000", CultureInfo.InvariantCulture).TrimEnd('0').TrimEnd('.');
            form = new OrbForm { Side = buy ? "buy" : "sell", Price = s, Qty = Math.Floor(row.Q + 0.5).ToString(CultureInfo.InvariantCulture) };
            return true;
        }

        // ---- requests
        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void RequestBook() { if (Base.Length == 0) return; seq++; Send("book", new Dictionary<string, object> { { "base", Base }, { "quote", Quote }, { "seq", seq } }); }
        public void RequestMine() { Send("mine"); }
        public void RequestWallet() { Send("wallet"); }
        public void Cancel(int id) { Send("cancel", new Dictionary<string, object> { { "id", id } }); }
        public void Place(Dictionary<string, object> req) { if (req != null) Send("place", req); }
        public void SelectBase(string key) { Base = key; if (Quote == Base) Quote = Gold; RequestBook(); }
        public void SelectQuote(string key) { Quote = key; RequestBook(); }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            switch (action)
            {
                case "meta":
                    Meta = d;
                    if (Base.Length == 0) { var l = OrbKeys(); if (l.Count > 0) { Base = l[0]; RequestBook(); } }
                    break;
                case "book": if (Meta != null && Json.Text(d, "base") == Base && Json.Text(d, "quote") == Quote) Book = d; else return; break;
                case "mine": Mine = d; break;
                case "wallet":
                    if (Meta is Dictionary<string, object> m) { m["gold"] = Json.Get(d, "gold"); m["have"] = Json.Get(d, "have"); }
                    break;
                case "done":
                    Status = Json.Text(d, "text"); StatusGood = true;
                    if (Tab == 0) RequestBook(); else RequestMine();
                    RequestWallet();
                    break;
                case "error": Status = Json.Text(d, "text"); StatusGood = false; break;
                default: return;
            }
            Changed();
        }

        public void Clear() { Meta = null; Book = null; Mine = null; Base = ""; Quote = Gold; Visible = false; Status = ""; }
    }

    // ------------------------------------------------------------------------------------------------ gamble
    public sealed class GambleCell
    {
        public int I, Id, ClientId, Level;
        public string Name = "", SlotText = "", LevelText = "", PriceText = "", PriceColor = "", BuyText = "", Tip = "";
        public bool Sold, CanBuy;
    }

    public sealed class GambleState
    {
        public const byte Opcode = 199;
        public const double BuyWaitMs = 4000;
        public static readonly string[] Rarity = { "", "#c8c8c8", "#5ccf5c", "#4a90ff", "#a35cf0", "#ffd040", "#ffd040", "#ffd040", "#ffd040", "#ffd040", "#c8e8ff", "#c8e8ff", "#c8e8ff", "#c8e8ff", "#c8e8ff", "#c8e8ff" };

        readonly ExtOpcodes ext;
        public object State;
        public bool Visible, Buying;
        public string Status = "", StatusColor = "#8c8070";
        public double ReceivedAt, BuyAt;
        public object Reveal;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public GambleState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public static string Countdown(double sec)
        {
            int s = (int)Math.Max(0, Math.Floor(sec)), h = s / 3600, m = s % 3600 / 60, r = s % 60;
            if (h > 0) return h + "h " + m.ToString("00") + "m";
            if (m > 0) return m + "m " + r.ToString("00") + "s";
            return r + "s";
        }

        public static string ShortGold(double n)
        {
            if (n >= 1e6) return (n / 1e6).ToString("0.00", CultureInfo.InvariantCulture).TrimEnd('0').TrimEnd('.') + "M";
            if (n >= 10000) return (int)Math.Floor(n / 1000) + "k";
            return WorldText.Thousands(n);
        }

        public double Left(double elapsedSec) => Math.Max(0, Json.Number(State, "left") - Math.Max(0, elapsedSec));
        public string RefreshText(double elapsedSec) => State == null ? "" : Loc.T("New crates at {0} ({1}), in {2}", Json.Text(State, "at", "?"), Json.Text(State, "tz", Loc.T("server time")), Countdown(Left(elapsedSec)));
        public bool Near => Json.Truthy(State, "near");

        public bool CanBuy(object it) => State != null && Near && !Json.Truthy(it, "sold") && Json.Number(State, "money") >= Json.Number(it, "p");

        public List<GambleCell> Cells()
        {
            var o = new List<GambleCell>();
            if (State == null) return o;
            foreach (object raw in Json.List(State, "items"))
            {
                object it = raw is Dictionary<string, object> ? raw : new Dictionary<string, object> { { "sold", true } };
                bool sold = Json.Truthy(it, "sold");
                double p = Json.Number(it, "p");
                bool afford = Json.Number(State, "money") >= p;
                string npc = Json.Text(State, "npc", Loc.T("the Gambler"));
                string why = sold ? Loc.T("Sold. New crates come with the next stock.") : !Near ? Loc.T("Buy from {0} in person (in the market of the teleport room).", npc)
                    : !afford ? Loc.T("You need {0} gold (backpack and bank).", WorldText.Thousands(p)) : Loc.T("Pay {0} gold and break the seal.", WorldText.Thousands(p));
                string name = WorldText.Cap(Json.Text(it, "n"));
                string slot = Json.Text(it, "sn", Json.Text(it, "s"));
                o.Add(new GambleCell
                {
                    I = Json.Int(it, "i"), Id = Json.Int(it, "id"), ClientId = WorldText.ClientId(Json.Get(it, "c")), Name = name, SlotText = slot, Level = Json.Int(it, "l"),
                    LevelText = "iLvl " + Json.Int(it, "l"), PriceText = WorldText.Thousands(p) + " gold", PriceColor = sold ? "#6a6058" : afford ? "#e8b84a" : "#e07060",
                    Sold = sold, CanBuy = CanBuy(it), BuyText = sold ? "Sold" : "Buy " + ShortGold(p),
                    Tip = Loc.T("{0}\n{1}, item level {2}\nRarity: sealed until bought\nPrice: {3} gold\n{4}", name, slot, Json.Int(it, "l"), WorldText.Thousands(p), why),
                });
            }
            return o;
        }

        public int SoldCount() { int n = 0; foreach (object it in Json.List(State, "items")) if (it is Dictionary<string, object> && Json.Truthy(it, "sold")) n++; return n; }

        public string Header() => State == null ? "" : Loc.T("Sealed crates for level {0} (item level up to {1}): {2} of {3} sold. Your gold: {4}", Json.Int(State, "level"), Json.Int(State, "gate"), SoldCount(), Json.List(State, "items").Count, WorldText.Thousands(Json.Number(State, "money")));

        public string NearText(out string color)
        {
            color = "#8c8070";
            if (State == null) return "";
            string npc = Json.Text(State, "npc", Loc.T("the Gambler"));
            if (Near) { color = "#8fd16a"; return Loc.T("You stand before {0}: pick a crate.", npc); }
            color = "#e0a050";
            return Loc.T("Look from anywhere; buy from {0} in the market of the teleport room.", npc);
        }

        /// <summary>The Fresh Crates button: text, enabled, tooltip.</summary>
        public string RerollText(out bool ok, out string tip)
        {
            ok = false;
            if (State == null || Json.Number(State, "rerollMax") <= 0) { tip = Loc.T("Not offered."); return Loc.T("Fresh Crates"); }
            if (Json.Get(State, "reroll") == null)
            {
                tip = Loc.T("Used {0} of {1} in this stock. New crates at {2}.", Json.Int(State, "rerolls"), Json.Int(State, "rerollMax"), Json.Text(State, "at", "?"));
                return Loc.T("Fresh Crates");
            }
            ok = Near && Json.Number(State, "money") >= Json.Number(State, "reroll");
            tip = Loc.T("A new stock now for {0} gold ({1} of {2} used). The sold marks go too; each crate is still paid in full.", WorldText.Thousands(Json.Number(State, "reroll")), Json.Int(State, "rerolls"), Json.Int(State, "rerollMax"));
            return Loc.T("Fresh Crates ({0})", ShortGold(Json.Number(State, "reroll")));
        }

        public string OddsText()
        {
            var parts = new List<string>();
            foreach (object o in Json.List(State, "odds"))
            {
                double p = Json.Number(o, "p");
                parts.Add(Json.Text(o, "n") + " " + p.ToString(p >= 1 ? "0.0" : "0.00", CultureInfo.InvariantCulture) + "%");
            }
            return parts.Count == 0 ? "" : Loc.T("Odds per crate: {0}", string.Join(", ", parts));
        }

        public static string RevealText(object last, out string color)
        {
            color = "#8c8070";
            if (!(last is Dictionary<string, object>) || Json.Get(last, "r") == null) return "";
            int r = Json.Int(last, "r");
            color = r >= 0 && r < Rarity.Length ? Rarity[r] : "#d8ccb4";
            if (color.Length == 0) color = "#d8ccb4";
            return Loc.T("The seal breaks: {0} {1} (item level {2})", Json.Text(last, "rn", "Rarity " + r), WorldText.Cap(Json.Text(last, "n")), Json.Int(last, "l"));
        }

        public static int RevealItem(object last) => last is Dictionary<string, object> && Json.Get(last, "r") != null ? WorldText.ClientId(Json.Get(last, "c")) : 0;

        public static bool SameCells(IList<GambleCell> a, IList<GambleCell> b)
        {
            if (a.Count != b.Count) return false;
            for (int k = 0; k < a.Count; k++) if (a[k].I != b[k].I || a[k].Id != b[k].Id) return false;
            return true;
        }

        public void Open() { Send("open"); Visible = true; }
        public void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void Toggle() { if (Visible) Hide(); else Open(); }
        public void Refresh() { Send("open"); }
        public void Reroll() { if (State != null) Send("reroll", new Dictionary<string, object> { { "w", Json.Get(State, "w") } }); }

        public bool Buy(GambleCell c)
        {
            if (State == null || c == null || !c.CanBuy || Buying) return false;
            Buying = true; BuyAt = Clock();
            Send("buy", new Dictionary<string, object> { { "i", c.I }, { "w", Json.Get(State, "w") }, { "id", c.Id } });
            return true;
        }

        /// <summary>Gives the Buy buttons back when no answer came in time (a request the server's rate limit dropped).</summary>
        public void Tick(double now) { if (Buying && now - BuyAt > BuyWaitMs) Buying = false; }

        public void Handle(string action, object data)
        {
            switch (action)
            {
                case "state": State = data; ReceivedAt = Clock(); Buying = false; Status = ""; Changed(); break;
                case "result":
                    Buying = false;
                    Status = Json.Text(data, "text"); StatusColor = Json.Truthy(data, "ok") ? "#8fd16a" : "#e07060";
                    if (Json.Get(data, "reveal") is Dictionary<string, object> rv) { Reveal = rv; RevealText(rv, out string c); StatusColor = c; }
                    Changed();
                    break;
                case "npc": Open(); Changed(); break;
            }
        }

        public void Clear() { State = null; Visible = false; Buying = false; Reveal = null; Status = ""; }
    }

    // ------------------------------------------------------------------------------------------------ ember cache
    public sealed class EmberTier { public string Title = "", Reward = "", Status = ""; public bool Reached; }

    public sealed class EmberCacheState
    {
        public const byte Opcode = 174;
        public static readonly Dictionary<string, string> Sources = new Dictionary<string, string>
        {
            { "kill", "Monster kills" }, { "elite", "Rare and legendary monsters" }, { "dungeon", "A dungeon cleared" }, { "rift", "A rift run" }, { "descent", "An Ember Descent run" },
            { "tower", "An Infinity Tower run" }, { "bounty", "A bounty done" }, { "task", "A kill task done" }, { "worldboss", "A world boss" }, { "raid", "An Ashen Sepulchre boss" },
            { "omen", "An Omen guardian" }, { "trial", "A Vocation Trial run" }, { "invasion", "An invasion fought" }, { "pvp", "A battleground or a siege" }, { "goblin", "A treasure goblin" },
            { "craft", "A crafting orb used" }, { "offering", "Junk orbs offered (the button below)" },
        };

        readonly ExtOpcodes ext;
        public object State, Quote;
        public bool Visible, QuoteVisible;
        public Action Changed = delegate { };

        public EmberCacheState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        static int Int(double v) => double.IsNaN(v) || double.IsInfinity(v) ? 0 : (int)Math.Max(0, Math.Floor(v));
        static int I(object o, string k) => Int(Json.Number(o, k));

        /// <summary>The duration as "1 h 5 min".</summary>
        public static string Duration(double seconds) { int s = Int(seconds), h = s / 3600, m = s % 3600 / 60; return h > 0 ? Loc.T("{0} h {1} min", h, m) : Loc.T("{0} min", m); }

        public static string Left(double seconds)
        {
            int s = Int(seconds);
            if (s >= 86400) { int d = s / 86400; return d == 1 ? Loc.T("{0} day", d) : Loc.T("{0} days", d); }
            if (s >= 3600) return Loc.T("{0} h", s / 3600);
            return Loc.T("under an hour");
        }

        /// <summary>A reward: gold and the items [[id, count, name]].</summary>
        public static string Reward(double gold, object items)
        {
            var parts = new List<string>();
            if (items is List<object> l)
                foreach (object it in l)
                {
                    if (!(it is List<object> r) || r.Count < 3) continue;
                    int n = Int(r[1] is double d ? d : 0);
                    string name = r[2] as string ?? "";
                    if (name.Length > 0) parts.Add((n > 1 ? n + "x " : "") + name);
                }
            return parts.Count == 0 ? Loc.T("{0} gold", WorldText.Short(gold)) : Loc.T("{0} gold, {1}", WorldText.Short(gold), string.Join(", ", parts));
        }

        /// <summary>The offer box: its text and whether Yes works.</summary>
        public static string OfferText(object q, out bool can)
        {
            int per = Math.Max(1, I(q, "per"));
            if (I(q, "room") <= 0) { can = false; return Loc.T("The Ember Cache takes no more junk orbs today. More tomorrow."); }
            if (I(q, "points") <= 0) { can = false; return Loc.T("You carry {0} junk orbs: at least {1} make an Ember point (locked orbs do not count).", I(q, "carried"), per); }
            can = true;
            return Loc.T("Offer {0} junk orbs for {1} Ember points? They are destroyed. ({2} orbs a point, {3} points left today)", I(q, "orbs"), I(q, "points"), per, I(q, "room"));
        }

        public static List<string[]> SourceRows(object src)
        {
            var o = new List<string[]>();
            if (!(src is List<object> l)) return o;
            foreach (object row in l)
            {
                if (!(row is List<object> r) || r.Count < 2 || !(r[0] is string key) || !Sources.TryGetValue(key, out string label)) continue;
                int pts = Int(r[1] is double a ? a : 0), per = r.Count > 2 && r[2] is double b ? Int(b) : 0, cap = r.Count > 3 && r[3] is double c ? Int(c) : 0, today = r.Count > 4 && r[4] is double d ? Int(d) : 0;
                string p = per > 1 ? Loc.T("{0} for 1 point", per) : pts == 1 ? Loc.T("{0} point", pts) : Loc.T("{0} points", pts);
                o.Add(new[] { Loc.T(label), p, cap > 0 ? Loc.T("at most {0} a day ({1} today)", cap, today) : "" });
            }
            return o;
        }

        public string WeekLine() => Loc.T("This week: {0} Ember points", I(Json.Get(State, "week"), "pts"));
        public string WeekEndsLine() => Loc.T("The week ends in {0}", Left(Json.Number(Json.Get(State, "week"), "ends")));
        public string SparksLine() => Loc.T("Daily Sparks this week: {0}", I(Json.Get(State, "week"), "sparks"));
        public string TodayLine() => Loc.T("Today: {0} Ember points", I(Json.Get(State, "day"), "pts"));

        public List<EmberTier> Tiers()
        {
            var o = new List<EmberTier>();
            var week = Json.Get(State, "week");
            int got = I(week, "got"), pts = I(week, "pts"), i = 0;
            foreach (object t in Json.List(week, "tiers"))
            {
                i++;
                bool reached = i <= got;
                o.Add(new EmberTier { Title = Loc.T("Milestone {0}: {1} points", i, I(t, "p")), Reward = Reward(Json.Number(t, "g"), Json.Get(t, "it")), Reached = reached, Status = reached ? Loc.T("reached") : Loc.T("{0} to go", Math.Max(0, I(t, "p") - pts)) });
            }
            return o;
        }

        public string SparkLine(out bool lit)
        {
            var day = Json.Get(State, "day");
            lit = I(day, "spark") == 1;
            return lit ? Loc.T("Daily Spark lit") : Loc.T("Daily Spark at {0} points: {1} to go", I(day, "goal"), Math.Max(0, I(day, "goal") - I(day, "pts")));
        }

        public string SparkReward() { var day = Json.Get(State, "day"); return Reward(Json.Number(day, "g"), Json.Get(day, "it")); }
        public string BonusLine() { int b = I(Json.Get(State, "day"), "bonus"); return b > 0 ? Loc.T("Your next {0} points today count double.", b) : Loc.T("Double points used up today."); }

        public List<string[]> BookRows()
        {
            var b = Json.Get(State, "book");
            int loot = I(b, "loot"), sup = I(b, "sup");
            return new List<string[]>
            {
                new[] { Loc.T("Experience"), WorldText.Short(I(b, "xp")) }, new[] { Loc.T("Levels gained"), I(b, "lv").ToString() }, new[] { Loc.T("Kills"), I(b, "kills").ToString() },
                new[] { Loc.T("Loot value"), WorldText.Short(loot) }, new[] { Loc.T("Supplies used"), WorldText.Short(sup) },
                new[] { Loc.T("Profit"), (loot < sup ? "-" : "") + WorldText.Short(Math.Abs(loot - sup)) },
                new[] { Loc.T("Orbs, uniques, rarity items"), I(b, "orbs") + " / " + I(b, "uniq") + " / " + I(b, "rares") }, new[] { Loc.T("Deaths"), I(b, "deaths").ToString() },
                new[] { Loc.T("Time played"), Duration(Json.Number(b, "secs")) },
            };
        }

        public void Open() { Visible = true; Send("open"); }
        public void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void Toggle() { if (Visible) Hide(); else Open(); }
        public void AskOffer() { Send("offerQuote"); }
        public void Offer() { QuoteVisible = false; Send("offer"); }

        public void Handle(string action, object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            if (action == "offer") { Quote = data; QuoteVisible = true; Changed(); return; }
            if (action != "state") return;
            State = data;
            if (Json.Truthy(data, "open") || Json.Number(data, "open") == 1) Visible = true;   // the server sends open = 1 (embercache.lua send), a number: phase 13 track G
            Changed();
        }

        public void Clear() { State = null; Quote = null; Visible = false; QuoteVisible = false; }
    }
}
