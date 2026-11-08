// Item and economy utilities, part 2 (client game_unveil 196, game_itemfinder 155, game_loadouts 206, game_spellsupports 243, game_pact 222, game_candlemarks 176). Pure models.
//
// unveil 196        client choose {path, id, sig, choice}; server open {name, rarityName, level, orbs, path, id, sig, offers = [{i, key, name, text, tier, tn, lo, hi, hook}]} | result {ok, text, veil}
// itemfinder 155    client search {q, p} | item {id} | item {cid} | page {id, k, p}; server results {q, p, pages, total, rows} | item {id, cid, name, total, none, secs} | page {...} | busy {}
// loadouts 206      client open | save {slot, name, icon} | load {slot} | rename {slot, name, icon} | delete {slot} | cancel; server state {...} | result {ok, text, lines} | cast {ms, slot} | castEnd {result}
// spellsupports 243 client open | socket {spell, slot, rune} | socket {spell, slot, pos, clientId} | remove {spell, slot, keep} | unlock {spell} | combine {rune}
//                   server state {level, orbId, orbClientId, orbName, orbCount, orbsNeeded, spells, runes} | bar {spells, words} | result {ok, text} | part {id, index, total, text}
// pact 222          client open | sync | claim | marksBuy {key} | buildSave {slot?, name} | buildRename {slot, name} | buildDelete {slot} | buildLoad {slot}; server status {...} | buildCode {slot, code} | message {text, error}
// candlemarks 176   client open | buy {k}; server hud {b, p, n, e, w} (every minute) | state {...} | result {ok, text} | npc {}
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ------------------------------------------------------------------------------------------------ unveil
    public sealed class UnveilCard
    {
        public int I;
        public string Key = "", Name = "", Text = "", TierText = "", TierColor = "", RangeText = "", HookText = "";
        public List<string> Lines = new List<string>();
    }

    public sealed class UnveilState
    {
        public const byte Opcode = 196;
        public const int Wrap = 26;
        public static readonly string[] TierColors = { "#9a8cc0", "#a98cff", "#c070ff", "#ff70e0" };

        readonly ExtOpcodes ext;
        public object Data;
        public int Selected;
        public bool Visible, Done;
        public string Result = "", ResultColor = "#8c8070";
        public Action Changed = delegate { };

        public UnveilState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public static string TierColor(int t) => t >= 1 && t <= TierColors.Length ? TierColors[t - 1] : "#b48cff";

        public string HeaderText()
        {
            if (Data == null) return "";
            var parts = new List<string> { WorldText.Cap(Json.Text(Data, "name", "?")) };
            if (Json.Text(Data, "rarityName").Length > 0) parts.Add(Json.Text(Data, "rarityName"));
            if (Json.Int(Data, "level") > 0) parts.Add(Loc.T("Item Level {0}", Json.Int(Data, "level")));
            return string.Join("  -  ", parts);
        }

        public string OrbsText() => Loc.T("Orbs of Unveiling: {0}", Json.Int(Data, "orbs"));

        public List<UnveilCard> Cards()
        {
            var o = new List<UnveilCard>();
            foreach (object c in Json.List(Data, "offers"))
            {
                if (o.Count >= 3 || !(c is Dictionary<string, object>) || Json.Get(c, "i") == null || Json.Text(c, "name").Length == 0 || Json.Text(c, "text").Length == 0) continue;
                string tn = Json.Text(c, "tn", "V" + (Json.Get(c, "tier") == null ? 1 : Json.Int(c, "tier")));
                string range = "";
                if (Json.Get(c, "lo") is double lo && Json.Get(c, "hi") is double hi) range = lo == hi ? Loc.T("Range {0}", (int)lo) : Loc.T("Range {0}-{1}", (int)lo, (int)hi);
                o.Add(new UnveilCard
                {
                    I = Json.Int(c, "i"), Key = Json.Text(c, "key"), Name = Json.Text(c, "name"), Text = Json.Text(c, "text"), Lines = WorldText.Wrap(Json.Text(c, "text"), Wrap),
                    TierText = Loc.T("Veiled tier {0}", tn), TierColor = TierColor(Json.Int(c, "tier")), RangeText = range, HookText = Json.Bool(c, "hook") ? Loc.T("Effect of its own") : "",
                });
            }
            return o;
        }

        public bool CanConfirm(int i)
        {
            if (Data == null || Json.Int(Data, "orbs") < 1) return false;
            foreach (var c in Cards()) if (c.I == i) return true;
            return false;
        }

        public string StatusText()
        {
            if (Data == null) return "";
            if (Json.Int(Data, "orbs") < 1) return Loc.T("You have no Orb of Unveiling.");
            foreach (var c in Cards()) if (c.I == Selected) return Loc.T("Reveal {0}? The choice is final and takes one orb.", c.Name);
            return Loc.T("Choose one of the three modifiers. The choice is final.");
        }

        public static string ResultTextOf(object res, out string color)
        {
            if (!(res is Dictionary<string, object>)) { color = "#8c8070"; return ""; }
            if (Json.Bool(res, "ok"))
            {
                color = "#7fe0a0";
                var v = Json.Get(res, "veil");
                if (v is Dictionary<string, object> && Json.Text(v, "n").Length > 0)
                    return Loc.T("The veil lifts: {0} ({1}) is yours.", Json.Text(v, "n"), Json.Text(v, "tn", "V" + (Json.Get(v, "tr") == null ? 1 : Json.Int(v, "tr"))));
                return Json.Text(res, "text", Loc.T("The veil lifts."));
            }
            color = "#e03a1e";
            return Json.Text(res, "text", Loc.T("That did not work."));
        }

        /// <summary>Unveil: the choice is final and takes one orb.</summary>
        public bool Confirm()
        {
            if (!CanConfirm(Selected) || Done) return false;
            return ext.Send(Opcode, "choose", new Dictionary<string, object> { { "path", Json.Get(Data, "path") }, { "id", Json.Get(Data, "id") }, { "sig", Json.Get(Data, "sig") }, { "choice", Selected } });
        }

        public void Hide() { Visible = false; }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            if (action == "open") { Data = d; Selected = 0; Done = false; Result = ""; Visible = true; Changed(); }
            else if (action == "result")
            {
                Result = ResultTextOf(d, out string c); ResultColor = c;
                if (Json.Bool(d, "ok")) Done = true;
                Changed();
            }
        }

        public void Clear() { Data = null; Visible = false; Done = false; Result = ""; }
    }

    // ------------------------------------------------------------------------------------------------ item finder
    public sealed class ItemFinderRow { public string N = "", D = "", V = "", C = ""; public int I, L; public bool B; public List<KeyValuePair<string, int>> Materials = new List<KeyValuePair<string, int>>(); }
    public sealed class ItemFinderSection { public string K = ""; public int P = 1, Pages = 1, Total; public List<ItemFinderRow> Rows = new List<ItemFinderRow>(); }
    public sealed class ItemFinderHit { public int Id, Cid, N; public string Name = ""; public List<string> Kinds = new List<string>(); }
    public sealed class ItemFinderResults { public string Q = ""; public int P = 1, Pages = 1, Total; public List<ItemFinderHit> Rows = new List<ItemFinderHit>(); }
    public sealed class ItemFinderItem { public int Id, Cid, Total; public string Name = ""; public bool None; public List<ItemFinderSection> Secs = new List<ItemFinderSection>(); }

    public sealed class ItemFinderState
    {
        public const byte Opcode = 155;
        public const double SearchDelayMs = 350, ResendMs = 900;
        public const int MinQuery = 2, MaxQuery = 40, HistoryMax = 20;
        public static readonly string[][] Sections =
        {
            new[] { "drop", "Chaos drops" }, new[] { "monster", "Monsters and bosses" }, new[] { "reward", "Chests and rewards" }, new[] { "craft", "Crafted from" },
            new[] { "shop", "NPCs that sell it" }, new[] { "store", "Store and vendors" }, new[] { "gamble", "The Gambler" }, new[] { "gather", "Gathering" },
            new[] { "usedin", "Used to make" }, new[] { "sellto", "NPCs that buy it" }, new[] { "use", "Other uses" },
        };
        public static readonly Dictionary<string, string> Short = new Dictionary<string, string>
        {
            { "monster", "drops" }, { "drop", "Chaos drops" }, { "reward", "rewards" }, { "craft", "recipes" }, { "shop", "shops" }, { "store", "store" }, { "gamble", "Gambler" },
            { "gather", "gathering" }, { "usedin", "used in" }, { "sellto", "sold to NPCs" }, { "use", "uses" },
        };

        readonly ExtOpcodes ext;
        public ItemFinderResults Results;
        public ItemFinderItem Item;
        public readonly List<KeyValuePair<int, int>> History = new List<KeyValuePair<int, int>>();
        public string LastSent = "", Status = "";
        public bool Visible;
        string pendingAction; Dictionary<string, object> pendingData; double pendingAt = -1;
        public double SearchDueAt = -1;
        public string SearchText = "";
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public ItemFinderState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        public static string SectionTitle(string k) { foreach (var s in Sections) if (s[0] == k) return Loc.T(s[1]); return k; }
        static int SectionIndex(string k) { for (int i = 0; i < Sections.Length; i++) if (Sections[i][0] == k) return i; return 99; }

        /// <summary>The query: spaces folded, trimmed, at most 40 characters.</summary>
        public static string Query(string text)
        {
            var sb = new StringBuilder();
            bool sp = false;
            foreach (char c in (text ?? "").Trim())
            {
                if (char.IsWhiteSpace(c)) { sp = true; continue; }
                if (sp && sb.Length > 0) sb.Append(' ');
                sp = false; sb.Append(c);
            }
            string q = sb.ToString();
            return q.Length > MaxQuery ? q.Substring(0, MaxQuery) : q;
        }

        public static bool ShouldSearch(string text, string lastSent, out string q)
        {
            q = Query(text);
            return q.Length >= MinQuery && !string.Equals(q, lastSent ?? "", StringComparison.OrdinalIgnoreCase);
        }

        public static string KindsText(IList<string> kinds, int max = 4)
        {
            var o = new List<string>();
            foreach (string k in kinds)
            {
                if (o.Count >= max) { o.Add("..."); break; }
                o.Add(Short.TryGetValue(k, out string s) ? s : k);
            }
            return string.Join(", ", o);
        }

        public static string PageText(int p, int pages) => pages <= 1 ? "" : p + " / " + pages;
        public static string TotalText(int n) => n == 1 ? Loc.T("1 source or use") : Loc.T("{0} sources and uses", n);
        public static string SectionHead(ItemFinderSection s) => SectionTitle(s.K) + " (" + (s.Total > 0 ? s.Total : s.Rows.Count) + ")";

        /// <summary>The main text, the description and the value of a row.</summary>
        public static void RowTexts(ItemFinderRow r, out string main, out string desc, out string value)
        {
            main = r.N + (r.B ? " (boss)" : "");
            desc = r.D;
            value = (r.V.Length > 0 ? r.V + (r.C.Length > 0 ? "  " : "") : "") + r.C;
        }

        public static string MaterialText(KeyValuePair<string, int> m) => m.Value + " x " + m.Key;

        static List<ItemFinderRow> CleanRows(object rows)
        {
            var o = new List<ItemFinderRow>();
            if (!(rows is List<object> l)) return o;
            foreach (object r in l)
            {
                if (!(r is Dictionary<string, object>) || Json.Get(r, "n") == null || !(Json.Get(r, "n") is string)) continue;
                var row = new ItemFinderRow { N = Json.Text(r, "n"), D = Json.Text(r, "d"), V = Json.Text(r, "v"), C = Json.Text(r, "c"), I = Json.Int(r, "i"), L = Json.Int(r, "l"), B = Json.Bool(r, "b") };
                foreach (object m in Json.List(r, "m")) if (m is Dictionary<string, object>) row.Materials.Add(new KeyValuePair<string, int>(Json.Text(m, "n"), Json.Get(m, "c") is double c ? (int)c : 1));
                o.Add(row);
            }
            return o;
        }

        static ItemFinderSection CleanSection(object s)
        {
            if (!(s is Dictionary<string, object>) || Json.Text(s, "k").Length == 0) return null;
            return new ItemFinderSection { K = Json.Text(s, "k"), P = Json.Get(s, "p") is double p ? (int)p : 1, Pages = Json.Get(s, "pages") is double pg ? (int)pg : 1, Total = Json.Int(s, "total"), Rows = CleanRows(Json.Get(s, "rows")) };
        }

        public static ItemFinderResults ParseResults(object d)
        {
            if (!(d is Dictionary<string, object>)) return null;
            var o = new ItemFinderResults { Q = Json.Text(d, "q"), P = Json.Get(d, "p") is double p ? (int)p : 1, Pages = Json.Get(d, "pages") is double pg ? (int)pg : 1, Total = Json.Int(d, "total") };
            foreach (object r in Json.List(d, "rows"))
            {
                if (!(r is Dictionary<string, object>) || Json.Get(r, "id") == null || !(Json.Get(r, "name") is string)) continue;
                var h = new ItemFinderHit { Id = Json.Int(r, "id"), Cid = Json.Int(r, "cid"), Name = Json.Text(r, "name"), N = Json.Int(r, "n") };
                foreach (object k in Json.List(r, "kinds")) if (k is string s) h.Kinds.Add(s);
                o.Rows.Add(h);
            }
            return o;
        }

        public static ItemFinderItem ParseItem(object d)
        {
            if (!(d is Dictionary<string, object>)) return null;
            var o = new ItemFinderItem { Id = Json.Int(d, "id"), Cid = Json.Int(d, "cid"), Name = Json.Text(d, "name"), Total = Json.Int(d, "total"), None = Json.Bool(d, "none") };
            foreach (object s in Json.List(d, "secs")) { var c = CleanSection(s); if (c != null) o.Secs.Add(c); }
            o.Secs.Sort((a, b) => SectionIndex(a.K).CompareTo(SectionIndex(b.K)));
            return o;
        }

        public static bool ApplyPage(ItemFinderItem item, object d)
        {
            if (item == null || !(d is Dictionary<string, object>) || Json.Int(d, "id") != item.Id) return false;
            var c = CleanSection(d);
            if (c == null) return false;
            for (int i = 0; i < item.Secs.Count; i++) if (item.Secs[i].K == c.K) { item.Secs[i] = c; return true; }
            return false;
        }

        public static void Push(List<KeyValuePair<int, int>> history, int id, int cid)
        {
            if (history.Count > 0 && history[history.Count - 1].Key == id && history[history.Count - 1].Value == cid) return;
            history.Add(new KeyValuePair<int, int>(id, cid));
            while (history.Count > HistoryMax) history.RemoveAt(0);
        }

        // ---- requests (a request without an answer after 900 ms goes out once more: the server drops requests that come too fast)
        void Request(string action, Dictionary<string, object> data)
        {
            pendingAction = action; pendingData = data; pendingAt = Clock();
            ext.Send(Opcode, action, data);
        }

        public void Open() { Visible = true; }
        public void Toggle() { Visible = !Visible; }
        public void Search(string text, int page = 1)
        {
            if (!ShouldSearch(text, page > 1 ? "" : LastSent, out string q)) return;
            LastSent = q;
            Request("search", new Dictionary<string, object> { { "q", q }, { "p", page } });
        }

        public void TypeAhead(string text) { SearchText = text; SearchDueAt = Clock() + SearchDelayMs; }

        /// <summary>The server answers a type-ahead search 350 ms after the last key; an unanswered request is sent again once.</summary>
        public void Tick()
        {
            double now = Clock();
            if (SearchDueAt >= 0 && now >= SearchDueAt) { SearchDueAt = -1; Search(SearchText); }
            if (pendingAction != null && now - pendingAt >= ResendMs)
            {
                string a = pendingAction; var d = pendingData; pendingAction = null; pendingAt = -1;
                ext.Send(Opcode, a, d);
            }
        }

        public void ShowItem(int id, int cid, bool pushCurrent = true)
        {
            if (pushCurrent && Item != null) Push(History, Item.Id, Item.Cid);
            var d = new Dictionary<string, object>();
            if (id > 0) d["id"] = id; else if (cid > 0) d["cid"] = cid; else return;
            Visible = true;
            Request("item", d);
        }

        /// <summary>"Where to find" on an item of a bag or the map (a client id).</summary>
        public bool WhereToFind(int clientId)
        {
            if (clientId < 1 || clientId > 65535) return false;
            ShowItem(0, clientId, false);
            return true;
        }

        public void Page(string kind, int p) { if (Item != null) Request("page", new Dictionary<string, object> { { "id", Item.Id }, { "k", kind }, { "p", p } }); }

        public bool Back()
        {
            if (History.Count == 0) { Item = null; Changed(); return false; }
            var e = History[History.Count - 1];
            History.RemoveAt(History.Count - 1);
            ShowItem(e.Key, e.Value, false);
            return true;
        }

        public void Handle(string action, object d)
        {
            pendingAction = null; pendingAt = -1;
            switch (action)
            {
                case "results": { var r = ParseResults(d); if (r != null) { Results = r; Status = ""; } break; }
                case "item": { var it = ParseItem(d); if (it != null) { Item = it; Status = ""; } break; }
                case "page": ApplyPage(Item, d); break;
                case "busy": Status = Loc.T("The finder is busy, try again."); break;
                default: return;
            }
            Changed();
        }

        public void Clear() { Results = null; Item = null; History.Clear(); LastSent = ""; Visible = false; }
    }

    // ------------------------------------------------------------------------------------------------ loadouts
    public sealed class LoadoutRow { public string Icon = "", Title = "", Sub = "", Tag = "", TagColor = "#8c8070"; public bool Dim; }
    public sealed class LoadoutLine { public string Text = "", Color = "#d8ccb4"; }
    public sealed class LoadoutButtons { public bool Save, Load, Rename, Delete; public string SaveText = ""; }

    public sealed class LoadoutsState
    {
        public const byte Opcode = 206;
        public const string Gold = "#e8b84a", Text = "#d8ccb4", Dim = "#8c8070", Good = "#8fd16a", Warn = "#e0a050", Bad = "#e07060", Active = "#7fc4ff";

        readonly ExtOpcodes ext;
        public object State;
        public double StateAt;
        public int Selected;
        public string IconChoice = "skills", Status = "", StatusColor = Dim;
        public int ConfirmDelete;
        public string PendingAction = ""; public int PendingSlot;
        public bool Visible;
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };
        /// <summary>The cast bar hand-off of a switch that takes time: name and ms; the result when it ends.</summary>
        public Action<string, double> CastStarted = delegate { };
        public Action<string> CastEnded = delegate { };
        /// <summary>The action bar profile remembered per character and slot (PlayerPrefs in Unity): set after a save, applied after a load.</summary>
        public Action<int> ProfileSaved = delegate { };
        public Action<int> ProfileLoaded = delegate { };

        public LoadoutsState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        static double Num(object o, string k) => Json.Number(o, k);
        static string Cap(string s) => WorldText.Cap(s);

        public static string IconPath(string icon) => string.IsNullOrEmpty(icon) ? "skills" : icon;

        public int UnlockLevel(int index)
        {
            int k = index - Json.Int(State, "baseSlots");
            var l = Json.List(State, "unlockLevels");
            return k >= 1 && k <= l.Count && l[k - 1] is double d ? (int)d : 0;
        }

        public object SlotOf(int n) { foreach (object s in Json.List(State, "slots")) if (Json.Int(s, "slot") == n) return s; return null; }

        public LoadoutRow SlotRow(object slot)
        {
            var row = new LoadoutRow { Icon = IconPath(Json.Text(slot, "icon")) };
            if (slot == null) { row.Title = "?"; return row; }
            bool empty = Json.Bool(slot, "empty"), locked = Json.Bool(slot, "locked");
            if (locked && empty)
            {
                int lvl = UnlockLevel(Json.Int(slot, "slot"));
                row.Title = Loc.T("Locked slot"); row.Sub = lvl > 0 ? Loc.T("Opens at level {0}", lvl) : Loc.T("Locked"); row.Dim = true; row.Icon = "options";
                return row;
            }
            if (empty) { row.Title = Loc.T("Empty slot"); row.Sub = Loc.T("Save your current build here"); row.Dim = true; row.Icon = "inventory"; return row; }
            row.Title = Json.Text(slot, "name", "Loadout " + Json.Int(slot, "slot"));
            var parts = new List<string> { Loc.T("{0} pts", Json.Int(slot, "points")) };
            var sup = Json.Get(slot, "supports");
            if (Json.Int(sup, "count") > 0) parts.Add(Loc.T("{0} runes", Json.Int(sup, "count")));
            var g = Json.Get(slot, "gear");
            if (Json.Int(g, "total") > 0) parts.Add(Loc.T("gear {0}/{1}", Json.Int(g, "ready"), Json.Int(g, "total")));
            row.Sub = string.Join(" | ", parts);
            if (Json.Bool(slot, "active")) { row.Tag = "ACTIVE"; row.TagColor = Active; }
            else if (locked) { row.Tag = "LOCKED"; row.TagColor = Dim; }
            else if (Json.List(slot, "warnings").Count > 0 || Json.List(g, "missing").Count > 0) { row.Tag = "CHECK"; row.TagColor = Warn; }
            return row;
        }

        public static string GearLine(object g, out string color)
        {
            int total = Json.Int(g, "total"), ready = Json.Int(g, "ready");
            if (total == 0) { color = Dim; return Loc.T("Gear set: none (save while wearing it)"); }
            if (ready >= total) { color = Good; return Loc.T("Gear set: complete ({0}/{1})", ready, total); }
            color = Warn; return Loc.T("Gear set: {0}/{1} ready", ready, total);
        }

        public List<LoadoutLine> Summary(object slot, string profile)
        {
            var o = new List<LoadoutLine>();
            void Add(string t, string c = Text) => o.Add(new LoadoutLine { Text = t, Color = c });
            if (slot == null) return o;
            if (Json.Bool(slot, "empty"))
            {
                if (Json.Bool(slot, "locked"))
                {
                    int lvl = UnlockLevel(Json.Int(slot, "slot"));
                    Add(lvl > 0 ? Loc.T("This slot opens at level {0}. Extra slots are earned by levelling, never sold.", lvl) : Loc.T("This slot is locked."), Dim);
                }
                else
                {
                    Add(Loc.T("Empty. Save copies your current build here: passive tree, Paragon points, the equipped gear set."), Dim);
                    Add(Loc.T("Support runes stay with the loadout they are socketed in."), Dim);
                }
                return o;
            }
            string cls = Cap(Json.Text(slot, "cls")), voc = Json.Text(slot, "voc");
            if (voc.Length > 0 && Cap(voc) != cls && cls.Length > 0) Add(Loc.T("Class: {0} ({1})", cls, voc));
            else Add("Class: " + (voc.Length > 0 ? voc : cls));
            Add(Loc.T("Passive points: {0} / {1}", Json.Int(slot, "points"), Json.Int(slot, "pointsTotal")));
            var ks = new List<string>();
            foreach (object k in Json.List(slot, "keystones")) if (k is string s) ks.Add(s);
            if (ks.Count > 0) Add("Keystones: " + string.Join(", ", ks), Gold); else Add(Loc.T("Keystones: none"), Dim);
            if (Json.Int(slot, "paragon") > 0) Add(Loc.T("Paragon points: {0}", Json.Int(slot, "paragon")));
            var sup = Json.Get(slot, "supports");
            int sc = Json.Int(sup, "count");
            if (sc > 0)
            {
                Add(Loc.T("Supports: {0} rune{1}", sc, sc == 1 ? "" : "s"));
                foreach (object sp in Json.List(sup, "spells"))
                {
                    var runes = new List<string>();
                    foreach (object r in Json.List(sp, "runes")) if (r is string rs) runes.Add(rs);
                    Add("  " + Json.Text(sp, "name") + ": " + string.Join(", ", runes), Dim);
                }
            }
            else Add(Loc.T("Supports: none"), Dim);
            var gear = Json.Get(slot, "gear");
            string gc;
            Add(GearLine(gear, out gc), gc);
            foreach (object m in Json.List(gear, "missing"))
            {
                string where = Json.Text(m, "where") == "missing" || Json.Text(m, "where").Length == 0 ? Loc.T("not found") : Json.Text(m, "where");
                Add("  Missing: " + Json.Text(m, "name") + " (" + where + ")", Bad);
            }
            if (!string.IsNullOrEmpty(profile)) Add(Loc.T("Action bar: {0}", profile), Dim);
            foreach (object w in Json.List(slot, "warnings")) if (w is string ws) Add(ws, Warn);
            if (Json.Bool(slot, "active")) Add(Loc.T("Active: this is your current build. Edit it in the passive tree window."), Active);
            return o;
        }

        public int CooldownLeft(double now) => State == null ? 0 : (int)Math.Max(0, Num(State, "cooldown") - Math.Floor((now - StateAt) / 1000));

        public string SwitchHint(double now, out string color)
        {
            color = Dim;
            if (State == null) return "";
            if (Json.Int(State, "level") < Json.Int(State, "minLevel")) return Loc.T("Loadouts open at level {0}.", Json.Int(State, "minLevel"));
            if (Json.Bool(State, "casting")) { color = Active; return Loc.T("Switching... stand still."); }
            if (Json.Get(State, "busy") is string busy && busy.Length > 0) { color = Bad; return Loc.T("No switching inside {0}.", busy); }
            int left = CooldownLeft(now);
            if (left > 0) { color = Warn; return Loc.T("Next switch in {0} s.", left); }
            if (Json.Bool(State, "inPz")) { color = Good; return Loc.T("Protection zone: switching is instant and free."); }
            color = Text;
            return Loc.T("Switching takes {0} s here (stand still). Free.", (Num(State, "castMs") / 1000).ToString("0.0", CultureInfo.InvariantCulture));
        }

        public LoadoutButtons Buttons(object slot, double now)
        {
            var b = new LoadoutButtons();
            if (State == null || slot == null) return b;
            bool empty = Json.Bool(slot, "empty"), locked = Json.Bool(slot, "locked");
            bool usable = !locked && Json.Int(State, "level") >= Json.Int(State, "minLevel");
            bool busy = Json.Get(State, "busy") is string bs && bs.Length > 0;
            b.Save = usable; b.Rename = !empty; b.Delete = !empty;
            b.Load = usable && !empty && !Json.Bool(slot, "active") && !Json.Bool(State, "casting") && !busy && CooldownLeft(now) == 0;
            b.SaveText = empty ? Loc.T("Save here") : Json.Bool(slot, "active") ? "Save" : "Overwrite";
            return b;
        }

        public static string NextIcon(IList<string> icons, string current)
        {
            if (icons == null || icons.Count == 0) return current;
            for (int i = 0; i < icons.Count; i++) if (icons[i] == current) return icons[(i + 1) % icons.Count];
            return icons[0];
        }

        public List<string> Icons() { var l = new List<string>(); foreach (object o in Json.List(State, "icons")) if (o is string s) l.Add(s); return l; }
        public static string ProfileKey(string charName, int slot) => (charName ?? "?").ToLowerInvariant() + ":" + slot;

        public static string ResultTextOf(object res)
        {
            if (!(res is Dictionary<string, object>)) return "";
            var lines = new List<string> { Json.Text(res, "text") };
            foreach (object l in Json.List(res, "lines")) if (l is string s) lines.Add(s);
            return string.Join("\n", lines);
        }

        public int PickSelection(int current)
        {
            var slots = Json.List(State, "slots");
            if (slots.Count == 0) return 0;
            foreach (object s in slots) if (Json.Int(s, "slot") == current) return current;
            foreach (object s in slots) if (Json.Bool(s, "active")) return Json.Int(s, "slot");
            return Json.Int(slots[0], "slot");
        }

        public void Select(int n)
        {
            if (Selected != n) ConfirmDelete = 0;
            Selected = n;
            var s = SlotOf(n);
            if (s != null && !Json.Bool(s, "empty")) IconChoice = Json.Text(s, "icon", IconChoice);
            else { var ic = Icons(); IconChoice = ic.Count > 0 ? ic[0] : "skills"; }
        }
        public void CycleIcon() { IconChoice = NextIcon(Icons(), IconChoice); }

        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void Save(string name) { if (Selected <= 0) return; PendingAction = "save"; PendingSlot = Selected; Send("save", new Dictionary<string, object> { { "slot", Selected }, { "name", name ?? "" }, { "icon", IconChoice } }); }
        public void Load() { if (Selected <= 0) return; PendingAction = "load"; PendingSlot = Selected; Send("load", new Dictionary<string, object> { { "slot", Selected } }); }
        public void Rename(string name) { if (Selected > 0) Send("rename", new Dictionary<string, object> { { "slot", Selected }, { "name", name ?? "" }, { "icon", IconChoice } }); }
        public void CancelSwitch() { Send("cancel"); }

        /// <summary>Delete asks to be clicked twice.</summary>
        public bool Delete()
        {
            if (Selected <= 0) return false;
            if (ConfirmDelete != Selected)
            {
                ConfirmDelete = Selected;
                var slot = SlotOf(Selected);
                Status = Loc.T("Click Confirm to delete {0}.", Json.Text(slot, "name")); StatusColor = Warn;
                return false;
            }
            ConfirmDelete = 0;
            Send("delete", new Dictionary<string, object> { { "slot", Selected } });
            return true;
        }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            switch (action)
            {
                case "state": State = d; StateAt = Clock(); Selected = PickSelection(Selected); var cs = SlotOf(Selected); if (cs != null && !Json.Bool(cs, "empty")) IconChoice = Json.Text(cs, "icon", IconChoice); else { var ic = Icons(); if (ic.Count > 0) IconChoice = ic[0]; } break;
                case "result":
                    Status = ResultTextOf(d); StatusColor = Json.Bool(d, "ok") ? Good : Bad;
                    if (Json.Bool(d, "ok") && PendingAction.Length > 0)
                    {
                        if (PendingAction == "save") ProfileSaved(PendingSlot); else if (PendingAction == "load") ProfileLoaded(PendingSlot);
                    }
                    PendingAction = "";
                    break;
                case "cast": Status = Loc.T("Switching loadout... stand still."); StatusColor = Active; CastStarted(Loc.T("Loadout"), Json.Number(d, "ms", 3000)); break;
                case "castEnd": if (Json.Text(d, "result", "done") != "done") PendingAction = ""; CastEnded(Json.Text(d, "result", "done")); break;
                default: return;
            }
            Changed();
        }

        public void Clear() { State = null; Visible = false; PendingAction = ""; ConfirmDelete = 0; Status = ""; }
    }

    // ------------------------------------------------------------------------------------------------ spell supports
    public sealed class SpellSupportsState
    {
        public const byte Opcode = 243;
        public static readonly Dictionary<string, string> KindShort = new Dictionary<string, string> { { "single", "single" }, { "area", "area" }, { "heal", "heal" }, { "buff", "buff" } };

        sealed class Part { public int Total, Got; public string[] Texts; }

        readonly ExtOpcodes ext;
        public object State;
        /// <summary>spell id (text) -> runes socketed, for the hotbar and the spellbook.</summary>
        public Dictionary<string, object> Bar = new Dictionary<string, object>();
        public Dictionary<string, object> BarWords = new Dictionary<string, object>();
        public double SelectedSpell = -1, SelectedRune = -1;
        public string Result = "";
        public bool ResultOk = true, Visible;
        public int ShatterSpell = -1, ShatterSlot = -1;
        public double ShatterUntil;
        readonly Dictionary<int, Part> parts = new Dictionary<int, Part>();
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public SpellSupportsState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public List<object> Spells() => Dicts(Json.List(State, "spells"));
        public List<object> Runes() => Dicts(Json.List(State, "runes"));
        static List<object> Dicts(List<object> l) { var o = new List<object>(); foreach (object x in l) if (x is Dictionary<string, object>) o.Add(x); return o; }

        public object SpellById(double id) { foreach (object s in Spells()) if (Json.Number(s, "id") == id) return s; return null; }
        public object RuneById(double id) { foreach (object r in Runes()) if (Json.Number(r, "id") == id) return r; return null; }
        public static object RuneAt(object spell, int slot) { foreach (object r in Json.List(spell, "runes")) if (r is Dictionary<string, object> && Json.Int(r, "slot") == slot) return r; return null; }

        public static string GoldText(double n) => n >= 1e6 ? (n / 1e6).ToString("0.0", CultureInfo.InvariantCulture) + "M" : n >= 1000 ? (int)Math.Floor(n / 1000) + "k" : ((long)n).ToString(CultureInfo.InvariantCulture);

        public static string RuneTip(object r) => Loc.T("{0}\n{1}.\nFits: {2} spells.", Json.Text(r, "name"), Json.Text(r, "text"), Json.Text(r, "fits"));

        /// <summary>The kind line of a spell row: "area, level 40".</summary>
        public static string KindLine(object spell) => Loc.T("{0}, level {1}", KindShort.TryGetValue(Json.Text(spell, "kind"), out string k) ? k : Json.Text(spell, "kind"), Json.Int(spell, "level"));

        public string InfoLine(object spell) => Loc.T("{0} spell, level {1}. Sockets open: {2} of {3} (2nd at level {4}, 3rd at level {5} with {6} {7}).",
            Json.Text(spell, "kindName", Json.Text(spell, "kind")), Json.Int(spell, "level"), Json.Int(spell, "count"), Json.Get(spell, "max") is double m ? (int)m : 3,
            Json.Int(spell, "secondLevel"), Json.Int(spell, "thirdLevel"), Json.Get(State, "orbsNeeded") is double on ? (int)on : 2, Loc.T("Orbs of Sockets"));

        /// <summary>What a socket row of a spell shows: the rune (or the empty / locked text) and its buttons.</summary>
        public sealed class SocketView { public string Name = "", Text = "", Button1 = "", Button2 = ""; public bool Button1On, Button2On, HasRune, Open; public object Rune; }

        public SocketView Socket(object spell, int slot, double now)
        {
            var v = new SocketView();
            int count = Json.Int(spell, "count");
            var r = RuneAt(spell, slot);
            if (r != null)
            {
                v.HasRune = true; v.Rune = r; v.Open = true;
                v.Name = Json.Text(r, "name") + (Json.Bool(r, "inactive") ? Loc.T(" (socket closed)") : "");
                v.Text = Json.Text(r, "text");
                v.Button1 = Loc.T("Remove") + " (" + GoldText(Json.Number(r, "cost")) + ")"; v.Button1On = true;
                bool armed = ShatterSpell == Json.Int(spell, "id") && ShatterSlot == slot && ShatterUntil > now;
                v.Button2 = armed ? Loc.T("Sure?") : Loc.T("Shatter"); v.Button2On = true;
            }
            else if (slot <= count)
            {
                v.Open = true; v.Name = Loc.T("Empty socket"); v.Text = Loc.T("Select a rune below and press Socket, or drag a rune here.");
                v.Button1 = Loc.T("Socket"); v.Button1On = SelectedRune >= 0;
            }
            else if (slot == 3 && !Json.Bool(spell, "opened"))
            {
                int need = Json.Get(State, "orbsNeeded") is double on ? (int)on : 2, have = Json.Int(State, "orbCount");
                v.Name = Loc.T("Locked socket");
                v.Text = Loc.T("Opens with {0} {1} (you have {2}). Needs level {3}.", need, Loc.T("Orbs of Sockets"), have, Json.Int(spell, "thirdLevel"));
                v.Button1 = Loc.T("Open"); v.Button1On = Json.Bool(spell, "canOpen") && have >= need;
            }
            else
            {
                v.Name = Loc.T("Locked socket");
                v.Text = Loc.T("Opens at level {0}.", slot == 2 ? Json.Int(spell, "secondLevel") : Json.Int(spell, "thirdLevel"));
            }
            return v;
        }

        public string RuneInfo(object r) => Loc.T("{0} (x{1}): {2}. Fits {3} spells.", Json.Text(r, "name"), Json.Int(r, "count"), Json.Text(r, "text"), Json.Text(r, "fits"));
        public bool CanCombine(object r) => r != null && Json.Bool(r, "combine") && Json.Int(r, "count") >= 3;

        // ---- requests
        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void SocketRune(int spell, int slot, int rune) { Send("socket", new Dictionary<string, object> { { "spell", spell }, { "slot", slot }, { "rune", rune } }); }
        public void SocketItem(int spell, int slot, Pos pos, int clientId)
        {
            Send("socket", new Dictionary<string, object> { { "spell", spell }, { "slot", slot }, { "pos", new Dictionary<string, object> { { "x", pos.X }, { "y", pos.Y }, { "z", pos.Z } } }, { "clientId", clientId } });
        }
        public void Remove(int spell, int slot, bool keep) { Send("remove", new Dictionary<string, object> { { "spell", spell }, { "slot", slot }, { "keep", keep } }); }
        public void Unlock(int spell) { Send("unlock", new Dictionary<string, object> { { "spell", spell } }); }
        public void Combine() { if (SelectedRune >= 0) Send("combine", new Dictionary<string, object> { { "rune", SelectedRune } }); }

        /// <summary>Shatter needs two clicks within three seconds.</summary>
        public bool Shatter(int spell, int slot, double now)
        {
            if (ShatterSpell == spell && ShatterSlot == slot && ShatterUntil > now) { ShatterSpell = -1; ShatterSlot = -1; Remove(spell, slot, false); return true; }
            ShatterSpell = spell; ShatterSlot = slot; ShatterUntil = now + 3000;
            return false;
        }

        /// <summary>The spellbook line: the rune names and the effects for its tooltip; null when the spell has no entry.</summary>
        public string BookLine(string words, out string tip)
        {
            tip = "";
            if (words == null || !BarWords.TryGetValue(words, out object idObj) || !(idObj is double id)) return null;
            if (!Bar.TryGetValue(((long)id).ToString(CultureInfo.InvariantCulture), out object runes) || !(runes is List<object> l) || l.Count == 0) return Loc.T("Supports: none socketed (Character > Spell Supports).");
            var names = new List<string>(); var fx = new List<string>();
            foreach (object r in l) { names.Add(Json.Text(r, "name")); fx.Add("  " + Json.Text(r, "name") + ": " + Json.Text(r, "text")); }
            tip = Loc.T("Supports") + ":\n" + string.Join("\n", fx);
            return Loc.T("Supports") + ": " + string.Join(", ", names) + ".";
        }

        /// <summary>The runes of a spell by id for the hotbar pips.</summary>
        public List<object> BarRunes(int spellId)
        {
            var o = new List<object>();
            if (Bar.TryGetValue(spellId.ToString(CultureInfo.InvariantCulture), out object r) && r is List<object> l) foreach (object x in l) if (x is Dictionary<string, object>) o.Add(x);
            return o;
        }

        // ---- server
        void OnPart(object d)
        {
            if (!(Json.Get(d, "id") is double id) || !(Json.Get(d, "index") is double index) || !(Json.Get(d, "total") is double total) || total < 1 || total > 64 || !(Json.Get(d, "text") is string text)) return;
            if (!parts.TryGetValue((int)id, out var p) || p.Total != (int)total) { p = new Part { Total = (int)total, Texts = new string[(int)total] }; parts[(int)id] = p; }
            int i = (int)index - 1;
            if (i < 0 || i >= p.Total) i = (int)index;   // the server counts from 1; tolerate a 0 based sender
            if (i < 0 || i >= p.Total) return;
            if (p.Texts[i] == null) { p.Texts[i] = text; p.Got++; }
            if (p.Got < p.Total) return;
            parts.Remove((int)id);
            object msg = Json.TryParse(string.Concat(p.Texts));
            if (msg is Dictionary<string, object> && Json.Text(msg, "action") != "part") Handle(Json.Text(msg, "action"), Json.Get(msg, "data"));
        }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            switch (action)
            {
                case "part": OnPart(d); return;
                case "state":
                    State = d; Visible = true;
                    if (SpellById(SelectedSpell) == null) { var sp = Spells(); SelectedSpell = sp.Count > 0 ? Json.Number(sp[0], "id") : -1; }
                    if (RuneById(SelectedRune) == null) SelectedRune = -1;
                    break;
                case "bar":
                    Bar = Json.Get(d, "spells") as Dictionary<string, object> ?? new Dictionary<string, object>();
                    BarWords = Json.Get(d, "words") as Dictionary<string, object> ?? new Dictionary<string, object>();
                    break;
                case "result": Result = Json.Text(d, "text"); ResultOk = Json.Bool(d, "ok", true); break;
                default: return;
            }
            Changed();
        }

        /// <summary>Opens for a spell of the spellbook (its Supports button).</summary>
        public void OpenFor(string words) { if (words != null && BarWords.TryGetValue(words, out object id) && id is double d) SelectedSpell = d; Open(); }

        public void Clear() { State = null; Bar.Clear(); BarWords.Clear(); parts.Clear(); Visible = false; SelectedSpell = SelectedRune = -1; Result = ""; }
    }

    // ------------------------------------------------------------------------------------------------ pact
    public sealed class PactBuildRow { public int Slot; public string Name = "", Sub = ""; public bool Saved, Editable; }
    public sealed class PactShelfRow { public string Key = "", Name = "", Button = "", Price = ""; public int Marks; public bool Owned, CanBuy, Monthly; }

    public sealed class PactState
    {
        public const byte Opcode = 222;
        readonly ExtOpcodes ext;
        public object Status;
        public bool Visible;
        public string Note = "", NoteColor = "#80c070";
        public int ArmedDelete;
        /// <summary>A build code the server sent for a loaded build: the passive tree asks the server for its preview.</summary>
        public Action<int, string> BuildCode = delegate { };
        public Action Changed = delegate { };

        public PactState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        static int N(object o, string k) => (int)Math.Floor(Json.Number(o, k));
        static string Plural(int count, string word) => count + " " + word + (count == 1 ? "" : "s");

        public string StatusTitle(out string line)
        {
            if (Status == null) { line = ""; return Loc.T("Loading..."); }
            if (Json.Bool(Status, "active"))
            {
                string title = Json.Text(Status, "title"); if (title.Length == 0) title = Json.Text(Status, "titleText");
                line = Loc.T("Until {0} ({1} left). Title: {2}.", Json.Text(Status, "ends", "?"), Plural(N(Status, "daysLeft"), "day"), title);
                return Loc.T("Chaos Pact active");
            }
            if (N(Status, "endsAt") > 0) { line = Loc.T("Ended {0}. Nothing is lost: extra tabs are withdraw-only, extra builds read-only.", Json.Text(Status, "ends")); return Loc.T("Chaos Pact ended"); }
            line = Loc.T("Perks for 30 days: +10% XP, stamina x1.5, remote stash deposit, room, slots, {0} Pact Marks a day and a title.", N(Status, "dailyMarks"));
            return Loc.T("No Chaos Pact");
        }

        public string ClaimText(out bool enabled)
        {
            enabled = false;
            if (Status == null || !Json.Bool(Status, "active")) return Loc.T("Daily Pact Marks");
            if (Json.Bool(Status, "canClaim")) { enabled = true; return Loc.T("Claim {0} Pact Marks", N(Status, "dailyMarks")); }
            return Loc.T("Claimed today");
        }

        public string MarksLine() => Status == null ? "" : Loc.T("Pact Marks: {0} (earned so far: {1}). They buy only the cosmetics below.", WorldText.Thousands(N(Status, "marks")), WorldText.Thousands(N(Status, "marksEarned")));

        public string MonthLine()
        {
            if (Status == null) return "";
            int m = N(Status, "monthExp"), a = N(Status, "monthExpAccount");
            if (m <= 0 && a <= 0) return Loc.T("This month the Pact has given you no extra experience yet.");
            if (a > m) return Loc.T("This month the Pact gave you {0} extra experience ({1} on all your characters).", WorldText.Thousands(m), WorldText.Thousands(a));
            return Loc.T("This month the Pact gave you {0} extra experience.", WorldText.Thousands(m));
        }

        public List<PactShelfRow> ShelfRows()
        {
            var o = new List<PactShelfRow>();
            int have = N(Status, "marks");
            foreach (object it in Json.List(Status, "shelf"))
            {
                int price = N(it, "marks");
                bool owned = Json.Bool(it, "owned"), monthly = Json.Bool(it, "monthly");
                string name = Json.Text(it, "name", Json.Text(it, "key"));
                if (monthly) name = Loc.T("{0} (this month)", name);
                o.Add(new PactShelfRow { Key = Json.Text(it, "key"), Name = name, Marks = price, Owned = owned, CanBuy = !owned && have >= price, Button = owned ? Loc.T("Owned") : Loc.T("Buy"), Price = Loc.T("{0} Marks", price), Monthly = monthly });
            }
            return o;
        }

        /// <summary>One limit row: label, free, pact, bought, total.</summary>
        public string[] LimitRow(object r)
        {
            string pact = N(r, "pact") > 0 ? "+" + N(r, "pact") : "-";
            if (N(r, "pact") > 0 && !Json.Bool(r, "pactActive")) pact += " (off)";
            string bought = N(r, "maxExtra") > 0 || N(r, "extra") > 0 ? N(r, "extra") + " / " + N(r, "maxExtra") : "-";
            return new[] { Json.Text(r, "label", Json.Text(r, "key", "?")), N(r, "free").ToString(), pact, bought, N(r, "total").ToString() };
        }

        public List<string[]> LimitRows()
        {
            var o = new List<string[]>();
            foreach (object r in Json.List(Status, "limits"))
            {
                var row = LimitRow(r);
                if (Json.Bool(r, "pactActive") && !Json.Bool(Status, "active") && N(r, "pact") > 0) row[2] += " (premium)";
                o.Add(row);
            }
            return o;
        }

        public string SpecialText()
        {
            var parts = new List<string>();
            foreach (object t in Json.List(Status, "special")) parts.Add(Loc.T(Json.Text(t, "name")) + (Json.Bool(t, "owned") ? Loc.T(" (owned)") : Loc.T(" (store)")));
            return parts.Count == 0 ? "" : Loc.T("Affinity stash tabs: {0}. The free stash tab holds {1} entries; Slot Expansions make it bigger.", string.Join(", ", parts), N(Status, "tabSize"));
        }

        public List<PactBuildRow> BuildRows()
        {
            var bySlot = new Dictionary<int, object>();
            int highest = N(Status, "buildLimit");
            foreach (object b in Json.List(Status, "builds")) { int s = N(b, "slot"); bySlot[s] = b; highest = Math.Max(highest, s); }
            var rows = new List<PactBuildRow>();
            for (int slot = 1; slot <= highest; slot++)
            {
                bool editable = slot <= N(Status, "buildLimit");
                if (bySlot.TryGetValue(slot, out object b))
                {
                    string cls = Json.Text(b, "cls");
                    string sub = (cls.Length > 0 ? WorldText.Cap(cls) + " line" : "no class") + ", " + Plural(N(b, "nodes"), "node");
                    if (!editable) sub += " - read-only";
                    rows.Add(new PactBuildRow { Slot = slot, Name = Json.Text(b, "name", "Build " + slot), Sub = sub, Saved = true, Editable = editable });
                }
                else rows.Add(new PactBuildRow { Slot = slot, Name = Loc.T("Empty slot"), Sub = editable ? Loc.T("Save your current tree here") : "", Editable = editable });
            }
            return rows;
        }

        public string BuildHeader() => Status == null ? "" : Loc.T("Saved builds: {0} of {1} slots (account-wide)", Json.List(Status, "builds").Count, N(Status, "buildLimit"));

        // ---- requests
        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public void Sync() { Send("sync"); }
        public void Claim() { Send("claim"); }
        public void Buy(string key) { Send("marksBuy", new Dictionary<string, object> { { "key", key } }); }
        public void Save(int slot, string name) { Send("buildSave", new Dictionary<string, object> { { "slot", slot }, { "name", name ?? "" } }); }
        public void Rename(int slot, string name) { Send("buildRename", new Dictionary<string, object> { { "slot", slot }, { "name", name ?? "" } }); }
        public void LoadBuild(int slot) { Send("buildLoad", new Dictionary<string, object> { { "slot", slot } }); }

        /// <summary>Delete asks to be clicked twice.</summary>
        public bool Delete(int slot)
        {
            if (ArmedDelete != slot) { ArmedDelete = slot; return false; }
            ArmedDelete = 0;
            Send("buildDelete", new Dictionary<string, object> { { "slot", slot } });
            return true;
        }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            switch (action)
            {
                case "status": Status = d; ArmedDelete = 0; if (Json.Bool(d, "open")) Visible = true; break;
                case "buildCode": BuildCode(N(d, "slot"), Json.Text(d, "code")); break;
                case "message": Note = Json.Text(d, "text"); NoteColor = Json.Bool(d, "error") ? "#e07060" : "#80c070"; break;
                default: return;
            }
            Changed();
        }

        public void Clear() { Status = null; Visible = false; ArmedDelete = 0; Note = ""; }
    }

    // ------------------------------------------------------------------------------------------------ candlemarks
    public sealed class CandleOffer
    {
        public string Key = "", Name = "", Boss = "", Desc = "", Kind = "item", Why = "";
        public int Price, Weekly, Used, Level, Cid;
        public bool Owned, CanBuy;
    }

    public sealed class CandlemarksState
    {
        public const byte Opcode = 176;
        public const int MaxOffers = 80;
        public const string Visit = "Visit Osric the Chandler to buy (in the market of the teleport room).";

        readonly ExtOpcodes ext;
        public object Hud, State;
        public double HudAt, StateAt;
        public bool Visible, Buying;
        public string Result = "", ResultColor = "#d6c9ae";
        public Func<double> Clock = () => 0;
        public Action Changed = delegate { };

        public CandlemarksState(ExtOpcodes e) { ext = e; ext.On(Opcode, m => Handle(m.Action, m.Data)); }

        void Send(string action, Dictionary<string, object> data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        static int I(object o, string k) { double v = Json.Number(o, k); return double.IsNaN(v) || double.IsInfinity(v) ? 0 : (int)v; }
        static int Any(object o, string a, string b) => Json.Get(o, a) != null ? I(o, a) : I(o, b);

        /// <summary>The counter: balance, minutes-to-next in seconds, earning, why not.</summary>
        public static void Counter(object h, double sinceSec, out int balance, out int left, out bool earning, out string why)
        {
            balance = Math.Max(0, Any(h, "b", "balance"));
            int block = Math.Max(60, Any(h, "n", "block")), progress = Math.Max(0, Any(h, "p", "progress"));
            earning = Json.Bool(h, "e") || Json.Bool(h, "earning");
            left = block - progress;
            if (earning) left -= (int)Math.Max(0, sinceSec);
            left = Math.Max(0, Math.Min(block, left));
            why = Json.Text(h, "w", Json.Text(h, "why"));
        }

        public static int Minutes(double seconds) => (int)Math.Floor((Math.Max(0, seconds) + 59) / 60);

        public string CounterText()
        {
            Counter(Hud, (Clock() - HudAt) / 1000, out int b, out int left, out bool earning, out _);
            return earning ? Loc.T("{0} Candlemarks, next in {1} min", b, Minutes(left)) : Loc.T("{0} Candlemarks (paused)", b);
        }

        public static string WhyText(string why)
        {
            switch (why)
            {
                case "ip": return Loc.T("Two other characters of your connection are earning. You keep your progress and earn again when one logs out.");
                case "staff": return Loc.T("Staff characters do not earn Candlemarks.");
                case "level": return Loc.T("Your character is below the level that earns Candlemarks.");
            }
            return Loc.T("Not earning right now. Your progress is kept.");
        }

        public string CounterTip()
        {
            Counter(Hud, (Clock() - HudAt) / 1000, out _, out _, out bool earning, out string why);
            return earning ? Loc.T("One Candlemark for every 30 minutes online, for your account. Click to open the shop.") : WhyText(why);
        }

        static string Str(object v, string fallback) { string s = v as string; if (string.IsNullOrEmpty(s)) return fallback; return s.Length > 96 ? s.Substring(0, 96) : s; }

        public List<CandleOffer> Offers()
        {
            var o = new List<CandleOffer>();
            int balance = I(State, "balance"), level = I(State, "level");
            foreach (object r in Json.List(State, "offers"))
            {
                string k = Json.Text(r, "k");
                if (!(r is Dictionary<string, object>) || k.Length == 0 || k.Length > 80) continue;
                var c = new CandleOffer
                {
                    Key = k, Name = Str(Json.Get(r, "n"), k), Boss = Str(Json.Get(r, "b"), ""), Desc = Str(Json.Get(r, "d"), ""), Price = Math.Max(0, I(r, "p")), Weekly = Math.Max(0, I(r, "w")),
                    Used = Math.Max(0, I(r, "u")), Level = Math.Max(0, I(r, "l")), Kind = Json.Text(r, "kind", "item"), Owned = Json.Bool(r, "own"),
                };
                int cid = I(r, "c");
                c.Cid = cid >= 1 && cid <= 65535 ? cid : 0;
                if (c.Owned) c.Why = Loc.T("Owned");
                else if (c.Weekly > 0 && c.Used >= c.Weekly) c.Why = Loc.T("Weekly limit reached");
                else if (level < c.Level) c.Why = Loc.T("Level {0}", c.Level);
                else if (balance < c.Price) c.Why = Loc.T("Not enough Candlemarks");
                if (c.Why.Length == 0 && Json.Get(State, "near") is bool nb && !nb) c.Why = Loc.T(Visit);
                c.CanBuy = c.Why.Length == 0;
                o.Add(c);
                if (o.Count >= MaxOffers) break;
            }
            return o;
        }

        public static string OfferTitle(CandleOffer r) => r.Boss.Length > 0 ? r.Name + ": " + r.Boss : r.Name;
        public static string OfferPrice(CandleOffer r) => Loc.T("{0} Candlemarks", r.Price);
        public static string OfferLimit(CandleOffer r) => r.Weekly > 0 ? Loc.T("This week: {0} of {1}", r.Used, r.Weekly) : "";

        public string HeaderBalance() { Counter(State, (Clock() - StateAt) / 1000, out int b, out _, out _, out _); return Loc.T("Your account has {0} Candlemarks", b); }
        public string HeaderNext()
        {
            Counter(State, (Clock() - StateAt) / 1000, out _, out int left, out bool earning, out string why);
            return earning ? Loc.T("Next Candlemark in {0} min", Minutes(left)) : WhyText(why);
        }
        public string HeaderWeek()
        {
            int days = (int)Math.Floor(Math.Max(0, Json.Number(State, "weekEnds") - Math.Max(0, (Clock() - StateAt) / 1000)) / 86400);
            return days >= 1 ? Loc.T("Weekly limits reset in {0} days", days) : Loc.T("Weekly limits reset within a day");
        }
        public string HeaderShop() => Json.Get(State, "near") is bool nb && !nb ? Loc.T(Visit) : Loc.T("Osric the Chandler is here: you can buy.");

        public void Open() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Visible = false; else Open(); }
        public bool Buy(CandleOffer c)
        {
            if (c == null || !c.CanBuy || Buying) return false;
            Buying = true;
            Send("buy", new Dictionary<string, object> { { "k", c.Key } });
            return true;
        }

        public void Handle(string action, object d)
        {
            if (!(d is Dictionary<string, object>)) return;
            switch (action)
            {
                case "hud": Hud = d; HudAt = Clock(); break;
                case "state": State = d; StateAt = Clock(); Buying = false; break;
                case "result": Buying = false; Result = Json.Text(d, "text"); ResultColor = Json.Bool(d, "ok") ? "#70d070" : "#e05040"; break;
                case "npc": Open(); break;
                default: return;
            }
            Changed();
        }

        public void Clear() { Hud = null; State = null; Visible = false; Buying = false; Result = ""; }
    }
}
