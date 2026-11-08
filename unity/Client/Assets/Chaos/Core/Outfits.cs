// Outfits: look type, the four colours and addons, and the 133-colour palette the colour mask layer uses.
using System;

namespace Chaos.Core
{
    public sealed class Outfit
    {
        public int LookType, Head, Body, Legs, Feet, Addons, Mount;
        public int LookTypeEx;   // an item shown instead of an outfit (look type 0)
        public int Wings, Aura;  // only on an Identity.Chaos connection (markers sent): 0 = none
        public string Shader = "";   // the outfit shader's name, "" = none (same condition)

        public Outfit() { }

        public Outfit(int lookType, int head, int body, int legs, int feet, int addons = 0, int mount = 0)
        {
            LookType = lookType; Head = head; Body = body; Legs = legs; Feet = feet; Addons = addons; Mount = mount;
        }

        public override string ToString() => LookType != 0 ? "look " + LookType : "item " + LookTypeEx;
    }

    public static class OutfitColors
    {
        const int Values = 7, Hues = 19;

        /// <summary>RGB of a palette index (0-132), as the stock client computes it.</summary>
        public static void Rgb(int color, out byte r, out byte g, out byte b)
        {
            if (color < 0 || color >= Hues * Values) color = 0;
            double h, s, v;
            if (color % Hues != 0)
            {
                h = color % Hues * 1.0 / 18.0;
                s = 1; v = 1;
                switch (color / Hues)
                {
                    case 0: s = 0.25; v = 1.00; break;
                    case 1: s = 0.25; v = 0.75; break;
                    case 2: s = 0.50; v = 0.75; break;
                    case 3: s = 0.667; v = 0.75; break;
                    case 4: s = 1.00; v = 1.00; break;
                    case 5: s = 1.00; v = 0.75; break;
                    case 6: s = 1.00; v = 0.50; break;
                }
            }
            else
            {
                h = 0; s = 0;
                v = 1 - (double)color / Hues / Values;
            }
            if (v == 0) { r = g = b = 0; return; }
            if (s == 0) { r = g = b = (byte)(int)(v * 255); return; }
            double red, green, blue;
            if (h < 1.0 / 6.0) { red = v; blue = v * (1 - s); green = blue + (v - blue) * 6 * h; }
            else if (h < 2.0 / 6.0) { green = v; blue = v * (1 - s); red = green - (v - blue) * (6 * h - 1); }
            else if (h < 3.0 / 6.0) { green = v; red = v * (1 - s); blue = red + (v - red) * (6 * h - 2); }
            else if (h < 4.0 / 6.0) { blue = v; red = v * (1 - s); green = blue - (v - red) * (6 * h - 3); }
            else if (h < 5.0 / 6.0) { blue = v; green = v * (1 - s); red = green + (v - green) * (6 * h - 4); }
            else { red = v; green = v * (1 - s); blue = red - (v - green) * (6 * h - 5); }
            r = (byte)(int)(red * 255); g = (byte)(int)(green * 255); b = (byte)(int)(blue * 255);
        }

        /// <summary>Tints `rgba` in place by the mask layer: yellow = head, red = body, green = legs, blue = feet.</summary>
        public static void Apply(byte[] rgba, byte[] mask, Outfit o)
        {
            Rgb(o.Head, out byte hr, out byte hg, out byte hb);
            Rgb(o.Body, out byte br, out byte bg, out byte bb);
            Rgb(o.Legs, out byte lr, out byte lg, out byte lb);
            Rgb(o.Feet, out byte fr, out byte fg, out byte fb);
            for (int i = 0; i < rgba.Length; i += 4)
            {
                if (mask[i + 3] == 0) continue;
                int mr = mask[i], mg = mask[i + 1], mb = mask[i + 2];
                byte cr, cg, cb;
                if (mr > 0 && mg > 0 && mb == 0) { cr = hr; cg = hg; cb = hb; }
                else if (mr > 0 && mg == 0 && mb == 0) { cr = br; cg = bg; cb = bb; }
                else if (mr == 0 && mg > 0 && mb == 0) { cr = lr; cg = lg; cb = lb; }
                else if (mr == 0 && mg == 0 && mb > 0) { cr = fr; cg = fg; cb = fb; }
                else continue;
                rgba[i] = (byte)(rgba[i] * cr / 255);
                rgba[i + 1] = (byte)(rgba[i + 1] * cg / 255);
                rgba[i + 2] = (byte)(rgba[i + 2] * cb / 255);
            }
        }
    }
}
