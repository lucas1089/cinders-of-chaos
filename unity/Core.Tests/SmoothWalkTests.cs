// Smooth 8-direction walking (Core/SmoothWalk.cs): step timing, pre-walk window, key and pointer mapping, the drawn offset between tiles,
// the glide chain of server moves and the prediction of the local player's steps. No engine, no clock: the times are given.
using System;

namespace Chaos.Core.Tests
{
    static class SmoothWalkTests
    {
        static bool Near(double a, double b, double eps = 1e-3) { return Math.Abs(a - b) <= eps; }

        public static void Run(Action<bool, string> check)
        {
            // ---- step timing: one diagonal constant, rounded the way the server rounds
            check(WalkTiming.DiagonalNum == 141 && WalkTiming.DiagonalDen == 100, "timing: the diagonal factor is sqrt(2) as 141 / 100");
            check(WalkTiming.Scale(300, false, true) == 300 && WalkTiming.Scale(300, true, true) == 430, "timing: player step 300 ms, diagonal 423 rounds up to 430");
            check(WalkTiming.Scale(300, true, false) == 450 && WalkTiming.Scale(310, false, false) == 350, "timing: other creatures round up to the 50 ms beat");
            check(WalkTiming.Scale(1, false, true) == 10 && WalkTiming.Scale(99999, true, true) == 5000, "timing: step clamps to 10 ms .. 5000 ms");
            check(Near(WalkTiming.Lead(300), 90) && Near(WalkTiming.Lead(100), 60), "pre-walk: lead 90 ms, at most 60% of a short step");

            // ---- the pre-walk window
            check(WalkTiming.CanSend(1000, -1, 300, 0), "pre-walk: standing still, a step goes at once");
            check(!WalkTiming.CanSend(1000, 1300, 300, 1) && WalkTiming.CanSend(1215, 1300, 300, 1), "pre-walk: the next step goes 90 ms before the glide ends");
            check(!WalkTiming.CanSend(1300, 1300, 300, WalkTiming.MaxPending), "pre-walk: never more than MaxPending steps in flight");

            // ---- keys: two held keys make a diagonal
            check(WalkInput.FromMask(WalkInput.Up | WalkInput.Right) == Dir.NorthEast && WalkInput.FromMask(WalkInput.Down | WalkInput.Left) == Dir.SouthWest, "keys: W+D is north-east, S+A south-west");
            check(WalkInput.FromMask(WalkInput.Up | WalkInput.Left) == Dir.NorthWest && WalkInput.FromMask(WalkInput.Down | WalkInput.Right) == Dir.SouthEast, "keys: W+A north-west, S+D south-east");
            check(WalkInput.FromMask(WalkInput.Up) == Dir.North && WalkInput.FromMask(WalkInput.Left) == Dir.West && WalkInput.FromMask(0) == null, "keys: one key is straight, none is nothing");
            check(WalkInput.FromMask(WalkInput.Up | WalkInput.Down) == null && WalkInput.FromMask(WalkInput.Up | WalkInput.Down | WalkInput.Left) == Dir.West, "keys: opposite keys cancel");
            check(WalkInput.FromMask(WalkInput.NumpadMask(7)) == Dir.NorthWest && WalkInput.FromMask(WalkInput.NumpadMask(9)) == Dir.NorthEast
                  && WalkInput.FromMask(WalkInput.NumpadMask(1)) == Dir.SouthWest && WalkInput.FromMask(WalkInput.NumpadMask(3)) == Dir.SouthEast, "numpad: 7 9 1 3 are diagonals");
            check(WalkInput.FromMask(WalkInput.NumpadMask(8)) == Dir.North && WalkInput.FromMask(WalkInput.NumpadMask(6)) == Dir.East && WalkInput.NumpadMask(5) == -1, "numpad: 8 6 straight, 5 nothing");
            // numpad 9 with W held is still north-east (one more key in the same direction), numpad 8 with D is north-east as well
            check(WalkInput.FromMask(WalkInput.NumpadMask(9) | WalkInput.Up) == Dir.NorthEast && WalkInput.FromMask(WalkInput.NumpadMask(8) | WalkInput.Right) == Dir.NorthEast, "numpad: mixes with the letter keys");

            // ---- the diagonal grace: the first key of a pair does not send a straight step
            var st = new WalkInputState();
            check(st.Update(0, WalkInput.Up) == null && st.Update(20, WalkInput.Up | WalkInput.Right) == Dir.NorthEast, "grace: W then D within 45 ms goes north-east, never north");
            st = new WalkInputState();
            check(st.Update(0, WalkInput.Up) == null && st.Update(50, WalkInput.Up) == Dir.North, "grace: a single key walks straight after 45 ms");
            check(st.Update(60, WalkInput.Up | WalkInput.Right) == Dir.NorthEast && st.Update(70, WalkInput.Right) == Dir.East, "grace: letting a key go acts at once");
            check(st.Update(80, 0) == null && st.Update(90, WalkInput.Left) == null && st.Update(140, WalkInput.Left) == Dir.West, "grace: starts again after all keys were let go");
            st = new WalkInputState();
            check(st.Update(0, WalkInput.NumpadMask(9)) == Dir.NorthEast, "grace: a numpad diagonal needs none");

            // ---- the pointer: 8 sectors of 45 degrees centred on the axes
            check(WalkInput.Sector(10, 0, 40) == null && WalkInput.Sector(0, 40, 40) == null, "pointer: inside the dead zone nothing walks");
            check(WalkInput.Sector(100, 0, 40) == Dir.East && WalkInput.Sector(0, 100, 40) == Dir.North && WalkInput.Sector(-100, 0, 40) == Dir.West && WalkInput.Sector(0, -100, 40) == Dir.South, "pointer: the four axes");
            check(WalkInput.Sector(100, 100, 40) == Dir.NorthEast && WalkInput.Sector(-100, 100, 40) == Dir.NorthWest
                  && WalkInput.Sector(-100, -100, 40) == Dir.SouthWest && WalkInput.Sector(100, -100, 40) == Dir.SouthEast, "pointer: the four diagonals");
            check(WalkInput.Sector(100, 41, 40) == Dir.East && WalkInput.Sector(100, 42, 40) == Dir.NorthEast, "pointer: the border is at 22.5 degrees");
            check(WalkInput.Sector(100, 45, 40, Dir.East) == Dir.East && WalkInput.Sector(100, 60, 40, Dir.East) == Dir.NorthEast, "pointer: a sector holds a few degrees past its edge");
            check(WalkInput.Sector(-100, 5, 40, Dir.West) == Dir.West && WalkInput.Sector(-100, -5, 40, Dir.West) == Dir.West, "pointer: west wraps at 180 degrees");

            // ---- the drawn offset: one glide at constant speed, tile to tile
            var c = new Creature { Id = 1, Position = new Pos(11, 10, 7) };
            c.WalkFrom = new Pos(10, 10, 7); c.WalkStart = 1000; c.WalkMs = 200;
            WalkMath.Drawn(c, 1000, out float x, out float y, out float p);
            check(Near(x, 10) && Near(y, 10) && Near(p, 0), "drawn: at the start of the step it is on the old tile");
            WalkMath.Drawn(c, 1100, out x, out y, out p);
            check(Near(x, 10.5) && Near(y, 10) && Near(p, 0.5), "drawn: half way at half the time");
            WalkMath.Drawn(c, 1200, out x, out y, out p);
            check(Near(x, 11) && Near(y, 10) && Near(p, 1), "drawn: at the end it is on the new tile");
            WalkMath.Drawn(c, 900, out x, out y, out p);
            check(Near(x, 10) && Near(p, 0), "drawn: a step that starts later holds the old tile (a chained step)");
            c.WalkFrom = new Pos(10, 11, 7); c.WalkMs = 430;   // a diagonal: both axes move together
            WalkMath.Drawn(c, 1215, out x, out y, out p);
            check(Near(x, 10.5, 0.01) && Near(y, 10.5, 0.01), "drawn: a diagonal moves both axes at the same rate");
            c.WalkStart = -1;
            WalkMath.Drawn(c, 5000, out x, out y, out p);
            check(Near(x, 11) && Near(y, 10) && Near(p, 1), "drawn: standing creature is on its tile");

            // ---- the glide chain: steps join without a stop
            check(WalkChain.Start(-1, 5000, 200) == 5000, "chain: the first step starts on arrival");
            check(WalkChain.Start(5100, 5000, 200) == 5100, "chain: an early move waits for the last glide to end, no overlap");
            check(WalkChain.Start(9000, 5000, 200) == 5200, "chain: the wait is never longer than one step");
            check(WalkChain.Start(5000, 5030, 200) == 5000, "chain: a move 30 ms late catches up to the end of the last glide");
            check(WalkChain.Start(5000, 5200, 200) == 5200, "chain: a move far too late starts on arrival (a real stop)");
            check(WalkChain.Start(5000, 5050, 100) == 5050 && WalkChain.Start(5000, 5025, 100) == 5000, "chain: the catch-up cap is 25% of a short step");

            // a creature that walks with a move every 200 ms, arrivals jittered up to 40 ms, never stands: sample the drawn x every 5 ms
            var w = new Creature { Id = 2, Position = new Pos(100, 50, 7) };
            double[] jitter = { 0, -35, -20, -15, -40, -10, -25, 0, -30, -30 };   // moves on time or early
            double maxStall = 0, lastMoved = 0, lastX = 100, t0 = 0;
            double prevEnd = -1;
            int step = 0;
            double nextArrival = 0;
            for (double t = 0; t <= 2200; t += 5)
            {
                if (step < jitter.Length && t >= nextArrival)
                {
                    var from = w.Position;
                    w.Position = from.Offset(1, 0);
                    double start = WalkChain.Start(prevEnd, t, 200);
                    WalkChain.Apply(w, from, start, 200, t);
                    prevEnd = start + 200;
                    step++;
                    nextArrival = step * 200 + (step < jitter.Length ? jitter[step] : 0);
                }
                WalkMath.Drawn(w, t, out x, out y, out p);
                if (t == 0) { t0 = t; lastX = x; lastMoved = t; continue; }
                if (x > lastX + 1e-6) { maxStall = Math.Max(maxStall, t - lastMoved); lastMoved = t; }
                lastX = x;
                if (t > 2100) break;
            }
            check(maxStall <= 10, "glide: a creature stepping every 200 ms with moves on time or early never stands more than 10 ms (" + maxStall + ")");
            check(t0 == 0, "glide: sampled from the start");

            // ---- prediction of the local player
            var me = new Creature { Id = 7, Position = new Pos(50, 50, 7) };
            var sp = new StepPredictor();
            check(sp.EndTime(me) < 0 && sp.Count == 0, "predict: nothing sent, nothing to wait for");
            var s1 = sp.Add(me, Dir.East, 1000, 200, true);
            check(s1.From == new Pos(50, 50, 7) && s1.To == new Pos(51, 50, 7) && s1.Start == 1000 && sp.EndTime(me) == 1200, "predict: the first step glides from the moment it is sent");
            WalkMath.Drawn(me, 1100, out x, out y, out p);
            check(Near(x, 50.5) && Near(y, 50), "predict: the player is drawn half way before the server answers");
            check(WalkTiming.CanSend(1110, sp.EndTime(me), 200, sp.Count), "predict: the next step goes out inside the window");
            var s2 = sp.Add(me, Dir.NorthEast, 1110, 280, true);
            check(s2.From == new Pos(51, 50, 7) && s2.To == new Pos(52, 49, 7) && s2.Start == 1200 && sp.EndTime(me) == 1480, "predict: the second step chains at the end of the first, from its tile");
            WalkMath.Drawn(me, 1200, out x, out y, out p);
            check(Near(x, 51) && Near(y, 50), "predict: no stop at the tile edge");
            WalkMath.Drawn(me, 1340, out x, out y, out p);
            check(Near(x, 51.5) && Near(y, 49.5), "predict: the diagonal glides after the straight step");
            // the server confirms the first step 40 ms after it was sent
            me.Position = new Pos(51, 50, 7);
            var hit = sp.Confirm(me, new Pos(50, 50, 7), new Pos(51, 50, 7));
            check(hit == s1 && sp.Count == 1 && me.Pred != null && me.Pred.Count == 1, "confirm: the first prediction is matched and dropped");
            me.WalkFrom = new Pos(50, 50, 7); me.WalkStart = hit.Start; me.WalkMs = 200;
            WalkMath.Drawn(me, 1100, out x, out y, out p);
            check(Near(x, 50.5), "confirm: the answer does not move the drawn position (same glide)");
            WalkMath.Drawn(me, 1340, out x, out y, out p);
            check(Near(x, 51.5) && Near(y, 49.5), "confirm: the second step is still drawn ahead");
            me.Position = new Pos(52, 49, 7);
            hit = sp.Confirm(me, new Pos(51, 50, 7), new Pos(52, 49, 7));
            me.WalkFrom = new Pos(51, 50, 7); me.WalkStart = hit.Start; me.WalkMs = 280;
            WalkMath.Drawn(me, 1340, out x, out y, out p);
            check(hit == s2 && sp.Count == 0 && me.Pred == null && Near(x, 51.5) && Near(y, 49.5), "confirm: both answered, the drawn position never jumped");

            // steps in a row at 200 ms: the player never stands, whatever the round trip (60 ms, 150 ms, 400 ms)
            foreach (double rtt in new double[] { 60, 150, 400 })
            {
                var pl = new Creature { Id = 9, Position = new Pos(10, 10, 7) };
                var sq = new StepPredictor();
                double stall = 0, lx = 10, lmv = 0;
                int sent = 0;
                var inflight = new System.Collections.Generic.List<(double at, PredStep s)>();
                for (double t = 0; t <= 3000; t += 5)
                {
                    // answers arriving
                    for (int i = 0; i < inflight.Count; )
                    {
                        if (inflight[i].at <= t)
                        {
                            var ps = inflight[i].s; inflight.RemoveAt(i);
                            var m = sq.Confirm(pl, pl.Position, ps.To);
                            pl.Position = ps.To;
                            if (m != null) WalkChain.Apply(pl, ps.From, m.Start, m.Ms, t);
                        }
                        else i++;
                    }
                    if (sent < 12 && WalkTiming.CanSend(t, sq.EndTime(pl), 200, sq.Count))
                    {
                        var ps = sq.Add(pl, Dir.East, t, 200, true);
                        inflight.Add((t + rtt, ps));
                        sent++;
                    }
                    WalkMath.Drawn(pl, t, out x, out y, out p);
                    if (sent >= 12 && sq.Count == 0 && t > 2600) break;
                    if (x > lx + 1e-6) { if (lmv > 0) stall = Math.Max(stall, t - lmv); lmv = t; }
                    else if (lmv == 0 && x > lx) lmv = t;
                    lx = x;
                    if (lmv == 0 && x > 10) lmv = t;
                }
                check(stall <= 10, "walk: 12 steps in a row, round trip " + rtt + " ms: longest stand " + stall + " ms");
                check(pl.Position.X == 22, "walk: 12 steps in a row, round trip " + rtt + " ms: arrives " + pl.Position.X);
            }

            // a server correction or a teleport clears the prediction
            var q = new Creature { Id = 11, Position = new Pos(5, 5, 7) };
            var sq2 = new StepPredictor();
            sq2.Add(q, Dir.North, 100, 200, true); sq2.Add(q, Dir.North, 150, 200, true);
            check(sq2.Confirm(q, new Pos(5, 5, 7), new Pos(4, 4, 7)) == null && sq2.Count == 0 && q.Pred == null, "reconcile: a move that was not predicted clears the queue");
            sq2.Add(q, Dir.North, 500, 200, true);
            sq2.Clear(q);
            WalkMath.Drawn(q, 550, out x, out y, out p);
            check(sq2.Count == 0 && q.Pred == null && Near(x, 5) && Near(y, 5), "reconcile: a cancel puts the player back on the server's tile");
            sq2.Add(q, Dir.South, 1000, 200, true);
            sq2.Expire(q, 1000 + WalkTiming.GiveUpMs - 1); bool kept = sq2.Count == 1;
            sq2.Expire(q, 1000 + WalkTiming.GiveUpMs + 1);
            check(kept && sq2.Count == 0, "reconcile: an unanswered step is given up after 1.5 s");
            // a step onto a tile the client thinks blocked is sent but not drawn
            var b = new Creature { Id = 12, Position = new Pos(8, 8, 7) };
            var sq3 = new StepPredictor();
            sq3.Add(b, Dir.East, 100, 200, false);
            WalkMath.Drawn(b, 150, out x, out y, out p);
            check(Near(x, 8) && Near(y, 8) && sq3.Count == 1, "predict: a step the client thinks blocked is not drawn");
            // a prediction that no longer starts at the creature's tile is ignored
            var f = new Creature { Id = 13, Position = new Pos(20, 20, 7) };
            var sq4 = new StepPredictor();
            sq4.Add(f, Dir.East, 100, 200, true);
            f.Position = new Pos(30, 30, 7);
            WalkMath.Drawn(f, 150, out x, out y, out p);
            check(Near(x, 30) && Near(y, 30), "predict: after a teleport the stale prediction is not drawn");

            // ---- the parser: a real 0x6D keeps the predicted start, a move of another creature chains
            ParserChecks(check);
        }

        static void ParserChecks(Action<bool, string> check)
        {
            // GameParser.StepMs uses the one diagonal constant for the player and for the others
            var world = new World(DatFile.Parse(Program.SyntheticDat()));
            var parser = new GameParser(world);
            double clock = 0;
            parser.Clock = () => clock;
            var me = new Creature { Id = 1, Position = new Pos(100, 100, 7), Speed = 220 };
            world.Creatures[1] = me; world.PlayerId = 1;
            world.AddThing(me.Position, new Thing { Creature = me });
            double straight = parser.StepMs(me, new Pos(101, 100, 7), false), diag = parser.StepMs(me, new Pos(101, 99, 7), true);
            check(Near(diag / straight, 1.41, 0.04), "parser: the player's diagonal step is 1.41 of a straight one (" + straight + " / " + diag + ")");
            var rat = new Creature { Id = 2, Position = new Pos(105, 100, 7), Speed = 220 };
            world.Creatures[2] = rat;
            double rs = parser.StepMs(rat, new Pos(106, 100, 7), false), rd = parser.StepMs(rat, new Pos(106, 99, 7), true);
            check(Near(rd / rs, 1.41, 0.17), "parser: a creature's diagonal step uses the same factor, on the 50 ms beat (" + rs + " / " + rd + ")");
            // a move of the player the client predicted keeps the predicted start; the next move of a creature chains behind the last glide
            clock = 1000;
            me.Direction = Dir.East;
            var pred = parser.Steps.Add(me, Dir.East, clock, straight, true);
            clock = 1060;
            parser.Parse(new ByteWriter().U8(0x6D).U16(0xFFFF).U32(1).U16(101).U16(100).U8(7).ToArray());
            check(me.Position == new Pos(101, 100, 7) && me.WalkStart == 1000 && me.WalkFrom == new Pos(100, 100, 7) && me.Pred == null,
                  "parser: a predicted step keeps its start (" + me.WalkStart + "), the answer 60 ms later changes nothing");
            parser.Steps.Add(me, Dir.East, clock, straight, true);
            parser.Parse(new ByteWriter().U8(0xB5).U8(1).ToArray());
            check(parser.Steps.Count == 0 && me.Pred == null && me.WalkStart < 0, "parser: a cancel (0xB5) clears the predicted steps");
            clock = 2000;
            parser.Parse(new ByteWriter().U8(0x6D).U16(0xFFFF).U32(2).U16(106).U16(100).U8(7).ToArray());
            double firstEnd = rat.WalkStart + rat.WalkMs;
            clock = 2100;
            parser.Parse(new ByteWriter().U8(0x6D).U16(0xFFFF).U32(2).U16(107).U16(100).U8(7).ToArray());
            check(rat.WalkStart == firstEnd && rat.PrevStart == 2000, "parser: a creature's next move starts when its last glide ends, with no gap (" + rat.WalkStart + " after " + firstEnd + ")");
        }
    }
}
