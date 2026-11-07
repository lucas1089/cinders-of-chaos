// A 5 x 7 pixel font for the name labels of the line-up screenshot (Unity/Hd2dShot.cs): the screenshot is read back from a render
// texture, where the game's own OnGUI labels never appear, and a built-in Unity font may be missing under a virtual display, so the
// labels are drawn into the picture from this table. Letters (lower case is drawn as upper case), digits, space, '.', '-' and '\''.
// Pure C#, no Unity types.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public static class PixelText
    {
        public const int GlyphW = 5, GlyphH = 7, Gap = 1;

        static readonly Dictionary<char, string> Glyphs = Build();

        static Dictionary<char, string> Build()
        {
            // seven rows of five bits per glyph, '1' is ink
            var d = new Dictionary<char, string>();
            void G(char c, string rows) { d[c] = rows.Replace(" ", ""); }
            G('A', "01110 10001 10001 11111 10001 10001 10001");
            G('B', "11110 10001 10001 11110 10001 10001 11110");
            G('C', "01110 10001 10000 10000 10000 10001 01110");
            G('D', "11110 10001 10001 10001 10001 10001 11110");
            G('E', "11111 10000 10000 11110 10000 10000 11111");
            G('F', "11111 10000 10000 11110 10000 10000 10000");
            G('G', "01110 10001 10000 10111 10001 10001 01111");
            G('H', "10001 10001 10001 11111 10001 10001 10001");
            G('I', "01110 00100 00100 00100 00100 00100 01110");
            G('J', "00111 00010 00010 00010 00010 10010 01100");
            G('K', "10001 10010 10100 11000 10100 10010 10001");
            G('L', "10000 10000 10000 10000 10000 10000 11111");
            G('M', "10001 11011 10101 10101 10001 10001 10001");
            G('N', "10001 11001 10101 10011 10001 10001 10001");
            G('O', "01110 10001 10001 10001 10001 10001 01110");
            G('P', "11110 10001 10001 11110 10000 10000 10000");
            G('Q', "01110 10001 10001 10001 10101 10010 01101");
            G('R', "11110 10001 10001 11110 10100 10010 10001");
            G('S', "01111 10000 10000 01110 00001 00001 11110");
            G('T', "11111 00100 00100 00100 00100 00100 00100");
            G('U', "10001 10001 10001 10001 10001 10001 01110");
            G('V', "10001 10001 10001 10001 10001 01010 00100");
            G('W', "10001 10001 10001 10101 10101 11011 10001");
            G('X', "10001 10001 01010 00100 01010 10001 10001");
            G('Y', "10001 10001 01010 00100 00100 00100 00100");
            G('Z', "11111 00001 00010 00100 01000 10000 11111");
            G('0', "01110 10001 10011 10101 11001 10001 01110");
            G('1', "00100 01100 00100 00100 00100 00100 01110");
            G('2', "01110 10001 00001 00010 00100 01000 11111");
            G('3', "11110 00001 00001 01110 00001 00001 11110");
            G('4', "00010 00110 01010 10010 11111 00010 00010");
            G('5', "11111 10000 11110 00001 00001 10001 01110");
            G('6', "00110 01000 10000 11110 10001 10001 01110");
            G('7', "11111 00001 00010 00100 01000 01000 01000");
            G('8', "01110 10001 10001 01110 10001 10001 01110");
            G('9', "01110 10001 10001 01111 00001 00010 01100");
            G('+', "00000 00100 00100 11111 00100 00100 00000");
            G('-', "00000 00000 00000 11111 00000 00000 00000");
            G('.', "00000 00000 00000 00000 00000 01100 01100");
            G('\'', "00100 00100 01000 00000 00000 00000 00000");
            G(' ', "00000 00000 00000 00000 00000 00000 00000");
            return d;
        }

        /// <summary>True when the font has the character (lower case counts as upper case).</summary>
        public static bool Has(char c) => Glyphs.ContainsKey(char.ToUpperInvariant(c));

        public static int Width(string s, int scale) => string.IsNullOrEmpty(s) ? 0 : (s.Length * (GlyphW + Gap) - Gap) * Math.Max(1, scale);
        public static int Height(int scale) => GlyphH * Math.Max(1, scale);

        /// <summary>The ink of a text as a row-major mask (w x h, top row first), each font pixel scale x scale pixels. A character the font does
        /// not have is a blank.</summary>
        public static bool[] Mask(string s, int scale, out int w, out int h)
        {
            scale = Math.Max(1, scale);
            w = Width(s, scale);
            h = Height(scale);
            var m = new bool[Math.Max(0, w) * h];
            if (string.IsNullOrEmpty(s)) return m;
            for (int i = 0; i < s.Length; i++)
            {
                if (!Glyphs.TryGetValue(char.ToUpperInvariant(s[i]), out var rows)) continue;
                int x0 = i * (GlyphW + Gap) * scale;
                for (int gy = 0; gy < GlyphH; gy++)
                    for (int gx = 0; gx < GlyphW; gx++)
                    {
                        if (rows[gy * GlyphW + gx] != '1') continue;
                        for (int sy = 0; sy < scale; sy++)
                            for (int sx = 0; sx < scale; sx++)
                                m[(gy * scale + sy) * w + x0 + gx * scale + sx] = true;
                    }
            }
            return m;
        }
    }
}
