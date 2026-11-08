// Factions (client game_factions, extended opcode 215, server factions.lua) and the Conquest vendor (client game_conquest, opcode 167, server conquest.lua).
//   Factions  client -> server  open {f?} | close | turnin {f} | deliver {key} | buy {key} | craft {key}
//             server -> client  state {now, nextDay, nextWeek, weekCap, gold, sel, ranks [{k, n, min, c}], factions [{k, n, s, c, lore, rival, rep, rank, rn, rc, lo, hi, pct,
//                               nx, wk, wc, dy, dr, ex, npc, near, tok, tn, tid, theme, at}], contracts [{key, f, per, kind, label, p, n, rep, done, give}],
//                               offers [{key, f, kind, n, rank, rn, price, tokens, st, why, wl, wb, item, lv, rar, mods, desc, craft}]}
//                               | msg {text, ok} | npc {f}
//             Go to NPC: opcode 121 (npc_travel.lua) travel {k: "faction_<key>"}.
//   Conquest  client -> server  open | close | buy {k}
//             server -> client  state {bal, level, pz, band, offers [{k, id, c, n, g, l, p, s, set, ok, why}], groups, pity, today, cinder, refine, refineMax}
//                               | result {ok, text} | npc {}
// The faction NPCs and Iselde Varrow open the windows by themselves (npc); the Windows list of the top menu holds both.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public static class FactionsMath
    {
        public static string Countdown(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            return Math.Max(1, m) + "m";
        }

        public static string CardName(object f)
        {
            string n = Json.Text(f, "n", Json.Text(f, "k"));
            return n.StartsWith("The ", StringComparison.Ordinal) ? n.Substring(4) : n;
        }

        public static object Faction(object data, string key) { foreach (var f in SFmt.Rows(data, "factions")) if (Json.Text(f, "k") == key) return f; return null; }

        /// <summary>The faction to show: the one the server asked for, the one shown before, else the first.</summary>
        public static string Select(object data, string current)
        {
            string sel = Json.Text(data, "sel");
            if (sel.Length > 0 && Faction(data, sel) != null) return sel;
            if (!string.IsNullOrEmpty(current) && Faction(data, current) != null) return current;
            var rows = SFmt.Rows(data, "factions");
            return rows.Count > 0 ? Json.Text(rows[0], "k") : "";
        }

        public static string BarText(object f)
        {
            if (f == null) return "";
            string rn = Json.Text(f, "rn"), rep = SFmt.Money(Json.Number(f, "rep"));
            if (Json.Bool(f, "ex") && Json.Number(f, "rep") >= Json.Number(f, "hi")) return rn + "  " + rep;
            if (!SFmt.Has(f, "nx") || Json.Get(f, "nx") is bool b && !b) return rn + "  " + rep;
            return rn + "  " + rep + " / " + SFmt.Money(Json.Number(f, "hi"));
        }

        public static int BarPercent(object f) => (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(f, "pct"))));

        public static string NextText(object f)
        {
            if (f == null || Json.Get(f, "nx") == null || Json.Get(f, "nx") is bool b && !b) return Loc.T("The highest rank.");
            return Loc.T("{0} more to {1}", SFmt.Money(Json.Number(f, "hi") - Json.Number(f, "rep")), Json.Text(f, "nx"));
        }

        public static double CapOf(object f, double cap) => Json.Number(f, "wc") > 0 ? Json.Number(f, "wc") : cap;
        public static string WeekText(object f, double cap) => Loc.T("This week {0} / {1}", SFmt.Money(Json.Number(f, "wk")), SFmt.Money(CapOf(f, cap)));
        public static bool Capped(object f, double cap) { double c = CapOf(f, cap); return f != null && c > 0 && Json.Number(f, "wk") >= c; }

        public static string DrText(object f)
        {
            double m = Json.Number(f, "dr");
            if (m >= 1) return Loc.T("Kills, tokens and events at full value today");
            if (m >= 0.5) return Loc.T("Kills, tokens and events at half value today");
            if (m > 0) return Loc.T("Kills, tokens and events at {0}% today", (int)Math.Floor(m * 100 + 0.5));
            return Loc.T("No more reputation from activity today");
        }

        public static string RivalText(object data, object f)
        {
            object r = Json.Text(f, "rival").Length > 0 ? Faction(data, Json.Text(f, "rival")) : null;
            return r == null ? "" : Loc.T("Rival: {0}. Every gain here costs them a quarter of it (not below Wary, never once they hold you Exalted).", Json.Text(r, "n"));
        }

        public static string TokenText(object f) => f == null ? "" : Loc.T("{0} {1} carried", Json.Int(f, "tok"), Json.Text(f, "tn", Loc.T("tokens")));

        /// <summary>The Turn in button: enabled and the tooltip.</summary>
        public static bool TokenButton(object f, double cap, out string tip)
        {
            tip = "";
            if (f == null) return false;
            string tn = Json.Text(f, "tn", Loc.T("tokens")), npc = Json.Text(f, "npc", Loc.T("the faction NPC"));
            if (Json.Int(f, "tok") <= 0) { tip = Loc.T("Bring {0} from {1} content.", tn, Json.Text(f, "s", Json.Text(f, "n"))); return false; }
            if (!Json.Bool(f, "near")) { tip = Loc.T("Speak with {0} to turn them in.", npc); return false; }
            if (Capped(f, cap) || (Json.Bool(f, "ex") && Json.Number(f, "rep") >= Json.Number(f, "hi"))) { tip = Loc.T("No more reputation this week: keep them."); return false; }
            tip = Loc.T("Give every {0} to {1}.", tn, npc);
            return true;
        }

        public static string HandInText(object f)
        {
            if (f == null) return "";
            string tn = Json.Text(f, "tn", Loc.T("tokens")), npc = Json.Text(f, "npc", Loc.T("the faction NPC"));
            if (Json.Bool(f, "near")) return Loc.T("{0} is listening: turn in your {1} and deliveries here.", npc, tn);
            return Loc.T("Hand in {0} and deliveries to {1}. Use Go to NPC to be taken there.", tn, Json.Text(f, "at", npc));
        }

        public static bool GoButton(object f, out string tip)
        {
            tip = "";
            if (f == null) return false;
            string npc = Json.Text(f, "npc", Loc.T("the faction NPC"));
            if (Json.Bool(f, "near")) { tip = Loc.T("You are already next to {0}.", npc); return false; }
            tip = Loc.T("Takes you in front of {0}. Not in combat; a short wait between two trips.", npc);
            return true;
        }

        /// <summary>Contracts of one faction: daily first, open ones first, then by key.</summary>
        public static List<object> ContractsFor(object data, string key)
        {
            var o = new List<object>();
            foreach (var c in SFmt.Rows(data, "contracts")) if (Json.Text(c, "f") == key) o.Add(c);
            o.Sort((a, b) =>
            {
                bool da = Json.Text(a, "per") == "d", db = Json.Text(b, "per") == "d";
                if (da != db) return da ? -1 : 1;
                bool xa = Json.Bool(a, "done"), xb = Json.Bool(b, "done");
                if (xa != xb) return xa ? 1 : -1;
                return string.CompareOrdinal(Json.Text(a, "key"), Json.Text(b, "key"));
            });
            return o;
        }

        public static string ProgressText(object c)
        {
            if (Json.Bool(c, "done")) return Loc.T("Done");
            if (Json.Text(c, "kind") == "deliver") return Loc.T("Bring it to the NPC");
            return SFmt.Money(Json.Number(c, "p")) + " / " + SFmt.Money(Json.Number(c, "n"));
        }

        public static int ProgressPercent(object c)
        {
            if (Json.Bool(c, "done")) return 100;
            double n = Json.Number(c, "n");
            return n <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(c, "p") * 100 / n)));
        }

        /// <summary>The Deliver button of a delivery contract: shown, enabled and the tooltip.</summary>
        public static bool DeliverButton(object c, object f, out bool enabled, out string tip)
        {
            enabled = false; tip = "";
            if (Json.Text(c, "kind") != "deliver" || Json.Bool(c, "done")) return false;
            if (!Json.Bool(f, "near")) { tip = Loc.T("Speak with {0} to deliver.", Json.Text(f, "npc", Loc.T("the NPC"))); return true; }
            enabled = true; tip = Loc.T("Hand over the materials and the gold.");
            return true;
        }

        public static List<object> OffersFor(object data, string key)
        {
            var o = new List<object>();
            foreach (var x in SFmt.Rows(data, "offers")) if (Json.Text(x, "f") == key) o.Add(x);
            o.Sort((a, b) =>
            {
                int c = Json.Int(a, "rank").CompareTo(Json.Int(b, "rank"));
                if (c != 0) return c;
                c = Json.Number(a, "price").CompareTo(Json.Number(b, "price"));
                return c != 0 ? c : string.CompareOrdinal(Json.Text(a, "key"), Json.Text(b, "key"));
            });
            return o;
        }

        public static string PriceText(object o, object f)
        {
            var p = new List<string>();
            if (Json.Number(o, "price") > 0) p.Add(SFmt.Money(Json.Number(o, "price")) + " " + Loc.T("gold"));
            if (Json.Number(o, "tokens") > 0) p.Add(Json.Int(o, "tokens") + " " + Json.Text(f, "tn", Loc.T("tokens")));
            return p.Count == 0 ? Loc.T("Free") : string.Join(" + ", p);
        }

        /// <summary>The offer's button: text, enabled, tone of the state line and the tooltip.</summary>
        public static string OfferButton(object o, object f, out bool enabled, out string tone, out string tip)
        {
            bool near = Json.Bool(f, "near");
            string who = Json.Text(f, "npc", Loc.T("the quartermaster"));
            string st = Json.Text(o, "st");
            if (st == "locked") { enabled = false; tone = "dim"; tip = Json.Text(o, "why"); return Loc.T("Locked"); }
            if (st == "soldout") { enabled = false; tone = "bad"; tip = Json.Text(o, "why"); return Loc.T("Sold out"); }
            if (st == "owned")
            {
                tone = "#7fb8e8";
                if (Json.Text(o, "kind") == "recipe")
                {
                    enabled = near; tip = near ? Loc.T("Craft once with the materials shown.") : Loc.T("Speak with {0} to craft.", who);
                    return Loc.T("Craft");
                }
                enabled = false; tip = Json.Text(o, "why"); return Loc.T("Owned");
            }
            tone = "good";
            enabled = near; tip = near ? Loc.T("Buy it now.") : Loc.T("Speak with {0} to buy.", who);
            return Loc.T("Buy");
        }

        public static string OfferKindText(object o)
        {
            string kind = Json.Text(o, "kind");
            if (kind == "gear") return Loc.T("Item level {0}, {1}", Json.Int(o, "lv"), MarketMath.RarityName(Json.Int(o, "rar")) ?? "");
            string t = Json.Text(o, "desc");
            if (kind == "orbs" && SFmt.Has(o, "wl")) t = Loc.T("{0} ({1} of {2} this week)", t, Json.Int(o, "wb"), Json.Int(o, "wl"));
            return t;
        }

        public static string ResetText(object data) => data == null ? "" : Loc.T("Daily contracts in {0}, weekly in {1}", Countdown(Json.Number(data, "nextDay")), Countdown(Json.Number(data, "nextWeek")));
    }

    public sealed class FactionsPanel : SocialPanel
    {
        public const byte Opcode = 215, TravelOpcode = 121;
        readonly ExtOpcodes ext;
        public object Data;
        public string Selected = "";
        public bool OffersTab;
        double dataAt;
        public Func<double> Clock = () => 0;

        public FactionsPanel(ExtOpcodes e) { ext = e; e.On(Opcode, OnMessage); }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Visible = true; Send("open", Selected.Length > 0 ? SFmt.Map("f", Selected) : new Dictionary<string, object>()); }
        public override void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public override void Clear() { base.Clear(); Data = null; Selected = ""; OffersTab = false; Tabs.Clear(); }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "state":
                    string sel = Json.Text(d, "sel");
                    Data = d; dataAt = Clock();
                    Selected = FactionsMath.Select(d, sel.Length > 0 ? sel : Selected);
                    if (d is Dictionary<string, object> map) map["sel"] = null;
                    Tabs.Clear();
                    foreach (var f in SFmt.Rows(d, "factions")) Tabs.Add(new KeyValuePair<string, string>(Json.Text(f, "k"), FactionsMath.CardName(f)));
                    Tab = Selected;
                    break;
                case "msg": Status = Json.Text(d, "text"); StatusTone = Json.Bool(d, "ok") ? "good" : "bad"; break;
                case "npc":
                    string f2 = Json.Get(d, "f") as string;
                    if (!string.IsNullOrEmpty(f2)) { Selected = f2; Tab = f2; }
                    Show();
                    break;
            }
            Changed();
        }

        public override void SelectTab(string key) { Selected = key; Tab = key; Changed(); }
        public void TurnIn() { if (Selected.Length > 0) Send("turnin", SFmt.Map("f", Selected)); }
        public void GoToNpc() { if (Selected.Length > 0) ext.Send(TravelOpcode, "travel", SFmt.Map("k", "faction_" + Selected)); }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (Data == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            object f = FactionsMath.Faction(Data, Selected);
            double cap = Json.Number(Data, "weekCap");
            Header1 = ""; Header2 = FactionsMath.ResetText(Data);
            foreach (var x in SFmt.Rows(Data, "factions"))
            {
                var r = l.Row(FactionsMath.CardName(x) + (Json.Text(x, "k") == Selected ? "  <" : ""), FactionsMath.BarText(x), Json.Text(x, "c").Length > 0 ? Json.Text(x, "c") : "text");
                r.Tip = FactionsMath.NextText(x) + "\n" + FactionsMath.WeekText(x, cap);
                if (Json.Bool(x, "near")) r.Text += "  (" + Loc.T("{0} is here", Json.Text(x, "npc")) + ")";
            }
            if (f == null) return l.Rows;
            l.Section(Json.Text(f, "n", Json.Text(f, "k")));
            if (Json.Text(f, "lore").Length > 0) l.Text(Json.Text(f, "lore"), "dim");
            string rival = FactionsMath.RivalText(Data, f);
            if (rival.Length > 0) l.Text(rival, "bad");
            l.Bar(FactionsMath.BarText(f), FactionsMath.BarPercent(f));
            l.Text(FactionsMath.NextText(f), "dim");
            l.Text(FactionsMath.WeekText(f, cap), FactionsMath.Capped(f, cap) ? "bad" : "text");
            l.Text(FactionsMath.DrText(f), "dim");
            bool turn = FactionsMath.TokenButton(f, cap, out string turnTip);
            l.Row(FactionsMath.TokenText(f)).Item(Json.Int(f, "tid")).Btn(Loc.T("Turn in"), turn, TurnIn, turnTip);
            l.Text(FactionsMath.HandInText(f), Json.Bool(f, "near") ? "good" : "text");
            bool go = FactionsMath.GoButton(f, out string goTip);
            l.Row("").Btn(Loc.T("Go to NPC"), go, GoToNpc, goTip);
            var contracts = FactionsMath.ContractsFor(Data, Selected);
            int open = 0; foreach (var c in contracts) if (!Json.Bool(c, "done")) open++;
            l.Row("")
                .Btn(open > 0 ? Loc.T("Contracts ({0})", open) : Loc.T("Contracts"), true, () => { OffersTab = false; Changed(); })
                .Btn(Loc.T("Offers"), true, () => { OffersTab = true; Changed(); });
            if (!OffersTab)
            {
                l.Section(Loc.T("Contracts"));
                if (contracts.Count == 0) l.Text(Loc.T("No contracts right now."), "dim");
                foreach (var c in contracts)
                {
                    string key = Json.Text(c, "key");
                    bool daily = Json.Text(c, "per") != "w";
                    var row = l.Row((daily ? Loc.T("Daily") : Loc.T("Weekly")) + "  " + Json.Text(c, "label"), FactionsMath.ProgressText(c) + "  +" + Json.Int(c, "rep"), Json.Bool(c, "done") ? "good" : daily ? "#e8b84a" : "#b98ae8");
                    row.Tip = Json.Text(c, "label");
                    if (FactionsMath.DeliverButton(c, f, out bool en, out string tip)) row.Btn(Loc.T("Deliver"), en, () => Send("deliver", SFmt.Map("key", key)), tip);
                    else l.Bar(FactionsMath.ProgressText(c), FactionsMath.ProgressPercent(c));
                }
            }
            else
            {
                l.Section(Loc.T("Offers"));
                var offers = FactionsMath.OffersFor(Data, Selected);
                if (offers.Count == 0) l.Text(Loc.T("Nothing on offer."), "dim");
                foreach (var o in offers)
                {
                    string key = Json.Text(o, "key"), kind = Json.Text(o, "kind");
                    bool recipeOwned = Json.Text(o, "st") == "owned" && kind == "recipe";
                    string label = FactionsMath.OfferButton(o, f, out bool en, out string tone, out string tip);
                    var row = l.Row(Json.Text(o, "n", key), FactionsMath.PriceText(o, f), Json.Text(o, "st") == "locked" ? "dim" : "text");
                    row.Item(Json.Int(o, "item"));
                    row.Btn(label, en, () => Send(recipeOwned ? "craft" : "buy", SFmt.Map("key", key)), tip);
                    l.Text(Loc.T("Needs {0}", Json.Text(o, "rn", "?")) + "  -  " + FactionsMath.OfferKindText(o), tone);
                }
            }
            return l.Rows;
        }
    }

    // ---------------------------------------------------------------------------------------- Conquest vendor
    public static class ConquestMath
    {
        public static readonly string[] TabIds = { "uniques", "sets", "chase", "cinder", "refine", "progress" };
        public static readonly string[] TabNames = { "Uniques", "Set Pieces", "Raid & Ascended", "Cinderheart", "Refine", "Progress" };

        public static bool InTab(string tab, string group)
        {
            switch (tab)
            {
                case "uniques": return group == "monster" || group == "boss";
                case "sets": return group == "set";
                case "chase": return group == "raid" || group == "ascended";
                default: return false;
            }
        }

        public static string Header(object s) =>
            !SFmt.IsMap(s) ? Loc.T("Loading...") : Loc.T("Conquest Tokens: {0}. Items up to level {1} (your level + {2}) and every item you have seen are on sale.",
                SFmt.Money(Json.Number(s, "bal")), Json.Int(s, "level") + Json.Int(s, "band"), Json.Int(s, "band"));

        public static string PlaceText(object s, out string tone)
        {
            tone = "dim";
            if (!SFmt.IsMap(s)) return "";
            if (Json.Bool(s, "pz")) { tone = "good"; return Loc.T("You may buy here."); }
            tone = "bad";
            return Loc.T("Buy from a protection zone or next to Iselde Varrow.");
        }

        static string GroupName(object s, string g) { foreach (var e in SFmt.Rows(s, "groups")) if (Json.Text(e, "g") == g) return Json.Text(e, "n", g); return g; }

        public sealed class ConquestRow
        {
            public string Key = "", Name = "", Sub = "", PriceText = "", Tip = "", Tone = "text";
            public int ClientId;
            public bool CanBuy, Locked, PriceBad;
        }

        static ConquestRow Row(object s, string key, double clientId, string name, string sub, double price, bool hasPrice, bool ok, string why, string tone)
        {
            bool afford = Json.Number(s, "bal") >= price;
            bool can = ok && afford && Json.Bool(s, "pz");
            string tip = !string.IsNullOrEmpty(why) ? why : (!afford && hasPrice ? Loc.T("You need {0} Conquest Tokens.", SFmt.Money(price)) : (!Json.Bool(s, "pz") ? Loc.T("Buy from a protection zone or next to Iselde Varrow.") : ""));
            int id = clientId >= 1 && clientId <= 65535 && clientId == Math.Floor(clientId) ? (int)clientId : 0;
            return new ConquestRow { Key = key, ClientId = id, Name = name, Sub = sub, PriceText = hasPrice ? Loc.T("{0} tokens", SFmt.Money(price)) : "", Tip = tip, Tone = tone, CanBuy = can, Locked = !ok, PriceBad = !(ok && afford) };
        }

        public static List<ConquestRow> Rows(object s, string tab)
        {
            var o = new List<ConquestRow>();
            if (!SFmt.IsMap(s)) return o;
            if (tab == "uniques" || tab == "sets" || tab == "chase")
            {
                foreach (var x in SFmt.Rows(s, "offers"))
                {
                    string g = Json.Text(x, "g");
                    if (!InTab(tab, g)) continue;
                    string sub = Loc.T("{0}, level {1}", GroupName(s, g), Json.Int(x, "l"));
                    if (Json.Text(x, "set").Length > 0) sub += " - " + Json.Text(x, "set");
                    bool ok = Json.Bool(x, "ok");
                    o.Add(Row(s, Json.Text(x, "k"), Json.Number(x, "c"), Json.Text(x, "n"), sub, Json.Number(x, "p"), true, ok, Json.Text(x, "why"), ok ? (g == "set" ? "#58c878" : "#ff9a40") : "locked"));
                }
            }
            else if (tab == "cinder")
            {
                object c = Json.Get(s, "cinder");
                if (!SFmt.IsMap(c)) return o;
                foreach (var k in SFmt.Rows(c, "omens"))
                {
                    o.Add(Row(s, "omen:" + Json.Text(k, "k"), 0, Loc.T("Omen Key: {0}", Json.Text(k, "n")), Loc.T("An Omen Key of this kind"), Json.Number(c, "omenKey"), true, true, "", "#ff9a40"));
                    bool hasKey = Json.Bool(c, "hasKey");
                    o.Add(Row(s, "attune:" + Json.Text(k, "k"), 0, Loc.T("Attune your Omen Key: {0}", Json.Text(k, "n")), Loc.T("The Omen Key you carry takes this kind"), Json.Number(c, "attune"), true, hasKey,
                        hasKey ? "" : Loc.T("Carry an Omen Key to attune it."), "text"));
                }
                object conv = Json.Get(c, "convert"), shards = Json.Get(c, "shards"), relics = Json.Get(c, "relics");
                var asc = SFmt.Rows(c, "ascended");
                foreach (var k in asc)
                    o.Add(Row(s, "shard:" + Json.Text(k, "k"), 0, Loc.T("Ascended Shard: {0}", Json.Text(k, "n")), Loc.T("You carry {0}", Json.Int(shards, Json.Text(k, "k"))), Json.Number(c, "shard"), true, true, "", "#ff9a40"));
                foreach (var from in asc)
                    foreach (var to in asc)
                    {
                        string fk = Json.Text(from, "k"), tk = Json.Text(to, "k");
                        if (fk == tk) continue;
                        double ns = Json.Number(conv, "shards"), nr = Json.Number(conv, "relics"), fee = Json.Number(conv, "fee");
                        bool okS = Json.Number(shards, fk) >= ns && ns > 0, okR = Json.Number(relics, fk) >= nr && nr > 0;
                        o.Add(Row(s, "conv:shards:" + fk + ":" + tk, 0, Loc.T("{0} {1} shards into 1 {2} shard", (long)ns, Json.Text(from, "n"), Json.Text(to, "n")), Loc.T("You carry {0}", Json.Int(shards, fk)), fee, true, okS,
                            okS ? "" : Loc.T("You do not carry enough of that kind to convert."), "text"));
                        o.Add(Row(s, "conv:relics:" + fk + ":" + tk, 0, Loc.T("{0} {1} relics into 1 {2} relic", (long)nr, Json.Text(from, "n"), Json.Text(to, "n")), Loc.T("You carry {0}", Json.Int(relics, fk)), fee, true, okR,
                            okR ? "" : Loc.T("You do not carry enough of that kind to convert."), "text"));
                    }
            }
            else if (tab == "refine")
            {
                foreach (var r in SFmt.Rows(s, "refine"))
                    o.Add(Row(s, "refine:" + Json.Int(r, "slot"), Json.Number(r, "c"), Json.Text(r, "n"), Loc.T("{0} to {1}: keeps every modifier, adds one", Json.Text(r, "rn"), Json.Text(r, "to")),
                        Json.Number(r, "p"), SFmt.Has(r, "p"), Json.Bool(r, "ok"), Json.Text(r, "why"), "text"));
            }
            return o;
        }

        public static List<string> ProgressLines(object s)
        {
            var o = new List<string>();
            if (!SFmt.IsMap(s)) return o;
            o.Add(Loc.T("Bad-luck protection: every miss raises your next chance; a drop starts the count again."));
            foreach (var p in SFmt.Rows(s, "pity")) o.Add(Loc.T("{0}: {1} misses in a row, chance x{2}", Json.Text(p, "n", Json.Text(p, "g")), Json.Int(p, "m"), Json.Number(p, "x").ToString("0.00", CultureInfo.InvariantCulture)));
            o.Add("");
            o.Add(Loc.T("Tokens earned today (the limit resets at midnight):"));
            foreach (var t in SFmt.Rows(s, "today")) o.Add(Loc.T("{0}: {1} of {2}", Json.Text(t, "n", Json.Text(t, "k")), Json.Int(t, "got"), Json.Int(t, "cap")));
            return o;
        }

        public static string EmptyText(string tab) =>
            tab == "refine" ? Loc.T("Wear an item with a rarity to refine it (it rises one rarity, keeps its modifiers and gains one).") : Loc.T("Nothing here yet.");
    }

    public sealed class ConquestPanel : SocialPanel
    {
        public const byte Opcode = 167;
        public const double BuyWaitMs = 4000;
        readonly ExtOpcodes ext;
        public object State;
        public bool Buying;
        double buyAt;
        public Func<double> Clock = () => 0;

        public ConquestPanel(ExtOpcodes e)
        {
            ext = e;
            for (int i = 0; i < ConquestMath.TabIds.Length; i++) Tabs.Add(new KeyValuePair<string, string>(ConquestMath.TabIds[i], ConquestMath.TabNames[i]));
            Tab = "uniques";
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Visible = true; Send("open"); }
        public override void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public override void Clear() { base.Clear(); State = null; Buying = false; Tab = "uniques"; }

        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "state": State = d; Buying = false; break;
                case "result": Buying = false; Status = Json.Text(d, "text"); StatusTone = Json.Bool(d, "ok") ? "good" : "bad"; break;
                case "npc": Show(); break;
            }
            Changed();
        }

        /// <summary>One purchase at a time: the Buy buttons stay off until the answer comes (BuyWaitMs at most).</summary>
        public bool Buy(string key)
        {
            if (State == null || (Buying && Clock() - buyAt < BuyWaitMs) || string.IsNullOrEmpty(key)) return false;
            Buying = true; buyAt = Clock();
            Status = Loc.T("Sending your order..."); StatusTone = "dim";
            Send("buy", SFmt.Map("k", key));
            Changed();
            return true;
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = ConquestMath.Header(State);
            string tone; Header2 = ConquestMath.PlaceText(State, out tone);
            if (State == null) return l.Rows;
            bool busy = Buying && Clock() - buyAt < BuyWaitMs;
            if (Tab == "progress") { foreach (var line in ConquestMath.ProgressLines(State)) l.Text(line, line.Length == 0 ? "" : "text"); return l.Rows; }
            var rows = ConquestMath.Rows(State, Tab);
            if (rows.Count == 0) l.Text(ConquestMath.EmptyText(Tab), "dim");
            foreach (var r in rows)
            {
                string key = r.Key;
                var row = l.Row(r.Name, r.PriceText, r.PriceBad ? "bad" : "gold");
                row.Item(r.ClientId);
                row.Tone = r.PriceBad ? "bad" : "gold";
                row.Tip = r.Tip;
                l.Text(r.Sub, r.Tone);
                row.Btn(Loc.T("Buy"), r.CanBuy && !busy, () => Buy(key), r.Tip);
            }
            return l.Rows;
        }
    }
}
