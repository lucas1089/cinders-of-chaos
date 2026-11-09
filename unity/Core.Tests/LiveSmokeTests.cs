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
            // the four windows of the first run without an answer (2026-11-09): none should get one on open
            check(LiveSmokePlan.RuleOf("SkillsWindow").Mode == LiveWindowMode.Prefetch && LiveSmokePlan.RuleOf("SkillsWindow").Opcode == 119, "live smoke plan: Skills is asked at the game start on opcode 119");
            check(LiveSmokePlan.RuleOf("DungeonsWindow").Mode == LiveWindowMode.Prefetch && LiveSmokePlan.RuleOf("DungeonsWindow").Opcode == DungeonsState.Opcode, "live smoke plan: Dungeons is fetched at the game start on its opcode");
            check(LiveSmokePlan.RuleOf("HelperWindow").Mode == LiveWindowMode.Local && LiveSmokePlan.RuleOf("ItemFinderWindow").Mode == LiveWindowMode.Local, "live smoke plan: Helper and Item Finder send nothing on open");
            check(LiveSmokePlan.RuleOf("BankWindow").Mode == LiveWindowMode.Asks && LiveSmokePlan.RuleOf("MinimapWindow").Mode == LiveWindowMode.Native, "live smoke plan: a module window asks, a native one does not");
            check(LiveSmokePlan.MainWindows.All(w => LiveSmokePlan.RuleOf(w).Why.Length > 0 || LiveSmokePlan.RuleOf(w).Mode == LiveWindowMode.Asks), "live smoke plan: every window that is not expected to ask says why");
            check(LiveSmokePlan.MainWindows.Where(w => LiveSmokePlan.RuleOf(w).Mode == LiveWindowMode.Prefetch).All(w => LiveSmokePlan.RuleOf(w).Opcode > 0), "live smoke plan: a prefetched window names its opcode");
            // the opcode a window of the catalog asks on is the same the fake server answers, for the windows that ask
            var asking = LiveSmokePlan.MainWindows.Where(w => LiveSmokePlan.RuleOf(w).Mode == LiveWindowMode.Asks).ToList();
            check(asking.Count + LiveSmokePlan.MainWindows.Count(w => LiveSmokePlan.RuleOf(w).Mode != LiveWindowMode.Asks) == LiveSmokePlan.MainWindows.Length && asking.Count >= 28, "live smoke plan: " + asking.Count + " windows ask, the rest is native, local or prefetched");

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

        static readonly Pos Start = new Pos(1000, 1000, 7);

        static List<LiveWalkLeg> OpenLegs() => LiveWalker.LegsAround(Start, p => true);

        static void WalkChecks(Action<bool, string> check)
        {
            // legs from the map round the start: the client's own walkable check decides
            var legs = OpenLegs();
            check(legs.Count == 8 && legs.All(l => l.Steps == 2 && l.Mask != 0) && legs.Select(l => l.Name).Distinct().Count() == 8 && legs.All(l => WalkInput.FromMask(l.Mask) != null) && legs.Count(l => l.Mirror) == 4, "live walk: an open start gives eight legs of two steps, out and back in four directions, names unique");
            check(legs.Where(l => !l.Mirror).Select(l => l.Mask).SequenceEqual(new[] { WalkInput.Up, WalkInput.Down, WalkInput.Right, WalkInput.Left }), "live walk: north, south, east, west in this order");
            for (int i = 0; i < legs.Count; i += 2)
                check(legs[i + 1].Mirror && (legs[i].Mask ^ legs[i + 1].Mask) is int x && (x == (WalkInput.Up | WalkInput.Down) || x == (WalkInput.Left | WalkInput.Right)), "live walk: leg " + legs[i].Name + " is followed by its way back");

            // a wall north and a one-tile gap east: no north leg, east one step; the asked tiles are the ones beyond the start
            var asked = new List<Pos>();
            var walls = LiveWalker.LegsAround(Start, p => { asked.Add(p); return !(p.X == Start.X && p.Y < Start.Y) && !(p.X > Start.X + 1); });
            check(walls.Select(l => l.Name).SequenceEqual(new[] { "south", "back north", "east", "back west", "west", "back east" }) && walls.First(l => l.Name == "east").Steps == 1 && walls.First(l => l.Name == "south").Steps == 2, "live walk: a wall has no leg, a gap of one tile gives one step: " + string.Join(",", walls.Select(l => l.Name + l.Steps)));
            check(asked.Contains(new Pos(Start.X, Start.Y - 1, 7)) && asked.Contains(new Pos(Start.X + 2, Start.Y, 7)) && asked.All(q => q.Z == 7), "live walk: the check is asked for the tiles next to the start on its floor");
            check(LiveWalker.LegsAround(Start, p => false).Count == 0, "live walk: nothing walkable, no leg");
            check(new LiveWalker(LiveWalker.LegsAround(Start, p => false)).Mask(0, 0, 0) == 0, "live walk: and the walker ends at once");

            // the real start tile of the first run: the north tile was a wall and the east and west ones were not the same on both characters; legs from that map never touch a wall
            var map = new HashSet<Pos>();
            for (int dx = -3; dx <= 3; dx++) for (int dy = -3; dy <= 3; dy++) map.Add(new Pos(Start.X + dx, Start.Y + dy, 7));
            map.Remove(new Pos(Start.X, Start.Y - 1, 7));           // the wall north of the start
            map.Remove(new Pos(Start.X + 1, Start.Y, 7));           // a pillar east
            var around = LiveWalker.LegsAround(Start, map.Contains);
            check(around.All(l => l.Name != "north" && l.Name != "east") && around.Any(l => l.Name == "south") && around.Any(l => l.Name == "west"), "live walk: a start with walls north and east walks south and west only");

            var w = new LiveWalker(OpenLegs());
            Simulate(w, m => false, false, out int moves, out int cancels, out var masks, out double ms);
            check(w.Done && w.Results.Count == 8 && w.Results.All(r => r.Confirmed >= 2 && !r.TimedOut && r.Cancelled == 0), "live walk: every leg confirmed on an open road: " + string.Join(",", w.Results.Select(r => r.Name + r.Confirmed)));
            check(masks.Where(m => m != 0).SequenceEqual(new[] { WalkInput.Up, WalkInput.Down, WalkInput.Down, WalkInput.Up, WalkInput.Right, WalkInput.Left, WalkInput.Left, WalkInput.Right }), "live walk: north and back, south and back, east and back, west and back with the keys let go between");
            check(moves >= 16 && moves <= 24 && ms < 30000, "live walk: " + moves + " steps in " + (ms / 1000).ToString("0.0") + " s");
            check(w.Mask(99999, moves, cancels) == 0 && w.Done, "live walk: done stays done and holds no key");

            // a wall the client did not know of (a prediction finding): two refusals end the north leg, its way back has nothing to walk, the rest walks
            w = new LiveWalker(OpenLegs());
            Simulate(w, m => m == WalkInput.Up, false, out moves, out cancels, out masks, out ms);
            var north = w.Results.First(r => r.Name == "north");
            var backSouth = w.Results.First(r => r.Name == "back south");
            check(w.Done && north.Cancelled >= 2 && north.Confirmed == 0 && !north.TimedOut && backSouth.Wanted == 0 && backSouth.Confirmed == 0, "live walk: a refused leg ends after two refusals and its way back is skipped");
            check(w.Results.Count(r => r.Confirmed >= 2) >= 5 && moves >= LiveSmokeReport.MinSteps, "live walk: the other legs still walk");
            // the way back is a short skip, not a pause of a leg's length
            check(ms < 4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs), "live walk: " + (ms / 1000).ToString("0.0") + " s with a refused leg");

            // a silent server: every out leg times out, the ways back are skipped, the walker still ends
            w = new LiveWalker(OpenLegs());
            Simulate(w, m => false, true, out moves, out cancels, out masks, out ms);
            check(w.Done && moves == 0 && w.Results.Count == 8 && w.Results.Where(r => r.Wanted > 0).All(r => r.TimedOut && r.Confirmed == 0) && w.Results.Count(r => r.Wanted == 0) == 4, "live walk: a server that answers nothing times the out legs out and skips the ways back");
            check(ms >= 4 * LiveWalker.LegTimeoutMs && ms < 4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) + 1500, "live walk: and it takes about " + (4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) / 1000).ToString("0") + " s (" + (ms / 1000).ToString("0.0") + ")");

            // a held key overshoots by the steps in flight: the way back is as long as what the leg really confirmed, so the hero is back where it began
            var pair = new List<LiveWalkLeg> { new LiveWalkLeg { Name = "south", Mask = WalkInput.Down, Steps = 2 }, new LiveWalkLeg { Name = "back north", Mask = WalkInput.Up, Steps = 2, Mirror = true } };
            w = new LiveWalker(pair);
            int mv = 0;
            double t = 0;
            w.Mask(t, mv, 0);
            mv = 3; t += 20;                                   // the third step was in flight when the second was confirmed
            check(w.Mask(t, mv, 0) == 0, "live walk: the out leg ends at its steps");
            t += LiveWalker.GapMs + 10;
            check(w.Mask(t, mv, 0) == WalkInput.Up && pair[1].Steps == 3, "live walk: the way back asks for the three steps that were walked");
            mv = 6; t += 20;
            check(w.Mask(t, mv, 0) == 0 && w.Results.Count == 2 && w.Results[1].Wanted == 3 && w.Results[1].Confirmed == 3, "live walk: the way back ends at the same three steps");

            // late confirmations during the pause count for the leg that ended
            w = new LiveWalker(new List<LiveWalkLeg> { new LiveWalkLeg { Name = "a", Mask = WalkInput.Up, Steps = 1 } });
            mv = 0; t = 0;
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

        static LiveSmokeWindow Win(string cls, params int[] ops)
        {
            var w = new LiveSmokeWindow { Name = "win:" + cls, Class = cls, Ms = 900 };
            foreach (var o in ops) { w.Opcodes.Add(o); w.Answers++; }
            return w;
        }

        static LiveSmokeReport Good()
        {
            var r = new LiveSmokeReport { Identity = "chaos", LoginOk = true, EnterOk = true, EnterMs = 812.4, LoggedOut = true, TilesInModel = 400, TilesDrawn = 160, TilesDrawnAfterWalk = 158, StepsPlanned = 8, StepsSent = 9, StepsConfirmed = 8, StepsCancelled = 1, Finished = true };
            r.Legs = new List<LiveWalkResult> { new LiveWalkResult { Name = "east", Wanted = 2, Confirmed = 2 } };
            r.Windows.Add(Win("BankWindow", 200, 201));
            r.Windows.Add(Win("MinimapWindow"));
            r.OpcodesSeen.Add(200); r.OpcodesSeen.Add(201);
            return r;
        }

        /// <summary>Every window of the run ends in exactly one of answered, prefetched, local-only, needs a condition, no answer: the first run counted 43 windows, 33 answered and
        /// 4 without, and 6 fell in neither (the native ones without an answer).</summary>
        static void AccountChecks(Action<bool, string> check)
        {
            // the first run, Extended: 33 windows answered (3 of them native), 4 without (Skills, Helper, Dungeons, Item Finder) and 6 native ones silent
            var r = new LiveSmokeReport { Identity = "extended", LoginOk = true, EnterOk = true, LoggedOut = true, TilesDrawn = 165 };
            var silentNative = new[] { "EquipmentWindow", "ContainersWindow", "BattleListWindow", "MinimapWindow", "ChannelsWindow", "MapMarkersWindow" };
            var answeredNative = new[] { "FightWindow", "OutfitWindow", "LootWindow" };
            var four = new[] { "SkillsWindow", "HelperWindow", "DungeonsWindow", "ItemFinderWindow" };
            foreach (var cls in LiveSmokePlan.MainWindows)
            {
                if (silentNative.Contains(cls) || four.Contains(cls)) r.Windows.Add(Win(cls));
                else r.Windows.Add(Win(cls, 100));
            }
            check(r.Windows.Count == 43 && r.AnsweredCount == 33 && silentNative.Concat(answeredNative).All(LiveSmokePlan.IsNative), "live account: the first run: 43 windows, 33 answered (" + r.AnsweredCount + ")");
            check(r.LocalCount == 8 && r.NoAnswerCount == 2 && r.AccountedCount == 43, "live account: before Skills and Dungeons are known as login requests: 8 local-only, 2 without an answer, all 43 accounted for (" + r.SummaryLine() + ")");

            // the same run with the rules: Skills and Dungeons were asked at login (119 and 109 seen before the steps), Helper and Item Finder send nothing
            r.Prefetched.Add(119); r.Prefetched.Add(109); r.Prefetched.Add(200);
            check(r.NoAnswerCount == 0 && r.PrefetchedCount == 2 && r.LocalCount == 8 && r.AnsweredCount == 33 && r.NeedsConditionCount == 0 && r.AccountedCount == 43, "live account: 33 answered, 2 prefetched, 8 local-only, none without an answer: " + r.SummaryLine());
            check(r.Warnings().Count == 0 && r.Notes().Count == 0 && r.Windows.All(w => r.StatusOf(w) != LiveWindowStatus.NoAnswer), "live account: and no warning is left");
            check(LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "DungeonsWindow"))) == "prefetched" && LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "ItemFinderWindow"))) == "local" && LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "BankWindow"))) == "answered", "live account: status names of a prefetched, a local-only and an answered window");

            // Skills asked at login but the answer never came: a warning that names the opcode, not a silent pass
            var late = new LiveSmokeReport { LoginOk = true, EnterOk = true };
            late.Windows.Add(Win("SkillsWindow"));
            check(late.NoAnswerCount == 1 && late.Warnings().Any(x => x == "SkillsWindow: opcode 119 never came after the login request"), "live account: a prefetch window whose opcode never came is a warning with the opcode");
            // an answer while the window was open also counts when the login one is missing
            late = new LiveSmokeReport { LoginOk = true, EnterOk = true };
            late.Windows.Add(Win("SkillsWindow", 119));
            check(late.AnsweredCount == 1 && late.NoAnswerCount == 0, "live account: a prefetch window answered while it was open is answered");
            // a window that needs a condition the test character lacks is its own count and a note, no warning
            late = new LiveSmokeReport { LoginOk = true, EnterOk = true };
            late.Windows.Add(Win("RaidWindow")); late.Windows.Add(Win("BankWindow"));
            late.Conditions["RaidWindow"] = "level 1500";
            check(late.NeedsConditionCount == 1 && late.NoAnswerCount == 1 && late.AccountedCount == 2 && late.Notes().Count == 1 && late.Notes()[0] == "RaidWindow: needs condition: level 1500" && late.Warnings().All(x => !x.StartsWith("RaidWindow", StringComparison.Ordinal)), "live account: a known condition is a note, not a warning");
            late.Windows.Add(Win("MarketWindow", 120));
            late.Conditions["MarketWindow"] = "a guild";
            check(late.StatusOf(late.Windows[2]) == LiveWindowStatus.Answered, "live account: a window that answered is answered whatever its listed condition");
            // the json says the status of every window and the counts add up
            var pj = Json.TryParse(r.ToJson(null));
            var wins = Json.List(pj, "windows");
            var sum = Json.Get(pj, "summary");
            check(wins.Count == 43 && Json.Int(sum, "answered") + Json.Int(sum, "prefetched") + Json.Int(sum, "local") + Json.Int(sum, "needsCondition") + Json.Int(sum, "noAnswer") == 43, "live account json: the five counts add up to the windows");
            check(wins.All(w => new[] { "answered", "prefetched", "local", "needsCondition", "noAnswer" }.Contains(Json.Text(w, "status"))) && Json.List(pj, "opcodesAtLogin").Count == 3, "live account json: every window has a status, and the opcodes at login are listed");
        }

        static void ReportChecks(Action<bool, string> check)
        {
            var r = Good();
            check(r.Pass && r.Failures().Count == 0 && r.WalkOk, "live report: login, entry, 8 steps and no exception pass");
            check(r.NoAnswerCount == 0 && r.AnsweredCount == 1 && r.LocalCount == 1 && r.Warnings().Count == 0, "live report: a native window without an answer is local-only, not a warning");

            r.Windows.Add(Win("MarketWindow"));
            check(r.Pass && r.NoAnswerCount == 1 && r.Warnings().Any(x => x.StartsWith("MarketWindow", StringComparison.Ordinal)), "live report: a window with no answer is a listed warning, not a failure");

            AccountChecks(check);

            var f = Good(); f.LoginOk = false; f.LoginError = "Account name or password is not correct.";
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("login failed", StringComparison.Ordinal)), "live report: a failed login fails");
            f = Good(); f.EnterOk = false; f.EnterError = "no world after 90 s";
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("did not enter", StringComparison.Ordinal)), "live report: not entering fails");
            f = Good(); f.StepsConfirmed = LiveSmokeReport.MinSteps - 1;
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("walk failed", StringComparison.Ordinal)), "live report: too few confirmed steps fail the walk");
            f = Good(); f.StepsPlanned = 6; f.StepsConfirmed = LiveSmokeReport.MinSteps;
            check(f.Pass, "live report: the minimum of steps passes when half of the plan is done");
            f = Good(); f.StepsPlanned = 16; f.StepsConfirmed = 7;
            check(!f.Pass && f.Failures().Any(x => x.Contains("7 of 16")), "live report: less than half of the planned steps fails the walk");
            f = Good(); f.StepsPlanned = 16; f.StepsConfirmed = 8;
            check(f.Pass, "live report: half of the planned steps passes");
            f = Good(); f.StepsPlanned = 2; f.StepsConfirmed = 2;
            check(f.Pass, "live report: a cramped start with two planned steps needs only those two");
            f = Good(); f.StepsPlanned = 0; f.StepsConfirmed = 0;
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("walk not tried", StringComparison.Ordinal)), "live report: no walkable tile round the start is its own failure");
            f = Good();
            f.Legs = new List<LiveWalkResult> { new LiveWalkResult { Name = "north", Wanted = 2, Confirmed = 0, Cancelled = 3 } };
            check(f.Pass && f.Warnings().Any(x => x.StartsWith("leg north: 3 refused", StringComparison.Ordinal)), "live report: a refused leg on a tile the client thought free is a warning, with the count");
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
            f.Windows[0].Record = f.Smoke.Begin("win:BankWindow", "win");
            f.Smoke.Log(false, true, "Error with the secret hunter2hunter2 and the account lcp1abc", "at Foo()");
            f.Smoke.End();
            f.Screenshots = 2; f.Sheets = 1;
            string json = f.ToJson(new[] { "hunter2hunter2", "lcp1abc", "" });
            check(!json.Contains("hunter2hunter2") && !json.Contains("lcp1abc") && json.Contains("<removed>"), "live report json: every secret is cut out of every text");
            var parsed = Json.TryParse(json);
            check(parsed != null && Json.Text(parsed, "identity") == "chaos" && Json.Bool(parsed, "pass"), "live report json: valid json with identity and pass");
            var walk = Json.Get(parsed, "walk");
            check(Json.Int(walk, "planned") == 8 && Json.Int(walk, "confirmed") == 8 && Json.Int(walk, "sent") == 9 && Json.Int(walk, "cancelled") == 1 && Json.Bool(walk, "ok") && Json.List(walk, "legs").Count == 1, "live report json: the walk section");
            var map = Json.Get(parsed, "map");
            check(Json.Int(map, "tilesDrawn") == 160 && Json.Int(map, "tilesInModel") == 400, "live report json: the map section");
            var wins = Json.List(parsed, "windows");
            check(wins.Count == 2 && Json.Int(wins[0], "answers") == 2 && Json.List(wins[0], "opcodes").Count == 2 && Json.Bool(wins[1], "native") && Json.Text(wins[0], "status") == "answered" && Json.Text(wins[1], "status") == "local", "live report json: windows with answers, opcodes and status");
            check(Json.List(parsed, "opcodesSeen").Count == 2 && Json.Int(Json.Get(parsed, "summary"), "windows") == 2 && Json.Int(Json.Get(parsed, "summary"), "loggedErrors") == 1, "live report json: opcodes seen and the summary");
            var sum = Json.Get(parsed, "summary");
            check(Json.Int(sum, "answered") == 1 && Json.Int(sum, "local") == 1 && Json.Int(sum, "prefetched") == 0 && Json.Int(sum, "needsCondition") == 0 && Json.Int(sum, "noAnswer") == 0 && Json.List(parsed, "notes").Count == 0 && Json.List(parsed, "opcodesAtLogin").Count == 0, "live report json: the five window counts, the notes and the opcodes at login");
            check(!json.Any(c => c > 0x7e), "live report json: ASCII only");
            var failing = Good(); failing.LoginOk = false;
            var fp = Json.TryParse(failing.ToJson(null));
            check(fp != null && !Json.Bool(fp, "pass") && Json.List(fp, "failures").Count >= 1, "live report json: a failing run says why");

            string line = Good().SummaryLine();
            check(line.StartsWith("chaos live smoke: identity chaos, login ok, entered ok, walk 8 of 9 steps confirmed, 160 tiles drawn, 2 windows (1 answered, 0 prefetched at login, 1 local-only, 0 need a condition, 0 without an answer), 0 exceptions, 0 layout errors, pass", StringComparison.Ordinal), "live report: the summary line: " + line);
            check(LiveSmokeReport.SheetName(0) == "live_smoke_sheet_1.png" && LiveSmokeReport.SheetName(11) == "live_smoke_sheet_12.png", "live report: sheet file names");
        }
    }
}
