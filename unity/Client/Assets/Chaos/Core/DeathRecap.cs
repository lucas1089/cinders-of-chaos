// The death recap: after a death the server tells who hit the character in its last seconds (each attacker with damage, share, health and mana
// part and element split), the killing blow, the experience and levels lost, the last hits and a few tips, plus the character's last deaths.
// A port of game_deathrecap/deathrecaplogic.lua (the pure rules) and deathrecap.lua (the protocol). Server: data/scripts/chaos/deathrecap.lua.
//
// Extended opcode 154 (JSON {action, data}):
//   client -> server  open {id?}   the history and one recap (the newest, or id)       get {id}   one recap
//   server -> client  history {list = [summary], sel, recap}   recap {id, recap, auto}  (auto: open by itself)
// The server stores a recap at the death and sends it at the next login (auto, once the experience lost is filled in), or at once for a
// defeat in a mode; the window opens by itself when auto is true and "Open after a death" is on. Short numbers follow the damage numbers'
// rule (client_chaos_numbers: 1150 is 1.15k). Tests: Core.Tests/HelperTests.cs (mirrors deathrecaplogic_test.lua).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public sealed class DeathElement { public string Key = "", Name = "", Color = ""; public double Amount, Pct; }

    public sealed class DeathRow
    {
        public string Name = "", Kind = "c", KindName = "", Color = "", ElText = "";
        public double Total, Hp, Mp, Hits, Crits, Max, Pct, Frac;
        public int CritPct;
        public List<DeathElement> Elements = new List<DeathElement>();
        /// <summary>The outfit look the server sent (type, auxType, head, body, legs, feet, addons), null when none.</summary>
        public Dictionary<string, int> Outfit;
    }

    public sealed class DeathHeader { public string Title = "", Sub = "", Loss = "", Window = "", Totals = ""; }
    public sealed class DeathTimelineLine { public string Time = "", Name = "", Element = "", Color = "", Text = ""; public double Amount; public bool Crit, Mana, Death; }
    public sealed class DeathHistoryRow { public int Id; public string Title = "", Sub = "", Killer = ""; public bool Selected; }
    public sealed class DeathSegment { public string Color = ""; public double Frac; }

    public static class DeathRecapRules
    {
        public const double DeathMs = 100;
        public const int TipsMax = 3;

        static readonly string[,] Elements =
        {
            { "physical", "Physical", "#a8a090" }, { "fire", "Fire", "#e0602a" }, { "earth", "Earth", "#5aa83a" }, { "energy", "Energy", "#a050e0" },
            { "ice", "Ice", "#5ab0e0" }, { "holy", "Holy", "#e8d070" }, { "death", "Death", "#7a3a8a" }, { "drown", "Drown", "#3a70c0" },
            { "lifedrain", "Life drain", "#c02a3a" }, { "manadrain", "Mana drain", "#4a5ad0" }, { "other", "Other", "#6b6258" },
        };

        static double Num(object o, string key, double fallback = 0)
        {
            var v = Json.Get(o, key);
            return v is double d && !double.IsNaN(d) && !double.IsInfinity(d) ? d : fallback;
        }

        static bool Has(object o, string key) => Json.Get(o, key) is double;

        // ------------------------------------------------------------------------------------ formats
        /// <summary>Short numbers by the rule of client_chaos_numbers formatShortNumber: 1150 is 1.15k, 150000 is 150k, integer arithmetic only.</summary>
        public static string Short(double n)
        {
            double v = n;
            string sign = "";
            if (v < 0) { sign = "-"; v = -v; }
            if (v < 1000) return sign + (v == Math.Floor(v) ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("R", CultureInfo.InvariantCulture));
            long value = (long)Math.Floor(v);
            string[] units = { "", "k", "M", "B", "T" };
            int unit = 0;
            long div = 1;
            while (unit < units.Length - 1 && value / div >= 1000) { div *= 1000; unit++; }
            long whole = value / div;
            int decimals = whole >= 100 ? 0 : (whole >= 10 ? 1 : 2);
            string text;
            if (decimals == 0) text = whole.ToString(CultureInfo.InvariantCulture);
            else
            {
                int factor = decimals == 2 ? 100 : 10;
                long scaled = value / (div / factor);
                long frac = scaled - whole * factor;
                text = whole.ToString(CultureInfo.InvariantCulture) + "." + frac.ToString(new string('0', decimals), CultureInfo.InvariantCulture);
                text = text.TrimEnd('0').TrimEnd('.');
            }
            return sign + text + units[unit];
        }

        /// <summary>Thousands separated by commas (formatExactNumber).</summary>
        public static string Exact(double n)
        {
            long v = (long)Math.Floor(n);
            return v.ToString("N0", CultureInfo.InvariantCulture);
        }

        /// <summary>The share of a total, one decimal ("68.2"), a whole number without it.</summary>
        public static double Percent(double part, double total)
        {
            if (total <= 0) return 0;
            return Math.Floor(part * 1000 / total + 0.5) / 10;
        }

        /// <summary>ms to "0.8 s", "12.4 s", "1:05".</summary>
        public static string Seconds(double ms)
        {
            ms = Math.Max(0, Math.Floor(ms));
            if (ms < 60000)
            {
                long tenths = (long)(ms / 100);
                return (tenths / 10).ToString(CultureInfo.InvariantCulture) + "." + (tenths % 10).ToString(CultureInfo.InvariantCulture) + " s";
            }
            long s = (long)(ms / 1000);
            return (s / 60).ToString(CultureInfo.InvariantCulture) + ":" + (s % 60).ToString("00", CultureInfo.InvariantCulture);
        }

        /// <summary>Unix time to "12 Oct 21:04" in the local time of the client; "?" for none.</summary>
        public static string Clock(double at)
        {
            if (at <= 0) return "?";
            try { return DateTimeOffset.FromUnixTimeSeconds((long)at).ToLocalTime().ToString("dd MMM HH:mm", CultureInfo.InvariantCulture); }
            catch (Exception) { return "?"; }
        }

        public static string ElementName(string el)
        {
            for (int i = 0; i < Elements.GetLength(0); i++) if (Elements[i, 0] == el) return Loc.T(Elements[i, 1]);
            return Loc.T("Other");
        }

        public static string ElementColor(string el)
        {
            for (int i = 0; i < Elements.GetLength(0); i++) if (Elements[i, 0] == el) return Elements[i, 2];
            return "#6b6258";
        }

        /// <summary>An attacker's shown name: "War Wolf (Varek)" for a summon.</summary>
        public static string DisplayName(string n, string master)
        {
            n = string.IsNullOrEmpty(n) ? Loc.T("Unknown") : n;
            return string.IsNullOrEmpty(master) ? n : n + " (" + master + ")";
        }

        static string KindName(string kind)
        {
            switch (kind)
            {
                case "u": return Loc.T("Player");
                case "s": return Loc.T("Yourself");
                case "e": return Loc.T("Environment");
                case "h": return Loc.T("Hidden");
                case "o": return Loc.T("Others");
                default: return Loc.T("Monster");
            }
        }

        static string KindColor(string kind)
        {
            switch (kind)
            {
                case "u": return "#f6cf72";
                case "s": case "e": return "#a8a090";
                case "h": case "o": return "#8c8070";
                default: return "#f2e8d0";
            }
        }

        // ------------------------------------------------------------------------------------ outfit, elements, rows
        public static Dictionary<string, int> Outfit(object look)
        {
            if (!(look is Dictionary<string, object>)) return null;
            var fields = new[] { new KeyValuePair<string, int>("type", 65535), new KeyValuePair<string, int>("auxType", 65535), new KeyValuePair<string, int>("head", 255),
                new KeyValuePair<string, int>("body", 255), new KeyValuePair<string, int>("legs", 255), new KeyValuePair<string, int>("feet", 255), new KeyValuePair<string, int>("addons", 3) };
            var o = new Dictionary<string, int>();
            foreach (var f in fields)
            {
                int v = (int)Math.Floor(Num(look, f.Key));
                o[f.Key] = v >= 0 && v <= f.Value ? v : 0;
            }
            return o["type"] == 0 && o["auxType"] == 0 ? null : o;
        }

        /// <summary>{element = amount} to the elements, largest first (ties by key), with their share.</summary>
        public static List<DeathElement> ElementList(object el)
        {
            var o = new List<DeathElement>();
            var map = el as Dictionary<string, object>;
            if (map == null) return o;
            double total = 0;
            foreach (var kv in map)
            {
                double a = kv.Value is double d ? d : 0;
                if (a <= 0) continue;
                total += a;
                o.Add(new DeathElement { Key = kv.Key, Name = ElementName(kv.Key), Color = ElementColor(kv.Key), Amount = a });
            }
            o.Sort((a, b) => a.Amount != b.Amount ? b.Amount.CompareTo(a.Amount) : string.CompareOrdinal(a.Key, b.Key));
            foreach (var e in o) e.Pct = Percent(e.Amount, total);
            return o;
        }

        /// <summary>The attacker rows, most damage first, "Others" last.</summary>
        public static List<DeathRow> Rows(object recap)
        {
            var o = new List<DeathRow>();
            var att = Json.List(recap, "att");
            double total = Num(recap, "tot"), top = 0;
            foreach (object a in att)
            {
                if (!(a is Dictionary<string, object>)) continue;
                double hits = Num(a, "h"), crits = Num(a, "c");
                var row = new DeathRow
                {
                    Name = DisplayName(Json.Text(a, "n", null), Json.Text(a, "m", null)), Kind = Json.Text(a, "kind", "c"), Total = Num(a, "tot"), Hp = Num(a, "hp"), Mp = Num(a, "mp"),
                    Hits = hits, Crits = crits, Max = Num(a, "x"), CritPct = hits > 0 ? (int)Math.Floor(crits * 100 / hits + 0.5) : 0,
                    Elements = ElementList(Json.Get(a, "el")), Outfit = Outfit(Json.Get(a, "look")),
                };
                row.KindName = KindName(row.Kind);
                row.Color = KindColor(row.Kind);
                if (row.Total > top) top = row.Total;
                o.Add(row);
            }
            // a stable sort: Others last, then the most damage, then the name
            var keyed = new List<KeyValuePair<int, DeathRow>>();
            for (int i = 0; i < o.Count; i++) keyed.Add(new KeyValuePair<int, DeathRow>(i, o[i]));
            keyed.Sort((x, y) =>
            {
                bool xo = x.Value.Kind == "o", yo = y.Value.Kind == "o";
                if (xo != yo) return xo ? 1 : -1;
                if (x.Value.Total != y.Value.Total) return y.Value.Total.CompareTo(x.Value.Total);
                int c = string.CompareOrdinal(x.Value.Name, y.Value.Name);
                return c != 0 ? c : x.Key.CompareTo(y.Key);
            });
            o.Clear();
            foreach (var k in keyed) o.Add(k.Value);
            foreach (var r in o)
            {
                r.Pct = Percent(r.Total, total);
                r.Frac = top > 0 ? r.Total / top : 0;
                var parts = new List<string>();
                for (int i = 0; i < r.Elements.Count && i < 4; i++) parts.Add(r.Elements[i].Name + " " + Short(r.Elements[i].Amount));
                r.ElText = string.Join(", ", parts);
            }
            return o;
        }

        /// <summary>The bar segments of a row (fractions of the row's own bar), or of the whole recap with its own element map and total.</summary>
        public static List<DeathSegment> Segments(IList<DeathElement> elements, double total)
        {
            var o = new List<DeathSegment>();
            if (total <= 0) return o;
            foreach (var e in elements) o.Add(new DeathSegment { Color = e.Color, Frac = e.Amount / total });
            return o;
        }

        // ------------------------------------------------------------------------------------ header, killing blow, timeline
        public static string KillingBlow(object recap)
        {
            var kb = Json.Get(recap, "kb");
            string name = DisplayName(Json.Text(kb, "n", null), Json.Text(kb, "m", null));
            double a = Num(kb, "a");
            if (a <= 0) return Loc.T("Killing blow: {0}", name);
            return Loc.T("Killing blow: {0}, {1} {2}{3}{4}", name, Exact(a), ElementName(Json.Text(kb, "el", "other")).ToLowerInvariant(),
                Num(kb, "c") == 1 ? " " + Loc.T("(critical)") : "", Num(kb, "mp") == 1 ? " " + Loc.T("(mana)") : "");
        }

        public static DeathHeader Header(object recap)
        {
            var kb = Json.Get(recap, "kb");
            bool defeat = Has(recap, "real") && Num(recap, "real") == 0;
            string who = DisplayName(Json.Text(kb, "n", null), Json.Text(kb, "m", null));
            var h = new DeathHeader { Title = Loc.T(defeat ? "Defeated by {0}" : "Killed by {0}", who) };
            var sub = new List<string> { Clock(Num(recap, "at")) };
            if (Has(recap, "lvl")) sub.Add(Loc.T("level {0}", (int)Num(recap, "lvl")));
            string mode = Json.Text(recap, "mode", "");
            if (mode != "") sub.Add(mode);
            if (Num(recap, "pvp") == 1) sub.Add("PvP");
            h.Sub = string.Join(", ", sub);
            bool hasXl = Has(recap, "xl");
            double xl = Num(recap, "xl"), ll = Num(recap, "ll");
            if (defeat) h.Loss = Loc.T("Nothing lost");
            else if (!hasXl) h.Loss = Loc.T("Experience lost: shown at your next login");
            else if (xl <= 0 && ll <= 0) h.Loss = Loc.T("No experience lost");
            else
            {
                h.Loss = Loc.T("Lost {0} experience", Short(xl));
                if (Has(recap, "ll") && ll > 0) h.Loss += Loc.T(ll == 1 ? " and {0} level" : " and {0} levels", (int)ll);
            }
            double tot = Num(recap, "tot"), hp = Num(recap, "hp"), mp = Num(recap, "mp"), nh = Num(recap, "nh");
            if (tot <= 0) { h.Window = Loc.T("No hits recorded before the death"); h.Totals = ""; }
            else
            {
                h.Window = Loc.T(nh == 1 ? "Last {0} before the death, {1} hit" : "Last {0} before the death, {1} hits", Seconds(Num(recap, "dur")), (int)nh);
                h.Totals = Loc.T("Damage taken: {0}", Short(tot));
                if (mp > 0) h.Totals += Loc.T(" (health {0}, mana {1})", Short(hp), Short(mp));
            }
            return h;
        }

        /// <summary>The last hits, oldest first.</summary>
        public static List<DeathTimelineLine> Timeline(object recap)
        {
            var o = new List<DeathTimelineLine>();
            foreach (object h in Json.List(recap, "last"))
            {
                if (!(h is Dictionary<string, object>)) continue;
                double dt = Num(h, "dt");
                var e = new DeathTimelineLine
                {
                    Death = dt < DeathMs, Name = DisplayName(Json.Text(h, "n", null), null), Amount = Num(h, "a"), Element = ElementName(Json.Text(h, "el", "other")),
                    Color = ElementColor(Json.Text(h, "el", "other")), Crit = Num(h, "c") == 1, Mana = Num(h, "mp") == 1,
                };
                e.Time = e.Death ? Loc.T("death") : "-" + Seconds(dt);
                e.Text = e.Time + "  " + e.Name + "  " + Exact(e.Amount) + " " + e.Element.ToLowerInvariant() + (e.Crit ? " " + Loc.T("(critical)") : "") + (e.Mana ? " " + Loc.T("(mana)") : "");
                o.Add(e);
            }
            return o;
        }

        /// <summary>The history list (the server's order, newest first).</summary>
        public static List<DeathHistoryRow> HistoryRows(IList<object> list, int selected)
        {
            var o = new List<DeathHistoryRow>();
            foreach (object s in list)
            {
                if (!Has(s, "id")) continue;
                string sub;
                if (Has(s, "real") && Num(s, "real") == 0) sub = Json.Text(s, "mode", "") != "" ? Json.Text(s, "mode") : Loc.T("Defeat");
                else if (Has(s, "xl") && Num(s, "xl") > 0)
                {
                    sub = Loc.T("-{0} exp", Short(Num(s, "xl")));
                    if (Has(s, "ll") && Num(s, "ll") > 0) sub += Loc.T(", -{0} lvl", (int)Num(s, "ll"));
                }
                else sub = Has(s, "lvl") ? Loc.T("Level {0}", (int)Num(s, "lvl")) : "";
                o.Add(new DeathHistoryRow { Id = (int)Num(s, "id"), Title = Clock(Num(s, "at")), Sub = sub, Killer = DisplayName(Json.Text(s, "k", null), null), Selected = selected == (int)Num(s, "id") });
            }
            return o;
        }

        // ------------------------------------------------------------------------------------ death advice
        /// <summary>The server's tips worded, in rule order, at most TipsMax; an unknown tip is skipped.</summary>
        public static List<string> Tips(object recap)
        {
            var o = new List<string>();
            foreach (object t in Json.List(recap, "tips"))
            {
                if (o.Count >= TipsMax) break;
                if (!(t is Dictionary<string, object>)) continue;
                string k = Json.Text(t, "k", ""), text = null;
                if (k == "lvl" && Has(t, "d")) text = Loc.T("These monsters are {0} levels above you: Next Goals shows hunts for your level", (int)Math.Floor(Num(t, "d")));
                else if (k == "res") text = ResTip(Json.Text(t, "el", ""), Math.Max(0, (int)Math.Floor(Num(t, "r"))));
                else if (k == "pot") text = Loc.T("You used no potions: set up healing in the Helper (Auto setup)");
                else if (k == "heal" && Has(t, "s")) text = Loc.T("Your healing covered only {0}% of the damage: heal sooner or pull fewer monsters", (int)Math.Floor(Num(t, "s")));
                else if (k == "pack" && Has(t, "n")) text = Loc.T("{0} monsters hit you at once: pull fewer at a time", (int)Math.Floor(Num(t, "n")));
                if (text != null) o.Add(text);
            }
            return o;
        }

        /// <summary>The element keys the server gives a resistance tip for.</summary>
        public static readonly string[] ResElements = { "fire", "ice", "earth", "holy", "death", "energy", "physical" };

        static string ResTip(string el, int r)
        {
            switch (el)
            {
                case "fire": return Loc.T("Most damage was fire and your fire resistance is {0}%: look for fire resistance on gear or a ruby in jewellery", r);
                case "ice": return Loc.T("Most damage was ice and your ice resistance is {0}%: look for ice resistance on gear or a sapphire in jewellery", r);
                case "earth": return Loc.T("Most damage was earth and your earth resistance is {0}%: look for earth resistance on gear or an emerald in jewellery", r);
                case "holy": return Loc.T("Most damage was holy and your holy resistance is {0}%: look for holy resistance on gear or a diamond in jewellery", r);
                case "death": return Loc.T("Most damage was death and your death resistance is {0}%: look for death resistance on gear or an amethyst in armour", r);
                case "energy": return Loc.T("Most damage was energy and your energy resistance is {0}%: look for energy resistance on gear or a topaz in armour", r);
                case "physical": return Loc.T("Most damage was physical and your physical resistance is {0}%: look for physical resistance on gear or an onyx in armour", r);
                default: return null;
            }
        }
    }

    /// <summary>The protocol side: opcode 154, the history and the recap shown.</summary>
    public sealed class DeathRecap
    {
        public const byte Opcode = 154;

        readonly ExtOpcodes ext;
        public readonly List<object> History = new List<object>();
        /// <summary>The id of the recap shown (0: one sent without an id).</summary>
        public int Selected;
        /// <summary>The recap shown (the JSON tree), null when none.</summary>
        public object Current;
        /// <summary>The server sent a recap to open by itself (auto), or the history changed.</summary>
        public event Action AutoOpen = delegate { };
        public event Action Changed = delegate { };

        public DeathRecap(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, OnMessage);
        }

        public void Open(int id = 0)
        {
            ext.Send(Opcode, "open", id > 0 ? new Dictionary<string, object> { { "id", id } } : null);
        }

        public void Get(int id)
        {
            ext.Send(Opcode, "get", new Dictionary<string, object> { { "id", id } });
        }

        /// <summary>Picks a recap of the history: shows it as soon as the server sends it.</summary>
        public void Select(int id)
        {
            if (id == Selected) return;
            Selected = id;
            Get(id);
            Changed();
        }

        void OnMessage(ExtMessage m)
        {
            var d = m.Data;
            if (!(d is Dictionary<string, object>)) return;
            switch (m.Action)
            {
                case "history":
                    History.Clear();
                    History.AddRange(Json.List(d, "list"));
                    Selected = Json.Int(d, "sel");
                    Current = Json.Get(d, "recap") is Dictionary<string, object> r ? r : null;
                    Changed();
                    return;
                case "recap":
                {
                    var recap = Json.Get(d, "recap");
                    if (!(recap is Dictionary<string, object>)) return;
                    Current = recap;
                    Selected = Json.Int(d, "id");
                    if (Json.Bool(d, "auto")) AutoOpen();
                    Changed();
                    return;
                }
            }
        }

        public void Reset() { History.Clear(); Selected = 0; Current = null; }
    }
}
