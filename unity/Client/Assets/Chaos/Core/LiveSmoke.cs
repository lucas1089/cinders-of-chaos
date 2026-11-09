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
        /// <summary>The fresh, never-logged-in character of the new player first minute (CHAOS_LIVE_NEW_ACCOUNT, _PASSWORD, _CHARACTER: all three or none). Empty: the step is skipped.</summary>
        public string NewAccount = "", NewPassword = "", NewCharacter = "";
        public bool HasNewPlayer => NewAccount.Length > 0 && NewPassword.Length > 0 && NewCharacter.Length > 0;
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
            e.NewAccount = V("CHAOS_LIVE_NEW_ACCOUNT");
            e.NewPassword = get("CHAOS_LIVE_NEW_PASSWORD") ?? "";
            e.NewCharacter = V("CHAOS_LIVE_NEW_CHARACTER");
            int given = (e.NewAccount.Length > 0 ? 1 : 0) + (e.NewPassword.Length > 0 ? 1 : 0) + (e.NewCharacter.Length > 0 ? 1 : 0);
            if (given != 0 && given != 3) e.Errors.Add("set all of CHAOS_LIVE_NEW_ACCOUNT, CHAOS_LIVE_NEW_PASSWORD and CHAOS_LIVE_NEW_CHARACTER, or none");
            return e;
        }

        /// <summary>The line for the log: host, port, identity. Never the account, the character or the password.</summary>
        public string Describe() => "host " + Host + ", login port " + Port.ToString(CultureInfo.InvariantCulture) + ", identity " + Identity;

        /// <summary>Every secret of the run, for ToJson and the logs.</summary>
        public List<string> Secrets()
        {
            var s = new List<string>();
            foreach (var t in new[] { Password, Account, Character, NewPassword, NewAccount, NewCharacter }) if (!string.IsNullOrEmpty(t)) s.Add(t);
            return s;
        }
    }

    /// <summary>One leg of the walk: keys held (WalkInput mask) until `Steps` steps were sent (not confirmed: see LiveWalker).</summary>
    public sealed class LiveWalkLeg
    {
        public string Name = "";
        public int Mask, Steps;
        /// <summary>A way back: its steps are where the hero stands after the leg before it (by position when the walker has one, else the steps that leg confirmed), so the
        /// hero ends where it began; nothing to undo, nothing to walk back.</summary>
        public bool Mirror;
    }

    /// <summary>What a leg did. Sent = steps the client sent in the leg, Confirmed = moves of the player the server sent, Cancelled = steps the server refused.</summary>
    public sealed class LiveWalkResult
    {
        public string Name = "";
        public int Wanted, Sent, Confirmed, Cancelled;
        public bool TimedOut;
        /// <summary>Steps sent but neither confirmed nor refused when the leg was closed (a time out).</summary>
        public int Lost => Math.Max(0, Sent - Confirmed - Cancelled);
    }

    /// <summary>The walk of the live run. The key of a leg is held until the leg's steps are SENT (the session's WalksSent counter), then let go, then the leg waits until every
    /// step it sent is answered (confirmed by the player's moves counter or refused by a cancel), or the time is up; then a short pause, then the next leg. Releasing by the
    /// confirmed count was the bug of run 2 (2026-11-09): the client sends the next step up to WalkTiming.PreWalkLeadMs before the glide of the last ends and keeps up to
    /// WalkTiming.MaxPending steps out, so with a key held until the server confirmed N steps, N+1 or N+2 were already sent, the extra tile was never checked and the way back
    /// had more to undo. A held key sends one step per frame at most and Mask() is asked every frame before the key path, so the count of sent steps is exact: the hero
    /// never goes past the planned tile. A refused step ends the hold at once (a wall or a creature). Mask() is asked every frame with the clock and the counters of the session
    /// and gives the key mask for that frame (the player's own path: ChaosApp.WalkMaskSource, WalkInputState, GameSession.Walk). No Unity, no session: the counters come in as numbers.</summary>
    public sealed class LiveWalker
    {
        public const double LegTimeoutMs = 3500, GapMs = 450;
        public const int MaxCancels = 2;
        /// <summary>Tiles past a leg's planned end that LegsAround wants walkable too.</summary>
        public const int PlanMargin = 1;

        readonly IList<LiveWalkLeg> legs;
        readonly Func<Pos> where;
        readonly List<LiveWalkResult> results = new List<LiveWalkResult>();
        int leg = -1, moves0, cancels0, sent0;
        Pos legFrom;
        double legStart, gapUntil = -1;
        bool inGap, released;

        /// <summary>`where` gives the player's position (for the way back by position); null: the way back is what the leg before confirmed.</summary>
        public LiveWalker(IList<LiveWalkLeg> legs, Func<Pos> where = null) { this.legs = legs; this.where = where; }

        public IList<LiveWalkResult> Results => results;
        public bool Done { get; private set; }
        public int LegIndex => leg;

        static readonly Dir[] Four = { Dir.North, Dir.South, Dir.East, Dir.West };

        static int MaskOf(Dir d) => d == Dir.North ? WalkInput.Up : d == Dir.South ? WalkInput.Down : d == Dir.East ? WalkInput.Right : WalkInput.Left;

        static Dir Opposite(Dir d) => d == Dir.North ? Dir.South : d == Dir.South ? Dir.North : d == Dir.East ? Dir.West : Dir.East;

        static string NameOf(Dir d) => d == Dir.North ? "north" : d == Dir.South ? "south" : d == Dir.East ? "east" : "west";

        /// <summary>The legs for a start tile: for north, south, east and west in this order, the tiles the client itself calls walkable (the check of the prediction, WalkMap.Walkable)
        /// up to `steps` of them, as one leg out and one leg back. Every tile a leg can reach is checked: the planned ones and `margin` more past the end (a step sent too many still
        /// lands on a checked tile). The way back needs none: its steps are the distance to the start, it stops there. A leg is cut so that its planned length plus the margin is walkable (a corridor of two free tiles
        /// gives a leg of one step); a direction with no such run has no leg, so a step the server refuses later is a real finding (the client thought the tile free), not a wall of
        /// the start place. The legs come in pairs, so the hero ends where it began. None free: no leg.</summary>
        public static List<LiveWalkLeg> LegsAround(Pos start, Func<Pos, bool> walkable, int steps = 2, int margin = PlanMargin)
        {
            var legs = new List<LiveWalkLeg>();
            foreach (var d in Four)
            {
                var p = start;
                int run = 0;
                while (run < steps + margin)
                {
                    var q = WalkDirs.Step(p, d);
                    if (!walkable(q)) break;
                    p = q; run++;
                }
                int k = Math.Min(steps, run - margin);
                if (k <= 0) continue;
                legs.Add(new LiveWalkLeg { Name = NameOf(d), Mask = MaskOf(d), Steps = k });
                legs.Add(new LiveWalkLeg { Name = "back " + NameOf(Opposite(d)), Mask = MaskOf(Opposite(d)), Steps = k, Mirror = true });
            }
            return legs;
        }

        /// <summary>`sent` is the session's WalksSent counter; `moves` the player's moves the server confirmed; `cancels` the refused steps.</summary>
        public int Mask(double nowMs, int moves, int cancels, int sent)
        {
            if (Done) return 0;
            if (legs.Count == 0) { Done = true; return 0; }
            if (leg < 0) { StartLeg(0, nowMs, moves, cancels, sent); }
            if (inGap)
            {
                if (nowMs < gapUntil) return 0;
                // late answers of the leg that just ended count for it
                var last = results[results.Count - 1];
                last.Confirmed = Math.Max(last.Confirmed, moves - moves0);
                last.Cancelled = Math.Max(last.Cancelled, cancels - cancels0);
                last.Sent = Math.Max(last.Sent, sent - sent0);
                inGap = false;
                if (leg + 1 >= legs.Count) { Done = true; return 0; }
                StartLeg(leg + 1, nowMs, moves, cancels, sent);
            }
            var l = legs[leg];
            if (l.Steps <= 0)
            {
                // a way back after a leg that went nowhere: nothing to walk
                results.Add(new LiveWalkResult { Name = l.Name, Wanted = 0 });
                inGap = true;
                gapUntil = nowMs;
                return 0;
            }
            int got = moves - moves0, refused = cancels - cancels0, out_ = sent - sent0;
            bool timedOut = nowMs - legStart >= LegTimeoutMs;
            // the key goes up when the planned steps are out, or one is refused, or the time is up
            if (!released && (out_ >= l.Steps || refused > 0 || timedOut)) released = true;
            bool answered = (out_ >= l.Steps || refused > 0) && got + refused >= out_;
            if (released && (answered || refused >= MaxCancels || timedOut))
            {
                results.Add(new LiveWalkResult { Name = l.Name, Wanted = l.Steps, Sent = out_, Confirmed = got, Cancelled = refused, TimedOut = timedOut && !answered });
                inGap = true;
                gapUntil = nowMs + GapMs;
                return 0;
            }
            return released ? 0 : l.Mask;
        }

        void StartLeg(int index, double nowMs, int moves, int cancels, int sent)
        {
            leg = index; legStart = nowMs; moves0 = moves; cancels0 = cancels; sent0 = sent; inGap = false; released = false;
            var l = legs[index];
            if (l.Mirror && results.Count > 0)
            {
                var prev = results[results.Count - 1];
                // back by position: the steps from where the hero stands to where the leg before it began
                if (where != null) l.Steps = Math.Max(Math.Abs(where().X - legFrom.X), Math.Abs(where().Y - legFrom.Y));
                else l.Steps = prev.Confirmed;
            }
            if (where != null) legFrom = where();
        }
    }

    /// <summary>What a window is expected to do when it opens on a live server. Asks: it sends its request on open (or its model does), the server answers on an extended opcode.
    /// Native: the data comes from the base protocol or the client alone. Local: nothing is sent on open (the player's own settings, or a request that waits for typed input).
    /// Prefetch: the module is asked once at login (Opcode), opening the window sends nothing, the data is there already.</summary>
    public enum LiveWindowMode { Asks, Native, Local, Prefetch }

    /// <summary>The rule of one window class (LiveSmokePlan.RuleOf).</summary>
    public sealed class LiveWindowRule
    {
        public LiveWindowMode Mode = LiveWindowMode.Asks;
        public int Opcode;
        public string Why = "";
    }

    /// <summary>Where a window ends in the report: every window is exactly one of these.</summary>
    public enum LiveWindowStatus { Answered, Prefetched, Local, NeedsCondition, NoAnswer }

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

        /// <summary>The first live run (2026-11-09, both identities) found four windows without an answer, and the code says none of them should get one on open:
        /// Skills (the main client's game_skillstats asks `get` on opcode 119 at the game start, the server pushes the numbers on every change; the Unity Progress.Start does the same
        /// 1.8 s after entering), Dungeons (game_dungeons asks `fetch` on opcode 109 at the game start only, Endgame.Start 2.2 s after entering; opening it sends nothing), Helper (its
        /// settings are the character's own, saved in the player's prefs; the loop runs whether the window is open or not) and the Item Finder (it asks only once two letters are typed).</summary>
        public static LiveWindowRule RuleOf(string windowClass)
        {
            if (IsNative(windowClass)) return new LiveWindowRule { Mode = LiveWindowMode.Native, Why = "base protocol or client only" };
            switch (windowClass)
            {
                case "SkillsWindow": return new LiveWindowRule { Mode = LiveWindowMode.Prefetch, Opcode = SkillStats.Opcode, Why = "stat rows asked at the game start, pushed on every change" };
                case "DungeonsWindow": return new LiveWindowRule { Mode = LiveWindowMode.Prefetch, Opcode = DungeonsState.Opcode, Why = "list fetched once at the game start" };
                case "HelperWindow": return new LiveWindowRule { Mode = LiveWindowMode.Local, Why = "the character's own settings, nothing to ask" };
                case "ItemFinderWindow": return new LiveWindowRule { Mode = LiveWindowMode.Local, Why = "asks only after two typed letters" };
                default: return new LiveWindowRule();
            }
        }

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
        public bool Native => LiveSmokePlan.IsNative(Class);
        public LiveWindowRule Rule => LiveSmokePlan.RuleOf(Class);
        public readonly SortedSet<int> Opcodes = new SortedSet<int>();
        public int Answers;
        public double Ms;
        public SmokeRecord Record;
        public bool NoAnswer => Answers == 0;
    }

    /// <summary>What the Helper window shows right now, read by the player each frame (Unity/Windows/HelperWindow.cs OnboardingView): open, the tab, whether the gold hint was drawn this
    /// frame, the hint text, whether the blink time is still running.</summary>
    public sealed class LiveHelperView
    {
        public bool Open, HintDrawn, BlinkActive;
        public int Tab = -1;
        public string Hint = "";
    }

    public enum LiveNewPlayerAction { Wait, Screenshot, Done }

    /// <summary>The first minute of a new player in the live run (O433): the "newplayer" block of live_smoke.json and its failure lines. `Ran` is false when the run had no fresh
    /// character (the variables CHAOS_LIVE_NEW_* unset): no failure.</summary>
    public sealed class LiveNewPlayerResult
    {
        /// <summary>The Helper's Shooter tab, where Auto setup is (HelperWindow tab 1).</summary>
        public const int ShooterTab = 1;

        public bool Ran, LoginOk, EnterOk, ToastSeen, HelperAsked, HelperOpened, HintShown, BlinkActive, LoggedOut;
        public int Tab = -1;
        public string Hint = "", Error = "", Screenshot = "";
        public double ToastMs = -1, HelperMs = -1;

        public List<string> Failures()
        {
            var f = new List<string>();
            if (!Ran) return f;
            if (Error.Length > 0) f.Add("newplayer: " + Error);
            if (!(LoginOk && EnterOk)) { if (Error.Length == 0) f.Add("newplayer: the fresh character did not get into the game"); return f; }
            if (!ToastSeen) { f.Add("newplayer: no welcome toast after " + (int)(LiveNewPlayerStep.ToastLimitMs / 1000) + " s in the game"); return f; }
            if (!HelperAsked) f.Add("newplayer: the welcome toast came without openHelper");
            if (!HelperOpened) f.Add("newplayer: the Helper did not open by itself on the welcome toast");
            else
            {
                if (Tab != ShooterTab) f.Add("newplayer: the Helper opened on tab " + Tab + ", not on Auto setup (tab " + ShooterTab + ")");
                if (!HintShown) f.Add("newplayer: the Helper shows no hint above Auto setup");
                if (!BlinkActive) f.Add("newplayer: the Auto setup button does not blink");
            }
            return f;
        }

        public bool Pass => Failures().Count == 0;

        static string B(bool v) => v ? "true" : "false";

        public string ToJson(IList<string> secrets)
        {
            var inv = CultureInfo.InvariantCulture;
            if (!Ran) return "{\"ran\":false}";
            var b = new StringBuilder("{\"ran\":true,\"pass\":").Append(B(Pass));
            b.Append(",\"loginOk\":").Append(B(LoginOk)).Append(",\"enterOk\":").Append(B(EnterOk)).Append(",\"error\":").Append(LiveSmokeReport.Quote(Error, secrets));
            b.Append(",\"toastSeen\":").Append(B(ToastSeen)).Append(",\"toastMs\":").Append(Math.Round(ToastMs).ToString("0", inv));
            b.Append(",\"openHelper\":").Append(B(HelperAsked));
            b.Append(",\"helperOpened\":").Append(B(HelperOpened)).Append(",\"helperMs\":").Append(Math.Round(HelperMs).ToString("0", inv));
            b.Append(",\"tab\":").Append(Tab.ToString(inv)).Append(",\"autoSetupTab\":").Append(B(Tab == ShooterTab));
            b.Append(",\"hintShown\":").Append(B(HintShown)).Append(",\"hint\":").Append(LiveSmokeReport.Quote(Hint, secrets));
            b.Append(",\"blinkActive\":").Append(B(BlinkActive)).Append(",\"screenshot\":").Append(LiveSmokeReport.Quote(Screenshot, secrets));
            b.Append(",\"loggedOut\":").Append(B(LoggedOut)).Append('}');
            return b.ToString();
        }
    }

    /// <summary>The state machine of the new player step, after the fresh character is in the game: wait for the welcome toast (the server sends it 2.5 s after the first login),
    /// wait for the Helper to open on its own, let it draw a moment, take the screenshot, done. A timeout does not stop the step: the flags stay false and the screenshot is still
    /// taken, so a failed run shows what the screen had. Time is in ms on the caller's clock; nothing here reads a clock.</summary>
    public sealed class LiveNewPlayerStep
    {
        public const double ToastLimitMs = 30000, HelperLimitMs = 4000, SettleMs = 700;
        public enum Phase { WaitToast, WaitHelper, Settle, Shoot, Done }

        public Phase State { get; private set; } = Phase.WaitToast;
        public readonly LiveNewPlayerResult Result;
        readonly double start;
        double phaseAt;

        public LiveNewPlayerStep(LiveNewPlayerResult result, double nowMs)
        {
            Result = result;
            start = phaseAt = nowMs;
        }

        void Go(Phase p, double now) { State = p; phaseAt = now; }

        /// <summary>One call per frame. `toastNow`: a welcome toast (NEW_PLAYER) is on screen or in the queue this frame; `helperRequests`: ToastCenter.HelperRequests (how many openHelper toasts
        /// came); `view`: the Helper window as it is. Returns Screenshot (the caller takes it and calls ShotTaken) and, at the end, Done.</summary>
        public LiveNewPlayerAction Update(double now, bool toastNow, int helperRequests, LiveHelperView view)
        {
            var r = Result;
            if (State == Phase.Done) return LiveNewPlayerAction.Done;
            if (State != Phase.Shoot)
            {
                if (toastNow && !r.ToastSeen) { r.ToastSeen = true; r.ToastMs = now - start; }
                if (helperRequests > 0) r.HelperAsked = true;
                if (view.Open && !r.HelperOpened) { r.HelperOpened = true; r.HelperMs = now - start; }
            }
            switch (State)
            {
                case Phase.WaitToast:
                    if (r.ToastSeen) Go(Phase.WaitHelper, now);
                    else if (now - start >= ToastLimitMs) Go(Phase.Shoot, now);   // no toast: no Helper to wait for either, the screenshot shows what there is
                    break;
                case Phase.WaitHelper:
                    if (r.HelperOpened) Go(Phase.Settle, now);
                    else if (now - phaseAt >= HelperLimitMs) Go(Phase.Shoot, now);
                    break;
                case Phase.Settle:
                    if (now - phaseAt >= SettleMs) Go(Phase.Shoot, now);
                    break;
            }
            if (State == Phase.Shoot)
            {
                // what the screen shows at the moment of the shot
                r.HelperOpened = r.HelperOpened && view.Open;
                if (r.HelperOpened) { r.Tab = view.Tab; r.HintShown = view.HintDrawn && !string.IsNullOrEmpty(view.Hint); r.Hint = view.Hint ?? ""; r.BlinkActive = view.BlinkActive; }
                return LiveNewPlayerAction.Screenshot;
            }
            return LiveNewPlayerAction.Wait;
        }

        /// <summary>The caller took the screenshot (or tried): the step ends.</summary>
        public void ShotTaken(string name)
        {
            Result.Screenshot = name ?? "";
            State = Phase.Done;
        }
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
        /// <summary>Steps the legs asked for (the tiles round the start that the client calls walkable, out and back).</summary>
        public int StepsPlanned;
        public IList<LiveWalkResult> Legs = new List<LiveWalkResult>();
        public readonly List<LiveSmokeWindow> Windows = new List<LiveSmokeWindow>();
        public readonly List<string> MissingWindows = new List<string>();
        public readonly SortedSet<int> OpcodesSeen = new SortedSet<int>();
        /// <summary>The extended opcodes that came before the first window step (the login requests): what a Prefetch window needs.</summary>
        public readonly SortedSet<int> Prefetched = new SortedSet<int>();
        /// <summary>Windows whose server answer needs something the fresh test character lacks, with what (class name to a short reason). Empty: the first run found none.</summary>
        public readonly Dictionary<string, string> Conditions = new Dictionary<string, string>();
        public readonly SmokeReport Smoke = new SmokeReport();
        /// <summary>The new player first minute (a fresh character logged in before the normal run); not run when the environment has no fresh character.</summary>
        public readonly LiveNewPlayerResult NewPlayer = new LiveNewPlayerResult();
        public int Sheets, Screenshots;

        /// <summary>The walk counts when the legs had a free tile to walk, the server confirmed at least MinSteps (or all there were) and at least half of the planned steps. The legs
        /// only cover tiles the client calls walkable, so a refusal is a finding, but one creature in the way does not fail the run.</summary>
        public bool WalkOk => StepsPlanned > 0 && StepsConfirmed >= Math.Min(MinSteps, StepsPlanned) && StepsConfirmed * 2 >= StepsPlanned;
        public int Exceptions => Smoke.Total(SmokeIssueKind.Exception) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Exception);
        public int LayoutErrors => Smoke.Total(SmokeIssueKind.Layout) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Layout);
        public int LoggedErrors => Smoke.Total(SmokeIssueKind.Error) + Smoke.BackgroundRecord.Count(SmokeIssueKind.Error);

        /// <summary>The one place a window ends. Prefetch windows first (the login request was answered), then the windows that ask nothing (local, whatever lands while they are
        /// open), then an answer while the window was open, then a known condition, and what is left has no answer.</summary>
        public LiveWindowStatus StatusOf(LiveSmokeWindow w)
        {
            var rule = w.Rule;
            if (rule.Mode == LiveWindowMode.Prefetch && Prefetched.Contains(rule.Opcode)) return LiveWindowStatus.Prefetched;
            // a native or local window asks nothing, so an extended opcode that lands while it is open is a background push (runs 3 and 4 of 2026-11-09: Containers, Battle
            // List, Minimap and Fight swapped between answered and local by timing alone); its opcodes stay in the json, its status stays local
            if (rule.Mode == LiveWindowMode.Native || rule.Mode == LiveWindowMode.Local) return LiveWindowStatus.Local;
            if (w.Answers > 0) return LiveWindowStatus.Answered;
            if (Conditions.ContainsKey(w.Class)) return LiveWindowStatus.NeedsCondition;
            return LiveWindowStatus.NoAnswer;
        }

        public static string StatusName(LiveWindowStatus s) =>
            s == LiveWindowStatus.Answered ? "answered" : s == LiveWindowStatus.Prefetched ? "prefetched" : s == LiveWindowStatus.Local ? "local" : s == LiveWindowStatus.NeedsCondition ? "needsCondition" : "noAnswer";

        int Count(LiveWindowStatus status) { int n = 0; foreach (var w in Windows) if (StatusOf(w) == status) n++; return n; }
        public int AnsweredCount => Count(LiveWindowStatus.Answered);
        public int PrefetchedCount => Count(LiveWindowStatus.Prefetched);
        public int LocalCount => Count(LiveWindowStatus.Local);
        public int NeedsConditionCount => Count(LiveWindowStatus.NeedsCondition);
        public int NoAnswerCount => Count(LiveWindowStatus.NoAnswer);
        /// <summary>Every window is in exactly one of the five counts: this is always Windows.Count.</summary>
        public int AccountedCount => AnsweredCount + PrefetchedCount + LocalCount + NeedsConditionCount + NoAnswerCount;

        /// <summary>What fails the run: login, entering, the walk, a closed session, an exception, an abort. A window without an answer is a warning, never a failure.</summary>
        public List<string> Failures()
        {
            var f = new List<string>();
            if (Aborted.Length > 0) f.Add("aborted: " + Aborted);
            if (!LoginOk) f.Add("login failed" + (LoginError.Length > 0 ? ": " + LoginError : ""));
            if (!EnterOk) f.Add("did not enter the game" + (EnterError.Length > 0 ? ": " + EnterError : ""));
            if (LoginOk && EnterOk && !WalkOk)
            {
                if (StepsPlanned == 0) f.Add("walk not tried: no tile round the start is walkable for the client");
                else f.Add("walk failed: " + StepsConfirmed + " of " + StepsPlanned + " planned steps confirmed, at least " + Math.Min(MinSteps, StepsPlanned) + " and half needed");
            }
            foreach (var l in Legs) if (l.Sent > l.Wanted) f.Add("walk plan bug: leg " + l.Name + " sent " + l.Sent + " steps for " + l.Wanted + " planned, the extra tile was never checked");
            if (Closed.Length > 0) f.Add("the session closed: " + Closed);
            if (Exceptions > 0) f.Add(Exceptions + " exceptions logged");
            f.AddRange(NewPlayer.Failures());
            return f;
        }

        public List<string> Warnings()
        {
            var w = new List<string>();
            foreach (var x in Windows)
            {
                if (StatusOf(x) != LiveWindowStatus.NoAnswer) continue;
                var rule = x.Rule;
                if (rule.Mode == LiveWindowMode.Prefetch) w.Add(x.Class + ": opcode " + rule.Opcode + " never came after the login request");
                else w.Add(x.Class + ": no extended answer from the server");
            }
            foreach (var l in Legs) if (l.Cancelled > 0) w.Add("leg " + l.Name + ": " + l.Cancelled + " refused on tiles the client thought walkable");
            foreach (var m in MissingWindows) w.Add(m + ": not a window of this build");
            if (LayoutErrors > 0) w.Add(LayoutErrors + " IMGUI layout errors");
            if (LoggedErrors > 0) w.Add(LoggedErrors + " logged errors");
            if (EnterOk && LoginOk && !LoggedOut) w.Add("no clean logout (the server did not close the connection)");
            if (NewPlayer.Ran && NewPlayer.EnterOk && !NewPlayer.LoggedOut) w.Add("newplayer: no clean logout of the fresh character");
            if (EnterOk && TilesDrawn == 0) w.Add("no tile in the drawn view");
            return w;
        }

        /// <summary>What is not a warning and not a failure but worth a line: a window that needs a condition the test character lacks.</summary>
        public List<string> Notes()
        {
            var n = new List<string>();
            foreach (var x in Windows) if (StatusOf(x) == LiveWindowStatus.NeedsCondition) n.Add(x.Class + ": needs condition: " + Conditions[x.Class]);
            if (StepsCancelled > 0) n.Add("known issue: a held key keeps up to " + WalkTiming.MaxPending + " steps out and a refusal (0xB5) drops every predicted step (Core/SmoothWalk.cs, Core/Game.cs); the legs here stop at the planned steps, so a refusal on a checked tile is the server's or a creature's");
            return n;
        }

        public bool Pass => Failures().Count == 0;

        /// <summary>Planned, sent, confirmed and refused of the walk on one line; sent = confirmed + refused + unanswered, planned >= sent when the plan holds.</summary>
        public string WalkAccounts()
        {
            int unanswered = Math.Max(0, StepsSent - StepsConfirmed - StepsCancelled);
            return "walk: " + StepsPlanned + " planned, " + StepsSent + " sent, " + StepsConfirmed + " confirmed, " + StepsCancelled + " refused, " + unanswered + " unanswered";
        }

        public string SummaryLine() =>
            "chaos live smoke: identity " + Identity + ", login " + (LoginOk ? "ok" : "FAILED") + ", entered " + (EnterOk ? "ok" : "FAILED") + ", walk " + StepsConfirmed + " of " + StepsSent
            + " steps confirmed, " + TilesDrawn + " tiles drawn, " + Windows.Count + " windows (" + AnsweredCount + " answered, " + PrefetchedCount + " prefetched at login, " + LocalCount + " local-only, " + NeedsConditionCount + " need a condition, " + NoAnswerCount + " without an answer), "
            + Exceptions + " exceptions, " + LayoutErrors + " layout errors, " + (NewPlayer.Ran ? "newplayer " + (NewPlayer.Pass ? "ok" : "FAIL") + ", " : "") + (Pass ? "pass" : "FAIL");

        /// <summary>The name of sheet N (0 based) of the contact sheets.</summary>
        public static string SheetName(int sheet) => "live_smoke_sheet_" + (sheet + 1).ToString(CultureInfo.InvariantCulture) + ".png";

        // ------------------------------------------------------------------------------------ json
        /// <summary>A json string with every secret cut out.</summary>
        public static string Quote(string s, IList<string> secrets) => Q(s, secrets);

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
             .Append(",\n \"warnings\":").Append(Strs(Warnings(), secrets)).Append(",\n \"notes\":").Append(Strs(Notes(), secrets));
            b.Append(",\n \"newplayer\":").Append(NewPlayer.ToJson(secrets));
            b.Append(",\n \"login\":{\"ok\":").Append(Bool(LoginOk)).Append(",\"error\":").Append(Q(LoginError, secrets)).Append('}');
            b.Append(",\n \"enter\":{\"ok\":").Append(Bool(EnterOk)).Append(",\"error\":").Append(Q(EnterError, secrets)).Append(",\"ms\":").Append(Math.Round(EnterMs).ToString("0", inv)).Append('}');
            b.Append(",\n \"map\":{\"tilesInModel\":").Append(TilesInModel.ToString(inv)).Append(",\"tilesDrawn\":").Append(TilesDrawn.ToString(inv))
             .Append(",\"tilesDrawnAfterWalk\":").Append(TilesDrawnAfterWalk.ToString(inv)).Append('}');
            b.Append(",\n \"walk\":{\"ok\":").Append(Bool(WalkOk)).Append(",\"planned\":").Append(StepsPlanned.ToString(inv)).Append(",\"sent\":").Append(StepsSent.ToString(inv)).Append(",\"confirmed\":").Append(StepsConfirmed.ToString(inv))
             .Append(",\"cancelled\":").Append(StepsCancelled.ToString(inv)).Append(",\"dx\":").Append(NetDx.ToString(inv)).Append(",\"dy\":").Append(NetDy.ToString(inv)).Append(",\"legs\":[");
            for (int i = 0; i < Legs.Count; i++)
            {
                var l = Legs[i];
                b.Append(i == 0 ? "" : ",").Append("{\"name\":").Append(Q(l.Name, null)).Append(",\"wanted\":").Append(l.Wanted.ToString(inv)).Append(",\"sent\":").Append(l.Sent.ToString(inv)).Append(",\"confirmed\":").Append(l.Confirmed.ToString(inv))
                 .Append(",\"cancelled\":").Append(l.Cancelled.ToString(inv)).Append(",\"timedOut\":").Append(Bool(l.TimedOut)).Append('}');
            }
            b.Append("]}");
            b.Append(",\n \"summary\":{\"windows\":").Append(Windows.Count.ToString(inv)).Append(",\"answered\":").Append(AnsweredCount.ToString(inv)).Append(",\"prefetched\":").Append(PrefetchedCount.ToString(inv)).Append(",\"local\":").Append(LocalCount.ToString(inv))
             .Append(",\"needsCondition\":").Append(NeedsConditionCount.ToString(inv)).Append(",\"noAnswer\":").Append(NoAnswerCount.ToString(inv))
             .Append(",\"exceptions\":").Append(Exceptions.ToString(inv)).Append(",\"layoutErrors\":").Append(LayoutErrors.ToString(inv)).Append(",\"loggedErrors\":").Append(LoggedErrors.ToString(inv))
             .Append(",\"screenshots\":").Append(Screenshots.ToString(inv)).Append(",\"sheets\":").Append(Sheets.ToString(inv)).Append(",\"loggedOut\":").Append(Bool(LoggedOut))
             .Append(",\"finished\":").Append(Bool(Finished)).Append('}');
            b.Append(",\n \"opcodesSeen\":").Append(Ints(OpcodesSeen)).Append(",\n \"opcodesAtLogin\":").Append(Ints(Prefetched)).Append(",\n \"missingWindows\":").Append(Strs(MissingWindows, null)).Append(",\n \"windows\":[");
            for (int i = 0; i < Windows.Count; i++)
            {
                var w = Windows[i];
                b.Append(i == 0 ? "" : ",").Append("\n  {\"name\":").Append(Q(w.Name, null)).Append(",\"status\":").Append(Q(StatusName(StatusOf(w)), null)).Append(",\"native\":").Append(Bool(w.Native)).Append(",\"answers\":").Append(w.Answers.ToString(inv))
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
