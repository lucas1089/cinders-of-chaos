// Typed damage numbers (main client: game_damagescatter/scatterlogic.lua; server: src-patch 0051 typed impact numbers, feature 155).
// A client with capability bit 7 gets three more fields in every damage, heal and experience text message (0xB4, kinds 23..29), after the
// value / colour pairs and before the text: u16 percent (the value as a share of the target's maximum health, x100, rounded up), u8 type
// (ImpactType) and u32 creature id (the creature the number belongs to; 0: the number stays on its tile). GameParser.TextMessage reads them.
// This file keeps the rules of the scatter: every number rises on the same line, so an area hit or a group hunt stacks them into one
// column; a roll shifts a number by a few pixels, changes its speed and gives it a drift. The texts of one hit (physical and element side
// by side) share one roll. Pure C#, no engine calls (Core.Tests/HelperTests.cs).
using System;

namespace Chaos.Core
{
    /// <summary>The number types the server sends (TextMessage typeId, ChaosImpactType). 6 and up are free for scripts.</summary>
    public static class ImpactType
    {
        public const int Normal = 0, Critical = 1, Condition = 2, ManaDrain = 3, ManaGain = 4, EnergyShield = 5;
        /// <summary>A critical hit floats a little slower, so it is read.</summary>
        public const float CritSpeed = 0.85f;
        public const float CritSize = 1.35f, ConditionSize = 0.7f;
    }

    /// <summary>The scatter options of the logged-in character (main client: g_settings node chaosDamageScatter, key "world/name"): on or off and
    /// the strength Subtle, Normal, Wide. The Options window edits Current, the live view reads it each frame.</summary>
    public static class ScatterPrefs
    {
        public const string Pref = "chaos.damagescatter.";
        public static ScatterSettings Current = ScatterSettings.Default;
        public static readonly string[] LevelNames = { "Subtle", "Normal", "Wide" };

        /// <summary>The PlayerPrefs key of a character (lower case), null without a name.</summary>
        public static string Key(string name) => string.IsNullOrEmpty(name) ? null : Pref + name.ToLowerInvariant();

        /// <summary>A stored value (JSON {enabled, level}, or anything) as settings; defaults for what is missing or hand-edited.</summary>
        public static ScatterSettings Read(string json)
        {
            object o = string.IsNullOrEmpty(json) ? null : Json.TryParse(json);
            bool? enabled = Json.Get(o, "enabled") is bool b ? b : (bool?)null;
            double? level = Json.Get(o, "level") is double d ? d : (double?)null;
            return DamageScatter.Sanitize(enabled, level);
        }

        public static string Write(ScatterSettings s)
        {
            var d = DamageScatter.Sanitize(s.Enabled, s.Level);
            return Json.Serialize(new System.Collections.Generic.Dictionary<string, object> { { "enabled", d.Enabled }, { "level", d.Level } });
        }

        public static string LevelName(int level) => Loc.T(LevelNames[Math.Max(1, Math.Min(DamageScatter.Levels, level)) - 1]);
    }

    public struct ScatterSettings
    {
        public bool Enabled;
        public int Level;   // 1 .. Levels
        public static ScatterSettings Default => new ScatterSettings { Enabled = true, Level = 2 };
    }

    /// <summary>One roll: pixel shift (up is negative), speed scale and the drift over the number's life (pixels, up negative).</summary>
    public struct ScatterRoll
    {
        public int Dx, Dy;
        public float Speed;
        public int Sx, Sy;
    }

    public sealed class DamageScatter
    {
        public const int Levels = 3;
        public const double GroupMs = 80;
        // per level: the largest sideways and vertical shift in pixels, how far the speed may stray, the drift sideways and the rise
        static readonly int[] StrX = { 6, 12, 20 }, StrY = { 4, 8, 12 }, DriftX = { 6, 14, 24 }, RiseMin = { 44, 40, 36 }, RiseMax = { 52, 56, 60 };
        static readonly double[] StrSpeed = { 0.08, 0.15, 0.25 };

        public ScatterSettings Settings = ScatterSettings.Default;

        // Park-Miller, a generator of its own so the game's random state is left alone (the Lua one, so the numbers agree)
        long state;
        public DamageScatter(long seed = 1)
        {
            state = (long)(Math.Abs((double)seed) % 2147483647.0);
            if (state == 0) state = 1;
        }

        public double Next()
        {
            state = (state * 16807) % 2147483647;
            return (state - 1) / 2147483646.0;
        }

        public static ScatterSettings Sanitize(bool? enabled, double? level)
        {
            var s = ScatterSettings.Default;
            if (enabled.HasValue) s.Enabled = enabled.Value;
            if (level.HasValue && !double.IsNaN(level.Value) && !double.IsInfinity(level.Value))
                s.Level = Math.Max(1, Math.Min(Levels, (int)Math.Floor(level.Value + 0.5)));
            return s;
        }

        static int Spread(double r, int limit)
        {
            double v = (r * 2 - 1) * limit;
            return v >= 0 ? (int)Math.Floor(v + 0.5) : -(int)Math.Floor(-v + 0.5);
        }

        int Idx => Math.Max(1, Math.Min(Levels, Settings.Level)) - 1;

        /// <summary>One roll for the level: dx, dy in pixels and the speed scale.</summary>
        public void RollShift(out int dx, out int dy, out float speed)
        {
            int i = Idx;
            dx = Spread(Next(), StrX[i]);
            dy = Spread(Next(), StrY[i]);
            speed = (float)(1 + (Next() * 2 - 1) * StrSpeed[i]);
        }

        /// <summary>One drift for the level: sx (pixels sideways over the whole life, either way) and sy (up: negative).</summary>
        public void RollDrift(out int sx, out int sy)
        {
            int i = Idx;
            sx = Spread(Next(), DriftX[i]);
            int rise = RiseMin[i] + (int)Math.Floor(Next() * (RiseMax[i] - RiseMin[i] + 1));
            if (rise > RiseMax[i]) rise = RiseMax[i];
            sy = -rise;
        }

        // group state: the square and time of the last text, and its roll
        int gx, gy, gz;
        double gAt = double.NegativeInfinity;
        ScatterRoll group;
        bool hasDrift;

        bool SameGroup(Pos p, double nowMs) => nowMs - gAt <= GroupMs && gx == p.X && gy == p.Y && gz == p.Z;

        /// <summary>The roll for a number at p at clock nowMs: the group's when the last text was on the same square within GroupMs, else a new
        /// one. Experience floats straight up (no sideways drift), a critical hit a little slower. False when the scatter is off.</summary>
        public bool Pick(Pos p, double nowMs, int type, bool experience, out ScatterRoll roll)
        {
            roll = default(ScatterRoll);
            if (!Settings.Enabled) return false;
            bool same = SameGroup(p, nowMs);
            if (!same)
            {
                int dx, dy; float sp;
                RollShift(out dx, out dy, out sp);
                group = new ScatterRoll { Dx = dx, Dy = dy, Speed = sp };
                gx = p.X; gy = p.Y; gz = p.Z; gAt = nowMs;
                hasDrift = false;
            }
            if (!hasDrift) { int sx, sy; RollDrift(out sx, out sy); group.Sx = sx; group.Sy = sy; hasDrift = true; }
            roll = group;
            if (experience) roll.Sx = 0;
            if (type == ImpactType.Critical) roll.Speed *= ImpactType.CritSpeed;
            return true;
        }
    }
}
