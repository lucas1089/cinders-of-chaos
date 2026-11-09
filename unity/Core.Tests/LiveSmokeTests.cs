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
            NewPlayerChecks(check);
            FirstFightChecks(check);
            SlowCallChecks(check);
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

        /// <summary>A simulated client and server: a held key sends a step as soon as fewer than two are out and the last glide is about to end (the client's pipelining, WalkTiming
        /// MaxPending and PreWalkLeadMs); the server answers each 160 ms after the one before; a step onto a blocked tile is refused and drops every step still out. Mask() is asked
        /// before the key path of every frame, as ChaosApp.LiveSmoke does. `Touched` is every tile a step was sent to.</summary>
        sealed class Sim
        {
            public Pos Pos = Start;
            public int Sent, Moves, Cancels;
            public readonly List<Pos> Touched = new List<Pos>();
            public readonly List<int> Masks = new List<int>();
            public double Ms;
            readonly List<(Pos to, double at)> pending = new List<(Pos, double)>();

            public void Run(LiveWalker w, Func<Pos, bool> blocked, bool silent)
            {
                double now = 1000, lastEnd = 0;
                int guard = 0;
                while (!w.Done && guard++ < 100000)
                {
                    int m = w.Mask(now, Moves, Cancels, Sent);
                    if (Masks.Count == 0 || Masks[Masks.Count - 1] != m) Masks.Add(m);
                    // the server answers
                    while (!silent && pending.Count > 0 && now >= pending[0].at)
                    {
                        var st = pending[0]; pending.RemoveAt(0);
                        if (blocked(st.to)) { Cancels++; pending.Clear(); lastEnd = now; }
                        else { Moves++; Pos = st.to; }
                    }
                    // the key path: one step per frame at most
                    if (m != 0 && pending.Count < 2 && now >= lastEnd - 90)
                    {
                        var d = WalkInput.FromMask(m).Value;
                        var tip = pending.Count > 0 ? pending[pending.Count - 1].to : Pos;
                        var to = WalkDirs.Step(tip, d);
                        double conf = Math.Max(now + 40, pending.Count > 0 ? pending[pending.Count - 1].at + 160 : now + 40);
                        pending.Add((to, conf));
                        Touched.Add(to);
                        Sent++;
                        lastEnd = conf + 120;
                    }
                    now += 16;
                }
                Ms = now - 1000;
            }
        }

        static readonly Pos Start = new Pos(1000, 1000, 7);

        static List<LiveWalkLeg> OpenLegs() => LiveWalker.LegsAround(Start, p => true);

        static Pos At(int dx, int dy) => new Pos(Start.X + dx, Start.Y + dy, 7);

        static void WalkChecks(Action<bool, string> check)
        {
            // legs from the map round the start: the client's own walkable check decides
            var legs = OpenLegs();
            check(legs.Count == 8 && legs.All(l => l.Steps == 2 && l.Mask != 0) && legs.Select(l => l.Name).Distinct().Count() == 8 && legs.All(l => WalkInput.FromMask(l.Mask) != null) && legs.Count(l => l.Mirror) == 4, "live walk: an open start gives eight legs of two steps, out and back in four directions, names unique");
            check(legs.Where(l => !l.Mirror).Select(l => l.Mask).SequenceEqual(new[] { WalkInput.Up, WalkInput.Down, WalkInput.Right, WalkInput.Left }), "live walk: north, south, east, west in this order");
            for (int i = 0; i < legs.Count; i += 2)
                check(legs[i + 1].Mirror && (legs[i].Mask ^ legs[i + 1].Mask) is int x && (x == (WalkInput.Up | WalkInput.Down) || x == (WalkInput.Left | WalkInput.Right)), "live walk: leg " + legs[i].Name + " is followed by its way back");

            // the margin: every tile a leg can reach is asked, the planned ones, and one past the end (the way back goes by position and stops at the start, so it needs no margin)
            var asked = new List<Pos>();
            LiveWalker.LegsAround(Start, p => { asked.Add(p); return true; });
            check(asked.Contains(At(0, -3)) && asked.Contains(At(0, 3)) && asked.Contains(At(3, 0)) && asked.Contains(At(-3, 0)) && !asked.Contains(At(0, 0)) && asked.All(q => q.Z == 7), "live walk: the check is asked for the tile past the planned end of every leg, on the start's floor");
            // a wall at three tiles north: the leg is one step (two free tiles, one is the margin); a wall at two tiles: no north leg
            var cut = LiveWalker.LegsAround(Start, p => !(p.X == Start.X && p.Y <= Start.Y - 3));
            check(cut.First(l => l.Name == "north").Steps == 1 && cut.First(l => l.Name == "back south").Steps == 1 && cut.First(l => l.Name == "south").Steps == 2, "live walk: a wall at three tiles north cuts the north leg to one step, the margin tile stays free");
            var cut2 = LiveWalker.LegsAround(Start, p => !(p.X == Start.X && p.Y <= Start.Y - 2));
            check(cut2.All(l => l.Name != "north" && l.Name != "back south") && cut2.Any(l => l.Name == "south"), "live walk: a wall at two tiles north leaves no room for a margin, no north leg");
            check(LiveWalker.LegsAround(Start, p => p.X == Start.X && (p.Y == Start.Y - 1 || p.Y == Start.Y - 2), 2, 0).Any(l => l.Name == "north" && l.Steps == 2), "live walk: margin 0 plans the old way");
            check(LiveWalker.LegsAround(Start, p => false).Count == 0, "live walk: nothing walkable, no leg");
            check(new LiveWalker(LiveWalker.LegsAround(Start, p => false)).Mask(0, 0, 0, 0) == 0, "live walk: and the walker ends at once");

            // the real start tile of the first run: the north tile was a wall and the east and west ones were not the same on both characters; legs from that map never touch a wall
            var map = new HashSet<Pos>();
            for (int dx = -4; dx <= 4; dx++) for (int dy = -4; dy <= 4; dy++) map.Add(At(dx, dy));
            map.Remove(At(0, -1));           // the wall north of the start
            map.Remove(At(1, 0));            // a pillar east
            var around = LiveWalker.LegsAround(Start, map.Contains);
            check(around.All(l => l.Name != "north" && l.Name != "east" && l.Name != "back south" && l.Name != "back west") && around.Any(l => l.Name == "south") && around.Any(l => l.Name == "west") && around.Count == 4, "live walk: a start with walls north and east walks south and west only");

            // an open road with a client that keeps two steps out: no step goes past the plan, sent = confirmed + refused, the hero ends where it began
            var sim = new Sim();
            var w = new LiveWalker(OpenLegs(), () => sim.Pos);
            sim.Run(w, p => false, false);
            int planned = OpenLegs().Sum(l => l.Steps);
            check(w.Done && w.Results.Count == 8 && w.Results.All(r => r.Sent == r.Wanted && r.Confirmed == r.Wanted && r.Cancelled == 0 && !r.TimedOut), "live walk: every leg sent, and had confirmed, exactly its steps: " + string.Join(",", w.Results.Select(r => r.Name + " " + r.Sent + "/" + r.Confirmed + "/" + r.Wanted)));
            check(sim.Sent == planned && sim.Moves == planned && sim.Cancels == 0 && sim.Pos.Equals(Start), "live walk: " + planned + " steps planned, sent, confirmed, none refused, net zero (" + sim.Sent + "," + sim.Moves + "," + sim.Cancels + ")");
            var okTiles = new HashSet<Pos>(new[] { At(0, -1), At(0, -2), At(0, 1), At(0, 2), At(1, 0), At(2, 0), At(-1, 0), At(-2, 0), Start });
            check(sim.Touched.All(okTiles.Contains), "live walk: every step went to a tile of the plan");
            check(sim.Masks.Where(m => m != 0).SequenceEqual(new[] { WalkInput.Up, WalkInput.Down, WalkInput.Down, WalkInput.Up, WalkInput.Right, WalkInput.Left, WalkInput.Left, WalkInput.Right }), "live walk: north and back, south and back, east and back, west and back with the keys let go between");
            check(sim.Ms < 30000, "live walk: " + (sim.Ms / 1000).ToString("0.0") + " s");
            check(w.Mask(99999, sim.Moves, sim.Cancels, sim.Sent) == 0 && w.Done, "live walk: done stays done and holds no key");

            // a margin tile the server refuses (the client thought it free) is never walked: the legs stop at their planned steps
            sim = new Sim();
            w = new LiveWalker(OpenLegs(), () => sim.Pos);
            sim.Run(w, p => p.Equals(At(0, -3)) || p.Equals(At(0, 3)) || p.Equals(At(3, 0)) || p.Equals(At(-3, 0)), false);
            check(sim.Cancels == 0 && sim.Moves == planned && sim.Pos.Equals(Start), "live walk: a wall on the margin tile is never touched by a leg of two steps");

            // a wall the client did not know of (a prediction finding) two tiles north: one step is confirmed, one refused, the way back is the one step walked
            sim = new Sim();
            w = new LiveWalker(OpenLegs(), () => sim.Pos);
            sim.Run(w, p => p.Equals(At(0, -2)), false);
            var north = w.Results.First(r => r.Name == "north");
            var backSouth = w.Results.First(r => r.Name == "back south");
            check(w.Done && north.Wanted == 2 && north.Sent == 2 && north.Confirmed == 1 && north.Cancelled == 1 && !north.TimedOut, "live walk: a refused step ends the north leg: sent " + north.Sent + " confirmed " + north.Confirmed + " refused " + north.Cancelled);
            check(backSouth.Wanted == 1 && backSouth.Sent == 1 && backSouth.Confirmed == 1 && backSouth.Cancelled == 0, "live walk: the way back is by position, one step");
            check(sim.Pos.Equals(Start) && sim.Sent == sim.Moves + sim.Cancels && sim.Cancels == 1, "live walk: the hero is home and sent = confirmed + refused (" + sim.Sent + "," + sim.Moves + "," + sim.Cancels + ")");

            // a wall at the first tile (a real prediction miss): the leg ends after the refusal, the way back is skipped, the others walk
            sim = new Sim();
            w = new LiveWalker(OpenLegs(), () => sim.Pos);
            sim.Run(w, p => p.Equals(At(0, -1)), false);
            north = w.Results.First(r => r.Name == "north");
            backSouth = w.Results.First(r => r.Name == "back south");
            check(w.Done && north.Confirmed == 0 && north.Cancelled >= 1 && backSouth.Wanted == 0 && backSouth.Sent == 0, "live walk: a leg refused at its first step has no way back");
            check(w.Results.Count(r => r.Confirmed >= 2) >= 5 && sim.Moves >= LiveSmokeReport.MinSteps && sim.Pos.Equals(Start), "live walk: the other legs still walk and the hero is home");
            check(sim.Ms < 4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs), "live walk: " + (sim.Ms / 1000).ToString("0.0") + " s with a refused leg");

            // a silent server: every out leg times out, the ways back are skipped (the hero did not move), the walker still ends
            sim = new Sim();
            w = new LiveWalker(OpenLegs(), () => sim.Pos);
            sim.Run(w, p => false, true);
            check(w.Done && sim.Moves == 0 && w.Results.Count == 8 && w.Results.Where(r => r.Wanted > 0).All(r => r.TimedOut && r.Confirmed == 0 && r.Sent <= r.Wanted && r.Lost == r.Sent) && w.Results.Count(r => r.Wanted == 0) == 4, "live walk: a server that answers nothing times the out legs out and skips the ways back");
            check(sim.Ms >= 4 * LiveWalker.LegTimeoutMs && sim.Ms < 4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) + 1500, "live walk: and it takes about " + (4 * (LiveWalker.LegTimeoutMs + LiveWalker.GapMs) / 1000).ToString("0") + " s (" + (sim.Ms / 1000).ToString("0.0") + ")");

            // the key goes up when the planned steps are SENT, not when they are confirmed: with two out the third is never sent
            var pair = new List<LiveWalkLeg> { new LiveWalkLeg { Name = "south", Mask = WalkInput.Down, Steps = 2 }, new LiveWalkLeg { Name = "back north", Mask = WalkInput.Up, Steps = 2, Mirror = true } };
            w = new LiveWalker(pair);
            int mv = 0, sent = 0;
            double t = 0;
            check(w.Mask(t, mv, 0, sent) == WalkInput.Down, "live walk: the key is held at the start");
            sent = 1; t += 20;
            check(w.Mask(t, mv, 0, sent) == WalkInput.Down, "live walk: one of two steps sent, still held");
            sent = 2; t += 20;
            check(w.Mask(t, mv, 0, sent) == 0, "live walk: two of two sent, the key is up before any is confirmed");
            mv = 1; t += 100;
            check(w.Mask(t, mv, 0, sent) == 0 && w.Results.Count == 0, "live walk: the leg waits for the answers of its steps");
            mv = 2; t += 100;
            w.Mask(t, mv, 0, sent);
            check(w.Results.Count == 1 && w.Results[0].Sent == 2 && w.Results[0].Confirmed == 2, "live walk: and ends when both are answered");
            t += LiveWalker.GapMs + 10;
            check(w.Mask(t, mv, 0, sent) == WalkInput.Up && pair[1].Steps == 2, "live walk: without a position the way back is what the leg confirmed");
            sent = 4; mv = 4; t += 20;
            w.Mask(t, mv, 0, sent);
            check(w.Results.Count == 2 && w.Results[1].Wanted == 2 && w.Results[1].Confirmed == 2, "live walk: the way back ends at the same steps");

            // late answers during the pause count for the leg that ended
            w = new LiveWalker(new List<LiveWalkLeg> { new LiveWalkLeg { Name = "a", Mask = WalkInput.Up, Steps = 1 } });
            mv = 0; sent = 0; t = 0;
            w.Mask(t, mv, 0, sent);
            sent = 1; mv = 1; t += 20;
            check(w.Mask(t, mv, 0, sent) == 0 && w.Results.Count == 1, "live walk: the leg ends at its steps");
            mv = 2; sent = 2; t += 100;   // a step of the key path that was already out
            w.Mask(t, mv, 0, sent); t += LiveWalker.GapMs + 10;
            w.Mask(t, mv, 0, sent);
            check(w.Done && w.Results[0].Confirmed == 2 && w.Results[0].Sent == 2, "live walk: a step answered during the pause counts for its leg");
            check(new LiveWalker(new List<LiveWalkLeg>()).Mask(0, 0, 0, 0) == 0, "live walk: no legs, nothing to do");
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
            check(r.Windows.Count == 43 && r.AnsweredCount == 30 && silentNative.Concat(answeredNative).All(LiveSmokePlan.IsNative), "live account: the first run: 43 windows, 33 with an opcode while open, 30 of them asking windows; a native window with a background push is local (" + r.AnsweredCount + ")");
            check(r.LocalCount == 11 && r.NoAnswerCount == 2 && r.AccountedCount == 43, "live account: before Skills and Dungeons are known as login requests: 11 local-only, 2 without an answer, all 43 accounted for (" + r.SummaryLine() + ")");

            // the same run with the rules: Skills and Dungeons were asked at login (119 and 109 seen before the steps), Helper and Item Finder send nothing
            r.Prefetched.Add(119); r.Prefetched.Add(109); r.Prefetched.Add(200);
            check(r.NoAnswerCount == 0 && r.PrefetchedCount == 2 && r.LocalCount == 11 && r.AnsweredCount == 30 && r.NeedsConditionCount == 0 && r.AccountedCount == 43, "live account: 30 answered, 2 prefetched, 11 local-only, none without an answer: " + r.SummaryLine());
            check(r.Warnings().Count == 0 && r.Notes().Count == 0 && r.Windows.All(w => r.StatusOf(w) != LiveWindowStatus.NoAnswer), "live account: and no warning is left");
            check(LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "DungeonsWindow"))) == "prefetched" && LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "ItemFinderWindow"))) == "local" && LiveSmokeReport.StatusName(r.StatusOf(r.Windows.First(w => w.Class == "BankWindow"))) == "answered", "live account: status names of a prefetched, a local-only and an answered window");

            // runs 3 and 4: the same native window got a background push in one run and none in the other; both must read local
            {
                var a = new LiveSmokeReport { LoginOk = true, EnterOk = true }; a.Windows.Add(Win("BattleListWindow", 100)); a.Windows.Add(Win("MinimapWindow"));
                check(a.StatusOf(a.Windows[0]) == LiveWindowStatus.Local && a.StatusOf(a.Windows[1]) == LiveWindowStatus.Local, "live account: a native window is local with or without a background push while open (counts stable between runs)");
            }

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

        // ------------------------------------------------------------------------------------ the new player first minute (O433)
        static LiveHelperView OpenView(int tab = 1, bool hint = true, bool blink = true) => new LiveHelperView { Open = true, Tab = tab, HintDrawn = hint, Hint = hint ? "Set up your helper in one click" : "", BlinkActive = blink };
        static readonly LiveHelperView Shut = new LiveHelperView();

        /// <summary>Runs the step with a script: the toast shows from toastAt, the Helper is open from helperAt (ms after the start), until the screenshot is asked. Returns that time, or -1.</summary>
        static double Drive(LiveNewPlayerStep st, double toastAt, double helperAt, Func<LiveHelperView> shown, int asks = 1, double limit = 60000)
        {
            for (double t = 0; t <= limit; t += 100)
            {
                bool toast = toastAt >= 0 && t >= toastAt;
                bool open = helperAt >= 0 && t >= helperAt;
                var act = st.Update(1000 + t, toast, toast ? asks : 0, open ? shown() : Shut);
                if (act == LiveNewPlayerAction.Screenshot) { st.ShotTaken("helper_onboarding_extended.png"); return t; }
            }
            return -1;
        }

        static LiveNewPlayerResult Fresh() => new LiveNewPlayerResult { Ran = true, LoginOk = true, EnterOk = true };

        static LiveSmokeReport WithNewPlayer(LiveNewPlayerResult n)
        {
            var r = Good();
            var to = r.NewPlayer;
            to.Ran = n.Ran; to.LoginOk = n.LoginOk; to.EnterOk = n.EnterOk; to.LoggedOut = n.LoggedOut; to.ToastSeen = n.ToastSeen; to.HelperAsked = n.HelperAsked;
            to.HelperOpened = n.HelperOpened; to.HintShown = n.HintShown; to.BlinkActive = n.BlinkActive; to.Tab = n.Tab; to.Hint = n.Hint; to.Error = n.Error;
            to.Screenshot = n.Screenshot; to.ToastMs = n.ToastMs; to.HelperMs = n.HelperMs; to.HelperTakenMs = n.HelperTakenMs; to.LongestFrameMs = n.LongestFrameMs; to.LongestFrameAtMs = n.LongestFrameAtMs;
            return r;
        }

        static void NewPlayerChecks(Action<bool, string> check)
        {
            // environment: all three or none
            var e = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p"));
            check(e.Ok && !e.HasNewPlayer, "newplayer env: none of the three variables: no fresh character, no error");
            e = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p", "CHAOS_LIVE_NEW_ACCOUNT", "lcn1x", "CHAOS_LIVE_NEW_PASSWORD", "np-secret", "CHAOS_LIVE_NEW_CHARACTER", "Live Fresh A"));
            check(e.Ok && e.HasNewPlayer && e.NewAccount == "lcn1x" && e.NewPassword == "np-secret" && e.NewCharacter == "Live Fresh A", "newplayer env: the three variables read");
            check(e.Secrets().Contains("np-secret") && e.Secrets().Contains("lcn1x") && e.Secrets().Contains("Live Fresh A"), "newplayer env: the fresh account, password and name are secrets");
            check(!e.Describe().Contains("np-secret") && !e.Describe().Contains("lcn1x") && !e.Describe().Contains("Fresh"), "newplayer env: the log line holds none of them");
            e = LiveSmokeEnv.Read(Env("CHAOS_LIVE_ACCOUNT", "a", "CHAOS_LIVE_PASSWORD", "p", "CHAOS_LIVE_NEW_ACCOUNT", "lcn1x"));
            check(!e.Ok && !e.HasNewPlayer && !string.Join(" ", e.Errors).Contains("lcn1x"), "newplayer env: one or two of the three is an error that holds no value");

            // the good first minute: toast at 2.6 s, the Helper opens 100 ms later, draws, shot
            var res = Fresh();
            var st = new LiveNewPlayerStep(res, 1000);
            check(st.State == LiveNewPlayerStep.Phase.WaitToast && st.Update(1000, false, 0, Shut) == LiveNewPlayerAction.Wait, "newplayer step: starts waiting for the toast");
            double end = Drive(st, 2600, 2700, () => OpenView());
            check(end >= 0 && st.State == LiveNewPlayerStep.Phase.Done && res.ToastSeen && res.HelperAsked && res.HelperOpened && res.Tab == 1 && res.HintShown && res.BlinkActive && res.Hint.Length > 0, "newplayer step: toast, Helper on tab 1, hint and blink recorded");
            check(Math.Abs(res.ToastMs - 2600) < 1 && Math.Abs(res.HelperMs - 2700) < 1, "newplayer step: toast and Helper times from the start of the step");
            check(end >= 2700 + LiveNewPlayerStep.SettleMs - 1 && end < 2700 + LiveNewPlayerStep.SettleMs + 300, "newplayer step: the shot waits for the settle time after the Helper opened (" + end + ")");
            check(st.Update(99999, true, 1, OpenView()) == LiveNewPlayerAction.Done && res.Screenshot == "helper_onboarding_extended.png", "newplayer step: done after the screenshot, the file name kept");
            check(res.Pass && res.Failures().Count == 0, "newplayer result: the good run passes");

            // the Helper was already open when the toast came
            res = Fresh();
            Drive(new LiveNewPlayerStep(res, 1000), 500, 0, () => OpenView());
            check(res.Pass && res.HelperOpened, "newplayer step: a Helper that was open before the toast still passes");

            // no toast: the step waits the limit, still asks for the shot, and fails with the line
            res = Fresh();
            st = new LiveNewPlayerStep(res, 1000);
            end = Drive(st, -1, -1, () => OpenView());
            check(end >= LiveNewPlayerStep.ToastLimitMs - 1 && end < LiveNewPlayerStep.ToastLimitMs + 200 && !res.ToastSeen && st.State == LiveNewPlayerStep.Phase.Done, "newplayer step: no toast ends after the limit with a shot (" + end + ")");
            check(!res.Pass && res.Failures().Count == 1 && res.Failures()[0].StartsWith("newplayer: no welcome toast after 30 s", StringComparison.Ordinal), "newplayer result: no toast is a failure line: " + string.Join("|", res.Failures()));

            // toast but the Helper never opens
            res = Fresh();
            st = new LiveNewPlayerStep(res, 1000);
            end = Drive(st, 2000, -1, () => OpenView());
            check(end >= 2000 + LiveNewPlayerStep.HelperLimitMs - 1 && end < 2000 + LiveNewPlayerStep.HelperLimitMs + 200 && res.ToastSeen && !res.HelperOpened, "newplayer step: a Helper that stays shut ends after its limit (" + end + ")");
            check(!res.Pass && res.Failures().Any(x => x.Contains("Helper did not open by itself")) && res.Tab == -1 && !res.HintShown, "newplayer result: a Helper that did not open is a failure line, no tab or hint recorded");

            // the toast came without openHelper
            res = Fresh();
            Drive(new LiveNewPlayerStep(res, 1000), 1000, -1, () => OpenView(), 0);
            check(res.ToastSeen && !res.HelperAsked && res.Failures().Any(x => x.Contains("without openHelper")), "newplayer result: a toast without openHelper is its own failure line");

            // wrong tab, no hint, no blink: a separate line each
            res = Fresh();
            Drive(new LiveNewPlayerStep(res, 1000), 500, 600, () => OpenView(0, true, true));
            check(res.HelperOpened && res.Tab == 0 && res.Failures().Count == 1 && res.Failures()[0].Contains("tab 0, not on Auto setup"), "newplayer result: the Healing tab is a failure line");
            res = Fresh();
            Drive(new LiveNewPlayerStep(res, 1000), 500, 600, () => OpenView(1, false, true));
            check(res.Failures().Count == 1 && res.Failures()[0].Contains("no hint") && !res.HintShown, "newplayer result: no hint drawn is a failure line");
            res = Fresh();
            Drive(new LiveNewPlayerStep(res, 1000), 500, 600, () => OpenView(1, true, false));
            check(res.Failures().Count == 1 && res.Failures()[0].Contains("does not blink"), "newplayer result: no blink is a failure line");

            // a Helper that opened and was shut again before the shot does not count as open
            res = Fresh();
            st = new LiveNewPlayerStep(res, 0);
            st.Update(0, true, 1, Shut); st.Update(100, true, 1, OpenView());
            var act = LiveNewPlayerAction.Wait;
            for (double t = 200; t <= 3000 && act != LiveNewPlayerAction.Screenshot; t += 100) act = st.Update(t, true, 1, Shut);
            check(act == LiveNewPlayerAction.Screenshot && !res.HelperOpened && res.Tab == -1, "newplayer step: a Helper shut again before the shot is not open");

            // the toast seen is kept when it leaves the screen
            res = Fresh();
            st = new LiveNewPlayerStep(res, 0);
            st.Update(0, true, 1, Shut); st.Update(100, false, 1, OpenView());
            check(res.ToastSeen && res.HelperAsked && res.HelperOpened && st.State == LiveNewPlayerStep.Phase.Settle, "newplayer step: the toast is latched when it leaves the screen");

            // login and entry faults of the fresh character
            res = new LiveNewPlayerResult { Ran = true, Error = "login: Account name or password is not correct." };
            check(!res.Pass && res.Failures().Count == 1 && res.Failures()[0] == "newplayer: login: Account name or password is not correct.", "newplayer result: a login fault is one failure line: " + string.Join("|", res.Failures()));
            res = new LiveNewPlayerResult { Ran = true, LoginOk = true };
            check(!res.Pass && res.Failures().Any(x => x.Contains("did not get into the game")), "newplayer result: not entering the game without a message still fails");
            res = new LiveNewPlayerResult();
            check(res.Pass && res.Failures().Count == 0 && res.ToJson(null) == "{\"ran\":false}", "newplayer result: a run without a fresh character has no failure and an empty block");

            // the report: the failure lines join the gate rule, the other checks stay as they were
            var good = new LiveNewPlayerResult { Ran = true, LoginOk = true, EnterOk = true, LoggedOut = true, ToastSeen = true, HelperAsked = true, HelperOpened = true, Tab = 1, HintShown = true, Hint = "Set up your helper in one click", BlinkActive = true, ToastMs = 2600, HelperMs = 2700, Screenshot = "helper_onboarding_extended.png" };
            var rep = WithNewPlayer(good);
            check(rep.Pass && rep.Failures().Count == 0 && rep.SummaryLine().Contains("0 layout errors, newplayer ok, pass"), "newplayer report: a good first minute passes and shows on the summary line: " + rep.SummaryLine());
            rep = WithNewPlayer(new LiveNewPlayerResult { Ran = true, LoginOk = true, EnterOk = true, LoggedOut = true, ToastSeen = false });
            check(!rep.Pass && rep.Failures().Any(x => x.StartsWith("newplayer: no welcome toast", StringComparison.Ordinal)) && rep.SummaryLine().Contains("newplayer FAIL, FAIL"), "newplayer report: a missing toast fails the run: " + rep.SummaryLine());
            rep = WithNewPlayer(good);
            rep.StepsConfirmed = 0;
            check(!rep.Pass && !rep.Failures().Any(x => x.StartsWith("newplayer", StringComparison.Ordinal)), "newplayer report: a good first minute does not hide a failed walk");
            rep = WithNewPlayer(good); rep.NewPlayer.LoggedOut = false;
            check(rep.Pass && rep.Warnings().Any(x => x.StartsWith("newplayer: no clean logout", StringComparison.Ordinal)), "newplayer report: no clean logout of the fresh character is a warning, not a failure");
            check(Good().Pass && !Good().SummaryLine().Contains("newplayer") && Good().Warnings().Count == 0, "newplayer report: a run without a fresh character reads as before");

            // the json block
            rep = WithNewPlayer(good);
            var pj = Json.TryParse(rep.ToJson(null));
            var nb = Json.Get(pj, "newplayer");
            check(nb != null && Json.Bool(nb, "ran") && Json.Bool(nb, "pass") && Json.Bool(nb, "toastSeen") && Json.Bool(nb, "openHelper") && Json.Bool(nb, "helperOpened") && Json.Int(nb, "tab") == 1 && Json.Bool(nb, "autoSetupTab"), "newplayer json: ran, pass, toast, openHelper, Helper opened on tab 1");
            check(Json.Bool(nb, "hintShown") && Json.Text(nb, "hint") == "Set up your helper in one click" && Json.Bool(nb, "blinkActive") && Json.Text(nb, "screenshot") == "helper_onboarding_extended.png" && Json.Int(nb, "toastMs") == 2600 && Json.Bool(nb, "loggedOut"), "newplayer json: hint, blink, screenshot name, times");
            check(Json.Bool(pj, "pass") && Json.Bool(Json.Get(pj, "login"), "ok"), "newplayer json: the normal login and pass stay at their places");
            pj = Json.TryParse(Good().ToJson(null));
            check(!Json.Bool(Json.Get(pj, "newplayer"), "ran"), "newplayer json: no fresh character gives {\"ran\":false}");
            rep = WithNewPlayer(new LiveNewPlayerResult { Ran = true, LoginOk = true, EnterOk = true, ToastSeen = false, Error = "boom with np-secret and Live Fresh A" });
            string text = rep.ToJson(new[] { "np-secret", "lcn1x", "Live Fresh A" });
            pj = Json.TryParse(text);
            check(pj != null && !text.Contains("np-secret") && !text.Contains("Live Fresh A") && text.Contains("<removed>") && !Json.Bool(pj, "pass") && !Json.Bool(Json.Get(pj, "newplayer"), "pass"), "newplayer json: a failing block says why and holds no secret");
            check(!text.Any(c => c > 0x7e), "newplayer json: ASCII only");
        }


        // ============================================================================================================================ the first fight (O433, "New player first fight")
        // A simulated game: the temple floor with the stair the client calls not walkable, the cave below with Rats, steps one tile each 250 ms, a kill after some seconds of attack, a body, a container
        // that opens. The step runs against it the way the player and the live check run it, so the route, the stair step, the fight, the loot and every end state are checked without a screen or a server.
        sealed class FightSim
        {
            public Pos Player = new Pos(32369, 32241, 7);
            public bool SpellsLoaded = true, Dead, BlockRoute, StairWorks = true, RatsInCave = true, NeverDies, GivesExperience = true, OpensBody = true, BodyHasItems = true, WindowOpensByItself = true, StaysAtTemple = true;
            public int Slots = 5, InjectRefusals;
            public double KillAfterMs = 3000, SpawnAtMs, StepMs = 250;
            public long Experience = 4200;
            public int ExpTexts, ContainerOpens, Moves, Refused, Attacks, Chases, UseCalls, Walks, Steps, ShowBodies;
            public bool HelperOn, Rotation, ContainersWindow, AutoWalk, StuckWalk;
            public double Now;
            public readonly List<LiveFightMonster> Rats = new List<LiveFightMonster>();
            readonly Dictionary<Pos, int> bodies = new Dictionary<Pos, int>();
            readonly List<LiveFightContainer> containers = new List<LiveFightContainer>();
            List<Pos> walk = new List<Pos>();
            int walkAt;
            double nextStep = -1, stairAt = -1, attackStart = -1;
            uint target;
            bool arrived;
            public static readonly Pos Landing = new Pos(32390, 32225, 8);

            public bool Walkable(Pos p)
            {
                if (p.Z == 7) return p.X >= 32355 && p.X <= 32400 && p.Y >= 32205 && p.Y <= 32250 && !p.Equals(LiveFirstFightStep.Stair) && !(BlockRoute && p.Y == 32230);
                if (p.Z == 8) return p.X >= 32340 && p.X <= 32410 && p.Y >= 32195 && p.Y <= 32240;
                return false;
            }

            public void Advance(double now)
            {
                Now = now;
                if (stairAt >= 0 && now >= stairAt) { stairAt = -1; Player = Landing; Moves++; }
                if (AutoWalk && !StuckWalk && nextStep >= 0 && now >= nextStep)
                {
                    if (InjectRefusals > 0 && walkAt == 2) { InjectRefusals--; Refused++; AutoWalk = false; nextStep = -1; }
                    else
                    {
                        Player = walk[++walkAt]; Moves++;
                        if (walkAt >= walk.Count - 1) { AutoWalk = false; nextStep = -1; }
                        else nextStep = now + StepMs;
                    }
                }
                if (Player.Z == 8 && !arrived)
                {
                    arrived = true; SpawnAtMs = now;
                    if (RatsInCave)
                    {
                        Rats.Add(new LiveFightMonster { Id = 101, Name = "Cave Rat [5]", Pos = new Pos(32392, 32228, 8) });
                        Rats.Add(new LiveFightMonster { Id = 102, Name = "Rat [2]", Pos = new Pos(32387, 32230, 8) });
                    }
                }
                if (target != 0 && attackStart >= 0 && !NeverDies && now - attackStart >= KillAfterMs)
                {
                    var rat = Rats.Find(m => m.Id == target);
                    if (rat != null)
                    {
                        Rats.Remove(rat);
                        ExpTexts++;
                        if (GivesExperience) Experience += 390;
                        bodies[rat.Pos] = 5964;
                    }
                    target = 0;
                }
            }

            public LiveFightView View()
            {
                var v = new LiveFightView
                {
                    Player = Player, Dead = Dead, Health = 150, MaxHealth = 185, SpellsLoaded = SpellsLoaded, AutoWalkActive = AutoWalk, Moves = Moves, Refused = Refused, ExpTexts = ExpTexts, Experience = Experience,
                    ContainerOpens = ContainerOpens, ContainersWindowOpen = ContainersWindow, Walkable = Walkable,
                };
                foreach (var m in Rats) if (m.Pos.Z == Player.Z) v.Monsters.Add(m);
                v.LootNear = at =>
                {
                    for (int ring = 0; ring <= 1; ring++)
                        foreach (var kv in bodies)
                            if (PathFinder.Cheb(kv.Key, at) == ring) return new LiveFightLoot { Tile = kv.Key, Stack = 1, ItemId = kv.Value };
                    return null;
                };
                foreach (var c in containers) v.Containers.Add(c);
                return v;
            }

            public void Do(LiveFightAction act, LiveFirstFightStep st)
            {
                switch (act)
                {
                    case LiveFightAction.PressAutoSetup: st.AutoSetupDone(Slots, Slots > 0 ? "Rotation set: Kindling Spark" : ""); break;
                    case LiveFightAction.HelperOn: HelperOn = true; Rotation = true; st.HelperSet(true, true); break;
                    case LiveFightAction.Walk:
                        {
                            Walks++;
                            var path = PathFinder.Find(Player, st.WalkGoal, Walkable, st.WalkRange);
                            if (path == null) { st.WalkStarted(-1); break; }
                            if (path.Count == 0) { st.WalkStarted(0); break; }
                            walk = PathFinder.Tiles(Player, path); walkAt = 0; AutoWalk = true; nextStep = Now + StepMs;
                            if (StuckWalk) nextStep = -1;
                            st.WalkStarted(path.Count);
                            break;
                        }
                    case LiveFightAction.Step:
                        {
                            Steps++;
                            var to = WalkDirs.Step(Player, st.StepDir);
                            if (to.Equals(LiveFirstFightStep.Stair) && StairWorks) stairAt = Now + 300;
                            else if (Walkable(to)) { Player = to; Moves++; }
                            else Refused++;
                            break;
                        }
                    case LiveFightAction.ChaseOn: Chases++; break;
                    case LiveFightAction.Attack:
                        Attacks++;
                        if (target != st.AttackId) { target = st.AttackId; attackStart = Now; }
                        break;
                    case LiveFightAction.UseLoot:
                        UseCalls++;
                        if (OpensBody && PathFinder.Cheb(Player, st.Loot.Tile) <= 1)   // the server refuses a use from afar
                        {
                            ContainerOpens++;
                            containers.Clear();
                            containers.Add(new LiveFightContainer { Id = 0, ItemId = st.Loot.ItemId, Name = "dead rat", Items = BodyHasItems ? 2 : 0 });
                            if (WindowOpensByItself) ContainersWindow = true;
                        }
                        break;
                    case LiveFightAction.OpenContainers: ContainersWindow = true; break;
                    case LiveFightAction.ShowBody: ShowBodies++; break;
                    case LiveFightAction.Screenshot: st.ShotTaken("first_fight_extended.png"); break;
                }
            }
        }

        /// <summary>Runs the step against the sim from `from` ms until the picture is taken or `limit` ms went by; returns the clock at the end, -1 when it never finished.</summary>
        static double RunFight(LiveFirstFightStep st, FightSim sim, double from = 10000, double limit = 240000)
        {
            for (double t = from; t < from + limit; t += 50)
            {
                sim.Advance(t);
                var act = st.Update(t, sim.View());
                sim.Do(act, st);
                if (st.State == LiveFirstFightStep.Phase.Done) return t;
            }
            return -1;
        }

        static void FirstFightChecks(Action<bool, string> check)
        {
            // the route data: the temple spot, the stair, the way and the grounds as the live check walks them
            check(LiveFirstFightStep.Route.Length == 7 && LiveFirstFightStep.Route.All(p => p.Z == 7) && LiveFirstFightStep.Grounds.All(p => p.Z == 8) && LiveFirstFightStep.Stair.Equals(new Pos(32390, 32225, 7)) && LiveFirstFightStep.TempleSpot.Z == 7, "first fight: the route, the stair and the grounds are floor 7 and floor 8 of the live check's data");
            check(LiveFirstFightStep.IsRat("Rat [4]") && LiveFirstFightStep.IsRat("Cave Rat") && LiveFirstFightStep.IsRat("rat") && !LiveFirstFightStep.IsRat("Pig [2]") && !LiveFirstFightStep.IsRat("Rat King"), "first fight: a Rat or a Cave Rat by name, with or without the level tag");
            check(LiveFirstFightStep.BaseName("Cave Rat [5]") == "Cave Rat" && LiveFirstFightStep.BaseName("Cave Rat") == "Cave Rat" && LiveFirstFightStep.BaseName(null) == "", "first fight: the level tag is cut from a name");

            // ---- the good run
            var sim = new FightSim();
            var res = new LiveFirstFightResult();
            var st = new LiveFirstFightStep(res, 10000);
            double end = RunFight(st, sim);
            check(end > 0 && st.State == LiveFirstFightStep.Phase.Done && res.Ran && !res.Skipped, "first fight: the good run ends with the picture taken (" + end + ")");
            check(res.AutoSetupPressed && res.AutoSetupSlots == 5 && res.HelperOn && res.RotationOn && sim.HelperOn && sim.Rotation, "first fight: Auto setup pressed with 5 slots, the Helper and the rotation on");
            check(res.ReachedCave && res.Hops >= 2 && res.Hops <= 8 && sim.Player.Z == 8 && sim.Steps >= 1 && sim.Steps <= 3, "first fight: the walk reached the cave on floor 8 by the stair step (" + res.Hops + " hops, " + sim.Steps + " step(s))");
            check(res.WalkPlanned > 20 && res.WalkSent >= res.WalkPlanned && res.WalkConfirmed >= res.WalkPlanned - 3 && res.WalkRefused == 0, "first fight: the walk counts: planned " + res.WalkPlanned + ", sent " + res.WalkSent + ", confirmed " + res.WalkConfirmed + ", refused " + res.WalkRefused);
            check(res.HopLog.Count == res.Hops && res.HopLog.All(h => h.Contains("arrived")) && res.HopLog[0].StartsWith("route 1 to 32366,32235,7", StringComparison.Ordinal), "first fight: one log line per hop, each arrived: " + string.Join(" | ", res.HopLog.Take(2)));
            check(res.RatInReach && res.Kills == 1 && res.Monster.Length > 0 && sim.Chases == 1 && sim.Attacks >= 1, "first fight: chase on once, a Rat attacked and killed (" + res.Monster + ", " + sim.Attacks + " attack order(s))");
            check(res.ExpBefore == 4200 && res.ExpAfter == 4590 && res.ExpTexts == 1, "first fight: the experience before and after, one text (" + res.ExpBefore + " to " + res.ExpAfter + ")");
            check(res.LootTried && res.LootOpened && res.LootItems == 2 && res.LootName == "dead rat" && res.LootWindowOpen && sim.UseCalls == 1, "first fight: the body opened in the container window with its 2 items");
            check(sim.ShowBodies == 1, "first fight: with the body open the picture is prepared once (the Helper window put away, the container window in front)");
            check(res.Screenshot == "first_fight_extended.png" && res.Ms > 10000 && res.Ms < LiveFirstFightStep.LimitMs, "first fight: the picture is named and the part took " + (int)res.Ms + " ms");
            check(res.Pass && res.Failures().Count == 0 && res.Warnings().Count == 0, "first fight: a good run passes with no failure and no warning: " + string.Join("|", res.Failures().Concat(res.Warnings())));
            check(st.Update(end + 1000, sim.View()) == LiveFightAction.Done, "first fight: done stays done");

            // ---- the action order: Auto setup first, then the Helper, then the walk (no step before the Helper is on)
            sim = new FightSim();
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            var order = new List<LiveFightAction>();
            for (double t = 0; t < 30000 && order.Count < 6; t += 50)
            {
                sim.Advance(t);
                var act = st.Update(t, sim.View());
                if (act != LiveFightAction.None) order.Add(act);
                sim.Do(act, st);
            }
            check(order.Count >= 3 && order[0] == LiveFightAction.PressAutoSetup && order[1] == LiveFightAction.HelperOn && order[2] == LiveFightAction.Walk, "first fight: the order is Auto setup, Helper on, walk: " + string.Join(",", order));

            // ---- a spell list that is late: the step waits for it, then goes on
            sim = new FightSim { SpellsLoaded = false };
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            for (double t = 0; t < 4000; t += 50) { sim.Advance(t); sim.Do(st.Update(t, sim.View()), st); }
            check(!res.AutoSetupPressed && res.Error.Length == 0 && st.State == LiveFirstFightStep.Phase.Spells, "first fight: no Auto setup before the spell list is there");
            sim.SpellsLoaded = true;
            end = RunFight(st, sim, 4000);
            check(end > 0 && res.Pass && res.Kills == 1, "first fight: the spell list arrives late, the run goes on and passes");

            // ---- the spell list never comes: an error line, a picture, no walk
            sim = new FightSim { SpellsLoaded = false };
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            end = RunFight(st, sim, 0);
            check(end >= LiveFirstFightStep.SpellsWaitMs && end < LiveFirstFightStep.SpellsWaitMs + 2000 && res.Error.Contains("spell list never arrived") && sim.Walks == 0 && !res.Pass && res.Failures().Any(x => x.StartsWith("firstfight: the spell list", StringComparison.Ordinal)), "first fight: no spell list in 10 s is a failure, nothing is walked");

            // ---- Auto setup that fills nothing, a Helper that stays off
            sim = new FightSim { Slots = 0 };
            res = new LiveFirstFightResult();
            RunFight(new LiveFirstFightStep(res, 10000), sim);
            check(!res.Pass && res.Failures().Any(x => x.StartsWith("firstfight: Auto setup filled no spell slot", StringComparison.Ordinal)), "first fight: an Auto setup with no slot is a failure");
            res = new LiveFirstFightResult { Ran = true, AutoSetupPressed = true, AutoSetupSlots = 3, HelperOn = false };
            check(res.Failures().Any(x => x.Contains("Helper did not turn on")), "first fight: a Helper that did not turn on is a failure");

            // ---- not at the temple: nothing to walk, a skip with the place
            sim = new FightSim { Player = new Pos(32500, 32100, 7) };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end > 0 && res.Skipped && res.SkipReason.Contains("not at the temple") && res.Pass && res.Warnings().Any(x => x.StartsWith("firstfight: skipped:", StringComparison.Ordinal)) && res.AutoSetupPressed, "first fight: away from the temple the run skips with the place (Auto setup was still pressed)");

            // ---- a wall across the way: the walk fails, the part skips with the reason, no failure
            sim = new FightSim { BlockRoute = true };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end > 0 && res.Skipped && res.SkipReason.StartsWith("the way to the cave failed", StringComparison.Ordinal) && !res.ReachedCave && res.Pass && res.HopLog.Any(h => h.Contains("failed")), "first fight: a blocked way skips with the hop that failed: " + res.SkipReason);
            check(res.Kills == 0 && !res.RatInReach && sim.Attacks == 0, "first fight: a skipped run attacks nothing");

            // ---- the stair that does not take the character down: three steps, then a skip
            sim = new FightSim { StairWorks = false };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end > 0 && res.Skipped && res.SkipReason.Contains("did not change the floor") && sim.Steps == LiveFirstFightStep.StepAttempts && res.Pass, "first fight: a stair step that does not change the floor is tried " + LiveFirstFightStep.StepAttempts + " times, then a skip: " + res.SkipReason);

            // ---- no Rat in the cave: the landing waits, the grounds are visited, then a skip
            sim = new FightSim { RatsInCave = false };
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            end = RunFight(st, sim, 0);
            check(end > 0 && res.Skipped && res.ReachedCave && res.SkipReason.StartsWith("no Rat in view", StringComparison.Ordinal) && res.Pass && !res.RatInReach && res.Kills == 0, "first fight: no Rat in view skips with the reason, no failure: " + res.SkipReason);
            check(res.Hops >= 7 && sim.Walks >= 8, "first fight: the known grounds were visited before the skip (" + res.Hops + " hops)");

            // ---- a Rat that comes late (while the character waits at the landing): it is fought
            sim = new FightSim { RatsInCave = false };
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            bool added = false;
            for (double t = 0; t < 200000 && st.State != LiveFirstFightStep.Phase.Done; t += 50)
            {
                sim.Advance(t);
                if (!added && sim.Player.Z == 8 && sim.Now - sim.SpawnAtMs > 3000) { added = true; sim.Rats.Add(new LiveFightMonster { Id = 201, Name = "Cave Rat [5]", Pos = new Pos(32392, 32222, 8) }); }
                sim.Do(st.Update(t, sim.View()), st);
            }
            check(added && res.Kills == 1 && res.Pass && res.Hops <= 8, "first fight: a Rat that wanders in during the landing wait is fought and killed without a walk to the grounds");

            // ---- a Rat in reach that never dies: the limit, a failure
            sim = new FightSim { NeverDies = true };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end >= LiveFirstFightStep.LimitMs && end < LiveFirstFightStep.LimitMs + 2000 && res.RatInReach && res.Kills == 0 && !res.Skipped, "first fight: the time limit ends a fight that never ends (" + end + ")");
            check(!res.Pass && res.Failures().Count == 1 && res.Failures()[0].StartsWith("firstfight: no kill in 120 s with a ", StringComparison.Ordinal) && sim.Attacks >= 40, "first fight: no kill with a Rat in reach is a failure (the attack order repeated " + sim.Attacks + " times): " + string.Join("|", res.Failures()));

            // ---- the time limit while still walking (a slow walk): a skip, not a failure
            sim = new FightSim { StepMs = 3000 };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end > 0 && res.Skipped && res.SkipReason.StartsWith("the cave was not reached in 120 s", StringComparison.Ordinal) && !res.ReachedCave && res.Pass, "first fight: a walk too slow for the time limit skips at the limit: " + res.SkipReason);

            // ---- a walk that never moves: every hop gives up after its tries, a skip with the hop
            sim = new FightSim();
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            for (double t = 0; t < 200000 && st.State != LiveFirstFightStep.Phase.Done; t += 50)
            {
                sim.Advance(t);
                var act = st.Update(t, sim.View());
                if (act == LiveFightAction.Walk) st.WalkStarted(5);   // a walk that never moves the character
                else sim.Do(act, st);
            }
            check(res.Skipped && res.SkipReason.StartsWith("the way to the cave failed: no way to 32366,32235,7", StringComparison.Ordinal) && res.Pass, "first fight: a walk that never moves gives up after " + LiveFirstFightStep.HopAttempts + " tries: " + res.SkipReason);

            // ---- the character dies
            sim = new FightSim { KillAfterMs = 30000 };
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            for (double t = 0; t < 120000 && st.State != LiveFirstFightStep.Phase.Done; t += 50)
            {
                sim.Advance(t);
                if (sim.Player.Z == 8 && t > 25000) sim.Dead = true;
                sim.Do(st.Update(t, sim.View()), st);
            }
            check(res.Died && !res.Pass && res.Failures().Any(x => x.Contains("died")) && st.State == LiveFirstFightStep.Phase.Done && res.Screenshot.Length > 0, "first fight: a death is a failure line, the picture is still taken");

            // ---- a kill with no experience in 0xA0, and none in the text
            sim = new FightSim { GivesExperience = false };
            res = new LiveFirstFightResult();
            RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(res.Kills == 1 && !res.Pass && res.Failures().Any(x => x.Contains("no experience in 0xA0 (4200 to 4200)")), "first fight: a kill whose experience did not go up in 0xA0 is a failure");
            res = new LiveFirstFightResult { Ran = true, Kills = 1, ExpBefore = 10, ExpAfter = 400, ExpTexts = 0, AutoSetupPressed = true, AutoSetupSlots = 1, HelperOn = true };
            check(res.Failures().Count == 1 && res.Failures()[0].Contains("no experience text"), "first fight: a kill with no experience text is a failure");

            // ---- a body that never opens: a warning, the run still passes
            sim = new FightSim { OpensBody = false };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(sim.ShowBodies == 0, "first fight: no open body, the Helper window stays for the picture");
            check(end > 0 && res.Kills == 1 && res.LootTried && !res.LootOpened && res.Pass && res.Warnings().Any(x => x.Contains("body did not open")) && sim.UseCalls == LiveFirstFightStep.LootTries, "first fight: a body that never opens is a warning after " + LiveFirstFightStep.LootTries + " tries: " + string.Join("|", res.Warnings()));

            // ---- a walk to the body that never ends: the part's time limit ends it, a warning
            sim = new FightSim();
            res = new LiveFirstFightResult();
            st = new LiveFirstFightStep(res, 0);
            double killedAt = -1;
            for (double t = 0; t < 200000 && st.State != LiveFirstFightStep.Phase.Done; t += 50)
            {
                sim.Advance(t);
                if (res.Kills > 0 && killedAt < 0) { killedAt = t; sim.StuckWalk = true; }
                sim.Do(st.Update(t, sim.View()), st);
                if (st.State == LiveFirstFightStep.Phase.Done) end = t;
            }
            check(killedAt > 0 && res.Kills == 1 && !res.LootOpened && res.Pass && st.State == LiveFirstFightStep.Phase.Done && end <= LiveFirstFightStep.LimitMs + 1000 && res.Warnings().Any(x => x.Contains("body did not open")), "first fight: a walk to the body that never ends is cut at the part's time limit (" + (int)end + " ms), a warning");

            // ---- an empty body is fine (the coins go to the bank)
            sim = new FightSim { BodyHasItems = false };
            res = new LiveFirstFightResult();
            RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(res.LootOpened && res.LootItems == 0 && res.Pass && res.Warnings().Count == 0, "first fight: an empty body that opened passes with no warning");

            // ---- the Containers window that does not open by itself: the step opens it like a player
            sim = new FightSim { WindowOpensByItself = false };
            res = new LiveFirstFightResult();
            RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(res.LootOpened && res.LootWindowOpen && sim.ContainersWindow && res.Pass, "first fight: a Containers window that stayed shut is opened by the step, the body shows in it");

            // ---- refused steps on tiles the client thought free: a warning with the count, the walk goes on
            sim = new FightSim { InjectRefusals = 1 };
            res = new LiveFirstFightResult();
            end = RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            check(end > 0 && res.Pass && res.WalkRefused == 1 && res.Replans >= 1 && res.Kills == 1 && res.Warnings().Any(x => x.StartsWith("firstfight walk: 1 steps refused", StringComparison.Ordinal)), "first fight: a refused step is a warning, the hop is planned again and the run passes: " + string.Join("|", res.Warnings()));
            check(res.HopLog.Any(h => h.Contains("1 refused")), "first fight: the hop log says where the refusal was");

            // ---- the loot rule: the kill's own tile first, the top of a stack, a body of an earlier fight beside it is not taken
            var w = new World(null);
            void Put(Pos p, params Thing[] things) { var tl = w.GetOrMake(p); foreach (var th in things) tl.Things.Add(th); }
            Thing Box(int id) => new Thing { Item = new Item { Id = id, Type = new ThingType { Id = id, Container = true } } };
            Thing Plain(int id) => new Thing { Item = new Item { Id = id, Type = new ThingType { Id = id } } };
            var kill = new Pos(32392, 32228, 8);
            Put(kill.Offset(-1, 0), Box(7001));
            check(LiveFirstFightStep.LootOn(w, kill)?.ItemId == 7001 && LiveFirstFightStep.LootOn(w, kill).Tile.Equals(kill.Offset(-1, 0)), "loot rule: no body on the tile, the one beside it is taken");
            Put(kill, Plain(100), Box(5964), Plain(101));
            var l = LiveFirstFightStep.LootOn(w, kill);
            check(l != null && l.ItemId == 5964 && l.Tile.Equals(kill) && l.Stack == 1, "loot rule: the kill's own tile first, the stack position of the container item");
            Put(kill, Box(5965));
            check(LiveFirstFightStep.LootOn(w, kill).ItemId == 5965 && LiveFirstFightStep.LootOn(w, kill).Stack == 3, "loot rule: the top of the stack first");
            check(LiveFirstFightStep.LootOn(w, new Pos(32300, 32100, 8)) == null, "loot rule: nothing near is null");
            var tc = w.GetOrMake(new Pos(32300, 32100, 8)); tc.Things.Add(new Thing { Creature = new Creature { Id = 5 } }); tc.Things.Add(Plain(9));
            check(LiveFirstFightStep.LootOn(w, new Pos(32300, 32100, 8)) == null, "loot rule: a creature or a plain item is no container");

            // ---- the json block
            sim = new FightSim();
            res = new LiveFirstFightResult();
            RunFight(new LiveFirstFightStep(res, 0), sim, 0);
            var json = Json.TryParse(res.ToJson(null));
            check(json != null && Json.Bool(json, "ran") && Json.Bool(json, "pass") && !Json.Bool(json, "skipped") && Json.Text(json, "skipReason") == "" && Json.Text(json, "error") == "", "first fight json: ran, pass, not skipped");
            var asj = Json.Get(json, "autoSetup");
            check(Json.Bool(asj, "pressed") && Json.Int(asj, "slots") == 5 && Json.Bool(json, "helperOn") && Json.Bool(json, "rotationOn"), "first fight json: Auto setup slots, Helper on");
            var wj = Json.Get(json, "walk");
            check(Json.Int(wj, "hops") == res.Hops && Json.Int(wj, "planned") == res.WalkPlanned && Json.Int(wj, "sent") == res.WalkSent && Json.Int(wj, "confirmed") == res.WalkConfirmed && Json.Int(wj, "refused") == 0 && Json.Bool(wj, "reachedCave"), "first fight json: the walk counts");
            var xj = Json.Get(json, "experience");
            check(Json.Int(json, "kills") == 1 && Json.Text(json, "monster") == res.Monster && Json.Int(xj, "before") == 4200 && Json.Int(xj, "after") == 4590 && Json.Int(xj, "texts") == 1, "first fight json: kills, experience before and after");
            var lj = Json.Get(json, "loot");
            check(Json.Bool(lj, "opened") && Json.Int(lj, "items") == 2 && Json.Text(lj, "name") == "dead rat" && Json.Bool(lj, "windowOpen") && Json.Text(json, "screenshot") == "first_fight_extended.png" && Json.Int(json, "ms") > 0 && Json.List(json, "hopLog").Count == res.Hops, "first fight json: the body, the picture, the time and the hop log");
            check(!res.ToJson(null).Any(c => c > 0x7e), "first fight json: ASCII only");
            check(Json.TryParse(new LiveFirstFightResult().ToJson(null)) != null && !Json.Bool(Json.TryParse(new LiveFirstFightResult().ToJson(null)), "ran"), "first fight json: not run is {\"ran\":false}");
            var sk = new LiveFirstFightResult { Ran = true, Skipped = true, SkipReason = "no Rat in view at the landing with fresh-secret" };
            string skJson = sk.ToJson(new[] { "fresh-secret" });
            check(Json.Bool(Json.TryParse(skJson), "skipped") && Json.Bool(Json.TryParse(skJson), "pass") && !skJson.Contains("fresh-secret") && skJson.Contains("<removed>"), "first fight json: a skip says why and passes, a secret is cut");

            // ---- inside the report: failure and warning lines, the summary line, the json key, the logout note
            var rep = Good();
            rep.FirstFight.Ran = true; rep.FirstFight.Skipped = false; rep.FirstFight.AutoSetupPressed = true; rep.FirstFight.AutoSetupSlots = 2; rep.FirstFight.HelperOn = true; rep.FirstFight.RatInReach = true;
            check(!rep.Pass && rep.Failures().Any(x => x.StartsWith("firstfight: no kill in 120 s", StringComparison.Ordinal)) && rep.SummaryLine().Contains("firstfight FAIL"), "first fight report: a failure line fails the run and shows in the summary line");
            rep = Good();
            rep.FirstFight.Ran = true; rep.FirstFight.Skipped = true; rep.FirstFight.SkipReason = "no Rat in view";
            check(rep.Pass && rep.Warnings().Any(x => x.StartsWith("firstfight: skipped: no Rat in view", StringComparison.Ordinal)) && rep.SummaryLine().Contains("firstfight skipped"), "first fight report: a skip is a warning, the run passes");
            rep = Good();
            check(!rep.SummaryLine().Contains("firstfight") && rep.Warnings().Count == 0 && !Json.Bool(Json.Get(Json.TryParse(rep.ToJson(null)), "firstfight"), "ran"), "first fight report: no fresh character, nothing about the first fight and the json says ran false");
            rep = Good();
            rep.NewPlayer.Ran = true; rep.NewPlayer.LoginOk = true; rep.NewPlayer.EnterOk = true; rep.NewPlayer.ToastSeen = true; rep.NewPlayer.HelperAsked = true; rep.NewPlayer.HelperOpened = true; rep.NewPlayer.Tab = 1; rep.NewPlayer.HintShown = true; rep.NewPlayer.BlinkActive = true; rep.NewPlayer.LoggedOut = false;
            check(rep.Warnings().Any(x => x.StartsWith("newplayer: no clean logout", StringComparison.Ordinal)), "first fight report: a fresh character that did not log out is a warning when it did not fight");
            rep.FirstFight.Ran = true; rep.FirstFight.RatInReach = true; rep.FirstFight.Kills = 1; rep.FirstFight.ExpBefore = 1; rep.FirstFight.ExpAfter = 5; rep.FirstFight.ExpTexts = 1; rep.FirstFight.AutoSetupPressed = true; rep.FirstFight.AutoSetupSlots = 1; rep.FirstFight.HelperOn = true; rep.FirstFight.LootOpened = true; rep.FirstFight.LootWindowOpen = true;
            check(!rep.Warnings().Any(x => x.StartsWith("newplayer: no clean logout", StringComparison.Ordinal)) && rep.Notes().Any(x => x.Contains("refuses a logout")) && rep.Pass, "first fight report: after a fight the dropped connection is a note, the server refuses a logout in the minute after a fight");
            var jr = Json.TryParse(rep.ToJson(null));
            check(Json.Bool(Json.Get(jr, "firstfight"), "ran") && Json.Int(Json.Get(jr, "firstfight"), "kills") == 1 && Json.Bool(jr, "pass"), "first fight report: the json holds the firstfight block next to the newplayer block");
            rep.FirstFight.Error = "the session closed during the first minute";
            check(!rep.Pass && rep.Failures().Any(x => x == "firstfight: the session closed during the first minute"), "first fight report: an error of the part is its own failure line");

            // ---- the new player step records the frame gaps and when the Helper took the request (the 22 s stall of the first CI run)
            var np = Fresh();
            var step = new LiveNewPlayerStep(np, 1000);
            step.Update(1000, false, 0, Shut);
            step.Update(1100, false, 0, Shut);
            step.Update(3400, true, 1, new LiveHelperView { TakenMs = -1 });
            step.Update(25400, true, 1, new LiveHelperView { Open = true, Tab = 1, HintDrawn = true, Hint = "h", BlinkActive = true, TakenMs = 3450 });
            check(Math.Abs(np.LongestFrameMs - 22000) < 1 && Math.Abs(np.LongestFrameAtMs - 2400) < 1, "new player step: the longest frame gap is 22 s and it began 2.4 s after the start (" + np.LongestFrameMs + " at " + np.LongestFrameAtMs + ")");
            check(Math.Abs(np.HelperTakenMs - 2450) < 1 && Math.Abs(np.HelperMs - 24400) < 1 && np.ToastSeen && np.HelperOpened, "new player step: the Helper took the request at 2.4 s and was seen open at 24.4 s: a stall, not a window that stayed shut");
            check(np.Warnings().Count == 1 && np.Warnings()[0].Contains("one frame took 22.0 s, 2.4 s after") && WithNewPlayer(np).Warnings().Any(x => x.StartsWith("newplayer: one frame took", StringComparison.Ordinal)) && !WithNewPlayer(np).Failures().Any(x => x.Contains("frame")), "new player step: a frame of seconds is a warning, never a failure");
            check(Fresh().Warnings().Count == 0, "new player step: normal frames give no warning");
            var npj = Json.TryParse(WithNewPlayer(np).ToJson(null));
            check(Json.Int(Json.Get(npj, "newplayer"), "longestFrameMs") == 22000 && Json.Int(Json.Get(npj, "newplayer"), "helperTakenMs") == 2450 && Json.Int(Json.Get(npj, "newplayer"), "longestFrameAtMs") == 2400, "new player json: helperTakenMs, longestFrameMs and longestFrameAtMs");
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
            f = Good(); f.StepsPlanned = 12; f.StepsSent = 11; f.StepsConfirmed = 10; f.StepsCancelled = 1;
            f.Legs = new List<LiveWalkResult> { new LiveWalkResult { Name = "north", Wanted = 2, Sent = 2, Confirmed = 1, Cancelled = 1 } };
            check(f.Pass && f.WalkAccounts() == "walk: 12 planned, 11 sent, 10 confirmed, 1 refused, 0 unanswered" && f.Notes().Any(x => x.StartsWith("known issue:", StringComparison.Ordinal)), "live report: planned, sent, confirmed, refused and unanswered on one line, a refusal names the known pipelining issue");
            f = Good(); f.StepsCancelled = 0;
            check(!f.Notes().Any(x => x.StartsWith("known issue:", StringComparison.Ordinal)), "live report: no refusal, no known issue note");
            f = Good();
            f.Legs = new List<LiveWalkResult> { new LiveWalkResult { Name = "south", Wanted = 2, Sent = 3, Confirmed = 3 } };
            check(!f.Pass && f.Failures().Any(x => x.StartsWith("walk plan bug: leg south sent 3 steps for 2", StringComparison.Ordinal)), "live report: a leg that sent more steps than planned is a plan bug and fails");
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
            check(Json.Int(sum, "answered") == 1 && Json.Int(sum, "local") == 1 && Json.Int(sum, "prefetched") == 0 && Json.Int(sum, "needsCondition") == 0 && Json.Int(sum, "noAnswer") == 0 && Json.List(parsed, "notes").Count == 1 && Json.List(parsed, "opcodesAtLogin").Count == 0, "live report json: the five window counts, the notes and the opcodes at login");
            check(!json.Any(c => c > 0x7e), "live report json: ASCII only");
            var failing = Good(); failing.LoginOk = false;
            var fp = Json.TryParse(failing.ToJson(null));
            check(fp != null && !Json.Bool(fp, "pass") && Json.List(fp, "failures").Count >= 1, "live report json: a failing run says why");

            string line = Good().SummaryLine();
            check(line.StartsWith("chaos live smoke: identity chaos, login ok, entered ok, walk 8 of 9 steps confirmed, 160 tiles drawn, 2 windows (1 answered, 0 prefetched at login, 1 local-only, 0 need a condition, 0 without an answer), 0 exceptions, 0 layout errors, pass", StringComparison.Ordinal), "live report: the summary line: " + line);
            check(LiveSmokeReport.SheetName(0) == "live_smoke_sheet_1.png" && LiveSmokeReport.SheetName(11) == "live_smoke_sheet_12.png", "live report: sheet file names");
        }

        // ------------------------------------------------------------------------------------ the slow call record (Core/SlowCalls.cs)
        static void SlowCallChecks(Action<bool, string> check)
        {
            double t = 0;
            SlowCallLog Make(bool on) => new SlowCallLog { Clock = () => t, On = on };

            // off: nothing is read, nothing is written
            t = 0;
            var log = Make(false);
            using (log.Begin("x", "OnGUI")) t += 5000;
            check(log.Calls().Count == 0 && log.Where().StartsWith("outside", StringComparison.Ordinal), "slow calls: with the log off a scope records nothing and costs a default struct");

            // on: 600 ms is written down, 100 ms is not
            log = Make(true); t = 1000; log.SetOrigin("new");
            t = 3000;
            using (log.Begin("HelperWindow", "OnGUI Repaint")) t += 600;
            using (log.Begin("Quick", "Tick")) t += 100;
            var calls = log.Calls();
            check(calls.Count == 1 && calls[0].Name == "HelperWindow" && calls[0].Phase == "OnGUI Repaint" && Math.Abs(calls[0].Ms - 600) < 0.01 && Math.Abs(calls[0].AtMs - 2000) < 0.01 && calls[0].Who == "new", "slow calls: a call of 500 ms or more is kept with name, phase, ms and when it began after the origin, a quick one is not");
            check(log.LastEnded == "Tick Quick", "slow calls: the last call that ended is known: " + log.LastEnded);

            // nested: the outer call's own time leaves the inner out; the top list ranks by own time
            t = 0; log = Make(true);
            using (log.Begin("Window", "OnGUI"))
            {
                t += 500;
                using (log.Begin("ArtTexture a.png", "load")) t += 1500;
                t += 100;
            }
            calls = log.Calls();
            check(calls.Count == 2 && calls[0].Name == "ArtTexture a.png" && Math.Abs(calls[1].Ms - 2100) < 0.01 && Math.Abs(calls[1].SelfMs - 600) < 0.01, "slow calls: the outer call keeps the inner time out of its own time (2100 total, 600 own)");
            var top = SlowCallLog.Top(calls, 1);
            check(top.Count == 1 && top[0].Name == "ArtTexture a.png", "slow calls: the top list is by own time, the inner call that did the work comes first");
            check(SlowCallLog.Summary(calls, 3).StartsWith("ArtTexture a.png (load) 1.5 s at 0.5 s", StringComparison.Ordinal) && SlowCallLog.Summary(calls, 3).Contains("Window (OnGUI) 0.6 s of 2.1 s at 0.0 s"), "slow calls: the summary names the top calls: " + SlowCallLog.Summary(calls, 3));

            // where the main thread is: the open scopes from the outside in, else the last note
            log = Make(true); t = 0;
            log.Note("Update");
            check(log.Where() == "outside any timed call, after Update", "slow calls: no open scope, the last note: " + log.Where());
            var outer = log.Begin("HelperWindow", "OnGUI");
            var inner = log.Begin("ArtTexture b.png", "load");
            check(log.Where() == "OnGUI HelperWindow > load ArtTexture b.png", "slow calls: the open scopes, outside in: " + log.Where());
            inner.Dispose(); outer.Dispose();
            check(log.Where().StartsWith("outside", StringComparison.Ordinal), "slow calls: closed scopes leave the stack empty");

            // a thrown exception still ends the scope
            log = Make(true); t = 0;
            try { using (log.Begin("Boom", "Update")) { t += 800; throw new InvalidOperationException("x"); } } catch (InvalidOperationException) { }
            check(log.Calls().Count == 1 && log.Where().StartsWith("outside", StringComparison.Ordinal), "slow calls: a scope that ends by an exception is recorded and popped");

            // the record is bounded
            log = Make(true); t = 0;
            for (int i = 0; i < SlowCallLog.MaxCalls + 20; i++) using (log.Begin("c" + i, "Tick")) t += 600;
            check(log.Calls().Count == SlowCallLog.MaxCalls && log.DroppedCalls == 20, "slow calls: at most " + SlowCallLog.MaxCalls + " calls are kept, the rest are counted");

            // a frame of 500 ms or more turns a log that is off on
            log = Make(false);
            log.FrameStarted(16); bool a = log.On;
            log.FrameStarted(499); bool b = log.On;
            log.FrameStarted(520);
            check(!a && !b && log.On, "slow calls: the log turns itself on after a frame of 500 ms, not before");

            // the frame gap record and the watchdog: the main thread is in a call for 20 s, the watchdog samples it, the next beat closes the gap
            log = Make(true); t = 100000; log.SetOrigin("new");
            t = 101800; log.Beat();                                    // a frame at 1.8 s
            using (log.Begin("ControlSkin", "OnGUI")) { }
            var scope = log.Begin("SomeWindow", "OnGUI Layout");       // the call that hangs
            t = 102300;
            check(log.Sample() == null, "stall watch: 500 ms without a beat is too early to look");
            t = 103000;
            string line = log.Sample();
            check(line != null && line.Contains("1.2 s without a frame") && line.Contains("OnGUI Layout SomeWindow"), "stall watch: after 1 s the watchdog says where the main thread is: " + line);
            t = 103200;
            check(log.Sample() == null, "stall watch: the watchdog does not write twice in 400 ms");
            var deeper = log.Begin("ArtTexture c.png", "load");
            t = 110000;
            line = log.Sample();
            check(line != null && line.Contains("load ArtTexture c.png") && line.Contains("8.2 s"), "stall watch: a new place is a new line: " + line);
            t = 111000;
            check(log.Sample() == null, "stall watch: the same place again is not logged again");
            deeper.Dispose(); scope.Dispose();
            t = 122000; log.Beat();
            var stalls = log.Stalls();
            check(stalls.Count == 1 && log.ClosedStalls == 1 && Math.Abs(stalls[0].Ms - 20200) < 0.01 && Math.Abs(stalls[0].AtMs - 1800) < 0.01 && stalls[0].Who == "new", "stall watch: the beat after the freeze closes it: 20.2 s that began 1.8 s after the origin");
            check(stalls[0].Seen.Count == 2 && stalls[0].Seen[0].Contains("SomeWindow") && stalls[0].Seen[1].Contains("ArtTexture c.png") && stalls[0].LastEnded.Contains("ControlSkin"), "stall watch: the record holds both places the watchdog saw and the call that ended before the hang");
            check(SlowCallLog.Line(stalls[0]).StartsWith("frame gap: 20.2 s at 1.8 s (new)", StringComparison.Ordinal), "stall watch: the log line: " + SlowCallLog.Line(stalls[0]));
            t = 122400; log.Beat();
            check(log.Stalls().Count == 1, "stall watch: a gap under 500 ms is not a stall");
            t = 123200; log.Beat();
            stalls = log.Stalls();
            check(stalls.Count == 2 && Math.Abs(stalls[1].Ms - 800) < 0.01 && stalls[1].Seen.Count == 0, "stall watch: a gap of 500 ms to 1 s is recorded without a place (the watchdog starts at 1 s)");
            // a freeze still going on is listed (the job is cut off in the middle of it)
            t = 130000; log.Sample();
            check(log.Stalls().Count == 3 && log.ClosedStalls == 2 && log.Stalls()[2].Ms > 6000, "stall watch: a freeze that has not ended yet is listed last");

            // the report: json, notes and the secret cut
            var rep = Good();
            rep.Slow.Add(new SlowCall { Name = "ArtTexture hunter2hunter2.png", Phase = "load", Ms = 21000, SelfMs = 20500, AtMs = 2400, Who = "new" });
            rep.Slow.Add(new SlowCall { Name = "Window", Phase = "OnGUI Repaint", Ms = 700, SelfMs = 700, AtMs = 25000, Who = "new" });
            rep.Stalls.Add(new StallRecord { AtMs = 1800, Ms = 19000, Who = "new", LastEnded = "OnGUI ControlSkin" });
            rep.Stalls[0].Seen.Add("OnGUI SomeWindow > load ArtTexture c.png");
            var j = Json.TryParse(rep.ToJson(new List<string> { "hunter2hunter2" }));
            var sc = Json.List(j, "slowCalls"); var st = Json.List(j, "stalls");
            check(sc.Count == 2 && Json.Text(sc[0], "name") == "ArtTexture <removed>.png" && Json.Text(sc[0], "phase") == "load" && Json.Int(sc[0], "ms") == 21000 && Json.Int(sc[0], "selfMs") == 20500 && Json.Int(sc[0], "at") == 2400 && Json.Text(sc[0], "who") == "new", "slow call json: name (secrets cut), phase, ms, own ms, at and who");
            check(st.Count == 1 && Json.Int(st[0], "ms") == 19000 && Json.Int(st[0], "at") == 1800 && Json.Text(st[0], "lastEnded") == "OnGUI ControlSkin" && Json.List(st[0], "seen").Count == 1, "slow call json: the stall with its places and the last call that ended");
            check(rep.Notes().Any(x => x.StartsWith("slow calls (own time): ArtTexture hunter2hunter2.png (load) 20.5 s of 21.0 s at 2.4 s new", StringComparison.Ordinal)) && rep.Pass, "slow call report: a note with the top calls, never a failure");
            var empty = Json.TryParse(Good().ToJson(null));
            check(Json.List(empty, "slowCalls").Count == 0 && Json.List(empty, "stalls").Count == 0 && !Good().Notes().Any(x => x.StartsWith("slow calls", StringComparison.Ordinal)), "slow call report: nothing slow, empty arrays and no note");

            // the watchdog thread and the main thread together (real clock): no exception, the record stays consistent
            var real = new SlowCallLog { On = true, WatchMs = 5, SampleMs = 1, ThresholdMs = 1 };
            bool stop = false; Exception bad = null;
            var th = new System.Threading.Thread(() => { try { while (!stop) { real.Sample(); System.Threading.Thread.Sleep(1); } } catch (Exception e) { bad = e; } });
            th.Start();
            real.Beat();
            for (int i = 0; i < 300; i++)
            {
                using (real.Begin("a", "OnGUI")) using (real.Begin("b", "load")) System.Threading.Thread.Sleep(0);
                if (i % 100 == 0) { System.Threading.Thread.Sleep(15); real.Beat(); }
            }
            stop = true; th.Join();
            check(bad == null && real.Where().StartsWith("outside", StringComparison.Ordinal) && real.Stalls().Count >= 1, "stall watch: a watchdog thread beside a main thread that opens and closes scopes breaks nothing");
        }
    }
}
