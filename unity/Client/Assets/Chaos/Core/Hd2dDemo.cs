// An offline demo room for the HD-2D view (O432): a small temple-like room of 15 x 11 tiles with walls, pillars, torches,
// a carpet and two creatures. Two sources for the art:
//   - Synthetic(): sprites drawn by code (placeholder pixel art), written as a real .dat / .spr byte pair, so the
//     screenshot mode and the tests need no game files.
//   - FromPair(dat): the same room from the real pair's temple tileset (client ids 44511-44549, pair 60).
// Pure C#, no Unity types.
using System;
using System.Collections.Generic;

namespace Chaos.Core
{
    public sealed class DemoIds
    {
        public int Floor, Checker, Border, Wall, Pillar, Torch, Carpet, OutfitA, OutfitB;
        public static DemoIds Synthetic() => new DemoIds { Floor = 100, Checker = 101, Border = 102, Wall = 103, Pillar = 104, Torch = 105, Carpet = 106, OutfitA = 1, OutfitB = 2 };
        public static DemoIds Temple() => new DemoIds { Floor = 44511, Checker = 44512, Border = 44514, Wall = 44528, Pillar = 44540, Torch = 44544, Carpet = 44523, OutfitA = 128, OutfitB = 129 };
    }

    public sealed class Hd2dDemo
    {
        public DatFile Dat;
        public byte[] DatBytes, SprBytes;   // Synthetic only
        public World World;
        public Pos Center = new Pos(100, 100, 7);
        public bool Real;

        public static Hd2dDemo Synthetic()
        {
            var art = new DemoArt();
            var d = new Hd2dDemo();
            d.DatBytes = art.DatBytes();
            d.SprBytes = art.SprBytes();
            d.Dat = DatFile.Parse(d.DatBytes);
            d.Build(DemoIds.Synthetic());
            return d;
        }

        /// <summary>The room from the real pair's temple tileset; null when the dat does not hold it.</summary>
        public static Hd2dDemo FromPair(DatFile dat)
        {
            var ids = DemoIds.Temple();
            if (dat.Item(ids.Torch) == null || dat.Outfit(ids.OutfitA) == null || dat.Outfit(ids.OutfitB) == null) return null;
            var d = new Hd2dDemo { Dat = dat, Real = true };
            d.Build(ids);
            return d;
        }

        void Add(Pos p, int id) { World.AddThing(p, new Thing { Item = World.MakeItem(id, 0) }); }

        void Build(DemoIds ids)
        {
            World = new World(Dat) { Center = Center, WorldLight = 90 };
            int cx = Center.X, cy = Center.Y, z = Center.Z;
            for (int x = cx - 8; x <= cx + 9; x++)
                for (int y = cy - 6; y <= cy + 7; y++)
                    Add(new Pos(x, y, z), (x + y) % 2 == 0 ? ids.Floor : ids.Checker);
            // gilded border strip under the back wall
            for (int x = cx - 7; x <= cx + 7; x++) Add(new Pos(x, cy - 4, z), ids.Border);
            // back wall (64 px pieces, two tiles wide, anchored on their east tile) and torches on it
            for (int x = cx - 6; x <= cx + 8; x += 2) Add(new Pos(x, cy - 5, z), ids.Wall);
            Add(new Pos(cx - 3, cy - 5, z), ids.Torch);
            Add(new Pos(cx + 3, cy - 5, z), ids.Torch);
            // pillars, and a standing torch beside the carpet
            Add(new Pos(cx - 4, cy - 1, z), ids.Pillar);
            Add(new Pos(cx + 5, cy - 1, z), ids.Pillar);
            Add(new Pos(cx - 4, cy + 3, z), ids.Pillar);
            Add(new Pos(cx + 5, cy + 3, z), ids.Pillar);
            Add(new Pos(cx - 2, cy + 2, z), ids.Torch);
            // the carpet runs from the back wall to the player (a flat decal)
            Add(new Pos(cx + 1, cy + 1, z), ids.Carpet);
            MakeCreature(1, "Hero", ids.OutfitA, new Pos(cx, cy + 2, z), 3, 215, Dir.North);
            MakeCreature(2, "Acolyte", ids.OutfitB, new Pos(cx + 3, cy, z), 0, 0, Dir.West);
            World.PlayerId = 1;
        }

        void MakeCreature(uint id, string name, int look, Pos at, int light, int color, Dir dir)
        {
            var c = new Creature { Id = id, Name = name, Outfit = new Outfit(look, 78, 69, 58, 76), LightLevel = light, LightColor = color, Direction = dir };
            World.Creatures[id] = c;
            World.AddThing(at, new Thing { Creature = c });
        }
    }

    /// <summary>The placeholder art of the synthetic demo, drawn by code, and the .dat / .spr bytes that hold it.</summary>
    sealed class DemoArt
    {
        // one entry per thing: id, category, size in cells, flags (as writer calls), pixel painter
        sealed class Def
        {
            public int Id, W, H;
            public bool Outfit;
            public Action<ByteWriter> Flags;
            public Func<int, int, int, int, uint[]> Paint;   // (x, y, w px, h px) -> rgba (r | g << 8 | b << 16 | a << 24)
        }

        readonly List<Def> defs = new List<Def>();
        readonly List<byte[]> sprites = new List<byte[]>();   // 32 x 32 RGBA, sprite id = index + 1

        public DemoArt()
        {
            Item(100, 1, 1, w => w.U8(0).U16(100), Floor(150, 146, 160));
            Item(101, 1, 1, w => w.U8(0).U16(100), Floor(46, 42, 58));
            Item(102, 1, 1, w => w.U8(1), Border());
            Item(103, 2, 2, w => w.U8(2).U8(12).U8(13), Wall());
            Item(104, 2, 2, w => w.U8(12).U8(13), Pillar());
            Item(105, 2, 2, w => w.U8(2).U8(12).U8(13).U8(22).U16(6).U16(206), Torch());
            Item(106, 2, 3, w => w.U8(13), Carpet());
            Outfit(1, new[] { 190, 60, 50 });
            Outfit(2, new[] { 90, 60, 170 });
        }

        static uint Px(int r, int g, int b, int a = 255) => (uint)(Cl(r) | Cl(g) << 8 | Cl(b) << 16 | Cl(a) << 24);
        static int Cl(int v) => v < 0 ? 0 : v > 255 ? 255 : v;
        static int Hash(int x, int y, int s) { unchecked { int h = x * 73856093 ^ y * 19349663 ^ s * 83492791; h ^= h >> 13; h *= 0x5bd1e995; return (h ^ (h >> 15)) & 0x7fffffff; } }

        static Func<int, int, int, int, uint[]> Make(Func<int, int, int, int, uint> px)
        {
            return (x0, y0, w, h) =>
            {
                var o = new uint[w * h];
                for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) o[y * w + x] = px(x, y, w, h);
                return o;
            };
        }

        static Func<int, int, int, int, uint[]> Floor(int r, int g, int b) => Make((x, y, w, h) =>
        {
            int n = Hash(x, y, r) % 13 - 6;
            bool grout = x == 0 || y == 0;
            int k = grout ? -28 : n;
            return Px(r + k, g + k, b + k);
        });

        static Func<int, int, int, int, uint[]> Border() => Make((x, y, w, h) =>
        {
            int n = Hash(x, y, 5) % 9 - 4;
            if (y < 4) return Px(214 + n, 170 + n, 70 + n);
            if (y == 4) return Px(110, 80, 30);
            return Px(150 + n, 146 + n, 160 + n);
        });

        static Func<int, int, int, int, uint[]> Wall() => Make((x, y, w, h) =>
        {
            int row = y / 11, off = row % 2 * 8;
            bool mortar = y % 11 == 0 || (x + off) % 16 == 0;
            int n = Hash(x / 16 + row * 7, row, 3) % 21 - 10;
            int top = y < 6 ? 20 : 0;
            if (mortar) return Px(50, 44, 52);
            return Px(104 + n + top, 92 + n + top, 100 + n + top);
        });

        static Func<int, int, int, int, uint[]> Pillar() => Make((x, y, w, h) =>
        {
            int cx = w / 2;
            bool cap = y < 8 || y >= h - 9;
            int half = cap ? 20 : 13;
            if (Math.Abs(x - cx) > half || y < 3) return 0;
            float shade = 1f - Math.Abs(x - cx) / (float)half * 0.55f;
            if (x < cx) shade += 0.12f;
            int n = Hash(x, y, 8) % 7 - 3;
            int v = (int)(150 * shade) + n;
            return Px(v, v - 4, v + 6);
        });

        static Func<int, int, int, int, uint[]> Torch() => Make((x, y, w, h) =>
        {
            int cx = w / 2;
            float fx = (x - cx) / 6f, fy = (y - 16) / 11f;
            float fl = fx * fx + fy * fy;
            if (fl < 1f) return fl < 0.35f ? Px(255, 244, 190) : Px(255, 170 + (int)(60 * (1 - fl)), 50);
            if (y >= 24 && y < 50 && Math.Abs(x - cx) <= 3) return Px(70, 52, 40);    // the staff
            if (y >= 26 && y < 31 && Math.Abs(x - cx) <= 8) return Px(40, 36, 44);    // the cup
            return 0;
        });

        static Func<int, int, int, int, uint[]> Carpet() => Make((x, y, w, h) =>
        {
            int e = Math.Min(Math.Min(x, w - 1 - x), Math.Min(y, h - 1 - y));
            int n = Hash(x, y, 2) % 9 - 4;
            if (e < 2) return Px(214, 170, 70);
            if (e < 5) return Px(120 + n, 20, 30);
            if (e == 6) return Px(214, 170, 70);
            return Px(140 + n, 24 + n / 2, 36);
        });

        static Func<int, int, int, int, uint[]> Figure(int[] body) => Make((x, y, w, h) =>
        {
            int cx = w / 2;
            // head
            float hx = (x - cx) / 7f, hy = (y - 18) / 8f;
            if (hx * hx + hy * hy < 1f) return Px(224, 180, 140);
            if (y >= 26 && y < 44 && Math.Abs(x - cx) <= 9 - (y - 26) / 6) return Px(body[0], body[1], body[2]);
            if (y >= 44 && y < 58 && (Math.Abs(x - cx + 4) <= 3 || Math.Abs(x - cx - 4) <= 3)) return Px(60, 56, 80);
            return 0;
        });

        void Item(int id, int w, int h, Action<ByteWriter> flags, Func<int, int, int, int, uint[]> paint)
        {
            defs.Add(new Def { Id = id, W = w, H = h, Flags = flags, Paint = paint });
        }

        void Outfit(int id, int[] body)
        {
            defs.Add(new Def { Id = id, W = 2, H = 2, Outfit = true, Flags = w => { }, Paint = Figure(body) });
        }

        // slices an image of w x h cells into 32 x 32 sprites; cell (cw, ch) is the cell cw to the west and ch up from the anchor
        uint SpriteOf(uint[] img, int w, int h, int cw, int ch)
        {
            int px = (w - 1 - cw) * 32, py = (h - 1 - ch) * 32, stride = w * 32;
            var cell = new byte[32 * 32 * 4];
            bool any = false;
            for (int y = 0; y < 32; y++)
                for (int x = 0; x < 32; x++)
                {
                    uint p = img[(py + y) * stride + px + x];
                    int i = (y * 32 + x) * 4;
                    cell[i] = (byte)p; cell[i + 1] = (byte)(p >> 8); cell[i + 2] = (byte)(p >> 16); cell[i + 3] = (byte)(p >> 24);
                    if (cell[i + 3] != 0) any = true;
                }
            if (!any) return 0;
            sprites.Add(cell);
            return (uint)sprites.Count;
        }

        public byte[] DatBytes()
        {
            var w = new ByteWriter().U32(0x42a3).U16(106).U16(2).U16(0).U16(0);
            foreach (var d in defs) if (!d.Outfit) Thing(w, d);
            foreach (var d in defs) if (d.Outfit) Thing(w, d);
            return w.ToArray();
        }

        void Thing(ByteWriter w, Def d)
        {
            d.Flags(w);
            w.U8(0xFF);
            int px = d.Outfit ? 4 : 1;
            if (d.Outfit) w.U8(1).U8(0);    // one frame group, type idle
            w.U8((byte)d.W).U8((byte)d.H);
            if (d.W > 1 || d.H > 1) w.U8(64);
            w.U8(1).U8((byte)px).U8(1).U8(1).U8(1);
            var img = d.Paint(0, 0, d.W * 32, d.H * 32);
            // item cells are ordered (h, w) with w fastest; an outfit repeats the 4 facings (the demo draws one figure)
            for (int dir = 0; dir < px; dir++)
                for (int ch = 0; ch < d.H; ch++)
                    for (int cw = 0; cw < d.W; cw++)
                    {
                        w.U32(dir == 0 || !d.Outfit ? SpriteOf(img, d.W, d.H, cw, ch) : SpriteOf(Mirror(img, d.W * 32, d.H * 32, dir), d.W, d.H, cw, ch));
                    }
        }

        // the east and west facings mirror the figure; north and south stay as they are
        static uint[] Mirror(uint[] img, int w, int h, int dir)
        {
            if (dir != 1 && dir != 3) return img;
            var o = new uint[img.Length];
            for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) o[y * w + x] = img[y * w + (dir == 3 ? w - 1 - x : x)];
            return o;
        }

        public byte[] SprBytes()
        {
            // the sprites were made while writing the dat
            if (sprites.Count == 0) DatBytes();
            var head = new ByteWriter().U32(0x1234).U32((uint)sprites.Count);
            var recs = new List<byte[]>();
            foreach (var cell in sprites) recs.Add(Encode(cell));
            long at = 8 + 4L * sprites.Count;
            var body = new ByteWriter();
            foreach (var r in recs)
            {
                head.U32((uint)at);
                body.Raw(r);
                at += r.Length;
            }
            return head.Raw(body.ToArray()).ToArray();
        }

        static byte[] Encode(byte[] cell)
        {
            var data = new ByteWriter();
            int i = 0, last = 0;
            while (i < 1024)
            {
                while (i < 1024 && cell[i * 4 + 3] == 0) i++;
                if (i >= 1024) break;
                int start = i;
                while (i < 1024 && cell[i * 4 + 3] != 0) i++;
                data.U16((ushort)(start - last)).U16((ushort)(i - start));
                for (int k = start; k < i; k++) data.U8(cell[k * 4]).U8(cell[k * 4 + 1]).U8(cell[k * 4 + 2]).U8(cell[k * 4 + 3]);
                last = i;
            }
            var body = data.ToArray();
            return new ByteWriter().U8(255).U8(0).U8(255).U16((ushort)body.Length).Raw(body).ToArray();
        }
    }
}
