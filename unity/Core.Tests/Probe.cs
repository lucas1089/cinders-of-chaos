// dotnet run -c Release -- probe DAT SPR OUTDIR [outfit ids...]
// Loads a real client pair and writes a contact sheet of outfits (4 directions, idle) and a strip of items as PNG,
// to check the readers against the real files. Not run in CI (the pair is not in git).
using System;
using System.Diagnostics;
using System.IO;

namespace Chaos.Core.Tests
{
    static class Probe
    {
        public static int Run(string[] args)
        {
            if (args.Length < 4)
            {
                Console.WriteLine("usage: probe DAT SPR OUTDIR [outfit ids...]");
                return 2;
            }
            var sw = Stopwatch.StartNew();
            var dat = DatFile.Load(args[1]);
            Console.WriteLine("dat: signature " + dat.Signature.ToString("x") + ", items " + (dat.Items.Length - 1) + ", outfits " +
                              (dat.Outfits.Length - 1) + ", effects " + (dat.Effects.Length - 1) + ", missiles " +
                              (dat.Missiles.Length - 1) + " (" + sw.ElapsedMilliseconds + " ms)");
            using var spr = SprFile.Open(args[2]);
            Console.WriteLine("spr: signature " + spr.Signature.ToString("x") + ", " + spr.Count + " sprites");
            Directory.CreateDirectory(args[3]);

            int[] outfits = args.Length > 4 ? Array.ConvertAll(args[4..], int.Parse) : new[] { 128, 129, 130, 131, 2126, 2127 };
            var sheet = new Canvas(4 * 64, outfits.Length * 64);
            for (int i = 0; i < outfits.Length; i++)
            {
                var t = dat.Outfit(outfits[i]);
                if (t == null) continue;
                for (int dir = 0; dir < 4; dir++)
                    Draw(sheet, spr, t.Idle, dir * 64 + 32, i * 64 + 32, dir, 0, new Outfit(outfits[i], 78, 69, 58, 76));
            }
            Png.Write(Path.Combine(args[3], "outfits.png"), sheet.Px, sheet.W, sheet.H);

            int[] items = { 100, 101, 102, 103, 104, 105, 106, 3031, 3035, 3043, 2853, 1987, 1642, 29326 };
            var strip = new Canvas(items.Length * 64, 64);
            for (int i = 0; i < items.Length; i++)
            {
                var t = dat.Item(items[i]);
                if (t != null) Draw(strip, spr, t.Idle, i * 64 + 32, 32, 0, 0, null);
            }
            Png.Write(Path.Combine(args[3], "items.png"), strip.Px, strip.W, strip.H);
            Console.WriteLine("wrote outfits.png and items.png to " + args[3] + " (" + sw.ElapsedMilliseconds + " ms)");
            return 0;
        }

        /// <summary>Draws a thing with its bottom-right tile at (x, y) (top-left of that tile), as the client anchors it.</summary>
        static void Draw(Canvas c, SprFile spr, FrameGroup g, int x, int y, int px, int phase, Outfit colors)
        {
            for (int layer = 0; layer < (colors != null ? g.Layers : 1); layer++)
                for (int h = 0; h < g.Height; h++)
                    for (int w = 0; w < g.Width; w++)
                    {
                        var rgba = spr.Rgba(g.Sprite(w, h, layer, px, 0, 0, phase));
                        if (rgba == null) continue;
                        if (layer == 1) continue;   // the colour mask is applied to layer 0 below
                        var mask = g.Layers > 1 && colors != null ? spr.Rgba(g.Sprite(w, h, 1, px, 0, 0, phase)) : null;
                        if (mask != null) OutfitColors.Apply(rgba, mask, colors);
                        c.Blit(rgba, x - w * 32, y - h * 32);
                    }
        }
    }

    sealed class Canvas
    {
        public readonly int W, H;
        public readonly byte[] Px;

        public Canvas(int w, int h)
        {
            W = w; H = h;
            Px = new byte[w * h * 4];
            for (int i = 0; i < Px.Length; i += 4) { Px[i] = 40; Px[i + 1] = 36; Px[i + 2] = 44; Px[i + 3] = 255; }
        }

        public void Blit(byte[] rgba, int x0, int y0)
        {
            for (int y = 0; y < 32; y++)
                for (int x = 0; x < 32; x++)
                {
                    int tx = x0 + x, ty = y0 + y;
                    if (tx < 0 || ty < 0 || tx >= W || ty >= H) continue;
                    int s = (y * 32 + x) * 4, d = (ty * W + tx) * 4;
                    int a = rgba[s + 3];
                    if (a == 0) continue;
                    for (int k = 0; k < 3; k++) Px[d + k] = (byte)((rgba[s + k] * a + Px[d + k] * (255 - a)) / 255);
                }
        }
    }
}
