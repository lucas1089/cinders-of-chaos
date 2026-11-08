// Party Finder (client game_partyfinder, extended opcode 208, server party_finder.lua) and Group Queue (client game_groupqueue, opcode 160, server groupqueue.lua).
//   Party Finder  client -> server  open | hide | refresh | post {...} | unlist | apply {id, role} | withdraw {id} | accept {id, g} | decline {id, g} | queue {role, a} | unqueue
//                 server -> client  init {acts, roles, my, lv, exp, defExp, lim, notes} | list {rows, mine, badge, applied, queue} | badge {n}
//                                   | notice {text, kind} | nudge {text, a, n}
//   Group Queue   client -> server  open | query | join {arena?, bg?, dungeon? {id, difficulty}} | leave | accept | decline | raid
//                 server -> client  state {enabled, leader, size, inParty, group, arena, bg, dungeons, raid} | check {key, label, left, seconds, accepted, total, mine}
//                                   | checkEnd | msg {text}
// Times come in seconds counted from the moment the list arrived: the panel counts down by the clock it is given.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public static class PartyFinderMath
    {
        public static readonly string[] RoleOrder = { "tank", "healer", "dps" };

        public static string RoleName(string role, object init = null)
        {
            foreach (var r in SFmt.Rows(init, "roles")) if (Json.Text(r, "k") == role && Json.Text(r, "n").Length > 0) return Json.Text(r, "n");
            switch (role) { case "tank": return "Tank"; case "healer": return "Healer"; case "dps": return "DPS"; default: return role ?? "?"; }
        }

        public static string RoleLetter(string role) => role == "tank" ? "T" : role == "healer" ? "H" : role == "dps" ? "D" : "?";

        public static string TimeLeft(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            long h = s / 3600, m = s % 3600 / 60;
            if (h > 0) return h + "h " + m.ToString("00", CultureInfo.InvariantCulture) + "m";
            if (m > 0) return m + "m";
            return s + "s";
        }

        public static string Ago(double seconds)
        {
            long s = (long)Math.Max(0, Math.Floor(seconds));
            if (s < 60) return Loc.T("just now");
            if (s < 3600) return Loc.T("{0}m ago", s / 60);
            return Loc.T("{0}h ago", s / 3600);
        }

        public static int OpenOf(object row, string role) => Json.Int(Json.Get(row, "open"), role);

        /// <summary>"Needs 1 Healer, 2 DPS" or "Full".</summary>
        public static string OpenText(object row, object init = null)
        {
            var parts = new List<string>();
            foreach (var r in RoleOrder) { int n = OpenOf(row, r); if (n > 0) parts.Add(n + " " + RoleName(r, init)); }
            return parts.Count == 0 ? Loc.T("Full") : Loc.T("Needs {0}", string.Join(", ", parts));
        }

        /// <summary>The roles of `my` (what the viewer's class fills) that are open in the row.</summary>
        public static List<string> ApplyRoles(object row, List<object> my)
        {
            var o = new List<string>();
            foreach (object r in my) if (r is string s && OpenOf(row, s) > 0) o.Add(s);
            return o;
        }

        public static bool LevelFits(object row, int level)
        {
            if (level < Json.Int(row, "ml")) return false;
            int xl = Json.Int(row, "xl");
            return !(xl > 0 && level > xl);
        }

        public static string BandText(object row) =>
            Json.Int(row, "xl") > 0 ? Loc.T("Level {0}-{1}", Math.Max(1, Json.Int(row, "ml")), Json.Int(row, "xl")) : Loc.T("Level {0}+", Json.Int(row, "ml"));

        public static string BandShort(object row) =>
            Json.Int(row, "xl") > 0 ? "Lv " + Math.Max(1, Json.Int(row, "ml")) + "-" + Json.Int(row, "xl") : "Lv " + Json.Int(row, "ml") + "+";

        /// <summary>Can the viewer apply: true, or false and the reason shown next to the button.</summary>
        public static bool CanApply(object row, List<object> my, int level, out string why)
        {
            why = "";
            if (Json.Bool(row, "mine")) { why = Loc.T("Your group"); return false; }
            if (Json.Get(row, "ap") is string) { why = Loc.T("Applied"); return false; }
            if (!LevelFits(row, level)) { why = BandText(row); return false; }
            if (ApplyRoles(row, my).Count == 0) { why = Loc.T("No open role for you"); return false; }
            return true;
        }

        public static string MentorTag(string mt) => mt == "mentor" ? Loc.T("Mentoring") : mt == "seeking" ? Loc.T("Looking for mentor") : "";

        public static string SubLine(object row, double elapsed)
        {
            var p = new List<string> { Json.Text(row, "ld", "?") };
            string mt = MentorTag(Json.Text(row, "mt"));
            if (mt.Length > 0) p.Add(mt);
            if (Json.Int(row, "ml") > 1 || Json.Int(row, "xl") > 0) p.Add(BandShort(row));
            p.Add(Loc.T("{0} left", TimeLeft(Json.Number(row, "left") - elapsed)));
            if (Json.Bool(row, "season")) p.Add(Loc.T("Season"));
            return string.Join("  -  ", p);
        }

        public static string NoteText(object row, List<object> notes)
        {
            var p = new List<string>();
            int nk = Json.Int(row, "nk");
            if (nk >= 1 && nk <= notes.Count && notes[nk - 1] is string fixedNote) p.Add(fixedNote);
            if (Json.Text(row, "note").Length > 0) p.Add(Json.Text(row, "note"));
            return string.Join("  -  ", p);
        }

        public static string CompText(object row, object init)
        {
            var p = new List<string>();
            foreach (var m in SFmt.Rows(row, "comp"))
            {
                string role = RoleLetter(Json.Text(m, "r"));
                string st = Json.Text(m, "st");
                p.Add(role + " " + Json.Text(m, "n", "?") + (st == "leader" ? "*" : st == "invited" ? "?" : ""));
            }
            foreach (var r in RoleOrder) for (int i = 0; i < OpenOf(row, r); i++) p.Add(RoleLetter(r) + " -");
            return string.Join("   ", p);
        }

        public static object ActivityOf(List<object> acts, string key) { foreach (object a in acts) if (Json.Text(a, "k") == key) return a; return null; }

        /// <summary>Which part of the form an activity uses: range, targets, title or none.</summary>
        public static string FormKind(object act)
        {
            if (!SFmt.IsMap(act)) return "none";
            if (SFmt.Has(act, "range")) return "range";
            if (Json.List(act, "targets").Count > 0) return "targets";
            if (Json.Bool(act, "title") || Json.Get(act, "title") is bool b && b) return "title";
            return "none";
        }

        /// <summary>The size and wanted caps of an activity: max, and per role.</summary>
        public static int[] Limits(object act, object lim)
        {
            int party = Json.Int(lim, "party") > 0 ? Json.Int(lim, "party") : 10, per = Json.Int(lim, "perRole") > 0 ? Json.Int(lim, "perRole") : 6;
            int max = Json.Int(act, "max") > 0 ? Json.Int(act, "max") : party;
            object p = Json.Get(act, "per");
            return new[] { max, SFmt.Has(p, "tank") ? Json.Int(p, "tank") : per, SFmt.Has(p, "healer") ? Json.Int(p, "healer") : per, SFmt.Has(p, "dps") ? Json.Int(p, "dps") : per };
        }

        static int Int(string text, int fallback) => int.TryParse((text ?? "").Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out int v) ? v : fallback;

        /// <summary>The post input from the form's values (the activity key, texts and chosen options); clamps ranges into the activity's bounds.</summary>
        public static Dictionary<string, object> PostInput(List<object> acts, string a, string role, int exp, string note, bool auto, int tank, int healer, int dps,
            string minLevel, string maxLevel, int nk, string lo, string hi, int target, string title)
        {
            object act = ActivityOf(acts, a);
            var input = new Dictionary<string, object> { { "a", a }, { "role", role }, { "exp", exp }, { "note", note ?? "" }, { "auto", auto },
                { "want", SFmt.Map("tank", tank, "healer", healer, "dps", dps) } };
            int min = Math.Max(1, Int(minLevel, 1));
            input["minLevel"] = min;
            int max = Int(maxLevel, 0);
            input["maxLevel"] = max > 0 ? Math.Max(max, min) : 0;
            input["nk"] = Math.Max(0, nk);
            string kind = FormKind(act);
            if (kind == "range")
            {
                object r = Json.Get(act, "range");
                int rmin = Json.Int(r, "min"), rmax = Json.Int(r, "max");
                int l = Int(lo, rmin), h = Int(hi, l);
                l = Math.Max(rmin, Math.Min(rmax, l));
                h = Math.Max(l, Math.Min(rmax, h));
                input["lo"] = l; input["hi"] = h;
            }
            else if (kind == "targets") input["t"] = Math.Max(0, target);
            else if (kind == "title") input["title"] = title ?? "";
            return input;
        }

        public static string QueueText(object q, List<object> acts, double elapsed, object init)
        {
            if (!SFmt.IsMap(q)) return "";
            object act = Json.Get(q, "a") is string key ? ActivityOf(acts, key) : null;
            string what = act != null ? Json.Text(act, "n") : Loc.T("any activity");
            double since = Json.Number(q, "since") + elapsed;
            return Loc.T("Queued as {0} ({1}) - {2}", RoleName(Json.Text(q, "r"), init), what, since < 60 ? Loc.T("just now") : TimeLeft(since));
        }

        public static string ApplicantLine(object a) => Json.Text(a, "n", "?") + "  Lv " + Json.Int(a, "lv") + " " + Json.Text(a, "vn");
    }

    public sealed class PartyFinderPanel : SocialPanel
    {
        public const byte Opcode = 208;
        readonly ExtOpcodes ext;
        public object Init, Data;
        public int Badge;
        double receivedAt;
        public Func<double> Clock = () => 0;
        /// <summary>A notice, an application or a group nudge: the app shows a toast (text, kind).</summary>
        public Action<string, string> Notice = delegate { };
        int filledFor = -1;

        public PartyFinderPanel(ExtOpcodes e)
        {
            ext = e;
            Tabs.Add(new KeyValuePair<string, string>("browse", "Browse"));
            Tabs.Add(new KeyValuePair<string, string>("my", "My Group"));
            Tab = "browse";
            Form["minLevel"] = "1";
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Visible = true; Status = ""; Send("open"); }
        public override void Hide() { if (Visible) { Visible = false; Send("hide"); } }
        public void Refresh() { Send("refresh"); }
        public override void Clear() { base.Clear(); Init = Data = null; Badge = 0; filledFor = -1; Form["minLevel"] = "1"; }

        double Elapsed => Math.Max(0, (Clock() - receivedAt) / 1000.0);
        public List<object> Acts => Json.List(Init, "acts");
        List<object> My => Json.List(Init, "my");
        int Level => Json.Int(Init, "lv");

        void OnMessage(ExtMessage m)
        {
            object d = m.Data;
            if (!SFmt.IsMap(d)) return;
            switch (m.Action)
            {
                case "init":
                    Init = d;
                    var names = new List<string>();
                    foreach (object r in My) names.Add(PartyFinderMath.RoleName(r as string, Init));
                    Header1 = Loc.T("Level {0}  -  your class plays {1}", Level, string.Join(" / ", names));
                    if (!Form.ContainsKey("exp") && SFmt.Has(d, "defExp")) { var exps = Json.List(d, "exp"); for (int i = 0; i < exps.Count; i++) if (exps[i] is double v && v == Json.Number(d, "defExp")) Form["exp"] = i.ToString(CultureInfo.InvariantCulture); }
                    break;
                case "list":
                    Data = d; receivedAt = Clock(); Badge = Math.Max(0, Json.Int(d, "badge"));
                    var mine = Json.Get(d, "mine");
                    if (SFmt.IsMap(mine) && filledFor != Json.Int(mine, "id") && SFmt.IsMap(Json.Get(mine, "input"))) { filledFor = Json.Int(mine, "id"); FillForm(Json.Get(mine, "input")); }
                    else if (!SFmt.IsMap(mine)) filledFor = -1;
                    break;
                case "badge": Badge = Math.Max(0, Json.Int(d, "n")); break;
                case "notice":
                    string text = Json.Text(d, "text"), kind = Json.Text(d, "kind");
                    Status = text; StatusTone = kind == "error" ? "bad" : kind == "accepted" ? "good" : "text";
                    if (kind == "apply" || kind == "accepted") Notice(text, kind);
                    break;
                case "nudge":
                    string nt = Json.Text(d, "text");
                    if (nt.Length > 0 && nt.Length <= 160) Notice(nt + " " + Loc.T("[Join]"), "nudge");
                    break;
            }
            Changed();
        }

        void FillForm(object input)
        {
            var acts = Acts;
            for (int i = 0; i < acts.Count; i++) if (Json.Text(acts[i], "k") == Json.Text(input, "a")) Form["act"] = i.ToString(CultureInfo.InvariantCulture);
            for (int i = 0; i < My.Count; i++) if (My[i] as string == Json.Text(input, "role")) Form["prole"] = i.ToString(CultureInfo.InvariantCulture);
            Form["lo"] = Json.Int(input, "lo").ToString(CultureInfo.InvariantCulture); Form["hi"] = Json.Int(input, "hi").ToString(CultureInfo.InvariantCulture);
            Form["target"] = Json.Int(input, "t").ToString(CultureInfo.InvariantCulture);
            Form["title"] = Json.Text(input, "title");
            object want = Json.Get(input, "want");
            Form["tank"] = Json.Int(want, "tank").ToString(CultureInfo.InvariantCulture); Form["healer"] = Json.Int(want, "healer").ToString(CultureInfo.InvariantCulture); Form["dps"] = Json.Int(want, "dps").ToString(CultureInfo.InvariantCulture);
            Form["minLevel"] = Math.Max(1, Json.Int(input, "minLevel")).ToString(CultureInfo.InvariantCulture);
            Form["maxLevel"] = Json.Int(input, "maxLevel") > 0 ? Json.Int(input, "maxLevel").ToString(CultureInfo.InvariantCulture) : "";
            Form["note"] = Json.Text(input, "note"); Form["nk"] = Json.Int(input, "nk").ToString(CultureInfo.InvariantCulture);
            var exps = Json.List(Init, "exp");
            for (int i = 0; i < exps.Count; i++) if (exps[i] is double v && v == Json.Number(input, "exp")) Form["exp"] = i.ToString(CultureInfo.InvariantCulture);
            Form["auto"] = Json.Bool(input, "auto") ? "1" : "0";
        }

        public override void OnForm(string key)
        {
            if (key == "act")
            {
                // an activity proposes its wanted counts (a new listing only)
                object act = ActivityAt(Index("act"));
                object s = Json.Get(act, "suggest");
                if (SFmt.IsMap(s) && !SFmt.IsMap(Json.Get(Data, "mine")))
                {
                    Form["tank"] = Json.Int(s, "tank").ToString(CultureInfo.InvariantCulture); Form["healer"] = Json.Int(s, "healer").ToString(CultureInfo.InvariantCulture); Form["dps"] = Json.Int(s, "dps").ToString(CultureInfo.InvariantCulture);
                }
            }
            if (key == "target")
            {
                // a hunt proposes its level band
                var bands = Json.List(ActivityAt(Index("act")), "bands");
                int t = Index("target");
                if (t >= 1 && t <= bands.Count && bands[t - 1] is List<object> band && band.Count > 0 && band[0] is double lo)
                {
                    Form["minLevel"] = ((long)lo).ToString(CultureInfo.InvariantCulture);
                    Form["maxLevel"] = ((long)(band.Count > 1 && band[1] is double hi ? hi : lo)).ToString(CultureInfo.InvariantCulture);
                }
            }
        }

        object ActivityAt(int i) { var a = Acts; return i >= 0 && i < a.Count ? a[i] : null; }

        // ------------------------------------------------------------------------------------ requests
        public void Apply(object row, string role) { Send("apply", SFmt.Map("id", Json.Get(row, "id"), "role", role)); }
        public void Withdraw(object row) { Send("withdraw", SFmt.Map("id", Json.Get(row, "id"))); }
        public void Unlist() { Send("unlist"); }
        public void Accept(object mine, object app) { Send("accept", SFmt.Map("id", Json.Get(mine, "id"), "g", Json.Get(app, "g"))); }
        public void Decline(object mine, object app) { Send("decline", SFmt.Map("id", Json.Get(mine, "id"), "g", Json.Get(app, "g"))); }

        public Dictionary<string, object> PostData()
        {
            var acts = Acts; var my = My;
            object act = ActivityAt(Index("act"));
            int role = Index("prole");
            var exps = Json.List(Init, "exp");
            int ei = Index("exp");
            return PartyFinderMath.PostInput(acts, Json.Text(act, "k"), role >= 0 && role < my.Count ? my[role] as string ?? "" : "",
                ei >= 0 && ei < exps.Count && exps[ei] is double v ? (int)v : Json.Int(Init, "defExp"), Text("note"), Text("auto") == "1",
                Math.Max(0, Index("tank")), Math.Max(0, Index("healer")), Math.Max(0, Index("dps")), Text("minLevel"), Text("maxLevel"), Index("nk"),
                Text("lo"), Text("hi"), Index("target"), Text("title"));
        }

        public void Post() { if (Init == null || Acts.Count == 0) return; filledFor = -1; Send("post", PostData()); }

        public void ToggleQueue()
        {
            if (SFmt.IsMap(Json.Get(Data, "queue"))) { Send("unqueue"); return; }
            var my = My; int ri = Index("qrole"); var acts = Acts; int ai = Index("qact");
            Send("queue", SFmt.Map("role", ri >= 0 && ri < my.Count ? my[ri] as string ?? "" : "", "a", ai > 0 && ai <= acts.Count ? Json.Text(acts[ai - 1], "k") : ""));
        }

        /// <summary>The browse rows the filters keep: own listing first, then the ones applied to, then the rest in the server's order.</summary>
        public List<object> FilteredRows()
        {
            int ai = Index("fact"), ri = Index("frole");
            var acts = Acts;
            string actKey = ai > 0 && ai <= acts.Count ? Json.Text(acts[ai - 1], "k") : "";
            string role = ri >= 1 && ri <= 3 ? PartyFinderMath.RoleOrder[ri - 1] : "";
            bool fits = Text("fits") == "1";
            var mine = new List<object>(); var applied = new List<object>(); var rest = new List<object>();
            foreach (var row in SFmt.Rows(Data, "rows"))
            {
                bool keep = true;
                if (!Json.Bool(row, "mine"))
                {
                    if (actKey.Length > 0 && Json.Text(row, "a") != actKey) keep = false;
                    if (keep && role.Length > 0 && PartyFinderMath.OpenOf(row, role) <= 0 && Json.Text(row, "ap") != role) keep = false;
                    if (keep && fits && !PartyFinderMath.LevelFits(row, Level)) keep = false;
                }
                if (!keep) continue;
                if (Json.Bool(row, "mine")) mine.Add(row); else if (Json.Get(row, "ap") is string) applied.Add(row); else rest.Add(row);
            }
            mine.AddRange(applied); mine.AddRange(rest);
            return mine;
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (Init == null) { l.Text(Loc.T("Loading..."), "dim"); return l.Rows; }
            if (Tab == "my") MyRows(l); else BrowseRows(l);
            return l.Rows;
        }

        static string OnOff(bool on) => on ? "1" : "0";

        void BrowseRows(RowList l)
        {
            var acts = Acts;
            var ao = new List<string> { Loc.T("All activities") }; foreach (var a in acts) ao.Add(Json.Text(a, "n"));
            l.Combo(Loc.T("Activity"), "fact", ao);
            l.Combo(Loc.T("Role"), "frole", new List<string> { Loc.T("Any role"), PartyFinderMath.RoleName("tank", Init), PartyFinderMath.RoleName("healer", Init), PartyFinderMath.RoleName("dps", Init) });
            l.Combo(Loc.T("Level filter"), "fits", new List<string> { Loc.T("Every group"), Loc.T("Only groups my level fits") });
            var rows = FilteredRows();
            l.Section(Data == null ? Loc.T("Loading...") : Loc.T("{0} of {1} groups", rows.Count, SFmt.Rows(Data, "rows").Count));
            double el = Elapsed;
            var notes = Json.List(Init, "notes");
            foreach (var row in rows)
            {
                var r = row;
                var line = l.Row(Json.Text(row, "an", "?"), PartyFinderMath.OpenText(row, Init), Json.Bool(row, "mine") ? "gold" : "text");
                line.Tip = PartyFinderMath.SubLine(row, el);
                string note = PartyFinderMath.NoteText(row, notes);
                if (note.Length > 0) l.Text(note, "dim");
                l.Text(PartyFinderMath.SubLine(row, el), "dim");
                l.Text(PartyFinderMath.CompText(row, Init), "text");
                if (Json.Bool(row, "mine")) line.Btn(Loc.T("Manage"), true, () => SelectTab("my"));
                else if (Json.Get(row, "ap") is string ap) { line.Right = Loc.T("Applied as {0}", PartyFinderMath.RoleName(ap, Init)); line.Btn(Loc.T("Withdraw"), true, () => Withdraw(r)); }
                else
                {
                    bool ok = PartyFinderMath.CanApply(row, My, Level, out string why);
                    if (!ok) line.Right += "  (" + why + ")";
                    foreach (var role in PartyFinderMath.ApplyRoles(row, My)) { string rr = role; line.Btn(Loc.T("Apply as {0}", PartyFinderMath.RoleName(rr, Init)), ok, () => Apply(r, rr)); }
                    if (line.Buttons.Count == 0) line.Btn(Loc.T("Apply"), false, null, why);
                }
            }
            if (Data != null && rows.Count == 0)
                l.Text(SFmt.Rows(Data, "rows").Count > 0 ? Loc.T("No group matches the filters.") : Loc.T("No groups are looking right now. Post your own under My Group."), "dim");
            l.Section(Loc.T("Quick join"));
            object q = Json.Get(Data, "queue");
            if (!SFmt.IsMap(q))
            {
                var ro = new List<string>(); foreach (object r in My) ro.Add(PartyFinderMath.RoleName(r as string, Init));
                l.Combo(Loc.T("Role"), "qrole", ro);
                var qa = new List<string> { Loc.T("Any activity") }; foreach (var a in acts) qa.Add(Json.Text(a, "n"));
                l.Combo(Loc.T("Activity"), "qact", qa);
            }
            else l.Text(PartyFinderMath.QueueText(q, acts, Elapsed, Init), "gold");
            l.Row("").Btn(SFmt.IsMap(q) ? Loc.T("Leave queue") : Loc.T("Join queue"), true, ToggleQueue);
        }

        void MyRows(RowList l)
        {
            var acts = Acts; var my = My;
            object mine = Json.Get(Data, "mine");
            bool listed = SFmt.IsMap(mine);
            l.Section(listed ? Loc.T("Listed: {0}", Json.Text(mine, "an", "?")) : Loc.T("Not listed"));
            if (listed)
            {
                l.Text(PartyFinderMath.OpenText(mine, Init) + "  -  " + Loc.T("{0} left", PartyFinderMath.TimeLeft(Json.Number(mine, "left") - Elapsed)), "gold");
                l.Text(PartyFinderMath.CompText(mine, Init));
            }
            else l.Text(Loc.T("Fill in the form and post: other players see your group under Browse."), "dim");
            var ao = new List<string>(); foreach (var a in acts) ao.Add(Json.Text(a, "n"));
            l.Combo(Loc.T("Activity"), "act", ao);
            object act = ActivityAt(Index("act"));
            switch (PartyFinderMath.FormKind(act))
            {
                case "range": l.Input(Json.Text(Json.Get(act, "range"), "label", Loc.T("Range")) + " (" + Loc.T("{0} to {1}", Json.Int(Json.Get(act, "range"), "min"), Json.Int(Json.Get(act, "range"), "max")) + ")", "lo"); l.Input(Loc.T("To"), "hi"); break;
                case "targets":
                    var to = new List<string> { Loc.T("Any") }; foreach (object t in Json.List(act, "targets")) to.Add(t as string ?? "");
                    l.Combo(Loc.T("Target"), "target", to); break;
                case "title": l.Input(Loc.T("Title"), "title"); break;
            }
            var ro = new List<string>(); foreach (object r in my) ro.Add(PartyFinderMath.RoleName(r as string, Init));
            l.Combo(Loc.T("Your role"), "prole", ro);
            int[] lim = PartyFinderMath.Limits(act, Json.Get(Init, "lim"));
            l.Input(Loc.T("Tanks wanted") + " (0-" + lim[1] + ")", "tank"); l.Input(Loc.T("Healers wanted") + " (0-" + lim[2] + ")", "healer"); l.Input(Loc.T("DPS wanted") + " (0-" + lim[3] + ")", "dps");
            int size = 1 + Math.Max(0, Index("tank")) + Math.Max(0, Index("healer")) + Math.Max(0, Index("dps"));
            l.Text(Loc.T("group of {0} / {1}", size, lim[0]), size > lim[0] ? "bad" : "dim");
            l.Input(Loc.T("Minimum level"), "minLevel"); l.Input(Loc.T("Maximum level"), "maxLevel", Loc.T("empty = none"));
            var nk = new List<string> { Loc.T("No preset note") }; foreach (object n in Json.List(Init, "notes")) nk.Add(n as string ?? "");
            l.Combo(Loc.T("Note"), "nk", nk);
            l.Input(Loc.T("Free note"), "note");
            var eo = new List<string>(); foreach (object m in Json.List(Init, "exp")) { long min = m is double dd ? (long)dd : 0; eo.Add(min >= 60 ? Loc.T("{0} h", min / 60) : Loc.T("{0} min", min)); }
            l.Combo(Loc.T("Listed for"), "exp", eo);
            l.Combo(Loc.T("Accept applicants"), "auto", new List<string> { Loc.T("By hand"), Loc.T("Automatically") });
            l.Row("").Btn(listed ? Loc.T("Update") : Loc.T("Post"), true, Post).Btn(Loc.T("Unlist"), listed, Unlist);
            var apps = listed ? SFmt.Rows(mine, "apps") : new List<object>();
            l.Section(Loc.T("Applications ({0})", apps.Count));
            if (apps.Count == 0) l.Text(listed ? Loc.T("No applications yet.") : Loc.T("Post a listing to get applications."), "dim");
            foreach (var a in apps)
            {
                var app = a;
                l.Row(PartyFinderMath.ApplicantLine(a), PartyFinderMath.RoleName(Json.Text(a, "r"), Init) + "  " + (Json.Bool(a, "q") ? Loc.T("quick join, ") : "") + PartyFinderMath.Ago(Json.Number(a, "ago") + Elapsed))
                    .Btn(Loc.T("Accept"), true, () => Accept(mine, app)).Btn(Loc.T("Decline"), true, () => Decline(mine, app));
            }
        }
    }

    // ---------------------------------------------------------------------------------------- group queue
    public static class GroupQueueMath
    {
        public static readonly string[] ArenaOrder = { "1v1", "2v2", "3v3" };

        public static int ArenaSize(string mode) => mode == "1v1" ? 1 : mode == "2v2" ? 2 : mode == "3v3" ? 3 : 0;
        public static bool InGroup(object state) => SFmt.IsMap(Json.Get(state, "group"));
        public static bool CanEdit(object state) => SFmt.IsMap(state) && !(SFmt.Has(state, "enabled") && !Json.Bool(state, "enabled", true)) && Json.Bool(state, "leader") && !InGroup(state);

        public static List<int> Difficulties(object dungeon)
        {
            var o = new List<int>();
            if (!SFmt.IsMap(dungeon)) { o.Add(1); return o; }
            if (SFmt.Has(dungeon, "fixed")) { o.Add(Json.Int(dungeon, "fixed")); return o; }
            for (int d = 1; d <= Math.Max(1, Json.Int(dungeon, "max", 1)); d++) o.Add(d);
            return o;
        }

        /// <summary>The "join" request of the choice: arena mode or null, battleground, dungeon id (or -1) and difficulty.</summary>
        public static Dictionary<string, object> Payload(string arena, bool bg, int dungeonId, int difficulty)
        {
            var p = new Dictionary<string, object>();
            if (!string.IsNullOrEmpty(arena)) p["arena"] = arena;
            if (bg) p["bg"] = true;
            if (dungeonId >= 0) p["dungeon"] = SFmt.Map("id", dungeonId, "difficulty", Math.Max(1, difficulty));
            return p;
        }

        public static bool Joinable(object state, Dictionary<string, object> payload, out string why)
        {
            why = "";
            if (!SFmt.IsMap(state)) { why = Loc.T("Waiting for the server."); return false; }
            if (SFmt.Has(state, "enabled") && !Json.Bool(state, "enabled", true)) { why = Loc.T("The Group Queue is closed."); return false; }
            if (InGroup(state)) return false;
            if (!Json.Bool(state, "leader")) { why = Loc.T("Only the party leader can queue the party."); return false; }
            if (!payload.ContainsKey("arena") && !payload.ContainsKey("bg") && !payload.ContainsKey("dungeon")) { why = Loc.T("Pick at least one queue."); return false; }
            int size = SFmt.Has(state, "size") ? Json.Int(state, "size") : 1;
            if (payload.TryGetValue("arena", out object am) && ArenaSize(am as string) != size) { why = Loc.T("Arena: 1v1 is played alone, 2v2 as a party of two, 3v3 as a party of three."); return false; }
            int max = SFmt.Has(Json.Get(state, "bg"), "partyMax") ? Json.Int(Json.Get(state, "bg"), "partyMax") : 5;
            if (payload.ContainsKey("bg") && size > max) { why = Loc.T("Your party is too large for the battleground."); return false; }
            return true;
        }

        public static List<KeyValuePair<string, string>> StatusLines(object state, double elapsed)
        {
            var o = new List<KeyValuePair<string, string>>();
            if (!SFmt.IsMap(state)) return o;
            object g = Json.Get(state, "group");
            if (!SFmt.IsMap(g))
            {
                o.Add(new KeyValuePair<string, string>(Loc.T("Not queued."), "dim"));
                if (Json.Bool(state, "inParty") && !Json.Bool(state, "leader")) o.Add(new KeyValuePair<string, string>(Loc.T("Your party leader picks the queues."), "dim"));
                return o;
            }
            var names = new List<string>();
            foreach (var p in SFmt.Rows(g, "picks")) names.Add(Json.Text(p, "label", Json.Text(p, "key")));
            o.Add(new KeyValuePair<string, string>(Loc.T("Queued for: {0}", string.Join(", ", names)), "good"));
            o.Add(new KeyValuePair<string, string>(Loc.T("Waiting {0}", SFmt.Clock(Json.Number(g, "waited") + elapsed)), "text"));
            object chk = Json.Get(g, "check");
            if (SFmt.IsMap(chk)) o.Add(new KeyValuePair<string, string>(Loc.T("Ready check: {0}, {1} of {2} ready", Json.Text(chk, "label", Json.Text(chk, "key")), Json.Int(chk, "accepted"), Json.Int(chk, "total")), "warn"));
            else if (Json.Bool(g, "ready")) o.Add(new KeyValuePair<string, string>(Loc.T("Everyone is ready: the match starts as soon as it can."), "good"));
            o.Add(new KeyValuePair<string, string>(Loc.T("When a queue finds a match, you leave the others. A party gets a ready check first."), "dim"));
            return o;
        }

        /// <summary>The ready check popup: title, sub line, bar percent, seconds left, timer text, answered.</summary>
        public sealed class Check { public string Title = "", Sub = "", Timer = ""; public int Percent; public double Left; public bool Answered; }

        public static Check ReadyCheck(object c, double elapsed, double total)
        {
            if (!SFmt.IsMap(c)) return null;
            total = Math.Max(1, total > 0 ? total : 20);
            double left = Math.Max(0, Json.Number(c, "left") - elapsed);
            return new Check
            {
                Title = Loc.T("{0} is ready to start", Json.Text(c, "label", Json.Text(c, "key", "?"))),
                Sub = Loc.T("{0} of {1} party members ready", Json.Int(c, "accepted"), Math.Max(1, SFmt.Has(c, "total") ? Json.Int(c, "total") : 1)),
                Percent = (int)Math.Floor(Math.Min(100, 100 * left / total) + 0.5), Left = left, Timer = SFmt.Clock(left), Answered = Json.Bool(c, "mine"),
            };
        }
    }

    public sealed class GroupQueuePanel : SocialPanel
    {
        public const byte Opcode = 160;
        readonly ExtOpcodes ext;
        public object State, CheckData;
        double stateAt, checkAt;
        public Func<double> Clock = () => 0;
        public string Arena = "";
        public bool Bg, Dungeon;
        public Action FindGroup = delegate { };

        public GroupQueuePanel(ExtOpcodes e)
        {
            ext = e;
            e.On(Opcode, OnMessage);
        }

        void Send(string action, object data = null) { ext.Send(Opcode, action, data ?? new Dictionary<string, object>()); }

        public override void Show() { Send("open"); }
        public override void Clear() { base.Clear(); State = CheckData = null; Arena = ""; Bg = Dungeon = false; Form.Clear(); }

        /// <summary>The ready check box is up while a check came and its time is not over.</summary>
        public bool CheckOpen => CheckData != null && GroupQueueMath.ReadyCheck(CheckData, (Clock() - checkAt) / 1000.0, Json.Number(CheckData, "seconds")).Left > 0;
        public GroupQueueMath.Check Check => GroupQueueMath.ReadyCheck(CheckData, (Clock() - checkAt) / 1000.0, Json.Number(CheckData, "seconds"));

        void OnMessage(ExtMessage m)
        {
            object d = m.Data ?? new Dictionary<string, object>();
            switch (m.Action)
            {
                case "state":
                    State = d; stateAt = Clock();
                    if (Json.Bool(d, "open")) { Visible = true; Status = ""; }
                    int size = SFmt.Has(d, "size") ? Json.Int(d, "size") : 1;
                    if (Arena.Length > 0 && GroupQueueMath.ArenaSize(Arena) != size) Arena = "";
                    break;
                case "check": CheckData = d; checkAt = Clock(); break;
                case "checkEnd": CheckData = null; Send("query"); break;
                case "msg": Status = Json.Text(d, "text"); StatusTone = "text"; break;
            }
            Changed();
        }

        public void Answer(bool yes) { Send(yes ? "accept" : "decline"); if (!yes) CheckData = null; Changed(); }
        public void RaidCheck() { Send("raid"); }
        public void Query() { Send("query"); }

        object DungeonAt(int i) { var l = Json.List(State, "dungeons"); return i >= 0 && i < l.Count ? l[i] : null; }

        public Dictionary<string, object> CurrentPayload()
        {
            object d = DungeonAt(Index("dungeon"));
            var diffs = GroupQueueMath.Difficulties(d);
            int di = Math.Max(0, Math.Min(diffs.Count - 1, Index("diff", diffs.Count - 1)));
            return GroupQueueMath.Payload(Arena, Bg, Dungeon && d != null ? Json.Int(d, "id") : -1, diffs[di]);
        }

        public void JoinOrLeave()
        {
            if (GroupQueueMath.InGroup(State)) { Send("leave"); return; }
            var p = CurrentPayload();
            if (GroupQueueMath.Joinable(State, p, out _)) Send("join", p);
        }

        public override List<SocialRow> BuildRows()
        {
            var l = new RowList();
            if (!SFmt.IsMap(State)) { l.Text(Loc.T("Waiting for the server."), "dim"); return l.Rows; }
            bool edit = GroupQueueMath.CanEdit(State);
            int size = SFmt.Has(State, "size") ? Json.Int(State, "size") : 1;
            l.Section(Loc.T("Arena"));
            var order = Json.List(Json.Get(State, "arena"), "order");
            var arena = l.Row(Loc.T("Pick a mode that fits your party size."), "", "dim");
            foreach (string mode in order.Count > 0 ? order.ConvertAll(o => o as string ?? "") : new List<string>(GroupQueueMath.ArenaOrder))
            {
                string md = mode; bool fits = GroupQueueMath.ArenaSize(mode) == size;
                arena.Btn((Arena == mode ? "[x] " : "") + mode, fits && edit, () => { Arena = Arena == md ? "" : md; Changed(); },
                    GroupQueueMath.ArenaSize(mode) == 1 ? Loc.T("Arena 1v1: alone.") : Loc.T("Arena {0}: a party of exactly {1}.", mode, GroupQueueMath.ArenaSize(mode)));
            }
            l.Section(Loc.T("Battleground and dungeon"));
            l.Row(Loc.T("Battleground")).Btn(Bg ? Loc.T("[x] Queue") : Loc.T("Queue"), edit, () => { Bg = !Bg; Changed(); });
            var dungeons = Json.List(State, "dungeons");
            l.Row(Loc.T("Dungeon")).Btn(Dungeon ? Loc.T("[x] Queue") : Loc.T("Queue"), edit && dungeons.Count > 0, () => { Dungeon = !Dungeon; Changed(); });
            if (dungeons.Count > 0)
            {
                var names = new List<string>(); foreach (var d in dungeons) names.Add(Loc.T("{0} (level {1})", Json.Text(d, "title"), Json.Int(d, "level", 1)));
                l.Combo(Loc.T("Dungeon"), "dungeon", names);
                var dn = new List<string>(); foreach (int n in GroupQueueMath.Difficulties(DungeonAt(Index("dungeon")))) dn.Add(Loc.T("Difficulty {0}", n));
                l.Combo(Loc.T("Difficulty"), "diff", dn);
            }
            l.Section(Loc.T("Status"));
            foreach (var s in GroupQueueMath.StatusLines(State, (Clock() - stateAt) / 1000.0)) l.Text(s.Key, s.Value);
            var payload = CurrentPayload();
            if (GroupQueueMath.InGroup(State)) l.Row("").Btn(Loc.T("Leave Queues"), true, JoinOrLeave, Loc.T("Leave every queue of the Group Queue (the whole party leaves)."));
            else
            {
                bool ok = GroupQueueMath.Joinable(State, payload, out string why);
                l.Row("", why, "dim").Btn(Loc.T("Join Queues"), ok, JoinOrLeave, why.Length > 0 ? why : Loc.T("Queue in a protection zone, out of combat."));
            }
            var row = l.Row("");
            if (Json.Bool(State, "raid")) row.Btn(Loc.T("Raid check"), Json.Bool(State, "inParty") && Json.Bool(State, "leader") && !GroupQueueMath.InGroup(State), RaidCheck);
            row.Btn(Loc.T("Find a group"), true, () => FindGroup());
            return l.Rows;
        }
    }
}
