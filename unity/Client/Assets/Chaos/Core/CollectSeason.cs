// Seasons (client game_season, extended opcode 246, server season.lua): the overview, the join dialog and the Journey tab.
//   client -> server  open | sync (3 s after the login) | join {confirm:false} | join {confirm:true, mode} | beat (Hardcore heartbeat) | journey | journeyClose
//   server -> client  state {season {name, tag, status (active|upcoming|soon|ended; soon: the launch date is open, no start, no finish, O463), endsIn, startsIn, modifier {name, description}}, mine {seasonal, veteran, eligible, reason,
//                     mode, modeName, hc, heartbeat, fallen {level, cause}}, track [{name, reward, value, progress, unlocked, by}], titles [..], open}
//                     confirm {text, modes [{key, name, short, warning, ssf, hc}]}  | notice {text}
//                     journey {none | name, mode, current, preview, why, finished, set, pieces, piecesTotal, chapters [{key, name, state, level, lockedWhy, text, done, total}]}
//                     journeyChapter {index, objectives [{text, only, target, progress, done}], rewards [{text, piece, clientId, count, look, kind}]}
//                     journeyDone {chapter?, text}
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core
{
    public sealed class SeasonMode { public string Key = "", Name = "", Short = "", Warning = ""; public bool Ssf, Hc; }

    public sealed class JourneyObjective { public string Text = "", Tag, Label = ""; public int Percent; public bool Done; }

    /// <summary>The join dialog's rules (seasonjoin.lua).</summary>
    public static class SeasonJoin
    {
        public const string Default = "standard";

        public static List<SeasonMode> Choices(object data)
        {
            var o = new List<SeasonMode>();
            var seen = new HashSet<string>();
            foreach (var m in CF.Rows(CF.G(data, "modes")))
            {
                string key = CF.G(m, "key") as string;
                if (string.IsNullOrEmpty(key) || !seen.Add(key)) continue;
                o.Add(new SeasonMode { Key = key, Name = CF.T(m, "name", key), Short = CF.T(m, "short", CF.T(m, "name", key)), Warning = CF.T(m, "warning"), Ssf = CF.B(m, "ssf"), Hc = CF.B(m, "hc") });
            }
            if (!seen.Contains(Default)) o.Insert(0, new SeasonMode { Key = Default, Name = "Standard", Short = "Standard" });
            return o;
        }

        public static SeasonMode Find(IList<SeasonMode> choices, string key) => choices?.FirstOrDefault(c => c.Key == key);
        public static bool NeedsAck(SeasonMode c) => c != null && c.Hc;
        public static bool CanJoin(SeasonMode c, bool acked) => c != null && (!NeedsAck(c) || acked);
        public static Dictionary<string, object> Payload(SeasonMode c, bool acked) => CanJoin(c, acked) ? new Dictionary<string, object> { { "confirm", true }, { "mode", c.Key } } : null;
        public static string JoinLabel(SeasonMode c) => c != null && c.Hc ? Loc.T("Join (one life)") : Loc.T("Join");
        public static string WarningText(SeasonMode c) => c == null ? "" : c.Warning.Length > 0 ? c.Warning : c.Name;

        public static string ModeLine(object mine)
        {
            if (!(mine is Dictionary<string, object>)) return null;
            if (CF.G(mine, "fallen") is Dictionary<string, object> f) return Loc.T("Fallen in Hardcore at level {0}. ({1})", CF.I(f, "level"), CF.T(f, "cause", "died"));
            string mode = CF.T(mine, "mode");
            if (mode.Length > 0 && mode != Default) return Loc.T("Mode: {0}.", CF.T(mine, "modeName", mode));
            return null;
        }

        /// <summary>Seconds between beats while a Hardcore character is online, else 0.</summary>
        public static double Heartbeat(object mine)
        {
            if (!(mine is Dictionary<string, object>) || !CF.B(mine, "hc")) return 0;
            double s = CF.N(mine, "heartbeat");
            return s < 1 ? 0 : s;
        }
    }

    public sealed class SeasonState : CollectModel
    {
        public const byte OpcodeId = 246;
        static readonly Dictionary<string, string> OnlyTag = new Dictionary<string, string> { { "hc", "Hardcore" }, { "ssf", "Self-Found" }, { "nossf", "Not Self-Found" }, { "nohc", "Not Hardcore" } };
        static readonly string[] Roman = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" };

        public object State;
        public double StateAt;
        public bool Visible;
        public string Tab = "season", Notice = "";
        // join dialog
        public List<SeasonMode> JoinChoices = new List<SeasonMode>();
        public SeasonMode JoinChoice;
        public bool JoinAcked, JoinOpen;
        public string JoinText = "";
        // heartbeat
        public double BeatSeconds, NextBeatAt;
        // journey
        public object Header;
        public List<Dictionary<string, object>> Chapters = new List<Dictionary<string, object>>();
        public readonly Dictionary<int, Dictionary<string, object>> Details = new Dictionary<int, Dictionary<string, object>>();
        public int Selected;   // 1-based, 0 none
        public string Banner = "";
        public double BannerAt;

        public SeasonState(ExtOpcodes e) : base(e, OpcodeId) { }

        public void Show() { Visible = true; Send("open"); }
        public void Toggle() { if (Visible) Hide(); else Show(); }
        public void Hide() { if (Tab == "journey") CloseJourney(); Visible = false; CloseJoin(); }
        public void Sync() { Send("sync"); }
        public void AskJoin() { Send("join", D("confirm", false)); }

        public void ShowTab(string name)
        {
            bool journey = name == "journey";
            if (journey && Tab != "journey") Send("journey");
            else if (!journey && Tab == "journey") CloseJourney();
            Tab = journey ? "journey" : "season";
        }

        void CloseJourney() { Send("journeyClose"); }

        public void CloseJoin() { JoinOpen = false; JoinChoice = null; JoinAcked = false; }
        public void SelectMode(string key) { JoinChoice = SeasonJoin.Find(JoinChoices, key) ?? JoinChoice; JoinAcked = false; }
        public bool ConfirmJoin()
        {
            var p = SeasonJoin.Payload(JoinChoice, JoinAcked);
            if (p == null) return false;
            CloseJoin();
            return Send("join", p);
        }

        /// <summary>Called every frame: the Hardcore heartbeat.</summary>
        public void Tick(double nowMs)
        {
            if (BeatSeconds > 0 && nowMs >= NextBeatAt) { Send("beat"); NextBeatAt = nowMs + BeatSeconds * 1000; }
        }

        public override void Handle(string action, object data)
        {
            if (action == "state")
            {
                var mine = CF.G(data, "mine");
                if (JoinOpen && mine is Dictionary<string, object> && !CF.B(mine, "eligible")) CloseJoin();
                double s = SeasonJoin.Heartbeat(mine);
                if (s != BeatSeconds) { BeatSeconds = s; NextBeatAt = s > 0 ? Clock() : 0; }
                State = data;
                StateAt = Clock();
                if (CF.B(data, "open")) Visible = true;
            }
            else if (action == "journey") OnHeader(data);
            else if (action == "journeyChapter") OnChapter(data);
            else if (action == "journeyDone") { Banner = DoneText(data); BannerAt = Clock(); }
            else if (action == "confirm")
            {
                CloseJoin();
                JoinChoices = SeasonJoin.Choices(data);
                JoinText = CF.T(data, "text");
                JoinChoice = SeasonJoin.Find(JoinChoices, SeasonJoin.Default);
                JoinOpen = true;
            }
            else if (action == "notice" && CF.T(data, "text").Length > 0) Notice = CF.T(data, "text");
        }

        public void Clear()
        {
            State = null; Visible = false; Tab = "season"; CloseJoin(); BeatSeconds = 0; Header = null; Chapters = new List<Dictionary<string, object>>(); Details.Clear(); Selected = 0; Banner = "";
        }

        // ---------------------------------------------------------------------------------------------- overview rules
        public object Season => CF.G(State, "season");
        public object Mine => CF.G(State, "mine");

        public string TimerText(double nowMs)
        {
            if (Season == null) return "";
            double passed = (nowMs - StateAt) / 1000.0;
            string st = CF.T(Season, "status");
            if (st == "active") return Loc.T("Ends in {0}", PassState.FormatTime(CF.N(Season, "endsIn") - passed));
            if (st == "upcoming") return Loc.T("Starts in {0}", PassState.FormatTime(CF.N(Season, "startsIn") - passed));
            if (st == "soon") return Loc.T("Starts: Coming soon");
            return Loc.T("Ended");
        }

        public string NameLine() => Season == null ? Loc.T("Seasons") : string.Format("{0} {1}", CF.T(Season, "name", "?"), CF.T(Season, "tag"));

        public string ModifierLine()
        {
            var mod = CF.G(Season, "modifier");
            if (Season == null || CF.T(Season, "status") == "ended" || !(mod is Dictionary<string, object>)) return "";
            return Loc.T("Season modifier {0}: {1}", CF.T(mod, "name"), CF.T(mod, "description"));
        }

        public string MineText()
        {
            if (Season == null) return Loc.T("No season is configured on this server.");
            var mine = Mine;
            string name = CF.T(Season, "name", "?"), status = CF.T(Season, "status"), text;
            if (CF.B(mine, "seasonal")) text = Loc.T("This character is a {0} character. Milestones it reaches unlock their rewards for your whole account.", name);
            else if (CF.B(mine, "veteran")) text = Loc.T("This character played a season and is a standard character now.");
            else if (CF.B(mine, "eligible")) text = Loc.T("This character can join {0}: it starts over with nothing and plays only with {0} characters until the end.", name);
            else if (status == "active") text = CF.T(mine, "reason");
            else if (status == "upcoming" || status == "soon") text = Loc.T("The season has not started yet. Make a fresh character to join it when it starts.");
            else text = Loc.T("The season has ended. Its rewards stay on your account.");
            string line = SeasonJoin.ModeLine(mine);
            return line != null ? text + " " + line : text;
        }

        public bool CanJoin => Season != null && CF.B(Mine, "eligible");

        public List<Dictionary<string, object>> Track => CF.Rows(CF.G(State, "track"));

        /// <summary>A track row: progress text, percent, unlocked.</summary>
        public static string TrackProgress(object m, out int pct, out bool unlocked)
        {
            double goal = Math.Max(1, CF.G(m, "value") == null ? 1 : CF.N(m, "value") == 0 ? 1 : CF.N(m, "value"));
            double p = Math.Min(goal, CF.N(m, "progress"));
            unlocked = CF.B(m, "unlocked");
            if (unlocked) { pct = 100; return Loc.T("Unlocked"); }
            pct = (int)Math.Floor(p * 100 / goal);
            return (long)p + " / " + (long)goal;
        }

        public string TitlesLine()
        {
            var t = CF.Values(CF.G(State, "titles"));
            return t.Count > 0 ? Loc.T("Season titles of your account: {0}", string.Join(", ", t)) : "";
        }

        // ---------------------------------------------------------------------------------------------- journey
        public static string RomanOf(int i) => i >= 1 && i <= Roman.Length ? Roman[i - 1] : i.ToString();

        public void OnHeader(object data)
        {
            if (CF.B(data, "none")) { Header = new Dictionary<string, object> { { "none", true } }; Chapters = new List<Dictionary<string, object>>(); Details.Clear(); Selected = 0; return; }
            var old = Chapters;
            Header = data;
            Chapters = CF.Rows(CF.G(data, "chapters"));
            for (int i = 0; i < Chapters.Count; i++)
                if (i >= old.Count || CF.Str(CF.G(old[i], "key")) != CF.Str(CF.G(Chapters[i], "key"))) Details.Remove(i + 1);
            foreach (int k in Details.Keys.ToList()) if (k > Chapters.Count) Details.Remove(k);
            if (Selected < 1 || Selected > Chapters.Count)
            {
                int cur = CF.I(data, "current");
                Selected = cur > 0 ? cur : Chapters.Count > 0 ? LastOpen(Chapters) : 0;
            }
        }

        public static int LastOpen(IList<Dictionary<string, object>> chapters)
        {
            int best = 1;
            for (int i = 0; i < chapters.Count; i++)
            {
                string st = CF.T(chapters[i], "state");
                if (st == "open") return i + 1;
                if (st == "done") best = i + 1;
            }
            return best;
        }

        public void OnChapter(object data)
        {
            int i = CF.I(data, "index");
            if (i < 1 || i > 64) return;
            Details[i] = new Dictionary<string, object> { { "objectives", CF.G(data, "objectives") }, { "rewards", CF.G(data, "rewards") } };
        }

        public void Select(int i) { if (i >= 1 && i <= Chapters.Count) Selected = i; }

        public static string ChapterLabel(object c, int i) => string.Format("{0}. {1}", RomanOf(i), CF.T(c, "name", "?"));

        public static string ChapterStatus(object c)
        {
            string st = CF.T(c, "state");
            if (st == "done") return Loc.T("Complete");
            if (st == "locked") return CF.N(c, "level") > 0 ? Loc.T("Lv {0}", CF.I(c, "level")) : Loc.T("Locked");
            if (st == "preview") return Loc.T("{0} goals", CF.I(c, "total"));
            return CF.I(c, "done") + " / " + CF.I(c, "total");
        }

        public static string ChapterNote(object c) => CF.T(c, "state") == "locked" && CF.G(c, "lockedWhy") != null ? Loc.T("Locked: {0}", CF.T(c, "lockedWhy")) : CF.T(c, "text");

        public static JourneyObjective ObjectiveRow(object o, bool preview)
        {
            double target = Math.Max(1, CF.G(o, "target") == null || CF.N(o, "target") == 0 ? 1 : CF.N(o, "target"));
            string text = CF.T(o, "text", "?");
            string only = CF.T(o, "only");
            string tag = only.Length > 0 && OnlyTag.TryGetValue(only, out var t) ? t : null;
            if (tag != null && text.StartsWith(tag + ":", StringComparison.Ordinal)) tag = null;
            if (preview) return new JourneyObjective { Text = text, Tag = tag, Percent = 0, Label = Loc.T("Goal: {0}", (long)target) };
            if (CF.B(o, "done")) return new JourneyObjective { Text = text, Tag = tag, Percent = 100, Label = Loc.T("Done"), Done = true };
            double p = Math.Max(0, Math.Min(target, CF.N(o, "progress")));
            return new JourneyObjective { Text = text, Tag = tag, Percent = (int)Math.Floor(p * 100 / target), Label = (long)p + " / " + (long)target };
        }

        public static string RewardLine(object r) => CF.T(r, "text") + (CF.B(r, "piece") ? " (set)" : "");

        public string JourneyTitle()
        {
            if (Header == null || CF.B(Header, "none")) return Loc.T("No journey this season");
            string t = CF.T(Header, "name", "Journey");
            return CF.T(Header, "mode").Length > 0 ? t + "  -  " + CF.T(Header, "mode") : t;
        }

        public string JourneySummary()
        {
            if (Header == null || CF.B(Header, "none")) return "";
            var parts = new List<string> { CF.B(Header, "preview") ? Loc.T("Preview") : Loc.T("Chapters {0} / {1}", CF.I(Header, "finished"), Chapters.Count) };
            if (CF.G(Header, "set") != null) parts.Add(Loc.T("{0} set {1} / {2}", CF.T(Header, "set"), CF.I(Header, "pieces"), CF.I(Header, "piecesTotal")));
            return string.Join("   ", parts);
        }

        public bool Preview => Header != null && CF.B(Header, "preview");

        public static string DoneText(object d)
        {
            if (!(d is Dictionary<string, object>)) return "";
            return CF.G(d, "chapter") != null ? Loc.T("Chapter complete: {0}!", CF.T(d, "text")) : Loc.T("Objective done: {0}", CF.T(d, "text"));
        }
    }
}
