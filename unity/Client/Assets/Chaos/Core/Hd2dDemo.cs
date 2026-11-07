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

    /// <summary>The ids the outdoor demo picked from the real pair by looking at the sprites' pixels (0: none found).</summary>
    public sealed class OutdoorIds
    {
        public int Grass, Dirt, Water, Tree, Rock, Bush, OutfitA, OutfitB;
        public override string ToString() => "grass " + Grass + ", dirt " + Dirt + ", water " + Water + ", tree " + Tree + ", rock " + Rock + ", bush " + Bush;
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

        public OutdoorIds Ids;

        /// <summary>Picks the outdoor demo's ids from the pair by the pixels of its sprites (Hd2dTerrain): a plain ground of each class
        /// (Grass, Dirt: one phase, the least noise, a whole tile; Water: the most phases), a tall blocking green thing for a tree, a
        /// grey 1 x 1 lump for a rock, a small green blocking thing for a bush. `sprite` gives a sprite's 32 x 32 RGBA, or null.
        /// Null when the pair has no grass, water or tree.</summary>
        public static OutdoorIds PickOutdoor(DatFile dat, Func<uint, byte[]> sprite, SpriteClassifier cls = null)
        {
            cls = cls ?? new SpriteClassifier(sprite);
            var ids = new OutdoorIds();
            float grassSpread = 9f, dirtSpread = 9f, treeGreen = 0f, rockFill = 0f, bushGreen = 0f;
            int waterPhases = 0;
            for (int id = 100; id < dat.Items.Length; id++)
            {
                var t = dat.Items[id];
                if (t == null || t.Idle == null || t.Idle.Sprites == null || t.Idle.Sprites.Length == 0) continue;
                var g = t.Idle;
                if (t.Ground)
                {
                    if (g.Width != 1 || g.Height != 1 || t.GroundBorder) continue;
                    var i = cls.Info(t);
                    if (i.Stats.Alpha < 0.95f) continue;
                    if (i.Class == GroundClass.Grass && g.Phases == 1 && i.Stats.Spread < grassSpread) { grassSpread = i.Stats.Spread; ids.Grass = id; }
                    else if (i.Class == GroundClass.Dirt && g.Phases == 1 && i.Stats.Spread < dirtSpread) { dirtSpread = i.Stats.Spread; ids.Dirt = id; }
                    else if (i.Class == GroundClass.Water && g.Phases > waterPhases) { waterPhases = g.Phases; ids.Water = id; }
                    continue;
                }
                // upright candidates: the cheap flags first, the pixels only for those
                if (t.OnBottom || t.OnTop || t.Pickupable || t.Container || t.Stackable || t.LightLevel > 0 || !Hd2d.Blocking(t)) continue;
                if (Hd2d.Classify(t) != Hd2dKind.Billboard || g.Width * g.Height > 4) continue;
                var piece = new Hd2dPiece { Kind = Hd2dKind.Billboard, Type = t, Width = g.Width, Height = g.Height };
                var role = Hd2dWorld3d.RoleOf(piece, cls, true);
                var st = cls.Info(t).Stats;
                if (role == RuinsRole.Tree && st.GreenShare >= Hd2dWorld3d.GreenShare && st.GreenShare > treeGreen) { treeGreen = st.GreenShare; ids.Tree = id; }
                else if (role == RuinsRole.Rock && st.Alpha >= 0.4f && st.Value >= 0.3f && st.Value <= 0.75f && st.Alpha > rockFill) { rockFill = st.Alpha; ids.Rock = id; }
                else if (role == RuinsRole.Bush && st.GreenShare > bushGreen) { bushGreen = st.GreenShare; ids.Bush = id; }
            }
            if (ids.Grass == 0 || ids.Water == 0 || ids.Tree == 0) return null;
            if (ids.Dirt == 0) ids.Dirt = ids.Grass;
            for (int id = 1; id < dat.Outfits.Length && (ids.OutfitA == 0 || ids.OutfitB == 0); id++)
            {
                if (dat.Outfit(id) == null) continue;
                if (ids.OutfitA == 0 && (id >= 128 || dat.Outfit(128) == null)) ids.OutfitA = id;
                else if (ids.OutfitB == 0 && id != ids.OutfitA) ids.OutfitB = id;
            }
            if (ids.OutfitA == 0) return null;
            if (ids.OutfitB == 0) ids.OutfitB = ids.OutfitA;
            return ids;
        }

        /// <summary>An outdoor scene from the real pair: a meadow with a winding dirt path, a pond, trees round it, rocks and bushes, the
        /// hero on the path and one creature. The ids are picked from the pixels (PickOutdoor); null when the pair lacks them.</summary>
        public static Hd2dDemo Outdoor(DatFile dat, Func<uint, byte[]> sprite, SpriteClassifier cls = null)
        {
            var ids = PickOutdoor(dat, sprite, cls);
            if (ids == null) return null;
            var d = new Hd2dDemo { Dat = dat, Real = true, Ids = ids };
            d.BuildOutdoor(ids);
            return d;
        }

        void BuildOutdoor(OutdoorIds ids)
        {
            World = new World(Dat) { Center = Center, WorldLight = 200 };
            int cx = Center.X, cy = Center.Y, z = Center.Z;
            var ground = new Dictionary<long, int>();
            for (int x = cx - 8; x <= cx + 9; x++)
                for (int y = cy - 6; y <= cy + 7; y++)
                {
                    int id = ids.Grass;
                    int px = cx - 1 + (int)Math.Round(1.5 * Math.Sin(0.7 * (y - cy)));
                    if (x == px || x == px + 1) id = ids.Dirt;
                    double dx = (x - (cx - 4)) / 3.4, dy = (y - (cy + 3)) / 2.4;
                    if (dx * dx + dy * dy <= 1.0) id = ids.Water;
                    ground[Hd2dRuins.Key(x, y)] = id;
                    Add(new Pos(x, y, z), id);
                }
            Func<int, int, bool> grass = (x, y) => ground.TryGetValue(Hd2dRuins.Key(x, y), out var g) && g == ids.Grass;
            // trees (2 x 2 or taller, anchored on the south-east tile) round the edge, never on the path or the water
            foreach (var t in new[] { new[] { -7, -3 }, new[] { -4, -5 }, new[] { 2, -5 }, new[] { 6, -4 }, new[] { 8, 0 }, new[] { 6, 5 }, new[] { 8, 6 }, new[] { -7, 6 }, new[] { -7, 1 }, new[] { 3, 6 } })
                if (grass(cx + t[0], cy + t[1]) && grass(cx + t[0] - 1, cy + t[1])) Add(new Pos(cx + t[0], cy + t[1], z), ids.Tree);
            if (ids.Rock != 0)
                foreach (var r in new[] { new[] { 3, 4 }, new[] { -2, -2 }, new[] { 4, 1 }, new[] { -1, 6 } })
                    if (grass(cx + r[0], cy + r[1])) Add(new Pos(cx + r[0], cy + r[1], z), ids.Rock);
            if (ids.Bush != 0)
                foreach (var b in new[] { new[] { -1, -3 }, new[] { 2, -2 }, new[] { 5, 2 }, new[] { -6, -1 } })
                    if (grass(cx + b[0], cy + b[1])) Add(new Pos(cx + b[0], cy + b[1], z), ids.Bush);
            MakeCreature(1, "Hero", ids.OutfitA, new Pos(cx, cy + 2, z), 3, 215, Dir.North);
            MakeCreature(2, "Wanderer", ids.OutfitB, new Pos(cx + 3, cy - 1, z), 0, 0, Dir.West);
            World.PlayerId = 1;
        }

        void Add(Pos p, int id) { World.AddThing(p, new Thing { Item = World.MakeItem(id, 0) }); }

        /// <summary>The ids the temple room was built with (null for the outdoor demo).</summary>
        public DemoIds Used;

        /// <summary>One creature of the line-up: a class or a monster, and where it stands (tiles from the room's centre).</summary>
        public sealed class CastMember
        {
            public string Name;
            public byte Type;       // 0 player, 1 monster
            public int Vocation;    // a class (vocation id) for a player
            public int Dx, Dy;
        }

        /// <summary>The line-up of the 3D characters (hd2d_3d_cast.png): the front row is one class per class group (Juggernaut, Deadeye, Elementalist,
        /// Ninja, Lich, Shadowfist, Inquisitor: Knight, Rogue, Mage, hooded Rogue, Skeleton_Mage, Barbarian, a holy Knight), the back row is
        /// the four dark monsters (a skeleton warrior, mage, rogue and minion: the summons of the Necromancer's dead).</summary>
        public static readonly CastMember[] Cast =
        {
            new CastMember { Name = "Risen Skeleton", Type = 1, Dx = -3, Dy = -3 },
            new CastMember { Name = "Risen Warrior", Type = 1, Dx = -1, Dy = -3 },
            new CastMember { Name = "Risen Mage", Type = 1, Dx = 1, Dy = -3 },
            new CastMember { Name = "Risen Archer", Type = 1, Dx = 3, Dy = -3 },
            new CastMember { Name = "Juggernaut", Vocation = 8, Dx = -6, Dy = 4 },
            new CastMember { Name = "Deadeye", Vocation = 7, Dx = -4, Dy = 4 },
            new CastMember { Name = "Elementalist", Vocation = 5, Dx = -2, Dy = 4 },
            new CastMember { Name = "Ninja", Vocation = 12, Dx = 0, Dy = 4 },
            new CastMember { Name = "Lich", Vocation = 21, Dx = 2, Dy = 4 },
            new CastMember { Name = "Shadowfist", Vocation = 18, Dx = 4, Dy = 4 },
            new CastMember { Name = "Inquisitor", Vocation = 24, Dx = 6, Dy = 4 },
        };

        /// <summary>Replaces the room's creatures by the cast and puts a torch at each end of both rows, so the torches light them. Needs a room built by
        /// Synthetic() or FromPair(). Returns the cast's creatures in order of Cast; they face the camera (south).</summary>
        public List<Creature> Lineup()
        {
            var made = new List<Creature>();
            if (Used == null || World == null) return made;
            foreach (var t in World.Tiles.Values) t.Things.RemoveAll(th => th.IsCreature);
            World.Creatures.Clear();
            int cx = Center.X, cy = Center.Y, z = Center.Z;
            foreach (var at in new[] { new[] { -7, 4 }, new[] { 7, 4 }, new[] { -5, -3 }, new[] { 5, -3 } })
                Add(new Pos(cx + at[0], cy + at[1], z), Used.Torch);
            uint id = 100;
            foreach (var m in Cast)
            {
                var c = new Creature
                {
                    Id = id++, Name = m.Name, Type = m.Type, Vocation = m.Vocation, Direction = Dir.South,
                    Outfit = new Outfit(Used.OutfitA, 78, 69, 58, 76),
                };
                World.Creatures[c.Id] = c;
                World.AddThing(new Pos(cx + m.Dx, cy + m.Dy, z), new Thing { Creature = c });
                made.Add(c);
            }
            World.PlayerId = made.Count > 0 ? made[made.Count / 2 + 2].Id : 0;   // somebody of the front row is "the player": no effect on the models
            return made;
        }

        void Build(DemoIds ids)
        {
            Used = ids;
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
