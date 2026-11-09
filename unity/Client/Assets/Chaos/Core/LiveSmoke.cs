// The player on a live server (O433, unity/README.md "Player on a live server (CI)"). Pure C#, no Unity types. The player (Unity/ChaosApp.LiveSmoke.cs, flag
// -chaosLiveSmoke OUT_DIR) logs in to a real server through the app's login path, walks a few steps with held keys, opens the main game windows and logs out. This file is
// what can be tested without Unity: the environment, the window list and when a step is done, the walk legs, the tiles counted, the report json and the pass rule.
// Secrets: the environment holds the password; nothing here prints it, and ToJson cuts every secret it is given out of every text it writes.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;

namespace Chaos.Core
{
    /// <summary>What the run reads from the environment. Names (the same as Core.LiveCheck where it has one): CHAOS_LIVE_HOST (default 127.0.0.1), CHAOS_LIVE_PORT (login port,
    /// default 7171), CHAOS_LIVE_ACCOUNT, CHAOS_LIVE_PASSWORD, CHAOS_LIVE_CHARACTER (optional, else the first of the list), CHAOS_LIVE_IDENTITY (extended or chaos, default
    /// extended). The guard key (CHAOS_CLIENT_KEY) and the RSA modulus (CHAOS_RSA_PUBLIC) are read by the app itself, as for any login.</summary>
    public sealed class LiveSmokeEnv
    {
        public string Host = "127.0.0.1", Account = "", Password = "", Character, Identity = "extended";
        public int Port = 7171;
        public readonly List<string> Errors = new List<string>();
        public bool Ok => Errors.Count == 0;

        public static LiveSmokeEnv Read(Func<string, string> get)
        {
            var e = new LiveSmokeEnv();
            string V(string name) { string v = get(name); return v == null ? "" : v.Trim(); }
            if (V("CHAOS_LIVE_HOST").Length > 0) e.Host = V("CHAOS_LIVE_HOST");
            if (V("CHAOS_LIVE_PORT").Length > 0)
            {
                if (!int.TryParse(V("CHAOS_LIVE_PORT"), NumberStyles.None, CultureInfo.InvariantCulture, out int p) || p < 1 || p > 65535) e.Errors.Add("CHAOS_LIVE_PORT is not a port");
                else e.Port = p;
            }
            e.Account = V("CHAOS_LIVE_ACCOUNT");
            if (e.Account.Length == 0) e.Errors.Add("set CHAOS_LIVE_ACCOUNT");
            string pw = get("CHAOS_LIVE_PASSWORD");   // not trimmed: the password is what it is
            e.Password = pw ?? "";
            if (e.Password.Length == 0) e.Errors.Add("set CHAOS_LIVE_PASSWORD");
            if (V("CHAOS_LIVE_CHARACTER").Length > 0) e.Character = V("CHAOS_LIVE_CHARACTER");
            if (V("CHAOS_LIVE_IDENTITY").Length > 0)
            {
                string id = V("CHAOS_LIVE_IDENTITY").ToLowerInvariant();
                if (id != "extended" && id != "chaos") e.Errors.Add("CHAOS_LIVE_IDENTITY must be extended or chaos");
                else e.Identity = id;
            }
            return e;
        }

        /// <summary>The line for the log: host, port, identity. Never the account, the character or the password.</summary>
        public string Describe() => "host " + Host + ", login port " + Port.ToString(CultureInfo.InvariantCulture) + ", identity " + Identity;

        /// <summary>Every secret of the run, for ToJson and the logs.</summary>
        public List<string> Secrets()
        {
            var s = new List<string>();
            foreach (var t in new[] { Password, Account, Character }) if (!string.IsNullOrEmpty(t)) s.Add(t);
            return s;
        }
    }

    /// <summary>One leg of the walk: keys held (WalkInput mask) until some steps were confirmed.</summary>
    public sealed class LiveWalkLeg
    {
        public string Name = "";
        public int Mask, Steps;
    }

    /// <summary>What a leg did.</summary>
    public sealed class LiveWalkResult
    {
        public string Name = "";
        public int Wanted, Confirmed, Cancelled;
        public bool TimedOut;
    }

    /// <summary>The walk of the live run: the keys of a leg are held until the leg's steps are confirmed by the server (the player's moves counter), two steps are refused
    /// (a wall) or the time is up; then a short pause, then the next leg. Mask() is asked every frame with the clock and the two counters of the session and gives the key mask for
    /// that frame (the player's own path: ChaosApp.WalkMaskSource, WalkInputState, GameSession.Walk). No Unity, no session: the counters come in as numbers.</summary>
    public sealed class LiveWalker
    {
        public const double LegTimeoutMs = 3500, GapMs = 450;
        public const int MaxCancels = 2;

        readonly IList<LiveWalkLeg> legs;
        readonly List<LiveWalkResult> results = new List<LiveWalkResult>();
        int leg = -1, moves0, cancels0;
        double legStart, gapUntil = -1;
        bool inGap;

        public LiveWalker(IList<LiveWalkLeg> legs) { this.legs = legs; }

        public IList<LiveWalkResult> Results => results;
        public bool Done { get; private set; }
        public int LegIndex => leg;

        /// <summary>North, south, east, west, then north and south again: two steps each, so the hero ends where it began. A start place with a wall on one side (the temple
        /// stair of the CI server refuses east and west, 2026-11-09) still gets the steps from the legs that are free: a refused leg ends after two refusals.</summary>
        public static List<LiveWalkLeg> DefaultLegs() => new List<LiveWalkLeg>
        {
            new LiveWalkLeg { Name = "north", Mask = WalkInput.Up, Steps = 2 },
            new LiveWalkLeg { Name = "south", Mask = WalkInput.Down, Steps = 2 },
            new LiveWalkLeg { Name = "east", Mask = WalkInput.Right, Steps = 2 },
            new LiveWalkLeg { Name = "west", Mask = WalkInput.Left, Steps = 2 },
            new LiveWalkLeg { Name = "north again", Mask = WalkInput.Up, Steps = 2 },
            new LiveWalkLeg { Name = "south again", Mask = WalkInput.Down, Steps = 2 },
        };

        public int Mask(double nowMs, int moves, int cancels)
        {
            if (Done) return 0;
            if (legs.Count == 0) { Done = true; return 0; }
            if (leg < 0) { StartLeg(0, nowMs, moves, cancels); }
            if (inGap)
            {
                if (nowMs < gapUntil) return 0;
                // late confirmations of the leg that just ended count for it
                var last = results[results.Count - 1];
                last.Confirmed = Math.Max(last.Confirmed, moves - moves0);
                last.Cancelled = Math.Max(last.Cancelled, cancels - cancels0);
                inGap = false;
                if (leg + 1 >= legs.Count) { Done = true; return 0; }
                StartLeg(leg + 1, nowMs, moves, cancels);
            }
            var l = legs[leg];
            int got = moves - moves0, refused = cancels - cancels0;
            bool timedOut = nowMs - legStart >= LegTimeoutMs;
            if (got >= l.Steps || refused >= MaxCancels || timedOut)
            {
                results.Add(new LiveWalkResult { Name = l.Name, Wanted = l.Steps, Confirmed = got, Cancelled = refused, TimedOut = timedOut && got < l.Steps && refused < MaxCancels });
                inGap = true;
                gapUntil = nowMs + GapMs;
                return 0;
            }
            return l.Mask;
        }

        void StartLeg(int index, double nowMs, int moves, int cancels)
        {
            leg = index; legStart = nowMs; moves0 = moves; cancels0 = cancels; inGap = false;
        }
    }

    /// <summary>The window steps of the live run and when a step is done.</summary>
    public static class LiveSmokePlan
    {
        /// <summary>The main windows, in the order they are opened: what a player opens in the first hour. Class names of ChaosApp.MakeWindows.</summary>
        public static readonly string[] MainWindows =
        {
            "EquipmentWindow", "ContainersWindow", "SkillsWindow", "SpellbookWindow", "PassiveTreeWindow", "GoalsWindow", "HuntWindow", "BattleListWindow", "MinimapWindow",
            "ChannelsWindow", "FightWindow", "OutfitWindow", "BankWindow", "StashWindow", "StoreWindow", "HelperWindow", "LootWindow",
            "AchievementsWindow", "BestiaryWindow", "CharmsWindow", "PassWindow", "SeasonWindow", "DailyWindow", "CosmeticsWindow", "PetsWindow", "ProfessionsWindow", "CraftingWindow",
            "LoadoutsWindow", "TowerWindow", "DungeonsWindow", "RaidWindow", "RiftAtlasWindow", "WaystoneAtlasWindow", "ArenaWindow", "BountyWindow",
            "MarketWindow", "GuildWindow", "PartyFinderWindow", "LeaderboardWindow", "FactionsWindow", "ItemFinderWindow", "OrbExchangeWindow", "MapMarkersWindow",
        };

        /// <summary>Windows whose data comes from the base protocol or from the client alone: no extended answer is expected, so none is not a warning.</summary>
        public static readonly string[] Native =
        {
            "EquipmentWindow", "ContainersWindow", "BattleListWindow", "MinimapWindow", "ChannelsWindow", "FightWindow", "OutfitWindow", "MapMarkersWindow", "LootWindow",
        };

        public static bool IsNative(string windowClass) => Array.IndexOf(Native, windowClass) >= 0;

        /// <summary>The steps (Core/Phase10F.cs WindowSmokePlan.GameSteps, windows only) for the main windows that exist in `available` (the class names of the app's window list);
        /// the ones that do not exist are listed in `missing`.</summary>
        public static List<SmokeStep> Windows(IEnumerable<string> available, out List<string> missing)
        {
            var have = new HashSet<string>(available ?? new string[0], StringComparer.Ordinal);
            var use = new List<string>();
            missing = new List<string>();
            foreach (var w in MainWindows) { if (have.Contains(w)) use.Add(w); else missing.Add(w); }
            return WindowSmokePlan.GameSteps(new string[0], new int[0], use, new string[0], new string[0]);
        }

        // a step stays open at least MinMs (the window asks its module in its own tick), ends QuietMs after the last extended message once one came, and at the latest at MaxMs
        public const double MinMs = 700, QuietMs = 350, MaxMs = 3000;

        /// <summary>elapsed: ms since the step opened; sinceAnswerMs: ms since the last extended message (the step's start when none came); answered: one came.</summary>
        public static bool StepReady(double elapsedMs, double sinceAnswerMs, bool answered)
        {
            if (elapsedMs >= MaxMs) return true;
            if (elapsedMs < MinMs) return false;
            return answered && sinceAnswerMs >= QuietMs;
        }

        /// <summary>Tiles of the player's floor inside the drawn view (viewW x viewH tiles round the hero) that hold at least one thing: the ground the map draws.</summary>
        public static int TilesDrawn(World w, int viewW, int viewH)
        {
            if (w == null || w.Player == null) return 0;
            var me = w.Player.Position;
            int n = 0;
            int left = viewW / 2, top = viewH / 2;
            for (int dy = -top; dy <= viewH - top - 1; dy++)
                for (int dx = -left; dx <= viewW - left - 1; dx++)
                {
                    var t = w.Get(new Pos(me.X + dx, me.Y + dy, me.Z));
                    if (t != null && t.Things.Count > 0) n++;
                }
            return n;
        }
    }

    /// <summary>One window step of the live run: which extended opcodes sent something while it was open.</summary>
    public sealed class LiveSmokeWindow
    {
        public string Name = "", Class = "";
        public bool Native;
        public readonly SortedSet<int> Opcodes = new SortedSet<int>();
        public int Answers;
        public double Ms;
        public SmokeRecord Record;
        public bool NoAnswer => Answers == 0;
    }

    /// <summary>The run's report (live_smoke.json), the pass rule and the log lines.</summary>
    public sealed class LiveSmokeReport
    {
        public const int MinSteps = 3;   // steps the server must confirm for the walk to count

        public string Identity = "extended";
        public bool LoginOk, EnterOk, LoggedOut, Finished;
        public string LoginError = "", EnterError = "", Closed = "", Aborted = "";
        public double EnterMs = -1;
        public int TilesInModel, TilesDrawn, TilesDrawnAfterWalk;
        public int StepsSent, StepsConfirmed, StepsCancelled, NetDx, NetDy;
        public IList<LiveWalkResult> Legs = new List<LiveWalkResult>();
        public readonly List<LiveSmokeWindow> Windows = new List<LiveSmokeWindow>();
        public readonly List<string> MissingWindows = new List<string>();
        public readonly SortedSet<int> OpcodesSeen = new SortedSet<int>();
        public readonly SmokeReport Smoke = new SmokeReport();
        public int Sheets, Screenshots;

        public bool WalkOk => StepsConfirmed >= MinSteps;
        public int Exceptions => Smoke.Total(SmokeIssueKind.Exception) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Exception);
        public int LayoutErrors => Smoke.Total(SmokeIssueKind.Layout) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Layout);
        public int LoggedErrors => Smoke.Total(SmokeIssueKind.Error) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Error);
        public int NoAnswerCount { get { int n = 0; foreach (var w in Windows) if (w.NoAnswer && !w.Native) n++; return n; } }
        public int AnsweredCount { get { int n = 0; foreach (var w in Windows) if (!w.NoAnswer) n++; return n; } }

        /// <summary>What fails the run: login, entering, the walk, a closed session, an exception, an abort. A window without an answer is a warning, never a failure.</summary>
        public List<string> Failures()
        {
            var f = new List<string>();
            if (Aborted.Length > 0) f.Add("aborted: " + Aborted);
            if (!LoginOk) f.Add("login failed" + (LoginError.Length > 0 ? ": " + LoginError : ""));
            if (!EnterOk) f.Add("did not enter the game" + (EnterError.Length > 0 ? ": " + EnterError : ""));
            if (LoginOk && EnterOk && !WalkOk) f.Add("walk failed: " + StepsConfirmed + " steps confirmed, at least " + MinSteps + " needed");
            if (Closed.Length > 0) f.Add("the session closed: " + Closed);
            if (Exceptions > 0) f.Add(Exceptions + " exceptions logged");
            return f;
        }

        public List<string> Warnings()
        {
            var w = new List<string>();
            foreach (var x in Windows) if (x.NoAnswer && !x.Native) w.Add(x.Class + ": no extended answer from the server");
            foreach (var m in MissingWindows) w.Add(m + ": not a window of this build");
            if (LayoutErrors > 0) w.Add(LayoutErrors + " IMGUI layout errors");
            if (LoggedErrors > 0) w.Add(LoggedErrors + " logged errors");
            if (EnterOk && LoginOk && !LoggedOut) w.Add("no clean logout (the server did not close the connection)");
            if (EnterOk && TilesDrawn == 0) w.Add("no tile in the drawn view");
            return w;
        }

        public bool Pass => Failures().Count == 0;

        public string SummaryLine() =>
            "chaos live smoke: identity " + Identity + ", login " + (LoginOk ? "ok" : "FAILED") + ", entered " + (EnterOk ? "ok" : "FAILED") + ", walk " + StepsConfirmed + " of " + StepsSent
            + " steps confirmed, " + TilesDrawn + " tiles drawn, " + Windows.Count + " windows (" + AnsweredCount + " with an answer, " + NoAnswerCount + " without), "
            + Exceptions + " exceptions, " + LayoutErrors + " layout errors, " + (Pass ? "pass" : "FAIL");

        /// <summary>The name of sheet N (0 based) of the contact sheets.</summary>
        public static string SheetName(int sheet) => "live_smoke_sheet_" + (sheet + 1).ToString(CultureInfo.InvariantCulture) + ".png";

        // ------------------------------------------------------------------------------------ json
        static string Q(string s, IList<string> secrets)
        {
            s = s ?? "";
            if (secrets != null) foreach (var x in secrets) if (!string.IsNullOrEmpty(x)) s = s.Replace(x, "<removed>");
            var b = new StringBuilder("\"");
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': b.Append("\\\""); break;
                    case '\\': b.Append("\\\\"); break;
                    case '\n': b.Append("\\n"); break;
                    case '\r': b.Append("\\r"); break;
                    case '\t': b.Append("\\t"); break;
                    default:
                        if (c < 0x20 || c > 0x7e) b.Append("\\u").Append(((int)c).ToString("x4", CultureInfo.InvariantCulture)); else b.Append(c);
                        break;
                }
            }
            return b.Append('"').ToString();
        }

        static string Bool(bool v) => v ? "true" : "false";

        static string Ints(IEnumerable<int> v) => "[" + string.Join(",", v.Select(i => i.ToString(CultureInfo.InvariantCulture))) + "]";

        static string Strs(IEnumerable<string> v, IList<string> secrets) => "[" + string.Join(",", v.Select(s => Q(s, secrets))) + "]";

        static string Issues(SmokeRecord r, IList<string> secrets)
        {
            var b = new StringBuilder("[");
            for (int i = 0; i < r.Issues.Count; i++)
            {
                var x = r.Issues[i];
                string kind = x.Kind == SmokeIssueKind.Exception ? "exception" : x.Kind == SmokeIssueKind.Layout ? "layout" : "error";
                b.Append(i == 0 ? "" : ",").Append("{\"kind\":").Append(Q(kind, null)).Append(",\"message\":").Append(Q(x.Message, secrets)).Append(",\"stack\":").Append(Q(x.Stack, secrets))
                 .Append(",\"count\":").Append(x.Count.ToString(CultureInfo.InvariantCulture)).Append('}');
            }
            return b.Append(']').ToString();
        }

        /// <summary>live_smoke.json: ASCII only, stable order. Every text goes through the secret cut (the password, the account name, the character name).</summary>
        public string ToJson(IList<string> secrets)
        {
            var inv = CultureInfo.InvariantCulture;
            var b = new StringBuilder();
            b.Append("{\n \"identity\":").Append(Q(Identity, null)).Append(",\n \"pass\":").Append(Bool(Pass)).Append(",\n \"failures\":").Append(Strs(Failures(), secrets))
             .Append(",\n \"warnings\":").Append(Strs(Warnings(), secrets));
            b.Append(",\n \"login\":{\"ok\":").Append(Bool(LoginOk)).Append(",\"error\":").Append(Q(LoginError, secrets)).Append('}');
            b.Append(",\n \"enter\":{\"ok\":").Append(Bool(EnterOk)).Append(",\"error\":").Append(Q(EnterError, secrets)).Append(",\"ms\":").Append(Math.Round(EnterMs).ToString("0", inv)).Append('}');
            b.Append(",\n \"map\":{\"tilesInModel\":").Append(TilesInModel.ToString(inv)).Append(",\"tilesDrawn\":").Append(TilesDrawn.ToString(inv))
             .Append(",\"tilesDrawnAfterWalk\":").Append(TilesDrawnAfterWalk.ToString(inv)).Append('}');
            b.Append(",\n \"walk\":{\"ok\":").Append(Bool(WalkOk)).Append(",\"sent\":").Append(StepsSent.ToString(inv)).Append(",\"confirmed\":").Append(StepsConfirmed.ToString(inv))
             .Append(",\"cancelled\":").Append(StepsCancelled.ToString(inv)).Append(",\"dx\":").Append(NetDx.ToString(inv)).Append(",\"dy\":").Append(NetDy.ToString(inv)).Append(",\"legs\":[");
            for (int i = 0; i < Legs.Count; i++)
            {
                var l = Legs[i];
                b.Append(i == 0 ? "" : ",").Append("{\"name\":").Append(Q(l.Name, null)).Append(",\"wanted\":").Append(l.Wanted.ToString(inv)).Append(",\"confirmed\":").Append(l.Confirmed.ToString(inv))
                 .Append(",\"cancelled\":").Append(l.Cancelled.ToString(inv)).Append(",\"timedOut\":").Append(Bool(l.TimedOut)).Append('}');
            }
            b.Append("]}");
            b.Append(",\n \"summary\":{\"windows\":").Append(Windows.Count.ToString(inv)).Append(",\"answered\":").Append(AnsweredCount.ToString(inv)).Append(",\"noAnswer\":").Append(NoAnswerCount.ToString(inv))
             .Append(",\"exceptions\":").Append(Exceptions.ToString(inv)).Append(",\"layoutErrors\":").Append(LayoutErrors.ToString(inv)).Append(",\"loggedErrors\":").Append(LoggedErrors.ToString(inv))
             .Append(",\"screenshots\":").Append(Screenshots.ToString(inv)).Append(",\"sheets\":").Append(Sheets.ToString(inv)).Append(",\"loggedOut\":").Append(Bool(LoggedOut))
             .Append(",\"finished\":").Append(Bool(Finished)).Append('}');
            b.Append(",\n \"opcodesSeen\":").Append(Ints(OpcodesSeen)).Append(",\n \"missingWindows\":").Append(Strs(MissingWindows, null)).Append(",\n \"windows\":[");
            for (int i = 0; i < Windows.Count; i++)
            {
                var w = Windows[i];
                b.Append(i == 0 ? "" : ",").Append("\n  {\"name\":").Append(Q(w.Name, null)).Append(",\"native\":").Append(Bool(w.Native)).Append(",\"answers\":").Append(w.Answers.ToString(inv))
                 .Append(",\"opcodes\":").Append(Ints(w.Opcodes)).Append(",\"ms\":").Append(Math.Round(w.Ms).ToString("0", inv));
                if (w.Record != null)
                {
                    var r = w.Record;
                    b.Append(",\"openAtEnd\":").Append(Bool(r.OpenAtEnd)).Append(",\"offScreen\":").Append(Bool(r.OffScreen)).Append(",\"zeroSize\":").Append(Bool(r.ZeroSize))
                     .Append(",\"oversize\":").Append(Bool(r.Oversize)).Append(",\"exceptions\":").Append(Issues(r, secrets));
                }
                b.Append('}');
            }
            b.Append("\n ],\n \"background\":").Append(Issues(Smoke.BackgroundRecord, secrets)).Append("\n}\n");
            return b.ToString();
        }
    }
}
