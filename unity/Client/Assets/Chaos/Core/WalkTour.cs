// The walking video (phase 19, track W; unity/README.md "Walking video"): `ChaosUnity -chaosWalkTour OUT_DIR` records about 30 seconds of the hero walking the
// smooth 8-direction walk (Core/SmoothWalk.cs) in each of the views, against the demo tour's fake server (Core/DemoTour.cs, FakeGameServer.UseWalkTour).
// Pure logic, no engine API, tested in Core.Tests/WalkTourTests.cs:
//   WalkTourPlan       the plan: segments (a view each) of acts (a pause, held keys for a number of steps, a turn on the spot, a click path), the creatures'
//                      paths, the round trip, the captions
//   WalkStandstill     the meter: how long the drawn hero stood still while a key was held
//   WalkTourConductor  runs the plan against a GameSession: the key mask of the frame (the player's own path: WalkInputState, then GameSession.Walk), the view
//                      switches, the measured line of each segment
// The keys are held for a number of steps sent, not for a time, so the route is the same tile for tile whatever the step times are.
using System;
using System.Collections.Generic;
using System.Globalization;

namespace Chaos.Core
{
    public enum WalkView { Classic, Hd2d, Live, World3d }

    public enum WalkActKind { Pause, Hold, Turn, Click }

    public sealed class WalkAct
    {
        public WalkActKind Kind;
        /// <summary>Hold: the keys held (WalkInput mask) and how many steps are sent before they are let go or changed.</summary>
        public int Mask, Steps;
        public Dir Dir;
        /// <summary>Click: the goal as a distance from where the hero stands.</summary>
        public int Dx, Dy;
        public double Ms;

        public static WalkAct Pause(double ms) { return new WalkAct { Kind = WalkActKind.Pause, Ms = ms }; }
        public static WalkAct Hold(Dir d, int steps) { return new WalkAct { Kind = WalkActKind.Hold, Dir = d, Mask = WalkTourPlan.MaskOf(d), Steps = steps }; }
        public static WalkAct Turn(Dir d) { return new WalkAct { Kind = WalkActKind.Turn, Dir = d }; }
        public static WalkAct Click(int dx, int dy) { return new WalkAct { Kind = WalkActKind.Click, Dx = dx, Dy = dy }; }
    }

    public sealed class WalkSegment
    {
        public WalkView View;
        public WalkAct[] Acts;
    }

    /// <summary>A creature that walks its tiles to the end and back, one tile at a time (the server script of the walking video).</summary>
    public sealed class WalkCreature
    {
        public uint Id;
        public string Name;
        public Pos[] Tiles;
        public double StartMs;
    }

    public static class WalkTourPlan
    {
        public const int Width = 1280, Height = 720, Fps = 60;

        /// <summary>The simulated round trip of a step: half to the server, half back (the real server's queue and step times come on top, see FakeGameServer.QueueStep).</summary>
        public const double RoundTripMs = 120, OneWayMs = 60;

        /// <summary>The director fails the run when the hero stood still longer than this while a key was held.</summary>
        public const double StandstillLimitMs = 50;

        /// <summary>A key held and the hero not moving for this long from the first frame: the run is stuck (blocked tile, no answer).</summary>
        public const double StuckLimitMs = 600;

        /// <summary>The nominal step times the estimates use: speed 220 on a grass tile of 150, straight and diagonal (WalkTiming.StepMs).</summary>
        public const double StraightMs = 300, DiagonalMs = 420;

        public const double FirstBreathMs = 600, BreathMs = 300, TurnWaitMs = 700, SettleMs = 100, ClickEndMs = 300, StaggerMs = 30;

        /// <summary>How long the creatures' script runs (the plan is shorter; a run that goes over still has creatures).</summary>
        public const double ScriptMs = 60000;

        public static readonly Pos Start = new Pos(100, 102, 7);

        /// <summary>The creatures' paths: diagonals out and back, two tiles or more away from every tile the hero's route touches (WalkTourTests checks it, and the map).</summary>
        public static readonly WalkCreature[] Creatures =
        {
            new WalkCreature { Id = FakeGameServer.SkeletonId, Name = "Skeleton", StartMs = 600, Tiles = Diagonal(109, 107, -1, 1, 6) },
            new WalkCreature { Id = FakeGameServer.GhoulId, Name = "Ghoul", StartMs = 1100, Tiles = Diagonal(112, 102, -1, -1, 6) },
        };

        static Pos[] Diagonal(int x, int y, int dx, int dy, int n)
        {
            var t = new Pos[n];
            for (int i = 0; i < n; i++) t[i] = new Pos(x + dx * i, y + dy * i, 7);
            return t;
        }

        /// <summary>The keys of a direction: two keys for a diagonal (WalkInput.FromMask folds them back).</summary>
        public static int MaskOf(Dir d)
        {
            switch (d)
            {
                case Dir.North: return WalkInput.Up;
                case Dir.South: return WalkInput.Down;
                case Dir.West: return WalkInput.Left;
                case Dir.East: return WalkInput.Right;
                case Dir.NorthEast: return WalkInput.Up | WalkInput.Right;
                case Dir.NorthWest: return WalkInput.Up | WalkInput.Left;
                case Dir.SouthEast: return WalkInput.Down | WalkInput.Right;
                default: return WalkInput.Down | WalkInput.Left;
            }
        }

        // A round of the meadow east of the start that touches all 8 directions: diagonals of 4 tiles, short straights. Both come back to the start tile and stay
        // on bare ground whatever the art is (pond, wall, torch or none).
        static WalkAct[] Round() { return new[] { WalkAct.Hold(Dir.NorthEast, 4), WalkAct.Hold(Dir.East, 1), WalkAct.Hold(Dir.SouthEast, 4), WalkAct.Hold(Dir.South, 2),
                                                  WalkAct.Hold(Dir.SouthWest, 4), WalkAct.Hold(Dir.West, 1), WalkAct.Hold(Dir.NorthWest, 4), WalkAct.Hold(Dir.North, 2) }; }
        static WalkAct[] RoundBack() { return new[] { WalkAct.Hold(Dir.South, 2), WalkAct.Hold(Dir.SouthEast, 4), WalkAct.Hold(Dir.East, 1), WalkAct.Hold(Dir.NorthEast, 4),
                                                      WalkAct.Hold(Dir.North, 2), WalkAct.Hold(Dir.NorthWest, 4), WalkAct.Hold(Dir.West, 1), WalkAct.Hold(Dir.SouthWest, 4) }; }

        static WalkAct[] Join(WalkAct first, WalkAct[] middle, params WalkAct[] last)
        {
            var l = new List<WalkAct> { first };
            l.AddRange(middle);
            l.AddRange(last);
            return l.ToArray();
        }

        /// <summary>The plan: classic with a turn on the spot, HD-2D the other way round, the live front-art view, and the 3D world (when the models are in the build)
        /// with two click paths and a straight run of 4 diagonal tiles out and back.</summary>
        public static List<WalkSegment> Segments(bool with3d)
        {
            var l = new List<WalkSegment>
            {
                new WalkSegment { View = WalkView.Classic, Acts = Join(WalkAct.Pause(FirstBreathMs), Round(), WalkAct.Turn(Dir.East)) },
                new WalkSegment { View = WalkView.Hd2d, Acts = Join(WalkAct.Pause(BreathMs), RoundBack()) },
                new WalkSegment { View = WalkView.Live, Acts = Join(WalkAct.Pause(BreathMs), Round()) },
            };
            if (with3d)
                l.Add(new WalkSegment { View = WalkView.World3d, Acts = new[] { WalkAct.Pause(BreathMs), WalkAct.Click(3, -3), WalkAct.Click(-3, 3), WalkAct.Hold(Dir.SouthEast, 4), WalkAct.Hold(Dir.NorthWest, 4) } });
            return l;
        }

        /// <summary>The tiles the hero stands on in the plan, from the start, with the path of a click taken as the diagonals first then the straight rest (what the
        /// path finder gives on open ground). Used by the tests to check the route against the map and the creatures.</summary>
        public static List<Pos> RouteTiles(bool with3d)
        {
            var tiles = new List<Pos>();
            var p = Start;
            tiles.Add(p);
            foreach (var seg in Segments(with3d))
                foreach (var a in seg.Acts)
                {
                    if (a.Kind == WalkActKind.Hold)
                        for (int i = 0; i < a.Steps; i++) { p = WalkDirs.Step(p, a.Dir); tiles.Add(p); }
                    else if (a.Kind == WalkActKind.Click)
                    {
                        int dx = a.Dx, dy = a.Dy;
                        while (dx != 0 || dy != 0)
                        {
                            int sx = Math.Sign(dx), sy = Math.Sign(dy);
                            p = p.Offset(sx, sy);
                            dx -= sx; dy -= sy;
                            tiles.Add(p);
                        }
                    }
                }
            return tiles;
        }

        public static double StepNominalMs(Dir d) { return WalkDirs.Diagonal(d) ? DiagonalMs : StraightMs; }

        /// <summary>The time one act takes with the nominal step times (the real run settles within a second of it).</summary>
        public static double EstimateMs(WalkAct a)
        {
            switch (a.Kind)
            {
                case WalkActKind.Pause: return a.Ms;
                case WalkActKind.Hold: return a.Steps * StepNominalMs(a.Dir);
                case WalkActKind.Turn: return SettleMs + TurnWaitMs;
                default:
                {
                    int diag = Math.Min(Math.Abs(a.Dx), Math.Abs(a.Dy)), straight = Math.Max(Math.Abs(a.Dx), Math.Abs(a.Dy)) - diag;
                    return SettleMs + RoundTripMs + diag * DiagonalMs + straight * StraightMs + ClickEndMs;
                }
            }
        }

        public static double EstimateMs(WalkSegment s)
        {
            double t = 0;
            foreach (var a in s.Acts) t += EstimateMs(a);
            return t + SettleMs + RoundTripMs;   // the settle at the segment's end
        }

        public static double EstimateMs(bool with3d)
        {
            double t = 0;
            foreach (var s in Segments(with3d)) t += EstimateMs(s);
            return t;
        }

        // ---- the captions (pt-BR through Loc: the keys are the English texts, LocPhase19W has the Portuguese)
        public static string ViewName(WalkView v)
        {
            switch (v)
            {
                case WalkView.Classic: return Loc.T("Classic view");
                case WalkView.Hd2d: return Loc.T("HD-2D view");
                case WalkView.Live: return Loc.T("Live front-art view");
                default: return Loc.T("3D world view");
            }
        }

        public static string Caption(WalkView v) { return Loc.T("{0}: 8 directions, continuous steps", ViewName(v)); }
    }

    /// <summary>How long the drawn hero stood still while a key was held. Feed it once a frame with the drawn position (tiles). It only counts after the hero has started to
    /// move in this hold: the time from the key down to the first motion is the start delay, reported on its own. A key let go and pressed again starts a new hold.</summary>
    public sealed class WalkStandstill
    {
        public double Longest, StartDelay, Stuck;
        double run, wait, lx, ly;
        bool armed, held, have;

        public void Update(double dtMs, bool keyHeld, double x, double y)
        {
            bool moved = have && Math.Abs(x - lx) + Math.Abs(y - ly) > 1e-4;
            lx = x; ly = y; have = true;
            if (!keyHeld) { armed = false; held = false; run = 0; wait = 0; return; }
            if (!held) { held = true; wait = 0; run = 0; }
            if (moved)
            {
                if (!armed) StartDelay = Math.Max(StartDelay, wait);
                armed = true;
                run = 0;
            }
            else if (armed)
            {
                run += dtMs;
                Longest = Math.Max(Longest, run);
            }
            else
            {
                wait += dtMs;
                Stuck = Math.Max(Stuck, wait);
            }
        }
    }

    /// <summary>The numbers of one segment, logged as one line.</summary>
    public sealed class WalkSegmentReport
    {
        public WalkView View;
        public double Ms, Standstill, StartDelay;
        public int Sent, Confirmed;

        public bool Over => Standstill > WalkTourPlan.StandstillLimitMs;

        public string Line(int index)
        {
            return string.Format(CultureInfo.InvariantCulture, "segment {0} {1}: {2:0.0} s, steps sent {3}, steps confirmed {4}, longest standstill {5:0} ms, start delay {6:0} ms",
                                 index, View, Ms / 1000.0, Sent, Confirmed, Standstill, StartDelay);
        }
    }

    /// <summary>What the conductor needs of the client: the session and world, the view switch and the click path (the director gives the app's own).</summary>
    public sealed class WalkTourHost
    {
        public GameSession Session;
        public World World;
        public Action<WalkView> SetView = v => { };
        /// <summary>Starts an auto-walk to the goal as a click does; the number of steps of the path, or -1 when there is none.</summary>
        public Func<Pos, int> Click = goal => -1;
        public double Now { get { return Session.Now; } }
        public Pos Position { get { return World.Player.Position; } }
    }

    /// <summary>Runs the plan. Two calls per frame: PollMask (from the walk input, once per frame at least) gives the keys held now; Observe (after the frame's
    /// update, the player's drawn position is final) feeds the standstill meter. Either one moves the plan on, so the next leg's keys are there in the same frame
    /// the last step of the leg went out.</summary>
    public sealed class WalkTourConductor
    {
        public const double StaggerMs = WalkTourPlan.StaggerMs;
        readonly WalkTourHost host;
        readonly List<WalkSegment> segs;
        int seg = -1, act, mask;
        bool begun, settling, fromRest, turned, clicked, clickArrived;
        double segStart, actStart, turnAt, clickAt, arrivedAt, settleAt;
        int baseSent, baseMoves, holdBase, segClickSteps, clickSteps;
        Pos goal;
        WalkStandstill meter = new WalkStandstill();

        public bool Done { get; private set; }
        public readonly List<WalkSegmentReport> Reports = new List<WalkSegmentReport>();
        /// <summary>Everything that went wrong, one clear line each (the director logs them and fails the run).</summary>
        public readonly List<string> Problems = new List<string>();

        public WalkTourConductor(WalkTourHost h, bool with3d)
        {
            host = h;
            segs = WalkTourPlan.Segments(with3d);
        }

        public int SegmentIndex => seg;
        public WalkView View => seg >= 0 && seg < segs.Count ? segs[seg].View : WalkView.Classic;
        public string Caption => seg >= 0 && seg < segs.Count && !Done ? WalkTourPlan.Caption(segs[seg].View) : "";
        public int Mask => mask;

        /// <summary>The keys held in this frame.</summary>
        public int PollMask() { Tick(); return mask; }

        /// <summary>After the frame's update: the standstill meter takes the drawn position of the hero.</summary>
        public void Observe(double dtMs)
        {
            Tick();
            if (Done || seg < 0 || host.World.Player == null) return;
            WalkMath.Drawn(host.World.Player, host.Now, out float x, out float y, out float progress);
            bool held = mask != 0 || (begun && act < segs[seg].Acts.Length && segs[seg].Acts[act].Kind == WalkActKind.Click && clicked && !clickArrived);
            meter.Update(dtMs, held, x, y);
            if (meter.Stuck > WalkTourPlan.StuckLimitMs) Fail(string.Format(CultureInfo.InvariantCulture, "segment {0} {1}: a key was held and the hero did not move for {2:0} ms", seg + 1, segs[seg].View, meter.Stuck));
        }

        bool stuckLogged;
        void Fail(string line)
        {
            if (stuckLogged) return;
            stuckLogged = true;
            Problems.Add(line);
        }

        void Tick()
        {
            if (Done) { mask = 0; return; }
            double now = host.Now;
            for (int guard = 0; guard < 32; guard++)
            {
                if (seg < 0 || (act >= segs[seg].Acts.Length && !settling))
                {
                    if (seg >= 0) { settling = true; settleAt = now; mask = 0; }
                    else if (!NextSegment(now)) { mask = 0; return; }
                }
                if (settling)
                {
                    mask = 0;
                    // every step sent is confirmed and the last glide is over; then the numbers are final and the next view comes
                    bool idle = host.Session.WalkIdle;
                    if (!((idle && now - settleAt >= WalkTourPlan.SettleMs + WalkTourPlan.RoundTripMs) || now - settleAt > 3000)) return;
                    settling = false;
                    Finish(now);
                    if (!NextSegment(now)) { mask = 0; return; }
                    continue;
                }
                var a = segs[seg].Acts[act];
                if (!begun) Begin(a, now);
                if (Step(a, now)) { act++; begun = false; continue; }
                return;
            }
        }

        bool NextSegment(double now)
        {
            seg++;
            if (seg >= segs.Count) { Done = true; return false; }
            act = 0; begun = false; settling = false;
            segStart = now;
            baseSent = host.Session.WalksSent;
            baseMoves = host.Session.Parser.PlayerMoves;
            segClickSteps = 0;
            meter = new WalkStandstill();
            stuckLogged = false;
            host.SetView(segs[seg].View);
            return true;
        }

        void Finish(double now)
        {
            var r = new WalkSegmentReport
            {
                View = segs[seg].View,
                Ms = now - segStart,
                Sent = host.Session.WalksSent - baseSent + segClickSteps,
                Confirmed = host.Session.Parser.PlayerMoves - baseMoves,
                Standstill = meter.Longest,
                StartDelay = meter.StartDelay,
            };
            Reports.Add(r);
            if (r.Over) Problems.Add(string.Format(CultureInfo.InvariantCulture, "segment {0} {1}: the hero stood still for {2:0} ms with a key held, over the limit of {3:0} ms", seg + 1, r.View, r.Standstill, WalkTourPlan.StandstillLimitMs));
            if (r.Sent != r.Confirmed) Problems.Add(string.Format(CultureInfo.InvariantCulture, "segment {0} {1}: {2} steps sent but {3} confirmed", seg + 1, r.View, r.Sent, r.Confirmed));
        }

        void Begin(WalkAct a, double now)
        {
            begun = true;
            actStart = now;
            switch (a.Kind)
            {
                case WalkActKind.Hold:
                    holdBase = host.Session.WalksSent;
                    fromRest = mask == 0;
                    break;
                case WalkActKind.Turn: turned = false; break;
                case WalkActKind.Click: clicked = false; clickArrived = false; break;
            }
        }

        /// <summary>One act for this frame; true when it is over (the next one then starts in the same call, so held keys do not blink).</summary>
        bool Step(WalkAct a, double now)
        {
            switch (a.Kind)
            {
                case WalkActKind.Pause:
                    mask = 0;
                    return now - actStart >= a.Ms;
                case WalkActKind.Hold:
                {
                    if (host.Session.WalksSent - holdBase >= a.Steps) return true;
                    if (now - actStart > a.Steps * 1500.0 + 4000)
                    {
                        Problems.Add(string.Format(CultureInfo.InvariantCulture, "segment {0} {1}: {2} held for {3} steps and only {4} went out", seg + 1, segs[seg].View, a.Dir, a.Steps, host.Session.WalksSent - holdBase));
                        mask = 0;
                        return true;
                    }
                    // from rest a diagonal starts with its first key and the second follows a moment later, as fingers do (WalkInputState waits for it)
                    if (fromRest && WalkDirs.Diagonal(a.Dir) && now - actStart < StaggerMs) mask = a.Mask & (WalkInput.Up | WalkInput.Down);
                    else mask = a.Mask;
                    return false;
                }
                case WalkActKind.Turn:
                {
                    mask = 0;
                    if (!turned)
                    {
                        if (host.Session.WalkIdle && now - actStart >= WalkTourPlan.SettleMs) { host.Session.Turn(a.Dir); turned = true; turnAt = now; }
                        else if (now - actStart > 3000) { Problems.Add("segment " + (seg + 1) + ": the hero never stood still for the turn"); return true; }
                        return false;
                    }
                    return now - turnAt >= WalkTourPlan.TurnWaitMs;
                }
                default:
                {
                    mask = 0;
                    if (!clicked)
                    {
                        if (host.Session.WalkIdle && now - actStart >= WalkTourPlan.SettleMs)
                        {
                            goal = host.Position.Offset(a.Dx, a.Dy);
                            int n = host.Click(goal);
                            if (n < 0) { Problems.Add("segment " + (seg + 1) + ": no click path to " + goal); return true; }
                            clicked = true; clickAt = now; clickSteps = n; segClickSteps += n; arrivedAt = -1;
                        }
                        else if (now - actStart > 3000) { Problems.Add("segment " + (seg + 1) + ": the hero never stood still for the click"); return true; }
                        return false;
                    }
                    if (!clickArrived && host.Position == goal && host.Session.WalkIdle) { clickArrived = true; arrivedAt = now; }
                    if (clickArrived) return now - arrivedAt >= WalkTourPlan.ClickEndMs;
                    if (now - clickAt > clickSteps * 1500.0 + 4000) { Problems.Add("segment " + (seg + 1) + ": the click path to " + goal + " was not walked"); clickArrived = true; arrivedAt = now - WalkTourPlan.ClickEndMs; }
                    return false;
                }
            }
        }
    }
}
