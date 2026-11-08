// The DPS meter and combat log (O433 phase 5, track Q): a bar per skill (spell, rune, weapon attack, damage over time, proc, summon) with its total, per second and
// share; tabs Damage / Healing / Taken / Received; the current fight, the session or one of the last 10 fights; a party mode; a detail view (hits, crits, average,
// max, element split); export of a summary. A port of game_dpsmeter/dpsmath.lua (the pure part) and dpsmeter.lua (the protocol).
// The server counts and attributes everything (combatlog.lua) and pushes it on extended opcode 204 (JSON {action, data}):
//   server -> client  state {sel, segs, v, live, share, party?}
//   client -> server  open {seg, party, share} | close | seg {id} | party {on} | share {on} | reset
// Tests: Core.Tests/InfoTests.cs (mirrors dpsmath_test.lua).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public sealed class DpsTab { public string Key = "", Name = "", Short = "", Rate = "", Tip = ""; public int Idx; }

    public sealed class DpsRow
    {
        public string Key = "", Kind = "", Name = "";
        public object Icon;
        public double Total, Hits, Crits, Max, Over, Pct, Frac, Rate, Avg, CritPct;
    }

    public sealed class DpsElement { public string Key = "", Name = ""; public double Amount, Pct; }

    public sealed class DpsSegment { public string Id = "c", Text = ""; }

    public sealed class DpsPartyRow { public string Name = ""; public bool Self, Live; public double Value, Rate, Frac; }

    public sealed class DpsSettings
    {
        public bool Shown, Party, Share = true, Locked;
        public int W = DpsMath.DefaultW, H = DpsMath.DefaultH;
        public string Tab = "dmg", Seg = "c", DetailTab = "dmg";
        public int? X, Y;

        public string ToJson()
        {
            var d = new Dictionary<string, object>
            {
                { "shown", Shown }, { "party", Party }, { "share", Share }, { "locked", Locked }, { "w", W }, { "h", H }, { "tab", Tab }, { "seg", Seg }, { "detailTab", DetailTab },
            };
            if (X.HasValue && Y.HasValue) { d["x"] = X.Value; d["y"] = Y.Value; }
            return Json.Serialize(d);
        }
    }

    public static class DpsMath
    {
        public const string TextColor = "#d6c9ae", DimColor = "#8c8070", HealColor = "#3f9a4a";
        public const int DefaultW = 236, DefaultH = 200, MinW = 180, MinH = 110, MaxW = 600, MaxH = 700;

        public static readonly DpsTab[] Tabs =
        {
            new DpsTab { Key = "dmg", Idx = 1, Name = "Damage", Short = "Dmg", Rate = "DPS", Tip = "Damage you dealt, by skill" },
            new DpsTab { Key = "heal", Idx = 2, Name = "Healing", Short = "Heal", Rate = "HPS", Tip = "Healing you did, by skill" },
            new DpsTab { Key = "taken", Idx = 3, Name = "Taken", Short = "Taken", Rate = "DTPS", Tip = "Damage you took, by attacker" },
            new DpsTab { Key = "recv", Idx = 4, Name = "Received", Short = "Recv", Rate = "HPS", Tip = "Healing you received, by healer" },
        };

        public static DpsTab Tab(string key) { foreach (var t in Tabs) if (t.Key == key) return t; return Tabs[0]; }

        /// <summary>The bar colour by source kind (damage / healing / taken).</summary>
        public static readonly Dictionary<string, string> KindColors = new Dictionary<string, string>
        {
            { "s", "#b8452a" }, { "r", "#8e4fc4" }, { "w", "#a8843a" }, { "d", "#4f9a34" }, { "p", "#2f8fc0" }, { "x", "#c8402a" }, { "m", "#4fb88e" },
            { "i", "#c04a78" }, { "o", "#6b6258" }, { "c", "#9a1c14" }, { "u", "#c8a040" }, { "e", "#6b6258" }, { "k", "#8a6cc8" },
        };

        public static readonly Dictionary<string, string> ElementNames = new Dictionary<string, string>
        {
            { "physical", "Physical" }, { "fire", "Fire" }, { "earth", "Earth" }, { "energy", "Energy" }, { "ice", "Ice" }, { "holy", "Holy" }, { "death", "Death" },
            { "drown", "Drown" }, { "lifedrain", "Life drain" }, { "manadrain", "Mana drain" },
        };

        /// <summary>A keystone note: how much a keystone changed a hit the other rows already count.</summary>
        public static bool IsNote(string kind) => kind == "k";

        public static string BarColor(string kind, int tabIdx)
        {
            if (tabIdx == 2 || tabIdx == 4) return kind == "u" ? KindColors["u"] : HealColor;
            string c;
            return KindColors.TryGetValue(kind ?? "", out c) ? c : KindColors["o"];
        }

        static double Clamp(double v, double lo, double hi) => v < lo ? lo : v > hi ? hi : v;

        // ------------------------------------------------------------------------------------ settings
        public static DpsSettings Sanitize(object node)
        {
            var s = new DpsSettings();
            if (!(node is Dictionary<string, object>)) return s;
            s.Shown = Json.Get(node, "shown") is bool b1 ? b1 : false;
            s.Party = Json.Get(node, "party") is bool b2 ? b2 : false;
            s.Share = Json.Get(node, "share") is bool b3 ? b3 : true;
            s.Locked = Json.Get(node, "locked") is bool b4 ? b4 : false;
            s.W = (int)Math.Floor(Clamp(Json.Get(node, "w") is double w ? w : DefaultW, MinW, MaxW));
            s.H = (int)Math.Floor(Clamp(Json.Get(node, "h") is double h ? h : DefaultH, MinH, MaxH));
            s.Tab = Tab(Json.Text(node, "tab")).Key;
            s.DetailTab = Tab(Json.Text(node, "detailTab")).Key;
            s.Seg = Json.Text(node, "seg") == "s" ? "s" : "c";   // a fight id is not kept over a relog
            if (Json.Get(node, "x") is double x && Json.Get(node, "y") is double y) { s.X = (int)Math.Floor(x); s.Y = (int)Math.Floor(y); }
            return s;
        }

        public static string PrefsKey(string character) => "chaos.dpsmeter." + (string.IsNullOrEmpty(character) ? "-" : character.ToLowerInvariant());

        public static void ClampSize(ref int w, ref int h)
        {
            w = (int)Math.Floor(Clamp(w, MinW, MaxW));
            h = (int)Math.Floor(Clamp(h, MinH, MaxH));
        }

        // ------------------------------------------------------------------------------------ formats
        /// <summary>1234 is 1.2k, 15000 is 15k, 2.5M, 4.2B, 7.3T; the units of client_chaos_numbers; a decimal below 100, rounded down.</summary>
        public static string Short(double n)
        {
            string sign = n < 0 ? "-" : "";
            n = Math.Abs(n);
            Func<double, string, string> fmt = (v, suffix) =>
            {
                if (v >= 100) return sign + ((long)Math.Floor(v)).ToString(CultureInfo.InvariantCulture) + suffix;
                string s = (Math.Floor(v * 10) / 10).ToString("0.0", CultureInfo.InvariantCulture);
                if (s.EndsWith(".0")) s = s.Substring(0, s.Length - 2);
                return sign + s + suffix;
            };
            if (n >= 1e12) return fmt(n / 1e12, "T");
            if (n >= 1e9) return fmt(n / 1e9, "B");
            if (n >= 1e6) return fmt(n / 1e6, "M");
            if (n >= 1e3) return fmt(n / 1e3, "k");
            return sign + ((long)Math.Floor(n)).ToString(CultureInfo.InvariantCulture);
        }

        public static string Exact(double n) => ShortNumbers.Exact(Math.Floor(n));

        /// <summary>ms to "0:42", "12:05", "1:02:05".</summary>
        public static string Duration(double ms)
        {
            long s = (long)Math.Max(0, Math.Floor(ms / 1000));
            long h = s / 3600, m = s / 60 % 60;
            s %= 60;
            return h > 0 ? string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}:{2:00}", h, m, s) : string.Format(CultureInfo.InvariantCulture, "{0}:{1:00}", m, s);
        }

        public static double PerSecond(double value, double ms) => ms <= 0 ? 0 : Math.Floor(value * 1000 / ms);

        public static double Percent(double part, double total) => total <= 0 ? 0 : Math.Floor(part * 1000 / total + 0.5) / 10;

        static string Pct(double p) => p.ToString("0.#", CultureInfo.InvariantCulture);

        // ------------------------------------------------------------------------------------ rows
        static double Num(object o) => o is double d && !double.IsNaN(d) && !double.IsInfinity(d) ? d : 0;

        static List<object> Rs(object tab) => tab is Dictionary<string, object> ? Json.List(tab, "r") : new List<object>();

        /// <summary>The rows of tab idx (1..4) of a segment view: share, bar length (the top row is 1), per second, average, crit rate. total is the tab's total.</summary>
        public static List<DpsRow> Rows(object view, int idx, out double total)
        {
            var o = new List<DpsRow>();
            total = 0;
            var tabs = Json.List(view, "t");
            if (idx < 1 || idx > tabs.Count || !(tabs[idx - 1] is Dictionary<string, object>)) return o;
            object tab = tabs[idx - 1];
            total = Json.Number(tab, "tot");
            double dur = Json.Number(view, "dur"), top = 0;
            var rs = Rs(tab);
            foreach (object r in rs) { var l = r as List<object>; if (l != null && l.Count > 4 && Num(l[4]) > top) top = Num(l[4]); }
            foreach (object r in rs)
            {
                var l = r as List<object>;
                if (l == null || l.Count < 5) continue;
                double v = Num(l[4]), hits = l.Count > 5 ? Num(l[5]) : 0, crits = l.Count > 6 ? Num(l[6]) : 0;
                o.Add(new DpsRow
                {
                    Key = l[0] as string ?? "", Kind = l[1] as string ?? "", Name = l[2] as string ?? "?", Icon = l[3], Total = v, Hits = hits, Crits = crits,
                    Max = l.Count > 7 ? Num(l[7]) : 0, Over = l.Count > 8 ? Num(l[8]) : 0, Pct = Percent(v, total), Frac = top > 0 ? v / top : 0, Rate = PerSecond(v, dur),
                    Avg = hits > 0 ? Math.Floor(v / hits + 0.5) : 0, CritPct = hits > 0 ? Math.Floor(crits * 100 / hits + 0.5) : 0,
                });
            }
            return o;
        }

        /// <summary>The elements of a tab, largest first.</summary>
        public static List<DpsElement> Elements(object view, int idx)
        {
            var o = new List<DpsElement>();
            var tabs = Json.List(view, "t");
            if (idx < 1 || idx > tabs.Count) return o;
            var el = Json.Get(tabs[idx - 1], "el") as Dictionary<string, object>;
            if (el == null) return o;
            double total = 0;
            foreach (var kv in el) total += Num(kv.Value);
            foreach (var kv in el)
            {
                string name;
                o.Add(new DpsElement { Key = kv.Key, Name = ElementNames.TryGetValue(kv.Key, out name) ? name : kv.Key, Amount = Num(kv.Value) });
            }
            o.Sort((a, b) => a.Amount != b.Amount ? b.Amount.CompareTo(a.Amount) : string.CompareOrdinal(a.Key, b.Key));
            foreach (var e in o) e.Pct = Percent(e.Amount, total);
            return o;
        }

        // ------------------------------------------------------------------------------------ segments
        static string IdText(object id) => id is double d ? ((long)d).ToString(CultureInfo.InvariantCulture) : id as string ?? "";

        /// <summary>The drop-down entries: the current fight, the session and the finished fights (the running one is the current fight).</summary>
        public static List<DpsSegment> SegmentOptions(object segs)
        {
            var o = new List<DpsSegment> { new DpsSegment { Id = "c", Text = Loc.T("Current fight") } };
            var list = segs as List<object>;
            if (list == null) return o;
            foreach (object s in list)
            {
                var l = s as List<object>;
                if (l == null || l.Count < 3) continue;
                string id = IdText(l[0]);
                string label = l[1] as string ?? "";
                bool live = l.Count > 6 && Num(l[6]) == 1, boss = l.Count > 7 && Num(l[7]) == 1;
                if (id == "s") o.Add(new DpsSegment { Id = "s", Text = Loc.T("Session") });
                else if (!live) o.Add(new DpsSegment { Id = id, Text = "#" + id + " " + (boss ? "[" + Loc.T("Boss") + "] " : "") + label + " (" + Duration(Num(l[2])) + ")" });
            }
            return o;
        }

        public static string SegmentKey(IList<DpsSegment> options)
        {
            var sb = new StringBuilder();
            foreach (var o in options) sb.Append(o.Id).Append('=').Append(o.Text).Append('|');
            return sb.ToString();
        }

        /// <summary>The title line of the panel: "label  0:42" (live: "label  0:42 *").</summary>
        public static string Title(object view)
        {
            if (!(view is Dictionary<string, object>)) return Loc.T("No fight yet");
            object id = Json.Get(view, "id");
            string label = IdText(id) == "s" ? Loc.T("Session") : (Json.Text(view, "label").Length > 0 ? Json.Text(view, "label") : Loc.T("Fight"));
            return label + "  " + Duration(Json.Number(view, "dur")) + (Json.Number(view, "live") == 1 ? " *" : "");
        }

        // ------------------------------------------------------------------------------------ party
        /// <summary>The party members' rows for tab idx, best first. session: the session numbers, else the current (or last) fight.</summary>
        public static List<DpsPartyRow> PartyRows(object party, int idx, bool session)
        {
            var o = new List<DpsPartyRow>();
            string field = idx == 1 ? "d" : idx == 3 ? "t" : idx == 2 || idx == 4 ? "h" : "d";
            var list = party as List<object>;
            if (list == null) return o;
            foreach (object m in list)
            {
                double value = Json.Number(m, (session ? "s" : "f") + field), dur = Json.Number(m, session ? "sdur" : "fdur");
                o.Add(new DpsPartyRow { Name = Json.Text(m, "n", "?"), Self = Json.Number(m, "self") == 1, Value = value, Rate = PerSecond(value, dur), Live = Json.Number(m, "live") == 1 });
            }
            o.Sort((a, b) => a.Rate != b.Rate ? b.Rate.CompareTo(a.Rate) : string.CompareOrdinal(a.Name, b.Name));
            double top = o.Count > 0 ? o[0].Rate : 0;
            foreach (var r in o) r.Frac = top > 0 ? r.Rate / top : 0;
            return o;
        }

        // ------------------------------------------------------------------------------------ export (local only: the clipboard and the chat input line)
        static DpsTab TabOf(int idx) { foreach (var t in Tabs) if (t.Idx == idx) return t; return Tabs[0]; }

        static string ViewLabel(object view) => IdText(Json.Get(view, "id")) == "s" ? Loc.T("Session") : (Json.Text(view, "label").Length > 0 ? Json.Text(view, "label") : "Fight");

        /// <summary>Several lines for the clipboard.</summary>
        public static string Summary(object view, int idx, int maxRows = 15)
        {
            if (!(view is Dictionary<string, object>)) return "";
            var t = TabOf(idx);
            double total;
            var rows = Rows(view, idx, out total);
            double dur = Json.Number(view, "dur");
            var lines = new List<string>
            {
                string.Format(CultureInfo.InvariantCulture, "DPS Meter - {0} ({1})", ViewLabel(view), Duration(dur)),
                string.Format(CultureInfo.InvariantCulture, "{0}: {1} ({2} {3})", t.Name, Exact(total), Exact(PerSecond(total, dur)), t.Rate),
            };
            for (int i = 0; i < rows.Count && i < maxRows; i++)
            {
                var r = rows[i];
                lines.Add(string.Format(CultureInfo.InvariantCulture, "{0,2}. {1}  {2}  {3}%  {4}/s  hits {5}  crit {6}%  avg {7}  max {8}", i + 1, r.Name, Exact(r.Total), Pct(r.Pct),
                    Exact(r.Rate), (long)r.Hits, (long)r.CritPct, Exact(r.Avg), Exact(r.Max)));
            }
            return string.Join("\n", lines);
        }

        /// <summary>One line for the chat input (the player sends it, or not): at most maxLen characters.</summary>
        public static string ChatLine(object view, int idx, int maxLen = 240)
        {
            if (!(view is Dictionary<string, object>)) return "";
            var t = TabOf(idx);
            double total;
            var rows = Rows(view, idx, out total);
            double dur = Json.Number(view, "dur");
            string line = string.Format(CultureInfo.InvariantCulture, "[{0}] {1} {2}: {3}, {4} {5}", t.Name, ViewLabel(view), Duration(dur), Short(total), Short(PerSecond(total, dur)), t.Rate);
            foreach (var r in rows)
            {
                string part = " | " + r.Name + " " + Pct(r.Pct) + "%";
                if (line.Length + part.Length > maxLen) break;
                line += part;
            }
            return line;
        }
    }

    /// <summary>The meter's connection to the server (opcode 204): the last state and what the window asks for.</summary>
    public sealed class DpsMeter
    {
        public const byte Opcode = 204;
        readonly ExtOpcodes ext;
        public DpsSettings Settings = new DpsSettings();
        /// <summary>The last `state` data (a Json dictionary), null before the first one.</summary>
        public object State;
        public string SegSel = "c";
        public bool Watching;
        public int Updates;

        public DpsMeter(ExtOpcodes e)
        {
            ext = e;
            ext.On(Opcode, m => { if (m.Action == "state") Apply(m.Data); });
        }

        public object View => State != null ? Json.Get(State, "v") : null;
        public object Segs => State != null ? Json.Get(State, "segs") : null;
        public object Party => State != null ? Json.Get(State, "party") : null;
        public bool Live => State != null && Json.Number(State, "live") == 1;

        public void Apply(object data)
        {
            if (!(data is Dictionary<string, object>)) return;
            State = data;
            object sel = Json.Get(data, "sel");
            if (sel != null) SegSel = sel is double d ? ((long)d).ToString(CultureInfo.InvariantCulture) : sel as string ?? SegSel;
            Updates++;
        }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        static object SegId(string id)
        {
            long n;
            return long.TryParse(id, NumberStyles.None, CultureInfo.InvariantCulture, out n) ? (object)n : id;
        }

        /// <summary>The window is open: the server starts pushing the state.</summary>
        public void Start()
        {
            if (Watching) return;
            Watching = true;
            Send("open", new Dictionary<string, object> { { "seg", SegId(SegSel) }, { "party", Settings.Party }, { "share", Settings.Share } });
        }

        public void Stop() { if (Watching) { Watching = false; Send("close"); } }

        public void Choose(string id)
        {
            if (id == null || id == SegSel) return;
            SegSel = id;
            if (id == "c" || id == "s") Settings.Seg = id;
            Send("seg", new Dictionary<string, object> { { "id", SegId(id) } });
        }

        public void SetParty(bool on) { Settings.Party = on; Send("party", new Dictionary<string, object> { { "on", on } }); }
        public void SetShare(bool on) { Settings.Share = on; Send("share", new Dictionary<string, object> { { "on", on } }); }
        public void Reset() { Send("reset"); }

        /// <summary>A new session: forget the old state (the settings stay).</summary>
        public void Forget() { State = null; Watching = false; SegSel = Settings.Seg; }
    }
}
