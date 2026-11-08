// Phase 12, track H: windows that fit the screen and a smoke run that sees the ones that do not (unity/README.md "Window smoke run"). Pure C#, no Unity types.
//   WindowFit  one shared clamp of a window rect to the screen (GameWindow.Draw uses it for HUD windows and windows that size themselves) and the scroll maths of a long body.
//   SmokeBody  the "empty body" checks of the smoke run: a body too thin to hold a line, and the share of ink (pixels unlike the body's main colour) in the crop under the title bar.
using System;

namespace Chaos.Core
{
    public static class WindowFit
    {
        /// <summary>The gap kept to every screen edge, UI units.</summary>
        public const float Margin = 4f;

        /// <summary>True when a window of this size does not fit on the screen with the margin to both sides.</summary>
        public static bool Exceeds(float w, float h, float screenW, float screenH) => w > screenW - 2 * Margin || h > screenH - 2 * Margin;

        /// <summary>The rect cut to the screen: a side larger than the screen less the margins shrinks to it, then the rect moves in so no edge is outside.
        /// NaN sizes become the smallest the screen allows (1); a screen of no size gives the rect back unchanged.</summary>
        public static SmokeBox Fit(SmokeBox r, float screenW, float screenH)
        {
            if (screenW <= 2 * Margin + 1 || screenH <= 2 * Margin + 1) return r;
            float w = float.IsNaN(r.W) ? 1f : Math.Max(1f, Math.Min(r.W, screenW - 2 * Margin));
            float h = float.IsNaN(r.H) ? 1f : Math.Max(1f, Math.Min(r.H, screenH - 2 * Margin));
            float x = float.IsNaN(r.X) ? Margin : Math.Max(Margin, Math.Min(r.X, screenW - w - Margin));
            float y = float.IsNaN(r.Y) ? Margin : Math.Max(Margin, Math.Min(r.Y, screenH - h - Margin));
            return new SmokeBox(x, y, w, h);
        }

        /// <summary>The height a scroll view needs: the content, never less than the view (no scroll bar for a short text).</summary>
        public static float ScrollContent(float contentH, float viewH) => Math.Max(contentH, viewH);

        /// <summary>The part of a body a long text may use: the body less the fixed bottom bar (buttons) and its gap, at least 1.</summary>
        public static float ViewHeight(float bodyH, float barH, float gap) => Math.Max(1f, bodyH - barH - gap);
    }

    public static class SmokeBody
    {
        /// <summary>GameWindow.Draw: the body starts 28 below the window top and ends 4 above its bottom (a 4 wide frame at both sides).</summary>
        public const float TitleH = 28f, BodyInsetY = 32f, BodyInsetX = 8f;
        /// <summary>A body shorter than this holds no line of text (a 15 pt line needs about 22).</summary>
        public const float MinBody = 24f;
        /// <summary>A pixel is ink when one channel differs from the body's main colour by more than this (0-255).</summary>
        public const int InkDiff = 36;
        /// <summary>Under this share of ink the body is empty: no text, no icon, no bar.</summary>
        public const float InkMin = 0.004f;
        public const int MinSamples = 64, MaxSamples = 40000;

        public static float BodyHeight(float windowH) => windowH - BodyInsetY;

        /// <summary>The body is too thin to draw a line in.</summary>
        public static bool Thin(float windowH) => !float.IsNaN(windowH) && BodyHeight(windowH) < MinBody;

        /// <summary>The body of a window in screen pixels, top down, cut to the screen: window rect (UI units) under the title bar, times the scale.</summary>
        public static SmokeBox Inner(SmokeBox win, float scale, float screenPxW, float screenPxH)
        {
            float x0 = Math.Max(0f, (win.X + 4f) * scale), y0 = Math.Max(0f, (win.Y + TitleH) * scale);
            float x1 = Math.Min(screenPxW, (win.X + win.W - 4f) * scale), y1 = Math.Min(screenPxH, (win.Y + win.H - 4f) * scale);
            if (float.IsNaN(x0 + y0 + x1 + y1) || x1 - x0 < 1f || y1 - y0 < 1f) return new SmokeBox(0, 0, 0, 0);
            return new SmokeBox(x0, y0, x1 - x0, y1 - y0);
        }

        /// <summary>The share (0..1) of ink in a box of an image of 4 bytes per pixel (the first three are colour; their order does not matter here).
        /// bottomUp: the rows start at the bottom (a Unity texture). The box is in pixels, top down. samples gets the number of pixels looked at (a stride keeps it under MaxSamples).
        /// The main colour is the busiest of 16 levels per channel; ink is a pixel that differs from the mean of that bin by more than InkDiff in any channel.</summary>
        public static float Ink(byte[] px, int imgW, int imgH, SmokeBox box, bool bottomUp, out int samples)
        {
            samples = 0;
            if (px == null || imgW <= 0 || imgH <= 0 || px.Length < imgW * imgH * 4 || box.W < 1 || box.H < 1) return 0f;
            int x0 = Math.Max(0, (int)box.X), y0 = Math.Max(0, (int)box.Y), x1 = Math.Min(imgW, (int)Math.Ceiling(box.XMax)), y1 = Math.Min(imgH, (int)Math.Ceiling(box.YMax));
            if (x1 <= x0 || y1 <= y0) return 0f;
            long area = (long)(x1 - x0) * (y1 - y0);
            int stride = Math.Max(1, (int)Math.Ceiling(Math.Sqrt(area / (double)MaxSamples)));
            var count = new int[4096];
            var sum = new long[4096 * 3];
            int n = 0;
            for (int y = y0; y < y1; y += stride)
            {
                int row = bottomUp ? imgH - 1 - y : y;
                for (int x = x0; x < x1; x += stride)
                {
                    int i = (row * imgW + x) * 4;
                    int r = px[i], g = px[i + 1], b = px[i + 2];
                    int bin = (r >> 4) << 8 | (g >> 4) << 4 | (b >> 4);
                    count[bin]++; sum[bin * 3] += r; sum[bin * 3 + 1] += g; sum[bin * 3 + 2] += b;
                    n++;
                }
            }
            samples = n;
            if (n == 0) return 0f;
            int main = 0;
            for (int k = 1; k < 4096; k++) if (count[k] > count[main]) main = k;
            int mr = (int)(sum[main * 3] / count[main]), mg = (int)(sum[main * 3 + 1] / count[main]), mb = (int)(sum[main * 3 + 2] / count[main]);
            int ink = 0;
            for (int y = y0; y < y1; y += stride)
            {
                int row = bottomUp ? imgH - 1 - y : y;
                for (int x = x0; x < x1; x += stride)
                {
                    int i = (row * imgW + x) * 4;
                    if (Math.Abs(px[i] - mr) > InkDiff || Math.Abs(px[i + 1] - mg) > InkDiff || Math.Abs(px[i + 2] - mb) > InkDiff) ink++;
                }
            }
            return ink / (float)n;
        }

        /// <summary>An empty body: enough pixels were looked at and (almost) none is ink.</summary>
        public static bool Empty(float ink, int samples) => samples >= MinSamples && ink < InkMin;
    }
}
