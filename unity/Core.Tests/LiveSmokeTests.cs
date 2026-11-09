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
            to.Screenshot = n.Screenshot; to.ToastMs = n.ToastMs; to.HelperMs = n.HelperMs;
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
    }
}
