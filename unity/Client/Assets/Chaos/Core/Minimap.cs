// The minimap the client remembers: one colour byte per tile and floor, filled from the World so explored ground stays.
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class MinimapMemory
    {
        readonly Dictionary<int, Dictionary<long, byte>> floors = new Dictionary<int, Dictionary<long, byte>>();
        /// <summary>Grows each time a remembered colour changes, so a view knows when to redraw.</summary>
        public int Version { get; private set; }

        static long Key(int x, int y) => ((long)x << 20) | (long)y;

        /// <summary>The colour byte of a tile (6x6x6 cube), 0 when never seen.</summary>
        public byte Get(int x, int y, int z)
        {
            if (!floors.TryGetValue(z, out var f)) return 0;
            f.TryGetValue(Key(x, y), out byte c);
            return c;
        }

        public int Count(int z) => floors.TryGetValue(z, out var f) ? f.Count : 0;

        public void Clear() { floors.Clear(); Version++; }

        /// <summary>The colour byte a tile shows: its top-most item with a minimap colour, 0 when none.</summary>
        public static byte Pick(Tile t)
        {
            if (t == null) return 0;
            for (int i = t.Things.Count - 1; i >= 0; i--)
            {
                var th = t.Things[i];
                if (th.IsCreature || th.Item == null || th.Item.Type == null) continue;
                int c = th.Item.Type.MinimapColor & 0xFF;
                if (c != 0) return (byte)c;
            }
            return 0;
        }

        /// <summary>Remembers every tile the World holds. A tile without a colour keeps what was remembered.</summary>
        public void Update(World w)
        {
            foreach (var t in w.Tiles.Values)
            {
                byte c = Pick(t);
                if (c == 0) continue;
                if (!floors.TryGetValue(t.Pos.Z, out var f)) { f = new Dictionary<long, byte>(); floors[t.Pos.Z] = f; }
                long k = Key(t.Pos.X, t.Pos.Y);
                if (f.TryGetValue(k, out byte old) && old == c) continue;
                f[k] = c;
                Version++;
            }
        }

        /// <summary>The 8-bit cube colour as r, g, b (each 0-255). Bytes above 215 are black.</summary>
        public static void Rgb(byte c, out byte r, out byte g, out byte b)
        {
            if (c >= 216) { r = g = b = 0; return; }
            r = (byte)(c / 36 * 51);
            g = (byte)(c / 6 % 6 * 51);
            b = (byte)(c % 6 * 51);
        }
    }
}
