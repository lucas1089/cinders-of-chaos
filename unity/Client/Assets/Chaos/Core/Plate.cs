// The character plate (client game_chaoshud, hudmath.lua): the numbers of the health, mana and experience bars. It uses no
// extended opcode: health, mana, level, the experience and the percent to the next level are all in the base 0xA0 packet.
using System;
using System.Globalization;

namespace Chaos.Core
{
    public static class Plate
    {
        /// <summary>Width in pixels of a bar fill: 0 for nothing, at least 1 while above 0, never wider than the bar.</summary>
        public static int FillWidth(double value, double max, int width)
        {
            if (max <= 0 || value <= 0 || width <= 0) return 0;
            if (value >= max) return width;
            return Math.Max(1, (int)Math.Floor(width * value / max));
        }

        /// <summary>Whole percent for the "percent" display: rounds down, 1% while above 0, 100% only when full.</summary>
        public static int Percent(double value, double max)
        {
            if (max <= 0 || value <= 0) return 0;
            if (value >= max) return 100;
            return Math.Min(99, Math.Max(1, (int)Math.Floor(value * 100 / max)));
        }

        /// <summary>"15.3k", "2m": the client's short number format.</summary>
        public static string Short(double v)
        {
            if (v >= 1e9) return Trim(v / 1e9) + "b";
            if (v >= 1e6) return Trim(v / 1e6) + "m";
            if (v >= 1e3) return Trim(v / 1e3) + "k";
            return Math.Floor(v).ToString(CultureInfo.InvariantCulture);
        }

        static string Trim(double x)
        {
            string t = (Math.Floor(x * 10) / 10).ToString("0.0", CultureInfo.InvariantCulture);
            return t.EndsWith(".0", StringComparison.Ordinal) ? t.Substring(0, t.Length - 2) : t;
        }

        /// <summary>The text of a bar: "15.3k / 20k", or "73%" with the percent option.</summary>
        public static string BarText(double value, double max, bool asPercent) =>
            asPercent ? Percent(value, max) + "%" : Short(value) + " / " + Short(max);

        /// <summary>The experience a level needs: 50/3 (L^3 - 6 L^2 + 17 L - 12), as in the stock formula.</summary>
        public static ulong ExperienceFor(int level)
        {
            if (level <= 1) return 0;
            double l = level;
            return (ulong)Math.Floor(50.0 / 3.0 * (l * l * l - 6 * l * l + 17 * l - 12));
        }

        /// <summary>Percent of the way from this level to the next (0-100), by the formula. The server sends its own in 0xA0; this is the check and the fallback.</summary>
        public static int ExperiencePercent(ulong experience, int level)
        {
            ulong lo = ExperienceFor(level), hi = ExperienceFor(level + 1);
            if (hi <= lo || experience <= lo) return 0;
            if (experience >= hi) return 100;
            return (int)Math.Min(100UL, (experience - lo) * 100 / (hi - lo));
        }

        /// <summary>Experience still missing to the next level (0 when above it).</summary>
        public static ulong ExperienceToNext(ulong experience, int level)
        {
            ulong hi = ExperienceFor(level + 1);
            return experience >= hi ? 0 : hi - experience;
        }

        /// <summary>The percent to show: the server's, kept inside 0-100.</summary>
        public static int LevelPercent(int fromServer) => Math.Max(0, Math.Min(100, fromServer));
    }
}
