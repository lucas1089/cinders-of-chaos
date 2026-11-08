// Community modules, part 2 (O433 phase 5, track S): game_community (opcode 203, goal bar and Brazier), game_chronicle (171, Ashen Chronicle and Memorial),
// game_mentor (194), game_patchnotes (244). SocialPanels like part 1 (Core/Community.cs); rules from the main client's communityview.lua, chronicleview.lua,
// mentorview.lua and patchnotesview.lua.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace Chaos.Core
{
    // ====================================================================================================== game_community (203)
    /// <summary>The community goal: bar with four stages and the buff each lights, your contribution, the top, the week's world modifiers, and the Brazier (donate gold).
    /// client -> server: open | close | donate {gold}; server -> client: state {goal {n, d, left, target, p, pct, rn}, stages [{i, pct, key, n, d, h, done, left}], sources [{k, n, cap, mine}],
    /// mine {p, today, cap, rank, token, tokenText, title, top}, top [{n, p}], week {mods [{k, n, d}], left, staff}, brazier {near, min, max, gold, per, room}} | msg {text, ok} | brazier {}.</summary>
    public sealed class CommunityGoalPanel : CommunityPanel
    {
        public const byte Opcode = 203;
        public object Data;
        public double Arrived;
        double msgAt;

        public CommunityGoalPanel(ExtOpcodes e) : base(e, Opcode)
        {
            Tabs.Add(new KeyValuePair<string, string>("goal", "Goal"));
            Tabs.Add(new KeyValuePair<string, string>("brazier", "Brazier"));
            Tab = "goal";
        }

        public double Elapsed => Math.Max(0, (NowMs - Arrived) / 1000);
        public override void Show() { Visible = true; Send("open"); }
        public override void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public override void Clear() { base.Clear(); Data = null; Tab = "goal"; }

        protected override void Handle(string action, object data)
        {
            switch (action)
            {
                case "state": Data = data; Arrived = NowMs; break;
                case "msg": Status = Json.Text(data, "text"); StatusTone = Json.Bool(data, "ok") ? "good" : "bad"; msgAt = NowMs; break;
                case "brazier": Tab = "brazier"; if (!Visible) Show(); else Send("open"); break;
            }
        }

        /// <summary>The message line goes away after a few seconds.</summary>
        public void Poll(double now) { if (Status.Length > 0 && now - msgAt > 6000) { Status = ""; Changed(); } }

        // ---- rules (communityview.lua)
        public static string Fmt(double n) => SFmt.Money(n);
        public static double Left(double seconds, double elapsed) => Math.Max(0, seconds - Math.Max(0, elapsed));

        public static int BarPercent(object data) => (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(Json.Get(data, "goal"), "pct"))));

        public static string BarText(object data)
        {
            var g = Json.Get(data, "goal");
            return Fmt(Json.Number(g, "p")) + " / " + Fmt(Json.Number(g, "target")) + "  (" + SFmt.Pct(Json.Number(g, "pct")) + "%)";
        }

        public static string StageState(object s, double elapsed)
        {
            if (s != null && Json.Get(s, "left") != null && Left(Json.Number(s, "left"), elapsed) > 0) return "open";
            return Json.Bool(s, "done") ? "done" : "todo";
        }

        public static string StageLine(object s, double elapsed, out string tone)
        {
            string st = StageState(s, elapsed);
            if (st == "open") { tone = "#6fd86f"; return Loc.T("Active: {0} left", Cm.CountdownMin(Left(Json.Number(s, "left"), elapsed))); }
            if (st == "done") { tone = "#f6cf72"; return Loc.T("Reached at {0}%", Json.Int(s, "pct")); }
            tone = "#8c8070";
            return Loc.T("At {0}%", Json.Int(s, "pct"));
        }

        public static string StageTip(object s) => s == null ? "" : Loc.T("{0} ({1}%)\n{2} for everyone online, {3} hours.", Json.Text(s, "n"), Json.Int(s, "pct"), Json.Text(s, "d"), Json.Int(s, "h"));

        public static string MineText(object data)
        {
            var m = Json.Get(data, "mine");
            string rank = Json.Number(m, "rank") > 0 ? Loc.T(" (rank {0})", Json.Int(m, "rank")) : "";
            return Loc.T("{0} points{1}", Fmt(Json.Number(m, "p")), rank);
        }

        public static string TodayText(object data)
        {
            var m = Json.Get(data, "mine");
            return Loc.T("Today: {0} / {1}", Fmt(Json.Number(m, "today")), Fmt(Json.Number(m, "cap")));
        }

        public static string RewardText(object data)
        {
            var m = Json.Get(data, "mine");
            var parts = new List<string>();
            if (Json.Number(m, "top") > 0 && Json.Text(m, "title").Length > 0) parts.Add(Loc.T("Top {0}: the title {1}.", Json.Int(m, "top"), Json.Text(m, "title")));
            if (Json.Number(m, "token") > 0)
            {
                bool have = Json.Number(m, "p") >= Json.Number(m, "token");
                parts.Add(Loc.T("{0} points: {1}{2}", Fmt(Json.Number(m, "token")), Json.Text(m, "tokenText", Loc.T("a reward")), have ? " " + Loc.T("(earned)") : ""));
            }
            return string.Join("\n", parts);
        }

        public static string WeekText(object data, double elapsed)
        {
            var w = Json.Get(data, "week");
            if (Json.List(w, "mods").Count == 0) return Loc.T("No world modifier this week.");
            return Loc.T("This week ({0} left){1}", Cm.CountdownMin(Left(Json.Number(w, "left"), elapsed)), Json.Bool(w, "staff") ? Loc.T(", set by the staff") : "");
        }

        public static string GoalTimeText(object data, double elapsed) => Loc.T("Ends in {0}", Cm.CountdownMin(Left(Json.Number(Json.Get(data, "goal"), "left"), elapsed)));

        // ---- the Brazier
        /// <summary>"150k" / "1.5m" / "25,000" / "2kk" -> gold, or -1 when it is no amount.</summary>
        public static long ParseGold(string text)
        {
            var sb = new StringBuilder();
            foreach (char c in (text ?? "").ToLowerInvariant()) if (c != ',' && !char.IsWhiteSpace(c)) sb.Append(c);
            string t = sb.ToString();
            if (t.Length == 0) return -1;
            int i = 0;
            while (i < t.Length && (char.IsDigit(t[i]) || t[i] == '.')) i++;
            string num = t.Substring(0, i), suffix = t.Substring(i);
            if (num.Length == 0 || !double.TryParse(num, NumberStyles.Float, CultureInfo.InvariantCulture, out double n)) return -1;
            double mult;
            switch (suffix) { case "": mult = 1; break; case "k": mult = 1000; break; case "kk": case "m": mult = 1000000; break; default: return -1; }
            return (long)Math.Floor(n * mult + 0.5);
        }

        /// <summary>What a donation of gold would take: whole `per` units within the limits. Returns the problem text, or null.</summary>
        public static string Donation(object data, long gold, out long take, out long points)
        {
            var b = Json.Get(data, "brazier");
            take = points = 0;
            long per = Math.Max(1, (long)Json.Number(b, "per"));
            if (gold <= 0) return Loc.T("Enter an amount of gold.");
            if (gold < Json.Number(b, "min")) return Loc.T("At least {0} gold.", Fmt(Json.Number(b, "min")));
            double max = Json.Number(b, "max") > 0 ? Json.Number(b, "max") : gold;
            long t = (long)Math.Min(gold, Math.Min(max, Json.Number(b, "room")));
            t = t / per * per;
            if (t <= 0) return Loc.T("The Brazier takes no more from you today.");
            if (t > Json.Number(b, "gold")) return Loc.T("You do not have that much gold.");
            take = t; points = t / per;
            return null;
        }

        public static string DonateState(object data, string text, out bool ok, out string tone)
        {
            var b = Json.Get(data, "brazier");
            ok = false; tone = "bad";
            if (!Json.Bool(b, "near")) return Loc.T("Stand next to the Great Brazier in the temple.");
            string why = Donation(data, ParseGold(text), out long take, out long pts);
            if (why != null) return why;
            ok = true; tone = "good";
            return Loc.T("Give {0} gold for {1} points.", Fmt(take), Fmt(pts));
        }

        public static List<long> QuickAmounts(object data)
        {
            var b = Json.Get(data, "brazier");
            var o = new List<long>();
            foreach (long g in new long[] { 10000, 100000, 1000000 })
                if (g >= Json.Number(b, "min") && g <= Math.Max(Json.Number(b, "max"), g)) o.Add(g);
            return o;
        }

        public static string Short(long g)
        {
            if (g >= 1000000 && g % 1000000 == 0) return g / 1000000 + "m";
            if (g >= 1000 && g % 1000 == 0) return g / 1000 + "k";
            return Fmt(g);
        }

        public void Donate()
        {
            if (Data == null) return;
            string why = Donation(Data, ParseGold(Text("gold")), out long take, out long pts);
            if (why != null || take <= 0) return;
            Send("donate", SFmt.Map("gold", (double)take));
            Form["gold"] = "";
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Community");
            Header2 = "";
            if (Data == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            double e = Elapsed;
            var g = Json.Get(Data, "goal");
            string rn = Json.Text(g, "rn");
            Header1 = Json.Text(g, "n", Loc.T("Community")) + (rn.Length > 0 ? " - " + rn : "");
            Header2 = Json.Text(g, "d");
            if (Tab == "brazier") return BrazierRows(l);
            l.Bar(BarText(Data), BarPercent(Data));
            l.Text(GoalTimeText(Data, e), "dim");
            l.Section(Loc.T("Stages"));
            foreach (var s in SFmt.Rows(Data, "stages"))
            {
                string tone;
                string line = StageLine(s, e, out tone);
                var row = l.Row(Json.Text(s, "n"), line, tone);
                row.Tip = StageTip(s);
                row.Sub = Json.Text(s, "s", Json.Text(s, "d"));
            }
            l.Section(Loc.T("Your part"));
            l.Row(MineText(Data), TodayText(Data), "gold");
            string reward = RewardText(Data);
            if (reward.Length > 0) l.Text(reward, "text");
            foreach (var s in SFmt.Rows(Data, "sources"))
            {
                double cap = Json.Number(s, "cap");
                l.Bar(Json.Text(s, "n", Json.Text(s, "k")) + "   " + Fmt(Json.Number(s, "mine")) + " / " + Fmt(cap), cap > 0 ? (int)Math.Min(100, Math.Floor(Json.Number(s, "mine") * 100 / cap)) : 0);
            }
            l.Section(Loc.T("Top contributors"));
            var top = SFmt.Rows(Data, "top");
            if (top.Count == 0) l.Text(Loc.T("Nobody yet."), "dim");
            for (int i = 0; i < top.Count; i++) l.Row((i + 1) + ".  " + Json.Text(top[i], "n", "?"), Fmt(Json.Number(top[i], "p")));
            l.Section(WeekText(Data, e));
            foreach (var m in SFmt.Rows(Json.Get(Data, "week"), "mods")) { var r = l.Row(Json.Text(m, "n", Json.Text(m, "k")), ""); r.Sub = Json.Text(m, "d"); r.Tip = Json.Text(m, "d"); }
            return l.Rows;
        }

        List<SocialRow> BrazierRows(RowList l)
        {
            var b = Json.Get(Data, "brazier");
            l.Text(Loc.T("You carry {0} gold (backpack and bank). The Brazier takes up to {1} more from you today.", Fmt(Json.Number(b, "gold")), Fmt(Json.Number(b, "room"))), "text");
            var inp = l.Input(Loc.T("Gold to give"), "gold", Loc.T("150k, 1.5m, 25,000"));
            foreach (long q in QuickAmounts(Data))
            {
                long amount = q;
                inp.Btn("+" + Short(q), true, () => { long cur = Math.Max(0, ParseGold(Text("gold"))); Form["gold"] = (cur + amount).ToString(CultureInfo.InvariantCulture); Changed(); });
            }
            bool ok; string tone;
            string preview = DonateState(Data, Text("gold"), out ok, out tone);
            l.Text(preview, tone);
            l.Row(Loc.T("Give the gold to the Brazier")).Btn(Loc.T("Give"), ok, Donate);
            return l.Rows;
        }
    }

    // ====================================================================================================== game_chronicle (171)
    /// <summary>The Ashen Chronicle of the season and the Capital Memorial. client -> server: open | close | mem | memset {records, fallen}; server -> client: state {season, active, arc, title {en, pt},
    /// intro, ending, done, chapters [{i, key, state, pct, doneAt, title, text {en, pt}, world, pending, goals [{l, lp, p, t}], mine, top [{n, p}]}], record [{season, name, title, chapters}]} |
    /// mem {season, records, fallen, ask, firsts [{t, n, at}], recs [{t, v, n, c, at}], falls [{n, l, c, k, at}]}.</summary>
    public sealed class ChroniclePanel : CommunityPanel
    {
        public const byte Opcode = 171;
        public object State, Mem;
        public int SelectedChapter, SelectedSeason = 1;
        public string MemSection = "choice";

        public ChroniclePanel(ExtOpcodes e) : base(e, Opcode)
        {
            Tabs.Add(new KeyValuePair<string, string>("chapters", "Chapters"));
            Tabs.Add(new KeyValuePair<string, string>("record", "Record"));
            Tabs.Add(new KeyValuePair<string, string>("memorial", "Memorial"));
            Tab = "chapters";
        }

        public override void Show() { Visible = true; Send("open"); Send("mem"); }
        public override void Hide() { if (Visible) { Visible = false; Send("close"); } }
        public override void Clear() { base.Clear(); State = Mem = null; SelectedChapter = 0; Tab = "chapters"; MemSection = "choice"; }
        public override void SelectTab(string key) { base.SelectTab(key); if (key == "memorial") Send("mem"); }

        protected override void Handle(string action, object data)
        {
            if (action == "state")
            {
                State = data;
                if (SelectedChapter <= 0 || SelectedChapter > Chapters(State).Count) SelectedChapter = DefaultChapter(State);
            }
            else if (action == "mem") { Mem = data; if (!Form.ContainsKey("m_records")) { Form["m_records"] = Json.Bool(data, "records") ? "1" : "0"; Form["m_fallen"] = Json.Bool(data, "fallen") ? "1" : "0"; } }
        }

        public static string Lang() => Loc.Language == Loc.Portuguese ? "pt" : "en";

        /// <summary>A server text in both languages: {en, pt} (a string or a list of paragraphs).</summary>
        public static object Pick(object field, string lang)
        {
            if (!Cm.IsMap(field)) return field;
            if (lang == "pt" && Json.Get(field, "pt") != null) return Json.Get(field, "pt");
            if (Json.Get(field, "en") != null) return Json.Get(field, "en");
            return Json.Get(field, "pt");
        }

        public static string PickText(object field, string lang) => Pick(field, lang) as string ?? "";

        public static List<string> Paragraphs(object field, string lang)
        {
            var v = Pick(field, lang);
            var o = new List<string>();
            if (v is string s) { if (s.Length > 0) o.Add(s); return o; }
            if (v is List<object> list) foreach (object p in list) if (p is string t && t.Length > 0) o.Add(t);
            return o;
        }

        public static List<object> Chapters(object data) { var o = new List<object>(); foreach (var c in SFmt.Rows(data, "chapters")) o.Add(c); return o; }

        public static int DefaultChapter(object data)
        {
            var chs = Chapters(data);
            for (int i = 0; i < chs.Count; i++) if (Json.Text(chs[i], "state") == "open") return i + 1;
            return chs.Count > 0 ? chs.Count : 0;
        }

        public static int GoalPercent(object g) => Json.Number(g, "t") <= 0 ? 0 : (int)Math.Max(0, Math.Min(100, Math.Floor(Json.Number(g, "p") * 100 / Json.Number(g, "t"))));
        public static string GoalText(object g) => SFmt.Money(Json.Number(g, "p")) + " / " + SFmt.Money(Json.Number(g, "t"));
        public static string GoalLabel(object g, string lang) => lang == "pt" && Json.Text(g, "lp").Length > 0 ? Json.Text(g, "lp") : Json.Text(g, "l");

        public static string ChapterLine(object ch, out string tone)
        {
            string st = Json.Text(ch, "state");
            if (st == "done")
            {
                tone = "#f6cf72";
                string when = Cm.DateText(Json.Number(ch, "doneAt"));
                return when.Length > 0 ? Loc.T("Written on {0}", when) : Loc.T("Written");
            }
            if (st == "open") { tone = "#6fd86f"; return Loc.T("Open: {0}% written", SFmt.Pct(Json.Number(ch, "pct"))); }
            tone = "#6b6258";
            return Loc.T("Not yet told");
        }

        public static string SeasonTitle(object s, string lang)
        {
            string name = Json.Text(s, "name"), title = PickText(Json.Get(s, "title"), lang);
            if (name.Length > 0 && title.Length > 0) return name + ": " + title;
            return name.Length > 0 ? name : title;
        }

        public static List<string[]> MemFirsts(object mem) { var o = new List<string[]>(); foreach (var e in SFmt.Rows(mem, "firsts")) o.Add(new[] { Json.Text(e, "t"), Json.Text(e, "n"), Cm.DateText(Json.Number(e, "at")) }); return o; }

        public static List<string[]> MemRecords(object mem)
        {
            var o = new List<string[]>();
            foreach (var e in SFmt.Rows(mem, "recs"))
            {
                string n = Json.Text(e, "n"), c = Json.Text(e, "c");
                string who = n.Length > 0 ? n + (c.Length > 0 ? ", " + c : "") : Loc.T("a hero who keeps their name");
                o.Add(new[] { Json.Text(e, "t"), Json.Text(e, "v") + ", " + who, Cm.DateText(Json.Number(e, "at")) });
            }
            return o;
        }

        public static List<string[]> MemFalls(object mem)
        {
            var o = new List<string[]>();
            foreach (var e in SFmt.Rows(mem, "falls"))
            {
                string c = Json.Text(e, "c");
                o.Add(new[] { Json.Text(e, "n"), Loc.T("level {0} {1}, {2}", Json.Int(e, "l"), c.Length > 0 ? c : Loc.T("adventurer"), Json.Text(e, "k")), Cm.DateText(Json.Number(e, "at")) });
            }
            return o;
        }

        public static Dictionary<string, object> ChoiceRequest(bool records, bool fallen) => SFmt.Map("records", records, "fallen", fallen);

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            string lang = Lang();
            Header1 = Loc.T("Ashen Chronicle");
            Header2 = "";
            if (Tab == "memorial") return MemorialRows(l);
            if (State == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            string season = Json.Text(State, "season");
            string arcTitle = PickText(Json.Get(State, "title"), lang);
            Header1 = arcTitle.Length > 0 ? arcTitle : Loc.T("Ashen Chronicle");
            Header2 = season.Length > 0 ? Loc.T("Season {0}", season) : "";
            if (Tab == "record") return RecordRows(l, lang);
            foreach (string p in Paragraphs(Json.Get(State, "intro"), lang)) l.Text(p, "dim");
            var chs = Chapters(State);
            if (chs.Count == 0) { l.Text(Loc.T("The Chronicle has no chapter yet."), "dim"); return l.Rows; }
            l.Section(Loc.T("Chapters"));
            for (int i = 0; i < chs.Count; i++)
            {
                int idx = i + 1;
                string tone;
                string line = ChapterLine(chs[i], out tone);
                var row = l.Row(idx + ". " + PickText(Json.Get(chs[i], "title"), lang), line, tone);
                row.Btn(idx == SelectedChapter ? Loc.T("Shown") : Loc.T("Read"), idx != SelectedChapter, () => { SelectedChapter = idx; Changed(); });
            }
            if (SelectedChapter >= 1 && SelectedChapter <= chs.Count)
            {
                var ch = chs[SelectedChapter - 1];
                l.Section(PickText(Json.Get(ch, "title"), lang));
                if (Json.Text(ch, "state") == "locked") l.Text(Loc.T("Not yet told"), "dim");
                else
                {
                    foreach (string p in Paragraphs(Json.Get(ch, "text"), lang)) l.Text(p, "text");
                    string world = PickText(Json.Get(ch, "world"), lang);
                    if (world.Length > 0) l.Text(world, "gold");
                    if (Json.List(ch, "pending").Count > 0) l.Text(Loc.T("The way is not on the map yet: the staff is placing it."), "warn");
                }
                foreach (var g in SFmt.Rows(ch, "goals")) l.Bar(GoalLabel(g, lang) + "   " + GoalText(g), GoalPercent(g));
                if (Json.Get(ch, "mine") != null) l.Row(Loc.T("Your part"), SFmt.Money(Json.Number(ch, "mine")), "gold");
                var top = SFmt.Rows(ch, "top");
                for (int i = 0; i < top.Count; i++) l.Row((i + 1) + ".  " + Json.Text(top[i], "n"), SFmt.Money(Json.Number(top[i], "p")));
            }
            foreach (string p in Paragraphs(Json.Get(State, "ending"), lang)) l.Text(p, "gold");
            return l.Rows;
        }

        List<SocialRow> RecordRows(RowList l, string lang)
        {
            var seasons = SFmt.Rows(State, "record");
            if (seasons.Count == 0) { l.Text(Loc.T("No season is written down yet."), "dim"); return l.Rows; }
            foreach (var s in seasons)
            {
                l.Section(SeasonTitle(s, lang));
                foreach (var ch in SFmt.Rows(s, "chapters"))
                {
                    var tops = new List<string>();
                    int n = 0;
                    foreach (var t in SFmt.Rows(ch, "top")) { n++; tops.Add(n + ". " + Json.Text(t, "n") + " " + SFmt.Money(Json.Number(t, "p"))); }
                    var row = l.Row(Json.Int(ch, "i") + ". " + PickText(Json.Get(ch, "title"), lang));
                    row.Sub = string.Join("   ", tops);
                }
            }
            return l.Rows;
        }

        public static readonly string[][] MemSections = { new[] { "choice", "Your choice" }, new[] { "firsts", "Realm firsts" }, new[] { "records", "Records" }, new[] { "falls", "The fallen" } };

        List<SocialRow> MemorialRows(RowList l)
        {
            Header1 = Loc.T("Capital Memorial");
            if (Mem == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            var r = l.Row(Loc.T("Section"));
            foreach (var sec in MemSections)
            {
                string key = sec[0];
                r.Btn(Loc.T(sec[1]), MemSection != key, () => { MemSection = key; Changed(); });
            }
            Header2 = Json.Bool(Mem, "ask") ? Loc.T("Your fall waits for an answer") : Loc.T("Show me on the Memorial");
            if (MemSection == "choice")
            {
                l.Text(Loc.T("The Capital Memorial remembers the realm's firsts, its records and the heroes who fell in Hardcore. Choose what it may say about you."), "text");
                l.Combo(Loc.T("Show my name on records"), "m_records", new[] { Loc.T("No"), Loc.T("Yes") });
                l.Combo(Loc.T("Show me among the fallen"), "m_fallen", new[] { Loc.T("No"), Loc.T("Yes") });
                l.Row(Loc.T("Save your choice")).Btn(Loc.T("Save"), true, () => { Send("memset", ChoiceRequest(Text("m_records") == "1", Text("m_fallen") == "1")); Say(Loc.T("Choice sent."), true); });
                return l.Rows;
            }
            List<string[]> items = MemSection == "firsts" ? MemFirsts(Mem) : MemSection == "records" ? MemRecords(Mem) : MemFalls(Mem);
            if (items.Count == 0) l.Text(Loc.T("Nothing is remembered here yet."), "dim");
            foreach (var it in items) { var row = l.Row(it[0], it[2]); row.Sub = it[1]; }
            return l.Rows;
        }
    }

    // ====================================================================================================== game_mentor (194)
    /// <summary>The mentor window: find a mentor, My mentor, Mentoring (card, apprentices, invites), the Marks shop, Top mentors, and the once-per-character mentor offer.
    /// client -> server: open | sync | list {line, lang, online} | register {lang, hours, note, accepting, public} | retire | choose {guid} | invite {name} | accept {guid} | decline {guid} |
    /// dismiss | release {guid} | seek {on} | buy {key} | offer {answer}; server -> client: status {...} (open: show) | mentors {rows} | message {text, error} | offer {online, any, exp, dmg}.</summary>
    public sealed class MentorPanel : CommunityPanel
    {
        public const byte Opcode = 194;
        public object StatusData;
        public List<object> MentorRows;
        public object Offer;
        bool tabChosen;

        public static readonly string[][] OnlineOptions = { new[] { "any", "Any time" }, new[] { "week", "Seen this week" }, new[] { "now", "Online now" } };

        public MentorPanel(ExtOpcodes e) : base(e, Opcode)
        {
            Tabs.Add(new KeyValuePair<string, string>("find", "Find a mentor"));
            Tabs.Add(new KeyValuePair<string, string>("mine", "My mentor"));
            Tabs.Add(new KeyValuePair<string, string>("mentoring", "Mentoring"));
            Tabs.Add(new KeyValuePair<string, string>("shop", "Marks Shop"));
            Tabs.Add(new KeyValuePair<string, string>("top", "Top Mentors"));
            Tab = "find";
        }

        public override void Show() { Visible = true; Send("open"); }
        public override void Clear() { base.Clear(); StatusData = null; MentorRows = null; Offer = null; tabChosen = false; Tab = "find"; }
        public override void SelectTab(string key) { base.SelectTab(key); if (key == "find" && MentorRows == null && StatusData != null) Search(); }

        protected override void Handle(string action, object d)
        {
            switch (action)
            {
                case "status":
                {
                    bool first = StatusData == null;
                    StatusData = d;
                    if (Json.Bool(d, "open"))
                    {
                        if (first || !Visible || !tabChosen) Tab = FirstTab(d);
                        tabChosen = true;
                        Status = "";
                        Visible = true;
                        if (Tab == "find") Search();
                    }
                    break;
                }
                case "mentors": MentorRows = new List<object>(SFmt.Rows(d, "rows")); break;
                case "message": Status = Json.Text(d, "text"); StatusTone = Json.Bool(d, "error") ? "bad" : "good"; break;
                case "offer": Offer = d; Visible = true; break;
            }
        }

        // ---- rules (mentorview.lua)
        public static string FirstTab(object s) => Json.Get(s, "apprentice") != null ? "mine" : Json.Get(s, "mentor") != null ? "mentoring" : "find";

        public static string MinutesText(double m)
        {
            long v = (long)Math.Floor(m);
            if (v < 60) return v + " min";
            return (v / 60) + "h " + (v % 60).ToString("00", CultureInfo.InvariantCulture) + "m";
        }

        public static string LeftText(double seconds)
        {
            long s = (long)Math.Floor(seconds);
            if (s <= 0) return Loc.T("expired");
            if (s < 60) return Loc.T("{0}s left", s);
            return Loc.T("{0} min left", (long)Math.Ceiling(s / 60.0));
        }

        public static string PickText(object s)
        {
            if (s == null) return Loc.T("Loading...");
            if (!Json.Bool(s, "enabled")) return Loc.T("The mentor system is off.");
            var r = Json.Get(s, "rules");
            if (Json.Get(s, "apprentice") != null) return Loc.T("You have a mentor: see My mentor.");
            if (!Json.Bool(s, "canPick")) return Json.Text(s, "pickNote");
            return Loc.T("New characters (up to level {0}, account up to {1} days old) can pick a mentor. Hunting together in a party gives you +{2}% experience and {3}% less damage from monsters while your mentor is not far above the monsters. You graduate at level {4}.",
                Json.Int(r, "maxLevel"), Json.Int(r, "accountDays"), Json.Int(r, "exp"), Json.Int(r, "dmg"), Json.Int(r, "gradLevel"));
        }

        public static List<KeyValuePair<string, string>> LineOptions(object s)
        {
            var o = new List<KeyValuePair<string, string>> { new KeyValuePair<string, string>("", "Any class") };
            foreach (var l in SFmt.Rows(s, "lines")) o.Add(new KeyValuePair<string, string>(Json.Text(l, "key"), Json.Text(l, "name")));
            return o;
        }

        public static Dictionary<string, object> Filter(string line, string lang, string online)
        {
            string o = "any";
            foreach (var opt in OnlineOptions) if (opt[0] == online) o = online;
            lang = (lang ?? "").Trim();
            if (lang.Length > 24) lang = lang.Substring(0, 24);
            return SFmt.Map("line", line ?? "", "lang", lang, "online", o);
        }

        public void Search()
        {
            var lines = LineOptions(StatusData);
            int li = Index("f_line");
            string line = li >= 0 && li < lines.Count ? lines[li].Key : "";
            int oi = Index("f_online");
            string online = oi >= 0 && oi < OnlineOptions.Length ? OnlineOptions[oi][0] : "any";
            Send("list", Filter(line, Text("f_lang"), online));
        }

        public static string MentorTitle(object r) => Json.Text(r, "name", "?") + "  -  Lv " + Json.Int(r, "level") + " " + Json.Text(r, "voc");

        public static string MentorSub(object r)
        {
            int places = Math.Max(0, Json.Int(r, "max") - Json.Int(r, "active"));
            var sub = new List<string>();
            if (Json.Text(r, "lang").Length > 0) sub.Add(Json.Text(r, "lang"));
            if (Json.Text(r, "hours").Length > 0) sub.Add(Json.Text(r, "hours"));
            sub.Add(Loc.T(Json.Int(r, "graduates") == 1 ? "{0} graduate" : "{0} graduates", Json.Int(r, "graduates")));
            sub.Add(Loc.T(places == 1 ? "{0} place free" : "{0} places free", places));
            return string.Join("  -  ", sub);
        }

        public static bool CanChoose(object r, object s)
        {
            int places = Math.Max(0, Json.Int(r, "max") - Json.Int(r, "active"));
            return (s == null || (Json.Bool(s, "canPick") && Json.Get(s, "apprentice") == null)) && places > 0;
        }

        public sealed class InviteRow { public double Guid; public string Kind = "", Text = ""; }

        public static List<InviteRow> InviteRows(object s)
        {
            var o = new List<InviteRow>();
            if (s == null) return o;
            var rf = Json.Get(s, "referrer");
            if (Cm.IsMap(rf) && Json.Bool(s, "canPick")) o.Add(new InviteRow { Guid = Json.Number(rf, "guid"), Kind = "referrer", Text = Loc.T("Your referrer mentors as {0}.", Json.Text(rf, "name", "?")) });
            foreach (var i in SFmt.Rows(s, "invites"))
                o.Add(new InviteRow { Guid = Json.Number(i, "guid"), Kind = "invite", Text = Loc.T("{0} (Lv {1} {2}) invites you - {3}", Json.Text(i, "name", "?"), Json.Int(i, "level"), Json.Text(i, "voc"), LeftText(Json.Number(i, "left"))) });
            return o;
        }

        static string StateText(string st) { switch (st) { case "open": return "-"; case "paid": return Loc.T("marks paid"); case "unearned": return Loc.T("no marks"); case "capped": return Loc.T("month cap"); case "before": return Loc.T("before the link"); } return st; }
        static string StateTone(string st) { switch (st) { case "paid": return "#80c070"; case "unearned": return "#e07060"; case "capped": return "#e8b84a"; case "before": return "#6b6258"; } return "#8c8070"; }

        public static string ShortMilestone(string key)
        {
            switch (key) { case "l25": return "25"; case "l50": return "50"; case "l100": return "100"; case "rift": return "Rift"; case "dungeon": return "Dng"; case "bounty": return "Bty"; case "worldboss": return "WB"; case "graduation": return "Grad"; }
            return key;
        }

        public static string MineHeader(object s, out string sub)
        {
            sub = "";
            if (s == null) return "";
            var a = Json.Get(s, "apprentice");
            if (!Cm.IsMap(a))
            {
                if (Json.Bool(s, "graduated")) { sub = Loc.T("Thank your mentor: you can become one yourself one day."); return Loc.T("You graduated."); }
                sub = Loc.T("Pick one in Find a mentor, or accept an invitation.");
                return Loc.T("You have no mentor.");
            }
            string title = Json.Text(a, "name", "?") + "  -  Lv " + Json.Int(a, "level") + " " + Json.Text(a, "voc") + "  (" + (Json.Bool(a, "online") ? Loc.T("online") : Loc.T("offline")) + ")";
            string how = Json.Text(a, "source");
            switch (how) { case "list": how = Loc.T("chosen from the list"); break; case "invite": how = Loc.T("by invitation"); break; case "referral": how = Loc.T("your referrer"); break; }
            sub = Loc.T("Mentor since {0} ({1}). Hunted together: {2}.", Cm.IsoDate(Json.Number(a, "linkedAt")), how, MinutesText(Json.Number(a, "shared")));
            return title;
        }

        public static string RequirementsText(object s)
        {
            if (s == null) return "";
            var r = Json.Get(s, "rules");
            string basic = Loc.T("Mentors: an account with a level {0} character, {1} hours of play and {2} days of age. Up to {3} apprentices. You earn Mentor Marks from their milestones (after {4} minutes hunting together) and 1 mark per {5} minutes of hunting together ({6} a day, {7} a month in all). Marks buy titles, cosmetics and supplies, never power.",
                Json.Int(r, "mentorLevel"), Json.Int(r, "mentorHours"), Json.Int(r, "mentorDays"), Json.Int(r, "maxApprentices"), Json.Int(r, "minShared"), Json.Int(r, "huntMinutes"), Json.Int(r, "dailyHuntMarks"), Json.Int(r, "monthlyCap"));
            if (Json.Get(s, "mentor") != null) return basic;
            if (Json.Bool(s, "canMentor")) return Loc.T("{0} You can register this character.", basic);
            return basic + " " + Json.Text(s, "mentorNote");
        }

        public static string MentorStats(object s)
        {
            var m = Json.Get(s, "mentor");
            if (!Cm.IsMap(m)) return "";
            var r = Json.Get(s, "rules");
            return Loc.T("Marks {0} (earned {1})   Graduates {2}   Today {3}/{4} marks, {5}   Month {6}/{7} marks, {8}/{9} new",
                Json.Int(m, "marks"), Json.Int(m, "earned"), Json.Int(m, "graduates"), Json.Int(m, "dayMarks"), Json.Int(r, "dailyHuntMarks"), MinutesText(Json.Number(m, "dayMinutes")),
                Json.Int(m, "monthMarks"), Json.Int(r, "monthlyCap"), Json.Int(m, "linksThisMonth"), Json.Int(m, "monthlyLinks"));
        }

        public sealed class ShopRow { public string Key = "", Name = "", Desc = "", Price = "", Button = ""; public bool Buyable; public string Tone = "text"; }

        public static List<ShopRow> ShopRows(object s)
        {
            var o = new List<ShopRow>();
            var m = Json.Get(s, "mentor");
            double marks = Cm.IsMap(m) ? Json.Number(m, "marks") : 0;
            bool isMentor = Cm.IsMap(m);
            foreach (var it in SFmt.Rows(s, "shop"))
            {
                string button = Loc.T("Buy");
                bool buyable = true;
                bool weekly = Json.Get(it, "weeklyLeft") != null;
                if (!isMentor) { buyable = false; button = Loc.T("Mentors only"); }
                else if (Json.Bool(it, "owned")) { buyable = false; button = Loc.T("Owned"); }
                else if (weekly && Json.Number(it, "weeklyLeft") <= 0) { buyable = false; button = Loc.T("Next week"); }
                else if (marks < Json.Number(it, "cost")) buyable = false;
                string desc = Json.Text(it, "desc");
                if (weekly) desc += Loc.T(" ({0} left this week)", Json.Int(it, "weeklyLeft"));
                string kind = Json.Text(it, "kind");
                string kindText = kind == "title" ? Loc.T("Title") : kind == "cosmetic" ? Loc.T("Cosmetic") : kind == "item" ? Loc.T("Supplies") : "";
                o.Add(new ShopRow
                {
                    Key = Json.Text(it, "key"), Name = (kindText.Length > 0 ? kindText + ": " : "") + Json.Text(it, "name", Json.Text(it, "key")), Desc = desc,
                    Price = Json.Int(it, "cost") + " " + Loc.T("marks"), Button = button, Buyable = buyable, Tone = kind == "title" ? Json.Text(it, "color", "gold") : "text",
                });
            }
            return o;
        }

        public static string OfferBody(object d) => Loc.T("A mentor hunts with you and you both earn rewards. While you hunt together you get +{0}% experience and take {1}% less damage.", Json.Int(d, "exp"), Json.Int(d, "dmg"));

        public static string OfferOnline(object d)
        {
            int same = (int)Math.Floor(Json.Number(d, "online")), any = (int)Math.Floor(Json.Number(d, "any"));
            if (same == 1) return Loc.T("1 mentor who speaks your language is online now.");
            if (same > 1) return Loc.T("{0} mentors who speak your language are online now.", same);
            if (any == 1) return Loc.T("1 mentor is online now.");
            if (any > 1) return Loc.T("{0} mentors are online now.", any);
            return Loc.T("No mentor is online right now: pick one and hunt together later.");
        }

        public void AnswerOffer(bool find)
        {
            Offer = null;
            if (find) Tab = "find";
            Send("offer", SFmt.Map("answer", find ? "find" : "no"));
            Changed();
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            var s = StatusData;
            Header1 = Loc.T("Mentors");
            Header2 = "";
            if (Offer != null)
            {
                l.Section(Loc.T("Find a mentor?"));
                l.Text(OfferBody(Offer), "text");
                l.Text(OfferOnline(Offer), "dim");
                var r = l.Row(Loc.T("A mentor can help you"));
                r.Btn(Loc.T("Find a mentor"), true, () => AnswerOffer(true));
                r.Btn(Loc.T("No thanks"), true, () => AnswerOffer(false));
            }
            if (s == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            switch (Tab)
            {
                case "find": FindRows(l, s); break;
                case "mine": MineRows(l, s); break;
                case "mentoring": MentoringRows(l, s); break;
                case "shop": ShopTab(l, s); break;
                case "top": TopRows(l, s); break;
            }
            return l.Rows;
        }

        void FindRows(RowList l, object s)
        {
            l.Text(PickText(s), "text");
            l.Combo(Loc.T("Looking for a mentor"), "seek", new[] { Loc.T("No"), Loc.T("Yes") });
            if (!Form.ContainsKey("seek")) Form["seek"] = Json.Bool(s, "seeking") ? "1" : "0";
            foreach (var inv in InviteRows(s))
            {
                double guid = inv.Guid;
                var r = l.Row(inv.Text);
                if (inv.Kind == "referrer") r.Btn(Loc.T("Choose"), true, () => Send("choose", SFmt.Map("guid", guid)));
                else { r.Btn(Loc.T("Accept"), true, () => Send("accept", SFmt.Map("guid", guid))); r.Btn(Loc.T("Decline"), true, () => Send("decline", SFmt.Map("guid", guid))); }
            }
            l.Section(Loc.T("Mentors"));
            var lineNames = new List<string>();
            foreach (var o in LineOptions(s)) lineNames.Add(Loc.T(o.Value));
            l.Combo(Loc.T("Class"), "f_line", lineNames);
            var names = new List<string>();
            foreach (var o in OnlineOptions) names.Add(Loc.T(o[1]));
            l.Combo(Loc.T("Online"), "f_online", names);
            l.Input(Loc.T("Language"), "f_lang", Loc.T("any")).Btn(Loc.T("Search"), true, Search);
            if (MentorRows == null) l.Text(Loc.T("Press Search to see the mentors."), "dim");
            else if (MentorRows.Count == 0) l.Text(Loc.T("No mentor matches these filters."), "dim");
            else
                foreach (var r0 in MentorRows)
                {
                    double guid = Json.Number(r0, "guid");
                    bool on = Json.Bool(r0, "online");
                    var row = l.Row(MentorTitle(r0), on ? Loc.T("online") : Loc.T("offline"), on ? "good" : "dim");
                    row.Sub = MentorSub(r0);
                    row.Tip = Json.Text(r0, "note");
                    row.Btn(Loc.T("Choose"), CanChoose(r0, s), () => Send("choose", SFmt.Map("guid", guid)));
                }
        }

        public override void OnForm(string key)
        {
            if (key == "seek" && StatusData != null) Send("seek", SFmt.Map("on", Text("seek") == "1"));
        }

        void MineRows(RowList l, object s)
        {
            string sub;
            string title = MineHeader(s, out sub);
            l.Section(title);
            if (sub.Length > 0) l.Text(sub, "dim");
            var a = Json.Get(s, "apprentice");
            if (Cm.IsMap(a))
            {
                string bonus = Json.Text(a, "bonusText");
                if (bonus.Length > 0) l.Text(bonus, Json.Bool(a, "bonus") ? "good" : "warn");
                l.Row(Loc.T("Dismiss your mentor")).Btn(Loc.T("Dismiss"), true, () => Send("dismiss"));
                l.Section(Loc.T("Milestones (your mentor earns Mentor Marks)"));
                foreach (var m in SFmt.Rows(a, "milestones"))
                {
                    string st = Json.Text(m, "state");
                    string marks = st == "paid" ? "+" + Json.Int(m, "got") : st == "open" ? Json.Int(m, "marks") + " " + Loc.T("marks") : "";
                    l.Row(Json.Text(m, "name", Json.Text(m, "key")), StateText(st) + (marks.Length > 0 ? "  " + marks : ""), StateTone(st));
                }
            }
            var r = Json.Get(s, "rules");
            l.Text(Loc.T("Graduation at level {0}: {1} for you, {2} Mentor Marks for your mentor (after {3} minutes hunting together). Dismissing your mentor ends the link.",
                Json.Int(r, "gradLevel"), Json.Text(r, "gradReward"), Json.Int(r, "gradMarks"), Json.Int(r, "gradShared")), "dim");
        }

        void MentoringRows(RowList l, object s)
        {
            l.Text(RequirementsText(s), "dim");
            var m = Json.Get(s, "mentor");
            bool isMentor = Cm.IsMap(m);
            if (isMentor)
            {
                l.Text(MentorStats(s), "gold");
                var apps = SFmt.Rows(m, "apprentices");
                l.Section(Loc.T("Apprentices ({0} / {1})", apps.Count, Json.Int(Json.Get(s, "rules"), "maxApprentices")));
                foreach (var a in apps)
                {
                    double guid = Json.Number(a, "guid");
                    var steps = new List<string>();
                    foreach (var ms in SFmt.Rows(a, "milestones")) steps.Add(ShortMilestone(Json.Text(ms, "key")) + " " + StateText(Json.Text(ms, "state")));
                    var row = l.Row(Json.Text(a, "name", "?") + "  -  Lv " + Json.Int(a, "level") + " " + Json.Text(a, "voc") + (Json.Bool(a, "online") ? "  (" + Loc.T("online") + ")" : ""),
                        Loc.T("Since {0}, together {1}", Cm.IsoDate(Json.Number(a, "linkedAt")), MinutesText(Json.Number(a, "shared"))));
                    row.Sub = string.Join("   ", steps);
                    row.Btn(Loc.T("Release"), true, () => Send("release", SFmt.Map("guid", guid)));
                }
                l.Input(Loc.T("Invite a character"), "inv", Loc.T("character name")).Btn(Loc.T("Invite"), true, Invite);
            }
            if (isMentor || Json.Bool(s, "canMentor"))
            {
                l.Section(Loc.T("Your card"));
                if (isMentor && !Form.ContainsKey("c_lang"))
                {
                    Form["c_lang"] = Json.Text(m, "lang"); Form["c_hours"] = Json.Text(m, "hours"); Form["c_note"] = Json.Text(m, "note");
                    Form["c_accepting"] = Json.Bool(m, "accepting") ? "1" : "0"; Form["c_public"] = Json.Bool(m, "public") ? "1" : "0";
                }
                l.Input(Loc.T("Language"), "c_lang", Loc.T("e.g. English, Portuguese"));
                l.Input(Loc.T("Hours"), "c_hours", Loc.T("e.g. evenings"));
                l.Input(Loc.T("Note"), "c_note", Loc.T("a line for the list"));
                l.Combo(Loc.T("Accepting apprentices"), "c_accepting", new[] { Loc.T("No"), Loc.T("Yes") });
                l.Combo(Loc.T("Listed publicly"), "c_public", new[] { Loc.T("No"), Loc.T("Yes") });
                var r = l.Row(isMentor ? Loc.T("Save card") : Loc.T("Become a mentor"));
                r.Btn(isMentor ? Loc.T("Save card") : Loc.T("Become a mentor"), true, SaveCard);
                if (isMentor) r.Btn(Loc.T("Retire"), true, () => Send("retire"));
            }
        }

        public void SaveCard()
        {
            Send("register", SFmt.Map("lang", Text("c_lang"), "hours", Text("c_hours"), "note", Text("c_note"), "accepting", Text("c_accepting") == "1", "public", Text("c_public") == "1"));
        }

        public void Invite()
        {
            string n = Text("inv").Trim();
            if (n.Length == 0) { Say(Loc.T("Type the character name first."), false); return; }
            Send("invite", SFmt.Map("name", n));
        }

        void ShopTab(RowList l, object s)
        {
            var m = Json.Get(s, "mentor");
            l.Text(Cm.IsMap(m) ? Loc.T("Your Mentor Marks: {0}", Json.Int(m, "marks")) : Loc.T("Mentor Marks are earned by mentoring. Register in Mentoring."), "gold");
            foreach (var r in ShopRows(s))
            {
                string key = r.Key;
                var row = l.Row(r.Name, r.Price, r.Tone);
                row.Sub = r.Desc;
                row.Btn(r.Button, r.Buyable, () => Send("buy", SFmt.Map("key", key)));
            }
        }

        void TopRows(RowList l, object s)
        {
            var top = SFmt.Rows(s, "top");
            if (top.Count == 0) l.Text(Loc.T("Nobody has graduated an apprentice yet."), "dim");
            foreach (var t in top)
                l.Row("#" + Json.Int(t, "rank") + "  " + Json.Text(t, "name", "?") + "  -  Lv " + Json.Int(t, "level") + " " + Json.Text(t, "voc"), Loc.T(Json.Int(t, "graduates") == 1 ? "{0} graduate" : "{0} graduates", Json.Int(t, "graduates")));
        }
    }

    // ====================================================================================================== game_patchnotes (244)
    /// <summary>The patch notes: the weeks, the selected week's note and the Changelog tab. server -> client: list {weeks [{id, title, date, new}], selected, open, auto, autoEnabled, dailyFirst} |
    /// note {id, title, date, part, parts, intro, sections [{name, kind, cont, items [{text, level, lead}]}]} | changelog {available, server {date}, published, entries [{id, date, ts, pr, text, tags, client, pending}]};
    /// client -> server: open {id?} | get {id} | seen {id} | auto {enabled} | closed | changelog. At the login the server sends `auto` once per unseen week: the window waits for the Daily Reward window.</summary>
    public sealed class PatchNotesPanel : CommunityPanel
    {
        public const byte Opcode = 244;
        public const double DailyWait = 6, AfterDaily = 0.6, AutoGuard = 20, ChangelogRefresh = 300;
        public static readonly string[] TagOrder = { "server", "client", "content", "website" };
        public static readonly string[] Filters = { "all", "server", "client", "content", "website" };
        static readonly string[] MonthNames = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

        public sealed class Block { public string Style = "", Text = "", Lead = "", Tone = "text"; public int Level; }
        public sealed class Auto { public bool DailyFirst, SawDaily; public double Since, ClosedAt = -1; }

        public readonly List<object> Weeks = new List<object>();
        public readonly Dictionary<string, object> Notes = new Dictionary<string, object>();
        readonly Dictionary<string, Dictionary<int, object>> partial = new Dictionary<string, Dictionary<int, object>>();
        readonly HashSet<string> seenSent = new HashSet<string>();
        public string SelectedId = "", ShownId = "";
        public bool AutoEnabled = true;
        public Auto Pending;
        public double AutoShownAt = -1;
        public object Changelog;
        double changelogAt = -1;
        public double ChangelogSeenTs;
        /// <summary>The Daily Reward window is on screen, a modal dialog is open (the app sets them).</summary>
        public Func<bool> DailyVisible = () => false, ModalOpen = () => false;
        /// <summary>The last look at the changelog, saved by the app (PlayerPrefs).</summary>
        public Func<double> LoadSeen = () => 0;
        public Action<double> SaveSeen = delegate { };

        public PatchNotesPanel(ExtOpcodes e) : base(e, Opcode)
        {
            Tabs.Add(new KeyValuePair<string, string>("notes", "Patch notes"));
            Tabs.Add(new KeyValuePair<string, string>("changelog", "Changelog"));
            Tab = "notes";
        }

        public override void Show()
        {
            Visible = true;
            Send("open", string.IsNullOrEmpty(SelectedId) ? new Dictionary<string, object>() : SFmt.Map("id", SelectedId));
            MarkSeen();
        }

        public override void Hide() { if (Visible) { Visible = false; Send("closed"); } }
        public override void Clear() { base.Clear(); Weeks.Clear(); Notes.Clear(); partial.Clear(); seenSent.Clear(); SelectedId = ShownId = ""; Pending = null; AutoShownAt = -1; Changelog = null; changelogAt = -1; Tab = "notes"; }

        public override void SelectTab(string key)
        {
            base.SelectTab(key);
            if (key == "changelog") AskChangelog(true);
        }

        public void AskChangelog(bool force)
        {
            if (!force && changelogAt >= 0 && NowMs - changelogAt < ChangelogRefresh * 1000) return;
            changelogAt = NowMs;
            Send("changelog");
        }

        protected override void Handle(string action, object d)
        {
            switch (action)
            {
                case "list": OnList(d); break;
                case "note": OnNote(d); break;
                case "changelog": Changelog = d; changelogAt = NowMs; break;
            }
        }

        void OnList(object d)
        {
            Weeks.Clear();
            foreach (var w in SFmt.Rows(d, "weeks")) if (Json.Text(w, "id").Length > 0) Weeks.Add(w);
            AutoEnabled = Json.Get(d, "autoEnabled") as bool? != false;
            string id = Json.Text(d, "selected");
            if (id.Length == 0 || FindWeek(id) == null) id = Weeks.Count > 0 ? Json.Text(Weeks[0], "id") : "";
            SelectedId = id;
            if (Json.Bool(d, "open"))
            {
                Pending = null;
                Visible = true;
                AskChangelog(false);
                MarkSeen();
            }
            else if (Json.Bool(d, "auto") && !Visible)
            {
                Pending = new Auto { DailyFirst = Json.Bool(d, "dailyFirst"), Since = NowMs / 1000 };
            }
        }

        public object FindWeek(string id) { foreach (var w in Weeks) if (Json.Text(w, "id") == id) return w; return null; }

        void OnNote(object d)
        {
            string id = Json.Text(d, "id");
            if (id.Length == 0) return;
            int total = (int)Math.Max(1, Math.Min(50, Json.Number(d, "parts", 1)));
            int index = Json.Int(d, "part", 1);
            if (!partial.TryGetValue(id, out var p) || p.Count > 0 && Json.Int(FirstOf(p), "parts", 1) != total) partial[id] = p = new Dictionary<int, object>();
            p[index] = d;
            if (p.Count < total) return;
            partial.Remove(id);
            var parts = new List<object>();
            for (int i = 1; i <= total; i++) { if (!p.TryGetValue(i, out var part)) return; parts.Add(part); }
            var note = Join(parts);
            if (note == null) return;
            Notes[id] = note;
            if (id == SelectedId) MarkSeen();
        }

        static object FirstOf(Dictionary<int, object> p) { foreach (var v in p.Values) return v; return null; }

        /// <summary>The parts of a long note put back together; a section with cont continues the last section before it. Null when a part is missing.</summary>
        public static Dictionary<string, object> Join(List<object> parts)
        {
            if (parts == null || parts.Count == 0 || !Cm.IsMap(parts[0])) return null;
            var first = parts[0];
            var note = new Dictionary<string, object> { { "id", Json.Get(first, "id") }, { "title", Json.Get(first, "title") }, { "date", Json.Get(first, "date") }, { "intro", Json.Get(first, "intro") ?? new List<object>() } };
            var sections = new List<object>();
            foreach (var p in parts)
            {
                if (!Cm.IsMap(p)) return null;
                foreach (var sec in SFmt.Rows(p, "sections"))
                {
                    var last = sections.Count > 0 ? sections[sections.Count - 1] as Dictionary<string, object> : null;
                    if (Json.Bool(sec, "cont") && last != null && Json.Text(last, "name") == Json.Text(sec, "name"))
                        ((List<object>)last["items"]).AddRange(Json.List(sec, "items"));
                    else
                        sections.Add(new Dictionary<string, object> { { "name", Json.Get(sec, "name") }, { "kind", Json.Get(sec, "kind") }, { "items", new List<object>(Json.List(sec, "items")) } });
                }
            }
            note["sections"] = sections;
            return note;
        }

        void MarkSeen()
        {
            if (SelectedId.Length == 0 || !Visible || !Notes.ContainsKey(SelectedId) || seenSent.Contains(SelectedId)) return;
            seenSent.Add(SelectedId);
            Send("seen", SFmt.Map("id", SelectedId));
            var w = FindWeek(SelectedId) as Dictionary<string, object>;
            if (w != null) w["new"] = false;
        }

        public void Select(string id)
        {
            SelectedId = id;
            if (!Notes.ContainsKey(id)) Send("get", SFmt.Map("id", id)); else MarkSeen();
            Changed();
        }

        // ---- login auto-open (patchnotesview.lua autoStep)
        public static string AutoStep(Auto st, bool dailyVisible, double now)
        {
            if (dailyVisible) { st.SawDaily = true; st.ClosedAt = -1; return "wait"; }
            if (st.SawDaily)
            {
                if (st.ClosedAt < 0) st.ClosedAt = now;
                return now - st.ClosedAt < AfterDaily ? "wait" : "show";
            }
            if (st.DailyFirst && now - st.Since < DailyWait) return "wait";
            return "show";
        }

        /// <summary>Per frame: the login auto-open waits for the Daily Reward window and for a modal dialog.</summary>
        public void Poll(double nowMs, bool inGame)
        {
            if (!inGame) return;
            double now = nowMs / 1000;
            if (Pending != null)
            {
                if (ModalOpen()) return;
                if (AutoStep(Pending, DailyVisible(), now) == "show") { Pending = null; Show(); AutoShownAt = now; }
            }
            else if (AutoShownAt >= 0)
            {
                // a Daily Reward window that shows up late goes first: step aside and come back once it is closed
                if (now - AutoShownAt > AutoGuard || !Visible) { AutoShownAt = -1; return; }
                if (DailyVisible()) { Hide(); AutoShownAt = -1; Pending = new Auto { DailyFirst = true, Since = now, SawDaily = true }; }
            }
        }

        // ---- rules (patchnotesview.lua)
        public static string FormatDate(string s, bool shortMonth = false)
        {
            if (s == null || s.Length != 10 || s[4] != '-' || s[7] != '-') return s ?? "";
            if (!int.TryParse(s.Substring(0, 4), out int y) || !int.TryParse(s.Substring(5, 2), out int m) || !int.TryParse(s.Substring(8, 2), out int d) || m < 1 || m > 12) return s;
            string month = MonthNames[m - 1];
            if (shortMonth) month = month.Substring(0, 3);
            return d + " " + month + " " + y;
        }

        public static readonly Dictionary<string, string> SectionColors = new Dictionary<string, string> { { "new", "#7cd35a" }, { "changes", "#e8b84a" }, { "fixes", "#6aa8ff" }, { "balance", "#d07aff" } };

        public static List<Block> Blocks(object note)
        {
            var o = new List<Block>();
            if (!Cm.IsMap(note)) return o;
            o.Add(new Block { Style = "title", Text = Json.Text(note, "title"), Tone = "#f6cf72" });
            if (Json.Text(note, "date").Length > 0) o.Add(new Block { Style = "date", Text = FormatDate(Json.Text(note, "date")), Tone = "#8c8070" });
            foreach (object line in Json.List(note, "intro")) if (line is string t && t.Length > 0) o.Add(new Block { Style = "intro", Text = t });
            foreach (var sec in SFmt.Rows(note, "sections"))
            {
                var items = Json.List(sec, "items");
                if (items.Count == 0) continue;
                string color = SectionColors.TryGetValue(Json.Text(sec, "kind"), out var c) ? c : "text";
                o.Add(new Block { Style = "section", Text = Json.Text(sec, "name"), Tone = color });
                foreach (object it in items)
                {
                    if (!Cm.IsMap(it)) continue;
                    int level = Json.Get(it, "level") is double lv ? (int)lv : 1;
                    var b = new Block { Text = Json.Text(it, "text"), Lead = Json.Text(it, "lead"), Level = level };
                    if (level == 0) b.Style = "paragraph";
                    else { b.Style = "bullet"; b.Level = level >= 2 ? 2 : 1; }
                    if (b.Text.Length > 0 || b.Lead.Length > 0) o.Add(b);
                }
            }
            return o;
        }

        public static string Plain(Block b) => b.Lead.Length > 0 && b.Text.Length > 0 ? b.Lead + " " + b.Text : b.Lead.Length > 0 ? b.Lead : b.Text;

        // ---- changelog
        public static string TagLabel(string tag)
        {
            switch (tag) { case "server": return Loc.T("Server"); case "client": return Loc.T("Client"); case "content": return Loc.T("Content"); case "website": return Loc.T("Website"); }
            return Loc.T("All");
        }

        static bool HasTag(object e, string tag) { foreach (object t in Json.List(e, "tags")) if (t as string == tag) return true; return false; }
        public static bool IsNew(object e, double seenTs) => seenTs > 0 && Json.Number(e, "ts") > seenTs;
        public static double NewestTs(object entries) { double m = 0; foreach (object e in entries as List<object> ?? new List<object>()) m = Math.Max(m, Json.Number(e, "ts")); return m; }
        public static int NewCount(object data, double seenTs) { int n = 0; foreach (var e in SFmt.Rows(data, "entries")) if (IsNew(e, seenTs)) n++; return n; }

        public static string TagText(object e, string tag)
        {
            if (tag == "client")
            {
                int n = Json.Int(e, "client");
                if (Json.Bool(e, "pending") || n == 0) return Loc.T("Client: next update");
                return Loc.T("Client {0}", n);
            }
            return TagLabel(tag);
        }

        /// <summary>Rows of the changelog: a date row, then one entry row per change (the text with its tags in front).</summary>
        public static List<SocialRow> ChangelogRows(object data, string filter, double seenTs, out int shown)
        {
            var rows = new List<SocialRow>();
            shown = 0;
            string lastDate = null;
            foreach (var e in SFmt.Rows(data, "entries"))
            {
                if (Json.Text(e, "text").Length == 0) continue;
                if (!(filter == null || filter == "all" || HasTag(e, filter))) continue;
                string date = Json.Text(e, "date");
                if (date != lastDate) { rows.Add(new SocialRow { Kind = RowKind.Section, Text = FormatDate(date) }); lastDate = date; }
                var sb = new StringBuilder();
                bool isNew = IsNew(e, seenTs);
                if (isNew) sb.Append(Loc.T("NEW")).Append(' ');
                foreach (string tag in TagOrder) if (HasTag(e, tag)) sb.Append('[').Append(TagText(e, tag)).Append("] ");
                sb.Append(Json.Text(e, "text"));
                rows.Add(new SocialRow { Kind = RowKind.Text, Text = sb.ToString(), Tone = isNew ? "good" : "text" });
                shown++;
            }
            return rows;
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            Header1 = Loc.T("Patch Notes");
            Header2 = "";
            if (Tab == "changelog") return ChangelogTab(l);
            if (Weeks.Count == 0) { l.Text(Loc.T("No patch notes yet."), "dim"); return l.Rows; }
            var names = new List<string>();
            int sel = 0;
            for (int i = 0; i < Weeks.Count; i++)
            {
                string id = Json.Text(Weeks[i], "id");
                if (id == SelectedId) sel = i;
                string date = FormatDate(Json.Text(Weeks[i], "date"), true);
                names.Add((date.Length > 0 ? date : id) + "  " + Json.Text(Weeks[i], "title") + (Json.Bool(Weeks[i], "new") ? "  " + Loc.T("NEW") : ""));
            }
            if (Form.ContainsKey("week") && Index("week") != sel)
            {
                int pick = Math.Max(0, Math.Min(Weeks.Count - 1, Index("week")));
                string id = Json.Text(Weeks[pick], "id");
                if (id != SelectedId) Select(id);
                sel = pick;
            }
            Form["week"] = sel.ToString(CultureInfo.InvariantCulture);
            l.Combo(Loc.T("Week"), "week", names);
            l.Combo(Loc.T("Open at login"), "auto", new[] { Loc.T("Yes"), Loc.T("No") });
            if (!Form.ContainsKey("auto")) Form["auto"] = AutoEnabled ? "0" : "1";
            if (!Notes.TryGetValue(SelectedId, out var note)) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            foreach (var b in Blocks(note))
            {
                switch (b.Style)
                {
                    case "title": Header1 = b.Text; break;
                    case "date": Header2 = b.Text; break;
                    case "section": l.Section(b.Text); break;
                    case "bullet": l.Text((b.Level == 2 ? "      - " : "  - ") + Plain(b), b.Level == 2 ? "dim" : "text"); break;
                    default: l.Text(Plain(b), "text"); break;
                }
            }
            return l.Rows;
        }

        public override void OnForm(string key)
        {
            if (key == "auto") Send("auto", SFmt.Map("enabled", Text("auto") == "0"));
            else if (key == "cl_filter") Changed();
        }

        List<SocialRow> ChangelogTab(RowList l)
        {
            if (Changelog == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            if (!Json.Bool(Changelog, "available", true)) { l.Text(Loc.T("The changelog is not available on this server."), "dim"); return l.Rows; }
            string date = Json.Text(Json.Get(Changelog, "server"), "date");
            Header2 = (date.Length > 0 ? Loc.T("Server updated: {0}", FormatDate(date)) : Loc.T("Server updated: unknown")) + "     " + Loc.T("Client: Unity prototype");
            var names = new List<string>();
            foreach (string f in Filters) names.Add(TagLabel(f));
            l.Combo(Loc.T("Show"), "cl_filter", names);
            int idx = Math.Max(0, Math.Min(Filters.Length - 1, Index("cl_filter")));
            if (ChangelogSeenTs == 0) ChangelogSeenTs = LoadSeen();
            var rows = ChangelogRows(Changelog, Filters[idx], ChangelogSeenTs, out int shown);
            if (shown == 0) l.Text(Loc.T("No change matches."), "dim");
            foreach (var r in rows) l.Add(r);
            double newest = NewestTs(Json.Get(Changelog, "entries"));
            if (newest > LoadSeen()) SaveSeen(newest);
            return l.Rows;
        }
    }
}
