// Market (client game_market, extended opcode 221, server market.lua + market_core.lua): our player market for gold and Chaos Coins.
//   client -> server  open | browse {q, cat, rarity, cur, sort, page, ilvlMin, ilvlMax, priceMin, priceMax} | tip {id} | buy {id, cur} | sellable
//                     | list {ref|pos, sid|cid, iid, count, gold, coins, days} | cancel {id} | mine | history | wallet
//                     | orders {q, cur, sort, mine, page} | myOrders | orderFind {q} | orderPost {sid, quantity, price, cur, days, filter}
//                     | orderCancel {id} | fillable {id} | fill {id, ref, sid, iid, count}
//   server -> client  meta | page | tip | sellable | mine | history | wallet | done {what, text} | error {text} | openWindow | orders | myOrders
//                     | orderFind | fillable
// Tabs: Browse (search, filters, sort, pages, hover tooltip, Buy with a confirmation), Sell (pick a backpack item, prices, days, the fee), My Offers
// (Cancel), History, Buy Orders (the open orders with Sell to fill them, your own with Cancel, a form to post one).
// The Modifiers section of the Browse filter and of an order (typeahead over the Codex) is Phase8BMarket.cs. The price history (action "prices") and the drop on the Sell tab are in Phase7ZMarket.cs.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    /// <summary>The market's arithmetic as the server does it (market_core.lua): fee, tax, the Sell form and the order form.</summary>
    public static class MarketMath
    {
        public static readonly string[] Categories = { "weapon", "shield", "helmet", "armor", "legs", "boots", "jewel", "other", "orb", "gem", "key", "misc" };
        public static readonly string[] CategoryNames = { "Weapons", "Shields", "Helmets", "Armors", "Legs", "Boots", "Jewellery", "Other gear", "Orbs", "Gems", "Rift keys", "Other" };
        public static readonly string[] Sorts = { "new", "price", "price_desc", "ilvl", "rarity", "name", "ending" };
        public static readonly string[] SortNames = { "Newest", "Price: low to high", "Price: high to low", "Item level", "Rarity", "Name", "Ending soon" };
        public static readonly string[] OrderSorts = { "new", "price", "ending", "name" };
        public static readonly string[] OrderSortNames = { "Newest", "Best price", "Ending soon", "Name" };
        public static readonly int[] RarityIds = ItemRarity.Ids;

        public static string CategoryName(string key) { int i = Array.IndexOf(Categories, key ?? ""); return i >= 0 ? CategoryNames[i] : (key ?? ""); }

        public static string RarityName(int id) { string n = ItemRarity.Name(ItemRarity.Canon(id)); return n == null ? null : Loc.T(n); }

        /// <summary>The listing fee in gold: pct of the gold price (or of the coin price converted), within min and max.</summary>
        public static long Fee(object meta, long gold, long coins)
        {
            object f = Json.Get(meta, "fee");
            double pct = Json.Number(f, "pct"), min = Json.Number(f, "min"), coinGold = Json.Number(f, "coinGold");
            double baseV = gold > 0 ? gold : coins * coinGold;
            double fee = Math.Floor(baseV * pct / 100);
            if (fee < min) fee = min;
            if (SFmt.Has(f, "max") && fee > Json.Number(f, "max")) fee = Json.Number(f, "max");
            return (long)fee;
        }

        /// <summary>The tax of a sale in "gold" or "coins" and what the seller keeps.</summary>
        public static void Tax(object meta, string cur, long price, out long tax, out long net)
        {
            double pct = Json.Number(Json.Get(meta, "tax"), cur);
            tax = (long)Math.Floor(price * pct / 100);
            net = price - tax;
        }

        static void Limits(object meta, string cur, out long min, out long max)
        {
            object p = Json.Get(Json.Get(meta, "price"), cur);
            min = p != null && SFmt.Has(p, "min") ? (long)Json.Number(p, "min") : 1;
            max = p != null && SFmt.Has(p, "max") ? (long)Json.Number(p, "max") : (cur == "coins" ? 100000 : 2000000000);
        }

        /// <summary>The Sell form: texts of the prices, the count asked and held, the days. Null and a reason when it is not valid.</summary>
        public static bool CheckSell(object meta, string goldText, string coinsText, long count, long have, int days, out long gold, out long coins, out string why)
        {
            gold = SFmt.ParseAmount(goldText); coins = SFmt.ParseAmount(coinsText); why = "";
            if (gold < 0 || coins < 0) { why = Loc.T("Prices are whole numbers (5k and 2.5m work)."); return false; }
            if (gold == 0 && coins == 0) { why = Loc.T("Set a price in gold, in Chaos Coins or in both."); return false; }
            Limits(meta, "gold", out long gmin, out long gmax);
            Limits(meta, "coins", out long cmin, out long cmax);
            if (gold > 0 && (gold < gmin || gold > gmax)) { why = Loc.T("A gold price must be between {0} and {1}.", SFmt.Money(gmin), SFmt.Money(gmax)); return false; }
            if (coins > 0 && (coins < cmin || coins > cmax)) { why = Loc.T("A coin price must be between {0} and {1}.", SFmt.Money(cmin), SFmt.Money(cmax)); return false; }
            if (count < 1 || count > Math.Max(1, have)) { why = Loc.T("You do not have that many."); return false; }
            return true;
        }

        /// <summary>The order form: the orderPost request, the total and the fee. Null and a reason when it is not valid.</summary>
        public static Dictionary<string, object> CheckOrder(object meta, long sid, string qtyText, string priceText, string cur, int days, int rarity, string ilvlText,
            out long total, out long fee, out string why, Dictionary<string, object> mods = null)
        {
            total = 0; fee = 0; why = "";
            if (sid <= 0) { why = Loc.T("Choose the item you want: search for it first."); return null; }
            long qty = SFmt.ParseAmount(qtyText);
            if (qty < 1) { why = Loc.T("How many do you want? A whole number of 1 or more."); return null; }
            object lim = Json.Get(meta, "orders");
            long maxQ = lim != null && SFmt.Has(lim, "maxQuantity") ? (long)Json.Number(lim, "maxQuantity") : 1000;
            if (qty > maxQ) { why = Loc.T("At most {0} per order.", SFmt.Money(maxQ)); return null; }
            cur = cur == "coins" ? "coins" : "gold";
            long price = SFmt.ParseAmount(priceText);
            Limits(meta, cur, out long pmin, out long pmax);
            if (cur == "gold" && Json.Get(Json.Get(meta, "price"), "gold") == null) pmin = 100;
            if (price < pmin || price > pmax)
            {
                why = Loc.T("The price per item in {0} must be between {1} and {2}.", cur == "coins" ? Loc.T("Chaos Coins") : Loc.T("gold"), SFmt.Money(pmin), SFmt.Money(pmax));
                return null;
            }
            total = price * qty;
            double maxT = SFmt.Has(Json.Get(lim, "maxTotal"), cur) ? Json.Number(Json.Get(lim, "maxTotal"), cur) : (cur == "coins" ? 1000000 : 2000000000);
            if (total > maxT) { why = Loc.T("One order may hold at most {0} {1}.", SFmt.Money(maxT), cur == "coins" ? Loc.T("Chaos Coins") : Loc.T("gold")); return null; }
            long ilvl = SFmt.ParseAmount(ilvlText);
            if (ilvl < 0) { why = Loc.T("Item level: a whole number."); return null; }
            fee = Fee(meta, cur == "gold" ? total : 0, cur == "coins" ? total : 0);
            var filter = new Dictionary<string, object>();
            if (rarity > 0) filter["rarity"] = rarity;
            if (ilvl > 0) filter["ilvl"] = ilvl;
            if (mods != null) foreach (var kv in mods) if (kv.Key != "mods" || ((List<object>)kv.Value).Count > 0) filter[kv.Key] = kv.Value;
            return SFmt.Map("sid", sid, "quantity", qty, "price", price, "cur", cur, "days", days, "filter", filter);
        }

        public static string OrderCostText(object meta, Dictionary<string, object> req, long total, long fee)
        {
            if (req == null) return "";
            string cur = (string)req["cur"];
            string name = cur == "coins" ? Loc.T("Chaos Coins") : Loc.T("gold");
            string held = cur == "coins"
                ? Loc.T("Held now: {0} Chaos Coins from your account, and the listing fee of {1} gold from your bank.", SFmt.Money(total), SFmt.Money(fee))
                : Loc.T("Held now: {0} gold from your bank ({1} for the items + {2} listing fee).", SFmt.Money(total + fee), SFmt.Money(total), SFmt.Money(fee));
            Tax(meta, cur, (long)req["price"], out long tax, out _);
            return held + "\n" + Loc.T("Sellers get {0} {1} per item ({2} sales tax). What is not bought comes back when the order ends; the fee does not.",
                SFmt.Money((long)req["price"] - tax), name, SFmt.Money(tax));
        }

        public static string TimeLeft(double sec)
        {
            long s = (long)Math.Floor(sec);
            if (s <= 0) return Loc.T("ended");
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return Loc.T("{0}d {1}h", d, h);
            if (h > 0) return Loc.T("{0}h {1}m", h, m);
            if (m > 0) return Loc.T("{0}m", m);
            return Loc.T("<1m");
        }

        /// <summary>"12,000 gold" and "40 coins" of an offer, in that order.</summary>
        public static List<KeyValuePair<string, string>> PriceLines(object row)
        {
            var o = new List<KeyValuePair<string, string>>();
            if (Json.Number(row, "gold") > 0) o.Add(new KeyValuePair<string, string>(SFmt.Money(Json.Number(row, "gold")) + " " + Loc.T("gold"), "gold"));
            if (Json.Number(row, "coins") > 0) o.Add(new KeyValuePair<string, string>(SFmt.Money(Json.Number(row, "coins")) + " " + Loc.T("coins"), "coins"));
            return o;
        }

        /// <summary>The line under a Browse row's name.</summary>
        public static string SubLine(object row)
        {
            var p = new List<string>();
            int rarity = Json.Int(row, "rarity");
            if (Json.Truthy(row, "unique")) p.Add(Loc.T("Unique"));
            else if (rarity > 0) p.Add(RarityName(rarity) ?? Loc.T("Rarity {0}", rarity));
            if (Json.Int(row, "ilvl") > 0) p.Add(Loc.T("iLvl {0}", Json.Int(row, "ilvl")));
            string veil = Json.Text(row, "veil");
            if (veil.Length > 0) p.Add(veil == "open" ? Loc.T("Unveiled") : Loc.T("Veiled"));
            p.Add(Loc.T(CategoryName(Json.Text(row, "cat"))));
            if (Json.Text(row, "seller").Length > 0) p.Add(Loc.T("by {0}", Json.Text(row, "seller")));
            p.Add(Loc.T("{0} left", TimeLeft(Json.Number(row, "left"))));
            return string.Join(" - ", p);
        }

        public static string StateLine(object row)
        {
            string state = Json.Text(row, "state");
            string cur = Json.Text(row, "cur") == "coins" ? Loc.T("coins") : Loc.T("gold");
            if (state == "sold")
            {
                double paid = Json.Number(row, "paid"), tax = Json.Number(row, "tax");
                return Loc.T("Sold to {0} for {1} {2} (tax {3}, you got {4})", Json.Text(row, "buyer", "?"), SFmt.Money(paid), cur, SFmt.Money(tax), SFmt.Money(paid - tax));
            }
            if (state == "expired") return Loc.T("Expired: the item went back to your inbox");
            if (state == "cancelled") return Loc.T("Cancelled: the item went back to your inbox");
            if (state == "active") return Loc.T("{0} left", TimeLeft(Json.Number(row, "left")));
            return state;
        }

        public static string HistoryLine(object row)
        {
            string cur = Json.Text(row, "cur") == "coins" ? Loc.T("coins") : Loc.T("gold");
            if (Json.Text(row, "side") == "bought") return Loc.T("Bought from {0} for {1} {2}", Json.Text(row, "seller", "?"), SFmt.Money(Json.Number(row, "paid")), cur);
            return Loc.T("Sold to {0} for {1} {2} (tax {3})", Json.Text(row, "buyer", "?"), SFmt.Money(Json.Number(row, "paid")), cur, SFmt.Money(Json.Number(row, "tax")));
        }

        public static string PageText(int page, int pages, int total) =>
            Loc.T(total == 1 ? "Page {0} / {1}  ({2} offer)" : "Page {0} / {1}  ({2} offers)", page, Math.Max(1, pages), total);

        public static string OrderSubLine(object row, Func<string, string> modName = null)
        {
            var p = new List<string> { Loc.T("{0}/{1} bought", SFmt.Money(Json.Number(row, "filled")), SFmt.Money(Json.Number(row, "qty"))) };
            if (Json.Text(row, "buyer").Length > 0 && !Json.Truthy(row, "mine")) p.Add(Loc.T("by {0}", Json.Text(row, "buyer")));
            string state = Json.Text(row, "state");
            p.Add(state == "active" ? Loc.T("{0} left", TimeLeft(Json.Number(row, "left"))) : Loc.T(state));
            object f = Json.Get(row, "filter");
            string ft = MarketMods.FilterText(f, modName);
            if (ft != Loc.T("Any")) p.Add(ft);
            return string.Join(" - ", p);
        }

        public static string FillText(object meta, object order, long n)
        {
            if (n <= 0) return "";
            string cur = Json.Text(order, "cur") == "coins" ? "coins" : "gold";
            long total = (long)Json.Number(order, "price") * n;
            Tax(meta, cur, total, out long tax, out long net);
            string name = cur == "coins" ? Loc.T("Chaos Coins") : Loc.T("gold");
            return Loc.T("Sell {0} for {1} {2}: tax {3}, you receive {4} {2}{5}.", n > 1 ? Loc.T("{0} items", n) : Loc.T("1 item"), SFmt.Money(total), name, SFmt.Money(tax), SFmt.Money(net),
                cur == "coins" ? Loc.T(" on your account") : Loc.T(" in your bank"));
        }

        /// <summary>The seller's items for an order: those that fit first, then rarity, then the larger stack.</summary>
        public static List<object> SortFillable(List<object> items)
        {
            var list = new List<object>(items);
            list.Sort((a, b) =>
            {
                bool wa = Json.Text(a, "why").Length == 0, wb = Json.Text(b, "why").Length == 0;
                if (wa != wb) return wa ? -1 : 1;
                int ra = Json.Int(a, "rarity"), rb = Json.Int(b, "rarity");
                if (ra != rb) return rb.CompareTo(ra);
                return Json.Int(b, "count").CompareTo(Json.Int(a, "count"));
            });
            return list;
        }

        /// <summary>Listable items first, then the others (with why), rarity then name.</summary>
        public static List<object> SortSellable(List<object> items)
        {
            var list = new List<object>(items);
            list.Sort((a, b) =>
            {
                bool wa = Json.Text(a, "why").Length == 0, wb = Json.Text(b, "why").Length == 0;
                if (wa != wb) return wa ? -1 : 1;
                int ra = Json.Int(a, "rarity"), rb = Json.Int(b, "rarity");
                if (ra != rb) return rb.CompareTo(ra);
                return string.CompareOrdinal(Json.Text(a, "name"), Json.Text(b, "name"));
            });
            return list;
        }
    }

    public sealed class MarketPanel : SocialPanel
    {
        public const byte Opcode = 221;
        public static readonly string[] TabKeys = { "browse", "sell", "mine", "history", "orders" };
        readonly ExtOpcodes ext;
        public object Meta;
        public object PageData, MineData, HistoryData, SellData, OrdersData, MyOrdersData, FindData, FillData;
        public int PageNo = 1, Pages = 1, Total;
        public bool Mine;   // the orders tab shows my own orders
        public readonly Dictionary<string, object> Tips = new Dictionary<string, object>();
        readonly Dictionary<string, double> tipAsked = new Dictionary<string, double>();
        public Func<double> Clock = () => 0;
        /// <summary>The offer a Buy confirmation is open for, or a cancel confirmation.</summary>
        public object ConfirmBuyOffer, ConfirmCancelOffer, ConfirmOrderCancel;
        /// <summary>The price history (Phase7ZMarket.cs): the stats of the clicked Browse offer, and of the item chosen in the Sell form.</summary>
        public object PriceOffer, PriceData, SellPriceData, SellPriceFor;
        public string PriceCur = "gold";
        int priceSeq, priceSeqOffer, priceSeqSell;
        public object Selected;   // the Sell item chosen
        public object ChosenKind; // the order form's item kind
        public object FillOrder, FillChosen;
        /// <summary>Phase 8 B: the Modifiers section of Browse (rows are read from the Form keys mq/mc/mm/mt + row number, mmode, mneed, msock, mqual), the codex it searches, the
        /// modifiers a buy order takes from it and the filter of the last Browse request (the matched lines of a tooltip).</summary>
        public readonly ModForm Mods = new ModForm();
        public bool ModsOpen;
        public Func<CodexData> CodexSource;
        public Dictionary<string, object> OrderMods, LastFilter;
        ModCatalog catalog;

        public MarketPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("browse", "Browse"));
            Tabs.Add(new KeyValuePair<string, string>("sell", "Sell"));
            Tabs.Add(new KeyValuePair<string, string>("mine", "My Offers"));
            Tabs.Add(new KeyValuePair<string, string>("history", "History"));
            Tabs.Add(new KeyValuePair<string, string>("orders", "Buy Orders"));
            Tab = "browse";
            Form["days"] = "-1"; Form["ordays"] = "-1";
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Visible = true; Send("open"); }
        public override void Hide() { Visible = false; ConfirmBuyOffer = ConfirmCancelOffer = ConfirmOrderCancel = null; }

        public override void Clear()
        {
            base.Clear();
            Meta = PageData = MineData = HistoryData = SellData = OrdersData = MyOrdersData = FindData = FillData = null;
            Tips.Clear(); tipAsked.Clear(); Selected = ChosenKind = FillOrder = FillChosen = null;
            PriceOffer = PriceData = SellPriceData = SellPriceFor = null; PriceCur = "gold";
            ConfirmBuyOffer = ConfirmCancelOffer = ConfirmOrderCancel = null;
            PageNo = Pages = 1; Total = 0;
            Mods.Rows.Clear(); Mods.Count = Mods.FreeP = Mods.FreeS = Mods.Power = Mods.Bound = false; Mods.Need = Mods.Sockets = Mods.Quality = ""; ModsOpen = false;
            OrderMods = LastFilter = null;
        }

        // ------------------------------------------------------------------------------------ the Modifiers section
        public ModCatalog Catalog
        {
            get
            {
                if (catalog == null || catalog.List.Count == 0) { var cd = CodexSource != null ? CodexSource() : null; catalog = ModCatalog.Build(cd); }
                return catalog;
            }
        }

        public MarketMods.Limits ModLimits => MarketMods.LimitsOf(Meta);

        /// <summary>Reads the section's Form keys into Mods.</summary>
        public void SyncMods()
        {
            for (int i = 0; i < Mods.Rows.Count; i++)
            {
                var r = Mods.Rows[i];
                r.Search = Text("mq" + i); r.Min = Text("mm" + i); r.Tier = Index("mt" + i);
                var ch = Catalog.Choices(r.Search, out _);
                int ci = Index("mc" + i);
                r.Key = ci >= 0 && ci < ch.Count ? ch[ci].Key : "";
            }
            Mods.Count = Index("mmode") == 1; Mods.Need = Text("mneed"); Mods.Sockets = Text("msock"); Mods.Quality = Text("mqual");
        }

        /// <summary>The Modifiers section as filter fields, null and why when invalid.</summary>
        public Dictionary<string, object> ModsRequest(out string why) { SyncMods(); return MarketMods.Request(Mods, ModLimits, out why); }

        public void AddModRow()
        {
            if (Mods.Rows.Count >= ModLimits.MaxRows) { Say(Loc.T("At most {0} modifiers per search.", ModLimits.MaxRows), false); return; }
            SyncMods();
            int i = Mods.Rows.Count;
            Mods.Rows.Add(new ModRow());
            Form["mq" + i] = ""; Form["mm" + i] = ""; Form["mt" + i] = "0"; Form["mc" + i] = "0";
            Changed();
        }

        public void RemoveModRow(int index)
        {
            SyncMods();
            if (index < 0 || index >= Mods.Rows.Count) return;
            int n = Mods.Rows.Count;
            for (int j = index; j < n - 1; j++) foreach (string k in new[] { "mq", "mm", "mt", "mc" }) Form[k + j] = Text(k + (j + 1));
            foreach (string k in new[] { "mq", "mm", "mt", "mc" }) Form.Remove(k + (n - 1));
            Mods.Rows.RemoveAt(index);
            Search();
            Changed();
        }

        public void ToggleMods() { ModsOpen = !ModsOpen; if (ModsOpen && Mods.Rows.Count == 0) AddModRow(); Changed(); }

        public void ClearMods()
        {
            Mods.Rows.Clear();
            foreach (string k in new List<string>(Form.Keys)) if (k.Length > 2 && (k.StartsWith("mq") || k.StartsWith("mm") || k.StartsWith("mt") || k.StartsWith("mc")) && char.IsDigit(k[2])) Form.Remove(k);
            Form.Remove("mmode"); Form.Remove("mneed"); Form.Remove("msock"); Form.Remove("mqual");
            Mods.FreeP = Mods.FreeS = Mods.Power = Mods.Bound = false;
            if (ModsOpen) AddModRow();
            Search();
        }

        /// <summary>The count on the section's toggle button.</summary>
        public int ModsActive { get { var r = ModsRequest(out _); return MarketMods.Count(r); } }

        static bool IsModKey(string key) => key.Length > 1 && key[0] == 'm' && key != "mine" && (key.StartsWith("mq") || key.StartsWith("mm") || key.StartsWith("mt") || key.StartsWith("mc") || key == "mmode" || key == "mneed" || key == "msock" || key == "mqual");

        /// <summary>The text boxes of the section wait for the Search button (like the item name); the combos search at once.</summary>
        static bool IsModBox(string key) => key.StartsWith("mq") || key.StartsWith("mm") || key == "mneed" || key == "msock" || key == "mqual";

        void ModFormChanged(string key)
        {
            if (key.StartsWith("mq") && key.Length > 2 && char.IsDigit(key[2]))
            {
                // the typed words narrow the combo: it takes the first match (a search that matches nothing chooses nothing)
                var ch = Catalog.Choices(Text(key), out string first);
                int idx = 0;
                if (Text(key).Trim().Length > 0) for (int i = 0; i < ch.Count; i++) if (ch[i].Key.Length > 0 && ch[i].Key == first) { idx = i; break; }
                Form["mc" + key.Substring(2)] = idx.ToString(CultureInfo.InvariantCulture);
            }
        }

        // ------------------------------------------------------------------------------------ messages
        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "meta":
                    Meta = d;
                    Header1 = WalletText();
                    if (Visible) EnterTab(Tab);
                    break;
                case "openWindow": Visible = true; break;
                case "page":
                    PageData = d; PageNo = Math.Max(1, Json.Int(d, "page", 1)); Pages = Math.Max(1, Json.Int(d, "pages", 1)); Total = Json.Int(d, "total");
                    if (Status.Length > 0 && StatusTone == "bad") Status = "";
                    break;
                case "tip":
                    if (Json.Get(d, "tip") is Dictionary<string, object> && IdKey(Json.Get(d, "id")).Length > 0)
                        Tips[IdKey(Json.Get(d, "id"))] = Json.Get(d, "tip");
                    break;
                case "prices": OnPrices(d); break;
                case "sellable": SellData = d; break;
                case "mine": MineData = d; break;
                case "history": HistoryData = d; break;
                case "wallet":
                    if (Meta is Dictionary<string, object> mm)
                    {
                        if (SFmt.Has(d, "gold")) mm["gold"] = Json.Number(d, "gold");
                        if (SFmt.Has(d, "coins")) mm["coins"] = Json.Number(d, "coins");
                    }
                    Header1 = WalletText();
                    break;
                case "orders": OrdersData = d; Mine = false; break;
                case "myOrders": MyOrdersData = d; Mine = true; break;
                case "orderFind":
                    FindData = d;
                    var items = Json.List(d, "items");
                    if (items.Count == 1) ChosenKind = items[0];
                    Say(items.Count == 0 ? Loc.T("No item of that name. Try another part of the name, or the exact name.") : Loc.T("{0} item kinds found: click the one you want.", items.Count), items.Count > 0);
                    break;
                case "fillable":
                    if (FillOrder != null && Json.Get(d, "id") != null && IdKey(Json.Get(FillOrder, "id")) == IdKey(Json.Get(d, "id")))
                    {
                        FillData = d;
                        if (Json.Get(d, "order") is Dictionary<string, object>) FillOrder = Json.Get(d, "order");
                    }
                    break;
                case "done":
                    Say(Json.Text(d, "text"), true);
                    switch (Json.Text(d, "what"))
                    {
                        case "list": Selected = null; Form["gold"] = ""; Form["coins"] = ""; Send("sellable"); break;
                        case "buy": AskBrowse(); break;
                        case "cancel": if (Tab == "mine") Send("mine"); else AskBrowse(); break;
                        case "orderPost": case "orderCancel": AskOrders(); break;
                        case "fill": AskOrders(); if (FillOrder != null) Send("fillable", SFmt.Map("id", Json.Get(FillOrder, "id"))); break;
                    }
                    break;
                case "error": Say(Json.Text(d, "text"), false); break;
            }
            Changed();
        }

        static string IdKey(object id) => id is double dd ? ((long)dd).ToString(CultureInfo.InvariantCulture) : (id as string ?? "");

        public string WalletText()
        {
            if (Meta == null) return "";
            string realm = Json.Text(Meta, "realmName", Loc.T("Standard"));
            if (SFmt.Has(Meta, "coinsOk") && !Json.Truthy(Meta, "coinsOk", true))
                return Loc.T("{0} market   Bank: {1} gold", realm, SFmt.Money(Json.Number(Meta, "gold")));
            return Loc.T("{0} market  Bank: {1} gold  Chaos Coins: {2}", realm, SFmt.Money(Json.Number(Meta, "gold")), SFmt.Money(Json.Number(Meta, "coins")));
        }

        bool CoinsOk => Meta == null || !SFmt.Has(Meta, "coinsOk") || Json.Truthy(Meta, "coinsOk", true);

        // ------------------------------------------------------------------------------------ requests
        public override void SelectTab(string key) { Tab = key; EnterTab(key); Changed(); }

        void EnterTab(string key)
        {
            switch (key)
            {
                case "browse": AskBrowse(); break;
                case "sell": Send("sellable"); break;
                case "mine": Send("mine"); break;
                case "history": Send("history"); break;
                case "orders": AskOrders(); break;
            }
        }

        public static List<string> CategoryOptions() { var o = new List<string> { Loc.T("All items") }; foreach (var n in MarketMath.CategoryNames) o.Add(Loc.T(n)); return o; }
        public static List<string> RarityOptions() { var o = new List<string> { Loc.T("Any rarity") }; foreach (int id in MarketMath.RarityIds) o.Add(MarketMath.RarityName(id) + " +"); return o; }
        static List<string> CurrencyOptions() => new List<string> { Loc.T("Any price"), Loc.T("Gold"), Loc.T("Chaos Coins") };
        static List<string> SortOptions() { var o = new List<string>(); foreach (var n in MarketMath.SortNames) o.Add(Loc.T(n)); return o; }

        /// <summary>The browse filter of the form (the page given).</summary>
        public Dictionary<string, object> BrowseFilter(int page)
        {
            var mods = ModsRequest(out string why);
            if (mods == null) { Say(why, false); return null; }
            int cat = Index("cat"), rar = Index("rarity"), cur = Index("cur"), sort = Index("sort");
            var f = new Dictionary<string, object>
            {
                { "q", Text("q") },
                { "cat", cat > 0 && cat <= MarketMath.Categories.Length ? MarketMath.Categories[cat - 1] : "" },
                { "rarity", rar > 0 && rar <= MarketMath.RarityIds.Length ? MarketMath.RarityIds[rar - 1] : 0 },
                { "cur", cur == 1 ? "gold" : cur == 2 ? "coins" : "" },
                { "sort", sort >= 0 && sort < MarketMath.Sorts.Length ? MarketMath.Sorts[sort] : "new" },
                { "page", page },
            };
            f["ilvlMin"] = Math.Max(0, SFmt.ParseAmount(Text("ilvlMin"))); f["ilvlMax"] = Math.Max(0, SFmt.ParseAmount(Text("ilvlMax")));
            f["priceMin"] = Math.Max(0, SFmt.ParseAmount(Text("priceMin"))); f["priceMax"] = Math.Max(0, SFmt.ParseAmount(Text("priceMax")));
            foreach (var kv in mods) if (kv.Key != "mods" || ((List<object>)kv.Value).Count > 0) f[kv.Key] = kv.Value;
            return f;
        }

        void AskPage(int page) { var f = BrowseFilter(page); if (f == null) return; LastFilter = f; Send("browse", f); }
        public void AskBrowse(int page = 0) { AskPage(page > 0 ? page : PageNo); }
        public void Search() { PageNo = 1; AskPage(1); }
        public void Page(int delta) { int t = PageNo + delta; if (t >= 1 && t <= Pages) AskPage(t); }

        public override void OnForm(string key)
        {
            ModFormChanged(key);
            if (Tab == "browse" && IsModKey(key)) { if (!IsModBox(key)) Search(); else Changed(); return; }
            if (Tab == "browse" && key != "q" && !key.StartsWith("ilvl") && !key.StartsWith("price")) Search();
            if (Tab == "orders" && (key == "ocur" || key == "osort")) AskOrders(1);
        }

        public Dictionary<string, object> OrderFilter(int page)
        {
            int cur = Index("ocur"), sort = Index("osort");
            var f = new Dictionary<string, object> { { "q", Text("oq") }, { "cur", cur == 1 ? "gold" : cur == 2 ? "coins" : "" },
                { "sort", sort >= 0 && sort < MarketMath.OrderSorts.Length ? MarketMath.OrderSorts[sort] : "new" }, { "page", page } };
            if (Mine) f["mine"] = true;
            return f;
        }

        public void AskOrders(int page = 0)
        {
            if (Mine) Send("myOrders"); else Send("orders", OrderFilter(page > 0 ? page : Math.Max(1, Json.Int(OrdersData, "page", 1))));
        }

        public void ToggleMine() { Mine = !Mine; AskOrders(1); Changed(); }

        public void AskTip(object offerId)
        {
            string key = IdKey(offerId);
            if (key.Length == 0 || Tips.ContainsKey(key)) return;
            double now = Clock();
            if (tipAsked.TryGetValue(key, out double at) && now - at < 3000) return;
            tipAsked[key] = now;
            Send("tip", SFmt.Map("id", offerId));
        }

        public void Buy(object offer, string cur) { ConfirmBuyOffer = null; Send("buy", SFmt.Map("id", Json.Get(offer, "id"), "cur", cur)); Changed(); }
        public void CancelOffer(object offer) { ConfirmCancelOffer = null; Send("cancel", SFmt.Map("id", Json.Get(offer, "id"))); Changed(); }

        public void ChooseSell(object entry)
        {
            if (Json.Text(entry, "why").Length > 0) { Say(Json.Text(entry, "why"), false); return; }
            Selected = entry; Form["count"] = Json.Int(entry, "count", 1).ToString(CultureInfo.InvariantCulture); Status = "";
            // the typical price of the chosen item (the Sell form suggests it and warns about a far price)
            SellPriceData = null; SellPriceFor = entry;
            if (SFmt.Has(entry, "sid"))
            {
                priceSeqSell = ++priceSeq;
                Send("prices", SFmt.Map("sid", Json.Get(entry, "sid"), "rarity", Json.Int(entry, "rarity"), "ilvl", Json.Int(entry, "ilvl"), "seq", priceSeqSell));
            }
            Changed();
        }

        /// <summary>An item dropped on the Sell tab: the picker entry it matches is chosen; false when the tab is not Sell or the list does not hold it.</summary>
        public bool DropItem(int clientId, int count, ulong iid)
        {
            if (Tab != "sell") return false;
            var entry = MarketDrop.Match(SFmt.Rows(SellData, "items"), clientId, count, iid);
            if (entry == null) { Say(Loc.T("That item is not in the list: it cannot be sold, or the list is old."), false); return true; }
            ChooseSell(entry);
            return true;
        }

        // ------------------------------------------------------------------------------------ price history (marketpriceview.lua)
        /// <summary>A click on a Browse offer: the prices of its item key with the 30-day chart.</summary>
        public void ShowPrices(object offer)
        {
            PriceOffer = offer; PriceData = null;
            priceSeqOffer = ++priceSeq;
            Send("prices", SFmt.Map("id", Json.Get(offer, "id"), "seq", priceSeqOffer));
            Changed();
        }

        public void ClosePrices() { PriceOffer = null; PriceData = null; Changed(); }

        void OnPrices(object d)
        {
            int seq = Json.Int(d, "seq");
            if (PriceOffer != null && seq == priceSeqOffer) { PriceData = d; PriceCur = MarketPrices.Currency(d, PriceCur); }
            else if (seq != 0 && seq == priceSeqSell) SellPriceData = d;
            Changed();
        }

        /// <summary>The Sell form's price hint: the typical line and the suggested price; the suggestion is 0 without a typical price.</summary>
        public string SellHint(out long suggest)
        {
            suggest = 0;
            if (Selected == null || SellPriceData == null || SellPriceFor != Selected) return "";
            object g = Json.Get(SellPriceData, "gold");
            long count = Json.Truthy(Selected, "stack") ? Math.Max(1, SFmt.ParseAmount(Text("count"))) : 1;
            string key = MarketPrices.KeyText(Json.Int(SellPriceData, "rarity"), Json.Text(SellPriceData, "bandText"));
            string text = (key.Length > 0 ? key + ": " : "") + MarketPrices.Typical(g, "gold").Text;
            double typical = Json.Number(g, "typical");
            long min = (long)Json.Number(Json.Get(Json.Get(Meta, "price"), "gold"), "min");
            if (typical > 0) { suggest = MarketPrices.Suggest(typical, count, min); text += count > 1 ? Loc.T(". Suggested: {0} gold for {1}.", SFmt.Money(suggest), count) : Loc.T(". Suggested: {0} gold.", SFmt.Money(suggest)); }
            return text;
        }

        /// <summary>The warnings for the asking prices in the Sell form (gold and coins), empty when they are near the typical price.</summary>
        public List<PriceLine> SellWarnings()
        {
            var o = new List<PriceLine>();
            if (Selected == null || SellPriceData == null || SellPriceFor != Selected) return o;
            long count = Json.Truthy(Selected, "stack") ? Math.Max(1, SFmt.ParseAmount(Text("count"))) : 1;
            var warn = Json.Get(SellPriceData, "warn");
            double low = warn != null && Json.Get(warn, "low") is double l ? l : 0.5, high = warn != null && Json.Get(warn, "high") is double h ? h : 2.0;
            foreach (string cur in new[] { "gold", "coins" })
            {
                var w = MarketPrices.SellWarning(Math.Max(0, SFmt.ParseAmount(Text(cur))), count, Json.Number(Json.Get(SellPriceData, cur), "typical"), low, high, cur);
                if (w != null) o.Add(w);
            }
            return o;
        }

        public int DaysOption()
        {
            var durations = Json.List(Meta, "durations");
            int idx = Index("days", -1);
            if (idx >= 0 && idx < durations.Count && durations[idx] is double dd) return (int)dd;
            return SFmt.Has(Meta, "defaultDuration") ? Json.Int(Meta, "defaultDuration") : 3;
        }

        public bool ListItem()
        {
            if (Selected == null) return false;
            bool stack = Json.Truthy(Selected, "stack");
            long have = Json.Int(Selected, "count", 1), count = stack ? SFmt.ParseAmount(Text("count")) : 1;
            if (!MarketMath.CheckSell(Meta, Text("gold"), Text("coins"), count, have, DaysOption(), out long gold, out long coins, out string why)) { Say(why, false); return false; }
            var req = new Dictionary<string, object>();
            foreach (var k in new[] { "ref", "pos", "sid", "cid", "iid" }) if (SFmt.Has(Selected, k)) req[k] = Json.Get(Selected, k);
            req["count"] = count; req["gold"] = gold; req["coins"] = coins; req["days"] = DaysOption();
            Send("list", req);
            return true;
        }

        public string FeeText()
        {
            long gold = Math.Max(0, SFmt.ParseAmount(Text("gold"))), coins = Math.Max(0, SFmt.ParseAmount(Text("coins")));
            var lines = new List<string> { Loc.T("Listing fee: {0} gold from your bank, not refunded.", SFmt.Money(MarketMath.Fee(Meta, gold, coins))) };
            if (gold > 0) { MarketMath.Tax(Meta, "gold", gold, out long t, out long n); lines.Add(Loc.T("Sold for gold: tax {0}, you receive {1} gold in your bank.", SFmt.Money(t), SFmt.Money(n))); }
            if (coins > 0) { MarketMath.Tax(Meta, "coins", coins, out long t, out long n); lines.Add(Loc.T("Sold for coins: tax {0}, you receive {1} Chaos Coins on your account.", SFmt.Money(t), SFmt.Money(n))); }
            int days = DaysOption();
            lines.Add(Loc.T(days == 1 ? "The offer lasts {0} day; if nothing sells, the item returns to your inbox." : "The offer lasts {0} days; if nothing sells, the item returns to your inbox.", days));
            return string.Join("\n", lines);
        }

        public void Find() { string q = Text("find").Trim(); if (q.Length == 0) { Say(Loc.T("Type the name of the item you want."), false); return; } Send("orderFind", SFmt.Map("q", q)); }

        public Dictionary<string, object> OrderRequest(out string why, out long total, out long fee)
        {
            var pay = new[] { "gold", "coins" };
            int pi = Math.Max(0, Math.Min(1, Index("opay")));
            int ri = Index("orarity");
            var durations = Json.List(Meta, "durations");
            int di = Index("ordays", -1);
            int days = di >= 0 && di < durations.Count && durations[di] is double dd ? (int)dd : (SFmt.Has(Meta, "defaultDuration") ? Json.Int(Meta, "defaultDuration") : 3);
            return MarketMath.CheckOrder(Meta, ChosenKind == null ? 0 : (long)Json.Number(ChosenKind, "sid"), Text("qty"), Text("oprice"), pay[CoinsOk ? pi : 0], days,
                ri > 0 && ri <= MarketMath.RarityIds.Length ? MarketMath.RarityIds[ri - 1] : 0, Text("oilvl"), out total, out fee, out why, OrderMods);
        }

        public void PostOrder()
        {
            var req = OrderRequest(out string why, out _, out _);
            if (req == null) { Say(why, false); return; }
            Send("orderPost", req);
        }

        public void StartFill(object order) { FillOrder = order; FillData = null; FillChosen = null; Form["fill"] = ""; Send("fillable", SFmt.Map("id", Json.Get(order, "id"))); Changed(); }

        public void DoFill()
        {
            if (FillOrder == null || FillChosen == null) return;
            long n = SFmt.ParseAmount(Text("fill"));
            long have = Json.Int(FillChosen, "count", 1);
            if (n < 1 || n > have) { Say(Loc.T("You do not have that many."), false); return; }
            var req = SFmt.Map("id", Json.Get(FillOrder, "id"), "count", n);
            foreach (var k in new[] { "ref", "sid", "iid" }) if (SFmt.Has(FillChosen, k)) req[k] = Json.Get(FillChosen, k);
            Send("fill", req);
        }

        // ------------------------------------------------------------------------------------ rows
        List<string> DaysOptions()
        {
            var o = new List<string>();
            var durations = Json.List(Meta, "durations");
            if (durations.Count == 0) { durations = new List<object> { 1.0, 3.0, 7.0 }; }
            foreach (object x in durations) { int d = x is double dd ? (int)dd : 3; o.Add(d == 1 ? Loc.T("1 day") : Loc.T("{0} days", d)); }
            return o;
        }

        SocialRow OfferRow(RowList l, object offer, string mode)
        {
            int rarity = Json.Int(offer, "rarity");
            bool unique = Json.Truthy(offer, "unique");
            string name = (Json.Int(offer, "count", 1) > 1 ? Json.Int(offer, "count", 1) + "x " : "") + Json.Text(offer, "name", "?");
            string sub = mode == "browse" ? MarketMath.SubLine(offer) : mode == "history" ? MarketMath.HistoryLine(offer) + (Json.Truthy(offer, "order") ? Loc.T(" (buy order)") : "") : MarketMath.StateLine(offer);
            if (mode == "browse")
            {
                var mark = MarketPrices.RowMark(offer);
                if (mark != null) sub += (sub.Length > 0 ? "  -  " : "") + mark.Text;
            }
            string right = "";
            if (mode == "history" || (mode == "closed" && Json.Text(offer, "state") == "sold"))
                right = SFmt.Money(Json.Number(offer, "paid")) + (Json.Text(offer, "cur") == "coins" ? " " + Loc.T("coins") : " " + Loc.T("gold"));
            else foreach (var p in MarketMath.PriceLines(offer)) right += (right.Length > 0 ? "  " : "") + p.Key;
            string key = IdKey(Json.Get(offer, "id"));
            var r = l.Row(name, right, rarity > 0 || unique ? SFmt.RarityTone(rarity, unique) : "text");
            r.Sub = sub;
            r.Item((int)Json.Number(offer, "look") > 0 ? (int)Json.Number(offer, "look") : (int)Json.Number(offer, "item"), Json.Int(offer, "count", 1), rarity > 0 || unique ? SFmt.RarityTone(rarity, unique) : null,
                mode == "browse" && Tips.TryGetValue(key, out var tip) ? tip : null);
            if (mode == "browse")
            {
                var o = offer;
                if (Tips.TryGetValue(key, out var tip2))
                {
                    var matched = MarketMods.MatchedMods(tip2, LastFilter);
                    if (matched.Count > 0)
                    {
                        r.TipExtra = new List<TipLine>();
                        for (int mi = 0; mi < matched.Count; mi++) r.TipExtra.Add(new TipLine { Text = matched[mi], Color = "#7fdc7f", Sep = mi == 0 });
                    }
                }
                r.Hover = () => AskTip(Json.Get(o, "id"));
                r.Btn(Loc.T("Prices"), true, () => ShowPrices(o), MarketPrices.RowTypical(o) ?? "");
                if (!Json.Truthy(offer, "mine")) r.Btn(Loc.T("Buy"), true, () => { ConfirmBuyOffer = o; Changed(); });
                else r.Btn(Loc.T("Cancel"), true, () => { ConfirmCancelOffer = o; Changed(); });
            }
            else if (mode == "mine")
            {
                var o = offer;
                r.Btn(Loc.T("Cancel"), true, () => { ConfirmCancelOffer = o; Changed(); });
            }
            return r;
        }

        void ConfirmRows(RowList l)
        {
            if (ConfirmBuyOffer != null)
            {
                var o = ConfirmBuyOffer;
                string what = (Json.Int(o, "count", 1) > 1 ? Json.Int(o, "count", 1) + "x " : "") + Json.Text(o, "name", "item");
                l.Section(Loc.T("Buy"));
                l.Text(Loc.T("Buy {0} from {1}?", what, Json.Text(o, "seller", "?")) + " " + Loc.T("It goes to your inbox (the depot)."), "warn");
                var row = l.Row("");
                foreach (var p in MarketMath.PriceLines(o)) { string cur = p.Value; row.Btn(Loc.T("Pay {0}", p.Key), true, () => Buy(o, cur)); }
                row.Btn(Loc.T("Cancel"), true, () => { ConfirmBuyOffer = null; Changed(); });
            }
            if (ConfirmCancelOffer != null)
            {
                var o = ConfirmCancelOffer;
                l.Section(Loc.T("Cancel offer"));
                l.Text(Loc.T("Cancel the offer of {0}? The item goes back to your inbox; the listing fee is not refunded.", Json.Text(o, "name", "item")), "warn");
                l.Row("").Btn(Loc.T("Yes"), true, () => CancelOffer(o)).Btn(Loc.T("No"), true, () => { ConfirmCancelOffer = null; Changed(); });
            }
            if (ConfirmOrderCancel != null)
            {
                var o = ConfirmOrderCancel;
                l.Section(Loc.T("Cancel buy order"));
                l.Text(Loc.T("Cancel the buy order of {0}? What it holds comes back; the listing fee does not.", Json.Text(o, "name", "item")), "warn");
                l.Row("").Btn(Loc.T("Yes"), true, () => { ConfirmOrderCancel = null; Send("orderCancel", SFmt.Map("id", Json.Get(o, "id"))); })
                    .Btn(Loc.T("No"), true, () => { ConfirmOrderCancel = null; Changed(); });
            }
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            ConfirmRows(l);
            switch (Tab)
            {
                case "browse": BrowseRows(l); break;
                case "sell": SellRows(l); break;
                case "mine": MineRows(l); break;
                case "history": HistoryRows(l); break;
                case "orders": OrderRows(l); break;
            }
            return l.Rows;
        }

        void BrowseRows(RowList l)
        {
            l.Input(Loc.T("Search"), "q", Loc.T("item name")).Btn(Loc.T("Search"), true, Search);
            l.Combo(Loc.T("Category"), "cat", CategoryOptions());
            l.Combo(Loc.T("Rarity"), "rarity", RarityOptions());
            l.Combo(Loc.T("Currency"), "cur", CurrencyOptions());
            l.Combo(Loc.T("Sort"), "sort", SortOptions());
            l.Input(Loc.T("Item level from"), "ilvlMin"); l.Input(Loc.T("Item level to"), "ilvlMax");
            l.Input(Loc.T("Price from"), "priceMin"); l.Input(Loc.T("Price to"), "priceMax");
            ModRows(l);
            l.Row(MarketMath.PageText(PageNo, Pages, Total), "", "dim").Btn("<", PageNo > 1, () => Page(-1)).Btn(">", PageNo < Pages, () => Page(1));
            var rows = SFmt.Rows(PageData, "rows");
            if (PageData != null && rows.Count == 0) l.Text(Loc.T("No offers match."), "dim");
            if (PriceOffer != null) PriceRows(l);
            foreach (var o in rows) OfferRow(l, o, "browse");
        }

        void ModRows(RowList l)
        {
            int n = ModsActive;
            l.Row(n > 0 ? Loc.T("Modifiers ({0})", n) : Loc.T("Modifiers"), n > 0 && !ModsOpen ? Loc.T("Modifier filters active") : "", n > 0 ? "good" : "dim")
                .Btn(ModsOpen ? Loc.T("Hide") : Loc.T("Show"), true, ToggleMods);
            if (!ModsOpen) return;
            var lim = ModLimits;
            for (int i = 0; i < Mods.Rows.Count; i++)
            {
                int row = i;
                l.Input(Loc.T("Modifier {0}", i + 1), "mq" + i, Loc.T("type to find one"));
                var ch = Catalog.Choices(Text("mq" + i), out _);
                var names = new List<string>(); foreach (var c in ch) names.Add(c.Text);
                l.Combo("", "mc" + i, names);
                l.Input(Loc.T("Lowest value"), "mm" + i, "0");
                l.Combo(Loc.T("Lowest tier"), "mt" + i, MarketMods.TierOptions(lim.MaxTier));
                l.Row("").Btn(Loc.T("Remove"), true, () => RemoveModRow(row));
            }
            var ctl = l.Row("").Btn(Loc.T("Add modifier"), Mods.Rows.Count < lim.MaxRows, AddModRow);
            ctl.Btn(Loc.T("Clear modifiers"), true, ClearMods);
            l.Combo(Loc.T("Match"), "mmode", new List<string> { Loc.T("All of them"), Loc.T("At least N of them") });
            if (Index("mmode") == 1) l.Input(Loc.T("At least"), "mneed", "1");
            l.Input(Loc.T("Sockets"), "msock", "0"); l.Input(Loc.T("Quality"), "mqual", "0");
            l.Row("").Btn(Mods.FreeP ? Loc.T("Free prefix: yes") : Loc.T("Free prefix: any"), true, () => { Mods.FreeP = !Mods.FreeP; Search(); })
                .Btn(Mods.FreeS ? Loc.T("Free suffix: yes") : Loc.T("Free suffix: any"), true, () => { Mods.FreeS = !Mods.FreeS; Search(); });
            l.Row("").Btn(Mods.Power ? Loc.T("Legendary power: yes") : Loc.T("Legendary power: any"), true, () => { Mods.Power = !Mods.Power; Search(); })
                .Btn(Mods.Bound ? Loc.T("Bound modifier: yes") : Loc.T("Bound modifier: any"), true, () => { Mods.Bound = !Mods.Bound; Search(); });
            l.Text(Loc.T("Up to {0} modifiers. Type in the box to find one, the list narrows to what matches. Tiers: T1 is the lowest, T8 the best (T5+ = T5 or better). Press Search after typing.", lim.MaxRows), "dim");
        }

        void OrderModRows(RowList l)
        {
            l.Text(OrderMods != null ? Loc.T("Modifiers: {0}", MarketMods.FilterText(OrderMods, Catalog.NameOf)) : Loc.T("Modifiers: any. Set rows in the Browse tab's Modifiers section, then press Use Browse modifiers."), "dim");
            l.Row("").Btn(Loc.T("Use Browse modifiers"), true, OrderModsFromBrowse).Btn(Loc.T("Clear"), OrderMods != null, () => { OrderMods = null; Changed(); });
        }

        public void OrderModsFromBrowse()
        {
            var req = ModsRequest(out string why);
            if (req == null) { Say(why, false); return; }
            if (MarketMods.Count(req) == 0) { Say(Loc.T("The Browse tab's Modifiers section is empty: add rows there first."), false); return; }
            OrderMods = req; Changed();
        }

        void PriceRows(RowList l)
        {
            l.Section(Loc.T("Price history") + ": " + Json.Text(PriceOffer, "name", "?"));
            if (PriceData == null) { l.Text(Loc.T("Loading..."), "dim"); l.Row("").Btn(Loc.T("Close"), true, ClosePrices); return; }
            if (Json.Truthy(PriceData, "gone")) { l.Text(Loc.T("That offer is gone."), "dim"); l.Row("").Btn(Loc.T("Close"), true, ClosePrices); return; }
            string key = MarketPrices.KeyText(Json.Int(PriceData, "rarity"), Json.Text(PriceData, "bandText"));
            l.Text((key.Length > 0 ? key + "; " : "") + Loc.T("sales on your market only"), "dim");
            var s = Json.Get(PriceData, PriceCur);
            foreach (var line in MarketPrices.Stats(s, PriceCur)) l.Text(line.Text, line.Tone);
            l.Chart(Loc.T("Average price per day, last {0} days", s != null && Json.Get(s, "days") is double dd ? (int)dd : 30), PriceChart.Points(Json.Get(s, "points")), s != null && Json.Get(s, "days") is double d2 ? (int)d2 : 30);
            string other = PriceCur == "gold" ? "coins" : "gold";
            var row = l.Row("");
            var o2 = Json.Get(PriceData, other);
            if (o2 != null && (Json.Int(o2, "n30") > 0 || Json.Int(o2, "n7") > 0))
                row.Btn(other == "coins" ? Loc.T("Coin prices") : Loc.T("Gold prices"), true, () => { PriceCur = other; Changed(); });
            row.Btn(Loc.T("Close"), true, ClosePrices);
        }

        void SellRows(RowList l)
        {
            if (Selected != null)
            {
                int rarity = Json.Int(Selected, "rarity");
                var sel = l.Row(Json.Text(Selected, "name", "?"), "", rarity > 0 ? SFmt.RarityTone(rarity, false) : "gold");
                sel.Item((int)Json.Number(Selected, "item"), Json.Int(Selected, "count", 1), rarity > 0 ? SFmt.RarityTone(rarity, false) : null);
                var sub = new List<string>();
                if (rarity > 0) sub.Add(MarketMath.RarityName(rarity));
                if (Json.Int(Selected, "ilvl") > 0) sub.Add("iLvl " + Json.Int(Selected, "ilvl"));
                sel.Sub = string.Join(" - ", sub);
                if (Json.Truthy(Selected, "stack")) l.Input(Loc.T("Count"), "count", Loc.T("of {0}", Json.Int(Selected, "count", 1)));
                l.Input(Loc.T("Gold price"), "gold", "5k, 2.5m");
                if (CoinsOk) l.Input(Loc.T("Chaos Coins price"), "coins");
                l.Combo(Loc.T("Duration"), "days", DaysOptions());
                string hint = SellHint(out long suggest);
                if (hint.Length > 0)
                {
                    l.Text(hint, "gold");
                    if (suggest > 0) l.Row("").Btn(Loc.T("Use suggested price"), true, () => { Form["gold"] = suggest.ToString(CultureInfo.InvariantCulture); Changed(); });
                }
                foreach (var w in SellWarnings()) l.Text(w.Text, w.Tone);
                l.Text(FeeText(), "dim");
                l.Row("").Btn(Loc.T("List item"), true, () => ListItem()).Btn(Loc.T("Clear"), true, () => { Selected = null; Changed(); });
            }
            else l.Text(Loc.T("No item chosen"), "gold");
            l.Text(Loc.T("Locked, equipped, store and quest items and bags with something inside cannot be listed. Bought items and items that come back arrive in your inbox (the depot); gold goes to your bank, Chaos Coins to your account."), "dim");
            var items = MarketMath.SortSellable(SFmt.Rows(SellData, "items"));
            l.Section(items.Count == 0 && SellData != null ? Loc.T("Your backpack is empty: put the items you want to sell in it.") : Loc.T("Your backpack: click an item to sell it."));
            foreach (var e in items)
            {
                var entry = e;
                int rarity = Json.Int(e, "rarity");
                string why = Json.Text(e, "why");
                var r = l.Row((Json.Int(e, "count", 1) > 1 ? Json.Int(e, "count", 1) + "x " : "") + Json.Text(e, "name", "?"), why, why.Length > 0 ? "dim" : (rarity > 0 ? SFmt.RarityTone(rarity, false) : "text"));
                r.Item((int)Json.Number(e, "item"), Json.Int(e, "count", 1), rarity > 0 ? SFmt.RarityTone(rarity, false) : null);
                r.Btn(Loc.T("Choose"), why.Length == 0, () => ChooseSell(entry));
            }
        }

        void MineRows(RowList l)
        {
            if (MineData == null) { l.Text(Loc.T("Loading..."), "dim"); return; }
            var active = SFmt.Rows(MineData, "active");
            l.Section(Loc.T("Active offers ({0}; listings used with buy orders: {1} / {2})", active.Count, SFmt.Has(MineData, "used") ? Json.Int(MineData, "used") : active.Count, SFmt.Has(MineData, "max") ? Json.Int(MineData, "max") : 20));
            foreach (var o in active) OfferRow(l, o, "mine");
            if (active.Count == 0) l.Text(Loc.T("No active offers. List items in the Sell tab."), "dim");
            if (Json.Int(MineData, "owed") > 0) l.Text(Loc.T("{0} deliveries are on the way to your inbox / bank.", Json.Int(MineData, "owed")), "gold");
            l.Section(Loc.T("Sold, expired and cancelled"));
            foreach (var o in SFmt.Rows(MineData, "closed")) OfferRow(l, o, "closed");
        }

        void HistoryRows(RowList l)
        {
            if (HistoryData == null) { l.Text(Loc.T("Loading..."), "dim"); return; }
            l.Section(Loc.T("Your purchases and sales"));
            var rows = SFmt.Rows(HistoryData, "rows");
            foreach (var o in rows) OfferRow(l, o, "history");
            if (rows.Count == 0) l.Text(Loc.T("Nothing bought or sold yet."), "dim");
        }

        SocialRow OrderRow(RowList l, object o, bool mine)
        {
            string cur = Json.Text(o, "cur") == "coins" ? Loc.T("coins") : Loc.T("gold");
            string right = Loc.T("{0} {1} each", SFmt.Money(Json.Number(o, "price")), cur);
            var r = l.Row(Json.Text(o, "name", "?"), right, Json.Text(o, "cur") == "coins" ? "coins" : "gold");
            r.Sub = MarketMath.OrderSubLine(o, Catalog.NameOf);
            r.Item((int)Json.Number(o, "item"));
            var order = o;
            if (Json.Text(o, "state") == "active")
            {
                if (mine || Json.Truthy(o, "mine")) r.Btn(Loc.T("Cancel"), true, () => { ConfirmOrderCancel = order; Changed(); });
                else r.Btn(Loc.T("Sell"), true, () => StartFill(order));
            }
            return r;
        }

        void OrderRows(RowList l)
        {
            l.Input(Loc.T("Search"), "oq", Loc.T("item name")).Btn(Loc.T("Search"), true, () => { Mine = false; AskOrders(1); });
            l.Combo(Loc.T("Currency"), "ocur", CurrencyOptions());
            { var so = new List<string>(); foreach (var n in MarketMath.OrderSortNames) so.Add(Loc.T(n)); l.Combo(Loc.T("Sort"), "osort", so); }
            l.Row(Mine ? Loc.T("Showing your own buy orders") : Loc.T("Showing every open buy order"), "", "dim").Btn(Mine ? Loc.T("All orders") : Loc.T("My orders"), true, ToggleMine);
            if (FillOrder != null) FillRows(l);
            if (Mine)
            {
                if (MyOrdersData != null)
                {
                    var act = SFmt.Rows(MyOrdersData, "active");
                    l.Section(Loc.T("Your open buy orders (listings used: {0} / {1})", Json.Int(MyOrdersData, "used"), SFmt.Has(MyOrdersData, "max") ? Json.Int(MyOrdersData, "max") : 20));
                    foreach (var o in act) OrderRow(l, o, true);
                    if (act.Count == 0) l.Text(Loc.T("No open buy orders."), "dim");
                    l.Section(Loc.T("Filled, expired and cancelled"));
                    foreach (var o in SFmt.Rows(MyOrdersData, "closed")) OrderRow(l, o, true);
                }
            }
            else if (OrdersData != null)
            {
                int page = Math.Max(1, Json.Int(OrdersData, "page", 1)), pages = Math.Max(1, Json.Int(OrdersData, "pages", 1));
                l.Row(Loc.T("Page {0} / {1}  ({2} orders)", page, pages, Json.Int(OrdersData, "total")), "", "dim")
                    .Btn("<", page > 1, () => AskOrders(page - 1)).Btn(">", page < pages, () => AskOrders(page + 1));
                var rows = SFmt.Rows(OrdersData, "rows");
                if (rows.Count == 0) l.Text(Loc.T("No buy orders match. Post one below: sellers fill it from their backpacks."), "dim");
                foreach (var o in rows) OrderRow(l, o, false);
            }
            PostRows(l);
        }

        void FillRows(RowList l)
        {
            l.Section(Loc.T("Sell to the buy order of {0}", Json.Text(FillOrder, "name", "?")));
            var items = MarketMath.SortFillable(SFmt.Rows(FillData, "items"));
            if (FillData != null && items.Count == 0) l.Text(Loc.T("Nothing in your backpack fits this order."), "dim");
            foreach (var e in items)
            {
                var entry = e;
                string why = Json.Text(e, "why");
                var r = l.Row((Json.Int(e, "count", 1) > 1 ? Json.Int(e, "count", 1) + "x " : "") + Json.Text(e, "name", "?"), why, why.Length > 0 ? "dim" : "text");
                r.Item((int)Json.Number(e, "item"), Json.Int(e, "count", 1));
                r.Btn(Loc.T("Choose"), why.Length == 0, () => { FillChosen = entry; Form["fill"] = Json.Int(entry, "count", 1).ToString(CultureInfo.InvariantCulture); Changed(); });
            }
            if (FillChosen != null)
            {
                l.Input(Loc.T("How many"), "fill", Loc.T("of {0}", Json.Int(FillChosen, "count", 1)));
                l.Text(MarketMath.FillText(Meta, FillOrder, Math.Max(0, SFmt.ParseAmount(Text("fill")))), "dim");
                l.Row("").Btn(Loc.T("Sell"), true, DoFill);
            }
            l.Row("").Btn(Loc.T("Close"), true, () => { FillOrder = FillChosen = null; FillData = null; Changed(); });
        }

        void PostRows(RowList l)
        {
            l.Section(Loc.T("Post a buy order"));
            l.Input(Loc.T("Item name"), "find", Loc.T("type a name")).Btn(Loc.T("Find"), true, Find);
            foreach (var e in SFmt.Rows(FindData, "items"))
            {
                var entry = e;
                l.Row(Json.Text(e, "name", "?")).Item((int)Json.Number(e, "item")).Btn(Loc.T("Choose"), true, () => { ChosenKind = entry; Changed(); });
            }
            l.Text(ChosenKind != null ? Json.Text(ChosenKind, "name", "?") : Loc.T("No item chosen: type its name and press Find."), ChosenKind != null ? "gold" : "dim");
            l.Input(Loc.T("How many"), "qty");
            l.Input(Loc.T("Price each"), "oprice", "5k, 2.5m");
            l.Combo(Loc.T("Pay with"), "opay", CoinsOk ? new List<string> { Loc.T("Gold"), Loc.T("Chaos Coins") } : new List<string> { Loc.T("Gold") });
            l.Combo(Loc.T("Duration"), "ordays", DaysOptions());
            l.Combo(Loc.T("Lowest rarity"), "orarity", RarityOptions());
            l.Input(Loc.T("Lowest item level"), "oilvl");
            OrderModRows(l);
            var req = OrderRequest(out string why, out long total, out long fee);
            l.Text(req != null ? MarketMath.OrderCostText(Meta, req, total, fee) : why, req != null ? "text" : "dim");
            l.Row("").Btn(Loc.T("Post order"), req != null, PostOrder);
        }
    }
}
