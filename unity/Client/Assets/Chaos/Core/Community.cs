// Community modules, part 1 (O433 phase 5, track S): the window models of the main client's game_admin (opcode 120), game_bossspawns (217),
// game_chaossurvey (122), game_nemesis (163), game_referral (220). They are SocialPanels (Core/Social.cs): messages in through ExtOpcodes, rows out,
// requests back through ExtOpcodes. Rules and texts follow the main client's *view.lua / *logic.lua next to each module.
// Part 2 is Core/CommunityGoal.cs (community goal, chronicle, mentor, patch notes), part 3 Core/CommunityExtras.cs.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    /// <summary>Numbers, times and texts the community panels share.</summary>
    public static class Cm
    {
        public static readonly string[] Months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

        /// <summary>1234567890 (epoch seconds) -> "13 Feb 2009"; "" for 0 or less.</summary>
        public static string DateText(double epoch)
        {
            if (epoch <= 0) return "";
            var d = DateTimeOffset.FromUnixTimeSeconds((long)epoch).UtcDateTime;
            return d.Day.ToString(CultureInfo.InvariantCulture) + " " + Months[d.Month - 1] + " " + d.Year.ToString(CultureInfo.InvariantCulture);
        }

        public static string IsoDate(double epoch)
        {
            if (epoch <= 0) return "?";
            return DateTimeOffset.FromUnixTimeSeconds((long)epoch).UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        /// <summary>93784 -> "1d 2h", 4980 -> "1h 23m", 125 -> "2m 05s", 9 -> "9s" (the boss spawn list).</summary>
        public static string Countdown(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60, r = s % 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            if (m > 0) return m + "m " + r.ToString("00", CultureInfo.InvariantCulture) + "s";
            return r + "s";
        }

        /// <summary>The coarser countdown of the community goal: 93784 -> "1d 2h", 4980 -> "1h 23m", 125 -> "2m", under a minute "1m".</summary>
        public static string CountdownMin(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60;
            if (d > 0) return d + "d " + h + "h";
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            return Math.Max(1, m) + "m";
        }

        public static string Ago(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            if (s < 60) return Loc.T("just now");
            if (s < 3600) return Loc.T("{0}m ago", s / 60);
            if (s < 86400) return Loc.T("{0}h ago", s / 3600);
            return Loc.T("{0}d ago", s / 86400);
        }

        public static string Str(object o, string key, string fallback = "") => Json.Text(o, key, fallback);
        public static bool IsMap(object o) => o is Dictionary<string, object>;
        public static List<object> Rows(object o, string key) => SFmt.Rows(o, key);
    }

    /// <summary>A SocialPanel that talks on one extended opcode: JSON {action, data} in, the same out. Handle sees the data (an empty map when none).</summary>
    public abstract class CommunityPanel : SocialPanel
    {
        protected readonly ExtOpcodes Ext;
        public readonly byte Op;
        public Func<double> Clock = () => 0;

        protected CommunityPanel(ExtOpcodes e, byte op)
        {
            Ext = e;
            Op = op;
            e.On(op, OnMessage);
        }

        void OnMessage(ExtMessage m)
        {
            Handle(m.Action ?? "", m.Data ?? new Dictionary<string, object>());
            Changed();
        }

        protected abstract void Handle(string action, object data);

        public bool Send(string action, object data = null) => Ext.Send(Op, action, data ?? new Dictionary<string, object>());
        protected double NowMs => Clock();
    }

    // ====================================================================================================== game_admin (120)
    /// <summary>The server driven admin panel. The server sends the catalog only to staff accounts and re-checks every action, so a player's client never opens it
    /// (same rule as the main client: the window exists once a catalog has arrived). Catalog: {categories [{id, label, actions [{id, name, description, dangerous, confirm,
    /// params [{name, label, type (text int bool select), required, default, hint, options}]}]}]}; client -> server: catalog | run {rid, id, params}; server -> client: catalog | result {rid, id, ok, message, lines}.</summary>
    public sealed class AdminPanel : CommunityPanel
    {
        public const byte Opcode = 120;
        public const int MaxResultLines = 300;
        public const double ConfirmMs = 4000, UnlockMs = 3000;
        public const double CatalogDelayMs = 600;

        public sealed class Param { public string Name = "", Label = "", Type = "text", Hint = ""; public bool Required; public object Default; public List<KeyValuePair<string, object>> Options = new List<KeyValuePair<string, object>>(); }
        public sealed class Act { public string Id = "", Name = "", Description = "", Category = ""; public bool Dangerous, Confirm; public List<Param> Params = new List<Param>(); }
        public sealed class Cat { public string Id = "", Label = ""; public List<Act> Actions = new List<Act>(); }
        public sealed class Line { public string Text = "", Tone = ""; }

        public readonly List<Cat> Categories = new List<Cat>();
        public bool HasCatalog;
        public string Category = "*";
        public Act Selected;
        public readonly List<Line> Results = new List<Line>();
        readonly Dictionary<int, string> pending = new Dictionary<int, string>();
        int nextRid = 1;
        public bool Armed, Busy, Asked;
        double armedAt, busyAt;

        public AdminPanel(ExtOpcodes e) : base(e, Opcode) { }

        /// <summary>Ask for the catalog shortly after the login. A player never gets an answer.</summary>
        public void Poll(double now, bool inGame, double enteredAt)
        {
            if (inGame && !Asked && enteredAt >= 0 && now - enteredAt > CatalogDelayMs) { Asked = true; Send("catalog"); }
            if (Armed && now - armedAt > ConfirmMs) Armed = false;
            if (Busy && now - busyAt > UnlockMs) Busy = false;
        }

        public override void Show() { if (!HasCatalog) return; Visible = true; Send("catalog"); }
        public override void Clear() { base.Clear(); Categories.Clear(); HasCatalog = false; Category = "*"; Selected = null; Results.Clear(); pending.Clear(); Armed = Busy = Asked = false; }

        protected override void Handle(string action, object data)
        {
            if (action == "catalog") OnCatalog(data);
            else if (action == "result") OnResult(data);
        }

        public static List<Cat> CleanCatalog(object data)
        {
            var cats = new List<Cat>();
            foreach (var c in SFmt.Rows(data, "categories"))
            {
                if (Json.Get(c, "id") == null) continue;
                var cat = new Cat { Id = Cm.Str(c, "id"), Label = Cm.Str(c, "label", Cm.Str(c, "id")) };
                foreach (var a in SFmt.Rows(c, "actions"))
                {
                    if (Json.Get(a, "id") == null) continue;
                    var act = new Act
                    {
                        Id = Cm.Str(a, "id"), Name = Cm.Str(a, "name", Cm.Str(a, "id")), Description = Cm.Str(a, "description"), Category = cat.Id,
                        Dangerous = Json.Truthy(a, "dangerous"), Confirm = Json.Truthy(a, "confirm"),
                    };
                    foreach (var p in SFmt.Rows(a, "params"))
                    {
                        var pr = new Param { Name = Cm.Str(p, "name"), Label = Cm.Str(p, "label", Cm.Str(p, "name")), Type = Cm.Str(p, "type", "text"), Hint = Cm.Str(p, "hint"), Required = Json.Truthy(p, "required"), Default = Json.Get(p, "default") };
                        foreach (object o in Json.List(p, "options"))
                        {
                            if (o is Dictionary<string, object>) pr.Options.Add(new KeyValuePair<string, object>(Cm.Str(o, "label", Cm.Str(o, "value")), Json.Get(o, "value")));
                            else if (o != null) pr.Options.Add(new KeyValuePair<string, object>(DefaultText(o), o));
                        }
                        if (pr.Name.Length > 0) act.Params.Add(pr);
                    }
                    cat.Actions.Add(act);
                }
                cats.Add(cat);
            }
            return cats;
        }

        void OnCatalog(object data)
        {
            if (!(Json.Get(data, "categories") is List<object>)) return;
            Categories.Clear();
            Categories.AddRange(CleanCatalog(data));
            HasCatalog = true;
            if (Category != "*" && Categories.Find(c => c.Id == Category) == null) Category = "*";
            if (Selected != null) Selected = Find(Selected.Id);
        }

        public Act Find(string id) { foreach (var c in Categories) foreach (var a in c.Actions) if (a.Id == id) return a; return null; }

        void OnResult(object data)
        {
            int rid = Json.Int(data, "rid");
            string name;
            if (!pending.TryGetValue(rid, out name)) name = Cm.Str(data, "id", "?");
            pending.Remove(rid);
            Busy = false;
            AddResult("[" + name + "] " + Cm.Str(data, "message"), Json.Truthy(data, "ok") ? "good" : "bad");
            foreach (object l in Json.List(data, "lines")) AddResult("  " + (l is string s ? s : Json.Serialize(l)), "text");
        }

        void AddResult(string text, string tone)
        {
            Results.Add(new Line { Text = text, Tone = tone });
            while (Results.Count > MaxResultLines) Results.RemoveAt(0);
        }

        public void Select(Act a)
        {
            Selected = a; Armed = false;
            var drop = new List<string>();
            foreach (var k in Form.Keys) if (k.StartsWith("p_", StringComparison.Ordinal)) drop.Add(k);
            foreach (var k in drop) Form.Remove(k);
            Changed();
        }

        public static bool Matches(Act a, string filter)
        {
            if (string.IsNullOrEmpty(filter)) return true;
            string hay = (a.Name + " " + a.Id + " " + a.Description).ToLowerInvariant();
            return hay.Contains(filter.ToLowerInvariant());
        }

        /// <summary>The parameters as the server reads them, or null with the label of the first required field that is empty.</summary>
        public Dictionary<string, object> Collect(Act a, out string missing)
        {
            missing = null;
            var d = new Dictionary<string, object>();
            foreach (var p in a.Params)
            {
                string key = "p_" + p.Name;
                object value;
                if (p.Type == "bool") value = Form.TryGetValue(key, out var b) ? b == "1" : Json.Truthy(p.Default);
                else if (p.Type == "select")
                {
                    int idx = Form.ContainsKey(key) ? Index(key) : DefaultIndex(p);
                    value = idx >= 0 && idx < p.Options.Count ? p.Options[idx].Value : null;
                }
                else
                {
                    string t = Form.TryGetValue(key, out var tx) ? tx : (p.Default != null ? DefaultText(p.Default) : "");
                    value = t;
                    if (p.Type == "int" && t.Length > 0 && double.TryParse(t, NumberStyles.Float, CultureInfo.InvariantCulture, out double n)) value = n;
                }
                if (p.Required && (value == null || (value is string s && s.Length == 0))) { missing = p.Label; return null; }
                d[p.Name] = value;
            }
            return d;
        }

        public static string DefaultText(object o) => o is double d ? SFmt.Pct(d) : (o ?? "").ToString();

        public static int DefaultIndex(Param p)
        {
            if (p.Default == null) return 0;
            for (int i = 0; i < p.Options.Count; i++) if (DefaultText(p.Options[i].Value) == DefaultText(p.Default)) return i;
            return 0;
        }

        /// <summary>The Run button: a "confirm" action asks for a second press within ConfirmMs.</summary>
        public void Run()
        {
            var a = Selected;
            if (a == null) return;
            var ps = Collect(a, out string missing);
            if (ps == null) { AddResult("[" + a.Name + "] " + Loc.T("missing required field") + ": " + missing, "bad"); Changed(); return; }
            if (a.Confirm && !Armed) { Armed = true; armedAt = NowMs; Changed(); return; }
            Armed = false;
            int rid = nextRid++;
            pending[rid] = a.Name;
            if (Send("run", SFmt.Map("rid", (double)rid, "id", a.Id, "params", ps)))
            {
                Busy = true; busyAt = NowMs;
                AddResult("> " + a.Name, "dim");
            }
            Changed();
        }

        List<string> CategoryNames()
        {
            var n = new List<string> { Loc.T("All actions") };
            foreach (var c in Categories) n.Add(c.Label);
            return n;
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Admin Panel");
            Header2 = Selected != null ? Selected.Name + (Selected.Dangerous ? Loc.T("  (dangerous)") : "") : Loc.T("Select an action");
            if (!HasCatalog) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            l.Input(Loc.T("Search"), "filter", Loc.T("filter actions"));
            l.Combo(Loc.T("Category"), "cat", CategoryNames());
            int pick = Index("cat");
            string cat = pick <= 0 || pick > Categories.Count ? "*" : Categories[pick - 1].Id;
            Category = cat;
            string filter = Text("filter");
            if (Selected == null)
            {
                int shown = 0;
                foreach (var c in Categories)
                {
                    if (cat != "*" && cat != c.Id) continue;
                    foreach (var a in c.Actions)
                    {
                        if (!Matches(a, filter)) continue;
                        var act = a;
                        var row = l.Row(a.Name, a.Dangerous ? Loc.T("dangerous") : "", a.Dangerous ? "bad" : "text");
                        row.Tip = a.Description;
                        if (a.Description.Length > 0) row.Sub = a.Description.Length > 90 ? a.Description.Substring(0, 90) : a.Description;
                        row.Btn(Loc.T("Open"), true, () => Select(act));
                        if (++shown > 400) break;
                    }
                }
                if (shown == 0) l.Text(Loc.T("No action matches."), "dim");
            }
            else
            {
                if (Selected.Description.Length > 0) l.Text(Selected.Description, "dim");
                foreach (var p in Selected.Params)
                {
                    string key = "p_" + p.Name;
                    string label = p.Label + (p.Required ? " *" : "");
                    if (p.Type == "bool")
                    {
                        if (!Form.ContainsKey(key)) Form[key] = Json.Truthy(p.Default) ? "1" : "0";
                        l.Combo(label, key, new[] { Loc.T("No"), Loc.T("Yes") });
                    }
                    else if (p.Type == "select")
                    {
                        if (!Form.ContainsKey(key)) Form[key] = DefaultIndex(p).ToString(CultureInfo.InvariantCulture);
                        var names = new List<string>();
                        foreach (var o in p.Options) names.Add(o.Key);
                        l.Combo(label, key, names);
                    }
                    else
                    {
                        if (!Form.ContainsKey(key) && p.Default != null) Form[key] = DefaultText(p.Default);
                        l.Input(label, key, p.Hint);
                    }
                }
                var r = l.Row(Armed ? Loc.T("Click again to confirm") : Loc.T("Run"), "", Armed ? "warn" : "text");
                r.Btn(Armed ? Loc.T("Click again to confirm") : Loc.T("Run"), !Busy, Run);
                r.Btn(Loc.T("Back"), true, () => { Selected = null; Armed = false; Changed(); });
            }
            if (Results.Count > 0)
            {
                l.Section(Loc.T("Results"));
                for (int i = Results.Count - 1; i >= 0 && i >= Results.Count - 60; i--) l.Text(Results[i].Text, Results[i].Tone);
            }
            return l.Rows;
        }
    }

    // ====================================================================================================== game_bossspawns (217)
    /// <summary>Boss Spawns: every boss by category, where it is and when it comes back. client -> server: open | refresh | pocketEnter {k}; server -> client: list {now, refresh,
    /// cats [{k, n, c, t}], rows [{k, c, n, loc, p, lv, o, st, in, at, tx, ago, by, kills, alive, party, pl, ln, sh}]} | pocket {bosses {key {l, m, b, lv, ok}}, reset, inside} |
    /// pocketError {text} | npc {}. Times are seconds counted from the moment the list arrived.</summary>
    public sealed class BossSpawnsPanel : CommunityPanel
    {
        public const byte Opcode = 217;
        public object Data, Pocket;
        public double ReceivedAt, PocketAt, AskedAt, MsgAt;
        public string PocketMsg = "";
        public readonly HashSet<string> Collapsed = new HashSet<string>();

        public BossSpawnsPanel(ExtOpcodes e) : base(e, Opcode) { }

        public double Elapsed => Math.Max(0, (NowMs - ReceivedAt) / 1000);

        public override void Show() { Visible = true; AskedAt = NowMs; Send("open"); }
        public override void Clear() { base.Clear(); Data = Pocket = null; PocketMsg = ""; Collapsed.Clear(); }

        /// <summary>While the window is open: asks the list again once the refresh period has passed.</summary>
        public void Poll(double now)
        {
            if (!Visible || Data == null) return;
            double period = Json.Number(Data, "refresh", 30) * 1000;
            if (now - ReceivedAt >= period && now - AskedAt >= period) { AskedAt = now; Send("refresh"); }
        }

        protected override void Handle(string action, object data)
        {
            switch (action)
            {
                case "list": Data = data; ReceivedAt = NowMs; break;
                case "pocket": Pocket = data; PocketAt = NowMs; break;
                case "npc": if (!Visible) Show(); break;
                case "pocketError":
                    if (Json.Text(data, "text").Length > 0) { PocketMsg = Json.Text(data, "text"); MsgAt = NowMs; }
                    break;
            }
        }

        // ---- pure rules (bossspawnsview.lua)
        public static double Left(double sent, double receivedAt, double now) => Math.Max(0, sent - Math.Max(0, now - receivedAt));

        public static string StatusOf(object row, double elapsed, out string tone)
        {
            string st = Json.Text(row, "st");
            bool hasIn = Json.Get(row, "in") != null;
            double left = hasIn ? Math.Max(0, Json.Number(row, "in") - elapsed) : 0;
            switch (st)
            {
                case "alive": { int n = Json.Int(row, "alive"); tone = "#6fd86f"; return n > 1 ? Loc.T("Alive ({0})", n) : Loc.T("Alive"); }
                case "respawn":
                    if (hasIn && left > 0) { tone = "#f6cf72"; return Loc.T("Respawns in {0}", Cm.Countdown(left)); }
                    tone = "#e8a040"; return Loc.T("Respawn due");
                case "due": tone = "#e8a040"; return Loc.T("Respawn due");
                case "scheduled":
                    if (hasIn && left > 0) { tone = "#7fb8e8"; return Loc.T("In {0}", Cm.Countdown(left)); }
                    tone = "#6fd86f"; return Loc.T("Starting");
                case "random": tone = "#b98ae8"; return Loc.T("Random");
                case "ondemand": tone = "#c8b890"; return Loc.T("On demand");
                case "cooldown":
                    if (hasIn && left > 0) { tone = "#e05a3a"; return Loc.T("Your cooldown {0}", Cm.Countdown(left)); }
                    tone = "#6fd86f"; return Loc.T("Ready");
            }
            tone = "#8c8070";
            return Loc.T("Not seen yet");
        }

        public static string StatusSub(object row, double elapsed)
        {
            string st = Json.Text(row, "st");
            if (Json.Get(row, "at") != null && (st == "scheduled" || st == "respawn")) return Json.Text(row, "at");
            if (Json.Get(row, "ago") != null)
            {
                string text = Loc.T("Slain {0}", Cm.Ago(Json.Number(row, "ago") + elapsed));
                if (Json.Get(row, "by") != null) text += Loc.T(" by {0}", Json.Text(row, "by"));
                return text;
            }
            if (st == "ondemand" || st == "cooldown" || st == "random") return Json.Text(row, "sh", Json.Text(row, "tx"));
            return "";
        }

        public static string LevelText(object row)
        {
            var parts = new List<string>();
            if (Json.Number(row, "lv") > 0) parts.Add(Loc.T("Level {0}+", Json.Int(row, "lv")));
            else if (Json.Number(row, "pl") > 0) parts.Add(Loc.T("Pocket: level {0}+", Json.Int(row, "pl")));
            if (Json.Number(row, "party") > 1) parts.Add(Loc.T("party of {0}", Json.Int(row, "party")));
            return string.Join(", ", parts);
        }

        public static string Coords(object p) => Cm.IsMap(p) && Json.Get(p, "x") is double ? string.Format(CultureInfo.InvariantCulture, "{0}, {1}, {2}", Json.Int(p, "x"), Json.Int(p, "y"), Json.Int(p, "z", 7)) : "";

        public static string Where(object row) { string c = Coords(Json.Get(row, "p")); return c.Length > 0 ? c : Json.Text(row, "ln"); }

        public static string Tooltip(object row, double elapsed)
        {
            var lines = new List<string> { Json.Text(row, "n", "?") };
            if (Json.Text(row, "tx").Length > 0) lines.Add(Json.Text(row, "tx"));
            if (Json.Get(row, "at") != null) lines.Add(Loc.T("Next: {0}", Json.Text(row, "at")));
            if (Json.Get(row, "ago") != null)
            {
                string line = Loc.T("Last kill: {0}", Cm.Ago(Json.Number(row, "ago") + elapsed));
                if (Json.Get(row, "by") != null) line += Loc.T(" by {0}", Json.Text(row, "by"));
                if (Json.Number(row, "kills") > 0) line += Loc.T(" ({0} kills)", Json.Int(row, "kills"));
                lines.Add(line);
            }
            string c = Coords(Json.Get(row, "p"));
            if (c.Length > 0) lines.Add(Loc.T("Position: {0}", c));
            return string.Join("\n", lines);
        }

        public static bool Matches(object row, string filter)
        {
            if (string.IsNullOrEmpty(filter)) return true;
            string f = filter.ToLowerInvariant();
            return Json.Text(row, "n").ToLowerInvariant().Contains(f) || Json.Text(row, "loc").ToLowerInvariant().Contains(f);
        }

        public sealed class Group { public object Cat; public List<object> Rows = new List<object>(); public int Total; }

        public static List<Group> GroupRows(object data, string filter)
        {
            var result = new List<Group>();
            var by = new Dictionary<string, Group>();
            foreach (var c in SFmt.Rows(data, "cats"))
            {
                string k = Json.Text(c, "k");
                if (k.Length == 0) continue;
                var g = new Group { Cat = c };
                result.Add(g); by[k] = g;
            }
            foreach (var r in SFmt.Rows(data, "rows"))
            {
                if (!by.TryGetValue(Json.Text(r, "c"), out var g)) continue;
                g.Total++;
                if (Matches(r, filter)) g.Rows.Add(r);
            }
            result.RemoveAll(g => g.Rows.Count == 0);
            return result;
        }

        /// <summary>The Pocket button of a row: false when the boss has no pocket, else its text, whether it can be pressed and its tooltip.</summary>
        public static bool PocketOf(object row, object pocket, double elapsed, out string text, out bool enabled, out string tip)
        {
            text = tip = ""; enabled = false;
            var bosses = Json.Get(pocket, "bosses");
            if (!Cm.IsMap(row) || !Cm.IsMap(bosses)) return false;
            var p = Json.Get(bosses, Json.Text(row, "k"));
            if (!Cm.IsMap(p)) return false;
            int left = Json.Int(p, "l"), daily = Json.Int(p, "m"), bonus = Json.Int(p, "b");
            double reset = Math.Max(0, Json.Number(pocket, "reset") - elapsed);
            var lines = new List<string>
            {
                Loc.T("Pocket: a private copy of this boss, open any time, alone or with your party (each member spends a charge)."),
                Loc.T("Less experience and loot than the scheduled fight; the boss passive point counts the same."),
                Loc.T("Charges left: {0} (daily {1}, bonus {2}). New daily charges in {3}.", left, daily, bonus, Cm.Countdown(reset)),
            };
            bool okLevel = Json.Get(p, "ok") != null;
            bool inside = Json.Get(pocket, "inside") != null;
            enabled = left > 0 && okLevel && !inside;
            if (!okLevel && Json.Number(p, "lv") > 0) lines.Add(Loc.T("Needs level {0}.", Json.Int(p, "lv")));
            else if (inside) lines.Add(Loc.T("You are in a pocket now."));
            text = Loc.T("Pocket {0}/{1}", left, daily);
            tip = string.Join("\n", lines);
            return true;
        }

        public static string HeaderText(Group g, bool collapsed)
        {
            string count = g.Rows.Count == g.Total ? g.Total.ToString(CultureInfo.InvariantCulture) : g.Rows.Count + " " + Loc.T("of") + " " + g.Total;
            int alive = 0;
            foreach (var r in g.Rows) if (Json.Text(r, "st") == "alive") alive++;
            string text = (collapsed ? "+ " : "- ") + Json.Text(g.Cat, "n", Json.Text(g.Cat, "k")) + " (" + count + ")";
            if (alive > 0) text += Loc.T(" - {0} alive", alive);
            return text;
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Boss Spawns");
            double e = Elapsed;
            if (Data == null) { Header2 = ""; l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            if (PocketMsg.Length > 0 && (NowMs - MsgAt) / 1000 < 8) Header2 = PocketMsg;
            else Header2 = e < 5 ? Loc.T("Updated just now") : Loc.T("Updated {0}", Cm.Ago(e));
            l.Input(Loc.T("Search"), "search", Loc.T("boss or place"));
            string filter = Text("search");
            var groups = GroupRows(Data, filter);
            if (groups.Count == 0) l.Text(filter.Length > 0 ? Loc.T("No boss matches.") : Loc.T("No bosses listed."), "dim");
            foreach (var g in groups)
            {
                string key = Json.Text(g.Cat, "k");
                bool folded = Collapsed.Contains(key) && filter.Length == 0;
                string col = Json.Text(g.Cat, "c");
                var head = l.Row(HeaderText(g, folded), "", col.StartsWith("#", StringComparison.Ordinal) ? col : "gold");
                head.Tip = Json.Text(g.Cat, "t");
                head.Btn(folded ? Loc.T("Show") : Loc.T("Hide"), true, () => { if (!Collapsed.Remove(key)) Collapsed.Add(key); Changed(); });
                if (folded) continue;
                foreach (var r in g.Rows)
                {
                    string tone;
                    string st = StatusOf(r, e, out tone);
                    var row = l.Row(Json.Text(r, "n", "?"), st, tone);
                    var parts = new List<string>();
                    string lv = LevelText(r); if (lv.Length > 0) parts.Add(lv);
                    string where = Json.Text(r, "loc"); if (where.Length > 0) parts.Add(where);
                    string wc = Where(r); if (wc.Length > 0) parts.Add(wc);
                    string sub = StatusSub(r, e); if (sub.Length > 0) parts.Add(sub);
                    row.Sub = string.Join("   ", parts);
                    row.Tip = Tooltip(r, e);
                    if (PocketOf(r, Pocket, Math.Max(0, (NowMs - PocketAt) / 1000), out string pt, out bool pe, out string ptip))
                    {
                        string bk = Json.Text(r, "k");
                        row.Btn(pt, pe, () => Send("pocketEnter", SFmt.Map("k", bk)), ptip);
                    }
                }
            }
            return l.Rows;
        }
    }

    // ====================================================================================================== game_chaossurvey (122)
    /// <summary>The new player survey. server -> client: open {s, max} | done {s}; client -> server: answer {s, fun, rec, text, src} | skip {s}. At level 20 and 50 (once per account).</summary>
    public sealed class SurveyPanel : CommunityPanel
    {
        public const byte Opcode = 122;
        public const int TextMax = 200, SourceStage = 20;
        public static readonly int[] Stages = { 20, 50 };
        public static readonly KeyValuePair<string, string>[] Sources =
        {
            new KeyValuePair<string, string>("discord", "Discord"), new KeyValuePair<string, string>("forum", "A forum"), new KeyValuePair<string, string>("serverlist", "A server list"),
            new KeyValuePair<string, string>("youtube", "YouTube"), new KeyValuePair<string, string>("shorts", "TikTok, Reels or Shorts"), new KeyValuePair<string, string>("streamer", "A streamer"),
            new KeyValuePair<string, string>("friend", "A friend"), new KeyValuePair<string, string>("search", "A web search"), new KeyValuePair<string, string>("other", "Somewhere else"),
        };
        public int Stage, Max = TextMax;

        public SurveyPanel(ExtOpcodes e) : base(e, Opcode) { }

        protected override void Handle(string action, object data)
        {
            if (action == "open")
            {
                int s = Json.Int(data, "s");
                if (Array.IndexOf(Stages, s) < 0) return;
                double max = Json.Number(data, "max", TextMax);
                Stage = s; Max = max < 1 || max > TextMax ? TextMax : (int)max;
                Form.Clear();
                Visible = true;
            }
            else if (action == "done") { Visible = false; Stage = 0; }
        }

        public override void Clear() { base.Clear(); Stage = 0; }

        public static string Tidy(string text)
        {
            if (text == null) return "";
            var sb = new StringBuilder();
            bool space = false;
            foreach (char c in text)
            {
                if (char.IsControl(c) || c == ' ') { space = true; continue; }
                if (space && sb.Length > 0) sb.Append(' ');
                space = false;
                sb.Append(c);
            }
            return sb.ToString();
        }

        public static string SourceKey(int index) => index >= 1 && index <= Sources.Length ? Sources[index - 1].Key : null;

        /// <summary>The answer the server reads. fun 1..5 (0 none), rec 1 yes 2 no (0 none), src index into Sources (1 based, 0 none).</summary>
        public static Dictionary<string, object> Answer(int stage, int fun, int rec, string text, int max, int src)
        {
            var d = new Dictionary<string, object> { { "s", (double)stage } };
            if (stage == SourceStage && SourceKey(src) != null) d["src"] = SourceKey(src);
            if (fun >= 1 && fun <= 5) d["fun"] = (double)fun;
            if (rec == 1) d["rec"] = true; else if (rec == 2) d["rec"] = false;
            string t = Tidy(text);
            if (t.Length > max) t = t.Substring(0, max);
            if (t.Length > 0) d["text"] = t;
            return d;
        }

        public static bool CanSend(int stage, int fun, int rec, string text, int src) =>
            (fun >= 1 && fun <= 5) || rec == 1 || rec == 2 || Tidy(text).Length > 0 || (stage == SourceStage && src >= 1);

        bool CanSendNow => CanSend(Stage, Index("fun"), Index("rec"), Text("text"), Index("src"));

        public void SendAnswer()
        {
            if (!CanSendNow) { Say(Loc.T("Answer at least one question, or press Skip."), false); return; }
            Send("answer", Answer(Stage, Index("fun"), Index("rec"), Text("text"), Max, Index("src")));
            Visible = false;
        }

        public void Skip() { Send("skip", SFmt.Map("s", (double)Stage)); Visible = false; }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("A few questions");
            Header2 = Loc.T("Your answers help us make the game better. This takes a minute.");
            if (Stage == 0) return l.Rows;
            if (Stage == SourceStage)
            {
                var src = new List<string> { "-" };
                foreach (var s in Sources) src.Add(Loc.T(s.Value));
                l.Combo(Loc.T("Where did you hear about the game?"), "src", src);
            }
            l.Input(Loc.T("What confused you so far?"), "text", Loc.T("optional"));
            l.Text(Math.Min(Text("text").Length, Max) + "/" + Max, "dim");
            l.Combo(Loc.T("How fun is it? (1 to 5)"), "fun", new[] { "-", "1", "2", "3", "4", "5" });
            l.Combo(Loc.T("Would you recommend it?"), "rec", new[] { "-", Loc.T("Yes"), Loc.T("No") });
            var r = l.Row(Loc.T("Send your answers"));
            r.Btn(Loc.T("Send"), CanSendNow, SendAnswer);
            r.Btn(Loc.T("Skip"), true, Skip);
            return l.Rows;
        }

        public override void OnForm(string key)
        {
            if (key == "text" && Text("text").Length > Max) Form["text"] = Text("text").Substring(0, Max);
        }
    }

    // ====================================================================================================== game_nemesis (163)
    /// <summary>The monster that hunts this character. client -> server: get; server -> client: state {has, name, shown, monster, level, kills, traits [{key, name, desc}], lastSeen,
    /// created, expiresIn, avenged, hunted}.</summary>
    public sealed class NemesisPanel : CommunityPanel
    {
        public const byte Opcode = 163;
        public const int MaxText = 64;
        public object State;
        /// <summary>Seconds since 1970, from the clock of the computer (the server's lastSeen is in the same unit).</summary>
        public Func<double> Epoch = () => DateTimeOffset.UtcNow.ToUnixTimeSeconds();

        public NemesisPanel(ExtOpcodes e) : base(e, Opcode) { }

        public override void Show() { Visible = true; Send("get"); }
        public override void Clear() { base.Clear(); State = null; }

        protected override void Handle(string action, object data) { if (action == "state") State = data; }

        public static string Cut(string s, string fallback) => string.IsNullOrEmpty(s) ? fallback : (s.Length > MaxText ? s.Substring(0, MaxText) : s);
        static int Whole(object v) => v is double d && !double.IsNaN(d) && !double.IsInfinity(d) ? (int)Math.Max(0, Math.Floor(d)) : 0;

        public static string Ago(double seconds)
        {
            long s = (long)Math.Max(0, seconds);
            if (s < 60) return Loc.T("just now");
            if (s < 3600) return Loc.T("{0} min ago", s / 60);
            if (s < 86400) return Loc.T("{0} h ago", s / 3600);
            long days = s / 86400;
            return Loc.T(days == 1 ? "{0} day ago" : "{0} days ago", days);
        }

        public static string Left(double seconds)
        {
            long s = (long)Math.Max(0, seconds);
            if (s >= 86400) { long d = s / 86400; return Loc.T(d == 1 ? "{0} day" : "{0} days", d); }
            if (s >= 3600) return Loc.T("{0} h", s / 3600);
            return Loc.T("under an hour");
        }

        public static string SubText(string monster, int kills)
        {
            if (kills < 1) kills = 1;
            if (kills == 1) return Loc.T("A {0} that killed you once", monster);
            if (kills == 2) return Loc.T("A {0} that killed you twice", monster);
            if (kills == 3) return Loc.T("A {0} that killed you three times", monster);
            return Loc.T("A {0} that killed you {1} times", monster, kills);
        }

        public static readonly Dictionary<string, string> TraitColors = new Dictionary<string, string>
        {
            { "vengeful", "#e05040" }, { "swift", "#70c8f0" }, { "thorned", "#c8a040" }, { "regenerating", "#60d070" }, { "stalker", "#b080e0" },
        };

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            var s = State ?? new Dictionary<string, object>();
            bool has = Json.Truthy(s, "has");
            if (!has)
            {
                Header1 = Loc.T("No Nemesis hunts you");
                Header2 = "";
                l.Text(Loc.T("When a monster kills you (level 50 or more), it may become your Nemesis. It returns while you hunt its kind. Slay it for a trophy and the title Avenger of Self."), "dim");
            }
            else
            {
                string monster = Cut(Json.Text(s, "monster"), "?");
                Header1 = Cut(Json.Text(s, "shown", Json.Text(s, "name")), "?");
                Header2 = SubText(monster, Whole(Json.Get(s, "kills")));
                l.Row(Loc.T("Monster"), monster);
                l.Row(Loc.T("Level"), Whole(Json.Get(s, "level")).ToString(CultureInfo.InvariantCulture));
                l.Row(Loc.T("Kills"), Math.Max(1, Whole(Json.Get(s, "kills"))).ToString(CultureInfo.InvariantCulture));
                double seen = Whole(Json.Get(s, "lastSeen")), now = Epoch();
                l.Row(Loc.T("Last seen"), seen > 0 && now > 0 ? Ago(now - seen) : "?");
                l.Row(Loc.T("Fades in"), Left(Json.Number(s, "expiresIn")));
                int n = 0;
                foreach (var t in SFmt.Rows(s, "traits"))
                {
                    string name = Json.Text(t, "name");
                    if (name.Length == 0) continue;
                    if (n == 0) l.Section(Loc.T("Traits"));
                    l.Row(Cut(name, "?"), "", TraitColors.TryGetValue(Json.Text(t, "key"), out var c) ? c : "text").Sub = Cut(Json.Text(t, "desc"), "");
                    if (++n >= 4) break;
                }
            }
            l.Text(Loc.T("Nemeses avenged: {0}   |   Nemeses of others slain: {1}", Whole(Json.Get(s, "avenged")), Whole(Json.Get(s, "hunted"))), "dim");
            return l.Rows;
        }
    }

    // ====================================================================================================== game_referral (220)
    /// <summary>The referral window. client -> server: open | sync | enter {code}; server -> client: status {...} (open: show the window) | message {text, error}.</summary>
    public sealed class ReferralPanel : CommunityPanel
    {
        public const byte Opcode = 220;
        public object StatusData;
        /// <summary>Puts text on the clipboard (the app sets it).</summary>
        public Action<string> Copy = delegate { };

        public ReferralPanel(ExtOpcodes e) : base(e, Opcode) { }

        public override void Show() { Visible = true; Send("open"); }
        public override void Clear() { base.Clear(); StatusData = null; }

        protected override void Handle(string action, object data)
        {
            if (action == "status") { StatusData = data; if (Json.Truthy(data, "open")) { Visible = true; Status = ""; } }
            else if (action == "message") { Status = Json.Text(data, "text"); StatusTone = Json.Truthy(data, "error") ? "bad" : "good"; }
        }

        public static string LeftText(double seconds)
        {
            if (seconds <= 0) return "";
            long days = (long)Math.Floor(seconds / 86400);
            if (days >= 1) return Loc.T(days == 1 ? "{0} day left" : "{0} days left", days);
            long hours = Math.Max(1, (long)Math.Floor(seconds / 3600));
            return Loc.T(hours == 1 ? "{0} hour left" : "{0} hours left", hours);
        }

        public static string RewardsText(object s)
        {
            if (s == null) return "";
            var lines = new List<string>();
            string gift = Json.Text(s, "gift");
            if (Json.Text(s, "giftTitle").Length > 0) gift = Loc.T("{0} and the title {1}", gift, Json.Text(s, "giftTitle"));
            lines.Add(Loc.T("Your friend gets: {0}.", gift));
            var parts = new List<string>();
            foreach (var m in SFmt.Rows(s, "milestones")) parts.Add(Loc.T("level {0}: {1}", Json.Int(m, "level"), Json.Text(m, "reward")));
            if (parts.Count > 0) lines.Add(Loc.T("You get, when your friend's first character reaches {0}.", string.Join("; ", parts)));
            var tiers = new List<string>();
            foreach (var t in SFmt.Rows(s, "tiers")) tiers.Add(Loc.T("{0} friends: {1}{2}", Json.Int(t, "count"), Json.Text(t, "reward"), Json.Truthy(t, "reached") ? " " + Loc.T("(yours)") : ""));
            if (tiers.Count > 0) lines.Add(Loc.T("And with friends at level {0} ({1} so far): {2}.", Json.Int(s, "qualifyLevel"), Json.Int(s, "qualified"), string.Join("; ", tiers)));
            return string.Join("\n", lines);
        }

        /// <summary>The "got a code" part: its text, and whether the code box shows.</summary>
        public static string EntryText(object s, out bool box)
        {
            box = false;
            if (s == null) return "";
            if (Json.Text(s, "referrer").Length > 0)
            {
                string text = Loc.T("You were referred by {0}.", Json.Text(s, "referrer"));
                if (Json.Text(s, "linkStatus") == "active") text += Json.Truthy(s, "giftGiven") ? Loc.T(" Your welcome gift was given.") : Loc.T(" Your welcome gift comes at your next login.");
                return text;
            }
            if (Json.Truthy(s, "canEnter"))
            {
                box = true;
                string left = LeftText(Json.Number(s, "enterLeft"));
                if (Json.Text(s, "rejected").Length > 0) return Loc.T("The code from your account creation was not accepted: {0} You can enter another one ({1}).", Json.Text(s, "rejected"), left);
                return Loc.T("Got a code from a friend? Enter it here ({0}).", left);
            }
            return Json.Text(s, "enterNote");
        }

        public static string StepText(string state) { switch (state) { case "open": return "-"; case "due": return Loc.T("waiting"); case "paid": return Loc.T("rewarded"); case "void": return Loc.T("no reward"); } return state; }

        public static string MonthText(object s) =>
            s == null ? "" : Loc.T("This month: {0} / {1} new friends, {2} / {3} rewards.   Chaos Coins earned: {4}", Json.Int(s, "linksThisMonth"), Json.Int(s, "monthlyLinks"), Json.Int(s, "paidThisMonth"), Json.Int(s, "monthlyRewards"), Json.Int(s, "coinsEarned"));

        public void Enter()
        {
            string code = (Text("code") ?? "").Trim();
            if (code.Length == 0) { Say(Loc.T("Type the code first."), false); return; }
            Send("enter", SFmt.Map("code", code));
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            var s = StatusData;
            Header1 = Loc.T("Referral");
            Header2 = "";
            if (s == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            l.Section(Loc.T("Your code"));
            if (!Json.Truthy(s, "enabled")) { l.Text(Loc.T("The referral program is off."), "dim"); return l.Rows; }
            string code = Json.Text(s, "code");
            if (code.Length == 0) l.Text(Json.Text(s, "codeNote", "-"), "dim");
            else
            {
                var row = l.Row(code, "", "gold");
                string c = code;
                row.Btn(Loc.T("Copy code"), true, () => { Copy(c); Say(Loc.T("Code copied."), true); });
                string url = Json.Text(s, "shareUrl");
                l.Text(url.Length > 0 ? Loc.T("Share it, or the link {0}", url) : Loc.T("Share it: a friend enters it when creating an account on the website, or in this window in the first week."), "dim");
            }
            l.Text(RewardsText(s), "text");
            bool box;
            string entry = EntryText(s, out box);
            if (entry.Length > 0) l.Text(entry, "dim");
            if (box) l.Input(Loc.T("Friend's code"), "code", Loc.T("code")).Btn(Loc.T("Use code"), true, Enter);
            l.Text(MonthText(s), "dim");
            var friends = SFmt.Rows(s, "friends");
            l.Section(friends.Count == 0 ? Loc.T("Referred friends") : Loc.T("Referred friends ({0})", friends.Count));
            if (friends.Count == 0) l.Text(Loc.T("Nobody has joined with your code yet."), "dim");
            foreach (var f in friends)
            {
                var steps = new List<string>();
                foreach (var st in SFmt.Rows(f, "steps")) steps.Add(Loc.T("Lv {0}: {1}", Json.Int(st, "level"), StepText(Json.Text(st, "state"))));
                var r = l.Row(Json.Text(f, "name", "?"), Loc.T("Level {0}, joined {1}", Json.Int(f, "level"), Cm.IsoDate(Json.Number(f, "linkedAt"))));
                r.Sub = string.Join("   ", steps);
            }
            return l.Rows;
        }
    }
}
