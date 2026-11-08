// Eased bars of the character plate (phase 6, track V; client game_chaoshud hudbars_logic.lua, O229). The same timing as the bars over creatures:
//   a bar eases to a new value in EaseMs (ease-out) and reaches it exactly;
//   a fall leaves a pale chip from where the bar stood (or where the chip on screen is) to the new value: it holds HoldMs, then slides down in SlideMs (smoothstep);
//   a rise eases up with no chip and drops an open chip;
//   the first value is taken at once (no slide in from 0 at the login).
// Values are percents (0-100); times are milliseconds on any clock the caller keeps. Nothing runs by itself: Shown and ChipAt are computed from the clock.
using System;

namespace Chaos.Core
{
    public sealed class HudBarTrack
    {
        public const double EaseMs = 150, HoldMs = 250, SlideMs = 300;

        bool valid;
        double from, target, chip, easeStart, chipStart, lastSeen;

        static double EaseOut(double u) { u = Math.Max(0, Math.Min(1, u)); double r = 1 - u; return 1 - r * r; }
        static double SmoothStep(double u) { u = Math.Max(0, Math.Min(1, u)); return u * u * (3 - 2 * u); }

        public void Reset() { valid = false; }

        public double Shown(double now)
        {
            if (!valid) return target;
            double el = now - easeStart;
            if (el >= EaseMs) return target;
            if (el <= 0) return from;
            return from + (target - from) * EaseOut(el / EaseMs);
        }

        public double ChipAt(double now)
        {
            double s = Shown(now);
            if (!valid) return s;
            double el = now - chipStart, c;
            if (el <= HoldMs) c = chip;
            else if (el >= HoldMs + SlideMs) c = target;
            else c = chip + (target - chip) * SmoothStep((el - HoldMs) / SlideMs);
            return c < s ? s : c;
        }

        public bool Settled(double now) => Shown(now) == target && ChipAt(now) == target;

        /// <summary>The value now; a number for staleMs also takes it at once when the bar was not observed for that long (the plate passes none).</summary>
        public void Observe(double value, double now, double staleMs = -1)
        {
            if (!valid || now < lastSeen || (staleMs >= 0 && now - lastSeen > staleMs))
            {
                valid = true;
                from = target = chip = value;
                easeStart = chipStart = lastSeen = now;
                return;
            }
            lastSeen = now;
            if (value == target) return;
            double cur = Shown(now), chipNow = ChipAt(now);
            from = cur; target = value; easeStart = chipStart = now;
            chip = value < cur ? Math.Max(chipNow, cur) : cur;
        }

        /// <summary>The pixel widths to draw at `now`: the fill and the chip (never narrower than the fill). A bar at rest draws Plate.FillWidth(value, max, width) exactly.</summary>
        public void Widths(double value, double max, int width, double now, out int fillPx, out int chipPx, out bool settled)
        {
            if (Settled(now)) { fillPx = chipPx = Plate.FillWidth(value, max, width); settled = true; return; }
            fillPx = Plate.FillWidth(Shown(now), 100, width);
            chipPx = Math.Max(fillPx, Plate.FillWidth(ChipAt(now), 100, width));
            settled = false;
        }

        /// <summary>value / max as a percent (0 without a max, 100 when full).</summary>
        public static double Percent(double value, double max)
        {
            if (max <= 0 || value <= 0) return 0;
            return value >= max ? 100 : value * 100 / max;
        }
    }
}
