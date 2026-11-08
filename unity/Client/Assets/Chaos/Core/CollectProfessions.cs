// Professions (client game_professions, extended opcode 195, server professions). Gathering levels, the demand board of the Material Broker.
//   client -> server  open | close | sell {id} | sellAll
//   server -> client  state {bonus, per, cap, profs [{k, n, lv, xp, need, pct, tier, d, tool, g, bp, book, perks [{k, v, lv, n, on}]}], tiers {"1": {n, col}, ...},
//                     demand [{id, c, n, p, t, g, l, m, h, s}], areas [{n, t, h, m, near, x, y, z, nodes [{k, r, t}]}], broker, full, late, capDay, nextDay, nextWeek}
//                     result {ok, text} | levelup {k, lv} | npc (the broker NPC opens the window)
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

namespace Chaos.Core
{
    public sealed class ProfRow
    {
        public string Key = "", Name = "", XpText = "", TierText = "", TierColor = "", Tool = "", Desc = "";
        public int Level, Pct;
        public double Gathered;
    }

    public sealed class DemandRow
    {
        public int Id, ClientId, Tier, Units;
        public string Name = "", Prof = "", TierColor, PriceText = "", MultText = "", MultColor = "", SoldText = "", HaveText = "";
        public double Worth;
        public bool CanSell;
        public Dictionary<string, object> Raw;
    }

    public sealed class AreaLine { public string Title = "", Color = "", Text = "", Tip = ""; }

    public sealed class ProfessionsState : CollectModel
    {
        public const byte OpcodeId = 195;
        public const string Gold = "#e8b84a", TextColor = "#d8ccb4", Dim = "#8c8070", Good = "#8fd16a", Bad = "#e07060", Warn = "#e0a050", Up = "#8fd16a", Down = "#e07060";
        static readonly string[] Order = { "delving", "wortcunning", "flaying", "angling" };
        static readonly Dictionary<string, string> Books = new Dictionary<string, string> { { "mining", "Mining" }, { "herbalist", "Herbalist" }, { "armorsmith", "Armorsmith" } };
        static readonly Dictionary<string, string> PerkKinds = new Dictionary<string, string>
        {
            { "channel", "gathering takes {0}% less time" }, { "byproduct", "+{0}% chance of a crafting material" },
            { "lucky", "+{0}% chance of one more unit" }, { "flay", "+{0}% chance of a hide" },
        };

        public object State;
        public bool Visible;
        public string StatusText = "", StatusColor = Dim;

        public ProfessionsState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Refresh() { Send("open"); }
        public void Sell(int id) { Send("sell", D("id", (double)id)); }
        public void SellAll() { Send("sellAll"); }

        public override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state": State = data; break;
                case "result": StatusText = CF.T(data, "text"); StatusColor = CF.B(data, "ok") ? Good : Bad; break;
                case "levelup": StatusText = Loc.T("{0} level {1}!", ProfName(State, CF.T(data, "k")), CF.I(data, "lv")); StatusColor = Gold; break;
                case "npc": Show(); break;
            }
        }

        public void Clear() { State = null; Visible = false; }

        // ---------------------------------------------------------------------------------------------- the view rules
        public static string FmtNum(double n) => CF.Group(n) is string s && n < 0 ? "-" + CF.Group(-n) : CF.Group(n);

        /// <summary>2.5 -> "2.5", 0.05 -> "0.05", 3 -> "3" (%.2f, or %.4f below 0.1, trailing zeros stripped).</summary>
        public static string FmtPct(double v)
        {
            string s = v.ToString(Math.Abs(v) < 0.1 ? "0.0000" : "0.00", CultureInfo.InvariantCulture);
            if (s.Contains(".")) { s = s.TrimEnd('0'); if (s.EndsWith(".")) s = s.Substring(0, s.Length - 1); }
            return s;
        }

        public static string TimeText(double sec)
        {
            long s = (long)Math.Max(0, Math.Floor(sec));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return string.Format("{0}d {1}h", d, h);
            if (h > 0) return string.Format("{0}h {1}m", h, m);
            return Math.Max(1, m) + "m";
        }

        public static string ProfName(object s, string key)
        {
            foreach (var p in CF.Rows(CF.G(s, "profs"))) if (CF.T(p, "k") == key) return CF.T(p, "n");
            return key;
        }

        public static string TierName(object s, double t, out string color)
        {
            var tiers = CF.M(s, "tiers");
            string key = ((long)t).ToString(CultureInfo.InvariantCulture);
            if (tiers.TryGetValue(key, out var v) && v is Dictionary<string, object>) { color = CF.T(v, "col", TextColor); return CF.T(v, "n"); }
            color = TextColor;
            return "Tier " + (long)t;
        }

        public string BonusText() => State == null ? "" : Loc.T("Experience bonus: +{0}% from monsters (every profession level above 1 adds {1}%, at most +{2}%)", FmtPct(CF.N(State, "bonus")), FmtPct(CF.N(State, "per")), FmtPct(CF.N(State, "cap")));

        public List<ProfRow> ProfRows()
        {
            var o = new List<ProfRow>();
            foreach (var p in CF.Rows(CF.G(State, "profs")))
            {
                string name = TierName(State, CF.N(p, "tier"), out string color);
                bool mastered = CF.N(p, "need") <= 0;
                o.Add(new ProfRow
                {
                    Key = CF.T(p, "k"), Name = CF.T(p, "n"), Level = CF.I(p, "lv"), XpText = mastered ? Loc.T("Mastered") : string.Format("{0} / {1}", FmtNum(CF.N(p, "xp")), FmtNum(CF.N(p, "need"))),
                    Pct = mastered ? 100 : (int)Math.Max(0, Math.Min(100, CF.N(p, "pct"))), TierText = Loc.T("Gathers {0} materials", name.ToLowerInvariant()), TierColor = color,
                    Tool = CF.T(p, "tool"), Desc = CF.T(p, "d"), Gathered = CF.N(p, "g"),
                });
            }
            return o;
        }

        public List<KeyValuePair<string, bool>> PerkLines(object p)
        {
            var o = new List<KeyValuePair<string, bool>>();
            foreach (var pk in CF.Rows(CF.G(p, "perks")))
            {
                string k = CF.T(pk, "k");
                double pct = k == "channel" ? (1 - CF.N(pk, "v")) * 100 : CF.N(pk, "v") * 100;
                string what = string.Format(CultureInfo.InvariantCulture, Loc.T(PerkKinds.TryGetValue(k, out var f) ? f : "{0}"), FmtPct(Math.Floor(pct * 10 + 0.5) / 10));
                o.Add(new KeyValuePair<string, bool>(Loc.T("Level {0}, {1}: {2}", CF.I(pk, "lv"), Loc.T(CF.T(pk, "n")), what), CF.G(pk, "on") is bool b && b));
            }
            return o;
        }

        public static string CraftText(object p)
        {
            if (!(p is Dictionary<string, object>)) return "";
            var parts = new List<string>();
            if (CF.N(p, "bp") > 0) parts.Add(Loc.T("{0}% chance of a base crafting material per gather", FmtPct(CF.N(p, "bp"))));
            if (CF.G(p, "book") is string book) parts.Add(Loc.T("refine at the {0} crafting table", Loc.T(Books.TryGetValue(book, out var b) ? b : book)));
            return parts.Count == 0 ? "" : Loc.T("Crafting: {0}", string.Join("; ", parts));
        }

        public string ProfTooltip(Dictionary<string, object> p, ProfRow r)
        {
            var lines = new List<string> { Loc.T("{0}\nTool: {1}\n{2} gathered in total", r.Desc, r.Tool, FmtNum(r.Gathered)) };
            string craft = CraftText(p);
            if (craft.Length > 0) lines.Add(craft);
            var perks = PerkLines(p);
            if (perks.Count > 0) { lines.Add(Loc.T("Perks:")); foreach (var l in perks) lines.Add((l.Value ? "+ " : "- ") + l.Key); }
            return string.Join("\n", lines);
        }

        public static string MultText(double m, out string color)
        {
            if (m > 1.001) { color = Up; return "x" + FmtPct(m); }
            if (m < 0.999) { color = Down; return "x" + FmtPct(m); }
            color = TextColor; return "x1";
        }

        /// <summary>How many units of count the day's cap lets you sell and what they fetch (full price up to "full" sold, then the late price).</summary>
        public static void Quote(object s, object row, double count, out int units, out double gold)
        {
            double full = CF.N(s, "full"), cap = CF.N(s, "capDay"), sold = CF.N(row, "s");
            count = Math.Max(0, Math.Floor(count));
            double u = Math.Min(count, Math.Max(0, cap - sold));
            double atFull = Math.Min(u, Math.Max(0, full - sold));
            units = (int)u;
            gold = atFull * CF.N(row, "g") + (u - atFull) * CF.N(row, "l");
        }

        public static bool CanSellRow(object s, object row) => s != null && CF.B(s, "broker") && CF.N(row, "h") > 0 && CF.N(row, "s") < CF.N(s, "capDay");

        public List<DemandRow> DemandRows(string key = null)
        {
            var o = new List<DemandRow>();
            foreach (var d in CF.Rows(CF.G(State, "demand")))
            {
                if (!string.IsNullOrEmpty(key) && CF.T(d, "p") != key) continue;
                string mt = MultText(CF.N(d, "m"), out string mc);
                Quote(State, d, CF.N(d, "h"), out int units, out double worth);
                TierName(State, CF.N(d, "t"), out string tc);
                o.Add(new DemandRow
                {
                    Id = CF.I(d, "id"), ClientId = CF.I(d, "c"), Name = CF.T(d, "n"), Prof = CF.T(d, "p"), Tier = CF.I(d, "t"), TierColor = tc, PriceText = FmtNum(CF.N(d, "g")) + " gold",
                    MultText = mt, MultColor = mc, SoldText = Loc.T("{0} / {1} today", CF.I(d, "s"), CF.I(State, "capDay")), HaveText = Loc.T("{0} carried", FmtNum(CF.N(d, "h"))),
                    Worth = worth, Units = units, CanSell = CanSellRow(State, d), Raw = d,
                });
            }
            return StableSort(o, (a, b) =>
            {
                int oa = Array.IndexOf(Order, a.Prof), ob = Array.IndexOf(Order, b.Prof);
                if (oa < 0) oa = 9; if (ob < 0) ob = 9;
                return oa != ob ? oa.CompareTo(ob) : a.Tier.CompareTo(b.Tier);
            });
        }

        public void SellAllEstimate(out int units, out double gold)
        {
            units = 0; gold = 0;
            foreach (var d in CF.Rows(CF.G(State, "demand"))) { Quote(State, d, CF.N(d, "h"), out int u, out double g); units += u; gold += g; }
        }

        public bool AtBroker => CF.B(State, "broker");

        public List<AreaLine> AreaLines()
        {
            var o = new List<AreaLine>();
            foreach (var a in CF.Rows(CF.G(State, "areas")))
            {
                string tn = TierName(State, CF.N(a, "t"), out string color);
                var parts = new List<string>();
                foreach (var n in CF.Rows(CF.G(a, "nodes")))
                    parts.Add(CF.T(n, "k") == "angling" ? "fishing" : Loc.T("{0} {1}/{2} ready", ProfName(State, CF.T(n, "k")), CF.I(n, "r"), CF.I(n, "t")));
                string where = CF.G(a, "near") is string near ? "near " + near : "";
                string name = CF.T(a, "n");
                o.Add(new AreaLine
                {
                    Title = CF.B(a, "h") ? string.Format("{0} ({1}, {2})", name, tn, Loc.T("hunt")) : string.Format("{0} ({1})", name, tn), Color = color,
                    Text = (parts.Count > 0 ? string.Join(", ", parts) : Loc.T("no nodes")) + (where.Length > 0 ? "; " + where : ""),
                    Tip = Loc.T("{0}{1}\nPosition {2}, {3}, {4}", name, CF.G(a, "m") is string m ? Loc.T(": hunting ground of {0}", m) : "", CF.I(a, "x"), CF.I(a, "y"), CF.I(a, "z")),
                });
            }
            return o;
        }

        public string Footer()
        {
            if (State == null) return "";
            string rule = Loc.T("Full price for {0} a day per material, then {1}% up to {2}.", CF.I(State, "full"), FmtPct(CF.N(State, "late") * 100), CF.I(State, "capDay"));
            return rule + Loc.T(" New day in {0}, new demand in {1}.", TimeText(CF.N(State, "nextDay")), TimeText(CF.N(State, "nextWeek")));
        }

        public string BrokerText() => AtBroker ? Loc.T("You are at a Material Broker: sell here.") : Loc.T("Sell at a Material Broker (next to every temple; in Cinderhold in the market of the teleport room).");
    }
}
