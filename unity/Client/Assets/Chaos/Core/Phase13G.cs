// Phase 13, track G: a window whose rect is mostly hidden by other open windows drawn after it (the last such bug was a confirm window drawn behind its parent). Pure C#, no Unity types.
// The smoke run (ChaosApp.Smoke.cs) gives the rect of the window of a step and the rects of the other open windows that are drawn after it (a later place in the window list is drawn
// above); SmokeCover.Share is the part of the first one they hide, Covered the yes / no. The result goes to window_smoke.json as "covered" (and "coverShare"); it fails nothing yet.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class SmokeCover
    {
        /// <summary>A window with at least this share of its rect hidden is reported as covered.</summary>
        public const float Limit = 0.5f;

        /// <summary>The share (0..1) of the area of rect a that the union of the rects above it hides. Overlaps between the covering rects count once. NaN or empty rects give 0.</summary>
        public static float Share(SmokeBox a, IList<SmokeBox> above)
        {
            if (above == null || above.Count == 0 || Bad(a) || a.W <= 0 || a.H <= 0) return 0f;
            var xs = new List<float> { a.X, a.XMax };
            var ys = new List<float> { a.Y, a.YMax };
            var cut = new List<SmokeBox>();
            foreach (var b in above)
            {
                if (Bad(b) || b.W <= 0 || b.H <= 0) continue;
                float x0 = Math.Max(a.X, b.X), x1 = Math.Min(a.XMax, b.XMax), y0 = Math.Max(a.Y, b.Y), y1 = Math.Min(a.YMax, b.YMax);
                if (x1 <= x0 || y1 <= y0) continue;
                cut.Add(new SmokeBox(x0, y0, x1 - x0, y1 - y0));
                xs.Add(x0); xs.Add(x1); ys.Add(y0); ys.Add(y1);
            }
            if (cut.Count == 0) return 0f;
            xs.Sort(); ys.Sort();
            double hidden = 0;
            for (int i = 0; i + 1 < xs.Count; i++)
            {
                float cx0 = xs[i], cx1 = xs[i + 1];
                if (cx1 <= cx0) continue;
                for (int j = 0; j + 1 < ys.Count; j++)
                {
                    float cy0 = ys[j], cy1 = ys[j + 1];
                    if (cy1 <= cy0) continue;
                    float mx = (cx0 + cx1) / 2f, my = (cy0 + cy1) / 2f;
                    foreach (var c in cut)
                        if (mx >= c.X && mx <= c.XMax && my >= c.Y && my <= c.YMax) { hidden += (double)(cx1 - cx0) * (cy1 - cy0); break; }
                }
            }
            double total = (double)a.W * a.H;
            return (float)Math.Max(0, Math.Min(1, hidden / total));
        }

        public static bool Covered(float share) => share >= Limit;

        static bool Bad(SmokeBox b) => float.IsNaN(b.X + b.Y + b.W + b.H) || float.IsInfinity(b.X + b.Y + b.W + b.H);
    }
}
