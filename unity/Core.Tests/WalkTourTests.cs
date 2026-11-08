// The walking video (Core/WalkTour.cs, FakeGameServer.UseWalkTour): the plan (timing, the 8 directions, diagonal runs, the view switches, the route on bare ground
// and clear of the creatures), the standstill meter, and the whole plan against a real GameSession over the fake server's sockets on a simulated 60 fps clock:
// steps answered after the round trip, no standstill with a key held, creatures that glide, every step confirmed.
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace Chaos.Core.Tests
{
    static class WalkTourTests
    {
        public static void Run(Action<bool, string> check)
        {
            PlanChecks(check);
            MeterChecks(check);
            EndToEnd(check);
        }

        static void PlanChecks(Action<bool, string> check)
        {
            var segs = WalkTourPlan.Segments(true);
            var views = segs.Select(s => s.View).ToArray();
            check(views.SequenceEqual(new[] { WalkView.Classic, WalkView.Hd2d, WalkView.Live, WalkView.World3d }), "walk tour plan: classic, HD-2D, live front-art, 3D world in this order");
            check(WalkTourPlan.Segments(false).Select(s => s.View).SequenceEqual(new[] { WalkView.Classic, WalkView.Hd2d, WalkView.Live }), "walk tour plan: without the 3D models the 3D segment is left out");
            double total = WalkTourPlan.EstimateMs(true), total3 = WalkTourPlan.EstimateMs(false);
            check(total >= 28000 && total <= 36000, "walk tour plan: about 30 s with the 3D world (" + (total / 1000).ToString("0.0") + " s)");
            check(total3 >= 22000 && total3 <= 30000, "walk tour plan: about 25 s without it (" + (total3 / 1000).ToString("0.0") + " s)");
            bool segTimes = true;
            foreach (var s in segs) { double ms = WalkTourPlan.EstimateMs(s); if (ms < 5000 || ms > 10500) segTimes = false; }
            check(segTimes && WalkTourPlan.EstimateMs(segs[0]) > 8000 && WalkTourPlan.EstimateMs(segs[1]) < 10000, "walk tour plan: every segment about 6 to 10 s (" + string.Join(", ", segs.Select(s => (WalkTourPlan.EstimateMs(s) / 1000).ToString("0.0"))) + ")");
            check(WalkTourPlan.Width == 1280 && WalkTourPlan.Height == 720 && WalkTourPlan.Fps == 60, "walk tour plan: 1280x720 at 60 fps");

            // every direction, held through two keys for a diagonal
            var acts = segs.SelectMany(s => s.Acts).ToList();
            var holds = acts.Where(a => a.Kind == WalkActKind.Hold).ToList();
            check(WalkDirs.All.All(d => holds.Any(h => h.Dir == d)), "walk tour plan: all 8 directions are held");
            bool masks = true;
            foreach (var d in WalkDirs.All)
            {
                int m = WalkTourPlan.MaskOf(d);
                int keys = ((m & 1) != 0 ? 1 : 0) + ((m & 2) != 0 ? 1 : 0) + ((m & 4) != 0 ? 1 : 0) + ((m & 8) != 0 ? 1 : 0);
                if (WalkInput.FromMask(m) != d || keys != (WalkDirs.Diagonal(d) ? 2 : 1)) masks = false;
            }
            check(masks, "walk tour plan: a diagonal is two held keys, a straight direction one, and WalkInput folds them back");
            int diagRuns = holds.Count(h => WalkDirs.Diagonal(h.Dir) && h.Steps >= 4);
            check(diagRuns >= 8, "walk tour plan: " + diagRuns + " diagonal runs of 4 tiles or more");
            check(acts.Count(a => a.Kind == WalkActKind.Turn) == 1 && (int)acts.First(a => a.Kind == WalkActKind.Turn).Dir < 4, "walk tour plan: one turn on the spot");
            var clicks = acts.Where(a => a.Kind == WalkActKind.Click).ToList();
            check(clicks.Count == 2 && clicks.All(c => c.Dx != 0 && c.Dy != 0), "walk tour plan: two click paths with diagonals");
            check(segs.All(s => s.Acts[0].Kind == WalkActKind.Pause), "walk tour plan: every segment starts standing, the view changes there");

            // the route is closed after every segment, on bare ground in the strictest art, and the creatures keep two tiles away
            var rounds = new List<WalkAct[]> { segs[0].Acts, segs[1].Acts, segs[2].Acts, segs[3].Acts };
            bool closed = true;
            foreach (var r in rounds)
            {
                int x = 0, y = 0;
                foreach (var a in r)
                {
                    if (a.Kind == WalkActKind.Hold) { WalkDirs.Delta(a.Dir, out int dx, out int dy); x += dx * a.Steps; y += dy * a.Steps; }
                    if (a.Kind == WalkActKind.Click) { x += a.Dx; y += a.Dy; }
                }
                if (x != 0 || y != 0) closed = false;
            }
            check(closed, "walk tour plan: every segment ends on the tile it started from");
            var strict = new TourArt { Grass = 100, Path = 101, Water = 102, Tree = 104, Rock = 104, Wall = 103, Torch = 105 };
            var map = new TourMap(strict, new Pos(100, 100, 7));
            var route = WalkTourPlan.RouteTiles(true);
            var blocked = route.Where(p => !map.Walkable(p.X, p.Y)).ToList();
            check(route.Count == 1 + 22 * 3 + 14 && blocked.Count == 0, "walk tour plan: " + route.Count + " route tiles, all bare ground even with pond, wall and torch (" + string.Join(" ", blocked) + ")");
            bool creaturesFine = true;
            string why = "";
            foreach (var c in WalkTourPlan.Creatures)
            {
                for (int i = 0; i < c.Tiles.Length; i++)
                {
                    var p = c.Tiles[i];
                    if (!map.Walkable(p.X, p.Y)) { creaturesFine = false; why += " " + c.Name + p; }
                    if (i > 0 && (Math.Abs(p.X - c.Tiles[i - 1].X) != 1 || Math.Abs(p.Y - c.Tiles[i - 1].Y) != 1)) { creaturesFine = false; why += " " + c.Name + " step " + i; }
                    foreach (var r in route) if (Math.Max(Math.Abs(r.X - p.X), Math.Abs(r.Y - p.Y)) < 2) { creaturesFine = false; why += " " + c.Name + p + " near " + r; break; }
                }
            }
            check(creaturesFine && WalkTourPlan.Creatures.Length == 2, "walk tour plan: two creatures on diagonal paths, bare ground, two tiles from the hero's route" + why);
            check(WalkTourPlan.Start == new Pos(100, 102, 7) && WalkTourPlan.Start == new FakeGameServer(strict).Start, "walk tour plan: starts where the fake server puts the hero");

            // the shared step time: speed 220 on a 150 tile, the monsters' stock diagonal
            check(WalkTiming.StepMs(220, 150, false, true) == WalkTourPlan.StraightMs && WalkTiming.StepMs(220, 150, true, true) == WalkTourPlan.DiagonalMs, "walk tour plan: the nominal step times are the client's (300 / 420 ms)");
            check(WalkTiming.StepMs(150, 150, true, false) == WalkTiming.StepMs(150, 150, false, false), "walk tour plan: a monster's diagonal costs a straight step");

            // the captions in pt-BR through Loc
            string before = Loc.Language;
            Loc.Set(Loc.Portuguese);
            string c1 = WalkTourPlan.Caption(WalkView.Classic), c4 = WalkTourPlan.Caption(WalkView.World3d);
            bool all = true;
            foreach (WalkView v in Enum.GetValues(typeof(WalkView))) { string c = WalkTourPlan.Caption(v); if (!c.Contains("8 direções, passo contínuo") || c.Contains("{0}") || !c.StartsWith(WalkTourPlan.ViewName(v), StringComparison.Ordinal)) all = false; }
            Loc.Set(before);
            check(all && c1 == "Visão clássica: 8 direções, passo contínuo" && c4 == "Mundo 3D: 8 direções, passo contínuo", "walk tour plan: pt-BR captions '" + c1 + "' / '" + c4 + "'");
            check(WalkTourPlan.Caption(WalkView.Hd2d) == "HD-2D view: 8 directions, continuous steps", "walk tour plan: the English caption is the key");
        }

        static void MeterChecks(Action<bool, string> check)
        {
            double dt = 1000.0 / 60;
            // a hold that moves every frame: nothing stood still; the start delay is the wait before the first motion
            var m = new WalkStandstill();
            double x = 0;
            for (int i = 0; i < 6; i++) m.Update(dt, true, 0, 0);
            for (int i = 0; i < 60; i++) { x += 0.02; m.Update(dt, true, x, 0); }
            check(m.Longest == 0 && Math.Abs(m.StartDelay - 6 * dt) < 1e-6 && Math.Abs(m.Stuck - 6 * dt) < 1e-6, "walk standstill: moving with a key held is no standstill, the wait before the first motion is the start delay");
            // a stop of 4 frames in the middle of a hold counts
            m = new WalkStandstill();
            for (int i = 0; i < 10; i++) { x += 0.02; m.Update(dt, true, x, 0); }
            for (int i = 0; i < 4; i++) m.Update(dt, true, x, 0);
            for (int i = 0; i < 10; i++) { x += 0.02; m.Update(dt, true, x, 0); }
            check(Math.Abs(m.Longest - 4 * dt) < 1e-6, "walk standstill: four frames standing in a hold are " + m.Longest.ToString("0.0") + " ms");
            // standing without a key is nothing, and a new press starts a new hold
            m = new WalkStandstill();
            for (int i = 0; i < 10; i++) { x += 0.02; m.Update(dt, true, x, 0); }
            for (int i = 0; i < 30; i++) m.Update(dt, false, x, 0);
            for (int i = 0; i < 3; i++) m.Update(dt, true, x, 0);
            for (int i = 0; i < 10; i++) { x += 0.02; m.Update(dt, true, x, 0); }
            check(m.Longest == 0 && Math.Abs(m.StartDelay - 3 * dt) < 1e-6, "walk standstill: no key, no standstill; the next press is a new hold");
            // a key held and never moving is stuck
            m = new WalkStandstill();
            for (int i = 0; i < 60; i++) m.Update(dt, true, 5, 5);
            check(m.Longest == 0 && m.Stuck > WalkTourPlan.StuckLimitMs, "walk standstill: a key held and no motion is stuck");
        }

        static void EndToEnd(Action<bool, string> check)
        {
            var demo = Hd2dDemo.Synthetic();
            var art = TourArt.FromDemo(DemoIds.Synthetic()).Probe(demo.Dat);
            using (var server = new FakeGameServer(art))
            {
                server.UseWalkTour();
                server.Begin();
                var res = LoginClient.Login("127.0.0.1", server.Port, "demo", "demo", server.RsaModulus, 30).GetAwaiter().GetResult();
                if (res.Error != null || res.Characters.Count == 0) { check(false, "walk tour server: login (" + res.Error + ")"); return; }
                double clock = 0;
                GameSession.TestClock = () => clock;
                string language = Loc.Language;
                try
                {
                    var world = new World(demo.Dat);
                    world.Fx.Enabled = true;
                    var session = new GameSession(world, new GameSession.Options
                    {
                        Host = "127.0.0.1", Port = server.GamePort, Account = "demo", Password = "demo", SessionKey = res.SessionKey, Character = FakeGameServer.HeroName,
                        GuardKey = server.GuardKey, Build = 30, RsaModulus = server.RsaModulus, Identity = ClientIdentity.Extended,
                    });
                    session.Start();
                    var wall = DateTime.UtcNow.AddSeconds(20);
                    while (DateTime.UtcNow < wall && !server.InGame) { session.Poll(); Thread.Sleep(5); }
                    for (int i = 0; i < 60 && !(session.Parser.LoggedIn && world.Player != null); i++) { clock += 1000.0 / 60; session.Poll(); Thread.Sleep(5); }
                    var settle = DateTime.UtcNow.AddSeconds(10);
                    while (DateTime.UtcNow < settle && session.Parser.Health != FakeGameServer.MaxHealth) { session.Poll(); Thread.Sleep(5); }
                    check(session.Parser.LoggedIn && world.Player != null && world.Player.Position == WalkTourPlan.Start, "walk tour server: the hero stands on the start tile");
                    check(world.Creatures.Count == 2 && world.Creatures.ContainsKey(FakeGameServer.SkeletonId) && !world.Creatures.ContainsKey(FakeGameServer.GhoulId), "walk tour server: the hero and the skeleton are in the first view, the ghoul is beyond it (" + world.Creatures.Count + " creatures)");
                    if (world.Player == null) return;

                    // one diagonal step by itself, to see the answer: two tiles, and the round trip
                    var keys = new WalkInputState();
                    double t0 = clock, sentAt = -1, answeredAt = -1;
                    int movesBefore = session.Parser.PlayerMoves;
                    for (int i = 0; i < 90 && answeredAt < 0; i++)
                    {
                        clock += 1000.0 / 60;
                        double t = clock - t0;
                        session.Poll();
                        if (sentAt < 0)
                        {
                            Dir? d = keys.Update(session.Now, WalkInput.Up | WalkInput.Right);
                            if (d != null)
                            {
                                check(d == Dir.NorthEast, "walk tour server: two held keys fold into north-east, not a straight step first");
                                session.Walk(d.Value);
                                if (session.WalksSent == 1) sentAt = clock;
                            }
                        }
                        server.Advance(t);
                        Thread.Sleep(3);
                        if (session.Parser.PlayerMoves > movesBefore) answeredAt = clock;
                    }
                    double rtt = answeredAt - sentAt;
                    check(sentAt >= 0 && answeredAt >= 0 && rtt >= WalkTourPlan.RoundTripMs - 1 && rtt <= WalkTourPlan.RoundTripMs + 50, "walk tour server: a diagonal step is answered after the round trip (" + rtt.ToString("0") + " ms)");
                    check(world.Player.Position == new Pos(101, 101, 7) && server.HeroPos == world.Player.Position && server.Steps == 1, "walk tour server: the hero went north-east to " + world.Player.Position + " and the server agrees");
                    // back to the start with the south-west diagonal, then wait for the hero to stand
                    keys = new WalkInputState();
                    int guard = 0;
                    bool backSent = false;
                    while (guard++ < 240 && !(backSent && session.WalkIdle && world.Player.Position == WalkTourPlan.Start))
                    {
                        clock += 1000.0 / 60;
                        session.Poll();
                        if (!backSent) { Dir? d = keys.Update(session.Now, WalkInput.Down | WalkInput.Left); if (d != null) { session.Walk(d.Value); backSent = session.WalksSent == 2; } }
                        server.Advance(clock - t0);
                        Thread.Sleep(3);
                    }
                    check(world.Player.Position == WalkTourPlan.Start && session.WalkIdle, "walk tour server: south-west took the hero back to the start (" + world.Player.Position + ")");
                    check(session.WalksSent == 2 && server.Steps == 2 && server.Blocked == 0, "walk tour server: two steps sent, two taken, none refused");

                    // the whole plan, as the director plays it: the conductor's keys, the player's input path, the fake server's answers
                    Loc.Set(Loc.Portuguese);
                    int viewSwitches = 0;
                    var seen = new List<WalkView>();
                    WalkTourConductor conductor = null;
                    var host = new WalkTourHost { Session = session, World = world };
                    host.SetView = v => { viewSwitches++; seen.Add(v); };
                    host.Click = goal =>
                    {
                        var me = world.Player.Position;
                        uint self = world.PlayerId;
                        var path = PathFinder.Find(me, goal, p => WalkMap.Walkable(world, p, self), 0);
                        if (path == null || path.Count == 0) return -1;
                        session.SendRaw(AutoWalkPackets.WalkPacket(path));
                        return path.Count;
                    };
                    conductor = new WalkTourConductor(host, true);
                    keys = new WalkInputState();
                    double rec0 = clock;
                    int stepsBefore = server.Steps, sentBefore = session.WalksSent;
                    var sendTimes = new Queue<double>();
                    var delays = new List<double>();
                    int lastSent = session.WalksSent, lastMoves = session.Parser.PlayerMoves, frames = 0, glideFrames = 0, glideTotal = 0;
                    var atEnd = new List<Pos>();
                    var enteredAt = new Dictionary<uint, double>();
                    var stillRun = new Dictionary<uint, int>();
                    int longestStill = 0;
                    Dir faced = Dir.North;
                    var firstSent = new List<Dir>();
                    while (!conductor.Done && frames < 60 * 60 && session.Closed == null)
                    {
                        frames++;
                        clock += 1000.0 / 60;
                        double t = clock - t0;
                        session.Poll();
                        int mask = conductor.PollMask();
                        Dir? d = keys.Update(session.Now, mask);   // HandleWalk of the app
                        if (d != null) session.Walk(d.Value);
                        server.Advance(t);
                        conductor.Observe(1000.0 / 60);
                        if (session.WalksSent > lastSent) { for (int k = lastSent; k < session.WalksSent; k++) sendTimes.Enqueue(clock); if (d != null && firstSent.Count < 1) firstSent.Add(d.Value); lastSent = session.WalksSent; }
                        if (session.Parser.PlayerMoves > lastMoves)
                        {
                            for (int k = lastMoves; k < session.Parser.PlayerMoves; k++)
                                if (conductor.SegmentIndex < 3 && sendTimes.Count > 0) delays.Add(clock - sendTimes.Dequeue());
                            lastMoves = session.Parser.PlayerMoves;
                        }
                        if (atEnd.Count < conductor.Reports.Count) { atEnd.Add(world.Player.Position); if (conductor.Reports.Count == 1) faced = world.Player.Direction; }
                        // the creatures: gliding in nearly every frame while they are on the map; one that comes into view by the hero's step stands until its next move (it was out
                        // of sight for the last one), so it is counted from 400 ms after it came
                        if (clock - rec0 > 2500)
                            foreach (uint id in new[] { FakeGameServer.SkeletonId, FakeGameServer.GhoulId })
                            {
                                bool drawn = false;
                                if (world.Creatures.TryGetValue(id, out var mob))
                                {
                                    var tile = world.Get(mob.Position);
                                    var me = world.Player.Position;
                                    bool inWindow = mob.Position.X >= me.X - World.RangeLeft && mob.Position.X <= me.X + World.RangeRight && mob.Position.Y >= me.Y - World.RangeTop && mob.Position.Y <= me.Y + World.RangeBottom;
                                    drawn = inWindow && tile != null && tile.Things.Any(th => th.Creature == mob);
                                    if (drawn)
                                    {
                                        if (!enteredAt.TryGetValue(id, out double since) || since < 0) enteredAt[id] = since = clock;
                                        if (clock - since >= 400)
                                        {
                                            WalkMath.Between(mob, session.Now, out Pos from, out Pos to, out float u);
                                            glideTotal++;
                                            if (from != to && u < 1f) { glideFrames++; stillRun[id] = 0; }
                                            else
                                            {
                                                stillRun.TryGetValue(id, out int run);
                                                stillRun[id] = ++run;
                                                longestStill = Math.Max(longestStill, run);
                                            }
                                        }
                                    }
                                }
                                if (!drawn) { enteredAt[id] = -1; stillRun[id] = 0; }
                            }
                        Thread.Sleep(3);
                    }
                    for (int i = 0; i < 40; i++) { clock += 1000.0 / 60; session.Poll(); server.Advance(clock - t0); Thread.Sleep(3); }
                    check(conductor.Done && session.Closed == null, "walk tour run: the plan finished in " + frames + " frames (" + (frames / 60.0).ToString("0.0") + " s)");
                    check(frames >= 60 * 20 && frames <= 60 * 45, "walk tour run: 25 to 35 s of frames, by the art's ground speed (" + frames + ")");
                    foreach (var r in conductor.Reports) Console.WriteLine("  " + r.Line(conductor.Reports.IndexOf(r) + 1));
                    foreach (var p in conductor.Problems) Console.WriteLine("  problem: " + p);
                    check(conductor.Reports.Count == 4 && seen.SequenceEqual(new[] { WalkView.Classic, WalkView.Hd2d, WalkView.Live, WalkView.World3d }), "walk tour run: four segments, the view switched in order (" + string.Join(",", seen) + ")");
                    check(conductor.Reports.All(r => r.Standstill <= WalkTourPlan.StandstillLimitMs), "walk tour run: longest standstill with a key held " + string.Join(", ", conductor.Reports.Select(r => r.Standstill.ToString("0") + " ms")) + " (limit 50)");
                    check(conductor.Reports.All(r => r.Sent == r.Confirmed && r.Sent > 0), "walk tour run: steps sent equal steps confirmed in every segment (" + string.Join(", ", conductor.Reports.Select(r => r.Sent + "/" + r.Confirmed)) + ")");
                    check(conductor.Reports.Select(r => r.Sent).SequenceEqual(new[] { 22, 22, 22, 14 }), "walk tour run: 22, 22, 22 and 14 steps per segment");
                    check(conductor.Reports.All(r => r.StartDelay <= 200), "walk tour run: the start delay from the key down to the first motion stays small (" + string.Join(", ", conductor.Reports.Select(r => r.StartDelay.ToString("0") + " ms")) + ")");
                    check(conductor.Problems.Count == 0, "walk tour run: no problems (" + string.Join("; ", conductor.Problems) + ")");
                    check(atEnd.Count == 4 && atEnd.All(p => p == WalkTourPlan.Start), "walk tour run: every segment ended on the start tile (" + string.Join(" ", atEnd) + ")");
                    check(faced == Dir.East, "walk tour run: the turn on the spot left the hero facing east (" + faced + ")");
                    check(server.Steps - stepsBefore == 80 && server.Blocked == 0 && server.Cancels == 0 && server.Turns == 1 && server.AutoRequests == 2, "walk tour run: the server took 80 steps, one turn, two auto-walks, refused none (" + (server.Steps - stepsBefore) + ", " + server.Turns + ", " + server.AutoRequests + ", " + server.Cancels + ")");
                    check(session.WalksSent - sentBefore == 74 && world.Player.Position == server.HeroPos, "walk tour run: 74 key steps and 6 on click paths; the client and the server agree on " + server.HeroPos + " (" + (session.WalksSent - sentBefore) + ")");
                    check(firstSent.Count == 1 && firstSent[0] == Dir.NorthEast, "walk tour run: the first key step is the diagonal, the second key came inside the grace time (" + string.Join(",", firstSent) + ")");
                    delays.Sort();
                    double median = delays.Count > 0 ? delays[delays.Count / 2] : -1, worst = delays.Count > 0 ? delays[delays.Count - 1] : -1;
                    // a step goes out one pre-walk lead before the glide of the step before ends and the server runs it when that one is over: its answer is the round trip after the
                    // step's own predicted start, so after the send it is lead + round trip; a step from rest is answered after the round trip alone
                    double lead = WalkTiming.PreWalkLeadMs, best = delays.Count > 0 ? delays[0] : -1;
                    check(delays.Count >= 60 && best >= WalkTourPlan.RoundTripMs - 20 && median >= WalkTourPlan.RoundTripMs + lead - 25 && median <= WalkTourPlan.RoundTripMs + lead + 30 && worst <= WalkTourPlan.RoundTripMs + lead + 60,
                          "walk tour run: key steps are confirmed one round trip after they start gliding, best " + best.ToString("0") + " ms, median " + median.ToString("0") + " ms, worst " + worst.ToString("0") + " ms after the send, of " + delays.Count);
                    double share = glideTotal > 0 ? glideFrames / (double)glideTotal : 0;
                    check(share >= 0.9 && glideTotal >= 400 && longestStill <= 2, "walk tour run: the skeleton and the ghoul glide in " + (share * 100).ToString("0") + "% of the " + glideTotal + " frames they are on the map, the longest standing run is " + longestStill + " frames (the one frame at each tile's end is the next glide's start)");
                    bool known = world.Creatures.TryGetValue(FakeGameServer.SkeletonId, out var skel) & world.Creatures.TryGetValue(FakeGameServer.GhoulId, out var ghoul);
                    check(known && WalkTourPlan.Creatures[0].Tiles.Contains(skel.Position) && WalkTourPlan.Creatures[1].Tiles.Contains(ghoul.Position), "walk tour run: both creatures came into view and stand on their own paths");
                    session.Dispose();
                }
                finally { GameSession.TestClock = null; Loc.Set(language); }
            }
        }
    }
}
