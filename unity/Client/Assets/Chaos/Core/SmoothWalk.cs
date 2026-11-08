// Smooth 8-direction walking (phase 18, track M1). Pure: no engine API, tested in Core.Tests/SmoothWalkTests.cs.
//   * WalkTiming: the diagonal step factor (one constant), the pre-walk window.
//   * WalkInput / WalkInputState: held keys and the pointer to one of 8 directions.
//   * WalkMath: where a creature is drawn (the confirmed step, or the predicted ones not yet confirmed).
//   * WalkChain: when a step the server confirmed starts to glide, so steps join without a stop.
//   * StepPredictor: the local player's steps sent and not yet confirmed (client side prediction).
// Why walking hitched: a step was sent only after the server answered the last one and the animation had ended, and the glide of a step
// began when its answer arrived. Every step cost one round trip of standing still. Now the next step goes out a little before the
// current one ends, the player glides at once from the prediction, and the server's answer only reconciles.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class WalkTiming
    {
        /// <summary>A diagonal step takes DiagonalNum / DiagonalDen of a straight one (about sqrt(2), the length of the way). The server's side is
        /// PLAYER_DIAGONAL_STEP_NUM / _DEN of server/src-patches/0018-movement-speed.patch; track M2 of phase 18 moves it to 141 / 100 in a later
        /// numbered patch, and these two numbers follow it. Nothing else in the client holds a diagonal factor.</summary>
        public const long DiagonalNum = 141, DiagonalDen = 100;

        /// <summary>The server rounds a player's step up to 10 ms, the others' to its 50 ms beat.</summary>
        public const int PlayerRounding = 10, OtherRounding = 50;

        /// <summary>The next step goes out this long before the current glide ends (the pre-walk window), but never earlier than this share of a step.</summary>
        public const double PreWalkLeadMs = 90, PreWalkMaxShare = 0.6;

        /// <summary>Steps sent and not confirmed yet, at most (the server holds the next one of a walking player).</summary>
        public const int MaxPending = 2;

        /// <summary>Unanswered steps are given up after this long.</summary>
        public const double GiveUpMs = 1500;

        public static long Scale(long straightMs, bool diagonal, bool player)
        {
            long ms = straightMs;
            if (diagonal) ms = ms * DiagonalNum / DiagonalDen;
            int step = player ? PlayerRounding : OtherRounding;
            ms = (ms + step - 1) / step * step;
            return Math.Max(step, Math.Min(5000, ms));
        }

        public static double Lead(double stepMs) { return Math.Min(PreWalkLeadMs, stepMs * PreWalkMaxShare); }

        /// <summary>True when the next step may go: nothing is predicted past `endMs` minus the lead, and fewer than MaxPending are out.</summary>
        public static bool CanSend(double now, double endMs, double stepMs, int pending)
        {
            return pending < MaxPending && now >= endMs - Lead(stepMs);
        }
    }

    public static class WalkInput
    {
        public const int Up = 1, Down = 2, Left = 4, Right = 8;

        /// <summary>Two held keys make a diagonal; opposite keys cancel; null when nothing is held.</summary>
        public static Dir? FromMask(int mask)
        {
            bool u = (mask & Up) != 0, d = (mask & Down) != 0, l = (mask & Left) != 0, r = (mask & Right) != 0;
            if (u && d) { u = false; d = false; }
            if (l && r) { l = false; r = false; }
            if (u && l) return Dir.NorthWest;
            if (u && r) return Dir.NorthEast;
            if (d && l) return Dir.SouthWest;
            if (d && r) return Dir.SouthEast;
            if (u) return Dir.North;
            if (d) return Dir.South;
            if (l) return Dir.West;
            if (r) return Dir.East;
            return null;
        }

        /// <summary>The mask of a numpad key: 7 9 1 3 are the diagonals, 8 2 4 6 the straight ones; -1 for another digit.</summary>
        public static int NumpadMask(int digit)
        {
            switch (digit)
            {
                case 7: return Up | Left;
                case 8: return Up;
                case 9: return Up | Right;
                case 4: return Left;
                case 6: return Right;
                case 1: return Down | Left;
                case 2: return Down;
                case 3: return Down | Right;
                default: return -1;
            }
        }

        /// <summary>The pointer keeps its sector while it stays within this many degrees of the sector's edge, so it does not flicker on a border.</summary>
        public const double HysteresisDeg = 6;

        /// <summary>The direction towards a vector (x right, y up, as the screen centre to the pointer), in 8 sectors of 45 degrees centred on the
        /// axes. `prev` is the sector of the last frame. Null inside the dead zone.</summary>
        public static Dir? Sector(double x, double y, double dead, Dir? prev = null)
        {
            if (Math.Sqrt(x * x + y * y) <= dead) return null;
            double a = Math.Atan2(y, x) * 180.0 / Math.PI;
            if (prev.HasValue)
            {
                double c = CenterDeg(prev.Value);
                double diff = Math.Abs(((a - c + 540) % 360 + 360) % 360 - 180);
                if (diff <= 22.5 + HysteresisDeg) return prev;
            }
            int oct = (int)Math.Round(a / 45.0);
            switch (oct)
            {
                case 0: return Dir.East;
                case 1: return Dir.NorthEast;
                case 2: return Dir.North;
                case 3: return Dir.NorthWest;
                case -1: return Dir.SouthEast;
                case -2: return Dir.South;
                case -3: return Dir.SouthWest;
                default: return Dir.West;
            }
        }

        static double CenterDeg(Dir d)
        {
            switch (d)
            {
                case Dir.East: return 0;
                case Dir.NorthEast: return 45;
                case Dir.North: return 90;
                case Dir.NorthWest: return 135;
                case Dir.West: return 180;
                case Dir.SouthWest: return -135;
                case Dir.South: return -90;
                default: return -45;
            }
        }
    }

    /// <summary>Held keys to a direction over time. Pressing two keys for a diagonal is never exactly at once: the first key alone would send a
    /// straight step, so a straight direction that has just started waits GraceMs for the second key. Later changes (a key let go) act at once.</summary>
    public sealed class WalkInputState
    {
        public const double GraceMs = 45;
        double risen = -1;

        public Dir? Update(double now, int mask)
        {
            var d = WalkInput.FromMask(mask);
            if (d == null) { risen = -1; return null; }
            if (risen < 0) risen = now;
            if (!WalkDirs.Diagonal(d.Value) && now - risen < GraceMs) return null;
            return d;
        }
    }

    /// <summary>A step sent and not confirmed: the local player's prediction.</summary>
    public sealed class PredStep
    {
        public Dir Dir;
        public Pos From, To;
        public double Start, Ms, SentAt;
        /// <summary>False when the client thought the tile blocked: sent all the same, but not drawn before the server says yes.</summary>
        public bool Drawn;
    }

    public static class WalkMath
    {
        /// <summary>The two tiles a creature is between and how far (0..1) it is, at `now`. A step the server has not confirmed yet is drawn as well
        /// (Creature.Pred), so the player glides without waiting for the answer.</summary>
        public static void Between(Creature c, double now, out Pos from, out Pos to, out float u)
        {
            var preds = c.Pred;
            if (preds != null && preds.Count > 0 && preds[0].Drawn && preds[0].From == c.Position)
            {
                PredStep seg = null;
                for (int i = 0; i < preds.Count; i++)
                {
                    if (!preds[i].Drawn || preds[i].Start > now) break;
                    seg = preds[i];
                }
                if (seg != null)
                {
                    from = seg.From; to = seg.To;
                    u = (float)Math.Max(0.0, Math.Min(1.0, (now - seg.Start) / Math.Max(1.0, seg.Ms)));
                    return;
                }
            }
            from = c.Position; to = c.Position; u = 1f;
            if (c.WalkStart >= 0 && c.WalkMs > 0 && c.WalkFrom.Z == c.Position.Z)
            {
                double p = (now - c.WalkStart) / c.WalkMs;
                if (p < 0 && c.PrevStart >= 0 && c.PrevMs > 0)
                {
                    // the next glide waits for the one before it: that one is still going
                    double pp = (now - c.PrevStart) / c.PrevMs;
                    if (pp < 1) { from = c.PrevFrom; to = c.WalkFrom; u = (float)Math.Max(0.0, pp); return; }
                }
                if (p < 0) p = 0;
                if (p < 1)
                {
                    from = c.WalkFrom; u = (float)p;
                }
            }
        }

        /// <summary>The drawn position in tiles (x east, y south) and the progress of the step (1 when standing).</summary>
        public static void Drawn(Creature c, double now, out float x, out float y, out float progress)
        {
            Between(c, now, out Pos from, out Pos to, out progress);
            x = from.X + (to.X - from.X) * progress;
            y = from.Y + (to.Y - from.Y) * progress;
            if (from == to) { x = to.X; y = to.Y; progress = 1f; }
        }
    }

    public static class WalkChain
    {
        /// <summary>The cap of the catch-up, as a share of the step and in ms: a step that arrives a little late starts that much in the past.</summary>
        public const double CatchUpShare = 0.25, CatchUpMaxMs = 60;

        /// <summary>When the glide of a step the server just confirmed starts. `prevEnd` is when the creature's last glide ends (negative: none),
        /// `arrival` when the move came in. A step that comes before the last glide ended waits for its end (no overlap, no jump); one that comes a little
        /// late starts at the end of the last glide, as far as the cap says (the creature catches up a few pixels instead of standing); later than that
        /// it starts on arrival. The wait is never longer than one step.</summary>
        public static double Start(double prevEnd, double arrival, double stepMs)
        {
            if (prevEnd < 0) return arrival;
            if (prevEnd >= arrival) return Math.Min(prevEnd, arrival + stepMs);
            double late = arrival - prevEnd;
            double cap = Math.Min(CatchUpMaxMs, stepMs * CatchUpShare);
            return late <= cap ? prevEnd : arrival;
        }

        /// <summary>Sets the glide of a confirmed move. The glide that is still going (the new one waits for it) is kept as the previous one.</summary>
        public static void Apply(Creature c, Pos from, double start, double ms, double now)
        {
            double oldEnd = EndOf(c);
            if (start > now && oldEnd > now) { c.PrevFrom = c.WalkFrom; c.PrevStart = c.WalkStart; c.PrevMs = c.WalkMs; }
            else c.PrevStart = -1;
            c.WalkFrom = from; c.WalkStart = start; c.WalkMs = ms;
        }

        public static double EndOf(Creature c)
        {
            return c.WalkStart >= 0 && c.WalkMs > 0 ? c.WalkStart + c.WalkMs : -1;
        }
    }

    /// <summary>The steps of the local player sent and not yet confirmed. The session sends a step when CanSend says so, the parser tells each
    /// 0x6D of the player, and anything that does not fit (a cancel, a teleport, a floor change, no answer) clears it.</summary>
    public sealed class StepPredictor
    {
        readonly List<PredStep> q = new List<PredStep>();
        public int Count => q.Count;

        /// <summary>When everything sent so far ends its glide (negative: nothing to wait for).</summary>
        public double EndTime(Creature me)
        {
            if (q.Count > 0) { var l = q[q.Count - 1]; return l.Start + l.Ms; }
            return WalkChain.EndOf(me);
        }

        /// <summary>The tile the next step starts from.</summary>
        public Pos Tip(Creature me) { return q.Count > 0 ? q[q.Count - 1].To : me.Position; }

        public PredStep Add(Creature me, Dir d, double now, double stepMs, bool drawn)
        {
            var from = Tip(me);
            var to = WalkDirs.Step(from, d);
            double end = EndTime(me);
            var s = new PredStep { Dir = d, From = from, To = to, Start = Math.Max(now, end), Ms = stepMs, SentAt = now, Drawn = drawn };
            q.Add(s);
            Publish(me);
            return s;
        }

        /// <summary>A move of the player came in. Returns the matching prediction (older ones are dropped with it) or null: then nothing was predicted
        /// for this step and the queue is cleared, the server's way wins.</summary>
        public PredStep Confirm(Creature me, Pos from, Pos to)
        {
            for (int i = 0; i < q.Count; i++)
            {
                if (q[i].To == to && q[i].From == from)
                {
                    var hit = q[i];
                    q.RemoveRange(0, i + 1);
                    Publish(me);
                    return hit;
                }
            }
            q.Clear();
            Publish(me);
            return null;
        }

        public void Publish(Creature me)
        {
            if (me != null) me.Pred = q.Count > 0 ? new List<PredStep>(q) : null;
        }

        public void Clear(Creature me)
        {
            q.Clear();
            Publish(me);
        }

        /// <summary>Drops steps nobody answered.</summary>
        public void Expire(Creature me, double now)
        {
            if (q.Count > 0 && now - q[0].SentAt > WalkTiming.GiveUpMs) Clear(me);
        }
    }
}
