// The pictures of the live effects, drawn in code so no art files are needed: the impact burst of an element (a port of impact_strip() of
// tools/front_art_packs.py: a flash that shrinks, a ring that grows and thins, sparks that fly out and fade, hard pixels), a heal burst
// (a thin ring and sparks that rise), a comet for a missile when the projectile sheets (fx_*) are not there, and the pixel-font text of a
// floating number with an outline. RGBA bytes, rows bottom first (a Unity texture). Pure C#, no Unity types.
using System;

namespace Chaos.Core
{
    public static class FrontFxArt
    {
        public const int ImpactSize = 64;   // a frame's side in texels; the quad scales it up with point filtering
        public const int CometSize = 32, CometFrames = 4;

        static byte B(float v) { return (byte)Math.Max(0, Math.Min(255, (int)Math.Round(v * 255f))); }

        static void Put(byte[] px, int w, int h, int x, int y, float r, float g, float b, float a)
        {
            if (x < 0 || y < 0 || x >= w || y >= h) return;
            int i = (y * w + x) * 4;
            px[i] = B(r); px[i + 1] = B(g); px[i + 2] = B(b); px[i + 3] = B(a);
        }

        /// <summary>FrontFxTiming.BurstFrames frames of ImpactSize side by side. heal = a rising sparkle instead of a blast.</summary>
        public static byte[] ImpactStrip(FxPalette p, bool heal)
        {
            int n = FrontFxTiming.BurstFrames, s = ImpactSize, w = s * n;
            var px = new byte[w * s * 4];
            const int Sparks = 14;
            var ang = new float[Sparks]; var spd = new float[Sparks];
            for (int k = 0; k < Sparks; k++)
            {
                ang[k] = (float)((k * 2.399963) % (2 * Math.PI));
                spd[k] = 0.6f + 0.4f * ((k * 7919) % 13) / 12f;
            }
            float c = s / 2f - 0.5f;
            for (int f = 0; f < n; f++)
            {
                float u = f / (n - 1f);
                int x0 = f * s;
                float flash = heal ? 2.5f * (1f - u) : 9f * (float)Math.Pow(1f - u, 1.3) + (u < 0.9f ? 2f : 0f);
                float ring = heal ? 8f + 12f * (float)Math.Pow(u, 0.7) : 6f + 22f * (float)Math.Pow(u, 0.7);
                float width = heal ? 2f * (1f - u) + 1f : 4f * (1f - u) + 1f;
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float d = (float)Math.Sqrt((x - c) * (x - c) + (y - c) * (y - c));
                        if (d <= flash)
                        {
                            if (d < flash * 0.55f) Put(px, w, s, x0 + x, y, p.CR, p.CG, p.CB, 1f);
                            else Put(px, w, s, x0 + x, y, p.BR, p.BG, p.BB, 1f);
                        }
                        else if (Math.Abs(d - ring) <= width / 2f && u < 0.95f)
                        {
                            bool inner = Math.Abs(d - ring) < width / 4f;
                            Put(px, w, s, x0 + x, y, inner ? p.BR : p.RR, inner ? p.BG : p.RG, inner ? p.BB : p.RB, (heal ? 0.7f : 1f) * (1f - u * 0.6f));
                        }
                    }
                if (u > 0.92f) continue;
                for (int k = 0; k < Sparks; k++)
                {
                    float r = (8f + 24f * spd[k]) * (float)Math.Pow(u, 0.6) + 3f;
                    float sx, sy;
                    if (heal) { sx = c + (float)Math.Cos(ang[k]) * 12f * spd[k]; sy = c + 4f + 26f * spd[k] * u; }   // up (rows go up)
                    else { sx = c + (float)Math.Cos(ang[k]) * r; sy = c + (float)Math.Sin(ang[k]) * r; }
                    int size = u < 0.5f ? 2 : 1;
                    for (int dy = 0; dy < size; dy++)
                        for (int dx = 0; dx < size; dx++)
                            Put(px, w, s, x0 + (int)Math.Round(sx) + dx, (int)Math.Round(sy) + dy, p.CR, p.CG, p.CB, 1f);
                }
            }
            return px;
        }

        /// <summary>A comet heading east, CometFrames frames of CometSize side by side: a bright head, a tail that thins to the west, a flicker. The
        /// stand-in for a projectile sheet row; the view turns the quad to the heading.</summary>
        public static byte[] CometStrip(FxPalette p)
        {
            int s = CometSize, n = CometFrames, w = s * n;
            var px = new byte[w * s * 4];
            for (int f = 0; f < n; f++)
            {
                int x0 = f * s;
                float head = s * 0.72f, cy = s / 2f - 0.5f;
                float tail = s * (0.55f + 0.06f * ((f * 5) % 4));
                for (int y = 0; y < s; y++)
                    for (int x = 0; x < s; x++)
                    {
                        float dx = x - head, dy = y - cy;
                        float d = (float)Math.Sqrt(dx * dx + dy * dy);
                        if (d <= 3.2f) { Put(px, w, s, x0 + x, y, p.CR, p.CG, p.CB, 1f); continue; }
                        if (d <= 5.5f) { Put(px, w, s, x0 + x, y, p.BR, p.BG, p.BB, 1f); continue; }
                        float back = head - x;   // distance behind the head
                        if (back > 0f && back < tail)
                        {
                            float u = back / tail, half = 4.5f * (1f - u) + 0.5f;
                            if (Math.Abs(dy) <= half) Put(px, w, s, x0 + x, y, u < 0.4f ? p.BR : p.RR, u < 0.4f ? p.BG : p.RG, u < 0.4f ? p.BB : p.RB, 1f - u * 0.85f);
                        }
                    }
            }
            return px;
        }

        /// <summary>The text of a floating number in the pixel font (PixelText, scale 1): fill colour with a one texel outline, a one texel margin. Rows
        /// bottom first. w and h are the picture's size.</summary>
        public static byte[] NumberPixels(string text, float fr, float fg, float fb, float kr, float kg, float kb, out int w, out int h)
        {
            bool[] ink = PixelText.Mask(text, 1, out int tw, out int th);
            w = tw + 4; h = th + 4;
            var px = new byte[w * h * 4];
            for (int ty = 0; ty < th; ty++)   // mask rows go top first
                for (int tx = 0; tx < tw; tx++)
                {
                    if (!ink[ty * tw + tx]) continue;
                    int x = tx + 2, y = (th - 1 - ty) + 2;
                    for (int oy = -1; oy <= 1; oy++)
                        for (int ox = -1; ox <= 1; ox++)
                        {
                            int i = ((y + oy) * w + x + ox) * 4;
                            if (px[i + 3] == 0) { px[i] = B(kr); px[i + 1] = B(kg); px[i + 2] = B(kb); px[i + 3] = 255; }
                        }
                }
            for (int ty = 0; ty < th; ty++)   // fill over the outline
                for (int tx = 0; tx < tw; tx++)
                {
                    if (!ink[ty * tw + tx]) continue;
                    Put(px, w, h, tx + 2, (th - 1 - ty) + 2, fr, fg, fb, 1f);
                }
            return px;
        }
    }
}
