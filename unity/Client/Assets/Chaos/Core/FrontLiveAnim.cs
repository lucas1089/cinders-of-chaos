// Front-art creatures, what a live creature is doing (pure C#, tested in Core.Tests/FrontLooksTests.cs). The server tells only places:
// a creature's tile, the tile it came from and the step time (Creature.WalkFrom / WalkMs), its direction and its health percentage.
// From that this state machine makes: smooth movement between tiles, idle / walk / attack clips, the facing, a swing when a creature
// stands next to a foe, and a flinch (pushed back a little, a red flash) when its health drops.
// It runs on its own clock (seconds), so it never needs the game's clock: a new step is told by the creature's WalkStart changing.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public enum FcClip { Idle, Walk, Attack }

    public sealed class FrontCreatureState
    {
        public const float StepMinMs = 60f;
        public const float AttackEvery = 2.0f;   // seconds between swings of a creature that stands next to a foe
        public const float Swing = 0.75f;        // the attack clip (9 frames at 12)
        public const float HitAt = 0.4f;         // the blow lands this far into the swing
        public const float FlinchTime = 0.3f;
        public const float Knock = 0.16f;        // the push back at the peak, in tiles
        public const float Lean = 0.12f;         // a picture without an attack clip leans into its swing this far
        public const float SnapTiles = 1.6f;     // a new step starting farther than this from where the picture is snaps

        // inputs seen last
        bool started;
        Pos lastPos;
        int lastHp;
        double lastWalkStart = -1;
        // the step going on
        bool stepActive;
        float fromX, fromY;
        double stepStart, stepDur;
        // the swing
        double swingStart = -1, nextSwing;
        float swingFx, swingFz;
        // the flinch
        double flinchStart = -1;
        float pushX, pushZ;

        // outputs, valid after Update
        public uint Id;
        /// <summary>Where the picture stands: tile coordinates, fractional between tiles (x east, y south).</summary>
        public float X, Y;
        /// <summary>The unit heading on the ground (x east, z north).</summary>
        public float FaceX, FaceZ;
        public FcClip Clip;
        public bool Walking;
        /// <summary>0..1 through the step while walking; 0..1 through the swing while attacking.</summary>
        public float WalkU, SwingU;
        /// <summary>Seconds the going step takes.</summary>
        public float StepSeconds;
        /// <summary>The blow of the swing has landed (SwingU past HitAt / Swing).</summary>
        public bool Blow;
        /// <summary>How hard it flinches: 0 none, 1 the peak; and the push at that moment, in tiles (x east, z north).</summary>
        public float Flinch, PushX, PushZ;
        /// <summary>The picture's offset from its place: the push of a flinch and the lean of a swing, in tiles (x east, z north).</summary>
        public float OffX, OffZ;
        public bool Dead;

        public FrontCreatureState(uint id)
        {
            Id = id;
        }

        static float Hash01(uint id)
        {
            unchecked
            {
                uint h = id * 2654435761u + 0x9E3779B9u;
                h ^= h >> 15; h *= 0x85EBCA6Bu; h ^= h >> 13;
                return (h & 0xFFFFFF) / (float)0x1000000;
            }
        }

        /// <summary>True when b is on a's floor and a tile or less away (not the same tile).</summary>
        public static bool Adjacent(Pos a, Pos b)
        {
            if (a.Z != b.Z) return false;
            int dx = Math.Abs(a.X - b.X), dy = Math.Abs(a.Y - b.Y);
            return Math.Max(dx, dy) == 1;
        }

        /// <summary>Forces a swing now (a damage effect that lands next to the creature, once the protocol parser tells those).</summary>
        public void Strike(double t)
        {
            if (swingStart >= 0 && t - swingStart < Swing) return;
            swingStart = t;
            nextSwing = Math.Max(nextSwing, t + AttackEvery * 0.5);
        }

        /// <summary>Moves the machine to time `t` (seconds, its own clock) with what the creature is now. `foe` is the creature it fights,
        /// or null: the nearest one of the other side standing next to it, or the target the player picked.</summary>
        public void Update(double t, Creature c, Creature foe)
        {
            if (!started)
            {
                started = true;
                lastPos = c.Position; lastHp = c.HealthPercent; lastWalkStart = c.WalkStart;
                X = c.Position.X; Y = c.Position.Y;
                nextSwing = t + Hash01(c.Id) * AttackEvery;
            }
            // ---- movement
            if (c.Position != lastPos)
            {
                bool step = c.WalkStart >= 0 && c.WalkStart != lastWalkStart && c.WalkMs > 0 && c.WalkFrom.Z == c.Position.Z
                            && Math.Max(Math.Abs(c.WalkFrom.X - c.Position.X), Math.Abs(c.WalkFrom.Y - c.Position.Y)) <= 1;
                if (step)
                {
                    // start from where the picture is, unless that is far from where the server says the step began
                    float sx = c.WalkFrom.X, sy = c.WalkFrom.Y;
                    {
                        float dx = X - sx, dy = Y - sy;
                        if (dx * dx + dy * dy > SnapTiles * SnapTiles) { X = sx; Y = sy; }
                    }
                    fromX = X; fromY = Y;
                    stepStart = t;
                    stepDur = Math.Max(StepMinMs, c.WalkMs) / 1000.0;
                    stepActive = true;
                }
                else { stepActive = false; X = c.Position.X; Y = c.Position.Y; }
                lastPos = c.Position;
            }
            lastWalkStart = c.WalkStart;
            if (stepActive)
            {
                double u = (t - stepStart) / stepDur;
                if (u >= 1.0) { stepActive = false; X = c.Position.X; Y = c.Position.Y; WalkU = 1f; }
                else
                {
                    WalkU = (float)u;
                    X = fromX + (c.Position.X - fromX) * WalkU;
                    Y = fromY + (c.Position.Y - fromY) * WalkU;
                }
            }
            else { X = c.Position.X; Y = c.Position.Y; }
            Walking = stepActive;
            StepSeconds = (float)stepDur;
            if (!Walking) WalkU = 0f;

            // ---- facing: the heading of the step, the server's direction otherwise, the foe while swinging
            FrontLooks.Face(c.Direction, out FaceX, out FaceZ);

            // ---- attack: a creature that stands next to a foe swings every AttackEvery seconds
            bool engaged = foe != null && !Walking && Adjacent(c.Position, foe.Position) && c.HealthPercent > 0;
            if (engaged && t >= nextSwing && (swingStart < 0 || t - swingStart >= Swing))
            {
                swingStart = t;
                nextSwing = t + AttackEvery;
            }
            bool swinging = swingStart >= 0 && t - swingStart < Swing && !Walking;
            if (swinging)
            {
                SwingU = (float)((t - swingStart) / Swing);
                if (foe != null && Adjacent(c.Position, foe.Position))
                {
                    float fx = foe.Position.X - c.Position.X, fz = -(foe.Position.Y - c.Position.Y), n = (float)Math.Sqrt(fx * fx + fz * fz);
                    swingFx = fx / n; swingFz = fz / n;
                }
                else if (swingFx == 0f && swingFz == 0f) { swingFx = FaceX; swingFz = FaceZ; }
                FaceX = swingFx; FaceZ = swingFz;
            }
            else { SwingU = -1f; swingFx = swingFz = 0f; if (swingStart >= 0 && t - swingStart >= Swing) swingStart = -1; }
            Blow = swinging && SwingU >= HitAt / Swing;

            // ---- flinch: health went down
            if (c.HealthPercent < lastHp)
            {
                flinchStart = t;
                float px = -FaceX, pz = -FaceZ;
                if (foe != null && foe.Position != c.Position)
                {
                    px = c.Position.X - foe.Position.X; pz = -(c.Position.Y - foe.Position.Y);
                }
                float n = (float)Math.Sqrt(px * px + pz * pz);
                pushX = n > 1e-4f ? px / n : 0f; pushZ = n > 1e-4f ? pz / n : 0f;
            }
            lastHp = c.HealthPercent;
            Flinch = 0f; PushX = 0f; PushZ = 0f;
            if (flinchStart >= 0)
            {
                double u = (t - flinchStart) / FlinchTime;
                if (u >= 0.0 && u < 1.0)
                {
                    Flinch = (float)Math.Sin(Math.PI * u);
                    PushX = pushX * Knock * Flinch; PushZ = pushZ * Knock * Flinch;
                }
                else if (u >= 1.0) flinchStart = -1;
            }
            OffX = PushX; OffZ = PushZ;
            if (swinging)
            {
                float k = (float)Math.Sin(Math.PI * Math.Min(1.0, SwingU * 1.6)) * Lean;
                OffX += swingFx * k; OffZ += swingFz * k;
            }
            Clip = swinging ? FcClip.Attack : Walking ? FcClip.Walk : FcClip.Idle;
        }
    }

    /// <summary>Who fights whom, from places only: a monster fights the players and own summons next to it, a player or a summon fights the
    /// monsters next to it, a townsperson fights no one.</summary>
    public static class FrontTargets
    {
        public static bool Hostile(Creature a, Creature b)
        {
            if (a == null || b == null || a == b) return false;
            bool aMon = a.Type == 1, bMon = b.Type == 1;
            if (a.Type == 2 || b.Type == 2) return false;
            return aMon != bMon;
        }

        /// <summary>The foe of `c` among the creatures: `preferred` (the target the local player picked, by id, 0 none) when it is next to
        /// `c`, else the nearest hostile creature next to it (ties: the lower id). Null when there is none.</summary>
        public static Creature Foe(IEnumerable<Creature> all, Creature c, uint preferred)
        {
            Creature best = null;
            float bd = float.MaxValue;
            foreach (var o in all)
            {
                if (!Hostile(c, o) || !FrontCreatureState.Adjacent(c.Position, o.Position)) continue;
                if (preferred != 0 && o.Id == preferred) return o;
                int dx = c.Position.X - o.Position.X, dy = c.Position.Y - o.Position.Y;
                float d = dx * dx + dy * dy + o.Id * 1e-9f;   // the straight neighbour before the diagonal one
                if (d < bd) { bd = d; best = o; }
            }
            return best;
        }
    }

    /// <summary>Which frame of a strip is shown.</summary>
    public static class FrontFrames
    {
        public const float IdleFps = 8f, WalkFps = 10f, RunFps = 16f;

        /// <summary>The frame of a clip: an attack plays once through its frames by `swingU`; idle and walk loop at their rate, a fast
        /// stepper (a step under 330 ms) runs, and `phase` (frames) shifts one creature against the next.</summary>
        public static int Index(FcClip clip, int frames, double t, float swingU, float stepSeconds, int phase)
        {
            if (frames <= 1) return 0;
            if (clip == FcClip.Attack) return Math.Max(0, Math.Min(frames - 1, (int)(Math.Max(0f, swingU) * frames)));
            float fps = clip == FcClip.Walk ? (stepSeconds < 0.33f ? RunFps : WalkFps) : IdleFps;
            int f = ((int)Math.Floor(t * fps) + phase) % frames;
            return f < 0 ? f + frames : f;
        }
    }
}
