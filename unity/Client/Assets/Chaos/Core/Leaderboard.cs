// Leaderboards (client game_leaderboard, extended opcode 229, server leaderboard.lua + records.lua).
//   Boards   server -> client  meta {open, boards [{key, name, weekly, value, count, title, info, byClass, format, classAwards}], groups [{key, name}], ownGroup, season}
//                              | board {key, group, week, resetIn, rows [{rank, name, value, count, level, vocation, title, fallen}], own {rank, value, count},
//                                       champions [{rank, rankName, name, value, title}], total, championGroup, season}
//            client -> server  open {board} | get {board, group, season, mode}
//   Records  server -> client  rcat {cat, boards} (parts of the meta) | rmeta {categories, periods, groups, parts, season, badge}
//                              | rboard {board, variant, size, period, group, rows, own, total, record, resetIn, seasonName}
//                              | rfirsts {season, seasonName, rows [{target, board, name, members, at, value, format}]} | rmine {rows [{key, name, value}]}
//            client -> server  rmeta | rget {board, variant, size, period, group} | rfirsts | rmine
// The weekly boards are a pick list sorted by the name shown (accents folded); the board chosen is kept per character (PlayerPrefs, by the app).
// Values show as exact numbers (the main client's short numbers are not ported); the "time" format shows m:ss.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    public static class LeaderboardMath
    {
        public const string DefaultBoard = "worldboss";

        /// <summary>The sort form of a name: accents folded to their base letter, lower case.</summary>
        public static string Fold(string s) => TopMenu.SortKey(s);

        public sealed class Option { public string Key = "", Text = ""; public object Board; }

        /// <summary>The boards of the meta as options sorted by the name shown.</summary>
        public static List<Option> Options(object meta)
        {
            var o = new List<Option>();
            foreach (var b in SFmt.Rows(meta, "boards"))
            {
                string key = Json.Get(b, "key") is string s ? s : Json.Get(b, "key") is double d ? ((long)d).ToString(CultureInfo.InvariantCulture) : "";
                if (key.Length == 0) continue;
                string name = Json.Text(b, "name", key);
                o.Add(new Option { Key = key, Text = Loc.T(name), Board = b });
            }
            o.Sort((x, y) => { int c = string.CompareOrdinal(Fold(x.Text), Fold(y.Text)); return c != 0 ? c : string.CompareOrdinal(x.Key, y.Key); });
            return o;
        }

        /// <summary>The board to show: the wanted one when it is an option, else World Boss, else the first option.</summary>
        public static string Resolve(List<Option> opts, string wanted)
        {
            foreach (var o in opts) if (o.Key == wanted) return o.Key;
            foreach (var o in opts) if (o.Key == DefaultBoard) return o.Key;
            return opts.Count > 0 ? opts[0].Key : null;
        }

        public static string ValueText(double v, string format)
        {
            long n = (long)Math.Max(0, Math.Floor(v));
            if (format == "time")
            {
                if (n >= 3600) return (n / 3600) + ":" + (n % 3600 / 60).ToString("00", CultureInfo.InvariantCulture) + ":" + (n % 60).ToString("00", CultureInfo.InvariantCulture);
                return (n / 60) + ":" + (n % 60).ToString("00", CultureInfo.InvariantCulture);
            }
            if (format == "pct") return (v / 100).ToString("0.00", CultureInfo.InvariantCulture) + "%";
            return SFmt.Money(v);
        }

        public static string Ordinal(int n) => n + (n == 1 ? "st" : n == 2 ? "nd" : n == 3 ? "rd" : "th");

        /// <summary>"Weekly reset in 3d 02h 10m" with the time left counted down by elapsed seconds.</summary>
        public static string ResetText(double left)
        {
            long s = (long)Math.Max(0, Math.Floor(left));
            long d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60, sec = s % 60;
            string t = d > 0 ? d + "d " + h.ToString("00", CultureInfo.InvariantCulture) + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m"
                : h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m " + sec.ToString("00", CultureInfo.InvariantCulture) + "s";
            return Loc.T("Weekly reset in {0}", t);
        }

        public static string DateText(double at)
        {
            if (at <= 0) return "";
            return DateTimeOffset.FromUnixTimeSeconds((long)at).UtcDateTime.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        }

        public static string OwnText(object board, object data)
        {
            object own = Json.Get(data, "own");
            if (!SFmt.IsMap(own)) return Loc.T("You have no result on this board in this view yet.");
            return Loc.T("Your rank: #{0} of {1}   -   {2}: {3}", Json.Int(own, "rank"), Json.Int(data, "total"), Json.Text(board, "value", "Best"), ValueText(Json.Number(own, "value"), Json.Text(board, "format")));
        }

        public static string RecordText(object board, object data) =>
            SFmt.Has(data, "record") ? Loc.T("All-time record: {0}", ValueText(Json.Number(data, "record"), Json.Text(board, "format"))) : Loc.T("No all-time record yet: be the first.");

        /// <summary>The filters of a record board kept valid: a filter the board does not have is dropped, one it has but is not valid becomes the first.</summary>
        public static Dictionary<string, object> Request(object board, string period, string variant, string size, string group)
        {
            var r = new Dictionary<string, object> { { "board", Json.Text(board, "key") }, { "period", period } };
            if (Json.List(board, "variants").Count > 0) r["variant"] = variant;
            if (Json.List(board, "sizes").Count > 0) r["size"] = size;
            if (Json.Truthy(board, "byClass") && group.Length > 0) r["group"] = group;
            return r;
        }
    }

    public sealed class LeaderboardPanel : SocialPanel
    {
        public const byte Opcode = 229;
        readonly ExtOpcodes ext;
        public object Meta, Current, RMeta, RCurrent;
        public string Selected = "";
        public Func<double> Clock = () => 0;
        double boardAt, rAt;
        readonly Dictionary<string, List<object>> rparts = new Dictionary<string, List<object>>();
        int rpartsCount;
        public bool RMetaComplete;
        List<object> rcats = new List<object>();
        /// <summary>The board kept per character: read at the first meta, written at a pick (the app stores it in PlayerPrefs).</summary>
        public Func<string> SavedBoard = () => null;
        public Action<string> RememberBoard = delegate { };

        public LeaderboardPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("boards", "Weekly Boards"));
            Tabs.Add(new KeyValuePair<string, string>("records", "Records"));
            Tab = "boards";
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Send("open", SFmt.Map("board", Selected.Length > 0 ? Selected : (SavedBoard() ?? ""))); }
        public override void Clear() { base.Clear(); Meta = Current = RMeta = RCurrent = null; Selected = ""; rparts.Clear(); rpartsCount = 0; RMetaComplete = false; rcats.Clear(); Tab = "boards"; }

        public override void SelectTab(string key)
        {
            Tab = key;
            if (key == "records") { if (RMetaComplete) AskRecord(); else { rparts.Clear(); rpartsCount = 0; Send("rmeta"); } }
            else if (Selected.Length > 0) AskBoard();
            Changed();
        }

        // ------------------------------------------------------------------------------------ messages
        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "meta":
                    Meta = d;
                    if (Json.Truthy(d, "open")) { Visible = true; if (Tab == "records") { Tab = "boards"; } }
                    if (Json.Truthy(d, "open") || Selected.Length == 0)
                    {
                        if (Json.Truthy(d, "open")) { Form.Remove("season"); Form.Remove("mode"); }
                        Selected = LeaderboardMath.Resolve(LeaderboardMath.Options(d), Selected.Length > 0 ? Selected : SavedBoard()) ?? "";
                        if (!Form.ContainsKey("group") && Json.Get(d, "ownGroup") != null) SetGroupByKey(Json.Get(d, "ownGroup"));
                        if (Selected.Length > 0) AskBoard();
                    }
                    break;
                case "board":
                    string key = Json.Get(d, "key") is string ks ? ks : Json.Get(d, "key") is double kd ? ((long)kd).ToString(CultureInfo.InvariantCulture) : "";
                    Current = d; boardAt = Clock();
                    if (key.Length > 0) Selected = key;
                    break;
                case "rcat":
                    if (Json.Text(d, "cat").Length > 0)
                    {
                        if (!rparts.TryGetValue(Json.Text(d, "cat"), out var lst)) rparts[Json.Text(d, "cat")] = lst = new List<object>();
                        foreach (var b in SFmt.Rows(d, "boards")) if (Json.Text(b, "key").Length > 0) lst.Add(b);
                        rpartsCount++;
                    }
                    break;
                case "rmeta":
                    RMeta = d; rcats.Clear();
                    foreach (var c in SFmt.Rows(d, "categories"))
                    {
                        var cat = new Dictionary<string, object>((Dictionary<string, object>)c);
                        cat["boards"] = rparts.TryGetValue(Json.Text(c, "key"), out var bl) ? bl : new List<object>();
                        rcats.Add(cat);
                    }
                    rcats.Add(SFmt.Map("key", "firsts", "name", Loc.T("Realm Firsts"), "boards", new List<object>(), "info", Loc.T("The first player or party to defeat each boss this season.")));
                    rcats.Add(SFmt.Map("key", "mine", "name", Loc.T("My Records"), "boards", new List<object>(), "info", Loc.T("Your own best drop, highest Tower floor and rift tier, and your fastest boss kills.")));
                    RMetaComplete = Json.Int(d, "parts") == rpartsCount;
                    if (RMetaComplete && Tab == "records") AskRecord();
                    break;
                case "rboard": if (Json.Text(d, "board") == CurrentRecordBoardKey()) { RCurrent = d; rAt = Clock(); } break;
                case "rfirsts": RCurrent = SFmt.Map("isFirsts", true, "rows", Json.Get(d, "rows"), "seasonName", Json.Get(d, "seasonName")); rAt = Clock(); break;
                case "rmine": RCurrent = SFmt.Map("isMine", true, "rows", Json.Get(d, "rows")); rAt = Clock(); break;
            }
            Changed();
        }

        // ------------------------------------------------------------------------------------ boards
        public object BoardMeta(string key) { foreach (var b in SFmt.Rows(Meta, "boards")) if (Json.Get(b, "key") is string s ? s == key : Json.Get(b, "key") is double dd && ((long)dd).ToString(CultureInfo.InvariantCulture) == key) return b; return null; }

        List<object> Groups()
        {
            var g = SFmt.Rows(Meta, "groups");
            object b = BoardMeta(Selected);
            if (Json.Truthy(b, "weekly") && Json.Truthy(b, "byClass")) g.Insert(0, SFmt.Map("key", "all", "name", Loc.T("All classes")));
            return g;
        }

        static string KeyText(object o) => o is string s ? s : o is double d ? ((long)d).ToString(CultureInfo.InvariantCulture) : "";

        void SetGroupByKey(object key)
        {
            var groups = Groups();
            for (int i = 0; i < groups.Count; i++) if (KeyText(Json.Get(groups[i], "key")) == KeyText(key)) { Form["group"] = i.ToString(CultureInfo.InvariantCulture); return; }
        }

        object GroupKey()
        {
            var groups = Groups();
            int i = Index("group", -1);
            if (i < 0 || i >= groups.Count) return null;
            object k = Json.Get(groups[i], "key");
            return k as string == "all" ? null : k;
        }

        public void AskBoard()
        {
            if (Selected.Length == 0) return;
            var req = new Dictionary<string, object> { { "board", Selected } };
            object g = GroupKey();
            object b = BoardMeta(Selected);
            if (g != null && (!Json.Truthy(b, "weekly") || Json.Truthy(b, "byClass"))) req["group"] = g;
            if (Index("season") == 1) { req["season"] = true; var modes = Json.List(Json.Get(Meta, "season"), "modes"); int mi = Index("mode"); if (mi > 0 && mi < modes.Count + 1) req["mode"] = Json.Text(modes[mi - 1], "key"); }
            Send("get", req);
        }

        public override void OnForm(string key)
        {
            if (Tab == "boards")
            {
                if (key == "board")
                {
                    var opts = LeaderboardMath.Options(Meta);
                    int i = Index("board", -1);
                    if (i >= 0 && i < opts.Count && opts[i].Key != Selected) { Selected = opts[i].Key; RememberBoard(Selected); Form.Remove("group"); AskBoard(); }
                }
                else if (key == "group" || key == "season" || key == "mode") AskBoard();
            }
            else
            {
                if (key == "rcat") { Form.Remove("rboard"); AskRecord(); }
                else if (key == "rboard" || key == "period" || key == "variant" || key == "size" || key == "rgroup") AskRecord();
            }
        }

        // ------------------------------------------------------------------------------------ records
        object RCat() { int i = Index("rcat"); return i >= 0 && i < rcats.Count ? rcats[i] : (rcats.Count > 0 ? rcats[0] : null); }
        public object RBoard() { var boards = Json.List(RCat(), "boards"); int i = Index("rboard"); return i >= 0 && i < boards.Count ? boards[i] : (boards.Count > 0 ? boards[0] : null); }
        string CurrentRecordBoardKey() => Json.Text(RBoard(), "key");

        public void AskRecord()
        {
            object cat = RCat();
            string ck = Json.Text(cat, "key");
            if (ck == "firsts") { Send("rfirsts"); return; }
            if (ck == "mine") { Send("rmine"); return; }
            object b = RBoard();
            if (b == null) return;
            var periods = SFmt.Rows(RMeta, "periods");
            string period = periods.Count > 0 ? Json.Text(periods[Math.Max(0, Math.Min(periods.Count - 1, Index("period")))], "key") : "week";
            var variants = SFmt.Rows(b, "variants"); var sizes = SFmt.Rows(b, "sizes"); var groups = SFmt.Rows(RMeta, "groups");
            string variant = variants.Count > 0 ? Json.Text(variants[Math.Max(0, Math.Min(variants.Count - 1, Index("variant")))], "key") : "";
            string size = sizes.Count > 0 ? Json.Text(sizes[Math.Max(0, Math.Min(sizes.Count - 1, Index("size")))], "key") : "";
            int gi = Index("rgroup");
            string group = gi > 0 && gi <= groups.Count ? KeyText(Json.Get(groups[gi - 1], "key")) : "";
            Send("rget", LeaderboardMath.Request(b, period, variant, size, group));
        }

        // ------------------------------------------------------------------------------------ rows
        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (Tab == "records") RecordRows(l); else BoardRows(l);
            return l.Rows;
        }

        static string RankTone(int rank) => rank == 1 ? "#e8b84a" : rank == 2 ? "#a8b4c8" : rank == 3 ? "#c87a3a" : "";

        void BoardRows(RowList l)
        {
            if (Meta == null) { l.Text(Loc.T("Loading..."), "dim"); return; }
            var opts = LeaderboardMath.Options(Meta);
            var names = new List<string>(); foreach (var o in opts) names.Add(o.Text);
            int sel = opts.FindIndex(o => o.Key == Selected);
            if (sel >= 0 && !Form.ContainsKey("board")) Form["board"] = sel.ToString(CultureInfo.InvariantCulture);
            if (sel >= 0) Form["board"] = sel.ToString(CultureInfo.InvariantCulture);
            l.Combo(Loc.T("Board"), "board", names);
            object b = BoardMeta(Selected);
            if (Json.Text(b, "info").Length > 0) l.Text(Json.Text(b, "info"), "dim");
            bool weekly = Json.Truthy(b, "weekly"), byClass = Json.Truthy(b, "byClass");
            if (!weekly || byClass)
            {
                var gn = new List<string>(); foreach (var g in Groups()) gn.Add(Json.Text(g, "name", "?"));
                l.Combo(weekly ? Loc.T("Class") : Loc.T("Class line"), "group", gn);
            }
            object season = Json.Get(Meta, "season");
            if (SFmt.IsMap(season))
            {
                l.Combo(Loc.T("Characters"), "season", new List<string> { Loc.T("All characters"), Loc.T("{0} only", Json.Text(season, "tag", Loc.T("Season"))) });
                var modes = SFmt.Rows(season, "modes");
                if (Index("season") == 1 && modes.Count > 0) { var mn = new List<string> { Loc.T("All modes") }; foreach (var m in modes) mn.Add(Json.Text(m, "name", Json.Text(m, "key"))); l.Combo(Loc.T("Mode"), "mode", mn); }
            }
            if (Current == null) { l.Text(Loc.T("Loading..."), "dim"); return; }
            if (weekly)
            {
                l.Text(LeaderboardMath.ResetText(Json.Number(Current, "resetIn") - (Clock() - boardAt) / 1000.0), "dim");
                var champs = SFmt.Rows(Current, "champions");
                l.Section(Json.Truthy(b, "classAwards") ? Loc.T("Last week's podium (the top 3 of every class get Conquest Tokens)") : Loc.T("{0}: the title holders this week (last week's top 3)", Json.Text(b, "title")));
                if (champs.Count == 0) l.Text(Json.Truthy(b, "classAwards") ? Loc.T("Nobody yet: the podium of every class is rewarded on Monday.") : Loc.T("Nobody yet: the top 3 of this week get the title on Monday."), "dim");
                foreach (var c in champs) l.Text((Json.Text(c, "rankName").Length > 0 ? Json.Text(c, "rankName") : LeaderboardMath.Ordinal(Json.Int(c, "rank"))) + " " + Json.Text(c, "name", "?") + "  -  " + LeaderboardMath.ValueText(Json.Number(c, "value"), Json.Text(b, "format")));
            }
            else l.Text(Loc.T("Every class of the line counts. Updated every few minutes."), "dim");
            string valueName = weekly ? Json.Text(b, "value", Loc.T("Value")) : Loc.T("Level");
            l.Section(Loc.T("Rank") + "  -  " + valueName + (weekly && Json.Text(b, "count").Length > 0 ? "  -  " + Json.Text(b, "count") : ""));
            var rows = SFmt.Rows(Current, "rows");
            if (rows.Count == 0) l.Text(weekly ? Loc.T("No scores on this board yet this week.") : Loc.T("No characters of this class yet."), "dim");
            foreach (var r in rows)
            {
                int rank = Json.Int(r, "rank");
                string right = weekly ? LeaderboardMath.ValueText(Json.Number(r, "value"), Json.Text(b, "format")) + (Json.Text(b, "count").Length > 0 ? "   " + SFmt.Money(Json.Number(r, "count")) : "")
                    : (SFmt.Has(r, "level") ? Json.Int(r, "level") : Json.Int(r, "value")) + "   " + Json.Text(r, "vocation");
                var row = l.Row("#" + rank + "  " + Json.Text(r, "name", "?") + (Json.Text(r, "title").Length > 0 ? "  [" + Json.Text(r, "title") + "]" : ""), right, RankTone(rank));
                object fallen = Json.Get(r, "fallen");
                if (SFmt.IsMap(fallen)) { row.Tip = Loc.T("Fallen in Hardcore at level {0} ({1}).", Json.Int(fallen, "level"), Json.Text(fallen, "cause")); row.Tone = "dim"; }
            }
            object own = Json.Get(Current, "own");
            if (SFmt.IsMap(own))
                l.Text(weekly ? Loc.T("Your rank: #{0} of {1}   -   {2}: {3}", Json.Int(own, "rank"), Json.Int(Current, "total"), Json.Text(b, "value", Loc.T("Score")), LeaderboardMath.ValueText(Json.Number(own, "value"), Json.Text(b, "format")))
                    : Loc.T("Your rank in the line: #{0}   -   level {1}", Json.Int(own, "rank"), Json.Int(own, "value")), "gold");
            else l.Text(weekly ? Loc.T("You have no score on this board this week.") : Loc.T("Your class is not on this ladder."), "dim");
            l.Text(weekly ? Loc.T("Top 3 on Monday: the title {0} for a week, orbs to the inbox.", Json.Text(b, "title")) : Loc.T("Levels are read from the saved characters."), "dim");
        }

        void RecordRows(RowList l)
        {
            if (!RMetaComplete) { l.Text(Loc.T("Loading..."), "dim"); return; }
            var cn = new List<string>(); foreach (var c in rcats) cn.Add(Json.Text(c, "name", Json.Text(c, "key")));
            l.Combo(Loc.T("Category"), "rcat", cn);
            object cat = RCat();
            if (Json.Text(cat, "info").Length > 0) l.Text(Json.Text(cat, "info"), "dim");
            string ck = Json.Text(cat, "key");
            if (ck != "firsts" && ck != "mine")
            {
                var boards = SFmt.Rows(cat, "boards");
                var bn = new List<string>(); foreach (var b in boards) bn.Add(Json.Text(b, "name", Json.Text(b, "key")));
                l.Combo(Loc.T("Board"), "rboard", bn);
                object board = RBoard();
                var pn = new List<string>(); foreach (var p in SFmt.Rows(RMeta, "periods")) pn.Add(Json.Text(p, "name", Json.Text(p, "key")));
                if (pn.Count > 0) l.Combo(Loc.T("Period"), "period", pn);
                var vn = new List<string>(); foreach (var v in SFmt.Rows(board, "variants")) vn.Add(Json.Text(v, "name", Json.Text(v, "key")));
                if (vn.Count > 0) l.Combo(Loc.T("Variant"), "variant", vn);
                var sn = new List<string>(); foreach (var v in SFmt.Rows(board, "sizes")) sn.Add(Json.Text(v, "name", Json.Text(v, "key")));
                if (sn.Count > 0) l.Combo(Loc.T("Size"), "size", sn);
                if (Json.Truthy(board, "byClass")) { var gn = new List<string> { Loc.T("All classes") }; foreach (var g in SFmt.Rows(RMeta, "groups")) gn.Add(Json.Text(g, "name", "?")); l.Combo(Loc.T("Class"), "rgroup", gn); }
            }
            if (RCurrent == null) { l.Text(Loc.T("Loading..."), "dim"); return; }
            var rows = SFmt.Rows(RCurrent, "rows");
            if (Json.Truthy(RCurrent, "isMine"))
            {
                l.Section(Loc.T("My Records"));
                foreach (var r in rows) l.Row(Json.Text(r, "name"), Json.Get(r, "value") is double dv ? SFmt.Money(dv) : Json.Text(r, "value"));
                if (rows.Count == 0) l.Text(Loc.T("No records yet."), "dim");
            }
            else if (Json.Truthy(RCurrent, "isFirsts"))
            {
                l.Section(Loc.T("Realm firsts of {0}", Json.Text(RCurrent, "seasonName")));
                foreach (var r in rows)
                    l.Row(Json.Text(r, "members", "?") + "  -  " + Json.Text(r, "name", Json.Text(r, "board")), LeaderboardMath.DateText(Json.Number(r, "at")) + (SFmt.Has(r, "value") && Json.Text(r, "format") == "time" ? "  " + LeaderboardMath.ValueText(Json.Number(r, "value"), "time") : "")).Tip = Loc.T("{0}: realm first of {1}.", Json.Text(r, "board"), Json.Text(RCurrent, "seasonName"));
                if (rows.Count == 0) l.Text(Loc.T("No boss has fallen yet this season."), "dim");
            }
            else
            {
                object board = RBoard();
                if (SFmt.Has(RCurrent, "resetIn")) l.Text(LeaderboardMath.ResetText(Json.Number(RCurrent, "resetIn") - (Clock() - rAt) / 1000.0), "dim");
                l.Text(LeaderboardMath.RecordText(board, RCurrent), "gold");
                foreach (var r in rows)
                {
                    int party = Json.Int(r, "party", 1);
                    var row = l.Row("#" + Json.Int(r, "rank") + "  " + Json.Text(r, "name", "?") + "  " + (party > 1 ? Loc.T("party of {0}", party) : Json.Text(r, "vocation")),
                        LeaderboardMath.ValueText(Json.Number(r, "value"), Json.Text(board, "format")) + "  " + LeaderboardMath.DateText(Json.Number(r, "at")), RankTone(Json.Int(r, "rank")));
                    if (party > 1) row.Tip = Json.Text(r, "members");
                }
                if (rows.Count == 0) l.Text(Loc.T("No result on this board in this view yet."), "dim");
                l.Text(LeaderboardMath.OwnText(board, RCurrent), "gold");
            }
        }
    }
}
