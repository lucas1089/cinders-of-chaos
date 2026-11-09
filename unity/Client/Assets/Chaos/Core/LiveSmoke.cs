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

        public static int MaskOf(Dir d) => d == Dir.North ? WalkInput.Up : d == Dir.South ? WalkInput.Down : d == Dir.East ? WalkInput.Right : WalkInput.Left;

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
        /// <summary>The caller's clock (ms) when the window took the welcome toast's request and opened itself; -1 when it has not yet. Open is read by the smoke once a frame, the window
        /// opens in the first OnGUI pass of a frame: a long frame between the two shows as a gap between this and HelperMs (run 42602032582 of 2026-11-09: the request was taken at once
        /// and the smoke saw the window 22 s later, because the main thread had no frame in between).</summary>
        public double TakenMs = -1;
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
        /// <summary>When the Helper window took the request (relative to the step start; -1: not seen), the longest gap between two frames of the step and where it began (ms after the step start). A frame gap
        /// of seconds explains a toast or a Helper that is seen late: it is a main thread stall, not the window.</summary>
        public double HelperTakenMs = -1, LongestFrameMs, LongestFrameAtMs;

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

        /// <summary>A frame of the step that took StallWarnMs or more: the player froze that long (software rendering on a runner, a first-use cost). Not a failure: the Helper and the toast are only seen late by that much.</summary>
        public const double StallWarnMs = 3000;

        public List<string> Warnings()
        {
            var w = new List<string>();
            if (Ran && LongestFrameMs >= StallWarnMs)
                w.Add("newplayer: one frame took " + Math.Round(LongestFrameMs / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s, " + Math.Round(LongestFrameAtMs / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture)
                    + " s after the fresh character entered (a main thread stall: the toast and the Helper window are seen that late, the Helper took its request at " + (HelperTakenMs < 0 ? "no time" : Math.Round(HelperTakenMs / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s") + ")");
            return w;
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
            b.Append(",\"helperTakenMs\":").Append(Math.Round(HelperTakenMs).ToString("0", inv)).Append(",\"longestFrameMs\":").Append(Math.Round(LongestFrameMs).ToString("0", inv)).Append(",\"longestFrameAtMs\":").Append(Math.Round(LongestFrameAtMs).ToString("0", inv));
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
        double phaseAt, lastCall = -1;

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
            // the gap since the last call is the length of the frame in between: a stall of seconds (main thread) is written down, with where it began
            if (lastCall >= 0 && now - lastCall > r.LongestFrameMs) { r.LongestFrameMs = now - lastCall; r.LongestFrameAtMs = lastCall - start; }
            lastCall = now;
            if (State != Phase.Shoot)
            {
                if (view.TakenMs >= 0 && r.HelperTakenMs < 0) r.HelperTakenMs = view.TakenMs - start;
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

    // ============================================================================================================================ the first fight
    // A new player's first fight in the real player (O433, unity/README.md "New player first fight"): after the Helper shot the fresh character presses Auto setup (the window's own
    // code path), turns the Helper on, walks from the temple to the cave under Cinderhold with the client's own click-to-walk (an auto-walk path planned on the tiles the client calls
    // walkable), lets the Helper and the player's attack kill one Rat, opens the body in the container window and takes a picture. Everything that decides is here: the route, the
    // state machine, the pass rules and the json block. The player (Unity/ChaosApp.LiveSmoke.cs) and the live check (Core.LiveCheck, scenario firstfightsmoke) only run the actions.

    /// <summary>A monster in the player's world model, on the player's floor.</summary>
    public sealed class LiveFightMonster
    {
        public uint Id;
        public string Name = "";
        public Pos Pos;
        public int HealthPercent = 100;
    }

    /// <summary>A container item on a map tile (a monster's body or the loot bag): where, its stack position on the tile and its client id.</summary>
    public sealed class LiveFightLoot
    {
        public Pos Tile;
        public int Stack, ItemId;
    }

    /// <summary>An open container of the session (0x6E): its client item id, its name and what it holds.</summary>
    public sealed class LiveFightContainer
    {
        public int Id, ItemId, Items;
        public string Name = "";
    }

    /// <summary>What the player's session shows this frame (built by the caller from the world model, the parser and the windows).</summary>
    public sealed class LiveFightView
    {
        public Pos Player;
        public bool Dead, SpellsLoaded, AutoWalkActive, ContainersWindowOpen;
        public int Health, MaxHealth;
        /// <summary>The player's own moves the server confirmed (Parser.PlayerMoves) and the steps the server refused (0xB5), both counted since the session began.</summary>
        public int Moves, Refused;
        /// <summary>The experience text lines seen ("You gained N experience points.", Parser.ExpGainTexts), how many container windows the server opened (0x6E) and closed (0x6F).</summary>
        public int ExpTexts, ContainerOpens, ContainerCloses;
        /// <summary>The experience of the last 0xA0.</summary>
        public long Experience;
        /// <summary>The client's own walkability check (WalkMap.Walkable): the route is planned on what it calls free.</summary>
        public Func<Pos, bool> Walkable;
        /// <summary>The monsters of the player's floor that have a tile in the world model.</summary>
        public IList<LiveFightMonster> Monsters = new List<LiveFightMonster>();
        /// <summary>The container item on a tile or beside it (the body of a kill), null when there is none.</summary>
        public Func<Pos, LiveFightLoot> LootNear;
        public IList<LiveFightContainer> Containers = new List<LiveFightContainer>();
    }

    /// <summary>What the step asks the caller to do. Answered at once with the matching method of LiveFirstFightStep (AutoSetupDone, HelperSet, WalkStarted, ShotTaken); the others need no answer. Step: one step
    /// of the player's own key path in StepDir (the stair: the client calls its tile not walkable, the click path refuses it, a step onto it works).</summary>
    public enum LiveFightAction { None, PressAutoSetup, HelperOn, Walk, Step, ChaseOn, Attack, UseLoot, OpenContainers, ShowBody, Screenshot, Done }

    /// <summary>The "firstfight" block of live_smoke.json and its failure and warning lines. Ran is false when there was no fresh character (nothing to say). A skip says why and is no failure.</summary>
    public sealed class LiveFirstFightResult
    {
        public bool Ran, Skipped, Died, RatInReach, ReachedCave, AutoSetupPressed, HelperOn, RotationOn, LootOpened, LootWindowOpen, LootTried;
        public int AutoSetupSlots, Hops, Replans, WalkPlanned, WalkSent, WalkConfirmed, WalkRefused, Kills, ExpTexts, LootItems;
        public long ExpBefore, ExpAfter;
        public string SkipReason = "", Error = "", AutoSetupMessage = "", Monster = "", LootName = "", Screenshot = "";
        /// <summary>Why a body did not open, in one line (the uses sent, the 0x6E and 0x6F counts before and after, the open containers); empty when it opened. CI run 42670112065, Chaos: the body never opened with no word why.</summary>
        public string LootDiag = "";
        public double Ms;
        /// <summary>Where the character stood at the end (for the log: "32390,32227,8").</summary>
        public Pos End;
        /// <summary>One short line per hop of the walk (goal, how it ended, refused steps, re-plans): where a refusal happened. At most 24.</summary>
        public readonly List<string> HopLog = new List<string>();

        public List<string> Failures()
        {
            var f = new List<string>();
            if (!Ran) return f;
            if (Error.Length > 0) f.Add("firstfight: " + Error);
            if (Skipped) return f;
            if (Died) f.Add("firstfight: the character died in its first fight");
            if (AutoSetupPressed && AutoSetupSlots == 0) f.Add("firstfight: Auto setup filled no spell slot" + (AutoSetupMessage.Length > 0 ? " (" + AutoSetupMessage + ")" : ""));
            if (AutoSetupPressed && !HelperOn) f.Add("firstfight: the Helper did not turn on");
            if (Kills == 0 && RatInReach && !Died) f.Add("firstfight: no kill in " + (int)(LiveFirstFightStep.LimitMs / 1000) + " s with a " + (Monster.Length > 0 ? Monster : "Rat") + " in reach");
            if (Kills > 0)
            {
                if (ExpTexts == 0) f.Add("firstfight: the kill came with no experience text");
                if (ExpAfter <= ExpBefore) f.Add("firstfight: the kill gave no experience in 0xA0 (" + ExpBefore + " to " + ExpAfter + ")");
            }
            return f;
        }

        public List<string> Warnings()
        {
            var w = new List<string>();
            if (!Ran) return w;
            if (Skipped) w.Add("firstfight: skipped: " + SkipReason);
            if (WalkRefused > 0) w.Add("firstfight walk: " + WalkRefused + " steps refused on tiles the client thought walkable");
            if (!Skipped && Kills > 0 && !LootOpened) w.Add("firstfight: the body did not open in the container window" + (LootTried ? "" : " (no container on the kill's tile)") + (LootDiag.Length > 0 ? " [" + LootDiag + "]" : ""));
            if (LootOpened && !LootWindowOpen) w.Add("firstfight: the Containers window was not open with the body");
            return w;
        }

        public bool Pass => Failures().Count == 0;

        static string B(bool v) => v ? "true" : "false";

        public string ToJson(IList<string> secrets)
        {
            var inv = CultureInfo.InvariantCulture;
            if (!Ran) return "{\"ran\":false}";
            var b = new StringBuilder("{\"ran\":true,\"pass\":").Append(B(Pass)).Append(",\"skipped\":").Append(B(Skipped)).Append(",\"skipReason\":").Append(LiveSmokeReport.Quote(SkipReason, secrets));
            b.Append(",\"error\":").Append(LiveSmokeReport.Quote(Error, secrets));
            b.Append(",\"autoSetup\":{\"pressed\":").Append(B(AutoSetupPressed)).Append(",\"slots\":").Append(AutoSetupSlots.ToString(inv)).Append(",\"message\":").Append(LiveSmokeReport.Quote(AutoSetupMessage, secrets)).Append('}');
            b.Append(",\"helperOn\":").Append(B(HelperOn)).Append(",\"rotationOn\":").Append(B(RotationOn));
            b.Append(",\"walk\":{\"hops\":").Append(Hops.ToString(inv)).Append(",\"replans\":").Append(Replans.ToString(inv)).Append(",\"planned\":").Append(WalkPlanned.ToString(inv)).Append(",\"sent\":").Append(WalkSent.ToString(inv))
             .Append(",\"confirmed\":").Append(WalkConfirmed.ToString(inv)).Append(",\"refused\":").Append(WalkRefused.ToString(inv)).Append(",\"reachedCave\":").Append(B(ReachedCave)).Append('}');
            b.Append(",\"monster\":").Append(LiveSmokeReport.Quote(Monster, secrets)).Append(",\"ratInReach\":").Append(B(RatInReach)).Append(",\"kills\":").Append(Kills.ToString(inv)).Append(",\"died\":").Append(B(Died));
            b.Append(",\"experience\":{\"before\":").Append(ExpBefore.ToString(inv)).Append(",\"after\":").Append(ExpAfter.ToString(inv)).Append(",\"texts\":").Append(ExpTexts.ToString(inv)).Append('}');
            b.Append(",\"loot\":{\"opened\":").Append(B(LootOpened)).Append(",\"name\":").Append(LiveSmokeReport.Quote(LootName, secrets)).Append(",\"items\":").Append(LootItems.ToString(inv)).Append(",\"windowOpen\":").Append(B(LootWindowOpen)).Append(",\"diag\":").Append(LiveSmokeReport.Quote(LootDiag, secrets)).Append('}');
            b.Append(",\"screenshot\":").Append(LiveSmokeReport.Quote(Screenshot, secrets)).Append(",\"ms\":").Append(Math.Round(Ms).ToString("0", inv));
            b.Append(",\"end\":").Append(LiveSmokeReport.Quote(End.ToString(), secrets)).Append(",\"hopLog\":[");
            for (int i = 0; i < HopLog.Count; i++) b.Append(i == 0 ? "" : ",").Append(LiveSmokeReport.Quote(HopLog[i], secrets));
            b.Append("]}");
            return b.ToString();
        }
    }

    /// <summary>The state machine of the first fight. One Update per frame with the clock (ms) and the view; it returns the action to run (None most frames). Order: wait for the spell
    /// list, Auto setup, Helper on (and the spell rotation), the walk (hops: the waypoints of the way from the temple to the stair at 32390,32225,7, each an auto-walk planned on the
    /// tiles the client calls walkable, re-planned when a hop ends short), the Rats of the cave (the known grounds are visited when none is in view), the fight (chase on, an attack order
    /// repeated every 2.5 s, the Helper casting), the kill (the creature gone, the experience text, the experience of 0xA0), the body (walk beside it, use it, the container opens in the
    /// container window), a picture. Time limit LimitMs from the start: with a Rat in reach and no kill it fails, with no Rat in view it skips with the reason.</summary>
    public sealed class LiveFirstFightStep
    {
        public const double LimitMs = 120000, HopLimitMs = 25000, SpellsWaitMs = 10000, NoRatWaitMs = 8000, GroundWaitMs = 1500, AttackEveryMs = 2500, GoneWaitMs = 2500, KillSettleMs = 600,
            CorpseWaitMs = 2500, LootWaitMs = 4000, LootGraceMs = 15000, WindowWaitMs = 600, SettleMs = 700, RetryGapMs = 300, StepWaitMs = 1500;
        public const int HopAttempts = 4, LootTries = 2, StepAttempts = 3;

        /// <summary>Cinderhold's temple spot (where a new character stands) and the stair down to the cave of the first hunt (the stairs the street passes lead to closed basements).</summary>
        public static readonly Pos TempleSpot = new Pos(32369, 32241, 7), Stair = new Pos(32390, 32225, 7);
        /// <summary>The way from the temple to the stair (server map, floor 7: out of the hall by the west side of the north door, round the house to its east side). Every hop is short and in view (Core.LiveCheck DescentRoute).</summary>
        public static readonly Pos[] Route = { new Pos(32366, 32235, 7), new Pos(32366, 32229, 7), new Pos(32368, 32223, 7), new Pos(32374, 32217, 7), new Pos(32380, 32213, 7), new Pos(32384, 32219, 7), new Pos(32387, 32225, 7) };
        /// <summary>Where the Rats of the cave live (server spawn file, floor 8): visited when none is in view at the landing.</summary>
        public static readonly Pos[] Grounds = { new Pos(32385, 32217, 8), new Pos(32390, 32217, 8), new Pos(32394, 32217, 8), new Pos(32362, 32214, 8), new Pos(32352, 32214, 8), new Pos(32368, 32203, 8) };

        public enum Phase { Spells, AutoSetup, HelperOn, Walk, Hunt, Fight, Settle, Loot, Shoot, Done }
        enum Purpose { Route, Grounds, Body }
        enum LootState { Find, Beside, Use, Wait, Window }

        sealed class Hop { public Pos Goal; public int Range; public bool Floor, Stepping; }

        public Phase State { get; private set; } = Phase.Spells;
        public readonly LiveFirstFightResult Result;
        /// <summary>The parameters of the action just returned.</summary>
        public Pos WalkGoal;
        public int WalkRange;
        public Dir StepDir;
        public uint AttackId;
        public LiveFightLoot Loot;

        readonly double start;
        double phaseAt, killAt = -1, lastAttack = -1, hopAt, retryAt, shotAt = -1, goneAt = -1, lootAt, lastNow;
        readonly Queue<Hop> hops = new Queue<Hop>();
        Hop hop;
        Purpose purpose = Purpose.Route;
        LootState lootState = LootState.Find;
        int attempts, moves0, refused0, groundIndex, texts0 = -1, opens0, closes0, lootTries, hopRefused, hopReplans;
        string snap0 = "";
        double hopStart;
        bool hopAsked, hopRunning, setupAsked, helperAsked, planned, chased, windowAsked, stepAsked;
        double stepAt;
        string hopNote = "";
        uint target;
        readonly Dictionary<uint, Pos> seen = new Dictionary<uint, Pos>();
        Pos killPos;

        public LiveFirstFightStep(LiveFirstFightResult result, double nowMs)
        {
            Result = result;
            result.Ran = true;
            start = phaseAt = nowMs;
        }

        void Go(Phase p, double now) { State = p; phaseAt = now; }

        /// <summary>A Rat or a Cave Rat (the server adds a level tag: "Rat [4]").</summary>
        public static bool IsRat(string name)
        {
            string b = BaseName(name);
            return string.Equals(b, "Rat", StringComparison.OrdinalIgnoreCase) || string.Equals(b, "Cave Rat", StringComparison.OrdinalIgnoreCase);
        }

        public static string BaseName(string n)
        {
            n = n ?? "";
            int b = n.LastIndexOf(" [", StringComparison.Ordinal);
            return b > 0 && n.EndsWith("]", StringComparison.Ordinal) ? n.Substring(0, b) : n;
        }

        /// <summary>The container item on the tile of a kill, else on a tile beside it (the kill's own tile first, then the ring round it; the top of a stack first): the monster's body, or the
        /// loot bag on an engine that has it. A body of an earlier fight next to it is not taken for this one.</summary>
        public static LiveFightLoot LootOn(World w, Pos at)
        {
            for (int ring = 0; ring <= 1; ring++)
                for (int dx = -ring; dx <= ring; dx++)
                    for (int dy = -ring; dy <= ring; dy++)
                    {
                        if (Math.Max(Math.Abs(dx), Math.Abs(dy)) != ring) continue;
                        var tp = at.Offset(dx, dy);
                        var t = w.Get(tp);
                        if (t == null) continue;
                        for (int i = t.Things.Count - 1; i >= 0; i--)
                        {
                            var th = t.Things[i];
                            if (th.IsCreature || th.Item == null || th.Item.Type == null || !th.Item.Type.Container) continue;
                            return new LiveFightLoot { Tile = tp, Stack = i, ItemId = th.Item.Id };
                        }
                    }
            return null;
        }

        // ------------------------------------------------------------------------------------ the caller's answers
        public void AutoSetupDone(int slots, string message)
        {
            Result.AutoSetupPressed = true;
            Result.AutoSetupSlots = slots;
            Result.AutoSetupMessage = message ?? "";
        }

        public void HelperSet(bool on, bool rotation)
        {
            Result.HelperOn = on;
            Result.RotationOn = rotation;
        }

        /// <summary>The auto-walk was planned and its packet sent: its length in steps; 0 when the character is there already; -1 when there is no way over the tiles the client knows.</summary>
        public void WalkStarted(int steps)
        {
            if (steps < 0) { hopRunning = false; hopNote = "no way over the tiles in view"; return; }
            hopRunning = steps > 0;
            Result.WalkSent += steps;
            if (attempts == 0) Result.WalkPlanned += steps;
            hopAt = lastNow;
        }

        public void ShotTaken(string name)
        {
            Result.Screenshot = name ?? "";
            State = Phase.Done;
        }

        // ------------------------------------------------------------------------------------ the end states
        void Skip(string why, double now)
        {
            if (!Result.Skipped && Result.Kills == 0) { Result.Skipped = true; Result.SkipReason = why; }
            Go(Phase.Shoot, now);
        }

        /// <summary>One call per frame. Returns the action to run; the parameters are WalkGoal / WalkRange, AttackId and Loot.</summary>
        public LiveFightAction Update(double now, LiveFightView v)
        {
            lastNow = now;
            var r = Result;
            if (State == Phase.Done) return LiveFightAction.Done;
            r.Ms = now - start;
            r.End = v.Player;
            // the Rats' last tiles: a kill's tile is where the Rat was seen last
            foreach (var m in v.Monsters) if (IsRat(m.Name)) seen[m.Id] = m.Pos;
            if (v.Dead && State != Phase.Shoot) { r.Died = true; Go(Phase.Shoot, now); }
            if (r.Kills == 0 && State != Phase.Shoot && State != Phase.Settle && State != Phase.Loot && now - start >= LimitMs) TimeUp(v, now);
            // a walk to the body that does not end: the body's own time is up
            if (r.Kills > 0 && State == Phase.Walk && now > Math.Max(start + LimitMs, killAt + LootGraceMs)) Go(Phase.Shoot, now);
            switch (State)
            {
                case Phase.Spells:
                    if (!v.SpellsLoaded)
                    {
                        if (now - phaseAt >= SpellsWaitMs) { r.Error = "the spell list never arrived, so Auto setup had nothing to set up"; Go(Phase.Shoot, now); }
                        return LiveFightAction.None;
                    }
                    if (!setupAsked) { setupAsked = true; return LiveFightAction.PressAutoSetup; }
                    if (!helperAsked) { helperAsked = true; return LiveFightAction.HelperOn; }
                    if (!planned) { planned = true; PlanRoute(v, now); }   // the walk starts on the next frame (or the part ends: not at the temple)
                    return LiveFightAction.None;
                case Phase.Walk: return Walk(v, now, Phase.Walk);
                case Phase.Hunt: return Hunt(v, now);
                case Phase.Fight: return Fight(v, now);
                case Phase.Settle:
                    if (now - killAt < KillSettleMs) return LiveFightAction.None;
                    r.ExpAfter = v.Experience;
                    r.ExpTexts = Math.Max(0, v.ExpTexts - Math.Max(0, texts0));
                    r.Kills = 1;
                    lootAt = now; lootState = LootState.Find;
                    Go(Phase.Loot, now);
                    return LiveFightAction.None;
                case Phase.Loot: return LootStep(v, now);
                case Phase.Shoot:
                    // the picture shows the open body: the Helper window (on the same side of the screen) is put away and the container window comes to the front, once
                    if (shotAt < 0) { shotAt = now; return r.LootOpened ? LiveFightAction.ShowBody : LiveFightAction.None; }
                    // a moment for the frames to draw what is there (the open body, the fight), then the picture
                    if (now - shotAt < SettleMs) return LiveFightAction.None;
                    return LiveFightAction.Screenshot;
            }
            return LiveFightAction.None;
        }

        void TimeUp(LiveFightView v, double now)
        {
            if (!Result.ReachedCave) Skip("the cave was not reached in " + (int)(LimitMs / 1000) + " s" + (hopNote.Length > 0 ? " (" + hopNote + ")" : "") + ", the character is at " + v.Player, now);
            else if (!Result.RatInReach) Skip("no Rat came into view in " + (int)(LimitMs / 1000) + " s, the character is at " + v.Player, now);
            else Go(Phase.Shoot, now);   // a Rat was in reach and nothing died: Failures() says so
        }

        // ------------------------------------------------------------------------------------ the walk
        void PlanRoute(LiveFightView v, double now)
        {
            if (v.Player.Z != Stair.Z || PathFinder.Cheb(v.Player, TempleSpot) > 14)
            {
                Skip("the character is not at the temple of Cinderhold (at " + v.Player + ")", now);
                return;
            }
            purpose = Purpose.Route;
            foreach (var w in Route) hops.Enqueue(new Hop { Goal = w, Range = 1 });
            hops.Enqueue(new Hop { Goal = Stair, Range = 0, Floor = true });
            Go(Phase.Walk, now);
        }

        /// <summary>The tile beside the stair the character walks to before it steps onto the stair: a walkable tile next to it in the four directions with a way from the character, the nearest.
        /// Null when the stair is not in view (further than 7 tiles, or no such tile with a way).</summary>
        static bool BesideStair(LiveFightView v, out Pos beside)
        {
            beside = default(Pos);
            if (v.Walkable == null || v.Player.Z != Stair.Z || PathFinder.Cheb(v.Player, Stair) > 7) return false;
            int best = int.MaxValue;
            foreach (var d in new[] { Dir.North, Dir.South, Dir.East, Dir.West })
            {
                var q = WalkDirs.Step(Stair, d);
                if (!v.Walkable(q)) continue;
                var way = q.Equals(v.Player) ? new List<Dir>() : PathFinder.Find(v.Player, q, v.Walkable, 0);
                if (way == null || way.Count >= best) continue;
                best = way.Count; beside = q;
            }
            return best != int.MaxValue;
        }

        /// <summary>The next hop of the queue; on the route the stair itself instead as soon as it shows and a way to the tile beside it is known (the way a player takes a stair that is in view).
        /// The stair hop walks to that tile and then steps onto the stair with the key path.</summary>
        bool NextHop(LiveFightView v)
        {
            if (hops.Count == 0) return false;
            hop = hops.Dequeue();
            if (purpose == Purpose.Route && !hop.Floor && BesideStair(v, out Pos early))
            {
                hops.Clear();
                hop = new Hop { Goal = early, Range = 0, Floor = true };
            }
            else if (hop.Floor)
            {
                if (BesideStair(v, out Pos beside)) hop.Goal = beside;
                else { hop.Goal = Stair; hop.Range = 1; }
            }
            attempts = 0; hopAsked = false; hopRunning = false; hopNote = ""; stepAsked = false;
            Result.Hops++;
            moves0 = v.Moves; refused0 = v.Refused;
            hopRefused = 0; hopReplans = 0; hopStart = lastNow;
            return true;
        }

        void LogHop(LiveFightView v, string how)
        {
            if (hop == null || Result.HopLog.Count >= 24) return;
            Result.HopLog.Add((purpose == Purpose.Route ? "route " : purpose == Purpose.Grounds ? "grounds " : "body ") + Result.Hops + " to " + hop.Goal + (hop.Floor ? " (stair)" : "") + ": " + how + " at " + v.Player + ", "
                + Math.Round((lastNow - hopStart) / 1000.0, 1).ToString("0.0", CultureInfo.InvariantCulture) + " s, " + hopRefused + " refused, " + hopReplans + " re-plan(s)");
        }

        static bool Beside(Pos p) => Math.Abs(p.X - Stair.X) + Math.Abs(p.Y - Stair.Y) == 1 && p.Z == Stair.Z;

        static bool Arrived(Hop h, LiveFightView v)
        {
            if (h.Floor && h.Stepping) return v.Player.Z != Stair.Z;
            if (h.Floor && h.Range == 0 && v.Player.Z != Stair.Z) return true;   // some other way down
            if (v.Player.Z != h.Goal.Z) return false;
            return h.Range > 0 ? PathFinder.Cheb(v.Player, h.Goal) <= h.Range : v.Player.Equals(h.Goal);
        }

        static Dir DirTo(Pos from, Pos to)
        {
            int dx = Math.Sign(to.X - from.X), dy = Math.Sign(to.Y - from.Y);
            if (dx == 0) return dy < 0 ? Dir.North : Dir.South;
            if (dy == 0) return dx > 0 ? Dir.East : Dir.West;
            return dx > 0 ? (dy < 0 ? Dir.NorthEast : Dir.SouthEast) : (dy < 0 ? Dir.NorthWest : Dir.SouthWest);
        }

        void CountWalk(LiveFightView v)
        {
            Result.WalkConfirmed += v.Moves - moves0; moves0 = v.Moves;
            int refused = v.Refused - refused0;
            Result.WalkRefused += refused; hopRefused += refused; refused0 = v.Refused;
        }

        LiveFightAction Walk(LiveFightView v, double now, Phase self)
        {
            var r = Result;
            if (State != self) Go(self, now);
            for (; ; )
            {
                if (hop == null)
                {
                    if (!NextHop(v)) { WalkEnded(v, now, true, ""); return LiveFightAction.None; }
                }
                if (hop.Stepping)
                {
                    // the last step of the stair hop: one step of the key path onto the stair, again when the floor did not change
                    if (v.Player.Z != Stair.Z) { CountWalk(v); LogHop(v, "arrived"); hop = null; continue; }
                    if (!stepAsked)
                    {
                        if (!Beside(v.Player)) { hop.Stepping = false; hopAsked = false; hopRunning = false; continue; }   // pushed away: back to walking
                        stepAsked = true; stepAt = now;
                        StepDir = DirTo(v.Player, Stair);
                        r.WalkSent++;
                        return LiveFightAction.Step;
                    }
                    if (now - stepAt < StepWaitMs) return LiveFightAction.None;
                    CountWalk(v);
                    stepAsked = false;
                    if (++attempts >= StepAttempts)
                    {
                        string why = "stepping " + StepDir + " onto the stair at " + Stair + " did not change the floor (the character at " + v.Player + ")";
                        LogHop(v, "failed");
                        hop = null; hops.Clear();
                        WalkEnded(v, now, false, why);
                        return LiveFightAction.None;
                    }
                    r.Replans++; hopReplans++;
                    return LiveFightAction.None;
                }
                if (!hopAsked)
                {
                    if (now < retryAt) return LiveFightAction.None;
                    hopAsked = true; hopRunning = false;
                    WalkGoal = hop.Goal;
                    WalkRange = hop.Range + Math.Max(0, attempts - 1);   // a hop that found no way relaxes its range a tile per try
                    return LiveFightAction.Walk;
                }
                if (hopRunning && v.AutoWalkActive && now - hopAt < HopLimitMs) return LiveFightAction.None;
                // the walk is over, or never began: counted, and by position did it get there?
                CountWalk(v);
                if (Arrived(hop, v))
                {
                    if (hop.Floor && v.Player.Z == Stair.Z && Beside(v.Player)) { hop.Stepping = true; attempts = 0; stepAsked = false; continue; }
                    LogHop(v, "arrived");
                    hop = null;
                    continue;
                }
                if (hop.Floor && Beside(v.Player)) { hop.Stepping = true; attempts = 0; stepAsked = false; continue; }   // beside the stair, wherever the walk ended
                attempts++;
                if (attempts >= HopAttempts)
                {
                    string why = "no way to " + hop.Goal + " from " + v.Player + " after " + HopAttempts + " tries" + (hopNote.Length > 0 ? ": " + hopNote : "");
                    LogHop(v, "failed");
                    hop = null;
                    hops.Clear();
                    WalkEnded(v, now, false, why);
                    return LiveFightAction.None;
                }
                if (hopRunning) { r.Replans++; hopReplans++; }
                hopAsked = false; hopRunning = false;
                retryAt = now + RetryGapMs;
                return LiveFightAction.None;
            }
        }

        void WalkEnded(LiveFightView v, double now, bool ok, string why)
        {
            if (why.Length > 0) hopNote = why;
            switch (purpose)
            {
                case Purpose.Route:
                    if (!ok) { Skip("the way to the cave failed: " + why, now); return; }
                    Result.ReachedCave = v.Player.Z != Stair.Z;
                    Go(Phase.Hunt, now);
                    return;
                case Purpose.Grounds:
                    Go(Phase.Hunt, now);   // arrived, or this ground has no way: Hunt looks for a Rat and goes on to the next ground
                    return;
                default:
                    lootState = LootState.Use;
                    Go(Phase.Loot, now);
                    return;
            }
        }

        // ------------------------------------------------------------------------------------ the Rats
        LiveFightMonster NearestRat(LiveFightView v)
        {
            LiveFightMonster best = null;
            int bd = int.MaxValue;
            foreach (var m in v.Monsters)
            {
                if (!IsRat(m.Name) || m.HealthPercent <= 0 || m.Pos.Z != v.Player.Z) continue;
                int d = PathFinder.Cheb(m.Pos, v.Player);
                if (d > 9 || d > bd || (d == bd && best != null && m.Id > best.Id)) continue;
                if (d > 1 && (v.Walkable == null || PathFinder.Find(v.Player, m.Pos, v.Walkable, 1) == null)) continue;
                bd = d; best = m;
            }
            return best;
        }

        LiveFightAction Hunt(LiveFightView v, double now)
        {
            var r = Result;
            var rat = NearestRat(v);
            if (rat != null)
            {
                r.RatInReach = true;
                r.Monster = LiveFirstFightStep.BaseName(rat.Name);
                target = rat.Id;
                if (texts0 < 0) { texts0 = v.ExpTexts; r.ExpBefore = v.Experience; }
                lastAttack = -1; goneAt = -1;
                Go(Phase.Fight, now);
                return Fight(v, now);
            }
            if (now - phaseAt < (groundIndex == 0 ? NoRatWaitMs : GroundWaitMs)) return LiveFightAction.None;   // the landing fills, a Rat wanders in
            while (groundIndex < Grounds.Length)
            {
                var g = Grounds[groundIndex++];
                if (g.Z != v.Player.Z) continue;
                purpose = Purpose.Grounds;
                hops.Enqueue(new Hop { Goal = g, Range = 3 });
                return Walk(v, now, Phase.Walk);
            }
            Skip("no Rat in view at the landing or on the known grounds, the character is at " + v.Player, now);
            return LiveFightAction.None;
        }

        LiveFightAction Fight(LiveFightView v, double now)
        {
            var r = Result;
            if (!chased) { chased = true; return LiveFightAction.ChaseOn; }
            bool there = false;
            foreach (var m in v.Monsters) if (m.Id == target) { there = true; break; }
            // the kill: the experience text came and a Rat left the map (the one hit, or one the Helper took)
            uint goneId = there ? 0u : target;
            if (there && v.ExpTexts > texts0)
                foreach (var id in seen.Keys)
                {
                    bool inView = false;
                    foreach (var m in v.Monsters) if (m.Id == id) { inView = true; break; }
                    if (!inView) { goneId = id; break; }
                }
            if (v.ExpTexts > texts0 && goneId != 0)
            {
                killPos = seen[goneId]; killAt = now;
                Go(Phase.Settle, now);
                return LiveFightAction.None;
            }
            if (!there)
            {
                // gone and no experience text yet: a moment for it, then another Rat
                if (goneAt < 0) goneAt = now;
                else if (now - goneAt >= GoneWaitMs) { seen.Remove(target); goneAt = -1; Go(Phase.Hunt, now); }
                return LiveFightAction.None;
            }
            goneAt = -1;
            if (lastAttack < 0 || now - lastAttack >= AttackEveryMs)
            {
                lastAttack = now;
                AttackId = target;
                return LiveFightAction.Attack;
            }
            return LiveFightAction.None;
        }

        // ------------------------------------------------------------------------------------ the body
        /// <summary>The open container that is the body (its item id), null when none.</summary>
        LiveFightContainer BodyOpen(LiveFightView v)
        {
            if (Loot == null) return null;
            foreach (var x in v.Containers) if (x.ItemId == Loot.ItemId) return x;
            return null;
        }

        /// <summary>The open containers as "id:item" pairs: a change says a window opened, was replaced or closed.</summary>
        static string Snap(LiveFightView v)
        {
            var sb = new StringBuilder();
            foreach (var x in v.Containers) { if (sb.Length > 0) sb.Append(' '); sb.Append(x.Id).Append(':').Append(x.ItemId); }
            return sb.ToString();
        }

        LiveFightAction LootStep(LiveFightView v, double now)
        {
            var r = Result;
            if (now > Math.Max(start + LimitMs, killAt + LootGraceMs)) { Go(Phase.Shoot, now); return LiveFightAction.None; }
            switch (lootState)
            {
                case LootState.Find:
                    {
                        var l = v.LootNear != null ? v.LootNear(killPos) : null;
                        if (l == null)
                        {
                            if (now - lootAt >= CorpseWaitMs) Go(Phase.Shoot, now);   // no body on the tile: the warning says so
                            return LiveFightAction.None;
                        }
                        Loot = l;
                        if (PathFinder.Cheb(v.Player, l.Tile) > 1)
                        {
                            purpose = Purpose.Body;
                            hops.Enqueue(new Hop { Goal = l.Tile, Range = 1 });
                            lootState = LootState.Beside;
                            return Walk(v, now, Phase.Walk);
                        }
                        lootState = LootState.Use;
                        return LootStep(v, now);
                    }
                case LootState.Use:
                    {
                        var l = v.LootNear != null ? v.LootNear(killPos) : null;
                        if (l != null) Loot = l;
                        if (Loot == null) { Go(Phase.Shoot, now); return LiveFightAction.None; }
                        r.LootTried = true;
                        // a body that is open already (the server opened it, or an earlier use did and the count was missed): a use now would close it again
                        var already = BodyOpen(v);
                        if (already != null)
                        {
                            r.LootOpened = true; r.LootName = already.Name; r.LootItems = already.Items;
                            lootState = LootState.Window; lootAt = now;
                            return LootStep(v, now);
                        }
                        lootTries++;
                        opens0 = v.ContainerOpens;
                        closes0 = v.ContainerCloses;
                        snap0 = Snap(v);
                        lootAt = now;
                        lootState = LootState.Wait;
                        return LiveFightAction.UseLoot;
                    }
                case LootState.Wait:
                    // the count of 0x6E, or the open containers changed to hold the body (the server answers an open of a body with the id of the open backpack again)
                    if (v.ContainerOpens > opens0 || (Snap(v) != snap0 && BodyOpen(v) != null))
                    {
                        LiveFightContainer c = null;
                        foreach (var x in v.Containers) if (x.ItemId == Loot.ItemId) c = x;
                        if (c == null && v.Containers.Count > 0) c = v.Containers[v.Containers.Count - 1];
                        if (c != null)
                        {
                            r.LootOpened = true; r.LootName = c.Name; r.LootItems = c.Items;
                            lootState = LootState.Window; lootAt = now;
                            return LootStep(v, now);
                        }
                    }
                    if (now - lootAt >= LootWaitMs)
                    {
                        r.LootDiag = "use " + lootTries + " of " + LootTries + ": 0x6E " + opens0 + " to " + v.ContainerOpens + ", 0x6F " + closes0 + " to " + v.ContainerCloses + ", open [" + Snap(v) + "], body item " + (Loot != null ? Loot.ItemId : 0);
                        if (lootTries < LootTries) lootState = LootState.Find;   // the body moved or a creature stood on it: look again
                        else Go(Phase.Shoot, now);
                        lootAt = now;
                    }
                    return LiveFightAction.None;
                default:   // Window: the container window shows the open body
                    if (!v.ContainersWindowOpen && !windowAsked) { windowAsked = true; return LiveFightAction.OpenContainers; }
                    r.LootWindowOpen = v.ContainersWindowOpen;
                    if (v.ContainersWindowOpen || now - lootAt >= WindowWaitMs) Go(Phase.Shoot, now);
                    return LiveFightAction.None;
            }
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
        /// <summary>The fresh character's first fight after the Helper shot (Auto setup, Helper on, the walk to the cave, one Rat killed, its body opened); not run without the fresh character.</summary>
        public readonly LiveFirstFightResult FirstFight = new LiveFirstFightResult();
        public int Sheets, Screenshots;
        /// <summary>Calls of the player that took 500 ms or more and frame gaps of 500 ms or more (Core/SlowCalls.cs), the run's own record; empty when nothing was slow.</summary>
        public readonly List<SlowCall> Slow = new List<SlowCall>();
        public readonly List<StallRecord> Stalls = new List<StallRecord>();

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
            f.AddRange(FirstFight.Failures());
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
            w.AddRange(NewPlayer.Warnings());
            // after a fight the server refuses a logout for about a minute (the in-fight condition), so the app drops the connection: expected, a note
            if (NewPlayer.Ran && NewPlayer.EnterOk && !NewPlayer.LoggedOut && !FirstFight.RatInReach) w.Add("newplayer: no clean logout of the fresh character");
            w.AddRange(FirstFight.Warnings());
            if (EnterOk && TilesDrawn == 0) w.Add("no tile in the drawn view");
            return w;
        }

        /// <summary>What is not a warning and not a failure but worth a line: a window that needs a condition the test character lacks.</summary>
        public List<string> Notes()
        {
            var n = new List<string>();
            foreach (var x in Windows) if (StatusOf(x) == LiveWindowStatus.NeedsCondition) n.Add(x.Class + ": needs condition: " + Conditions[x.Class]);
            if (NewPlayer.Ran && NewPlayer.EnterOk && !NewPlayer.LoggedOut && FirstFight.RatInReach) n.Add("newplayer: the fresh character fought, the server refuses a logout in the minute after a fight, so the app closed the connection");
            if (Slow.Count > 0) n.Add("slow calls (own time): " + SlowCallLog.Summary(Slow, 3));
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
            + Exceptions + " exceptions, " + LayoutErrors + " layout errors, " + (NewPlayer.Ran ? "newplayer " + (NewPlayer.Pass ? "ok" : "FAIL") + ", " : "")
            + (FirstFight.Ran ? "firstfight " + (FirstFight.Skipped ? "skipped" : FirstFight.Pass ? "ok" : "FAIL") + ", " : "") + (Pass ? "pass" : "FAIL");

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

        string SlowCallsJson(IList<string> secrets)
        {
            var inv = CultureInfo.InvariantCulture;
            var b = new StringBuilder("[");
            for (int i = 0; i < Slow.Count; i++)
            {
                var c = Slow[i];
                b.Append(i == 0 ? "" : ",").Append("{\"name\":").Append(Q(c.Name, secrets)).Append(",\"phase\":").Append(Q(c.Phase, secrets)).Append(",\"ms\":").Append(Math.Round(c.Ms).ToString("0", inv))
                 .Append(",\"selfMs\":").Append(Math.Round(c.SelfMs).ToString("0", inv)).Append(",\"at\":").Append(Math.Round(c.AtMs).ToString("0", inv)).Append(",\"who\":").Append(Q(c.Who, secrets)).Append('}');
            }
            return b.Append(']').ToString();
        }

        string StallsJson(IList<string> secrets)
        {
            var inv = CultureInfo.InvariantCulture;
            var b = new StringBuilder("[");
            for (int i = 0; i < Stalls.Count; i++)
            {
                var s = Stalls[i];
                b.Append(i == 0 ? "" : ",").Append("{\"ms\":").Append(Math.Round(s.Ms).ToString("0", inv)).Append(",\"at\":").Append(Math.Round(s.AtMs).ToString("0", inv)).Append(",\"who\":").Append(Q(s.Who, secrets))
                 .Append(",\"lastEnded\":").Append(Q(s.LastEnded, secrets)).Append(",\"seen\":").Append(Strs(s.Seen, secrets)).Append('}');
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
            b.Append(",\n \"firstfight\":").Append(FirstFight.ToJson(secrets));
            b.Append(",\n \"slowCalls\":").Append(SlowCallsJson(secrets)).Append(",\n \"stalls\":").Append(StallsJson(secrets));
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
