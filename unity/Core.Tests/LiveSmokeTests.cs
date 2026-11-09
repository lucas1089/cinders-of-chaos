// The player on a live server (Core/LiveSmoke.cs, Unity/ChaosApp.LiveSmoke.cs, unity/README.md "Player on a live server (CI)"): the environment, the window list, when a
// step is done, the walk legs against a simulated server, the tiles counted, the report json (secrets cut) and the pass rule. No Unity, no server.
using System;
using System.Collections.Generic;
using System.Linq;

namespace Chaos.Core.Tests
{
    static class LiveSmokeTests
    {
        public static void Run(Action<bool, string> check)
        {
            EnvChecks(check);
            PlanChecks(check);
            WalkChecks(check);
            TileChecks(check);
            ReportChecks(check);
        }

        static Func<string, string> Env(params string[] kv)
        {
            var d = new Dictionary<string, string>();
            for (int i = 0; i + 1 < kv.Length; i += 2) d[kv[i]] = kv[i + 1];
            return k => d.TryGetValue(k, out var v) ? v : null;
        }

        static void EnvChecks(Action<bool, string> check)
        {
            var e = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "lcp1abc", "CHAOS_LIVE_PASSWORD", "s3cret pass"));
            check(e.Ok && e.Host == "127.0.0.1" && e.Port == 7171 && e.Identity == "extended" && e.Character == null && e.Password == "s3cret pass", "live smoke env: defaults (host, port 7171, extended, first character), the password is kept as it is");
            e = LiveSmokeEnv.Read(Env("CHAOS_LIVE_HOST", "10.0.0.5", "CHAOS_LIVE_PORT", "27171", "CHAOS_LIVE_ACCOUNT", " acc ", "CHAOS_LIVE_PASSWORD", "pw", "CHAOS_LIVE_CHARACTER", "Live Aldric A", "CHAOS_LIVE_IDENTITY", "Chaos"));
            check(e.Ok && e.Host == "10.0.0.5" && e.Port == 27171 && e.Account == "acc" && e.Character == "Live Aldric A" && e.Identity == "chaos", "live smoke env: every variable read, the identity in any case");
            check(!LiveSmokeEnv.Read(Env()).Ok && LiveSmokeEnv.Read(Env()).Errors.Count == 2, "live smoke env: no account and no password are two errors");
            check(!LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p", "CHAOS_LIVE_PORT", "0")).Ok, "live smoke env: port 0 refused");
            check(!LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p", "CHAOS_LIVE_PORT", "12x")).Ok, "live smoke env: a port that is not a number refused");
            check(!LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p", "CHAOS_LIVE_IDENTITY", "other")).Ok, "live smoke env: an unknown identity refused");
            var bad = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "acc-name", "CHAOS_LIVE_PASSWORD", "hunter2hunter2", "CHAOS_LIVE_PORT", "x"));
            check(!string.Join(" ", bad.Errors).Contains("hunter2") && !string.Join(" ", bad.Errors).Contains("acc-name"), "live smoke env: the errors never hold a value");
            var ok = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "acc-name", "CHAOS_LIVE_PASSWORD", "hunter2hunter2", "CHAOS_LIVE_CHARACTER", "Live Zed A"));
            check(!ok.Describe().Contains("hunter2") && !ok.Describe().Contains("acc-name") && !ok.Describe().Contains("Zed") && ok.Describe().Contains("127.0.0.1"), "live smoke env: the log line has host, port and identity, no account, character or password");
            check(ok.Secrets().Count == 3 && ok.Secrets().Contains("hunter2hunter2"), "live smoke env: the secrets are the password, the account and the character");
        }

        static void PlanChecks(Action<bool, string> check)
        {
            var main = LiveSmokePlan.MainWindows;
            check(main.Length >= 30 && main.Distinct().Count() == main.Length, "live smoke plan: " + main.Length + " main windows, each once");
            check(LiveSmokePlan.Native.All(n => main.Contains(n)), "live smoke plan: every native window is a main window");
            var steps = LiveSmokePlan.Windows(main, out var missing);
            check(missing.Count == 0 && steps.Count == main.Length && steps.All(s => s.Kind == WindowSmokePlan.Window) && steps.Select(s => s.Id).SequenceEqual(main), "live smoke plan: all main windows give window steps in order (the step list of the window smoke run)");
            steps = LiveSmokePlan.Windows(new[] { "SkillsWindow", "EquipmentWindow", "UnknownWindow" }, out missing);
            check(steps.Select(s => s.Id).SequenceEqual(new[] { "EquipmentWindow", "SkillsWindow" }) && missing.Count == main.Length - 2 && missing.Contains("BankWindow"), "live smoke plan: a window the build lacks is missing, not a step; the order is the plan's");
            check(LiveSmokePlan.Windows(null, out missing).Count == 0 && missing.Count == main.Length, "live smoke plan: no window list, no step");
            check(LiveSmokePlan.IsNative("MinimapWindow") && !LiveSmokePlan.IsNative("BankWindow"), "live smoke plan: native windows");

            check(!LiveSmokePlan.StepReady(100, 100, false), "live smoke plan: a step is not done at 100 ms");
            check(!LiveSmokePlan.StepReady(650, 650, true), "live smoke plan: not before the minimum, whatever came");
            check(!LiveSmokePlan.StepReady(1500, 1500, false), "live smoke plan: no answer yet, it waits for one");
            check(!LiveSmokePlan.StepReady(1500, 200, true), "live smoke plan: an answer 200 ms ago, it waits for the quiet");
            check(LiveSmokePlan.StepReady(1500, 400, true), "live smoke plan: an answer and quiet, done");
            check(LiveSmokePlan.StepReady(3000, 0, false) && LiveSmokePlan.StepReady(3200, 10, true), "live smoke plan: the maximum ends any step");
        }

        /// <summary>A simulated server: a key held confirms a step every 160 ms (not faster than one in flight); the walls refuse.</summary>
        static void Simulate(LiveWalker w, Func<int, bool> blocked, bool silent, out int moves, out int cancels, out List<int> masks, out double ms)
        {
            moves = 0; cancels = 0; masks = new List<int>();
            double now = 1000, nextStep = 0;
            int guard = 0;
            while (!w.Done && guard++ < 100000)
            {
                int m = w.Mask(now, moves, cancels);
                if (masks.Count == 0 || masks[masks.Count - 1] != m) masks.Add(m);
                if (m != 0 && !silent && now >= nextStep)
                {
                    if (blocked(m)) cancels++; else moves++;
                    nextStep = now + 160;
                }
                now += 16;
            }
            ms = now - 1000;
        }

        static void WalkChecks(Action<bool, string> check)
        {
            var legs = LiveWalker.DefaultLegs();
            check(legs.Count == 6 && legs.All(l => l.Steps == 2 && l.Mask != 0) && legs.Select(l => l.Mask).Distinct().Count() == 4 && legs.Select(l => l.Name).Distinct().Count() == 6 && legs.All(l => WalkInput.FromMask(l.Mask) != null), "live walk: six legs of two steps, one key each, all four directions, names unique");
            var w = new LiveWalker(LiveWalker.DefaultLegs());
            Simulate(w, m => false, false, out int moves, out int cancels, out var masks, out double ms);
            check(w.Done && w.Results.Count == 6 && w.Results.All(r => r.Confirmed >= 2 && !r.TimedOut && r.Cancelled == 0), "live walk: every leg confirmed on an open road: " + string.Join(",", w.Results.Select(r => r.Name + r.Confirmed)));
            check(masks.Where(m => m != 0).SequenceEqual(new[] { WalkInput.Up, WalkInput.Down, WalkInput.Right, WalkInput.Left, WalkInput.Up, WalkInput.Down }), "live walk: north, south, east, west, north, south in this order with the keys let go between");
            check(moves >= 12 && moves <= 18 && ms < 20000, "live walk: " + moves + " steps in " + (ms / 1000).ToString("0.0") + " s");
            check(w.Mask(99999, moves, cancels) == 0 && w.Done, "live walk: done stays done and holds no key");

            // a wall to the north: two refusals end each north leg, the others walk
            w = new LiveWalker(LiveWalker.DefaultLegs());
            Simulate(w, m => m == WalkInput.Up, false, out moves, out cancels, out masks, out ms);
            var north = w.Results.First(r => r.Name == "north");
            check(w.Done && north.Cancelled >= 2 && north.Confirmed == 0 && !north.TimedOut && w.Results.Count(r => r.Confirmed >= 2) == 4 && moves >= LiveSmokeReport.MinSteps, "live walk: a wall ends its leg after two refused steps, the rest still walk and the walk still passes");
            // the east and west walls of the CI server's start place (2026-11-09): north, south and the second north and south still give steps
            w = new LiveWalker(LiveWalker.DefaultLegs());
            Simulate(w, m => m == WalkInput.Left || m == WalkInput.Right, false, out moves, out cancels, out masks, out ms);
            check(w.Done && moves >= LiveSmokeReport.MinSteps && cancels >= 4, "live walk: walls east and west, " + moves + " steps still confirmed and " + cancels + " refused");

            // a silent server: every leg times out, the walker still ends
            w = new LiveWalker(LiveWalker.DefaultLegs());
            Simulate(w, m => false, true, out moves, out cancels, out masks, out ms);
            check(w.Done && moves == 0 && w.Results.Count == 6 && w.Results.All(r => r.TimedOut && r.Confirmed == 0), "live walk: a server that answers nothing times every leg out");
            check(ms >= 6 * LiveWalker.LegTimeoutMs && ms < 6 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) + 500, "live walk: and it takes about " + (6 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) / 1000).ToString("0") + " s (" + (ms / 1000).ToString("0.0") + ")");

            // late confirmations during the pause count for the leg that ended
            w = new LiveWalker(new List<LiveWalkLeg> { new LiveWalkLeg { Name = "a", Mask = WalkInput.Up, Steps = 1 } });
            int mv = 0;
            double t = 0;
            w.Mask(t, mv, 0);
            mv = 1; t += 20;
            check(w.Mask(t, mv, 0) == 0, "live walk: the leg ends at its steps");
            mv = 2; t += 100;   // a second step was already in flight
            w.Mask(t, mv, 0); t += LiveWalker.GapMs + 10;
            w.Mask(t, mv, 0);
            check(w.Done && w.Results[0].Confirmed == 2, "live walk: a step confirmed during the pause counts for its leg");
            check(new LiveWalker(new List<LiveWalkLeg>()).Mask(0, 0, 0) == 0, "live walk: no legs, nothing to do");
        }

        static void TileChecks(Action<bool, string> check)
        {
            var w = new World(null);
            check(LiveSmokePlan.TilesDrawn(w, 15, 11) == 0 && LiveSmokePlan.TilesDrawn(null, 15, 11) == 0, "live tiles: no player, no tile");
            w.PlayerId = 1;
            w.Creatures[1] = new Creature { Id = 1, Position = new Pos(100, 100, 7) };
            for (int x = 90; x <= 110; x++)
                for (int y = 90; y <= 110; y++)
                    w.GetOrMake(new Pos(x, y, 7)).Things.Add(new Thing { Item = new Item { Id = 100 } });
            w.GetOrMake(new Pos(100, 100, 8)).Things.Add(new Thing { Item = new Item { Id = 100 } });   // another floor: not counted
            w.GetOrMake(new Pos(101, 100, 7)).Things.Clear();                                           // an empty tile: not counted
            check(LiveSmokePlan.TilesDrawn(w, 15, 11) == 15 * 11 - 1, "live tiles: the 15 x 11 view round the hero counts tiles with something on them (" + LiveSmokePlan.TilesDrawn(w, 15, 11) + ")");
            check(LiveSmokePlan.TilesDrawn(w, 3, 3) == 8 && LiveSmokePlan.TilesDrawn(w, 1, 1) == 1, "live tiles: a smaller view counts fewer");
            check(w.Tiles.Count > LiveSmokePlan.TilesDrawn(w, 15, 11), "live tiles: the model holds more than the view draws");
        }

        static LiveSmokeWindow Win(string cls, bool native, params int[] ops)
        {
            var w = new LiveSmokeWindow { Name = "win:" + cls, Class = cls, Native = native, Ms = 900 };
            foreach (var o in ops) { w.Opcodes.Add(o); w.Answers++; }
            return w;
        }

        static LiveSmokeReport Good()
        {
            var r = new LiveSmokeReport { Identity = "chaos", LoginOk = true, EnterOk = true, EnterMs = 812.4, LoggedOut = true, TilesInModel = 400, TilesDrawn = 160, TilesDrawnAfterWalk = 158, StepsSent = 9, StepsConfirmed = 8, StepsCancelled = 1, Finished = true };
            r.Legs = new List<LiveWalkResult> { new LiveWalkResult { Name = "east", Wanted = 2, Confirmed = 2 } };
            r.Windows.Add(Win("SkillsWindow", false, 200, 201));
            r.Windows.Add(Win("MinimapWindow", true));
            r.OpcodesSeen.Add(200); r.OpcodesSeen.Add(201);
            return r;
        }

        static void ReportChecks(Action<bool, string> check)
        {
            var r = Good();
            check(r.Pass && r.Failures().Count == 0 && r.WalkOk, "live report: login, entry, 8 steps and no exception pass");
            check(r.NoAnswerCount == 0 && r.AnsweredCount == 1 && r.Warnings().Count == 0, "live report: a native window without an answer is not a warning");

            r.Windows.Add(Win("BankWindow", false));
            check(r.Pass && r.NoAnswerCount == 1 && r.Warnings().Any(x => x.StartsWith("BankWindow", StringComparison.Ordinal)), "live report: a window with no answer is a listed warning, not a failure");

            var f = Good(); f.LoginOk = false; f.LoginError = "Account name or password is not correct.";
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("login failed", StringComparison.Ordinal)), "live report: a failed login fails");
            f = Good(); f.EnterOk = false; f.EnterError = "no world after 90 s";
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("did not enter", StringComparison.Ordinal)), "live report: not entering fails");
            f = Good(); f.StepsConfirmed = LiveSmokeReport.MinSteps - 1;
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("walk failed", StringComparison.Ordinal)), "live report: too few confirmed steps fail the walk");
            f = Good(); f.StepsConfirmed = LiveSmokeReport.MinSteps;
            check(f.Pass, "live report: the minimum of steps passes");
            f = Good(); f.Closed = "Connection lost";
            check(!f.Pass, "live report: a closed session fails");
            f = Good(); f.Aborted = "over time";
            check(!f.Pass, "live report: an abort fails");
            f = Good(); f.LoggedOut = false;
            check(f.Pass && f.Warnings().Any(x => x.Contains("logout")), "live report: no clean logout is a warning");

            f = Good();
            f.Smoke.Begin("win:SkillsWindow", "win");
            f.Smoke.Log(true, false, "NullReferenceException: boom", "at X.Y()");
            f.Smoke.End();
            check(f.Exceptions == 1 && !f.Pass && f.Failures().Any(x => x.Contains("1 exceptions")), "live report: an exception logged in a step fails");
            f = Good();
            f.Smoke.Log(true, false, "InvalidOperationException: between steps", "at X.Z()");
            check(f.Exceptions == 1 && !f.Pass, "live report: an exception logged between steps (background) fails too");
            f = Good();
            f.Smoke.Begin("win:SkillsWindow", "win");
            f.Smoke.Log(false, false, "GUI Error: Invalid GUILayout state in X view", "");
            f.Smoke.End();
            check(f.LayoutErrors == 1 && f.Pass && f.Warnings().Any(x => x.Contains("layout")), "live report: an IMGUI layout error is a warning, not a failure");

            // json
            f = Good();
            f.Windows[0].Record = f.Smoke.Begin("win:SkillsWindow", "win");
            f.Smoke.Log(false, true, "Error with the secret hunter2hunter2 and the account lcp1abc", "at Foo()");
            f.Smoke.End();
            f.Screenshots = 2; f.Sheets = 1;
            string json = f.ToJson(new[] { "hunter2hunter2", "lcp1abc", "" });
            check(!json.Contains("hunter2hunter2") && !json.Contains("lcp1abc") && json.Contains("<removed>"), "live report json: every secret is cut out of every text");
            var parsed = Json.TryParse(json);
            check(parsed != null && Json.Text(parsed, "identity") == "chaos" && Json.Bool(parsed, "pass"), "live report json: valid json with identity and pass");
            var walk = Json.Get(parsed, "walk");
            check(Json.Int(walk, "confirmed") == 8 && Json.Int(walk, "sent") == 9 && Json.Int(walk, "cancelled") == 1 && Json.Bool(walk, "ok") && Json.List(walk, "legs").Count == 1, "live report json: the walk section");
            var map = Json.Get(parsed, "map");
            check(Json.Int(map, "tilesDrawn") == 160 && Json.Int(map, "tilesInModel") == 400, "live report json: the map section");
            var wins = Json.List(parsed, "windows");
            check(wins.Count == 2 && Json.Int(wins[0], "answers") == 2 && Json.List(wins[0], "opcodes").Count == 2 && Json.Bool(wins[1], "native"), "live report json: windows with answers and opcodes");
            check(Json.List(parsed, "opcodesSeen").Count == 2 && Json.Int(Json.Get(parsed, "summary"), "windows") == 2 && Json.Int(Json.Get(parsed, "summary"), "loggedErrors") == 1, "live report json: opcodes seen and the summary");
            check(!json.Any(c => c > 0x7e), "live report json: ASCII only");
            var failing = Good(); failing.LoginOk = false;
            var fp = Json.TryParse(failing.ToJson(null));
            check(fp != null && !Json.Bool(fp, "pass") && Json.List(fp, "failures").Count >= 1, "live report json: a failing run says why");

            string line = Good().SummaryLine();
            check(line.StartsWith("chaos live smoke: identity chaos, login ok, entered ok, walk 8 of 9 steps confirmed, 160 tiles drawn, 2 windows (1 with an answer, 0 without), 0 exceptions, 0 layout errors, pass", StringComparison.Ordinal), "live report: the summary line: " + line);
            check(LiveSmokeReport.SheetName(0) == "live_smoke_sheet_1.png" && LiveSmokeReport.SheetName(11) == "live_smoke_sheet_12.png", "live report: sheet file names");
        }
    }
}
